extends SceneTree

func _init() -> void:
	var hero_source := FileAccess.get_file_as_string("res://scripts/entities/hero.gd")
	var fx_source := FileAccess.get_file_as_string("res://scripts/systems/combat_fx.gd")
	var stream_source := FileAccess.get_file_as_string(
		"res://scripts/systems/world_chunk_streamer.gd")
	var telemetry_source := FileAccess.get_file_as_string(
		"res://scripts/systems/android_profile_telemetry.gd")
	var audio_source := FileAccess.get_file_as_string(
		"res://scripts/autoload/audio_manager.gd")
	var required := {
		"Hero owns skill timers": hero_source.contains("func _wait_skill_delay") \
			and hero_source.contains("func cancel_active_skill_effects"),
		"Hero tears down transient FX": hero_source.contains("func _exit_tree") \
			and hero_source.contains("CombatFx.cancel_context_effects(self)"),
		"Combat FX tracks particle owners": fx_source.contains("_particle_owner_ids") \
			and fx_source.contains("func _cleanup_particle_owners"),
		"Mobile chunk work is staged": stream_source.contains(
			"func _process_mobile_terrain_row") \
			and stream_source.contains("mobile_build_phase"),
		"Telemetry keeps frame context": telemetry_source.contains(
			"FRAME_HISTORY_CAP") and telemetry_source.contains("recent_frames"),
		"Mobile combat audio is prewarmed": audio_source.contains(
			"MOBILE_COMBAT_CUES") and audio_source.contains(
			"func _prewarm_mobile_combat_cues"),
		"Mobile skill FX is prewarmed and bounded": fx_source.contains(
			"static func prewarm_mobile") and fx_source.contains(
			"return mini(scaled, 8) if _is_mobile_runtime()"),
		"Mobile skill audio avoids lazy fetch": audio_source.contains(
			"Never start the lazy ZIP") and audio_source.contains(
			"if _is_mobile_runtime():\n\t\t\treturn"),
		"Mobile skills use bounded impact timing": hero_source.contains(
			"func _wait_for_skill_impact") and hero_source.contains(
			"SKILL_WINDUP.get(\"strike\", 0.10)") and hero_source.contains(
			"SKILL_WINDUP.get(\"dash_strike\", 0.10)"),
	}
	for label in required:
		if not bool(required[label]):
			push_error("Missing performance contract: %s" % label)
			quit(1)
			return
	print("SKILL PERFORMANCE CONTRACT PASSED")
	quit(0)
