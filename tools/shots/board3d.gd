## The board over the land (tools/spike/board3d.gd), each of its four looks, with the facts that
## make the case: looking straight down, the board's own UI is exactly where the flat chart has it
## (not a pixel moved); tilted, every token still stands on its own land, and a click on it comes
## back to that land.
##   SHOT_DIR=/dir MAPS=known24,world30 ./scripts/shot.sh board3d
extends RefCounted

const Spike := preload("res://tools/spike/board3d.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	var maps: PackedStringArray = OS.get_environment("MAPS").split(",") if OS.get_environment("MAPS") != "" else PackedStringArray(["known24", "world30"])
	for mid in maps:
		var s = Spike.new()
		s.map_id = mid
		p.get_tree().root.add_child(s)
		await p.frames(2)
		s.build()
		await p.frames(4)
		for m in 4:
			s.set_mode(m, true)
			await p.frames(200 if m == 3 else 8)
			await _snap("%s_mode%d" % [mid, m + 1])
			var b: Control = s.board
			if m == 1:
				## straight down: the UI hasn't moved
				var worst := 0.0
				for id in b.art.order:
					var flat: Vector2 = b.offset + (b.art.anchors[id] as Vector2) * b.zoom
					worst = maxf(worst, flat.distance_to(b.anchor(id)))
				p.ok(worst < 1.5, "%s, the land under the chart: every token where the flat chart has it (worst %.2f px)" % [mid, worst])
			if m >= 2:
				var wrong := 0
				var off := 0.0
				for id in b.art.order:
					var sp: Vector2 = b.anchor(id)
					var back: Vector2 = b.screen_to_map(sp)
					off = maxf(off, back.distance_to(b.art.anchors[id]))
					if b.art.territory_at(back) != id:
						wrong += 1
				p.ok(wrong == 0, "%s, tilted: a click on every token comes back to its own land (%d wrong, worst %.1f map px)" % [mid, wrong, off])
		s.queue_free()
		await p.frames(3)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
