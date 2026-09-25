## Root: theme, backdrop and screen switching. Screens are plain Controls.
extends Control

const Style := preload("res://game/core/style.gd")
const SessionScript := preload("res://game/core/session.gd")
const TitleScreen := preload("res://game/ui/title_screen.gd")
const SetupScreen := preload("res://game/ui/setup_screen.gd")
const HowToScreen := preload("res://game/ui/howto_screen.gd")
const GameScreen := preload("res://game/ui/game_screen.gd")
const SettingsPanel := preload("res://game/ui/settings_panel.gd")

var session: Node
var current: Control
var settings_panel: Control


func _ready() -> void:
	theme = Style.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	get_window().min_size = Vector2i(1180, 720)
	var bg := ColorRect.new()
	bg.color = Style.INK
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	session = SessionScript.new()
	session.name = "Session"
	add_child(session)
	show_title()


func _swap(next: Control) -> void:
	if current != null:
		current.queue_free()
	current = next
	current.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(current)
	if settings_panel != null:
		move_child(settings_panel, get_child_count() - 1)


func show_title() -> void:
	var t: Control = TitleScreen.new()
	t.main = self
	_swap(t)
	Audio.music("menu")
	Audio.ambience(false)


func show_setup(tutorial: bool = false) -> void:
	var s: Control = SetupScreen.new()
	s.main = self
	s.tutorial = tutorial
	_swap(s)
	Audio.music("menu")


func show_howto(page: int = 0) -> void:
	var h: Control = HowToScreen.new()
	h.main = self
	h.start_page = page
	_swap(h)


func start_game(config: Dictionary) -> void:
	var g: Control = GameScreen.new()
	g.main = self
	g.session = session
	_swap(g)
	session.new_game(config)


func continue_game() -> void:
	var g: Control = GameScreen.new()
	g.main = self
	g.session = session
	_swap(g)
	if not session.load_save():
		show_title()


func start_tutorial() -> void:
	start_game({
		"map": "res://maps/knife7.json",
		"seats": [
			{"id": "red", "name": str(Settings.get_value("last_setup", {}).get("name", "You")), "kind": "human", "ai": "", "portrait": "player"},
			{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
		],
		"length": "standard",
		"battle": "volleys",
		"tutorial": true,
		"timer": 0,
	})


func open_settings() -> void:
	if settings_panel != null:
		return
	settings_panel = SettingsPanel.new()
	settings_panel.closed.connect(func():
		settings_panel.queue_free()
		settings_panel = null)
	settings_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(settings_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_F and event.meta_pressed and event.ctrl_pressed):
			Settings.set_value("fullscreen", not bool(Settings.get_value("fullscreen", false)))
