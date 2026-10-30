import Foundation
import TrueFocusKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Platform-neutral editing behaviour for the note editor: it owns the TextKit 1 stack and
/// implements the Apple Notes rules (checklists continue on Return, end on an empty Return,
/// lose their circle on Backspace at the start, "[] " converts a line…). The UIKit and AppKit
/// coordinators only wire their text view into the closures below.
@MainActor
final class NoteEditorEngine {
    let storage = NSTextStorage()
    let layoutManager = NoteLayoutManager()
    let textContainer: NSTextContainer

    // Wired by the platform coordinator.
    var selectedRange: () -> NSRange = { NSRange(location: 0, length: 0) }
    var setSelectedRange: (NSRange) -> Void = { _ in }
    var setTypingAttributes: ([NSAttributedString.Key: Any]) -> Void = { _ in }
    /// Undo-aware character replacement through the text view.
    var replaceCharacters: (NSRange, String) -> Void = { _, _ in }
    var hasMarkedText: () -> Bool = { false }
    /// Redraws regions the text system doesn't know changed (the empty last line's marker).
    var redraw: () -> Void = {}
    var onChange: (String) -> Void = { _ in }

    /// The markup last handed to `onChange` (or loaded).
    private(set) var lastSerialized = ""
    /// The markup passed to the last `load`, before normalization.
    private(set) var loadedMarkup = ""

    private var pendingEdited: NSRange?
    private var pendingNewItem: (location: Int, kind: NoteBlockKind, indent: Int)?
    private var pendingShortcut: (location: Int, text: String, kind: NoteBlockKind)?
    private var isInternalEdit = false

    // TextKit forbids layout while the text storage is mid-edit (between beginEditing and
    // endEditing): it throws, and the app quits. Setting the text view's typing attributes or
    // redrawing does layout, so inside an edit those wait until the outermost edit ends.
    private var editDepth = 0
    private var needsTypingRefresh = false
    private var needsRedraw = false

    init() {
        textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
    }

    // MARK: Loading and saving

    func load(_ markup: String) {
        let built = NoteFormatter.attributedString(from: markup)
        storage.setAttributedString(built.text)
        layoutManager.extraLineKind = built.trailing?.kind
        layoutManager.extraLineIndent = built.trailing?.indent ?? 0
        loadedMarkup = markup
        lastSerialized = serialize()
        pendingEdited = nil
        pendingNewItem = nil
        pendingShortcut = nil
        selectionDidChange()
        redraw()
    }

    func serialize() -> String {
        NoteFormatter.markup(from: storage, trailingKind: layoutManager.extraLineKind,
                             trailingIndent: layoutManager.extraLineIndent)
    }

    private func notifyChanged() {
        let markup = serialize()
        lastSerialized = markup
        onChange(markup)
    }

    // MARK: Editing transactions

    /// Groups storage changes; typing-attribute and redraw requests made inside run after.
    private func editing(_ changes: () -> Void) {
        editDepth += 1
        storage.beginEditing()
        changes()
        storage.endEditing()
        editDepth -= 1
        if editDepth == 0 { flushDeferred() }
    }

    private func flushDeferred() {
        if needsTypingRefresh {
            needsTypingRefresh = false
            refreshTypingAttributes()
        }
        if needsRedraw {
            needsRedraw = false
            redraw()
        }
    }

    /// Typing attributes follow the paragraph the caret is in.
    private func refreshTypingAttributes() {
        if editDepth > 0 {
            needsTypingRefresh = true
            return
        }
        guard !hasMarkedText() else { return }
        let paragraph = paragraphRange(at: selectedRange().location)
        setTypingAttributes(NoteFormatter.attributes(for: kind(ofParagraph: paragraph), indent: indent(ofParagraph: paragraph)))
    }

    private func requestRedraw() {
        if editDepth > 0 { needsRedraw = true } else { redraw() }
    }

    // MARK: Paragraph helpers

    private var string: NSString { storage.string as NSString }

    private var endsWithTerminator: Bool {
        let length = string.length
        return length > 0 && NoteFormatter.isParagraphTerminator(string.character(at: length - 1))
    }

    /// The paragraph containing `location`. A zero-length range at the very end means the
    /// empty last line after a trailing newline.
    func paragraphRange(at location: Int) -> NSRange {
        let length = string.length
        if length == 0 { return NSRange(location: 0, length: 0) }
        if location >= length {
            if endsWithTerminator { return NSRange(location: length, length: 0) }
            return string.paragraphRange(for: NSRange(location: length - 1, length: 0))
        }
        return string.paragraphRange(for: NSRange(location: max(0, location), length: 0))
    }

    private func contentLength(_ paragraph: NSRange) -> Int {
        guard paragraph.length > 0 else { return 0 }
        let last = string.character(at: NSMaxRange(paragraph) - 1)
        return paragraph.length - (NoteFormatter.isParagraphTerminator(last) ? 1 : 0)
    }

    func kind(ofParagraph paragraph: NSRange) -> NoteBlockKind {
        if paragraph.location == 0 { return .title }
        if paragraph.length == 0 { return layoutManager.extraLineKind ?? .text }
        let found = NoteFormatter.kind(from: storage.attributes(at: paragraph.location, effectiveRange: nil)) ?? .text
        return found == .title ? .text : found
    }

    func indent(ofParagraph paragraph: NSRange) -> Int {
        if paragraph.location == 0 { return 0 }
        if paragraph.length == 0 { return layoutManager.extraLineIndent }
        return NoteFormatter.indent(from: storage.attributes(at: paragraph.location, effectiveRange: nil))
    }

    /// Every paragraph touched by a range (just one for a caret).
    private func paragraphs(in range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        var cursor = range.location
        repeat {
            let paragraph = paragraphRange(at: cursor)
            result.append(paragraph)
            if paragraph.length == 0 { break }
            cursor = NSMaxRange(paragraph)
        } while cursor < NSMaxRange(range)
        return result
    }

    private func caretIsIn(_ paragraph: NSRange) -> Bool {
        let caret = selectedRange().location
        if paragraph.length == 0 { return caret == paragraph.location }
        let content = NSRange(location: paragraph.location, length: contentLength(paragraph))
        return caret >= content.location && caret <= NSMaxRange(content)
    }

    /// Restyles one paragraph as `kind`, keeping its indent unless `indent` is given.
    /// Attributes only, so the selection never moves.
    func setKind(_ kind: NoteBlockKind, paragraph: NSRange, notify: Bool, indent: Int? = nil) {
        let resolved: NoteBlockKind = paragraph.location == 0 ? .title : (kind == .title ? .text : kind)
        let level = min(max(indent ?? self.indent(ofParagraph: paragraph), 0), NoteLine.maxIndent)
        if paragraph.length == 0 {
            layoutManager.extraLineKind = resolved
            layoutManager.extraLineIndent = level
            requestRedraw()
        } else {
            editing {
                storage.setAttributes(NoteFormatter.attributes(for: resolved, indent: level), range: paragraph)
            }
        }
        if caretIsIn(paragraph) { refreshTypingAttributes() }
        if notify { notifyChanged() }
    }

    /// Re-applies each touched paragraph's style uniformly, from its first character.
    private func normalize(_ range: NSRange) {
        guard storage.length > 0 else { return }
        var cursor = min(range.location, storage.length)
        let end = min(NSMaxRange(range), storage.length)
        repeat {
            let paragraph = paragraphRange(at: cursor)
            if paragraph.length == 0 { break }
            storage.setAttributes(NoteFormatter.attributes(for: kind(ofParagraph: paragraph),
                                                           indent: indent(ofParagraph: paragraph)), range: paragraph)
            cursor = NSMaxRange(paragraph)
        } while cursor < end
    }

    /// The first line is always the title; the line after it never is.
    private func normalizeTitle() {
        guard storage.length > 0 else { return }
        let title = paragraphRange(at: 0)
        normalize(title)
        if NSMaxRange(title) < storage.length {
            normalize(NSRange(location: NSMaxRange(title), length: 0))
        }
    }

    // MARK: Text view callbacks

    /// Return value: whether the text view should perform the edit itself.
    func shouldChange(range: NSRange, replacement: String) -> Bool {
        if isInternalEdit { return true }
        let inserted = NSRange(location: range.location, length: (replacement as NSString).length)
        pendingEdited = pendingEdited.map { NSUnionRange($0, inserted) } ?? inserted
        guard !hasMarkedText() else { return true }

        let paragraph = paragraphRange(at: range.location)
        let paragraphKind = self.kind(ofParagraph: paragraph)
        let paragraphIndent = self.indent(ofParagraph: paragraph)
        let continued: NoteBlockKind = paragraphKind == .done ? .todo : paragraphKind

        // Return
        if replacement == "\n" {
            if paragraphKind.isList {
                if contentLength(paragraph) == 0 && range.length == 0 {
                    // Return on an empty item steps it out a level, then ends the list.
                    let location = paragraph.location
                    pendingEdited = nil
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let here = self.paragraphRange(at: location)
                        if paragraphIndent > 0 {
                            self.setKind(paragraphKind, paragraph: here, notify: true, indent: paragraphIndent - 1)
                        } else {
                            self.setKind(.text, paragraph: here, notify: true)
                        }
                    }
                    return false
                }
                if range.location == paragraph.location && range.length == 0 {
                    // Return at the start of an item opens a fresh item above it; this one keeps its state.
                    pendingNewItem = (paragraph.location, continued, paragraphIndent)
                } else {
                    pendingNewItem = (range.location + 1, continued, paragraphIndent)
                }
            } else if paragraphKind == .title || paragraphKind == .heading || paragraphKind == .subheading {
                pendingNewItem = (range.location + 1, NoteBlockKind.text, paragraphIndent)
            } else if paragraphIndent > 0 {
                // Indented text keeps its indent on the next line.
                pendingNewItem = (range.location + 1, paragraphKind, paragraphIndent)
            }
            return true
        }

        // Backspace at the very start of a list item removes its marker.
        let selection = selectedRange()
        if replacement.isEmpty, range.length == 1, selection.length == 0, selection.location == NSMaxRange(range) {
            let caretParagraph = paragraphRange(at: selection.location)
            if caretParagraph.location == selection.location, caretParagraph.location > 0,
               self.kind(ofParagraph: caretParagraph).isList {
                let location = caretParagraph.location
                pendingEdited = nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.setKind(.text, paragraph: self.paragraphRange(at: location), notify: true)
                }
                return false
            }
        }

        // Markdown-style shortcuts typed at the start of a line: "[] ", "- [ ] ", "- ", "# ".
        if replacement == " ", range.length == 0, paragraph.location > 0, paragraph.length > 0,
           range.location > paragraph.location {
            let prefix = string.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
            var target: NoteBlockKind?
            switch prefix {
            case "[]", "[ ]", "- []", "- [ ]", "-[]", "-[ ]": target = .todo
            case "[x]", "[X]", "- [x]", "- [X]": target = .done
            case "-", "*", "•": target = paragraphKind == .text ? .bullet : nil
            case "–", "—": target = paragraphKind == .text ? .dashed : nil
            case "1.", "1)": target = paragraphKind == .text ? .numbered : nil
            case ">": target = paragraphKind == .text ? .quote : nil
            case "#", "##": target = paragraphKind == .text ? .heading : nil
            case "###": target = paragraphKind == .text ? .subheading : nil
            default: target = nil
            }
            if let target {
                pendingShortcut = (paragraph.location, prefix + " ", target)
            }
        }
        return true
    }

    func textDidChange() {
        if hasMarkedText() {
            notifyChanged()
            return
        }
        editing {
            if let edited = pendingEdited {
                normalize(edited)
            } else {
                normalize(NSRange(location: selectedRange().location, length: 0))
            }
            normalizeTitle()
            if let item = pendingNewItem {
                setKind(item.kind, paragraph: paragraphRange(at: item.location), notify: false, indent: item.indent)
            }
        }
        pendingEdited = nil
        pendingNewItem = nil
        if !endsWithTerminator {
            layoutManager.extraLineKind = nil
            layoutManager.extraLineIndent = 0
        }

        if let shortcut = pendingShortcut {
            pendingShortcut = nil
            Task { @MainActor [weak self] in self?.applyShortcut(shortcut) }
        }
        notifyChanged()
    }

    func selectionDidChange() {
        refreshTypingAttributes()
    }

    private func applyShortcut(_ shortcut: (location: Int, text: String, kind: NoteBlockKind)) {
        let range = NSRange(location: shortcut.location, length: (shortcut.text as NSString).length)
        guard NSMaxRange(range) <= string.length, string.substring(with: range) == shortcut.text else { return }
        isInternalEdit = true
        replaceCharacters(range, "")
        isInternalEdit = false
        let paragraph = paragraphRange(at: shortcut.location)
        setKind(shortcut.kind, paragraph: paragraph, notify: false)
        setSelectedRange(NSRange(location: shortcut.location, length: 0))
        setTypingAttributes(NoteFormatter.attributes(for: shortcut.kind, indent: indent(ofParagraph: paragraph)))
        notifyChanged()
    }

    // MARK: Commands

    /// Checklist button: makes the selected lines a checklist, or plain text if they already are.
    func toggleChecklistForSelection() {
        let selection = selectedRange()
        let touched = paragraphs(in: selection).filter { $0.location > 0 }
        guard !touched.isEmpty else {
            addChecklistItemBelowTitle()
            return
        }
        let allChecklist = touched.allSatisfy { kind(ofParagraph: $0).isChecklist }
        editing {
            for paragraph in touched {
                let current = kind(ofParagraph: paragraph)
                let next: NoteBlockKind = allChecklist ? .text : (current == .done ? .done : .todo)
                setKind(next, paragraph: paragraph, notify: false)
            }
        }
        notifyChanged()
    }

    /// "Mark as Checked": flips the selected checklist items.
    func toggleDoneForSelection() {
        let touched = paragraphs(in: selectedRange()).filter { kind(ofParagraph: $0).isChecklist }
        guard !touched.isEmpty else { return }
        editing {
            for paragraph in touched {
                setKind(kind(ofParagraph: paragraph) == .done ? .todo : .done, paragraph: paragraph, notify: false)
            }
        }
        if touched.contains(where: { kind(ofParagraph: $0) == .done }) { TFHaptics.success() } else { TFHaptics.tap() }
        notifyChanged()
    }

    /// A paragraph style from the Aa menu for the selected lines. Choosing the style they all
    /// already have turns them back into body text, like Apple Notes.
    func applyStyle(_ style: NoteBlockKind) {
        let touched = paragraphs(in: selectedRange()).filter { $0.location > 0 }
        guard !touched.isEmpty else { return }
        let target: NoteBlockKind = style == .title ? .heading : style
        let all = touched.allSatisfy { kind(ofParagraph: $0) == target }
        editing {
            for paragraph in touched {
                setKind(all && target != .text ? .text : target, paragraph: paragraph, notify: false)
            }
        }
        notifyChanged()
    }

    /// Indent (+1) or outdent (-1) the selected lines. Returns false when nothing moved.
    @discardableResult
    func changeIndent(by delta: Int) -> Bool {
        let touched = paragraphs(in: selectedRange()).filter { $0.location > 0 }
        var moved = false
        editing {
            for paragraph in touched {
                let current = indent(ofParagraph: paragraph)
                let next = min(max(current + delta, 0), NoteLine.maxIndent)
                guard next != current else { continue }
                setKind(kind(ofParagraph: paragraph), paragraph: paragraph, notify: false, indent: next)
                moved = true
            }
        }
        if moved {
            requestRedraw()
            notifyChanged()
        }
        return moved
    }

    /// Whether Tab should indent rather than type a tab: in a list or an indented line, or at
    /// the very start of a line (a leading tab would read back as an indent anyway).
    func tabIndents() -> Bool {
        let selection = selectedRange()
        let paragraph = paragraphRange(at: selection.location)
        guard paragraph.location > 0 else { return false }
        return selection.length > 0 || kind(ofParagraph: paragraph).isList || indent(ofParagraph: paragraph) > 0
            || selection.location == paragraph.location
    }

    /// Re-lays the note out after the text size changes, keeping the caret where it was.
    func reloadForTextScale() {
        let selection = selectedRange()
        load(serialize())
        setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
    }

    /// With the caret in the title, the checklist button starts a list on the next line.
    private func addChecklistItemBelowTitle() {
        let title = paragraphRange(at: 0)
        let insertAt = title.location + contentLength(title)
        isInternalEdit = true
        replaceCharacters(NSRange(location: insertAt, length: 0), "\n")
        isInternalEdit = false
        normalizeTitle()
        let item = paragraphRange(at: insertAt + 1)
        setSelectedRange(NSRange(location: insertAt + 1, length: 0))
        setKind(.todo, paragraph: item, notify: false)
        notifyChanged()
    }

    // MARK: Tapping the circle

    /// The checklist paragraph whose circle is under a point in text-container coordinates.
    func markerParagraph(atContainerPoint point: CGPoint) -> NSRange? {
        guard storage.length > 0 else { return nil }
        let index = layoutManager.characterIndex(for: point, in: textContainer,
                                                 fractionOfDistanceBetweenInsertionPoints: nil)
        let paragraph = paragraphRange(at: min(index, storage.length - 1))
        guard paragraph.length > 0, kind(ofParagraph: paragraph).isChecklist else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: paragraph.location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = line.minY + layoutManager.location(forGlyphAt: glyph).y
        let marker = NoteLayoutManager.markerRect(lineRect: line, baseline: baseline,
                                                  padding: textContainer.lineFragmentPadding,
                                                  indent: indent(ofParagraph: paragraph))
        // A forgiving target: around the circle, the height of the first line.
        let target = CGRect(x: marker.minX - 8, y: min(line.minY, marker.minY) - 4,
                            width: marker.width + 16, height: max(line.height, marker.height) + 8)
        return target.contains(point) ? paragraph : nil
    }

    /// Toggles the circle under a point. Returns true if it hit one.
    @discardableResult
    func handleMarkerTap(atContainerPoint point: CGPoint) -> Bool {
        guard let paragraph = markerParagraph(atContainerPoint: point) else { return false }
        let next: NoteBlockKind = kind(ofParagraph: paragraph) == .done ? .todo : .done
        setKind(next, paragraph: paragraph, notify: true)
        if next == .done { TFHaptics.success() } else { TFHaptics.tap() }
        return true
    }
}

/// Lets SwiftUI toolbars talk to the live editor.
@MainActor
final class NoteEditorHandle {
    weak var engine: NoteEditorEngine?

    func toggleChecklist() { engine?.toggleChecklistForSelection() }
    func toggleDone() { engine?.toggleDoneForSelection() }
    func applyStyle(_ style: NoteBlockKind) { engine?.applyStyle(style) }
    func indent() { engine?.changeIndent(by: 1) }
    func outdent() { engine?.changeIndent(by: -1) }
    func currentMarkup() -> String? { engine?.serialize() }
}
