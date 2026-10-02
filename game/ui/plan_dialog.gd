## "Here is what I would do, Commander." The advisor's drafted sheet, in plain words.
extends Control

const Style := preload("res://game/core/style.gd")
const Counsel := preload("res://game/core/counsel.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")

var session: Node
var _sheet
var _box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.flat(Color(0.93, 0.87, 0.74, 0.98), Color(0.36, 0.26, 0.14), 3, 10, 22))
	c.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var face := LeaderFace.new()
	face.custom_minimum_size = Vector2(130, 130)
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	face.bubble_side = "none"
	h.add_child(face)
	face.setup("advisor", "", "Your advisor")
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_box.custom_minimum_size = Vector2(520, 0)
	h.add_child(_box)
	_sheet = Counsel.draft(session)
	_box.add_child(Style.label("Here is what I would do, Commander.", 26, Color(0.25, 0.12, 0.06), "display"))
	for line in Counsel.explain(session, _sheet):
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		var ic := TextureRect.new()
		ic.texture = Style.icon(str(line[0]))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(28, 28)
		r.add_child(ic)
		var l := Style.label(str(line[1]), 18, Color(0.14, 0.09, 0.05))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		_box.add_child(r)
	_box.add_child(Style.label("It replaces what you have drafted this round. You can still change anything before sealing.", 15, Color(0.35, 0.25, 0.15), "italic"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Style.button("Use this plan", func():
		Counsel.adopt(session, _sheet)
		session.begin_orders() ## the plan places the recruits and writes the orders: show the orders
		Audio.sfx("seal", -6.0)
		queue_free(), 0, 20))
	row.add_child(Style.button("Keep my own", func(): queue_free(), 0, 20))
	_box.add_child(row)
	face.react("happy", "plan", 2.0)


func _unhandled_input(e: InputEvent) -> void:
	## v1.14: Esc keeps your own sheet (it used to put the pause menu over the plan)
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
