extends Node

## === Camera Scan → Object Detection → Weapon Forge ===
## Mobile: uses Godot's CameraFeed (Android/iOS) + simple color/shape detection
## Desktop fallback: simulated detection

signal scan_started
signal scan_progress(progress: float, message: String)
signal scan_completed(detected_class: String, confidence: float)
signal forge_completed(weapon_id: String, rarity: int)
signal relic_forged(relic: RelicData)
signal scan_failed(error: String)

## Timestamp of the last reveal, read by entity shaders (dirt scanline).
static var reveal_stamp_msec: int = -999999

@export var scan_duration: float = 2.5
@export var min_confidence: float = 0.65

var last_capture: Image = null
var last_relic: RelicData = null
var _capture_viewport: SubViewport = null

# Coco-SSD style classes mapped to weapons
const CLASS_TO_WEAPON: Dictionary = {
	"cup": {"id": "mug_mace", "name": "MUG MACE", "glyph": "☕", "atk": 7, "swing_time": 0.38, "range": 8.2, "skill": {"name": "MUG SLAM", "type": "aoe", "cooldown": 4.0, "radius": 13.0, "dmg_mult": 1.5}},
	"cell phone": {"id": "pocket_blade", "name": "POCKET BLADE", "glyph": "📱", "atk": 5, "swing_time": 0.26, "range": 6.4, "skill": {"name": "FLASH BANG", "type": "stun", "cooldown": 6.0, "radius": 15.0, "power": 1.5}},
	"scissors": {"id": "snip_twins", "name": "SNIP TWINS", "glyph": "✂️", "atk": 6, "swing_time": 0.32, "range": 7.2, "skill": {"name": "SNIP DASH", "type": "dash", "cooldown": 3.5, "power": 20.0, "dmg_mult": 1.2}},
	"bottle": {"id": "soda_cannon", "name": "SODA CANNON", "glyph": "🍾", "atk": 6, "swing_time": 0.34, "range": 7.6, "skill": {"name": "SODA SPRAY", "type": "projectile", "cooldown": 2.5, "power": 34.0, "dmg_mult": 1.6}},
	"laptop": {"id": "slab_hammer", "name": "SLAB HAMMER", "glyph": "💻", "atk": 10, "swing_time": 0.52, "range": 9.2, "skill": {"name": "EM PULSE", "type": "heavy_aoe", "cooldown": 7.0, "radius": 17.5, "dmg_mult": 1.8}}
}

const RARITY_WEIGHTS: Array = [
	{"rarity": 0, "weight": 0.50, "name": "Common", "mult": 1.00},    # Common
	{"rarity": 1, "weight": 0.25, "name": "Uncommon", "mult": 1.15},   # Uncommon
	{"rarity": 2, "weight": 0.15, "name": "Rare", "mult": 1.30},       # Rare
	{"rarity": 3, "weight": 0.07, "name": "Epic", "mult": 1.45},       # Epic
	{"rarity": 4, "weight": 0.03, "name": "Legendary", "mult": 1.65}   # Legendary
]

var camera_feed: CameraFeed = null
var is_scanning: bool = false
var scan_tween: Tween = null

func _ready() -> void:
	pass

func start_scan() -> void:
	if is_scanning:
		return
	
	is_scanning = true
	scan_started.emit()
	scan_progress.emit(0.04, "Waking lens...")
	
	# Real capture: grab a frame from the first available camera feed.
	# Desktop included — Godot exposes webcams on macOS/Windows too.
	last_capture = await _acquire_frame()
	if last_capture != null:
		scan_progress.emit(0.12, "Essence captured.")
	else:
		scan_progress.emit(0.12, "Lens dim — forging from memory.")
	
	_run_detection()

func _run_detection() -> void:
	scan_progress_proxy = 0.0
	scan_tween = create_tween().set_parallel(false)
	var steps = [
		{"progress": 0.15, "msg": "Initializing lens...", "time": 0.3},
		{"progress": 0.35, "msg": "Reading essence...", "time": 0.6},
		{"progress": 0.55, "msg": "Binding form...", "time": 0.5},
		{"progress": 0.75, "msg": "Rolling rarity...", "time": 0.4},
		{"progress": 1.0, "msg": "Revealing gear...", "time": 0.4}
	]
	
	for i in steps:
		scan_tween.tween_property(self, "scan_progress_proxy", i.progress, i.time).set_trans(Tween.TRANS_LINEAR)
		scan_tween.tween_callback(_on_scan_step.bind(i.msg)).set_delay(0.05)
	
	# Final detection
	await get_tree().create_timer(scan_duration).timeout
	_on_detection_complete()

func _on_scan_step(msg: String) -> void:
	scan_progress.emit(scan_progress_proxy, msg)

var scan_progress_proxy: float = 0.0

func _set_scan_progress(value: float) -> void:
	scan_progress_proxy = value

func _on_detection_complete() -> void:
	reveal_stamp_msec = Time.get_ticks_msec()
	if camera_feed and OS.has_feature("mobile"):
		camera_feed.stop()
	
	# Simulated detection (replace with real ML inference)
	var detected_classes = CLASS_TO_WEAPON.keys()
	var detected = detected_classes.pick_random()
	var confidence = randf_range(min_confidence, 0.98)
	
	scan_completed.emit(detected, confidence)
	
	# Forge weapon
	var weapon_data = CLASS_TO_WEAPON[detected].duplicate(true)
	var rarity = _roll_rarity()
	weapon_data.rarity = rarity
	weapon_data.rarity_name = RARITY_WEIGHTS[rarity].name
	weapon_data.rarity_mult = RARITY_WEIGHTS[rarity].mult
	
	# Apply rarity multiplier to stats
	weapon_data.atk = int(weapon_data.atk * weapon_data.rarity_mult)
	
	forge_completed.emit(weapon_data.id, rarity)
	
	# Photo-forged relic: the captured silhouette becomes 3D geometry.
	if last_capture != null:
		var forged := RelicForge.forge(last_capture)
		if not forged.is_empty():
			var relic := RelicData.new()
			relic.title = weapon_data.name
			relic.glyph = weapon_data.glyph
			relic.rarity = rarity
			relic.mesh = forged.mesh
			relic.texture = forged.texture
			last_relic = relic
			relic_forged.emit(relic)
	
	is_scanning = false

# === Real camera capture (desktop + mobile) ===
## Public raw frame grab for flows that need the photo itself (boss altar)
## without minting a weapon through the full detection pipeline.
func capture_frame(timeout_s: float = 3.0) -> Image:
	var img := await _acquire_frame(timeout_s)
	if img != null:
		last_capture = img
	return img

func _acquire_frame(timeout_s: float = 3.5) -> Image:
	var feeds := CameraServer.feeds()
	if feeds.is_empty():
		return null
	var feed: CameraFeed = feeds[0]
	feed.feed_is_active = true
	var tex := CameraTexture.new()
	tex.camera_feed_id = feed.get_id()
	
	if _capture_viewport == null or not is_instance_valid(_capture_viewport):
		_capture_viewport = SubViewport.new()
		_capture_viewport.disable_3d = true
		var frame_sprite := Sprite2D.new()
		frame_sprite.name = "Frame"
		frame_sprite.flip_v = true  # camera images arrive upside-down
		_capture_viewport.add_child(frame_sprite)
		add_child(_capture_viewport)
	var frame_sprite: Sprite2D = _capture_viewport.get_node_or_null("Frame")
	if frame_sprite == null:
		feed.feed_is_active = false
		return null
	frame_sprite.texture = tex
	
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var tw := tex.get_width()
		var th := tex.get_height()
		_capture_viewport.size = Vector2i(
			tw if tw > 0 else 320,
			th if th > 0 else 240)
		_capture_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		await get_tree().process_frame
		var img := _capture_viewport.get_texture().get_image()
		if img != null and not img.is_empty() and img.get_width() > 16:
			img.convert(Image.FORMAT_RGB8)
			feed.feed_is_active = false
			return img
	
	feed.feed_is_active = false
	return null

func _roll_rarity() -> int:
	var roll = randf()
	var cumulative = 0.0
	for i in RARITY_WEIGHTS.size():
		cumulative += RARITY_WEIGHTS[i].weight
		if roll <= cumulative:
			return i
	return 0

func get_weapon_data(class_name_str: String) -> Dictionary:
	if CLASS_TO_WEAPON.has(class_name_str):
		return CLASS_TO_WEAPON[class_name_str].duplicate(true)
	for weapon in CLASS_TO_WEAPON.values():
		if weapon.get("id", "") == class_name_str:
			return weapon.duplicate(true)
	return CLASS_TO_WEAPON["cup"].duplicate(true)

# Desktop testing
func simulate_scan(class_name_str: String = "") -> void:
	if not OS.has_feature("mobile"):
		var detected = class_name_str if class_name_str else CLASS_TO_WEAPON.keys().pick_random()
		scan_completed.emit(detected, 0.9)
		var weapon_data = CLASS_TO_WEAPON[detected].duplicate(true)
		var rarity = _roll_rarity()
		weapon_data.rarity = rarity
		weapon_data.rarity_name = RARITY_WEIGHTS[rarity].name
		weapon_data.rarity_mult = RARITY_WEIGHTS[rarity].mult
		weapon_data.atk = int(weapon_data.atk * weapon_data.rarity_mult)
		forge_completed.emit(weapon_data.id, rarity)