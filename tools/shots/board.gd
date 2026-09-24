## Render the board alone on each map with a dealt world and a few arrows.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Board := preload("res://game/board/map_board.gd")

func run(p) -> void:
	p.get_window().size = Vector2i(1600, 1000)
	var maps: PackedStringArray = OS.get_environment("MAPS").split(",") if OS.get_environment("MAPS") != "" else PackedStringArray(["knife7", "known24", "world30"])
	for mid in maps:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		var seats := [{"id": "red", "name": "Dad"}, {"id": "blue", "name": "B"}, {"id": "green", "name": "C"}, {"id": "gold", "name": "D"}]
		if mid == "knife7":
			seats = seats.slice(0, 2)
		var w: Types.World = Setup.deal(map, seats, 7)
		for id in w.territories.keys():
			var ts = w.territories[id]
			if ts.owner != "":
				ts.armies = 1 + (hash(id) % 9)
				if hash(id) % 3 == 0:
					ts.garrison = 2
		var b: Control = Board.new()
		b.size = Vector2(1600, 1000)
		p.get_tree().root.add_child(b)
		b.load_map(map)
		b.world = w
		b.viewer = "red"
		b.show_ceiling = true
		var mine := MapLib.player_territory_ids(w, "red")
		b.selected = mine[0]
		for n in MapLib.neighbors(map, mine[0]):
			b.targets[n] = true
		b.placements[mine[0]] = 2
		var t: String = MapLib.neighbors(map, mine[0])[0]
		b.orders = [{"from": mine[0], "to": t, "strength": 5, "owner": "red", "kind": "attack"}]
		var bl := MapLib.player_territory_ids(w, "blue")
		b.ghosts = [{"from": bl[0], "to": MapLib.neighbors(map, bl[0])[0], "strength": 3, "owner": "blue"}]
		b.refresh()
		await p.frames(4)
		await _snap(p, "board_" + mid)
		if mid == "world30":
			b.zoom_at(b.anchor(mine[0]), 2.2)
			await p.frames(3)
			await _snap(p, "board_" + mid + "_zoom")
		b.queue_free()
		await p.frames(2)

func _snap(p, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
