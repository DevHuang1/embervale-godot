extends RefCounted
class_name BossSkillVfx

## Data-driven visual layer for the canonical boss skills. CombatFx owns the
## actual pools, quality scaling, culling, and cleanup; this class only chooses
## a readable visual recipe for each skill without touching damage or timing.

const FAMILY_BY_SKILL: Dictionary = {
	"root_sword_combo": "boss_root_blade",
	"seed_burst": "boss_seed_spiral",
	"regent_cleave": "boss_regent_cleave",
	"root_crash": "boss_root_rupture",
	"needle_salvo": "boss_needle_fan",
	"briar_mine": "boss_briar_mine",
	"widow_bloom": "boss_petal_ring",
	"fog_roll": "boss_fog_roll",
	"burrow_burst": "boss_burrow_erupt",
	"furnace_pound": "boss_magma_impact",
	"magma_mortar": "boss_magma_mortar",
	"ash_mortar": "boss_ash_mortar",
	"flare_wall": "boss_flare_wall",
	"bell_regen": "boss_bell_regen",
	"tide_bolt": "boss_tide_bolt",
	"moon_tide_ring": "boss_moon_tide_ring",
	"oracle_split": "boss_oracle_split",
	"lunar_breath": "boss_lunar_breath",
	"crescent_sweep": "boss_crescent_sweep",
	"orbit_barrage": "boss_orbit_barrage",
}

static func family_for(skill: Dictionary) -> String:
	var explicit := str(skill.get("vfx_family", ""))
	if not explicit.is_empty():
		return explicit
	var skill_id := str(skill.get("id", ""))
	if FAMILY_BY_SKILL.has(skill_id):
		return str(FAMILY_BY_SKILL[skill_id])
	return "boss_projectile_trail" if str(skill.get("kind", "")) == "projectile" \
		else "boss_ground_crack"

static func start(context: Node3D, skill: Dictionary, target: Vector3) -> void:
	if context == null or not context.is_inside_tree():
		return
	var radius := maxf(0.5, float(skill.get("radius", 2.6)))
	var anticipation := maxf(0.1, float(skill.get("anticipation", 0.6)))
	var color := _color_for(skill)
	# Enemy danger remains on the protected non-blooming layer, while the
	# identity accents add depth around it without replacing it.
	CombatFx.spawn_ground_telegraph(context, target, radius, color, anticipation)
	var family := family_for(skill)
	var origin := _origin(context, family)
	CombatFx.spawn_charge_glow(context, origin, color, anticipation,
		1.0 + minf(radius * 0.14, 0.8))
	match family:
		"boss_root_blade":
			CombatFx.spawn_motes(context, origin, Color(color.r, color.g, color.b, 0.66), 10, 0.42, anticipation, 0.8)
		"boss_seed_spiral":
			CombatFx.spawn_ring(context, origin, radius * 0.30,
				Color(color.r, color.g, color.b, 0.72), anticipation)
			CombatFx.spawn_motes(context, origin + Vector3.UP * 0.35,
				Color(0.72, 1.0, 0.58, 0.74), 12, radius * 0.24, anticipation, 1.0)
		"boss_regent_cleave":
			CombatFx.spawn_vibrant_trail(context, origin, origin + Vector3.FORWARD * 2.8,
				color, color.lightened(0.35), 4)
		"boss_root_rupture":
			CombatFx.spawn_ring(context, target, radius * 0.42,
				Color(0.56, 1.0, 0.38, 0.74), anticipation)
			CombatFx.spawn_motes(context, target, Color(0.46, 0.92, 0.34, 0.58), 8,
				radius * 0.25, anticipation, 0.3)
		"boss_needle_fan":
			CombatFx.spawn_stretched_burst(context, origin,
				Color(color.r, color.g, color.b, 0.70), 10, 4.2, anticipation)
		"boss_briar_mine":
			CombatFx.spawn_ring(context, target, radius * 0.62,
				Color(color.r, color.g, color.b, 0.62), anticipation)
		"boss_petal_ring":
			CombatFx.spawn_ring(context, origin, radius * 0.56,
				Color(0.72, 1.0, 0.42, 0.66), anticipation)
			CombatFx.spawn_motes(context, origin + Vector3.UP * 0.5,
				Color(0.82, 1.0, 0.54, 0.70), 12, radius * 0.38,
				anticipation + 0.2, 1.1)
		"boss_fog_roll":
			CombatFx.spawn_motes(context, origin, Color(color.r, color.g, color.b, 0.55),
				12, radius * 0.34, anticipation, 0.35)
		"boss_burrow_erupt":
			CombatFx.spawn_ring(context, target, radius * 0.48,
				Color(0.32, 0.82, 0.86, 0.66), anticipation)
			CombatFx.spawn_charge_glow(context, target + Vector3.DOWN * 0.04,
				Color(0.28, 0.74, 0.80, 0.70), anticipation, 1.15)
		"boss_magma_impact":
			CombatFx.spawn_core_flash(context, origin, Color(1.0, 0.82, 0.30, 0.90), 1.2)
		"boss_magma_mortar":
			CombatFx.spawn_ring(context, origin, radius * 0.28,
				Color(1.0, 0.42, 0.08, 0.72), anticipation)
			CombatFx.spawn_stretched_burst(context, origin,
				Color(1.0, 0.70, 0.18, 0.72), 8, 4.8, anticipation)
		"boss_ash_mortar":
			CombatFx.spawn_motes(context, origin + Vector3.UP * 0.7,
				Color(1.0, 0.52, 0.16, 0.64), 10, radius * 0.30,
				anticipation, 0.5)
		"boss_flare_wall":
			CombatFx.spawn_ring(context, target, radius * 0.34,
				Color(1.0, 0.74, 0.20, 0.72), anticipation)
		"boss_bell_regen":
			CombatFx.spawn_ring(context, origin, radius * 0.42,
				Color(1.0, 0.64, 0.20, 0.70), anticipation)
		"boss_tide_bolt":
			CombatFx.spawn_ring(context, origin, radius * 0.24,
				Color(0.34, 0.86, 1.0, 0.76), anticipation)
		"boss_moon_tide_ring":
			CombatFx.spawn_ring(context, origin, radius * 0.45,
				Color(color.r, color.g, color.b, 0.64), anticipation)
			CombatFx.spawn_ring(context, origin + Vector3.UP * 0.22, radius * 0.24,
				Color(0.78, 0.88, 1.0, 0.58), anticipation * 0.8)
		"boss_oracle_split":
			CombatFx.spawn_motes(context, origin, Color(0.76, 0.56, 1.0, 0.68),
				10, radius * 0.34, anticipation, 0.7)
		"boss_lunar_breath":
			CombatFx.spawn_ring(context, origin, radius * 0.48,
				Color(color.r, color.g, color.b, 0.70), anticipation)
		"boss_crescent_sweep":
			CombatFx.spawn_telegraph(context, origin + Vector3.UP * 0.35,
				Color(color.r, color.g, color.b, 0.70), false)
		"boss_orbit_barrage":
			CombatFx.spawn_ring(context, origin + Vector3.UP * 0.45,
				radius * 0.38, Color(0.42, 0.76, 1.0, 0.66), anticipation)

static func impact(context: Node3D, skill: Dictionary, target: Vector3) -> void:
	if context == null or not context.is_inside_tree():
		return
	var color := _color_for(skill)
	var family := family_for(skill)
	var origin := _origin(context, family)
	var radius := maxf(0.5, float(skill.get("radius", 2.6)))
	var destination := target if target.distance_to(origin) > 0.2 \
		else origin + (-context.global_transform.basis.z * radius * 2.0)
	match family:
		"boss_root_blade":
			CombatFx.spawn_arc_trail(context, origin, color)
			CombatFx.spawn_skill_ribbon(context, origin, destination,
				Color(color.r, color.g, color.b, 0.80), 0.55, 0.26)
			CombatFx.spawn_burst(context, destination, color, 14, 5.4, 0.34, 0.16)
		"boss_seed_spiral":
			CombatFx.spawn_skill_ribbon(context, origin + Vector3.UP * 0.18,
				destination + Vector3.UP * 0.55, Color(color.r, color.g, color.b, 0.82),
				0.30, 0.36)
			CombatFx.spawn_ring(context, destination, radius * 0.34,
				Color(0.68, 1.0, 0.46, 0.84), 0.42)
			CombatFx.spawn_motes(context, destination + Vector3.UP * 0.3,
				Color(0.80, 1.0, 0.60, 0.76), 12, radius * 0.34, 0.62, 1.2)
		"boss_regent_cleave":
			CombatFx.spawn_arc_trail(context, origin + Vector3.UP * 0.5, color)
			CombatFx.spawn_vibrant_trail(context, origin, destination,
				color, Color(1.0, 0.92, 0.62, 0.95), 6)
			CombatFx.spawn_shockwave(context, destination, radius, color, 0.42)
		"boss_root_rupture":
			CombatFx.spawn_burst(context, destination, Color(0.42, 0.88, 0.26, 0.86), 18, 4.3, 0.52, 0.15, true)
			CombatFx.spawn_pillar(context, destination + Vector3(-radius * 0.42, 0, 0),
				radius * 0.72, Color(0.36, 0.82, 0.24, 0.62), 0.58, 0.46)
			CombatFx.spawn_pillar(context, destination + Vector3(radius * 0.42, 0, 0),
				radius * 0.92, Color(0.58, 1.0, 0.34, 0.66), 0.58, 0.46)
			CombatFx.spawn_shockwave(context, destination, radius, color, 0.54)
		"boss_needle_fan":
			_fan_ribbons(context, origin, destination, color, radius * 0.18)
			CombatFx.spawn_stretched_burst(context, origin, color, 16, 7.0, 0.28)
			CombatFx.spawn_burst(context, destination, Color(1.0, 0.78, 0.86, 0.82), 12, 5.8, 0.34, 0.10, true)
		"boss_briar_mine":
			CombatFx.spawn_core_flash(context, destination + Vector3.UP * 0.18, color, 1.35)
			CombatFx.spawn_burst(context, destination, color, 18, 4.8, 0.42, 0.15)
			CombatFx.spawn_ring(context, destination, radius, Color(color.r, color.g, color.b, 0.86), 0.48)
		"boss_petal_ring":
			for ring_index in range(3):
				CombatFx.spawn_ring(context, origin + Vector3.UP * (0.16 * ring_index),
					radius * (0.52 + ring_index * 0.18),
					Color(0.68 + ring_index * 0.08, 1.0, 0.38, 0.72),
					0.66 + ring_index * 0.12)
			CombatFx.spawn_motes(context, origin + Vector3.UP * 0.65,
				Color(0.78, 1.0, 0.44, 0.78), 18, radius * 0.54, 1.05, 1.7)
			CombatFx.spawn_core_flash(context, origin + Vector3.UP * 0.8,
				Color(0.90, 1.0, 0.68, 0.90), 1.15)
		"boss_fog_roll":
			CombatFx.spawn_vibrant_trail(context, origin, destination,
				color, Color(0.82, 0.98, 1.0, 0.82), 7)
			CombatFx.spawn_burst(context, destination, color, 16, 4.4, 0.48, 0.16)
			CombatFx.spawn_shockwave(context, destination, radius, color, 0.48)
		"boss_burrow_erupt":
			CombatFx.spawn_burst(context, destination, Color(0.34, 0.86, 0.92, 0.82), 20, 5.2, 0.46, 0.14, true)
			for index in range(3):
				var angle := TAU * float(index) / 3.0
				CombatFx.spawn_pillar(context, destination + Vector3(cos(angle), 0, sin(angle)) * radius * 0.44,
					radius * (0.72 + index * 0.16), Color(0.26, 0.72, 0.82, 0.62), 0.54, 0.52)
			CombatFx.spawn_shockwave(context, destination, radius * 0.82, color, 0.46)
		"boss_magma_impact":
			CombatFx.spawn_core_flash(context, destination + Vector3.UP * 0.3,
				Color(1.0, 0.92, 0.72, 0.96), 1.55)
			CombatFx.spawn_burst(context, destination, color, 24, 6.8, 0.55, 0.18)
			CombatFx.spawn_shockwave(context, destination, radius, color, 0.52)
		"boss_magma_mortar":
			CombatFx.spawn_bolt(context, origin, destination, Color(1.0, 0.42, 0.06, 0.94), 0.24, 0.46)
			CombatFx.spawn_burst(context, destination, Color(1.0, 0.78, 0.18, 0.90), 18, 5.8, 0.42, 0.16, true)
			CombatFx.spawn_core_flash(context, destination + Vector3.UP * 0.25,
				Color(1.0, 0.94, 0.60, 0.90), 1.2)
		"boss_ash_mortar":
			CombatFx.spawn_stretched_burst(context, destination + Vector3.UP * 0.5,
				Color(1.0, 0.54, 0.18, 0.90), 18, 4.0, 0.62)
			CombatFx.spawn_motes(context, destination + Vector3.UP * 0.6,
				Color(1.0, 0.30, 0.08, 0.76), 16, radius * 0.58, 0.86, 0.8)
			CombatFx.spawn_ring(context, destination, radius * 0.86,
				Color(1.0, 0.44, 0.08, 0.74), 0.50)
		"boss_flare_wall":
			_line_pillars(context, origin, destination, radius, color)
			CombatFx.spawn_burst(context, destination, Color(1.0, 0.86, 0.34, 0.90), 16, 4.8, 0.44, 0.14)
		"boss_bell_regen":
			CombatFx.spawn_ring(context, origin, radius, color, 0.74)
			CombatFx.spawn_shockwave(context, origin, radius * 0.72,
				Color(1.0, 0.84, 0.34, 0.74), 0.70)
			CombatFx.spawn_motes(context, origin + Vector3.UP * 0.8,
				Color(1.0, 0.68, 0.20, 0.78), 18, radius * 0.44, 1.1, 1.5)
		"boss_tide_bolt":
			CombatFx.spawn_bolt(context, origin, destination, Color(0.30, 0.90, 1.0, 0.94), 0.28, 0.32)
			CombatFx.spawn_ring(context, destination, radius * 0.32,
				Color(0.52, 0.94, 1.0, 0.80), 0.42)
		"boss_moon_tide_ring":
			CombatFx.spawn_ring(context, destination, radius, color, 0.76)
			CombatFx.spawn_ring(context, destination + Vector3.UP * 0.12, radius * 0.68,
				Color(0.72, 0.86, 1.0, 0.72), 0.86)
			CombatFx.spawn_ring(context, destination + Vector3.UP * 0.24, radius * 0.36,
				Color(0.90, 0.96, 1.0, 0.70), 0.96)
			CombatFx.spawn_motes(context, destination + Vector3.UP * 0.4,
				Color(color.r, color.g, color.b, 0.70), 14, radius * 0.42, 0.72, 1.5)
			CombatFx.spawn_core_flash(context, destination + Vector3.UP * 0.4,
				Color(0.86, 0.96, 1.0, 0.90), 1.1)
		"boss_oracle_split":
			_fan_ribbons(context, origin, destination, Color(0.68, 0.52, 1.0, 0.86), radius * 0.22)
			CombatFx.spawn_core_flash(context, destination + Vector3.UP * 0.35,
				Color(0.90, 0.82, 1.0, 0.92), 1.16)
			CombatFx.spawn_burst(context, destination, Color(0.54, 0.34, 1.0, 0.82), 16, 5.6, 0.44, 0.13, true)
		"boss_lunar_breath":
			CombatFx.spawn_vibrant_trail(context, origin, destination, color,
				Color(1.0, 0.86, 1.0, 0.92), 7)
			CombatFx.spawn_core_flash(context, destination + Vector3.UP * 0.5, color, 1.4)
			CombatFx.spawn_burst(context, destination, color, 20, 5.4, 0.48, 0.16)
		"boss_crescent_sweep":
			CombatFx.spawn_slash(context, destination, Color(1.0, 0.66, 1.0, 0.94))
			CombatFx.spawn_arc_trail(context, origin + Vector3.UP * 0.55, color)
			CombatFx.spawn_shockwave(context, destination, radius * 0.76,
				Color(0.82, 0.44, 1.0, 0.76), 0.42)
		"boss_orbit_barrage":
			_orbit_bursts(context, origin, radius, color)
			CombatFx.spawn_ring(context, origin + Vector3.UP * 0.46, radius * 0.74,
				Color(0.44, 0.76, 1.0, 0.72), 0.66)
			CombatFx.spawn_burst(context, destination, Color(0.70, 0.84, 1.0, 0.84), 18, 5.2, 0.46, 0.14, true)
		_:
			CombatFx.spawn_core_flash(context, destination, color, 1.0)
			CombatFx.spawn_burst(context, destination, color, 12, 4.4, 0.36, 0.14)

static func _fan_ribbons(context: Node, origin: Vector3, destination: Vector3,
		color: Color, spread: float) -> void:
	var direction := origin.direction_to(destination)
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	for index in range(3):
		var offset := side * float(index - 1) * spread
		CombatFx.spawn_skill_ribbon(context, origin, destination + offset,
			Color(color.r, color.g, color.b, 0.78 - absf(float(index - 1)) * 0.10),
			0.22 if index != 1 else 0.34, 0.30)

static func _line_pillars(context: Node, origin: Vector3, destination: Vector3,
		radius: float, color: Color) -> void:
	for index in range(3):
		var point := origin.lerp(destination, 0.34 + float(index) * 0.22)
		CombatFx.spawn_pillar(context, point, 1.7 + float(index) * 0.35,
			Color(color.r, color.g, color.b, 0.58), 0.52, radius * 0.18)

static func _orbit_bursts(context: Node, origin: Vector3, radius: float,
		color: Color) -> void:
	for index in range(4):
		var angle := TAU * float(index) / 4.0
		var point := origin + Vector3(cos(angle), 0.35 + sin(angle * 2.0) * 0.18,
			sin(angle)) * radius * 0.64
		CombatFx.spawn_burst(context, point,
			Color(color.r, color.g, color.b, 0.76), 8, 4.4, 0.42, 0.12, true)
		CombatFx.spawn_core_flash(context, point, Color(0.84, 0.74, 1.0, 0.78), 0.82)

static func _origin(context: Node3D, family: String = "") -> Vector3:
	var socket_name := "SOCKET_VFX_Chest"
	if family in ["boss_root_blade", "boss_regent_cleave", "boss_crescent_sweep"]:
		socket_name = "SOCKET_VFX_Weapon_R"
	elif family in ["boss_seed_spiral", "boss_needle_fan", "boss_magma_mortar",
			"boss_ash_mortar", "boss_tide_bolt", "boss_oracle_split",
			"boss_lunar_breath", "boss_orbit_barrage"]:
		socket_name = "SOCKET_VFX_Muzzle_R"
	var socket := context.find_child(socket_name, true, false) as Node3D
	return socket.global_position if socket != null else context.global_position + Vector3.UP * 1.6

static func _color_for(skill: Dictionary) -> Color:
	var value: Variant = skill.get("color", Color(1.0, 0.45, 0.12, 0.9))
	return value as Color if value is Color else Color(1.0, 0.45, 0.12, 0.9)
