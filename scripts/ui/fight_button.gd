extends Control
class_name FightButton

## === Shaped touch fight button ===
## Thumb-ready action control cloned from EmberJoystick's input model:
## per-pointer screen-touch tracking (attack + dodge work on separate
## fingers), mouse fallback for desktop, accept_event() so touches never
## leak into world taps. Draws its own silhouette — an axe-head polygon for
## the primary strike, a rimmed disc for skills/dodge/jump — plus a radial
## cooldown arc fed by the HUD's poll.

signal fight_pressed
signal fight_released

enum Shape { AXE, CIRCLE, SLASH }

@export var shape: Shape = Shape.CIRCLE
@export var accent := Color(0.96, 0.72, 0.29):
	set(value):
		if accent.is_equal_approx(value):
			return
		accent = value
		queue_redraw()

const BACKING := Color(0.05, 0.08, 0.10, 0.82)
const STEEL := Color(0.58, 0.64, 0.71, 1.0)
const WOOD := Color(0.36, 0.24, 0.13, 1.0)
const CD_OVERLAY := Color(0.07, 0.07, 0.09, 0.88)

var active_pointer := -1
var mouse_active := false
var dimmed := false:
	set(value):
		if dimmed == value:
			return
		dimmed = value
		self_modulate.a = 0.38 if value else 1.0
		queue_redraw()
var _pressed := false
var _cooldown_ratio := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

## Cooldown ring: ratio = remaining/total; 0 means ready.
func set_cooldown(remaining: float, total: float) -> void:
	var ratio := clampf(remaining / maxf(total, 0.01), 0.0, 1.0) if remaining > 0.0 else 0.0
	if absf(ratio - _cooldown_ratio) < 0.004:
		return
	_cooldown_ratio = ratio
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and active_pointer == -1:
			active_pointer = event.index
			_fire()
		elif not event.pressed and event.index == active_pointer:
			active_pointer = -1
			_pressed = false
			fight_released.emit()
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_active = true
			_pressed = true
			_fire()
		else:
			mouse_active = false
			_pressed = false
			fight_released.emit()
			queue_redraw()
		accept_event()

func _fire() -> void:
	fight_pressed.emit()
	_press_feedback()

func _press_feedback() -> void:
	_pressed = true
	queue_redraw()
	modulate = Color(1.5, 1.5, 1.25)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	var center := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	if r <= 0.0:
		return
	draw_circle(center, r, BACKING)
	match shape:
		Shape.AXE:
			_draw_axe_head(center, r)
		Shape.SLASH:
			_draw_slash(center, r)
		_:
			var fill := accent
			fill.a = 0.05 if dimmed else 0.12
			draw_circle(center, r * 0.80, fill)
	var rim := accent.lightened(0.35) if _pressed else accent
	draw_arc(center, r, 0.0, TAU, 64,
		Color(rim.r, rim.g, rim.b, 0.55 if dimmed else 0.9), 3.0, true)
	if _cooldown_ratio > 0.004:
		# Dark overlay drains clockwise from the top as the cooldown recovers
		draw_arc(center, r, -PI * 0.5, -PI * 0.5 + TAU * _cooldown_ratio,
			48, CD_OVERLAY, 6.0, true)

## Diagonal sword slash: a broad angled blade with an ember edge, a small
## cross-guard and pommel — reads as "strike" at a thumb-glance.
func _draw_slash(c: Vector2, r: float) -> void:
	var blade := STEEL.darkened(0.3) if dimmed else STEEL
	var half := r * 0.5
	var rot := -0.72
	# Blade: an elongated kite along the diagonal
	var pts := PackedVector2Array([
		Vector2(-half, -r * 0.95), Vector2(half, -r * 0.30),
		Vector2(half * 0.6, r * 0.82), Vector2(-half * 0.6, r * 0.82),
		Vector2(-half * 0.95, r * 0.25)])
	for i in pts.size():
		pts[i] = c + pts[i].rotated(rot)
	draw_colored_polygon(pts, blade)
	# Bright edge down the leading side
	var edge := PackedVector2Array([
		c + (Vector2(-half, -r * 0.95)).rotated(rot),
		c + (Vector2(half, -r * 0.30)).rotated(rot)])
	draw_polyline(edge, accent.lightened(0.25), maxf(2.0, r * 0.06), true)
	# Cross-guard
	var guard := PackedVector2Array([
		c + (Vector2(-r * 0.85, r * 0.30)).rotated(rot),
		c + (Vector2(r * 0.85, r * 0.18)).rotated(rot)])
	draw_polyline(guard, accent.darkened(0.1), maxf(3.0, r * 0.09), true)
	var pom := c + (Vector2(0, r * 0.92)).rotated(rot)
	draw_circle(pom, maxf(2.5, r * 0.07), accent)

## Stylized double-bit axe head: two beveled steel fans meeting over a
## wrapped wooden haft, gold edge glints and a center rivet.
func _draw_axe_head(c: Vector2, r: float) -> void:
	var s := r * 0.92
	var half := PackedVector2Array([
		Vector2(-0.14, -0.50), Vector2(-0.52, -0.84), Vector2(-0.90, -0.62),
		Vector2(-1.00, -0.12), Vector2(-0.86, 0.34), Vector2(-0.54, 0.70),
		Vector2(-0.28, 0.50), Vector2(-0.14, 0.18)])
	for side in [-1.0, 1.0]:
		var blade := PackedVector2Array()
		for p in half:
			blade.append(c + Vector2(p.x * side, p.y) * s)
		draw_colored_polygon(blade, STEEL.darkened(0.35) if dimmed else STEEL)
		# Inner bevel: a slightly smaller fan reads as a ground edge face
		var bevel := PackedVector2Array()
		for p in half:
			bevel.append(c + (Vector2(p.x * side, p.y) * s).lerp(
				c + Vector2(0, 0.06) * s, 0.22))
		draw_colored_polygon(bevel,
			STEEL.darkened(0.15) if dimmed else STEEL.lightened(0.12))
		var edge := PackedVector2Array()
		for p in [half[1], half[2], half[3], half[4], half[5]]:
			edge.append(c + Vector2(p.x * side, p.y) * s)
		var glint := accent
		glint.a = 0.35 if dimmed else 0.85
		draw_polyline(edge, glint, maxf(2.0, s * 0.05), true)
	# Haft with leather wrap bands
	var haft := PackedVector2Array([
		c + Vector2(-0.11, -0.58) * s, c + Vector2(0.11, -0.58) * s,
		c + Vector2(0.15, 0.98) * s, c + Vector2(-0.15, 0.98) * s])
	draw_colored_polygon(haft, WOOD.darkened(0.3) if dimmed else WOOD)
	for i in 4:
		var yy := -0.30 + i * 0.22
		var band := PackedVector2Array([
			c + Vector2(-0.13, yy) * s, c + Vector2(0.13, yy) * s,
			c + Vector2(0.15, yy + 0.07) * s, c + Vector2(-0.15, yy + 0.07) * s])
		draw_colored_polygon(band,
			Color(0.16, 0.11, 0.06, 0.9 if not dimmed else 0.5))
	# Center rivet pins the head to the haft
	var rivet_r := maxf(3.0, s * 0.09)
	draw_circle(c + Vector2(0, -0.44) * s, rivet_r, STEEL.lightened(0.35))
	draw_circle(c + Vector2(-rivet_r * 0.25, -0.44 * s - rivet_r * 0.25),
		rivet_r * 0.6, STEEL.lightened(0.55))
