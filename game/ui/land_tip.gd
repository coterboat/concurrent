## The land tooltip's words (peeled out of game_screen.gd in v1.13). What a land is, who holds
## it, and what the engine knows about it that the map can only hint at: what could strike it,
## whose road home runs through it, how many ways lead into its region, and what became of last
## round's columns that marched on it.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Income := preload("res://engine/income.gd")
const LastRound := preload("res://game/core/last_round.gd")
const BoardFacts := preload("res://game/core/board_facts.gd")
const Style := preload("res://game/core/style.gd")


static func lines(s: Node, board: Control, id: String) -> Array:
	var w: Types.World = board.world
	var ts: Types.TerritoryState = w.get_territory(id)
	var td: Types.TerritoryDef = s.map.get_territory(id)
	var out: Array = [td.display_name]
	if td.region != "":
		out.append(_region(s, w, td.region))
	if ts.owner == Types.UNOCCUPIED:
		out.append("Empty")
	else:
		var sp: Array = Income.home_split(ts)
		out.append("%s · %s · %d in the garrison" % [s.name_of(ts.owner), Style.plural(int(sp[0]), "army", "armies"), int(sp[1])])
	if board.threats.has(id):
		var th: Dictionary = board.threats[id]
		if int(th["max"]) > 0:
			out.append("%s could bring up to %d against it; you'll have %d%s." % [s.name_of(str(th["owner"])), int(th["max"]), int(th["held"]),
				" (your capital)" if bool(th.get("capital", false)) else ""])
	if board.hinges.has(id):
		var cut: Array = board.hinges[id]
		out.append("The road home for %s: if it falls, %s cut off." % [_names(s, cut), "that land is" if cut.size() == 1 else "they are"])
	var told: Array = []
	for g in board.ghosts:
		if str(g.get("to", "")) == id:
			var said: String = LastRound.said(g, s.name_of, s.hex_name)
			if said != "":
				told.append(said)
		elif str(g.get("surgeTo", "")) == id and str(g.get("surgeFate", "")) == LastRound.CLASH:
			told.append("%s's surge never got here: %s's met it on the border." % [s.name_of(str(g["owner"])), s.name_of(str(g["surgeBy"]))])
	if not told.is_empty():
		out.append("Last round: " + " ".join(told))
	return out


static func _region(s: Node, w: Types.World, region: String) -> String:
	## "Great Vane (+3) · Varek holds 5 of 7 · 2 ways in: from Morrow, from the Reach"
	var line := "%s  (+%d)" % [s.map.region_names.get(region, region), int(s.map.region_bonus.get(region, 0))]
	var sh: Dictionary = BoardFacts.shares(w, s.map).get(region, {})
	if not sh.is_empty() and str(sh["leader"]) != "":
		var n: int = (sh["members"] as PackedStringArray).size()
		if int(sh["led"]) == n:
			line += " · %s holds it all" % s.name_of(str(sh["leader"]))
		else:
			line += " · %s holds %d of %d" % [s.name_of(str(sh["leader"])), int(sh["led"]), n]
	var ways: Array = BoardFacts.ways_in(s.map, region)
	if ways.size() <= 3:
		var bits: Array = []
		for pr in ways:
			bits.append("%s → %s" % [s.hex_name(str(pr[0])), s.hex_name(str(pr[1]))])
		line += "\n%d way%s in: %s" % [ways.size(), "" if ways.size() == 1 else "s", ", ".join(bits)]
	return line


static func _names(s: Node, ids: Array) -> String:
	var names: Array = []
	for t in ids:
		names.append(s.hex_name(str(t)))
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names[-1])
