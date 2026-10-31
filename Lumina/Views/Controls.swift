import SwiftUI

enum Motion {
    static let bouncy = Animation.spring(response: 0.32, dampingFraction: 0.58)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.68)
}

// MARK: - 10. ADDITIONAL CUSTOM UI WRAPPERS
struct BackdropGradient: View {
    var isNight: Bool
    var body: some View {
        LinearGradient(
            colors: isNight
                ? [Color.indigo.opacity(0.10), Color.clear]
                : [Color.orange.opacity(0.08), Color.clear],
            startPoint: .top, endPoint: .center
        )
        .ignoresSafeArea()
        .animation(Motion.smooth, value: isNight)
    }
}

struct PremiumToggle: View {
    @Binding var isOn: Bool
    var tint: Color = .accentColor
    var title = "Automatic brightness"

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(tint)
            .accessibilityLabel(title)
    }
}

struct CoordinateField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LuminaText.muted)
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BrightnessSlider: View {
    @Binding var value: Double
    var tint: Color
    var step: Double = 0.02
    var onEditing: ((Double) -> Void)?

    var body: some View {
        Slider(value: Binding(
            get: { AutomationPolicy.clampBrightness(value) },
            set: { newValue in
                value = newValue
                onEditing?(newValue)
            }
        ), in: 0...1, step: step)
        .tint(tint)
        .accessibilityLabel("Keyboard brightness")
        .accessibilityValue("\(Int((AutomationPolicy.clampBrightness(value) * 100).rounded())) percent")
    }
}

struct BrightnessRow: View {
    var title: String
    @Binding var value: Double
    var tint: Color
    var subtitle: String? = nil
    var onEditing: ((Double) -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text(value == 0 ? "Off" : "\(Int((value * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(value == 0 ? LuminaText.soft : .primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: value)
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundStyle(LuminaText.faint)
                BrightnessSlider(value: $value, tint: tint, onEditing: onEditing)
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(LuminaText.faint)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(LuminaText.soft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ToggleRow: View {
    var systemImage: String
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(LuminaText.soft))
                .frame(width: 22)
                .animation(Motion.snappy, value: isOn)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(LuminaText.soft)
                }
            }
            Spacer(minLength: 8)
            PremiumToggle(isOn: $isOn, tint: tint, title: title)
        }
    }
}

struct SegmentedTabs<T: Hashable>: View {
    @Binding var selection: T
    var items: [(value: T, label: String, icon: String)]
    var tint: Color = .accentColor

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                let selected = item.value == selection
                Button {
                    withAnimation(Motion.smooth) { selection = item.value }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon).font(.caption2)
                        Text(item.label).font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(LuminaText.muted))
                    .background {
                        if selected {
                            Capsule()
                                .fill(tint.gradient)
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

struct ModeSwitch: View {
    @Binding var isAuto: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            segment(label: "System", icon: "laptopcomputer",
                    active: !isAuto, tint: .orange) {
                if isAuto { withAnimation(Motion.smooth) { isAuto = false } }
            }
            segment(label: "Periodic", icon: "slider.horizontal.3",
                    active: isAuto, tint: .indigo) {
                if !isAuto { withAnimation(Motion.smooth) { isAuto = true } }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func segment(label: String, icon: String, active: Bool,
                         tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(label).font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(LuminaText.muted))
            .background {
                if active {
                    Capsule().fill(tint.gradient)
                        .matchedGeometryEffect(id: "modeseg", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Card<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(Motion.bouncy, value: configuration.isPressed)
    }
}
