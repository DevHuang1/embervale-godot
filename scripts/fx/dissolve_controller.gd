extends Node
class_name DissolveController

## === Shader-Driven Entity Dissolve + Death FX ===
##
## Attaches to any entity (Hero, Hushling, BossBase). On trigger_death():
##   1. Swaps all MeshInstance3D materials to the dissolve shader variant
##   2. Animates noise-based dissolve (threshold 0→1) over dissolve_duration
##   3. At 40% dissolve: elemental particle burst (color = element_color)
##   4. At 80% dissolve: secondary scatter burst
##   5. On complete: queues the entity free (or calls death_callback if set)
##
## Shader contract (add dissolve.gdshader to your project):
##   uniform float dissolve_threshold : hint_range(0.0, 1.0) = 0.0;
##   uniform vec4  edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
##   uniform float edge_width  : hint_range(0.0, 0.3) = 0.06;
##   uniform sampler2D noise_tex;
##
## Usage:
##   var dc := DissolveController.new()
##   add_child(dc)
##   dc.setup(element_color, 1.6)
##   dc.trigger_death()

signal dissolve_complete

@export var dissolve_duration : float = 1.6
@export var edge_width        : float = 0.06
@export var use_shader        : bool  = true

var element_color  : Color = Color(1.0, 0.42, 0.12)
var death_callback : Callable = Callable()

var _meshes  : Array[MeshInstance3D] = []
var _originals : Array[Material] = []
var _dissolve_mats : Array[ShaderMaterial] = []
var _active   : bool = false
var _t        : float = 0.0
var _burst1_fired : bool = false
var _burst2_fired : bool = false
var _entity   : Node3D = null

func setup(color: Color = Color(1.0, 0.42, 0.12), duration: float = 1.6) -> void:
	element_color    = color
	dissolve_duration = duration

func _ready() -> void:
	_entity = get_parent() as Node3D
	if _entity == null:
		push_error("DissolveController: parent must be Node3D")

func trigger_death() -> void:
	if _active:
		return
	_active = true
	_t = 0.0
	_burst1_fired = false
	_burst2_fired = false
	_collect_meshes()
	_swap_to_dissolve_materials()

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta / dissolve_duration
	var threshold := clampf(_t, 0.0, 1.0)

	# Drive dissolve threshold on all shader materials
	for mat in _dissolve_mats:
		if is_instance_valid(mat):
			mat.set_shader_parameter("dissolve_threshold", threshold)

	# Elemental burst at 40%
	if not _burst1_fired and threshold >= 0.40:
		_burst1_fired = true
		_emit_burst(element_color, 18, 5.5, 0.40)

	# Scatter burst at 80%
	if not _burst2_fired and threshold >= 0.80:
		_burst2_fired = true
		_emit_burst(Color(element_color.r, element_color.g, element_color.b, 0.55),
			28, 8.0, 0.28)

	if threshold >= 1.0:
		_on_dissolve_complete()

func _collect_meshes() -> void:
	_meshes.clear()
	_originals.clear()
	if _entity == null:
		return
	_collect_recursive(_entity)

func _collect_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_meshes.append(node as MeshInstance3D)
		_originals.append((node as MeshInstance3D).material_override)
	for child in node.get_children():
		_collect_recursive(child)

func _swap_to_dissolve_materials() -> void:
	_dissolve_mats.clear()
	var shader_path := "res://assets/shaders/dissolve.gdshader"
	var shader_res: Shader = null
	if ResourceLoader.exists(shader_path):
		shader_res = load(shader_path)

	for i in _meshes.size():
		var mi := _meshes[i]
		if not is_instance_valid(mi):
			_dissolve_mats.append(null)
			continue

		if use_shader and shader_res != null:
			var dm := ShaderMaterial.new()
			dm.shader = shader_res
			dm.set_shader_parameter("dissolve_threshold", 0.0)
			dm.set_shader_parameter("edge_color", element_color)
			dm.set_shader_parameter("edge_width", edge_width)
			mi.material_override = dm
			_dissolve_mats.append(dm)
		else:
			# Fallback: fade albedo alpha without a shader
			var mat := StandardMaterial3D.new()
			var orig := _originals[i]
			if orig is StandardMaterial3D:
				mat.albedo_color = (orig as StandardMaterial3D).albedo_color
			else:
				mat.albedo_color = element_color
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = element_color
			mi.material_override = mat
			# Animate alpha manually via a dummy ShaderMaterial wrapper
			var tw := mi.create_tween()
			tw.tween_property(mat, "albedo_color:a", 0.0, dissolve_duration) \
				.set_trans(Tween.TRANS_QUAD)
			_dissolve_mats.append(null)  # no per-frame drive needed

func _emit_burst(color: Color, amount: int, speed: float, lifetime: float) -> void:
	if _entity == null or not is_instance_valid(_entity):
		return
	var center := _entity.global_position + Vector3(0, 0.8, 0)
	CombatFx.spawn_burst(_entity, center, color, amount, speed, lifetime, 0.15)

func _on_dissolve_complete() -> void:
	_active = false
	dissolve_complete.emit()
	if death_callback.is_valid():
		death_callback.call()
	elif _entity != null and is_instance_valid(_entity):
		_entity.queue_free()


## ── Convenience factory ──────────────────────────────────────────────────────
## Attach a DissolveController to any entity node and immediately trigger death.
static func dissolve_entity(entity: Node3D, color: Color = Color(1.0, 0.42, 0.12),
		duration: float = 1.6, on_done: Callable = Callable()) -> DissolveController:
	var dc := DissolveController.new()
	dc.death_callback = on_done
	entity.add_child(dc)
	dc.setup(color, duration)
	dc.trigger_death()
	return dc
