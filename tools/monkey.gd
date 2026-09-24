## 1000 random-legal games. Prints property summary. Exit 1 on a leak.
extends SceneTree

const Bot := preload("res://engine/bot.gd")
const Types := preload("res://engine/types.gd")

const N := 1000


func _initialize() -> void:
	var map: Types.MapDef = Types.MapDef.from_file("res://maps/knife7.json")
	print("CONCURRENT monkey  n=%s" % N)
	var t0: int = Time.get_ticks_msec()
	var ok := 0
	var rounds := 0
	for i in N:
		var result: Dictionary = Bot.play_match(map, 1000 + i, i % 5 == 0)
		rounds += int(result["rounds"])
		if result["ok"]:
			ok += 1
		else:
			print("FAIL game %s: %s" % [i, " ".join(result["violations"])])
			quit(1)
			return
	var ms: int = Time.get_ticks_msec() - t0
	print("ok %s/%s  rounds=%s  ms=%s  avg_rounds=%.2f" % [ok, N, rounds, ms, float(rounds) / float(N)])
	if ms >= 30000:
		print("G3 FAIL  slower than 30s")
		quit(1)
	else:
		print("G3 ok  no leaked armies")
		quit(0)
