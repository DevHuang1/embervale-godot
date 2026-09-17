extends CanvasLayer
class_name ChapterQuizMenu

@onready var game_state: GameState = GameState
@onready var question_label: Label = $Root/VBox/Question
@onready var answers_box: VBoxContainer = $Root/VBox/Answers
@onready var result_label: Label = $Root/VBox/Result
@onready var close_button: Button = $Root/VBox/Close

var _stage := 0
var _freeze_was_visible := false
var _freeze_held := false

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.apply_glass($Root)
	UiKit.style_button(close_button, UiKit.SAGE)
	close_button.pressed.connect(close)
	_apply_responsive_frame()
	get_viewport().size_changed.connect(_apply_responsive_frame)

## Phone frame: the lesson sheet authored 180px vertical margins, which eats a
## short portrait screen. Tighten with the shared safe-area-aware helper.
func _apply_responsive_frame() -> void:
	UiKit.apply_menu_frame(get_node_or_null("Root") as Control,
		get_viewport().get_visible_rect().size, 80.0, 180.0)

func _process(_delta: float) -> void:
	if visible != _freeze_was_visible:
		_freeze_was_visible = visible
		if visible:
			game_state.push_world_freeze()
			_freeze_held = true
		else:
			_release_world_freeze()

func open(stage: int) -> void:
	_stage = stage
	visible = true
	result_label.text = ""
	_build_question()

func close() -> void:
	visible = false

func _build_question() -> void:
	for child in answers_box.get_children():
		child.queue_free()
	var question: Dictionary = QuizManager.question_for_stage(_stage)
	if question.is_empty():
		question_label.text = "No chapter lesson available."
		return
	question_label.text = str(question.prompt)
	for i in question.answers.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 54)
		button.text = "%d. %s" % [i + 1, str(question.answers[i])]
		button.pressed.connect(_answer.bind(i))
		UiKit.style_secondary_button(button)
		answers_box.add_child(button)

func _answer(index: int) -> void:
	var result: Dictionary = QuizManager.submit(_stage, index)
	result_label.text = str(result.get("message", ""))
	if bool(result.get("correct", false)):
		var reward: Dictionary = result.get("reward", {})
		result_label.text += "  +%d GOLD" % int(reward.get("gold", 0))
		for button in answers_box.get_children():
			button.disabled = true
		game_state.quest_progress.emit("Chapter lesson complete.")
	else:
		result_label.text += " Try again."

## A menu freed while it still holds the world must not leave it paused behind
## it. Every freeze-holding surface shares this guarantee, matching the altar's
## teardown behaviour.
func _exit_tree() -> void:
	_release_world_freeze()

func _release_world_freeze() -> void:
	if not _freeze_held:
		return
	_freeze_held = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("pop_world_freeze"):
		gs.call("pop_world_freeze")
