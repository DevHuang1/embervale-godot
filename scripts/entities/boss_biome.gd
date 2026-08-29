extends BossBase
class_name BiomeBoss

## === Biome Boss (data-driven arena boss) ===
## One script, many bosses: all combat identity comes from a Bestiary
## BOSS_DEFS entry via `def_id`. Phase kit: ring volley -> realm summons
## or rot-heal -> arena-wide eruption storm.

@export var def_id: String = "thornhide_alpha"

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
	arena_radius = 20.0
	super._ready()

	var vis := get_node_or_null("Visual")
	if vis != null:
		var s := float(_def.get("scale", 1.0))
		vis.scale = Vector3(s, s, s)

	_apply_biome_palette()
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

func _perform_special_1(player: Node3D) -> void:
	var sk: Dictionary = _def.get("special_1", {})
	attack_cooldowns["special_1"] = float(sk.get("cooldown", 9.0))
	_ring_volley(player, int(sk.get("damage", 10)))

func _perform_special_2(player: Node3D) -> void:
	var sk: Dictionary = _def.get("special_2", {})
	attack_cooldowns["special_2"] = float(sk.get("cooldown", 15.0))
	match String(sk.get("kind", "summon")):
		"heal":
			_rot_mend(int(sk.get("amount", 14)))
		_:
			_summon_pack(int(sk.get("count", 2)))

func _perform_ultimate(player: Node3D) -> void:
	var sk: Dictionary = _def.get("ultimate", {})
	attack_cooldowns["ultimate"] = float(sk.get("cooldown", 22.0))
	_eruption_storm(int(sk.get("eruptions", 16)), int(sk.get("damage", 20)))

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
func _summon_pack(count: int) -> void:
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
	var scene: PackedScene = load("res://scenes/entities/hushling.tscn")
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

func _spawn_rewards() -> void:
	if is_practice:
		return
	game_state.grant_xp(int(_def.get("rewards", {}).get("xp", 200)))
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
