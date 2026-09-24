## Order pad: a +/− row per owned hex. Lock stays on screen.
extends PanelContainer

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Combat := preload("res://engine/combat.gd")
const Palette := preload("res://game/palette.gd")
const Session := preload("res://game/match_session.gd")

signal lock_pressed
signal hold_pressed
signal place_on(terr_id: String, delta: int)
signal send_on(from_id: String, delta: int)
signal attack_on(from_id: String, to_id: String)
signal regroup_on(from_id: String, to_id: String)
signal packet_nudge(index: int, delta: int)
signal packet_removed(index: int)

var _title: Label
var _hint: Label
var _list: VBoxContainer
var _packets: VBoxContainer
var _err: Label
var _lock: Button
var _hold: Button
var _plus_tex: Texture2D
var _minus_tex: Texture2D
var _lock_tex: Texture2D
var _built := false
var _session: Node


func _ready() -> void:
	custom_minimum_size = Vector2(440, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_plus_tex = _load_tex("res://game/ui/plus.png")
	_minus_tex = _load_tex("res://game/ui/minus.png")
	_lock_tex = _load_tex("res://game/ui/lock.png")
	var panel_tex: Texture2D = _load_tex("res://game/ui/panel.png")
	if panel_tex:
		var sb := StyleBoxTexture.new()
		sb.texture = panel_tex
		sb.texture_margin_left = 48
		sb.texture_margin_top = 48
		sb.texture_margin_right = 48
		sb.texture_margin_bottom = 48
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		sb.content_margin_top = 18
		sb.content_margin_bottom = 18
		add_theme_stylebox_override("panel", sb)
	else:
		var fb := StyleBoxFlat.new()
		fb.bg_color = Palette.PANEL
		fb.content_margin_left = 16
		fb.content_margin_right = 16
		fb.content_margin_top = 16
		fb.content_margin_bottom = 16
		add_theme_stylebox_override("panel", fb)
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	_title = _lab(20, Palette.CREAM)
	root.add_child(_title)
	_hint = _lab(13, Palette.MUTED)
	root.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	scroll.add_child(inner)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	inner.add_child(_list)
	_packets = VBoxContainer.new()
	_packets.add_theme_constant_override("separation", 4)
	inner.add_child(_packets)
	_err = _lab(14, Palette.RED)
	_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_err)
	_hold = _chip("HOLD")
	_hold.pressed.connect(func(): hold_pressed.emit())
	root.add_child(_hold)
	_lock = Button.new()
	_lock.text = "  LOCK ORDERS"
	_lock.custom_minimum_size = Vector2(0, 64)
	_lock.size_flags_vertical = Control.SIZE_SHRINK_END
	_lock.add_theme_font_size_override("font_size", 20)
	_lock.add_theme_color_override("font_color", Palette.CREAM)
	if _lock_tex:
		_lock.icon = _lock_tex
		_lock.expand_icon = true
		_lock.add_theme_constant_override("icon_max_width", 40)
	_lock.pressed.connect(func(): lock_pressed.emit())
	root.add_child(_lock)
	_built = true


func refresh(session: Node) -> void:
	if not _built:
		return
	_session = session
	var ph: int = session.phase
	var planning: bool = ph == Session.Phase.OPENING or ph == Session.Phase.PLANNING
	visible = planning
	if not planning:
		return
	var pid: String = session.planner
	if ph == Session.Phase.OPENING:
		_title.text = "%s  opening   pool left %s" % [pid.capitalize(), session.pool_left()]
		_hint.text = "Click your land, or + / − here. Cap = 1 + friendly neighbors."
	else:
		_title.text = "%s  round %s   income left %s" % [pid.capitalize(), session.world.round, session.income_left()]
		_hint.text = "Held land digs in. Dug-in hexes can send every soldier. Round 1 walks queued place only."
	if session.error_text != "":
		_err.text = session.error_text
		_err.add_theme_color_override("font_color", Palette.RED)
	else:
		_err.text = str(session.status_text)
		_err.add_theme_color_override("font_color", Palette.MUTED)
	call_deferred("_rebuild_lists")


func _rebuild_lists() -> void:
	if _session == null or not is_inside_tree():
		return
	_rebuild_hexes(_session)
	_rebuild_packets(_session)


func _clear(node: Node) -> void:
	while node.get_child_count() > 0:
		var c: Node = node.get_child(0)
		node.remove_child(c)
		c.free()


func _rebuild_hexes(session: Node) -> void:
	_clear(_list)
	if session.world == null:
		return
	var owned: PackedStringArray = MapLib.player_territory_ids(session.world, session.planner)
	for terr_id in owned:
		_list.add_child(_hex_card(session, terr_id))


func _hex_card(session: Node, terr_id: String) -> Control:
	var ts: Types.TerritoryState = session.world.get_territory(terr_id)
	var t: Types.TerritoryDef = session.map.get_territory(terr_id)
	var name: String = t.display_name if t else terr_id
	var cap: int = Income.cap_of(session.world, session.map, terr_id)
	var queued := 0
	if session.phase == Session.Phase.OPENING:
		queued = int(session.opening[session.planner].get(terr_id, 0))
	else:
		queued = int(session.current_sheet().placements.get(terr_id, 0))
	var shown: int = session.display_armies(terr_id)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	var selected: bool = session.selected == terr_id
	var head := Label.new()
	var dug: int = 0
	if session.has_method("display_garrison"):
		dug = session.display_garrison(terr_id)
	if dug > 0:
		head.text = "%s%s    %s on map    dug %s    cap %s" % [name, "  ◀" if selected else "", shown, dug, cap]
	else:
		head.text = "%s%s    %s on map    cap %s" % [name, "  ◀" if selected else "", shown, cap]
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Palette.CREAM)
	head.clip_text = true
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_icon_btn(_minus_tex, func(): place_on.emit(terr_id, -1)))
	var qty := Label.new()
	qty.text = "+%s" % queued
	qty.custom_minimum_size = Vector2(48, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty.add_theme_font_size_override("font_size", 22)
	qty.add_theme_color_override("font_color", Palette.CREAM)
	row.add_child(qty)
	row.add_child(_icon_btn(_plus_tex, func(): place_on.emit(terr_id, 1)))
	var cap_l := Label.new()
	cap_l.text = "place"
	cap_l.add_theme_color_override("font_color", Palette.MUTED)
	row.add_child(cap_l)
	box.add_child(row)
	if session.phase == Session.Phase.PLANNING:
		var mx: int = session.send_cap(terr_id)
		if mx >= 1:
			var send_row := HBoxContainer.new()
			send_row.add_theme_constant_override("separation", 8)
			send_row.add_child(_muted("send"))
			send_row.add_child(_icon_btn(_minus_tex, func(): send_on.emit(terr_id, -1)))
			var send_l := Label.new()
			send_l.text = "%s / %s" % [session.send_for(terr_id), mx]
			send_l.custom_minimum_size = Vector2(64, 0)
			send_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			send_l.add_theme_font_size_override("font_size", 20)
			send_l.add_theme_color_override("font_color", Palette.CREAM)
			send_row.add_child(send_l)
			send_row.add_child(_icon_btn(_plus_tex, func(): send_on.emit(terr_id, 1)))
			var keep_l := "garrison holds" if dug >= 1 else "leave 1"
			send_row.add_child(_muted(keep_l))
			box.add_child(send_row)
		var attacks := HFlowContainer.new()
		attacks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		attacks.add_theme_constant_override("h_separation", 6)
		attacks.add_theme_constant_override("v_separation", 6)
		for n in MapLib.neighbors(session.map, terr_id):
			var nts: Types.TerritoryState = session.world.get_territory(n)
			if nts == null:
				continue
			var nt: Types.TerritoryDef = session.map.get_territory(n)
			var short: String = nt.display_name if nt else n
			var from_id := terr_id
			var to_id := n
			if nts.owner == session.planner:
				var mb := _chip("move %s" % short)
				mb.pressed.connect(func(): regroup_on.emit(from_id, to_id))
				attacks.add_child(mb)
				continue
			var odds := "empty"
			if nts.armies > 0 and nts.owner != Types.UNOCCUPIED:
				odds = Combat.odds_word(maxi(1, mini(session.send_for(terr_id), session.max_send_from(terr_id))), nts.armies)
			var b := _chip("atk %s · %s" % [short, odds])
			b.pressed.connect(func(): attack_on.emit(from_id, to_id))
			if session.max_send_from(from_id) >= 1:
				attacks.add_child(b)
		if attacks.get_child_count() > 0:
			box.add_child(attacks)
	var sep := HSeparator.new()
	box.add_child(sep)
	return box


func _rebuild_packets(session: Node) -> void:
	_clear(_packets)
	if session.phase != Session.Phase.PLANNING:
		return
	var sheet: Types.Sheet = session.current_sheet()
	if sheet.regroup != null:
		_packets.add_child(_muted("regroup %s → %s  %s" % [sheet.regroup.from_id, sheet.regroup.to_id, sheet.regroup.strength]))
	var i := 0
	for raw in sheet.packets:
		var p: Types.Packet = raw
		var left: int = session.origin_will_remain(p.from_id)
		var from_n: String = _hex_name(session, p.from_id)
		var to_n: String = _hex_name(session, p.to_id)
		var line := "%s → %s   send %s" % [from_n, to_n, p.strength]
		if p.surge_to != "":
			line += "  surge %s" % _hex_name(session, p.surge_to)
		if left <= 0:
			line += "   garrison holds" if session.display_garrison(p.from_id) >= 1 else "   sits at %s" % left
		elif left == 1:
			line += "   sits at %s" % left
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = false
		l.custom_minimum_size = Vector2(180, 28)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Palette.RED if left <= 1 else Palette.CREAM)
		row.add_child(l)
		var idx := i
		row.add_child(_icon_btn(_minus_tex, func(): packet_nudge.emit(idx, -1)))
		row.add_child(_icon_btn(_plus_tex, func(): packet_nudge.emit(idx, 1)))
		var rm := _chip("x")
		rm.pressed.connect(func(): packet_removed.emit(idx))
		row.add_child(rm)
		_packets.add_child(row)
		i += 1


func _icon_btn(tex: Texture2D, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(48, 48)
	b.flat = true
	if tex:
		b.icon = tex
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 44)
	else:
		b.text = "+"
	b.pressed.connect(cb)
	return b


func _chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = false
	b.custom_minimum_size = Vector2(108, 32)
	b.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	sb.border_color = Palette.CREAM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", Palette.CREAM)
	return b


func _load_tex(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _lab(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _muted(text: String) -> Label:
	return _lab(13, Palette.MUTED)


func _hex_name(session: Node, terr_id: String) -> String:
	var t = session.map.get_territory(terr_id)
	return t.display_name if t else terr_id
