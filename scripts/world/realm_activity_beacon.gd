extends Node3D
class_name RealmActivityBeacon

## Optional, non-blocking realm activity marker. It teaches the realm's
## signature traversal without modifying route collision or combat.

@export var realm_id: String = "bramblewood"
@export var activity_id: String = ""

var _label: Label3D
var _discovered := false

func configure(p_realm: String) -> void:
	realm_id = p_realm
	activity_id = "activity_%s" % realm_id

func _ready() -> void:
	add_to_group("interactable")
	_build_visual()
	_build_area()
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var discovered: Dictionary = gs.get("discovered_landmarks") if gs.get("discovered_landmarks") != null else {}
		_discovered = bool(discovered.get(activity_id, false))
	_refresh_label()

func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.18
	cylinder.bottom_radius = 0.32
	cylinder.height = 1.2
	mesh.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.65, 0.85)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.65
	mesh.material_override = material
	mesh.position.y = 0.6
	add_child(mesh)
	_label = Label3D.new()
	_label.name = "ActivityLabel"
	_label.font_size = 16
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.5
	_label.modulate = Color(0.75, 0.9, 1.0)
	_label.visible = false
	var profile: Dictionary = RealmIdentityCatalog.for_realm(realm_id)
	_label.text = "%s\nREWARD  ·  %s" % [
		str(profile.get("traversal", "Explore")),
		str(profile.get("landmark_reward", "Discover a landmark"))]
	add_child(_label)

func _build_area() -> void:
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 1 << 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.8
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_label.visible = true
		_refresh_label()

func _on_body_exited(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_label.visible = false

func interact() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("begin_activity"):
		gs.call("begin_activity", activity_id, str(gs.get("route_checkpoint_id")))
	if _discovered:
		FloatingText.spawn_on_entity(self, "Already learned", Color(0.65, 0.75, 0.82), 1.0)
		return
	_discovered = true
	_refresh_label()
	var state_node: Node = get_node_or_null("/root/GameState")
	if state_node != null:
		var discovered: Dictionary = state_node.get("discovered_landmarks") if state_node.get("discovered_landmarks") != null else {}
		discovered[activity_id] = true
		state_node.set("discovered_landmarks", discovered)
		if state_node.has_method("save_game"):
			state_node.call("save_game")
	_grant_landmark_reward()

func _grant_landmark_reward() -> void:
	var profile: Dictionary = RealmIdentityCatalog.for_realm(realm_id)
	var reward: Dictionary = profile.get("reward", {})
	var reward_type := str(reward.get("type", ""))
	var quantity := int(reward.get("quantity", 0))
	var gs := get_node_or_null("/root/GameState")
	if gs == null or quantity <= 0:
		return
	match reward_type:
		"gold":
			if gs.has_method("add_gold"):
				gs.call("add_gold", quantity, "Landmark reward: %d gold." % quantity)
		"material":
			if gs.has_method("add_material"):
				gs.call("add_material", str(reward.get("id", "")), quantity)
		"scan_fragment":
			var fragments := int(gs.get("scan_fragments") if gs.get("scan_fragments") != null else 0)
			gs.set("scan_fragments", mini(fragments + quantity, 4))
	FloatingText.spawn_on_entity(self, "Landmark reward secured", Color(0.70, 0.90, 1.0), 1.2)

func _refresh_label() -> void:
	if _label == null:
		return
	var profile: Dictionary = RealmIdentityCatalog.for_realm(realm_id)
	var state := "DISCOVERED" if _discovered else "DISCOVER"
	_label.text = "%s  ·  %s\n%s  ·  %s" % [
		state, str(profile.get("traversal", "Explore")),
		"REWARD" if not _discovered else "ALREADY CLAIMED",
		str(profile.get("landmark_reward", "Discover a landmark"))]
