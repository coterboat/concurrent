## The tin-soldier field under the battle scene. Any number of armies: attackers on
## the left (several share the ground in a melee, each in its own band), the defender
## on the right. An army is counted in Risk pieces: a cannon for every 10, a horse for
## every 5, a man for the rest. When a loss can't come from the men, a horse falls and
## four men step up to make change (a cannon: a horse and four men).
## Moves: march in, breathe, fire (or kneel and fire, then reload), charge, rear, cheer,
## topple when hit, turn and march away. Every sheet is a Ludo loop checked for seams
## (tools/ludo/pack_anims.py); falls are drawn in code so they can never clip or reset.
extends Control

const Style := preload("res://game/core/style.gd")

const FIG_H := 104.0 ## a front-rank soldier's height in pixels at scale 1 (x 1.75 on screen)
const SIZE := {"inf": 0.86, "cav": 1.08, "gun": 0.78} ## on-screen height of each piece vs a man
const GAP := {"inf": 56.0, "cav": 84.0, "gun": 128.0} ## file spacing for each piece
const FRONT := 120.0 ## half the no-man's-land between the lines
const MAX_GUNS := 12

var armies: Array = [] ## [{pid, side, n, band: [d0, d1], fled: -1.0, flag_x}]
var figs: Array = [] ## {army, type, pos, cur, scale, state, t, alive, order, phase, alpha, anim}
var puffs: Array = [] ## {pos, t, big, seed}
var _clock := 0.0
var _anims := {} ## name -> sheet
var _legacy := false
var _soft: GradientTexture2D ## a feathered disc for smoke


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in ["soldier_idle", "soldier_fire", "soldier_march", "soldier_kneel", "soldier_reload", "soldier_charge", "soldier_cheer",
			"cavalry_idle", "cavalry_gallop", "cavalry_charge", "cavalry_rear", "cannon_idle", "cannon_fire", "cannon_reload", "flag_wave"]:
		_anims[n] = _sheet("res://assets/battle/" + n)
	if _anims["soldier_idle"].is_empty():
		_legacy = true
		var fire: Texture2D = Style.tex("res://assets/battle/soldier_fire.webp")
		if fire != null:
			_anims["soldier_idle"] = {"tex": fire, "cols": 4, "frames": 1, "fw": fire.get_width() / 4.0, "fh": fire.get_height() / 4.0, "ax": 0.5, "ay": 1.0, "fill": 1.0, "order": []}


func _sheet(base: String) -> Dictionary:
	var t: Texture2D = Style.tex(base + ".webp")
	if t == null or not FileAccess.file_exists(base + ".json"):
		return {}
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	if typeof(m) != TYPE_DICTIONARY or not (m as Dictionary).has("fw"):
		return {}
	return {"tex": t, "cols": int(m["cols"]), "frames": int(m["frames"]), "fw": float(m["fw"]), "fh": float(m["fh"]),
		"ax": float(m.get("ax", 0.55)), "ay": float(m.get("ay", 0.92)), "fill": float(m.get("fill", 450.0 / 768.0)), "order": m.get("order", [])}


func _a(name: String, fallback: String = "soldier_idle") -> Dictionary:
	var a: Dictionary = _anims.get(name, {})
	return a if not a.is_empty() else _anims.get(fallback, {})


# ------------------------------------------------------------------ armies

static func pieces(n: int) -> Dictionary:
	## Risk's pieces: cannon = 10, horse = 5, man = 1
	var guns: int = mini(n / 10, MAX_GUNS)
	var rest: int = n - guns * 10
	return {"gun": guns, "cav": rest / 5, "inf": rest % 5}


func setup(list: Array) -> void:
	## list: [{pid, side: 0 left / 1 right, n}]; attackers first, the defender last
	armies = []
	figs = []
	puffs = []
	var lefts := 0
	for a in list:
		if int(a["side"]) == 0:
			lefts += 1
	var li := 0
	for a in list:
		var side: int = int(a["side"])
		var band := [0.0, 1.0]
		if side == 0 and lefts > 1:
			band = [float(li) / lefts, float(li + 1) / lefts]
			li += 1
		armies.append({"pid": str(a["pid"]), "side": side, "n": int(a["n"]), "band": band, "fled": -1.0,
			"flag_x": -160.0 if side == 0 else size.x + 160.0})
	for i in armies.size():
		_spawn(i, pieces(int(armies[i]["n"])), true)
	queue_redraw()


func _alive(ai: int, type: String = "") -> Array:
	var out: Array = []
	for f in figs:
		if int(f["army"]) == ai and f["alive"] and (type == "" or f["type"] == type) and f["state"] != "flee":
			out.append(f)
	return out


func _spawn(ai: int, want: Dictionary, fresh: bool) -> void:
	## add pieces to an army (fresh = the opening march-in), then re-form its lines
	for type in ["inf", "cav", "gun"]:
		for k in int(want.get(type, 0)):
			var edge: float = -120.0 - randf() * 160.0 if int(armies[ai]["side"]) == 0 else size.x + 120.0 + randf() * 160.0
			figs.append({"army": ai, "type": type, "pos": Vector2.ZERO, "cur": Vector2(edge, size.y * 0.8), "scale": 1.0,
				"state": "march", "t": 0.0, "alive": true, "order": 0, "phase": randf() * 3.0, "alpha": 1.0, "anim": ""})
	_form(ai, fresh)


func _form(ai: int, snap_y: bool) -> void:
	## men in the front files, horse behind them, the guns at the rear
	var side: int = int(armies[ai]["side"])
	var band: Array = armies[ai]["band"]
	var mine: Array = _alive(ai)
	mine.sort_custom(func(x, y): return ["inf", "cav", "gun"].find(x["type"]) < ["inf", "cav", "gun"].find(y["type"]) or (x["type"] == y["type"] and int(x["order"]) < int(y["order"])))
	var n := mine.size()
	var rows: int = clampi(int(ceil(sqrt(float(n) * 0.8))), 1, 4)
	if float(band[1]) - float(band[0]) < 0.99:
		rows = clampi(rows, 1, 2)
	var x := FRONT + (40.0 if float(band[0]) > 0.01 else 0.0) ## the rear band stands a little back
	var file := -1
	for i in n:
		var f: Dictionary = mine[i]
		var row: int = i % rows
		if row == 0:
			file += 1
			if i > 0:
				x += GAP[mine[i - 1]["type"]]
		var t: float = 0.0 if rows == 1 else float(row) / float(rows - 1)
		var depth: float = lerpf(float(band[0]), float(band[1]), t * 0.85 + 0.075)
		var sc: float = 1.0 - depth * 0.3
		var y: float = size.y * (0.97 - depth * 0.52)
		var px: float = size.x * 0.5 - (x + (row % 2) * 22.0) * sc if side == 0 else size.x * 0.5 + (x + (row % 2) * 22.0) * sc
		f["order"] = i
		f["pos"] = Vector2(px, y)
		f["scale"] = sc
		if snap_y:
			f["cur"] = Vector2(f["cur"].x, y)
		if f["state"] == "idle":
			f["state"] = "march"


func set_count(ai: int, n: int) -> void:
	## casualties (or reserves): topple what's gone, bring up what's new
	n = maxi(0, n)
	var growing: bool = n > int(armies[ai]["n"])
	armies[ai]["n"] = n
	var want: Dictionary = pieces(n)
	var have := {"inf": _alive(ai, "inf").size(), "cav": _alive(ai, "cav").size(), "gun": _alive(ai, "gun").size()}
	var add := {}
	for type in ["gun", "cav", "inf"]:
		var extra: int = int(have[type]) - int(want[type])
		if extra > 0:
			var line: Array = _alive(ai, type)
			line.sort_custom(func(x, y): return int(x["order"]) < int(y["order"]))
			for k in extra:
				if growing:
					## reinforcements: small pieces fold into the bigger one, nobody dies
					line[k]["alive"] = false
					line[k]["state"] = "merge"
					line[k]["t"] = 0.0
				else:
					_fall(line[k])
		elif extra < 0:
			add[type] = -extra
	if not add.is_empty():
		_spawn(ai, add, false)


func _fall(f: Dictionary) -> void:
	f["alive"] = false
	f["state"] = "fall"
	f["t"] = 0.0
	puffs.append({"pos": f["cur"] + Vector2(0, -52 * f["scale"]), "t": 0.0, "big": f["type"] == "gun", "seed": randf() * TAU})


func volley(ai: int) -> String:
	## army ai wins a volley: a few of its pieces fire. Returns the sound to play.
	var sound := "volley"
	var shooters := _alive(ai).filter(func(f): return f["state"] == "idle")
	if shooters.is_empty():
		return sound
	shooters.shuffle()
	var guns := shooters.filter(func(f): return f["type"] == "gun")
	if not guns.is_empty() and randf() < 0.45:
		var g: Dictionary = guns[0]
		_act(g, "fire", "cannon_fire", 1.2)
		var dir := 1.0 if int(armies[ai]["side"]) == 0 else -1.0
		puffs.append({"pos": g["cur"] + Vector2(dir * 150.0 * g["scale"], -110.0 * g["scale"]), "t": -0.15, "big": true, "seed": randf() * TAU})
		return "cannon_big"
	var n := 0
	for f in shooters:
		if n >= 3:
			break
		match str(f["type"]):
			"inf":
				var kneel: bool = not _anims["soldier_kneel"].is_empty() and randf() < 0.35
				_act(f, "fire", "soldier_kneel" if kneel else "soldier_fire", 1.0 if kneel else 0.85)
				var dir2 := 1.0 if int(armies[ai]["side"]) == 0 else -1.0
				puffs.append({"pos": f["cur"] + Vector2(dir2 * 40 * f["scale"], (-40 if kneel else -62) * f["scale"]), "t": -0.3 if not kneel else -0.45, "big": false, "seed": randf() * TAU})
				n += 1
			"cav":
				if randf() < 0.5:
					_act(f, "charge", "cavalry_charge", 1.0)
					sound = "hoofs"
					n += 1
	return sound


func _act(f: Dictionary, state: String, anim: String, dur: float) -> void:
	f["state"] = state
	f["anim"] = anim
	f["t"] = 0.0
	f["dur"] = dur


func charge(ai: int) -> void:
	## pressing on: the men surge a few paces forward and back into line
	for f in _alive(ai):
		if f["state"] != "idle":
			continue
		if f["type"] == "inf" and not _anims["soldier_charge"].is_empty():
			_act(f, "charge", "soldier_charge", 0.9)
		elif f["type"] == "cav":
			_act(f, "charge", "cavalry_charge", 0.9)


func cheer(ai: int) -> void:
	for f in _alive(ai):
		match str(f["type"]):
			"inf":
				if not _anims["soldier_cheer"].is_empty():
					_act(f, "cheer", "soldier_cheer", 1.4)
			"cav":
				if not _anims["cavalry_rear"].is_empty():
					_act(f, "cheer", "cavalry_rear", 1.3)


func reload(ai: int) -> void:
	for f in _alive(ai):
		if f["state"] == "idle" and randf() < 0.4:
			match str(f["type"]):
				"inf":
					if not _anims["soldier_reload"].is_empty():
						_act(f, "reload", "soldier_reload", 1.2)
				"gun":
					if not _anims["cannon_reload"].is_empty():
						_act(f, "reload", "cannon_reload", 1.4)


func retreat(ai: int) -> void:
	armies[ai]["fled"] = 0.0
	for f in _alive(ai):
		f["state"] = "flee"
		f["t"] = randf() * 0.25


# ------------------------------------------------------------------ motion

func _process(delta: float) -> void:
	_clock += delta
	for f in figs:
		match str(f["state"]):
			"march":
				var to: Vector2 = f["pos"]
				var step: float = (430.0 if f["type"] == "cav" else 330.0) * float(f["scale"]) * delta
				var cur: Vector2 = f["cur"]
				if cur.distance_to(to) <= step:
					f["cur"] = to
					f["state"] = "idle"
				else:
					f["cur"] = cur.move_toward(to, step)
			"fire", "charge", "cheer", "reload":
				f["t"] = float(f["t"]) + delta
				if f["state"] == "charge":
					var dir := 1.0 if int(armies[int(f["army"])]["side"]) == 0 else -1.0
					var k: float = sin(clampf(float(f["t"]) / float(f.get("dur", 0.9)), 0.0, 1.0) * PI)
					f["cur"] = f["pos"] + Vector2(dir * 38.0 * k * float(f["scale"]), 0)
				if float(f["t"]) >= float(f.get("dur", 1.0)):
					f["cur"] = f["pos"]
					f["state"] = "idle"
			"fall":
				f["t"] = float(f["t"]) + delta
				if float(f["t"]) > 0.75:
					f["state"] = "dead"
			"merge":
				f["t"] = float(f["t"]) + delta
				f["alpha"] = clampf(1.0 - float(f["t"]) / 0.45, 0.0, 1.0)
				if float(f["alpha"]) <= 0.0:
					f["state"] = "gone"
			"flee":
				f["t"] = float(f["t"]) + delta
				var away := -1.0 if int(armies[int(f["army"])]["side"]) == 0 else 1.0
				if float(f["t"]) > 0.25:
					f["cur"] = f["cur"] + Vector2(away * 220.0 * float(f["scale"]) * delta, 0)
				f["alpha"] = clampf(1.6 - float(f["t"]) * 0.8, 0.0, 1.0)
				if float(f["alpha"]) <= 0.0:
					f["state"] = "gone"
					f["alive"] = false
	for a in armies:
		var i: int = armies.find(a)
		if float(a["fled"]) >= 0.0:
			a["fled"] = float(a["fled"]) + delta
			if float(a["fled"]) > 0.25:
				a["flag_x"] = float(a["flag_x"]) + (-1.0 if int(a["side"]) == 0 else 1.0) * 220.0 * delta
		else:
			a["flag_x"] = move_toward(float(a["flag_x"]), _flag_target(i), 360.0 * delta)
	var p := puffs.size() - 1
	while p >= 0:
		puffs[p]["t"] = float(puffs[p]["t"]) + delta
		if float(puffs[p]["t"]) > (2.0 if puffs[p]["big"] else 1.4):
			puffs.remove_at(p)
		p -= 1
	queue_redraw()


func _flag_target(ai: int) -> float:
	## the colours stand behind the last file of their army
	var back := 0.0
	for f in _alive(ai):
		back = maxf(back, absf(float(f["pos"].x) - size.x * 0.5))
	if back == 0.0:
		back = 120.0
	return size.x * 0.5 + (-1.0 if int(armies[ai]["side"]) == 0 else 1.0) * (back + 60.0)


# ------------------------------------------------------------------ drawing

func _len(an: Dictionary) -> int:
	var o: Array = an.get("order", [])
	return o.size() if not o.is_empty() else int(an.get("frames", 1))


func _pick(an: Dictionary, k: int, loop: bool) -> int:
	var n: int = _len(an)
	k = posmod(k, n) if loop else clampi(k, 0, n - 1)
	var o: Array = an.get("order", [])
	return int(o[k]) if not o.is_empty() else k


func _frame(an: Dictionary, idx: int) -> Rect2:
	var cols: int = int(an["cols"])
	idx = clampi(idx, 0, int(an["frames"]) - 1)
	return Rect2((idx % cols) * float(an["fw"]), (idx / cols) * float(an["fh"]), float(an["fw"]), float(an["fh"]))


func _idle_of(type: String) -> String:
	return {"inf": "soldier_idle", "cav": "cavalry_idle", "gun": "cannon_idle"}[type]


func _march_of(type: String) -> String:
	return {"inf": "soldier_march", "cav": "cavalry_gallop", "gun": "cannon_idle"}[type]


func _draw() -> void:
	if _anims.get("soldier_idle", {}).is_empty():
		return
	## the colours of every army, behind its lines
	var flag: Dictionary = _anims.get("flag_wave", {})
	for i in armies.size():
		var a: Dictionary = armies[i]
		var fled: float = float(a["fled"])
		if flag.is_empty() or (_alive(i).is_empty() and fled < 0.0):
			continue
		var alpha: float = 1.0 if fled < 0.0 else clampf(1.6 - fled * 0.8, 0.0, 1.0)
		if alpha <= 0.0:
			continue
		var band: Array = a["band"]
		var depth: float = (float(band[0]) + float(band[1])) * 0.5 + 0.12
		var y: float = size.y * (0.97 - clampf(depth, 0.0, 1.0) * 0.52)
		var flip: bool = int(a["side"]) == 1
		if fled >= 0.0:
			flip = not flip
		_draw_anim(flag, _pick(flag, int((_clock + i * 0.7) * 10.0), true), Vector2(float(a["flag_x"]), y), 1.0 - depth * 0.3, flip, _tint(str(a["pid"])), alpha, 0.0, 1.05)
	var order := figs.duplicate()
	order.sort_custom(func(x, y): return x["cur"].y < y["cur"].y)
	for f in order:
		if f["state"] == "gone":
			continue
		var army: Dictionary = armies[int(f["army"])]
		var type: String = f["type"]
		var col: Color = _tint(str(army["pid"]))
		var flip: bool = int(army["side"]) == 1
		var an: Dictionary = _a(_idle_of(type))
		var fi := 0
		var tilt := 0.0
		match str(f["state"]):
			"idle", "merge":
				fi = _pick(an, int((_clock + float(f["phase"])) * 9.0), true)
			"march", "flee":
				an = _a(_march_of(type), _idle_of(type))
				fi = _pick(an, int((_clock + float(f["phase"])) * (15.0 if type == "cav" else 13.0)), true)
				if f["state"] == "flee":
					flip = not flip
			"fire", "charge", "cheer", "reload":
				an = _a(str(f["anim"]), _idle_of(type))
				var k: float = float(f["t"]) / maxf(0.1, float(f.get("dur", 1.0)))
				if f["state"] == "charge" and (str(f["anim"]).ends_with("charge")):
					fi = _pick(an, int((_clock + float(f["phase"])) * 14.0), true)
				else:
					fi = _pick(an, int(k * float(_len(an))), false)
			"fall", "dead":
				fi = _pick(an, 0, false)
				## over backwards, away from the enemy; a gun just slews and burns
				var kk: float = clampf(float(f["t"]) / 0.42, 0.0, 1.0) if f["state"] == "fall" else 1.0
				var e: float = kk * kk
				if kk >= 1.0 and f["state"] == "fall":
					e = 1.0 - 0.06 * sin(clampf((float(f["t"]) - 0.42) / 0.3, 0.0, 1.0) * PI)
				var full: float = PI * 0.5 if type != "gun" else 0.22
				tilt = (1.0 if flip else -1.0) * full * e
				col = col.darkened(0.45 * e if type != "gun" else 0.6 * e)
		_draw_anim(an, fi, f["cur"], float(f["scale"]), flip, col, float(f["alpha"]), tilt, float(SIZE[type]))
	## powder smoke: soft feathered billows that swell, drift up and thin out
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.7))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	for p in puffs:
		var t: float = float(p["t"])
		if t < 0.0:
			continue
		var big: bool = p["big"]
		var r: float = (30.0 if big else 11.0) + t * (80.0 if big else 26.0)
		var a2: float = clampf((0.55 if big else 0.42) - t * (0.26 if big else 0.3), 0.0, 0.55)
		var c: Vector2 = p["pos"] + Vector2(t * 12.0, -t * 22.0)
		for k2 in 6:
			var off := Vector2.from_angle(float(k2) * 1.05 + float(p.get("seed", 0.0))) * r * 0.5
			var rr: float = r * (0.75 + 0.07 * k2)
			draw_texture_rect(_soft, Rect2(c + off - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(0.9, 0.89, 0.85, a2 * (0.6 + 0.07 * k2)))
		if t < (0.14 if big else 0.09):
			draw_circle(p["pos"], 16.0 if big else 8.0, Color(1.0, 0.78, 0.3, 0.9 * (1.0 - t / (0.14 if big else 0.09))))


func _draw_anim(an: Dictionary, idx: int, foot: Vector2, sc: float, flip: bool, col: Color, alpha: float, tilt: float, mult: float) -> void:
	## drawn from the feet: a man stands FIG_H x 1.75 x scale tall, other pieces by SIZE
	var h: float = FIG_H * 1.75 * sc * mult / float(an["fill"])
	var w: float = h * float(an["fw"]) / float(an["fh"])
	draw_set_transform(foot, tilt, Vector2(-1 if flip else 1, 1))
	draw_texture_rect_region(an["tex"], Rect2(Vector2(-w * float(an["ax"]), -h * float(an["ay"])), Vector2(w, h)), _frame(an, idx), Color(col, col.a * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tint(pid: String) -> Color:
	return Style.seat_color(pid).lightened(0.18) if pid != "neutral" else Color(0.72, 0.7, 0.66)
