#!/bin/sh
# The short check before a commit (about 15 s): ./scripts/check.sh
#   - compiles every script
#   - the tool tests (the review table, the note rewriter)
#   - the newest tests/test_vNN.gd, and any test file you changed
#   - with engine/ or session.gd changed: the view, properties and match tests too
# The full suite (./scripts/test.sh, a few minutes) is still the thing to run before a push.
#
# It runs as the git pre-commit hook (scripts/githooks/pre-commit) once a checkout says
#   git config core.hooksPath scripts/githooks
# which `./scripts/check.sh --install` does. Skip it once with `git commit --no-verify`.
# Without Godot on this machine it checks what it can and says it skipped the rest.
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" ## GitHub Desktop runs hooks with a bare PATH

if [ "$1" = "--install" ]; then
	git config core.hooksPath scripts/githooks
	echo "check: installed; every commit in this checkout runs scripts/check.sh first"
	exit 0
fi

GODOT="${GODOT:-}"
for g in "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" "/Applications/Godot.app/Contents/MacOS/Godot" "$(command -v godot)"; do
	[ -z "$GODOT" ] && [ -x "$g" ] && GODOT="$g"
done
LOG="$(mktemp "${TMPDIR:-/tmp}/concurrent_check.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
failed=0

## A GDScript runtime error doesn't quit headless Godot: it hangs. So every run is time-boxed
## (perl's alarm survives the exec), and its output is searched for SCRIPT ERROR.
timed() {
	secs=$1
	shift
	perl -e 'alarm shift; exec @ARGV' "$secs" "$@" >"$LOG" 2>&1
}

step() {
	## step <label> <seconds> <command...>: one line per step, the tail of the log when it fails
	label=$1
	secs=$2
	shift 2
	start=$(date +%s)
	if timed "$secs" "$@" && ! grep -q "SCRIPT ERROR" "$LOG"; then
		echo "check: ok    $label ($(($(date +%s) - start)) s)"
	else
		echo "check: FAIL  $label"
		grep -E "SCRIPT ERROR|FAIL|Error|error:|Traceback" "$LOG" | head -12 | sed 's/^/        /'
		tail -4 "$LOG" | sed 's/^/        /'
		failed=1
	fi
}

## what this commit touches: the staged files when git is committing, else everything changed
changed="$(git diff --cached --name-only 2>/dev/null)"
[ -z "$changed" ] && changed="$(git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard)"

if command -v python3 >/dev/null 2>&1; then
	step "tool tests" 120 sh -c "python3 tools/review/test_review.py && python3 tools/ludo/test_notes.py"
else
	echo "check: skip  tool tests (no python3)"
fi

if [ -z "$GODOT" ]; then
	echo "check: skip  the Godot checks (no Godot found; set GODOT=/path/to/Godot)"
	exit $failed
fi

step "compile every script" 120 "$GODOT" --headless --path . --script res://tools/compile_check.gd
grep -q ", 0 failed" "$LOG" || { [ $failed = 0 ] && echo "check: FAIL  compile (no '0 failed' line)"; failed=1; }

## the newest version's tests (test_v112 is 1.12, test_v19 is 1.9), plus any test file changed
newest="$(ls tests/test_v1*.gd 2>/dev/null | sed -E 's#^tests/test_v1([0-9]+)\.gd$#\1 &#' | sort -n | tail -1 | cut -d' ' -f2)"
tests="$newest $(echo "$changed" | grep -E '^tests/test_.*\.gd$')"
if echo "$changed" | grep -qE '^engine/|^game/core/session\.gd$|^game/view_events\.gd$'; then
	tests="$tests tests/test_view_events.gd tests/test_properties.gd tests/test_match.gd"
fi
for t in $(echo $tests | tr ' ' '\n' | sort -u); do
	[ -f "$t" ] || continue
	step "$t" ${CHECK_SECS:-300} "$GODOT" --headless --path . --script res://tools/test_one.gd -- "$t"
done

if [ $failed = 1 ]; then
	echo "check: something failed; fix it, or commit anyway with git commit --no-verify"
fi
exit $failed
