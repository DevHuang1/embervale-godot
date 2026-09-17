extends Node3D
class_name RealmLifeField

## Bounded, non-gameplay life cluster for authored route beats.  The field uses
## one MultiMesh for all agents and never joins physics, targeting, or combat.

const MAX_AGENTS: int = 8

var realm_id: String = "bramblewood"
var behavior: String = "drift"
var activity_id: String = ""
var presentation_type: String = "world_life"
var _agent_count: int = 0
var _seed: int = 0
var _phase: float = 0.0
var _time: float = 0.0
var _active: bool = true
var _label_visible: bool = false
var _mesh_instance: MultiMeshInstance3D = null
var _multimesh: MultiMesh = null
var _label: Label3D = null
var _light: OmniLight3D = null
var _base_positions: Array[Vector3] = []
var _base_scales: Array[Vector3] = []

func configure(p_realm_id: String, p_seed: int, p_behavior: String,
		p_count: int, p_activity_id: String, p_label: String,
		p_presentation_type: String = "world_life") -> void:
	realm_id = p_realm_id
	_seed = p_seed
	_phase = float(abs(p_seed) % 10000) * 0.0007
	behavior = p_behavior
	activity_id = p_activity_id
	presentation_type = p_presentation_type
	_agent_count = clampi(p_count, 1, MAX_AGENTS)
	_build(p_label)

func _ready() -> void:
	if _mesh_instance == null:
		_build(activity_id.replace("_", " ").to_upper())

func _build(p_label: String) -> void:
	for child in get_children():
		child.queue_free()
	_base_positions.clear()
	_base_scales.clear()

	var mesh := SphereMesh.new()
	mesh.radius = 0.16 if presentation_type != "patrol" else 0.20
	mesh.height = 0.34 if presentation_type != "patrol" else 0.78
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _realm_color()
	material.emission_enabled = true
	material.emission = _realm_color()
	material.emission_energy_multiplier = 0.7
	mesh.material = material

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = mesh
	_multimesh.instance_count = _agent_count
	_multimesh.custom_aabb = AABB(Vector3(-7.0, -1.0, -7.0), Vector3(14.0, 6.0, 14.0))
	for index in _agent_count:
		var angle := TAU * float(index) / float(maxi(_agent_count, 1))
		var radius := 1.4 + float((abs(_seed) + index * 17) % 11) * 0.16
		_base_positions.append(Vector3(cos(angle) * radius,
			0.7 + float(index % 3) * 0.22, sin(angle) * radius))
		var scale := 0.72 + float((abs(_seed) + index * 31) % 7) * 0.08
		var scale_y := scale * (1.32 if presentation_type == "patrol" else 0.82)
		_base_scales.append(Vector3(scale, scale_y, scale))
		_multimesh.set_instance_transform(index,
			Transform3D(Basis.IDENTITY.scaled(_base_scales[index]), _base_positions[index]))

	_mesh_instance = MultiMeshInstance3D.new()
	_mesh_instance.name = "LifeAgents"
	_mesh_instance.multimesh = _multimesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visibility_range_end = 78.0
	_mesh_instance.visibility_range_end_margin = 10.0
	_mesh_instance.set_meta("activity_id", activity_id)
	_mesh_instance.set_meta("agent_count", _agent_count)
	add_child(_mesh_instance)

	_label = Label3D.new()
	_label.name = "LifeLabel"
	_label.text = p_label.to_upper()
	_label.font_size = 20
	_label.pixel_size = 0.004
	_label.outline_size = 6
	_label.no_depth_test = true
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = _realm_color().lightened(0.22)
	_label.position = Vector3(0.0, 2.6, 0.0)
	_label.visible = _label_visible
	add_child(_label)

	# One small light per visible field keeps the event readable without
	# reintroducing the old unbounded ambient-light behavior.
	_light = OmniLight3D.new()
	_light.name = "LifeGlow"
	_light.light_color = _realm_color()
	_light.light_energy = 0.35
	_light.omni_range = 3.8
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.0, 0.0)
	add_child(_light)

func _process(delta: float) -> void:
	if not _active or _multimesh == null:
		return
	_time += delta
	for index in _agent_count:
		_multimesh.set_instance_transform(index,
			Transform3D(Basis.IDENTITY.scaled(_base_scales[index]),
				_agent_position(index)))
	if _light != null:
		_light.light_energy = 0.24 + (sin(_time * 2.4 + _phase) + 1.0) * 0.10

func _agent_position(index: int) -> Vector3:
	var base := _base_positions[index]
	var offset := float(index) * 0.71 + _phase
	match behavior:
		"crossing":
			return Vector3(sin(_time * 0.72 + offset) * 3.4,
				base.y + sin(_time * 1.7 + offset) * 0.22,
				base.z * 0.28 + cos(_time * 0.55 + offset) * 0.7)
		"orbit":
			var angle := _time * 0.48 + offset
			return Vector3(cos(angle) * (2.0 + base.length() * 0.22),
				base.y + sin(_time * 1.1 + offset) * 0.28,
				sin(angle) * (2.0 + base.length() * 0.22))
		"rise":
			return Vector3(base.x + sin(_time * 0.65 + offset) * 0.65,
				0.7 + fmod(_time * (0.18 + float(index % 3) * 0.03) + offset, 2.5),
				base.z + cos(_time * 0.56 + offset) * 0.65)
		"skitter":
			return Vector3(base.x + sin(_time * 1.2 + offset) * 1.5,
				0.35 + abs(sin(_time * 2.0 + offset)) * 0.18,
				base.z + cos(_time * 1.0 + offset) * 1.2)
		_:
			return Vector3(base.x + sin(_time * 0.38 + offset) * 0.8,
				base.y + sin(_time * 0.82 + offset) * 0.24,
				base.z + cos(_time * 0.31 + offset) * 0.8)

func set_active(value: bool) -> void:
	_active = value
	visible = value
	set_process(value)

func set_label_visible(value: bool) -> void:
	_label_visible = value
	if _label != null:
		_label.visible = value and _active

func agent_count() -> int:
	return _agent_count if _active else 0

func _realm_color() -> Color:
	if presentation_type == "patrol":
		return Color(1.0, 0.28, 0.12) if behavior == "skitter" else Color(1.0, 0.56, 0.16)
	match realm_id:
		"whispergrove": return Color(1.0, 0.78, 0.34)
		"mistfen": return Color(0.49, 0.88, 0.76)
		"heartwood": return Color(1.0, 0.42, 0.18)
		"moonfen": return Color(0.52, 0.72, 1.0)
		_: return Color(0.92, 0.67, 0.28)
