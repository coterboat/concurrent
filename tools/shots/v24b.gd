## v2.4 in the real client, from the owner's play on v2.3.1 (10-21): a storm from two of a commander's
## own lands, its retreats and its even volleys; a battle that ends by itself once everyone has spoken;
## and one charge bugle.
##   (rules 22, an old save) Admiral Imre storms your Gate from Ridge and Harbor; his officers judge each
##   column alone and one falls back while the other fights on: that column visibly leaves the field,
##   its men come off his count ("4  ↩5"), and the line says which went and which fights on.
##   (rules 23) His columns fall back together, told as one retreat, and a melee's even volleys are
##   fired again on the table. Your own two columns are asked one at a time, the plate quoting both
##   together. Your won battle closes by itself after the last line, never waiting for Space; and the
##   charge is sounded once, on the land and on the painted field alike.
##   SHOT_DIR=/dir ./scripts/shot.sh v24b
extends RefCounted

const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const Telemetry := preload("res://engine/telemetry.gd")
const Session := preload("res://game/core/session.gd")
const Style := preload("res://game/core/style.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["speed"] = "fast"
	Settings.data["battle_land"] = true
	await _one_column_falls_back()
	await _together_and_fired_again()
	await _your_two_columns()
	await _ends_by_itself()
	await _howto()


# ------------------------------------------------------------------ helpers

func _start(seats: Array, seed: int) -> Array:
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/knife7.json", "seed": seed, "length": "standard", "timer": 0, "capitals": false, "fortune": false, "seats": seats})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 1200:
		guard += 1
		await p.frames(1)
	return [main, s, gs]


func _imre_attacks() -> Array:
	return [{"id": "red", "name": "Admiral Imre", "kind": "ai", "ai": "imre", "portrait": "imre"},
		{"id": "blue", "name": "You", "kind": "human", "ai": "", "portrait": "player"}]


func _you_attack() -> Array:
	return [{"id": "red", "name": "You", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"}]


func _stage(s: Node, ridge: int, harbor: int, gate: int) -> void:
	## red holds Ridge and Harbor, both on The Gate's border (and the north shore); blue holds The Gate
	var w: Types.World = s.world
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	w.set_hex("ridge", "red", ridge, 1)
	w.set_hex("harbor", "red", harbor, 1)
	w.set_hex("beacon", "red", 2, 1)
	w.set_hex("mill", "red", 2, 1)
	w.set_hex("gate", "blue", gate, 1)
	w.set_hex("docks", "blue", 2, 1)
	w.set_hex("quarry", "blue", 2, 1)
	s.drafts.clear()
	s.changed.emit()


func _storm(pid: String, a: int, b: int, stance: String) -> Types.Sheet:
	var sh := Types.Sheet.new()
	sh.player_id = pid
	for x in [["ridge", a], ["harbor", b]]:
		var pk := Types.Packet.new()
		pk.from_id = str(x[0])
		pk.to_id = "gate"
		pk.strength = int(x[1])
		pk.stance = stance
		sh.packets.append(pk)
	return sh


func _empty(pid: String) -> Types.Sheet:
	var sh := Types.Sheet.new()
	sh.player_id = pid
	return sh


func _seed_for(s: Node, sheets: Array, live: Array, want: Callable) -> bool:
	## the round's dice come from the match seed: dry-run the very round on the session's own world
	## until the dice give the fight this probe is about, then play it for real
	for k in range(1, 600):
		s.match_seed = 7000 + k
		var res: Dictionary = Resolve.resolve_round(s.world, s.map, sheets, s.match_seed, live)
		for e in res["events"]:
			if str(e.get("kind", "")) == Types.EVENT_MELEE and bool(want.call(e, res)):
				return true
	return false


func _fell_at(mel: Dictionary, k: int) -> int:
	for c in mel["fronts"][k].get("calls", []):
		if str(c["call"]) == Combat.CALL_FALL_BACK:
			return int(c["at"])
	return -1


func _refired(mel: Dictionary) -> bool:
	for salvo in mel.get("salvos", []):
		var seen := {}
		for v in salvo:
			if seen.has(int(v["i"])):
				return true
			seen[int(v["i"])] = true
	return false


func _ready_land(gs: Control) -> void:
	var lf: Control = gs.theater._land_field
	var guard := 0
	while not lf.prepared and guard < 600:
		guard += 1
		await p.frames(1)


func _into_battle(gs: Control, th: Control) -> void:
	var guard := 0
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	guard = 0
	while th._state == "idle" and guard < 600:
		guard += 1
		await p.frames(1)


func _land_of(th: Control, i: int) -> String:
	return th.session.hex_name(th._front_from(i))


func _notes(th: Control) -> Array:
	## the words over the table between throws (EVEN VOLLEYS ARE FIRED AGAIN)
	var out: Array = []
	for c in th.get_children():
		if c is Label and (c as Label).text == "EVEN VOLLEYS ARE FIRED AGAIN" and (c as Label).modulate.a > 0.05:
			out.append(c)
	return out


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)


# ------------------------------------------------------------------ the old save (rules 22)

func _one_column_falls_back() -> void:
	var r: Array = await _start(_imre_attacks(), 51)
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	s.map.rules = 22 ## a war begun before v2.4: each of his columns is judged alone
	s.config["rules"] = 22
	await _ready_land(gs)
	_stage(s, 8, 6, 9)
	var imre: Types.Sheet = _storm("red", 7, 5, Combat.STANCE_JUDGMENT)
	s.locked["red"] = imre
	var found: bool = _seed_for(s, [imre, _empty("blue")], ["blue"], func(e, _res):
		var f0: int = _fell_at(e, 0)
		var f1: int = _fell_at(e, 1)
		return f0 >= 0 and f1 >= 0 and f0 != f1)
	p.ok(found, "(rules 22, an old save) a seed where Imre's columns fall back one at a time, as Alex saw (seed %d)" % s.match_seed)
	s.lock()
	await _into_battle(gs, th)
	p.ok(th.visible and th._melee and th._one_commander(), "Imre storms your Gate from Ridge and Harbor: one battle, two of his columns")
	var beat_sub := ""
	for b in gs.cinema.beats:
		if bool(b.get("melee", false)):
			beat_sub = str(b.get("sub", ""))
	p.ok(beat_sub.contains("The columns from ") and beat_sub.contains(" fell back. "), "the battle report's line for it says who fell back too: \"%s\"" % beat_sub)
	var lf: Control = th._land_field
	var first := -1
	var first_ok := false
	var second_ok := false
	var count0 := ""
	var line0 := ""
	var line1 := ""
	var count1 := ""
	var edge0 := ""
	var line_px := 0.0
	var left_field := false
	var stays_field := false
	var result := ""
	var guard := 0
	while th.visible and guard < 20000:
		guard += 1
		var gone: Array = []
		for i in 2:
			if th._seen_calls.has("fell|%d" % i):
				gone.append(i)
		if first < 0 and gone.size() == 1:
			first = int(gone[0])
			var other: int = 1 - first
			await p.frames(12)
			line0 = th._sub.text
			count0 = th._count_a.text
			edge0 = th._odds_bar.edge
			var want_count: String = "%d  ↩%d" % [int(th._left[other]), int(th._left[first])]
			var want_line: String = "The column from %s falls back — the column from %s fights on" % [_land_of(th, first), _land_of(th, other)]
			first_ok = line0 == want_line and count0 == want_count and edge0.begins_with("%d attacker" % int(th._left[other])) and edge0.contains("on 1 front")
			line_px = Style.font("italic").get_string_size(line0, HORIZONTAL_ALIGNMENT_LEFT, -1, th._sub.get_theme_font_size("font_size")).x
			if lf.dio != null:
				left_field = bool(lf.dio.armies[first]["fled"])
				stays_field = not bool(lf.dio.armies[other]["fled"])
			await snap("v24b_01_one_column_falls_back")
		elif first >= 0 and gone.size() == 2 and line1 == "":
			await p.frames(12)
			line1 = th._sub.text
			count1 = th._count_a.text
			second_ok = line1 == "The column from %s falls back too: the attack is called off" % _land_of(th, 1 - first) and count1.begins_with("↩")
			await snap("v24b_02_the_rest_fall_back")
		match str(th._state):
			"ready":
				th.press()
			"done":
				if result == "":
					result = th._result.text
					await p.frames(30)
					await snap("v24b_03_imre_falls_back")
		await p.frames(1)
	p.ok(first >= 0 and first_ok, "one column falls back: the line names it and the one that fights on (\"%s\"), his count drops to the men still fighting with the others shown gone home (\"%s\"), and the odds count only them (\"%s\")" % [line0, count0, edge0])
	p.ok(line_px > 0.0 and line_px < 520.0, "the line is short enough to stay clear of a speaking face's words beside it (%.0f px)" % line_px)
	p.ok(left_field and stays_field, "on the land that column turns and leaves the field; the other stands")
	p.ok(second_ok, "the other falls back later, and the line says the attack is over (\"%s\", count \"%s\")" % [line1, count1])
	p.ok(result.begins_with("ADMIRAL IMRE FALLS BACK — ") and result.ends_with(" SAVED"), "the verdict is his retreat: \"%s\"" % result)
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


# ------------------------------------------------------------------ rules 23

func _together_and_fired_again() -> void:
	var r: Array = await _start(_imre_attacks(), 52)
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	p.ok(s.map.rules == 23, "a new game plays rules 23 (%d)" % s.map.rules)
	await _ready_land(gs)
	_stage(s, 8, 6, 9)
	var imre: Types.Sheet = _storm("red", 7, 5, Combat.STANCE_JUDGMENT)
	s.locked["red"] = imre
	var found: bool = _seed_for(s, [imre, _empty("blue")], ["blue"], func(e, _res):
		var f0: int = _fell_at(e, 0)
		return f0 >= 0 and f0 == _fell_at(e, 1) and f0 >= 6 and _refired(e))
	p.ok(found, "(rules 23) a seed where Imre's columns fall back together after a few exchanges, with an even volley fired again on the way (seed %d)" % s.match_seed)
	s.lock()
	await _into_battle(gs, th)
	var notes_seen := 0
	var note_taken := false
	var line := ""
	var count := ""
	var both_left := false
	var guard := 0
	while th.visible and guard < 20000:
		guard += 1
		var notes: Array = _notes(th)
		if not notes.is_empty():
			notes_seen += 1
			if not note_taken:
				note_taken = true
				await p.frames(10)
				await snap("v24b_04_even_volleys_fired_again")
		if line == "" and th._seen_calls.has("fell|0") and th._seen_calls.has("fell|1"):
			await p.frames(12)
			line = th._sub.text
			count = th._count_a.text
			if th._land_field.dio != null:
				both_left = bool(th._land_field.dio.armies[0]["fled"]) and bool(th._land_field.dio.armies[1]["fled"])
			await snap("v24b_05_together")
		if str(th._state) == "ready":
			th.press()
		await p.frames(1)
	p.ok(note_taken, "an even volley in the melee is fired again: the table says so as its throw comes (seen %d frames)" % notes_seen)
	var want: String = "Admiral Imre sounds the retreat: both columns fall back"
	p.ok(line == want, "his columns fall back together, told as one retreat (\"%s\")" % line)
	p.ok(count.begins_with("↩") and not count.contains("+") and both_left, "both leave the field, and his count shows them all gone home (\"%s\")" % count)
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


func _your_two_columns() -> void:
	var r: Array = await _start(_you_attack(), 53)
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	await _ready_land(gs)
	_stage(s, 8, 6, 9)
	s.locked["blue"] = _empty("blue")
	s.set_attack("ridge", "gate", 7)
	s.set_attack("harbor", "gate", 5)
	var mine: Types.Sheet = s.sheet()
	var found: bool = _seed_for(s, [mine, s.locked["blue"]], ["red"], func(e, res):
		return bool(e.get("pending", false)) and (res.get("pending", {}) as Dictionary).has("mine"))
	p.ok(found, "your storm from Ridge and Harbor comes to a call (seed %d)" % s.match_seed)
	s.lock()
	await _into_battle(gs, th)
	var asks: Array = []
	var plates: Array = []
	var after_first := ""
	var count_first := ""
	var priced := true
	var result := ""
	var guard := 0
	while th.visible and guard < 20000:
		guard += 1
		match str(th._state):
			"ready":
				th.press()
			"call":
				if asks.size() < 2:
					await p.frames(8)
					var pend: Dictionary = s.pending
					var m: Array = pend.get("mine", [])
					plates.append(th._odds.text)
					asks.append(str(pend.get("from", "")))
					if m.size() >= 2:
						var pr: float = Combat.fronts_capture_rate(m, int(pend.get("dTotal", pend["d"])), Combat.MODE_VOLLEYS, 0)
						priced = priced and th._odds.text.contains("%d%% to take it" % int(round(pr * 100.0)))
					await snap("v24b_%02d_your_call" % (6 + asks.size() - 1))
					th._answer(Combat.CALL_FALL_BACK)
					if asks.size() == 1:
						await p.frames(14)
						after_first = th._sub.text
						count_first = th._count_a.text
				else:
					th._answer(Combat.CALL_PRESS)
			"done":
				if result == "":
					result = th._result.text
		await p.frames(1)
	var a0: String = s.hex_name(asks[0]) if asks.size() > 0 else "?"
	var a1: String = s.hex_name(asks[1]) if asks.size() > 1 else "?"
	p.ok(asks.size() == 2 and asks[0] != asks[1], "you are asked column by column: first the column from %s, then the one from %s" % [a0, a1])
	p.ok(plates.size() == 2 and plates[0].begins_with("Your call for the column from %s · both columns together: " % a0) and priced,
		"the first plate names its column and quotes your two columns together, priced as two fronts: \"%s\"" % (plates[0] if not plates.is_empty() else ""))
	p.ok(after_first == "Your column from %s falls back — the column from %s fights on" % [a0, a1] and count_first.contains("↩"),
		"you send that one home: the line says so and that the other fights on (\"%s\"), and your count shows it gone (\"%s\")" % [after_first, count_first])
	p.ok(plates.size() == 2 and plates[1].begins_with("Your call for the column from %s · From here: " % a1),
		"the second plate is for the other column, alone now: \"%s\"" % (plates[1] if plates.size() > 1 else ""))
	p.ok(result.begins_with("YOU FALL BACK — ") and result.ends_with(" SAVED"), "both home, the verdict says so: \"%s\"" % result)
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)


# ------------------------------------------------------------------ the battle's end, and the bugle

func _ends_by_itself() -> void:
	## the lines are spoken (on a silent bus): Varek's at his defeat, and maybe the advisor's after it
	Settings.data["voices"] = 0.9
	Audio.apply_volumes()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Voice"), true)
	var r: Array = await _start(_you_attack(), 54)
	var main: Control = r[0]
	var s: Node = r[1]
	var gs: Control = r[2]
	var th: Control = gs.theater
	await _ready_land(gs)
	p.ok(is_equal_approx(Audio.gain("res://assets/audio/sfx/charge"), -9.1), "the charge bugle plays 3 dB under its measured level (%.1f dB, was -6.1)" % Audio.gain("res://assets/audio/sfx/charge"))
	_stage(s, 16, 2, 5)
	s.locked["blue"] = _empty("blue")
	s.set_attack("ridge", "gate", 15)
	Audio.tracing = true
	Audio.trace.clear()
	s.lock()
	await _into_battle(gs, th)
	await p.frames(90)
	var bugles: int = Audio.trace.filter(func(t): return str(t["kind"]) == "sfx" and str(t["name"]) == "charge").size()
	p.ok(th._on_land and bugles == 1, "on the land the charge is sounded once as the battle opens (%d)" % bugles)
	var done_at := -1
	var left_at := -1
	var talked := false
	var talking_when_left := false
	var hands_on := false
	var frame := 0
	var guard := 0
	while th.visible and guard < 20000:
		guard += 1
		frame += 1
		var st: String = str(th._state)
		if st == "ready" and done_at < 0:
			th.press()
		elif st == "call":
			th._answer(Combat.CALL_PRESS)
		elif st == "done" and done_at < 0:
			done_at = frame
			hands_on = th._hands_on()
			await snap("v24b_08_won_and_waiting_for_the_lines")
		if done_at >= 0 and left_at < 0:
			if Audio.voice_playing():
				talked = true
			if st != "done":
				left_at = frame
				talking_when_left = Audio.voice_playing() or Audio.voice_waiting()
		await p.frames(1)
	if done_at >= 0 and left_at < 0:
		left_at = frame
	var secs: float = float(left_at - done_at) / 60.0
	p.ok(done_at >= 0 and hands_on, "you take The Gate rolling your own dice, and still have men on the field (the battle used to wait for Space here)")
	p.ok(left_at > done_at and secs < 14.0 and not talking_when_left, "it moves on by itself %.1f s after the verdict, nobody cut off (a line was spoken: %s)" % [secs, str(talked)])
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)
	## and on the painted field
	Settings.data["battle_land"] = false
	r = await _start(_you_attack(), 55)
	main = r[0]
	s = r[1]
	gs = r[2]
	th = gs.theater
	_stage(s, 16, 2, 5)
	s.locked["blue"] = _empty("blue")
	s.set_attack("ridge", "gate", 15)
	Audio.trace.clear()
	s.lock()
	await _into_battle(gs, th)
	await p.frames(60)
	bugles = Audio.trace.filter(func(t): return str(t["kind"]) == "sfx" and str(t["name"]) == "charge").size()
	p.ok(not th._on_land and bugles == 1, "on the painted field, once too (%d)" % bugles)
	Audio.tracing = false
	gs.cinema.skip()
	main.queue_free()
	await p.frames(5)
	Settings.data["battle_land"] = true
	Settings.data["voices"] = 0.0
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Voice"), false)
	Audio.apply_volumes()


func _howto() -> void:
	## the rules book says it, and its pages still fit the 1440x900 screen (with v24-map's ranked
	## garrison shields, the shield is no longer always gold: the two pages that called it so)
	var HowTo: Script = load("res://game/ui/howto_screen.gd")
	var shot := 9
	for page in [["Battles", "An even volley on a front is fired again"], ["Press, reserves, or fall back", "They judge your columns in a melee together"],
			["Attack — and leave home", "the shield beside its number"], ["Digging in", "plain wood for the one man held back"]]:
		var idx := -1
		for i in HowTo.PAGES.size():
			if str(HowTo.PAGES[i][0]) == str(page[0]):
				idx = i
		var h: Control = HowTo.new()
		h.overlay = true
		h.start_page = maxi(0, idx)
		p.get_tree().root.add_child(h)
		await p.frames(12)
		var body: Label = h._body
		var bottom: float = body.get_global_rect().end.y
		p.ok(idx >= 0 and body.text.contains(str(page[1])) and bottom <= 900.0 and body.get_visible_line_count() >= body.get_line_count(),
			"How to Play, \"%s\", says it (\"%s\") and fits the screen (%d of %d lines shown, its text ends at y=%d)" % [page[0], page[1], body.get_visible_line_count(), body.get_line_count(), int(bottom)])
		await snap("v24b_%02d_howto" % shot)
		shot += 1
		h.queue_free()
		await p.frames(2)
