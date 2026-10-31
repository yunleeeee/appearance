#!/bin/zsh
set -euo pipefail
FILEPET_SHELL_ROOT=${0:A:h}
FILEPET_BUILD_ENGINE_ROOT=${FILEPET_ENGINE_ROOT:-${FILEPET_SHELL_ROOT:h:h:h}/filepet-engine}
FILEPET_BUILD_ENGINE_ROOT=${FILEPET_BUILD_ENGINE_ROOT:A}
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
# Record this Mac's installed runtime location without hard-coding it in source.
/usr/bin/plutil -insert FilePetEngineRoot -string "$FILEPET_BUILD_ENGINE_ROOT" \
  "$FILEPET_SHELL_APP/Contents/Info.plist"
if [[ ! -d "$FILEPET_BUILD_ENGINE_ROOT/backend/filepet" || ! -x "$FILEPET_BUILD_ENGINE_ROOT/.venv/bin/python" ]]; then
  print -u2 "提示：本机分类环境尚未就绪，App 仍可构建；自动分类需要 $FILEPET_BUILD_ENGINE_ROOT 中的核心与 Python 环境。"
fi
codesign --force --sign - --entitlements FilePetShell.entitlements "$FILEPET_SHELL_APP"
codesign --verify --strict "$FILEPET_SHELL_APP"
print "已构建：$FILEPET_SHELL_APP"
