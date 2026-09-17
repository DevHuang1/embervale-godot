extends Node

const ROSTER := preload("res://scripts/systems/boss_roster_catalog.gd")
const BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss_articulated.tscn")
const PROJECTILE := preload("res://scripts/entities/boss_projectile.gd")
const DIRECTOR := preload("res://scripts/systems/boss_encounter_director.gd")
const ASSET_MANIFEST := preload("res://scripts/systems/boss_asset_manifest.gd")

var _failures: Array[String] = []

func _ready() -> void:
	for boss_id in ROSTER.CANONICAL_IDS:
		_validate_definition(str(boss_id))
		var boss := BOSS_SCENE.instantiate() as ArticulatedBoss
		_assert_true(boss != null, "%s scene instantiates" % boss_id)
		if boss == null:
			continue
		boss.def_id = str(boss_id)
		boss.is_practice = true
		add_child(boss)
		await get_tree().process_frame
		_assert_true(boss.canonical_id == str(boss_id), "%s canonical id is stable" % boss_id)
		_assert_true(boss.authored_model_mounted,
			"%s mounts its authored V2 model" % boss_id)
		var authored_rig := boss.get_node_or_null("Visual/AuthoredRig") as Node3D
		_assert_true(authored_rig != null,
			"%s keeps the authored rig under the shared Visual mount" % boss_id)
		if authored_rig != null:
			var coverage := CharacterRigLoader.animation_coverage(authored_rig)
			_assert_true(bool(coverage.get("authored_ready", false)),
				"%s authored rig has locomotion clip coverage" % boss_id)
			var textured_surfaces := 0
			var orm_surfaces := 0
			var relief_surfaces := 0
			for mesh_value in authored_rig.find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := mesh_value as MeshInstance3D
				if mesh_instance == null:
					continue
				var material := mesh_instance.get_active_material(0) as BaseMaterial3D
				if material == null:
					continue
				if material.albedo_texture != null:
					textured_surfaces += 1
				if material.roughness_texture != null or material.metallic_texture != null:
					orm_surfaces += 1
				if material.normal_enabled and material.normal_texture != null:
					relief_surfaces += 1
			_assert_true(textured_surfaces > 0,
				"%s uses the shared Boss V2 atlas on imported surfaces" % boss_id)
			_assert_true(orm_surfaces > 0,
				"%s imports ORM-driven surface channels" % boss_id)
			_assert_true(relief_surfaces > 0,
				"%s imports tangent-space normal relief" % boss_id)
			for socket_id in ASSET_MANIFEST.socket_map_for(str(boss_id)):
				_assert_true(boss.find_child(str(socket_id), true, false) != null,
					"%s exposes authored socket %s" % [boss_id, socket_id])
		# The visible (authored) surfaces must own combat feedback: the
		# procedural body is hidden after mount, so flash, tint, and wear
		# have to reach the imported materials instead.
		_assert_true(not boss._authored_surfaces.is_empty(),
			"%s registers authored surfaces as feedback targets" % boss_id)
		if not boss._authored_surfaces.is_empty():
			var flash_surface: StandardMaterial3D = boss._authored_surfaces[0]
			var resting_albedo := flash_surface.albedo_color
			var resting_energy := flash_surface.emission_energy_multiplier
			boss.set_surface_flash(1.0)
			_assert_true(flash_surface.albedo_color != resting_albedo \
					and flash_surface.emission_energy_multiplier > resting_energy,
				"%s authored surfaces carry the hit flash" % boss_id)
			boss.set_surface_flash(0.0)
			_assert_true(flash_surface.albedo_color.is_equal_approx(resting_albedo),
				"%s authored flash resets to the resting surface" % boss_id)
		var bridge := boss.get_meta("anim_bridge", null) as AnimTreeBridge
		_assert_true(bridge != null and bridge.is_active(),
			"%s exposes an active authored animation bridge" % boss_id)
		if bridge != null:
			for skill_value in boss._def.get("skills", []):
				if skill_value is Dictionary:
					var skill_id := str((skill_value as Dictionary).get("id", ""))
					if not skill_id.is_empty():
						_assert_true(bridge.has_cue(skill_id),
							"%s resolves authored skill clip %s" % [boss_id, skill_id])
		_assert_true(boss.get_node_or_null("Visual/ArmL/ForearmL/HandL") != null,
			"%s has articulated left limb chain" % boss_id)
		_assert_true(boss.get_node_or_null("Visual/ArmR/ForearmR/HandR") != null,
			"%s has articulated right limb chain" % boss_id)
		_assert_true(boss.find_children("Muzzle*", "Node3D", true, false).size() >= 2,
			"%s exposes two muzzle points" % boss_id)
		var animator := boss.get_node_or_null("Animator") as ArticulatedBossAnimator
		_assert_true(animator != null, "%s uses the articulated animator" % boss_id)
		if animator != null:
			animator.trigger_skill("sword")
			_assert_true(animator.anim_state == EntityAnimator.AnimState.ATTACK,
				"%s enters an attack animation state" % boss_id)
		var target := Node3D.new()
		add_child(target)
		target.global_position = Vector3(0.0, 0.0, -4.0)
		var event_counts := {"started": 0, "impact": 0, "finished": 0}
		boss.skill_started.connect(func(_skill_id: String) -> void: event_counts.started += 1)
		boss.skill_impact.connect(func(_skill_id: String) -> void: event_counts.impact += 1)
		boss.skill_finished.connect(func(_skill_id: String) -> void: event_counts.finished += 1)
		var representative_skill: Dictionary = boss._def["skills"][0]
		boss._perform_skill(representative_skill, target)
		var representative_timing := boss._skill_timing(representative_skill)
		await get_tree().create_timer(float(representative_timing.get("total_lock", 1.2)) + 0.15).timeout
		_assert_true(event_counts.started == 1 and event_counts.impact == 1 \
				and event_counts.finished == 1,
			"%s skill emits one start, impact, and finish event" % boss_id)
		target.queue_free()
		if boss_id == "moonfen_lunar_leviathan":
			boss.current_phase = BossBase.BossPhase.ENRAGE
			boss._on_phase_transition()
			_assert_true(boss.current_form == 4,
				"four-form boss advances to its final form")
		boss.reset_encounter()
		_assert_true(not boss.is_defeated and boss.hp == boss.max_hp,
			"%s reset restores the live encounter" % boss_id)
		if boss_id == "moonfen_lunar_leviathan":
			_assert_true(boss.current_form == 1 and boss.get_node("Visual").scale \
				.is_equal_approx(Vector3.ONE * 1.24),
				"form reset restores the base silhouette scale")
		boss.queue_free()
		await get_tree().process_frame

	await _validate_directed_roster()
	var encounter_host := Node3D.new()
	add_child(encounter_host)
	var director := DIRECTOR.new()
	director.setup(encounter_host)
	var directed_boss := director.spawn_boss("moonfen_tide_oracle", true,
		Vector3(7.0, 1.5, -3.0))
	_assert_true(directed_boss != null and directed_boss.global_position \
			.is_equal_approx(Vector3(7.0, 1.5, -3.0)),
		"encounter director places the active boss at its arena origin")
	if directed_boss != null:
		directed_boss.global_position = Vector3(14.0, 1.5, -3.0)
		director.reset_active_boss()
		_assert_true(directed_boss.global_position.is_equal_approx(
			Vector3(7.0, 1.5, -3.0)),
			"encounter director reset returns the boss to its origin")
		directed_boss.queue_free()
	await get_tree().process_frame
	encounter_host.queue_free()
	await get_tree().process_frame

	await _validate_projectile_cap()
	var alias_checks := [
		["matriarch", "whispergrove_root_harrow"],
		["biome_rootbound_warden", "bramblewood_thorn_regent"],
		["moonfen_oracle", "moonfen_tide_oracle"],
	]
	for pair in alias_checks:
		_assert_true(ROSTER.canonical_id_for(str(pair[0])) == str(pair[1]),
			"legacy alias %s maps to %s" % [pair[0], pair[1]])
	_assert_true(ROSTER.canonical_key_for("res://scripts/entities/boss_hushling_matriarch.gd") \
		== "boss_whispergrove_root_harrow",
		"legacy script kill key maps to Root Harrow")
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.save_path = "/tmp/embervale_articulated_boss_alias_test.cfg"
		game_state.delete_save()
		game_state.reset()
		_assert_true(game_state.mark_boss_killed(
			"res://scripts/entities/boss_hushling_matriarch.gd"),
			"legacy Root Harrow kill can be recorded")
		_assert_true(not game_state.mark_boss_killed("boss_whispergrove_root_harrow"),
			"legacy Root Harrow kill blocks a duplicate canonical first reward")
		_assert_true(game_state.has_boss_killed("matriarch"),
			"legacy Matriarch lookup sees the migrated kill")
		game_state.delete_save()
	_finish()

func _validate_directed_roster() -> void:
	for boss_value in ROSTER.CANONICAL_IDS:
		var boss_id := str(boss_value)
		var host := Node3D.new()
		host.name = "DirectedHost_%s" % boss_id
		add_child(host)
		var director: BossEncounterDirector = DIRECTOR.new()
		director.setup(host)
		var spawn_position := Vector3(6.0, 1.5, -4.0)
		var directed := director.spawn_boss(boss_id, true, spawn_position)
		await get_tree().process_frame
		_assert_true(directed != null, "%s spawns through the encounter director" % boss_id)
		if directed != null:
			var articulated := directed as ArticulatedBoss
			var definition := ROSTER.definition_for(boss_id)
			_assert_true(articulated != null and articulated.canonical_id == boss_id,
				"%s keeps its requested canonical identity through director spawn" % boss_id)
			_assert_true(articulated != null and articulated.max_hp == int(definition.get("hp", 0)),
				"%s receives its roster health through director spawn" % boss_id)
			_assert_true(articulated != null and articulated.authored_model_mounted,
				"%s mounts its authored model through director spawn" % boss_id)
			directed.queue_free()
		host.queue_free()
		await get_tree().process_frame

func _validate_definition(boss_id: String) -> void:
	var definition := ROSTER.definition_for(boss_id)
	for field in ["movement_mode", "attack_style", "attack_range", "chase_player",
			"can_fly", "can_roll", "form_count", "armor_profile", "projectile_pattern",
			"flash_level", "skill_definitions"]:
		_assert_true(definition.has(field), "%s definition has %s" % [boss_id, field])
	_assert_true(int(definition.get("form_count", 0)) >= 1,
		"%s has at least one form" % boss_id)
	_assert_true(definition.get("skills", []) is Array \
			and not (definition.get("skills", []) as Array).is_empty(),
		"%s has skill data" % boss_id)
	var visual_families: Dictionary = {}
	for skill_value in definition.get("skills", []):
		if skill_value is Dictionary:
			var skill := skill_value as Dictionary
			var family := str(skill.get("vfx_family", ""))
			_assert_true(not str(skill.get("vfx_family", "")).is_empty(),
				"%s skill %s declares a visual family" % [boss_id, skill.get("id", "")])
			_assert_true(family in ASSET_MANIFEST.VFX_FAMILIES,
				"%s skill %s uses a registered visual family" % [boss_id, skill.get("id", "")])
			_assert_true(not visual_families.has(family),
				"%s skill %s has a distinct VFX grammar" % [boss_id, skill.get("id", "")])
			visual_families[family] = true

func _validate_projectile_cap() -> void:
	var host := Node3D.new()
	add_child(host)
	var boss := Node3D.new()
	host.add_child(boss)
	await get_tree().process_frame
	var spawned := 0
	for index in PROJECTILE.MAX_ACTIVE + 2:
		var projectile := BossProjectile.spawn(host, boss, Vector3.ZERO,
			Vector3.FORWARD * 4.0, 2, Color(0.3, 0.8, 1.0), "frost", 4.0, 3.0,
			"validation")
		if projectile != null:
			spawned += 1
	_assert_true(spawned == PROJECTILE.MAX_ACTIVE,
		"projectile pool enforces the hard active cap")
	for projectile in host.get_tree().get_nodes_in_group(PROJECTILE.PROJECTILE_GROUP):
		projectile.queue_free()
	await get_tree().process_frame
	var expiring := BossProjectile.spawn(host, boss, Vector3.ZERO,
		Vector3.FORWARD * 4.0, 2, Color(0.3, 0.8, 1.0), "frost", 4.0, 0.20,
		"lifetime_validation")
	_assert_true(expiring != null, "projectile can be spawned after cap cleanup")
	await get_tree().create_timer(0.35).timeout
	_assert_true(host.get_tree().get_nodes_in_group(PROJECTILE.PROJECTILE_GROUP).is_empty(),
		"projectile lifetime cleans up the gameplay body")
	host.queue_free()

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures.append(message)
		print("FAILURE: ", message)

func _finish() -> void:
	if _failures.is_empty():
		print("ARTICULATED BOSS ROSTER TESTS PASSED")
		get_tree().quit(0)
	else:
		print("ARTICULATED BOSS ROSTER TESTS FAILED: ", _failures)
		get_tree().quit(1)
