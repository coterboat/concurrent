## Status board. Counts from the couch. Patterns, not color alone.
extends Control

const Types := preload("res://engine/types.gd")
const Income := preload("res://engine/income.gd")
const Palette := preload("res://game/palette.gd")

signal hex_clicked(terr_id: String, button_index: int)

var map: Types.MapDef
var world: Types.World
var viewer: String = "red"
var selected: String = ""
var highlights: PackedStringArray = PackedStringArray()
var ghosts: Array = []
var emphasize_links := false
var polys := {}
var centers := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _layout_from_map() -> void:
	centers = {}
	polys = {}
	if map == null:
		return
	if map.layout.size() > 0:
		for terr_id in map.layout.keys():
			centers[str(terr_id)] = map.layout[terr_id]
	else:
		centers = {
			"beacon": Vector2(170, 130),
			"ridge": Vector2(400, 120),
			"mill": Vector2(640, 130),
			"gate": Vector2(400, 330),
			"harbor": Vector2(180, 500),
			"docks": Vector2(400, 660),
			"quarry": Vector2(630, 500),
		}
	var n: int = centers.size()
	var base_r: float = 92.0 if n <= 8 else 48.0
	for id in centers.keys():
		var r: float = base_r + 16.0 if id == "gate" or id == "strait" else base_r
		polys[id] = _blob(centers[id], r, id)


func set_state(p_map: Types.MapDef, p_world: Types.World, p_viewer: String, p_selected: String, p_ghosts: Array, p_hi: PackedStringArray, p_emphasize_links: bool = false) -> void:
	map = p_map
	world = p_world
	viewer = p_viewer
	selected = p_selected
	ghosts = p_ghosts
	highlights = p_hi
	emphasize_links = p_emphasize_links
	_layout_from_map()
	queue_redraw()


func _blob(c: Vector2, r: float, id: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 8
	for i in n:
		var a: float = TAU * float(i) / float(n) - PI * 0.5
		var j: float = 1.0 + 0.08 * sin(float(id.length() + i) * 1.7)
		var stretch := Vector2(1.2, 0.92)
		if id == "gate":
			stretch = Vector2(1.05, 1.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * j * stretch)
	return pts


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return
		var local: Vector2 = event.position
		for id in polys.keys():
			if Geometry2D.is_point_in_polygon(local, polys[id]):
				hex_clicked.emit(id, event.button_index)
				accept_event()
				return


func _draw() -> void:
	if world == null or map == null:
		return
	_draw_links()
	var ids: Array = centers.keys()
	ids.sort()
	for id in ids:
		_draw_hex(str(id))
	_draw_ghosts()


func _draw_links() -> void:
	var col := Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, 0.55 if emphasize_links else 0.22)
	var width := 4.0 if emphasize_links else 2.0
	var seen := {}
	for id in centers.keys():
		var t = map.get_territory(id)
		if t == null:
			continue
		for n in t.adjacent:
			var nid := str(n)
			var key: String = id + "|" + nid if id < nid else nid + "|" + id
			if seen.has(key):
				continue
			seen[key] = true
			if not centers.has(nid):
				continue
			draw_line(centers[id], centers[nid], col, width, true)


func _draw_hex(id: String) -> void:
	var poly: PackedVector2Array = polys[id]
	var ts: Types.TerritoryState = world.get_territory(id)
	var t: Types.TerritoryDef = map.get_territory(id)
	var owner: String = ts.owner if ts else ""
	var fill: Color = Palette.owner_fill(owner)
	if owner != Types.UNOCCUPIED:
		fill.a = 0.82
	if t != null and t.region != "":
		var wash: Color = Palette.region_fill(t.region)
		wash.a = 0.22
		draw_colored_polygon(poly, wash)
	draw_colored_polygon(poly, fill)
	_draw_pattern(poly, Palette.pattern(owner))
	var outline: Color = Palette.CREAM
	var width := 2.0
	if id == selected:
		outline = Color(1, 0.95, 0.6)
		width = 4.0
	if highlights.has(id):
		outline = Color(1, 1, 1)
		width = 5.0
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, outline, width, true)
	var name: String = t.display_name if t else id
	var c: Vector2 = centers[id]
	var font := ThemeDB.fallback_font
	var small: bool = centers.size() > 8
	var name_size: int = 13 if small else 16
	var count_size: int = 26 if small else 40
	var name_w: float = 88.0 if small else 108.0
	draw_string(font, c + Vector2(-name_w * 0.5, -14 if small else -18), name, HORIZONTAL_ALIGNMENT_CENTER, name_w, name_size, Palette.CREAM)
	var count: String = str(ts.armies)
	draw_string(font, c + Vector2(-36, 16 if small else 22), count, HORIZONTAL_ALIGNMENT_CENTER, 72, count_size, Palette.CREAM)
	var extra := ""
	var dug: int = ts.garrison if ts else 0
	if dug > 0:
		extra = "dug %s" % dug
	elif owner == viewer:
		extra = "cap %s" % Income.cap_of(world, map, id)
	elif owner != Types.UNOCCUPIED:
		var cap: int = Income.cap_of(world, map, id)
		extra = "max %s" % (ts.armies + cap)
	if extra != "":
		draw_string(font, c + Vector2(-50, 32 if small else 42), extra, HORIZONTAL_ALIGNMENT_CENTER, 100, 12 if small else 14, Palette.MUTED)


func _draw_pattern(poly: PackedVector2Array, kind: String) -> void:
	if kind == "none":
		return
	var rect := Rect2()
	for p in poly:
		if rect.size == Vector2.ZERO and rect.position == Vector2.ZERO:
			rect.position = p
			rect.size = Vector2.ZERO
		else:
			rect = rect.expand(p)
	var ink := Color(0, 0, 0, 0.28)
	match kind:
		"hatch":
			var x: float = rect.position.x - 20.0
			while x < rect.position.x + rect.size.x + 40.0:
				_line_in_poly(poly, Vector2(x, rect.position.y - 10), Vector2(x + rect.size.y + 20, rect.position.y + rect.size.y + 10), ink)
				x += 9.0
		"dots":
			var y: float = rect.position.y
			while y < rect.position.y + rect.size.y:
				var x2: float = rect.position.x + int(y / 12.0) % 2 * 6.0
				while x2 < rect.position.x + rect.size.x:
					if Geometry2D.is_point_in_polygon(Vector2(x2, y), poly):
						draw_circle(Vector2(x2, y), 1.8, ink)
					x2 += 12.0
				y += 12.0
		"stripes":
			var y2: float = rect.position.y
			while y2 < rect.position.y + rect.size.y:
				_line_in_poly(poly, Vector2(rect.position.x, y2), Vector2(rect.position.x + rect.size.x, y2), ink)
				y2 += 8.0
		"cross":
			var x3: float = rect.position.x
			while x3 < rect.position.x + rect.size.x:
				_line_in_poly(poly, Vector2(x3, rect.position.y), Vector2(x3, rect.position.y + rect.size.y), ink)
				x3 += 10.0


func _line_in_poly(poly: PackedVector2Array, a: Vector2, b: Vector2, color: Color) -> void:
	var steps := 16
	var last: Vector2 = a
	var last_in := Geometry2D.is_point_in_polygon(a, poly)
	for i in range(1, steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		var inside := Geometry2D.is_point_in_polygon(p, poly)
		if last_in and inside:
			draw_line(last, p, color, 1.5)
		last = p
		last_in = inside


func _draw_ghosts() -> void:
	for g in ghosts:
		var a_id: String = str(g.get("from", ""))
		var b_id: String = str(g.get("to", ""))
		if not centers.has(a_id) or not centers.has(b_id):
			continue
		var col: Color = Palette.owner_fill(str(g.get("owner", "")))
		col.a = 0.3
		draw_line(centers[a_id], centers[b_id], col, 6.0, true)
		var mid: Vector2 = centers[a_id].lerp(centers[b_id], 0.7)
		draw_circle(mid, 5.0, col)
		var surge: String = str(g.get("surgeTo", ""))
		if surge != "" and centers.has(surge):
			var sc: Color = col
			sc.a = 0.2
			draw_dashed_line(centers[b_id], centers[surge], sc, 3.0, 8.0)
