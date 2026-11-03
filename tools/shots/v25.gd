## v2.5 the general pass before Dad's laptop (docs/v25/v25-pass.md), as facts on the screen:
## - every screen a new player meets fits, at the largest text the game offers, on a 1440×900 window
##   and on a 1366×768 laptop's maximized window (and the land draws that window's own pixels)
## - the window: a laptop's screen opens it maximized, its least size within the screen
## - a saved "Extra large" reads as Large, the most the screens hold
## - a new war asks before it takes the saved war's place; a save that can't be opened isn't offered
## - the land on the Compatibility renderer (OpenGL), in a second Godot: no near-black buildings, no grey sea
##   SHOT_DIR=/dir ./scripts/shot.sh v25
extends RefCounted

const Session := preload("res://game/core/session.gd")
const WindowFit := preload("res://game/core/window_fit.gd")
const Counsel := preload("res://game/core/counsel.gd")
const Setup := preload("res://engine/setup.gd")
const GlLook := preload("res://tools/probes/v25_gl.gd")
const Adapter := preload("res://game/world3d/adapter.gd")

var p
var main: Control


func run(probe) -> void:
	p = probe
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["speed"] = "fast"
	Settings.data["battles"] = "all"
	Settings.data["roll_yourself"] = true
	main = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	await _window()
	_text_size()
	await _fits(Vector2i(1366, 705), "laptop")
	await _fits(Vector2i(1440, 900), "1440")
	Settings.data["ui_scale"] = 1.0
	Settings.apply()
	p.get_window().size = Vector2i(1440, 900)
	await p.frames(5)
	Settings.data["land_quality"] = -1 ## (never measured: the next land starts where this machine's graphics say)
	await _new_war_asks()
	await _unreadable_save()
	await _vulkan_look()
	_compat()
	p.log("v25 probe done")


# ------------------------------------------------------------------ the window

func _window() -> void:
	var win: Window = p.get_window()
	WindowFit.apply(win, true, Rect2i(0, 0, 1366, 728))
	await p.frames(10)
	var deco: Vector2i = win.get_size_with_decorations() - win.size
	## (maximized as the window manager has it: on Windows; a bare X server, the bot's, has none to ask)
	var maxed: bool = win.mode == Window.MODE_MAXIMIZED or OS.get_name() != "Windows"
	p.ok(maxed and win.min_size.y + deco.y <= 728 and win.min_size.x + deco.x <= 1366,
		"on a 1366x768 laptop's screen the window opens maximized (mode %d), its least size %s inside it with the title bar" % [win.mode, str(win.min_size)])
	win.mode = Window.MODE_WINDOWED
	win.min_size = Vector2i(200, 200)
	win.size = Vector2i(1440, 900)
	await p.frames(10)


func _text_size() -> void:
	Settings.data["ui_scale"] = 1.3 ## a settings.cfg from before v2.5 ("Extra large")
	Settings.apply()
	p.ok(p.get_window().content_scale_factor <= Settings.UI_SCALE_MAX + 0.001, "a saved Extra large text reads as Large, the most the screens hold (%.2f)" % p.get_window().content_scale_factor)
	## a laptop's first launch reads Large; a desktop's, or a text size ever saved, is left as it is
	var kept: bool = Settings.ui_scale_kept
	Settings.data["ui_scale"] = 1.0
	Settings.ui_scale_kept = false
	main.first_text_size(false)
	var desk: float = float(Settings.data["ui_scale"])
	main.first_text_size(true)
	var lap: float = float(Settings.data["ui_scale"])
	Settings.data["ui_scale"] = 1.0
	main.first_text_size(true) ## (now kept: the laptop's pick was saved)
	var again: float = float(Settings.data["ui_scale"])
	p.ok(desk == 1.0 and lap == Settings.UI_SCALE_MAX and again == 1.0,
		"a first launch on a laptop's screen reads Large (%.2f), on a desktop's Normal (%.2f), and a text size once saved is the player's (%.2f)" % [lap, desk, again])
	Settings.ui_scale_kept = kept
	Settings.data["ui_scale"] = Settings.UI_SCALE_MAX
	Settings.apply()


# ------------------------------------------------------------------ every screen on the screen

func _fits(win_size: Vector2i, tag: String) -> void:
	## the largest text the game offers, on this window: nothing a player needs runs off the screen
	p.get_window().min_size = Vector2i(200, 200)
	p.get_window().size = win_size
	Settings.data["ui_scale"] = Settings.UI_SCALE_MAX
	Settings.apply()
	await p.frames(8)
	main.show_title()
	await p.frames(10)
	await _on_screen("%s title" % tag, "v25_%s_title" % tag)
	main.show_setup()
	await p.frames(10)
	await _on_screen("%s setup" % tag, "v25_%s_setup" % tag)
	main.open_settings()
	await p.frames(10)
	var opts: Array = []
	for ob in main.settings_panel.find_children("*", "OptionButton", true, false):
		var o: OptionButton = ob
		if o.item_count == 2 and o.get_item_text(1) == "Large":
			for i in o.item_count:
				opts.append(o.get_item_text(i))
	p.ok(opts == ["Normal", "Large"], "%s: Text size offers Normal and Large (%s)" % [tag, ", ".join(opts)])
	await _on_screen("%s settings" % tag, "v25_%s_settings" % tag)
	main.settings_panel.closed.emit()
	await p.frames(4)
	var HowTo: Script = load("res://game/ui/howto_screen.gd")
	var off_pages: Array = []
	for i in HowTo.PAGES.size():
		main.show_howto(i)
		await p.frames(6)
		var bad: Array = _off_screen()
		var hs: Control = main.current
		if not bad.is_empty() or hs._body.get_visible_line_count() < hs._body.get_line_count():
			off_pages.append(str(HowTo.PAGES[i][0]))
	p.ok(off_pages.is_empty(), "%s: all %d How to Play pages fit, their words and Previous/Next on the screen (%s)" % [tag, HowTo.PAGES.size(), ", ".join(off_pages) if not off_pages.is_empty() else "none off"])
	## the war: deployment, the orders with a land picked, the advisor's sheet, a battle, the report
	main.start_game({"map": "res://maps/known24.json", "seed": 25, "length": "standard", "timer": 0, "deal": "random", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
	await p.frames(10)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	var guard := 0
	while guard < 2000 and s.phase != Session.Phase.PLANNING:
		guard += 1
		if s.phase == Session.Phase.OPENING and s.is_human(s.planner):
			s.auto_deploy()
			s.lock()
		await p.frames(2)
	await p.frames(30)
	await _on_screen("%s the war's screen, reinforcements" % tag, "v25_%s_reinforce" % tag)
	var dial: Control = gs.bar.get("_dial")
	if dial != null:
		var vis: Rect2 = main.get_viewport().get_visible_rect()
		p.ok(vis.grow(2.0).encloses(dial.get_global_rect()), "%s: the dial (ORDERS, SEAL) is on the screen (%s in %s)" % [tag, str(Rect2i(dial.get_global_rect())), str(vis.size)])
	## the words (v2.5): the drawer's hint says what a click does in each step
	var hint_r: String = gs.drawer._hint_text()
	Counsel.adopt(s, Counsel.draft(s))
	if s.plan_step != "orders":
		s.begin_orders()
	await p.frames(10)
	var hint_o: String = gs.drawer._hint_text()
	p.ok(hint_r.contains("put a recruit there") and hint_r.contains("ORDERS") and not hint_r.contains("press +") and hint_o.contains("◀ Recruits") and not hint_o.contains("again"),
		"%s: the hint says what a click does: placing (\"%s\"), then the orders (\"%s\")" % [tag, hint_r.left(40), hint_o.left(40)])
	## ...and the last round's counsel keeps a guard at home (it said "spend every soldier")
	var r0: int = s.world.round
	s.world.round = Setup.rounds_for(s.map)
	var last: String = ""
	for it in Counsel.advice(s):
		if str(it["key"]) == "final":
			last = str(it["text"])
	s.world.round = r0
	p.ok(last.contains("keep enough at home") and not last.contains("spend every"), "%s: the last round's counsel: \"%s\"" % [tag, last])
	await _on_screen("%s the orders" % tag, "v25_%s_orders" % tag)
	s.lock()
	var th: Control = gs.theater
	var shot := false
	guard = 0
	while guard < 4000 and s.phase != Session.Phase.RECAP:
		guard += 1
		await p.frames(2)
		if th.visible and str(th._state) == "ready" and not shot:
			await p.frames(20)
			await _on_screen("%s a battle" % tag, "v25_%s_battle" % tag)
			shot = true
			th.press()
			await p.frames(10)
			gs.cinema.skip() ## (the rest of the round's battles unwatched: a slow box's hours)
		elif th.visible and str(th._state) in ["ready", "done"] and guard % 10 == 0:
			th.press()
		elif th.visible and str(th._state) == "call" and guard % 10 == 0:
			th._answer("p")
		if s.phase == Session.Phase.CINEMA and gs.cinema.visible and not gs.cinema._waiting and guard % 20 == 0:
			gs.cinema.advance()
	await p.frames(30)
	await _on_screen("%s the round's report" % tag, "v25_%s_report" % tag)
	if tag == "laptop":
		await _land_pixels(gs)


func _land_pixels(gs: Control) -> void:
	## a laptop's window: the land drawn at that window's own pixels, never more
	gs.toggle_land()
	var guard := 0
	while (gs.land == null or not gs.land.prepared) and guard < 1800:
		guard += 1
		await p.frames(1)
	await p.frames(30)
	var vp_size: Vector2i = gs.land._vp.size if gs.land != null else Vector2i.ZERO
	var win: Vector2i = p.get_window().size
	p.ok(gs.land_board.active() and absi(vp_size.x - win.x) <= 2 and absi(vp_size.y - win.y) <= 2,
		"on a %s window the land draws %s pixels (it drew the UI's %s before)" % [str(win), str(vp_size), str(Vector2i(main.get_viewport().get_visible_rect().size))])
	gs.toggle_land()
	await p.frames(5)


func _on_screen(what: String, shot: String) -> void:
	await RenderingServer.frame_post_draw
	var bad: Array = _off_screen()
	p.ok(bad.is_empty(), "%s: nothing a player needs runs off the screen (%s)" % [what, "; ".join(bad.slice(0, 3)) if not bad.is_empty() else "all on it"])
	p.log("%s: %s" % [what, _targets()])
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + shot + ".png")


func _targets() -> String:
	## the click targets, in the screen's own pixels: the smallest buttons a player has to hit here
	var k: float = main.get_viewport().get_final_transform().get_scale().y
	var sizes: Array = []
	for c in p.get_tree().root.find_children("*", "BaseButton", true, false):
		var b: BaseButton = c
		if b.is_visible_in_tree() and not b.disabled and b.modulate.a > 0.05 and b.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			var r: Rect2 = b.get_global_rect()
			if r.size.x > 2 and r.size.y > 2:
				var label: String = str(b.get("text")) if b.get("text") != null and str(b.get("text")) != "" else (str(b.tooltip_text) if b.tooltip_text != "" else b.get_class())
				sizes.append([r.size.y * k, r.size.x * k, label.left(18).replace(char(10), " ")])
	sizes.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for t in sizes.slice(0, 3):
		out.append("%.0fx%.0f '%s'" % [float(t[1]), float(t[0]), str(t[2])])
	return "%d buttons, the smallest %s (real px)" % [sizes.size(), ", ".join(out)]


func _off_screen() -> Array:
	## every visible control's box inside the screen (a backdrop as big as the screen is let off, and a
	## control a scroll or a clipping parent holds; 8 px of grace for a seal that hangs over an edge)
	var out: Array = []
	var vis: Rect2 = main.get_viewport().get_visible_rect()
	_walk(p.get_tree().root, vis.grow(8.0), out)
	return out


func _walk(n: Node, vis: Rect2, out: Array) -> void:
	if n is CanvasItem and (not (n as CanvasItem).visible or (n as CanvasItem).modulate.a < 0.05):
		return
	if n is ScrollContainer or (n is Window and n != p.get_window()):
		return
	if n is Control:
		var r: Rect2 = (n as Control).get_global_rect()
		var backdrop: bool = r.size.x >= vis.size.x * 0.9 and r.size.y >= vis.size.y * 0.9
		if r.size.x > 2 and r.size.y > 2 and not backdrop and not vis.encloses(r) and not _clipped(n as Control, vis):
			var txt: Variant = n.get("text")
			out.append("%s %s%s" % [n.get_class(), str(Rect2i(r)), (" '" + str(txt).left(20) + "'") if txt != null and str(txt) != "" else ""])
	for c in n.get_children():
		_walk(c, vis, out)


func _clipped(c: Control, vis: Rect2) -> bool:
	var q: Node = c.get_parent()
	while q != null:
		if q is Control and (q as Control).clip_contents:
			return vis.encloses((q as Control).get_global_rect())
		q = q.get_parent()
	return false


# ------------------------------------------------------------------ the saved war

func _new_war_asks() -> void:
	## a war is saved: the title's Tutorial and the setup's Begin ask before they end it
	main.start_game({"map": "res://maps/knife7.json", "seed": 25, "length": "short", "timer": 0, "deal": "random", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"}]})
	await p.frames(6)
	var s: Node = main.session
	main.current.intro._done()
	var guard := 0
	while guard < 2000 and s.phase != Session.Phase.PLANNING:
		guard += 1
		if s.phase == Session.Phase.OPENING and s.is_human(s.planner):
			s.auto_deploy()
			s.lock()
		await p.frames(2)
	var before: String = FileAccess.get_file_as_string(Session.SAVE_PATH)
	main.show_title()
	await p.frames(10)
	await _click(_button(main.current, "Tutorial"))
	await p.frames(8)
	var keep: Button = _button(main, "Keep my war")
	var asked: bool = keep != null and _button(main, "Start the tutorial") != null
	await _snap("v25_new_war_asks")
	await _click(keep)
	await p.frames(8)
	p.ok(asked and main.current.get_script() == load("res://game/ui/title_screen.gd") and FileAccess.get_file_as_string(Session.SAVE_PATH) == before,
		"a war is saved: the title's Tutorial asks first, and Keep my war keeps it (the save untouched)")
	main.show_setup()
	await p.frames(10)
	var setup: Control = main.current
	await _click(setup.begin_button)
	await p.frames(8)
	var go: Button = _button(main, "Start the new war")
	p.ok(go != null and main.current == setup, "and Begin the Campaign asks too")
	var chosen: String = str(setup.map_path).get_file().get_basename()
	await _click(go)
	await p.frames(10)
	p.ok(main.current != setup and s.map != null and s.map.id == chosen, "Start the new war starts it, on the map chosen (%s)" % (s.map.id if s.map else "none"))
	main.show_title()
	await p.frames(6)


func _unreadable_save() -> void:
	## a save the game can't pick up (here a round that doesn't replay, as a newer build's might not):
	## Continue takes it once, comes back with a line saying so, and sets it aside
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(Session.SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		p.fail("no save to spoil (%s)" % Session.SAVE_PATH)
		return
	var rec: Dictionary = d
	var bad_sheet := {"playerId": "red", "packets": [{"from": "nowhere", "to": "nowhere_else", "strength": 99}], "placements": {}}
	rec["sheets"] = [[bad_sheet]]
	var f := FileAccess.open(Session.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(rec))
	f.close()
	main.show_title()
	await p.frames(10)
	var cont: Button = _button(main.current, "Continue")
	p.ok(cont != null, "a save that reads but won't replay is still offered once (%s)" % (cont.text if cont else "no Continue"))
	await _click(cont)
	await p.frames(20)
	var aside: String = Session.SAVE_PATH.get_basename() + ".unreadable.json"
	var notice := false
	for l in main.current.find_children("*", "Label", true, false):
		if (l as Label).text.contains("couldn't be opened") and (l as Label).is_visible_in_tree():
			notice = true
	await _snap("v25_unreadable_save")
	p.ok(notice and _button(main.current, "Continue") == null and not Session.has_save() and FileAccess.file_exists(aside),
		"Continue on it comes back to the title with a line saying so, no Continue left, the save set aside (%s)" % aside.get_file())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(aside))
	main.show_title()
	await p.frames(5)


# ------------------------------------------------------------------ the land on each renderer

func _vulkan_look() -> void:
	## this renderer (Forward+ here) keeps the buildings' coat and the haze, as before v2.5
	Settings.data["map_land"] = true
	main.start_game({"map": "res://maps/known24.json", "seed": 25, "length": "standard", "timer": 0, "deal": "random", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
	await p.frames(10)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	var guard := 0
	while guard < 2000 and s.phase != Session.Phase.PLANNING:
		guard += 1
		if s.phase == Session.Phase.OPENING and s.is_human(s.planner):
			s.auto_deploy()
			s.lock()
		await p.frames(2)
	guard = 0
	while (gs.land == null or not gs.land.prepared) and guard < 1800:
		guard += 1
		await p.frames(1)
	await p.frames(60)
	Settings.data["map_land"] = false
	if gs.land == null or not gs.land.prepared:
		p.fail("the land was never built")
		return
	var weak: bool = Adapter.weak_here()
	p.ok(gs.land.quality == (2 if weak else 0) or (weak and gs.land.quality > 2),
		"a land this machine never measured starts at step %d on %s (%s): 0 on a graphics card, 2 on integrated graphics" % [gs.land.quality, RenderingServer.get_video_adapter_name(), "integrated" if weak else "a card"])
	var look: Dictionary = await GlLook.look_of(gs, gs.land, "v25_land_%s" % RenderingServer.get_current_rendering_method())
	p.log("on %s: %s" % [RenderingServer.get_current_rendering_method(), str(look)])
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		p.ok(int(look["coated"]) > 0 and bool(look["fog"]), "on %s the buildings keep their seating coat and the land its haze (%d coated)" % [RenderingServer.get_current_rendering_method(), int(look["coated"])])
	var sea: Color = look["sea"]
	p.ok(sea.b > sea.r + 0.04 and float(look["buildings"]) > 0.2, "here too the sea reads blue (%s) and the buildings stand in their colours (%.2f)" % [str(sea), float(look["buildings"])])


func _compat() -> void:
	## a second Godot on the Compatibility renderer (OpenGL), the path a PC without Vulkan or Direct3D 12 takes
	var out: Array = []
	var args := ["--rendering-driver", "opengl3", "--path", ProjectSettings.globalize_path("res://"), "res://tools/probe.tscn", "--", "--script=res://tools/probes/v25_gl.gd"]
	var code: int = OS.execute(OS.get_executable_path(), args, out, true)
	var text: String = "\n".join(out)
	var facts := 0
	for line in text.split("\n"):
		if line.begins_with("PROBE ok") or line.begins_with("PROBE FAIL"):
			facts += 1
			p.ok(line.begins_with("PROBE ok"), "OpenGL: " + line.substr(10).strip_edges())
		elif line.begins_with("PROBE on "):
			p.log("OpenGL: " + line.substr(6))
	p.ok(code == 0 and facts >= 4 and not text.contains("SCRIPT ERROR"), "the OpenGL game ran its %d checks and closed cleanly (exit %d)" % [facts, code])


# ------------------------------------------------------------------ the hand on the mouse

func _click(b: Control) -> void:
	if b == null:
		p.fail("a button to click was missing")
		return
	var vp: Viewport = p.get_viewport()
	var pos: Vector2 = vp.get_final_transform() * b.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	vp.push_input(mv)
	await p.frames(2)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		vp.push_input(e)
		await p.frames(1)


func _button(from: Node, words: String) -> Button:
	if from == null:
		return null
	for c in from.find_children("*", "Button", true, false):
		var b: Button = c
		if b.is_visible_in_tree() and b.text.contains(words):
			return b
	return null


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
