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

func mark_opened() -> void:
    opened = true
    set_meta("opened", true)
