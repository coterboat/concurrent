## The diorama spike, photographed at its moments, with the facts it must keep:
## every column stands in the land it attacks, on dry ground, nearer its own border than any
## other's; the board and the 3D world agree at the handoff.
##   SHOT_DIR=/dir MAPS=known24,world30 ./scripts/shot.sh diorama
extends RefCounted

const Spike := preload("res://tools/spike/diorama_spike.gd")

var p
var _prefix := ""


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	var maps: PackedStringArray = OS.get_environment("MAPS").split(",") if OS.get_environment("MAPS") != "" else PackedStringArray(["known24"])
	if OS.get_environment("GALLERY") != "":
		for mid in maps:
			var g = Spike.new()
			g.map_id = mid
			_prefix = mid + "_"
			p.get_tree().root.add_child(g)
			await p.frames(2)
			await g.gallery(func(name): await _shot(name, g))
			g.queue_free()
			await p.frames(3)
		return
	for mid in maps:
		var s = Spike.new()
		s.map_id = mid
		s.land = OS.get_environment("LAND")
		_prefix = mid + "_"
		s._snap = _shot.bind(s)
		p.get_tree().root.add_child(s)
		await p.frames(2)
		await s.play()
		_facts(s)
		s.queue_free()
		await p.frames(3)


func _shot(name: String, s) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + _prefix + name + ".png")
	p.log("shot " + _prefix + name)
	if name == "03_handoff_3d_under":
		## the 3D world, framed as the board is: the board's centre is the camera's
		var c: Vector2 = s.board.screen_to_map(s.vp_size() * 0.5)
		var on: Vector2 = s.wv.cam.unproject_position(Vector3(c.x, 0.0, c.y))
		p.ok(on.distance_to(s.vp_size() * 0.5) < 2.0, "handoff: the board's centre is the 3D camera's centre (%.1f px off)" % on.distance_to(s.vp_size() * 0.5))
		var a: Vector2 = s.board.art.anchors[s.land]
		var on2: Vector2 = s.wv.cam.unproject_position(Vector3(a.x, 0.0, a.y))
		p.ok(on2.distance_to(s.board.anchor(s.land)) < 3.0, "handoff: %s's token is where the 3D world has it (%.1f px off)" % [s.land, on2.distance_to(s.board.anchor(s.land))])


func _facts(s) -> void:
	var art = s.board.art
	var land: String = s.land
	var ti: int = int(art.index[land])
	var dry := true
	var wrong_land := 0
	for f in s.dio.figs:
		var at: Vector2 = f["home"]
		if s.wv.terrain.height_at(at) < 0.5:
			dry = false
	## the fronts are every army but the last (the defender, a group facing each front)
	var fronts: Array = s.dio.armies.slice(0, s.dio.armies.size() - 1)
	for a in fronts:
		var g: Dictionary = a["groups"][0]
		var c: Vector2 = g["at"]
		if art.territory_at(c) != land:
			wrong_land += 1
		var mine: float = c.distance_to(g["cross"])
		for b in fronts:
			if b != a:
				var gb: Dictionary = b["groups"][0]
				p.ok(mine < c.distance_to(gb["cross"]), "%s's column stands nearer its own border (%.0f) than %s's (%.0f)" % [a["pid"], mine, b["pid"], c.distance_to(gb["cross"])])
	p.ok(wrong_land == 0, "every column stands inside %s (%d outside)" % [land, wrong_land])
	p.ok(dry, "no figure stands in the sea")
	for f in s.spec["fronts"]:
		var x: Vector2 = s.dio.crossing(land, f["from"])
		p.ok(art.territory_at(x) == land, "%s's crossing from %s is on %s's side of the border" % [f["pid"], f["from"], land])
	var vis := 0
	for i in s.dio.armies.size():
		var sp: Vector2 = s.wv.cam.unproject_position(s.dio.centre_of(i) - Vector3(0, s.dio.FIG * 2.3, 0))
		if Rect2(Vector2.ZERO, s.vp_size()).has_point(sp):
			vis += 1
	p.ok(vis == s.dio.armies.size(), "every army is on screen when the camera settles (%d of %d)" % [vis, s.dio.armies.size()])
