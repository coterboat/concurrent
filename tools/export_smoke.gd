## Smoke test run against the exported pack (not the project): every map's art and data load from
## what the build ships, and a new game starts on each through the real main scene.
##   godot --headless --path . --export-pack "Windows" ../smoke.pck
##   godot --headless --main-pack ../smoke.pck --script <the absolute path of this file> (tools/ is not in the pack)
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	## fence the player's save slot and settings (CLAUDE.md: anything that runs a Session)
	load("res://game/core/session.gd").SAVE_PATH = "user://smoke_savegame.json"
	var st: Node = root.get_node("Settings")
	st.persist = false
	for k in ["music", "sfx", "ambience", "voices"]:
		st.data[k] = 0.0
	st.data["motion"] = "paintings"
	var MapArt: Script = load("res://game/board/map_art.gd")
	var bad := 0
	for m in ["knife7", "marches18", "known24", "isles24", "ring26", "world30"]:
		var art: RefCounted = MapArt.load_for(m)
		var ok: bool = art != null and art.data_image != null and art.data_image.get_width() > 0
		print("SMOKE %s map %s: art %s, data %s" % ["ok  " if ok else "FAIL", m, str(art != null), "%dx%d" % [art.data_image.get_width(), art.data_image.get_height()] if ok else "missing"])
		if not ok:
			bad += 1
	var main: Control = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	for m in ["knife7", "marches18", "known24", "isles24", "ring26", "world30"]:
		main.start_game({"map": "res://maps/%s.json" % m, "seed": 7, "length": "short", "timer": 0, "deal": "random", "seats": [
			{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
			{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
			{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
		for i in 10:
			await process_frame
		var s: Node = main.session
		var ok2: bool = s.map != null and s.map.id == m and main.current.board.art != null
		print("SMOKE %s game on %s: phase %d, %d lands" % ["ok  " if ok2 else "FAIL", m, s.phase, s.map.territory_ids().size() if s.map else 0])
		if not ok2:
			bad += 1
	print("SMOKE done, %d failed" % bad)
	quit(1 if bad > 0 else 0)
