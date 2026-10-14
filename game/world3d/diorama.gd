## A battle staged on the 3D world (v2.0). Every army stands where it came from: an invading
## column at the border it crossed, or rowed ashore in longboats over a sea lane; the defender at
## the land's heart, split into a group facing every front in proportion (as the rule splits
## him); a border clash on the border itself. Painted tin soldiers in their commander's colours,
## in poses (Ludo's, tools/ludo/v20_content.py): they hop in like toys pushed across a table,
## drop to aim, fire with a flash and a crack each, topple when the dice say so, and stay down.
## An officer leads each group, a drummer beats behind it, a gunner stands at each cannon.
extends Node3D

const DiceStage := preload("res://game/ui/dice_stage.gd")

const FIG := 18.0 ## a man's height, in world units (map pixels)
const DIE := 8.0
## every model, its height (a gun's and a boat's: its length) in men, the hue of the coat the game
## repaints (-1: none), and the turn (degrees) that faces it down +Z
const MODELS := {
	"inf": ["res://assets/models/infantry.glb", 1.0, 0.0, 0.0],
	"inf_aim": ["res://assets/models/diorama/inf_aim.glb", 1.0, 0.0, 0.0],
	"inf_kneel": ["res://assets/models/diorama/inf_kneel.glb", 0.78, 0.0, 0.0],
	"inf_charge": ["res://assets/models/diorama/inf_charge.glb", 0.95, 0.0, 0.0],
	"inf_march": ["res://assets/models/diorama/inf_march.glb", 1.0, 0.0, 0.0],
	"officer": ["res://assets/models/diorama/officer.glb", 1.12, 0.0, 0.0],
	"drummer": ["res://assets/models/diorama/drummer.glb", 1.0, 0.0, 0.0],
	"gunner": ["res://assets/models/diorama/gunner.glb", 1.2, 0.0, 0.0],
	"flag": ["res://assets/models/flag.glb", 1.05, 0.0, 0.0],
	"cav": ["res://assets/models/cavalry.glb", 1.3, 0.55, 0.0],
	"cav_charge": ["res://assets/models/diorama/cav_charge.glb", 1.25, 0.55, 0.0],
	"gun": ["res://assets/models/cannon.glb", 1.35, -1.0, -90.0], ## its muzzle is down +X
	"boat": ["res://assets/models/diorama/boat.glb", 3.2, -1.0, 0.0],
	## round two: the rest of a battle's life
	"inf_cheer": ["res://assets/models/diorama/inf_cheer.glb", 1.08, 0.0, 0.0],
	"inf_reload": ["res://assets/models/diorama/inf_reload.glb", 1.0, 0.0, 0.0],
	"inf_flee": ["res://assets/models/diorama/inf_flee.glb", 1.0, 0.0, 0.0],
	"inf_fallen": ["res://assets/models/diorama/inf_fallen.glb", 1.05, 0.0, 0.0],
	"gunner_ram": ["res://assets/models/diorama/gunner_ram.glb", 1.15, 0.0, 0.0],
	"gunner_fire": ["res://assets/models/diorama/gunner_fire.glb", 1.15, 0.0, 0.0],
	"general": ["res://assets/models/diorama/general.glb", 1.4, 0.0, 0.0],
}
const LONG := {"gun": "x", "boat": "z", "inf_fallen": "max"} ## sized by their length (along this axis, as modelled), not height
const GAP := {"inf": 0.95, "cav": 1.5, "gun": 2.0} ## file spacing, in men's heights
const FALL_SOUND := {"grass": "fall_grass", "forest": "fall_grass", "moor": "fall_mud", "coast": "fall_sand", "desert": "fall_sand",
	"snow": "fall_snow", "ash": "fall_stone", "mountain": "fall_stone"}

var wv: Node3D ## world_view
var armies: Array = [] ## {pid, color, n, n0, groups: [{at, dir, cross, by_sea, sea_from, share, foe}], fled}
var figs: Array = [] ## see _new_fig
var boats: Array = [] ## {node, from, to, t, dur, army, group, landed}
var puffs: Array = []
var flashes: Array = []
var tracers: Array = [] ## v2.2: shots in the air {node, from, to, t, dur, arc, gun, aim, army (who fired), foe (at whom)}
var ground := "grass" ## the land's terrain: what a fall sounds like
var heart := Vector2.ZERO
var shake := 0.0 ## a cannon's thump, for the camera
var _meshes := {} ## kind -> {mesh, tex, aabb, h, hue, yaw}
var _soft: GradientTexture2D
var _clock := 0.0
var _shot_at := -1.0 ## when the last volley's first musket goes off (a fall follows its shot)
var _drum_t := 0.0
var live := false ## the fight is on: the drum beats
var quiet := false ## no sounds (tests)
var extras := true ## an officer, a drummer and the colours with every group (false: garrisons on the board)
var size_mult := 1.0 ## the figures' size (the board's garrisons are game pieces, seen from far off: bigger)
var tables: Array = []
var _dice_layer: CanvasLayer


func _ready() -> void:
	for k in MODELS.keys():
		var path: String = MODELS[k][0]
		if not ResourceLoader.exists(path):
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		var mi: MeshInstance3D = _find_mesh(inst)
		if mi != null:
			var mat = mi.mesh.surface_get_material(0)
			_meshes[k] = {"mesh": mi.mesh, "tex": mat.albedo_texture if mat is StandardMaterial3D else null, "aabb": mi.mesh.get_aabb(),
				"h": float(MODELS[k][1]), "hue": float(MODELS[k][2]), "yaw": deg_to_rad(float(MODELS[k][3]))}
		inst.free()
	_soft = GradientTexture2D.new()
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	_soft.gradient = g


func has_model(kind: String) -> bool:
	return _meshes.has(kind)


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null


# ------------------------------------------------------------------ where everyone stands

func crossing(to: String, from: String) -> Vector2:
	## Where `from` meets `to`: the middle of their shared border, a step onto `to`'s side. Over
	## a sea lane, the beach the lane lands on.
	var art = wv.art
	var known: Variant = wv.terrain.crossing(to, from)
	if known != null:
		return (known as Vector2) + ((art.anchors[to] as Vector2) - (known as Vector2)).normalized() * 4.0
	var lane: Variant = sea_lane(to, from)
	if lane != null:
		return lane[1]
	return (art.anchors[to] as Vector2).lerp(art.anchors.get(from, art.anchors[to]), 0.5)


func sea_lane(to: String, from: String) -> Variant:
	## [the origin's beach, the target's beach] when `from` reaches `to` over the sea
	for l in wv.art.lanes:
		if l["a"] == to and l["b"] == from:
			return [l["pb"], l["pa"]]
		if l["b"] == to and l["a"] == from:
			return [l["pa"], l["pb"]]
	return null


func front_group(to: String, from: String, n: int) -> Dictionary:
	## a column coming into `to` from `from`: where it halts, which way it faces, and how it came
	var h: Vector2 = wv.art.anchors[to]
	var x: Vector2 = crossing(to, from)
	var dir: Vector2 = (h - x).normalized()
	var dist: float = h.distance_to(x)
	var lane: Variant = sea_lane(to, from) if wv.terrain.crossing(to, from) == null else null
	var g := {"cross": x, "dir": dir, "dist": dist, "share": n, "by_sea": lane != null}
	## the column halts halfway in, a few men's heights from the defenders (further off a beach)
	g["at"] = x + dir * dist * (0.55 if lane != null else 0.5)
	if lane != null:
		g["sea_from"] = lane[0]
	return g


func clear() -> void:
	for f in figs:
		(f["node"] as Node3D).queue_free()
	for p in puffs:
		(p["node"] as Node3D).queue_free()
	for b in boats:
		(b["node"] as Node3D).queue_free()
	for tr in tracers:
		(tr["node"] as Node3D).queue_free()
	figs.clear()
	puffs.clear()
	tracers.clear()
	boats.clear()
	armies.clear()
	live = false
	if not quiet:
		Audio.field_loop("")


func place(list: Array) -> void:
	## list: [{pid, color, n, groups: [{at, dir, share, cross?, dist?, by_sea?, sea_from?, foe?}]}]
	## (the theater's armies, in its order: the shares of an army's groups add up to its n)
	clear()
	for ai in list.size():
		var a: Dictionary = list[ai]
		armies.append({"pid": a["pid"], "color": a["color"], "n": int(a["n"]), "n0": maxi(1, int(a["n"])), "groups": a["groups"], "fled": false})
		for gi in (a["groups"] as Array).size():
			_form(ai, gi, true)
	if not boats.is_empty() and not quiet:
		Audio.field_loop("row_oars", -10.0)


func regarrison(list: Array) -> void:
	## The board's garrisons kept up to date without a fresh march (list: as place's, a land a
	## group, in the same order every time). A land that changed hands marches in afresh in its new
	## colours. v2.0.2: one that grew or shrank, or whose spot moved (it follows the token's size
	## as the camera zooms), keeps its men: the new ones step in from just behind, the ones gone are
	## lifted off the table, and the rest shuffle to their places. It used to re-form, every man
	## marching in again, on every recruit placed (and every few frames while the camera moved).
	if armies.size() != list.size():
		place(list)
		return
	for ai in list.size():
		var a: Dictionary = armies[ai]
		var w: Dictionary = list[ai]
		var n: int = int(w["n"])
		var moved: bool = ((a["groups"][0]["at"]) as Vector2).distance_to(w["groups"][0]["at"]) > 1.0
		var colours_changed: bool = bool(a["groups"][0].get("colours", false)) != bool(w["groups"][0].get("colours", false))
		var train_changed: bool = int(a["groups"][0].get("horse", 0)) != int(w["groups"][0].get("horse", 0)) or int(a["groups"][0].get("guns", 0)) != int(w["groups"][0].get("guns", 0))
		if a["color"] == w["color"] and int(a["n"]) == n and not moved and not colours_changed and not train_changed:
			continue
		if a["color"] == w["color"] and str(a["pid"]) == str(w["pid"]) and int(a["n"]) > 0 and n > 0:
			a["n"] = n
			a["n0"] = maxi(1, n)
			a["groups"] = w["groups"]
			_muster(ai)
			continue
		for i in range(figs.size() - 1, -1, -1):
			if int(figs[i]["army"]) == ai:
				(figs[i]["node"] as Node3D).queue_free()
				figs.remove_at(i)
		a["pid"] = w["pid"]
		a["color"] = w["color"]
		a["n"] = n
		a["n0"] = maxi(1, n)
		a["groups"] = w["groups"]
		for gi in (a["groups"] as Array).size():
			_form(ai, gi, false)


func _muster(ai: int) -> void:
	## a garrison (one group) to its count where it stands: lift off what's gone (the last of each
	## kind), step in what's new from just behind, shuffle the rest to their places
	for i in range(figs.size() - 1, -1, -1):
		var f0: Dictionary = figs[i]
		if int(f0["army"]) == ai and not f0["alive"] and f0["state"] == "lift" and float(f0["t"]) > 0.6:
			(f0["node"] as Node3D).queue_free()
			figs.remove_at(i)
	var g: Dictionary = armies[ai]["groups"][0]
	var want: Dictionary = _want(g)
	for k in ["inf", "cav", "gun"]:
		var line: Array = figs.filter(func(f): return int(f["army"]) == ai and f["alive"] and f["kind"] == k)
		for i in range(int(want[k]), line.size()):
			_lift(line[i])
	if not bool(g.get("colours", false)):
		for f in figs:
			if int(f["army"]) == ai and f["alive"] and f["kind"] == "flag":
				_lift(f)
	var had := {}
	for f in figs:
		if int(f["army"]) == ai:
			had[(f["node"] as Node3D).get_instance_id()] = true
	_form(ai, 0, false)
	var dir: Vector2 = g["dir"]
	for f in figs:
		if int(f["army"]) != ai or not f["alive"]:
			continue
		if not had.has((f["node"] as Node3D).get_instance_id()):
			f["from"] = (f["home"] as Vector2) - dir * FIG * size_mult * 0.9
			f["at"] = f["from"]
			f["dur"] = 0.8
		elif (f["state"] == "stand" or f["state"] == "march") and (f["at"] as Vector2).distance_to(f["home"]) > 1.0:
			var home: Vector2 = _dry(f["home"], dir)
			if wv.scenery != null:
				home = wv.scenery.clear_of(home, FIG * size_mult * 0.4)
			f["home"] = home
			f["from"] = f["at"]
			f["state"] = "march"
			f["t"] = 0.0
			f["delay"] = 0.0
			f["dur"] = 0.6
		_place(f)


func _lift(f: Dictionary) -> void:
	## taken off the table: up and away (a garrison grown smaller)
	f["alive"] = false
	f["state"] = "lift"
	f["t"] = 0.0


func _want(g: Dictionary) -> Dictionary:
	## the pieces a group stands, by kind: its men (pieces) and, on the board, the train an army
	## that size brings along (v2.0.2: horse and guns as well as the men, not in their place)
	var want: Dictionary = pieces(int(g["share"]))
	want["cav"] = int(want["cav"]) + int(g.get("horse", 0))
	want["gun"] = int(want["gun"]) + int(g.get("guns", 0))
	return want


func arrival() -> float:
	## seconds until everyone has reached their place
	var t := 0.0
	for b in boats:
		t = maxf(t, float(b["dur"]) + 2.4)
	for f in figs:
		if f["state"] == "march":
			t = maxf(t, 2.6 + float(f["delay"]))
	return t


static func battle_train(n: int) -> Dictionary:
	## v2.1: the train a big army brings into battle as well as its men (the owner: "i want to see
	## what we can do with a big battle"): two horsemen from 14, a third from 26; a gun from 18, a
	## second from 30. They stand with its biggest group and fire and charge with it, but they aren't
	## its count: they fall only when the whole army does (not with their group, RV-002 F6).
	return {"horse": (2 if n >= 14 else 0) + (1 if n >= 26 else 0), "guns": (1 if n >= 18 else 0) + (1 if n >= 30 else 0)}


static func pieces(n: int) -> Dictionary:
	## a cannon for ten and a horse for five once the ranks are full: eight to twelve men always stand
	var guns := 0
	var horse := 0
	if n > 12:
		guns = mini((n - 8) / 10, 3)
		horse = (n - 8 - guns * 10) / 5
	return {"inf": n - guns * 10 - horse * 5, "cav": horse, "gun": guns}


func _form(ai: int, gi: int, fresh: bool) -> void:
	## draw a group up: the men in ranks at the front, horse and guns behind, the officer before
	## them, the drummer and the colours at the rear. New pieces (making change, or the first
	## march) come in from behind.
	var a: Dictionary = armies[ai]
	var g: Dictionary = a["groups"][gi]
	var at: Vector2 = g["at"]
	var dir: Vector2 = g["dir"]
	var side := Vector2(-dir.y, dir.x)
	var want: Dictionary = _want(g)
	var have := {"inf": [], "cav": [], "gun": []}
	for f in figs:
		if int(f["army"]) == ai and int(f["group"]) == gi and f["alive"] and have.has(f["kind"]):
			(have[f["kind"]] as Array).append(f)
	var base: Dictionary = pieces(int(g["share"]))
	for k in ["inf", "cav", "gun"]:
		var counting := 0
		for f0 in have[k]:
			if bool(f0["counts"]):
				counting += 1
		for i in range(int(want[k]) - (have[k] as Array).size()):
			var nf := _new_fig(ai, gi, k, fresh)
			if counting < int(base[k]):
				counting += 1 ## the count's own pieces first
			elif bool(g.get("train", false)):
				nf["counts"] = false ## the train: horse and guns as well as the men, not in their place
			(have[k] as Array).append(nf)
	var men: Array = have["inf"]
	var files: int = clampi(int(ceil(sqrt(float(men.size()) * 1.6))), 1, 6)
	for i in men.size():
		var rank: int = i / files
		var file: int = i % files
		var in_rank: int = mini(files, men.size() - rank * files)
		var off: float = (float(file) - float(in_rank - 1) * 0.5) * GAP["inf"] * FIG * size_mult
		men[i]["home"] = at + side * off - dir * float(rank) * FIG * 1.05 * size_mult
		men[i]["rank"] = rank
	var ranks: int = int(ceil(float(men.size()) / float(files)))
	var back: float = (float(ranks) * FIG * 1.05 + FIG * 0.6) * size_mult
	var heavy: Array = (have["cav"] as Array) + (have["gun"] as Array)
	if bool(g.get("beside", false)):
		## the board's train, beside the men on the side away from the token: the guns (low) in
		## front, the horse (tall) behind them and half a place over, so the camera sees both
		var x0: float = float(files - 1) * 0.5 * GAP["inf"] * FIG * size_mult + FIG * size_mult * 0.85
		var rows := {"cav": 0, "gun": 0}
		for j in heavy.size():
			var hk: String = heavy[j]["kind"]
			var col_i: int = int(rows[hk])
			rows[hk] = col_i + 1
			var dx: float = x0 + (float(col_i) + (0.45 if hk == "cav" else 0.0)) * FIG * size_mult * 0.9
			heavy[j]["home"] = at - side * dx - dir * FIG * size_mult * (0.55 if hk == "cav" else -0.45)
			heavy[j]["rank"] = 9
	for j in heavy.size():
		if bool(g.get("beside", false)):
			break
		var k: String = heavy[j]["kind"]
		var off: float = (float(j) - float(heavy.size() - 1) * 0.5) * GAP[k] * FIG * size_mult
		heavy[j]["home"] = at + side * off - dir * back
		heavy[j]["rank"] = 9
	if not extras and bool(g.get("colours", false)) and int(g["share"]) > 0 and has_model("flag"):
		## a capital's garrison on the board carries the colours
		var has_flag := false
		for f in figs:
			if int(f["army"]) == ai and int(f["group"]) == gi and f["kind"] == "flag":
				has_flag = true
		if not has_flag:
			var cf := _new_fig(ai, gi, "flag", fresh)
			cf["home"] = at - dir * (back + FIG * size_mult * 0.2) + side * FIG * size_mult * 0.6
			cf["counts"] = false
	if fresh and extras and int(g["share"]) > 0:
		## the officer, the drummer and the colours: they lead and they beat, and they don't count
		var deep: float = back + (FIG * 1.7 if not heavy.is_empty() else FIG * 0.3)
		var extras := [["officer", at + dir * FIG * 1.1 + side * FIG * 0.35], ["drummer", at - dir * deep - side * FIG * 0.5],
			["flag", at - dir * deep + side * FIG * 0.5]]
		if gi == 0 and has_model("general"):
			## the commander himself, mounted, behind his army: the man who throws its dice
			extras.append(["general", at - dir * (deep + FIG * 2.6) + side * FIG * 1.4])
		for e in extras:
			var f := _new_fig(ai, gi, e[0], true)
			f["home"] = e[1]
			f["counts"] = false
		for gun in have["gun"]:
			var gf := _new_fig(ai, gi, "gunner", true)
			gf["home"] = (gun["home"] as Vector2) + side * FIG * 0.9 - dir * FIG * 0.4
			gf["counts"] = false
	## the march in: from behind the border, or from the boats
	for f in figs:
		if int(f["army"]) != ai or int(f["group"]) != gi or f["state"] != "new":
			continue
		var home: Vector2 = _dry(f["home"], dir)
		if wv.scenery != null:
			home = wv.scenery.clear_of(home, FIG * size_mult * 0.4) ## nobody forms up inside a wall
		f["home"] = home
		if fresh and bool(g.get("by_sea", false)):
			f["state"] = "boat"
		elif fresh:
			var start: Vector2 = home - dir * (float(g.get("dist", 120.0)) * 0.45 + FIG * 2.0)
			f["from"] = _dry(start, dir)
			f["at"] = f["from"]
			f["state"] = "march"
		else:
			f["from"] = home - dir * FIG * 3.0
			f["at"] = f["from"]
			f["state"] = "march"
			f["delay"] = 0.0
	if fresh and bool(g.get("by_sea", false)):
		_embark(ai, gi)
	for f in figs:
		if int(f["army"]) == ai and int(f["group"]) == gi:
			_place(f)


func _dry(p: Vector2, dir: Vector2) -> Vector2:
	## nobody stands in the sea: a spot in the water steps inland
	var tries := 0
	while wv.terrain.height_at(p) < 1.2 and tries < 40:
		p += dir * FIG * 0.5
		tries += 1
	return p


func _new_fig(ai: int, gi: int, kind: String, fresh: bool) -> Dictionary:
	var a: Dictionary = armies[ai]
	var g: Dictionary = a["groups"][gi]
	var f := {"army": ai, "group": gi, "kind": kind, "home": g["at"], "from": g["at"], "at": g["at"], "face": g["dir"],
		"state": "new", "t": 0.0, "delay": randf() * 0.4 if fresh else 0.0, "alive": true, "counts": true, "pose": "",
		"rank": 0, "boat": -1, "seat": Vector2.ZERO}
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/world3d/tin.gdshader")
	mat.set_shader_parameter("team", a["color"])
	mi.material_override = mat
	root.add_child(mi)
	add_child(root)
	f["node"] = root
	f["mi"] = mi
	_pose(f, _rest(kind))
	figs.append(f)
	return f


static func _length(aabb: AABB, axis: String) -> float:
	if axis == "max":
		return maxf(aabb.size.x, aabb.size.z)
	return aabb.size.x if axis == "x" else aabb.size.z


func _rest(kind: String) -> String:
	return "inf" if kind == "inf" else kind


func _pose(f: Dictionary, pose: String) -> void:
	## dress the figure in a pose (a model), falling back to the standing one
	if not _meshes.has(pose):
		pose = _rest(str(f["kind"])) if _meshes.has(_rest(str(f["kind"]))) else "inf"
	if f["pose"] == pose:
		return
	f["pose"] = pose
	var m: Dictionary = _meshes[pose]
	var mi: MeshInstance3D = f["mi"]
	mi.mesh = m["mesh"]
	var mat: ShaderMaterial = mi.material_override
	mat.set_shader_parameter("albedo_tex", m["tex"])
	var hue: float = m["hue"]
	var col: Color = armies[int(f["army"])]["color"]
	mat.set_shader_parameter("key_hue", maxf(hue, 0.0))
	## a redcoat model in the red seat's colour stays as painted
	mat.set_shader_parameter("repaint", hue >= 0.0 and not (hue == 0.0 and (col.h < 0.06 or col.h > 0.96) and col.s > 0.6))
	var aabb: AABB = m["aabb"]
	var sc: float = FIG * size_mult * float(m["h"]) / (_length(aabb, LONG[pose]) if LONG.has(pose) else aabb.size.y)
	mi.scale = Vector3.ONE * sc
	mi.rotation = Vector3(0.0, float(m["yaw"]), 0.0)
	mi.position = Vector3(0.0, -aabb.position.y * sc, 0.0) ## feet on the root


# ------------------------------------------------------------------ boats

func _embark(ai: int, gi: int) -> void:
	## a column over a sea lane comes in longboats: from the far shore, rowed to the beach
	var g: Dictionary = armies[ai]["groups"][gi]
	var land: Vector2 = g["cross"]
	var sea: Vector2 = g.get("sea_from", land - (g["dir"] as Vector2) * 300.0)
	var dir: Vector2 = (land - sea).normalized()
	var side := Vector2(-dir.y, dir.x)
	var riders: Array = figs.filter(func(f): return int(f["army"]) == ai and int(f["group"]) == gi and f["state"] == "boat")
	var nb: int = clampi(int(ceil(float(riders.size()) / 5.0)), 1, 4)
	var dur: float = clampf(sea.distance_to(land) / 70.0, 3.0, 5.5)
	for b in nb:
		var off: float = (float(b) - float(nb - 1) * 0.5) * FIG * 2.4
		var to: Vector2 = land - dir * FIG * 1.2 + side * off
		var from: Vector2 = sea + dir * FIG * 2.0 + side * off
		var node := _boat_node(armies[ai]["color"])
		boats.append({"node": node, "from": from, "to": to, "dir": dir, "t": -float(b) * 0.25, "dur": dur, "army": ai, "group": gi, "landed": false})
	for i in riders.size():
		var f: Dictionary = riders[i]
		var b: int = i % nb
		var seat: int = i / nb
		f["boat"] = boats.size() - nb + b
		f["seat"] = Vector2(0.0, (float(seat) - 2.0) * FIG * 0.55)


func _boat_node(col: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	if _meshes.has("boat"):
		var m: Dictionary = _meshes["boat"]
		mi.mesh = m["mesh"]
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = m["tex"]
		mat.roughness = 0.5
		mi.material_override = mat
		var aabb: AABB = m["aabb"]
		var sc: float = FIG * float(m["h"]) / _length(aabb, "z")
		mi.scale = Vector3.ONE * sc
		mi.rotation = Vector3(0.0, float(m["yaw"]), 0.0)
		mi.position = Vector3(0.0, -aabb.position.y * sc - FIG * 0.18, 0.0)
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(FIG * 0.9, FIG * 0.35, FIG * 3.0)
		mi.mesh = bm
		var mat2 := StandardMaterial3D.new()
		mat2.albedo_color = Color(0.2, 0.24, 0.34)
		mi.material_override = mat2
		mi.position = Vector3(0, FIG * 0.05, 0)
	root.add_child(mi)
	## a pennant in the commander's colour at the stern
	var pen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(FIG * 0.7, FIG * 0.4)
	pen.mesh = q
	var pm := StandardMaterial3D.new()
	pm.albedo_color = col
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pen.material_override = pm
	pen.position = Vector3(FIG * 0.35, FIG * 1.1, -FIG * 1.4)
	root.add_child(pen)
	add_child(root)
	return root


# ------------------------------------------------------------------ the theater's moves

func group_against(ai: int, foe: int) -> int:
	## which of ai's groups fights army foe (the defender has one per front)
	var gs: Array = armies[ai]["groups"]
	for gi in gs.size():
		if int(gs[gi].get("foe", -1)) == foe:
			return gi
	return 0


func volley(ai: int, foe: int = -1) -> String:
	## army ai wins a volley: its front rank drops to aim and fires (a crack each), or a gun
	## speaks. Returns what it did ("cannon", "cavalry", "volley", "shot").
	if ai < 0 or ai >= armies.size():
		return ""
	var gi: int = group_against(ai, foe) if foe >= 0 else 0
	var target: Vector2 = _target_of(ai, gi, foe)
	var mine: Array = figs.filter(func(f): return int(f["army"]) == ai and int(f["group"]) == gi and f["alive"] and f["state"] == "stand")
	var guns: Array = mine.filter(func(f): return f["kind"] == "gun")
	## v2.2: the balls are seen to fly, so a man falls when the first one gets there
	var reach: float = (armies[ai]["groups"][gi]["at"] as Vector2).distance_to(target)
	_shot_at = _clock + 0.22 + _flight(reach)
	if not guns.is_empty() and randf() < 0.45:
		var gun: Dictionary = guns[randi() % guns.size()]
		_aim(gun, target)
		gun["state"] = "fire"
		gun["t"] = -0.1
		gun["fired"] = false
		gun["target"] = target
		gun["foe"] = foe
		_shot_at = _clock + 0.28 + BALL_FLIGHT
		## its gunner touches it off, then rams the next charge home
		var crew: Array = figs.filter(func(f): return int(f["army"]) == ai and int(f["group"]) == gi and f["alive"] and f["kind"] == "gunner")
		if not crew.is_empty():
			crew.sort_custom(func(p, q): return (p["at"] as Vector2).distance_to(gun["at"]) < (q["at"] as Vector2).distance_to(gun["at"]))
			crew[0]["state"] = "crew"
			crew[0]["t"] = -0.1
		return "cannon"
	var men: Array = mine.filter(func(f): return f["kind"] == "inf")
	men.sort_custom(func(p, q): return int(p["rank"]) < int(q["rank"]))
	var n: int = mini(men.size(), 6)
	var first := INF
	for i in n:
		var f: Dictionary = men[i]
		_aim(f, target)
		## each man picks his mark in the ranks across the way (v2.2: his ball is seen to go there)
		f["target"] = target + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * FIG * 1.1
		f["foe"] = foe
		f["state"] = "fire"
		f["t"] = -randf() * 0.16
		f["fired"] = false
		f["kneel"] = int(f["rank"]) == 0 and i % 2 == 0
		## when his ball gets there: his trigger (FIRE_AT after his turn comes), then its flight
		first = minf(first, FIRE_AT - float(f["t"]) + _flight((f["at"] as Vector2).distance_to(f["target"])))
	if n > 0:
		_shot_at = _clock + first - 0.06 ## (RV-005 F5) the first man falls as the first ball arrives (set_count adds 0.06)
	if n == 0:
		var horse: Array = mine.filter(func(f): return f["kind"] == "cav")
		if not horse.is_empty():
			_charge_fig(horse[0], target)
			if not quiet:
				Audio.field("horse_gallop", -6.0)
			return "cavalry"
	return "volley" if n > 1 else "shot"


func _target_of(ai: int, gi: int, foe: int) -> Vector2:
	var g: Dictionary = armies[ai]["groups"][gi]
	if foe >= 0 and foe < armies.size():
		var fg: Dictionary = armies[foe]["groups"][group_against(foe, ai)]
		return fg["at"]
	return (g["at"] as Vector2) + (g["dir"] as Vector2) * FIG * 6.0


func _aim(f: Dictionary, target: Vector2) -> void:
	var d: Vector2 = target - (f["at"] as Vector2)
	if d.length() > 1.0:
		f["face"] = d.normalized()


func set_count(ai: int, n: int, from_foe: int = -1) -> void:
	## casualties (or reserves): topple what's gone, bring up what's new. A loss comes off the
	## group that was just fired on; the man falls when the shot lands.
	if ai < 0 or ai >= armies.size():
		return
	n = maxi(0, n)
	var a: Dictionary = armies[ai]
	var diff: int = n - int(a["n"])
	if diff == 0:
		return
	a["n"] = n
	var gs: Array = a["groups"]
	if diff > 0:
		a["n0"] = maxi(int(a["n0"]), n)
		gs[0]["share"] = int(gs[0]["share"]) + diff
		_form(ai, 0, false)
		return
	var lose: int = -diff
	var gi: int = group_against(ai, from_foe) if from_foe >= 0 else 0
	var order: Array = [gi]
	for k in gs.size():
		if k != gi:
			order.append(k)
	for k in order:
		if lose <= 0:
			break
		var take: int = mini(lose, int(gs[k]["share"]))
		gs[k]["share"] = int(gs[k]["share"]) - take
		lose -= take
	var delay: float = maxf(0.0, _shot_at - _clock) + 0.06
	for k in gs.size():
		_cull(ai, k, delay)


func _cull(ai: int, gi: int, delay: float) -> void:
	var share: int = int(armies[ai]["groups"][gi]["share"])
	var want: Dictionary = pieces(share)
	var dir: Vector2 = armies[ai]["groups"][gi]["dir"]
	var short := false
	for k in ["gun", "cav", "inf"]:
		## (v2.1: the train an army brings isn't its count: no casualty takes a gun of it)
		var line: Array = figs.filter(func(f): return int(f["army"]) == ai and int(f["group"]) == gi and f["alive"] and f["kind"] == k and bool(f["counts"]))
		line.sort_custom(func(p, q): return (p["at"] as Vector2).dot(dir) > (q["at"] as Vector2).dot(dir))
		var extra: int = line.size() - int(want[k])
		for i in maxi(0, extra):
			_topple(line[i], delay + 0.11 * i)
		if extra < 0:
			short = true
	if short:
		_form(ai, gi, false) ## a horse is down: four men step up in its place
	if share == 0:
		var army_down: bool = int(armies[ai]["n"]) <= 0
		for f in figs:
			if int(f["army"]) == ai and int(f["group"]) == gi and f["alive"] and not bool(f["counts"]):
				if (f["kind"] == "cav" or f["kind"] == "gun") and not army_down:
					continue ## v2.1: the army's train stands while the army fights on anywhere (RV-002 F6)
				_topple(f, delay + randf_range(0.2, 0.7))
	if int(armies[ai]["n"]) <= 0:
		## the army is gone: its train falls with it, whichever group it stood with
		for f in figs:
			if int(f["army"]) == ai and f["alive"] and not bool(f["counts"]) and (f["kind"] == "cav" or f["kind"] == "gun"):
				_topple(f, delay + randf_range(0.2, 0.7))


func _topple(f: Dictionary, delay: float) -> void:
	f["alive"] = false
	f["state"] = "fall"
	f["t"] = -delay
	var back: Vector2 = -(f["face"] as Vector2)
	var sway: Vector2 = Vector2(-back.y, back.x) * randf_range(-0.6, 0.6)
	var d: Vector2 = (back + sway).normalized()
	f["fall_axis"] = Vector3.UP.cross(Vector3(d.x, 0.0, d.y)).normalized()
	f["fall_spin"] = randf_range(-0.6, 0.6)


func charge(ai: int) -> String:
	## pressing on: the front rank lunges with the bayonet and back; horse gallop forward
	var horse := false
	var foot := false
	for f in figs:
		if int(f["army"]) != ai or not f["alive"] or f["state"] != "stand":
			continue
		if f["kind"] == "inf" and int(f["rank"]) == 0:
			f["state"] = "charge"
			f["t"] = -randf() * 0.15
			foot = true
		elif f["kind"] == "cav":
			_charge_fig(f, (f["home"] as Vector2) + (f["face"] as Vector2) * FIG * 5.0)
			horse = true
	if not quiet:
		if horse:
			Audio.field("horse_gallop", -4.0)
		if foot:
			Audio.field("melee_steel", -6.0, 0.05)
	return "horse" if horse else ("foot" if foot else "")


func _charge_fig(f: Dictionary, target: Vector2) -> void:
	_aim(f, target)
	f["state"] = "charge"
	f["t"] = 0.0


func cheer(ai: int) -> void:
	for f in figs:
		if int(f["army"]) == ai and f["alive"] and f["state"] == "stand":
			f["state"] = "cheer"
			f["t"] = -randf() * 0.3
	if not quiet and ai >= 0 and ai < armies.size() and int(armies[ai]["n"]) > 0:
		Audio.field("cheer_hurrah", -5.0)


func reload(ai: int) -> void:
	## the front rank that fired rams the next round home
	for f in figs:
		if int(f["army"]) == ai and f["alive"] and f["kind"] == "inf" and int(f["rank"]) == 0 and f["state"] == "stand":
			f["state"] = "reload"
			f["t"] = -randf() * 0.25


func sweep() -> void:
	## the battle's over: every piece, standing or fallen, is lifted off the table
	live = false
	for f in figs:
		f["state"] = "lift"
		f["t"] = -randf() * 0.45
	for b in boats:
		(b["node"] as Node3D).visible = false


func retreat(ai: int) -> void:
	armies[ai]["fled"] = true
	if not quiet:
		Audio.field("flee_run", -6.0)
	for f in figs:
		if int(f["army"]) == ai and f["alive"]:
			f["state"] = "flee"
			f["t"] = -randf() * 0.3
			f["face"] = -(armies[ai]["groups"][int(f["group"])]["dir"] as Vector2)
			f["from"] = f["at"]


# ------------------------------------------------------------------ motion

func _process(delta: float) -> void:
	_clock += delta
	shake = maxf(0.0, shake - delta * 2.5)
	for b in boats:
		_row(b, delta)
	var rel: float = wv.relief if wv != null else 1.0
	for f in figs:
		f["t"] = float(f["t"]) + delta
		## a man at ease on ground that isn't moving stays put (the board's garrisons: dozens of them)
		if f["state"] == "stand" and f["kind"] != "drummer" and is_equal_approx(float(f.get("rel", -1.0)), rel):
			continue
		f["rel"] = rel if f["state"] == "stand" else -1.0
		_place(f)
	for i in range(puffs.size() - 1, -1, -1):
		var p: Dictionary = puffs[i]
		p["t"] = float(p["t"]) + delta
		var k: float = float(p["t"]) / float(p["life"])
		var node: MeshInstance3D = p["node"]
		node.position += (p["drift"] as Vector3) * delta
		node.scale = Vector3.ONE * lerpf(0.4, float(p.get("grow", 1.9)), 1.0 - pow(1.0 - minf(k, 1.0), 2.5))
		(node.material_override as StandardMaterial3D).albedo_color.a = float(p.get("a", 0.75)) * (1.0 - smoothstep(0.25, 1.0, k))
		if k >= 1.0:
			node.queue_free()
			puffs.remove_at(i)
	for i in range(tracers.size() - 1, -1, -1):
		if _fly(tracers[i], delta):
			tracers.remove_at(i)
	for i in range(flashes.size() - 1, -1, -1):
		var fl: Dictionary = flashes[i]
		fl["t"] = float(fl["t"]) + delta
		var l: OmniLight3D = fl["light"]
		l.light_energy = float(fl.get("e", 6.0)) * clampf(1.0 - float(fl["t"]) / 0.14, 0.0, 1.0) * (1.0 if float(fl["t"]) >= 0.0 else 0.0)
		if float(fl["t"]) > 0.16:
			l.queue_free()
			flashes.remove_at(i)
	_drum(delta)


func _drum(delta: float) -> void:
	## the drum quickens as an army nears breaking: the side worst off sets the beat
	if not live or quiet:
		return
	var worst := 1.0
	for a in armies:
		if not bool(a["fled"]) and int(a["n"]) > 0:
			worst = minf(worst, float(a["n"]) / float(a["n0"]))
	if worst > 0.7:
		return
	var urgency: float = clampf((0.7 - worst) / 0.6, 0.0, 1.0)
	_drum_t -= delta
	if _drum_t <= 0.0:
		_drum_t = 1.0 / lerpf(1.3, 4.2, urgency)
		Audio.field("drum_tap", lerpf(-20.0, -12.0, urgency), 0.03)


func _row(b: Dictionary, delta: float) -> void:
	b["t"] = float(b["t"]) + delta
	var k: float = clampf(float(b["t"]) / float(b["dur"]), 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 2.2)
	var p: Vector2 = (b["from"] as Vector2).lerp(b["to"], e)
	var dir: Vector2 = b["dir"]
	var bob: float = sin(_clock * 2.3 + float(b["army"])) * 0.6 * (1.0 - k)
	var node: Node3D = b["node"]
	var y: float = maxf(0.0, wv.terrain.height_at(p) * wv.relief)
	node.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)) * Basis(Vector3.BACK, sin(_clock * 1.7) * 0.04 * (1.0 - k)), Vector3(p.x, y + bob, p.y))
	b["pos"] = p
	if k >= 1.0 and not bool(b["landed"]):
		b["landed"] = true
		if not quiet:
			Audio.field("boat_beach", -6.0)
			get_tree().create_timer(0.35).timeout.connect(func(): Audio.field("wade_ashore", -5.0))
			if boats.all(func(x): return bool(x["landed"])):
				Audio.field_loop("")
		for f in figs:
			if int(f["boat"]) >= 0 and boats[int(f["boat"])] == b and f["state"] == "boat":
				f["state"] = "march"
				f["from"] = _dry((b["to"] as Vector2) + dir * FIG * 1.6 + (f["seat"] as Vector2).rotated(atan2(dir.y, dir.x) - PI * 0.5), dir)
				f["at"] = f["from"]
				f["t"] = 0.0
				f["delay"] = randf() * 0.5


func _place(f: Dictionary) -> void:
	var node: Node3D = f["node"]
	var t: float = f["t"]
	var face: Vector2 = f["face"]
	var yaw: float = atan2(face.x, face.y)
	var basis := Basis(Vector3.UP, yaw)
	var lift := 0.0
	match f["state"]:
		"new":
			pass
		"boat":
			var b: Dictionary = boats[int(f["boat"])]
			var bd: Vector2 = b["dir"]
			var bp: Vector2 = b.get("pos", b["from"])
			var seat: Vector2 = (f["seat"] as Vector2).rotated(atan2(bd.y, bd.x) - PI * 0.5)
			f["at"] = bp + seat
			f["face"] = bd
			node.transform = Transform3D(Basis(Vector3.UP, atan2(bd.x, bd.y)), (b["node"] as Node3D).position + Vector3(seat.x, FIG * 0.02, seat.y))
			return
		"march":
			var dur: float = float(f.get("dur", 2.6))
			var k: float = clampf((t - float(f["delay"])) / dur, 0.0, 1.0)
			f["at"] = (f["from"] as Vector2).lerp(f["home"], 1.0 - pow(1.0 - k, 1.6))
			var dv: Vector2 = (f["home"] as Vector2) - (f["from"] as Vector2)
			if k > 0.0 and k < 1.0:
				## a toy pushed across the table: hop, hop, with a rock from foot to foot
				if dv.length() > 1.0:
					f["face"] = dv.normalized()
					basis = Basis(Vector3.UP, atan2(dv.x, dv.y))
				var ph: float = (t - float(f["delay"])) * 7.5
				lift = absf(sin(ph)) * FIG * 0.16
				basis = basis * Basis(Vector3.BACK, sin(ph) * 0.1)
				if f["kind"] == "inf":
					_pose(f, "inf_march")
				elif f["kind"] == "cav":
					_pose(f, "cav_charge")
			elif k >= 1.0:
				f["state"] = "stand"
				f["face"] = _rest_face(f)
				_pose(f, _rest(str(f["kind"])))
		"stand":
			if f["kind"] == "drummer" and live:
				lift = absf(sin(_clock * 9.0)) * FIG * 0.03
		"fire":
			if t > 0.0:
				if f["kind"] == "inf":
					_pose(f, "inf_kneel" if bool(f.get("kneel", false)) else "inf_aim")
				var at_shot: float = FIRE_AT
				if t > at_shot and not bool(f.get("fired", true)):
					f["fired"] = true
					_muzzle(f)
				if t > at_shot:
					var kt: float = t - at_shot
					var kick: float = exp(-kt * 9.0) * sin(minf(kt * 30.0, PI))
					basis = basis * Basis(Vector3.RIGHT, -kick * (0.12 if f["kind"] == "gun" else 0.2))
					if f["kind"] == "gun":
						f["at"] = (f["home"] as Vector2) - (f["face"] as Vector2) * FIG * 0.5 * exp(-kt * 3.0) * minf(kt * 20.0, 1.0)
				if t > 1.0:
					f["state"] = "stand"
					f["at"] = f["home"]
					_pose(f, _rest(str(f["kind"])))
					lift = FIG * 0.05
			elif t > -0.08:
				lift = FIG * 0.08 ## up on its toes as the pose changes
		"charge":
			if t > 0.0:
				if f["kind"] == "inf":
					_pose(f, "inf_charge")
				elif f["kind"] == "cav":
					_pose(f, "cav_charge")
				var reach: float = FIG * (1.4 if f["kind"] == "inf" else 3.0)
				var k2: float = sin(clampf(t / 0.9, 0.0, 1.0) * PI)
				f["at"] = (f["home"] as Vector2) + (f["face"] as Vector2) * reach * k2
				lift = absf(sin(t * 9.0)) * FIG * 0.1 * k2
				if t > 0.9:
					f["state"] = "stand"
					f["at"] = f["home"]
					f["face"] = _rest_face(f)
					_pose(f, _rest(str(f["kind"])))
		"cheer":
			if t > 0.0:
				if f["kind"] == "inf":
					_pose(f, "inf_cheer") ## and they keep cheering: the field is theirs
				lift = absf(sin(t * 8.0)) * FIG * 0.22 * maxf(0.0, 1.0 - t / 1.4)
				if t > 1.4:
					f["state"] = "stand"
		"reload":
			if t > 0.0:
				_pose(f, "inf_reload")
				if t > 1.5:
					f["state"] = "stand"
					_pose(f, _rest(str(f["kind"])))
		"crew":
			if t > 0.0:
				_pose(f, "gunner_fire" if t < 0.45 else "gunner_ram")
				if t > 0.45 and t < 1.6:
					f["at"] = (f["home"] as Vector2) + (f["face"] as Vector2) * FIG * 0.3 * sin((t - 0.45) / 1.15 * PI)
				if t > 1.8:
					f["state"] = "stand"
					f["at"] = f["home"]
					_pose(f, _rest(str(f["kind"])))
		"flee":
			if t > 0.0:
				_pose(f, ("inf_flee" if has_model("inf_flee") else "inf_march") if f["kind"] == "inf" else _rest(str(f["kind"])))
				f["at"] = (f["from"] as Vector2) + (f["face"] as Vector2) * t * FIG * 2.2
				lift = absf(sin(t * 7.5)) * FIG * 0.14
				basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, sin(t * 7.5) * 0.1)
				var shrink: float = clampf(1.0 - (t - 2.0) / 0.8, 0.0, 1.0)
				basis = basis.scaled(Vector3.ONE * maxf(shrink, 0.001))
				if shrink <= 0.0:
					node.visible = false
		"lift":
			if t > 0.0:
				var k3: float = clampf(t / 0.45, 0.0, 1.0)
				lift = FIG * 2.5 * k3 * k3
				basis = basis.scaled(Vector3.ONE * maxf(1.0 - k3, 0.001))
				if k3 >= 1.0:
					node.visible = false
		"fall":
			if t > 0.0:
				_pose(f, _rest(str(f["kind"])))
				## over it goes: gravity on the tip, a bounce, then still
				var k: float = minf(t / 0.42, 1.0)
				var ang: float = (PI * 0.5) * k * k
				if t > 0.42:
					var bt: float = t - 0.42
					ang = PI * 0.5 - absf(sin(bt * 16.0)) * exp(-bt * 9.0) * 0.25
				var axis: Vector3 = f["fall_axis"]
				basis = Basis(axis, ang) * Basis(Vector3.UP, float(f["fall_spin"]) * k) * basis
				lift = sin(ang) * FIG * 0.12
				if t > 0.62 and f["kind"] == "inf" and has_model("inf_fallen"):
					## the toy is down: he lies where he fell, as the fallen lie (in the dust it raised)
					_pose(f, "inf_fallen")
					var d3: Vector3 = axis.cross(Vector3.UP)
					basis = Basis(Vector3.UP, atan2(d3.x, d3.z) + float(f["fall_spin"]))
					lift = 0.0
				if not bool(f.get("dusted", false)) and t > 0.4:
					f["dusted"] = true
					_puff(f["at"], 0.6, Color(0.55, 0.5, 0.42))
					if not quiet:
						Audio.field(FALL_SOUND.get(ground, "fall_grass"), -7.0 if f["kind"] == "inf" else -3.0, 0.1)
	var p: Vector2 = f["at"]
	node.transform = Transform3D(basis, wv.ground_at(p) + Vector3(0.0, lift, 0.0))


func _rest_face(f: Dictionary) -> Vector2:
	return armies[int(f["army"])]["groups"][int(f["group"])]["dir"]


func _muzzle(f: Dictionary) -> void:
	var face: Vector2 = f["face"]
	var gun: bool = f["kind"] == "gun"
	var p: Vector2 = (f["at"] as Vector2) + face * FIG * (0.75 if gun else 0.55)
	var hgt: float = 0.3 if gun else (0.5 if bool(f.get("kneel", false)) else 0.72)
	var top: Vector3 = wv.ground_at(p) + Vector3(0.0, FIG * hgt, 0.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.omni_range = FIG * (7.0 if gun else 4.0)
	l.position = top
	add_child(l)
	flashes.append({"light": l, "t": 0.0, "e": 9.0 if gun else 6.0})
	_puff(p, 2.4 if gun else 1.0, Color(0.88, 0.87, 0.84), top)
	var aim: Vector2 = f.get("target", p + face * FIG * 8.0)
	_tracer(top, aim, gun, int(f["army"]), int(f.get("foe", -1)))
	if quiet:
		return
	if gun:
		Audio.field("cannon_big", -2.0, 0.05)
		shake = 1.0
		var tgt: Vector2 = aim
		get_tree().create_timer(BALL_FLIGHT).timeout.connect(func():
			_puff(tgt + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * FIG, 1.6, Color(0.45, 0.38, 0.3))
			shake = maxf(shake, 0.5)
			Audio.field("ball_impact", -5.0, 0.06))
	else:
		Audio.field("musket", randf_range(-9.0, -5.0), 0.1)


const BALL_FLIGHT := 0.38 ## a cannon's round shot, muzzle to the ground it strikes
const FIRE_AT := 0.18 ## how far into his firing a man's musket goes off


static func _flight(dist: float) -> float:
	## a musket ball's time in the air: quick, but slow enough to be followed
	return clampf(dist / (FIG * 40.0), 0.12, 0.26)


func _tracer(from: Vector3, aim: Vector2, gun: bool, ai: int, foe: int) -> void:
	## v2.2: the shot is seen to go where it's going: a streak in the firer's colours from the
	## muzzle to the man it's meant for (a dark round shot, arcing, from a gun)
	var to: Vector3 = wv.ground_at(aim) + Vector3(0.0, FIG * (0.15 if gun else 0.6), 0.0)
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.disable_receive_shadows = true
	if gun:
		var ball := SphereMesh.new()
		ball.radius = FIG * 0.14
		ball.height = FIG * 0.28
		ball.radial_segments = 10
		ball.rings = 6
		mi.mesh = ball
		m.albedo_color = Color(0.12, 0.11, 0.1)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.55, 0.2)
		m.emission_energy_multiplier = 0.6
	else:
		## a short hot streak, bright at the ball and thinning to nothing behind it, in the
		## firer's colour (his shots are told from the other side's by it)
		var streak := CylinderMesh.new()
		streak.top_radius = FIG * 0.075
		streak.bottom_radius = FIG * 0.008
		streak.height = FIG * 1.1
		streak.radial_segments = 6
		streak.rings = 1
		mi.mesh = streak
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var col: Color = armies[ai]["color"]
		var hot: Color = col.lightened(0.12).lerp(Color(1.0, 0.86, 0.5), 0.3)
		m.albedo_color = Color(hot.r * 1.6, hot.g * 1.6, hot.b * 1.6, 1.0) ## over 1: the glow takes it
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = from
	var d: Vector3 = to - from
	if not gun and d.length() > 0.01:
		mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	add_child(mi)
	tracers.append({"node": mi, "from": from, "to": to, "t": 0.0, "dur": BALL_FLIGHT if gun else _flight(d.length()),
		"arc": FIG * 1.6 if gun else 0.0, "gun": gun, "aim": aim, "army": ai, "foe": foe})


func _fly(tr: Dictionary, delta: float) -> bool:
	## a shot in the air: true when it has struck (a musket ball kicks up a little dust)
	tr["t"] = float(tr["t"]) + delta
	var k: float = clampf(float(tr["t"]) / float(tr["dur"]), 0.0, 1.0)
	var node: MeshInstance3D = tr["node"]
	node.position = (tr["from"] as Vector3).lerp(tr["to"], k) + Vector3(0.0, float(tr["arc"]) * 4.0 * k * (1.0 - k), 0.0)
	if k < 1.0:
		return false
	node.queue_free()
	if not bool(tr["gun"]):
		_puff(tr["aim"], 0.35, Color(0.62, 0.56, 0.46))
	return true


func _puff(at: Vector2, big: float, col: Color, pos: Variant = null) -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * FIG * 1.1 * big
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft
	m.albedo_color = Color(col.r, col.g, col.b, 0.75)
	m.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos if pos != null else wv.ground_at(at) + Vector3(0.0, FIG * 0.25, 0.0)
	add_child(mi)
	## powder smoke hangs: the field grows hazier as the fight goes on
	puffs.append({"node": mi, "t": 0.0, "life": 5.5 if big > 0.8 else 1.4, "grow": 2.6 if big > 0.8 else 1.6,
		"drift": Vector3(randf_range(1.0, 3.0), randf_range(0.8, 1.8), randf_range(-1.0, 1.0)), "a": 0.7 if big > 0.8 else 0.8})


func fire_burst(at: Vector2, n: int = 8) -> void:
	## a capital burning: fire and black smoke climbing
	for i in n:
		var p: Vector2 = at + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * FIG * 2.0
		_puff(p, 2.0, Color(0.2, 0.18, 0.17), wv.ground_at(p) + Vector3(0, FIG * randf_range(0.5, 1.5), 0))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.5, 0.2)
		l.omni_range = FIG * 6.0
		l.position = wv.ground_at(p) + Vector3(0, FIG, 0)
		add_child(l)
		flashes.append({"light": l, "t": -randf() * 0.5, "e": 4.0})


func centre_of(ai: int) -> Vector3:
	## the middle of an army as it stands (its plate hangs over it)
	var sum := Vector2.ZERO
	var n := 0
	for f in figs:
		if int(f["army"]) == ai and f["alive"] and bool(f["counts"]):
			sum += f["at"]
			n += 1
	var c: Vector2 = sum / float(n) if n > 0 else (armies[ai]["groups"][0]["at"] as Vector2)
	return wv.ground_at(c) + Vector3(0.0, FIG * 2.3, 0.0)


func spots() -> Array:
	## where everyone will stand: the camera must see them all
	var out: Array = []
	for a in armies:
		for g in a["groups"]:
			out.append(g["at"])
	return out


# ------------------------------------------------------------------ the spike's battle (tools/spike)

func stage(spec: Dictionary) -> void:
	## spec: {to, defender: {pid, n, color}, fronts: [{pid, from, n, color}]}: a melee
	var to: String = spec["to"]
	heart = wv.art.anchors[to]
	var list: Array = []
	var total := 0
	for f in spec["fronts"]:
		total += int(f["n"])
	var dn: int = int(spec["defender"]["n"])
	var left: int = dn
	var dgroups: Array = []
	var nf: int = (spec["fronts"] as Array).size()
	for i in nf:
		var f: Dictionary = spec["fronts"][i]
		var g := front_group(to, f["from"], int(f["n"]))
		g["foe"] = nf
		list.append({"pid": f["pid"], "color": f["color"], "n": int(f["n"]), "groups": [g]})
		var share: int = left if i == nf - 1 else int(round(float(dn) * float(f["n"]) / float(maxi(total, 1))))
		share = clampi(share, 0, left)
		left -= share
		var x: Vector2 = g["cross"]
		dgroups.append({"at": heart + (x - heart).normalized() * minf(float(g["dist"]) * 0.18, FIG * 3.2), "dir": (x - heart).normalized(), "share": share, "foe": i})
	list.append({"pid": spec["defender"]["pid"], "color": spec["defender"]["color"], "n": dn, "groups": dgroups})
	place(list)
	live = true


func army_top(ai: int) -> Vector3:
	return centre_of(ai)


# ------------------------------------------------------------------ dice on the land (the spike)

func setup_dice(layer: CanvasLayer) -> void:
	_dice_layer = layer


func _table(k: int) -> Dictionary:
	while tables.size() <= k:
		var dice := DiceStage.new()
		dice.board = false
		dice.arrange = false
		dice.width = 14.0
		dice.modulate.a = 0.0
		dice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dice.size = Vector2(900, 900)
		_dice_layer.add_child(dice)
		var w: Node3D = dice.get("_world")
		(w.get_parent() as Node).remove_child(w)
		for c in w.get_children():
			if c is Light3D or c is WorldEnvironment:
				c.queue_free()
			elif c is Camera3D:
				(c as Camera3D).current = false
		var root := Node3D.new()
		add_child(root)
		root.add_child(w)
		tables.append({"stage": dice, "root": root})
	return tables[k]


func throw(pairs: Array) -> float:
	var longest := 0.0
	for k in pairs.size():
		var pr: Dictionary = pairs[k]
		var a: Dictionary = armies[pr["army"]]
		var fg: Dictionary = armies[pr["foe"]]["groups"][group_against(pr["foe"], pr["army"])]
		var ag: Dictionary = a["groups"][0]
		var mid: Vector2 = ((ag["at"] as Vector2) + (fg["at"] as Vector2)) * 0.5
		var tb: Dictionary = _table(k)
		var n: Vector3 = wv.terrain.normal_at(mid).lerp(Vector3.UP, 0.4).normalized()
		var x: Vector3 = n.cross(Vector3.BACK).normalized()
		var z: Vector3 = x.cross(n).normalized()
		(tb["root"] as Node3D).transform = Transform3D(Basis(x, n, z).scaled(Vector3.ONE * DIE), wv.ground_at(mid) + n * 0.4)
		var bearing: Vector2 = ((ag["at"] as Vector2) - (fg["at"] as Vector2)).normalized()
		var side := Vector2(-bearing.y, bearing.x)
		var specs := [
			{"value": pr["a"], "n": a["n"], "tint": a["color"], "to": bearing * 0.9 + side * 0.6, "from_dir": bearing, "delay": 0.1 * k},
			{"value": pr["d"], "n": armies[pr["foe"]]["n"], "tint": armies[pr["foe"]]["color"], "to": -bearing * 0.9 - side * 0.6, "from_dir": -bearing, "delay": 0.1 * k + 0.05},
		]
		longest = maxf(longest, (tb["stage"] as Control).throw(specs))
	return longest


func mark(k: int, a_how: String, d_how: String) -> void:
	var st: Control = _table(k)["stage"]
	st.mark(0, a_how)
	st.mark(1, d_how)
