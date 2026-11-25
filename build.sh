#!/bin/bash
# Builds GifStash.ipa (the app, its share extension and its keyboard), ad-hoc signed with the TrollStore entitlements.
# Needs Xcode; no project file.
set -euo pipefail
cd "$(dirname "$0")"

OUT=build
APP="$OUT/Payload/GifStash.app"
APPEX="$APP/PlugIns/Share.appex"
KEYBOARD="$APP/PlugIns/Keyboard.appex"
MIN_IOS=16.0
rm -rf "$OUT"
mkdir -p "$APP" "$APPEX" "$KEYBOARD"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC=(xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min="$MIN_IOS"
    -fobjc-arc -fmodules -O2 -g0 -Wall -Wno-unused-parameter -Wno-deprecated-declarations -IShared -IApp)
FRAMEWORKS=(-framework Foundation -framework UIKit -framework AVFoundation -framework CoreMedia -framework CoreVideo
            -framework Accelerate -framework ImageIO -framework CoreGraphics -framework QuartzCore)

echo "== app executable"
"${CC[@]}" App/*.m Shared/*.m Shared/*.c -o "$APP/GifStash" "${FRAMEWORKS[@]}"

echo "== share extension"
"${CC[@]}" -fapplication-extension Share/*.m Shared/*.m Shared/*.c -o "$APPEX/Share" "${FRAMEWORKS[@]}" \
    -e _NSExtensionMain -Wl,-application_extension
cp Share/Info.plist "$APPEX/Info.plist"
plutil -lint "$APPEX/Info.plist"
plutil -convert binary1 "$APPEX/Info.plist"

echo "== keyboard"
"${CC[@]}" -fapplication-extension Keyboard/*.m Shared/*.m Shared/*.c -o "$KEYBOARD/Keyboard" "${FRAMEWORKS[@]}"     -e _NSExtensionMain -Wl,-application_extension
cp Keyboard/Info.plist "$KEYBOARD/Info.plist"
plutil -lint "$KEYBOARD/Info.plist"
plutil -convert binary1 "$KEYBOARD/Info.plist"

echo "== asset catalog"
xcrun actool App/Assets.xcassets --compile "$APP" --platform iphoneos \
    --minimum-deployment-target "$MIN_IOS" --target-device iphone \
    --app-icon AppIcon --output-partial-info-plist "$OUT/assets-info.plist" \
    --errors --warnings --notices --output-format human-readable-text

echo "== Info.plist"
cp App/Info.plist "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Merge $OUT/assets-info.plist" "$APP/Info.plist"
plutil -lint "$APP/Info.plist"
plutil -convert binary1 "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"

echo "== sign (ad-hoc + TrollStore entitlements; the extensions first, the app seals them)"
codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements Keyboard/keyboard.entitlements "$KEYBOARD"
codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements Share/share.entitlements "$APPEX"
codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements App/app.entitlements "$APP"

echo "== package"
(cd "$OUT" && zip -qry GifStash.ipa Payload)
ls -la "$OUT"
