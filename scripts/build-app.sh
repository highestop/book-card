#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
xcrun swift build -c release --product BookCard --disable-sandbox
app="$PWD/build/BookCard.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/BookCard "$app/Contents/MacOS/BookCard"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BookCard</string>
<key>CFBundleDisplayName</key><string>BookCard</string>
<key>CFBundleIdentifier</key><string>local.BookCard</string>
<key>CFBundleExecutable</key><string>BookCard</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app"
