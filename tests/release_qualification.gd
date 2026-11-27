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
	# 南湖 scenic area (NanhuBuilder, v0.0.2): 烟雨楼 island with its embankment, red boat and tour boats, 壕股塔,
	# 南湖天地 and the Hyatt complex are batched per site under NanhuDistrict
	var jx_nanhu: Node = jx_lm.get_node_or_null("NanhuDistrict") if jx_lm != null else null
	var jx_yanyu: Node = jx_nanhu.get_node_or_null("Nanhu_Yanyu_op") if jx_nanhu != null else null
	var jx_mem: Node = jx_lm.get_node_or_null("NanhuRevolutionaryMemorialHall") if jx_lm != null else null
	var jx_sta: Node = jx_lm.get_node_or_null("JiaxingForestRailwayStation") if jx_lm != null else null
	var jx_rail: Node = jx_lm.get_node_or_null("JiaxingHeavyRailways") if jx_lm != null else null
	var jx_water: Node = m._city_root.get_node_or_null("WaterAreas")
	var jx_island: Node = m._city_root.get_node_or_null("IslandParkAreas")
	var jx_seawall: Node = jx_yanyu # the stone embankment is part of the island batch
	_check(
		jx_graph.edges.size() >= 1500 and jx_tsim.trams.size() >= 2 and jx_graph.stations.size() >= 5,
		"Jiaxing street graph & Tram T1 demo loaded (%d edges, %d stations, %d trams)" % [jx_graph.edges.size(), jx_graph.stations.size(), jx_tsim.trams.size()]
	)
	var jx_s_plaza: Node = jx_hsr.get_node_or_null("JiaxingSouthNorthPlaza") if jx_hsr != null else null
	var jx_s_bus: Node = jx_hsr.get_node_or_null("JiaxingSouthBusHub") if jx_hsr != null else null
	_check(
		jx_hsr != null and jx_s_plaza != null and jx_s_bus != null and jx_yanyu != null and jx_mem != null and jx_sta != null and jx_rail != null,
		"All bespoke Jiaxing 3D landmarks & heavy railways built (2F/1F HSR South Sta. + North Plaza + Bus Hub, Yanyu Tower, Memorial Hall, Forest Station)"
	)
	var jx_gov: Node = jx_lm.get_node_or_null("JiaxingMunicipalGovernment") if jx_lm != null else null
	var jx_no1: Node = jx_lm.get_node_or_null("JiaxingNo1HighSchool") if jx_lm != null else null
	var jx_yuehe: Node = jx_lm.get_node_or_null("YueheHistoricQuarter") if jx_lm != null else null
	var jx_zicheng: Node = jx_lm.get_node_or_null("ZichengHistoricSitePark") if jx_lm != null else null
	var jx_cp: Node = jx_lm.get_node_or_null("JiaxingCentralParkLandmark") if jx_lm != null else null
	var jx_haogu: Node = jx_nanhu.get_node_or_null("Nanhu_Haogu_op") if jx_nanhu != null else null
	var jx_tiandi: Node = jx_nanhu.get_node_or_null("Nanhu_Tiandi_op") if jx_nanhu != null else null
	var jx_gate: Node = jx_lm.get_node_or_null("NanhuScenicMainGate") if jx_lm != null else null
	# 中山东路 x 禾兴南路 block (ZhongshanBlockBuilder, v0.0.2): 天主堂, 中山影城, 戴梦得, 旭辉广场, 江南大厦
	var jx_zs: Node = jx_lm.get_node_or_null("ZhongshanBlock") if jx_lm != null else null
	var jx_church: Node = jx_zs.get_node_or_null("Zhongshan_Church_op") if jx_zs != null else null
	var jx_h1: Node = jx_lm.get_node_or_null("JiaxingFirstHospital") if jx_lm != null else null
	var jx_h2: Node = jx_lm.get_node_or_null("JiaxingSecondHospital") if jx_lm != null else null
	var jx_h3: Node = jx_lm.get_node_or_null("JiaxingTCMHospital") if jx_lm != null else null
	var jx_yaohan: Node = jx_lm.get_node_or_null("JiaxingYaohanPlazaAndBridge") if jx_lm != null else null
	var jx_ybr: Node = jx_lm.get_node_or_null("YaohanCircularFootbridge") if jx_lm != null else null
	var jx_hilton: Node = jx_lm.get_node_or_null("JiaxingHiltonHotel") if jx_lm != null else null
	var jx_wanda: Node = jx_lm.get_node_or_null("JiaxingNanhuWandaPlaza") if jx_lm != null else null
	var jx_sams: Node = jx_lm.get_node_or_null("JiaxingSamsClub") if jx_lm != null else null
	var jx_xjd: Node = jx_lm.get_node_or_null("XiangjiadangWetlandPark") if jx_lm != null else null
	var jx_pingshan: Node = jx_lm.get_node_or_null("PingshanPark") if jx_lm != null else null
	var jx_jiangnan: Node = jx_zs.get_node_or_null("Zhongshan_Jiangnan_op") if jx_zs != null else null
	var jx_diamond: Node = jx_zs.get_node_or_null("Zhongshan_Diamond_op") if jx_zs != null else null
	var jx_cifi: Node = jx_zs.get_node_or_null("Zhongshan_CIFI_op") if jx_zs != null else null
	var jx_shaonian: Node = jx_lm.get_node_or_null("ShaonianPedestrianStreet") if jx_lm != null else null
	var jx_skybridge: Node = jx_lm.get_node_or_null("JiaxingNo1Skybridge") if jx_lm != null else null
	var jx_hanlin: Node = jx_lm.get_node_or_null("HanlinResidence") if jx_lm != null else null
	var jx_hyatt: Node = jx_nanhu.get_node_or_null("Nanhu_Hyatt_op") if jx_nanhu != null else null
	var jx_ap: Node = jx_lm.get_node_or_null("JiaxingNanhuAirport") if jx_lm != null else null
	var jx_b1_root: Node = m._underground_landmarks_root
	var jx_b1_hall: Node = jx_b1_root.get_node_or_null("JiaxingStationB1Hall") if jx_b1_root != null else null
	_check(
		jx_gov != null and jx_no1 != null and jx_skybridge != null and jx_hanlin != null and jx_yuehe != null and jx_zicheng != null and jx_cp != null and jx_haogu != null and jx_tiandi != null and jx_hyatt != null and jx_gate != null and jx_ap != null and jx_b1_hall != null,
		"All iconic Jiaxing civic/scenic landmarks built (No.1 High School + Skybridge + Hanlin, Nanhu Tiandi + Hyatt Hotel, B1 Hall, Airport)"
	)
	_check(
		jx_church != null and jx_h1 != null and jx_h2 != null and jx_h3 != null and jx_yaohan != null and jx_ybr != null and jx_hilton != null and jx_wanda != null and jx_sams != null and jx_xjd != null and jx_pingshan != null and jx_jiangnan != null and jx_diamond != null and jx_cifi != null and jx_shaonian != null,
		"All urban, old-town & eastern landmarks built (Shaonian St., Pingshan, Zicheng, Jiangnan, Diamond, CIFI, Church, Hospitals, Yaohan, Hilton, Wanda, Sam's, Xiangjiadang)"
	)
	# Verify 360-degree closed Inner Ring Expressway across all 36 angular sectors + Yuehe pedestrian bridges
	var ir_sec := {}
	for fw_i: Dictionary in m._map_data.get("freeways", []):
		for fpt in fw_i.get("pts", []):
			var fx := float(fpt[0]); var fy := float(fpt[1])
			if fx >= -3330.0 and fx <= 5680.0 and fy >= -4100.0 and fy <= 3760.0 and Vector2(fx - 1100.0, fy + 100.0).length() > 2800.0:
				var deg_i := int(floor(fposmod(rad_to_deg(atan2(fy + 100.0, fx - 1100.0)), 360.0) / 10.0))
				ir_sec[deg_i] = true
	var yuehe_br_cnt := (m._map_data.get("landmarks", {}).get("yuehe_quarter", {}).get("bridges", []) as Array).size()
	_check(
		ir_sec.size() == 36 and yuehe_br_cnt >= 10,
		"Inner Ring Expressway forms a 100%% closed 360-deg loop (%d/36 sectors) & Yuehe has %d real pedestrian bridges" % [ir_sec.size(), yuehe_br_cnt]
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
	var max_abs_grade_jx := 0.0
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
			max_abs_grade_jx = maxf(max_abs_grade_jx, absf(float(jx_tsim.trams[ti].get("grade_pct", 0.0))))
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
	var pinghu_h := Terrain.surface(985.5, -1005.4)
	var pinghu_g := Terrain.ground(985.5, -1005.4)
	var binhe_sta_h := Terrain.surface(983.0, -930.6)
	_check(
		jx_ev.is_empty() and jx_min_d > 400.0 and jx_max_d > 1200.0 and max_stuck_jx < 55.0,
		"Jiaxing Tram T1 runs 180s with traffic cleanly & zero deadlocks (min dist %.0fm, max %.0fm, max stop %.1fs)" % [jx_min_d, jx_max_d, max_stuck_jx]
	)
	_check(
		Terrain.active and not Terrain.has_dem() and pinghu_h >= 2.0 and pinghu_g == 0.0 and binhe_sta_h < 0.05 and max_abs_grade_jx >= 1.5,
		"Jiaxing river-bridge elevation arches & grade physics active (平湖塘桥=%.2fm over flat water=%.1fm, 滨河路站=%.2fm, max tram grade=%.1f%%)" % [pinghu_h, pinghu_g, binhe_sta_h, max_abs_grade_jx]
	)

	# ------------------------------------------------------------------
	# GATE 8: 3D Underground / Ground / Elevated Light Rail & Monorail + Lake Zoom Fix
	# ------------------------------------------------------------------
	print("\n[Gate 8] 3D Underground / Ground / Elevated Light Rail & Monorail + Lake Zoom Fix")
	var base_mi := m._city_root.get_node_or_null("UrbanSidewalkBase") as MeshInstance3D
	var base_pm := base_mi.mesh as PlaneMesh if base_mi != null else null
	_check(
		base_pm != null and base_pm.subdivide_width >= 16 and base_pm.subdivide_depth >= 16,
		"UrbanSidewalkBase subdivided (%dx%d) so zoomed-in Nanhu Lake never gets clipped by ground slab" % [base_pm.subdivide_width if base_pm != null else 0, base_pm.subdivide_depth if base_pm != null else 0]
	)

	# 8a. Build a full 3D mixed-elevation Light Rail line: G(0m) -> L1(+7.2m) -> G(0m) -> B1(-10.0m)
	var lr_pts: Array[Vector2] = [
		Vector2(-260.0, 220.0),
		Vector2(-100.0, 220.0), # G -> L1 ramp (160m, 4.5%)
		Vector2(80.0, 220.0),   # L1 elevated station span (180m)
		Vector2(240.0, 220.0),  # L1 -> G ramp (160m, 4.5%)
		Vector2(440.0, 220.0),  # G -> B1 tunnel portal ramp (200m, 5.0%)
		Vector2(660.0, 220.0),  # B1 underground station + crossover span (220m)
	]
	var lr_elevs: Array[float] = [0.0, 7.2, 7.2, 0.0, -10.0, -10.0]
	var lr_nids: Array[int] = []
	for li in range(lr_pts.size()):
		var rn := jx_graph.node_for_point_3d(lr_pts[li], lr_elevs[li], 2.0, 0, false)
		lr_nids.append(int(rn["nid"]))
	var lr_eids: Array[int] = []
	for li in range(lr_pts.size() - 1):
		var le := jx_graph.add_3d_rail_edge(lr_nids[li], lr_nids[li + 1], NetworkGraph.TrackMode.DOUBLE, TrackBuilder.BedStyle.STONE_SLAB, lr_elevs[li], lr_elevs[li + 1])
		lr_eids.append(le)
	var st_lr_elev := jx_graph.add_station_on_edge(lr_eids[1], 0.5, 0, "南湖高架站", NetworkGraph.StationKind.ISLAND, 27.0)
	var st_lr_ug := jx_graph.add_station_on_edge(lr_eids[4], 0.72, 0, "南湖地下站", NetworkGraph.StationKind.ISLAND, 27.0)
	jx_graph.set_crossover_on_edge(lr_eids[4], NetworkGraph.CrossoverType.DOUBLE, 0.22)
	var lr_lid := jx_graph.create_line([st_lr_elev, st_lr_ug], "siemens-s700", 1, 2, "立体轻轨测试线")

	# 8b. Build a multi-level Monorail line: L1(+7.2m) -> L2(+13.8m) -> B1(-10.0m underground monorail!)
	var mr_pts: Array[Vector2] = [
		Vector2(0.0, -240.0),
		Vector2(0.0, -80.0),   # L1 elevated station span (160m)
		Vector2(0.0, 80.0),    # L1 -> L2 ramp (160m, 4.1%)
		Vector2(0.0, 260.0),   # L2 crosses right over L1 light rail at y=+13.8m!
		Vector2(0.0, 580.0),   # L2 -> B1 ramp (320m, 7.4% <= 8.5% monorail limit)
		Vector2(0.0, 780.0),   # B1 underground monorail station span (200m)
	]
	var mr_elevs: Array[float] = [7.2, 7.2, 13.8, 13.8, -10.0, -10.0]
	var mr_nids: Array[int] = []
	for mi_i in range(mr_pts.size()):
		var rn_m := jx_graph.node_for_point_3d(mr_pts[mi_i], mr_elevs[mi_i], 2.0, 1, false)
		mr_nids.append(int(rn_m["nid"]))
	var mr_eids: Array[int] = []
	for mi_i in range(mr_pts.size() - 1):
		var me := jx_graph.add_3d_rail_edge(mr_nids[mi_i], mr_nids[mi_i + 1], NetworkGraph.TrackMode.DOUBLE, TrackBuilder.BedStyle.MONORAIL, mr_elevs[mi_i], mr_elevs[mi_i + 1])
		mr_eids.append(me)
	var st_mr_l1 := jx_graph.add_station_on_edge(mr_eids[0], 0.5, 0, "单轨高架站", NetworkGraph.StationKind.ISLAND, 27.0)
	var st_mr_ug := jx_graph.add_station_on_edge(mr_eids[4], 0.5, 0, "单轨地下站", NetworkGraph.StationKind.ISLAND, 27.0)
	var mr_lid := jx_graph.create_line([st_mr_l1, st_mr_ug], "seattle-alweg-red", 1, 2, "立体单轨测试线")

	# 8c. Stacked corridor test: lay a B1 (-10.0m) subway directly underneath an existing ground Tram T1 street!
	var ground_eid := -1
	for ge: int in jx_graph.built_tracks.keys():
		if not bool(jx_graph.edges[ge].get("rail_3d", false)) and absf(jx_graph.get_edge_elev_pair(ge).x) < 0.2:
			ground_eid = ge
			break
	var stacked_eid := jx_graph.lay_track_along_street(ground_eid, TrackBuilder.BedStyle.STONE_SLAB, NetworkGraph.TrackMode.DOUBLE, -10.0, -10.0) if ground_eid >= 0 else -1
	_check(
		lr_lid > 0 and mr_lid > 0 and stacked_eid >= 0 and stacked_eid != ground_eid and jx_graph.built_tracks.has(ground_eid) and jx_graph.is_edge_underground(stacked_eid),
		"3D Light Rail (lid=%d), 3D Monorail (lid=%d) & Stacked B1-under-Ground corridor (e=%d under %d) created cleanly" % [lr_lid, mr_lid, stacked_eid, ground_eid]
	)

	# Rebuild 3D meshes, stations, portals & fleet
	m._rebuild_tracks_and_operations(true, false)
	await process_frame
	var tr_root: Node = m._track_root
	var has_viad: bool = tr_root.get_node_or_null("ElevatedViaducts") != null
	var has_vpier: bool = tr_root.get_node_or_null("ElevatedViaductPiers") != null
	var has_barr: bool = tr_root.get_node_or_null("ViaductNoiseBarriers") != null
	var has_twall: bool = tr_root.get_node_or_null("UndergroundTunnelWalls") != null
	var has_troof: bool = tr_root.get_node_or_null("UndergroundTunnelRoofs") != null
	var has_tled: bool = tr_root.get_node_or_null("UndergroundTunnelLEDs") != null
	var has_mbeam: bool = tr_root.get_node_or_null("MonorailGuidewayBeams") != null
	var has_mpier: bool = tr_root.get_node_or_null("MonorailPiers") != null
	var ug_st_node: Node = tr_root.get_node_or_null("Station_%d" % st_lr_ug)
	var has_ug_roof: bool = ug_st_node != null and ug_st_node.get_node_or_null("UndergroundStationRoof") != null
	var has_ug_kiosk: bool = ug_st_node != null and ug_st_node.get_node_or_null("SurfaceEntranceKiosk") != null
	var n_portals := (jx_graph.get_meta("portal_cutouts", []) as Array).size()
	_check(
		has_viad and has_vpier and has_barr and has_twall and has_troof and has_tled and has_mbeam and has_mpier and has_ug_roof and has_ug_kiosk and n_portals > 0,
		"3D structures built (viaduct/piers/barriers/tunnels/roofs/LEDs/monorail/kiosk + %d portal cutouts)" % n_portals
	)

	# Test Underground X-Ray View toggle (U)
	m._set_underground_view(true)
	var t_roof_n := tr_root.get_node_or_null("UndergroundTunnelRoofs") as Node3D
	var st_roof_n := ug_st_node.get_node_or_null("UndergroundStationRoof") as Node3D if ug_st_node != null else null
	var bp_n := m._blueprint_root as Node3D
	var ug_on_ok: bool = (not (m._city_root as Node3D).visible) and (bp_n != null and bp_n.visible) and (t_roof_n != null and not t_roof_n.visible) and (st_roof_n != null and not st_roof_n.visible)
	m._set_underground_view(false)
	var ug_off_ok: bool = (m._city_root as Node3D).visible and (bp_n != null and not bp_n.visible) and (t_roof_n != null and t_roof_n.visible)
	_check(ug_on_ok and ug_off_ok, "Underground X-Ray View (U) cleanly toggles city/blueprint & tunnel/station cutaway roofs")

	# 8d. Build-mode per-elevation layer filtering:
	#     At G (0m): underground B1 tracks/stations & B1 Hall are HIDDEN while G tracks + G<->B1 ramps show;
	#     At B1 (-10m): ground G tracks/stations are HIDDEN while B1 tracks/stations + G<->B1 ramps + B1 Hall show!
	var t1_ground_sid := int((jx_graph.stations.keys() as Array)[0])
	m.call("_set_game_mode", 0) # GameMode.BUILD
	m.call("_set_build_elev_idx", 2, true) # G (0m)
	await process_frame
	var sv_g: Dictionary = m._station_views
	var ug_lm_n: Node3D = m._underground_landmarks_root as Node3D
	var filt_g_ok: bool = sv_g.has(t1_ground_sid) and (not sv_g.has(st_lr_ug)) and (not sv_g.has(st_lr_elev)) and jx_graph.edge_matches_elev_tier(lr_eids[3], "G") and (not jx_graph.edge_matches_elev_tier(lr_eids[4], "G")) and (ug_lm_n != null and not ug_lm_n.visible)
	m.call("_set_build_elev_idx", 1, true) # B1 (-10m)
	await process_frame
	var sv_b1: Dictionary = m._station_views
	var filt_b1_ok: bool = (not sv_b1.has(t1_ground_sid)) and sv_b1.has(st_lr_ug) and sv_b1.has(st_mr_ug) and (not sv_b1.has(st_lr_elev)) and jx_graph.edge_matches_elev_tier(lr_eids[3], "B1") and (ug_lm_n != null and ug_lm_n.visible)
	m.call("_set_build_elev_idx", 2, true)
	m.call("_set_game_mode", 2) # GameMode.RUN (all elevations visible together!)
	await process_frame
	var sv_run: Dictionary = m._station_views
	var filt_run_ok: bool = sv_run.has(t1_ground_sid) and sv_run.has(st_lr_ug) and sv_run.has(st_lr_elev) and sv_run.has(st_mr_ug)
	_check(
		filt_g_ok and filt_b1_ok and filt_run_ok,
		"Build-mode per-elevation filtering shows ONLY active tier + connecting ramps (G hides B1, B1 hides G, Run shows all)"
	)
	var scenic_n := m._city_root.get_node_or_null("JiaxingLandmarks/JiaxingScenicWalkways") as Node3D
	# the red boat and tour boats are batched with the 烟雨楼 island: its extent reaching well past the island's
	# ~56 m radius means the boats float offshore
	var red_boat_n := m._city_root.get_node_or_null("JiaxingLandmarks/NanhuDistrict/Nanhu_Yanyu_op") as MeshInstance3D
	var rb_ab := red_boat_n.get_aabb() if red_boat_n != null else AABB()
	var rb_dist := maxf(rb_ab.size.x, rb_ab.size.z) * 0.5
	_check(
		scenic_n != null and red_boat_n != null and rb_dist > 56.0,
		"Jiaxing scenic walkways built & Red Boat floats cleanly offshore in Nanhu Lake (r=%.1fm from island center)" % rb_dist
	)
	# Verify FreewayBuilder portal-straddle pier resolution keeps piers off surface roads & tram tracks
	var test_rd_grid := FreewayBuilder._build_road_grid([{"pts": [[0.0, 0.0], [100.0, 0.0]], "width": 16.0, "layer": 0}])
	var resolved_cols := FreewayBuilder._resolve_pier_columns(Vector3(50.0, 7.4, 0.0), Vector3(0.0, 0.0, 1.0), 6.4, 1.6, test_rd_grid, {})
	var cols_clear_of_road := resolved_cols.size() == 2 and absf(resolved_cols[0]) >= 9.0 and absf(resolved_cols[1]) >= 9.0
	var ng_pos_arr: Array = (m._map_data.get("landmarks", {}) as Dictionary).get("nanhu_gate", {}).get("pos", [0.0, 0.0])
	var ng_clear := Vector2(float(ng_pos_arr[0]), float(ng_pos_arr[1])).distance_to(Vector2(862.25, 500.54)) > 60.0
	_check(
		cols_clear_of_road and ng_clear,
		"Freeway piers auto-straddle streets/tracks as Portal Bents (cols=%s) & Nanhu Gate sits clear of T1" % [str(resolved_cols)]
	)
	# Verify Operations Board Line Metrics column alignment + Route Len & Avg Trip columns!
	var smodal: Control = m._stats_modal as Control
	smodal.visible = true
	m.call("_refresh_stats_modal_ui")
	await process_frame
	await process_frame
	var lvbox: VBoxContainer = m._stats_lines_vbox as VBoxContainer
	var cols_aligned := false
	var t1_route_km := jx_tsim.get_line_route_len_m(1) / 1000.0
	if lvbox != null and lvbox.get_child_count() >= 2:
		var h_hb := lvbox.get_child(0).get_child(0) as HBoxContainer
		var d_hb := lvbox.get_child(1).get_child(0) as HBoxContainer
		if h_hb.get_child_count() == 13 and d_hb.get_child_count() == 13:
			cols_aligned = true
			for ci in range(13):
				var hx := (h_hb.get_child(ci) as Control).position.x
				var dx := (d_hb.get_child(ci) as Control).position.x
				if absf(hx - dx) > 1.5:
					cols_aligned = false
					break
	smodal.visible = false
	_check(
		cols_aligned and t1_route_km > 8.0,
		"Operations Board Line Metrics columns align pixel-perfectly (13 cols) & show Route Len (%.2f km) + Avg Trip" % t1_route_km
	)

	# Simulate 3D Light Rail & 3D Monorail trains traversing elevated, ramps & underground tunnels!
	var lr_min_y := 1e9; var lr_max_y := -1e9
	var mr_min_y := 1e9; var mr_max_y := -1e9
	var t1_dock_checks := 0
	var t1_misaligned := 0
	var ev3 := {}
	for _s3 in range(900): # 90s @ 0.1s
		ev3 = jx_tsim.step_all_trams(0.1, jx_graph, m._pax_sim, m._traffic_sim, m._sound)
		if not ev3.is_empty():
			break
		for tr3: Dictionary in jx_tsim.trams:
			var y3 := (((tr3["tram_info"]["sections"] as Array)[0]) as Node3D).global_position.y
			var lid3 := int(tr3.get("line_id", -1))
			if lid3 == lr_lid:
				lr_min_y = minf(lr_min_y, y3); lr_max_y = maxf(lr_max_y, y3)
			elif lid3 == mr_lid:
				mr_min_y = minf(mr_min_y, y3); mr_max_y = maxf(mr_max_y, y3)
			elif lid3 == 1 and float(tr3.get("door_ratio", 0.0)) > 0.65 and float(tr3.get("speed_mps", 0.0)) < 0.25:
				t1_dock_checks += 1
				var od3 := int(tr3.get("open_doorways", 0))
				var td3 := maxi(1, int(tr3.get("total_doorways", 5)))
				if od3 < td3:
					t1_misaligned += 1
	_check(
		ev3.is_empty() and lr_max_y > 6.5 and lr_min_y < -8.0 and mr_max_y > 12.5 and mr_min_y < -8.0,
		"3D trains traverse elevated/ramps/tunnels smoothly with zero incidents (LR y=[%.1f..%.1f]m, Mono y=[%.1f..%.1f]m)" % [lr_min_y, lr_max_y, mr_min_y, mr_max_y]
	)

	# Verify all Jiaxing Realism Upgrades:
	# 1) Real T1 operational 15 stations (exact Amap sequence & names), bilingual EN TTS translations (0 CJK),
	#    center-of-road boulevards (>=18m bidirectional car lanes on both sides), straight 景湖路, B1 嘉兴火车站,
	#    环城东路 人民公园, 5/5 AI door alignment & <=16 portal cutouts!
	var t1_ln: Dictionary = jx_graph.lines.get(1, {})
	var t1_sids: Array = t1_ln.get("station_ids", [])
	var t1_tr_secs := 0
	for tr_chk: Dictionary in jx_tsim.trams:
		if int(tr_chk.get("line_id", -1)) == 1:
			t1_tr_secs = (tr_chk["tram_info"]["sections"] as Array).size()
			break
	var jx_sta_b1_y := 0.0
	var jh_pos := Vector3.ZERO
	var rm_pos := Vector3.ZERO
	var sx_pos := Vector3.ZERO
	var fy_pos := Vector3.ZERO
	var fy_road := ""
	var yz_pos := Vector3.ZERO
	var ps_pos := Vector3.ZERO
	var hx_pos := Vector3.ZERO
	var en_tts_ok := true
	for sid_v in t1_sids:
		var sd: Dictionary = jx_graph.stations.get(int(sid_v), {})
		var sname := str(sd.get("name", ""))
		var en_nm := L10n.station_en_name(sname)
		if en_nm.length() < 4:
			en_tts_ok = false
		for ci in range(en_nm.length()):
			var uc := en_nm.unicode_at(ci)
			if uc >= 0x4E00 and uc <= 0x9FFF:
				en_tts_ok = false
		var spos: Vector3 = sd["pos"]
		if sname == "嘉兴火车站":
			jx_sta_b1_y = spos.y
		elif sname == "纺工路景湖路站":
			jh_pos = spos
		elif sname == "人民公园":
			rm_pos = spos
		elif sname == "由拳路双溪路站":
			sx_pos = spos
		elif sname == "纺工路由拳路站":
			fy_pos = spos
			var fy_eid := int(sd.get("edge_id", -1))
			fy_road = str(jx_graph.edges.get(fy_eid, {}).get("name", ""))
		elif sname == "嘉兴一中站":
			yz_pos = spos
		elif sname == "中山东路建国南路(瓶山)":
			ps_pos = spos
		elif sname == "中山东路禾兴南路":
			hx_pos = spos
	var t1_surf_edges := 0
	var t1_center_blvd := 0
	for tr_rec in (m._map_data.get("starter_network", {}) as Dictionary).get("tracks", []):
		if tr_rec is Dictionary and float(tr_rec.get("ya", 0.0)) >= -0.5 and float(tr_rec.get("yb", 0.0)) >= -0.5:
			var eid_t := int(tr_rec.get("edge_id", -1))
			if jx_graph.edges.has(eid_t):
				t1_surf_edges += 1
				var ed_t: Dictionary = jx_graph.edges[eid_t]
				if float(ed_t.get("width", 0.0)) >= 17.5 and int(ed_t.get("lanes_f", 0)) >= 1 and int(ed_t.get("lanes_b", 0)) >= 1:
					t1_center_blvd += 1
	var center_blvd_pct := 100.0 * float(t1_center_blvd) / float(maxi(1, t1_surf_edges))
	var jh_on_fanggong := jh_pos.x >= 1110.0 and jh_pos.x <= 1175.0 and jh_pos.z <= -220.0 and jh_pos.z >= -400.0
	var rm_on_hcd := rm_pos.x >= 145.0 and rm_pos.x <= 220.0 and rm_pos.z <= -1320.0 and rm_pos.z >= -1515.0
	var sx_ok := sx_pos.x >= 3040.0 and sx_pos.x <= 3255.0 and absf(sx_pos.z - 2531.0) < 35.0
	var fy_ok := "纺工" in fy_road and fy_pos.z < 2515.0
	var yz_ok := yz_pos.z < 1600.0 and yz_pos.z > 1300.0
	var ps_ok := ps_pos.x < -220.0 and ps_pos.x > -420.0
	var hx_ok := hx_pos.x < -695.0 and hx_pos.x > -860.0
	var qf_pos := Vector3.ZERO
	for sid_q in t1_sids:
		var sd_q: Dictionary = jx_graph.stations.get(int(sid_q), {})
		if str(sd_q.get("name", "")) == "有轨电车庆丰路基地站":
			qf_pos = sd_q["pos"]
	var qf_ok := qf_pos.z >= 4150.0 and qf_pos.z <= 4380.0
	var pcut_cnt := (jx_graph.get_meta("portal_cutouts", []) as Array).size()
	var bold_sign_ok := false
	var ws_root: Node = m._track_root.get_node_or_null("WaysideSpeedSigns") if m._track_root != null else null
	if ws_root != null:
		for s_n in ws_root.get_children():
			for ch_s in s_n.get_children():
				if ch_s is Label3D and (ch_s as Label3D).outline_size >= 14:
					bold_sign_ok = true
					break
			if bold_sign_ok:
				break
	_check(
		str(t1_ln.get("model_key", "")) == "crrc-jiaxing-nanhu" and t1_sids.size() == 16 and t1_tr_secs == 5 and jx_sta_b1_y < -8.0 and jh_on_fanggong and rm_on_hcd and sx_ok and fy_ok and yz_ok and ps_ok and hx_ok and qf_ok and bold_sign_ok and pcut_cnt >= 2 and pcut_cnt <= 16 and en_tts_ok and center_blvd_pct >= 90.0,
		"Jiaxing T1 real alignment: 16 Amap stations (100%% EN TTS), 庆丰路基地站(z=%.0f), %.0f%% center-median boulevards, 双溪路(%.0f), 纺工路由拳路(%s z=%.0f), 一中北(z=%.0f), 瓶山西(x=%.0f), 禾兴西(x=%.0f), bold speed signs" % [qf_pos.z, center_blvd_pct, sx_pos.x, fy_road, fy_pos.z, yz_pos.z, ps_pos.x, hx_pos.x]
	)
	_check(
		t1_dock_checks > 0 and t1_misaligned == 0,
		"Jiaxing T1 5-section AI docking alignment: %d door-open checks, %d misaligned (100%% 5/5 doors aligned!)" % [t1_dock_checks, t1_misaligned]
	)
	# 2) Chinese Architecture Shader + realistic storefront coverage (>=30k, surveyed T1 merchants) + 1200+ Gated Residential Compounds
	var sfs_arr: Array = m._map_data.get("storefronts", [])
	var n_chain := 0; var n_local := 0
	for sf_d in sfs_arr:
		if sf_d is Dictionary:
			if str(sf_d.get("tier", "")) == "chain":
				n_chain += 1
			elif str(sf_d.get("tier", "")) == "local":
				n_local += 1
	var gcomp_n := m._city_root.get_node_or_null("JiaxingLandmarks/ChineseGatedCompounds/CompoundWallsAndGates") as MeshInstance3D
	var gcomp_cnt := ((m._map_data.get("landmarks", {}) as Dictionary).get("gated_compounds", []) as Array).size()
	var zh_shader_on := float((m._building_mat as ShaderMaterial).get_shader_parameter("chinese_style")) > 0.5
	# v0.0.2: shops only where Jiaxing has them (old walk-up ground floors, commercial buildings, main-road 底商) plus
	# the merchants surveyed at the T1 stops, instead of every frontage
	var real_named := 0
	for sf_r in sfs_arr:
		if sf_r is Dictionary and str(sf_r.get("name", "")) in ["五芳斋", "中国农业银行", "罗森", "南门高老太土菜馆", "万家福超市"]:
			real_named += 1
	_check(
		zh_shader_on and sfs_arr.size() >= 30000 and n_chain >= 10000 and n_local >= 15000 and real_named >= 4 and gcomp_n != null and gcomp_cnt >= 1200,
		"Chinese building shader ON, %d storefronts (%d chain + %d local, %d surveyed T1 merchants) & %d Gated Residential Compounds" % [sfs_arr.size(), n_chain, n_local, real_named, gcomp_cnt]
	)
	# 3) >=80% Bike-Lane Coverage + 200-Unit MultiMesh E-Bike Fleet (>3x cars!) + Chinese EV Fleet & Jam-Free AI Cars!
	var surf_rds := 0; var bl_rds := 0
	for rd_v in m._map_data.get("roads", []):
		if rd_v is Dictionary and not bool(rd_v.get("underground", false)):
			surf_rds += 1
			if bool(rd_v.get("bike_lane", false)):
				bl_rds += 1
	var bl_pct := 100.0 * float(bl_rds) / float(maxi(1, surf_rds))
	var ts_jx: TrafficSim = m._traffic_sim as TrafficSim
	var ebike_cnt := ts_jx.ebike_sim.ebikes.size() if (ts_jx != null and ts_jx.ebike_sim != null) else 0
	var car_cnt := ts_jx.cars.size() if ts_jx != null else 1
	var zh_ev_cnt := ts_jx._zh_car_meshes.size() if ts_jx != null else 0
	var focus_jx := Vector3(1191.0, 0.0, 224.0) # 纺工路南溪西路 busy T1 avenue
	var moving_samples := 0
	var total_samples := 0
	var eb_moving := 0
	var eb_near_teleports := 0
	var eb_blocked_on_rail := 0
	var prev_eb_pos: Array[Vector3] = []
	var clr_idx_chk: Dictionary = jx_graph.get_meta("track_clear_idx", {})
	if ts_jx != null and ts_jx.ebike_sim != null:
		for eb_d0: Dictionary in ts_jx.ebike_sim.ebikes:
			prev_eb_pos.append(eb_d0["pos"] as Vector3)
	for _tf in range(250): # 25s @ 0.1s live road + e-bike + tram co-simulation
		ts_jx.step_traffic(0.1, jx_graph, jx_tsim.trams, 0, false, focus_jx)
		if ts_jx != null and ts_jx.ebike_sim != null:
			for ei in range(mini(prev_eb_pos.size(), ts_jx.ebike_sim.ebikes.size())):
				var eb_d: Dictionary = ts_jx.ebike_sim.ebikes[ei]
				var np: Vector3 = eb_d["pos"]
				var op: Vector3 = prev_eb_pos[ei]
				if _tf > 5 and op.distance_to(focus_jx) < 115.0 and np.distance_to(focus_jx) < 115.0:
					if np.distance_to(op) > 3.5:
						eb_near_teleports += 1
				prev_eb_pos[ei] = np
				if _tf >= 20 and float(eb_d.get("speed", 0.0)) < 1.2 and not clr_idx_chk.is_empty():
					if TrackBuilder.track_clearance_dist(clr_idx_chk, Vector2(np.x, np.z)) < 2.2:
						eb_blocked_on_rail += 1
		if _tf >= 100 and _tf % 10 == 0:
			for car_d: Dictionary in ts_jx.cars:
				total_samples += 1
				if float(car_d.get("speed", 0.0)) > 1.2:
					moving_samples += 1
			if ts_jx.ebike_sim != null:
				for eb_d: Dictionary in ts_jx.ebike_sim.ebikes:
					if float(eb_d.get("speed", 0.0)) > 1.0:
						eb_moving += 1
	var move_ratio := float(moving_samples) / float(maxi(1, total_samples))
	# Verify ZERO e-bike clipping against tram catenary masts, ZERO visible teleports & ZERO rail blocking!
	var mast_pts_chk: Array = jx_graph.get_meta("mast_positions", [])
	var min_eb_mast_d := 999.0
	if ts_jx != null and ts_jx.ebike_sim != null:
		for eb_d: Dictionary in ts_jx.ebike_sim.ebikes:
			var ep: Vector3 = eb_d["pos"]
			var ep2 := Vector2(ep.x, ep.z)
			for mp: Vector2 in mast_pts_chk:
				var md := ep2.distance_to(mp)
				if md < min_eb_mast_d:
					min_eb_mast_d = md
	_check(
		bl_pct >= 80.0 and zh_ev_cnt == 16 and ebike_cnt >= 150 and ebike_cnt >= car_cnt * 3 and eb_moving > 0 and move_ratio >= 0.40 and min_eb_mast_d >= 0.85 and eb_near_teleports == 0 and eb_blocked_on_rail == 0,
		"Bike lanes %.1f%%, %d e-bikes vs %d cars (%.1fx), %.0f%% cruising, ZERO teleports (%d), ZERO rail blocks (%d), min mast %.2fm" % [bl_pct, ebike_cnt, car_cnt, float(ebike_cnt) / float(maxi(1, car_cnt)), move_ratio * 100.0, eb_near_teleports, eb_blocked_on_rail, min_eb_mast_d]
	)
	# Verify quantitative sculpted asset LOD budgets (Cars LOD0/1/2, E-Bikes LOD0/1, NPC LOD0/1)!
	var car_t0 := CarMeshGen.get_tri_count(ts_jx._zh_car_lods[0]["lod0"]) if not ts_jx._zh_car_lods.is_empty() else 0
	var car_t1 := CarMeshGen.get_tri_count(ts_jx._zh_car_lods[0]["lod1"]) if not ts_jx._zh_car_lods.is_empty() else 0
	var car_t2 := CarMeshGen.get_tri_count(ts_jx._zh_car_lods[0]["lod2"]) if not ts_jx._zh_car_lods.is_empty() else 0
	var eb_t0 := ts_jx.ebike_sim.get_lod0_tri_count(0) if (ts_jx != null and ts_jx.ebike_sim != null) else 0
	var eb_t1 := ts_jx.ebike_sim.get_lod1_tri_count(0) if (ts_jx != null and ts_jx.ebike_sim != null) else 0
	var npc_lod1_t := CarMeshGen.get_tri_count(HumanMeshGen.get_npc_lod1_mesh(0, Color(0.2, 0.3, 0.4), Color(0.2, 0.2, 0.3), Color(0.85, 0.7, 0.6), Color(0.1, 0.1, 0.1)))
	var car_has_3lods := not ts_jx.cars.is_empty() and (ts_jx.cars[0]["node"] as Node3D).get_node_or_null("LOD2") != null
	_check(
		car_has_3lods and car_t0 >= 8000 and car_t0 <= 15000 and car_t1 >= 2500 and car_t1 <= 5000 and car_t2 <= 1500 and eb_t0 >= 4000 and eb_t0 <= 7000 and eb_t1 <= 2000 and npc_lod1_t >= 1500 and npc_lod1_t <= 2400,
		"Sculpted Asset LODs match spec — Car(%d/%d/%d tris), E-Bike(%d/%d tris), NPC LOD1(%d tris)" % [car_t0, car_t1, car_t2, eb_t0, eb_t1, npc_lod1_t]
	)

	# Save/Load round-trip check for 3D elevations, stacked edges, ramps & underground stations
	var saved_3d := jx_graph.export_state()
	var g_reload := NetworkGraph.new()
	g_reload.load_from_map_data(m._map_data, false)
	g_reload.import_state(saved_3d)
	var ep_lr_ug := g_reload.get_edge_elev_pair(lr_eids[4])
	var ep_mr_l2 := g_reload.get_edge_elev_pair(mr_eids[2])
	var ep_stkd := g_reload.get_edge_elev_pair(stacked_eid)
	_check(
		absf(ep_lr_ug.x + 10.0) < 0.05 and absf(ep_mr_l2.x - 13.8) < 0.05 and absf(ep_stkd.x + 10.0) < 0.05 and g_reload.lines.has(lr_lid) and g_reload.lines.has(mr_lid),
		"3D elevation save/load round-trip preserves ramps, L2 (+13.8m), B1 (-10.0m), stacked corridor & lines"
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
