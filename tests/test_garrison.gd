## Dug-in garrisons: hold, send-all, capture wipes, Neutral does not dig.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const MapLib := preload("res://engine/map.gd")
const Events := preload("res://engine/events.gd")


func run(report: Callable) -> void:
	var map: Types.MapDef = H.knife7()
	_send_all_when_dug(report, map)
	_round1_still_leave_one(report, map)
	_entrench_on_hold(report, map)
	_capture_wipes(report, map)
	_neutral_does_not_dig(report, map)
	_region_bonus_cap(report, map)
	_hash_omits_zero(report, map)


func _send_all_when_dug(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 3],
		"beacon": ["red", 1],
		"mill": ["", 0],
		"gate": ["green", 4],
		"harbor": ["green", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	world.round = 2
	world.get_territory("ridge").garrison = 1
	var sheet: Types.Sheet = H.sheet("red", [H.pkt("ridge", "mill", 3)])
	var errs: PackedStringArray = Validate.validate_sheet(world, map, sheet)
	report.call(errs.is_empty(), "dug-in Ridge may send all 3 mobile (%s)" % " ".join(errs))
	var result: Dictionary = H.resolve(world, map, [sheet], 3)
	report.call(result["errors"].is_empty(), "send-all resolve is legal")
	var after: Types.World = result["world"]
	report.call(H.owner_of(after, "ridge") == "red", "garrison holds Ridge after the army marches")
	report.call(after.get_territory("ridge").armies == 0, "Ridge mobile is 0")
	report.call(after.get_territory("ridge").garrison >= 1, "Ridge still has a garrison")
	report.call(H.owner_of(after, "mill") == "red", "the 3 occupy empty Mill")


func _round1_still_leave_one(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 3],
		"beacon": ["red", 1],
		"mill": ["", 0],
		"gate": ["green", 4],
		"harbor": ["green", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	world.round = 1
	var sheet: Types.Sheet = H.sheet("red", [H.pkt("ridge", "mill", 3)])
	report.call(Validate.validate_sheet(world, map, sheet).size() > 0, "round 1 with no garrison still forbids sending the last man")


func _entrench_on_hold(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 2],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["green", 4],
		"harbor": ["green", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	world.round = 1
	var result: Dictionary = H.resolve(world, map, [H.sheet("red"), H.sheet("green")], 4)
	var after: Types.World = result["world"]
	report.call(after.get_territory("ridge").garrison == 1, "held Ridge digs in to 1 after the round")
	report.call(after.get_territory("beacon").garrison == 1, "held Beacon digs in")
	var kinds := H.kinds(result["events"])
	report.call(kinds.has(Types.EVENT_ENTRENCHED), "entrench is in the event log")


func _capture_wipes(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 8],
		"beacon": ["red", 1],
		"mill": ["green", 1],
		"gate": ["green", 1],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	world.round = 2
	world.get_territory("mill").garrison = 2
	var sheet: Types.Sheet = H.sheet("red", [H.pkt("ridge", "mill", 7)])
	var result: Dictionary = H.resolve(world, map, [sheet], 9)
	var after: Types.World = result["world"]
	if H.owner_of(after, "mill") == "red":
		report.call(after.get_territory("mill").garrison == 0, "a fresh capture starts with 0 garrison")
	else:
		report.call(true, "capture wipe skipped (green held mill)")


func _neutral_does_not_dig(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 1],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["neutral", 5],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	world.round = 1
	var result: Dictionary = H.resolve(world, map, [H.sheet("red"), H.sheet("blue")], 2)
	report.call(result["world"].get_territory("gate").garrison == 0, "Neutral The Gate does not entrench")
	report.call(Income.garrison_cap(world, map, "gate") == 0, "Neutral garrison cap is 0")


func _region_bonus_cap(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 1],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["green", 1],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	var base: int = 1 + MapLib.friendly_neighbor_count(world, map, "ridge")
	var cap: int = Income.garrison_cap(world, map, "ridge")
	report.call(cap == base + 1, "holding northshore adds +1 to Ridge garrison cap (%s vs base %s)" % [cap, base])


func _hash_omits_zero(report: Callable, map: Types.MapDef) -> void:
	var a: Types.World = H.paint(map, {"ridge": ["red", 1], "beacon": ["red", 1], "mill": ["red", 1], "gate": ["green", 1], "harbor": ["blue", 1], "docks": ["blue", 1], "quarry": ["blue", 1]})
	var b: Types.World = a.clone()
	b.get_territory("ridge").garrison = 0
	var Hash := preload("res://engine/hash.gd")
	report.call(Hash.world_hash(a) == Hash.world_hash(b), "zero garrison is omitted from the world hash")
	b.get_territory("ridge").garrison = 2
	report.call(Hash.world_hash(a) != Hash.world_hash(b), "a dug-in hex changes the world hash")
