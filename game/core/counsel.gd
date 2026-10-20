## The advisor's brain. Reads the public board for the commander at the table and
## says the one or two things worth saying. Also drafts a whole plan on request.
## Sees only what the player sees; never peeks at sealed sheets.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Combat := preload("res://engine/combat.gd")
const Cards := preload("res://engine/cards.gd")
const Ai := preload("res://engine/ai.gd")
const Rng := preload("res://engine/rng.gd")
const Validate := preload("res://engine/validate.gd")
const Session := preload("res://game/core/session.gd")
const BoardFacts := preload("res://game/core/board_facts.gd")

## item: {key, text, mood: neutral|alarmed|pleased, voice: line key or "", focus: [ids], rank}


static func advice(s: Node) -> Array:
	var out: Array = []
	if s.world == null or s.planner == "":
		return out
	var pid: String = s.planner
	var w: Types.World = s.world
	var map: Types.MapDef = s.map
	if s.phase == Session.Phase.OPENING and s.capital_choosable():
		var cap: String = s.capital_shown(pid)
		if s.opening_capital.has(pid):
			out.append(_item("capital", "%s will be our capital: two recruits a round, and it fights like a fortress. Choose 'Make this our capital' on another of our lands to change your mind before you seal." % s.hex_name(cap), "neutral", "", [cap], 45))
		else:
			out.append(_item("capital", "Name our capital, Commander. I have pencilled in %s, deep in our lands. Select any of our lands and choose 'Make this our capital' to move it. It pays two recruits a round and fights like a fortress." % s.hex_name(cap), "neutral", "capital_choose", [cap], 60))
	if s.phase == Session.Phase.PLANNING and s.capital_choosable():
		var cap2: String = s.capital_shown(pid)
		out.append(_item("capital_fell", "Our capital has fallen. The court has fled to %s. Keep it there, or select another of our lands and make it the capital: this round only." % s.hex_name(cap2), "alarmed", "capital_move", [cap2], 92))
	if s.phase == Session.Phase.OPENING:
		out.append(_item("deploy", "Place your starting armies: click one of your lands to add one (right-click takes one back). Put strength where enemies touch you — and on lands that could complete a region.", "neutral", "deploy", [], 50))
		return out
	## 1. unplaced men
	var left: int = s.placeable_left() ## v2.3: only the recruits that have somewhere to go
	if left > 0:
		## v2.3: in the orders step a click only selects; say how to get back to placing
		var how: String = ("Click one of our lands to put %s there" % ("it" if left == 1 else "them")) if s.plan_step == "reinforce" \
			else "Press ◀ Recruits (beside the tally) to go back and place %s" % ("it" if left == 1 else "them")
		out.append(_item("place", ("1 fresh troop waits" if left == 1 else "%d fresh troops wait" % left) + " for orders. " + how + " — unplaced men go home.", "neutral", "reinforce", [], 40))
	## 2. threats
	var proj: Types.World = s.projected_world()
	for t in MapLib.player_territory_ids(w, pid):
		var th: Dictionary = _threat(w, map, pid, t)
		if th.is_empty():
			continue
		var have: int = proj.get_territory(t).held()
		if float(th["max"]) >= float(have) * 1.6 and int(th["max"]) >= have + 3:
			var rank: int = 70 + mini(20, int(th["max"]) - have)
			if _in_held_region(w, map, pid, t):
				rank += 10
			out.append(_item("threat_" + t, "%s could bring up to %d against %s. We will have %d there." % [s.name_of(th["owner"]), th["max"], s.hex_name(t), have], "alarmed", "", [t, th["from"]], rank))
	## 3. vacate warnings from the sheet itself
	for wtxt in s.warnings():
		if wtxt.contains("walk right in"):
			out.append(_item("vacate", wtxt, "alarmed", "vacate_warn", [], 85))
	## 4. region completion
	for r in map.region_bonus.keys():
		var members := MapLib.region_members(map, str(r))
		var missing: Array = []
		for m in members:
			if w.get_territory(m).owner != pid:
				missing.append(m)
		if missing.is_empty() or missing.size() > 2 or missing.size() == members.size():
			continue
		var reachable := true
		for m in missing:
			if not _touches(w, map, pid, m):
				reachable = false
		if reachable:
			var names: Array = []
			for m in missing:
				names.append(s.hex_name(m))
			out.append(_item("region_" + str(r), "Take %s and all of %s is ours: +%d troops every round." % [" and ".join(names), map.region_names.get(r, r), int(map.region_bonus[r])], "pleased", "", missing, 60 + int(map.region_bonus[r]) * 3))
	## 5. soft targets next door
	var best_soft := ""
	var best_soft_n := 999
	for t in MapLib.player_territory_ids(w, pid):
		for n in MapLib.neighbors(map, t):
			var ns: Types.TerritoryState = w.get_territory(n)
			if ns.owner == pid:
				continue
			if ns.held() < best_soft_n and s.max_send(t) >= 2:
				best_soft_n = ns.held()
				best_soft = n
	if best_soft != "" and best_soft_n <= 1:
		var o: String = w.get_territory(best_soft).owner
		var who: String = "Nobody holds" if o == Types.UNOCCUPIED else "%s left only %d in" % [s.name_of(o), best_soft_n]
		out.append(_item("soft_" + best_soft, "%s %s. A small force takes it." % [who, s.hex_name(best_soft)], "pleased", "", [best_soft], 45))
	## 6. cards
	if map.cards and s.sheet().cash_set.is_empty() and s.best_set().size() == 3:
		out.append(_item("cards", "We hold a set of cards. Open the Cards and turn them in for %d more troops this round." % s.set_value_now(), "pleased", "cards", [], 55))
	## 7. the clock
	if s.is_last_round() and not s.conquest():
		out.append(_item("final", "Final round. Only land counts when this resolves — spend every soldier.", "alarmed", "final", [], 90))
	out.sort_custom(func(a, b): return int(a["rank"]) > int(b["rank"]))
	return out


static func _item(key: String, text: String, mood: String, voice: String, focus: Array, rank: int) -> Dictionary:
	return {"key": key, "text": text, "mood": mood, "voice": voice, "focus": focus, "rank": rank}


static func _threat(w: Types.World, map: Types.MapDef, pid: String, t: String) -> Dictionary:
	## The biggest single-owner punch that could land on t (v1.13: in BoardFacts, which the map uses too)
	return BoardFacts.threat_on(w, map, pid, t)


static func _touches(w: Types.World, map: Types.MapDef, pid: String, t: String) -> bool:
	for n in MapLib.neighbors(map, t):
		if w.get_territory(n).owner == pid:
			return true
	return false


static func _in_held_region(w: Types.World, map: Types.MapDef, pid: String, t: String) -> bool:
	var r: String = map.get_territory(t).region
	return r != "" and MapLib.holds_region(w, map, pid, r)


# ---------------------------------------------------------------- the advisor's plan

static func draft(s: Node) -> Types.Sheet:
	## A full sheet from a careful commander's head, for the player to adopt or ignore.
	var rng: RefCounted = Rng.derive_stream(s.match_seed, s.world.round, "advisor|" + s.planner)
	var prof: Dictionary = Ai.profile_for("veteran")
	prof["caution"] = 0.38
	prof["noise"] = 0.0
	return Ai.plan(s.world, s.map, s.planner, rng, prof)


static func explain(s: Node, sheet: Types.Sheet) -> Array:
	## Human sentences for each line of a drafted sheet.
	var lines: Array = []
	if sheet.cash_set.size() > 0:
		lines.append(["coins", "Trade in a card set for %d troops." % s.set_value_now()])
	if not sheet.placements.is_empty():
		var parts: Array = []
		var keys: Array = sheet.placements.keys()
		keys.sort_custom(func(a, b): return int(sheet.placements[a]) > int(sheet.placements[b]))
		for k in keys:
			parts.append("%d on %s" % [int(sheet.placements[k]), s.hex_name(str(k))])
		lines.append(["reinforce", "Recruits: " + ", ".join(parts) + "."])
	if sheet.regroup != null:
		lines.append(["move", "Move %d from %s to %s, toward the front." % [sheet.regroup.strength, s.hex_name(sheet.regroup.from_id), s.hex_name(sheet.regroup.to_id)]])
	var by_target := {}
	for raw in sheet.packets:
		var p: Types.Packet = raw
		if not by_target.has(p.to_id):
			by_target[p.to_id] = {"n": 0, "from": [], "sizes": [], "surge": p.surge_to}
		by_target[p.to_id]["n"] += p.strength
		by_target[p.to_id]["from"].append(s.hex_name(p.from_id))
		by_target[p.to_id]["sizes"].append(p.strength)
	for to in by_target.keys():
		var info: Dictionary = by_target[to]
		var d: int = s.world.get_territory(to).held()
		var bonus: int = MapLib.defender_bonus(s.world, s.map, str(to))
		## v2.3: from two lands it is two fronts (rules 21), and the word says what that is worth
		var word: String = "certain"
		if d > 0:
			if s.map.rules >= 21 and (info["sizes"] as Array).size() > 1:
				word = Combat.word_for(Combat.fronts_capture_rate(info["sizes"], d, s.map.battle, bonus))
			else:
				word = Combat.odds_word(int(info["n"]), maxi(1, d), s.map.battle, bonus)
		var txt := "Attack %s with %d from %s — %s." % [s.hex_name(to), info["n"], " and ".join(info["from"]), word]
		if str(info["surge"]) != "":
			txt += " If it falls, surge on into %s." % s.hex_name(str(info["surge"]))
		lines.append(["attack", txt])
	if sheet.packets.is_empty():
		lines.append(["shield", "Hold this round. Nothing out there is worth the risk."])
	return lines


static func adopt(s: Node, sheet: Types.Sheet) -> void:
	var mine := Types.Sheet.new()
	mine.player_id = s.planner
	mine.placements = sheet.placements.duplicate()
	mine.cash_set = sheet.cash_set.duplicate()
	for raw in sheet.packets:
		var p: Types.Packet = raw
		var q := Types.Packet.new()
		q.from_id = p.from_id
		q.to_id = p.to_id
		q.strength = p.strength
		q.surge_to = p.surge_to
		q.stance = p.stance if p.stance != "" else "judgment" ## the advisor's own doctrine
		mine.packets.append(q)
		if q.surge_to != "":
			mine.surges[q.to_id] = q.surge_to ## v1.3: the surge belongs to the land being taken
	if sheet.regroup != null and s.world.round > 1:
		var r := Types.Regroup.new()
		r.from_id = sheet.regroup.from_id
		r.to_id = sheet.regroup.to_id
		r.strength = sheet.regroup.strength
		mine.regroup = r
	s.drafts[s.planner] = mine
	s.clamp_packets()
	s.changed.emit()


# ---------------------------------------------------------------- tutorial lessons

static func lesson(s: Node, surge_pick: int) -> Dictionary:
	## The scripted Isthmus lessons (tutorial) and the gentle first-game hints.
	var ph: int = s.phase
	if ph != Session.Phase.PLANNING and ph != Session.Phase.OPENING:
		return {}
	if surge_pick >= 0:
		return _item("surgepick", "Pick where the survivors go next: any enemy or empty land touching the target. They only go if the first attack wins, and surges happen after every other battle.", "neutral", "", [], 200)
	var volleys: bool = s.map.battle == Combat.MODE_VOLLEYS
	## v1.14: the tutorial plays the firing line (v1.6): only five men fire, and an even volley is fired again
	var volley_rule := "Battles are fought volley by volley: each side rolls a die, times five, plus the men in its firing line (at most five). The loser of each volley loses a man, until one side is gone. An even volley is fired again." if s.map.fire_line \
		else "Battles are fought volley by volley: each side rolls a die, times five, plus its armies. The loser of each volley loses a man, until one side is gone. Ties go to the attacker."
	var battle_rule := volley_rule if volleys else "Battles are one roll: armies plus one die. Higher total wins, ties go to the attacker, and the winner loses half the loser's size."
	if bool(s.config.get("tutorial", false)):
		var r: int = s.world.round
		if ph == Session.Phase.OPENING:
			## v2.3: the banner says to name the capital; the lesson says what the crown is, and how deployment ends
			if s.placeable_left() <= 0:
				return _item("t-open2", "All placed. Press SEAL on the dial and every commander's armies take the field at once.", "pleased", "", [], 150)
			return _item("t-open", "Welcome, Commander. This is the Isthmus: a north shore and a south shore joined only by The Gate. The crown is our capital (I have pencilled one in): it pays two recruits a round and fights like a fortress. First, place your starting armies — click one of our lands to add one there.", "neutral", "welcome", [], 150)
		if r == 1:
			if s.plan_step == "reinforce":
				if s.placeable_left() > 0:
					return _item("t-r1a", "Every round begins with the reinforcement phase. Click our lands to place the recruits — they can attack this very round. The ≤ badge on an enemy land is the most it could hold after they secretly reinforce.", "neutral", "reinforce", [], 150)
				return _item("t-r1a2", "All placed. Press ORDERS to move on to the orders phase and choose where to strike.", "pleased", "", [], 150)
			if s.sheet().packets.is_empty():
				return _item("t-r1b", "Now attack: with our land selected, click an enemy or empty neighbor, or drag onto it. Every order happens at once — and armies you send LEAVE HOME.", "neutral", "attack_hint", [], 150)
			return _item("t-r1c", battle_rule + " Happy? Press SEAL, then watch it unfold — you roll the dice in your own battles.", "pleased", "", [], 150)
		if r == 2:
			return _item("t-r2", "Lands we hold dig in: each round a held land gains a dug-in defender (the gold shield beside its number). They never march, so a dug-in land can send every other soldier and still stay ours. And after every round's battles comes the regroup phase, when we march troops one land toward the front." if s.map.maneuvers else "Lands we hold dig in: each round a held land gains a dug-in defender (the little shield). They never march, so a dug-in land can send every other soldier and still stay ours. From now on we may also make one move: drag onto a land of ours.", "neutral", "dug_in", [], 150)
		if r == 3:
			return _item("t-r3", "Surge: after ordering an attack, drag from the land you're attacking on to the next one. If the attack wins, the men who took it push on — after every other battle. Click the surge arrow to choose how many.", "neutral", "surge", [], 150)
		if s.is_last_round():
			return _item("t-last", "Final round! Score is lands plus region bonuses. Soldiers left standing are worth nothing now — spend them.", "alarmed", "final", [], 150)
		if r == 4:
			return _item("t-r4", "Look for a walk-in: the faded arrows show where everyone marched last round. A land left with one man falls to a small push.", "neutral", "", [], 150)
	elif s.world.round == 1 and ph == Session.Phase.PLANNING and s.plan_step == "reinforce":
		return _item("r1r", "The reinforcement phase: click our lands to place the recruits, then press ORDERS. Or press 'Advisor's plan' and I will draft the whole sheet for you.", "neutral", "", [], 35)
	elif s.world.round == 1 and ph == Session.Phase.PLANNING and s.sheet().packets.is_empty():
		return _item("r1", "The orders phase: select one of our lands, then click an enemy neighbor to attack — or drag onto it.", "neutral", "", [], 35)
	return {}
