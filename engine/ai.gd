## Heuristic commander. Plans one sealed sheet from the public map.
## Sees exactly what a human sees: counts, garrisons, caps, incomes, card counts.
## Never peeks at other sheets. Seeded RNG only. No Node. No UI.
##
## The plan, in order:
##   1. cash a set if it holds one
##   2. regroup one interior stack toward the front (not round 1)
##   3. greedily pick attacks by expected value: region swings, cards, kills,
##      minus expected losses and the risk of being walked in an emptied origin
##   4. surge breakthroughs that will have men to spare
##   5. place the rest where the threat is, then where it can stage
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Combat := preload("res://engine/combat.gd")
const Cards := preload("res://engine/cards.gd")
const Setup := preload("res://engine/setup.gd")

## Personality knobs.
##   p_win      capture chance it wants before committing
##   attacks    max primary attacks per round
##   caution    how much it fears being walked (0 = never, 1 = paranoid)
##   noise      random jitter on target values (sloppiness)
##   surge      will it name surge targets
##   region     weight on completing / breaking regions
##   hunt       extra appetite for the score leader
##   read       how well it predicts enemy reinforcements (0..1)
const PROFILES := {
	"recruit": {"p_win": 0.55, "attacks": 2, "caution": 0.12, "noise": 0.45, "surge": false, "region": 0.6, "hunt": 0.0, "read": 0.0, "stance": "hold"},
	"veteran": {"p_win": 0.68, "attacks": 4, "caution": 0.3, "noise": 0.2, "surge": true, "region": 1.0, "hunt": 0.15, "read": 0.6, "stance": "judgment"},
	"general": {"p_win": 0.68, "attacks": 8, "caution": 0.3, "noise": 0.06, "surge": true, "region": 1.25, "hunt": 0.3, "read": 1.0, "search": true, "stance": "judgment"},
}

## Named commanders: a base level plus a lean.
const COMMANDERS := {
	"varek": {"name": "Grand Marshal Varek", "level": "general", "lean": {}, "blurb": "Old, patient, never wastes a man. Falls back when it's hopeless."},
	"ysolde": {"name": "Viceroy Ysolde", "level": "general", "lean": {"caution": 0.6, "p_win": 0.78, "stance": "bold"}, "blurb": "Holds what she takes. Throws in every reserve."},
	"imre": {"name": "Admiral Imre", "level": "general", "lean": {"region": 1.6, "hunt": 0.5}, "blurb": "Goes for bonuses and the leader's throat."},
	"hask": {"name": "Commodore Hask", "level": "veteran", "lean": {"p_win": 0.6, "attacks": 6, "caution": 0.15, "stance": "bold"}, "blurb": "Attacks everything. Never retreats. Leaves the door open."},
	"quill": {"name": "Governor Quill", "level": "veteran", "lean": {"region": 1.5, "attacks": 3, "stance": "careful"}, "blurb": "Counts coin. Cuts his losses the moment a battle turns."},
	"oren": {"name": "Captain Oren", "level": "recruit", "lean": {"p_win": 0.5, "attacks": 3}, "blurb": "Young, brave, and never knows when to quit."},
}

const ARMY_COST := 0.11


static func profile_for(spec: String) -> Dictionary:
	## "general", "hask", or "veteran|p_win=0.6|caution=0.2" for arena tuning.
	var parts: PackedStringArray = spec.split("|")
	var commander_or_level: String = parts[0]
	var c: Dictionary = COMMANDERS.get(commander_or_level, {})
	var level: String = str(c.get("level", commander_or_level))
	var p: Dictionary = PROFILES.get(level, PROFILES["veteran"]).duplicate()
	var lean: Dictionary = c.get("lean", {})
	for k in lean.keys():
		p[k] = lean[k]
	for i in range(1, parts.size()):
		var kv: PackedStringArray = parts[i].split("=")
		if kv.size() == 2:
			if kv[1].is_valid_float():
				p[kv[0]] = float(kv[1])
			elif kv[1] == "true" or kv[1] == "false":
				p[kv[0]] = kv[1] == "true"
			else:
				p[kv[0]] = kv[1]
	return p


# ---------------------------------------------------------------- opening

static func opening_placements(world: Types.World, map: Types.MapDef, pid: String, rng: RefCounted, prof: Dictionary) -> Dictionary:
	var pool: int = Setup.remaining_pool(world, pid, Setup._human_count(world), map)
	var owned: Array = Array(MapLib.player_territory_ids(world, pid))
	var place := {}
	if owned.is_empty() or pool <= 0:
		return place
	var weight := {}
	for t in owned:
		var w := 0.2
		var enemies := 0
		for n in MapLib.neighbors(map, t):
			var ns: Types.TerritoryState = world.get_territory(n)
			if ns.owner != pid:
				enemies += 1
		if enemies > 0:
			w += 1.0
		w += 1.5 * _region_share(world, map, pid, t) * float(prof.get("region", 1.0))
		w += 0.25 * MapLib.friendly_neighbor_count(world, map, t)
		w *= 1.0 + float(prof.get("noise", 0.1)) * (float(rng.roll_int(0, 100)) / 100.0 - 0.5)
		weight[t] = w
	owned.sort_custom(func(a, b): return float(weight[a]) > float(weight[b]))
	## Pour into the best hexes first, a few at a time, respecting the opening ceiling.
	var guard := 0
	while pool > 0 and guard < 200:
		guard += 1
		var placed_any := false
		for t in owned:
			if pool <= 0:
				break
			var room: int = Setup.opening_cap(world, map, t) - int(place.get(t, 0))
			if room <= 0:
				continue
			var chunk: int = mini(room, mini(pool, maxi(1, int(round(float(weight[t]))))))
			place[t] = int(place.get(t, 0)) + chunk
			pool -= chunk
			placed_any = true
		if not placed_any:
			break
	return place


# ---------------------------------------------------------------- sheet

static func plan(world: Types.World, map: Types.MapDef, pid: String, rng: RefCounted, prof: Dictionary) -> Types.Sheet:
	Combat.use_rules(map) ## the odds it plans by are the ones the battles are fought by
	if Combat.line > 0 and (map.rules < 17 or bool(prof.get("search", false))):
		## Under the firing line every attack is a longer shot, and the hard commanders
		## accept a little less certainty rather than sit still. v1.6 gave every commander
		## this nerve, but v1.6's queue was quietly handing the defender every even volley
		## (Amendment 18), so the whole table was compensating for dice that lied. With
		## honest dice only the hard commanders keep it: the arena then lands where v1.6
		## actually played (Known World: 10 wars in 60 won before the last round against
		## 11, the hard commander 47% against 47%), with odds that now tell the truth.
		prof = prof.duplicate()
		prof["p_win"] = float(prof.get("p_win", 0.68)) - 0.07
	var s: Types.Sheet
	if bool(prof.get("search", false)):
		s = _search(world, map, pid, rng, prof)
	else:
		s = _heuristic(world, map, pid, rng, prof)
	return stamp(s, prof)


static func stamp(sheet: Types.Sheet, prof: Dictionary) -> Types.Sheet:
	## Standing battle orders: every attack carries the commander's temperament.
	var st: String = str(prof.get("stance", "judgment"))
	for raw in sheet.packets:
		(raw as Types.Packet).stance = st
	return sheet


## Variants a searching commander drafts before choosing.
const DRAFTS := [
	{},
	{"caution": 0.0, "p_win": 0.58, "attacks": 10},
	{"caution": 0.15, "p_win": 0.62},
	{"caution": 0.55, "p_win": 0.8},
	{"caution": 0.8, "p_win": 0.9, "attacks": 2},
	{"surge": false, "caution": 0.3},
	{"region": 2.2, "p_win": 0.65},
	{"attacks": 0},
]
const SCENARIOS := 3
const DICE := 2


static func _search(world: Types.World, map: Types.MapDef, pid: String, rng: RefCounted, prof: Dictionary) -> Types.Sheet:
	## Draft several sheets, play each against predicted enemy sheets with made-up
	## dice (never the match seed), keep the one whose futures look best.
	var Resolve := load("res://engine/resolve.gd")
	var base: Dictionary = prof.duplicate()
	base["search"] = false
	var drafts: Array = []
	var seen := {}
	for i in DRAFTS.size():
		var p: Dictionary = base.duplicate()
		var lean: Dictionary = DRAFTS[i]
		for k in lean.keys():
			p[k] = lean[k]
		var sheet: Types.Sheet = stamp(_heuristic(world, map, pid, rng, p), prof)
		var key: String = JSON.stringify(sheet.to_dict())
		if seen.has(key):
			continue
		seen[key] = true
		drafts.append(sheet)
	if drafts.size() == 1:
		return drafts[0]
	var foes: Array = []
	for other in MapLib.living_player_ids(world):
		if other != pid:
			foes.append(other)
	var scenarios: Array = []
	for k in SCENARIOS:
		var guess: Array = []
		for o in foes:
			var style: String = ["veteran", "hask", "ysolde"][k % 3]
			guess.append(stamp(_heuristic(world, map, o, rng, profile_for(style)), profile_for(style)))
		scenarios.append(guess)
	var best: Types.Sheet = drafts[0]
	var best_v := -1.0e9
	for sheet in drafts:
		var total := 0.0
		for k in scenarios.size():
			var sheets: Array = [sheet]
			sheets.append_array(scenarios[k])
			for d in DICE:
				var fake_seed: int = rng.roll_int(1, 2147483646)
				var res: Dictionary = Resolve.resolve_round(world, map, sheets, fake_seed)
				if not res["errors"].is_empty():
					total -= 1000.0
					continue
				total += _position_value(res["world"], map, pid)
		if total > best_v:
			best_v = total
			best = sheet
	return best


static func _position_value(w: Types.World, map: Types.MapDef, pid: String) -> float:
	var ps: Types.PlayerState = w.players.get(pid, null)
	if ps == null or not ps.alive:
		return -200.0
	var left: int = Setup.rounds_for(map) - w.round + 1 ## rounds still to play
	var my: float = float(Income.score_of(w, map, pid))
	var best_other := 0.0
	var other_income := 0.0
	for o in MapLib.living_player_ids(w):
		if o == pid:
			continue
		best_other = maxf(best_other, float(Income.score_of(w, map, o)))
		other_income = maxf(other_income, float(Income.income_of(w, map, o)))
	var mine := MapLib.player_territory_ids(w, pid)
	if mine.size() >= Setup.early_end_threshold(map):
		return 500.0
	if left <= 0:
		return (my - best_other) * 10.0 + (40.0 if my > best_other else 0.0)
	var armies := 0.0
	for t in mine:
		armies += float(w.get_territory(t).held())
	var horizon: float = float(mini(left, 3))
	var v: float = my + horizon * 0.35 * float(Income.income_of(w, map, pid)) + 0.1 * armies
	v -= 0.55 * best_other + horizon * 0.15 * other_income
	return v


static func _heuristic(world: Types.World, map: Types.MapDef, pid: String, rng: RefCounted, prof: Dictionary) -> Types.Sheet:
	var sheet := Types.Sheet.new()
	sheet.player_id = pid
	var ps: Types.PlayerState = world.players.get(pid, null)
	if ps == null or not ps.alive or pid == Income.NEUTRAL_ID:
		return sheet

	if map.cards:
		var owned := {}
		for t in MapLib.player_territory_ids(world, pid):
			owned[t] = true
		var set: PackedStringArray = Cards.best_set(ps.cards, owned)
		if set.size() == 3:
			sheet.cash_set = set

	var p := Planner.new()
	p.setup(world, map, pid, rng, _endgame(world, map, prof))
	if world.round > 1 and not map.maneuvers: ## v1.3: troops move in the regroup phase instead
		sheet.regroup = p.choose_regroup()
		if sheet.regroup != null:
			Validate._apply_regroup_to(p.w, sheet)
	p.begin(Income.income_of(p.w, map, pid) + Validate.cash_value_of(world, map, sheet))
	p.choose_attacks()
	p.choose_surges()
	p.place_defense()
	p.place_leftover()
	sheet.placements = p.place
	sheet.packets = p.packets()
	return _legalize(world, map, sheet)


static func _endgame(world: Types.World, map: Types.MapDef, prof: Dictionary) -> Dictionary:
	## Score is counted at the end of the last round. Men left standing then are worth
	## nothing, so a commander who can count goes all in. Recruits cannot count.
	if float(prof.get("read", 0.0)) <= 0.0:
		return prof
	var left: int = Setup.rounds_for(map) - world.round
	var p: Dictionary = prof.duplicate()
	if left <= 0:
		p["caution"] = 0.0
		p["p_win"] = minf(float(p.get("p_win", 0.7)), 0.45)
		p["attacks"] = 12
		p["army_cost"] = 0.01
	elif left == 1:
		p["caution"] = float(p.get("caution", 0.3)) * 0.6
	return p


## Tuning instrument: sheets the planner drew up that broke a rule and had to be cut back
## (surges struck, attacks dropped). Should stay at zero; the tests hold it there.
static var repairs := 0
static var repair_log: Array = []


static func _legalize(world: Types.World, map: Types.MapDef, sheet: Types.Sheet) -> Types.Sheet:
	var errs: PackedStringArray = Validate.validate_sheet(world, map, sheet)
	if errs.is_empty():
		return sheet
	repairs += 1
	if repair_log.size() < 20:
		repair_log.append("%s r%s %s: %s" % [map.id, world.round, sheet.player_id, " ".join(errs)])
	for raw in sheet.packets:
		(raw as Types.Packet).surge_to = ""
	while not sheet.packets.is_empty() and not Validate.validate_sheet(world, map, sheet).is_empty():
		sheet.packets.pop_back()
	if not Validate.validate_sheet(world, map, sheet).is_empty():
		sheet.regroup = null
	if not Validate.validate_sheet(world, map, sheet).is_empty():
		sheet.cash_set = PackedStringArray()
	if not Validate.validate_sheet(world, map, sheet).is_empty():
		var hold := Types.Sheet.new()
		hold.player_id = sheet.player_id
		return hold
	return sheet


static func _region_share(world: Types.World, map: Types.MapDef, pid: String, terr_id: String) -> float:
	var t: Types.TerritoryDef = map.get_territory(terr_id)
	if t == null or t.region == "":
		return 0.0
	var members := MapLib.region_members(map, t.region)
	var mine := 0
	for m in members:
		if world.get_territory(m).owner == pid:
			mine += 1
	return float(mine) / float(maxi(1, members.size()))


class Planner extends RefCounted:
	const Types := preload("res://engine/types.gd")
	const MapLib := preload("res://engine/map.gd")
	const Income := preload("res://engine/income.gd")
	const Combat := preload("res://engine/combat.gd")
	const ARMY_COST := 0.11

	var w: Types.World
	var map: Types.MapDef
	var pid: String
	var rng: RefCounted
	var prof: Dictionary
	var place := {} ## terr -> armies
	var income_left := 0
	var cap := {} ## terr -> cap after regroup
	var sent := {} ## origin -> armies committed
	var attacks: Array = [] ## [{to, froms: {origin: n}, strength, def, surge}]
	var targeted := {}
	var threat_cache := {}
	var incomes := {}
	var leader := ""

	func setup(p_world: Types.World, p_map: Types.MapDef, p_pid: String, p_rng: RefCounted, p_prof: Dictionary) -> void:
		w = p_world.clone()
		map = p_map
		pid = p_pid
		rng = p_rng
		prof = p_prof
		var best := -1
		for other in MapLib.living_player_ids(w):
			incomes[other] = Income.income_of(w, map, other)
			var sc: int = Income.score_of(w, map, other)
			if other != pid and sc > best:
				best = sc
				leader = other
		if Income.score_of(w, map, pid) >= best:
			leader = "" ## we are leading; nobody to hunt

	func begin(income: int) -> void:
		income_left = income
		for t in mine():
			cap[t] = Income.cap_of(w, map, t)
		threat_cache.clear()

	func mine() -> PackedStringArray:
		return MapLib.player_territory_ids(w, pid)

	func owner_of(t: String) -> String:
		return w.get_territory(t).owner

	func is_foe(o: String) -> bool:
		return o != pid and o != Types.UNOCCUPIED and o != Income.NEUTRAL_ID

	# ---- strength bookkeeping

	func room(t: String) -> int:
		return maxi(0, int(cap.get(t, 0)) - int(place.get(t, 0)))

	func avail(t: String) -> int:
		## Armies that could march from t right now (after queued placements).
		var ts: Types.TerritoryState = w.get_territory(t)
		var mobile: int = ts.armies + int(place.get(t, 0)) - int(sent.get(t, 0))
		var keep: int = 0 if ts.garrison >= 1 else 1
		return maxi(0, mobile - keep)

	func remaining_defense(t: String) -> int:
		var ts: Types.TerritoryState = w.get_territory(t)
		return maxi(0, ts.armies + int(place.get(t, 0)) - int(sent.get(t, 0))) + ts.garrison

	func enemy_add(e: String) -> int:
		## Expected hidden reinforcement on an enemy hex.
		var o: String = owner_of(e)
		if not is_foe(o):
			return 0
		var c: int = Income.cap_of(w, map, e)
		var their_income: int = int(incomes.get(o, 3))
		var total_cap := 0
		for t in MapLib.player_territory_ids(w, o):
			if _frontier(t, o):
				total_cap += Income.cap_of(w, map, t)
		var share: float = float(c) / float(maxi(1, total_cap))
		var guess: float = minf(float(c), float(their_income) * share * 1.6)
		return int(ceil(guess * float(prof.get("read", 0.5))))

	func _frontier(t: String, o: String) -> bool:
		for n in MapLib.neighbors(map, t):
			if owner_of(n) != o:
				return true
		return false

	func threat(t: String) -> float:
		## Strongest single-owner punch that could land on t next resolve.
		if threat_cache.has(t):
			return threat_cache[t]
		var by_owner := {}
		for n in MapLib.neighbors(map, t):
			var o: String = owner_of(n)
			if not is_foe(o):
				continue
			var ns: Types.TerritoryState = w.get_territory(n)
			var send: int = Income.max_send(ns)
			var extra: int = mini(Income.cap_of(w, map, n), int(incomes.get(o, 3)))
			var punch: int = send + extra
			if MapLib.column_cap(map, t) > 0:
				punch = mini(punch, MapLib.column_cap(map, t)) ## v1.7: our pass lets in six a road
			by_owner[o] = float(by_owner.get(o, 0.0)) + float(punch)
		var best := 0.0
		for o in by_owner.keys():
			best = maxf(best, float(by_owner[o]))
		threat_cache[t] = best * 0.75
		return threat_cache[t]

	func hex_value(t: String) -> float:
		## What owning t is worth to us (for defending it).
		var v := 1.0
		var td: Types.TerritoryDef = map.get_territory(t)
		if td != null and td.region != "" and MapLib.holds_region(w, map, pid, td.region):
			v += float(map.region_bonus.get(td.region, 0)) * float(prof.get("region", 1.0))
		return v

	func loss_risk(t: String, defense: int) -> float:
		var th: float = threat(t)
		if th < 1.0:
			return 0.0
		var d: int = maxi(0, defense)
		var p_hit: float = 1.0 if d == 0 else Combat.capture_rate(int(round(th)), d, map.battle, MapLib.defender_line_bonus(map, t))
		var tempt: float = clampf(th / float(d + 1), 0.3, 1.6)
		return float(prof.get("caution", 0.3)) * tempt * p_hit

	# ---- regroup

	func choose_regroup() -> Types.Regroup:
		var dist := _front_distance()
		var best: Types.Regroup = null
		var best_score := 0.0
		for t in mine():
			var ts: Types.TerritoryState = w.get_territory(t)
			var n_send: int = Income.max_send(ts)
			if n_send < 2 or int(dist.get(t, 99)) == 0:
				continue
			for n in MapLib.neighbors(map, t):
				if owner_of(n) != pid:
					continue
				if int(dist.get(n, 99)) >= int(dist.get(t, 99)):
					continue
				var score: float = float(n_send) * (1.0 + threat(n) * 0.05)
				if score > best_score:
					best_score = score
					best = Types.Regroup.new()
					best.from_id = t
					best.to_id = n
					best.strength = n_send
		if best == null:
			## Nothing interior: shore up the most threatened hex from a quieter neighbor.
			var worst := ""
			var worst_gap := 1.0
			for t in mine():
				var gap: float = threat(t) - float(remaining_defense(t))
				if gap > worst_gap:
					worst_gap = gap
					worst = t
			if worst != "":
				for n in MapLib.neighbors(map, worst):
					if owner_of(n) != pid:
						continue
					var ns: Types.TerritoryState = w.get_territory(n)
					var spare: int = int(float(Income.max_send(ns)) - threat(n) * 0.8)
					if spare >= 2:
						best = Types.Regroup.new()
						best.from_id = n
						best.to_id = worst
						best.strength = spare
						break
		return best

	func _front_distance() -> Dictionary:
		var dist := {}
		var q: Array = []
		for t in mine():
			for n in MapLib.neighbors(map, t):
				if owner_of(n) != pid:
					dist[t] = 0
					q.append(t)
					break
		while not q.is_empty():
			var c: String = q.pop_front()
			for n in MapLib.neighbors(map, c):
				if owner_of(n) == pid and not dist.has(n):
					dist[n] = int(dist[c]) + 1
					q.append(n)
		return dist

	# ---- attacks

	func target_value(e: String, with_targets: Dictionary) -> float:
		var es: Types.TerritoryState = w.get_territory(e)
		var o: String = es.owner
		var v := 1.0
		var td: Types.TerritoryDef = map.get_territory(e)
		var rw: float = float(prof.get("region", 1.0))
		if td != null and td.region != "" and map.region_bonus.has(td.region):
			var bonus: float = float(map.region_bonus[td.region])
			var members := MapLib.region_members(map, td.region)
			var have := 0
			for m in members:
				if owner_of(m) == pid or with_targets.has(m):
					have += 1
			if have + 1 == members.size():
				v += bonus * 1.6 * rw
			else:
				v += bonus * float(have + 1) / float(members.size()) * 0.45 * rw
			if is_foe(o) and MapLib.holds_region(w, map, o, td.region):
				v += bonus * 1.2 * rw
		if is_foe(o):
			var left: int = MapLib.player_territory_ids(w, o).size()
			if left <= 2:
				v += 2.5 + 0.5 * float(w.players[o].cards.size())
			if o == leader:
				v *= 1.0 + float(prof.get("hunt", 0.0))
		if map.cards and attacks.is_empty():
			v += 0.7 ## the first capture of the round draws a card
		if map.supply:
			## how well a commander reads the roads is how well it reads the board: the
			## recruit never sees them, the general sees every one
			v += _supply_swing(e, o) * float(prof.get("read", 0.5))
		var jitter: float = float(prof.get("noise", 0.1)) * (float(rng.roll_int(0, 1000)) / 1000.0 - 0.5) * 2.0
		return v * (1.0 + jitter)

	func _supply_swing(e: String, o: String) -> float:
		## v1.7 supply maps: what taking e does to the roads home. A conquest that joins
		## stranded lands back to the main body is worth every land it feeds again; one that
		## would itself be stranded is worth less (it pays nothing and takes no recruits);
		## and one that cuts a rival's chain starves every land beyond the cut.
		var before_mine: int = MapLib.supplied_ids(w, map, pid).size()
		var before_theirs: int = MapLib.supplied_ids(w, map, o).size() if is_foe(o) else 0
		var ts: Types.TerritoryState = w.get_territory(e)
		var was: String = ts.owner
		ts.owner = pid
		var after: Dictionary = MapLib.supplied_ids(w, map, pid)
		var after_theirs: int = MapLib.supplied_ids(w, map, o).size() if is_foe(o) else 0
		ts.owner = was
		var v := 0.0
		if not after.has(e):
			v -= 0.6
		v += 0.5 * float(maxi(0, after.size() - (1 if after.has(e) else 0) - before_mine))
		if is_foe(o):
			v += 0.4 * float(maxi(0, before_theirs - after_theirs - 1))
		return v

	func choose_attacks() -> void:
		var max_attacks: int = int(prof.get("attacks", 4))
		var guard := 0
		while attacks.size() < max_attacks and guard < 40:
			guard += 1
			var best: Dictionary = {}
			var best_ev := 0.15
			for e in _targets():
				var cand: Dictionary = _evaluate(e)
				if cand.is_empty():
					continue
				if float(cand["ev"]) > best_ev:
					best_ev = float(cand["ev"])
					best = cand
			if best.is_empty():
				return
			_commit(best)

	func _targets() -> Array:
		var out := {}
		for t in mine():
			for n in MapLib.neighbors(map, t):
				if owner_of(n) != pid and not targeted.has(n):
					out[n] = true
		var keys: Array = out.keys()
		keys.sort()
		return keys

	func _evaluate(e: String) -> Dictionary:
		var es: Types.TerritoryState = w.get_territory(e)
		var d_now: int = es.held()
		var d_eff: int = d_now + enemy_add(e)
		var p_want: float = float(prof.get("p_win", 0.7))
		## Sources and what they can offer: spare men first, then fresh placements, then reserves.
		var srcs: Array = []
		for s in MapLib.neighbors(map, e):
			if owner_of(s) == pid:
				srcs.append(s)
		if srcs.is_empty():
			return {}
		var offers: Array = [] ## [origin, amount, kind] kind 0 spare, 1 place, 2 reserve
		var place_budget: int = income_left
		for s in srcs:
			var a: int = avail(s)
			var reserve: int = int(ceil(threat(s) * float(prof.get("caution", 0.3)) * 1.2))
			var spare: int = maxi(0, a - reserve)
			if spare > 0:
				offers.append([s, spare, 0])
			if a - spare > 0:
				offers.append([s, a - spare, 2])
			var r: int = mini(room(s), place_budget)
			if r > 0:
				offers.append([s, r, 1])
		offers.sort_custom(func(x, y):
			if int(x[2]) != int(y[2]):
				return int(x[2]) < int(y[2])
			return int(x[1]) > int(y[1]))
		var fort: int = MapLib.defender_line_bonus(map, e)
		var need := 1
		if d_eff > 0:
			need = _needed(d_eff, p_want, fort)
		elif es.owner == Types.UNOCCUPIED:
			need = 2 ## someone else may walk in too
		## v1.7: a pass takes no more than its column from any one land
		var col: int = MapLib.column_cap(map, e)
		var total := 0
		var per := {}
		for o in offers:
			var k: int = int(o[1])
			if col > 0:
				k = clampi(col - int(per.get(o[0], 0)), 0, k)
			per[o[0]] = int(per.get(o[0], 0)) + k
			total += k
		if total < need:
			return {}
		## Take the extra punch while it is cheap spare men.
		var spare_total := 0
		for o in offers:
			if int(o[2]) == 0:
				spare_total += int(o[1])
		var want: int = maxi(need, mini(spare_total, need + 3))
		var froms := {}
		var places := {}
		var got := 0
		var used_place := 0
		for o in offers:
			if got >= want:
				break
			var take: int = mini(int(o[1]), want - got)
			if col > 0:
				take = mini(take, col - int(froms.get(o[0], 0)))
			if take <= 0:
				continue
			if int(o[2]) == 1:
				take = mini(take, income_left - used_place)
				if take <= 0:
					continue
				places[o[0]] = int(places.get(o[0], 0)) + take
				used_place += take
			froms[o[0]] = int(froms.get(o[0], 0)) + take
			got += take
		if got < need:
			return {}
		var p_win: float = 1.0 if d_eff == 0 else Combat.capture_rate(got, d_eff, map.battle, fort)
		var value: float = target_value(e, targeted)
		var loss_win: float = float(d_eff / 2)
		var exp_loss: float = p_win * loss_win + (1.0 - p_win) * float(got)
		var exposure := 0.0
		for s in froms.keys():
			var before: int = remaining_defense(s) + int(places.get(s, 0))
			var after: int = before - int(froms[s])
			exposure += (loss_risk(s, after) - loss_risk(s, before)) * hex_value(s)
		var ev: float = value * p_win - exp_loss * float(prof.get("army_cost", ARMY_COST)) - exposure - float(used_place) * 0.04
		return {"to": e, "froms": froms, "places": places, "strength": got, "def": d_eff, "p": p_win, "ev": ev, "surge": ""}

	func _needed(d: int, p_want: float, d_bonus: int = 0) -> int:
		var top: int = d + maxi(12, d / 2) ## under the v1.6 firing line a big stack needs a real margin
		for a in range(1, top):
			if Combat.capture_rate(a, d, map.battle, d_bonus) >= p_want:
				return a
		return top

	func _commit(c: Dictionary) -> void:
		for s in c["places"].keys():
			place[s] = int(place.get(s, 0)) + int(c["places"][s])
			income_left -= int(c["places"][s])
		for s in c["froms"].keys():
			sent[s] = int(sent.get(s, 0)) + int(c["froms"][s])
		targeted[c["to"]] = true
		attacks.append(c)

	func choose_surges() -> void:
		if not bool(prof.get("surge", false)):
			return
		for a in attacks:
			var left: int = int(a["strength"]) - int(a["def"]) / 2
			if float(a["p"]) < 0.8 or left < 4:
				continue
			var e: String = a["to"]
			var from_set: Dictionary = a["froms"]
			var best := ""
			var best_score := 0.0
			for n in MapLib.neighbors(map, e):
				if owner_of(n) == pid or targeted.has(n) or from_set.has(n):
					continue
				var d: int = w.get_territory(n).held() + enemy_add(n)
				var push: int = left - 1
				if MapLib.column_cap(map, n) > 0:
					push = mini(push, MapLib.column_cap(map, n)) ## a surge into a pass is a column of six too
				var p: float = 1.0 if d == 0 else Combat.capture_rate(push, d, map.battle, MapLib.defender_line_bonus(map, n))
				if p < 0.62:
					continue
				var score: float = p * target_value(n, targeted)
				if score > best_score:
					best_score = score
					best = n
			if best != "":
				a["surge"] = best

	# ---- placements

	func place_defense() -> void:
		var guard := 0
		while income_left > 0 and guard < 400:
			guard += 1
			var best := ""
			var best_gain := 0.02
			for t in mine():
				if room(t) <= 0:
					continue
				var d: int = remaining_defense(t)
				var gain: float = (loss_risk(t, d) - loss_risk(t, d + 1)) * hex_value(t)
				if gain > best_gain:
					best_gain = gain
					best = t
			if best == "":
				return
			place[best] = int(place.get(best, 0)) + 1
			income_left -= 1

	func place_leftover() -> void:
		## Stage on the front: the hex next to the fattest target we could not afford.
		var guard := 0
		while income_left > 0 and guard < 400:
			guard += 1
			var best := ""
			var best_score := -1.0
			for t in mine():
				if room(t) <= 0:
					continue
				var score := 0.0
				for n in MapLib.neighbors(map, t):
					var o: String = owner_of(n)
					if o == pid:
						continue
					score += 1.0 + (0.5 if is_foe(o) else 0.2)
				score += threat(t) * 0.1 + float(rng.roll_int(0, 10)) * 0.01
				if score > best_score:
					best_score = score
					best = t
			if best == "":
				return ## everything capped; the rest is lost
			place[best] = int(place.get(best, 0)) + 1
			income_left -= 1

	func packets() -> Array:
		var out: Array = []
		for a in attacks:
			var keys: Array = a["froms"].keys()
			keys.sort()
			for s in keys:
				var n: int = int(a["froms"][s])
				if n < 1:
					continue
				var p := Types.Packet.new()
				p.from_id = s
				p.to_id = a["to"]
				p.strength = n
				p.surge_to = str(a["surge"])
				out.append(p)
		return out


# ---------------------------------------------------------------- the land draft (v1.4)

static func draft_pick(world: Types.World, map: Types.MapDef, pid: String, rng: RefCounted, prof: Dictionary, picks_left: Dictionary, upcoming: Array = []) -> String:
	## The hard commanders look one turn ahead: for each of their best few claims, they
	## let the rivals who choose before their next turn take what they would take, then
	## judge the board they are left with. Everyone else claims by the land's own merits.
	if bool(prof.get("search", false)) and not upcoming.is_empty():
		var ranked: Array = _draft_rank(world, map, pid, rng, prof, picks_left)
		var best_l := ""
		var best_s := -INF
		for k in mini(6, ranked.size()):
			var cand: String = str(ranked[k][1])
			var w2: Types.World = world.clone()
			w2.set_hex(cand, pid, 1)
			var left2: Dictionary = picks_left.duplicate()
			left2[pid] = int(left2.get(pid, 1)) - 1
			for rival in upcoming:
				if str(rival) == pid:
					break
				var calm := {"region": 1.0, "noise": 0.0}
				var r_rank: Array = _draft_rank(w2, map, str(rival), rng, calm, left2)
				if r_rank.is_empty():
					break
				w2.set_hex(str(r_rank[0][1]), str(rival), 1)
				left2[str(rival)] = int(left2.get(str(rival), 1)) - 1
			var score: float = _draft_eval(w2, map, pid, left2) + 0.35 * float(ranked[k][0])
			if score > best_s:
				best_s = score
				best_l = cand
		if best_l != "":
			return best_l
	var r: Array = _draft_rank(world, map, pid, rng, prof, picks_left)
	return str(r[0][1]) if not r.is_empty() else ""


static func _draft_eval(world: Types.World, map: Types.MapDef, pid: String, picks_left: Dictionary) -> float:
	## how good a half-drafted board is for pid: regions still ours to finish, a solid
	## block, and few borders with rivals
	var v := 0.0
	var mine_left: int = int(picks_left.get(pid, 0))
	for reg in map.region_bonus.keys():
		var members := MapLib.region_members(map, str(reg))
		var ours := 0
		var open := 0
		var rival := false
		for m in members:
			var o: String = world.get_territory(m).owner
			if o == pid:
				ours += 1
			elif o == Types.UNOCCUPIED:
				open += 1
			elif o != Income.NEUTRAL_ID:
				rival = true
		if ours == 0:
			continue
		var bonus: float = float(map.region_bonus[reg])
		if not rival and members.size() - ours <= mine_left:
			var frac: float = float(ours) / float(members.size())
			v += bonus * 3.0 * frac * frac
		elif rival:
			v -= 0.4 * bonus * float(ours) / float(members.size())
	for t in MapLib.player_territory_ids(world, pid):
		for n in MapLib.neighbors(map, t):
			var o2: String = world.get_territory(n).owner
			if o2 == pid:
				v += 0.35
			elif o2 != Types.UNOCCUPIED and o2 != Income.NEUTRAL_ID:
				v -= 0.3
	return v


static func _draft_rank(world: Types.World, map: Types.MapDef, pid: String, rng: RefCounted, prof: Dictionary, picks_left: Dictionary) -> Array:
	## [[value, land], ...] best first. Weighs, for every land still free:
	##   the region it opens (worth more the more of it we could still own outright, and
	##     nothing much once a rival has a foot in it),
	##   friends next door (a solid block holds and pays the bloc bonus),
	##   rivals next door (a claim ringed by enemies is a claim lost in round one),
	##   denial (the last free land of a region a rival is about to own),
	##   and room to grow. Sloppier commanders add noise.
	## picks_left: pid -> claims each commander still has to make.
	var free: Array = []
	for t in map.territory_ids():
		if world.get_territory(str(t)).owner == Types.UNOCCUPIED:
			free.append(str(t))
	var out: Array = []
	if free.is_empty():
		return out
	free.sort()
	var mine_left: int = int(picks_left.get(pid, 1))
	var region_w: float = float(prof.get("region", 1.0))
	var noise: float = float(prof.get("noise", 0.1))
	for t in free:
		var td: Types.TerritoryDef = map.get_territory(t)
		var v := 0.0
		## the region
		var reg: String = td.region
		if reg != "" and map.region_bonus.has(reg):
			var bonus: float = float(map.region_bonus[reg])
			var size := 0
			var ours := 0
			var theirs := {}
			var open := 0
			for u in map.territory_ids():
				if map.get_territory(str(u)).region != reg:
					continue
				size += 1
				var o: String = world.get_territory(str(u)).owner
				if o == pid:
					ours += 1
				elif o == Types.UNOCCUPIED:
					open += 1
				else:
					theirs[o] = int(theirs.get(o, 0)) + 1
			var per: float = bonus / float(maxi(1, size))
			if theirs.is_empty():
				## still ours to take: the closer to whole, and the cheaper to finish, the better
				var need: int = size - ours
				var reach: float = 1.0 if need <= mine_left else 0.45
				v += region_w * (1.4 * per + 2.2 * bonus * float(ours + 1) / float(size)) * reach
			else:
				v += region_w * 0.25 * per
				## a rival who could close it out with the free lands left: take one to spoil it
				for o in theirs.keys():
					if int(theirs[o]) + open == size and int(theirs[o]) >= maxi(1, size - 3):
						v += region_w * (1.2 + 0.9 * bonus) * float(theirs[o]) / float(size)
		## neighbours
		var friends := 0
		var rivals := 0
		var empty := 0
		for n in MapLib.neighbors(map, t):
			var o2: String = world.get_territory(str(n)).owner
			if o2 == pid:
				friends += 1
			elif o2 == Types.UNOCCUPIED:
				empty += 1
			elif o2 != Income.NEUTRAL_ID:
				rivals += 1
		v += 1.6 * friends - 0.9 * rivals + 0.35 * empty
		var deg: int = MapLib.neighbors(map, t).size()
		v += 0.25 * float(maxi(0, 5 - deg)) ## a land with few borders is easy to hold
		if noise > 0.0:
			v *= 1.0 + noise * (float(rng.roll_int(0, 1000)) / 1000.0 - 0.5) * 2.0
			v += noise * float(rng.roll_int(0, 1000)) / 1000.0
		out.append([v, t])
	out.sort_custom(func(a, b): return float(a[0]) > float(b[0]) or (float(a[0]) == float(b[0]) and str(a[1]) < str(b[1])))
	return out
