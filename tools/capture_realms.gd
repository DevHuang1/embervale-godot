extends SceneTree

## Visual-pass capture harness (run with a REAL window, not --headless):
##   godot --path . --script tools/capture_realms.gd -- --tier high --out .captures
## Loads each realm scene (autoloads initialize correctly), snaps a fixed
## third-person overlook, then replays representative light / heavy /
## elemental / boss-telegraph FX sequences and snaps each. Same fixed camera
## per realm across LOW/MEDIUM/HIGH so screenshots stay comparable.
##
## Output dir defaults to user://captures; pass --out <path> for a local dir.

const REALMS := [
	["bramblewood", "res://scenes/world/grove.tscn"],
	["whispergrove", "res://scenes/world/grove.tscn"],
	["mistfen", "res://scenes/world/mistfen.tscn"],
	["heartwood", "res://scenes/world/heartwood.tscn"],
	["moonfen", "res://scenes/world/moonfen.tscn"],
]

const FX_SPOTS := [
	Vector3(0, 0.1, -4),
	Vector3(2.5, 0.1, -6),
	Vector3(-2.5, 0.1, -6),
]

var _tier := "high"
var _out := "user://captures"
var _sequence: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		match args[i]:
			"--tier":
				_tier = args[i + 1]
			"--out":
				_out = args[i + 1]
	_run.call_deferred()


func _frame() -> void:
	await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(file_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("SKIP(no image): ", file_name)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var path := "%s/%s_%s.png" % [_out, _tier, file_name]
	var err := img.save_png(path)
	print("SNAP ", path, " err=", err, " ", img.get_size())


## Pull the first active camera out to a fixed overlook so every realm is
## framed identically regardless of its authored camera rig.
func _frame_camera(scene: Node) -> void:
	var cam := get_viewport_camera_for_scene(scene)
	if cam == null:
		return
	cam.global_position = Vector3(0, 6.2, 10)
	cam.rotation_degrees = Vector3(-52, 0, 0)
	cam.current = true


func get_viewport_camera_for_scene(scene: Node) -> Camera3D:
	for c in scene.find_children("*", "Camera3D", true, false):
		var cam := c as Camera3D
		if cam.is_inside_tree() and cam.is_current():
			return cam
	for c in scene.find_children("*", "Camera3D", true, false):
		return c as Camera3D
	return null


func _ensure_tier() -> void:
	var ws := root.get_node_or_null("/root/WorldState")
	if ws == null:
		return
	var qs := ws.get_node_or_null("QualityScaler") as QualityScaler
	if qs == null:
		return
	match _tier:
		"low":
			qs.set_mode(QualityScaler.Mode.LOW)
		"medium":
			qs._apply_level(QualityScaler.Level.MEDIUM)
		_:
			qs.set_mode(QualityScaler.Mode.HIGH)


func _run() -> void:
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	_ensure_tier()

	# --- Realm identity captures ---
	for entry in REALMS:
		var realm: String = entry[0]
		var scene_path: String = entry[1]
		gs.set_current_realm(realm)
		var scene: Node = (load(scene_path) as PackedScene).instantiate()
		root.add_child(scene)
		_frames(40)
		_frame_camera(scene)
		_frames(6)
		_snap("realm_%s" % realm)
		scene.queue_free()
		await _frame()

	# --- Combat FX captures on the grove stage ---
	var stage: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(stage)
	_frames(40)
	_frame_camera(stage)
	_frames(4)

	var host := Node3D.new()
	host.name = "CaptureFxHost"
	stage.add_child(host)
	var light_pos := FX_SPOTS[1]

	CombatFx.spawn_telegraph(host, FX_SPOTS[0], Color(1.0, 0.84, 0.47))
	CombatFx.spawn_arc_trail(host, light_pos, Color(1.0, 0.92, 0.7))
	CombatFx.spawn_burst(host, light_pos, Color(1.0, 0.84, 0.47), 24, 6.0, 0.4)
	_frames(3)
	_snap("fx_light")

	await _frame()
	CombatFx.spawn_core_flash(host, light_pos, Color(1.0, 0.97, 0.90), 2.2)
	CombatFx.spawn_shockwave(host, light_pos, 4.0, Color(1.0, 0.84, 0.47, 0.9), 0.5)
	CombatFx.spawn_impact_light(host, light_pos, Color(1.0, 0.8, 0.5), 3.0, 5.0, 0.3)
	CombatFx.spawn_stretched_burst(host, light_pos,
		Color(1.0, 0.5, 0.2), 18, 9.0, 0.35)
	_frames(3)
	_snap("fx_heavy")

	await _frame()
	CombatFx.spawn_ground_telegraph(host, FX_SPOTS[2], 2.4,
		Color(1.0, 0.16, 0.08), 0.8)
	CombatFx.spawn_telegraph(host, FX_SPOTS[2], Color(1.0, 0.32, 0.18), true)
	CombatFx.spawn_ring(host, FX_SPOTS[2], 3.2, Color(1.0, 0.45, 0.2, 0.7), 0.8)
	_frames(3)
	_snap("fx_telegraph")

	await _frame()
	ImpactDirector.apply_element(host, "frost", FX_SPOTS[0], 1.8)
	ImpactDirector.apply_element(host, "nature", FX_SPOTS[1], 1.8)
	_frames(3)
	_snap("fx_elemental")

	await _frame()
	CombatFx.spawn_status_reaction(host, "VAPORIZE", Color(0.8, 0.9, 1.0))
	_frames(3)
	_snap("fx_reaction")

	stage.queue_free()
	await _frame()
	print("CAPTURE REALMS: done (tier=%s out=%s)" % [_tier, _out])
	quit(0)