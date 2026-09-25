## Spritesheet QA + packing for Ludo animations.
##   godot --headless --path . -s tools/sheet_tool.gd -- check <sheet> <cols> <rows> [frames]
##   godot --headless --path . -s tools/sheet_tool.gd -- shrink <sheet> <cols> <rows> <frame_px> <out.webp> [frames] [drop_last]
##   godot --headless --path . -s tools/sheet_tool.gd -- pad <in.png> <out.png> <w> <h> <cx> <baseline> [sprite_h]
##   godot --headless --path . -s tools/sheet_tool.gd -- montage <out.png> <cell_px> <cols> <img>...
## check prints, per frame: alpha bounding box, whether content touches the frame edge
## (clipping), the centroid drift from frame 0 (jitter) and the mean difference to the
## previous frame; then the loop seam (last frame vs first). A loop is clean when the
## seam is no bigger than an ordinary step and nothing touches an edge.
extends SceneTree


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 1:
		print("usage: check|shrink|pad ...")
		quit(2)
		return
	match a[0]:
		"check":
			quit(_check(a[1], int(a[2]), int(a[3]), int(a[4]) if a.size() > 4 else int(a[2]) * int(a[3])))
		"shrink":
			quit(_shrink(a[1], int(a[2]), int(a[3]), int(a[4]), a[5], int(a[6]) if a.size() > 6 else int(a[2]) * int(a[3]), a.size() > 7 and a[7] == "drop_last"))
		"pad":
			quit(_pad(a[1], a[2], int(a[3]), int(a[4]), float(a[5]), float(a[6]), int(a[7]) if a.size() > 7 else 0))
		"montage":
			quit(_montage(a[1], int(a[2]), int(a[3]), a.slice(4)))
		_:
			print("unknown command ", a[0])
			quit(2)


func _load(path: String) -> Image:
	var img := Image.new()
	var err := img.load(path if path.begins_with("/") or path.begins_with("res://") else ProjectSettings.globalize_path("res://") + path)
	if err != OK:
		push_error("cannot load %s (%s)" % [path, err])
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _frames(img: Image, cols: int, rows: int, n: int) -> Array:
	var fw: int = img.get_width() / cols
	var fh: int = img.get_height() / rows
	var out: Array = []
	for i in n:
		out.append(img.get_region(Rect2i((i % cols) * fw, (i / cols) * fh, fw, fh)))
	return out


func _stats(f: Image) -> Dictionary:
	## alpha bbox + centroid on a coarse grid (fast enough for 1024px frames)
	var w := f.get_width()
	var h := f.get_height()
	var step: int = maxi(1, w / 256)
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	var sx := 0.0
	var sy := 0.0
	var sa := 0.0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var al: float = f.get_pixel(x, y).a
			if al > 0.25:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
				sx += x * al
				sy += y * al
				sa += al
	var c := Vector2(sx / sa, sy / sa) if sa > 0.0 else Vector2.ZERO
	var edge := ""
	if maxx >= 0:
		if minx <= step:
			edge += "L"
		if maxx >= w - 1 - step:
			edge += "R"
		if miny <= step:
			edge += "T"
		if maxy >= h - 1 - step:
			edge += "B"
	return {"bbox": Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1), "c": c, "edge": edge, "mass": sa}


func _diff(a: Image, b: Image) -> float:
	var w := a.get_width()
	var h := a.get_height()
	var step: int = maxi(1, w / 192)
	var tot := 0.0
	var n := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var p: Color = a.get_pixel(x, y)
			var q: Color = b.get_pixel(x, y)
			tot += absf(p.r * p.a - q.r * q.a) + absf(p.g * p.a - q.g * q.a) + absf(p.b * p.a - q.b * q.a) + absf(p.a - q.a)
			n += 1
	return tot / float(maxi(1, n)) * 100.0


func _check(path: String, cols: int, rows: int, n: int) -> int:
	var img := _load(path)
	if img == null:
		return 1
	var fr := _frames(img, cols, rows, n)
	var s0: Dictionary = _stats(fr[0])
	var steps: Array = []
	var worst_drift := 0.0
	var edges := {}
	for i in fr.size():
		var s: Dictionary = _stats(fr[i])
		var drift: float = (s["c"] - s0["c"]).length()
		worst_drift = maxf(worst_drift, drift)
		var d := 0.0
		if i > 0:
			d = _diff(fr[i - 1], fr[i])
			steps.append(d)
		if s["edge"] != "":
			edges[i] = s["edge"]
		print("frame %2d  bbox %-28s edge %-3s drift %5.1f  step %5.2f" % [i, str(s["bbox"]), s["edge"], drift, d])
	var seam: float = _diff(fr[fr.size() - 1], fr[0])
	var seam2: float = _diff(fr[fr.size() - 2], fr[0]) if fr.size() > 2 else seam
	steps.sort()
	var median: float = steps[steps.size() / 2] if steps.size() > 0 else 0.0
	var mx: float = steps[steps.size() - 1] if steps.size() > 0 else 0.0
	print("SUMMARY %s frame=%dx%d  median_step %.2f  max_step %.2f  seam(last->first) %.2f  seam(prev->first) %.2f  max_drift %.1fpx  edge_frames %s" % [
		path.get_file(), fr[0].get_width(), fr[0].get_height(), median, mx, seam, seam2, worst_drift, str(edges)])
	return 0


func _shrink(path: String, cols: int, rows: int, px: int, out: String, n: int, drop_last: bool) -> int:
	var img := _load(path)
	if img == null:
		return 1
	var fr := _frames(img, cols, rows, n)
	if drop_last:
		fr.remove_at(fr.size() - 1)
	var count: int = fr.size()
	var oc: int = ceili(sqrt(float(count)))
	var orows: int = ceili(float(count) / float(oc))
	var fw: int = fr[0].get_width()
	var fh: int = fr[0].get_height()
	var ph: int = int(round(float(px) * float(fh) / float(fw)))
	var sheet := Image.create(oc * px, orows * ph, false, Image.FORMAT_RGBA8)
	for i in count:
		var f: Image = fr[i].duplicate()
		f.resize(px, ph, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(f, Rect2i(0, 0, px, ph), Vector2i((i % oc) * px, (i / oc) * ph))
	var outp: String = out if out.begins_with("/") else ProjectSettings.globalize_path("res://") + out
	var err: int = sheet.save_webp(outp, true, 0.9)
	if err != OK:
		push_error("save failed %s" % err)
		return 1
	var meta := {"cols": oc, "rows": orows, "frames": count, "fw": px, "fh": ph}
	var jf := FileAccess.open(outp.get_basename() + ".json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(meta))
	jf.close()
	print("wrote %s %dx%d  %s" % [out, sheet.get_width(), sheet.get_height(), JSON.stringify(meta)])
	return 0


func _pad(inp: String, out: String, w: int, h: int, cx: float, baseline: float, sprite_h: int = 0) -> int:
	## Place a cut-out sprite on a transparent w*h canvas: horizontal centre at cx (0..1),
	## feet on baseline (0..1). Room to the sides and above so an animation never clips.
	var img := _load(inp)
	if img == null:
		return 1
	var used: Rect2i = img.get_used_rect()
	var spr: Image = img.get_region(used)
	if sprite_h > 0:
		spr.resize(int(round(spr.get_width() * float(sprite_h) / spr.get_height())), sprite_h, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var x: int = int(round(cx * w - spr.get_width() * 0.5))
	var y: int = int(round(baseline * h - spr.get_height()))
	canvas.blit_rect(spr, Rect2i(0, 0, spr.get_width(), spr.get_height()), Vector2i(x, y))
	var outp: String = out if out.begins_with("/") else ProjectSettings.globalize_path("res://") + out
	var err: int = canvas.save_png(outp)
	print("padded %s -> %s (%dx%d, sprite %s at %d,%d)" % [inp, out, w, h, str(spr.get_size()), x, y])
	return err


func _montage(out: String, cell: int, cols: int, paths: PackedStringArray) -> int:
	## Contact sheet for review: each image fit into a cell on a mid-grey checker.
	var rows: int = ceili(float(paths.size()) / float(cols))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	for y in rows * cell:
		for x in cols * cell:
			var c: float = 0.32 if ((x / 16) + (y / 16)) % 2 == 0 else 0.4
			sheet.set_pixel(x, y, Color(c, c, c))
	for i in paths.size():
		var img := _load(paths[i])
		if img == null:
			continue
		var sc: float = minf(float(cell) / img.get_width(), float(cell) / img.get_height())
		var w: int = maxi(1, int(img.get_width() * sc))
		var h: int = maxi(1, int(img.get_height() * sc))
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		var ox: int = (i % cols) * cell + (cell - w) / 2
		var oy: int = (i / cols) * cell + (cell - h) / 2
		sheet.blend_rect(img, Rect2i(0, 0, w, h), Vector2i(ox, oy))
	return sheet.save_png(out)
