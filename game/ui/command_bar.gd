## The command bar: commander medallion, the advisor's dispatches, the order tally,
## and the big dial. Risk II's bottom strip, brought forward.
## v2.6 (Alex's call C17): its chips stand Style.CHIP_H tall, and it holds its words on every screen it's drawn
## on (_fit). The advisor's plan, his latest dispatches and the pages of his advice share one line under his words.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const Cards := preload("res://engine/cards.gd")
const Session := preload("res://game/core/session.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")

const HEIGHT := 156
const PAD_TOP := 16 ## the row under the brass rim
const PAD_BOTTOM := 10
const CHIP_FS := 16 ## v2.6: a chip's words (14 before)
const COUNSEL_FS := 18 ## his advice; where the bar is narrow it gives way a point at a time (_fit)
const SUB_FS := 15 ## the tally's hint, the same
const LEAST_PX := 14.0 ## ...but neither goes below this, in the screen's own pixels

var session: Node
var gs: Control
var commander: Control
var advisor: Control
var _coin: _Coin
var _ribbon: Label
var _counsel: Label
var _counsel_nav: Label
var _log: VBoxContainer
var _plan_btn: Button
var _b: PanelContainer ## the advisor's dispatches
var _foot: HBoxContainer ## under his words: his plan, the dispatches, the pages
var _pager: HBoxContainer ## the pages of his advice: ‹ 1 / 6 ›
var _tally_title: Label
var _tally: Label
var _tally_sub: Label
var _tally_row: HBoxContainer
var _dial: _Dial
var _coins: Array = []
var _items: Array = []
var _item_i := 0
var _fit_due := false
var _said := "" ## his advice in full (the label may hold it cut short to fit: _fit)
var _hint := "" ## the tally's hint in full, the same


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_top = PAD_TOP
	row.offset_left = 16
	row.offset_right = -12
	row.offset_bottom = -PAD_BOTTOM
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	## A — the commander at the table
	var a := Control.new()
	a.custom_minimum_size = Vector2(150, 0)
	row.add_child(a)
	commander = LeaderFace.new()
	commander.bubble_side = "top"
	commander.position = Vector2(10, -34)
	commander.size = Vector2(128, 128)
	a.add_child(commander)
	var rib := TextureRect.new()
	rib.texture = Style.tex("res://assets/hud/hud_ribbon.png")
	rib.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rib.stretch_mode = TextureRect.STRETCH_SCALE
	rib.position = Vector2(-6, 86)
	rib.size = Vector2(164, 44)
	rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.add_child(rib)
	_ribbon = Style.label("", 17, Style.CREAM, "bold")
	_ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ribbon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ribbon.position = Vector2(10, 90)
	_ribbon.size = Vector2(132, 30)
	_ribbon.clip_text = true
	_ribbon.add_theme_constant_override("outline_size", 4)
	_ribbon.add_theme_color_override("font_outline_color", Color(0.2, 0.05, 0.03))
	a.add_child(_ribbon)
	_coin = _Coin.new()
	_coin.position = Vector2(104, 38)
	_coin.size = Vector2(56, 56)
	a.add_child(_coin)
	## B — dispatches from the advisor
	_b = PanelContainer.new()
	_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_b.add_theme_stylebox_override("panel", Style.flat(Color(0.93, 0.87, 0.74, 0.96), Color(0.36, 0.26, 0.14), 2, 8, 10))
	row.add_child(_b)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	_b.add_child(bh)
	advisor = LeaderFace.new()
	advisor.custom_minimum_size = Vector2(76, 76)
	advisor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	advisor.bubble_side = "none"
	bh.add_child(advisor)
	advisor.setup("advisor", "", "Your advisor")
	var bv := VBoxContainer.new()
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.add_theme_constant_override("separation", 2)
	bh.add_child(bv)
	_counsel = Style.label("", COUNSEL_FS, Color(0.14, 0.09, 0.05), "bold")
	_counsel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_counsel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counsel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_counsel.custom_minimum_size = Vector2(200, 0)
	_counsel.resized.connect(_fit_soon) ## (a new width wraps his words afresh)
	bv.add_child(_counsel)
	## v2.6: one line under his words: his plan, the latest dispatches, the pages of his advice. The plan stood
	## under the dispatches, and on a 1440×900 window at Large text it ran off the foot of the screen; the pages'
	## ‹ › stood beside his words, which they made narrower, as bare arrows with no edge to show where to click
	_foot = HBoxContainer.new()
	_foot.add_theme_constant_override("separation", 10)
	bv.add_child(_foot)
	_plan_btn = _parch_chip("✦ Advisor's plan", func(): gs.open_plan())
	_foot.add_child(_plan_btn)
	_log = VBoxContainer.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_log.add_theme_constant_override("separation", -3)
	_foot.add_child(_log)
	_pager = HBoxContainer.new()
	_pager.add_theme_constant_override("separation", 4)
	_foot.add_child(_pager)
	_pager.add_child(_page_chip("‹", -1))
	_counsel_nav = Style.label("", 13, Color(0.35, 0.25, 0.15), "bold")
	_counsel_nav.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pager.add_child(_counsel_nav)
	_pager.add_child(_page_chip("›", 1))
	## C — order tally
	var c := VBoxContainer.new()
	c.custom_minimum_size = Vector2(250, 0)
	c.add_theme_constant_override("separation", 2)
	row.add_child(c)
	_tally_title = Style.label("ORDERS", 15, Style.GOLD, "display")
	c.add_child(_tally_title)
	_tally = Style.label("", 20, Style.CREAM, "bold")
	_tally.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(_tally)
	_tally_sub = Style.label("", SUB_FS, Style.PARCH)
	_tally_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tally_sub.resized.connect(_fit_soon)
	c.add_child(_tally_sub)
	_tally_row = HBoxContainer.new()
	_tally_row.add_theme_constant_override("separation", 6)
	c.add_child(_tally_row)
	## D — the dial
	var d := Control.new()
	d.custom_minimum_size = Vector2(250, 0)
	row.add_child(d)
	_dial = _Dial.new()
	_dial.position = Vector2(68, -40)
	_dial.size = Vector2(150, 150)
	_dial.pressed.connect(func(): gs.primary_action())
	d.add_child(_dial)
	var specs := [
		["View", "Switch the map between owner colours and region colours (V)", Vector2(8, -18), func(): gs.toggle_view()],
		["Rules", "How to play", Vector2(0, 34), func(): gs.open_rules()],
		["Menu", "Pause menu (Esc)", Vector2(8, 86), func(): gs.open_menu()],
	]
	for sp in specs:
		var cb := _CoinButton.new()
		cb.text = sp[0]
		cb.tooltip_text = sp[1]
		cb.position = sp[2]
		cb.size = Vector2(52, 52)
		cb.pressed.connect(sp[3])
		d.add_child(cb)
		_coins.append(cb)


func _chip(t: String, cb: Callable, color: Color = Style.CREAM) -> Button:
	## v2.6: a chip on the bar, Style.CHIP_H tall (Alex's call C17)
	var b := Style.chip(t, cb, color, CHIP_FS)
	b.custom_minimum_size.y = Style.CHIP_H
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _parch_chip(t: String, cb: Callable) -> Button:
	## a chip on the advisor's parchment: his plan, and the pages of his advice (as wide as it's tall at least)
	var ink := Color(0.45, 0.18, 0.1)
	var b := _chip(t, cb, ink)
	b.custom_minimum_size.x = Style.CHIP_H
	b.add_theme_stylebox_override("normal", Style.flat(Color(0.98, 0.93, 0.8), ink, 1, 5, 8))
	b.add_theme_stylebox_override("hover", Style.flat(Color(1, 0.97, 0.86), Color(0.6, 0.2, 0.1), 2, 5, 8))
	return b


func _page_chip(t: String, d: int) -> Button:
	## back or on through his advice (the arrows at their own size, as before)
	var b := _parch_chip(t, func(): _step(d))
	b.add_theme_font_size_override("font_size", 20)
	return b


func _fit_soon() -> void:
	if not _fit_due:
		_fit_due = true
		_fit.call_deferred()


func _fit() -> void:
	## v2.6: the bar holds its words on every screen it's drawn on. The narrowest is 1252 wide (a 1440×900 window
	## at Large text), where his advice ran to four or five lines and pushed his plan and his dispatches off the
	## foot of the screen. First the dispatches give way, where they stand under his words on their own; then his
	## advice, a point at a time, down to LEAST_PX on the screen; at the last it's cut short at a word, all of it
	## in its tooltip. The tally's hint does the same in its column. The words are measured with their font at the
	## width last laid out (a new width comes back here through resized), and each label is set once
	_fit_due = false
	if not is_inside_tree():
		return
	var k: float = maxf(get_viewport().get_final_transform().get_scale().y, 0.01)
	var room: float = HEIGHT - PAD_TOP - PAD_BOTTOM
	var b_room: float = room - _b.get_theme_stylebox("panel").get_minimum_size().y
	var lines: Array = _log.get_children().filter(func(l): return not l.is_queued_for_deletion())
	for l in lines:
		(l as Control).visible = true
	var alone: bool = not _plan_btn.visible and not _pager.visible
	## (chips stand at his panel's foot; the dispatches on their own follow his words, as they always did)
	_counsel.size_flags_vertical = Control.SIZE_FILL if alone else Control.SIZE_EXPAND_FILL
	if alone:
		while not lines.is_empty() and _words_h(_counsel, _said, COUNSEL_FS) + _under(_foot) > b_room:
			(lines.pop_front() as Control).visible = false
	_fit_words(_counsel, _said, COUNSEL_FS, mini(ceili(LEAST_PX / k), COUNSEL_FS), b_room - _under(_foot))
	var c_room: float = room - _tally_title.get_combined_minimum_size().y - _under(_tally) - _under(_tally_row) - 2.0
	_fit_words(_tally_sub, _hint, SUB_FS, mini(ceili(LEAST_PX / k), SUB_FS), c_room)


func _fit_words(l: Label, text: String, full: int, least: int, h: float) -> void:
	## the largest size from full down to least at which the words take no more than h; at least, as many words
	## as fit, then …, all of them in the tooltip (and where not one fits, the label steps aside)
	var fs := full
	while fs > least and _words_h(l, text, fs) > h:
		fs -= 1
	var said := text
	if _words_h(l, text, fs) > h:
		var words: PackedStringArray = text.split(" ")
		var lo := 0
		var hi := words.size()
		while lo < hi:
			var mid: int = (lo + hi + 1) / 2
			if _words_h(l, " ".join(words.slice(0, mid)) + "…", fs) <= h:
				lo = mid
			else:
				hi = mid - 1
		said = " ".join(words.slice(0, lo)) + "…" if lo > 0 else ""
	if l.text != said:
		l.text = said
	l.visible = said != "" or text == ""
	l.tooltip_text = text if said != text else ""
	if l.get_theme_font_size("font_size") != fs:
		l.add_theme_font_size_override("font_size", fs)


func _words_h(l: Label, text: String, fs: int) -> float:
	## how tall the label stands with these words at this size, wrapped at its width
	if text == "":
		return 0.0
	var f: Font = l.get_theme_font("font")
	var sz: Vector2 = f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, l.size.x, fs, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var n: int = maxi(roundi(sz.y / f.get_height(fs)), 1)
	return sz.y + (n - 1) * l.get_theme_constant("line_spacing")


func _under(c: Control) -> float:
	## what a box takes in its column, with the column's gap above it
	return c.get_combined_minimum_size().y + 2.0 if c.visible else 0.0


func _draw() -> void:
	## wood body, brass rim on top, a thin shadow above
	var wood: Texture2D = Style.tex("res://assets/tex/wood.webp")
	draw_rect(Rect2(0, -10, size.x, 10), Color(0, 0, 0, 0.35))
	if wood:
		draw_texture_rect(wood, Rect2(Vector2(0, 8), Vector2(size.x, size.y - 8)), true, Color(0.55, 0.45, 0.38))
	else:
		draw_rect(Rect2(0, 8, size.x, size.y - 8), Color(0.18, 0.12, 0.08))
	draw_rect(Rect2(0, 0, size.x, 10), Color(0.62, 0.47, 0.22))
	draw_rect(Rect2(0, 2, size.x, 3), Color(0.92, 0.78, 0.45))
	draw_rect(Rect2(0, 9, size.x, 2), Color(0.2, 0.12, 0.05))
	for x in range(40, int(size.x), 120):
		draw_circle(Vector2(x, 5), 3.0, Color(0.95, 0.85, 0.55))
		draw_circle(Vector2(x + 1, 6), 1.2, Color(0.4, 0.28, 0.1))


func _step(d: int) -> void:
	if _items.is_empty():
		return
	_item_i = (_item_i + d + _items.size()) % _items.size()
	_show_item()
	gs.focus_advice(_items[_item_i])


func _show_item() -> void:
	if _items.is_empty():
		return
	var it: Dictionary = _items[_item_i]
	_said = str(it["text"])
	_counsel.text = _said
	_counsel_nav.text = "%d / %d" % [_item_i + 1, _items.size()]
	advisor._set_mood(str({"alarmed": "alarm", "pleased": "happy"}.get(str(it["mood"]), "neutral")))
	_fit_soon()


func set_counsel(items: Array, keep: bool = true) -> void:
	var key: String = str(_items[_item_i]["key"]) if keep and not _items.is_empty() else ""
	_items = items
	_item_i = 0
	for i in _items.size():
		if str(_items[i]["key"]) == key:
			_item_i = i
	_pager.visible = _items.size() > 1
	if _items.is_empty():
		_said = ""
		_counsel.text = ""
		_fit_soon()
		return
	_show_item()


func set_message(text: String, mood: String = "neutral") -> void:
	_items = []
	_pager.visible = false
	_said = text
	_counsel.text = text
	advisor._set_mood(mood)
	_fit_soon()


func refresh() -> void:
	if session == null or session.world == null:
		return
	var s = session
	var ph: int = s.phase
	var planning: bool = ph == Session.Phase.PLANNING or ph == Session.Phase.OPENING
	var focus_pid: String = s.planner if planning or ph == Session.Phase.MANEUVER else ""
	if focus_pid != "":
		var seat: Dictionary = s.seat(focus_pid)
		commander.setup(str(seat.get("portrait", "player")), focus_pid, s.name_of(focus_pid))
		_ribbon.text = s.name_of(focus_pid)
	elif commander.who == "player" and _ribbon.text == "":
		_ribbon.text = "The War Table"
	_coin.visible = planning
	_plan_btn.visible = ph == Session.Phase.PLANNING
	if planning:
		_coin.value = s.placeable_left() ## v2.3: recruits with no room left aren't waiting on you
		_coin.total = s.income_total()
		_coin.queue_redraw()
	## log
	for c in _log.get_children():
		c.hide() ## (out of the layout now: the fit below mustn't count it)
		c.queue_free()
	var lines: Array = gs.log_lines.slice(maxi(0, gs.log_lines.size() - (2 if planning else 3)))
	for l in lines:
		var lab := Style.label("· " + str(l[0]), 14, Color(l[1]).darkened(0.35), "italic")
		lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS ## (v2.6: beside his plan on a narrow bar, cut with …)
		_log.add_child(lab)
	## tally + dial
	for c in _tally_row.get_children():
		c.hide()
		c.queue_free()
	match ph:
		Session.Phase.OPENING:
			_tally_title.text = "DEPLOYMENT"
			_tally.text = "%d of %d placed" % [s.placed_total(), s.income_total()]
			_hint = "Each land takes up to 2 × (1 + your neighboring lands)."
			_tally_row.add_child(_chip("Auto-place", func():
				s.auto_deploy()
				Audio.sfx("place"), Style.CREAM))
			_tally_row.add_child(_chip("Clear", func(): s.clear_placements(), Style.MUTED))
			_dial.set_label("SEAL", "deployment")
		Session.Phase.PLANNING when s.plan_step == "reinforce":
			## v1.5 the reinforcement phase: recruits (and cards) first
			_tally_title.text = ("FINAL ROUND · " if s.is_last_round() and not s.conquest() else "") + "REINFORCEMENT PHASE · ROUND %d" % s.world.round
			_tally.text = "%d of %d recruits placed" % [s.placed_total(), s.income_total()]
			if s.no_room() > 0 and s.placeable_left() == 0:
				_tally.text += " · %d no room" % s.no_room()
			var sub_r := "Click your lands to place them · right-click takes one back"
			if s.map.cards and s.hand().size() > 0:
				sub_r = "%d card%s in hand · %s" % [s.hand().size(), "" if s.hand().size() == 1 else "s", sub_r]
			_hint = sub_r
			var ap2 := _chip("Auto-place", func():
				s.auto_deploy()
				Audio.sfx("place"), Style.CREAM)
			ap2.disabled = s.placeable_left() <= 0
			_tally_row.add_child(ap2)
			_tally_row.add_child(_chip("Clear", func(): s.clear_placements(), Style.MUTED))
			if s.map.cards:
				var ready2: bool = s.best_set().size() == 3
				var label2 := "Cards (%d)" % s.hand().size()
				if not s.sheet().cash_set.is_empty():
					label2 = "Cards ✓ +%d" % s.set_value_now()
				elif ready2:
					label2 = "Cards ✦ set!"
				var cc2: Control = _chip(label2, func(): gs.open_cards(), Style.GOLD if ready2 or not s.sheet().cash_set.is_empty() else Style.CREAM)
				cc2.tooltip_text = "Your hand of cards (C): three alike or one of each turn in for fresh troops"
				_tally_row.add_child(cc2)
			_dial.set_label("ORDERS", "next ▸")
		Session.Phase.PLANNING:
			var sh: Types.Sheet = s.sheet()
			var targets := {}
			for raw in sh.packets:
				targets[(raw as Types.Packet).to_id] = true
			var parts: Array = []
			if targets.size() > 0:
				parts.append("%d attack%s" % [targets.size(), "" if targets.size() == 1 else "s"])
			if sh.regroup != null:
				parts.append("1 move")
			_tally_title.text = "FINAL ORDERS" if s.is_last_round() and not s.conquest() else "ORDERS PHASE · ROUND %d" % s.world.round
			_tally.text = ", ".join(parts) if not parts.is_empty() else "Holding everything"
			var sub := "%d of %d troops placed" % [s.placed_total(), s.income_total()]
			if s.map.cards and s.hand().size() > 0:
				sub += " · %d card%s" % [s.hand().size(), "" if s.hand().size() == 1 else "s"]
				if not s.sheet().cash_set.is_empty():
					sub += " (trading +%d)" % s.set_value_now()
			_hint = sub
			_tally_row.add_child(_chip("◀ Recruits", func(): s.back_to_reinforce(), Style.PARCH))
			_tally_row.add_child(_chip("Review", func(): gs.open_drawer(), Style.CREAM))
			if s.map.cards:
				## the hand opens on the table; a set glows when one is ready
				var ready: bool = s.best_set().size() == 3
				var label := "Cards (%d)" % s.hand().size()
				if not s.sheet().cash_set.is_empty():
					label = "Cards ✓ +%d" % s.set_value_now()
				elif ready:
					label = "Cards ✦ set!"
				var cc: Control = _chip(label, func(): gs.open_cards(), Style.GOLD if ready or not s.sheet().cash_set.is_empty() else Style.CREAM)
				cc.tooltip_text = "Your hand of cards (C): three alike or one of each turn in for fresh troops"
				_tally_row.add_child(cc)
			_dial.set_label("SEAL", "orders")
		Session.Phase.DRAFT:
			var turn: String = s.draft_turn()
			var picking: bool = str(gs._draft_state) == "picking"
			_tally_title.text = "CLAIMING THE LANDS"
			_tally.text = ("%s pick" % Style.owns(s.name_of(turn), true)) if picking and turn != "" else "Throwing for the order"
			var free := 0
			for t in s.map.territory_ids():
				if s.world.get_territory(str(t)).owner == Types.UNOCCUPIED:
					free += 1
			_hint = "%d land%s each · %d still free" % [int(s.draft.get("quota", 0)), "" if int(s.draft.get("quota", 0)) == 1 else "s", free]
			if picking and s.is_human(turn):
				_tally_row.add_child(_chip("Advisor's pick", func(): gs.draft_advise(), Style.CREAM))
				_dial.set_label("PICK", "for me")
			else:
				_tally_row.add_child(_chip("Hurry ▶▶" if not gs.draft_fast else "Normal pace", func():
					gs.draft_fast = not gs.draft_fast
					refresh(), Style.PARCH))
				_dial.set_label("…", "")
		Session.Phase.MANEUVER:
			var men := 0
			for m in s.my_moves():
				men += int(m["n"])
			var k: int = s.my_moves().size()
			_tally_title.text = "REGROUP PHASE"
			_tally.text = ("%d march%s · %d soldier%s" % [k, "" if k == 1 else "es", men, "" if men == 1 else "s"]) if k > 0 else "Every post holds"
			_hint = "Drag between your lands. One land per soldier."
			_tally_row.add_child(_chip("Advisor's marches", func():
				s.advise_moves()
				Audio.sfx("maneuver", -4.0), Style.CREAM))
			_tally_row.add_child(_chip("Clear", func(): s.clear_moves(), Style.MUTED))
			_dial.set_label("MARCH", "done")
		Session.Phase.CINEMA:
			_tally_title.text = "BATTLE REPORT"
			_tally.text = gs.cinema_progress()
			_hint = "Space: next · P: pause · Esc: skip"
			_tally_row.add_child(_chip("❚❚ / ▶", func(): gs.cinema.toggle_pause(), Style.CREAM))
			_tally_row.add_child(_chip("Skip ▶▶", func(): gs.cinema.skip(), Style.PARCH))
			_dial.set_label("NEXT", "")
		Session.Phase.RESOLVING:
			_tally_title.text = "SEALED"
			_tally.text = "The others are writing theirs…"
			_hint = ""
			_dial.set_label("…", "")
		_:
			_tally_title.text = ""
			_tally.text = ""
			_hint = ""
			_dial.set_label("NEXT", "")
	_tally_sub.text = _hint
	queue_redraw()
	_fit_soon()


func bump_coin(big: bool = false) -> void:
	var tw := create_tween()
	if big:
		## fresh troops from a set: the coin swells and glows gold a few times
		for k in 3:
			tw.tween_property(_coin, "scale", Vector2(1.45, 1.45), 0.14).set_trans(Tween.TRANS_BACK)
			tw.parallel().tween_property(_coin, "modulate", Color(1.6, 1.35, 0.7), 0.14)
			tw.tween_property(_coin, "scale", Vector2.ONE, 0.18)
			tw.parallel().tween_property(_coin, "modulate", Color.WHITE, 0.18)
		return
	tw.tween_property(_coin, "scale", Vector2(1.15, 1.15), 0.08)
	tw.tween_property(_coin, "scale", Vector2.ONE, 0.12)


func coin_center() -> Vector2:
	return _coin.global_position + _coin.size * 0.5


class _Coin extends Control:
	const Style := preload("res://game/core/style.gd")
	var value := 0
	var total := 0

	func _ready() -> void:
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		tooltip_text = "Troops left to place"

	func _draw() -> void:
		var t: Texture2D = Style.tex("res://assets/hud/hud_coin.png")
		if t:
			draw_texture_rect(t, Rect2(Vector2.ZERO, size), false)
		else:
			draw_circle(size * 0.5, size.x * 0.5, Style.GOLD)
		var f := Style.font("display")
		var txt := str(value)
		var fs := 26 if value < 100 else 20
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := Color(0.25, 0.14, 0.04) if value > 0 else Color(0.1, 0.35, 0.1)
		draw_string(f, Vector2(size.x * 0.5 - w * 0.5, size.y * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


class _Dial extends Control:
	const Style := preload("res://game/core/style.gd")
	signal pressed
	var label := "SEAL"
	var sub := ""
	var _hover := false
	var _down := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		pivot_offset = size * 0.5
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			_down = false
			queue_redraw())

	func set_label(l: String, s: String) -> void:
		if l == label and s == sub:
			return
		label = l
		sub = s
		queue_redraw()
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.1)
		tw.tween_property(self, "scale", Vector2.ONE, 0.15)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_down = true
				queue_redraw()
			elif _down:
				_down = false
				queue_redraw()
				Audio.sfx("click")
				pressed.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_circle(size * 0.5 + Vector2(3, 6), size.x * 0.47, Color(0, 0, 0, 0.45))
		var t: Texture2D = Style.tex("res://assets/hud/hud_button.png")
		var mod := Color(1, 1, 1)
		if _hover:
			mod = Color(1.15, 1.08, 1.0)
		if _down:
			mod = Color(0.82, 0.78, 0.75)
		if t:
			draw_texture_rect(t, r.grow(-2 if _down else 0), false, mod)
		else:
			draw_circle(size * 0.5, size.x * 0.48, Style.CRIMSON)
		var f := Style.font("display")
		var fs := 30 if label.length() <= 4 else 24
		var w: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while w > size.x * 0.8 and fs > 12: ## v1.9: a long word ("LET IT STAND") shrinks to sit on the seal
			fs -= 1
			w = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2(size.x * 0.5 - w * 0.5, size.y * 0.5 + (4 if sub == "" else -2))
		draw_string_outline(f, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.25, 0.03, 0.02, 0.9))
		draw_string(f, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.93, 0.78))
		if sub != "":
			var sf := Style.font("italic")
			var sw: float = sf.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(sf, Vector2(size.x * 0.5 - sw * 0.5, size.y * 0.5 + 22), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.88, 0.75, 0.9))


class _CoinButton extends Control:
	const Style := preload("res://game/core/style.gd")
	signal pressed
	var text := ""
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			Audio.sfx("click")
			pressed.emit()
			accept_event()

	func _draw() -> void:
		draw_circle(size * 0.5 + Vector2(2, 3), size.x * 0.46, Color(0, 0, 0, 0.4))
		var t: Texture2D = Style.tex("res://assets/hud/hud_coin.png")
		if t:
			draw_texture_rect(t, Rect2(Vector2.ZERO, size), false, Color(1.15, 1.1, 1.0) if _hover else Color(1, 1, 1))
		var f := Style.font("bold")
		var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f, Vector2(size.x * 0.5 - w * 0.5, size.y * 0.5 + 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.25, 0.14, 0.04))
