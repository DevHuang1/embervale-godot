extends Node

## === EnemyHealthBar — Boss / Elite HP Bar UI ===
## Preloaded and instantiated by BossBase._ready() as:
##   var health_bar := preload("res://scripts/ui/enemy_health_bar.gd").new()
##   health_bar.name = "EnemyHealthBar"
##   add_child(health_bar)
##
## Builds a floating ProgressBar + phase label above the entity.
## Works as both a world-space bar (Label3D) and a screen-space bar
## via a CanvasLayer — defaults to CanvasLayer for readability.
##
## Automatically connects to parent's:
##   hp / max_hp properties   — polled each frame (no signal needed)
##   is_defeated               — hides bar on death
##   current_phase             — shown in phase label

var _bar_root  : Control = null
var _bar       : ProgressBar = null
var _label     : Label = null
var _phase_lbl : Label = null
var _canvas    : CanvasLayer = null
var _entity    : Node3D = null
var _camera    : Camera3D = null

func _ready() -> void:
	_entity = get_parent() as Node3D
	if _entity == null:
		return
	_build_ui()
	_find_camera()

func _find_camera() -> void:
	if get_tree() == null: return
	await get_tree().process_frame
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		var scene := get_tree().current_scene
		if scene:
			_camera = scene.find_child("Camera3D", true, false) as Camera3D

# ─── UI Build ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 8   # Above world, below FloatingText
	add_child(_canvas)

	var vp_size := Vector2(1080, 1920)   # Match project viewport

	_bar_root = Control.new()
	_bar_root.name = "EnemyBarRoot"
	_bar_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_root.size = Vector2(720, 80)
	_bar_root.position = Vector2(vp_size.x * 0.5 - 360, 32)
	_canvas.add_child(_bar_root)

	# Background shadow
	var bg := ColorRect.new()
	bg.color  = Color(0.0, 0.0, 0.0, 0.55)
	bg.size   = Vector2(720, 52)
	bg.position = Vector2(0, 20)
	_bar_root.add_child(bg)

	# Boss name label
	_label = Label.new()
	_label.text          = _entity.name if _entity else "???"
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size      = Vector2(720, 22)
	_label.position  = Vector2(0, 0)
	_bar_root.add_child(_label)

	# HP bar
	_bar = ProgressBar.new()
	_bar.min_value   = 0
	_bar.max_value   = 1
	_bar.value       = 1
	_bar.show_percentage = false
	_bar.size        = Vector2(720, 28)
	_bar.position    = Vector2(0, 24)
	# Style
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.22, 0.08)
	fill.corner_radius_top_left    = 3
	fill.corner_radius_top_right   = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right= 3
	_bar.add_theme_stylebox_override("fill", fill)
	var bg2 := StyleBoxFlat.new()
	bg2.bg_color = Color(0.10, 0.06, 0.05)
	bg2.corner_radius_top_left    = 3
	bg2.corner_radius_top_right   = 3
	bg2.corner_radius_bottom_left = 3
	bg2.corner_radius_bottom_right= 3
	_bar.add_theme_stylebox_override("background", bg2)
	_bar_root.add_child(_bar)

	# Phase / guard label (shown below bar)
	_phase_lbl = Label.new()
	_phase_lbl.text = ""
	_phase_lbl.add_theme_font_size_override("font_size", 22)
	_phase_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	_phase_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_lbl.size     = Vector2(720, 20)
	_phase_lbl.position = Vector2(0, 54)
	_bar_root.add_child(_phase_lbl)

	_bar_root.visible = false

# ─── Per-frame update ─────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _bar_root == null or _entity == null or not is_instance_valid(_entity):
		return

	var defeated : bool = bool(_entity.get("is_defeated") if _entity.get("is_defeated") != null else false)
	if defeated:
		_bar_root.visible = false
		return

	var hp     := float(_entity.get("hp")     if _entity.get("hp")     != null else 0)
	var max_hp := float(_entity.get("max_hp") if _entity.get("max_hp") != null else 1)
	if max_hp <= 0:
		_bar_root.visible = false
		return

	_bar_root.visible = true
	_bar.value = hp / max_hp

	# Tint bar red at low HP
	var ratio := hp / max_hp
	var fill := _bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = Color(0.85, 0.22 * ratio, 0.08 * ratio)

	# Phase label (BossBase sets boss_phase_label.text externally,
	# but we also read current_phase for display)
	if _phase_lbl != null:
		var phase := _entity.get("current_phase")
		if phase != null:
			var phase_names := ["PHASE I", "PHASE II", "PHASE III", "ENRAGE"]
			_phase_lbl.text = phase_names[clampi(int(phase), 0, 3)]
		else:
			_phase_lbl.text = ""

	# Entity name (update once on first show)
	if _label != null and _label.text in ["", "???", "Node"]:
		var cls := _entity.get_class()
		# Friendly class name mapping
		var boss_names := {
			"HushlingMatriarch":    "The Matriarch",
			"MistfenSiltCrawler":  "Silt Crawler",
			"HeartwoodCinderColossus": "Cinder Colossus",
			"MoonfenVoidWeaver":   "Void Weaver",
			"BrambleThornWarden":  "Thorn Warden",
		}
		_label.text = boss_names.get(cls, _entity.name.replace("_", " "))

# ─── External API (called by BossBase) ────────────────────────────────────────

## BossBase._show_boss_health_bar() calls this (or we auto-show in _process).
func show() -> void:
	if _bar_root != null:
		_bar_root.visible = true

func hide_bar() -> void:
	if _bar_root != null:
		_bar_root.visible = false

## Called by BossBase when phase label text is set.
func set_phase_text(text: String) -> void:
	if _phase_lbl != null:
		_phase_lbl.text = text
