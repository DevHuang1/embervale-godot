extends Node
class_name SkillExecutor

## === SkillExecutor — Weapon Skill World Effects ===
## AutoLoad (or placed in scene). Fires all 12 weapon skills in the 3D world.
## Called by HUD._on_skill_pressed() after GameState.use_skill() succeeds.
##
## Skill types handled:
##   aoe         — ring of damage around player
##   explosion   — projectile arc then burst on marked target
##   heal_bloom  — heal + verdant particle bloom around player
##   strike      — dash toward target + heavy slash
##   whirl       — spinning ring damage
##   dash_strike — blink behind target + slash
##   comet       — slow-falling comet (delayed AoE)
##   heavy_aoe   — slow stomp + massive ring
##
## All effects use CombatFx — no external assets required.

signal skill_fired(slot: int, skill: Dictionary)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Main entry point called by HUD.
func execute_skill(slot: int, skill: Dictionary) -> void:
	if skill.is_empty():
		return
	var gs    := get_node_or_null("/root/GameState")
	var hero  := _find_hero()
	var target := _get_target(gs)

	var kind   : String = str(skill.get("type", "aoe"))
	var dmg    : int    = _calc_damage(skill, gs)
	var radius : float  = float(skill.get("radius", 4.0))
	var heal   : int    = int(skill.get("heal",   0))

	match kind:
		"aoe":          _skill_aoe(hero, target, radius, dmg)
		"explosion":    _skill_explosion(hero, target, radius, dmg)
		"heal_bloom":   _skill_heal_bloom(hero, heal, gs)
		"strike":       _skill_strike(hero, target, dmg)
		"whirl":        _skill_whirl(hero, radius, dmg)
		"dash_strike":  _skill_dash_strike(hero, target, dmg)
		"comet":        _skill_comet(hero, target, radius, dmg)
		"heavy_aoe":    _skill_heavy_aoe(hero, radius, dmg)
		_:              _skill_aoe(hero, target, radius, dmg)

	skill_fired.emit(slot, skill)

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _find_hero() -> Node3D:
	if get_tree() == null: return null
	var heroes := get_tree().get_nodes_in_group("player")
	return heroes[0] as Node3D if not heroes.is_empty() else null

func _get_target(gs: Node) -> Node3D:
	if gs == null: return null
	return gs.get("enemy_target") as Node3D

func _calc_damage(skill: Dictionary, gs: Node) -> int:
	var base_dmg := 8
	if gs != null and gs.has_method("get_base_auto_damage"):
		base_dmg = gs.call("get_base_auto_damage")
	return int(round(base_dmg * float(skill.get("dmg_mult", 1.0))))

func _weapon_color(gs: Node) -> Color:
	if gs == null: return Color(1.0, 0.72, 0.28)
	var weapon : Dictionary = gs.get("equipped_weapon") if gs.get("equipped_weapon") != null else {}
	match str(weapon.get("element", "fire")):
		"nature":    return Color(0.42, 0.88, 0.28)
		"arcane":    return Color(0.70, 0.42, 1.00)
		"ice":       return Color(0.55, 0.82, 1.00)
		_:           return Color(1.0, 0.55, 0.12)

func _deal_skill_damage(source: Node3D, center: Vector3, radius: float, damage: int) -> void:
	if source == null or not source.is_inside_tree(): return
	var space := source.get_world_3d().direct_space_state
	var shape  := SphereShape3D.new(); shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = (1 << 1) | (1 << 4)  # enemy + boss
	var results := space.intersect_shape(params)
	for r in results:
		var col := r.collider as Node3D
		if col != null and col.has_method("take_damage"):
			col.call("take_damage", damage, center.direction_to(col.global_position))

# ─── Skill implementations ────────────────────────────────────────────────────

func _skill_aoe(hero: Node3D, _target: Node3D, radius: float, damage: int) -> void:
	if hero == null: return
	var gs := get_node_or_null("/root/GameState")
	var col := _weapon_color(gs)
	CombatFx.spawn_ring(hero, hero.global_position, radius, col, 0.55)
	CombatFx.spawn_burst(hero, hero.global_position + Vector3(0, 0.8, 0), col, 22, 6.0, 0.45, 0.18)
	_deal_skill_damage(hero, hero.global_position, radius, damage)
	_shake(0.35)

func _skill_explosion(hero: Node3D, target: Node3D, radius: float, damage: int) -> void:
	if hero == null: return
	var gs  := get_node_or_null("/root/GameState")
	var col := _weapon_color(gs)
	var dest := target.global_position if target != null and is_instance_valid(target) \
		else hero.global_position + hero.global_transform.basis.z * -5.0
	# Telegraph
	CombatFx.spawn_ground_telegraph(hero, dest, radius, col, 0.9)
	var gen := 0
	var t := get_tree().create_timer(0.9, false)
	t.timeout.connect(func():
		CombatFx.spawn_burst(hero, dest + Vector3(0, 0.8, 0), col, 28, 8.5, 0.5, 0.22)
		CombatFx.spawn_ring(hero, dest, radius, col, 0.45)
		_deal_skill_damage(hero, dest, radius, damage)
		_shake(0.45))

func _skill_heal_bloom(hero: Node3D, heal: int, gs: Node) -> void:
	if hero == null: return
	var col := Color(0.42, 0.88, 0.30)
	CombatFx.spawn_burst(hero, hero.global_position + Vector3(0, 1.2, 0), col, 24, 4.5, 0.65, 0.16)
	CombatFx.spawn_ring(hero, hero.global_position, 2.8, col, 0.55)
	if gs != null and gs.has_method("heal"):
		var actual := gs.call("heal", heal)
		FloatingText.spawn_on_entity(hero, "+%d" % actual, col)

func _skill_strike(hero: Node3D, target: Node3D, damage: int) -> void:
	if hero == null or target == null or not is_instance_valid(target): return
	var gs  := get_node_or_null("/root/GameState")
	var col := _weapon_color(gs)
	# Glide hero toward target
	var dest := target.global_position + (hero.global_position - target.global_position).normalized() * 2.0
	var tw := hero.create_tween()
	tw.tween_property(hero, "global_position", dest, 0.18).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(func():
		CombatFx.spawn_slash(hero, target.global_position + Vector3(0, 1.0, 0), col)
		CombatFx.spawn_burst(hero, target.global_position + Vector3(0, 0.8, 0), col, 18, 7.0, 0.38, 0.16)
		if target.has_method("take_damage"):
			target.call("take_damage", damage, hero.global_position.direction_to(target.global_position))
		_shake(0.40))

func _skill_whirl(hero: Node3D, radius: float, damage: int) -> void:
	if hero == null: return
	var gs  := get_node_or_null("/root/GameState")
	var col := _weapon_color(gs)
	# 3 spinning ring pulses
	for i in 3:
		var r   := radius * (0.6 + float(i) * 0.3)
		var dl  := float(i) * 0.18
		var t := get_tree().create_timer(dl, false)
		t.timeout.connect(func():
			CombatFx.spawn_ring(hero, hero.global_position, r, col, 0.4)
			_deal_skill_damage(hero, hero.global_position, r, int(damage * 0.85)))
	_shake(0.28)

func _skill_dash_strike(hero: Node3D, target: Node3D, damage: int) -> void:
	if hero == null or target == null or not is_instance_valid(target): return
	var gs  := get_node_or_null("/root/GameState")
	var col := _weapon_color(gs)
	var behind := target.global_position + target.global_transform.basis.z * 1.8
	# Blink
	CombatFx.spawn_burst(hero, hero.global_position, col, 12, 5.5, 0.22, 0.14)
	hero.global_position = behind
	CombatFx.spawn_burst(hero, behind, col, 14, 6.0, 0.28, 0.16)
	CombatFx.spawn_slash(hero, target.global_position + Vector3(0, 0.9, 0), col)
	if target.has_method("take_damage"):
		target.call("take_damage", damage, behind.direction_to(target.global_position))
	_shake(0.42)

func _skill_comet(hero: Node3D, target: Node3D, radius: float, damage: int) -> void:
	if hero == null: return
	var gs  := get_node_or_null("/root/GameState")
	var col := _weapon_color(gs).lerp(Color(0.85, 0.85, 1.0), 0.4)
	var dest := target.global_position if target != null and is_instance_valid(target) \
		else hero.global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	# Rising comet marker
	CombatFx.spawn_ground_telegraph(hero, dest, radius, col, 1.8)
	# Comet descend effect
	var comet_start := dest + Vector3(randf_range(-2, 2), 14.0, randf_range(-2, 2))
	var t := get_tree().create_timer(1.8, false)
	t.timeout.connect(func():
		CombatFx.spawn_burst(hero, dest + Vector3(0, 1.0, 0), col, 36, 10.0, 0.55, 0.24)
		CombatFx.spawn_shockwave(hero, dest, radius * 1.4, col, 0.65)
		_deal_skill_damage(hero, dest, radius, damage)
		_shake(0.65))

func _skill_heavy_aoe(hero: Node3D, radius: float, damage: int) -> void:
	if hero == null: return
	var gs  := get_node_or_null("/root/GameState")
	var col := _weapon_color(gs)
	CombatFx.spawn_ground_telegraph(hero, hero.global_position, radius, col, 0.65)
	var t := get_tree().create_timer(0.65, false)
	t.timeout.connect(func():
		CombatFx.spawn_shockwave(hero, hero.global_position, radius, col, 0.55)
		CombatFx.spawn_burst(hero, hero.global_position + Vector3(0, 0.5, 0), col, 32, 9.0, 0.5, 0.22)
		_deal_skill_damage(hero, hero.global_position, radius, damage)
		_shake(0.60))

func _shake(intensity: float) -> void:
	var id := get_node_or_null("/root/ImpactDirector")
	if id and id.has_method("apply_feedback") and get_tree():
		var hero := _find_hero()
		if hero:
			id.call("apply_feedback", hero, "hit", hero.global_position, Vector3.UP, intensity)
