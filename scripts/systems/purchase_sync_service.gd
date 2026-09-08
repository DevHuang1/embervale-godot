extends RefCounted
class_name PurchaseSyncService

## Purchase completion is deliberately server-confirmed. This service only
## records provider-independent sync state and never grants inventory locally.

signal sync_required
var awaiting_confirmation: bool = false

func begin_provider_purchase() -> void:
	awaiting_confirmation = true

func provider_purchase_finished() -> void:
	awaiting_confirmation = false
	sync_required.emit()

func restore_requested() -> void:
	awaiting_confirmation = true
	sync_required.emit()
