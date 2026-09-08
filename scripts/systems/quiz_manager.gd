extends Node

## Replay-safe chapter knowledge checks with modest, non-power-skipping rewards.
signal quiz_answered(stage: int, correct: bool, reward: Dictionary)

const QUESTIONS: Array[Dictionary] = [
	{"prompt": "What should you do when an enemy telegraph closes?", "answers": ["Dodge", "Stand still", "Open the shop"], "correct": 0, "reward": {"gold": 12, "scan_fragment": 1}},
	{"prompt": "Which resource is used for weapon upgrades?", "answers": ["Iron Shards", "Diamonds", "Moonlight"], "correct": 0, "reward": {"gold": 14}},
	{"prompt": "What does a target ring mean?", "answers": ["A foe is locked", "A shop is open", "A quest is complete"], "correct": 0, "reward": {"gold": 16, "material": "fen_reed"}},
	{"prompt": "What is the safest way to read a boss phase?", "answers": ["Watch its telegraph", "Ignore the arena", "Spend diamonds"], "correct": 0, "reward": {"gold": 18, "material": "emberstone"}},
	{"prompt": "What does a scan charge do?", "answers": ["Starts one scan", "Guarantees legendary loot", "Raises damage forever"], "correct": 0, "reward": {"gold": 20, "material": "moonmoss"}},
]

func question_for_stage(stage: int) -> Dictionary:
	if stage < 0 or stage >= QUESTIONS.size():
		return {}
	return QUESTIONS[stage].duplicate(true)

func is_completed(stage: int) -> bool:
	return bool(GameState.completed_quizzes.get(str(stage), false))

func submit(stage: int, answer_index: int) -> Dictionary:
	var question := question_for_stage(stage)
	if question.is_empty():
		return {"success": false, "message": "No quiz is available for this chapter."}
	if is_completed(stage):
		return {"success": false, "message": "This chapter lesson is already complete."}
	if answer_index != int(question.correct):
		quiz_answered.emit(stage, false, {})
		return {"success": true, "correct": false, "message": "Not quite. Review the lesson and try again.", "reward": {}}
	GameState.completed_quizzes[str(stage)] = true
	var reward: Dictionary = question.reward.duplicate(true)
	var gold := int(reward.get("gold", 0))
	if gold > 0:
		GameState.add_gold(gold, "Quiz complete — lesson reward.")
	var material := str(reward.get("material", ""))
	if not material.is_empty():
		GameState.add_material(material, 1)
	var scan_fragment := int(reward.get("scan_fragment", 0))
	if scan_fragment > 0:
		GameState.add_scan_fragment(scan_fragment)
	GameState.save_game()
	quiz_answered.emit(stage, true, reward)
	return {"success": true, "correct": true, "message": "Lesson complete.", "reward": reward}
