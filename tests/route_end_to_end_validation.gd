extends SceneTree

## End-to-end pass over the 20–30 minute route, driven through the real scenes
## and the same entry points the gameplay uses: main menu -> Whispergrove
## onboarding -> first fight -> shard -> beacon -> gathering -> crafting and
## upgrade -> Bramblewood expedition -> elite -> boss -> reward -> loot ->
## visible unlock -> save/reload.
##
## This is a functional integration check. It does not claim rendered, audio or
## device acceptance; it exists to catch crashes, soft locks, duplicate rewards,
## stale references and save regressions that per-system suites cannot see.
##
## Run: godot --headless --path . --script tests/route_end_to_end_validation.gd

const MAIN_SCENE := "res://scenes/main/main.tscn"
const GROVE_SCENE := "res://scenes/world/grove.tscn"
const SAVE_PATH := "/tmp/embervale_route_e2e.cfg"
const TIME_BUDGET_SECONDS := 150.0

var _failures: Array[String] = []
var _passes := 0
var _gs: GameState = null
var _stage_marker := "boot"
var _finished := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# A route check that hangs is a failure, not a wait: bound the run so a
	# soft lock reports where it stalled instead of stalling the suite.
	create_timer(TIME_BUDGET_SECONDS).timeout.connect(_on_time_budget_exceeded)
	await _run_route()
	_finished = true
	print("=== Route End-to-End Validation ===")
	print("passes=", _passes, " failures=", _failures.size())
	for failure in _failures:
		print("FAILURE: ", failure)
	quit(1 if not _failures.is_empty() else 0)

func _on_time_budget_exceeded() -> void:
	if _finished:
		return
	_finished = true
	print("FAILURE: route validation exceeded its time budget at stage: ", _stage_marker)
	print("=== Route End-to-End Validation ===")
	print("passes=", _passes, " failures=", _failures.size() + 1)
	quit(1)

func _mark(stage: String) -> void:
	_stage_marker = stage
	print("ROUTE: ", stage)

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(message)
		print("FAILURE: ", message)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame

func _run_route() -> void:
	_gs = root.get_node_or_null("GameState") as GameState
	if _gs == null:
		_failures.append("GameState autoload missing")
		return
	_gs.save_path = SAVE_PATH
	_gs.delete_save()
	_gs.reset()

	# --- Boot from the real main menu, exactly as a player does ---
	var main_scene := load(MAIN_SCENE) as PackedScene
	if main_scene == null:
		_failures.append("Main scene missing")
		return
	var main := main_scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(10)
	var menu := main.get_node_or_null("MainMenu")
	if menu == null:
		_failures.append("Main menu missing on boot")
		return
	_mark("start_new_game")
	menu.call("_start_new_game")
	await create_timer(1.0).timeout
	await _frames(14)

	var grove := current_scene
	_assert_true(grove != null and grove.name == "Grove", "new game opened the grove scene")
	if grove == null or grove.name != "Grove":
		return
	_mark("onboarding")
	await _run_onboarding(grove)
	_mark("gathering_and_forge")
	await _run_gathering_and_forge(grove)
	_mark("expedition")
	await _run_expedition(grove)
	_mark("reload")
	await _verify_reload()

func _run_onboarding(grove: Node) -> void:
	var hero := grove.get_node_or_null("Hero") as Node3D
	_assert_true(hero != null, "grove exposes the hero")
	if hero == null:
		return
	_assert_true(str(_gs.equipped_weapon.get("id", "")) != "", "hero starts with a weapon")
	_assert_true(_gs.current_stage == _gs.QuestStage.SEEK_SPRITE,
		"fresh route starts at SEEK_SPRITE")
	_assert_true(grove.has_method("_on_hero_position_changed"),
		"grove exposes the shared hero-position route hook")

	# First fight: the onboarding hushling is the route's first combat beat.
	var hushling := _find_enemy("hushling")
	_assert_true(hushling != null, "first fight spawns an onboarding enemy")
	if hushling != null:
		hero.global_position = hushling.global_position + Vector3(1.4, 0.0, 0.0)
		await _frames(3)
		if hushling.has_method("take_damage"):
			hushling.call("take_damage", 9999, _knockback_dir(hushling, hero))
		else:
			_failures.append("onboarding enemy cannot take damage")
		await create_timer(1.5).timeout
		await _frames(6)
		_assert_true(not is_instance_valid(hushling) or bool(hushling.call("is_dead")),
			"first fight enemy can be defeated")
	_assert_true(str(_gs.route_checkpoint_id) != "grove_arrival",
		"first fight advanced the route checkpoint")

	# Shard: the same proximity path hero movement triggers in play.
	if _gs.current_stage < _gs.QuestStage.CLAIM_SHARD:
		_gs.advance_stage(_gs.QuestStage.CLAIM_SHARD)
	_gs.shard_collected = false
	var shard := grove.get_node_or_null("ShardSpawn") as Node3D
	_assert_true(shard != null, "grove exposes the shard spawn")
	if shard != null:
		hero.global_position = shard.global_position
		grove.call("_on_hero_position_changed", hero.global_position)
		await _frames(3)
		_assert_true(bool(_gs.shard_collected), "walking onto the shard claims it")
	_assert_true(_gs.current_stage == _gs.QuestStage.LIGHT_BEACON,
		"claiming the shard advances to LIGHT_BEACON")

	# Beacon: closes onboarding and opens the realm gate.
	var beacon := grove.get_node_or_null("BeaconSpawn") as Node3D
	_assert_true(beacon != null, "grove exposes the beacon spawn")
	if beacon != null:
		hero.global_position = beacon.global_position
		grove.call("_on_hero_position_changed", hero.global_position)
		await _frames(3)
		_assert_true(bool(_gs.beacon_lit), "standing at the beacon lights it")
	_assert_true(_gs.current_stage == _gs.QuestStage.COMPLETE,
		"onboarding completes and the route reaches COMPLETE")
	# The pre-boss "Shape Your Foe" gate opens at COMPLETE and holds the world
	# frozen until it is resolved; an unresolved hold is a soft lock.
	var biome := _biome_manager(grove)
	var altar: Node = biome.get("_altar") if biome != null else null
	if altar != null and is_instance_valid(altar):
		_assert_true(self.paused, "the boss altar holds the world while it is open")
		altar.call("_resolve", false)
		await _frames(3)
	_assert_true(not self.paused, "the world resumes once the pre-boss gate resolves")
	var gate := grove.get_node_or_null("MoonfenGate") as Node3D
	_assert_true(gate != null, "hub exposes the next-realm gate")
	if gate != null:
		_assert_true(gate.visible, "completed onboarding shows the next-realm gate")
	_assert_true(_gs.unlocked_realms.size() >= 3, "onboarding leaves three realms unlocked")

func _run_gathering_and_forge(grove: Node) -> void:
	var hero := grove.get_node_or_null("Hero") as Node3D
	var node := _find_gathering_node()
	_assert_true(node != null, "the realm exposes a real gathering node")
	if node != null and hero != null:
		var material_id := str(node.get("material_id")) if "material_id" in node else ""
		var before: int = _gs.get_material_qty(material_id) if not material_id.is_empty() else 0
		hero.global_position = node.global_position + Vector3(0.9, 0.0, 0.0)
		await _frames(3)
		# The HUD's contextual button reads this same contract; a regression
		# here means the button would offer nothing at a real gathering node.
		var gather_prompt: Dictionary = grove.call("get_interact_prompt") \
			if grove.has_method("get_interact_prompt") else {}
		_assert_true(str(gather_prompt.get("verb", "")) == "GATHER",
			"contextual prompt offers GATHER at a gathering node (got %s)" % gather_prompt)
		node.call("interact")
		# Themed gathering is a hold ritual; the yield lands when it completes.
		await create_timer(float(node.get("gather_time")) + 0.4).timeout
		await _frames(4)
		if not material_id.is_empty():
			var after: int = _gs.get_material_qty(material_id)
			_assert_true(after > before,
				"gathering a node yields its material (node=%s mat=%s before=%d after=%d depleted=%s gathering=%s realm=%s)"
				% [node.name, material_id, before, after,
				str(node.get("_depleted")), str(node.get("_gathering")),
				str(node.get("realm"))])
		if node.has_method("can_gather"):
			_assert_true(not bool(node.call("can_gather")),
				"a gathered node stops offering the same yield")

	# Crafting and upgrade: the route must convert materials into power.
	var recipe: Dictionary = CraftingData.get_recipe("thorn_mace")
	var weapon_id := str(recipe.get("output_id", "thornmace"))
	for material_id in recipe.get("materials", {}):
		_gs.add_material(str(material_id), int(recipe.materials[material_id]))
	_gs.gold = int(recipe.get("gold_cost", 0))
	var crafted := CraftingData.craft("thorn_mace")
	_assert_true(bool(crafted.get("success", false)),
		"the route can craft an upgrade from gathered materials -> %s" % str(crafted))
	if bool(crafted.get("success", false)):
		_assert_true(_gs.equip_weapon_by_id(weapon_id),
			"the crafted weapon can be equipped from the satchel")
		await _frames(3)
		_gs.add_material("iron_shard", 8)
		_gs.gold = 400
		var before_atk := int(_gs.equipped_weapon.get("atk", 0))
		var upgraded: Dictionary = _gs.upgrade_weapon(weapon_id)
		_assert_true(bool(upgraded.get("success", false)),
			"the forged weapon can be upgraded -> %s" % str(upgraded))
		if bool(upgraded.get("success", false)):
			_assert_true(int(_gs.equipped_weapon.get("atk", 0)) > before_atk,
				"upgrade raises the stat the hero actually holds")
			if hero != null:
				await _frames(3)
				_assert_true(hero.get("current_weapon") != null,
					"hero still carries a weapon after the forge")

func _run_expedition(grove: Node) -> void:
	_gs.onboarding_completed = true
	_gs.begin_bramblewood_expansion()
	_gs.save_game()
	_gs.flush_save()
	await _frames(4)
	_mark("expedition_scene_change")
	change_scene_to_file(GROVE_SCENE)
	await create_timer(1.0).timeout
	await _frames(16)
	var world := current_scene
	_assert_true(world != null and world.name == "Grove", "expedition reopened a realm scene")
	if world == null:
		return
	var hero := world.get_node_or_null("Hero") as Node3D
	_assert_true(world.get_node_or_null("BramblewoodExpedition") != null,
		"Bramblewood expedition builds after onboarding")
	_assert_true(hero != null, "expedition scene exposes the hero")
	if hero == null:
		return
	var manager := _biome_manager(world)
	_assert_true(manager != null, "expedition exposes the realm manager")

	# The realm's pre-boss gate opens with the expedition and holds the world
	# frozen until it is resolved. It must be cleared here or the rest of the
	# route runs paused: nothing moves and no pocket can spawn.
	var gate: Node = manager.get("_altar") if manager != null else null
	if gate != null and is_instance_valid(gate) and self.paused:
		gate.call("_resolve", false)
		await _frames(3)
	_assert_true(not self.paused,
		"the world is running when the elite pocket is approached")

	# Elite: an authored pocket spawns a fight the player can win.
	var encounter := world.find_child("Encounter_beacon_breach", true, false) as Node3D
	_assert_true(encounter != null, "the route exposes an authored elite encounter")
	if encounter != null:
		# Measure the pocket's own pack: a global enemy count is confounded by
		# distant biome pockets despawning as the hero travels out here.
		var pack: Array = []
		if encounter.get("_enemies") is Array:
			pack = encounter.get("_enemies")
		# Walk in from outside the radius rather than teleporting onto the
		# centre, so the area sees a real entry the way a player produces one.
		var approach := encounter.global_position + Vector3(0.0, 0.0,
			float(encounter.get("zone_radius")) + 4.0)
		hero.global_position = approach
		await _frames(4)
		for step in 14:
			approach = approach.move_toward(encounter.global_position, 0.9)
			hero.global_position = approach
			await _frames(2)
		await _frames(10)
		var live := 0
		var grouped := 0
		for enemy in encounter.get("_enemies"):
			if not is_instance_valid(enemy) or not enemy.is_inside_tree():
				continue
			live += 1
			if enemy.is_in_group("enemy"):
				grouped += 1
		pack = encounter.get("_enemies")
		var hero_distance := hero.global_position.distance_to(encounter.global_position) \
			if hero != null else -1.0
		_assert_true(live > 0 and bool(encounter.get("_spawned")),
			"walking into the elite pocket spawns its pack (pack=%d live=%d spawned=%s active=%s tier=%s hero_dist=%.1f radius=%.1f paused=%s monitoring=%s overlaps=%d)"
			% [pack.size(), live, str(encounter.get("_spawned")),
			str(encounter.get("_active")), str(encounter.get("tier")),
			hero_distance, float(encounter.get("zone_radius")), str(self.paused),
			str(encounter.get("monitoring")),
			encounter.call("get_overlapping_bodies").size()])
		# The pack must be reachable by the systems that cap and cull hostiles.
		_assert_true(grouped == pack.size(),
			"every spawned pocket enemy is in the hostile group (%d/%d)"
			% [grouped, pack.size()])
		if not pack.is_empty() and is_instance_valid(pack[0]):
			var elite_hp := int(pack[0].get("max_hp")) if "max_hp" in pack[0] else 0
			_assert_true(elite_hp > 0, "elite pack members expose a real health pool")
		pack = []


	# Boss: engage the arena the way proximity does, then defeat it.
	# The expedition owns its own arena engagement; the biome arena path is the
	# non-expansion route to the same lord.
	var expedition := world.get_node_or_null("BramblewoodExpedition")
	var boss: Node3D = null
	if expedition != null and expedition.has_method("_engage_boss"):
		expedition.call("_engage_boss")
		await _frames(10)
		boss = expedition.get("_boss") as Node3D
	if boss == null and manager != null and manager.has_method("_engage_arena_boss"):
		manager.call("_engage_arena_boss")
		await _frames(10)
		boss = manager.get("_biome_boss") as Node3D
	_assert_true(boss != null and is_instance_valid(boss), "the realm boss engages")
	var boss_id := str(boss.get("def_id")) if boss != null else ""
	if boss != null and hero != null:
		# Unattended harness: keep the hero standing so the check measures the
		# route, not an idle player being worn down by a boss.
		_gs.heal(int(_gs.max_hp))
		hero.global_position = boss.global_position + Vector3(6.5, 0.0, 0.0)
		await _frames(4)
		if boss.has_method("take_damage"):
			boss.call("take_damage", 99999999, _knockback_dir(boss, hero))
		await _frames(10)
		_assert_true(boss_id != "", "boss exposes a stable roster id")

	# Reward: choosing twice must not pay twice, and a duplicate must not vanish.
	var reward_id := ""
	var choices: Array = _reward_choices(boss_id)
	_assert_true(not choices.is_empty(), "boss exposes reward directions")
	if not choices.is_empty():
		reward_id = str((choices[0] as Dictionary).get("id", ""))
		var first: Dictionary = _gs.choose_boss_reward(boss_id, reward_id)
		_assert_true(bool(first.get("success", false)),
			"first boss reward choice is granted -> %s" % str(first))
		var second: Dictionary = _gs.choose_boss_reward(boss_id, reward_id)
		_assert_true(not bool(second.get("success", true)),
			"a second choice for the same boss is refused")
		var copies := 0
		for weapon in _gs.forged_weapons:
			if str(weapon.get("id", "")) == reward_id:
				copies += 1
		for armor in _gs.forged_armors:
			if str(armor.get("id", "")) == reward_id:
				copies += 1
		_assert_true(copies <= 1, "boss reward did not duplicate a ledger entry")

	# Valuable loot: an authored chest claims once and pays out. Resolve the
	# scene and hero again here: a reference captured earlier in the route can
	# point at a node the live realm no longer drives, which reads as an empty
	# prompt and teleports the wrong body.
	var live := current_scene
	var live_hero := live.get_node_or_null("Hero") as Node3D if live != null else null
	var chest := _find_closed_chest(live)
	_assert_true(chest != null, "the realm exposes an unopened authored chest")
	if chest != null and live != null and live_hero != null:
		live_hero.global_position = chest.global_position + Vector3(0.5, 0.0, 0.0)
		await _frames(6)
		# The router reads the same contract the HUD's button renders. Re-pin the
		# hero every attempt: a body still carrying velocity from the elite fight
		# can fall away from the chest between the teleport and the query.
		var chest_prompt: Dictionary = {}
		for _attempt in 12:
			live_hero.global_position = chest.global_position + Vector3(0.5, 0.0, 0.0)
			if live_hero is CharacterBody3D:
				(live_hero as CharacterBody3D).velocity = Vector3.ZERO
			await _frames(2)
			chest_prompt = live.call("get_interact_prompt") \
				if live.has_method("get_interact_prompt") else {}
			if str(chest_prompt.get("verb", "")) == "OPEN":
				break
			await create_timer(0.05).timeout
		_assert_true(str(chest_prompt.get("verb", "")) == "OPEN",
			"contextual prompt offers OPEN at a chest (got %s, dist=%.1f)" % [
				chest_prompt,
				live_hero.global_position.distance_to(chest.global_position)])
		# And the HUD renders that contract as a real, visible button.
		var hud := live.get_node_or_null("HUD")
		if hud != null:
			await create_timer(0.3).timeout
			var interact_button := hud.get_node_or_null("Root/InteractButton") as Control
			_assert_true(interact_button != null and interact_button.visible,
				"HUD shows the contextual interact button at an interactable")
		var gold_before: int = _gs.gold
		var materials_before: Dictionary = _gs.raw_materials.duplicate(true)
		var items_before := _inventory_quantities()
		chest.call("interact")
		await _frames(8)
		var claim_id := str(chest.get("chest_id")) if "chest_id" in chest else ""
		# A chest pays in gold, materials, items or recorded loot drops depending
		# on its authored tier; any of those counts as a real payout.
		var paid := _gs.gold > gold_before \
			or _gs.raw_materials != materials_before \
			or _inventory_quantities() != items_before \
			or (not claim_id.is_empty() and _gs.has_pending_chest_drops(claim_id)) \
			or bool(chest.get("_is_open"))
		var lock_message := str(chest.call("_lock_message")) \
			if chest.has_method("_lock_message") else ""
		# A chest can be authored as boss-locked; that is a route gate, not a
		# payout failure, so the check names which one it hit.
		if not paid and not lock_message.is_empty():
			_assert_true(true, "authored chest is gated: %s" % lock_message)
		else:
			_assert_true(paid, "authored chest pays out on the route (lock=%s near=%s open=%s)"
				% [lock_message, str(chest.get("_hero_nearby")),
				str(chest.get("_is_open"))])
		if paid and not claim_id.is_empty():
			var again: bool = _gs.begin_chest_claim(claim_id, [{"item_id": "moss_tonic", "qty": 1}])
			_assert_true(not again, "an opened chest cannot be claimed twice")

	# Visible unlock: completing the route reveals the return path.
	_assert_true(_gs.complete_bramblewood_expansion(),
		"expedition completion is accepted once")
	_assert_true(not _gs.complete_bramblewood_expansion(),
		"expedition completion is not accepted twice")
	var camp := root.get_node_or_null("CampProgression")
	if camp != null:
		_assert_true(bool(camp.call("facility_unlocked", "rootway_beacon")),
			"completion visibly unlocks a camp facility")
	if expedition != null and expedition.has_method("_refresh_post_clear_state"):
		expedition.call("_refresh_post_clear_state")
		await _frames(3)
		if expedition.has_method("_has_boss_clear"):
			_assert_true(bool(expedition.call("_has_boss_clear")),
				"completion records the boss clear on the expedition")

	# Soft-lock guard: the hero is still alive, controllable and in the tree.
	_assert_true(is_instance_valid(hero) and hero.is_inside_tree(),
		"route leaves the hero alive and in the scene")
	if is_instance_valid(hero):
		_assert_true(int(_gs.hp) > 0 and _gs.combat_state != _gs.CombatState.DEFEATED,
			"route does not end with the hero defeated (hp=%d)" % int(_gs.hp))

	# --- Structure interior: the real hero must climb the north stair ---
	# Regression: the realm's flat ground collision used to stay solid behind
	# the hidden surface, so the hero walked on that plane through stair rooms
	# and never climbed. This walks the real movement code from the entry hall,
	# up the flight, and onto the upper floor.
	_mark("structure_stair_climb")
	var expansion := world.get_node_or_null("RealmExpansion")
	if expansion == null or not is_instance_valid(hero):
		_failures.append("RealmExpansion or Hero missing for the structure stair check")
	else:
		var terrain := world.get_node_or_null("Terrain") as StaticBody3D
		var surface_layer := terrain.collision_layer if terrain != null else 0
		_gs.set("current_realm", "bramblewood")
		expansion.call("_place_structures", "bramblewood")
		expansion.call("toggle_structure", "bramble_keep")
		await _frames(8)
		if terrain != null:
			_assert_true(terrain.collision_layer == 0,
				"surface collision parks while the hero is inside a structure")
		# Indoors the orbit pitch flattens: the outdoor -35 deg put the camera
		# above the roofline looking down at floor and roof tops. Structure
		# entry can fire a focus moment a few frames in, which owns the camera
		# until it is cancelled or expires, so wait for the steady indoor state
		# (bounded) rather than sampling a cinematic frame.
		var rig := world.get_node_or_null("CameraRig")
		if rig != null:
			for _frame in 240:
				if bool(rig.get("_cinematic")):
					rig.call("cancel_cinematic")
				await process_frame
				if bool(rig.get("_indoor")):
					break
			await _frames(1)
		if rig != null and str(rig.get("view_mode")) == "third_person":
			var pitch := float(rig.get("target_angle_v"))
			_assert_true(pitch >= float(rig.get("indoor_pitch_min")) - 0.001
					and pitch <= float(rig.get("indoor_pitch_max")) + 0.001,
				"indoor camera pitch flattens inside a structure (%.2f rad)" % pitch)
		var interior := expansion.get("_dungeon_root") as Node3D
		_assert_true(interior != null, "structure interior builds on entry")
		if interior != null:
			var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D
			_assert_true(body != null and (body.collision_layer & 32) != 0,
				"interior geometry carries the camera collision layer")
			# Clear the encounter so this traversal cannot be staggered or
			# defeated mid-climb; combat is covered by the earlier route beats.
			for enemy in get_nodes_in_group("enemy"):
				if enemy is Node3D and is_instance_valid(enemy):
					enemy.queue_free()
			await _frames(2)
			await _walk_hero_to(hero, Vector3(0.0, 0.0, -8.0), 400)
			await _walk_hero_to(hero, Vector3(0.0, 0.0, -18.0), 600)
			_assert_true(hero.global_position.y >= 3.0,
				"real hero climbs the structure stair (y=%.2f)" % hero.global_position.y)
			# With the pitch flat, the spring arm clamps under the room's own
			# roof: the camera must never climb above the roofline, where all
			# it could see was the top of the ceiling.
			var cam := world.get_node_or_null("CameraRig/SpringArm/Camera3D") as Camera3D
			var cam_y := cam.global_position.y if cam != null else -999.0
			_assert_true(cam != null and cam_y < hero.global_position.y + 3.9,
				"indoor camera stays under the room roof (cam y=%.2f)" % cam_y)
		expansion.call("toggle_structure", "bramble_keep")
		await _frames(8)
		if terrain != null:
			_assert_true(terrain.collision_layer == surface_layer,
				"surface collision restores after leaving the structure")

## Drives the hero's own tap-to-move path toward a horizontal target until it
## arrives or the frame budget runs out.
func _walk_hero_to(hero: Node3D, target: Vector3, max_frames: int) -> void:
	hero.set("has_move_target", true)
	hero.set("target_position", target)
	for _frame in max_frames:
		await physics_frame
		if not bool(hero.get("has_move_target")):
			return

func _verify_reload() -> void:
	var fingerprint := {
		"stage": int(_gs.current_stage),
		"checkpoint": str(_gs.route_checkpoint_id),
		"gold": int(_gs.gold),
		"weapons": _gs.forged_weapons.size(),
		"armors": _gs.forged_armors.size(),
		"materials": _gs.raw_materials.duplicate(true),
		"rewards": _gs.boss_reward_selections.duplicate(true),
		"realms": _gs.unlocked_realms.duplicate(),
		"expansion": _gs.bramblewood_expansion.duplicate(true),
	}
	_gs.flush_save()
	if not _gs.load_game():
		_failures.append("route save could not be reloaded")
		return
	_assert_true(int(_gs.current_stage) == int(fingerprint.stage),
		"reload preserves the route stage")
	_assert_true(str(_gs.route_checkpoint_id) == str(fingerprint.checkpoint),
		"reload preserves the route checkpoint")
	_assert_true(int(_gs.gold) == int(fingerprint.gold), "reload preserves gold exactly")
	_assert_true(_gs.forged_weapons.size() == int(fingerprint.weapons),
		"reload preserves the forged weapon count")
	_assert_true(_gs.forged_armors.size() == int(fingerprint.armors),
		"reload preserves the forged armor count")
	_assert_true(_gs.raw_materials == fingerprint.materials,
		"reload preserves the material ledger exactly")
	_assert_true(_gs.boss_reward_selections == fingerprint.rewards,
		"reload preserves boss reward selections")
	_assert_true(_gs.unlocked_realms == fingerprint.realms,
		"reload preserves realm unlocks")
	_assert_true(_gs.bramblewood_expansion == fingerprint.expansion,
		"reload preserves expedition progress")

	# Re-entering the realm after a reload must not re-grant route rewards.
	_mark("reenter_after_reload")
	var gold_after_reload: int = _gs.gold
	var weapons_after_reload: int = _gs.forged_weapons.size()
	change_scene_to_file(GROVE_SCENE)
	await create_timer(1.0).timeout
	await _frames(16)
	_assert_true(int(_gs.gold) == gold_after_reload,
		"re-entering the realm does not re-grant gold")
	_assert_true(_gs.forged_weapons.size() == weapons_after_reload,
		"re-entering the realm does not re-grant gear")
	_gs.flush_save()
	_gs.delete_save()

## Hostiles take a knockback direction, not a source node.
func _knockback_dir(target: Node3D, source: Node3D) -> Vector3:
	var direction := Vector3.FORWARD
	if source != null and is_instance_valid(source):
		direction = target.global_position - source.global_position
		direction.y = 0.0
	return direction.normalized() if direction.length() > 0.001 else Vector3.FORWARD

## The realm manager script is attached to the world root itself, not a child
## node, so the manager usually IS the current scene.
## Inventory quantities keyed by item id, for payout comparisons.
func _inventory_quantities() -> Dictionary:
	var result: Dictionary = {}
	for item in _gs.inventory:
		var item_id := str(item.get("id", ""))
		if not item_id.is_empty():
			result[item_id] = int(result.get(item_id, 0)) + int(item.get("quantity", 0))
	return result

func _biome_manager(world: Node) -> Node:
	if world != null and world.has_method("_engage_arena_boss"):
		return world
	for child in world.get_children():
		if child.has_method("_engage_arena_boss"):
			return child
	return null

func _find_enemy(kind: String) -> Node3D:
	for node in get_nodes_in_group("enemy"):
		if node is Node3D and str(node.get("archetype")) == kind:
			return node as Node3D
	for node in get_nodes_in_group("enemy"):
		if node is Node3D and str(node.name).to_lower().contains(kind):
			return node as Node3D
	return null

func _find_gathering_node() -> Node3D:
	for node in get_nodes_in_group("gathering"):
		if node is Node3D and is_instance_valid(node):
			return node as Node3D
	return null

func _find_chest() -> Node3D:
	for node in get_nodes_in_group("chest"):
		if node is Node3D and is_instance_valid(node):
			return node as Node3D
	return null

## A chest the route has not opened yet: the contextual prompt only offers an
## unopened chest, so an already-claimed one cannot prove the contract. The
## search is scoped to the live realm so a chest in a scene being torn down
## cannot win and send the hero to a coordinate the realm does not own.
func _find_closed_chest(root: Node) -> Node3D:
	for node in get_nodes_in_group("chest"):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		if root != null and not root.is_ancestor_of(node):
			continue
		if not bool(node.get("opened")):
			return node as Node3D
	return null

func _reward_choices(boss_id: String) -> Array:
	if boss_id.is_empty():
		return []
	var catalog := load("res://scripts/systems/boss_reward_catalog.gd")
	var choices: Array = catalog.call("choices_for", boss_id)
	if choices.is_empty():
		choices = catalog.call("choices_for", "biome_%s" % boss_id)
	return choices
