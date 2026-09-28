## Who says what. Text and voice come from the same table (game/data/lines.json),
## so subtitles always match the audio. Commanders without lines stay quiet.
##
## v1.8: a line may have takes. In lines.json a key holds either one line or a list; take 1
## is <key>.mp3 and take n is <key>_v<n>.mp3. Takes are drawn from a shuffled bag, so none
## repeats until the others have been heard, and never twice in a row. Only takes that have
## a voice are drawn (a take still being generated, or rejected in review, stays silent and
## unseen). text() and voice_path() called for the same line within a moment agree.
extends RefCounted

static var _data: Dictionary = {}
static var _pick := {} ## "who|key" -> {i: take, t: msec}
static var _bag := {} ## "who|key" -> takes not yet heard this cycle
const SAME_MOMENT_MS := 1500


static func _load() -> void:
	if not _data.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/lines.json"))
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed.get("lines", {})


static func takes(who: String, key: String) -> Array:
	_load()
	var v: Variant = _data.get(who, {}).get(key, "")
	if typeof(v) == TYPE_ARRAY:
		return v
	return [v] if str(v) != "" else []


static func text(who: String, key: String) -> String:
	var t: Array = takes(who, key)
	if t.is_empty():
		return ""
	return subtitle(str(t[_choose(who, key)]))


## v1.11: a line's words are also its performance directions: *stars* stress a word for the
## voice. The subtitle keeps the words and drops the marks.
static func subtitle(s: String) -> String:
	return s.replace("*", "")


static func has(who: String, key: String) -> bool:
	return not takes(who, key).is_empty()


static func voice_path(who: String, key: String) -> String:
	if not has(who, key):
		return ""
	return _voice_of(who, key, _choose(who, key))


static func _voice_of(who: String, key: String, i: int) -> String:
	## v1.3: a second take of the commanders' voices (assets/voice13), the default since
	## v1.4 (Oren and Ysolde recast); Settings can bring back the classic takes.
	## The advisor keeps his one voice either way.
	var name: String = key if i == 0 else "%s_v%d" % [key, i + 1]
	var st: Node = Engine.get_main_loop().root.get_node_or_null("Settings") if Engine.get_main_loop() is SceneTree else null
	if who != "advisor" and (st == null or str(st.get_value("commander_voices", "new")) != "classic"):
		for ext in [".mp3", ".wav", ".ogg"]:
			var p2 := "res://assets/voice13/%s/%s%s" % [who, name, ext]
			if ResourceLoader.exists(p2):
				return p2
	for ext in [".mp3", ".wav", ".ogg"]:
		var p := "res://assets/voice/%s/%s%s" % [who, name, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


static func _choose(who: String, key: String) -> int:
	var k := who + "|" + key
	var now: int = Time.get_ticks_msec()
	if _pick.has(k) and now - int(_pick[k]["t"]) < SAME_MOMENT_MS:
		_pick[k]["t"] = now
		return int(_pick[k]["i"])
	var n: int = takes(who, key).size()
	var i := 0
	if n > 1:
		var voiced: Array = []
		for j in n:
			if _voice_of(who, key, j) != "":
				voiced.append(j)
		var pool: Array = voiced if not voiced.is_empty() else range(n)
		var bag: Array = (_bag.get(k, []) as Array).filter(func(x): return pool.has(x))
		if bag.is_empty():
			bag = pool.duplicate()
			bag.shuffle()
			## a new cycle never opens with the take that closed the last one
			var last: int = int(_pick[k]["i"]) if _pick.has(k) else -1
			if bag.size() > 1 and int(bag[-1]) == last:
				bag.push_front(bag.pop_back())
		i = int(bag.pop_back())
		_bag[k] = bag
	_pick[k] = {"i": i, "t": now}
	return i
