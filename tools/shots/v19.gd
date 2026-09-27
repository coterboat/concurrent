## v1.9 in the real client: the living title painting, Fortune's stars (roster and battle), a
## card's star fading from the map, a war chest divided by the dice, capitals on the final
## chart, and a cutscene when there is one.
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
	Settings.data["battles"] = "mine"
	Settings.data["roll_yourself"] = true
	Settings.data["motion"] = "all"
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)

	## --- the title: the war room breathes
	main.show_title()
	await p.frames(90)
	var vps: Array = main.current.find_children("*", "VideoStreamPlayer", true, false)
	var has_film: bool = ResourceLoader.exists("res://assets/video/title_loop.ogv")
	p.ok(not has_film or (not vps.is_empty() and (vps[0] as VideoStreamPlayer).is_playing()), "the title painting plays its film (%s)" % ("film on disk" if has_film else "no film yet: the still"))
	await snap("00_title_living")

	## --- the settings panel still fits a 900-high window with the Films row
	main.open_settings()
	await p.frames(10)
	var pcs: Array = main.settings_panel.find_children("*", "PanelContainer", true, false)
	var ph: float = (pcs[0] as Control).size.y if not pcs.is_empty() else 9999.0
	p.ok(ph <= 880.0, "the settings panel fits the window (%d px of 900)" % int(ph))
	await snap("00b_settings")
	main.settings_panel.closed.emit()
	await p.frames(4)

	## --- Fortune on the roster
	main.start_game({"map": "res://maps/knife7.json", "seed": 5, "length": "standard", "timer": 0, "capitals": false, "fortune": true, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_ironduke"},
		{"id": "blue", "name": "Grand Marshal Varek", "kind": "ai", "ai": "varek", "portrait": "varek"},
		{"id": "green", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"}]})
	await p.frames(6)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	if gs.cutscene.visible:
		gs.cutscene._close()
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	var guard := 0
	while s.phase != Session.Phase.PLANNING and guard < 1200:
		guard += 1
		await p.frames(1)
	var w: Types.World = s.world
	w.players["red"].fortune = 2
	w.players["red"].fortune_meter = 30
	w.players["blue"].fortune = 1
	s.changed.emit()
	await p.frames(6)
	var pips: Control = gs.roster._rows["red"]["pips"]
	p.ok(pips.visible and pips.held == 2 and absf(pips.share - 0.6) < 0.01, "the roster shows our two favours and the bar 60%% of the way to a third (%d, %.2f)" % [pips.held, pips.share])
	await snap("01_roster_stars")

	## --- a card's star on the map says where free troops appeared, then fades
	var land: String = str(MapLib.player_territory_ids(w, "red")[0])
	gs.board.bonus = {land: 1}
	gs.board.refresh()
	await p.frames(20)
	await snap("02_card_star")
	p.ok(gs.board.bonus_seen.has(land), "the gold star pops up on %s" % land)
	var t0: float = gs.board.now()
	guard = 0
	while gs.board.now() - t0 < 4.5 + 0.2 and guard < 1200:
		guard += 1
		await p.frames(1)
	p.ok(gs.board.now() - float(gs.board.bonus_seen.get(land, 0.0)) >= 4.5, "and after a few seconds it has faded away")
	await snap("03_card_star_gone")
	gs.board.bonus = {}

	## --- a war chest divided: we and Varek take Hask's last two lands in the same round
	for t in w.territories.keys():
		w.set_hex(str(t), Types.UNOCCUPIED, 0)
	w.set_hex("ridge", "red", 3, 1)
	w.set_hex("beacon", "red", 2, 1)
	w.set_hex("mill", "red", 2, 1)
	w.set_hex("gate", "red", 18, 1)
	w.set_hex("docks", "blue", 18, 1)
	w.set_hex("harbor", "green", 1)
	w.set_hex("quarry", "green", 1)
	w.players["green"].cards = PackedStringArray(["sun@harbor", "moon@quarry", "star@mill", "sun@gate"])
	s.drafts.clear()
	s.changed.emit()
	await p.frames(4)
	s.set_attack("gate", "harbor", 17)
	var bs := Types.Sheet.new()
	bs.player_id = "blue"
	var bp := Types.Packet.new()
	bp.from_id = "docks"
	bp.to_id = "quarry"
	bp.strength = 17
	bp.stance = "judgment"
	bs.packets = [bp]
	s.locked["blue"] = bs
	var gsh := Types.Sheet.new()
	gsh.player_id = "green"
	s.locked["green"] = gsh
	s.lock()
	var th: Control = gs.theater
	var split_seen := false
	var stars_in_battle := false
	var volley_snap := false
	var won_snap := false
	guard = 0
	while guard < 6000 and s.phase != Session.Phase.RECAP and s.phase != Session.Phase.PLANNING and s.phase != Session.Phase.MANEUVER:
		guard += 1
		if th.visible:
			if th._fort_a.visible and th._fort_a.held == 2 and not stars_in_battle:
				stars_in_battle = true
				await p.frames(30)
				await snap("04_battle_stars")
			if str(th._state) == "rolling" and not volley_snap:
				volley_snap = true
				await p.frames(75)
				await snap("04b_volley")
			if str(th._state) == "done" and not won_snap:
				won_snap = true
				await p.frames(50)
				await snap("04c_battle_won")
			if str(th._state) in ["ready", "done"]:
				th.press()
			elif str(th._state) == "call":
				th._answer("p" if not th._btn_fortune.visible else "n")
		elif gs.cinema.visible and not gs.cinema._waiting:
			var bb: Dictionary = gs.cinema.beats[gs.cinema.index] if gs.cinema.index >= 0 and gs.cinema.index < gs.cinema.beats.size() else {}
			if bb.has("split_throws") and not split_seen:
				split_seen = true
				await p.frames(210)
				await snap("05_chest_divided")
			if gs.cutscene.visible:
				gs.cutscene._close()
			gs.cinema.advance()
		await p.frames(1)
	p.ok(stars_in_battle, "in our battle the stars under our dice show our two favours")
	var divided := false
	for e in s.events:
		if str(e.get("kind", "")) == Types.EVENT_CARDS_CAPTURED and (e as Dictionary).has("split"):
			divided = true
	p.ok(not s.world.players["green"].alive, "Hask is gone")
	p.ok(divided and split_seen, "the chest was divided by the dice, and the report threw them on the map")
	p.ok(s.world.players["red"].cards.size() + s.world.players["blue"].cards.size() >= 4, "every card went to one of the two victors (%d + %d)" % [s.world.players["red"].cards.size(), s.world.players["blue"].cards.size()])

	## --- the final chart marks capitals taken
	s.capital_log.append({"round": 1, "pid": "blue", "by": "red", "land": "docks"})
	gs.game_over.show_result()
	await p.frames(40)
	await snap("06_chart_capitals")
	p.ok(gs.game_over.visible, "the end-of-war chart draws with a capital taken on it")
	gs.game_over.visible = false

	## --- a cutscene, if the film exists
	if gs.cutscene.available("capital_taken"):
		gs._films_seen.erase("capital_taken")
		var played: bool = gs._film("capital_taken", "Varek's capital falls", "capital_taken")
		await p.frames(70)
		await snap("07_cutscene")
		p.ok(played and gs.cutscene.visible, "the capital-taken film plays over the game")
		gs.cutscene._close()
		await p.frames(40)
		p.ok(not gs.cutscene.visible and not gs.cinema.paused, "and closes, handing the report back")
	else:
		p.log("no cutscene film on disk yet: skipped")
	p.log("v19 probe done")


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
