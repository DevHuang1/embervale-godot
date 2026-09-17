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

## Convert the already-applied RewardManager summary into display-only entries.
## Prefixes keep a material and a weapon with the same item id distinct while
## synthetic currency ids keep the model's non-empty-id contract intact.
static func entries_from_summary(reward_summary: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	_append_summary_entry(entries, "currency_gold", "Gold",
		int(reward_summary.get("gold", 0)), 0)
	_append_summary_entry(entries, "currency_xp", "Experience",
		int(reward_summary.get("xp", 0)), 0)
	_append_summary_entry(entries, "currency_diamonds", "Diamonds",
		int(reward_summary.get("diamonds", 0)), 2)
	for raw in reward_summary.get("materials", []):
		if raw is Dictionary:
			var drop: Dictionary = raw
			var id := str(drop.get("id", ""))
			_append_summary_entry(entries, "material:%s" % id, _pretty_id(id),
				int(drop.get("qty", drop.get("quantity", 1))), 0)
	for raw in reward_summary.get("items", []):
		if raw is Dictionary:
			var drop: Dictionary = raw
			var id := str(drop.get("id", ""))
			_append_summary_entry(entries, "item:%s" % id, _pretty_id(id),
				int(drop.get("qty", drop.get("quantity", 1))), int(drop.get("rarity", 0)))
	for collection_key in ["weapons", "armors"]:
		for raw in reward_summary.get(collection_key, []):
			if raw is Dictionary:
				var drop: Dictionary = raw
				var id := str(drop.get("id", ""))
				_append_summary_entry(entries, "%s:%s" % [collection_key, id],
					_pretty_id(id), int(drop.get("quantity", 1)), int(drop.get("rarity", 0)))
	return entries

static func _append_summary_entry(entries: Array[Dictionary], id: String,
		label: String, quantity: int, rarity: int) -> void:
	if id.is_empty() or quantity <= 0:
		return
	entries.append({"id": id, "label": label, "quantity": quantity,
		"rarity": clampi(rarity, 0, RARITY_SECONDS.size() - 1)})

static func _pretty_id(id: String) -> String:
	return id.replace("_", " ").capitalize() if not id.is_empty() else "Reward"

static func summary(entries: Array) -> String:
	var parts: Array[String] = []
	for item in entries:
		parts.append("%s ×%d" % [str(item.get("label", item.get("id", "item"))),
			maxi(1, int(item.get("quantity", 1)))])
	return " · ".join(parts) if not parts.is_empty() else "No reward"
