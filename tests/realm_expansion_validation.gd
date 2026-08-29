extends Node

var _failures: Array[String] = []
var _passes := 0

func _ready() -> void:
    await _run_validation()
    print("=== Realm Expansion Validation ===")
    print("passes=", _passes, " failures=", _failures.size())
    for failure in _failures:
        print("FAILURE: ", failure)
    get_tree().quit(1 if not _failures.is_empty() else 0)

func _run_validation() -> void:
    GameState.reset()
    GameState.gold = 100
    var expansion_script = load("res://scripts/world/realm_expansion.gd")
    _assert_true(expansion_script != null, "realm expansion script loads")
    if expansion_script == null:
        return
    var owner := Node3D.new()
    owner.name = "ExpansionOwner"
    var hero := Node3D.new()
    hero.name = "Hero"
    owner.add_child(hero)
    add_child(owner)
    var expansion = expansion_script.new()
    owner.add_child(expansion)
    expansion.setup(owner)
    var forge_scene := load("res://scenes/ui/forge_menu.tscn") as PackedScene
    _assert_true(forge_scene != null, "checkpoint forge scene loads")
    var forge = forge_scene.instantiate() if forge_scene != null else null
    if forge != null:
        add_child(forge)
    await get_tree().process_frame

    _assert_true(owner.get_node_or_null("RealmExpansion/MountainRidge") != null, "mountain ridge is built")
    if forge != null:
        _assert_true(forge.get_node_or_null("Root/VBox/ElementSwitcher") != null, "forge exposes checkpoint element switching")
    _assert_true(owner.get_node_or_null("RealmExpansion/EmbervaultDungeon") != null, "Embervault dungeon is built")
    var mountain := owner.get_node("RealmExpansion/MountainRidge")
    _assert_true(mountain.get_child_count() == 0,
        "mountain ridge remains an empty compatibility container after hill removal")

    var weapon_result: Dictionary = GameState.switch_weapon_element("frost", 24)
    _assert_true(bool(weapon_result.get("success", false)), "checkpoint element switch succeeds")
    _assert_true(str(GameState.equipped_weapon.get("element", "")) == "frost", "weapon element persists after switch")
    _assert_true(GameState.gold == 76, "element switch spends its forge cost")

    var chest = owner.get_node("RealmExpansion/Chest_mountain_cache")
    var before_gold := GameState.gold
    expansion.open_chest(chest, "mountain_cache")
    await get_tree().process_frame
    var gold_drop: Node3D = null
    for drop in get_tree().get_nodes_in_group("loot_drop"):
        if drop.get("drop_kind") == "gold":
            gold_drop = drop as Node3D
            break
    _assert_true(gold_drop != null, "chest spawns a physical gold drop")
    if gold_drop != null:
        hero.global_position = gold_drop.global_position
        gold_drop.call("_collect", hero)
        await get_tree().process_frame
        await get_tree().process_frame
    _assert_true(GameState.gold == before_gold + 38, "collecting chest gold grants deterministic reward")
    _assert_true(GameState.opened_chests.get("mountain_cache", false), "opened chest is persisted in GameState")
    var collected_gold := GameState.gold
    expansion.open_chest(chest, "mountain_cache")
    _assert_true(GameState.gold == collected_gold, "opened chest cannot spawn a second reward")

    var surface := hero.global_position
    expansion.toggle_dungeon()
    await get_tree().process_frame
    _assert_true(expansion.in_dungeon, "cave entrance enters the Embervault")
    _assert_true(hero.global_position.distance_to(Vector3(80, 0.3, 6.0)) < 0.1, "dungeon teleports hero to interior")
    expansion.toggle_dungeon()
    _assert_true(not expansion.in_dungeon, "dungeon exit returns to surface")
    _assert_true(hero.global_position.distance_to(surface) < 0.1, "dungeon exit restores surface position")

    expansion.queue_free()
    owner.queue_free()
    if forge != null:
        forge.queue_free()
    await get_tree().process_frame

func _assert_true(condition: bool, message: String) -> void:
    if condition:
        _passes += 1
        print("PASS: ", message)
    else:
        _failures.append(message)
        push_error("FAIL: " + message)
