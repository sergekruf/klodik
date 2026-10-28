#!/bin/bash
# Собирает build/Klodik.app из Swift Package. Запуск: bash scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Klodik.app"

cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Klodik"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Klodik"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>Klodik</string>
    <key>CFBundleDisplayName</key>      <string>Клодик</string>
    <key>CFBundleIdentifier</key>       <string>ru.tokarev-lab.klodik</string>
    <key>CFBundleExecutable</key>       <string>Klodik</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key>          <string>1</string>
    <key>LSMinimumSystemVersion</key>   <string>14.0</string>
    <key>LSUIElement</key>              <true/>
</dict>
</plist>
PLIST

# Подпись «для себя», без сертификата разработчика.
codesign --force --sign - "$APP"
echo "Готово: $APP"

# `--install` — положить в ~/Applications и перезапустить. Автозапуск привязан к месту приложения,
# поэтому для каждого дня запускать стоит именно эту копию, а не build/.
if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications/Klodik.app"
    pkill -x Klodik || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Установлено и запущено: $DEST"
fi
