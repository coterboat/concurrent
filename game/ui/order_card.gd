## Floating editor for one attack, pinned to its arrow: how many, the odds, surge, cancel.
extends PanelContainer

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")
const MapLib := preload("res://engine/map.gd")

const ODDS := {
	"long shot": Color(0.9, 0.42, 0.35), "toss-up": Color(0.95, 0.72, 0.35),
	"likely": Color(0.72, 0.85, 0.45), "lock": Color(0.45, 0.85, 0.5), "certain": Color(0.45, 0.85, 0.5),
}

var session: Node
var gs: Control
var from_id := ""
var to_id := ""
var _box: VBoxContainer
var _slider: HSlider
var _building := false
var kind := "attack" ## attack | move (a march in the regroup phase) | surge (on from a land being taken)


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.flat(Color(0.08, 0.04, 0.03, 0.96), Color(Style.CRIMSON.lightened(0.2), 0.9), 2, 8, 12))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(300, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 5)
	add_child(_box)
	visible = false


func show_for(a: String, b: String) -> void:
	kind = "attack"
	from_id = a
	to_id = b
	visible = a != "" and session.packet_index(a, b) >= 0
	if visible:
		rebuild()


func show_surge(a: String, b: String) -> void:
	## a: the land being attacked, b: where the surge goes on to
	kind = "surge"
	from_id = a
	to_id = b
	visible = a != "" and str(session.sheet().surges.get(a, "")) == b
	if visible:
		rebuild()


func _rebuild_surge() -> void:
	var s = session
	if str(s.sheet().surges.get(from_id, "")) != to_id:
		visible = false
		return
	_building = true
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var h := HBoxContainer.new()
	var t := Style.label("Surge %s ➜ %s" % [s.hex_name(from_id), s.hex_name(to_id)], 20, Style.GOLD, "display")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(Style.chip("✕", func(): gs.edit_order("", ""), Style.MUTED, 13))
	_box.add_child(h)
	_box.add_child(Style.label("If %s falls, the men who took it march on — after every other battle, all surges at once." % s.hex_name(from_id), 14, Style.PARCH, "italic"))
	## v1.10: a surge into a land you also attack directly is a second wave
	var direct := false
	for raw in s.sheet().packets:
		if (raw as Types.Packet).to_id == to_id:
			direct = true
	if direct:
		var sw := Style.label("Second wave: you also attack %s directly. The surge arrives after that assault: if %s has fallen, these men march in to hold it; if it still stands, they storm what's left." % [s.hex_name(to_id), s.hex_name(to_id)] if s.map.rules >= 19 else "Second wave: you also attack %s directly. If that assault takes it, this surge stays where it broke through; if not, it storms what's left." % s.hex_name(to_id), 13, Style.GOLD.lightened(0.2), "italic")
		sw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sw.custom_minimum_size = Vector2(300, 0)
		_box.add_child(sw)
	var most: int = s.surge_most(from_id)
	var n0: int = s.surge_count(from_id)
	var shown: int = most if n0 <= 0 else n0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Style.chip(" − ", func(): s.set_surge_count(from_id, shown - 1), Style.CREAM, 17))
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.max_value = most
	_slider.step = 1
	_slider.value = shown
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(100, 28)
	_slider.value_changed.connect(func(v):
		if not _building:
			s.set_surge_count(from_id, int(v)))
	row.add_child(_slider)
	row.add_child(Style.chip(" + ", func(): s.set_surge_count(from_id, shown + 1), Style.CREAM, 17))
	var nl := Style.label("all" if n0 <= 0 else "%d" % shown, 24, Style.GOLD, "display")
	nl.custom_minimum_size = Vector2(44, 0)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(nl)
	_box.add_child(row)
	var into_pass: bool = s.map.rules >= 17 and MapLib.column_cap(s.map, to_id) > 0
	if n0 > 0:
		_box.add_child(Style.label("Up to %d push on (fewer if the battle costs more); the rest hold %s." % [shown, s.hex_name(from_id)], 14, Style.PARCH))
	elif into_pass:
		_box.add_child(Style.label("%s is a pass: no more than %d push on; the rest hold %s." % [s.hex_name(to_id), MapLib.column_cap(s.map, to_id), s.hex_name(from_id)], 14, Style.PARCH))
	else:
		_box.add_child(Style.label("Everyone who survives pushes on but the one who stays to hold %s." % s.hex_name(from_id), 14, Style.PARCH))
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	act.add_child(Style.chip("All who can", func(): s.set_surge_count(from_id, 0), Style.CREAM, 14))
	act.add_child(Style.chip("Cancel surge", func():
		gs.edit_order("", "")
		var i0: int = gs._attack_into(from_id)
		if i0 >= 0:
			s.set_surge(i0, "")
		Audio.sfx("unplace"), Style.CRIMSON.lightened(0.3), 14))
	_box.add_child(act)
	_box.add_child(_ok_button())
	_building = false
	reset_size()
	gs.place_order_card(self, from_id, to_id)


func show_move(a: String, b: String) -> void:
	kind = "move"
	from_id = a
	to_id = b
	visible = a != "" and session.move_index(a, b) >= 0
	if visible:
		rebuild()


func _rebuild_move() -> void:
	var s = session
	var idx: int = s.move_index(from_id, to_id)
	if idx < 0:
		visible = false
		return
	_building = true
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var m: Dictionary = s.my_moves()[idx]
	var h := HBoxContainer.new()
	var t := Style.label("%s ➜ %s" % [s.hex_name(from_id), s.hex_name(to_id)], 20, Style.CREAM, "display")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(Style.chip("✕", func(): gs.edit_order("", ""), Style.MUTED, 13))
	_box.add_child(h)
	_box.add_child(Style.label("March to reinforce — one land, no further", 14, Style.PARCH, "italic"))
	var mx: int = maxi(1, s.can_move_from(from_id, idx))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Style.chip(" − ", func(): _set_move(int(m["n"]) - 1), Style.CREAM, 17))
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.max_value = mx
	_slider.step = 1
	_slider.value = int(m["n"])
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(100, 28)
	_slider.value_changed.connect(func(v):
		if not _building:
			_set_move(int(v)))
	row.add_child(_slider)
	row.add_child(Style.chip(" + ", func(): _set_move(int(m["n"]) + 1), Style.CREAM, 17))
	var n := Style.label("%d" % int(m["n"]), 26, Style.GOOD, "display")
	n.custom_minimum_size = Vector2(40, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(n)
	_box.add_child(row)
	var w = s.maneuver_world()
	_box.add_child(Style.label("%s keeps %d · %s will hold %d" % [s.hex_name(from_id), w.get_territory(from_id).held(), s.hex_name(to_id), w.get_territory(to_id).held()], 15, Style.PARCH))
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	act.add_child(Style.chip("Cancel march", func():
		gs.edit_order("", "")
		s.remove_move(idx)
		Audio.sfx("unplace"), Style.CRIMSON.lightened(0.3), 14))
	_box.add_child(act)
	_box.add_child(_ok_button())
	_building = false
	reset_size()
	gs.place_order_card(self, from_id, to_id)


func _set_move(v: int) -> void:
	var idx: int = session.move_index(from_id, to_id)
	if idx < 0:
		return
	session.set_move(idx, v)
	Audio.sfx("place", -8.0)


func rebuild() -> void:
	if kind == "move":
		_rebuild_move()
		return
	if kind == "surge":
		_rebuild_surge()
		return
	var s = session
	var idx: int = s.packet_index(from_id, to_id)
	if idx < 0:
		visible = false
		return
	_building = true
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var p: Types.Packet = s.sheet().packets[idx]
	var h := HBoxContainer.new()
	var t := Style.label("%s ➜ %s" % [s.hex_name(from_id), s.hex_name(to_id)], 20, Style.CREAM, "display")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(Style.chip("✕", func(): gs.edit_order("", ""), Style.MUTED, 13))
	_box.add_child(h)
	var mx: int = maxi(1, s.max_attack(from_id, to_id, idx))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Style.chip(" − ", func(): _set_strength(p.strength - 1), Style.CREAM, 17))
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.max_value = mx
	_slider.step = 1
	_slider.value = p.strength
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(100, 28)
	_slider.value_changed.connect(func(v):
		if not _building:
			_set_strength(int(v)))
	row.add_child(_slider)
	row.add_child(Style.chip(" + ", func(): _set_strength(p.strength + 1), Style.CREAM, 17))
	var n := Style.label("%d" % p.strength, 26, Style.GOLD, "display")
	n.custom_minimum_size = Vector2(40, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(n)
	_box.add_child(row)
	if s.max_attack(from_id, to_id, idx) < s.max_send(from_id, idx):
		var pl := Style.label("A pass: no more than %d may storm it from %s. Attack from another land too to bring more." % [s.max_attack(from_id, to_id, idx), s.hex_name(from_id)], 13, Style.GOLD.darkened(0.1), "italic")
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pl.custom_minimum_size = Vector2(300, 0)
		_box.add_child(pl)
	var d: Dictionary = s.expected_defense(to_id)
	var o: Dictionary = s.odds_into(to_id, int(d["now"])) ## v2.3: two lands at it are two fronts, priced so
	var total: int = int(o["total"])
	var odds_row := HBoxContainer.new()
	odds_row.add_theme_constant_override("separation", 8)
	odds_row.add_child(Style.label("Odds", 15, Style.PARCH))
	odds_row.add_child(Style.label(str(o["word"]).to_upper(), 20, ODDS.get(o["word"], Style.CREAM), "display"))
	if total != p.strength:
		var fronts: String = ("%d in all, from %d lands: each a front" % [total, int(o["fronts"])]) if int(o["fronts"]) > 1 and s.map.rules >= 21 else "%d total with your other attacks" % total
		odds_row.add_child(Style.label("(%s)" % fronts, 13, Style.MUTED, "italic"))
	_box.add_child(odds_row)
	if int(d["ceiling"]) > int(d["now"]):
		var o2: Dictionary = s.odds_into(to_id, int(d["ceiling"]))
		_box.add_child(Style.label("If they reinforce fully (%d): %s" % [d["ceiling"], o2["word"]], 14, Style.MUTED, "italic"))
	var home: int = s.projected_world().get_territory(from_id).held()
	var hl := Style.label("%s keeps %d at home" % [s.hex_name(from_id), home], 15, Style.CRIMSON.lightened(0.35) if home <= 1 else Style.PARCH)
	_box.add_child(hl)
	## v1.9: Fortune, both sides of this fight: who could have a bad exchange thrown again
	if s.map.fortune and s.map.battle == Combat.MODE_VOLLEYS:
		var owner: String = s.world.get_territory(to_id).owner
		var mine: int = int(s.world.players[s.planner].fortune) if s.world.players.has(s.planner) else 0
		var theirs: int = int(s.world.players[owner].fortune) if s.world.players.has(owner) and owner != "neutral" else 0
		var bits: Array = []
		if mine > 0:
			bits.append("you ✦%d" % mine)
		if theirs > 0:
			bits.append("%s ✦%d" % [s.name_of(owner).get_slice(" ", s.name_of(owner).get_slice_count(" ") - 1), theirs])
		if not bits.is_empty():
			var fl := Style.label("Fortune: " + "  ·  ".join(bits), 13, Style.GOLD.lightened(0.2), "italic")
			fl.tooltip_text = "Favours from Fortune: after an exchange that goes badly for them, a commander may have it thrown again, once a battle."
			fl.mouse_filter = Control.MOUSE_FILTER_PASS
			_box.add_child(fl)
	## standing orders for the battle calls you don't make yourself
	if s.map.battle == Combat.MODE_VOLLEYS:
		var reserves: int = s.reserves_at(from_id)
		if reserves > 0 and int(d["now"]) > 0:
			var o3: Dictionary = s.odds(total + reserves, int(d["now"]), to_id)
			_box.add_child(Style.label("With the %s thrown in: %s" % ["1 reserve" if reserves == 1 else "%d reserves" % reserves, o3["word"]], 14, Style.GOLD.darkened(0.1), "italic"))
		var st_row := HBoxContainer.new()
		st_row.add_theme_constant_override("separation", 6)
		st_row.add_child(Style.label("If it turns:", 14, Style.PARCH))
		var pick := OptionButton.new()
		pick.add_theme_font_size_override("font_size", 14)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cur: String = p.stance if p.stance != "" else Combat.STANCE_HOLD
		for i in Combat.STANCES.size():
			var st: String = Combat.STANCES[i]
			pick.add_item(Combat.stance_name(st), i)
			pick.set_item_tooltip(i, Combat.stance_help(st))
			if st == cur:
				pick.select(i)
		pick.tooltip_text = "What your officers do when you aren't watching the battle.\n" + Combat.stance_help(cur)
		pick.item_selected.connect(func(i: int):
			s.set_stance(idx, Combat.STANCES[i])
			Audio.sfx("click", -6.0))
		st_row.add_child(pick)
		_box.add_child(st_row)
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	if p.surge_to != "":
		var sn: int = s.surge_count(to_id)
		act.add_child(Style.chip("then surge → %s (%s)" % [s.hex_name(p.surge_to), "all" if sn <= 0 else str(sn)], func(): gs.edit_order(to_id, p.surge_to), Style.GOLD, 13))
	elif s.map.surges:
		var sb := Style.chip("Surge onward…", func(): gs.begin_surge_pick(idx), Style.PARCH, 14)
		sb.tooltip_text = "If this wins, the men who took %s push on into a land next to it — after every other battle. Or drag from %s to the next land." % [s.hex_name(to_id), s.hex_name(to_id)]
		act.add_child(sb)
	var rm := Style.chip("Cancel attack", func():
		gs.edit_order("", "")
		s.remove_packet(idx)
		Audio.sfx("unplace"), Style.CRIMSON.lightened(0.3), 14)
	act.add_child(rm)
	_box.add_child(act)
	_box.add_child(_ok_button())
	_building = false
	reset_size()
	gs.place_order_card(self, from_id, to_id)


func _ok_button() -> Button:
	## done with this order: close the card (the ✕ does the same; this one is where the eye ends)
	var ok := Style.chip("✓  OK", func():
		Audio.sfx("click", -6.0)
		gs.edit_order("", ""), Style.GOOD, 17)
	ok.custom_minimum_size = Vector2(0, 38)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.tooltip_text = "Keep this order and close the card (Enter)"
	return ok


func _set_strength(v: int) -> void:
	var idx: int = session.packet_index(from_id, to_id)
	if idx < 0:
		return
	session.set_packet_strength(idx, v)
	Audio.sfx("place", -8.0)
