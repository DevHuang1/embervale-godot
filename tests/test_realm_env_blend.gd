extends SceneTree

func _init() -> void:
	var manager_script := preload("res://scripts/systems/realm_manager.gd")
	var manager: Node = manager_script.new()
	var env := Environment.new()
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	var from_p: Dictionary = manager_script.REALM_ENVS["bramblewood"]
	var to_p: Dictionary = manager_script.REALM_ENVS["mistfen"]
	manager.call("_apply_env_blend", 0.5, env, from_p, to_p)
	var midpoint: Color = (from_p["fog_color"] as Color).lerp(to_p["fog_color"] as Color, 0.5)
	if not env.fog_light_color.is_equal_approx(midpoint) \
			or not is_equal_approx(env.fog_density,
				lerpf(float(from_p["fog_density"]), float(to_p["fog_density"]), 0.5)):
		push_error("Realm environment midpoint blend is incorrect")
		quit(1)
		return
	manager.call("_apply_env_blend", 1.0, env, from_p, to_p)
	if not env.fog_light_color.is_equal_approx(to_p["fog_color"]) \
			or not is_equal_approx(env.ambient_light_energy, float(to_p["ambient_energy"])):
		push_error("Realm environment endpoint blend is incorrect")
		quit(1)
		return
	print("ALL REALM ENVIRONMENT BLEND TESTS PASSED")
	manager.free()
	quit()
