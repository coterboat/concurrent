## Cards (bible 3.7). Income spikes, not a second game.
## Deck: 3 types × N territories, plus 2 wilds — drawn by seeded stream, so the
## deck needs no state on World. Set = three matching or one of each (wild
## substitutes). Table escalation 4, 6, 8, 10, then +5, global counter.
## Sets cashed in the same round are simultaneous: all pay the value the table
## was at when sheets locked, then the counter advances by the number cashed.
## v1.6 (games with rules >= 16): every card names a land, as in Risk: "sun@ridge". Each
## land has one card of a fixed kind (a seeded deal of the kinds over the map), a card
## already in someone's hand can't be drawn again, and turning in a card whose land you
## hold puts one free soldier there. Older cards are the bare kind ("sun").
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


static func kind(card: String) -> String:
	return card.get_slice("@", 0)


static func land(card: String) -> String:
	## the land a card names ("" for a bare card)
	return card.get_slice("@", 1) if card.contains("@") else ""


static func deck_kinds(match_seed: int, lands: Array) -> Dictionary:
	## land -> kind: the kinds dealt evenly over the map in a seeded order
	var ids: Array = lands.duplicate()
	ids.sort()
	var rng: RefCounted = Rng.derive_stream(match_seed, 0, "deck")
	for i in range(ids.size() - 1, 0, -1):
		var j: int = rng.rand_index(i + 1)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	var out := {}
	for i in ids.size():
		out[str(ids[i])] = TYPES[i % 3]
	return out


static func is_set(cards: Array) -> bool:
	if cards.size() != 3:
		return false
	var wild := 0
	var kinds := {}
	for c in cards:
		var s := kind(str(c))
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


static func best_set(hand: PackedStringArray, owned: Dictionary = {}) -> PackedStringArray:
	## Prefer sets that spend no wilds, then one wild. Empty if none.
	## v1.6: among equal sets, the one with the most cards naming lands we hold (owned: land -> true).
	var named: Array = []
	for c in hand:
		if land(c) != "":
			named.append(c)
	if not named.is_empty():
		return _best_named(hand, owned)
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


static func _best_named(hand: PackedStringArray, owned: Dictionary) -> PackedStringArray:
	## every three cards of the hand: a set, scored by the free soldiers it brings
	var best := PackedStringArray()
	var best_n := -1
	var n: int = hand.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var trio := [hand[i], hand[j], hand[k]]
				if not is_set(trio):
					continue
				var bonus := 0
				var wilds := 0
				for c in trio:
					if owned.has(land(str(c))):
						bonus += 1
					if kind(str(c)) == Types.CARD_WILD:
						wilds += 1
				var sc: int = bonus * 4 - wilds
				if sc > best_n:
					best_n = sc
					best = PackedStringArray(trio)
	return best


static func draw_land(match_seed: int, round: int, player_id: String, lands: Array, taken: Dictionary) -> String:
	## v1.6: a land card nobody holds (taken: land -> true), as "kind@land"
	var kinds: Dictionary = deck_kinds(match_seed, lands)
	var free: Array = []
	var ids: Array = lands.duplicate()
	ids.sort()
	for t in ids:
		if not taken.has(str(t)):
			free.append(str(t))
	if free.is_empty():
		free = ids ## every card is out: a second copy, rather than no card
	var rng: RefCounted = Rng.derive_stream(match_seed, round, "card|" + player_id)
	var pick: String = str(free[rng.rand_index(free.size())])
	return "%s@%s" % [str(kinds[pick]), pick]


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
