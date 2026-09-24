## G5 session smoke: vs-monkey hotseat skipped, cinema skip, game ends.
extends RefCounted

const Session := preload("res://game/match_session.gd")
const H := preload("res://tests/harness.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")


func run(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	tree.root.add_child(s)
	s.new_game(true, 42)
	report.call(s.phase == Session.Phase.OPENING, "G5 new vs-monkey starts at opening")
	report.call(s.selected != "", "G5 auto-selects an owned hex")
	var MapLib := preload("res://engine/map.gd")
	var first: String = s.selected
	var other := ""
	for terr_id in MapLib.player_territory_ids(s.world, "red"):
		if terr_id != first:
			other = terr_id
			break
	if other != "":
		s.select_hex(other)
		report.call(int(s.opening["red"].get(other, 0)) == 0, "G5 first click selects, does not place")
		s.select_hex(other)
		report.call(int(s.opening["red"].get(other, 0)) >= 1, "G5 second click on same hex places")
	s.add_place(1)
	var queued: int = int(s.opening["red"].get(s.selected, 0))
	report.call(queued >= 1, "G5 +/- places without a prior map click (queued %s on %s)" % [queued, s.selected])
	var before_place: int = 1
	report.call(s.display_armies(s.selected) == before_place + queued, "G5 map preview shows queued troops immediately")
	s.lock()
	report.call(s.phase == Session.Phase.PLANNING, "G5 monkey opening auto-locks blue")
	var plan_hex: String = s.selected
	var placed_before: int = int(s.current_sheet().placements.get(plan_hex, 0))
	s.select_hex(plan_hex)
	report.call(int(s.current_sheet().placements.get(plan_hex, 0)) == placed_before + 1, "G5 after opening, second click on selected hex places income")
	_attack_packet_labeled(report, s)
	_last_man(report, s)
	_plan_bugs(report, tree)
	_recap_and_teach(report, tree)
	_beacon_ridge_screenshot(report, tree)
	report.call(s.setup_dict.is_empty() == false, "G5 setup snapshot stored without waiting for a UI")
	report.call(not s.setup_dict.has("matchSeed"), "G5 setup still has no matchSeed")
	var guard := 0
	while s.phase != Session.Phase.GAME_OVER and guard < 40:
		guard += 1
		if s.phase == Session.Phase.PLANNING:
			s.hold_and_lock()
		elif s.phase == Session.Phase.CINEMA or s.phase == Session.Phase.RECAP:
			s.cinema_skip()
		elif s.phase == Session.Phase.HOTSEAT:
			report.call(false, "G5 vs-monkey should not hotseat")
			break
		else:
			break
	report.call(s.phase == Session.Phase.GAME_OVER, "G5 vs-monkey hold-fest reaches game over")
	report.call(str(s.winner) != "", "G5 winner is named")
	s.queue_free()


func _attack_packet_labeled(report: Callable, s: Node) -> void:
	var MapLib := preload("res://engine/map.gd")
	var Types := preload("res://engine/types.gd")
	for terr_id in MapLib.player_territory_ids(s.world, "red"):
		if s.max_send_from(terr_id) < 1:
			continue
		for n in MapLib.neighbors(s.map, terr_id):
			var ts = s.world.get_territory(n)
			if ts == null or ts.owner == "red":
				continue
			s.attack_to(terr_id, n)
			report.call(s.current_sheet().packets.size() == 1, "G5 attack creates a packet")
			var p = s.current_sheet().packets[0]
			report.call(p.from_id == terr_id and p.to_id == n and p.strength >= 1, "G5 packet names origin, dest, and send count")
			s.remove_packet_at(0)
			return
	report.call(true, "G5 no legal attack to label-test (skip)")


func _last_man(report: Callable, s: Node) -> void:
	var MapLib := preload("res://engine/map.gd")
	var Types := preload("res://engine/types.gd")
	var from_id := ""
	for terr_id in MapLib.player_territory_ids(s.world, "red"):
		if s.max_send_from(terr_id) < 1:
			from_id = terr_id
			break
	if from_id == "":
		report.call(true, "G5 no 1-stack to last-man test (skip)")
		return
	var enemy := ""
	var friend := ""
	for n in MapLib.neighbors(s.map, from_id):
		var ts = s.world.get_territory(n)
		if ts == null:
			continue
		if ts.owner == "red":
			friend = n
		elif ts.owner != Types.UNOCCUPIED or ts.armies == 0:
			enemy = n
	var before: int = s.display_armies(from_id)
	if enemy != "":
		s.attack_to(from_id, enemy)
		report.call(s.current_sheet().packets.is_empty(), "G5 cannot attack off a 1-stack")
	if friend != "":
		s.regroup_to(from_id, friend)
		report.call(s.current_sheet().regroup == null, "G5 cannot regroup the last man")
	report.call(s.display_armies(from_id) == before, "G5 last man still on %s" % from_id)
	report.call(s.world.get_territory(from_id).owner == "red", "G5 last man still owns %s" % from_id)


func _plan_bugs(report: Callable, tree: SceneTree) -> void:
	_duplicate_attack_merges(report, tree)
	_beacon_ridge_reinforcement(report, tree)
	_round1_move_lock(report, tree)
	_round2_standing_regroup(report, tree)


func _planning(tree: SceneTree, hexes: Dictionary, round: int = 1) -> Node:
	var s: Node = Session.new()
	tree.root.add_child(s)
	s.new_game(true, 1)
	s.world = H.paint(s.map, hexes)
	s.world.round = round
	s.phase = Session.Phase.PLANNING
	s.planner = "red"
	s.vs_monkey = true
	s.sheets = {"red": s._empty_sheet("red"), "blue": s._empty_sheet("blue")}
	s.locked = {"red": false, "blue": false}
	s.selected = ""
	s.send_amount = {}
	s.error_text = ""
	s.pending_surge_from = -1
	s._auto_select()
	return s


func _duplicate_attack_merges(report: Callable, tree: SceneTree) -> void:
	## Screenshot 1: Harbor → Gate twice must stay one packet.
	var s: Node = _planning(tree, {
		"harbor": ["red", 8],
		"docks": ["red", 5],
		"quarry": ["red", 1],
		"gate": ["neutral", 5],
		"beacon": ["blue", 1],
		"ridge": ["blue", 1],
		"mill": ["blue", 1],
	})
	s.attack_to("harbor", "gate")
	s.attack_to("harbor", "gate")
	report.call(s.current_sheet().packets.size() == 1, "same origin→dest attack is one packet, not two")
	if s.current_sheet().packets.size() == 1:
		var p = s.current_sheet().packets[0]
		report.call(p.from_id == "harbor" and p.to_id == "gate" and p.strength >= 1, "merged Harbor→Gate packet keeps origin, dest, strength")
		report.call(p.strength == s.send_for("harbor") or p.strength == s.max_send_from("harbor", 0), "Harbor→Gate strength is the send amount, not a leftover 1")
	s.send_amount["harbor"] = 1
	s.attack_to("harbor", "docks") ## docks is friendly — should refuse
	report.call(s.current_sheet().packets.size() == 1, "cannot add a second packet by attacking a friend")
	s.attack_to("harbor", "gate")
	report.call(s.current_sheet().packets.size() == 1, "second click on the same attack still one row")
	s.queue_free()


func _beacon_ridge_reinforcement(report: Callable, tree: SceneTree) -> void:
	## Screenshot 2: Beacon 1 standing + 2 placed = 3 on map. Send 2 to Ridge.
	var s: Node = _planning(tree, {
		"beacon": ["red", 1],
		"ridge": ["red", 1],
		"mill": ["red", 1],
		"gate": ["neutral", 5],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	s.add_place_on("beacon", 2)
	report.call(int(s.current_sheet().placements.get("beacon", 0)) == 2, "Beacon queued +2")
	report.call(s.display_armies("beacon") == 3, "Beacon map count is 3 (1 standing + 2 placed)")
	report.call(s.max_send_from("beacon") == 2, "Beacon attack send cap is 2 (leave 1)")
	report.call(s.send_cap("beacon") == 2, "Beacon stepper cap is 2, not 1")
	report.call(s.send_for("beacon") == 2, "Beacon default send is 2")
	report.call(s.max_move_from("beacon") == 0, "round 1 cannot regroup the 1-stack")
	report.call(s.max_friendly_from("beacon", "ridge") == 2, "Beacon can walk 2 placements to Ridge")
	s.regroup_to("beacon", "ridge")
	report.call(s.current_sheet().regroup == null, "round 1 move is not a kernel regroup")
	report.call(int(s.current_sheet().placements.get("beacon", 0)) == 0, "Beacon placements moved off")
	report.call(int(s.current_sheet().placements.get("ridge", 0)) == 2, "Ridge received the 2 reinforcements")
	report.call(s.display_armies("beacon") == 1, "Beacon keeps the garrison")
	report.call(s.display_armies("ridge") == 3, "Ridge shows the 2 that walked in")
	s.queue_free()


func _round1_move_lock(report: Callable, tree: SceneTree) -> void:
	## Screenshot 3: LOCK after a Beacon→Ridge reinforcement must succeed on round 1.
	var s: Node = _planning(tree, {
		"beacon": ["red", 1],
		"ridge": ["red", 1],
		"mill": ["red", 1],
		"gate": ["neutral", 5],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	s.add_place_on("beacon", 2)
	s.regroup_to("beacon", "ridge")
	s.lock()
	report.call(s.error_text == "", "round 1 reinforcement lock has no error (got: %s)" % s.error_text)
	report.call(s.current_sheet().regroup == null or s.phase != Session.Phase.PLANNING, "lock did not leave a round-1 regroup on the sheet")
	report.call(s.phase != Session.Phase.PLANNING or s.locked["red"] == true, "round 1 lock is accepted")
	s.queue_free()

	var stuck: Node = _planning(tree, {
		"beacon": ["red", 3],
		"ridge": ["red", 1],
		"mill": ["red", 1],
		"gate": ["neutral", 5],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	stuck.regroup_to("beacon", "ridge")
	report.call(stuck.current_sheet().regroup == null, "round 1 standing-only move does not write a regroup")
	stuck.lock()
	report.call(stuck.error_text == "" or not stuck.error_text.contains("regroup"), "standing-only round 1 move does not block lock with 'round 1 has no regroup'")
	stuck.queue_free()


func _round2_standing_regroup(report: Callable, tree: SceneTree) -> void:
	var s: Node = _planning(tree, {
		"beacon": ["red", 3],
		"ridge": ["red", 1],
		"mill": ["red", 1],
		"gate": ["neutral", 5],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	}, 2)
	report.call(s.max_move_from("beacon") == 2, "round 2 Beacon can regroup 2")
	s.regroup_to("beacon", "ridge")
	report.call(s.current_sheet().regroup != null, "round 2 move writes a regroup")
	if s.current_sheet().regroup != null:
		report.call(s.current_sheet().regroup.from_id == "beacon" and s.current_sheet().regroup.to_id == "ridge", "regroup is Beacon→Ridge")
		report.call(s.current_sheet().regroup.strength == 2, "regroup sends 2 (leave 1)")
	s.queue_free()


func _recap_and_teach(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	tree.root.add_child(s)
	s.new_game(true, 42)
	s.lock()
	while s.phase == Session.Phase.PLANNING:
		s.hold_and_lock()
	if s.phase == Session.Phase.CINEMA:
		s.cinema_skip()
	report.call(s.phase == Session.Phase.RECAP, "G6 cinema skip lands on the round board")
	report.call(s.recap_lines().size() > 0, "G6 recap has lines")
	report.call(s.telemetry_rounds.size() >= 1, "G6 round telemetry is stored")
	s.cinema_skip()
	s.queue_free()

	var t: Node = Session.new()
	tree.root.add_child(t)
	t.new_game(false, 7, true)
	report.call(t.teach, "G6 teach flag sticks")
	t.lock()
	report.call(t.phase != Session.Phase.HOTSEAT, "G6 teach skips hotseat after red opening")
	report.call(t.planner == "blue", "G6 teach hands the open sheet to blue")
	t.lock()
	report.call(t.phase == Session.Phase.PLANNING, "G6 teach opening both sides reaches round 1 planning")
	report.call(t.planner == "red", "G6 teach round 1 starts with red")
	t.lock()
	report.call(t.phase != Session.Phase.HOTSEAT, "G6 teach round 1 still skips hotseat")
	t.queue_free()

	var Telemetry := preload("res://engine/telemetry.gd")
	var Events := preload("res://engine/events.gd")
	var ev: Array = [
		Events.vacated("red", "ridge", "mill", 4, 0),
		Events.occupied("blue", "ridge", 2),
		Events.score({"red": 2, "blue": 4}, "blue"),
		Events.round_ended(1, "", false),
	]
	var sum: Dictionary = Telemetry.summarize_events(ev)
	report.call(int(sum.get("vacatePunish", 0)) == 1, "G6 telemetry counts a walk-in as vacate-punish")
	var rec: Dictionary = Telemetry.from_play({
		"mapId": "knife7",
		"matchSeed": 1,
		"vsMonkey": false,
		"teach": true,
		"rounds": [sum],
		"winner": "",
		"early": false,
		"hashes": ["deadbeef"],
	})
	report.call(str(rec.get("kind", "")) == "match" and int(rec.get("vacatePunish", 0)) == 1, "G6 match telemetry rolls up vacate-punish")


func _beacon_ridge_screenshot(report: Callable, tree: SceneTree) -> void:
	## Screenshot: Beacon 4 with +1, Ridge at cap +2, no silent migrate.
	var s: Node = _planning(tree, {
		"beacon": ["red", 3],
		"ridge": ["red", 1],
		"harbor": ["red", 2],
		"mill": ["blue", 2],
		"gate": ["neutral", 5],
		"quarry": ["blue", 2],
		"docks": ["blue", 3],
	})
	s.add_place_on("beacon", 1)
	s.add_place_on("ridge", 2)
	report.call(s.display_armies("beacon") == 4, "screenshot Beacon shows 4")
	report.call(s.max_friendly_from("beacon", "ridge") == 0, "Ridge at cap: no placement walk left")
	s.regroup_to("beacon", "ridge")
	report.call(s.current_sheet().regroup == null, "cap-blocked move writes no regroup")
	report.call(s.error_text.contains("cap") or s.error_text.contains("Ridge"), "cap-blocked move explains Ridge cap (got: %s)" % s.error_text)
	s.queue_free()

	var w: Node = _planning(tree, {
		"beacon": ["red", 3],
		"ridge": ["red", 1],
		"harbor": ["red", 2],
		"mill": ["blue", 2],
		"gate": ["neutral", 5],
		"quarry": ["blue", 2],
		"docks": ["blue", 3],
	})
	w.add_place_on("beacon", 2)
	report.call(w.max_friendly_from("beacon", "ridge") == 2, "Ridge has room for Beacon's +2")
	w.selected = "beacon"
	w.select_hex("ridge")
	report.call(int(w.current_sheet().placements.get("ridge", 0)) == 2, "map-click Ridge walks Beacon's queued place")
	report.call(int(w.current_sheet().placements.get("beacon", 0)) == 0, "Beacon queued place left with the walk")
	report.call(w.display_armies("beacon") == 3, "Beacon keeps standing garrison")
	report.call(w.display_armies("ridge") == 3, "Ridge shows the walked +2")
	w.queue_free()

	var a: Node = _planning(tree, {
		"ridge": ["red", 1],
		"beacon": ["red", 1],
		"mill": ["blue", 2],
		"gate": ["neutral", 5],
		"harbor": ["red", 2],
		"docks": ["blue", 3],
		"quarry": ["blue", 2],
	})
	a.add_place_on("ridge", 2)
	a.send_amount["ridge"] = 4
	a.selected = "ridge"
	a.select_hex("mill")
	if a.current_sheet().packets.size() == 1:
		var p = a.current_sheet().packets[0]
		report.call(p.strength <= a.max_send_from("ridge", 0), "Ridge→Mill cannot send more than leftover (%s vs cap)" % p.strength)
	else:
		report.call(a.current_sheet().packets.is_empty() or a.max_send_from("ridge") >= 1, "Ridge→Mill either refused or is legal")
	a.queue_free()
