extends RefCounted
class_name StreamingBudgetCatalog

## Release thresholds for first-use and streamed presentation checks. These are
## diagnostics only; gameplay remains usable if a budget is exceeded.
const BUDGETS: Dictionary = {
	"first_use_stutter_ms": 120.0,
	"shader_warmup_ms": 180.0,
	"texture_memory_mb": 256.0,
	"realm_transition_ms": 500.0,
	"chunk_rebuild_ms": 80.0,
}

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for key in ["first_use_stutter_ms", "shader_warmup_ms", "texture_memory_mb", "realm_transition_ms", "chunk_rebuild_ms"]:
		var value := float(BUDGETS.get(key, -1.0))
		if value <= 0.0:
			errors.append("Streaming budget must be positive: %s" % key)
	if float(BUDGETS["chunk_rebuild_ms"]) >= float(BUDGETS["realm_transition_ms"]):
		errors.append("Chunk rebuild budget must be below transition budget")
	return errors

static func evaluate(measurements: Dictionary) -> Dictionary:
	var results: Dictionary = {}
	for key in BUDGETS:
		var measured := float(measurements.get(key, 0.0))
		results[key] = {"measured": measured, "budget": float(BUDGETS[key]),
			"within_budget": measured <= float(BUDGETS[key])}
	return results
