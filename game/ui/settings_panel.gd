## Volume, battle speed, advisor, text size, fullscreen. Saved as you change them.
extends Control

const Style := preload("res://game/core/style.gd")

signal closed


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
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(560, 0)
	p.add_child(v)
	v.add_child(Style.label("Settings", 40, Style.CREAM, "display"))
	v.add_child(_slider("Music", "music"))
	v.add_child(_slider("Sound effects", "sfx"))
	v.add_child(_slider("Campfire ambience", "ambience"))
	v.add_child(_slider("Voices", "voices"))
	v.add_child(_choice("Commander voices", "commander_voices", ["New take", "Classic (v1.2)"], ["new", "classic"]))
	v.add_child(_choice("Lands in new games", "deal", ["Dealt at random", "Claimed in turn (dice for order)"], ["random", "draft"]))
	v.add_child(_choice("Battle scenes", "battles", ["Show my battles", "Show every battle", "Map only"], ["mine", "all", "off"]))
	v.add_child(_toggle("Roll the dice yourself in your battles", "roll_yourself"))
	v.add_child(_choice("Battle speed", "speed", ["Slow — savor every roll", "Normal", "Fast"], ["slow", "normal", "fast"]))
	v.add_child(_choice("Text size", "ui_scale", ["Normal", "Large", "Extra large"], [1.0, 1.15, 1.3]))
	v.add_child(_toggle("Advisor tips", "tips"))
	v.add_child(_toggle("Show enemy ceilings (≤) on the map", "ceilings"))
	v.add_child(_toggle("Fullscreen", "fullscreen"))
	var done := Style.button("Done", func(): closed.emit(), 0, 22)
	done.custom_minimum_size = Vector2(0, 56)
	v.add_child(done)


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


func _toggle(title: String, key: String) -> Control:
	var h := _row(title)
	var t := CheckButton.new()
	t.button_pressed = bool(Settings.get_value(key, false))
	t.toggled.connect(func(on): Settings.set_value(key, on))
	h.add_child(t)
	return h
