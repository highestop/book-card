#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain.sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
xcrun swift test --disable-sandbox
