## v1.11: the redone volley sheets fire on their marks. A volley is shot at the moment the sheet's
## `shot` frame plays, so the flash should leave the muzzle, not the soldier's chest.
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
	f.setup([{"pid": "red", "side": 0, "n": 6}, {"pid": "blue", "side": 1, "n": 6}])
	await p.get_tree().create_timer(3.0).timeout
	var shot_at: float = f._shot_at("volley_kf") if f._anims.has("volley_kf") else -1.0
	var used := ""
	for side in [0, 1]:
		used = f.volley(side)
		## the flash comes at the shot: catch the frames around it
		for k in 3:
			await p.get_tree().create_timer(0.18 if k == 0 else 0.12).timeout
			await snap("v111_volley_%d_%d" % [side, k])
		await p.get_tree().create_timer(2.0).timeout
	p.ok(used != "", "a volley plays (%s)" % used)
	for name in f._anims.keys():
		var an: Dictionary = f._anims[name]
		if str(name).contains("volley"):
			p.ok(int(an.get("shot", -1)) > 0 and (an.get("muzzle", []) as Array).size() == 2, "%s fires on its shot frame %s at %s" % [name, an.get("shot"), an.get("muzzle")])
	p.log("v111 probe done (raise %.2f s)" % shot_at)


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
