extends SceneTree

# Release Qualification Test Suite (headless, CI-safe, zero external save dependencies).
# Run via: godot --headless --path . --script res://tests/release_qualification.gd

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] %s" % label)
	else:
		print("  [FAIL] %s" % label)
		_failures.append(label)


func _run() -> void:
	print("============================================================")
	print("  3D Train Game — Release Qualification Test Suite")
	print("============================================================")

	# ------------------------------------------------------------------
	# GATE 1: Boot, Data & Asset Integrity
	# ------------------------------------------------------------------
	print("\n[Gate 1] Boot, Data & Asset Integrity")
	var main_scn := load("res://scenes/main.tscn") as PackedScene
	_check(main_scn != null, "Main scene res://scenes/main.tscn loads cleanly")
	if main_scn == null:
		_finish(null)
		return

	var m := main_scn.instantiate()
	root.add_child(m)
	await process_frame
	var boot_frames := 0
	while bool(m._startup_loading) and boot_frames < 240:
		await process_frame
		boot_frames += 1
	await process_frame

	_check(not bool(m._startup_loading), "Startup loading completes cleanly (%d frames)" % boot_frames)
	var models_arr: Array = m._tram_models
	_check(models_arr.size() >= 15, "Tram catalogue loaded (%d models)" % models_arr.size())
	_check(m._weather is WeatherSystem, "WeatherSystem node initialized")
	_check(m._sound is SoundSynth, "SoundSynth node initialized")

	# ------------------------------------------------------------------
	# GATE 2: Seattle Demo 120s Multi-Line Simulation & Interlocking
	# ------------------------------------------------------------------
	print("\n[Gate 2] Seattle Demo 120s Multi-Line Simulation & Interlocking")
	m._selected_home_map = "seattle"
	m._start_map_demo_network()
	await process_frame

	var tsim: TransitSim = m._transit_sim
	var g: NetworkGraph = m._graph
	var psim: PassengerSim = m._pax_sim
	_check(g.lines.size() >= 1 and tsim.trams.size() >= 2, "Seattle demo network launched (%d lines, %d trams)" % [g.lines.size(), tsim.trams.size()])

	var accident_ev := {}
	var dup_plat_violations := 0
	var crossover_intrusions := 0
	for step in range(1200): # 120 seconds @ 0.1s
		var ev := tsim.step_all_trams(0.1, g, psim, m._traffic_sim, m._sound)
		if not ev.is_empty():
			accident_ev = ev
			break

		# Check terminal interlocking invariants every step
		var held_map := {}
		for i in range(tsim.trams.size()):
			var tr: Dictionary = tsim.trams[i]
			var elev := 1 if bool(tr.get("elevated", false)) else 0
			var res: Dictionary = tr.get("term_res", {})
			for sid in res:
				var plat := int((res[sid] as Dictionary)["platform"])
				var k := "%d:%d:%d" % [elev, int(sid), plat]
				if held_map.has(k):
					dup_plat_violations += 1
				held_map[k] = i
			if bool(tr["is_loop"]):
				var rlen := float(tr["route_len"])
				var dir := float(tr["dir"])
				var s_now := float(tr["s"])
				for z: Dictionary in tr.get("terminal_zones", []):
					var sid := int(z["station_id"])
					if res.has(sid):
						continue
					var hold_s := float(z["hold_s"])
					var cusp_s := float(z["cusp_s"])
					var arr_len := fposmod((cusp_s - hold_s) * dir, rlen)
					var from_hold := fposmod((s_now - hold_s) * dir, rlen)
					if from_hold <= arr_len + 0.5 and from_hold > NetworkGraph.TERMINAL_HOLD_MARGIN_M - 1.5:
						crossover_intrusions += 1

		# Mid-run save/reload integrity check at t=60s (with term_res stripped)
		if step == 600:
			var exp_mid := tsim.export_run_state()
			var exp_strip := exp_mid.duplicate(true)
			for td in exp_strip["trams"]:
				(td as Dictionary).erase("term_res")
			tsim.import_run_state(exp_strip, g)

	var max_dist := 0.0
	for tr: Dictionary in tsim.trams:
		max_dist = maxf(max_dist, float(tr.get("st_dist_m", 0.0)))
	_check(accident_ev.is_empty(), "Zero accidents / derailments over 120s (%s)" % ("NONE" if accident_ev.is_empty() else str(accident_ev)))
	_check(dup_plat_violations == 0, "Zero duplicate terminal platform reservations (%d)" % dup_plat_violations)
	_check(crossover_intrusions == 0, "Zero unauthorized terminal crossover intrusions (%d)" % crossover_intrusions)
	_check(max_dist > 150.0, "Trams actively travel along routes (max dist %.1fm)" % max_dist)

	# ------------------------------------------------------------------
	# GATE 3: Per-Line AI Mode Groups (incl. No Default) & Run Persistence
	# ------------------------------------------------------------------
	print("\n[Gate 3] Per-Line AI Mode Groups & Run-Slot Persistence")
	var line_ids: Array = g.lines.keys()
	line_ids.sort()
	var lid0 := int(line_ids[0])
	var l0_idxs := tsim.line_tram_indices(lid0)
	_check(tsim.get_line_ai_style(lid0) == TransitSim.LINE_AI_NONE, "Initial line AI group default is LINE_AI_NONE")
	m._on_set_line_ai_style(lid0, TransitSim.AIStyle.FURIOUS)
	var all_fur := (tsim.get_line_ai_style(lid0) == TransitSim.AIStyle.FURIOUS)
	for ti in l0_idxs:
		if int(tsim.trams[ti]["ai_style"]) != TransitSim.AIStyle.FURIOUS:
			all_fur = false
	_check(all_fur, "Setting line AI group to FURIOUS updates all %d trams on line %d" % [l0_idxs.size(), lid0])
	tsim.set_tram_ai_style(l0_idxs[0], TransitSim.AIStyle.SLOW)
	m._on_set_line_ai_style(lid0, TransitSim.LINE_AI_NONE)
	_check(
		tsim.get_line_ai_style(lid0) == TransitSim.LINE_AI_NONE
		and int(tsim.trams[l0_idxs[0]]["ai_style"]) == TransitSim.AIStyle.SLOW,
		"Resetting line AI group to No Default clears line default while keeping per-tram mode"
	)

	var exp_ai := tsim.export_run_state()
	tsim.line_ai_styles[lid0] = TransitSim.AIStyle.FURIOUS
	tsim.set_tram_ai_style(l0_idxs[0], TransitSim.AIStyle.NORMAL)
	tsim.import_run_state(exp_ai, g)
	_check(
		tsim.get_line_ai_style(lid0) == TransitSim.LINE_AI_NONE
		and int(tsim.trams[l0_idxs[0]]["ai_style"]) == TransitSim.AIStyle.SLOW
		and (m._line_ai_style_btns as Array).size() == 4,
		"Run-state export/import restores No Default, per-tram overrides, and 4 HUD buttons"
	)

	# ------------------------------------------------------------------
	# GATE 4: Weather System (Sunny / Cloudy / Rainy) & Stereo Rain Sound
	# ------------------------------------------------------------------
	print("\n[Gate 4] Weather System & Rain Audio")
	var env: Environment = m._world_env.environment
	var sun: DirectionalLight3D = m._sun
	var wx: WeatherSystem = m._weather
	var snd: SoundSynth = m._sound
	m._set_time_hours(13.5)

	m._set_weather_mode(WeatherSystem.WeatherType.SUNNY, false)
	await process_frame
	await process_frame
	var sunny_e := sun.light_energy
	_check((not env.fog_enabled) and (not wx._rain_particles.emitting) and snd.weather_rain_intensity <= 0.01, "Sunny: clear sky, no fog, no rain particles/audio")

	m._set_weather_mode(WeatherSystem.WeatherType.CLOUDY, false)
	await process_frame
	await process_frame
	var cloudy_e := sun.light_energy
	_check(env.fog_enabled and (not wx._rain_particles.emitting) and cloudy_e < sunny_e * 0.55, "Cloudy: overcast fog enabled, diffused sunlight")

	m._set_weather_mode(WeatherSystem.WeatherType.RAINY, false)
	m._cam_mode = 1 # CHASE
	await process_frame
	await process_frame
	var rain_chase_ok: bool = env.fog_enabled and wx._rain_particles.emitting and sun.light_energy < cloudy_e and snd.weather_rain_intensity >= 0.99 and (not snd.weather_rain_muffled)
	m._cam_mode = 0 # CAB
	await process_frame
	await process_frame
	var rain_cab_ok: bool = snd.weather_rain_muffled and snd.weather_rain_intensity >= 0.99
	var save_payload: Dictionary = m._build_current_save_payload("rq_test")
	_check(rain_chase_ok and rain_cab_ok and int(save_payload.get("weather", -1)) == WeatherSystem.WeatherType.RAINY, "Rainy: fog, GPU rain streaks, stereo/cab-muffled audio & save persistence")
	m._set_weather_mode(WeatherSystem.WeatherType.SUNNY, false)

	# ------------------------------------------------------------------
	# GATE 5: Bilingual Localization (Auto / ZH / EN) & UI Hygiene
	# ------------------------------------------------------------------
	print("\n[Gate 5] Bilingual Localization & UI Hygiene")
	var sys_loc := OS.get_locale().to_lower()
	var expect_auto := "zh" if sys_loc.begins_with("zh") else "en"
	_check(L10n.detect_system_lang() == expect_auto, "System locale '%s' auto-maps to '%s'" % [sys_loc, expect_auto])

	m._on_set_language("en")
	await process_frame
	var en_build_txt: String = m._btn_mode_build.text
	var en_cats: Array[String] = []
	for cb: Button in m._build_cat_btns:
		en_cats.append(cb.text)

	m._on_set_language("zh")
	await process_frame
	var zh_build_txt: String = m._btn_mode_build.text
	var zh_cats: Array[String] = []
	for cb: Button in m._build_cat_btns:
		zh_cats.append(cb.text)

	m._on_set_language("auto")
	await process_frame

	_check(en_build_txt == "[1] Build Track" and zh_build_txt == "[1] 建设轨道", "Live EN/ZH language switching updates UI cleanly")
	var no_parens := true
	for ct in (en_cats + zh_cats):
		if "(" in ct or ")" in ct or "（" in ct or "）" in ct:
			no_parens = false
	_check(no_parens and en_cats.size() == 5 and zh_cats.size() == 5, "Build panel accordion headers have zero confusing parentheses")

	# ------------------------------------------------------------------
	# GATE 6: Grid City Map & Mode Transition Smoke Test
	# ------------------------------------------------------------------
	print("\n[Gate 6] Grid City Map & Mode Transition Smoke Test")
	m._selected_home_map = "grid_city"
	m._start_map_demo_network()
	await process_frame
	m._set_game_mode(0) # BUILD
	await process_frame
	m._set_game_mode(1) # PLAN
	await process_frame
	m._set_game_mode(2) # RUN
	await process_frame
	var grid_ev := {}
	for _s in range(100):
		grid_ev = m._transit_sim.step_all_trams(0.1, m._graph, m._pax_sim, m._traffic_sim, m._sound)
		if not grid_ev.is_empty():
			break
	_check(m._graph.edges.size() > 20 and m._transit_sim.trams.size() >= 1 and grid_ev.is_empty(), "Grid City loads, transitions BUILD->PLAN->RUN, and runs 10s cleanly")

	_finish(m)


func _finish(m: Node) -> void:
	print("\n============================================================")
	if _failures.is_empty():
		print("  RELEASE QUALIFICATION RESULT: ALL GATES PASSED")
	else:
		print("  RELEASE QUALIFICATION RESULT: FAILED (%d failures)" % _failures.size())
		for f in _failures:
			print("    - %s" % f)
	print("============================================================")
	if m != null and is_instance_valid(m):
		m.queue_free()
		await process_frame
	quit(0 if _failures.is_empty() else 1)
