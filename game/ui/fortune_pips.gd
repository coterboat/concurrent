## v1.9 Fortune at a glance: a commander's favours as stars (lit: held; dark sockets: room
## for more, up to three). The next socket fills with gold from the bottom as the dice owe
## you more, so the next favour's progress is on the star itself (show_bar adds a bar too).
##   ready: they can call on her right now (the lit stars breathe and glow)
##   spent: they already called on her in this battle (the stars go dim, "called")
## The art is assets/hud/fortune_star.png and fortune_empty.png; drawn stars stand in without it.
extends Control

const Style := preload("res://game/core/style.gd")

var held := 0
var most := 3
var share := 0.0 ## 0..1 of the way to the next favour
var callable := false
var spent := false
var show_bar := false
var star_px := 18.0
var align := 0.5 ## 0 left, 0.5 centre, 1 right
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_state(p_held: int, p_share: float, p_ready: bool = false, p_spent: bool = false) -> void:
	if p_held == held and is_equal_approx(p_share, share) and p_ready == callable and p_spent == spent:
		return
	var gained: bool = p_held > held
	held = p_held
	share = clampf(p_share, 0.0, 1.0)
	callable = p_ready
	spent = p_spent
	if gained and is_inside_tree():
		## a favour banked: the new star pops
		pivot_offset = size * 0.5
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.35, 1.35), 0.14)
		tw.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _process(delta: float) -> void:
	if callable and held > 0:
		_t += delta
		queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(most * star_px + (most - 1) * star_px * 0.22, star_px + (7.0 if show_bar else 0.0))


func _draw() -> void:
	var full: Texture2D = Style.tex("res://assets/hud/fortune_star.png")
	var hollow: Texture2D = Style.tex("res://assets/hud/fortune_empty.png")
	var gap: float = star_px * 0.22
	var total: float = most * star_px + (most - 1) * gap
	var x0: float = (size.x - total) * align
	var y0: float = 0.0
	var breathe: float = 0.5 + 0.5 * sin(_t * 4.0) if callable else 0.0
	for i in most:
		var c := Vector2(x0 + i * (star_px + gap) + star_px * 0.5, y0 + star_px * 0.5)
		var lit: bool = i < held
		if lit:
			var a: float = 0.35 if spent else 1.0
			if callable and not spent:
				for k in 3:
					draw_circle(c, star_px * (0.7 + 0.22 * k) * (1.0 + 0.12 * breathe), Color(1.0, 0.82, 0.35, (0.1 + 0.08 * breathe) * (1.0 - 0.25 * k)))
			if full != null:
				draw_texture_rect(full, Rect2(c - Vector2.ONE * star_px * 0.62, Vector2.ONE * star_px * 1.24), false, Color(1, 1, 1, a))
			else:
				Style.draw_shape(self, "star", c, star_px * 0.52, Color(Style.GOLD.lightened(0.15), a), Color(0.25, 0.14, 0.02, a), 1.4)
		else:
			if hollow != null:
				draw_texture_rect(hollow, Rect2(c - Vector2.ONE * star_px * 0.55, Vector2.ONE * star_px * 1.1), false, Color(1, 1, 1, 0.55))
			else:
				Style.draw_shape(self, "star", c, star_px * 0.46, Color(0.1, 0.08, 0.06, 0.55), Color(0.62, 0.55, 0.42, 0.6), 1.2)
			if i == held and share > 0.02:
				## the next favour, filling from the bottom
				if full != null:
					var dst := Rect2(c - Vector2.ONE * star_px * 0.62, Vector2.ONE * star_px * 1.24)
					var cut: float = dst.size.y * (1.0 - share)
					var tw: float = float(full.get_width())
					var th: float = float(full.get_height())
					draw_texture_rect_region(full, Rect2(dst.position + Vector2(0, cut), Vector2(dst.size.x, dst.size.y - cut)),
						Rect2(0, th * (1.0 - share), tw, th * share), Color(1, 1, 1, 0.8))
				else:
					Style.draw_shape(self, "star", c, star_px * 0.46 * share, Color(Style.GOLD, 0.7), Color(0, 0, 0, 0), 0.0)
	if show_bar:
		## the way to the next favour (full at three in hand: nothing more to bank)
		var by: float = y0 + star_px + 3.0
		var bw: float = total
		draw_rect(Rect2(Vector2(x0, by), Vector2(bw, 3.5)), Color(0, 0, 0, 0.55))
		if held < most:
			draw_rect(Rect2(Vector2(x0, by), Vector2(bw * share, 3.5)), Color(1.0, 0.8, 0.35, 0.9))
		else:
			draw_rect(Rect2(Vector2(x0, by), Vector2(bw, 3.5)), Color(1.0, 0.8, 0.35, 0.35))
