## v1.9 cutscenes: a few seconds of film (assets/video/cut_<name>.ogv, made with Ludo from our
## own paintings and portraits) at the war's big moments: a capital taken or lost, a rival
## wiped out, victory, defeat, and the dawn the war begins. The films carry music and battle
## sound but no speech: the advisor speaks over them in his own voice (game/data/lines.json).
## Any key or click skips. Off with Settings "motion" (Films: Living paintings only / Still).
extends Control

const Style := preload("res://game/core/style.gd")
const Lines := preload("res://game/core/lines.gd")

signal done

var _vp: VideoStreamPlayer
var _caption: Label
var _hint: Label
var _bars: Array = []
var _open := false
var _started := 0


static func path_of(kind: String) -> String:
	return "res://assets/video/cut_%s.ogv" % kind


static func available(kind: String) -> bool:
	return str(Settings.get_value("motion", "all")) == "all" and ResourceLoader.exists(path_of(kind))


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	_vp = VideoStreamPlayer.new()
	_vp.expand = true
	_vp.bus = "SFX"
	_vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vp)
	_vp.finished.connect(func(): _close())
	## letterbox bars that slide in, and the caption on the lower one
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	_caption = Style.label("", 30, Style.CREAM, "display")
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_hint = Style.label("Space or click: skip", 14, Color(Style.MUTED, 0.8), "italic")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	resized.connect(_fit)


func play(kind: String, caption: String = "", voice_who: String = "advisor", voice_key: String = "") -> bool:
	## Returns false (and emits nothing) when there is no film for this moment.
	if not available(kind):
		return false
	var stream: VideoStream = load(path_of(kind))
	if stream == null:
		return false
	_vp.stream = stream
	_caption.text = caption
	visible = true
	_open = true
	_started = Time.get_ticks_msec()
	modulate.a = 0.0
	_fit()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)
	_vp.play()
	Audio._duck(true)
	_vp.volume_db = -5.0 if voice_key != "" else 0.0 ## the film sits a little under the advisor's line
	if voice_key != "" and Lines.has(voice_who, voice_key):
		## the line lands a beat into the shot
		get_tree().create_timer(0.9).timeout.connect(func():
			if _open:
				Audio.voice(Lines.voice_path(voice_who, voice_key), true))
	return true


func _fit() -> void:
	if _vp == null:
		return
	var vs := Vector2(16, 9)
	var tex: Texture2D = _vp.get_video_texture()
	if tex != null and tex.get_width() > 0:
		vs = Vector2(tex.get_width(), tex.get_height())
	var k: float = minf(size.x / vs.x, size.y / vs.y)
	_vp.size = vs * k
	_vp.position = (size - _vp.size) * 0.5
	var bar_h: float = maxf(size.y * 0.08, (size.y - _vp.size.y) * 0.5)
	(_bars[0] as ColorRect).position = Vector2.ZERO
	(_bars[0] as ColorRect).size = Vector2(size.x, bar_h)
	(_bars[1] as ColorRect).position = Vector2(0, size.y - bar_h)
	(_bars[1] as ColorRect).size = Vector2(size.x, bar_h)
	_caption.position = Vector2(0, size.y - bar_h + (bar_h - 44) * 0.5)
	_caption.size = Vector2(size.x, 44)
	_hint.position = Vector2(size.x - 320, size.y - 26)
	_hint.size = Vector2(300, 20)


func _gui_input(e: InputEvent) -> void:
	if _open and e is InputEventMouseButton and e.pressed:
		skip()
		accept_event()


func _unhandled_input(e: InputEvent) -> void:
	if _open and e is InputEventKey and e.pressed and not e.echo and not Style.is_fullscreen_key(e):
		skip()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open:
		_fit()
		if Time.get_ticks_msec() - _started > 20000:
			_close() ## a stuck stream never holds the game


func skip() -> void:
	if Time.get_ticks_msec() - _started < 350:
		return ## the click that started things isn't a skip
	_close()


func _close() -> void:
	if not _open:
		return
	_open = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		_vp.stop()
		visible = false
		Audio._duck(false)
		done.emit())
