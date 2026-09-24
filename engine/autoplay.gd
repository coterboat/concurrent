## Full matches with no humans: AI seats (and optionally the monkey) to the end.
## Used by the arena tuner and the property tests. No Node. No UI. Seeded only.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Validate := preload("res://engine/validate.gd")
const Resolve := preload("res://engine/resolve.gd")
const Rng := preload("res://engine/rng.gd")
const Hash := preload("res://engine/hash.gd")
const Ai := preload("res://engine/ai.gd")
const Bot := preload("res://engine/bot.gd")
const Telemetry := preload("res://engine/telemetry.gd")


## seats: [{id, name, ai: "general"|"veteran"|"recruit"|commander id|"monkey"}]
static func play(map: Types.MapDef, seats: Array, match_seed: int, max_rounds: int = 0) -> Dictionary:
	if max_rounds > 0:
		map.rounds = max_rounds
	var world: Types.World = Setup.deal(map, seats, match_seed)
	var brains := {}
	for seat in seats:
		brains[str(seat["id"])] = str(seat.get("ai", "veteran"))
	var violations := PackedStringArray()
	var opening := {}
	for pid in MapLib.living_player_ids(world):
		var rng: RefCounted = Rng.derive_stream(match_seed, 0, "open|" + pid)
		if brains[pid] == "monkey":
			opening[pid] = Bot.opening_placements(world, map, pid, rng)
		else:
			opening[pid] = Ai.opening_placements(world, map, pid, rng, Ai.profile_for(brains[pid]))
	Setup.apply_opening(world, map, opening)
	var setup: Dictionary = world.to_dict()
	var rounds: Array = []
	var sheets_log: Array = []
	var hashes: Array = []
	var territory_history: Array = [] ## per round: {pid: territories}
	var winner := ""
	var early := false
	var guard: int = Setup.rounds_for(map) + 2
	var plan_usec := 0
	var plans := 0
	while guard > 0:
		guard -= 1
		var sheets: Array = []
		for pid in MapLib.living_player_ids(world):
			var rng: RefCounted = Rng.derive_stream(match_seed, world.round, "ai|" + pid)
			var t0 := Time.get_ticks_usec()
			var sheet: Types.Sheet
			if brains[pid] == "monkey":
				sheet = Bot.legal_sheet(world, map, pid, rng)
			else:
				sheet = Ai.plan(world, map, pid, rng, Ai.profile_for(brains[pid]))
			plan_usec += Time.get_ticks_usec() - t0
			plans += 1
			var errs: PackedStringArray = Validate.validate_sheet(world, map, sheet)
			if not errs.is_empty():
				violations.append("r%s %s illegal: %s" % [world.round, pid, " ".join(errs)])
			sheets.append(sheet)
		var dicts: Array = []
		for s in sheets:
			dicts.append((s as Types.Sheet).to_dict())
		sheets_log.append(dicts)
		var result: Dictionary = Resolve.resolve_round(world, map, sheets, match_seed)
		if not result["errors"].is_empty():
			violations.append("resolve r%s: %s" % [world.round, " ".join(result["errors"])])
			break
		world = result["world"]
		var err: String = MapLib.hex_invariant_error(world)
		if err != "":
			violations.append("r%s %s" % [world.round - 1, err])
		hashes.append(Hash.world_hash(world))
		var summary: Dictionary = Telemetry.summarize_events(result["events"])
		rounds.append(summary)
		var snap := {}
		for pid in brains.keys():
			snap[pid] = MapLib.player_territory_ids(world, pid).size()
		territory_history.append(snap)
		winner = str(summary.get("winner", ""))
		early = bool(summary.get("early", false))
		if winner != "":
			break
	return {
		"ok": violations.is_empty(),
		"violations": violations,
		"winner": winner,
		"early": early,
		"rounds": rounds,
		"roundsPlayed": rounds.size(),
		"world": world,
		"setup": setup,
		"sheets": sheets_log,
		"hashes": hashes,
		"history": territory_history,
		"brains": brains,
		"planMs": float(plan_usec) / 1000.0 / float(maxi(1, plans)),
	}
