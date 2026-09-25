## Loads the mapgen output for one map: data texture, hit-test image, anchors, lanes.
## The data PNG is read raw (importer "keep") so the bytes stay exact in exports.
extends RefCounted

var id: String = ""
var size := Vector2(2400, 1500)
var order: PackedStringArray = PackedStringArray() ## texture index -> territory id
var index := {} ## territory id -> texture index
var anchors := {} ## territory id -> Vector2 (token spot)
var depth := {} ## territory id -> float (room around the anchor)
var lanes: Array = [] ## [{a, b, pa: Vector2, pb: Vector2}]
var regions := {} ## region id -> Vector2 (label spot)
var data_image: Image
var data_texture: ImageTexture
var ornaments: Array = [] ## [{kind: rose|ship|cartouche, pos, r}] chart decorations in open water


static func load_for(map_id: String) -> RefCounted:
	var art = load("res://game/board/map_art.gd").new()
	if not art._load(map_id):
		return null
	return art


func _load(map_id: String) -> bool:
	id = map_id
	var meta_text := FileAccess.get_file_as_string("res://maps/art/%s_art.json" % map_id)
	var meta: Variant = JSON.parse_string(meta_text)
	if typeof(meta) != TYPE_DICTIONARY:
		push_error("map art meta missing for %s" % map_id)
		return false
	size = Vector2(float(meta["width"]), float(meta["height"]))
	order = PackedStringArray(meta["order"])
	for i in order.size():
		index[order[i]] = i
	for t in meta["anchors"].keys():
		var a: Dictionary = meta["anchors"][t]
		anchors[t] = Vector2(float(a["x"]), float(a["y"]))
		depth[t] = float(a.get("depth", 40.0))
	for l in meta["lanes"]:
		lanes.append({
			"a": str(l["a"]), "b": str(l["b"]),
			"pa": Vector2(float(l["ax"]), float(l["ay"])),
			"pb": Vector2(float(l["bx"]), float(l["by"])),
		})
	for r in meta.get("regions", {}).keys():
		var p: Dictionary = meta["regions"][r]
		regions[r] = Vector2(float(p["x"]), float(p["y"]))
	var bytes := FileAccess.get_file_as_bytes("res://maps/art/%s_data.png" % map_id)
	data_image = Image.new()
	if bytes.is_empty() or data_image.load_png_from_buffer(bytes) != OK:
		push_error("map data texture missing for %s" % map_id)
		return false
	data_texture = ImageTexture.create_from_image(data_image)
	_place_ornaments()
	return true


func _deep(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= data_image.get_width() or y >= data_image.get_height():
		return false
	var c: Color = data_image.get_pixel(x, y)
	return (c.g * 255.0 - 128.0) / 3.0 <= -30.0


func _clear(p: Vector2, r: float) -> bool:
	## open water all round p, and clear of the dashed sea lanes
	for k in 16:
		var q: Vector2 = p + Vector2.from_angle(TAU * k / 16.0) * r
		if not _deep(int(q.x), int(q.y)):
			return false
	if not _deep(int(p.x), int(p.y)):
		return false
	for l in lanes:
		var c: Vector2 = Geometry2D.get_closest_point_to_segment(p, l["pa"], l["pb"])
		if c.distance_to(p) < r * 0.8:
			return false
	return true


func _place_ornaments() -> void:
	## An admiral's chart: a compass rose, the map's title plate, a few ships of the line.
	## Placed deterministically in the widest open water, never over land or sea lanes.
	var w: int = data_image.get_width()
	var h: int = data_image.get_height()
	var step := 28
	var cands: Array = []
	for y in range(step, h - step, step):
		for x in range(step, w - step, step):
			if _deep(x, y):
				cands.append(Vector2(x, y))
	var want := [["cartouche", 150.0], ["rose", 120.0], ["ship", 70.0], ["ship", 70.0], ["ship", 70.0]]
	for kv in want:
		var kind: String = kv[0]
		var r: float = kv[1]
		var best := Vector2(-1, -1)
		var best_s := -1.0e9
		for p in cands:
			if not _clear(p, r):
				continue
			var ok := true
			var near := 1.0e9
			for o in ornaments:
				var d: float = p.distance_to(o["pos"])
				near = minf(near, d)
				if d < float(o["r"]) + r + 60.0:
					ok = false
					break
			if not ok:
				continue
			## prefer: the title plate high on the chart, the rose low, ships spread out
			var sc: float = minf(near, 900.0)
			match kind:
				"cartouche":
					sc = -p.y + 0.15 * absf(p.x - w * 0.5)
				"rose":
					sc = p.y * 0.8 + minf(near, 900.0) * 0.5
			if sc > best_s:
				best_s = sc
				best = p
		if best.x >= 0.0:
			ornaments.append({"kind": kind, "pos": best, "r": r, "flip": (int(best.x) / step) % 2 == 0})


func territory_at(p: Vector2) -> String:
	## Map-pixel hit test. A few pixels of sea around a coast still count, so
	## small islands are easy to click.
	var x := int(p.x)
	var y := int(p.y)
	if x < 0 or y < 0 or x >= data_image.get_width() or y >= data_image.get_height():
		return ""
	var c: Color = data_image.get_pixel(x, y)
	var coast: float = (c.g * 255.0 - 128.0) / 3.0
	if coast < -10.0:
		return ""
	var i := int(round(c.r * 255.0))
	if i < 0 or i >= order.size():
		return ""
	return order[i]
