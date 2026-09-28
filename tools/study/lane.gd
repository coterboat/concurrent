## Map tool (v1.12): the closest coast points of two lands, and (with draw=1) a dotted sea lane
## painted onto the map's preview in the style of the others.
##   $G --headless --path . --script res://tools/study/lane.gd -- map=isles24 a=vaneholt b=kestrelport [draw=1]
extends SceneTree


func _initialize() -> void:
	var args := {"map": "isles24", "a": "vaneholt", "b": "kestrelport", "draw": "0"}
	for s in OS.get_cmdline_user_args():
		var kv: PackedStringArray = str(s).split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/art/%s_art.json" % args["map"]))
	var order: Array = meta["order"]
	var ia: int = order.find(args["a"])
	var ib: int = order.find(args["b"])
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes("res://maps/art/%s_data.png" % args["map"]))
	var pa: Array = []
	var pb: Array = []
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c: Color = img.get_pixel(x, y)
			var coast: float = (c.g * 255.0 - 128.0) / 3.0
			if coast < 0.0 or coast > 3.0:
				continue
			var i := int(round(c.r * 255.0))
			if i == ia:
				pa.append(Vector2(x, y))
			elif i == ib:
				pb.append(Vector2(x, y))
	var best := 1.0e9
	var A := Vector2.ZERO
	var B := Vector2.ZERO
	for p in pa:
		for q in pb:
			var d: float = p.distance_squared_to(q)
			if d < best:
				best = d
				A = p
				B = q
	print("lane %s (%d, %d) -> %s (%d, %d), length %d" % [args["a"], A.x, A.y, args["b"], B.x, B.y, int(sqrt(best))])
	if args["draw"] == "1":
		var path := "res://maps/art/%s_preview.png" % args["map"]
		var pv := Image.new()
		pv.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		var col := Color(0.95, 0.9, 0.78)
		var d: Vector2 = B - A
		var n := int(d.length() / 11.0)
		for k in n + 1:
			var c: Vector2 = A + d * (float(k) / float(maxi(1, n)))
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var r := sqrt(float(dx * dx + dy * dy))
					if r > 2.6:
						continue
					var px := int(c.x) + dx
					var py := int(c.y) + dy
					var a: float = clampf(2.6 - r, 0.0, 1.0)
					pv.set_pixel(px, py, pv.get_pixel(px, py).lerp(col, a))
		pv.save_png(ProjectSettings.globalize_path(path))
		print("drew it on %s" % path)
	quit(0)
