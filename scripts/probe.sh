#!/bin/sh
# Boot a headless Godot and run one probe body (EO7-style).
#   ./scripts/probe.sh plan_bugs
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
BODY="${1:-plan_bugs}"
if [ ! -x "$GODOT" ]; then
	echo "Godot not found at $GODOT"
	echo "Set GODOT=/path/to/Godot and retry."
	exit 127
fi
exec "$GODOT" --headless --path "$ROOT" res://tools/probe.tscn -- "--script=res://tools/probes/${BODY}.gd"
