extends PanelContainer
class_name BossRewardChoicePanel

const REWARD_CATALOG := preload("res://scripts/systems/boss_reward_catalog.gd")

## Non-mutating post-boss choice presentation. Selection emits a request;
## RewardManager/GameState must authorize and persist the final grant.

signal choice_requested(boss_id: String, reward_id: String)

var boss_id: String = ""
var _choices: Array[Dictionary] = []
var _body: VBoxContainer

func open_for(p_boss_id: String) -> void:
	boss_id = p_boss_id
	_choices = REWARD_CATALOG.choices_for(boss_id)
	_build()
	visible = true

func _ready() -> void:
	visible = false

func _build() -> void:
	for child in get_children():
		child.queue_free()
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	var title := Label.new()
	title.text = "CHOOSE YOUR SPOILS"
	UiKit.style_label(title, &"MenuTitle", 20)
	_body.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Choose the build direction that shapes your next expedition."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(subtitle, &"Caption", 13)
	_body.add_child(subtitle)
	for choice in _choices:
		var button := Button.new()
		var action := UiKit.action_state("available", "Preview only until confirmed")
		button.text = "%s\n%s\n%s" % [str(choice.get("title", "Reward")),
			str(choice.get("build_tag", "Build option")),
			"[%s] %s" % [str(action.get("label", "AVAILABLE")),
			str(choice.get("summary", ""))]]
		button.tooltip_text = "%s. %s." % [str(action.get("label", "AVAILABLE")),
			str(action.get("detail", "Preview only until confirmed"))]
		button.custom_minimum_size = Vector2(0, 78)
		button.pressed.connect(_on_choice_pressed.bind(str(choice.get("id", ""))))
		_body.add_child(button)

func _on_choice_pressed(reward_id: String) -> void:
	if reward_id.is_empty() or _choices.is_empty():
		return
	choice_requested.emit(boss_id, reward_id)
