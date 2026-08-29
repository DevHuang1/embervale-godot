extends CanvasLayer
class_name ScreenFX

## === Screen FX Overlay ===
## Low-HP vignette pulse, death desaturation and heavy-hit chromatic
## aberration. Lives under the HUD so both biomes get it for free.

const VIGNETTE_MAX := 0.45   # hard cap so low-warmth never blacks the screen
const VIGNETTE_BASE := 0.12

var _mat: ShaderMaterial = null
var _rect: ColorRect = null
var _vignette_level := 0.0      # 0..1 driven by warmth
var _pulse := 0.0
var _chroma := 0.0
var _death_tween: Tween = null
var _last_hp: int = 999
var _world_state: Node = null   # mood source (rain, combat intensity)

func _ready() -> void:
	add_to_group("screen_fx")
	layer = 5
	
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/screen_fx.gdshader")
	
	_rect = ColorRect.new()
	_rect.name = "FxRect"
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	
	_apply(0.0)
	
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.defeated.connect(_on_defeated)

func _process(delta: float) -> void:
	if _world_state == null or not is_instance_valid(_world_state):
		_world_state = get_tree().get_first_node_in_group("world_state")
	var intensity: float = _world_state.combat_intensity \
		if _world_state != null else 0.0
	var rain: float = _world_state.rain_level if _world_state != null else 0.0
	var quality = _world_state.quality if _world_state != null else null
	var allow_distortion := quality == null or bool(quality.distortion_enabled)
	var target_vignette := clampf(VIGNETTE_BASE + _vignette_level * 0.35 + _pulse,
		0.0, VIGNETTE_MAX)
	# Combat tension breathes a hair of extra vignette (capped by VIGNETTE_MAX)
	target_vignette += intensity * 0.05
	var target_sat := clampf(lerpf(1.0, 0.25, maxf(_vignette_level - 0.9, 0.0) * 10.0), 0.2, 1.0)
	_pulse = maxf(_pulse - delta * 1.6, 0.0)
	_chroma = maxf(_chroma - delta * 3.2, 0.0)
	_mat.set_shader_parameter("vignette_amount", clampf(target_vignette, 0.0, 0.9))
	_mat.set_shader_parameter("saturation", target_sat)
	_mat.set_shader_parameter("chroma_strength", _chroma if allow_distortion else 0.0)
	_mat.set_shader_parameter("wetness", rain if allow_distortion else 0.0)

func _on_hp_changed(_old_hp: int, new_hp: int) -> void:
	var warmth := GameState.get_warmth_percent()
	_vignette_level = clampf(1.0 - warmth / 100.0, 0.0, 1.0)
	if new_hp > _last_hp:
		_vignette_level = minf(_vignette_level, 0.35)
	_last_hp = new_hp
	# Back at full strength: clear any lingering death desaturation
	if new_hp >= GameState.max_hp and _last_hp > 0:
		reset()
	elif _vignette_level > 0.6:
		pulse_vignette()

func _on_defeated() -> void:
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_method(func(v: float): _mat.set_shader_parameter("saturation", v), 1.0, 0.15, 0.7)

# === Public API ===
func pulse_vignette(strength: float = 0.22) -> void:
	_pulse = maxf(_pulse, strength)

func punch_chroma(strength: float = 0.8) -> void:
	_chroma = maxf(_chroma, strength)

func reset() -> void:
	_vignette_level = 0.0
	_last_hp = GameState.hp
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_mat.set_shader_parameter("saturation", 1.0)
	_apply(0.0)

## A kill (or a fresh start) lifts the gloom: ease the low-warmth vignette
## back down to a warm lantern glow instead of leaving the screen black.
func comfort() -> void:
	_pulse = 0.0
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	var tw := create_tween()
	tw.tween_method(func(v: float): _vignette_level = v, _vignette_level, 0.15, 0.45)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(
		func(v: float): _mat.set_shader_parameter("saturation", v), 0.6, 1.0, 0.45)

func _apply(_v: float) -> void:
	_mat.set_shader_parameter("vignette_amount", VIGNETTE_BASE)
	_mat.set_shader_parameter("saturation", 1.0)
	_mat.set_shader_parameter("chroma_strength", 0.0)
