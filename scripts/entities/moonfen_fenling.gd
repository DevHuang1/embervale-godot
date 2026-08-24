extends Hushling

class_name MoonfenFenling

var mire_phase := false
var _phase_flash_timer := 0.0

func _ready() -> void:
	thorn_volley = true
	sfx_profile = "grave_moss"
	burst_radius = 4.4
	burst_damage = 8
	burst_cooldown = 4.0
	orbit_distance = 5.8
	lunge_speed = 23.0
	feint_speed = 14.5
	super._ready()
	_build_fen_flags()

func _physics_process(delta: float) -> void:
	if not mire_phase and hp > 0 and hp <= int(max_hp * 0.5):
		_enter_mire_phase()
	_phase_flash_timer = maxf(0.0, _phase_flash_timer - delta)
	super._physics_process(delta)

## The fen variant wears the bat rig — a winged mire-sprite.
func _rig_profile() -> String:
	return "fenling"

func _enter_mire_phase() -> void:
	mire_phase = true
	move_speed *= 1.20
	orbit_speed *= 1.28
	lunge_speed *= 1.18
	burst_cooldown = maxf(2.8, burst_cooldown * 0.72)
	burst_radius += 0.5
	_phase_flash_timer = 0.8
	_modulate_eyes(Color(0.35, 0.85, 1.0))
	audio.play_profile_cue("grave_moss", "vocal")
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.45, 0),
		Color(0.25, 0.78, 1.0, 0.9), 24, 5.0, 0.55, 0.16)
	game_state.quest_progress.emit("A Fenling tears open the mire phase — its thorns move with the tide.")

func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	if mire_phase:
		var pulse := 0.75 + 0.25 * sin(bob_timer * 4.2)
		for eye in eyes.get_children():
			if eye.material_override:
				eye.material_override.set_shader_parameter("glow_intensity", pulse + 0.35)

## Fenling signature: pale membrane fins fanning off the flanks + tail
## blades, so the moon-territory sprite reads instantly as its own thing.
func _build_fen_flags() -> void:
	if visual == null:
		return
	var membrane := StandardMaterial3D.new()
	membrane.albedo_color = Color(0.02, 0.52, 0.68, 0.88)
	membrane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	membrane.roughness = 0.55
	membrane.emission_enabled = true
	membrane.emission = Color(0.0, 0.62, 0.85)
	membrane.emission_energy_multiplier = 0.5
	var fin := PrismMesh.new()
	fin.left_to_right = 0.55
	fin.size = Vector3(0.52, 0.16, 0.5)
	fin.material = membrane
	var tail := CylinderMesh.new()
	tail.top_radius = 0.0
	tail.bottom_radius = 0.05
	tail.height = 0.3
	tail.radial_segments = 4
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		wing.name = "FinWing"
		wing.mesh = fin
		wing.material_override = membrane
		wing.position = Vector3(0.36 * side, 0.22, 0.05)
		wing.rotation = Vector3(0, 0.25 * side, -0.55 * side)
		wing.scale = Vector3(0.8 + 0.2 * side, 1.0, 1.0)
		visual.add_child(wing)
		var blade := MeshInstance3D.new()
		blade.name = "FinBlade"
		blade.mesh = tail
		blade.material_override = membrane
		blade.position = Vector3(0.62 * side, 0.1, -0.18)
		blade.rotation = Vector3(-0.7, 0, -0.6 * side)
		visual.add_child(blade)
