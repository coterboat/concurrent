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
	var art := TextureRect.new()
	art.texture = Style.tex("res://assets/art/victory.webp" if (humans_won or not any_human) else "res://assets/art/defeat.webp")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	art.modulate = Color(0.55, 0.55, 0.6)
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
	g.columns = 7
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 6)
	for h in ["", "Commander", "Score", "Captures", "Walk-ins", "Battles won", "Sets"]:
		g.add_child(Style.label(h, 16, Style.GOLD, "bold"))
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
		place += 1
	lv.add_child(g)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", Style.panel_box(18))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(Style.label("Lands held, round by round", 24, Style.GOLD, "display"))
	var chart := _Chart.new()
	chart.session = s
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.custom_minimum_size = Vector2(0, 260)
	rv.add_child(chart)

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

	func _draw() -> void:
		var h: Array = session.history
		if h.size() < 2:
			return
		var pad := Vector2(40, 16)
		var area := Rect2(pad, size - pad * 2)
		var max_v := 1
		for snap in h:
			for pid in snap["terr"].keys():
				max_v = maxi(max_v, int(snap["terr"][pid]))
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
				var v: float = float(h[i]["terr"].get(pid, 0))
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
