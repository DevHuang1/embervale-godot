extends BossBase
class_name BiomeBoss

## === Biome Boss (data-driven arena boss) ===
## One script, many bosses: all combat identity comes from a Bestiary
## BOSS_DEFS entry via `def_id`. Phase kit: ring volley -> realm summons
## or rot-heal -> arena-wide eruption storm.

@export var def_id: String = "thornhide_alpha"
## Selects one of the two realm-authored Blender silhouettes.
@export_range(0, 1) var visual_variant: int = 0

var _def: Dictionary = {}
var _summoned: Array[Node3D] = []

func _ready() -> void:
	_def = Bestiary.boss_def(def_id)
	if _def.is_empty():
		push_error("BiomeBoss: unknown def_id '%s'" % def_id)
	# Derived stats must exist before BossBase calculates thresholds and camera
	# framing; otherwise phase timing and arena zoom use base defaults.
	max_hp = int(_def.get("hp", 400))
	hp = max_hp
	base_atk = int(_def.get("atk", 12))
	move_speed = float(_def.get("speed", 4.5))
	diamond_reward = int(_def.get("diamond_reward", 3))
	var model_variants: Array = _def.get("model_variants", [])
	if not model_variants.is_empty():
		var selected := clampi(visual_variant, 0, model_variants.size() - 1)
		authored_model_profile = str(model_variants[selected])
	else:
		authored_model_profile = str(_def.get("model_profile", "boss_matriarch"))

	arena_radius = 20.0

	super._ready()

	var vis := get_node_or_null("Visual")
	if vis != null:
		var s := float(_def.get("scale", 1.0))
		vis.scale = Vector3(s, s, s)

	_apply_biome_palette()
	_build_boss_identity()
	sfx_profile = "ember_glass" if def_id == "cinderhart_colossus" else (
		"grave_moss" if def_id == "moonfen_oracle" else sfx_profile)
	attack_cooldowns["special_1"] = 3.0
	attack_cooldowns["special_2"] = 6.0
	attack_cooldowns["ultimate"] = 10.0
	_refresh_boss_bar()

func _boss_key() -> String:
	return "biome_%s" % def_id

func _apply_biome_palette() -> void:
	var body_mesh := get_node_or_null("Visual/Body") as MeshInstance3D
	if body_mesh == null or not (body_mesh.material_override is ShaderMaterial):
		return
	var palette: Array = _def.get("palette", [])
	var mat: ShaderMaterial = body_mesh.material_override
	if palette.size() >= 1:
		mat.set_shader_parameter("base_color", palette[0])
	if palette.size() >= 2:
		mat.set_shader_parameter("emissive_color", palette[1])

func _setup_attacks() -> void:
	super._setup_attacks()
	_skill_range = SkillRange.new()

var _skill_range: SkillRange = null

func _perform_special_1(player: Node3D) -> void:
	if not _is_skill_in_range(player, 5):
		return
	var sk: Dictionary = _def.get("special_1", {})
	attack_cooldowns["special_1"] = float(sk.get("cooldown", 9.0))
	match String(sk.get("kind", "volley")):
		"fissure":
			_fissure_line(player, int(sk.get("damage", 10)))
		"tide_cross":
			_tide_cross(player, int(sk.get("damage", 10)))
		_:
			_ring_volley(player, int(sk.get("damage", 10)))

func _perform_special_2(player: Node3D) -> void:
	if not _is_skill_in_range(player, 5):
		return
	var sk: Dictionary = _def.get("special_2", {})
	attack_cooldowns["special_2"] = float(sk.get("cooldown", 15.0))
	match String(sk.get("kind", "summon")):
		"heal":
			_rot_mend(int(sk.get("amount", 14)))
		_:
			_summon_pack(int(sk.get("count", 2)), str(sk.get("scene", "")))

func _perform_ultimate(player: Node3D = null) -> void:
	if not _is_skill_in_range(player, 6):
		return
	var sk: Dictionary = _def.get("ultimate", {})
	var rank := stage_rank()
	attack_cooldowns["ultimate"] = maxf(12.0,
		float(sk.get("cooldown", 22.0)) - 3.0 * float(rank))
	var ult_damage := maxi(1, int(round(float(sk.get("damage", 20)) * stage_dmg_mult())))
	if String(sk.get("kind", "storm")) == "spiral":
		_spiral_storm(int(sk.get("eruptions", 16)), ult_damage)
	else:
		_eruption_storm(int(sk.get("eruptions", 16)), ult_damage)

func _is_skill_in_range(player: Node3D, range_tiles: int) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var range_m := float(range_tiles) * 2.0
	return global_position.distance_to(player.global_position) <= range_m

## === Attacks ===

## Twin warning rings close onto the player's position.
func _ring_volley(target: Node3D, damage: int) -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_special()
	else:
		audio.play_profile_cue(sfx_profile, "cast")
	_shake_camera(0.35)
	var tint: Color = _fx_tint()
	for ring in 2:
		var radius := 4.5 + ring * 5.5
		CombatFx.spawn_ring(self, target.global_position, radius,
			Color(tint.r, tint.g, tint.b, 0.55), 1.0 + ring * 0.3)
		for i in 9:
			var angle := (i / 9.0) * TAU
			var pos: Vector3 = target.global_position \
				+ Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			var timer := get_tree().create_timer(0.75 + ring * 0.35, false)
			timer.timeout.connect(_erupt_at.bind(pos, 2.2, damage))

## Realm kin rise from the ground to shield their alpha.
func _summon_pack(count: int, requested_scene := "") -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "vocal")
	_summoned = _summoned.filter(func(h): return is_instance_valid(h))
	var biome_realm := Bestiary.REALM_BRAMBLEWOOD
	for id in Bestiary.BIOMES:
		if str(Bestiary.BIOMES[id].get("boss_id", "")) == def_id:
			biome_realm = id
			break
	var scene_path := requested_scene if not requested_scene.is_empty() \
		else "res://scenes/entities/hushling.tscn"
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return
	for i in count:
		if get_tree().get_nodes_in_group("enemy").size() > 7:
			return
		var minion: Node3D = scene.instantiate()
		get_parent().add_child(minion)
		minion.global_position = global_position \
			+ Vector3(randf_range(-5, 5), 0.2, randf_range(-5, 5))
		minion.call("set_max_hp", 30)
		minion.call("set_base_atk", 4)
		var v := Bestiary.variant_for(biome_realm, "normal")
		if not v.is_empty():
			var md := CharacterModelData.new()
			md.display_name = str(v.get("display", "Hushling"))
			md.model_scale = float(v.get("scale", 1.0)) * 0.9
			md.body_tint = v.get("tint", Color(0, 0, 0, 0))
			md.eye_glow_color = v.get("eye", Color(0, 0, 0, 0))
			md.configure_entity(minion)
		_summoned.append(minion)

## A readable furnace crack advances in fixed steps toward the player. The
## player can dodge across it; no hidden damage exists between telegraphs.
func _fissure_line(target: Node3D, damage: int) -> void:
	var direction := (target.global_position - global_position).normalized()
	direction.y = 0.0
	for i in 7:
		var pos := global_position + direction * (3.0 + float(i) * 2.4)
		var timer := get_tree().create_timer(0.12 * float(i), false)
		timer.timeout.connect(_erupt_at.bind(pos, 1.7, damage, 0.62))

## Four moonlit currents cross at the target. Gaps between nodes remain safe,
## making this a positioning problem rather than a screen-filling lottery.
func _tide_cross(target: Node3D, damage: int) -> void:
	var center := target.global_position
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.FORWARD]
	for axis in axes:
		for offset in range(-4, 5):
			if offset == 0:
				continue
			var pos := center + axis * float(offset) * 2.2
			var delay := 0.08 * float(abs(offset))
			var timer := get_tree().create_timer(delay, false)
			timer.timeout.connect(_erupt_at.bind(pos, 1.25, damage, 0.72))

## Deterministic expanding spiral: visually cinematic while still learnable
## across retries and identical on every quality tier.
func _spiral_storm(eruptions: int, damage: int) -> void:
	var tint := _fx_tint()
	CombatFx.spawn_ring(self, global_position, arena_radius * 0.82,
		Color(tint.r, tint.g, tint.b, 0.45), 1.15)
	for i in eruptions:
		var progress := float(i) / maxf(float(eruptions - 1), 1.0)
		var angle := progress * TAU * 2.5
		var radius := lerpf(3.0, arena_radius * 0.82, progress)
		var pos := global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var timer := get_tree().create_timer(0.06 * float(i), false)
		timer.timeout.connect(_erupt_at.bind(pos, 1.55, damage, 0.65))

## Rot-blooms knit the wounds closed while they hiss.
func _rot_mend(amount: int) -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "telegraph")
	for tick in 3:
		var timer := get_tree().create_timer(0.5 + tick * 0.7, false)
		timer.timeout.connect(_mend_tick.bind(amount))

func _mend_tick(amount: int) -> void:
	if is_defeated or hp >= max_hp:
		return
	hp = mini(hp + amount, max_hp)
	if boss_hp_bar:
		boss_hp_bar.value = hp
	var tint: Color = _fx_tint()
	CombatFx.spawn_burst(self, global_position + Vector3(0, 2.0, 0),
		Color(tint.r, tint.g, tint.b, 0.85), 14, 3.0, 0.6, 0.18)

## Eruptions tear across the whole arena for several seconds.
func _eruption_storm(eruptions: int, damage: int) -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_special()
	else:
		audio.play_profile_cue(sfx_profile, "cast")
	_shake_camera(0.6)
	var tint: Color = _fx_tint()
	for i in eruptions:
		var angle := randf() * TAU
		var r := randf() * arena_radius
		var pos: Vector3 = global_position + Vector3(cos(angle) * r, 0, sin(angle) * r)
		var timer := get_tree().create_timer(randf_range(0.5, 1.6), false)
		timer.timeout.connect(_erupt_at.bind(pos, 3.2, damage))
	var peak := get_tree().create_timer(1.1)
	peak.timeout.connect(func(): _shake_camera(1.1))

const DANGER := Color(1.0, 0.16, 0.08)

## Ground eruption with a red telegraph zone first — damage lands only
## after the warning window, so the hitbox syncs to the visual.
func _erupt_at(pos: Vector3, radius: float, damage: int, warn := 0.5) -> void:
	if is_defeated:
		return
	if warn > 0.0:
		CombatFx.spawn_ground_telegraph(self, pos, radius * 1.1,
			Color(DANGER.r, DANGER.g, DANGER.b), warn)
		CombatFx.spawn_decal(self, pos, radius * 0.8)
		var timer := get_tree().create_timer(warn, false)
		timer.timeout.connect(_erupt_at.bind(pos, radius, damage, 0.0))
		return
	_deal_area_damage(pos, radius, damage)
	var tint: Color = _fx_tint()
	CombatFx.spawn_burst(self, pos + Vector3(0, 0.5, 0),
		Color(tint.r, tint.g, tint.b, 0.8), 12, 5.0, 0.5, 0.15)
	CombatFx.spawn_decal(self, pos, 0.9)

func _fx_tint() -> Color:
	var palette: Array = _def.get("palette", [])
	if palette.size() >= 2 and palette[1] is Color:
		return palette[1]
	return Color(1, 0.45, 0.2)

func _build_boss_identity() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	var tint := _fx_tint()
	var material := StandardMaterial3D.new()
	material.albedo_color = tint.darkened(0.55)
	material.roughness = 0.64
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.75
	match str(_def.get("silhouette", "")):
		"cinder_antlers":
			for side in [-1.0, 1.0]:
				_add_identity_spike(visual, Vector3(0.55 * side, 1.35, 0),
					Vector3(0, 0, -0.62 * side), 1.35, material)
				_add_identity_spike(visual, Vector3(0.9 * side, 1.72, 0),
					Vector3(0, 0, -0.85 * side), 0.85, material)
		"lunar_crown":
			for i in 7:
				var angle := lerpf(-1.1, 1.1, float(i) / 6.0)
				_add_identity_spike(visual, Vector3(sin(angle) * 0.72, 1.5,
					cos(angle) * 0.18), Vector3(0, 0, -angle * 0.4), 0.85, material)
			var halo := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.72
			torus.outer_radius = 0.82
			halo.mesh = torus
			halo.position.y = 1.58
			halo.rotation.x = PI * 0.5
			halo.material_override = material
			visual.add_child(halo)

func _add_identity_spike(parent: Node3D, pos: Vector3, rot: Vector3,
		height: float, material: Material) -> void:
	var spike := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.11
	mesh.height = height
	mesh.radial_segments = 6
	spike.mesh = mesh
	spike.position = pos
	spike.rotation = rot
	spike.material_override = material
	parent.add_child(spike)

func _spawn_rewards() -> void:
	if is_practice:
		return
	game_state.grant_xp(int(_def.get("rewards", {}).get("xp", 200)))
	var materials: Dictionary = _def.get("rewards", {}).get("materials", {})
	for material_id in materials:
		game_state.add_material(str(material_id), int(materials[material_id]))
	var loot: Dictionary = _def.get("rewards", {}).get("loot", {})
	for item_id in loot:
		game_state.add_loot(str(item_id), int(loot[item_id]),
			"%s essence seeps into the satchel." % str(_def.get("name", "The beast")).capitalize())
	var weapon: Dictionary = _def.get("rewards", {}).get("weapon", {})
	if not weapon.is_empty():
		game_state.add_weapon(weapon.duplicate(), false,
			"%s's trophy hums with realm power." % str(_def.get("name", "The beast")))

func die() -> void:
	# Free any remaining minions so the arena doesn't stay haunted
	for h in _summoned:
		if is_instance_valid(h):
			h.queue_free()
	_summoned.clear()
	super.die()
