#!/bin/sh
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
	echo "Godot not found at $GODOT"
	echo "Set GODOT=/path/to/Godot and retry."
	exit 127
fi
## v1.14: the runner can print "failed=0" over a SCRIPT ERROR (a test file that fails to compile, or
## one that dies halfway, just stops reporting), so the output is searched for one too
LOG="$(mktemp "${TMPDIR:-/tmp}/concurrent_test.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
rc=0
"$GODOT" --headless --path "$ROOT" --script res://tests/runner.gd 2>&1 | tee "$LOG" || rc=$?
if grep -q "SCRIPT ERROR" "$LOG"; then
	echo "test: FAIL  a SCRIPT ERROR above (the passed/failed count doesn't see it):"
	grep -A1 "SCRIPT ERROR" "$LOG" | head -8 | sed 's/^/        /'
	exit 1
fi
grep -q "CONCURRENT ok" "$LOG" || exit 1
exit $rc
