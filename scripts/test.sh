#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/contract-tests
swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/BookCard/WeRead.swift Sources/BookCard/Store.swift Sources/BookCard/ArticleTitles.swift Tests/BookCardTests/BookCardTests.swift -o .build/contract-tests/BookCardTests
.build/contract-tests/BookCardTests
