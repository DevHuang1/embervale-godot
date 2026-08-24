extends CanvasLayer
class_name ForgeMenu

## === Divining Lens / Forge Menu ===
## Camera → Detection → Rarity Roll → Player names the relic and its three
## rites (Skill 1 / Skill 2 / Ultimate) → app-computed stats revealed.

@onready var game_state: GameState = GameState
@onready var scan_manager: ScanManager = ScanManager
@onready var audio: AudioManager = AudioManager

@onready var camera_view: SubViewportContainer = get_node_or_null("Root/VBox/CameraView")
@onready var camera_feed = get_node_or_null("Root/VBox/CameraView/SubViewport/CameraFeed")
@onready var pipeline: PanelContainer = $Root/VBox/Pipeline
@onready var result_panel: PanelContainer = $Root/VBox/Result
@onready var weapon_glyph: Label = $Root/VBox/Result/ResultVBox/WeaponGlyph
@onready var weapon_name: Label = $Root/VBox/Result/ResultVBox/WeaponName
@onready var weapon_stats: Label = $Root/VBox/Result/ResultVBox/WeaponStats
@onready var rarity_label: Label = $Root/VBox/Result/ResultVBox/RarityLabel
@onready var item_name_edit: LineEdit = $Root/VBox/Result/ResultVBox/ItemRow/ItemNameEdit
@onready var skill_edits: Array[LineEdit] = [
	$Root/VBox/Result/ResultVBox/Skill1Row/Skill1Edit,
	$Root/VBox/Result/ResultVBox/Skill2Row/Skill2Edit,
	$Root/VBox/Result/ResultVBox/UltimateRow/UltimateEdit,
]
@onready var kit_preview: Label = $Root/VBox/Result/ResultVBox/KitPreview
@onready var equip_button: Button = $Root/VBox/Result/ResultVBox/EquipButton
@onready var scan_button: Button = $Root/VBox/ScanButton
@onready var close_button: TextureButton = $Root/VBox/Header/CloseButton

var is_scanning: bool = false
var pending_base: Dictionary = {}
var pending_rarity: int = 0

func _ready() -> void:
	_connect_signals()
	
	close_button.pressed.connect(_on_close_pressed)
	scan_button.pressed.connect(_start_scan)
	equip_button.pressed.connect(_on_equip_pressed)
	InputManager.scan_pressed.connect(_on_scan_requested)
	item_name_edit.text_changed.connect(_on_name_input_changed)
	for edit in skill_edits:
		edit.text_changed.connect(_on_name_input_changed)

func _connect_signals() -> void:
	scan_manager.scan_started.connect(_on_scan_started)
	scan_manager.scan_completed.connect(_on_scan_completed)
	scan_manager.forge_completed.connect(_on_forge_completed)

func _on_close_pressed() -> void:
	if is_scanning:
		return
	visible = false
	_hide_result()

func _on_scan_requested() -> void:
	visible = true
	_start_scan()

func _start_scan() -> void:
	if is_scanning:
		return
	
	is_scanning = true
	pipeline.visible = true
	_hide_result()
	
	# Start camera on mobile
	if OS.has_feature("mobile") and camera_feed:
		camera_feed.start()
	
	scan_manager.start_scan()

func _on_scan_started() -> void:
	audio.play_ui_blip()

func _on_scan_completed(detected_class: String, confidence: float) -> void:
	# Camera feed will be stopped in ScanManager
	is_scanning = false
	pipeline.visible = false

func _on_forge_completed(weapon_id: String, rarity: int) -> void:
	_show_result(weapon_id, rarity)

func _show_result(weapon_id: String, rarity: int) -> void:
	var base := scan_manager.get_weapon_data(weapon_id)
	base.erase("skill")  # relic kits carry their own 3-slot template
	pending_base = base
	pending_rarity = clampi(rarity, 0, 4)
	
	var rarity_names := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
	var rarity_colors := [
		Color(0.58, 0.67, 0.65),
		Color(0.56, 0.67, 0.45),
		Color(0.4, 0.72, 0.7),
		Color(0.96, 0.84, 0.47),
		Color(0.96, 0.72, 0.29)
	]
	
	weapon_glyph.text = str(base.get("glyph", "✦"))
	rarity_label.text = "RARITY: %s" % rarity_names[pending_rarity]
	rarity_label.add_theme_color_override("font_color", rarity_colors[pending_rarity])
	
	# Seed the naming fields with sensible defaults the player can overwrite
	item_name_edit.text = str(base.get("name", ""))
	for i in skill_edits.size():
		skill_edits[i].text = ""
	_refresh_preview()
	
	result_panel.visible = true
	audio.play_loot_fanfare()

func _hide_result() -> void:
	result_panel.visible = false
	pending_base = {}

func _on_name_input_changed(_text: String = "") -> void:
	_refresh_preview()

## Live read-only stat reveal: numbers come straight from the same builder
## the equip path uses, so what you see is exactly what you wield.
func _refresh_preview() -> void:
	if pending_base.is_empty():
		return
	var def := RelicData.build_weapon_def(pending_base, pending_rarity,
		item_name_edit.text, _skill_name_inputs())
	weapon_name.text = def.name
	var parts := ["ATK %d · %s style" % [def.atk, str(def.style).to_upper()]]
	for i in def.skills.size():
		var sk: Dictionary = def.skills[i]
		var cd_text := "%ds" % int(sk.cooldown)
		if str(sk.type) == "whirl":
			parts.append("%s · %.2f× AoE · %s CD" % [sk.name, sk.dmg_mult, cd_text])
		elif str(sk.type) in ["explosion", "comet"]:
			parts.append("%s (ULT) · %.2f× blast · %s CD" % [sk.name, sk.dmg_mult, cd_text])
		else:
			parts.append("%s · %.2f× hit · %s CD" % [sk.name, sk.dmg_mult, cd_text])
	kit_preview.text = " · ".join(parts)

func _skill_name_inputs() -> Array:
	var names := []
	for edit in skill_edits:
		names.append(edit.text)
	return names

func _on_equip_pressed() -> void:
	if pending_base.is_empty():
		return
	game_state.forge_relic_weapon(pending_base, pending_rarity,
		item_name_edit.text, _skill_name_inputs())
	_hide_result()
	visible = false
	var satchel = get_tree().root.find_child("SatchelUI", true, false)
	if satchel:
		satchel.visible = true
