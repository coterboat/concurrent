## The war table: full-bleed map, commanders top-right, the command bar below,
## floating cards on the map, and the battlefield for the fights that matter.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
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
const Cutscene := preload("res://game/ui/cutscene.gd")
const Intro := preload("res://game/ui/intro.gd")
const PlanDialog := preload("res://game/ui/plan_dialog.gd")
const HowTo := preload("res://game/ui/howto_screen.gd")
const CardsDialog := preload("res://game/ui/cards_dialog.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")
const DiceStage := preload("res://game/ui/dice_stage.gd")
const LandTip := preload("res://game/ui/land_tip.gd")
const Moments := preload("res://game/ui/moments.gd")
const BoardFacts := preload("res://game/core/board_facts.gd")
const Land := preload("res://game/world3d/land.gd")
const LandBoard := preload("res://game/world3d/land_board.gd")

const BAR := 156.0
const TOP := 84.0

var main: Control
var session: Node
var resuming := false ## v2.4: a saved war picked up (main.continue_game): it comes back on the view it was left on
var selected := ""
var surge_pick := -1
var log_lines: Array = [] ## [text, color]

var board: Control
var land: Node ## v2.0: the map's land in 3D, one world a game (land.gd)
var land_board: Control ## v2.0: the board standing on it (land_board.gd)
var _land_chip: Button
var _land_lbl: Array = [] ## v2.4: the chip's "3D" and "2D", the view the board is on lit
var _veil: Control ## v2.4: over the board while a war picked up on the land waits for it to be laid out
var bar: Control
var roster: Control
var cinema: Control
var theater: Control
var recap: Control
var game_over: Control
var cutscene: Control ## v1.9: the war's big moments on film
var _films_seen := {} ## each film plays once a war
var land_card: PanelContainer
var order_card: PanelContainer
var drawer: PanelContainer
var intro: Control
var _plate_map: Label
var _plate_round: Label
var _plate_phase: Label
var _cover: Control
var _modal: Control
var _claim_wait := false ## v1.14: a land was just claimed; the next turn hasn't been announced yet
var _recap_at := 0 ## v1.14: when the round report came up (Space goes on from it, but not at once)
const RECAP_KEY_MS := 900
var _hover_tip: PanelContainer
var _hover_label: Label
var _loaded_map := ""
var _order_focus := ["", ""]
var _spoken := {} ## advisor lines already said: key -> round
var _intro_done := false
var _defeat_shown := false
var _last_place := ""
var _pre_regions := {}
## v1.4 the land draft: dice dropped on the map for the order, then claims round the table
var _draft_ui: Control
var _draft_dice: Control
var _draft_title: Label
var _draft_row: HBoxContainer
var _draft_state := "" ## "" | rolling | picking | done
var _draft_marks: Array = []
var _draft_spoke := {}
var draft_fast := false
## v2.4: the commanders take their seats on the war table as their dice fall for the order of claims (on a
## dealt war, before the deployment): who is still to sit, whose card is up, and whose die is falling
var _seats_due := false ## the roll about to begin opens with the introductions
var _seating: Array = [] ## pids still to take their seats
var _seated := {} ## pid -> true once their card has come up
var _seat_live := "" ## whose card is up
var _seat_t0 := 0 ## when it came up (msec)
var _seat_min := 0.0 ## seconds it stays up at least
var _seat_rolling := "" ## whose die is still falling ("*": the rest, thrown together on Esc)
var _seat_dice := false ## their dice fall as they sit (the draft); a dealt war has no roll
var _seat_wait := 0 ## the next card waits till then (msec): a breath between commanders
var _seat_snaps: Array = [] ## the dice already down, kept on the table as pictures while the next one falls
var _fallen_until := 0.0 ## the fallen commander's panel is up until then (msec)
var _fallen_at := Vector2.ZERO
var _chest_taken := false


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
	board.shield_style = str(Settings.get_value("shields", "ranked")) ## v2.4
	land = Land.new()
	add_child(land)
	land_board = LandBoard.new()
	land_board.attach(board, land)
	land_board.set_on(bool(Settings.get_value("map_land", true)))
	Settings.changed.connect(_land_setting) ## the Settings panel's switch, mid-game
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
	_build_draft()
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
	cinema.finished.connect(func():
		roster.view = null
		session.cinema_done())
	cinema.shown.connect(func():
		roster.view = board.world
		roster.refresh())
	bar = CommandBar.new()
	bar.session = session
	bar.gs = self
	bar.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bar.offset_top = -BAR
	add_child(bar)
	theater = Theater.new()
	theater.board = board
	theater.land = land
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
	intro = Intro.new() ## v2.4: a card on the table: the commanders take their seats as their dice fall (_seat_*)
	intro.pressed.connect(_seat_hurry)
	intro.skipped.connect(func():
		if _seating_now():
			_seat_skip())
	add_child(intro)
	cutscene = Cutscene.new()
	add_child(cutscene)
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
	tools.offset_top = -BAR - 220
	tools.offset_right = -12
	tools.offset_bottom = -BAR - 14
	tools.add_theme_constant_override("separation", 6)
	add_child(tools)
	for spec in [["+", func(): board.zoom_at(board.size * 0.5, 1.25)], ["−", func(): board.zoom_at(board.size * 0.5, 0.8)], ["⤢", func(): board.reset_view()]]:
		var b := Style.chip(spec[0], spec[1], Style.CREAM, 22)
		b.custom_minimum_size = Vector2(48, 44)
		b.tooltip_text = {"+": "Zoom in (wheel / pinch)", "−": "Zoom out", "⤢": "Whole map"}[spec[0]]
		tools.add_child(b)
	## v2.0: the board on the land, or the chart. v2.4: the chip shows the view the board is on, both
	## words on it and that one lit (it read "2D" on the land: the way out, which reads as where you are)
	_land_chip = Style.chip("", toggle_land, Style.GOLD, 17)
	_land_chip.custom_minimum_size = Vector2(48, 52)
	var lv := VBoxContainer.new()
	lv.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", -4)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_land_chip.add_child(lv)
	for word in ["3D", "2D"]:
		var l := Style.label(word, 15, Style.MUTED, "display")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(l)
		_land_lbl.append(l)
	tools.add_child(_land_chip)
	tools.move_child(_land_chip, 0)
	_land_chip_text()


func _land_chip_text() -> void:
	if _land_chip == null:
		return
	var on3d: bool = land_board != null and land_board.on
	for k in _land_lbl.size():
		var lit: bool = (k == 0) == on3d
		var l: Label = _land_lbl[k]
		l.add_theme_font_size_override("font_size", 18 if lit else 12)
		l.add_theme_color_override("font_color", Style.GOLD if lit else Color(Style.MUTED, 0.8))
	_land_chip.tooltip_text = "The land in 3D: click or press L for the chart" if on3d else "The chart: click or press L for the land in 3D"


func land_view() -> String:
	## v2.4: the view the chip shows lit ("3D" or "2D"; the probe reads it)
	return "3D" if land_board != null and land_board.on else "2D"


func toggle_land() -> void:
	## v2.0: the board on the land in 3D, or the chart as it always was (L)
	var v: bool = not land_board.on
	Settings.set_value("map_land", v)
	land_board.set_on(v)
	_prepare_land()
	_land_chip_text()
	if not v:
		_lift_veil() ## the chart is there at once
	_toast("The map: %s" % ("the land" if v else "the chart"))


func _land_setting() -> void:
	var v: bool = bool(Settings.get_value("map_land", true))
	if land_board != null and land_board.on != v:
		land_board.set_on(v)
		_prepare_land()
		_land_chip_text()
		if not v:
			_lift_veil()


func _prepare_land() -> void:
	## v2.0: build the land in the background once a map is loaded, if the board or the battles want it
	if board.art == null:
		return
	if theater != null:
		theater.prepare_land()
	var resume: bool = resuming ## (only as the war is picked up: turned on later, the land rises from the chart)
	resuming = false
	if land_board != null and land_board.on:
		land.prepare(board)
		if resume:
			_veil_land()


func _veil_land() -> void:
	## v2.4: a war picked up on the land comes back on it (the owner: "loading a game brings it into 2d,
	## it should resume on whichever view it was"). It showed the chart while the land was laid out again
	## (two seconds here, longer on a slower machine), the chip already reading "2D", then rose into 3D.
	## Now a veil covers the board until the land is ready, and the board is on it at once.
	if land_board.ready_to_show() or _veil != null:
		land_board.set_on(true, true)
		return
	_veil = Control.new()
	_veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	var dark := ColorRect.new()
	dark.color = Style.INK
	dark.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.add_child(dark)
	var l := Style.label("Laying out the land…", 22, Style.PARCH, "italic")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(PRESET_CENTER)
	l.offset_left = -300
	l.offset_right = 300
	l.offset_top = 40 ## under where a phase's banner hangs
	l.offset_bottom = 72
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.add_child(l)
	add_child(_veil)
	move_child(_veil, board.get_index() + 1) ## over the board, under the table's own panels
	land.built.connect(_land_up, CONNECT_ONE_SHOT)
	get_tree().create_timer(20.0).timeout.connect(_lift_veil) ## a land that never comes: the chart, and it rises when it does


func _land_up() -> void:
	## the land is laid out: the board is on it at once (not risen from the chart), and the veil lifts once
	## its first pictures are in
	if land_board.on:
		land_board.set_on(true, true)
	_land_chip_text()
	get_tree().create_timer(0.2).timeout.connect(_lift_veil)


func _lift_veil() -> void:
	if _veil == null or not is_instance_valid(_veil) or _veil.has_meta("lifting"):
		return
	var v: Control = _veil
	v.set_meta("lifting", true)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := v.create_tween()
	tw.tween_property(v, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		v.queue_free()
		if _veil == v:
			_veil = null)


# ================================================================ phases

func _on_phase(ph: int) -> void:
	## v2.3: a war being left (main._swap) lives to the frame's end and hears the next war start: it
	## must not take it up (it loaded the new map and began building that land too: a crash at exit)
	if is_queued_for_deletion():
		return
	if session.map != null and session.map.id != _loaded_map:
		board.load_map(session.map)
		_loaded_map = session.map.id
		_prepare_land()
	_cover.visible = false
	recap.visible = false
	surge_pick = -1
	drawer.visible = false
	edit_order("", "")
	_drop_planning_question()
	match ph:
		Session.Phase.DRAFT:
			select("")
			if not _intro_done and not bool(session.config.get("tutorial", false)):
				_start_intro() ## v2.4: the music waits for the film
			else:
				Audio.music("plan")
				if _intro_done:
					phase_banner("CLAIMING THE LANDS", "Every commander throws a die for the order of choosing")
				_intro_done = true
		Session.Phase.MANEUVER:
			select("")
			_war_alive()
			Audio.music(_hot_or("muster")) ## v1.13: a war at its height stays there through the regroup
			phase_banner("REGROUP PHASE", "March troops one land toward the front")
			_say_once("maneuver", "neutral")
			log_line("Regroup phase: march troops one land toward the front.", Style.GOOD)
		Session.Phase.OPENING, Session.Phase.PLANNING:
			select("")
			Audio.heat = _plan_mood() if ph == Session.Phase.PLANNING else ""
			var seats_first: bool = ph == Session.Phase.OPENING and not _intro_done and not bool(session.config.get("tutorial", false))
			if seats_first:
				_start_intro() ## v2.4: the music waits for the film; the deployment's banner follows the introductions
			else:
				Audio.music(_plan_mood() if ph == Session.Phase.PLANNING else "plan")
				_intro_done = true
				if ph == Session.Phase.OPENING:
					phase_banner("DEPLOYMENT", "Name your capital, then place your starting armies" if session.capital_choosable() else "Place your starting armies")
			if ph == Session.Phase.PLANNING:
				_war_alive()
				phase_banner("REINFORCEMENT PHASE", "Round %d · place %d fresh recruits on your lands" % [session.world.round, session.income_total()])
				_pre_regions = _regions_of_humans()
				_note_rival_marches()
				if session.is_last_round() and not session.conquest():
					_say_once("final", "alarm")
				elif session.world.round == 1 and not bool(session.config.get("tutorial", false)):
					_say_once("reinforce")
				else:
					_standing_remark()
		Session.Phase.PASS:
			_show_pass()
		Session.Phase.RESOLVING:
			_show_sealing()
		Session.Phase.CINEMA:
			_cover.visible = false
			roster.view = session.pre_world ## the counts start where the round began
			select("")
			if not bool(session.get_meta("opening_cinema", false)):
				Audio.heat = _plan_mood() ## v1.13: the report's music (Audio.battle_music)
				phase_banner("THE BATTLES", "Every order happens at once")
			board.smolder([]) ## the report makes its own smoke
			cinema.play(session, board)
		Session.Phase.RECAP:
			if session.winner == "":
				Audio.music(_hot_or("plan")) ## v1.13: the endgame doesn't drop back to the plan theme
			## (the war's last reckoning keeps the battle playing until the ending)
			_log_round()
			recap.show_round()
			_recap_at = Time.get_ticks_msec()
			_react_to_round()
			_lead_moment()
			_maybe_defeat_notice()
		Session.Phase.GAME_OVER:
			var won: bool = session.is_human(session.winner)
			var any_human := false
			for s in session.seats:
				if s["kind"] == "human":
					any_human = true
			Audio.ambience(false)
			## v1.9: the film of the ending first, then the tally. v1.13: the ending's music starts
			## with the tally, full, not ducked under the film's own score (the war's music fades
			## out under the film)
			var tally := func():
				Audio.music("victory" if (won or not any_human) else "defeat", 0.6, true) ## v1.9: then the march (or the lament)
				game_over.show_result()
				_game_over_voice(won, any_human)
			if any_human and _film("victory" if won else "defeat", "", "", tally):
				Audio.music("", 1.5)
			else:
				tally.call()
	_refresh()


func _refresh() -> void:
	if is_queued_for_deletion():
		return ## v2.3: a war being left (see _on_phase)
	if session.map != null and board.art == null:
		board.load_map(session.map)
		_loaded_map = session.map.id
		_prepare_land()
	if session.world == null:
		return
	var ph: int = session.phase
	board.threats = {}
	board.hinges = {}
	board.arriving = {}
	board.capital_override = {}
	if session.capital_choosable():
		board.capital_override[session.planner] = session.capital_shown(session.planner) ## v1.8: yours, as you choose it
	_refresh_plate()
	roster.refresh()
	bar.refresh()
	var planning: bool = ph == Session.Phase.OPENING or ph == Session.Phase.PLANNING
	_draft_ui.visible = ph == Session.Phase.DRAFT
	if ph == Session.Phase.DRAFT:
		board.interactive = true
		board.viewer = session.planner
		board.world = session.world
		board.show_ceiling = false
		board.selected = ""
		board.placements = {}
		board.ghosts = []
		board.orders = []
		board.battle = {}
		board.targets = {}
		if _draft_state == "picking" and session.is_human(session.draft_turn()):
			for t in session.map.territory_ids():
				if session.world.get_territory(str(t)).owner == Types.UNOCCUPIED:
					board.targets[str(t)] = true
		board.refresh()
		land_card.show_for("")
		order_card.visible = false
		_draft_strip()
		if _intro_done and _draft_state == "":
			_draft_begin()
	elif ph == Session.Phase.MANEUVER:
		board.interactive = true
		board.viewer = session.planner
		board.world = session.maneuver_world()
		board.show_ceiling = false
		board.selected = selected
		board.placements = {}
		board.ghosts = session.ghosts
		var arrows: Array = []
		var inbound := {} ## v2.4: the men marching in are drawn apart from those there (they stay put)
		for m in session.my_moves():
			arrows.append({"from": str(m["from"]), "to": str(m["to"]), "strength": int(m["n"]), "owner": session.planner, "kind": "move"})
			inbound[str(m["to"])] = int(inbound.get(str(m["to"]), 0)) + int(m["n"])
		board.orders = arrows
		board.arriving = inbound
		board.targets = _march_targets()
		board.battle = {}
		board.refresh()
		land_card.show_for(selected if not order_card.visible else "")
		if order_card.visible:
			order_card.rebuild()
		bar.set_counsel([{"key": "maneuver", "text": "Regroup phase. The battles are done: march troops one land at a time toward the front. Drag from one of our lands onto a neighbour of ours (or press Advisor's marches), then press MARCH. Soldiers who arrive stay put, and dug-in defenders never leave.", "mood": "neutral", "voice": "", "focus": [], "rank": 50}])
	elif planning:
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
		board.bonus = {}
		if ph == Session.Phase.PLANNING:
			for ln in session.card_bonus_lands():
				board.bonus[ln] = int(board.bonus.get(ln, 0)) + 1
		board.ghosts = (session.ghosts + session.move_ghosts) if ph == Session.Phase.PLANNING else []
		if ph == Session.Phase.PLANNING:
			## v1.13: on the world as it will stand when you seal (your recruits placed, your columns
			## gone), what could land on each of your lands, and which of them hold the road home
			board.threats = BoardFacts.threats(board.world, session.map, session.planner)
			board.hinges = BoardFacts.hinges(board.world, session.map, session.planner)
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
			## the round being fought: the world before the battles (B-006: while one of your battles
			## waits for a call, the world hasn't moved on yet, so "world.round - 1" was a round behind)
			n = s.pre_world.round if s.pre_world != null else maxi(1, s.world.round - 1)
		_plate_round.text = ("Round %d" % n) if s.conquest() else ("Round %d of %d" % [mini(n, total), total])
	match s.phase:
		Session.Phase.DRAFT:
			_plate_round.text = "Claiming the lands"
			_plate_phase.text = ("%s pick" % Style.owns(s.name_of(s.draft_turn()), true)) if _draft_state == "picking" and s.draft_turn() != "" else "Rolling for the order"
		Session.Phase.OPENING:
			_plate_phase.text = "Deployment — %s" % s.name_of(s.planner)
		Session.Phase.PLANNING:
			_plate_phase.text = ("FINAL ROUND — " if s.is_last_round() and not s.conquest() else "") + ("Reinforcements for %s" if s.plan_step == "reinforce" else "Orders for %s") % s.name_of(s.planner)
		Session.Phase.MANEUVER:
			_plate_phase.text = "Regroup phase — %s" % s.name_of(s.planner)
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
		out.append({"from": p.from_id, "to": p.to_id, "strength": p.strength, "owner": session.planner, "surge": p.surge_to, "surge_n": session.surge_count(p.to_id), "kind": "attack"})
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
	if session.plan_step == "reinforce":
		## where the recruits can still go
		if session.income_left() > 0:
			for id in MapLib.player_territory_ids(session.world, session.planner):
				if session.place_cap(id) - session.placed_on(id) > 0:
					t[id] = true
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
	var placing: bool = session.phase == Session.Phase.PLANNING and session.plan_step == "reinforce"
	if placing and str(les.get("voice", "")) == "attack_hint":
		les = {} ## attacks wait for the orders phase
	if not les.is_empty():
		items.append(les)
	if bool(Settings.get_value("tips", true)) or bool(session.config.get("tutorial", false)):
		items.append_array(Counsel.advice(session))
	if placing:
		## the reinforcement phase: where to put the men (threats and regions first), not whom to hit
		items = items.filter(func(it): return not str(it.get("key", "")).begins_with("soft_"))
	if items.is_empty():
		items.append({"key": "idle", "text": "Place your recruits, Commander." if placing else "Awaiting your orders, Commander.", "mood": "neutral", "voice": "", "focus": [], "rank": 0})
	bar.set_counsel(items)
	## speak the most important thing, once per round
	var top: Dictionary = items[0]
	var v: String = str(top.get("voice", ""))
	## (v2.4: not while the film plays or the commanders take their seats: they speak first)
	if v != "" and _intro_done and (int(top["rank"]) >= 80 or v in ["welcome", "deploy", "cards", "dug_in", "surge", "attack_hint", "capital_choose"]): ## v1.13: naming the capital is spoken too
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


func _march_targets() -> Dictionary:
	var t := {}
	if selected == "" or session.world.get_territory(selected).owner != session.planner or session.can_move_from(selected) < 1:
		return t
	for n in MapLib.supply_links(session.world, session.map, selected): ## v1.7: ports cross the sea
		if session.world.get_territory(n).owner == session.planner:
			t[n] = true
	return t


func order_march(from_id: String, to_id: String) -> void:
	var err: String = session.add_move(from_id, to_id)
	if err != "":
		_toast(err)
		Audio.sfx("error")
		return
	Audio.sfx("maneuver", -4.0)
	var n: int = int(session.my_moves()[session.move_index(from_id, to_id)]["n"])
	log_line("March: %s ➜ %s with %d." % [session.hex_name(from_id), session.hex_name(to_id), n], Style.GOOD)
	selected = from_id
	edit_order(from_id, to_id)


func _note_rival_marches() -> void:
	var n := 0
	for g in session.move_ghosts:
		if not session.is_human(str(g["owner"])):
			n += int(g["strength"])
	if n > 0:
		log_line("Your rivals marched %s toward their fronts (the pale arrows)." % Style.plural(n, "soldier"), Style.PARCH)


func _on_click(id: String, button: int) -> void:
	if _seating_now():
		_toast("The commanders are taking their seats. Space: the next one · Esc: skip them") ## v2.4
		return
	var ph: int = session.phase
	if ph == Session.Phase.DRAFT:
		if _draft_state == "picking" and not _claim_wait and session.is_human(session.draft_turn()):
			var who: String = session.draft_turn()
			var err: String = session.claim(id)
			if err != "":
				_toast(err)
				Audio.sfx("error")
			else:
				_draft_claimed(who, id)
		return
	if ph == Session.Phase.MANEUVER:
		var own: bool = session.world.get_territory(id).owner == session.planner
		if own and selected != "" and selected != id and session.world.get_territory(selected).owner == session.planner and session.marches_to(selected, id):
			order_march(selected, id)
		elif own:
			select(id if selected != id else "")
			Audio.sfx("click", -8.0)
		else:
			select(id)
		return
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
		var sp_idx: int = session.packet_index(selected, id) if selected != "" else -1
		_refresh()
		if err == "":
			for raw in session.sheet().packets:
				var pk: Types.Packet = raw
				if pk.surge_to == id:
					edit_order(pk.to_id, id) ## straight to its card: how many push on
					break
		return
	if button == MOUSE_BUTTON_RIGHT:
		if ts.owner == session.planner and _placing():
			place(id, -1)
		return
	if _placing():
		## the reinforcement phase: every click on one of ours puts a recruit there
		if ts.owner == session.planner:
			if selected != id:
				select(id)
			place(id, 1)
		else:
			select(id)
		return
	## the orders phase: pick one of ours, then the enemy to strike
	if ts.owner == session.planner:
		select(id if selected != id else "")
		Audio.sfx("click", -8.0)
		return
	if selected != "" and session.world.get_territory(selected).owner == session.planner and session.map.is_adjacent(selected, id):
		order_attack(selected, id)
		return
	if selected != "" and session.world.get_territory(selected).owner == session.planner and session.plan_step != "reinforce":
		## v1.14: say why no attack was ordered (a drag said so; a click just moved the selection)
		_toast("%s does not border %s: pick one of our lands beside it." % [session.hex_name(id), session.hex_name(selected)])
	select(id)


var _banner_node: Control


func phase_banner(title: String, sub: String = "", quiet: bool = false) -> void:
	## v1.5: every phase opens with a banner across the map and a drum-and-brass sting,
	## so it is always clear when a new phase begins
	if _banner_node != null and is_instance_valid(_banner_node):
		_banner_node.queue_free()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	root.offset_top = TOP + 170 ## over the heart of the map, clear of the report's caption
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	if theater != null:
		move_child(root, theater.get_index()) ## over the map, under the battlefield
	_banner_node = root
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Style.flat(Color(0.05, 0.035, 0.03, 0.9), Color(Style.GOLD, 0.85), 2, 6, 22))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE ## the banner never eats a click meant for the map
	pc.add_child(v)
	var t := Style.label(title, 46, Style.GOLD, "display")
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	v.add_child(t)
	if sub != "":
		var sl := Style.label(sub, 19, Style.PARCH, "italic")
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sl)
	pc.reset_size()
	pc.position = Vector2(-pc.size.x * 0.5, 0)
	pc.pivot_offset = pc.size * 0.5
	pc.scale = Vector2(1.25, 1.25)
	pc.modulate.a = 0.0
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(pc, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)
	tw.tween_callback(root.queue_free)
	if not quiet:
		Audio.sfx("phase_sting", -5.0)


func _clear_banner() -> void:
	## v2.0.2: the phase banner goes up and out of the way (it sat over the fights the report was
	## leaning in on: "THE ASSAULTS" across Wold through its whole assault)
	if _banner_node == null or not is_instance_valid(_banner_node) or _banner_node.has_meta("leaving"):
		return
	var root: Control = _banner_node
	root.set_meta("leaving", true)
	if root.get_child_count() == 0:
		root.queue_free()
		return
	var pc: Control = root.get_child(0)
	var tw := root.create_tween()
	tw.tween_property(pc, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_property(pc, "position:y", pc.position.y - 26.0, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


func _placing() -> bool:
	## deployment, or the reinforcement step of a round's planning
	return session.phase == Session.Phase.OPENING or (session.phase == Session.Phase.PLANNING and session.plan_step == "reinforce")


func begin_orders() -> void:
	## from the reinforcement phase to the orders phase
	if session.phase != Session.Phase.PLANNING or session.plan_step == "orders":
		return
	var go := func():
		session.begin_orders()
		select("")
		phase_banner("ORDERS PHASE", "Choose where to strike. Every commander's orders happen at once.")
		_say_once("orders")
	_no_room_note()
	if session.placeable_left() > 0:
		_say_once("unplaced", "alarm")
		_confirm("%s still unplaced" % Style.plural(session.placeable_left(), "recruit"),
			"Anything you don't place is lost when you seal your orders.",
			[["Place them for me", func():
				session.auto_deploy()
				go.call()], ["On to the orders", func(): go.call()], ["Go back", func(): pass]])
		_modal.set_meta("planning", true)
		return
	go.call()


func _no_room_note() -> void:
	## v2.3: recruits with nowhere to go are said once, not asked about (nothing could place them)
	var n: int = session.no_room()
	if n <= 0 or _no_room_said == "%d|%s" % [session.world.round, session.planner]:
		return
	_no_room_said = "%d|%s" % [session.world.round, session.planner]
	log_line("%s no room on our lands and %s home (a land takes 1 + your neighbouring lands)." % [Style.plural(n, "recruit") + (" has" if n == 1 else " have"), "goes" if n == 1 else "go"], Style.PARCH)


var _no_room_said := ""


func _on_drag(from_id: String, to_id: String) -> void:
	if _seating_now():
		return ## v2.4: the commanders are taking their seats
	if session.phase == Session.Phase.MANEUVER:
		if session.world.get_territory(from_id).owner == session.planner and session.world.get_territory(to_id).owner == session.planner:
			order_march(from_id, to_id)
		else:
			_toast("March between two of your own lands.")
			Audio.sfx("error")
		return
	if session.phase != Session.Phase.PLANNING:
		return
	if session.plan_step == "reinforce":
		if session.placeable_left() > 0:
			_toast("Place your %s first, then press ORDERS to attack." % ("last recruit" if session.placeable_left() == 1 else "%d recruits" % session.placeable_left()))
			Audio.sfx("error")
			return
		session.begin_orders()
	## v1.5: drag on from a land you're attacking to surge beyond it
	if session.world.get_territory(from_id).owner != session.planner:
		var idx: int = _attack_into(from_id)
		if idx >= 0 and session.map.is_adjacent(from_id, to_id):
			var err0: String = session.set_surge(idx, to_id)
			if err0 != "":
				_toast(err0)
				Audio.sfx("error")
			else:
				Audio.sfx("surge", -6.0)
				log_line("Surge planned from %s into %s." % [session.hex_name(from_id), session.hex_name(to_id)], Style.GOLD)
				edit_order(from_id, to_id)
			_refresh()
		return
	if not session.map.is_adjacent(from_id, to_id):
		_toast("%s does not border %s." % [session.hex_name(to_id), session.hex_name(from_id)])
		Audio.sfx("error")
		return
	selected = from_id
	if session.world.get_territory(to_id).owner == session.planner and session.map.maneuvers:
		_toast("Troops march between your lands in the regroup phase, after the battles.")
		Audio.sfx("error")
	elif session.world.get_territory(to_id).owner == session.planner:
		order_move(from_id, to_id)
	else:
		order_attack(from_id, to_id)


func _on_hover(id: String) -> void:
	if id == "" or session.world == null or land_card.visible and id == selected:
		_hover_tip.visible = false
		return
	## the words, the box and where it sits: game/ui/land_tip.gd
	LandTip.show(_hover_tip, _hover_label, "\n".join(LandTip.lines(session, board, id)), board.anchor(id),
		Rect2(4, TOP, size.x - 8, size.y - BAR - TOP - 4), board.token_radius() + 16.0)


var _tip_was_covered := false
var _tip_phase := -1


func tip_covered() -> bool:
	## a report, a battle, a film or a dialog is over the table
	return recap.visible or theater.visible or bool(cinema.get("_active")) or (intro != null and intro.visible) or _overlay_open()


func _tip_watch() -> void:
	## v2.0.1: a land's tip goes when the phase turns, or a report or a dialog opens over the board (LandTip.stale)
	var covered: bool = tip_covered()
	var turned: bool = session.phase != _tip_phase ## sealing the sheet, the battles, the report: a new page
	_tip_phase = session.phase
	if _hover_tip.visible and LandTip.stale(board, get_viewport().gui_get_hovered_control(), turned or (covered and not _tip_was_covered)):
		_hover_tip.visible = false
		if board.hovered != "":
			board.hovered = "" ## so the same land, pointed at again, brings its tip back
			board.refresh()
	_tip_was_covered = covered


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
	_far_off(_d)
	_tip_watch()
	_seat_tick()
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
	if session.phase == Session.Phase.MANEUVER:
		order_card.show_move(a, b)
	elif session.phase == Session.Phase.PLANNING and session.world.get_territory(a).owner != session.planner and str(session.sheet().surges.get(a, "")) == b:
		order_card.show_surge(a, b) ## v1.5: a surge edits like any march
	else:
		order_card.show_for(a, b)
	_refresh()


func order_done() -> void:
	## v2.4: OK on an order's card (or Enter): the order stands, the card closes, and the land it came
	## from is let go (the owner: "pressing 'ok' after moving troops through a left click -> left click
	## action should deselect the source region"). The card's ✕ and Esc only close the card.
	edit_order("", "")
	select("")


func _attack_into(dest: String) -> int:
	## the first of our attacks on dest (-1: none)
	if session.phase != Session.Phase.PLANNING:
		return -1
	var i := 0
	for raw in session.sheet().packets:
		if (raw as Types.Packet).to_id == dest:
			return i
		i += 1
	return -1


func begin_surge_pick(i: int) -> void:
	surge_pick = i
	edit_order("", "")
	var p: Types.Packet = session.sheet().packets[i]
	_toast("Click a land next to %s to surge into it. (Esc cancels)" % session.hex_name(p.to_id))
	_refresh()


func primary_action() -> void:
	match session.phase:
		Session.Phase.DRAFT:
			draft_advise()
		Session.Phase.OPENING:
			try_seal()
		Session.Phase.PLANNING:
			if session.plan_step == "reinforce":
				begin_orders()
			else:
				try_seal()
		Session.Phase.MANEUVER:
			var err: String = session.lock()
			if err != "":
				_toast(err)
				Audio.sfx("error")
			else:
				Audio.sfx("maneuver")
				log_line("The marches are sealed.", Style.GOOD)
				selected = ""
		Session.Phase.CINEMA:
			if not theater.visible:
				cinema.advance()
		Session.Phase.RECAP:
			recap.visible = false
			session.next_round()


func try_seal() -> void:
	if session.phase != Session.Phase.PLANNING and session.phase != Session.Phase.OPENING:
		return
	_no_room_note()
	if session.placeable_left() > 0:
		_say_once("unplaced", "alarm")
		_confirm("%s still unplaced" % Style.plural(session.placeable_left(), "troop"),
			"Anything you don't place is lost.",
			[["Place them for me", func():
				session.auto_deploy()
				_seal()], ["Seal anyway", func(): _seal()], ["Go back", func(): pass]])
		_modal.set_meta("planning", true)
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


func cycle_shields() -> void:
	## v2.4 (G): the garrison shields' looks, side by side on the owner's own war (map_board.SHIELD_STYLES)
	var all: Array = Board.SHIELD_STYLES
	var nxt: String = str(all[(all.find(board.shield_style) + 1) % all.size()])
	board.shield_style = nxt
	Settings.set_value("shields", nxt)
	board.refresh()
	_toast("Garrison shields: %s" % {"ranked": "dressed by how deep they're dug in, with the number",
		"number": "one look, the number inside (as before v2.4)", "chevrons": "dressed by depth, a chevron a man dug in"}.get(nxt, nxt))


func toggle_view() -> void:
	var m: int = 1 - board.view_mode
	board.set_view_mode(m)
	Settings.set_value("map_view", m)
	_toast("Map shows %s" % ("region colours — owners ride the borders" if m == 1 else "owner colours"))


func open_cards() -> void:
	if session.phase != Session.Phase.PLANNING or not session.map.cards:
		return
	var d: Control = CardsDialog.new()
	d.session = session
	d.closed.connect(func(): _refresh())
	d.hover_land.connect(func(id: String):
		## the land a card names lights up on the map behind the table
		if id == "":
			_refresh()
		else:
			board.targets = {id: true}
			board.pulse_token(id, 0.6)
			board.refresh())
	d.turned.connect(_on_cards_turned)
	add_child(d)


func _on_cards_turned(value: int, lands: Array, flying: Array) -> void:
	## the cards fly off the table into the recruits; then the new troops are waiting
	if session.plan_step != "reinforce":
		session.back_to_reinforce() ## fresh troops to place: back to the reinforcement phase
	var to: Vector2 = bar.coin_center()
	for k in flying.size():
		var g: Control = flying[k]
		var tw := g.create_tween()
		tw.tween_interval(0.06 * k)
		tw.tween_property(g, "global_position", to - g.size * 0.5, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(g, "scale", Vector2(0.15, 0.15), 0.55)
		tw.parallel().tween_property(g, "rotation", randf_range(-0.8, 0.8), 0.55)
		tw.tween_callback(g.queue_free)
	get_tree().create_timer(0.62).timeout.connect(func():
		Audio.sfx("cash", -3.0)
		bar.bump_coin(true)
		var l := Style.label("+%d recruits" % value, 34, Style.GOLD, "display")
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.position = to + Vector2(-60, -110)
		add_child(l)
		var tw2 := l.create_tween()
		tw2.tween_property(l, "position:y", l.position.y - 50.0, 1.4)
		tw2.parallel().tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.6)
		tw2.tween_callback(l.queue_free)
		for ln in lands:
			board.float_text(str(ln), "★ +1", Style.GOLD, 2.2, 28)
			board.pulse_token(str(ln), 1.4)
		bar.advisor.react("happy", "cash_us", 3.0)
		var names: Array = []
		for ln in lands:
			names.append(session.hex_name(str(ln)))
		log_line("Cards turned in: +%d recruits%s." % [value, (" and a free soldier on " + ", ".join(names)) if not names.is_empty() else ""], Style.GOLD)
		_refresh())


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
	for a in b.get("attackers", []):
		if session.is_human(str(a)):
			return true
	return session.is_human(str(b["a"])) or session.is_human(str(b["b"]))


func _taunt() -> void:
	## v1.8: when the orders open, one commander marching on you has a word for you (after
	## the advisor's own line), now and then — every round would wear thin
	if session.rounds_log.is_empty() or randf() > 0.55 or cinema._pre == null:
		return
	var marching: Array = []
	for d in session.rounds_log[-1]:
		var pid: String = str(d.get("playerId", ""))
		if session.is_human(pid) or not roster.faces.has(pid):
			continue
		var voice: String = str(session.seat(pid).get("portrait", ""))
		if not Lines.has(voice, "taunt"):
			continue
		for pk in d.get("packets", []):
			var ts: Types.TerritoryState = cinema._pre.get_territory(str(pk.get("to", "")))
			if ts != null and session.is_human(ts.owner):
				marching.append(pid)
				break
	if marching.is_empty():
		return
	var who: String = str(marching[randi() % marching.size()])
	get_tree().create_timer(3.4).timeout.connect(func():
		if roster.faces.has(who) and session.phase == Session.Phase.CINEMA:
			roster.faces[who].react("win", "taunt", 3.0))


func _standing_remark() -> void:
	## v1.8: the advisor notices when we take the lead, or fall far behind
	var me: Array = session.living_humans()
	if me.size() != 1 or session.world.round < 2:
		return
	var pid: String = str(me[0])
	var mine: int = Income.score_of(session.world, session.map, pid)
	var best := -1
	for o in MapLib.living_player_ids(session.world):
		if o != pid and o != "neutral":
			best = maxi(best, Income.score_of(session.world, session.map, o))
	var lead: bool = mine > best
	if lead and not _was_leading:
		_say_once("leader", "happy")
	elif not lead and best - mine >= 5 and session.world.round - _behind_said >= 3:
		_behind_said = session.world.round
		_say_once("behind", "alarm")
	_was_leading = lead


var _was_leading := false
var _behind_said := -9


func _on_beat(b: Dictionary) -> void:
	if not b.has("stage"):
		_clear_banner() ## v2.0.2: a stage's banner gives way to the stage's first moment
	bar.set_message("%s — %s" % [b.get("caption", ""), b.get("sub", "")] if str(b.get("sub", "")) != "" else str(b.get("caption", "")))
	bar.refresh()
	if bool(b.get("reveal", false)) and not session.living_humans().is_empty():
		_say_once("reveal")
		_taunt()
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
		var gone: String = str(b["eliminated"])
		if session.is_human(gone) or session.living_humans().is_empty() or not _film("eliminated", "%s is wiped out" % session.name_of(gone), "enemy_out", func(): _show_fallen(gone)):
			_show_fallen(gone)
	if b.has("fortune_to") and session.is_human(str(b["fortune_to"])):
		bar.advisor.react("happy", "fortune_gained", 3.0)
	if b.has("capital_taken"):
		## v1.8: a capital falls — the captor crows, the fallen curse, the advisor has a view
		var victim2: String = str(b["capital_taken"])
		var by2: String = str(b["capital_by"])
		for fl in b.get("focus", []):
			board.fire_at(str(fl), 5.5) ## v1.9: the city burns
		var vby: String = str(session.seat(by2).get("portrait", ""))
		var vvi: String = str(session.seat(victim2).get("portrait", ""))
		var commander_says := func():
			if not session.is_human(by2) and roster.faces.has(by2) and Lines.has(vby, "capital_took"):
				roster.faces[by2].react("win", "capital_took", 3.2)
			elif not session.is_human(victim2) and roster.faces.has(victim2) and Lines.has(vvi, "capital_lost"):
				roster.faces[victim2].react("lose", "capital_lost", 3.2)
		## v1.13: when the fall plays as a film, the commander speaks after it (the film's own
		## line used to cut theirs off, its bubble hidden under the film)
		var filmed := false
		if session.is_human(by2):
			filmed = _film("capital_taken", "%s capital falls" % Style.owns(session.name_of(victim2), true), "capital_taken", commander_says)
			if not filmed:
				bar.advisor.react("happy", "capital_taken", 3.4)
		elif session.is_human(victim2):
			filmed = _film("capital_lost", "Our capital has fallen", "capital_lost", commander_says)
			if not filmed:
				bar.advisor.react("alarm", "capital_lost", 3.4)
		if not filmed:
			commander_says.call()
	if b.has("cards_to"):
		_show_war_chest(str(b["cards_from"]), str(b["cards_to"]), b.get("cards", []))
	if b.has("split_throws"):
		_throw_split(b["split_throws"])
	if b.has("stage"):
		phase_banner(str(b["caption"]), str(b.get("sub", "")), true)
		if str(b["stage"]) == "surge" and not session.living_humans().is_empty():
			_say_once("surges", "alarm")
	if b.has("cash"):
		_show_cash(str(b["cash"]), b.get("cards", []), int(b.get("cash_value", 0)))
		for ln in b.get("cash_lands", []):
			board.float_text(str(ln), "★ +1", Style.GOLD, 2.2, 26)
			board.pulse_token(str(ln), 1.2)


# ================================================================ the land draft (v1.4)

func _build_draft() -> void:
	_draft_ui = Control.new()
	_draft_ui.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_draft_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draft_ui.visible = false
	add_child(_draft_ui)
	## the commanders' dice fall onto the map itself
	_draft_dice = DiceStage.new()
	_draft_dice.board = false
	_draft_dice.arrange = false ## where each commander's die comes to rest is where it stays
	_draft_dice.pitch = 66.0
	_draft_dice.width = 17.0
	_draft_dice.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_draft_dice.offset_bottom = -BAR
	_draft_ui.add_child(_draft_dice)
	## the order of claims, top centre
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.04, 0.07, 0.9), Color(Style.GOLD, 0.6), 1, 10, 12))
	pc.set_anchors_preset(PRESET_CENTER_TOP)
	pc.offset_top = 92
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draft_ui.add_child(pc)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	_draft_title = Style.label("", 24, Style.GOLD, "display")
	_draft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_draft_title)
	_draft_row = HBoxContainer.new()
	_draft_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_draft_row.add_theme_constant_override("separation", 14)
	v.add_child(_draft_row)


func _draft_strip() -> void:
	## the commanders in the order they choose (seat order until the dice have spoken)
	for c in _draft_row.get_children():
		c.queue_free()
	if session.draft.is_empty():
		return
	var order: Array = session.draft["order"] if _draft_state == "picking" else []
	if order.is_empty():
		for st in session.seats:
			order.append(str(st["id"]))
	var turn: String = session.draft_turn() if _draft_state == "picking" else ""
	for k in order.size():
		var pid: String = str(order[k])
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 0)
		var lf: Control = LeaderFace.new()
		lf.custom_minimum_size = Vector2(58, 58)
		lf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(lf)
		lf.setup(str(session.seat(pid).get("portrait", "player")), pid, session.name_of(pid))
		if turn != "" and pid != turn:
			lf.modulate = Color(0.6, 0.6, 0.6)
		elif _seating_now() and not _seated.has(pid):
			lf.modulate = Color(0.42, 0.42, 0.45) ## v2.4: still to take their seat
		var rank: String = ("%d. " % (k + 1)) if _draft_state == "picking" else ""
		var nm := Style.label(rank + session.name_of(pid).get_slice(" ", session.name_of(pid).get_slice_count(" ") - 1), 15, Style.seat_color(pid).lightened(0.45) if pid == turn or turn == "" else Style.MUTED, "bold")
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(nm)
		if _draft_state == "picking":
			var owned := 0
			for t in session.map.territory_ids():
				if session.world.get_territory(str(t)).owner == pid:
					owned += 1
			var ct := Style.label("%d / %d" % [owned, int(session.draft["quota"])], 13, Style.PARCH, "italic")
			ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(ct)
		_draft_row.add_child(box)


func _draft_begin() -> void:
	_draft_state = "rolling"
	_draft_title.text = "ROLLING FOR THE ORDER OF CLAIMS"
	bar.set_message("Every commander throws a die: the highest claims first, and so on round the table.")
	if not session.living_humans().is_empty():
		_say_once("draft_roll")
	if _seats_due:
		## v2.4: a new war's first roll: each commander takes their seat and throws, one by one
		_seats_due = false
		_draft_title.text = "THE COMMANDERS TAKE THEIR SEATS"
		_seat_begin(true)
		return
	get_tree().create_timer(1.4).timeout.connect(func(): _draft_throw(0))


func _draft_clear_marks() -> void:
	for m in _draft_marks:
		(m as Node).queue_free()
	_draft_marks = []
	for t in _seat_snaps:
		if is_instance_valid(t):
			(t as Node).queue_free()
	_seat_snaps = []


func _draft_throw(k: int) -> void:
	if session.phase != Session.Phase.DRAFT:
		return
	var throws: Array = session.draft["throws"]
	if k >= throws.size():
		_draft_order()
		return
	_draft_clear_marks()
	var t: Array = throws[k]
	var specs: Array = []
	for i in t.size():
		var sp: Dictionary = _die_spec(t, i)
		sp["delay"] = 0.09 * i
		specs.append(sp)
	Audio.sfx("dice_shake", -2.0)
	var dur: float = _draft_dice.throw(specs)
	get_tree().create_timer(dur + 0.15).timeout.connect(func(): _draft_landed(k))


func _die_spec(t: Array, i: int) -> Dictionary:
	## the die of the i-th commander in a throw, falling to its place in the row
	var x: float = (float(i) - float(t.size() - 1) * 0.5) * 2.7
	return {"value": int(t[i]["die"]), "n": 9, "tint": Style.seat_color(str(t[i]["pid"])), "to": Vector2(x, 0.2), "drop": true}


func _draft_mark(pid: String, die: int, at: Vector2) -> void:
	## "Varek  5" under a commander's die (v2.4: the last of their name, as on the strip: with every
	## commander's die on the table at once, "Grand Marshal Varek" ran into his neighbour's)
	var nm: String = session.name_of(pid)
	var l := Style.label("%s  %d" % [nm.get_slice(" ", nm.get_slice_count(" ") - 1), die], 20, Style.seat_color(pid).lightened(0.5), "display")
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(220, 30)
	l.position = _draft_dice.position + at + Vector2(-110, 52)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draft_ui.add_child(l)
	_draft_marks.append(l)


func _draft_landed(k: int) -> void:
	if session.phase != Session.Phase.DRAFT:
		return
	var throws: Array = session.draft["throws"]
	var t: Array = throws[k]
	for i in t.size():
		_draft_mark(str(t[i]["pid"]), int(t[i]["die"]), _draft_dice.die_screen(i))
	_draft_after(k)


func _draft_after(k: int) -> void:
	## every die of throw k is down: the tied throw again among themselves, or the order stands
	var throws: Array = session.draft["throws"]
	if k + 1 < throws.size():
		var tied: Array = []
		for r in throws[k + 1]:
			tied.append(session.name_of(str(r["pid"])))
		_draft_title.text = "%s TIE — THEY THROW AGAIN" % " AND ".join(tied).to_upper()
		get_tree().create_timer(1.8).timeout.connect(func(): _draft_throw(k + 1))
	else:
		get_tree().create_timer(1.3).timeout.connect(func(): _draft_order())


func _draft_order() -> void:
	if session.phase != Session.Phase.DRAFT:
		return
	_draft_state = "picking"
	Audio.sfx("fanfare_order", -3.0)
	_draft_title.text = "THE ORDER OF CLAIMS"
	var order: Array = session.draft["order"]
	var names: Array = []
	for pid in order:
		names.append(session.name_of(str(pid)))
	log_line("Order of claims: %s." % ", ".join(names), Style.GOLD)
	if session.is_human(str(order[0])):
		_say_once("draft_first", "happy")
	_draft_strip()
	get_tree().create_timer(2.2).timeout.connect(func():
		_draft_clear_marks()
		_draft_dice.clear()
		_draft_next())


func _draft_next() -> void:
	_claim_wait = false
	if session.phase != Session.Phase.DRAFT or not session.drafting():
		return
	var pid: String = session.draft_turn()
	_refresh()
	if session.is_human(pid):
		_draft_title.text = "%s — CLAIM A LAND" % session.name_of(pid).to_upper()
		bar.set_message("Click any free land to claim it (%d more to claim). The dial picks the advisor's choice." % session.draft_left(pid))
		_say_once("draft_pick", "neutral")
	else:
		_draft_title.text = "%s CHOOSES…" % session.name_of(pid).to_upper()
		get_tree().create_timer(0.12 if draft_fast else 0.7).timeout.connect(func():
			if session.phase == Session.Phase.DRAFT and session.draft_turn() == pid and _draft_state == "picking":
				var land: String = session.ai_claim()
				if land != "":
					_draft_claimed(pid, land))


func draft_advise() -> void:
	## the advisor's choice, for a commander who'd rather not agonize
	if session.phase != Session.Phase.DRAFT or _draft_state != "picking" or _claim_wait:
		return
	var pid: String = session.draft_turn()
	if not session.is_human(pid):
		return
	var land: String = session.draft_pick_for(pid)
	if land != "" and session.claim(land) == "":
		_draft_claimed(pid, land)


func _draft_claimed(pid: String, land: String) -> void:
	Audio.sfx("flag_plant", -5.0 if draft_fast else -2.0)
	board.float_text(land, "⚑ " + session.name_of(pid).get_slice(" ", session.name_of(pid).get_slice_count(" ") - 1), Style.seat_color(pid).lightened(0.45), 1.4, 20)
	board.pulse_token(land, 0.7)
	var voice: String = str(session.seat(pid).get("portrait", ""))
	if not _draft_spoke.has(pid) and roster.faces.has(pid) and not session.is_human(pid):
		_draft_spoke[pid] = true
		if Lines.has(voice, "claim"):
			roster.faces[pid].react("win", "claim", 2.4)
	if session.phase == Session.Phase.DRAFT:
		## v1.14: until the next commander's turn is announced, a second click (or a double-click on
		## the dial) can't claim a land in their name (hotseat: the next seat may be a person too)
		_claim_wait = true
		get_tree().create_timer(0.08 if draft_fast else 0.3).timeout.connect(func(): _draft_next())
	else:
		_draft_state = "done"
		draft_fast = false
		log_line("Every land is claimed. Deploy your armies.", Style.GOOD)


# ================================================================ the commanders take their seats (v2.4)

func _seat_begin(dice: bool) -> void:
	## the rivals first, in their seats' order, then whoever is at the table: on the roll the throws build
	## to your own; on a dealt war (no roll) only the rivals step up, to say hello
	_seat_dice = dice
	_seating = []
	_seated = {}
	for st in session.seats:
		if str(st["kind"]) != "human" and (dice or Lines.has(str(st["ai"]), "greet")):
			_seating.append(str(st["id"]))
	if dice:
		for st in session.seats:
			if str(st["kind"]) == "human":
				_seating.append(str(st["id"]))
	_seat_live = ""
	_seat_rolling = ""
	_seat_wait = Time.get_ticks_msec() + 500
	if _seating.is_empty():
		_seats_done()
	elif dice:
		_draft_strip()


func _seating_now() -> bool:
	return _seat_live != "" or _seat_rolling != "" or not _seating.is_empty()


func _seat_tick() -> void:
	if not _seating_now():
		return
	if session.phase != Session.Phase.DRAFT and session.phase != Session.Phase.OPENING:
		_seat_stop()
		return
	var now := Time.get_ticks_msec()
	if _seat_live != "":
		var up: float = float(now - _seat_t0) / 1000.0
		## the card stays for its commander's word and their die (a word that runs long is let go at 9 s)
		if up < _seat_min or _seat_rolling != "" or (Audio.voice_playing() and up < 9.0):
			return
		_seat_live = ""
		intro.leave()
		if _seating.is_empty():
			_seats_done()
			return
		_seat_wait = now + 260
	if _seat_rolling != "" or now < _seat_wait or (Audio.voice_playing() and now - _seat_wait < 6000):
		return ## (the advisor's word first)
	_seat_show(str(_seating.pop_front()))


func _seat_show(pid: String) -> void:
	_seat_live = pid
	_seated[pid] = true
	_seat_t0 = Time.get_ticks_msec()
	if _seat_dice:
		_draft_strip()
		_seat_throw(pid) ## (its fall is worked out at the throw: the card can hang where it will come to rest)
	var secs: float = intro.show_seat(session, pid)
	_place_seat_card()
	_seat_min = 1.8 if session.is_human(pid) else maxf(2.4, secs + 0.5)


func _place_seat_card() -> void:
	## near where their die comes to rest (it rolls where it will: the card waits on the throw), under it
	## and its name, or over it, or low on the map: wherever covers the fewest dice and names already on
	## the table. A dealt war's card stands in the middle of the map.
	intro.reset_size()
	var sz: Vector2 = intro.size
	var lo: float = size.y - BAR - sz.y - 10.0
	var at := Vector2((size.x - sz.x) * 0.5, TOP + (size.y - BAR - TOP - sz.y) * 0.5)
	if _seat_dice and _seat_rolling != "":
		var g: Vector2 = _draft_dice.position + _draft_dice.die_screen(0)
		var keep_clear: Array = [Rect2(g - Vector2(70, 70), Vector2(140, 160))] ## this die, and its name to come
		for m in _draft_marks:
			var lp: Vector2 = (m as Control).position
			keep_clear.append(Rect2(lp + Vector2(30, -100), Vector2(160, 132))) ## a die down, and its name
		var panel: Control = _draft_title.get_parent().get_parent()
		keep_clear.append(Rect2(panel.global_position - global_position, panel.size))
		var best := -1.0
		for y in [g.y + 96.0, g.y - 66.0 - sz.y, lo, TOP + 150.0]:
			for dx in [0.0, -0.35, 0.35]:
				var c := Vector2(clampf(g.x - sz.x * (0.5 + dx), 12.0, size.x - sz.x - 12.0), clampf(y, TOP + 8.0, lo))
				var r := Rect2(c, sz)
				var cost: float = 0.0
				for k in keep_clear:
					cost += r.intersection(k).get_area()
				cost += absf(c.y - (g.y + 96.0)) * 0.5 + absf(dx) * 400.0 ## near its die, and under it, for choice
				if best < 0.0 or cost < best:
					best = cost
					at = c
	intro.position = Vector2(clampf(at.x, 12.0, size.x - sz.x - 12.0), clampf(at.y, TOP + 8.0, lo))


static func _throw_index(t: Array, pid: String) -> int:
	for i in t.size():
		if str(t[i]["pid"]) == pid:
			return i
	return -1


func _seat_throw(pid: String) -> void:
	## their die leaves the hand a moment after their card comes up
	var t: Array = session.draft["throws"][0]
	var i: int = _throw_index(t, pid)
	if i < 0:
		return
	_seat_rolling = pid
	var sp: Dictionary = _die_spec(t, i)
	sp["delay"] = 0.35
	var dur: float = _draft_dice.throw([sp])
	get_tree().create_timer(0.3).timeout.connect(func():
		if _seat_rolling == pid:
			Audio.sfx("dice_shake", -2.0))
	get_tree().create_timer(dur + 0.1).timeout.connect(func(): _seat_landed(pid, i))


func _seat_landed(pid: String, i: int) -> void:
	await RenderingServer.frame_post_draw ## the die at rest is in the stage's picture
	if not is_inside_tree() or session.phase != Session.Phase.DRAFT or _seat_rolling != pid:
		return
	var t: Array = session.draft["throws"][0]
	_draft_mark(pid, int(t[i]["die"]), _draft_dice.die_screen(0))
	_seat_picture()
	_seat_rolling = ""


func _seat_picture() -> void:
	## one stage throws every die, one at a time: the dice already down stay on the table as a picture of
	## it, and the stage clears for the next (a stage for each would be a 3D world for each)
	var vp: SubViewport = _draft_dice.get("_vp")
	var img: Image = vp.get_texture().get_image() if vp != null else null
	if img == null or img.is_empty():
		return
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA ## as the stage draws itself
	tr.material = cm
	tr.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	tr.offset_bottom = -BAR
	_draft_ui.add_child(tr)
	_draft_ui.move_child(tr, _draft_dice.get_index() + 1)
	_seat_snaps.append(tr)
	_draft_dice.clear()


func _seat_hurry() -> void:
	## Space, Enter or a click on the card: on to the next commander, once this one's die is down
	if _seat_live == "":
		return
	Audio.skip_voice()
	_seat_min = 0.0


func _seat_skip() -> void:
	## Esc: no more introductions. Whoever hasn't thrown throws now, all together.
	if _seat_rolling == "*":
		return ## (they already are)
	Audio.skip_voice()
	intro.leave()
	var left: Array = []
	if _seat_rolling != "" and _seat_rolling != "*":
		left.append(_seat_rolling) ## its die falls again with the rest (the same number)
	left.append_array(_seating)
	_seating = []
	_seat_live = ""
	_seat_rolling = ""
	if not _seat_dice or session.phase != Session.Phase.DRAFT:
		_seats_done()
		return
	var t: Array = session.draft["throws"][0]
	var specs: Array = []
	var who: Array = []
	for pid in left:
		var i: int = _throw_index(t, str(pid))
		if i >= 0:
			var sp: Dictionary = _die_spec(t, i)
			sp["delay"] = 0.09 * specs.size()
			specs.append(sp)
			who.append(i)
			_seated[str(pid)] = true
	_draft_strip()
	if specs.is_empty():
		_seats_done()
		return
	_seat_rolling = "*"
	Audio.sfx("dice_shake", -2.0)
	var dur: float = _draft_dice.throw(specs)
	get_tree().create_timer(dur + 0.15).timeout.connect(func():
		if session.phase != Session.Phase.DRAFT or _seat_rolling != "*":
			return
		for j in who.size():
			_draft_mark(str(t[int(who[j])]["pid"]), int(t[int(who[j])]["die"]), _draft_dice.die_screen(j))
		_seat_rolling = ""
		_seats_done())


func _seats_done() -> void:
	_seat_live = ""
	_seating = []
	intro.leave()
	if _seat_dice:
		## every commander has thrown: the tied throw again, or the order stands
		_seat_dice = false
		_draft_title.text = "ROLLING FOR THE ORDER OF CLAIMS"
		_draft_strip()
		_draft_after(0)
		return
	## a dealt war: on to the deployment
	_intro_done = true
	if session.phase == Session.Phase.OPENING:
		phase_banner("DEPLOYMENT", "Name your capital, then place your starting armies" if session.capital_choosable() else "Place your starting armies")
	_refresh()


func _seat_stop() -> void:
	## the phase moved on under them (a dealt war's deployment sealed early): the introductions are over
	_seating = []
	_seat_live = ""
	_seat_rolling = ""
	_seat_dice = false
	_intro_done = true
	intro.leave()


func _show_cash(pid: String, cards: Array, value: int) -> void:
	## v1.5: a set turned in: the cards fly up from the table into the commander's ring,
	## and everyone hears about it
	var to_p: Vector2 = size * Vector2(0.5, 0.3)
	if roster.faces.has(pid):
		var tf: Control = roster.faces[pid]
		to_p = tf.global_position - global_position + tf.size * 0.5
	for k in cards.size():
		var tr := TextureRect.new()
		tr.texture = Style.card_tex(str(cards[k]))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.size = Vector2(90, 128)
		tr.pivot_offset = tr.size * 0.5
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mid: Vector2 = size * Vector2(0.5, 0.45) + Vector2((float(k) - 1.0) * 96.0, 0) - tr.size * 0.5
		tr.position = mid + Vector2(0, 60)
		tr.rotation = (float(k) - 1.0) * 0.12
		tr.modulate.a = 0.0
		add_child(tr)
		var tw := create_tween()
		tw.tween_interval(0.08 * k)
		tw.tween_property(tr, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(tr, "position", mid, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.8)
		tw.tween_property(tr, "position", to_p - tr.size * 0.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(tr, "scale", Vector2(0.3, 0.3), 0.45)
		tw.parallel().tween_property(tr, "modulate:a", 0.0, 0.45).set_delay(0.2)
		tw.tween_callback(tr.queue_free)
	board_float_value(pid, value)
	var voice: String = str(session.seat(pid).get("portrait", ""))
	if session.is_human(pid):
		bar.advisor.react("happy", "cash_us", 3.0)
	else:
		if roster.faces.has(pid) and Lines.has(voice, "cash"):
			roster.faces[pid].react("win", "cash", 2.6)
		elif not session.living_humans().is_empty():
			bar.advisor.react("alarm", "cash_them", 3.0)


func board_float_value(pid: String, value: int) -> void:
	## "+N" rises over the commander's ring
	if not roster.faces.has(pid):
		return
	var tf: Control = roster.faces[pid]
	var l := Style.label("+%d" % value, 34, Style.GOLD, "display")
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = tf.global_position - global_position + Vector2(tf.size.x * 0.5 - 24, tf.size.y)
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(l, "position:y", l.position.y + 30.0, 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tw.tween_callback(l.queue_free)


func _throw_split(throws: Array) -> void:
	## v1.9: a war chest divided by the dice: each taker's die falls onto the map in their
	## colour, once the fallen commander's card has cleared the middle of the table
	if cutscene.visible:
		## a film is up (the fallen commander's, say): throw once it's done and their card has gone
		cutscene.done.connect(func(): _throw_split(throws), CONNECT_ONE_SHOT)
		return
	var wait: float = maxf(0.0, (_fallen_until - Time.get_ticks_msec()) / 1000.0)
	if wait > 0.05:
		get_tree().create_timer(wait).timeout.connect(func(): _throw_split_now(throws))
	else:
		_throw_split_now(throws)


func _throw_split_now(throws: Array) -> void:
	var stage: Control = DiceStage.new()
	stage.board = false
	stage.arrange = false
	stage.pitch = 66.0
	stage.width = 17.0
	stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stage.offset_bottom = -BAR
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	var specs: Array = []
	for i in throws.size():
		var x: float = (float(i) - float(throws.size() - 1) * 0.5) * 2.7
		specs.append({"value": int(throws[i]["value"]), "n": 9, "tint": Style.seat_color(str(throws[i]["pid"])), "to": Vector2(x, 0.6), "drop": true, "delay": 0.09 * i})
	Audio.sfx("dice_shake", -2.0)
	var dur: float = stage.throw(specs)
	var marks: Array = []
	get_tree().create_timer(dur + 0.1).timeout.connect(func():
		if not is_instance_valid(stage):
			return
		for i in throws.size():
			var pid: String = str(throws[i]["pid"])
			var l := Style.label("%s  %d" % [session.name_of(pid), int(throws[i]["value"])], 20, Style.seat_color(pid).lightened(0.5), "display")
			l.add_theme_constant_override("outline_size", 8)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(220, 30)
			l.position = stage.position + stage.die_screen(i) + Vector2(-110, 52)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(l)
			marks.append(l))
	get_tree().create_timer(dur + 2.6).timeout.connect(func():
		for m in marks:
			if is_instance_valid(m):
				(m as Node).queue_free()
		if is_instance_valid(stage):
			stage.queue_free())


func _show_war_chest(from_pid: String, to_pid: String, cards: Array) -> void:
	## the fallen commander's cards fly across the table to whoever took their last land;
	## if their fallen panel is still up, the cards spill out of it as it fades
	var wait: float = maxf(0.0, (_fallen_until - Time.get_ticks_msec()) / 1000.0)
	if wait > 0.05:
		_chest_taken = true
		get_tree().create_timer(wait).timeout.connect(func(): _fly_chest(from_pid, to_pid, cards, _fallen_at))
		return
	var from_p: Vector2 = size * Vector2(0.5, 0.35)
	if roster.faces.has(from_pid):
		var ff: Control = roster.faces[from_pid]
		from_p = ff.global_position - global_position + ff.size * 0.5
	_fly_chest(from_pid, to_pid, cards, from_p)


func _fly_chest(from_pid: String, to_pid: String, cards: Array, from_p: Vector2) -> void:
	if session.is_human(to_pid):
		bar.advisor.react("happy", "cards_seized", 3.2)
	Audio.sfx("war_chest", -4.0)
	var to_p: Vector2 = size * Vector2(0.5, 0.35)
	if roster.faces.has(to_pid):
		var tf: Control = roster.faces[to_pid]
		to_p = tf.global_position - global_position + tf.size * 0.5
	for k in cards.size():
		var tr := TextureRect.new()
		tr.texture = Style.card_tex(str(cards[k]))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.size = Vector2(84, 120)
		tr.pivot_offset = tr.size * 0.5
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.position = from_p - tr.size * 0.5
		tr.rotation = randf_range(-0.3, 0.3)
		tr.modulate.a = 0.0
		add_child(tr)
		var mid: Vector2 = size * Vector2(0.5, 0.42) + Vector2((float(k) - float(cards.size() - 1) * 0.5) * 70.0, 0) - tr.size * 0.5
		var tw := create_tween()
		tw.tween_interval(0.12 * k)
		tw.tween_property(tr, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(tr, "position", mid, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(tr, "scale", Vector2(1.35, 1.35), 0.45)
		tw.tween_interval(0.7)
		tw.tween_property(tr, "position", to_p - tr.size * 0.5, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(tr, "scale", Vector2(0.3, 0.3), 0.5)
		tw.parallel().tween_property(tr, "modulate:a", 0.0, 0.5).set_delay(0.3)
		tw.tween_callback(tr.queue_free)
	if roster.faces.has(to_pid):
		get_tree().create_timer(1.6).timeout.connect(func(): roster.faces[to_pid].react("win"))


# ================================================================ v1.12: the war around you

var _far_in := 12.0 ## seconds until the next far-off sound of the war


func _war_alive() -> void:
	## the lands fought over last round still smoke, and the light is the war's time of day
	var changed: Array = []
	if session.pre_world != null and session.world.round > 1:
		for t in session.world.territories.keys():
			var a: Types.TerritoryState = session.pre_world.get_territory(str(t))
			var b: Types.TerritoryState = session.world.get_territory(str(t))
			if a != null and b != null and a.owner != b.owner and b.owner != Types.UNOCCUPIED:
				changed.append(str(t))
	board.smolder(changed)
	board.set_daylight(war_light(war_progress()), session.world.round <= 1)


func war_progress() -> float:
	## how far into the war we are, 0 to 1: by the rounds, or in a conquest by the leader's
	## progress toward the lands that end it
	var f: float = float(session.world.round - 1) / float(maxi(1, session.rounds_total() - 1))
	if session.conquest():
		var thr: int = load("res://engine/setup.gd").early_end_threshold(session.map)
		var most := 0
		for st in session.seats:
			most = maxi(most, MapLib.player_territory_ids(session.world, str(st["id"])).size())
		f = float(most) / float(maxi(1, thr))
	return clampf(f, 0.0, 1.0)


static func war_light(f: float) -> Color:
	## a cool morning, a plain noon, a golden afternoon and a red dusk for the last rounds
	var keys := [[0.0, Color(0.9, 0.95, 1.0)], [0.35, Color(1, 1, 1)], [0.7, Color(1.0, 0.93, 0.8)], [1.0, Color(1.0, 0.72, 0.58)]]
	for k in range(1, keys.size()):
		if f <= float(keys[k][0]):
			var a: Array = keys[k - 1]
			var b: Array = keys[k]
			return (a[1] as Color).lerp(b[1] as Color, (f - float(a[0])) / (float(b[0]) - float(a[0])))
	return keys[-1][1]


func _far_off(delta: float) -> void:
	## the war beyond the tent while you plan: now and then a far cannon, volley, drum or
	## bugle, nearer and more often as the war heats up (the besieged and endgame moods)
	if session == null or session.world == null or (session.phase != Session.Phase.PLANNING and session.phase != Session.Phase.MANEUVER):
		return
	if cinema.visible or theater.visible:
		return
	_far_in -= delta
	if _far_in > 0.0:
		return
	var mood: String = _plan_mood()
	var hot: bool = mood != "plan"
	Audio.distant(randf_range(-17.0, -12.0) if hot else randf_range(-24.0, -18.0))
	_far_in = randf_range(9.0, 20.0) if hot else randf_range(22.0, 45.0)


func _hot_or(calm: String) -> String:
	## v1.13: the planning mood when the war is hot (besieged, endgame), else the phase's own theme
	var m: String = _plan_mood()
	return m if m != "plan" else calm


func _plan_mood() -> String:
	## v1.9: the planning music follows the war. Your capital under the guns: "besieged".
	## The last rounds, or someone near a conquest: "endgame". Otherwise the plan themes.
	for pid in session.living_humans():
		var cap: String = str(session.world.players[pid].capital) if session.world.players.has(pid) else ""
		if cap == "" or session.world.get_territory(cap) == null:
			continue
		var held: int = session.world.get_territory(cap).held()
		var worst := 0
		for n in MapLib.neighbors(session.map, cap):
			var ts: Types.TerritoryState = session.world.get_territory(str(n))
			if ts != null and ts.owner != pid and ts.owner != Types.UNOCCUPIED and ts.owner != "neutral":
				worst = maxi(worst, ts.armies)
		if worst >= maxi(3, held) and Audio.has_music("besieged"):
			return "besieged"
	var late: bool = not session.conquest() and session.world.round >= session.map.rounds - 1
	var near := false
	var thr: int = load("res://engine/setup.gd").early_end_threshold(session.map)
	for st in session.seats:
		if MapLib.player_territory_ids(session.world, str(st["id"])).size() >= int(ceil(thr * 0.85)):
			near = true
	if (late or near) and Audio.has_music("endgame"):
		return "endgame"
	return "plan"


func _start_intro() -> void:
	## v1.9: dawn in the war room on film, then the commanders take their seats. v2.4: the war's music,
	## and the tent's sounds, wait for the film to end or be skipped (the owner: "the in-game music begins
	## playing as soon as a new game is started over the sounds of the intro cutscene"); and the seats are
	## taken on the war table itself, each rival as their die falls for the order of claims (_seat_begin)
	var after := func():
		if is_queued_for_deletion():
			return
		Audio.ambience(true)
		Audio.music("plan")
		if session.phase == Session.Phase.DRAFT:
			_seats_due = true
			_intro_done = true
			_refresh() ## the roll begins (_draft_begin), and with it the introductions
		else:
			_seat_begin(false) ## a dealt war: the rivals step up before the deployment
	if _film("intro", "", "", after):
		Audio.music("", 0.8) ## the setup screen's music gives way to the film's own
		Audio.ambience(false)
		return
	after.call()


func _film(kind: String, caption: String, voice_key: String, then: Callable = Callable()) -> bool:
	## v1.9: play a cutscene if there is one (and Settings allow films), once a war; the report
	## waits for it. False: nothing played (the caller carries on as before).
	if _films_seen.has(kind) or not Cutscene.available(kind):
		return false
	_films_seen[kind] = true
	var was: bool = cinema.paused
	cinema.paused = true
	move_child(cutscene, get_child_count() - 1)
	cutscene.done.connect(func():
		cinema.paused = was
		if then.is_valid():
			then.call(), CONNECT_ONE_SHOT)
	if not cutscene.play(kind, caption, "advisor", voice_key):
		cinema.paused = was
		return false
	return true


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
	var n := Style.label(("%s fallen" % Style.says(session.name_of(pid), "has")).to_upper(), 28, Style.seat_color(pid).lightened(0.4), "display")
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
	_fallen_until = Time.get_ticks_msec() + 3700.0
	_fallen_at = card.position + card.size * 0.5
	_chest_taken = false
	face.react("dead", "eliminated", 3.5)
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.3)
	tw.tween_interval(3.4)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)
	if not session.is_human(pid) and not session.living_humans().is_empty():
		get_tree().create_timer(4.0).timeout.connect(func():
			if not _chest_taken:
				bar.advisor.react("happy", "enemy_out", 2.5))


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


func _lead_moment() -> void:
	## v1.13: a new leader on points is a moment. The recap says it at the top (recap.gd), the
	## flag snaps, and the advisor has his word when it's our lead won or lost.
	var lc: Dictionary = Moments.lead_change(session.history)
	if lc.is_empty() or session.winner != "":
		return
	Audio.sfx("banner", -4.0)
	var to: String = str(lc["to"])
	var from: String = str(lc.get("from", ""))
	if session.is_human(to):
		_say_once("leader", "happy")
		_was_leading = true
	elif from != "" and session.is_human(from):
		_say_once("behind", "alarm")
		_behind_said = session.world.round
		_was_leading = false


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
			var secs: float = Audio.voice(Lines.voice_path(who, "victory"))
			if any_human and secs > 0.0:
				## v1.13: then the advisor, for the table that lost (it never spoke when an AI won)
				get_tree().create_timer(secs + 0.6).timeout.connect(func(): Audio.voice(Lines.voice_path("advisor", "defeat")))
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
	_confirm(Recap.defeat_title(fell),
		"The commanders will fight on without you. Watch them finish the war, or leave the field.",
		[["Watch the rest", func(): pass], ["New game", func(): main.show_setup()], ["Main menu", func(): main.show_title()]])


# ================================================================ overlays

func _drop_planning_question() -> void:
	## v2.0.2: a question about one commander's planning goes with it (the turn's timer sealed the
	## orders with "5 recruits still unplaced" still up: it stayed over the whole battle report, and
	## in hotseat the next commander could answer it, placing their own recruits)
	if _modal != null and is_instance_valid(_modal) and _modal.has_meta("planning"):
		_modal.queue_free()
		_modal = null


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
	var after: int = int(session.get_meta("after_pass", 0))
	var what := "place your starting armies" if after == Session.Phase.OPENING else ("march your troops to the front" if after == Session.Phase.MANEUVER else "write your orders for round %d" % session.world.round)
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


var _toast_panel: Control ## v2.0: the toast showing (a new one takes its place: V then L never stack two)


func _toast(text: String) -> void:
	if _toast_panel != null and is_instance_valid(_toast_panel):
		_toast_panel.queue_free()
	var p := PanelContainer.new()
	_toast_panel = p
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


func _overlay_open() -> bool:
	## v1.14: a pause menu, a confirm, the settings, the rules, the cards or the advisor's plan is up
	if _modal != null or (main != null and main.settings_panel != null):
		return true
	for c in get_children():
		if c is PlanDialog or c is HowTo or c is CardsDialog:
			return true
	return false


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
		elif _seating_now():
			_seat_skip() ## v2.4: no more introductions
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
	elif _overlay_open():
		return ## v1.14: a dialog or page over the table takes the keys (the seal key sealed behind the pause menu)
	elif (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and _seat_live != "":
		_seat_hurry() ## v2.4: on to the next commander
		get_viewport().set_input_as_handled()
	elif (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and recap.visible and session.phase == Session.Phase.RECAP:
		## (not in its first moment: a Space still being pressed through the battles mustn't skip it unread)
		if Time.get_ticks_msec() - _recap_at > RECAP_KEY_MS:
			recap.continue_pressed.emit() ## v1.14: the round report goes on with the key that ran the battles
		get_viewport().set_input_as_handled()
	elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and (event.meta_pressed or event.ctrl_pressed):
		## v1.14: what the dial does (README: "SEAL on the dial (or ⌘↩)"): in the reinforcement step it
		## moves on to the orders, as the dial does, rather than sealing a sheet with none; and it
		## seals the regroup's marches too
		if session.phase in [Session.Phase.PLANNING, Session.Phase.OPENING, Session.Phase.MANEUVER]:
			primary_action()
		get_viewport().set_input_as_handled()
	elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and order_card.visible:
		order_done() ## OK: keep the order, close the card, let go of the land (v2.4)
		get_viewport().set_input_as_handled()
	elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and session.phase == Session.Phase.PLANNING and session.plan_step == "reinforce":
		begin_orders() ## v1.6: Enter moves on from the recruits to the orders
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_C and session.phase == Session.Phase.PLANNING and session.map.cards:
		open_cards() ## v1.6: C opens your cards
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_V and session.phase != Session.Phase.CINEMA:
		toggle_view()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_G and not event.meta_pressed and not event.ctrl_pressed:
		cycle_shields() ## v2.4: the garrison shields' looks, to compare
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_L and not event.meta_pressed and not event.ctrl_pressed:
		toggle_land() ## v2.0: the land or the chart
		get_viewport().set_input_as_handled()
