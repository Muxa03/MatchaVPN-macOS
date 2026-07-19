import Foundation
import NetworkExtension

// Точка входа системного расширения на macOS: переводим процесс в режим сетевого
// расширения, дальше система по NEProviderClasses (Info.plist) поднимает наш
// PacketTunnelProvider для типа packet-tunnel.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
