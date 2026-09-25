## One match, any mix of humans and AI commanders, 2–5 seats.
## Holds match_seed; never writes it onto World. The UI reads this and calls in;
## nothing here draws. Every resolved round is autosaved as a replayable record.
extends Node

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Resolve := preload("res://engine/resolve.gd")
const Combat := preload("res://engine/combat.gd")
const Cards := preload("res://engine/cards.gd")
const Rng := preload("res://engine/rng.gd")
const Hash := preload("res://engine/hash.gd")
const Ai := preload("res://engine/ai.gd")
const Telemetry := preload("res://engine/telemetry.gd")

enum Phase { NONE, OPENING, PASS, PLANNING, RESOLVING, CINEMA, RECAP, GAME_OVER }

static var SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const LENGTHS := {"short": 0.75, "standard": 1.0, "long": 1.5, "conquest": 0.0}

signal changed
signal phase_changed(phase: int)
signal extended ## a paused round resolved further: events grew (same prefix)

var config: Dictionary = {}
var map: Types.MapDef
var world: Types.World
var match_seed: int = 0
var phase: int = Phase.NONE
var seats: Array = [] ## [{id, name, kind: human|ai, ai, portrait}]
var planner: String = ""
var pass_to: String = ""
var queue: Array = [] ## humans still to plan this window
var drafts := {} ## pid -> Sheet
var opening := {} ## pid -> {terr: n}
var locked := {} ## pid -> Sheet (or opening dict)
var setup_dict: Dictionary = {}
var rounds_log: Array = [] ## [[sheet dicts]]
var hashes: Array = []
var history: Array = [] ## [{round, terr: {pid: n}, score: {pid: n}}]
var stats := {} ## pid -> {captures, walkins, lost_to_walkins, battles, won, killed, cards}
var pre_world: Types.World
var events: Array = []
var ghosts: Array = []
var winner: String = ""
var early := false
var time_left := 0.0
var error_text := ""
var watching := false ## every human is out; AIs play on
var instant := false ## tests: resolve without waiting a frame
var round_sheets: Array = [] ## this round's sheets while its battles are being called
var live: Array = [] ## humans calling their own battles this round
var pending: Dictionary = {} ## the battle call the round is waiting on (empty = none)
var force_live := false ## tests: call battles live even when instant


# ================================================================ lifecycle

func new_game(p_config: Dictionary) -> void:
	config = p_config.duplicate(true)
	match_seed = int(config.get("seed", 0))
	if match_seed == 0:
		match_seed = int(Time.get_unix_time_from_system()) % 2000000000 + randi() % 1000
		config["seed"] = match_seed
	map = Types.MapDef.from_file(str(config["map"]))
	_apply_length()
	seats = config["seats"]
	world = Setup.deal(map, _seat_list(), match_seed)
	## Neutral name in two-seat games
	if world.players.has(Income.NEUTRAL_ID):
		world.players[Income.NEUTRAL_ID].display_name = "Neutral"
	setup_dict = {}
	rounds_log = []
	hashes = []
	history = []
	stats = {}
	for s in seats:
		stats[s["id"]] = _blank_stats()
	ghosts = []
	events = []
	winner = ""
	early = false
	watching = false
	drafts = {}
	opening = {}
	locked = {}
	_start_window(Phase.OPENING)


func _apply_length() -> void:
	map.battle = str(config.get("battle", "volleys"))
	config["battle"] = map.battle ## saves must replay with the same dice
	var base: int = Setup.rounds_for(map)
	var mode: String = str(config.get("length", "standard"))
	var k: float = float(LENGTHS.get(mode, 1.0))
	if k <= 0.0:
		map.rounds = 60
	else:
		map.rounds = maxi(3, int(round(float(base) * k)))


func _seat_list() -> Array:
	var out: Array = []
	for s in seats:
		out.append({"id": s["id"], "name": s["name"]})
	return out


func _blank_stats() -> Dictionary:
	return {"captures": 0, "walkins": 0, "walked": 0, "battles": 0, "won": 0, "armies_lost": 0, "kills": 0, "sets": 0}


func seat(pid: String) -> Dictionary:
	for s in seats:
		if s["id"] == pid:
			return s
	return {}


func is_human(pid: String) -> bool:
	return str(seat(pid).get("kind", "ai")) == "human"


func name_of(pid: String) -> String:
	if pid == Income.NEUTRAL_ID:
		return "Neutral"
	if pid == "" or pid == Types.UNOCCUPIED:
		return "nobody"
	return str(seat(pid).get("name", pid.capitalize()))


func living_humans() -> Array:
	var out: Array = []
	for s in seats:
		if s["kind"] == "human" and world.players.has(s["id"]) and world.players[s["id"]].alive:
			out.append(s["id"])
	return out


func is_last_round() -> bool:
	return world != null and world.round >= Setup.rounds_for(map)


func rounds_total() -> int:
	return Setup.rounds_for(map)


func conquest() -> bool:
	return str(config.get("length", "standard")) == "conquest"


# ================================================================ windows

func _start_window(kind: int) -> void:
	drafts = {}
	opening = {}
	locked = {}
	error_text = ""
	queue = living_humans()
	for pid in MapLib.living_player_ids(world):
		if kind == Phase.OPENING:
			opening[pid] = {}
		else:
			drafts[pid] = _empty(pid)
	if queue.is_empty():
		watching = true
		_finish_window(kind)
		return
	_next_planner(kind)


func _next_planner(kind: int) -> void:
	planner = str(queue.pop_front())
	time_left = float(config.get("timer", 0))
	if living_humans().size() > 1 and not bool(config.get("open_sheets", false)):
		pass_to = planner
		phase = Phase.PASS
		set_meta("after_pass", kind)
	else:
		phase = kind
	_emit_phase()


func seated() -> void:
	if phase != Phase.PASS:
		return
	phase = int(get_meta("after_pass", Phase.PLANNING))
	time_left = float(config.get("timer", 0))
	_emit_phase()


func _emit_phase() -> void:
	phase_changed.emit(phase)
	changed.emit()


func lock() -> String:
	## Seal the current human's sheet. Returns an error, or "" if sealed.
	error_text = ""
	if phase == Phase.OPENING:
		locked[planner] = opening.get(planner, {})
	elif phase == Phase.PLANNING:
		var s: Types.Sheet = sheet()
		if world.round <= 1:
			s.regroup = null
		clamp_packets()
		var errs := Validate.validate_sheet(world, map, s)
		if not errs.is_empty():
			error_text = errs[0]
			changed.emit()
			return error_text
		locked[planner] = s
	else:
		return "nothing to seal"
	var kind: int = phase
	if not queue.is_empty():
		_next_planner(kind)
		return ""
	_finish_window(kind)
	return ""


func timeout_lock() -> void:
	## Planning clock ran out: keep what is legal, drop what is not.
	if phase == Phase.PLANNING:
		var s: Types.Sheet = sheet()
		while not s.packets.is_empty() and not Validate.validate_sheet(world, map, s).is_empty():
			s.packets.pop_back()
		if not Validate.validate_sheet(world, map, s).is_empty():
			drafts[planner] = _empty(planner)
	lock()


func _finish_window(kind: int) -> void:
	phase = Phase.RESOLVING
	_emit_phase()
	## Give the UI a frame to show "sealing" before the generals think.
	if not instant:
		await get_tree().process_frame
		await get_tree().process_frame
	if kind == Phase.OPENING:
		_resolve_opening()
	else:
		_resolve_round()


func _resolve_opening() -> void:
	var placements := {}
	for pid in MapLib.living_player_ids(world):
		if locked.has(pid):
			placements[pid] = locked[pid]
		else:
			var rng: RefCounted = Rng.derive_stream(match_seed, 0, "open|" + pid)
			placements[pid] = Ai.opening_placements(world, map, pid, rng, Ai.profile_for(ai_of(pid)))
	pre_world = world.clone()
	Setup.apply_opening(world, map, placements)
	setup_dict = world.to_dict()
	events = []
	for pid in placements.keys():
		var place: Dictionary = placements[pid]
		for t in place.keys():
			var ts: Types.TerritoryState = world.get_territory(str(t))
			if ts.owner == pid and int(place[t]) > 0:
				events.append({"kind": Types.EVENT_PLACED, "playerId": pid, "terrId": str(t), "added": ts.armies - pre_world.get_territory(str(t)).armies, "armies": ts.armies, "overflow": 0})
	_snapshot_history(0)
	save()
	phase = Phase.CINEMA
	set_meta("opening_cinema", true)
	_emit_phase()


func ai_of(pid: String) -> String:
	return str(seat(pid).get("ai", "veteran"))


func _resolve_round() -> void:
	var sheets: Array = []
	for pid in MapLib.living_player_ids(world):
		if locked.has(pid):
			sheets.append(locked[pid])
		else:
			var rng: RefCounted = Rng.derive_stream(match_seed, world.round, "ai|" + pid)
			sheets.append(Ai.plan(world, map, pid, rng, Ai.profile_for(ai_of(pid))))
	pre_world = world.clone()
	round_sheets = sheets
	live = _live_players()
	_run(true)


func _setting(key: String, fallback: Variant) -> Variant:
	## Settings is an autoload; the headless test runner has none.
	var st: Node = get_node_or_null("/root/Settings") if is_inside_tree() else null
	return st.get_value(key, fallback) if st != null else fallback


func _live_players() -> Array:
	## Humans who will watch (and so call) their own battles this round.
	if map.battle != Combat.MODE_VOLLEYS or watching or (instant and not force_live):
		return []
	if str(_setting("battles", "mine")) == "off":
		return []
	return living_humans()


func _run(first: bool) -> void:
	var result: Dictionary = Resolve.resolve_round(world, map, round_sheets, match_seed, live)
	if not result["errors"].is_empty():
		## Should never happen: every sheet was validated. Fall back to holds.
		push_error("resolve rejected sheets: %s" % " ".join(result["errors"]))
		round_sheets = []
		for pid in MapLib.living_player_ids(world):
			round_sheets.append(_empty(pid))
		live = []
		result = Resolve.resolve_round(world, map, round_sheets, match_seed)
	events = result["events"]
	if result.has("pending"):
		pending = result["pending"]
	else:
		pending = {}
		var dicts: Array = []
		for s in round_sheets:
			dicts.append((s as Types.Sheet).to_dict())
		rounds_log.append(dicts)
		_absorb(round_sheets, result)
		save()
	if first:
		phase = Phase.CINEMA
		set_meta("opening_cinema", false)
		_emit_phase()
	else:
		extended.emit()


func answer(call: String) -> void:
	## The attacker's live call at the paused battle: record it on their sheet, go on.
	if pending.is_empty():
		return
	var pid: String = str(pending["attacker"])
	for raw in round_sheets:
		var sh: Types.Sheet = raw
		if sh.player_id == pid:
			var key: String = str(pending["key"])
			var list: Array = sh.calls.get(key, [])
			list.append(call)
			sh.calls[key] = list
	_run(false)


func release_live() -> void:
	## Nobody is watching any more (battles skipped): officers call the rest.
	live = []
	if not pending.is_empty():
		_run(false)


func officer_call() -> String:
	## What the sealed standing order says for the paused battle.
	if pending.is_empty():
		return Combat.CALL_PRESS
	return Combat.doctrine(str(pending.get("stance", "")), int(pending["a"]), int(pending["d"]), int(pending["reserves"]), str(pending["refuge"]) != "")


func _absorb(sheets: Array, result: Dictionary) -> void:
	## Shared by live play and save replay.
	events = result["events"]
	var prev_round: int = world.round
	world = result["world"]
	hashes.append(Hash.world_hash(world))
	ghosts = []
	for s in sheets:
		var sh: Types.Sheet = s
		for p in sh.packets:
			var pk: Types.Packet = p
			ghosts.append({"from": pk.from_id, "to": pk.to_id, "strength": pk.strength, "owner": sh.player_id, "surgeTo": pk.surge_to})
	_tally(events)
	_snapshot_history(prev_round)
	for e in events:
		if str(e.get("kind", "")) == Types.EVENT_ROUND_ENDED:
			winner = str(e.get("winner", ""))
			early = bool(e.get("early", false))


func _tally(evs: Array) -> void:
	var vacated := {}
	for e in evs:
		var k: String = str(e.get("kind", ""))
		match k:
			Types.EVENT_VACATED:
				vacated[str(e["from"])] = str(e["playerId"])
			Types.EVENT_OCCUPIED:
				var who: String = str(e["playerId"])
				var prev: String = str(e.get("previousOwner", ""))
				if stats.has(who) and prev != who:
					stats[who]["captures"] += 1
				var hex: String = str(e["terrId"])
				if vacated.has(hex) and vacated[hex] != who:
					if stats.has(who):
						stats[who]["walkins"] += 1
					if stats.has(vacated[hex]):
						stats[vacated[hex]]["walked"] += 1
			Types.EVENT_INVASION:
				var a: String = str(e["attackerId"])
				var d: String = str(e["defenderId"])
				var won: bool = bool(e["attackerWon"])
				for pid in [a, d]:
					if stats.has(pid):
						stats[pid]["battles"] += 1
				var winner_id: String = a if won else d
				if stats.has(winner_id):
					stats[winner_id]["won"] += 1
				## reserves fight too; men who fall back are saved, not lost
				var att_in: int = int(e["attackerSize"]) + int(e.get("reservesAdded", 0))
				var att_lost: int = att_in - (int(e["winnerRemaining"]) if won else int(e.get("attackerLeft", 0)))
				var def_lost: int = int(e["defenderSize"]) if won else int(e["defenderSize"]) - int(e["winnerRemaining"])
				if stats.has(a):
					stats[a]["armies_lost"] += att_lost
				if stats.has(d):
					stats[d]["armies_lost"] += def_lost
			Types.EVENT_CLASH, Types.EVENT_SPOILS:
				var w: String = str(e["winnerId"])
				for pid in [str(e["playerA"]), str(e["playerB"])]:
					if stats.has(pid):
						stats[pid]["battles"] += 1
						if pid == w:
							stats[pid]["won"] += 1
			Types.EVENT_PLAYER_ELIMINATED:
				pass
			Types.EVENT_SET_CASHED:
				if stats.has(str(e["playerId"])):
					stats[str(e["playerId"])]["sets"] += 1


func _snapshot_history(round_n: int) -> void:
	var terr := {}
	var score := {}
	var armies := {}
	for s in seats:
		var pid: String = s["id"]
		var mine := MapLib.player_territory_ids(world, pid)
		terr[pid] = mine.size()
		score[pid] = Income.score_of(world, map, pid)
		var a := 0
		for t in mine:
			a += world.get_territory(t).held()
		armies[pid] = a
	history.append({"round": round_n, "terr": terr, "score": score, "armies": armies})


func cinema_done() -> void:
	if phase != Phase.CINEMA:
		return
	phase = Phase.RECAP
	if bool(get_meta("opening_cinema", false)):
		## No recap after deployment: straight into round 1.
		_start_window(Phase.PLANNING)
		return
	_emit_phase()


func next_round() -> void:
	if phase != Phase.RECAP:
		return
	if winner != "":
		phase = Phase.GAME_OVER
		clear_save()
		_emit_phase()
		return
	_start_window(Phase.PLANNING)


func watch_on() -> void:
	watching = true


# ================================================================ planning helpers

func _empty(pid: String) -> Types.Sheet:
	var s := Types.Sheet.new()
	s.player_id = pid
	return s


func sheet() -> Types.Sheet:
	if not drafts.has(planner):
		drafts[planner] = _empty(planner)
	return drafts[planner]


func _post_regroup() -> Types.World:
	var w: Types.World = world.clone()
	var s: Types.Sheet = sheet()
	if s.regroup != null and world.round > 1:
		var origin: Types.TerritoryState = w.get_territory(s.regroup.from_id)
		if origin != null and s.regroup.strength <= Income.max_send(origin):
			Validate._apply_regroup_to(w, s)
	return w


func _post_place() -> Types.World:
	var w: Types.World = _post_regroup()
	Validate._apply_placements_to(w, map, sheet())
	return w


func projected_world() -> Types.World:
	## What the planner's own lands will look like the instant orders lock.
	if phase == Phase.OPENING:
		var w0: Types.World = world.clone()
		var place: Dictionary = opening.get(planner, {})
		for t in place.keys():
			w0.get_territory(str(t)).armies += int(place[t])
		return w0
	var w: Types.World = _post_place()
	for raw in sheet().packets:
		var p: Types.Packet = raw
		var ts: Types.TerritoryState = w.get_territory(p.from_id)
		if ts != null and ts.owner == planner:
			ts.armies = maxi(0 if ts.garrison >= 1 else 1, ts.armies - p.strength)
	return w


func income_total() -> int:
	if phase == Phase.OPENING:
		return Setup.pool_for(map, MapLib.living_player_ids(world).size()) - _dealt_armies(planner)
	return Income.income_of(_post_regroup(), map, planner) + Validate.cash_value_of(world, map, sheet())


func _dealt_armies(pid: String) -> int:
	var n := 0
	for t in MapLib.player_territory_ids(world, pid):
		n += world.get_territory(t).armies
	return n


func income_breakdown() -> Dictionary:
	var w: Types.World = _post_regroup()
	var terrs: int = MapLib.player_territory_ids(w, planner).size()
	return {
		"lands": maxi(Income.INCOME_FLOOR, terrs / 3),
		"bloc": Income.connected_bloc(w, map, planner) / 6,
		"regions": Income.region_bonus_of(w, map, planner),
		"cards": Validate.cash_value_of(world, map, sheet()),
	}


func placed_total() -> int:
	var src: Dictionary = opening.get(planner, {}) if phase == Phase.OPENING else sheet().placements
	var n := 0
	for k in src.keys():
		n += int(src[k])
	return n


func income_left() -> int:
	return maxi(0, income_total() - placed_total())


func placed_on(t: String) -> int:
	if phase == Phase.OPENING:
		return int(opening.get(planner, {}).get(t, 0))
	return int(sheet().placements.get(t, 0))


func place_cap(t: String) -> int:
	if phase == Phase.OPENING:
		return Setup.opening_cap(world, map, t)
	return Income.cap_of(_post_regroup(), map, t)


func add_place(t: String, delta: int) -> String:
	## Returns an explanation when the click does nothing.
	var ts: Types.TerritoryState = world.get_territory(t)
	if ts == null or ts.owner != planner:
		return "You can only reinforce your own lands."
	var cur: int = placed_on(t)
	var cap: int = place_cap(t)
	if delta > 0:
		if income_left() <= 0:
			return "No reinforcements left to place."
		if cur >= cap:
			return "%s can take at most %d (1 + your %d neighboring lands%s)." % [
				hex_name(t), cap, cap / (2 if phase == Phase.OPENING else 1) - 1,
				", doubled for deployment" if phase == Phase.OPENING else ""]
	var nxt: int = clampi(cur + delta, 0, cap)
	nxt = mini(nxt, cur + income_left()) if delta > 0 else nxt
	if phase == Phase.OPENING:
		if nxt == 0:
			opening[planner].erase(t)
		else:
			opening[planner][t] = nxt
	else:
		if nxt == 0:
			sheet().placements.erase(t)
		else:
			sheet().placements[t] = nxt
		clamp_packets()
	changed.emit()
	return ""


func clear_placements() -> void:
	if phase == Phase.OPENING:
		opening[planner] = {}
	else:
		sheet().placements = {}
		clamp_packets()
	changed.emit()


func auto_deploy() -> void:
	## Let the Quartermaster place the rest (opening or reinforcements).
	var rng: RefCounted = Rng.derive_stream(match_seed, world.round, "auto|" + planner + str(placed_total()))
	if phase == Phase.OPENING:
		var w: Types.World = projected_world()
		var extra: Dictionary = Ai.opening_placements(w, map, planner, rng, Ai.profile_for("veteran"))
		## opening_placements reads the pool from the projected world; respect our ceiling.
		for t in extra.keys():
			for _i in int(extra[t]):
				if add_place(str(t), 1) != "":
					break
		## anything left: spread over open room
		for t in MapLib.player_territory_ids(world, planner):
			while income_left() > 0 and add_place(t, 1) == "":
				pass
	else:
		var p := Ai.Planner.new()
		p.setup(world, map, planner, rng, Ai.profile_for("veteran"))
		var w2: Types.World = _post_regroup()
		p.w = w2
		p.begin(income_left())
		for t in sheet().placements.keys():
			p.cap[t] = maxi(0, int(p.cap.get(t, 0)) - int(sheet().placements[t]))
		for raw in sheet().packets:
			var pk: Types.Packet = raw
			p.sent[pk.from_id] = int(p.sent.get(pk.from_id, 0)) + pk.strength
		p.place_defense()
		p.place_leftover()
		for t in p.place.keys():
			for _i in int(p.place[t]):
				if add_place(str(t), 1) != "":
					break
	changed.emit()


func max_send(from_id: String, skip_packet: int = -1) -> int:
	## Armies that could leave from_id in an attack, counting queued placements.
	var w: Types.World = _post_place()
	var ts: Types.TerritoryState = w.get_territory(from_id)
	if ts == null or ts.owner != planner:
		return 0
	var n: int = ts.armies
	var i := 0
	for raw in sheet().packets:
		if i != skip_packet and (raw as Types.Packet).from_id == from_id:
			n -= (raw as Types.Packet).strength
		i += 1
	return maxi(0, n - (0 if ts.garrison >= 1 else 1))


func packet_index(from_id: String, to_id: String) -> int:
	var i := 0
	for raw in sheet().packets:
		var p: Types.Packet = raw
		if p.from_id == from_id and p.to_id == to_id:
			return i
		i += 1
	return -1


func set_attack(from_id: String, to_id: String, strength: int = -1) -> String:
	var a: Types.TerritoryState = world.get_territory(from_id)
	var b: Types.TerritoryState = world.get_territory(to_id)
	if a == null or b == null or a.owner != planner:
		return "Pick one of your own lands to attack from."
	if b.owner == planner:
		return "That land is already yours."
	if not map.is_adjacent(from_id, to_id):
		return "%s does not border %s." % [hex_name(to_id), hex_name(from_id)]
	var idx: int = packet_index(from_id, to_id)
	var mx: int = max_send(from_id, idx)
	if mx < 1:
		return _cannot_send(from_id)
	var n: int = mx if strength < 0 else clampi(strength, 1, mx)
	if idx >= 0:
		(sheet().packets[idx] as Types.Packet).strength = n
	else:
		var p := Types.Packet.new()
		p.from_id = from_id
		p.to_id = to_id
		p.strength = n
		p.stance = str(_setting("stance", Combat.STANCE_JUDGMENT))
		sheet().packets.append(p)
	changed.emit()
	return ""


func _cannot_send(from_id: String) -> String:
	var ts: Types.TerritoryState = world.get_territory(from_id)
	if ts.garrison < 1:
		return "%s must keep 1 army at home (it has no dug-in garrison yet)." % hex_name(from_id)
	return "Everyone who can march from %s is already marching." % hex_name(from_id)


func set_packet_strength(i: int, n: int) -> void:
	if i < 0 or i >= sheet().packets.size():
		return
	var p: Types.Packet = sheet().packets[i]
	p.strength = clampi(n, 1, maxi(1, max_send(p.from_id, i)))
	changed.emit()


func set_stance(i: int, stance: String) -> void:
	if i < 0 or i >= sheet().packets.size():
		return
	(sheet().packets[i] as Types.Packet).stance = stance
	var st: Node = get_node_or_null("/root/Settings")
	if st != null and not instant:
		st.remember("stance", stance) ## the next order starts with the same doctrine
	changed.emit()


func reserves_at(from_id: String) -> int:
	## Mobile armies still at home after this sheet's attacks leave: the reserves
	## a battle call can throw in (before anything else happens to the land).
	return max_send(from_id)


func remove_packet(i: int) -> void:
	if i < 0 or i >= sheet().packets.size():
		return
	sheet().packets.remove_at(i)
	changed.emit()


func set_surge(i: int, target: String) -> String:
	if i < 0 or i >= sheet().packets.size():
		return ""
	var p: Types.Packet = sheet().packets[i]
	if target == "":
		p.surge_to = ""
		changed.emit()
		return ""
	if target == p.from_id or not map.is_adjacent(p.to_id, target):
		return "A surge must go on to a land bordering %s." % hex_name(p.to_id)
	if world.get_territory(target).owner == planner:
		return "Surge targets an enemy or empty land."
	p.surge_to = target
	## Same-destination packets merge; keep their surge in step.
	for raw in sheet().packets:
		var q: Types.Packet = raw
		if q.to_id == p.to_id:
			q.surge_to = target
	changed.emit()
	return ""


func clamp_packets() -> void:
	var s: Types.Sheet = sheet()
	var i := 0
	while i < s.packets.size():
		var p: Types.Packet = s.packets[i]
		var mx: int = max_send(p.from_id, i)
		if mx < 1:
			s.packets.remove_at(i)
			continue
		if p.strength > mx:
			p.strength = mx
		i += 1


func max_regroup(from_id: String) -> int:
	if world.round <= 1:
		return 0
	var ts: Types.TerritoryState = world.get_territory(from_id)
	if ts == null or ts.owner != planner:
		return 0
	return Income.max_send(ts)


func set_regroup(from_id: String, to_id: String, n: int = -1) -> String:
	if world.round <= 1:
		return "No moves on round 1 — your first sheet is placements and attacks."
	var a: Types.TerritoryState = world.get_territory(from_id)
	var b: Types.TerritoryState = world.get_territory(to_id)
	if a == null or b == null or a.owner != planner or b.owner != planner:
		return "Moves go from one of your lands to a neighboring land of yours."
	if not map.is_adjacent(from_id, to_id):
		return "%s does not border %s." % [hex_name(to_id), hex_name(from_id)]
	var mx: int = max_regroup(from_id)
	if mx < 1:
		return "%s has nobody free to move (placements can't move the turn they arrive)." % hex_name(from_id)
	var r := Types.Regroup.new()
	r.from_id = from_id
	r.to_id = to_id
	r.strength = mx if n < 0 else clampi(n, 1, mx)
	sheet().regroup = r
	clamp_packets()
	changed.emit()
	return ""


func clear_regroup() -> void:
	sheet().regroup = null
	clamp_packets()
	changed.emit()


func hand() -> PackedStringArray:
	return world.players[planner].cards if world.players.has(planner) else PackedStringArray()


func toggle_cash() -> String:
	var s: Types.Sheet = sheet()
	if s.cash_set.size() > 0:
		s.cash_set = PackedStringArray()
	else:
		var best: PackedStringArray = Cards.best_set(hand())
		if best.is_empty():
			return "You need three matching cards or one of each."
		s.cash_set = best
	## Income changed: placements beyond it are trimmed.
	while placed_total() > income_total():
		var keys: Array = s.placements.keys()
		keys.sort()
		var last: String = str(keys[keys.size() - 1])
		s.placements[last] = int(s.placements[last]) - 1
		if int(s.placements[last]) <= 0:
			s.placements.erase(last)
	clamp_packets()
	changed.emit()
	return ""


func set_value_now() -> int:
	return Cards.set_value(world.sets_cashed)


func odds(att: int, def: int) -> Dictionary:
	var p: float = 1.0 if def <= 0 else Combat.capture_rate(att, def, map.battle)
	var word := "certain"
	if def > 0:
		word = Combat.odds_word(att, def, map.battle)
	return {"p": p, "word": word}


func expected_defense(to_id: String) -> Dictionary:
	## What the target holds now, and the most it could hold after its owner's hidden reinforcement.
	var ts: Types.TerritoryState = world.get_territory(to_id)
	var now: int = ts.held()
	var ceiling: int = now
	if ts.owner != Types.UNOCCUPIED and ts.owner != Income.NEUTRAL_ID:
		ceiling += Income.cap_of(world, map, to_id)
	return {"now": now, "ceiling": ceiling}


func hex_name(t: String) -> String:
	var d: Types.TerritoryDef = map.get_territory(t) if map else null
	return d.display_name if d else t


func warnings() -> PackedStringArray:
	## Advisor notes on the current sheet, worst first.
	var out := PackedStringArray()
	if phase != Phase.PLANNING and phase != Phase.OPENING:
		return out
	if income_left() > 0:
		if phase == Phase.OPENING:
			out.append("%d starting arm%s not placed yet — anything unplaced is lost." % [income_left(), "y" if income_left() == 1 else "ies"])
		else:
			out.append("%d reinforcement%s not placed yet — unplaced armies are lost." % [income_left(), "" if income_left() == 1 else "s"])
	if phase == Phase.PLANNING:
		var w: Types.World = projected_world()
		var warned := {}
		for raw in sheet().packets:
			var p: Types.Packet = raw
			if warned.has(p.from_id):
				continue
			var ts: Types.TerritoryState = w.get_territory(p.from_id)
			var left: int = ts.held()
			var danger := false
			for n in map.get_territory(p.from_id).adjacent:
				var o: String = world.get_territory(n).owner
				if o != planner and o != Types.UNOCCUPIED and o != Income.NEUTRAL_ID:
					danger = true
			if left <= 1 and danger:
				out.append("%s will be left with %d — a neighbor could walk right in." % [hex_name(p.from_id), left])
				warned[p.from_id] = true
		if hand().size() >= Cards.HAND_LIMIT and sheet().cash_set.is_empty():
			out.append("Your hand is full: trade a set in or you won't draw new cards.")
	return out


# ================================================================ save / load

func save() -> void:
	if setup_dict.is_empty():
		return
	var rec := {
		"version": SAVE_VERSION,
		"config": config,
		"matchSeed": match_seed,
		"mapId": map.id,
		"rounds": map.rounds,
		"setup": setup_dict,
		"sheets": rounds_log,
		"hashes": hashes,
		"saved": Time.get_datetime_string_from_system(false, true),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rec))


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func save_summary() -> Dictionary:
	if not has_save():
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	var map_name := str(d.get("mapId", ""))
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(d["config"]["map"])))
	if typeof(m) == TYPE_DICTIONARY:
		map_name = str(m.get("name", map_name))
	return {"map": map_name, "round": (d["sheets"] as Array).size() + 1, "saved": d.get("saved", "")}


func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func load_save() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	config = d["config"]
	match_seed = int(d["matchSeed"])
	config["seed"] = match_seed
	map = Types.MapDef.from_file(str(config["map"]))
	map.rounds = int(d.get("rounds", map.rounds))
	map.battle = str(config.get("battle", "decisive"))
	seats = config["seats"]
	stats = {}
	for s in seats:
		stats[s["id"]] = _blank_stats()
	setup_dict = d["setup"]
	world = Types.World.from_dict(setup_dict)
	rounds_log = []
	hashes = []
	history = []
	winner = ""
	watching = false
	_snapshot_history(0)
	for round_sheets in d["sheets"]:
		var sheets: Array = []
		for raw in round_sheets:
			sheets.append(Types.Sheet.from_dict(raw))
		var result: Dictionary = Resolve.resolve_round(world, map, sheets, match_seed)
		if not result["errors"].is_empty():
			push_error("save replay diverged: %s" % " ".join(result["errors"]))
			return false
		rounds_log.append(round_sheets)
		_absorb(sheets, result)
	var saved_hashes: Array = d.get("hashes", [])
	if saved_hashes.size() == hashes.size() and not saved_hashes.is_empty() and str(saved_hashes[-1]) != str(hashes[-1]):
		push_warning("save replay hash differs from recorded hash")
	events = []
	if winner != "":
		phase = Phase.GAME_OVER
		_emit_phase()
		return true
	_start_window(Phase.PLANNING)
	return true


# ================================================================ timer

func _process(delta: float) -> void:
	if time_left <= 0.0:
		return
	if phase != Phase.PLANNING and phase != Phase.OPENING:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		timeout_lock()


# ================================================================ leaderboard

func standings() -> Array:
	## Living and dead, best first: score, regions, armies.
	var rows: Array = []
	for s in seats:
		var pid: String = s["id"]
		var alive: bool = world.players.has(pid) and world.players[pid].alive
		var mine := MapLib.player_territory_ids(world, pid)
		var armies := 0
		for t in mine:
			armies += world.get_territory(t).held()
		var regions := 0
		for r in map.region_bonus.keys():
			if MapLib.holds_region(world, map, pid, str(r)):
				regions += 1
		rows.append({
			"id": pid, "name": s["name"], "alive": alive,
			"score": Income.score_of(world, map, pid), "lands": mine.size(),
			"regions": regions, "armies": armies,
			"income": Income.income_of(world, map, pid) if alive else 0,
			"cards": world.players[pid].cards.size() if world.players.has(pid) else 0,
			"human": s["kind"] == "human",
		})
	rows.sort_custom(func(a, b):
		if a["alive"] != b["alive"]:
			return a["alive"]
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		if a["regions"] != b["regions"]:
			return a["regions"] > b["regions"]
		return a["armies"] > b["armies"])
	return rows
