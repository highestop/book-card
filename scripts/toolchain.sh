#!/bin/zsh
# SwiftData macros and iOS SDKs require the complete Xcode toolchain.
# Respect an explicitly selected toolchain and do not change xcode-select globally.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
