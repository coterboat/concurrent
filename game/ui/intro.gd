## "The commanders take their seats", on the war table (v2.4; until then a screen of its own, before the
## table). Each rival steps up as their die falls for the order of claims (the owner: "move the
## introductions of the characters from its own screen to just before and while the initial dice are
## being rolled to see who goes first"): a card with their face, name, manner and level, and their
## greeting in their own voice. A commander at the table gets a card too, without a word. On a war whose
## lands are dealt (no roll), the rivals step up the same way before the deployment.
## game_screen.gd runs who sits when, and the dice; this is the card.
extends PanelContainer

const Style := preload("res://game/core/style.gd")
const Lines := preload("res://game/core/lines.gd")
const Ai := preload("res://engine/ai.gd")
const LeaderFace := preload("res://game/ui/leader_face.gd")

signal pressed ## a click on the card: on to the next commander
signal skipped ## no more introductions (_done: the old screen's way out)

var seat_id := "" ## whose card this is now ("" when it's away)
var _face: Control
var _name: Label
var _blurb: Label
var _line: Label
var _hint: Label
var _tw: Tween


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.04, 0.07, 0.93), Color(Style.GOLD, 0.65), 1, 10, 14))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(118, 118)
	row.add_child(holder)
	_face = LeaderFace.new()
	_face.custom_minimum_size = Vector2(112, 112)
	_face.bubble_side = "none"
	holder.add_child(_face)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 3)
	row.add_child(v)
	_name = Style.label("", 30, Style.CREAM, "display")
	v.add_child(_name)
	_blurb = Style.label("", 16, Style.PARCH, "italic")
	v.add_child(_blurb)
	_line = Style.label("", 19, Style.CREAM, "italic")
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(340, 0)
	v.add_child(_line)
	_hint = Style.label("Space: next  ·  Esc: skip the introductions", 12, Color(Style.MUTED, 0.85), "italic")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_hint)
	visible = false


func show_seat(session: Node, pid: String) -> float:
	## Up comes this commander's card. A rival greets the table in their own voice: returns how long they
	## speak (0 for a commander at the table, or a line that couldn't be heard).
	var seat: Dictionary = session.seat(pid)
	seat_id = pid
	var human: bool = str(seat.get("kind", "ai")) == "human"
	var who: String = str(seat.get("portrait", "player")) if human else str(seat.get("ai", ""))
	_face.setup(who, pid, str(seat.get("name", pid)))
	_name.text = str(seat.get("name", pid))
	_name.add_theme_color_override("font_color", Style.seat_color(pid).lightened(0.45))
	if human:
		_blurb.text = "Your throw"
		_line.text = ""
	else:
		var c: Dictionary = Ai.COMMANDERS.get(who, {})
		var level: String = {"recruit": "Easy", "veteran": "Medium", "general": "Hard"}.get(str(c.get("level", "")), "")
		var bits := PackedStringArray()
		for b in [str(c.get("blurb", "")), level]:
			if b != "":
				bits.append(b)
		_blurb.text = "  ·  ".join(bits)
		_line.text = ("“%s”" % Lines.text(who, "greet")) if Lines.has(who, "greet") else ""
	_line.visible = _line.text != ""
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	reset_size()
	modulate.a = 0.0
	scale = Vector2(0.92, 0.92)
	pivot_offset = size * 0.5
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(self, "modulate:a", 1.0, 0.22)
	_tw.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if human or not Lines.has(who, "greet"):
		_face.react("happy")
		return 0.0
	return _face.react("happy", "greet", 3.0)


func leave() -> void:
	## the card goes (the next commander's comes up in its place)
	if not visible:
		return
	seat_id = ""
	mouse_filter = Control.MOUSE_FILTER_IGNORE ## going: a click passes to the map
	_face.hush()
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "modulate:a", 0.0, 0.18)
	_tw.tween_callback(func(): visible = false)


func _done() -> void:
	## the old screen's way out, kept for the probes and tools that skip the introductions: game_screen
	## throws whoever hasn't thrown yet, together, and goes on (Esc does the same in the game)
	skipped.emit()


func _gui_input(e: InputEvent) -> void:
	if visible and seat_id != "" and e is InputEventMouseButton and e.pressed:
		pressed.emit()
		accept_event()
