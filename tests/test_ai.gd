## AI commanders: legal sheets, finished games, determinism, and a sanity edge.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Ai := preload("res://engine/ai.gd")
const Rng := preload("res://engine/rng.gd")
const Validate := preload("res://engine/validate.gd")
const H := preload("res://tests/harness.gd")


func run(report: Callable) -> void:
	var configs := [
		["knife7", ["general", "recruit"]],
		["knife7", ["veteran", "hask", "oren"]],
		["known24", ["general", "veteran", "recruit"]],
		["known24", ["varek", "ysolde", "imre", "quill", "hask"]],
		["world30", ["general", "veteran"]],
		["world30", ["general", "hask", "quill", "oren"]],
	]
	for cfg in configs:
		var bad := 0
		var finished := 0
		for seed in [101, 202]:
			var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % cfg[0])
			var seats: Array = []
			var brains: Array = cfg[1]
			for i in brains.size():
				seats.append({"id": Setup.SEAT_IDS[i], "name": brains[i], "ai": brains[i]})
			var r: Dictionary = Autoplay.play(map, seats, seed)
			if not r["ok"]:
				bad += 1
				print("    ", r["violations"])
			if str(r["winner"]) != "":
				finished += 1
		report.call(bad == 0, "%s %s: every AI sheet legal, invariants hold" % [cfg[0], "/".join(cfg[1])])
		report.call(finished == 2, "%s %s: games reach a winner" % [cfg[0], "/".join(cfg[1])])

	## same seed, same war
	var m1: Types.MapDef = Types.MapDef.from_file("res://maps/known24.json")
	var m2: Types.MapDef = Types.MapDef.from_file("res://maps/known24.json")
	var seats2 := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "veteran"}, {"id": "green", "name": "c", "ai": "recruit"}]
	var a: Dictionary = Autoplay.play(m1, seats2, 77)
	var b: Dictionary = Autoplay.play(m2, seats2, 77)
	report.call(a["hashes"] == b["hashes"], "AI matches are deterministic for a seed")

	## A clear opening: the choke is empty and the south is thin. Take it.
	var knife: Types.MapDef = H.knife7()
	var w: Types.World = H.paint(knife, {
		"beacon": ["red", 1], "ridge": ["red", 9], "mill": ["red", 1],
		"harbor": ["blue", 1], "docks": ["blue", 1], "quarry": ["blue", 1]})
	w.round = 2
	var rng: RefCounted = Rng.derive_stream(1, 2, "t")
	var s: Types.Sheet = Ai.plan(w, knife, "red", rng, Ai.profile_for("general"))
	report.call(Validate.validate_sheet(w, knife, s).is_empty(), "general's sheet validates on a crafted board")
	var sent := 0
	for p in s.packets:
		sent += (p as Types.Packet).strength
	report.call(sent >= 1, "general walks into the empty Gate (sent %s)" % sent)

	## the recruit plans quickly; the general stays under a human's patience
	var map3: Types.MapDef = Types.MapDef.from_file("res://maps/world30.json")
	var w3: Types.World = Setup.deal(map3, [{"id": "red", "name": "a"}, {"id": "blue", "name": "b"}, {"id": "green", "name": "c"}, {"id": "gold", "name": "d"}, {"id": "purple", "name": "e"}], 3)
	for t in w3.territories.keys():
		if w3.territories[t].owner != "":
			w3.territories[t].armies = 4
	w3.round = 3
	var t0 := Time.get_ticks_msec()
	Ai.plan(w3, map3, "red", Rng.derive_stream(1, 3, "x"), Ai.profile_for("general"))
	var ms := Time.get_ticks_msec() - t0
	report.call(ms < 1500, "general plans a 5-seat world30 turn in %d ms" % ms)
