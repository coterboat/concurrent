## v1.6 in the real client: land cards on the table and a turn-in that flies into the
## recruits; a border clash that takes the loser's arrow off the map; the dice in their
## commanders' colours; and the end-of-war chart by armies with the card sets marked.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "off"
	Settings.data["speed"] = "fast"
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/known24.json", "seed": 61, "length": "short", "timer": 0, "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"},
		{"id": "green", "name": "Viceroy Ysolde", "kind": "ai", "ai": "ysolde", "portrait": "ysolde"}]})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	s.auto_deploy()
	s.lock()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 600:
		guard += 1
		if gs.cinema.visible:
			gs.cinema.skip()
		await p.frames(1)
	p.ok(s.map.rules >= 16, "a new game plays by v1.6 rules")
	## a hand of land cards: two naming our lands
	var mine: Array = Array(load("res://engine/map.gd").player_territory_ids(s.world, "red"))
	var theirs := ""
	for t in s.map.territory_ids():
		if s.world.get_territory(str(t)).owner == "blue":
			theirs = str(t)
	s.world.players["red"].cards = PackedStringArray(["sun@" + str(mine[0]), "moon@" + theirs, "star@" + str(mine[1]), "sun@" + theirs])
	s.changed.emit()
	await p.frames(4)
	gs.open_cards()
	await p.frames(10)
	var dlg: Control = null
	for c in gs.get_children():
		if c.has_method("_pick_best"):
			dlg = c
	p.ok(dlg != null, "the cards open on the table")
	dlg._pick_best()
	await p.frames(6)
	await snap("90_land_cards")
	var income0: int = s.income_total()
	dlg._turn()
	await p.frames(12)
	await snap("91_cards_flying")
	await p.get_tree().create_timer(0.9).timeout
	await snap("92_troops_waiting")
	p.ok(not is_instance_valid(dlg) or not dlg.is_inside_tree(), "turning in closes the table")
	p.ok(s.income_total() > income0 and s.card_bonus_lands().size() == 2, "the set adds recruits, and two free soldiers on our named lands")
	var sub: String = str(gs.roster._rows["red"]["sub"].text)
	p.ok(sub.contains("turned in") and sub.contains("1 card"), "the roster counts the cards turned in (%s)" % sub)
	## a border clash on the map: the loser's arrow leaves
	s.auto_deploy()
	s.begin_orders()
	var from := ""
	var to := ""
	for a in mine:
		for n in s.map.get_territory(str(a)).adjacent:
			if s.world.get_territory(str(n)).owner == "blue" and from == "":
				from = str(a)
				to = str(n)
	s.world.set_hex(from, "red", 20, 1)
	s.world.set_hex(to, "blue", 3, 1)
	s.drafts.clear()
	s.auto_deploy()
	s.begin_orders()
	s.set_attack(from, to, 19)
	s.lock()
	guard = 0
	var clash_seen := false
	var arrow_gone := false
	while gs.cinema.visible or guard < 30:
		guard += 1
		if guard > 3000:
			break
		var bt: Dictionary = gs.cinema.beats[gs.cinema.index] if gs.cinema.visible and gs.cinema.index >= 0 and gs.cinema.index < gs.cinema.beats.size() else {}
		if str((bt.get("event", {}) as Dictionary).get("kind", "")) == Types.EVENT_CLASH and gs.cinema._rolling <= 0.0 and not clash_seen:
			clash_seen = true
			await p.frames(8)
			await snap("93_clash_settled")
			var ev: Dictionary = bt["event"]
			var loser: String = str(ev["playerB"]) if str(ev["winnerId"]) == str(ev["playerA"]) else str(ev["playerA"])
			arrow_gone = true
			for o in gs.board.orders:
				if str(o.get("owner", "")) == loser and (str(o["to"]) == str(ev["hexA"]) or str(o["to"]) == str(ev["hexB"])):
					arrow_gone = false
		if gs.cinema.visible and not gs.cinema._waiting and gs.cinema._wait <= 0.0 and gs.cinema._rolling <= 0.0:
			gs.cinema.advance()
		await p.frames(1)
	p.log("clash seen: %s" % clash_seen)
	if clash_seen:
		p.ok(arrow_gone, "the loser of a border clash no longer marches on the map")
	## the end of the war: the chart by armies, with the sets marked
	s.cash_log = [{"round": 1, "pid": "red", "value": 4, "lands": []}, {"round": 1, "pid": "blue", "value": 6, "lands": []}]
	gs.game_over.show_result()
	await p.frames(10)
	var chart: Control = null
	for n in gs.game_over.find_children("*", "Control", true, false):
		if n.get("mode") != null and n.has_method("queue_redraw") and str(n.get("mode")) == "terr":
			chart = n
	p.ok(chart != null, "the end-of-war chart")
	if chart != null:
		chart.mode = "armies"
		chart.queue_redraw()
	await p.frames(6)
	await snap("94_chart_armies")


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
