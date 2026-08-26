extends SceneTree

## Headless test: WorldState mood engine — intensity rise/decay, magic level
## from night factor + scans, rain clamps + beacon lock, wind bounds.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	var ws = root.get_node_or_null("/root/WorldState")
	if ws == null:
		print("FAIL: WorldState autoload missing")
		root.add_child(Node.new())
		quit(1)
		return
	var gs = root.get_node_or_null("/root/GameState")

	# --- Intensity: rises in combat, decays exploring, capped by impacts ---
	ws.combat_intensity = 0.0
	gs.combat_state = gs.CombatState.COMBAT
	ws._update_intensity(1.0)
	if ws.combat_intensity < 0.5:
		failures += 1
		print("FAIL: intensity should rise toward %.2f while in combat, got %.2f"
			% [0.55, ws.combat_intensity])
	gs.combat_state = gs.CombatState.EXPLORING
	ws._update_intensity(1.0)
	if ws.combat_intensity >= 0.55:
		failures += 1
		print("FAIL: intensity should decay when exploring, got %.2f" % ws.combat_intensity)
	for i in 20:
		ws.notify_impact(0.9)
	if ws.combat_intensity > 1.0:
		failures += 1
		print("FAIL: notify_impact must clamp at 1.0, got %.2f" % ws.combat_intensity)

	# --- Magic level: night factor + relic scans feed it ---
	ws.scan_depth = 0
	ws.report_night_factor(0.0)
	ws._update_magic_level()
	var day_magic: float = ws.magic_level
	ws.report_night_factor(1.0)
	ws._update_magic_level()
	if not (ws.magic_level > day_magic):
		failures += 1
		print("FAIL: magic_level should rise with night factor (%.2f -> %.2f)"
			% [day_magic, ws.magic_level])
	ws.scan_depth = 3
	ws._update_magic_level()
	if not (ws.magic_level >= 0.7 * 1.0):
		failures += 1
		print("FAIL: scan depth should add to magic level, got %.2f" % ws.magic_level)
	# --- Rain: clamped, eased toward target, beacon lock forces calm ---
	ws.weather_locked = false
	ws.set_rain(2.0)
	if ws._rain_target != 1.0:
		failures += 1
		print("FAIL: set_rain must clamp target to 1.0, got %.2f" % ws._rain_target)
	ws.weather_locked = true
	ws.set_rain(0.8)
	if ws._rain_target != 0.0:
		failures += 1
		print("FAIL: weather_locked must force rain calm, got %.2f" % ws._rain_target)
	ws.weather_locked = false

	# --- Wind stays inside the shader-safe envelope ---
	for i in 30:
		ws._update_wind(1.0 / 60.0)
	if ws.wind.length() > 0.31:
		failures += 1
		print("FAIL: wind exceeded safe magnitude: %.3f" % ws.wind.length())

	# --- Relic forged signal bumps scan depth ---
	var before: int = ws.scan_depth
	var sm = root.get_node_or_null("/root/ScanManager")
	sm.relic_forged.emit(null)
	if ws.scan_depth != before + 1:
		failures += 1
		print("FAIL: relic_forged should increment scan_depth")

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
