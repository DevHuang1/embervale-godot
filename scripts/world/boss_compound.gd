extends Node3D
class_name BossCompound

## === Boss Compound — the ruin a boss haunts ===
## Replaces the old flat "boss circle" with a large, visually unique compound
## per boss. The boss sleeps inside a focal shrine; stepping into the shrine
## makes it materialise (with a title card), it is leashed to the compound
## boundary, and leaving the compound sends it back into hiding until the next
## approach. Combat timing, damage, hitboxes and rewards are unchanged — this
## node owns only the trigger, presentation, leash and retreat lifecycle.

const ROSTER := preload("res://scripts/systems/boss_roster_catalog.gd")
const COMPOUND_CATALOG := preload("res://scripts/systems/boss_compound_catalog.gd")

signal boss_spawned(boss: Node3D)
signal boss_died(boss_id: String)
signal boss_despawned(boss_id: String)

var boss_id := ""
var realm_id := ""
## Leash and retreat boundary. Large by design: the boss roams this whole area.
var compound_radius := 22.0
## Inner shrine trigger radius — the "specific part" that wakes the boss.
var trigger_radius := 5.5
var rematch_seconds := 30.0

## Optional gate predicate (Callable returning bool). Empty = always allowed.
## Side bosses gate on the primary boss being cleared; the shared grove gates
## the primary boss on the completed quest stage.
var allowed: Callable = Callable()

var director: BossEncounterDirector = null
var host: Node = null

var _active_boss: Node3D = null
var _spawn_pending := false
var _spawn_delay := 0.0
var _down_at := -1.0
var _rearm_at := -1.0
var _title_card: Node3D = null
var _rng := RandomNumberGenerator.new()
var _shrine_core: MeshInstance3D = null
var _shrine_core_mat: StandardMaterial3D = null
var _shrine_light: OmniLight3D = null
var _ambient_light: OmniLight3D = null
var _armed := false
var _armed_t := 0.0
var _theme: Dictionary = {}

func setup(cfg: Dictionary) -> void:
	boss_id = str(cfg.get("boss_id", ""))
	realm_id = str(cfg.get("realm_id", "bramblewood"))
	compound_radius = maxf(float(cfg.get("compound_radius", 22.0)), 14.0)
	trigger_radius = clampf(float(cfg.get("trigger_radius", 5.5)), 3.0, compound_radius * 0.6)
	rematch_seconds = maxf(float(cfg.get("rematch_seconds", 30.0)), 1.0)
	if cfg.get("director", null) is BossEncounterDirector:
		director = cfg["director"] as BossEncounterDirector
	if cfg.get("host", null) is Node:
		host = cfg["host"] as Node
	var allowed_value: Variant = cfg.get("allowed", Callable())
	if allowed_value is Callable:
		allowed = allowed_value as Callable
	_theme = COMPOUND_CATALOG.theme_for(boss_id)
	_rng.seed = boss_id.hash()
	_build_compound()
	_set_armed(false)

func is_boss_active() -> bool:
	return _active_boss != null and is_instance_valid(_active_boss)

func force_spawn() -> Node3D:
	if is_boss_active():
		return _active_boss
	_spawn_pending = false
	_spawn_delay = 0.0
	return _do_spawn()

func reset_encounter() -> void:
	## Player defeat or realm reset: send the boss back into hiding silently.
	_despawn_boss(true)
	_set_armed(_is_allowed())

# ─── Gate / arm state ────────────────────────────────────────────────────────

func _is_allowed() -> bool:
	if allowed.is_valid() and allowed.get_object() != null:
		return bool(allowed.call())
	return true

func _set_armed(armed: bool) -> void:
	_armed = armed
	if _shrine_core_mat != null:
		var tint: Color = _theme_tint()
		_shrine_core_mat.emission = tint if armed else tint.darkened(0.55)
	if _shrine_light != null:
		_shrine_light.light_energy = 1.4 if armed else 0.25

func _theme_tint() -> Color:
	var definition := ROSTER.definition_for(boss_id)
	var palette: Array = definition.get("palette", [])
	if palette.size() >= 2 and palette[1] is Color:
		return palette[1]
	return Color(0.92, 0.42, 0.12)

func _fx_tint() -> Color:
	return _theme_tint()

func _stone_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _theme_tint().darkened(0.66).lerp(Color(0.22, 0.20, 0.19), 0.5)
	mat.roughness = 0.92
	return mat

func _glow_material(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

# ─── Construction ─────────────────────────────────────────────────────────────

func _build_compound() -> void:
	var tint := _theme_tint()
	# Ground decal: the readable extent of the compound.
	var decal := MeshInstance3D.new()
	decal.name = "CompoundDecal"
	var disc := CylinderMesh.new()
	disc.top_radius = compound_radius
	disc.bottom_radius = compound_radius
	disc.height = 0.02
	disc.radial_segments = 40
	disc.rings = 1
	decal.mesh = disc
	var decal_mat := StandardMaterial3D.new()
	decal_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.10)
	decal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	decal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	decal.material_override = decal_mat
	decal.position.y = 0.03
	add_child(decal)

	# Boundary: broken stones mark the edge the boss cannot cross.
	_build_boundary(tint)

	# Focal shrine at the centre.
	var shrine := Node3D.new()
	shrine.name = "Shrine"
	add_child(shrine)
	_build_shrine_kind(shrine)

	var label := Label3D.new()
	label.name = "ShrineLabel"
	label.text = COMPOUND_CATALOG.label_for(boss_id)
	label.font_size = 34
	label.pixel_size = 0.004
	label.outline_size = 8
	label.modulate = Color(tint.r, tint.g, tint.b, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 3.4, 0.0)
	shrine.add_child(label)

	_ambient_light = OmniLight3D.new()
	_ambient_light.light_color = tint
	_ambient_light.light_energy = 0.35
	_ambient_light.omni_range = compound_radius * 0.9
	_ambient_light.position = Vector3(0.0, 2.5, 0.0)
	add_child(_ambient_light)

	# Inner trigger: the shrine's footprint.
	var trigger := Area3D.new()
	trigger.name = "Trigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 1 << 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = trigger_radius
	cyl.height = 4.0
	cs.shape = cyl
	trigger.add_child(cs)
	trigger.position = Vector3(0.0, 2.0, 0.0)
	add_child(trigger)
	trigger.body_entered.connect(_on_trigger_body_entered)

func _build_boundary(tint: Color) -> void:
	var root := Node3D.new()
	root.name = "Boundary"
	add_child(root)
	var stone := _stone_material()
	var count := 10
	for i in count:
		var angle := TAU * float(i) / float(count)
		var pillar := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.3
		mesh.bottom_radius = 0.55
		mesh.height = 1.1 + 0.6 * float(i % 3)
		mesh.radial_segments = 6
		pillar.mesh = mesh
		pillar.material_override = stone
		pillar.position = Vector3(cos(angle) * compound_radius, mesh.height * 0.5,
			sin(angle) * compound_radius)
		pillar.rotation.z = 0.14 if i % 3 == 0 else -0.12
		root.add_child(pillar)
		var tip := MeshInstance3D.new()
		var tip_mat := _glow_material(tint, 0.5)
		var gem := SphereMesh.new()
		gem.radius = 0.16
		gem.height = 0.3
		tip.mesh = gem
		tip.material_override = tip_mat
		tip.position = Vector3(cos(angle) * compound_radius, mesh.height + 0.14,
			sin(angle) * compound_radius)
		root.add_child(tip)

func _add_pillar(parent: Node3D, pos: Vector3, height: float,
		top_r: float, bottom_r: float, mat: Material,
		tilt: float = 0.0) -> MeshInstance3D:
	var pillar := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = 7
	pillar.mesh = mesh
	pillar.material_override = mat
	pillar.position = pos
	pillar.rotation.z = tilt
	parent.add_child(pillar)
	return pillar

func _add_stone(parent: Node3D, pos: Vector3, radius: float, mat: Material,
		rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var stone := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.6
	mesh.radial_segments = 7
	mesh.rings = 4
	stone.mesh = mesh
	stone.material_override = mat
	stone.position = pos
	stone.rotation = rotation
	parent.add_child(stone)
	return stone

func _add_glow(parent: Node3D, pos: Vector3, radius: float,
		color: Color, energy: float = 1.0) -> MeshInstance3D:
	var glow := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	glow.mesh = mesh
	glow.material_override = _glow_material(color, energy)
	glow.position = pos
	parent.add_child(glow)
	return glow

func _build_shrine_kind(shrine: Node3D) -> void:
	var tint := _theme_tint()
	var stone := _stone_material()
	var kind := str(_theme.get("kind", "thorn_court"))
	# Shared stepped pedestal every shrine stands on.
	_build_shrine_pedestal(shrine, stone)
	# The glowing heart of the shrine: the wake trigger's visual anchor.
	_shrine_core = _add_glow(shrine, Vector3(0.0, 1.05, 0.0), 0.42, tint, 0.9)
	_shrine_core_mat = _shrine_core.material_override as StandardMaterial3D
	_shrine_light = OmniLight3D.new()
	_shrine_light.light_color = tint
	_shrine_light.light_energy = 1.4
	_shrine_light.omni_range = trigger_radius * 1.7
	_shrine_light.position = Vector3(0.0, 1.5, 0.0)
	shrine.add_child(_shrine_light)
	match kind:
		"overgrown_shrine":
			for side in [-1.0, 1.0]:
				_add_pillar(shrine, Vector3(1.35 * side, 0.6, -0.7), 1.2, 0.16, 0.34, stone, 0.2 * side)
				_add_stone(shrine, Vector3(2.0 * side, 0.22, 0.5), 0.34, stone)
			for i in 5:
				var a := TAU * float(i) / 5.0
				_add_glow(shrine, Vector3(cos(a) * 1.7, 0.3, sin(a) * 1.7), 0.12, tint, 0.55)
		"thorn_court":
			for i in 6:
				var a := TAU * float(i) / 6.0 + 0.26
				var spire := _add_pillar(shrine, Vector3(cos(a) * 1.9, 1.05, sin(a) * 1.9), 2.1,
					0.05, 0.26, stone)
				spire.rotation = Vector3(0.0, -a, 0.24)
			var crown := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.85
			tor.outer_radius = 1.05
			tor.ring_segments = 20
			crown.mesh = tor
			crown.material_override = _glow_material(tint, 0.6)
			crown.rotation.x = PI * 0.5
			crown.position = Vector3(0.0, 1.75, 0.0)
			shrine.add_child(crown)
		"widow_grove":
			for i in 4:
				var a := TAU * float(i) / 4.0
				var tree := MeshInstance3D.new()
				var trunk := CylinderMesh.new()
				trunk.top_radius = 0.12
				trunk.bottom_radius = 0.24
				trunk.height = 3.4
				trunk.radial_segments = 5
				tree.mesh = trunk
				tree.material_override = stone
				tree.position = Vector3(cos(a) * 2.4, 0.5, sin(a) * 2.4)
				tree.rotation = Vector3(0.62 * cos(a), -a, 0.62 * sin(a))
				shrine.add_child(tree)
			_add_stone(shrine, Vector3(1.3, 0.3, 0.8), 0.4, stone, Vector3(0.3, 0.6, 0.2))
			_add_glow(shrine, Vector3(0.0, 0.9, 0.0), 0.34, tint, 0.85)
		"sunken_maw":
			var rim := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 1.7
			tor.outer_radius = 2.05
			tor.ring_segments = 22
			rim.mesh = tor
			rim.material_override = stone
			rim.rotation.x = PI * 0.5
			rim.position = Vector3(0.0, 0.22, 0.0)
			shrine.add_child(rim)
			var pool := MeshInstance3D.new()
			var pool_mesh := CylinderMesh.new()
			pool_mesh.top_radius = 1.72
			pool_mesh.bottom_radius = 1.72
			pool_mesh.height = 0.06
			pool_mesh.radial_segments = 18
			pool.mesh = pool_mesh
			var water := StandardMaterial3D.new()
			water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water.albedo_color = Color(tint.r, tint.g, tint.b, 0.55)
			water.emission_enabled = true
			water.emission = tint
			water.emission_energy_multiplier = 0.3
			pool.material_override = water
			pool.position = Vector3(0.0, 0.2, 0.0)
			shrine.add_child(pool)
			for i in 3:
				var a := TAU * float(i) / 3.0
				_add_pillar(shrine, Vector3(cos(a) * 3.0, 0.9, sin(a) * 3.0), 1.8, 0.1, 0.5, stone,
					0.1 * cos(a))
		"cinder_foundry":
			for side in [-1.0, 1.0]:
				_add_pillar(shrine, Vector3(1.5 * side, 0.55, 0.0), 1.1, 0.2, 0.4, stone)
			var anvil := MeshInstance3D.new()
			var anvil_mesh := BoxMesh.new()
			anvil_mesh.size = Vector3(0.9, 0.5, 0.9)
			anvil.mesh = anvil_mesh
			anvil.material_override = stone
			anvil.position = Vector3(0.0, 0.4, 0.6)
			shrine.add_child(anvil)
			for i in 6:
				var a := TAU * float(i) / 6.0
				_add_glow(shrine, Vector3(cos(a) * 1.9, 0.18, sin(a) * 1.9), 0.14, tint, 1.1)
		"ash_belltower":
			var bell := MeshInstance3D.new()
			var bell_mesh := CylinderMesh.new()
			bell_mesh.top_radius = 0.28
			bell_mesh.bottom_radius = 0.95
			bell_mesh.height = 1.6
			bell_mesh.radial_segments = 10
			bell.mesh = bell_mesh
			bell.material_override = stone
			bell.position = Vector3(0.0, 0.8, 0.0)
			bell.rotation.x = PI * 0.5
			shrine.add_child(bell)
			var ash := MeshInstance3D.new()
			var ash_mesh := CylinderMesh.new()
			ash_mesh.top_radius = 0.05
			ash_mesh.bottom_radius = 1.1
			ash_mesh.height = 0.5
			ash_mesh.radial_segments = 12
			ash.mesh = ash_mesh
			ash.material_override = stone
			ash.position = Vector3(0.0, 0.25, 1.0)
			shrine.add_child(ash)
			_add_glow(shrine, Vector3(0.0, 1.3, 0.0), 0.3, tint, 0.9)
		"tide_sanctum":
			for i in 4:
				var a := TAU * float(i) / 4.0 + 0.4
				_add_pillar(shrine, Vector3(cos(a) * 2.2, 0.85, sin(a) * 2.2), 1.7, 0.08, 0.32, stone)
			_add_glow(shrine, Vector3(0.0, 1.3, 0.0), 0.5, tint, 0.8)
			for i in 3:
				var a := TAU * float(i) / 3.0 + 1.1
				_add_glow(shrine, Vector3(cos(a) * 1.5, 0.4, sin(a) * 1.5), 0.1, tint, 0.6)
		"lunar_henge":
			for i in 5:
				var a := TAU * float(i) / 5.0
				_add_pillar(shrine, Vector3(cos(a) * 2.5, 1.2, sin(a) * 2.5), 2.4, 0.1, 0.42, stone)
			for i in 3:
				var a := TAU * float(i) / 3.0 + 0.7
				_add_glow(shrine, Vector3(cos(a) * 1.8, 1.9, sin(a) * 1.8), 0.16, tint, 0.85)
		_:  # generic ruin shrine
			for side in [-1.0, 1.0]:
				_add_pillar(shrine, Vector3(1.4 * side, 0.55, 0.0), 1.1, 0.16, 0.36, stone)
			_add_stone(shrine, Vector3(0.0, 0.35, 0.8), 0.4, stone)

func _build_shrine_pedestal(shrine: Node3D, stone: Material) -> void:
	var base := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.25
	mesh.bottom_radius = 1.6
	mesh.height = 0.6
	mesh.radial_segments = 9
	base.mesh = mesh
	base.material_override = stone
	base.position = Vector3(0.0, 0.3, 0.0)
	shrine.add_child(base)

# ─── Trigger ──────────────────────────────────────────────────────────────────

func _on_trigger_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if is_boss_active() or _spawn_pending:
		return
	if _down_at > 0.0 or _rearm_at > 0.0:
		return
	if not _is_allowed():
		return
	# "Randomly appear": a short, seeded surprise delay with a rumble telegraph.
	_spawn_pending = true
	_spawn_delay = _rng.randf_range(0.45, 1.5)
	_set_armed(true)
	_play_spawn_omen()

func _play_spawn_omen() -> void:
	var tint := _theme_tint()
	CombatFx.spawn_motes(self, global_position + Vector3(0.0, 1.4, 0.0),
		Color(tint.r, tint.g, tint.b, 0.7), 14, 1.2, 1.0, 1.8)
	CombatFx.spawn_ring(self, global_position, trigger_radius * 1.4,
		Color(tint.r, tint.g, tint.b, 0.5), 0.8)
	var rig := _host_camera_rig()
	if rig != null:
		rig.add_shake(0.35)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("record_golden_route_signal"):
		scene.call("record_golden_route_signal", "boss_reveal")

# ─── Process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Arm state follows the gate and cooldowns; the shrine dims when it cannot
	# wake, so the player always reads whether an approach is dangerous.
	if not _armed and _is_allowed() and _down_at <= 0.0 and _rearm_at <= 0.0:
		_set_armed(true)
	elif _armed and not _is_allowed():
		_set_armed(false)
	if _rearm_at > 0.0:
		_rearm_at -= delta
		if _rearm_at <= 0.0:
			_rearm_at = -1.0
			_set_armed(true)
	if _down_at > 0.0:
		if Time.get_ticks_msec() / 1000.0 - _down_at > rematch_seconds:
			_down_at = -1.0
			_set_armed(true)
		return

	if _spawn_pending:
		_spawn_delay -= delta
		if _spawn_delay <= 0.0:
			_spawn_pending = false
			_do_spawn()
		return

	# Idle pulse for the shrine core.
	if _shrine_core != null:
		_armed_t += delta
		_shrine_core.scale = Vector3.ONE * (1.0 + 0.12 * sin(_armed_t * 1.6))

	# Retreat: leaving the compound sends the boss back into hiding.
	if is_boss_active():
		var player := _player_node()
		if player != null and not bool(_active_boss.get("is_defeated")):
			var distance := Vector2(player.global_position.x - global_position.x,
				player.global_position.z - global_position.z).length()
			if distance > compound_radius + 3.0:
				_despawn_boss(false)
				return

func _physics_process(_delta: float) -> void:
	# Hard leash: the boss can never cross the compound boundary, whatever its
	# AI decides to do this frame.
	if is_boss_active():
		_enforce_leash()

func _player_node() -> Node3D:
	if host != null:
		var hero: Node3D = host.get("hero") as Node3D
		if hero != null and is_instance_valid(hero):
			return hero
	return get_tree().get_first_node_in_group("player") as Node3D

func _host_camera_rig() -> Node:
	if host == null:
		return null
	return host.get("camera_rig") as Node

func _host_audio() -> Node:
	if host == null:
		return null
	return host.get("audio") as Node

func _host_game_state() -> Node:
	if host == null:
		return null
	return host.get("game_state") as Node

func _enforce_leash() -> void:
	if not is_instance_valid(_active_boss):
		return
	var offset := Vector3(_active_boss.global_position.x - global_position.x, 0.0,
		_active_boss.global_position.z - global_position.z)
	var radius := compound_radius * 0.96
	if offset.length() > radius:
		var clamped := global_position + offset.normalized() * radius
		clamped.y = _active_boss.global_position.y
		_active_boss.global_position = clamped

# ─── Spawn / despawn ──────────────────────────────────────────────────────────

func _do_spawn() -> Node3D:
	if director == null:
		push_warning("BossCompound: no boss director for '%s'" % boss_id)
		return null
	var definition := ROSTER.definition_for(boss_id)
	if definition.is_empty():
		return null
	var player := _player_node()
	var spawn_pos := global_position + Vector3(0.0, 0.1, 0.0)
	# Small seeded surprise offset so the boss never appears on the exact spot.
	if player != null:
		var toward := Vector3(player.global_position.x - global_position.x, 0.0,
			player.global_position.z - global_position.z).normalized()
		if toward.length_squared() < 0.01:
			toward = Vector3.FORWARD
		spawn_pos = global_position + toward * 1.6 + Vector3(0.0, 0.1, 0.0)
	var boss := director.spawn_boss(boss_id, false, spawn_pos)
	if boss == null:
		push_warning("BossCompound: spawn_boss returned null for '%s'" % boss_id)
		return null
	_active_boss = boss
	if boss.has_method("set_leash"):
		boss.call("set_leash", global_position, compound_radius)
	if boss.has_signal("died"):
		boss.died.connect(_on_boss_died)
	_attach_title_card(boss)
	_set_hud_boss_name()
	_play_spawn_reveal(boss)
	boss_spawned.emit(boss)
	return boss

func _play_spawn_reveal(boss: Node3D) -> void:
	var tint := _theme_tint()
	CombatFx.spawn_spawn_portal(self, boss.global_position, tint)
	CombatFx.spawn_motes(self, boss.global_position + Vector3(0.0, 1.8, 0.0),
		Color(tint.r, tint.g, tint.b, 0.85), 22, 2.4, 1.2, 2.2)
	CombatFx.spawn_shockwave(self, boss.global_position - Vector3(0.0, 0.3, 0.0),
		3.0, Color(tint.r, tint.g, tint.b, 0.7), 0.7)
	var rig := _host_camera_rig()
	if rig != null and rig.has_method("play_boss_intro"):
		rig.add_shake(0.6)
		rig.play_boss_intro(boss)
	var audio_node := _host_audio()
	if audio_node != null and audio_node.has_method("play_enemy_telegraph"):
		audio_node.play_enemy_telegraph()
	var game_state_node := _host_game_state()
	if game_state_node != null:
		var definition := ROSTER.definition_for(boss_id)
		game_state_node.quest_progress.emit(
			str(definition.get("intro", "%s answers the ruin." % str(definition.get("name", "The boss")))))

func _on_boss_died() -> void:
	_active_boss = null
	_down_at = Time.get_ticks_msec() / 1000.0
	_set_armed(false)
	boss_died.emit(boss_id)

func _despawn_boss(silent: bool) -> void:
	if is_boss_active():
		var boss := _active_boss
		_active_boss = null
		if boss.has_method("clear_leash"):
			boss.call("clear_leash")
		if not silent:
			var tint := _theme_tint()
			CombatFx.spawn_motes(self, boss.global_position + Vector3(0.0, 1.6, 0.0),
				Color(tint.r, tint.g, tint.b, 0.8), 18, 2.2, 1.0, 1.6)
			CombatFx.spawn_spawn_portal(self, boss.global_position, tint)
		boss.queue_free()
		_hide_hud_boss_bar()
	_rearm_at = 2.0
	_set_armed(false)
	boss_despawned.emit(boss_id)

# ─── Title card ───────────────────────────────────────────────────────────────

func _attach_title_card(boss: Node3D) -> void:
	var definition := ROSTER.definition_for(boss_id)
	if definition.is_empty():
		return
	var card := Node3D.new()
	card.name = "BossTitleCard"
	var name_text := str(definition.get("name", boss_id)).to_upper()
	var title_text := str(definition.get("title", ""))
	var stats_text := "HP %d   ·   ATK %d" % [int(definition.get("hp", 0)),
		int(definition.get("atk", 0))]
	var height := clampf(float(definition.get("body_height", 3.8))
		* float(definition.get("scale", 1.0)) + 2.4, 4.4, 7.5)

	var name_label := _title_label(name_text, 64, Color(1.0, 0.94, 0.82), 10)
	name_label.position = Vector3(0.0, height, 0.0)
	card.add_child(name_label)
	var title_label := _title_label(title_text, 30, Color(1.0, 0.78, 0.55), 6)
	title_label.position = Vector3(0.0, height - 0.5, 0.0)
	card.add_child(title_label)
	var stats_label := _title_label(stats_text, 26, Color(0.88, 0.95, 0.9), 5)
	stats_label.position = Vector3(0.0, height - 0.92, 0.0)
	card.add_child(stats_label)
	boss.add_child(card)
	_title_card = card
	# Fade + settle in so the nameplate reads as an announcement, not a pop.
	name_label.modulate.a = 0.0
	title_label.modulate.a = 0.0
	stats_label.modulate.a = 0.0
	card.scale = Vector3.ONE * 1.3
	var tween := card.create_tween()
	tween.tween_property(name_label, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(title_label, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(stats_label, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(card, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _title_label(text: String, font_size: int, color: Color,
		outline: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.005
	label.modulate = color
	label.outline_size = outline
	label.outline_modulate = Color(0.02, 0.01, 0.01, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	return label

func _set_hud_boss_name() -> void:
	var definition := ROSTER.definition_for(boss_id)
	if definition.is_empty():
		return
	var hud := get_tree().root.find_child("HUD", true, false)
	if hud == null:
		return
	var name_label := hud.get_node_or_null("Root/BossHealthBar/BossName") as Label
	if name_label != null:
		name_label.text = str(definition.get("name", boss_id)).to_upper()

func _hide_hud_boss_bar() -> void:
	var hud := get_tree().root.find_child("HUD", true, false)
	if hud == null:
		return
	var bar := hud.get_node_or_null("Root/BossHealthBar")
	if bar != null:
		bar.visible = false
