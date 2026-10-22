## v2.4: a token drawn in meshes (map_board.gd _draw_token). Its body (its shadow on the land, its
## thickness, its rim, its face in its commander's colours and its edge, the lacquer's sheen and shine)
## is one mesh; so is the garrison's shield, and the amber ring of a land that holds the road home. Drawn
## shape by shape a token was fifteen polygons on the land, each a GPU buffer made afresh for every one
## of thirty tokens every frame: the board's heaviest drawing, through every swoop and every report
## (tools/study/swoop.gd). A mesh is made once for a look (shape, colours, edge, on the land or the
## chart) and a size (to the pixel under 20 pixels' radius, every two above; drawn at the size it is,
## within a few percent), and drawn wherever the token stands. body_shapes() is the old way, kept: the
## v24p probe holds the meshes to its picture.
extends RefCounted

const Style := preload("res://game/core/style.gd")

const SEGMENTS := 64 ## a circle's sides (as CanvasItem.draw_circle draws it)
const FEATHER := 1.25 ## an antialiased edge's fade across the line's edge, in pixels, centred on it (draw_polyline's, matched to its picture)
const DARK := Color(0.08, 0.06, 0.05)

var meshes := {} ## look and size -> ArrayMesh
var made := 0 ## (probes) meshes made
var drawn := 0 ## ...and drawn


static func bucket(r: float) -> float:
	## the size a mesh is made at: to the pixel below 20, every two pixels above (never under 4)
	return maxf(4.0, roundf(r)) if r < 20.0 else roundf(r / 2.0) * 2.0


func body(ci: CanvasItem, p: Vector2, r: float, shape: String, col: Color, edge: Color, edge_w: float, land: bool) -> void:
	## the token's body at p, r across its face (as body_shapes draws it)
	var b: float = bucket(r)
	var key := "body|%s|%s|%s|%s|%s|%s" % [shape, col.to_html(), edge.to_html(), edge_w, b, land]
	if not meshes.has(key):
		var g := Geo.new()
		if land:
			for k in 3:
				g.disc(Vector2(b * 0.15, b * 0.62), b * (1.25 - 0.18 * k), Color(0, 0, 0, 0.09), 0.42)
		g.disc(Vector2(2, 3), b + 1.0, Color(0, 0, 0, 0.35))
		if land:
			var thick := Vector2(0, maxf(3.0, b * 0.16))
			g.shape(shape, thick, b + 2.5, DARK, DARK, 1.0)
			g.shape(shape, thick, b, col.darkened(0.5), col.darkened(0.6), 1.0)
		g.shape(shape, Vector2.ZERO, b + 2.5, DARK, DARK, 1.0)
		g.shape(shape, Vector2.ZERO, b, col.darkened(0.08), edge, edge_w)
		g.shape(shape, Vector2(0, b * 0.12), b * 0.78, Color(0, 0, 0, 0.12), Color(0, 0, 0, 0), 0.0)
		g.disc(Vector2(-b * 0.3, -b * 0.34), b * 0.42, Color(1, 1, 1, 0.13))
		_keep(key, g)
	_draw(ci, key, p, r / b)


static func body_shapes(ci: CanvasItem, p: Vector2, r: float, shape: String, col: Color, edge: Color, edge_w: float, land: bool) -> void:
	## the old way, shape by shape (v2.0.2's token, as it was drawn until v2.4)
	if land:
		## v2.0, on the land: the token stands on its ground (a soft shadow on the land under it)
		ci.draw_set_transform(p + Vector2(r * 0.15, r * 0.62), 0.0, Vector2(1.0, 0.42))
		for k in 3:
			ci.draw_circle(Vector2.ZERO, r * (1.25 - 0.18 * k), Color(0, 0, 0, 0.09))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_circle(p + Vector2(2, 3), r + 1, Color(0, 0, 0, 0.35))
	if land:
		## v2.0.2, on the land: the piece has a thickness, its edge showing under the face
		var thick: Vector2 = Vector2(0, maxf(3.0, r * 0.16))
		Style.draw_shape(ci, shape, p + thick, r + 2.5, DARK, DARK, 1.0)
		Style.draw_shape(ci, shape, p + thick, r, col.darkened(0.5), col.darkened(0.6), 1.0)
	Style.draw_shape(ci, shape, p, r + 2.5, DARK, DARK, 1.0)
	Style.draw_shape(ci, shape, p, r, col.darkened(0.08), edge, edge_w)
	## lacquer sheen: a soft highlight up and to the left, a shade below
	Style.draw_shape(ci, shape, p + Vector2(0, r * 0.12), r * 0.78, Color(0, 0, 0, 0.12), Color(0, 0, 0, 0), 0.0)
	ci.draw_circle(p + Vector2(-r * 0.3, -r * 0.34), r * 0.42, Color(1, 1, 1, 0.13))


func shield(ci: CanvasItem, p: Vector2, r: float, fill: Color, edge: Color, edge_w: float, shadow: bool, glow: float = 0.0) -> void:
	## a garrison's shield at p, r across (its glow, its shadow, its face and edge)
	var b: float = bucket(r)
	var key := "shield|%s|%s|%s|%s|%s|%s" % [fill.to_html(), edge.to_html(), edge_w, shadow, glow, b]
	if not meshes.has(key):
		var g := Geo.new()
		if glow > 0.0:
			g.disc(Vector2(0, b * 0.12), b * 1.45, Color(1.0, 0.8, 0.35, glow * 0.8))
		if shadow:
			g.disc(Vector2(1.5, 2.5), b, Color(0, 0, 0, 0.35))
		g.shape("shield", Vector2.ZERO, b, fill, edge, edge_w)
		_keep(key, g)
	_draw(ci, key, p, r / b)


func ring(ci: CanvasItem, p: Vector2, r: float, col: Color, w: float, dashes: int) -> void:
	## a dashed ring at p, r round (the road home's amber ring: sixteen arcs, each its own polyline)
	var b: float = bucket(r)
	var key := "ring|%s|%s|%d|%s" % [col.to_html(), w, dashes, b]
	if not meshes.has(key):
		var g := Geo.new()
		for k in dashes:
			var arc := PackedVector2Array()
			for j in 4:
				var a: float = TAU * (float(k) + 0.55 * float(j) / 3.0) / float(dashes)
				arc.append(Vector2(cos(a), sin(a)) * b)
			g.line(arc, col, w)
		_keep(key, g)
	_draw(ci, key, p, r / b)


func _keep(key: String, g: Geo) -> void:
	meshes[key] = g.mesh()
	made += 1


func _draw(ci: CanvasItem, key: String, p: Vector2, s: float) -> void:
	drawn += 1
	ci.draw_mesh(meshes[key], null, Transform2D(0.0, Vector2(s, s), 0.0, p))


## a mesh's geometry, layer on layer in the order they were drawn (one draw blends them the same)
class Geo:
	static var _tris := {} ## shape -> its fill's triangles (the same at any size)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	static func fill_triangles(shape: String) -> PackedInt32Array:
		if not _tris.has(shape):
			_tris[shape] = Geometry2D.triangulate_polygon(Style.shape_points(shape, Vector2.ZERO, 1.0))
		return _tris[shape]

	func disc(c: Vector2, rad: float, col: Color, ys: float = 1.0) -> void:
		## a filled circle (draw_circle: not antialiased), squashed to ys of its height
		var o: int = pts.size()
		pts.append(c)
		cols.append(col)
		for i in SEGMENTS:
			var a: float = TAU * float(i) / float(SEGMENTS)
			pts.append(c + Vector2(cos(a) * rad, sin(a) * rad * ys))
			cols.append(col)
		for i in SEGMENTS:
			idx.append_array([o, o + 1 + i, o + 1 + (i + 1) % SEGMENTS])

	func shape(name: String, c: Vector2, rad: float, fill: Color, edge: Color, edge_w: float) -> void:
		## Style.draw_shape: the shape filled (not antialiased), its edge drawn round it (antialiased)
		var poly: PackedVector2Array = Style.shape_points(name, c, rad)
		var tris: PackedInt32Array = fill_triangles(name)
		if fill.a > 0.0:
			var o: int = pts.size()
			pts.append_array(poly)
			for i in poly.size():
				cols.append(fill)
			for t in tris:
				idx.append(o + t)
		if edge_w > 0.0 and edge.a > 0.0:
			outline(poly, edge, edge_w, true)

	func line(poly: PackedVector2Array, col: Color, w: float) -> void:
		outline(poly, col, w, false)

	func outline(poly: PackedVector2Array, col: Color, w: float, closed: bool) -> void:
		## a line w wide along poly, as draw_polyline draws it antialiased: solid in the middle, fading
		## to nothing over FEATHER across each edge; its joints mitred, three widths out at most; an open
		## line's ends faded too
		var n: int = poly.size()
		var clear := Color(col, 0.0)
		var core: float = maxf(w * 0.5 - FEATHER * 0.5, 0.0)
		var outer: float = w * 0.5 + FEATHER * 0.5
		var o: int = pts.size()
		for i in n:
			var cur: Vector2 = poly[i]
			var prev: Vector2 = poly[(i - 1 + n) % n] if closed or i > 0 else cur - (poly[1] - cur)
			var nxt: Vector2 = poly[(i + 1) % n] if closed or i < n - 1 else cur + (cur - poly[n - 2])
			var n0: Vector2 = (cur - prev).normalized().orthogonal()
			var n1: Vector2 = (nxt - cur).normalized().orthogonal()
			var nm: Vector2 = n0 + n1
			nm = nm.normalized() if nm.length() > 0.0001 else n1
			var k: float = 1.0 / maxf(nm.dot(n1), 1.0 / 3.0)
			for off in [-outer, -core, core, outer]:
				pts.append(cur + nm * float(off) * k)
			cols.append_array([clear, col, col, clear])
		for i in (n if closed else n - 1):
			var a: int = o + i * 4
			var b: int = o + ((i + 1) % n) * 4
			for s in 3:
				idx.append_array([a + s, b + s, b + s + 1, a + s, b + s + 1, a + s + 1])
		if closed:
			return
		for end in [0, n - 1]:
			## the fringe round an open end, out along the line
			var along: Vector2 = (poly[0] - poly[1]).normalized() if end == 0 else (poly[n - 1] - poly[n - 2]).normalized()
			var c0: int = o + end * 4
			var c1: int = pts.size()
			for j in 4:
				pts.append(pts[c0 + j] + along * FEATHER * 0.5)
				cols.append(clear)
			for s in 3:
				idx.append_array([c0 + s, c1 + s, c1 + s + 1, c0 + s, c1 + s + 1, c0 + s + 1])

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pts
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m
