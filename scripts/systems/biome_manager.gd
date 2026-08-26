extends WorldManager
class_name BiomeManager

## === Biome Manager ===
## Turns a grove-derived scene into one explorable biome: fixed realm
## theming, respawning realm-tier packs, travel gates to sibling biomes,
## and an arena stone that wakes this biome's boss.

@export var biome_id: String = "bramblewood"

var _biome_def: Dictionary = {}
var _gates: Array[Dictionary] = []  # {node, dest}
var _arena_stone: Node3D = null
var _biome_boss: Node3D = null
var _boss_down_at := -1.0
var _traveling := false

func _ready() -> void:
	_biome_def = Bestiary.biome(biome_id)
	if _biome_def.is_empty():
		push_error("BiomeManager: unknown biome_id '%s'" % biome_id)
	super._ready()
	_enter_biome()

## === Identity ===

func _enter_biome() -> void:
	if game_state.current_realm != biome_id:
		game_state.set_current_realm(biome_id)
	_apply_realm_theme(game_state.current_stage)
	var title := str(_biome_def.get("title", biome_id.capitalize()))
	game_state.quest_progress.emit("Now entering %s." % title)
	_build_gates()
	_build_arena()
	_spawn_wave(current_grove_state)
	_start_respawner()

func _realm_tint() -> Color:
	return Bestiary.REALMS.get(biome_id, {}).get("mist_tint", Color(0.65, 0.75, 0.72))

func _fx_tint() -> Color:
	return Bestiary.REALMS.get(biome_id, {}).get("firefly_tint", Color(1.0, 0.86, 0.45))

## === Theming: fixed to this biome, not the quest ladder ===

func _apply_realm_theme(_stage: int) -> void:
	if day_night == null:
		return
	day_night.apply_realm(_realm_tint(), _fx_tint(),
		Bestiary.REALMS.get(biome_id, {}).get("grade", {}))
	var fog_mult := float(_biome_def.get("fog_energy", 1.0))
	if world_environment != null and world_environment.environment != null and fog_mult != 1.0:
		world_environment.environment.fog_density *= fog_mult

## === Packs: realm-tier enemies, respawn while you stay ===

func _spawn_wave(_stage: int) -> void:
	if _biome_def.is_empty():
		return
	_clear_pack()
	_spawn_biome_pack(hero.global_position if hero != null else player_spawn.global_position)

func _start_respawner() -> void:
	var timer := Timer.new()
	timer.name = "PackRespawner"
	timer.wait_time = float(_biome_def.get("respawn_seconds", 17.0))
	timer.autostart = true
	timer.timeout.connect(_on_respawn_tick)
	add_child(timer)

func _on_respawn_tick() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var cap := int(_biome_def.get("pack_cap", 5))
	if get_tree().get_nodes_in_group("enemy").size() >= cap:
		return
	_spawn_biome_pack(hero.global_position)

func _spawn_biome_pack(origin: Vector3) -> void:
	var comp: Dictionary = _biome_def.get("pack", {})
	var hard_count := int(comp.get("hard", 0))
	var normal_count := int(comp.get("normal", 0))
	var total := hard_count + normal_count
	var idx := 0
	for i in hard_count:
		_spawn_pack_enemy(origin, biome_id, true, idx, total)
		idx += 1
	for i in normal_count:
		_spawn_pack_enemy(origin, biome_id, false, idx, total)
		idx += 1

## === Travel gates ===

func _build_gates() -> void:
	var dests: Array = _biome_def.get("gates", [])
	var origin := player_spawn.global_position
	# Deterministic per-biome spread so terrain flattening matches the gates
	var base_angle := float(abs(int(biome_id.hash())) % 628) / 100.0
	for i in dests.size():
		var dest := str(dests[i])
		if not Bestiary.WORLD_REALMS.has(dest):
			continue
		var angle := base_angle + TAU * float(i) / maxf(float(dests.size()), 1.0)
		var pos := origin + Vector3(cos(angle) * 15.0, 0, sin(angle) * 15.0)
		pos.y = 0.1
		_gates.append({"node": _make_monolith(dest, pos), "dest": dest})

func _make_monolith(dest: String, pos: Vector3) -> Node3D:
	var gate := Node3D.new()
	gate.name = "Gate_%s" % dest
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.7, 3.4, 0.5)
	slab.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.12, 0.11)
	mat.emission_enabled = true
	var dest_tint: Color = Bestiary.REALMS.get(dest, {}).get("mist_tint", Color(0.7, 0.8, 0.75))
	mat.emission = dest_tint
	mat.emission_energy_multiplier = 0.55
	slab.material_override = mat
	gate.add_child(slab)
	var label := Label3D.new()
	label.text = str(Bestiary.WORLD_REALMS.get(dest, {}).get("name", dest)).to_upper()
	label.font_size = 96
	label.pixel_size = 0.004
	label.modulate = dest_tint
	label.outline_size = 18
	label.position = Vector3(0, 2.2, 0.3)
	gate.add_child(label)
	var glow := OmniLight3D.new()
	glow.light_color = dest_tint
	glow.light_energy = 0.8
	glow.omni_range = 4.5
	glow.position = Vector3(0, 1.6, 0)
	gate.add_child(glow)
	add_child(gate)
	gate.global_position = pos
	return gate

## === Arena: walk the stone to wake the biome boss ===

func _build_arena() -> void:
	var boss_id := str(_biome_def.get("boss_id", ""))
	if boss_id.is_empty():
		return  # final-boss biome: the Matriarch answers the quest rite only
	_arena_stone = Node3D.new()
	_arena_stone.name = "ArenaStone"
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.72
	cyl.height = 1.5
	pillar.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.10, 0.09)
	mat.emission_enabled = true
	mat.emission = _fx_tint()
	mat.emission_energy_multiplier = 0.7
	pillar.material_override = mat
	_arena_stone.add_child(pillar)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 1.5
	tor.outer_radius = 1.9
	ring.mesh = tor
	ring.material_override = mat
	_arena_stone.add_child(ring)
	ring.position = Vector3(0, 0.08, 0)
	var label := Label3D.new()
	var def := Bestiary.boss_def(boss_id)
	label.text = str(def.get("name", "THE BEAST"))
	label.font_size = 72
	label.pixel_size = 0.004
	label.modulate = _fx_tint()
	label.outline_size = 16
	label.position = Vector3(0, 2.3, 0)
	_arena_stone.add_child(label)
	add_child(_arena_stone)
	_arena_stone.global_position = player_spawn.global_position + Vector3(0, 0.1, -20)

func _engage_arena_boss() -> void:
	var boss_id := str(_biome_def.get("boss_id", ""))
	var def := Bestiary.boss_def(boss_id)
	if def.is_empty() or _arena_stone == null:
		return
	if _biome_boss != null and is_instance_valid(_biome_boss):
		return
	var scene_path := str(def.get("scene", "res://scenes/entities/boss_biome.tscn"))
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("BiomeManager: boss scene missing (%s)" % scene_path)
		return
	_biome_boss = scene.instantiate()
	if "def_id" in _biome_boss:
		_biome_boss.def_id = boss_id
	add_child(_biome_boss)
	_biome_boss.global_position = _arena_stone.global_position + Vector3(0, 0.1, 6)
	# Hide the summoning stone once its lord walks
	_arena_stone.visible = false
	if camera_rig:
		camera_rig.add_shake(0.6)
		camera_rig.play_boss_intro(_biome_boss)
	audio.play_enemy_telegraph()
	game_state.quest_progress.emit(str(def.get("intro", "The arena wakes.")))
	if _biome_boss.has_signal("died"):
		_biome_boss.died.connect(_on_arena_boss_died)

func _on_arena_boss_died() -> void:
	_biome_boss = null
	_boss_down_at = Time.get_ticks_msec() / 1000.0
	game_state.quest_progress.emit("The biome exhales. The stone will wake again if you seek a rematch.")

## === Frame: relic spin + proximity triggers ===
## NOTE: does not chain to WorldManager._process — the base version calls
## set_process(false) whenever no relic trophy exists, which would kill
## gate/arena polling.
func _process(delta: float) -> void:
	if _relic_trophy != null and is_instance_valid(_relic_trophy):
		_relic_trophy.rotate_y(delta * 0.7)
	if _traveling or hero == null or not is_instance_valid(hero):
		return
	var pos := hero.global_position
	# Gates
	for g in _gates:
		var node: Node3D = g.get("node")
		if node == null or not is_instance_valid(node):
			continue
		if pos.distance_to(node.global_position) < 1.9:
			_travel_to(str(g.get("dest")))
			return
	# Arena
	if _arena_stone != null and is_instance_valid(_arena_stone) and _arena_stone.visible \
			and pos.distance_to(_arena_stone.global_position) < 2.4:
		_engage_arena_boss()
		return
	# Rematch: the stone re-rises half a minute after a kill
	if _boss_down_at > 0.0 and Time.get_ticks_msec() / 1000.0 - _boss_down_at > 30.0:
		_boss_down_at = -1.0
		if _arena_stone != null and is_instance_valid(_arena_stone):
			_arena_stone.visible = true

func _travel_to(dest: String) -> void:
	if _traveling:
		return
	var scene_path := Bestiary.biome_scene(dest)
	if scene_path.is_empty():
		return
	_traveling = true
	game_state.set_current_realm(dest)
	get_tree().change_scene_to_file.call_deferred(scene_path)

## === Quest finale stays out of Mistfen ===

func _open_boss_gate() -> void:
	if biome_id == Bestiary.REALM_MISTFEN:
		return  # no throne here for the Bramble Queen
	super._open_boss_gate()
