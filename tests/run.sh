#!/bin/bash
# Compiles the parts of the app that do not need an iPhone for the build machine and runs their tests.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build-tests/out
xcrun clang -fobjc-arc -fmodules -O1 -g -Wall -Wno-unused-parameter -Wno-deprecated-declarations -IShared \
    tests/logic_tests.m Shared/GSCommon.m Shared/GSTweet.m Shared/GSStore.m Shared/GSGifMaker.m Shared/GSImporter.m \
    Shared/GSGifWriter.c \
    -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework Accelerate \
    -framework ImageIO -framework CoreGraphics -o build-tests/logic_tests
build-tests/logic_tests build-tests/out
