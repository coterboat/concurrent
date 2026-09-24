## The table: top bar, the map, the order sheet, and the overlays for each phase.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Session := preload("res://game/core/session.gd")
const Board := preload("res://game/board/map_board.gd")
const TopBar := preload("res://game/ui/top_bar.gd")
const OrdersPanel := preload("res://game/ui/orders_panel.gd")
const Cinema := preload("res://game/ui/cinema.gd")
const Recap := preload("res://game/ui/recap.gd")
const GameOver := preload("res://game/ui/game_over.gd")
const Advisor := preload("res://game/ui/advisor.gd")
const HowTo := preload("res://game/ui/howto_screen.gd")

var main: Control
var session: Node
var selected := ""
var surge_pick := -1

var top: PanelContainer
var board: Control
var panel: PanelContainer
var cinema: Control
var recap: Control
var game_over: Control
var advisor: Control
var map_area: Control
var legend: PanelContainer
var _legend_box: VBoxContainer
var _cover: Control
var _cover_box: VBoxContainer
var _modal: Control
var _loaded_map := ""
var _hover_tip: PanelContainer
var _hover_label: Label


func _ready() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	add_child(v)
	top = TopBar.new()
	top.session = session
	top.menu_pressed.connect(open_menu)
	top.help_pressed.connect(func(): _open_rules(0))
	v.add_child(top)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 0)
	v.add_child(h)
	map_area = Control.new()
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_area.clip_contents = true
	h.add_child(map_area)
	board = Board.new()
	board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	map_area.add_child(board)
	board.territory_clicked.connect(_on_click)
	board.drag_order.connect(_on_drag)
	board.empty_clicked.connect(func(): _select(""))
	board.territory_hovered.connect(_on_hover)
	_build_map_tools()
	advisor = Advisor.new()
	advisor.session = session
	advisor.gs = self
	map_area.add_child(advisor)
	cinema = Cinema.new()
	map_area.add_child(cinema)
	cinema.finished.connect(func(): session.cinema_done())
	panel = OrdersPanel.new()
	panel.session = session
	panel.gs = self
	h.add_child(panel)
	recap = Recap.new()
	recap.session = session
	recap.visible = false
	recap.continue_pressed.connect(func():
		recap.visible = false
		session.next_round())
	add_child(recap)
	game_over = GameOver.new()
	game_over.session = session
	game_over.visible = false
	game_over.again_pressed.connect(func():
		var cfg: Dictionary = session.config.duplicate(true)
		cfg["seed"] = 0
		main.start_game(cfg))
	game_over.menu_pressed.connect(func(): main.show_title())
	add_child(game_over)
	_cover = Control.new()
	_cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_cover.visible = false
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	session.changed.connect(_refresh)
	session.phase_changed.connect(_on_phase)
	Audio.ambience(true)


func _build_map_tools() -> void:
	var tools := VBoxContainer.new()
	tools.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	tools.offset_left = -64
	tools.offset_top = -170
	tools.offset_right = -14
	tools.offset_bottom = -14
	tools.add_theme_constant_override("separation", 6)
	map_area.add_child(tools)
	for spec in [["+", func(): board.zoom_at(board.size * 0.5, 1.25)], ["−", func(): board.zoom_at(board.size * 0.5, 0.8)], ["⤢", func(): board.reset_view()]]:
		var b := Style.chip(spec[0], spec[1], Style.CREAM, 22)
		b.custom_minimum_size = Vector2(48, 44)
		b.tooltip_text = {"+": "Zoom in (mouse wheel / pinch)", "−": "Zoom out", "⤢": "Show the whole map"}[spec[0]]
		tools.add_child(b)
	## region legend
	legend = PanelContainer.new()
	legend.add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.045, 0.08, 0.86), Color(Style.GOLD, 0.35), 1, 6, 10))
	legend.set_anchors_preset(PRESET_TOP_LEFT)
	legend.offset_left = 12
	legend.offset_top = 12
	legend.mouse_filter = Control.MOUSE_FILTER_PASS
	map_area.add_child(legend)
	_legend_box = VBoxContainer.new()
	_legend_box.add_theme_constant_override("separation", 2)
	legend.add_child(_legend_box)
	## hover card
	_hover_tip = PanelContainer.new()
	_hover_tip.add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.045, 0.08, 0.93), Color(Style.GOLD, 0.5), 1, 6, 10))
	_hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tip.visible = false
	_hover_label = Style.label("", 16, Style.CREAM)
	_hover_tip.add_child(_hover_label)
	map_area.add_child(_hover_tip)


# ================================================================ phases

func _on_phase(ph: int) -> void:
	if session.map != null and session.map.id != _loaded_map:
		board.load_map(session.map)
		_loaded_map = session.map.id
	_cover.visible = false
	recap.visible = false
	surge_pick = -1
	match ph:
		Session.Phase.OPENING, Session.Phase.PLANNING:
			_select("")
			Audio.music("plan")
			if session.is_last_round() and ph == Session.Phase.PLANNING and not session.conquest():
				board.float_text(_any_owned(), "", Style.GOLD)
		Session.Phase.PASS:
			_show_pass()
		Session.Phase.RESOLVING:
			_show_sealing()
		Session.Phase.CINEMA:
			_cover.visible = false
			cinema.play(session, board)
		Session.Phase.RECAP:
			Audio.music("plan")
			recap.show_round()
			_maybe_defeat_notice()
		Session.Phase.GAME_OVER:
			var won: bool = session.is_human(session.winner)
			var any_human := false
			for s in session.seats:
				if s["kind"] == "human":
					any_human = true
			Audio.music("victory" if (won or not any_human) else "defeat", 0.6, false)
			Audio.ambience(false)
			game_over.show_result()
	_refresh()


var _defeat_shown := false


func _maybe_defeat_notice() -> void:
	## The last human just fell: say so, and offer to watch or leave.
	if _defeat_shown or session.winner != "":
		return
	var fell: Array = []
	for e in session.events:
		if str(e.get("kind", "")) == "PlayerEliminated" and session.is_human(str(e["playerId"])):
			fell.append(session.name_of(str(e["playerId"])))
	if fell.is_empty() or not session.living_humans().is_empty():
		return
	_defeat_shown = true
	Audio.sfx("eliminated")
	_confirm("%s ha%s been defeated" % [" and ".join(fell), "s" if fell.size() == 1 else "ve"],
		"The commanders will fight on without you. Watch them finish the war, or leave the field.",
		[["Watch the rest", func(): pass], ["New game", func(): main.show_setup()], ["Main menu", func(): main.show_title()]])


func _any_owned() -> String:
	var mine := MapLib.player_territory_ids(session.world, session.planner)
	return mine[0] if mine.size() > 0 else ""


func _refresh() -> void:
	if session.world == null or board.art == null and session.map != null:
		if session.map != null and board.art == null:
			board.load_map(session.map)
			_loaded_map = session.map.id
	top.refresh()
	panel.refresh()
	advisor.refresh()
	_refresh_legend()
	var ph: int = session.phase
	var planning: bool = ph == Session.Phase.OPENING or ph == Session.Phase.PLANNING
	if planning:
		board.interactive = true
		board.viewer = session.planner
		board.world = session.projected_world()
		board.show_ceiling = bool(Settings.get_value("ceilings", true))
		board.ceiling_mult = 2 if ph == Session.Phase.OPENING else 1
		board.selected = selected
		board.placements = {}
		var src: Dictionary = session.opening.get(session.planner, {}) if ph == Session.Phase.OPENING else session.sheet().placements
		for k in src.keys():
			board.placements[k] = int(src[k])
		board.ghosts = session.ghosts if ph == Session.Phase.PLANNING else []
		board.orders = _my_arrows()
		board.targets = _targets()
		board.dimmed = {}
		board.battle = {}
		board.refresh()
	elif ph == Session.Phase.PASS or ph == Session.Phase.RESOLVING or ph == Session.Phase.RECAP or ph == Session.Phase.GAME_OVER:
		board.interactive = false
		board.viewer = ""
		board.world = session.world
		board.selected = ""
		board.targets = {}
		board.placements = {}
		board.orders = []
		board.ghosts = session.ghosts if ph != Session.Phase.GAME_OVER else []
		board.show_ceiling = false
		board.refresh()


func _my_arrows() -> Array:
	if session.phase != Session.Phase.PLANNING:
		return []
	var out: Array = []
	var s: Types.Sheet = session.sheet()
	for raw in s.packets:
		var p: Types.Packet = raw
		out.append({"from": p.from_id, "to": p.to_id, "strength": p.strength, "owner": session.planner, "surge": p.surge_to, "kind": "attack"})
	if s.regroup != null:
		out.append({"from": s.regroup.from_id, "to": s.regroup.to_id, "strength": s.regroup.strength, "owner": session.planner, "kind": "move"})
	return out


func _targets() -> Dictionary:
	var t := {}
	if session.phase != Session.Phase.PLANNING:
		return t
	if surge_pick >= 0 and surge_pick < session.sheet().packets.size():
		var p: Types.Packet = session.sheet().packets[surge_pick]
		for n in MapLib.neighbors(session.map, p.to_id):
			if n != p.from_id and session.world.get_territory(n).owner != session.planner:
				t[n] = true
		return t
	if selected == "" or session.world.get_territory(selected).owner != session.planner:
		return t
	if session.max_send(selected) < 1:
		return t
	for n in MapLib.neighbors(session.map, selected):
		if session.world.get_territory(n).owner != session.planner:
			t[n] = true
	return t


# ================================================================ map input

func _select(id: String) -> void:
	selected = id
	surge_pick = -1
	_refresh()


func _on_click(id: String, button: int) -> void:
	var ph: int = session.phase
	if ph != Session.Phase.OPENING and ph != Session.Phase.PLANNING:
		return
	var ts: Types.TerritoryState = session.world.get_territory(id)
	if surge_pick >= 0:
		var err: String = session.set_surge(surge_pick, id)
		if err != "":
			_toast(err)
			Audio.sfx("error")
		else:
			Audio.sfx("surge", -6.0)
		surge_pick = -1
		_refresh()
		return
	if button == MOUSE_BUTTON_RIGHT:
		if ts.owner == session.planner:
			place(id, -1)
		return
	if ts.owner == session.planner:
		if selected == id:
			place(id, 1)
		else:
			_select(id)
			Audio.sfx("click", -8.0)
		return
	## an enemy or empty land
	if ph == Session.Phase.PLANNING and selected != "" and session.world.get_territory(selected).owner == session.planner and session.map.is_adjacent(selected, id):
		order_attack(selected, id)
		return
	_select(id)


func _on_drag(from_id: String, to_id: String) -> void:
	if session.phase != Session.Phase.PLANNING:
		return
	var a: Types.TerritoryState = session.world.get_territory(from_id)
	if a.owner != session.planner:
		return
	if not session.map.is_adjacent(from_id, to_id):
		_toast("%s does not border %s." % [session.hex_name(to_id), session.hex_name(from_id)])
		Audio.sfx("error")
		return
	if session.world.get_territory(to_id).owner == session.planner:
		order_move(from_id, to_id)
	else:
		order_attack(from_id, to_id)


func _on_hover(id: String) -> void:
	if id == "" or session.world == null:
		_hover_tip.visible = false
		return
	var w: Types.World = board.world
	var ts: Types.TerritoryState = w.get_territory(id)
	var td: Types.TerritoryDef = session.map.get_territory(id)
	var lines: Array = [td.display_name]
	if td.region != "":
		lines.append("%s  (+%d)" % [session.map.region_names.get(td.region, td.region), int(session.map.region_bonus.get(td.region, 0))])
	if ts.owner == Types.UNOCCUPIED:
		lines.append("Empty")
	else:
		lines.append("%s · %d armies%s" % [session.name_of(ts.owner), ts.held(), (" (%d dug in)" % ts.garrison) if ts.garrison > 0 else ""])
	_hover_label.text = "\n".join(lines)
	_hover_tip.visible = true
	_hover_tip.reset_size()
	var p: Vector2 = board.anchor(id) + Vector2(26, -_hover_tip.size.y - 20)
	p.x = clampf(p.x, 4, map_area.size.x - _hover_tip.size.x - 4)
	p.y = clampf(p.y, 4, map_area.size.y - _hover_tip.size.y - 4)
	_hover_tip.position = p


# ================================================================ orders (called by the panel too)

func place(id: String, delta: int) -> void:
	var err: String = session.add_place(id, delta)
	if err != "":
		_toast(err)
		Audio.sfx("error")
	else:
		Audio.sfx("place" if delta > 0 else "unplace")
	if selected != id:
		selected = id
		_refresh()


func order_attack(from_id: String, to_id: String) -> void:
	var err: String = session.set_attack(from_id, to_id)
	if err != "":
		_toast(err)
		Audio.sfx("error")
		return
	Audio.sfx("order_attack")
	selected = from_id
	_refresh()


func order_move(from_id: String, to_id: String) -> void:
	var err: String = session.set_regroup(from_id, to_id)
	if err != "":
		_toast(err)
		Audio.sfx("error")
		return
	Audio.sfx("order_move")
	_refresh()


func begin_surge_pick(i: int) -> void:
	surge_pick = i
	var p: Types.Packet = session.sheet().packets[i]
	_toast("Click a land next to %s to surge into it. (Esc cancels)" % session.hex_name(p.to_id))
	_refresh()


func try_seal() -> void:
	if session.phase != Session.Phase.PLANNING and session.phase != Session.Phase.OPENING:
		return
	if session.income_left() > 0:
		_confirm("%d reinforcement%s still unplaced" % [session.income_left(), "" if session.income_left() == 1 else "s"],
			"Anything you don't place is lost.",
			[["Place them for me", func():
				session.auto_deploy()
				_seal()], ["Seal anyway", func(): _seal()], ["Go back", func(): pass]])
		return
	_seal()


func _seal() -> void:
	var err: String = session.lock()
	if err != "":
		_toast(err)
		Audio.sfx("error")
		return
	Audio.sfx("seal")
	selected = ""


# ================================================================ overlays

func _clear_cover() -> void:
	for c in _cover.get_children():
		c.queue_free()


func _show_pass() -> void:
	_clear_cover()
	_cover.visible = true
	var bg := TextureRect.new()
	bg.texture = Style.tex("res://assets/tex/wood.webp")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.modulate = Color(0.4, 0.37, 0.35)
	_cover.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_cover.add_child(c)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.panel_box(30))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var pid: String = session.pass_to
	var pic := TextureRect.new()
	pic.texture = Style.portrait(str(session.seat(pid).get("portrait", "player")))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(0, 180)
	v.add_child(pic)
	var t := Style.label("Pass the computer to %s" % session.name_of(pid), 40, Style.seat_color(pid).lightened(0.4), "display")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var what := "place your starting armies" if int(session.get_meta("after_pass", 0)) == Session.Phase.OPENING else "write your orders for round %d" % session.world.round
	var sub := Style.label("Everyone else, look away. %s, it's your turn to %s." % [session.name_of(pid), what], 20, Style.PARCH, "italic")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(560, 0)
	v.add_child(sub)
	var b := Style.button("I'm %s — show my map" % session.name_of(pid), func():
		Audio.sfx("pass")
		session.seated(), 0, 24)
	b.custom_minimum_size = Vector2(0, 64)
	v.add_child(b)


func _show_sealing() -> void:
	_clear_cover()
	_cover.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.6)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_cover.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_cover.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	var seal := TextureRect.new()
	seal.texture = Style.icon("seal")
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.custom_minimum_size = Vector2(150, 150)
	seal.pivot_offset = Vector2(75, 75)
	v.add_child(seal)
	var t := Style.label("Orders sealed", 44, Style.CREAM, "display")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := Style.label("The other commanders are writing theirs…", 20, Style.PARCH, "italic")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	seal.scale = Vector2(1.6, 1.6)
	seal.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(seal, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(seal, "modulate:a", 1.0, 0.15)


func _toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.flat(Color(0.08, 0.05, 0.04, 0.95), Style.WARN, 1, 6, 12))
	var l := Style.label(text, 18, Style.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_area.add_child(p)
	p.reset_size()
	var w: float = minf(p.size.x, map_area.size.x - 40)
	p.position = Vector2((map_area.size.x - w) * 0.5, map_area.size.y - p.size.y - 90)
	var tw := p.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _confirm(title: String, body: String, choices: Array) -> void:
	if _modal != null:
		_modal.queue_free()
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_modal.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_modal.add_child(c)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.panel_box(26))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(Style.label(title, 30, Style.CREAM, "display"))
	if body != "":
		var b := Style.label(body, 19, Style.PARCH)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(460, 0)
		v.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var modal := _modal
	for ch in choices:
		var cb: Callable = ch[1]
		row.add_child(Style.button(str(ch[0]), func():
			modal.queue_free()
			if _modal == modal:
				_modal = null
			cb.call(), 0, 19))


func open_menu() -> void:
	var saved_note := "Your campaign is saved after every round."
	_confirm("Paused", saved_note, [
		["Resume", func(): pass],
		["How to play", func(): _open_rules(0)],
		["Settings", func(): main.open_settings()],
		["Save & quit to title", func(): main.show_title()],
		["Quit game", func(): get_tree().quit()],
	])


func _open_rules(page: int) -> void:
	var h: Control = HowTo.new()
	h.main = null
	h.overlay = true
	h.start_page = page
	add_child(h)


func _refresh_legend() -> void:
	for c in _legend_box.get_children():
		c.queue_free()
	if session.map == null or session.map.region_bonus.is_empty():
		legend.visible = false
		return
	legend.visible = true
	_legend_box.add_child(Style.label("Regions", 17, Style.GOLD, "display"))
	var keys: Array = session.map.region_bonus.keys()
	keys.sort()
	for r in keys:
		var members := MapLib.region_members(session.map, str(r))
		var holder := ""
		var mine := 0
		for pid in MapLib.living_player_ids(session.world):
			if MapLib.holds_region(session.world, session.map, pid, str(r)):
				holder = pid
		if session.planner != "":
			for m in members:
				if session.world.get_territory(m).owner == session.planner:
					mine += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var dot := _Dot.new()
		dot.pid = holder
		dot.custom_minimum_size = Vector2(14, 14)
		row.add_child(dot)
		var txt := "%s  +%d" % [session.map.region_names.get(r, r), int(session.map.region_bonus[r])]
		var l := Style.label(txt, 15, Style.CREAM if holder == "" else Style.seat_color(holder).lightened(0.45), "bold")
		row.add_child(l)
		if (session.phase == Session.Phase.PLANNING or session.phase == Session.Phase.OPENING) and holder == "":
			row.add_child(Style.label("you %d/%d" % [mine, members.size()], 13, Style.MUTED))
		_legend_box.add_child(row)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if _modal != null:
			_modal.queue_free()
			_modal = null
		elif surge_pick >= 0:
			surge_pick = -1
			_refresh()
		elif selected != "":
			_select("")
		elif session.phase != Session.Phase.CINEMA:
			open_menu()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and (event.meta_pressed or event.ctrl_pressed):
		try_seal()
		get_viewport().set_input_as_handled()


class _Dot extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := ""

	func _draw() -> void:
		if pid == "":
			draw_arc(size * 0.5, 5.5, 0, TAU, 16, Style.MUTED, 1.2)
			return
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, 6.0, Style.seat_color(pid), Style.CREAM, 1.0)
