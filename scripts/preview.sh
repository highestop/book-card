#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
xcrun swift build --product BookCard --disable-sandbox
mkdir -p .build/previews
preview_bin="$(xcrun swift build --show-bin-path)"
if [[ -f "$preview_bin/libBookCardCore.a" ]]; then
  preview_core=(-I "$preview_bin" "$preview_bin/libBookCardCore.a")
else
  preview_core=(-I "$preview_bin/Modules" "$preview_bin"/BookCardCore.build/*.swift.o)
fi
xcrun swiftc -swift-version 5 -D PREVIEW_RENDER -parse-as-library -module-cache-path "$PWD/.build/clang-cache" "${preview_core[@]}" Apps/macOS/*.swift scripts/render-preview.swift -o .build/previews/RenderPreview
.build/previews/RenderPreview
