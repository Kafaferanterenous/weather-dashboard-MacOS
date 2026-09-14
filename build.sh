#!/bin/sh
set -e
cd "$(dirname "$0")"

APP_NAME="WeatherDashboard"
APP="dist/${APP_NAME}.app"
BUILD="build"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/x86_64" "$BUILD/arm64"

swiftc -O -parse-as-library -target x86_64-apple-macos13.0 \
    src/*.swift -o "$BUILD/x86_64/${APP_NAME}"
swiftc -O -parse-as-library -target arm64-apple-macos13.0 \
    src/*.swift -o "$BUILD/arm64/${APP_NAME}"

lipo -create "$BUILD/x86_64/${APP_NAME}" "$BUILD/arm64/${APP_NAME}" \
     -output "$APP/Contents/MacOS/${APP_NAME}"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" 2>/dev/null || true

echo "--- Build complete: $APP ---"
lipo -info "$APP/Contents/MacOS/${APP_NAME}" | sed 's/^/Architectures: /'
du -sh "$APP" | cut -f1 | xargs -I{} echo "App size: {}"
df -h / | tail -1 | awk '{print "Disk free: " $4 " of " $2}'
