## Music, ambience and sound effects (all generated with Ludo.ai). Autoload "Audio".
extends Node

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _pool: Array = []
var _next := 0
var _cache := {}
var _current := ""
var _last_play := {}
var _voice: AudioStreamPlayer
var _ducked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Ambience", "Voice"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_music_a = _player("Music")
	_music_b = _player("Music")
	_amb = _player("Ambience")
	_voice = _player("Voice")
	_voice.finished.connect(_next_line)
	for i in 10:
		_pool.append(_player("SFX"))
	for i in 6:
		_knocks.append(_player("SFX"))
	apply_volumes()


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func apply_volumes() -> void:
	var s := get_node_or_null("/root/Settings")
	var music: float = float(s.get_value("music", 0.55)) if s else 0.55
	var sfx_v: float = float(s.get_value("sfx", 0.8)) if s else 0.8
	var amb: float = float(s.get_value("ambience", 0.35)) if s else 0.35
	_set_bus("Music", music)
	_set_bus("SFX", sfx_v)
	_set_bus("Ambience", amb)
	var voices: float = float(s.get_value("voices", 0.9)) if s else 0.9
	_set_bus("Voice", voices)


func _set_bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func _stream(path_no_ext: String, loop: bool = false) -> AudioStream:
	var key := path_no_ext + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = null
	for ext in [".mp3", ".wav", ".ogg"]:
		if ResourceLoader.exists(path_no_ext + ext):
			s = load(path_no_ext + ext)
			break
	if s != null and loop:
		s = s.duplicate()
		if s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = true
		elif s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s


## v1.5: some sounds are a handful of takes, picked at random so a long fight never repeats
## itself: black-powder volleys and shots that boom, and horses at a real three-beat gallop.
const VARIANTS := {
	"volley": ["musket_volley_1", "musket_volley_2", "musket_volley_3"],
	"shot": ["musket_shot_1", "musket_shot_2"],
	"hoofs": ["cavalry_gallop"],
	"cavalry": ["cavalry_charge"],
	"far": ["far_cannon", "far_volley", "far_drums", "far_bugle", "far_shouts"],
}
var _last_variant := {}


func has_sfx(name: String) -> bool:
	## v1.9: new sounds arrive from the generator; callers fall back to an old one until then
	return _stream(SFX_DIR + name) != null


func sfx(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.04) -> void:
	## Same sound within 60 ms is dropped so a burst of events does not stack.
	if VARIANTS.has(name):
		var takes: Array = []
		for t in VARIANTS[name]:
			if _stream(SFX_DIR + str(t)) != null:
				takes.append(str(t))
		if not takes.is_empty():
			if takes.size() > 1:
				takes.erase(_last_variant.get(name, ""))
			var pick: String = str(takes[randi() % takes.size()])
			_last_variant[name] = pick
			var now0 := Time.get_ticks_msec()
			if now0 - int(_last_play.get(name, -1000)) < 60:
				return
			_last_play[name] = now0
			_play_sfx(pick, volume_db, pitch_jitter)
			return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 60:
		return
	_last_play[name] = now
	_play_sfx(name, volume_db, pitch_jitter)


func _play_sfx(name: String, volume_db: float, pitch_jitter: float) -> void:
	var s := _stream(SFX_DIR + name)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## v1.4: every die that hits the table knocks, by what it is made of, as hard as it hit.
## Their own small pool, so a clatter of dice never steals a volley's player.
var _knocks: Array = []
var _knock_i := 0


func knock(name: String, strength: float) -> void:
	var s := _stream(SFX_DIR + name)
	if s == null:
		s = _stream(SFX_DIR + "dice_click")
	if s == null:
		return
	var p: AudioStreamPlayer = _knocks[_knock_i]
	_knock_i = (_knock_i + 1) % _knocks.size()
	p.stream = s
	p.volume_db = linear_to_db(clampf(0.18 + 0.82 * strength, 0.05, 1.0)) - 3.0
	p.pitch_scale = randf_range(0.9, 1.12) * (1.0 + (1.0 - strength) * 0.08)
	p.play()


func cheer(n: int, volume_db: float = -6.0) -> void:
	## a handful of men cheer for a handful; a grand army roars. Bigger is fuller, not louder:
	## the takes are levelled, and the big ones sit a little further back.
	if n <= 0:
		return
	if n <= 4:
		sfx("cheer_few", volume_db + 1.0, 0.06)
	elif n <= 14:
		sfx("cheer_company", volume_db, 0.05)
	else:
		sfx("cheer_company", volume_db - 3.0, 0.05)
		get_tree().create_timer(0.12).timeout.connect(func(): sfx("cheer_army", volume_db - (2.0 if n >= 30 else 4.0), 0.03))


## v1.3 music: each mood is a playlist of takes. A take plays through once, and a few
## seconds before its ending swells it crossfades into another take of the same mood,
## so the music never snaps from a crescendo back to a quiet opening.
const PLAYLISTS := {
	"menu": ["menu", "menu_2"],
	"plan": ["plan", "plan_2", "plan_3"],
	"battle": ["battle", "battle_2", "battle_3"],
	"charge": ["charge", "charge_2", "charge_3"],
	"muster": ["muster", "plan_2"],
	## v1.9: Ludo remixes of the menu, plan and battle themes, and a sung march
	"victory": ["victory", "march_song"],
	"defeat": ["defeat", "lament"],
	"besieged": ["besieged"],
	"endgame": ["endgame", "battle_3"],
}
const XFADE := 6.0 ## seconds of overlap between takes
var _take := "" ## file playing now
var _player_now: AudioStreamPlayer
var _looping := true


func has_music(name: String) -> bool:
	## v1.9: a mood only plays if one of its takes is on disk (new remixes arrive later)
	for t in PLAYLISTS.get(name, [name]):
		if _stream(MUSIC_DIR + str(t)) != null:
			return true
	return false


func music(name: String, fade: float = 1.2, loop: bool = true) -> void:
	if name == _current:
		return
	_current = name
	_looping = loop
	if name == "":
		_crossfade("", fade)
		return
	_crossfade(_next_take(name), fade)


func _next_take(mood: String) -> String:
	var takes: Array = PLAYLISTS.get(mood, [mood])
	var have: Array = []
	for t in takes:
		if _stream(MUSIC_DIR + str(t)) != null:
			have.append(str(t))
	if have.is_empty():
		return mood
	if have.size() > 1:
		have.erase(_take) ## never the same take twice running
	return str(have[randi() % have.size()])


func _crossfade(take: String, fade: float) -> void:
	var old: AudioStreamPlayer = _player_now if _player_now != null else _music_a
	var nxt: AudioStreamPlayer = _music_b if old == _music_a else _music_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.tween_callback(old.stop)
	_take = take
	if take == "":
		_player_now = nxt
		return
	var s: AudioStream = _stream(MUSIC_DIR + take, false) ## played through once; the playlist does the looping
	if s == null:
		return
	nxt.stream = s
	nxt.volume_db = -40.0
	nxt.play()
	_player_now = nxt
	var tw2 := create_tween()
	tw2.tween_property(nxt, "volume_db", 0.0, fade)


func _process(_delta: float) -> void:
	## hand over to the next take before this one's ending
	if not _looping or _player_now == null or not _player_now.playing or _player_now.stream == null or _current == "":
		return
	var length: float = _player_now.stream.get_length()
	if length > XFADE * 3.0 and _player_now.get_playback_position() >= length - XFADE:
		_crossfade(_next_take(_current), XFADE)


## v1.10 nobody is cut off. A line the game starts by itself waits for the one being spoken
## (and is dropped if it waited too long for its moment); a line that follows the player's
## own click or key within INTERRUPT_MS may cut in, and Space/Enter skips the line outright.
const INTERRUPT_MS := 600
const STALE_MS := 5000
var _queue: Array = [] ## [{path, at, cb}]
var _last_input := -100000


func _input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed and not e.echo):
		_last_input = Time.get_ticks_msec()
		if e is InputEventKey and (e.keycode == KEY_SPACE or e.keycode == KEY_ENTER) and _voice.playing:
			skip_voice()


func voice(path: String, urgent: bool = false, on_start: Callable = Callable()) -> float:
	## Plays one spoken line and ducks the music. Returns its length in seconds (0 if silent).
	## If another line is still being spoken and this one isn't urgent (nor the player's doing),
	## it is queued: returns -1, and on_start(seconds) is called if and when it plays.
	if path == "" or not ResourceLoader.exists(path):
		return 0.0
	var s := get_node_or_null("/root/Settings")
	if s and float(s.get_value("voices", 0.9)) <= 0.001:
		return 0.0
	var now := Time.get_ticks_msec()
	if _voice.playing and not urgent and now - _last_input > INTERRUPT_MS:
		_queue.append({"path": path, "at": now, "cb": on_start})
		while _queue.size() > 2:
			_queue.pop_front() ## the oldest waiting line has had its moment
		return -1.0
	if urgent or now - _last_input <= INTERRUPT_MS:
		_queue.clear()
	return _play_line(path)


func _play_line(path: String) -> float:
	var st: AudioStream = load(path)
	_voice.stream = st
	_voice.play()
	_duck(true)
	return st.get_length()


func _next_line() -> void:
	## the line ended: the next one waiting, if it is still timely
	var now := Time.get_ticks_msec()
	while not _queue.is_empty():
		var q: Dictionary = _queue.pop_front()
		if now - int(q["at"]) > STALE_MS:
			continue
		var secs: float = _play_line(str(q["path"]))
		var cb: Callable = q["cb"]
		if cb.is_valid():
			cb.call(secs)
		return
	_duck(false)


func skip_voice() -> void:
	## the player moved on: stop the line and forget the ones waiting
	_queue.clear()
	if _voice.playing:
		_voice.stop()
	_duck(false)


func voice_playing() -> bool:
	return _voice.playing


func _duck(on: bool) -> void:
	if on == _ducked:
		return
	_ducked = on
	var i := AudioServer.get_bus_index("Music")
	var s := get_node_or_null("/root/Settings")
	var base: float = linear_to_db(maxf(float(s.get_value("music", 0.55)) if s else 0.55, 0.001))
	AudioServer.set_bus_volume_db(i, base - (9.0 if on else 0.0))


func ambience(on: bool, name: String = "ambience_tent") -> void:
	if on and _amb.playing and _amb.has_meta("name") and str(_amb.get_meta("name")) != name:
		_amb.stop()
	if on and not _amb.playing:
		_amb.set_meta("name", name)
		_amb.stream = _stream(MUSIC_DIR + name, true)
		_amb.volume_db = -6.0
		_amb.play()
	elif not on and _amb.playing:
		_amb.stop()
