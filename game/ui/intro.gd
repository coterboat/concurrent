## "The commanders take their seats": each AI rival steps up and says hello.
extends Control

const Style := preload("res://game/core/style.gd")
const Lines := preload("res://game/core/lines.gd")
const Ai := preload("res://engine/ai.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")

signal finished

var session: Node
var _queue: Array = []
var _face: Control
var _name: Label
var _blurb: Label
var _line: Label
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TextureRect.new()
	bg.texture = Style.tex("res://assets/tex/wood.webp")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.modulate = Color(0.35, 0.32, 0.3, 0.97)
	add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(c)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	var head := Style.label("THE COMMANDERS TAKE THEIR SEATS", 26, Style.GOLD, "display")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, 250)
	v.add_child(holder)
	_face = LeaderFace.new()
	_face.custom_minimum_size = Vector2(240, 240)
	_face.bubble_side = "none"
	holder.add_child(_face)
	_name = Style.label("", 44, Style.CREAM, "display")
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_name)
	_blurb = Style.label("", 19, Style.PARCH, "italic")
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_blurb)
	_line = Style.label("", 24, Style.CREAM, "italic")
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(760, 0)
	v.add_child(_line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	row.add_child(Style.button("Next", func(): _next(), 180, 20))
	row.add_child(Style.button("To the war table", func(): _done(), 260, 20))
	visible = false


func play(p_session: Node) -> bool:
	session = p_session
	_queue = []
	for seat in session.seats:
		if seat["kind"] == "ai" and Lines.has(str(seat["ai"]), "greet"):
			_queue.append(seat)
	if _queue.is_empty():
		return false
	visible = true
	_next()
	return true


func _next() -> void:
	if _queue.is_empty():
		_done()
		return
	var seat: Dictionary = _queue.pop_front()
	var who: String = str(seat["ai"])
	_face.setup(who, str(seat["id"]), str(seat["name"]))
	_name.text = str(seat["name"])
	_name.add_theme_color_override("font_color", Style.seat_color(str(seat["id"])).lightened(0.45))
	var c: Dictionary = Ai.COMMANDERS.get(who, {})
	var level: String = {"recruit": "Easy", "veteran": "Medium", "general": "Hard"}.get(str(c.get("level", "")), "")
	_blurb.text = "%s  ·  %s" % [str(c.get("blurb", "")), level]
	_line.text = "“%s”" % Lines.text(who, "greet")
	var secs: float = _face.react("happy", "greet", 3.0)
	_t = maxf(2.2, secs + 0.8)
	_face.modulate.a = 0.0
	create_tween().tween_property(_face, "modulate:a", 1.0, 0.25)


func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_next()


func _done() -> void:
	if not visible:
		return
	visible = false
	finished.emit()


func _unhandled_input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and not Style.is_fullscreen_key(e):
		if e.keycode == KEY_ESCAPE:
			_done()
		else:
			_next()
		get_viewport().set_input_as_handled()
