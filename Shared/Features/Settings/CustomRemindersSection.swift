import SwiftUI
import TrueFocusKit

/// "Your own words": a line of your own for each moment TrueFocus speaks up, in place of the
/// tone's. Sits under the tone picker. Saved into `TFSettings.customReminders`, so the
/// iPhone, the Mac, the shields and the browser extension all use it.
struct CustomRemindersSection: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        SettingsSection("Your own words",
                        footnote: "Write {task} where the task's name should go. Up to \(CustomReminders.titleLimit) characters becomes the title over the built-in message; anything longer becomes the message under the tone's title. Clear a line to go back to the built-in one.") {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(ReminderMoment.allCases, id: \.self) { moment in
                    CustomReminderRow(moment: moment)
                }
            }
            if !controller.settings.customReminders.isEmpty {
                Button("Reset all to built-in lines") {
                    TFHaptics.tap()
                    controller.updateSettings { $0.customReminders = CustomReminders() }
                }
                .buttonStyle(QuietButtonStyle())
                .fixedSize()
            }
        }
    }
}

/// One moment: its name, a field with the tone's line as the placeholder, a clear button,
/// and a live preview of what will show up.
private struct CustomReminderRow: View {
    @Environment(FocusController.self) private var controller
    let moment: ReminderMoment

    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    /// The task named in placeholders and previews.
    private static let sampleTask = "Investor update"

    private var stored: String? { controller.settings.customReminders[moment] }
    private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let builtIn = Copy(tone: controller.settings.tone).sample(moment, task: Self.sampleTask)

        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.label).font(.body).foregroundStyle(TF.Palette.ink)
                Text(moment.detail)
                    .font(.footnote)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 0) {
                TextField(moment.label, text: $draft, prompt: Text(builtIn.title).foregroundStyle(TF.Palette.ink3))
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(TF.Palette.ink)
                    .focused($focused)
                    #if os(iOS)
                    .submitLabel(.done)
                    #endif
                    .onSubmit(commit)
                    .padding(.leading, 14)
                    .padding(.trailing, hasText ? 0 : 14)
                    .frame(minHeight: 44)
                if hasText {
                    Button {
                        TFHaptics.tap()
                        reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(TF.Palette.ink3)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use the built-in line for \(moment.label)")
                }
            }
            .background(RoundedRectangle(cornerRadius: TF.Radius.control).fill(TF.Palette.surface2))

            if hasText || focused {
                preview
            }
        }
        .onAppear { draft = stored ?? "" }
        .onChange(of: draft) { _, text in
            if text.count > CustomReminders.maxLength {
                draft = String(text.prefix(CustomReminders.maxLength))
            } else {
                scheduleSave()
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onChange(of: stored) { _, value in
            // Changed elsewhere (another device, or "Reset all") while you weren't typing here.
            if !focused { draft = value ?? "" }
        }
        .onDisappear(perform: commit)
    }

    /// What the reminder will look like, with your words as you type them.
    private var preview: some View {
        var custom = controller.settings.customReminders
        custom[moment] = draft
        let line = Copy(tone: controller.settings.tone, custom: custom).sample(moment, task: Self.sampleTask)
        return VStack(alignment: .leading, spacing: 3) {
            Text(line.title).font(.headline).foregroundStyle(TF.Palette.ink)
            Text(line.body).font(.subheadline).foregroundStyle(TF.Palette.ink2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TF.Radius.control).strokeBorder(TF.Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(line.title). \(line.body)")
    }

    // MARK: Saving

    /// Save shortly after typing stops, so the nudges and your other devices pick it up
    /// without a write on every keystroke.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        saveTask?.cancel()
        saveTask = nil
        var next = controller.settings.customReminders
        next[moment] = draft
        guard next != controller.settings.customReminders else { return }
        controller.updateSettings { $0.customReminders[moment] = draft }
    }

    private func reset() {
        draft = ""
        commit()
    }
}
