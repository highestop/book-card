#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
platform="${1:-simulator}"
case "$platform" in
  simulator)
    destination="generic/platform=iOS Simulator"
    product_directory="Debug-iphonesimulator"
    signing_options=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-)
    ;;
  device)
    destination="generic/platform=iOS"
    product_directory="Debug-iphoneos"
    signing_options=(CODE_SIGNING_ALLOWED=NO)
    ;;
  *) echo "Usage: $0 [simulator|device]" >&2; exit 2 ;;
esac
xcodebuild -project BookCard.xcodeproj -scheme BookCard-iOS \
  -configuration Debug -destination "$destination" \
  -derivedDataPath "$PWD/build/ios-$platform" "${signing_options[@]}" build
echo "Built: build/ios-$platform/Build/Products/$product_directory/BookCard.app"
