import FamilyControls
import ManagedSettings
import SwiftUI
import TrueFocusKit

// Building blocks for the Guard tab. Rows sit directly on paper, divided by hairlines —
// no grouped-table boxes.

/// An eyebrow label and its rows.
struct GuardSection<Content: View>: View {
    var title: String
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).tfEyebrowStyle()
                .padding(.bottom, TF.Space.m)
            Hairline()
            content
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(TF.Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TF.Space.m)
            }
        }
        .padding(.top, TF.Space.huge)
    }
}

/// "Boot me out after   −  5 min  +"
struct GuardStepper: View {
    var title: String
    var caption: String?
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var unit: String = "min"

    var body: some View {
        HStack(alignment: .center, spacing: TF.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(TF.Palette.ink)
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(TF.Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: TF.Space.s)
            HStack(spacing: TF.Space.s) {
                stepButton("minus", enabled: value - step >= range.lowerBound) {
                    value = max(range.lowerBound, value - step)
                }
                VStack(spacing: 0) {
                    Text("\(value)")
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(TF.Palette.ink)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(TF.Palette.ink3)
                }
                .frame(minWidth: 44)
                stepButton("plus", enabled: value + step <= range.upperBound) {
                    value = min(range.upperBound, value + step)
                }
            }
        }
        .padding(.vertical, TF.Space.l)
        .animation(TF.Motion.snappy, value: value)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            TFHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? TF.Palette.ink : TF.Palette.ink3)
                .frame(width: 34, height: 34)
                .background(Circle().strokeBorder(TF.Palette.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A switch row.
struct GuardToggleRow: View {
    var title: String
    var caption: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body).foregroundStyle(TF.Palette.ink)
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(TF.Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(TF.Palette.signal)
        .padding(.vertical, TF.Space.l)
    }
}

/// The apps, categories and sites in a selection, as a row of overlapping icons.
struct TokenStrip: View {
    var selection: FamilyActivitySelection
    var limit = 6

    var body: some View {
        let apps = Array(selection.applicationTokens)
        let categories = Array(selection.categoryTokens)
        let sites = Array(selection.webDomainTokens)
        let total = apps.count + categories.count + sites.count
        let shownApps = Array(apps.prefix(limit))
        let shownCategories = Array(categories.prefix(max(0, limit - shownApps.count)))
        let shownSites = Array(sites.prefix(max(0, limit - shownApps.count - shownCategories.count)))
        let shown = shownApps.count + shownCategories.count + shownSites.count

        HStack(spacing: -8) {
            ForEach(shownApps, id: \.self) { token in
                tokenIcon { Label(token).labelStyle(.iconOnly) }
            }
            ForEach(shownCategories, id: \.self) { token in
                tokenIcon { Label(token).labelStyle(.iconOnly) }
            }
            ForEach(shownSites, id: \.self) { token in
                tokenIcon { Label(token).labelStyle(.iconOnly) }
            }
            if total > shown {
                Text("+\(total - shown)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(TF.Palette.ink2)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(TF.Palette.surface2))
                    .overlay(Circle().strokeBorder(TF.Palette.paper, lineWidth: 2))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(total == 0 ? "Nothing selected" : "\(total) selected")
    }

    private func tokenIcon<Icon: View>(@ViewBuilder _ icon: () -> Icon) -> some View {
        icon()
            .font(.system(size: 20))
            .frame(width: 32, height: 32)
            .background(Circle().fill(TF.Palette.surface))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(TF.Palette.paper, lineWidth: 2))
    }
}

/// "Scroll apps   [icons]   Choose"
struct SelectionRow: View {
    var title: String
    var caption: String
    var selection: FamilyActivitySelection
    var enabled: Bool
    var choose: () -> Void

    private var isEmpty: Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TF.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(TF.Palette.ink)
                Spacer()
                Button(isEmpty ? "Choose" : "Edit", action: choose)
                    .buttonStyle(QuietButtonStyle())
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(TF.Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if !isEmpty {
                TokenStrip(selection: selection)
            }
        }
        .padding(.vertical, TF.Space.l)
    }
}

/// A numbered, expandable setup guide.
struct GuideRow: View {
    var number: Int
    var title: String
    var summary: String
    var steps: [String]
    var actionTitle: String?
    var action: (() -> Void)?
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(TF.Motion.soft) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: TF.Space.m) {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(TF.Palette.ink2)
                        .frame(width: 22, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.body).foregroundStyle(TF.Palette.ink)
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(TF.Palette.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: TF.Space.s)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TF.Palette.ink3)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, TF.Space.l)

            if expanded {
                VStack(alignment: .leading, spacing: TF.Space.s) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: TF.Space.s) {
                            Text("\(index + 1).")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(TF.Palette.ink3)
                            Text(step)
                                .font(.callout)
                                .foregroundStyle(TF.Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(QuietButtonStyle())
                            .padding(.top, TF.Space.s)
                    }
                }
                .padding(.leading, 22 + TF.Space.m)
                .padding(.bottom, TF.Space.l)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
