extends Node
class_name RealmAudioBeds

## === Realm Audio Beds + Overkill System Audio Wiring ===
##
## Two responsibilities:
##
## 1. REALM AMBIENT BEDS
##    Each realm gets a distinct procedural ambient bed rendered at startup
##    (no external audio files required). Crossfades between realms on transition.
##    Called by RealmManager._play_realm_ambient(realm_id).
##
##    Bramblewood : warm drone + firefly tones + distant owl
##    Mistfen     : cold wind + dripping + distant frog choir
##    Heartwood   : deep rumble + vent hiss + ember crackle
##    Moonfen     : ethereal pad + water lapping + crystalline shimmer
##
## 2. OVERKILL SYSTEM AUDIO WIRING
##    Static helper methods the overkill graphics nodes call for:
##      - Boss phase transitions
##      - Boss enrage activation
##      - Boss crack seam flashes (hit response)
##      - Biome hazard triggers (spore field, vent eruption, column shatter)
##    All routed through AudioManager so volume settings apply.
##
## Usage — add to AutoLoad (optional), or instantiate once in world_manager._ready():
##   var rab := RealmAudioBeds.new()
##   add_child(rab)
##   rab.setup()  # pre-renders all 4 beds

const SYNTH_SR := 44100
const BED_DURATION := 12.0

var _beds     : Dictionary = {}   # realm_id → AudioStreamWAV
var _player   : AudioStreamPlayer = null
var _current  : String = ""
var _fade_t   : float  = 0.0
var _fading   : bool   = false
var _next_realm : String = ""

func setup() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = -24.0
	add_child(_player)
	# Pre-render beds in deferred so _ready() doesn't block the main thread
	call_deferred("_prerender_all")

func _prerender_all() -> void:
	_beds["bramblewood"] = _render_bramblewood()
	_beds["mistfen"]     = _render_mistfen()
	_beds["heartwood"]   = _render_heartwood()
	_beds["moonfen"]     = _render_moonfen()

# ─────────────────────────────────────────────────────────────────────────────
# Bed playback
# ─────────────────────────────────────────────────────────────────────────────

func play_realm_ambient(realm_id: String) -> void:
	if realm_id == _current and _player.playing:
		return
	if not _beds.has(realm_id):
		# Bed not rendered yet — render now (blocking but only once)
		match realm_id:
			"mistfen":   _beds[realm_id] = _render_mistfen()
			"heartwood": _beds[realm_id] = _render_heartwood()
			"moonfen":   _beds[realm_id] = _render_moonfen()
			_:           _beds[realm_id] = _render_bramblewood()
	_next_realm = realm_id
	_fading = true
	_fade_t = 0.0

func _process(delta: float) -> void:
	if not _fading:
		return
	_fade_t += delta
	if _fade_t < 0.5:
		# Fade out
		_player.volume_db = lerpf(-24.0, -60.0, _fade_t / 0.5)
	elif _fade_t < 0.65:
		# Swap stream at silence
		if _current != _next_realm:
			_current = _next_realm
			if _beds.has(_current):
				_player.stream = _beds[_current]
				_player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				_player.stream.loop_begin = 0
				_player.stream.loop_end = int(BED_DURATION * SYNTH_SR)
				_player.play()
	else:
		# Fade in
		_player.volume_db = lerpf(-60.0, -24.0, (_fade_t - 0.65) / 0.65)
		if _fade_t > 1.3:
			_player.volume_db = -24.0
			_fading = false

# ─────────────────────────────────────────────────────────────────────────────
# Overkill system audio wiring (static)
# ─────────────────────────────────────────────────────────────────────────────

static func on_boss_phase(boss: Node3D, phase: int) -> void:
	var audio := boss.get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	if audio.has_method("play_boss_phase_sting"):
		audio.call("play_boss_phase_sting", phase)
	elif audio.has_method("play_victory"):
		audio.call("play_victory")
	if audio.has_method("update_combat_beds"):
		audio.call("update_combat_beds", 0.65 + phase * 0.12)

static func on_boss_enrage(boss: Node3D) -> void:
	var audio := boss.get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	if audio.has_method("play_boss_phase_sting"):
		audio.call("play_boss_phase_sting", 3)
	if audio.has_method("update_combat_beds"):
		audio.call("update_combat_beds", 1.0)

static func on_crack_flash(source: Node3D) -> void:
	var audio := source.get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	if audio.has_method("play_hit"):
		audio.call("play_hit")

static func on_vent_erupted(source: Node3D, pos: Vector3) -> void:
	var audio := source.get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	if audio.has_method("play_synth_at"):
		audio.call("play_synth_at", source, "vent_erupt", 0.0)
	elif audio.has_method("play_enemy_special"):
		audio.call("play_enemy_special")

static func on_column_shattered(source: Node3D, _pos: Vector3) -> void:
	var audio := source.get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	if audio.has_method("play_boss_stomp"):
		audio.call("play_boss_stomp", source)

static func on_spore_hazard(source: Node3D, _pos: Vector3) -> void:
	var audio := source.get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	if audio.has_method("play_synth_at"):
		audio.call("play_synth_at", source, "spore_cloud", 0.0)

# ─────────────────────────────────────────────────────────────────────────────
# Procedural bed renderers
# ─────────────────────────────────────────────────────────────────────────────

func _make_wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format     = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate   = SYNTH_SR
	wav.stereo     = false
	var bytes      := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		var s := clampf(b[i], -1.0, 1.0)
		var v := int(s * 32767.0)
		bytes[i * 2]     = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	wav.data = bytes
	return wav

func _render_bramblewood() -> AudioStreamWAV:
	var n := int(BED_DURATION * SYNTH_SR)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / SYNTH_SR
		# Warm drone (D2 + A2 + D3)
		var drone := (sin(TAU * 73.4 * t) * 0.22
			+ sin(TAU * 110.0 * t + 0.5) * 0.14
			+ sin(TAU * 146.8 * t + 1.1) * 0.10)
		# Firefly shimmer
		var shimmer := sin(TAU * 880.0 * t) * 0.03 * sin(TAU * 0.8 * t + 0.3)
		# Soft wind noise (LCG rand)
		var rng_val := fmod(float(i * 1664525 + 1013904223) / 4294967296.0, 1.0) * 2.0 - 1.0
		var wind    := rng_val * 0.018 * (0.5 + 0.5 * sin(TAU * 0.25 * t))
		b[i] = drone + shimmer + wind
	return _make_wav(b)

func _render_mistfen() -> AudioStreamWAV:
	var n := int(BED_DURATION * SYNTH_SR)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / SYNTH_SR
		# Cold wind low pad (Bb1 + F2)
		var pad := (sin(TAU * 58.27 * t) * 0.18
			+ sin(TAU * 87.31 * t + 1.2) * 0.12)
		# Drip tone (high-frequency ping, 4 per loop)
		var drip := 0.0
		for d in 4:
			var dt := fmod(t - float(d) * 3.0, BED_DURATION)
			if dt >= 0 and dt < 0.08:
				drip += sin(TAU * 1760.0 * dt) * exp(-dt * 55.0) * 0.06
		# Cold wind noise
		var rng_v := fmod(float(i * 22695477 + 1) / 4294967296.0, 1.0) * 2.0 - 1.0
		var wind  := rng_v * 0.022 * (0.4 + 0.6 * sin(TAU * 0.18 * t + 0.5))
		b[i] = pad + drip + wind
	return _make_wav(b)

func _render_heartwood() -> AudioStreamWAV:
	var n := int(BED_DURATION * SYNTH_SR)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / SYNTH_SR
		# Deep ember rumble (E1 + B1 subwoofer)
		var rumble := (sin(TAU * 41.2 * t) * 0.20
			+ sin(TAU * 61.7 * t + 0.8) * 0.14)
		# Vent hiss (filtered noise burst every 3s)
		var hiss := 0.0
		var vent_t := fmod(t, 3.0)
		if vent_t < 0.35:
			var rng_v2 := fmod(float(i * 134775813 + 1) / 4294967296.0, 1.0) * 2.0 - 1.0
			hiss = rng_v2 * 0.028 * (1.0 - vent_t / 0.35)
		# Ember crackle (sparse clicks)
		var crack := 0.0
		if fmod(float(i), 22050.0) < 12.0:
			crack = sin(TAU * 4200.0 * float(i % 12) / 12.0) * 0.04
		b[i] = rumble + hiss + crack
	return _make_wav(b)

func _render_moonfen() -> AudioStreamWAV:
	var n := int(BED_DURATION * SYNTH_SR)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / SYNTH_SR
		# Ethereal crystal pad (C#3 + G#3 + C#4)
		var pad := (sin(TAU * 138.6 * t) * 0.16
			+ sin(TAU * 207.7 * t + 0.7) * 0.11
			+ sin(TAU * 277.2 * t + 1.4) * 0.07)
		# Water lap (slow sine AM noise)
		var rng_v3 := fmod(float(i * 6364136223846793005 + 1442695040888963407) / 9223372036854775808.0, 1.0) * 2.0 - 1.0
		var lap    := rng_v3 * 0.015 * (0.5 + 0.5 * sin(TAU * 0.35 * t))
		# Shimmer overtone
		var shimmer := sin(TAU * 2637.0 * t) * 0.018 * sin(TAU * 0.55 * t + 0.9)
		b[i] = pad + lap + shimmer
	return _make_wav(b)
