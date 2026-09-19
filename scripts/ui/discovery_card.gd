extends PanelContainer
class_name DiscoveryCard

## === Discovery Card ===
## The readable half of a first meeting: name, title, a short piece of history
## and the skills (creatures) or features (places) involved. It is an ambient
## notice, never a modal — it ignores pointer input, holds long enough to read,
## fades, and releases the HUD queue, matching the reward reveal contract.

signal dismissed()

const HOLD_SECONDS := 5.5
const FADE_SECONDS := 0.5

var _auto_dismiss: Tween = null

func open_for(record: Dictionary, hold_seconds: float = HOLD_SECONDS) -> void:
	_stop_auto_dismiss()
	for child in get_children():
		child.queue_free()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiKit.glass_stylebox(true, 0.55))
	var body := VBoxContainer.new()
	body.name = "DiscoveryBody"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	var kicker := Label.new()
	kicker.name = "DiscoveryKicker"
	kicker.text = "NEW CREATURE" if str(record.get("type", "mob")) == "mob" \
		else "NEW PLACE"
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.style_label(kicker, &"Caption", 16)
	body.add_child(kicker)
	var name_label := Label.new()
	name_label.name = "DiscoveryName"
	name_label.text = str(record.get("name", "UNKNOWN"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.style_label(name_label, &"MenuTitle", 30)
	body.add_child(name_label)
	var title_label := Label.new()
	title_label.name = "DiscoveryTitle"
	title_label.text = str(record.get("title", ""))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.style_label(title_label, &"Body", 18)
	body.add_child(title_label)
	var story := Label.new()
	story.name = "DiscoveryStory"
	story.text = str(record.get("story", ""))
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.style_label(story, &"Caption", 17)
	body.add_child(story)
	var bullets_label := Label.new()
	bullets_label.name = "DiscoveryBulletsLabel"
	bullets_label.text = str(record.get("bullets_label", "SKILLS"))
	bullets_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.style_label(bullets_label, &"Caption", 15)
	body.add_child(bullets_label)
	var bullets: Array = record.get("bullets", [])
	# Two bullets is the readable ceiling on a phone; the codex itself keeps
	# every entry so nothing is lost, it just does not crowd the fight.
	for index in mini(bullets.size(), 3):
		var bullet := bullets[index] as Dictionary
		var row := Label.new()
		row.name = "DiscoveryBullet"
		row.text = "%s — %s" % [str(bullet.get("name", "")),
			str(bullet.get("desc", ""))]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.style_label(row, &"Body", 16)
		body.add_child(row)
	visible = true
	modulate.a = 1.0
	_auto_dismiss = create_tween()
	_auto_dismiss.tween_interval(maxf(hold_seconds, 0.8))
	_auto_dismiss.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_auto_dismiss.tween_callback(dismiss)

func _stop_auto_dismiss() -> void:
	if _auto_dismiss != null and _auto_dismiss.is_valid():
		_auto_dismiss.kill()
	_auto_dismiss = null

func dismiss() -> void:
	if not visible:
		return
	_stop_auto_dismiss()
	modulate.a = 1.0
	visible = false
	dismissed.emit()
