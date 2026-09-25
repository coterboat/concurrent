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
	_voice.finished.connect(func(): _duck(false))
	for i in 10:
		_pool.append(_player("SFX"))
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


func sfx(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.04) -> void:
	## Same sound within 60 ms is dropped so a burst of events does not stack.
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 60:
		return
	_last_play[name] = now
	var s := _stream(SFX_DIR + name)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## v1.3 music: each mood is a playlist of takes. A take plays through once, and a few
## seconds before its ending swells it crossfades into another take of the same mood,
## so the music never snaps from a crescendo back to a quiet opening.
const PLAYLISTS := {
	"menu": ["menu", "menu_2"],
	"plan": ["plan", "plan_2", "plan_3"],
	"battle": ["battle", "battle_2", "battle_3"],
	"charge": ["charge", "charge_2", "charge_3"],
	"muster": ["muster", "plan_2"],
}
const XFADE := 6.0 ## seconds of overlap between takes
var _take := "" ## file playing now
var _player_now: AudioStreamPlayer
var _looping := true


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


func voice(path: String) -> float:
	## Plays one spoken line (cutting off any line still going) and ducks the music.
	## Returns its length in seconds, 0 if silent.
	if path == "" or not ResourceLoader.exists(path):
		return 0.0
	var s := get_node_or_null("/root/Settings")
	if s and float(s.get_value("voices", 0.9)) <= 0.001:
		return 0.0
	var st: AudioStream = load(path)
	_voice.stream = st
	_voice.play()
	_duck(true)
	return st.get_length()


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
