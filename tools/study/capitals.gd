## Study (v1.12): what a commander's new capital gets after the old one falls, in AI wars.
##   $G --headless --path . --script res://tools/study/capitals.gd -- map=isles24 n=30
extends SceneTree

const Types := preload("res://engine/types.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Combat := preload("res://engine/combat.gd")


func _initialize() -> void:
	var args := {"map": "isles24", "n": "30", "seed": "700", "rules": "19"}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = str(a).split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	Autoplay.keep_events = true
	var falls := 0
	var placed_new := []
	var placed_all := []
	var held_new := []
	var moved := 0
	for i in int(args["n"]):
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % args["map"])
		map.battle = "volleys"
		map.maneuvers = true
		map.scramble = true
		map.dig_cap = 3
		map.rules = int(args["rules"])
		map.fire_line = true
		map.capitals = true
		map.fortune = true
		Combat.line_size = 5
		var seats: Array = []
		var brains := ["general", "veteran", "recruit", "hask"]
		for k in brains.size():
			seats.append({"id": ["red", "blue", "green", "gold"][k], "name": brains[(k + i) % 4], "ai": brains[(k + i) % 4]})
		var r: Dictionary = Autoplay.play(map, seats, int(args["seed"]) + i, 0, true)
		var evs: Array = r["events"]
		## split into rounds
		var rounds: Array = [[]]
		for e in evs:
			(rounds[-1] as Array).append(e)
			if str(e.get("kind", "")) == Types.EVENT_ROUND_ENDED:
				rounds.append([])
		for ri in rounds.size():
			for e in rounds[ri]:
				if str(e.get("kind", "")) != Types.EVENT_CAPITAL_FOUNDED or str(e.get("why", "")) != "fallen":
					continue
				falls += 1
				var pid: String = str(e["playerId"])
				var cap: String = str(e["terrId"])
				if ri + 1 >= rounds.size():
					continue
				var on_cap := 0
				var total := 0
				var after := -1
				for e2 in rounds[ri + 1]:
					if str(e2.get("kind", "")) == Types.EVENT_CAPITAL_FOUNDED and str(e2.get("playerId", "")) == pid and str(e2.get("why", "")) == "moved":
						cap = str(e2["terrId"])
						moved += 1
					if str(e2.get("kind", "")) == Types.EVENT_PLACED and str(e2.get("playerId", "")) == pid:
						total += int(e2.get("added", 0))
						if str(e2.get("terrId", "")) == cap:
							on_cap += int(e2.get("added", 0))
							after = int(e2.get("armies", -1))
				placed_new.append(on_cap)
				placed_all.append(total)
				held_new.append(after)
	var mean := func(a: Array) -> float:
		var s := 0.0
		for v in a:
			s += float(v)
		return s / maxf(1.0, float(a.size()))
	print("map=%s wars=%s capital falls=%d" % [args["map"], args["n"], falls])
	print("  the round after: recruits placed on the new capital mean %.1f (of %.1f placed in all)" % [mean.call(placed_new), mean.call(placed_all)])
	placed_new.sort()
	print("  on the new capital: %s  (moved in %d cases)" % [str(placed_new), moved])
	held_new.sort()
	print("  its armies after placing: %s" % str(held_new))
	quit(0)
