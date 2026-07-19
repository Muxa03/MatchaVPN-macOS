# MatchaVPN — macOS

Нативный macOS-клиент MatchaVPN (SwiftUI + Network Extension **app-extension** + AmneziaWG).
Упаковка туннеля — как в iOS-приложении (`packet-tunnel-provider`), поэтому подписывается
той же автоподписью, что и айфон. Распространяется вне App Store как подписанный Developer ID
и нотаризованный `.dmg` — чистый VPN-клиент без декоя.

## Что уже есть

- Полный UI на SwiftUI (окно 460×720, тёмная taro-палитра, ритуальная кнопка подключения,
  выбор локации, ввод ключа, настройки, переключение темы).
- Переносимое ядро, общее с iOS: `SubscriptionStore`, `Keychain`, `AmneziaConfig`, `Theme`.
- Реальный туннель: `PacketTunnelProvider` (amneziawg-go) как **app-extension**; точку входа
  даёт `NSExtension` в Info.plist (`NSExtensionPrincipalClass`), ровно как на iOS.
- Живая метрика трафика: приложение через app-message тянет **реальные** rx/tx-счётчики
  туннеля (`TrafficMonitor`), спидометр ↓/↑ и спарклайн на главном экране.
- Иконка приложения (AppIcon) по macOS-сетке.
- Проект **собирается и линкуется целиком** (WireGuardKit + Go + appex + app).

Без подписи приложение запускается в превью-режиме — интерфейс живой, но VPN не поднимается.
С подписью (Team ID) туннель работает.

## Требования

- macOS 13+, Xcode 16+ (проверено на Xcode 26.3).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Go (для сборки amneziawg-go): `brew install go`

## Сборка

```sh
xcodegen generate           # .xcodeproj из project.yml
# вписать Team ID в project.yml → settings.base.DEVELOPMENT_TEAM (или задать в Xcode → Signing)
open MatchaLab.xcodeproj     # схема MatchaLab → Run
```

Проверка сборки без подписи:

```sh
xcodebuild build -scheme MatchaLab -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## Подпись (как на iOS)

Туннель — обычный app-extension с entitlement `packet-tunnel-provider`, поэтому подпись
устроена так же, как в iOS-проекте, который уже успешно подписывается:

1. В портале Apple у **обоих** App ID (`space.matchavpn.mac` и `space.matchavpn.mac.tunnel`)
   включить способность **Network Extensions**.
2. В Xcode оставить «Automatically manage signing», выбрать Team → автоподпись выпустит профили.
3. При первом подключении система один раз спросит «MatchaVPN хочет добавить конфигурации VPN» —
   как на айфоне. Никакого одобрения расширения в «Конфиденциальности» не требуется.

## .dmg (для распространения)

1. Archive → экспорт с сертификатом **Developer ID Application**, Hardened Runtime включён.
2. Собрать `.dmg` (`create-dmg`), нотаризовать и застейплить:
   ```sh
   xcrun notarytool submit MatchaVPN.dmg --keychain-profile "matcha" --wait
   xcrun stapler staple MatchaVPN.dmg
   ```

## Структура

```
App/            приложение (SwiftUI)
  Views/        экраны + UI-атомы (Components, WhiskShape)
  Support/      TunnelManager
  MatchaLab.entitlements
Shared/         переносимое ядро (Theme, Keychain, AmneziaConfig, Subscription)
Tunnel/         app-extension туннеля
  PacketTunnelProvider.swift, Tunnel.entitlements
project.yml     спецификация XcodeGen
```

## Безопасность

- Приложение и расширение — в **App Sandbox** (минимум entitlements: network client/server).
- Ключ-подписка — единственный секрет — в Keychain (`AfterFirstUnlockThisDeviceOnly`),
  не в UserDefaults; не в бэкапах, недоступен другим приложениям.
- Токен уходит на сервер заголовком `X-Token` по HTTPS (не в URL — не оседает в логах).
- Hardened Runtime включён. Хардкоженных секретов нет (базовый URL публичный).

## Статус

Каркас порта готов и собирается. Дальше: подпись на устройстве, сборка `.dmg`,
проверка реального туннеля, публикация рядом с Windows-клиентом.
