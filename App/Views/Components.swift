import SwiftUI

// MARK: - Bento-карточка
enum CardStyle { case cream, lime, teal, taro }

struct Card<Content: View>: View {
    var style: CardStyle
    var padding: CGFloat = 16
    var fill: Bool = false
    @ObservedObject private var theme = ThemeManager.shared
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .foregroundColor(fg)
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(bg))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(style == .teal ? Color.mCream.opacity(0.14) : Color.clear, lineWidth: 2)
            )
    }
    private var bg: Color {
        switch style {
        case .cream: return .mCream
        case .lime:  return .mLime
        case .taro:  return .mTaro
        case .teal:  return .mTealD
        }
    }
    private var fg: Color { (style == .teal || style == .taro) ? .mCream : .mTeal }
}

// MARK: - Мелкие элементы
struct MonoLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.mono(9.5))
            .tracking(1.5)
            .opacity(0.7)
    }
}

struct Chip: View {
    let text: String
    var on: Bool = false
    @ObservedObject private var theme = ThemeManager.shared
    var body: some View {
        Text(text.uppercased())
            .font(.mono(8))
            .tracking(0.5)
            .foregroundColor(on ? .mLime : .mTeal)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.mTeal : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(on ? Color.mTeal : Color.mTeal.opacity(0.35), lineWidth: 1.5)
            )
    }
}

struct Sparkline: View {
    let values: [CGFloat]
    var color: Color = .mTeal
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.85))
                        .frame(height: max(2, geo.size.height * values[i]))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct StatusPill: View {
    var active: Bool
    @ObservedObject private var theme = ThemeManager.shared
    @State private var blink = false
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(active ? Color.mTeal : Color.mCream.opacity(0.6))
                .frame(width: 7, height: 7)
                .opacity(active && blink ? 0.2 : 1)
            Text(active ? "защита включена" : "отключено")
                .font(.system(size: 10, weight: .heavy)).textCase(.uppercase)
        }
        .foregroundColor(active ? .mTeal : .mCream)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(active ? Color.mLime : Color.white.opacity(0.12)))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { blink = true }
        }
    }
}

struct MToggle: View {
    @Binding var isOn: Bool
    @ObservedObject private var theme = ThemeManager.shared
    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(Color.mTeal).frame(width: 56, height: 32)
            Circle().fill(Color.mLime).frame(width: 26, height: 26).padding(3)
        }
        .onTapGesture { withAnimation(.spring(response: 0.25)) { isOn.toggle() } }
    }
}

// MARK: - Главная кнопка (венчик + кольца + свечение)
struct PowerButton: View {
    var isOn: Bool
    var action: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @State private var animateRings = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // пульсирующее свечение (только когда включено)
            Circle()
                .fill(RadialGradient(colors: [Color.mLime.opacity(0.4), .clear],
                                     center: .center, startRadius: 0, endRadius: 90))
                .frame(width: 172, height: 172)
                .scaleEffect(pulse ? 1.12 : 0.9)
                .opacity(isOn ? (pulse ? 1 : 0.55) : 0)

            // кольца — вращаются только когда VPN включён
            Circle().strokeBorder(Color.mCream.opacity(isOn ? 0.22 : 0.1),
                                  style: StrokeStyle(lineWidth: 2, dash: [2, 6]))
                .frame(width: 232, height: 232)
                .rotationEffect(.degrees(animateRings ? -360 : 0))
                .animation(animateRings ? .linear(duration: 16).repeatForever(autoreverses: false) : .default,
                           value: animateRings)
            Circle().strokeBorder((isOn ? Color.mLime : Color.mCream).opacity(isOn ? 0.5 : 0.15),
                                  style: StrokeStyle(lineWidth: 2.5, dash: [8, 10]))
                .frame(width: 206, height: 206)
                .rotationEffect(.degrees(animateRings ? 360 : 0))
                .animation(animateRings ? .linear(duration: 13).repeatForever(autoreverses: false) : .default,
                           value: animateRings)
            Circle().strokeBorder(Color.mCream.opacity(0.14), lineWidth: 2.5)
                .frame(width: 180, height: 180)

            // сама кнопка
            Button(action: action) {
                ZStack {
                    Circle().fill(isOn
                        ? AnyShapeStyle(RadialGradient(
                            colors: [.mGlowHi, .mLime, .mGlowLo],
                            center: UnitPoint(x: 0.38, y: 0.32), startRadius: 5, endRadius: 110))
                        : AnyShapeStyle(Color.mCream))
                    Circle().strokeBorder(Color.mLime.opacity(isOn ? 0.16 : 0), lineWidth: 8).frame(width: 174, height: 174)
                    Circle().strokeBorder(Color.mTeal, lineWidth: 4)
                    VStack(spacing: 3) {
                        WhiskIcon(color: .mTeal, size: 56)
                        Text(isOn ? "СТОП" : "СТАРТ")
                            .font(.display(16, .heavy))
                            .tracking(2)
                            .foregroundColor(.mTeal)
                    }
                }
                .frame(width: 158, height: 158)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 232, height: 232)
        .onAppear {
            animateRings = isOn
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: isOn) { newValue in
            animateRings = newValue
        }
    }
}
