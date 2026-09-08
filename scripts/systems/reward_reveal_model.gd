extends RefCounted
class_name RewardRevealModel

## Presentation data only. Granting remains owned by RewardManager and is never
## delayed or repeated by this reveal model.
const MAX_ENTRIES: int = 12
const RARITY_SECONDS: Array[float] = [0.35, 0.55, 0.8, 1.1, 1.35]

static func build(entries: Array, source: String = "reward") -> Dictionary:
	var visible: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw in entries:
		if not raw is Dictionary or visible.size() >= MAX_ENTRIES:
			continue
		var item: Dictionary = raw
		var id := str(item.get("id", "")).strip_edges()
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		var rarity := clampi(int(item.get("rarity", 0)), 0, RARITY_SECONDS.size() - 1)
		visible.append({"id": id, "label": str(item.get("label", id)),
			"quantity": maxi(1, int(item.get("quantity", 1))), "rarity": rarity,
			"reveal_seconds": RARITY_SECONDS[rarity]})
	return {"source": source.strip_edges() if not source.strip_edges().is_empty() else "reward",
		"entries": visible, "skippable": true, "summary": summary(visible)}

static func summary(entries: Array) -> String:
	var parts: Array[String] = []
	for item in entries:
		parts.append("%s ×%d" % [str(item.get("label", item.get("id", "item"))),
			maxi(1, int(item.get("quantity", 1)))])
	return " · ".join(parts) if not parts.is_empty() else "No reward"
