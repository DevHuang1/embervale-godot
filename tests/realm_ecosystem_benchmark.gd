extends Node

## Dense-forest benchmark. Each case instantiates a realm with a different
## ecosystem density, measures generation time and sampled frame time, then
## verifies that foliage uses MultiMesh batches instead of per-instance nodes.

const CASES := [
    {"name": "baseline", "density": 1.0},
    {"name": "dense", "density": 1.5},
    {"name": "stress", "density": 2.0},
]
const SCENES := [
    {"name": "Grove", "path": "res://scenes/world/grove.tscn"},
    {"name": "Moonfen", "path": "res://scenes/world/moonfen.tscn"},
]
const SAMPLE_FRAMES := 45
const FRAME_BUDGET_MS := 16.67

var _records: Array = []
var _failures: Array[String] = []

func _ready() -> void:
    Engine.time_scale = 1.0
    print("=== Realm Ecosystem Dense-Forest Benchmark ===")
    for scene_spec in SCENES:
        for case_spec in CASES:
            await _run_case(scene_spec, case_spec)
    _write_report()
    print("ECOSYSTEM_BENCHMARK_RESULT=", "PASS" if _failures.is_empty() else "FAIL")
    for failure in _failures:
        print("FAILURE: ", failure)
    get_tree().quit(1 if not _failures.is_empty() else 0)

func _run_case(scene_spec: Dictionary, case_spec: Dictionary) -> void:
    var packed := load(str(scene_spec.path)) as PackedScene
    if packed == null:
        _failures.append("Unable to load " + str(scene_spec.name))
        return
    Engine.time_scale = 1.0
    var start_usec := Time.get_ticks_usec()
    var world := packed.instantiate()
    var dressing := world.get_node_or_null("ForestBorder")
    if dressing != null and "ecosystem_density" in dressing:
        dressing.ecosystem_density = float(case_spec.density)
    add_child(world)
    await _wait_frames(5)
    var generation_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
    var ecosystem: Node = world.get_node_or_null("ForestBorder/RealmEcosystem")
    var batches := 0
    var instances := 0
    var batch_names: Array = []
    var zone_counts: Dictionary = {}
    var populated_zones := 0
    if ecosystem != null:
        for child in ecosystem.get_children():
            if child is MultiMeshInstance3D:
                batches += 1
                var multimesh: MultiMesh = (child as MultiMeshInstance3D).multimesh
                if multimesh != null:
                    instances += multimesh.instance_count
                    batch_names.append(str(child.name))
    else:
        _failures.append("%s/%s missing RealmEcosystem" % [scene_spec.name, case_spec.name])
    if ecosystem != null:
        var raw_zone_points = ecosystem.get("_zone_points")
        if raw_zone_points is Dictionary:
            for zone_name in raw_zone_points:
                var zone_count := (raw_zone_points[zone_name] as Array).size()
                zone_counts[str(zone_name)] = zone_count
                if zone_count > 0:
                    populated_zones += 1
    if populated_zones < 4:
        _failures.append("%s/%s populated too few ecological zones: %d" % [scene_spec.name, case_spec.name, populated_zones])
    if batches < 4:
        _failures.append("%s/%s produced too few MultiMesh batches: %d" % [scene_spec.name, case_spec.name, batches])
    var frame_samples: Array = []
    for _frame in range(SAMPLE_FRAMES):
        var frame_start := Time.get_ticks_usec()
        await get_tree().process_frame
        frame_samples.append(float(Time.get_ticks_usec() - frame_start) / 1000.0)
    var frame_p95 := _percentile(frame_samples, 0.95)
    var frame_max := _max_value(frame_samples)
    var budget_over := 0
    for value in frame_samples:
        if float(value) > FRAME_BUDGET_MS:
            budget_over += 1
    var record := {
        "realm": scene_spec.name,
        "case": case_spec.name,
        "density": case_spec.density,
        "generation_ms": generation_ms,
        "batches": batches,
        "instances": instances,
        "batch_names": batch_names,
        "zone_counts": zone_counts,
        "populated_zones": populated_zones,
        "frame_p95_ms": frame_p95,
        "frame_max_ms": frame_max,
        "budget_over_count": budget_over,
        "sample_frames": SAMPLE_FRAMES,
    }
    _records.append(record)
    print("  ", scene_spec.name, "/", case_spec.name,
        " density=", case_spec.density,
        " generation_ms=", snapped(generation_ms, 0.01),
        " batches=", batches,
        " instances=", instances,
        " zones=", populated_zones,
        " frame_p95_ms=", snapped(frame_p95, 0.01),
        " frame_max_ms=", snapped(frame_max, 0.01),
        " budget_over=", budget_over)
    world.queue_free()
    await _wait_frames(3)
    Engine.time_scale = 1.0

func _percentile(values: Array, percentile: float) -> float:
    if values.is_empty():
        return 0.0
    var sorted: Array = values.duplicate()
    sorted.sort()
    var index := int(round(float(sorted.size() - 1) * percentile))
    return float(sorted[clampi(index, 0, sorted.size() - 1)])

func _max_value(values: Array) -> float:
    var result := 0.0
    for value in values:
        result = maxf(result, float(value))
    return result

func _wait_frames(count: int) -> void:
    for _i in range(count):
        await get_tree().process_frame

func _write_report() -> void:
    var report := {"frame_budget_ms": FRAME_BUDGET_MS, "records": _records, "failures": _failures}
    var file := FileAccess.open("user://realm_ecosystem_benchmark.json", FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(report, "\t"))
        file.close()
    print("ECOSYSTEM_REPORT_PATH=user://realm_ecosystem_benchmark.json")
