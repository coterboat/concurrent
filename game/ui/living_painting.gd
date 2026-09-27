## v1.9 a painting that breathes: a looping Ludo film (assets/video/*.ogv, first frame = the
## painting) over its still. The still shows until the film is running, and for good if there
## is no film or Settings "motion" is off. Cover-scaled like the still (the films are 1.73:1).
## Its sound (room tone, gulls, a bell) sits on the ambience bus, quiet under the music.
extends Control

const Style := preload("res://game/core/style.gd")

var still_path := ""
var video_path := ""
var volume_db := -14.0
var tint := Color.WHITE
var _still: TextureRect
var _clip: Control
var _vp: VideoStreamPlayer


func setup(p_still: String, p_video: String, p_tint: Color = Color.WHITE) -> void:
	still_path = p_still
	video_path = p_video
	tint = p_tint
	if is_inside_tree():
		_build()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_fit)
	_build()


static func has_film(path: String) -> bool:
	return path != "" and ResourceLoader.exists(path) and str(Settings.get_value("motion", "all")) != "off"


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_vp = null
	_still = TextureRect.new()
	_still.texture = Style.tex(still_path)
	_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_still.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_still.modulate = tint
	add_child(_still)
	if not has_film(video_path):
		return
	var stream: VideoStream = load(video_path)
	if stream == null:
		return
	_clip = Control.new()
	_clip.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.modulate = Color(tint, 0.0)
	add_child(_clip)
	_vp = VideoStreamPlayer.new()
	_vp.stream = stream
	_vp.expand = true
	_vp.loop = true
	_vp.volume_db = volume_db
	_vp.bus = "Ambience"
	_vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_vp)
	_vp.play()
	_fit()
	## the first frame is the painting: fade the film in over it once it's rolling
	get_tree().create_timer(0.25).timeout.connect(func():
		if is_instance_valid(_clip):
			_fit()
			create_tween().tween_property(_clip, "modulate:a", 1.0, 0.6))


func _fit() -> void:
	if _vp == null:
		return
	var vs := Vector2(1664, 960)
	var tex: Texture2D = _vp.get_video_texture()
	if tex != null and tex.get_width() > 0:
		vs = Vector2(tex.get_width(), tex.get_height())
	var k: float = maxf(size.x / vs.x, size.y / vs.y)
	_vp.size = vs * k
	_vp.position = (size - _vp.size) * 0.5


func stop() -> void:
	if _vp != null:
		_vp.stop()
