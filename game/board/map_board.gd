## The campaign map. Status board first: counts readable from the couch,
## vacated origins look vacated, arrows say who is going where.
## Emits clicks and drags; the game screen decides what they mean.
extends Control

const Types := preload("res://engine/types.gd")
const Income := preload("res://engine/income.gd")
const Style := preload("res://game/core/style.gd")
const MapArt := preload("res://game/board/map_art.gd")

signal territory_clicked(id: String, button: int)
signal territory_hovered(id: String)
signal drag_order(from_id: String, to_id: String)
signal empty_clicked
signal arrow_clicked(from_id: String, to_id: String)

var art: RefCounted
var map: Types.MapDef
var world: Types.World
var viewer := "" ## whose eyes: own lands show caps, enemy lands show their ceiling
var selected := ""
var hovered := ""
var targets := {} ## id -> true, pulsing gold
var dimmed := {}
var battle := {}
var orders: Array = [] ## [{from, to, strength, owner, surge, kind: "attack"|"move"}]
var ghosts: Array = [] ## last round's packets
var placements := {} ## id -> queued reinforcements (viewer)
var show_ceiling := false
var ceiling_mult := 1 ## deployment folds two capped passes into one
var drag_from := ""
var fx: Array = [] ## floating texts {map, text, color, t, dur, size}
var shake := {} ## id -> seconds of token pulse
var interactive := true
var plain := false ## thumbnails: geography only, no tokens
var view_mode := 0 ## 0 owners, 1 regions
var pad_top := 0.0 ## screen space kept clear of the map at fit (HUD above)
var pad_bottom := 0.0 ## (HUD below)
var show_region_labels := true
var _label_hits: Array = [] ## [{pos, from, to}] arrow labels you can click
var _region_font: FontVariation

var zoom := 0.5
var offset := Vector2.ZERO
var fit := 0.5
var _at_fit := true
var terrain: TextureRect
var overlay: Control
var _mat: ShaderMaterial
var _state_img: Image
var _state_tex: ImageTexture
var _press_pos := Vector2.ZERO
var _press_id := ""
var _pressing := false
var _panning := false
var _mouse := Vector2.ZERO
var _time := 0.0
var _token_base := 17.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	terrain = TextureRect.new()
	terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(terrain)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	resized.connect(_on_resized)


func load_map(p_map: Types.MapDef) -> void:
	map = p_map
	art = MapArt.load_for(map.id)
	if art == null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://game/board/map.gdshader")
	_mat.set_shader_parameter("data_n", art.data_texture)
	_mat.set_shader_parameter("data_l", art.data_texture)
	_mat.set_shader_parameter("land_tex", Style.tex("res://assets/tex/land.webp"))
	_mat.set_shader_parameter("sea_tex", Style.tex("res://assets/tex/sea.webp"))
	_mat.set_shader_parameter("paper_tex", Style.tex("res://assets/tex/parchment.webp"))
	_mat.set_shader_parameter("map_size", art.size)
	_mat.set_shader_parameter("n_terr", float(art.order.size()))
	_state_img = Image.create(art.order.size(), 2, false, Image.FORMAT_RGBA8)
	_state_tex = ImageTexture.create_from_image(_state_img)
	_mat.set_shader_parameter("state_tex", _state_tex)
	var depths: Array = art.depth.values()
	depths.sort()
	_token_base = clampf(float(depths[depths.size() / 2]) * 0.2, 16.0, 26.0)
	terrain.texture = art.data_texture
	terrain.material = _mat
	terrain.size = art.size
	_at_fit = true
	_on_resized()


func refresh() -> void:
	if art == null or world == null:
		return
	for i in art.order.size():
		var id: String = art.order[i]
		var ts: Types.TerritoryState = world.get_territory(id)
		var owner: String = ts.owner if ts else ""
		var col: Color = Style.seat_color(owner)
		var flags := 0
		if targets.has(id):
			flags |= 1
		if dimmed.has(id):
			flags |= 2
		if battle.has(id):
			flags |= 4
		if owner == viewer and viewer != "":
			flags |= 8
		if owner == Types.UNOCCUPIED:
			flags |= 16
		_state_img.set_pixel(i, 0, Color(col.r, col.g, col.b, float(flags) / 255.0))
		var region: String = map.get_territory(id).region
		_state_img.set_pixel(i, 1, _region_tint(region))
	_state_tex.update(_state_img)
	_mat.set_shader_parameter("select_id", int(art.index.get(selected, -1)))
	_mat.set_shader_parameter("hover_id", int(art.index.get(hovered, -1)) if interactive else -1)
	overlay.queue_redraw()


func region_color(region: String) -> Color:
	if map != null and map.region_colors.has(region):
		return Color(str(map.region_colors[region]))
	if region == "":
		return Color(0.82, 0.78, 0.7)
	var h: float = float(hash(region) % 1000) / 1000.0
	return Color.from_hsv(h, 0.35, 0.85)


func _region_tint(region: String) -> Color:
	return region_color(region)


func set_view_mode(m: int) -> void:
	view_mode = m
	if _mat:
		_mat.set_shader_parameter("view_mode", m)
	overlay.queue_redraw()


# ------------------------------------------------------------------ view math

func map_to_screen(p: Vector2) -> Vector2:
	return offset + p * zoom


func screen_to_map(p: Vector2) -> Vector2:
	return (p - offset) / zoom


func anchor(id: String) -> Vector2:
	return map_to_screen(art.anchors.get(id, Vector2.ZERO))


func _on_resized() -> void:
	if art == null or size.x < 10 or size.y < 10:
		return
	var avail := Vector2(size.x, maxf(100.0, size.y - pad_top - pad_bottom))
	fit = minf(avail.x / art.size.x, avail.y / art.size.y)
	if _at_fit:
		zoom = fit
		offset = Vector2((size.x - art.size.x * zoom) * 0.5, pad_top + (avail.y - art.size.y * zoom) * 0.5)
	_apply_view()


func reset_view() -> void:
	_at_fit = true
	_on_resized()


func _apply_view() -> void:
	## Keep the map on screen.
	var span: Vector2 = art.size * zoom
	var slack := size * 0.35
	if span.x <= size.x:
		offset.x = (size.x - span.x) * 0.5
	else:
		offset.x = clampf(offset.x, size.x - span.x - slack.x, slack.x)
	if span.y <= size.y - pad_top - pad_bottom:
		offset.y = pad_top + (size.y - pad_top - pad_bottom - span.y) * 0.5
	else:
		offset.y = clampf(offset.y, size.y - span.y - slack.y, slack.y)
	terrain.position = offset
	terrain.scale = Vector2(zoom, zoom)
	_mat.set_shader_parameter("screen_per_texel", zoom)
	overlay.queue_redraw()


func zoom_at(screen_p: Vector2, factor: float) -> void:
	var before: Vector2 = screen_to_map(screen_p)
	zoom = clampf(zoom * factor, fit, fit * 3.5)
	_at_fit = is_equal_approx(zoom, fit)
	offset = screen_p - before * zoom
	_apply_view()


func focus_on(ids: Array, min_zoom: float = 0.0) -> void:
	## Cinema camera: frame these territories if we are zoomed in.
	if ids.is_empty() or art == null or zoom <= fit * 1.05:
		return
	var c := Vector2.ZERO
	for id in ids:
		c += art.anchors.get(id, Vector2.ZERO)
	c /= float(ids.size())
	var target_zoom := maxf(zoom, min_zoom)
	var target_off: Vector2 = size * 0.5 - c * target_zoom
	var tw := create_tween()
	tw.tween_method(func(t: float):
		offset = offset.lerp(target_off, t)
		_apply_view(), 0.0, 1.0, 0.35)


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if art == null:
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _panning:
			offset += event.relative
			_at_fit = false
			_apply_view()
			return
		if _pressing and _press_id == "" and event.position.distance_to(_press_pos) > 6:
			_panning = true
			return
		if _pressing and _press_id != "" and event.position.distance_to(_press_pos) > 12:
			drag_from = _press_id
		var id: String = art.territory_at(screen_to_map(event.position))
		if id != hovered:
			hovered = id
			territory_hovered.emit(id)
			refresh()
		if drag_from != "":
			overlay.queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(mb.position, 1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(mb.position, 1.0 / 1.12)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_pressing = false
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_pos = mb.position
				_press_id = art.territory_at(screen_to_map(mb.position))
				drag_from = ""
			else:
				var was_pan := _panning
				_pressing = false
				_panning = false
				if was_pan:
					return
				var id: String = art.territory_at(screen_to_map(mb.position))
				if drag_from != "":
					var from := drag_from
					drag_from = ""
					overlay.queue_redraw()
					if id != "" and id != from and interactive:
						drag_order.emit(from, id)
					return
				if not interactive:
					return
				for h in _label_hits:
					if mb.position.distance_to(h["pos"]) < 16.0:
						arrow_clicked.emit(str(h["from"]), str(h["to"]))
						return
				if id == "":
					empty_clicked.emit()
				else:
					territory_clicked.emit(id, MOUSE_BUTTON_LEFT)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and interactive:
			var id2: String = art.territory_at(screen_to_map(mb.position))
			if id2 != "":
				territory_clicked.emit(id2, MOUSE_BUTTON_RIGHT)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		offset -= event.delta * 12.0
		_at_fit = false
		_apply_view()


func _process(delta: float) -> void:
	_time += delta
	var live := false
	var i := fx.size() - 1
	while i >= 0:
		fx[i]["t"] = float(fx[i]["t"]) + delta
		if float(fx[i]["t"]) >= float(fx[i]["dur"]):
			fx.remove_at(i)
		i -= 1
	for k in shake.keys():
		shake[k] = float(shake[k]) - delta
		if float(shake[k]) <= 0.0:
			shake.erase(k)
	if not fx.is_empty() or not shake.is_empty() or not battle.is_empty() or drag_from != "":
		live = true
	## the ships ride the swell
	if art != null and not art.ornaments.is_empty() and Engine.get_frames_drawn() % 2 == 0:
		live = true
	if _mat != null:
		_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_time * 6.0))
	if live:
		overlay.queue_redraw()


func float_text(id: String, text: String, color: Color, dur: float = 1.6, size_px: int = 26) -> void:
	if art == null:
		return
	fx.append({"map": art.anchors.get(id, Vector2.ZERO), "text": text, "color": color, "t": 0.0, "dur": dur, "size": size_px})


func pulse_token(id: String, seconds: float = 0.8) -> void:
	shake[id] = seconds


# ------------------------------------------------------------------ drawing

func token_radius() -> float:
	return clampf(_token_base * sqrt(zoom / maxf(fit, 0.01)), 15.0, 34.0)


func _draw_overlay() -> void:
	if art == null or world == null:
		return
	var ci := overlay
	_label_hits.clear()
	_draw_ornaments(ci)
	_draw_lanes(ci)
	if show_region_labels:
		_draw_region_labels(ci)
	if plain:
		return
	for g in ghosts:
		_draw_arrow(ci, str(g["from"]), str(g["to"]), int(g.get("strength", 1)), str(g.get("owner", "")), str(g.get("surgeTo", "")), "attack", 0.22, false)
	for o in orders:
		_draw_arrow(ci, str(o["from"]), str(o["to"]), int(o.get("strength", 1)), str(o.get("owner", "")), str(o.get("surge", "")), str(o.get("kind", "attack")), float(o.get("alpha", 1.0)), true)
	if drag_from != "":
		var a: Vector2 = anchor(drag_from)
		ci.draw_line(a, _mouse, Color(1, 0.9, 0.6, 0.85), 5.0, true)
		ci.draw_circle(_mouse, 7.0, Color(1, 0.9, 0.6, 0.85))
	var ids: Array = art.order.duplicate()
	ids.sort_custom(func(x, y): return art.anchors[x].y < art.anchors[y].y)
	for id in ids:
		_draw_token(ci, str(id))
	for f in fx:
		var t: float = float(f["t"]) / float(f["dur"])
		var p: Vector2 = map_to_screen(f["map"]) + Vector2(0, -34 - 46 * t)
		var col: Color = f["color"]
		col.a = 1.0 - t * t
		var font := Style.font("display")
		var sz: int = int(f["size"])
		var w: float = font.get_string_size(str(f["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		ci.draw_string_outline(font, p - Vector2(w * 0.5, 0), str(f["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 6, Color(0, 0, 0, col.a * 0.85))
		ci.draw_string(font, p - Vector2(w * 0.5, 0), str(f["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw_ornaments(ci: CanvasItem) -> void:
	## compass rose, title plate and ships of the line, painted on the sea
	var k: float = zoom
	for o in art.ornaments:
		var p: Vector2 = map_to_screen(o["pos"])
		var r: float = float(o["r"]) * k
		match str(o["kind"]):
			"rose":
				var t: Texture2D = Style.tex("res://assets/art/chart_rose.png")
				if t != null:
					ci.draw_texture_rect(t, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, 0.78))
			"ship":
				var t2: Texture2D = Style.tex("res://assets/art/chart_ship.png")
				if t2 != null:
					var sz := Vector2(r * 2.0, r * 2.0 * t2.get_height() / maxf(1.0, t2.get_width()))
					var bob: float = sin(_time * 1.1 + o["pos"].x * 0.01) * 0.035
					ci.draw_set_transform(p, bob, Vector2(-1 if bool(o.get("flip", false)) else 1, 1))
					ci.draw_texture_rect(t2, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, 0.9))
					ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"cartouche":
				var t3: Texture2D = Style.tex("res://assets/art/chart_cartouche.png")
				if t3 != null:
					var cw: float = r * 2.1
					var ch: float = cw * t3.get_height() / maxf(1.0, t3.get_width())
					ci.draw_texture_rect(t3, Rect2(p - Vector2(cw, ch) * 0.5, Vector2(cw, ch)), false, Color(1, 1, 1, 0.92))
					var f := Style.font("display")
					var title: String = map.display_name.to_upper() if map != null else ""
					var fs: int = int(clampf(cw * 0.075, 10.0, 40.0))
					var tw: float = f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					if tw > cw * 0.62:
						fs = int(fs * cw * 0.62 / tw)
						tw = f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					ci.draw_string(f, p + Vector2(-tw * 0.5, fs * 0.25), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.35, 0.12, 0.08, 0.95))


func _draw_region_labels(ci: CanvasItem) -> void:
	if _region_font == null:
		_region_font = FontVariation.new()
		_region_font.base_font = Style.font("display")
		_region_font.spacing_glyph = 5
	var k: float = zoom / maxf(fit, 0.01)
	var sz: int = int(clampf(30.0 * sqrt(k) * (art.size.x / 2400.0 + 0.3), 20.0, 52.0))
	for r in art.regions.keys():
		if not map.region_bonus.has(r):
			continue
		var p: Vector2 = map_to_screen(art.regions[r])
		var name: String = str(map.region_names.get(r, r)).to_upper()
		var bonus := "+%d" % int(map.region_bonus[r])
		var w: float = _region_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		## a painted-map watermark: large, spaced, faint; tokens read on top of it
		var col: Color = region_color(r).lightened(0.6)
		col.a = 0.55
		var at := p + Vector2(-w * 0.5, 0)
		ci.draw_string_outline(_region_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0.05, 0.03, 0.02, 0.35))
		ci.draw_string(_region_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		var bf := Style.font("display")
		var bs: int = int(sz * 0.8)
		var bw: float = bf.get_string_size(bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
		var bp := p + Vector2(-bw * 0.5, bs + 4)
		ci.draw_string_outline(bf, bp, bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, 5, Color(0.05, 0.03, 0.02, 0.4))
		ci.draw_string(bf, bp, bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, Color(1.0, 0.85, 0.45, 0.7))


func _draw_lanes(ci: CanvasItem) -> void:
	for l in art.lanes:
		var a: Vector2 = map_to_screen(l["pa"])
		var b: Vector2 = map_to_screen(l["pb"])
		var d: Vector2 = b - a
		var n := int(d.length() / 9.0)
		if n < 2:
			ci.draw_line(a, b, Color(0.95, 0.88, 0.7, 0.8), 3.0, true)
			continue
		for i in range(0, n, 2):
			ci.draw_line(a + d * (float(i) / n), a + d * (float(i + 1) / n), Color(0.95, 0.88, 0.7, 0.75), 3.0, true)
		ci.draw_circle(a, 3.5, Color(0.95, 0.88, 0.7, 0.8))
		ci.draw_circle(b, 3.5, Color(0.95, 0.88, 0.7, 0.8))


func _curve(a: Vector2, b: Vector2, bend: float) -> PackedVector2Array:
	var mid: Vector2 = (a + b) * 0.5
	var perp: Vector2 = (b - a).orthogonal().normalized()
	var ctrl: Vector2 = mid + perp * (b - a).length() * bend
	var pts := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts


func _draw_arrow(ci: CanvasItem, from_id: String, to_id: String, strength: int, owner: String, surge: String, kind: String, alpha: float, labeled: bool) -> void:
	if not art.anchors.has(from_id) or not art.anchors.has(to_id):
		return
	var r := token_radius()
	var a: Vector2 = anchor(from_id)
	var b: Vector2 = anchor(to_id)
	var dir: Vector2 = (b - a).normalized()
	a += dir * (r + 2)
	b -= dir * (r + 8)
	## Opposite arrows bend to opposite sides so a border clash reads as two arrows.
	var bend := 0.14 if from_id < to_id else -0.14
	if kind == "move":
		bend *= 0.5
	var pts := _curve(a, b, bend)
	var col: Color = Style.seat_color(owner)
	col = col.lightened(0.15)
	col.a = alpha
	var w: float = clampf(4.0 + sqrt(float(strength)) * 1.6, 4.0, 13.0)
	var dark := Color(0.05, 0.04, 0.03, alpha * 0.9)
	if kind == "move":
		for i in range(0, pts.size() - 1, 2):
			ci.draw_line(pts[i], pts[i + 1], dark, w + 3.0, true)
			ci.draw_line(pts[i], pts[i + 1], col, w, true)
	else:
		ci.draw_polyline(pts, dark, w + 4.0, true)
		ci.draw_polyline(pts, col, w, true)
	var tip: Vector2 = pts[pts.size() - 1]
	var back: Vector2 = (tip - pts[pts.size() - 3]).normalized()
	var side: Vector2 = back.orthogonal()
	var head := PackedVector2Array([tip + back * (w + 8), tip + side * (w + 6), tip - side * (w + 6)])
	ci.draw_colored_polygon(head, dark)
	var inner := PackedVector2Array([tip + back * (w + 4), tip + side * (w + 2.5), tip - side * (w + 2.5)])
	ci.draw_colored_polygon(inner, col)
	if surge != "" and art.anchors.has(surge):
		var c: Vector2 = anchor(surge)
		var sp := _curve(anchor(to_id) + (c - anchor(to_id)).normalized() * (r + 4), c - (c - anchor(to_id)).normalized() * (r + 8), bend)
		for i in range(0, sp.size() - 1, 2):
			ci.draw_line(sp[i], sp[i + 1], dark, 6.0, true)
			ci.draw_line(sp[i], sp[i + 1], col, 3.5, true)
		var st: Vector2 = sp[sp.size() - 1]
		var sb: Vector2 = (st - sp[sp.size() - 3]).normalized()
		var ss: Vector2 = sb.orthogonal()
		ci.draw_colored_polygon(PackedVector2Array([st + sb * 9, st + ss * 7, st - ss * 7]), col)
	if labeled:
		var m: Vector2 = pts[11]
		_label_hits.append({"pos": m, "from": from_id, "to": to_id})
		var txt := str(strength)
		var f := Style.font("bold")
		var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var rad: float = maxf(12.0, tw * 0.5 + 7.0)
		ci.draw_circle(m, rad + 2.0, dark)
		ci.draw_circle(m, rad, Color(0.96, 0.92, 0.82, alpha))
		ci.draw_string(f, m + Vector2(-tw * 0.5, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.1, 0.08, 0.06, alpha))


func _draw_token(ci: CanvasItem, id: String) -> void:
	var ts: Types.TerritoryState = world.get_territory(id)
	if ts == null:
		return
	var p: Vector2 = anchor(id)
	var r := token_radius()
	if shake.has(id):
		r *= 1.0 + 0.18 * sin(float(shake[id]) * 18.0)
	var owner: String = ts.owner
	var f := Style.font("bold")
	## name plate under the token
	var name: String = map.get_territory(id).display_name
	var ns := 15 if zoom < fit * 1.4 else 17
	var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
	var np: Vector2 = p + Vector2(-nw * 0.5, r + ns + 1)
	ci.draw_string_outline(f, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, 5, Color(0.05, 0.04, 0.03, 0.85))
	ci.draw_string(f, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, Style.CREAM if id != selected else Style.GOLD)
	if owner == Types.UNOCCUPIED:
		ci.draw_arc(p, r * 0.8, 0, TAU, 28, Color(0.95, 0.9, 0.78, 0.55), 2.0, true)
		ci.draw_string(f, p + Vector2(-6, 7), "–", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.9, 0.78, 0.7))
		return
	var col: Color = Style.seat_color(owner)
	var shape: String = Style.seat_shape(owner)
	ci.draw_circle(p + Vector2(2, 3), r + 1, Color(0, 0, 0, 0.35))
	var edge := Color(0.96, 0.9, 0.76) if id != selected else Color(1.0, 0.85, 0.35)
	Style.draw_shape(ci, shape, p, r + 2.5, Color(0.08, 0.06, 0.05), Color(0.08, 0.06, 0.05), 1.0)
	Style.draw_shape(ci, shape, p, r, col.darkened(0.08), edge, 2.0 if id != selected else 3.5)
	## lacquer sheen: a soft highlight up and to the left, a shade below
	Style.draw_shape(ci, shape, p + Vector2(0, r * 0.12), r * 0.78, Color(0, 0, 0, 0.12), Color(0, 0, 0, 0), 0.0)
	ci.draw_circle(p + Vector2(-r * 0.3, -r * 0.34), r * 0.42, Color(1, 1, 1, 0.13))
	var n: int = ts.armies + ts.garrison
	var txt := str(n)
	var fs := 22 if n < 100 else 18
	var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string_outline(f, p + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.05, 0.03, 0.02, 0.9))
	ci.draw_string(f, p + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.98, 0.92))
	## dug-in garrison: a small shield badge top-left
	if ts.garrison > 0:
		var gp: Vector2 = p + Vector2(-r * 0.95, -r * 0.8)
		Style.draw_shape(ci, "shield", gp, 9.0, Color(0.2, 0.17, 0.12), Color(0.9, 0.78, 0.5), 1.5)
		var gt := str(ts.garrison)
		var gw: float = f.get_string_size(gt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		ci.draw_string(f, gp + Vector2(-gw * 0.5, 5), gt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.92, 0.7))
	## queued reinforcements: gold "+n" top-right
	var q: int = int(placements.get(id, 0))
	if q > 0:
		var qp: Vector2 = p + Vector2(r * 0.95, -r * 0.8)
		var qt := "+%d" % q
		var qw: float = f.get_string_size(qt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ci.draw_rect(Rect2(qp - Vector2(qw * 0.5 + 5, 11), Vector2(qw + 10, 20)), Color(0.12, 0.09, 0.03, 0.95))
		ci.draw_rect(Rect2(qp - Vector2(qw * 0.5 + 5, 11), Vector2(qw + 10, 20)), Style.GOLD, false, 1.5)
		ci.draw_string(f, qp + Vector2(-qw * 0.5, 5), qt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Style.GOLD)
	## enemy ceiling: the most this hex could hold after their hidden reinforcement
	if show_ceiling and owner != viewer and owner != Types.UNOCCUPIED:
		var ceiling: int = n + (Income.cap_of(world, map, id) * ceiling_mult if owner != "neutral" else 0)
		if ceiling > n:
			var cp: Vector2 = p + Vector2(r * 0.95, -r * 0.8)
			var ct := "≤%d" % ceiling
			var cw: float = f.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			ci.draw_rect(Rect2(cp - Vector2(cw * 0.5 + 4, 10), Vector2(cw + 8, 18)), Color(0.06, 0.05, 0.05, 0.85))
			ci.draw_string(f, cp + Vector2(-cw * 0.5, 4), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.75, 0.65))
