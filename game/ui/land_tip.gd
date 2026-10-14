## The land tooltip (peeled out of game_screen.gd in v1.13; where it sits, in v1.13.2). What a land
## is, who holds it, and what the engine knows about it that the map can only hint at: what could
## strike it, whose road home runs through it, how many ways lead into its region, and what became
## of last round's columns that marched on it.
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
		out.append(_region(s, w, td.region, id))
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
	for g in LastRound.merged(board.ghosts, id):
		var said: String = LastRound.said(g, s.name_of, s.hex_name)
		if said != "":
			told.append(said)
	for g in board.ghosts:
		if str(g.get("surgeTo", "")) == id and str(g.get("surgeFate", "")) == LastRound.CLASH:
			told.append("%s surge never got here: %s met it on the border." % [Style.owns(s.name_of(str(g["owner"])), true), Style.owns(s.name_of(str(g["surgeBy"])))])
	if not told.is_empty():
		out.append("Last round: " + " ".join(told))
	return out


static func _region(s: Node, w: Types.World, region: String, here: String = "") -> String:
	## "Great Vane (+3) · Varek holds 5 of 7", then "2 ways into Great Vane: Morrow → Vane Tor (here), …"
	## v1.13.2: the ways in are the region's, so the line names it, and marks the one at this land
	## (every land of the region said the same words, which read as if they were about the land)
	var rname: String = str(s.map.region_names.get(region, region))
	var line := "%s  (+%d)" % [rname, int(s.map.region_bonus.get(region, 0))]
	var sh: Dictionary = BoardFacts.shares(w, s.map).get(region, {})
	if not sh.is_empty() and str(sh["leader"]) != "":
		var n: int = (sh["members"] as PackedStringArray).size()
		if int(sh["led"]) == n:
			line += " · %s it all" % Style.says(s.name_of(str(sh["leader"])), "holds")
		else:
			line += " · %s %d of %d" % [Style.says(s.name_of(str(sh["leader"])), "holds"), int(sh["led"]), n]
	var ways: Array = BoardFacts.ways_in(s.map, region)
	if ways.size() <= 3:
		var bits: Array = []
		for pr in ways:
			bits.append("%s → %s%s" % [s.hex_name(str(pr[0])), s.hex_name(str(pr[1])), " (here)" if str(pr[1]) == here else ""])
		line += "\n%d way%s into %s: %s" % [ways.size(), "" if ways.size() == 1 else "s", rname, ", ".join(bits)]
	return line


const WIDE := 400.0 ## v1.13.2: past this the words wrap, so the box stays narrow


static func show(tip: PanelContainer, label: Label, text: String, at: Vector2, area: Rect2, gap: float) -> void:
	## fill the tooltip, keep it narrow (a long line wraps), and put it where place() says
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 0.0
	tip.visible = true
	tip.reset_size()
	if tip.size.x > WIDE:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDE - (tip.size.x - label.size.x)
		tip.reset_size()
		tip.reset_size()
	tip.position = place(at, tip.size, area, gap)


static func place(at: Vector2, tip: Vector2, area: Rect2, gap: float) -> Vector2:
	## v1.13.2: where the tooltip goes, keeping off the middle of the map where the fighting is
	## (the play critic: "the tooltip box is also big and covers the middle of the map"):
	##   beside the land, level with it, on its outer side (a land left of centre: to its left);
	##   no room there (a land near the edge): above or below it, the side nearer the edge,
	##   reaching outward; only then beside it on the inner side. Never over the land itself.
	var c: Vector2 = area.get_center()
	var outer_left: bool = at.x < c.x
	var left_x: float = at.x - gap - tip.x
	var right_x: float = at.x + gap
	var level_y: float = at.y - tip.y * 0.5
	if outer_left and left_x >= area.position.x:
		return _inside(Vector2(left_x, level_y), tip, area)
	if not outer_left and right_x + tip.x <= area.end.x:
		return _inside(Vector2(right_x, level_y), tip, area)
	var below_y: float = at.y + gap
	var above_y: float = at.y - gap - tip.y
	var fits_below: bool = below_y + tip.y <= area.end.y
	var fits_above: bool = above_y >= area.position.y
	var reach_x: float = (at.x + gap - tip.x) if outer_left else (at.x - gap)
	if fits_below and (at.y >= c.y or not fits_above):
		return _inside(Vector2(reach_x, below_y), tip, area)
	if fits_above:
		return _inside(Vector2(reach_x, above_y), tip, area)
	return _inside(Vector2(right_x if outer_left else left_x, level_y), tip, area)


static func _inside(p: Vector2, tip: Vector2, area: Rect2) -> Vector2:
	return Vector2(clampf(p.x, area.position.x, maxf(area.position.x, area.end.x - tip.x)),
		clampf(p.y, area.position.y, maxf(area.position.y, area.end.y - tip.y)))


static func _names(s: Node, ids: Array) -> String:
	var names: Array = []
	for t in ids:
		names.append(s.hex_name(str(t)))
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names[-1])


static func stale(board: Control, hovered: Control, just_covered: bool) -> bool:
	## v2.0.1: a land's tip goes when the cursor is no longer on the board, or the moment the phase
	## turns or a report, a battle or a dialog opens over it (the play critic: Fenmoor's tip stayed up through a whole
	## round's report and the next round's battles; the board never heard the cursor leave, as the
	## report took the mouse)
	var on_board: bool = hovered != null and (hovered == board or board.is_ancestor_of(hovered))
	return just_covered or not on_board
