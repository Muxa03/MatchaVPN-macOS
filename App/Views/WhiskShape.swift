import SwiftUI

// MARK: - Венчик матчи (часэн) — фирменный значок кнопки подключения
/// Тонкие «прутья» веничка (без ручки). Координаты нормированы под сетку 24×24
/// — те же кривые, что в HTML-макете, перенесённые в Path.
struct WhiskTines: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        // центральный прут
        path.move(to: p(12, 15)); path.addLine(to: p(12, 3.5))
        // внутренняя пара
        path.move(to: p(12, 15)); path.addCurve(to: p(9.3, 3.7), control1: p(11, 9.5), control2: p(9.8, 6.5))
        path.move(to: p(12, 15)); path.addCurve(to: p(14.7, 3.7), control1: p(13, 9.5), control2: p(14.2, 6.5))
        // внешняя пара
        path.move(to: p(12, 15)); path.addCurve(to: p(6.6, 5), control1: p(10, 10.5), control2: p(7.6, 8.5))
        path.move(to: p(12, 15)); path.addCurve(to: p(17.4, 5), control1: p(14, 10.5), control2: p(16.4, 8.5))
        // перевязка
        path.move(to: p(9.2, 14.4)); path.addQuadCurve(to: p(14.8, 14.4), control: p(12, 16.2))
        return path
    }
}

/// Ручка веничка (толстая линия снизу).
struct WhiskHandle: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: 12 * s, y: 15 * s))
        path.addLine(to: CGPoint(x: 12 * s, y: 21.5 * s))
        return path
    }
}

struct WhiskIcon: View {
    var color: Color = .mTeal
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            WhiskHandle()
                .stroke(color, style: StrokeStyle(lineWidth: size * 3.2 / 24, lineCap: .round))
            WhiskTines()
                .stroke(color, style: StrokeStyle(lineWidth: size * 1.7 / 24, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Рисованная от руки стрелка «жми»
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.93, y: h * 0.15))
        p.addCurve(to: CGPoint(x: w * 0.16, y: h * 0.85),
                   control1: CGPoint(x: w * 0.57, y: h * 0.05),
                   control2: CGPoint(x: w * 0.23, y: h * 0.35))
        // наконечник
        p.move(to: CGPoint(x: w * 0.16, y: h * 0.85)); p.addLine(to: CGPoint(x: w * 0.09, y: h * 0.55))
        p.move(to: CGPoint(x: w * 0.16, y: h * 0.85)); p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.75))
        return p
    }
}
