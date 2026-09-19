extends Node

const ROSTER := {
	"thorn_charger": {"profile": "thorn_charger", "silhouette": "horns", "hp": 42},
	"mire_stalker": {"profile": "mire_stalker", "silhouette": "fins", "hp": 36},
	"ember_warden": {"profile": "ember_warden", "silhouette": "shield", "hp": 54},
	"spore_weaver": {"profile": "spore_weaver", "silhouette": "crown", "hp": 38},
	"relic_leech": {"profile": "relic_leech", "silhouette": "maw", "hp": 44},
}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	for enemy_id in ROSTER:
		var path := "res://scenes/entities/%s.tscn" % enemy_id
		var packed := load(path) as PackedScene
		if packed == null:
			failures += 1
			print("FAIL: enemy scene does not load: %s" % path)
			continue
		var enemy := packed.instantiate() as RealmArchetypeEnemy
		if enemy == null:
			failures += 1
			print("FAIL: %s does not use RealmArchetypeEnemy" % enemy_id)
			continue
		add_child(enemy)
		await get_tree().process_frame
		var expected := ROSTER[enemy_id] as Dictionary
		if enemy.archetype != str(expected.profile):
			failures += 1
			print("FAIL: %s profile mismatch" % enemy_id)
		if enemy.silhouette_kind != str(expected.silhouette):
			failures += 1
			print("FAIL: %s silhouette mismatch" % enemy_id)
		if enemy.max_hp != int(expected.hp) or enemy.hp != enemy.max_hp:
			failures += 1
			print("FAIL: %s health initialization mismatch" % enemy_id)
		if not AudioManager.SFX_PROFILES.has(enemy.sfx_profile):
			failures += 1
			print("FAIL: %s sfx profile '%s' has no cue set" % [enemy_id, enemy.sfx_profile])
		var animator := enemy.get_node_or_null("Animator")
		if animator == null or animator.get("visual_root") == null \
				or animator.get("torso") == null:
			failures += 1
			print("FAIL: %s animator rig refs unresolved" % enemy_id)
		var visual := enemy.get_node_or_null("Visual")
		if visual == null or visual.get_child_count() <= 3:
			failures += 1
			print("FAIL: %s has no distinct silhouette geometry" % enemy_id)
		enemy.queue_free()
		await get_tree().process_frame
	# === Enemy attack SFX contract ===
	# A swing must make a sound on both paths: vanilla creatures route through
	# play_enemy_attack, profiled creatures through play_profile_cue("attack").
	# Voice count is the observable: each path must spawn players, and vanilla
	# profiles must stay silent so the generic cue set is never doubled.
	if not AudioManager.has_method("play_enemy_attack"):
		failures += 1
		print("FAIL: AudioManager lacks play_enemy_attack")
	else:
		var before := AudioManager.get_child_count()
		AudioManager.play_enemy_attack()
		if AudioManager.get_child_count() <= before:
			failures += 1
			print("FAIL: play_enemy_attack spawned no voice")
		AudioManager.stop_one_shots()
		before = AudioManager.get_child_count()
		AudioManager.play_profile_cue("grave_moss", "attack")
		if AudioManager.get_child_count() <= before:
			failures += 1
			print("FAIL: profiled attack cue spawned no voice")
		AudioManager.stop_one_shots()
		before = AudioManager.get_child_count()
		AudioManager.play_profile_cue("vanilla", "attack")
		if AudioManager.get_child_count() != before:
			failures += 1
			print("FAIL: vanilla profile duplicated the generic attack cue")
	# === Hushling-family animator wiring ===
	# Each of these scenes owns an Animator; its exported rig references must
	# resolve or the creature animates frozen and never reaches the authored
	# cue bridge (attack/hit one-shots included).
	for scene_id in ["hushling", "spitter", "elite_hushling", "moonfen_fenling"]:
		var packed := load("res://scenes/entities/%s.tscn" % scene_id) as PackedScene
		if packed == null:
			failures += 1
			print("FAIL: %s scene does not load" % scene_id)
			continue
		var foe := packed.instantiate() as Node3D
		add_child(foe)
		await get_tree().process_frame
		var animator := foe.get_node_or_null("Animator")
		if animator == null or animator.get("visual_root") == null \
				or animator.get("torso") == null:
			failures += 1
			print("FAIL: %s animator rig refs unresolved" % scene_id)
		if not AudioManager.SFX_PROFILES.has(str(foe.get("sfx_profile"))):
			failures += 1
			print("FAIL: %s sfx profile '%s' has no cue set" \
				% [scene_id, foe.get("sfx_profile")])
		foe.queue_free()
		await get_tree().process_frame
	print("REALM ENEMY ROSTER %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	get_tree().quit(failures)
