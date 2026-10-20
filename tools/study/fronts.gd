## v2.3 study: what a split attack is really worth under rules 21+, against what the AI thinks it is.
## The AI prices an attack from two lands as one force of their sum (Combat.capture_rate), but since
## rules 21 the two columns are two fronts and the defenders' whole firing line answers each. This
## storms The Gate from Ridge and Harbor with every split of a force, many seeds each, and prints the
## real capture rate beside the one-force estimate and the v2.3 price (Combat.fronts_capture_rate).
##   $G --headless --path . --script res://tools/study/fronts.gd -- n=200
extends SceneTree

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const Combat := preload("res://engine/combat.gd")
const Resolve := preload("res://engine/resolve.gd")


func _init() -> void:
	var n := 200
	for a in OS.get_cmdline_user_args():
		if a.begins_with("n="):
			n = int(a.trim_prefix("n="))
	var m: Types.MapDef = H.knife7()
	m.battle = Combat.MODE_VOLLEYS
	m.scramble = true
	m.dig_cap = 3
	m.rules = 22
	m.fire_line = true
	m.wild_cards = false
	Combat.use_rules(m)
	print("def  total  one-force  split (big+small): real capture rate")
	for d in [3, 5, 7, 9, 12]:
		for total in [d + 2, d + 5, d * 2, d * 2 + 6]:
			var line := "%3d  %5d    %5.0f%%  " % [d, total, 100.0 * Combat.capture_rate(total, d, m.battle)]
			for small in [total / 2, maxi(1, total / 4), 2]:
				var big: int = total - small
				if small < 1 or big < 1:
					continue
				var won := 0
				for sd in range(1, n + 1):
					var w: Types.World = H.paint(m, {"ridge": ["red", big + 1], "harbor": ["red", small + 1], "gate": ["blue", d],
						"beacon": ["blue", 1], "mill": ["blue", 1], "docks": ["blue", 1], "quarry": ["blue", 1]})
					var res: Dictionary = Resolve.resolve_round(w, m, [H.sheet("red", [H.pkt("ridge", "gate", big), H.pkt("harbor", "gate", small)]), H.sheet("blue")], sd * 7919)
					if (res["world"] as Types.World).get_territory("gate").owner == "red":
						won += 1
				line += "  %d+%d %3.0f%% (priced %2.0f%%)" % [big, small, 100.0 * won / n, 100.0 * Combat.fronts_capture_rate([big, small], d)]
			print(line)
	Combat.use_rules(null)
	quit(0)
