#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
if [[ $# -gt 0 ]]; then shift; fi
APP_NAME="DisplayWeave"
PROJECT="OpenSidecar.xcodeproj"
SCHEME="OpenSidecarMac"
CONFIGURATION="Debug"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build-run"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

log_step() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

launch_app() {
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "找不到 App：$APP_BUNDLE" >&2
    exit 1
  fi

  log_step "正在打开 $APP_BUNDLE"
  /usr/bin/open -n "$APP_BUNDLE" --args "$@"
  sleep 1

  if app_process exists; then
    log_step "$APP_NAME 已启动"
    return 0
  fi

  echo "$APP_NAME 已请求打开，但 1 秒后没有检测到运行中的进程。" >&2
  echo "如果这是第一次运行，请检查 macOS 是否弹出了隐私权限或安全确认窗口。" >&2
  exit 1
}

# Match this checkout's executable, so an installed release keeps running.
app_process() {
  python3 - "$APP_BINARY" "$1" <<'PYPROCESS'
import os, signal, subprocess, sys
binary, action = sys.argv[1:]
rows = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True).splitlines()
pids = [int(row.strip().split(None, 1)[0]) for row in rows
        if len(row.strip().split(None, 1)) == 2 and row.strip().split(None, 1)[1] == binary]
if action == "stop":
    for pid in pids:
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: pass
else:
    sys.exit(0 if pids else 1)
PYPROCESS
}

app_process stop
xcodegen generate

log_step "开始构建 $SCHEME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA/SourcePackages" \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
log_step "构建完成"

case "$MODE" in
  run)
    launch_app "$@"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    launch_app "$@"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    launch_app "$@"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    launch_app "$@"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
