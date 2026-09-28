## AI arena: many seeded matches, bands printed. Tuning instrument, not a test.
##   godot --headless --script res://tools/arena.gd -- map=world30 n=40 seats=general,veteran,recruit,hask
extends SceneTree

const Types := preload("res://engine/types.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Setup := preload("res://engine/setup.gd")


func _initialize() -> void:
	var args := {"map": "known24", "n": "30", "seats": "general,veteran,recruit", "rounds": "0", "seed": "1000", "battle": "volleys", "moves": "1", "wild": "0", "scramble": "1", "deal": "random", "dig": "3", "rules": "20", "first": "0", "line": "5", "supply": "map", "traits": "map", "capitals": "1", "fortune": "1", "levee": "map", "fbar": "0", "ffloor": "0"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var brains: PackedStringArray = str(args["seats"]).split(",")
	load("res://engine/combat.gd").line_size = int(args["line"])
	## v1.9: try another Fortune bar or floor on the same seeds (0 = the rules' own)
	load("res://engine/fortune.gd").tune_bar = int(args["fbar"])
	load("res://engine/fortune.gd").tune_floor = int(args["ffloor"])
	var n: int = int(args["n"])
	var wins := {}
	var rounds_total := 0
	var early := 0
	var before_last := 0 ## decided before the final round (early counts domination on the last round too)
	var bad := 0
	var walks := 0
	var even := 0
	var even_cap := 0
	var evenc := 0
	var evenc_cap := 0
	var inv := 0
	var res := 0
	var fb := 0
	var mel := 0
	var scr := 0
	var caps := 0
	var f_spent := 0
	var f_saved := 0
	var f_gain := 0
	var lead_changes := 0
	var comebacks := 0
	var margin := 0.0
	var close := 0
	var upsets := 0
	var ms := 0.0
	var lengths: Array = []
	var fp: Array = [] ## v1.11: the determinism fingerprint
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
		## v1.7 A/B switches: "map" keeps what the map file asks for, 0/1 forces it off/on,
		## so a rule can be measured against the very same seeds without a second map file.
		map.capitals = str(args["capitals"]) == "1" ## v1.8 (new games default on)
		map.fortune = str(args["fortune"]) == "1"
		if str(args["levee"]) != "map":
			map.levee = int(args["levee"])
		if str(args["supply"]) != "map":
			map.supply = str(args["supply"]) == "1"
		if str(args["traits"]) == "0":
			for tid in map.territory_ids():
				(map.get_territory(tid) as Types.TerritoryDef).traits = PackedStringArray()
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
			evenc += int(rd.get("evenClean", 0))
			evenc_cap += int(rd.get("evenCleanCaptures", 0))
			inv += int(rd.get("invasions", 0))
			res += int(rd.get("reserves", 0))
			fb += int(rd.get("fallbacks", 0))
			mel += int(rd.get("melees", 0))
			scr += int(rd.get("scrambles", 0))
			caps += int(rd.get("capitalsTaken", 0))
			f_spent += int(rd.get("fortuneSpent", 0))
			f_saved += int(rd.get("fortuneSaved", 0))
			f_gain += int(rd.get("fortuneGained", 0))
			upsets += int(rd.get("upsets", 0))
		## v1.8 drama: the lead changing hands, wins from behind, how close the finish was
		var leaders: Array = []
		for rd in r["rounds"]:
			leaders.append(str(rd.get("leader", "")))
		for k in range(1, leaders.size()):
			if leaders[k] != "" and leaders[k - 1] != "" and leaders[k] != leaders[k - 1]:
				lead_changes += 1
		var mid: int = int(ceil(leaders.size() * 0.6)) - 1
		if leaders.size() >= 3 and mid >= 0 and str(leaders[mid]) != str(r["winner"]):
			comebacks += 1
		var fin: Dictionary = (r["rounds"][-1] as Dictionary).get("scores", {}) if not (r["rounds"] as Array).is_empty() else {}
		var sc: Array = fin.values()
		sc.sort()
		if sc.size() >= 2 and not r["early"]:
			var m: float = float(sc[-1]) - float(sc[-2])
			margin += m
			if m <= 3.0:
				close += 1
		ms += float(r["planMs"])
		fp.append("%s|%s|%s" % [str(r["winner"]), int(r["roundsPlayed"]), str(fin)])
	lengths.sort()
	print("map=%s seats=%s n=%s" % [args["map"], args["seats"], n])
	## v1.11: every war's winner, length and final scores, hashed: the same on any machine, or the
	## engine isn't deterministic there (PLAYTEST.md lists the Mac's fingerprints)
	print("  fingerprint %s" % "\n".join(fp).md5_text().left(12))
	print("  wins        %s" % wins)
	print("  rounds      mean %.1f  median %s  domination %s/%s (before the last round %s)" % [float(rounds_total) / n, lengths[n / 2], early, n, before_last])
	print("  walk-ins    %.2f per game" % (float(walks) / n))
	## Not a reading on the combat rule. These are the even fights the commanders happened to
	## end up in, and which fights those are is chosen by the AI, not by the dice: the band
	## wanders far from 50% on a small sample and always has. The rule itself is checked
	## under controlled conditions in tests/test_v17.gd, which fights the same matchup
	## through this very queue 600 times and holds it to the quoted odds.
	print("  even fights %s, attacker took %.0f%% (a selected sample, not the rule: see test_v17)  ·  fought as they started: %s at %.0f%%"
		% [even, 100.0 * even_cap / maxf(1.0, even), evenc, 100.0 * evenc_cap / maxf(1.0, evenc)])
	print("  assaults    %.1f per game: reserves called in %.0f%%, fell back in %.0f%%" % [float(inv) / n, 100.0 * res / maxf(1.0, inv), 100.0 * fb / maxf(1.0, inv)])
	print("  melees      %.1f per game, scrambles %.1f" % [float(mel) / n, float(scr) / n])
	print("  capitals    %.2f fell per game" % (float(caps) / n))
	print("  fortune     %.2f favours earned, %.2f spent per game (%.2f and %.2f per commander); %d%% of the battles it was spent in were won by the spender" % [float(f_gain) / n, float(f_spent) / n,
		float(f_gain) / n / brains.size(), float(f_spent) / n / brains.size(), int(100.0 * f_saved / maxf(1.0, f_spent))])
	var full: int = n - early
	print("  drama       %.1f lead changes a game, %d%% won from behind, %.0f upsets a game; finishes on score: margin %.1f, within 3 in %d of %d" % [
		float(lead_changes) / n, int(100.0 * comebacks / n), float(upsets) / n, margin / maxf(1.0, float(full)), close, full])
	print("  plan time   %.1f ms per sheet" % (ms / n))
	print("  violations  %s" % bad)
	quit(0 if bad == 0 else 1)
