## AI arena: many seeded matches, bands printed. Tuning instrument, not a test.
##   godot --headless --script res://tools/arena.gd -- map=world30 n=40 seats=general,veteran,recruit,hask
extends SceneTree

const Types := preload("res://engine/types.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Setup := preload("res://engine/setup.gd")


func _initialize() -> void:
	var args := {"map": "known24", "n": "30", "seats": "general,veteran,recruit", "rounds": "0", "seed": "1000"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var brains: PackedStringArray = str(args["seats"]).split(",")
	var n: int = int(args["n"])
	var wins := {}
	var rounds_total := 0
	var early := 0
	var bad := 0
	var walks := 0
	var even := 0
	var even_cap := 0
	var ms := 0.0
	var lengths: Array = []
	for i in n:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % args["map"])
		var seats: Array = []
		## rotate seats so no brain always sits in the same chair
		for k in brains.size():
			var b: String = brains[(k + i) % brains.size()]
			seats.append({"id": Setup.SEAT_IDS[k], "name": b, "ai": b})
		var r: Dictionary = Autoplay.play(map, seats, int(args["seed"]) + i, int(args["rounds"]))
		if not r["ok"]:
			bad += 1
			print("VIOLATION seed %s: %s" % [int(args["seed"]) + i, " | ".join(r["violations"])])
		var who: String = str(r["brains"].get(r["winner"], "none"))
		wins[who] = int(wins.get(who, 0)) + 1
		rounds_total += int(r["roundsPlayed"])
		lengths.append(int(r["roundsPlayed"]))
		if r["early"]:
			early += 1
		for rd in r["rounds"]:
			walks += int(rd.get("vacatePunish", 0))
			even += int(rd.get("even", 0))
			even_cap += int(rd.get("evenCaptures", 0))
		ms += float(r["planMs"])
	lengths.sort()
	print("map=%s seats=%s n=%s" % [args["map"], args["seats"], n])
	print("  wins        %s" % wins)
	print("  rounds      mean %.1f  median %s  early-ends %s/%s" % [float(rounds_total) / n, lengths[n / 2], early, n])
	print("  walk-ins    %.2f per game" % (float(walks) / n))
	print("  even fights %s, attacker took %.0f%%" % [even, 100.0 * even_cap / maxf(1.0, even)])
	print("  plan time   %.1f ms per sheet" % (ms / n))
	print("  violations  %s" % bad)
	quit(0 if bad == 0 else 1)
