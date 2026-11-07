#!/bin/zsh
# Builds LogoGlow.app in ./build
set -e
cd "$(dirname "$0")"
APP=build/LogoGlow.app
rm -rf build && mkdir -p $APP/Contents/{MacOS,Resources} build/tmp

# Icon
xcrun swiftc -O Sources/MakeIcon.swift -o build/tmp/makeicon
build/tmp/makeicon build/tmp/icon.png
ICONSET=build/tmp/AppIcon.iconset; mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s build/tmp/icon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/tmp/icon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns

# App
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14 Sources/LogoGlow.swift -o $APP/Contents/MacOS/LogoGlow

cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>LogoGlow</string>
  <key>CFBundleDisplayName</key><string>LogoGlow</string>
  <key>CFBundleIdentifier</key><string>com.sanjitverma.LogoGlow</string>
  <key>CFBundleExecutable</key><string>LogoGlow</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep -s - $APP
rm -rf build/tmp
echo "Built $APP"
