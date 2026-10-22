## v2.4 faces: reactions that move. An accepted reaction (assets/portraits/loops/<who>_<clip>.webp)
## plays once, from the portrait and back to the idle loop, and the talk loop says whatever is left
## of its line; a fall stays fallen and greys; a face with no accepted reaction shows its v1.2 still
## and bump, as before. The review batch's takes are not in the game until the owner keeps them, so
## this probe stands in reactions cut from the talk loops for the moments, and checks every
## installed one for what the face needs.
##   SHOT_DIR=/dir ./scripts/shot.sh v24f
extends RefCounted

const LeaderFace := preload("res://game/ui/leader_face.gd")
const Style := preload("res://game/core/style.gd")

const CAST := ["advisor", "varek", "ysolde", "quill", "oren", "hask", "imre"]
const PLAYERS := ["you_ironduke", "you_corsair", "you_lioness", "you_scholar", "you_rajah", "you_grenadier"]

var p
var stage: Control
var _stood_in: Array = []


func run(probe) -> void:
	p = probe
	p.get_window().size = Vector2i(1440, 900)
	for k in ["music", "sfx", "ambience"]:
		Settings.data[k] = 0.0
	## a line has to report its length (the talk loop follows a reaction for the rest of it), so
	## voices are on, and their bus muted
	Settings.data["voices"] = 0.6
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Voice"), true)
	Settings.data["speed"] = "fast"
	p.steady(true)
	stage = Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.size = Vector2(1440, 900)
	p.get_tree().root.add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.12, 0.09)
	bg.size = Vector2(1440, 900)
	stage.add_child(bg)
	await p.frames(3)

	await installed()
	await fallback()
	await reactions()
	await falls()
	stage.queue_free()
	await p.frames(2)
	await in_game()
	for k in _stood_in:
		LeaderFace._loops.erase(k)
	p.log("v24f probe done")


## ---------------------------------------------------------------- what is installed
func installed() -> void:
	## every face has something for every mood: an accepted reaction it can play, or its still
	var reactions := 0
	var bad: Array = []
	for who in CAST + PLAYERS:
		var clips: Array = ["win", "lose", "dead"] + (["taunt"] if who != "advisor" and not str(who).begins_with("you_") else [])
		for c in clips:
			var clip: Dictionary = LeaderFace.loop_for(who, c)
			if not clip.is_empty():
				reactions += 1
				var m: Dictionary = clip["meta"]
				var holds: bool = bool(m.get("hold", false))
				if not bool(m.get("once", false)) or int(m.get("frames", 0)) < 2 or float(m.get("fps", 0)) <= 0.0 \
						or int(m.get("fw", 0)) != 256 or holds != (c == "dead" and who != "advisor"):
					bad.append("%s_%s %s" % [who, c, m])
				continue
			var mood: String = {"win": "win", "lose": "lose", "dead": "dead", "taunt": "win"}[c]
			var suffix: String = str(LeaderFace.MOODS[mood][1 if who == "advisor" else 0])
			if Style.portrait("%s_%s" % [who, suffix]) == null:
				bad.append("%s has neither a %s reaction nor its %s still" % [who, c, suffix])
	p.ok(bad.is_empty(), "every face has a reaction or its still for every mood (%d reactions installed) %s" % [reactions, bad])
	## the moods the callers use all lead somewhere
	var moods_ok := true
	for m in ["win", "happy", "lose", "alarm", "dead"]:
		moods_ok = moods_ok and LeaderFace.CLIPS.has(m) and LeaderFace.MOODS.has(m)
	p.ok(moods_ok and LeaderFace.LINE_CLIPS.get("taunt", "") == "taunt", "win, happy, lose, alarm and dead each have a reaction, and the taunt its own")


## ---------------------------------------------------------------- no reaction: today's still
func fallback() -> void:
	var f: Control = face("ysolde", "red", 170, Vector2(120, 140), "none", "Ysolde wins, no reaction: her v1.2 still")
	await p.frames(4)
	LeaderFace._loops["ysolde_win"] = {} ## whatever is installed, this face has no win reaction
	_stood_in.append("ysolde_win")
	var idle: Texture2D = LeaderFace.loop_for("ysolde", "idle")["tex"]
	p.ok(f._view.showing() == idle, "at rest, Ysolde breathes (her idle loop)")
	LeaderFace.still_for("ysolde", "triumphant") ## loaded now: a first load stalls a frame past the bump
	await p.frames(2)
	f.react("win", "", 1.2)
	var peak := 1.0
	for i in 30:
		await p.frames(1)
		peak = maxf(peak, f.scale.x)
		if i == 15:
			p.ok(f._view.showing() == LeaderFace.still_for("ysolde", "triumphant") and not f._clip_on,
				"without a reaction, a win still shows her triumphant still")
			await snap("01_fallback_still")
	p.ok(peak > 1.01, "...and the bump (scale up to %.2f)" % peak)
	var back: bool = await until(func(): return f._view.showing() == idle, 240)
	p.ok(back, "...and she relaxes into her idle loop after it")
	f.queue_free()


## ---------------------------------------------------------------- an accepted reaction plays
func reactions() -> void:
	var v: Control = face("varek", "blue", 170, Vector2(120, 140), "right", "Varek: his win reaction (stand-in)")
	var h: Control = face("hask", "green", 120, Vector2(620, 160), "right", "Hask loses, no reaction: his still")
	var a: Control = face("advisor", "", 120, Vector2(1000, 160), "left", "the advisor's warning (stand-in)")
	var y: Control = face("you_lioness", "red", 64, Vector2(660, 420), "none", "your face wins (stand-in)")
	await p.frames(4)
	var win: Dictionary = stand_in("varek", "win")
	var idle: Texture2D = LeaderFace.loop_for("varek", "idle")["tex"]
	var talk: Texture2D = LeaderFace.loop_for("varek", "talk")["tex"]
	v.react("win")
	await p.frames(3)
	p.ok(v._view.showing() == win["tex"] and v._view._once and v._clip_on,
		"with an accepted reaction, a win plays it (once), not the old still")
	p.ok(absf(v.scale.x - 1.0) < 0.001 and absf(v.rotation) < 0.001, "...and the old bump stays out of it")
	h.react("lose") ## no reaction for Hask's loss: his still
	stand_in("advisor", "lose")
	a.react("alarm")
	stand_in("you_lioness", "win")
	y.react("win")
	await p.frames(12)
	await snap("02_reactions_playing")
	p.ok(a._view.showing() == LeaderFace.loop_for("advisor", "lose")["tex"], "the advisor's alarm plays his warning")
	p.ok(y._view.showing() == LeaderFace.loop_for("you_lioness", "win")["tex"], "the player's own face plays its win (no voice)")
	var secs: float = LeaderFace.clip_secs(win)
	var back: bool = await until(func(): return not v._clip_on, int(secs * 60.0) + 90)
	await p.frames(2)
	p.ok(back and v._view.showing() == idle, "...and when it ends Varek is back in his idle loop (%.1f s)" % secs)
	await until(func(): return not a._clip_on and not y._clip_on, 240)
	await until(func(): return a._view.showing() == LeaderFace.loop_for("advisor", "idle")["tex"], 400)
	p.ok(a._view.showing() == LeaderFace.loop_for("advisor", "idle")["tex"]
		and y._view.showing() == LeaderFace.loop_for("you_lioness", "idle")["tex"], "the advisor and the player's face come back to rest too")
	await snap("03_back_at_rest")

	## a long line: the reaction first, then the talk loop for the rest of it, then rest
	Audio.skip_voice()
	var said: float = v.react("happy", "greet", 3.0)
	await p.frames(3)
	p.ok(said > secs + 0.5, "Varek's greeting outlasts his reaction (%.1f s against %.1f s)" % [said, secs])
	p.ok(v._view.showing() == win["tex"], "a greeting (happy) plays his win reaction")
	var talked: bool = await until(func(): return v._view.showing() == talk, int(secs * 60.0) + 90)
	p.ok(talked and not v._clip_on, "...then his mouth moves for the rest of the line (the talk loop)")
	await snap("04_talk_after_reaction")
	var rested: bool = await until(func(): return v._view.showing() == idle, int(said * 60.0) + 120)
	p.ok(rested, "...then he is at rest")

	## the taunt: its own reaction when there is one, else the win's
	Audio.skip_voice()
	v.react("win", "taunt", 3.0)
	await p.frames(3)
	p.ok(v._view.showing() == win["tex"], "with no taunt of his own, a taunt plays Varek's win")
	await until(func(): return not v._clip_on, int(secs * 60.0) + 90)
	Audio.skip_voice()
	var taunt: Dictionary = stand_in("varek", "taunt")
	v.react("win", "taunt", 3.0)
	await p.frames(3)
	p.ok(v._view.showing() == taunt["tex"], "with one, the taunt plays its own reaction")
	await p.frames(6)
	v.hush() ## the battle closes
	await p.frames(2)
	p.ok(not v._clip_on and v._view.showing() == idle, "a battle closing (hush) stops a reaction: he is at rest")

	## a line that has to wait its turn: the reaction plays now all the same
	Audio.skip_voice()
	a.react("happy", "capture", 3.0)
	await p.frames(2)
	stand_in("hask", "win")
	var queued: float = h.react("win", "win", 2.6)
	await p.frames(3)
	p.ok(queued == 0.0 and h._view.showing() == LeaderFace.loop_for("hask", "win")["tex"],
		"a line still waiting its turn doesn't hold the reaction back (Hask laughs while the advisor speaks)")
	Audio.skip_voice()
	for f in [v, h, a, y]:
		f.queue_free()
	await p.frames(2)


## ---------------------------------------------------------------- a fall stays down
func falls() -> void:
	var q: Control = face("quill", "yellow", 170, Vector2(120, 140), "none", "Quill falls and stays down")
	var r: Control = face("quill", "yellow", 44, Vector2(560, 200), "none", "roster: down, then back")
	var k: Control = face("hask", "green", 44, Vector2(800, 200), "none", "no fall: defeated still")
	await p.frames(4)
	var fall: Dictionary = stand_in("quill", "dead", true)
	q.react("dead", "eliminated", 3.5)
	await p.frames(3)
	p.ok(q._view.showing() == fall["tex"] and q._hold, "knocked out, Quill plays his fall")
	var secs: float = LeaderFace.clip_secs(fall)
	await p.frames(int(secs * 60.0) + 70)
	p.ok(q._view.showing() == fall["tex"] and q._view.done(), "...and stays on its last frame (not back to rest)")
	p.ok(q.modulate.r < 0.8 and q.scale.x < 0.97, "...his colour drained and his ring sunk (%.2f, %.2f)" % [q.modulate.r, q.scale.x])
	r.set_dead(true)
	await p.frames(2)
	p.ok(r._view.showing() == fall["tex"] and r._view.done(), "in the roster a fallen face shows the fall's last frame at once")
	p.ok(is_equal_approx(float((r._view.material as ShaderMaterial).get_shader_parameter("grey")), 0.85), "...in grey")
	LeaderFace._loops["hask_dead"] = {} ## whatever is installed: a face with no fall
	_stood_in.append("hask_dead")
	k.set_dead(true)
	await p.frames(2)
	p.ok(k._view.showing() == LeaderFace.still_for("hask", "defeated"), "a face with no fall shows its defeated still, as before")
	r.set_dead(false)
	await p.frames(2)
	p.ok(r._view.showing() == LeaderFace.loop_for("quill", "idle")["tex"], "a face brought back breathes again")
	await snap("05_fallen")
	for f in [q, r, k]:
		f.queue_free()
	await p.frames(2)


## ---------------------------------------------------------------- in the war
func in_game() -> void:
	var main: Control = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	main.start_game({"map": "res://maps/marches18.json", "seed": 41, "length": "standard", "timer": 0, "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "you_lioness"},
		{"id": "blue", "name": "Commodore Hask", "kind": "ai", "ai": "hask", "portrait": "hask"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
	await p.frames(8)
	var gs: Control = main.current
	## (the commanders' introductions, wherever they are shown, are not what this looks at)
	var intro: Variant = gs.get("intro")
	if intro is Node and is_instance_valid(intro) and intro.has_method("_done"):
		intro._done()
	await p.frames(10)
	Audio.skip_voice()
	var taunt: Dictionary = stand_in("hask", "taunt")
	var hf: Control = gs.roster.faces["blue"]
	var qf: Control = gs.roster.faces["green"]
	LeaderFace._loops["quill_win"] = {}
	_stood_in.append("quill_win")
	LeaderFace.still_for("quill", "triumphant")
	hf.react("win", "taunt", 3.0)
	qf.react("win")
	await p.frames(3)
	p.ok(hf._view.showing() == taunt["tex"], "in the war, Hask's taunt plays on his roster face")
	p.ok(qf._view.showing() == LeaderFace.still_for("quill", "triumphant"), "...and Quill, with no reaction, shows his still")
	await p.frames(7)
	await snap("06_roster_taunt")
	var back: bool = await until(func(): return not hf._clip_on and not hf._talk_left > 0.0, 600)
	p.ok(back, "...and Hask's face comes back to rest")
	Audio.skip_voice()
	main.queue_free()
	await p.frames(3)


## ---------------------------------------------------------------- helpers
func face(who: String, pid: String, px: float, pos: Vector2, bubble := "none", says := "") -> Control:
	var f: Control = LeaderFace.new()
	f.bubble_side = bubble
	f.setup(who, pid, who.capitalize())
	f.position = pos
	f.size = Vector2(px, px)
	f.custom_minimum_size = Vector2(px, px)
	stage.add_child(f)
	## what the shot shows, under the face
	var l := Style.label(says if says != "" else who.capitalize(), 15, Style.CREAM, "italic")
	l.position = pos + Vector2(-40, px + 6)
	l.size = Vector2(px + 80, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(l)
	f.tree_exited.connect(l.queue_free)
	return f


func stand_in(who: String, clip: String, hold := false) -> Dictionary:
	## a reaction cut from the face's own talk (or idle) loop, as its own texture, played once quickly
	var src: Dictionary = LeaderFace.loop_for(who, "talk")
	if src.is_empty():
		src = LeaderFace.loop_for(who, "idle")
	var meta: Dictionary = (src["meta"] as Dictionary).duplicate()
	meta.erase("order")
	meta["fps"] = 24.0
	meta["once"] = true
	if hold:
		meta["hold"] = true
	var tex := ImageTexture.create_from_image((src["tex"] as Texture2D).get_image())
	var out := {"tex": tex, "meta": meta}
	LeaderFace._loops["%s_%s" % [who, clip]] = out
	_stood_in.append("%s_%s" % [who, clip])
	return out


func until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await p.frames(1)
	return cond.call()


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")
	p.log("shot " + name)
