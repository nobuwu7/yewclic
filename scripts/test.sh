#!/usr/bin/env bash
# Runs the unit tests. Works with full Xcode or with only the Command Line
# Tools, which ship Swift Testing outside the default search path.
set -euo pipefail
cd "$(dirname "$0")/.."

EXTRA_FLAGS=()
CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_LIBS="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" && -d "$CLT_FRAMEWORKS/Testing.framework" ]]; then
  EXTRA_FLAGS=(-Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS"
               -Xlinker -F -Xlinker "$CLT_FRAMEWORKS"
               -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS"
               -Xlinker -rpath -Xlinker "$CLT_LIBS")
fi

swift test --scratch-path .build.nosync "${EXTRA_FLAGS[@]}"
