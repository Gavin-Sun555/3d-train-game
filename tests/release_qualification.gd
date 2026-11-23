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
	m._selected_home_map = "grid"
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

	# ------------------------------------------------------------------
	# GATE 7: Jiaxing Map (Nanhu + Changshui-Qingfeng-Jiaxing South HSR)
	# ------------------------------------------------------------------
	print("\n[Gate 7] Jiaxing Map, Landmarks & Tram T1 60s Run")
	m._selected_home_map = "jiaxing"
	m._start_map_demo_network()
	await process_frame
	var jx_graph: NetworkGraph = m._graph
	var jx_tsim: TransitSim = m._transit_sim
	var jx_lm: Node = m._city_root.get_node_or_null("JiaxingLandmarks")
	var jx_hsr: Node = jx_lm.get_node_or_null("JiaxingSouthHSRStation") if jx_lm != null else null
	var jx_yanyu: Node = jx_lm.get_node_or_null("NanhuYanyuTowerAndRedBoat") if jx_lm != null else null
	var jx_mem: Node = jx_lm.get_node_or_null("NanhuRevolutionaryMemorialHall") if jx_lm != null else null
	var jx_sta: Node = jx_lm.get_node_or_null("JiaxingForestRailwayStation") if jx_lm != null else null
	var jx_rail: Node = jx_lm.get_node_or_null("JiaxingHeavyRailways") if jx_lm != null else null
	var jx_water: Node = m._city_root.get_node_or_null("WaterAreas")
	var jx_island: Node = m._city_root.get_node_or_null("IslandParkAreas")
	var jx_seawall: Node = jx_yanyu.get_node_or_null("LakeHeartIslandSeawall") if jx_yanyu != null else null
	_check(
		jx_graph.edges.size() >= 1500 and jx_tsim.trams.size() >= 2 and jx_graph.stations.size() >= 5,
		"Jiaxing street graph & Tram T1 demo loaded (%d edges, %d stations, %d trams)" % [jx_graph.edges.size(), jx_graph.stations.size(), jx_tsim.trams.size()]
	)
	_check(
		jx_hsr != null and jx_yanyu != null and jx_mem != null and jx_sta != null and jx_rail != null,
		"All bespoke Jiaxing 3D landmarks & heavy railways built (HSR South Sta., Yanyu Tower, Memorial Hall, Forest Station, Heavy Railways)"
	)
	var jx_gov: Node = jx_lm.get_node_or_null("JiaxingMunicipalGovernment") if jx_lm != null else null
	var jx_no1: Node = jx_lm.get_node_or_null("JiaxingNo1HighSchool") if jx_lm != null else null
	var jx_yuehe: Node = jx_lm.get_node_or_null("YueheHistoricQuarter") if jx_lm != null else null
	var jx_zicheng: Node = jx_lm.get_node_or_null("ZichengHistoricSitePark") if jx_lm != null else null
	var jx_cp: Node = jx_lm.get_node_or_null("JiaxingCentralParkLandmark") if jx_lm != null else null
	var jx_haogu: Node = jx_lm.get_node_or_null("NanhuHaoguPagoda") if jx_lm != null else null
	var jx_tiandi: Node = jx_lm.get_node_or_null("NanhuTiandiDistrict") if jx_lm != null else null
	var jx_ap: Node = jx_lm.get_node_or_null("JiaxingNanhuAirport") if jx_lm != null else null
	_check(
		jx_gov != null and jx_no1 != null and jx_yuehe != null and jx_zicheng != null and jx_cp != null and jx_haogu != null and jx_tiandi != null and jx_ap != null,
		"All iconic Jiaxing civic/scenic landmarks & Nanhu Airport built (Gov, No.1 High School, Yuehe, Zicheng, Central Park, Haogu Pagoda, Nanhu Tiandi, Airport)"
	)
	_check(
		(m._map_data.get("freeways", []) as Array).size() >= 300 and (m._map_data.get("storefronts", []) as Array).size() >= 3500,
		"Inner Ring + Airport Expressway (%d viaduct pieces) & authentic Jiaxing storefronts (%d shops)" % [(m._map_data.get("freeways", []) as Array).size(), (m._map_data.get("storefronts", []) as Array).size()]
	)
	_check(
		jx_water != null and jx_island != null and jx_seawall != null,
		"Nanhu Lake, Huancheng Moat water layer, Lake Heart Island turf & stone seawall built"
	)
	var conv_cnt := 0
	var hsr_cnt := 0
	var hsr_min_x := 1e9
	var hsr_max_x := -1e9
	for rw: Dictionary in m._map_data.get("railways", []):
		if str(rw.get("kind", "")) == "hsr":
			hsr_cnt += 1
			for p in rw.get("pts", []):
				hsr_min_x = minf(hsr_min_x, float(p[0]))
				hsr_max_x = maxf(hsr_max_x, float(p[0]))
		else:
			conv_cnt += 1
	_check(
		conv_cnt >= 30 and hsr_cnt >= 20 and (hsr_max_x - hsr_min_x) >= 2400.0,
		"Jiaxing railways complete (%d conventional 沪昆线, %d extended HSR spanning %.0fm)" % [conv_cnt, hsr_cnt, hsr_max_x - hsr_min_x]
	)
	var jx_rc: Array = m._map_data.get("landmarks", {}).get("rail_crossings", [])
	var tun_rc := 0
	var br_rc := 0
	for rc_i: Dictionary in jx_rc:
		if str(rc_i.get("kind", "")) == "bridge":
			br_rc += 1
		else:
			tun_rc += 1
	_check(
		jx_rc.size() >= 8 and tun_rc >= 4 and br_rc >= 2,
		"沪昆线 crossings connected with grade-separated tunnels & bridges (%d tunnels, %d bridges)" % [tun_rc, br_rc]
	)
	# Verify PlazaAreas & RoadMarkings use depth-pushed shaders so tracks are NEVER covered
	var pl_node := m._city_root.get_node_or_null("PlazaAreas") as MeshInstance3D
	var rm_node := m._city_root.get_node_or_null("RoadMarkings") as MeshInstance3D
	_check(
		(pl_node == null or pl_node.material_override is ShaderMaterial) and (rm_node == null or rm_node.material_override is ShaderMaterial),
		"PlazaAreas & RoadMarkings use depth-pushed ShaderMaterials behind tram tracks"
	)
	# Verify zoomed-out CityOverview & bird camera far plane on flat tiled Jiaxing map (no grey void clipping)
	var jx_ov := CityOverview.build(m._overview_snapshot())
	var ov_ground := jx_ov.get_node_or_null("OverviewGround")
	var ov_blds := jx_ov.get_node_or_null("OverviewBuildings")
	m._set_game_mode(0) # BUILD (bird's-eye)
	m._plan_height = 1800.0
	m._update_camera(0.05)
	_check(
		ov_ground != null and ov_blds != null and m._camera.far >= 4500.0,
		"Jiaxing zoomed-out CityOverview builds cleanly & camera far plane scales to %.0fm" % m._camera.far
	)
	jx_ov.free()
	m._set_game_mode(2) # back to RUN
	var jx_ev := {}
	var last_s_jx: Array[float] = []
	var max_stuck_jx := 0.0
	var cur_stuck_jx: Array[float] = []
	for tr_i: Dictionary in jx_tsim.trams:
		last_s_jx.append(float(tr_i.get("s", 0.0)))
		cur_stuck_jx.append(0.0)
	for _js in range(1800): # 180 seconds @ 0.1s with active street traffic & passengers!
		var fpos: Vector3 = ((jx_tsim.trams[0]["tram_info"]["sections"] as Array)[0] as Node3D).global_position
		m._pax_sim.step_simulation(0.1, jx_graph, fpos)
		m._traffic_sim.step_traffic(0.1, jx_graph, jx_tsim.trams, jx_tsim.active_tram_idx, false, fpos)
		jx_ev = jx_tsim.step_all_trams(0.1, jx_graph, m._pax_sim, m._traffic_sim, m._sound)
		if not jx_ev.is_empty():
			break
		for ti in range(jx_tsim.trams.size()):
			var cs := float(jx_tsim.trams[ti].get("s", 0.0))
			if absf(cs - last_s_jx[ti]) < 0.05:
				cur_stuck_jx[ti] += 0.1
				max_stuck_jx = maxf(max_stuck_jx, cur_stuck_jx[ti])
			else:
				cur_stuck_jx[ti] = 0.0
			last_s_jx[ti] = cs
	var jx_min_d := 1e9
	var jx_max_d := 0.0
	for tr: Dictionary in jx_tsim.trams:
		var dd := float(tr.get("st_dist_m", 0.0))
		jx_min_d = minf(jx_min_d, dd)
		jx_max_d = maxf(jx_max_d, dd)
	_check(
		jx_ev.is_empty() and jx_min_d > 500.0 and max_stuck_jx < 60.0,
		"Jiaxing Tram T1 runs 180s with traffic cleanly & zero deadlocks (min dist %.0fm, max %.0fm, max stop %.1fs)" % [jx_min_d, jx_max_d, max_stuck_jx]
	)

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
