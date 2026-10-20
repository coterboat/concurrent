## v2.3 the handoff: the tutorial played start to finish the way a first-time player meets it, on
## the defaults a fresh install has (the board and the battles on the land, his own battles opened,
## his own dice to throw), with real clicks for the title's button, every recruit placed and every
## attack ordered. Each lesson has to come up when its moment comes, every battle of his has to open
## on the land and close, every sound the war asks for has to exist, and the war has to reach its
## ending and give back the title with nothing left to continue.
##   SHOT_DIR=/dir ./scripts/shot.sh v23
extends RefCounted

const Session := preload("res://game/core/session.gd")
const MapLib := preload("res://engine/map.gd")
const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")

var p
var vp: Viewport
var main: Control
var s: Node
var gs: Control
var lessons := {} ## lesson key -> the round it was first shown in
var _shot_round := {}


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	vp = p.get_viewport()
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	## a fresh install's defaults (settings.gd), but quick
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = true
	Settings.data["tips"] = true
	Settings.data["speed"] = "fast"
	Audio.tracing = true
	Audio.trace.clear()
	main = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(30)
	var btn: Button = _button(main.current, "Tutorial")
	p.ok(btn != null and btn.is_visible_in_tree(), "the title offers the tutorial (%s)" % (btn.text if btn else "none"))
	await snap("01_title")
	if btn == null:
		return
	await _click_at(btn.get_global_rect().get_center())
	await p.frames(10)
	gs = main.current
	s = main.session
	p.ok(bool(s.config.get("tutorial", false)) and s.map.id == "knife7", "a click on it starts the tutorial on the Isthmus (%s)" % s.map.id)
	var guard := 0
	while (gs.land == null or not gs.land.prepared) and guard < 900:
		guard += 1
		await p.frames(1)
	p.ok(gs.land != null and gs.land.prepared and gs.land_board.on, "the board stands on the land (built in %d frames)" % guard)
	await _play_war()
	await _ending()
	await _sounds()


func _play_war() -> void:
	var th: Control = gs.theater
	var battles_opened := 0
	var battles_closed := 0
	var was_open := false
	var fortune_called := false
	var guard := 0
	var last_phase := -1
	var placed_rounds := {}
	var ordered_rounds := {}
	var recap_rounds := {}
	var still := 0 ## frames with nothing moving: a player stuck with no way on is a failure
	var mark := ""
	while s.phase != Session.Phase.GAME_OVER and guard < 40000:
		guard += 1
		var ph: int = s.phase
		var now_mark: String = "%d|%d|%s|%s|%s" % [ph, s.world.round, s.plan_step, str(th._state) if th.visible else "-", str(gs.cinema._waiting) if gs.cinema.visible else "-"]
		still = still + 1 if now_mark == mark else 0
		mark = now_mark
		if still == 900:
			await snap("stuck")
			var open: Array = []
			for c in gs.get_children():
				if c is Control and (c as Control).visible and c != gs.board and c != gs.bar:
					open.append(str(c.name) + ":" + c.get_class())
			p.fail("the war stood still for 15 s at %s (showing: %s; modal: %s)" % [mark, ", ".join(open), str(gs._modal != null and is_instance_valid(gs._modal) and gs._modal.visible)])
			return
		if ph != last_phase:
			last_phase = ph
			await p.frames(8) ## let the phase's banner and counsel settle
		_note_lessons()
		var r: int = s.world.round
		match ph:
			Session.Phase.OPENING:
				if not placed_rounds.has(0):
					placed_rounds[0] = true
					await snap("02_deployment")
					await _place_all()
					p.ok(s.income_left() == 0, "deployment: every starting army placed by clicking (%d left)" % s.income_left())
					await p.frames(6)
					_note_lessons() ## all placed: the lesson says SEAL
					gs.primary_action()
			Session.Phase.PLANNING:
				if s.plan_step == "reinforce" and not placed_rounds.has(r):
					placed_rounds[r] = true
					await _place_all()
					await p.frames(4)
					_note_lessons()
					if r == 1:
						await snap("03_r1_placed")
					gs.primary_action() ## ORDERS
					await p.frames(6)
				elif s.plan_step == "orders" and not ordered_rounds.has(r):
					ordered_rounds[r] = true
					_note_lessons()
					var n: int = await _order_attacks(r)
					await p.frames(4)
					_note_lessons()
					if r == 1 or r == 3:
						await snap("04_r%d_orders" % r)
					p.log("round %d: %d attacks ordered" % [r, n])
					gs.primary_action() ## SEAL
					await p.frames(4)
					if gs._modal != null and is_instance_valid(gs._modal) and gs._modal.visible:
						p.fail("round %d: SEAL asked a question with everything placed" % r)
			Session.Phase.MANEUVER:
				gs.primary_action() ## no marches; seal them
			Session.Phase.CINEMA, Session.Phase.RESOLVING:
				if th.visible:
					if not was_open:
						was_open = true
						battles_opened += 1
						await p.frames(20)
						if battles_opened == 1:
							await snap("05_first_battle")
						p.ok(th._land_field != null and th._land_field.visible, "battle %d opened on the land" % battles_opened)
					if th._state == "ready":
						th.press() ## ROLL
					elif th._state == "call":
						if not fortune_called and th._btn_fortune.visible and not th._btn_fortune.disabled:
							fortune_called = true
							await p.frames(15) ## the plate fades in
							await snap("06_fortune_offered")
							var fb: Rect2 = th._btn_fortune.get_global_rect()
							p.ok(not th._help.visible and th._btn_fortune.is_visible_in_tree() and th._shout.modulate.a < 0.05,
								"Fortune offered: its button on the plate, uncovered by the dice help, and no shout across the plate (%s)" % str(fb))
							th._answer(Combat.CALL_FORTUNE)
						else:
							th._answer(Combat.CALL_PRESS)
					elif th._state == "done":
						th.press()
				else:
					if was_open:
						was_open = false
						battles_closed += 1
					if gs.cinema.visible and not gs.cinema._waiting:
						gs.cinema.advance()
			Session.Phase.RECAP:
				if not recap_rounds.has(r):
					recap_rounds[r] = true
					await p.frames(20)
					if r == 2:
						await snap("07_r1_report")
					p.ok(gs.recap.visible, "round %d's report is up" % (r - 1)) ## the world's round has moved on by then
					await p.frames(30)
					gs.primary_action() ## Space: the next round
		await p.frames(1)
	p.ok(s.phase == Session.Phase.GAME_OVER, "the war reached its end (round %d, %d frames)" % [s.world.round, guard])
	p.ok(battles_opened > 0 and battles_opened == battles_closed, "every battle of his opened and closed (%d opened, %d closed)" % [battles_opened, battles_closed])
	p.log("lessons seen: %s" % str(lessons))
	## every lesson whose moment the war reached (a war can end by conquest before its last rounds)
	var due := ["t-open", "t-open2", "t-r1a", "t-r1a2", "t-r1b", "t-r1c"]
	for rr in [2, 3]:
		if ordered_rounds.has(rr):
			due.append("t-r%d" % rr)
	if ordered_rounds.has(s.map.rounds):
		due.append("t-last")
	for k in due:
		p.ok(lessons.has(k), "lesson %s came up (round %s)" % [k, str(lessons.get(k, "never"))])
	var order_ok: bool = int(lessons.get("t-r1a", 99)) == 1 and int(lessons.get("t-r1b", 99)) == 1 \
		and (not ordered_rounds.has(2) or int(lessons.get("t-r2", 99)) == 2) and (not ordered_rounds.has(3) or int(lessons.get("t-r3", 99)) == 3)
	p.ok(order_ok, "each lesson in its own round (r1 placing and attacking, r2 digging in, r3 the surge; the war reached round %d of %d)" % [ordered_rounds.size(), s.map.rounds])


func _ending() -> void:
	var guard := 0
	while not gs.game_over.visible and guard < 900:
		guard += 1
		if gs.cutscene != null and gs.cutscene.visible and gs.cutscene.has_method("skip"):
			gs.cutscene.skip()
		await p.frames(1)
	await p.frames(40)
	await snap("08_game_over")
	p.ok(gs.game_over.visible, "the war's ending is shown (%s won)" % s.name_of(s.winner))
	var menu: Button = _button(gs.game_over, "Main menu")
	p.ok(menu != null, "the ending offers the main menu")
	if menu == null:
		return
	await _click_at(menu.get_global_rect().get_center())
	await p.frames(30)
	var cont: Button = _button(main.current, "Continue")
	p.ok(_button(main.current, "New Game") != null and cont == null, "back on the title, with no war left to continue")
	await snap("09_back_to_title")


func _sounds() -> void:
	var missing := {}
	var asked := {}
	for t in Audio.trace:
		var key: String = "%s:%s" % [t["kind"], t["name"]]
		asked[key] = int(asked.get(key, 0)) + 1
		if not bool(t["ok"]):
			missing[key] = true
	p.log("sounds asked for: %d kinds, %d requests" % [asked.size(), Audio.trace.size()])
	p.ok(missing.is_empty(), "every sound the war asked for exists (missing: %s)" % str(missing.keys()))
	for want in ["sfx:seal", "field:musket", "music:plan"]:
		p.ok(asked.has(want), "%s was played (%d times)" % [want, int(asked.get(want, 0))])
	## the mix (RV-006: a gain table nobody saw applied proves nothing): the levels are loaded, the loud
	## effects come down, the music playing now sits at its take's level, and the master bus has its limiter
	p.ok(Audio._levels.size() > 300 and Audio.gain("res://assets/audio/sfx/melee") < -5.0 and Audio.gain("res://assets/audio/music/ambience_tent") > 5.0,
		"the levels are in (%d sounds; melee %+.1f dB, the tent's bed %+.1f dB)" % [Audio._levels.size(), Audio.gain("res://assets/audio/sfx/melee"), Audio.gain("res://assets/audio/music/ambience_tent")])
	await p.frames(90) ## the ending's music has faded in
	var pl: AudioStreamPlayer = Audio._player_now
	var want_db: float = Audio.gain(Audio.MUSIC_DIR + Audio._take)
	p.ok(pl != null and pl.playing and absf(pl.volume_db - want_db) < 0.5, "the music now (%s) plays at its level: %.1f dB, wants %.1f" % [Audio._take, pl.volume_db if pl else 0.0, want_db])
	var lim := false
	var mb: int = AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(mb):
		lim = lim or AudioServer.get_bus_effect(mb, i) is AudioEffectHardLimiter
	p.ok(lim, "the master bus has its limiter")


func _note_lessons() -> void:
	var bar: Control = gs.bar
	for it in bar._items:
		var k: String = str(it.get("key", ""))
		if k.begins_with("t-") and not lessons.has(k):
			lessons[k] = s.world.round if s.world else 0


func _place_all() -> void:
	## click our lands, the front first, until every recruit is placed
	var guard := 0
	while s.income_left() > 0 and guard < 60:
		guard += 1
		var target := ""
		for t in MapLib.player_territory_ids(s.world, s.planner):
			if s.placed_on(t) >= s.place_cap(t):
				continue
			for n in MapLib.neighbors(s.map, t):
				if s.world.get_territory(n).owner != s.planner:
					target = t
		if target == "":
			target = MapLib.player_territory_ids(s.world, s.planner)[0]
		var before: int = s.income_left()
		await _click_land(target)
		await p.frames(2)
		if s.income_left() == before:
			## that land is full: try the others in turn
			for t in MapLib.player_territory_ids(s.world, s.planner):
				await _click_land(t)
				await p.frames(2)
				if s.income_left() < before:
					break
			if s.income_left() == before:
				break


func _order_attacks(r: int) -> int:
	## pick our strongest land beside an enemy and click it, then the enemy (as the lesson says)
	var made := 0
	for from in MapLib.player_territory_ids(s.world, s.planner):
		if s.max_send(from) < 2:
			continue
		var to := ""
		var weakest := 999
		for n in MapLib.neighbors(s.map, from):
			var ts: Types.TerritoryState = s.world.get_territory(n)
			if ts.owner != s.planner and ts.held() < weakest and s.packet_index(from, n) < 0:
				weakest = ts.held()
				to = n
		if to == "":
			continue
		gs.select("")
		await _click_land(from)
		await p.frames(2)
		await _click_land(to)
		await p.frames(3)
		if gs.order_card != null and gs.order_card.visible:
			gs.edit_order("", "") ## ✓ OK
		if s.packet_index(from, to) >= 0:
			made += 1
			if r == 3 and made == 1:
				## the lesson of round three: push on into the next land
				for n2 in MapLib.neighbors(s.map, to):
					if n2 != from and s.world.get_territory(n2).owner != s.planner:
						var err: String = s.set_surge(s.packet_index(from, to), n2)
						p.ok(err == "", "round 3: a surge on from %s into %s (%s)" % [s.hex_name(to), s.hex_name(n2), err])
						break
		if made >= 2:
			break
	return made


func _click_land(id: String) -> void:
	var b: Control = gs.board
	var pos: Vector2 = vp.get_final_transform() * (b.get_global_transform_with_canvas() * b.anchor(id))
	await _click_at(pos, false)


func _click_at(pos: Vector2, scaled: bool = true) -> void:
	if scaled:
		pos = vp.get_final_transform() * pos
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


func _button(root: Node, words: String) -> Button:
	if root == null:
		return null
	for c in root.find_children("*", "Button", true, false):
		var b: Button = c
		if b.is_visible_in_tree() and b.text.contains(words):
			return b
	return null


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
