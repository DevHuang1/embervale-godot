extends SceneTree

## Headless authored-asset contract for the Blender realm boss variants.
## Phase 1: every exported boss-variant GLB passes the mounted-rig contract —
##   import precedence over the FBX fallback, hidden procedural body, mobile
##   LOD visibility ranges, RealmMask vertex colors, sockets, the shared clip
##   set, and gameplay cue resolution through AnimTreeBridge.
## Phase 2: each realm's boss boots through the real selection path
##   (Bestiary.model_variants -> boss_biome / boss_matriarch -> rig loader)
##   and actually mounts its authored silhouettes for visual_variant 0 and 1.
## Profiles are enumerated from Bestiary.BOSS_DEFS so this test cannot drift
## from the runtime source of truth.

const BOSS_BIOME_SCENE := "res://scenes/entities/boss_biome.tscn"
const MATRIARCH_SCENE := "res://scenes/entities/boss_matriarch.tscn"
const CLIP_TOKENS := ["idle", "attack1_slam", "cast_rootprison", "buff_phase",
	"hit_heavy", "death_forward"]
const SOCKET_NAMES := ["SOCKET_Hand_R", "SOCKET_Hand_L", "SOCKET_VFX_Chest",
	"SOCKET_VFX_Foot_L", "SOCKET_VFX_Foot_R"]
const BRIDGE_CUES := ["idle", "light_1", "cast", "buff", "hit", "death"]

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(120.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — boss variant test hung")
		quit(2))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		print("FAILURE: ", message)


func _run() -> void:
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	# --- Phase 1: mounted-rig contract for every authored variant profile ---
	var profiles: Array[String] = []
	for def_id in Bestiary.BOSS_DEFS:
		for v in Bestiary.BOSS_DEFS[def_id].get("model_variants", []):
			if not profiles.has(str(v)):
				profiles.append(str(v))
	_check(profiles.size() == 10,
		"Bestiary exposes ten authored boss variant profiles (got %d)" % profiles.size())

	for profile in profiles:
		await _check_profile_contract(profile)

	# --- Phase 2: realm bosses boot and select their authored silhouettes ---
	var audio := root.get_node("/root/AudioManager")
	var boots := 0
	for def_id in Bestiary.BOSS_DEFS:
		var def: Dictionary = Bestiary.BOSS_DEFS[def_id]
		var variants: Array = def.get("model_variants", [])
		if variants.is_empty():
			continue
		var scene_path := str(def.get("scene", MATRIARCH_SCENE))
		for i in variants.size():
			var expected := str(variants[i])
			var boss := (load(scene_path) as PackedScene).instantiate()
			if scene_path == MATRIARCH_SCENE:
				# The grove override picks a grove silhouette from
				# authored_visual_variant when the realm is whispergrove.
				boss.is_practice = true
				gs.set_current_realm("whispergrove")
				boss.authored_visual_variant = i
			else:
				boss.def_id = def_id
				boss.visual_variant = i
			root.add_child(boss)
			for f in 3:
				await process_frame
			boots += 1
			_check(str(boss.authored_model_profile) == expected,
				"%s boot (variant %d) selects authored profile %s"
					% [def_id, i, expected])
			var rig := boss.find_child("AuthoredRig", true, false)
			_check(rig != null,
				"%s variant %d mounts its authored rig" % [def_id, i])
			if rig != null:
				var body := boss.get_node_or_null("Visual/Body") as MeshInstance3D
				_check(body != null and not body.visible,
					"%s variant %d hides the procedural silhouette" % [def_id, i])
				_check(rig.find_child("AnimBridge", true, false) != null,
					"%s variant %d bridges its authored clips" % [def_id, i])
			boss.queue_free()
			if audio != null:
				audio.stop_all_playback()
			await process_frame

	if audio != null:
		audio.stop_all_playback()
	for f in 3:
		await process_frame

	if failures == 0:
		print("ALL BOSS VARIANT ASSET TESTS PASSED (profiles=%d boots=%d checks=%d)"
			% [profiles.size(), boots, checks])
	else:
		print("%d BOSS VARIANT ASSET FAILURES (profiles=%d boots=%d checks=%d)"
			% [failures, profiles.size(), boots, checks])
	quit(0 if failures == 0 else 1)


## Mount the profile's GLB on a synthetic entity and assert the full
## authored-rig contract documented in docs/BLENDER_PIPELINE.md.
func _check_profile_contract(profile: String) -> void:
	var expected := "res://assets/models/boss_variants/%s.glb" % profile
	_check(CharacterRigLoader._any_model(profile) == expected,
		"%s resolves to its validated boss_variants GLB" % profile)

	var entity := Node3D.new()
	var visual := Node3D.new()
	visual.name = "Visual"
	entity.add_child(visual)
	var body := MeshInstance3D.new()
	body.name = "Body"
	visual.add_child(body)
	root.add_child(entity)

	var wired := CharacterRigLoader.try_if_wire(entity, profile)
	_check(wired, "%s GLB mounts through CharacterRigLoader" % profile)
	var rig := entity.find_child("AuthoredRig", true, false) as Node3D
	_check(rig != null, "%s exposes an AuthoredRig" % profile)
	if rig == null:
		entity.queue_free()
		await process_frame
		return

	_check(body != null and not body.visible,
		"%s hides the procedural body" % profile)

	# Mobile LOD contract: three progressive silhouettes, near/mid/far ranges.
	var lod_counts := {0: 0, 1: 0, 2: 0}
	var ranges_ok := {0: true, 1: true, 2: true}
	var mask_meshes := 0
	for cand in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := cand as MeshInstance3D
		var mesh_name := str(mesh.name).to_upper()
		if mesh_name.ends_with("_LOD0"):
			lod_counts[0] += 1
			ranges_ok[0] = bool(ranges_ok[0]) \
				and is_equal_approx(mesh.visibility_range_end, 20.0)
		elif mesh_name.ends_with("_LOD1"):
			lod_counts[1] += 1
			ranges_ok[1] = bool(ranges_ok[1]) \
				and is_equal_approx(mesh.visibility_range_begin, 18.0) \
				and is_equal_approx(mesh.visibility_range_end, 36.0)
		elif mesh_name.ends_with("_LOD2"):
			lod_counts[2] += 1
			ranges_ok[2] = bool(ranges_ok[2]) \
				and is_equal_approx(mesh.visibility_range_begin, 34.0) \
				and is_zero_approx(mesh.visibility_range_end)
		if mesh.mesh != null and mesh.mesh.get_surface_count() > 0 \
				and (mesh.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0:
			mask_meshes += 1
	_check(lod_counts[0] > lod_counts[1] and lod_counts[1] > lod_counts[2] \
			and lod_counts[2] > 0,
		"%s keeps three progressive LOD silhouettes" % profile)
	_check(bool(ranges_ok[0]) and bool(ranges_ok[1]) and bool(ranges_ok[2]),
		"%s LOD pieces use the mobile visibility ranges" % profile)
	_check(mask_meshes > 0,
		"%s retains the Blender RealmMask vertex colors" % profile)

	for socket_name in SOCKET_NAMES:
		_check(rig.find_child(socket_name, true, false) != null,
			"%s exposes %s" % [profile, socket_name])

	var players := rig.find_children("*", "AnimationPlayer", true, false)
	_check(not players.is_empty(), "%s imports an AnimationPlayer" % profile)
	if not players.is_empty():
		var names := " ".join(Array(
			(players[0] as AnimationPlayer).get_animation_list())).to_lower()
		for token in CLIP_TOKENS:
			_check(names.contains(token),
				"%s clip set includes %s" % [profile, token])

	var bridge := rig.find_child("AnimBridge", true, false)
	_check(bridge != null, "%s bridges its authored clips" % profile)
	if bridge != null:
		for cue in BRIDGE_CUES:
			_check(bridge.has_cue(cue),
				"%s bridge resolves cue %s" % [profile, cue])

	entity.queue_free()
	await process_frame
