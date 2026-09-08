extends PanelContainer
class_name RewardRevealPanel

const MODEL := preload("res://scripts/systems/reward_reveal_model.gd")
signal dismissed()

var _summary: Label
var _body: VBoxContainer

func _ready() -> void:
	visible = false

func open_for(entries: Array, source: String = "reward") -> void:
	var reveal: Dictionary = MODEL.build(entries, source)
	for child in get_children():
		child.queue_free()
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	var title := Label.new()
	title.text = "%s REVEAL" % str(reveal.get("source", "REWARD")).to_upper()
	UiKit.style_label(title, &"MenuTitle", 18)
	_body.add_child(title)
	for item in reveal.get("entries", []):
		var row := Label.new()
		row.text = "%s  ×%d  ·  RARITY %d" % [str(item.get("label", item.get("id", "item"))),
			int(item.get("quantity", 1)), int(item.get("rarity", 0))]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(row, &"Body", 14)
		_body.add_child(row)
	_summary = Label.new()
	_summary.name = "AccessibleRewardSummary"
	_summary.text = "SUMMARY · %s" % str(reveal.get("summary", "No reward"))
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_summary, &"Caption", 12)
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
