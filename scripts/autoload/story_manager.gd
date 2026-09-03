extends Node
## StoryManager — data-driven story layer: quest registry, story flags,
## exactly-once rewards and save/load. Additive by design: the existing GameState
## main-quest flow (stages, grove world states) is untouched; this engine
## tracks side quests gated by stage / realm / story flags desde JSON data.

signal quest_started(quest_id: String)
signal quest_completed(quest_id: String)
signal story_flags_changed

const QUESTS_PATH := "res://data/story/quests.json"
const SAVE_SECTION := "story"
const MAX_HUD_LINES := 3

var _registry: Dictionary = {}
var _main_stages: Array = []
var _active: Dictionary = {}
var _completed: Dictionary = {}
var story_flags: Dictionary = {}

func _ready() -> void:
    _load_registry()
    _reset_runtime()
    var gs := _game_state()
    if gs != null:
        if gs.has_signal("stage_changed"):
            gs.stage_changed.connect(_on_flow_signal)
        if gs.has_signal("realm_changed"):
            gs.realm_changed.connect(_on_flow_signal)
    _check_auto_grants()

func _game_state() -> Node:
    return get_node_or_null("/root/GameState")

func _load_registry() -> void:
    _registry.clear()
    _main_stages.clear()
    if not FileAccess.file_exists(QUESTS_PATH):
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(QUESTS_PATH))
    if not parsed is Dictionary:
        return
    var main: Variant = parsed.get("main_quest", {})
    if main is Dictionary:
        var stages: Variant = main.get("stages", [])
        if stages is Array:
            for s in stages:
                if s is Dictionary:
                    _main_stages.append(s.duplicate(true))
    var quests: Variant = parsed.get("quests", [])
    if not quests is Array:
        return
    for raw in quests:
        if not raw is Dictionary:
            continue
        var def: Dictionary = raw
        var id := str(def.get("id", ""))
        if id.is_empty() or _registry.has(id):
            continue
        _registry[id] = def.duplicate(true)

func quest_count() -> int:
    return _registry.size()

func main_stage_count() -> int:
    return _main_stages.size()

func has_quest(quest_id: String) -> bool:
    return _registry.has(quest_id)

func has_flag(flag_key: String) -> bool:
    return bool(story_flags.get(flag_key, false))

func set_flag(flag_key: String, value: bool = true) -> void:
    if value:
        story_flags[flag_key] = true
    else:
        story_flags.erase(flag_key)
    story_flags_changed.emit()
    _persist()

func get_quest_def(quest_id: String) -> Dictionary:
    return (_registry.get(quest_id, {}) as Dictionary).duplicate(true)

func _gate_passes(gate: String) -> bool:
    var negate := gate.begins_with("!")
    var token := gate.trim_prefix("!")
    var ok := false
    if token.begins_with("stage."):
        var rank := _stage_rank(token.trim_prefix("stage."))
        if rank >= 0:
            var gs := _game_state()
            ok = gs != null and int(gs.get("current_stage")) >= rank
    elif token.begins_with("realm."):
        var gs := _game_state()
        ok = gs != null and str(gs.get("current_realm")) == token.trim_prefix("realm.")
    elif token.begins_with("quest."):
        ok = _completed.has(_quest_id_from_token(token))
    elif token.begins_with("flag."):
        ok = bool(story_flags.get(token.trim_prefix("flag."), false))
    else:
        ok = bool(story_flags.get(token, false))
    return ok if not negate else not ok

func _gates_pass(def: Dictionary) -> bool:
    for raw in def.get("gates", []):
        if not _gate_passes(str(raw)):
            return false
    return true

const STAGE_RANK :={
    "seek_sprite":0, "claim_shard":1, "light_beacon":2,"complete":3,
}

func _reset_runtime() -> void:
    _active.clear()
    _completed.clear()
    story_flags.clear()

func _check_auto_grants() -> void:
    for id in _registry:
        var def := _registry[id] as Dictionary
        if not _completed.has(id) and not _active.has(id):
            if _gates_pass(def):
                _grant_quest(id, def)

func start_quest(quest_id: String) -> Dictionary:
    var def := get_quest_def(quest_id)
    if def.is_empty():
        return {"ok": false, "message": "Unknown quest."}
    if _active.has(quest_id):
        return {"ok": false, "message": "Quest already active."}
    if _completed.has(quest_id):
        return {"ok": false, "message": "Quest already completed."}
    if not _gates_pass(def):
        return {"ok": false, "message": "Gates not met."}
    _grant_quest(quest_id, def)
    return {"ok": true}

func _grant_quest(quest_id: String, def: Dictionary) -> void:
    var objectives: Array = []
    for raw in def.get("objectives", []):
        if raw is Dictionary:
            var o: Dictionary = raw
            objectives.append({
                "id": str(o.get("id", "")),
                "type": str(o.get("type", "")),
                "target": str(o.get("target", "")),
                "qty": maxi(1, int(o.get("qty", 1))),
                "current": 0,
                "completed": false,
                "description": str(o.get("description", "")),
            })
    _active[quest_id] = {
        "id": quest_id,
        "chapter": str(def.get("chapter", "")),
        "title": str(def.get("title", "")),
        "giver": str(def.get("giver", "")),
        "objectives": objectives,
    }
    quest_started.emit(quest_id)
    _persist()
func _stage_rank(stage_name: String) -> int:
    return STAGE_RANK.get(stage_name, 9999)

func _quest_id_from_token(token: String) -> String:
    var qid := token.trim_prefix("quest.")
    if qid.ends_with(".done"):
        qid = qid.trim_suffix(".done")
    return qid
func notify_objective(type: String, target: String = "", qty: int = 1) -> bool:
    var changed := false
    for quest_id in _active:
        var quest: Dictionary = _active[quest_id] as Dictionary
        var objs: Array = quest.get("objectives", [])
        for i in objs.size():
            var o: Dictionary = objs[i] as Dictionary
            if o.get("completed", false):
                continue
            if o.get("type", "") != type:
                continue
            if not str(o.get("target", "")).is_empty() and target != "" \
                    and not target.contains(str(o.get("target", ""))):
                continue
            var cur := mini(int(o.get("current", 0)) + qty, int(o.get("qty", 1)))
            o["current"] = cur
            if cur >= int(o.get("qty", 1)):
                o["completed"] = true
            objs[i] = o
            changed = true
    if changed:
        _persist()
        _check_quest_completions()
    return changed

func _check_quest_completions() -> void:
    for quest_id in _active.keys():
        var quest: Dictionary = _active[quest_id] as Dictionary
        var objs: Array = quest.get("objectives", [])
        var all_done := true
        for o in objs:
            if not o.get("completed", false):
                all_done = false
                break
        if all_done:
            _complete_quest(quest_id)

func _complete_quest(quest_id: String) -> void:
    if _completed.has(quest_id):
        return
    var def := get_quest_def(quest_id)
    _active.erase(quest_id)
    _completed[quest_id] = true
    var reward: Dictionary = def.get("reward", {})
    var gs := _game_state()
    if gs != null:
        var gold: int = int(reward.get("gold", 0))
        if gold > 0 and gs.has_method("add_gold"):
            gs.call("add_gold", gold, "+%d gold from tale. " % gold)
        var xp: int = int(reward.get("xp", 0))
        if xp > 0 and gs.has_method("grant_xp"):
            gs.call("grant_xp", xp)
        var diamonds: int = int(reward.get("diamonds", 0))
        if diamonds >0 and gs.has_method("add_diamonds"):
            gs.call("add_diamonds", diamonds, "A glint of jewels from the tale. ")
        var mats: Variant = reward.get("materials", {})
        if mats is Dictionary and gs.has_method("add_material"):
            for mid in mats:
                gs.call("add_material", mid, int(mats[mid]))
    for flag in reward.get("flags", []):
        set_flag(str(flag))
    quest_completed.emit(quest_id)
    _persist()
    _check_auto_grants()
    var gs2 := _game_state()
    if gs2 != null and gs2.has_signal("quest_progress"):
        gs2.quest_progress.emit("Tale complete: %s" % def.get("title", quest_id))
func _on_flow_signal(_what: Variant) -> void:
    _check_auto_grants()

func _persist() -> void:
    var gs := _game_state()
    if gs != null and gs.has_method("save_game"):
        gs.call("save_game")

func save_payload() -> Dictionary:
    return {
        "active": _active.duplicate(true),
        "completed": _completed.duplicate(true),
        "flags": story_flags.duplicate(true),
    }

func load_payload(data: Dictionary) -> void:
    var active_raw: Variant = data.get("active", {})
    _active = active_raw.duplicate(true) if active_raw is Dictionary else {}
    var completed_raw: Variant = data.get("completed", {})
    _completed = completed_raw.duplicate(true) if completed_raw is Dictionary else {}
    var flags_raw: Variant = data.get("flags", {})
    story_flags = flags_raw.duplicate(true) if flags_raw is Dictionary else {}
    _check_quest_completions()
    _check_auto_grants()

func reset_payload() -> void:
    _reset_runtime()
    _check_auto_grants()

func active_quests() -> Array:
    return _active.values()

func active_quest_count() -> int:
    return _active.size()

func is_completed(quest_id: String) -> bool:
    return _completed.has(quest_id)

func hud_objective_lines(limit: int = MAX_HUD_LINES) -> Array[String]:
    var lines: Array[String] = []
    for quest_id in _active:
        var quest: Dictionary = _active[quest_id] as Dictionary
        var objs: Array = quest.get("objectives", [])
        for o in objs:
            if o.get("completed", false):
                continue
            var label: String = str(o.get("description", ""))
            lines.append("%s — %d/%d" % [label, int(o.get("current", 0)), int(o.get("qty", 1))])
            if lines.size() >= limit:
                return lines
    return lines

func validate_registry() -> Dictionary:
    var known_stages := STAGE_RANK.keys()
    var known_quests := {}
    for id in _registry:
        known_quests[id] = true
    var problems: Array[String] = []
    for id in _registry:
        var def := get_quest_def(id)
        for gate in def.get("gates", []):
            var token := str(gate).trim_prefix("!")
            if token.begins_with("stage.") and token.trim_prefix("stage.") not in known_stages:
                problems.append("%s bad stage gate: %s" % [id, gate])
            elif token.begins_with("quest.") and not known_quests.has(_quest_id_from_token(token)):
                problems.append("%s bad quest gate: %s" % [id, gate])
    return {"problems": problems, "quest_count": _registry.size(), "main_stage_count": _main_stages.size()}
