#!/bin/sh
# Standalone builds you can copy to another computer (no Godot needed there).
#   ./scripts/export.sh            -> build/CONCURRENT-mac.zip and build/windows/CONCURRENT.exe
#   ./scripts/export.sh windows    -> just build/windows/CONCURRENT.exe (mac: just the Mac zip)
# Needs Godot's export templates once: open Godot → Editor → Manage Export
# Templates → Download and Install (about 1.3 GB, from godotengine.org).
# v2.3: runs on the Windows PC too (Git Bash): its Godot and its template folder are found.
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-}"
for g in "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" "$HOME/Documents/godot/Godot_v4.7.1-stable_win64_console.exe" "$(command -v godot)"; do
	[ -z "$GODOT" ] && [ -n "$g" ] && [ -x "$g" ] && GODOT="$g"
done
[ -n "$GODOT" ] || { echo "Godot not found: set GODOT=/path/to/Godot"; exit 127; }
VER="$("$GODOT" --version | tr -d '\r' | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.stable.*/\1.stable/')"
case "$(uname -s)" in
	Darwin) TPL="$HOME/Library/Application Support/Godot/export_templates/$VER" ;;
	MINGW*|MSYS*|CYGWIN*) TPL="$APPDATA/Godot/export_templates/$VER" ;;
	*) TPL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VER" ;;
esac
if [ ! -d "$TPL" ]; then
	echo "Export templates for Godot $VER are not installed (looked in $TPL)."
	echo "Open Godot → Editor → Manage Export Templates → Download and Install, then rerun."
	echo "(Or double-click build/CONCURRENT.app from ./scripts/make_launcher.sh — it needs no templates.)"
	exit 2
fi
WHICH="${1:-all}"
mkdir -p "$ROOT/build/windows"
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
if [ "$WHICH" = "all" ] || [ "$WHICH" = "mac" ]; then
	"$GODOT" --headless --path "$ROOT" --export-release "macOS" "$ROOT/build/CONCURRENT-mac.zip"
	echo "Built build/CONCURRENT-mac.zip"
fi
if [ "$WHICH" = "all" ] || [ "$WHICH" = "windows" ]; then
	"$GODOT" --headless --path "$ROOT" --export-release "Windows" "$ROOT/build/windows/CONCURRENT.exe"
	echo "Built build/windows/CONCURRENT.exe"
fi
