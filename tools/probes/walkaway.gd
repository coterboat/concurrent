## Repro: A captures B while B's army marches to C. Does B's army reach C?
extends RefCounted

const Types := preload("res://engine/types.gd")
const Resolve := preload("res://engine/resolve.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Hash := preload("res://engine/hash.gd")
const H := preload("res://tests/harness.gd")

func run(p) -> void:
	var map: Types.MapDef = H.knife7()
	## Red at Beacon hits Blue's Ridge; Blue's Ridge marches on the Gate / Mill.
	for dest in ["gate", "mill"]:
		for seed in [1, 2, 3, 4, 5]:
			var w: Types.World = H.paint(map, {
				"beacon": ["red", 9], "ridge": ["blue", 8], "mill": ["neutral", 2], "gate": ["neutral", 2],
				"harbor": ["red", 3], "docks": ["red", 3], "quarry": ["red", 3]})
			w.round = 2
			var red: Types.Sheet = H.sheet("red", [H.pkt("beacon", "ridge", 8)])
			var blue: Types.Sheet = H.sheet("blue", [H.pkt("ridge", dest, 7)])
			var r: Dictionary = Resolve.resolve_round(w, map, [red, blue], seed)
			var nw: Types.World = r["world"]
			var lines := PackedStringArray()
			for e in r["events"]:
				lines.append("%s %s" % [e["kind"], JSON.stringify(e).substr(0, 140)])
			var view: Types.World = ViewEvents.apply_through(w, r["events"], r["events"].size() - 1)
			p.log("dest=%s seed=%s  %s owner=%s armies=%s | ridge owner=%s | view==engine %s" % [dest, seed, dest, nw.get_territory(dest).owner, nw.get_territory(dest).held(), nw.get_territory("ridge").owner, Hash.world_hash(view) == Hash.world_hash(nw)])
			if seed == 1:
				for l in lines:
					p.log("   " + l)
