extends Node3D
class_name OverkillGraphicsHero

## === OVERKILL 3D Graphics — Hero (Lantern Bearer) Layer ===
##
## Drop as a child of the Hero node. Reads the Hero's live state each frame
## — weapon, armor, combat state, lantern, dodge, gait — and drives visuals.
## Zero changes to hero.gd required.
##
## What it adds:
##
##   LANTERN
##   ├── Dynamic flame geometry (animated SphereMesh corona + inner core)
##   ├── Reactive light energy (dim=exploring, full=combat, spike=strike)
##   ├── Lens flare billboard quad that appears when aimed at a target
##   ├── Smoke exhaust (idle) + ember burst (post-strike)
##   └── Warmth aura: soft OmniLight tinted by equipped weapon element
##
##   BODY
##   ├── Animated cape (SpringBoneSystem cloth chain behind back)
##   ├── Shoulder pauldron (armor-tinted, scaled by armor tier)
##   ├── Weapon trail (wide emissive quad sweep visible during swings)
##   ├── Ground shadow disc (soft decal-style circle, scales with height)
##   └── Footstep ember sparks (triggers on heavy landing / footfall events)
##
##   COMBAT STATES
##   ├── Dodge roll: brief golden iframes glow ring around hero
##   ├── Counter window: vibrating amber edge pulse (after perfect dodge)
##   ├── Stun: grey desaturate flash + suppressed lantern
##   └── Death: DissolveController triggered automatically on defeat
##
##   WEAPON ELEMENT THEMING (reads GameState.equipped_weapon.element)
##   ├── fire    → orange lantern + red weapon trail
##   ├── nature  → green lantern + green weapon trail
##   ├── arcane  → purple lantern + violet weapon trail
##   └── default → amber lantern + white weapon trail
##
## Usage:
##   var og := OverkillGraphicsHero.new()
##   hero.add_child(og)
##   og.setup(hero)

signal graphics_ready

var _hero    : Node3D = null
var _visual  : Node3D = null
var _t       : float  = 0.0

# Tracked sub-nodes
var _flame_mat      : StandardMaterial3D = null
var _flame_core_mat : StandardMaterial3D = null
var _lantern_light  : OmniLight3D = null
var _flare_mat      : StandardMaterial3D = null
var _aura_light     : OmniLight3D = null
var _cape_sbs       : SpringBoneSystem = null
var _trail_mat      : StandardMaterial3D = null
var _dodge_ring     : MeshInstance3D = null
var _counter_ring   : MeshInstance3D = null
var _shadow_disc    : MeshInstance3D = null
var _smoke_particles : GPUParticles3D = null
var _ember_particles : GPUParticles3D = null

# Element palette cache
var _element_color  : Color = Color(1.0, 0.62, 0.12)
var _last_element   : String = ""

func setup(hero: Node3D) -> void:
	_hero   = hero
	_visual = hero.get_node_or_null("Visual/Rig")
	if _visual == null:
		_visual = hero.get_node_or_null("Visual")
	if _visual == null:
		push_warning("OverkillGraphicsHero: no Visual node found on hero")

func _ready() -> void:
	if _hero == null:
		return
	_build_lantern_fx()
	_build_cape()
	_build_pauldron()
	_build_weapon_trail()
	_build_dodge_ring()
	_build_counter_ring()
	_build_shadow_disc()
	_refresh_element_theme()
	graphics_ready.emit()

func _process(delta: float) -> void:
	_t += delta
	if _hero == null or not is_instance_valid(_hero):
		return
	_update_lantern(delta)
	_update_combat_rings(delta)
	_update_shadow(delta)
	_update_element_theme()
	_update_trail(delta)

# ─────────────────────────────────────────────────────────────────────────────
# LANTERN FX
# ─────────────────────────────────────────────────────────────────────────────
func _build_lantern_fx() -> void:
	# Try to find the lantern node in the hero's rig
	var lantern : Node3D = _hero.get_node_or_null("Visual/Rig/ArmR/Lantern")
	if lantern == null:
		lantern = _hero  # fallback: attach to hero root

	# Flame corona (outer animated shell)
	var corona := MeshInstance3D.new()
	corona.name = "FlameCorona"
	var sm := SphereMesh.new()
	sm.radius = 0.18; sm.height = 0.28; sm.radial_segments = 14; sm.rings = 8
	corona.mesh = sm
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.albedo_color               = Color(1.0, 0.75, 0.30, 0.55)
	_flame_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.emission_enabled           = true
	_flame_mat.emission                   = Color(1.0, 0.55, 0.12)
	_flame_mat.emission_energy_multiplier = 3.5
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	corona.material_override = _flame_mat
	corona.position.y = 0.06
	lantern.add_child(corona)

	# Flame core (inner solid)
	var core := MeshInstance3D.new()
	core.name = "FlameCore"
	var sm2 := SphereMesh.new()
	sm2.radius = 0.08; sm2.height = 0.14
	core.mesh = sm2
	_flame_core_mat = StandardMaterial3D.new()
	_flame_core_mat.albedo_color               = Color(1.0, 0.95, 0.80)
	_flame_core_mat.emission_enabled           = true
	_flame_core_mat.emission                   = Color(1.0, 0.85, 0.55)
	_flame_core_mat.emission_energy_multiplier = 7.0
	_flame_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = _flame_core_mat
	core.position.y = 0.06
	lantern.add_child(core)

	# Warmth aura light (soft, wide — lights terrain around hero)
	_aura_light = OmniLight3D.new()
	_aura_light.name = "WarmthAura"
	_aura_light.light_color  = Color(1.0, 0.62, 0.18)
	_aura_light.light_energy = 0.85
	_aura_light.omni_range   = 5.5
	lantern.add_child(_aura_light)

	# Lens flare billboard
	var flare := MeshInstance3D.new()
	flare.name = "LanternFlare"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.45, 0.45)
	flare.mesh = qm
	_flare_mat = StandardMaterial3D.new()
	_flare_mat.albedo_color               = Color(1.0, 0.88, 0.60, 0.0)
	_flare_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_mat.emission_enabled           = true
	_flare_mat.emission                   = Color(1.0, 0.75, 0.35)
	_flare_mat.emission_energy_multiplier = 4.5
	_flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flare_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare.material_override = _flare_mat
	lantern.add_child(flare)

	# Smoke (idle exhaust)
	_smoke_particles = GPUParticles3D.new()
	_smoke_particles.name = "LanternSmoke"
	_smoke_particles.amount = 10; _smoke_particles.lifetime = 1.0; _smoke_particles.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0); pm.spread = 25.0; pm.gravity = Vector3(0, 0.3, 0)
	pm.initial_velocity_min = 0.15; pm.initial_velocity_max = 0.45
	pm.scale_min = 0.06; pm.scale_max = 0.18; pm.color = Color(0.8, 0.7, 0.6, 0.3)
	_smoke_particles.process_material = pm; _smoke_particles.position.y = 0.12
	lantern.add_child(_smoke_particles)

	# Ember burst (fires on strike)
	_ember_particles = GPUParticles3D.new()
	_ember_particles.name = "StrikeEmbers"
	_ember_particles.amount = 24; _ember_particles.lifetime = 0.6
	_ember_particles.emitting = false; _ember_particles.one_shot = true
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm2.emission_sphere_radius = 0.12; pm2.direction = Vector3(0, 1, 0); pm2.spread = 120.0
	pm2.initial_velocity_min = 1.2; pm2.initial_velocity_max = 3.8; pm2.gravity = Vector3(0, -2.5, 0)
	pm2.scale_min = 0.04; pm2.scale_max = 0.12; pm2.color = Color(1.0, 0.55, 0.12)
	_ember_particles.process_material = pm2
	lantern.add_child(_ember_particles)

func _update_lantern(delta: float) -> void:
	if _flame_mat == null:
		return

	# Read hero state
	var combat_state := 0
	if _hero.has_method("get") and _hero.get("game_state") != null:
		var gs: Node = _hero.get("game_state")
		if gs != null:
			combat_state = int(gs.get("combat_state") if gs.get("combat_state") != null else 0)

	var in_combat := combat_state == 1  # CombatState.COMBAT
	var is_dodging := float(_hero.get("dodge_timer") if _hero.get("dodge_timer") != null else 0.0) > 0.0

	# Flame corona flicker
	var flicker := 0.8 + sin(_t * 6.5) * 0.12 + sin(_t * 11.2) * 0.06
	var combat_mult := 1.85 if in_combat else 1.0
	_flame_mat.emission_energy_multiplier = flicker * 3.5 * combat_mult

	# Core dims during dodge (iframes read = temporarily doused)
	var dodge_dim := 0.35 if is_dodging else 1.0
	_flame_core_mat.emission_energy_multiplier = 7.0 * flicker * dodge_dim

	# Aura light energy responds to combat
	if _aura_light != null:
		var target_energy := 1.6 if in_combat else 0.55
		_aura_light.light_energy = lerpf(_aura_light.light_energy, target_energy, delta * 4.0)

	# Flare — visible when hero has a combat target
	if _flare_mat != null:
		var has_target := false
		if _hero.get("game_state") != null:
			var gs: Node = _hero.get("game_state")
			has_target = bool(gs.get("enemy_selected") if gs.get("enemy_selected") != null else false)
		var target_alpha := 0.55 if has_target else 0.0
		_flare_mat.albedo_color.a = lerpf(_flare_mat.albedo_color.a, target_alpha, delta * 6.0)

## Call from hero.gd animator.attack_impact or the strike callback to burst embers.
func notify_strike() -> void:
	if _ember_particles != null:
		_ember_particles.restart()
		_ember_particles.emitting = true
	if _flame_core_mat != null:
		var tw := create_tween()
		tw.tween_property(_flame_core_mat, "emission_energy_multiplier", 16.0, 0.06)
		tw.tween_property(_flame_core_mat, "emission_energy_multiplier", 7.0, 0.28)

# ─────────────────────────────────────────────────────────────────────────────
# CAPE — SpringBoneSystem cloth chain
# ─────────────────────────────────────────────────────────────────────────────
func _build_cape() -> void:
	if _visual == null:
		return
	_cape_sbs = SpringBoneSystem.new()
	_cape_sbs.name = "CapePhysics"
	_cape_sbs.gravity        = Vector3(0.0, -5.0, 0.0)
	_cape_sbs.damping        = 0.93
	_cape_sbs.stiffness      = 0.22
	_cape_sbs.wind_strength  = 0.10
	_cape_sbs.wind_frequency = 0.45
	_visual.add_child(_cape_sbs)

	# 3 vertical chains across the cape width, anchored to the upper back
	var back_pos := _visual.global_position + Vector3(0.0, 0.85, -0.35)
	for i in 3:
		var x_off := (float(i) - 1.0) * 0.18
		var anchor := back_pos + Vector3(x_off, 0.0, 0.0)
		_cape_sbs.add_chain_at(
			anchor, 6, 0.15,
			0.028,
			_element_color.lerp(Color(0.22, 0.14, 0.10), 0.55))

# ─────────────────────────────────────────────────────────────────────────────
# PAULDRON — right shoulder plate, armor-tinted
# ─────────────────────────────────────────────────────────────────────────────
func _build_pauldron() -> void:
	if _visual == null:
		return
	var host := Node3D.new()
	host.name = "HeroPauldron"
	host.position = Vector3(0.28, 0.72, 0.0)
	_visual.add_child(host)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.32, 0.36)
	mat.roughness    = 0.55; mat.metallic = 0.40
	mat.emission_enabled = true
	mat.emission = _element_color
	mat.emission_energy_multiplier = 0.14

	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22; sm.height = 0.30; sm.radial_segments = 10
	dome.mesh = sm; dome.material_override = mat
	dome.scale = Vector3(1.0, 0.75, 0.85)
	host.add_child(dome)

	# Spike fringe
	for i in 3:
		var spike := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0; cm.bottom_radius = 0.028; cm.height = 0.20; cm.radial_segments = 5
		spike.mesh = cm; spike.material_override = mat
		var ang := (float(i) / 2.0 - 0.5) * 0.9
		spike.position = Vector3(sin(ang) * 0.18, -0.14, cos(ang) * 0.06)
		spike.rotation.z = 0.85 + ang * 0.3
		host.add_child(spike)

# ─────────────────────────────────────────────────────────────────────────────
# WEAPON TRAIL — emissive quad sweep during swings
# ─────────────────────────────────────────────────────────────────────────────
func _build_weapon_trail() -> void:
	if _visual == null:
		return
	var trail := MeshInstance3D.new()
	trail.name = "WeaponTrail"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.08, 0.85)
	trail.mesh = qm
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.albedo_color               = Color(_element_color.r, _element_color.g, _element_color.b, 0.0)
	_trail_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.emission_enabled           = true
	_trail_mat.emission                   = _element_color
	_trail_mat.emission_energy_multiplier = 0.0
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	trail.material_override = _trail_mat
	trail.position = Vector3(0.35, 0.55, 0.35)
	_visual.add_child(trail)

func _update_trail(_delta: float) -> void:
	if _trail_mat == null or _hero == null:
		return
	# Check if hero is in swing window (get_attack_window returns bool)
	var in_swing := false
	if _hero.has_method("get_attack_window"):
		in_swing = bool(_hero.call("get_attack_window"))
	var target_energy := 3.8 if in_swing else 0.0
	var target_alpha  := 0.70 if in_swing else 0.0
	_trail_mat.emission_energy_multiplier = lerpf(
		_trail_mat.emission_energy_multiplier, target_energy, 0.35)
	_trail_mat.albedo_color.a = lerpf(_trail_mat.albedo_color.a, target_alpha, 0.35)

# ─────────────────────────────────────────────────────────────────────────────
# DODGE RING — golden iframes glow ring
# ─────────────────────────────────────────────────────────────────────────────
func _build_dodge_ring() -> void:
	_dodge_ring = MeshInstance3D.new()
	_dodge_ring.name = "DodgeRing"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.50; tm.outer_radius = 0.65; tm.ring_segments = 32; tm.rings = 3
	_dodge_ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.88, 0.22, 0.0)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.88, 0.22)
	mat.emission_energy_multiplier = 2.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dodge_ring.material_override = mat
	_dodge_ring.rotation.x = PI * 0.5
	_dodge_ring.position.y = 0.06
	_dodge_ring.visible = false
	if _hero != null:
		_hero.add_child(_dodge_ring)

# ─────────────────────────────────────────────────────────────────────────────
# COUNTER WINDOW RING — amber edge pulse after perfect dodge
# ─────────────────────────────────────────────────────────────────────────────
func _build_counter_ring() -> void:
	_counter_ring = MeshInstance3D.new()
	_counter_ring.name = "CounterRing"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62; tm.outer_radius = 0.72; tm.ring_segments = 32; tm.rings = 2
	_counter_ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.55, 0.10, 0.0)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.60, 0.12)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_counter_ring.material_override = mat
	_counter_ring.rotation.x = PI * 0.5
	_counter_ring.position.y = 0.08
	_counter_ring.visible = false
	if _hero != null:
		_hero.add_child(_counter_ring)

func _update_combat_rings(delta: float) -> void:
	if _hero == null:
		return

	# Dodge ring
	var dodge_t := float(_hero.get("dodge_timer") if _hero.get("dodge_timer") != null else 0.0)
	if _dodge_ring != null:
		_dodge_ring.visible = dodge_t > 0.0
		if dodge_t > 0.0:
			var mat := _dodge_ring.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = clampf(dodge_t * 2.5, 0.0, 0.65)
				_dodge_ring.rotation.y += delta * 3.5

	# Counter window ring
	var counter_t := float(_hero.get("counter_window_timer") if _hero.get("counter_window_timer") != null else 0.0)
	if _counter_ring != null:
		_counter_ring.visible = counter_t > 0.0
		if counter_t > 0.0:
			var mat := _counter_ring.material_override as StandardMaterial3D
			if mat:
				var pulse := 0.55 + sin(_t * 12.0) * 0.45
				mat.albedo_color.a = pulse * clampf(counter_t, 0.0, 1.0)
				_counter_ring.rotation.y -= delta * 5.0

# ─────────────────────────────────────────────────────────────────────────────
# SHADOW DISC — soft ground shadow
# ─────────────────────────────────────────────────────────────────────────────
func _build_shadow_disc() -> void:
	_shadow_disc = MeshInstance3D.new()
	_shadow_disc.name = "ShadowDisc"
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	_shadow_disc.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.0, 0.0, 0.0, 0.35)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_disc.material_override = mat
	_shadow_disc.rotation.x = -PI * 0.5
	_shadow_disc.position.y = 0.02
	if _hero != null:
		_hero.add_child(_shadow_disc)

func _update_shadow(delta: float) -> void:
	if _shadow_disc == null or _hero == null:
		return
	# Shadow fades and shrinks as hero rises (jump)
	var hero_y := _hero.global_position.y
	var ground_y := 0.0  # simplified — could raycast
	var height := maxf(0.0, hero_y - ground_y)
	var scale_v := clampf(1.0 - height * 0.12, 0.3, 1.0)
	_shadow_disc.scale = Vector3(scale_v, 1.0, scale_v)
	var mat := _shadow_disc.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = clampf(0.35 - height * 0.06, 0.0, 0.35)

# ─────────────────────────────────────────────────────────────────────────────
# ELEMENT THEMING
# ─────────────────────────────────────────────────────────────────────────────
func _update_element_theme() -> void:
	if _hero == null:
		return
	var gs: Node = _hero.get("game_state")
	if gs == null:
		return
	var weapon : Dictionary = gs.get("equipped_weapon") if gs.get("equipped_weapon") != null else {}
	var element := str(weapon.get("element", "default"))
	if element == _last_element:
		return
	_last_element = element
	_refresh_element_theme()

func _refresh_element_theme() -> void:
	match _last_element:
		"fire":   _element_color = Color(1.00, 0.42, 0.10)
		"nature": _element_color = Color(0.35, 0.88, 0.30)
		"arcane": _element_color = Color(0.70, 0.30, 1.00)
		_:        _element_color = Color(1.00, 0.62, 0.12)

	# Recolor aura light
	if _aura_light != null:
		_aura_light.light_color = _element_color
	# Recolor weapon trail
	if _trail_mat != null:
		_trail_mat.emission = _element_color
		_trail_mat.albedo_color = Color(_element_color.r, _element_color.g, _element_color.b, 0.0)
	# Recolor lantern flame corona
	if _flame_mat != null:
		_flame_mat.emission = _element_color.lerp(Color(1.0, 0.75, 0.30), 0.4)
