## A commander (or the advisor) in a gilded ring: face, mood, speech bubble, voice.
##   face.setup("hask", "green", "Commodore Hask")
##   face.react("win", "win")   # he laughs, "Hah! Soft as butter!" spoken
## At rest the face breathes (a Ludo idle loop); while a line is spoken the mouth moves
## (a talk loop). Both loops start and end on the portrait itself, frames crossfade at
## display rate, and a switch between loops fades over a fifth of a second: no jumps.
## v2.4: a mood plays its reaction (assets/portraits/loops/<who>_<clip>.webp, once the owner has
## accepted it in the review), from the portrait and back, then the talk loop for the rest of the
## line; a fall stays fallen. A face without an accepted reaction shows its v1.2 still and a bump.
extends Control

const Style := preload("res://game/core/style.gd")
const Lines := preload("res://game/core/lines.gd")

const MOODS := {
	"win": ["triumphant", "pleased"],
	"lose": ["angry", "alarmed"],
	"dead": ["defeated", "alarmed"],
	"alarm": ["angry", "alarmed"],
	"happy": ["triumphant", "pleased"],
	"neutral": ["", ""],
}
## v2.4: the reaction clip of each mood (the advisor's too: his win is his good news), and the lines
## that have their own
const CLIPS := {"win": "win", "happy": "win", "lose": "lose", "alarm": "lose", "dead": "dead"}
const LINE_CLIPS := {"taunt": "taunt"}

var who := "player" ## portrait/voice id: commander id, "advisor", or "player"
var pid := "" ## seat colour for the ring glow
var display_name := ""
var bubble_side := "right" ## right | left | top | bottom | none
var show_name := false
var ring_scale := 1.0
var animate := true ## idle/talk loops (off for tiny faces if ever needed)
var _view: _FaceView
var _ring: TextureRect
var _bubble: PanelContainer
var _bubble_text: Label
var _name: Label
var _mood := "neutral"
var _dead := false
var _bubble_timer := 0.0
var _talk_in := -1.0 ## seconds until the talk loop starts
var _talk_left := 0.0 ## seconds of talking left
var _revert_in := -1.0 ## seconds until an emotional face relaxes
var _clip_on := false ## v2.4: a reaction is playing (the talk waits for its end)
var _hold := false ## v2.4: the face stays on a fall's last frame
static var _mask: Shader
static var _loops := {} ## "who_kind" -> {tex, meta} or {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	if _mask == null:
		_mask = Shader.new()
		_mask.code = """shader_type canvas_item;
uniform float grey = 0.0;
uniform vec2 box = vec2(100.0);
varying vec2 lp;
varying vec4 vcol;
void vertex() {
	lp = VERTEX;
	vcol = COLOR;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV) * vcol;
	float d = distance(lp / box, vec2(0.5));
	c.a *= 1.0 - smoothstep(0.455, 0.47, d);
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(c.rgb, vec3(l) * 0.8, grey);
	COLOR = c;
}"""
	_view = _FaceView.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _mask
	_view.material = mat
	add_child(_view)
	_ring = TextureRect.new()
	_ring.texture = Style.tex("res://assets/hud/hud_ring.png")
	_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring.stretch_mode = TextureRect.STRETCH_SCALE
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)
	_name = Style.label("", 15, Style.CREAM, "bold")
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.visible = false
	add_child(_name)
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", Style.flat(Color(0.96, 0.92, 0.82, 0.97), Color(0.45, 0.3, 0.1), 2, 10, 12))
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	_bubble.top_level = true
	_bubble.z_index = 50
	_bubble_text = Style.label("", 17, Color(0.12, 0.08, 0.05), "italic")
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.custom_minimum_size = Vector2(220, 0)
	_bubble.add_child(_bubble_text)
	add_child(_bubble)
	resized.connect(_layout)
	_apply()
	_layout()


func setup(p_who: String, p_pid: String, p_name: String) -> void:
	who = p_who if p_who != "" else "player"
	pid = p_pid
	display_name = p_name
	_mood = "neutral"
	_dead = false
	_talk_in = -1.0
	_talk_left = 0.0
	_revert_in = -1.0
	_clip_on = false
	_hold = false
	if is_inside_tree():
		_apply()
		_layout()


func set_dead(dead: bool) -> void:
	if dead and _dead and _mood == "dead":
		return ## the roster says so every refresh: the face is already down
	_dead = dead
	if _view and _view.material:
		(_view.material as ShaderMaterial).set_shader_parameter("grey", 0.85 if dead else 0.0)
	if dead:
		_talk_in = -1.0
		_talk_left = 0.0
		_revert_in = -1.0
		_set_mood("dead")
	elif _mood == "dead":
		_set_mood("neutral")


func _layout() -> void:
	var s: float = minf(size.x, size.y)
	var r := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
	var inner: float = s * 0.72
	_view.position = r.position + Vector2(s - inner, s - inner) * 0.5
	_view.size = Vector2(inner, inner)
	if _view.material:
		(_view.material as ShaderMaterial).set_shader_parameter("box", _view.size)
	var rs: float = s * ring_scale
	_ring.position = r.position + Vector2(s - rs, s - rs) * 0.5
	_ring.size = Vector2(rs, rs)
	_name.visible = show_name
	_name.text = display_name
	_name.position = Vector2(0, s - 4)
	_name.size = Vector2(size.x, 20)
	pivot_offset = size * 0.5


func _apply() -> void:
	if _view == null:
		return
	_view.tint = Style.seat_color(pid) if pid != "" and pid != "neutral" else Color(0.55, 0.42, 0.22)
	_set_mood(_mood)
	var glow: Color = Style.seat_color(pid) if pid != "" else Style.GOLD
	_ring.modulate = Color(1, 1, 1).lerp(glow.lightened(0.4), 0.18)


static func loop_for(p_who: String, kind: String) -> Dictionary:
	## {tex, meta} for a portrait loop, or {} when there is none.
	var key: String = p_who + "_" + kind
	if _loops.has(key):
		return _loops[key]
	var out := {}
	var base: String = "res://assets/portraits/loops/%s" % key
	var t: Texture2D = Style.tex(base + ".webp")
	if t != null and FileAccess.file_exists(base + ".json"):
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
		if typeof(meta) == TYPE_DICTIONARY:
			out = {"tex": t, "meta": meta}
	_loops[key] = out
	return out


static func still_for(p_who: String, suffix: String = "") -> Texture2D:
	var name: String = p_who if suffix == "" else "%s_%s" % [p_who, suffix]
	var t: Texture2D = Style.portrait(name)
	if t == null and suffix != "":
		t = Style.portrait(p_who)
	if t == null:
		t = Style.portrait("player")
	return t


static func clip_for(p_who: String, mood: String, line_key: String = "") -> Dictionary:
	## v2.4: the accepted reaction for a mood, or for a line that has its own (the taunt); {} when
	## there is none yet, and the face shows its still instead
	if LINE_CLIPS.has(line_key):
		var own: Dictionary = loop_for(p_who, str(LINE_CLIPS[line_key]))
		if not own.is_empty():
			return own
	return loop_for(p_who, str(CLIPS[mood])) if CLIPS.has(mood) else {}


static func clip_secs(clip: Dictionary) -> float:
	## how long a reaction takes to reach its last frame
	var meta: Dictionary = clip.get("meta", {})
	var order: Array = meta.get("order", [])
	var n: int = order.size() if not order.is_empty() else int(meta.get("frames", 1))
	return float(maxi(n - 1, 1)) / float(meta.get("fps", _FaceView.FPS))


func _set_mood(m: String) -> void:
	_mood = m
	_clip_on = false
	_hold = false
	var variants: Array = MOODS.get(m, ["", ""])
	var suffix: String = str(variants[1] if who == "advisor" else variants[0])
	if suffix == "" and animate and not _dead:
		var idle: Dictionary = loop_for(who, "idle")
		if not idle.is_empty():
			_view.play(idle, still_for(who))
			return
	if m == "dead" and animate:
		## v2.4: fallen is a fall's last frame, once a fall is accepted
		var fall: Dictionary = clip_for(who, "dead")
		if not fall.is_empty() and bool(fall["meta"].get("hold", false)):
			_hold = true
			_view.play(fall, still_for(who), true, true)
			return
	_view.show_still(still_for(who, suffix))


func _play_clip(mood: String, clip: Dictionary) -> void:
	_mood = mood
	_clip_on = true
	_hold = bool(clip["meta"].get("hold", false))
	_talk_in = -1.0
	_talk_left = 0.0
	_revert_in = -1.0
	_view.play(clip, still_for(who), true)


func react(mood: String, line_key: String = "", hold: float = 2.8, speak: bool = true) -> float:
	## Show the reaction, the line, speak it. Returns seconds of speech.
	if _dead and mood != "dead":
		mood = "dead"
	## v2.4: an accepted reaction plays (not on a face already down: that one stays down)
	var clip: Dictionary = clip_for(who, mood, line_key) if animate and not _dead else {}
	if not clip.is_empty():
		_play_clip(mood, clip)
		if _hold:
			## the colour drains as the head goes down
			var fade := create_tween()
			fade.tween_property(self, "scale", Vector2(0.94, 0.94), clip_secs(clip))
			fade.parallel().tween_property(self, "modulate", Color(0.75, 0.75, 0.78), clip_secs(clip))
	else:
		_set_mood(mood)
		var tw := create_tween()
		match mood:
			"win", "happy":
				tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.12).set_trans(Tween.TRANS_BACK)
				tw.tween_property(self, "scale", Vector2.ONE, 0.25)
			"lose", "alarm":
				for i in 4:
					tw.tween_property(self, "rotation", 0.07 * (1 if i % 2 == 0 else -1), 0.05)
				tw.tween_property(self, "rotation", 0.0, 0.05)
			"dead":
				tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.4)
				tw.parallel().tween_property(self, "modulate", Color(0.75, 0.75, 0.78), 0.4)
			_:
				tw.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1)
				tw.tween_property(self, "scale", Vector2.ONE, 0.15)
	var text: String = Lines.text(who, line_key) if line_key != "" else ""
	var secs := 0.0
	if text != "":
		if speak:
			## v1.10: if someone is still speaking, this line waits its turn (bubble and all)
			var m0: String = mood
			secs = Audio.voice(Lines.voice_path(who, line_key), false, func(s2: float):
				if is_instance_valid(self):
					say_text(text, hold)
					if _hold:
						return ## a fallen face says its last words without moving
					## v2.4: a reaction still playing finishes first, then the mouth moves
					_talk_in = -1.0 if _clip_on else 0.0
					_talk_left = s2
					_revert_in = -1.0 if m0 == "neutral" else s2 + 0.4)
			if secs < 0.0:
				if _clip_on:
					return 0.0 ## the reaction plays now; the line, when its turn comes
				## queued: the face keeps its mood a while; if the line never gets its turn it lapses
				_talk_in = -1.0
				_revert_in = hold if mood != "neutral" else -1.0
				return 0.0
		say_text(text, hold)
	if _clip_on:
		## the line runs while the reaction plays; whatever is left of it, the talk loop says
		_talk_left = 0.0 if _hold else secs
		return secs
	if mood == "dead":
		_talk_in = -1.0
		_revert_in = -1.0
		return secs
	## the reaction shows first, then the mouth moves for the rest of the line
	if secs > 0.0:
		_talk_in = 0.0 if mood == "neutral" else minf(1.0, secs * 0.35)
		_talk_left = secs - _talk_in
		_revert_in = -1.0
	else:
		_talk_in = -1.0
		_revert_in = hold if mood != "neutral" else -1.0
	return secs


func say_text(text: String, hold: float = 2.8) -> void:
	if bubble_side == "none" or text == "":
		return
	_bubble_text.text = "“%s”" % text
	_bubble.visible = true
	_bubble.reset_size()
	var gp: Vector2 = get_global_rect().position
	var gs: Vector2 = get_global_rect().size
	var bs: Vector2 = _bubble.size
	match bubble_side:
		"left":
			_bubble.global_position = gp + Vector2(-bs.x - 10, gs.y * 0.5 - bs.y * 0.5)
		"top":
			_bubble.global_position = gp + Vector2(gs.x * 0.5 - bs.x * 0.5, -bs.y - 8)
		"bottom":
			_bubble.global_position = gp + Vector2(gs.x * 0.5 - bs.x * 0.5, gs.y + 8)
		_:
			_bubble.global_position = gp + Vector2(gs.x + 10, gs.y * 0.5 - bs.y * 0.5)
	var vp: Vector2 = get_viewport_rect().size
	_bubble.global_position = _bubble.global_position.clamp(Vector2(6, 6), vp - bs - Vector2(6, 6))
	_bubble.modulate.a = 0.0
	create_tween().tween_property(_bubble, "modulate:a", 1.0, 0.15)
	_bubble_timer = hold


func hush() -> void:
	_bubble.visible = false
	_bubble_timer = 0.0
	if _hold:
		return ## a fall stays down
	if _clip_on or _talk_left > 0.0 or _talk_in >= 0.0: ## v2.4: a reaction stops with the talking
		_clip_on = false
		_talk_in = -1.0
		_talk_left = 0.0
		if not _dead:
			_set_mood("neutral")


func _process(delta: float) -> void:
	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			var tw := create_tween()
			tw.tween_property(_bubble, "modulate:a", 0.0, 0.3)
			tw.tween_callback(func(): _bubble.visible = false)
	if _dead:
		return
	if _clip_on:
		## v2.4: a reaction plays to its end while its line counts down, then the talk loop says
		## what is left of the line, or the face is at rest again (a fall stays down)
		_talk_left = maxf(0.0, _talk_left - delta)
		if not _view.done():
			return
		_clip_on = false
		if _hold:
			return
		var talk: Dictionary = loop_for(who, "talk") if animate and _talk_left > 0.25 else {}
		if not talk.is_empty():
			_mood = "neutral"
			_view.play(talk, still_for(who))
		else:
			_talk_left = 0.0
			_set_mood("neutral")
		return
	if _hold:
		return
	if _talk_in >= 0.0:
		_talk_in -= delta
		if _talk_in < 0.0:
			var talk: Dictionary = loop_for(who, "talk") if animate else {}
			if not talk.is_empty():
				_mood = "neutral"
				_view.play(talk, still_for(who))
			_talk_in = -1.0
	elif _talk_left > 0.0:
		_talk_left -= delta
		if _talk_left <= 0.0:
			_set_mood("neutral")
	elif _revert_in >= 0.0:
		_revert_in -= delta
		if _revert_in < 0.0:
			_set_mood("neutral")


## The face itself: a still, or a loop whose frames crossfade at display rate.
class _FaceView extends Control:
	const FPS := 8.0
	var tint := Color(0.55, 0.42, 0.22)
	var _still: Texture2D
	var _sheet: Texture2D
	var _meta := {}
	var _t := 0.0
	var _once := false ## v2.4: a reaction, played once to its last frame (where it stays)
	## what was on screen before a switch, faded out on top of the new face
	var _old_tex: Texture2D
	var _old_src := Rect2()
	var _old_size := Vector2.ONE
	var _fade := 0.0
	static var _glow: GradientTexture2D

	func show_still(t: Texture2D) -> void:
		if t == _still and _sheet == null:
			return
		_remember()
		_sheet = null
		_once = false
		_still = t
		queue_redraw()

	func play(loop: Dictionary, still: Texture2D, once := false, at_end := false) -> void:
		## a loop already playing plays on; a reaction (once) starts over, or shows its last frame
		if loop.get("tex") == _sheet and _sheet != null and not once and not _once:
			return
		_remember()
		_sheet = loop["tex"]
		_meta = loop["meta"]
		_still = still
		_once = once
		_t = float(_count() - 1) / _fps() if at_end else 0.0
		queue_redraw()

	func done() -> bool:
		## a reaction that has reached its last frame
		return _once and _sheet != null and _t * _fps() >= float(_count() - 1)

	func showing() -> Texture2D:
		## the sheet playing, or the still when none is (the probes ask)
		return _sheet if _sheet != null else _still

	func _count() -> int:
		var order: Array = _meta.get("order", [])
		return order.size() if not order.is_empty() else int(_meta.get("frames", 1))

	func _fps() -> float:
		return float(_meta.get("fps", FPS)) ## v1.9: a loop may carry its own rate (the Hydra talk loops)

	func _pos() -> Array:
		## [the frame showing, the next one fading in over it, how far in]; a reaction stops on its last
		var order: Array = _meta.get("order", [])
		var n: int = _count()
		var ft: float = _t * _fps()
		var i: int = int(ft) % n
		var j: int = (i + 1) % n
		if _once:
			ft = minf(ft, float(n - 1))
			i = int(ft)
			j = mini(i + 1, n - 1)
		if not order.is_empty():
			i = int(order[i])
			j = int(order[j])
		return [i, j, ft - floorf(ft)]

	func _remember() -> void:
		## snapshot the frame showing now so the switch can fade instead of jump
		if _sheet != null:
			_old_tex = _sheet
			_old_src = _frame(int(_pos()[0]))
			_old_size = Vector2(float(_meta["fw"]), float(_meta["fh"]))
		elif _still != null:
			_old_tex = _still
			_old_src = Rect2(Vector2.ZERO, _still.get_size())
			_old_size = _still.get_size()
		else:
			return
		_fade = 1.0

	func _frame(i: int) -> Rect2:
		var cols: int = int(_meta.get("cols", 4))
		var fw: float = float(_meta["fw"])
		var fh: float = float(_meta["fh"])
		return Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)

	func _cover(sz: Vector2) -> Rect2:
		var sc: float = maxf(size.x / maxf(sz.x, 1.0), size.y / maxf(sz.y, 1.0))
		var d: Vector2 = sz * sc
		return Rect2((size - d) * 0.5, d)

	func _process(delta: float) -> void:
		if (_sheet != null and not done()) or _fade > 0.0:
			_t += delta
			_fade = maxf(0.0, _fade - delta * 5.0)
			queue_redraw()

	func _draw() -> void:
		if _glow == null:
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(0.18, 0.18, 0.2, 1))
			_glow = GradientTexture2D.new()
			_glow.gradient = g
			_glow.fill = GradientTexture2D.FILL_RADIAL
			_glow.fill_from = Vector2(0.5, 0.42)
			_glow.fill_to = Vector2(1.0, 1.0)
			_glow.width = 128
			_glow.height = 128
		## a lamp-lit backdrop in the seat's colour, so silhouettes and cut-outs read
		draw_texture_rect(_glow, Rect2(Vector2.ZERO, size), false, tint.darkened(0.35).lerp(Color(0.35, 0.22, 0.1), 0.35))
		if _sheet != null:
			var at: Array = _pos()
			var r: Rect2 = _cover(Vector2(float(_meta["fw"]), float(_meta["fh"])))
			draw_texture_rect_region(_sheet, r, _frame(int(at[0])))
			draw_texture_rect_region(_sheet, r, _frame(int(at[1])), Color(1, 1, 1, float(at[2])))
		elif _still != null:
			draw_texture_rect(_still, _cover(_still.get_size()), false)
		if _fade > 0.0 and _old_tex != null:
			draw_texture_rect_region(_old_tex, _cover(_old_size), _old_src, Color(1, 1, 1, _fade))
