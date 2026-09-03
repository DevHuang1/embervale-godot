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
		var visual := enemy.get_node_or_null("Visual")
		if visual == null or visual.get_child_count() <= 3:
			failures += 1
			print("FAIL: %s has no distinct silhouette geometry" % enemy_id)
		enemy.queue_free()
		await get_tree().process_frame
	print("REALM ENEMY ROSTER %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	get_tree().quit(failures)
