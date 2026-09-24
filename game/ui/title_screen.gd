extends Control

const Style := preload("res://game/core/style.gd")
const SessionScript := preload("res://game/core/session.gd")

var main: Control
var _art: TextureRect
var _t := 0.0


func _ready() -> void:
	_art = TextureRect.new()
	_art.texture = Style.tex("res://assets/art/splash_title.webp")
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	var shade := TextureRect.new()
	shade.texture = _gradient()
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var col := VBoxContainer.new()
	col.set_anchors_preset(PRESET_LEFT_WIDE)
	col.offset_left = 90
	col.offset_right = 620
	col.offset_top = 0
	col.offset_bottom = 0
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var title := Style.label("CONCURRENT", 84, Style.CREAM, "display")
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	col.add_child(title)
	var rule := ColorRect.new()
	rule.color = Style.CRIMSON
	rule.custom_minimum_size = Vector2(300, 5)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)
	var tag := Style.label("Everyone commits at once. Attackers leave home empty.\nWhoever strips a border gets walked.", 22, Style.PARCH, "italic")
	col.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	col.add_child(gap)

	if SessionScript.has_save():
		var info: Dictionary = SessionScript.save_summary()
		var cont := Style.button("Continue  ·  %s, round %s" % [info.get("map", ""), info.get("round", "?")], func(): main.continue_game(), 420, 22)
		col.add_child(cont)
	col.add_child(Style.button("New Game", func(): main.show_setup(), 420, 22))
	if not bool(Settings.get_value("seen_tutorial", false)):
		col.add_child(Style.button("First time? Play the Tutorial", func(): _tutorial(), 420, 22))
	else:
		col.add_child(Style.button("Tutorial", func(): _tutorial(), 420, 22))
	col.add_child(Style.button("How to Play", func(): main.show_howto(), 420, 22))
	col.add_child(Style.button("Settings", func(): main.open_settings(), 420, 22))
	col.add_child(Style.button("Quit", func(): get_tree().quit(), 420, 22))

	var foot := Style.label("A SameTime conquest game  ·  art & sound made with Ludo.ai", 15, Color(Style.MUTED, 0.8), "italic")
	foot.set_anchors_preset(PRESET_BOTTOM_LEFT)
	foot.offset_left = 90
	foot.offset_top = -44
	add_child(foot)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)


func _tutorial() -> void:
	Settings.set_value("seen_tutorial", true)
	main.start_tutorial()


func _process(delta: float) -> void:
	## A slow drift over the war table.
	_t += delta
	var s := 1.06 + 0.02 * sin(_t * 0.07)
	_art.pivot_offset = _art.size * 0.5
	_art.scale = Vector2(s, s)
	_art.position = Vector2(sin(_t * 0.05) * 18.0, cos(_t * 0.04) * 10.0)


func _gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.06, 0.93))
	g.set_color(1, Color(0.02, 0.03, 0.06, 0.05))
	g.add_point(0.45, Color(0.02, 0.03, 0.06, 0.62))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0.5)
	t.fill_to = Vector2(1, 0.5)
	t.width = 256
	t.height = 16
	return t
