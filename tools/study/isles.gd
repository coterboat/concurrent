## Study (v1.12): on the Thousand Isles, does whoever holds Great Vane win? And what does a third
## crossing (Vaneholt - Kestrel Port) do to that?
##   $G --headless --path . --script res://tools/study/isles.gd -- n=40 variant=base|lane|lane_nofort|bonus3
extends SceneTree

const Types := preload("res://engine/types.gd")
const Autoplay := preload("res://engine/autoplay.gd")
const Combat := preload("res://engine/combat.gd")
const MapLib := preload("res://engine/map.gd")

var holds := {} ## this war: pid -> rounds holding all of Vane


func _initialize() -> void:
	var args := {"n": "40", "seed": "900", "variant": "base", "rules": "19"}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = str(a).split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	Autoplay.watch = _watch
	var wars := 0
	var vane_wars := 0 ## someone held Vane for 3+ rounds
	var vane_won := 0 ## ...and that someone won
	var wins := {}
	var lengths := 0
	var early := 0
	for i in int(args["n"]):
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/isles24.json")
		map.battle = "volleys"
		map.maneuvers = true
		map.scramble = true
		map.dig_cap = 3
		map.rules = int(args["rules"])
		map.fire_line = true
		map.capitals = true
		map.fortune = true
		Combat.line_size = 5
		var v: String = args["variant"]
		if v.begins_with("lane"):
			(map.get_territory("vaneholt") as Types.TerritoryDef).adjacent.append("kestrelport")
			(map.get_territory("kestrelport") as Types.TerritoryDef).adjacent.append("vaneholt")
		if v.begins_with("lane_nofort") or v == "nofort":
			var t: Types.TerritoryDef = map.get_territory("vaneholt")
			t.traits = PackedStringArray(Array(t.traits).filter(func(x): return x != "fort"))
			(map.get_territory("vanefell") as Types.TerritoryDef).traits.append("fort")
		if v.ends_with("bonus3"):
			map.region_bonus["vane"] = 3
		if v.begins_with("lane_nofort") or v == "nofort":
			pass
		var seats: Array = []
		var brains := ["general", "veteran", "recruit", "hask"]
		for k in brains.size():
			seats.append({"id": ["red", "blue", "green", "gold"][k], "name": brains[(k + i) % 4], "ai": brains[(k + i) % 4]})
		holds = {}
		var r: Dictionary = Autoplay.play(map, seats, int(args["seed"]) + i, 0, true)
		wars += 1
		lengths += int(r["roundsPlayed"])
		if r["early"]:
			early += 1
		var who: String = str(r["brains"].get(r["winner"], "none"))
		wins[who] = int(wins.get(who, 0)) + 1
		var top := ""
		var top_n := 0
		for pid in holds.keys():
			if int(holds[pid]) > top_n:
				top_n = int(holds[pid])
				top = str(pid)
		if top_n >= 3:
			vane_wars += 1
			if top == str(r["winner"]):
				vane_won += 1
	print("isles24 variant=%s wars=%d" % [args["variant"], wars])
	print("  Vane held 3+ rounds in %d wars; its holder won %d of them (%d%%)" % [vane_wars, vane_won, int(100.0 * vane_won / maxf(1.0, vane_wars))])
	print("  rounds mean %.1f, conquests %d/%d, wins %s" % [float(lengths) / wars, early, wars, wins])
	quit(0)


func _watch(w: Types.World, map: Types.MapDef) -> void:
	for pid in w.players.keys():
		if MapLib.holds_region(w, map, str(pid), "vane"):
			holds[pid] = int(holds.get(pid, 0)) + 1
