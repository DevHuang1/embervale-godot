extends RefCounted
class_name GoldenRouteCatalog

## Executable pacing contract for the first 20–30 minute vertical slice.
## It describes required signals; it does not claim rendered/device acceptance.

const BEATS: Array[Dictionary] = [
	{"id": "grove_arrival", "start_sec": 0, "end_sec": 90, "signal": "lantern_path,welcome_arch,arrival_framing", "required_signals": ["lantern_path", "welcome_arch", "arrival_framing"], "recovery": "grove_arrival"},
	{"id": "living_clue", "start_sec": 90, "end_sec": 240, "signal": "ambient_life,hushling_reveal", "required_signals": ["ambient_life", "hushling_reveal"], "recovery": "grove_arrival"},
	{"id": "first_fight", "start_sec": 240, "end_sec": 420, "signal": "telegraph,hit_reaction,weapon_verb", "required_signals": ["telegraph", "hit_reaction", "weapon_verb"], "recovery": "hushling_cleared"},
	{"id": "gathering_ritual", "start_sec": 420, "end_sec": 600, "signal": "marked_gather_nodes,crafting_explanation", "required_signals": ["marked_gather_nodes", "crafting_explanation"], "recovery": "hushling_cleared"},
	{"id": "first_upgrade", "start_sec": 600, "end_sec": 780, "signal": "forge_comparison,held_weapon_change", "required_signals": ["forge_comparison", "held_weapon_change"], "recovery": "shard_claimed"},
	{"id": "bramblewood_approach", "start_sec": 780, "end_sec": 960, "signal": "landmark,encounter_pocket,danger_music", "required_signals": ["landmark", "encounter_pocket", "danger_music"], "recovery": "shard_claimed"},
	{"id": "elite_lesson", "start_sec": 960, "end_sec": 1200, "signal": "role_composition,bounded_telegraphs,valuable_drop", "required_signals": ["role_composition", "bounded_telegraphs", "valuable_drop"], "recovery": "shard_claimed"},
	{"id": "matriarch_reveal", "start_sec": 1200, "end_sec": 1260, "signal": "skippable_reveal,arena_readability,boss_music", "required_signals": ["skippable_reveal", "arena_readability", "boss_music"], "recovery": "beacon_relit"},
	{"id": "boss_phases", "start_sec": 1260, "end_sec": 1560, "signal": "guard_break,vulnerability,phase_safe_space", "required_signals": ["guard_break", "vulnerability", "phase_safe_space"], "recovery": "beacon_relit"},
	{"id": "unlock_aftermath", "start_sec": 1560, "end_sec": 1800, "signal": "reward_reveal,forge_prompt,moonfen_unlock", "required_signals": ["reward_reveal", "forge_prompt", "moonfen_unlock"], "recovery": "beacon_relit"},
]

static func validate() -> Array[String]:
	var errors: Array[String] = []
	var previous_end := -1
	var ids: Dictionary = {}
	for beat in BEATS:
		var id := str(beat.get("id", ""))
		var start := int(beat.get("start_sec", -1))
		var end := int(beat.get("end_sec", -1))
		if id.is_empty() or ids.has(id):
			errors.append("Duplicate or empty route beat ID: %s" % id)
		ids[id] = true
		if start < 0 or end <= start or start < previous_end:
			errors.append("Invalid route timing for beat: %s" % id)
		if str(beat.get("signal", "")).is_empty() or str(beat.get("recovery", "")).is_empty():
			errors.append("Route beat missing signal/recovery: %s" % id)
		previous_end = end
	if BEATS.size() != 10 or int(BEATS[-1].get("end_sec", 0)) != 1800:
		errors.append("Golden Route must contain ten beats ending at 30 minutes")
	return errors
