import SwiftData
import SwiftUI
import TrueFocusKit

/// The main window: a slim top bar over Today / Notes / Review, with the immersive
/// focus screen taking over the whole window while you work.
struct MacRootView: View {
    @Environment(FocusController.self) private var controller
    @Environment(MacUIState.self) private var ui
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                MacTopBar()
                Hairline()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(controller.isFocusScreenPresented ? 0 : 1)
            .allowsHitTesting(!controller.isFocusScreenPresented)

            if controller.isFocusScreenPresented {
                FocusScreen()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(2)
            }

            if ui.showQuickAdd && !controller.isFocusScreenPresented {
                QuickAddOverlay()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(3)
            }
        }
        .animation(TF.Motion.soft, value: controller.isFocusScreenPresented)
        .animation(TF.Motion.snappy, value: ui.showQuickAdd)
        .frame(minWidth: 760, minHeight: 560)
        .tfPage()
        .onAppear { WindowOpener.shared.openWindow = openWindow }
        .onOpenURL { url in MacURLRouter.handle(url) }
    }

    @ViewBuilder
    private var content: some View {
        switch ui.section {
        case .today:
            TodayView()
        case .notes:
            NotesHomeView()
        case .review:
            ReviewView(isSheet: false)
        }
    }
}

// MARK: - Top bar

private struct MacTopBar: View {
    @Environment(FocusController.self) private var controller
    @Environment(MacUIState.self) private var ui
    @Namespace private var segment

    var body: some View {
        HStack(spacing: 16) {
            // Room for the traffic lights of the hidden title bar.
            Color.clear.frame(width: 64, height: 1)

            Text(TFFormat.dayEyebrow(Date())).tfEyebrowStyle()

            Spacer(minLength: 12)

            segmented

            Spacer(minLength: 12)

            nowPill

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TF.Palette.ink2)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(MacSection.allCases) { section in
                let selected = ui.section == section
                Button {
                    withAnimation(TF.Motion.snappy) { ui.section = section }
                } label: {
                    Text(section.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? TF.Palette.ink : TF.Palette.ink2)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(TF.Palette.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "segment", in: segment)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(TF.Palette.surface2))
    }

    /// What's running, at a glance. Click to enter the focus screen.
    @ViewBuilder
    private var nowPill: some View {
        let snapshot = controller.snapshot
        if snapshot.mode.isActive {
            Button {
                controller.isFocusScreenPresented = true
            } label: {
                HStack(spacing: 8) {
                    ModeDot(mode: snapshot.mode)
                    Text(TFFormat.truncate(snapshot.headline ?? snapshot.mode.label, to: 28))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(TF.Palette.ink)
                        .lineLimit(1)
                    if let start = snapshot.modeStartedAt {
                        if snapshot.mode == .rest, let end = snapshot.plannedRestEnd {
                            CountdownText(until: end)
                                .foregroundStyle(TF.Palette.ink2)
                        } else {
                            ElapsedText(since: start, base: snapshot.mode == .focus ? snapshot.taskFocusBefore : 0)
                                .foregroundStyle(TF.Palette.ink2)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(TF.tint(for: snapshot.mode).opacity(0.10)))
                .overlay(Capsule().strokeBorder(TF.tint(for: snapshot.mode).opacity(0.25), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open the focus screen (⇧⌘F)")
        }
    }
}

// MARK: - Quick add (⌘N)

/// A Spotlight-style capture bar. Return adds and keeps it open for the next one; Esc closes.
private struct QuickAddOverlay: View {
    @Environment(FocusController.self) private var controller
    @Environment(MacUIState.self) private var ui
    @State private var text = ""
    @State private var added = 0
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TF.Palette.signal)
                    TextField("New task", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(TF.Palette.ink)
                        .focused($focused)
                        .onSubmit(add)
                        .onExitCommand(perform: close)
                }
                .padding(.horizontal, 22)
                .frame(width: 580, height: 64)
                .tfGlass(cornerRadius: 20)
                .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 16)

                Text(added == 0 ? "Return to add · Esc to close" : "Added \(added) · keep going, or Esc")
                    .font(.tfCaption)
                    .foregroundStyle(TF.Palette.ink2)
            }
            .padding(.top, 96)
        }
        .onAppear { focused = true }
    }

    private func add() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            close()
            return
        }
        controller.addTask(title)
        added += 1
        text = ""
        focused = true
    }

    private func close() {
        ui.showQuickAdd = false
    }
}
