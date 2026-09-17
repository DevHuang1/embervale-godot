extends SceneTree

func _init() -> void:
	var manifest := preload("res://scripts/systems/boss_asset_manifest.gd")
	var failures := manifest.validate()
	if not failures.is_empty():
		for failure in failures:
			push_error(str(failure))
		quit(1)
		return
	if manifest.BOSS_PROFILES.size() != 8 or manifest.WEAPON_PROFILES.size() != 8:
		push_error("Boss asset manifest does not cover all eight boss and weapon profiles")
		quit(1)
		return
	if manifest.VFX_FAMILIES.size() < 8 or manifest.SFX_FAMILIES.size() < 8:
		push_error("Boss asset manifest is missing VFX or SFX families")
		quit(1)
		return
	print("BOSS ASSET MANIFEST TEST PASSED")
	quit(0)
