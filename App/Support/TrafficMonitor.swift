import Foundation
import SwiftUI

/// Живой монитор трафика: раз в секунду спрашивает у туннеля реальные rx/tx-байты,
/// считает мгновенную скорость ↓/↑ и держит скользящее окно для спарклайна.
///
/// Реальные цифры показываются только на поднятом туннеле (подписанная сборка).
/// В превью-режиме (без entitlement) генерируется лёгкая демо-волна — чтобы дизайн был
/// «живым» при просмотре без VPN; на реальную работу это не влияет.
@MainActor
final class TrafficMonitor: ObservableObject {
    @Published private(set) var rxTotal: UInt64 = 0
    @Published private(set) var txTotal: UInt64 = 0
    @Published private(set) var downBps: Double = 0
    @Published private(set) var upBps: Double = 0
    @Published private(set) var spark: [CGFloat] = Array(repeating: 0, count: 34)

    private var task: Task<Void, Never>?
    private var lastRx: UInt64 = 0
    private var lastTx: UInt64 = 0
    private var lastAt = Date()
    private var scale: Double = 1          // авто-нормировка спарклайна
    private var primed = false

    func start(_ tunnel: TunnelManager) {
        stop()
        reset()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(tunnel)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func reset() {
        rxTotal = 0; txTotal = 0; downBps = 0; upBps = 0
        lastRx = 0; lastTx = 0; lastAt = Date(); scale = 1; primed = false
        spark = Array(repeating: 0, count: 34)
    }

    private func tick(_ tunnel: TunnelManager) async {
        // Демо-волна в превью — только для наглядности дизайна без реального туннеля.
        if tunnel.usePreview {
            guard tunnel.isActive else { decay(); return }
            let d = Double.random(in: 200_000...2_400_000)
            let u = Double.random(in: 40_000...500_000)
            apply(down: d, up: u, addRx: UInt64(d), addTx: UInt64(u))
            return
        }

        guard let s = await tunnel.fetchStats() else { decay(); return }
        let now = Date()
        let dt = max(0.4, now.timeIntervalSince(lastAt))
        var d = 0.0, u = 0.0
        if primed {
            d = Double(s.rx &- lastRx) / dt
            u = Double(s.tx &- lastTx) / dt
        }
        primed = true
        lastRx = s.rx; lastTx = s.tx; lastAt = now
        rxTotal = s.rx; txTotal = s.tx
        apply(down: d, up: u, addRx: 0, addTx: 0, absolute: true, rx: s.rx, tx: s.tx)
    }

    private func apply(down: Double, up: Double, addRx: UInt64, addTx: UInt64,
                       absolute: Bool = false, rx: UInt64 = 0, tx: UInt64 = 0) {
        downBps = down; upBps = up
        if absolute { rxTotal = rx; txTotal = tx }
        else { rxTotal &+= addRx; txTotal &+= addTx }
        let total = down + up
        scale = max(scale * 0.9, total, 1)
        pushSpark(CGFloat(min(1, total / scale)))
    }

    private func decay() {
        downBps *= 0.5; upBps *= 0.5
        if downBps < 1 { downBps = 0 }; if upBps < 1 { upBps = 0 }
        pushSpark(0)
    }

    private func pushSpark(_ v: CGFloat) {
        spark.removeFirst()
        spark.append(v)
    }

    /// "1.2 МБ/с" / "820 КБ/с" / "0 Б/с"
    static func rate(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.1f МБ/с", bps / 1_048_576) }
        if bps >= 1024 { return String(format: "%.0f КБ/с", bps / 1024) }
        return "\(Int(bps)) Б/с"
    }

    static func bytes(_ b: UInt64) -> String {
        let d = Double(b)
        if d >= 1_073_741_824 { return String(format: "%.1f ГБ", d / 1_073_741_824) }
        if d >= 1_048_576 { return String(format: "%.0f МБ", d / 1_048_576) }
        if d >= 1024 { return String(format: "%.0f КБ", d / 1024) }
        return "\(b) Б"
    }
}
