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
const BattleField := preload("res://game/ui/battle_field.gd")

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
var _fronts: Array = [] ## the melee's fronts from the event
var _left: Array = [] ## men standing per army: fronts (or the one attacker) first, the defender last
var _extra: Array = [] ## [{face, name, count}] rings for the second and third invaders
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
	_field = BattleField.new()
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
	else:
		_fronts = []
		_a_pid = str(b["a"])
		_b_pid = str(b["b"])
		_rolls = e.get("rolls", [])
		_volley_mode = not _rolls.is_empty() and (_rolls[0] as Dictionary).has("sa")
		_left = [int(b["a_size"]), int(b["b_size"])]
		list = [{"pid": _a_pid, "side": 0, "n": _left[0]}, {"pid": _b_pid, "side": 1, "n": _left[1]}]
	_a_left = _left[0]
	_b_left = _left[_def()]
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
		_:
			_sub.text = "%s attacks from %s" % [session.name_of(_a_pid), session.hex_name(str(e.get("from", "")))]
	_setup_side(_face_a, _name_a, _melee_lead_pid() if _melee else _a_pid, true)
	_setup_side(_face_b, _name_b, _b_pid, false)
	_setup_extras()
	_update_counts()
	_field.setup(list)
	_result.text = ""
	_score.text = ("Every front fights at once: die × 5 + armies against the defenders' share there." if _melee else "Each volley: die × 5 + armies. Loser of the volley loses one.") if _volley_mode else "One roll: armies + die. Higher total wins."
	_clear_dice()
	_progress.text = "Battle %d of %d at this land" % [_bi + 1, _beats.size()] if _beats.size() > 1 else ""
	if not _spoken_attack:
		_spoken_attack = true
		var who: String = _who(_melee_lead_pid() if _melee else _a_pid)
		if Lines.has(who, "attack"):
			_face_a.react("win", "attack", 2.4)
		else:
			_face_a.react("happy")
		if _melee:
			Audio.sfx("melee", -4.0)
			if _advisor.visible:
				get_tree().create_timer(1.2).timeout.connect(func(): _advisor.react("alarm", "melee", 3.0))
	_state = "ready"
	_auto_t = 1.4 ## let them march in
	_dial.set_label("ROLL", "Space")


func _melee_lead_pid() -> String:
	return str(_fronts[_lead_front()]["attackerId"]) if not _fronts.is_empty() else _a_pid


func _lead_front() -> int:
	for i in _fronts.size():
		if str(_fronts[i]["attackerId"]) == _a_pid:
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
	if not _melee:
		return
	var k := 0
	for i in _fronts.size():
		if i == _lead_front():
			continue
		var pid: String = str(_fronts[i]["attackerId"])
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
	if not _melee or i == _lead_front():
		return _face_a
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
	if _melee:
		_count_a.text = str(maxi(0, int(_left[_lead_front()])))
		for x in _extra:
			(x["count"] as Label).text = str(maxi(0, int(_left[int(x["front"])])))
	else:
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
	## one exchange: three volleys (or three salvos of a melee, or the one decisive roll)
	var chunk: Array = []
	if _melee:
		while _ri < _rolls.size() and chunk.size() < Combat.EXCHANGE:
			chunk.append(_rolls[_ri])
			_ri += 1
	elif _volley_mode:
		var decided := 0
		while _ri < _rolls.size() and decided < Combat.EXCHANGE:
			chunk.append(_rolls[_ri])
			_ri += 1
			if str(chunk[-1].get("w", "")) != "":
				decided += 1
	else:
		chunk = _rolls.duplicate()
		_ri = _rolls.size()
	Audio.sfx("dice")
	var t := 0.55 if manual else 0.4
	var tw := create_tween()
	tw.tween_interval(t)
	for r in chunk:
		tw.tween_callback(func(): _show_roll(r))
		tw.tween_interval(0.5 if _melee else (0.42 if _volley_mode else 0.2))
	tw.tween_callback(func(): _after_exchange())


func _show_roll(r: Variant) -> void:
	## lay out this volley's (or salvo's) dice, then settle them
	_clear_dice()
	var pairs: Array = r if _melee else [r]
	var made: Array = []
	for v in pairs:
		var ap: String = str(_fronts[int(v["i"])]["attackerId"]) if _melee else _a_pid
		var da := _Die.new()
		da.tint = Style.seat_color(ap)
		da.rolling = true
		_dice_a.add_child(da)
		var db := _Die.new()
		db.tint = Style.seat_color(_b_pid)
		db.rolling = true
		_dice_b.add_child(db)
		made.append([da, db, v])
	var tw := create_tween()
	tw.tween_interval(0.18)
	tw.tween_callback(func():
		var lines: Array = []
		for m in made:
			lines.append(_settle(m[0], m[1], m[2]))
		if _melee:
			_score.text = "    ·    ".join(lines))


func _settle(da: _Die, db: _Die, r: Dictionary) -> String:
	da.rolling = false
	db.rolling = false
	da.value = int(r["a"])
	db.value = int(r["b"])
	var w: String = str(r.get("w", ""))
	if not _volley_mode:
		return ""
	var fi: int = int(r.get("i", 0))
	var army: int = _army_of_front(fi) if _melee else 0
	var ap: String = str(_fronts[fi]["attackerId"]) if _melee else _a_pid
	var sa: float = 5.0 * int(r["a"]) + float(r["sa"])
	var sb: float = 5.0 * int(r["b"]) + float(r["sd"])
	if w == "":
		_score.text = "%d vs %d — a tie in the field. Roll again." % [int(sa), int(sb)]
		da.dim = true
		db.dim = true
		return ""
	var line: String
	if _melee:
		line = "%s %s" % [session.name_of(ap), "✔" if w == "a" else "✘"]
	else:
		_score.text = "%s  5×%d + %d = %d    vs    %s  5×%d + %d = %d" % [session.name_of(ap), r["a"], r["sa"], int(sa), session.name_of(_b_pid) if _b_pid != "neutral" else "Neutral", r["b"], r["sd"], int(sb)]
		line = ""
	var sound := "volley"
	if w == "a":
		db.dim = true
		_left[_def()] = int(_left[_def()]) - 1
		sound = _field.volley(army)
		_flinch(_face_b)
	else:
		da.dim = true
		_left[army] = int(_left[army]) - 1
		sound = _field.volley(_def())
		_flinch(_face_of_front(fi) if _melee else _face_a)
	_a_left = int(_left[0])
	_b_left = int(_left[_def()])
	_field.set_count(army, maxi(0, int(_left[army])))
	_field.set_count(_def(), maxi(0, int(_left[_def()])))
	_update_counts()
	Audio.sfx(sound, -5.0 if sound == "volley" else -3.0, 0.12)
	get_tree().create_timer(0.12).timeout.connect(func(): Audio.sfx("hit", -9.0, 0.15))
	return line


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
	var pr: float = Combat.capture_rate(a, d, Combat.MODE_VOLLEYS)
	var who: String = session.name_of(str(p.get("attacker", "")))
	_odds.text = ("%s's call · " % who if _melee else "") + "From here: %s — %d%% to take it" % [Combat.odds_word(a, d, Combat.MODE_VOLLEYS), int(round(pr * 100.0))]
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
			_sub.text = "%s throws in the reserves from home" % session.name_of(pid)
			Audio.sfx("reserves", -2.0)
			get_tree().create_timer(0.5).timeout.connect(func(): Audio.sfx("hurrah", -4.0))
			if Lines.has(who, "reserves"):
				face.react("happy", "reserves", 2.4)
			elif _advisor.visible and session.is_human(pid):
				face.react("happy")
				_advisor.react("happy", "reserves", 2.4)
		Combat.CALL_FALL_BACK:
			_shout_text("FALL BACK!", Style.PARCH)
			_sub.text = "%s sounds the retreat to %s" % [session.name_of(pid), session.hex_name(str(c.get("to", "")))]
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
		_result.text = ("%s falls back to %s — %d saved" % [session.name_of(_a_pid), session.hex_name(str(e.get("refuge", ""))), _a_left]).to_upper()
		Audio.sfx("hold")
	elif kind == "Invasion":
		_result.text = ("%s TAKES %s" % [session.name_of(winner), session.hex_name(land)]).to_upper() if a_won else ("%s HOLDS %s" % [session.name_of(winner) if winner != "neutral" else "THE GARRISON", session.hex_name(land)]).to_upper()
		Audio.sfx("capture" if a_won else "hold")
	else:
		_result.text = ("%s wins the field" % session.name_of(winner)).to_upper()
		Audio.sfx("clash")
	_result.add_theme_color_override("font_color", Style.seat_color(winner).lightened(0.5))
	_field.cheer(0 if a_won else 1)
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
		_result.text = ("%s HOLDS %s AGAINST ALL COMERS" % [session.name_of(_b_pid) if _b_pid != "neutral" else "THE GARRISON", session.hex_name(land)]).to_upper()
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
	get_tree().create_timer(0.35).timeout.connect(func(): Audio.sfx("cheer", -6.0))
	_state = "done"
	_auto_t = 2.6
	_dial.set_label("NEXT" if _bi < _beats.size() - 1 else "DONE", "")


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
