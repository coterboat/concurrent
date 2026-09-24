## Illustrated rules, one idea per page. Works as a screen or as an in-game overlay.
extends Control

const Style := preload("res://game/core/style.gd")

var main: Control
var overlay := false
var start_page := 0
var page := 0
var _art: TextureRect
var _title: Label
var _body: Label
var _count: Label
var _prev: Button
var _next: Button

const PAGES := [
	["The big idea", "howto_sealed",
	"Every commander writes their orders in secret, at the same time. Nobody moves first. When everyone has sealed their orders, they all happen at once.\n\nThat is the whole game: you are always guessing what everyone else is about to do."],
	["Reinforce", "howto_cards",
	"Each round you get new armies: one for every three lands you hold (at least 3), a little extra for a big connected empire, and a bonus for every region you hold completely.\n\nYou can place at most 1 + (the number of your own lands touching it) on any single land — so a lonely outpost can't become a fortress overnight. Anything you don't place is lost."],
	["Attack — and leave home", "howto_march",
	"To attack, pick one of your lands and send armies at a neighboring land. Those armies LEAVE HOME the moment orders are sealed. They do not defend the land they left.\n\nOne army must stay behind (unless the land is dug in). Several of your attacks on the same target join together."],
	["The walk-in", "howto_walkin",
	"While your armies are away, somebody else may attack the land you just emptied. If you left one army behind, one attacker might be all it takes.\n\nThis is the groan the game is built on. The faded ghost arrows on the map show where everyone marched last round."],
	["Battles", "howto_clash",
	"Every fight is one roll: each side adds one die to its number of armies. The higher total wins; if an attacker ties, the attacker wins. The loser is wiped out, and the winner loses half as many as the loser had.\n\nIf two commanders attack each other's lands, the armies meet in the field first — a border clash. If several commanders hit the same land, they fight the defender one at a time, and then each other for the spoils."],
	["Surge", "howto_surge",
	"When you order an attack you can name a second target beyond it. If the first attack wins, everyone but one presses on into the second land.\n\nSurges happen after every other battle, so a breakthrough can never spoil someone else's plan mid-fight."],
	["Digging in", "howto_dugin",
	"Every round you keep a land, it gains one dug-in defender (the shield on its token), up to 1 + your neighboring lands (+1 more if you hold its whole region).\n\nDug-in defenders never march. So a dug-in land can send out every other soldier and still be safe from a single walk-in. Fresh conquests start with no dug-in defenders."],
	["Cards and winning", "howto_cards",
	"On the bigger maps, capturing at least one land in a round earns a card. Three matching, or one of each (wilds fill in), trade for extra armies: 4, then 6, 8, 10, then 5 more each time anyone trades.\n\nThe game ends after the last round: your score is your lands plus the bonus of each region you hold. Holding 80% of the map, or being the last one standing, wins at once."],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.97 if overlay else 1.0)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 48)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(Style.label("How to Play", 44, Style.CREAM, "display"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	if not overlay:
		head.add_child(Style.button("Play the Tutorial", func(): main.start_tutorial(), 0))
	head.add_child(Style.button("Close" if overlay else "Back", func(): _close(), 140))
	v.add_child(head)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 30)
	v.add_child(row)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art.size_flags_stretch_ratio = 1.1
	row.add_child(_art)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 14)
	row.add_child(tv)
	_title = Style.label("", 38, Style.GOLD, "display")
	tv.add_child(_title)
	_body = Style.label("", 23, Style.CREAM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(460, 0)
	tv.add_child(_body)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 20)
	v.add_child(nav)
	_prev = Style.button("◀  Previous", func(): _go(-1), 200)
	nav.add_child(_prev)
	_count = Style.label("", 20, Style.MUTED)
	nav.add_child(_count)
	_next = Style.button("Next  ▶", func(): _go(1), 200)
	nav.add_child(_next)
	page = clampi(start_page, 0, PAGES.size() - 1)
	_show()


func _go(d: int) -> void:
	if page + d >= PAGES.size():
		_close()
		return
	page = clampi(page + d, 0, PAGES.size() - 1)
	Audio.sfx("pass", -6.0)
	_show()


func _show() -> void:
	var p: Array = PAGES[page]
	_title.text = p[0]
	_art.texture = Style.tex("res://assets/art/%s.webp" % p[1])
	_body.text = p[2]
	_count.text = "%d / %d" % [page + 1, PAGES.size()]
	_prev.disabled = page == 0
	_next.text = "Done" if page == PAGES.size() - 1 else "Next  ▶"


func _close() -> void:
	if overlay:
		queue_free()
	else:
		main.show_title()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT:
			_go(1)
		elif event.keycode == KEY_LEFT:
			_go(-1)
		elif event.keycode == KEY_ESCAPE:
			_close()
		else:
			return
		get_viewport().set_input_as_handled()
