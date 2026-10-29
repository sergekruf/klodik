#!/bin/bash
# Собирает build/Klodik.app из Swift Package.
#   bash scripts/build-app.sh            — сборка под этот Mac
#   bash scripts/build-app.sh --install  — то же и установить в ~/Applications
#   bash scripts/build-app.sh --release  — universal (Apple Silicon + Intel) и build/Klodik-<версия>.zip для GitHub
set -euo pipefail

VERSION="0.2.2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Klodik.app"

cd "$ROOT"
ARCHS=()
[[ "${1:-}" == "--release" ]] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Klodik"

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
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key>          <string>5</string>
    <key>LSMinimumSystemVersion</key>   <string>14.0</string>
    <key>LSUIElement</key>              <true/>
</dict>
</plist>
PLIST
sed -i '' "s/__VERSION__/$VERSION/" "$APP/Contents/Info.plist"

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

if [[ "${1:-}" == "--release" ]]; then
    ZIP="$ROOT/build/Klodik-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Архив для релиза: $ZIP"
fi
