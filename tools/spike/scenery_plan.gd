## Headless: every map's scenery plan (scenery.gd) drawn over its relief: villages green, landmarks
## gold, quays blue, bridges white, ships navy; each land's stage a faint ring, its crossings red.
##   $G --headless --path . --script res://tools/spike/scenery_plan.gd -- out=/some/dir maps=known24,knife7
extends SceneTree

const Types := preload("res://engine/types.gd")
const MapArt := preload("res://game/board/map_art.gd")
const Terrain := preload("res://game/world3d/terrain.gd")
const Scenery := preload("res://game/world3d/scenery.gd")

const ROLE := {"village": Color(0.2, 0.75, 0.25), "landmark": Color(1.0, 0.8, 0.2), "port": Color(0.3, 0.6, 1.0),
	"bridge": Color(1, 1, 1), "ship": Color(0.1, 0.15, 0.4), "lane": Color(0.1, 0.15, 0.4)}


func _initialize() -> void:
	var out := "/tmp"
	var maps := ["known24", "world30", "isles24", "ring26", "marches18", "knife7"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.trim_prefix("out=")
		elif a.begins_with("maps="):
			maps = Array(a.trim_prefix("maps=").split(","))
	for mid in maps:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		var art = MapArt.load_for(mid)
		var t = Terrain.build(art, map, 3)
		var t0 := Time.get_ticks_msec()
		var plan: Array = Scenery.plan(art, map, t)
		var ms := Time.get_ticks_msec() - t0
		var counts := {}
		for s in plan:
			counts[s["role"]] = int(counts.get(s["role"], 0)) + 1
		var kinds := {}
		for s in plan:
			if s["role"] == "landmark":
				kinds[s["land"]] = s["kind"]
		print("PLAN %s %d ms %s landmarks %s" % [mid, ms, counts, kinds])
		var img := Image.create(t.w, t.h, false, Image.FORMAT_RGB8)
		for y in t.h:
			for x in t.w:
				var hv: float = t.heights[y * t.w + x]
				var c := Color(0.12, 0.2, 0.32) if hv < 0.0 else Color(0.5, 0.52, 0.4).lerp(Color(0.95, 0.93, 0.9), clampf(hv / 140.0, 0.0, 1.0))
				img.set_pixel(x, y, c)
		for id in art.order:
			_ring(img, t, art.anchors[id], float(art.depth.get(id, 60.0)) * 0.55, Color(0.3, 0.3, 0.3))
		for k in t.crossings.keys():
			_disc(img, t, t.crossings[k], 5.0, Color(0.85, 0.1, 0.1))
		for s in plan:
			_disc(img, t, s["at"], float(s["foot"]) * 0.5, ROLE.get(s["role"], Color.MAGENTA))
		img.save_png("%s/plan_%s.png" % [out, mid])
	quit()


func _disc(img: Image, t, p: Vector2, r: float, c: Color) -> void:
	var cx: float = p.x / t.cell.x
	var cy: float = p.y / t.cell.y
	var rc: float = r / t.cell.x
	for y in range(int(cy - rc), int(cy + rc) + 1):
		for x in range(int(cx - rc), int(cx + rc) + 1):
			if x >= 0 and y >= 0 and x < t.w and y < t.h and Vector2(x - cx, y - cy).length() <= rc:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, 0.7))


func _ring(img: Image, t, p: Vector2, r: float, c: Color) -> void:
	var cx: float = p.x / t.cell.x
	var cy: float = p.y / t.cell.y
	var rc: float = r / t.cell.x
	for k in 90:
		var a := float(k) * TAU / 90.0
		var x := int(cx + cos(a) * rc)
		var y := int(cy + sin(a) * rc)
		if x >= 0 and y >= 0 and x < t.w and y < t.h:
			img.set_pixel(x, y, c)
