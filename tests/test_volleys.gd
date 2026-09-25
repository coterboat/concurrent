## Roll-by-roll battles hold the v0.2 bands and the same bloodiness.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")
const Rng := preload("res://engine/rng.gd")
const Setup := preload("res://engine/setup.gd")
const Autoplay := preload("res://engine/autoplay.gd")

const V := "volleys"


func run(report: Callable) -> void:
	var bands := [[1, 1, 0.55, 0.61], [4, 4, 0.55, 0.61], [8, 8, 0.55, 0.61], [20, 20, 0.55, 0.62],
		[6, 4, 0.80, 0.90], [8, 5, 0.85, 0.95], [5, 8, 0.0, 0.20], [10, 5, 0.95, 1.0]]
	for b in bands:
		var p: float = Combat.capture_rate(b[0], b[1], V)
		report.call(p >= b[2] and p <= b[3], "volleys %sv%s capture %.1f%% in %d–%d%%" % [b[0], b[1], p * 100.0, int(b[2] * 100), int(b[3] * 100)])
	## the simulator agrees with the exact odds, and survivors match the decisive rule
	for c in [[8, 8], [6, 4], [12, 12], [3, 5]]:
		var wins := 0
		var rem_v := 0.0
		var rem_d := 0.0
		var n := 3000
		for i in n:
			var rng: RefCounted = Rng.derive_stream(5, i, "v")
			var f = Combat.invasion(c[0], c[1], rng, V)
			if f.attacker_won:
				wins += 1
			rem_v += f.winner_remaining
			var g = Combat.invasion(c[0], c[1], Rng.derive_stream(5, i, "d"))
			rem_d += g.winner_remaining
		var exact: float = Combat.capture_rate(c[0], c[1], V)
		report.call(absf(float(wins) / n - exact) < 0.03, "%sv%s simulated %.1f%% vs exact %.1f%%" % [c[0], c[1], 100.0 * wins / n, exact * 100.0])
		report.call(absf(rem_v / n - rem_d / n) < 1.0, "%sv%s survivors: volleys %.1f vs decisive %.1f" % [c[0], c[1], rem_v / n, rem_d / n])
	## every volley is on the record and replays to the result
	var ok := true
	for i in 300:
		var f = Combat.clash(1 + i % 13, 1 + (i * 7) % 11, Rng.derive_stream(9, i, "c"), V)
		var a: int = f.attacker_size
		var d: int = f.defender_size
		for r in f.rolls:
			if r["sa"] != a or r["sd"] != d:
				ok = false
			if r["w"] == "a":
				d -= 1
			elif r["w"] == "b":
				a -= 1
		if (a if f.attacker_won else d) != f.winner_remaining or (a > 0 and d > 0):
			ok = false
	report.call(ok, "each recorded volley replays to the battle's result")
	## whole wars, both maps, with army accounting (P2) on every round
	for mid in ["known24", "world30"]:
		var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
		map.battle = V
		var seats := [{"id": "red", "name": "a", "ai": "general"}, {"id": "blue", "name": "b", "ai": "hask"}, {"id": "green", "name": "c", "ai": "quill"}]
		var r: Dictionary = Autoplay.play(map, seats, 404)
		report.call(r["ok"] and str(r["winner"]) != "", "%s volleys war: legal, conserved, finished (%s)" % [mid, " ".join(r["violations"])])
