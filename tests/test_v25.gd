## v2.5: the general pass before the game goes to Dad, a first-time player on a Windows PC we haven't
## seen (docs/v25/v25-pass.md). No rule changes (rules 23): these are the window, the renderer and the
## robustness facts that the kernel side can state.
extends RefCounted

const WindowFit := preload("res://game/core/window_fit.gd")
const Session := preload("res://game/core/session.gd")

## Windows 10's title bar and borders at 100% (measured on the PC: 16 wider, 39 taller, the client area
## 8 in from the left and 31 down)
const DECO := Vector2i(16, 39)
const INSET := Vector2i(8, 31)


func run(report: Callable, tree: SceneTree) -> void:
	_window(report)
	_renderer(report)
	_saves(report, tree)


func _saves(report: Callable, tree: SceneTree) -> void:
	## the save is written whole; a save that can't be picked up is never offered as Continue
	var keep: String = Session.SAVE_PATH
	Session.SAVE_PATH = "user://test_v25_save_%d.json" % OS.get_process_id()
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/knife7.json", "seed": 25, "length": "short", "deal": "random", "seats": [
		{"id": "red", "name": "Varek", "kind": "ai", "ai": "varek"},
		{"id": "blue", "name": "Oren", "kind": "ai", "ai": "oren"}]})
	s.save() ## (an AI war is deployed and saved as it starts)
	var whole: Variant = JSON.parse_string(FileAccess.get_file_as_string(Session.SAVE_PATH))
	var info: Dictionary = Session.save_summary()
	report.call(typeof(whole) == TYPE_DICTIONARY and not FileAccess.file_exists(Session.SAVE_PATH + ".part") and str(info.get("map", "")) == "The Isthmus",
		"a save is written whole and put in its place, nothing left beside it (%s)" % str(info))
	var text: String = FileAccess.get_file_as_string(Session.SAVE_PATH)
	for cut in [["cut short", text.left(text.length() / 2)], ["empty", ""], ["no sheets", JSON.stringify({"config": {"map": "res://maps/knife7.json"}, "setup": {}})]]:
		var f := FileAccess.open(Session.SAVE_PATH, FileAccess.WRITE)
		f.store_string(str(cut[1]))
		f.close()
		report.call(Session.save_summary().is_empty(), "a save %s has no summary: the title offers no Continue to nowhere" % str(cut[0]))
	Session.set_aside_save()
	var aside: String = Session.SAVE_PATH.get_basename() + ".unreadable.json"
	report.call(not Session.has_save() and FileAccess.file_exists(aside), "a save that couldn't be opened is set aside under another name (%s), not offered again" % aside.get_file())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(aside))
	s.queue_free()
	Session.SAVE_PATH = keep


func _window(report: Callable) -> void:
	## the window fits the screen it opens on, title bar and all
	for scr in [[Vector2i(1366, 768), 40, true], [Vector2i(1280, 720), 40, true], [Vector2i(1440, 900), 40, true],
			[Vector2i(1600, 900), 40, true], [Vector2i(1920, 1080), 40, false], [Vector2i(2560, 1440), 48, false],
			[Vector2i(3840, 2160), 60, false]]:
		var screen: Vector2i = scr[0]
		var area := Rect2i(Vector2i.ZERO, screen - Vector2i(0, int(scr[1])))
		var pl: Dictionary = WindowFit.plan(area, DECO, INSET)
		var least: Vector2i = pl["least"]
		var fits_least: bool = least.x + DECO.x <= area.size.x and least.y + DECO.y <= area.size.y
		if bool(scr[2]):
			report.call(bool(pl["maximize"]) and fits_least,
				"a %dx%d screen opens the game maximized, its least size %s inside what's left under the taskbar and a title bar" % [screen.x, screen.y, str(least)])
		else:
			var at: Vector2i = pl["position"]
			var outer := Rect2i(at - INSET, Vector2i(pl["size"]) + DECO)
			var share: float = float(Vector2i(pl["size"]).y) / float(area.size.y)
			report.call(not bool(pl["maximize"]) and area.encloses(outer) and least == WindowFit.LEAST and absf(share - 0.85) < 0.06,
				"a %dx%d screen opens a %s window, %.0f%% of its height, title bar and borders on the screen (%s)" % [screen.x, screen.y, str(pl["size"]), share * 100.0, str(outer)])
	## a laptop's 1920×1080 at Windows' 150% (Dad's 14-inch Lenovo, likely) is a small screen too; a 4K
	## monitor at 150% is not
	var lap: Dictionary = WindowFit.plan(Rect2i(0, 0, 1920, 1020), DECO, INSET, 1.5)
	var lap125: Dictionary = WindowFit.plan(Rect2i(0, 0, 1920, 1030), DECO, INSET, 1.25)
	var lap100: Dictionary = WindowFit.plan(Rect2i(0, 0, 1920, 1040), DECO, INSET, 1.0)
	var big: Dictionary = WindowFit.plan(Rect2i(0, 0, 3840, 2100), DECO, INSET, 1.5)
	report.call(bool(lap["maximize"]) and bool(lap125["maximize"]) and not bool(lap100["maximize"]) and not bool(big["maximize"]),
		"Windows' display scale counts: 1920x1080 at 150%% and 125%% open maximized, at 100%% a window; a 4K screen at 150%% a window (%s)" % str(big.get("size")))
	## v2.3's sum for the 1366×768 laptop, for the record: 1180×720 placed at y=4, its title bar above the screen
	var old_h: float = minf(728 * 0.85, 1366 * 0.85 / 1.6)
	var old := Vector2i(int(old_h * 1.6), int(old_h)).max(Vector2i(1180, 720)).min(Vector2i(1366, 728))
	report.call(old.y + DECO.y > 728, "(before v2.5 a 1366x768 screen got a %s window, %d tall with its title bar under 728)" % [str(old), old.y + DECO.y])


func _renderer(report: Callable) -> void:
	## a PC without Vulkan or Direct3D 12 still starts the game, on OpenGL (the Compatibility renderer)
	var gl: bool = bool(ProjectSettings.get_setting("rendering/rendering_device/fallback_to_opengl3", false))
	var d3d: bool = bool(ProjectSettings.get_setting("rendering/rendering_device/fallback_to_d3d12", false))
	var angle: bool = bool(ProjectSettings.get_setting("rendering/gl_compatibility/fallback_to_angle", false))
	report.call(gl and d3d and angle, "the renderer falls back: Vulkan to Direct3D 12 to OpenGL, and OpenGL to ANGLE (%s, %s, %s)" % [d3d, gl, angle])
