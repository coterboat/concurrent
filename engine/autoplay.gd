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
const Maneuver := preload("res://engine/maneuver.gd")
const Income := preload("res://engine/income.gd")
const Capitals := preload("res://engine/capitals.gd")

## Tuning instrument only: when on, play() returns every event of every round under
## "events". Off by default, because a long tournament would otherwise keep every roll of
## every battle in memory.
static var keep_events := false
## v1.12 studies: called with (world, map) after every round when set. Watching changes nothing.
static var watch: Callable = Callable()


## seats: [{id, name, ai: "general"|"veteran"|"recruit"|commander id|"monkey"}]
static func play(map: Types.MapDef, seats: Array, match_seed: int, max_rounds: int = 0, draft: bool = false) -> Dictionary:
	if max_rounds > 0:
		map.rounds = max_rounds
	var brains := {}
	for seat in seats:
		brains[str(seat["id"])] = str(seat.get("ai", "veteran"))
	var world: Types.World = draft_deal(map, seats, match_seed, brains) if draft else Setup.deal(map, seats, match_seed)
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
	var all_events: Array = []
	var sheets_log: Array = []
	var hashes: Array = []
	var maneuvers_log: Array = []
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
		var before: int = MapLib.sum_armies(world)
		var result: Dictionary = Resolve.resolve_round(world, map, sheets, match_seed)
		if not result["errors"].is_empty():
			violations.append("resolve r%s: %s" % [world.round, " ".join(result["errors"])])
			break
		## P2 on every map and seat count: nothing appears or vanishes outside a fight.
		var evs: Array = result["events"]
		if keep_events:
			all_events.append_array(evs)
		var expected: int = before + Bot._placed_added(evs) + Bot._entrenched_added(evs) - Bot._combat_deaths(evs)
		var got: int = MapLib.sum_armies(result["world"])
		if got != expected:
			violations.append("r%s army leak: expected %s got %s" % [world.round, expected, got])
		world = result["world"]
		## v1.3 regroup phase: everyone marches, then the next round
		if map.maneuvers and str(Telemetry.summarize_events(result["events"]).get("winner", "")) == "":
			var by := {}
			for pid in MapLib.living_player_ids(world):
				if pid != Income.NEUTRAL_ID:
					by[pid] = Maneuver.plan(world, map, pid, {} if brains.get(pid, "") == "monkey" else Ai.profile_for(str(brains.get(pid, "veteran"))))
			var before_moves: int = MapLib.sum_armies(world)
			Maneuver.apply(world, map, by)
			if MapLib.sum_armies(world) != before_moves:
				violations.append("r%s maneuvers changed the army count" % world.round)
			maneuvers_log.append(by)
		else:
			maneuvers_log.append({})
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
		if watch.is_valid():
			watch.call(world, map)
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
		"maneuvers": maneuvers_log,
		"hashes": hashes,
		"history": territory_history,
		"brains": brains,
		"events": all_events,
		"planMs": float(plan_usec) / 1000.0 / float(maxi(1, plans)),
	}


static func draft_deal(map: Types.MapDef, seats: Array, match_seed: int, brains: Dictionary) -> Types.World:
	## v1.4 lands claimed in turn: the order roll, then every seat's brain picks (as the session does)
	var w: Types.World = Setup.draft_world(map, seats, match_seed)
	var pids: Array = []
	for s in seats:
		pids.append(str(s["id"]))
	var roll: Dictionary = Setup.order_roll(match_seed, pids)
	var free := 0
	for t in map.territory_ids():
		if w.get_territory(str(t)).owner == Types.UNOCCUPIED:
			free += 1
	var turns: Array = Setup.draft_turns(roll["order"], Setup.draft_quota(map, seats.size()), free)
	for i in turns.size():
		var pid: String = str(turns[i])
		var left := {}
		for q in pids:
			left[q] = 0
		for k in range(i, turns.size()):
			left[str(turns[k])] = int(left[str(turns[k])]) + 1
		var rng: RefCounted = Rng.derive_stream(match_seed, 0, "draft|%d" % i)
		var brain: String = str(brains.get(pid, "veteran"))
		var land: String = Ai.draft_pick(w, map, pid, rng, Ai.profile_for("veteran" if brain == "monkey" else brain), left, turns.slice(i + 1))
		if land == "":
			break
		w.set_hex(land, pid, 1)
		Capitals.claimed(w, map, pid, land) ## v1.8: the first claim is the capital
	Setup.finish_draft(w, map, seats.size())
	return w
