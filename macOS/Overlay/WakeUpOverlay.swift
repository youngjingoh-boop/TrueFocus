import AppKit
import SwiftUI
import TrueFocusKit

/// What the full-screen wake-up overlay says and offers.
struct WakeUpContent {
    var eyebrow: String = "TruFocus"
    var title: String
    var message: String
    /// "Next up" / "You're on"
    var taskLabel: String?
    var task: String?
    var primaryTitle: String
    var primary: @MainActor () -> Void
    var snoozeTitle: String? = "Give me 2 minutes"
    var snooze: (@MainActor () -> Void)? = nil

    /// The obvious next move for the current state: resume, start the next task, or just get out of the way.
    @MainActor
    static func standard(title: String, message: String, snapshot: LiveSnapshot,
                         snooze: (@MainActor () -> Void)? = nil) -> WakeUpContent {
        switch snapshot.mode {
        case .focus:
            return WakeUpContent(title: title, message: message, taskLabel: "You're on", task: snapshot.taskTitle,
                                 primaryTitle: "Back to it", primary: {}, snoozeTitle: nil, snooze: nil)
        case .think:
            return WakeUpContent(title: title, message: message, taskLabel: "You're on", task: snapshot.taskTitle,
                                 primaryTitle: "Back to it", primary: { FocusController.shared.backToIt() },
                                 snooze: snooze)
        case .rest, .idle:
            if let next = snapshot.nextTaskTitle {
                return WakeUpContent(title: title, message: message, taskLabel: "Next up", task: next,
                                     primaryTitle: "Start it", primary: { FocusController.shared.backToIt() },
                                     snooze: snooze)
            }
            return WakeUpContent(title: title, message: message, taskLabel: nil, task: nil,
                                 primaryTitle: "Open TruFocus", primary: { WindowOpener.shared.openMain() },
                                 snooze: snooze)
        }
    }
}

/// A borderless window that can still take keyboard focus (for Escape and the buttons).
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The "Wake up." screen: covers every display until you choose to get back to work.
@MainActor
final class WakeUpOverlay {
    static let shared = WakeUpOverlay()

    private var windows: [NSWindow] = []
    private var keyMonitor: Any?

    var isVisible: Bool { !windows.isEmpty }

    func show(_ content: WakeUpContent) {
        dismiss(animated: false)
        let view = WakeUpView(
            content: content,
            onPrimary: { [weak self] in
                self?.dismiss()
                content.primary()
            },
            onSnooze: { [weak self] in
                self?.dismiss()
                content.snooze?()
            }
        )

        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                       backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                window.animator().alphaValue = 1
            }
            windows.append(window)
        }

        NSApp.activate()
        windows.first?.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Escape
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.dismiss() }
                return nil
            }
            return event
        }
    }

    func dismiss(animated: Bool = true) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        let closing = windows
        windows.removeAll()
        guard !closing.isEmpty else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                for window in closing { window.animator().alphaValue = 0 }
            }, completionHandler: {
                for window in closing { window.orderOut(nil) }
            })
        } else {
            for window in closing { window.orderOut(nil) }
        }
    }
}

private struct WakeUpView: View {
    let content: WakeUpContent
    let onPrimary: @MainActor () -> Void
    let onSnooze: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var glow = false

    var body: some View {
        ZStack {
            TF.Palette.night.opacity(0.97).ignoresSafeArea()

            RadialGradient(colors: [TF.Palette.signal.opacity(glow ? 0.30 : 0.18), .clear],
                           center: .bottom, startRadius: 20, endRadius: 760)
                .ignoresSafeArea()
                // Scoped here so the repeating glow can't loop anything else on screen.
                .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: glow)
                .blendMode(.screen)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(TF.Palette.signal).frame(width: 7, height: 7)
                    Text(content.eyebrow).tfEyebrowStyle(TF.Palette.signal)
                }
                .padding(.bottom, 36)

                Text(content.title)
                    .font(.system(size: 92, weight: .thin))
                    .tracking(-1.5)
                    .foregroundStyle(TF.Palette.nightInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)

                Text(content.message)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(TF.Palette.nightInk2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
                    .padding(.top, 18)

                if let task = content.task, !task.isEmpty {
                    VStack(spacing: 10) {
                        if let label = content.taskLabel {
                            Text(label).tfEyebrowStyle(TF.Palette.nightInk2)
                        }
                        Text(task)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(TF.Palette.nightInk)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 720)
                    }
                    .padding(.top, 56)
                }

                HStack(spacing: 14) {
                    Button(action: onPrimary) {
                        Text(content.primaryTitle)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: .black))
                    .frame(width: 240)
                    .keyboardShortcut(.defaultAction)

                    if let snoozeTitle = content.snoozeTitle {
                        Button(action: onSnooze) {
                            Text(snoozeTitle)
                        }
                        .buttonStyle(QuietButtonStyle(foreground: TF.Palette.nightInk))
                    }
                }
                .padding(.top, 56)

                Text("esc to dismiss")
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.nightInk2.opacity(0.55))
                    .padding(.top, 22)
            }
            .padding(64)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.985)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.5)) { appeared = true }
            // A slow breathing glow, unless motion is reduced.
            guard !reduceMotion else { return }
            glow = true
        }
    }
}

// MARK: - HUD toast

/// A small, non-activating capsule near the top of the screen for gentle nudges.
@MainActor
final class HUDToast {
    static let shared = HUDToast()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(title: String, message: String? = nil, mode: FlowMode = .focus, duration: TimeInterval = 4) {
        let view = HUDToastView(title: title, message: message, mode: mode)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 14)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        self.panel = panel

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }
}

private struct HUDToastView: View {
    let title: String
    let message: String?
    let mode: FlowMode

    var body: some View {
        HStack(spacing: 12) {
            ModeDot(mode: mode == .idle ? .focus : mode, size: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TF.Palette.ink)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(TF.Palette.ink2)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 260, maxWidth: 440, alignment: .leading)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(TF.Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .padding(16)
    }
}
