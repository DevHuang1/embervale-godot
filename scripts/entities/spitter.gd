extends Hushling
class_name Spitter

## === Spitter / Venom Caster ===
## A ranged kin of the hushling that keeps its standoff and lobs an arcing
## venom glob at the hero instead of closing to melee. Distinct venom-gland
## + fang silhouette, its own SFX profile, and a two-stage (telegraph -> lob
## -> splash) projectile read so the hit is fair and readable.

func _rig_profile() -> String:
	return "spitter"

func _ready() -> void:
	# Ranged profile: hold standoff, reposition instead of lunging in.
	orbit_distance = 8.5
	lunge_speed = 5.6
	feint_speed = 4.8
	orbit_speed = 2.8
	recover_speed = 3.6
	burst_cooldown = 4.2
	burst_damage = 7
	sfx_profile = "venom_spit"
	super._ready()
	_build_spitter_details()

## Distinct fangs + a rear venom gland so the ranged type reads at a glance,
## even under the procedural-fallback silhouette.
func _build_spitter_details() -> void:
	if visual == null:
		return
	var gland_mat := StandardMaterial3D.new()
	gland_mat.albedo_color = Color(0.36, 0.9, 0.42)
	gland_mat.emission_enabled = true
	gland_mat.emission = Color(0.30, 1.0, 0.35)
	gland_mat.emission_energy_multiplier = 3.0
	var gland := MeshInstance3D.new()
	gland.name = "VenomGland"
	var gs := SphereMesh.new()
	gs.radius = 0.16
	gs.height = 0.32
	gland.mesh = gs
	gland.material_override = gland_mat
	gland.position = Vector3(0, 0.0, -0.52)
	visual.add_child(gland)

	var fang_mat := StandardMaterial3D.new()
	fang_mat.albedo_color = Color(0.9, 0.95, 0.85)
	fang_mat.roughness = 0.3
	var fang := CylinderMesh.new()
	fang.top_radius = 0.0
	fang.bottom_radius = 0.05
	fang.height = 0.3
	fang.radial_segments = 5
	for side in [-1.0, 1.0]:
		var f := MeshInstance3D.new()
		f.name = "Fang"
		f.mesh = fang
		f.material_override = fang_mat
		f.position = Vector3(0.22 * side, 0.3, 0.5)
		f.rotation.x = 0.3
		f.rotation.z = -0.5 * side
		visual.add_child(f)

## Override the hushling's ground-eruption with a telegraphed venom lob.
func _perform_bramble_burst(player: Node3D) -> void:
	if not burst_active:
		return
	burst_active = false
	burst_timer = burst_cooldown
	_modulate_eyes(Color(0.36, 1.0, 0.42))
	if sfx_profile == "venom_spit":
		audio.play_synth_at(self, "venom_lob", 0.0)
	else:
		audio.play_enemy_special()
	var target_pos: Vector3 = player.global_position + Vector3(0, 0.7, 0)
	CombatFx.spawn_ground_telegraph(self,
		Vector3(target_pos.x, 0, target_pos.z), 1.6,
		Color(0.36, 0.9, 0.42), 0.5)
	_spawn_burst_fx(Color(0.36, 0.9, 0.42, 0.5), 0.5, 14)
	var timer := get_tree().create_timer(0.55, false)
	timer.timeout.connect(_lob_venom.bind(player, target_pos))

func _lob_venom(player: Node3D, target_pos: Vector3) -> void:
	if is_defeated or player == null or not is_instance_valid(player):
		return
	CombatFx.spawn_bolt(self, global_position + Vector3(0, 1.1, 0.4),
		target_pos, Color(0.36, 1.0, 0.42), 0.42, 0.55)
	var impact := get_tree().create_timer(0.42, false)
	impact.timeout.connect(_venom_impact.bind(player, target_pos))

func _venom_impact(player: Node3D, pos: Vector3) -> void:
	if is_defeated or player == null or not is_instance_valid(player):
		return
	CombatFx.spawn_burst(self, pos, Color(0.36, 1.0, 0.42, 0.9),
		20, 4.5, 0.4, 0.2)
	CombatFx.spawn_explosion(self, pos, Color(0.30, 0.9, 0.30), 1.8)
	CombatFx.spawn_decal(self, pos, 1.1)
	if sfx_profile == "venom_spit":
		audio.play_synth_at(self, "venom_hit", 0.0)
	if pos.distance_to(player.global_position) <= 1.8:
		if player.has_method("is_airborne") and player.is_airborne():
			return
		if player.has_method("take_damage"):
			player.take_damage(burst_damage,
				pos.direction_to(player.global_position))
