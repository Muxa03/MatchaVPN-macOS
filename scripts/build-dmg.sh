#!/usr/bin/env bash
# Сборка подписанного Developer ID и нотаризованного MatchaVPN.dmg.
#
# Требуется:
#   • заполненный DEVELOPMENT_TEAM в project.yml (или Team в Xcode → Signing);
#   • сертификат "Developer ID Application" в связке ключей;
#   • настроенный notarytool-профиль (имя ≥3 символов!):
#       xcrun notarytool store-credentials "matcha" --apple-id <id> --team-id <TEAM_ID> --password <app-spec-pass>
#   • create-dmg: brew install create-dmg
#
# Запуск:  NOTARY_PROFILE=matcha ./scripts/build-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MatchaVPN"
SCHEME="MatchaLab"
CONFIG="Release"
BUILD_DIR="$(pwd)/build"
NOTARY_PROFILE="${NOTARY_PROFILE:-matcha}"

command -v create-dmg >/dev/null || { echo "нужен create-dmg: brew install create-dmg" >&2; exit 1; }

echo "▸ Генерация проекта"
xcodegen generate

echo "▸ Архив (Developer ID)"
rm -rf "$BUILD_DIR"
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" archive

echo "▸ Экспорт .app"
cat > "$BUILD_DIR/export.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/export.plist" \
  -exportPath "$BUILD_DIR/export"

APP="$BUILD_DIR/export/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME.dmg"

echo "▸ Сборка .dmg"
rm -f "$DMG"
create-dmg \
  --volname "$APP_NAME" \
  --window-size 500 320 --icon-size 96 \
  --icon "$APP_NAME.app" 130 150 \
  --app-drop-link 370 150 \
  "$DMG" "$APP"

echo "▸ Нотаризация"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "✅ Готово: $DMG"
