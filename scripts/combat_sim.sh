#!/bin/sh
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
	echo "Godot not found at $GODOT"
	echo "Set GODOT=/path/to/Godot and retry."
	exit 127
fi
exec "$GODOT" --headless --path "$ROOT" --script res://tools/combat_sim.gd
