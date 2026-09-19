extends StaticBody3D

var handler: Node = null
var action := ""
var prop_id := ""
var prompt := "INTERACT"
var opened := false

func configure(owner_node: Node, next_action: String, id: String, label: String) -> void:
    add_to_group("interactable")
    handler = owner_node
    action = next_action
    prop_id = id
    prompt = label

func interact() -> void:
    if action == "chest" and opened:
        return
    if handler == null or not is_instance_valid(handler):
        return
    match action:
        "chest":
            opened = true
            handler.open_chest(self, prop_id)
        "checkpoint":
            handler.open_checkpoint()
        "dungeon":
            handler.toggle_dungeon()
        "dungeon_exit":
            handler.toggle_dungeon()
        # A door or an exit on any catalogued structure: the prop carries the
        # structure id, so one interaction path serves every castle, house and
        # pyramid instead of one hard-coded dungeon.
        "structure":
            if handler.has_method("toggle_structure"):
                handler.toggle_structure(prop_id)
        "structure_exit":
            if handler.has_method("toggle_structure"):
                handler.toggle_structure(prop_id)

func mark_opened() -> void:
    opened = true
    set_meta("opened", true)
