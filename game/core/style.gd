## Colors, fonts, token shapes and the game Theme. One place for the look.
extends RefCounted

const INK := Color(0.043, 0.071, 0.125) ## deep navy
const INK_2 := Color(0.07, 0.10, 0.16)
const PANEL := Color(0.055, 0.08, 0.13, 0.96)
const CREAM := Color(0.93, 0.89, 0.8)
const PARCH := Color(0.87, 0.8, 0.66)
const MUTED := Color(0.66, 0.64, 0.6)
const GOLD := Color(0.86, 0.69, 0.34)
const CRIMSON := Color(0.74, 0.2, 0.16)
const GOOD := Color(0.45, 0.72, 0.42)
const WARN := Color(0.93, 0.55, 0.25)

const SEATS := {
	"red": {"color": Color(0.78, 0.22, 0.17), "shape": "circle", "label": "Crimson"},
	"blue": {"color": Color(0.2, 0.42, 0.75), "shape": "square", "label": "Azure"},
	"green": {"color": Color(0.2, 0.58, 0.34), "shape": "diamond", "label": "Verdant"},
	"gold": {"color": Color(0.88, 0.68, 0.16), "shape": "hexagon", "label": "Gold"},
	"purple": {"color": Color(0.55, 0.33, 0.7), "shape": "shield", "label": "Violet"},
	"neutral": {"color": Color(0.5, 0.47, 0.43), "shape": "octagon", "label": "Neutral"},
}

static var _fonts := {}
static var _theme: Theme
static var _tex := {}


static func seat_color(pid: String) -> Color:
	if SEATS.has(pid):
		return SEATS[pid]["color"]
	return Color(0.28, 0.28, 0.3)


static func seat_shape(pid: String) -> String:
	return str(SEATS.get(pid, {}).get("shape", "circle"))


static func font(kind: String = "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"display":
			var v := FontVariation.new()
			v.base_font = load("res://assets/fonts/Cinzel.ttf")
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
			f = v
		"display_light":
			var v2 := FontVariation.new()
			v2.base_font = load("res://assets/fonts/Cinzel.ttf")
			v2.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
			f = v2
		"bold":
			f = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
		"italic":
			f = load("res://assets/fonts/AlegreyaSans-Italic.ttf")
		_:
			f = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
	_fonts[kind] = f
	return f


static func tex(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex[path] = t
	return t


static func icon(name: String) -> Texture2D:
	return tex("res://assets/icons/%s.png" % name)


static func portrait(name: String) -> Texture2D:
	## v1.2 portraits are cut-out PNGs; older ones were WebP.
	var t: Texture2D = tex("res://assets/portraits/%s.png" % name)
	return t if t != null else tex("res://assets/portraits/%s.webp" % name)


static func card_tex(kind: String) -> Texture2D:
	return tex("res://assets/cards/%s.webp" % kind)


static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 6, pad: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	sb.anti_aliasing = true
	return sb


static func panel_box(pad: int = 18) -> StyleBox:
	var t: Texture2D = tex("res://game/ui/panel.png")
	if t == null:
		return flat(PANEL, GOLD, 2, 8, pad)
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = 44
	sb.texture_margin_right = 44
	sb.texture_margin_top = 44
	sb.texture_margin_bottom = 44
	sb.content_margin_left = pad + 4
	sb.content_margin_right = pad + 4
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 19
	t.set_color("font_color", "Label", CREAM)
	## Buttons: painted plate from Ludo, flat fallbacks for states.
	var plate: Texture2D = tex("res://game/ui/button.png")
	var normal: StyleBox
	if plate != null:
		var sb := StyleBoxTexture.new()
		sb.texture = plate
		sb.region_rect = Rect2(40, 34, 432, 222)
		sb.texture_margin_left = 20
		sb.texture_margin_right = 20
		sb.texture_margin_top = 16
		sb.texture_margin_bottom = 16
		sb.content_margin_left = 24
		sb.content_margin_right = 24
		sb.content_margin_top = 10
		sb.content_margin_bottom = 12
		normal = sb
	else:
		normal = flat(INK_2, CREAM, 2, 6, 14)
	var hover: StyleBox = normal.duplicate()
	if hover is StyleBoxTexture:
		(hover as StyleBoxTexture).modulate_color = Color(1.18, 1.12, 1.0)
	var pressed: StyleBox = normal.duplicate()
	if pressed is StyleBoxTexture:
		(pressed as StyleBoxTexture).modulate_color = Color(0.8, 0.78, 0.74)
	var disabled: StyleBox = normal.duplicate()
	if disabled is StyleBoxTexture:
		(disabled as StyleBoxTexture).modulate_color = Color(0.55, 0.55, 0.58, 0.8)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.82))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_font("font", "Button", font("bold"))
	t.set_font_size("font_size", "Button", 20)
	## Panels
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, Color(GOLD, 0.55), 1, 8, 14))
	t.set_stylebox("panel", "Panel", flat(PANEL, Color(GOLD, 0.55), 1, 8, 14))
	## Inputs
	var field := flat(Color(0.03, 0.05, 0.09, 0.9), Color(GOLD, 0.5), 1, 5, 10)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", flat(Color(0.03, 0.05, 0.09, 0.95), GOLD, 2, 5, 10))
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_stylebox("normal", "OptionButton", field)
	t.set_stylebox("hover", "OptionButton", flat(Color(0.06, 0.09, 0.14, 0.95), GOLD, 1, 5, 10))
	t.set_stylebox("pressed", "OptionButton", field)
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", CREAM)
	t.set_font("font", "OptionButton", font("body"))
	t.set_stylebox("panel", "PopupMenu", flat(Color(0.05, 0.07, 0.11, 0.98), GOLD, 1, 6, 8))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("hover", "PopupMenu", flat(Color(0.12, 0.15, 0.22), Color(0, 0, 0, 0), 0, 4, 6))
	t.set_font_size("font_size", "PopupMenu", 19)
	## Sliders / checks
	t.set_stylebox("slider", "HSlider", flat(Color(0.2, 0.2, 0.24), Color(0, 0, 0, 0), 0, 3, 3))
	t.set_stylebox("grabber_area", "HSlider", flat(GOLD, Color(0, 0, 0, 0), 0, 3, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(Color(1, 0.8, 0.45), Color(0, 0, 0, 0), 0, 3, 3))
	t.set_color("font_color", "CheckBox", CREAM)
	t.set_color("font_color", "CheckButton", CREAM)
	t.set_font_size("font_size", "CheckButton", 19)
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	## Tooltips
	t.set_stylebox("panel", "TooltipPanel", flat(Color(0.04, 0.06, 0.1, 0.97), GOLD, 1, 5, 10))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_font_size("font_size", "TooltipLabel", 17)
	## Scroll
	t.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber", "VScrollBar", flat(Color(GOLD, 0.45), Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(GOLD, Color(0, 0, 0, 0), 0, 3, 2))
	_theme = t
	return t


static func says(name: String, verb: String) -> String:
	## "Varek holds", but "You hold": the default human seat is called You
	if name.strip_edges().to_lower() != "you":
		return "%s %s" % [name, verb]
	var irregular := {"is": "are", "has": "have", "does": "do", "was": "were"}
	var v: String = verb
	if irregular.has(v):
		v = irregular[v]
	elif v.ends_with("ches") or v.ends_with("shes") or v.ends_with("sses") or v.ends_with("xes") or v.ends_with("zes"):
		v = v.substr(0, v.length() - 2)
	elif v.ends_with("ies"):
		v = v.substr(0, v.length() - 3) + "y"
	elif v.ends_with("s"):
		v = v.substr(0, v.length() - 1)
	return "%s %s" % [name, v]


static func plural(n: int, one: String, many: String = "") -> String:
	return "%d %s" % [n, one if n == 1 else (many if many != "" else one + "s")]


static func label(text: String, size: int = 19, color: Color = CREAM, kind: String = "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w: int = 0, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 60)
	b.pressed.connect(func():
		var a := b.get_tree().root.get_node_or_null("Audio") if b.is_inside_tree() else null
		if a:
			a.sfx("click")
		cb.call())
	return b


static func chip(text: String, cb: Callable, color: Color = CREAM, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", font("bold"))
	b.add_theme_stylebox_override("normal", flat(Color(0.1, 0.13, 0.19, 0.95), Color(color, 0.7), 1, 5, 8))
	b.add_theme_stylebox_override("hover", flat(Color(0.16, 0.19, 0.27, 0.98), color, 1, 5, 8))
	b.add_theme_stylebox_override("pressed", flat(Color(0.06, 0.08, 0.12, 0.98), color, 2, 5, 8))
	b.add_theme_stylebox_override("disabled", flat(Color(0.08, 0.09, 0.12, 0.7), Color(0.3, 0.3, 0.3), 1, 5, 8))
	b.add_theme_color_override("font_color", color)
	b.pressed.connect(func():
		var a := b.get_tree().root.get_node_or_null("Audio") if b.is_inside_tree() else null
		if a:
			a.sfx("click")
		cb.call())
	return b


static func draw_shape(ci: CanvasItem, shape: String, c: Vector2, r: float, fill: Color, edge: Color, edge_w: float) -> void:
	var pts := shape_points(shape, c, r)
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, edge, edge_w, true)


static func shape_points(shape: String, c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		"square":
			for i in 32:
				var a := i * TAU / 32.0
				var x := cos(a)
				var y := sin(a)
				pts.append(c + Vector2(signf(x) * pow(absf(x), 0.35), signf(y) * pow(absf(y), 0.35)) * r * 0.9)
		"diamond":
			for i in 4:
				var a := i * PI / 2.0 - PI / 2.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 1.12)
		"hexagon":
			for i in 6:
				var a := i * PI / 3.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
		"octagon":
			for i in 8:
				var a := i * PI / 4.0 + PI / 8.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
		"shield":
			pts.append(c + Vector2(-r * 0.9, -r * 0.85))
			pts.append(c + Vector2(r * 0.9, -r * 0.85))
			pts.append(c + Vector2(r * 0.9, r * 0.1))
			for i in range(1, 8):
				var t := float(i) / 8.0
				pts.append(c + Vector2(r * 0.9 * (1.0 - t), r * 0.1 + r * 1.0 * sin(t * PI / 2.0)))
			for i in range(0, 8):
				var t := 1.0 - float(i) / 8.0
				pts.append(c + Vector2(-r * 0.9 * (1.0 - t), r * 0.1 + r * 1.0 * sin(t * PI / 2.0)))
		_:
			for i in 24:
				var a := i * TAU / 24.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
