extends SceneTree

## Deterministic waterway contract:
## - Every realm owns a river profile deep and wide enough to read as water.
## - The carved channel never enters the spawn core (the fixed scene anchors
##   all live within ~30 m of the origin) and keeps clearance from every
##   authored gameplay anchor, so no chest, pocket or arena is submerged.
## - Each realm carries a labeled bridge on its centerline inside the
##   authored band, giving the player a dry crossing.

const REALMS := ["whispergrove", "bramblewood", "mistfen", "heartwood", "moonfen"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	for realm in REALMS:
		var spec := WorldWaterways.river_for(realm)
		if spec.is_empty():
			failures += 1
			print("FAIL: %s has no river spec" % realm)
			continue
		var width := float(spec.get("width", 0.0))
		var depth := float(spec.get("depth", 0.0))
		var bank := float(spec.get("bank", 0.0))
		if width < 3.0 or depth < 0.8 or bank < 1.5:
			failures += 1
			print("FAIL: %s river profile is too small to read (%s)" % [realm, spec])

		var core_distance := WorldWaterways.core_center_distance(realm)
		if core_distance < WorldWaterways.carve_reach(spec) + 34.0:
			failures += 1
			print("FAIL: %s river enters the spawn core (%.1f m)" \
				% [realm, core_distance])

		var anchors: Array[Vector2] = []
		var profile_realms: Array[String] = [realm]
		if realm == "whispergrove" or realm == "bramblewood":
			profile_realms = ["whispergrove", "bramblewood"]
		for profile_realm in profile_realms:
			for anchor in RealmLayoutData.flatten_anchors(profile_realm):
				if anchor not in anchors:
					anchors.append(anchor)
		var clearance := WorldWaterways.minimum_anchor_clearance(realm, anchors)
		if clearance < WorldWaterways.ANCHOR_CLEARANCE:
			failures += 1
			print("FAIL: %s river carve reaches a gameplay anchor (%.1f m)" \
				% [realm, clearance])

		var crossings := WorldWaterways.bridge_crossings(realm)
		var labels := WorldWaterways.bridge_labels(realm)
		if crossings.is_empty() or labels.size() != crossings.size():
			failures += 1
			print("FAIL: %s has no labeled bridge crossing" % realm)
		for crossing in crossings:
			if absf(crossing.y) > 300.0:
				failures += 1
				print("FAIL: %s bridge sits outside the authored band (%s)" \
					% [realm, crossing])
			if WorldWaterways.lateral_distance(spec, crossing) > 0.01:
				failures += 1
				print("FAIL: %s bridge is not on its river centerline" % realm)

		if WorldWaterways.center_x(spec, 12.5) != WorldWaterways.center_x(spec, 12.5) \
				or WorldWaterways.center_x(spec, -40.0) != WorldWaterways.center_x(spec, -40.0):
			failures += 1
			print("FAIL: %s river centerline is not deterministic" % realm)

	if failures == 0:
		print("ALL WORLD WATERWAY TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
