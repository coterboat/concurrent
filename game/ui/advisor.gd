## The old military advisor in the corner. Tutorial lessons, then gentle hints.
extends PanelContainer

const Style := preload("res://game/core/style.gd")
const Session := preload("res://game/core/session.gd")
const MapLib := preload("res://engine/map.gd")

var session: Node
var gs: Control
var _text: Label
var _dismissed := {} ## tip key -> true
var _key := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.045, 0.08, 0.93), Color(Style.GOLD, 0.55), 1, 8, 12))
	set_anchors_preset(PRESET_BOTTOM_LEFT)
	offset_left = 12
	offset_bottom = -12
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(430, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	add_child(h)
	var pic := TextureRect.new()
	pic.texture = Style.portrait("advisor")
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(72, 72)
	pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	var top := HBoxContainer.new()
	var who := Style.label("Your advisor", 16, Style.GOLD, "display")
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	top.add_child(Style.chip("Got it", func():
		_dismissed[_key] = true
		refresh(), Style.MUTED, 13))
	v.add_child(top)
	_text = Style.label("", 17, Style.CREAM)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(320, 0)
	v.add_child(_text)
	visible = false


func refresh() -> void:
	if session == null or session.world == null:
		visible = false
		return
	var tip: Array = _tip()
	_key = str(tip[0])
	if _key == "" or _dismissed.has(_key):
		visible = false
		return
	_text.text = str(tip[1])
	visible = true
	reset_size()


func _tip() -> Array:
	var s = session
	var ph: int = s.phase
	if ph != Session.Phase.PLANNING and ph != Session.Phase.OPENING:
		return ["", ""]
	if gs.surge_pick >= 0:
		return ["surgepick", "Pick where the survivors go next: any enemy or empty land touching the target. They only go if the first attack wins, and surges happen after every other battle."]
	var tutorial: bool = bool(s.config.get("tutorial", false))
	var tips_on: bool = bool(Settings.get_value("tips", true))
	if not tutorial and not tips_on:
		return ["", ""]
	var warn: PackedStringArray = s.warnings()
	## Tutorial script, one lesson per round on the Isthmus.
	if tutorial:
		var r: int = s.world.round
		if ph == Session.Phase.OPENING:
			return ["t-open", "Welcome, commander. This is the Isthmus: a north shore and a south shore joined only by The Gate.\n\nFirst, place your starting armies. Click one of your lands to select it, then click it again to add an army. A land can take up to twice (1 + your neighboring lands) — spread out or pile up at a border."]
		if r == 1:
			if s.placed_total() < s.income_total():
				return ["t-r1a", "Every round you get reinforcements: at least 3, more for lands and whole regions. Click your lands to place them — they can attack this very round.\n\nThe ≤ numbers on enemy lands show the most they could hold after secretly reinforcing."]
			if s.sheet().packets.is_empty():
				return ["t-r1b", "Now attack. With your land selected, click an enemy (or empty) neighbor — or drag from your land onto it.\n\nEveryone's orders happen at the same time. Armies you send LEAVE HOME, so watch what you leave behind."]
			return ["t-r1c", "Battles are one roll each: armies + one die. Higher total wins; ties go to the attacker. The winner loses half the loser's size.\n\nHappy? Press Seal Orders. Then watch it all unfold."]
		if r == 2:
			return ["t-r2", "Lands you hold dig in: each round a held land gains a dug-in defender (the little shield). Dug-in troops never march — so a dug-in land can send out every other soldier and still stay yours.\n\nFrom round 2 you may also make one move: drag from your land onto a neighbor of yours."]
		if r == 3:
			return ["t-r3", "Surge: after you order an attack, press 'Surge onward…' in your orders and pick the next land. If the first attack wins, the survivors (all but one) keep marching — after every other battle is done."]
		if s.is_last_round():
			return ["t-last", "Final round! The score is your lands plus region bonuses. Soldiers left standing are worth nothing after this — throw them at anything you can take."]
		if r == 4:
			return ["t-r4", "Look for a walk-in: if an enemy land was stripped bare last round, the faded ghost arrows show who marched where. A single army can walk into an empty land."]
	if not warn.is_empty() and (ph == Session.Phase.PLANNING):
		return ["w-" + warn[0], warn[0]]
	if ph == Session.Phase.OPENING:
		return ["open", "Place your starting armies: select a land, click again to add. Right-click removes one. 'Auto-place the rest' lets the quartermaster finish."]
	if s.world.round == 1 and not bool(s.config.get("tutorial", false)):
		return ["r1", "Select one of your lands, then click an enemy neighbor to attack — or drag onto it. Click your selected land again to reinforce it. Attackers leave home, so watch your borders."]
	if s.is_last_round() and not s.conquest():
		return ["last", "Final round: only lands and regions count once this resolves. Commit everything."]
	return ["", ""]
