## Volume, battle speed, advisor, text size, fullscreen. Saved as you change them.
extends Control

const Style := preload("res://game/core/style.gd")

signal closed

var _scroll: ScrollContainer ## v2.5: the rows, so the panel is never taller than the screen
var _rows: VBoxContainer
var _head: Control
var _done: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(c)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.panel_box(28))
	c.add_child(p)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	outer.custom_minimum_size = Vector2(560, 0)
	p.add_child(outer)
	_head = Style.label("Settings", 40, Style.CREAM, "display")
	outer.add_child(_head)
	## v2.5: at Large text the panel stood 827 high in a 783 screen, its Done below the edge. The rows
	## scroll when the screen is shorter than they are; the title and Done stay put
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows = v
	_scroll.add_child(v)
	v.add_child(_slider("Music", "music"))
	v.add_child(_slider("Sound effects", "sfx"))
	v.add_child(_slider("Campfire ambience", "ambience"))
	v.add_child(_slider("Voices", "voices"))
	v.add_child(_choice("Commander voices", "commander_voices", ["New take", "Classic (v1.2)"], ["new", "classic"]))
	v.add_child(_choice("Battle scenes", "battles", ["Show my battles", "Show every battle", "Map only"], ["mine", "all", "off"]))
	v.add_child(_toggles("The land in 3D", [["The map", "map_land"], ["Battles", "battle_land"]])) ## v2.0 (L in a game)
	v.add_child(_toggle("Roll the dice yourself in your battles", "roll_yourself"))
	v.add_child(_choice("Films", "motion", ["Cutscenes and living paintings", "Living paintings only", "Still paintings"], ["all", "paintings", "off"]))
	v.add_child(_choice("Battle speed", "speed", ["Slow — savor every roll", "Normal", "Fast"], ["slow", "normal", "fast"]))
	v.add_child(_choice("Text size", "ui_scale", ["Normal", "Large"], [1.0, Settings.UI_SCALE_MAX])) ## (v2.5: no Extra large, see settings.gd)
	v.add_child(_toggle("Advisor tips", "tips"))
	v.add_child(_toggle("Show enemy ceilings (≤) at your borders", "ceilings"))
	v.add_child(_toggle("Fullscreen", "fullscreen"))
	var done := Style.button("Done", func(): closed.emit(), 0, 22)
	done.custom_minimum_size = Vector2(0, 56)
	_done = done
	outer.add_child(done)
	resized.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	## the rows as tall as they are, or as the screen leaves room for (the panel's frame and margins,
	## the title, Done, and a breath above and below)
	if _rows == null:
		return
	var room: float = get_viewport_rect().size.y - 2.0 * 28.0 - _head.get_combined_minimum_size().y - _done.get_combined_minimum_size().y - 2.0 * 10.0 - 40.0
	_scroll.custom_minimum_size.y = minf(_rows.get_combined_minimum_size().y, maxf(room, 120.0))


func _row(title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := Style.label(title, 20, Style.CREAM, "bold")
	l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	return h


func _slider(title: String, key: String) -> Control:
	var h := _row(title)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get_value(key, 0.5))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(240, 30)
	s.value_changed.connect(func(val):
		Settings.set_value(key, val)
		if key == "sfx":
			Audio.sfx("click"))
	h.add_child(s)
	return h


func _choice(title: String, key: String, labels: Array, values: Array) -> Control:
	var h := _row(title)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size = Vector2(0, 40)
	for x in labels:
		o.add_item(x)
	var cur = Settings.get_value(key)
	var idx := 0
	for i in values.size():
		if str(values[i]) == str(cur):
			idx = i
	o.selected = idx
	o.item_selected.connect(func(i): Settings.set_value(key, values[i]))
	h.add_child(o)
	return h


func _toggles(title: String, pairs: Array) -> Control:
	## several switches on one row: [[label, key], ...]
	var h := _row(title)
	for pr in pairs:
		var t := CheckButton.new()
		t.text = str(pr[0])
		t.button_pressed = bool(Settings.get_value(str(pr[1]), true))
		var key: String = str(pr[1])
		t.toggled.connect(func(on): Settings.set_value(key, on))
		h.add_child(t)
	return h


func _toggle(title: String, key: String) -> Control:
	var h := _row(title)
	var t := CheckButton.new()
	t.button_pressed = bool(Settings.get_value(key, false))
	t.toggled.connect(func(on): Settings.set_value(key, on))
	h.add_child(t)
	return h


func _input(e: InputEvent) -> void:
	## v1.14: Esc closes the settings (in a game it used to open the pause menu, hidden behind them).
	## v2.0.1: first in line, so nothing under the panel can take the key first (the play critic's
	## Esc once left them up; not reproduced, so the panel no longer waits its turn for it)
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE and is_visible_in_tree():
		closed.emit()
		get_viewport().set_input_as_handled()
