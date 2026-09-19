extends CanvasLayer
class_name ForgeMenu

## === Forge Menu — blueprint list, deterministic tiers, naming ===
## Weapons are forged from unlocked blueprints and exact material bills.
## No camera, no random detection: the tier the player pays for is the
## rarity they receive. Naming rights and the live stat preview stay.

const FORGE_CATALOG := preload("res://scripts/systems/forge_catalog.gd")

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager

@onready var result_panel: PanelContainer = $Root/VBox/Result
@onready var result_title: Label = $Root/VBox/Result/ResultVBox/ResultTitle
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
@onready var close_button: Button = $Root/Header/CloseButton
@onready var scan_count: Label = $Root/VBox/ScanCount

var pending_blueprint_id: String = ""
var pending_tier: int = 0
var discard_button: Button
var _blueprint_rows: Dictionary = {}
var _tier_buttons: Array[Button] = []
var _cost_label: Label = null
var _status_label: Label = null
var _blueprint_list_box: VBoxContainer = null

var _freeze_was_visible := false
var _freeze_held := false
var element_switcher: PanelContainer = null
var _result_spacer: Control = null
var element_status: Label = null
var element_buttons: Dictionary = {}
const ELEMENTS := ["fire", "frost", "shock", "nature"]
const ELEMENT_COLORS := {
	"fire": Color(1.0, 0.30, 0.10),
	"frost": Color(0.38, 0.84, 1.0),
	"shock": Color(0.76, 0.52, 1.0),
	"nature": Color(0.34, 1.0, 0.46),
}
const RARITY_COLORS := [
	Color(0.58, 0.67, 0.65),
	Color(0.56, 0.67, 0.45),
	Color(0.4, 0.72, 0.7),
	Color(0.96, 0.84, 0.47),
	Color(0.96, 0.72, 0.29),
]

func _poll_world_freeze() -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		game_state.push_world_freeze()
		_freeze_held = true
	else:
		_release_world_freeze()

func _process(_delta: float) -> void:
	_poll_world_freeze()

func _ready() -> void:
	$Root.add_theme_stylebox_override("panel", UiKit.glass_stylebox())
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.apply_parchment(result_panel, UiKit.RADIUS_BUTTON)
	UiKit.style_primary_button(equip_button)
	UiKit.style_button(close_button, UiKit.SAGE)
	_strip_retired_nodes()
	_build_blueprint_list()
	_build_tier_row()
	_build_element_switcher()
	_build_result_actions()
	_connect_signals()

	close_button.pressed.connect(_on_close_pressed)
	equip_button.pressed.connect(_on_forge_pressed)
	InputManager.scan_pressed.connect(_on_scan_requested)
	item_name_edit.text_changed.connect(_on_name_input_changed)
	for edit in skill_edits:
		edit.text_changed.connect(_on_name_input_changed)
	_apply_responsive_frame()
	get_viewport().size_changed.connect(_apply_responsive_frame)

func _strip_retired_nodes() -> void:
	for path in ["Root/VBox/CameraView", "Root/VBox/Pipeline", "Root/VBox/ScanButton"]:
		var node := get_node_or_null(path)
		if node != null:
			node.queue_free()

func _apply_responsive_frame() -> void:
	UiKit.apply_menu_frame(get_node_or_null("Root") as Control,
		get_viewport().get_visible_rect().size, 60.0, 60.0)

func _connect_signals() -> void:
	game_state.weapon_changed.connect(_refresh_element_switcher)
	game_state.gold_changed.connect(_on_element_forge_gold_changed)
	game_state.scans_changed.connect(_on_scans_changed)
	game_state.scan_fragments_changed.connect(_on_fragments_changed)
	game_state.materials_changed.connect(_on_materials_changed)
	_on_scans_changed(game_state.scans_remaining)
	_refresh_blueprint_list()

func _build_result_actions() -> void:
	discard_button = Button.new()
	discard_button.text = "CANCEL"
	discard_button.custom_minimum_size = Vector2(0, 48)
	UiKit.style_secondary_button(discard_button)
	discard_button.pressed.connect(_on_discard_pressed)
	$Root/VBox/Result/ResultVBox.add_child(discard_button)
	discard_button.visible = false
	_status_label = Label.new()
	_status_label.name = "ForgeStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_status_label, &"Caption", 18)
	$Root/VBox.add_child(_status_label)

func _build_blueprint_list() -> void:
	var panel := PanelContainer.new()
	panel.name = "BlueprintList"
	panel.add_theme_stylebox_override("panel", UiKit.glass_stylebox(false, 0.85))
	var scroll := ScrollContainer.new()
	scroll.name = "BlueprintScroll"
	scroll.custom_minimum_size = Vector2(0, 236)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_blueprint_list_box = VBoxContainer.new()
	_blueprint_list_box.name = "BlueprintBox"
	_blueprint_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blueprint_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_blueprint_list_box)

	var title := Label.new()
	title.text = "BLUEPRINTS"
	UiKit.style_label(title, &"Eyebrow", 20)
	_blueprint_list_box.add_child(title)

	for blueprint_id in FORGE_CATALOG.blueprint_ids():
		var button := Button.new()
		button.name = "%sBlueprint" % blueprint_id
		button.custom_minimum_size = Vector2(0, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_select_blueprint.bind(blueprint_id))
		_blueprint_list_box.add_child(button)
		_blueprint_rows[blueprint_id] = button

	var vbox := get_node_or_null("Root/VBox") as VBoxContainer
	if vbox != null:
		vbox.add_child(panel)
		vbox.move_child(panel, 0)

func _refresh_blueprint_list() -> void:
	for blueprint_id in _blueprint_rows:
		var button: Button = _blueprint_rows[blueprint_id]
		var base: Dictionary = game_state.WEAPON_DEFS.get(blueprint_id, {})
		var progress: Dictionary = game_state.blueprint_progress(blueprint_id)
		var unlocked := bool(progress.get("unlocked", false))
		var display_name := str(base.get("name", blueprint_id))
		var element := str(base.get("element", "")).to_upper()
		if str(blueprint_id) == pending_blueprint_id:
			display_name = "▸ %s" % display_name
		if unlocked:
			button.text = "%s · %s\nREADY — choose a forge tier" % [display_name, element]
			button.disabled = false
			button.tooltip_text = "ATK %s · %s · %s" % [
				str(base.get("atk", "?")), str(base.get("style", "")).to_upper(),
				"Unlocked"]
		else:
			button.text = "%s · %s\nLOCKED — %s (%d/%d)" % [display_name, element,
				str(progress.get("label", "")), int(progress.get("current", 0)),
				int(progress.get("required", 1))]
			button.disabled = true
			button.tooltip_text = str(progress.get("label", ""))

func _build_tier_row() -> void:
	var panel := PanelContainer.new()
	panel.name = "TierRow"
	panel.add_theme_stylebox_override("panel", UiKit.glass_stylebox(false, 0.85))
	var box := VBoxContainer.new()
	box.name = "TierBox"
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "FORGE TIER · THE TIER YOU PAY FOR IS THE RARITY YOU GET"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(title, &"Eyebrow", 18)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.name = "TierButtons"
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for index in FORGE_CATALOG.tier_count():
		var button := Button.new()
		button.name = "%sTier" % str(FORGE_CATALOG.tier_name(index))
		button.custom_minimum_size = Vector2(0, 50)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = str(FORGE_CATALOG.tier_name(index)).to_upper()
		button.pressed.connect(_on_tier_pressed.bind(index))
		row.add_child(button)
		_tier_buttons.append(button)

	_cost_label = Label.new()
	_cost_label.name = "TierCost"
	_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_cost_label, &"Caption", 18)
	box.add_child(_cost_label)

	var result_vbox := $Root/VBox/Result/ResultVBox as VBoxContainer
	result_vbox.add_child(panel)
	result_vbox.move_child(panel, rarity_label.get_index() + 1)

func _on_tier_pressed(index: int) -> void:
	pending_tier = clampi(index, 0, FORGE_CATALOG.tier_count() - 1)
	audio.play_ui_blip()
	_refresh_preview()

func _refresh_tier_buttons() -> void:
	for index in _tier_buttons.size():
		var button := _tier_buttons[index]
		var selected := index == pending_tier
		var accent: Color = RARITY_COLORS[clampi(index, 0, RARITY_COLORS.size() - 1)]
		if selected:
			button.add_theme_stylebox_override("normal", UiKit.role_stylebox("tab", "selected", accent))
			button.add_theme_stylebox_override("disabled", UiKit.role_stylebox("tab", "selected", accent))
		UiKit.style_role_button(button, "tab", accent, 18)
		if selected:
			button.add_theme_stylebox_override("normal", UiKit.role_stylebox("tab", "selected", accent))
			button.add_theme_stylebox_override("disabled", UiKit.role_stylebox("tab", "selected", accent))

func _select_blueprint(blueprint_id: String) -> void:
	pending_blueprint_id = blueprint_id
	pending_tier = clampi(pending_tier, 0, FORGE_CATALOG.tier_count() - 1)
	var base: Dictionary = game_state.WEAPON_DEFS.get(blueprint_id, {})
	if base.is_empty():
		return
	var progress: Dictionary = game_state.blueprint_progress(blueprint_id)
	if not bool(progress.get("unlocked", false)):
		_set_status("Blueprint locked · %s" % str(progress.get("label", "")))
		audio.play_ui_blip()
		return
	result_title.text = "FORGE THE RELIC"
	item_name_edit.text = str(base.get("name", ""))
	for edit in skill_edits:
		edit.text = ""
	_paint_weapon_icon(blueprint_id)
	_refresh_blueprint_list()
	_refresh_preview()
	result_panel.visible = true
	if _result_spacer != null and is_instance_valid(_result_spacer):
		_result_spacer.visible = false
	if discard_button != null:
		discard_button.visible = true
	_set_status("")
	audio.play_ui_blip()

func _paint_weapon_icon(weapon_id: String) -> void:
	var old_icon := weapon_glyph.get_parent().get_node_or_null("WeaponIcon")
	if old_icon != null:
		old_icon.queue_free()
	var weapon_icon := IconRegistry.icon_for(weapon_id)
	if weapon_icon != null:
		var icon_view := TextureRect.new()
		icon_view.name = "WeaponIcon"
		icon_view.texture = weapon_icon
		icon_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_view.custom_minimum_size = Vector2(72, 72)
		weapon_glyph.visible = false
		weapon_glyph.get_parent().add_child(icon_view)
	else:
		weapon_glyph.visible = true
	UiKit.style_label(weapon_glyph, &"Title", 56)

func _hide_result() -> void:
	result_panel.visible = false
	if _result_spacer != null and is_instance_valid(_result_spacer):
		_result_spacer.visible = true
	pending_blueprint_id = ""
	if discard_button != null:
		discard_button.visible = false
	_refresh_blueprint_list()

func _on_close_pressed() -> void:
	visible = false
	_hide_result()

func _on_scan_requested() -> void:
	visible = true
	_refresh_blueprint_list()
	if pending_blueprint_id.is_empty():
		for blueprint_id in FORGE_CATALOG.blueprint_ids():
			if game_state.is_blueprint_unlocked(blueprint_id):
				_select_blueprint(blueprint_id)
				break

func _on_scans_changed(remaining: int) -> void:
	if scan_count == null:
		return
	scan_count.text = "LENS CHARGES: %d · SHARDS: %d/%d" % [remaining,
		game_state.scan_fragments, game_state.SCAN_FRAGMENTS_PER_SCAN]
	scan_count.add_theme_color_override("font_color",
		Color(0.95, 0.78, 0.42) if remaining > 0 else Color(0.92, 0.40, 0.34))

func _on_fragments_changed(_fragments: int) -> void:
	_on_scans_changed(game_state.scans_remaining)

func _on_materials_changed() -> void:
	if result_panel.visible:
		_refresh_preview()
	_refresh_blueprint_list()

func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message

func _on_name_input_changed(_text: String = "") -> void:
	_refresh_preview()

func _refresh_preview() -> void:
	if pending_blueprint_id.is_empty():
		return
	var base: Dictionary = game_state.WEAPON_DEFS.get(pending_blueprint_id, {})
	if base.is_empty():
		return
	var def := RelicData.build_weapon_def(base, pending_tier, item_name_edit.text,
		_skill_name_inputs())
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
	weapon_stats.text = " · ".join(parts)

	rarity_label.text = "RARITY: %s" % str(FORGE_CATALOG.tier_name(pending_tier)).to_upper()
	rarity_label.add_theme_color_override("font_color",
		RARITY_COLORS[clampi(pending_tier, 0, RARITY_COLORS.size() - 1)])

	var cost := FORGE_CATALOG.tier_cost(pending_tier)
	var cost_parts: Array[String] = []
	var affordable := true
	for mat_id in cost:
		var needed := int(cost[mat_id])
		var have := game_state.get_material_qty(str(mat_id))
		if have < needed:
			affordable = false
		cost_parts.append("%d %s (%d)" % [needed,
			str(game_state.MATERIAL_DEFS.get(str(mat_id), {}).get("name", mat_id)), have])
	_cost_label.text = "COST · %s%s" % [", ".join(cost_parts),
		"" if affordable else " · MISSING MATERIALS"]
	_cost_label.add_theme_color_override("font_color",
		UiKit.CREAM if affordable else UiKit.BLOOD)
	kit_preview.text = "The forge fixes every number — names are yours alone."
	_refresh_tier_buttons()
	equip_button.disabled = not affordable

func _skill_name_inputs() -> Array:
	var names := []
	for edit in skill_edits:
		names.append(edit.text)
	return names

func _on_forge_pressed() -> void:
	if pending_blueprint_id.is_empty():
		return
	var forged: Dictionary = game_state.forge_blueprint(pending_blueprint_id,
		pending_tier, item_name_edit.text, _skill_name_inputs())
	if bool(forged.get("success", false)):
		var def: Dictionary = forged.get("def", {})
		audio.play_forge_success()
		_set_status("FORGED · %s · %s" % [str(def.get("name", "")),
			str(FORGE_CATALOG.tier_name(int(forged.get("tier", 0)))).to_upper()])
		_hide_result()
	else:
		_set_status(str(forged.get("message", "The forge refused the rite.")))
		audio.play_ui_blip()
	_refresh_blueprint_list()

func _on_discard_pressed() -> void:
	_hide_result()
	_set_status("Selection cleared. No materials were spent.")
	audio.play_ui_back()

func _build_element_switcher() -> void:
	element_switcher = PanelContainer.new()
	element_switcher.name = "ElementSwitcher"
	element_switcher.add_theme_stylebox_override("panel", UiKit.glass_stylebox(false, 0.85))
	var box := VBoxContainer.new()
	box.name = "AttunementBox"
	box.add_theme_constant_override("separation", 8)
	element_switcher.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var title := Label.new()
	title.text = "CHECKPOINT ATTUNEMENT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiKit.style_label(title, &"Eyebrow", 20)
	title.add_theme_color_override("font_color", UiKit.MOON_BRIGHT)
	head.add_child(title)
	head.add_child(UiKit.badge("%d GOLD" % GameState.ELEMENT_SWITCH_COST, UiKit.COPPER, 18))

	var row := HBoxContainer.new()
	row.name = "AttunementRow"
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for element in ELEMENTS:
		var button := Button.new()
		button.name = "%sButton" % element.capitalize()
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = element.to_upper()
		button.pressed.connect(_on_element_pressed.bind(element))
		row.add_child(button)
		element_buttons[element] = button

	element_status = Label.new()
	element_status.name = "AttunementStatus"
	element_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(element_status, &"Caption", 18)
	box.add_child(element_status)
	_result_spacer = Control.new()
	_result_spacer.name = "ResultSpacer"
	_result_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root/VBox.add_child(_result_spacer)
	$Root/VBox.add_child(element_switcher)
	_refresh_element_switcher()

func _refresh_element_switcher(_weapon: Dictionary = {}) -> void:
	if element_status == null:
		return
	var current := str(game_state.equipped_weapon.get("element", ""))
	if current.is_empty():
		current = "none"
	var can_afford := game_state.gold >= GameState.ELEMENT_SWITCH_COST
	element_status.text = "CURRENT: %s · GOLD %d%s" % [current.to_upper(), game_state.gold,
		"" if can_afford else " · NEED %d MORE" % (GameState.ELEMENT_SWITCH_COST - game_state.gold)]
	element_status.add_theme_color_override("font_color",
		Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.72) if can_afford else UiKit.BLOOD)
	for element in element_buttons:
		var button: Button = element_buttons[element]
		var same_element: bool = str(element) == current
		var state := UiKit.action_state("equipped" if same_element else ("available" if can_afford else "unavailable"),
			"Already attuned" if same_element else ("Need %d more gold" %
			(GameState.ELEMENT_SWITCH_COST - game_state.gold) if not can_afford else
			"Costs %d gold · binds %s" % [GameState.ELEMENT_SWITCH_COST, element.to_upper()]))
		button.disabled = bool(state.get("disabled", false))
		button.text = "%s%s" % [element.to_upper(), "  ✓" if same_element else ""]
		button.tooltip_text = "%s · %s" % [str(state.get("label", "")),
			str(state.get("detail", ""))]
		var role := "tab"
		var accent: Color = UiKit.VERDIGRIS if same_element else (ELEMENT_COLORS[element] as Color)
		if same_element:
			button.add_theme_stylebox_override("normal", UiKit.role_stylebox(role, "selected", accent))
			button.add_theme_stylebox_override("disabled", UiKit.role_stylebox(role, "selected", accent))
		UiKit.style_role_button(button, role, accent, 22)
		if same_element:
			button.add_theme_stylebox_override("normal", UiKit.role_stylebox(role, "selected", accent))
			button.add_theme_stylebox_override("disabled", UiKit.role_stylebox(role, "selected", accent))

func _on_element_forge_gold_changed(_gold: int) -> void:
	_refresh_element_switcher()

func _on_element_pressed(element: String) -> void:
	var restoring := UiKit.action_state("restoring", "Binding elemental payload")
	element_status.text = "%s\n%s" % [str(restoring.get("label", "RESTORING…")),
		str(restoring.get("detail", ""))]
	var result: Dictionary = game_state.switch_weapon_element(element)
	var final_state := UiKit.action_state("purchased" if bool(result.get("success", false)) else "failed",
		"Saved immediately" if bool(result.get("success", false)) else "No gold was deducted")
	element_status.text = "%s · %s" % [str(final_state.get("label", "FAILED")),
		str(result.get("message", ""))]
	if bool(result.get("success", false)):
		audio.play_forge_success()
	else:
		audio.play_ui_blip()
	_refresh_element_switcher()

func _exit_tree() -> void:
	_release_world_freeze()

func _release_world_freeze() -> void:
	if not _freeze_held:
		return
	_freeze_held = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("pop_world_freeze"):
		gs.call("pop_world_freeze")
