## A first-time player's war, end to end, as Dad meets it (v2.5): the first launch on a fresh install,
## the settings set and kept, the tutorial begun, then the war the readme suggests (the Known World,
## Standard, against Captain Oren and Governor Quill, on the land), left mid-war from the pause menu, the
## game closed, opened again, the war picked up from Continue and played to its end. Runs in the editor
## build and inside the exported game, windowed. Its lines are facts: `WALK ok`, `WALK FAIL`.
##
## It plays in the REAL save slot and settings, so it refuses any user folder that isn't fresh. Give it
## one of its own through APPDATA (Windows keeps user:// under %APPDATA%\Godot\app_userdata):
##   APPDATA=<empty folder> godot --path . --script res://tools/first_war.gd -- step=1
##   APPDATA=<same folder> godot --path . --script res://tools/first_war.gd -- step=2
## and in the export, the pack inside the .exe run by the editor's Godot (the exported .exe itself doesn't
## run --script; tools/ isn't in the pack: give the file's own path):
##   APPDATA=<empty folder> godot --main-pack build/windows/CONCURRENT.exe --script <abs path>/tools/first_war.gd -- step=1
extends SceneTree

const Session := preload("res://game/core/session.gd")
const Counsel := preload("res://game/core/counsel.gd")

var _fails := 0
var _step := 1
var main: Control
var s: Node
var gs: Control
var st: Node ## Settings
var t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("step="):
			_step = int(a.trim_prefix("step="))
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
	print("WALK %s %s" % ["ok  " if cond else "FAIL", msg])


func _run() -> void:
	t0 = Time.get_ticks_msec()
	var udir := OS.get_user_data_dir()
	var fresh: bool = not FileAccess.file_exists("user://settings.cfg") and not FileAccess.file_exists("user://savegame.json") and not DirAccess.dir_exists_absolute("user://wars")
	if _step == 1 and not fresh:
		print("WALK refuses: %s isn't a fresh install (give it an empty folder through APPDATA)" % udir)
		quit(3)
		return
	if _step == 2 and not FileAccess.file_exists("user://savegame.json"):
		print("WALK refuses: %s has no war saved by step 1" % udir)
		quit(3)
		return
	print("WALK step %d in %s (%s, %s)" % [_step, udir, RenderingServer.get_current_rendering_method(), "the exported pack" if OS.get_cmdline_args().has("--main-pack") or OS.has_feature("template") else "the project"])
	st = root.get_node("Settings")
	change_scene_to_file("res://game/main.tscn")
	await _frames(40)
	main = current_scene
	s = main.session
	var win: Window = root
	var area: Rect2i = DisplayServer.screen_get_usable_rect(win.current_screen)
	print("WALK window %s at %s, mode %d, on a usable screen of %s" % [win.size, win.position, win.mode, area])
	ok(win.mode == Window.MODE_MAXIMIZED or area.encloses(Rect2i(win.get_position_with_decorations(), win.get_size_with_decorations())),
		"the window opens on the screen, title bar and all (%s at %s)" % [win.get_size_with_decorations(), win.get_position_with_decorations()])
	if _step == 1:
		await _first_launch()
	else:
		await _second_launch()
	print("WALK done, %d failed, %.0f s" % [_fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if _fails > 0 else 0)


# ------------------------------------------------------------------ step 1: the first launch

func _first_launch() -> void:
	var title: Control = main.current
	ok(_button(title, "First time? Play the Tutorial") != null and _button(title, "Continue") == null,
		"a fresh install's title offers the tutorial first, and nothing to continue")
	## the settings, through the panel: every volume down (this walk plays silent), battles fast
	main.open_settings()
	await _frames(10)
	for sl in main.settings_panel.find_children("*", "HSlider", true, false):
		(sl as HSlider).value = 0.0
	for ob in main.settings_panel.find_children("*", "OptionButton", true, false):
		var o: OptionButton = ob
		for i in o.item_count:
			if o.get_item_text(i) == "Fast":
				o.select(i)
				o.item_selected.emit(i)
	main.settings_panel.closed.emit()
	await _frames(5)
	var cfg := ConfigFile.new()
	ok(cfg.load("user://settings.cfg") == OK and float(cfg.get_value("prefs", "music", 1.0)) == 0.0 and str(cfg.get_value("prefs", "speed", "")) == "fast",
		"the settings are written as they're changed (music %s, speed %s)" % [str(cfg.get_value("prefs", "music", "?")), str(cfg.get_value("prefs", "speed", "?"))])
	## the tutorial begins, and is left at its first orders
	await _click(_button(main.current, "First time? Play the Tutorial"))
	await _frames(10)
	gs = main.current
	ok(gs != null and gs.get("session") != null and bool(s.config.get("tutorial", false)), "the title's button starts the tutorial")
	await _play_until(func(): return s.phase == Session.Phase.PLANNING and s.world.round >= 1, 180.0)
	ok(s.phase == Session.Phase.PLANNING, "the tutorial reaches its first orders (round %d)" % s.world.round)
	await _quit_to_title()
	ok(_button(main.current, "Continue") != null and _button(main.current, "Continue").text.contains("Isthmus"),
		"the tutorial is saved and offered on the title (%s)" % (_button(main.current, "Continue").text if _button(main.current, "Continue") else "no Continue"))
	## the war the readme suggests: New Game, the setup's defaults, Begin
	await _click(_button(main.current, "New Game"))
	await _frames(10)
	var setup: Control = main.current
	var seats: Array = setup.seats.map(func(x): return str(x["name"]))
	ok(str(setup.map_path).ends_with("known24.json") and seats.size() == 3 and seats.has("Captain Oren") and seats.has("Governor Quill") and str(setup.length) == "standard",
		"New Game opens on the readme's first war: the Known World, Standard, against %s" % ", ".join(seats.slice(1)))
	await _click(setup.begin_button)
	await _frames(10)
	var go: Button = _button(main, "Start the new war")
	ok(go != null and main.current == setup, "with the tutorial saved, Begin asks before it ends it (%s)" % ("asked" if go != null else "not asked"))
	await _click(go)
	await _frames(10)
	gs = main.current
	ok(s.map != null and s.map.id == "known24" and str(s.config.get("preset", "")) == "standard" and s.map.rules == 23,
		"the war begins on the Known World, Standard, rules %d" % (s.map.rules if s.map else -1))
	var built: bool = await _land_built()
	ok(built and gs.land_board.active(), "the board stands on the land (a fresh install's default)")
	await _play_until(func(): return s.phase == Session.Phase.PLANNING and s.world.round >= 3, 900.0)
	ok(s.phase == Session.Phase.PLANNING and s.world.round == 3, "two rounds played on the land, his battles opened and rolled (round %d)" % s.world.round)
	await _quit_to_title()
	var cont: Button = _button(main.current, "Continue")
	ok(cont != null and cont.text.contains("Known World") and cont.text.contains("round 3"), "quit from the pause menu, the title offers the war at round 3 (%s)" % (cont.text if cont else "no Continue"))
	_wars_kept(2)


# ------------------------------------------------------------------ step 2: the game opened again

func _second_launch() -> void:
	ok(float(st.get_value("music", 1.0)) == 0.0 and str(st.get_value("speed", "")) == "fast" and bool(st.get_value("seen_tutorial", false)),
		"the settings came back (music %s, speed %s, the tutorial seen)" % [str(st.get_value("music")), str(st.get_value("speed"))])
	var title: Control = main.current
	var cont: Button = _button(title, "Continue")
	ok(cont != null and cont.text.contains("Known World") and cont.text.contains("round 3") and _button(title, "First time?") == null,
		"opened again, the title offers the war at round 3 (%s)" % (cont.text if cont else "no Continue"))
	## F11: fullscreen and back
	st.set_value("fullscreen", true)
	await _frames(20)
	var full: bool = root.mode == Window.MODE_FULLSCREEN or root.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	st.set_value("fullscreen", false)
	await _frames(20)
	var area: Rect2i = DisplayServer.screen_get_usable_rect(root.current_screen)
	ok(full and root.mode != Window.MODE_FULLSCREEN and (root.mode == Window.MODE_MAXIMIZED or area.encloses(Rect2i(root.get_position_with_decorations(), root.get_size_with_decorations()))),
		"fullscreen and back, the window on the screen (mode %d, %s)" % [root.mode, root.get_size_with_decorations()])
	await _click(cont)
	await _frames(20)
	gs = main.current
	ok(s.world != null and s.world.round == 3 and s.map.id == "known24", "Continue picks the war up at round %d" % (s.world.round if s.world else -1))
	var built: bool = await _land_built()
	ok(built and gs.land_board.active(), "back on the land it was left on")
	await _play_until(func(): return s.phase == Session.Phase.GAME_OVER, 2400.0)
	ok(s.phase == Session.Phase.GAME_OVER, "the war plays to its end (round %d, %s won)" % [s.world.round, s.name_of(s.winner) if s.winner != "" else "nobody"])
	var guard := 0
	while not gs.game_over.visible and guard < 1200:
		guard += 1
		if gs.cutscene != null and gs.cutscene.visible and gs.cutscene.has_method("skip"):
			gs.cutscene.skip()
		await _frames(1)
	ok(gs.game_over.visible, "the ending is shown")
	await _click(_button(gs.game_over, "Main menu"))
	await _frames(20)
	ok(_button(main.current, "Continue") == null and not FileAccess.file_exists("user://savegame.json"), "back on the title, nothing left to continue")
	_wars_kept(2)


# ------------------------------------------------------------------ playing

func _play_until(done: Callable, secs: float) -> void:
	## the advisor's plan sealed every round, his own battles opened and rolled, every report read
	var th: Control = gs.theater
	var guard := 0
	var since := Time.get_ticks_msec() ## when the war last moved on
	var mark := ""
	var end: int = Time.get_ticks_msec() + int(secs * 1000.0)
	while not done.call() and Time.get_ticks_msec() < end:
		guard += 1
		await _frames(1)
		var claimed := 0
		if s.world != null:
			for t in s.world.territories.values():
				claimed += 1 if str(t.owner) != "" else 0
		var now: String = "%d|%d|%s|%s|%d|%s" % [s.phase, s.world.round if s.world else -1, s.plan_step, str(th._state) if th.visible else "-", claimed, str(gs.cinema._waiting) if gs.cinema.visible else "-"]
		if now != mark:
			since = Time.get_ticks_msec()
		mark = now
		if Time.get_ticks_msec() - since > 30000:
			ok(false, "the war stood still for 30 s at %s (the draft %s, rolling %s, seating %s, claim wait %s, whose turn %s)" % [mark, str(gs._draft_state), str(gs._seat_rolling),
				str(gs._seating), str(gs._claim_wait), str(s.draft_turn()) if s.phase == Session.Phase.DRAFT else "-"])
			return
		if gs._seating_now():
			gs._seat_skip()
			continue
		if gs.intro != null and gs.intro.visible and gs.intro.has_method("_done"):
			gs.intro._done()
		if gs.cutscene != null and gs.cutscene.visible and gs.cutscene.has_method("skip"):
			gs.cutscene.skip()
		if th.visible:
			if guard % 10 == 0:
				match str(th._state):
					"ready", "done":
						th.press()
					"call":
						th._answer("p")
			continue
		if guard % 15 != 0:
			continue
		match s.phase:
			Session.Phase.DRAFT:
				if s.is_human(s.draft_turn()):
					gs.draft_advise()
			Session.Phase.OPENING:
				if s.is_human(s.planner):
					s.auto_deploy()
					gs.primary_action()
			Session.Phase.PLANNING:
				if s.is_human(s.planner):
					Counsel.adopt(s, Counsel.draft(s))
					if s.plan_step != "orders":
						s.begin_orders()
					gs.primary_action()
					await _frames(4)
					var place: Button = _button(gs._modal, "Place them for me") if gs._modal != null and is_instance_valid(gs._modal) else null
					if place != null:
						ok(false, "round %d: SEAL asked about unplaced recruits after the advisor's plan" % s.world.round)
						await _click(place)
			Session.Phase.MANEUVER:
				if s.is_human(s.planner):
					gs.primary_action()
			Session.Phase.CINEMA:
				if gs.cinema.visible and not gs.cinema._waiting:
					gs.cinema.advance()
			Session.Phase.RECAP:
				if gs.recap.visible:
					gs.primary_action()


func _land_built() -> bool:
	var guard := 0
	while (gs.land == null or not gs.land.prepared) and guard < 1800:
		guard += 1
		await _frames(1)
	await _frames(30)
	return gs.land != null and gs.land.prepared


func _quit_to_title() -> void:
	## Esc, then the pause menu's Quit to title
	gs.open_menu()
	await _frames(6)
	await _click(_button(gs, "Quit to title"))
	await _frames(20)


func _wars_kept(n: int) -> void:
	var files: Array = []
	if DirAccess.dir_exists_absolute("user://wars"):
		for f in DirAccess.get_files_at("user://wars"):
			if f.ends_with(".json"):
				files.append(f)
	ok(files.size() == n, "%d wars kept in the wars folder (%s)" % [files.size(), ", ".join(files)])


# ------------------------------------------------------------------ the hand on the mouse

func _click(b: Control) -> void:
	if b == null:
		ok(false, "a button to click was missing")
		return
	var vp: Viewport = root
	var pos: Vector2 = vp.get_final_transform() * b.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	vp.push_input(mv)
	await _frames(2)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		vp.push_input(e)
		await _frames(1)


func _button(from: Node, words: String) -> Button:
	if from == null:
		return null
	for c in from.find_children("*", "Button", true, false):
		var b: Button = c
		if b.is_visible_in_tree() and b.text.contains(words):
			return b
	return null


func _frames(n: int) -> void:
	for i in maxi(1, n):
		await process_frame
