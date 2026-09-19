extends CanvasLayer
class_name HUD

const BOSS_REWARD_CHOICE_PANEL := preload("res://scripts/ui/boss_reward_choice_panel.gd")
const REWARD_REVEAL_PANEL := preload("res://scripts/ui/reward_reveal_panel.gd")
const REWARD_REVEAL_MODEL := preload("res://scripts/systems/reward_reveal_model.gd")
const DISCOVERY_CARD := preload("res://scripts/ui/discovery_card.gd")
const DISCOVERY_DIRECTOR := preload("res://scripts/systems/discovery_director.gd")

## === HUD — Full Embervale Combat + Quest Interface ===

@onready var game_state : GameState = GameState
@onready var input_manager: Node = get_node_or_null("/root/InputManager")
@onready var warmth_bar : ProgressBar = $Root/PlayerPlate/PlateVBox/WarmthBar
@onready var warmth_text : Label = $Root/PlayerPlate/PlateVBox/PlateHeader/WarmthText
@onready var exp_bar : ProgressBar = $Root/PlayerPlate/PlateVBox/ExpBar
@onready var level_badge : Label = $Root/PlayerPlate/PlateVBox/PlateHeader/LevelBadge
@onready var gold_label : Label = $Root/MetaRow/TopRow/GoldLabel
@onready var diamond_label : Label = $Root/MetaRow/TopRow/DiamondLabel
@onready var settings_button : Button = $Root/MetaRow/TopRow/SettingsButton
@onready var top_row : HBoxContainer = $Root/MetaRow/TopRow
@onready var action_row : HBoxContainer = $Root/MetaRow/ActionRow
@onready var satchel_button : Button = $Root/MetaRow/ActionRow/SatchelButton
@onready var scan_button : Button = $Root/MetaRow/ActionRow/ScanButton
@onready var shop_button : Button = $Root/MetaRow/ActionRow/ShopButton
@onready var stats_button : Button = $Root/MetaRow/ActionRow/StatsButton
@onready var field_note : Label = $Root/FieldNote
@onready var combat_card : PanelContainer = $Root/CombatCard
@onready var enemy_name : Label = $Root/CombatCard/CombatVBox/EnemyName
@onready var enemy_hp_bar : ProgressBar = $Root/CombatCard/CombatVBox/EnemyHPBar
@onready var combat_status : Label = $Root/CombatCard/CombatVBox/CombatStatus
@onready var target_direction_label : Label = $Root/CombatCard/CombatVBox/TargetDirectionLabel
@onready var enemy_scan_button : Button = $Root/CombatCard/CombatVBox/EnemyScanButton
@onready var target_switch_button : Button = $Root/CombatCard/CombatVBox/TargetSwitchButton
## Elemental buildup readout. Built in code and parented into the combat card,
## which is where the elite-status validation expects to find it.
var elemental_hud: ElementalHud = null
@onready var boss_health_bar : PanelContainer = $Root/BossHealthBar
@onready var boss_name : Label = $Root/BossHealthBar/BossName
@onready var boss_hp_bar : ProgressBar = $Root/BossHealthBar/BossHPBar
@onready var phase_indicator : Label = $Root/BossHealthBar/PhaseIndicator
@onready var loot_toast : PanelContainer = $Root/LootToast
@onready var loot_count : Label = $Root/LootToast/LootVBox/LootCount
@onready var loot_title : Label = $Root/LootToast/LootVBox/LootTitle
@onready var loot_notice : Label = $Root/LootToast/LootVBox/LootNotice
@onready var chapter_label : Label = $Root/QuestLedger/QuestLedgerVBox/ChapterLabel
@onready var title_label : Label = $Root/QuestLedger/QuestLedgerVBox/TitleLabel
@onready var instruction_label : Label = $Root/QuestLedger/QuestLedgerVBox/InstructionLabel
@onready var objective_label : Label = $Root/QuestLedger/QuestLedgerVBox/ObjectiveLabel
@onready var checkpoint_label : Label = $Root/QuestLedger/QuestLedgerVBox/CheckpointLabel
@onready var lesson_button : Button = $Root/QuestLedger/QuestLedgerVBox/LessonButton
@onready var quest_ledger: PanelContainer = $Root/QuestLedger
@onready var player_plate: PanelContainer = $Root/PlayerPlate
## Authored chrome that previously had no runtime owner: the satchel badge and
## the level-up banner were dead nodes, and GLINT was a button with no handler.
@onready var satchel_count: Label = get_node_or_null("Root/MetaRow/ActionRow/SatchelButton/SatchelCount")
@onready var glint_button: Button = get_node_or_null("Root/MetaRow/ActionRow/GlintButton")
@onready var level_toast: PanelContainer = get_node_or_null("Root/LevelToast")
@onready var toast_title: Label = get_node_or_null("Root/LevelToast/ToastVBox/ToastTitle")
@onready var toast_sub: Label = get_node_or_null("Root/LevelToast/ToastVBox/ToastSub")
var _level_toast_tween: Tween = null
var journal_button: Button
var journal_panel: PanelContainer
var _reward_history: Array[String] = []
var _reward_reveal_panel: RewardRevealPanel = null
const REWARD_HISTORY_CAP := 8
const MAX_REWARD_POPUPS := 4
var _reward_popup_queue: Array[Dictionary] = []
var _reward_popup_active := false
var _reward_popup_serial := 0
## First-encounter introductions. The director owns the trigger; the HUD owns
## presentation and queues at most three so a crowded camp cannot flood it.
const MAX_DISCOVERY_CARDS := 3
var _discovery_director: Node = null
var _discovery_queue: Array[Dictionary] = []
var _discovery_active := false
var _discovery_serial := 0
@onready var skill_buttons : Array = []
@onready var skill_glyph_labels : Array = []
@onready var skill_cd_labels : Array = []

var _loot_toast_timer : float = 0.0
var _loot_toast_tween: Tween = null
var _field_note_queue : Array = []
var _field_note_timer : float = 0.0
var _field_note_visible := false
var _last_onboarding_hint := ""
var _active_boss : Node3D = null
var _boss_telegraph_until_ms: int = 0
var _analyzed_enemy_id: int = 0
var _activity_line: Label = null
var _activity_poll_in: float = 0.0
var _interact_button: FightButton = null
var _interact_label: Label = null
var _interact_verb := ""
var _interact_poll_in: float = 0.0
var _actions_toggle: Button = null
var _compact_actions_open: bool = false
var _left_handed_applied := false
## The left-side quest ledger folds down to a one-line objective strip so the
## player can reclaim the corner for the touch controls. The folded state is a
## presentation preference and persists beside the mobile-control settings.
var _ledger_header: HBoxContainer = null
var _ledger_summary: Label = null
var _ledger_toggle: Button = null
var _route_pulse: PanelContainer = null
var _ledger_minimized := false
## Redirectable settings path, the same seam QualityScaler and CameraRig expose
## so tests never write the player's real preferences.
var settings_path: String = AudioManager.SETTINGS_PATH

## The contextual interact button is the only visible affordance for opening
## chests and starting gathers on touch: keyboard Space and an on-screen
## double-tap both exist, but neither is discoverable. Poll fast enough to
## feel live without re-scanning the interactable group every frame.
const INTERACT_POLL_SECONDS := 0.2
## Authored slot directly left of the JUMP button, clear of the skill row.
const INTERACT_BUTTON_RECT := Rect2(-308.0, -480.0, 100.0, 100.0)

## Minimized-ledger preference. Lives in the settings file's own section so it
## survives across sessions without touching save progress.
const LEDGER_SETTINGS_SECTION := "hud"
const LEDGER_MINIMIZED_KEY := "quest_ledger_minimized"

## Wide-bar frame limits. Narrow portrait viewports clamp these instead of
## letting the boss bar or the currency row run off the screen edge. Values
## match the authored desktop layout so nothing moves when there is room.
const FRAME_MARGIN := 20.0
const LOOT_TOAST_MARGIN := 24.0
const BOSS_BAR_MAX_WIDTH := 660.0
const COMBAT_CARD_MAX_WIDTH := 430.0
const META_ROW_MAX_WIDTH := 600.0

## Action cluster metrics. The cluster is positioned in code so sizes and gaps
## are identical on every viewport instead of drifting per scene authoring.
const SKILL_BUTTON_SIZE := 116.0
const ACTION_BUTTON_SIZE := 176.0
const ACTION_GAP := 14.0
const ACTION_MARGIN := 16.0

const SKILL_RUNES := {
	"aoe": "AOE",
	"explosion": "BLAST",
	"heal_bloom": "HEAL",
	"strike": "SLASH",
	"whirl": "WHIRL",
	"dash_strike": "DASH",
	"comet": "COMET",
	"heavy_aoe": "HEAVY",
}

func _ready() -> void:
	call_deferred("_connect_dungeon_completion")
	# Built before the preference pass so action scale, opacity, and the
	# left-handed mirror treat it exactly like the authored combat controls.
	_build_interact_button()
	_apply_mobile_control_preferences()
	# The joystick owns pointer capture and deadzone shaping; forward its
	# already-normalized output through the same movement signal used by
	# keyboard/gamepad input. Without this bridge the control rendered and
	# moved its knob, but the Hero never received a direction.
	var move_joystick := get_node_or_null("Root/MoveJoystick")
	if move_joystick != null and input_manager != null \
			and move_joystick.has_signal("direction_changed"):
		move_joystick.direction_changed.connect(
			func(direction: Vector2) -> void: input_manager.move_input.emit(direction))
	# The expanded realm map grows over the player plate. Yield the plate while
	# the map is open so neither overlaps, and restore it on collapse.
	var minimap := get_node_or_null("Root/MinimapContainer")
	if minimap != null and minimap.has_signal("minimap_toggled"):
		minimap.minimap_toggled.connect(_on_minimap_toggled)
	# Skill bar buttons - lazy find
	for i in 3:
		var btn = get_node_or_null("Root/SkillBar/Skill%dButton" % i)
		var glyph = btn.get_node_or_null("Skill%dGlyph" % i) if btn else null
		var cd = btn.get_node_or_null("Skill%dCooldown" % i) if btn else null
		skill_buttons.append(btn)
		skill_glyph_labels.append(glyph)
		skill_cd_labels.append(cd)
		if cd != null:
			UiKit.style_label(cd, &"RowLabel", 22)
		if btn:
			var idx := i
			if btn is FightButton:
				btn.fight_pressed.connect(func(): input_manager.skill_slot_pressed.emit(idx))
			elif btn is BaseButton:
				btn.pressed.connect(func(): input_manager.skill_slot_pressed.emit(idx))
	_build_elemental_hud()
	_wire_action_buttons()
	_build_camp_button()
	_build_compact_actions_toggle()
	_build_quest_ledger_toggle()
	_apply_hud_chrome()
	_build_activity_line()
	_build_journal_button()
	_restore_ledger_preference()
	get_viewport().size_changed.connect(_layout_journal_panel)
	get_viewport().size_changed.connect(_layout_route_ledger)
	get_viewport().size_changed.connect(_layout_compact_actions)
	get_viewport().size_changed.connect(_apply_frame_layout)
	_apply_frame_layout()
	_layout_route_ledger()
	_layout_compact_actions()
	call_deferred("_layout_route_ledger")
	call_deferred("_apply_frame_layout")
	_enforce_touch_targets()
	_connect_signals()
	_refresh_all()
	# The world may not be registered as the current scene yet, so confirm the
	# Glintmonger entry point once the tree has settled.
	call_deferred("_update_glint_visibility")
	_queue_onboarding_hint()
	if combat_card: combat_card.visible = false
	if boss_health_bar: boss_health_bar.visible = false
	if loot_toast: loot_toast.visible = false
	_apply_touch_target_scale()
	_setup_discovery()

## First meetings are watched by a small director that shares the HUD's world,
## so every realm gets intros without each scene wiring its own trigger.
func _setup_discovery() -> void:
	if _discovery_director != null and is_instance_valid(_discovery_director):
		return
	var world := get_parent() as Node3D
	if world == null:
		return
	_discovery_director = DISCOVERY_DIRECTOR.new()
	_discovery_director.name = "DiscoveryDirector"
	add_child(_discovery_director)
	_discovery_director.call("setup", world)
	_discovery_director.connect("record_discovered", _on_record_discovered)

func _on_record_discovered(record: Dictionary) -> void:
	var active_count: int = 1 if _discovery_active else 0
	if _discovery_queue.size() + active_count >= MAX_DISCOVERY_CARDS:
		return
	_discovery_queue.append(record.duplicate())
	_show_next_discovery()

func _show_next_discovery() -> void:
	if _discovery_active or _discovery_queue.is_empty():
		return
	var record: Dictionary = _discovery_queue.pop_front()
	_discovery_active = true
	_discovery_serial += 1
	var wrapper := Control.new()
	wrapper.name = "DiscoveryCardSlot_%d" % _discovery_serial
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card: DiscoveryCard = DISCOVERY_CARD.new()
	card.name = "DiscoveryCard"
	var card_width := _discovery_card_width()
	card.custom_minimum_size = Vector2(card_width, 0.0)
	# Right side, below the combat card and the loot/level toasts. The
	# introduction must never cover the fight it is describing, and the top
	# centre already belongs to the enemy plate.
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -card_width - FRAME_MARGIN
	card.offset_right = -FRAME_MARGIN
	card.offset_top = 430.0
	wrapper.add_child(card)
	(_root_control() as Control).add_child(wrapper)
	card.dismissed.connect(func() -> void:
		if is_instance_valid(wrapper):
			wrapper.queue_free()
		_discovery_active = false
		call_deferred("_show_next_discovery"))
	card.open_for(record)
	_play_discovery_focus(record)

func _discovery_card_width() -> float:
	var viewport_width := get_viewport().get_visible_rect().size.x
	return clampf(viewport_width - 2.0 * FRAME_MARGIN, 280.0, 520.0)

func _root_control() -> Node:
	return get_node_or_null("Root")

## Places get the small camera beat (a calm moment worth framing); creatures
## never take the camera, because the meeting is usually the start of a fight.
func _play_discovery_focus(record: Dictionary) -> void:
	if str(record.get("type", "")) != "structure":
		return
	if not _discovery_motion_allows_focus():
		return
	# A sweep while a fight is live would take the camera exactly when the
	# player needs it; the card still introduces the place.
	if game_state != null and int(game_state.combat_state) == GameState.CombatState.COMBAT:
		return
	var focus := record.get("node") as Node3D
	if focus == null or not is_instance_valid(focus):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var camera_rig := scene.get_node_or_null("CameraRig")
	var hero := scene.get_node_or_null("Hero") as Node3D
	if camera_rig == null or not camera_rig.has_method("play_focus_moment"):
		return
	var focus_offset := Vector3(0.0, 1.4, 0.0)
	var anchor := focus.global_position + focus_offset + Vector3(0.0, 1.0, 5.0)
	if hero != null and is_instance_valid(hero):
		var toward_hero := hero.global_position - focus.global_position
		toward_hero.y = 0.0
		if toward_hero.length() > 0.5:
			anchor = focus.global_position + focus_offset \
				+ toward_hero.normalized() * 5.0 + Vector3(0.0, 1.0, 0.0)
	camera_rig.call("play_focus_moment", focus, anchor, focus_offset, 1.6)

## Reduced-motion and off keep the information and drop the camera move.
func _discovery_motion_allows_focus() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	var camera_rig := scene.get_node_or_null("CameraRig")
	if camera_rig == null:
		return true
	var feedback := str(camera_rig.get("feedback_mode"))
	return feedback != "off" and feedback != "reduced"


func _connect_dungeon_completion() -> void:
	var expansion := get_tree().root.find_child("RealmExpansion", true, false)
	if expansion == null or not expansion.has_signal("dungeon_completed"):
		return
	if not expansion.dungeon_completed.is_connected(_on_dungeon_completed):
		expansion.dungeon_completed.connect(_on_dungeon_completed)

## Keeps the expanded map from stacking on top of the vitals plate.
func _on_minimap_toggled(expanded: bool) -> void:
	var plate := get_node_or_null("Root/PlayerPlate") as Control
	if plate != null:
		plate.visible = not expanded

func _on_dungeon_completed(dungeon_id: String) -> void:
	var entries: Array[Dictionary] = [{
		"id": dungeon_id,
		"label": "%s CLEARED" % dungeon_id.replace("_", " ").to_upper(),
		"quantity": 1,
		"rarity": 3,
	}]
	_show_reward_reveal_entries(entries, "dungeon")

func _show_reward_reveal_entries(entries: Array[Dictionary], source: String) -> void:
	_enqueue_reward_popup(entries, source)

func _enqueue_reward_popup(entries: Array, source: String,
		title_override: String = "", subtitle: String = "") -> void:
	var active_count: int = 1 if _reward_popup_active else 0
	if entries.is_empty() or _reward_popup_queue.size() + active_count >= MAX_REWARD_POPUPS:
		return
	_reward_popup_queue.append({"entries": entries.duplicate(true), "source": source,
		"title": title_override, "subtitle": subtitle})
	_show_next_reward_popup()

func _show_next_reward_popup() -> void:
	if _reward_popup_active or _reward_popup_queue.is_empty():
		return
	var item: Dictionary = _reward_popup_queue.pop_front()
	var entries: Array = item.get("entries", [])
	if entries.is_empty():
		_show_next_reward_popup()
		return
	_reward_popup_active = true
	var wrapper := CenterContainer.new()
	_reward_popup_serial += 1
	wrapper.name = "RewardRevealCenter_%d" % _reward_popup_serial
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reward_reveal_panel = REWARD_REVEAL_PANEL.new()
	_reward_reveal_panel.custom_minimum_size = Vector2(420.0, 0.0)
	wrapper.add_child(_reward_reveal_panel)
	add_child(wrapper)
	_reward_reveal_panel.dismissed.connect(func() -> void:
		if is_instance_valid(wrapper):
			wrapper.queue_free()
		_reward_reveal_panel = null
		_reward_popup_active = false
		call_deferred("_show_next_reward_popup"))
	_reward_reveal_panel.open_for(entries, str(item.get("source", "reward")),
		str(item.get("title", "")), str(item.get("subtitle", "")))

func _apply_mobile_control_preferences() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	var joystick_scale := clampf(float(config.get_value("mobile_controls", "joystick_scale", 1.0)), 0.75, 1.45)
	var action_scale := clampf(float(config.get_value("mobile_controls", "action_scale", 1.0)), 0.75, 1.35)
	var opacity := clampf(float(config.get_value("mobile_controls", "opacity", 0.92)), 0.55, 1.0)
	var layout := str(config.get_value("mobile_controls", "layout", "standard"))
	var joystick := get_node_or_null("Root/MoveJoystick") as Control
	if joystick != null:
		joystick.scale = Vector2.ONE * joystick_scale
		joystick.modulate.a = opacity
	var controls := get_tree().get_nodes_in_group("combat_action_controls")
	for control_value in controls:
		var control := control_value as Control
		if control != null:
			control.scale = Vector2.ONE * action_scale
			control.modulate.a = opacity
	_set_left_handed(layout == "left_handed", joystick, controls)

## Mirror about the screen centre. This is its own inverse, so applying and
## clearing left-handed mode are the same operation. Replaces the previous
## sequence of manual anchor writes that `set_anchors_and_offsets_preset`
## immediately overwrote (the layout silently did nothing).
func _mirror_horizontally(control: Control) -> void:
	var anchor_left := control.anchor_left
	var anchor_right := control.anchor_right
	var offset_left := control.offset_left
	var offset_right := control.offset_right
	control.anchor_left = 1.0 - anchor_right
	control.anchor_right = 1.0 - anchor_left
	control.offset_left = -offset_right
	control.offset_right = -offset_left

func _set_left_handed(enabled: bool, joystick: Control, controls: Array) -> void:
	if enabled == _left_handed_applied:
		return
	_left_handed_applied = enabled
	if joystick != null:
		_mirror_horizontally(joystick)
	for control_value in controls:
		var control := control_value as Control
		if control != null:
			_mirror_horizontally(control)

func _apply_touch_target_scale() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	var scale := clampf(float(config.get_value("accessibility", "touch_target_scale", 1.0)), 1.0, 1.5)
	for control in get_tree().get_nodes_in_group("combat_action_controls"):
		if control is FightButton:
			(control as FightButton).accessibility_touch_scale = scale

func _connect_signals() -> void:
	game_state.hp_changed.connect(_on_hp_changed)
	game_state.xp_changed.connect(_on_xp_changed)
	game_state.gold_changed.connect(_on_gold_changed)
	game_state.diamonds_changed.connect(_on_diamonds_changed)
	game_state.level_up.connect(_on_level_up)
	game_state.weapon_changed.connect(_on_weapon_changed)
	game_state.skill_cooldown_changed.connect(_on_skill_cooldown_changed)
	game_state.stage_changed.connect(_on_stage_changed)
	if game_state.has_signal("route_checkpoint_changed"):
		game_state.route_checkpoint_changed.connect(_on_route_checkpoint_changed)
	game_state.loot_received.connect(_on_loot_received)
	game_state.inventory_changed.connect(_on_inventory_changed)
	if game_state.has_signal("quest_progress"):
		game_state.quest_progress.connect(_on_quest_progress)
	if game_state.has_signal("world_activity_changed"):
		game_state.world_activity_changed.connect(_on_world_activity_changed)
	var rm := get_node_or_null("/root/RewardManager")
	if rm and rm.has_signal("reward_granted"):
		rm.reward_granted.connect(_on_reward_granted)
	if rm and rm.has_signal("quest_reward_granted"):
		rm.quest_reward_granted.connect(_on_quest_reward_granted)
	if rm and rm.has_signal("boss_reward_choice_available"):
		rm.boss_reward_choice_available.connect(_on_boss_reward_choice_available)
	if settings_button: settings_button.pressed.connect(_on_settings_pressed)
	if satchel_button: satchel_button.pressed.connect(_on_satchel_pressed)
	if scan_button:
		scan_button.pressed.connect(_on_scan_pressed)
		scan_button.text = "FORGE"
		scan_button.tooltip_text = "Open the forge: blueprints, tiers, and reforging"
	if shop_button: shop_button.pressed.connect(_on_shop_pressed)
	if stats_button: stats_button.pressed.connect(_on_stats_pressed)
	if enemy_scan_button: enemy_scan_button.pressed.connect(_on_enemy_scan_pressed)
	if target_switch_button: target_switch_button.pressed.connect(_on_target_switch_pressed)
	if lesson_button: lesson_button.pressed.connect(_on_lesson_pressed)
	if journal_button: journal_button.pressed.connect(_on_journal_pressed)

func _build_journal_button() -> void:
	journal_button = Button.new()
	journal_button.text = "JOURNAL"
	journal_button.tooltip_text = "Open Expedition Journal"
	journal_button.custom_minimum_size = Vector2(0, 36)
	UiKit.style_secondary_button(journal_button)
	$Root/QuestLedger/QuestLedgerVBox.add_child(journal_button)

func _build_camp_button() -> void:
	var camp_button := Button.new()
	camp_button.name = "CampButton"
	camp_button.text = "CAMP"
	camp_button.tooltip_text = "Open Lantern Camp"
	camp_button.custom_minimum_size = Vector2(96, 48)
	UiKit.style_secondary_button(camp_button)
	camp_button.pressed.connect(_on_camp_pressed)
	$Root/MetaRow/ActionRow.add_child(camp_button)

func _build_compact_actions_toggle() -> void:
	_actions_toggle = Button.new()
	_actions_toggle.name = "ActionsToggle"
	_actions_toggle.text = "ACTIONS"
	_actions_toggle.tooltip_text = "Show inventory, scan, shop, stats, and camp"
	_actions_toggle.custom_minimum_size = Vector2(104, 44)
	UiKit.style_secondary_button(_actions_toggle)
	_actions_toggle.add_theme_font_size_override("font_size", 18)
	_actions_toggle.pressed.connect(_toggle_compact_actions)
	top_row.add_child(_actions_toggle)

func _toggle_compact_actions() -> void:
	_compact_actions_open = not _compact_actions_open
	_layout_compact_actions()

## Folds the quest tracker into a one-line objective strip. The control lives in
## the ledger's own header so the thumb that would otherwise fight the panel can
## reach it. Building the header here keeps the authored scene untouched while
## still giving the chapter label and the toggle one aligned row.
func _build_quest_ledger_toggle() -> void:
	var vbox := get_node_or_null("Root/QuestLedger/QuestLedgerVBox") as VBoxContainer
	if vbox == null or chapter_label == null:
		return
	_ledger_header = HBoxContainer.new()
	_ledger_header.name = "LedgerHeader"
	_ledger_header.add_theme_constant_override("separation", 8)
	vbox.add_child(_ledger_header)
	vbox.move_child(_ledger_header, 0)
	vbox.remove_child(chapter_label)
	_ledger_header.add_child(chapter_label)
	chapter_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chapter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ledger_summary = Label.new()
	_ledger_summary.name = "LedgerSummary"
	_ledger_summary.visible = false
	_ledger_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ledger_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ledger_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiKit.style_label(_ledger_summary, &"Caption", 20)
	_ledger_header.add_child(_ledger_summary)
	_ledger_toggle = Button.new()
	_ledger_toggle.name = "LedgerMinimizeButton"
	_ledger_toggle.text = "▲"
	_ledger_toggle.tooltip_text = "Minimize quest tracker"
	UiKit.style_secondary_button(_ledger_toggle)
	_ledger_toggle.pressed.connect(_on_ledger_toggle_pressed)
	_ledger_header.add_child(_ledger_toggle)
	UiKit.ensure_touch_target(_ledger_toggle)
	_refresh_ledger_summary()

func _on_ledger_toggle_pressed() -> void:
	_set_ledger_minimized(not _ledger_minimized)

func _set_ledger_minimized(minimized: bool, persist: bool = true) -> void:
	_ledger_minimized = minimized
	_apply_ledger_minimized_state()
	if persist:
		_save_ledger_preference()

## Hides the tracker's detail rows while the header keeps the live objective and
## the toggle, so folding never costs the player their next step.
func _apply_ledger_minimized_state() -> void:
	if chapter_label != null:
		chapter_label.visible = not _ledger_minimized
	if _ledger_summary != null:
		_ledger_summary.visible = _ledger_minimized
	if _ledger_toggle != null:
		_ledger_toggle.text = "▲" if not _ledger_minimized else "▼"
		_ledger_toggle.tooltip_text = "Minimize quest tracker" if not _ledger_minimized \
			else "Expand quest tracker"
	for value in [title_label, instruction_label, objective_label, checkpoint_label,
			lesson_button, journal_button, _route_pulse]:
		var detail := value as CanvasItem
		if detail != null:
			detail.visible = not _ledger_minimized
	if _ledger_minimized:
		_refresh_ledger_summary()
	_layout_route_ledger()

## The folded strip states the current objective; the chapter rides in the
## tooltip, where there is room for it.
func _refresh_ledger_summary() -> void:
	if _ledger_summary == null:
		return
	var chapter := chapter_label.text.strip_edges() if chapter_label != null else ""
	var title := title_label.text.strip_edges() if title_label != null else ""
	_ledger_summary.text = title
	_ledger_summary.tooltip_text = "%s · %s" % [chapter, title] \
		if not chapter.is_empty() else title

func _restore_ledger_preference() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	_set_ledger_minimized(bool(config.get_value(
		LEDGER_SETTINGS_SECTION, LEDGER_MINIMIZED_KEY, false)), false)

func _save_ledger_preference() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(LEDGER_SETTINGS_SECTION, LEDGER_MINIMIZED_KEY, _ledger_minimized)
	config.save(settings_path)

## Installs the elemental buildup indicator inside the combat card. It polls the
## live target itself, so the card only has to hand it the current enemy.
func _build_elemental_hud() -> void:
	if elemental_hud != null:
		return
	var vbox := get_node_or_null("Root/CombatCard/CombatVBox") as VBoxContainer
	if vbox == null:
		return
	elemental_hud = ElementalHud.new()
	elemental_hud.name = "ElementalHud"
	vbox.add_child(elemental_hud)

func _layout_compact_actions() -> void:
	if _actions_toggle == null or action_row == null:
		return
	var compact := get_viewport().get_visible_rect().size.x < UiKit.COMPACT_BREAKPOINT
	_actions_toggle.visible = compact
	if not compact:
		_compact_actions_open = false
		action_row.visible = true
		return
	_actions_toggle.text = "HIDE" if _compact_actions_open else "ACTIONS"
	action_row.visible = _compact_actions_open
	for child in action_row.get_children():
		var button := child as Button
		if button == null:
			continue
		button.custom_minimum_size.y = 56.0
		button.add_theme_font_size_override("font_size", 18)

## Places Attack plus the three rite buttons as one aligned cluster pinned to
## the bottom-right safe corner: rites in a row above the strike button.
## One source of truth for the combat cluster's size, so the action row and any
## copy placed above it can never disagree about where the cluster starts.
func _cluster_metrics() -> Dictionary:
	var viewport_width := get_viewport().get_visible_rect().size.x
	var cluster_width := ACTION_MARGIN + ACTION_BUTTON_SIZE + ACTION_GAP \
		+ 3.0 * (SKILL_BUTTON_SIZE + ACTION_GAP)
	var scale := 1.0
	if viewport_width > 0.0 and cluster_width > viewport_width * 0.86:
		scale = clampf(viewport_width * 0.86 / cluster_width, 0.66, 1.0)
	return {
		"scale": scale,
		"attack": ACTION_BUTTON_SIZE * scale,
		"skill": SKILL_BUTTON_SIZE * scale,
		"gap": ACTION_GAP * scale,
		"margin": ACTION_MARGIN * scale,
	}

func _layout_action_cluster() -> void:
	var bar := get_node_or_null("Root/SkillBar") as Control
	if bar == null:
		return
	# Narrow portrait: shrink the whole cluster rather than letting the leftmost
	# rite slide under the minimap or off the screen.
	var metrics := _cluster_metrics()
	var attack_size := float(metrics["attack"])
	var skill_size := float(metrics["skill"])
	var gap := float(metrics["gap"])
	var margin := float(metrics["margin"])
	var attack := bar.get_node_or_null("AttackButton") as Control
	if attack != null:
		attack.custom_minimum_size = Vector2(attack_size, attack_size)
		_anchor_bottom_right(attack, attack_size, attack_size, margin, margin)
	var skill_right := margin + attack_size + gap
	var skill_bottom := margin + attack_size + gap
	for i in 3:
		var btn := bar.get_node_or_null("Skill%dButton" % i) as Control
		if btn == null:
			continue
		btn.custom_minimum_size = Vector2(skill_size, skill_size)
		_anchor_bottom_right(btn, skill_size, skill_size,
			skill_right + float(i) * (skill_size + gap), skill_bottom)

func _anchor_bottom_right(control: Control, width: float, height: float,
		right: float, bottom: float) -> void:
	control.anchor_left = 1.0
	control.anchor_top = 1.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_right = -right
	control.offset_left = -right - width
	control.offset_bottom = -bottom
	control.offset_top = -bottom - height

func _build_activity_line() -> void:
	var strip := PanelContainer.new()
	strip.name = "RoutePulse"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.custom_minimum_size = Vector2(0, 52)
	strip.add_theme_stylebox_override("panel",
		UiKit.item_card_stylebox(UiKit.SAGE_BRIGHT, false))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	strip.add_child(margin)
	var pulse_box := VBoxContainer.new()
	pulse_box.add_theme_constant_override("separation", 1)
	margin.add_child(pulse_box)
	var pulse_heading := Label.new()
	pulse_heading.text = "ROUTE PULSE"
	UiKit.style_label(pulse_heading, &"Eyebrow", 20)
	pulse_heading.add_theme_color_override("font_color", UiKit.SAGE_BRIGHT)
	pulse_box.add_child(pulse_heading)
	_activity_line = Label.new()
	_activity_line.name = "NearbyActivityLabel"
	_activity_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_activity_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_label(_activity_line, &"Body", 20)
	_activity_line.add_theme_color_override("font_color", UiKit.CREAM_DIM)
	pulse_box.add_child(_activity_line)
	_route_pulse = strip
	$Root/QuestLedger/QuestLedgerVBox.add_child(strip)
	_refresh_nearby_activity()

func _apply_hud_chrome() -> void:
	if quest_ledger != null:
		quest_ledger.add_theme_stylebox_override("panel",
			UiKit.glass_stylebox(false, 0.62, UiKit.RADIUS_PANEL))
	if player_plate != null:
		player_plate.add_theme_stylebox_override("panel",
			UiKit.item_card_stylebox(UiKit.EMBER, false))
	UiKit.style_label(chapter_label, &"Eyebrow", 20)
	UiKit.style_label(title_label, &"Title", 30)
	UiKit.style_label(instruction_label, &"Body", 20)
	UiKit.style_label(objective_label, &"Caption", 20)
	UiKit.style_label(checkpoint_label, &"Caption", 18)
	if field_note != null and not _field_note_visible:
		# The field note is transient: it must not idle on the scene's authored
		# placeholder line (which carried a language glyph) before the first note.
		field_note.text = ""
	chapter_label.add_theme_color_override("font_color", UiKit.SAGE_BRIGHT)
	title_label.add_theme_color_override("font_color", UiKit.EMBER_BRIGHT)
	instruction_label.add_theme_color_override("font_color", UiKit.CREAM_DIM)
	objective_label.add_theme_color_override("font_color", UiKit.CREAM_DIM)
	checkpoint_label.add_theme_color_override("font_color", UiKit.EMBER)

## Safe-area inset plus narrow-portrait clamping for the HUD's full-width
## elements. Presentation only: no gameplay timing or telegraph changes.
func _apply_frame_layout() -> void:
	_layout_action_cluster()
	_layout_field_note()
	_sync_joystick_pivot()

	var root := get_node_or_null("Root") as Control
	if root == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	UiKit.apply_safe_area(root, viewport_size)
	_layout_wide_bars(viewport_size)

## Control.scale pivots on the control's top-left by default, which pushed an
## enlarged stick off the bottom edge and pulled a shrunken one out of the thumb
## corner. Pin the pivot to the screen corner the stick is anchored to so the
## joystick grows and shrinks in place as its size preference changes.
func _sync_joystick_pivot() -> void:
	var joystick := get_node_or_null("Root/MoveJoystick") as Control
	if joystick == null:
		return
	var stick_size := joystick.size
	if stick_size.x <= 1.0 or stick_size.y <= 1.0:
		stick_size = joystick.custom_minimum_size
	joystick.pivot_offset = Vector2(
		stick_size.x if _left_handed_applied else 0.0, stick_size.y)

## Field notes used to sit in a fixed 640px band across the bottom, which ran
## straight over the joystick on a phone. They now sit above the stick, wrap,
## and stay left-aligned to the safe margin.
func _layout_field_note() -> void:
	if field_note == null or not is_instance_valid(field_note):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var joystick := get_node_or_null("Root/MoveJoystick") as Control
	var joystick_height := 208.0
	if joystick != null:
		# The stick is scaled about its bottom anchor, so its visual height is
		# the layout height times the size preference, not the authored offset.
		var stick_scale := maxf(joystick.scale.x, joystick.scale.y)
		var stick_base := maxf(joystick.size.y, joystick.custom_minimum_size.y)
		joystick_height = absf(joystick.offset_bottom) + stick_base * stick_scale
	var cluster := _cluster_metrics()
	var cluster_top := float(cluster["margin"]) + float(cluster["attack"]) \
		+ float(cluster["gap"]) + float(cluster["skill"])
	var note_width := minf(viewport_size.x * 0.66, 560.0)
	field_note.anchor_left = 0.0
	field_note.anchor_right = 0.0
	field_note.anchor_top = 1.0
	field_note.anchor_bottom = 1.0
	field_note.offset_left = 24.0
	field_note.offset_right = 24.0 + note_width
	# Clear whichever is taller: the joystick on the left or the action cluster
	# on the right. The note sits above both instead of across them.
	field_note.offset_bottom = -(maxf(joystick_height, cluster_top) + 18.0)
	field_note.offset_top = field_note.offset_bottom - 68.0
	field_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiKit.style_label(field_note, &"Body", 20)

func _layout_wide_bars(viewport_size: Vector2) -> void:
	var half_limit := maxf(viewport_size.x * 0.5 - FRAME_MARGIN, 110.0)
	if boss_health_bar != null and is_instance_valid(boss_health_bar):
		var boss_half := minf(BOSS_BAR_MAX_WIDTH * 0.5, half_limit)
		boss_health_bar.offset_left = -boss_half
		boss_health_bar.offset_right = boss_half
	if combat_card != null and is_instance_valid(combat_card):
		var card_half := minf(COMBAT_CARD_MAX_WIDTH * 0.5, half_limit)
		combat_card.offset_left = -card_half
		combat_card.offset_right = card_half
	var meta := top_row.get_parent() as Control if top_row != null else null
	if meta != null and is_instance_valid(meta):
		var meta_width := minf(META_ROW_MAX_WIDTH,
			maxf(viewport_size.x - FRAME_MARGIN * 2.0, 220.0))
		meta.offset_left = -meta_width
		meta.offset_right = -FRAME_MARGIN
	if loot_toast != null and is_instance_valid(loot_toast):
		loot_toast.offset_right = -LOOT_TOAST_MARGIN

## Authored small controls predate the 48px Android touch token. Growing them
## here (never shrinking) keeps every tap target reachable on a phone.
func _enforce_touch_targets() -> void:
	var targets: Array[Control] = [settings_button, lesson_button, journal_button,
		_actions_toggle, satchel_button, scan_button, shop_button, stats_button]
	for control in targets:
		if control != null and is_instance_valid(control):
			UiKit.ensure_touch_target(control)

func _layout_route_ledger() -> void:
	if quest_ledger == null or not is_instance_valid(quest_ledger):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := viewport_size.x < UiKit.COMPACT_BREAKPOINT
	var left := 16.0 if compact else 20.0
	# Measure against the safe-area frame, not the raw viewport: on a phone the
	# Root is already inset by the notch/gesture bar, so viewport width would let
	# the ledger run past the right edge.
	var root := get_node_or_null("Root") as Control
	var frame_width := root.size.x if root != null and root.size.x > 1.0 else viewport_size.x
	var width := minf(360.0, maxf(264.0, frame_width * 0.36))
	width = minf(width, frame_width - left - 20.0)
	quest_ledger.offset_left = left
	quest_ledger.offset_right = left + width
	quest_ledger.offset_top = 342.0 if viewport_size.y >= 720.0 else 260.0
	var measured_height := quest_ledger.get_combined_minimum_size().y + 8.0
	# Folded, the ledger is exactly its header: the 360px expanded floor would
	# defeat the whole point of reclaiming the corner for a larger joystick.
	var content_height := measured_height if _ledger_minimized \
		else clampf(measured_height, 360.0, 520.0)
	var available_height := maxf(220.0, viewport_size.y - quest_ledger.offset_top - 36.0)
	quest_ledger.offset_bottom = quest_ledger.offset_top + minf(content_height, available_height)

func _on_journal_pressed() -> void:
	if journal_panel != null and is_instance_valid(journal_panel):
		journal_panel.queue_free()
		journal_panel = null
		return
	journal_panel = PanelContainer.new()
	journal_panel.name = "ExpeditionJournal"
	journal_panel.custom_minimum_size = Vector2(420, 360)
	journal_panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_PANEL))
	var scroll := ScrollContainer.new()
	scroll.name = "JournalScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var copy := game_state.get_quest_copy(game_state.current_stage)
	var title := Label.new()
	title.text = "EXPEDITION JOURNAL  ·  %s" % str(copy.get("chapter", "CURRENT CHAPTER")).to_upper()
	UiKit.style_label(title, &"MenuTitle", 32)
	box.add_child(title)
	var map := Label.new()
	var chapters := [
		[0, "I  THE QUIET GROVE", "Whispergrove onboarding"],
		[1, "II  A WARM FRAGMENT", "Bramblewood gathering"],
		[2, "III  THE WAY BACK", "Elite fight and beacon"],
		[3, "IV  A PATH RELIT", "Next realm expedition"],
	]
	var map_lines: Array[String] = ["CHAPTER MAP"]
	for chapter in chapters:
		var chapter_index := int(chapter[0])
		var marker := "CLEARED" if chapter_index < int(game_state.current_stage) else ("CURRENT" if chapter_index == int(game_state.current_stage) else "LOCKED")
		map_lines.append("%s  ·  %s  ·  %s" % [marker, str(chapter[1]), str(chapter[2])])
	map.text = "\n".join(map_lines)
	UiKit.style_label(map, &"Caption", 18)
	box.add_child(map)
	var route := Label.new()
	route.text = "PRIMARY ROUTE\n%s\n\n%s\nWHY  ·  %s\nRISK  ·  %s\nREWARD  ·  %s\nNEXT  ·  %s" % [
		str(copy.get("title", "Quest")), str(copy.get("instruction", "")),
		str(copy.get("why", "")), str(copy.get("risk", "")),
		str(copy.get("reward", "")), str(copy.get("next_action", ""))]
	route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(route, &"Body", 20)
	box.add_child(route)
	var checkpoint := Label.new()
	checkpoint.text = "CURRENT MILESTONE  ·  %s" % str(game_state.route_checkpoint_id).replace("_", " ").to_upper()
	UiKit.style_label(checkpoint, &"Caption", 18)
	box.add_child(checkpoint)
	var route_map := Label.new()
	var route_nodes := [
		["grove_arrival", "WHISPERGROVE", "Start"],
		["sprite_found", "BRAMBLEWOOD", "Gather"],
		["elite_gate", "BRAMBLEWOOD", "Elite"],
		["beacon_relit", "OLD BEACON", "Unlock"],
	]
	var expansion: Dictionary = game_state.bramblewood_expansion_snapshot() \
		if game_state.has_method("bramblewood_expansion_snapshot") else {}
	if str(game_state.current_realm) == "bramblewood" \
			and (bool(expansion.get("started", false)) or bool(expansion.get("completed", false))):
		route_nodes = [
			["bramblewood_expansion_start", "SPLIT-ROAD OAK", "Landmark"],
			["rootcut_gully", "ROOTCUT GULLY", "Gather"],
			["hollow_camp", "HOLLOW CAMP", "Checkpoint"],
			["beacon_breach", "BEACON BREACH", "Elite"],
			["rootbound_court", "ROOTBOUND COURT", "Finale"],
			["rootway_shortcut", "ROOTWAY BEACON", "Shortcut"],
		]
	var route_map_lines: Array[String] = ["ROUTE MAP  ·  LAST SAFE PATH"]
	for route_node in route_nodes:
		var route_id := str(route_node[0])
		var route_marker := "●" if route_id == str(game_state.route_checkpoint_id) else ("✓" if _checkpoint_is_reached(route_id, str(game_state.route_checkpoint_id)) else "○")
		route_map_lines.append("%s  %s  ·  %s" % [route_marker, str(route_node[1]), str(route_node[2])])
	route_map.text = "\n".join(route_map_lines)
	UiKit.style_label(route_map, &"Caption", 18)
	box.add_child(route_map)
	var recovery: Dictionary = game_state.get_activity_recovery() if game_state.has_method("get_activity_recovery") else {}
	if not recovery.is_empty():
		var recovery_label := Label.new()
		recovery_label.name = "ActivityRecovery"
		recovery_label.text = "RECOVERY  ·  %s\n%s\n%s" % [str(recovery.get("status", "unknown")).to_upper(), str(recovery.get("reason", "Activity snapshot preserved.")), str(recovery.get("next_action", "Return to the recorded checkpoint."))]
		recovery_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(recovery_label, &"Caption", 18)
		box.add_child(recovery_label)
	var realm_id := str(game_state.get("current_realm") if game_state.get("current_realm") != null else "bramblewood")
	var realm_profile: Dictionary = RealmIdentityCatalog.for_realm(realm_id)
	var identity := Label.new()
	identity.text = "REALM READ\n%s\nRESOURCE  ·  %s\nLANDMARK REWARD  ·  %s" % [
		str(realm_profile.get("traversal", "Explore the realm")),
		str(realm_profile.get("resource_ritual", "Gather local materials")),
		str(realm_profile.get("landmark_reward", "Discover a landmark"))]
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(identity, &"Caption", 18)
	box.add_child(identity)
	var optional := Label.new()
	optional.text = "OPTIONAL OBJECTIVES"
	UiKit.style_label(optional, &"Caption", 18)
	box.add_child(optional)
	var objectives_box := VBoxContainer.new()
	objectives_box.name = "ObjectivePinRows"
	objectives_box.add_theme_constant_override("separation", 4)
	box.add_child(objectives_box)
	var pinned_id := str(game_state.pinned_objective_id)
	var objectives: Array = game_state.get_active_objectives()
	if objectives.is_empty():
		var empty := Label.new()
		empty.text = "None active"
		UiKit.style_label(empty, &"Caption", 18)
		objectives_box.add_child(empty)
	else:
		for objective in objectives:
			var objective_id := str(objective.get("id", ""))
			var row := HBoxContainer.new()
			row.name = "Objective_%s" % objective_id
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var objective_label := Label.new()
			objective_label.text = "• %s  %d/%d" % [str(objective.get("description", "Objective")), int(objective.get("current_qty", 0)), int(objective.get("target_qty", 1))]
			objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UiKit.style_label(objective_label, &"Caption", 18)
			row.add_child(objective_label)
			var pin := Button.new()
			var is_pinned := objective_id == pinned_id
			pin.text = "UNPIN" if is_pinned else "PIN"
			pin.tooltip_text = "Remove this objective from the HUD focus." if is_pinned else "Show only this objective on the HUD."
			pin.custom_minimum_size = Vector2(68, 32)
			UiKit.style_secondary_button(pin)
			pin.pressed.connect(_on_objective_pin_pressed.bind(objective_id, is_pinned))
			row.add_child(pin)
			objectives_box.add_child(row)
	var reward_direction := Label.new()
	reward_direction.text = "REWARD DIRECTION\nComplete route objectives to earn gold, XP, and lens progress."
	reward_direction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(reward_direction, &"Caption", 18)
	box.add_child(reward_direction)
	var ownership := Label.new()
	ownership.name = "OwnershipLedgerSummary"
	ownership.text = "OWNERSHIP LEDGER\nGold %d · Diamonds %d · Lens %d\nWeapons %d · Armor %d · Purchases %d" % [
		game_state.gold, game_state.diamonds, game_state.scans_remaining,
		game_state.forged_weapons.size(), game_state.forged_armors.size(),
		game_state.get_purchase_ledger().size()]
	ownership.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(ownership, &"Caption", 18)
	box.add_child(ownership)
	var history := Label.new()
	history.name = "RecentRewardHistory"
	var history_lines: Array[String] = []
	for entry in _reward_history:
		history_lines.append("• " + entry)
	var saved_activity: Array = game_state.get_activity_history() \
		if game_state.has_method("get_activity_history") else []
	for entry in saved_activity:
		var line := "• " + str(entry)
		if line not in history_lines:
			history_lines.append(line)
		if history_lines.size() >= REWARD_HISTORY_CAP:
			break
	history.text = "RECENT ACTIVITY\n%s" % ("\n".join(history_lines) if not history_lines.is_empty() else "No recent activity")
	history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(history, &"Caption", 18)
	box.add_child(history)
	var close := Button.new()
	close.text = "CLOSE JOURNAL"
	close.pressed.connect(_on_journal_pressed)
	UiKit.style_secondary_button(close)
	box.add_child(close)
	add_child(journal_panel)
	_layout_journal_panel()

func _checkpoint_is_reached(candidate: String, current: String) -> bool:
	var order := ["grove_arrival", "sprite_found", "elite_gate", "beacon_relit",
		"bramblewood_expansion_start", "rootcut_gully", "hollow_camp",
		"beacon_breach", "rootbound_court", "rootway_shortcut"]
	return order.find(candidate) >= 0 and order.find(candidate) < order.find(current)

func _on_objective_pin_pressed(objective_id: String, was_pinned: bool) -> void:
	if was_pinned and game_state.has_method("unpin_objective"):
		game_state.unpin_objective(objective_id)
	elif game_state.has_method("pin_objective"):
		game_state.pin_objective(objective_id)
	if journal_panel != null and is_instance_valid(journal_panel):
		journal_panel.queue_free()
		journal_panel = null
	_on_journal_pressed()

func _layout_journal_panel() -> void:
	if journal_panel == null or not is_instance_valid(journal_panel):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(420.0, viewport_size.x - 24.0)
	var height := minf(460.0, viewport_size.y - 96.0)
	if viewport_size.x >= 284.0:
		width = maxf(260.0, width)
	if viewport_size.y >= 336.0:
		height = maxf(240.0, height)
	var content_min := journal_panel.get_combined_minimum_size()
	width = maxf(width, content_min.x)
	height = maxf(height, minf(content_min.y, viewport_size.y - 48.0))
	journal_panel.custom_minimum_size = Vector2.ZERO
	journal_panel.size = Vector2(width, height)
	journal_panel.position = Vector2(
		maxf(12.0, viewport_size.x - width - 24.0),
		maxf(48.0, (viewport_size.y - height) * 0.5))

func _refresh_all() -> void:
	_on_hp_changed(0, game_state.hp)
	_on_xp_changed(game_state.xp, game_state.level)
	_on_gold_changed(game_state.gold)
	_on_diamonds_changed(game_state.diamonds)
	_on_stage_changed(int(game_state.current_stage))
	_on_route_checkpoint_changed(str(game_state.get("route_checkpoint_id")))
	_on_weapon_changed(game_state.equipped_weapon)
	_refresh_objectives()
	_refresh_satchel_count()
	_update_glint_visibility()

func _on_hp_changed(_old: int, new_hp: int) -> void:
	var max_hp := game_state.max_hp
	if warmth_bar:
		warmth_bar.max_value = max_hp
		warmth_bar.value = new_hp
	if warmth_text:
		warmth_text.text = "%d / %d" % [new_hp, max_hp]

func _on_xp_changed(new_xp: int, new_level: int) -> void:
	if level_badge: level_badge.text = "LV %d" % new_level
	var xp_cap := 100 + (new_level - 1) * 35
	if exp_bar:
		exp_bar.max_value = xp_cap
		exp_bar.value = new_xp

func _on_level_up(new_level: int, _pts: int) -> void:
	_push_field_note("LEVEL UP! Now level %d." % new_level)
	_show_level_toast(new_level)

## The authored level banner now actually fires. Previous builds only pushed a
## field note, so LevelToast/ToastTitle/ToastSub never appeared.
func _show_level_toast(new_level: int) -> void:
	if level_toast == null or not is_instance_valid(level_toast):
		return
	if toast_title != null:
		toast_title.text = "LEVEL %d" % new_level
	if toast_sub != null:
		toast_sub.text = "A new rite waits in the satchel."
	if _level_toast_tween != null and _level_toast_tween.is_valid():
		_level_toast_tween.kill()
	level_toast.visible = true
	level_toast.modulate.a = 1.0
	_level_toast_tween = create_tween()
	_level_toast_tween.tween_interval(2.2)
	_level_toast_tween.tween_property(level_toast, "modulate:a", 0.0, 0.5)
	_level_toast_tween.tween_callback(func() -> void:
		if is_instance_valid(level_toast):
			level_toast.visible = false)

func _on_gold_changed(total: int) -> void:
	if gold_label: gold_label.text = "GOLD  %d" % total

func _on_diamonds_changed(total: int) -> void:
	if diamond_label: diamond_label.text = "DIAMONDS  %d" % total

func _on_weapon_changed(weapon: Dictionary) -> void:
	var skills : Array = weapon.get("skills", [])
	for i in 3:
		var glyph = skill_glyph_labels[i] if i < skill_glyph_labels.size() else null
		var btn   = skill_buttons[i]       if i < skill_buttons.size()       else null
		if i < skills.size():
			if glyph:
				glyph.text = ""
			if btn is FightButton:
				var fight := btn as FightButton
				var skill: Dictionary = skills[i]
				fight.skill_kind = str(skill.get("type", ""))
				fight.tooltip_data = {
					"name": str(skill.get("name", "RITE")).to_upper(),
					"key": ["Q", "E", "R"][i],
					"type_label": str(SKILL_RUNES.get(fight.skill_kind, "RITE")),
					"cooldown": float(skill.get("cooldown", 0.0)),
					"desc": str(skill.get("desc", "")),
					"effect": _skill_effect_text(skill),
				}
				fight.set_action_state("available", "Ready when the cooldown is clear")
			elif btn: btn.disabled = false
		else:
			if glyph: glyph.text = "—"
			if btn is FightButton:
				var empty := btn as FightButton
				empty.skill_kind = ""
				empty.tooltip_data = {}
				empty.set_action_state("unavailable", "Equip a weapon skill")
			elif btn: btn.disabled = true

## One-line effect summary built from the skill's own numbers, so the tooltip
## explains what the rite does without inventing copy.
func _skill_effect_text(skill: Dictionary) -> String:
	var parts: Array[String] = []
	var dmg := float(skill.get("dmg_mult", 0.0))
	if dmg > 0.0:
		parts.append("×%.1f damage" % dmg)
	var radius := float(skill.get("radius", 0.0))
	if radius > 0.0:
		parts.append("%.0fm area" % radius)
	var power := float(skill.get("power", 0.0))
	if power > 0.0:
		parts.append("%.1f force" % power)
	var duration := float(skill.get("duration", 0.0))
	if duration > 0.0:
		parts.append("%.1fs" % duration)
	return " · ".join(parts)

func _on_skill_cooldown_changed(slot: int, remaining: float) -> void:
	if slot < 0 or slot >= 3: return
	var cd  = skill_cd_labels[slot]  if slot < skill_cd_labels.size()  else null
	var btn = skill_buttons[slot]    if slot < skill_buttons.size()    else null
	if cd:  cd.text = "" if remaining <= 0.0 else "%ds" % ceili(remaining)
	if btn is FightButton:
		# Radial cooldown ring + countdown, fed by the same numbers the
		# refusal path uses (skill cooldown is padded 1.20x in use_skill).
		var sk := game_state.get_skill(slot)
		var total := (float(sk.get("cooldown", 1.0)) * 1.20) if not sk.is_empty() else 1.0
		btn.set_cooldown(remaining, total)
		btn.set_action_state("unavailable" if remaining > 0.0 else "available",
			"Cooldown %0.1fs remaining" % remaining if remaining > 0.0 else "Ready")
	elif btn: btn.disabled = remaining > 0.0

# ─────────────────────────────────────────────────────────────────────────────
# Contextual interact button
# ─────────────────────────────────────────────────────────────────────────────

## A thumb-reachable button that appears only while something in the world can
## be acted on (chest, gather node, landmark, dropped loot). It routes through
## InputManager.interact_pressed — the same canonical path as Space and the
## gamepad A button — so WorldManager's nearby-interactable router stays the
## single owner of what a press actually does.
func _build_interact_button() -> void:
	var root := get_node_or_null("Root") as Control
	if root == null:
		return
	_interact_button = FightButton.new()
	_interact_button.name = "InteractButton"
	_interact_button.shape = FightButton.Shape.CIRCLE
	_interact_button.accent = Color(0.96, 0.72, 0.29)
	_interact_button.custom_minimum_size = INTERACT_BUTTON_RECT.size
	_interact_button.anchor_left = 1.0
	_interact_button.anchor_top = 1.0
	_interact_button.anchor_right = 1.0
	_interact_button.anchor_bottom = 1.0
	_interact_button.offset_left = INTERACT_BUTTON_RECT.position.x
	_interact_button.offset_top = INTERACT_BUTTON_RECT.position.y
	_interact_button.offset_right = INTERACT_BUTTON_RECT.end.x
	_interact_button.offset_bottom = INTERACT_BUTTON_RECT.end.y
	_interact_button.visible = false
	_interact_button.add_to_group("combat_action_controls")
	_interact_label = Label.new()
	_interact_label.name = "InteractLabel"
	_interact_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interact_label.add_theme_font_size_override("font_size", 18)
	_interact_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_button.add_child(_interact_label)
	_interact_button.fight_pressed.connect(_on_interact_pressed)
	root.add_child(_interact_button)

func _on_interact_pressed() -> void:
	if input_manager != null:
		input_manager.interact_pressed.emit()

func _refresh_interact_prompt() -> void:
	if _interact_button == null or not is_instance_valid(_interact_button):
		return
	var scene := get_tree().current_scene
	var prompt: Dictionary = {}
	if scene != null and scene.has_method("get_interact_prompt"):
		prompt = scene.call("get_interact_prompt")
	var available := not prompt.is_empty()
	_interact_button.visible = available
	if not available:
		_interact_verb = ""
		return
	var verb := str(prompt.get("verb", "INTERACT"))
	if verb == _interact_verb:
		return
	_interact_verb = verb
	if _interact_label != null:
		_interact_label.text = verb
	_interact_button.tooltip_text = "%s (Space)" % verb.capitalize()
	_interact_button.set_action_state("available",
		"Press to %s" % verb.to_lower())

## The Attack/Dodge/Jump FightButtons are plain Controls — nothing wired
## them before, so the primary STRIKE button literally did nothing on
## touch. Route them through InputManager exactly like their keyboard
## twins so there is one canonical input path into the hero.
func _wire_action_buttons() -> void:
	var attack_btn := get_node_or_null("Root/SkillBar/AttackButton") as FightButton
	if attack_btn != null:
		attack_btn.set_action_state("available", "Strike the marked foe; auto-mark when needed")
		attack_btn.fight_pressed.connect(func(): input_manager.attack_pressed.emit())
		attack_btn.fight_released.connect(func(): input_manager.attack_released.emit())
	var dodge_btn := get_node_or_null("Root/DodgeButton") as FightButton
	if dodge_btn != null:
		dodge_btn.set_action_state("available", "Brief invulnerability")
		dodge_btn.fight_pressed.connect(func(): input_manager.dodge_pressed.emit(Vector2.ZERO))
	var jump_btn := get_node_or_null("Root/JumpButton") as FightButton
	if jump_btn != null:
		jump_btn.set_action_state("available", "Clear terrain and hazards")
		jump_btn.fight_pressed.connect(func(): input_manager.jump_pressed.emit())
	if glint_button != null and is_instance_valid(glint_button):
		glint_button.pressed.connect(_on_glint_pressed)
	# The whole action row breathes with the lantern mark: pulsing lock
	# ring on skill + attack buttons while a foe is lit.
	game_state.mark_locked.connect(func(_t: Node3D): _set_lock_glow(true))
	game_state.mark_released.connect(func(): _set_lock_glow(false))

func _set_lock_glow(on: bool) -> void:
	var all: Array = skill_buttons.duplicate()
	var atk := get_node_or_null("Root/SkillBar/AttackButton")
	if atk != null:
		all.append(atk)
	for btn in all:
		if btn is FightButton:
			(btn as FightButton).set_lock_glow(on)

func show_combat_card(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy): hide_combat_card(); return
	if combat_card: combat_card.visible = true
	if elemental_hud != null:
		elemental_hud.set_target(enemy)
	if _analyzed_enemy_id != enemy.get_instance_id():
		_analyzed_enemy_id = 0
	if enemy_name: enemy_name.text = str(enemy.get("display_name") if enemy.get("display_name") != null else enemy.name)
	_update_combat_card(enemy)

func hide_combat_card() -> void:
	if combat_card: combat_card.visible = false
	if elemental_hud != null:
		elemental_hud.set_target(null)

func _update_combat_card(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy): return
	var hp = float(enemy.get("hp") if enemy.get("hp") != null else 0)
	var mhp = float(enemy.get("max_hp") if enemy.get("max_hp") != null else 1)
	if enemy_hp_bar:
		enemy_hp_bar.max_value = 1.0
		enemy_hp_bar.value = clampf(hp / maxf(mhp, 1.0), 0.0, 1.0)
	var target_name := str(enemy.get("display_name") if enemy.get("display_name") != null else enemy.name)
	var target_kind := str(enemy.get("kind") if enemy.get("kind") != null else "")
	if target_kind.is_empty():
		target_kind = _target_role_from_name(target_name)
	if combat_status:
		combat_status.text = "LOCKED  ·  %s  ·  %s\n%s\nHP %d / %d" % [
			target_kind.to_upper(), target_name.to_upper(),
			_target_priority_hint(target_kind), int(hp), int(mhp)]
	_update_target_direction(enemy)
	if enemy_scan_button:
		var analyzed := _analyzed_enemy_id == enemy.get_instance_id()
		var scan_state := UiKit.action_state("analyzed" if analyzed else ("unavailable" if game_state.scans_remaining <= 0 else "available"),
			"This foe is already resolved" if analyzed else ("Earn a lens charge from a quest" if game_state.scans_remaining <= 0 else "Reveal bounded combat stats"))
		enemy_scan_button.disabled = bool(scan_state.get("disabled", false))
		enemy_scan_button.text = "FOE ANALYZED" if analyzed else "ANALYZE FOE  ·  %d LENS" % game_state.scans_remaining
		enemy_scan_button.tooltip_text = "%s · %s" % [str(scan_state.get("label", "")), str(scan_state.get("detail", ""))]

func _target_role_from_name(target_name: String) -> String:
	var normalized := target_name.to_lower()
	if normalized.contains("boss") or normalized.contains("matriarch"):
		return "BOSS"
	if normalized.contains("spitter") or normalized.contains("weaver"):
		return "RANGED"
	if normalized.contains("guard") or normalized.contains("knight"):
		return "DEFENDER"
	if normalized.contains("elite") or normalized.contains("warden"):
		return "ELITE"
	return "THREAT"

func _target_priority_hint(target_kind: String) -> String:
	match target_kind.to_upper():
		"BOSS": return "PRIORITY: SURVIVE PATTERN"
		"RANGED": return "PRIORITY: INTERRUPT SPACE CONTROL"
		"DEFENDER": return "PRIORITY: FLANK OR BREAK GUARD"
		"ELITE": return "PRIORITY: WATCH THE TELEGRAPH"
	return "PRIORITY: CLOSE THE THREAT"

func _update_target_direction(enemy: Node3D) -> void:
	if target_direction_label == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		target_direction_label.text = ""
		return
	var screen := camera.unproject_position(enemy.global_position + Vector3.UP * 0.8)
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := 36.0
	var behind := camera.is_position_behind(enemy.global_position)
	var offscreen := behind or screen.x < margin or screen.x > viewport_size.x - margin \
			or screen.y < margin or screen.y > viewport_size.y - margin
	if not offscreen:
		target_direction_label.text = "TARGET IN VIEW"
		target_direction_label.add_theme_color_override("font_color", Color(0.55, 0.86, 0.62))
		return
	var horizontal := "LEFT" if (screen.x < viewport_size.x * 0.5 and not behind) else "RIGHT"
	if behind:
		horizontal = "BEHIND"
	target_direction_label.text = "TARGET %s  ·  TURN TO FIND" % horizontal
	target_direction_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32))

func _on_enemy_scan_pressed() -> void:
	var enemy := game_state.enemy_target
	if enemy == null or not is_instance_valid(enemy):
		return
	var analyzed := _analyzed_enemy_id == enemy.get_instance_id()
	if analyzed or game_state.scans_remaining <= 0:
		return
	if not game_state.consume_scan():
		if combat_status: combat_status.text = "No lens charges — earn one from a quest."
		return
	var report := Bestiary.scan_report(enemy)
	if report.is_empty():
		if combat_status: combat_status.text = "Lens could not resolve this foe."
		return
	var unlocked: Array = []
	if game_state.has_method("register_analysis"):
		unlocked = game_state.register_analysis(str(report.get("kind", "")))
	if game_state.has_method("check_onboarding_trigger"):
		game_state.check_onboarding_trigger("analyze")
	var scan_manager := get_node_or_null("/root/ScanManager")
	if scan_manager != null and scan_manager.has_method("pulse_reveal"):
		scan_manager.call("pulse_reveal")
	var unlock_line := ""
	if not unlocked.is_empty():
		var names: Array[String] = []
		for blueprint_id in unlocked:
			var def: Dictionary = game_state.WEAPON_DEFS.get(str(blueprint_id), {})
			names.append(str(def.get("name", blueprint_id)))
		unlock_line = "\nBLUEPRINT UNLOCKED · %s" % ", ".join(names)
	elif game_state.has_method("analysis_progress_note"):
		var note := str(game_state.analysis_progress_note(str(report.get("kind", ""))))
		if not note.is_empty():
			unlock_line = "\n%s" % note
	if combat_status:
		combat_status.text = "HP %d · ATK %d · SPD %.1f\nPHYS RES %d%% · MAGIC RES %d%%\n%s\n%s%s" % [
			int(report.hp), int(report.attack), float(report.speed),
			int(report.physical_resist), int(report.magic_resist), str(report.reward),
			str(report.ecology), unlock_line]
	if enemy_scan_button:
		_analyzed_enemy_id = enemy.get_instance_id()
		enemy_scan_button.disabled = true
		enemy_scan_button.text = "FOE ANALYZED"
		enemy_scan_button.tooltip_text = "ANALYZED · This foe is already resolved"

func _on_target_switch_pressed() -> void:
	var hero := get_tree().current_scene.get_node_or_null("Hero") if get_tree().current_scene else null
	if hero == null or not hero.has_method("cycle_target"):
		return
	var target := hero.call("cycle_target", 18.0) as Node3D
	if target != null:
		show_combat_card(target)
		if target_switch_button:
			target_switch_button.tooltip_text = "TARGET SWITCHED · Cycle to the next nearby foe"
	else:
		_push_field_note("No nearby foe to target.")
		if target_switch_button:
			target_switch_button.tooltip_text = "UNAVAILABLE · No nearby foe to target"

func show_boss_bar(boss: Node3D, name_str: String) -> void:
	_active_boss = boss
	_boss_telegraph_until_ms = 0
	if boss != null and boss.has_signal("attack_telegraphed") \
			and not boss.attack_telegraphed.is_connected(_on_boss_attack_telegraphed):
		boss.attack_telegraphed.connect(_on_boss_attack_telegraphed)
	# The boss presentation owns the upper combat band. Retire the ordinary
	# target card immediately so the two hierarchies never compete for focus.
	if combat_card: combat_card.visible = false
	if boss_health_bar: boss_health_bar.visible = true
	if boss_name: boss_name.text = name_str

func hide_boss_bar() -> void:
	_active_boss = null
	_boss_telegraph_until_ms = 0
	if boss_health_bar: boss_health_bar.visible = false

func _on_boss_attack_telegraphed(kind: String, _radius: float, delay: float) -> void:
	if not boss_health_bar.visible:
		return
	var readable := kind.replace("_", " ").to_upper()
	if phase_indicator:
		phase_indicator.text = "INCOMING  ·  %s  ·  %.1fs" % [readable, maxf(0.0, delay)]
	_boss_telegraph_until_ms = Time.get_ticks_msec() + maxi(250, int(delay * 1000.0))

func update_boss_bar(hp: int, max_hp: int, phase: int) -> void:
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = hp
	if _boss_telegraph_until_ms > Time.get_ticks_msec():
		return
	if _active_boss != null and is_instance_valid(_active_boss) \
			and _active_boss.has_method("phase_guidance"):
		var guidance: Dictionary = _active_boss.call("phase_guidance")
		if phase_indicator:
			phase_indicator.text = "PHASE %d  ·  %s\nSAFE  ·  %s" % [
				phase + 1, str(guidance.get("pattern", "Read the arena")),
				str(guidance.get("safe_zone", "Step out of the marked area."))]
		return
	var names := ["PHASE I  ·  WATCH THE ARENA", "PHASE II  ·  NEW PATTERN", "PHASE III  ·  HOLD YOUR GROUND", "ENRAGE  ·  SURVIVE THE WINDOW"]
	if phase_indicator: phase_indicator.text = names[clampi(phase, 0, 3)]

func _on_stage_changed(stage: int) -> void:
	var copy := game_state.get_quest_copy(stage) if game_state.has_method("get_quest_copy") else {}
	if chapter_label: chapter_label.text = str(copy.get("chapter", "Chapter I"))
	if title_label: title_label.text = str(copy.get("title", "Quest"))
	if instruction_label: instruction_label.text = str(copy.get("instruction", ""))
	_refresh_ledger_summary()
	_refresh_objectives()

func _on_route_checkpoint_changed(checkpoint_id: String) -> void:
	if checkpoint_label == null or checkpoint_id.is_empty():
		return
	var names := {"grove_arrival": "GROVE ARRIVAL", "hushling_cleared": "HUSHLING CLEARED", "shard_claimed": "EMBER SHARD CLAIMED", "beacon_relit": "BEACON RELIT"}
	checkpoint_label.text = "CHECKPOINT  ·  %s" % str(names.get(checkpoint_id, checkpoint_id.to_upper()))
	_refresh_nearby_activity()

func _on_world_activity_changed(_realm_id: String, _activity_id: String, _status: String) -> void:
	_refresh_nearby_activity()

func _refresh_nearby_activity() -> void:
	if _activity_line == null:
		return
	var scene := get_tree().current_scene
	var director := scene.find_child("RealmActivityDirector", true, false) \
		if scene != null else null
	if director == null or not director.has_method("nearby_activity_snapshot"):
		_activity_line.text = "Route is quiet"
		return
	var snapshot: Dictionary = director.call("nearby_activity_snapshot")
	if snapshot.is_empty():
		_activity_line.text = "Watch for a route marker"
		return
	_activity_line.text = "%s\n%s  ·  %dm" % [
		str(snapshot.get("label", "Activity")).to_upper(),
		str(snapshot.get("prompt", "AHEAD")),
		int(roundf(float(snapshot.get("distance", 0.0))))]

func _on_inventory_changed(_notice: String = "", _count: int = 0) -> void:
	_refresh_objectives()
	_refresh_satchel_count()

## The satchel badge shipped at "0" and was never updated. Reflect the live
## carried-item count so the button communicates state.
func _refresh_satchel_count() -> void:
	if satchel_count == null or not is_instance_valid(satchel_count):
		return
	var inventory: Variant = game_state.get("inventory")
	var carried := 0
	if inventory is Array:
		carried = (inventory as Array).size()
	satchel_count.text = str(carried)

func _refresh_objectives() -> void:
	if not game_state.has_method("get_active_objectives"):
		return
	_refresh_lesson_action()
	var objectives: Array = game_state.get_active_objectives()
	if objective_label == null:
		return
	if objectives.is_empty():
		objective_label.text = "No side objectives active."
		return
	var lines: Array[String] = []
	for obj in objectives.slice(0, 2):
		var current := int(obj.get("current_qty", 0))
		var target := int(obj.get("target_qty", 1))
		lines.append("• %s  %d/%d" % [str(obj.get("description", "Objective")), current, target])
	objective_label.text = "SIDE OBJECTIVES\n" + "\n".join(lines)

func _refresh_lesson_action() -> void:
	if lesson_button == null:
		return
	var quiz_manager := get_node_or_null("/root/QuizManager")
	var completed := quiz_manager != null and bool(quiz_manager.call("is_completed", int(game_state.current_stage)))
	var state := UiKit.action_state("owned" if not completed else "purchased",
		"Chapter lesson is ready" if not completed else "This chapter lesson is complete")
	lesson_button.disabled = false
	lesson_button.text = "LESSON COMPLETE" if completed else "OPEN CHAPTER LESSON"
	lesson_button.tooltip_text = "%s · %s" % [str(state.get("label", "")), str(state.get("detail", ""))]

func _on_lesson_pressed() -> void:
	_retire_other_menus("QuizMenu")
	var menu := get_node_or_null("QuizMenu")
	if menu == null:
		var packed := load("res://scenes/ui/quiz_menu.tscn") as PackedScene
		if packed == null:
			return
		menu = packed.instantiate()
		add_child(menu)
	if menu.has_method("open"):
		menu.call("open", int(game_state.current_stage))

func _on_loot_received(notice: String, count: int) -> void:
	_record_reward_history(notice, count)
	if loot_count: loot_count.text = "× %d" % count
	if loot_notice: loot_notice.text = notice
	if loot_title: loot_title.text = "LOOT"
	_show_loot_toast(3.5)

func _on_reward_granted(summary: Dictionary) -> void:
	var source := str(summary.get("source", ""))
	# A chest roll preview has not granted anything yet: it only drives the
	# reveal, so the currency toast and reward history must stay untouched.
	var preview := bool(summary.get("preview", false))
	var persistent_chest := source == "chest" and bool(summary.get("persistent", false))
	var meaningful_gear: bool = not summary.get("weapons", []).is_empty() \
		or not summary.get("armors", []).is_empty()
	var should_reveal := persistent_chest or (source.is_empty() and meaningful_gear)
	var gold := int(summary.get("gold", 0))
	var xp   := int(summary.get("xp",   0))
	var gems := int(summary.get("diamonds", 0))
	if not preview and (gold > 0 or xp > 0 or gems > 0):
		var parts := []
		if gold > 0: parts.append("+%d G" % gold)
		if xp   > 0: parts.append("+%d XP" % xp)
		if gems > 0: parts.append("+%d D" % gems)
		if loot_notice: loot_notice.text = " · ".join(parts)
		_append_reward_context(summary, parts)
		if loot_title: loot_title.text = _reward_reveal_title(summary)
		if loot_count: loot_count.text = ""
		_show_loot_toast(3.0)
		if gems > 0 or not summary.get("weapons", []).is_empty() \
				or not summary.get("armors", []).is_empty():
			_play_reward_focus()
		_record_reward_history(" · ".join(parts), 0)
	elif not preview and not summary.get("loot_context", []).is_empty():
		_append_reward_context(summary, [])
		if loot_title: loot_title.text = "LOOT"
		if loot_count: loot_count.text = ""
		_show_loot_toast(3.0)
		_record_reward_history(str(summary.get("loot_context", ["Loot context updated"])[0]), 0)
	if should_reveal:
		var reveal_title := "CHEST OPENED" if persistent_chest else _reward_reveal_title(summary)
		_show_reward_reveal(summary, reveal_title, str(summary.get("source_label", "")))

func _show_reward_reveal(summary: Dictionary, title_override: String = "",
		subtitle: String = "") -> void:
	var entries: Array[Dictionary] = REWARD_REVEAL_MODEL.entries_from_summary(summary)
	_enqueue_reward_popup(entries, str(summary.get("source", "loot")),
		title_override, subtitle)

func _on_quest_reward_granted(_completion_id: String, title: String,
		summary: Dictionary) -> void:
	var kind := str(summary.get("completion_kind", "quest_objective"))
	var header := "QUEST COMPLETE" if kind == "quest_stage" else "OBJECTIVE COMPLETE"
	_show_reward_reveal(summary, header, title)

func _rarity_rank(value: Variant) -> int:
	if value is int or value is float:
		return clampi(int(value), 0, 4)
	return clampi(["common", "uncommon", "rare", "epic", "legendary"].find(
		str(value).to_lower()), 0, 4)

func _reward_reveal_title(summary: Dictionary) -> String:
	var highest := 0
	var rarity_names := ["common", "uncommon", "rare", "epic", "legendary"]
	for collection_key in ["weapons", "armors"]:
		for drop in summary.get(collection_key, []):
			var rarity := str(drop.get("rarity", "common")).to_lower()
			var rank := rarity_names.find(rarity)
			if rank > highest:
				highest = rank
	if highest >= 4:
		return "LEGENDARY REVEAL"
	if highest >= 3:
		return "EPIC REVEAL"
	if highest >= 2:
		return "RARE REVEAL"
	return "REWARD"

func _record_reward_history(notice: String, count: int) -> void:
	var entry := notice.strip_edges()
	if entry.is_empty():
		return
	if count > 0:
		entry += "  ×%d" % count
	_reward_history.push_front(entry)
	while _reward_history.size() > REWARD_HISTORY_CAP:
		_reward_history.pop_back()

func _on_boss_reward_choice_available(boss_id: String, _choices: Array) -> void:
	var panel := get_node_or_null("BossRewardChoicePanel") as PanelContainer
	if panel == null:
		panel = BOSS_REWARD_CHOICE_PANEL.new()
		panel.name = "BossRewardChoicePanel"
		panel.position = Vector2(310, 420)
		panel.custom_minimum_size = Vector2(460, 270)
		panel.choice_requested.connect(_on_boss_reward_choice_requested)
		add_child(panel)
	panel.open_for(boss_id)

func _on_boss_reward_choice_requested(boss_id: String, reward_id: String) -> void:
	var result: Dictionary = game_state.choose_boss_reward(boss_id, reward_id)
	if bool(result.get("success", false)):
		_push_field_note("Reward secured · %s" % reward_id.replace("_", " ").capitalize())
		var panel := get_node_or_null("BossRewardChoicePanel")
		if panel != null:
			panel.queue_free()
	else:
		_push_field_note("Reward choice unavailable · %s" % str(result.get("reason", "unknown")))

func _append_reward_context(summary: Dictionary, parts: Array) -> void:
	var contexts: Array = summary.get("loot_context", [])
	if contexts.is_empty() or loot_notice == null:
		return
	var context_text := str(contexts[0])
	if contexts.size() > 1:
		context_text += " +%d more" % (contexts.size() - 1)
	if parts.is_empty():
		loot_notice.text = context_text
	else:
		loot_notice.text = " · ".join(parts) + "\n" + context_text

func _play_reward_focus() -> void:
	## Reward framing is reserved for meaningful drops; ordinary gold/XP kills
	## stay uninterrupted so the camera never fights the player during combat.
	var scene := get_tree().current_scene
	if scene == null:
		return
	var camera_rig := scene.get_node_or_null("CameraRig")
	var hero := scene.get_node_or_null("Hero")
	if camera_rig != null and hero != null and camera_rig.has_method("play_focus_moment"):
		camera_rig.play_focus_moment(hero, Vector3(0.0, 3.8, 6.4),
			Vector3(0.0, 1.25, 0.0), 1.25)

func _show_loot_toast(duration: float) -> void:
	if loot_toast == null: return
	if _loot_toast_tween != null and _loot_toast_tween.is_valid():
		_loot_toast_tween.kill()
	loot_toast.visible = true
	loot_toast.modulate = Color.WHITE
	_loot_toast_timer = duration
	_loot_toast_tween = loot_toast.create_tween()
	_loot_toast_tween.tween_interval(maxf(duration - 0.6, 0.0))
	_loot_toast_tween.tween_property(loot_toast, "modulate:a", 0.0, 0.6)

func _on_quest_progress(message: String) -> void:
	_push_field_note(message)
	if message.to_lower().contains("unlocked"):
		if loot_title: loot_title.text = "REALM UNLOCKED"
		if loot_count: loot_count.text = "◆"
		if loot_notice: loot_notice.text = message + "  ·  Open the expedition journal to plan your route."
		_show_loot_toast(5.0)
	_queue_onboarding_hint()

func _queue_onboarding_hint() -> void:
	if game_state == null or not game_state.has_method("get_onboarding_hint"):
		return
	var hint := str(game_state.get_onboarding_hint())
	if hint.is_empty() or hint == _last_onboarding_hint:
		return
	_last_onboarding_hint = hint
	_push_field_note("FIELD GUIDE · " + hint)

func _push_field_note(msg: String) -> void:
	if msg.is_empty(): return
	_field_note_queue.append(msg)

func _show_next_field_note() -> void:
	if _field_note_queue.is_empty(): return
	var msg: String = _field_note_queue.pop_front()
	if field_note:
		field_note.text = msg
		field_note.modulate = Color.WHITE
	_field_note_visible = true
	_field_note_timer = 3.8
	if field_note:
		var tw := field_note.create_tween()
		tw.tween_interval(3.0)
		tw.tween_property(field_note, "modulate:a", 0.0, 0.8)

func _process(delta: float) -> void:
	_queue_onboarding_hint()
	if boss_health_bar and boss_health_bar.visible and combat_card and combat_card.visible:
		combat_card.visible = false
	_activity_poll_in -= delta
	if _activity_poll_in <= 0.0:
		_activity_poll_in = 0.35
		_refresh_nearby_activity()
	_interact_poll_in -= delta
	if _interact_poll_in <= 0.0:
		_interact_poll_in = INTERACT_POLL_SECONDS
		_refresh_interact_prompt()
	if _boss_telegraph_until_ms > 0 and Time.get_ticks_msec() >= _boss_telegraph_until_ms:
		_boss_telegraph_until_ms = 0
		if phase_indicator and _active_boss != null and is_instance_valid(_active_boss):
			phase_indicator.text = "PHASE %d" % (int(_active_boss.get("current_phase")) + 1)
	if _loot_toast_timer > 0.0:
		_loot_toast_timer -= delta
		if _loot_toast_timer <= 0.0 and loot_toast:
			loot_toast.visible = false
	if _field_note_visible:
		_field_note_timer -= delta
		if _field_note_timer <= 0.0:
			_field_note_visible = false
			if not _field_note_queue.is_empty():
				_show_next_field_note()
	elif not _field_note_queue.is_empty():
		_show_next_field_note()
	if combat_card and combat_card.visible and game_state.enemy_target != null and is_instance_valid(game_state.enemy_target):
		_update_combat_card(game_state.enemy_target)
	if boss_health_bar and boss_health_bar.visible and _active_boss != null and is_instance_valid(_active_boss):
		var hp := int(_active_boss.get("hp") if _active_boss.get("hp") != null else 0)
		var mhp := int(_active_boss.get("max_hp") if _active_boss.get("max_hp") != null else 1)
		var ph  := int(_active_boss.get("current_phase") if _active_boss.get("current_phase") != null else 0)
		update_boss_bar(hp, mhp, ph)

## Every overlay menu this HUD can raise. The HUD sits below the menu layers,
## but a sheet whose dimmer is input-ignoring still leaves the HUD reachable,
## so a second menu could open on top of the first and closing the top one left
## the other behind — two sheets, one never going away.
const OVERLAY_MENUS: Array[String] = ["SatchelUI", "ShopMenu", "SettingsMenu",
	"ForgeMenu", "StatsScreen", "DiamondShop"]

## One sheet at a time: every open path retires the others first.
func _retire_other_menus(except: String) -> void:
	var scene := get_tree().current_scene
	if scene != null:
		for menu_name in OVERLAY_MENUS:
			if menu_name == except:
				continue
			var node := scene.find_child(menu_name, true, false)
			if node != null and node.has_method("close"):
				node.call("close")
	if except == "QuizMenu":
		return
	var quiz := get_node_or_null("QuizMenu")
	# A sheet is a CanvasLayer, not a CanvasItem: read the property, never cast.
	if quiz != null and bool(quiz.get("visible")) and quiz.has_method("close"):
		quiz.call("close")

func _on_settings_pressed() -> void:
	# SettingsMenu lives in the gameplay scene and freezes the world while
	# open. Opening it here (rather than flipping get_tree().paused directly)
	# keeps the ref-counted world-freeze balanced with every other menu.
	_retire_other_menus("SettingsMenu")
	var s := get_tree().current_scene.find_child("SettingsMenu", true, false)
	if s is SettingsMenu:
		(s as SettingsMenu).open()
	else:
		get_tree().paused = not get_tree().paused

func _on_satchel_pressed() -> void:
	_retire_other_menus("SatchelUI")
	var s := get_tree().current_scene.find_child("SatchelUI", true, false)
	if s is SatchelUI:
		(s as SatchelUI).toggle()

func _on_scan_pressed() -> void:
	var im := get_node_or_null("/root/InputManager")
	if im and im.has_signal("scan_pressed"):
		im.emit_signal("scan_pressed")

func _on_shop_pressed() -> void:
	_retire_other_menus("ShopMenu")
	var shop := get_tree().current_scene.find_child("ShopMenu", true, false)
	if shop is ShopMenu:
		(shop as ShopMenu).open()
	else:
		_push_field_note("The trader is not here yet.")

func _on_camp_pressed() -> void:
	var camp := get_tree().current_scene.find_child("CampMenu", true, false)
	if camp != null and camp.has_method("open"):
		camp.open()
	else:
		_push_field_note("The camp is not available here.")

## The Glintmonger's Case is a real surface now, so the entry point shows only
## where the shop is actually instanced in the world — never as a dead button.
func _update_glint_visibility() -> void:
	if glint_button == null or not is_instance_valid(glint_button):
		return
	glint_button.visible = _glint_shop() != null

func _glint_shop() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("DiamondShop", true, false)

func _on_glint_pressed() -> void:
	_retire_other_menus("DiamondShop")
	var shop := _glint_shop()
	if shop != null and shop.has_method("open"):
		shop.call("open")
	else:
		_push_field_note("The Glintmonger is not here yet.")

func _on_stats_pressed() -> void:
	_retire_other_menus("SatchelUI")
	var s := get_tree().current_scene.find_child("SatchelUI", true, false)
	if s is SatchelUI:
		(s as SatchelUI).show_stats()
