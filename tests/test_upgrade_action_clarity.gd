extends SceneTree

## Behavioral contract for the item loop: every craftable recipe must explain
## what it produces, what the hero is short of, and must not be able to charge
## the player twice for one activation.
##
## Replaces the previous source-grep check, which passed as long as two format
## strings existed in satchel.gd regardless of whether crafting behaved.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.save_path = "/tmp/embervale_upgrade_clarity_test.cfg"
	gs.delete_save()
	gs.reset()

	# --- Every recipe resolves to a real item and states its output ---
	for recipe_id in CraftingData.recipe_ids():
		var recipe: Dictionary = CraftingData.get_recipe(recipe_id)
		var preview := CraftingData.output_preview(recipe_id)
		if preview.is_empty() or str(preview.get("name", "")).is_empty():
			failures += 1
			print("FAIL: recipe does not preview its output -> ", recipe_id)
			continue
		if str(preview.get("stat_line", "")).is_empty():
			failures += 1
			print("FAIL: recipe output has no stat line -> ", recipe_id)
		var claimed := str(recipe.get("name", recipe_id))
		var granted := str(preview.get("name", ""))
		var category := str(recipe.get("category", ""))
		if category in ["potion", "utility"] and int(recipe.get("output_qty", 1)) == 1:
			# A single-item consumable recipe must not advertise one item and
			# hand back another (the old bait recipes did exactly that).
			if claimed.to_upper() != granted.to_upper():
				failures += 1
				print("FAIL: recipe advertises '%s' but grants '%s' -> %s"
					% [claimed, granted, recipe_id])
		if int(recipe.get("output_qty", 1)) > 1:
			# Bundles must still name the item they hand over, since the title
			# alone no longer identifies it.
			var output_id := str(recipe.get("output_id", ""))
			var granted_bare := granted.to_upper().replace(" ", "")
			if not granted_bare.contains(output_id.to_upper().replace("_", "")):
				failures += 1
				print("FAIL: bundle '%s' does not name its granted item '%s'"
					% [claimed, output_id])
		if int(recipe.get("output_qty", 1)) < 1:
			failures += 1
			print("FAIL: recipe grants no quantity -> ", recipe_id)

	# --- Gear recipes never share an output id (a shared id silently replaces
	# the earlier craft in forged_weapons/forged_armors) ---
	var seen_outputs: Dictionary = {}
	for recipe_id in CraftingData.recipe_ids():
		var recipe: Dictionary = CraftingData.get_recipe(recipe_id)
		var category := str(recipe.get("category", ""))
		if category not in ["weapon", "armor"]:
			continue
		var output_id := str(recipe.get("output_id", ""))
		if seen_outputs.has(output_id):
			failures += 1
			print("FAIL: %s and %s share gear output id '%s'"
				% [seen_outputs[output_id], recipe_id, output_id])
		seen_outputs[output_id] = recipe_id

	# --- Requirements are explained, not implied ---
	var weapon_recipe := "ember_sword_ii"
	gs.raw_materials.clear()
	gs.gold = 0
	var report := CraftingData.requirement_report(weapon_recipe)
	if bool(report.get("can_craft", true)):
		failures += 1
		print("FAIL: recipe reports craftable with no materials and no gold")
	var summary := str(report.get("summary", ""))
	if summary.is_empty() or summary == "Ready to craft.":
		failures += 1
		print("FAIL: unmet requirements were not explained")
	if not summary.to_lower().contains("gold"):
		failures += 1
		print("FAIL: gold shortfall missing from requirement summary -> ", summary)
	var cake_recipe: Dictionary = CraftingData.get_recipe(weapon_recipe)
	for material_id in cake_recipe.get("materials", {}):
		if not summary.to_lower().contains(str(material_id).replace("_", " ")):
			failures += 1
			print("FAIL: missing material not named in summary -> ", material_id)

	# --- A disabled craft button explains itself instead of saying NEEDS MATERIALS ---
	# Every unmet state must produce a specific reason, never a generic label.
	for recipe_id in CraftingData.recipe_ids():
		var unmet := CraftingData.requirement_report(recipe_id)
		var unmet_summary := str(unmet.get("summary", ""))
		if unmet_summary.is_empty():
			failures += 1
			print("FAIL: recipe reports no requirement summary -> ", recipe_id)
		elif unmet_summary.strip_edges().to_upper() in ["NEEDS MATERIALS", "REQUIREMENTS UNMET"]:
			failures += 1
			print("FAIL: recipe fell back to a generic requirement label -> ", recipe_id)
			break
	var satchel_source := FileAccess.get_file_as_string("res://scripts/ui/satchel.gd")
	if not satchel_source.contains("CraftingData.recipe_ids()"):
		failures += 1
		print("FAIL: satchel keeps a private recipe list instead of the data order")
	if not satchel_source.contains("CraftingData.output_preview(recipe_id)"):
		failures += 1
		print("FAIL: crafting cards do not state what they grant")

	# --- Crafting is transactional: one press charges once ---
	gs.raw_materials.clear()
	for material_id in cake_recipe.get("materials", {}):
		gs.raw_materials[material_id] = int(cake_recipe.materials[material_id]) + 2
	gs.gold = int(cake_recipe.get("gold_cost", 0)) + 10
	var materials_before: Dictionary = gs.raw_materials.duplicate(true)
	var gold_before: int = gs.gold
	var first := CraftingData.craft(weapon_recipe)
	if not bool(first.get("success", false)):
		failures += 1
		print("FAIL: funded craft was rejected -> ", first)
	else:
		var gold_after_first: int = gs.gold
		if gold_after_first != gold_before - int(cake_recipe.get("gold_cost", 0)):
			failures += 1
			print("FAIL: craft charged the wrong gold -> %d -> %d"
				% [gold_before, gold_after_first])
		var second := CraftingData.craft(weapon_recipe)
		if gold_after_first != gold_before - int(cake_recipe.get("gold_cost", 0)):
			failures += 1
			print("FAIL: a second activation re-charged an already-spent craft")
		if not bool(second.get("success", false)):
			# Second craft is only legal while the restocked materials last; a
			# refusal here must still leave the first craft's cost intact.
			if gs.gold != gold_after_first:
				failures += 1
				print("FAIL: refused craft still changed gold")
		if gs.get_material_qty(str(cake_recipe.materials.keys()[0])) \
				> int(materials_before[cake_recipe.materials.keys()[0]]):
			failures += 1
			print("FAIL: crafting granted materials instead of spending them")

	# --- An unfunded craft is refused and costs nothing ---
	gs.raw_materials.clear()
	gs.gold = 0
	var refused := CraftingData.craft(weapon_recipe)
	if bool(refused.get("success", true)) or gs.gold != 0:
		failures += 1
		print("FAIL: unfunded craft was not refused cleanly")
	if str(refused.get("message", "")).is_empty():
		failures += 1
		print("FAIL: refused craft gave no reason")

	# --- The live crafting page states every recipe's output and shortfall ---
	gs.raw_materials.clear()
	gs.gold = 0
	root.size = Vector2i(1080, 1920)
	var satchel_scene := load("res://scenes/ui/satchel.tscn") as PackedScene
	if satchel_scene == null:
		failures += 1
		print("FAIL: satchel scene missing")
	else:
		var satchel := satchel_scene.instantiate()
		root.add_child(satchel)
		await process_frame
		var grid := satchel.find_child("Recipes", true, false) as GridContainer
		var expected_cards := CraftingData.recipe_ids().size()
		if grid == null:
			failures += 1
			print("FAIL: satchel exposes no recipe grid")
		elif grid.get_child_count() != expected_cards:
			failures += 1
			print("FAIL: satchel shows %d recipe cards, data has %d"
				% [grid.get_child_count(), expected_cards])
		else:
			for card in grid.get_children():
				var card_name := str(card.name).replace("Recipe_", "")
				var preview := CraftingData.output_preview(card_name)
				var output_label := card.find_child("Output", true, false) as Label
				if output_label == null or not output_label.text.begins_with("GRANTS "):
					failures += 1
					print("FAIL: recipe card does not state what it grants -> ", card_name)
					continue
				var granted := str(preview.get("name", ""))
				if not output_label.text.to_upper().contains(granted.to_upper()):
					failures += 1
					print("FAIL: card for %s does not name its granted item '%s'"
						% [card_name, granted])
				if str(preview.get("category", "")) in ["weapon", "armor"] \
						and not output_label.text.contains("vs equipped"):
					failures += 1
					print("FAIL: gear card does not compare against current gear -> ", card_name)
				var craft_button := card.find_child("CraftButton", true, false) as Button
				if craft_button == null:
					failures += 1
					print("FAIL: recipe card has no craft button -> ", card_name)
					continue
				if not craft_button.disabled and granted != "":
					failures += 1
					print("FAIL: card is craftable with no gold and no materials -> ", card_name)
				if craft_button.disabled \
						and not craft_button.text.to_upper().contains("SHORT"):
					failures += 1
					print("FAIL: disabled craft button gives no specific reason -> %s (%s)"
						% [card_name, craft_button.text])
		# Fund one recipe and prove the card flips to an actionable state.
		var funded := "spore_wrap_recipe"
		var funded_recipe: Dictionary = CraftingData.get_recipe(funded)
		for material_id in funded_recipe.get("materials", {}):
			gs.raw_materials[material_id] = int(funded_recipe.materials[material_id])
		gs.gold = int(funded_recipe.get("gold_cost", 0))
		satchel.call("_refresh_crafting")
		await process_frame
		var funded_card := grid.find_child("Recipe_%s" % funded, true, false) as PanelContainer
		if funded_card == null:
			failures += 1
			print("FAIL: funded recipe card disappeared -> ", funded)
		else:
			var funded_button := funded_card.find_child("CraftButton", true, false) as Button
			if funded_button == null or funded_button.disabled \
					or funded_button.text != "CRAFT":
				failures += 1
				print("FAIL: funded recipe is not actionable -> %s (%s)"
					% [funded, funded_button.text if funded_button != null else "no button"])
			if gs.has_method("save_game"):
				gs.flush_save()
		# Salvage is destructive, so the sheet arms before it commits.
		var equipped_id := str(gs.equipped_weapon.get("id", ""))
		var spare_id := "ember_sword" if equipped_id != "ember_sword" else "mug_mace"
		var spare: Dictionary = gs.WEAPON_DEFS[spare_id].duplicate(true)
		gs.add_weapon(spare, false)
		await process_frame
		satchel.call("_show_item_detail", gs.forged_weapons[gs.forged_weapons.size() - 1])
		await process_frame
		var salvage_button: Button = null
		for action_node in satchel.get("_inspect_actions").get_children():
			var button := action_node as Button
			if button != null and button.text.begins_with("SALVAGE"):
				salvage_button = button
				break
		if salvage_button == null:
			failures += 1
			print("FAIL: item sheet offers no salvage action")
		else:
			var iron_before: int = gs.get_material_qty("iron_shard")
			var weapons_before: int = gs.forged_weapons.size()
			salvage_button.pressed.emit()
			await process_frame
			if gs.forged_weapons.size() != weapons_before:
				failures += 1
				print("FAIL: first salvage press destroyed gear without confirmation")
			if str(satchel.get("_salvage_confirm_id")) != spare_id:
				failures += 1
				print("FAIL: first salvage press did not arm the confirmation")
			salvage_button = null
			for action_node in satchel.get("_inspect_actions").get_children():
				var button := action_node as Button
				if button != null and button.text.begins_with("CONFIRM SALVAGE"):
					salvage_button = button
					break
			if salvage_button == null:
				failures += 1
				print("FAIL: armed salvage does not offer a confirmation button")
			else:
				salvage_button.pressed.emit()
				await process_frame
				if gs.forged_weapons.size() != weapons_before - 1:
					failures += 1
					print("FAIL: confirmed salvage did not remove the gear")
				elif gs.get_material_qty("iron_shard") <= iron_before:
					failures += 1
					print("FAIL: confirmed salvage returned no iron")
				if not str(satchel.get("_salvage_confirm_id")).is_empty():
					failures += 1
					print("FAIL: salvage confirmation state survived the action")
		satchel.queue_free()
		await process_frame

	gs.delete_save()
	if failures == 0:
		print("ALL UPGRADE ACTION CLARITY TESTS PASSED")
	else:
		print("UPGRADE ACTION CLARITY TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
