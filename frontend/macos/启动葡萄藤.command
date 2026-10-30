#!/bin/zsh
set -euo pipefail
FILEPET_LAUNCH_ROOT=${0:A:h}
cd "$FILEPET_LAUNCH_ROOT"

if (( $# == 0 )); then
  print "葡萄藤 · 界面与分类核心联合启动"
  print "把允许分类的文件夹拖到这里，再按回车。直接回车使用项目示例。"
  read -r "FILEPET_SELECTED_ROOT?文件夹："
  FILEPET_SELECTED_ROOT="${FILEPET_SELECTED_ROOT#"${FILEPET_SELECTED_ROOT%%[![:space:]]*}"}"
  FILEPET_SELECTED_ROOT="${FILEPET_SELECTED_ROOT%"${FILEPET_SELECTED_ROOT##*[![:space:]]}"}"
  if [[ -n "$FILEPET_SELECTED_ROOT" ]]; then
    FILEPET_SELECTED_ROOT=${(Q)FILEPET_SELECTED_ROOT}
    set -- --root "$FILEPET_SELECTED_ROOT"
  else
    set -- --examples
  fi
fi

# A running shell can reconnect without being rebuilt or restarted.
if pgrep -x FilePetShell >/dev/null; then
  print "葡萄藤界面已打开，本次补启动分类核心。"
  print "启动后可在菜单中点“重新连接分类引擎”，或直接再次投放文件。"
  exec "$FILEPET_LAUNCH_ROOT/run-dev.sh" "$@" --engine-only
fi
exec "$FILEPET_LAUNCH_ROOT/run-dev.sh" "$@"
