extends Control
class_name MainMenu

## === Main Menu — Embervale Start Screen ===
## Procedurally built (no .tscn assets needed for the overlay).
## Attaches to main scene root if found, or self-manages as CanvasLayer.
##
## Panels: Start, Load Game, Settings, Credits
## Visual: animated ember-glow background, title plate, version badge

signal game_start_requested
signal load_game_requested
signal settings_requested

var _panel_canvas : CanvasLayer = null
var _root_control : Control = null
var _title_label  : Label = null
var _subtitle     : Label = null
var _start_btn    : Button = null
var _load_btn     : Button = null
var _settings_btn : Button = null
var _credits_btn  : Button = null
var _version_lbl  : Label = null
var _bg           : ColorRect = null
var _has_save     : bool = false
var _t            : float = 0.0

func _ready() -> void:
	_check_save()
	_build_ui()
	_animate_in()

func _process(delta: float) -> void:
	_t += delta
	if _bg:
		var r := 0.043 + sin(_t * 0.4) * 0.012
		var g := 0.094 + sin(_t * 0.3 + 1.0) * 0.008
		var b := 0.078 + sin(_t * 0.5 + 2.0) * 0.010
		_bg.color = Color(r, g, b)

# ─── Save check ───────────────────────────────────────────────────────────────

func _check_save() -> void:
	var slm := get_node_or_null("/root/SaveLoadManager")
	_has_save = slm.call("has_save") if slm and slm.has_method("has_save") else false

# ─── Build UI ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel_canvas = CanvasLayer.new()
	_panel_canvas.layer = 10
	add_child(_panel_canvas)

	var vp := Vector2(1080, 1920)

	# Animated background
	_bg = ColorRect.new()
	_bg.color = Color(0.043, 0.094, 0.078)
	_bg.anchor_right  = 1.0
	_bg.anchor_bottom = 1.0
	_bg.size = vp
	_panel_canvas.add_child(_bg)

	# Ember particle overlay
	var p := GPUParticles2D.new()
	p.amount = 40; p.lifetime = 4.0; p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RECTANGLE
	pm.emission_rect_extents = Vector2(vp.x * 0.5, 10)
	pm.direction = Vector3(0, -1, 0); pm.spread = 20.0
	pm.initial_velocity_min = 60.0; pm.initial_velocity_max = 180.0
	pm.scale_min = 2.0; pm.scale_max = 6.0
	pm.color = Color(1.0, 0.55, 0.18, 0.55)
	p.process_material = pm
	p.position = Vector2(vp.x * 0.5, vp.y)
	_panel_canvas.add_child(p)

	# Title plate
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.corner_radius_top_left    = 12
	sb.corner_radius_top_right   = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right= 12
	plate.add_theme_stylebox_override("panel", sb)
	plate.size     = Vector2(800, 340)
	plate.position = Vector2(vp.x * 0.5 - 400, 280)
	_panel_canvas.add_child(plate)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "EMBERVALE"
	_title_label.add_theme_font_size_override("font_size", 88)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_subtitle = Label.new()
	_subtitle.text = "mobile"
	_subtitle.add_theme_font_size_override("font_size", 32)
	_subtitle.add_theme_color_override("font_color", Color(0.65, 0.75, 0.72))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_subtitle)

	# Buttons
	var btn_container := VBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 24)
	btn_container.size     = Vector2(420, 420)
	btn_container.position = Vector2(vp.x * 0.5 - 210, 700)
	_panel_canvas.add_child(btn_container)

	_start_btn    = _make_btn("BEGIN JOURNEY",     Color(0.85, 0.42, 0.12))
	_load_btn     = _make_btn("CONTINUE",          Color(0.32, 0.65, 0.42))
	_settings_btn = _make_btn("SETTINGS",          Color(0.35, 0.45, 0.55))
	_credits_btn  = _make_btn("CREDITS",           Color(0.28, 0.28, 0.32))

	_load_btn.visible = _has_save

	btn_container.add_child(_start_btn)
	btn_container.add_child(_load_btn)
	btn_container.add_child(_settings_btn)
	btn_container.add_child(_credits_btn)

	_start_btn.pressed.connect(_on_start)
	_load_btn.pressed.connect(_on_load)
	_settings_btn.pressed.connect(_on_settings)
	_credits_btn.pressed.connect(_on_credits)

	# Version badge
	_version_lbl = Label.new()
	_version_lbl.text = "v0.1 – Bramblewood"
	_version_lbl.add_theme_font_size_override("font_size", 22)
	_version_lbl.add_theme_color_override("font_color", Color(0.45, 0.55, 0.50))
	_version_lbl.position = Vector2(vp.x * 0.5 - 100, vp.y - 60)
	_panel_canvas.add_child(_version_lbl)

func _make_btn(text: String, col: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(420, 72)
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left     = 8
	sb.corner_radius_top_right    = 8
	sb.corner_radius_bottom_left  = 8
	sb.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = col.lightened(0.15)
	btn.add_theme_stylebox_override("hover", sb_h)
	return btn

func _animate_in() -> void:
	if _panel_canvas == null: return
	_panel_canvas.layer = 10
	modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_QUAD)

# ─── Button handlers ──────────────────────────────────────────────────────────

func _on_start() -> void:
	game_start_requested.emit()
	_fade_out(func(): _load_main_scene())

func _on_load() -> void:
	load_game_requested.emit()
	var slm := get_node_or_null("/root/SaveLoadManager")
	if slm and slm.has_method("load_save"):
		slm.call("bind", get_node("/root/GameState"))
		slm.call("load_save")
	_fade_out(func(): _load_main_scene())

func _on_settings() -> void:
	settings_requested.emit()
	# TODO: open settings panel

func _on_credits() -> void:
	if _subtitle:
		_subtitle.text = "A game by DevHuang1"
		var tw := create_tween()
		tw.tween_interval(3.0)
		tw.tween_callback(func(): if _subtitle: _subtitle.text = "mobile")

func _fade_out(callback: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(callback)

func _load_main_scene() -> void:
	var scene_path := "res://scenes/world/grove.tscn"
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		# Fallback: just hide the menu and let whatever is loaded run
		if _panel_canvas: _panel_canvas.visible = false
		queue_free()
