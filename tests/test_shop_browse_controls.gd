extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var shop_scene := load("res://scenes/ui/shop_menu.tscn") as PackedScene
	if shop_scene == null:
		print("FAIL: shop scene missing")
		quit(1)
		return
	var shop := shop_scene.instantiate()
	root.add_child(shop)
	await process_frame
	var ledger_label := shop.find_child("OwnershipLedgerSummary", true, false) as Label
	if ledger_label == null or not ledger_label.text.contains("OWNERSHIP LEDGER") \
		or not ledger_label.text.contains("LAST:"):
		print("FAIL: player-facing ownership ledger summary missing")
		quit(1)
		return
	if shop.find_child("ViewOwnershipHistory", true, false) == null:
		print("FAIL: ownership history action missing")
		quit(1)
		return

	shop.set("_kind_filter", "all")
	shop.set("_sort_mode", "price")
	var by_price: Array[Dictionary] = shop.call("_sorted_stock")
	for index in range(1, by_price.size()):
		if int(by_price[index - 1].get("price", 0)) > int(by_price[index].get("price", 0)):
			print("FAIL: price sort is not ascending")
			quit(1)
			return

	shop.set("_sort_mode", "power")
	var by_power: Array[Dictionary] = shop.call("_sorted_stock")
	for index in range(1, by_power.size()):
		var previous_power := float(shop.call("_stock_power", by_power[index - 1]))
		var current_power := float(shop.call("_stock_power", by_power[index]))
		if previous_power < current_power:
			print("FAIL: power sort is not descending")
			quit(1)
			return

	shop.set("_kind_filter", "armor")
	var armor_stock: Array[Dictionary] = shop.call("_sorted_stock")
	if armor_stock.is_empty():
		print("FAIL: armor filter returned no stock")
		quit(1)
		return
	for entry in armor_stock:
		if str(entry.get("kind", "")) != "armor":
			print("FAIL: armor filter leaked another category")
			quit(1)
			return

	shop.call("_set_mode", "sell")
	var filter_button := shop.get("_filter_button") as Button
	if filter_button == null or not filter_button.disabled:
		print("FAIL: sell mode did not disable buy filter")
		quit(1)
		return

	shop.queue_free()
	print("ALL SHOP BROWSE CONTROL TESTS PASSED")
	quit(0)
