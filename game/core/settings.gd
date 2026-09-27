## Player preferences, saved to user://settings.cfg. Autoload "Settings".
extends Node

const PATH := "user://settings.cfg"

signal changed

var data := {
	"music": 0.55,
	"sfx": 0.8,
	"ambience": 0.35,
	"voices": 0.9,
	"battles": "mine", ## mine | all | off — when to open the battle scene
	"roll_yourself": true, ## wait for ROLL in your own battles
	"map_view": 0,
	"speed": "normal", ## slow | normal | fast
	"tips": true,
	"fullscreen": false,
	"ui_scale": 1.0,
	"ceilings": true,
	"last_setup": {},
	"seen_tutorial": false,
	"commander_voices": "new", ## new (v1.3/1.4 second take, the default since v1.4) | classic
	"deal": "random", ## (v1.4–1.7) how new games handed out the lands; v1.8 moved it into the setup screen's Rules
	"dice_help_seen": 0, ## the battlefield opens "How a throw is scored" by itself the first two times
	"stance": "judgment",
	"calls_seen": 0,
	"motion": "all", ## v1.9: all (cutscenes and living paintings) | paintings (no cutscenes) | off (stills)
}


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in data.keys():
			if cfg.has_section_key("prefs", k):
				data[k] = cfg.get_value("prefs", k)
	apply()


func get_value(key: String, fallback: Variant = null) -> Variant:
	return data.get(key, fallback)


func remember(key: String, value: Variant) -> void:
	## a quiet preference (a counter, the last standing order): saved, nothing re-applied
	data[key] = value
	save()


func set_value(key: String, value: Variant) -> void:
	data[key] = value
	save()
	apply()
	changed.emit()


var persist := true ## probes and tests turn this off so they never touch the player's prefs


func save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("prefs", k, data[k])
	cfg.save(PATH)


func apply() -> void:
	var win := get_window()
	if win == null:
		return
	var want_full: bool = bool(data["fullscreen"])
	var is_full: bool = win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	if want_full != is_full and not DisplayServer.get_name().begins_with("headless"):
		win.mode = Window.MODE_FULLSCREEN if want_full else Window.MODE_WINDOWED
	win.content_scale_factor = float(data["ui_scale"])
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.apply_volumes()


func battle_delay() -> float:
	## Seconds per cinema beat.
	match str(data["speed"]):
		"slow":
			return 2.4
		"fast":
			return 0.75
		_:
			return 1.4
