## The battlefield. One or more engagements at one land, played exchange by exchange.
## Every die shown is the engine's own roll from the event log — the theater only
## chooses when to reveal it. After each exchange of an assault the attacker calls:
## PRESS ON, throw in the RESERVES from home, or FALL BACK. A watching commander calls
## it here (the round is paused in the session until they do); everyone else's calls
## come from their sealed standing orders and are shown as they happen.
## Figures are Ludo tin soldiers tinted to each side: they march in, breathe, fire,
## fall, and — if it comes to that — turn and march away.
extends Control

const MapLib := preload("res://engine/map.gd")
const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const Lines := preload("res://game/core/lines.gd")
const Combat := preload("res://engine/combat.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")
const BattleField := preload("res://game/ui/battle_field.gd")
const DiceStage := preload("res://game/ui/dice_stage.gd")

signal finished(skip_rest: bool)

var session: Node
var manual := true ## wait for the commander between exchanges
var _beats: Array = []
var _bi := -1
var _rolls: Array = []
var _ri := 0
var _volley_mode := true
var _state := "idle" ## idle | ready | rolling | call | wait | done
var _auto_t := 0.0
var _a_left := 0
var _b_left := 0
var _a_pid := ""
var _b_pid := ""
var _spoken_attack := false
var _seen_calls := {} ## roll index -> true: calls already shown for this engagement
var _exchange := 0
var _advised := false
var _human := false

var _bg: TextureRect
var _title: Label
var _sub: Label
var _face_a: Control
var _face_b: Control
var _advisor: Control
var _count_a: Label
var _count_b: Label
var _name_a: Label
var _name_b: Label
var _field: Control ## BattleField
var _melee := false ## several invaders at once (v1.3): fronts, one per invader
var _scramble := false ## v1.4: victors fighting each other for the prize, every army against every other
var _fronts: Array = [] ## the melee's fronts from the event
var _left: Array = [] ## men standing per army: fronts (or the one attacker) first, the defender last
var _extra: Array = [] ## [{face, name, count}] rings for the second and third invaders
var _tray: Control ## DiceStage: the dice table at the foot of the field
var _reads: Array = [] ## this throw's readouts, one under each die
var _odds_bar: Control ## who the battle favours from here, and why
var _tier_a: Label
var _tier_b: Label
var _help: PanelContainer
var _score: Label
var _result: Label
var _shout: Label
var _dial: Control
var _progress: Label
var _auto_btn: Button
var _calls: HBoxContainer
var _odds: Label
var _btn_reserves: Button
var _btn_fall: Button
var _call_plate: PanelContainer
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	var shade := TextureRect.new()
	shade.texture = _shade_tex()
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_field = BattleField.new()
	_field.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_field.offset_top = 250
	_field.offset_bottom = -226
	_field.offset_left = 40
	_field.offset_right = -40
	add_child(_field)
	## title
	var tv := VBoxContainer.new()
	tv.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	tv.offset_top = 22
	tv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tv)
	_title = Style.label("", 40, Style.CREAM, "display")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	tv.add_child(_title)
	_sub = Style.label("", 20, Style.PARCH, "italic")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	tv.add_child(_sub)
	## the two commanders
	_face_a = LeaderFace.new()
	_face_a.bubble_side = "right"
	add_child(_face_a)
	_face_b = LeaderFace.new()
	_face_b.bubble_side = "left"
	add_child(_face_b)
	_name_a = _side_label(24)
	_name_b = _side_label(24)
	_count_a = _side_label(44)
	_count_b = _side_label(44)
	## the big shout across the field: RESERVES! / FALL BACK!
	_shout = Style.label("", 64, Style.GOLD, "display")
	_shout.set_anchors_and_offsets_preset(PRESET_CENTER)
	_shout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_shout.grow_vertical = Control.GROW_DIRECTION_BOTH
	_shout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shout.add_theme_constant_override("outline_size", 14)
	_shout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_shout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shout.modulate.a = 0.0
	add_child(_shout)
	## the dice table, at the foot of the field: the dice fly in over the armies and land on it
	_tray = DiceStage.new()
	_tray.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_tray.offset_top = -430
	_tray.offset_bottom = -100
	_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tray.width = 21.0
	_tray.table_w = 13.6
	_tray.ground_h = 124.0
	add_child(_tray)
	_result = Style.label("", 32, Style.CREAM, "display")
	_result.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	_result.offset_bottom = -246
	_result.offset_top = -290
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_constant_override("outline_size", 10)
	_result.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_result)
	## the odds from here, under the title: a tug of war between the colours
	_odds_bar = _OddsBar.new()
	_odds_bar.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	_odds_bar.offset_top = 104
	_odds_bar.offset_bottom = 162
	_odds_bar.offset_left = -300
	_odds_bar.offset_right = 300
	_odds_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_odds_bar)
	_score = Style.label("", 15, Style.PARCH, "italic")
	_score.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	_score.offset_top = 164
	_score.offset_bottom = 186
	_score.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_constant_override("outline_size", 6)
	_score.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_score)
	_tier_a = _side_label(15)
	_tier_b = _side_label(15)
	for tl in [_tier_a, _tier_b]:
		tl.add_theme_font_override("font", Style.font("italic"))
		tl.add_theme_color_override("font_color", Style.GOLD)
	_help = _dice_help()
	add_child(_help)
	## the battle call: a war-council plate above the dice when the commander must decide
	_call_plate = PanelContainer.new()
	_call_plate.add_theme_stylebox_override("panel", Style.flat(Color(0.07, 0.035, 0.025, 0.93), Color(Style.GOLD, 0.75), 2, 10, 14))
	_call_plate.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	_call_plate.offset_bottom = -300
	_call_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_call_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_call_plate.visible = false
	add_child(_call_plate)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 8)
	_call_plate.add_child(cv)
	_hint = Style.label("Your call, Commander: PRESS ON (Space), throw in the RESERVES still at home, or FALL BACK to save the men.", 16, Style.PARCH, "italic")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(_hint)
	_odds = Style.label("", 20, Style.CREAM, "bold")
	_odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_odds.add_theme_constant_override("outline_size", 7)
	_odds.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_odds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(_odds)
	_calls = HBoxContainer.new()
	_calls.alignment = BoxContainer.ALIGNMENT_CENTER
	_calls.add_theme_constant_override("separation", 16)
	cv.add_child(_calls)
	_btn_reserves = Style.chip("⚑ Reserves", func(): _answer(Combat.CALL_RESERVES), Style.GOLD, 19)
	_btn_reserves.custom_minimum_size = Vector2(250, 48)
	_calls.add_child(_btn_reserves)
	_btn_fall = Style.chip("↩ Fall back", func(): _answer(Combat.CALL_FALL_BACK), Style.PARCH, 19)
	_btn_fall.custom_minimum_size = Vector2(250, 48)
	_calls.add_child(_btn_fall)
	## controls
	var ctl := HBoxContainer.new()
	ctl.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	ctl.offset_bottom = -12
	ctl.offset_top = -92
	ctl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ctl.alignment = BoxContainer.ALIGNMENT_CENTER
	ctl.add_theme_constant_override("separation", 18)
	add_child(ctl)
	_auto_btn = Style.chip("Auto-roll ▶", func(): _set_manual(not manual), Style.CREAM, 16)
	_auto_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ctl.add_child(_auto_btn)
	_dial = load("res://game/ui/command_bar.gd")._Dial.new()
	_dial.custom_minimum_size = Vector2(96, 96)
	_dial.size = Vector2(96, 96)
	_dial.pressed.connect(func(): press())
	ctl.add_child(_dial)
	var dh := Style.chip("? Dice", func(): _toggle_help(), Style.PARCH, 15)
	dh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dh.tooltip_text = "How a throw is scored, and why big armies roll finer dice"
	ctl.add_child(dh)
	var skip := Style.chip("Skip battles ▶▶", func(): _skip(), Style.PARCH, 16)
	skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip.tooltip_text = "Settle this round's remaining battles on the map (your standing orders decide the calls)"
	ctl.add_child(skip)
	## the chief of staff, at your elbow
	_advisor = LeaderFace.new()
	_advisor.bubble_side = "top" ## above his ring, clear of the dice table
	_advisor.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	_advisor.offset_left = 18
	_advisor.offset_top = -176
	_advisor.offset_right = 138
	_advisor.offset_bottom = -56
	add_child(_advisor)
	_progress = Style.label("", 16, Style.PARCH, "italic")
	_progress.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	_progress.offset_left = 24
	_progress.offset_top = -40
	_progress.add_theme_constant_override("outline_size", 5)
	_progress.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_progress)
	resized.connect(_layout)


func _side_label(sz: int) -> Label:
	var l := Style.label("", sz, Style.CREAM, "display")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _layout() -> void:
	var w: float = size.x
	_face_a.position = Vector2(46, 24)
	_face_a.size = Vector2(170, 170)
	_face_b.position = Vector2(w - 216, 24)
	_face_b.size = Vector2(170, 170)
	_name_a.position = Vector2(10, 192)
	_name_a.size = Vector2(242, 30)
	_name_b.position = Vector2(w - 252, 192)
	_name_b.size = Vector2(242, 30)
	_count_a.position = Vector2(10, 222)
	_count_a.size = Vector2(242, 56)
	_count_b.position = Vector2(w - 252, 222)
	_count_b.size = Vector2(242, 56)
	_tier_a.position = Vector2(10, 274)
	_tier_a.size = Vector2(242, 22)
	_tier_b.position = Vector2(w - 252, 274)
	_tier_b.size = Vector2(242, 22)


func _shade_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.05, 0.78))
	g.set_color(1, Color(0.02, 0.03, 0.05, 0.82))
	g.add_point(0.3, Color(0.02, 0.03, 0.05, 0.12))
	g.add_point(0.7, Color(0.02, 0.03, 0.05, 0.2))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.5, 0)
	t.fill_to = Vector2(0.5, 1)
	t.width = 8
	t.height = 256
	return t


# ------------------------------------------------------------------ flow

# ------------------------------------------------------------------ flow

func play(p_session: Node, beats: Array, human_involved: bool) -> void:
	session = p_session
	_beats = beats
	_bi = -1
	_spoken_attack = false
	_human = human_involved
	manual = human_involved and bool(Settings.get_value("roll_yourself", true))
	_auto_btn.text = "Auto-roll ▶" if manual else "Roll myself ✋"
	_layout()
	_advisor.visible = human_involved
	if human_involved:
		_advisor.setup("advisor", "", "Chief of Staff")
	visible = true
	## the camera has swooped down on the map; the field opens out of it
	modulate.a = 0.0
	pivot_offset = size * 0.5
	scale = Vector2(1.1, 1.1)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.35)
	tw.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Audio.ambience(true, "ambience_battle")
	Audio.music("charge")
	Audio.sfx("charge", -3.0)
	## the scoring rules for this game's battles (the firing line is per game)
	_help.queue_free()
	_help = _dice_help()
	add_child(_help)
	## the first two times you watch, the scoring rules open beside the table on their own
	_help.visible = false
	var seen: int = int(Settings.get_value("dice_help_seen", 0))
	if human_involved and seen < 2:
		Settings.remember("dice_help_seen", seen + 1)
		_help.visible = true
		get_tree().create_timer(9.0).timeout.connect(func(): _help.visible = false)
	_next_engagement()


func extend(beats: Array) -> void:
	## The session resolved further after a call: same fights, longer log.
	_beats = beats
	if _bi >= 0 and _bi < _beats.size():
		var e: Dictionary = _beats[_bi]["event"]
		_rolls = e.get("salvos", []) if _melee else e.get("rolls", [])
		if _melee:
			_fronts = e.get("fronts", [])


func _set_manual(m: bool) -> void:
	manual = m
	_auto_btn.text = "Auto-roll ▶" if manual else "Roll myself ✋"
	_auto_t = 0.2
	if not manual and _state == "call":
		_call_plate.visible = false


func _skip() -> void:
	_close(true)


func abort() -> void:
	## Closed from outside (the whole report was skipped): no signal, no fade.
	_state = "idle"
	visible = false
	scale = Vector2.ONE
	_face_a.hush()
	_face_b.hush()
	_advisor.hush()
	Audio.ambience(true, "ambience_tent")
	Audio.music("battle")


func _close(skip_rest: bool) -> void:
	_state = "idle"
	_call_plate.visible = false
	Audio.ambience(true, "ambience_tent")
	Audio.music("battle")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		visible = false
		scale = Vector2.ONE
		_face_a.hush()
		_face_b.hush()
		_advisor.hush()
		finished.emit(skip_rest))


func press() -> void:
	match _state:
		"ready":
			_roll_exchange()
		"call":
			_answer(Combat.CALL_PRESS)
		"done":
			_next_engagement()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_SPACE or e.keycode == KEY_ENTER:
			press()
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_R and _state == "call" and not _btn_reserves.disabled:
			_answer(Combat.CALL_RESERVES)
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_F and _state == "call" and not _btn_fall.disabled:
			_answer(Combat.CALL_FALL_BACK)
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_ESCAPE:
			_skip()
			get_viewport().set_input_as_handled()


var _bed_t := 3.0 ## the battle beyond this one: now and then, far off and quiet


func _process(delta: float) -> void:
	if not visible:
		return
	_bed_t -= delta
	if _bed_t <= 0.0:
		_bed_t = randf_range(4.5, 9.0)
		Audio.sfx("far", randf_range(-21.0, -16.0), 0.06)
	if _state == "ready" and not manual:
		_auto_t -= delta
		if _auto_t <= 0.0:
			_roll_exchange()
	elif _state == "call" and not manual:
		_auto_t -= delta
		if _auto_t <= 0.0:
			_answer(session.officer_call())
	elif _state == "done":
		_auto_t -= delta
		if _auto_t <= 0.0 and not manual:
			_next_engagement()


func _event() -> Dictionary:
	return _beats[_bi]["event"] if _bi >= 0 and _bi < _beats.size() else {}


func _fort_bonus() -> int:
	## v1.7: the bar has to quote the odds of the land actually being fought over, and in a
	## fortress the defenders fire a longer line.
	if _bi < 0 or _bi >= _beats.size() or session == null:
		return 0
	return MapLib.defender_line_bonus(session.map, str(_beats[_bi].get("resolves", "")))


func _def() -> int:
	## the defender's army index on the field
	return _left.size() - 1


func _next_engagement() -> void:
	_bi += 1
	if _bi >= _beats.size():
		_close(false)
		return
	var b: Dictionary = _beats[_bi]
	var e: Dictionary = b["event"]
	var kind: String = str(e["kind"])
	var land: String = str(b.get("resolves", ""))
	if land == "":
		land = str((b.get("focus", [""]) as Array)[0])
	_melee = kind == Types.EVENT_MELEE
	_scramble = kind == Types.EVENT_SCRAMBLE
	_seen_calls = {}
	_exchange = 0
	_advised = false
	_ri = 0
	_call_plate.visible = false
	var list: Array = []
	if _melee:
		_fronts = e.get("fronts", [])
		_rolls = e.get("salvos", [])
		_volley_mode = true
		_left = []
		for f in _fronts:
			list.append({"pid": str(f["attackerId"]), "side": 0, "n": int(f["size"])})
			_left.append(int(f["size"]))
		list.append({"pid": str(e["defenderId"]), "side": 1, "n": int(e["defenderSize"])})
		_left.append(int(e["defenderSize"]))
		## the lead ring goes to a watching commander if there is one
		_a_pid = str(b["a"])
		_b_pid = str(e["defenderId"])
	elif _scramble:
		## no defender: every army against every other, split either side of the field
		_fronts = e.get("fronts", [])
		_rolls = e.get("salvos", [])
		_volley_mode = true
		_left = []
		for i in _fronts.size():
			list.append({"pid": _front_pid(i), "side": i % 2, "n": int(_fronts[i]["size"])})
			_left.append(int(_fronts[i]["size"]))
		_a_pid = str(b["a"])
		_b_pid = _front_pid(_b_front())
	else:
		_fronts = []
		_a_pid = str(b["a"])
		_b_pid = str(b["b"])
		_rolls = e.get("rolls", [])
		_volley_mode = not _rolls.is_empty() and (_rolls[0] as Dictionary).has("sa")
		_left = [int(b["a_size"]), int(b["b_size"])]
		list = [{"pid": _a_pid, "side": 0, "n": _left[0]}, {"pid": _b_pid, "side": 1, "n": _left[1]}]
	_a_left = _left[0]
	_b_left = _left[_def()] if not _scramble else _left[_b_front()]
	## the ground under this fight
	var region: String = session.map.get_territory(land).region if land != "" else ""
	var terrain: String = str(session.map.region_terrain.get(region, "grass"))
	_bg.texture = Style.tex("res://assets/battle/field_%s.webp" % terrain)
	_title.text = str(b["caption"]).to_upper()
	match kind:
		"Clash":
			_sub.text = "Border clash! Both columns march at once and meet in the field — no retreat"
		"Spoils":
			_sub.text = "Two invaders, one prize — no retreat"
		Types.EVENT_MELEE:
			_sub.text = "%d armies storm it at once — the defenders must hold every front" % _fronts.size()
		Types.EVENT_SCRAMBLE:
			_sub.text = "%d armies, one prize — every man for himself" % _fronts.size()
		_:
			_sub.text = "%s from %s" % [Style.says(session.name_of(_a_pid), "attacks"), session.hex_name(str(e.get("from", "")))]
	_setup_side(_face_a, _name_a, _melee_lead_pid() if (_melee or _scramble) else _a_pid, true)
	_setup_side(_face_b, _name_b, _b_pid, false)
	_setup_extras()
	_update_counts()
	_field.setup(list)
	_result.text = ""
	if _melee:
		_score.text = "Every front throws at once: pips × 5 + its men, against pips × 5 + the defenders' share of the wall there."
	elif _scramble:
		_score.text = "Every army duels every other at once, its men split among its foes: pips × 5 + men. Last army standing takes it."
	elif _volley_mode and Combat.line > 0:
		_score.text = "Each volley: pips × 5 + the men firing (at most %d a side). The higher total wins; the loser loses a man; an even volley is fired again." % Combat.line
	elif _volley_mode:
		_score.text = "Each volley: pips × 5 + men standing, both sides. The higher total wins; the loser loses a man."
	else:
		_score.text = "One throw: men + pips. The higher total wins."
	_clear_dice()
	_update_odds()
	_progress.text = "Battle %d of %d at this land" % [_bi + 1, _beats.size()] if _beats.size() > 1 else ""
	if not _spoken_attack:
		_spoken_attack = true
		var who: String = _who(_melee_lead_pid() if (_melee or _scramble) else _a_pid)
		if Lines.has(who, "attack"):
			_face_a.react("win", "attack", 2.4)
		else:
			_face_a.react("happy")
		if _melee:
			Audio.sfx("melee", -4.0)
			if _advisor.visible:
				get_tree().create_timer(1.2).timeout.connect(func(): _advisor.react("alarm", "melee", 3.0))
	if _scramble:
		Audio.sfx("melee", -5.0)
		if _advisor.visible:
			get_tree().create_timer(0.8).timeout.connect(func(): _advisor.react("alarm", "scramble", 3.2))
	_state = "ready"
	_auto_t = 1.4 ## let them march in
	_dial.set_label("ROLL", "Space")


func _melee_lead_pid() -> String:
	return _front_pid(_lead_front()) if not _fronts.is_empty() else _a_pid


func _front_pid(i: int) -> String:
	var f: Dictionary = _fronts[i]
	return str(f.get("attackerId", f.get("playerId", "")))


func _lead_front() -> int:
	for i in _fronts.size():
		if _front_pid(i) == _a_pid:
			return i
	return 0


func _b_front() -> int:
	## the scramble's second ring: the first army that isn't the lead
	var lead: int = _lead_front()
	for i in _fronts.size():
		if i != lead:
			return i
	return 0


func _army_of_front(i: int) -> int:
	return i


func _setup_extras() -> void:
	## rings for the other invaders in a melee, beside the lead one
	for x in _extra:
		(x["face"] as Control).queue_free()
		(x["name"] as Control).queue_free()
		(x["count"] as Control).queue_free()
	_extra = []
	if not _melee and not _scramble:
		return
	var k := 0
	for i in _fronts.size():
		if i == _lead_front() or (_scramble and i == _b_front()):
			continue
		var pid: String = _front_pid(i)
		var face: Control = LeaderFace.new()
		face.bubble_side = "bottom"
		face.position = Vector2(236 + k * 138, 40)
		face.size = Vector2(124, 124)
		add_child(face)
		face.setup(_who(pid), pid, session.name_of(pid))
		var nm := _side_label(18)
		nm.text = session.name_of(pid)
		nm.add_theme_color_override("font_color", Style.seat_color(pid).lightened(0.45))
		nm.position = Vector2(206 + k * 138, 164)
		nm.size = Vector2(184, 26)
		var ct := _side_label(34)
		ct.position = Vector2(206 + k * 138, 188)
		ct.size = Vector2(184, 44)
		_extra.append({"face": face, "name": nm, "count": ct, "front": i})
		k += 1


func _face_of_front(i: int) -> Control:
	if (not _melee and not _scramble) or i == _lead_front():
		return _face_a
	if _scramble and i == _b_front():
		return _face_b
	for x in _extra:
		if int(x["front"]) == i:
			return x["face"]
	return _face_a


func _who(pid: String) -> String:
	if pid == "neutral" or pid == "":
		return "player"
	return str(session.seat(pid).get("portrait", "player"))


func _setup_side(face: Control, name_l: Label, pid: String, left: bool) -> void:
	var nm: String = session.name_of(pid) if pid != "neutral" else "Neutral garrison"
	face.setup(_who(pid), pid, nm)
	face.scale = Vector2.ONE
	face.rotation = 0.0
	face.modulate = Color(1, 1, 1)
	face.set_dead(false)
	name_l.text = nm
	name_l.add_theme_color_override("font_color", Style.seat_color(pid).lightened(0.45))
	## long imperial titles shrink to fit under the ring
	var fs := 24
	while fs > 13 and Style.font("display").get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 226.0:
		fs -= 1
	name_l.add_theme_font_size_override("font_size", fs)
	name_l.size = Vector2(242, 30) ## a label grows to its text; pin it back under the ring


func _update_counts() -> void:
	var na: int = maxi(0, _a_left)
	var nb: int = maxi(0, _b_left)
	if _melee or _scramble:
		na = maxi(0, int(_left[_lead_front()]))
		for x in _extra:
			(x["count"] as Label).text = str(maxi(0, int(_left[int(x["front"])])))
		if _scramble:
			nb = maxi(0, int(_left[_b_front()]))
	_count_a.text = str(na)
	_count_b.text = str(nb)
	## the dice each side throws, by the men it has left
	_tier_a.text = (DiceStage.tier_name(na) + " dice") if na > 0 else ""
	_tier_b.text = (DiceStage.tier_name(nb) + " dice") if nb > 0 else ""


func _clear_dice() -> void:
	_tray.clear()
	for r in _reads:
		(r as Node).queue_free()
	_reads = []


func _roll_exchange() -> void:
	if _ri >= _rolls.size():
		_after_exchange()
		return
	_state = "rolling"
	_call_plate.visible = false
	_dial.set_label("…", "")
	## one exchange: three volleys thrown together (a melee or scramble: three salvos,
	## one throw each; the decisive style: its one throw)
	var throws: Array = []
	if _melee or _scramble:
		## salvos share a throw while it holds four duels or fewer, so a two-army scramble
		## throws three pairs at once like any exchange, and a three-way melee one salvo a throw
		var n := 0
		var cur: Array = []
		while _ri < _rolls.size() and n < Combat.EXCHANGE:
			var salvo: Array = _rolls[_ri]
			if not cur.is_empty() and cur.size() + salvo.size() > 4:
				throws.append(cur)
				cur = []
			cur.append_array(salvo)
			_ri += 1
			n += 1
		if not cur.is_empty():
			throws.append(cur)
	elif _volley_mode:
		var chunk: Array = []
		var decided := 0
		while _ri < _rolls.size() and decided < Combat.EXCHANGE:
			chunk.append(_rolls[_ri])
			_ri += 1
			if str(chunk[-1].get("w", "")) != "":
				decided += 1
		throws.append(chunk)
	else:
		throws.append([_rolls[-1]])
		_ri = _rolls.size()
	## the dice keep the battle speed from Settings (and hurry a little when they roll themselves)
	var sp: float = clampf(1.4 / maxf(0.3, Settings.battle_delay()), 0.8, 1.8) * (1.0 if manual else 1.3)
	_tray.pace = sp
	_tray.gravity = 34.0 * sp
	Audio.sfx("dice_shake", -4.0)
	get_tree().create_timer(0.3 if manual else 0.18).timeout.connect(func(): _next_throw(throws, 0))


func _next_throw(throws: Array, k: int) -> void:
	if not visible or _state != "rolling":
		return
	if k >= throws.size():
		_after_exchange()
		return
	var pairs: Array = _pairs_of(throws[k])
	_clear_dice()
	var specs: Array = []
	var m: int = pairs.size()
	var span: float = minf(3.6, 12.6 / float(maxi(1, m)))
	for i in m:
		var pr: Dictionary = pairs[i]
		var cx: float = (float(i) - float(m - 1) * 0.5) * span
		var zl: float = -0.35 + randf_range(-0.12, 0.12)
		specs.append({"value": int(pr["lv"]), "n": int(pr["ln"]), "tint": Style.seat_color(str(pr["lp"])), "to": Vector2(cx - 0.72, zl),
			"from": Vector3(-11.0, 2.6 + randf() * 0.6, randf_range(-1.0, 0.4)), "delay": 0.05 * i})
		specs.append({"value": int(pr["rv"]), "n": int(pr["rn"]), "tint": Style.seat_color(str(pr["rp"])), "to": Vector2(cx + 0.72, -0.35 + randf_range(-0.12, 0.12)),
			"from": Vector3(11.0, 2.6 + randf() * 0.6, randf_range(-1.0, 0.4)), "delay": 0.03 + 0.05 * i})
	var dur: float = _tray.throw(specs)
	get_tree().create_timer(dur + 0.05).timeout.connect(func(): _reveal(pairs, 0, func(): _next_throw(throws, k + 1)))


func _pairs_of(r: Variant) -> Array:
	## The duels in one throw, left die against right die, with the sums each side made.
	##   l*/r*: pid, pip value, men (picks the dice), what the men count for; w: "a" left won,
	##   "b" right won, "" tie; la/ra: the army index on the field
	var out: Array = []
	if _scramble:
		for v in r:
			var i: int = int(v["i"])
			var j: int = int(v["j"])
			out.append({"lp": _front_pid(i), "lv": int(v["a"]), "ln": int(_left[i]), "lw": float(v["si"]), "la": i,
				"rp": _front_pid(j), "rv": int(v["b"]), "rn": int(_left[j]), "rw": float(v["sj"]), "ra": j, "w": str(v.get("w", ""))})
	elif _melee:
		for v in r:
			var fi: int = int(v["i"])
			out.append({"lp": _front_pid(fi), "lv": int(v["a"]), "ln": int(v["sa"]), "lw": float(v.get("fa", v["sa"])), "la": fi,
				"rp": _b_pid, "rv": int(v["b"]), "rn": int(_left[_def()]), "rw": float(v.get("fd", v["sd"])), "ra": _def(), "w": str(v.get("w", ""))})
	elif _volley_mode:
		## v1.6: the men term is the firing line (fa/fd), at most five
		for v in r:
			out.append({"lp": _a_pid, "lv": int(v["a"]), "ln": int(v["sa"]), "lw": float(v.get("fa", v["sa"])), "la": 0,
				"rp": _b_pid, "rv": int(v["b"]), "rn": int(v["sd"]), "rw": float(v.get("fd", v["sd"])), "ra": _def(), "w": str(v.get("w", ""))})
	else:
		var bt: Dictionary = _beats[_bi]
		var last: Dictionary = r[0]
		var a_won: bool = bool(bt["a_won"])
		out.append({"lp": _a_pid, "lv": int(last["a"]), "ln": int(bt["a_size"]), "lw": float(bt["a_size"]), "la": 0,
			"rp": _b_pid, "rv": int(last["b"]), "rn": int(bt["b_size"]), "rw": float(bt["b_size"]), "ra": 1, "w": "a" if a_won else "b", "decisive": true})
	return out


func _reveal(pairs: Array, k: int, done: Callable) -> void:
	## the dice are down: settle each duel in turn, left to right
	if not visible or _state != "rolling":
		return
	if k >= pairs.size():
		done.call()
		return
	_settle_pair(pairs[k], k)
	var gap: float = (0.34 if manual else 0.24) if pairs.size() <= 3 else 0.2
	get_tree().create_timer(gap).timeout.connect(func(): _reveal(pairs, k + 1, done))


func _num(x: float) -> String:
	return str(int(x)) if absf(x - round(x)) < 0.05 else "%.1f" % x


func _settle_pair(pr: Dictionary, k: int) -> void:
	var w: String = str(pr["w"])
	var dec: bool = bool(pr.get("decisive", false))
	var sl: float = (float(pr["lv"]) + float(pr["lw"])) if dec else (5.0 * float(pr["lv"]) + float(pr["lw"]))
	var sr: float = (float(pr["rv"]) + float(pr["rw"])) if dec else (5.0 * float(pr["rv"]) + float(pr["rw"]))
	var tl: String = ("%s + %d = %s" % [_num(float(pr["lw"])), int(pr["lv"]), _num(sl)]) if dec else ("%d×5 + %s = %s" % [int(pr["lv"]), _num(float(pr["lw"])), _num(sl)])
	var tr: String = ("%s + %d = %s" % [_num(float(pr["rw"])), int(pr["rv"]), _num(sr)]) if dec else ("%d×5 + %s = %s" % [int(pr["rv"]), _num(float(pr["rw"])), _num(sr)])
	_read(k * 2, tl, w == "a", w == "")
	_read(k * 2 + 1, tr, w == "b", w == "")
	if w == "":
		_tray.mark(k * 2, "tie")
		_tray.mark(k * 2 + 1, "tie")
		_float_at(k * 2, "tie!", Style.PARCH)
		return
	_tray.mark(k * 2, "win" if w == "a" else "lose")
	_tray.mark(k * 2 + 1, "win" if w == "b" else "lose")
	if dec:
		return ## the decisive throw's losses land all at once (_after_exchange)
	var la: int = int(pr["la"])
	var ra: int = int(pr["ra"])
	var winner_army: int = la if w == "a" else ra
	var loser_army: int = ra if w == "a" else la
	_left[loser_army] = int(_left[loser_army]) - 1
	_float_at(k * 2 + (1 if w == "a" else 0), "−1", Style.CRIMSON.lightened(0.35))
	var sound: String = _field.volley(winner_army)
	_field.set_count(loser_army, maxi(0, int(_left[loser_army])))
	if _scramble:
		_flinch(_face_of_front(loser_army))
	elif loser_army == _def():
		_flinch(_face_b)
	else:
		_flinch(_face_of_front(loser_army) if _melee else _face_a)
	_a_left = int(_left[0])
	_b_left = int(_left[_def()]) if not _scramble else int(_left[_b_front()])
	_update_counts()
	_update_odds()
	Audio.sfx(sound, -1.5 if sound == "volley" or sound == "shot" else -3.0, 0.08)
	get_tree().create_timer(0.12).timeout.connect(func(): Audio.sfx("hit", -9.0, 0.15))


func _read(i: int, text: String, won: bool, tie: bool) -> void:
	## the sum a die made, written on the felt in front of it
	var l := Style.label(text, 17, Style.CREAM, "bold")
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_color", Style.GOLD if won else (Style.PARCH if tie else Color(0.85, 0.55, 0.5)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(170, 24)
	## the two sums of a duel lean away from each other, so they never overlap
	var at: Vector2 = _tray.position + _tray.die_screen(i)
	var mate: Vector2 = _tray.position + _tray.die_screen(i + 1 if i % 2 == 0 else i - 1)
	var mid: float = (at.x + mate.x) * 0.5
	if i % 2 == 0:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.position = Vector2(mid - 6.0 - l.size.x, at.y + 28)
	else:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = Vector2(mid + 6.0, at.y + 28)
	add_child(l)
	_reads.append(l)
	l.modulate.a = 0.0
	create_tween().tween_property(l, "modulate:a", 1.0, 0.12)


func _float_at(i: int, text: String, col: Color) -> void:
	var l := Style.label(text, 26, col, "display")
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at: Vector2 = _tray.position + _tray.die_screen(i)
	l.position = at + Vector2(-16, -64)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 34.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _update_odds() -> void:
	## who this fight favours from here, in plain numbers
	var bar: _OddsBar = _odds_bar
	if not _volley_mode and not _melee:
		bar.show_odds(-1.0, _a_pid, _b_pid, "", "")
		return
	if _scramble:
		var bits: Array = []
		for i in _fronts.size():
			if int(_left[i]) > 0:
				bits.append("%s %d" % [session.name_of(_front_pid(i)), int(_left[i])])
		bar.show_odds(-1.0, _a_pid, _b_pid, "Last army standing takes it", "  ·  ".join(bits))
		return
	var a := 0
	if _melee:
		for i in _fronts.size():
			if not _fled(i):
				a += maxi(0, int(_left[i]))
	else:
		a = maxi(0, int(_left[0]))
	var d: int = maxi(0, int(_left[_def()]))
	var land0: String = session.hex_name(str(_beats[_bi].get("resolves", ""))) if _bi >= 0 else ""
	if a <= 0 or d <= 0:
		## decided: the bar goes all the way, and says so (it used to keep the last odds)
		var taken: bool = d <= 0
		var winner0: String = (_melee_lead_pid() if _melee else _a_pid) if taken else _b_pid
		var wn: String = session.name_of(winner0) if winner0 != "neutral" else "The garrison"
		var what: String = ("%s %s" % [Style.says(wn, "takes"), land0]) if _event_kind() == Types.EVENT_INVASION or _melee else ("%s the field" % Style.says(wn, "wins"))
		if not taken and (_event_kind() == Types.EVENT_INVASION or _melee):
			what = "%s %s" % [Style.says(wn, "holds"), land0]
		bar.show_odds(1.0 if taken else 0.0, _melee_lead_pid() if _melee else _a_pid, _b_pid, what, "Decided.")
		return
	var ties: bool = _event_kind() == Types.EVENT_INVASION or _melee
	var p: float = Combat.volley_capture_rate(a, d, ties, _fort_bonus())
	var land: String = session.hex_name(str(_beats[_bi].get("resolves", ""))) if _bi >= 0 else ""
	var head: String
	var who: String = session.name_of(_melee_lead_pid() if _melee else _a_pid)
	if _melee:
		head = "All the attackers together: %d%% to take %s" % [int(round(p * 100.0)), land]
	elif _event_kind() == Types.EVENT_INVASION:
		head = "%s: %d%% to take %s" % [who, int(round(p * 100.0)), land]
	else:
		head = "%s: %d%% to win the field" % [who, int(round(p * 100.0))]
	var diff: int = a - d
	var edge: String
	var men := func(n: int) -> String: return Style.plural(n, "man", "men")
	var tie_note: String = "  ·  ties go to the attacker" if ties and not _melee and not Combat.fair_ties else ""
	var fa0: int = Combat.fire(a)
	var fd0: int = Combat.fire(d, _fort_bonus()) ## v1.7: a fortress's defenders fire a longer line
	if Combat.line > 0 and not _melee:
		## v1.6: what the firing line means right now
		if fa0 == fd0:
			var deeper: String = who if a > d else (session.name_of(_b_pid) if _b_pid != "neutral" else "The garrison")
			edge = "%s against %d: both fire a full line of %d, so every volley is even" % [men.call(a), d, fa0]
			if a != d:
				edge += "; %s %d more to lose" % [Style.says(deeper, "has"), absi(a - d)]
		else:
			var strong: String = who if fa0 > fd0 else (session.name_of(_b_pid) if _b_pid != "neutral" else "The garrison")
			edge = "%s against %d: %d fire against %d, and %s every tied pip" % [men.call(a), d, maxi(fa0, fd0), mini(fa0, fd0), Style.says(strong, "wins")]
			if fd0 > Combat.LINE:
				edge += " (the fortress fires a line of %d)" % fd0
		bar.show_odds(p, _a_pid, _b_pid, head, edge)
		return
	if _melee:
		edge = "%d attackers on %d fronts against %d defenders, who must split themselves across every front" % [a, _fronts_up(), d]
	elif diff == 0:
		edge = "%s against %d: even numbers, the dice decide%s" % [men.call(a), d, tie_note]
	else:
		var side: String = who if diff > 0 else (session.name_of(_b_pid) if _b_pid != "neutral" else "The garrison")
		var pips: float = absf(float(diff)) / 5.0
		edge = "%s against %d: %s with a %d-man edge (%s pip%s on every throw)%s" % [men.call(a), d, Style.says(side, "throws"), absi(diff), _num(pips), "" if absf(pips - 1.0) < 0.05 else "s", tie_note]
	bar.show_odds(p, _melee_lead_pid() if _melee else _a_pid, _b_pid, head, edge)


func _fronts_up() -> int:
	var n := 0
	for i in _fronts.size():
		if int(_left[i]) > 0 and not _fled(i):
			n += 1
	return n


func _event_kind() -> String:
	return str(_event().get("kind", ""))


func _dice_help() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Style.flat(Color(0.06, 0.04, 0.03, 0.94), Color(Style.GOLD, 0.7), 2, 10, 14))
	pc.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	pc.offset_right = -18
	pc.offset_bottom = -104
	pc.offset_left = -400
	pc.offset_top = -420
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.visible = false
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	v.add_child(Style.label("HOW A THROW IS SCORED", 18, Style.GOLD, "display"))
	var rule_txt: String = "Each side throws a die. Its pips count five men apiece; add the men in the firing line, at most five a side. The higher total wins the volley and the loser loses a man; an even volley is fired again.\n\nA big army can't win every volley: only its front rank fires. It wins by staying power, able to lose men long after the other side is gone. Numbers still tell: a lone holdout firing one man against five needs a miracle." if Combat.line > 0 else "Each side throws a die. Its pips count five men apiece; add the men still standing. The higher total wins the volley and the loser loses a man.\n\nSo every five men you bring is worth a whole pip on every throw — a big army wins most volleys even on a bad roll, and a lone holdout needs a miracle."
	var t := Style.label(rule_txt, 14, Style.CREAM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(360, 0)
	v.add_child(t)
	v.add_child(Style.label("THE DICE AN ARMY THROWS", 15, Style.GOLD, "display"))
	var names := ["whittled wood, burnt pips", "old bone", "ivory, enamel pips in its colours", "lacquer in its colours, brass edges", "gold, gem pips and the imperial star"]
	for i in DiceStage.TIERS.size():
		var tdef: Dictionary = DiceStage.TIERS[i]
		var hi: int = int(DiceStage.TIERS[i + 1]["min"]) - 1 if i + 1 < DiceStage.TIERS.size() else -1
		var rng: String = ("%d–%d men" % [int(tdef["min"]), hi]) if hi > int(tdef["min"]) else (("%d+ men" % int(tdef["min"])) if hi < 0 else "%d men" % int(tdef["min"]))
		var row := Style.label("%s  (%s): %s" % [str(tdef["name"]), rng, names[i]], 13, Style.PARCH, "italic")
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(360, 0)
		v.add_child(row)
	return pc


func _toggle_help() -> void:
	_help.visible = not _help.visible


func _flinch(face: Control) -> void:
	## the commander who just lost a man winces in the ring
	var tw := create_tween()
	tw.tween_property(face, "rotation", 0.06, 0.04)
	tw.tween_property(face, "rotation", -0.05, 0.05)
	tw.tween_property(face, "rotation", 0.0, 0.05)
	var m: Color = face.modulate
	face.modulate = Color(1.25, 0.8, 0.8)
	create_tween().tween_property(face, "modulate", m, 0.3)


func _after_exchange() -> void:
	if not _volley_mode:
		## the decisive roll: reveal totals, then the loser falls and the winner bleeds
		var b: Dictionary = _beats[_bi]
		var a_won: bool = bool(b["a_won"])
		var left: int = int(b["left"])
		_a_left = left if a_won else 0
		_b_left = 0 if a_won else left
		Audio.sfx("cannon", -4.0)
		_field.volley(0 if a_won else 1)
		get_tree().create_timer(0.35).timeout.connect(func():
			_field.set_count(0, _a_left)
			_field.set_count(1, _b_left))
		_update_counts()
		get_tree().create_timer(1.1).timeout.connect(func(): _finish_engagement())
		return
	_exchange += 1
	_field.reload(0)
	_field.reload(_def())
	if _all_down():
		get_tree().create_timer(0.5).timeout.connect(func(): _finish_engagement())
		return
	## calls already on the log (officers', or replayed) happen here, front by front
	var calls: Array = _calls_at(_ri)
	if not calls.is_empty():
		for c in calls:
			_seen_calls["%d|%d" % [int(c.get("front", 0)), _ri]] = true
		_show_calls(calls)
		return
	if bool(_event().get("pending", false)) and _ri >= _rolls.size():
		_ask()
		return
	if _ri >= _rolls.size():
		get_tree().create_timer(0.4).timeout.connect(func(): _finish_engagement())
		return
	_state = "ready"
	_auto_t = 0.35
	_dial.set_label("ROLL", "%d vs %d" % [_a_left, _b_left])


func _all_down() -> bool:
	if _scramble:
		var standing := 0
		for v in _left:
			if int(v) > 0:
				standing += 1
		return standing <= 1
	if int(_left[_def()]) <= 0:
		return true
	for i in range(0, _def()):
		if int(_left[i]) > 0 and not _fled(i):
			return false
	return true


func _fled(i: int) -> bool:
	return _melee and bool(_fronts[i].get("fellBack", false)) and _seen_calls.has("fell|%d" % i)


func _calls_at(at: int) -> Array:
	var out: Array = []
	if _melee:
		for i in _fronts.size():
			if _seen_calls.has("%d|%d" % [i, at]):
				continue
			for c in _fronts[i].get("calls", []):
				if int(c.get("at", -1)) == at:
					var cc: Dictionary = c.duplicate()
					cc["front"] = i
					out.append(cc)
	else:
		if _seen_calls.has("0|%d" % at):
			return out
		for c in _event().get("calls", []):
			if int(c.get("at", -1)) == at:
				out.append(c)
	return out


func _ask() -> void:
	## Paused in the session: the commander calls it.
	_state = "call"
	var p: Dictionary = session.pending
	var a: int = int(p.get("a", _a_left))
	var d: int = int(p.get("d", _b_left))
	var res: int = int(p.get("reserves", 0))
	var refuge: String = str(p.get("refuge", ""))
	var pr: float = Combat.capture_rate(a, d, Combat.MODE_VOLLEYS, _fort_bonus())
	var who: String = session.name_of(str(p.get("attacker", "")))
	_odds.text = ("%s's call · " % who if _melee else "") + "From here: %s — %d%% to take it" % [Combat.odds_word(a, d, Combat.MODE_VOLLEYS, _fort_bonus()), int(round(pr * 100.0))]
	if res > 0:
		var pr2: float = Combat.capture_rate(a + res, d, Combat.MODE_VOLLEYS, _fort_bonus())
		_odds.text += "   ·   with the reserves: %d%%" % int(round(pr2 * 100.0))
	var src: Array = p.get("reserveFrom", [])
	var from_name: String = session.hex_name(str(src[0]["from"])) if not src.is_empty() else ""
	_btn_reserves.text = "⚑ Reserves  +%d from %s   (R)" % [res, from_name] if res > 0 else "No reserves at home"
	_btn_reserves.disabled = res <= 0
	_btn_fall.text = "↩ Fall back to %s   (F)" % session.hex_name(refuge) if refuge != "" else "Cut off — no retreat!"
	_btn_fall.disabled = refuge == ""
	if manual:
		var seen: int = int(Settings.get_value("calls_seen", 0))
		_hint.visible = seen < 4
		if seen < 4:
			Settings.remember("calls_seen", seen + 1)
		_call_plate.visible = true
		_dial.set_label("PRESS ON", "Space")
		_call_plate.modulate.a = 0.0
		create_tween().tween_property(_call_plate, "modulate:a", 1.0, 0.15)
	else:
		_auto_t = 0.7
		_dial.set_label("…", "")
	_counsel(a, d, res, refuge)


func _counsel(a: int, d: int, res: int, refuge: String) -> void:
	## The chief of staff reads the opening exchange once per battle.
	var att: String = str(session.pending.get("attacker", _a_pid))
	if _advised or not _advisor.visible or not session.is_human(att):
		return
	_advised = true
	var fi: int = int(session.pending.get("front", 0))
	var start_a: int = int(_fronts[fi]["size"]) if _melee else int(_beats[_bi]["a_size"])
	var start_d: int = int(_event().get("defenderSize", _beats[_bi].get("b_size", d))) if _melee else int(_beats[_bi]["b_size"])
	var lost_a: int = start_a - a
	var lost_d: int = start_d - (int(session.pending.get("dTotal", d)) if _melee else d)
	if refuge == "" and lost_a >= lost_d:
		_advisor.react("alarm", "cut_off", 3.0)
	elif lost_a >= 2 and lost_d == 0 or lost_a - lost_d >= 2:
		_advisor.react("alarm", "opening_bad", 3.4)
	elif lost_d >= 3 or lost_d - lost_a >= 2:
		_advisor.react("happy", "opening_good", 3.0)


func _answer(call: String) -> void:
	if _state != "call":
		return
	_call_plate.visible = false
	_state = "wait"
	_dial.set_label("…", "")
	var p: Dictionary = session.pending.duplicate()
	var at: int = int(p.get("rolls", _ri))
	var fi: int = int(p.get("front", 0))
	session.answer(call) ## re-resolves; the cinema hands us the longer log (extend)
	_seen_calls["%d|%d" % [fi, at]] = true
	if call == Combat.CALL_PRESS:
		if _advised and _advisor.visible and session.is_human(str(p.get("attacker", ""))) and _exchange == 1:
			_advisor.react("happy", "press", 2.0)
		_field.charge(fi if _melee else 0)
		## in a melee other fronts may also have called at this moment: show them, then go on
		var rest: Array = _calls_at(at)
		if not rest.is_empty():
			for c in rest:
				_seen_calls["%d|%d" % [int(c.get("front", 0)), at]] = true
			_show_calls(rest)
			return
		if bool(_event().get("pending", false)) and _ri >= _rolls.size():
			_ask()
			return
		_roll_exchange()
		return
	var entry := {"call": call, "at": at, "to": str(p.get("refuge", "")), "front": fi}
	entry["n"] = int(p.get("reserves", 0)) if call == Combat.CALL_RESERVES else int(p.get("a", _a_left))
	_show_calls([entry])


func _show_calls(calls: Array) -> void:
	## reserves and retreats, shown one after another; then the battle goes on (or ends)
	_state = "wait"
	var delay := 0.0
	var ends := false
	for c in calls:
		var cc: Dictionary = c
		get_tree().create_timer(delay).timeout.connect(func(): _show_call(cc))
		delay += 1.5 if str(cc.get("call", "")) == Combat.CALL_RESERVES else 1.8
		if str(cc.get("call", "")) == Combat.CALL_FALL_BACK and not _melee:
			ends = true
	get_tree().create_timer(delay).timeout.connect(func():
		if _state != "wait":
			return
		if ends or _all_down():
			_finish_engagement()
		elif bool(_event().get("pending", false)) and _ri >= _rolls.size():
			_ask()
		else:
			_state = "ready"
			_auto_t = 0.3
			_dial.set_label("ROLL", "%d vs %d" % [_a_left, _b_left]))


func _show_call(c: Dictionary) -> void:
	var call: String = str(c.get("call", ""))
	var fi: int = int(c.get("front", 0))
	var army: int = fi if _melee else 0
	var pid: String = str(_fronts[fi]["attackerId"]) if _melee else _a_pid
	var who: String = _who(pid)
	var face: Control = _face_of_front(fi)
	match call:
		Combat.CALL_RESERVES:
			var n: int = int(c.get("n", 0))
			_left[army] = int(_left[army]) + n
			_a_left = int(_left[0])
			_update_counts()
			_field.set_count(army, int(_left[army]))
			_shout_text("RESERVES!  +%d" % n, Style.GOLD)
			_sub.text = "%s in the reserves from home" % Style.says(session.name_of(pid), "throws")
			Audio.sfx("reserves", -2.0)
			get_tree().create_timer(0.5).timeout.connect(func(): Audio.sfx("hurrah", -4.0))
			if Lines.has(who, "reserves"):
				face.react("happy", "reserves", 2.4)
			elif _advisor.visible and session.is_human(pid):
				face.react("happy")
				_advisor.react("happy", "reserves", 2.4)
		Combat.CALL_FALL_BACK:
			_shout_text("FALL BACK!", Style.PARCH)
			_sub.text = "%s the retreat to %s" % [Style.says(session.name_of(pid), "sounds"), session.hex_name(str(c.get("to", "")))]
			Audio.sfx("retreat", -2.0)
			_field.retreat(army)
			_seen_calls["fell|%d" % fi] = true
			if Lines.has(who, "retreat"):
				face.react("lose", "retreat", 2.6)
			elif _advisor.visible and session.is_human(pid):
				face.react("lose")
				_advisor.react("alarm", "retreat", 2.6)


func _shout_text(t: String, col: Color) -> void:
	_shout.text = t
	_shout.add_theme_color_override("font_color", col)
	_shout.pivot_offset = _shout.size * 0.5
	_shout.scale = Vector2(1.4, 1.4)
	_shout.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_shout, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(0.9)
	tw.tween_property(_shout, "modulate:a", 0.0, 0.4)


func _finish_engagement() -> void:
	if _bi < 0 or _bi >= _beats.size():
		return
	if _state == "done":
		return
	var b: Dictionary = _beats[_bi]
	var e: Dictionary = b["event"]
	var kind: String = str(e["kind"])
	var land: String = str(b.get("resolves", ""))
	if _melee:
		_finish_melee(e, land)
		return
	if _scramble:
		_finish_scramble(e, land)
		return
	var a_won: bool = bool(b["a_won"])
	var fell: bool = bool(e.get("fellBack", false))
	var winner: String = _a_pid if a_won else _b_pid
	var loser: String = _b_pid if a_won else _a_pid
	## make the board agree exactly with the log before the verdict
	if fell:
		_a_left = int(e.get("attackerLeft", 0))
		_b_left = int(b["left"])
		_field.set_count(1, _b_left)
	else:
		_a_left = int(b["left"]) if a_won else 0
		_b_left = 0 if a_won else int(b["left"])
		_field.set_count(0, _a_left)
		_field.set_count(1, _b_left)
	_left = [_a_left, _b_left]
	_update_counts()
	if fell:
		_result.text = ("%s back to %s — %d saved" % [Style.says(session.name_of(_a_pid), "falls"), session.hex_name(str(e.get("refuge", ""))), _a_left]).to_upper()
		Audio.sfx("hold")
	elif kind == "Invasion":
		_result.text = ("%s %s" % [Style.says(session.name_of(winner), "takes"), session.hex_name(land)]).to_upper() if a_won else ("%s %s" % [Style.says(session.name_of(winner) if winner != "neutral" else "The garrison", "holds"), session.hex_name(land)]).to_upper()
		Audio.sfx("capture" if a_won else "hold")
	else:
		_result.text = ("%s the field" % Style.says(session.name_of(winner), "wins")).to_upper()
		Audio.sfx("clash")
	_result.add_theme_color_override("font_color", Style.seat_color(winner).lightened(0.5))
	## the bar ends where the fight did
	var wn: String = session.name_of(winner) if winner != "neutral" else "The garrison"
	var verdict: String = "%s back" % Style.says(session.name_of(_a_pid), "falls") if fell else (("%s %s" % [Style.says(wn, "takes" if a_won else "holds"), session.hex_name(land)]) if kind == "Invasion" else "%s the field" % Style.says(wn, "wins"))
	_odds_bar.show_odds(1.0 if a_won and not fell else 0.0, _a_pid, _b_pid, verdict, "Decided.")
	_field.cheer(0 if a_won else 1)
	var cheering: int = _a_left if a_won else _b_left
	if not fell:
		get_tree().create_timer(0.35).timeout.connect(func(): Audio.cheer(cheering))
	## reactions: winner exults, loser curses; AI commanders speak one line
	var face_w: Control = _face_a if a_won else _face_b
	var face_l: Control = _face_b if a_won else _face_a
	var ww: String = _who(winner)
	var lw: String = _who(loser)
	var spoke := false
	if Lines.has(ww, "win"):
		face_w.react("win", "win", 2.6)
		spoke = true
	else:
		face_w.react("win")
	if fell:
		pass ## the attacker already had their say when they called the retreat
	elif Lines.has(lw, "lose") and not spoke:
		face_l.react("lose", "lose", 2.6)
	else:
		face_l.react("lose")
		if Lines.has(lw, "lose"):
			face_l.say_text(Lines.text(lw, "lose"), 2.6)
	_state = "done"
	_auto_t = 2.6
	_dial.set_label("NEXT" if _bi < _beats.size() - 1 else "DONE", "")


func _finish_melee(e: Dictionary, land: String) -> void:
	var held: bool = int(e.get("defenderLeft", 0)) > 0
	for i in _fronts.size():
		_left[i] = int(_fronts[i].get("left", 0))
		if not bool(_fronts[i].get("fellBack", false)):
			_field.set_count(i, int(_left[i]))
	_left[_def()] = int(e.get("defenderLeft", 0))
	_field.set_count(_def(), int(_left[_def()]))
	_a_left = int(_left[0])
	_b_left = int(_left[_def()])
	_update_counts()
	if held:
		_result.text = ("%s %s against all comers" % [Style.says(session.name_of(_b_pid) if _b_pid != "neutral" else "The garrison", "holds"), session.hex_name(land)]).to_upper()
		_result.add_theme_color_override("font_color", Style.seat_color(_b_pid).lightened(0.5))
		Audio.sfx("hold")
		_field.cheer(_def())
		if Lines.has(_who(_b_pid), "win"):
			_face_b.react("win", "win", 2.6)
		else:
			_face_b.react("win")
		_face_a.react("lose")
	else:
		var standing: Array = []
		for i in _fronts.size():
			if int(_left[i]) > 0 and not bool(_fronts[i].get("fellBack", false)):
				standing.append(i)
				_field.cheer(i)
		_result.text = ("THE DEFENDERS OF %s ARE OVERRUN" % session.hex_name(land)).to_upper() + ("" if standing.size() < 2 else " — NOW FOR THE SPOILS")
		_result.add_theme_color_override("font_color", Style.GOLD)
		Audio.sfx("capture")
		if Lines.has(_who(_melee_lead_pid()), "win"):
			_face_a.react("win", "win", 2.6)
		else:
			_face_a.react("win")
		_face_b.react("lose")
	var cheering := 0
	if held:
		cheering = int(_left[_def()])
	else:
		for i in _fronts.size():
			if not bool(_fronts[i].get("fellBack", false)):
				cheering += maxi(0, int(_left[i]))
	get_tree().create_timer(0.35).timeout.connect(func(): Audio.cheer(cheering))
	_state = "done"
	_auto_t = 2.6
	_dial.set_label("NEXT" if _bi < _beats.size() - 1 else "DONE", "")


func _finish_scramble(e: Dictionary, land: String) -> void:
	for i in _fronts.size():
		_left[i] = int(_fronts[i].get("left", 0))
		_field.set_count(i, int(_left[i]))
	var win: String = str(e.get("winnerId", ""))
	var wi := 0
	for i in _fronts.size():
		if _front_pid(i) == win:
			wi = i
	_a_left = int(_left[0])
	_b_left = int(_left[_b_front()])
	_update_counts()
	_update_odds()
	_result.text = ("%s %s — last army standing" % [Style.says(session.name_of(win), "takes"), session.hex_name(land)]).to_upper()
	_result.add_theme_color_override("font_color", Style.seat_color(win).lightened(0.5))
	Audio.sfx("capture")
	_field.cheer(wi)
	var face: Control = _face_of_front(wi)
	if Lines.has(_who(win), "win"):
		face.react("win", "win", 2.6)
	else:
		face.react("win")
	for i in _fronts.size():
		if i != wi:
			_face_of_front(i).react("lose")
	var cheering: int = int(_left[wi])
	get_tree().create_timer(0.35).timeout.connect(func(): Audio.cheer(cheering))
	_state = "done"
	_auto_t = 2.6
	_dial.set_label("NEXT" if _bi < _beats.size() - 1 else "DONE", "")


class _OddsBar extends Control:
	## a tug of war in the two commanders' colours, the chance in words above it and the
	## reason (the edge in men, and what it is worth in pips) below
	const Style := preload("res://game/core/style.gd")
	var p := -1.0
	var shown := -1.0
	var a_pid := ""
	var b_pid := ""
	var head := ""
	var edge := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_odds(np: float, a: String, b: String, h: String, e: String) -> void:
		p = np
		a_pid = a
		b_pid = b
		head = h
		edge = e
		if shown < 0.0:
			shown = np
		queue_redraw()

	func _process(delta: float) -> void:
		if p >= 0.0 and absf(shown - p) > 0.002:
			shown = move_toward(shown, p, delta * 0.8)
			queue_redraw()

	func _draw() -> void:
		if head == "" and edge == "":
			return
		var f := Style.font("bold")
		var fi := Style.font("italic")
		var w: float = size.x
		var hw: float = f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string_outline(f, Vector2((w - hw) * 0.5, 16), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 6, Color(0, 0, 0, 0.85))
		draw_string(f, Vector2((w - hw) * 0.5, 16), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Style.CREAM)
		if p >= 0.0:
			var r := Rect2(Vector2(40, 23), Vector2(w - 80, 12))
			draw_rect(r.grow(2.0), Color(0, 0, 0, 0.7))
			var split: float = r.size.x * clampf(shown, 0.0, 1.0)
			draw_rect(Rect2(r.position, Vector2(split, r.size.y)), Style.seat_color(a_pid).lightened(0.1))
			draw_rect(Rect2(r.position + Vector2(split, 0), Vector2(r.size.x - split, r.size.y)), Style.seat_color(b_pid).lightened(0.1) if b_pid != "neutral" else Color(0.55, 0.53, 0.5))
			draw_rect(Rect2(r.position + Vector2(split - 2.0, -4), Vector2(4, r.size.y + 8)), Style.GOLD)
		var ew: float = fi.get_string_size(edge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var ey: float = 52.0 if p >= 0.0 else 36.0
		draw_string_outline(fi, Vector2((w - ew) * 0.5, ey), edge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.85))
		draw_string(fi, Vector2((w - ew) * 0.5, ey), edge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Style.PARCH)
