## v1.7 in the real client: the commander you choose to be, a fortress and a pass on the
## map and on the land card, an army cut off from its supply, and the new rules pages.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Style := preload("res://game/core/style.gd")

var p


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["speed"] = "fast"
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)

	## --- the setup screen: six faces to be, and the new maps on the shelf
	main.show_setup()
	await p.frames(12)
	await snap("01_setup_marches")
	var setup: Control = main.current
	## the page must fit the window: six maps once pushed the start button off the screen
	var vis: Rect2 = p.get_viewport().get_visible_rect()
	var br: Rect2 = setup.begin_button.get_global_rect()
	p.ok(vis.encloses(br) and br.size.y > 20.0, "Begin the Campaign is on screen (%s inside %s)" % [br, vis.size])
	var page: Control = null
	for c in setup.get_children():
		if c is MarginContainer:
			page = c
	p.ok(page != null and page.get_combined_minimum_size().y <= vis.size.y + 0.5, "the setup page is no taller than the window (%.0f of %.0f)" % [page.get_combined_minimum_size().y if page != null else -1.0, vis.size.y])
	p.ok(setup.MAPS.size() == 6, "six maps on the shelf (%s)" % setup.MAPS.size())
	var human := -1
	for i in setup.seats.size():
		if setup.seats[i]["kind"] == "human":
			human = i
	p.ok(human >= 0, "there is a human seat")
	setup.seats[human]["portrait"] = "you_lioness"
	setup._refresh()
	await p.frames(10)
	await snap("02_setup_face")
	p.ok(Style.portrait("you_lioness") != null, "the Lioness has a portrait")
	## every face the player may wear needs its stills, its moods and a loop that breathes,
	## packed and imported — a raw master that was never packed leaves the face sitting still
	var faces := 0
	var missing: Array = []
	for f in setup.FACES:
		if str(f) == "player":
			continue
		faces += 1
		for suffix in ["", "_triumphant", "_angry", "_defeated"]:
			if Style.portrait(str(f) + suffix) == null:
				missing.append(str(f) + suffix)
		if load("res://game/ui/leader_face.gd").loop_for(str(f), "idle").is_empty():
			missing.append(str(f) + " idle loop")
	p.ok(missing.is_empty(), "all %s commanders have their faces and their breathing (%s)" % [faces, missing])

	## --- The Marches: a fortress, a pass, and what the card says about them
	main.start_game({"map": "res://maps/marches18.json", "seed": 31, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_lioness"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"}]})
	await p.frames(8)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	await p.frames(6)
	var w: Types.World = s.world
	## stage it: red holds the northern fortress and the pass beside it
	w.set_hex("redgate", "red", 9, 3)
	w.set_hex("ironford", "red", 4, 1)
	w.set_hex("elmspire", "red", 6, 2)
	w.set_hex("blackford", "blue", 7, 2)
	w.set_hex("sunreach", "blue", 8, 2)
	gs.board.queue_redraw()
	gs.select("redgate")
	await p.frames(10)
	await snap("03_fortress_card")
	p.ok(MapLib.defender_line_bonus(s.map, "redgate") == 1, "Redgate is a fortress to the engine too")
	gs.select("ironford")
	await p.frames(10)
	await snap("04_pass_card")

	## --- an army with no road home
	main.start_game({"map": "res://maps/isles24.json", "seed": 77, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_lioness"},
		{"id": "blue", "name": "Viceroy Ysolde", "kind": "ai", "ai": "ysolde", "portrait": "ysolde"}]})
	await p.frames(8)
	s = main.session
	gs = main.current
	gs.intro._done()
	await p.frames(6)
	w = s.world
	for t in s.map.territory_ids():
		w.set_hex(str(t), "blue", 3, 1)
	for t in ["vanetor", "vanefell", "vaneholt", "vanemoor", "vanehead"]:
		w.set_hex(t, "red", 4, 1)
	w.set_hex("thalecliff", "red", 5, 1) ## away on Thale, with no harbour behind it
	gs.board.queue_redraw()
	gs.select("thalecliff")
	await p.frames(12)
	await snap("05_cut_off")
	p.ok(not MapLib.in_supply(w, s.map, "thalecliff"), "Thale Cliff really is cut off")
	p.ok(MapLib.in_supply(w, s.map, "vaneholt"), "the main body really is in supply")

	## --- a march by sea: two of your own harbours, and the arrow sails round
	w.set_hex("kestrelport", "red", 3, 1)
	w.set_hex("vanewick", "red", 8, 1)
	p.ok(s.marches_to("vanewick", "kestrelport") and not s.map.is_adjacent("vanewick", "kestrelport"), "the client lets a march cross the sea between two of your ports")
	gs.select("")
	gs.board.orders = [{"from": "vanewick", "to": "kestrelport", "strength": 5, "owner": "red", "kind": "move"}]
	gs.board.queue_redraw()
	await p.frames(6)
	await snap("06_sea_march")

	## --- the rules book explains the new rules
	var pages: Array = load("res://game/ui/howto_screen.gd").PAGES
	var titles: Array = []
	for pg in pages:
		titles.append(str(pg[0]))
	p.ok(titles.has("Fortresses, passes and ports") and titles.has("Supply"),
		"the rules book explains the new rules (%s pages)" % pages.size())
	p.log("v17 probe done")


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
