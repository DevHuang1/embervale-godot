extends SceneTree

## P0 feasibility: the first blueprint and the first forge must be reachable in
## Whispergrove with one pass of its authored nodes and activities, and the
## onboarding route must teach the lens before it teaches the forge.

const LAYOUT := preload("res://scripts/world/realm_layout_data.gd")
const ACTIVITIES := preload("res://scripts/world/realm_activity_catalog.gd")
const FORGE_CATALOG := preload("res://scripts/systems/forge_catalog.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.save_path = "/tmp/embervale_forge_early_route.cfg"
	gs.delete_save()
	gs.reset()

	var profile: Dictionary = LAYOUT.PROFILES.get("whispergrove", {})
	var node_yield := {}
	for entry in profile.get("resources", []):
		var node_id := str(entry.get("id", ""))
		node_yield[node_id] = maxi(int(node_yield.get(node_id, 0)), int(entry.get("yield", 0)))
	var activity_yield := {}
	for entry in ACTIVITIES.ACTIVITIES.get("whispergrove", []):
		var reward: Dictionary = entry.get("reward", {})
		if str(reward.get("type", "")) != "material":
			continue
		var material_id := str(reward.get("id", ""))
		activity_yield[material_id] = int(activity_yield.get(material_id, 0)) \
			+ int(reward.get("quantity", 0))

	var cost: Dictionary = FORGE_CATALOG.tier_cost(0)
	for material_id in cost:
		var needed := int(cost[material_id])
		var available := int(node_yield.get(material_id, 0)) + int(activity_yield.get(material_id, 0))
		if available < needed:
			failures += 1
			print("FAIL: %s needs %d but Whispergrove offers %d in one pass"
				% [material_id, needed, available])

	var whisper_enemies: Array = profile.get("enemies", [])
	var whisper_families := {}
	for enemy_id in whisper_enemies:
		var family := FORGE_CATALOG.family_for_kind(str(enemy_id))
		if not family.is_empty():
			whisper_families[family] = true
	var first_blueprint := ""
	for blueprint_id in FORGE_CATALOG.blueprint_ids():
		var unlock: Dictionary = FORGE_CATALOG.blueprint(blueprint_id).get("unlock", {})
		if unlock.has("family") and whisper_families.has(str(unlock.get("family", ""))) \
				and int(unlock.get("count", 99)) <= 2:
			first_blueprint = str(blueprint_id)
			break
	if first_blueprint.is_empty():
		failures += 1
		print("FAIL: no blueprint is unlockable from Whispergrove foes")

	var triggers: Array = []
	for step in GAME_STATE_SCRIPT.ONBOARDING_STEPS:
		triggers.append(str(step.get("trigger", "")))
	var analyze_at := triggers.find("analyze")
	var craft_at := triggers.find("craft")
	if analyze_at < 0 or craft_at < 0 or analyze_at > craft_at:
		failures += 1
		print("FAIL: onboarding does not teach the lens before the forge -> ", triggers)

	if not first_blueprint.is_empty():
		gs.register_analysis("hushling")
		gs.register_analysis("hushling")
		if not gs.is_blueprint_unlocked(first_blueprint):
			failures += 1
			print("FAIL: two Whispergrove analyses did not unlock ", first_blueprint)
		for material_id in cost:
			gs.add_material(str(material_id), int(cost[material_id]))
		var forged: Dictionary = gs.forge_blueprint(first_blueprint, 0, "FIRST FORGE",
			["FIRST RITE", "SECOND RITE", "THIRD RITE"])
		if not bool(forged.get("success", false)):
			failures += 1
			print("FAIL: first forge failed -> ", forged.get("message", ""))
		elif not bool(gs.equipped_weapon.get("relic", false)):
			failures += 1
			print("FAIL: first forge did not equip its relic")
		for material_id in cost:
			if gs.get_material_qty(str(material_id)) != 0:
				failures += 1
				print("FAIL: first forge left material behind -> ", material_id)

	gs.delete_save()
	if failures == 0:
		print("ALL EARLY FORGE ROUTE TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
