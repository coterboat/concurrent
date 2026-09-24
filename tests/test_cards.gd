## Cards (3.7), generic seats, opening passes. No Node.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Cards := preload("res://engine/cards.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Validate := preload("res://engine/validate.gd")
const Resolve := preload("res://engine/resolve.gd")
const Income := preload("res://engine/income.gd")
const H := preload("res://tests/harness.gd")


func run(report: Callable) -> void:
	_sets(report)
	_seats(report)
	_cash_in_resolve(report)
	_draw_and_handover(report)


func _sets(report: Callable) -> void:
	var S := Types.CARD_SUN
	var M := Types.CARD_MOON
	var R := Types.CARD_STAR
	var W := Types.CARD_WILD
	report.call(Cards.is_set([S, S, S]), "three suns are a set")
	report.call(Cards.is_set([S, M, R]), "one of each is a set")
	report.call(Cards.is_set([S, S, W]), "two + wild is a set")
	report.call(Cards.is_set([S, M, W]), "two different + wild is a set")
	report.call(not Cards.is_set([S, S, M]), "two suns and a moon is not a set")
	report.call(not Cards.is_set([S, S]), "two cards are not a set")
	report.call(Cards.set_value(0) == 4 and Cards.set_value(3) == 10 and Cards.set_value(4) == 15 and Cards.set_value(5) == 20, "escalation 4,6,8,10,15,20")
	report.call(Array(Cards.best_set(PackedStringArray([S, M, S, W, R]))) == [S, M, R], "best set spends no wild when it can")
	report.call(Cards.best_set(PackedStringArray([S, M])).is_empty(), "two cards make no set")
	## Five cards of three kinds always hold a set.
	var kinds := [S, M, R]
	var always := true
	for a in 3:
		for b in 3:
			for c in 3:
				for d in 3:
					for e in 3:
						if Cards.best_set(PackedStringArray([kinds[a], kinds[b], kinds[c], kinds[d], kinds[e]])).is_empty():
							always = false
	report.call(always, "every five-card hand holds a set")


func _seats(report: Callable) -> void:
	for spec in [["known24", 3], ["known24", 4], ["known24", 5], ["world30", 3], ["world30", 4], ["world30", 5], ["knife7", 3]]:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % spec[0])
		var seats: Array = []
		for i in int(spec[1]):
			seats.append({"id": Setup.SEAT_IDS[i], "name": "P%d" % i})
		var w: Types.World = Setup.deal(map, seats, 5)
		var each: int = map.territories.size() / int(spec[1])
		var ok := true
		for s in seats:
			if MapLib.player_territory_ids(w, s["id"]).size() != each:
				ok = false
		var unocc := 0
		for t in w.territories.keys():
			if w.territories[t].owner == Types.UNOCCUPIED:
				unocc += 1
		report.call(ok and unocc == map.territories.size() - each * int(spec[1]), "%s %sp deals %s each, %s unoccupied" % [spec[0], spec[1], each, unocc])
		report.call(MapLib.hex_invariant_error(w) == "", "%s %sp deal holds invariants" % spec)
	var map2: Types.MapDef = Types.MapDef.from_file("res://maps/world30.json")
	var w2: Types.World = Setup.deal(map2, [{"id": "gold", "name": "Dad"}, {"id": "purple", "name": "Son"}], 9)
	report.call(w2.players.has("gold") and w2.players.has("purple") and w2.players.has("neutral"), "two-seat deal keeps chosen seat ids and adds Neutral")
	report.call(MapLib.player_territory_ids(w2, "gold").size() == 10 and MapLib.player_territory_ids(w2, "neutral").size() == 10, "world30 2p: 10 / 10 / 10 Neutral")
	## the opening sheet folds two capped passes into one
	var knife: Types.MapDef = H.knife7()
	var w3: Types.World = H.paint(knife, {"beacon": ["red", 1], "ridge": ["red", 1], "harbor": ["blue", 1], "gate": ["neutral", 5]})
	report.call(Setup.opening_cap(w3, knife, "beacon") == 4, "opening cap on Beacon = 2 × (1 + 1 friendly neighbor)")


func _cash_in_resolve(report: Callable) -> void:
	var map: Types.MapDef = Types.MapDef.from_file("res://maps/known24.json")
	var w: Types.World = Types.World.empty_from_map(map)
	w.round = 2
	w.players["red"] = H.player("red")
	w.players["blue"] = H.player("blue")
	for t in ["firth", "cairn", "moor", "wold"]:
		w.set_hex(t, "red", 3)
	for t in ["vale", "keep", "marsh", "throne"]:
		w.set_hex(t, "blue", 3)
	w.players["red"].cards = PackedStringArray([Types.CARD_SUN, Types.CARD_MOON, Types.CARD_STAR, Types.CARD_SUN])
	w.players["blue"].cards = PackedStringArray([Types.CARD_WILD, Types.CARD_WILD, Types.CARD_MOON])
	var red: Types.Sheet = H.sheet("red")
	red.cash_set = PackedStringArray([Types.CARD_SUN, Types.CARD_MOON, Types.CARD_STAR])
	var blue: Types.Sheet = H.sheet("blue")
	blue.cash_set = PackedStringArray([Types.CARD_WILD, Types.CARD_WILD, Types.CARD_MOON])
	report.call(Validate.validate_sheet(w, map, red).is_empty(), "a held set validates")
	var bogus: Types.Sheet = H.sheet("red")
	bogus.cash_set = PackedStringArray([Types.CARD_WILD, Types.CARD_WILD, Types.CARD_WILD])
	report.call(not Validate.validate_sheet(w, map, bogus).is_empty(), "cards you do not hold are rejected")
	var r: Dictionary = Resolve.resolve_round(w, map, [red, blue], 3)
	var nw: Types.World = r["world"]
	report.call(r["errors"].is_empty(), "two sets cashed the same round resolve")
	report.call(Array(nw.players["red"].cards) == [Types.CARD_SUN], "red keeps the unused card")
	report.call(nw.players["blue"].cards.is_empty(), "blue's hand is spent")
	report.call(nw.sets_cashed == 2, "the table counter advances by two")
	var vals: Array = []
	for e in r["events"]:
		if str(e["kind"]) == Types.EVENT_SET_CASHED:
			vals.append(int(e["value"]))
	report.call(vals == [4, 4], "simultaneous sets both pay the value at lock (got %s)" % [vals])


func _draw_and_handover(report: Callable) -> void:
	var map: Types.MapDef = Types.MapDef.from_file("res://maps/known24.json")
	var w: Types.World = Types.World.empty_from_map(map)
	w.round = 3
	w.players["red"] = H.player("red")
	w.players["blue"] = H.player("blue")
	w.set_hex("firth", "red", 9)
	w.set_hex("cairn", "blue", 1)
	w.set_hex("moor", "red", 2)
	w.players["blue"].cards = PackedStringArray([Types.CARD_STAR, Types.CARD_STAR])
	var red: Types.Sheet = H.sheet("red", [H.pkt("firth", "cairn", 8)])
	var r: Dictionary = Resolve.resolve_round(w, map, [red, H.sheet("blue")], 17)
	var nw: Types.World = r["world"]
	report.call(not nw.players["blue"].alive, "blue loses their last land")
	report.call(nw.players["red"].cards.size() == 3, "red draws 1 and seizes blue's 2 (has %s)" % nw.players["red"].cards.size())
	var kinds: Array = []
	for e in r["events"]:
		kinds.append(str(e["kind"]))
	report.call(kinds.has(Types.EVENT_CARDS_CAPTURED) and kinds.has(Types.EVENT_CARD_DRAWN), "capture and draw are in the log")
	## no capture, no card
	var hold: Dictionary = Resolve.resolve_round(nw, map, [H.sheet("red")], 17)
	report.call((hold["world"] as Types.World).players["red"].cards.size() == 3, "holding does not draw")
