extends SceneTree

func _init() -> void:
	var queue := preload("res://scripts/systems/cloud_sync_queue.gd").new()
	if not queue.enqueue("upgrade-1", "upgrade_weapon", {"item_id": "ember_sword"}):
		push_error("Initial sync action was rejected")
	if queue.enqueue("upgrade-1", "upgrade_weapon", {}):
		push_error("Duplicate sync action was accepted")
	if queue.enqueue("forbidden", "upgrade_weapon", {"gold": 9999}) \
			or queue.enqueue("nested-forbidden", "upgrade_weapon", {"meta": {"inventory": []}}):
		push_error("Queue accepted a client-authoritative replacement payload")
	if not queue.mark_attempted("upgrade-1") or int(queue.pending()[0].get("attempts", 0)) != 1:
		push_error("Sync attempt count was not retained")
	var restored := preload("res://scripts/systems/cloud_sync_queue.gd").new()
	restored.restore(queue.pending())
	if restored.pending().size() != 1 or str(restored.pending()[0].get("action", "")) != "upgrade_weapon":
		push_error("Sync queue did not restore an action")
	if not restored.mark_attempted("upgrade-1") or int(restored.pending()[0].get("attempts", 0)) != 2:
		push_error("Restored sync retry count was not incremented")
	if not restored.acknowledge("upgrade-1") or not restored.pending().is_empty():
		push_error("Acknowledged sync action was not removed")
	var capped := preload("res://scripts/systems/cloud_sync_queue.gd").new()
	for index in capped.MAX_PENDING_ACTIONS:
		if not capped.enqueue("cap-%d" % index, "test_action", {}):
			push_error("Queue rejected action before its cap")
	if capped.enqueue("over-cap", "test_action", {}) or capped.pending().size() != capped.MAX_PENDING_ACTIONS:
		push_error("Queue exceeded its bounded pending-action cap")
	var reconciled := preload("res://scripts/systems/cloud_sync_queue.gd").new()
	reconciled.enqueue("accepted", "upgrade", {})
	reconciled.enqueue("retry", "purchase", {})
	reconciled.enqueue("rejected", "craft", {})
	var summary: Dictionary = reconciled.reconcile([
		{"id": "accepted", "status": "accepted"},
		{"id": "retry", "status": "timeout"},
		{"id": "rejected", "status": "conflict"},
		{"id": "unknown", "status": "accepted"},
	])
	if int(summary["acknowledged"]) != 1 or int(summary["retryable"]) != 1 \
			or int(summary["rejected"]) != 1 or reconciled.pending().size() != 2:
		push_error("Queue reconciliation did not preserve retryable/terminal local intents")
	if str(reconciled.pending()[0].get("delivery_status", "")) != "retryable" \
			or str(reconciled.pending()[1].get("delivery_status", "")) != "rejected":
		push_error("Queue reconciliation did not persist delivery status")
	var round_trip := preload("res://scripts/systems/cloud_sync_queue.gd").new()
	round_trip.restore(reconciled.pending())
	if str(round_trip.pending()[0].get("delivery_status", "")) != "retryable" \
			or str(round_trip.pending()[1].get("delivery_status", "")) != "rejected" \
			or str(round_trip.pending()[0].get("last_error", "")) != "timeout":
		push_error("Delivery status/error did not survive save round-trip")
	print("ALL CLOUD SYNC QUEUE TESTS PASSED")
	quit(0)
