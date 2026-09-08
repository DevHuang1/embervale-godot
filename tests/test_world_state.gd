extends SceneTree

## Headless test: WorldState current surface — combat intensity clamping +
## signal, rain, wind/gust, realm/time-of-day/night, gathered/discovered
## persistence, and save round-trip safety.
##
## History: the old intensity rise/decay engine, night-factor magic level,
## weather-lock and wind decay lived here. They were refactored elsewhere
## (EncounterZone drives intensity via set_combat_intensity; screen_fx
## consumes it; RealmEnvironment owns realm dressing). This test pins the
## surface that remains so a future refactor cannot silently break movement
## of state into/out of the save file.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var failures := 0
	var ws := root.get_node_or_null("/root/WorldState")
	if ws == null:
		print("FAIL: WorldState autoload missing")
		quit(1)
		return

	# --- Combat intensity: clamps [0,1], emits, mirrors in getter ---
	var sig_hits: Array[float] = []
	ws.combat_intensity_changed.connect(func(v: float): sig_hits.append(v))
	ws.set_combat_intensity(0.0)
	ws.set_combat_intensity(1.7)
	if not is_equal_approx(ws.get_combat_intensity(), 1.0):
		failures += 1
		print("FAIL: set_combat_intensity must clamp high at 1.0, got %.2f"
			% ws.get_combat_intensity())
	ws.set_combat_intensity(-0.4)
	if not is_equal_approx(ws.get_combat_intensity(), 0.0):
		failures += 1
		print("FAIL: set_combat_intensity must clamp low at 0.0, got %.2f"
			% ws.get_combat_intensity())
	ws.set_combat_intensity(0.55)
	if sig_hits.is_empty() or not is_equal_approx(sig_hits.back(), 0.55):
		failures += 1
		print("FAIL: combat_intensity_changed did not fire with the clamped value")

	# --- Rain: clamps [0,1], emits ---
	var rain_hits: Array[float] = []
	ws.rain_changed.connect(func(v: float): rain_hits.append(v))
	ws.set_rain(2.0)
	if not is_equal_approx(ws.get_rain(), 1.0):
		failures += 1
		print("FAIL: set_rain must clamp at 1.0, got %.2f" % ws.get_rain())
	ws.set_rain(0.35)
	if rain_hits.is_empty() or not is_equal_approx(rain_hits.back(), 0.35):
		failures += 1
		print("FAIL: rain_changed did not fire with the clamped value")
	var quality := ws.get_node_or_null("QualityScaler") as QualityScaler
	if quality != null:
		ws.set_rain(1.0)
		quality.set_mode(QualityScaler.Mode.LOW)
		if not is_equal_approx(ws.visual_rain_level(), 0.5):
			failures += 1
			print("FAIL: LOW visual rain should be presentation-scaled")
		quality.set_mode(QualityScaler.Mode.HIGH)
		if not is_equal_approx(ws.visual_rain_level(), 1.0):
			failures += 1
			print("FAIL: HIGH visual rain should retain full presentation level")

	# --- Wind: set/get plus gust starting high and easing back to calm ---
	var wind_hits: Array[Vector2] = []
	ws.wind_changed.connect(func(v: Vector2): wind_hits.append(v))
	var gust_dir := Vector2(1, 0)
	ws.gust(gust_dir, 0.8)
	if ws.get_wind().length() < 0.5:
		failures += 1
		print("FAIL: gust should raise wind, got ", ws.get_wind())
	ws.gust(Vector2(-1, 0), 0.6)
	if ws.get_wind().x > -0.5:
		failures += 1
		print("FAIL: repeated gust should replace the active wind impulse")
	await create_timer(2.2).timeout  # real time: tween advances on delta, not frames
	if ws.get_wind().length() > 0.05:
		failures += 1
		print("FAIL: gust must ease wind back toward calm, got ", ws.get_wind())

	# --- Realm / time-of-day / night boundaries ---
	var realm_hits: Array[String] = []
	ws.realm_environment_changed.connect(func(r: String): realm_hits.append(r))
	ws.set_realm("mistfen")
	if ws.get_realm() != "mistfen":
		failures += 1
		print("FAIL: set_realm did not stick")
	if realm_hits.is_empty() or realm_hits.back() != "mistfen":
		failures += 1
		print("FAIL: realm_environment_changed did not fire")
	ws.set_time_of_day(0.5)
	if ws.is_night():
		failures += 1
		print("FAIL: is_night must be false at midday 0.5")
	ws.set_time_of_day(0.1)
	if not ws.is_night():
		failures += 1
		print("FAIL: is_night must be true before 0.22")
	ws.set_time_of_day(0.9)
	if not ws.is_night():
		failures += 1
		print("FAIL: is_night must be true after 0.75")
	ws.set_time_of_day(1.3)
	if not is_equal_approx(ws.get_time_of_day(), 0.3):
		failures += 1
		print("FAIL: set_time_of_day must wrap by 1.0, got %.2f" % ws.get_time_of_day())

	# --- Gathered / landmark persistence ---
	ws.mark_gathered("node_01", 120.0)
	if not ws.is_gathered("node_01"):
		failures += 1
		print("FAIL: marked node not reported gathered")
	if not ws.discover_landmark("elder_oak"):
		failures += 1
		print("FAIL: first landmark discovery should return true")
	if ws.discover_landmark("elder_oak"):
		failures += 1
		print("FAIL: duplicate landmark discovery should return false")
	if not ws.has_discovered("elder_oak"):
		failures += 1
		print("FAIL: discovered landmark not reported")

	# --- Save round-trip: to_dict -> mutate -> from_dict restores exactly ---
	ws.set_combat_intensity(0.7)
	ws.set_rain(0.6)
	ws.set_magic_level(0.8)
	ws.set_realm("heartwood")
	ws.set_time_of_day(0.12)
	var snap: Dictionary = ws.to_dict()
	ws.set_combat_intensity(0.1)
	ws.set_rain(0.1)
	ws.set_magic_level(0.1)
	ws.set_realm("bramblewood")
	ws.set_time_of_day(0.5)
	ws.from_dict(snap)
	if not is_equal_approx(ws.get_combat_intensity(), 0.7) \
			or not is_equal_approx(ws.get_rain(), 0.6) \
			or not is_equal_approx(ws.magic_level, 0.8) \
			or ws.get_realm() != "heartwood" \
			or not is_equal_approx(ws.get_time_of_day(), 0.12):
		failures += 1
		print("FAIL: from_dict did not restore the saved snapshot")
	if not ws.has_discovered("elder_oak") or not ws.is_gathered("node_01"):
		failures += 1
		print("FAIL: from_dict dropped discovered/gathered state")

	# Best-effort shader-global mirror check (skip if the headless dummy
	# renderer cannot serve global params back).
	var mirror: Variant = RenderingServer.global_shader_parameter_get("world_rain_level")
	if mirror is float and not is_equal_approx(float(mirror), 0.6):
		failures += 1
		print("FAIL: world_rain_level shader global out of sync: ", mirror)

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
