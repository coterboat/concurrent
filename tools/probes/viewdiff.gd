## Does the cinema's replay of events land on the engine's world, territory by territory?
extends RefCounted

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Resolve := preload("res://engine/resolve.gd")
const Ai := preload("res://engine/ai.gd")
const Rng := preload("res://engine/rng.gd")
const ViewEvents := preload("res://game/view_events.gd")

func run(p) -> void:
	var bad := 0
	var checked := 0
	for mid in ["knife7", "known24", "world30"]:
		for seed in range(1, 13):
			var map: Types.MapDef = Types.MapDef.from_file("res://maps/%s.json" % mid)
			var n: int = 2 if mid == "knife7" else 4
			var seats: Array = []
			var brains := ["hask", "veteran", "quill", "oren"]
			for i in n:
				seats.append({"id": Setup.SEAT_IDS[i], "name": "x"})
			var w: Types.World = Setup.deal(map, seats, seed)
			var open := {}
			for pid in MapLib.living_player_ids(w):
				open[pid] = Ai.opening_placements(w, map, pid, Rng.derive_stream(seed, 0, pid), Ai.profile_for("veteran"))
			Setup.apply_opening(w, map, open)
			for r in 12:
				var sheets: Array = []
				var i := 0
				for pid in MapLib.living_player_ids(w):
					sheets.append(Ai.plan(w, map, pid, Rng.derive_stream(seed, w.round, pid), Ai.profile_for(brains[i % 4])))
					i += 1
				var res: Dictionary = Resolve.resolve_round(w, map, sheets, seed)
				var view: Types.World = ViewEvents.apply_through(w, res["events"], res["events"].size() - 1)
				var nw: Types.World = res["world"]
				checked += 1
				for t in nw.territories.keys():
					var a: Types.TerritoryState = view.get_territory(t)
					var b: Types.TerritoryState = nw.get_territory(t)
					if a.owner != b.owner or a.armies != b.armies or a.garrison != b.garrison:
						bad += 1
						if bad <= 12:
							p.log("%s seed %s r%s %s: view %s %s+%s  engine %s %s+%s" % [mid, seed, w.round, t, a.owner, a.armies, a.garrison, b.owner, b.armies, b.garrison])
							for e in res["events"]:
								if JSON.stringify(e).contains('"%s"' % t):
									p.log("      " + JSON.stringify(e).substr(0, 200))
				w = nw
				var won := false
				for e in res["events"]:
					if str(e["kind"]) == "RoundEnded" and str(e["winner"]) != "":
						won = true
				if won:
					break
	p.log("rounds checked %d, territory mismatches %d" % [checked, bad])
