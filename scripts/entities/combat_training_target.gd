extends CharacterBody3D
class_name CombatTrainingTarget

## Optional practice target. It uses the enemy group/contract for targeting but
## never grants loot, XP, objectives, or scan charges.

@export var max_hp: int = 120
@export var reset_delay: float = 2.5

var hp: int = 120
var is_defeated: bool = false
var _reset_timer: float = 0.0
var _practice_label: Label3D

func _ready() -> void:
	hp = maxi(max_hp, 1)
	add_to_group("enemy")
	set_meta("scan_kind", "training_target")
	set_meta("scan_role", "practice")
	set_meta("scan_hp", hp)
	set_meta("scan_attack", 0)
	set_meta("scan_speed", 0.0)
	set_meta("scan_description", "Practice target — no combat rewards")
	_practice_label = get_node_or_null("PracticeLabel") as Label3D

func _physics_process(delta: float) -> void:
	if is_defeated:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			reset_target()

func take_damage(amount: int, _knockback_dir: Vector3 = Vector3.ZERO,
		_critical: bool = false) -> void:
	if is_defeated:
		return
	hp = maxi(hp - maxi(amount, 0), 0)
	set_meta("scan_hp", hp)
	if hp == 0:
		is_defeated = true
		_reset_timer = maxf(reset_delay, 0.1)
		visible = false

func reset_target() -> void:
	hp = maxi(max_hp, 1)
	is_defeated = false
	_reset_timer = 0.0
	visible = true
	set_meta("scan_hp", hp)
