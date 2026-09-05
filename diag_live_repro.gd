extends SceneTree
## TEMP diagnostic: real-renderer live repro of "hero missing / skills dead".
## Run: godot --path . --script res://diag_live_repro.gd  (DIAG_SCENE env overrides realm)

var _target_scene := "res://scenes/world/moonfen.tscn"
var _menu_mode := false
var _menu_driven := false
var _elapsed := 0.0
var _started := false
var _done := false

func _initialize() -> void:
	var env := OS.get_environment("DIAG_SCENE")
	if not env.is_empty():
		_target_scene = env
	_menu_mode = OS.get_environment("DIAG_MENU") == "1"
	print("DIAG target=", _target_scene, " menu_mode=", _menu_mode)

func _process(delta: float) -> bool:
	if _done:
		return false
	if not _started:
		_started = true
		change_scene_to_file.call_deferred(_target_scene)
		return false
	_elapsed += delta
	if _menu_mode:
		if _elapsed > 1.5 and not _menu_driven:
			_menu_driven = true
			_drive_menu()
			return false
		if _elapsed < 9.0:
			return false
	else:
		if _elapsed < 5.0:
			return false
	_done = true
	_run_diagnostics()
	var img := root.get_texture().get_image()
	if img:
		var out := "/tmp/embervale_repro_%s.png" % _target_scene.get_file().get_basename()
		img.save_png(out)
		print("DIAG screenshot saved: ", out)
	quit(0)
	return false

func _drive_menu() -> void:
	var menu := current_scene.get_node_or_null("MainMenu")
	print("DIAG menu=", menu)
	root.get_node_or_null("/root/SaveLoadManager").call("bind", root.get_node_or_null("/root/GameState"))
	var cont := menu.get_node_or_null("Root/HeroCard/HeroVBox/SecondaryRow/ContinueButton") as Button
	if cont and not cont.disabled:
		print("DIAG pressing ContinueButton")
		cont.pressed.emit()
	else:
		var cta := menu.get_node_or_null("Root/HeroCard/HeroVBox/CTAButton") as Button
		print("DIAG pressing CTAButton (new game)")
		cta.pressed.emit()

func _run_diagnostics() -> void:
	var scene := current_scene
	print("DIAG current_scene=", scene.name if scene else "null")
	var hero := scene.get_node_or_null("Hero") if scene else null
	print("DIAG hero_node=", hero)
	if hero:
		print("DIAG hero_pos=", hero.global_position)
		print("DIAG hero_scale=", hero.scale)
		print("DIAG hero_in_player_group=", hero.is_in_group("player"))
		print("DIAG hero_visible=", hero.visible)
		var visual := hero.get_node_or_null("Visual") as Node3D
		print("DIAG visual=", visual, " visible=", (visual.visible if visual else -1))
		if visual:
			print("DIAG visual_scale=", visual.scale)
			print("DIAG mesh_count=", _count_mesh(visual))
	var cam := scene.get_node_or_null("CameraRig")
	if cam:
		print("DIAG camrig_target=", cam.get("target"))
		print("DIAG camrig_view_mode=", cam.get("view_mode"))
		print("DIAG camrig_pos=", cam.global_position)
		var cam3d := cam.get_node_or_null("Camera3D")
		if cam3d:
			print("DIAG cam3d_global=", cam3d.global_position, " is_current=", cam3d.is_current())
	var active_cam := root.get_camera_3d() as Camera3D
	print("DIAG active_camera3d=", active_cam)
	if active_cam:
		print("DIAG active_cam_pos=", active_cam.global_position)
	if hero:
		print("DIAG hero_collision_layer=", hero.collision_layer)
		var world3d := hero.get_world_3d() as World3D
		if world3d:
			var q := PhysicsRayQueryParameters3D.create(hero.global_position + Vector3(0, 60, 0), hero.global_position + Vector3(0, -80, 0))
			q.collide_with_areas = false
			q.exclude = [hero.get_rid()]
			var hit: Dictionary = world3d.direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				print("DIAG terrain_under_hero_y=", (hit["position"] as Vector3).y, " collider=", hit.collider)
				print("DIAG hero_buried_amt=", hero.global_position.y - (hit["position"] as Vector3).y)
			else:
				print("DIAG no terrain under hero (ray ended below -80)")
	var gs := root.get_node_or_null("/root/GameState")
	print("DIAG autoload GameState=", gs)
	if gs:
		gs.skill_cooldown_changed.emit(0, 2.0)
	var sc := load("res://scripts/entities/boss_mistfen_siltcrawler.gd")
	print("DIAG siltcrawler_script_loaded=", sc)
	var se := root.get_node_or_null("/root/SkillExecutor")
	print("DIAG SkillExecutor=", se)
	if se:
		se.call("execute_skill", 1, {"type": "heal_bloom", "heal": 5,
			"name": "diagnostic", "cooldown": 1.0, "dmg_mult": 1.0, "radius": 2.0})

func _count_mesh(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for child in n.get_children():
		c += _count_mesh(child)
	return c