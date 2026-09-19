extends PanelContainer
class_name RewardRevealPanel

const MODEL := preload("res://scripts/systems/reward_reveal_model.gd")
signal dismissed()

## Reveals are ambient notices, not modal prompts: they hold long enough to
## read, fade, then release the queue. Every popup keeps a bounded lifetime so
## stacked completions can never pin gameplay behind an unread panel.
const AUTO_DISMISS_HOLD := 4.0
const AUTO_DISMISS_FADE := 0.5

var _summary: Label
var _body: VBoxContainer
var _auto_dismiss: Tween = null

func _ready() -> void:
	visible = false

func open_for(entries: Array, source: String = "reward",
		title_override: String = "", subtitle: String = "",
		hold_seconds: float = AUTO_DISMISS_HOLD) -> void:
	_stop_auto_dismiss()
	var reveal: Dictionary = MODEL.build(entries, source)
	for child in get_children():
		child.queue_free()
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	var title := Label.new()
	title.name = "RewardRevealTitle"
	title.text = title_override if not title_override.strip_edges().is_empty() \
		else "%s REVEAL" % str(reveal.get("source", "REWARD")).to_upper()
	UiKit.style_label(title, &"MenuTitle", 32)
	_body.add_child(title)
	if not subtitle.strip_edges().is_empty():
		var subtitle_label := Label.new()
		subtitle_label.name = "RewardRevealSubtitle"
		subtitle_label.text = subtitle
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(subtitle_label, &"Body", 20)
		_body.add_child(subtitle_label)
	for item in reveal.get("entries", []):
		var row := Label.new()
		row.text = "%s  ×%d  ·  RARITY %d" % [str(item.get("label", item.get("id", "item"))),
			int(item.get("quantity", 1)), int(item.get("rarity", 0))]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(row, &"Body", 20)
		_body.add_child(row)
	_summary = Label.new()
	_summary.name = "AccessibleRewardSummary"
	_summary.text = "SUMMARY · %s" % str(reveal.get("summary", "No reward"))
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_summary, &"Caption", 18)
	_body.add_child(_summary)
	visible = true
	_start_auto_dismiss(hold_seconds)

func _start_auto_dismiss(hold_seconds: float) -> void:
	modulate.a = 1.0
	_auto_dismiss = create_tween()
	_auto_dismiss.tween_interval(maxf(hold_seconds, 0.0))
	_auto_dismiss.tween_property(self, "modulate:a", 0.0, AUTO_DISMISS_FADE)
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
