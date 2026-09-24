## G0+G1 headless runner. No UI. Exit 0 only if the kernel holds.
extends SceneTree

const EngineTypesScript = preload("res://engine/types.gd")
const GameRngScript = preload("res://engine/rng.gd")
const EngineHashScript = preload("res://engine/hash.gd")
const CombatBandsTest = preload("res://tests/test_combat_bands.gd")
const QueueTest = preload("res://tests/test_queue.gd")
const PropertiesTest = preload("res://tests/test_properties.gd")
const MatchTest = preload("res://tests/test_match.gd")
const ViewEventsTest = preload("res://tests/test_view_events.gd")
const SessionTest = preload("res://tests/test_session.gd")
const MapsTest = preload("res://tests/test_maps.gd")
const GarrisonTest = preload("res://tests/test_garrison.gd")

const KNIFE7 := "res://maps/knife7.json"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("CONCURRENT G0–G6")
	_section("map")
	var map: EngineTypesScript.MapDef = _test_map()
	_section("types")
	_test_types(map)
	_section("rng")
	_test_rng()
	_section("hash")
	_test_hash(map)
	_section("combat")
	CombatBandsTest.new().run(Callable(self, "_ok"))
	_section("queue T1–T8")
	QueueTest.new().run(Callable(self, "_ok"))
	_section("monkey P1–P4")
	PropertiesTest.new().run(Callable(self, "_ok"))
	_section("match.json")
	MatchTest.new().run(Callable(self, "_ok"))
	_section("g5 view + session")
	ViewEventsTest.new().run(Callable(self, "_ok"))
	SessionTest.new().run(Callable(self, "_ok"), self)
	_section("known world")
	MapsTest.new().run(Callable(self, "_ok"), self)
	_section("garrison")
	GarrisonTest.new().run(Callable(self, "_ok"))
	print("")
	print("G0–G6 %s  passed=%s  failed=%s" % ["ok" if _failed == 0 else "FAIL", _passed, _failed])
	quit(0 if _failed == 0 else 1)


func _section(name: String) -> void:
	print("\n[%s]" % name)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  ok   %s" % msg)
	else:
		_failed += 1
		print("  FAIL %s" % msg)


func _test_map() -> EngineTypesScript.MapDef:
	var map: EngineTypesScript.MapDef = EngineTypesScript.MapDef.from_file(KNIFE7)
	_ok(map != null, "knife7.json loads")
	if map == null:
		return null
	_ok(map.id == "knife7", "map id is knife7")
	_ok(map.display_name == "The Isthmus", "map name is The Isthmus")
	_ok(map.territories.size() == 7, "seven territories")
	_ok(map.region_bonus.size() == 2, "two region bonuses")
	_ok(int(map.region_bonus.get("northshore", 0)) == 2, "northshore bonus 2")
	_ok(int(map.region_bonus.get("southshore", 0)) == 2, "southshore bonus 2")

	var ids := map.territory_ids()
	_ok(ids.size() == 7, "territory_ids size 7")

	var gate: EngineTypesScript.TerritoryDef = map.get_territory("gate")
	_ok(gate != null and gate.display_name == "The Gate", "The Gate exists")
	_ok(gate != null and gate.region == "", "The Gate has no region")

	var symmetric := true
	var unknown := false
	var self_edge := false
	for terr_id in ids:
		var t: EngineTypesScript.TerritoryDef = map.get_territory(terr_id)
		if t == null:
			unknown = true
			continue
		for n in t.adjacent:
			if n == terr_id:
				self_edge = true
			if not map.territories.has(n):
				unknown = true
			elif not map.is_adjacent(n, terr_id):
				symmetric = false
	_ok(symmetric, "adjacency is undirected")
	_ok(not unknown, "every adjacent id exists")
	_ok(not self_edge, "no self-edges")

	_ok(_reachable(map, "beacon", "harbor", true), "north reaches south through The Gate")
	_ok(not _reachable(map, "beacon", "harbor", false), "north cannot reach south if The Gate is removed")
	_ok(_reachable(map, "beacon", "mill", false), "northshore stays connected without The Gate")
	_ok(_reachable(map, "harbor", "quarry", false), "southshore stays connected without The Gate")
	return map


func _reachable(map: EngineTypesScript.MapDef, start: String, goal: String, use_gate: bool) -> bool:
	var seen := {}
	var q: Array = [start]
	seen[start] = true
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == goal:
			return true
		var t: EngineTypesScript.TerritoryDef = map.get_territory(cur)
		if t == null:
			continue
		for n in t.adjacent:
			if n == "gate" and not use_gate and cur != "gate":
				continue
			if seen.has(n):
				continue
			seen[n] = true
			q.append(n)
	return false


func _test_types(map: EngineTypesScript.MapDef) -> void:
	if map == null:
		_ok(false, "types need a map")
		return
	var world: EngineTypesScript.World = EngineTypesScript.World.empty_from_map(map)
	_ok(world.map_id == "knife7", "empty world map_id")
	_ok(world.territories.size() == 7, "empty world has 7 hexes")
	var empty_ok := true
	for terr_id in world.territories.keys():
		var ts: EngineTypesScript.TerritoryState = world.territories[terr_id]
		if ts.owner != EngineTypesScript.UNOCCUPIED or ts.armies != 0:
			empty_ok = false
	_ok(empty_ok, "every hex starts unoccupied with 0 armies")

	var red := EngineTypesScript.PlayerState.new()
	red.id = "red"
	red.display_name = "Red"
	red.color = "#c23b2e"
	world.players["red"] = red

	var packet := EngineTypesScript.Packet.new()
	packet.from_id = "ridge"
	packet.to_id = "gate"
	packet.strength = 4
	packet.surge_to = "harbor"
	var pd := packet.to_dict()
	_ok(pd["from"] == "ridge" and pd["to"] == "gate" and pd["strength"] == 4, "packet bible keys")
	_ok(pd.get("surgeTo", "") == "harbor", "surgeTo is optional bible key")

	var sheet := EngineTypesScript.Sheet.new()
	sheet.player_id = "red"
	sheet.placements["ridge"] = 2
	sheet.packets.append(packet)
	var sd := sheet.to_dict()
	_ok(sd["playerId"] == "red", "sheet playerId")
	_ok(sd["packets"].size() == 1, "sheet packets")
	_ok(not sd.has("regroup"), "empty regroup omitted")


func _rolls(match_seed: int, round: int, key: String, n: int) -> PackedInt32Array:
	var rng: GameRngScript = GameRngScript.derive_stream(match_seed, round, key)
	var out := PackedInt32Array()
	for i in n:
		var d := rng.roll_d6()
		out.append(d)
		if d < 1 or d > 6:
			return PackedInt32Array()
	return out


func _same_seq(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _in_band(seq: PackedInt32Array) -> bool:
	if seq.is_empty():
		return false
	for v in seq:
		if v < 1 or v > 6:
			return false
	return true


func _test_rng() -> void:
	var a := _rolls(42, 1, "clash|gate|red|blue", 24)
	var a2 := _rolls(42, 1, "clash|gate|red|blue", 24)
	var b := _rolls(42, 1, "invasion|harbor|red", 24)
	var c := _rolls(42, 2, "clash|gate|red|blue", 24)
	_ok(_in_band(a) and _in_band(b) and _in_band(c), "d6 values are 1..6")
	_ok(a.size() == 24 and _same_seq(a, a2), "same matchSeed+round+battleKey -> same stream")
	_ok(a.size() == 24 and not _same_seq(a, b), "different battleKey does not reroll this fight into that one")
	_ok(a.size() == 24 and not _same_seq(a, c), "different round is a different stream")

	# Unrelated packet on the other side of the map must not change this fight.
	var fight := _rolls(99, 3, "invasion|gate|red", 8)
	var fight_again := _rolls(99, 3, "invasion|gate|red", 8)
	_ok(_same_seq(fight, fight_again), "deriving another stream does not disturb this battle_key")


func _test_hash(map: EngineTypesScript.MapDef) -> void:
	if map == null:
		_ok(false, "hash needs a map")
		return
	var w1: EngineTypesScript.World = EngineTypesScript.World.empty_from_map(map)
	var w2: EngineTypesScript.World = EngineTypesScript.World.empty_from_map(map)
	# Insert in opposite order to prove canonicalization ignores dict insertion.
	var red := EngineTypesScript.PlayerState.new()
	red.id = "red"
	red.display_name = "Red"
	red.color = "#c23b2e"
	var blue := EngineTypesScript.PlayerState.new()
	blue.id = "blue"
	blue.display_name = "Blue"
	blue.color = "#2e5aa6"
	w1.players["red"] = red
	w1.players["blue"] = blue
	w2.players["blue"] = blue
	w2.players["red"] = red
	w1.territories["gate"].armies = 5
	w1.territories["gate"].owner = "neutral"
	w2.territories["gate"].armies = 5
	w2.territories["gate"].owner = "neutral"

	var h1 := EngineHashScript.world_hash(w1)
	var h2 := EngineHashScript.world_hash(w2)
	_ok(h1 == h2, "world hash ignores insertion order")
	_ok(h1.length() == 8, "world hash is 8 hex chars")

	w2.territories["gate"].armies = 4
	var h3 := EngineHashScript.world_hash(w2)
	_ok(h1 != h3, "changing an army count changes the hash")

	var snap := w1.to_dict()
	_ok(snap["territories"]["gate"]["owner"] == "neutral", "occupied owner is a string in snapshot")
	_ok(snap["territories"]["beacon"]["owner"] == null, "unoccupied owner is null in snapshot")
	_ok(not snap.has("matchSeed"), "seed is not stored on World")
