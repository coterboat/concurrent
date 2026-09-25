## The battlefield. One or more engagements at one land, played exchange by exchange.
## Every die shown is the engine's own roll from the event log — the theater only
## chooses when to reveal it. After each exchange of an assault the attacker calls:
## PRESS ON, throw in the RESERVES from home, or FALL BACK. A watching commander calls
## it here (the round is paused in the session until they do); everyone else's calls
## come from their sealed standing orders and are shown as they happen.
## Figures are Ludo tin soldiers tinted to each side: they march in, breathe, fire,
## fall, and — if it comes to that — turn and march away.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const Lines := preload("res://game/core/lines.gd")
const Combat := preload("res://engine/combat.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")

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
var _field: _Field
var _dice_a: HBoxContainer
var _dice_b: HBoxContainer
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
	_field = _Field.new()
	_field.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_field.offset_top = 250
	_field.offset_bottom = -190
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
	## dice tray + score
	var tray := VBoxContainer.new()
	tray.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	tray.offset_bottom = -104
	tray.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tray.alignment = BoxContainer.ALIGNMENT_CENTER
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tray)
	_result = Style.label("", 32, Style.CREAM, "display")
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_constant_override("outline_size", 10)
	_result.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	tray.add_child(_result)
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 26)
	tray.add_child(drow)
	_dice_a = HBoxContainer.new()
	_dice_a.add_theme_constant_override("separation", 8)
	drow.add_child(_dice_a)
	var vs := Style.label("VS", 26, Style.GOLD, "display")
	vs.add_theme_constant_override("outline_size", 6)
	vs.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	drow.add_child(vs)
	_dice_b = HBoxContainer.new()
	_dice_b.add_theme_constant_override("separation", 8)
	drow.add_child(_dice_b)
	_score = Style.label("", 18, Style.PARCH, "bold")
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_constant_override("outline_size", 6)
	_score.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tray.add_child(_score)
	## the battle call: a war-council plate above the dice when the commander must decide
	_call_plate = PanelContainer.new()
	_call_plate.add_theme_stylebox_override("panel", Style.flat(Color(0.07, 0.035, 0.025, 0.93), Color(Style.GOLD, 0.75), 2, 10, 14))
	_call_plate.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	_call_plate.offset_bottom = -222
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
	var skip := Style.chip("Skip battles ▶▶", func(): _skip(), Style.PARCH, 16)
	skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip.tooltip_text = "Settle this round's remaining battles on the map (your standing orders decide the calls)"
	ctl.add_child(skip)
	## the chief of staff, at your elbow
	_advisor = LeaderFace.new()
	_advisor.bubble_side = "right"
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
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	Audio.ambience(true, "ambience_battle")
	Audio.music("charge")
	Audio.sfx("charge", -3.0)
	_next_engagement()


func extend(beats: Array) -> void:
	## The session resolved further after a call: same fights, longer log.
	_beats = beats
	if _bi >= 0 and _bi < _beats.size():
		_rolls = (_beats[_bi]["event"] as Dictionary).get("rolls", [])


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


func _process(delta: float) -> void:
	if not visible:
		return
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
	_a_pid = str(b["a"])
	_b_pid = str(b["b"])
	_a_left = int(b["a_size"])
	_b_left = int(b["b_size"])
	_rolls = e.get("rolls", [])
	_volley_mode = not _rolls.is_empty() and (_rolls[0] as Dictionary).has("sa")
	_ri = 0
	_exchange = 0
	_seen_calls = {}
	_advised = false
	_call_plate.visible = false
	## the ground under this fight
	var region: String = session.map.get_territory(land).region if land != "" else ""
	var terrain: String = str(session.map.region_terrain.get(region, "grass"))
	_bg.texture = Style.tex("res://assets/battle/field_%s.webp" % terrain)
	_title.text = str(b["caption"]).to_upper()
	match kind:
		"Clash":
			_sub.text = "Both armies march at once and meet in the field — no retreat"
		"Spoils":
			_sub.text = "Two invaders, one prize — no retreat"
		_:
			var attacker_from: String = session.hex_name(str(e.get("from", "")))
			_sub.text = "%s attacks from %s" % [session.name_of(_a_pid), attacker_from]
	_setup_side(_face_a, _name_a, _a_pid, true)
	_setup_side(_face_b, _name_b, _b_pid, false)
	_update_counts()
	_field.setup(_a_pid, _a_left, _b_pid, _b_left)
	_result.text = ""
	_score.text = "Each volley: die × 5 + armies. Loser of the volley loses one." if _volley_mode else "One roll: armies + die. Higher total wins."
	_clear_dice()
	_progress.text = "Battle %d of %d at this land" % [_bi + 1, _beats.size()] if _beats.size() > 1 else ""
	if not _spoken_attack:
		_spoken_attack = true
		var who: String = _who(_a_pid)
		if Lines.has(who, "attack"):
			_face_a.react("win", "attack", 2.4)
		else:
			_face_a.react("happy")
	_state = "ready"
	_auto_t = 1.3 ## let them march in
	_dial.set_label("ROLL", "Space")


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
	_count_a.text = str(maxi(0, _a_left))
	_count_b.text = str(maxi(0, _b_left))


func _clear_dice() -> void:
	for c in _dice_a.get_children():
		c.queue_free()
	for c in _dice_b.get_children():
		c.queue_free()


func _roll_exchange() -> void:
	if _ri >= _rolls.size():
		_after_exchange()
		return
	_state = "rolling"
	_call_plate.visible = false
	_dial.set_label("…", "")
	_clear_dice()
	## one exchange: three volleys (or the single decisive roll with its rerolls)
	var chunk: Array = []
	if _volley_mode:
		var decided := 0
		while _ri < _rolls.size() and decided < Combat.EXCHANGE:
			chunk.append(_rolls[_ri])
			_ri += 1
			if str(chunk[-1].get("w", "")) != "":
				decided += 1
	else:
		chunk = _rolls.duplicate()
		_ri = _rolls.size()
	var dice_pairs: Array = []
	for r in chunk:
		var da := _Die.new()
		da.tint = Style.seat_color(_a_pid)
		da.rolling = true
		_dice_a.add_child(da)
		var db := _Die.new()
		db.tint = Style.seat_color(_b_pid)
		db.rolling = true
		_dice_b.add_child(db)
		dice_pairs.append([da, db, r])
	Audio.sfx("dice")
	var t := 0.55 if manual else 0.4
	var tw := create_tween()
	tw.tween_interval(t)
	for i in dice_pairs.size():
		var pair: Array = dice_pairs[i]
		tw.tween_callback(func(): _settle(pair[0], pair[1], pair[2]))
		tw.tween_interval(0.42 if _volley_mode else 0.2)
	tw.tween_callback(func(): _after_exchange())


func _settle(da: _Die, db: _Die, r: Dictionary) -> void:
	da.rolling = false
	db.rolling = false
	da.value = int(r["a"])
	db.value = int(r["b"])
	var w: String = str(r.get("w", ""))
	if not _volley_mode:
		return
	var sa: int = 5 * int(r["a"]) + int(r["sa"])
	var sb: int = 5 * int(r["b"]) + int(r["sd"])
	if w == "":
		_score.text = "%d vs %d — a tie in the field. Roll again." % [sa, sb]
		da.dim = true
		db.dim = true
		return
	_score.text = "%s  5×%d + %d = %d    vs    %s  5×%d + %d = %d" % [session.name_of(_a_pid), r["a"], r["sa"], sa, session.name_of(_b_pid) if _b_pid != "neutral" else "Neutral", r["b"], r["sd"], sb]
	if w == "a":
		db.dim = true
		_b_left -= 1
		_field.volley(true)
		_flinch(_face_b)
	else:
		da.dim = true
		_a_left -= 1
		_field.volley(false)
		_flinch(_face_a)
	_field.set_alive(_a_left, _b_left)
	_update_counts()
	Audio.sfx("volley", -5.0, 0.12)
	get_tree().create_timer(0.12).timeout.connect(func(): Audio.sfx("hit", -9.0, 0.15))


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
		var last: Dictionary = _rolls[-1]
		var ta: int = int(b["a_size"]) + int(last["a"])
		var tb: int = int(b["b_size"]) + int(last["b"])
		_score.text = "%d + %d = %d    vs    %d + %d = %d" % [b["a_size"], last["a"], ta, b["b_size"], last["b"], tb]
		var a_won: bool = bool(b["a_won"])
		var left: int = int(b["left"])
		_a_left = left if a_won else 0
		_b_left = 0 if a_won else left
		var dice_a: Array = _dice_a.get_children()
		var dice_b: Array = _dice_b.get_children()
		if a_won and not dice_b.is_empty():
			(dice_b[-1] as _Die).dim = true
		elif not a_won and not dice_a.is_empty():
			(dice_a[-1] as _Die).dim = true
		Audio.sfx("cannon", -4.0)
		_field.rout(a_won, _a_left, _b_left)
		_update_counts()
		get_tree().create_timer(1.1).timeout.connect(func(): _finish_engagement())
		return
	_exchange += 1
	if _a_left <= 0 or _b_left <= 0:
		get_tree().create_timer(0.4).timeout.connect(func(): _finish_engagement())
		return
	## a call already on the log (an officer's, or a replayed one) happens here
	var c: Dictionary = _call_at(_ri)
	if not c.is_empty():
		_seen_calls[_ri] = true
		_show_call(c, false)
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


func _call_at(at: int) -> Dictionary:
	if _seen_calls.has(at):
		return {}
	for c in _event().get("calls", []):
		if int(c.get("at", -1)) == at:
			return c
	return {}


func _ask() -> void:
	## Paused in the session: the commander calls it.
	_state = "call"
	var p: Dictionary = session.pending
	var a: int = int(p.get("a", _a_left))
	var d: int = int(p.get("d", _b_left))
	var res: int = int(p.get("reserves", 0))
	var refuge: String = str(p.get("refuge", ""))
	var pr: float = Combat.capture_rate(a, d, Combat.MODE_VOLLEYS)
	_odds.text = "From here: %s — %d%% to take it" % [Combat.odds_word(a, d, Combat.MODE_VOLLEYS), int(round(pr * 100.0))]
	if res > 0:
		var pr2: float = Combat.capture_rate(a + res, d, Combat.MODE_VOLLEYS)
		_odds.text += "   ·   with the reserves: %d%%" % int(round(pr2 * 100.0))
	var src: Array = p.get("reserveFrom", [])
	var from_name: String = session.hex_name(str(src[0]["from"])) if not src.is_empty() else ""
	_btn_reserves.text = "⚑ Reserves  +%d from %s   (R)" % [res, from_name] if res > 0 else "No reserves at home"
	_btn_reserves.disabled = res <= 0
	_btn_fall.text = "↩ Fall back to %s   (F)" % session.hex_name(refuge) if refuge != "" else "Cut off — no retreat!"
	_btn_fall.disabled = refuge == ""
	if manual:
		## the first few times, say what the plate is for
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
	if _advised or not _advisor.visible or not session.is_human(_a_pid):
		return
	_advised = true
	var start_a: int = int(_beats[_bi]["a_size"])
	var start_d: int = int(_beats[_bi]["b_size"])
	var lost_a: int = start_a - a
	var lost_d: int = start_d - d
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
	session.answer(call) ## re-resolves; the cinema hands us the longer log (extend)
	_seen_calls[at] = true
	if call == Combat.CALL_PRESS:
		if _advised and _advisor.visible and session.is_human(_a_pid) and _exchange == 1:
			_advisor.react("happy", "press", 2.0)
		_roll_exchange()
		return
	var entry := {"call": call, "at": at, "to": str(p.get("refuge", ""))}
	entry["n"] = int(p.get("reserves", 0)) if call == Combat.CALL_RESERVES else int(p.get("a", _a_left))
	_show_call(entry, true)


func _show_call(c: Dictionary, live: bool) -> void:
	_state = "wait"
	var call: String = str(c.get("call", ""))
	var who: String = _who(_a_pid)
	match call:
		Combat.CALL_RESERVES:
			var n: int = int(c.get("n", 0))
			_a_left += n
			_update_counts()
			_field.reinforce(0, _a_left)
			_shout_text("RESERVES!  +%d" % n, Style.GOLD)
			_sub.text = "%s throws in the reserves from home" % session.name_of(_a_pid)
			Audio.sfx("reserves", -2.0)
			get_tree().create_timer(0.5).timeout.connect(func(): Audio.sfx("hurrah", -4.0))
			if Lines.has(who, "reserves"):
				_face_a.react("happy", "reserves", 2.4)
			elif _advisor.visible and session.is_human(_a_pid):
				_face_a.react("happy")
				_advisor.react("happy", "reserves", 2.4)
			get_tree().create_timer(1.5).timeout.connect(func():
				if _state != "wait":
					return
				_state = "ready"
				_auto_t = 0.3
				_dial.set_label("ROLL", "%d vs %d" % [_a_left, _b_left]))
		Combat.CALL_FALL_BACK:
			_shout_text("FALL BACK!", Style.PARCH)
			_sub.text = "%s sounds the retreat to %s" % [session.name_of(_a_pid), session.hex_name(str(c.get("to", "")))]
			Audio.sfx("retreat", -2.0)
			_field.retreat(0)
			if Lines.has(who, "retreat"):
				_face_a.react("lose", "retreat", 2.6)
			elif _advisor.visible and session.is_human(_a_pid):
				_face_a.react("lose")
				_advisor.react("alarm", "retreat", 2.6)
			get_tree().create_timer(1.8).timeout.connect(func():
				if _state == "wait":
					_finish_engagement())
		_:
			_state = "ready"
			_auto_t = 0.3


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
	var b: Dictionary = _beats[_bi]
	var e: Dictionary = b["event"]
	var a_won: bool = bool(b["a_won"])
	var fell: bool = bool(e.get("fellBack", false))
	var winner: String = _a_pid if a_won else _b_pid
	var loser: String = _b_pid if a_won else _a_pid
	var land: String = str(b.get("resolves", ""))
	var kind: String = str(e["kind"])
	## make the board agree exactly with the log before the verdict
	if fell:
		_a_left = int(e.get("attackerLeft", 0))
		_b_left = int(b["left"])
		_field.set_alive(0, _b_left, true) ## the attackers have already marched off
	else:
		_a_left = int(b["left"]) if a_won else 0
		_b_left = 0 if a_won else int(b["left"])
		_field.set_alive(_a_left, _b_left)
	_update_counts()
	if fell:
		_result.text = ("%s falls back to %s — %d saved" % [session.name_of(_a_pid), session.hex_name(str(e.get("refuge", ""))), _a_left]).to_upper()
		Audio.sfx("hold")
	elif kind == "Invasion":
		_result.text = ("%s TAKES %s" % [session.name_of(winner), session.hex_name(land)]).to_upper() if a_won else ("%s HOLDS %s" % [session.name_of(winner) if winner != "neutral" else "THE GARRISON", session.hex_name(land)]).to_upper()
		Audio.sfx("capture" if a_won else "hold")
	else:
		_result.text = ("%s wins the field" % session.name_of(winner)).to_upper()
		Audio.sfx("clash")
	_result.add_theme_color_override("font_color", Style.seat_color(winner).lightened(0.5))
	get_tree().create_timer(0.35).timeout.connect(func(): Audio.sfx("cheer", -6.0))
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


# ------------------------------------------------------------------ the field

class _Field extends Control:
	const Style := preload("res://game/core/style.gd")
	const MAX_FIGS := 24
	const FIG_H := 104.0 ## a front-rank soldier's height in pixels at scale 1
	var a_pid := ""
	var b_pid := ""
	var figs: Array = [] ## {side, pos, cur, scale, state, t, alive, order, phase, alpha}
	var unit_a := 1
	var unit_b := 1
	var puffs: Array = [] ## {pos, t, big}
	var _clock := 0.0
	var _anims := {} ## name -> {tex, cols, frames, fw, fh, ax, ay, fill}
	var _flag_x := [0.0, 0.0] ## where each colour party is now (it marches with its men)
	var _flag_fled := [-1.0, -1.0] ## seconds since that side sounded the retreat, -1 = standing

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		## a tin soldier falls the way tin soldiers do: stiffly, over backwards, drawn in
		## code (a rigid topple about the feet), so it can never clip or reset
		for n in ["idle", "fire", "march"]:
			_anims[n] = _sheet("res://assets/battle/soldier_%s" % n)
		_anims["flag"] = _sheet("res://assets/battle/flag_wave")
		## v1.1 fallback: tight-cropped 4x4 sheets, no idle or march
		if _anims["fire"].is_empty():
			var fire: Texture2D = Style.tex("res://assets/battle/soldier_fire.webp")
			if fire != null:
				_anims["fire"] = {"tex": fire, "cols": 4, "frames": 16, "fw": fire.get_width() / 4.0, "fh": fire.get_height() / 4.0, "ax": 0.5, "ay": 1.0, "fill": 1.0}
		for n in ["idle", "march"]:
			if _anims[n].is_empty() and not _anims["fire"].is_empty():
				_anims[n] = _anims["fire"].duplicate()
				_anims[n]["frames"] = 1
		if _anims["flag"].is_empty():
			var flag: Texture2D = Style.tex("res://assets/battle/soldier_flag.png")
			if flag != null:
				_anims["flag"] = {"tex": flag, "cols": 1, "frames": 1, "fw": float(flag.get_width()), "fh": float(flag.get_height()), "ax": 0.5, "ay": 1.0, "fill": 1.0}

	func _sheet(base: String) -> Dictionary:
		var t: Texture2D = Style.tex(base + ".webp")
		if t == null or not FileAccess.file_exists(base + ".json"):
			return {}
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
		if typeof(m) != TYPE_DICTIONARY or not (m as Dictionary).has("fw"):
			return {} ## a v1.1 sheet (tight-cropped): handled by the fallback
		## padded canvas: feet at (0.55, 0.92); the soldier is 450/768 of the frame
		return {"tex": t, "cols": int(m["cols"]), "frames": int(m["frames"]), "fw": float(m["fw"]), "fh": float(m["fh"]),
			"ax": float(m.get("ax", 0.55)), "ay": float(m.get("ay", 0.92)), "fill": float(m.get("fill", 450.0 / 768.0)),
			"order": m.get("order", [])}

	func _len(an: Dictionary) -> int:
		## playback length: an explicit frame order (ping-pong, raise-fire-lower) or the sheet
		var o: Array = an.get("order", [])
		return o.size() if not o.is_empty() else int(an["frames"])

	func _pick(an: Dictionary, k: int, loop: bool) -> int:
		var n: int = _len(an)
		k = posmod(k, n) if loop else clampi(k, 0, n - 1)
		var o: Array = an.get("order", [])
		return int(o[k]) if not o.is_empty() else k

	func setup(pa: String, na: int, pb: String, nb: int) -> void:
		a_pid = pa
		b_pid = pb
		unit_a = int(ceil(float(na) / MAX_FIGS))
		unit_b = int(ceil(float(nb) / MAX_FIGS))
		figs = []
		puffs = []
		_flag_x = [-160.0, size.x + 160.0]
		_flag_fled = [-1.0, -1.0]
		_place(0, int(ceil(float(na) / unit_a)), 0)
		_place(1, int(ceil(float(nb) / unit_b)), 0)
		queue_redraw()

	func _slot(side: int, i: int, n_total: int) -> Dictionary:
		## Rows run into the distance (up the screen); files march back from the front line.
		var rows: int = clampi(int(ceil(sqrt(float(n_total) * 0.9))), 1, 5)
		var row: int = i % rows
		var file: int = i / rows
		var depth: float = 0.0 if rows == 1 else float(row) / float(rows - 1)
		var sc: float = 1.0 - depth * 0.28
		var gap: float = 70.0 * sc
		var front: float = 90.0 + (row % 2) * 24.0
		var cx: float = size.x * 0.5
		var x: float = cx - (front + file * gap) if side == 0 else cx + (front + file * gap)
		return {"pos": Vector2(x, size.y * (0.97 - depth * 0.5)), "scale": sc}

	func _place(side: int, n: int, first: int) -> void:
		for i in range(first, first + n):
			var s: Dictionary = _slot(side, i, maxi(n + first, 1))
			var pos: Vector2 = s["pos"]
			## everyone marches in from their own edge of the field
			var start := Vector2(-80.0 - randf() * 120.0 if side == 0 else size.x + 80.0 + randf() * 120.0, pos.y)
			figs.append({"side": side, "pos": pos, "cur": start, "scale": s["scale"], "state": "march", "t": 0.0,
				"alive": true, "order": i, "phase": randf() * 3.0, "alpha": 1.0})

	func _flag_target(side: int) -> float:
		## the colours stand just behind the last file of their side
		var n := 0
		for f in figs:
			if f["side"] == side and f["alive"] and f["state"] != "flee":
				n += 1
		n = maxi(n, 1)
		var rows: int = clampi(int(ceil(sqrt(float(n) * 0.9))), 1, 5)
		var files: int = int(ceil(float(n) / rows))
		return size.x * 0.5 + (-1 if side == 0 else 1) * (90.0 + 70.0 * (files + 0.4))

	func _alive(side: int) -> Array:
		var out: Array = []
		for f in figs:
			if f["side"] == side and f["alive"]:
				out.append(f)
		return out

	func set_alive(na: int, nb: int, keep_fled: bool = false) -> void:
		_trim(0, int(ceil(float(maxi(0, na)) / unit_a)), keep_fled)
		_trim(1, int(ceil(float(maxi(0, nb)) / unit_b)), keep_fled)

	func _trim(side: int, want: int, keep_fled: bool = false) -> void:
		var alive := _alive(side)
		if keep_fled:
			alive = alive.filter(func(f): return f["state"] != "flee")
		## the front of the line falls first
		alive.sort_custom(func(x, y): return int(x["order"]) < int(y["order"]))
		var k := alive.size() - want
		for i in range(maxi(0, k)):
			var f: Dictionary = alive[i]
			f["alive"] = false
			f["state"] = "fall"
			f["t"] = 0.0
			puffs.append({"pos": f["cur"] + Vector2(0, -52 * f["scale"]), "t": 0.0, "big": false, "seed": randf() * TAU})

	func reinforce(side: int, armies: int) -> void:
		## the reserves march up behind the line
		var unit: int = unit_a if side == 0 else unit_b
		var want: int = int(ceil(float(armies) / unit))
		var have := _alive(side).size()
		if want <= have:
			return
		var top := 0
		for f in figs:
			if f["side"] == side:
				top = maxi(top, int(f["order"]) + 1)
		var n: int = mini(want - have, MAX_FIGS)
		for i in range(top, top + n):
			var s: Dictionary = _slot(side, i, maxi(top + n, 1))
			var pos: Vector2 = s["pos"]
			figs.append({"side": side, "pos": pos, "cur": Vector2(-100.0 - randf() * 160.0 if side == 0 else size.x + 100.0 + randf() * 160.0, pos.y),
				"scale": s["scale"], "state": "march", "t": 0.0, "alive": true, "order": i, "phase": randf() * 3.0, "alpha": 1.0})

	func retreat(side: int) -> void:
		## about face, and march off the field — colours and all
		_flag_fled[side] = 0.0
		for f in _alive(side):
			f["state"] = "flee"
			f["t"] = randf() * 0.25

	func volley(a_fires: bool) -> void:
		var shooters := _alive(0 if a_fires else 1).filter(func(f): return f["state"] == "idle")
		if shooters.is_empty():
			return
		shooters.shuffle()
		for i in mini(3, shooters.size()):
			var f: Dictionary = shooters[i]
			f["state"] = "fire"
			f["t"] = randf() * 0.1
			var dir := 1.0 if f["side"] == 0 else -1.0
			puffs.append({"pos": f["cur"] + Vector2(dir * 40 * f["scale"], -62 * f["scale"]), "t": -0.3, "big": false, "seed": randf() * TAU})

	func rout(a_won: bool, na: int, nb: int) -> void:
		## decisive roll: two quick volleys, then the losers go down
		volley(a_won)
		volley(not a_won)
		get_tree().create_timer(0.35).timeout.connect(func(): set_alive(na, nb))
		for i in 3:
			puffs.append({"pos": Vector2(size.x * (0.35 + 0.15 * i), size.y * 0.6), "t": -0.1 * i, "big": true})

	func _process(delta: float) -> void:
		_clock += delta
		for f in figs:
			match str(f["state"]):
				"march":
					var to: Vector2 = f["pos"]
					var step: float = 380.0 * float(f["scale"]) * delta
					var cur: Vector2 = f["cur"]
					if cur.distance_to(to) <= step:
						f["cur"] = to
						f["state"] = "idle"
					else:
						f["cur"] = cur.move_toward(to, step)
				"fire":
					f["t"] = float(f["t"]) + delta
					if float(f["t"]) > 0.85:
						f["state"] = "idle"
				"fall":
					f["t"] = float(f["t"]) + delta
					if float(f["t"]) > 0.75:
						f["state"] = "dead"
				"flee":
					f["t"] = float(f["t"]) + delta
					var away := -1.0 if f["side"] == 0 else 1.0
					if float(f["t"]) > 0.25:
						f["cur"] = f["cur"] + Vector2(away * 200.0 * float(f["scale"]) * delta, 0)
					f["alpha"] = clampf(1.6 - float(f["t"]) * 0.8, 0.0, 1.0)
					if float(f["alpha"]) <= 0.0:
						f["state"] = "gone"
						f["alive"] = false
		for side in [0, 1]:
			if float(_flag_fled[side]) >= 0.0:
				_flag_fled[side] = float(_flag_fled[side]) + delta
				if float(_flag_fled[side]) > 0.25:
					_flag_x[side] = float(_flag_x[side]) + (-1.0 if side == 0 else 1.0) * 200.0 * delta
			else:
				_flag_x[side] = move_toward(float(_flag_x[side]), _flag_target(side), 380.0 * delta)
		var i := puffs.size() - 1
		while i >= 0:
			puffs[i]["t"] = float(puffs[i]["t"]) + delta
			if float(puffs[i]["t"]) > 1.4:
				puffs.remove_at(i)
			i -= 1
		queue_redraw()

	func _frame(an: Dictionary, idx: int) -> Rect2:
		var cols: int = int(an["cols"])
		idx = clampi(idx, 0, int(an["frames"]) - 1)
		return Rect2((idx % cols) * float(an["fw"]), (idx / cols) * float(an["fh"]), float(an["fw"]), float(an["fh"]))

	func _draw() -> void:
		if _anims.get("fire", {}).is_empty():
			return
		## flag bearers behind each line, colours flying
		var flag: Dictionary = _anims.get("flag", {})
		for side in [0, 1]:
			var fled: float = float(_flag_fled[side])
			if flag.is_empty() or (_alive(side).is_empty() and fled < 0.0):
				continue
			var pid: String = a_pid if side == 0 else b_pid
			var alpha: float = 1.0 if fled < 0.0 else clampf(1.6 - fled * 0.8, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var an: Dictionary = flag
			var fi: int = _pick(an, int((_clock + side * 0.7) * 10.0), true)
			var flip: bool = side == 1
			if fled >= 0.0:
				flip = not flip
			_draw_anim(an, fi, Vector2(float(_flag_x[side]), size.y * 0.8), 1.05, flip, _tint(pid), alpha)
		var order := figs.duplicate()
		order.sort_custom(func(x, y): return x["cur"].y < y["cur"].y)
		for f in order:
			if f["state"] == "gone":
				continue
			var pid2: String = a_pid if f["side"] == 0 else b_pid
			var col: Color = _tint(pid2)
			var an: Dictionary = _anims["idle"]
			var fi := 0
			var flip: bool = f["side"] == 1
			match str(f["state"]):
				"idle":
					fi = _pick(an, int((_clock + float(f["phase"])) * 9.0), true)
				"march":
					an = _anims["march"]
					fi = _pick(an, int((_clock + float(f["phase"])) * 14.0), true)
				"flee":
					an = _anims["march"]
					fi = _pick(an, int((_clock + float(f["phase"])) * 14.0), true)
					flip = not flip
				"fire":
					an = _anims["fire"]
					fi = _pick(an, int(float(f["t"]) / 0.85 * float(_len(an))), false)
				"fall", "dead":
					fi = _pick(an, 0, false)
			var tilt := 0.0
			if f["state"] == "fall" or f["state"] == "dead":
				## over backwards, away from the enemy, with a little bounce as he lands
				var k: float = clampf(float(f["t"]) / 0.42, 0.0, 1.0) if f["state"] == "fall" else 1.0
				var e: float = k * k
				if k >= 1.0 and f["state"] == "fall":
					e = 1.0 - 0.06 * sin(clampf((float(f["t"]) - 0.42) / 0.3, 0.0, 1.0) * PI)
				tilt = (1.0 if flip else -1.0) * PI * 0.5 * e
				col = col.darkened(0.45 * e)
			_draw_anim(an, fi, f["cur"], float(f["scale"]), flip, col, float(f["alpha"]), tilt)
		for p in puffs:
			var t: float = float(p["t"])
			if t < 0.0:
				continue
			## powder smoke: a soft cluster of billows that swells, drifts up and thins
			var r: float = (20.0 if p["big"] else 9.0) + t * (58.0 if p["big"] else 24.0)
			var a: float = clampf(0.34 - t * 0.24, 0.0, 0.34)
			var c: Vector2 = p["pos"] + Vector2(t * 10.0, -t * 20.0)
			for k in 5:
				var off := Vector2.from_angle(float(k) * 1.26 + float(p.get("seed", 0.0))) * r * 0.55
				draw_circle(c + off, r * (0.62 + 0.08 * k), Color(0.88, 0.87, 0.83, a * (0.7 + 0.06 * k)))
			if t < 0.09:
				draw_circle(p["pos"], 8.0, Color(1.0, 0.8, 0.35, 0.9 * (1.0 - t / 0.09)))

	func _draw_anim(an: Dictionary, idx: int, foot: Vector2, sc: float, flip: bool, col: Color, alpha: float, tilt: float = 0.0) -> void:
		## Drawn from the feet: the soldier stands FIG_H * sc tall whatever the canvas.
		var h: float = FIG_H * 1.75 * sc / float(an["fill"])
		var w: float = h * float(an["fw"]) / float(an["fh"])
		draw_set_transform(foot, tilt, Vector2(-1 if flip else 1, 1))
		draw_texture_rect_region(an["tex"], Rect2(Vector2(-w * float(an["ax"]), -h * float(an["ay"])), Vector2(w, h)), _frame(an, idx), Color(col, col.a * alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _tint(pid: String) -> Color:
		return Style.seat_color(pid).lightened(0.18) if pid != "neutral" else Color(0.72, 0.7, 0.66)


class _Die extends Control:
	var value := 1
	var rolling := false
	var dim := false:
		set(v):
			dim = v
			queue_redraw()
	var tint := Color.WHITE
	var _tick := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(70, 70)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if rolling:
			_tick += delta
			if _tick > 0.055:
				_tick = 0.0
				value = randi_range(1, 6)
				queue_redraw()

	func _draw() -> void:
		var s: Vector2 = size
		var wob := randf_range(-0.2, 0.2) if rolling else 0.0
		var lift := randf_range(-6.0, 0.0) if rolling else 0.0
		draw_set_transform(s * 0.5 + Vector2(0, lift), wob, Vector2.ONE)
		var r := Rect2(-s * 0.42, s * 0.84)
		var body := StyleBoxFlat.new()
		body.bg_color = Color(0.97, 0.94, 0.86) if not dim else Color(0.55, 0.53, 0.5)
		body.border_color = tint.darkened(0.1) if not dim else tint.darkened(0.6)
		body.set_border_width_all(5)
		body.set_corner_radius_all(11)
		body.shadow_color = Color(0, 0, 0, 0.5)
		body.shadow_size = 6
		body.shadow_offset = Vector2(2, 4)
		draw_style_box(body, r)
		## a lacquer highlight
		draw_rect(Rect2(r.position + Vector2(8, 6), Vector2(r.size.x - 16, 7)), Color(1, 1, 1, 0.35 if not dim else 0.1))
		var pips := {
			1: [Vector2(0, 0)], 2: [Vector2(-1, -1), Vector2(1, 1)], 3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
			4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
			5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
			6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
		}
		var pc := Color(0.14, 0.08, 0.06) if value != 1 else Color(0.7, 0.1, 0.08)
		for p in pips[clampi(value, 1, 6)]:
			draw_circle(p * r.size.x * 0.27, 6.0, pc if not dim else pc.lightened(0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
