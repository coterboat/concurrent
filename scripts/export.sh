#!/bin/sh
# Standalone builds you can copy to another computer (no Godot needed there).
#   ./scripts/export.sh          -> build/CONCURRENT-mac.zip and build/windows/CONCURRENT.exe
# Needs Godot's export templates once: open Godot → Editor → Manage Export
# Templates → Download and Install (about 1 GB, from godotengine.org).
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
VER="$("$GODOT" --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.stable.*/\1.stable/')"
TPL="$HOME/Library/Application Support/Godot/export_templates/$VER"
if [ ! -d "$TPL" ]; then
	echo "Export templates for Godot $VER are not installed."
	echo "Open Godot → Editor → Manage Export Templates → Download and Install, then rerun."
	echo "(Or double-click build/CONCURRENT.app from ./scripts/make_launcher.sh — it needs no templates.)"
	exit 2
fi
mkdir -p "$ROOT/build/windows"
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$ROOT" --export-release "macOS" "$ROOT/build/CONCURRENT-mac.zip"
"$GODOT" --headless --path "$ROOT" --export-release "Windows" "$ROOT/build/windows/CONCURRENT.exe"
echo "Built build/CONCURRENT-mac.zip and build/windows/CONCURRENT.exe"
