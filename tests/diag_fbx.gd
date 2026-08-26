extends SceneTree

## Static probe of assets/models/hero.fbx: root transform, node tree scales,
## and every animation track that touches :scale or root transforms —
## hunting what blows AuthoredRig up to 105x at runtime.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var ps := load("res://assets/models/hero.fbx") as PackedScene
	if ps == null:
		print("FAIL: hero.fbx did not load")
		quit(1)
		return
	var rig := ps.instantiate() as Node3D
	print("ROOT name=%s pos=%s rot_deg=%s scale=%s" % [rig.name, rig.position,
		rig.rotation_degrees, rig.scale])
	for c in rig.find_children("*", "", true, false):
		if c is Node3D:
			var n3 := c as Node3D
			print("  %s (%s) pos=%s scale=%s" % [n3.name, c.get_class(),
				n3.position, n3.scale])
	for ap in rig.find_children("*", "AnimationPlayer", true, false):
		var player := ap as AnimationPlayer
		print("AnimationPlayer '%s' libs:" % player.name)
		for anim_name in player.get_animation_list():
			var anim := player.get_animation(anim_name)
			print("  clip '%s' len=%.2f tracks=%d" % [anim_name,
				anim.length, anim.get_track_count()])
			for t in anim.get_track_count():
				var tp := anim.track_get_path(t)
				if str(tp).contains("scale") or str(tp).contains(":") \
						and not str(tp).contains("Skeleton3D:"):
					print("    track[%d] %s (%s)" % [t, tp,
						anim.track_get_type(t)])
	root.add_child(rig)
	quit(0)
