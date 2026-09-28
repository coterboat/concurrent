## The order sheet. Rebuilt on every change; cheap and never stale.
extends PanelContainer

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Cards := preload("res://engine/cards.gd")
const Session := preload("res://game/core/session.gd")

const ODDS_COLOR := {
	"long shot": Color(0.9, 0.42, 0.35),
	"toss-up": Color(0.95, 0.72, 0.35),
	"likely": Color(0.72, 0.85, 0.45),
	"lock": Color(0.45, 0.85, 0.5),
	"certain": Color(0.45, 0.85, 0.5),
}

var session: Node
var gs: Control ## game screen: selection + surge picking
var drawer := false ## review drawer: no seal button, no selected-land section
var _body: VBoxContainer
var _seal: Button
var _clock: Label
var _scroll: ScrollContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.panel_box(14))
	custom_minimum_size = Vector2(410, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)
	_clock = Style.label("", 18, Style.WARN, "bold")
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.visible = false
	v.add_child(_clock)
	_seal = Style.button("Seal Orders", func(): gs.try_seal(), 0, 26)
	_seal.custom_minimum_size = Vector2(0, 68)
	_seal.icon = Style.icon("seal")
	_seal.expand_icon = true
	_seal.add_theme_constant_override("icon_max_width", 44)
	v.add_child(_seal)
	if drawer:
		_seal.visible = false
		custom_minimum_size = Vector2(420, 0)
		var close := Style.chip("Close ✕", func(): visible = false, Style.MUTED, 14)
		close.size_flags_horizontal = Control.SIZE_SHRINK_END
		v.add_child(close)
		v.move_child(close, 0)


func _process(_d: float) -> void:
	if session == null:
		return
	var t: float = session.time_left
	_clock.visible = t > 0.0 and (session.phase == Session.Phase.PLANNING or session.phase == Session.Phase.OPENING)
	if _clock.visible:
		_clock.text = "⌛ %d:%02d left to seal" % [int(t) / 60, int(t) % 60]
		_clock.add_theme_color_override("font_color", Style.CRIMSON if t < 15.0 else Style.WARN)


func refresh() -> void:
	if session == null or session.world == null:
		return
	var planning: bool = session.phase == Session.Phase.PLANNING or session.phase == Session.Phase.OPENING
	if drawer:
		if not planning:
			visible = false
		if not visible:
			return
	else:
		visible = planning
	if not planning:
		return
	var y: float = _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_header()
	_reinforcements()
	if session.phase == Session.Phase.PLANNING and session.map.cards:
		_cards()
	if not drawer:
		_selected()
	if session.phase == Session.Phase.PLANNING:
		_orders()
	_warnings()
	_seal.text = "Seal Deployment" if session.phase == Session.Phase.OPENING else ("Seal Final Orders" if session.is_last_round() and not session.conquest() else "Seal Orders")
	_scroll.set_deferred("scroll_vertical", y)


# ------------------------------------------------------------------ sections

func _section(title: String, icon_name: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if icon_name != "":
		var ic := TextureRect.new()
		ic.texture = Style.icon(icon_name)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(26, 26)
		h.add_child(ic)
	h.add_child(Style.label(title, 20, Style.GOLD, "display"))
	box.add_child(h)
	_body.add_child(box)
	return box


func _header() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var pic := TextureRect.new()
	pic.texture = Style.portrait(str(session.seat(session.planner).get("portrait", "player")))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(64, 64)
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	h.add_child(v)
	var who := Style.label(session.name_of(session.planner), 26, Style.seat_color(session.planner).lightened(0.35), "display")
	v.add_child(who)
	var sub := "Place your starting armies" if session.phase == Session.Phase.OPENING else "Your sealed orders for this round"
	v.add_child(Style.label(sub, 17, Style.PARCH, "italic"))
	_body.add_child(h)


func _reinforcements() -> void:
	var box := _section("Recruits" if session.phase == Session.Phase.PLANNING else "Starting armies", "reinforce")
	var left: int = session.income_left()
	var total: int = session.income_total()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var big := Style.label("%d" % left, 44, Style.CREAM if left > 0 else Style.GOOD, "display")
	h.add_child(big)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.add_child(Style.label("left to place of %d" % total, 18, Style.CREAM))
	if session.phase == Session.Phase.PLANNING:
		var b: Dictionary = session.income_breakdown()
		var parts := ["lands %d" % b["lands"]]
		if int(b["bloc"]) > 0:
			parts.append("connected %d" % b["bloc"])
		if int(b["regions"]) > 0:
			parts.append("regions %d" % b["regions"])
		if int(b.get("capital", 0)) > 0:
			parts.append("capital %d" % b["capital"])
		if int(b.get("levee", 0)) > 0:
			parts.append("levée %d" % b["levee"])
		if int(b["cards"]) > 0:
			parts.append("cards %d" % b["cards"])
		if int(b.get("cut", 0)) > 0:
			parts.append("(%d cut off pay nothing)" % b["cut"])
		v.add_child(Style.label(" + ".join(parts), 15, Style.MUTED))
	else:
		v.add_child(Style.label("each land takes up to 2 × (1 + your neighbors)", 15, Style.MUTED))
	h.add_child(v)
	box.add_child(h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var auto := Style.chip("Auto-place the rest", func():
		session.auto_deploy()
		Audio.sfx("place"), Style.PARCH, 15)
	auto.disabled = left <= 0
	row.add_child(auto)
	var clear := Style.chip("Clear", func(): session.clear_placements(), Style.MUTED, 15)
	clear.disabled = session.placed_total() == 0
	row.add_child(clear)
	box.add_child(row)


func _cards() -> void:
	var hand: PackedStringArray = session.hand()
	if hand.is_empty():
		return
	var box := _section("Cards  (%d/%d)" % [hand.size(), Cards.HAND_LIMIT])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var cashing: PackedStringArray = session.sheet().cash_set
	var marked := cashing.duplicate()
	for c in hand:
		var t := TextureRect.new()
		t.texture = Style.card_tex(c)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		t.custom_minimum_size = Vector2(44, 58)
		var i := marked.find(c)
		if i >= 0:
			marked.remove_at(i)
			t.modulate = Color(1.2, 1.1, 0.7)
		elif cashing.size() > 0:
			t.modulate = Color(0.55, 0.55, 0.6)
		t.tooltip_text = c.capitalize() + (" — matches anything" if c == "wild" else "")
		row.add_child(t)
	box.add_child(row)
	var best: PackedStringArray = session.best_set()
	if cashing.size() > 0:
		box.add_child(Style.chip("Trading a set for +%d armies  ·  undo" % session.set_value_now(), func():
			session.toggle_cash()
			Audio.sfx("card"), Style.GOLD, 16))
	elif best.size() == 3:
		box.add_child(Style.chip("Trade in a set for +%d armies" % session.set_value_now(), func():
			session.toggle_cash()
			Audio.sfx("cash"), Style.GOLD, 16))
	else:
		box.add_child(Style.label("Three of a kind or one of each makes a set.", 15, Style.MUTED, "italic"))


func _selected() -> void:
	var id: String = gs.selected
	if id == "":
		var hint := _section("Your lands")
		hint.add_child(_wrap(_hint_text(), 17, Style.PARCH))
		return
	var ts: Types.TerritoryState = session.world.get_territory(id)
	var td: Types.TerritoryDef = session.map.get_territory(id)
	var mine: bool = ts.owner == session.planner
	var box := _section(td.display_name, "flag")
	var region_txt := ""
	if td.region != "":
		region_txt = "%s (+%d if you hold all of it)" % [session.map.region_names.get(td.region, td.region), int(session.map.region_bonus.get(td.region, 0))]
	if region_txt != "":
		box.add_child(Style.label(region_txt, 15, Style.MUTED, "italic"))
	if not mine:
		var d: Dictionary = session.expected_defense(id)
		var owner_txt: String = "Empty land — anyone can walk in" if ts.owner == Types.UNOCCUPIED else "Held by %s: %s" % [session.name_of(ts.owner), Style.plural(int(d["now"]), "army", "armies")]
		box.add_child(_wrap(owner_txt, 17, Style.CREAM))
		if int(d["ceiling"]) > int(d["now"]):
			box.add_child(_wrap("They could reinforce it to %d before battle." % d["ceiling"], 16, Style.PARCH))
		if int(Income.home_split(ts)[1]) > 0:
			box.add_child(_wrap("%d of those hold the garrison and never leave." % int(Income.home_split(ts)[1]), 16, Style.PARCH))
		## Who of ours can hit it?
		for n in MapLib.neighbors(session.map, id):
			var ns: Types.TerritoryState = session.world.get_territory(n)
			if ns.owner == session.planner and session.phase == Session.Phase.PLANNING:
				box.add_child(_attack_row(n, id, true))
		return
	## own land
	var placed: int = session.placed_on(id)
	var cap: int = session.place_cap(id)
	var info := Style.plural(ts.armies, "army", "armies")
	if int(Income.home_split(ts)[1]) > 0:
		info += " + %d in the garrison" % int(Income.home_split(ts)[1])
	box.add_child(Style.label(info, 18, Style.CREAM, "bold"))
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 8)
	pr.add_child(Style.chip("  −  ", func(): gs.place(id, -1), Style.CREAM, 20))
	var q := Style.label("+%d" % placed, 24, Style.GOLD, "display")
	q.custom_minimum_size = Vector2(52, 0)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pr.add_child(q)
	pr.add_child(Style.chip("  +  ", func(): gs.place(id, 1), Style.CREAM, 20))
	pr.add_child(Style.label("room for %d here" % maxi(0, cap - placed), 15, Style.MUTED))
	box.add_child(pr)
	if session.phase != Session.Phase.PLANNING:
		return
	var sends: int = session.max_send(id)
	if sends > 0 or ts.garrison > 0:
		var note := "%d can march out" % sends
		note += " (the garrison of %d holds the land)" % int(Income.home_split(ts)[1])
		box.add_child(Style.label(note, 15, Style.MUTED, "italic"))
	for n in MapLib.neighbors(session.map, id):
		var ns: Types.TerritoryState = session.world.get_territory(n)
		if ns.owner == session.planner:
			box.add_child(_move_row(id, n))
		else:
			box.add_child(_attack_row(id, n, false))


func _hint_text() -> String:
	if session.phase == Session.Phase.OPENING:
		return "Click one of your lands to select it. Click it again (or press +) to add armies. Right-click takes one back."
	return "Click one of your lands to select it. Then click an enemy neighbor to attack, or drag from your land onto the target. Click your selected land again to add a recruit."


func _attack_row(from_id: String, to_id: String, from_enemy_view: bool) -> Control:
	var ns: Types.TerritoryState = session.world.get_territory(to_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var dot := _Dot.new()
	dot.pid = ns.owner
	dot.custom_minimum_size = Vector2(18, 18)
	row.add_child(dot)
	var name_txt: String = session.hex_name(from_id if from_enemy_view else to_id)
	var d: Dictionary = session.expected_defense(to_id)
	var lbl: String
	if from_enemy_view:
		lbl = "from %s" % name_txt
	else:
		lbl = "%s  %s" % [name_txt, "(empty)" if ns.owner == Types.UNOCCUPIED else str(d["now"])]
	var l := Style.label(lbl, 16, Style.CREAM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var idx: int = session.packet_index(from_id, to_id)
	if idx >= 0:
		var p: Types.Packet = session.sheet().packets[idx]
		row.add_child(Style.label("attacking with %d" % p.strength, 15, Style.GOLD, "bold"))
	else:
		var mx: int = session.max_attack(from_id, to_id)
		var b := Style.chip("Attack", func(): gs.order_attack(from_id, to_id), Style.CRIMSON.lightened(0.3), 15)
		b.disabled = mx < 1
		if mx >= 1:
			var o: Dictionary = session.odds(mx, int(d["now"]), to_id)
			b.text = "Attack · %s" % o["word"]
			b.add_theme_color_override("font_color", ODDS_COLOR.get(o["word"], Style.CREAM))
			b.tooltip_text = "With all %d who can march: %s against %d now" % [mx, o["word"], d["now"]]
		else:
			b.tooltip_text = session._cannot_send(from_id)
		row.add_child(b)
	return row


func _move_row(from_id: String, to_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var dot := _Dot.new()
	dot.pid = session.planner
	dot.custom_minimum_size = Vector2(18, 18)
	row.add_child(dot)
	var l := Style.label("%s  (yours)" % session.hex_name(to_id), 16, Style.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var r: Types.Regroup = session.sheet().regroup
	if r != null and r.from_id == from_id and r.to_id == to_id:
		row.add_child(Style.label("moving %d" % r.strength, 15, Style.GOLD, "bold"))
	elif session.map.maneuvers:
		row.add_child(Style.label("march after the battles", 13, Style.MUTED, "italic"))
	elif session.world.round > 1:
		var b := Style.chip("Move", func(): gs.order_move(from_id, to_id), Style.PARCH, 15)
		b.disabled = session.max_regroup(from_id) < 1
		b.tooltip_text = "One move per round, sealed like everything else."
		row.add_child(b)
	return row


func _orders() -> void:
	var s: Types.Sheet = session.sheet()
	var box := _section("Orders", "scroll")
	if s.packets.is_empty() and s.regroup == null:
		box.add_child(_wrap("No attacks yet. Holding everything is a legal plan — but land wins the war.", 16, Style.MUTED))
	var w: Types.World = session.projected_world()
	for i in s.packets.size():
		var p: Types.Packet = s.packets[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", Style.flat(Color(0.1, 0.07, 0.06, 0.85), Color(Style.CRIMSON, 0.6), 1, 6, 8))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		var top := HBoxContainer.new()
		var t := Style.label("%s  ➜  %s" % [session.hex_name(p.from_id), session.hex_name(p.to_id)], 18, Style.CREAM, "bold")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		top.add_child(t)
		var idx := i
		top.add_child(Style.chip("✕", func():
			session.remove_packet(idx)
			Audio.sfx("unplace"), Style.MUTED, 14))
		v.add_child(top)
		var mid := HBoxContainer.new()
		mid.add_theme_constant_override("separation", 6)
		mid.add_child(Style.chip(" − ", func(): session.set_packet_strength(idx, p.strength - 1), Style.CREAM, 17))
		var n := Style.label("%d" % p.strength, 22, Style.GOLD, "display")
		n.custom_minimum_size = Vector2(38, 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(n)
		mid.add_child(Style.chip(" + ", func(): session.set_packet_strength(idx, p.strength + 1), Style.CREAM, 17))
		mid.add_child(Style.chip("all", func(): session.set_packet_strength(idx, 999), Style.PARCH, 14))
		var d: Dictionary = session.expected_defense(p.to_id)
		var total_in := 0
		for raw in s.packets:
			if (raw as Types.Packet).to_id == p.to_id:
				total_in += (raw as Types.Packet).strength
		var o_now: Dictionary = session.odds(total_in, int(d["now"]), p.to_id)
		var ow := Style.label(o_now["word"], 18, ODDS_COLOR.get(o_now["word"], Style.CREAM), "bold")
		ow.tooltip_text = "Your %d against their %d as the map stands" % [total_in, d["now"]]
		mid.add_child(ow)
		v.add_child(mid)
		if int(d["ceiling"]) > int(d["now"]):
			var o_max: Dictionary = session.odds(total_in, int(d["ceiling"]), p.to_id)
			v.add_child(Style.label("if they reinforce to %d: %s" % [d["ceiling"], o_max["word"]], 14, Style.MUTED, "italic"))
		var left: int = w.get_territory(p.from_id).held()
		var home := Style.label("%s keeps %d at home" % [session.hex_name(p.from_id), left], 14, Style.CRIMSON.lightened(0.25) if left <= 1 else Style.MUTED)
		v.add_child(home)
		var sr := HBoxContainer.new()
		sr.add_theme_constant_override("separation", 6)
		if p.surge_to != "":
			sr.add_child(Style.label("then surge into %s" % session.hex_name(p.surge_to), 15, Style.GOLD, "italic"))
			sr.add_child(Style.chip("cancel surge", func(): session.set_surge(idx, ""), Style.MUTED, 13))
		else:
			var sb := Style.chip("Surge onward…", func(): gs.begin_surge_pick(idx), Style.PARCH, 13)
			sb.tooltip_text = "If this attack wins, everyone but 1 pushes on into a land next to %s. Surges go last." % session.hex_name(p.to_id)
			sr.add_child(sb)
		v.add_child(sr)
		box.add_child(card)
	if s.regroup != null:
		var card2 := PanelContainer.new()
		card2.add_theme_stylebox_override("panel", Style.flat(Color(0.06, 0.08, 0.1, 0.85), Color(Style.PARCH, 0.5), 1, 6, 8))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		card2.add_child(h)
		var r: Types.Regroup = s.regroup
		var t2 := Style.label("Move %s ➜ %s" % [session.hex_name(r.from_id), session.hex_name(r.to_id)], 17, Style.CREAM, "bold")
		t2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t2.clip_text = true
		h.add_child(t2)
		h.add_child(Style.chip(" − ", func(): session.set_regroup(r.from_id, r.to_id, r.strength - 1), Style.CREAM, 16))
		h.add_child(Style.label("%d" % r.strength, 20, Style.GOLD, "display"))
		h.add_child(Style.chip(" + ", func(): session.set_regroup(r.from_id, r.to_id, r.strength + 1), Style.CREAM, 16))
		h.add_child(Style.chip("✕", func(): session.clear_regroup(), Style.MUTED, 14))
		box.add_child(card2)


func _warnings() -> void:
	var ws: PackedStringArray = session.warnings()
	if session.error_text != "":
		ws.insert(0, session.error_text)
	for w in ws:
		var l := _wrap("⚠  " + w, 16, Style.WARN)
		_body.add_child(l)


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := Style.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	return l


class _Dot extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := ""

	func _draw() -> void:
		if pid == "":
			draw_arc(size * 0.5, 7.0, 0, TAU, 20, Style.PARCH, 1.5)
			return
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, 7.5, Style.seat_color(pid), Style.CREAM, 1.2)
