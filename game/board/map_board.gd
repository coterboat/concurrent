## The campaign map. Status board first: counts readable from the couch,
## vacated origins look vacated, arrows say who is going where.
## Emits clicks and drags; the game screen decides what they mean.
extends Control

const Types := preload("res://engine/types.gd")
const Income := preload("res://engine/income.gd")
const MapLib := preload("res://engine/map.gd")
const Style := preload("res://game/core/style.gd")
const MapArt := preload("res://game/board/map_art.gd")
const LastRound := preload("res://game/core/last_round.gd")
const BoardFacts := preload("res://game/core/board_facts.gd")

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
var clash: Array = [] ## [land a, land b]: a border clash being fought on the line between them
var orders: Array = [] ## [{from, to, strength, owner, surge, kind: "attack"|"move", born?}]
var flow := false ## columns on the move: marching chevrons run along the live arrows (the battle report)
var ghosts: Array = [] ## last round's packets (v1.13: each with its fate, LastRound.ghosts)
var threats := {} ## v1.13: the viewer's lands -> BoardFacts.threats (planning only): what could land on them
var hinges := {} ## v1.13: the viewer's lands -> the lands they hold the road home for (supply maps)
var placements := {} ## id -> queued reinforcements (viewer)
var bonus := {} ## id -> free soldiers from the cards being turned in (v1.6), drawn as a gold star
var bonus_seen := {} ## v1.9: id -> when its star first showed; the star pops in, then fades after BONUS_SHOW
const BONUS_SHOW := 4.5
var capital_override := {} ## v1.8: pid -> the capital a commander is choosing (drawn before it is sealed)
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
var _late: Array = [] ## v1.13: marks drawn over the tokens (fates, region pips), queued while the arrows draw
var drawn_ceilings: Array = [] ## v1.13.2: the enemy lands wearing their ≤N this frame (the probe reads it)
var drawn_fates: Array = [] ## v1.13.2: [fate, where] for each fate mark this frame (the probe reads it)
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


func swoop_to(ids: Array, zmult: float, dur: float) -> Tween:
	## the cinema camera: ease in on a battle (centre and zoom), for the fights that matter
	var c := Vector2.ZERO
	var n := 0
	for id in ids:
		if art.anchors.has(id):
			c += art.anchors[id]
			n += 1
	if n == 0:
		return null
	c /= float(n)
	var z0: float = zoom
	var o0: Vector2 = offset
	var z1: float = clampf(fit * zmult, fit, fit * 3.5)
	var mid := Vector2(size.x * 0.5, pad_top + (size.y - pad_top - pad_bottom) * 0.5)
	var o1: Vector2 = mid - c * z1
	_at_fit = false
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var e: float = ease(t, -2.2)
		zoom = lerpf(z0, z1, e)
		offset = o0.lerp(o1, e)
		_apply_view(), 0.0, 1.0, dur)
	return tw


func swoop_back(dur: float) -> Tween:
	var z0: float = zoom
	var o0: Vector2 = offset
	var avail2 := Vector2(size.x, size.y - pad_top - pad_bottom)
	var o1 := Vector2((size.x - art.size.x * fit) * 0.5, pad_top + (avail2.y - art.size.y * fit) * 0.5)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var e: float = ease(t, -2.2)
		zoom = lerpf(z0, fit, e)
		offset = o0.lerp(o1, e)
		_apply_view(), 0.0, 1.0, dur)
	tw.tween_callback(func():
		_at_fit = true
		_on_resized())
	return tw


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
	var fi := fires.size() - 1
	while fi >= 0:
		fires[fi]["t"] = float(fires[fi]["t"]) + delta
		if float(fires[fi]["t"]) >= float(fires[fi]["dur"]):
			fires.remove_at(fi)
		else:
			live = true
		fi -= 1
	for k in bonus_seen.keys():
		if not bonus.has(k):
			bonus_seen.erase(k) ## the set was taken back: it shows afresh if it comes again
		elif _time - float(bonus_seen[k]) < BONUS_SHOW + 0.1:
			live = true
	if not fx.is_empty() or not shake.is_empty() or not battle.is_empty() or not clash.is_empty() or drag_from != "" or flow:
		live = true
	## the ships ride the swell
	if art != null and not art.ornaments.is_empty() and Engine.get_frames_drawn() % 2 == 0:
		live = true
	if _mat != null:
		_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_time * 6.0))
		if _day != _day_to:
			_day = _day.lerp(_day_to, clampf(delta * 0.6, 0.0, 1.0))
			if absf(_day.r - _day_to.r) + absf(_day.g - _day_to.g) + absf(_day.b - _day_to.b) < 0.002:
				_day = _day_to
			_mat.set_shader_parameter("daylight", Vector3(_day.r, _day.g, _day.b))
	if not smoke.is_empty():
		live = true
	if live:
		overlay.queue_redraw()


func now() -> float:
	return _time


func float_text(id: String, text: String, color: Color, dur: float = 1.6, size_px: int = 26) -> void:
	if art == null:
		return
	fx.append({"map": art.anchors.get(id, Vector2.ZERO), "text": text, "color": color, "t": 0.0, "dur": dur, "size": size_px})


## v1.12: the war's day (morning to a red dusk) and smoke over the lands fought over last round
var _day := Color(1, 1, 1)
var _day_to := Color(1, 1, 1)
var smoke := {} ## territory id -> when it began smouldering


func set_daylight(c: Color, instant: bool = false) -> void:
	_day_to = c
	if instant:
		_day = c
		if _mat != null:
			_mat.set_shader_parameter("daylight", Vector3(c.r, c.g, c.b))


func smolder(ids: Array) -> void:
	smoke = {}
	for id in ids:
		smoke[str(id)] = _time - randf() * 3.0 ## not all in step


func _draw_smoke(ci: CanvasItem) -> void:
	if smoke.is_empty() or art == null:
		return
	var r: float = token_radius()
	for id in smoke.keys():
		if not art.anchors.has(id) or dimmed.has(id):
			continue
		var base: Vector2 = map_to_screen(art.anchors[id]) + Vector2(r * 0.95, -r * 0.55)
		var age: float = _time - float(smoke[id])
		var fade: float = clampf(age / 1.5, 0.0, 1.0)
		for i in 8:
			var ph: float = fmod(age * 0.14 + float(i) / 8.0, 1.0)
			var at: Vector2 = base + Vector2(sin(ph * 3.0 + float(i)) * r * 0.3 + ph * r * 1.1, -ph * r * 3.4)
			var rad: float = r * (0.3 + 0.62 * ph)
			var a: float = 0.5 * sin(ph * PI) * fade
			ci.draw_circle(at, rad, Color(0.14, 0.12, 0.11, a), true, -1.0, true)
			ci.draw_circle(at + Vector2(-rad * 0.22, -rad * 0.22), rad * 0.62, Color(0.5, 0.47, 0.44, a * 0.6), true, -1.0, true)
		## the embers at its foot
		var glow: float = (0.55 + 0.25 * sin(age * 5.0 + float(id.hash() % 7))) * fade
		ci.draw_circle(base + Vector2(0, r * 0.15), r * 0.2, Color(1.0, 0.45, 0.12, 0.5 * glow), true, -1.0, true)


var fires: Array = [] ## v1.9: a fallen capital burns: {map, t, dur}
var _fire_sheet := {}


func fire_at(id: String, seconds: float = 5.0) -> void:
	## the city burns behind its token for a few seconds (assets/fx/capital_fire, a loop)
	if art == null or not art.anchors.has(id):
		return
	fires.append({"map": art.anchors[id], "t": 0.0, "dur": seconds})


func _fire_frame() -> Dictionary:
	if _fire_sheet.is_empty():
		var t: Texture2D = Style.tex("res://assets/fx/capital_fire.webp")
		if t == null or not FileAccess.file_exists("res://assets/fx/capital_fire.json"):
			return {}
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/capital_fire.json"))
		if typeof(m) != TYPE_DICTIONARY:
			return {}
		_fire_sheet = {"tex": t, "cols": int(m["cols"]), "frames": int(m["frames"]), "fw": float(m["fw"]), "fh": float(m["fh"]),
			"ax": float(m.get("ax", 0.5)), "ay": float(m.get("ay", 0.7)), "fps": float(m.get("fps", 12.0)), "order": m.get("order", [])}
	return _fire_sheet


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
	_late.clear()
	drawn_ceilings.clear()
	drawn_fates.clear()
	_draw_ornaments(ci)
	_draw_lanes(ci)
	if show_region_labels:
		_draw_region_labels(ci)
	if plain:
		return
	_surges_drawn = {}
	for g in ghosts:
		_draw_ghost(ci, g)
	_surges_drawn = {}
	for o in orders:
		var grow: float = clampf((_time - float(o["born"])) / 0.55, 0.0, 1.0) if o.has("born") else 1.0
		_draw_arrow(ci, str(o["from"]), str(o["to"]), int(o.get("strength", 1)), str(o.get("owner", "")), str(o.get("surge", "")), str(o.get("kind", "attack")), float(o.get("alpha", 1.0)), true, grow, int(o.get("surge_n", 0)))
	if drag_from != "":
		var a: Vector2 = anchor(drag_from)
		ci.draw_line(a, _mouse, Color(1, 0.9, 0.6, 0.85), 5.0, true)
		ci.draw_circle(_mouse, 7.0, Color(1, 0.9, 0.6, 0.85))
	_draw_battle_marks(ci)
	_draw_smoke(ci)
	## v1.9: fallen capitals burn behind their tokens
	var fs: Dictionary = _fire_frame() if not fires.is_empty() else {}
	for fr in fires:
		if fs.is_empty():
			break
		var ft: float = float(fr["t"])
		var o: Array = fs["order"]
		var n: int = o.size() if not o.is_empty() else int(fs["frames"])
		var k: int = posmod(int(ft * float(fs["fps"])), n)
		var idx: int = int(o[k]) if not o.is_empty() else k
		var cols: int = int(fs["cols"])
		var src := Rect2((idx % cols) * float(fs["fw"]), (idx / cols) * float(fs["fh"]), float(fs["fw"]), float(fs["fh"]))
		var al: float = clampf(ft / 0.3, 0.0, 1.0) * clampf((float(fr["dur"]) - ft) / 0.8, 0.0, 1.0)
		var h: float = token_radius() * 5.2
		var w: float = h * float(fs["fw"]) / float(fs["fh"])
		var at: Vector2 = map_to_screen(fr["map"])
		ci.draw_texture_rect_region(fs["tex"], Rect2(at - Vector2(w * float(fs["ax"]), h * float(fs["ay"])), Vector2(w, h)), src, Color(1, 1, 1, al))
	var ids: Array = art.order.duplicate()
	ids.sort_custom(func(x, y): return art.anchors[x].y < art.anchors[y].y)
	for id in ids:
		_draw_token(ci, str(id))
	for m in _late:
		(m as Callable).call(ci)
	_draw_clash(ci)
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


func _draw_battle_marks(ci: CanvasItem) -> void:
	## the lands fighting right now: a pulsing ring of fire under their tokens
	if battle.is_empty():
		return
	var r := token_radius()
	var k: float = 0.5 + 0.5 * sin(_time * 7.0)
	for id in battle.keys():
		if not art.anchors.has(id):
			continue
		var p: Vector2 = anchor(str(id))
		ci.draw_circle(p, r * (1.9 + 0.25 * k), Color(1.0, 0.35, 0.15, 0.10 + 0.08 * k))
		ci.draw_arc(p, r * (1.55 + 0.2 * k), 0, TAU, 40, Color(1.0, 0.78, 0.35, 0.55 + 0.35 * k), 3.0, true)
		ci.draw_arc(p, r * (1.3 + 0.1 * k), 0, TAU, 40, Color(0.9, 0.2, 0.1, 0.5), 2.0, true)


func _draw_clash(ci: CanvasItem) -> void:
	## two columns meeting on the border: a starburst and crossed swords where they collide
	if clash.size() < 2 or not art.anchors.has(clash[0]) or not art.anchors.has(clash[1]):
		return
	var a: Vector2 = anchor(str(clash[0]))
	var b: Vector2 = anchor(str(clash[1]))
	var m: Vector2 = (a + b) * 0.5
	var k: float = 0.5 + 0.5 * sin(_time * 9.0)
	var R: float = token_radius() * (1.5 + 0.2 * k)
	var star := PackedVector2Array()
	for i in 24:
		var ang: float = TAU * i / 24.0 + _time * 0.6
		star.append(m + Vector2.from_angle(ang) * (R if i % 2 == 0 else R * 0.55))
	ci.draw_colored_polygon(star, Color(1.0, 0.55, 0.15, 0.85))
	var star2 := PackedVector2Array()
	for i in 24:
		var ang2: float = TAU * i / 24.0 - _time * 0.4
		star2.append(m + Vector2.from_angle(ang2) * (R * 0.8 if i % 2 == 0 else R * 0.45))
	ci.draw_colored_polygon(star2, Color(1.0, 0.9, 0.5, 0.95))
	var sw: Texture2D = Style.icon("attack")
	if sw != null:
		var sz: float = R * 1.1
		ci.draw_texture_rect(sw, Rect2(m - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)


func _draw_region_labels(ci: CanvasItem) -> void:
	if _region_font == null:
		_region_font = FontVariation.new()
		_region_font.base_font = Style.font("display")
		_region_font.spacing_glyph = 5
	var k: float = zoom / maxf(fit, 0.01)
	var sz: int = int(clampf(30.0 * sqrt(k) * (art.size.x / 2400.0 + 0.3), 20.0, 52.0))
	var shares: Dictionary = BoardFacts.shares(world, map) if world != null and not plain else {}
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
		if shares.has(r):
			## beside the bonus, over the tokens (a pip hidden under a crown would miscount)
			_late.append(_draw_region_pips.bind(shares[r], bp + Vector2(bw + 10.0, -bs * 0.34), sz))


func _draw_region_pips(ci: CanvasItem, sh: Dictionary, at: Vector2, sz: int) -> void:
	## v1.13: who holds the region, a pip a land in its holder's colour, the biggest holder first,
	## on a dark pill that starts at `at`. A commander one land short of it: the missing pip rings
	## in their colour, pulsing.
	var by: Dictionary = sh["by"]
	var owners: Array = by.keys()
	owners.sort_custom(func(a, b): return int(by[a]) > int(by[b]) or (int(by[a]) == int(by[b]) and str(a) < str(b)))
	var cols: Array = []
	for o in owners:
		for i in int(by[o]):
			cols.append(Style.seat_color(str(o)))
	var n: int = (sh["members"] as PackedStringArray).size()
	var pr: float = clampf(float(sz) * 0.13, 3.5, 6.5)
	var gap: float = pr * 2.0 + 3.0
	var x0: float = at.x + pr + 4.0
	var pill := Rect2(Vector2(at.x, at.y - pr - 3.0), Vector2(gap * float(n - 1) + pr * 2.0 + 8.0, pr * 2.0 + 6.0))
	ci.draw_rect(pill, Color(0.05, 0.035, 0.02, 0.55))
	var one_short: bool = int(sh["to_go"]) == 1 and str(sh["leader"]) != "" and n > 1
	for i in n:
		var c: Vector2 = Vector2(x0 + gap * i, at.y)
		ci.draw_circle(c, pr + 1.5, Color(0.05, 0.03, 0.02, 0.55))
		if i < cols.size():
			ci.draw_circle(c, pr, cols[i])
		else:
			ci.draw_arc(c, pr - 0.5, 0, TAU, 14, Color(0.95, 0.9, 0.78, 0.5), 1.5, true)
			if one_short and i == cols.size():
				var lc: Color = Style.seat_color(str(sh["leader"]))
				ci.draw_arc(c, pr + 3.5, 0, TAU, 18, Color(lc, 0.55 + 0.4 * sin(_time * 4.0)), 2.5, true)


func _draw_lanes(ci: CanvasItem) -> void:
	for l in art.lanes:
		if map != null and not map.lane_live(str(l["a"]), str(l["b"])):
			continue ## v1.12: a lane a map amendment added shows only under the rules that added it
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


func _draw_threat(ci: CanvasItem, id: String, p: Vector2, r: float, f: Font) -> void:
	## v1.13: your land could be outnumbered next round: a crimson plate at its lower right with a
	## sword and the most that could land on it. A capital that could be outnumbered at all also
	## wears a slow crimson ring.
	if not threats.has(id) or not bool(threats[id].get("danger", false)):
		return
	var th: Dictionary = threats[id]
	if bool(th.get("capital", false)):
		var pulse: float = 0.55 + 0.35 * sin(_time * 3.0)
		ci.draw_arc(p, r + 7.0, 0, TAU, 40, Color(0.92, 0.25, 0.2, pulse), 3.0, true)
	var txt := str(int(th["max"]))
	var fs := 14
	var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ic: float = 14.0
	var box := Rect2(p + Vector2(r * 0.55, r * 0.45), Vector2(ic + tw + 12.0, 20.0))
	ci.draw_rect(Rect2(box.position + Vector2(1.5, 2.0), box.size), Color(0, 0, 0, 0.4))
	ci.draw_rect(box, Color(0.38, 0.06, 0.05, 0.95))
	ci.draw_rect(box, Color(0.98, 0.55, 0.45, 0.9), false, 1.5)
	var sw: Texture2D = Style.icon("attack")
	if sw != null:
		ci.draw_texture_rect(sw, Rect2(box.position + Vector2(4, 3), Vector2(ic, ic)), false, Color(1, 0.9, 0.85))
	ci.draw_string(f, box.position + Vector2(ic + 7.0, 15.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.93, 0.88))


func _borders(id: String, pid: String) -> bool:
	## does this land touch one of pid's (by land or lane)?
	if pid == "":
		return false
	for nb in MapLib.neighbors(map, id):
		if world.get_territory(nb).owner == pid:
			return true
	return false


func _is_capital(id: String, owner: String) -> bool:
	if map == null or not map.capitals or world == null or not world.players.has(owner):
		return false
	if capital_override.has(owner):
		return str(capital_override[owner]) == id
	return (world.players[owner] as Types.PlayerState).capital == id


func _sea_bend(a: Vector2, b: Vector2, from_id: String, to_id: String) -> float:
	## the arc, of a few, that keeps farthest from every other land's token
	var best := 0.3
	var best_gap := -1.0
	for bend in [0.3, -0.3, 0.55, -0.55, 0.12, -0.12]:
		var gap := 1.0e9
		for pt in _curve(a, b, bend):
			for id in art.anchors.keys():
				if str(id) == from_id or str(id) == to_id:
					continue
				gap = minf(gap, pt.distance_to(anchor(str(id))))
		if gap > best_gap + 4.0:
			best_gap = gap
			best = bend
	return best


var _surges_drawn := {}


func _draw_ghost(ci: CanvasItem, g: Dictionary) -> void:
	## v1.13: last round's column, faint, with its fate: a column that failed ends in a cross at
	## the walls it was thrown back from; one beaten in a border clash stops halfway, where the two
	## columns met. One that took its land needs no mark: the land's colour says it.
	var res: String = str(g.get("result", ""))
	var failed: bool = LastRound.FAILED.has(res)
	var surge_died: bool = str(g.get("surgeFate", "")) == LastRound.CLASH
	var kind: String = str(g.get("kind", "attack"))
	var end: Vector2 = _draw_arrow(ci, str(g["from"]), str(g["to"]), int(g.get("strength", 1)), str(g.get("owner", "")), "" if surge_died else str(g.get("surgeTo", "")),
		kind, 0.42 if failed else 0.22, false, 1.0, 0, 0.5 if res == LastRound.CLASH else 1.0)
	## the marks go over the tokens: at a land's edge its garrison shield would hide them
	if failed and end != Vector2.INF:
		var back: String = str(g.get("fellTo", "")) if str(g.get("fellTo", "")) != "" else str(g["from"])
		_late.append(_draw_fate_mark.bind(end, res, anchor(back) if art.anchors.has(back) else Vector2.INF))
	if surge_died:
		## the surge it sent on met another surge on the border and died there
		var se: Vector2 = _draw_arrow(ci, str(g["to"]), str(g["surgeTo"]), -1, str(g.get("owner", "")), "", kind, 0.42, false, 1.0, 0, 0.5)
		if se != Vector2.INF:
			_late.append(_draw_fate_mark.bind(se, LastRound.CLASH, Vector2.INF))


func _draw_fate_mark(ci: CanvasItem, at: Vector2, fate: String, toward: Vector2) -> void:
	## a column that failed, on a dark medal readable over any land or sea. v1.13.2: each fate its
	## own mark (the play critic: "you can tell it failed, but not how, without hovering"). Thrown
	## back or beaten on the border: a red cross. Fell back: a pale double chevron pointing the way
	## the survivors went. Beaten in a scramble (or the fight for the spoils): crossed swords.
	var s: float = clampf(token_radius() * 0.32, 6.0, 9.0)
	drawn_fates.append([fate, at])
	ci.draw_circle(at + Vector2(1.0, 1.5), s + 5.0, Color(0, 0, 0, 0.35))
	ci.draw_circle(at, s + 5.0, Color(0.10, 0.05, 0.04, 0.88))
	ci.draw_arc(at, s + 5.0, 0, TAU, 20, Color(0.95, 0.88, 0.72, 0.7), 1.5, true)
	var swords: Texture2D = Style.icon("attack") if fate == LastRound.OUTFOUGHT else null
	if fate == LastRound.FELL_BACK:
		var d: Vector2 = (toward - at).normalized() if toward != Vector2.INF and toward.distance_to(at) > 1.0 else Vector2.LEFT
		var n: Vector2 = d.orthogonal()
		var pale := Color(0.98, 0.84, 0.55)
		for k in 2:
			var c: Vector2 = at + d * (s * (0.45 - 0.8 * k))
			ci.draw_polyline(PackedVector2Array([c - d * s * 0.45 + n * s * 0.8, c + d * s * 0.45, c - d * s * 0.45 - n * s * 0.8]), pale, 3.0, true)
	elif swords != null:
		var q: float = s * 1.25
		ci.draw_texture_rect(swords, Rect2(at - Vector2(q, q), Vector2(q, q) * 2.0), false, Color(1.0, 0.72, 0.66))
	else:
		var red := Color(0.95, 0.33, 0.26)
		ci.draw_line(at + Vector2(-s, -s), at + Vector2(s, s), red, 3.5, true)
		ci.draw_line(at + Vector2(-s, s), at + Vector2(s, -s), red, 3.5, true)


func _draw_arrow(ci: CanvasItem, from_id: String, to_id: String, strength: int, owner: String, surge: String, kind: String, alpha: float, labeled: bool, grow: float = 1.0, surge_n: int = 0, cut: float = 1.0) -> Vector2:
	## strength < 0: a surge onward (everyone left after the capture, less the one who stays)
	## v1.13: cut < 1 draws only that part of the way, with no head (a column that never got
	## there); returns where the drawn arrow ends (Vector2.INF when it isn't drawn)
	if not art.anchors.has(from_id) or not art.anchors.has(to_id):
		return Vector2.INF
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
		if not map.is_adjacent(from_id, to_id):
			bend = _sea_bend(a, b, from_id, to_id) ## v1.7: a march by sea sails round the other lands
	var pts := _curve(a, b, bend)
	if cut < 1.0:
		pts = pts.slice(0, maxi(3, int(ceil(cut * float(pts.size() - 1))) + 1))
	if grow < 1.0:
		## a column setting out: the arrow draws itself from its origin
		var keep: int = maxi(3, int(ceil(grow * float(pts.size() - 1))) + 1)
		pts = pts.slice(0, keep)
	var col: Color = Style.seat_color(owner)
	col = col.lightened(0.15)
	col.a = alpha
	var w: float = clampf(4.0 + sqrt(float(strength if strength > 0 else 5)) * 1.6, 4.0, 13.0)
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
	if cut >= 1.0:
		var head := PackedVector2Array([tip + back * (w + 8), tip + side * (w + 6), tip - side * (w + 6)])
		ci.draw_colored_polygon(head, dark)
		var inner := PackedVector2Array([tip + back * (w + 4), tip + side * (w + 2.5), tip - side * (w + 2.5)])
		ci.draw_colored_polygon(inner, col)
	if flow and alpha >= 0.95 and grow >= 1.0:
		## marching chevrons: which way the column is going, at a glance
		for k in 3:
			var u: float = fposmod(_time * 0.7 + float(k) / 3.0, 1.0)
			var fi: float = u * float(pts.size() - 1)
			var i0: int = clampi(int(fi), 0, pts.size() - 2)
			var at: Vector2 = pts[i0].lerp(pts[i0 + 1], fi - float(i0))
			var fwd: Vector2 = (pts[i0 + 1] - pts[i0]).normalized()
			var sd: Vector2 = fwd.orthogonal()
			var cw: float = w * 0.55 + 2.0
			var chev := PackedVector2Array([at - fwd * cw + sd * cw, at, at - fwd * cw - sd * cw])
			var fade: float = sin(u * PI)
			ci.draw_polyline(chev, Color(0.05, 0.04, 0.03, alpha * 0.8 * fade), 4.5, true)
			ci.draw_polyline(chev, Color(1, 0.96, 0.85, alpha * fade), 2.2, true)
	if surge != "" and art.anchors.has(surge) and not _surges_drawn.has(owner + to_id + surge):
		## the surge is a march like any other, on from the land being taken
		_surges_drawn[owner + to_id + surge] = true
		_draw_arrow(ci, to_id, surge, -1 if surge_n <= 0 else -(surge_n + 1), owner, "", kind, alpha, labeled, grow)
	if labeled and grow >= 1.0:
		var m: Vector2 = pts[mini(11, pts.size() - 1)]
		_label_hits.append({"pos": m, "from": from_id, "to": to_id}) ## a surge's label opens its card too
		var txt := str(strength) if strength >= 0 else ("all" if strength == -1 else "≤%d" % (-strength - 1))
		var f := Style.font("bold")
		var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var rad: float = maxf(12.0, tw * 0.5 + 7.0)
		ci.draw_circle(m, rad + 2.0, dark)
		ci.draw_circle(m, rad, Color(0.96, 0.92, 0.82, alpha))
		ci.draw_string(f, m + Vector2(-tw * 0.5, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.1, 0.08, 0.06, alpha))
	return tip ## the head's base: at a land's edge, just outside its token


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
	var n: int = ts.armies + ts.garrison ## everyone who defends (the ceiling counts them all)
	## v1.3: the token's number is the army that can march; the dug-in defenders who never
	## march sit on their own shield. Two separate numbers, never one inside the other.
	## v1.5: the big number is exactly who can march; the shield, who stays home
	var split: Array = Income.home_split(ts)
	var marching: int = int(split[0])
	var home: int = int(split[1])
	var txt := str(marching)
	var fs := 22 if marching < 100 else 18
	var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var num_col := Color(1, 0.98, 0.92) if marching > 0 else Color(1, 0.98, 0.92, 0.5)
	ci.draw_string_outline(f, p + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.05, 0.03, 0.02, 0.9))
	ci.draw_string(f, p + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_col)
	## the garrison's shield, on the token's left shoulder
	var gp: Vector2 = p + Vector2(-r * 1.05, -r * 0.55)
	var gr: float = clampf(r * 0.52, 9.0, 14.0)
	if home > 0:
		ci.draw_circle(gp + Vector2(1.5, 2.5), gr, Color(0, 0, 0, 0.35))
		Style.draw_shape(ci, "shield", gp, gr, Color(0.36, 0.24, 0.08), Color(1.0, 0.84, 0.45), 2.0)
		var gt := str(home)
		var gs: int = int(gr * 1.15)
		var gw: float = f.get_string_size(gt, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
		ci.draw_string_outline(f, gp + Vector2(-gw * 0.5, gs * 0.36), gt, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, 3, Color(0.1, 0.06, 0.02, 0.9))
		ci.draw_string(f, gp + Vector2(-gw * 0.5, gs * 0.36), gt, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(1, 0.94, 0.72))
	elif owner != "neutral":
		## nobody dug in yet: a faint empty shield, so the absence reads too
		Style.draw_shape(ci, "shield", gp, gr * 0.8, Color(0, 0, 0, 0.0), Color(0.95, 0.9, 0.78, 0.28), 1.2)
	## queued reinforcements: gold "+n" top-right
	var q: int = int(placements.get(id, 0))
	if q > 0:
		var qp: Vector2 = p + Vector2(r * 0.95, -r * 0.8)
		var qt := "+%d" % q
		var qw: float = f.get_string_size(qt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ci.draw_rect(Rect2(qp - Vector2(qw * 0.5 + 5, 11), Vector2(qw + 10, 20)), Color(0.12, 0.09, 0.03, 0.95))
		ci.draw_rect(Rect2(qp - Vector2(qw * 0.5 + 5, 11), Vector2(qw + 10, 20)), Style.GOLD, false, 1.5)
		ci.draw_string(f, qp + Vector2(-qw * 0.5, 5), qt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Style.GOLD)
	_draw_threat(ci, id, p, r, f)
	## a free soldier from a card naming this land: a gold star under the token
	## v1.9: it only says where the troops came from, so it pops in and fades after a few seconds
	if bonus.has(id):
		if not bonus_seen.has(id):
			bonus_seen[id] = _time
		var age: float = _time - float(bonus_seen[id])
		if age < BONUS_SHOW:
			var al: float = 1.0 - smoothstep(BONUS_SHOW - 1.2, BONUS_SHOW, age)
			var pop: float = 1.0 + 0.6 * (1.0 - smoothstep(0.0, 0.35, age)) + 0.12 * sin(age * 7.0) * (1.0 - smoothstep(0.0, 2.0, age))
			var bp: Vector2 = p + Vector2(r * 0.95, r * 0.55)
			for k in 2:
				ci.draw_circle(bp, 11.0 * pop * (1.6 - 0.3 * k), Color(1.0, 0.8, 0.3, 0.12 * al))
			Style.draw_shape(ci, "star", bp, 11.0 * pop, Color(Style.GOLD, al), Color(0.25, 0.15, 0.02, al), 1.5)
			ci.draw_string_outline(f, bp + Vector2(10, 6), "+%d" % int(bonus[id]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0.05, 0.03, 0.02, 0.9 * al))
			ci.draw_string(f, bp + Vector2(10, 6), "+%d" % int(bonus[id]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Style.GOLD, al))
	## v1.8: a capital wears a crown on top of its token
	if _is_capital(id, owner):
		## the crown in its laurels, set on the token's brow with a warm glow behind it
		var cr: float = clampf(r * 0.85, 15.0, 24.0)
		var cp: Vector2 = p + Vector2(0, -r - cr * 0.25)
		for k in 3:
			ci.draw_circle(cp, cr * (0.95 - 0.18 * k), Color(1.0, 0.8, 0.35, 0.10 + 0.06 * k))
		var ctex: Texture2D = Style.tex("res://assets/icons/crown.png")
		if ctex != null:
			var asp: float = float(ctex.get_width()) / float(maxi(1, ctex.get_height()))
			var sz := Vector2(cr * 2.0 * asp, cr * 2.0) if asp < 1.0 else Vector2(cr * 2.0, cr * 2.0 / asp)
			ci.draw_texture_rect(ctex, Rect2(cp - sz * 0.5, sz), false)
		else:
			Style.draw_shape(ci, "star", cp, cr * 0.7, Style.GOLD, Color(0.25, 0.15, 0.02), 1.5)
	## v1.7: what this land is, on the land itself — a fortress, a pass, a harbour — as
	## small brass emblems off the token's left flank: under the shield, above the name
	## (at the lower-left they sat on the first letters of every harbour on the Isles).
	var td: Types.TerritoryDef = map.get_territory(id)
	if td != null and td.traits.size() > 0:
		var er: float = clampf(r * 0.5, 10.0, 14.0)
		var ep: Vector2 = p + Vector2(-r * 1.32, r * 0.42)
		for tr in td.traits:
			var tex: Texture2D = Style.tex("res://assets/icons/%s.png" % tr)
			if tex != null:
				## a brass medal: dark enough to sit on any land, bright enough to read at
				## token size, where the icon's own painting turns to mud
				ci.draw_circle(ep + Vector2(1.5, 2.5), er + 2.0, Color(0, 0, 0, 0.5))
				ci.draw_circle(ep, er + 2.0, Color(0.20, 0.15, 0.06, 0.97))
				ci.draw_arc(ep, er + 2.0, 0, TAU, 24, Color(1.0, 0.84, 0.42), 2.0, true)
				ci.draw_texture_rect(tex, Rect2(ep - Vector2(er, er) * 0.95, Vector2(er, er) * 1.9), false, Color(1.0, 0.95, 0.82))
			ep.x -= (er + 2.0) * 2.1
	## v1.7: a land with no road home. The rule is invisible otherwise, and an invisible
	## rule is a rule the commander gets caught by rather than plays around.
	if map.supply and owner != Types.UNOCCUPIED and owner != "neutral" and not MapLib.in_supply(world, map, id):
		var cut := Color(0.92, 0.35, 0.28)
		ci.draw_arc(p, r + 6.0, 0, TAU, 40, Color(cut, 0.85), 2.5, true)
		var cw: float = f.get_string_size("CUT OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var cpp: Vector2 = p + Vector2(-cw * 0.5, -r - 10)
		ci.draw_string_outline(f, cpp, "CUT OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0.05, 0.03, 0.02, 0.9))
		ci.draw_string(f, cpp, "CUT OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cut)
	## v1.13: a land that holds the road home for others: an amber ring, dashed (the tooltip names them)
	if hinges.has(id):
		var amber := Color(1.0, 0.72, 0.25, 0.85)
		for k in 16:
			ci.draw_arc(p, r + 6.0, TAU * k / 16.0, TAU * (k + 0.55) / 16.0, 4, amber, 2.5, true)
	## enemy ceiling: the most this hex could hold after their hidden reinforcement. v1.13.2: only
	## where you could march on it (it borders a land of yours) and on the land you hover; on every
	## enemy land at once it was clutter (the play critic counted about 20 numbers on the ring)
	if show_ceiling and owner != viewer and owner != Types.UNOCCUPIED and (id == hovered or _borders(id, viewer)):
		var ceiling: int = n + (Income.cap_of(world, map, id) * ceiling_mult if owner != "neutral" else 0)
		if ceiling > n:
			drawn_ceilings.append(id)
			var cp: Vector2 = p + Vector2(r * 0.95, -r * 0.8)
			var ct := "≤%d" % ceiling
			var cw: float = f.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			ci.draw_rect(Rect2(cp - Vector2(cw * 0.5 + 4, 10), Vector2(cw + 8, 18)), Color(0.06, 0.05, 0.05, 0.85))
			ci.draw_string(f, cp + Vector2(-cw * 0.5, 4), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.75, 0.65))
