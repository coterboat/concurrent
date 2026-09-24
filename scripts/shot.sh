#!/bin/sh
# Windowed screenshot probe: ./scripts/shot.sh board   (PNGs land in $SHOT_DIR, default /tmp)
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
SHOT_DIR="${SHOT_DIR:-/tmp}" exec "$GODOT" --path "$ROOT" res://tools/probe.tscn -- "--script=res://tools/shots/${1:-board}.gd"
