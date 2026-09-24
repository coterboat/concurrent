## Client session: seats, hotseat, orders, save/replay, a whole game. No UI.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Hash := preload("res://engine/hash.gd")


func _new(tree: SceneTree, cfg: Dictionary) -> Node:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game(cfg)
	return s


func run(report: Callable, tree: SceneTree) -> void:
	_solo(report, tree)
	_hotseat(report, tree)
	_watch(report, tree)


func _solo(report: Callable, tree: SceneTree) -> void:
	var s: Node = _new(tree, {"map": "res://maps/known24.json", "seed": 4242, "length": "short", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Oren", "kind": "ai", "ai": "oren"},
		{"id": "green", "name": "Quill", "kind": "ai", "ai": "quill"}]})
	report.call(s.phase == Session.Phase.OPENING and s.planner == "red", "solo game opens on the human's deployment")
	report.call(s.income_total() == 22 - 8, "3p Known World: 22 pool, 8 dealt, 14 to place (got %s)" % s.income_total())
	var mine := MapLib.player_territory_ids(s.world, "red")
	var cap: int = s.place_cap(mine[0])
	for i in cap:
		s.add_place(mine[0], 1)
	report.call(s.add_place(mine[0], 1) != "", "placing past the opening ceiling explains why")
	s.auto_deploy()
	report.call(s.income_left() == 0 or s.placed_total() > cap, "auto-place spends the pool")
	s.lock()
	report.call(s.phase == Session.Phase.CINEMA and not s.events.is_empty(), "deployment plays as a cinema")
	s.cinema_done()
	report.call(s.phase == Session.Phase.PLANNING and s.world.round == 1, "round 1 planning")
	report.call(s.set_regroup(mine[0], mine[1] if mine.size() > 1 else mine[0]) != "", "no moves on round 1")
	## attack from the fattest land into any neighbor
	var best := ""
	for t in MapLib.player_territory_ids(s.world, "red"):
		if best == "" or s.world.get_territory(t).armies > s.world.get_territory(best).armies:
			best = t
	var target := ""
	for n in MapLib.neighbors(s.map, best):
		if s.world.get_territory(n).owner != "red":
			target = n
	if target != "":
		report.call(s.set_attack(best, target) == "", "attack order accepted")
		var p: Types.Packet = s.sheet().packets[0]
		report.call(p.strength == s.max_send(best, 0) and p.strength >= 1, "default strength is everyone who can march")
		report.call(s.projected_world().get_territory(best).armies == 1, "the origin shows 1 left at home the moment you order")
		s.set_packet_strength(0, 999)
		report.call(p.strength == s.max_send(best, 0), "strength clamps to what can march")
	s.auto_deploy()
	var err: String = s.lock()
	report.call(err == "", "a legal sheet seals (%s)" % err)
	report.call(s.phase == Session.Phase.CINEMA, "round resolves into the cinema")
	report.call(s.world.round == 2 and s.history.size() == 2, "round 2 and two history snapshots")
	report.call(Session.has_save(), "autosave written after the round")
	s.cinema_done()
	report.call(s.phase == Session.Phase.RECAP, "cinema -> recap")
	var hash_before: String = Hash.world_hash(s.world)
	## reload into a fresh session and compare
	var t: Node = Session.new()
	t.instant = true
	tree.root.add_child(t)
	report.call(t.load_save(), "save loads")
	report.call(Hash.world_hash(t.world) == hash_before, "replayed save matches the live world hash")
	report.call(t.phase == Session.Phase.PLANNING and t.planner == "red", "loaded game resumes at planning")
	t.queue_free()
	s.next_round()
	## play it out holding with auto-placement
	var guard := 0
	while s.phase != Session.Phase.GAME_OVER and guard < 60:
		guard += 1
		match s.phase:
			Session.Phase.PLANNING:
				s.auto_deploy()
				s.lock()
			Session.Phase.CINEMA:
				s.cinema_done()
			Session.Phase.RECAP:
				s.next_round()
			_:
				break
	report.call(s.phase == Session.Phase.GAME_OVER and s.winner != "", "the short game reaches game over (%s)" % s.winner)
	report.call(not Session.has_save(), "a finished game clears the save")
	report.call(s.standings().size() == 3, "standings list every seat")
	s.queue_free()


func _hotseat(report: Callable, tree: SceneTree) -> void:
	var s: Node = _new(tree, {"map": "res://maps/knife7.json", "seed": 7, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Son", "kind": "human", "ai": ""}]})
	report.call(s.phase == Session.Phase.PASS and s.pass_to == "red", "hotseat starts with a pass screen for Dad")
	s.seated()
	report.call(s.phase == Session.Phase.OPENING, "seated -> Dad deploys")
	s.auto_deploy()
	s.lock()
	report.call(s.phase == Session.Phase.PASS and s.pass_to == "blue", "then pass to Son")
	s.seated()
	s.auto_deploy()
	s.lock()
	report.call(s.phase == Session.Phase.CINEMA, "both sealed -> deployment cinema")
	s.cinema_done()
	report.call(s.phase == Session.Phase.PASS and s.pass_to == "red", "round 1 opens with a pass to Dad")
	s.queue_free()
	Session.new().clear_save()


func _watch(report: Callable, tree: SceneTree) -> void:
	var s: Node = _new(tree, {"map": "res://maps/world30.json", "seed": 31, "length": "short", "seats": [
		{"id": "red", "name": "Varek", "kind": "ai", "ai": "varek"},
		{"id": "blue", "name": "Hask", "kind": "ai", "ai": "hask"},
		{"id": "green", "name": "Quill", "kind": "ai", "ai": "quill"}]})
	var guard := 0
	while s.phase != Session.Phase.GAME_OVER and guard < 80:
		guard += 1
		if s.phase == Session.Phase.CINEMA:
			s.cinema_done()
		elif s.phase == Session.Phase.RECAP:
			s.next_round()
		else:
			break
	report.call(s.phase == Session.Phase.GAME_OVER, "an all-AI war plays itself to the end")
	var cards := 0
	for e in s.history:
		pass
	for pid in ["red", "blue", "green"]:
		cards += int(s.stats[pid]["sets"])
	report.call(s.world.sets_cashed == cards and cards >= 0, "set trades are tallied (%s)" % cards)
	s.queue_free()
