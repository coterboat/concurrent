## v1.4 rules: the scramble (spoils fought all at once), the war chest (a fallen
## commander's cards go to whoever took their last land), and lands claimed in turn.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")
const Bot := preload("res://engine/bot.gd")
const MapLib := preload("res://engine/map.gd")
const Rng := preload("res://engine/rng.gd")
const Setup := preload("res://engine/setup.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Session := preload("res://game/core/session.gd")


func run(report: Callable, tree: SceneTree) -> void:
	var map: Types.MapDef = H.knife7()
	map.battle = Combat.MODE_VOLLEYS
	map.scramble = true
	_scramble_rule(report)
	_three_way(report, map)
	_empty_land(report, map)
	_old_rules(report)
	_war_chest(report, map)
	_order_roll(report)
	_dig_cap(report)
	_drafts(report)
	_session_draft(report, tree)


func _conserved(before: Types.World, result: Dictionary) -> bool:
	var evs: Array = result["events"]
	return MapLib.sum_armies(result["world"]) == MapLib.sum_armies(before) + Bot._placed_added(evs) + Bot._entrenched_added(evs) - Bot._combat_deaths(evs)


func _view_agrees(before: Types.World, result: Dictionary) -> bool:
	var seen: Types.World = ViewEvents.apply_through(before, result["events"], (result["events"] as Array).size() - 1)
	for t in (result["world"] as Types.World).territories.keys():
		var a: Types.TerritoryState = result["world"].get_territory(t)
		var b: Types.TerritoryState = seen.get_territory(t)
		if a.owner != b.owner or a.armies != b.armies or a.garrison != b.garrison:
			return false
	return true


func _scramble_rule(report: Callable) -> void:
	## two armies: exactly a volley fight (ties cost nobody, as a reroll would)
	var wins := 0
	var n := 4000
	for i in n:
		var r: Dictionary = Combat.scramble([6, 4], Rng.derive_stream(77, 1, "t|%d" % i))
		if int(r["winner"]) == 0:
			wins += 1
	var want: float = Combat.volley_capture_rate(6, 4, false)
	report.call(absf(float(wins) / n - want) < 0.03, "two-army scramble matches a volley fight: %.3f vs %.3f" % [float(wins) / n, want])
	## three or four: always one army left, nobody below zero, every duel logged
	var ok := true
	var big := 0
	for i in 600:
		var sizes: Array = [1 + i % 9, 2 + (i * 7) % 11, 1 + (i * 3) % 5]
		if i % 3 == 0:
			sizes.append(1 + i % 4)
		var r: Dictionary = Combat.scramble(sizes, Rng.derive_stream(5, 2, "s|%d" % i))
		var standing := 0
		for k in (r["left"] as Array).size():
			var v: int = int(r["left"][k])
			if v < 0 or v > int(sizes[k]):
				ok = false
			if v > 0:
				standing += 1
		if standing != 1 or int(r["left"][int(r["winner"])]) <= 0:
			ok = false
		var biggest := 0
		for k in sizes.size():
			if int(sizes[k]) > int(sizes[biggest]):
				biggest = k
		if int(r["winner"]) == biggest:
			big += 1
	report.call(ok, "a scramble of three or four always leaves exactly one army standing")
	report.call(big > 300, "the biggest army usually carries a scramble (%d of 600)" % big)


func _three(map: Types.MapDef, gate: int) -> Types.World:
	## red (Ridge), green (Docks) and gold (Quarry) all storm blue's Gate
	var w: Types.World = H.paint(map, {
		"ridge": ["red", 9], "beacon": ["red", 1], "mill": ["red", 1],
		"gate": ["blue", gate], "harbor": ["blue", 2],
		"docks": ["green", 9], "quarry": ["gold", 9],
	})
	w.round = 2
	return w


func _three_way(report: Callable, map: Types.MapDef) -> void:
	var scrambles := 0
	var three := 0
	var ok := true
	var same := true
	for seed in range(1, 121):
		var w := _three(map, 2)
		var sheets := [H.sheet("red", [H.pkt("ridge", "gate", 8)]), H.sheet("green", [H.pkt("docks", "gate", 8)]), H.sheet("gold", [H.pkt("quarry", "gate", 8)])]
		var r: Dictionary = Resolve.resolve_round(w, map, sheets, seed)
		if not r["errors"].is_empty() or not _conserved(w, r) or not _view_agrees(w, r):
			ok = false
		var sc: Array = H.all_of(r["events"], Types.EVENT_SCRAMBLE)
		if not H.all_of(r["events"], Types.EVENT_SPOILS).is_empty():
			ok = false ## no ladder of duels under v1.4
		if not sc.is_empty():
			scrambles += 1
			var e: Dictionary = sc[0]
			if (e["fronts"] as Array).size() == 3:
				three += 1
			if str(e.get("after", "")) != "melee":
				ok = false
			var owner: String = (r["world"] as Types.World).get_territory("gate").owner
			if owner != str(e["winnerId"]) or (r["world"] as Types.World).get_territory("gate").armies != int(e["winnerLeft"]):
				ok = false
		var again: Dictionary = Resolve.resolve_round(w, map, sheets, seed)
		if Hash.world_hash(again["world"]) != Hash.world_hash(r["world"]):
			same = false
	report.call(ok, "three invaders: melee, then one scramble for the prize; conserved, the view agrees, the winner holds it")
	report.call(scrambles >= 110 and three >= 90, "the victors turn on each other (%d scrambles, %d three-way)" % [scrambles, three])
	report.call(same, "scrambles replay exactly")


func _empty_land(report: Callable, map: Types.MapDef) -> void:
	## nobody holds the Gate: red and green converge on it and fight it out on arrival
	var ok := true
	var seen := 0
	for seed in range(1, 61):
		var w: Types.World = H.paint(map, {
			"ridge": ["red", 6], "beacon": ["red", 1], "mill": ["red", 1],
			"harbor": ["blue", 2], "docks": ["green", 6], "quarry": ["green", 1],
		})
		w.round = 2
		var sheets := [H.sheet("red", [H.pkt("ridge", "gate", 5)]), H.sheet("green", [H.pkt("docks", "gate", 5)])]
		var r: Dictionary = Resolve.resolve_round(w, map, sheets, seed)
		var e: Dictionary = H.first(r["events"], Types.EVENT_SCRAMBLE)
		if e.is_empty() or str(e.get("after", "")) != "empty" or not _conserved(w, r) or not _view_agrees(w, r):
			ok = false
		elif (r["world"] as Types.World).get_territory("gate").owner == str(e["winnerId"]):
			seen += 1
	report.call(ok and seen == 60, "two columns meeting in an empty land scramble for it (%d/60)" % seen)


func _old_rules(report: Callable) -> void:
	## saves from before v1.4 keep their ladder of duels
	var map: Types.MapDef = H.knife7()
	map.battle = Combat.MODE_VOLLEYS
	map.scramble = false
	var spoils := 0
	for seed in range(1, 41):
		var w := _three(map, 1)
		var sheets := [H.sheet("red", [H.pkt("ridge", "gate", 8)]), H.sheet("green", [H.pkt("docks", "gate", 8)]), H.sheet("gold", [H.pkt("quarry", "gate", 8)])]
		var r: Dictionary = Resolve.resolve_round(w, map, sheets, seed)
		if not H.all_of(r["events"], Types.EVENT_SCRAMBLE).is_empty():
			spoils = -999
		spoils += H.all_of(r["events"], Types.EVENT_SPOILS).size()
	report.call(spoils > 20, "old games keep pairwise spoils (%d)" % spoils)


func _war_chest(report: Callable, map: Types.MapDef) -> void:
	## blue's last land falls to red: every card blue held goes to red
	var w: Types.World = H.paint(map, {
		"ridge": ["red", 12], "beacon": ["red", 1], "mill": ["red", 1],
		"gate": ["blue", 1], "docks": ["green", 3], "harbor": ["green", 1], "quarry": ["green", 1],
	})
	w.round = 3
	w.players["blue"].cards = PackedStringArray(["sun", "moon", "moon", "star"])
	w.players["red"].cards = PackedStringArray(["sun"])
	var r: Dictionary = Resolve.resolve_round(w, map, [H.sheet("red", [H.pkt("ridge", "gate", 11)])], 3)
	var nw: Types.World = r["world"]
	var got: bool = nw.get_territory("gate").owner == "red"
	report.call(got and nw.players["red"].cards.size() >= 5 and nw.players["blue"].cards.is_empty() and not H.first(r["events"], Types.EVENT_CARDS_CAPTURED).is_empty(),
		"taking a commander's last land takes their war chest (red holds %d)" % nw.players["red"].cards.size())
	## their last land was one they had only just taken: it still counts. Blue loses the Gate
	## to red, takes green's Harbor, then loses the Harbor back to green: green takes the chest.
	var w2: Types.World = H.paint(map, {"gate": ["red", 3], "harbor": ["green", 2], "ridge": ["red", 3]}, ["blue"])
	w2.players["blue"].cards = PackedStringArray(["star", "star"])
	var held := {"gate": "blue", "harbor": "green"}
	var evs: Array = [
		{"kind": Types.EVENT_OCCUPIED, "playerId": "red", "terrId": "gate", "armies": 3, "previousOwner": "blue"},
		{"kind": Types.EVENT_OCCUPIED, "playerId": "blue", "terrId": "harbor", "armies": 2, "previousOwner": "green"},
		{"kind": Types.EVENT_OCCUPIED, "playerId": "green", "terrId": "harbor", "armies": 2, "previousOwner": "blue"},
	]
	Resolve._hand_over_cards(w2, evs, held, "blue")
	var e2: Dictionary = H.first(evs, Types.EVENT_CARDS_CAPTURED)
	report.call(str(e2.get("to", "")) == "green" and w2.players["green"].cards.size() == 2 and w2.players["red"].cards.is_empty(),
		"the war chest goes to whoever took the very last land, even one just captured (%s)" % str(e2.get("to", "none")))


func _dig_cap(report: Callable) -> void:
	## Amendment 15: nobody digs in deeper than two; old games keep 1 + neighbours
	var map: Types.MapDef = H.knife7()
	var w: Types.World = H.paint(map, {"beacon": ["red", 3], "ridge": ["red", 3], "mill": ["red", 3], "gate": ["red", 3]})
	var Income := load("res://engine/income.gd")
	var old: int = Income.garrison_cap(w, map, "ridge")
	map.dig_cap = 2
	var capped: int = Income.garrison_cap(w, map, "ridge")
	var lonely: Types.World = H.paint(map, {"gate": ["red", 3], "docks": ["blue", 2]})
	report.call(old >= 4 and capped == 2 and Income.garrison_cap(lonely, map, "gate") == 1, "dig-in is capped at two (was %d on the Ridge); a lone land digs in one" % old)
	## a whole war under the cap never holds a garrison above it
	var m2: Types.MapDef = Types.MapDef.from_file("res://maps/known24.json")
	m2.battle = Combat.MODE_VOLLEYS
	m2.maneuvers = true
	m2.scramble = true
	m2.dig_cap = 2
	var r: Dictionary = Autoplay.play(m2, [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"}, {"id": "green", "name": "c", "ai": "hask"}], 21)
	var deepest := 0
	for t in (r["world"] as Types.World).territories.keys():
		deepest = maxi(deepest, (r["world"] as Types.World).get_territory(t).garrison)
	report.call(r["ok"] and deepest <= 2, "a capped war stays legal and nobody is dug in past two (deepest %d)" % deepest)


func _order_roll(report: Callable) -> void:
	var pids := ["red", "blue", "green", "gold", "purple"]
	var ok := true
	var ties := 0
	for seed in range(1, 201):
		var r: Dictionary = Setup.order_roll(seed, pids)
		var order: Array = r["order"]
		var seen := {}
		for p in order:
			seen[p] = true
		if order.size() != 5 or seen.size() != 5:
			ok = false
		if (r["throws"] as Array).size() > 1:
			ties += 1
		## the first throw's highest die goes first, unless tied (then the re-throw settles it)
		var first: Array = r["throws"][0]
		var top := 0
		for t in first:
			top = maxi(top, int(t["die"]))
		var tops: Array = []
		for t in first:
			if int(t["die"]) == top:
				tops.append(str(t["pid"]))
		if not tops.has(str(order[0])):
			ok = false
		if Setup.order_roll(seed, pids)["order"] != order:
			ok = false
	report.call(ok, "the order roll: everyone placed once, highest first, the same every time")
	report.call(ties > 50, "ties throw again among themselves (%d of 200 needed a re-throw)" % ties)


func _drafts(report: Callable) -> void:
	for spec in [["knife7", ["general", "veteran"]], ["known24", ["general", "veteran", "hask"]], ["world30", ["ysolde", "imre", "quill", "oren", "varek"]]]:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % spec[0])
		map.battle = Combat.MODE_VOLLEYS
		map.maneuvers = true
		map.wild_cards = false
		map.scramble = true
		var seats: Array = []
		for k in (spec[1] as Array).size():
			seats.append({"id": Setup.SEAT_IDS[k], "name": spec[1][k], "ai": spec[1][k]})
		var brains := {}
		for st in seats:
			brains[st["id"]] = st["ai"]
		var w: Types.World = Autoplay.draft_deal(map, seats, 9, brains)
		var dealt: Types.World = Setup.deal(map, seats, 9)
		var same_counts := true
		for st in seats:
			if MapLib.player_territory_ids(w, st["id"]).size() != MapLib.player_territory_ids(dealt, st["id"]).size():
				same_counts = false
		var neutral_same: bool = MapLib.player_territory_ids(w, "neutral").size() == MapLib.player_territory_ids(dealt, "neutral").size()
		report.call(same_counts and neutral_same, "%s draft: everyone claims what the deal would give (and the doorstop stays neutral)" % spec[0])
		var r: Dictionary = Autoplay.play(map, seats, 9, 0, true)
		report.call(r["ok"] and str(r["winner"]) != "", "%s: a drafted war is legal and finishes (%s)" % [spec[0], " ".join(r["violations"])])


func _session_draft(report: Callable, tree: SceneTree) -> void:
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/known24.json", "seed": 31, "length": "short", "deal": "draft", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Oren", "kind": "ai", "ai": "oren"},
		{"id": "green", "name": "Quill", "kind": "ai", "ai": "quill"}]})
	report.call(s.phase == Session.Phase.OPENING and s.draft_turn() == "" and (s.draft["claims"] as Array).size() == 24,
		"a drafted session claims every land (24 claims) and opens on deployment")
	report.call(s.income_total() == 22 - 8, "after the draft the deployment pool is the dealt one (%s)" % s.income_total())
	## by hand: the human claims when it's their turn, and can't take a claimed land
	var t: Node = Session.new()
	t.instant = false
	tree.root.add_child(t)
	t.new_game({"map": "res://maps/knife7.json", "seed": 7, "length": "short", "deal": "draft", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Oren", "kind": "ai", "ai": "oren"}]})
	var guard := 0
	var refused := false
	while t.drafting() and guard < 20:
		guard += 1
		if t.is_human(t.draft_turn()):
			var taken := ""
			for id in t.map.territory_ids():
				if t.world.get_territory(str(id)).owner != Types.UNOCCUPIED:
					taken = str(id)
			if taken != "" and t.claim(taken) != "":
				refused = true
			t.claim(t.draft_pick_for("red"))
		else:
			t.ai_claim()
	report.call(refused, "a claimed land can't be claimed again")
	report.call(t.phase == Session.Phase.OPENING and t.world.get_territory("gate").owner == "neutral" and MapLib.player_territory_ids(t.world, "red").size() == 3,
		"the Isthmus duel: the Gate stays neutral, three lands each")
	s.queue_free()
	t.queue_free()
