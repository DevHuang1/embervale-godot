extends SceneTree

## Real-renderer visual capture matrix.
## Captures (realm, tier, focus) stills with a REAL renderer (run WITHOUT
## --headless; recommended --rendering-method mobile to match the Android
## target). Redirects GameState save + QualityScaler settings to /tmp so the
## player's real save/settings are never touched.
##
## Single combo:
##   godot --path . --rendering-method mobile --script tests/capture_render_matrix.gd \
##     -- --realm moonfen --tier medium --focus boss --out /tmp/caps/moonfen_boss_medium.png
##
## Full realm matrix (7 focuses x 3 tiers in ONE window per realm):
##   godot --path . --rendering-method mobile --script tests/capture_render_matrix.gd \
##     -- --realm bramblewood --all --out /tmp/caps/
##   writes /tmp/caps/bramblewood_scene_low.png ... /tmp/caps/bramblewood_crowd_high.png
##
## tiers:  low | medium | high          (--tier ignored when --all)
## focus:  scene | light | heavy | elemental | boss | telegraph | crowd
## --boss-id <canonical_id> optionally replaces the realm's legacy boss with
## the V2 articulated roster scene; --skill-id triggers one existing skill.
## --all loops every focus x every tier, reloading the realm scene per combo
## so each still is deterministic and cleans up after itself.

var _realm := "bramblewood"
var _tier := "medium"
var _focus := "scene"
var _out := "/tmp/embervale_capture.png"
var _all := false
var _keep_ui := false
var _expansion := false
var _boss_id := ""
var _skill_id := ""
var _boss_frozen := false
var _orbit := 1
var _failed := 0

var GS: Node = null
var _input: Node = null
var _current_tier_level := 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--realm":
				_realm = args[i + 1]
				i += 2
			"--tier":
				_tier = args[i + 1]
				i += 2
			"--focus":
				_focus = args[i + 1]
				i += 2
			"--out":
				_out = args[i + 1]
				i += 2
			"--all":
				_all = true
				i += 1
			"--keep-ui":
				_keep_ui = true
				i += 1
			"--expansion":
				_expansion = true
				i += 1
			"--boss-id":
				_boss_id = args[i + 1]
				i += 2
			"--skill-id":
				_skill_id = args[i + 1]
				i += 2
			"--boss-frozen":
				_boss_frozen = true
				i += 1
			"--orbit":
				_orbit = maxi(1, int(args[i + 1]))
				i += 2
			_:
				i += 1
	_set_tier_level(_tier)
	_run.call_deferred()


func _set_tier_level(tier: String) -> void:
	match tier:
		"low":
			_current_tier_level = 0
		"high":
			_current_tier_level = 2
		_:
			_current_tier_level = 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Hide HUD / panels so composition evidence is not cluttered.
func _hide_ui() -> void:
	if current_scene == null:
		return
	for layer in current_scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false


## Force a deterministic quality tier on the shared QualityScaler singleton.
## Calling _apply_level directly (bypassing set_mode) keeps settings.will_pom
## clean: nothing persists. `mode` is pinned away from AUTO so the FPS
## hysteresis never re-degrades mid-capture.
func _force_tier() -> void:
	var qs := root.get_node_or_null("/root/WorldState/QualityScaler")
	if qs == null:
		return
	qs.set("settings_path", "/private/tmp/embervale_capture_qs.cfg")
	qs.set("mode", 2)
	qs.call("_apply_level", _current_tier_level)
	print("TIER ", _tier, " level=", qs.get("level"),
		" density=", qs.get("vfx_density"),
		" distortion=", qs.get("distortion_enabled"),
		" contact_shadows=", qs.get("contact_shadows"),
		" pom=", qs.get("pom_mode"))


## Add a dedicated camera so capture framing is deterministic across tiers.
func _camera_at(target: Vector3, offset: Vector3, look: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	cam.global_position = target + offset
	cam.look_at(look)
	cam.fov = fov
	cam.make_current()
	for i in 4:
		await process_frame
	if is_instance_valid(cam) and cam.is_inside_tree():
		cam.make_current()


func _snap() -> bool:
	if current_scene == null:
		print("FAIL: no current scene to snapshot")
		return false
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(_out)
	print("SNAP ", _out, " size=", img.get_size(), " err=", err)
	return err == OK


func _hero() -> Node3D:
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("Hero") as Node3D


func _spawn_enemy_near(origin: Vector3, offset: Vector3) -> Node3D:
	var scene: PackedScene = load("res://scenes/entities/hushling.tscn")
	if scene == null:
		return null
	var enemy: Node3D = scene.instantiate()
	current_scene.add_child(enemy)
	enemy.global_position = origin + offset
	if not enemy.is_in_group("enemy"):
		enemy.add_to_group("enemy")
	return enemy


func _load_realm(scene_path: String) -> bool:
	if not ResourceLoader.exists(scene_path):
		print("FAIL: realm scene missing -> ", _realm, " ", scene_path)
		return false
	GS.call("reset")
	GS.set_current_realm(_realm)
	if _expansion and _realm == "bramblewood":
		GS.set("onboarding_completed", true)
	change_scene_to_file(scene_path)
	await _frames(10)
	_force_tier()
	await _frames(150)
	if not _keep_ui:
		_hide_ui()
	return true


func _run() -> void:
	GS = root.get_node("/root/GameState")
	_input = root.get_node("/root/InputManager")
	GS.set("save_path", "/private/tmp/embervale_capture_save.cfg")
	if not _boss_id.is_empty():
		var boss_profile := BossAssetManifest.profile_for(_boss_id)
		if boss_profile.is_empty():
			print("FAIL: unknown canonical boss id ", _boss_id)
			quit(1)
			return
		_realm = str(boss_profile.get("realm", _realm))

	var scene_path := "res://scenes/world/grove.tscn"
	if _realm != "whispergrove":
		scene_path = String(Bestiary.biome_scene(_realm))

	if _all:
		await _run_all(scene_path)
	else:
		GS.call("reset")
		print("REALM ", _realm, " scene=", scene_path, " tier=", _tier, " focus=", _focus)
		if not await _load_realm(scene_path):
			quit(1)
			return
		var ok := await _dispatch_focus(_focus)
		quit(0 if ok else 1)


func _run_all(scene_path: String) -> void:
	var out_dir := _out.trim_suffix("/")
	var tiers := ["low", "medium", "high"]
	var focuses := ["scene", "light", "heavy", "elemental", "boss", "telegraph", "crowd"]
	print("MATRIX realm=", _realm, " scene=", scene_path, " combos=", tiers.size() * focuses.size())
	for tier in tiers:
		_tier = tier
		_set_tier_level(tier)
		for focus in focuses:
			_focus = focus
			_out = out_dir.path_join("%s_%s_%s.png" % [_realm, focus, tier])
			print("COMBO realm=", _realm, " tier=", tier, " focus=", focus)
			if not await _load_realm(scene_path):
				_failed += 1
				continue
			if not await _dispatch_focus(focus):
				_failed += 1
	quit(0 if _failed == 0 else 1)


func _dispatch_focus(focus_name: String) -> bool:
	match focus_name:
		"scene":     return await _focus_scene()
		"crowd":     return await _focus_crowd()
		"light":     return await _focus_light(false)
		"heavy":     return await _focus_light(true)
		"elemental": return await _focus_elemental()
		"boss":      return await _focus_boss(false)
		"telegraph": return await _focus_boss(true)
		_:
			print("FAIL: unknown focus ", focus_name)
			return false


func _focus_scene() -> bool:
	var hero := _hero()
	if hero == null:
		print("FAIL: no hero for scene focus")
		return false
	if _expansion and _realm == "bramblewood":
		var oak := current_scene.find_child("ExpansionPocket_split_road_oak", true, false) as Node3D
		if oak != null:
			hero.global_position = oak.global_position + Vector3(0.0, 0.05, 6.8)
	var base := hero.global_position
	await _camera_at(base, Vector3(1.5, 3.0, 7.5), base + Vector3(0, 0.9, 0), 42.0)
	await _frames(8)
	return _snap()


func _focus_crowd() -> bool:
	var hero := _hero()
	if hero == null:
		print("FAIL: no hero for crowd focus")
		return false
	var base := hero.global_position
	current_scene.call("_spawn_biome_pack", base + Vector3(0, 0, 3))
	await _frames(20)
	current_scene.call("_spawn_biome_pack", base + Vector3(2, 0, -2))
	await _frames(120)
	await _camera_at(base, Vector3(0, 4.2, 10.0), base + Vector3(0, 0.9, 0), 46.0)
	await _frames(6)
	return _snap()


func _focus_light(heavy: bool) -> bool:
	var hero := _hero()
	if hero == null:
		print("FAIL: no hero for light-heavy focus")
		return false
	var base := hero.global_position
	var forward := (-hero.global_transform.basis.z).normalized()
	var enemy := _spawn_enemy_near(base, forward * 1.2 + Vector3(0, 0.1, 0))
	if enemy == null:
		print("FAIL: enemy spawn failed")
		return false
	# Face the enemy like a real engagement, then lock it as the target.
	hero.look_at(enemy.global_position, Vector3.UP)
	hero.rotation.x = 0.0
	if not GS.engage_enemy(enemy):
		print("WARN: engage_enemy refused")
	await _frames(6)
	await _camera_at(base, Vector3(2.6, 1.6, 3.9), base + Vector3(0, 0.95, 0), 36.0)
	_input.attack_pressed.emit()
	if heavy:
		await _frames(int(0.55 * 60))  # hold past HEAVY_HOLD_MSEC
		_input.attack_released.emit()
		await _frames(18)
	else:
		_input.attack_released.emit()  # quick tap -> light combo
		await _frames(12)
	return _snap()


func _focus_elemental() -> bool:
	var hero := _hero()
	if hero == null:
		print("FAIL: no hero for elemental focus")
		return false
	var base := hero.global_position
	var forward := (-hero.global_transform.basis.z).normalized()
	var enemy := _spawn_enemy_near(base, forward * 2.0 + Vector3(0, 0.1, 0))
	if enemy == null:
		print("FAIL: enemy spawn failed")
		return false
	hero.look_at(enemy.global_position, Vector3.UP)
	hero.rotation.x = 0.0
	await _frames(6)
	await _camera_at(enemy.global_position, Vector3(1.8, 1.4, 3.2),
		enemy.global_position + Vector3(0, 0.9, 0), 36.0)
	var status: Node = null
	if enemy.has_node("ElementalStatus"):
		status = enemy.get_node("ElementalStatus")
	for child in enemy.get_children():
		if status == null and child.name.to_lower().contains("elemental"):
			status = child
			break
	if status != null:
		status.call("apply", "fire", 30.0, hero)
	await _frames(20)
	return _snap()


func _focus_boss(telegraph: bool) -> bool:
	var hero := _hero()
	if hero == null:
		print("FAIL: no hero for boss focus")
		return false
	var manager := current_scene
	var expedition := current_scene.get_node_or_null("BramblewoodExpedition")
	var frozen_boss: Node3D = null
	if not _boss_id.is_empty():
		var packed := load("res://scenes/entities/boss_articulated.tscn") as PackedScene
		if packed == null:
			print("FAIL: canonical boss scene failed to load")
			return false
		var authored_boss := packed.instantiate() as ArticulatedBoss
		authored_boss.def_id = _boss_id
		authored_boss.is_practice = true
		current_scene.add_child(authored_boss)
		authored_boss.global_position = hero.global_position + (-hero.global_transform.basis.z) * 4.5
		authored_boss.set_encounter_origin(authored_boss.global_position)
		if _boss_frozen:
			# Boss portrait mode: freeze the encounter AI so the silhouette
			# cannot walk into the lens mid-capture, then frame from the
			# mounted model's measured bounds. The portrait is lifted clear of
			# the realm's instanced foliage (which cannot be hidden per-instance)
			# so every boss is judged against the same clean sky/fog backdrop.
			authored_boss.set_physics_process(false)
			authored_boss.velocity = Vector3.ZERO
			authored_boss.global_position += Vector3(0.0, 18.0, 0.0)
			authored_boss.set_encounter_origin(authored_boss.global_position)
			frozen_boss = authored_boss
	elif _expansion and _realm == "bramblewood" and expedition != null:
		var court := current_scene.find_child("ExpansionPocket_rootbound_court", true, false) as Node3D
		if court != null:
			hero.global_position = court.global_position + Vector3(0.0, 0.05, 2.8)
		expedition.call("_engage_boss")
	else:
		manager.call("_engage_arena_boss")
	await _frames(40)
	if frozen_boss != null:
		return await _snap_frozen_boss(frozen_boss)
	var boss: Node3D = null
	for node in get_nodes_in_group("boss"):
		if node is Node3D:
			boss = node
			break
	if boss == null:
		print("FAIL: boss not engaged")
		return false
	var boss_pos := boss.global_position
	# Boss meshes vary substantially in authored scale; keep the full silhouette
	# and arena readably inside the portrait mobile frame.
	await _camera_at(boss_pos, Vector3(-3.8, 3.6, 15.5),
		boss_pos + Vector3(0, 1.8, 0), 48.0)
	var skill_to_show: Dictionary = {}
	if not _boss_id.is_empty() and not _skill_id.is_empty():
		var boss_def: Dictionary = (boss as ArticulatedBoss)._def
		for skill_value in boss_def.get("skills", []):
			if skill_value is Dictionary and str((skill_value as Dictionary).get("id", "")) == _skill_id:
				skill_to_show = (skill_value as Dictionary).duplicate(true)
				break
		if skill_to_show.is_empty():
			print("FAIL: skill ", _skill_id, " not found on ", _boss_id)
			return false
		boss.call("_perform_skill", skill_to_show, hero)
	if telegraph:
		# Deterministic telegraph on our camera's schedule: pin the action
		# lock so the boss's own AI cannot overwrite it during the frame.
		boss.call("lock_action", 2.0)
		if not _boss_id.is_empty():
			await _frames(12)
		elif _expansion and _realm == "bramblewood":
			boss.call("_perform_special_1", hero)
		else:
			boss.call("_perform_basic_attack", hero)
		await _frames(12)
	else:
		if not _skill_id.is_empty():
			var impact_wait := float(skill_to_show.get("anticipation", 0.6)) + 0.18
			await _frames(maxi(10, int(impact_wait * 60.0)))
		else:
			await _frames(10)
	return _snap()


## Deterministic boss portrait: the frozen encounter is framed from the
## silhouette's own world bounds, so every canonical boss is judged at the
## same relative size instead of at whatever distance its AI happened to pick.
## `--orbit N` walks N evenly spaced yaw angles around the model.
func _snap_frozen_boss(boss: Node3D) -> bool:
	# The world-space enemy health plate is 3D geometry above the boss, and the
	# hero stands between the lens and the silhouette at close orbits.
	var hero := _hero()
	if hero != null:
		# Parked far enough that the hero never occludes a close orbit but is
		# still available as scale context.
		hero.global_position = boss.global_position + Vector3(0.0, 0.0, -30.0)
	var bounds := _visible_bounds(boss)
	_clear_portrait_occluders(boss, maxf(25.0, bounds.size.length() * 2.5))
	var focus := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 1.5)
	var fov := 42.0
	var distance := radius / tan(deg_to_rad(fov * 0.5)) * 1.4
	var base_out := _out.get_basename()
	var angles := maxi(1, _orbit)
	var ok := true
	for index in angles:
		var yaw := TAU * float(index) / float(angles) if angles > 1 else deg_to_rad(35.0)
		var offset := Vector3(sin(yaw), 0.0, cos(yaw)) * distance \
			+ Vector3(0.0, radius * 0.42, 0.0)
		await _camera_at(boss.global_position, offset, focus, fov)
		_out = base_out + (".png" if angles == 1 else "_a%d.png" % index)
		_hide_capture_ui()
		if not _snap():
			ok = false
	print("BOSS PORTRAIT ", base_out, " size=", bounds.size, " radius=%.2f distance=%.2f" % [radius, distance])
	return ok


## Hide every UI layer the portrait would otherwise capture. `_hide_ui` only
## reaches CanvasLayers under the current scene, while the HUD, objective
## prompt, and boss bar are persistent siblings of the scene root.
func _hide_capture_ui() -> void:
	var hidden := 0
	for node in root.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer != null:
			layer.visible = false
			hidden += 1
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control != null:
			control.visible = false
			hidden += 1
	# World-space enemy plates are 3D geometry that re-shows itself every
	# frame, so their processing is stopped before they are hidden.
	for node in root.find_children("*", "Label3D", true, false):
		var label := node as Label3D
		if label != null:
			label.visible = false
			hidden += 1
	for node in root.find_children("EnemyHealthBar", "Node3D", true, false):
		var bar := node as Node3D
		if bar == null:
			continue
		bar.set_process(false)
		bar.set_physics_process(false)
		for child in bar.find_children("*", "VisualInstance3D", true, false):
			(child as VisualInstance3D).visible = false
		bar.visible = false
		hidden += 1
	print("HIDDEN_UI ", hidden)


## Hide props that stand between the portrait camera and the model. Terrain and
## foliage survive (they are large or instanced), but realm landmarks, trunks,
## and stumps near the spawn would otherwise hide the very silhouette the
## portrait exists to show.
func _clear_portrait_occluders(boss: Node3D, radius: float) -> void:
	if current_scene == null:
		return
	const KEEP_TOKENS := ["terrain", "ground", "water", "sky", "cloud", "moon", "sun"]
	for node in current_scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree() or boss.is_ancestor_of(mesh):
			continue
		var mesh_name := str(mesh.name).to_lower()
		if KEEP_TOKENS.any(func(token: String) -> bool: return mesh_name.contains(token)):
			continue
		# Terrain is flat and vast; everything else near the spawn is a prop that
		# would hide the silhouette the portrait exists to show.
		if mesh.mesh != null:
			var mesh_size := mesh.mesh.get_aabb().size
			if mesh_size.y < 3.0 and mesh_size.length() > 40.0:
				continue
		if mesh.global_position.distance_to(boss.global_position) <= radius:
			mesh.visible = false
	for node in current_scene.find_children("*", "MultiMeshInstance3D", true, false):
		var grass := node as MultiMeshInstance3D
		if grass == null or not grass.is_visible_in_tree():
			continue
		if grass.global_position.distance_to(boss.global_position) <= radius * 0.6:
			grass.visible = false


## World-space AABB over every visible mesh under `root`, used to frame the
## portrait camera against the actual mounted silhouette.
func _visible_bounds(root_node: Node3D) -> AABB:
	var result := AABB()
	var started := false
	for mesh_value in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
			continue
		var mesh_bounds := mesh_instance.get_aabb()
		for index in 8:
			var point := mesh_instance.global_transform * mesh_bounds.get_endpoint(index)
			if not started:
				result = AABB(point, Vector3.ZERO)
				started = true
			else:
				result = result.expand(point)
	return result
