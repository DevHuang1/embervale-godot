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
	var summary_entries: Array = model.entries_from_summary({
		"gold": 10,
		"xp": 25,
		"diamonds": 2,
		"materials": [{"id": "moss_fiber", "qty": 3}],
		"items": [{"id": "moss_tonic", "qty": 1, "rarity": 1}],
		"weapons": [{"id": "ember_sword", "rarity": 4}],
		"armors": [{"id": "warden_plate", "rarity": 2}],
	})
	var summary_ids: Dictionary = {}
	for item in summary_entries:
		summary_ids[str(item.get("id", ""))] = true
	if summary_entries.size() != 7 or not summary_ids.has("currency_gold") \
			or not summary_ids.has("currency_xp") or not summary_ids.has("currency_diamonds") \
			or not summary_ids.has("material:moss_fiber") \
			or not summary_ids.has("weapons:ember_sword"):
		push_error("Reward reveal model failed summary conversion contract")
		quit(1)
		return
	print("REWARD REVEAL MODEL PASSED")
	quit(0)
