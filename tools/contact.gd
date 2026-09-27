## Contact sheet of a glob of images, so a whole art batch can be eyeballed at once.
##   godot --headless --script res://tools/contact.gd -- dir=res://assets/portraits match=you_ out=/tmp/sheet.png
extends SceneTree

func _initialize() -> void:
	var args := {"dir": "res://assets/portraits", "match": "", "out": "/tmp/sheet.png", "cell": "300", "cols": "6"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var names: Array = []
	var d := DirAccess.open(str(args["dir"]))
	for f in d.get_files():
		if f.ends_with(".png") and (str(args["match"]) == "" or f.contains(str(args["match"]))):
			names.append(f)
	names.sort()
	var cell: int = int(args["cell"])
	var cols: int = int(args["cols"])
	var rows: int = int(ceil(float(names.size()) / float(cols)))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.09, 0.14, 1.0)) ## the game's own sea blue, so cut-outs show
	for i in names.size():
		var img: Image = Image.load_from_file(str(args["dir"]).replace("res://", "") + "/" + str(names[i]))
		if img == null:
			continue
		var s: float = float(cell) / float(maxi(img.get_width(), img.get_height()))
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_BILINEAR)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var x: int = (i % cols) * cell + (cell - img.get_width()) / 2
		var y: int = (i / cols) * cell + (cell - img.get_height()) / 2
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, y))
	sheet.save_png(str(args["out"]))
	print("contact sheet: %s images -> %s" % [names.size(), args["out"]])
	for i in names.size():
		print("  %s%s" % ["row %s col %s: " % [i / cols + 1, i % cols + 1], names[i]])
	quit(0)
