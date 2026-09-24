#!/bin/sh
# Build a double-clickable CONCURRENT.app for this Mac.
# It runs the game through the Godot already on this machine, so it needs no
# export templates. Drag it to the Dock or Applications like any other app.
#   ./scripts/make_launcher.sh            -> build/CONCURRENT.app
#   ./scripts/make_launcher.sh ~/Desktop  -> ~/Desktop/CONCURRENT.app
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/build}"
APP="$DEST/CONCURRENT.app"
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
if [ ! -x "$GODOT" ]; then
	echo "Godot not found. Set GODOT=/path/to/Godot.app/Contents/MacOS/Godot"
	exit 127
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# First run imports the art; make sure that has happened once.
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
cat > "$APP/Contents/MacOS/concurrent" <<SH
#!/bin/sh
PROJECT="$ROOT"
GODOT="$GODOT"
[ -x "\$GODOT" ] || GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
[ -x "\$GODOT" ] || GODOT="\$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
if [ ! -x "\$GODOT" ] || [ ! -f "\$PROJECT/project.godot" ]; then
	osascript -e 'display alert "CONCURRENT cannot start" message "It needs Godot 4.5 and the game folder it was built from."'
	exit 1
fi
exec "\$GODOT" --path "\$PROJECT"
SH
chmod +x "$APP/Contents/MacOS/concurrent"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleName</key><string>CONCURRENT</string>
	<key>CFBundleDisplayName</key><string>CONCURRENT</string>
	<key>CFBundleIdentifier</key><string>game.concurrent.launcher</string>
	<key>CFBundleVersion</key><string>1.0.0</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleExecutable</key><string>concurrent</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Icon from the Ludo emblem
ICON_SRC="$ROOT/assets/icons/app.png"
if [ -f "$ICON_SRC" ]; then
	SET="$(mktemp -d)/AppIcon.iconset"
	mkdir -p "$SET"
	for s in 16 32 64 128 256 512; do
		sips -z $s $s "$ICON_SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
		d=$((s * 2))
		sips -z $d $d "$ICON_SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
	done
	iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi
touch "$APP"
echo "Built $APP"
