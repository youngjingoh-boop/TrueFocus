import SwiftUI
import TrueFocusKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The note editor surface: a native text view on a TextKit 1 stack, so typing,
/// selection, autocorrect, dictation and undo all behave exactly like Apple Notes.
///
/// `markup` is the note's stored body. The view reloads it only when it changes from the
/// outside (another device, or switching notes) and the user isn't typing.
#if os(iOS)
struct NoteTextView: UIViewRepresentable {
    var noteID: UUID
    var markup: String
    var handle: NoteEditorHandle
    var autofocus: Bool = false
    var onChange: (String) -> Void

    func makeCoordinator() -> NoteTextCoordinator { NoteTextCoordinator() }

    func makeUIView(context: Context) -> UITextView {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        let textView = coordinator.makeTextView()
        coordinator.load(markup, noteID: noteID)
        handle.engine = coordinator.engine
        if autofocus {
            Task { @MainActor in textView.becomeFirstResponder() }
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        handle.engine = coordinator.engine
        let engine = coordinator.engine
        if coordinator.noteID != noteID {
            coordinator.load(markup, noteID: noteID)
        } else if markup != engine.lastSerialized, markup != engine.loadedMarkup, !textView.isFirstResponder {
            coordinator.load(markup, noteID: noteID)
        }
    }
}

@MainActor
final class NoteTextCoordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    let engine = NoteEditorEngine()
    weak var textView: UITextView?
    var onChange: (String) -> Void = { _ in }
    private(set) var noteID: UUID?
    private weak var markerTap: UITapGestureRecognizer?

    func makeTextView() -> UITextView {
        let textView = UITextView(frame: .zero, textContainer: engine.textContainer)
        textView.backgroundColor = .clear
        textView.font = NoteFormatter.bodyFont
        textView.textColor = NoteFormatter.primaryColor
        // Apple Notes margins: text starts ~20pt from the edge.
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 15, bottom: 160, right: 15)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.allowsEditingTextAttributes = false
        textView.adjustsFontForContentSizeCategory = false
        textView.tintColor = UIColor(tfHex: 0xFF5A1F)
        textView.delegate = self
        textView.inputAccessoryView = makeAccessoryBar()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMarkerTap(_:)))
        tap.delegate = self
        textView.addGestureRecognizer(tap)
        markerTap = tap
        self.textView = textView
        wire(textView)
        NotificationCenter.default.addObserver(self, selector: #selector(textScaleChanged),
                                               name: .tfNoteTextScaleChanged, object: nil)
        return textView
    }

    @objc private func textScaleChanged() {
        textView?.font = NoteFormatter.bodyFont
        engine.reloadForTextScale()
    }

    private func wire(_ textView: UITextView) {
        engine.selectedRange = { [weak textView] in textView?.selectedRange ?? NSRange(location: 0, length: 0) }
        engine.setSelectedRange = { [weak textView] range in textView?.selectedRange = range }
        engine.setTypingAttributes = { [weak textView] attributes in textView?.typingAttributes = attributes }
        engine.hasMarkedText = { [weak textView] in textView?.markedTextRange != nil }
        engine.replaceCharacters = { [weak textView] range, text in
            guard let textView,
                  let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            textView.replace(textRange, withText: text)
        }
        engine.redraw = { [weak self, weak textView] in
            guard let self, let textView else { return }
            let length = self.engine.storage.length
            if length > 0 {
                self.engine.layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: length - 1, length: 1))
            }
            textView.setNeedsDisplay()
            for subview in textView.subviews { subview.setNeedsDisplay() }
        }
        engine.onChange = { [weak self] markup in self?.onChange(markup) }
    }

    func load(_ markup: String, noteID: UUID) {
        self.noteID = noteID
        engine.load(markup)
        if engine.storage.length == 0 {
            textView?.typingAttributes = NoteFormatter.attributes(for: .title)
        }
    }

    private func makeAccessoryBar() -> UIView {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let format = UIBarButtonItem(image: UIImage(systemName: "textformat"), menu: makeFormatMenu())
        bar.items = [
            format,
            UIBarButtonItem(image: UIImage(systemName: "checklist"), style: .plain,
                            target: self, action: #selector(toggleChecklist)),
            UIBarButtonItem(image: UIImage(systemName: "decrease.indent"), style: .plain,
                            target: self, action: #selector(outdent)),
            UIBarButtonItem(image: UIImage(systemName: "increase.indent"), style: .plain,
                            target: self, action: #selector(indent)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), style: .plain,
                            target: self, action: #selector(dismissKeyboard)),
        ]
        bar.tintColor = .label
        bar.sizeToFit()
        return bar
    }

    /// Apple Notes' Aa menu: paragraph styles, lists, and the note text size.
    private func makeFormatMenu() -> UIMenu {
        func style(_ title: String, _ image: String, _ kind: NoteBlockKind) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: image)) { [weak self] _ in self?.engine.applyStyle(kind) }
        }
        let styles = UIMenu(options: .displayInline, children: [
            style("Heading", "textformat.size.larger", .heading),
            style("Subheading", "textformat.size", .subheading),
            style("Body", "text.alignleft", .text),
            style("Monostyled", "chevron.left.forwardslash.chevron.right", .mono),
        ])
        let lists = UIMenu(options: .displayInline, children: [
            style("Bulleted List", "list.bullet", .bullet),
            style("Dashed List", "list.dash", .dashed),
            style("Numbered List", "list.number", .numbered),
            style("Block Quote", "text.quote", .quote),
        ])
        let size = UIMenu(title: "Text Size", image: UIImage(systemName: "textformat.size"), children: [
            UIAction(title: "Larger", image: UIImage(systemName: "plus.magnifyingglass")) { _ in NoteFormatter.stepTextScale(1) },
            UIAction(title: "Smaller", image: UIImage(systemName: "minus.magnifyingglass")) { _ in NoteFormatter.stepTextScale(-1) },
            UIAction(title: "Default Size") { _ in NoteFormatter.stepTextScale(0) },
        ])
        return UIMenu(children: [styles, lists, size])
    }

    @objc private func toggleChecklist() { engine.toggleChecklistForSelection() }
    @objc private func toggleDone() { engine.toggleDoneForSelection() }
    @objc private func indent() { engine.changeIndent(by: 1) }
    @objc private func outdent() { engine.changeIndent(by: -1) }
    @objc private func dismissKeyboard() { textView?.resignFirstResponder() }

    // MARK: UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        engine.shouldChange(range: range, replacement: text)
    }

    func textViewDidChange(_ textView: UITextView) {
        engine.textDidChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        engine.selectionDidChange()
    }

    // MARK: Tapping a circle

    private func containerPoint(for recognizer: UIGestureRecognizer) -> CGPoint {
        guard let textView else { return .zero }
        let point = recognizer.location(in: textView)
        return CGPoint(x: point.x - textView.textContainerInset.left, y: point.y - textView.textContainerInset.top)
    }

    @objc private func handleMarkerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        engine.handleMarkerTap(atContainerPoint: containerPoint(for: recognizer))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === markerTap else { return true }
        return engine.markerParagraph(atContainerPoint: containerPoint(for: gestureRecognizer)) != nil
    }

    /// The text view's own taps wait for ours to fail, so tapping a circle doesn't also
    /// move the caret or raise the keyboard. Off a circle ours fails at once.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === markerTap && otherGestureRecognizer is UITapGestureRecognizer
    }
}

#elseif os(macOS)
struct NoteTextView: NSViewRepresentable {
    var noteID: UUID
    var markup: String
    var handle: NoteEditorHandle
    var autofocus: Bool = false
    var onChange: (String) -> Void

    func makeCoordinator() -> NoteTextCoordinator { NoteTextCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        let scrollView = coordinator.makeScrollView()
        coordinator.load(markup, noteID: noteID)
        handle.engine = coordinator.engine
        if autofocus {
            Task { @MainActor [weak coordinator] in
                guard let textView = coordinator?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        handle.engine = coordinator.engine
        let engine = coordinator.engine
        let isEditing = coordinator.textView.map { $0.window?.firstResponder === $0 } ?? false
        if coordinator.noteID != noteID {
            coordinator.load(markup, noteID: noteID)
        } else if markup != engine.lastSerialized, markup != engine.loadedMarkup, !isEditing {
            coordinator.load(markup, noteID: noteID)
        }
    }
}

/// NSTextView that toggles checklist circles on click, indents on Tab, and pastes as plain text.
final class NoteNSTextView: NSTextView {
    var markerClick: ((NSPoint) -> Bool)?
    /// Tab (+1) and Shift-Tab (-1). Returns true when it changed the indent.
    var indentKey: ((Int) -> Bool)?

    override func insertTab(_ sender: Any?) {
        if let indentKey, indentKey(1) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if let indentKey, indentKey(-1) { return }
        super.insertBacktab(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        if let markerClick, markerClick(containerPoint) { return }
        super.mouseDown(with: event)
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}

@MainActor
final class NoteTextCoordinator: NSObject, NSTextViewDelegate {
    let engine = NoteEditorEngine()
    weak var textView: NoteNSTextView?
    var onChange: (String) -> Void = { _ in }
    private(set) var noteID: UUID?

    func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Starts at zero width and grows with the clip view (autoresizing adds the delta).
        let textView = NoteNSTextView(frame: .zero, textContainer: engine.textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 22, height: 18)
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.insertionPointColor = NSColor(tfHex: 0xFF5A1F)
        textView.font = NoteFormatter.bodyFont
        textView.delegate = self
        textView.markerClick = { [weak self] point in
            self?.engine.handleMarkerTap(atContainerPoint: point) ?? false
        }
        textView.indentKey = { [weak self] delta in
            guard let engine = self?.engine else { return false }
            if delta > 0 && !engine.tabIndents() { return false }
            return engine.changeIndent(by: delta) || delta < 0
        }

        scrollView.documentView = textView
        self.textView = textView
        wire(textView)
        NotificationCenter.default.addObserver(self, selector: #selector(textScaleChanged),
                                               name: .tfNoteTextScaleChanged, object: nil)
        return scrollView
    }

    @objc private func textScaleChanged() {
        textView?.font = NoteFormatter.bodyFont
        engine.reloadForTextScale()
    }

    private func wire(_ textView: NoteNSTextView) {
        engine.selectedRange = { [weak textView] in textView?.selectedRange() ?? NSRange(location: 0, length: 0) }
        engine.setSelectedRange = { [weak textView] range in textView?.setSelectedRange(range) }
        engine.setTypingAttributes = { [weak textView] attributes in textView?.typingAttributes = attributes }
        engine.hasMarkedText = { [weak textView] in textView?.hasMarkedText() ?? false }
        engine.replaceCharacters = { [weak textView] range, text in
            guard let textView, let storage = textView.textStorage else { return }
            if textView.shouldChangeText(in: range, replacementString: text) {
                storage.replaceCharacters(in: range, with: text)
                textView.didChangeText()
            }
        }
        engine.redraw = { [weak textView] in
            guard let textView else { return }
            textView.setNeedsDisplay(textView.bounds)
        }
        engine.onChange = { [weak self] markup in self?.onChange(markup) }
    }

    func load(_ markup: String, noteID: UUID) {
        self.noteID = noteID
        engine.load(markup)
        if engine.storage.length == 0 {
            textView?.typingAttributes = NoteFormatter.attributes(for: .title)
        }
    }

    // MARK: NSTextViewDelegate

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString else { return true }
        return engine.shouldChange(range: affectedCharRange, replacement: replacementString)
    }

    func textDidChange(_ notification: Notification) {
        engine.textDidChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        engine.selectionDidChange()
    }
}
#endif
