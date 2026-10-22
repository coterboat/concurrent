## v2.4 (v24-3d): the ground under a fort made level (Terrain.level). A battle at a fort is fought at
## its walls now (land_field.gd), and seated on a slope (at the lowest of its ground) a fort stood half
## buried: 36 of fall under Redgate's ramparts, which are 10 high. Display only (no rules change).
## The rest of v24-3d (the swoop, the streaks, the fight at the walls) is the v24p probe's: those
## scripts name the Audio autoload, which the full runner can't preload.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapArt := preload("res://game/board/map_art.gd")
const Terrain := preload("res://game/world3d/terrain.gd")
const Scenery := preload("res://game/world3d/scenery.gd")


func run(report: Callable, _tree: SceneTree) -> void:
	for mid in ["marches18", "isles24", "ring26"]:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		var art = MapArt.load_for(mid)
		var t = Terrain.build(art, map, 3)
		var plan: Array = Scenery.plan(art, map, t)
		var before: PackedFloat32Array = t.heights.duplicate()
		var forts: Array = plan.filter(func(s): return str(s["kind"]) == "starfort")
		report.call(not forts.is_empty(), "%s: its forts have their places (%d)" % [mid, forts.size()])
		var levelled := 0
		var stands := 0
		var falls: Array = []
		for s in forts:
			var r: float = float(s["foot"]) * 0.5
			var was: float = _fall(t, s["at"], r)
			var h: float = t.level(art, str(s["land"]), s["at"], r)
			var now: float = _fall(t, s["at"], r)
			falls.append("%s %.1f→%.1f" % [s["land"], was, now])
			if now < 1.0:
				levelled += 1
			if absf(t.height_at(s["at"]) - h) < 0.5:
				stands += 1
		report.call(levelled == forts.size(), "%s: the ground under every fort is level, but the shore it stands over (%s)" % [mid, ", ".join(falls)])
		report.call(stands == forts.size(), "%s: and each stands at the height it was levelled to" % mid)
		## only round the forts, and never the shore
		var far := 0
		var wet := 0
		for k in before.size():
			if before[k] == t.heights[k]:
				continue
			var p := Vector2((k % t.w + 0.5) * t.cell.x, (k / t.w + 0.5) * t.cell.y)
			var near := false
			for s in forts:
				if p.distance_to(s["at"]) <= float(s["foot"]) * 0.5 * 1.3 + 0.01:
					near = true
			if not near:
				far += 1
			if t.coast_px[k] < 4.0:
				wet += 1
		report.call(far == 0 and wet == 0, "%s: no ground is touched but round the forts (%d), none of the shore (%d)" % [mid, far, wet])
		## the land's highest and lowest are the levelled land's (the battle camera's sight test leans on its highest)
		var lo := 1.0e9
		var hi := -1.0e9
		for v in t.heights:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		var px_ok := true
		for s in forts:
			var c := Vector2i(clampi(int((s["at"] as Vector2).x / t.cell.x), 0, t.w - 1), clampi(int((s["at"] as Vector2).y / t.cell.y), 0, t.h - 1))
			px_ok = px_ok and is_equal_approx(t.height_image.get_pixel(c.x, c.y).r, t.heights[c.y * t.w + c.x])
		report.call(is_equal_approx(hi, t.hi) and is_equal_approx(lo, t.lo) and px_ok,
			"%s: the land's height map and its highest and lowest are the levelled ground's" % mid)


static func _fall(t: RefCounted, at: Vector2, r: float) -> float:
	## how far the ground falls under a fort's walls (its middle, and two rings of eight), but where
	## it stands over the shore (that is left as it was: Terrain.level eases off within 16 of it)
	var lo := 1.0e9
	var hi := -1.0e9
	for j in 17:
		var q: Vector2 = at if j == 16 else at + Vector2(cos(float(j) * TAU / 16.0), sin(float(j) * TAU / 16.0)) * r * (0.45 if j % 2 == 0 else 0.85)
		if t.coast_at(q) < 16.0:
			continue
		lo = minf(lo, t.height_at(q))
		hi = maxf(hi, t.height_at(q))
	return maxf(hi - lo, 0.0)
