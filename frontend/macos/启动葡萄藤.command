#!/bin/zsh
set -euo pipefail
FILEPET_LAUNCH_ROOT=${0:A:h}
cd "$FILEPET_LAUNCH_ROOT"

# With no arguments this is only a convenience shortcut to the self-starting App.
# Custom root/port options retain the explicit external-engine development mode.
if (( $# > 0 )); then
  exec "$FILEPET_LAUNCH_ROOT/run-dev.sh" "$@"
fi
FILEPET_LAUNCH_BUNDLE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Info.plist)
FILEPET_LAUNCH_APP="$FILEPET_LAUNCH_ROOT/build/$FILEPET_LAUNCH_BUNDLE_NAME.app"
if [[ ! -x "$FILEPET_LAUNCH_APP/Contents/MacOS/FilePetShell" ]]; then
  "$FILEPET_LAUNCH_ROOT/build-app.sh"
fi
/usr/bin/open "$FILEPET_LAUNCH_APP"
print "葡萄藤已打开，会自动启动并连接分类核心。可以关闭本终端。"
