import Foundation
import SystemExtensions
import os

/// Активация системного расширения-туннеля на macOS.
///
/// Для распространения вне App Store (.dmg) NE-провайдер оформлен как **System Extension**.
/// Его надо один раз активировать через `OSSystemExtensionRequest`; система попросит
/// пользователя одобрить расширение в «Системные настройки → Конфиденциальность и
/// безопасность». После одобрения `NETunnelProviderManager` управляет им как VPN-профилем.
@MainActor
final class SystemExtensionManager: NSObject, ObservableObject {

    enum State: Equatable {
        case unknown
        case installing            // запрос отправлен, ждём систему
        case needsApproval         // пользователь должен разрешить в Системных настройках
        case active                // расширение установлено и активно
        case failed(String)
    }

    static let shared = SystemExtensionManager()
    @Published private(set) var state: State = .unknown

    private let extID = AppIDs.tunnelBundleId
    private let log = Logger(subsystem: "space.matchavpn.mac", category: "sysext")

    /// Запросить активацию (идемпотентно).
    func activate() {
        guard state != .installing else { return }
        state = .installing
        log.info("activation request for \(self.extID, privacy: .public)")
        let req = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extID, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }
}

extension SystemExtensionManager: OSSystemExtensionRequestDelegate {

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties)
    -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in self.state = .active }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            self.log.error("failed: \(error.localizedDescription, privacy: .public)")
            self.state = .failed(error.localizedDescription)
        }
    }
}
