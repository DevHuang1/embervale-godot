extends Node
class_name RealmExpansion

## === RealmExpansion — Realm Progression Unlock System ===
## Instantiated by world_manager._ready():
##   _realm_expansion = preload("res://scripts/world/realm_expansion.gd").new()
##   _realm_expansion.name = "RealmExpansion"
##   add_child(_realm_expansion)
##   _realm_expansion.setup(self)
##
## Responsibilities:
##   - Gate unlocks: show MoonfenGate when Bramblewood boss is defeated
##   - Show ReturnGate back to previous realm
##   - Handle gate interaction → GameState.realm_changed signal
##   - Altar placement for boss practice respawns
##   - Relic trophy pedestal update after forge

signal gate_opened(target_realm: String)
signal gate_closed
signal altar_placed(altar: Node3D)

var _world : Node3D = null

func setup(world_manager: Node3D) -> void:
	_world = world_manager
	_connect_signals()
	_sync_gates()

func _ready() -> void:
	pass  # setup() is called explicitly by world_manager

# ─────────────────────────────────────────────────────────────────────────────
# Gate management
# ─────────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	if gs.has_signal("stage_changed"):
		gs.stage_changed.connect(_on_stage_changed)
	if gs.has_signal("victory"):
		gs.victory.connect(_on_victory)
	if gs.has_signal("realm_changed"):
		gs.realm_changed.connect(_on_realm_changed)

func _sync_gates() -> void:
	if _world == null:
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var stage := int(gs.get("current_stage") if gs.get("current_stage") != null else 0)
	# MoonfenGate opens after COMPLETE (stage 3)
	_set_gate_visible("MoonfenGate",  stage >= 3)
	_set_gate_visible("ReturnGate",   stage >= 1)

func _set_gate_visible(gate_name: String, visible: bool) -> void:
	if _world == null:
		return
	var gate := _world.get_node_or_null(gate_name)
	if gate != null:
		gate.visible = visible
		# Enable/disable collision too
		for child in gate.get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D:
				child.disabled = not visible

func _on_stage_changed(stage: int) -> void:
	_sync_gates()
	if stage >= 3:
		# Spawn a practice altar near the last boss spawn area
		_try_place_practice_altar()

func _on_victory() -> void:
	# Flash the MoonfenGate portal open if stage just completed
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var stage := int(gs.get("current_stage") if gs.get("current_stage") != null else 0)
	if stage >= 3:
		_open_gate_fx("MoonfenGate")

func _on_realm_changed(realm_id: String) -> void:
	# Show ReturnGate in new realm if we came from somewhere
	_set_gate_visible("ReturnGate", true)

# ─────────────────────────────────────────────────────────────────────────────
# Practice altar
# ─────────────────────────────────────────────────────────────────────────────

func _try_place_practice_altar() -> void:
	if _world == null:
		return
	if _world.get("_practice_altar") != null and \
			is_instance_valid(_world.get("_practice_altar")):
		return  # already placed

	# Simple procedural altar: a stone plinth
	var altar := Node3D.new()
	altar.name = "PracticeAltar"
	var plinth := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.55, 0.8)
	plinth.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.18, 0.16)
	mat.roughness    = 0.88
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.18, 0.06)
	mat.emission_energy_multiplier = 0.35
	plinth.material_override = mat
	altar.add_child(plinth)

	# Altar label
	var label := Label3D.new()
	label.text     = "PRACTICE ARENA"
	label.font_size = 48
	label.modulate  = Color(1.0, 0.85, 0.45)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position  = Vector3(0, 0.55, 0)
	altar.add_child(label)

	# Place near hero spawn + offset
	var spawn : Marker3D = _world.get_node_or_null("PlayerSpawn")
	altar.global_position = (spawn.global_position if spawn != null else Vector3.ZERO) \
		+ Vector3(4.0, 0, 0)
	_world.add_child(altar)
	if _world.get("_practice_altar") != null:
		_world.set("_practice_altar", altar)
	altar_placed.emit(altar)

# ─────────────────────────────────────────────────────────────────────────────
# Gate FX
# ─────────────────────────────────────────────────────────────────────────────

func _open_gate_fx(gate_name: String) -> void:
	if _world == null:
		return
	var gate := _world.get_node_or_null(gate_name)
	if gate == null:
		return
	gate.visible = true
	# Spawn portal burst
	CombatFx.spawn_ring(_world, gate.global_position, 1.8,
		Color(0.42, 0.72, 0.50, 0.8), 0.85)
	CombatFx.spawn_burst(_world, gate.global_position + Vector3(0, 1.2, 0),
		Color(0.32, 1.0, 0.55, 0.9), 18, 4.5, 0.55, 0.16)
	gate_opened.emit(gate_name.to_lower().replace("gate", ""))
