extends SceneTree

## Deep diagnostic: measure the actual world-space geometry of every mounted
## authored rig (hero + hushling) — merged mesh AABBs, skeleton bounds, and
## socket transforms after bind. Tells us if figures render off-scale,
## underground, or not at all.

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT")
		quit(3))
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _merged_world_aabb(rig: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if first:
			acc = ab
			first = false
		else:
			acc = acc.merge(ab)
	return acc

func _report(entity: Node3D, label: String) -> void:
	print("=== %s ===" % label)
	var rig := entity.get_node_or_null("Visual/Rig/AuthoredRig") as Node3D
	if rig == null:
		rig = entity.get_node_or_null("Visual/AuthoredRig") as Node3D
	if rig == null:
		print("  no authored rig mounted")
		return
	print("  rig scale=%s gpos=%s" % [rig.scale, rig.global_position])
	var ab := _merged_world_aabb(rig)
	print("  merged mesh world AABB pos=%s size=%s" % [ab.position, ab.size])
	for sock_id in ["HandSocketL", "HandSocketR", "BackSocket"]:
		var s := entity.find_child(sock_id, true, false) as Node3D
		if s != null:
			var wscale: Vector3 = s.global_transform.basis.get_scale()
			print("  %s local_scale=%s world_scale=%s" % [sock_id, s.scale,
				wscale])

func _run() -> void:
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	var scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(20)

	var hero := scene.get_node_or_null("Hero") as Node3D
	if hero != null:
		_report(hero, "HERO")
	for e in get_nodes_in_group("enemy"):
		_report(e as Node3D, "ENEMY:%s" % e.name)
		break

	print("DIAG2 DONE")
	gs.delete_save()
	quit(0)
