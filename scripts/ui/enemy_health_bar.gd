extends Node3D
class_name EnemyHealthBar

## World-space enemy health plate. It reads hp/max_hp from its parent so it
## works for Hushlings, Fenlings, and BossBase without coupling to one class.
@export var bar_width: float = 1.65
@export var bar_height: float = 0.13
@export var height_offset: float = 2.35
@export var show_name_when_targeted: bool = true

var _background: MeshInstance3D
var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D
var _damage_trail: MeshInstance3D
var _damage_trail_material: StandardMaterial3D
var _trail_tween: Tween
var _poise_fill: MeshInstance3D
var _poise_material: StandardMaterial3D
var _lock_frame: MeshInstance3D
var _lock_material: StandardMaterial3D
var _name_label: Label3D
var _hp_label: Label3D
var _last_ratio := -1.0
var _source: Node
var _base_scale := 1.0
var _lock_was := false
var _manual_values := false
var _manual_hp := 0
var _manual_max_hp := 1
## Optional owner-driven range gate. Bosses retire their plate when the player
## leaves the encounter; ordinary enemies keep the default always-on plate.
var _range_visible := true

func _ready() -> void:
	_source = get_parent()
	if _source == null:
		queue_free()
		return
	_base_scale = 1.25 if int(_source.get("max_hp")) >= 200 else 1.0
	position = Vector3(0.0, height_offset * _base_scale, 0.0)
	scale = Vector3.ONE * _base_scale
	call_deferred("_build_bar")
	call_deferred("_refresh", true)

func _process(_delta: float) -> void:
	if not is_instance_valid(_source):
		queue_free()
		return
	_refresh(false)

## Encounter-scoped plates (bosses) can gate visibility on the player's
## distance without touching the ordinary enemy behaviour.
func set_range_visible(visible_in_range: bool) -> void:
	if _range_visible == visible_in_range:
		return
	_range_visible = visible_in_range
	_refresh(true)

func _build_bar() -> void:
	var plate := Node3D.new()
	plate.name = "HealthPlate"
	add_child(plate)

	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(bar_width, bar_height)
	var back_material := _make_material(Color(0.025, 0.018, 0.02, 0.92))
	back_mesh.material = back_material
	_background = MeshInstance3D.new()
	_background.name = "HealthBackground"
	_background.mesh = back_mesh
	_background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.add_child(_background)

	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(bar_width - 0.06, bar_height - 0.035)
	_fill_material = _make_material(Color(0.20, 0.92, 0.34, 1.0))
	fill_mesh.material = _fill_material
	_fill = MeshInstance3D.new()
	_fill.name = "HealthFill"
	_fill.mesh = fill_mesh
	_fill.position = Vector3(-(bar_width - 0.06) * 0.5, 0.0, -0.006)
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.add_child(_fill)

	var trail_mesh := QuadMesh.new()
	trail_mesh.size = Vector2(bar_width - 0.06, bar_height - 0.035)
	_damage_trail_material = _make_material(Color(1.0, 0.68, 0.16, 0.9))
	trail_mesh.material = _damage_trail_material
	_damage_trail = MeshInstance3D.new()
	_damage_trail.name = "DamageTrail"
	_damage_trail.mesh = trail_mesh
	_damage_trail.position = Vector3(-(bar_width - 0.06) * 0.5, 0.0, -0.004)
	_damage_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_damage_trail.visible = false
	plate.add_child(_damage_trail)

	# Optional amber poise strip. Only enemies that expose get_poise_ratio()
	# receive it, keeping ordinary health plates uncluttered.
	var poise_mesh := QuadMesh.new()
	poise_mesh.size = Vector2(bar_width - 0.12, 0.045)
	_poise_material = _make_material(Color(1.0, 0.68, 0.16, 1.0))
	poise_mesh.material = _poise_material
	_poise_fill = MeshInstance3D.new()
	_poise_fill.name = "PoiseFill"
	_poise_fill.mesh = poise_mesh
	_poise_fill.position = Vector3(-(bar_width - 0.12) * 0.5, -0.105, -0.006)
	_poise_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_poise_fill.visible = false
	plate.add_child(_poise_fill)

	# Lantern sigil: real annular geometry rather than a translucent QuadMesh.
	# Only the ring owns pixels, so compatibility renderers cannot expose a
	# square texture boundary on the marked enemy.
	var lock_mesh := _make_lock_sigil_mesh()
	_lock_material = _make_material(Color(1.0, 0.74, 0.30, 0.0))
	lock_mesh.surface_set_material(0, _lock_material)
	_lock_frame = MeshInstance3D.new()
	_lock_frame.name = "LockFrame"
	_lock_frame.mesh = lock_mesh
	_lock_frame.position = Vector3(-bar_width * 0.5 - 0.26, 0.0, -0.002)
	_lock_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lock_frame.visible = false
	plate.add_child(_lock_frame)

	_name_label = Label3D.new()
	_name_label.name = "EnemyName"
	_name_label.position = Vector3(0.0, 0.18, 0.0)
	_name_label.font_size = 32
	_name_label.modulate = Color(1.0, 0.90, 0.72, 0.96)
	_name_label.outline_size = 6
	_name_label.outline_modulate = Color(0.03, 0.02, 0.02, 0.9)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.text = _clean_name(str(_source.name))
	plate.add_child(_name_label)

	_hp_label = Label3D.new()
	_hp_label.name = "EnemyHP"
	_hp_label.position = Vector3(0.0, -0.18, 0.0)
	_hp_label.font_size = 22
	_hp_label.modulate = Color(1.0, 0.96, 0.90, 0.9)
	_hp_label.outline_size = 4
	_hp_label.outline_modulate = Color(0.03, 0.02, 0.02, 0.9)
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	plate.add_child(_hp_label)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.disable_receive_shadows = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return material

func _make_lock_sigil_mesh() -> ArrayMesh:
	const SEGMENTS := 28
	const INNER_RADIUS := 0.105
	const OUTER_RADIUS := 0.175
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var a0 := TAU * float(i) / float(SEGMENTS)
		var a1 := TAU * float(i + 1) / float(SEGMENTS)
		var inner0 := Vector3(cos(a0) * INNER_RADIUS, sin(a0) * INNER_RADIUS, 0.0)
		var outer0 := Vector3(cos(a0) * OUTER_RADIUS, sin(a0) * OUTER_RADIUS, 0.0)
		var inner1 := Vector3(cos(a1) * INNER_RADIUS, sin(a1) * INNER_RADIUS, 0.0)
		var outer1 := Vector3(cos(a1) * OUTER_RADIUS, sin(a1) * OUTER_RADIUS, 0.0)
		for vertex in [inner0, outer0, outer1, inner0, outer1, inner1]:
			surface.set_normal(Vector3(0.0, 0.0, 1.0))
			surface.add_vertex(vertex)
	return surface.commit() as ArrayMesh

## Immediate damage hook used by enemy and boss damage handlers. The normal
## process refresh remains as a safety net for regeneration and scripted damage.
func set_values(current_hp: int, maximum_hp: int, _current_mana: int = 0,
		_maximum_mana: int = 0) -> void:
	_manual_hp = maxi(0, current_hp)
	_manual_max_hp = maxi(1, maximum_hp)
	_manual_values = _source == null or not ("hp" in _source and "max_hp" in _source)
	if _fill != null:
		_refresh(true)

func notify_damage(_amount: int = 0, resulting_hp: int = -1) -> void:
	if _fill == null or _fill_material == null:
		return
	if _manual_values and resulting_hp >= 0:
		_manual_hp = clampi(resulting_hp, 0, _manual_max_hp)
	if resulting_hp >= 0 and _source != null and int(_source.get("hp")) != resulting_hp:
		return
	_last_ratio = -1.0
	_refresh(true)
	var current_ratio := _current_ratio()
	if _damage_trail != null:
		_damage_trail.visible = current_ratio > 0.001
		_damage_trail.scale = Vector3(maxf(_damage_trail.scale.x, current_ratio), 1.0, 1.0)
		if _trail_tween != null and _trail_tween.is_valid():
			_trail_tween.kill()
		_trail_tween = create_tween()
		_trail_tween.tween_interval(0.10)
		_trail_tween.tween_property(_damage_trail, "scale:x", current_ratio, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var original := _fill_material.albedo_color
	var flash := create_tween()
	_fill_material.albedo_color = Color(1.0, 0.92, 0.62)
	flash.tween_property(_fill_material, "albedo_color", original, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _refresh(force: bool) -> void:
	var max_hp := _manual_max_hp if _manual_values else maxi(1, int(_source.get("max_hp")))
	var hp := _manual_hp if _manual_values else clampi(int(_source.get("hp")), 0, max_hp)
	hp = clampi(hp, 0, max_hp)
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var defeated := bool(_source.get("is_defeated")) or hp <= 0
	if force or not is_equal_approx(ratio, _last_ratio):
		_last_ratio = ratio
		var fill_width := bar_width - 0.06
		# Scale from a fixed left edge so each hit removes exactly the amount
		# represented by hp/max_hp instead of moving both ends of the bar.
		_fill.scale = Vector3(maxf(ratio, 0.001), 1.0, 1.0)
		_fill.position.x = -fill_width * 0.5 + fill_width * ratio * 0.5
		var healthy := Color(0.18, 0.92, 0.34)
		var danger := Color(0.96, 0.16, 0.10)
		_fill_material.albedo_color = danger.lerp(healthy, smoothstep(0.0, 0.72, ratio))
		_hp_label.text = "%d / %d" % [hp, max_hp]
	if _poise_fill != null and _poise_material != null:
		var has_poise := _source.has_method("get_poise_ratio")
		_poise_fill.visible = has_poise and not defeated
		if has_poise:
			var poise_ratio := clampf(float(_source.call("get_poise_ratio")), 0.0, 1.0)
			_poise_fill.scale = Vector3(maxf(poise_ratio, 0.001), 1.0, 1.0)
	visible = not defeated and _range_visible
	var is_locked := false
	if show_name_when_targeted:
		# A detached bar (enemy freed mid-frame) is outside the active scene
		# tree, where an absolute get_node() is an engine error.
		var game_state: Node = null
		if is_inside_tree():
			game_state = get_tree().root.get_node_or_null("GameState")
		var target = game_state.enemy_target if game_state != null else null
		is_locked = target == _source
		_name_label.visible = is_locked or hp < max_hp
	if is_locked and not _lock_was:
		_lock_was = true
		_name_label.modulate = Color(1.0, 0.74, 0.30, 1.0)
		_name_label.text = "◈ %s" % _clean_name(str(_source.name))
	elif not is_locked and _lock_was:
		_lock_was = false
		_name_label.modulate = Color(1.0, 0.90, 0.72, 0.96)
		_name_label.text = _clean_name(str(_source.name))
	_lock_frame.visible = is_locked
	if is_locked and _lock_material:
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
		_lock_material.albedo_color = Color(1.0, 0.74, 0.30,
			0.16 + 0.16 * pulse)

func _current_ratio() -> float:
	if _manual_values:
		return clampf(float(_manual_hp) / float(maxi(1, _manual_max_hp)), 0.0, 1.0)
	if not is_instance_valid(_source):
		return 0.0
	var maximum := maxi(1, int(_source.get("max_hp")))
	return clampf(float(int(_source.get("hp"))) / float(maximum), 0.0, 1.0)

func _clean_name(value: String) -> String:
	var parts := value.split("@", false)
	return parts[parts.size() - 1] if not parts.is_empty() else value
