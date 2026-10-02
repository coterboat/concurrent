## v1.14: a senior pass on the polish. Display only (no rules change: games still play rules 20).
## The seat called You reads right everywhere (the bot's B-009 to B-012), and the board keeps its
## marks off each other (fate marks, CUT OFF, a region's bonus and its pips).
extends RefCounted

const Types := preload("res://engine/types.gd")
const Session := preload("res://game/core/session.gd")
const Style := preload("res://game/core/style.gd")
const LandTip := preload("res://game/ui/land_tip.gd")
const Recap := preload("res://game/ui/recap.gd")
const BoardFacts := preload("res://game/core/board_facts.gd")
const MapLib := preload("res://engine/map.gd")


func run(report: Callable, tree: SceneTree) -> void:
	_you_reads_right(report, tree)


func _you_reads_right(report: Callable, tree: SceneTree) -> void:
	## the playtest bot's report on cd3b208: B-009 to B-012, all the seat called You
	var s: Node = Session.new()
	s.instant = true
	tree.root.add_child(s)
	s.new_game({"map": "res://maps/ring26.json", "seed": 1, "length": "short", "seats": [
		{"id": "red", "name": "You", "kind": "human", "ai": ""},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill"}]})
	## B-009: the land tooltip's region line, with You holding all of a region, then most of one
	var region: String = str(s.map.region_bonus.keys()[0])
	var members: PackedStringArray = MapLib.region_members(s.map, region)
	var w: Types.World = s.world.clone()
	for id in members:
		w.get_territory(id).owner = "red"
	var all_line: String = LandTip._region(s, w, region)
	w.get_territory(members[0]).owner = "blue"
	var most_line: String = LandTip._region(s, w, region)
	report.call(all_line.contains("You hold it all") and most_line.contains("You hold %d of %d" % [members.size() - 1, members.size()])
		and not (all_line + most_line).contains("You holds"),
		"B-009: the tooltip's region line says \"You hold\" (%s / %s)" % [all_line, most_line])
	for id in members:
		w.get_territory(id).owner = "blue"
	var theirs: String = LandTip._region(s, w, region)
	report.call(theirs.contains("Captain Oren holds it all"), "B-009: and a rival still \"holds\" (%s)" % theirs)
	## B-010: the defeat notice
	report.call(Recap.defeat_title(["You"]) == "You have been defeated" and Recap.defeat_title(["Dad"]) == "Dad has been defeated"
		and Recap.defeat_title(["Dad", "Mum"]) == "Dad and Mum have been defeated",
		"B-010: \"You have been defeated\", \"Dad has been defeated\", \"Dad and Mum have been defeated\"")
	## B-011: the claiming phase's pick
	report.call("%s pick" % Style.owns("You", true) == "Your pick" and "%s pick" % Style.owns("Captain Oren", true) == "Captain Oren's pick",
		"B-011: claiming reads \"Your pick\" and \"Captain Oren's pick\"")
	## B-012: the recap's lead change, both ways round
	var a: String = Recap.lead_said("Captain Oren", "You")
	var b: String = Recap.lead_said("You", "Captain Oren")
	var c: String = Recap.lead_said("You", "")
	report.call(a == "Captain Oren takes the lead from you." and b == "You take the lead from Captain Oren." and c == "You take the lead.",
		"B-012: the lead changes hands in plain English (%s / %s / %s)" % [a, b, c])
	## and the others the sweep found: the fallen card, the roster's tooltip
	report.call(("%s fallen" % Style.says("You", "has")).to_upper() == "YOU HAVE FALLEN" and Style.says("You", "raises") == "You raise",
		"the fallen card and the roster's recruits read \"YOU HAVE FALLEN\", \"You raise\"")
	s.queue_free()
