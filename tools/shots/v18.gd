## v1.8 in the real client: naming your capital at deployment (the crown on the map and the
## card's button), a capital falling in the report, and the spoils fix — once your defenders
## are gone, the victors' fight over your land no longer waits on you to roll their dice.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Style := preload("res://game/core/style.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["speed"] = "fast"
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)

	## --- the rules: presets and the Customize card
	main.show_setup()
	await p.frames(10)
	var setup: Control = main.current
	setup.rules = load("res://game/core/rules.gd").values_of("standard")
	setup._refresh_rules()
	setup._open_custom()
	await p.frames(10)
	await snap("00_rules_custom")
	setup.rules["levee"] = 0
	setup._refresh_rules()
	p.ok(load("res://game/core/rules.gd").preset_of(setup.rules) == "custom" and setup._rules_pick.selected == 3, "changing a rule makes it Custom")
	setup.rules = load("res://game/core/rules.gd").values_of("classic")
	setup._refresh_rules()
	p.ok(setup._rules_pick.selected == 2, "and the presets are recognised (Classic)")
	setup.rules = load("res://game/core/rules.gd").values_of("standard")
	setup._refresh_rules()

	## --- deployment: name the capital
	main.start_game({"map": "res://maps/known24.json", "seed": 23, "length": "standard", "timer": 0, "capitals": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
	await p.frames(8)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	await p.frames(10)
	p.ok(s.capital_choosable(), "deployment asks for a capital")
	var auto: String = s.capital_shown("red")
	p.ok(auto != "" and gs.board.capital_override.get("red", "") == auto, "the advisor pencils one in, and the map crowns it (%s)" % auto)
	var mine: Array = Array(MapLib.player_territory_ids(s.world, "red"))
	mine.sort()
	var other: String = ""
	for t in mine:
		if str(t) != auto:
			other = str(t)
			break
	gs.select(other)
	await p.frames(8)
	var btn: Button = _find_button(gs.land_card, "capital")
	p.ok(btn != null, "the land card offers 'Make this our capital'")
	if btn != null:
		btn.pressed.emit()
	await p.frames(8)
	await snap("01_capital_chosen")
	p.ok(s.capital_shown("red") == other and gs.board.capital_override.get("red", "") == other, "the crown moves to %s" % other)
	s.auto_deploy()
	s.lock()
	await p.frames(30)
	await snap("02a_armies_deploy")
	gs.cinema.skip()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 1200:
		guard += 1
		await p.frames(1)
	await p.frames(10)
	var all := true
	for pid in ["red", "blue", "green"]:
		var c: String = s.world.players[pid].capital
		if c == "" or s.world.get_territory(c).owner != pid:
			all = false
	p.ok(all and s.world.players["red"].capital == other, "after deployment every commander has a capital, ours where we put it")
	gs.select(other)
	await p.frames(8)
	await snap("02_capitals_on_the_map")

	## --- the spoils: we defend alone against two, and lose; they fight over it without us
	main.start_game({"map": "res://maps/knife7.json", "seed": 41, "length": "standard", "timer": 0, "capitals": false, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
	await p.frames(6)
	s = main.session
	gs = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(10)
	var w: Types.World = s.world
	w.set_hex("ridge", "blue", 15, 1)
	w.set_hex("beacon", "blue", 3)
	w.set_hex("mill", "blue", 3)
	w.set_hex("gate", "red", 2, 1)
	w.set_hex("harbor", "red", 4, 1)
	w.set_hex("docks", "green", 14, 1)
	w.set_hex("quarry", "green", 3)
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	var bs := Types.Sheet.new()
	bs.player_id = "blue"
	var bp := Types.Packet.new()
	bp.from_id = "ridge"
	bp.to_id = "gate"
	bp.strength = 13
	bp.stance = "hold"
	bs.packets = [bp]
	var gsh := Types.Sheet.new()
	gsh.player_id = "green"
	var gp := Types.Packet.new()
	gp.from_id = "docks"
	gp.to_id = "gate"
	gp.strength = 12
	gp.stance = "hold"
	gsh.packets = [gp]
	s.locked["blue"] = bs
	s.locked["green"] = gsh
	s.lock()
	var th: Control = gs.theater
	guard = 0
	while not th.visible and guard < 900:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(th.visible and th._melee, "two AIs storm our land: the melee opens")
	var kinds: Array = []
	for b in th._beats:
		kinds.append(str(b["event"]["kind"]))
	p.ok(kinds.has(Types.EVENT_SCRAMBLE), "and the fight for the spoils is part of the same field (%s)" % ", ".join(kinds))
	## we roll while our men stand; after that we touch nothing
	var ours := 0
	var theirs := 0
	var fell_at := -1
	guard = 0
	while th.visible and guard < 6000:
		guard += 1
		var standing: bool = th._human_standing()
		if fell_at < 0 and not standing and th._bi >= 0:
			fell_at = guard
		match str(th._state):
			"ready":
				if standing:
					th.press()
					ours += 1
			"done":
				if standing:
					th.press()
		if str(th._state) == "rolling" and not standing and th._scramble:
			theirs += 1
		await p.frames(1)
	p.ok(not th.visible and fell_at > 0, "once our defenders fell the field closed by itself (%d rolls pressed while we stood)" % ours)
	p.ok(theirs == 0, "we were never shown the victors' scramble to roll (%d frames of it)" % theirs)
	guard = 0
	while gs.cinema.visible and guard < 900:
		guard += 1
		if not gs.cinema._waiting:
			gs.cinema.advance()
		await p.frames(1)
	p.ok(s.world.get_territory("gate").owner != "red", "the map shows who took the spoils (%s)" % s.world.get_territory("gate").owner)

	## --- a capital falls in the report
	main.start_game({"map": "res://maps/knife7.json", "seed": 7, "length": "standard", "timer": 0, "capitals": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"}]})
	await p.frames(6)
	s = main.session
	gs = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(10)
	Settings.data["battles"] = "off"
	th = gs.theater
	w = s.world
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	w.set_hex("ridge", "red", 16, 1)
	w.set_hex("beacon", "red", 2, 1)
	w.set_hex("mill", "red", 2, 1)
	w.set_hex("gate", "blue", 1, 1)
	w.set_hex("harbor", "blue", 3, 1)
	w.set_hex("docks", "blue", 3, 1)
	w.set_hex("quarry", "blue", 3, 1)
	w.players["red"].capital = "beacon"
	w.players["blue"].capital = "gate"
	w.players["blue"].cards = PackedStringArray(["sun@harbor", "moon@docks"])
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("ridge", "gate", 15)
	var bsh := Types.Sheet.new()
	bsh.player_id = "blue"
	s.locked["blue"] = bsh
	s.lock()
	var saw := false
	guard = 0
	while guard < 2400 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.MANEUVER and s.phase != Session.Phase.PLANNING:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			var bb: Dictionary = gs.cinema.beats[gs.cinema.index] if gs.cinema.index < gs.cinema.beats.size() else {}
			if bb.has("capital_taken") and not saw:
				saw = true
				await p.frames(40)
				await snap("03_capital_falls")
			gs.cinema.advance()
		if th.visible and str(th._state) in ["ready", "done"]:
			th.press()
		await p.frames(1)
	p.ok(saw, "the report shows the capital falling")
	p.ok(s.world.players["blue"].capital != "gate" and s.world.players["red"].cards.size() == 1, "blue's court fled and we carried off one of their two cards")
	## --- Fortune: a bad exchange of ours, the plate offers the favour, T throws it again
	Settings.data["battles"] = "mine"
	main.start_game({"map": "res://maps/knife7.json", "seed": 5, "length": "standard", "timer": 0, "capitals": false, "fortune": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"}]})
	await p.frames(6)
	s = main.session
	gs = main.current
	th = gs.theater
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(10)
	w = s.world
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	w.set_hex("ridge", "red", 12, 1)
	w.set_hex("beacon", "red", 2, 1)
	w.set_hex("mill", "red", 2, 1)
	w.set_hex("gate", "blue", 9, 1)
	w.set_hex("harbor", "blue", 3, 1)
	w.set_hex("docks", "blue", 3, 1)
	w.set_hex("quarry", "blue", 3, 1)
	w.players["red"].fortune = 2
	w.players["blue"].fortune = 0
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	## find a seed whose first exchange goes badly for us
	var Resolve = load("res://engine/resolve.gd")
	var found := -1
	for sd in range(1, 300):
		var ra := Types.Sheet.new()
		ra.player_id = "red"
		var pk := Types.Packet.new()
		pk.from_id = "ridge"
		pk.to_id = "gate"
		pk.strength = 12
		pk.stance = "judgment"
		ra.packets = [pk]
		var rb := Types.Sheet.new()
		rb.player_id = "blue"
		rb.fortune_auto = true
		var rr: Dictionary = Resolve.resolve_round(w, s.map, [ra, rb], sd, ["red"])
		if rr.has("pending") and bool(rr["pending"].get("fortune", false)) and str(rr["pending"]["chooser"]) == "red" and int(rr["pending"].get("call", 0)) == 0:
			found = sd
			break
	p.ok(found > 0, "found a battle whose opening exchange goes badly for us (seed %d)" % found)
	s.match_seed = found
	s.set_attack("ridge", "gate", 12)
	var bl := Types.Sheet.new()
	bl.player_id = "blue"
	bl.fortune_auto = true
	s.locked["blue"] = bl
	s.lock()
	guard = 0
	var offered := false
	var thrown := false
	while guard < 9000 and not thrown:
		guard += 1
		if gs.cinema.visible and not gs.cinema._waiting:
			gs.cinema.advance()
		if th.visible:
			match str(th._state):
				"ready":
					th.press()
				"call":
					if th._btn_fortune.visible and not offered:
						offered = true
						await p.frames(12)
						await snap("04_fortune_offered")
						th._answer("F")
					elif not th._btn_fortune.visible:
						th._answer("p")
		if offered and str(th._shout.text).contains("FORTUNE") and th._shout.modulate.a > 0.5:
			thrown = true
			p.ok(th._a_left == 12 and th._b_left == 10, "the fallen stand again: the counts go back to 12 against 10 (%d, %d)" % [th._a_left, th._b_left])
			await p.frames(6)
			await snap("05_fortune_thrown")
		await p.frames(1)
	p.ok(offered, "the call plate offered ✦ Fortune after a bad exchange")
	p.ok(thrown, "and throwing it again showed on the field")
	var spent := false
	for e in s.events:
		for c in e.get("calls", []):
			if str(c.get("call", "")) == "F" and str(c.get("by", "")) == "red":
				spent = true
	p.ok(spent, "the favour is on the record as ours")
	p.log("v18 probe done")


func _find_button(root: Node, text: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if (c as Button).text.to_lower().contains(text):
			return c
	return null


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
