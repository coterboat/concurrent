## v2.2: which dice are rolling where. In a melee every front throws at once, and when one
## commander comes at a land from two of his own, both fronts' dice wear his colour. So each pair
## on the table carries a tag on the far rail naming its front ("from Ridge"), the same name its
## army carries on its plate on the field, and as a pair is read a thread runs from its tag up to
## that army's plate (which swells) while the shots fly on the field (diorama.gd's tracers).
## (Peeled from battle_theater.gd: the theater says what each pair is, this draws it.)
extends Control

const Style := preload("res://game/core/style.gd")

const THREAD_LIFE := 0.8 ## seconds a thread is on screen
const TAG_H := 24.0

var tags: Array = [] ## one per pair in the throw on the table: {node, sb, text, armies: [int], col}
var threads: Array = [] ## {from, to, col, t, army, pair, won (the pair's winner, "" for an even one)}
var _field: Control ## where the threads end (it says where each army's plate is)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func clear() -> void:
	for t in tags:
		(t["node"] as Node).queue_free()
	tags = []
	threads = []
	queue_redraw()


func place(tray: Control, pairs: Array) -> void:
	## pairs: [{text, col, armies}] in the throw's order, left to right: a tag over each on the
	## tray's far rail (the dice of pair k are tray dice 2k and 2k + 1)
	clear()
	for k in pairs.size():
		var pr: Dictionary = pairs[k]
		var text: String = str(pr.get("text", ""))
		if text == "":
			tags.append({"node": Control.new(), "sb": null, "text": "", "armies": [], "col": Color.WHITE})
			add_child(tags[-1]["node"])
			continue
		var col: Color = pr["col"]
		var tag := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.88)
		sb.border_color = col
		sb.set_border_width_all(2)
		sb.border_width_left = 6
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 0
		sb.content_margin_bottom = 1
		tag.add_theme_stylebox_override("panel", sb)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Style.label(text, 15, col.lightened(0.55), "italic")
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(l)
		add_child(tag)
		tag.reset_size()
		var x: float = (tray.table_x(k * 2) + tray.table_x(k * 2 + 1)) * 0.5
		var at: Vector2 = tray.position + tray.far_rail_screen(x)
		tag.position = at - Vector2(tag.size.x * 0.5, TAG_H * 0.5)
		tag.pivot_offset = tag.size * 0.5
		tag.modulate.a = 0.0
		tag.create_tween().tween_property(tag, "modulate:a", 1.0, 0.2)
		tags.append({"node": tag, "sb": sb, "text": text, "armies": pr.get("armies", []), "col": col})


func read(k: int, field: Control, won: String = "") -> void:
	## pair k is being read: its tag lights, and a thread runs from it to each of its armies' plates,
	## in the colours of whoever won the pair (the owner: "the color of the arrows connecting the
	## dice to the target reflect the winner's color"); an even pair's is parchment
	if k < 0 or k >= tags.size() or str(tags[k]["text"]) == "":
		return
	var t: Dictionary = tags[k]
	var tag: Control = t["node"]
	var col: Color = t["col"]
	var tw := tag.create_tween().set_parallel(true)
	tag.scale = Vector2(1.18, 1.18)
	tw.tween_property(tag, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var sb: StyleBoxFlat = t["sb"]
	sb.border_color = Style.GOLD
	tw.tween_method(func(c: Color): sb.border_color = c, Style.GOLD, col, 0.7)
	if not field.has_method("plate_point"):
		return
	_field = field
	var from: Vector2 = tag.position + Vector2(tag.size.x * 0.5, 0.0)
	for ai in t["armies"]:
		var to: Vector2 = field.plate_point(int(ai))
		if to.x < 0.0:
			continue
		threads.append({"from": from, "to": to, "col": thread_colour(won), "t": 0.0, "army": int(ai), "pair": k, "won": won})
		field.pulse(int(ai), Style.GOLD)
	queue_redraw()


static func thread_colour(won: String) -> Color:
	## the winner's colour, lit a little so it reads over the ground; parchment for an even pair
	return Style.seat_color(won).lightened(0.3) if won != "" else Style.PARCH


func _process(delta: float) -> void:
	if threads.is_empty():
		return
	for i in range(threads.size() - 1, -1, -1):
		var th: Dictionary = threads[i]
		th["t"] = float(th["t"]) + delta
		if float(th["t"]) > THREAD_LIFE:
			threads.remove_at(i)
			continue
		## the plates keep clear of each other as the men fall: a thread stays tied to its own
		if is_instance_valid(_field):
			var to: Vector2 = _field.plate_point(int(th["army"]))
			if to.x >= 0.0:
				th["to"] = to
	queue_redraw()


func _draw() -> void:
	for th in threads:
		var t: float = th["t"]
		var a: float = clampf(t / 0.1, 0.0, 1.0) * (1.0 - smoothstep(THREAD_LIFE * 0.55, THREAD_LIFE, t))
		var from: Vector2 = th["from"]
		var to: Vector2 = th["to"]
		## a gentle bow, so two threads to two fronts read as two
		var mid: Vector2 = (from + to) * 0.5 + Vector2((to.x - from.x) * 0.15, -absf(to.x - from.x) * 0.12)
		var pts := PackedVector2Array()
		for s in 17:
			var u: float = float(s) / 16.0
			pts.append(from.lerp(mid, u).lerp(mid.lerp(to, u), u))
		var col: Color = th["col"]
		draw_polyline(pts, Color(0, 0, 0, 0.45 * a), 5.0, true)
		draw_polyline(pts, Color(col.r, col.g, col.b, 0.9 * a), 2.0, true)
		## a spark runs up the thread to the army it names
		var u2: float = clampf(t / 0.3, 0.0, 1.0)
		var spark: Vector2 = from.lerp(mid, u2).lerp(mid.lerp(to, u2), u2)
		draw_circle(spark, 4.5, Color(1.0, 0.92, 0.7, a))
		draw_circle(to, 3.5, Color(col.r, col.g, col.b, a))
