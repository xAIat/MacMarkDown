#!/bin/bash
# MacMarkDown - Unit Test Runner
# Usage: ./scripts/test.sh [--coverage]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$PROJECT_DIR/.derived"
LOG="$DERIVED_DATA/test.log"
COVERAGE=false

if [ "${1:-}" = "--coverage" ]; then
    COVERAGE=true
fi

echo "============================================"
echo "  MacMarkDown - Unit Test Runner"
echo "  Coverage: $COVERAGE"
echo "============================================"

cd "$PROJECT_DIR"
mkdir -p "$DERIVED_DATA"

EXTRA_ARGS=()
if [ "$COVERAGE" = true ]; then
    EXTRA_ARGS+=("-enableCodeCoverage" "YES" "-resultBundlePath" "$DERIVED_DATA/TestResults.xcresult")
    rm -rf "$DERIVED_DATA/TestResults.xcresult"
fi

echo ""
echo "[1/2] Running unit tests..."
if xcodebuild -project MacMarkDown.xcodeproj -scheme MacMarkDown \
    -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} test > "$LOG" 2>&1; then
    grep -E "Test Suite '.*' (passed|failed)|Executed [0-9]+ tests" "$LOG" | tail -12
    echo "  Tests passed"
else
    echo "  TEST FAILED:"
    grep -E "error:|failed" "$LOG" | head -30 || true
    exit 1
fi

if [ "$COVERAGE" = true ]; then
    echo ""
    echo "[2/2] Generating coverage report..."
    xcrun xccov view --report --only-targets "$DERIVED_DATA/TestResults.xcresult" 2>&1 || true
else
    echo ""
    echo "[2/2] Test summary..."
    grep -E "Executed [0-9]+ tests" "$LOG" | tail -1
fi

echo ""
echo "============================================"
echo "  TEST RUN COMPLETE"
echo "============================================"
