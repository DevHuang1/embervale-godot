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

const TT_BG := Color(0.045, 0.06, 0.08, 0.96)
const TT_BORDER := Color(0.72, 0.55, 0.24, 0.95)
const TT_TITLE := Color(1.0, 0.93, 0.78)
const TT_ACCENT := Color(0.96, 0.72, 0.29)
const TT_BODY := Color(0.94, 0.90, 0.82)
const TT_DIM := Color(0.76, 0.70, 0.60)

var active_pointer := -1
var mouse_active := false
# Human-readable info fed by the HUD so the custom tooltip can explain what
# a skill does, its effect, its cooldown, and whether it needs a target.
var tooltip_data: Dictionary = {}
var dimmed := false:
	set(value):
		if dimmed == value:
			return
		dimmed = value
		self_modulate.a = 0.38 if value else 1.0
		queue_redraw()
var _pressed := false
var _cooldown_ratio := 0.0
var _cd_remaining := 0.0      # seconds left, for the on-logo countdown
var _ready_flash := 0.0    # brief glow when a cooldown completes
var _lock_glow := 0.0      # 0..1 lantern lock ring (a mark is held)
var _lock_target := 0.0

## Raise/lower the pulsing "marked foe" ring so the whole action row
## visibly breathes with the lantern lock.
func set_lock_glow(on: bool) -> void:
	_lock_target = 1.0 if on else 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

## Cooldown ring: ratio = remaining/total; 0 means ready.
func set_cooldown(remaining: float, total: float) -> void:
	var ratio := clampf(remaining / maxf(total, 0.01), 0.0, 1.0) if remaining > 0.0 else 0.0
	_cd_remaining = remaining
	# Crossing from cooling → ready sparks a one-shot flash
	if _cooldown_ratio > 0.02 and ratio <= 0.001:
		_flash_ready()
	if absf(ratio - _cooldown_ratio) < 0.004:
		return
	_cooldown_ratio = ratio
	queue_redraw()

## Radial flash ring + soft scale pop when the rite comes off cooldown.
func _flash_ready() -> void:
	_ready_flash = 1.0
	queue_redraw()
	var tween := create_tween()
	tween.tween_method(func(v: float): _ready_flash = v, 1.0, 0.0, 0.45)
	pivot_offset = size * 0.5
	scale = Vector2(1.12, 1.12)
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	pivot_offset = size * 0.5
	scale = Vector2(1.08, 1.08)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate", Color.WHITE, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _ready_flash > 0.0:
		_ready_flash = maxf(_ready_flash - delta * 2.2, 0.0)
		if _ready_flash == 0.0:
			queue_redraw()
	if _lock_glow != _lock_target:
		if _lock_glow < _lock_target:
			_lock_glow = minf(_lock_glow + delta * 3.5, 1.0)
		else:
			_lock_glow = maxf(_lock_glow - delta * 5.0, 0.0)
		queue_redraw()
	_glow_drift += delta
	if _lock_glow > 0.0:
		queue_redraw()

var _glow_drift := 0.0

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
	if _lock_glow > 0.01:
		# Pulsing lantern-orange ring: "a foe is lit" — breathes in time with
		# the ground mark so button row and world ring share one language.
		var pulse := 0.5 + 0.5 * sin(_glow_drift * TAU * 1.2)
		var lc := Color(1.0, 0.74, 0.30)
		draw_arc(center, r + 4.0, 0.0, TAU, 64,
			Color(lc.r, lc.g, lc.b, (0.35 + 0.45 * pulse) * _lock_glow), 4.0, true)
		draw_arc(center, r * (1.04 + 0.06 * pulse), 0.0, TAU, 64,
			Color(lc.r, lc.g, lc.b,
				0.30 * _lock_glow * (1.0 - pulse * 0.5)), 2.0, true)
	if _cooldown_ratio > 0.004:
		# Pie overlay covering the icon interior proportionally to remaining
		# time — unmistakable at thumb-glance, unlike a thin rim arc alone.
		var segs := 40
		var fan := PackedVector2Array([center])
		for i in segs + 1:
			var pie_ang := -PI * 0.5 + TAU * _cooldown_ratio * float(i) / float(segs)
			fan.append(center + Vector2(cos(pie_ang), sin(pie_ang)) * r * 0.93)
		draw_colored_polygon(fan, Color(0.02, 0.03, 0.03, 0.55))
		# Dark overlay drains clockwise from the top as the cooldown recovers —
		# thick and high-contrast so it reads clearly around the icon.
		var cd_end := -PI * 0.5 + TAU * _cooldown_ratio
		draw_arc(center, r, -PI * 0.5, cd_end, 48, CD_OVERLAY, 7.0, true)
		# A bright leading edge marks where the drain currently is.
		var lead := accent.lightened(0.4)
		lead.a = 0.9 if not dimmed else 0.5
		draw_arc(center, r, cd_end - 0.12, cd_end, 8, lead, 8.0, true)
		# Big centered countdown INSIDE the logo disc.
		var txt := ("%d" % int(ceil(_cd_remaining))) if _cd_remaining >= 3.0 \
			else ("%0.1f" % _cd_remaining)
		var fs := int(clampf(r * 0.62, 13.0, 34.0))
		var f := ThemeDB.fallback_font
		var base_y := center.y + fs * 0.36
		var txt_w := r * 2.0
		var txt_x := center.x - r
		draw_string_outline(f, Vector2(txt_x, base_y), txt,
			HORIZONTAL_ALIGNMENT_CENTER, txt_w, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(txt_x, base_y), txt,
			HORIZONTAL_ALIGNMENT_CENTER, txt_w, fs, Color(1.0, 0.93, 0.72))
	if _ready_flash > 0.01:
		# Expanding glow ring when the rite comes off cooldown
		var flash_col := accent.lightened(0.5)
		flash_col.a = 0.85 * _ready_flash
		draw_arc(center, r * (1.04 + 0.12 * (1.0 - _ready_flash)),
			0.0, TAU, 64, flash_col, 4.0 + 3.0 * _ready_flash, true)

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

## Build a rich, readable explanation panel for a skill. Called by Godot
## whenever the hover tooltip is needed; content comes from tooltip_data,
## which the HUD sets from the equipped weapon kit each frame.
func _make_custom_tooltip(_for_text: String) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TT_BG
	sb.set_border_width_all(2)
	sb.border_color = TT_BORDER
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	var d: Dictionary = tooltip_data
	var name_str := str(d.get("name", "RITE"))
	var key := str(d.get("key", ""))
	var title := Label.new()
	title.text = "%s  %s" % [name_str, ("(%s)" % key) if key != "" else ""]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TT_TITLE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(title)

	var type_str := str(d.get("type_label", ""))
	var cooldown := float(d.get("cooldown", 0.0))
	var meta := Label.new()
	meta.text = "%s   ·   CD %0.1fs" % [type_str, cooldown]
	meta.add_theme_font_size_override("font_size", 14)
	meta.add_theme_color_override("font_color", TT_ACCENT)
	vbox.add_child(meta)

	var desc := str(d.get("desc", ""))
	if desc != "":
		var dl := Label.new()
		dl.text = desc
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(240, 0)
		dl.add_theme_font_size_override("font_size", 14)
		dl.add_theme_color_override("font_color", TT_BODY)
		vbox.add_child(dl)

	var effect := str(d.get("effect", ""))
	if effect != "":
		var el := Label.new()
		el.text = effect
		el.add_theme_font_size_override("font_size", 14)
		el.add_theme_color_override("font_color", TT_DIM)
		vbox.add_child(el)

	var target := str(d.get("target_hint", ""))
	if target != "":
		var tl := Label.new()
		tl.text = target
		tl.add_theme_font_size_override("font_size", 13)
		tl.add_theme_color_override("font_color",
			Color(0.62, 0.85, 0.45) if target.begins_with("✓") else Color(0.96, 0.62, 0.35))
		vbox.add_child(tl)

	return panel

