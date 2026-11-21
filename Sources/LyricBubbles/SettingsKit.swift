import SwiftUI

// MARK: - Shared settings controls
//
// Every style's settings are built from these, so the panels look and behave the same
// whichever style you open: the same section headings, label sizes, value read-outs, hints,
// switch toggles and small sliders.

/// A section heading inside a settings panel.
struct SettingSection: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Icon + title, the label every control uses.
struct SettingLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
    }
}

/// One line of grey help text under a control.
struct SettingHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A 0…1 slider with a percentage read-out ("Off" at zero when `offAtZero`).
struct SettingSlider: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    var hint: String? = nil
    var offAtZero = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                SettingLabel(title: title, symbol: symbol)
                Spacer()
                Text(offAtZero && value == 0 ? "Off" : "\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...1).controlSize(.small)
            if let hint { SettingHint(hint) }
        }
    }
}

/// A switch on the right, like System Settings.
struct SettingToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                SettingLabel(title: title, symbol: symbol)
                Spacer()
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            if let hint { SettingHint(hint) }
        }
    }
}
