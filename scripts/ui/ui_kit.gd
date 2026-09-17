class_name UiKit
extends RefCounted

## === Ember Glass UI Kit ===
## Single source of truth for the game's web-inspired design tokens and
## reusable styling primitives. The shared Theme (assets/ui/theme.tres)
## covers default controls; these helpers cover code-built chrome.

const BG_DEEP := Color(0.008, 0.014, 0.012)
# Modal surfaces are intentionally opaque. World lighting and foliage must not
# compete with inventory, merchant, scan, or settings copy.
const GLASS_BG := Color(0.012, 0.022, 0.018, 0.995)
const GLASS_BG_RAISED := Color(0.025, 0.038, 0.030, 1.0)
const EMBER := Color(0.961, 0.722, 0.255)
const EMBER_BRIGHT := Color(1.0, 0.84, 0.47)
const EMBER_DEEP := Color(0.78, 0.49, 0.16)
const CREAM := Color(1.0, 0.976, 0.91)
const CREAM_DIM := Color(0.92, 0.90, 0.84)
const SAGE := Color(0.56, 0.686, 0.451)
const SAGE_DIM := Color(0.38, 0.46, 0.32)
const DANGER := Color(0.851, 0.322, 0.227)
const BORDER_GOLD := Color(1.0, 0.78, 0.30, 0.82)
const BORDER_GOLD_STRONG := Color(0.961, 0.722, 0.255, 1.0)

# Accent family for rite-type skill buttons (lit by rite family)
const STEEL := Color(0.58, 0.64, 0.71, 1.0)
const WOOD := Color(0.36, 0.24, 0.13, 1.0)
# Obsidian parchment keeps the handmade texture without putting inherited
# ivory text on a pale surface.
const PARCHMENT_BG := Color(0.055, 0.038, 0.024, 0.995)
const PARCHMENT_INK := Color(1.0, 0.96, 0.86, 1.0)
const PARCHMENT_EDGE := Color(0.78, 0.49, 0.16, 1.0)
const DANGER_BRIGHT := Color(1.0, 0.46, 0.34)
const SAGE_BRIGHT := Color(0.62, 0.82, 0.52)
const CHIP_BG := Color(0.055, 0.078, 0.062, 0.82)
# Fullscreen dimmer behind floating sheets / confirm overlays.
const MODAL_DIM := Color(0.002, 0.006, 0.005, 0.88)

const RADIUS_PANEL := 16
const RADIUS_BUTTON := 11
const RADIUS_CARD := 9
## Minimum interactive size for Android touch targets.
const TOUCH_TARGET_MIN := 48.0
## Portrait Android builds often expose a 1080px logical width. Treat that as
## compact so modal controls wrap before they become unreadable.
const COMPACT_BREAKPOINT := 1200.0
const SAFE_MARGIN_COMPACT := 32.0
const SAFE_MARGIN_EXPANDED := 64.0

## Shared responsive metrics for code-built screens. Keeping the breakpoint and
## safe-area math here prevents inventory, shop, and forge from drifting apart.
static func responsive_metrics(viewport_size: Vector2) -> Dictionary:
	var compact := viewport_size.x < COMPACT_BREAKPOINT
	var margin := SAFE_MARGIN_COMPACT if compact else SAFE_MARGIN_EXPANDED
	return {
		"compact": compact,
		"safe_margin": margin,
		"content_width": maxf(0.0, viewport_size.x - margin * 2.0),
		"columns": 2 if compact else 4,
		"gap": 8.0 if compact else 12.0,
	}

## True only on a real phone/tablet display. Desktop and headless harnesses keep
## their authored layout, so no editor/test frame gains phantom insets.
static func is_mobile_display() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

## Pure inset math, split out from the platform query so it stays unit-testable:
## given the OS-reported safe rect and the physical screen size, return the
## notch / cutout / gesture-bar insets in viewport pixels.
static func insets_from_rects(safe: Rect2i, screen_size: Vector2,
		viewport_size: Vector2) -> Dictionary:
	var zero := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if safe.size.x <= 0 or safe.size.y <= 0:
		return zero
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return zero
	var scale := Vector2(viewport_size.x / screen_size.x, viewport_size.y / screen_size.y)
	return {
		"left": maxf(float(safe.position.x) * scale.x, 0.0),
		"top": maxf(float(safe.position.y) * scale.y, 0.0),
		"right": maxf((screen_size.x - float(safe.position.x + safe.size.x)) * scale.x, 0.0),
		"bottom": maxf((screen_size.y - float(safe.position.y + safe.size.y)) * scale.y, 0.0),
	}

## Device display insets in viewport pixels. Non-mobile callers get zeros.
static func safe_area_insets(viewport_size: Vector2) -> Dictionary:
	if not is_mobile_display():
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var safe := DisplayServer.get_display_safe_area()
	var screen_size := Vector2(DisplayServer.screen_get_size())
	return insets_from_rects(safe, screen_size, viewport_size)

## Inset a full-rect Control so its edge-anchored children clear the notch and
## the gesture/nav bar. A no-op when the device reports no inset.
static func apply_safe_area(control: Control, viewport_size: Vector2) -> Dictionary:
	if control == null:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var insets := safe_area_insets(viewport_size)
	control.offset_left = float(insets["left"])
	control.offset_top = float(insets["top"])
	control.offset_right = -float(insets["right"])
	control.offset_bottom = -float(insets["bottom"])
	return insets

## Inset a full-rect menu panel by its authored margin plus the device safe
## area, tightening the margin only on genuinely small viewports so desktop and
## tablet layout is untouched.
##
## The panel is normalised to full-rect first. Authored menus mix full-rect
## roots (anchors 0,0,1,1) with top-left-pinned ones (anchors 0,0,0,0) that use
## absolute pixel offsets; writing inset offsets onto a pinned root yields a
## negative width and the panel collapses to its minimum size.
static func apply_menu_frame(control: Control, viewport_size: Vector2,
		horizontal: float = 60.0, vertical: float = 60.0) -> Dictionary:
	if control == null:
		return {"horizontal": 0.0, "vertical": 0.0}
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH
	var insets := safe_area_insets(viewport_size)
	var inset_h := horizontal
	var inset_v := vertical
	if viewport_size.x < 900.0:
		inset_h = clampf(viewport_size.x * 0.05, 14.0, horizontal)
	if viewport_size.y < 1200.0:
		inset_v = clampf(viewport_size.y * 0.05, 12.0, vertical)
	control.offset_left = inset_h + float(insets["left"])
	control.offset_right = -(inset_h + float(insets["right"]))
	control.offset_top = inset_v + float(insets["top"])
	control.offset_bottom = -(inset_v + float(insets["bottom"]))
	return {"horizontal": inset_h, "vertical": inset_v}

## Shared semantic tokens for code-built screens. Callers should use these
## values instead of inventing per-screen spacing, typography, or rarity colors.
## Color is never the only status cue: item cards also render text and shape.
static func theme_tokens() -> Dictionary:
	return {
		"spacing": {
			"xs": 6.0, "sm": 8.0, "md": 12.0, "lg": 18.0, "xl": 28.0,
		},
		"typography": {
			"caption": 16, "body": 20, "button": 23, "heading": 30,
			"display": 42,
		},
		"surfaces": {
			"deep": BG_DEEP, "panel": GLASS_BG, "raised": GLASS_BG_RAISED,
			"chip": CHIP_BG, "modal_dim": MODAL_DIM,
		},
		"rarity": {
			"common": Color(0.68, 0.72, 0.70),
			"uncommon": SAGE_BRIGHT,
			"rare": Color(0.38, 0.68, 1.0),
			"epic": Color(0.78, 0.48, 1.0),
			"legendary": EMBER_BRIGHT,
		},
		"focus": {
			"outline": EMBER_BRIGHT, "outline_width": 2,
			"minimum_touch": TOUCH_TARGET_MIN,
		},
		"safe_area": {
			"compact_margin": SAFE_MARGIN_COMPACT,
			"expanded_margin": SAFE_MARGIN_EXPANDED,
		},
	}

## Semantic action copy shared by shops, forge, and scan surfaces. The state is
## machine-readable so a caller can style/disable consistently while the text
## remains understandable without color alone.
static func action_state(state: String, detail: String = "") -> Dictionary:
	var key := state.strip_edges().to_lower()
	var labels := {
		"locked": "LOCKED", "unavailable": "UNAVAILABLE", "loading": "LOADING…",
		"available": "AVAILABLE", "analyzed": "ANALYZED",
		"purchased": "PURCHASED", "owned": "OWNED / EQUIP", "equipped": "EQUIPPED",
		"success": "SUCCESS",
		"crafting": "CRAFTING…", "scanning": "SCANNING…",
		"restoring": "RESTORING…", "failed": "FAILED",
	}
	return {
		"state": key,
		"label": str(labels.get(key, key.to_upper())),
		"detail": detail,
		"disabled": key in ["locked", "unavailable", "loading", "crafting",
			"scanning", "restoring", "failed"],
	}

const _GLASS_SHADER := preload("res://assets/ui/glass_panel.gdshader")

static func glass_stylebox(raised: bool = false, border_alpha: float = 0.45,
		radius: int = RADIUS_PANEL) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS_BG_RAISED if raised else GLASS_BG
	sb.border_color = Color(BORDER_GOLD.r, BORDER_GOLD.g, BORDER_GOLD.b, border_alpha)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.72)
	sb.shadow_size = 16
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
			sb.bg_color = Color(0.022, 0.028, 0.025, 0.92)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.18)
		_:
			sb.bg_color = Color(0.045, 0.060, 0.048, 1.0)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.42)
	sb.set_border_width_all(1)
	if state == "pressed":
		sb.set_border_width_all(2)
	sb.set_corner_radius_all(RADIUS_BUTTON)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	return sb

static func focus_stylebox(accent: Color = EMBER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(RADIUS_BUTTON)
	sb.expand_margin_left = 3
	sb.expand_margin_right = 3
	sb.expand_margin_top = 3
	sb.expand_margin_bottom = 3
	return sb

## Dense, game-facing card chrome for loot, equipment, and merchant stock.
## A strong left rarity rail makes categories readable without relying on color
## alone; callers also provide a text rarity/status label.
static func item_card_stylebox(accent: Color = EMBER, selected: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.016, 0.027, 0.022, 1.0) if not selected \
		else Color(0.055, 0.075, 0.057, 1.0)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.74 if selected else 0.36)
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(RADIUS_CARD)
	sb.shadow_color = Color(0, 0, 0, 0.32)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 13
	sb.content_margin_bottom = 13
	return sb

static func icon_well_stylebox(accent: Color = EMBER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.004, 0.009, 0.008, 1.0)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.48)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

static func style_button(b: Button, accent: Color = EMBER) -> void:
	ensure_touch_target(b)
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, button_stylebox(state, accent))
	b.add_theme_stylebox_override("focus", focus_stylebox(accent))
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_font_size_override("font_size", 23)
	b.add_theme_color_override("font_hover_color", EMBER_BRIGHT)
	b.add_theme_color_override("font_pressed_color", EMBER)
	b.add_theme_color_override("font_disabled_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.30))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	b.add_theme_constant_override("outline_size", 2)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("shadow_offset_y", 2)

## Big primary action: ember-lit surface instead of dark glass.
static func style_primary_button(b: Button) -> void:
	ensure_touch_target(b)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := button_stylebox(state)
		match state:
			"normal":
				sb.bg_color = Color(0.74, 0.50, 0.16, 0.98)
				sb.border_color = Color(EMBER_BRIGHT.r, EMBER_BRIGHT.g, EMBER_BRIGHT.b, 0.65)
			"hover":
				sb.bg_color = Color(0.72, 0.49, 0.15, 0.97)
				sb.border_color = Color(EMBER_BRIGHT.r, EMBER_BRIGHT.g, EMBER_BRIGHT.b, 0.95)
			"pressed":
				sb.bg_color = Color(0.48, 0.31, 0.09, 1.0)
			"disabled":
				sb.bg_color = Color(0.30, 0.24, 0.14, 0.60)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", focus_stylebox(EMBER_BRIGHT))
	b.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.94))
	b.add_theme_color_override("font_pressed_color", Color(0.96, 0.86, 0.64))
	b.add_theme_color_override("font_disabled_color", Color(0.9, 0.87, 0.78, 0.35))
	b.add_theme_font_size_override("font_size", 23)
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
			if not is_zero_approx(rise):
				c.position.y = target_y + rise
			tw.tween_property(c, "modulate:a", 1.0, duration) \
				.set_delay(i * stagger) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if not is_zero_approx(rise):
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

static func ensure_touch_target(control: Control, minimum: float = TOUCH_TARGET_MIN) -> void:
	var current := control.custom_minimum_size
	control.custom_minimum_size = Vector2(maxf(current.x, minimum), maxf(current.y, minimum))

static func apply_accessibility_text_scale(root: Node, scale: float) -> void:
	## Store base sizes once so repeated settings changes never compound.
	if root == null or not is_instance_valid(root):
		return
	var clamped := clampf(scale, 1.0, 1.3)
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not (control is Label or control is Button \
				or control is LinkButton or control is CheckButton \
				or control is OptionButton):
			continue
		var base_size: int
		if control.has_meta("accessibility_base_font_size"):
			base_size = int(control.get_meta("accessibility_base_font_size"))
		else:
			base_size = maxi(1, control.get_theme_font_size("font_size"))
			control.set_meta("accessibility_base_font_size", base_size)
		control.add_theme_font_size_override("font_size", roundi(float(base_size) * clamped))

static func style_secondary_button(b: Button) -> void:
	ensure_touch_target(b)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := button_stylebox(state, SAGE)
		match state:
			"normal":   sb.bg_color = Color(0.028, 0.044, 0.034, 1.0)
			"hover":    sb.bg_color = Color(0.065, 0.100, 0.074, 1.0)
			"pressed":  sb.bg_color = Color(0.018, 0.032, 0.025, 1.0)
			"disabled": sb.bg_color = Color(0.020, 0.026, 0.023, 0.94)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", focus_stylebox(SAGE))
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", SAGE_BRIGHT)
	b.add_theme_color_override("font_pressed_color", SAGE)
	b.add_theme_color_override("font_disabled_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.25))
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_font_size_override("font_size", 23)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("shadow_offset_y", 2)

static func style_danger_button(b: Button) -> void:
	ensure_touch_target(b)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := button_stylebox(state, DANGER)
		match state:
			"normal":   sb.bg_color = Color(0.070, 0.045, 0.042, 0.50)
			"hover":    sb.bg_color = Color(0.100, 0.055, 0.048, 0.70)
			"pressed":  sb.bg_color = Color(0.045, 0.028, 0.026, 0.75)
			"disabled": sb.bg_color = Color(0.070, 0.045, 0.042, 0.22)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", focus_stylebox(DANGER))
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", DANGER_BRIGHT)
	b.add_theme_color_override("font_pressed_color", DANGER)
	b.add_theme_color_override("font_disabled_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.25))
	b.add_theme_constant_override("outline_size", 1)
	b.add_theme_font_size_override("font_size", 23)
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
	sb.border_color = Color(BORDER_GOLD.r, BORDER_GOLD.g, BORDER_GOLD.b, 0.82)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.72)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 3)
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
	over.self_modulate = Color(0.42, 0.28, 0.12, 0.10)
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
