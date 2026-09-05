# FIX-3 — HUD: mobile skill buttons don't auto-select nearest enemy

**Severity:** 🟡 Medium — mobile/HUD skills appear to do nothing when no enemy
is manually tapped first; keyboard path auto-selects the nearest enemy before
firing.

---

## File

`scripts/ui/hud.gd`

---

## Location

`_on_skill_pressed(slot: int)` — around line 140.

---

## Root cause

The keyboard path (`hero.gd` ~line 1750) calls a helper that:
1. Finds the nearest enemy in range.
2. Calls `GameState.engage_enemy(enemy)` to set the target.
3. Then fires the skill.

The HUD mobile path calls `game_state.use_skill(slot)` directly. Because
`GameState.use_skill()` checks `needs_target` and returns `{"success": false}`
when `enemy_target == null`, every tap on a mobile skill button fails silently
when the player hasn't first manually tapped an enemy.

The fix is to mirror the keyboard path: if the skill requires a target and
none is selected, auto-engage the nearest enemy before firing.

---

## Exact fix

Replace the `_on_skill_pressed` function in `hud.gd`:

```gdscript
# BEFORE
func _on_skill_pressed(slot: int) -> void:
    var result := game_state.use_skill(slot)
    if result.get("success", false):
        var se := get_node_or_null("/root/SkillExecutor")
        if se == null:
            se = get_tree().current_scene.find_child("SkillExecutor", true, false)
        if se:
            se.call("execute_skill", slot, result.get("skill", {}))
    else:
        _push_field_note(str(result.get("message", "")))
```

```gdscript
# AFTER
func _on_skill_pressed(slot: int) -> void:
    # If skill needs a target but none is selected, auto-engage nearest enemy
    var sk := game_state.get_skill(slot)
    var needs_target : bool = str(sk.get("type", "")) != "heal_bloom"
    if needs_target and (not game_state.enemy_selected or game_state.enemy_target == null):
        _auto_engage_nearest()

    var result := game_state.use_skill(slot)
    if result.get("success", false):
        var se := get_node_or_null("/root/SkillExecutor")
        if se == null:
            se = get_tree().current_scene.find_child("SkillExecutor", true, false)
        if se:
            se.call("execute_skill", slot, result.get("skill", {}))
    else:
        _push_field_note(str(result.get("message", "")))

## Finds the nearest enemy in the scene and engages it via GameState.
func _auto_engage_nearest() -> void:
    var best   : Node3D = null
    var best_d : float  = 18.0   # max auto-engage range in world units
    var hero   : Node3D = null
    # Find hero
    if get_tree():
        var heroes := get_tree().get_nodes_in_group("player")
        if not heroes.is_empty():
            hero = heroes[0] as Node3D
    if hero == null:
        return
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy): continue
        var d := hero.global_position.distance_to((enemy as Node3D).global_position)
        if d < best_d:
            best_d = d
            best = enemy as Node3D
    if best != null:
        game_state.engage_enemy(best)
```

---

## Verification

1. Run the grove scene on a mobile device or in portrait-window mode on desktop.
2. Do NOT tap any enemy first.
3. Tap skill button 0 (Q slot).
4. The hero should engage the nearest enemy automatically and fire the skill.
5. A `_push_field_note` error message should NOT appear.
6. Keyboard Q/E/R behaviour should be unchanged.
