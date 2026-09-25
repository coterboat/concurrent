## Cards (bible 3.7). Income spikes, not a second game.
## Deck: 3 types × N territories, plus 2 wilds — drawn by seeded stream, so the
## deck needs no state on World. Set = three matching or one of each (wild
## substitutes). Table escalation 4, 6, 8, 10, then +5, global counter.
## Sets cashed in the same round are simultaneous: all pay the value the table
## was at when sheets locked, then the counter advances by the number cashed.
## No Node. No UI. Seeded RNG only.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Rng := preload("res://engine/rng.gd")

const HAND_LIMIT := 5
const TYPES := [Types.CARD_SUN, Types.CARD_MOON, Types.CARD_STAR]


static func set_value(sets_cashed: int) -> int:
	var early := [4, 6, 8, 10]
	if sets_cashed < early.size():
		return int(early[sets_cashed])
	return 10 + 5 * (sets_cashed - early.size() + 1)


static func is_set(cards: Array) -> bool:
	if cards.size() != 3:
		return false
	var wild := 0
	var kinds := {}
	for c in cards:
		var s := str(c)
		if s == Types.CARD_WILD:
			wild += 1
		elif TYPES.has(s):
			kinds[s] = int(kinds.get(s, 0)) + 1
		else:
			return false
	if wild >= 2:
		return true
	if kinds.size() == 1:
		return true ## three of a kind, or two + wild
	if kinds.size() + wild == 3 and _max_count(kinds) == 1:
		return true ## one of each, a wild filling the gap
	return false


static func holds(hand: PackedStringArray, cards: PackedStringArray) -> bool:
	var need := {}
	for c in cards:
		need[c] = int(need.get(c, 0)) + 1
	var have := {}
	for c in hand:
		have[c] = int(have.get(c, 0)) + 1
	for k in need.keys():
		if int(have.get(k, 0)) < int(need[k]):
			return false
	return true


static func without(hand: PackedStringArray, cards: PackedStringArray) -> PackedStringArray:
	var out := hand.duplicate()
	for c in cards:
		var i := out.find(c)
		if i >= 0:
			out.remove_at(i)
	return out


static func best_set(hand: PackedStringArray) -> PackedStringArray:
	## Prefer sets that spend no wilds, then one wild. Empty if none.
	var plain: Array = []
	var wilds := 0
	for c in hand:
		if c == Types.CARD_WILD:
			wilds += 1
		else:
			plain.append(c)
	for t in TYPES:
		if plain.count(t) >= 3:
			return PackedStringArray([t, t, t])
	var distinct: Array = []
	for t in TYPES:
		if plain.has(t):
			distinct.append(t)
	if distinct.size() == 3:
		return PackedStringArray(distinct)
	if wilds >= 1:
		for t in TYPES:
			if plain.count(t) >= 2:
				return PackedStringArray([t, t, Types.CARD_WILD])
		if distinct.size() == 2:
			return PackedStringArray([distinct[0], distinct[1], Types.CARD_WILD])
	if wilds >= 2 and plain.size() >= 1:
		return PackedStringArray([plain[0], Types.CARD_WILD, Types.CARD_WILD])
	if wilds >= 3:
		return PackedStringArray([Types.CARD_WILD, Types.CARD_WILD, Types.CARD_WILD])
	return PackedStringArray()


static func draw(match_seed: int, round: int, player_id: String, territory_count: int, wilds: bool = true) -> String:
	## v1.3 decks are men, horses and cannon only (wilds = false); older saves keep wilds.
	var rng: RefCounted = Rng.derive_stream(match_seed, round, "card|" + player_id)
	var n: int = maxi(1, territory_count)
	var roll: int = rng.rand_index(3 * n + (2 if wilds else 0))
	if roll >= 3 * n:
		return Types.CARD_WILD
	return str(TYPES[roll % 3])


static func _max_count(kinds: Dictionary) -> int:
	var m := 0
	for k in kinds.keys():
		m = maxi(m, int(kinds[k]))
	return m
