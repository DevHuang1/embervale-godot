extends PanelContainer
class_name RewardRevealPanel

const MODEL := preload("res://scripts/systems/reward_reveal_model.gd")
signal dismissed()

var _summary: Label
var _body: VBoxContainer

func _ready() -> void:
	visible = false

func open_for(entries: Array, source: String = "reward",
		title_override: String = "", subtitle: String = "") -> void:
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
	var skip := Button.new()
	skip.name = "SkipRewardReveal"
	skip.text = "CONTINUE"
	UiKit.style_secondary_button(skip)
	skip.pressed.connect(dismiss)
	_body.add_child(skip)
	visible = true

func dismiss() -> void:
	visible = false
	dismissed.emit()
