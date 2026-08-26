extends SceneTree

## Headless regression: no HUD/menu chrome overlaps at design resolution.
## CombatCard and BossHealthBar share the upper band by design; runtime
## exclusivity (hud._process yields the card to the boss bar) is asserted
## instead of a static rect check.

const MENU_NODES := ["Root/Wordmark", "Root/VersionChip", "Root/HeroCard", "Root/FooterHint"]
const HUD_NODES := [
	"Root/MinimapContainer", "Root/PlayerPlate", "Root/QuestLedger",
	"Root/MetaRow", "Root/CombatCard", "Root/BossHealthBar",
	"Root/LevelToast", "Root/LootToast", "Root/FieldNote",
	"Root/MoveJoystick", "Root/DodgeButton", "Root/JumpButton",
	"Root/SkillBar/Skill0Button", "Root/SkillBar/Skill1Button",
	"Root/SkillBar/Skill2Button", "Root/SkillBar/AttackButton",
]
const EXCLUSIVE_PAIRS := [["Root/CombatCard", "Root/BossHealthBar"]]

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT")
		quit(3))
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _rect_of(n: Control) -> Rect2:
	return Rect2(n.global_position, n.size)

func _audit(scene: Node, paths: Array, label: String) -> int:
	var bad := 0
	var nodes: Array[Control] = []
	for p in paths:
		var n := scene.get_node_or_null(p) as Control
		if n == null:
			print("FAIL: missing node ", p)
			return 1
		nodes.append(n)
	await _frames(4)
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if _is_exclusive(scene, nodes[i], nodes[j]):
				continue
			var a := _rect_of(nodes[i])
			var b := _rect_of(nodes[j])
			if a.intersects(b):
				bad += 1
				print("FAIL overlap [", label, "]: ", nodes[i].name, " ",
					a, " <-> ", nodes[j].name, " ", b)
	return bad

func _is_exclusive(scene: Node, a: Control, b: Control) -> bool:
	for pair in EXCLUSIVE_PAIRS:
		var na := scene.get_node(pair[0]) as Control
		var nb := scene.get_node(pair[1]) as Control
		if (na == a and nb == b) or (na == b and nb == a):
			return true
	return false

func _run() -> void:
	var failures := 0
	root.size = Vector2i(1080, 1920)
	await _frames(2)
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	var main_scene: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	current_scene = main_scene
	await _frames(12)
	var menu := main_scene.get_node("MainMenu")
	menu.get_node("Root/HeroCard/HeroVBox/ConfirmCard").visible = true
	failures += await _audit(menu, MENU_NODES, "MENU")

	main_scene.queue_free()
	await _frames(3)

	var grove: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(grove)
	current_scene = grove
	await _frames(12)
	var hud := grove.get_node("HUD")
	failures += await _audit(hud, HUD_NODES, "HUD")

	# Runtime exclusivity: showing the boss bar must retire the combat card.
	var card := hud.get_node("Root/CombatCard") as Control
	var boss := hud.get_node("Root/BossHealthBar") as Control
	card.visible = true
	boss.visible = true
	await _frames(3)
	if card.visible:
		failures += 1
		print("FAIL: combat card not yielded to boss bar")

	gs.delete_save()
	if failures == 0:
		print("ALL UI OVERLAP TESTS PASSED")
	else:
		print("UI OVERLAP TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
