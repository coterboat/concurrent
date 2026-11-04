## The battlefield's foot, under the dice: Auto-roll, the dial (ROLL, PRESS ON, NEXT), ? Dice and Skip battles.
## v2.6 (Alex's call C17; peeled out of battle_theater.gd): the chips stand Style.CHIP_H tall, about 32 px on a
## 1366×768 laptop at Large text (they were 22 to 24), and the strip is as tall as the dial, whose rim it used
## to hang 4 px below the foot of the screen. Space, Enter and Esc stay the battlefield's (battle_theater.gd).
extends HBoxContainer

const Style := preload("res://game/core/style.gd")

signal auto_pressed
signal dial_pressed
signal help_pressed
signal skip_pressed

const DIAL := 96.0
const FOOT := 6.0 ## from the foot of the screen to the strip's

var auto_btn: Button
var dial: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	offset_bottom = -FOOT
	offset_top = -FOOT - DIAL - 2.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 18)
	auto_btn = _chip("Auto-roll ▶", func(): auto_pressed.emit(), Style.CREAM)
	add_child(auto_btn)
	dial = load("res://game/ui/command_bar.gd")._Dial.new()
	dial.custom_minimum_size = Vector2(DIAL, DIAL)
	dial.size = Vector2(DIAL, DIAL)
	dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dial.pressed.connect(func(): dial_pressed.emit())
	add_child(dial)
	var dh := _chip("? Dice", func(): help_pressed.emit(), Style.PARCH)
	dh.tooltip_text = "How a throw is scored, and why big armies roll finer dice"
	add_child(dh)
	var skip := _chip("Skip battles ▶▶", func(): skip_pressed.emit(), Style.PARCH)
	skip.tooltip_text = "Settle this round's remaining battles on the map (Esc): your standing orders decide the calls"
	add_child(skip)


func _chip(t: String, cb: Callable, color: Color) -> Button:
	var b := Style.chip(t, cb, color, 16)
	b.custom_minimum_size.y = Style.CHIP_H
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b
