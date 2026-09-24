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
	return true


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
