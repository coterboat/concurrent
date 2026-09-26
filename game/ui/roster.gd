## Roll call along the top: every commander's face, colour, score, lands and cards.
## Lives in the strip the map keeps clear, so it never covers a land.
## Hover a commander to light up their lands on the map.
extends HBoxContainer

const Style := preload("res://game/core/style.gd")
const Session := preload("res://game/core/session.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")

signal hovered(pid: String)

var session: Node
var faces := {} ## pid -> LeaderFace
var _rows := {}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_PASS


var view: RefCounted ## v1.6: the world the table is showing (the battle report's), for the card counts


func refresh() -> void:
	if session == null or session.world == null:
		return
	var s = session
	var rows: Array = s.standings()
	if view != null:
		## during the battle report: lands and scores as the map shows them, not the final tally
		for r in rows:
			if view.players.has(r["id"]):
				r["lands"] = MapLib.player_territory_ids(view, r["id"]).size()
				r["score"] = Income.score_of(view, s.map, r["id"])
				r["alive"] = view.players[r["id"]].alive and int(r["lands"]) > 0
	var lead := -1
	var leaders := 0
	for r in rows:
		if r["alive"] and int(r["score"]) > lead:
			lead = int(r["score"])
	for r in rows:
		if r["alive"] and int(r["score"]) == lead:
			leaders += 1
	## build once per seat, then update
	for seat in s.seats:
		var pid: String = seat["id"]
		if not _rows.has(pid):
			_rows[pid] = _make_row(seat)
			add_child(_rows[pid]["panel"])
	for r in rows:
		var ui: Dictionary = _rows[r["id"]]
		var active: bool = s.planner == r["id"] and (s.phase == Session.Phase.PLANNING or s.phase == Session.Phase.OPENING)
		var col: Color = Style.seat_color(r["id"])
		(ui["panel"] as PanelContainer).add_theme_stylebox_override("panel", Style.flat(
			Color(0.16, 0.12, 0.06, 0.94) if active else Color(0.03, 0.045, 0.08, 0.86),
			col.lightened(0.2) if r["alive"] else Color(0.3, 0.3, 0.3), 2 if active else 1, 8, 6))
		(ui["score"] as Label).text = "%d" % r["score"] if r["alive"] else "—"
		var bits := "%d lands" % r["lands"]
		if s.map.cards and r["alive"]:
			var nc: int = int(r["cards"])
			if view != null and view.players.has(r["id"]):
				nc = view.players[r["id"]].cards.size() ## the report hasn't reached the draws yet
			var turning := ""
			if s.phase == Session.Phase.PLANNING and s.planner == r["id"] and not s.sheet().cash_set.is_empty():
				nc -= s.sheet().cash_set.size()
				turning = " (3 turned in)"
			bits += " · %d card%s%s" % [nc, "" if nc == 1 else "s", turning]
		if not r["alive"]:
			bits = "fallen"
		(ui["sub"] as Label).text = bits
		(ui["crown"] as Control).visible = r["alive"] and int(r["score"]) == lead and leaders == 1
		(ui["face"] as Control).set_dead(not r["alive"])
		(ui["panel"] as Control).modulate = Color(1, 1, 1) if r["alive"] else Color(0.7, 0.7, 0.72)


func _make_row(seat: Dictionary) -> Dictionary:
	var pid: String = seat["id"]
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(200, 60)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_entered.connect(func(): hovered.emit(pid))
	p.mouse_exited.connect(func(): hovered.emit(""))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var face: Control = LeaderFace.new()
	face.custom_minimum_size = Vector2(44, 44)
	face.bubble_side = "bottom"
	face.setup(str(seat.get("portrait", "player")), pid, str(seat["name"]))
	h.add_child(face)
	faces[pid] = face
	var mark := _Mark.new()
	mark.pid = pid
	mark.custom_minimum_size = Vector2(14, 44)
	h.add_child(mark)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	## the strip is narrow: "Grand Marshal Varek" reads as "Varek" here (full title on hover)
	var shown: String = str(seat["name"])
	if str(seat.get("kind", "")) == "ai" and shown.split(" ").size() > 1 and shown.length() > 11:
		shown = shown.split(" ")[-1]
	var name_l := Style.label(shown, 15, Style.seat_color(pid).lightened(0.45), "bold")
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(name_l)
	var sub := Style.label("", 13, Style.PARCH)
	v.add_child(sub)
	var crown := TextureRect.new()
	crown.texture = Style.icon("crown")
	crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crown.custom_minimum_size = Vector2(24, 24)
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(crown)
	var score := Style.label("", 26, Style.GOLD, "display")
	score.custom_minimum_size = Vector2(34, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(score)
	for c in [name_l, sub, score]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.tooltip_text = "%s — score is lands + region bonuses" % seat["name"]
	return {"panel": p, "face": face, "score": score, "sub": sub, "crown": crown}


class _Mark extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := ""

	func _draw() -> void:
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, 8.0, Style.seat_color(pid), Style.CREAM, 1.2)
