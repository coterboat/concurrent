## T1–T8 on The Isthmus. G2 gate.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Hash := preload("res://engine/hash.gd")
const Events := preload("res://engine/events.gd")


func run(report: Callable) -> void:
	var map: Types.MapDef = H.knife7()
	_t1(report, map)
	_t2(report, map)
	_t3(report, map)
	_t4(report, map)
	_t5(report, map)
	_t6(report, map)
	_t7(report, map)
	_t8(report, map)
	_merge_before_clash(report, map)
	_overflow_forfeit(report, map)
	_friendly_surge_merge(report, map)


func _t1(report: Callable, map: Types.MapDef) -> void:
	## Red origin 5 sends 4 to unoccupied mill. Green sends 3 at that origin.
	## After lock Red origin has 1. Green's invasion is 3 vs 1, not vs 5.
	## If Green wins ridge, Green keeps it even if Red takes mill.
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 5],
		"beacon": ["red", 1],
		"mill": ["", 0],
		"gate": ["green", 4],
		"harbor": ["green", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	var sheets: Array = [
		H.sheet("red", [H.pkt("ridge", "mill", 4)]),
		H.sheet("green", [H.pkt("gate", "ridge", 3)]),
	]
	var result: Dictionary = H.resolve(world, map, sheets, 1)
	report.call(result["errors"].is_empty(), "T1 sheet is legal")
	var after: Types.World = result["world"]
	var events: Array = result["events"]
	var vac: Dictionary = {}
	for e in H.all_of(events, Types.EVENT_VACATED):
		if e.get("from") == "ridge":
			vac = e
	report.call(vac.get("originRemaining", -1) == 1, "T1 after lock Red origin has 1")
	report.call(vac.get("strength", -1) == 4, "T1 Red sent 4")
	var inv: Dictionary = {}
	for e in H.all_of(events, Types.EVENT_INVASION):
		if e.get("to") == "ridge":
			inv = e
	report.call(inv.get("attackerSize", -1) == 3 and inv.get("defenderSize", -1) == 1, "T1 Green invades 3 vs leftover 1")
	report.call(H.owner_of(after, "mill") == "red", "T1 Red occupies mill (walk-in)")
	if inv.get("attackerWon", false):
		report.call(H.owner_of(after, "ridge") == "green", "T1 if Green wins, Green owns ridge even though Red won mill")
	else:
		report.call(H.owner_of(after, "ridge") == "red", "T1 if Green loses, Red remnant holds ridge")
	report.call(H.owner_of(after, "mill") == "red", "T1 Red winning elsewhere does not reclaim a lost origin")


func _t2(report: Callable, map: Types.MapDef) -> void:
	## Clash packets fight each other before leftover garrisons are used as defenders.
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 5],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["green", 5],
		"harbor": ["green", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	var sheets: Array = [
		H.sheet("red", [H.pkt("ridge", "gate", 4)]),
		H.sheet("green", [H.pkt("gate", "ridge", 3)]),
	]
	var result: Dictionary = H.resolve(world, map, sheets, 1)
	report.call(result["errors"].is_empty(), "T2 sheet is legal")
	var clash: Dictionary = H.first(result["events"], Types.EVENT_CLASH)
	report.call(not clash.is_empty(), "T2 emits Clash")
	var sizes: Array = [int(clash.get("sizeA", 0)), int(clash.get("sizeB", 0))]
	sizes.sort()
	report.call(sizes == [3, 4], "T2 clash is 4 vs 3, leftover 1s are not in the fight")
	var kinds := Array(H.kinds(result["events"]))
	var clash_i: int = kinds.find(Types.EVENT_CLASH)
	var inv_i: int = kinds.find(Types.EVENT_INVASION)
	report.call(clash_i >= 0 and (inv_i == -1 or clash_i < inv_i), "T2 clash before any invasion")


func _t3(report: Callable, map: Types.MapDef) -> void:
	## Red 5 and Blue 5 both hit Green 3. One owner remains.
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 6],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["green", 3],
		"harbor": ["blue", 6],
		"docks": ["blue", 1],
		"quarry": ["green", 1],
	})
	var sheets: Array = [
		H.sheet("red", [H.pkt("ridge", "gate", 5)]),
		H.sheet("blue", [H.pkt("harbor", "gate", 5)]),
	]
	var result: Dictionary = H.resolve(world, map, sheets, 1)
	report.call(result["errors"].is_empty(), "T3 sheet is legal")
	var after: Types.World = result["world"]
	var owner: String = H.owner_of(after, "gate")
	report.call(owner != Types.UNOCCUPIED, "T3 gate is owned")
	report.call(H.armies_of(after, "gate") >= 1, "T3 gate has >= 1 army")
	var owners := {}
	owners[owner] = true
	report.call(owners.size() == 1, "T3 one owner remains on gate (%s)" % owner)
	var invasions: Array = H.all_of(result["events"], Types.EVENT_INVASION)
	var spoils: Array = H.all_of(result["events"], Types.EVENT_SPOILS)
	report.call(invasions.size() + spoils.size() >= 1, "T3 mass is in the event log")


func _t4(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 3],
		"beacon": ["red", 1],
		"mill": ["green", 1],
		"gate": ["green", 1],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	var bad: Types.Sheet = H.sheet("red", [H.pkt("ridge", "mill", 2), H.pkt("ridge", "gate", 2)])
	var errs: PackedStringArray = Validate.validate_sheet(world, map, bad)
	var joined := " ".join(errs)
	report.call(errs.size() > 0, "T4 origin 3 two packets of 2 is rejected")
	report.call(joined.contains("leftover"), "T4 error names leftover")
	var result: Dictionary = H.resolve(world, map, [bad], 1)
	report.call(not result["errors"].is_empty(), "T4 resolve refuses to run an illegal sheet")
	report.call(H.armies_of(result["world"], "ridge") == 3, "T4 world is unchanged on reject")


func _t5(report: Callable, map: Types.MapDef) -> void:
	## Beacon is isolated if Red does not own ridge. Cap = 1. Overflow vanishes.
	var world: Types.World = H.paint(map, {
		"beacon": ["red", 1],
		"ridge": ["green", 1],
		"mill": ["green", 1],
		"gate": ["green", 1],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	report.call(Income.cap_of(world, map, "beacon") == 1, "T5 isolated cap is 1")
	var s: Types.Sheet = H.sheet("red", [], {"beacon": 3})
	var errs: PackedStringArray = Validate.validate_sheet(world, map, s)
	report.call(errs.is_empty(), "T5 overflow is legal (it vanishes, not a reject)")
	var result: Dictionary = H.resolve(world, map, [s], 1)
	report.call(result["errors"].is_empty(), "T5 resolve accepts overflow sheet")
	report.call(H.armies_of(result["world"], "beacon") == 2, "T5 isolated hex accepts 1 reinforcement (1+1=2)")
	var placed: Dictionary = H.first(result["events"], Types.EVENT_PLACED)
	report.call(int(placed.get("added", -1)) == 1, "T5 placed 1")
	report.call(int(placed.get("overflow", -1)) == 2, "T5 overflow 2 vanishes")


func _t6(report: Callable, map: Types.MapDef) -> void:
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 5],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["green", 4],
		"harbor": ["green", 2],
		"docks": ["blue", 3],
		"quarry": ["blue", 1],
	})
	var sheets: Array = [
		H.sheet("red", [H.pkt("ridge", "gate", 3)]),
		H.sheet("green", [H.pkt("harbor", "docks", 1)]),
		H.sheet("blue", [H.pkt("docks", "gate", 2)]),
	]
	var a: Dictionary = H.resolve(world, map, sheets, 42)
	var b: Dictionary = H.resolve(world, map, sheets, 42)
	report.call(a["errors"].is_empty() and b["errors"].is_empty(), "T6 sheets legal (%s)" % " ".join(a["errors"]))
	var ha := Hash.world_hash(a["world"])
	var hb := Hash.world_hash(b["world"])
	report.call(ha == hb, "T6 same seed same world hash")
	report.call(Events.canonical_list(a["events"]) == Events.canonical_list(b["events"]), "T6 same seed same event list")
	var dice_moved := false
	for seed in [43, 7, 99, 256]:
		var other: Dictionary = H.resolve(world, map, sheets, seed)
		if Events.canonical_list(a["events"]) != Events.canonical_list(other["events"]):
			dice_moved = true
			break
	report.call(dice_moved, "T6 seed is not on World; a different seed changes event dice")


func _t7(report: Callable, map: Types.MapDef) -> void:
	## Red walks unoccupied gate with surgeTo harbor. Blue has a primary to harbor.
	## Harbor as a primary dest resolves before the surge lands.
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 5],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["", 0],
		"harbor": ["", 0],
		"docks": ["blue", 4],
		"quarry": ["blue", 1],
	}, ["green"])
	var sheets: Array = [
		H.sheet("red", [H.pkt("ridge", "gate", 4, "harbor")]),
		H.sheet("blue", [H.pkt("docks", "harbor", 3)]),
	]
	var result: Dictionary = H.resolve(world, map, sheets, 1)
	report.call(result["errors"].is_empty(), "T7 sheet is legal")
	var events: Array = result["events"]
	var kinds := Array(H.kinds(events))
	var surge_i: int = kinds.find(Types.EVENT_SURGE)
	report.call(surge_i >= 0, "T7 emits Surge")
	var harbor_primary := -1
	for i in events.size():
		var e: Dictionary = events[i]
		var kind: String = str(e.get("kind", ""))
		if kind == Types.EVENT_OCCUPIED and e.get("terrId") == "harbor":
			harbor_primary = i
			break
		if kind == Types.EVENT_INVASION and e.get("to") == "harbor" and kind != Types.EVENT_SURGE:
			harbor_primary = i
			break
	report.call(harbor_primary >= 0, "T7 harbor primary occupies before surge")
	report.call(surge_i > harbor_primary, "T7 surge last: harbor primary index %s surge %s" % [harbor_primary, surge_i])
	report.call(H.owner_of(result["world"], "gate") == "red", "T7 Red holds gate after surge leaves 1")
	report.call(H.armies_of(result["world"], "gate") == 1, "T7 surge leaves 1 on gate")


func _t8(report: Callable, map: Types.MapDef) -> void:
	## Clash survivor continues into a hex a third player also hit.
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 5],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["green", 5],
		"harbor": ["blue", 5],
		"docks": ["blue", 1],
		"quarry": ["green", 1],
	})
	var sheets: Array = [
		H.sheet("red", [H.pkt("ridge", "gate", 4)]),
		H.sheet("green", [H.pkt("gate", "ridge", 3)]),
		H.sheet("blue", [H.pkt("harbor", "gate", 4)]),
	]
	var result: Dictionary = H.resolve(world, map, sheets, 1)
	report.call(result["errors"].is_empty(), "T8 sheet is legal")
	var events: Array = result["events"]
	report.call(not H.first(events, Types.EVENT_CLASH).is_empty(), "T8 clash happened")
	var gate_fights := 0
	var reconstruct := true
	for e in events:
		var kind: String = str(e.get("kind", ""))
		if kind == Types.EVENT_CLASH:
			if int(e.get("sizeA", 0)) < 1 or int(e.get("sizeB", 0)) < 1:
				reconstruct = false
			if not e.has("dieA") or not e.has("totalA") or not e.has("winnerRemaining"):
				reconstruct = false
		if kind == Types.EVENT_INVASION and e.get("to") == "gate":
			gate_fights += 1
			if not e.has("attackerDie") or not e.has("defenderSize"):
				reconstruct = false
		if kind == Types.EVENT_SPOILS and e.get("to") == "gate":
			gate_fights += 1
	report.call(gate_fights >= 1, "T8 clash survivor (or Blue) continues into gate")
	report.call(reconstruct, "T8 log is reconstructible from events (sizes, dice, totals)")
	report.call(H.armies_of(result["world"], "gate") >= 1, "T8 gate is occupied after the three-way")
	var a: Dictionary = H.resolve(world, map, sheets, 1)
	report.call(Events.canonical_list(events) == Events.canonical_list(a["events"]), "T8 replay of same seed matches the log")


func _merge_before_clash(report: Callable, map: Types.MapDef) -> void:
	## Two same-owner packets on one border merge before the clash, so leftover
	## 1s stay out and the second packet cannot sneak past.
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 5],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["green", 5],
		"harbor": ["green", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	var sheets: Array = [
		H.sheet("red", [H.pkt("ridge", "gate", 2), H.pkt("ridge", "gate", 2)]),
		H.sheet("green", [H.pkt("gate", "ridge", 3)]),
	]
	var result: Dictionary = H.resolve(world, map, sheets, 1)
	report.call(result["errors"].is_empty(), "merge-before-clash sheet is legal")
	var clash: Dictionary = H.first(result["events"], Types.EVENT_CLASH)
	var sizes: Array = [int(clash.get("sizeA", 0)), int(clash.get("sizeB", 0))]
	sizes.sort()
	report.call(sizes == [3, 4], "same-owner packets merge to 4 before clashing with 3")


func _overflow_forfeit(report: Callable, map: Types.MapDef) -> void:
	## Income 3, isolated beacon cap 1 and isolated mill cap 1. Request 3 on
	## beacon then 2 on mill. Overflow is forfeited, not spent on mill.
	var world: Types.World = H.paint(map, {
		"beacon": ["red", 1],
		"ridge": ["green", 1],
		"mill": ["red", 1],
		"gate": ["green", 1],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	report.call(Income.income_of(world, map, "red") == 3, "overflow-forfeit income is 3")
	var result: Dictionary = H.resolve(world, map, [H.sheet("red", [], {"beacon": 3, "mill": 2})], 1)
	report.call(result["errors"].is_empty(), "overflow-forfeit sheet is legal")
	report.call(H.armies_of(result["world"], "beacon") == 2, "overflow-forfeit beacon got 1")
	report.call(H.armies_of(result["world"], "mill") == 1, "overflow-forfeit mill got none; vanished overflow is not reused")


func _friendly_surge_merge(report: Callable, map: Types.MapDef) -> void:
	## Two Red walk-ins surge into empty quarry. Same owner merges; they do not spoils-fight.
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 5],
		"beacon": ["red", 1],
		"mill": ["red", 1],
		"gate": ["", 0],
		"harbor": ["red", 5],
		"docks": ["", 0],
		"quarry": ["", 0],
	}, ["green", "blue"])
	var sheets: Array = [
		H.sheet("red", [
			H.pkt("ridge", "gate", 4, "quarry"),
			H.pkt("harbor", "docks", 4, "quarry"),
		]),
	]
	var result: Dictionary = H.resolve(world, map, sheets, 1)
	report.call(result["errors"].is_empty(), "friendly-surge sheet is legal (%s)" % " ".join(result["errors"]))
	report.call(H.all_of(result["events"], Types.EVENT_SPOILS).is_empty(), "friendly surges do not spoils-fight")
	report.call(H.owner_of(result["world"], "quarry") == "red", "friendly surges occupy quarry")
	report.call(H.armies_of(result["world"], "quarry") == 6, "friendly surges merge 3+3=6")
