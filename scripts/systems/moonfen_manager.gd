extends BiomeManager

class_name MoonfenManager

func _ready() -> void:
	biome_id = Bestiary.REALM_MOONFEN
	super._ready()
	# Moonfen uses the shared capped biome lifecycle; the inherited starter is
	# exclusively a Whispergrove onboarding actor.
	hushling.visible = false
	hushling.set_physics_process(false)
	hushling.collision_layer = 0
	hushling.collision_mask = 0
	hushling.get_node("Hitbox").monitoring = false
	hushling.get_node("AttackArea").monitoring = false
	game_state.quest_progress.emit("The Moonfen wakes beneath the blue ash. The Oracle waits beyond the undertide.")
