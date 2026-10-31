import SwiftUI

/// Native click-to-open menus have consistent mouse, trackpad, and keyboard
/// behavior. Scrolling the surrounding panel never edits a closed timer.
struct DurationPicker: View {
    @Binding var minutes: Int
    @Binding var seconds: Int

    var body: some View {
        HStack(spacing: 4) {
            NumberMenuPicker(title: "Timeout minutes", selection: $minutes, range: 0...59, suffix: " min")
            NumberMenuPicker(title: "Timeout seconds", selection: $seconds, range: 0...59, suffix: " sec")
        }
        .fixedSize()
    }
}

struct NumberMenuPicker: View {
    let title: String
    @Binding var selection: Int
    let range: ClosedRange<Int>
    var suffix = ""
    var width: CGFloat = 72

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(range, id: \.self) { value in
                Text(String(format: "%02d", value) + suffix).tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .monospacedDigit()
        .frame(width: width)
        .accessibilityLabel(title)
        .accessibilityIdentifier(title)
    }
}
