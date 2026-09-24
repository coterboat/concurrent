## Cinema view-world follows engine events. No Node.
extends RefCounted

const Types := preload("res://engine/types.gd")
const H := preload("res://tests/harness.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Events := preload("res://engine/events.gd")


func run(report: Callable) -> void:
	var map: Types.MapDef = H.knife7()
	var world: Types.World = H.paint(map, {
		"ridge": ["red", 5],
		"beacon": ["red", 1],
		"mill": ["", 0],
		"gate": ["green", 4],
		"harbor": ["green", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	var e: Dictionary = Events.vacated("red", "ridge", "mill", 4, 1)
	var w: Types.World = world.clone()
	ViewEvents.apply(w, e)
	report.call(w.get_territory("ridge").armies == 1, "cinema vacate leaves 1 on origin")
	report.call(w.get_territory("ridge").owner == "red", "cinema vacate keeps owner while 1 remains")
	var cap: String = ViewEvents.caption(e)
	report.call(cap.contains("ridge") and cap.contains("mill"), "caption names the walk")
	var occ: Dictionary = Events.occupied("green", "ridge", 3)
	ViewEvents.apply(w, occ)
	report.call(w.get_territory("ridge").owner == "green" and w.get_territory("ridge").armies == 3, "cinema occupy updates the hex")
	var through: Types.World = ViewEvents.apply_through(world, [e, occ], 0)
	report.call(through.get_territory("ridge").armies == 1, "apply_through index 0 is only vacate")
	report.call(through.get_territory("ridge").owner == "red", "dice have not run yet at vacate beat")
	var spoils: Dictionary = Events.spoils_event("mill", "blue", "red", _fake_fight(false, 2))
	var mill: Types.World = H.paint(map, {
		"ridge": ["red", 1],
		"beacon": ["red", 1],
		"mill": ["red", 4],
		"gate": ["green", 1],
		"harbor": ["blue", 1],
		"docks": ["blue", 1],
		"quarry": ["blue", 1],
	})
	ViewEvents.apply(mill, spoils)
	report.call(mill.get_territory("mill").owner == "red", "cinema spoils defender keeps the hex")
	report.call(mill.get_territory("mill").armies == 2, "cinema spoils defender remnant is winnerRemaining")
	_recap(report, map)


func _recap(report: Callable, map: Types.MapDef) -> void:
	var events: Array = [
		Events.vacated("red", "ridge", "mill", 4, 0),
		Events.became_unoccupied("ridge", "red"),
		Events.occupied("green", "ridge", 3),
		Events.score({"red": 2, "green": 4}, "green"),
		Events.round_ended(1, "", false),
	]
	var lines: PackedStringArray = ViewEvents.recap(events, map)
	var blob: String = " ".join(lines)
	report.call(blob.contains("Walk-in") and blob.contains("Ridge"), "recap names the walk-in on Ridge")
	report.call(blob.contains("Leader green") or blob.contains("leader green"), "recap names the leader")
	report.call(blob.contains("Round 1"), "recap names the round")


func _fake_fight(attacker_won: bool, remaining: int):
	var Combat := preload("res://engine/combat.gd")
	var f = Combat.FightResult.new()
	f.attacker_won = attacker_won
	f.winner_remaining = remaining
	f.attacker_size = 5
	f.defender_size = 4
	f.attacker_die = 2
	f.defender_die = 6
	f.attacker_total = 7
	f.defender_total = 10
	return f
