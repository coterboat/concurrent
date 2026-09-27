## v1.8 Fortune. The dice keep no memory, but Fortune keeps a ledger: every assault you
## fight is weighed against the odds quoted as it began, and each time the dice have cost you
## a whole battle's worth she owes you one favour (✦). Spend it in a battle you are watching,
## after an exchange that went badly for you, and the whole exchange is thrown again, as if
## it never happened: once per battle for each side. Every commander starts with one and can
## hold three; the AI spends by doctrine; a human's favour is only ever spent by the human.
## Off unless the game asks for it (MapDef.fortune). No Node. No UI. Seeded RNG only.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Combat := preload("res://engine/combat.gd")

const START := 1 ## favours every commander begins the war with
const MOST := 3 ## never more in hand than this
const BATTLE := 75 ## the ledger is kept in hundredths of a battle: three-quarters of one owes you a favour
const FLOOR := -150 ## a lucky streak is remembered, but only so far back
const NEUTRAL_ID := "neutral"
const EVENT := "FortuneGained"
## v1.9 (rules 18): the ledger is kept exchange by exchange (resolve.gd puts the dice's swing
## on each battle as "luck"), so a battle you fell back from counts, and your own rethrows
## don't count against you. Before, every fall-back was ignored while every win was booked
## as luck, so an attacker's ledger only ever ran down and a spent favour almost never came
## back. The bar and the floor are set by the arena (docs/CHANGELOG.md v1.9).
const BATTLE_18 := 50 ## half a battle's worth of bad luck owes you a favour
const FLOOR_18 := -20 ## ...and a lucky streak is held against you only a little
static var tune_bar := 0 ## tools/arena.gd: try another bar or floor on the same seeds
static var tune_floor := 0


static func bar(map: Types.MapDef) -> int:
	if map != null and map.rules >= 18:
		return tune_bar if tune_bar > 0 else BATTLE_18
	return BATTLE


static func floor_of(map: Types.MapDef) -> int:
	if map != null and map.rules >= 18:
		return tune_floor if tune_floor < 0 else FLOOR_18
	return FLOOR


static func held(w: Types.World, pid: String) -> int:
	return int((w.players[pid] as Types.PlayerState).fortune) if w.players.has(pid) else 0


static func found(w: Types.World, map: Types.MapDef) -> void:
	if map == null or not map.fortune:
		return
	for pid in w.players.keys():
		if str(pid) != NEUTRAL_ID and not str(pid).begins_with("__"):
			(w.players[pid] as Types.PlayerState).fortune = START


static func bad_for(a0: int, d0: int, a: int, d: int) -> String:
	## Whose exchange was it a disaster for? "a" the attacker, "d" the defender, "" neither.
	## Bad means the exchange ended your battle, or cost you two more men than it cost them.
	var lost_a: int = a0 - a
	var lost_d: int = d0 - d
	if a <= 0 or lost_a - lost_d >= 2:
		return "a"
	if d <= 0 or lost_d - lost_a >= 2:
		return "d"
	return ""


static func doctrine(side: String, a0: int, d0: int, a: int, d: int, bonus: int, battle: String) -> bool:
	## An AI calls on Fortune when the exchange swung a real fight: the battle was worth
	## having (a quarter or better) and those three volleys cost it a fifth of its chances.
	var p0: float = Combat.capture_rate(a0, d0, battle, bonus)
	var p1: float = 0.0 if a <= 0 else (1.0 if d <= 0 else Combat.capture_rate(a, d, battle, bonus))
	if side == "d":
		p0 = 1.0 - p0
		p1 = 1.0 - p1
	return p0 >= 0.25 and p0 - p1 >= 0.2


static func upkeep(before: Types.World, w: Types.World, map: Types.MapDef, events: Array) -> void:
	## End of the round: weigh every assault against its odds, and pay out the favours owed.
	if map == null or not map.fortune:
		return
	var delta := {}
	for e in events:
		if str(e.get("kind", "")) != Types.EVENT_INVASION:
			continue
		if bool(e.get("fellBack", false)) and not e.has("luck"):
			continue ## v1.8 ignored a battle abandoned halfway (the flaw v1.9 fixes)
		var owed: int = _owed(before, map, e)
		var a: String = str(e["attackerId"])
		var d: String = str(e["defenderId"])
		delta[a] = int(delta.get(a, 0)) + owed
		delta[d] = int(delta.get(d, 0)) - owed
	var top: int = bar(map)
	var bottom: int = floor_of(map)
	var pids: Array = delta.keys()
	pids.sort()
	for pid in pids:
		if not w.players.has(pid) or str(pid) == NEUTRAL_ID:
			continue
		var ps: Types.PlayerState = w.players[pid]
		if not ps.alive:
			continue
		ps.fortune_meter += int(delta[pid])
		var gained := 0
		while ps.fortune_meter >= top and ps.fortune < MOST:
			ps.fortune += 1
			ps.fortune_meter -= top
			gained += 1
		ps.fortune_meter = clampi(ps.fortune_meter, bottom, top)
		if gained > 0:
			events.append({"kind": EVENT, "playerId": str(pid), "gained": gained, "fortune": ps.fortune})


static func _owed(before: Types.World, map: Types.MapDef, e: Dictionary) -> int:
	## What the dice owe the attacker for one assault, in hundredths of a battle (the defender
	## is owed the opposite). v1.9: the swing measured exchange by exchange, when the battle
	## carries it; a one-roll battle is its odds against its outcome.
	if e.has("luck"):
		return -int(e["luck"])
	var bonus: int = MapLib.defender_bonus(before, map, str(e.get("to", "")))
	var p: float = Combat.capture_rate(int(e["attackerSize"]), int(e["defenderSize"]), map.battle, bonus)
	return int(round(100.0 * (p - (1.0 if bool(e["attackerWon"]) else 0.0))))


static func meter_share(map: Types.MapDef, meter: int) -> float:
	## how far along the next favour is, 0..1 (for the bar under a commander's ✦)
	return clampf(float(meter) / float(maxi(1, bar(map))), 0.0, 1.0)
