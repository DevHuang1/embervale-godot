extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/streaming_budget_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty():
		push_error("Streaming budgets invalid: %s" % "; ".join(errors))
		quit(1)
		return
	var result: Dictionary = catalog.evaluate({"chunk_rebuild_ms": 40.0})
	if not bool(result["chunk_rebuild_ms"].get("within_budget", false)) \
			or bool(result["shader_warmup_ms"].get("within_budget", false)) != true:
		push_error("Streaming budget evaluation failed")
		quit(1)
		return
	print("STREAMING BUDGET CATALOG PASSED")
	quit(0)
