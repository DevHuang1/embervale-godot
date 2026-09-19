extends RefCounted
class_name StructureKit

## === StructureKit — shipped CC0 modular pieces for structures ===
## Maps a logical piece name ("wall", "wall_door", "floor", "stairs", ...) to a
## CC0 model that ships in the repo and instantiates it under a parent at a
## given local transform. Every piece is optional: when a model is missing the
## call returns null and the caller keeps its procedural box, so a kit can be
## swapped or stripped without breaking a build or a test.
##
## Piece dimensions are measured once from the real model and cached, so layout
## math uses actual metres instead of guesses. Interiors are KayKit Dungeon
## Remastered (4 m module), exteriors are Kenney Castle Kit / Fantasy Town Kit
## (1 m module). All three are CC0 1.0; see each pack's License.txt.

const KAYKIT := "res://assets/models/kaykit_dungeon/"
const CASTLE := "res://assets/models/kenney_castle/"
const TOWN := "res://assets/models/kenney_fantasy_town/"

## Logical piece -> model file. Interior pieces on the KayKit 4 m grid.
const PIECES: Dictionary = {
	# Interior surfaces
	"floor": KAYKIT + "floor_tile_large.gltf.glb",
	"floor_small": KAYKIT + "floor_tile_small.gltf.glb",
	"floor_corner": KAYKIT + "floor_tile_small_corner.gltf.glb",
	"wall": KAYKIT + "wall.gltf.glb",
	"wall_door": KAYKIT + "wall_doorway.glb",
	"wall_corner": KAYKIT + "wall_corner.gltf.glb",
	"wall_endcap": KAYKIT + "wall_endcap.gltf.glb",
	"wall_window": KAYKIT + "wall_window_open.gltf.glb",
	"wall_pillar": KAYKIT + "wall_pillar.gltf.glb",
	"stairs": KAYKIT + "stairs_walled.gltf.glb",
	"column": KAYKIT + "column.gltf.glb",
	# Interior dressing
	"torch": KAYKIT + "torch_mounted.gltf.glb",
	"candle": KAYKIT + "candle_triple.gltf.glb",
	"banner": KAYKIT + "banner_red.gltf.glb",
	"chest": KAYKIT + "chest.glb",
	"chest_gold": KAYKIT + "chest_gold.glb",
	"barrel": KAYKIT + "barrel_large.gltf.glb",
	"barrel_small": KAYKIT + "barrel_small.gltf.glb",
	"crates": KAYKIT + "crates_stacked.gltf.glb",
	"table": KAYKIT + "table_long.gltf.glb",
	"table_small": KAYKIT + "table_small.gltf.glb",
	"sword_shield": KAYKIT + "sword_shield.gltf.glb",
	# Exterior: Kenney Castle Kit
	"castle_wall": CASTLE + "wall.glb",
	"castle_wall_half": CASTLE + "wall-half.glb",
	"castle_wall_door": CASTLE + "wall-doorway.glb",
	"castle_wall_stairs": CASTLE + "wall-narrow-stairs.glb",
	"castle_tower_base": CASTLE + "tower-square-base.glb",
	"castle_tower_mid": CASTLE + "tower-square-mid.glb",
	"castle_tower_top": CASTLE + "tower-square-top.glb",
	"castle_tower_roof": CASTLE + "tower-square-top-roof.glb",
	"castle_tower_roof_tall": CASTLE + "tower-square-roof.glb",
	"castle_door": CASTLE + "door.glb",
	"castle_gate": CASTLE + "gate.glb",
	"castle_flag": CASTLE + "flag-banner-long.glb",
	"castle_stairs": CASTLE + "stairs-stone-square.glb",
	# Exterior: Kenney Fantasy Town Kit
	"town_wall": TOWN + "wall-side.glb",
	"town_roof": TOWN + "roof.glb",
	"town_pillar": TOWN + "pillar-stone.glb",
	"town_window": TOWN + "wall-window-shutters.glb",
}

static var _scenes: Dictionary = {}
static var _boxes: Dictionary = {}

## True when the logical piece maps to a model that actually loads. Resolves the
## packed scene only: instantiating here would leak a node per probe.
static func has_piece(piece: String) -> bool:
	return _packed(piece) != null

## The model path for a logical piece, empty when unknown.
static func piece_path(piece: String) -> String:
	return str(PIECES.get(piece, ""))

## Loads and caches the PackedScene, including failed lookups so a missing piece
## is only probed once. Null for unknown or unloadable pieces.
static func _packed(piece: String) -> PackedScene:
	if not _scenes.has(piece):
		var path := piece_path(piece)
		_scenes[piece] = ResourceLoader.load(path, "PackedScene") as PackedScene \
			if not path.is_empty() else null
	return _scenes.get(piece) as PackedScene

## Instantiates a piece, or returns null when it is unknown or fails to load.
## Instances are fresh every call: callers own their node and its lifetime.
static func make(piece: String) -> Node3D:
	var scene := _packed(piece)
	if scene == null:
		return null
	return scene.instantiate() as Node3D

## Measured local-space AABB of a piece, cached. Empty when unavailable.
static func piece_box(piece: String) -> AABB:
	if _boxes.has(piece):
		return _boxes.get(piece) as AABB
	var node := make(piece)
	var box := AABB()
	if node != null:
		box = _node_aabb(node, Transform3D.IDENTITY)
		node.free()
	_boxes[piece] = box
	return box

## Measured world-space size of a piece, cached. Vector3.ZERO when unavailable.
static func piece_size(piece: String) -> Vector3:
	return piece_box(piece).size

## Adds a piece under `parent`, scaled to `target_size` (any zero axis keeps the
## authored size) and offset so its measured centre lands on `xform.origin`.
## Returns the instance, or null when the piece is unavailable.
static func add(parent: Node3D, piece: String, xform: Transform3D,
		target_size := Vector3.ZERO, node_name := "") -> Node3D:
	var node := _fit(piece, target_size)
	if node == null:
		return null
	node.name = node_name if not node_name.is_empty() else "Kit_%s" % piece
	parent.add_child(node)
	node.transform = xform
	return node

## Adds a piece under `parent` with its authored pivot on `xform.origin` — the
## floor point for a prop — instead of centre-aligning it to a box.
static func place(parent: Node3D, piece: String, xform: Transform3D,
		target_size := Vector3.ZERO, node_name := "") -> Node3D:
	var node := _fit(piece, target_size, false)
	if node == null:
		return null
	node.name = node_name if not node_name.is_empty() else "Kit_%s" % piece
	parent.add_child(node)
	node.transform = xform
	return node

## Instantiated + scaled piece. `centre` also shifts the instance so its AABB
## centre sits on the node origin, which is what fitting a piece to a slab needs.
static func _fit(piece: String, target_size: Vector3, centre := true) -> Node3D:
	var node := make(piece)
	if node == null:
		return null
	var box := piece_box(piece)
	if box.size.x <= 0.001 or box.size.y <= 0.001 or box.size.z <= 0.001:
		return node
	var scale := Vector3.ONE
	if target_size.x > 0.001:
		scale.x = target_size.x / box.size.x
	if target_size.y > 0.001:
		scale.y = target_size.y / box.size.y
	if target_size.z > 0.001:
		scale.z = target_size.z / box.size.z
	node.scale = scale
	if centre:
		node.position = -box.get_center() * scale
	return node

## Tiles a rectangular span with floor pieces, scaling the last tile of each
## row to the remainder so the surface ends exactly at the span edge. Returns
## the number of instances added (0 when the piece is unavailable).
static func tile_floor(parent: Node3D, origin: Vector3, span: Vector2, y: float,
		piece := "floor", node_prefix := "KitFloor") -> int:
	var base := piece_size(piece)
	if base.x <= 0.001 or base.z <= 0.001:
		return 0
	var count := 0
	var x := 0.0
	while x < span.x - 0.01:
		var width := minf(base.x, span.x - x)
		var z := 0.0
		while z < span.y - 0.01:
			var depth := minf(base.z, span.y - z)
			var center := Vector3(origin.x + x + width * 0.5, y,
				origin.z + z + depth * 0.5)
			add(parent, piece, Transform3D(Basis.IDENTITY, center),
				Vector3(width, 0.0, depth), "%s_%d" % [node_prefix, count])
			count += 1
			z += depth
		x += width
	return count

static func _node_aabb(node: Node, xform: Transform3D) -> AABB:
	var merged := AABB()
	var has := false
	if node is Node3D:
		xform = xform * (node as Node3D).transform
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			if mesh != null:
				merged = xform * mesh.get_aabb()
				has = true
	for child in node.get_children():
		var box := _node_aabb(child, xform)
		if box.size != Vector3.ZERO:
			merged = box if not has else merged.merge(box)
			has = true
	return merged
