## Roll call along the top: every commander's face, colour, score, lands and cards.
## Lives in the strip the map keeps clear, so it never covers a land.
## Hover a commander to light up their lands on the map.
extends HBoxContainer

const Types := preload("res://engine/types.gd")
const Style := preload("res://game/core/style.gd")
const Session := preload("res://game/core/session.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Fortune := preload("res://engine/fortune.gd")
const FortunePips := preload("res://game/ui/fortune_pips.gd")

signal hovered(pid: String)

var session: Node
var faces := {} ## pid -> LeaderFace
const NAME_MIN := 96.0 ## v1.14: the most room a name is promised (a longer one trims with an ellipsis)
var _rows := {}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_PASS


var view: RefCounted ## v1.6: the world the table is showing (the battle report's), for the card counts


var _crowned := "" ## v1.13: the sole leader the crown last sat on


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
		## v1.13: what each commander raises next round, for everyone to see (the recap had it alone)
		var inc: int = int(r["income"])
		if view != null and view.players.has(r["id"]):
			inc = Income.income_of(view, s.map, r["id"])
		var bits := "%s · +%d" % [Style.plural(int(r["lands"]), "land"), inc]
		if s.map.cards and r["alive"]:
			var nc: int = int(r["cards"])
			if view != null and view.players.has(r["id"]):
				nc = view.players[r["id"]].cards.size() ## the report hasn't reached the draws yet
			var turning := ""
			if s.phase == Session.Phase.PLANNING and s.planner == r["id"] and not s.sheet().cash_set.is_empty():
				nc -= s.sheet().cash_set.size()
				turning = " (3 turned in)"
			bits += " · %d card%s%s" % [nc, "" if nc == 1 else "s", turning]
		## v1.8: the favours Fortune owes each commander, for everyone to see (v1.9: as stars,
		## the next one filling with gold)
		var tip := "%s %d recruits next round, as the map stands." % [Style.says(s.name_of(r["id"]), "raises"), inc] if r["alive"] else ""
		var pips: Control = ui["pips"]
		pips.visible = false
		if s.map.fortune and r["alive"]:
			var wf: Types.World = view if view != null and view.players.has(r["id"]) else s.world
			var ps: Types.PlayerState = wf.players.get(r["id"], null)
			var truth: Types.PlayerState = s.world.players.get(r["id"], null)
			if ps != null:
				var meter: int = truth.fortune_meter if truth != null else ps.fortune_meter
				var share: float = Fortune.meter_share(s.map, meter)
				pips.visible = true
				pips.set_state(ps.fortune, share)
				var nm: String = s.name_of(r["id"])
				tip += "\n\n" + "Fortune ✦ %d of %d: %s. After an exchange that goes badly, %s can throw it again (once a battle).\nThe next star fills with gold as the dice rob %s: about half a battle's worth of bad luck owes another (%d%% of the way there)." % [
					ps.fortune, Fortune.MOST, "no favours in hand" if ps.fortune == 0 else ("%d favour%s in hand" % [ps.fortune, "" if ps.fortune == 1 else "s"]),
					Style.who(nm), Style.who(nm), int(round(share * 100.0))]
		if not r["alive"]:
			bits = "fallen"
		(ui["sub"] as Label).text = bits
		(ui["panel"] as Control).tooltip_text = tip
		var crown: Control = ui["crown"]
		var crowned: bool = r["alive"] and int(r["score"]) == lead and leaders == 1
		if crowned and str(r["id"]) != _crowned:
			## v1.13: the crown changes hands with a flourish (silently here; the recap sounds it)
			if _crowned != "":
				crown.pivot_offset = crown.size * 0.5
				crown.scale = Vector2(2.0, 2.0)
				crown.modulate = Color(1.6, 1.4, 0.9)
				var tw := crown.create_tween().set_parallel(true)
				tw.tween_property(crown, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(crown, "modulate", Color(1, 1, 1), 0.8)
			_crowned = str(r["id"])
		crown.visible = crowned
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
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## v1.14: the name keeps its room. Its label clips, so it asked for none: on a map without cards
	## the short "3 lands · +7" left the stars and the crown nothing but "Da" and an empty line
	name_l.custom_minimum_size.x = minf(Style.font("bold").get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 2.0, NAME_MIN)
	## v1.9: the name, and Fortune's stars beside it
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 4)
	nh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nh.add_child(name_l)
	var pips: Control = FortunePips.new()
	pips.star_px = 14.0
	pips.align = 1.0
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.visible = false
	nh.add_child(pips)
	v.add_child(nh)
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
	return {"panel": p, "face": face, "score": score, "sub": sub, "crown": crown, "pips": pips, "name": name_l}


class _Mark extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := ""

	func _draw() -> void:
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, 8.0, Style.seat_color(pid), Style.CREAM, 1.2)
