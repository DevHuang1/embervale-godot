extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	game_state.reset()
	var weapon: Dictionary = game_state.WEAPON_DEFS["ember_sword"].duplicate(true)
	weapon["kind"] = "weapon"
	var armor: Dictionary = game_state.ARMOR_DEFS["warden_plate"].duplicate(true)
	armor["kind"] = "armor"
	game_state.add_weapon(weapon, false)
	game_state.add_armor(armor, false)
	var preview := HeroPreviewPanel.new()
	root.add_child(preview)
	await process_frame
	if not preview._can_drop_data(Vector2.ZERO, weapon):
		_fail("Weapon was not accepted by the hero preview")
	preview._drop_data(Vector2.ZERO, weapon)
	await process_frame
	if str(game_state.equipped_weapon.get("id", "")) != "ember_sword":
		_fail("Valid weapon drop did not equip")
	var weapon_before_invalid := str(game_state.equipped_weapon.get("id", ""))
	var invalid := {"id": "moss_tonic", "kind": "consumable"}
	if preview._can_drop_data(Vector2.ZERO, invalid):
		_fail("Invalid item was accepted by the hero preview")
	preview._drop_data(Vector2.ZERO, invalid)
	if str(game_state.equipped_weapon.get("id", "")) != weapon_before_invalid:
		_fail("Invalid drop mutated weapon equipment")
	preview._drop_data(Vector2.ZERO, armor)
	await process_frame
	if str(game_state.equipped_armor.get("id", "")) != "warden_plate":
		_fail("Valid armor drop did not equip")
	var weapon_slot := preview.get_node("HeroContent/PreviewAndSlots/EquipmentSlots/WeaponSlot") as EquipmentSlot
	weapon_slot._drop_data(Vector2.ZERO, weapon)
	await process_frame
	if str(game_state.equipped_weapon.get("id", "")) != "ember_sword":
		_fail("Equipment slot fallback did not equip the weapon")
	var fallback_armor: Dictionary = game_state.ARMOR_DEFS["emberweave_cloak"].duplicate(true)
	fallback_armor["kind"] = "armor"
	game_state.add_armor(fallback_armor, false)
	game_state.unequip_slot(&"chest")
	var satchel_scene := load("res://scenes/ui/satchel.tscn") as PackedScene
	var satchel := satchel_scene.instantiate() as SatchelUI
	root.add_child(satchel)
	await process_frame
	satchel.call("_show_item_detail", fallback_armor)
	var inspect_sheet := satchel.get("_inspect_sheet") as Control
	var fallback_equip: Button = null
	for button_node in inspect_sheet.find_children("*", "Button", true, false):
		var candidate := button_node as Button
		if candidate != null and candidate.text == "EQUIP":
			fallback_equip = candidate
			break
	if fallback_equip == null:
		_fail("Inspect sheet did not expose the mobile EQUIP fallback")
	else:
		fallback_equip.pressed.emit()
		if str(game_state.equipped_armor.get("id", "")) != "emberweave_cloak":
			_fail("Inspect sheet EQUIP fallback did not equip armor")
	if failures.is_empty():
		print("HERO PREVIEW EQUIPMENT TESTS PASSED")
	else:
		print("HERO PREVIEW EQUIPMENT TESTS FAILED: ", failures)
	quit(1 if not failures.is_empty() else 0)

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL: ", message)
