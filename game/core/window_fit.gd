## The window the game opens in (v2.3; peeled out of main.gd in v2.5). On Windows and Linux it takes 85% of
## the usable screen at the tables' 16:10, centred. The UI is laid out at 1440×900 or more whatever the
## window's size and scales with it, so a small window only makes the words smaller.
## v2.5: a laptop's screen had no room for the window's least size, 1180×720. A 1366×768 screen leaves 728
## under the taskbar and about 690 under a title bar too, so the window ran off it, its title bar above the
## top. Now the least size is what the screen can hold, the window is centred with its title bar and
## borders counted, and a screen too small for 85% (anything under about 1390×850) opens the window
## maximized: every pixel goes to the war, with the title bar and the taskbar where Windows keeps them.
## A screen is measured as Windows shows it: a 14-inch laptop's 1920×1080 runs at 150% (Dad's Lenovo,
## Alex 11-03), which Windows treats as a 1280×720 screen and so does this; the game, which sizes in real
## pixels, would otherwise open a desktop's 85% window on it, its words three-fifths the size Windows
## gives everything else there.
extends RefCounted

const LEAST := Vector2i(1180, 720) ## the least the window is made, where the screen has room for it
const SHARE := 0.85


static func plan(area: Rect2i, deco: Vector2i, inset: Vector2i, scale: float = 1.0) -> Dictionary:
	## area: the screen's usable rect (above the taskbar); deco: the title bar and borders (the outer size
	## less the inner); inset: where the inner area sits in the outer window; scale: Windows' display
	## scale (1.5 at 150%). Always {least, maximize}; {size, position} too when it opens as a window
	var room: Vector2i = (area.size - deco).max(Vector2i(1, 1))
	var least: Vector2i = LEAST.min(room)
	var h: float = minf(area.size.y * SHARE, area.size.x * SHARE / 1.6)
	var want := Vector2i(int(h * 1.6), int(h))
	var k: float = maxf(scale, 1.0)
	if want.x / k < LEAST.x or want.y / k < LEAST.y:
		return {"least": least, "maximize": true}
	want = want.min(room)
	return {"least": least, "maximize": false, "size": want, "position": area.position + inset + (room - want) / 2}


static func apply(win: Window, opening: bool, area: Rect2i = Rect2i()) -> void:
	## opening: the game starting, when the window is placed. Otherwise (back from fullscreen) the window
	## is left as the player had it, unless it runs off the screen. area: the screen's usable rect (a probe
	## passes a laptop's)
	if area.size.x <= 0 or area.size.y <= 0:
		area = DisplayServer.screen_get_usable_rect(win.current_screen)
	if area.size.x <= 0 or area.size.y <= 0:
		return
	var deco: Vector2i = (win.get_size_with_decorations() - win.size).max(Vector2i.ZERO)
	var inset: Vector2i = (win.position - win.get_position_with_decorations()).max(Vector2i.ZERO)
	var pl: Dictionary = plan(area, deco, inset, float(DisplayServer.screen_get_dpi(win.current_screen)) / 96.0)
	win.min_size = pl["least"]
	if win.mode != Window.MODE_WINDOWED:
		return
	if pl["maximize"]:
		win.mode = Window.MODE_MAXIMIZED
		return
	var on_screen: bool = area.encloses(Rect2i(win.get_position_with_decorations(), win.get_size_with_decorations()))
	var want: Vector2i = pl["size"]
	if on_screen and (not opening or absf(float(want.x) / float(win.size.x) - 1.0) < 0.1):
		return ## as the player left it, or near enough to what it opened at
	win.size = want
	win.position = pl["position"]
