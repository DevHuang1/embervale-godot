extends Node

## === StoryManager AutoLoad ===
## Manages narrative state: voiced story beats, journal entries, NPC dialogue,
## and one-shot cinematic triggers.
##
## All story events are keyed by string ID and stored as a flat flag set.
## WorldManager and quest logic call trigger_event(); UI calls get_journal().
##
## Signal system lets HUD / overlays react without polling.

signal story_event_triggered(event_id: String)
signal journal_entry_added(entry: Dictionary)
signal dialogue_started(npc_id: String, lines: Array)
signal dialogue_ended(npc_id: String)

# === Story flag store =========================================================
var _flags         : Dictionary = {}   # event_id → bool (triggered)
var _journal       : Array[Dictionary] = []
var _active_npc    : String = ""

# === Built-in story entries ===================================================
## Each entry: { id, title, body, realm, stage, icon }
const STORY_DATABASE := {
	"intro_grove": {
		"title": "The Whispergrove",
		"body":  "The old warmth road brought me here. The grove is quiet — too quiet. Something stirs in the bramble.",
		"realm": "bramblewood", "stage": 0, "icon": "📖"
	},
	"first_hushling_sighted": {
		"title": "A Bramble Sprite",
		"body":  "A flicker of green light in the ferns. The sprite circled once, then vanished. My lantern knows the way.",
		"realm": "bramblewood", "stage": 0, "icon": "🌿"
	},
	"hushling_defeated": {
		"title": "The Sprite Answered",
		"body":  "The bramble sprite fell. Where it stood, a warm shard — a fragment of the old beacon. The grove exhaled.",
		"realm": "bramblewood", "stage": 1, "icon": "✨"
	},
	"shard_collected": {
		"title": "Ember Shard",
		"body":  "I found it — the ember shard. Warm to the touch. The ruined altar is north-east. I can feel the pull.",
		"realm": "bramblewood", "stage": 1, "icon": "◆"
	},
	"beacon_lit": {
		"title": "The Beacon Returns",
		"body":  "Light. Real warmth. The old road remembers now. The grove will hold its warmth until the next traveller comes through.",
		"realm": "bramblewood", "stage": 2, "icon": "🔆"
	},
	"matriarch_first_sighting": {
		"title": "She Who Roots",
		"body":  "A shape in the oldest thicket — too large, too still. The matriarch watches. I felt her eyes before I saw them.",
		"realm": "bramblewood", "stage": 2, "icon": "👁"
	},
	"matriarch_defeated": {
		"title": "The Crown Falls",
		"body":  "The Matriarch's crown shattered. Her bramble-song faded. The grove is mine — and so is the scepter she left behind.",
		"realm": "bramblewood", "stage": 3, "icon": "♛"
	},
	"mistfen_unlocked": {
		"title": "The Fen Gate Opens",
		"body":  "Beyond the Moonfen gate, cold mist rises. Fenlings orbit at the edge of sight. The fen holds its own warmth — or the cold that passes for it.",
		"realm": "mistfen", "stage": 3, "icon": "🌊"
	},
	"siltcrawler_sighted": {
		"title": "Something Beneath the Mud",
		"body":  "The ground moved. Not an earthquake — something alive. Bioluminescent trails below the surface. The Silt Crawler knows I am here.",
		"realm": "mistfen", "stage": 3, "icon": "🦀"
	},
	"heartwood_unlocked": {
		"title": "The Heartwood Burns",
		"body":  "Heat before light. The Heartwood's entrance scorches the mist away. Ember stone crumbles underfoot. Something enormous lives inside.",
		"realm": "heartwood", "stage": 3, "icon": "🔥"
	},
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# ─── Event system ─────────────────────────────────────────────────────────────

## Trigger a named story event. Fires signal and adds journal entry if first time.
func trigger_event(event_id: String) -> bool:
	if _flags.get(event_id, false):
		return false  # already triggered
	_flags[event_id] = true
	story_event_triggered.emit(event_id)
	# Auto-add journal entry if database has one
	if STORY_DATABASE.has(event_id):
		_add_journal(event_id, STORY_DATABASE[event_id])
	return true  # first trigger

## Returns true if the event has ever been triggered this save.
func has_triggered(event_id: String) -> bool:
	return bool(_flags.get(event_id, false))

## Force-set a flag without firing the signal (used by SaveLoadManager on load).
func set_flag(event_id: String, value: bool) -> void:
	_flags[event_id] = value

## Trigger all automatic events that match the current quest stage.
func sync_with_quest_stage(stage: int, realm_id: String) -> void:
	match stage:
		0:
			trigger_event("intro_grove")
		1:
			trigger_event("hushling_defeated")
			trigger_event("shard_collected")
		2:
			trigger_event("beacon_lit")
		3:
			trigger_event("matriarch_defeated")
			if realm_id == "mistfen":
				trigger_event("mistfen_unlocked")
			elif realm_id == "heartwood":
				trigger_event("heartwood_unlocked")

# ─── Journal ──────────────────────────────────────────────────────────────────

func _add_journal(event_id: String, entry_def: Dictionary) -> void:
	var entry := {
		"id":        event_id,
		"title":     str(entry_def.get("title",  "Unknown")),
		"body":      str(entry_def.get("body",   "")),
		"realm":     str(entry_def.get("realm",  "")),
		"stage":     int(entry_def.get("stage",   0)),
		"icon":      str(entry_def.get("icon",   "📖")),
		"timestamp": Time.get_unix_time_from_system(),
	}
	_journal.append(entry)
	journal_entry_added.emit(entry)

## Returns all journal entries, newest first.
func get_journal() -> Array[Dictionary]:
	var sorted := _journal.duplicate()
	sorted.sort_custom(func(a, b): return a["timestamp"] > b["timestamp"])
	return sorted

## Returns journal entries for a specific realm.
func get_journal_for_realm(realm_id: String) -> Array[Dictionary]:
	return _journal.filter(func(e): return str(e.get("realm", "")) == realm_id)

# ─── Dialogue ─────────────────────────────────────────────────────────────────

## Built-in NPC line pools
const NPC_DIALOGUE := {
	"quest_board": [
		["The boards says: 'Find the bramble sprite that lurks north of the glade.'",
		 "Your warmth will guide you. Keep the lantern lit."],
	],
	"practice_altar": [
		["This altar remembers the old fights.",
		 "Touch it to face the challenge again — no reward, only the practice."],
	],
	"loot_pedestal": [
		["A trophy from the deep grove.",
		 "The Matriarch would not give it willingly."],
	],
}

func start_dialogue(npc_id: String) -> void:
	if _active_npc == npc_id:
		return
	var pools : Array = NPC_DIALOGUE.get(npc_id, [])
	if pools.is_empty():
		return
	_active_npc = npc_id
	var lines : Array = pools[randi() % pools.size()]
	dialogue_started.emit(npc_id, lines)

func end_dialogue() -> void:
	var npc := _active_npc
	_active_npc = ""
	dialogue_ended.emit(npc)

func is_in_dialogue() -> bool:
	return not _active_npc.is_empty()

# ─── Serialisation ────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return { "flags": _flags.duplicate() }

func from_dict(d: Dictionary) -> void:
	_flags = d.get("flags", {})
	# Rebuild journal from flags
	_journal.clear()
	for event_id in _flags:
		if _flags[event_id] and STORY_DATABASE.has(event_id):
			_add_journal(event_id, STORY_DATABASE[event_id])
