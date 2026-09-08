extends CanvasLayer
class_name ChapterQuizMenu

@onready var game_state: GameState = GameState
@onready var question_label: Label = $Root/VBox/Question
@onready var answers_box: VBoxContainer = $Root/VBox/Answers
@onready var result_label: Label = $Root/VBox/Result
@onready var close_button: Button = $Root/VBox/Close

var _stage := 0
var _freeze_was_visible := false

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.apply_glass($Root)
	UiKit.style_button(close_button, UiKit.SAGE)
	close_button.pressed.connect(close)

func _process(_delta: float) -> void:
	if visible != _freeze_was_visible:
		_freeze_was_visible = visible
		if visible:
			game_state.push_world_freeze()
		else:
			game_state.pop_world_freeze()

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
