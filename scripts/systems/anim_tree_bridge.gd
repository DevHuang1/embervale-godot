class_name AnimTreeBridge
extends Node3D

## === Authored Animation Bridge ===
## Consumes animation clips from an imported glTF/glb rig and plays them by
## gameplay cue ("idle", "walk", "light_1", "heavy", ...). It is the seam
## between authored movie clips and the existing code-driven EntityAnimator:
## when clips exist it plays them; when they don't, gameplay code keeps
## using the procedural animator untouched (see CharacterRigLoader).

var player: AnimationPlayer = null
var tree: AnimationTree = null
var _current_cue := ""

## Gameplay cue -> likely clip names in imported packs (Quaternius and
## friends name clips "Idle", "Walk_01", "Attack", ... not our cue ids).
const CUE_ALIASES := {
	"idle": ["idle", "flying", "float"],
	"walk": ["walk", "walking", "fly"],
	"run": ["run", "jog", "sprint"],
	"light_1": ["attack", "attack1", "slash", "hit1"],
	"light_2": ["attack2", "slash2", "hit2"],
	"light_3": ["attack3", "combo", "hit3"],
	"heavy": ["heavy", "slam", "attack"],
	"cast": ["cast", "spell", "magic", "attack"],
	"buff": ["buff", "cast", "spell"],
	"hit": ["hurt", "take_hit", "damage", "hit"],
	"dodge": ["dodge", "roll", "evade"],
	"death": ["death", "die", "dead"],
}

## Called once by CharacterRigLoader after the imported model is parented.
func bind(anim_root: Node) -> void:
	if anim_root == null:
		return
	var found := anim_root.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		player = found[0] as AnimationPlayer
	var trees := anim_root.find_children("*", "AnimationTree", true, false)
	if not trees.is_empty():
		tree = trees[0] as AnimationTree
		tree.active = true

## Map a gameplay cue to the closest clip name in the imported set.
func _resolve(alias: String) -> String:
	if player == null:
		return ""
	var list := player.get_animation_list()
	if list.is_empty():
		return ""
	# Alias table first (pack clip naming differs from gameplay cues),
	# then exact, then substring fallbacks.
	var wanted: Array = CUE_ALIASES.get(alias, [alias])
	for want in wanted:
		want = str(want).to_lower()
		for name in list:
			if str(name).to_lower() == want:
				return str(name)
	for want in wanted:
		want = str(want).to_lower()
		for name in list:
			if str(name).to_lower().contains(want):
				return str(name)
	return ""

## Try to play a cue with a crossfade. Returns false when no clip matched,
## which tells gameplay code to keep the procedural pose instead.
func play_cue(cue: String, cross: float = 0.22) -> bool:
	if player == null:
		return false
	var clip := _resolve(cue)
	if clip == "":
		_current_cue = ""
		return false
	_current_cue = cue
	# Locomotion/idle clips must loop; one-shots (attack/death) hold last frame.
	if cue in _LOOPING_CUES:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	else:
		player.get_animation(clip).loop_mode = Animation.LOOP_NONE
	if tree != null:
		var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback != null:
			playback.travel(clip)
			return true
	player.play(clip, cross)
	return true

func stop() -> void:
	if player != null:
		player.stop()
	_current_cue = ""

func current_cue() -> String:
	return _current_cue

## True when this bridge owns the provided sync signals, so gameplay hooks
## (attack_impact/footfall) can forward from clip events later.
func is_active() -> bool:
	return player != null

# === Autonomous state driving ===
## Optional callable returning {dead, attacking, moving, running} so the
## bridge can pick cues itself every frame without entity-side wiring.
var state_provider: Callable = Callable()
var _last_cue := ""
const _LOOPING_CUES := ["idle", "walk", "run"]

func _process(_delta: float) -> void:
	if player == null or not state_provider.is_valid():
		return
	var st: Dictionary = state_provider.call()
	var cue := _pick_cue(st)
	if cue == "":
		return
	if cue == _current_cue and player.is_playing():
		return
	if play_cue(cue):
		_last_cue = cue

func _pick_cue(st: Dictionary) -> String:
	if st.get("dead", false):
		return "death"
	if st.get("attacking", false):
		# A cast (staff/area/heal) reads as a stance — the knight has no cast
		# clip, so this falls back to idle rather than a walk-swing.
		if st.get("casting", false):
			return "cast"
		return "light_1"
	if st.get("dodging", false):
		return "dodge"
	if st.get("moving", false):
		return "run" if st.get("running", false) else "walk"
	return "idle"