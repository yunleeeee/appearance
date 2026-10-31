#!/bin/zsh
set -euo pipefail
FILEPET_SHELL_ROOT=${0:A:h}
FILEPET_ENGINE_ROOT=${FILEPET_ENGINE_ROOT:-${FILEPET_SHELL_ROOT:h:h:h}/filepet-engine}
FILEPET_INPUT_ROOT=""
FILEPET_USE_EXAMPLES=0
FILEPET_PORT=8765
FILEPET_OPEN_APP=1
FILEPET_ENGINE_PID=""

usage() {
  print "日常使用可直接双击 FilePetShell.app，App 会自动启动并连接分类核心。"
  print "以下为自定义授权目录或外部核心的开发启动方式。"
  print "用法：./run-dev.sh --root <允许引擎读取的文件夹> [--port 8765] [--engine-only] [--engine-root <核心仓库>]"
  print "示例：./run-dev.sh --examples"
  print "核心默认使用相邻的 filepet-engine；也可通过 FILEPET_ENGINE_ROOT 或 --engine-root 指定。"
  print -r -- "--examples 允许读取核心 backend/，覆盖普通分类与 DDL 示例。"
  print "Ctrl+C 只停止本脚本启动的分类引擎；不会移动或删除输入文件。"
}

while (( $# )); do
  case "$1" in
    --root)
      (( $# >= 2 )) || { usage; exit 2; }
      FILEPET_INPUT_ROOT="$2"
      FILEPET_USE_EXAMPLES=0
      shift 2 ;;
    --examples)
      FILEPET_USE_EXAMPLES=1
      shift ;;
    --engine-root)
      (( $# >= 2 )) || { usage; exit 2; }
      FILEPET_ENGINE_ROOT="$2"
      shift 2 ;;
    --port)
      (( $# >= 2 )) || { usage; exit 2; }
      FILEPET_PORT="$2"
      shift 2 ;;
    --no-open|--engine-only)
      FILEPET_OPEN_APP=0
      shift ;;
    --help|-h)
      usage
      exit 0 ;;
    *)
      print -u2 "未知参数：$1"
      usage
      exit 2 ;;
  esac
done

# LaunchServices does not replace the arguments of an already running app.
# Refuse a misleading "reconnect" to a different external service.
if (( FILEPET_OPEN_APP )) && pgrep -x FilePetShell >/dev/null; then
  print -u2 "葡萄藤已运行，并会自动管理分类核心。"
  print -u2 "切换到脚本的自定义目录或外部核心前，请先从菜单栏退出 App；仅启动外部服务可加 --engine-only。"
  exit 2
fi

FILEPET_ENGINE_ROOT=${FILEPET_ENGINE_ROOT:A}
FILEPET_BACKEND_ROOT="$FILEPET_ENGINE_ROOT/backend"
FILEPET_PYTHON="$FILEPET_ENGINE_ROOT/.venv/bin/python"
if [[ ! -d "$FILEPET_BACKEND_ROOT/filepet" ]]; then
  print -u2 "未找到 FilePet 核心：$FILEPET_BACKEND_ROOT"
  print -u2 "请将核心放在相邻的 filepet-engine，或通过 FILEPET_ENGINE_ROOT / --engine-root 指定核心仓库。"
  exit 2
fi
if (( FILEPET_USE_EXAMPLES )); then
  FILEPET_INPUT_ROOT="$FILEPET_BACKEND_ROOT"
fi
if [[ -z "$FILEPET_INPUT_ROOT" ]]; then
  usage
  print -u2 "请显式指定 --root，或用 --examples 选择项目示例。"
  exit 2
fi
if [[ "$FILEPET_PORT" != <-> ]] || (( FILEPET_PORT < 1 || FILEPET_PORT > 65535 )); then
  print -u2 "端口必须为 1–65535。"
  exit 2
fi
if [[ ! -x "$FILEPET_PYTHON" ]]; then
  print -u2 "未找到项目 Python 环境：$FILEPET_PYTHON"
  print -u2 "请先按照 $FILEPET_BACKEND_ROOT/README.md 安装分类引擎依赖。"
  exit 2
fi
if ! FILEPET_INPUT_ROOT=$("$FILEPET_PYTHON" -c '
import pathlib,sys
try:
    root=pathlib.Path(sys.argv[1]).expanduser().resolve(strict=True)
except OSError:
    raise SystemExit("找不到或无法读取所选目录："+sys.argv[1])
if not root.is_dir():
    raise SystemExit("--root 必须指向已存在的文件夹")
print(root)
' "$FILEPET_INPUT_ROOT"); then
  exit 2
fi
FILEPET_ENGINE_URL="http://127.0.0.1:$FILEPET_PORT"

is_filepet_engine() {
  /usr/bin/curl --silent --fail --max-time 2 "$FILEPET_ENGINE_URL/health" \
    | "$FILEPET_PYTHON" -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status")=="ok" and d.get("version")=="0.1.0" else 1)' \
    >/dev/null 2>&1
}

if /usr/sbin/lsof -nP -iTCP:"$FILEPET_PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
  if is_filepet_engine; then
    print -u2 "端口 $FILEPET_PORT 已有 FilePet 引擎。当前协议不提供授权目录查询，不能确认其 --root。"
  else
    print -u2 "端口 $FILEPET_PORT 已被其他服务占用。"
  fi
  print -u2 "没有停止现有服务。请自行关闭它，或使用 --port 选择空闲端口。"
  exit 2
fi

if (( FILEPET_OPEN_APP )); then
  FILEPET_ENGINE_ROOT="$FILEPET_ENGINE_ROOT" "$FILEPET_SHELL_ROOT/build-app.sh"
fi
mkdir -p "$FILEPET_SHELL_ROOT/build"
FILEPET_ENGINE_LOG="$FILEPET_SHELL_ROOT/build/engine.log"
cleanup() {
  if [[ -n "$FILEPET_ENGINE_PID" ]] && kill -0 "$FILEPET_ENGINE_PID" 2>/dev/null; then
    kill "$FILEPET_ENGINE_PID" 2>/dev/null || true
    wait "$FILEPET_ENGINE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
(
  cd "$FILEPET_BACKEND_ROOT"
  exec "$FILEPET_PYTHON" -m filepet serve --root "$FILEPET_INPUT_ROOT" --port "$FILEPET_PORT"
) >"$FILEPET_ENGINE_LOG" 2>&1 &
FILEPET_ENGINE_PID=$!

FILEPET_READY=0
for FILEPET_ATTEMPT in {1..50}; do
  if is_filepet_engine && /usr/sbin/lsof -nP -a -p "$FILEPET_ENGINE_PID" -iTCP:"$FILEPET_PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
    FILEPET_READY=1
    break
  fi
  if ! kill -0 "$FILEPET_ENGINE_PID" 2>/dev/null; then
    print -u2 "引擎未能启动，请查看 $FILEPET_ENGINE_LOG"
    exit 1
  fi
  sleep 0.1
done
if (( ! FILEPET_READY )); then
  print -u2 "等待引擎启动超时，请查看 $FILEPET_ENGINE_LOG"
  exit 1
fi
print "分类引擎：$FILEPET_ENGINE_URL"
print "允许读取：$FILEPET_INPUT_ROOT"
if (( FILEPET_OPEN_APP )); then
  /usr/bin/open "$FILEPET_SHELL_ROOT/build/FilePetShell.app" --args --engine-url "$FILEPET_ENGINE_URL"
fi
print "保持本终端运行。Ctrl+C 停止本次引擎；葡萄藤的离线预览仍可使用。"
wait "$FILEPET_ENGINE_PID"
FILEPET_ENGINE_PID=""
