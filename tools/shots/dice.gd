## v1.4 dice: a tray throw (every tier, both sides) and a drop onto the map.
extends RefCounted

const DiceStage := preload("res://game/ui/dice_stage.gd")
const Style := preload("res://game/core/style.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.get_tree().root.add_child(root)
	var bg := TextureRect.new()
	bg.texture = Style.tex("res://assets/battle/field_grass.webp")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var st: Control = DiceStage.new()
	st.position = Vector2(270, 470)
	st.size = Vector2(900, 340)
	st.ground_h = 170.0
	root.add_child(st)
	await p.frames(3)
	var specs: Array = []
	var sizes := [1, 4, 9, 20, 40]
	var red := Style.seat_color("red")
	var blue := Style.seat_color("blue")
	for i in 5:
		var x: float = -5.6 + i * 2.8
		specs.append({"value": i + 1, "n": sizes[i], "tint": red, "to": Vector2(x - 0.65, 0.0), "from": Vector3(-8.0, 2.2, 0.3), "delay": i * 0.04})
		specs.append({"value": 6 - i, "n": sizes[4 - i], "tint": blue, "to": Vector2(x + 0.65, 0.0), "from": Vector3(8.0, 2.2, -0.3), "delay": 0.05 + i * 0.04})
	## v1.5 physics: a hundred throws of ten dice, every one lands on its number
	var bad := 0
	var worst_ms := 0
	var longest := 0.0
	for k in 100:
		var t0 := Time.get_ticks_msec()
		var trial: Array = []
		for i in 10:
			trial.append({"value": 1 + (i + k) % 6, "n": [1, 4, 9, 20, 40][i % 5], "tint": red if i % 2 == 0 else blue,
				"to": Vector2(-5.6 + (i / 2) * 2.8 + (-0.72 if i % 2 == 0 else 0.72), -0.3), "from": Vector3(-8.0 if i % 2 == 0 else 8.0, 2.8, 0.2)})
		var dd: float = st.throw(trial)
		worst_ms = maxi(worst_ms, Time.get_ticks_msec() - t0)
		longest = maxf(longest, dd)
		for i in 10:
			if st.shown(i) != int(trial[i]["value"]):
				bad += 1
	p.ok(bad == 0, "physics dice: 1000 dice thrown, every one shows its roll (%d wrong); slowest simulation %d ms, longest throw %.2fs" % [bad, worst_ms, longest])
	var dur: float = st.throw(specs)
	p.log("throw lasts %.2fs, depth %.2f, %s" % [dur, st.depth(), str(st.sim_stats())])
	await p.get_tree().create_timer(0.3).timeout
	await snap("d1_tray_flight")
	await p.get_tree().create_timer(0.35).timeout
	await snap("d1b_tray_tumble")
	await p.get_tree().create_timer(dur).timeout
	await snap("d2_tray_rest")
	for i in 5:
		st.mark(i * 2, "win" if i % 2 == 0 else "lose")
		st.mark(i * 2 + 1, "lose" if i % 2 == 0 else "win")
	await p.get_tree().create_timer(0.6).timeout
	await snap("d3_tray_marked")
	## over the map: no tray, dice dropped from above
	var map_st: Control = DiceStage.new()
	map_st.board = false
	map_st.pitch = 68.0
	map_st.width = 16.0
	map_st.position = Vector2(0, 0)
	map_st.size = Vector2(1440, 900)
	root.add_child(map_st)
	st.visible = false
	await p.frames(3)
	var drops: Array = []
	var seats := ["red", "blue", "green", "gold", "purple"]
	for i in 5:
		drops.append({"value": [3, 6, 1, 5, 2][i], "n": 8, "tint": Style.seat_color(seats[i]), "to": Vector2(-4.0 + i * 2.0, 0.0), "drop": true, "delay": i * 0.12})
	map_st.arrange = false
	var d2: float = map_st.throw(drops)
	await p.get_tree().create_timer(0.35).timeout
	await snap("d4_map_drop")
	await p.get_tree().create_timer(d2).timeout
	await snap("d5_map_rest")
	p.ok(true, "dice rendered")


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
