extends Node

## Headless scene test: entity v3 material pass. Per-clone variation duplication
## stays per-instance, the shared .tres keeps its authored seed, the boss binds
## its secondary stone layer, and gold loot renders as shaded metal.

var failures := 0

func _ready() -> void:
	_run.call_deferred()
	var watchdog := get_tree().create_timer(20.0)
	watchdog.timeout.connect(_on_watchdog)

func _on_watchdog() -> void:
	print("WATCHDOG TIMEOUT")
	get_tree().quit(2)

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _finish() -> void:
	if failures == 0:
		print("ALL ENTITY MATERIAL TESTS PASSED")
	else:
		print("ENTITY MATERIAL TESTS FAILED: ", failures)
	get_tree().quit(failures)

func _run() -> void:
	await get_tree().process_frame

	var root := get_tree().root

	# Shared .tres stays pristine
	var shared: ShaderMaterial = load("res://assets/materials/entity_hushling.tres")
	_check(shared != null, "hushling material missing")
	_check(float(shared.get_shader_parameter("albedo_variation")) > 0.0, "hushling has no clone variation")
	_check(float(shared.get_shader_parameter("variation_seed")) == 0.35, "hushling authored seed changed")
	_check(shared.get_shader_parameter("micro_roughness") != null, "hushling missing micro roughness")

	# Per-instance duplication via EntityAnimator
	var anim := EntityAnimator.new()
	anim.process_mode = Node.PROCESS_MODE_DISABLED
	var visual := Node3D.new()
	visual.name = "Visual"
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = SphereMesh.new()
	mi.material_override = shared
	visual.add_child(mi)
	anim.visual_root = visual
	anim.name = "Animator"
	root.add_child(anim)
	await get_tree().process_frame
	var local: Material = mi.material_override
	_check(local != shared, "body material was not duplicated")
	_check(local is ShaderMaterial, "body material lost its shader")
	var seed0: float = (local as ShaderMaterial).get_shader_parameter("variation_seed")
	_check(seed0 >= 0.0 and seed0 <= 1.0, "variation seed out of range")
	_check(float(shared.get_shader_parameter("variation_seed")) == 0.35, "shared .tres seed mutated by clone")

	# A second clone must roll a different seed against its own material
	var anim2 := EntityAnimator.new()
	anim2.process_mode = Node.PROCESS_MODE_DISABLED
	var visual2 := Node3D.new()
	var mi2 := MeshInstance3D.new()
	mi2.mesh = SphereMesh.new()
	mi2.material_override = shared
	visual2.add_child(mi2)
	anim2.visual_root = visual2
	root.add_child(anim2)
	await get_tree().process_frame
	var local2: Material = mi2.material_override
	var seed1: float = (local2 as ShaderMaterial).get_shader_parameter("variation_seed")
	_check(local2 != local, "two clones share one duplicated material")
	_check(local2 != shared, "second clone not duplicated")
	_check(seed1 != seed0, "two clones rolled the same seed")
	_check(float(shared.get_shader_parameter("variation_seed")) == 0.35, "shared .tres seed mutated after clone 2")

	# Boss stone layer + heart pulse
	var boss: ShaderMaterial = load("res://assets/materials/entity_boss.tres")
	_check(boss != null, "boss material missing")
	var rock: Texture2D = boss.get_shader_parameter("detail_tex")
	_check(rock != null and rock is Texture2D, "boss stone layer unbound")
	_check(float(boss.get_shader_parameter("detail_mix")) > 0.0, "boss stone layer disabled")
	_check(float(boss.get_shader_parameter("emission_pulse_speed")) > 0.0, "boss heart pulse disabled")

	# Eye gloss + pulse
	var eye: ShaderMaterial = load("res://assets/materials/hushling_eye.tres")
	_check(eye != null, "eye material missing")
	_check(float(eye.get_shader_parameter("roughness")) <= 0.25, "eye lens not glossy")
	_check(float(eye.get_shader_parameter("emission_pulse_speed")) > 0.0, "eye pulse disabled")

	# Boss opts out of variation, so it must never be duplicated
	var anim_boss := EntityAnimator.new()
	anim_boss.process_mode = Node.PROCESS_MODE_DISABLED
	var vb := Node3D.new()
	var mb := MeshInstance3D.new()
	mb.mesh = SphereMesh.new()
	mb.material_override = boss
	vb.add_child(mb)
	anim_boss.visual_root = vb
	root.add_child(anim_boss)
	await get_tree().process_frame
	_check(mb.material_override == boss, "boss material was wrongly duplicated")

	# Gold loot reads as shaded metal
	var drop := LootDrop.new()
	drop.configure_gold(5)
	root.add_child(drop)
	await get_tree().process_frame
	var gold: MeshInstance3D = drop.get_node_or_null("GoldCoin") as MeshInstance3D
	_check(gold != null, "gold coin visual missing")
	if gold != null:
		var gm := gold.material_override as StandardMaterial3D
		_check(gm != null, "gold material missing")
		if gm != null:
			_check(gm.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "gold is still unshaded")
			_check(gm.metallic > 0.99, "gold not metallic")

	_finish()

