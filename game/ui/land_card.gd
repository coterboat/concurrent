## Floating card beside the selected land: who holds it, reinforce it, strike from it.
extends PanelContainer

const Style := preload("res://game/core/style.gd")
const Income := preload("res://engine/income.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Combat := preload("res://engine/combat.gd")
const Session := preload("res://game/core/session.gd")

const ODDS := {
	"long shot": Color(0.9, 0.42, 0.35), "toss-up": Color(0.95, 0.72, 0.35),
	"likely": Color(0.72, 0.85, 0.45), "lock": Color(0.45, 0.85, 0.5), "certain": Color(0.45, 0.85, 0.5),
}

var session: Node
var gs: Control
var land := ""
var _box: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.flat(Color(0.035, 0.05, 0.085, 0.95), Color(Style.GOLD, 0.7), 1, 8, 12))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 5)
	add_child(_box)
	custom_minimum_size = Vector2(290, 0)
	visible = false


func show_for(id: String) -> void:
	land = id
	visible = id != ""
	if visible:
		rebuild()
		_fit.call_deferred() ## wrapped text settles a frame later: place it again, clear of the land


func rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if land == "" or session.world == null:
		visible = false
		return
	var s = session
	var ts: Types.TerritoryState = s.world.get_territory(land)
	var td: Types.TerritoryDef = s.map.get_territory(land)
	var mine: bool = ts.owner == s.planner
	var planning: bool = s.phase == Session.Phase.PLANNING
	if s.phase == Session.Phase.MANEUVER:
		_rebuild_maneuver(ts, td, mine)
		return
	## header
	var h := HBoxContainer.new()
	var dot := _Dot.new()
	dot.pid = ts.owner
	dot.custom_minimum_size = Vector2(22, 22)
	h.add_child(dot)
	var t := Style.label(td.display_name, 22, Style.CREAM, "display")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(Style.chip("✕", func(): gs.select(""), Style.MUTED, 13))
	_box.add_child(h)
	var reg := ""
	if td.region != "":
		reg = "%s  +%d" % [s.map.region_names.get(td.region, td.region), int(s.map.region_bonus.get(td.region, 0))]
	var who: String = "Empty land" if ts.owner == Types.UNOCCUPIED else s.name_of(ts.owner)
	_box.add_child(Style.label(("%s  ·  %s" % [who, reg]) if reg != "" else who, 15, Style.PARCH, "italic"))
	for row in _trait_rows(s, ts, td):
		_box.add_child(row)
	if not mine:
		var d: Dictionary = s.expected_defense(land)
		if ts.owner != Types.UNOCCUPIED:
			var sp: Array = Income.home_split(ts)
			var line := "%s  ·  %d in the garrison" % [Style.plural(int(sp[0]), "army", "armies"), int(sp[1])]
			if int(d["ceiling"]) > int(d["now"]):
				line += "  ·  could reach %d" % d["ceiling"]
			_box.add_child(Style.label(line, 17, Style.CREAM, "bold"))
		if planning and s.plan_step == "reinforce":
			_box.add_child(Style.label("Attacks come in the orders phase, once your recruits are placed.", 14, Style.MUTED, "italic"))
		elif planning:
			var any := false
			for n in MapLib.neighbors(s.map, land):
				if s.world.get_territory(n).owner == s.planner:
					_box.add_child(_strike_row(n, land, true))
					any = true
			if not any:
				_box.add_child(Style.label("None of your lands border it.", 15, Style.MUTED, "italic"))
		_fit()
		return
	## ours
	var placed: int = s.placed_on(land)
	var sp2: Array = Income.home_split(ts)
	var line2 := "%s  ·  %d in the garrison" % [Style.plural(int(sp2[0]), "army", "armies"), int(sp2[1])]
	if placed > 0:
		line2 += "  (+%d arriving)" % placed
	_box.add_child(Style.label(line2, 17, Style.CREAM, "bold"))
	if planning and s.plan_step == "orders":
		## the recruits are placed; the card is about the orders now
		pass
	else:
		_box.add_child(_recruit_row(land, placed))
	if not planning or s.plan_step == "reinforce":
		_fit()
		return
	_orders_rows(land, ts)


func _recruit_row(land: String, placed: int) -> HBoxContainer:
	var s = session
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	pr.add_child(Style.label("Recruits", 16, Style.GOLD, "bold"))
	pr.add_child(Style.chip("  −  ", func(): gs.place(land, -1), Style.CREAM, 18))
	var q := Style.label("+%d" % placed, 22, Style.GOLD, "display")
	q.custom_minimum_size = Vector2(44, 0)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.add_child(q)
	pr.add_child(Style.chip("  +  ", func(): gs.place(land, 1), Style.CREAM, 18))
	pr.add_child(Style.label("room %d" % maxi(0, s.place_cap(land) - placed), 14, Style.MUTED))
	return pr


func _orders_rows(land: String, ts: Types.TerritoryState) -> void:
	var s = session
	var sends: int = s.max_send(land)
	var note := "%d can march" % sends
	note += " (the garrison holds the land)"
	_box.add_child(Style.label(note, 14, Style.MUTED, "italic"))
	var rows := 0
	for n in MapLib.neighbors(s.map, land):
		if s.world.get_territory(n).owner != s.planner:
			_box.add_child(_strike_row(land, n, false))
			rows += 1
	for n in MapLib.neighbors(s.map, land):
		if s.world.get_territory(n).owner == s.planner and s.world.round > 1 and not s.map.maneuvers:
			_box.add_child(_move_row(land, n)) ## v1.3 games march in the regroup phase instead
	if rows > 0:
		_box.add_child(Style.label("Tip: click an enemy land, or drag onto it.", 13, Style.MUTED, "italic"))
	_fit()


func _rebuild_maneuver(ts: Types.TerritoryState, td: Types.TerritoryDef, mine: bool) -> void:
	## the regroup phase: where can this land's soldiers march?
	var s = session
	var h := HBoxContainer.new()
	var dot := _Dot.new()
	dot.pid = ts.owner
	dot.custom_minimum_size = Vector2(22, 22)
	h.add_child(dot)
	var t := Style.label(td.display_name, 22, Style.CREAM, "display")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(Style.chip("✕", func(): gs.select(""), Style.MUTED, 13))
	_box.add_child(h)
	var w = s.maneuver_world()
	var now: Types.TerritoryState = w.get_territory(land)
	var who: String = "Empty land" if ts.owner == Types.UNOCCUPIED else s.name_of(ts.owner)
	_box.add_child(Style.label(who, 15, Style.PARCH, "italic"))
	var sp3: Array = Income.home_split(now)
	var line := "%s  ·  %d in the garrison" % [Style.plural(int(sp3[0]), "army", "armies"), int(sp3[1])]
	_box.add_child(Style.label(line, 17, Style.CREAM, "bold"))
	if not mine:
		_fit()
		return
	var can: int = s.can_move_from(land)
	_box.add_child(Style.label("%d can still march out — one land, no further" % can, 14, Style.MUTED, "italic"))
	var any := false
	for n in MapLib.neighbors(s.map, land):
		if s.world.get_territory(n).owner != s.planner:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var danger := 0
		for e in MapLib.neighbors(s.map, n):
			var es: Types.TerritoryState = s.world.get_territory(e)
			if es.owner != s.planner and es.owner != Types.UNOCCUPIED:
				danger = maxi(danger, es.armies)
		var l := Style.label("➜ %s  %d%s" % [s.hex_name(n), w.get_territory(n).held(), ("  · faces %d" % danger) if danger > 0 else "  · quiet"], 15, Style.CREAM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var idx: int = s.move_index(land, n)
		if idx >= 0:
			var b0 := Style.chip("marching %d" % int(s.my_moves()[idx]["n"]), func(): gs.edit_order(land, n), Style.GOOD, 14)
			b0.tooltip_text = "Edit this march"
			row.add_child(b0)
		else:
			var b := Style.chip("March", func(): gs.order_march(land, n), Style.PARCH, 14)
			b.disabled = can < 1
			row.add_child(b)
		_box.add_child(row)
	if not any:
		_box.add_child(Style.label("None of your lands border it.", 14, Style.MUTED, "italic"))
	else:
		_box.add_child(Style.label("Tip: drag from one of your lands onto a neighbour.", 13, Style.MUTED, "italic"))
	_fit()


func _strike_row(from_id: String, to_id: String, from_view: bool) -> Control:
	var s = session
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var ns: Types.TerritoryState = s.world.get_territory(to_id)
	var dot := _Dot.new()
	dot.pid = s.planner if from_view else ns.owner
	dot.custom_minimum_size = Vector2(16, 16)
	row.add_child(dot)
	var d: Dictionary = s.expected_defense(to_id)
	var lbl: String
	if from_view:
		lbl = "from %s" % s.hex_name(from_id)
	else:
		lbl = "%s  %s" % [s.hex_name(to_id), "–" if ns.owner == Types.UNOCCUPIED else str(d["now"])]
	var l := Style.label(lbl, 16, Style.CREAM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var idx: int = s.packet_index(from_id, to_id)
	if idx >= 0:
		var b0 := Style.chip("⚔ %d" % (s.sheet().packets[idx] as Types.Packet).strength, func(): gs.edit_order(from_id, to_id), Style.GOLD, 15)
		b0.tooltip_text = "Edit this attack"
		row.add_child(b0)
		return row
	var mx: int = s.max_send(from_id)
	var b := Style.chip("Attack", func(): gs.order_attack(from_id, to_id), Style.CREAM, 15)
	if mx >= 1:
		var o: Dictionary = s.odds(mx, int(d["now"]), to_id)
		b.text = "Attack · %s" % o["word"]
		b.add_theme_color_override("font_color", ODDS.get(o["word"], Style.CREAM))
		b.tooltip_text = "All %d who can march, against %d now" % [mx, d["now"]]
	else:
		b.disabled = true
		b.tooltip_text = s._cannot_send(from_id)
	row.add_child(b)
	return row


func _move_row(from_id: String, to_id: String) -> Control:
	var s = session
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Style.label("%s (yours)" % s.hex_name(to_id), 15, Style.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var r: Types.Regroup = s.sheet().regroup
	if r != null and r.from_id == from_id and r.to_id == to_id:
		row.add_child(Style.label("moving %d" % r.strength, 14, Style.GOLD, "bold"))
	else:
		var b := Style.chip("Move", func(): gs.order_move(from_id, to_id), Style.PARCH, 14)
		b.disabled = s.max_regroup(from_id) < 1
		b.tooltip_text = "One move per round."
		row.add_child(b)
	return row


func _trait_rows(s, ts: Types.TerritoryState, td: Types.TerritoryDef) -> Array:
	## v1.7: what this particular land does, in the words the rules use.
	var out: Array = []
	if td.has_trait("fort"):
		out.append(_trait("fort", "Fortress", "Its defenders fire a line of %d, not five, and one more man may dig in here."
			% [Combat.LINE + s.map.fort_bonus], Style.GOLD))
	if td.has_trait("pass"):
		out.append(_trait("pass", "Pass", "No more than %d may storm it in one column, however many you have."
			% [s.map.pass_cap], Style.GOLD))
	if td.has_trait("port"):
		out.append(_trait("port", "Port", "Joined by sea to your other ports: troops may march between them, and supply runs along them.", Style.GOLD))
	if s.map.supply and ts.owner != Types.UNOCCUPIED and not MapLib.in_supply(s.world, s.map, land):
		out.append(_trait("supply", "Cut off", "No road home: it pays no income and takes no recruits until it is joined up again.", Style.CRIMSON.lightened(0.3)))
	return out


func _trait(icon: String, name: String, help: String, tint: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var i := TextureRect.new()
	i.texture = Style.tex("res://assets/icons/%s.png" % icon)
	i.custom_minimum_size = Vector2(20, 20)
	i.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	i.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	i.modulate = tint
	h.add_child(i)
	var l := Style.label(name, 15, tint, "bold")
	h.add_child(l)
	h.tooltip_text = help
	i.tooltip_text = help
	l.tooltip_text = help
	return h


func _fit() -> void:
	reset_size()
	gs.place_popover(self, land)


class _Dot extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := ""

	func _draw() -> void:
		if pid == "":
			draw_arc(size * 0.5, 6.0, 0, TAU, 16, Style.PARCH, 1.5)
			return
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, minf(size.x, size.y) * 0.42, Style.seat_color(pid), Style.CREAM, 1.2)
