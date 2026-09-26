## v1.5 formations: armies of many sizes drawn up on the field.
extends RefCounted

const BattleField := preload("res://game/ui/battle_field.gd")
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
	bg.texture = Style.tex("res://assets/battle/field_desert.webp")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var f: Control = BattleField.new()
	f.position = Vector2(40, 250)
	f.size = Vector2(1360, 424)
	root.add_child(f)
	await p.frames(3)
	for spec in [["f1_small", [[4, 0], [3, 1]]], ["f2_mid", [[12, 0], [12, 1]]], ["f3_big", [[34, 0], [27, 1]]], ["f4_huge", [[78, 0], [55, 1]]], ["f5_melee", [[18, 0], [9, 0], [23, 1]]]]:
		var list: Array = []
		var seats := ["red", "green", "blue"]
		for i in (spec[1] as Array).size():
			list.append({"pid": seats[i], "side": int(spec[1][i][1]), "n": int(spec[1][i][0])})
		f.setup(list)
		await p.get_tree().create_timer(3.2).timeout
		await snap(str(spec[0]))
	p.ok(true, "formations drawn")


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
