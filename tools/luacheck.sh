#!/bin/sh
# ============================================================================
# Penitent Relics Lua syntax check (Git Bash version)
# Usage: bash tools/luacheck.sh
# ============================================================================
LUAC="$(dirname "$0")/lua/luac53.exe"
MODROOT="$(dirname "$0")/../mod"

if [ ! -f "$LUAC" ]; then
    echo "[ERROR] $LUAC not found."
    echo "        Install the portable Lua 5.3 build into tools/lua/ (see README \"Development environment\")."
    exit 1
fi

echo "========== Penitent Relics Lua syntax check =========="
FAIL=0
TOTAL=0
for f in $(find "$MODROOT" -name "*.lua" | sort); do
    TOTAL=$((TOTAL + 1))
    if "$LUAC" -p "$f" 2>/dev/null; then
        echo "[ OK ] ${f#*mod/}"
    else
        echo "[FAIL] ${f#*mod/}"
        "$LUAC" -p "$f"
        FAIL=$((FAIL + 1))
    fi
done
echo "=================================================="
echo "$TOTAL file(s) checked, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "[RESULT] Syntax errors found. Fix them and re-run."
    exit 1
fi
echo "[RESULT] All checks passed."
