extends CanvasLayer
class_name HUD

## === HUD — Embervale-style Quest Ledger + Combat UI ===

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var world: WorldManager = get_tree().root.find_child("Grove", true, false)

@onready var quest_ledger: PanelContainer = $Root/QuestLedger
@onready var chapter_label: Label = $Root/QuestLedger/QuestLedgerVBox/ChapterLabel
@onready var title_label: Label = $Root/QuestLedger/QuestLedgerVBox/TitleLabel
@onready var instruction_label: Label = $Root/QuestLedger/QuestLedgerVBox/InstructionLabel
@onready var player_plate: PanelContainer = $Root/PlayerPlate
@onready var level_badge: Label = $Root/PlayerPlate/PlateVBox/PlateHeader/LevelBadge
@onready var exp_bar: ProgressBar = $Root/PlayerPlate/PlateVBox/ExpBar
@onready var gold_label: Label = $Root/MetaRow/TopRow/GoldLabel
@onready var diamond_label: Label = $Root/MetaRow/TopRow/DiamondLabel
@onready var stats_button: Button = $Root/MetaRow/ActionRow/StatsButton
@onready var glint_button: Button = $Root/MetaRow/ActionRow/GlintButton
@onready var warmth_bar: ProgressBar = $Root/PlayerPlate/PlateVBox/WarmthBar
@onready var warmth_text: Label = $Root/PlayerPlate/PlateVBox/PlateHeader/WarmthText
@onready var satchel_button: Button = $Root/MetaRow/ActionRow/SatchelButton
@onready var satchel_count: Label = $Root/MetaRow/ActionRow/SatchelButton/SatchelCount
@onready var scan_button: Button = $Root/MetaRow/ActionRow/ScanButton
@onready var shop_button: Button = $Root/MetaRow/ActionRow/ShopButton
@onready var settings_button: Button = $Root/MetaRow/TopRow/SettingsButton
@onready var field_note: Label = $Root/FieldNote
@onready var combat_card: PanelContainer = $Root/CombatCard
@onready var enemy_name: Label = $Root/CombatCard/CombatVBox/EnemyName
@onready var enemy_hp_bar: ProgressBar = $Root/CombatCard/CombatVBox/EnemyHPBar
@onready var combat_status: Label = $Root/CombatCard/CombatVBox/CombatStatus
@onready var boss_health_bar: PanelContainer = $Root/BossHealthBar
@onready var boss_name: Label = $Root/BossHealthBar/BossName
@onready var boss_hp_bar: ProgressBar = $Root/BossHealthBar/BossHPBar
@onready var phase_indicator: Label = $Root/BossHealthBar/PhaseIndicator
@onready var loot_toast: PanelContainer = $Root/LootToast
@onready var loot_count: Label = $Root/LootToast/LootVBox/LootCount
@onready var loot_title: Label = $Root/LootToast/LootVBox/LootTitle
@onready var loot_notice: Label = $Root/LootToast/LootVBox/LootNotice
@onready var skill_buttons: Array[FightButton] = [
	$Root/SkillBar/Skill0Button,
	$Root/SkillBar/Skill1Button,
	$Root/SkillBar/Skill2Button,
]
@onready var skill_glyph_labels: Array[Label] = [
	$Root/SkillBar/Skill0Button/Skill0Glyph,
	$Root/SkillBar/Skill1Button/Skill1Glyph,
	$Root/SkillBar/Skill2Button/Skill2Glyph,
]
@onready var skill_cd_labels: Array[Label] = [
	$Root/SkillBar/Skill0Button/Skill0Cooldown,
	$Root/SkillBar/Skill1Button/Skill1Cooldown,
	$Root/SkillBar/Skill2Button/Skill2Cooldown,
]
@onready var attack_button: FightButton = $Root/SkillBar/AttackButton
@onready var attack_label: Label = $Root/SkillBar/AttackButton/AttackLabel
@onready var dodge_button: FightButton = $Root/DodgeButton
@onready var jump_button: FightButton = $Root/JumpButton
@onready var meta_row: Control = $Root/MetaRow
@onready var move_joystick: EmberJoystick = $Root/MoveJoystick

const SKILL_KEYS := ["Q", "E", "R"]

var _cooldown_poll := 0.0

func _ready() -> void:
	_apply_ui_theme()
	_connect_signals()
	_update_all()
	
	# Button connections
	satchel_button.pressed.connect(_on_satchel_pressed)
	scan_button.pressed.connect(_on_scan_pressed)
	shop_button.pressed.connect(_on_shop_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	stats_button.pressed.connect(_on_stats_pressed)
	glint_button.pressed.connect(_on_glint_pressed)
	minimap.set_realm(game_state.current_realm)
	game_state.realm_changed.connect(minimap.set_realm)
	# Hub slide-in on first appearance
	meta_row.modulate.a = 0.0
	create_tween().tween_property(meta_row, "modulate:a", 1.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for slot in 3:
		skill_buttons[slot].fight_pressed.connect(_on_skill_pressed.bind(slot))
	attack_button.fight_pressed.connect(_on_attack_pressed)
	attack_button.fight_released.connect(func(): InputManager.attack_released.emit())
	dodge_button.fight_pressed.connect(
		func(): InputManager.dodge_pressed.emit(Vector2.ZERO))
	jump_button.fight_pressed.connect(func(): InputManager.jump_pressed.emit())
	move_joystick.direction_changed.connect(_on_joystick_direction)
	# Action-button glyphs from assets/ui/icons (see credits note)
	attack_button.shape = FightButton.Shape.SLASH
	_set_button_icon(attack_button, "attack")
	_set_key_badge(attack_button, "LMB")
	_set_button_icon(dodge_button, "dodge")
	_set_key_badge(dodge_button, "SHIFT")
	_set_button_icon(jump_button, "jump")
	_set_key_badge(jump_button, "C")
	for slot in 3:
		_set_key_badge(skill_buttons[slot], SKILL_KEYS[slot])
	# The vector glyphs carry the meaning now — text labels underneath would
	# double-draw right on top of the art. Hide them (keep key badges).
	attack_label.visible = false
	for lbl in [$Root/DodgeButton/DodgeLabel, $Root/JumpButton/JumpLabel]:
		if lbl:
			lbl.visible = false

func _connect_signals() -> void:
	game_state.hp_changed.connect(_on_hp_changed)
	game_state.xp_changed.connect(_on_xp_changed)
	game_state.stage_changed.connect(_on_stage_changed)
	game_state.loot_received.connect(_on_loot_received)
	game_state.inventory_changed.connect(_on_inventory_changed)
	game_state.weapon_changed.connect(_on_weapon_changed)
	game_state.skill_cooldown_changed.connect(_on_skill_cooldown_changed)
	game_state.gold_changed.connect(_on_gold_changed)
	game_state.diamonds_changed.connect(_on_diamonds_changed)
	game_state.level_up.connect(_on_level_up)
	game_state.quest_progress.connect(_on_quest_progress)
	game_state.defeated.connect(_on_defeated)
	game_state.victory.connect(_on_victory)
	
	if world:
		world.get_node("Hero").position_changed.connect(_on_hero_position)
	
	# Combat signals via world
	var hero = world.get_node("Hero") if world else null
	if hero and hero.has_signal("combat_started"):
		hero.connect("combat_started", _on_combat_started)
	if hero and hero.has_signal("combat_ended"):
		hero.connect("combat_ended", _on_combat_ended)

func _process(delta: float) -> void:
	# Boss bar owns the upper band; the regular combat plate yields to it.
	if boss_health_bar.visible and combat_card.visible:
		combat_card.visible = false
	# Cooldown labels poll lightly; skill names follow the equipped kit
	_cooldown_poll -= delta
	if _cooldown_poll <= 0.0:
		_cooldown_poll = 0.15
		_update_skill_cooldowns()
		# Keep the engaged foe's plate honest while combat lasts
		if combat_card.visible and game_state.enemy_target != null \
				and is_instance_valid(game_state.enemy_target):
			var e: Node3D = game_state.enemy_target
			if e.has_method("get_hp"):
				enemy_hp_bar.value = e.get_hp()
			if e.has_method("is_dead") and e.is_dead():
				combat_card.visible = false
	_process_markers(delta)

func _update_all() -> void:
	_update_quest_ledger()
	_update_level_xp()
	_update_warmth()
	_update_gold()
	_update_diamonds()
	_update_satchel_count()
	_update_weapon_kit()
	_update_skill_cooldowns()

func _update_quest_ledger() -> void:
	var copy = game_state.get_quest_copy(game_state.current_stage)
	chapter_label.text = copy.chapter
	title_label.text = copy.title
	instruction_label.text = copy.instruction

func _update_level_xp() -> void:
	level_badge.text = "LV %02d" % game_state.level
	exp_bar.max_value = maxf(1.0, float(game_state.xp_to_next()))
	exp_bar.value = clampf(float(game_state.xp), 0.0, exp_bar.max_value)

func _update_gold() -> void:
	gold_label.text = "🪙 %d" % game_state.gold

func _update_diamonds() -> void:
	diamond_label.text = "💎 %d" % game_state.diamonds

func _update_warmth() -> void:
	warmth_bar.max_value = game_state.max_hp
	warmth_bar.value = game_state.hp
	warmth_text.text = "%d/%d" % [game_state.hp, game_state.max_hp]
	# Ember fill cools toward a hot alarm red as warmth runs out
	if warmth_bar is EmberBar:
		var pct := float(game_state.hp) / maxf(1.0, float(game_state.max_hp))
		(warmth_bar as EmberBar).accent = Color(0.85, 0.32, 0.18).lerp(
			Color(1.0, 0.16, 0.10), clampf(1.0 - pct * 2.4, 0.0, 1.0))

# === HUD theme tokens live in UiKit; this screen only wires them ===

func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := UiKit.glass_stylebox(false, border.a)
	sb.bg_color = bg
	sb.border_color = border
	return sb

func _style_button(b: Button) -> void:
	UiKit.style_button(b)

func _style_chip(lbl: Label, tint: Color) -> void:
	UiKit.chip_style(lbl, tint)

## Display face for headline chrome (ledger title, boss name, fanfares).
var _cinzel_bold: FontVariation = null

func _display_font() -> FontVariation:
	if _cinzel_bold == null:
		_cinzel_bold = FontVariation.new()
		_cinzel_bold.base_font = load("res://assets/fonts/Cinzel-Variable.ttf")
		_cinzel_bold.variation_opentype = {2003265652: 700}
	return _cinzel_bold

## One pass to restyle every panel, chip and action button.
func _apply_ui_theme() -> void:
	for panel in [player_plate, level_toast]:
		panel.add_theme_stylebox_override("panel",
			_panel_style(UiKit.GLASS_BG_RAISED, UiKit.BORDER_GOLD))
	# The quest ledger keeps its ink-on-paper fiction: warm letter stock
	# plus the generated fiber veil, so its sepia/ink label colors read.
	UiKit.apply_parchment(quest_ledger)
	combat_card.add_theme_stylebox_override("panel",
		_panel_style(UiKit.GLASS_BG, UiKit.BORDER_GOLD))
	boss_health_bar.add_theme_stylebox_override("panel",
		_panel_style(Color(0.09, 0.06, 0.05, 0.93), Color(0.62, 0.20, 0.12)))
	loot_toast.add_theme_stylebox_override("panel",
		_panel_style(UiKit.GLASS_BG, UiKit.EMBER))
	for panel in [quest_ledger, player_plate, combat_card,
			boss_health_bar, loot_toast, level_toast]:
		UiKit.apply_glass(panel)
	for btn in [stats_button, satchel_button, scan_button, shop_button,
			glint_button, settings_button]:
		_style_button(btn)
	_style_chip(gold_label, UiKit.EMBER_BRIGHT)
	_style_chip(diamond_label, Color(0.55, 0.85, 1.0))
	title_label.add_theme_font_override("font", _display_font())
	boss_name.add_theme_font_override("font", _display_font())
	toast_title.add_theme_font_override("font", _display_font())
	chapter_label.add_theme_font_override("font", _display_font())
	chapter_label.add_theme_font_size_override("font_size", 22)

func _update_satchel_count() -> void:
	var total = 0
	for item in game_state.inventory:
		total += item.quantity
	satchel_count.text = str(total)

func _update_skill_cooldowns() -> void:
	for slot in 3:
		var sk: Dictionary = game_state.get_skill(slot)
		var btn := skill_buttons[slot]
		if sk.is_empty():
			btn.set_cooldown(0.0, 1.0)
			btn.dimmed = true
			skill_glyph_labels[slot].text = ""
			skill_cd_labels[slot].text = ""
			continue
		var remaining := float(game_state.skill_cooldowns.get("slot_%d" % slot, 0.0))
		btn.set_cooldown(remaining, float(sk.get("cooldown", 1.0)))
		btn.accent = _skill_accent(str(sk.get("type", "")))
		btn.tooltip_text = "%s (%s)" % [str(sk.get("name", "?")), SKILL_KEYS[slot]]
		skill_glyph_labels[slot].text = str(sk.get("glyph", ""))
		skill_cd_labels[slot].text = "%ds" % ceili(remaining) if remaining > 0.0 else ""
		# Vector glyph by rite family; emoji stays as fallback when the
		# icon set has no match for the type.
		var icon := _icon_texture(str(sk.get("type", "")))
		if icon != null:
			_set_button_icon(btn, str(sk.get("type", "")), _skill_accent(str(sk.get("type", ""))))
			skill_glyph_labels[slot].visible = false
		else:
			if btn.has_node("TypeIcon"):
				btn.get_node("TypeIcon").hide()
			skill_glyph_labels[slot].visible = true
		# Dim targeted rites while uncastable (mirrors use_skill gating);
		# heal blooms stay lit everywhere.
		var needs_target := str(sk.get("type", "")) != "heal_bloom"
		var target_ok: bool = game_state.enemy_target != null \
			and is_instance_valid(game_state.enemy_target)
		btn.dimmed = remaining > 0.0 or (needs_target and
			(game_state.combat_state != GameState.CombatState.COMBAT or not target_ok))
	attack_button.dimmed = game_state.combat_state \
		in [GameState.CombatState.DEFEATED, GameState.CombatState.VICTORY]

## Skill buttons tint by rite family so the kit reads at thumb-glance.
func _skill_accent(skill_type: String) -> Color:
	match skill_type:
		"heal_bloom":
			return Color(0.62, 0.85, 0.45)
		"explosion", "comet":
			return Color(0.62, 0.55, 0.96)
		"dash_strike":
			return Color(1.0, 0.62, 0.30)
		"whirl":
			return Color(0.45, 0.78, 0.62)
		_:
			return Color(0.96, 0.72, 0.29)

# === Action icons (game-icons.net, CC-BY 3.0 — see credits) ===
const _ICON_DIR := "res://assets/ui/icons/"
var _icon_cache: Dictionary = {}

func _icon_texture(icon_name: String) -> Texture2D:
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	var path := _ICON_DIR + icon_name + ".svg"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_icon_cache[icon_name] = tex
	return tex

## Overlay a centered vector glyph on a FightButton (replaces emoji text).
## Inset margins keep the glyph inside the drawn ring, clear of the
## cooldown arc; EXPAND_IGNORE_SIZE lets the 512px SVG shrink to fit.
func _set_button_icon(button: Control, icon_name: String,
		tint: Color = Color(1.0, 0.93, 0.78)) -> void:
	var tex := _icon_texture(icon_name)
	if tex == null:
		return
	var icon: TextureRect = button.get_node_or_null("TypeIcon")
	if icon == null:
		icon = TextureRect.new()
		icon.name = "TypeIcon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			icon.set("offset_" + side, 16.0)
		button.add_child(icon)
	icon.texture = tex
	icon.self_modulate = tint
	icon.show()

## Small key hint pinned to the button's top-left corner.
func _set_key_badge(button: Control, key_text: String) -> void:
	var badge: Label = button.get_node_or_null("KeyBadge")
	if badge == null:
		badge = Label.new()
		badge.name = "KeyBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 14)
		badge.add_theme_color_override("font_color", Color(1, 0.93, 0.78, 0.9))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		badge.add_theme_constant_override("outline_size", 5)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.position = Vector2(-30, 6)
		button.add_child(badge)
	badge.text = key_text

func _update_weapon_kit() -> void:
	var weapon: Dictionary = game_state.equipped_weapon
	attack_label.text = "%s\n%s" % [
		str(weapon.get("glyph", "")), str(weapon.get("name", ""))]
	attack_button.tooltip_text = "Strike %s (LMB)" % str(weapon.get("name", ""))
	_update_skill_cooldowns()

func _on_gold_changed(_total: int) -> void:
	_update_gold()

func _on_diamonds_changed(_total: int) -> void:
	_update_diamonds()

## Feed the minimap its landmark set at a lazy cadence.
var _marker_poll := 0.0

func _process_markers(delta: float) -> void:
	_marker_poll -= delta
	if _marker_poll > 0.0 or world == null:
		return
	_marker_poll = 0.4
	var marks: Array[Dictionary] = []
	for pair in [["ShardSpawn", "🔥"], ["BeaconSpawn", "🔥"],
			["MoonfenGate", "🚪"], ["ReturnGate", "🚪"],
			["RelicPedestal", "⛓"]]:
		var n := world.get_node_or_null(pair[0])
		if n is Node3D:
			marks.append({"pos": (n as Node3D).global_position, "glyph": pair[1]})
	if world.matriarch != null and is_instance_valid(world.matriarch):
		marks.append({"pos": world.matriarch.global_position, "glyph": "💀"})
	minimap.markers = marks
	minimap.queue_redraw()

## Level-up fanfare + toast; auto-fades and points await allocation.
func _on_level_up(new_level: int, points: int) -> void:
	toast_title.text = "⬆ LEVEL UP!"
	toast_sub.text = "LV %02d reached · +%d stat points" % [new_level, points]
	level_toast.visible = true
	level_toast.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(level_toast, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.4)
	tw.tween_property(level_toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): level_toast.visible = false)
	audio.play_forge_success()
	_update_level_xp()
	_update_warmth()

func _on_stats_pressed() -> void:
	var screen := get_tree().root.find_child("StatsScreen", true, false)
	if not screen:
		var scene: PackedScene = load("res://scenes/ui/stats_screen.tscn")
		screen = scene.instantiate()
		get_tree().current_scene.add_child(screen)
	screen.open()
	audio.play_ui_blip()

# === Signal Handlers ===

func _on_inventory_changed() -> void:
	_update_satchel_count()

func _on_weapon_changed(_weapon: Dictionary) -> void:
	_update_satchel_count()
	_update_weapon_kit()

func _on_hp_changed(old: int, new: int) -> void:
	_update_warmth()
	if new <= 0:
		field_note.text = "✦ The mist folds around your lantern."

func _on_xp_changed(new_xp: int, new_level: int) -> void:
	_update_level_xp()
	if new_level > game_state.level - 1:
		field_note.text = "✦ Ember marks gather — your lantern burns brighter."

func _on_stage_changed(stage: int) -> void:
	_update_quest_ledger()

func _on_loot_received(notice: String, count: int) -> void:
	loot_count.text = "+%d" % count
	loot_notice.text = notice
	loot_toast.visible = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(loot_toast, "modulate:a", 1.0, 0.15)
	tween.tween_callback(_hide_loot_toast).set_delay(2.8)

func _hide_loot_toast() -> void:
	var tween = create_tween()
	tween.tween_property(loot_toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): loot_toast.visible = false)

func _on_skill_cooldown_changed(_slot: int, _remaining: float) -> void:
	_update_skill_cooldowns()

func _on_embers_changed(_total: int) -> void:
	_update_gold()

func _on_quest_progress(message: String) -> void:
	field_note.text = "✦ %s" % message

func _on_combat_started(enemy: Node3D) -> void:
	combat_card.visible = true
	enemy_name.text = _display_enemy_name(enemy)
	enemy_hp_bar.max_value = enemy.max_hp if enemy.has_method("get_max_hp") else 28
	enemy_hp_bar.value = enemy.hp if enemy.has_method("get_hp") else 28
	combat_status.text = "Target locked — Elian closes in"

## "@Hushling@12" → "Hushling": scene-instanced nodes carry engine scaffolding.
func _display_enemy_name(enemy: Node3D) -> String:
	var parts := String(enemy.name).split("@", false)
	var clean := parts[parts.size() - 1] if parts.size() > 0 else String(enemy.name)
	return String(clean).rstrip("0123456789").capitalize()

func _on_combat_ended() -> void:
	combat_card.visible = false

func _on_hero_position(pos: Vector3) -> void:
	# Could update minimap here
	pass

func _on_defeated() -> void:
	field_note.text = "✦ The mist folds around your lantern."
	# Show defeat modal

func _on_victory() -> void:
	field_note.text = "✦ The grove remembers the way home."
	# Show victory modal

# === Button Handlers ===

func _on_satchel_pressed() -> void:
	get_tree().root.find_child("SatchelUI", true, false).visible = true

func _on_joystick_direction(direction: Vector2) -> void:
	InputManager.move_input.emit(direction)

func _on_scan_pressed() -> void:
	# Open scan camera
	InputManager.scan_pressed.emit()

func _on_shop_pressed() -> void:
	var shop := get_tree().root.find_child("ShopMenu", true, false)
	if not shop:
		var scene: PackedScene = load("res://scenes/ui/shop_menu.tscn")
		shop = scene.instantiate()
		get_tree().current_scene.add_child(shop)
	shop.open()

func _on_settings_pressed() -> void:
	var settings = get_tree().root.find_child("SettingsMenu", true, false)
	if not settings:
		var scene: PackedScene = load("res://scenes/ui/settings_menu.tscn")
		settings = scene.instantiate()
		# current_scene can be null early in boot — fall back to root.
		var host := get_tree().current_scene
		if host == null:
			host = get_tree().root
		host.add_child(settings)
	settings.open()

func _on_skill_pressed(slot: int) -> void:
	InputManager.skill_slot_pressed.emit(slot)

func _on_attack_pressed() -> void:
	InputManager.attack_pressed.emit()
# Extra UI refs
@onready var minimap: MiniMap = $Root/MinimapContainer
@onready var level_toast: PanelContainer = $Root/LevelToast
@onready var toast_title: Label = $Root/LevelToast/ToastVBox/ToastTitle
@onready var toast_sub: Label = $Root/LevelToast/ToastVBox/ToastSub


func _on_glint_pressed() -> void:
	var shop := get_tree().root.find_child("DiamondShop", true, false)
	if not shop:
		var scene: PackedScene = load("res://scenes/ui/diamond_shop.tscn")
		shop = scene.instantiate()
		get_tree().current_scene.add_child(shop)
	shop.open()
	audio.play_ui_blip()
