#!/bin/bash
# MacMarkDown - SwiftLint + Strict Concurrency Check
# Usage: ./scripts/lint.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "============================================"
echo "  MacMarkDown - Lint & Concurrency Check"
echo "============================================"

# Swift 6.4 strict concurrency warnings check
echo ""
echo "[1/4] Checking Swift 6.4 strict concurrency..."
cd "$PROJECT_DIR"

DERIVED_DATA="$PROJECT_DIR/.derived"
BUILD_LOG="$DERIVED_DATA/lint-build.log"
mkdir -p "$DERIVED_DATA"
xcodebuild -project MacMarkDown.xcodeproj -scheme MacMarkDown \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" build \
    > "$BUILD_LOG" 2>&1 || true

WARNING_LINES=$(grep -E ": warning:" "$BUILD_LOG" | grep -v -i "appintents" || true)
CONCURRENCY_WARNINGS=$(echo "$WARNING_LINES" | grep -icE "concurren|actor|Sendable|isolation|data race" || true)
if [ "${CONCURRENCY_WARNINGS:-0}" -gt 0 ]; then
    echo "  WARNING: Found $CONCURRENCY_WARNINGS concurrency-related warnings"
    echo "$WARNING_LINES" | grep -iE "concurren|actor|Sendable|isolation|data race" | head -20
else
    echo "  No concurrency warnings"
fi

# Check for TODO/FIXME markers
echo ""
echo "[2/4] Checking TODO/FIXME markers..."
cd "$PROJECT_DIR/MacMarkDown"
TODO_COUNT=$(grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.swift" . 2>/dev/null | wc -l | tr -d ' ') || TODO_COUNT=0
TODO_COUNT="${TODO_COUNT:-0}"
if [ "$TODO_COUNT" -gt 0 ]; then
    echo "  Found $TODO_COUNT TODO/FIXME markers:"
    grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.swift" . 2>/dev/null | head -20
else
    echo "  No TODO/FIXME markers found"
fi

# Check file structure
echo ""
echo "[3/4] Verifying file structure..."
EXPECTED_FILES=(
    "Application/MacMarkDownApp.swift"
    "Extensions/StringExtensions.swift"
    "Document/MarkdownDocument.swift"
    "Document/FrontMatter.swift"
    "Markdown/MarkdownParser.swift"
    "Markdown/MarkdownElement.swift"
    "Theme/Theme.swift"
    "Theme/EditorTheme.swift"
    "Stores/Preferences.swift"
    "Tools/Constants.swift"
    "Services/Export/ExportService.swift"
    "Services/Preview/RenderService.swift"
    "Services/Preview/Renderer.swift"
    "Services/Editor/EditorOperations.swift"
    "Services/ScrollSync/ScrollSyncCoordinator.swift"
    "Services/ScrollSync/ScrollSyncService.swift"
    "UI/Shared/Document/DocumentView.swift"
    "UI/Shared/Document/ToolbarView.swift"
    "UI/Shared/Preview/MarkdownView.swift"
    "UI/Shared/Settings/SettingsView.swift"
    "UI/macOS/ScrollSync/ScrollSyncPane.swift"
    "UI/macOS/Editor/MarkdownEditorView.swift"
    "Tests/EditorOperationsTests.swift"
    "Tests/FrontMatterTests.swift"
    "Tests/MarkdownParserTests.swift"
    "Tests/ScrollSyncCoordinatorTests.swift"
    "Tests/ScrollSyncServiceTests.swift"
    "Tests/StringExtensionsTests.swift"
)

MISSING=0
for f in "${EXPECTED_FILES[@]}"; do
    if [ ! -f "$PROJECT_DIR/MacMarkDown/$f" ]; then
        echo "  MISSING: $f"
        MISSING=$((MISSING + 1))
    fi
done

if [ "$MISSING" -eq 0 ]; then
    echo "  All ${#EXPECTED_FILES[@]} expected files present"
else
    echo "  $MISSING files missing"
fi

# TextKit 2 compliance: the editor text view runs on TextKit 2, where
# `.layoutManager` is nil (or forces a TextKit 1 fallback). Accessing it from
# any editor-stack file is a bug. ExportService intentionally spins up a
# separate throwaway TextKit 1 text view for PDF printing only.
echo ""
echo "[4/4] Verifying TextKit 2 compliance..."
TK1_HITS=$(cd "$PROJECT_DIR/MacMarkDown" && grep -rn "\.layoutManager" --include="*.swift" UI/macOS/Editor UI/macOS/ScrollSync Services/Editor || true)
if [ -n "$TK1_HITS" ]; then
    echo "  WARNING: TextKit 1 (.layoutManager) access found in editor stack:"
    echo "$TK1_HITS"
    TK1_VIOLATION=1
else
    echo "  No TextKit 1 editor-stack violations"
    TK1_VIOLATION=0
fi

echo ""
echo "============================================"
if [ "$CONCURRENCY_WARNINGS" -eq 0 ] && [ "$MISSING" -eq 0 ] && [ "$TK1_VIOLATION" -eq 0 ]; then
    echo "  LINT CHECK PASSED"
else
    echo "  LINT CHECK COMPLETED WITH WARNINGS"
fi
echo "============================================"
