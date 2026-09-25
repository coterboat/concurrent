## Real mouse events through the viewport: select, place, attack, drag, surge.
extends RefCounted

const Session := preload("res://game/core/session.gd")
const MapLib := preload("res://engine/map.gd")

var p
var vp: Viewport

func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	Settings.data["sfx"] = 0.0
	Settings.data["music"] = 0.0
	vp = p.get_viewport()
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/knife7.json", "seed": 3, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Oren", "kind": "ai", "ai": "oren", "portrait": "oren"}]})
	await p.frames(10)
	var s: Node = main.session
	var gs: Control = main.current
	gs.intro._done()
	await p.frames(3)
	var b: Control = gs.board
	var mine := MapLib.player_territory_ids(s.world, "red")
	var t: String = mine[0]
	await click(b, t)
	p.ok(gs.selected == t, "left click selects %s" % t)
	await click(b, t)
	p.ok(s.placed_on(t) == 1, "second click places one (%d)" % s.placed_on(t))
	await click(b, t, MOUSE_BUTTON_RIGHT)
	p.ok(s.placed_on(t) == 0, "right click takes it back")
	await click(b, t)
	await click(b, t)
	s.auto_deploy()
	s.lock()
	await p.frames(5)
	gs.cinema.skip()
	await p.frames(5)
	p.ok(s.phase == Session.Phase.PLANNING, "round 1 planning")
	## find an attack: own land with an enemy / empty neighbor and someone to send
	var from := ""
	var to := ""
	for a in MapLib.player_territory_ids(s.world, "red"):
		if s.max_send(a) < 1:
			continue
		for n in MapLib.neighbors(s.map, a):
			if s.world.get_territory(n).owner != "red":
				from = a
				to = n
	p.ok(from != "", "found an attack %s -> %s" % [from, to])
	await click(b, from)
	var mv := InputEventMouseMotion.new()
	mv.position = screen(b, to)
	mv.global_position = mv.position
	vp.push_input(mv)
	await p.frames(2)
	var hov: Control = vp.gui_get_hovered_control()
	p.log("after selecting %s: selected=%s  card=%s  target at %s  hovered=%s (%s)" % [from, gs.selected, gs.land_card.get_global_rect(), screen(b, to), hov, hov.get_script().resource_path if hov and hov.get_script() else ""])
	await click(b, to)
	p.log("after clicking %s: selected=%s packets=%s phase=%s" % [to, gs.selected, s.sheet().packets.size(), s.phase])
	p.ok(s.packet_index(from, to) >= 0, "click own then enemy orders an attack")
	s.remove_packet(s.packet_index(from, to))
	await drag(b, from, to)
	p.ok(s.packet_index(from, to) >= 0, "dragging own onto enemy orders an attack")
	## surge pick through the map
	var i: int = s.packet_index(from, to)
	gs.begin_surge_pick(i)
	var surge := ""
	for n in MapLib.neighbors(s.map, to):
		if n != from and s.world.get_territory(n).owner != "red":
			surge = n
	if surge != "":
		await click(b, surge)
		p.ok((s.sheet().packets[i]).surge_to == surge, "surge target picked on the map (%s)" % surge)
	## hover card appears
	var ev := InputEventMouseMotion.new()
	ev.position = screen(b, to)
	ev.global_position = ev.position
	vp.push_input(ev)
	await p.frames(3)
	p.ok(gs._hover_tip.visible, "hovering a land shows its card")
	## zoom with the wheel keeps working
	var z0: float = b.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = screen(b, from)
	wheel.global_position = wheel.position
	vp.push_input(wheel)
	await p.frames(2)
	p.ok(b.zoom > z0, "mouse wheel zooms in")
	## a zoomed map still hit-tests correctly
	await click(b, from)
	p.ok(gs.selected == from, "clicks still land after zooming")

func screen(b: Control, id: String) -> Vector2:
	## pushed events are in window pixels; on a HiDPI screen the UI is scaled
	return vp.get_final_transform() * (b.get_global_transform_with_canvas() * b.anchor(id))

func click(b: Control, id: String, button := MOUSE_BUTTON_LEFT) -> void:
	var pos := screen(b, id)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		vp.push_input(e)
		await p.frames(1)

func drag(b: Control, a: String, c: String) -> void:
	var pa := screen(b, a)
	var pc := screen(b, c)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pa
	e.global_position = pa
	vp.push_input(e)
	await p.frames(1)
	for k in range(1, 9):
		var m := InputEventMouseMotion.new()
		m.position = pa.lerp(pc, k / 8.0)
		m.global_position = m.position
		m.relative = (pc - pa) / 8.0
		vp.push_input(m)
		await p.frames(1)
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.pressed = false
	r.position = pc
	r.global_position = pc
	vp.push_input(r)
	await p.frames(2)
