extends SceneTree

func _init() -> void:
	for profile in ["hushling", "fenling", "boss_matriarch", "hero"]:
		var path := "res://assets/models/%s.fbx" % profile
		if not ResourceLoader.exists(path):
			print(profile, ": MISSING")
			continue
		var ps: PackedScene = load(path)
		if ps == null:
			print(profile, ": LOAD FAILED")
			continue
		var root := ps.instantiate()
		print("== ", profile, " root=", root.name)
		var players := root.find_children("*", "AnimationPlayer", true, false)
		if players.is_empty():
			print("  no AnimationPlayer")
		else:
			var ap: AnimationPlayer = players[0]
			print("  clips: ", ap.get_animation_list())
		var skels := root.find_children("*", "Skeleton3D", true, false)
		print("  bones: ", skels[0].get_bone_count() if not skels.is_empty() else 0)
		root.free()
	quit()