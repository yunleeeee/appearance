#!/bin/zsh
set -euo pipefail
FILEPET_MOTION_TOOLS=${0:A:h}
FILEPET_MOTION_ROOT=${FILEPET_MOTION_TOOLS:h}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p "$FILEPET_MOTION_TOOLS/.build"
xcrun swiftc -parse-as-library -O \
  "$FILEPET_MOTION_TOOLS/RenderMotion.swift" \
  -o "$FILEPET_MOTION_TOOLS/.build/RenderMotion"
"$FILEPET_MOTION_TOOLS/.build/RenderMotion" "$FILEPET_MOTION_ROOT" "$@"
