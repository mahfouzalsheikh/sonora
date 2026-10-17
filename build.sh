#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Sonora.app"
mkdir -p "$APP/Contents/MacOS"
swiftc Sources/*.swift -o "$APP/Contents/MacOS/Sonora" -O -framework SwiftUI -framework AppKit -framework AVFoundation -framework Accelerate -module-cache-path /tmp/sonora-swift-cache
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Sonora</string>
<key>CFBundleIdentifier</key><string>local.sonora.app</string>
<key>CFBundleName</key><string>Sonora</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>NSMicrophoneUsageDescription</key><string>Sonora uses your microphone to visualize sound frequencies and detect musical notes and chords. Audio stays on your Mac.</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
