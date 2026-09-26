## AI arena: many seeded matches, bands printed. Tuning instrument, not a test.
##   godot --headless --script res://tools/arena.gd -- map=world30 n=40 seats=general,veteran,recruit,hask
extends SceneTree

const Types := preload("res://engine/types.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Setup := preload("res://engine/setup.gd")


func _initialize() -> void:
	var args := {"map": "known24", "n": "30", "seats": "general,veteran,recruit", "rounds": "0", "seed": "1000", "battle": "volleys", "moves": "1", "wild": "0", "scramble": "1", "deal": "random", "dig": "3", "rules": "16", "first": "0", "line": "5"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var brains: PackedStringArray = str(args["seats"]).split(",")
	load("res://engine/combat.gd").line_size = int(args["line"])
	var n: int = int(args["n"])
	var wins := {}
	var rounds_total := 0
	var early := 0
	var before_last := 0 ## decided before the final round (early counts domination on the last round too)
	var bad := 0
	var walks := 0
	var even := 0
	var even_cap := 0
	var inv := 0
	var res := 0
	var fb := 0
	var mel := 0
	var scr := 0
	var ms := 0.0
	var lengths: Array = []
	for i in n:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % args["map"])
		map.battle = str(args["battle"])
		map.maneuvers = str(args["moves"]) == "1"
		map.wild_cards = str(args["wild"]) == "1"
		map.scramble = str(args["scramble"]) == "1"
		map.dig_cap = int(args["dig"])
		map.rules = int(args["rules"])
		map.first_digs_in = str(args["first"]) == "1"
		map.fire_line = int(args["line"]) > 0
		var seats: Array = []
		## rotate seats so no brain always sits in the same chair
		for k in brains.size():
			var b: String = brains[(k + i) % brains.size()]
			seats.append({"id": Setup.SEAT_IDS[k], "name": b, "ai": b})
		var r: Dictionary = Autoplay.play(map, seats, int(args["seed"]) + i, int(args["rounds"]), str(args["deal"]) == "draft")
		if not r["ok"]:
			bad += 1
			print("VIOLATION seed %s: %s" % [int(args["seed"]) + i, " | ".join(r["violations"])])
		var who: String = str(r["brains"].get(r["winner"], "none"))
		wins[who] = int(wins.get(who, 0)) + 1
		rounds_total += int(r["roundsPlayed"])
		lengths.append(int(r["roundsPlayed"]))
		if r["early"]:
			early += 1
			if int(r["roundsPlayed"]) < Setup.rounds_for(map):
				before_last += 1
		for rd in r["rounds"]:
			walks += int(rd.get("vacatePunish", 0))
			even += int(rd.get("even", 0))
			even_cap += int(rd.get("evenCaptures", 0))
			inv += int(rd.get("invasions", 0))
			res += int(rd.get("reserves", 0))
			fb += int(rd.get("fallbacks", 0))
			mel += int(rd.get("melees", 0))
			scr += int(rd.get("scrambles", 0))
		ms += float(r["planMs"])
	lengths.sort()
	print("map=%s seats=%s n=%s" % [args["map"], args["seats"], n])
	print("  wins        %s" % wins)
	print("  rounds      mean %.1f  median %s  domination %s/%s (before the last round %s)" % [float(rounds_total) / n, lengths[n / 2], early, n, before_last])
	print("  walk-ins    %.2f per game" % (float(walks) / n))
	print("  even fights %s, attacker took %.0f%%" % [even, 100.0 * even_cap / maxf(1.0, even)])
	print("  assaults    %.1f per game: reserves called in %.0f%%, fell back in %.0f%%" % [float(inv) / n, 100.0 * res / maxf(1.0, inv), 100.0 * fb / maxf(1.0, inv)])
	print("  melees      %.1f per game, scrambles %.1f" % [float(mel) / n, float(scr) / n])
	print("  plan time   %.1f ms per sheet" % (ms / n))
	print("  violations  %s" % bad)
	quit(0 if bad == 0 else 1)
