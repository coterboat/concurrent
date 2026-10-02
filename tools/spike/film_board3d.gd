## A film of the board over the land: today's board, the land rising under it, the tilt, the
## garrisons, then a pan and a zoom while tilted (the board's own UI riding the land).
##   $G --path . --fixed-fps 30 --write-movie out.avi res://tools/probe.tscn -- --script=res://tools/spike/film_board3d.gd
extends RefCounted

const Spike := preload("res://tools/spike/board3d.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	var s = Spike.new()
	s.map_id = OS.get_environment("MAP") if OS.get_environment("MAP") != "" else "known24"
	p.get_tree().root.add_child(s)
	await p.frames(2)
	s.build()
	await p.frames(60)
	for m in [1, 2, 3]:
		s.set_mode(m)
		await p.frames(110)
	var b: Control = s.board
	## a slow pan across the map and a zoom in, tilted, with the garrisons standing
	for i in 150:
		b.offset += Vector2(-2.2, -0.8)
		b._apply_view()
		await p.frames(1)
	for i in 70:
		b.zoom_at(b.size * 0.5, 1.008)
		await p.frames(1)
	await p.frames(60)
	s.set_mode(0)
	await p.frames(90)
	p.log("film done")
