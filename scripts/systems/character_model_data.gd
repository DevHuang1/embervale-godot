extends RefCounted
class_name CharacterModelData

## === CharacterModelData — Enemy Visual / Stat Configurator ===
## Used by world_manager._spawn_pack_enemy() and HushlingMatriarch._summon_hushlings()
## to configure an enemy's appearance and stats after instantiation.
##
## Usage:
##   var md := CharacterModelData.new()
##   md.display_name   = "Ember Warden"
##   md.model_scale    = 1.18
##   md.body_tint      = Color(0.28, 0.08, 0.04, 1.0)
##   md.eye_glow_color = Color(1.0, 0.30, 0.08, 1.0)
##   md.max_hp_override = 68
##   md.configure_entity(enemy_node)
##
## Also provides static helpers:
##   CharacterModelData.elder_hushling() -> CharacterModelData
##   CharacterModelData.for_realm(realm_id, tier) -> CharacterModelData

# Display name (shown in FloatingText on first hit if desired)
var display_name    : String = ""

# Visual overrides
var model_scale     : float  = 1.0
var body_tint       : Color  = Color(0, 0, 0, 0)   # zero alpha = no override
var eye_glow_color  : Color  = Color(0, 0, 0, 0)
var aura_color      : Color  = Color(0, 0, 0, 0)
var emissive_color  : Color  = Color(0, 0, 0, 0)

# Stat overrides (0 = no override, keeps entity's exported value)
var max_hp_override   : int   = 0
var base_atk_bonus    : int   = 0
var move_speed_mult   : float = 1.0

# Archetype (drives configure_archetype call)
var archetype       : String = ""

# ─────────────────────────────────────────────────────────────────────────────
# Configure entity
# ─────────────────────────────────────────────────────────────────────────────

func configure_entity(entity: Node3D) -> void:
	if entity == null or not is_instance_valid(entity):
		return

	# Scale
	var visual := entity.get_node_or_null("Visual")
	if visual != null and is_instance_valid(visual) and model_scale != 1.0:
		visual.scale = Vector3.ONE * model_scale

	# Stats
	if max_hp_override > 0:
		entity.set("max_hp", max_hp_override)
		entity.set("hp",     max_hp_override)
	if base_atk_bonus != 0:
		var cur := int(entity.get("base_atk") if entity.get("base_atk") != null else 3)
		entity.set("base_atk", cur + base_atk_bonus)
	if move_speed_mult != 1.0:
		var cur_spd := float(entity.get("move_speed") if entity.get("move_speed") != null else 2.3)
		entity.set("move_speed", cur_spd * move_speed_mult)

	# Archetype
	if not archetype.is_empty() and entity.has_method("configure_archetype"):
		entity.call("configure_archetype", archetype)

	# Shader tints (entity_body.gdshader params)
	if body_tint.a > 0.01:
		_set_shader_on_meshes(entity, "base_color", body_tint)
	if eye_glow_color.a > 0.01:
		_set_shader_on_meshes(entity, "emission_color", eye_glow_color)
		_set_shader_on_meshes(entity, "rim_color",      eye_glow_color)
	if emissive_color.a > 0.01:
		_set_shader_on_meshes(entity, "emissive_color",  emissive_color)
		_set_shader_on_meshes(entity, "emissive_energy", 1.2)

func _set_shader_on_meshes(entity: Node3D, param: String, value: Variant) -> void:
	for child in entity.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter(param, value)

# ─────────────────────────────────────────────────────────────────────────────
# Static presets
# ─────────────────────────────────────────────────────────────────────────────

static func elder_hushling() -> CharacterModelData:
	var md := CharacterModelData.new()
	md.display_name   = "Elder Hushling"
	md.model_scale    = 1.22
	md.body_tint      = Color(0.20, 0.10, 0.06, 1.0)
	md.eye_glow_color = Color(1.00, 0.22, 0.06, 1.0)
	md.max_hp_override = 68
	md.base_atk_bonus  = 4
	md.move_speed_mult = 1.05
	md.archetype       = "thorn_charger"
	return md

static func for_realm(realm_id: String, tier: String) -> CharacterModelData:
	var variant : Dictionary = Bestiary.variant_for(realm_id, tier)
	if variant.is_empty():
		return CharacterModelData.new()
	var md := CharacterModelData.new()
	md.display_name   = str(variant.get("display", "Enemy"))
	md.model_scale    = float(variant.get("scale", 1.0))
	md.body_tint      = variant.get("tint", Color(0, 0, 0, 0)) as Color
	md.eye_glow_color = variant.get("eye",  Color(0, 0, 0, 0)) as Color
	md.max_hp_override = int(variant.get("hp", 0))
	md.base_atk_bonus  = int(variant.get("atk_bonus", 0))
	md.move_speed_mult = float(variant.get("speed", 1.0))
	md.archetype       = str(variant.get("kind", "hushling"))
	return md
