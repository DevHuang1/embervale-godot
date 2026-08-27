class_name UiKit
extends RefCounted

## === Ember Glass UI Kit ===
## Single source of truth for the game's web-inspired design tokens and
## reusable styling primitives. The shared Theme (assets/ui/theme.tres)
## covers default controls; these helpers cover code-built chrome.

const BG_DEEP := Color(0.043, 0.090, 0.071)
const GLASS_BG := Color(0.030, 0.048, 0.038, 0.92)
const GLASS_BG_RAISED := Color(0.038, 0.058, 0.046, 0.94)
const EMBER := Color(0.961, 0.722, 0.255)
const EMBER_BRIGHT := Color(1.0, 0.84, 0.47)
const EMBER_DEEP := Color(0.78, 0.49, 0.16)
const CREAM := Color(0.965, 0.925, 0.808)
const CREAM_DIM := Color(0.90, 0.87, 0.76)
const SAGE := Color(0.56, 0.686, 0.451)
const SAGE_DIM := Color(0.38, 0.46, 0.32)
const DANGER := Color(0.851, 0.322, 0.227)
const BORDER_GOLD := Color(0.961, 0.722, 0.255, 0.70)
const BORDER_GOLD_STRONG := Color(0.961, 0.722, 0.255, 1.0)

# Accent family for rite-type skill buttons (lit by rite family)
const STEEL := Color(0.58, 0.64, 0.71, 1.0)
const WOOD := Color(0.36, 0.24, 0.13, 1.0)
# Parchment surface — warm letter stock read against the dark grove.
const PARCHMENT_BG := Color(0.92, 0.84, 0.68, 0.92)
const PARCHMENT_INK := Color(0.52, 0.42, 0.30, 1.0)
const PARCHMENT_EDGE := Color(0.78, 0.49, 0.16, 1.0)
const DANGER_BRIGHT := Color(1.0, 0.46, 0.34)
const SAGE_BRIGHT := Color(0.62, 0.82, 0.52)
const CHIP_BG := Color(0.055, 0.078, 0.062, 0.82)
# Fullscreen dimmer behind floating sheets / confirm overlays.
const MODAL_DIM := Color(0.006, 0.016, 0.011, 0.72)

const RADIUS_PANEL := 16
const RADIUS_BUTTON := 11

const _GLASS_SHADER := preload("res://assets/ui/glass_panel.gdshader")

static func glass_stylebox(raised: bool = false, border_alpha: float = 0.45,
		radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS_BG_RAISED if raised else GLASS_BG
	sb.border_color = Color(BORDER_GOLD.r, BORDER_GOLD.g, BORDER_GOLD.b, border_alpha)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.38)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	return sb

static func button_stylebox(state: String, accent: Color = EMBER,
		font_size_driven_width: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match state:
		"hover":
			sb.bg_color = Color(0.086, 0.125, 0.10, 0.95)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.75)
		"pressed":
			sb.bg_color = Color(0.035, 0.055, 0.042, 0.98)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.95)
		"disabled":
			sb.bg_color = Color(0.05, 0.07, 0.06, 0.55)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.18)
		_:
			sb.bg_color = Color(0.058, 0.088, 0.070, 0.88)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.42)
	sb.set_border_width_all(1)
	if state == "pressed":
		sb.set_border_width_all(2)
	sb.set_corner_radius_all(RADIUS_BUTTON)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 15
	sb.content_margin_bottom = 15
	return sb

static func style_button(b: Button, accent: Color = EMBER) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, button_stylebox(state, accent))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_hover_color", EMBER_BRIGHT)
	b.add_theme_color_override("font_pressed_color", EMBER)
	b.add_theme_color_override("font_disabled_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.30))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	b.add_theme_constant_override("outline_size", 2)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("shadow_offset_y", 2)

## Big primary action: ember-lit surface instead of dark glass.
static func style_primary_button(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := button_stylebox(state)
		match state:
			"normal":
				sb.bg_color = Color(0.62, 0.42, 0.12, 0.94)
				sb.border_color = Color(EMBER_BRIGHT.r, EMBER_BRIGHT.g, EMBER_BRIGHT.b, 0.65)
			"hover":
				sb.bg_color = Color(0.72, 0.49, 0.15, 0.97)
				sb.border_color = Color(EMBER_BRIGHT.r, EMBER_BRIGHT.g, EMBER_BRIGHT.b, 0.95)
			"pressed":
				sb.bg_color = Color(0.48, 0.31, 0.09, 1.0)
			"disabled":
				sb.bg_color = Color(0.30, 0.24, 0.14, 0.60)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.94))
	b.add_theme_color_override("font_pressed_color", Color(0.96, 0.86, 0.64))
	b.add_theme_color_override("font_disabled_color", Color(0.9, 0.87, 0.78, 0.35))
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("shadow_offset_y", 2)

static func chip_style(lbl: Label, tint: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.055, 0.042, 0.80)
	sb.border_color = Color(tint.r, tint.g, tint.b, 0.50)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	lbl.add_theme_stylebox_override("normal", sb)

## Fake-glass overlay: sheen highlight + faint living grain drawn between a
## panel's stylebox and its content. Cheap enough for every panel on mobile.
static func apply_glass(panel: PanelContainer, corner_radius: float = RADIUS_PANEL,
		sheen: float = 0.10) -> void:
	var rect := ColorRect.new()
	rect.name = "GlassVeil"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = _GLASS_SHADER
	mat.set_shader_parameter("corner_radius", corner_radius)
	mat.set_shader_parameter("sheen_strength", sheen)
	rect.material = mat
	panel.add_child(rect)
	panel.move_child(rect, 0)
	_sync_glass_size(panel, rect, corner_radius)
	panel.resized.connect(
		func(): _sync_glass_size(panel, rect, corner_radius))

static func _sync_glass_size(panel: Control, rect: ColorRect, corner_radius: float) -> void:
	var mat := rect.material as ShaderMaterial
	mat.set_shader_parameter("panel_size", panel.size)

## Fade+rise entrance, staggered across a container's children.
static func stagger_entrance(container: Control, duration: float = 0.32,
		stagger: float = 0.06, rise: float = 26.0) -> Tween:
	var tw := container.get_tree().create_tween()
	tw.set_parallel(true)
	var i := 0
	for child in container.get_children():
		if child is Control:
			var c := child as Control
			var target_y := c.position.y
			c.modulate.a = 0.0
			c.position.y = target_y + rise
			tw.tween_property(c, "modulate:a", 1.0, duration) \
				.set_delay(i * stagger) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(c, "position:y", target_y, duration) \
				.set_delay(i * stagger) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			i += 1
	return tw


## === UI texture cache (import-independent) ===
## Reads generated PNGs straight from the packed filesystem as ImageTextures,
## so UI surfaces work identically in the editor (imported .ctex) and in
## headless test/export runs (no import cache required). One decode per name.
const _UI_TEX_DIR := "res://assets/textures/generated/"
static var _tex_cache: Dictionary = {}

static func _ui_tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name] as Texture2D
	var tex: Texture2D = null
	var path := _UI_TEX_DIR + name + ".png"
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			var img := Image.new()
			if img.load_png_from_buffer(bytes) == OK:
				tex = ImageTexture.create_from_image(img)
	_tex_cache[name] = tex
	return tex

## === Button roles ===
## Primary = ember-lit (CTA); secondary = subdued glass; danger = bloodied edge.

static func style_secondary_button(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := button_stylebox(state, SAGE)
		match state:
			"normal":   sb.bg_color = Color(0.045, 0.070, 0.055, 0.42)
			"hover":    sb.bg_color = Color(0.070, 0.105, 0.078, 0.60)
			"pressed":  sb.bg_color = Color(0.032, 0.050, 0.040, 0.65)
			"disabled": sb.bg_color = Color(0.045, 0.070, 0.055, 0.22)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", SAGE_BRIGHT)
	b.add_theme_color_override("font_pressed_color", SAGE)
	b.add_theme_color_override("font_disabled_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.25))
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("shadow_offset_y", 2)

static func style_danger_button(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := button_stylebox(state, DANGER)
		match state:
			"normal":   sb.bg_color = Color(0.070, 0.045, 0.042, 0.50)
			"hover":    sb.bg_color = Color(0.100, 0.055, 0.048, 0.70)
			"pressed":  sb.bg_color = Color(0.045, 0.028, 0.026, 0.75)
			"disabled": sb.bg_color = Color(0.070, 0.045, 0.042, 0.22)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", DANGER_BRIGHT)
	b.add_theme_color_override("font_pressed_color", DANGER)
	b.add_theme_color_override("font_disabled_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.25))
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("shadow_offset_y", 2)

## === Typography ===
## Route a label through one of the Theme's font-variation families so
## code-built UI matches scene UI exactly:
## Wordmark / Eyebrow / Title / Subtitle / Body / Caption / MenuTitle / RowLabel
static func style_label(lbl: Label, variation: String = "", font_size: int = -1) -> void:
	if not variation.is_empty():
		lbl.theme_type_variation = variation
	if font_size > 0:
		lbl.add_theme_font_size_override("font_size", font_size)

## === Surfaces ===
## A parchment-warm flat panel stylebox (warm letter stock vs. the dark grove).
static func parchment_stylebox(radius: float = RADIUS_PANEL) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PARCHMENT_BG
	sb.border_color = Color(BORDER_GOLD.r, BORDER_GOLD.g, BORDER_GOLD.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb

## Warm parchment panel: flat stock + a translucent fiber-vignette veil
## (the generated parchment texture, when present) + a gold edge. Idempotent.
static func apply_parchment(panel: PanelContainer, corner_radius: float = RADIUS_PANEL) -> void:
	panel.add_theme_stylebox_override("panel", parchment_stylebox(corner_radius))
	if panel.get_node_or_null("ParchmentVeil") != null:
		return
	var tex := _ui_tex("ui_parchment_paper")
	if tex == null:
		return
	var over := TextureRect.new()
	over.name = "ParchmentVeil"
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The fiber sheet must never dictate the host's minimum size.
	over.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	over.custom_minimum_size = Vector2.ZERO
	over.texture = tex
	over.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	over.self_modulate = Color(1.0, 1.0, 1.0, 0.24)
	panel.add_child(over)
	panel.move_child(over, 0)

## Rounded pill panel stylebox (version chip, stat pills). Tint darkens the
## rim so the label reads without a separate icon.
static func pill_stylebox(tint: Color = EMBER, corner_radius: float = 999.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.050, 0.042, 0.85)
	sb.border_color = Color(tint.r, tint.g, tint.b, 0.65)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(corner_radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb

## Route a label through one of the Theme's font-variation families so
## code-built UI matches scene UI exactly. (Kept as an alias of style_label.)
static func style_chip(lbl: Label, tint: Color) -> void:
	# Best-effort: set the pill bg override (only takes effect on controls that
	# draw it) AND tint the text so colored emoji/labels always read.
	chip_style(lbl, tint)
	lbl.add_theme_color_override("font_color", tint.lightened(0.08))
