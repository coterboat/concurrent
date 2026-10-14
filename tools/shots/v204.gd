## v2.0.2, round two: the look of the land. The same views every time (the board at the fit, and
## close over a village, the mountains and the south), so a change to the land's look is seen
## against the last. The facts: every building stands on its own shadow; the countryside has its
## woods and scattered trees, none on a land's battlefield; the light gives the relief its shade.
##   SHOT_DIR=/dir ./scripts/shot.sh v204
extends RefCounted

const Types := preload("res://engine/types.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["battles"] = "off"
	Settings.data["battle_land"] = true
	Settings.data["map_land"] = true
	await _views("known24", [["cairn", 3.0], ["peak", 2.6], ["oasis", 2.6], ["vale", 1.7]])
	await _views("world30", [[], []])


func _game(map: String) -> Array:
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	var seats := [{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "human", "ai": "", "portrait": "varek"},
		{"id": "green", "name": "Viceroy Ysolde", "kind": "human", "ai": "", "portrait": "ysolde"}]
	main.start_game({"map": map, "seed": 41, "length": "standard", "timer": 0, "open_sheets": true, "seats": seats})
	await p.frames(5)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	for i in seats.size():
		s.auto_deploy()
		s.lock()
	await p.frames(5)
	gs.cinema.skip()
	var lb: Control = gs.land_board
	var guard := 0
	while not (lb.ready_to_show() and lb.settled()) and guard < 900:
		guard += 1
		await p.frames(1)
	await p.frames(60)
	return [main, s, gs]


func _views(mid: String, spots: Array) -> void:
	var r: Array = await _game("res://maps/%s.json" % mid)
	var main: Control = r[0]
	var gs: Control = r[2]
	var b: Control = gs.board
	var land: Node = gs.land
	_facts(mid, land)
	await snap("v204_%s_00_fit" % mid)
	var k := 1
	for spot in spots:
		var id: String = str(spot[0]) if spot.size() > 0 else str(b.art.order[(k * 7) % b.art.order.size()])
		var z: float = float(spot[1]) if spot.size() > 1 else 2.6
		b.swoop_to([id], z, 0.05)
		await p.frames(70)
		await snap("v204_%s_%02d_%s" % [mid, k, id])
		k += 1
	b.restore_view()
	main.queue_free()
	await p.frames(5)


func _facts(mid: String, land: Node) -> void:
	var sc: Node3D = land.scenery
	var built: Array = sc.pieces.filter(func(pc): return not (pc["role"] in ["ship", "lane"]) and pc["kind"] != "bridge")
	var grounded: int = built.filter(func(pc): return (pc["node"] as Node3D).has_meta("contact")).size()
	var coated := 0
	for pc in built:
		var mis: Array = (pc["node"] as Node).find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty() and (mis[0] as MeshInstance3D).material_override != null and ((mis[0] as MeshInstance3D).material_override as Material).next_pass != null:
			coated += 1
	p.ok(grounded == built.size(), "%s: every building stands on its own shadow (%d of %d)" % [mid, grounded, built.size()])
	p.ok(coated == built.size(), "%s: and sits in the land (its plate's lime toned down, its foot darkened: %d of %d)" % [mid, coated, built.size()])
	## the countryside: woods and copses, but none on a land's battlefield
	var art = land.wv.art
	var trees := 0
	var on_stage := 0
	for mmi in land.wv.props.get_children():
		if not (mmi is MultiMeshInstance3D):
			continue
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var o: Vector3 = mm.get_instance_transform(i).origin
			trees += 1
			for id in art.order:
				if Vector2(o.x, o.z).distance_to(art.anchors[id]) < float(art.depth.get(id, 60.0)) * 0.55 - 0.5:
					on_stage += 1
					break
	p.ok(trees == land.wv.props.count and on_stage == 0, "%s: %d trees and rocks on the land, none on any land's battlefield" % [mid, trees])


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
