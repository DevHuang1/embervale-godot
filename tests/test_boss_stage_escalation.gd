extends Node

## Headless validation for boss stage escalation:
## per-stage armor/damage scaling, capped mend ability, stage-scaled ultimate,
## per-stage visual evolution (tint + silhouette), and encounter reset.
## Run: godot --headless --path . res://tests/test_boss_stage_escalation.tscn

var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _build_boss() -> Node:
	var boss: Node = (load("res://scenes/entities/boss_biome.tscn") as PackedScene).instantiate()
	boss.def_id = "thornhide_alpha"
	get_tree().root.add_child(boss)
	return boss

func _build_plain_boss() -> Node:
	var boss := CharacterBody3D.new()
	boss.set_script(load("res://scripts/entities/boss_base.gd"))
	var visual := Node3D.new()
	visual.name = "Visual"
	var body := MeshInstance3D.new()
	body.name = "Body"
	var sh := Shader.new()
	sh.code = ("shader_type spatial;\n"
		+ "uniform float flash_intensity = 0.0;\n"
		+ "uniform float hp_wear = 0.0;\n"
		+ "uniform vec3 emissive_color = vec3(1.0, 0.5, 0.2);\n"
		+ "uniform vec3 base_color = vec3(0.3, 0.2, 0.15);\n")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	body.material_override = mat
	visual.add_child(body)
	boss.add_child(visual)
	var animator := Node3D.new()
	animator.name = "Animator"
	animator.set_script(load("res://scripts/entities/entity_animator.gd"))
	boss.add_child(animator)
	var hitbox := Area3D.new()
	hitbox.name = "Hitbox"
	boss.add_child(hitbox)
	boss.add_child(_named("AttackAreas"))
	get_tree().root.add_child(boss)
	return boss

func _named(n: String) -> Node3D:
	var v := Node3D.new()
	v.name = n
	return v

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		failures += 1
		print("FAIL: ", msg)

func _run() -> void:
	var boss: Node = _build_boss()
	var plain: Node = _build_plain_boss()
	await get_tree().process_frame
	await get_tree().process_frame

	# --- Stage helpers scale per phase ---
	_check(boss.effective_atk() == 12, "stage 1 damage is base (12)")
	boss.current_phase = 3  # BossPhase.ENRAGE
	_check(boss.effective_atk() == 18, "enrage damage mult applied (12 * 1.5)")
	_check(boss.stage_armor_value() == 8, "enrage armor is 8")
	var mults: Array = boss.stage_damage_mult
	var mono := true
	for i in range(1, mults.size()):
		mono = mono and float(mults[i]) > float(mults[i - 1])
	_check(mono, "damage mult strictly increases with stage")

	# --- Stage armor reduces incoming damage (min 1 gets through) ---
	boss.current_phase = 3
	boss.hp = boss.max_hp
	boss.take_damage(50, Vector3.FORWARD)
	_check(boss.hp == boss.max_hp - 42, "armor reduced 50 dmg to 42 at enrage")
	boss.current_phase = 0  # BossPhase.PHASE_1
	boss.hp = boss.max_hp
	boss.take_damage(50, Vector3.FORWARD)
	_check(boss.hp == boss.max_hp - 50, "stage 1 armor is 0 (full damage)")

	# --- Biome ultimate: data-driven, sharpened by stage ---
	boss.current_phase = 2  # BossPhase.PHASE_3
	boss._perform_ultimate()
	var cd3: float = float(boss.attack_cooldowns["ultimate"])
	boss.current_phase = 3
	boss._perform_ultimate()
	var cdE: float = float(boss.attack_cooldowns["ultimate"])
	_check(cdE < cd3, "enrage ultimate recasts faster (%.1f < %.1f)" % [cdE, cd3])
	var def_ult: Dictionary = boss._def.get("ultimate", {})
	_check(int(round(float(def_ult.get("damage", 20)) * boss.stage_dmg_mult()))
			== 30, "biome ultimate damage scales with stage (20 -> 30)")

	# --- Base ultimate: telegraph radius grows with stage ---
	var telegraphs: Array = []
	plain.attack_telegraphed.connect(func(kind: String, radius: float, delay: float):
		telegraphs.append({"kind": kind, "radius": radius, "delay": delay}))
	plain.current_phase = 2  # BossPhase.PHASE_3
	plain._perform_ultimate()
	plain.current_phase = 3  # ENRAGE
	plain._perform_ultimate()
	var r3 := float(telegraphs[0]["radius"])
	var rE := float(telegraphs[1]["radius"])
	_check(absf(r3 - 8.0) < 0.01 and absf(rE - 9.5) < 0.01,
		"base ultimate telegraph radii follow 5 + 1.5*rank (8.0, 9.5)")

	# --- Mend: heals, consumes uses, hard-capped ---
	boss.mend_uses_left = 2
	boss.mend_cooldown_left = 0.0
	boss.current_phase = 0
	boss.hp = int(boss.max_hp * 0.3)
	_check(boss._should_mend(), "mend offered below 50% hp")
	boss._perform_mend()
	_check(boss.mend_uses_left == 1, "mend consumed one use")
	_check(boss.mend_cooldown_left > 0.0, "mend cooldown started")
	var before_hp: int = boss.hp
	boss._resolve_mend(boss.encounter_generation)
	var expected_heal := maxi(1, int(round(float(boss.max_hp) * 0.08)))
	_check(boss.hp == mini(before_hp + expected_heal, boss.max_hp),
		"mend healed %d hp" % expected_heal)
	boss.mend_uses_left = 0
	_check(not boss._should_mend(), "mend hard-capped after uses exhausted")

	# --- Visual evolution: tint + silhouette change per stage ---
	var body := plain.get_node("Visual/Body") as MeshInstance3D
	var body_mat := body.material_override as ShaderMaterial
	body_mat.set_shader_parameter("emissive_color", Color(1.0, 0.5, 0.2))
	var emissive_before: Color = body_mat.get_shader_parameter("emissive_color")
	plain._evolve_for_phase(2)
	var emissive_after: Color = body_mat.get_shader_parameter("emissive_color")
	_check(emissive_before != emissive_after, "stage tint changed body emissive")
	var visual := plain.get_node("Visual")
	_check(absf(visual.scale.x - 1.09) < 0.001, "stage 3 silhouette swelled to 1.09x")

	# --- Encounter reset restores stage + mend budget ---
	boss.reset_encounter()
	_check(boss.mend_uses_left == boss.mend_max_uses, "mend budget restored on reset")
	_check(boss.hp == boss.max_hp, "hp restored on reset")
	_check(int(boss.current_phase) == 0, "stage reset to phase 1")

	if failures == 0:
		print("ALL BOSS STAGE ESCALATION TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	get_tree().quit(1 if failures > 0 else 0)
