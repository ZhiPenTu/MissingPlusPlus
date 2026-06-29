#!/usr/bin/env bash
# run_tests.sh - run MissingPlusPlusTests unit tests (Xcode project)
#
# 用法:
#   ./scripts/run_tests.sh                 # run all tests, Debug
#   ./scripts/run_tests.sh --release       # run all tests, Release
#   ./scripts/run_tests.sh --filter <expr> # only run tests matching <expr>
#                                          # e.g. --filter MissingPlusPlusTests.ActiveStateControllerTests
#   ./scripts/run_tests.sh --build-only    # build-for-testing but don't run
#
# 设计:
# - xcodebuild test 走 DerivedData/ 隔离
# - 输出末尾 30 行 (BUILD result + test summary), 用户不需要翻几百行编译输出
# - --filter 用 xcodebuild 的 -only-testing: 语法, 不实现自己的 grep
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="MissingPlusPlus.xcodeproj"
SCHEME="MissingPlusPlus"
DERIVED="$ROOT_DIR/build/DerivedData"

CONFIG="Debug"
FILTER=""
BUILD_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)   CONFIG="Release"; shift ;;
        --filter)    FILTER="$2"; shift 2 ;;
        --build-only) BUILD_ONLY=1; shift ;;
        --help|-h)   sed -n '2,9p' "$0"; exit 0 ;;
        *)           echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

LOG=$(mktemp -t missingpp-tests.XXXXXX.log)
trap 'rm -f "$LOG"' EXIT

XCODEBUILD_BASE=(
    -project "$ROOT_DIR/$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIG"
    -derivedDataPath "$DERIVED"
)
# xcodebuild -only-testing 格式: TargetName/ClassName/methodName
# 用户通常只传 ClassName.methodName, 自动补 Target 前缀
if [[ -n "$FILTER" ]]; then
    case "$FILTER" in
        */*) ;;  # 已经含 target 前缀, 原样用
        *)   FILTER="MissingPlusPlusTests/$FILTER" ;;
    esac
    XCODEBUILD_BASE+=(-only-testing:"$FILTER")
fi

echo "==> xcodebuild -configuration $CONFIG test"
if [[ $BUILD_ONLY -eq 1 ]]; then
    set +e
    xcodebuild "${XCODEBUILD_BASE[@]}" build-for-testing 2>&1 | tee "$LOG" | tail -30
    EXIT=${PIPESTATUS[0]}
else
    set +e
    xcodebuild "${XCODEBUILD_BASE[@]}" -destination 'platform=macOS' test 2>&1 | tee "$LOG" | tail -30
    EXIT=${PIPESTATUS[0]}
fi
set -e

# 失败时输出相关上下文
if [[ $EXIT -ne 0 ]]; then
    echo
    echo "==> FAILED (exit=$EXIT). Last 60 lines of test output:"
    tail -60 "$LOG"
    exit "$EXIT"
fi
