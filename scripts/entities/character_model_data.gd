class_name CharacterModelData
extends Resource

## === Character Model Data ===
## Data-driven enemy/character variants. Swap a resource to spawn an
## elder, elite or tinted variant without duplicating scenes or code.

@export var display_name: String = "Hushling"
@export var model_scale: float = 1.0

# Shader tinting (entity_body.gdshader params; null leaves material as-is)
@export var body_tint: Color = Color(0, 0, 0, 0)  # alpha 0 = no override
@export var eye_glow_color: Color = Color(0, 0, 0, 0)
@export var rim_color: Color = Color(0, 0, 0, 0)

# Stats (applied via entity setters when present)
@export var max_hp_override: int = 0   # 0 = keep scene default
@export var base_atk_bonus: int = 0
@export var move_speed_mult: float = 1.0

# Animator tuning
@export var hop_height: float = 0.16
@export var stride_amplitude: float = 0.8
@export var walk_frequency: float = 8.0
@export var lod_distance: float = 30.0


static func elder_hushling() -> CharacterModelData:
	var d := CharacterModelData.new()
	d.display_name = "Elder Hushling"
	d.model_scale = 1.32
	d.body_tint = Color(0.13, 0.20, 0.12)
	d.eye_glow_color = Color(1.0, 0.42, 0.16)
	d.max_hp_override = 55
	d.base_atk_bonus = 2
	d.move_speed_mult = 0.9
	d.hop_height = 0.22
	return d


func configure_entity(entity: Node3D) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	
	entity.scale *= model_scale
	
	# Retint shader materials under the visual tree
	if body_tint.a > 0.0 or rim_color.a > 0.0:
		for mi in entity.find_children("*", "MeshInstance3D", true, false):
			var mat: Material = mi.material_override
			if mat is ShaderMaterial and mat.shader != null \
					and mat.shader.resource_path.ends_with("entity_body.gdshader"):
				mat = mat.duplicate()
				mi.material_override = mat
				if body_tint.a > 0.0:
					mat.set_shader_parameter("base_color", body_tint)
				if rim_color.a > 0.0:
					mat.set_shader_parameter("rim_color", rim_color)
		if eye_glow_color.a > 0.0:
			for mi in entity.find_children("*", "MeshInstance3D", true, false):
				var mat2: Material = mi.material_override
				if mat2 is ShaderMaterial:
					mat2.set_shader_parameter("emission_color", eye_glow_color)
					mat2.set_shader_parameter("emission_energy", 1.2)
	
	# Stats
	if max_hp_override > 0 and entity.has_method("set_max_hp"):
		entity.call("set_max_hp", max_hp_override)
	if base_atk_bonus != 0 and "base_atk" in entity:
		entity.base_atk += base_atk_bonus
	if move_speed_mult != 1.0 and "move_speed" in entity:
		entity.move_speed *= move_speed_mult
	
	# Animator tuning
	var animator := entity.get_node_or_null("Animator")
	if animator and animator.has_method("apply_model_data"):
		animator.apply_model_data(self)