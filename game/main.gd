extends Control

const Palette := preload("res://game/palette.gd")
const SessionScript := preload("res://game/match_session.gd")
const MapViewScript := preload("res://game/map_view.gd")
const SheetScript := preload("res://game/sheet_ui.gd")
const Income := preload("res://engine/income.gd")
const Types := preload("res://engine/types.gd")

var session: Node
var map_view: Control
var sheet: PanelContainer
var hud: Label
var title: Control
var hotseat: Control
var cinema: Control
var recap: Control
var over: Control
var cinema_caption: Label
var recap_copy: Label
var map_pick: OptionButton


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	session = SessionScript.new()
	add_child(session)
	session.changed.connect(_refresh)
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Palette.CREAM)
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.custom_minimum_size = Vector2(0, 40)
	root.add_child(hud)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	root.add_child(row)

	map_view = MapViewScript.new()
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.hex_clicked.connect(_on_hex)
	row.add_child(map_view)

	sheet = SheetScript.new()
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.lock_pressed.connect(func(): session.lock())
	sheet.hold_pressed.connect(func(): session.hold_and_lock())
	sheet.place_on.connect(func(id, d): session.add_place_on(id, d))
	sheet.send_on.connect(func(id, d): session.nudge_send(id, d))
	sheet.attack_on.connect(func(f, t): session.attack_to(f, t))
	sheet.regroup_on.connect(func(f, t): session.regroup_to(f, t))
	sheet.packet_nudge.connect(func(i, d): session.nudge_packet(i, d))
	sheet.packet_removed.connect(func(i): session.remove_packet_at(i))
	row.add_child(sheet)

	title = _overlay()
	var tbox := VBoxContainer.new()
	tbox.add_theme_constant_override("separation", 16)
	tbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_child(tbox)
	tbox.set_anchors_preset(PRESET_FULL_RECT)
	var tt := Label.new()
	tt.text = "CONCURRENT"
	tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tt.add_theme_font_size_override("font_size", 48)
	tt.add_theme_color_override("font_color", Palette.CREAM)
	tbox.add_child(tt)
	var sub := Label.new()
	sub.text = "everyone commits  ·  attackers leave home empty"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Palette.RED)
	tbox.add_child(sub)
	map_pick = OptionButton.new()
	map_pick.custom_minimum_size = Vector2(320, 40)
	map_pick.add_item("The Isthmus  ·  7 lands  ·  5 rounds")
	map_pick.add_item("The Known World  ·  24 lands  ·  8 rounds")
	map_pick.selected = 0
	tbox.add_child(map_pick)
	tbox.add_child(_big_btn("Hotseat — you and him", func(): session.new_game(false, 0, false, _map_path())))
	tbox.add_child(_big_btn("Teach round 1 — sheets open", func(): session.new_game(false, 0, true, _map_path())))
	tbox.add_child(_big_btn("You vs Monkey", func(): session.new_game(true, 0, false, _map_path())))
	var hint := Label.new()
	hint.text = "Isthmus is the knife-fight. Known World is the golden globe. Neutral sits on the choke. Esc quits."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Palette.MUTED)
	tbox.add_child(hint)

	hotseat = _overlay()
	hotseat.set_anchor(SIDE_LEFT, 0.58)
	var hbox := VBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 18)
	hotseat.add_child(hbox)
	hbox.set_anchors_preset(PRESET_FULL_RECT)
	var hl := Label.new()
	hl.name = "Copy"
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.add_theme_font_size_override("font_size", 32)
	hl.add_theme_color_override("font_color", Palette.CREAM)
	hbox.add_child(hl)
	var hm := Label.new()
	hm.name = "Hint"
	hm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hm.add_theme_color_override("font_color", Palette.MUTED)
	hm.text = "The map stays. The sheet is hidden."
	hbox.add_child(hm)
	hbox.add_child(_big_btn("Seated", func(): session.seated()))

	cinema = _overlay()
	cinema.color = Color(0.02, 0.03, 0.05, 0.35)
	var cbox := VBoxContainer.new()
	cbox.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	cbox.offset_top = -160
	cbox.offset_left = 40
	cbox.offset_right = -40
	cbox.offset_bottom = -20
	cinema.add_child(cbox)
	cinema_caption = Label.new()
	cinema_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cinema_caption.add_theme_font_size_override("font_size", 22)
	cinema_caption.add_theme_color_override("font_color", Palette.CREAM)
	cbox.add_child(cinema_caption)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 12)
	cbox.add_child(crow)
	crow.add_child(_big_btn("Next  (Space)", func(): session.cinema_next()))
	crow.add_child(_big_btn("Skip cinema", func(): session.cinema_skip()))
	cinema.gui_input.connect(_cinema_click)

	recap = _overlay()
	recap.color = Color(0.02, 0.03, 0.06, 0.82)
	var rbox := VBoxContainer.new()
	rbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rbox.add_theme_constant_override("separation", 14)
	recap.add_child(rbox)
	rbox.set_anchors_preset(PRESET_FULL_RECT)
	rbox.offset_left = 80
	rbox.offset_right = -80
	var rt := Label.new()
	rt.name = "Title"
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rt.add_theme_font_size_override("font_size", 32)
	rt.add_theme_color_override("font_color", Palette.CREAM)
	rbox.add_child(rt)
	recap_copy = Label.new()
	recap_copy.name = "Copy"
	recap_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	recap_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recap_copy.add_theme_font_size_override("font_size", 20)
	recap_copy.add_theme_color_override("font_color", Palette.CREAM)
	rbox.add_child(recap_copy)
	rbox.add_child(_big_btn("Continue  (Space)", func(): session.cinema_next()))
	recap.gui_input.connect(_cinema_click)

	over = _overlay()
	var obox := VBoxContainer.new()
	obox.alignment = BoxContainer.ALIGNMENT_CENTER
	obox.add_theme_constant_override("separation", 16)
	over.add_child(obox)
	obox.set_anchors_preset(PRESET_FULL_RECT)
	var ol := Label.new()
	ol.name = "Copy"
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ol.add_theme_font_size_override("font_size", 36)
	ol.add_theme_color_override("font_color", Palette.CREAM)
	obox.add_child(ol)
	obox.add_child(_big_btn("New hotseat", func(): session.new_game(false, 0, false, _map_path())))
	obox.add_child(_big_btn("Teach round 1", func(): session.new_game(false, 0, true, _map_path())))
	obox.add_child(_big_btn("New vs Monkey", func(): session.new_game(true, 0, false, _map_path())))


func _overlay() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.03, 0.06, 0.92)
	r.set_anchors_preset(PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(r)
	return r


func _big_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 48)
	b.pressed.connect(cb)
	return b


func _on_hex(id: String, button_index: int = MOUSE_BUTTON_LEFT) -> void:
	if button_index == MOUSE_BUTTON_RIGHT:
		session.add_place_on(id, -1)
	else:
		session.select_hex(id)


func _cinema_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		session.cinema_next()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if session.phase == SessionScript.Phase.TITLE:
			get_tree().quit()
		elif session.phase == SessionScript.Phase.CINEMA or session.phase == SessionScript.Phase.RECAP:
			session.cinema_next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and (session.phase == SessionScript.Phase.CINEMA or session.phase == SessionScript.Phase.RECAP):
		session.cinema_next()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var ph: int = session.phase
	title.visible = ph == SessionScript.Phase.TITLE
	hotseat.visible = ph == SessionScript.Phase.HOTSEAT
	cinema.visible = ph == SessionScript.Phase.CINEMA
	recap.visible = ph == SessionScript.Phase.RECAP
	over.visible = ph == SessionScript.Phase.GAME_OVER
	if session.world != null and session.map != null:
		var reinforce: bool = ph == SessionScript.Phase.OPENING or ph == SessionScript.Phase.PLANNING
		map_view.set_state(
			session.map,
			session.view_world(),
			session.planner if ph != SessionScript.Phase.HOTSEAT else "",
			session.selected,
			session.last_packets,
			session.cinema_highlights() if ph == SessionScript.Phase.CINEMA else PackedStringArray(),
			reinforce
		)
	sheet.refresh(session)
	hud.text = _hud_text()
	if ph == SessionScript.Phase.HOTSEAT:
		_set_named_label(hotseat, "Copy", "Hand the Mac to %s" % session.hotseat_for.capitalize())
	if ph == SessionScript.Phase.CINEMA:
		cinema_caption.text = session.cinema_caption()
	if ph == SessionScript.Phase.RECAP:
		_set_named_label(recap, "Title", session.recap_title())
		recap_copy.text = "\n".join(session.recap_lines())
	if ph == SessionScript.Phase.GAME_OVER:
		_set_named_label(over, "Copy", "Winner: %s\nmatch written to user://last_match.json\ntelemetry appended to user://telemetry.jsonl" % session.winner)


func _set_named_label(root: Node, n: String, text: String) -> void:
	var l := _find_label(root, n)
	if l:
		l.text = text


func _find_label(n: Node, want: String) -> Label:
	if n is Label and n.name == want:
		return n
	for c in n.get_children():
		var f := _find_label(c, want)
		if f:
			return f
	return null


func _map_path() -> String:
	if map_pick != null and map_pick.selected == 1:
		return "res://maps/known24.json"
	return "res://maps/knife7.json"


func _hud_text() -> String:
	if session.world == null:
		return "CONCURRENT"
	var w = session.view_world()
	var r: int = 0
	var b: int = 0
	for id in session.map.territory_ids():
		var ts = w.get_territory(id)
		if ts.owner == "red":
			r += 1
		elif ts.owner == "blue":
			b += 1
	var score_r: int = Income.score_of(w, session.map, "red")
	var score_b: int = Income.score_of(w, session.map, "blue")
	var teach_bit := "    TEACHING" if session.teach and session.world.round <= 1 else ""
	var Setup := preload("res://engine/setup.gd")
	var max_r: int = Setup.rounds_for(session.map)
	var title_n: String = session.map.display_name
	return "%s   round %s / %s    red %s hex (score %s)    blue %s hex (score %s)    Neutral is a doorstop%s" % [title_n, w.round, max_r, r, score_r, b, score_b, teach_bit]
