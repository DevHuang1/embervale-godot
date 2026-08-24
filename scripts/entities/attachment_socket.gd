class_name AttachmentSocket
extends Node3D

## === Attachment Socket ===
## Named mount point on a character rig ("weapon_r_hand",
## "lantern_hand", "back"). Attachments are plain meshes + materials
## with local offsets, so gear swaps never touch entity code.

@export var socket_id: String = ""
var _attached: Node3D = null


func attach(mesh: Mesh, material: Material = null, offset: Vector3 = Vector3.ZERO,
		rotation_euler: Vector3 = Vector3.ZERO, id: String = "") -> Node3D:
	detach()
	var mi := MeshInstance3D.new()
	mi.name = "Attachment_%s" % (id if not id.is_empty() else socket_id)
	mi.mesh = mesh
	if material:
		mi.material_override = material
	mi.position = offset
	mi.rotation = rotation_euler
	add_child(mi)
	_attached = mi
	return mi


func attach_node(node: Node3D) -> void:
	detach()
	add_child(node)
	_attached = node


func detach() -> void:
	if _attached and is_instance_valid(_attached):
		_attached.queue_free()
	_attached = null


func is_occupied() -> bool:
	return _attached != null and is_instance_valid(_attached)


static func find_socket(root: Node, id: String) -> AttachmentSocket:
	for child in root.find_children("*", "AttachmentSocket", true, false):
		if child.socket_id == id:
			return child
	return null