## Round, phase and one chip per commander: lands, score, cards, leader crown.
extends PanelContainer

const Style := preload("res://game/core/style.gd")
const Session := preload("res://game/core/session.gd")

signal menu_pressed
signal help_pressed

var session: Node
var _round: Label
var _phase: Label
var _chips: HBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.045, 0.08, 0.97), Color(Style.GOLD, 0.35), 0, 0, 10))
	custom_minimum_size = Vector2(0, 66)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	add_child(h)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -4)
	h.add_child(title)
	_round = Style.label("", 24, Style.CREAM, "display")
	title.add_child(_round)
	_phase = Style.label("", 16, Style.GOLD, "bold")
	title.add_child(_phase)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(16, 0)
	h.add_child(sp)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 10)
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(_chips)
	var help := Style.chip("?  Rules", func(): help_pressed.emit(), Style.PARCH, 17)
	help.custom_minimum_size = Vector2(0, 42)
	h.add_child(help)
	var menu := Style.chip("≡  Menu", func(): menu_pressed.emit(), Style.PARCH, 17)
	menu.custom_minimum_size = Vector2(0, 42)
	h.add_child(menu)


func refresh() -> void:
	if session == null or session.world == null:
		return
	var s = session
	var total: int = s.rounds_total()
	if s.phase == Session.Phase.OPENING or (s.phase == Session.Phase.CINEMA and s.has_meta("opening_cinema") and s.get_meta("opening_cinema")) or s.setup_dict.is_empty():
		_round.text = "Deployment"
	else:
		var n: int = s.world.round
		if s.phase == Session.Phase.CINEMA or s.phase == Session.Phase.RECAP or s.phase == Session.Phase.GAME_OVER:
			n = maxi(1, s.world.round - 1)
		_round.text = ("Round %d" % n) if s.conquest() else ("Round %d of %d" % [mini(n, total), total])
	_phase.text = _phase_text()
	for c in _chips.get_children():
		c.queue_free()
	var rows: Array = s.standings()
	var lead_score: int = -1
	var leaders := 0
	for r in rows:
		if r["alive"] and int(r["score"]) > lead_score:
			lead_score = int(r["score"])
	for r in rows:
		if r["alive"] and int(r["score"]) == lead_score:
			leaders += 1
	## chips in seat order so they don't jump around
	for seat in s.seats:
		for r in rows:
			if r["id"] == seat["id"]:
				_chips.add_child(_chip(r, r["alive"] and int(r["score"]) == lead_score and leaders == 1))


func _phase_text() -> String:
	var s = session
	match s.phase:
		Session.Phase.OPENING:
			return "Deployment — %s" % s.name_of(s.planner)
		Session.Phase.PASS:
			return "Passing to %s" % s.name_of(s.pass_to)
		Session.Phase.PLANNING:
			if s.is_last_round() and not s.conquest():
				return "FINAL ROUND — orders for %s" % s.name_of(s.planner)
			return "Orders for %s" % s.name_of(s.planner)
		Session.Phase.RESOLVING:
			return "Orders sealed"
		Session.Phase.CINEMA:
			return "Battle report"
		Session.Phase.RECAP:
			return "The round is done"
		Session.Phase.GAME_OVER:
			return "The war is over"
	return ""


func _chip(r: Dictionary, leading: bool) -> Control:
	var pid: String = r["id"]
	var p := PanelContainer.new()
	var edge: Color = Style.seat_color(pid)
	var bg := Color(0.07, 0.09, 0.14, 0.95)
	if session.planner == pid and (session.phase == Session.Phase.PLANNING or session.phase == Session.Phase.OPENING):
		bg = Color(0.16, 0.13, 0.07, 0.98)
	p.add_theme_stylebox_override("panel", Style.flat(bg, edge if r["alive"] else Color(0.3, 0.3, 0.3), 2, 6, 8))
	p.tooltip_text = "%s\n%d lands · %d regions · %d armies\nIncome %d · %d card%s\nScore %d (lands + region bonuses)" % [r["name"], r["lands"], r["regions"], r["armies"], r["income"], r["cards"], "" if r["cards"] == 1 else "s", r["score"]]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var sw := _Mark.new()
	sw.pid = pid
	sw.dead = not r["alive"]
	sw.custom_minimum_size = Vector2(26, 30)
	h.add_child(sw)
	var name_l := Style.label(str(r["name"]), 17, Style.CREAM if r["alive"] else Style.MUTED, "bold")
	h.add_child(name_l)
	if not r["alive"]:
		h.add_child(Style.label("out", 15, Style.MUTED, "italic"))
		return p
	h.add_child(Style.label("%d" % r["score"], 20, Style.GOLD, "display"))
	if int(r["cards"]) > 0 and session.map.cards:
		h.add_child(Style.label("▯%d" % r["cards"], 15, Style.PARCH, "bold"))
	if leading:
		var crown := TextureRect.new()
		crown.texture = Style.icon("crown")
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.custom_minimum_size = Vector2(22, 22)
		h.add_child(crown)
	for c in h.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


class _Mark extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := ""
	var dead := false

	func _draw() -> void:
		var col: Color = Style.seat_color(pid)
		if dead:
			col = col.darkened(0.6)
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, 11.0, col, Style.CREAM, 1.5)
