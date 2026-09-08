extends CanvasLayer
class_name HUD

const BOSS_REWARD_CHOICE_PANEL := preload("res://scripts/ui/boss_reward_choice_panel.gd")
const REWARD_REVEAL_PANEL := preload("res://scripts/ui/reward_reveal_panel.gd")

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
var journal_button: Button
var journal_panel: PanelContainer
var _reward_history: Array[String] = []
var _reward_reveal_panel: RewardRevealPanel = null
const REWARD_HISTORY_CAP := 8
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
	# Skill bar buttons - lazy find
	for i in 3:
		var btn = get_node_or_null("Root/SkillBar/Skill%dButton" % i)
		var glyph = btn.get_node_or_null("Skill%dGlyph" % i) if btn else null
		var cd = btn.get_node_or_null("Skill%dCooldown" % i) if btn else null
		skill_buttons.append(btn)
		skill_glyph_labels.append(glyph)
		skill_cd_labels.append(cd)
		if btn:
			var idx := i
			if btn is FightButton:
				btn.fight_pressed.connect(func(): input_manager.skill_slot_pressed.emit(idx))
			elif btn is BaseButton:
				btn.pressed.connect(func(): input_manager.skill_slot_pressed.emit(idx))
	_wire_action_buttons()
	_build_camp_button()
	_build_journal_button()
	get_viewport().size_changed.connect(_layout_journal_panel)
	_connect_signals()
	_refresh_all()
	_queue_onboarding_hint()
	if combat_card: combat_card.visible = false
	if boss_health_bar: boss_health_bar.visible = false
	if loot_toast: loot_toast.visible = false
	_apply_touch_target_scale()

func _connect_dungeon_completion() -> void:
	var expansion := get_tree().root.find_child("RealmExpansion", true, false)
	if expansion == null or not expansion.has_signal("dungeon_completed"):
		return
	if not expansion.dungeon_completed.is_connected(_on_dungeon_completed):
		expansion.dungeon_completed.connect(_on_dungeon_completed)

func _on_dungeon_completed(dungeon_id: String) -> void:
	var entries: Array[Dictionary] = [{
		"id": dungeon_id,
		"label": "%s CLEARED" % dungeon_id.replace("_", " ").to_upper(),
		"quantity": 1,
		"rarity": 3,
	}]
	_show_reward_reveal_entries(entries, "dungeon")

func _show_reward_reveal_entries(entries: Array[Dictionary], source: String) -> void:
	if _reward_reveal_panel != null and is_instance_valid(_reward_reveal_panel):
		_reward_reveal_panel.dismiss()
	var wrapper := CenterContainer.new()
	wrapper.name = "RewardRevealCenter"
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reward_reveal_panel = REWARD_REVEAL_PANEL.new()
	_reward_reveal_panel.custom_minimum_size = Vector2(420.0, 0.0)
	wrapper.add_child(_reward_reveal_panel)
	add_child(wrapper)
	_reward_reveal_panel.dismissed.connect(wrapper.queue_free)
	_reward_reveal_panel.open_for(entries, source)

func _apply_mobile_control_preferences() -> void:
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
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
	if layout == "left_handed" and joystick != null:
		joystick.anchor_left = 1.0
		joystick.anchor_right = 1.0
		joystick.offset_left = -232.0
		joystick.offset_right = -48.0
		joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT,
			Control.PRESET_MODE_MINSIZE, 24)

func _apply_touch_target_scale() -> void:
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
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
	var rm := get_node_or_null("/root/RewardManager")
	if rm and rm.has_signal("reward_granted"):
		rm.reward_granted.connect(_on_reward_granted)
	if rm and rm.has_signal("boss_reward_choice_available"):
		rm.boss_reward_choice_available.connect(_on_boss_reward_choice_available)
	if settings_button: settings_button.pressed.connect(_on_settings_pressed)
	if satchel_button: satchel_button.pressed.connect(_on_satchel_pressed)
	if scan_button: scan_button.pressed.connect(_on_scan_pressed)
	if shop_button: shop_button.pressed.connect(_on_shop_pressed)
	if stats_button: stats_button.pressed.connect(_on_stats_pressed)
	if enemy_scan_button: enemy_scan_button.pressed.connect(_on_enemy_scan_pressed)
	if target_switch_button: target_switch_button.pressed.connect(_on_target_switch_pressed)
	if lesson_button: lesson_button.pressed.connect(_on_lesson_pressed)
	if journal_button: journal_button.pressed.connect(_on_journal_pressed)

func _build_journal_button() -> void:
	journal_button = Button.new()
	journal_button.text = "OPEN EXPEDITION JOURNAL"
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
	UiKit.style_label(title, &"MenuTitle", 20)
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
	UiKit.style_label(map, &"Caption", 13)
	box.add_child(map)
	var route := Label.new()
	route.text = "PRIMARY ROUTE\n%s\n\n%s\nWHY  ·  %s\nRISK  ·  %s\nREWARD  ·  %s\nNEXT  ·  %s" % [
		str(copy.get("title", "Quest")), str(copy.get("instruction", "")),
		str(copy.get("why", "")), str(copy.get("risk", "")),
		str(copy.get("reward", "")), str(copy.get("next_action", ""))]
	route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(route, &"Body", 15)
	box.add_child(route)
	var checkpoint := Label.new()
	checkpoint.text = "CURRENT MILESTONE  ·  %s" % str(game_state.route_checkpoint_id).replace("_", " ").to_upper()
	UiKit.style_label(checkpoint, &"Caption", 14)
	box.add_child(checkpoint)
	var route_map := Label.new()
	var route_nodes := [
		["grove_arrival", "WHISPERGROVE", "Start"],
		["sprite_found", "BRAMBLEWOOD", "Gather"],
		["elite_gate", "BRAMBLEWOOD", "Elite"],
		["beacon_relit", "OLD BEACON", "Unlock"],
	]
	var route_map_lines: Array[String] = ["ROUTE MAP  ·  LAST SAFE PATH"]
	for route_node in route_nodes:
		var route_id := str(route_node[0])
		var route_marker := "●" if route_id == str(game_state.route_checkpoint_id) else ("✓" if _checkpoint_is_reached(route_id, str(game_state.route_checkpoint_id)) else "○")
		route_map_lines.append("%s  %s  ·  %s" % [route_marker, str(route_node[1]), str(route_node[2])])
	route_map.text = "\n".join(route_map_lines)
	UiKit.style_label(route_map, &"Caption", 13)
	box.add_child(route_map)
	var recovery: Dictionary = game_state.get_activity_recovery() if game_state.has_method("get_activity_recovery") else {}
	if not recovery.is_empty():
		var recovery_label := Label.new()
		recovery_label.name = "ActivityRecovery"
		recovery_label.text = "RECOVERY  ·  %s\n%s\n%s" % [str(recovery.get("status", "unknown")).to_upper(), str(recovery.get("reason", "Activity snapshot preserved.")), str(recovery.get("next_action", "Return to the recorded checkpoint."))]
		recovery_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(recovery_label, &"Caption", 13)
		box.add_child(recovery_label)
	var realm_id := str(game_state.get("current_realm") if game_state.get("current_realm") != null else "bramblewood")
	var realm_profile: Dictionary = RealmIdentityCatalog.for_realm(realm_id)
	var identity := Label.new()
	identity.text = "REALM READ\n%s\nRESOURCE  ·  %s\nLANDMARK REWARD  ·  %s" % [
		str(realm_profile.get("traversal", "Explore the realm")),
		str(realm_profile.get("resource_ritual", "Gather local materials")),
		str(realm_profile.get("landmark_reward", "Discover a landmark"))]
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(identity, &"Caption", 13)
	box.add_child(identity)
	var optional := Label.new()
	optional.text = "OPTIONAL OBJECTIVES"
	UiKit.style_label(optional, &"Caption", 14)
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
		UiKit.style_label(empty, &"Caption", 13)
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
			UiKit.style_label(objective_label, &"Caption", 13)
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
	reward_direction.text = "REWARD DIRECTION\nComplete route objectives to earn gold, XP, and scan progress."
	reward_direction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(reward_direction, &"Caption", 13)
	box.add_child(reward_direction)
	var ownership := Label.new()
	ownership.name = "OwnershipLedgerSummary"
	ownership.text = "OWNERSHIP LEDGER\nGold %d · Diamonds %d · Scans %d\nWeapons %d · Armor %d · Purchases %d" % [
		game_state.gold, game_state.diamonds, game_state.scans_remaining,
		game_state.forged_weapons.size(), game_state.forged_armors.size(),
		game_state.get_purchase_ledger().size()]
	ownership.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(ownership, &"Caption", 13)
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
	UiKit.style_label(history, &"Caption", 13)
	box.add_child(history)
	var close := Button.new()
	close.text = "CLOSE JOURNAL"
	close.pressed.connect(_on_journal_pressed)
	UiKit.style_secondary_button(close)
	box.add_child(close)
	add_child(journal_panel)
	_layout_journal_panel()

func _checkpoint_is_reached(candidate: String, current: String) -> bool:
	var order := ["grove_arrival", "sprite_found", "elite_gate", "beacon_relit"]
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
				var kind := str(skills[i].get("type", ""))
				glyph.text = ""
				if btn is FightButton:
					(btn as FightButton).skill_kind = kind
			if btn is FightButton:
				(btn as FightButton).set_action_state("available", "Ready when the cooldown is clear")
			elif btn: btn.disabled = false
		else:
			if glyph: glyph.text = "—"
			if btn is FightButton: (btn as FightButton).skill_kind = ""
			if btn is FightButton: (btn as FightButton).set_action_state("unavailable", "Equip a weapon skill")
			elif btn: btn.disabled = true

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
	if _analyzed_enemy_id != enemy.get_instance_id():
		_analyzed_enemy_id = 0
	if enemy_name: enemy_name.text = str(enemy.get("display_name") if enemy.get("display_name") != null else enemy.name)
	_update_combat_card(enemy)

func hide_combat_card() -> void:
	if combat_card: combat_card.visible = false

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
			"This foe is already resolved" if analyzed else ("Earn or purchase a scan" if game_state.scans_remaining <= 0 else "Reveal bounded combat stats"))
		enemy_scan_button.disabled = bool(scan_state.get("disabled", false))
		enemy_scan_button.text = "FOE ANALYZED" if analyzed else "ANALYZE FOE  ·  %d SCAN" % game_state.scans_remaining
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
		if combat_status: combat_status.text = "No scans remaining — earn one from a quest."
		return
	var report := Bestiary.scan_report(enemy)
	if report.is_empty():
		if combat_status: combat_status.text = "Lens could not resolve this foe."
		return
	if combat_status:
		combat_status.text = "HP %d · ATK %d · SPD %.1f\nPHYS RES %d%% · MAGIC RES %d%%\n%s\n%s" % [
			int(report.hp), int(report.attack), float(report.speed),
			int(report.physical_resist), int(report.magic_resist), str(report.reward),
			str(report.ecology)]
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
	_refresh_objectives()

func _on_route_checkpoint_changed(checkpoint_id: String) -> void:
	if checkpoint_label == null or checkpoint_id.is_empty():
		return
	var names := {"grove_arrival": "GROVE ARRIVAL", "hushling_cleared": "HUSHLING CLEARED", "shard_claimed": "EMBER SHARD CLAIMED", "beacon_relit": "BEACON RELIT"}
	checkpoint_label.text = "CHECKPOINT  ·  %s" % str(names.get(checkpoint_id, checkpoint_id.to_upper()))

func _on_inventory_changed(_notice: String = "", _count: int = 0) -> void:
	_refresh_objectives()

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
	var gold := int(summary.get("gold", 0))
	var xp   := int(summary.get("xp",   0))
	var gems := int(summary.get("diamonds", 0))
	if gold > 0 or xp > 0 or gems > 0:
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
		if not summary.get("weapons", []).is_empty() or not summary.get("armors", []).is_empty():
			_show_reward_reveal(summary)
		_record_reward_history(" · ".join(parts), 0)
	elif not summary.get("loot_context", []).is_empty():
		_append_reward_context(summary, [])
		if loot_title: loot_title.text = "LOOT"
		if loot_count: loot_count.text = ""
		_show_loot_toast(3.0)
		_record_reward_history(str(summary.get("loot_context", ["Loot context updated"])[0]), 0)

func _show_reward_reveal(summary: Dictionary) -> void:
	if _reward_reveal_panel != null and is_instance_valid(_reward_reveal_panel):
		_reward_reveal_panel.dismiss()
	var wrapper := CenterContainer.new()
	wrapper.name = "RewardRevealCenter"
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reward_reveal_panel = REWARD_REVEAL_PANEL.new()
	_reward_reveal_panel.custom_minimum_size = Vector2(420.0, 0.0)
	wrapper.add_child(_reward_reveal_panel)
	add_child(wrapper)
	_reward_reveal_panel.dismissed.connect(wrapper.queue_free)
	var entries: Array[Dictionary] = []
	for key in ["weapons", "armors"]:
		for raw in summary.get(key, []):
			if raw is Dictionary:
				var drop: Dictionary = raw
				entries.append({"id": str(drop.get("id", "")),
					"label": str(drop.get("id", "")).replace("_", " ").capitalize(),
					"quantity": 1, "rarity": _rarity_rank(drop.get("rarity", 0))})
	_reward_reveal_panel.open_for(entries, "loot")

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

func _on_settings_pressed() -> void:
	# SettingsMenu lives in the gameplay scene and freezes the world while
	# open. Opening it here (rather than flipping get_tree().paused directly)
	# keeps the ref-counted world-freeze balanced with every other menu.
	var s := get_tree().current_scene.find_child("SettingsMenu", true, false)
	if s is SettingsMenu:
		(s as SettingsMenu).open()
	else:
		get_tree().paused = not get_tree().paused

func _on_satchel_pressed() -> void:
	var s := get_tree().current_scene.find_child("SatchelUI", true, false)
	if s is SatchelUI:
		(s as SatchelUI).toggle()

func _on_scan_pressed() -> void:
	# Route through InputManager.scan_pressed — the ForgeMenu is the single
	# listener that opens itself and drives the scan request UI. Calling
	# ScanManager.start_scan() directly here bypassed the menu, so scans
	# started invisibly with no feedback.
	var im := get_node_or_null("/root/InputManager")
	if im and im.has_signal("scan_pressed"):
		im.emit_signal("scan_pressed")
	else:
		var sm := get_node_or_null("/root/ScanManager")
		if sm and sm.has_method("start_scan"):
			sm.call("start_scan")

func _on_shop_pressed() -> void:
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

func _on_stats_pressed() -> void:
	var s := get_tree().current_scene.find_child("SatchelUI", true, false)
	if s is SatchelUI:
		(s as SatchelUI).show_stats()
