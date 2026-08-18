#!/bin/bash
# 위젯 컴파일 + 최소 .app 번들 갱신.
# 번들이 필요한 이유: launchd(로그인 자동 시작)로 띄우는 GUI 프로그램은
# 번들 신원이 없으면 화면(WindowServer)에 붙지 못한다.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP="$DIR/Tally.app"
echo "컴파일 중… ($(swiftc --version | head -1))"
swiftc -O widget.swift -o tally -framework AppKit

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f tally "$APP/Contents/MacOS/tally"

# 아이콘 — 없으면 만든다
if [ ! -f icon.icns ]; then
  echo "아이콘 생성 중…"
  swift make-icon.swift
fi
cp -f icon.icns "$APP/Contents/Resources/icon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tally</string>
  <key>CFBundleDisplayName</key><string>Tally</string>
  <key>CFBundleIdentifier</key><string>dev.tally.app</string>
  <key>CFBundleExecutable</key><string>tally</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 자체 서명(ad-hoc) — 서명이 없으면 맥이 알림 권한을 거부한다(UNErrorDomain 1)
codesign --force --sign - --identifier dev.tally.app "$APP" 2>/dev/null \
  && echo "서명 완료(ad-hoc)" || echo "서명 실패 — 알림은 osascript 로 떨어집니다"

# 번들을 바꿨으면 LaunchServices 캐시도 갱신해 준다
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" 2>/dev/null || true

echo "완료 → $APP  (실행파일: $DIR/tally)"
