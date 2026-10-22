## One match, any mix of humans and AI commanders, 2–5 seats.
## Holds match_seed; never writes it onto World. The UI reads this and calls in;
## nothing here draws. Every resolved round is autosaved as a replayable record.
extends Node

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Fortune := preload("res://engine/fortune.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Resolve := preload("res://engine/resolve.gd")
const Combat := preload("res://engine/combat.gd")
const Cards := preload("res://engine/cards.gd")
const Rng := preload("res://engine/rng.gd")
const Hash := preload("res://engine/hash.gd")
const Ai := preload("res://engine/ai.gd")
const Telemetry := preload("res://engine/telemetry.gd")
const Maneuver := preload("res://engine/maneuver.gd")
const Capitals := preload("res://engine/capitals.gd")
const LastRound := preload("res://game/core/last_round.gd")
const BoardFacts := preload("res://game/core/board_facts.gd")

enum Phase { NONE, OPENING, PASS, PLANNING, RESOLVING, CINEMA, RECAP, GAME_OVER, MANEUVER, DRAFT }

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
var opening_capital := {} ## v1.8: pid -> the land a commander named their capital at deployment
var locked := {} ## pid -> Sheet (or opening dict)
var setup_dict: Dictionary = {}
var rounds_log: Array = [] ## [[sheet dicts]]
var hashes: Array = []
var history: Array = [] ## [{round, terr: {pid: n}, score: {pid: n}}]
var cash_log: Array = [] ## v1.6: every set turned in: [{round, pid, value, lands}], for the end-of-war chart
var capital_log: Array = [] ## v1.9: every capital taken: [{round, pid (who lost it), by, land}], for the chart
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
var moves := {} ## pid -> [{from, to, n}] being written in the regroup phase
var maneuvers_log: Array = [] ## per resolved round: {pid: [moves]} made after its battles
var move_ghosts: Array = [] ## the last regroup phase's marches, for the board
var draft := {} ## v1.4 lands claimed in turn: {throws, order, turns, i, quota, claims: [{pid, land}]}
var plan_step := "reinforce" ## v1.5: each commander's planning in two steps: place the recruits, then write the orders


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
	var drafting: bool = str(config.get("deal", "random")) == "draft"
	world = Setup.draft_world(map, _seat_list(), match_seed) if drafting else Setup.deal(map, _seat_list(), match_seed)
	## Neutral name in two-seat games
	if world.players.has(Income.NEUTRAL_ID):
		world.players[Income.NEUTRAL_ID].display_name = "Neutral"
	setup_dict = {}
	rounds_log = []
	maneuvers_log = []
	move_ghosts = []
	hashes = []
	history = []
	cash_log = []
	capital_log = []
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
	opening_capital = {}
	locked = {}
	draft = {}
	if drafting:
		_start_draft()
	else:
		_start_window(Phase.OPENING)


func _apply_rules(fresh: bool) -> void:
	## v1.8 the table's rules (game/core/rules.gd). A save from before v1.8 has none of these
	## keys and plays exactly as it did: surges on, the map's own features and cards, no levée.
	map.levee = int(config.get("levee", 3 if fresh else 0))
	map.surges = bool(config.get("surges", true))
	if config.has("cards"):
		map.cards = map.cards and bool(config["cards"])
	if not bool(config.get("terrain", true)):
		map.supply = false
		for tid in map.territory_ids():
			(map.get_territory(tid) as Types.TerritoryDef).traits = PackedStringArray()
	if fresh:
		config["levee"] = map.levee
		config["surges"] = map.surges


func _apply_length() -> void:
	map.battle = str(config.get("battle", "volleys"))
	config["battle"] = map.battle ## saves must replay with the same dice
	## v1.3 rules for new games: a regroup phase, and a deck of men, horses and cannon
	map.maneuvers = bool(config.get("maneuvers", true))
	config["maneuvers"] = map.maneuvers
	map.wild_cards = bool(config.get("wild_cards", false))
	config["wild_cards"] = map.wild_cards
	## v1.4 rules for new games: victors who meet over one prize fight it out all at once
	map.scramble = bool(config.get("scramble", true))
	config["scramble"] = map.scramble
	## ...and nobody digs in deeper than three (v1.4 capped it at two)
	map.dig_cap = int(config.get("dig_cap", 3))
	config["dig_cap"] = map.dig_cap
	## v1.5 rules: surges clash head-on and carry a count; v1.6: the firing line, fair ties,
	## and campaign cards with a land on each; v1.7: an even volley is fired again in every
	## battle actually fought, and a pass holds to its column of six, surges and reserves too
	map.rules = int(config.get("rules", 22)) ## v2.2: rules 22 (an exchange Fortune throws away from you is owed you)
	config["rules"] = map.rules
	map.first_digs_in = bool(config.get("first_digs_in", false))
	config["first_digs_in"] = map.first_digs_in
	map.fire_line = bool(config.get("firing_line", true))
	config["firing_line"] = map.fire_line
	## v1.8: every commander keeps a capital (setup: Capitals), and Fortune keeps a ledger
	map.capitals = bool(config.get("capitals", true))
	config["capitals"] = map.capitals
	map.fortune = bool(config.get("fortune", true))
	config["fortune"] = map.fortune
	_apply_rules(true)
	Combat.use_rules(map)
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
	return {"captures": 0, "walkins": 0, "walked": 0, "battles": 0, "won": 0, "armies_lost": 0, "kills": 0, "sets": 0,
		"luck_n": 0, "luck_odds": 0.0, "luck_won": 0} ## v1.8: battles against the odds quoted when they began


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
	if kind == Phase.OPENING:
		opening_capital = {}
	locked = {}
	error_text = ""
	queue = living_humans()
	moves = {}
	for pid in MapLib.living_player_ids(world):
		if kind == Phase.OPENING:
			opening[pid] = {}
		elif kind == Phase.MANEUVER:
			moves[pid] = []
		else:
			drafts[pid] = _empty(pid)
	if queue.is_empty():
		watching = true
		_finish_window(kind)
		return
	_next_planner(kind)


func _next_planner(kind: int) -> void:
	planner = str(queue.pop_front())
	plan_step = "reinforce"
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
	elif phase == Phase.MANEUVER:
		var mine: Array = moves.get(planner, [])
		var errs0 := Maneuver.validate(world, map, planner, mine)
		if not errs0.is_empty():
			error_text = errs0[0]
			changed.emit()
			return error_text
		locked[planner] = mine.duplicate(true)
	elif phase == Phase.PLANNING:
		var s: Types.Sheet = sheet()
		if world.round <= 1 or map.maneuvers:
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
	elif kind == Phase.MANEUVER:
		_resolve_maneuvers()
	else:
		_resolve_round()


func _resolve_maneuvers() -> void:
	## Everyone's marches land at once (they only touch their own lands).
	var by := {}
	for pid in MapLib.living_player_ids(world):
		if pid == Income.NEUTRAL_ID:
			continue
		by[pid] = locked[pid] if locked.has(pid) else Maneuver.plan(world, map, pid, {} if is_human(pid) else Ai.profile_for(ai_of(pid)))
	var evs: Array = Maneuver.apply(world, map, by)
	while maneuvers_log.size() < rounds_log.size():
		maneuvers_log.append({})
	if not rounds_log.is_empty():
		maneuvers_log[rounds_log.size() - 1] = by.duplicate(true)
	move_ghosts = []
	for e in evs:
		move_ghosts.append({"from": str(e["from"]), "to": str(e["to"]), "strength": int(e["strength"]), "owner": str(e["playerId"]), "kind": "move"})
	save()
	_start_window(Phase.PLANNING)


func _resolve_opening() -> void:
	var placements := {}
	for pid in MapLib.living_player_ids(world):
		if locked.has(pid):
			placements[pid] = locked[pid]
		else:
			var rng: RefCounted = Rng.derive_stream(match_seed, 0, "open|" + pid)
			placements[pid] = Ai.opening_placements(world, map, pid, rng, Ai.profile_for(ai_of(pid)))
	pre_world = world.clone()
	var cap_events: Array = []
	Setup.apply_opening(world, map, placements, opening_capital, cap_events)
	setup_dict = world.to_dict()
	events = cap_events.duplicate() ## v1.8: the crowns go up first, as the armies deploy
	for pid in placements.keys():
		var place: Dictionary = placements[pid]
		for t in place.keys():
			var ts: Types.TerritoryState = world.get_territory(str(t))
			if ts.owner == pid and int(place[t]) > 0:
				events.append({"kind": Types.EVENT_PLACED, "playerId": pid, "terrId": str(t), "added": ts.armies + ts.garrison - pre_world.get_territory(str(t)).held(), "armies": ts.armies, "garrison": ts.garrison, "overflow": 0})
	## v1.5: lands that got no recruits still dig in their first soldier; show it
	var shown := {}
	for e in events:
		if str(e["kind"]) == Types.EVENT_PLACED:
			shown[str(e["terrId"])] = true
	var ids: Array = Array(map.territory_ids())
	for t in ids:
		var ts2: Types.TerritoryState = world.get_territory(str(t))
		if not shown.has(str(t)) and ts2.garrison > pre_world.get_territory(str(t)).garrison:
			events.append({"kind": Types.EVENT_ENTRENCHED, "terrId": str(t), "garrison": ts2.garrison, "cap": Income.garrison_cap(world, map, str(t)), "converted": ts2.garrison - pre_world.get_territory(str(t)).garrison})
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


# ================================================================ reinforcement, then orders (v1.5)

func begin_orders() -> void:
	## the recruits are placed: on to the orders (the sheet is the same; this is the screen)
	if phase == Phase.PLANNING and plan_step != "orders":
		plan_step = "orders"
		changed.emit()


func back_to_reinforce() -> void:
	if phase == Phase.PLANNING and plan_step != "reinforce":
		plan_step = "reinforce"
		changed.emit()


# ================================================================ the land draft (v1.4)

func _start_draft() -> void:
	var pids: Array = []
	for s in seats:
		pids.append(str(s["id"]))
	var roll: Dictionary = Setup.order_roll(match_seed, pids)
	var free := 0
	for t in map.territory_ids():
		if world.get_territory(str(t)).owner == Types.UNOCCUPIED:
			free += 1
	var quota: int = Setup.draft_quota(map, seats.size())
	draft = {"throws": roll["throws"], "order": roll["order"], "turns": Setup.draft_turns(roll["order"], quota, free), "i": 0, "quota": quota, "claims": []}
	_draft_planner()
	phase = Phase.DRAFT
	_emit_phase()
	if instant:
		while drafting():
			ai_claim()


func drafting() -> bool:
	return phase == Phase.DRAFT and not draft.is_empty() and int(draft["i"]) < (draft["turns"] as Array).size()


func draft_turn() -> String:
	## whose claim it is ("" once the draft is done)
	if draft.is_empty() or int(draft["i"]) >= (draft["turns"] as Array).size():
		return ""
	return str(draft["turns"][int(draft["i"])])


func draft_left(pid: String) -> int:
	var n := 0
	for k in range(int(draft.get("i", 0)), (draft.get("turns", []) as Array).size()):
		if str(draft["turns"][k]) == pid:
			n += 1
	return n


func _draft_planner() -> void:
	## the board's eyes: whoever is choosing, if they're at the table; else the first human
	var t: String = draft_turn()
	if t != "" and is_human(t):
		planner = t
	elif planner == "" or not is_human(planner):
		var h: Array = living_humans()
		planner = str(h[0]) if not h.is_empty() else ""


func claim(id: String) -> String:
	## the commander whose turn it is plants a flag on a free land
	if not drafting():
		return "The lands are all claimed."
	var ts: Types.TerritoryState = world.get_territory(id)
	if ts == null or ts.owner != Types.UNOCCUPIED:
		return "%s is already taken — pick a free land." % hex_name(id)
	var pid: String = draft_turn()
	world.set_hex(id, pid, 1)
	Capitals.claimed(world, map, pid, id) ## v1.8: your first claim is your capital
	(draft["claims"] as Array).append({"pid": pid, "land": id})
	draft["i"] = int(draft["i"]) + 1
	if int(draft["i"]) >= (draft["turns"] as Array).size():
		Setup.finish_draft(world, map, seats.size())
		_draft_planner()
		changed.emit()
		_start_window(Phase.OPENING)
		return ""
	_draft_planner()
	changed.emit()
	return ""


func draft_pick_for(pid: String) -> String:
	## the land this commander's brain would claim now (the advisor's pick, for a human)
	var picks := {}
	for s in seats:
		picks[str(s["id"])] = draft_left(str(s["id"]))
	var rng: RefCounted = Rng.derive_stream(match_seed, 0, "draft|%d" % int(draft.get("i", 0)))
	## a human's "pick for me" gets the chief of staff, who thinks like the hard commanders
	var prof: Dictionary = Ai.profile_for(ai_of(pid)) if not is_human(pid) else {"search": true, "region": 1.25, "noise": 0.0}
	var upcoming: Array = (draft["turns"] as Array).slice(int(draft.get("i", 0)) + 1)
	return Ai.draft_pick(world, map, pid, rng, prof, picks, upcoming)


func ai_claim() -> String:
	## the commander whose turn it is claims by their own lights; returns the land
	if not drafting():
		return ""
	var land: String = draft_pick_for(draft_turn())
	if land == "":
		return ""
	claim(land)
	return land


# ================================================================ regroup phase

func maneuver_world() -> Types.World:
	## the planner's own marches drawn in (what the board shows while they write them)
	var w: Types.World = world.clone()
	for m in moves.get(planner, []):
		w.get_territory(str(m["from"])).armies -= int(m["n"])
		w.get_territory(str(m["to"])).armies += int(m["n"])
	return w


func my_moves() -> Array:
	return moves.get(planner, [])


func move_index(from_id: String, to_id: String) -> int:
	var i := 0
	for m in my_moves():
		if str(m["from"]) == from_id and str(m["to"]) == to_id:
			return i
		i += 1
	return -1


func can_move_from(from_id: String, skip: int = -1) -> int:
	## soldiers who could still march out of from_id (each moves one land, once)
	var n: int = Maneuver.can_leave(world, from_id)
	var i := 0
	for m in my_moves():
		if i != skip and str(m["from"]) == from_id:
			n -= int(m["n"])
		i += 1
	return maxi(0, n)


func add_move(from_id: String, to_id: String, n: int = -1) -> String:
	if phase != Phase.MANEUVER:
		return "Troops march in the regroup phase, after the battles."
	var a: Types.TerritoryState = world.get_territory(from_id)
	var b: Types.TerritoryState = world.get_territory(to_id)
	if a == null or b == null or a.owner != planner or b.owner != planner:
		return "March between two of your own lands."
	if not marches_to(from_id, to_id):
		return "One land at a time: %s does not border %s." % [hex_name(to_id), hex_name(from_id)]
	var idx: int = move_index(from_id, to_id)
	var mx: int = can_move_from(from_id, idx)
	if mx < 1:
		if Maneuver.can_leave(world, from_id) < 1:
			return "%s has nobody who can march (one stays unless it is dug in; soldiers who just arrived stay put)." % hex_name(from_id)
		return "Everyone who can leave %s is already marching." % hex_name(from_id)
	var k: int = mx if n < 0 else clampi(n, 1, mx)
	if idx >= 0:
		my_moves()[idx]["n"] = k
	else:
		my_moves().append({"from": from_id, "to": to_id, "n": k})
	changed.emit()
	return ""


func set_move(i: int, n: int) -> void:
	if i < 0 or i >= my_moves().size():
		return
	var m: Dictionary = my_moves()[i]
	m["n"] = clampi(n, 1, maxi(1, can_move_from(str(m["from"]), i)))
	changed.emit()


func remove_move(i: int) -> void:
	if i < 0 or i >= my_moves().size():
		return
	my_moves().remove_at(i)
	changed.emit()


func clear_moves() -> void:
	moves[planner] = []
	changed.emit()


func advise_moves() -> void:
	## the chief of staff's marches, adopted in one click
	moves[planner] = Maneuver.plan(world, map, planner, {"search": true}) ## the chief of staff marches to strike
	changed.emit()


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
	## v1.8: at a Fortune pause the chooser may be the defender; and for an attacker whose
	## battle goes on, one plate answers both (Fortune declined, then the call made)
	var pid: String = str(pending.get("chooser", pending["attacker"]))
	var add: Array = [call]
	if bool(pending.get("fortune", false)) and call != Combat.CALL_FORTUNE:
		add = [Combat.CALL_STAND]
		if str(pending.get("side", "")) == "a" and not bool(pending.get("ended", false)) and call != Combat.CALL_STAND:
			add.append(call)
	for raw in round_sheets:
		var sh: Types.Sheet = raw
		if sh.player_id == pid:
			var key: String = str(pending["key"])
			var list: Array = sh.calls.get(key, [])
			list.append_array(add)
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
	if bool(pending.get("fortune", false)) and (str(pending.get("side", "")) == "d" or bool(pending.get("ended", false))):
		return Combat.CALL_STAND ## officers never spend a commander's favours
	return Combat.doctrine(str(pending.get("stance", "")), int(pending["a"]), int(pending["d"]), int(pending["reserves"]), str(pending["refuge"]) != "")


func _absorb(sheets: Array, result: Dictionary) -> void:
	## Shared by live play and save replay.
	events = result["events"]
	var prev_round: int = world.round
	var before: Types.World = world
	world = result["world"]
	hashes.append(Hash.world_hash(world))
	## last round's marches, as they actually went, each with its fate (v1.13: game/core/last_round.gd;
	## a column beaten in a border clash now shows where it died, and a surge only if it set off)
	ghosts = LastRound.ghosts(before, world, sheets, events, map.rules)
	_tally(events)
	_luck(events, before)
	for e in events:
		if str(e.get("kind", "")) == Types.EVENT_SET_CASHED:
			cash_log.append({"round": prev_round, "pid": str(e.get("playerId", "")), "value": int(e.get("value", 0)), "lands": e.get("lands", [])})
		elif str(e.get("kind", "")) == Types.EVENT_CAPITAL_TAKEN:
			capital_log.append({"round": prev_round, "pid": str(e.get("playerId", "")), "by": str(e.get("by", "")), "land": str(e.get("terrId", ""))})
	_snapshot_history(prev_round)
	for e in events:
		if str(e.get("kind", "")) == Types.EVENT_ROUND_ENDED:
			winner = str(e.get("winner", ""))
			early = bool(e.get("early", false))


func _luck(evs: Array, before: Types.World) -> void:
	## v1.8 the luck ledger: every one-on-one battle, won or lost, against the odds quoted as
	## it began. A commander who wins what the odds said breaks even; the dice owe the rest.
	## (Retreats are left out: falling back is a choice, not a roll.)
	for e in evs:
		var k: String = str(e.get("kind", ""))
		if k == Types.EVENT_INVASION and e.has("luck"):
			## v1.9: the dice's swing measured exchange by exchange (a battle abandoned halfway
			## counts for the exchanges that were fought; the choice to leave does not)
			_luck_swing(str(e["attackerId"]), float(e["luck"]) / 100.0)
			_luck_swing(str(e["defenderId"]), -float(e["luck"]) / 100.0)
		elif k == Types.EVENT_INVASION and not bool(e.get("fellBack", false)):
			var a: String = str(e["attackerId"])
			var d: String = str(e["defenderId"])
			var p: float = Combat.capture_rate(int(e["attackerSize"]), int(e["defenderSize"]), map.battle, MapLib.defender_bonus(before, map, str(e.get("to", ""))))
			var won: bool = bool(e["attackerWon"])
			_luck_add(a, p, won)
			_luck_add(d, 1.0 - p, not won)
		elif map.rules >= 19 and k in [Types.EVENT_CLASH, Types.EVENT_SPOILS, Types.EVENT_MELEE, Types.EVENT_SCRAMBLE]:
			## v1.10: every fight, weighed as Fortune weighs it
			var fl: Dictionary = Fortune.fight_luck(e, map.battle)
			for pid in fl.keys():
				_luck_swing(str(pid), float(fl[pid]) / 100.0)
		elif k == Types.EVENT_CLASH:
			var pa: float = Combat.volley_capture_rate(int(e["sizeA"]), int(e["sizeB"]), true) if map.battle == Combat.MODE_VOLLEYS else Combat.capture_rate(int(e["sizeA"]), int(e["sizeB"]), map.battle)
			var wa: bool = str(e["winnerId"]) == str(e["playerA"])
			_luck_add(str(e["playerA"]), pa, wa)
			_luck_add(str(e["playerB"]), 1.0 - pa, not wa)


func _luck_add(pid: String, p: float, won: bool) -> void:
	if not stats.has(pid):
		return
	var st: Dictionary = stats[pid]
	st["luck_n"] = int(st.get("luck_n", 0)) + 1
	st["luck_odds"] = float(st.get("luck_odds", 0.0)) + p
	st["luck_won"] = int(st.get("luck_won", 0)) + (1 if won else 0)


func _luck_swing(pid: String, sw: float) -> void:
	if not stats.has(pid):
		return
	var st: Dictionary = stats[pid]
	st["luck_n2"] = int(st.get("luck_n2", 0)) + 1
	st["luck_sw"] = float(st.get("luck_sw", 0.0)) + sw


func luck_of(pid: String) -> Dictionary:
	## {n, expected, won, swing, measured}: swing > 0 the dice were kind, < 0 they owed you.
	## measured: battles weighed exchange by exchange (v1.9), the rest by their outcome.
	var st: Dictionary = stats.get(pid, {})
	var n: int = int(st.get("luck_n", 0))
	var ex: float = float(st.get("luck_odds", 0.0))
	var wn: int = int(st.get("luck_won", 0))
	var n2: int = int(st.get("luck_n2", 0))
	return {"n": n + n2, "expected": ex, "won": wn, "swing": float(wn) - ex + float(st.get("luck_sw", 0.0)), "measured": n2}


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
			Types.EVENT_MELEE:
				var held: bool = int(e.get("defenderLeft", 0)) > 0
				var dp: String = str(e.get("defenderId", ""))
				if stats.has(dp):
					stats[dp]["battles"] += 1
					stats[dp]["armies_lost"] += int(e.get("defenderSize", 0)) - int(e.get("defenderLeft", 0))
					if held:
						stats[dp]["won"] += 1
				var counted := {} ## v2.1: a commander on two fronts fought one battle (won it once)
				for f in e.get("fronts", []):
					var ap: String = str(f.get("attackerId", ""))
					if not stats.has(ap):
						continue
					if not counted.has(ap):
						counted[ap] = false
						stats[ap]["battles"] += 1
					stats[ap]["armies_lost"] += int(f.get("size", 0)) + int(f.get("reservesAdded", 0)) - int(f.get("left", 0))
					if not held and int(f.get("left", 0)) > 0 and not bool(f.get("fellBack", false)) and not bool(counted[ap]):
						counted[ap] = true
						stats[ap]["won"] += 1
			Types.EVENT_SCRAMBLE:
				for f in e.get("fronts", []):
					var sp: String = str(f.get("playerId", ""))
					if not stats.has(sp):
						continue
					stats[sp]["battles"] += 1
					stats[sp]["armies_lost"] += int(f.get("size", 0)) - int(f.get("left", 0))
					if sp == str(e.get("winnerId", "")):
						stats[sp]["won"] += 1
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
	move_ghosts = []
	_start_window(Phase.MANEUVER if map.maneuvers else Phase.PLANNING)


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
		## v2.3: never more than the lands can take. The Isthmus deals 15 to a shore whose three lands
		## hold 4, 6 and 4: the last man could only ever be lost, and the tutorial's very first SEAL asked
		## about him ("1 troop still unplaced"). The world after deployment is the same either way.
		var room := 0
		for t in MapLib.player_territory_ids(world, planner):
			room += Setup.opening_cap(world, map, t)
		return mini(Setup.pool_for(map, MapLib.living_player_ids(world).size()) - _dealt_armies(planner), room)
	return Income.income_of(_post_regroup(), map, planner) + Validate.cash_value_of(world, map, sheet())


func _dealt_armies(pid: String) -> int:
	var n := 0
	for t in MapLib.player_territory_ids(world, pid):
		n += world.get_territory(t).armies
	return n


func income_breakdown() -> Dictionary:
	## v1.13: the parts add up to income_total(), as Income.income_of counts them: only the lands
	## in supply pay, and a held capital's treasury and the levée are recruits too
	var w: Types.World = _post_regroup()
	var terrs: int = MapLib.player_territory_ids(w, planner).size()
	var cut := 0
	if map.supply:
		var fed: Dictionary = MapLib.supplied_ids(w, map, planner)
		cut = terrs - fed.size()
		terrs = fed.size()
	return {
		"lands": maxi(Income.INCOME_FLOOR, terrs / 3),
		"bloc": Income.connected_bloc(w, map, planner) / 6,
		"regions": Income.region_bonus_of(w, map, planner),
		"capital": Income.treasury_of(w, map, planner),
		"levee": Income.levee_of(w, map, planner),
		"cards": Validate.cash_value_of(world, map, sheet()),
		"cut": cut, ## lands that pay nothing, cut off from the road home
	}


func placed_total() -> int:
	var src: Dictionary = opening.get(planner, {}) if phase == Phase.OPENING else sheet().placements
	var n := 0
	for k in src.keys():
		n += int(src[k])
	return n


func income_left() -> int:
	return maxi(0, income_total() - placed_total())


func placeable_left() -> int:
	## v2.3: the recruits still to place that have somewhere to go: income_left(), but never more than
	## the room left on the planner's lands. Lands that border none of yours take one each, so a deal
	## of three lone lands on the Isthmus can place 3 of 5, and the other 2 only ever went home; the
	## game used to ask about them every round ("2 recruits still unplaced"), and "Place them for me"
	## could do nothing.
	var room := 0
	for t in MapLib.player_territory_ids(world, planner):
		room += maxi(0, place_cap(t) - placed_on(t))
	return mini(income_left(), room)


func no_room() -> int:
	## recruits this round with nowhere they may go (they go home at the seal, as ever)
	return income_left() - placeable_left()


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
		if cap == 0 and phase != Phase.OPENING and map.supply and not MapLib.in_supply(world, map, t):
			return "%s is cut off: no recruits can reach it until the road home is open again." % hex_name(t) ## v1.13
		if cur >= cap:
			var nb: int = cap / (2 if phase == Phase.OPENING else 1) - 1
			return "%s can take at most %d (1 + your %d neighboring %s%s)." % [
				hex_name(t), cap, nb, "land" if nb == 1 else "lands",
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


func capital_choosable() -> bool:
	## v1.8: may the planner name their capital now? At deployment after a random deal (a
	## draft's first claim already is one), or the round after their capital fell.
	if not map.capitals or planner == "" or not world.players.has(planner):
		return false
	var ps: Types.PlayerState = world.players[planner]
	if phase == Phase.OPENING:
		return ps.capital == ""
	return phase == Phase.PLANNING and ps.capital_free


func capital_shown(pid: String) -> String:
	## the capital the board shows for pid: the planner's own choice while they make it
	if not map.capitals or not world.players.has(pid):
		return ""
	var ps: Types.PlayerState = world.players[pid]
	if phase == Phase.OPENING and ps.capital == "":
		if pid != planner:
			return "" ## the others' choices are sealed until deployment ends
		return str(opening_capital.get(pid, Capitals.auto_pick(world, map, pid)))
	if phase == Phase.PLANNING and pid == planner and ps.capital_free and sheet().capital != "":
		return sheet().capital
	return MapLib.capital_of(world, map, pid)


func set_capital(id: String) -> String:
	if not capital_choosable():
		return "Your capital stands where it is."
	var ts: Types.TerritoryState = world.get_territory(id)
	if ts == null or ts.owner != planner:
		return "Your capital must be one of your own lands."
	if phase == Phase.OPENING:
		opening_capital[planner] = id
	else:
		sheet().capital = id if id != MapLib.capital_of(world, map, planner) else ""
	changed.emit()
	return ""


func max_attack(from_id: String, to_id: String, skip_packet: int = -1) -> int:
	## max_send, and v1.7: no more than a pass's column may storm it from any one land
	var mx: int = max_send(from_id, skip_packet)
	var col: int = MapLib.column_cap(map, to_id)
	return mini(mx, col) if col > 0 else mx


func marches_to(from_id: String, to_id: String) -> bool:
	## a march or a move: a neighbouring land, or v1.7 another of your ports across the sea
	return Array(MapLib.supply_links(world, map, from_id)).has(to_id)


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
	var mx: int = max_attack(from_id, to_id, idx)
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
		p.surge_to = str(sheet().surges.get(to_id, "")) ## joins the surge already ordered from there
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
	p.strength = clampi(n, 1, maxi(1, max_attack(p.from_id, p.to_id, i)))
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
	var to: String = (sheet().packets[i] as Types.Packet).to_id
	sheet().packets.remove_at(i)
	var still := false
	for raw in sheet().packets:
		if (raw as Types.Packet).to_id == to:
			still = true
	if not still:
		sheet().surges.erase(to)
	changed.emit()


func set_surge(i: int, target: String) -> String:
	if i < 0 or i >= sheet().packets.size():
		return ""
	if target != "" and not map.surges:
		return "Surges are off in this war (Rules on the setup screen)."
	var p: Types.Packet = sheet().packets[i]
	if target == "":
		for raw in sheet().packets:
			if (raw as Types.Packet).to_id == p.to_id:
				(raw as Types.Packet).surge_to = ""
		sheet().surges.erase(p.to_id)
		sheet().surge_n.erase(p.to_id)
		changed.emit()
		return ""
	if target == p.from_id or not map.is_adjacent(p.to_id, target):
		return "A surge must go on to a land bordering %s." % hex_name(p.to_id)
	if world.get_territory(target).owner == planner:
		return "Surge targets an enemy or empty land."
	p.surge_to = target
	## v1.3: the surge belongs to the land being taken, so every army converging on it
	## (from any of your lands) pushes on together
	sheet().surges[p.to_id] = target
	for raw in sheet().packets:
		var q: Types.Packet = raw
		if q.to_id == p.to_id:
			q.surge_to = target
	changed.emit()
	return ""


func surge_count(dest: String) -> int:
	## v1.5: how many the surge from dest is ordered to push on with (0 = all but the one who stays)
	return int(sheet().surge_n.get(dest, 0))


func surge_most(dest: String) -> int:
	## the most who could push on: everyone sent at dest, less the one who stays
	var total := 0
	for raw in sheet().packets:
		if (raw as Types.Packet).to_id == dest:
			total += (raw as Types.Packet).strength
	var most: int = maxi(1, total - 1)
	var on: String = str(sheet().surges.get(dest, ""))
	if on != "" and map.rules >= 17 and MapLib.column_cap(map, on) > 0:
		most = mini(most, MapLib.column_cap(map, on)) ## v1.7: into a pass, a column of six at most
	return most


func set_surge_count(dest: String, n: int) -> void:
	if not sheet().surges.has(dest):
		return
	if n <= 0 or n >= surge_most(dest):
		sheet().surge_n.erase(dest) ## all who can
	else:
		sheet().surge_n[dest] = n
	changed.emit()


func clamp_packets() -> void:
	var s: Types.Sheet = sheet()
	var i := 0
	while i < s.packets.size():
		var p: Types.Packet = s.packets[i]
		var mx: int = max_attack(p.from_id, p.to_id, i)
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
	if not marches_to(from_id, to_id):
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


func best_set() -> PackedStringArray:
	## the planner's best set: v1.6 prefers cards naming lands they hold (a free soldier each)
	var owned := {}
	for t in MapLib.player_territory_ids(world, planner):
		owned[t] = true
	return Cards.best_set(hand(), owned)


func card_bonus_lands() -> Array:
	## the lands the set being turned in puts a free soldier on
	var out: Array = []
	if Validate.cash_value_of(world, map, sheet()) <= 0:
		return out
	for c in sheet().cash_set:
		var ln: String = Cards.land(c)
		if ln != "" and world.get_territory(ln) != null and world.get_territory(ln).owner == planner:
			out.append(ln)
	return out


func toggle_cash() -> String:
	var s: Types.Sheet = sheet()
	if s.cash_set.size() > 0:
		return set_cash(PackedStringArray())
	var best: PackedStringArray = best_set()
	if best.is_empty():
		return "You need three matching cards or one of each."
	return set_cash(best)


func set_cash(cards: PackedStringArray) -> String:
	## turn in exactly these three cards this round (empty = keep them all)
	var s: Types.Sheet = sheet()
	if cards.size() > 0:
		if not Cards.is_set(Array(cards)):
			return "Three alike, or one of each."
		if not Cards.holds(hand(), cards):
			return "You don't hold those cards."
	s.cash_set = cards
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


func odds(att: int, def: int, to_id: String = "") -> Dictionary:
	## v1.7: a fortress fires a longer line, so the sheet must quote the fort's odds, not
	## open-ground odds. Passing the land is how the card tells the truth about it.
	var bonus: int = MapLib.defender_bonus(world, map, to_id) if to_id != "" else 0
	var p: float = 1.0 if def <= 0 else Combat.capture_rate(att, def, map.battle, bonus)
	var word := "certain"
	if def > 0:
		word = Combat.odds_word(att, def, map.battle, bonus)
	return {"p": p, "word": word, "fort": bonus > 0}


func odds_into(to_id: String, def: int) -> Dictionary:
	## v2.3: the planner's whole attack on one land, priced as it will be fought. Under rules 21 each
	## land it comes from is a front of its own, facing the defenders' whole line
	## (Combat.fronts_capture_rate); before that, one force of their sum. Adds "total" and "fronts".
	var by_from := {}
	var tot := 0
	for raw in sheet().packets:
		var pk: Types.Packet = raw
		if pk.to_id == to_id:
			by_from[pk.from_id] = int(by_from.get(pk.from_id, 0)) + pk.strength
			tot += pk.strength
	var o: Dictionary = odds(tot, def, to_id)
	o["total"] = tot
	o["fronts"] = by_from.size()
	if map.rules >= 21 and by_from.size() > 1 and def > 0:
		var p: float = Combat.fronts_capture_rate(by_from.values(), def, map.battle, MapLib.defender_bonus(world, map, to_id))
		o["p"] = p
		o["word"] = Combat.word_for(p)
	return o


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
	var unplaced: int = placeable_left() ## v2.3: recruits with no room anywhere aren't a warning (RV-006)
	if unplaced > 0:
		if phase == Phase.OPENING:
			out.append("%d starting arm%s not placed yet — anything unplaced is lost." % [unplaced, "y" if unplaced == 1 else "ies"])
		else:
			out.append("%d reinforcement%s not placed yet — unplaced armies are lost." % [unplaced, "" if unplaced == 1 else "s"])
	if phase == Phase.PLANNING:
		var w: Types.World = projected_world()
		var hinges: Dictionary = BoardFacts.hinges(w, map, planner) ## v1.13: lands that hold the road home
		var warned := {}
		for raw in sheet().packets:
			var p: Types.Packet = raw
			if warned.has(p.from_id):
				continue
			var ts: Types.TerritoryState = w.get_territory(p.from_id)
			var left: int = ts.held()
			## v2.4 (the owner: only "another adjacent region that you could be attacked by outside of
			## the one you're invading"): a land this one marches on must beat its column on the border
			## before it could walk in, so only the enemy neighbours it leaves alone count. A land that
			## sends columns at two neighbours fears neither of them.
			var struck := {}
			for raw2 in sheet().packets:
				if (raw2 as Types.Packet).from_id == p.from_id:
					struck[(raw2 as Types.Packet).to_id] = true
			var danger := false
			for n in map.get_territory(p.from_id).adjacent:
				var o: String = world.get_territory(n).owner
				if o != planner and o != Types.UNOCCUPIED and o != Income.NEUTRAL_ID and not struck.has(n):
					danger = true
			if left <= 1 and danger:
				var road := ""
				if hinges.has(p.from_id):
					var cut: Array = hinges[p.from_id]
					road = " It holds the road home for %s: lose it and %s cut off." % [", ".join(cut.map(func(x): return hex_name(str(x)))), "that land is" if cut.size() == 1 else "they are"]
				out.append("%s will be left with %d — a neighbor could walk right in.%s" % [hex_name(p.from_id), left, road])
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
		"maneuvers": maneuvers_log,
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
	map.maneuvers = bool(config.get("maneuvers", false)) ## saves from before v1.3 had no regroup phase
	map.wild_cards = bool(config.get("wild_cards", true))
	map.scramble = bool(config.get("scramble", false)) ## saves from before v1.4 fought spoils as a ladder of duels
	map.dig_cap = int(config.get("dig_cap", 0)) ## ...and dug in up to 1 + neighbours
	map.rules = int(config.get("rules", 0))
	map.first_digs_in = bool(config.get("first_digs_in", false))
	map.fire_line = bool(config.get("firing_line", false)) ## saves from before v1.6: every man counts
	map.capitals = bool(config.get("capitals", false)) ## saves from before v1.8 had no capitals
	map.fortune = bool(config.get("fortune", false)) ## ...and no Fortune
	_apply_rules(false)
	Combat.use_rules(map)
	seats = config["seats"]
	stats = {}
	for s in seats:
		stats[s["id"]] = _blank_stats()
	setup_dict = d["setup"]
	world = Types.World.from_dict(setup_dict)
	rounds_log = []
	maneuvers_log = []
	move_ghosts = []
	hashes = []
	history = []
	cash_log = []
	capital_log = []
	winner = ""
	watching = false
	_snapshot_history(0)
	var saved_moves: Array = d.get("maneuvers", [])
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
		var k: int = rounds_log.size() - 1
		if k < saved_moves.size() and typeof(saved_moves[k]) == TYPE_DICTIONARY and not (saved_moves[k] as Dictionary).is_empty():
			Maneuver.apply(world, map, saved_moves[k])
			maneuvers_log.append(saved_moves[k])
		else:
			maneuvers_log.append({})
	var saved_hashes: Array = d.get("hashes", [])
	if saved_hashes.size() == hashes.size() and not saved_hashes.is_empty() and str(saved_hashes[-1]) != str(hashes[-1]):
		push_warning("save replay hash differs from recorded hash")
	events = []
	if winner != "":
		phase = Phase.GAME_OVER
		_emit_phase()
		return true
	## saved between the battles and the marches: pick up in the regroup phase
	if map.maneuvers and not rounds_log.is_empty() and (maneuvers_log[-1] as Dictionary).is_empty():
		_start_window(Phase.MANEUVER)
	else:
		_start_window(Phase.PLANNING)
	return true


# ================================================================ timer

func _process(delta: float) -> void:
	if time_left <= 0.0:
		return
	if phase != Phase.PLANNING and phase != Phase.OPENING and phase != Phase.MANEUVER:
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
