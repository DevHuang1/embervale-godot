extends ProgressBar
class_name EmberBar

## === EmberBar — hand-drawn vitals bar ===
## Replaces the stock ProgressBar chrome with a grove-styled bar: rounded
## parchment-backed track, glowing fill, segment ticks, and a pale "ghost"
## trail that lingers where damage was just lost (classic fighting-game
## readability). Works for HP, XP, enemy and boss bars alike.

@export var accent := Color(0.78, 0.30, 0.22)
@export var ghost_color := Color(1.0, 0.93, 0.80, 0.85)
@export var track_color := Color(0.07, 0.10, 0.09, 0.92)
@export var border_color := Color(0.35, 0.26, 0.14, 1.0)
@export var show_ticks := true
@export var ghost_lag := true

var _display_ratio := 1.0    # eased fill
var _ghost_ratio := 1.0      # lingering damage marker
var _ghost_hold := 0.0       # pause before the ghost starts chasing
var _flash := 0.0            # border pulse on gain/loss
var _flash_color := Color.WHITE
var _last_value := -1.0

func _ready() -> void:
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display_ratio = ratio()
	_ghost_ratio = _display_ratio
	value_changed.connect(func(_v): queue_redraw())
	resized.connect(func(): queue_redraw())

func ratio() -> float:
	return clampf(value / maxf(max_value, 0.001), 0.0, 1.0)

func _process(delta: float) -> void:
	var prev := _last_value
	if value != prev and prev >= 0.0:
		if value < prev and ghost_lag:
			_ghost_hold = 0.45   # damage: let the loss register first
			_flash = 1.0
			_flash_color = Color(1.0, 0.42, 0.30)
		elif value > prev:
			_ghost_ratio = maxf(_ghost_ratio, ratio())
			_flash = 0.7
			_flash_color = Color(0.65, 1.0, 0.55)
	_last_value = value
	# Fill eases toward the true value: quick swell on gain, gentle drain
	var diff := ratio() - _display_ratio
	_display_ratio += clampf(diff, -delta * 2.8, delta * 7.0)
	# Ghost chases down after a short hold; snaps up instantly on heals
	if not ghost_lag:
		_ghost_ratio = ratio()
	elif _ghost_hold > 0.0:
		_ghost_hold -= delta
	else:
		_ghost_ratio = maxf(ratio(),
			move_toward(_ghost_ratio, ratio(), delta * 0.55))
	_flash = maxf(_flash - delta * 2.4, 0.0)
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var inset := 2.0
	var inner := r.grow(-inset)
	# Track
	var bg := StyleBoxFlat.new()
	bg.bg_color = track_color
	bg.set_corner_radius_all(int(size.y * 0.45))
	bg.border_color = border_color
	bg.set_border_width_all(2)
	bg.draw(get_canvas_item(), r)
	# Ghost (damage trail) behind the live fill
	if ghost_lag and _ghost_ratio > _display_ratio + 0.003:
		var gr := Rect2(inner.position,
			Vector2(inner.size.x * _ghost_ratio, inner.size.y))
		var gb := StyleBoxFlat.new()
		gb.bg_color = Color(ghost_color.r, ghost_color.g, ghost_color.b, 0.38)
		gb.set_corner_radius_all(int(inner.size.y * 0.4))
		gb.draw(get_canvas_item(), gr)
	# Live fill
	if _display_ratio > 0.002:
		var fr := Rect2(inner.position,
			Vector2(maxf(inner.size.x * _display_ratio, inner.size.y), inner.size.y))
		var fb := StyleBoxFlat.new()
		fb.bg_color = accent
		fb.set_corner_radius_all(int(inner.size.y * 0.4))
		fb.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
		fb.shadow_size = 3
		fb.draw(get_canvas_item(), fr)
		# Top sheen strip for a lantern-lit gloss
		var sheen := Rect2(fr.position + Vector2(1, 1),
			Vector2(fr.size.x - 2.0, maxf(inner.size.y * 0.32, 1.5)))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.22)
		sb.set_corner_radius_all(int(sheen.size.y * 0.5))
		sb.draw(get_canvas_item(), sheen)
	# Segment ticks at quarters
	if show_ticks and size.x > 60.0:
		for q: float in [0.25, 0.5, 0.75]:
			var x := inner.position.x + inner.size.x * q
			draw_line(Vector2(x, inner.position.y + 1),
				Vector2(x, inner.end.y - 1),
				Color(0, 0, 0, 0.28), 1.0, true)
	# Flash border on gain/loss
	if _flash > 0.01:
		var fl := StyleBoxFlat.new()
		fl.bg_color = Color(_flash_color.r, _flash_color.g, _flash_color.b,
			0.30 * _flash)
		fl.set_corner_radius_all(int(size.y * 0.45))
		fl.border_color = Color(_flash_color.r, _flash_color.g,
			_flash_color.b, 0.85 * _flash)
		fl.set_border_width_all(2)
		fl.draw(get_canvas_item(), r)
