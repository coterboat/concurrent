extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const Ai := preload("res://engine/ai.gd")
const Board := preload("res://game/board/map_board.gd")

## v1.7: the faces a human seat may wear. "player" is the old faceless silhouette, kept
## first so anyone who liked being nobody in particular still can be.
const FACES := ["player", "you_ironduke", "you_corsair", "you_lioness", "you_scholar", "you_rajah", "you_grenadier"]
const FACE_NAMES := {
	"player": "An anonymous commander",
	"you_ironduke": "The Iron Duke",
	"you_corsair": "The Corsair",
	"you_lioness": "The Lioness",
	"you_scholar": "The Scholar",
	"you_rajah": "The Rajah",
	"you_grenadier": "The Grenadier",
}

const MAPS := ["res://maps/knife7.json", "res://maps/marches18.json", "res://maps/known24.json",
	"res://maps/ring26.json", "res://maps/world30.json", "res://maps/isles24.json"]
const AI_ORDER := ["oren", "hask", "quill", "varek", "imre", "ysolde"]
const LEVEL_WORD := {"recruit": "Easy", "veteran": "Medium", "general": "Hard"}

var main: Control
var tutorial := false
var map_path := "res://maps/known24.json"
var seats: Array = []
var length := "standard"
var timer := 0
var battle := "volleys"
var deal := "random"
var odds := "line"

var _map_cards := {}
var _seat_box: VBoxContainer
var _add_btn: Button
var _note: Label
var begin_button: Button
var _mapdefs := {}


func _ready() -> void:
	for p in MAPS:
		_mapdefs[p] = Types.MapDef.from_file(p)
	_load_last()
	var bg := TextureRect.new()
	bg.texture = Style.tex("res://assets/tex/wood.webp")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.modulate = Color(0.45, 0.42, 0.4)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 36 if side == "left" or side == "right" else 26)
	add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	root.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(Style.label("New Campaign", 44, Style.CREAM, "display"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(Style.button("Back", func(): main.show_title(), 140))

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 26)
	v.add_child(cols)

	## ---- maps
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", Style.panel_box(18))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	cols.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)
	lv.add_child(Style.label("Choose the map", 26, Style.GOLD, "display"))
	## v1.7: six maps are taller than the screen. Unscrolled, the list stretched the whole
	## page past the window and pushed "Begin the Campaign" off the bottom, out of reach.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for p in MAPS:
		var card := _map_card(p)
		list.add_child(card)
	## the map you played last may be at the bottom of the list: bring it into view
	get_tree().process_frame.connect(func():
		if _map_cards.has(map_path):
			scroll.ensure_control_visible(_map_cards[map_path]), CONNECT_ONE_SHOT)

	## ---- seats + options
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", Style.panel_box(18))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8) ## five commanders and every option must fit a 900-high window
	right.add_child(rv)
	rv.add_child(Style.label("Commanders", 26, Style.GOLD, "display"))
	_seat_box = VBoxContainer.new()
	_seat_box.add_theme_constant_override("separation", 8)
	rv.add_child(_seat_box)
	_add_btn = Style.chip("+  Add a commander", func(): _add_seat())
	_add_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rv.add_child(_add_btn)
	var sep := HSeparator.new()
	rv.add_child(sep)
	rv.add_child(Style.label("Options", 26, Style.GOLD, "display"))
	rv.add_child(_option_row("Game length", ["Short", "Standard", "Long", "Conquest (no round limit)"], ["short", "standard", "long", "conquest"], length, func(val):
		length = val
		_refresh()))
	rv.add_child(_option_row("Battles", ["Roll by roll (volleys)", "One decisive roll"], ["volleys", "decisive"], battle, func(val): battle = val))
	rv.add_child(_option_row("Battle odds", ["Firing line (five fire at once)", "Every man counts (v1.5)"], ["line", "classic"], odds, func(val): odds = val))
	rv.add_child(_option_row("Lands", ["Dealt at random", "Claimed in turn (dice for order)"], ["random", "draft"], deal, func(val): deal = val))
	rv.add_child(_option_row("Planning clock", ["Off", "90 seconds", "3 minutes"], [0, 90, 180], timer, func(val): timer = val))
	_note = Style.label("", 17, Style.PARCH, "italic")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_note)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(grow)
	var start := Style.button("Begin the Campaign", func(): _start(), 0, 26)
	begin_button = start
	start.custom_minimum_size = Vector2(0, 70)
	start.icon = Style.icon("seal")
	start.expand_icon = true
	start.add_theme_constant_override("icon_max_width", 46)
	rv.add_child(start)
	_refresh()


func _load_last() -> void:
	var last: Dictionary = Settings.get_value("last_setup", {})
	map_path = str(last.get("map", map_path))
	if not MAPS.has(map_path):
		map_path = "res://maps/known24.json"
	length = str(last.get("length", "standard"))
	timer = int(last.get("timer", 0))
	battle = str(last.get("battle", "volleys"))
	deal = str(last.get("deal", str(Settings.get_value("deal", "random"))))
	odds = str(last.get("odds", "line"))
	seats = []
	## v1.2 gave the commanders imperial titles; saved setups keep up
	var retitled := ["Marshal Varek", "Lady Ysolde", "Commander Imre", "Old Bear Hask", "The Quartermaster"]
	for s in last.get("seats", []):
		var seat: Dictionary = (s as Dictionary).duplicate()
		if str(seat.get("kind", "")) == "ai" and retitled.has(str(seat.get("name", ""))):
			seat["name"] = str(Ai.COMMANDERS.get(str(seat.get("ai", "")), {}).get("name", seat["name"]))
		seats.append(seat)
	if seats.is_empty():
		seats = [
			{"kind": "human", "name": str(last.get("name", "You")), "ai": ""},
			{"kind": "ai", "name": "Captain Oren", "ai": "oren"},
			{"kind": "ai", "name": "Governor Quill", "ai": "quill"},
		]


func _map_card(path: String) -> Control:
	var m: Types.MapDef = _mapdefs[path]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 150)
	b.toggle_mode = true
	b.add_theme_stylebox_override("normal", Style.flat(Color(0.05, 0.07, 0.11, 0.9), Color(Style.GOLD, 0.25), 1, 8, 10))
	b.add_theme_stylebox_override("hover", Style.flat(Color(0.08, 0.1, 0.15, 0.95), Color(Style.GOLD, 0.6), 1, 8, 10))
	b.add_theme_stylebox_override("pressed", Style.flat(Color(0.12, 0.1, 0.07, 0.95), Style.GOLD, 3, 8, 10))
	b.add_theme_stylebox_override("hover_pressed", Style.flat(Color(0.12, 0.1, 0.07, 0.95), Style.GOLD, 3, 8, 10))
	b.pressed.connect(func():
		Audio.sfx("click")
		map_path = path
		_fit_seats()
		_refresh())
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	h.offset_top = 10
	h.offset_bottom = -10
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 14)
	b.add_child(h)
	var thumb := Board.new()
	thumb.custom_minimum_size = Vector2(208, 130)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.interactive = false
	h.add_child(thumb)
	thumb.ready.connect(func():
		thumb.load_map(m)
		thumb.world = Types.World.empty_from_map(m)
		thumb.plain = true
		thumb.show_region_labels = false ## names at thumbnail size are just noise
		thumb.refresh())
	var txt := VBoxContainer.new()
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(txt)
	txt.add_child(Style.label(m.display_name, 26, Style.CREAM, "display"))
	var who: String = ("%d players" % m.min_players) if m.min_players == m.max_players else ("%d–%d players" % [m.min_players, m.max_players])
	var facts := Style.label("%d lands · %d regions · %s · %d rounds%s" % [m.territories.size(), m.region_bonus.size(), who, Setup.rounds_for(m), " · cards" if m.cards else ""], 17, Style.GOLD, "bold")
	txt.add_child(facts)
	var blurb := Style.label(m.blurb, 17, Style.PARCH)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_child(blurb)
	for c in txt.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_cards[path] = b
	return b


func _fit_seats() -> void:
	var m: Types.MapDef = _mapdefs[map_path]
	while seats.size() > m.max_players:
		seats.pop_back()
	while seats.size() < m.min_players:
		_add_seat(false)


func _add_seat(refresh: bool = true) -> void:
	var m: Types.MapDef = _mapdefs[map_path]
	if seats.size() >= m.max_players:
		return
	var used := {}
	for s in seats:
		used[s["ai"]] = true
	var pick := "veteran"
	for a in AI_ORDER:
		if not used.has(a):
			pick = a
			break
	seats.append({"kind": "ai", "name": Ai.COMMANDERS[pick]["name"] if Ai.COMMANDERS.has(pick) else "Commander", "ai": pick})
	if refresh:
		_refresh()


func _refresh() -> void:
	for p in _map_cards.keys():
		(_map_cards[p] as Button).set_pressed_no_signal(p == map_path)
	for c in _seat_box.get_children():
		c.queue_free()
	for i in seats.size():
		_seat_box.add_child(_seat_row(i))
	var m: Types.MapDef = _mapdefs[map_path]
	_add_btn.visible = seats.size() < m.max_players
	var humans := 0
	for s in seats:
		if s["kind"] == "human":
			humans += 1
	var notes: Array = []
	if humans == 0:
		notes.append("No human seats: you will watch the commanders fight it out.")
	elif humans > 1:
		notes.append("Hotseat: %d people share this computer. Each plans behind a cover screen, then pass it on." % humans)
	if seats.size() == 2:
		notes.append("Two commanders: a Neutral army holds some lands as a doorstop. It never attacks.")
	if length == "conquest":
		notes.append("Conquest: no round limit — play until someone holds 80% of the map or stands alone.")
	_note.text = "\n".join(notes)


func _seat_row(i: int) -> Control:
	var s: Dictionary = seats[i]
	var sid: String = Setup.SEAT_IDS[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var sw := _Swatch.new()
	sw.pid = sid
	sw.custom_minimum_size = Vector2(40, 44)
	row.add_child(sw)
	var face: String = str(s.get("portrait", "player"))
	if s["kind"] == "human" and not FACES.has(face):
		face = "player"
	var pic := TextureButton.new()
	pic.custom_minimum_size = Vector2(44, 44)
	pic.ignore_texture_size = true
	pic.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_normal = Style.portrait(face if s["kind"] == "human" else str(s["ai"]))
	if s["kind"] == "human":
		pic.tooltip_text = "%s — click to choose another face" % FACE_NAMES.get(face, "Your commander")
		pic.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pic.pressed.connect(func():
			Audio.sfx("click")
			s["portrait"] = FACES[(FACES.find(face) + 1) % FACES.size()]
			_refresh())
	else:
		pic.disabled = true
		pic.tooltip_text = str(Ai.COMMANDERS.get(s["ai"], {}).get("blurb", ""))
	row.add_child(pic)
	var name_edit := LineEdit.new()
	name_edit.text = str(s["name"])
	name_edit.custom_minimum_size = Vector2(268, 44) ## 'Grand Marshal Varek' must fit without losing its k
	name_edit.max_length = 24 ## 'Grand Marshal Varek' is nineteen; eighteen lost its k
	name_edit.editable = s["kind"] == "human"
	name_edit.text_changed.connect(func(t): s["name"] = t)
	row.add_child(name_edit)
	var who := OptionButton.new()
	who.custom_minimum_size = Vector2(250, 44)
	who.add_item("Human at this computer")
	for a in AI_ORDER:
		var c: Dictionary = Ai.COMMANDERS[a]
		who.add_item("%s  (%s)" % [c["name"], LEVEL_WORD[c["level"]]])
	who.selected = 0 if s["kind"] == "human" else AI_ORDER.find(str(s["ai"])) + 1
	who.tooltip_text = "" if s["kind"] == "human" else str(Ai.COMMANDERS.get(s["ai"], {}).get("blurb", ""))
	who.item_selected.connect(func(idx):
		Audio.sfx("click")
		if idx == 0:
			s["kind"] = "human"
			s["ai"] = ""
			if not FACES.has(str(s.get("portrait", ""))):
				s["portrait"] = "player"
			s["name"] = "Player %d" % (i + 1) if i > 0 else "You"
		else:
			var a: String = AI_ORDER[idx - 1]
			s["kind"] = "ai"
			s["ai"] = a
			s["name"] = Ai.COMMANDERS[a]["name"]
		_refresh())
	row.add_child(who)
	var m: Types.MapDef = _mapdefs[map_path]
	if seats.size() > m.min_players:
		row.add_child(Style.chip("✕", func():
			seats.remove_at(i)
			_refresh(), Style.MUTED))
	return row


func _option_row(title: String, labels: Array, values: Array, current, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Style.label(title, 20, Style.CREAM, "bold")
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(300, 40)
	for x in labels:
		o.add_item(x)
	o.selected = maxi(0, values.find(current))
	o.item_selected.connect(func(idx):
		Audio.sfx("click")
		cb.call(values[idx]))
	h.add_child(o)
	return h


func _start() -> void:
	var cfg_seats: Array = []
	var human_name := ""
	for i in seats.size():
		var s: Dictionary = seats[i]
		var nm: String = str(s["name"]).strip_edges()
		if nm == "":
			nm = "Player %d" % (i + 1)
		if s["kind"] == "human" and human_name == "":
			human_name = nm
		cfg_seats.append({
			"id": Setup.SEAT_IDS[i],
			"name": nm,
			"kind": s["kind"],
			"ai": s["ai"] if s["kind"] == "ai" else "",
			"portrait": str(s.get("portrait", "player")) if s["kind"] == "human" else str(s["ai"]),
		})
	Settings.set_value("last_setup", {"map": map_path, "seats": seats, "length": length, "timer": timer, "battle": battle, "deal": deal, "odds": odds, "name": human_name if human_name != "" else "You"})
	Settings.set_value("deal", deal)
	main.start_game({"map": map_path, "seats": cfg_seats, "length": length, "timer": timer, "battle": battle, "deal": deal, "firing_line": odds == "line", "tutorial": false})


class _Swatch extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := "red"

	func _draw() -> void:
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, 16.0, Style.seat_color(pid), Style.CREAM, 2.0)
