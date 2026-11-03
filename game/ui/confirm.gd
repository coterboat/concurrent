## A question over the screen, its answers as buttons (v2.5: the title's, How to Play's and the setup's,
## before a new war takes the place of the one that's saved). Any answer closes it; Esc closes it with
## none. The war's own questions are game_screen.gd's _confirm, which the pause menu's keys know about.
extends Control

const Style := preload("res://game/core/style.gd")
const SessionScript := preload("res://game/core/session.gd")

var title := ""
var body := ""
var choices: Array = [] ## [[label, Callable], ...]


static func saved_war_line() -> String:
	## the saved war, as the title's Continue names it ("" when there is none)
	if not SessionScript.has_save():
		return ""
	var info: Dictionary = SessionScript.save_summary()
	if info.is_empty():
		return ""
	return "Your war on %s is saved at round %s." % [info.get("map", ""), info.get("round", "?")]


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(c)
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
	for ch in choices:
		var cb: Callable = ch[1]
		row.add_child(Style.button(str(ch[0]), func():
			queue_free()
			cb.call(), 0, 19))


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE and is_visible_in_tree():
		queue_free()
		get_viewport().set_input_as_handled()
