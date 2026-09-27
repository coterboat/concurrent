## The tin-soldier field under the battle scene. Any number of armies: attackers on
## the left (several share the ground in a melee, each in its own band), the defender
## on the right. An army is counted in Risk pieces: a cannon for every 10, a horse for
## every 5, a man for the rest. When a loss can't come from the men, a horse falls and
## four men step up to make change (a cannon: a horse and four men).
## Moves: march in, breathe, fire (standing or from the knee: a real aiming pose, the
## recoil, the flash and the smoke drawn here, so the musket always points at the enemy),
## reload, charge, rear, cheer,
## topple when hit, turn and march away. Every sheet is a Ludo loop checked for seams
## (tools/ludo/pack_anims.py); falls are drawn in code so they can never clip or reset.
extends Control

const Style := preload("res://game/core/style.gd")

const FIG_H := 104.0 ## a front-rank soldier's height in pixels at scale 1 (x 1.75 on screen)
const SIZE := {"inf": 0.86, "cav": 1.02, "gun": 0.7} ## on-screen height of each piece vs a man
const GAP := {"inf": 56.0, "cav": 84.0, "gun": 128.0} ## file spacing for each piece
const FRONT := 120.0 ## half the no-man's-land between the lines
const MAX_GUNS := 12
## where the muzzle is on each aiming pose, from the feet, at scale 1 (facing right)
const MUZZLE := {"soldier_aim": Vector2(91, -119), "soldier_kneel_aim": Vector2(82, -78)}
const SHOT_AT := 0.06 ## seconds into the fire move when the musket goes off
const ELITE := 15 ## v1.9: an army this big (a Brigade's dice) fields grenadiers and cuirassiers
## v1.9 keyframed moves (Ludo, through our own poses): used when on disk, else the v1.4 moves
const KF := ["soldier_volley_kf", "soldier_kneel_volley_kf", "soldier_charge_kf", "soldier_cheer_kf", "soldier_reload_kf", "soldier_fall_kf",
	"cannon_fire_kf", "cavalry_charge_kf", "grenadier_idle", "grenadier_march", "grenadier_volley_kf", "grenadier_charge_kf",
	"cuirassier_idle", "cuirassier_gallop", "cuirassier_charge_kf"]

var armies: Array = [] ## [{pid, side, n, band: [d0, d1], fled: -1.0, flag_x}]
var figs: Array = [] ## {army, type, pos, cur, scale, state, t, alive, order, phase, alpha, anim}
var puffs: Array = [] ## {pos, t, big, seed}
var _clock := 0.0
var _anims := {} ## name -> sheet
var _legacy := false
var _soft: GradientTexture2D ## a feathered disc for smoke
var bursts: Array = [] ## v1.9: painted effect sheets in play: {name, pos, t, px, flip}
var _fx := {} ## name -> sheet (assets/fx), {} when missing
var _elite_ok := {"inf": false, "cav": false}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in ["soldier_idle", "soldier_aim", "soldier_kneel_aim", "soldier_fire", "soldier_march", "soldier_reload", "soldier_charge", "soldier_cheer",
			"cavalry_idle", "cavalry_gallop", "cavalry_charge", "cavalry_rear", "cannon_idle", "cannon_fire", "cannon_reload", "flag_wave"]:
		_anims[n] = _sheet("res://assets/battle/" + n)
	for n in KF:
		_anims[n] = _sheet("res://assets/battle/" + n)
	## the elite dress only when the whole set is there (no bearskin swapped in mid-volley)
	_elite_ok["inf"] = ["grenadier_idle", "grenadier_march", "grenadier_volley_kf", "grenadier_charge_kf"].all(func(k): return not _anims[k].is_empty())
	_elite_ok["cav"] = ["cuirassier_idle", "cuirassier_gallop", "cuirassier_charge_kf"].all(func(k): return not _anims[k].is_empty())
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
		"ax": float(m.get("ax", 0.55)), "ay": float(m.get("ay", 0.92)), "fill": float(m.get("fill", 450.0 / 768.0)), "order": m.get("order", []),
		"fps": float(m.get("fps", 0.0)), "shot": int(m.get("shot", -1)), "muzzle": m.get("muzzle", []), "down": int(m.get("down", -1))}


func _fx_sheet(name: String) -> Dictionary:
	## v1.9: an untinted effect sheet (smoke, blast, dust), painted with Ludo
	if _fx.has(name):
		return _fx[name]
	var base := "res://assets/fx/" + name
	var t: Texture2D = Style.tex(base + ".webp")
	var out := {}
	if t != null and FileAccess.file_exists(base + ".json"):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
		if typeof(m) == TYPE_DICTIONARY and (m as Dictionary).has("fw"):
			out = {"tex": t, "cols": int(m["cols"]), "frames": int(m["frames"]), "fw": float(m["fw"]), "fh": float(m["fh"]),
				"ax": float(m.get("ax", 0.5)), "ay": float(m.get("ay", 0.5)), "fps": float(m.get("fps", 12.0)), "loop": bool(m.get("loop", false)),
				"order": m.get("order", []), "faces": str(m.get("faces", "right"))}
	_fx[name] = out
	return out


func burst(name: String, pos: Vector2, px: float, toward_right: bool = true, delay: float = 0.0, dur: float = 0.0) -> bool:
	## play an effect sheet at pos (its emitter point), px tall; false if there is no such sheet.
	## A looping sheet (fire) plays for dur seconds (4 if none given), fading at the end.
	var sh: Dictionary = _fx_sheet(name)
	if sh.is_empty():
		return false
	var flip: bool = (str(sh["faces"]) == "right") != toward_right
	var d: float = dur if dur > 0.0 else (4.0 if bool(sh["loop"]) else 0.0)
	bursts.append({"name": name, "pos": pos, "t": -delay, "px": px, "flip": flip, "dur": d})
	return true


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
	bursts = []
	## several armies on one side share its ground in bands, front to back
	var per_side := [0, 0]
	for a in list:
		per_side[int(a["side"])] += 1
	var seen := [0, 0]
	for a in list:
		var side: int = int(a["side"])
		var band := [0.0, 1.0]
		if int(per_side[side]) > 1:
			band = [float(seen[side]) / per_side[side], float(seen[side] + 1) / per_side[side]]
		seen[side] += 1
		armies.append({"pid": str(a["pid"]), "side": side, "n": int(a["n"]), "band": band, "fled": -1.0,
			"flag_x": -160.0 if side == 0 else size.x + 160.0, "elite": int(a["n"]) >= ELITE})
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
	## Drawn up in formation. The foot stand in a line at the front of their ground, four
	## abreast and rank behind rank; the horse wait behind the foot; and the guns are
	## drawn up in a battery on the far side of the ground, three lanes deep. Foot and
	## guns keep their own lanes, so nothing stands in front of a gun's muzzle. If the
	## whole array won't fit its half of the field, it closes ranks.
	var side: int = int(armies[ai]["side"])
	var band: Array = armies[ai]["band"]
	var mine: Array = _alive(ai)
	mine.sort_custom(func(x, y): return int(x["order"]) < int(y["order"]))
	var inf: Array = mine.filter(func(f): return f["type"] == "inf")
	var cav: Array = mine.filter(func(f): return f["type"] == "cav")
	var gun: Array = mine.filter(func(f): return f["type"] == "gun")
	var b0: float = float(band[0])
	var b1: float = float(band[1])
	## the near lanes for the foot and horse, the far lanes for the guns
	var foot_band := [b0, b1]
	var gun_band := [b0, b1]
	if not gun.is_empty() and (not inf.is_empty() or not cav.is_empty()):
		var cut: float = lerpf(b0, b1, 0.5)
		foot_band = [b0, cut]
		gun_band = [cut, b1]
	var slots: Array = [] ## [figure, distance back from the front, depth]
	var per_rank: int = 4 if foot_band[1] - foot_band[0] > 0.6 else 2
	var x := 0.0
	for i in inf.size():
		var rank: int = i / per_rank
		var k: int = mini(per_rank, inf.size() - rank * per_rank)
		var lane: float = (float(i % per_rank) + 0.5) / float(k)
		slots.append([inf[i], float(rank) * float(GAP["inf"]) * 0.85, lerpf(foot_band[0], foot_band[1], lane * 0.8 + 0.1)])
	if not inf.is_empty():
		x = float(GAP["inf"]) * (0.85 * float((inf.size() - 1) / per_rank) + 1.0)
	for i in cav.size():
		slots.append([cav[i], x + float(i) * float(GAP["cav"]), lerpf(foot_band[0], foot_band[1], 0.5)])
	var per_col := 3 if gun_band[1] - gun_band[0] > 0.45 else 2
	for i in gun.size():
		var col: int = i / per_col
		var k2: int = mini(per_col, gun.size() - col * per_col)
		var lane2: float = (float(i % per_col) + 0.5) / float(k2)
		slots.append([gun[i], 95.0 + float(col) * float(GAP["gun"]), lerpf(gun_band[0], gun_band[1], lane2 * 0.8 + 0.1)])
	## close ranks if the array runs off its half of the field
	var deepest := 0.0
	for sl in slots:
		deepest = maxf(deepest, float(sl[1]))
	var room: float = maxf(80.0, size.x * 0.5 - FRONT - 90.0)
	var squeeze: float = minf(1.0, room / maxf(1.0, deepest))
	var front: float = FRONT + (40.0 if b0 > 0.01 else 0.0) ## the rear band stands a little back
	for i in slots.size():
		var f: Dictionary = slots[i][0]
		var depth: float = float(slots[i][2])
		var sc: float = 1.0 - depth * 0.3
		var y: float = size.y * (0.97 - depth * 0.52)
		var dx: float = (front + float(slots[i][1]) * squeeze) * sc
		var px: float = size.x * 0.5 - dx if side == 0 else size.x * 0.5 + dx
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
	var sc: float = float(f["scale"])
	if f["type"] == "gun" and burst("fort_explosion", f["cur"] + Vector2(0, -30 * sc), 240.0 * sc):
		return
	if burst("dust_kick", f["cur"] + Vector2(0, -6 * sc), (110.0 if f["type"] == "inf" else 150.0) * sc, randf() < 0.5, 0.12):
		return
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
		var dir := 1.0 if int(armies[ai]["side"]) == 0 else -1.0
		var mouth: Vector2 = g["cur"] + Vector2(dir * 150.0 * g["scale"], -110.0 * g["scale"])
		var at_shot := 0.15
		if _has("cannon_fire_kf"):
			_act(g, "fire", "cannon_fire_kf", _fire_len("cannon_fire_kf"))
			mouth = g["cur"] + _muzzle_of("cannon_fire_kf", g, dir < 0.0)
			at_shot = _shot_at("cannon_fire_kf")
		else:
			_act(g, "fire", "cannon_fire", 1.2)
		if not burst("cannon_blast", mouth, 300.0 * float(g["scale"]), dir > 0.0, at_shot):
			puffs.append({"pos": mouth, "t": -0.15, "big": true, "seed": randf() * TAU})
		return "cannon_big"
	var n := 0
	for f in shooters:
		if n >= 3:
			break
		match str(f["type"]):
			"inf":
				var dir2 := 1.0 if int(armies[ai]["side"]) == 0 else -1.0
				var kf: String = "grenadier_volley_kf" if _elite(f) else ("soldier_kneel_volley_kf" if randf() < 0.35 and _has("soldier_kneel_volley_kf") else "soldier_volley_kf")
				if _has(kf):
					_act(f, "fire", kf, _fire_len(kf))
					var at_kf: Vector2 = f["cur"] + _muzzle_of(kf, f, dir2 < 0.0)
					var t_kf: float = _shot_at(kf)
					var painted_kf: bool = burst("smoke_musket", at_kf, 150.0 * float(f["scale"]), dir2 > 0.0, t_kf)
					puffs.append({"pos": at_kf, "t": -t_kf, "big": false, "seed": randf() * TAU, "flash": true, "no_smoke": painted_kf})
				elif not _anims["soldier_aim"].is_empty():
					## up to the shoulder (or down on one knee), fire, kick, and back to the stance
					var pose: String = "soldier_kneel_aim" if randf() < 0.35 and not _anims["soldier_kneel_aim"].is_empty() else "soldier_aim"
					_act(f, "fire", pose, randf_range(0.75, 0.95))
					var mz: Vector2 = MUZZLE[pose] * float(f["scale"]) * float(SIZE["inf"]) / 0.86
					var at: Vector2 = f["cur"] + Vector2(dir2 * mz.x, mz.y)
					var painted: bool = burst("smoke_musket", at, 150.0 * float(f["scale"]), dir2 > 0.0, SHOT_AT)
					puffs.append({"pos": at, "t": -SHOT_AT, "big": false, "seed": randf() * TAU, "flash": true, "no_smoke": painted})
				else:
					_act(f, "fire", "soldier_fire", 0.85)
					puffs.append({"pos": f["cur"] + Vector2(dir2 * 40 * f["scale"], -62 * f["scale"]), "t": -0.3, "big": false, "seed": randf() * TAU})
				n += 1
			"cav":
				if randf() < 0.5:
					var ck: String = "cuirassier_charge_kf" if _elite(f) else "cavalry_charge_kf"
					if _has(ck):
						_act(f, "charge", ck, _kf_len(ck))
					else:
						_act(f, "charge", "cavalry_charge", 1.0)
					sound = "cavalry"
					n += 1
	if sound == "volley" and n == 1:
		sound = "shot" ## one man fires: one shot, not a volley
	return sound


func _elite(f: Dictionary) -> bool:
	return bool(armies[int(f["army"])].get("elite", false)) and bool(_elite_ok.get(str(f["type"]), false))


func _has(name: String) -> bool:
	return not (_anims.get(name, {}) as Dictionary).is_empty()


func _kf_len(name: String) -> float:
	## how long a keyframed move plays, at its own frame rate
	var an: Dictionary = _anims.get(name, {})
	return float(_len(an)) / maxf(1.0, float(an.get("fps", 12.0)))


func _muzzle_of(name: String, f: Dictionary, flip: bool) -> Vector2:
	## where the muzzle is when the sheet fires, from the feet (screen pixels)
	var an: Dictionary = _anims[name]
	var mz: Array = an.get("muzzle", [])
	if mz.size() < 2:
		return Vector2(0, -80.0 * float(f["scale"]))
	var h: float = FIG_H * 1.75 * float(f["scale"]) * float(SIZE[str(f["type"])]) / float(an["fill"])
	var w: float = h * float(an["fw"]) / float(an["fh"])
	var off := Vector2((float(mz[0]) - float(an["ax"])) * w, (float(mz[1]) - float(an["ay"])) * h)
	return Vector2(-off.x if flip else off.x, off.y)


const RAISE := 0.28 ## seconds a keyframed fire move takes to come up to the shot (the dice have spoken)


func _shot_at(name: String) -> float:
	## the raise is hurried so the shot lands with the dice; the rest plays at the sheet's own pace
	var an: Dictionary = _anims[name]
	return RAISE if int(an.get("shot", -1)) > 0 else 0.0


func _fire_len(name: String) -> float:
	var an: Dictionary = _anims[name]
	var shot: int = int(an.get("shot", -1))
	if shot <= 0:
		return _kf_len(name)
	return RAISE + float(_len(an) - shot) / maxf(1.0, float(an.get("fps", 12.0)))


func _fire_frame(an: Dictionary, t: float) -> int:
	var shot: int = int(an.get("shot", -1))
	if t < RAISE:
		return int(t / RAISE * float(shot))
	return shot + int((t - RAISE) * maxf(1.0, float(an.get("fps", 12.0))))


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
		if f["type"] == "inf":
			var ik: String = "grenadier_charge_kf" if _elite(f) else "soldier_charge_kf"
			if _has(ik):
				_act(f, "charge", ik, _kf_len(ik))
			elif not _elite(f) and not _anims["soldier_charge"].is_empty():
				_act(f, "charge", "soldier_charge", 0.9)
		elif f["type"] == "cav":
			var ck2: String = "cuirassier_charge_kf" if _elite(f) else "cavalry_charge_kf"
			if _has(ck2):
				_act(f, "charge", ck2, _kf_len(ck2))
			elif not _elite(f):
				_act(f, "charge", "cavalry_charge", 0.9)


func cheer(ai: int) -> void:
	for f in _alive(ai):
		match str(f["type"]):
			"inf":
				if _elite(f):
					continue ## the Guard doesn't cheer in a line infantryman's shako
				if _has("soldier_cheer_kf"):
					_act(f, "cheer", "soldier_cheer_kf", _kf_len("soldier_cheer_kf"))
				elif not _anims["soldier_cheer"].is_empty():
					_act(f, "cheer", "soldier_cheer", 1.4)
			"cav":
				if not _elite(f) and not _anims["cavalry_rear"].is_empty():
					_act(f, "cheer", "cavalry_rear", 1.3)


func reload(ai: int) -> void:
	for f in _alive(ai):
		if f["state"] == "idle" and randf() < 0.4:
			match str(f["type"]):
				"inf":
					if _elite(f):
						continue
					if _has("soldier_reload_kf"):
						_act(f, "reload", "soldier_reload_kf", _kf_len("soldier_reload_kf"))
					elif not _anims["soldier_reload"].is_empty():
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
				var lie := 0.75
				if f["type"] == "inf" and not _elite(f) and _has("soldier_fall_kf"):
					var fa: Dictionary = _anims["soldier_fall_kf"]
					var down: int = int(fa.get("down", -1))
					lie = float((down if down >= 0 else _len(fa) - 1) + 1) / maxf(1.0, float(fa.get("fps", 12.0)))
				if float(f["t"]) > lie:
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
	var bi := bursts.size() - 1
	while bi >= 0:
		var b: Dictionary = bursts[bi]
		b["t"] = float(b["t"]) + delta
		var sh: Dictionary = _fx_sheet(str(b["name"]))
		var over: bool = float(b["t"]) >= float(b.get("dur", 0.0)) if float(b.get("dur", 0.0)) > 0.0 else float(b["t"]) * float(sh.get("fps", 12.0)) >= float(_len(sh))
		if sh.is_empty() or over:
			bursts.remove_at(bi)
		bi -= 1
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


func _idle_of(type: String, elite: bool = false) -> String:
	if elite:
		return {"inf": "grenadier_idle", "cav": "cuirassier_idle"}.get(type, "cannon_idle")
	return {"inf": "soldier_idle", "cav": "cavalry_idle", "gun": "cannon_idle"}[type]


func _march_of(type: String, elite: bool = false) -> String:
	if elite:
		return {"inf": "grenadier_march", "cav": "cuirassier_gallop"}.get(type, "cannon_idle")
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
		var el: bool = _elite(f)
		var an: Dictionary = _a(_idle_of(type, el))
		var fi := 0
		var tilt := 0.0
		match str(f["state"]):
			"idle", "merge":
				fi = _pick(an, int((_clock + float(f["phase"])) * 9.0), true)
			"march", "flee":
				an = _a(_march_of(type, el), _idle_of(type, el))
				fi = _pick(an, int((_clock + float(f["phase"])) * (15.0 if type == "cav" else 13.0)), true)
				if f["state"] == "flee":
					flip = not flip
			"fire", "charge", "cheer", "reload":
				an = _a(str(f["anim"]), _idle_of(type, el))
				var k: float = float(f["t"]) / maxf(0.1, float(f.get("dur", 1.0)))
				if str(f["anim"]).ends_with("_aim"):
					## the aim: snap up, fire, kick back, steady, and lower again
					var t: float = float(f["t"])
					var dur: float = float(f.get("dur", 0.9))
					var into: float = clampf(t / 0.05, 0.0, 1.0)
					var outof: float = clampf((dur - t) / 0.12, 0.0, 1.0)
					var aim_a: float = minf(into, outof)
					var dir3: float = -1.0 if flip else 1.0
					var kick := 0.0
					if t > SHOT_AT:
						kick = exp(-(t - SHOT_AT) / 0.07)
					var foot: Vector2 = f["cur"] + Vector2(-dir3 * 7.0 * kick * float(f["scale"]), 0)
					if aim_a < 1.0:
						var idle: Dictionary = _a("soldier_idle")
						_draw_anim(idle, _pick(idle, int((_clock + float(f["phase"])) * 9.0), true), f["cur"], float(f["scale"]), flip, col, float(f["alpha"]) * (1.0 - aim_a), 0.0, float(SIZE[type]))
					_draw_anim(an, 0, foot, float(f["scale"]), flip, col, float(f["alpha"]) * aim_a, -dir3 * 0.035 * kick, float(SIZE[type]))
					continue
				if f["state"] == "fire" and int(an.get("shot", -1)) > 0:
					fi = _pick(an, _fire_frame(an, float(f["t"])), false)
				elif f["state"] == "charge" and (str(f["anim"]).ends_with("charge")):
					fi = _pick(an, int((_clock + float(f["phase"])) * 14.0), true)
				else:
					fi = _pick(an, int(k * float(_len(an))), false)
			"fall", "dead":
				if type == "inf" and not el and _has("soldier_fall_kf"):
					## v1.9: a real fall, keyframed from the stand to our fallen pose
					var fa: Dictionary = _anims["soldier_fall_kf"]
					var down: int = int(fa.get("down", -1))
					var last: int = (down if down >= 0 else _len(fa) - 1)
					var kf2: int = mini(int(float(f["t"]) * maxf(1.0, float(fa.get("fps", 12.0)))), last) if f["state"] == "fall" else last
					var dk: float = clampf(float(kf2) / maxf(1.0, float(last)), 0.0, 1.0)
					_draw_anim(fa, _pick(fa, kf2, false), f["cur"], float(f["scale"]), flip, col.darkened(0.4 * dk), float(f["alpha"]), 0.0, float(SIZE[type]))
					continue
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
	for b in bursts:
		var bt: float = float(b["t"])
		if bt < 0.0:
			continue
		var sh: Dictionary = _fx_sheet(str(b["name"]))
		if sh.is_empty():
			continue
		var k4: int = int(bt * float(sh["fps"]))
		var fi4: int = _pick(sh, k4, bool(sh["loop"]))
		var bh: float = float(b["px"])
		var bw: float = bh * float(sh["fw"]) / float(sh["fh"])
		var bd: float = float(b.get("dur", 0.0))
		var fade: float = clampf((bd - bt) / 0.8, 0.0, 1.0) * clampf(bt / 0.3, 0.0, 1.0) if bd > 0.0 else clampf((float(_len(sh)) - bt * float(sh["fps"])) / 4.0, 0.0, 1.0)
		draw_set_transform(b["pos"], 0.0, Vector2(-1 if bool(b["flip"]) else 1, 1))
		draw_texture_rect_region(sh["tex"], Rect2(Vector2(-bw * float(sh["ax"]), -bh * float(sh["ay"])), Vector2(bw, bh)), _frame(sh, fi4), Color(1, 1, 1, 0.92 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for p in puffs:
		var t: float = float(p["t"])
		if t < 0.0:
			continue
		var big: bool = p["big"]
		if bool(p.get("no_smoke", false)):
			if bool(p.get("flash", false)) and t < 0.08:
				var ft2: float = 1.0 - t / 0.08
				draw_circle(p["pos"], 9.0 * (0.6 + 0.4 * ft2), Color(1.0, 0.95, 0.75, 0.95 * ft2))
			continue
		var r: float = (30.0 if big else 11.0) + t * (80.0 if big else 26.0)
		var a2: float = clampf((0.55 if big else 0.42) - t * (0.26 if big else 0.3), 0.0, 0.55)
		var c: Vector2 = p["pos"] + Vector2(t * 12.0, -t * 22.0)
		for k2 in 6:
			var off := Vector2.from_angle(float(k2) * 1.05 + float(p.get("seed", 0.0))) * r * 0.5
			var rr: float = r * (0.75 + 0.07 * k2)
			draw_texture_rect(_soft, Rect2(c + off - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(0.9, 0.89, 0.85, a2 * (0.6 + 0.07 * k2)))
		if t < (0.14 if big else 0.09):
			draw_circle(p["pos"], 16.0 if big else 8.0, Color(1.0, 0.78, 0.3, 0.9 * (1.0 - t / (0.14 if big else 0.09))))
		if bool(p.get("flash", false)) and t < 0.08:
			## the musket's own flash: a hot star at the muzzle, never tinted
			var ft: float = 1.0 - t / 0.08
			var fr: float = 13.0 * (0.6 + 0.4 * ft)
			for k3 in 5:
				var ang: float = float(p.get("seed", 0.0)) + float(k3) * TAU / 5.0
				draw_line(p["pos"], p["pos"] + Vector2.from_angle(ang) * fr * 1.6, Color(1.0, 0.85, 0.45, 0.8 * ft), 3.0, true)
			draw_circle(p["pos"], fr * 0.7, Color(1.0, 0.95, 0.75, 0.95 * ft))
			draw_circle(p["pos"], fr * 0.35, Color(1, 1, 1, ft))


func _draw_anim(an: Dictionary, idx: int, foot: Vector2, sc: float, flip: bool, col: Color, alpha: float, tilt: float, mult: float) -> void:
	## drawn from the feet: a man stands FIG_H x 1.75 x scale tall, other pieces by SIZE
	var h: float = FIG_H * 1.75 * sc * mult / float(an["fill"])
	var w: float = h * float(an["fw"]) / float(an["fh"])
	draw_set_transform(foot, tilt, Vector2(-1 if flip else 1, 1))
	draw_texture_rect_region(an["tex"], Rect2(Vector2(-w * float(an["ax"]), -h * float(an["ay"])), Vector2(w, h)), _frame(an, idx), Color(col, col.a * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tint(pid: String) -> Color:
	return Style.seat_color(pid).lightened(0.18) if pid != "neutral" else Color(0.72, 0.7, 0.66)
