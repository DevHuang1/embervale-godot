extends CanvasLayer
class_name HUD

## === HUD — Full Embervale Combat + Quest Interface ===

@onready var game_state : GameState = GameState
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
@onready var skill_buttons : Array = []
@onready var skill_glyph_labels : Array = []
@onready var skill_cd_labels : Array = []

var _loot_toast_timer : float = 0.0
var _field_note_queue : Array = []
var _field_note_timer : float = 0.0
var _field_note_visible := false
var _active_boss : Node3D = null

func _ready() -> void:
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
				btn.fight_pressed.connect(func(): _on_skill_pressed(idx))
			elif btn is BaseButton:
				btn.pressed.connect(func(): _on_skill_pressed(idx))
	_connect_signals()
	_refresh_all()
	if combat_card: combat_card.visible = false
	if boss_health_bar: boss_health_bar.visible = false
	if loot_toast: loot_toast.visible = false

func _connect_signals() -> void:
	game_state.hp_changed.connect(_on_hp_changed)
	game_state.xp_changed.connect(_on_xp_changed)
	game_state.gold_changed.connect(_on_gold_changed)
	game_state.diamonds_changed.connect(_on_diamonds_changed)
	game_state.level_up.connect(_on_level_up)
	game_state.weapon_changed.connect(_on_weapon_changed)
	game_state.skill_cooldown_changed.connect(_on_skill_cooldown_changed)
	game_state.stage_changed.connect(_on_stage_changed)
	game_state.loot_received.connect(_on_loot_received)
	if game_state.has_signal("quest_progress"):
		game_state.quest_progress.connect(_on_quest_progress)
	var rm := get_node_or_null("/root/RewardManager")
	if rm and rm.has_signal("reward_granted"):
		rm.reward_granted.connect(_on_reward_granted)
	if settings_button: settings_button.pressed.connect(_on_settings_pressed)
	if satchel_button: satchel_button.pressed.connect(_on_satchel_pressed)
	if scan_button: scan_button.pressed.connect(_on_scan_pressed)
	if shop_button: shop_button.pressed.connect(_on_shop_pressed)
	if stats_button: stats_button.pressed.connect(_on_stats_pressed)

func _refresh_all() -> void:
	_on_hp_changed(0, game_state.hp)
	_on_xp_changed(game_state.xp, game_state.level)
	_on_gold_changed(game_state.gold)
	_on_diamonds_changed(game_state.diamonds)
	_on_stage_changed(int(game_state.current_stage))
	_on_weapon_changed(game_state.equipped_weapon)

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
	if gold_label: gold_label.text = "🪙 %d" % total

func _on_diamonds_changed(total: int) -> void:
	if diamond_label: diamond_label.text = "💎 %d" % total

func _on_weapon_changed(weapon: Dictionary) -> void:
	var skills : Array = weapon.get("skills", [])
	for i in 3:
		var glyph = skill_glyph_labels[i] if i < skill_glyph_labels.size() else null
		var btn   = skill_buttons[i]       if i < skill_buttons.size()       else null
		if i < skills.size():
			if glyph: glyph.text = str(skills[i].get("name", "—"))[0]
			if btn is FightButton: btn.dimmed = false
			elif btn: btn.disabled = false
		else:
			if glyph: glyph.text = "—"
			if btn is FightButton: btn.dimmed = true
			elif btn: btn.disabled = true

func _on_skill_cooldown_changed(slot: int, remaining: float) -> void:
	if slot < 0 or slot >= 3: return
	var cd  = skill_cd_labels[slot]  if slot < skill_cd_labels.size()  else null
	var btn = skill_buttons[slot]    if slot < skill_buttons.size()    else null
	if cd:  cd.text = "" if remaining <= 0.0 else "%ds" % ceili(remaining)
	if btn is FightButton: btn.dimmed = remaining > 0.0
	elif btn: btn.disabled = remaining > 0.0

func _on_skill_pressed(slot: int) -> void:
	_auto_mark_for_skill(slot)
	var result := game_state.use_skill(slot)
	if result.get("success", false):
		var se := get_node_or_null("/root/SkillExecutor")
		if se == null:
			se = get_tree().current_scene.find_child("SkillExecutor", true, false)
		if se:
			se.call("execute_skill", slot, result.get("skill", {}))
	else:
		_push_field_note(str(result.get("message", "")))

## Mobile/keyboard parity: keyboard rites auto-snap onto the nearest foe
## (hero._on_skill_slot_pressed), so HUD presses must mark the same way or
## touch players get "no target lit" with no visible way to mark one.
func _auto_mark_for_skill(slot: int) -> void:
	var sk := game_state.get_skill(slot)
	if sk.is_empty() or str(sk.get("type", "")) == "heal_bloom":
		return
	var locked := game_state.enemy_target as Node3D
	if locked != null and is_instance_valid(locked):
		return
	var hero := get_tree().get_first_node_in_group("player") as Node3D
	if hero == null or not is_instance_valid(hero) \
			or not hero.has_method("nearest_enemy"):
		return
	var near := (hero.call("nearest_enemy", 14.0) as Node3D)
	if near != null:
		game_state.engage_enemy(near)

func show_combat_card(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy): hide_combat_card(); return
	if combat_card: combat_card.visible = true
	if enemy_name: enemy_name.text = str(enemy.get("display_name") if enemy.get("display_name") != null else enemy.name)
	_update_combat_card(enemy)

func hide_combat_card() -> void:
	if combat_card: combat_card.visible = false

func _update_combat_card(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy): return
	var hp = float(enemy.get("hp") if enemy.get("hp") != null else 0)
	var mhp = float(enemy.get("max_hp") if enemy.get("max_hp") != null else 1)
	if enemy_hp_bar: enemy_hp_bar.value = hp / max(mhp, 1.0)
	if combat_status: combat_status.text = "HP %d / %d" % [int(hp), int(mhp)]

func show_boss_bar(boss: Node3D, name_str: String) -> void:
	_active_boss = boss
	if boss_health_bar: boss_health_bar.visible = true
	if boss_name: boss_name.text = name_str

func hide_boss_bar() -> void:
	_active_boss = null
	if boss_health_bar: boss_health_bar.visible = false

func update_boss_bar(hp: int, max_hp: int, phase: int) -> void:
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = hp
	var names := ["PHASE I", "PHASE II", "PHASE III", "ENRAGE"]
	if phase_indicator: phase_indicator.text = names[clampi(phase, 0, 3)]

func _on_stage_changed(stage: int) -> void:
	var copy := game_state.get_quest_copy(stage) if game_state.has_method("get_quest_copy") else {}
	if chapter_label: chapter_label.text = str(copy.get("chapter", "Chapter I"))
	if title_label: title_label.text = str(copy.get("title", "Quest"))
	if instruction_label: instruction_label.text = str(copy.get("instruction", ""))

func _on_loot_received(notice: String, count: int) -> void:
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
		if loot_title: loot_title.text = "REWARD"
		if loot_count: loot_count.text = ""
		_show_loot_toast(3.0)

func _show_loot_toast(duration: float) -> void:
	if loot_toast == null: return
	loot_toast.visible = true
	loot_toast.modulate = Color.WHITE
	_loot_toast_timer = duration
	var tw := loot_toast.create_tween()
	tw.tween_interval(duration - 0.6)
	tw.tween_property(loot_toast, "modulate:a", 0.0, 0.6)

func _on_quest_progress(message: String) -> void:
	_push_field_note(message)

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
	get_tree().paused = not get_tree().paused

func _on_satchel_pressed() -> void:
	var s := get_tree().current_scene.find_child("Satchel", true, false)
	if s and s.has_method("toggle"): s.call("toggle")

func _on_scan_pressed() -> void:
	var sm := get_node_or_null("/root/ScanManager")
	if sm and sm.has_method("start_scan"): sm.call("start_scan")

func _on_shop_pressed() -> void:
	_push_field_note("The trader is not here yet.")

func _on_stats_pressed() -> void:
	var s := get_tree().current_scene.find_child("Satchel", true, false)
	if s and s.has_method("show_stats"): s.call("show_stats")
