## The end of the war: winner, standings, the lands-over-time chart, and stats.
extends Control

const Style := preload("res://game/core/style.gd")

signal again_pressed
signal menu_pressed

var session: Node


func show_result() -> void:
	for c in get_children():
		c.queue_free()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var s = session
	var humans_won: bool = s.is_human(s.winner)
	var any_human := false
	for seat in s.seats:
		if seat["kind"] == "human":
			any_human = true
	## v1.9: the victory (or defeat) painting breathes behind the tally
	var good: bool = humans_won or not any_human
	var art: Control = load("res://game/ui/living_painting.gd").new()
	art.setup("res://assets/art/victory.webp" if good else "res://assets/art/defeat.webp",
		"res://assets/video/victory_loop.ogv" if good else "res://assets/video/defeat_loop.ogv", Color(0.55, 0.55, 0.6))
	add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.45)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 50)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var head: String
	if s.winner == "":
		head = "The war ends"
	elif humans_won:
		head = "Victory for %s!" % s.name_of(s.winner)
	else:
		head = "%s wins the war" % s.name_of(s.winner)
	var t := Style.label(head, 58, Style.CREAM, "display")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	v.add_child(t)
	var how := "by holding %d%% of the world" % 80 if s.early and s.standings().filter(func(r): return r["alive"]).size() > 1 else ("as the last commander standing" if s.early else "on points after %d rounds" % (s.world.round - 1))
	var sub := Style.label(how, 24, Style.PARCH, "italic")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", Style.panel_box(18))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lv.add_child(Style.label("Final standings", 24, Style.GOLD, "display"))
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 6)
	for h in ["", "Commander", "Score", "Captures", "Walk-ins", "Battles won", "Sets", "Luck"]:
		var hl := Style.label(h, 16, Style.GOLD, "bold")
		if h == "Luck":
			hl.tooltip_text = "Battles won beyond (or short of) what the odds said when each one began.\n+2 means the dice handed you two battles you should have lost."
			hl.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(hl)
	var place := 1
	for r in s.standings():
		var st: Dictionary = s.stats.get(r["id"], {})
		var col: Color = Style.seat_color(r["id"]).lightened(0.35)
		g.add_child(Style.label("%d." % place, 20, Style.PARCH, "display"))
		g.add_child(Style.label(str(r["name"]) + ("" if r["alive"] else " (out)"), 20, col, "bold"))
		g.add_child(Style.label("%d" % r["score"], 20, Style.CREAM, "display"))
		g.add_child(Style.label("%d" % int(st.get("captures", 0)), 19, Style.CREAM))
		g.add_child(Style.label("%d" % int(st.get("walkins", 0)), 19, Style.CREAM))
		g.add_child(Style.label("%d / %d" % [int(st.get("won", 0)), int(st.get("battles", 0))], 19, Style.CREAM))
		g.add_child(Style.label("%d" % int(st.get("sets", 0)), 19, Style.CREAM))
		## v1.8: the luck ledger — did the dice owe you, or you them?
		var lk: Dictionary = s.luck_of(str(r["id"]))
		var sw: float = float(lk["swing"])
		var lcol: Color = Style.GOOD if sw >= 0.75 else (Style.CRIMSON.lightened(0.35) if sw <= -0.75 else Style.CREAM)
		var lword: String = " blessed" if sw >= 2.5 else (" cursed" if sw <= -2.5 else "")
		var ll := Style.label(("%+.1f" % sw) + lword if int(lk["n"]) > 0 else "—", 19, lcol, "bold")
		if int(lk.get("measured", 0)) > 0:
			ll.tooltip_text = "The dice's swing over %d battles, weighed exchange by exchange against the odds: %+.1f battles' worth.\n(A battle you fell back from counts for the volleys fought.)" % [int(lk["n"]), sw]
		else:
			ll.tooltip_text = "Won %d of %d one-on-one battles; the odds said %.1f." % [int(lk["won"]), int(lk["n"]), float(lk["expected"])]
		ll.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(ll)
		place += 1
	lv.add_child(g)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", Style.panel_box(18))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var ch_head := HBoxContainer.new()
	ch_head.add_theme_constant_override("separation", 8)
	var ch_title := Style.label("Lands held, round by round", 24, Style.GOLD, "display")
	ch_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch_head.add_child(ch_title)
	rv.add_child(ch_head)
	var chart := _Chart.new()
	chart.session = s
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.custom_minimum_size = Vector2(0, 260)
	## v1.6: the chart by lands, armies or score; card sets turned in are marked on it
	var modes := [["terr", "Lands", "Lands held, round by round"], ["armies", "Armies", "Armies in the field, round by round"], ["score", "Score", "Score, round by round"]]
	var chips: Array = []
	for md in modes:
		var mkey: String = md[0]
		var chip := Style.chip(md[1], func():
			chart.mode = mkey
			ch_title.text = md[2]
			for c2 in chips:
				(c2 as Button).modulate = Color(1, 1, 1, 0.55)
			chips[modes.find(md)].modulate = Color.WHITE
			chart.queue_redraw()
			Audio.sfx("click", -6.0), Style.CREAM, 14)
		chip.modulate = Color.WHITE if mkey == "terr" else Color(1, 1, 1, 0.55)
		chips.append(chip)
		ch_head.add_child(chip)
	rv.add_child(chart)
	var keys: Array = []
	if not s.cash_log.is_empty():
		keys.append("▣ +N: a set of cards turned in, in the commander's colour")
	if not s.capital_log.is_empty():
		keys.append("♛ a capital taken: on the line of the commander who lost it, ringed in the captor's colour")
	if not keys.is_empty():
		var key := Style.label("    ".join(keys), 13, Style.MUTED, "italic")
		key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(key)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	btns.add_child(Style.button("Play again", func(): again_pressed.emit(), 260, 24))
	btns.add_child(Style.button("Main menu", func(): menu_pressed.emit(), 260, 24))
	v.add_child(btns)
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)


class _Chart extends Control:
	const Style := preload("res://game/core/style.gd")
	var session: Node
	var mode := "terr" ## terr | armies | score

	func _draw() -> void:
		var h: Array = session.history
		if h.size() < 2:
			return
		var pad := Vector2(40, 16)
		var area := Rect2(pad, size - pad * 2)
		var max_v := 1
		for snap in h:
			var series: Dictionary = snap.get(mode, snap["terr"])
			for pid in series.keys():
				max_v = maxi(max_v, int(series[pid]))
		var f := Style.font("body")
		for k in 5:
			var y: float = area.position.y + area.size.y * (1.0 - float(k) / 4.0)
			draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(1, 1, 1, 0.08), 1.0)
			draw_string(f, Vector2(4, y + 5), str(int(round(max_v * k / 4.0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Style.MUTED)
		for seat in session.seats:
			var pid: String = seat["id"]
			var pts := PackedVector2Array()
			for i in h.size():
				var x: float = area.position.x + area.size.x * float(i) / float(h.size() - 1)
				var v: float = float((h[i] as Dictionary).get(mode, h[i]["terr"]).get(pid, 0))
				pts.append(Vector2(x, area.end.y - area.size.y * v / float(max_v)))
			var col: Color = Style.seat_color(pid).lightened(0.2)
			draw_polyline(pts, Color(0, 0, 0, 0.5), 6.0, true)
			draw_polyline(pts, col, 3.5, true)
			for p in pts:
				draw_circle(p, 4.0, col)
			draw_string(Style.font("bold"), pts[pts.size() - 1] + Vector2(-60, -10), str(seat["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		for i in h.size():
			var x2: float = area.position.x + area.size.x * float(i) / float(h.size() - 1)
			draw_string(f, Vector2(x2 - 4, size.y), str(h[i]["round"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Style.MUTED)
		## card sets turned in: a little card in the commander's colour on their line, with its worth
		var stack := {}
		for c in session.cash_log:
			var idx := -1
			for i in h.size():
				if int(h[i]["round"]) == int(c["round"]):
					idx = i
			if idx < 0:
				continue
			var pid2: String = str(c["pid"])
			var series2: Dictionary = (h[idx] as Dictionary).get(mode, h[idx]["terr"])
			var x3: float = area.position.x + area.size.x * float(idx) / float(h.size() - 1)
			var y3: float = area.end.y - area.size.y * float(series2.get(pid2, 0)) / float(max_v)
			var k: int = int(stack.get(idx, 0))
			stack[idx] = k + 1
			var at := Vector2(x3 - 7, y3 - 30 - k * 22)
			var col2: Color = Style.seat_color(pid2).lightened(0.2)
			draw_rect(Rect2(at, Vector2(14, 19)), Color(0.08, 0.05, 0.03), true)
			draw_rect(Rect2(at + Vector2(1.5, 1.5), Vector2(11, 16)), col2, true)
			draw_rect(Rect2(at + Vector2(3.5, 3.5), Vector2(7, 12)), Color(0.97, 0.93, 0.82, 0.9), false, 1.2)
			draw_string_outline(Style.font("bold"), at + Vector2(17, 15), "+%d" % int(c["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
			draw_string(Style.font("bold"), at + Vector2(17, 15), "+%d" % int(c["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col2)
		## v1.9: capitals taken: a crown on the fallen commander's line, ringed in the captor's colour
		var crown: Texture2D = Style.tex("res://assets/icons/crown.png")
		for cl in session.capital_log:
			var ci := -1
			for i in h.size():
				if int(h[i]["round"]) == int(cl["round"]):
					ci = i
			if ci < 0:
				continue
			var lost: String = str(cl["pid"])
			var series3: Dictionary = (h[ci] as Dictionary).get(mode, h[ci]["terr"])
			var cx: float = area.position.x + area.size.x * float(ci) / float(h.size() - 1)
			var cy: float = area.end.y - area.size.y * float(series3.get(lost, 0)) / float(max_v)
			var k2: int = int(stack.get(ci, 0))
			stack[ci] = k2 + 1
			var at2 := Vector2(cx, cy + 26 + k2 * 4) if cy < area.position.y + 40 else Vector2(cx, cy - 26 - k2 * 22)
			var ring: Color = Style.seat_color(str(cl["by"])).lightened(0.2)
			draw_line(Vector2(cx, cy), at2, Color(ring, 0.7), 2.0, true)
			draw_circle(at2, 14.0, Color(0.06, 0.04, 0.03, 0.95))
			draw_arc(at2, 14.0, 0.0, TAU, 32, ring, 3.0, true)
			if crown != null:
				draw_texture_rect(crown, Rect2(at2 - Vector2(10, 10), Vector2(20, 20)), false, Style.seat_color(lost).lightened(0.55))
			else:
				draw_string(Style.font("bold"), at2 + Vector2(-6, 6), "♛", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Style.GOLD)
