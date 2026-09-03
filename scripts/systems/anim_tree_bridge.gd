class_name AnimTreeBridge
extends Node3D

## === Authored Animation Bridge ===
## Consumes animation clips from an imported glTF/glb rig and plays them by
## gameplay cue ("idle", "walk", "light_1", "heavy", ...). It is the seam
## between authored movie clips and the existing code-driven EntityAnimator:
## when clips exist it plays them; when they don't, gameplay code keeps
## using the procedural animator untouched (see CharacterRigLoader).

signal cue_impact(cue: String)

var player: AnimationPlayer = null
var tree: AnimationTree = null
var _current_cue := ""
var _current_clip := ""
var _cue_elapsed := 0.0
var _cue_impact_fired := false
var _impact_fraction_override := -1.0
var _cue_speed := 1.0
var _attack_serial := -1

## Per-cue playback speed: the authored sword clip is 1.167s — far slower
## than the attack cadence — so light swings play slightly sped up. Heavy
## keeps natural speed to stay weighty. Impact thresholds compensate.
const CUE_SPEEDS := {"light_1": 1.25, "light_2": 1.35, "light_3": 1.1}

## Gameplay cue -> likely clip names in imported packs (Quaternius and
## friends name clips "Idle", "Walk_01", "Attack", ... not our cue ids).
const CUE_ALIASES := {
	"idle": ["idle", "flying", "fly", "float"],
	"walk": ["walk", "walking", "fly", "flying"],
	"run": ["run", "jog", "sprint", "walk"],
	"light_1": ["attack1", "swordattack", "attack", "slash", "hit1"],
	"light_2": ["attack2", "slash2", "hit2", "swordattack", "attack"],
	"light_3": ["attack3", "combo", "hit3", "swordattack", "attack"],
	"heavy": ["heavy", "slam", "swordattack", "attack"],
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
## `restart` forces a same-clip replay back to frame 0 — Godot 4.x
## AnimationPlayer.play() keeps the old playback position when the requested
## clip is already the current one, which reads as a swing that never resets.
func play_cue(cue: String, cross: float = 0.22, restart: bool = false) -> bool:
	if player == null:
		return false
	var clip := _resolve(cue)
	if clip == "":
		_current_cue = ""
		return false
	var was_playing_same: bool = player.current_animation == clip \
			and player.is_playing()
	_current_cue = cue
	_current_clip = clip
	_cue_elapsed = 0.0
	_cue_impact_fired = false
	_impact_fraction_override = -1.0
	_cue_speed = float(CUE_SPEEDS.get(cue, 1.0))
	player.speed_scale = _cue_speed
	# Locomotion/idle clips must loop and may crossfade; one-shots (attack/
	# death) hold last frame AND cut in — a long crossfade makes the visible
	# arm start its swing a quarter-second after the blade and the damage.
	var fade := cross
	if cue in _LOOPING_CUES:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	else:
		player.get_animation(clip).loop_mode = Animation.LOOP_NONE
		fade = 0.05
	if tree != null:
		var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback != null:
			playback.travel(clip)
			return true
	player.play(clip, fade)
	if restart and was_playing_same:
		# Same clip was mid-play: play() above did NOT rewind it, so snap
		# the swing back to its first frame immediately (attacks reuse the
		# same cue for combo resets and spaced taps).
		player.seek(0.0, true)
	return true

func stop() -> void:
	if player != null:
		player.stop()
		player.speed_scale = 1.0
	_cue_speed = 1.0
	_current_cue = ""
	_current_clip = ""
	_cue_elapsed = 0.0
	_cue_impact_fired = false

func current_cue() -> String:
	return _current_cue

func has_cue(cue: String) -> bool:
	return not _resolve(cue).is_empty()

func current_cue_has_impact() -> bool:
	return has_cue(_current_cue) and _impact_fraction(_current_cue) >= 0.0

## Real impact moment of a cue on this rig, in seconds from cue start,
## accounting for the per-cue playback speed. -1 when the rig has no clip
## or the cue has no impact. `fraction_override` mirrors the runtime override
## (entity-authored impact fractions) so gameplay can pre-align its clock.
func cue_impact_time(cue: String, fraction_override: float = -1.0) -> float:
	var clip := _resolve(cue)
	if clip == "" or player == null:
		return -1.0
	var fraction := _impact_fraction(cue)
	if fraction_override >= 0.0:
		fraction = clampf(fraction_override, 0.05, 0.95)
	if fraction < 0.0:
		return -1.0
	return player.get_animation(clip).length * fraction \
		/ float(CUE_SPEEDS.get(cue, 1.0))

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

func _impact_fraction(cue: String) -> float:
	match cue:
		"heavy":
			return 0.52
		"buff":
			return 0.42
		"cast":
			return 0.46
		"light_1", "light_2", "light_3":
			return 0.48
		_:
			return -1.0

func _update_authored_impact(_delta: float) -> void:
	if player == null or _current_clip == "" or _cue_impact_fired:
		return
	var fraction := _impact_fraction(_current_cue)
	if _impact_fraction_override >= 0.0:
		fraction = _impact_fraction_override
	if fraction < 0.0:
		return
	var animation := player.get_animation(_current_clip)
	if animation == null:
		return
	# Authoritative clip clock: current_animation_position already accounts
	# for speed_scale and the AnimationPlayer's process mode. Self-accumulated
	# process deltas drift against real playback (headless frame-rate
	# clamping and dropped frames included), so threshold on clip time.
	_cue_elapsed = player.current_animation_position
	if _cue_elapsed >= animation.length * fraction:
		_cue_impact_fired = true
		cue_impact.emit(_current_cue)

func _process(delta: float) -> void:
	_update_authored_impact(delta)
	if player == null or not state_provider.is_valid():
		return
	var st: Dictionary = state_provider.call()
	if st.is_empty():
		# Host entity freed (e.g. Visual now rides a TumbleCorpse): freeze on
		# the last pose instead of polling dead captures every frame.
		set_process(false)
		return
	# A new attack press must restart the swing clip even when the cue id is
	# unchanged (combo resets, spaced taps) — otherwise the arm keeps playing
	# the old clip while the blade, FX and damage start over.
	var serial := int(st.get("attack_serial", -1))
	var new_attack: bool = st.get("attacking", false) and serial != -1 and serial != _attack_serial
	if new_attack:
		_attack_serial = serial
	var cue := _pick_cue(st)
	if cue == "":
		return
	if not new_attack and cue == _current_cue and player.is_playing():
		return
	if play_cue(cue, 0.22, new_attack):
		if st.get("attacking", false) and float(st.get("impact_fraction", -1.0)) >= 0.0:
			_impact_fraction_override = clampf(float(st.impact_fraction), 0.05, 0.95)
		_last_cue = cue

func _pick_cue(st: Dictionary) -> String:
	if st.get("dead", false):
		return "death"
	if st.get("hit", false):
		return "hit"
	if st.get("attacking", false):
		# A cast (staff/area/heal) reads as a stance — the knight has no cast
		# clip, so this falls back to idle rather than a walk-swing.
		var attack_cue := str(st.get("attack_cue", ""))
		if not attack_cue.is_empty():
			return attack_cue
		return "cast" if st.get("casting", false) else "light_1"
	if st.get("dodging", false):
		return "dodge"
	if st.get("moving", false):
		return "run" if st.get("running", false) else "walk"
	return "idle"
