import FamilyControls
import SwiftUI
import TrueFocusKit
import UIKit

/// The Guard tab: what gets shielded, how much scrolling is allowed, the adult filter,
/// and the few one-time switches iOS needs you to flip yourself.
struct GuardView: View {
    @Environment(FocusController.self) private var focus

    @State private var pickingScroll = false
    @State private var pickingReply = false
    @State private var scrollDraft = FamilyActivitySelection()
    @State private var replyDraft = FamilyActivitySelection()
    @State private var confirmFilterOff = false
    @State private var expandedGuide: Int?

    private var shield: ScreenTimeGuard { ScreenTimeGuard.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                statusCard
                    .padding(.top, TF.Space.xl)
                if !shield.isAuthorized {
                    accessCard
                        .padding(.top, TF.Space.l)
                }
                shieldedSection
                budgetSection
                adultSection
                setupSection
            }
            .padding(.horizontal, TF.Space.page)
            .padding(.top, TF.Space.l)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .tfPage()
        .familyActivityPicker(isPresented: $pickingScroll, selection: $scrollDraft)
        .onChange(of: pickingScroll) { _, isOpen in
            if !isOpen { shield.setScrollSelection(scrollDraft) }
        }
        .onChange(of: pickingReply) { _, isOpen in
            if !isOpen { shield.setReplySelection(replyDraft) }
        }
        .confirmationDialog("Turn off the adult filter?", isPresented: $confirmFilterOff, titleVisibility: .visible) {
            Button("Start the \(coolOffHours)-hour cool-off", role: .destructive) {
                shield.requestAdultFilterOff()
            }
            Button("Keep it on", role: .cancel) {}
        } message: {
            Text("It stays on for \(coolOffHours) hours, then turns off. You can cancel any time before then.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TF.Space.s) {
            Text("Guard").tfEyebrowStyle()
            Text("Cut the feed.")
                .font(.tfDisplay)
                .foregroundStyle(TF.Palette.ink)
            Text("Distractions are shielded while you work, budgeted while you don't.")
                .font(.body)
                .foregroundStyle(TF.Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Status

    private enum Status {
        case off, up, budget(Date?), down
    }

    private var status: Status {
        guard shield.isAuthorized else { return .off }
        if shield.config.focusShieldActive { return .up }
        if shield.config.budgetShieldActive { return .budget(shield.config.budgetShieldUntil) }
        return .down
    }

    private var statusCard: some View {
        let snapshot = focus.snapshot
        let settings = focus.settings
        return VStack(alignment: .leading, spacing: TF.Space.l) {
            HStack(spacing: 8) {
                statusDot
                Text(statusEyebrow).tfEyebrowStyle(statusTint)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(statusHeadline)
                    .font(.tfHeadline)
                    .foregroundStyle(TF.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusDetail(snapshot: snapshot))
                    .font(.callout)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Hairline()
            HStack(alignment: .top, spacing: TF.Space.l) {
                StatTile(value: "\(snapshot.bootsToday)", label: "Boot-outs")
                StatTile(value: "\(shield.passesRemaining(settings: settings))", label: "Reply passes")
                StatTile(value: "\(settings.scrollBudgetMinutes)m", label: "Budget")
            }
        }
        .padding(TF.Space.xl)
        .tfCard(tint: shield.config.focusShieldActive ? TF.Palette.signal : nil)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch status {
        case .up: ModeDot(mode: .focus)
        case .budget: Circle().fill(TF.Palette.alarm).frame(width: 8, height: 8)
        case .down: Circle().fill(TF.Palette.rest).frame(width: 8, height: 8)
        case .off: Circle().strokeBorder(TF.Palette.ink3, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }

    private var statusTint: Color {
        switch status {
        case .up: return TF.Palette.signal
        case .budget: return TF.Palette.alarm
        case .down: return TF.Palette.rest
        case .off: return TF.Palette.ink2
        }
    }

    private var statusEyebrow: String {
        switch status {
        case .up: return "Shields up"
        case .budget: return "Locked out"
        case .down: return "Shields down"
        case .off: return "Guard off"
        }
    }

    private var statusHeadline: String {
        switch status {
        case .up: return "Feeds are out of reach."
        case .budget: return "Scroll budget spent."
        case .down: return shield.config.hasSelection ? "On a budget." : "Nothing to guard yet."
        case .off: return "Give TrueFocus the keys."
        }
    }

    private func statusDetail(snapshot: LiveSnapshot) -> String {
        switch status {
        case .up:
            if let task = snapshot.taskTitle, snapshot.mode.isWorking {
                return "Shielded until you finish “\(task)”. They come back for your rest."
            }
            return "Your Focus is on, so the shields are too."
        case .budget(let until):
            if let until, until > Date() {
                return "Back at \(until.formatted(date: .omitted, time: .shortened)). Use the time."
            }
            return "Back shortly. Use the time."
        case .down:
            if shield.config.hasSelection {
                return "\(focus.settings.scrollBudgetMinutes) minutes of scrolling, then a \(focus.settings.scrollCooldownMinutes)-minute lockout. Shields go up the moment you start a task."
            }
            return "Pick the apps that eat your day. They'll be shielded while you work."
        case .off:
            return "Screen Time access lets TrueFocus shield apps and filter the web on this iPhone. Nothing leaves your device."
        }
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: TF.Space.m) {
            Button {
                Task { await shield.requestAuthorization() }
            } label: {
                HStack(spacing: 8) {
                    if shield.isRequesting { ProgressView().tint(TF.Palette.paper) }
                    Text(shield.authorization == .denied ? "Try again" : "Allow Screen Time access")
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.signal, foreground: TF.Palette.onSignal))
            .disabled(shield.isRequesting)

            if let error = shield.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Sections

    private var shieldedSection: some View {
        GuardSection(title: "What gets shielded",
                     footnote: "Reply apps are shielded too, but their shield offers a short pass to answer messages.") {
            SelectionRow(
                title: "Scroll apps",
                caption: "Instagram, YouTube, TikTok, X — whatever you open on autopilot. Whole categories work too.",
                selection: shield.config.scrollSelection,
                enabled: shield.isAuthorized
            ) {
                scrollDraft = shield.config.scrollSelection
                pickingScroll = true
            }
            Hairline()
            SelectionRow(
                title: "Reply apps",
                caption: "Apps you still need for messages. Pick them one by one, not by category.",
                selection: shield.config.replySelection,
                enabled: shield.isAuthorized
            ) {
                replyDraft = shield.config.replySelection
                pickingReply = true
            }
            Hairline()
        }
        // Each picker hangs off its own view: two presentations on one view can clash.
        .familyActivityPicker(isPresented: $pickingReply, selection: $replyDraft)
    }

    private var budgetSection: some View {
        GuardSection(title: "Doom-scroll budget",
                     footnote: "iPhone can't see individual scrolls inside other apps, so the budget is time in them. In Safari, the TrueFocus extension counts every swipe.") {
            GuardToggleRow(title: "Shield during focus",
                           caption: "Scroll and reply apps are blocked while a task is running.",
                           isOn: focus.binding(\.shieldDuringFocus))
            Hairline()
            GuardStepper(title: "Boot me out after",
                         caption: "Minutes of use outside focus.",
                         value: focus.binding(\.scrollBudgetMinutes), range: 1...60)
            Hairline()
            GuardStepper(title: "Lock for",
                         caption: "iOS needs at least 15 minutes.",
                         value: focus.binding(\.scrollCooldownMinutes), range: 15...120, step: 5)
            Hairline()
            GuardStepper(title: "Reply pass",
                         caption: "How long a reply app opens for.",
                         value: focus.binding(\.respondPassMinutes), range: 1...10)
            Hairline()
            GuardStepper(title: "Passes per day",
                         value: focus.binding(\.respondPassesPerDay), range: 0...20, unit: "passes")
            Hairline()
        }
    }

    private var coolOffHours: Int { Int(focus.settings.adultFilterCoolOffHours.rounded()) }

    private var adultSection: some View {
        GuardSection(title: "Adult filter") {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                adultFilterBody(now: context.date)
            }
            Hairline()
        }
    }

    @ViewBuilder
    private func adultFilterBody(now: Date) -> some View {
        let settings = focus.settings
        let active = settings.adultFilterActive(now: now)
        let pendingOff = active && settings.adultFilterOffRequestedAt != nil

        VStack(alignment: .leading, spacing: TF.Space.m) {
            HStack(spacing: 8) {
                Circle()
                    .fill(active ? (pendingOff ? TF.Palette.alarm : TF.Palette.rest) : TF.Palette.ink3)
                    .frame(width: 8, height: 8)
                Text(active ? (pendingOff ? "On · turning off" : "On") : "Off")
                    .tfEyebrowStyle(active ? (pendingOff ? TF.Palette.alarm : TF.Palette.rest) : TF.Palette.ink2)
            }
            Text(active ? "Adult sites are blocked on this iPhone." : "Adult sites aren't filtered.")
                .font(.tfTitle)
                .foregroundStyle(TF.Palette.ink)
            Text("Covers Safari and every app that shows web pages: Apple's automatic filter plus TrueFocus's own list. Turning it off waits \(coolOffHours) hours, so the decision is never made in a weak moment.")
                .font(.footnote)
                .foregroundStyle(TF.Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if !shield.isAuthorized {
                Text("Needs Screen Time access.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TF.Palette.signal)
            } else if pendingOff, let end = settings.adultFilterOffEffectiveAt {
                Text("Turns off \(end.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(TF.Palette.ink)
                Button("Keep it on") { shield.keepAdultFilterOn() }
                    .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.ink, foreground: TF.Palette.paper))
            } else if active {
                Button("Turn off…") { confirmFilterOff = true }
                    .buttonStyle(QuietButtonStyle(foreground: TF.Palette.ink2))
            } else {
                Button("Turn it back on") { shield.keepAdultFilterOn() }
                    .buttonStyle(PrimaryButtonStyle(tint: TF.Palette.ink, foreground: TF.Palette.paper))
            }
        }
        .padding(.vertical, TF.Space.l)
    }

    private var setupSection: some View {
        GuardSection(title: "Finish setup",
                     footnote: "These live in iOS Settings, so only you can flip them.") {
            guide(1,
                  title: "Turn on the Safari extension",
                  summary: "Strips Reels and Shorts, counts your swipes, boots you out of doom-scrolls.",
                  steps: [
                    "Open Settings ▸ Apps ▸ Safari ▸ Extensions.",
                    "Tap TrueFocus and switch it on.",
                    "Set All Websites to Allow.",
                  ])
            Hairline()
            guide(2,
                  title: "Link your Focus",
                  summary: "One switch silences notifications on iPhone and Mac and raises the shields.",
                  steps: [
                    "Open Settings ▸ Focus ▸ Work (or make a “Deep Work” Focus).",
                    "Under Focus Filters, tap Add Filter ▸ TrueFocus and turn on Deep Work shields.",
                    "Allow notifications only from TrueFocus and the people who matter.",
                    "Back in Focus, turn on Share Across Devices.",
                  ])
            Hairline()
            guide(3,
                  title: "Instagram without the feed",
                  summary: "Answer DMs without falling into Reels.",
                  steps: [
                    "Instagram's app can't have Reels removed, so keep it in your scroll apps.",
                    "For messages, use instagram.com in Safari: with the extension on it opens straight to your inbox, with Reels and Explore gone.",
                    "Or add Instagram as a reply app and use the shield's Reply pass.",
                  ],
                  opensSettings: false)
            Hairline()
            guide(4,
                  title: "Run ads, skip the feed",
                  summary: "Ads Manager and Business Suite stay open while Facebook and Instagram are blocked.",
                  steps: [
                    "Shield the Facebook and Instagram apps. Leave Meta Business Suite and Ads Manager out of your scroll apps.",
                    "Don't add facebook.com or instagram.com as websites here: Screen Time would block business.facebook.com with them.",
                    "In Safari the extension already closes the feeds and leaves Ads Manager, Business Suite and the Ad Library alone.",
                  ],
                  opensSettings: false)
            Hairline()
            guide(5,
                  title: "Add Apple's own adult filter",
                  summary: "A second wall that works even without TrueFocus.",
                  steps: [
                    "Open Settings ▸ Screen Time ▸ Content & Privacy Restrictions and switch it on.",
                    "Tap App Store, Media, Web & Games ▸ Web Content.",
                    "Choose Limit Adult Websites.",
                  ])
            Hairline()
        }
    }

    private func guide(_ number: Int, title: String, summary: String, steps: [String], opensSettings: Bool = true) -> some View {
        GuideRow(
            number: number,
            title: title,
            summary: summary,
            steps: steps,
            actionTitle: opensSettings ? "Open Settings" : nil,
            action: opensSettings ? { openSettings() } : nil,
            expanded: Binding(
                get: { expandedGuide == number },
                set: { expandedGuide = $0 ? number : nil }
            )
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
