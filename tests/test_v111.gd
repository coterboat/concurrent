## v1.11: a line's words carry the voice's direction (*stress*); the subtitle drops the marks.
## And the redone volley sheets carry their shot marks again.
extends RefCounted

const Lines := preload("res://game/core/lines.gd")


func run(report: Callable, _tree: SceneTree) -> void:
	_subtitles(report)
	_sheet_marks(report)


func _subtitles(report: Callable) -> void:
	report.call(Lines.subtitle("They dare to sit in *my* capital?") == "They dare to sit in my capital?", "a stressed word loses its stars in the subtitle")
	report.call(Lines.subtitle("Gone... Taken.") == "Gone... Taken.", "a pause stays: it reads as one")
	## every line the game can show, drawn through Lines.text: none shows a star
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/lines.json"))
	var starred := 0
	var shown_bad := 0
	for who in (parsed["lines"] as Dictionary).keys():
		for key in (parsed["lines"][who] as Dictionary).keys():
			for take in Lines.takes(who, key):
				if str(take).contains("*"):
					starred += 1
			for i in 6:  ## the bag draws every take within a few calls
				if Lines.text(who, key).contains("*"):
					shown_bad += 1
	report.call(starred > 0 and shown_bad == 0, "%d lines carry stars for the voice; no subtitle shows one" % starred)


func _sheet_marks(report: Callable) -> void:
	for name in ["soldier_volley_kf", "soldier_kneel_volley_kf", "grenadier_volley_kf", "cannon_fire_kf"]:
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/battle/%s.json" % name))
		var ok: bool = typeof(m) == TYPE_DICTIONARY and int(m.get("shot", -1)) > 0 and int(m.get("shot", -1)) < int(m.get("frames", 0)) \
			and (m.get("muzzle", []) as Array).size() == 2
		report.call(ok, "%s is timed: shot on frame %s, muzzle at %s" % [name, m.get("shot") if m else "?", m.get("muzzle") if m else "?"])
	var fall: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/battle/soldier_fall_kf.json"))
	report.call(typeof(fall) == TYPE_DICTIONARY and int(fall.get("down", -1)) > 0, "the fall knows when he hits the ground (frame %s)" % [fall.get("down") if fall else "?"])
