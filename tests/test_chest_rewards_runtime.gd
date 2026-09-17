extends SceneTree

## Runtime contract for persistent, gated, and repeatable ChestNode rewards,
## plus the physical loot pickup path (spawn height, exactly-once claim,
## reload restore) and reward/inventory integrity.

var _failures := 0
var _grant_count := 0
var _last_summary: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(func() -> void:
		print("WATCHDOG TIMEOUT — chest runtime test hung")
		quit(2))

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	var rewards := root.get_node_or_null("/root/RewardManager")
	if gs == null or rewards == null:
		_fail("required reward autoloads are missing")
		quit(_failures)
		return
	gs.save_path = "/tmp/embervale_chest_rewards_%d.cfg" % OS.get_process_id()
	gs.delete_save()
	gs.reset()

	var host := Node3D.new()
	host.name = "ChestRuntimeHost"
	root.add_child(host)

	var persistent := ChestNode.new()
	persistent.name = "PersistentChest"
	persistent.chest_id = "test_persistent_chest"
	persistent.chest_label = "TEST CACHE"
	persistent.realm_id = "bramblewood"
	persistent.chest_tier = "common"
	persistent.persistence_mode = "persistent"
	persistent.respawn_time_sec = 0.0
	host.add_child(persistent)
	await process_frame
	var before_gold := int(gs.gold)
	rewards.reward_granted.connect(_on_reward_granted_test)
	persistent.interact()
	await process_frame
	_assert(persistent.opened, "persistent chest opens after a successful grant")
	_assert(bool(gs.opened_chests.get("test_persistent_chest", false)),
		"persistent chest writes opened_chests")
	_assert(str(_last_summary.get("source", "")) == "chest" \
		and str(_last_summary.get("source_id", "")) == "test_persistent_chest" \
		and bool(_last_summary.get("persistent", false)),
		"chest reward carries persistent source metadata")
	_assert(int(gs.gold) >= before_gold, "persistent chest does not reduce gold")
	var first_grant_count := _grant_count
	persistent.interact()
	await process_frame
	_assert(_grant_count == first_grant_count, "persistent chest cannot grant twice")

	var restored := ChestNode.new()
	restored.name = "RestoredPersistentChest"
	restored.chest_id = "test_persistent_chest"
	restored.persistence_mode = "persistent"
	host.add_child(restored)
	await process_frame
	_assert(restored.opened, "persistent chest restores open state on reload")

	var repeatable := ChestNode.new()
	repeatable.name = "RepeatableChest"
	repeatable.chest_id = ""
	repeatable.persistence_mode = "respawnable"
	repeatable.respawn_time_sec = 0.05
	host.add_child(repeatable)
	await process_frame
	repeatable.interact()
	await process_frame
	_assert(repeatable.opened, "repeatable chest opens")
	await create_timer(0.12).timeout
	_assert(not repeatable.opened, "repeatable chest resets after bounded cooldown")

	var gated := ChestNode.new()
	gated.name = "GatedChest"
	gated.configure_from_definition({
		"id": "test_gated_chest",
		"label": "ALPHA HOARD",
		"rarity": 3,
		"type": "boss_gated",
		"boss_key": "test_boss_key",
	})
	gated.persistence_mode = "persistent"
	host.add_child(gated)
	await process_frame
	gated.interact()
	await process_frame
	_assert(not gated.opened, "boss-gated chest remains closed before boss defeat")
	gs.mark_boss_killed("test_boss_key")
	gated.interact()
	await process_frame
	_assert(gated.opened, "boss-gated chest opens after boss defeat")
	_assert(gated.chest_tier == "rare", "rarity 3 maps to rare chest tier")

	# Tear the first scene down so each loot section only sees its own drops.
	host.queue_free()
	await process_frame

	await _run_physical_loot(gs, rewards)
	await _run_reload_restore(gs)

	# Let queued pickups finish their collect tween before exit.
	await create_timer(0.4).timeout
	quit(_failures)

# ─────────────────────────────────────────────────────────────────────────────
# Physical loot + pending claim
# ─────────────────────────────────────────────────────────────────────────────

func _run_physical_loot(gs: Node, rewards: Node) -> void:
	gs.reset()
	var host := Node3D.new()
	host.name = "ChestLootHost"
	root.add_child(host)

	# A real chest opens and claims regardless of what its random table rolls.
	var chest := ChestNode.new()
	chest.name = "PhysicalLootChest"
	chest.chest_id = "test_physical_chest"
	chest.chest_label = "PHYSICAL CACHE"
	chest.realm_id = "bramblewood"
	chest.chest_tier = "rare"
	chest.persistence_mode = "persistent"
	host.add_child(chest)
	await process_frame
	chest.interact()
	await process_frame
	_assert(chest.opened, "physical loot chest opens")
	_assert(bool(gs.opened_chests.get("test_physical_chest", false)),
		"physical loot chest persists its claim")
	host.queue_free()
	await process_frame

	# Deterministic roll so pickup height, pending clearing, and grants are
	# asserted without the chest table's randomness.
	var loot_host := Node3D.new()
	loot_host.name = "DeterministicLootHost"
	root.add_child(loot_host)
	var anchor := Node3D.new()
	anchor.position = Vector3(0.0, 5.0, 0.0)
	loot_host.add_child(anchor)

	var claim_drops: Array = [
		{"type": "gold", "id": "", "quantity": 11, "rarity": 0},
		{"type": "item", "id": "hushling_thorn", "quantity": 2, "rarity": 1},
		{"type": "weapon", "id": "ember_sword", "quantity": 1, "rarity": 2},
	]
	_assert(gs.begin_chest_claim("test_claim_chest", claim_drops),
		"claim records a pending chest roll")
	_assert(_pending_count(gs, "test_claim_chest") == claim_drops.size(),
		"every physical drop is recorded pending")
	for i in claim_drops.size():
		var angle := TAU * float(i) / float(claim_drops.size())
		load("res://scripts/systems/loot_drop.gd").spawn_drop(anchor,
			anchor.global_position + Vector3(cos(angle) * 0.4, 0.55, sin(angle) * 0.4),
			claim_drops[i], "test_claim_chest", i)
	await process_frame
	await physics_frame
	var drops := _live_drops()
	_assert(drops.size() == claim_drops.size(),
		"one physical pickup spawns per recorded drop")

	# The bob must not sink drops to world y≈0; they keep their spawn height.
	var anchor_y := anchor.global_position.y
	for drop in drops:
		_assert(absf(drop.global_position.y - anchor_y) < 1.6,
			"drop holds its spawn height instead of sinking to world zero")

	var before_gold := int(gs.gold)
	for drop in drops:
		drop._collect(null)
	await process_frame
	await process_frame
	_assert(int(gs.gold) == before_gold + 11,
		"collected gold lands in GameState")
	_assert(not gs.has_pending_chest_drops("test_claim_chest"),
		"collecting every drop clears the pending claim")

	loot_host.queue_free()
	await process_frame

	# A crafted weapon style drop must reach forged gear, not the item path.
	var grant: Dictionary = rewards.grant_drops([
		{"type": "weapon", "id": "ember_sword", "quantity": 1, "rarity": 2},
		{"type": "armor", "id": "warden_plate", "quantity": 1, "rarity": 2},
		{"type": "weapon", "id": "not_a_real_weapon", "quantity": 1, "rarity": 2},
	])
	_assert(gs.forged_weapons.any(func(w): return str(w.get("id", "")) == "ember_sword"),
		"weapon reward reaches the forged weapon inventory")
	_assert(gs.forged_armors.any(func(a): return str(a.get("id", "")) == "warden_plate"),
		"armor reward reaches the forged armor inventory")
	_assert((grant.get("weapons", []) as Array).size() == 1,
		"only actually-granted weapons are reported")
	_assert((grant.get("armors", []) as Array).size() == 1,
		"only actually-granted armors are reported")

	# A never-owned consumable still lands in the satchel.
	gs.add_loot("ember_salve", 2, "", 2)
	_assert(int(gs.get_item("ember_salve").get("quantity", 0)) == 2,
		"first pickup of a new consumable lands in the satchel")

	# The reveal preview reports the roll without granting any of it.
	var gold_before_preview := int(gs.gold)
	var preview: Dictionary = rewards.chest_roll_preview([
		{"type": "gold", "id": "", "quantity": 500, "rarity": 0},
		{"type": "weapon", "id": "ember_sword", "quantity": 1, "rarity": 2},
	])
	_assert(int(preview.get("gold", 0)) == 500 and bool(preview.get("preview", false)),
		"chest roll preview reports the rolled contents as a preview")
	_assert(int(gs.gold) == gold_before_preview,
		"chest roll preview never grants currency")

# ─────────────────────────────────────────────────────────────────────────────
# Reload mid-collection restores only the uncollected remainder
# ─────────────────────────────────────────────────────────────────────────────

func _run_reload_restore(gs: Node) -> void:
	gs.reset()
	var host := Node3D.new()
	host.name = "ChestReloadHost"
	root.add_child(host)
	var anchor := Node3D.new()
	host.add_child(anchor)
	await process_frame

	var claim_drops: Array = [
		{"type": "gold", "id": "", "quantity": 5, "rarity": 0},
		{"type": "item", "id": "hushling_thorn", "quantity": 1, "rarity": 1},
		{"type": "gold", "id": "", "quantity": 3, "rarity": 0},
	]
	_assert(gs.begin_chest_claim("test_reload_chest", claim_drops),
		"reload claim recorded")
	for i in claim_drops.size():
		load("res://scripts/systems/loot_drop.gd").spawn_drop(anchor,
			anchor.global_position + Vector3(0.3 * float(i), 0.55, 0.0),
			claim_drops[i], "test_reload_chest", i)
	await process_frame
	await physics_frame
	var total: int = _pending_count(gs, "test_reload_chest")
	_assert(total == 3, "reload chest recorded a multi-drop roll")

	# Collect exactly one drop, leave the rest on the ground.
	var spawned := _live_drops()
	_assert(spawned.size() == 3, "all three drops spawned before the reload")
	spawned[0]._collect(null)
	await process_frame
	var remaining := _pending_count(gs, "test_reload_chest")
	_assert(remaining == 2, "the collected slot clears but the rest stay pending")

	# Simulate a scene teardown + reload: the remainder must survive.
	gs.flush_save()
	host.queue_free()
	await process_frame
	_assert(gs.load_game(), "reload of the chest save succeeds")
	_assert(_pending_count(gs, "test_reload_chest") == remaining,
		"uncollected remainder survives save/load")

	var restored_host := Node3D.new()
	root.add_child(restored_host)
	var restored_chest := ChestNode.new()
	restored_chest.name = "RestoredReloadChest"
	restored_chest.chest_id = "test_reload_chest"
	restored_chest.persistence_mode = "persistent"
	restored_host.add_child(restored_chest)
	await process_frame
	await process_frame
	_assert(restored_chest.opened, "restored chest reopens its claimed state")
	var respawned := _live_drops()
	_assert(respawned.size() == remaining,
		"reload respawns exactly the uncollected remainder")

	for drop in respawned:
		if is_instance_valid(drop):
			drop._collect(null)
	await process_frame
	await process_frame
	_assert(not gs.has_pending_chest_drops("test_reload_chest"),
		"finishing the restored drops clears the claim")

	restored_host.queue_free()
	await process_frame

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _live_drops() -> Array:
	var live: Array = []
	for drop in get_nodes_in_group("loot_drop"):
		if is_instance_valid(drop) and not drop.collected:
			live.append(drop)
	return live

func _pending_count(gs: Node, chest_id: String) -> int:
	var drops: Variant = gs.pending_chest_drops.get(chest_id, null)
	if not drops is Array:
		return 0
	var count := 0
	for entry in drops as Array:
		if entry != null:
			count += 1
	return count

func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)

func _on_reward_granted_test(summary: Dictionary) -> void:
	_grant_count += 1
	_last_summary = summary

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: %s" % message)
