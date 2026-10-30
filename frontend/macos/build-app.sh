#!/bin/zsh
set -euo pipefail
FILEPET_SHELL_ROOT=${0:A:h}
cd "$FILEPET_SHELL_ROOT"
if [[ -z ${DEVELOPER_DIR:-} && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if pgrep -x FilePetShell >/dev/null; then
  print -u2 "请先从菜单栏退出葡萄藤，再重新构建。"
  exit 2
fi
swift build -c release
FILEPET_SHELL_BINARY_DIR=$(swift build -c release --show-bin-path)
FILEPET_SHELL_APP="$FILEPET_SHELL_ROOT/build/FilePetShell.app"
mkdir -p "$FILEPET_SHELL_APP/Contents/MacOS" "$FILEPET_SHELL_APP/Contents/Resources"
cp "$FILEPET_SHELL_BINARY_DIR/FilePetShell" "$FILEPET_SHELL_APP/Contents/MacOS/FilePetShell"
ditto "$FILEPET_SHELL_BINARY_DIR/FilePetShell_FilePetShell.bundle" \
  "$FILEPET_SHELL_APP/Contents/Resources/FilePetShell_FilePetShell.bundle"
cp Info.plist "$FILEPET_SHELL_APP/Contents/Info.plist"
codesign --force --sign - --entitlements FilePetShell.entitlements "$FILEPET_SHELL_APP"
codesign --verify --strict "$FILEPET_SHELL_APP"
print "已构建：$FILEPET_SHELL_APP"
