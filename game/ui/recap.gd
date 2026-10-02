## After the cinema: what happened this round, who leads, what comes next.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const Moments := preload("res://game/ui/moments.gd")

signal continue_pressed

var session: Node
var _panel: PanelContainer
var _box: VBoxContainer


static func lead_said(to_name: String, from_name: String) -> String:
	## "Varek takes the lead from you." / "You take the lead from Varek." (B-012: the seat called You)
	if from_name == "":
		return "%s the lead." % Style.says(to_name, "takes")
	return "%s the lead from %s." % [Style.says(to_name, "takes"), Style.who(from_name)]


static func defeat_title(fell: Array) -> String:
	## "You have been defeated", "Dad has been defeated", "Dad and Mum have been defeated" (B-010)
	if fell.size() == 1:
		return "%s been defeated" % Style.says(str(fell[0]), "has")
	return "%s have been defeated" % " and ".join(fell)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Style.panel_box(24))
	_panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)


func show_round() -> void:
	for c in _box.get_children():
		c.queue_free()
	var s = session
	var n: int = s.world.round - 1
	var title := "Round %d report" % n
	if s.winner != "":
		title = "The final reckoning"
	_box.add_child(_center(Style.label(title, 34, Style.CREAM, "display")))
	var lines: Array = _lines(s.events)
	## v1.13: the moments first: a new leader, a capital won back
	for rt in Moments.retaken(s.events, s.capital_log):
		lines.insert(0, ["crown", "%s won back %s, the capital lost in round %d." % [s.name_of(str(rt["pid"])), s.hex_name(str(rt["land"])), int(rt["round"])], Style.GOLD])
	var lc: Dictionary = Moments.lead_change(s.history)
	if not lc.is_empty() and s.winner == "":
		var from: String = str(lc.get("from", ""))
		lines.insert(0, ["crown", lead_said(s.name_of(str(lc["to"])), s.name_of(from) if from != "" else ""),
			Style.seat_color(str(lc["to"])).lightened(0.45)])
	if lines.is_empty():
		lines.append(["scroll", "A quiet round. Nobody lost an inch.", Style.MUTED])
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	for l in lines.slice(0, 11):
		list.add_child(_line(l[0], l[1], l[2]))
	if lines.size() > 11:
		list.add_child(Style.label("…and %d more." % (lines.size() - 11), 16, Style.MUTED, "italic"))
	_box.add_child(list)
	_box.add_child(HSeparator.new())
	_box.add_child(_standings())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := "See who won" if s.winner != "" else ("Begin the final round" if s.world.round == s.rounds_total() and not s.conquest() else "Next round")
	var b := Style.button(label + "  ▶", func(): continue_pressed.emit(), 320, 24)
	b.custom_minimum_size = Vector2(320, 60)
	foot.add_child(b)
	_box.add_child(foot)
	visible = true
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.25)


func _center(c: Control) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(c)
	return h


func _line(icon_name: String, text: String, color: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var ic := TextureRect.new()
	ic.texture = Style.icon(icon_name)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(26, 26)
	h.add_child(ic)
	var l := Style.label(text, 19, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


func _lines(evs: Array) -> Array:
	var s = session
	var out: Array = []
	var vacated := {}
	var took := {} ## pid -> [hex names]
	for e in evs:
		var k: String = str(e["kind"])
		match k:
			Types.EVENT_VACATED:
				vacated[str(e["from"])] = str(e["playerId"])
			Types.EVENT_OCCUPIED:
				var hex: String = str(e["terrId"])
				var who: String = str(e["playerId"])
				if vacated.has(hex) and vacated[hex] != who:
					out.append(["skull", "Walk-in: %s took %s while %s away." % [s.name_of(who), s.hex_name(hex), Style.says(Style.who(s.name_of(vacated[hex])), "was")], Style.CRIMSON.lightened(0.35)])
				else:
					if not took.has(who):
						took[who] = []
					took[who].append(s.hex_name(hex))
			Types.EVENT_INVASION:
				if not bool(e["attackerWon"]):
					var fell: String = ""
					if bool(e.get("fellBack", false)):
						fell = " (%d fell back to %s)" % [int(e.get("attackerLeft", 0)), s.hex_name(str(e.get("refuge", "")))]
					out.append(["shield", "%s held %s against %s%s." % [s.name_of(str(e["defenderId"])), s.hex_name(str(e["to"])), Style.who(s.name_of(str(e["attackerId"]))), fell], Style.PARCH])
			Types.EVENT_MELEE:
				## v1.13: several at once against one land
				if int(e.get("defenderLeft", 0)) > 0:
					var foes: Array = []
					for f in e.get("fronts", []):
						foes.append(Style.who(s.name_of(str(f.get("attackerId", "")))))
					out.append(["shield", "%s held %s against %s at once." % [s.name_of(str(e.get("defenderId", ""))), s.hex_name(str(e.get("to", ""))), _join(foes)], Style.PARCH])
			Types.EVENT_SCRAMBLE:
				var rivals: Array = []
				for f in e.get("fronts", []):
					if str(f.get("playerId", "")) != str(e.get("winnerId", "")):
						rivals.append(Style.who(s.name_of(str(f.get("playerId", "")))))
				out.append(["attack", "%s won the scramble for %s against %s." % [s.name_of(str(e.get("winnerId", ""))), s.hex_name(str(e.get("to", ""))), _join(rivals)], Style.PARCH])
			Types.EVENT_CAPITAL_TAKEN:
				out.append(["crown", "%s took %s capital, %s." % [s.name_of(str(e.get("by", ""))), Style.owns(s.name_of(str(e.get("playerId", "")))), s.hex_name(str(e.get("terrId", "")))], Style.GOLD])
			Types.EVENT_CLASH:
				## v1.13: named by the road it was fought on (hexB was one end of it, not "where" it was)
				var loser: String = str(e["playerB"]) if str(e["winnerId"]) == str(e["playerA"]) else str(e["playerA"])
				out.append(["attack", "%s beat %s column on the road between %s and %s." % [s.name_of(str(e["winnerId"])), Style.owns(s.name_of(loser)), s.hex_name(str(e["hexA"])), s.hex_name(str(e["hexB"]))], Style.PARCH])
			Types.EVENT_PLAYER_ELIMINATED:
				out.append(["skull", "%s been eliminated." % Style.says(s.name_of(str(e["playerId"])), "has"), Style.CRIMSON.lightened(0.3)])
			Types.EVENT_SET_CASHED:
				out.append(["coins", "%s traded a card set for +%d armies." % [s.name_of(str(e["playerId"])), int(e["value"])], Style.GOLD])
			Types.EVENT_CARDS_CAPTURED:
				out.append(["coins", "%s seized %s cards." % [s.name_of(str(e["to"])), Style.owns(s.name_of(str(e["from"])))], Style.GOLD])
	for who in took.keys():
		var names: Array = took[who]
		out.insert(0, ["flag", "%s captured %s." % [s.name_of(who), _join(names)], Style.seat_color(who).lightened(0.4)])
	return out


func _join(names: Array) -> String:
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names[-1])


func _standings() -> Control:
	var s = session
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 4)
	for h in ["Commander", "Score", "Change", "Lands", "Armies", "Next income"]:
		g.add_child(Style.label(h, 16, Style.GOLD, "bold"))
	var prev: Dictionary = s.history[s.history.size() - 2]["score"] if s.history.size() >= 2 else {}
	for r in s.standings():
		var col: Color = Style.seat_color(r["id"]).lightened(0.35) if r["alive"] else Style.MUTED
		g.add_child(Style.label(("%s" % r["name"]) + ("" if r["alive"] else "  (out)"), 19, col, "bold"))
		g.add_child(Style.label("%d" % r["score"], 19, Style.CREAM, "display"))
		var d: int = int(r["score"]) - int(prev.get(r["id"], r["score"]))
		g.add_child(Style.label(("+%d" % d) if d > 0 else ("%d" % d if d < 0 else "–"), 18, Style.GOOD if d > 0 else (Style.CRIMSON.lightened(0.3) if d < 0 else Style.MUTED), "bold"))
		g.add_child(Style.label("%d" % r["lands"], 18, Style.CREAM))
		g.add_child(Style.label("%d" % r["armies"], 18, Style.CREAM))
		g.add_child(Style.label("%d" % r["income"] if r["alive"] else "–", 18, Style.CREAM))
	return g
