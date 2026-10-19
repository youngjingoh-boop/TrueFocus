import AppKit
import SwiftUI
import TrueFocusKit

/// The drift guard's nudge: a small card under the menu bar. It never blocks or steals focus;
/// it names where you are and offers three ways back.
@MainActor
final class DriftPanel {
    static let shared = DriftPanel()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    var isShowing: Bool { panel?.isVisible == true }

    func show(title: String, message: String, breadcrumb: String?,
              onBack: @escaping () -> Void, onPartOfTask: @escaping () -> Void, onSwitch: @escaping () -> Void) {
        let view = DriftCard(title: title, message: message, breadcrumb: breadcrumb,
                             onBack: { [weak self] in self?.dismiss(); onBack() },
                             onPartOfTask: { [weak self] in self?.dismiss(); onPartOfTask() },
                             onSwitch: { [weak self] in self?.dismiss(); onSwitch() },
                             onClose: { [weak self] in self?.dismiss() })
        let hosting = FirstClickHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.maxX - size.width - 12, y: frame.maxY - size.height - 8)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }

        // It stays a while, then steps aside; the guard asks again later if you're still away.
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }
}

/// The panel never becomes key (it must not take the keyboard from what you're typing in),
/// so its buttons have to answer the very first click.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct DriftCard: View {
    let title: String
    let message: String
    let breadcrumb: String?
    let onBack: () -> Void
    let onPartOfTask: () -> Void
    let onSwitch: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ModeDot(mode: .focus, size: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TF.Palette.ink)
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(TF.Palette.ink2)
                    if let breadcrumb, !breadcrumb.isEmpty {
                        Text("↳ \(breadcrumb)")
                            .font(.system(size: 12))
                            .foregroundStyle(TF.Palette.ink2)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TF.Palette.ink2)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            HStack(spacing: 8) {
                Button("Back to it", action: onBack)
                    .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: .black))
                    .keyboardShortcut(.defaultAction)
                Button("Part of the task", action: onPartOfTask)
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
                Button("Switch task", action: onSwitch)
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(TF.Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .padding(12)
    }
}
