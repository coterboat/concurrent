## The lie of the land, for any map. Heights are generated from what every map already
## carries (mapgen's data texture: which land each pixel belongs to, how far it is from the
## coast and from a border; and each region's terrain), so a new map gets its hills,
## mountains, dunes and river valleys for free, and the same map always gets the same ones.
##
## One cell is `step` map pixels. World units are map pixels: x east, z south, y up.
##   heights   PackedFloat32Array, W*H, the ground's height at each cell centre
##   height_image   FORMAT_RF, the same numbers for the shaders (bilinear)
##   ground_image   FORMAT_RGBA8: rgb the bare ground's colour, a how wooded it is
extends RefCounted

const T_GRASS := 0
const T_FOREST := 1
const T_MOOR := 2
const T_COAST := 3
const T_DESERT := 4
const T_SNOW := 5
const T_ASH := 6
const T_MOUNTAIN := 7
const TERRAINS := ["grass", "forest", "moor", "coast", "desert", "snow", "ash", "mountain"]

## the bare ground of each terrain (painterly, a little muted, like the chart)
const GROUND := [
	Color(0.38, 0.53, 0.22), Color(0.25, 0.38, 0.17), Color(0.46, 0.40, 0.33), Color(0.47, 0.56, 0.28),
	Color(0.82, 0.67, 0.43), Color(0.85, 0.88, 0.92), Color(0.27, 0.25, 0.24), Color(0.44, 0.45, 0.33),
]
## rolling hills on each terrain (world units, peak to trough)
const HILLS := [18.0, 26.0, 34.0, 10.0, 8.0, 38.0, 28.0, 36.0]

var map_size := Vector2(2400, 1500)
var step := 3
var cell := Vector2(3, 3) ## map pixels per cell (step, stretched so the cells tile the map exactly)
var w := 0
var h := 0
var heights := PackedFloat32Array()
var height_image: Image
var ground_image: Image
var coast_px := PackedFloat32Array() ## per cell: signed distance to the coast (map px, +-42)
var woods := PackedFloat32Array() ## per cell: 0..1, how wooded
var crossings := {} ## "a|b" (land ids, sorted) -> Vector2: where two touching lands meet, on the border's middle
var roads: Array = [] ## [[from anchor, crossing, to anchor]]: the way between two touching lands, a pass in the hills
var road_d := PackedFloat32Array() ## per cell: map px to the nearest road (1e9 when none is near)
var weights_a: Image ## per cell, blurred: how much grass, forest, moor, coast (the ground textures' blend)
var weights_b: Image ## ...desert, snow, ash, mountain
var scenery: Array = [] ## scenery.gd's plan: where the villages and landmarks stand (the woods keep clear)
var scenery_scenes: Dictionary = {} ## ...and their models, loaded with the land (off the main thread)
var lo := 0.0
var hi := 0.0
var millis := 0


static func build(art: RefCounted, map: RefCounted, p_step: int = 3) -> RefCounted:
	var t = load("res://game/world3d/terrain.gd").new()
	t._build(art, map, p_step)
	return t


func height_at(p: Vector2) -> float:
	## Bilinear, exactly as the GPU samples height_image (texel centres at (i + 0.5) * step).
	var fx: float = p.x / cell.x - 0.5
	var fy: float = p.y / cell.y - 0.5
	var x0: int = clampi(floori(fx), 0, w - 1)
	var y0: int = clampi(floori(fy), 0, h - 1)
	var x1: int = mini(x0 + 1, w - 1)
	var y1: int = mini(y0 + 1, h - 1)
	var tx: float = clampf(fx - floorf(fx), 0.0, 1.0)
	var ty: float = clampf(fy - floorf(fy), 0.0, 1.0)
	var a: float = lerpf(heights[y0 * w + x0], heights[y0 * w + x1], tx)
	var b: float = lerpf(heights[y1 * w + x0], heights[y1 * w + x1], tx)
	return lerpf(a, b, ty)


func normal_at(p: Vector2) -> Vector3:
	var e: float = cell.x
	var dx: float = height_at(p + Vector2(e, 0)) - height_at(p - Vector2(e, 0))
	var dz: float = height_at(p + Vector2(0, e)) - height_at(p - Vector2(0, e))
	return Vector3(-dx, 2.0 * e, -dz).normalized()


# ------------------------------------------------------------------ generation

func _build(art: RefCounted, map: RefCounted, p_step: int) -> void:
	var t0 := Time.get_ticks_msec()
	step = p_step
	map_size = art.size
	w = int(ceil(map_size.x / step))
	h = int(ceil(map_size.y / step))
	cell = Vector2(map_size.x / w, map_size.y / h)
	var n: int = w * h
	var src: PackedByteArray = art.data_image.get_data()
	var sw: int = art.data_image.get_width()
	## which terrain each land is
	var terr_of := PackedInt32Array()
	terr_of.resize(256)
	terr_of.fill(T_GRASS)
	for i in art.order.size():
		var td = map.get_territory(art.order[i])
		if td != null:
			terr_of[i] = maxi(0, TERRAINS.find(str(map.region_terrain.get(td.region, "grass"))))
	## per cell: the land it belongs to, the coast and the border
	var idx := PackedInt32Array()
	var coast := PackedFloat32Array()
	var bord := PackedFloat32Array()
	idx.resize(n)
	coast.resize(n)
	bord.resize(n)
	var wa := PackedByteArray() ## grass forest moor coast
	var wb := PackedByteArray() ## desert snow ash mountain
	var wc := PackedByteArray() ## land, mountain, high ground (snow + ash), forest: blurred wide
	wa.resize(n * 4)
	wb.resize(n * 4)
	wc.resize(n * 4)
	var sh: int = art.data_image.get_height()
	for y in h:
		var sy: int = mini(int((y + 0.5) * cell.y), sh - 1)
		for x in w:
			var k: int = y * w + x
			var s: int = (sy * sw + mini(int((x + 0.5) * cell.x), sw - 1)) * 4
			var ti: int = src[s]
			var c: float = (float(src[s + 1]) - 128.0) / 3.0
			idx[k] = ti
			coast[k] = c
			bord[k] = float(src[s + 2]) / 8.0
			var tt: int = terr_of[ti] if ti < 256 else T_GRASS
			if tt < 4:
				wa[k * 4 + tt] = 255
			else:
				wb[k * 4 + tt - 4] = 255
			if c > 0.0:
				wc[k * 4] = 255
				if tt == T_MOUNTAIN:
					wc[k * 4 + 1] = 255
				if tt == T_SNOW or tt == T_ASH:
					wc[k * 4 + 2] = 255
				if tt == T_FOREST:
					wc[k * 4 + 3] = 255
	## soft edges between terrains (blurred by halving and blowing back up: C++ speed)
	var ia := _blur(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, wa), 3)
	var ib := _blur(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, wb), 3)
	var ic := _blur(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, wc), 5)
	var ic2 := _blur(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, wc), 3)
	var ic3 := _blur(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, wc), 6) ## the foothills: a range's reach
	weights_a = ia
	weights_b = ib
	wa = ia.get_data()
	wb = ib.get_data()
	wc = ic.get_data()
	var wc2: PackedByteArray = ic2.get_data()
	var wc3: PackedByteArray = ic3.get_data()
	## the noises, seeded by the map so a map always looks the same
	var sd: int = hash(str(art.id))
	var hills := _noise(sd, FastNoiseLite.FRACTAL_FBM, 1.0 / 190.0, 4)
	var ridge := _noise(sd + 1, FastNoiseLite.FRACTAL_RIDGED, 1.0 / 300.0, 4)
	var crag := _noise(sd + 2, FastNoiseLite.FRACTAL_RIDGED, 1.0 / 110.0, 2)
	var detail := _noise(sd + 3, FastNoiseLite.FRACTAL_FBM, 1.0 / 46.0, 3)
	var warp := _noise(sd + 4, FastNoiseLite.FRACTAL_FBM, 1.0 / 320.0, 2)
	heights.resize(n)
	woods.resize(n)
	var gimg := PackedByteArray()
	gimg.resize(n * 4)
	var wt := PackedFloat32Array()
	wt.resize(8)
	for y in h:
		var py: float = (y + 0.5) * cell.y
		for x in w:
			var k: int = y * w + x
			var px: float = (x + 0.5) * cell.x
			var c: float = coast[k]
			var tot := 0.0
			for j in 4:
				wt[j] = float(wa[k * 4 + j])
				wt[j + 4] = float(wb[k * 4 + j])
				tot += wt[j] + wt[j + 4]
			tot = maxf(tot, 1.0)
			for j in 8:
				wt[j] /= tot
			var land: float = float(wc[k * 4]) / 255.0
			var mount: float = smoothstep(0.12, 0.9, float(wc[k * 4 + 1]) / 255.0)
			var mount_near: float = float(wc2[k * 4 + 1]) / 255.0
			var high: float = smoothstep(0.2, 0.95, float(wc[k * 4 + 2]) / 255.0)
			var cliff: float = clampf(mount_near * 1.4 + wt[T_SNOW] * 0.6, 0.0, 1.0)
			var hv := 0.0
			if c < 0.0:
				## the shelf drops off the coast; steeper under a mountain coast
				hv = c * lerpf(0.7, 1.4, cliff) - 1.0
				hv = maxf(hv, -48.0)
			else:
				var cont: float = smoothstep(0.5, 0.93, land) ## 0 on the coast, 1 deep inland
				var shore: float = smoothstep(0.0, lerpf(40.0, 6.0, cliff), c)
				var inland: float = smoothstep(0.5, 0.9, land) ## hills grow as the sea falls behind
				hv = 0.12 * minf(c, 10.0) + 2.0 * shore + 9.0 * cont
				var amp := 0.0
				for j in 8:
					amp += wt[j] * HILLS[j]
				var hl: float = hills.get_noise_2d(px, py) * 0.5 + 0.5
				hv += amp * hl * shore * (0.15 + 0.85 * inland)
				var wx: float = warp.get_noise_2d(px, py) ## a slow warp, so ridges and dunes wander
				var wy: float = warp.get_noise_2d(px + 913.0, py - 517.0)
				var dt: float = detail.get_noise_2d(px, py)
				hv += dt * (1.2 + 3.0 * (wt[T_MOOR] + wt[T_ASH] + wt[T_MOUNTAIN] + wt[T_SNOW]))
				if wt[T_DESERT] > 0.01:
					var u: float = (px * 0.82 + py * 0.36) / 30.0 + wx * 7.0 + wy * 3.0
					var dune: float = pow(1.0 - absf(sin(u)), 1.8)
					var big: float = hills.get_noise_2d(px * 0.6, py * 0.6) * 0.5 + 0.5
					hv += wt[T_DESERT] * shore * (6.0 + (5.0 + 9.0 * big) * dune)
				if mount > 0.001 or high > 0.001 or wt[T_ASH] > 0.01:
					var rg: float = ridge.get_noise_2d(px + wx * 140.0, py + wy * 140.0) * 0.5 + 0.5
					var cr: float = crag.get_noise_2d(px + wx * 60.0, py + wy * 60.0) * 0.5 + 0.5
					hv += pow(mount, 1.4) * (30.0 + 105.0 * pow(rg, 1.7) + 6.0 * cr * rg) * shore * (0.35 + 0.65 * inland)
					hv += high * (12.0 + 36.0 * rg * rg) * shore * (0.4 + 0.6 * inland)
					hv += wt[T_ASH] * 26.0 * cr * cr * shore
				## foothills: a range's reach rolls out into the lands below it
				var foot: float = smoothstep(0.03, 0.45, float(wc3[k * 4 + 1]) / 255.0 + float(wc3[k * 4 + 2]) / 510.0)
				if foot > 0.001:
					hv += foot * (1.0 - mount) * (8.0 + 22.0 * hl) * shore
				## snowfields: broad swells and drifts cut by the wind
				if wt[T_SNOW] > 0.01:
					var su: float = (px * 0.3 - py * 0.9) / 46.0 + wx * 5.0
					var drift: float = pow(1.0 - absf(sin(su)), 2.2)
					hv += wt[T_SNOW] * shore * (7.0 * drift + 16.0 * (hills.get_noise_2d(px * 0.5, py * 0.5) * 0.5 + 0.5))
				## a border between two lands: a river valley in the lowlands, a crest in the hills
				var bd: float = bord[k]
				if c > bd + 1.5:
					var bv: float = 1.0 - smoothstep(0.0, 31.0, bd)
					var rocky: float = clampf(mount * 1.3 + high * 0.6, 0.0, 1.0)
					hv -= bv * bv * 11.0 * (1.0 - rocky)
					hv += bv * bv * bv * 6.0 * rocky
			heights[k] = hv
			## the bare ground's colour, and how wooded
			var col := Color(0, 0, 0)
			for j in 8:
				col += GROUND[j] * wt[j]
			var dv: float = detail.get_noise_2d(px * 1.7, py * 1.7) * 0.06
			gimg[k * 4] = clampi(int((col.r + dv) * 255.0), 0, 255)
			gimg[k * 4 + 1] = clampi(int((col.g + dv) * 255.0), 0, 255)
			gimg[k * 4 + 2] = clampi(int((col.b + dv * 0.7) * 255.0), 0, 255)
			var wd: int = clampi(int(float(wc2[k * 4 + 3]) * (0.6 + 0.8 * hills.get_noise_2d(px * 2.3, py * 2.3))), 0, 255)
			gimg[k * 4 + 3] = wd
			woods[k] = float(wd) / 255.0
	coast_px = coast
	_find_crossings(art, idx)
	var floors: Dictionary = _flatten_anchors(art, idx, bord)
	_carve_roads(art, floors)
	## the roads worn into the ground: a dirt track down the middle of each way
	for k in n:
		var rd: float = road_d[k]
		if rd > 7.0:
			continue
		var f: float = (1.0 - smoothstep(2.5, 7.0, rd)) * 0.75
		gimg[k * 4] = int(lerpf(gimg[k * 4], 150.0, f))
		gimg[k * 4 + 1] = int(lerpf(gimg[k * 4 + 1], 126.0, f))
		gimg[k * 4 + 2] = int(lerpf(gimg[k * 4 + 2], 92.0, f))
		gimg[k * 4 + 3] = int(gimg[k * 4 + 3] * (1.0 - f))
	lo = 1.0e9
	hi = -1.0e9
	for v in heights:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	height_image = Image.create_from_data(w, h, false, Image.FORMAT_RF, heights.to_byte_array())
	ground_image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, gimg)
	millis = Time.get_ticks_msec() - t0


func _flatten_anchors(art: RefCounted, idx: PackedInt32Array, bord: PackedFloat32Array) -> Dictionary:
	## Every land keeps a level stage round its token, where its garrison stands and its
	## battles are fought: the floor of the ground there (in the hills, a high valley),
	## eased out to the wild land, and to nothing at the land's border (so a small land in the
	## hills is never a raised block with cliffs where its neighbours begin). Returns land
	## index -> the stage's height.
	var floors := {}
	for i in art.order.size():
		var id: String = art.order[i]
		var a: Vector2 = art.anchors.get(id, Vector2.ZERO)
		var dep: float = float(art.depth.get(id, 60.0))
		var r0: float = dep * 0.35
		var r1: float = dep * 1.0
		var vals := PackedFloat32Array()
		var cx: int = int(a.x / cell.x)
		var cy: int = int(a.y / cell.y)
		var rc: int = int(r1 / cell.x) + 1
		for y in range(maxi(0, cy - rc), mini(h, cy + rc + 1)):
			for x in range(maxi(0, cx - rc), mini(w, cx + rc + 1)):
				var k: int = y * w + x
				if idx[k] != i:
					continue
				var d: float = Vector2((x + 0.5) * cell.x, (y + 0.5) * cell.y).distance_to(a)
				if d <= r0:
					vals.append(heights[k])
		if vals.is_empty():
			continue
		vals.sort()
		var low := 0.0
		var nlow: int = maxi(1, int(vals.size() * 0.4))
		for j in nlow:
			low += vals[j]
		var mean: float = maxf(low / nlow, 2.0)
		floors[i] = mean
		for y in range(maxi(0, cy - rc), mini(h, cy + rc + 1)):
			for x in range(maxi(0, cx - rc), mini(w, cx + rc + 1)):
				var k: int = y * w + x
				if idx[k] != i or heights[k] < 0.0 or coast_px[k] < 4.0:
					continue
				var d: float = Vector2((x + 0.5) * cell.x, (y + 0.5) * cell.y).distance_to(a)
				var f: float = (1.0 - smoothstep(r0 * 0.5, r1, d)) * smoothstep(4.0, 36.0, coast_px[k]) * smoothstep(1.0, 26.0, bord[k])
				heights[k] = lerpf(heights[k], mean, f * f * 0.85)
	return floors


func _find_crossings(art: RefCounted, idx: PackedInt32Array) -> void:
	## every pair of lands that touch, and the middle of the border between them
	var pts := {} ## key -> [Vector2]
	for y in h - 1:
		for x in w - 1:
			var k: int = y * w + x
			if coast_px[k] <= 2.0:
				continue
			var a: int = idx[k]
			for k2 in [k + 1, k + w]:
				var b: int = idx[k2]
				if b == a or coast_px[k2] <= 2.0 or a >= art.order.size() or b >= art.order.size():
					continue
				var key: String = _pair(art.order[a], art.order[b])
				var mid: Vector2 = Vector2((x + 0.5) * cell.x, (y + 0.5) * cell.y) + (Vector2(cell.x * 0.5, 0) if k2 == k + 1 else Vector2(0, cell.y * 0.5))
				if not pts.has(key):
					pts[key] = [] ## an Array: a packed array in a dictionary appends to a copy
				(pts[key] as Array).append(mid)
	for key in pts.keys():
		var ps: Array = pts[key]
		if ps.size() < 3:
			continue
		var c := Vector2.ZERO
		for p in ps:
			c += p
		c /= float(ps.size())
		var best: Vector2 = ps[0]
		for p in ps:
			if p.distance_squared_to(c) < best.distance_squared_to(c):
				best = p
		crossings[key] = best


static func _pair(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func crossing(a: String, b: String) -> Variant:
	return crossings.get(_pair(a, b), null)


func _carve_roads(art: RefCounted, floors: Dictionary) -> void:
	## The way from one land's heart, over the middle of its border, to the next land's heart.
	## Where the ground is higher than the way (in the hills), the way is cut down to it: a
	## pass, its floor eased from one land's stage to the other's with a saddle at the border.
	road_d.resize(w * h)
	road_d.fill(1.0e9)
	for key in crossings.keys():
		var ids: PackedStringArray = (key as String).split("|")
		var ia: int = int(art.index.get(ids[0], -1))
		var ib: int = int(art.index.get(ids[1], -1))
		if ia < 0 or ib < 0:
			continue
		var pa: Vector2 = art.anchors[ids[0]]
		var pb: Vector2 = art.anchors[ids[1]]
		var x: Vector2 = crossings[key]
		var fa: float = float(floors.get(ia, height_at(pa)))
		var fb: float = float(floors.get(ib, height_at(pb)))
		var saddle: float = maxf(fa, fb) * 0.6 + minf(fa, fb) * 0.4 + 5.0
		roads.append([pa, x, pb])
		for seg in [[pa, x, fa, saddle], [x, pb, saddle, fb]]:
			_carve(seg[0], seg[1], seg[2], seg[3])


func _carve(p0: Vector2, p1: Vector2, h0: float, h1: float) -> void:
	var r := 44.0
	var lo_p := Vector2(minf(p0.x, p1.x) - r, minf(p0.y, p1.y) - r)
	var hi_p := Vector2(maxf(p0.x, p1.x) + r, maxf(p0.y, p1.y) + r)
	var seg: Vector2 = p1 - p0
	var len2: float = maxf(seg.length_squared(), 1.0)
	for y in range(maxi(0, int(lo_p.y / cell.y)), mini(h, int(hi_p.y / cell.y) + 1)):
		for x in range(maxi(0, int(lo_p.x / cell.x)), mini(w, int(hi_p.x / cell.x) + 1)):
			var k: int = y * w + x
			if coast_px[k] < 0.0:
				continue
			var p := Vector2((x + 0.5) * cell.x, (y + 0.5) * cell.y)
			var t: float = clampf((p - p0).dot(seg) / len2, 0.0, 1.0)
			var d: float = p.distance_to(p0 + seg * t)
			if d >= r:
				continue
			road_d[k] = minf(road_d[k], d)
			var floor_h: float = lerpf(h0, h1, t * t * (3.0 - 2.0 * t))
			var keep: float = smoothstep(r * 0.3, r, d)
			heights[k] = minf(heights[k], lerpf(floor_h, heights[k], keep))


func road_at(p: Vector2) -> float:
	var x: int = clampi(int(p.x / cell.x), 0, w - 1)
	var y: int = clampi(int(p.y / cell.y), 0, h - 1)
	return road_d[y * w + x] if road_d.size() > 0 else 1.0e9


func _noise(sd: int, fractal: int, freq: float, octaves: int) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.seed = sd
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.fractal_type = fractal
	nz.frequency = freq
	nz.fractal_octaves = octaves
	return nz


func _blur(img: Image, levels: int) -> Image:
	var ow: int = img.get_width()
	var oh: int = img.get_height()
	var out: Image = img.duplicate()
	for i in levels:
		out.shrink_x2()
	## up in two steps so the blow-up stays smooth (one big cubic step leaves a grid)
	out.resize(maxi(1, ow / 2), maxi(1, oh / 2), Image.INTERPOLATE_CUBIC)
	out.resize(ow, oh, Image.INTERPOLATE_BILINEAR)
	return out


func woods_at(p: Vector2) -> float:
	var x: int = clampi(int(p.x / cell.x), 0, w - 1)
	var y: int = clampi(int(p.y / cell.y), 0, h - 1)
	return woods[y * w + x]


func coast_at(p: Vector2) -> float:
	var x: int = clampi(int(p.x / cell.x), 0, w - 1)
	var y: int = clampi(int(p.y / cell.y), 0, h - 1)
	return coast_px[y * w + x]
