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
@export_range(1.0, 1.5, 0.05) var accessibility_touch_scale: float = 1.0:
	set(value):
		accessibility_touch_scale = clampf(value, 1.0, 1.5)
		if _base_minimum_size != Vector2.ZERO:
			custom_minimum_size = _base_minimum_size * accessibility_touch_scale
		queue_redraw()
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
var _base_minimum_size := Vector2.ZERO
# Human-readable info fed by the HUD so the custom tooltip can explain what
# a skill does, its effect, its cooldown, and whether it needs a target.
var tooltip_data: Dictionary = {}
var semantic_action: Dictionary = {}
var skill_kind := "":
	set(value):
		skill_kind = value
		_refresh_icon()
		queue_redraw()
## Authored icon for the current skill. The procedural fallback below still
## covers kinds that have no authored mark yet.
var _icon_tex: Texture2D = null
var _key_chip: StyleBoxFlat = null
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

## Shared action-state adapter for custom touch controls. Combat callers use
## this instead of inventing a second disabled/tooltip vocabulary.
func set_action_state(state: String, detail: String = "") -> void:
	semantic_action = UiKit.action_state(state, detail)
	dimmed = bool(semantic_action.get("disabled", false))
	tooltip_data["state_label"] = str(semantic_action.get("label", ""))
	tooltip_data["state_detail"] = str(semantic_action.get("detail", ""))
	tooltip_text = "%s%s" % [str(semantic_action.get("label", "")),
		(" · " + detail) if not detail.is_empty() else ""]
	queue_redraw()

## Authored marks live in IconRegistry; "bleed" and "heavy_aoe" are the two
## kinds whose registry key differs from the gameplay kind.
const ICON_KEYS: Dictionary = {
	"bleed": "strike", "heavy_aoe": "aoe", "aoe": "aoe",
	"strike": "strike", "whirl": "whirl", "dash_strike": "dash_strike",
	"heal_bloom": "heal_bloom", "comet": "comet", "explosion": "explosion",
}

func _refresh_icon() -> void:
	var key := str(ICON_KEYS.get(skill_kind, skill_kind))
	_icon_tex = UiKit.icon_texture(key) if not key.is_empty() else null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_base_minimum_size = custom_minimum_size
	custom_minimum_size = _base_minimum_size * accessibility_touch_scale
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
	var rim := accent.lightened(0.35) if _pressed else accent
	# Contact shadow, then the base disc: a flat circle read as a sticker; the
	# layered version reads as a pressed metal medallion.
	draw_circle(center + Vector2(0.0, 2.0), r, Color(0, 0, 0, 0.38))
	draw_circle(center, r, BACKING)
	draw_circle(center, r * 0.92, Color(accent.r, accent.g, accent.b,
		0.06 if dimmed else 0.16))
	draw_circle(center + Vector2(0.0, -r * 0.26), r * 0.66, Color(1.0, 1.0, 1.0, 0.05))
	match shape:
		Shape.AXE:
			_draw_axe_head(center, r)
		Shape.SLASH:
			_draw_slash(center, r)
		_:
			if not skill_kind.is_empty():
				_draw_skill_icon(center, r * 0.58)
	draw_arc(center, r - 1.0, 0.0, TAU, 64, Color(0, 0, 0, 0.55), 5.0, true)
	draw_arc(center, r - 3.0, 0.0, TAU, 64,
		Color(rim.r, rim.g, rim.b, 0.55 if dimmed else 0.95), 3.0, true)
	draw_arc(center, r - 6.0, PI * 0.82, PI * 1.48, 24,
		Color(1.0, 1.0, 1.0, 0.05 if dimmed else 0.12), 2.0, true)
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
	if not _key_label().is_empty():
		_draw_key_chip(center, r)

## The keyboard/gamepad binding shown on the control itself.
func _key_label() -> String:
	return str(tooltip_data.get("key", "")).strip_edges()

func _draw_key_chip(center: Vector2, r: float) -> void:
	if _key_chip == null:
		_key_chip = StyleBoxFlat.new()
		_key_chip.bg_color = Color(0.02, 0.03, 0.03, 0.86)
		_key_chip.border_color = Color(accent.r, accent.g, accent.b, 0.55)
		_key_chip.set_border_width_all(1)
		_key_chip.set_corner_radius_all(6)
		_key_chip.content_margin_left = 5
		_key_chip.content_margin_right = 5
		_key_chip.content_margin_top = 1
		_key_chip.content_margin_bottom = 1
	var label := _key_label()
	var font := ThemeDB.fallback_font
	var font_size := int(clampf(r * 0.34, 13.0, 20.0))
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var chip_size := text_size + Vector2(14.0, 6.0)
	var chip_pos := center + Vector2(r * 0.30, r * 0.30)
	draw_style_box(_key_chip, Rect2(chip_pos, chip_size))
	draw_string(font, chip_pos + Vector2(7.0, chip_size.y - 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
		Color(1.0, 0.94, 0.80, 0.92))

func _draw_skill_icon(c: Vector2, r: float) -> void:
	var ink := accent.lightened(0.34)
	if dimmed:
		ink = ink.darkened(0.42)
	var dark := BACKING.lightened(0.08)
	if _icon_tex != null:
		# A dark medallion behind the mark keeps it legible over the cooldown
		# pie, then the authored silhouette is drawn on top in the rite's accent.
		draw_circle(c, r * 0.94, Color(0.02, 0.03, 0.03, 0.75))
		var side := r * 1.72
		var rect := Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))
		var tint := Color(1.0, 1.0, 1.0, 0.42 if dimmed else 1.0)
		draw_texture_rect(_icon_tex, rect, false, tint)
		return
	match skill_kind:
		"bleed":
			# Three descending cuts plus a falling droplet: readable as a
			# damage-over-time rite without relying on a language glyph.
			for i in 3:
				var yy := -0.48 + float(i) * 0.38
				draw_line(c + Vector2(-0.62, yy) * r, c + Vector2(0.18, yy - 0.22) * r,
					ink, maxf(3.0, r * 0.09), true)
			draw_circle(c + Vector2(0.48, 0.38) * r, r * 0.16, Color(0.82, 0.16, 0.18))
			draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.48, 0.62) * r,
			c + Vector2(0.34, 0.36) * r,
			c + Vector2(0.62, 0.36) * r]), Color(0.82, 0.16, 0.18))
		"strike":
			var blade := PackedVector2Array([
				c + Vector2(-0.12, 0.70) * r, c + Vector2(0.12, 0.70) * r,
				c + Vector2(0.20, -0.48) * r, c + Vector2(0.0, -0.88) * r,
				c + Vector2(-0.20, -0.48) * r])
			draw_colored_polygon(blade, STEEL)
			draw_line(c + Vector2(-0.48, 0.42) * r, c + Vector2(0.48, 0.42) * r, ink, 4.0, true)
		"whirl":
			draw_arc(c, r * 0.68, -0.35, TAU - 0.72, 30, ink, 7.0, true)
			var tip := PackedVector2Array([c + Vector2(0.66, -0.30) * r,
				c + Vector2(0.30, -0.37) * r, c + Vector2(0.55, -0.02) * r])
			draw_colored_polygon(tip, ink)
		"dash_strike":
			for y in [-0.34, 0.0, 0.34]:
				draw_line(c + Vector2(-0.72, y) * r, c + Vector2(0.15, y) * r, ink, 4.0, true)
			var arrow := PackedVector2Array([c + Vector2(0.05, -0.68) * r,
				c + Vector2(0.78, 0.0) * r, c + Vector2(0.05, 0.68) * r])
			draw_colored_polygon(arrow, ink)
		"heal_bloom":
			draw_rect(Rect2(c + Vector2(-0.18, -0.72) * r, Vector2(0.36, 1.44) * r), ink, true)
			draw_rect(Rect2(c + Vector2(-0.72, -0.18) * r, Vector2(1.44, 0.36) * r), ink, true)
		"comet":
			draw_circle(c + Vector2(0.28, 0.24) * r, r * 0.34, ink)
			draw_line(c + Vector2(-0.70, -0.70) * r, c + Vector2(0.05, 0.05) * r, ink, 8.0, true)
			draw_line(c + Vector2(-0.68, -0.35) * r, c + Vector2(-0.02, 0.18) * r, ink, 4.0, true)
		"explosion":
			var burst := PackedVector2Array()
			for i in 16:
				var rr := r * (0.82 if i % 2 == 0 else 0.38)
				var a := TAU * float(i) / 16.0
				burst.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(burst, ink)
		"aoe", "heavy_aoe":
			draw_circle(c, r * 0.30, ink)
			draw_arc(c, r * 0.68, 0.0, TAU, 32, ink, 5.0, true)
			draw_circle(c, r * 0.11, dark)
		_:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.78) * r, c + Vector2(0.68, 0) * r,
				c + Vector2(0, 0.78) * r, c + Vector2(-0.68, 0) * r]), ink)

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
## A clean greatsword icon — tapered steel blade with a fuller highlight,
## brass crossguard, wrapped grip and pommel. Replaces the old double-axe
## polygon, which read as an ambiguous white bowtie at thumb size.
func _draw_axe_head(c: Vector2, r: float) -> void:
	var s := r * 0.92
	var steel := STEEL.darkened(0.35) if dimmed else STEEL
	var steel_hi := STEEL.darkened(0.15) if dimmed else STEEL.lightened(0.25)
	var brass := Color(0.72, 0.55, 0.24).darkened(0.3) if dimmed \
		else Color(0.72, 0.55, 0.24)
	var wood := WOOD.darkened(0.3) if dimmed else WOOD
	# Blade: pointed pentagon, tip up
	var blade := PackedVector2Array([
		c + Vector2(0.0, -0.60) * s,
		c + Vector2(0.12, -0.42) * s, c + Vector2(0.11, -0.02) * s,
		c + Vector2(-0.11, -0.02) * s, c + Vector2(-0.12, -0.42) * s])
	draw_colored_polygon(blade, steel)
	# Fuller highlight down the middle of the blade
	draw_line(c + Vector2(0, -0.40) * s, c + Vector2(0, -0.06) * s,
		steel_hi, maxf(2.0, s * 0.06), true)
	# Crossguard
	var guard := PackedVector2Array([
		c + Vector2(-0.30, 0.00) * s, c + Vector2(0.30, 0.00) * s,
		c + Vector2(0.26, 0.12) * s, c + Vector2(-0.26, 0.12) * s])
	draw_colored_polygon(guard, brass)
	# Grip with wrap bands
	var grip := PackedVector2Array([
		c + Vector2(-0.07, 0.12) * s, c + Vector2(0.07, 0.12) * s,
		c + Vector2(0.08, 0.42) * s, c + Vector2(-0.08, 0.42) * s])
	draw_colored_polygon(grip, wood)
	for i in 2:
		var yy := 0.20 + i * 0.12
		draw_line(c + Vector2(-0.08, yy) * s, c + Vector2(0.08, yy) * s,
			Color(0.16, 0.11, 0.06, 0.9), maxf(2.0, s * 0.05), true)
	# Pommel
	draw_circle(c + Vector2(0, 0.48) * s, maxf(3.0, s * 0.09), steel_hi)

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
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TT_TITLE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(title)

	var type_str := str(d.get("type_label", ""))
	var cooldown := float(d.get("cooldown", 0.0))
	var meta := Label.new()
	meta.text = "%s   ·   CD %0.1fs" % [type_str, cooldown]
	meta.add_theme_font_size_override("font_size", 20)
	meta.add_theme_color_override("font_color", TT_ACCENT)
	vbox.add_child(meta)
	var state_label := str(d.get("state_label", ""))
	if not state_label.is_empty():
		var state := Label.new()
		state.text = state_label
		state.add_theme_font_size_override("font_size", 20)
		state.add_theme_color_override("font_color", TT_ACCENT)
		vbox.add_child(state)
	var state_detail := str(d.get("state_detail", ""))
	if not state_detail.is_empty():
		var state_note := Label.new()
		state_note.text = state_detail
		state_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		state_note.add_theme_font_size_override("font_size", 18)
		state_note.add_theme_color_override("font_color", TT_DIM)
		vbox.add_child(state_note)

	var desc := str(d.get("desc", ""))
	if desc != "":
		var dl := Label.new()
		dl.text = desc
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(280, 0)
		dl.add_theme_font_size_override("font_size", 20)
		dl.add_theme_color_override("font_color", TT_BODY)
		vbox.add_child(dl)

	var effect := str(d.get("effect", ""))
	if effect != "":
		var el := Label.new()
		el.text = effect
		el.add_theme_font_size_override("font_size", 20)
		el.add_theme_color_override("font_color", TT_DIM)
		vbox.add_child(el)

	var target := str(d.get("target_hint", ""))
	if target != "":
		var tl := Label.new()
		tl.text = target
		tl.add_theme_font_size_override("font_size", 18)
		tl.add_theme_color_override("font_color",
			Color(0.62, 0.85, 0.45) if target.begins_with("✓") else Color(0.96, 0.62, 0.35))
		vbox.add_child(tl)

	return panel
