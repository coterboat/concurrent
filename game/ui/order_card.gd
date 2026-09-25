## Floating editor for one attack, pinned to its arrow: how many, the odds, surge, cancel.
extends PanelContainer

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")

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
var kind := "attack" ## attack | move (a march in the reinforcement phase)


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
	var mx: int = maxi(1, s.max_send(from_id, idx))
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
	var total := 0
	for raw in s.sheet().packets:
		if (raw as Types.Packet).to_id == to_id:
			total += (raw as Types.Packet).strength
	var d: Dictionary = s.expected_defense(to_id)
	var o: Dictionary = s.odds(total, int(d["now"]))
	var odds_row := HBoxContainer.new()
	odds_row.add_theme_constant_override("separation", 8)
	odds_row.add_child(Style.label("Odds", 15, Style.PARCH))
	odds_row.add_child(Style.label(str(o["word"]).to_upper(), 20, ODDS.get(o["word"], Style.CREAM), "display"))
	if total != p.strength:
		odds_row.add_child(Style.label("(%d total with your other attacks)" % total, 13, Style.MUTED, "italic"))
	_box.add_child(odds_row)
	if int(d["ceiling"]) > int(d["now"]):
		var o2: Dictionary = s.odds(total, int(d["ceiling"]))
		_box.add_child(Style.label("If they reinforce fully (%d): %s" % [d["ceiling"], o2["word"]], 14, Style.MUTED, "italic"))
	var home: int = s.projected_world().get_territory(from_id).held()
	var hl := Style.label("%s keeps %d at home" % [s.hex_name(from_id), home], 15, Style.CRIMSON.lightened(0.35) if home <= 1 else Style.PARCH)
	_box.add_child(hl)
	## standing orders for the battle calls you don't make yourself
	if s.map.battle == Combat.MODE_VOLLEYS:
		var reserves: int = s.reserves_at(from_id)
		if reserves > 0 and int(d["now"]) > 0:
			var o3: Dictionary = s.odds(total + reserves, int(d["now"]))
			_box.add_child(Style.label("With the %d reserves thrown in: %s" % [reserves, o3["word"]], 14, Style.GOLD.darkened(0.1), "italic"))
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
		act.add_child(Style.label("then surge → %s" % s.hex_name(p.surge_to), 14, Style.GOLD, "italic"))
		act.add_child(Style.chip("no surge", func(): s.set_surge(idx, ""), Style.MUTED, 13))
	else:
		var sb := Style.chip("Surge onward…", func(): gs.begin_surge_pick(idx), Style.PARCH, 14)
		sb.tooltip_text = "If this wins, all but one push on into a land next to %s — after every other battle." % s.hex_name(to_id)
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
