import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Палитра как значение (переключаемая тема)
struct Palette: Identifiable, Equatable {
    let id: String
    let name: String
    let teal: Color      // фон страницы + тёмный текст на светлых карточках
    let tealD: Color     // тёмные карточки (hero / split)
    let lime: Color      // акцент (кнопка, пилюли, пинг, протокол)
    let cream: Color     // светлые карточки
    let taro: Color      // вторичная карточка (трафик)
    let glowHi: Color    // блик кнопки (верх)
    let glowLo: Color    // блик кнопки (низ)

    static let matchaLatte = Palette(
        id: "matcha", name: "matcha latte",
        teal: Color(hex: 0x285A71), tealD: Color(hex: 0x204C5F),
        lime: Color(hex: 0xCFDA5A), cream: Color(hex: 0xFCE4C0),
        taro: Color(hex: 0x2B6E6E), glowHi: Color(hex: 0xE2EC7E), glowLo: Color(hex: 0xB8C541))

    static let taroMatchaLatte = Palette(
        id: "taro", name: "taro matcha latte",
        teal: Color(hex: 0x412B42), tealD: Color(hex: 0x291E24),
        lime: Color(hex: 0x86A88E), cream: Color(hex: 0xF2E7EC),
        taro: Color(hex: 0x754A70), glowHi: Color(hex: 0xA6C4AD), glowLo: Color(hex: 0x6E9077))

    static let pumpkin = Palette(
        id: "pumpkin", name: "тыквенный полу-кофеиновый 88 градусный латте без пенки",
        teal: Color(hex: 0x141518), tealD: Color(hex: 0x373A3E),
        lime: Color(hex: 0xFF8A00), cream: Color(hex: 0xFFF2DF),
        taro: Color(hex: 0x26282C), glowHi: Color(hex: 0xFFB04D), glowLo: Color(hex: 0xE07600))

    static let all: [Palette] = [matchaLatte, taroMatchaLatte, pumpkin]
}

// MARK: - Менеджер темы (singleton, переживает пересоздание вью)
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    @Published private(set) var palette: Palette
    private let key = "matcha.theme"

    private init() {
        let saved = UserDefaults.standard.string(forKey: key) ?? Palette.taroMatchaLatte.id
        palette = Palette.all.first { $0.id == saved } ?? Palette.taroMatchaLatte
    }

    func select(_ p: Palette) {
        guard p.id != palette.id else { return }
        palette = p
        UserDefaults.standard.set(p.id, forKey: key)
    }
}

// MARK: - Цвета читаются из текущей темы
extension Color {
    static var mTeal:   Color { ThemeManager.shared.palette.teal }
    static var mTealD:  Color { ThemeManager.shared.palette.tealD }
    static var mLime:   Color { ThemeManager.shared.palette.lime }
    static var mCream:  Color { ThemeManager.shared.palette.cream }
    static var mTaro:   Color { ThemeManager.shared.palette.taro }
    static var mGlowHi: Color { ThemeManager.shared.palette.glowHi }
    static var mGlowLo: Color { ThemeManager.shared.palette.glowLo }
}

// MARK: - Шрифты
extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
