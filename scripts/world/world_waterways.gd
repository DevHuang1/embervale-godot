extends RefCounted
class_name WorldWaterways

## === World Waterways ===
## Deterministic river centerlines shared by terrain carving, water
## presentation and vegetation clearance. A river is a north-south meander
## `x = center_x(z)`, so any terrain sample, chunk or prop placement can test
## proximity without per-chunk state and every streamed tile meets its
## neighbours. Paths are authored to pass clear of every flattened gameplay
## anchor, and each realm carries an authored bridge crossing so the channel
## is traversable rather than a wall.

const GROVE_RIVER := {
	"base_x": 152.0, "meander": 10.0, "wavelen": 130.0, "phase": 1.1,
	"detail": 0.25, "width": 5.6, "depth": 1.3, "bank": 3.2,
	"bridges": [{"z": -186.0, "label": "ROOTWAY CROSSING"}],
}

const SPECS := {
	"whispergrove": GROVE_RIVER,
	"bramblewood": GROVE_RIVER,
	"mistfen": {
		"base_x": -125.0, "meander": 12.0, "wavelen": 145.0, "phase": 2.4,
		"detail": 0.25, "width": 5.2, "depth": 1.2, "bank": 3.0,
		"bridges": [{"z": -116.0, "label": "REEDWATER CROSSING"}],
	},
	"heartwood": {
		"base_x": 200.0, "meander": 14.0, "wavelen": 110.0, "phase": 0.6,
		"detail": 0.25, "width": 5.0, "depth": 1.2, "bank": 3.0,
		"bridges": [{"z": -88.0, "label": "ASHFORD CROSSING"}],
	},
	"moonfen": {
		"base_x": 95.0, "meander": 12.0, "wavelen": 125.0, "phase": 3.3,
		"detail": 0.25, "width": 5.4, "depth": 1.25, "bank": 3.1,
		"bridges": [{"z": -20.0, "label": "MOONDRIFT CROSSING"}],
	},
}

## Presentation-only water tints per realm, matching the authored pond family.
const WATER_TINTS := {
	"whispergrove": Color(0.25, 0.42, 0.38, 0.70),
	"bramblewood": Color(0.22, 0.38, 0.33, 0.74),
	"mistfen": Color(0.30, 0.45, 0.50, 0.74),
	"heartwood": Color(0.34, 0.21, 0.15, 0.72),
	"moonfen": Color(0.18, 0.38, 0.58, 0.78),
}

## The channel is defined from z=-RIVER_MIN to +RIVER_MAX so a river reaches
## the relocated world walls instead of ending in mid-stream.
const RIVER_MIN_Z := -1005.0
const RIVER_MAX_Z := 1005.0

## Realm-anchor clearance guard used by the terrain carve and the validation
## test: the carve must stay this far outside any flattened gameplay anchor.
const ANCHOR_CLEARANCE := 3.0

static func river_for(realm: String) -> Dictionary:
	if not SPECS.has(realm):
		return {}
	return (SPECS[realm] as Dictionary).duplicate(true)

static func has_river(realm: String) -> bool:
	return SPECS.has(realm)

static func water_tint(realm: String) -> Color:
	return WATER_TINTS.get(realm, WATER_TINTS["bramblewood"])

static func center_x(spec: Dictionary, z: float) -> float:
	var wavelength := maxf(float(spec.get("wavelen", 120.0)), 1.0)
	var phase := float(spec.get("phase", 0.0))
	var meander := float(spec.get("meander", 0.0))
	var detail := float(spec.get("detail", 0.25))
	var primary := sin(z / wavelength * TAU + phase)
	var secondary := sin(z / (wavelength * 0.37) * TAU + phase * 1.7)
	return float(spec.get("base_x", 0.0)) + meander * primary \
		+ meander * detail * secondary

static func lateral_distance(spec: Dictionary, point: Vector2) -> float:
	return absf(point.x - center_x(spec, point.y))

## Hard channel edge: half the bed width plus the carved bank.
static func carve_reach(spec: Dictionary) -> float:
	return float(spec.get("width", 5.0)) * 0.5 + float(spec.get("bank", 3.0))

## The water plane reaches past the visible waterline so its outer edge is
## buried under the bank instead of hovering above the slope.
static func water_half_width(spec: Dictionary) -> float:
	return carve_reach(spec) + 0.6

## Water sits this far above the carved channel floor, i.e. below the
## untouched banks by `depth * (1.0 - WATER_FRACTION)`.
const WATER_FRACTION := 0.62

static func water_offset(spec: Dictionary) -> float:
	return float(spec.get("depth", 1.0)) * WATER_FRACTION

## World-space bridge centers (XZ) for a realm.
static func bridge_crossings(realm: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var spec := SPECS.get(realm, {}) as Dictionary
	for bridge_value in spec.get("bridges", []):
		var bridge := bridge_value as Dictionary
		var z := float(bridge.get("z", 0.0))
		result.append(Vector2(center_x(spec, z), z))
	return result

static func bridge_labels(realm: String) -> Array[String]:
	var result: Array[String] = []
	var spec := SPECS.get(realm, {}) as Dictionary
	for bridge_value in spec.get("bridges", []):
		result.append(str((bridge_value as Dictionary).get("label", "CROSSING")))
	return result

## Smallest gap between the carved channel edge and any supplied anchor.
## Negative means the channel reaches into the anchor's ground.
static func minimum_anchor_clearance(realm: String, anchors: Array[Vector2]) -> float:
	var spec := river_for(realm)
	if spec.is_empty():
		return INF
	var reach := carve_reach(spec)
	var smallest := INF
	for anchor in anchors:
		smallest = minf(smallest, lateral_distance(spec, anchor) - reach)
	return smallest

## Smallest lateral distance from a river centerline to the world origin over
## the authored core band. Guards the fixed scene anchors (spawn, summon
## points, quest board) that live within ~30 m of the origin.
static func core_center_distance(realm: String, z_min: float = -300.0,
		z_max: float = 300.0) -> float:
	var spec := river_for(realm)
	if spec.is_empty():
		return INF
	var smallest := INF
	var steps := 120
	for i in steps + 1:
		var z := lerpf(z_min, z_max, float(i) / float(steps))
		smallest = minf(smallest, absf(center_x(spec, z)))
	return smallest
