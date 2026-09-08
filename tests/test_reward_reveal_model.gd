extends SceneTree

func _init() -> void:
	var model := preload("res://scripts/systems/reward_reveal_model.gd")
	var reveal: Dictionary = model.build([
		{"id": "ember_sword", "label": "Ember Sword", "quantity": 1, "rarity": 4},
		{"id": "ember_sword", "label": "Duplicate", "quantity": 2, "rarity": 0},
		{"id": "moss", "label": "Moss", "quantity": 3, "rarity": 1}], "boss")
	var entries: Array = reveal.get("entries", [])
	if entries.size() != 2 or not bool(reveal.get("skippable", false)) \
			or not str(reveal.get("summary", "")).contains("Ember Sword") \
			or float(entries[0].get("reveal_seconds", 0.0)) <= float(entries[1].get("reveal_seconds", 0.0)):
		push_error("Reward reveal model failed duplicate/rarity/summary contract")
		quit(1)
		return
	print("REWARD REVEAL MODEL PASSED")
	quit(0)
