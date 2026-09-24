## Play a few vs-monkey rounds like a human. Print what felt wrong.
##   ./scripts/probe.sh play_rounds
extends RefCounted

const Session := preload("res://game/match_session.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Types := preload("res://engine/types.gd")
const Ascii := preload("res://tools/ascii.gd")


func run(p) -> void:
	var s: Node = Session.new()
	p.get_tree().root.add_child(s)
	s.new_game(true, 99)
	p.log("seed 99 vs monkey. opening as red.")
	_fill_opening(s)
	p.log(Ascii.render(s.view_world(), s.map, "red"))
	s.lock()
	p.ok(s.phase == Session.Phase.PLANNING, "opening locked into round 1")
	var rounds := 0
	var notes: Array = []
	while s.phase != Session.Phase.GAME_OVER and rounds < 4:
		if s.phase == Session.Phase.PLANNING:
			rounds += 1
			p.log("—— round %s planning ——" % s.world.round)
			_plan_like_human(s, notes)
			p.log(Ascii.render_sheet(s.current_sheet()))
			if s.error_text != "":
				notes.append("pre-lock error r%s: %s" % [s.world.round, s.error_text])
			s.lock()
			if s.error_text != "":
				notes.append("LOCK failed r%s: %s" % [s.world.round, s.error_text])
				p.fail("lock failed: %s" % s.error_text)
				break
		elif s.phase == Session.Phase.CINEMA:
			p.log(s.cinema_caption())
			s.cinema_skip()
		elif s.phase == Session.Phase.RECAP:
			p.log("BOARD %s" % s.recap_title())
			for line in s.recap_lines():
				p.log("  %s" % line)
			s.cinema_skip()
		elif s.phase == Session.Phase.HOTSEAT:
			p.fail("vs-monkey hotseat")
			break
		else:
			break
	p.log(Ascii.render(s.view_world(), s.map, "red"))
	p.ok(rounds >= 3, "played %s full rounds" % rounds)
	if notes.is_empty():
		p.log("no lock/error notes")
	else:
		for n in notes:
			p.log("NOTE %s" % n)
	s.queue_free()
	await p.frames(1)


func _fill_opening(s: Node) -> void:
	var owned: PackedStringArray = MapLib.player_territory_ids(s.world, "red")
	for terr_id in owned:
		while s.pool_left() > 0:
			var cap: int = Income.cap_of(s.world, s.map, terr_id)
			var cur: int = int(s.opening["red"].get(terr_id, 0))
			if cur >= cap:
				break
			s.add_place_on(terr_id, 1)
			if s.error_text != "":
				break


func _plan_like_human(s: Node, notes: Array) -> void:
	var owned: PackedStringArray = MapLib.player_territory_ids(s.world, "red")
	## Place on hexes that touch an enemy, then anywhere with room.
	for terr_id in owned:
		if s.income_left() <= 0:
			break
		if not _touches_enemy(s, terr_id):
			continue
		_fill_place(s, terr_id)
	for terr_id in owned:
		if s.income_left() <= 0:
			break
		_fill_place(s, terr_id)
	## Walk queued place / standing toward a thin friend.
	for terr_id in owned:
		for n in MapLib.neighbors(s.map, terr_id):
			var ts = s.world.get_territory(n)
			if ts == null or ts.owner != "red":
				continue
			if s.max_friendly_from(terr_id, n) < 1:
				continue
			if s.display_armies(n) <= s.display_armies(terr_id):
				s.regroup_to(terr_id, n)
				if s.error_text != "":
					notes.append("move %s→%s: %s" % [terr_id, n, s.error_text])
				break
	## Attack the weakest neighbor we can legally hit.
	for terr_id in owned:
		if s.max_send_from(terr_id) < 1:
			continue
		var best := ""
		var best_n := 999
		for n in MapLib.neighbors(s.map, terr_id):
			var ts = s.world.get_territory(n)
			if ts == null or ts.owner == "red":
				continue
			if ts.armies < best_n:
				best_n = ts.armies
				best = n
		if best != "":
			s.attack_to(terr_id, best)
			if s.error_text.begins_with("must leave"):
				notes.append("attack %s→%s: %s" % [terr_id, best, s.error_text])


func _fill_place(s: Node, terr_id: String) -> void:
	var cap: int = Income.cap_of(s.world, s.map, terr_id)
	while s.income_left() > 0:
		var cur: int = int(s.current_sheet().placements.get(terr_id, 0))
		if cur >= cap:
			return
		s.add_place_on(terr_id, 1)
		if s.error_text != "":
			return


func _touches_enemy(s: Node, terr_id: String) -> bool:
	for n in MapLib.neighbors(s.map, terr_id):
		var ts = s.world.get_territory(n)
		if ts != null and ts.owner != "red" and ts.owner != Types.UNOCCUPIED:
			return true
	return false
