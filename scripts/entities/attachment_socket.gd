extends Node3D
class_name AttachmentSocket

## === AttachmentSocket — Weapon / Gear Mount Point ===
## Used by Hero for hand sockets (hand_l, hand_r) and back socket.
## Entities create these in _ready(); CharacterRigLoader reparents them
## under the matching bone when an authored rig mounts.
##
## Properties read by the weapon visual system:
##   socket_id   : String  — "hand_l", "hand_r", "back"
##   attached    : Node3D  — currently mounted item (set by equip/unequip)
##
## API:
##   attach(item: Node3D)   — parent item under this socket, keep world xform
##   detach() -> Node3D     — remove and return the current item
##   has_item() -> bool

@export var socket_id : String = ""
## Tag displayed in editor for identification
@export var socket_label : String = ""

var attached : Node3D = null

func attach(item: Node3D) -> void:
	if item == null:
		return
	if attached != null and is_instance_valid(attached):
		detach()
	var world_xform := item.global_transform if item.is_inside_tree() else item.transform
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	add_child(item)
	item.global_transform = world_xform
	attached = item

func detach() -> Node3D:
	if attached == null or not is_instance_valid(attached):
		attached = null
		return null
	var item := attached
	attached = null
	var world_xform := item.global_transform
	remove_child(item)
	# Return to scene root so caller can reparent elsewhere
	var scene_root := get_tree().current_scene
	if scene_root != null:
		scene_root.add_child(item)
	item.global_transform = world_xform
	return item

func has_item() -> bool:
	return attached != null and is_instance_valid(attached)

func get_item() -> Node3D:
	return attached if has_item() else null
