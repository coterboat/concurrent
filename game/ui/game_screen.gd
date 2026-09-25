## The war table: full-bleed map, commanders top-right, the command bar below,
## floating cards on the map, and the battlefield for the fights that matter.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Session := preload("res://game/core/session.gd")
const Counsel := preload("res://game/core/counsel.gd")
const Lines := preload("res://game/core/lines.gd")
const Board := preload("res://game/board/map_board.gd")
const CommandBar := preload("res://game/ui/command_bar.gd")
const Roster := preload("res://game/ui/roster.gd")
const LandCard := preload("res://game/ui/land_card.gd")
const OrderCard := preload("res://game/ui/order_card.gd")
const OrdersPanel := preload("res://game/ui/orders_panel.gd")
const Cinema := preload("res://game/ui/cinema.gd")
const Theater := preload("res://game/ui/battle_theater.gd")
const Recap := preload("res://game/ui/recap.gd")
const GameOver := preload("res://game/ui/game_over.gd")
const Intro := preload("res://game/ui/intro.gd")
const PlanDialog := preload("res://game/ui/plan_dialog.gd")
const HowTo := preload("res://game/ui/howto_screen.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")

const BAR := 156.0
const TOP := 84.0

var main: Control
var session: Node
var selected := ""
var surge_pick := -1
var log_lines: Array = [] ## [text, color]

var board: Control
var bar: Control
var roster: Control
var cinema: Control
var theater: Control
var recap: Control
var game_over: Control
var land_card: PanelContainer
var order_card: PanelContainer
var drawer: PanelContainer
var intro: Control
var _plate_map: Label
var _plate_round: Label
var _plate_phase: Label
var _cover: Control
var _modal: Control
var _hover_tip: PanelContainer
var _hover_label: Label
var _loaded_map := ""
var _order_focus := ["", ""]
var _spoken := {} ## advisor lines already said: key -> round
var _intro_done := false
var _defeat_shown := false
var _last_place := ""
var _pre_regions := {}


func _ready() -> void:
	board = Board.new()
	board.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	board.pad_top = TOP
	board.pad_bottom = BAR + 4
	add_child(board)
	board.territory_clicked.connect(_on_click)
	board.drag_order.connect(_on_drag)
	board.empty_clicked.connect(func(): select(""))
	board.territory_hovered.connect(_on_hover)
	board.arrow_clicked.connect(func(a, b): edit_order(a, b))
	board.set_view_mode(int(Settings.get_value("map_view", 0)))
	_build_plate()
	roster = Roster.new()
	roster.session = session
	roster.set_anchors_preset(PRESET_TOP_RIGHT)
	roster.offset_right = -12
	roster.offset_top = 12
	roster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	roster.hovered.connect(_on_roster_hover)
	add_child(roster)
	_build_zoom()
	_hover_tip = PanelContainer.new()
	_hover_tip.add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.045, 0.08, 0.93), Color(Style.GOLD, 0.5), 1, 6, 10))
	_hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tip.visible = false
	_hover_label = Style.label("", 16, Style.CREAM)
	_hover_tip.add_child(_hover_label)
	add_child(_hover_tip)
	land_card = LandCard.new()
	land_card.session = session
	land_card.gs = self
	add_child(land_card)
	order_card = OrderCard.new()
	order_card.session = session
	order_card.gs = self
	add_child(order_card)
	drawer = OrdersPanel.new()
	drawer.session = session
	drawer.gs = self
	drawer.drawer = true
	drawer.set_anchors_preset(PRESET_RIGHT_WIDE)
	drawer.offset_top = TOP + 190
	drawer.offset_bottom = -BAR - 10
	drawer.offset_left = -440
	drawer.offset_right = -12
	drawer.visible = false
	add_child(drawer)
	cinema = Cinema.new()
	cinema.bottom_margin = BAR + 10
	add_child(cinema)
	cinema.finished.connect(func(): session.cinema_done())
	bar = CommandBar.new()
	bar.session = session
	bar.gs = self
	bar.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bar.offset_top = -BAR
	add_child(bar)
	theater = Theater.new()
	add_child(theater)
	cinema.theater = theater
	cinema.theater_hook = _theater_wants
	cinema.beat_hook = _on_beat
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
	intro = Intro.new()
	intro.finished.connect(func():
		_intro_done = true
		_refresh())
	add_child(intro)
	session.changed.connect(_refresh)
	session.phase_changed.connect(_on_phase)
	Audio.ambience(true)


func _build_plate() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.045, 0.08, 0.86), Color(Style.GOLD, 0.45), 1, 8, 12))
	p.set_anchors_preset(PRESET_TOP_LEFT)
	p.offset_left = 12
	p.offset_top = 12
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	p.add_child(v)
	_plate_map = Style.label("", 14, Style.GOLD, "display")
	v.add_child(_plate_map)
	_plate_round = Style.label("", 28, Style.CREAM, "display")
	v.add_child(_plate_round)
	_plate_phase = Style.label("", 16, Style.PARCH, "bold")
	v.add_child(_plate_phase)


func _build_zoom() -> void:
	var tools := VBoxContainer.new()
	tools.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	tools.offset_left = -60
	tools.offset_top = -BAR - 170
	tools.offset_right = -12
	tools.offset_bottom = -BAR - 14
	tools.add_theme_constant_override("separation", 6)
	add_child(tools)
	for spec in [["+", func(): board.zoom_at(board.size * 0.5, 1.25)], ["−", func(): board.zoom_at(board.size * 0.5, 0.8)], ["⤢", func(): board.reset_view()]]:
		var b := Style.chip(spec[0], spec[1], Style.CREAM, 22)
		b.custom_minimum_size = Vector2(48, 44)
		b.tooltip_text = {"+": "Zoom in (wheel / pinch)", "−": "Zoom out", "⤢": "Whole map"}[spec[0]]
		tools.add_child(b)


# ================================================================ phases

func _on_phase(ph: int) -> void:
	if session.map != null and session.map.id != _loaded_map:
		board.load_map(session.map)
		_loaded_map = session.map.id
	_cover.visible = false
	recap.visible = false
	surge_pick = -1
	drawer.visible = false
	edit_order("", "")
	match ph:
		Session.Phase.OPENING, Session.Phase.PLANNING:
			select("")
			Audio.music("plan")
			if ph == Session.Phase.OPENING and not _intro_done and not bool(session.config.get("tutorial", false)):
				if not intro.play(session):
					_intro_done = true
			else:
				_intro_done = true
			if ph == Session.Phase.PLANNING:
				_pre_regions = _regions_of_humans()
				if session.is_last_round() and not session.conquest():
					_say_once("final", "alarm")
				elif session.world.round == 1 and not bool(session.config.get("tutorial", false)):
					_say_once("reinforce")
		Session.Phase.PASS:
			_show_pass()
		Session.Phase.RESOLVING:
			_show_sealing()
		Session.Phase.CINEMA:
			_cover.visible = false
			select("")
			cinema.play(session, board)
		Session.Phase.RECAP:
			Audio.music("plan")
			_log_round()
			recap.show_round()
			_react_to_round()
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
			_game_over_voice(won, any_human)
	_refresh()


func _refresh() -> void:
	if session.map != null and board.art == null:
		board.load_map(session.map)
		_loaded_map = session.map.id
	if session.world == null:
		return
	var ph: int = session.phase
	_refresh_plate()
	roster.refresh()
	bar.refresh()
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
		board.battle = {}
		board.refresh()
		land_card.show_for(selected if not order_card.visible else "")
		if order_card.visible:
			order_card.rebuild()
		if drawer.visible:
			drawer.refresh()
		_update_counsel()
	elif ph != Session.Phase.CINEMA:
		land_card.show_for("")
		order_card.visible = false
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
	else:
		land_card.show_for("")
		order_card.visible = false


func _refresh_plate() -> void:
	var s = session
	_plate_map.text = s.map.display_name.to_upper()
	var total: int = s.rounds_total()
	if s.phase == Session.Phase.OPENING or s.setup_dict.is_empty() or (s.phase == Session.Phase.CINEMA and bool(s.get_meta("opening_cinema", false))):
		_plate_round.text = "Deployment"
	else:
		var n: int = s.world.round
		if s.phase == Session.Phase.CINEMA or s.phase == Session.Phase.RECAP or s.phase == Session.Phase.GAME_OVER:
			n = maxi(1, s.world.round - 1)
		_plate_round.text = ("Round %d" % n) if s.conquest() else ("Round %d of %d" % [mini(n, total), total])
	match s.phase:
		Session.Phase.OPENING:
			_plate_phase.text = "Deployment — %s" % s.name_of(s.planner)
		Session.Phase.PLANNING:
			_plate_phase.text = ("FINAL ROUND — " if s.is_last_round() and not s.conquest() else "") + "Orders for %s" % s.name_of(s.planner)
		Session.Phase.CINEMA:
			_plate_phase.text = "Battle report"
		Session.Phase.RECAP:
			_plate_phase.text = "The round is done"
		Session.Phase.GAME_OVER:
			_plate_phase.text = "The war is over"
		Session.Phase.RESOLVING:
			_plate_phase.text = "Orders sealed"
		_:
			_plate_phase.text = ""


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


# ================================================================ counsel + voice

func _update_counsel() -> void:
	var items: Array = []
	var les: Dictionary = Counsel.lesson(session, surge_pick)
	if not les.is_empty():
		items.append(les)
	if bool(Settings.get_value("tips", true)) or bool(session.config.get("tutorial", false)):
		items.append_array(Counsel.advice(session))
	if items.is_empty():
		items.append({"key": "idle", "text": "Awaiting your orders, Commander.", "mood": "neutral", "voice": "", "focus": [], "rank": 0})
	bar.set_counsel(items)
	## speak the most important thing, once per round
	var top: Dictionary = items[0]
	var v: String = str(top.get("voice", ""))
	if v != "" and (int(top["rank"]) >= 80 or v in ["welcome", "deploy", "cards", "dug_in", "surge", "attack_hint"]):
		_say_once(v, {"alarmed": "alarm", "pleased": "happy"}.get(str(top["mood"]), "neutral"), str(top["key"]))


func _say_once(line: String, mood: String = "neutral", key: String = "") -> void:
	var k: String = key if key != "" else line
	var r: int = session.world.round if session.world else 0
	if _spoken.get(k, -1) == r:
		return
	_spoken[k] = r
	if not Lines.has("advisor", line):
		return
	bar.advisor.react(mood, line, 3.0)


func focus_advice(item: Dictionary) -> void:
	var f: Array = item.get("focus", [])
	board.battle = {}
	for id in f:
		board.battle[id] = true
	board.refresh()
	get_tree().create_timer(1.6).timeout.connect(func():
		board.battle = {}
		board.refresh())


func open_plan() -> void:
	if session.phase != Session.Phase.PLANNING:
		return
	var d: Control = PlanDialog.new()
	d.session = session
	add_child(d)


# ================================================================ map input

func select(id: String) -> void:
	selected = id
	surge_pick = -1
	if id == "" or id != _order_focus[0]:
		edit_order("", "")
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
			log_line("Surge planned into %s." % session.hex_name(id), Style.GOLD)
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
			select(id)
			Audio.sfx("click", -8.0)
		return
	if ph == Session.Phase.PLANNING and selected != "" and session.world.get_territory(selected).owner == session.planner and session.map.is_adjacent(selected, id):
		order_attack(selected, id)
		return
	select(id)


func _on_drag(from_id: String, to_id: String) -> void:
	if session.phase != Session.Phase.PLANNING:
		return
	if session.world.get_territory(from_id).owner != session.planner:
		return
	if not session.map.is_adjacent(from_id, to_id):
		_toast("%s does not border %s." % [session.hex_name(to_id), session.hex_name(from_id)])
		Audio.sfx("error")
		return
	selected = from_id
	if session.world.get_territory(to_id).owner == session.planner:
		order_move(from_id, to_id)
	else:
		order_attack(from_id, to_id)


func _on_hover(id: String) -> void:
	if id == "" or session.world == null or land_card.visible and id == selected:
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
		lines.append("%s · %s%s" % [session.name_of(ts.owner), Style.plural(ts.held(), "army", "armies"), (" (%d dug in)" % ts.garrison) if ts.garrison > 0 else ""])
	_hover_label.text = "\n".join(lines)
	_hover_tip.visible = true
	_hover_tip.reset_size()
	var p: Vector2 = board.anchor(id) + Vector2(28, -_hover_tip.size.y - 22)
	p.x = clampf(p.x, 4, size.x - _hover_tip.size.x - 4)
	p.y = clampf(p.y, TOP, size.y - BAR - _hover_tip.size.y - 4)
	_hover_tip.position = p


func _on_roster_hover(pid: String) -> void:
	if session.world == null:
		return
	board.dimmed = {}
	if pid != "":
		for t in session.world.territories.keys():
			if session.world.get_territory(t).owner != pid:
				board.dimmed[t] = true
	board.refresh()


func place_popover(ctrl: Control, land: String) -> void:
	if land == "" or board.art == null:
		return
	## Pick the side that hides the fewest neighbors — they are what you click next.
	var a: Vector2 = board.anchor(land)
	var sz: Vector2 = ctrl.size
	var r: float = board.token_radius() + 10.0
	var low: float = size.y - BAR - sz.y - 12
	var candidates := [
		a + Vector2(r + 36, -sz.y * 0.35),
		a + Vector2(-r - 36 - sz.x, -sz.y * 0.35),
		a + Vector2(-sz.x * 0.5, r + 34),
		a + Vector2(-sz.x * 0.5, -r - 20 - sz.y),
		Vector2(12, low),
		Vector2(size.x - sz.x - 72, low),
		Vector2(12, a.y - sz.y * 0.5),
		Vector2(size.x - sz.x - 72, a.y - sz.y * 0.5),
	]
	var near: Array = [a]
	for n in session.map.get_territory(land).adjacent:
		near.append(board.anchor(n))
	var best: Vector2 = candidates[0]
	var best_cost := 1e9
	for i in candidates.size():
		var p: Vector2 = candidates[i]
		p.x = clampf(p.x, 8, size.x - sz.x - 8)
		p.y = clampf(p.y, TOP + 8, size.y - BAR - sz.y - 8)
		var rect := Rect2(p, sz).grow(18)
		var cost := float(i) * 0.02 + (p + sz * 0.5).distance_to(a) * 0.0006
		for q in near:
			if rect.has_point(q):
				cost += 1.0
		if cost < best_cost:
			best_cost = cost
			best = p
	ctrl.position = best


func place_order_card(ctrl: Control, a: String, b: String) -> void:
	if board.art == null:
		return
	var m: Vector2 = (board.anchor(a) + board.anchor(b)) * 0.5
	var p := m + Vector2(30, 24)
	if p.x + ctrl.size.x > size.x - 8:
		p.x = m.x - 30 - ctrl.size.x
	p.x = clampf(p.x, 8, size.x - ctrl.size.x - 8)
	p.y = clampf(p.y, TOP + 8, size.y - BAR - ctrl.size.y - 8)
	ctrl.position = p


func _process(_d: float) -> void:
	## cards follow the map when it pans or zooms
	if land_card.visible and land_card.land != "":
		place_popover(land_card, land_card.land)
	if order_card.visible:
		place_order_card(order_card, _order_focus[0], _order_focus[1])


# ================================================================ orders

func place(id: String, delta: int) -> void:
	var err: String = session.add_place(id, delta)
	if err != "":
		_toast(err)
		Audio.sfx("error")
	else:
		Audio.sfx("place" if delta > 0 else "unplace")
		bar.bump_coin()
		board.pulse_token(id, 0.3)
		if delta > 0:
			var n: int = session.placed_on(id)
			var txt := "%s placed in %s." % ["A battalion has been" if n == 1 else "%d battalions have been" % n, session.hex_name(id)]
			if _last_place == id and not log_lines.is_empty():
				log_lines[-1] = [txt, Style.CREAM]
			else:
				log_line(txt, Style.CREAM)
			_last_place = id
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
	var idx: int = session.packet_index(from_id, to_id)
	var n: int = (session.sheet().packets[idx] as Types.Packet).strength
	log_line("Attack ordered: %s ➜ %s with %d." % [session.hex_name(from_id), session.hex_name(to_id), n], Style.CRIMSON.lightened(0.2))
	_last_place = ""
	edit_order(from_id, to_id)


func order_move(from_id: String, to_id: String) -> void:
	var err: String = session.set_regroup(from_id, to_id)
	if err != "":
		_toast(err)
		Audio.sfx("error")
		return
	Audio.sfx("order_move")
	log_line("Move ordered: %s ➜ %s." % [session.hex_name(from_id), session.hex_name(to_id)], Style.PARCH)
	_refresh()


func edit_order(a: String, b: String) -> void:
	_order_focus = [a, b]
	if a == "":
		order_card.visible = false
		return
	order_card.show_for(a, b)
	_refresh()


func begin_surge_pick(i: int) -> void:
	surge_pick = i
	edit_order("", "")
	var p: Types.Packet = session.sheet().packets[i]
	_toast("Click a land next to %s to surge into it. (Esc cancels)" % session.hex_name(p.to_id))
	_refresh()


func primary_action() -> void:
	match session.phase:
		Session.Phase.OPENING, Session.Phase.PLANNING:
			try_seal()
		Session.Phase.CINEMA:
			if not theater.visible:
				cinema.advance()
		Session.Phase.RECAP:
			recap.visible = false
			session.next_round()


func try_seal() -> void:
	if session.phase != Session.Phase.PLANNING and session.phase != Session.Phase.OPENING:
		return
	if session.income_left() > 0:
		_say_once("unplaced", "alarm")
		_confirm("%d troops still unplaced" % session.income_left(),
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
	log_line("Orders sealed.", Style.GOLD)
	selected = ""


func toggle_view() -> void:
	var m: int = 1 - board.view_mode
	board.set_view_mode(m)
	Settings.set_value("map_view", m)
	_toast("Map shows %s" % ("region colours — owners ride the borders" if m == 1 else "owner colours"))


func open_drawer() -> void:
	drawer.visible = not drawer.visible
	if drawer.visible:
		drawer.refresh()


func open_rules() -> void:
	_open_rules(0)


func cinema_progress() -> String:
	return cinema.progress_text()


func log_line(text: String, color: Color = Style.CREAM) -> void:
	log_lines.append([text, color])
	if log_lines.size() > 40:
		log_lines.pop_front()
	bar.refresh()


# ================================================================ cinema hooks

func _theater_wants(b: Dictionary) -> bool:
	match str(Settings.get_value("battles", "mine")):
		"off":
			return false
		"all":
			return true
	return session.is_human(str(b["a"])) or session.is_human(str(b["b"]))


func _on_beat(b: Dictionary) -> void:
	bar.set_message("%s — %s" % [b.get("caption", ""), b.get("sub", "")] if str(b.get("sub", "")) != "" else str(b.get("caption", "")))
	bar.refresh()
	if bool(b.get("reveal", false)) and not session.living_humans().is_empty():
		_say_once("reveal")
	if b.has("walkin"):
		var who: String = str(b["walkin"])
		var victim: String = str(b["victim"])
		var voice: String = str(session.seat(who).get("portrait", ""))
		if session.is_human(victim) and roster.faces.has(who) and Lines.has(voice, "walkin"):
			roster.faces[who].react("win", "walkin", 3.2)
		elif session.is_human(who):
			bar.advisor.react("happy", "walkin_us", 3.0)
		elif session.is_human(victim):
			bar.advisor.react("alarm", "walkin_them", 3.0)
	if b.has("eliminated"):
		_show_fallen(str(b["eliminated"]))


func _show_fallen(pid: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.panel_box(22))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var holder := CenterContainer.new()
	v.add_child(holder)
	var face: Control = LeaderFace.new()
	face.custom_minimum_size = Vector2(170, 170)
	face.bubble_side = "none"
	holder.add_child(face)
	var seat: Dictionary = session.seat(pid)
	var who: String = str(seat.get("portrait", "player"))
	face.setup(who, pid, session.name_of(pid))
	var n := Style.label("%s HAS FALLEN" % session.name_of(pid).to_upper(), 28, Style.seat_color(pid).lightened(0.4), "display")
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var q := Style.label("", 19, Style.PARCH, "italic")
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(420, 0)
	v.add_child(q)
	if Lines.has(who, "eliminated"):
		q.text = "“%s”" % Lines.text(who, "eliminated")
	card.reset_size()
	card.position = (size - card.size) * 0.5 - Vector2(0, BAR * 0.4)
	face.react("dead", "eliminated", 3.5)
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.3)
	tw.tween_interval(3.4)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)
	if not session.is_human(pid) and not session.living_humans().is_empty():
		get_tree().create_timer(4.0).timeout.connect(func(): bar.advisor.react("happy", "enemy_out", 2.5))


func _regions_of_humans() -> Dictionary:
	var out := {}
	for pid in session.living_humans():
		for r in session.map.region_bonus.keys():
			if MapLib.holds_region(session.world, session.map, pid, str(r)):
				out["%s|%s" % [pid, r]] = true
	return out


func _react_to_round() -> void:
	var now := _regions_of_humans()
	for k in now.keys():
		if not _pre_regions.has(k):
			var r: String = str(k).split("|")[1]
			log_line("%s is ours! +%d every round." % [session.map.region_names.get(r, r), int(session.map.region_bonus[r])], Style.GOLD)
			_say_once("region", "happy", "region_" + r)
			return


func _log_round() -> void:
	var took := {}
	var lost := {}
	for e in session.events:
		if str(e.get("kind", "")) == "Occupied":
			var who: String = str(e["playerId"])
			var prev: String = str(e.get("previousOwner", ""))
			took[who] = int(took.get(who, 0)) + 1
			if prev != "":
				lost[prev] = int(lost.get(prev, 0)) + 1
	var n: int = maxi(1, session.world.round - 1)
	for pid in session.living_humans():
		var t: int = int(took.get(pid, 0))
		var l: int = int(lost.get(pid, 0))
		log_line("Round %d: %s took %d, lost %d." % [n, session.name_of(pid), t, l], Style.GOOD if t >= l else Style.WARN)


func _game_over_voice(won: bool, any_human: bool) -> void:
	var w: String = session.winner
	var who: String = str(session.seat(w).get("portrait", ""))
	get_tree().create_timer(0.8).timeout.connect(func():
		if not session.is_human(w) and Lines.has(who, "victory"):
			Audio.voice(Lines.voice_path(who, "victory"))
		elif won:
			Audio.voice(Lines.voice_path("advisor", "victory"))
		elif any_human:
			Audio.voice(Lines.voice_path("advisor", "defeat")))


func _maybe_defeat_notice() -> void:
	if _defeat_shown or session.winner != "":
		return
	var fell: Array = []
	for e in session.events:
		if str(e.get("kind", "")) == "PlayerEliminated" and session.is_human(str(e["playerId"])):
			fell.append(session.name_of(str(e["playerId"])))
	if fell.is_empty() or not session.living_humans().is_empty():
		return
	_defeat_shown = true
	bar.advisor.react("dead", "defeat", 3.0)
	_confirm("%s ha%s been defeated" % [" and ".join(fell), "s" if fell.size() == 1 else "ve"],
		"The commanders will fight on without you. Watch them finish the war, or leave the field.",
		[["Watch the rest", func(): pass], ["New game", func(): main.show_setup()], ["Main menu", func(): main.show_title()]])


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
	var holder := CenterContainer.new()
	v.add_child(holder)
	var face: Control = LeaderFace.new()
	face.custom_minimum_size = Vector2(180, 180)
	face.bubble_side = "none"
	holder.add_child(face)
	face.setup(str(session.seat(pid).get("portrait", "player")), pid, session.name_of(pid))
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
	dim.color = Color(0.01, 0.02, 0.04, 0.55)
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
	if not session.living_humans().is_empty():
		_say_once("sealed")


func _toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.flat(Color(0.08, 0.05, 0.04, 0.95), Style.WARN, 1, 6, 12))
	var l := Style.label(text, 18, Style.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## a wrapping label has no natural width: give it the text's own, up to a line's worth
	var w: float = Style.font("body").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	l.custom_minimum_size = Vector2(minf(w + 4.0, 680.0), 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	p.reset_size()
	p.position = Vector2((size.x - p.size.x) * 0.5, size.y - BAR - p.size.y - 26)
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
	_confirm("Paused", "Your campaign is saved after every round.", [
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
		elif order_card.visible:
			edit_order("", "")
		elif drawer.visible:
			drawer.visible = false
		elif selected != "":
			select("")
		elif session.phase != Session.Phase.CINEMA:
			open_menu()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and (event.meta_pressed or event.ctrl_pressed):
		try_seal()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_V and session.phase != Session.Phase.CINEMA:
		toggle_view()
		get_viewport().set_input_as_handled()
