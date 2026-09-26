## Who says what. Text and voice come from the same table (game/data/lines.json),
## so subtitles always match the audio. Commanders without lines stay quiet.
extends RefCounted

static var _data: Dictionary = {}


static func _load() -> void:
	if not _data.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/lines.json"))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed.get("lines", {})


static func text(who: String, key: String) -> String:
	_load()
	return str(_data.get(who, {}).get(key, ""))


static func has(who: String, key: String) -> bool:
	return text(who, key) != ""


static func voice_path(who: String, key: String) -> String:
	## v1.3: a second take of the commanders' voices (assets/voice13), the default since
	## v1.4 (Oren and Ysolde recast); Settings can bring back the classic takes.
	## The advisor keeps his one voice either way.
	var st: Node = Engine.get_main_loop().root.get_node_or_null("Settings") if Engine.get_main_loop() is SceneTree else null
	if who != "advisor" and (st == null or str(st.get_value("commander_voices", "new")) != "classic"):
		for ext in [".mp3", ".wav", ".ogg"]:
			var p2 := "res://assets/voice13/%s/%s%s" % [who, key, ext]
			if ResourceLoader.exists(p2):
				return p2
	for ext in [".mp3", ".wav", ".ogg"]:
		var p := "res://assets/voice/%s/%s%s" % [who, key, ext]
		if ResourceLoader.exists(p):
			return p
	return ""
