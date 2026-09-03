extends Node

## === Audio Manager — chime synthesis style from embervale ===
## Layered procedural SFX engine on top of the classic chime synth:
## named cues rendered offline-per-session into cached WAV variants,
## driven by assets/audio/audio_config.tres (volume / pitch / bus / count),
## positional playback via play_synth_at(), and looping environment beds.

@export var master_volume: float = 1.0
@export var sfx_volume: float = 0.8
@export var music_volume: float = 0.6

var players: Dictionary = {}
var music_player: AudioStreamPlayer = null
var ambient_playing: bool = false

# === Reactive combat bed (WorldState-driven intensity crossfade) ===
const BED_DURATION := 12.0
var _combat_player: AudioStreamPlayer = null
var _combat_stream: AudioStreamWAV = null
var _bed_target_db := -60.0
var _bed_live := false
var _bed_bus := -1
var _cue_live := 0
const CUE_PLAYER_CAP := 14

## Every transient one-shot voice joins this group so stop_one_shots() can
## hard-stop and free them (teardown must never leave an AudioServer playback
## alive after its host scene is gone).
const ONE_SHOT_GROUP := "audio_one_shot"

# === Synchronized boss score (three fixed voices, one shared loop clock) ===
const BOSS_SCORE_DURATION := 12.0
const BOSS_SCORE_LAYER_CAP := 3
var _boss_score_players: Array[AudioStreamPlayer] = []
var _boss_score_streams: Array[AudioStreamWAV] = []
var _boss_score_targets: Array[float] = [-14.0, -60.0, -60.0]
var boss_score_phase: int = -1
var boss_score_active := false
var _boss_score_fading := false

# === Synth cue engine state ===
const SYNTH_SR := 44100
var cue_config: AudioCueConfig = null
var _cue_streams: Dictionary = {}   # cue name -> Array[AudioStreamWAV]

const SETTINGS_PATH := "user://embervale_settings.cfg"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep music/UI sounds alive behind frozen-world interfaces
	_load_settings()
	_apply_volumes()
	_load_cue_config()

func _process(delta: float) -> void:
	_update_boss_score(delta)
	# Ease the combat bed toward its intensity target; stop when idle long.
	if _combat_player == null:
		return
	var cur := db_to_linear(_combat_player.volume_db)
	var goal := db_to_linear(_bed_target_db)
	cur = lerpf(cur, goal, minf(delta * 2.5, 1.0))
	if not _bed_live or cur < 0.004:
		if _combat_player.playing:
			_combat_player.stop()
		return
	if not _combat_player.playing:
		_combat_player.play()
	_combat_player.volume_db = linear_to_db(cur)

## Called every frame by WorldState: crossfades the tense bed in with combat
## intensity; `night` muffles the bed's highs (dread reads better muffled).
func update_combat_beds(intensity: float, night: float = 0.0) -> void:
	_bed_target_db = lerpf(-52.0, -8.0, pow(clampf(intensity, 0.0, 1.0), 1.4))
	if boss_score_active:
		_bed_target_db = minf(_bed_target_db, -24.0)
	if intensity <= 0.02:
		_bed_live = false
		return
	if _combat_player == null:
		if _combat_stream == null:
			var b := PackedFloat32Array()
			b.resize(int(BED_DURATION * SYNTH_SR))
			_render_combat_bed(b, BED_DURATION)
			_combat_stream = _to_wav(b)
			_combat_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			_combat_stream.loop_begin = 0
			_combat_stream.loop_end = b.size()
		_combat_player = AudioStreamPlayer.new()
		add_child(_combat_player)
		_combat_player.stream = _combat_stream
		_combat_player.bus = _ensure_bed_bus_name()
		_combat_player.volume_db = -60.0
	_bed_live = true
	# Night low-pass on the dedicated bus (day = open highs, night = dread)
	var idx := AudioServer.get_bus_index("CombatBed")
	if idx >= 0 and AudioServer.get_bus_effect_count(idx) > 0:
		var lp := AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter
		if lp != null:
			lp.cutoff_hz = lerpf(15000.0, 4200.0, clampf(night, 0.0, 1.0))

## Dedicated bus so the bed filter never touches Music/SFX settings.
func _ensure_bed_bus_name() -> String:
	var idx := AudioServer.get_bus_index("CombatBed")
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "CombatBed")
		AudioServer.set_bus_send(idx, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 12000.0
		AudioServer.add_bus_effect(idx, lp)
	return "CombatBed"

## Tense layer over the ambient pads: minor-second drone, loop-locked heart
## thumps (4 per bar of 12s), and a thin anxious shimmer.
func _render_combat_bed(b: PackedFloat32Array, duration: float) -> void:
	var rate := SYNTH_SR
	for i in b.size():
		var t := i / float(rate)
		var w := TAU / duration
		var swell := 0.7 + 0.3 * sin(w * t + 0.9)
		b[i] += 0.05 * swell * (
			sin(TAU * 110.0 * t) * 0.8
			+ sin(TAU * 116.54 * t + 0.4) * 0.6
			+ sin(TAU * 220.0 * t + 1.1) * 0.22)
	for beat in 4:  # loop-locked heartbeat at 3s spacing
		_sweep_tone(b, beat * 3.0, 0.16, 74.0, 42.0, 0.34, 9.0)
		_sweep_tone(b, beat * 3.0 + 0.14, 0.13, 62.0, 38.0, 0.26, 10.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260825
	for k in 20:  # whole-cycle shimmer grains keep the loop seamless
		var bt := fposmod(rng.randf(), duration - 0.3)
		_tone_at(b, bt, 0.18, 1244.5 + rng.randf() * 300.0, 0.012, 12.0, 2)

## Starts all three layers on the same audio frame. Repeated calls reuse the
## cached streams and never create more voices.
func start_boss_score(_boss_id: String = "matriarch") -> void:
	if _boss_score_streams.is_empty():
		for layer in BOSS_SCORE_LAYER_CAP:
			var samples := PackedFloat32Array()
			samples.resize(int(BOSS_SCORE_DURATION * SYNTH_SR))
			_render_boss_score_layer(samples, layer)
			var stream := _to_wav(samples)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = samples.size()
			_boss_score_streams.append(stream)
	while _boss_score_players.size() < BOSS_SCORE_LAYER_CAP:
		var player := AudioStreamPlayer.new()
		player.name = "BossScoreLayer%d" % _boss_score_players.size()
		player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_boss_score_players.append(player)
	for i in BOSS_SCORE_LAYER_CAP:
		var player := _boss_score_players[i]
		player.stream = _boss_score_streams[i]
		player.volume_db = -60.0
		player.play(0.0)
	boss_score_active = true
	_boss_score_fading = false
	set_boss_score_phase(0)

func set_boss_score_phase(phase: int) -> void:
	if _boss_score_players.is_empty():
		return
	boss_score_phase = clampi(phase, 0, 3)
	match boss_score_phase:
		0: _boss_score_targets = [-14.0, -40.0, -60.0]
		1: _boss_score_targets = [-13.0, -22.0, -42.0]
		2: _boss_score_targets = [-12.0, -15.0, -22.0]
		_: _boss_score_targets = [-10.0, -9.0, -11.0]

func reset_boss_score() -> void:
	if boss_score_active:
		set_boss_score_phase(0)

func finish_boss_score(victory: bool = true) -> void:
	if not _boss_score_players.is_empty():
		_boss_score_targets = [-60.0, -60.0, -60.0]
		_boss_score_fading = true
	if victory:
		play_boss_victory_stinger()

func stop_boss_score_immediate() -> void:
	for player in _boss_score_players:
		if is_instance_valid(player):
			player.stop()
			player.volume_db = -60.0
	boss_score_active = false
	_boss_score_fading = false
	boss_score_phase = -1

func _update_boss_score(delta: float) -> void:
	if _boss_score_players.is_empty():
		return
	var all_silent := true
	for i in mini(_boss_score_players.size(), _boss_score_targets.size()):
		var player := _boss_score_players[i]
		if not is_instance_valid(player):
			continue
		player.volume_db = move_toward(player.volume_db,
			_boss_score_targets[i], delta * 26.0)
		if player.volume_db > -55.0:
			all_silent = false
	if _boss_score_fading and all_silent:
		stop_boss_score_immediate()

## Loop-locked layers: root drone, bark-heart percussion, then thorn ostinato.
func _render_boss_score_layer(buffer: PackedFloat32Array, layer: int) -> void:
	var duration := BOSS_SCORE_DURATION
	match layer:
		0:
			for i in buffer.size():
				var t := i / float(SYNTH_SR)
				var swell := 0.72 + 0.28 * sin(TAU * t / duration)
				buffer[i] = 0.052 * swell * (sin(TAU * 55.0 * t)
					+ 0.56 * sin(TAU * 82.5 * t + 0.4)
					+ 0.28 * sin(TAU * 110.0 * t + 1.0))
		1:
			for beat in 8:
				var at := float(beat) * 1.5
				_sweep_tone(buffer, at, 0.22, 76.0, 43.0, 0.30, 10.0)
				_sweep_tone(buffer, at + 0.20, 0.16, 62.0, 38.0, 0.22, 12.0)
		2:
			var notes := [220.0, 233.333333, 165.0, 220.0]
			for step in 24:
				var at := float(step) * 0.5
				_tone_at(buffer, at, 0.24, notes[step % notes.size()],
					0.042, 9.0, 3)

## Escalating boss stage roar: pitch and dissonance rise with the stage.
## Bounded voice count (4 chimes max) so stage transitions never flood the bus.
func play_boss_phase_roar(phase_rank: int = 0) -> void:
	var rank := clampi(phase_rank, 0, 3)
	var base: float = [55.0, 65.4, 77.8, 92.5][rank]
	play_chime(base, 0.0, 0.34 + 0.04 * float(rank), 0.07)
	play_chime(base * 1.5, 0.03, 0.28, 0.05)
	if rank >= 2:
		play_chime(base * 2.02, 0.06, 0.24, 0.04)  # dissonant beat = fury
	if rank >= 3:
		play_chime(base * 3.01, 0.09, 0.2, 0.035)

func play_boss_victory_stinger() -> void:
	play_chime(220.0, 0.0, 0.32, 0.055)
	await get_tree().create_timer(0.12, true, false, true).timeout
	play_chime(329.63, 0.0, 0.34, 0.06)
	await get_tree().create_timer(0.14, true, false, true).timeout
	play_chime(440.0, 0.0, 0.48, 0.065)

func _load_cue_config() -> void:
	if ResourceLoader.exists("res://assets/audio/audio_config.tres"):
		cue_config = load("res://assets/audio/audio_config.tres")

func _apply_volumes() -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))
	var sfx_idx = AudioServer.get_bus_index("SFX")
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))
	var music_idx = AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))

# === Settings persistence ===
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	sfx_volume = clampf(cfg.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
	music_volume = clampf(cfg.get_value("audio", "music", music_volume), 0.0, 1.0)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.save(SETTINGS_PATH)

# === Procedural Chimes (embervale-style) ===
func play_chime(frequency: float, start_offset: float = 0.0, duration: float = 0.15, volume: float = 0.05, wave_type: int = AudioStreamWAV.FORMAT_16_BITS) -> void:
	var player = AudioStreamPlayer.new()
	player.add_to_group(ONE_SHOT_GROUP)
	add_child(player)
	
	# Generate simple sine chime as 16-bit stereo PCM
	var sample_rate = 44100
	var samples = int(sample_rate * duration)
	var bytes = PackedByteArray()
	bytes.resize(samples * 4)

	for i in range(samples):
		var t = (i + start_offset * sample_rate) / sample_rate
		var env = exp(-t * 8.0)  # Exponential decay
		var v = int(clampf(sin(TAU * frequency * t) * env * volume * 10.0, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 4, v)
		bytes.encode_s16(i * 4 + 2, v)

	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = true
	stream.data = bytes
	
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume)
	player.play()
	
	await player.finished
	player.queue_free()

# === Predefined Cues ===
func play_ui_blip() -> void:
	# Triad: 392Hz + 587Hz delayed
	play_chime(392.0, 0.0, 0.12, 0.045)
	await get_tree().create_timer(0.075).timeout
	play_chime(587.33, 0.0, 0.16, 0.038)

func play_ui_back() -> void:
	play_chime(493.88, 0.0, 0.11, 0.04)
	await get_tree().create_timer(0.06).timeout
	play_chime(329.63, 0.0, 0.13, 0.035)

func play_loot_fanfare() -> void:
	# Ascending triad
	play_chime(523.25, 0.0, 0.18, 0.05)
	await get_tree().create_timer(0.08).timeout
	play_chime(659.25, 0.0, 0.18, 0.05)
	await get_tree().create_timer(0.09).timeout
	play_chime(783.99, 0.0, 0.18, 0.05)

# === Weapon cues ===
## Breath-swish at the top of a swing's wind-up; pitch rises with combo step.
func play_whoosh(pitch_scale: float = 1.0) -> void:
	play_chime(300.0 * pitch_scale, 0.0, 0.09, 0.028)
	await get_tree().create_timer(0.04).timeout
	play_chime(180.0 * pitch_scale, 0.0, 0.09, 0.024)

## Combo-aware layered whooshes (opening / reverse / overhead finisher).
## The synth cue sits under a recorded CC0 swipe so every slash animation
## carries a real air-cut; variants mirror the combo stage's weight.
func play_swing_stage(combo_step: int) -> void:
	match clampi(combo_step, 0, 2):
		1:
			play_cue("swing_reverse")
			play_fx(["swipe_mid"], -8.0)
		2:
			play_cue("swing_finisher")
			play_fx(["swipe_heavy"], -7.0)
		_:
			play_cue("swing_open")
			play_fx(["swipe_light"], -8.0)

func play_slash() -> void:
	play_cue("slash_impact")
	play_fx(["swing", "swing2", "swing3"], -9.0)

func play_magic_cast() -> void:
	play_cue("magic_cast")
	play_fx(["magic1", "spell"], -11.0)

# === Skill rite SFX director ===
## One call at cast start: a shared gather shimmer plus the rite family's
## signature cue, so every skill sounds distinct yet related.
func play_skill_cast(skill_type: String) -> void:
	play_cue("skill_charge")
	match skill_type:
		"whirl":
			play_cue("skill_whirl_spin")
		"dash_strike":
			play_cue("skill_dash_zip")
		_:
			pass

## One call at the payload moment (bolt launch, comet call, bloom pop).
func play_skill_release(skill_type: String) -> void:
	match skill_type:
		"explosion":
			play_cue("skill_hurl")
		"comet":
			play_cue("comet_fall")
		"heal_bloom":
			play_cue("heal_bloom_cue")
		"aoe":
			play_cue("skill_whirl_spin")
		_:
			pass

func play_explosion() -> void:
	play_cue("explosion")

func play_heal() -> void:
	play_cue("heal_bloom_cue")
	await get_tree().create_timer(0.30).timeout
	play_chime(1046.5, 0.0, 0.22, 0.04)
	play_fx(["spell"], -14.0)

# === Recorded foley layer ("RPG Sound Pack", CC0 — opengameart.org) ===
## Plays one of the given foley wav variants with light pitch jitter so
## repeats never sound identical. Lookup order: bundled res:// copy, then
## user:// cache (a lazy online download of the pack), then quietly nothing
## while the synth bed still plays — no crashes, no UI spam.
const SFX_CACHE_DIR := "user://sfx_cache"
const SFX_PACK_URL := "https://opengameart.org/sites/default/files/rpg_sound_pack.zip"
const SFX_ZIP_PREFIX := "RPG Sound Pack/battle/"
## Known foley variant ids — the exact set referenced by play_fx() call sites.
## The lazy download only ever reads these fixed entries from the pack.
const SOUND_VARIANTS := [
	"swipe_mid", "swipe_heavy", "swipe_light",
	"swing", "swing2", "swing3", "magic1", "spell",
]
## Bounds for the download and the extracted wav, so a mutated oversized remote
## pack cannot inflate memory or write an oversized blob into the user cache.
const SFX_PACK_MAX_BYTES := 32 * 1024 * 1024
const SFX_ENTRY_MAX_BYTES := 8 * 1024 * 1024
var _sfx_fetching := {}

func play_fx(variants: Array, volume_db: float = -6.0) -> void:
	if variants.is_empty():
		return
	var name := str(variants[randi() % variants.size()])
	var path := _sfx_local_path(name)
	if path == "":
		_fetch_sfx(name)
		return
	var player := play_sfx(path, volume_db) if path.begins_with("res://") \
		else _play_wav_from_disk(path, volume_db)
	if player:
		player.pitch_scale = randf_range(0.94, 1.06)

func _sfx_local_path(name: String) -> String:
	var res_path := "res://assets/audio/fx/%s.wav" % name
	if ResourceLoader.exists(res_path):
		return res_path
	var cache_path := "%s/%s.wav" % [SFX_CACHE_DIR, name]
	if FileAccess.file_exists(cache_path):
		return cache_path
	return ""

func _play_wav_from_disk(path: String, volume_db: float) -> AudioStreamPlayer:
	var wav := AudioStreamWAV.load_from_file(path) as AudioStreamWAV
	if wav == null:
		return null
	var player := AudioStreamPlayer.new()
	player.add_to_group(ONE_SHOT_GROUP)
	add_child(player)
	player.stream = wav
	player.volume_db = volume_db + linear_to_db(sfx_volume)
	player.play()
	player.finished.connect(_on_sfx_finished.bind(player))
	return player

## Async online fetch: downloads the pack zip once into user:// cache, then
## extracts the requested wav entry in place. When offline every step just
## returns; a future call retries from where it left off.
func _fetch_sfx(name: String) -> void:
	if _sfx_fetching.has(name):
		return
	# `name` must be one of the known variant ids so the zip entry we read is a
	# fixed, bundled path — never a path assembled from player input.
	if name.is_empty() or name.count("/") > 0 or not _known_sfx_variant(name):
		_sfx_release(name)
		return
	_sfx_fetching[name] = true
	DirAccess.make_dir_recursive_absolute(SFX_CACHE_DIR)
	var zip_path := "%s/rpg_sound_pack.zip" % SFX_CACHE_DIR
	if not FileAccess.file_exists(zip_path):
		var http := HTTPRequest.new()
		add_child(http)
		http.timeout = 20.0
		var err := http.request(SFX_PACK_URL)
		if err != OK:
			_sfx_release(name, http)
			return
		var resp: Array = await http.request_completed
		http.queue_free()
		if int(resp[0]) != HTTPRequest.RESULT_SUCCESS or int(resp[1]) != 200:
			_sfx_release(name)
			return
		var body: PackedByteArray = resp[3]
		# Guard the lazy pack download so a mutated/oversized remote payload
		# cannot inflate memory or write an oversized blob to the user cache.
		if body.size() > SFX_PACK_MAX_BYTES:
			push_warning("AudioManager: sound pack download rejected (too large)")
			_sfx_release(name)
			return
		var wf := FileAccess.open(zip_path, FileAccess.WRITE)
		wf.store_buffer(body)
		wf.close()
	var zipped := "%s/%s.wav" % [SFX_ZIP_PREFIX, name]
	var zip := ZIPReader.new()
	var ok_open := zip.open(zip_path) == OK
	if ok_open and zip.file_exists(zipped):
		var wav := zip.read_file(zipped)
		if wav.size() > SFX_ENTRY_MAX_BYTES:
			push_warning("AudioManager: sfx entry rejected (too large) -> %s" % name)
		elif wav.size() > 0:
			var out := "%s/%s.wav" % [SFX_CACHE_DIR, name]
			var of := FileAccess.open(out, FileAccess.WRITE)
			of.store_buffer(wav)
			of.close()
	if ok_open:
		zip.close()
	_sfx_release(name)

func _known_sfx_variant(name: String) -> bool:
	return SOUND_VARIANTS.has(name)

func _sfx_release(name: String, node_to_free: Node = null) -> void:
	_sfx_fetching.erase(name)
	if node_to_free:
		node_to_free.queue_free()

func play_hit() -> void:
	play_chime(220.0, 0.0, 0.08, 0.06)

func play_hurt() -> void:
	play_chime(164.81, 0.0, 0.12, 0.07)

func play_victory() -> void:
	play_chime(523.25, 0.0, 0.25, 0.06)
	await get_tree().create_timer(0.1).timeout
	play_chime(659.25, 0.0, 0.25, 0.055)
	await get_tree().create_timer(0.1).timeout
	play_chime(783.99, 0.0, 0.3, 0.05)

func play_defeat() -> void:
	play_chime(130.81, 0.0, 0.4, 0.08)
	await get_tree().create_timer(0.15).timeout
	play_chime(110.0, 0.0, 0.4, 0.07)

func play_dash() -> void:
	play_cue("dodge_roll")

func play_footstep(speed_ratio: float = 1.0) -> void:
	var pitch = 118.0 + speed_ratio * 24.0
	play_chime(pitch, 0.0, 0.055, 0.018)

## Surface-aware footsteps: the world passes its realm surface in.
func play_footstep_surface(surface: String, speed_ratio: float = 1.0) -> void:
	match surface:
		"mud":
			play_cue("footstep_mud")
		"stone":
			play_cue("footstep_stone")
		_:
			play_cue("footstep_grass")

## Pendulum-driven lantern life: hum on the pulse timer, creak on swings.
func play_lantern_hum(speed_ratio: float = 0.0) -> void:
	play_cue("lantern_hum")

func play_lantern_creak() -> void:
	play_cue("lantern_creak")

func play_lantern_pulse(speed_ratio: float = 0.0) -> void:
	var pitch = 276.0 + speed_ratio * 56.0
	play_chime(pitch, 0.0, 0.11, 0.022 + speed_ratio * 0.008)

## Bright lock-on stinger, played at the marked foe so the source reads.
func play_lantern_lock(at_node: Node = null) -> void:
	if at_node != null:
		play_synth_at(at_node, "lantern_lock")
	else:
		play_cue("lantern_lock")

## Soft "mark forgotten" descent; gentle enough for every tap-to-move.
func play_lantern_release(at_node: Node = null) -> void:
	if at_node != null:
		play_synth_at(at_node, "lantern_release", -4.0)
	else:
		play_cue("lantern_release")

## Harsh short buzz when a rite is refused for lack of a lit mark.
func play_lantern_refuse() -> void:
	play_cue("lantern_refuse")

func play_boss_stomp(at_node: Node = null) -> void:
	if at_node != null:
		play_synth_at(at_node, "boss_stomp")
	else:
		play_cue("boss_stomp")

func play_boss_death() -> void:
	play_cue("boss_death")

# --- UI / forge ---
func play_ui_confirm() -> void:
	play_cue("ui_confirm")

func play_ui_cancel() -> void:
	play_cue("ui_cancel")

func play_forge_success() -> void:
	play_cue("forge_success")

func play_enemy_telegraph() -> void:
	play_cue("hushling_telegraph")

func play_enemy_special() -> void:
	play_cue("spore_burst")

# === Boss/enemy SFX profiles (player-chosen flavor) ===
## Parameter sets over the chime synth: freq scale, decay stretch, volume.
## Locked boss stingers never route through here — only generic cues do.
const SFX_PROFILES := {
	"vanilla": {},
	"hollow_resin": {"freq": 1.35, "decay": 0.70, "vol": 0.90},
	"grave_moss": {"freq": 0.72, "decay": 1.60, "vol": 1.10},
	"ember_glass": {"freq": 1.62, "decay": 0.55, "vol": 1.22},
}

## kind ∈ {"telegraph", "stomp", "cast", "vocal"}; vanilla is a no-op so the
## original cue set stays untouched for un-customized bosses.
func play_profile_cue(preset: String, kind: String) -> void:
	var p: Dictionary = SFX_PROFILES.get(preset, {})
	if p.is_empty():
		return
	var f := float(p.freq)
	var d := float(p.decay)
	var v := float(p.vol)
	match kind:
		"telegraph":
			play_chime(92.5 * f, 0.0, 0.22 * d, 0.035 * v)
		"stomp":
			play_chime(64.0 * f, 0.0, 0.26 * d, 0.06 * v)
			play_chime(48.0 * f, 0.02, 0.30 * d, 0.05 * v)
		"cast":
			play_chime(146.8 * f, 0.0, 0.16 * d, 0.05 * v)
			play_chime(220.0 * f, 0.05, 0.20 * d, 0.04 * v)
		"vocal":
			play_chime(58.0 * f, 0.0, 0.34 * d, 0.06 * v)
			play_chime(87.0 * f, 0.06, 0.26 * d, 0.045 * v)

# === Procedural Ambient Pad ===
## Seamless 12-second loop; every partial completes whole cycles so the
## loop point is inaudible. Called once from the grove.
## bed: "grove" (crickets over warm pad) or "fen" (bubbles over cold drone).
func start_ambient(bed: String = "grove") -> void:
	if ambient_playing:
		return
	ambient_playing = true

	var duration := 12.0
	var rate := SYNTH_SR
	var samples := int(duration * rate)
	var b := PackedFloat32Array()
	b.resize(samples)

	match bed:
		"fen":
			_render_fen_bed(b, duration)
		_:
			_render_grove_bed(b, duration)

	var bytes := PackedByteArray()
	bytes.resize(samples * 4)
	for i in samples:
		var v := int(clampf(b[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 4, v)
		bytes.encode_s16(i * 4 + 2, v)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = true
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	stream.data = bytes

	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.stream = stream
	music_player.volume_db = linear_to_db(music_volume) - 6.0  # beds sit under combat SFX
	music_player.play()

func _render_grove_bed(b: PackedFloat32Array, duration: float) -> void:
	var rate := SYNTH_SR
	for i in b.size():
		var t := i / float(rate)
		var w := TAU / duration
		var swell := 0.55 + 0.45 * sin(w * t)
		var drift := 0.75 + 0.25 * sin(w * 3.0 * t + 1.7)
		b[i] = 0.05 * swell * drift * (
			sin(TAU * 110.0 * t) * 0.9
			+ sin(TAU * 165.0 * t + 0.6) * 0.55
			+ sin(TAU * 220.0 * t + 1.2) * 0.32
			+ sin(TAU * 330.0 * t) * 0.16)

func _render_fen_bed(b: PackedFloat32Array, duration: float) -> void:
	# Cold drone bed + whole-cycle bubbles so the loop stays seamless
	var rate := SYNTH_SR
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260824
	for k in 26:  # bubbles at loop-locked positions
		var bt := fposmod(rng.randf(), duration)
		_sweep_tone(b, bt, 0.09, 140.0 * (1.0 + rng.randf()), rng.randf_range(2.0, 3.4),
			0.05, 14.0)
	for i in b.size():
		var t := i / float(rate)
		var w := TAU / duration
		b[i] += 0.045 * (
			sin(TAU * 82.4 * t) * 0.8
			+ sin(TAU * 123.5 * t + 0.9) * 0.45
			+ sin(TAU * 246.9 * t + 2.1) * 0.18) \
			* (0.7 + 0.3 * sin(w * 2.0 * t))

# === Synth cue engine ===
## Renders each named cue into cached WAV variants (seeded per variant so
## the same name always yields the same set), then plays with config rules.

func play_cue(cue_name: String) -> void:
	var streams := _get_cue_streams(cue_name)
	if streams.is_empty():
		return
	# Pool hygiene: cap concurrent one-shots so bursts never pile up voices
	if _cue_live >= CUE_PLAYER_CAP:
		return
	_cue_live += 1
	var stream: AudioStreamWAV = streams[randi() % streams.size()]
	var cfg := _cue_cfg(cue_name)
	var player := AudioStreamPlayer.new()
	player.add_to_group(ONE_SHOT_GROUP)
	add_child(player)
	player.stream = stream
	player.volume_db = float(cfg.get("volume_db", -8.0))
	player.pitch_scale = randf_range(float(cfg.get("pitch_min", 0.95)),
		float(cfg.get("pitch_max", 1.05)))
	var bus := str(cfg.get("bus", "SFX"))
	if AudioServer.get_bus_index(bus) >= 0:
		player.bus = bus
	player.finished.connect(_on_cue_finished.bind(player))
	player.play()

func _on_cue_finished(player: AudioStreamPlayer) -> void:
	_cue_live = maxi(0, _cue_live - 1)
	player.queue_free()

## Hard cleanup for every transient one-shot voice: cues, chimes, positional
## synth-at players and disk foley. Stops playback immediately (so the
## AudioServer releases its AudioStreamPlaybackWAV instead of leaking it when
## the host scene dies mid-play) and queues the players for freeing.
## Idempotent; safe to call during scene teardown or on quit.
func stop_one_shots() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(ONE_SHOT_GROUP):
		var player := node as Node
		if not is_instance_valid(player):
			continue
		if player is AudioStreamPlayer:
			(player as AudioStreamPlayer).stop()
		elif player is AudioStreamPlayer3D:
			(player as AudioStreamPlayer3D).stop()
		player.queue_free()
	# Freed one-shots never reach `finished`, so release the voice counter
	# here or the CUE_PLAYER_CAP would stay consumed for the session.
	_cue_live = 0

## Full session/realm teardown: looping beds (ambient + reactive combat bed),
## boss score voices, and every one-shot. Anything still playing at quit or
## realm swap would leak its AudioStreamPlaybackWAV even though the player
## node itself is freed correctly, so teardown must stop playback first.
func stop_all_playback() -> void:
	stop_one_shots()
	if music_player != null and is_instance_valid(music_player):
		music_player.stop()
		ambient_playing = false
	if _combat_player != null and is_instance_valid(_combat_player):
		_combat_player.stop()
		_bed_live = false
	stop_boss_score_immediate()

## Positional playback for world-space events (stomps, bursts, deaths).
func play_synth_at(host: Node, cue_name: String, volume_db_offset := 0.0) -> void:
	# is_instance_valid first: a freed host reference must fall back to the
	# non-positional cue instead of erroring on is_inside_tree().
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		play_cue(cue_name)
		return
	var streams := _get_cue_streams(cue_name)
	if streams.is_empty():
		return
	var cfg := _cue_cfg(cue_name)
	var p := AudioStreamPlayer3D.new()
	p.add_to_group(ONE_SHOT_GROUP)
	host.add_child(p)
	p.global_position = host.global_position
	p.stream = streams[randi() % streams.size()]
	p.volume_db = float(cfg.get("volume_db", -8.0)) + volume_db_offset
	p.unit_size = 16.0
	p.max_db = 3.0
	var bus := str(cfg.get("bus", "SFX"))
	if AudioServer.get_bus_index(bus) >= 0:
		p.bus = bus
	p.finished.connect(p.queue_free)
	p.play()

func _cue_cfg(cue_name: String) -> Dictionary:
	if cue_config != null and cue_config.cues.has(cue_name):
		return cue_config.cues[cue_name]
	return {}

func _get_cue_streams(cue_name: String) -> Array:
	if _cue_streams.has(cue_name):
		return _cue_streams[cue_name]
	var variants := int(_cue_cfg(cue_name).get("variants", 2))
	var arr: Array = []
	for v in variants:
		arr.append(_to_wav(_render_cue(cue_name, v)))
	_cue_streams[cue_name] = arr
	return arr

func _cue_rng(cue_name: String, variant: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(hash(cue_name)) * 31 + variant * 7919
	return r

func _render_cue(name_: String, variant: int) -> PackedFloat32Array:
	var rng := _cue_rng(name_, variant)
	var b := PackedFloat32Array()
	match name_:
		# --- Hero movement ---
		"footstep_grass":
			b.resize(int(0.10 * SYNTH_SR))
			_crackle(b, rng, 0.0, 0.06, 40.0, 0.35)
			_noise(b, rng, 0.005, 0.07, 0.30, 34.0, 0.22)
			_sweep_tone(b, 0.0, 0.05, 110.0, 70.0, 0.28, 30.0)
		"footstep_mud":
			b.resize(int(0.16 * SYNTH_SR))
			_noise(b, rng, 0.0, 0.13, 0.42, 20.0, 0.12)
			_sweep_tone(b, 0.02, 0.07, 190.0, 65.0, 0.30, 22.0)
			_crackle(b, rng, 0.03, 0.08, 18.0, 0.25)
		"footstep_stone":
			b.resize(int(0.09 * SYNTH_SR))
			_noise(b, rng, 0.0, 0.025, 0.5, 60.0, 0.85)   # bright click
			_sweep_tone(b, 0.004, 0.06, 82.0, 55.0, 0.38, 26.0)
			_crackle(b, rng, 0.01, 0.04, 14.0, 0.2)
		"dodge_roll":
			b.resize(int(0.26 * SYNTH_SR))
			_crackle(b, rng, 0.0, 0.13, 55.0, 0.30)        # cloth rustle
			_noise(b, rng, 0.02, 0.22, 0.34, 16.0, 0.30, 0.10)  # ground slide
		# --- Hero combat ---
		"swing_open":
			b.resize(int(0.17 * SYNTH_SR))
			_whoosh(b, rng, 0.0, 0.16, 0.5, 0.14, 0.85)
		"swing_reverse":
			b.resize(int(0.20 * SYNTH_SR))
			_whoosh(b, rng, 0.0, 0.19, 0.6, 0.16, 0.55)    # faster attack
		"swing_finisher":
			b.resize(int(0.34 * SYNTH_SR))
			_whoosh(b, rng, 0.0, 0.27, 0.62, 0.10, 0.35)   # deeper sweep
			_sweep_tone(b, 0.20, 0.12, 72.0, 46.0, 0.5, 18.0)
			_crackle(b, rng, 0.21, 0.10, 22.0, 0.2)
		"magic_cast":
			b.resize(int(0.55 * SYNTH_SR))
			_hum(b, 0.0, 0.44, 84.0, 176.0, 0.30, 3)
			_sweep_tone(b, 0.40, 0.12, 1240.0, 900.0, 0.22, 16.0)  # snap
		"slash_impact":
			b.resize(int(0.11 * SYNTH_SR))
			_noise(b, rng, 0.0, 0.03, 0.5, 55.0, 0.8)
			_sweep_tone(b, 0.005, 0.09, 1450.0, 680.0, 0.30, 15.0)
		# --- Skill rites (one signature cue per rite family) ---
		"skill_charge":
			# Rising gather: hum climbs while embers crackle at the hand
			b.resize(int(0.50 * SYNTH_SR))
			_hum(b, 0.0, 0.42, 96.0, 214.0, 0.24, 3)
			_crackle(b, rng, 0.16, 0.26, 30.0, 0.11)
			_sweep_tone(b, 0.36, 0.12, 520.0, 1240.0, 0.15, 9.0)
		"skill_hurl":
			# Throw: airy pass ending in a downward tonal drop
			b.resize(int(0.34 * SYNTH_SR))
			_whoosh(b, rng, 0.0, 0.22, 0.48, 0.16, 0.78)
			_sweep_tone(b, 0.15, 0.15, 1020.0, 380.0, 0.20, 11.0)
		"skill_whirl_spin":
			# Three linked swishes around the body, closing on a low sweep
			b.resize(int(0.64 * SYNTH_SR))
			for k in 3:
				_whoosh(b, rng, 0.02 + k * 0.19, 0.17,
					0.42 - k * 0.06, 0.32, 0.82)
			_sweep_tone(b, 0.46, 0.16, 640.0, 230.0, 0.22, 10.0)
			_crackle(b, rng, 0.46, 0.14, 20.0, 0.14)
		"skill_dash_zip":
			# Sharp bright zip for the lunge
			b.resize(int(0.26 * SYNTH_SR))
			_whoosh(b, rng, 0.0, 0.14, 0.55, 0.88, 0.22)
			_sweep_tone(b, 0.03, 0.10, 1650.0, 720.0, 0.17, 13.0)
		"comet_fall":
			# Descending sky-whistle into a rumble bed
			b.resize(int(0.74 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.58, 1480.0, 210.0, 0.23, 3.6)
			_noise(b, rng, 0.12, 0.52, 0.16, 5.0, 0.5, 0.12)
		"heal_bloom_cue":
			# Warm arpeggio blooming under a petal-sparkle shimmer
			b.resize(int(0.92 * SYNTH_SR))
			_tone_at(b, 0.00, 0.30, 523.25, 0.15, 5.0, 3)
			_tone_at(b, 0.12, 0.32, 659.25, 0.14, 5.0, 3)
			_tone_at(b, 0.24, 0.40, 783.99, 0.14, 4.0, 3)
			_tone_at(b, 0.40, 0.46, 1046.50, 0.11, 3.5, 2)
			_crackle(b, rng, 0.08, 0.72, 26.0, 0.07)
		"aura_rise":
			# Shimmering rise for self-buffs
			b.resize(int(0.82 * SYNTH_SR))
			_hum(b, 0.0, 0.70, 132.0, 264.0, 0.21, 4)
			_crackle(b, rng, 0.20, 0.50, 38.0, 0.08)
			_sweep_tone(b, 0.52, 0.24, 690.0, 1420.0, 0.11, 8.0)
		# --- Lantern ---
		"lantern_hum":
			b.resize(int(1.15 * SYNTH_SR))
			_hum(b, 0.0, 1.1, 118.0, 118.0, 0.16, 2)
		"lantern_creak":
			b.resize(int(0.45 * SYNTH_SR))
			_hum(b, 0.0, 0.4, 158.0, 172.0, 0.14, 2)
			_noise(b, rng, 0.05, 0.3, 0.08, 12.0, 0.45)
		"lantern_lock":
			# Bright lock-on stinger: two clean rising tones + a glassy
			# shimmer and a warm ember bed — the "your light has claimed it"
			# moment, clearly distinct from the soft ambient pulse.
			b.resize(int(0.42 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.16, 587.33, 880.0, 0.20, 7.0)
			_sweep_tone(b, 0.05, 0.20, 1174.66, 1760.0, 0.11, 6.0)
			_hum(b, 0.0, 0.30, 110.0, 220.0, 0.09, 2)
			_crackle(b, rng, 0.10, 0.22, 34.0, 0.07)
		"lantern_release":
			# Soft falling "mark forgotten" — gentle so moving around never
			# clatters, but the state change is heard.
			b.resize(int(0.40 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.22, 440.0, 196.0, 0.14, 5.0)
			_sweep_tone(b, 0.06, 0.16, 880.0, 587.0, 0.06, 6.0)
		"lantern_refuse":
			# Short flat descending buzz: a rite refused for lack of a mark.
			# Harsher than the soft release so "you CAN'T cast yet" reads.
			b.resize(int(0.30 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.10, 330.0, 160.0, 0.18, 11.0)
			_noise(b, rng, 0.04, 0.12, 0.10, 20.0, 0.5, 0.30)
		# --- Hushling ---
		"hushling_telegraph":
			b.resize(int(0.30 * SYNTH_SR))
			_crackle(b, rng, 0.0, 0.12, 60.0, 0.32)
			_crackle(b, rng, 0.15, 0.10, 48.0, 0.26)
			_sweep_tone(b, 0.02, 0.22, 74.0, 66.0, 0.30, 9.0)  # low thrum
		"hushling_lunge":
			b.resize(int(0.22 * SYNTH_SR))
			_whoosh(b, rng, 0.0, 0.13, 0.35, 0.5, 0.8)     # fast rise
			_noise(b, rng, 0.12, 0.09, 0.22, 26.0, 0.88)   # thorn scratch
		"spore_burst":
			b.resize(int(0.26 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.05, 330.0, 68.0, 0.55, 20.0)  # pop
			_noise(b, rng, 0.03, 0.18, 0.30, 22.0, 0.35)        # hiss ring
			_crackle(b, rng, 0.05, 0.14, 30.0, 0.18)
		"hushling_death":
			b.resize(int(0.55 * SYNTH_SR))
			_hum(b, 0.00, 0.12, 220.0, 200.0, 0.20, 2)
			_hum(b, 0.13, 0.12, 165.0, 150.0, 0.18, 2)
			_hum(b, 0.26, 0.14, 112.0, 96.0, 0.16, 2)      # wilting creaks
			_noise(b, rng, 0.36, 0.18, 0.16, 18.0, 0.30)   # soft spore puff
		# --- Spitter (ranged venom caster) ---
		"venom_lob":
			# Wet gurgle climb into a spit — fleshy, unnerving
			b.resize(int(0.28 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.10, 240.0, 120.0, 0.40, 9.0)
			_hum(b, 0.03, 0.10, 150.0, 96.0, 0.22, 2)
			_noise(b, rng, 0.12, 0.10, 0.5, 38.0, 0.9)     # spit pop
			_whoosh(b, rng, 0.10, 0.16, 0.42, 0.5, 0.35)
		"venom_hit":
			# Slick splash: bright spatter over a low tonal drop
			b.resize(int(0.22 * SYNTH_SR))
			_noise(b, rng, 0.0, 0.06, 0.5, 46.0, 0.85)
			_sweep_tone(b, 0.004, 0.16, 640.0, 180.0, 0.34, 13.0)
			_crackle(b, rng, 0.02, 0.12, 36.0, 0.2)
		"enemy_spawn":
			# Rising portal shimmer that resolves into a materializing thud
			b.resize(int(0.42 * SYNTH_SR))
			_hum(b, 0.0, 0.22, 200.0, 520.0, 0.20, 3)
			_sweep_tone(b, 0.16, 0.14, 880.0, 1400.0, 0.18, 10.0)
			_sweep_tone(b, 0.30, 0.10, 300.0, 120.0, 0.4, 14.0)  # landing thud
		# --- Boss ---
		"boss_stomp":
			b.resize(int(0.5 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.26, 46.0, 34.0, 0.85, 10.0)
			_noise(b, rng, 0.0, 0.42, 0.35, 9.0, 0.14)     # rumble
			_crackle(b, rng, 0.02, 0.12, 16.0, 0.14)
		"boss_death":
			b.resize(int(1.5 * SYNTH_SR))
			_hum(b, 0.0, 1.05, 58.0, 37.0, 0.5, 4)         # groaning bark
			_crackle(b, rng, 0.1, 0.9, 26.0, 0.22)         # crumbling
			_sweep_tone(b, 1.12, 0.30, 52.0, 33.0, 0.7, 9.0)  # final thud
		# --- UI / forge ---
		"ui_confirm":
			b.resize(int(0.30 * SYNTH_SR))
			_sweep_tone(b, 0.00, 0.14, 523.25, 523.25, 0.16, 12.0)
			_sweep_tone(b, 0.045, 0.14, 659.25, 659.25, 0.15, 12.0)
			_sweep_tone(b, 0.09, 0.18, 783.99, 783.99, 0.14, 10.0)
		"ui_cancel":
			b.resize(int(0.26 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.12, 392.0, 380.0, 0.15, 13.0)
			_sweep_tone(b, 0.08, 0.16, 261.63, 255.0, 0.13, 11.0)
		"forge_success":
			b.resize(int(0.75 * SYNTH_SR))
			_noise(b, rng, 0.0, 0.5, 0.30, 7.0, 0.16)      # fire roar swell
			_sweep_tone(b, 0.18, 0.16, 940.0, 430.0, 0.4, 14.0)  # hammer clang
			_crackle(b, rng, 0.2, 0.4, 30.0, 0.16)
		"explosion":
			b.resize(int(0.5 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.34, 90.0, 40.0, 0.7, 8.0)
			_noise(b, rng, 0.0, 0.4, 0.45, 14.0, 0.20)
		# --- Impact director: material-aware strikes ---
		"impact_thud":
			b.resize(int(0.16 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.10, 96.0, 44.0, 0.6, 12.0)
			_noise(b, rng, 0.0, 0.09, 0.30, 18.0, 0.24)
		"impact_plant":
			b.resize(int(0.20 * SYNTH_SR))
			_crackle(b, rng, 0.0, 0.14, 46.0, 0.34)      # fibers tearing
			_noise(b, rng, 0.01, 0.11, 0.22, 22.0, 0.34)
			_sweep_tone(b, 0.01, 0.08, 210.0, 90.0, 0.22, 16.0)
		"impact_stone":
			b.resize(int(0.15 * SYNTH_SR))
			_noise(b, rng, 0.0, 0.02, 0.55, 70.0, 0.85)  # bright crack
			_sweep_tone(b, 0.003, 0.10, 320.0, 70.0, 0.42, 13.0)
			_crackle(b, rng, 0.03, 0.08, 26.0, 0.2)
		"impact_claw":
			b.resize(int(0.17 * SYNTH_SR))
			_noise(b, rng, 0.02, 0.10, 0.36, 30.0, 0.8)  # raking scratch
			_whoosh(b, rng, 0.0, 0.12, 0.4, 0.5, 0.7)
			_sweep_tone(b, 0.04, 0.07, 180.0, 80.0, 0.26, 15.0)
		# --- Relic element payloads ---
		"elem_fire":
			b.resize(int(0.55 * SYNTH_SR))
			_noise(b, rng, 0.0, 0.42, 0.32, 6.0, 0.30, 0.10)  # whoomp roar
			_sweep_tone(b, 0.0, 0.20, 140.0, 60.0, 0.4, 10.0)
			_crackle(b, rng, 0.1, 0.35, 34.0, 0.16)
		"elem_frost":
			b.resize(int(0.45 * SYNTH_SR))
			_sweep_tone(b, 0.0, 0.28, 1560.0, 880.0, 0.16, 9.0)  # crystalline
			_crackle(b, rng, 0.05, 0.25, 40.0, 0.12)             # brittle snap
			_noise(b, rng, 0.06, 0.22, 0.14, 26.0, 0.5)
		"elem_shock":
			b.resize(int(0.30 * SYNTH_SR))
			_noise(b, rng, 0.0, 0.12, 0.5, 60.0, 0.9)     # sharp crack
			_sweep_tone(b, 0.01, 0.14, 1900.0, 300.0, 0.3, 12.0)
			_crackle(b, rng, 0.06, 0.16, 52.0, 0.18)      # arcing sputter
		"elem_nature":
			b.resize(int(0.50 * SYNTH_SR))
			_hum(b, 0.0, 0.40, 98.0, 196.0, 0.22, 3)      # rising growth
			_crackle(b, rng, 0.08, 0.30, 30.0, 0.12)      # unfurling leaves
			_sweep_tone(b, 0.30, 0.16, 520.0, 1040.0, 0.10, 9.0)
		_:
			b.resize(int(0.1 * SYNTH_SR))
	return b

# === Synth primitives (append-only into a mono buffer) ===

func _tone_at(buf: PackedFloat32Array, t_start: float, dur: float,
		freq: float, amp: float, decay: float, harmonics: int = 1) -> void:
	var s0 := int(t_start * SYNTH_SR)
	var n := int(dur * SYNTH_SR)
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := i / float(SYNTH_SR)
		var env := exp(-t * decay)
		var s := 0.0
		var h_amp := 1.0
		for h in harmonics:
			s += sin(TAU * freq * (h + 1) * t) * h_amp
			h_amp *= 0.45
		buf[idx] += s * env * amp / maxf(1.0, harmonics * 0.7)

## Frequency-swept tone (also serves as thuds/pops/chimes).
func _sweep_tone(buf: PackedFloat32Array, t_start: float, dur: float,
		f0: float, f1: float, amp: float, decay: float) -> void:
	var s0 := int(t_start * SYNTH_SR)
	var n := int(dur * SYNTH_SR)
	var phase := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := i / float(n)
		var f := lerpf(f0, f1, t)
		phase += TAU * f / float(SYNTH_SR)
		buf[idx] += sin(phase) * exp(-t * decay * 0.16) * amp

## Rising/falling harmonic hum for casts, groans and lantern drones.
func _hum(buf: PackedFloat32Array, t_start: float, dur: float,
		f0: float, f1: float, amp: float, harmonics: int) -> void:
	var s0 := int(t_start * SYNTH_SR)
	var n := int(dur * SYNTH_SR)
	var phase := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := i / float(SYNTH_SR)
		var tt := i / float(n)
		var f := lerpf(f0, f1, tt)
		phase += TAU * f / float(SYNTH_SR)
		var s := 0.0
		var h_amp := 1.0
		for h in harmonics:
			s += sin(phase * (h + 1)) * h_amp
			h_amp *= 0.5
		var env := sin(tt * PI)  # fade in and out, never clicks
		buf[idx] += s * env * amp / maxf(1.0, harmonics * 0.6)

## One-pole low-passed noise with an attack/decay envelope and optional
## cutoff sweep (lp_alpha_end < 0 keeps a fixed cutoff).
func _noise(buf: PackedFloat32Array, rng: RandomNumberGenerator, t_start: float,
		dur: float, amp: float, decay: float, lp_alpha: float,
		lp_alpha_end: float = -1.0) -> void:
	var s0 := int(t_start * SYNTH_SR)
	var n := int(dur * SYNTH_SR)
	var y := 0.0
	var prev := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := i / float(n)
		var a := lp_alpha if lp_alpha_end < 0.0 else lerpf(lp_alpha, lp_alpha_end, t)
		var x := rng.randf_range(-1.0, 1.0)
		y += a * (x - y)
		var env := minf(t * 6.0, 1.0) * exp(-t * decay * 0.35)
		buf[idx] += y * env * amp

## Humped whoosh: two noise layers crossfade cutoffs mid-sweep.
func _whoosh(buf: PackedFloat32Array, rng: RandomNumberGenerator, t_start: float,
		dur: float, amp: float, lp_lo: float, lp_hi: float) -> void:
	var s0 := int(t_start * SYNTH_SR)
	var n := int(dur * SYNTH_SR)
	var y := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := i / float(n)
		var hump := sin(t * PI)
		var a := lerpf(lp_lo, lp_hi, sin(t * PI * 0.5))
		var x := rng.randf_range(-1.0, 1.0)
		y += a * (x - y)
		buf[idx] += y * hump * hump * amp

## Sparse impulse grains — leaf/branch crackle, cloth, debris.
func _crackle(buf: PackedFloat32Array, rng: RandomNumberGenerator, t_start: float,
		dur: float, density: float, amp: float) -> void:
	var count := int(density * dur)
	var y := 0.0
	for k in count:
		var s0 := int((t_start + rng.randf() * dur) * SYNTH_SR)
		var glen := int(rng.randf_range(0.0008, 0.004) * SYNTH_SR)
		var gamp := rng.randf_range(0.4, 1.0) * amp
		for i in glen:
			var idx := s0 + i
			if idx >= buf.size():
				break
			var x := rng.randf_range(-1.0, 1.0)
			y += 0.6 * (x - y)
			buf[idx] += y * gamp * exp(-i / float(glen) * 4.0)

func _to_wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 4)
	for i in b.size():
		var v := int(clampf(b[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 4, v)
		bytes.encode_s16(i * 4 + 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SYNTH_SR
	stream.stereo = true
	stream.data = bytes
	return stream

# === Streamed SFX (for imported files) ===
func play_sfx(resource_path: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	player.add_to_group(ONE_SHOT_GROUP)
	add_child(player)
	player.stream = load(resource_path)
	player.volume_db = volume_db + linear_to_db(sfx_volume)
	player.play()
	
	player.finished.connect(_on_sfx_finished.bind(player))
	return player

func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	player.queue_free()

# === Music ===
func play_music(resource_path: String, fade_time: float = 1.0) -> void:
	if music_player and music_player.playing:
		music_player.volume_db = -80
		await get_tree().create_timer(fade_time).timeout
		music_player.queue_free()
	
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.stream = load(resource_path)
	music_player.volume_db = linear_to_db(music_volume)
	music_player.autoplay = true
	music_player.play()

func stop_music(fade_time: float = 1.0) -> void:
	if music_player:
		var tween = create_tween()
		tween.tween_property(music_player, "volume_db", -80, fade_time)
		tween.tween_callback(music_player.queue_free)

# === Helpers ===
func linear_to_db(linear: float) -> float:
	return 20.0 * log(max(0.0001, linear)) / log(10.0)

func db_to_linear(db: float) -> float:
	return pow(10.0, db / 20.0)

func _set_bus_volume(bus_name: String, linear_volume: float) -> void:
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear_volume))

func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)
	_set_bus_volume("Master", master_volume)

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_set_bus_volume("SFX", sfx_volume)

func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_set_bus_volume("Music", music_volume)
	if music_player:
		music_player.volume_db = linear_to_db(music_volume)
