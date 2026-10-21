#!/bin/sh
# Every screenshot probe, one at a time, as facts: ./scripts/probes.sh [name ...]
#   ./scripts/probes.sh              every probe in tools/shots/
#   ./scripts/probes.sh v112 v111    just these
# A probe fails on a `FAIL` line (its p.ok() facts), a SCRIPT ERROR, a non-zero exit, or a hang
# (each is time-boxed). PNGs land in $SHOT_DIR (default: a fresh folder under /tmp), for looking at.
# Windowed: it needs a display (the bot uses Xvfb). Run it alone when the owner's Godot is open.
# PROBE_ARGS go to every probe: `PROBE_ARGS=--box=40` plays each frame as 40/60 of a second, as the
# bot's software-GL box does (tools/probe.gd).
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT="$(command -v godot)"
[ -n "$GODOT" ] && [ -x "$GODOT" ] || { echo "probes: Godot not found (set GODOT=/path/to/godot)"; exit 127; }
SHOT_DIR="${SHOT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/concurrent_probes.XXXXXX")}"
SECS="${PROBE_SECS:-900}"
names="$*"
[ -z "$names" ] && names="$(ls tools/shots/*.gd | sed -E 's#tools/shots/(.*)\.gd#\1#')"
failed=""
for n in $names; do
	[ -f "tools/shots/$n.gd" ] || { echo "probes: no probe $n"; failed="$failed $n"; continue; }
	mkdir -p "$SHOT_DIR/$n"
	log="$SHOT_DIR/$n/probe.log"
	start=$(date +%s)
	SHOT_DIR="$SHOT_DIR/$n" perl -e 'alarm shift; exec @ARGV' "$SECS" \
		"$GODOT" --path . res://tools/probe.tscn -- "--script=res://tools/shots/$n.gd" $PROBE_ARGS >"$log" 2>&1
	rc=$?
	facts=$(grep -c "^PROBE ok" "$log")
	if [ $rc = 0 ] && ! grep -qE "^PROBE FAIL|SCRIPT ERROR" "$log"; then
		echo "probes: ok    $n ($facts facts, $(ls "$SHOT_DIR/$n" | grep -c png) shots, $(($(date +%s) - start)) s)"
	else
		[ $rc = 142 ] && echo "probes: FAIL  $n (hung: killed after $SECS s)" || echo "probes: FAIL  $n (exit $rc)"
		grep -E "^PROBE FAIL|SCRIPT ERROR" "$log" | head -8 | sed 's/^/        /'
		failed="$failed $n"
	fi
done
echo "probes: screenshots and logs in $SHOT_DIR"
[ -z "$failed" ] || { echo "probes: failed:$failed"; exit 1; }
