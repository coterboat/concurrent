## Root: theme, backdrop and screen switching. Screens are plain Controls.
extends Control

const Style := preload("res://game/core/style.gd")
const SessionScript := preload("res://game/core/session.gd")
const TitleScreen := preload("res://game/ui/title_screen.gd")
const SetupScreen := preload("res://game/ui/setup_screen.gd")
const HowToScreen := preload("res://game/ui/howto_screen.gd")
const GameScreen := preload("res://game/ui/game_screen.gd")
const SettingsPanel := preload("res://game/ui/settings_panel.gd")
const WindowFit := preload("res://game/core/window_fit.gd")
const Confirm := preload("res://game/ui/confirm.gd")

var session: Node
var current: Control
var settings_panel: Control


func _ready() -> void:
	theme = Style.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	get_window().min_size = WindowFit.LEAST ## (v2.5: no more than the screen holds, once it's placed)
	var bg := ColorRect.new()
	bg.color = Style.INK
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	session = SessionScript.new()
	session.name = "Session"
	add_child(session)
	show_title()
	_fit_window.call_deferred()


func _fit_window() -> void:
	## v2.3: open at a size that fits the screen it's on. The project asks for 1440×900: more than a
	## 1366×768 laptop has, and a postage stamp on a 4K monitor. On Windows and Linux the window takes
	## 85% of the usable screen, or (v2.5) a small screen's all, maximized (game/core/window_fit.gd).
	## The Mac sizes its windows in points and already fits; a probe (not the main scene) is left alone.
	if OS.get_name() == "macOS" or get_tree().current_scene != self or DisplayServer.get_name().begins_with("headless"):
		return
	first_text_size(WindowFit.apply(get_window(), true))


func first_text_size(small_screen: bool) -> void:
	## v2.5: a laptop's first launch reads Large (Settings, Text size: the player can go back to Normal).
	## Dad's 14-inch Lenovo (Alex, 11-03): at 1366x768 the words came out at 78% of their size, and at a
	## 1920x1080 panel's 150% at 111% where Windows gives everything else 150%. Large makes them 90% and
	## 128%, and every screen holds it (probe v25). Only before a text size was ever saved: never a choice
	## made, nor a desktop's screen
	if small_screen and not Settings.ui_scale_kept:
		Settings.set_value("ui_scale", Settings.UI_SCALE_MAX)
		Settings.ui_scale_kept = true


func _swap(next: Control) -> void:
	if current != null:
		current.queue_free()
	current = next
	current.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(current)
	if settings_panel != null:
		move_child(settings_panel, get_child_count() - 1)


func show_title(notice: String = "") -> void:
	var t: Control = TitleScreen.new()
	t.main = self
	t.notice = notice
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


func new_war(start: Callable, tutorial: bool = false) -> void:
	## v2.5: a new war (or the tutorial, a war too) takes the saved war's place on the title's Continue,
	## and nothing said so: a war played over three evenings went at a click on Tutorial. Asked first now
	var line: String = Confirm.saved_war_line()
	if line == "":
		start.call()
		return
	var c: Control = Confirm.new()
	c.title = "Start a new war?"
	c.body = line + (" The tutorial is a war too: starting it ends yours." if tutorial else " Starting a new war ends it.")
	c.choices = [["Start the tutorial" if tutorial else "Start the new war", start], ["Keep my war", func(): pass]]
	add_child(c)


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
	g.resuming = true ## v2.4: back on the view it was left on (the land, or the chart)
	_swap(g)
	if not session.load_save():
		## v2.5: set aside rather than offered again (Continue led back to the title, every time)
		SessionScript.set_aside_save()
		show_title("That saved war couldn't be opened. It's kept for Alex to look at.")


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
