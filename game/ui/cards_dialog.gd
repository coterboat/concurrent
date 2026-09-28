## Your campaign cards, laid out on the table: men, horses and cannon, each naming a land.
## Pick three alike or one of each and turn them in for fresh troops this round; a card
## naming a land you hold also puts a free soldier there (v1.6). Turning in sends the
## cards flying off the table into your recruits, and the table closes.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const Cards := preload("res://engine/cards.gd")

const NAMES := {
	Types.CARD_SUN: "Infantry", Types.CARD_MOON: "Cavalry", Types.CARD_STAR: "Artillery", Types.CARD_WILD: "Wild",
}

signal closed
signal turned(value: int, lands: Array, from: Array) ## a set went in: its worth, the free-soldier lands, where the cards flew from
signal hover_land(id: String) ## a card is under the mouse: light its land on the map

var session: Node
var _picked: Array = [] ## indices into the hand
var _row: HBoxContainer
var _value: Label
var _status: Label
var _turn_in: Button
var _undo: Button


static func card_name(kind: String) -> String:
	kind = kind.get_slice("@", 0)
	return str(NAMES.get(kind, kind.capitalize()))


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.panel_box(26))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var h := HBoxContainer.new()
	var t := Style.label("Campaign cards", 34, Style.CREAM, "display")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(Style.chip("✕", func(): _close(), Style.MUTED, 16))
	v.add_child(h)
	_value = Style.label("", 19, Style.GOLD, "bold")
	v.add_child(_value)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 14)
	_row.custom_minimum_size = Vector2(0, 290)
	v.add_child(_row)
	_status = Style.label("", 17, Style.PARCH, "italic")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	var act := HBoxContainer.new()
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override("separation", 12)
	v.add_child(act)
	act.add_child(Style.chip("Pick the best set", func(): _pick_best(), Style.CREAM, 17))
	_turn_in = Style.button("Turn in", func(): _turn()) as Button
	_turn_in.custom_minimum_size = Vector2(260, 56)
	act.add_child(_turn_in)
	_undo = Style.chip("Keep my cards", func():
		session.set_cash(PackedStringArray())
		Audio.sfx("card")
		_picked = []
		_build(), Style.MUTED, 16)
	act.add_child(_undo)
	var rules := Style.label("Three alike, or one of each, turns in for fresh troops this round. Every set turned in by anyone raises the next: 4, 6, 8, 10, then 5 more each time. Each card names a land: if you hold it when you turn the card in, a free soldier joins you there. At five cards you draw no more.", 15, Style.MUTED)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(640, 0)
	v.add_child(rules)
	Audio.sfx("cards_open", -3.0)
	## start from what is already queued this round
	var queued: PackedStringArray = session.sheet().cash_set
	var hand: PackedStringArray = session.hand()
	var used := {}
	for q in queued:
		for i in hand.size():
			if not used.has(i) and hand[i] == q:
				used[i] = true
				_picked.append(i)
				break
	_build()


func _build() -> void:
	for ch in _row.get_children():
		ch.queue_free()
	var hand: PackedStringArray = session.hand()
	var value: int = session.set_value_now()
	_value.text = "A set is worth +%d troops right now" % value
	var queued0: bool = session.sheet().cash_set.size() == 3
	if hand.is_empty():
		var none := Style.label("No cards yet. Take a land in a round to draw one.", 20, Style.PARCH, "italic")
		_row.add_child(none)
	## laid out by kind, so the sets are easy to see
	var order: Array = range(hand.size())
	order.sort_custom(func(x, y): return str(hand[x]) < str(hand[y]))
	for i in order:
		if queued0 and _picked.has(i):
			continue ## already turned in: off the table
		_row.add_child(_card(i, str(hand[i])))
	var picked: Array = []
	for i in _picked:
		picked.append(str(hand[i]))
	var queued: bool = session.sheet().cash_set.size() == 3
	var is_set: bool = picked.size() == 3 and Cards.is_set(picked)
	_turn_in.disabled = not is_set or queued
	_turn_in.text = ("Turning in: +%d" % value) if queued else ("Turn in for +%d" % value)
	_undo.visible = queued
	if queued:
		var bl: Array = session.card_bonus_lands()
		var names: Array = []
		for ln in bl:
			names.append(session.hex_name(str(ln)))
		_status.text = "Turned in: +%d recruits are waiting%s. Changed your mind? Keep my cards takes them back." % [value, (", and a free soldier on " + ", ".join(names)) if not names.is_empty() else ""]
	elif picked.size() < 3:
		_status.text = "Pick three cards: three alike, or one of each."
	elif not is_set:
		_status.text = "Those three don't make a set."
	else:
		_status.text = "A set! Turn them in."


func _card(i: int, card: String) -> Control:
	var kind: String = Cards.kind(card)
	var ln: String = Cards.land(card)
	var picked: bool = _picked.has(i)
	var b := Button.new()
	b.set_meta("card", card)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(170, 280)
	b.toggle_mode = true
	b.button_pressed = picked
	var nb := Style.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 0)
	var sb := Style.flat(Color(1, 0.85, 0.4, 0.12), Style.GOLD, 4, 10, 0)
	b.add_theme_stylebox_override("normal", nb)
	b.add_theme_stylebox_override("hover", Style.flat(Color(1, 1, 1, 0.06), Color(Style.GOLD, 0.5), 2, 10, 0))
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("hover_pressed", sb)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 8
	v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var art := TextureRect.new()
	art.texture = Style.card_tex(kind)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	var l := Style.label(card_name(kind).to_upper(), 17, Style.GOLD if picked else Style.CREAM, "display")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	if ln != "":
		## the land this card names, and whether it would bring a free soldier
		var mine: bool = session.world.get_territory(ln) != null and session.world.get_territory(ln).owner == session.planner
		var nl := Style.label(session.hex_name(ln), 16, Style.PARCH, "bold")
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nl)
		var bl := Style.label("★ yours: +1 soldier there" if mine else "not yours", 13, Style.GOOD if mine else Style.MUTED, "italic")
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(bl)
		b.mouse_entered.connect(func(): hover_land.emit(ln))
		b.mouse_exited.connect(func(): hover_land.emit(""))
		b.custom_minimum_size = Vector2(170, 318)
	b.position.y = -14 if picked else 0
	b.toggled.connect(func(on: bool):
		if session.sheet().cash_set.size() == 3:
			return
		if on and not _picked.has(i):
			if _picked.size() >= 3:
				_picked.pop_front()
			_picked.append(i)
		elif not on:
			_picked.erase(i)
		Audio.sfx("card", -4.0)
		_build.call_deferred())
	return b


func _pick_best() -> void:
	var best: PackedStringArray = session.best_set()
	if best.is_empty():
		_status.text = "No set in this hand yet."
		Audio.sfx("error")
		return
	var hand: PackedStringArray = session.hand()
	_picked = []
	var used := {}
	for q in best:
		for i in hand.size():
			if not used.has(i) and hand[i] == q:
				used[i] = true
				_picked.append(i)
				break
	Audio.sfx("card")
	_build()


func _turn() -> void:
	var hand: PackedStringArray = session.hand()
	var cards := PackedStringArray()
	for i in _picked:
		cards.append(hand[i])
	var err: String = session.set_cash(cards)
	if err != "":
		_status.text = err
		Audio.sfx("error")
		return
	Audio.sfx("turn_in")
	## the three cards leave the table, the table closes, the troops arrive
	var from: Array = []
	var flying: Array = []
	var k := 0
	for ch in _row.get_children():
		if ch is Button and (ch as Button).button_pressed:
			var btn: Button = ch
			from.append(btn.global_position + btn.size * 0.5)
			var ghost := TextureRect.new()
			ghost.texture = Style.card_tex(str(btn.get_meta("card", cards[mini(k, cards.size() - 1)])))
			ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ghost.size = Vector2(btn.size.x - 16, btn.size.y * 0.72)
			ghost.global_position = btn.global_position + Vector2(8, 8)
			ghost.pivot_offset = ghost.size * 0.5
			ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			get_parent().add_child(ghost)
			flying.append(ghost)
			btn.modulate.a = 0.0
			k += 1
	var value: int = session.set_value_now()
	var lands: Array = session.card_bonus_lands()
	turned.emit(value, lands, flying)
	_close()


func _close() -> void:
	if is_queued_for_deletion():
		return ## already closing (a set turned in closes it too)
	hover_land.emit("")
	closed.emit()
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
