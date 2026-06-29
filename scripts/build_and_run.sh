#!/usr/bin/env bash
# build_and_run.sh - kill + build + launch MissingPlusPlus (Xcode project)
#
# 用法:
#   ./scripts/build_and_run.sh              # default: kill + Debug build + launch
#   ./scripts/build_and_run.sh --release    # Release build
#   ./scripts/build_and_run.sh --verify     # build + launch + pgrep verify alive
#   ./scripts/build_and_run.sh --debug      # build + lldb attach
#   ./scripts/build_and_run.sh --logs       # build + launch + unified log stream
#
# 设计 (按 build-macos-apps:build-run-debug skill 约定):
# - shell-first 入口, xcodebuild 走 DerivedData/ 隔离
# - default no-flag 路径: kill existing -> xcodebuild Debug build -> /usr/bin/open -n .app
# - 单一脚本拥有整个工作流, 不让用户记 xcodebuild 长命令
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="MissingPlusPlus.xcodeproj"
SCHEME="MissingPlusPlus"
APP_NAME="MissingPlusPlus"
BUNDLE_ID="com.tuzhipeng.MissingPlusPlus"
DERIVED="$ROOT_DIR/build/DerivedData"

CONFIG="Debug"
MODE="run"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)  CONFIG="Release"; shift ;;
        --verify)   MODE="verify"; shift ;;
        --debug)    MODE="debug"; shift ;;
        --logs)     MODE="logs"; shift ;;
        --help|-h)  sed -n '2,12p' "$0"; exit 0 ;;
        *)          echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

APP_BUNDLE="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"

# 1) 杀掉已经跑着的进程
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.3

# 2) xcodebuild
echo "==> xcodebuild -configuration $CONFIG build"
xcodebuild \
    -project "$ROOT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    build | tail -20

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: build did not produce $APP_BUNDLE" >&2
    exit 1
fi

# 3) launch / verify / debug / logs
case "$MODE" in
    run)
        /usr/bin/open -n "$APP_BUNDLE"
        echo "==> launched $APP_BUNDLE"
        ;;
    verify)
        /usr/bin/open -n "$APP_BUNDLE"
        sleep 1
        if pgrep -x "$APP_NAME" >/dev/null; then
            echo "==> verified: $APP_NAME is running"
        else
            echo "ERROR: $APP_NAME not running after launch" >&2
            exit 1
        fi
        ;;
    debug)
        /usr/bin/open -n "$APP_BUNDLE"
        sleep 0.5
        APP_PID=$(pgrep -x "$APP_NAME" | head -1)
        echo "==> attaching lldb to pid $APP_PID"
        lldb --attach-pid "$APP_PID"
        ;;
    logs)
        /usr/bin/open -n "$APP_BUNDLE"
        sleep 0.5
        echo "==> streaming unified logs for $BUNDLE_ID (Ctrl-C to stop)"
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\" OR processIdentifier == $(pgrep -x "$APP_NAME" | head -1)"
        ;;
esac
