## v1.8 capitals. Every commander keeps a seat of government: it pays the treasury (+2
## recruits a round), its defenders fire the fortress's longer line, and one more man may
## dig in there. When it falls, the captor plunders it (half the fallen commander's cards
## and a levy of fresh troops on the spot) and a new capital is named at once, which its
## commander may move to another of their lands the round after. Off unless the game asks
## for it (MapDef.capitals), so older saves replay untouched. No Node. No UI. Seeded RNG only.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Events := preload("res://engine/events.gd")
const Rng := preload("res://engine/rng.gd")

const NEUTRAL_ID := "neutral"
const TREASURY := 2 ## recruits a round while you hold your capital
const LEVY := 3 ## fresh troops the captor raises in a fallen capital


static func auto_pick(w: Types.World, map: Types.MapDef, pid: String) -> String:
	## Where a commander's capital goes when nobody chooses: deep in their own lands and
	## well held. Deterministic: the same world always names the same land.
	var best := ""
	var best_score := -1.0e9
	var ids: Array = Array(MapLib.player_territory_ids(w, pid))
	ids.sort()
	for t in ids:
		var friends := 0
		var foes := 0
		for n in MapLib.neighbors(map, str(t)):
			var ns: Types.TerritoryState = w.get_territory(n)
			if ns.owner == pid:
				friends += 1
			elif ns.owner != Types.UNOCCUPIED:
				foes += 1
		var score: float = 3.0 * friends - 2.0 * foes + float(w.get_territory(str(t)).held())
		if score > best_score:
			best_score = score
			best = str(t)
	return best


static func found(w: Types.World, map: Types.MapDef, choices: Dictionary, events: Array = []) -> void:
	## Deployment: every commander without a capital names one — their choice if it is
	## one of their lands, else the auto pick. (After a draft the first claim is already it.)
	if map == null or not map.capitals:
		return
	var pids: Array = w.players.keys()
	pids.sort()
	for pid in pids:
		var ps: Types.PlayerState = w.players[pid]
		if str(pid) == NEUTRAL_ID or str(pid).begins_with("__") or not ps.alive:
			continue
		if ps.capital != "" and w.get_territory(ps.capital) != null and w.get_territory(ps.capital).owner == pid:
			continue
		var want: String = str(choices.get(pid, ""))
		var ts: Types.TerritoryState = w.get_territory(want) if want != "" else null
		ps.capital = want if ts != null and ts.owner == pid else auto_pick(w, map, str(pid))
		if ps.capital != "":
			events.append(Events.capital_founded(str(pid), ps.capital, "deploy"))


static func claimed(w: Types.World, map: Types.MapDef, pid: String, land: String) -> void:
	## Lands claimed in turn: your first claim is your capital.
	if map == null or not map.capitals or not w.players.has(pid):
		return
	var ps: Types.PlayerState = w.players[pid]
	if ps.capital == "":
		ps.capital = land


static func can_move(w: Types.World, map: Types.MapDef, pid: String) -> bool:
	## the round after a capital falls, its commander may choose where the new one stands
	return map != null and map.capitals and w.players.has(pid) and (w.players[pid] as Types.PlayerState).capital_free


static func apply_moves(w: Types.World, map: Types.MapDef, by_player: Dictionary, events: Array) -> void:
	## Start of the round: a commander free to move their capital does (if they chose), and
	## the window closes for everyone — the choice was this round's, not forever.
	if map == null or not map.capitals:
		return
	var pids: Array = w.players.keys()
	pids.sort()
	for pid in pids:
		var ps: Types.PlayerState = w.players[pid]
		if ps.capital_free and by_player.has(pid):
			var want: String = (by_player[pid] as Types.Sheet).capital
			var ts: Types.TerritoryState = w.get_territory(want) if want != "" else null
			if ts != null and ts.owner == pid and want != ps.capital:
				ps.capital = want
				events.append(Events.capital_founded(str(pid), want, "moved"))
		ps.capital_free = false


static func upkeep(w: Types.World, map: Types.MapDef, events: Array, match_seed: int) -> void:
	## End of the round: every capital that changed hands is plundered, and its commander
	## (if they still hold any land) names a new one at once.
	if map == null or not map.capitals:
		return
	var pids: Array = w.players.keys()
	pids.sort()
	for pid in pids:
		var ps: Types.PlayerState = w.players[pid]
		if ps.capital == "" or str(pid) == NEUTRAL_ID:
			continue
		var ts: Types.TerritoryState = w.get_territory(ps.capital)
		if ts == null or ts.owner == pid:
			continue
		var fallen: String = ps.capital
		var captor: String = ts.owner
		var loot := PackedStringArray()
		var levy := 0
		if w.players.has(captor) and captor != NEUTRAL_ID:
			## the treasury: half the fallen commander's cards (rounded up), drawn by lot
			var hand: Array = Array(ps.cards)
			var rng: RefCounted = Rng.derive_stream(match_seed, w.round, "plunder|" + str(pid))
			var take: int = (hand.size() + 1) / 2
			for _k in take:
				var i: int = rng.roll_int(0, hand.size() - 1)
				loot.append(str(hand[i]))
				hand.remove_at(i)
			ps.cards = PackedStringArray(hand)
			(w.players[captor] as Types.PlayerState).cards.append_array(loot)
			## and the levy: the captor raises fresh troops in the city
			levy = LEVY
			ts.armies += levy
		events.append(Events.capital_taken(str(pid), fallen, captor, loot, levy))
		if levy > 0:
			var pev: Dictionary = Events.placed(captor, fallen, levy, ts.armies, 0)
			pev["capitalLevy"] = true
			events.append(pev)
		if not loot.is_empty():
			var cev: Dictionary = Events.cards_captured(str(pid), captor, loot)
			cev["plunder"] = true ## half a hand, not a war chest
			events.append(cev)
		ps.capital = auto_pick(w, map, str(pid))
		ps.capital_free = ps.capital != ""
		if ps.capital != "":
			events.append(Events.capital_founded(str(pid), ps.capital, "fallen"))
