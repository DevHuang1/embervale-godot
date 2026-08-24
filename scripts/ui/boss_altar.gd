extends CanvasLayer
class_name BossAltar

## === Shape Your Foe — Boss Altar ===
## Pre-boss customization gate. Scan an object (or reuse the last capture),
## extract its palette, pick ONE skill from the boss's realm pool and an
## SFX preset, then Lock In to spend a scan. Declining keeps the default
## boss; cancel/close counts as declining and never consumes a scan.
##
## Emits `resolved(customized: bool)` exactly once, then the opener
## unpauses the world and frees this layer.

signal resolved(customized: bool)

@onready var game_state: GameState = GameState
@onready var scan_manager: ScanManager = ScanManager
@onready var audio: AudioManager = AudioManager

@onready var title_label: Label = $Root/VBox/Title
@onready var scan_line: Label = $Root/VBox/ScanLine
@onready var locked_blurb: Label = $Root/VBox/LockedBlurb
@onready var action_row: HBoxContainer = $Root/VBox/ActionRow
@onready var scan_button: Button = $Root/VBox/ActionRow/ScanButton
@onready var default_button: Button = $Root/VBox/ActionRow/DefaultButton
@onready var status_label: Label = $Root/VBox/Status
@onready var custom_box: VBoxContainer = $Root/VBox/CustomBox
@onready var palette_row: HBoxContainer = $Root/VBox/CustomBox/PaletteRow
@onready var skill_grid: GridContainer = $Root/VBox/CustomBox/SkillGrid
@onready var sfx_row: HBoxContainer = $Root/VBox/CustomBox/SfxRow
@onready var summary: Label = $Root/VBox/CustomBox/Summary
@onready var lock_button: Button = $Root/VBox/CustomBox/LockRow/LockButton
@onready var rescan_button: Button = $Root/VBox/CustomBox/LockRow/RescanButton

const BOSS_ID := "matriarch"
const PRESET_LABELS := {
	"hollow_resin": "HOLLOW RESIN",
	"grave_moss": "GRAVE MOSS",
	"ember_glass": "EMBER GLASS",
}

var practice := false
var _captured: Image = null
var _palette: Array[Color] = []
var _idol_mesh: Mesh = null
var _selected_skill: Dictionary = {}
var _selected_preset := "vanilla"
var _busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the world is paused behind us
	var def := Bestiary.boss_def(BOSS_ID)
	title_label.text = "SHAPE YOUR FOE"
	locked_blurb.text = str(def.get("locked_blurb", ""))
	scan_line.text = "You hold %d scan%s." % [game_state.scans_remaining,
		"" if game_state.scans_remaining == 1 else "s"]
	status_label.text = ""
	custom_box.visible = false
	lock_button.disabled = true
	rescan_button.visible = false

	scan_button.pressed.connect(_on_scan_pressed)
	default_button.pressed.connect(func(): _resolve(false))
	lock_button.pressed.connect(_on_lock_pressed)
	rescan_button.pressed.connect(_on_scan_pressed)
	_build_skill_cards()
	_build_sfx_buttons()

func _build_skill_cards() -> void:
	for sk in Bestiary.skill_pool(BOSS_ID):
		var btn := Button.new()
		btn.text = "%s\n%s" % [str(sk.name).to_upper(), str(sk.desc)]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(230, 84)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_on_skill_selected.bind(sk.get("id", ""), btn))
		skill_grid.add_child(btn)

func _build_sfx_buttons() -> void:
	for preset in Bestiary.boss_def(BOSS_ID).get("sfx_presets", []):
		var btn := Button.new()
		btn.text = PRESET_LABELS.get(str(preset), str(preset).to_upper())
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_on_preset_selected.bind(str(preset), btn))
		sfx_row.add_child(btn)

# === Scan flow ===
func _on_scan_pressed() -> void:
	if _busy:
		return
	_busy = true
	scan_button.disabled = true
	rescan_button.disabled = true
	status_label.text = "The lens drinks the light..."
	var img := await scan_manager.capture_frame(3.0)
	if img == null and scan_manager.last_capture != null:
		img = scan_manager.last_capture
	_busy = false
	scan_button.disabled = false
	rescan_button.disabled = false
	if img == null:
		status_label.text = "Lens dim — try again, or face the default."
		audio.play_ui_back()
		return
	_ingest_capture(img)

func _ingest_capture(img: Image) -> void:
	_captured = img
	_palette = RelicForge.extract_palette(img, 3)
	var forged := RelicForge.forge(img)
	_idol_mesh = forged.get("mesh")
	_paint_palette_swatches()
	custom_box.visible = true
	rescan_button.visible = true
	action_row.visible = false
	_refresh_lock()
	audio.play_loot_fanfare()

func _paint_palette_swatches() -> void:
	for child in palette_row.get_children():
		child.queue_free()
	for col in _palette:
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(44, 30)
		var style := StyleBoxFlat.new()
		style.bg_color = col
		style.set_corner_radius_all(4)
		swatch.add_theme_stylebox_override("panel", style)
		palette_row.add_child(swatch)

# === Selections ===
func _on_skill_selected(skill_id: String, btn: Button) -> void:
	for other in skill_grid.get_children():
		if other is Button and other != btn:
			other.button_pressed = false
	if not btn.button_pressed:
		_selected_skill = {}
	else:
		for sk in Bestiary.skill_pool(BOSS_ID):
			if str(sk.get("id", "")) == skill_id:
				_selected_skill = sk
				break
	audio.play_ui_blip()
	_refresh_lock()

func _on_preset_selected(preset: String, btn: Button) -> void:
	for other in sfx_row.get_children():
		if other is Button and other != btn:
			other.button_pressed = false
	_selected_preset = preset if btn.button_pressed else "vanilla"
	audio.play_profile_cue(_selected_preset, "cast")  # audible sample
	_refresh_lock()

func _refresh_lock() -> void:
	lock_button.disabled = _selected_skill.is_empty()
	if _selected_skill.is_empty():
		summary.text = "Choose one rite from her pool to complete the binding."
		return
	summary.text = "%s replaces %s · %d/%ds CD · SFX %s%s" % [
		str(_selected_skill.get("name", "")),
		str(Bestiary.boss_def(BOSS_ID).get("default_skill_label", "")),
		1, int(_selected_skill.get("cooldown", 12)),
		PRESET_LABELS.get(_selected_preset, "VANILLA"),
		" · idol bound" if _idol_mesh != null else "",
	]

# === Resolve ===
func _on_lock_pressed() -> void:
	if _selected_skill.is_empty():
		return
	if not game_state.consume_scan():
		status_label.text = "No scans remain — the default wakes."
		_resolve(false)
		return
	game_state.set_boss_custom(BOSS_ID, {
		"boss_id": BOSS_ID,
		"skill": _selected_skill,
		"sfx_preset": _selected_preset,
		"palette": _palette.map(func(c): return c.to_html(true)),
	})
	audio.play_victory()
	_resolve(true)

func _resolve(customized: bool) -> void:
	resolved.emit(customized)
