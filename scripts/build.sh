#!/bin/bash
# MacMarkDown - Build Verification Script
# Usage: ./scripts/build.sh [debug|release]

set -euo pipefail

CONFIGURATION="${1:-debug}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$PROJECT_DIR/.derived"
LOG="$DERIVED_DATA/build.log"
OFFICIAL_CONFIG="Debug"
if [ "$CONFIGURATION" = "release" ]; then
    OFFICIAL_CONFIG="Release"
fi

echo "============================================"
echo "  MacMarkDown - Build Verification"
echo "  Configuration: $OFFICIAL_CONFIG"
echo "============================================"

# Check prerequisites
echo ""
echo "[1/4] Checking prerequisites..."

if ! command -v xcodebuild &> /dev/null; then
    echo "ERROR: xcodebuild not found"
    exit 1
fi
XCODE_VERSION_FULL=$(xcodebuild -version 2>&1)
XCODE_VERSION=$(printf '%s\n' "$XCODE_VERSION_FULL" | sed -n '1p')
echo "  Xcode: $XCODE_VERSION"

if command -v xcodegen &> /dev/null; then
    echo "  Regenerating project from project.yml..."
    (cd "$PROJECT_DIR" && xcodegen generate > /dev/null)
else
    echo "  WARNING: xcodegen not found; using committed MacMarkDown.xcodeproj"
fi

# Resolve packages
echo ""
echo "[2/4] Resolving Swift packages..."
cd "$PROJECT_DIR"
xcodebuild -project MacMarkDown.xcodeproj -scheme MacMarkDown \
    -derivedDataPath "$DERIVED_DATA" -resolvePackageDependencies > /dev/null 2>&1
echo "  Packages resolved successfully"

# Build
echo ""
echo "[3/4] Building project..."
mkdir -p "$DERIVED_DATA"
if xcodebuild -project MacMarkDown.xcodeproj -scheme MacMarkDown \
    -configuration "$OFFICIAL_CONFIG" -derivedDataPath "$DERIVED_DATA" build \
    > "$LOG" 2>&1; then
    grep -E "warning:|error:" "$LOG" | grep -v "AppIntents.framework" | head -20 || true
    echo "  Build completed successfully"
else
    echo "  BUILD FAILED:"
    grep -E "error:" "$LOG" | head -30 || true
    exit 1
fi

# Run tests
echo ""
echo "[4/4] Running tests..."
"$PROJECT_DIR/scripts/test.sh"

echo ""
echo "============================================"
echo "  BUILD VERIFICATION PASSED"
echo "============================================"
