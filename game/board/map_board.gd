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
signal clash_met ## v2.0.2: a clash's two columns have just met on the border

var art: RefCounted
var map: Types.MapDef
var world: Types.World
var viewer := "" ## whose eyes: own lands show caps, enemy lands show their ceiling
var selected := ""
var hovered := ""
var targets := {} ## id -> true, pulsing gold
var dimmed := {}
var battle := {}
var clash: Array = []: ## [land a, land b]: a border clash being fought on the line between them
	set(v):
		clash = v
		if v.size() >= 2 and (clash_fx.is_empty() or str(clash_fx["a"]) != str(v[0]) or str(clash_fx["b"]) != str(v[1])):
			clash_fx = {"a": str(v[0]), "b": str(v[1]), "t0": _time, "hit": false}
## v2.0.2: a border clash, told (the owner: "border clashes show both arrows colliding, with the
## winner's carrying through"). The two columns charge down the road between their lands and meet
## on the border; they push there while the dice roll; when the dice land, the winner's arrow shoves
## the loser's back into its own land and carries on to the land it marched on, its count falling to
## the men still standing. {a, b, t0, hit, won?: {owner, from, to, n0, n1, t}, lost?: {owner, n}}
var clash_fx := {}
const CLASH_DRIVE := 0.45 ## the columns charge to the border
const CLASH_HOLD := 0.45 ## at least this long locked on the border before the break
const CLASH_PUSH := 0.65 ## the winner carries through
var drawn_clash := {} ## v2.0.2: this frame's clash, as drawn (the probe reads it): {meet, a_tip, b_tip, winner, w}
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
var drawn_cut: Dictionary = {} ## v1.14: land -> where its CUT OFF plate sits this frame (the probe reads it)
var drawn_bonus: Dictionary = {} ## v1.14: region -> the screen rect of its bonus and pips this frame (the probe reads it)
var _names_now: Array = [] ## v1.14: this frame's name plates (found once a frame, when a fate mark needs them)
var _fate_spots: Array = [] ## v1.14: where this frame's fate marks go, queued before the tokens draw
var _fates_q: Array = [] ## v2.0.1: this frame's fate marks, [at, fate, toward, count]: two of a kind that would touch are one
var names_over: Array = [] ## v2.0.1: lands whose name a crown touched, written again over it this frame (the probe reads it)
var drawn_crowns: Dictionary = {} ## v2.0.1: capital -> the screen rect of its crown this frame (the probe reads it)
var _region_font: FontVariation

var zoom := 0.5
var offset := Vector2.ZERO
## v2.0: the board drawn over the land in 3D: map -> screen through the 3D camera, and back (a
## ray onto the ground). Empty: the flat chart, as ever.
var ships_drawn := true ## v2.0: the chart's painted ships (off when the land's own ships sail under the board)
var view_fix: Callable = Callable() ## v2.0: (screen point, map point) -> moves the view so the point stays under it
var projector: Callable = Callable()
var unprojector: Callable = Callable()
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
	_bonus_at.clear()
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
	_owner_seen.clear()
	_ink.clear()
	_count_seen.clear()
	_count_fx.clear()
	_region_seen.clear()
	_region_fx.clear()
	_mat.set_shader_parameter("state_tex", _state_tex)
	var depths: Array = art.depth.values()
	depths.sort()
	_token_base = clampf(float(depths[depths.size() / 2]) * 0.2, 16.0, 26.0)
	terrain.texture = art.data_texture
	terrain.material = _mat
	terrain.size = art.size
	_at_fit = true
	_on_resized()


## v2.0.2: a land changing hands: its new owner's colour spreads over it (on the chart and on the
## land under the board) and its token pops with a ring, rather than the colour swapping in a frame
var _owner_seen := {} ## id -> the owner last drawn
var _ink := {} ## id -> {from: Color, to: Color, t0, owner}
## v2.0.2: a land's count that changes (men placed, men lost) gives its number a bump, gold up and
## red down, rather than the figure changing under the eye unseen
var _count_seen := {}
var _count_fx := {} ## id -> {t0, up}
const COUNT_FX := 0.6
var _hover_k := {} ## v2.0.2: id -> how far its token has lifted under the cursor (0..1)
## v2.0.2: a region falling wholly to one commander is a moment: its name flares in their colours
## and a ring sweeps over each of its lands
var _region_seen := {} ## region -> who holds all of it ("" for no one)
var _region_fx := {} ## region -> {t0, owner}
const REGION_FX := 1.8
const INK := 0.7 ## seconds for a taken land to take its new colour


func refresh() -> void:
	if art == null or world == null:
		return
	for i in art.order.size():
		var id: String = art.order[i]
		var ts: Types.TerritoryState = world.get_territory(id)
		var owner: String = ts.owner if ts else ""
		var col: Color = Style.seat_color(owner)
		if _owner_seen.has(id) and str(_owner_seen[id]) != owner and not plain:
			var was: Color = _ink_now(id) if _ink.has(id) else Style.seat_color(str(_owner_seen[id]))
			_ink[id] = {"from": was, "to": col, "t0": _time, "owner": owner}
		elif ts != null and _count_seen.has(id) and int(_count_seen[id]) != ts.armies + ts.garrison and not plain:
			_count_fx[id] = {"t0": _time, "up": ts.armies + ts.garrison > int(_count_seen[id])}
		_owner_seen[id] = owner
		_count_seen[id] = ts.armies + ts.garrison if ts != null else 0
		if _ink.has(id):
			col = _ink_now(id)
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
	if not plain:
		for r in map.region_bonus.keys():
			var holder := ""
			for m in MapLib.region_members(map, str(r)):
				var mts: Types.TerritoryState = world.get_territory(m)
				var mo: String = mts.owner if mts != null else ""
				if mo == Types.UNOCCUPIED or (holder != "" and mo != holder):
					holder = ""
					break
				holder = mo
			if _region_fx.has(r) and str(_region_fx[r]["owner"]) != holder:
				_region_fx.erase(r) ## won and lost again in one report: its moment ends with it
			if _region_seen.has(r) and holder != "" and str(_region_seen[r]) != holder:
				_region_fx[r] = {"t0": _time, "owner": holder}
				if art.regions.has(r):
					## its bonus rises off its name: the commander's now, every round
					fx.append({"map": art.regions[r], "text": "+%d A ROUND" % int(map.region_bonus[r]), "color": Style.seat_color(holder).lightened(0.45), "t": 0.0, "dur": 2.2, "size": 30})
			_region_seen[r] = holder
	_mat.set_shader_parameter("select_id", int(art.index.get(selected, -1)))
	_mat.set_shader_parameter("hover_id", int(art.index.get(hovered, -1)) if interactive else -1)
	overlay.queue_redraw()


func _ink_now(id: String) -> Color:
	var k: Dictionary = _ink[id]
	var e: float = smoothstep(0.0, 1.0, clampf((_time - float(k["t0"])) / INK, 0.0, 1.0))
	return (k["from"] as Color).lerp(k["to"], e)


func region_won(region: String) -> float:
	## v2.0.2: how far through its moment a region just won is (0..1), or -1 (the probe reads it)
	if not _region_fx.has(region):
		return -1.0
	return clampf((_time - float(_region_fx[region]["t0"])) / REGION_FX, 0.0, 1.0)


func taking(id: String) -> float:
	## v2.0.2: how far through being taken this land is (0..1), or -1 (the probe reads it)
	if not _ink.has(id):
		return -1.0
	return clampf((_time - float(_ink[id]["t0"])) / INK, 0.0, 1.0)


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

func behind(s: Vector2) -> bool:
	## v2.0.2: a screen point the land's camera can't truly show: land.project's sentinel for a point
	## behind it, or one just in front of its near plane thrown absurdly far off the screen (a battle's
	## low camera). Drawing there made degenerate shapes ("triangulation failed": 266 in one soak, then
	## 23 from the near plane in the next)
	return absf(s.x) > 20000.0 or absf(s.y) > 20000.0 or not s.is_finite()


func map_to_screen(p: Vector2) -> Vector2:
	if projector.is_valid():
		return projector.call(p)
	return offset + p * zoom


func screen_to_map(p: Vector2) -> Vector2:
	if unprojector.is_valid():
		return unprojector.call(p)
	return (p - offset) / zoom


func land_at(screen_p: Vector2) -> String:
	## the land under a screen point: a token's own land first (v2.0: on the land a hill can stand
	## in front of a token's ground), then the ground itself
	if projector.is_valid() and art != null:
		var r: float = token_radius()
		var best := ""
		var best_d := r * r
		for id in art.order:
			var d: float = anchor(id).distance_squared_to(screen_p)
			if d < best_d:
				best_d = d
				best = id
		if best != "":
			return best
	return art.territory_at(screen_to_map(screen_p))


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
	if view_fix.is_valid() and not _at_fit:
		view_fix.call(screen_p, before) ## on the land: the ground under the cursor stays under it


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
	keep_home()
	_kill(_lean_tw)
	_kill(_back_tw)
	var z0: float = zoom
	var o0: Vector2 = offset
	var z1: float = clampf(fit * zmult, fit, fit * 3.5)
	var mid := Vector2(size.x * 0.5, pad_top + (size.y - pad_top - pad_bottom) * 0.5)
	var o1: Vector2 = mid - c * z1
	_at_fit = false
	var tw := create_tween()
	_swoop_tw = tw ## (RV-002 F5: a report skipped mid-swoop stops it, so the view it found comes back)
	tw.tween_method(func(t: float):
		var e: float = ease(t, -2.2)
		zoom = lerpf(z0, z1, e)
		offset = o0.lerp(o1, e)
		_apply_view(), 0.0, 1.0, dur)
	return tw


func swoop_back(dur: float) -> Tween:
	_kill(_lean_tw)
	_kill(_back_tw)
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
	_back_tw = tw
	return tw


## v2.0.2: the battle report's camera on the land. It leans in on each fight as it's told, close
## enough to see the columns meet and with all its lands in view, hops (out a little and back in)
## between fights far apart, and gives back the view it found when the report ends.
const LEAN := 1.9 ## how close it leans, against the fit
var _lean_tw: Tween
var _back_tw: Tween
var _swoop_tw: Tween ## a battle's swoop down (swoop_to): its finish opens the battle, so only a skip stops it
var _cam_home := {} ## the view the report found: {zoom, offset, at_fit}


func _kill(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()


func keep_home() -> void:
	## remember the view the report found (on the land, where its camera moves), once
	if _cam_home.is_empty() and projector.is_valid():
		_cam_home = {"zoom": zoom, "offset": offset, "at_fit": _at_fit}


func lean_in(ids: Array, aim_y: float = 0.5, dur: float = 0.75) -> void:
	## frame these lands: their middle at aim_y of the free height, all of them in the middle band
	if art == null or ids.is_empty():
		return
	var c := Vector2.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var n := 0
	for id in ids:
		if art.anchors.has(id):
			var q: Vector2 = art.anchors[id]
			c += q
			lo = lo.min(q)
			hi = hi.max(q)
			n += 1
	if n == 0:
		return
	c /= float(n)
	keep_home()
	var avail_h: float = size.y - pad_top - pad_bottom
	var span: Vector2 = hi - lo
	var z1: float = fit * LEAN
	if span.x > 1.0:
		z1 = minf(z1, size.x * 0.45 / span.x)
	if span.y > 1.0:
		z1 = minf(z1, avail_h * 0.25 / span.y)
	_glide(c, clampf(z1, fit * 1.2, fit * 3.0), aim_y, dur)


func camera_moving() -> bool:
	## the report's camera is on its way somewhere (a lean, or back to the view it found)
	return (_lean_tw != null and _lean_tw.is_valid() and _lean_tw.is_running()) or (_back_tw != null and _back_tw.is_valid() and _back_tw.is_running())


func in_view(ids: Array, margin: float = 60.0) -> bool:
	## every one of these lands is on the screen, clear of its edges
	var r := Rect2(Vector2(margin, pad_top + margin), Vector2(size.x - margin * 2.0, size.y - pad_top - pad_bottom - margin * 2.0))
	for id in ids:
		if art.anchors.has(id) and not r.has_point(anchor(str(id))):
			return false
	return true


func stand_back(dur: float = 0.9, keep: bool = false) -> void:
	## the view the report found, again (keep: between its stages, it will lean in again)
	if _cam_home.is_empty():
		return
	var home: Dictionary = _cam_home
	if not keep:
		_cam_home = {}
	if bool(home["at_fit"]):
		if not (_at_fit or (_back_tw != null and _back_tw.is_valid())):
			swoop_back(dur)
		return
	var aim := Vector2(size.x * 0.5, pad_top + (size.y - pad_top - pad_bottom) * 0.5)
	_glide((aim - (home["offset"] as Vector2)) / maxf(float(home["zoom"]), 0.0001), float(home["zoom"]), 0.5, dur)


func restore_view() -> void:
	## the report skipped: the view it found, at once
	if _cam_home.is_empty():
		return
	var home: Dictionary = _cam_home
	_cam_home = {}
	_kill(_lean_tw)
	_kill(_back_tw)
	_kill(_swoop_tw)
	if bool(home["at_fit"]):
		reset_view()
	else:
		zoom = float(home["zoom"])
		offset = home["offset"]
		_at_fit = false
		_apply_view()


func _glide(c1: Vector2, z1: float, aim_y: float, dur: float) -> void:
	## the camera to map point c1 at aim_y of the free height, at zoom z1: the point at the aim
	## travels and the zoom eases, so the way there is straight; far apart, it hops out on the way
	_kill(_lean_tw)
	_kill(_back_tw)
	var aim := Vector2(size.x * 0.5, pad_top + (size.y - pad_top - pad_bottom) * aim_y)
	var z0: float = zoom
	var c0: Vector2 = (aim - offset) / maxf(z0, 0.0001)
	var hop: float = clampf((c1 - c0).length() * minf(z0, z1) / maxf(size.x, 1.0) - 0.15, 0.0, 0.6)
	_at_fit = false
	_lean_tw = create_tween()
	_lean_tw.tween_method(func(t: float):
		var e: float = ease(t, -2.0)
		zoom = maxf(fit, lerpf(z0, z1, e) * (1.0 - hop * 0.5 * sin(PI * t)))
		offset = aim - c0.lerp(c1, e) * zoom
		_apply_view(), 0.0, 1.0, dur)


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
			if unprojector.is_valid():
				## v2.0, on the land: the ground under the cursor stays under it
				offset += (screen_to_map(event.position) - screen_to_map(event.position - event.relative)) * zoom
			else:
				offset += event.relative
			_at_fit = false
			_apply_view()
			return
		if _pressing and _press_id == "" and event.position.distance_to(_press_pos) > 6:
			_panning = true
			return
		if _pressing and _press_id != "" and event.position.distance_to(_press_pos) > 12:
			drag_from = _press_id
		var id: String = land_at(event.position)
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
				_press_id = land_at(mb.position)
				drag_from = ""
			else:
				var was_pan := _panning
				_pressing = false
				_panning = false
				if was_pan:
					return
				var id: String = land_at(mb.position)
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
			var id2: String = land_at(mb.position)
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
	for k in _region_fx.keys():
		if _time - float(_region_fx[k]["t0"]) >= REGION_FX:
			_region_fx.erase(k)
		else:
			live = true
	for k in _count_fx.keys():
		if _time - float(_count_fx[k]["t0"]) >= COUNT_FX:
			_count_fx.erase(k)
		else:
			live = true
	var hov: String = hovered if interactive else ""
	if hov != "" and not _hover_k.has(hov):
		_hover_k[hov] = 0.0
	for k in _hover_k.keys():
		var to: float = 1.0 if str(k) == hov else 0.0
		_hover_k[k] = move_toward(float(_hover_k[k]), to, delta * 7.0)
		if float(_hover_k[k]) != to:
			live = true
		if to == 0.0 and float(_hover_k[k]) <= 0.0:
			_hover_k.erase(k)
	if not _ink.is_empty():
		live = true
		for k in _ink.keys():
			var ink_i: int = int(art.index.get(k, -1))
			if _time - float(_ink[k]["t0"]) >= INK:
				_ink.erase(k)
			if ink_i >= 0:
				var px: Color = _state_img.get_pixel(ink_i, 0)
				var c2: Color = _ink_now(str(k)) if _ink.has(k) else Style.seat_color(str(_owner_seen.get(k, "")))
				_state_img.set_pixel(ink_i, 0, Color(c2.r, c2.g, c2.b, px.a))
		_state_tex.update(_state_img)
	if not clash_fx.is_empty():
		var cu: float = _time - float(clash_fx["t0"])
		if not bool(clash_fx["hit"]) and cu >= CLASH_DRIVE:
			## the columns meet: both lands' tokens take the shock
			clash_fx["hit"] = true
			shake[str(clash_fx["a"])] = 0.35
			shake[str(clash_fx["b"])] = 0.35
			clash_met.emit()
		if clash.is_empty() and (not clash_fx.has("won") or _time - float(clash_fx["won"]["t"]) > CLASH_PUSH + 0.25):
			clash_fx = {}
	if not fx.is_empty() or not shake.is_empty() or not battle.is_empty() or not clash.is_empty() or not clash_fx.is_empty() or drag_from != "" or flow:
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
	drawn_cut.clear()
	drawn_bonus.clear()
	_fate_spots.clear()
	_fates_q.clear()
	drawn_crowns.clear()
	names_over.clear()
	_names_now = []
	_draw_ornaments(ci)
	_draw_lanes(ci)
	if show_region_labels:
		_draw_region_labels(ci)
	if plain:
		return
	_surges_drawn = {}
	for g in ghosts:
		_draw_ghost(ci, g)
	for q in _fates_q:
		_late.append(_draw_fate_mark.bind(q[0], q[1], q[2], q[3]))
		_fate_spots.append(q[0])
	_surges_drawn = {}
	drawn_clash = {}
	for o in orders:
		if clash_hides(str(o["from"]), str(o["to"]), str(o.get("owner", ""))):
			continue ## the clash draws these two columns itself, meeting on the border
		var grow: float = clampf((_time - float(o["born"])) / 0.55, 0.0, 1.0) if o.has("born") else 1.0
		_draw_arrow(ci, str(o["from"]), str(o["to"]), int(o.get("strength", 1)), str(o.get("owner", "")), str(o.get("surge", "")), str(o.get("kind", "attack")), float(o.get("alpha", 1.0)), true, grow, int(o.get("surge_n", 0)))
	if drag_from != "":
		_draw_drag(ci)
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
				if t2 != null and ships_drawn:
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


func clash_hides(from_id: String, to_id: String, owner: String = "") -> bool:
	## v2.0.2: while a clash is being told, its two columns are drawn by it, not as plain arrows.
	## Before rules 21 a commander's columns into one land were one army, and all of it fought the
	## clash: every one of its orders into that land stands aside too, or the map shows the army and
	## its parts at once (RV-004 F1)
	if clash_fx.is_empty():
		return false
	var a: String = str(clash_fx["a"])
	var b: String = str(clash_fx["b"])
	var on_road: bool = (from_id == a and to_id == b) or (from_id == b and to_id == a)
	if not on_road and bool(clash_fx.get("merged", false)) and owner != "":
		var sides: Dictionary = clash_fx.get("sides", {})
		on_road = (to_id == b and str((sides.get(a, {}) as Dictionary).get("owner", "")) == owner) \
			or (to_id == a and str((sides.get(b, {}) as Dictionary).get("owner", "")) == owner)
	if not on_road:
		return false
	return not clash_fx.has("won") or _time - float(clash_fx["won"]["t"]) < CLASH_PUSH


func clash_won(winner: String, win_from: String, win_to: String, n0: int, n1: int, loser: String, lost_n: int) -> void:
	## v2.0.2: the dice landed (the cinema says who won): the winner's column carries through, n0
	## men in and n1 still standing; the loser's (lost_n men) is driven back into win_to
	var pair: Array = [str(clash_fx.get("a", "")), str(clash_fx.get("b", ""))]
	if clash_fx.is_empty() or not (pair.has(win_from) and pair.has(win_to)):
		## told without its charge (the report went on before the dice landed): already locked
		clash_fx = {"a": win_from, "b": win_to, "t0": _time - CLASH_DRIVE - CLASH_HOLD, "hit": true}
	if clash_fx.has("won"):
		return
	## dice that land before the columns have met (and pushed a moment) wait for them
	var at: float = maxf(_time, float(clash_fx["t0"]) + CLASH_DRIVE + CLASH_HOLD)
	clash_fx["won"] = {"owner": winner, "from": win_from, "to": win_to, "n0": n0, "n1": n1, "t": at, "m0": 0.5}
	clash_fx["lost"] = {"owner": loser, "from": win_to, "to": win_from, "n": lost_n}


func clash_clock() -> Dictionary:
	## v2.0.2: the clash as the land's columns need it: which lands, how long since they set off,
	## and how long since the break (-1 before it)
	if clash_fx.is_empty():
		return {}
	var won: Dictionary = clash_fx.get("won", {})
	var since: float = _time - float(won["t"]) if not won.is_empty() and _time >= float(won["t"]) else -1.0
	return {"a": str(clash_fx["a"]), "b": str(clash_fx["b"]), "u": _time - float(clash_fx["t0"]), "won_from": str(won.get("from", "")), "since_won": since}


func clash_sides(a_owner: String, a_n: int, b_owner: String, b_n: int, merged: bool = false) -> void:
	## the clash's two columns as its event tells them (a surge's column has no arrow of its own on
	## the board: it is drawn on from the land it set out from). merged: before rules 21, each side
	## is all its commander's columns into the other's land, one army
	if not clash_fx.is_empty():
		clash_fx["sides"] = {str(clash_fx["a"]): {"owner": a_owner, "n": a_n}, str(clash_fx["b"]): {"owner": b_owner, "n": b_n}}
		clash_fx["merged"] = merged


func _clash_side(from_id: String, to_id: String) -> Dictionary:
	## one of the two columns in the clash: {owner, n}, as its event tells it when the cinema has
	## (the event's size is the army that fought: before rules 21 a commander's columns into one
	## land were one army, RV-003 F2), else as its order on the board
	var told: Dictionary = (clash_fx.get("sides", {}) as Dictionary).get(from_id, {})
	if not told.is_empty() and not clash_fx.has("lost"):
		return told
	for o in orders:
		if str(o["from"]) == from_id and str(o["to"]) == to_id:
			return {"owner": str(o.get("owner", "")), "n": int(o.get("strength", 1))}
	var lost: Dictionary = clash_fx.get("lost", {})
	if not lost.is_empty() and str(lost["from"]) == from_id:
		return lost
	return (clash_fx.get("sides", {}) as Dictionary).get(from_id, {})


func _road_at(road: PackedVector2Array, f: float) -> Vector2:
	var i: int = clampi(int(f), 0, road.size() - 2)
	return road[i].lerp(road[i + 1], clampf(f - float(i), 0.0, 1.0))


func _road_part(road: PackedVector2Array, s0: float, s1: float) -> PackedVector2Array:
	## the stretch of a road from s0 to s1 (shares of its length from its start; s1 < s0 runs back)
	var n: int = road.size() - 1
	var f0: float = clampf(s0, 0.0, 1.0) * n
	var f1: float = clampf(s1, 0.0, 1.0) * n
	var out := PackedVector2Array([_road_at(road, f0)])
	if f1 >= f0:
		for i in range(int(floor(f0)) + 1, int(ceil(f1))):
			out.append(road[i])
	else:
		for i in range(int(ceil(f0)) - 1, int(floor(f1)), -1):
			out.append(road[i])
	out.append(_road_at(road, f1))
	return out


func _draw_clash_column(ci: CanvasItem, pts: PackedVector2Array, side: Dictionary, n: int, alpha: float, broken: bool) -> void:
	## one column's arrow, from its land to where it has got to: a head on it while it fights, a
	## splintered end once it's beaten
	if pts.size() < 2 or pts[0].distance_to(pts[pts.size() - 1]) < 2.0:
		return
	var col: Color = Style.seat_color(str(side["owner"])).lightened(0.15)
	if broken:
		col = col.darkened(0.35)
	col.a = alpha
	var w: float = clampf(4.0 + sqrt(float(maxi(n, 1))) * 1.6, 4.0, 13.0)
	var dark := Color(0.05, 0.04, 0.03, alpha * 0.9)
	if projector.is_valid():
		_arrow_shadow(ci, pts, w, alpha, false)
	ci.draw_polyline(pts, dark, w + 4.0, true)
	ci.draw_polyline(pts, col, w, true)
	var tip: Vector2 = pts[pts.size() - 1]
	var back: Vector2 = (tip - pts[maxi(0, pts.size() - 3)]).normalized()
	var sd: Vector2 = back.orthogonal()
	if broken:
		for k in [-1.0, 1.0]:
			ci.draw_line(tip, tip - back * (w + 4.0) + sd * k * (w + 2.0), dark, 3.0, true)
	else:
		ci.draw_colored_polygon(PackedVector2Array([tip + back * 4.0, tip - back * (w + 4.0) + sd * (w + 6.0), tip - back * (w + 4.0) - sd * (w + 6.0)]), dark)
		ci.draw_colored_polygon(PackedVector2Array([tip, tip - back * (w + 2.0) + sd * (w + 2.5), tip - back * (w + 2.0) - sd * (w + 2.5)]), col)
	## its count rides beside it (on its own left, so the two columns' counts sit either side of the road)
	var fm: float = (pts.size() - 1) * 0.4
	var along: Vector2 = (_road_at(pts, minf(fm + 0.5, pts.size() - 1)) - _road_at(pts, maxf(fm - 0.5, 0.0))).normalized()
	var txt := str(n)
	var f := Style.font("bold")
	var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var rad: float = maxf(12.0, tw * 0.5 + 7.0)
	var mid: Vector2 = _road_at(pts, fm) + along.orthogonal() * (rad + w * 0.5 + 3.0)
	ci.draw_circle(mid, rad + 2.0, dark)
	ci.draw_circle(mid, rad, Color(0.96, 0.92, 0.82, alpha))
	ci.draw_string(f, mid + Vector2(-tw * 0.5, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.1, 0.08, 0.06, alpha))


func _draw_clash(ci: CanvasItem) -> void:
	## v2.0.2: two columns meeting on the border. They charge down the road between their lands,
	## lock where they meet (a flare behind the two heads, sparks flying) and push there while the
	## dice roll; then the winner's arrow drives the loser's back into its own land and carries on.
	if clash_fx.is_empty():
		return
	var a_id: String = str(clash_fx["a"])
	var b_id: String = str(clash_fx["b"])
	if not art.anchors.has(a_id) or not art.anchors.has(b_id):
		return
	var won: Dictionary = clash_fx.get("won", {})
	if not won.is_empty() and _time < float(won["t"]):
		won = {} ## the dice are in, but the columns are still to meet
	elif not won.is_empty() and not bool(clash_fx.get("broke", false)):
		clash_fx["broke"] = true
		won["m0"] = float(clash_fx.get("m", 0.5))
		shake[str(won["to"])] = 0.5 ## the beaten land takes the blow
	var w: float = clampf((_time - float(won["t"])) / CLASH_PUSH, 0.0, 1.0) if not won.is_empty() else 0.0
	if w >= 1.0:
		return ## the winner's own arrow has taken over
	var side_a: Dictionary = _clash_side(a_id, b_id)
	var side_b: Dictionary = _clash_side(b_id, a_id)
	var r := token_radius()
	var pa: Vector2 = anchor(a_id)
	var pb: Vector2 = anchor(b_id)
	var d: Vector2 = (pb - pa).normalized()
	var road: PackedVector2Array = _curve(pa + d * (r + 2.0), pb - d * (r + 2.0), 0.14 if a_id < b_id else -0.14)
	var nr: float = float(road.size() - 1)
	var u: float = _time - float(clash_fx["t0"])
	var drive: float = clampf(u / CLASH_DRIVE, 0.0, 1.0)
	var charge: float = drive * drive ## they gather speed into each other
	var locked: float = smoothstep(0.0, 0.3, u - CLASH_DRIVE)
	## where they meet, as a share of the road from a: it sways while they push
	var m: float = 0.5 + (sin(_time * 5.3) * 0.035 + sin(_time * 8.7) * 0.015) * locked
	var a_tip: float = 0.5 * charge if drive < 1.0 else m
	var b_tip: float = 1.0 - 0.5 * charge if drive < 1.0 else m
	var a_won := false
	var e := 0.0
	if not won.is_empty():
		a_won = str(won["from"]) == a_id
		e = 1.0 - pow(1.0 - w, 3.0) ## the shove: fast, then home
		m = lerpf(float(won["m0"]), 1.0 if a_won else 0.0, e)
		a_tip = m
		b_tip = m
	else:
		clash_fx["m"] = m
	var meet: Vector2 = _road_at(road, m * nr)
	## the flare where they meet, behind the two heads
	if drive >= 1.0:
		var pulse: float = 0.5 + 0.5 * sin(_time * 9.0)
		var pop: float = clampf((u - CLASH_DRIVE) / 0.22, 0.0, 1.0)
		var grow: float = (1.0 + 2.7 * pow(pop - 1.0, 3.0) + 1.7 * pow(pop - 1.0, 2.0)) * (1.0 + e * 1.1)
		var fade: float = 1.0 - e
		var R: float = r * (1.25 + 0.15 * pulse) * grow
		for layer in 2:
			var star := PackedVector2Array()
			var spin: float = _time * (0.6 if layer == 0 else -0.45)
			var k1: float = 1.0 if layer == 0 else 0.72
			for i in 22:
				star.append(meet + Vector2.from_angle(TAU * i / 22.0 + spin) * R * k1 * (1.0 if i % 2 == 0 else 0.5))
			ci.draw_colored_polygon(star, Color(1.0, 0.55, 0.15, 0.85 * fade) if layer == 0 else Color(1.0, 0.92, 0.55, 0.95 * fade))
		## the shock of the meeting, and of the break
		var hit_t: float = (u - CLASH_DRIVE) / 0.4
		if hit_t < 1.0:
			ci.draw_arc(meet, r * (0.6 + 2.6 * hit_t), 0, TAU, 40, Color(1.0, 0.95, 0.8, 0.9 * (1.0 - hit_t)), 4.0, true)
		if not won.is_empty():
			ci.draw_arc(meet, r * (0.8 + 3.2 * w), 0, TAU, 40, Color(1.0, 0.85, 0.5, 0.85 * (1.0 - w)), 5.0 * (1.0 - w) + 1.0, true)
	## the two columns: the winner's over the loser's
	var parts := [[side_a, _road_part(road, 0.0, a_tip), a_id], [side_b, _road_part(road, 1.0, b_tip), b_id]]
	if not won.is_empty() and not a_won:
		parts.reverse()
	for pt in parts:
		var side: Dictionary = pt[0]
		if side.is_empty():
			continue
		var beaten: bool = not won.is_empty() and str(pt[2]) != str(won["from"])
		var n: int = int(side["n"])
		if not won.is_empty() and not beaten:
			n = int(round(lerpf(float(won["n0"]), float(won["n1"]), e))) ## its losses paid as it goes
		_draw_clash_column(ci, pt[1], side, n, 1.0 - 0.85 * w if beaten else 1.0, beaten)
	## sparks fly while they fight, and a spray of them through the break
	if drive >= 1.0:
		var since: float = u - CLASH_DRIVE
		var beat: int = int(since / 0.55)
		var ph: float = fmod(since, 0.55) / 0.55
		var burst_n: int = 9
		if not won.is_empty():
			ph = w
			beat = 99
			burst_n = 14
		for i in burst_n:
			var h: float = fposmod(sin(float(i) * 12.9898 + float(beat) * 4.1) * 43758.5453, 1.0)
			var ang: float = TAU * float(i) / float(burst_n) + float(beat) * 1.7 + h * 0.5
			var dir: Vector2 = Vector2.from_angle(ang)
			if not won.is_empty():
				dir = (dir + (d if a_won else -d) * 1.4).normalized() ## carried on with the winner
			var dist: float = r * (0.45 + 1.5 * ph) * (0.75 + 0.5 * h)
			var p0: Vector2 = meet + dir * dist
			ci.draw_line(p0, p0 + dir * r * 0.32 * (1.0 - ph), Color(1.0, 0.93, 0.7, 0.95 * (1.0 - ph)), 2.5, true)
	drawn_clash = {"meet": meet, "a_tip": _road_at(road, a_tip * nr), "b_tip": _road_at(road, b_tip * nr), "m": m, "w": w,
		"winner": str(won.get("owner", "")), "met": drive >= 1.0, "sides": int(not side_a.is_empty()) + int(not side_b.is_empty()),
		"a_n": int(side_a.get("n", 0)), "b_n": int(side_b.get("n", 0))}


func _draw_region_labels(ci: CanvasItem) -> void:
	if _region_font == null:
		_region_font = FontVariation.new()
		_region_font.base_font = Style.font("display")
		_region_font.spacing_glyph = 5
	var k: float = zoom / maxf(fit, 0.01)
	var sz: int = int(clampf(30.0 * sqrt(k) * (art.size.x / 2400.0 + 0.3), 20.0, 52.0))
	var shares: Dictionary = BoardFacts.shares(world, map) if world != null and not plain else {}
	## the view zoomed (or, v2.0.1, on the land the camera tipped or swung, which moves the lands
	## against each other with no zoom: the Greyfell's bonus sat on Stonehold's name): the spots are
	## found again once it settles
	var lay: PackedVector2Array = _layout()
	## v2.4: found again once the view has held still a moment. It was every 0.15 s while the view
	## moved, and on the land a search can take a third of a second (each spot it tries asks the land
	## which region is under three points): the swoop down to a battle chugged
	if absf(zoom - _view_zoom) > zoom * 0.0005 or not _near_layout(lay, _view_layout):
		_view_still = _time
	_view_zoom = zoom
	_view_layout = lay
	if (absf(zoom - _bonus_zoom) > zoom * 0.002 or _layout_moved(lay)) and _time - _view_still > 0.15:
		_bonus_at.clear()
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
		var won_k: float = region_won(str(r))
		if won_k >= 0.0:
			## won whole: the name flares in its new master's colours, a ring over each of its lands
			var oc: Color = Style.seat_color(str(_region_fx[r]["owner"])).lightened(0.3)
			var glow: float = sin(PI * minf(won_k * 2.5, 1.0)) * 0.5 + (1.0 - won_k) * 0.5
			col = col.lerp(Color(oc, 0.95), clampf(glow * 1.4, 0.0, 1.0))
			var ms: PackedStringArray = MapLib.region_members(map, str(r))
			for mi in ms.size():
				var rk: float = clampf((won_k * REGION_FX - 0.1 * float(mi)) / 0.9, 0.0, 1.0)
				if rk > 0.0 and rk < 1.0 and art.anchors.has(ms[mi]):
					ci.draw_arc(anchor(ms[mi]), token_radius() * (1.1 + 1.8 * rk), 0, TAU, 40, Color(oc, 0.95 * (1.0 - rk)), 7.0 * (1.0 - rk) + 1.5, true)
					ci.draw_arc(anchor(ms[mi]), token_radius() * (1.0 + 1.2 * rk), 0, TAU, 40, Color(1.0, 0.9, 0.6, 0.7 * (1.0 - rk)), 2.0, true)
			ci.draw_string_outline(_region_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 9, Color(0.05, 0.03, 0.02, 0.5 * glow))
		ci.draw_string_outline(_region_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0.05, 0.03, 0.02, 0.35))
		ci.draw_string(_region_font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		var bf := Style.font("display")
		var bs: int = int(sz * 0.8)
		var bw: float = bf.get_string_size(bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
		## v1.14: the bonus and its pips are meant to be read, so they keep off the tokens and their
		## names (on the Known World Eastshore's pips sat on Steppe's name, Crownlands' on Throne's
		## crown): under the region's name if that's clear, else the nearest clear spot around it
		var pw: float = _pips_width((shares[r]["members"] as PackedStringArray).size(), sz) if shares.has(r) else 0.0
		var bw_all: float = bw + (10.0 + pw if shares.has(r) else 0.0)
		var bp := p + Vector2(-bw * 0.5, bs + 4)
		if world != null and not plain:
			bp = p + _bonus_spot(str(r), p, bp - p, Vector2(bw_all, bs), w, sz)
		drawn_bonus[r] = Rect2(bp + Vector2(0, -bs * 0.8), Vector2(bw_all, bs))
		ci.draw_string_outline(bf, bp, bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, 5, Color(0.05, 0.03, 0.02, 0.4))
		ci.draw_string(bf, bp, bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, Color(1.0, 0.85, 0.45, 0.7))
		if shares.has(r):
			## beside the bonus, over the tokens (a pip hidden under a crown would miscount)
			_late.append(_draw_region_pips.bind(shares[r], bp + Vector2(bw + 10.0, -bs * 0.34), sz))


var _bonus_at := {} ## v1.14: region -> [where its bonus sits from its label at _bonus_zoom, its size]
var _bonus_zoom := 0.0
var _bonus_t := -1.0
var _bonus_layout := PackedVector2Array()
var _view_zoom := 0.0 ## v2.4: the view last frame, and when it last moved (the bonuses are placed again once it rests)
var _view_layout := PackedVector2Array()
var _view_still := -1.0


static func _near_layout(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.5:
			return false
	return true


func _layout() -> PackedVector2Array:
	## v2.0.1: how three far-apart lands sit against each other on the screen (a pan on the chart
	## keeps it; a zoom, or the land's camera tipping or swinging, changes it)
	var o: Array = art.order
	if o.size() < 3:
		return PackedVector2Array()
	var a: Vector2 = anchor(str(o[0]))
	return PackedVector2Array([anchor(str(o[o.size() / 2])) - a, anchor(str(o[o.size() - 1])) - a])


func _layout_moved(lay: PackedVector2Array) -> bool:
	if lay.size() != _bonus_layout.size():
		return true
	for i in lay.size():
		if lay[i].distance_to(_bonus_layout[i]) > 1.0:
			return true
	return false
var _bonus_offsets: Array = []


func _bonus_spot(r: String, p: Vector2, home: Vector2, box: Vector2, name_w: float, sz: int) -> Vector2:
	## the nearest spot to `home` (from the label at p) where a box this big covers no token, no
	## land's name and no other region's bonus; failing that, the one that covers least. Found once
	## per zoom (and scaled meanwhile while a zoom is under way): panning only slides it.
	if _bonus_at.has(r) and ((_bonus_at[r][1] as Vector2).is_equal_approx(box) or _time - _view_still <= 0.15):
		return (_bonus_at[r][0] as Vector2) * (zoom / maxf(_bonus_zoom, 0.0001)) ## (v2.4: and while the view moves, whatever its size)
	if _bonus_offsets.is_empty():
		for dy in range(-16, 17):
			for dx in range(-40, 41):
				_bonus_offsets.append(Vector2(dx, dy))
		_bonus_offsets.sort_custom(func(a, b): return a.x * a.x + 1.7 * a.y * a.y < b.x * b.x + 1.7 * b.y * b.y)
	var step := Vector2(minf(8.0, (name_w * 0.5 + 60.0) / 40.0), float(sz) * 0.16)
	var reach := Rect2(p + home - Vector2(name_w * 0.5 + 60.0, step.y * 16.0), box + Vector2(name_w + 120.0, step.y * 32.0))
	## a land's name weighs three times a token's box (whose corners are mostly empty)
	var near: Array = []
	for b in token_boxes():
		if reach.intersects(b as Rect2):
			near.append(b)
	for other in drawn_bonus.values():
		near.append(other)
	var names: Array = []
	for b in token_boxes(true, false):
		if reach.intersects(b as Rect2):
			names.append(b)
	var view := Rect2(Vector2(0, pad_top), size - Vector2(0, pad_top + pad_bottom))
	var lift := Vector2(0, -box.y * 0.8)
	var keep_in: bool = view.encloses(Rect2(p + home + lift, box))
	## it must read as its own region's: the nearest clear spot on its lands; else the nearest clear
	## spot in the water off them (on an archipelago, or the Ring's inner sea, the lands are full),
	## touching no other region; else the spot on its lands that covers least for its distance
	var best: Vector2 = home
	var best_cost := INF
	var own_best: Vector2 = Vector2.INF
	var own_cost := INF
	var wet: Vector2 = Vector2.INF
	for o in _bonus_offsets:
		var c: Vector2 = home + (o as Vector2) * step
		var rect := Rect2(p + c + lift, box)
		if keep_in and not view.encloses(rect):
			continue
		var hit: float = _overlap(rect, near)
		var cost: float = hit + (2.0 * _overlap(rect, names) if hit > 0.0 else 0.0) + 0.05 * c.distance_squared_to(home)
		if hit > 0.0 and cost >= own_cost:
			## v2.4: whose ground it is can't change a thing here (only a clear spot, or one cheaper
			## than the best on its own lands, is weighed by it): the land isn't asked
			if cost < best_cost:
				best_cost = cost
				best = c
			continue
		var mid: String = _region_at(rect.get_center())
		var ends: Array = [_region_at(rect.position + Vector2(4, box.y * 0.5)), _region_at(rect.end - Vector2(4, box.y * 0.5))]
		var own: bool = mid == r and (ends[0] == r or ends[1] == r)
		var off_shore: bool = (mid == r or mid == "") and ends.all(func(e): return e == r or e == "") and not own
		if hit <= 0.0 and own:
			own_best = c
			wet = Vector2.INF
			break
		if hit <= 0.0 and off_shore and wet == Vector2.INF:
			wet = c
		if own and cost < own_cost:
			own_cost = cost
			own_best = c
		if cost < best_cost:
			best_cost = cost
			best = c
	if wet != Vector2.INF:
		best = wet
	elif own_best != Vector2.INF:
		best = own_best
	_bonus_at[r] = [best, box]
	_bonus_zoom = zoom
	_bonus_layout = _layout()
	_bonus_t = _time
	return best


func _region_at(at: Vector2) -> String:
	## the region of the land under this screen point ("" on the sea)
	var id: String = art.territory_at(screen_to_map(at))
	var td: Types.TerritoryDef = map.get_territory(id) if id != "" else null
	return td.region if td != null else ""


func _draw_name(ci: CanvasItem, id: String, r: float) -> void:
	var f := Style.font("bold")
	var name: String = map.get_territory(id).display_name
	var ns := 15 if zoom < fit * 1.4 else 17
	var nw: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
	var np: Vector2 = anchor(id) + Vector2(-nw * 0.5, r + ns + 1)
	ci.draw_string_outline(f, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, 5, Color(0.05, 0.04, 0.03, 0.85))
	ci.draw_string(f, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, Style.CREAM if id != selected else Style.GOLD)


func crown_rect(id: String) -> Rect2:
	## v2.0.1: where a capital's crown sits: on its token's brow, unless that covers another land's
	## name (the play critic, at the Ring's fit zoom: crowns over "Greywatch" and "Cinderhow"); then
	## slid along the brow, then smaller and lower on it, whichever clears first
	if _names_now.is_empty():
		_names_now = token_boxes(true, false)
	var p: Vector2 = anchor(id)
	var r := token_radius()
	var cr: float = clampf(r * 0.85, 15.0, 24.0)
	var own: int = art.order.find(id) ## token_boxes(true, false) lists one name a land, in art.order
	var best := Rect2()
	var best_hit := INF
	for k in [1.0, 0.8, 0.62]:
		for dx in [0.0, 0.45, -0.45, 0.75, -0.75]:
			if k > 0.9 and absf(dx) > 0.5:
				continue ## a full-size crown out past the brow would sit on the shield or the plates
			var c: Vector2 = p + Vector2(r * dx, -r * (1.0 - 0.25 * (1.0 - k)) - cr * k * 0.25)
			var box := Rect2(c - Vector2(cr, cr) * k, Vector2(cr, cr) * 2.0 * k)
			var hit := 0.0
			for i in _names_now.size():
				if i != own:
					hit += box.intersection(_names_now[i] as Rect2).get_area()
			if hit <= 0.0:
				return box
			if hit < best_hit:
				best_hit = hit
				best = box
	return best


func token_boxes(names: bool = true, tokens: bool = true) -> Array:
	## v1.14: the screen rects of every land's token (its shield, crown and plates) and its name
	var out: Array = []
	var r := token_radius()
	var f := Style.font("bold")
	var ns := 15 if zoom < fit * 1.4 else 17
	for id in art.order:
		var p: Vector2 = anchor(str(id))
		if tokens:
			out.append(Rect2(p - Vector2(r * 1.55, r * 1.3), Vector2(r * 2.9, r * 2.4)))
			if world != null and world.territories.has(str(id)) and _is_capital(str(id), world.get_territory(str(id)).owner):
				out.append(crown_rect(str(id))) ## v2.0.1: a crown stands above the token's box
		var td: Types.TerritoryDef = map.get_territory(str(id)) if map != null else null
		if td != null and names:
			var nw: float = f.get_string_size(td.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
			out.append(Rect2(p + Vector2(-nw * 0.5 - 2.0, r + 2.0), Vector2(nw + 4.0, float(ns) + 3.0)))
	return out


static func _overlap(box: Rect2, boxes: Array) -> float:
	var a := 0.0
	for b in boxes:
		a += box.intersection(b as Rect2).get_area()
	return a


static func _pips_width(n: int, sz: int) -> float:
	## the region pips' pill, as _draw_region_pips draws it
	var pr: float = clampf(float(sz) * 0.13, 3.5, 6.5)
	return (pr * 2.0 + 3.0) * float(maxi(n, 1) - 1) + pr * 2.0 + 8.0


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
		end = _off_names(end, anchor(str(g["from"])), anchor(str(g["to"])))
		var back: String = str(g.get("fellTo", "")) if str(g.get("fellTo", "")) != "" else str(g["from"])
		_queue_fate(end, res, anchor(back) if art.anchors.has(back) else Vector2.INF)
	if surge_died:
		## the surge it sent on met another surge on the border and died there
		var se: Vector2 = _draw_arrow(ci, str(g["to"]), str(g["surgeTo"]), -1, str(g.get("owner", "")), "", kind, 0.42, false, 1.0, 0, 0.5)
		if se != Vector2.INF:
			_queue_fate(se, LastRound.CLASH, Vector2.INF)


func _queue_fate(at: Vector2, fate: String, toward: Vector2) -> void:
	## v2.0.1: two marks of one kind that would touch are one mark with a count (the play critic: two
	## red crosses at Cinderhow's walls ran together into one red blob)
	for q in _fates_q:
		if str(q[1]) == fate and (q[0] as Vector2).distance_to(at) < (fate_mark_size() + 6.0) * 2.2:
			q[3] = int(q[3]) + 1
			return
	_fates_q.append([at, fate, toward, 1])


func _draw_fate_mark(ci: CanvasItem, at: Vector2, fate: String, toward: Vector2, count: int = 1) -> void:
	## a column that failed, on a dark medal readable over any land or sea. v1.13.2: each fate its
	## own mark (the play critic: "you can tell it failed, but not how, without hovering"). Thrown
	## back or beaten on the border: a red cross. Fell back: a pale double chevron pointing the way
	## the survivors went. Beaten in a scramble (or the fight for the spoils): a broken banner.
	## v1.14: half as big again, on a solid disc (the critic: "about the size of an army crest, and
	## the pale chevron is the hardest to spot"), and the scramble's crossed swords became a broken
	## banner: the swords were the threat plate's symbol, so the two read as one thing.
	var s: float = fate_mark_size()
	drawn_fates.append([fate, at, count])
	var rr: float = s + 6.0
	ci.draw_circle(at + Vector2(1.5, 2.0), rr + 1.0, Color(0, 0, 0, 0.45))
	ci.draw_circle(at, rr, Color(0.10, 0.05, 0.04, 0.97))
	ci.draw_arc(at, rr, 0, TAU, 28, Color(0.98, 0.9, 0.72, 0.9), 2.0, true)
	if fate == LastRound.FELL_BACK:
		var d: Vector2 = (toward - at).normalized() if toward != Vector2.INF and toward.distance_to(at) > 1.0 else Vector2.LEFT
		var n: Vector2 = d.orthogonal()
		var pale := Color(1.0, 0.9, 0.6)
		for k in 2:
			var c: Vector2 = at + d * (s * (0.45 - 0.8 * k))
			ci.draw_polyline(PackedVector2Array([c - d * s * 0.45 + n * s * 0.8, c + d * s * 0.45, c - d * s * 0.45 - n * s * 0.8]), pale, 4.0, true)
	elif fate == LastRound.OUTFOUGHT:
		_draw_broken_banner(ci, at + Vector2(0, s * 0.06), s * 1.18)
	else:
		var red := Color(0.98, 0.36, 0.28)
		ci.draw_line(at + Vector2(-s, -s) * 0.85, at + Vector2(s, s) * 0.85, red, 4.0, true)
		ci.draw_line(at + Vector2(-s, s) * 0.85, at + Vector2(s, -s) * 0.85, red, 4.0, true)
	if count > 1:
		## how many columns this one mark stands for: "×2" on a cream tab at the disc's lower right
		var f := Style.font("bold")
		var ct := "×%d" % count
		var cs := 13
		var cw: float = f.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
		var tab := Rect2(at + Vector2(rr * 0.45, rr * 0.25), Vector2(cw + 8.0, 17.0))
		ci.draw_rect(Rect2(tab.position + Vector2(1.0, 1.5), tab.size), Color(0, 0, 0, 0.45))
		ci.draw_rect(tab, Color(0.98, 0.9, 0.72))
		ci.draw_rect(tab, Color(0.10, 0.05, 0.04), false, 1.5)
		ci.draw_string(f, tab.position + Vector2(4.0, 13.0), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color(0.25, 0.06, 0.04))


func _off_names(at: Vector2, toward: Vector2, home: Vector2) -> Vector2:
	## v1.14: a fate mark keeps off the lands' names (one that came in from below sat on the name
	## plate: "…en Spar"): it slides back along its arrow, or up onto the rim of the land's token,
	## whichever clears first
	if _names_now.is_empty():
		_names_now = token_boxes(true, false)
	var m: float = fate_mark_size() + 6.0
	var rim: float = token_radius() * 0.75
	for k in 13:
		for c in [at.move_toward(toward, 4.0 * k), at.move_toward(home, minf(3.0 * k, rim))]:
			var hit := false
			for b in _names_now:
				if (b as Rect2).intersects(Rect2(c - Vector2(m, m), Vector2(m, m) * 2.0)):
					hit = true
					break
			if not hit:
				return c
	return at


func fate_mark_size() -> float:
	## the fate marks' inner size (v1.14: 1.5x the v1.13.2 marks)
	return clampf(token_radius() * 0.48, 9.0, 13.5)


func _draw_broken_banner(ci: CanvasItem, at: Vector2, s: float) -> void:
	## a colour lost in the scramble: the staff snapped, its top hanging askew, the flag torn
	var staff := Color(0.98, 0.88, 0.66)
	var cloth := Color(0.98, 0.38, 0.3)
	var foot: Vector2 = at + Vector2(-0.45, 0.95) * s
	var snap: Vector2 = at + Vector2(-0.45, 0.05) * s
	ci.draw_line(foot, snap, staff, 3.0, true)
	## the broken top, leaning away from the stump
	var kink: Vector2 = at + Vector2(-0.25, -0.12) * s
	var tip: Vector2 = at + Vector2(0.55, -0.9) * s
	ci.draw_line(kink, tip, staff, 3.0, true)
	## the flag hangs off the top, its fly edge torn in a zigzag
	var dir: Vector2 = (tip - kink).normalized()
	var hoist: Vector2 = tip - dir * s * 0.62
	var drop := Vector2(0.18, 1.0).normalized() * s * 0.9
	var pts := PackedVector2Array([tip, tip + drop * 0.55 + Vector2(0.28, 0) * s, tip + drop * 0.7 + Vector2(0.05, 0) * s,
		tip + drop + Vector2(0.18, 0) * s, hoist + drop * 0.85, hoist])
	ci.draw_colored_polygon(pts, cloth)
	pts.append(tip)
	ci.draw_polyline(pts, Color(0.2, 0.05, 0.03, 0.9), 1.2, true)
	## the splinters at the break
	ci.draw_line(snap, snap + Vector2(0.2, -0.22) * s, staff, 2.0, true)


func _draw_arrow(ci: CanvasItem, from_id: String, to_id: String, strength: int, owner: String, surge: String, kind: String, alpha: float, labeled: bool, grow: float = 1.0, surge_n: int = 0, cut: float = 1.0) -> Vector2:
	## strength < 0: a surge onward (everyone left after the capture, less the one who stays)
	## v1.13: cut < 1 draws only that part of the way, with no head (a column that never got
	## there); returns where the drawn arrow ends (Vector2.INF when it isn't drawn)
	if not art.anchors.has(from_id) or not art.anchors.has(to_id):
		return Vector2.INF
	var r := token_radius()
	var a: Vector2 = anchor(from_id)
	var b: Vector2 = anchor(to_id)
	if behind(a) or behind(b) or a.distance_to(b) < 1.0:
		return Vector2.INF ## v2.0.2: an end behind the land's camera (a battle's low camera): nothing to draw
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
	if projector.is_valid():
		_arrow_shadow(ci, pts, w, alpha, kind == "move")
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
	if cut >= 1.0 and back != Vector2.ZERO:
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
	if surge != "" and art.anchors.has(surge) and not _surges_drawn.has(owner + to_id + surge) and not clash_hides(to_id, surge):
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


func _draw_drag(ci: CanvasItem) -> void:
	## v2.0.2: an order being dragged is drawn as the arrow it will be, in the commander's colours
	## (a march dashed), snapped onto the bordering land under the cursor; off any land it reaches
	## for the cursor
	var to: String = hovered if hovered != drag_from and art.anchors.has(hovered) and map.is_adjacent(drag_from, hovered) else ""
	if to != "":
		var ts: Types.TerritoryState = world.get_territory(to)
		var kind: String = "move" if ts != null and ts.owner == viewer and viewer != "" else "attack"
		var pulse: float = 0.78 + 0.18 * sin(_time * 6.0)
		_draw_arrow(ci, drag_from, to, 0, viewer, "", kind, pulse, false)
		return
	var a: Vector2 = anchor(drag_from)
	var col: Color = Style.seat_color(viewer).lightened(0.25) if viewer != "" else Color(1, 0.9, 0.6)
	col.a = 0.8
	var d: Vector2 = (_mouse - a)
	if d.length() < token_radius():
		return
	var dir: Vector2 = d.normalized()
	var start: Vector2 = a + dir * (token_radius() + 2.0)
	ci.draw_line(start, _mouse, Color(0.05, 0.04, 0.03, 0.6), 8.0, true)
	ci.draw_line(start, _mouse, col, 5.0, true)
	var sd: Vector2 = dir.orthogonal()
	ci.draw_colored_polygon(PackedVector2Array([_mouse + dir * 6.0, _mouse - dir * 10.0 + sd * 9.0, _mouse - dir * 10.0 - sd * 9.0]), col)


func _arrow_shadow(ci: CanvasItem, pts: PackedVector2Array, w: float, alpha: float, dashed: bool) -> void:
	## v2.0.2, on the land: an arrow casts a soft shadow on the ground under it, so it rides over
	## the land rather than lying painted on it
	var off := Vector2(w * 0.35 + 2.0, w * 0.5 + 3.0)
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + off)
	var c := Color(0, 0, 0, 0.22 * alpha)
	if dashed:
		for i in range(0, sh.size() - 1, 2):
			ci.draw_line(sh[i], sh[i + 1], c, w + 3.0, true)
	else:
		ci.draw_polyline(sh, c, w + 4.0, true)


func _draw_token(ci: CanvasItem, id: String) -> void:
	var ts: Types.TerritoryState = world.get_territory(id)
	if ts == null:
		return
	var p: Vector2 = anchor(id)
	if behind(p):
		return ## v2.0.2: behind the land's camera (a battle's low camera)
	var r := token_radius()
	if shake.has(id):
		r *= 1.0 + 0.18 * sin(float(shake[id]) * 18.0)
	var lift: float = float(_hover_k.get(id, 0.0))
	if lift > 0.0:
		r *= 1.0 + 0.08 * smoothstep(0.0, 1.0, lift) ## pointed at: the token lifts a little toward you
	var tk: float = taking(id)
	if tk >= 0.0 and ts.owner != Types.UNOCCUPIED:
		## v2.0.2: taken: the token pops up in its new colours, a ring of them going out over the land
		var ring_col: Color = Style.seat_color(ts.owner).lightened(0.25)
		ci.draw_arc(p, r * (1.0 + 1.6 * tk), 0, TAU, 40, Color(ring_col, 0.85 * (1.0 - tk)), 5.0 * (1.0 - tk) + 1.0, true)
		ci.draw_arc(p, r * (1.0 + 1.0 * tk), 0, TAU, 40, Color(1.0, 0.9, 0.6, 0.7 * (1.0 - tk)), 2.0, true)
		r *= 1.0 + 0.32 * sin(PI * minf(tk * 1.6, 1.0)) * (1.0 - tk)
	var owner: String = ts.owner
	var f := Style.font("bold")
	## name plate under the token
	var ns := 15 if zoom < fit * 1.4 else 17
	_draw_name(ci, id, r)
	if owner == Types.UNOCCUPIED:
		ci.draw_arc(p, r * 0.8, 0, TAU, 28, Color(0.95, 0.9, 0.78, 0.55), 2.0, true)
		ci.draw_string(f, p + Vector2(-6, 7), "–", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.9, 0.78, 0.7))
		return
	var col: Color = Style.seat_color(owner)
	var shape: String = Style.seat_shape(owner)
	if projector.is_valid():
		## v2.0, on the land: the token stands on its ground (a soft shadow on the land under it)
		ci.draw_set_transform(p + Vector2(r * 0.15, r * 0.62), 0.0, Vector2(1.0, 0.42))
		for k in 3:
			ci.draw_circle(Vector2.ZERO, r * (1.25 - 0.18 * k), Color(0, 0, 0, 0.09))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_circle(p + Vector2(2, 3), r + 1, Color(0, 0, 0, 0.35))
	var edge := Color(0.96, 0.9, 0.76) if id != selected else Color(1.0, 0.85, 0.35)
	if projector.is_valid():
		## v2.0.2, on the land: the piece has a thickness, its edge showing under the face
		var thick: Vector2 = Vector2(0, maxf(3.0, r * 0.16))
		Style.draw_shape(ci, shape, p + thick, r + 2.5, Color(0.08, 0.06, 0.05), Color(0.08, 0.06, 0.05), 1.0)
		Style.draw_shape(ci, shape, p + thick, r, col.darkened(0.5), col.darkened(0.6), 1.0)
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
	var num_col := Color(1, 0.98, 0.92) if marching > 0 else Color(1, 0.98, 0.92, 0.5)
	if _count_fx.has(id):
		var ck: float = clampf((_time - float(_count_fx[id]["t0"])) / COUNT_FX, 0.0, 1.0)
		fs = int(round(float(fs) * (1.0 + 0.4 * sin(PI * minf(ck * 1.8, 1.0)) * (1.0 - ck))))
		var flash: Color = Color(1.0, 0.82, 0.35) if bool(_count_fx[id]["up"]) else Color(1.0, 0.42, 0.34)
		num_col = flash.lerp(num_col, smoothstep(0.35, 1.0, ck))
	var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
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
		## v2.0.1: clear of the other lands' names (crown_rect)
		var crect: Rect2 = crown_rect(id)
		drawn_crowns[id] = crect
		## where no spot clears (the Ring's middle, seven lands packed close: Goldmarch's name sits on
		## the Throne's brow), the name it touches is written again over it
		for i in _names_now.size():
			var other: String = str(art.order[i])
			if other != id and (_names_now[i] as Rect2).intersects(crect) and not names_over.has(other):
				names_over.append(other)
				_late.append(_draw_name.bind(other, token_radius()))
		var cr: float = crect.size.y * 0.5
		var cp: Vector2 = crect.get_center()
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
		## v1.14: on a dark plate above the token, or under its name when a fate mark sits there
		## (an arrow ends at the token's edge, so last round's cross used to land on the words)
		var cw: float = f.get_string_size("CUT OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var cc: Vector2 = p + Vector2(0, -r - 14)
		var clear_of: float = cw * 0.5 + fate_mark_size() + 8.0
		for spot in _fate_spots:
			if absf((spot as Vector2).x - cc.x) < clear_of and absf((spot as Vector2).y - cc.y) < fate_mark_size() + 14.0:
				cc = p + Vector2(0, r + ns + 15)
				break
		drawn_cut[id] = cc
		ci.draw_rect(Rect2(cc - Vector2(cw * 0.5 + 4, 8), Vector2(cw + 8, 15)), Color(0.08, 0.03, 0.02, 0.82))
		var cpp: Vector2 = cc + Vector2(-cw * 0.5, 4)
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
