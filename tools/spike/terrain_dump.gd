## Headless: build every map's terrain, time it, and save a shaded relief of each.
##   $G --headless --path . --script res://tools/spike/terrain_dump.gd -- out=/some/dir maps=known24,world30 step=3
extends SceneTree

const Types := preload("res://engine/types.gd")
const MapArt := preload("res://game/board/map_art.gd")
const Terrain := preload("res://game/world3d/terrain.gd")


func _initialize() -> void:
	var out := "/tmp"
	var maps := ["known24", "world30", "isles24", "ring26", "marches18", "knife7"]
	var st := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.trim_prefix("out=")
		elif a.begins_with("maps="):
			maps = Array(a.trim_prefix("maps=").split(","))
		elif a.begins_with("step="):
			st = int(a.trim_prefix("step="))
	for mid in maps:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		var art = MapArt.load_for(mid)
		var t = Terrain.build(art, map, st)
		print("TERRAIN %s %dx%d step=%d %d ms  low=%.1f high=%.1f" % [mid, t.w, t.h, st, t.millis, t.lo, t.hi])
		_shade(t).save_png("%s/relief_%s.png" % [out, mid])
	quit()


func _shade(t) -> Image:
	var img := Image.create(t.w, t.h, false, Image.FORMAT_RGB8)
	var sun := Vector3(-0.55, 0.75, -0.4).normalized()
	for y in t.h:
		for x in t.w:
			var p := Vector2((x + 0.5) * t.step, (y + 0.5) * t.step)
			var hv: float = t.heights[y * t.w + x]
			var nrm: Vector3 = t.normal_at(p)
			var lit: float = clampf(nrm.dot(sun), 0.0, 1.0) * 0.85 + 0.25
			var c: Color
			if hv < 0.0:
				c = Color(0.1, 0.25, 0.35).lerp(Color(0.03, 0.08, 0.14), clampf(-hv / 40.0, 0.0, 1.0))
			else:
				c = t.ground_image.get_pixel(x, y)
				var g: float = t.ground_image.get_pixel(x, y).a
				c = c.lerp(Color(0.16, 0.26, 0.12), g * 0.6)
				if hv > 95.0:
					c = c.lerp(Color(0.95, 0.96, 1.0), smoothstep(95.0, 125.0, hv))
				c = Color(c.r * lit, c.g * lit, c.b * lit)
			img.set_pixel(x, y, c)
	return img
