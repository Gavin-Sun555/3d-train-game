extends Node3D

const BED_STYLE_NAMES := [
	"独立工字草皮",
	"柏油槽型嵌轨",
	"齐平绿茵草皮",
	"花岗岩专用道",
	"碎石工字枕木",
	"高架单轨梁 (单轨系统)",
]

const MAP_ORDER: Array[String] = ["grid", "seattle"]

const MAP_PRESETS := {
	"grid": {
		"key": "grid",
		"index": "01",
		"title": "网格新城",
		"subtitle": "9×9 棋盘街区 · 跨河绿带 · 中央广场",
		"desc": "规整开阔的 1km² 棋盘街网与滨河绿廊，适合从零规划草皮工字轨、柏油嵌轨与多线换乘。",
		"data_path": "res://data/grid_city.json",
		"default_target": Vector3(0.0, 0.0, 0.0),
		"default_height": 560.0,
	},
	"seattle": {
		"key": "seattle",
		"index": "02",
		"title": "西雅图 · 中心城区",
		"subtitle": "Pike · Westlake · 亚马逊球体 · 联合湖",
		"desc": "基于真实 OSM 街区构建的西雅图核心城景、高架单轨与湖岸建筑群，沉浸式多视角驾驶电车。",
		"data_path": "res://data/seattle_expanded.json",
		"default_target": Vector3(0.0, 0.0, 120.0),
		"default_height": 600.0,
	},
}

enum GameMode {
	BUILD = 0,
	PLAN = 1,
	RUN = 2,
}

enum BuildTool {
	TRACK_SINGLE = 0,
	TRACK_PATH = 1,
	CROSSOVER = 2,
	STATION = 3,
	DEMOLISH = 4,
}

enum CamMode {
	CAB = 0,
	CHASE = 1,
	INTERIOR = 2,
	DOOR_ACTION = 3,
	BIRD = 4,
}

var _cjk_font: Font
var _building_mat: ShaderMaterial
var _road_mat: ShaderMaterial
var _sidewalk_mat: ShaderMaterial
var _grass_track_mat: ShaderMaterial
var _spheres_mat: ShaderMaterial
var _night_mats: Array[ShaderMaterial] = []
var _globe_mat: StandardMaterial3D

var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _camera: Camera3D
var _sound: SoundSynth

var _city_root: Node3D
var _track_root: Node3D
var _overlay_root: Node3D
var _preview_mi: MeshInstance3D
var _route_preview_mi: MeshInstance3D

var _graph: NetworkGraph
var _pax_sim: PassengerSim
var _transit_sim: TransitSim
var _traffic_sim: TrafficSim
var _fx_root: Node3D
var _fx_particles: Array[Dictionary] = []

var _current_map_key := "seattle"
var _selected_home_map := "seattle"
var _in_home_menu := true
var _is_demo_readonly := false
var _started_from_demo := false
var _game_over := false
var _accident_focus := Vector3.ZERO
var _accident_orbit_yaw := 0.0
var _hud_refresh_timer := 0.0
var _fps_ema := 60.0
var _home_orbit_angle := 0.35
var _reset_confirm_timer := 0.0
var _autosave_timer := 0.0

var _map_data: Dictionary = {}
var _tram_models: Array = []
var _city_lights: Array[OmniLight3D] = []
var _track_lights: Array[OmniLight3D] = []
var _station_views: Dictionary = {}
var _pan_limit_x := 580.0
var _pan_limit_z := 1050.0

# Monorail background landmark animation
var _monorail_curve: Curve3D = null
var _monorail_cars: Array = []
var _monorail_cars_hidden := false
var _monorail_s := 55.0
var _monorail_dir := 1.0
var _monorail_pause := 0.0

# Game mode & Build/Plan state
var _game_mode: int = GameMode.RUN
var _build_tool: int = BuildTool.TRACK_SINGLE
var _build_bed_style: int = TrackBuilder.BedStyle.GRASS_VIGNOLE
var _build_track_mode: int = NetworkGraph.TrackMode.SINGLE
var _build_crossover_type: int = NetworkGraph.CrossoverType.SINGLE
var _build_station_side := 1
var _build_station_kind: int = NetworkGraph.StationKind.SIDE_SINGLE
var _editing_station_id := -1
var _path_start_node := -1
var _track_mode_btns: Array[Button] = []
var _crossover_type_btns: Array[Button] = []
var _station_kind_btns: Array[Button] = []
var _edit_station_name: LineEdit

# Plan mode state
var _draft_station_ids: Array[int] = []
var _plan_era_filter := "all"
var _plan_model_idx := 0
var _plan_fleet_count := 3
var _plan_sections := 2

# Time of day (continuous 0..24h)
var _time_hours := 13.5
var _night_factor := 0.0
var _updating_slider := false

# Camera state
var _cam_mode: int = CamMode.CHASE
var _orbit_yaw := deg_to_rad(-18.0)
var _orbit_pitch := deg_to_rad(16.0)
var _orbit_dist := 17.5
var _cab_yaw := 0.0
var _cab_pitch := deg_to_rad(-8.5)
var _cab_fov := 66.0
var _cab_dragging_lever := false
var _cab_lever_drag_start_y := 0.0
var _cab_lever_start_notch := TransitSim.NOTCH_NEUTRAL
var _cab_hover_ctrl := ""
var _lbl_cab_tip: Label
var _active_plan_slot_idx := 0
var _btn_quick_save_run: Button
var _audio_modal: Control
var _stats_modal: Control
var _stats_summary_lbl: Label
var _stats_lines_vbox: VBoxContainer
var _stats_stations_vbox: VBoxContainer
var _stats_refresh_accum := 0.0
var _last_ann_approach_sid := -1
var _last_ann_door_open := false
var _door_cam_yaw := 0.0
var _door_cam_pitch := 0.0
var _plan_target := Vector3(0.0, 0.0, 120.0)
var _plan_height := 560.0
var _snap_camera_next := true

# Mouse / Trackpad drag & click state
var _rmb_dragging := false
var _lmb_down := false
var _lmb_drag_active := false
var _lmb_down_pos := Vector2.ZERO
var _last_mouse_pos := Vector2.ZERO

var _hold_up_timer := 0.0
var _hold_down_timer := 0.0

# UI Containers & Labels
var _hud_layer_ctrl: Control
var _nav_bar: PanelContainer
var _btn_mode_build: Button
var _btn_mode_plan: Button
var _btn_mode_run: Button
var _lbl_clock: Label
var _lbl_fps: Label
var _slider_time: HSlider
var _lbl_toast: Label
var _toast_timer := 0.0

var _build_panel: PanelContainer
var _lbl_build_hint: Label
var _bed_btns: Array[Button] = []
var _tool_btns: Array[Button] = []

var _plan_panel: PanelContainer
var _lbl_draft_stops: Label
var _lbl_model_card: Label
var _lbl_fleet_cfg: Label
var _lines_list_vbox: VBoxContainer

var _run_top_panel: PanelContainer
var _cam_panel: PanelContainer
var _drv_panel: PanelContainer
var _lbl_net_stats: Label
var _lbl_tram_info: Label
var _lbl_station_next: Label
var _lbl_hazard_hint: Label
var _btn_pax_rate: Button
var _lbl_speed: Label
var _lbl_speed_limit: Label
var _lbl_notch: Label
var _lbl_drv_status: Label
var _btn_doors: Button
var _btn_drive_mode: Button
var _notch_bars: Array[ColorRect] = []

var _gameover_modal: Control
var _lbl_gameover_title: Label
var _lbl_gameover_detail: Label

# Home Screen & Multi-Slot Save Manager UI
var _home_overlay: Control
var _home_card_panels: Dictionary = {}
var _home_card_badges: Dictionary = {}
var _btn_home_primary: Button
var _btn_home_demo: Button
var _btn_home_slots: Button
var _btn_home_reset: Button

var _slot_modal: Control
var _slot_modal_map_key := "seattle"
var _slot_tab_mode := 0 # 0 = Manual Blueprint (10, each with up to 3 linked run saves), 1 = Auto-saves (5)
var _lbl_slot_title: Label
var _btn_tab_manual: Button
var _btn_tab_auto: Button
var _slot_name_row: HBoxContainer
var _edit_slot_name: LineEdit
var _slot_list_vbox: VBoxContainer

# Automated verification screenshot tour
var _shot_dir := ""
var _shot_step := 0
var _shot_frames_wait := 0


func _ready() -> void:
	_setup_font()
	_load_tram_catalogue()
	_setup_environment()
	_setup_scene_nodes()
	_build_ui()

	# Load default backdrop city on startup and show Home Screen
	_load_map_world("seattle", true, false)
	_set_time_hours(_time_hours)
	_enter_home_screen()
	_parse_cli_args()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _in_home_menu and not _is_demo_readonly and not _game_over:
			_save_current_progress(false)


func _setup_font() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Heiti SC",
		"STHeiti",
		"Songti SC",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Arial Unicode MS",
	])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_cjk_font = sf


func _load_tram_catalogue() -> void:
	var raw_models := _read_json("res://data/tram_models.json")
	_tram_models = raw_models.get("models", [])
	_graph = NetworkGraph.new()


func _load_map_world(map_key: String, use_starter: bool, seed_pax: bool) -> void:
	var preset: Dictionary = MAP_PRESETS.get(map_key, MAP_PRESETS["seattle"])
	_current_map_key = str(preset["key"])
	_map_data = _read_json(str(preset["data_path"]))

	var bounds: Array = _map_data.get("bounds", [-520.0, -520.0, 520.0, 520.0])
	_pan_limit_x = maxf(absf(float(bounds[0])), absf(float(bounds[2]))) + 80.0
	_pan_limit_z = maxf(absf(float(bounds[1])), absf(float(bounds[3]))) + 80.0

	_plan_target = preset["default_target"] as Vector3
	_plan_height = float(preset["default_height"])
	_snap_camera_next = true

	_graph.load_from_map_data(_map_data, use_starter)
	_build_city_world()
	_rebuild_tracks_and_operations(seed_pax)


func _setup_environment() -> void:
	_world_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_curve = 0.12
	sky_mat.ground_curve = 0.08
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.76, 0.77, 0.79)
	env.ambient_light_energy = 0.70
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.08
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.45
	env.ssil_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.03

	_world_env.environment = env
	add_child(_world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	# 4 cascades + split blending: much finer texels near the camera, so shadow edges don't swim
	# while the camera travels with the tram; normal bias stops large flat surfaces self-shadowing.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_split_1 = 0.06
	_sun.directional_shadow_split_2 = 0.18
	_sun.directional_shadow_split_3 = 0.45
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_max_distance = 300.0
	_sun.shadow_bias = 0.06
	_sun.shadow_normal_bias = 1.6
	_sun.shadow_blur = 0.9
	add_child(_sun)

	_building_mat = ShaderMaterial.new()
	_building_mat.shader = load("res://shaders/building.gdshader") as Shader

	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://shaders/road_asphalt.gdshader") as Shader

	_sidewalk_mat = ShaderMaterial.new()
	_sidewalk_mat.shader = load("res://shaders/sidewalk.gdshader") as Shader

	_grass_track_mat = ShaderMaterial.new()
	_grass_track_mat.shader = load("res://shaders/grass_track.gdshader") as Shader

	_globe_mat = StandardMaterial3D.new()
	_globe_mat.albedo_color = Color(0.95, 0.93, 0.88)
	_globe_mat.roughness = 0.35
	_globe_mat.emission_enabled = true
	_globe_mat.emission = Color(1.0, 0.85, 0.56)
	_globe_mat.emission_energy_multiplier = 0.0


func _setup_scene_nodes() -> void:
	_city_root = Node3D.new()
	_city_root.name = "CityWorld"
	add_child(_city_root)

	_track_root = Node3D.new()
	_track_root.name = "PlayerTrackAndStations"
	add_child(_track_root)

	_overlay_root = Node3D.new()
	_overlay_root.name = "PlanningOverlays"
	add_child(_overlay_root)

	_preview_mi = MeshInstance3D.new()
	_preview_mi.name = "HoverPreview"
	_overlay_root.add_child(_preview_mi)

	_route_preview_mi = MeshInstance3D.new()
	_route_preview_mi.name = "DraftRoutePreview"
	_overlay_root.add_child(_route_preview_mi)

	_pax_sim = PassengerSim.new()
	_pax_sim.name = "PassengerSim"
	add_child(_pax_sim)

	_transit_sim = TransitSim.new()
	_transit_sim.name = "TransitSim"
	add_child(_transit_sim)

	_traffic_sim = TrafficSim.new()
	_traffic_sim.name = "TrafficSim"
	add_child(_traffic_sim)

	_fx_root = Node3D.new()
	_fx_root.name = "AccidentFX"
	add_child(_fx_root)

	_sound = SoundSynth.new()
	add_child(_sound)

	_camera = Camera3D.new()
	_camera.fov = 56.0
	_camera.near = 0.12
	_camera.far = 2800.0
	add_child(_camera)
	_camera.make_current()


func _build_city_world() -> void:
	for c in _city_root.get_children():
		_city_root.remove_child(c)
		c.queue_free()
	var lm_info := CityBuilder.build_city(
		_city_root,
		_map_data,
		_building_mat,
		_road_mat,
		_sidewalk_mat,
		_globe_mat
	)
	_monorail_curve = lm_info.get("monorail_curve")
	_monorail_cars = lm_info.get("monorail_cars", [])
	_spheres_mat = lm_info.get("spheres_mat")
	_night_mats.clear()
	for nm in lm_info.get("night_mats", []):
		_night_mats.append(nm)
	_city_lights.clear()
	for l in lm_info.get("lights", []):
		if l is OmniLight3D:
			_city_lights.append(l)


func _rebuild_tracks_and_operations(seed_pax: bool = false) -> void:
	# Seattle: offer the real Seattle Center Monorail as a playable line once per save (5th Ave & Stewart
	# -> 5th Ave N & Harrison). Kept off any street the player already built on.
	if _current_map_key == "seattle" and not _graph.monorail_seeded:
		_graph.monorail_seeded = true
		var mono_lid := _graph.seed_seattle_monorail(Vector2(-7.57, 583.6), Vector2(-737.9, -424.2), "seattle-alweg-red")
		if mono_lid > 0:
			_show_toast("🚝 西雅图中心单轨已作为一条线路加入，可在线路列表中选择并驾驶")
	for c in _track_root.get_children():
		c.queue_free()

	var built := TrackBuilder.build_network_tracks_and_stations(
		_track_root,
		_graph,
		_cjk_font,
		_grass_track_mat
	)
	_station_views = built["stations"]
	_sync_landmark_monorail()
	CityBuilder.apply_track_clearance(_city_root, _graph.get_meta("track_clear_idx", {}), _graph.get_meta("station_bays", []))
	CityBuilder.apply_station_bays(_city_root, _graph.get_meta("station_bays", []))
	_track_lights.clear()
	for l in built["lights"]:
		_track_lights.append(l)

	_pax_sim.reset_for_stations(_station_views)
	if seed_pax:
		_pax_sim.seed_initial_passengers(_graph, 22)

	_clear_accident_fx()
	_transit_sim.rebuild_fleet(_graph, _tram_models, _night_factor)
	if _traffic_sim != null:
		_traffic_sim.rebuild_traffic(_graph, _get_traffic_focus_pos())
	_apply_lighting_from_clock()
	_refresh_lines_list_ui()


# Once the player network has a real monorail guideway, the decorative (non-playable) landmark monorail is retired
func _sync_landmark_monorail() -> void:
	var has_mono := false
	for eid: int in _graph.built_tracks.keys():
		if TrackBuilder.is_monorail_style(int(_graph.built_tracks[eid])):
			has_mono = true
			break
	var stack: Array = [_city_root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for ch in nd.get_children():
			if str(ch.name) in ["SeattleCenterMonorail", "SeattleCenterMonorailTerminal"] and ch is Node3D:
				(ch as Node3D).visible = not has_mono
			elif ch.get_child_count() > 0 and ch.get_child_count() < 400:
				stack.append(ch)
	if has_mono:
		_monorail_cars_hidden = true
		for car in _monorail_cars:
			if is_instance_valid(car):
				(car as Node3D).visible = false
	else:
		_monorail_cars_hidden = false
		for car in _monorail_cars:
			if is_instance_valid(car):
				(car as Node3D).visible = true


func _switch_line(delta_i: int) -> void:
	var before := int(_transit_sim.get_active_tram().get("line_id", -1))
	_transit_sim.cycle_active_line(delta_i)
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	if int(tr["line_id"]) == before:
		_show_toast("当前只有一条线路在运营")
	else:
		_show_toast("已切换到线路：%s（%d 列车）" % [str(tr["line_name"]), _transit_sim.line_tram_indices(int(tr["line_id"])).size()])


func _get_traffic_focus_pos() -> Vector3:
	if _transit_sim != null and not _transit_sim.trams.is_empty():
		var tr := _transit_sim.get_active_tram()
		var secs: Array = tr["tram_info"]["sections"]
		if not secs.is_empty() and is_instance_valid(secs[0]):
			return (secs[0] as Node3D).global_position
	return _plan_target


# --- Home Screen & Session Entry Logic ---
func _enter_home_screen() -> void:
	if not _in_home_menu and not _is_demo_readonly and not _game_over:
		_save_current_progress(false)
	_in_home_menu = true
	_game_over = false
	if _gameover_modal != null:
		_gameover_modal.visible = false
	_slot_modal.visible = false
	if _audio_modal != null:
		_audio_modal.visible = false
	if _stats_modal != null:
		_stats_modal.visible = false
	_reset_confirm_timer = 0.0
	_sound.set_menu_silenced(true)
	_overlay_root.visible = false
	_hud_layer_ctrl.visible = false
	_home_overlay.visible = true
	_selected_home_map = _current_map_key
	_refresh_home_screen_ui()


func _select_home_map_card(map_key: String) -> void:
	_selected_home_map = map_key
	_reset_confirm_timer = 0.0
	if _current_map_key != map_key:
		_load_map_world(map_key, true, true)
	_refresh_home_screen_ui()


func _start_map_continue_or_new() -> void:
	var mkey := _selected_home_map
	var latest_run := SaveManager.get_latest_run_slot(mkey)
	var saved := SaveManager.load_current(mkey)
	_is_demo_readonly = false
	_started_from_demo = false
	_game_over = false
	_gameover_modal.visible = false
	_in_home_menu = false
	_home_overlay.visible = false
	_hud_layer_ctrl.visible = true
	_nav_bar.visible = true

	if bool(latest_run.get("exists", false)):
		var bp_data: Dictionary = latest_run["blueprint_data"]
		var run_data: Dictionary = latest_run["run_data"]
		_active_plan_slot_idx = int(latest_run["slot_idx"])
		_apply_loaded_save_state(mkey, bp_data)
		_set_game_mode(GameMode.RUN)
		_pax_sim.set_spawn_level(int(run_data.get("pax_spawn_level", _pax_sim.spawn_level)))
		_pax_sim.total_delivered = int(run_data.get("total_delivered", 0))
		if _btn_pax_rate != null:
			_btn_pax_rate.text = "客流: %s (P)" % PassengerSim.SPAWN_LEVEL_NAMES[_pax_sim.spawn_level]
		_set_time_hours(float(run_data.get("time_hours", _time_hours)))
		_transit_sim.import_run_state(run_data.get("transit", {}), _graph)
		_show_toast("✓ 已继续驾驶【%s】运行存档（槽位 %02d · 已送达 %d 人）" % [
			str(MAP_PRESETS[mkey]["title"]),
			_active_plan_slot_idx + 1,
			_pax_sim.total_delivered,
		])
	elif not saved.is_empty():
		_apply_loaded_save_state(mkey, saved)
		var start_mode := GameMode.RUN if not _graph.lines.is_empty() else GameMode.BUILD
		_set_game_mode(start_mode)
		_show_toast("✓ 已继续【%s】上次进度" % str(MAP_PRESETS[mkey]["title"]))
	else:
		_load_map_world(mkey, false, false)
		_pax_sim.total_delivered = 0
		_set_game_mode(GameMode.BUILD)
		_save_current_progress(false)
		_show_toast("已进入【%s】空白沙盒 · 左键铺设轨道，按下触摸板左右滑动平移地图" % str(MAP_PRESETS[mkey]["title"]))


func _start_map_demo_network() -> void:
	var mkey := _selected_home_map
	var had_existing := bool(SaveManager.get_current_summary(mkey)["exists"])
	_is_demo_readonly = had_existing
	_started_from_demo = true
	_game_over = false
	_gameover_modal.visible = false
	_in_home_menu = false
	_home_overlay.visible = false
	_hud_layer_ctrl.visible = true
	_nav_bar.visible = true

	_load_map_world(mkey, true, true)
	_pax_sim.total_delivered = 0
	_set_game_mode(GameMode.RUN)
	_set_cam_mode(CamMode.CHASE)
	_show_toast("✓ 已进入【%s】示例线网！注意弯道/道岔限速与路口小车（超速翻车或撞车将结束本局）" % str(MAP_PRESETS[mkey]["title"]))


func _handle_home_reset_button() -> void:
	var mkey := _selected_home_map
	if _reset_confirm_timer <= 0.0:
		_reset_confirm_timer = 3.6
		_btn_home_reset.text = "确认清空重开？"
		return

	_reset_confirm_timer = 0.0
	var prev := SaveManager.load_current(mkey)
	if not prev.is_empty():
		SaveManager.push_autosave(mkey, "重开前自动备份", prev)
	SaveManager.delete_current(mkey)

	_is_demo_readonly = false
	_started_from_demo = false
	_game_over = false
	_gameover_modal.visible = false
	_in_home_menu = false
	_home_overlay.visible = false
	_hud_layer_ctrl.visible = true
	_nav_bar.visible = true
	_load_map_world(mkey, false, false)
	_pax_sim.total_delivered = 0
	_set_game_mode(GameMode.BUILD)
	_save_current_progress(false)
	_show_toast("已清空并重新开始【%s】" % str(MAP_PRESETS[mkey]["title"]))


func _apply_loaded_save_state(map_key: String, save_data: Dictionary) -> void:
	if _current_map_key != map_key or _map_data.is_empty():
		_load_map_world(map_key, false, false)
	var net: Dictionary = save_data.get("network", {})
	_graph.import_state(net)
	_pax_sim.set_spawn_level(int(save_data.get("pax_spawn_level", 3)))
	_pax_sim.total_delivered = int(save_data.get("total_delivered", 0))
	if _btn_pax_rate != null:
		_btn_pax_rate.text = "客流: %s (P)" % PassengerSim.SPAWN_LEVEL_NAMES[_pax_sim.spawn_level]
	_set_time_hours(float(save_data.get("time_hours", 13.5)))
	_rebuild_tracks_and_operations(not _graph.lines.is_empty())


func _build_current_save_payload(slot_name: String) -> Dictionary:
	return SaveManager.build_payload(
		_current_map_key,
		slot_name,
		_graph,
		_pax_sim.spawn_level,
		_time_hours,
		_pax_sim.total_delivered
	)


func _save_current_progress(show_msg: bool = false) -> void:
	var payload := _build_current_save_payload("当前进度")
	SaveManager.save_current(_current_map_key, payload)
	if show_msg:
		_show_toast("✓ 已自动保存当前进度")


func _open_slot_modal(map_key: String, show_auto_tab: bool = false, tab_mode: int = -1) -> void:
	_slot_modal_map_key = map_key
	if tab_mode >= 0:
		_slot_tab_mode = clampi(tab_mode, 0, 1)
	else:
		_slot_tab_mode = 1 if show_auto_tab else 0
	_slot_modal.visible = true
	_refresh_slot_modal_ui()


func _refresh_home_screen_ui() -> void:
	if _home_overlay == null:
		return
	for mkey: String in MAP_ORDER:
		var summary := SaveManager.get_current_summary(mkey)
		var badge_lbl: Label = _home_card_badges.get(mkey)
		if badge_lbl != null:
			if bool(summary["exists"]):
				badge_lbl.text = "● 已有进度：轨道 %d 段 · 车站 %d 座 · 线路 %d 条\n   上次保存：%s" % [
					int(summary["tracks"]),
					int(summary["stations"]),
					int(summary["lines"]),
					str(summary["saved_at"]),
				]
				badge_lbl.add_theme_color_override("font_color", Color(0.46, 0.92, 0.70))
			else:
				badge_lbl.text = "○ 暂无本地存档\n   可点击【开始建设】从零规划，或进入【示例线网】试驾"
				badge_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))

		var card_pc: PanelContainer = _home_card_panels.get(mkey)
		if card_pc != null:
			var is_sel := (mkey == _selected_home_map)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.11, 0.17, 0.24, 0.95) if is_sel else Color(0.07, 0.09, 0.13, 0.88)
			sb.corner_radius_top_left = 10; sb.corner_radius_top_right = 10
			sb.corner_radius_bottom_left = 10; sb.corner_radius_bottom_right = 10
			sb.border_width_left = 2 if is_sel else 1
			sb.border_width_top = 2 if is_sel else 1
			sb.border_width_right = 2 if is_sel else 1
			sb.border_width_bottom = 2 if is_sel else 1
			sb.border_color = Color(0.36, 0.86, 0.66, 0.95) if is_sel else Color(0.30, 0.35, 0.42, 0.55)
			sb.content_margin_left = 16; sb.content_margin_right = 16
			sb.content_margin_top = 14; sb.content_margin_bottom = 14
			card_pc.add_theme_stylebox_override("panel", sb)

	var sel_sum := SaveManager.get_current_summary(_selected_home_map)
	var latest_run := SaveManager.get_latest_run_slot(_selected_home_map)
	var has_run := bool(latest_run.get("exists", false))
	var has_cur := bool(sel_sum["exists"]) or has_run
	var map_title := str(MAP_PRESETS[_selected_home_map]["title"])
	if has_run:
		_btn_home_primary.text = "▶ 继续驾驶（%s · 运行档）" % map_title
	elif has_cur:
		_btn_home_primary.text = "▶ 继续游戏（%s）" % map_title
	else:
		_btn_home_primary.text = "▶ 开始建设（%s）" % map_title
	_btn_home_reset.visible = has_cur
	if _reset_confirm_timer <= 0.0:
		_btn_home_reset.text = "重新开始"


func _refresh_slot_modal_ui() -> void:
	if _slot_modal == null or not _slot_modal.visible:
		return
	var map_title := str(MAP_PRESETS[_slot_modal_map_key]["title"])
	_lbl_slot_title.text = "存档管理 · %s" % map_title
	_highlight_active_btn(_btn_tab_manual, _slot_tab_mode == 0)
	_highlight_active_btn(_btn_tab_auto, _slot_tab_mode == 1)

	var is_auto_tab := (_slot_tab_mode == 1)
	var can_save_here := (not _in_home_menu) and (_slot_modal_map_key == _current_map_key) and (not is_auto_tab)
	_slot_name_row.visible = can_save_here

	for c in _slot_list_vbox.get_children():
		c.queue_free()

	var slots := SaveManager.list_slots(_slot_modal_map_key, is_auto_tab)
	for s_info: Dictionary in slots:
		var idx := int(s_info["index"])
		var exists := bool(s_info["exists"])
		var row_pc := _make_panel(Color(0.11, 0.14, 0.19, 0.92) if exists else Color(0.08, 0.10, 0.13, 0.78))
		_slot_list_vbox.add_child(row_pc)

		var row_vbox := VBoxContainer.new()
		row_vbox.add_theme_constant_override("separation", 5)
		row_pc.add_child(row_vbox)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		row_vbox.add_child(hbox)

		var badge := Label.new()
		badge.text = "[%02d]" % (idx + 1)
		badge.add_theme_color_override("font_color", Color(0.52, 0.88, 0.72) if exists else Color(0.55, 0.60, 0.66))
		hbox.add_child(badge)

		var info_lbl := Label.new()
		info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if exists:
			info_lbl.text = "【建设规划】%s  |  轨道%d · 站%d · 线%d  (%s)" % [
				str(s_info["name"]),
				int(s_info["tracks"]),
				int(s_info["stations"]),
				int(s_info["lines"]),
				str(s_info["saved_at"]),
			]
			info_lbl.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98))
		else:
			info_lbl.text = str(s_info["name"])
			info_lbl.add_theme_color_override("font_color", Color(0.58, 0.62, 0.68))
		hbox.add_child(info_lbl)

		if can_save_here:
			var idx_save := idx
			var save_btn := _make_btn("覆盖规划" if exists else "存建设规划", func():
				var custom_nm := _edit_slot_name.text.strip_edges()
				var payload := _build_current_save_payload(custom_nm)
				if SaveManager.save_manual_slot(_current_map_key, idx_save, custom_nm, payload):
					_active_plan_slot_idx = idx_save
					_is_demo_readonly = false
					SaveManager.save_current(_current_map_key, payload)
					_edit_slot_name.text = ""
					_refresh_slot_modal_ui()
					_show_toast("✓ 已保存建设规划至槽位 %02d" % (idx_save + 1))
			)
			hbox.add_child(save_btn)

		if exists:
			var idx_load := idx
			var is_auto_load := is_auto_tab
			var mkey_load := _slot_modal_map_key
			hbox.add_child(_make_btn("读取规划", func():
				if not _in_home_menu and not _is_demo_readonly:
					SaveManager.push_autosave(_current_map_key, "读档前自动备份", _build_current_save_payload("读档前备份"))
				var loaded := SaveManager.load_slot(mkey_load, is_auto_load, idx_load)
				if not loaded.is_empty():
					if not is_auto_load:
						_active_plan_slot_idx = idx_load
					_is_demo_readonly = false
					_in_home_menu = false
					_slot_modal.visible = false
					_home_overlay.visible = false
					_hud_layer_ctrl.visible = true
					_apply_loaded_save_state(mkey_load, loaded)
					SaveManager.save_current(mkey_load, loaded)
					_set_game_mode(GameMode.RUN if not _graph.lines.is_empty() else GameMode.BUILD)
					_show_toast("✓ 已读取建设规划：%s" % str(loaded.get("name", "")))
			))

			var idx_del := idx
			var is_auto_del := is_auto_tab
			var mkey_del := _slot_modal_map_key
			hbox.add_child(_make_btn("删除" if is_auto_del else "删规划+3运行档", func():
				SaveManager.delete_slot(mkey_del, is_auto_del, idx_del)
				_refresh_slot_modal_ui()
				_show_toast("已删除槽位 %02d（关联运行存档已同步删除）" % (idx_del + 1))
			))

			# Embedded linked driving run saves (up to 3 per manual blueprint save)
			if not is_auto_tab:
				var run_saves: Array = s_info.get("run_saves", [])
				for rs_var in run_saves:
					var rs: Dictionary = rs_var
					var si := int(rs.get("sub_idx", 0))
					var rexists := bool(rs.get("exists", false))
					var sub_row := HBoxContainer.new()
					sub_row.add_theme_constant_override("separation", 6)
					row_vbox.add_child(sub_row)

					var indent := Label.new()
					indent.text = "   ↳ 运行档 %d：" % (si + 1)
					indent.add_theme_font_size_override("font_size", 12)
					indent.add_theme_color_override("font_color", Color(0.46, 0.86, 0.96) if rexists else Color(0.50, 0.56, 0.62))
					sub_row.add_child(indent)

					var r_lbl := Label.new()
					r_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					r_lbl.add_theme_font_size_override("font_size", 12)
					if rexists:
						r_lbl.text = "累计送达 %d 人  (%s)" % [int(rs.get("delivered", 0)), str(rs.get("saved_at", ""))]
						r_lbl.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0))
					else:
						r_lbl.text = "空（可存当前驾驶进度）"
						r_lbl.add_theme_color_override("font_color", Color(0.52, 0.56, 0.62))
					sub_row.add_child(r_lbl)

					if can_save_here and _game_mode == GameMode.RUN and not _transit_sim.trams.is_empty():
						var p_s := idx
						var s_s := si
						sub_row.add_child(_make_btn("覆盖运行" if rexists else "存运行", func():
							_save_run_progress_to_slot(p_s, s_s)
							_refresh_slot_modal_ui()
						))

					if rexists:
						var p_l := idx
						var s_l := si
						var mkey_rl := _slot_modal_map_key
						sub_row.add_child(_make_btn("继续驾驶", func():
							var bp := SaveManager.load_slot(mkey_rl, false, p_l)
							var rd := SaveManager.load_run_slot(mkey_rl, p_l, s_l)
							if not bp.is_empty() and not rd.is_empty():
								_active_plan_slot_idx = p_l
								_is_demo_readonly = false
								_in_home_menu = false
								_slot_modal.visible = false
								_home_overlay.visible = false
								_hud_layer_ctrl.visible = true
								_nav_bar.visible = true
								_apply_loaded_save_state(mkey_rl, bp)
								_set_game_mode(GameMode.RUN)
								_set_time_hours(float(rd.get("time_hours", _time_hours)))
								_pax_sim.set_spawn_level(int(rd.get("pax_spawn_level", _pax_sim.spawn_level)))
								_pax_sim.total_delivered = int(rd.get("total_delivered", 0))
								if _btn_pax_rate != null:
									_btn_pax_rate.text = "客流: %s (P)" % PassengerSim.SPAWN_LEVEL_NAMES[_pax_sim.spawn_level]
								_transit_sim.import_run_state(rd.get("transit", {}), _graph)
								_show_toast("✓ 已继续驾驶规划 %02d · 运行档 %d（送达 %d 人）" % [p_l + 1, s_l + 1, _pax_sim.total_delivered])
						))

						var p_d := idx
						var s_d := si
						var mkey_rd := _slot_modal_map_key
						sub_row.add_child(_make_btn("删除", func():
							SaveManager.delete_run_slot(mkey_rd, p_d, s_d)
							_refresh_slot_modal_ui()
							_show_toast("已删除规划 %02d · 运行档 %d" % [p_d + 1, s_d + 1])
						))


func _set_game_mode(mode: int) -> void:
	var prev_mode := _game_mode
	_game_mode = mode
	_path_start_node = -1
	_preview_mi.mesh = null
	_last_ann_approach_sid = -1
	_last_ann_door_open = false
	if _btn_quick_save_run != null:
		_btn_quick_save_run.visible = (_game_mode == GameMode.RUN)
	_sound.set_menu_silenced(_in_home_menu or _game_mode != GameMode.RUN)

	if prev_mode != GameMode.RUN and _game_mode == GameMode.RUN:
		_draft_station_ids.clear()
		_route_preview_mi.mesh = null
		_transit_sim.rebuild_fleet(_graph, _tram_models, _night_factor)
		_pax_sim.reset_for_stations(_station_views)
		_pax_sim.seed_initial_passengers(_graph, 20)
		_traffic_sim.rebuild_traffic(_graph, _get_traffic_focus_pos())
		if _cam_mode == CamMode.BIRD and not _transit_sim.trams.is_empty():
			_set_cam_mode(CamMode.CHASE)

	if _game_mode in [GameMode.BUILD, GameMode.PLAN]:
		var active_tr := _transit_sim.get_active_tram()
		if prev_mode == GameMode.RUN and not active_tr.is_empty():
			var secs: Array = active_tr["tram_info"]["sections"]
			if not secs.is_empty():
				var p := (secs[0] as Node3D).global_position
				_plan_target = Vector3(p.x, 0.0, p.z)
		_camera.fov = 46.0
		_sun.directional_shadow_max_distance = 540.0
	else:
		_sun.directional_shadow_max_distance = 540.0 if _cam_mode == CamMode.BIRD else 290.0

	_overlay_root.visible = (not _in_home_menu) and (_game_mode != GameMode.RUN)
	_build_panel.visible = (_game_mode == GameMode.BUILD)
	_plan_panel.visible = (_game_mode == GameMode.PLAN)
	_run_top_panel.visible = (_game_mode == GameMode.RUN)
	_cam_panel.visible = (_game_mode == GameMode.RUN)
	_drv_panel.visible = (_game_mode == GameMode.RUN)

	_highlight_active_btn(_btn_mode_build, _game_mode == GameMode.BUILD)
	_highlight_active_btn(_btn_mode_plan, _game_mode == GameMode.PLAN)
	_highlight_active_btn(_btn_mode_run, _game_mode == GameMode.RUN)
	_refresh_plan_ui()


func _show_toast(msg: String) -> void:
	if _lbl_toast != null:
		_lbl_toast.text = msg
		_lbl_toast.visible = true
		_toast_timer = 3.4


func _set_time_hours(h: float) -> void:
	_time_hours = fposmod(h, 24.0)
	_apply_lighting_from_clock()
	if _slider_time != null and not _updating_slider:
		_updating_slider = true
		_slider_time.value = _time_hours
		_updating_slider = false


func _apply_lighting_from_clock() -> void:
	var env := _world_env.environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial

	var hour_angle := ((_time_hours - 13.0) / 12.0) * PI
	var elev_deg := cos(hour_angle) * 56.0
	var azim_deg := -110.0 + ((_time_hours - 6.0) / 14.0) * 155.0

	var day_fac := smoothstep(-4.0, 14.0, elev_deg)
	var dusk_fac := smoothstep(20.0, 1.0, elev_deg) * smoothstep(-6.0, 1.0, elev_deg)
	_night_factor = smoothstep(9.0, -5.0, elev_deg)

	sky_mat.sky_top_color = Color(0.025, 0.035, 0.065).lerp(Color(0.32, 0.52, 0.78), day_fac).lerp(Color(0.18, 0.26, 0.46), dusk_fac * 0.75)
	sky_mat.sky_horizon_color = Color(0.055, 0.075, 0.12).lerp(Color(0.76, 0.82, 0.89), day_fac).lerp(Color(0.94, 0.58, 0.36), dusk_fac * 0.85)
	# Below the horizon the sky continues as distant haze over Elliott Bay (no dark band past the far plane)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.lerp(Color(0.30, 0.40, 0.46), 0.25 * day_fac)
	sky_mat.ground_bottom_color = Color(0.03, 0.03, 0.04).lerp(Color(0.28, 0.28, 0.27), day_fac)

	if elev_deg > -2.5:
		_sun.rotation_degrees = Vector3(-maxf(elev_deg, 2.0), azim_deg, 0.0)
		_sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.66, 0.38), dusk_fac)
		_sun.light_energy = lerpf(0.08, 2.35, smoothstep(-2.5, 18.0, elev_deg))
	else:
		_sun.rotation_degrees = Vector3(-48.0, 125.0, 0.0)
		_sun.light_color = Color(0.68, 0.72, 0.82)
		_sun.light_energy = 0.24

	env.ambient_light_color = Color(0.20, 0.22, 0.26).lerp(Color(0.76, 0.77, 0.79), day_fac).lerp(Color(0.56, 0.49, 0.47), dusk_fac * 0.55)
	env.ambient_light_energy = lerpf(0.45, 0.70, day_fac)

	var sky_refl := Color(0.10, 0.12, 0.18).lerp(
		Color(0.62, 0.70, 0.78).lerp(Color(0.86, 0.64, 0.48), dusk_fac),
		day_fac
	)
	_building_mat.set_shader_parameter("night_factor", _night_factor)
	for nm in _night_mats:
		nm.set_shader_parameter("night_factor", _night_factor)
	_building_mat.set_shader_parameter("env_sky_tint", Vector3(sky_refl.r, sky_refl.g, sky_refl.b))
	if _spheres_mat != null:
		_spheres_mat.set_shader_parameter("night_factor", _night_factor)

	_globe_mat.emission_energy_multiplier = _night_factor * 2.8
	var lamp_e := _night_factor * 2.05
	var show_lamps := (lamp_e > 0.02)
	for cl in _city_lights:
		if is_instance_valid(cl):
			cl.visible = show_lamps
			cl.light_energy = lamp_e
	for tl in _track_lights:
		if is_instance_valid(tl):
			tl.visible = show_lamps
			tl.light_energy = lamp_e * 1.15

	if _transit_sim != null:
		_transit_sim.apply_night_lights(_night_factor)

	if _lbl_clock != null:
		var hh := int(floor(_time_hours)) % 24
		var mm := int(floor((_time_hours - floor(_time_hours)) * 60.0)) % 60
		_lbl_clock.text = "%02d:%02d" % [hh, mm]


func _unhandled_input(event: InputEvent) -> void:
	if _game_over:
		if event is InputEventKey and event.pressed and not event.echo:
			var gk := (event as InputEventKey).keycode
			if gk == KEY_ENTER or gk == KEY_KP_ENTER or gk == KEY_R:
				_restart_current_map_after_crash()
		return

	if _slot_modal != null and _slot_modal.visible:
		if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
			_slot_modal.visible = false
		return

	if _stats_modal != null and _stats_modal.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var sk := (event as InputEventKey).keycode
			if sk == KEY_ESCAPE or sk == KEY_T:
				_stats_modal.visible = false
		return

	if _audio_modal != null and _audio_modal.visible:
		if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
			_audio_modal.visible = false
		return

	if _in_home_menu:
		if event is InputEventKey and event.pressed and not event.echo:
			var hk := (event as InputEventKey).keycode
			if hk == KEY_1 or hk == KEY_LEFT:
				_select_home_map_card("grid")
			elif hk == KEY_2 or hk == KEY_RIGHT:
				_select_home_map_card("seattle")
			elif hk == KEY_ENTER or hk == KEY_KP_ENTER:
				_start_map_continue_or_new()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rmb_dragging = mb.pressed
			_last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _game_mode == GameMode.RUN and _cam_mode == CamMode.CAB:
					var hit_ctrl := _pick_cab_control(mb.position)
					if hit_ctrl == "throttle":
						var tr_c := _transit_sim.get_active_tram()
						if not tr_c.is_empty():
							_transit_sim.manual_drive = true
							_cab_dragging_lever = true
							_cab_lever_drag_start_y = mb.position.y
							_cab_lever_start_notch = int(tr_c["notch"])
							return
					elif hit_ctrl == "btn_doors":
						_sound.play_notch_click()
						_toggle_doors_with_safety_check()
						return
					elif hit_ctrl == "btn_bell":
						_ring_tram_bell()
						return
					elif hit_ctrl == "btn_light":
						_sound.play_notch_click()
						var tr_l := _transit_sim.get_active_tram()
						if not tr_l.is_empty():
							var hi := not bool(tr_l.get("headlamp_high", false))
							tr_l["headlamp_high"] = hi
							var hsp: SpotLight3D = tr_l["tram_info"].get("head_spot")
							if is_instance_valid(hsp):
								hsp.light_energy = 4.2 if hi else 1.2
							_show_toast("💡 远光前照灯：%s" % ("已开启" if hi else "已切回近光"))
						return
					elif hit_ctrl == "btn_wiper":
						_sound.play_notch_click()
						var tr_w := _transit_sim.get_active_tram()
						if not tr_w.is_empty():
							var won := not bool(tr_w.get("wipers_on", false))
							tr_w["wipers_on"] = won
							_show_toast("🌧 前挡风玻璃雨刮：%s" % ("已开启" if won else "已关闭"))
						return
					elif hit_ctrl == "btn_panto":
						_sound.play_notch_click()
						_show_toast("⚡ 受电弓状态：已升弓受流（750V DC 正常）")
						return
					elif hit_ctrl == "btn_sand":
						_sound.play_notch_click()
						_show_toast("🏜 轨道撒砂防滑系统已触发（增粘防滑）")
						return
					elif hit_ctrl == "btn_rev":
						_sound.play_notch_click()
						_do_cab_change()
						return
					elif hit_ctrl == "btn_eb":
						_sound.play_notch_click()
						_transit_sim.manual_set_notch(0)
						_show_toast("⚠ 已拍下驾驶台【紧急制动 EB】按钮！")
						return
				_lmb_down = true
				_lmb_drag_active = false
				_lmb_down_pos = mb.position
				_last_mouse_pos = mb.position
			else:
				if _cab_dragging_lever:
					_cab_dragging_lever = false
					return
				var was_click := _lmb_down and (not _lmb_drag_active)
				_lmb_down = false
				_lmb_drag_active = false
				if was_click and (_game_mode == GameMode.BUILD or _game_mode == GameMode.PLAN):
					_handle_map_left_click(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-1.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _cab_dragging_lever and _game_mode == GameMode.RUN and _cam_mode == CamMode.CAB:
			var dy := mm.position.y - _cab_lever_drag_start_y
			var target_n := clampi(_cab_lever_start_notch + int(round(-dy / 26.0)), 0, TransitSim.NOTCH_LABELS.size() - 1)
			var tr_d := _transit_sim.get_active_tram()
			if not tr_d.is_empty() and int(tr_d["notch"]) != target_n:
				_transit_sim.manual_set_notch(target_n)
				_sound.play_notch_click()
			return

		var is_bird := (_game_mode != GameMode.RUN or _cam_mode == CamMode.BIRD)

		# Support pressing down the MacBook trackpad / left button and moving left/right/up/down to drag map!
		if _lmb_down and not _lmb_drag_active and mm.position.distance_to(_lmb_down_pos) >= 5.0:
			_lmb_drag_active = true
			_preview_mi.mesh = null

		if is_bird and (_rmb_dragging or _lmb_drag_active):
			_pan_bird_by_screen_drag(_last_mouse_pos, mm.position, mm.relative)
		elif _game_mode == GameMode.RUN and (_lmb_drag_active or _rmb_dragging):
			_rotate_run_camera_by_delta(mm.relative)

		_last_mouse_pos = mm.position

		if _game_mode == GameMode.BUILD and not _lmb_drag_active and not _rmb_dragging:
			_update_build_hover_preview(mm.position)
		elif _game_mode == GameMode.RUN and _cam_mode == CamMode.CAB and not _lmb_drag_active and not _rmb_dragging:
			_update_cab_hover_tip(mm.position)
		elif _lbl_cab_tip != null:
			_lbl_cab_tip.visible = false

	elif event is InputEventPanGesture:
		# Two-finger trackpad glide support on macOS!
		var pg := event as InputEventPanGesture
		var is_bird_pan := (_game_mode != GameMode.RUN or _cam_mode == CamMode.BIRD)
		if is_bird_pan:
			var p_scale := _plan_height * 0.018
			_plan_target.x = clampf(_plan_target.x + pg.delta.x * p_scale, -_pan_limit_x, _pan_limit_x)
			_plan_target.z = clampf(_plan_target.z + pg.delta.y * p_scale, -_pan_limit_z, _pan_limit_z)
		else:
			_rotate_run_camera_by_delta(-pg.delta * 10.0)

	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_camera((1.0 - mg.factor) * 6.0)

	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			if _game_mode == GameMode.BUILD and _path_start_node >= 0:
				_path_start_node = -1
				_preview_mi.mesh = null
				_show_toast("已取消连线铺轨起点")
			else:
				_enter_home_screen()
			return
		elif k == KEY_TAB:
			_set_game_mode((_game_mode + 1) % 3)
			return
		elif k == KEY_N:
			_set_time_hours(22.0 if _night_factor < 0.5 else 13.5)
			return
		elif k == KEY_COMMA:
			_set_time_hours(_time_hours - 0.5)
			return
		elif k == KEY_PERIOD:
			_set_time_hours(_time_hours + 0.5)
			return
		elif k == KEY_F5:
			_open_slot_modal(_current_map_key, false)
			return
		elif k == KEY_F9:
			_open_slot_modal(_current_map_key, false)
			return
		elif k == KEY_T:
			_toggle_stats_modal()
			return

		if _game_mode == GameMode.BUILD:
			if k == KEY_R:
				if _build_tool == BuildTool.CROSSOVER:
					_build_crossover_type = NetworkGraph.CrossoverType.DOUBLE if _build_crossover_type == NetworkGraph.CrossoverType.SINGLE else NetworkGraph.CrossoverType.SINGLE
					_refresh_build_buttons()
					_show_toast("渡线类型已切换为：%s" % ("双渡线 (交叉渡线)" if _build_crossover_type == NetworkGraph.CrossoverType.DOUBLE else "单渡线"))
				else:
					_build_station_side = -_build_station_side
					_show_toast("站台方向已切换至轨道%s侧" % ("右" if _build_station_side > 0 else "左"))
		elif _game_mode == GameMode.PLAN:
			if k == KEY_BACKSPACE and not _draft_station_ids.is_empty():
				_draft_station_ids.pop_back()
				_refresh_plan_ui()
		else:
			# RUN & DRIVE Mode Controls:
			# W / S = Throttle / Brake; Arrow Keys (Up/Down/Left/Right) = Move/Rotate Camera View!
			match k:
				KEY_1: _set_cam_mode(CamMode.CAB)
				KEY_2: _set_cam_mode(CamMode.CHASE)
				KEY_3: _set_cam_mode(CamMode.INTERIOR)
				KEY_4: _set_cam_mode(CamMode.DOOR_ACTION)
				KEY_5: _set_cam_mode(CamMode.BIRD)
				KEY_C: _set_cam_mode((_cam_mode + 1) % 5)
				KEY_F:
					_transit_sim.cycle_active_tram(1)
				KEY_L:
					_switch_line(1)
				KEY_P:
					var lvl := _pax_sim.cycle_spawn_level()
					_btn_pax_rate.text = "客流: %s (P)" % PassengerSim.SPAWN_LEVEL_NAMES[lvl]
				KEY_Q:
					_transit_sim.manual_drive = not _transit_sim.manual_drive
				KEY_W:
					_transit_sim.manual_step_notch(1, _sound)
					_hold_up_timer = 0.25
				KEY_S:
					var tr_chk := _transit_sim.get_active_tram()
					if not tr_chk.is_empty():
						_transit_sim.manual_step_notch(-1, _sound)
						_hold_down_timer = 0.25
				KEY_SPACE:
					var tr := _transit_sim.get_active_tram()
					if not tr.is_empty():
						if float(tr["speed_mps"]) < 0.22:
							_toggle_doors_with_safety_check()
						else:
							_transit_sim.manual_set_notch(TransitSim.NOTCH_NEUTRAL)
				KEY_O:
					_toggle_doors_with_safety_check()
				KEY_B:
					_transit_sim.manual_set_notch(0)
				KEY_R:
					_do_cab_change()
				KEY_G:
					_do_throw_switch()
				KEY_H:
					_ring_tram_bell()


# Manual driving (monorail): throw the next switch ahead for this train's route
func _do_throw_switch() -> void:
	if not _transit_sim.manual_drive:
		_show_toast("⚠ 自动运营时道岔由调度按进路自动排列；切换手动驾驶 (Q) 后可手动扳道岔")
		return
	match _transit_sim.manual_throw_switch(_graph):
		"diverge":
			_sound.play_notch_click()
			_show_toast("🔀 前方道岔扳向【侧向/渡线】，转辙约 4 秒，锁闭后信号开放")
		"straight":
			_sound.play_notch_click()
			_show_toast("⬆ 前方道岔扳向【直向】，转辙约 4 秒，锁闭后信号开放")
		"busy":
			_show_toast("⚠ 前方道岔已被其他列车的进路占用，请在信号机前停车等待")
		"locked":
			_show_toast("⚠ 列车正在道岔上，道岔已锁闭不能扳动")
		"not_mono":
			_show_toast("⚠ 有轨电车线路没有可扳动的道岔（仅单轨线路）")
		_:
			_show_toast("前方 260 m 内没有道岔")


# Manual cab change: the driver walks to the other cab; at a terminal the tram then departs back the way it came
func _do_cab_change() -> void:
	var res := _transit_sim.manual_reverse_dir()
	match res:
		"ok":
			_sound.play_notch_click()
			_show_toast("🔄 已换端：现在从另一端驾驶室驾驶，前方为返程方向（出站后经渡线进入对向轨道）")
		"moving":
			_show_toast("⚠ 换端前请先停车（速度降到 0）")
		"doors":
			_show_toast("⚠ 换端前请先关闭车门 (O)")
		"not_terminal":
			var d := _transit_sim.turnback_distance_ahead(_transit_sim.get_active_tram())
			if d > 0.0:
				_show_toast("⚠ 只能在终点站换端：再向前行驶约 %d m 进入终点站后停车" % int(round(maxf(1.0, d - 55.0))))
			else:
				_show_toast("⚠ 只能在终点站换端折返（环线中途不能掉头）")


func _pick_cab_control(screen_pos: Vector2) -> String:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return ""
	var ctrls: Dictionary = tr["tram_info"].get("cab_controls", {})
	if ctrls.is_empty():
		return ""
	var ro := _camera.project_ray_origin(screen_pos)
	var rd := _camera.project_ray_normal(screen_pos).normalized()

	var hit_specs: Array = [
		["throttle", Vector3(0.0, 0.16, 0.0), 0.16],
		["btn_doors", Vector3(0.0, 0.01, 0.0), 0.026],
		["btn_bell", Vector3(0.0, 0.01, 0.0), 0.026],
		["btn_light", Vector3(0.0, 0.01, 0.0), 0.026],
		["btn_wiper", Vector3(0.0, 0.01, 0.0), 0.026],
		["btn_panto", Vector3(0.0, 0.01, 0.0), 0.026],
		["btn_sand", Vector3(0.0, 0.01, 0.0), 0.026],
		["btn_rev", Vector3(0.0, 0.018, 0.0), 0.042],
		["btn_eb", Vector3(0.0, 0.02, 0.0), 0.048],
	]
	var best_key := ""
	var best_dist := 999.0
	for hs: Array in hit_specs:
		var k: String = str(hs[0])
		var node: Node3D = ctrls.get(k)
		if not is_instance_valid(node):
			continue
		var wp := node.global_transform * (hs[1] as Vector3)
		var v := wp - ro
		var t_proj := v.dot(rd)
		if t_proj <= 0.05 or t_proj > 3.5:
			continue
		var perp_d := (v - rd * t_proj).length()
		if perp_d <= float(hs[2]) and t_proj < best_dist:
			best_dist = t_proj
			best_key = k
	return best_key


func _update_cab_hover_tip(screen_pos: Vector2) -> void:
	if _lbl_cab_tip == null:
		return
	var hit := _pick_cab_control(screen_pos)
	_cab_hover_ctrl = hit
	if hit.is_empty():
		_lbl_cab_tip.visible = false
		return
	var tip_map := {
		"throttle": "▲▼ 按住上下推拉【主控牵引/制动手柄】",
		"btn_doors": "● 点击【DOORS 车门开关】",
		"btn_bell": "● 点击【BELL 叮叮铜铃】",
		"btn_light": "● 点击【LIGHT 远近光前照灯】",
		"btn_wiper": "● 点击【WIPER 挡风玻璃雨刮】",
		"btn_panto": "● 点击【PANTO 受电弓状态检查】",
		"btn_sand": "● 点击【SAND 轨道撒砂防滑】",
		"btn_rev": "● 点击【F/N/R 换向/换端开关】",
		"btn_eb": "⚠ 点击【EB STOP 紧急制动】",
	}
	_lbl_cab_tip.text = str(tip_map.get(hit, ""))
	_lbl_cab_tip.position = screen_pos + Vector2(16, -24)
	_lbl_cab_tip.visible = true


func _ring_tram_bell() -> void:
	_sound.ring_bell()
	var tr := _transit_sim.get_active_tram()
	if not tr.is_empty() and _traffic_sim != null:
		var secs: Array = tr["tram_info"]["sections"]
		if not secs.is_empty() and is_instance_valid(secs[0]):
			var s0 := secs[0] as Node3D
			_traffic_sim.on_bell_rung(s0.global_position, -s0.global_transform.basis.z)


func _pan_bird_by_screen_drag(prev_screen: Vector2, curr_screen: Vector2, raw_rel: Vector2) -> void:
	var p0 = _screen_to_ground_xz(prev_screen)
	var p1 = _screen_to_ground_xz(curr_screen)
	if p0 != null and p1 != null:
		var delta_xz: Vector2 = (p0 as Vector2) - (p1 as Vector2)
		if delta_xz.length() < 400.0:
			_plan_target.x = clampf(_plan_target.x + delta_xz.x, -_pan_limit_x, _pan_limit_x)
			_plan_target.z = clampf(_plan_target.z + delta_xz.y, -_pan_limit_z, _pan_limit_z)
			return
	var pan_scale := _plan_height * 0.0017
	_plan_target.x = clampf(_plan_target.x - raw_rel.x * pan_scale, -_pan_limit_x, _pan_limit_x)
	_plan_target.z = clampf(_plan_target.z - raw_rel.y * pan_scale, -_pan_limit_z, _pan_limit_z)


func _rotate_run_camera_by_delta(rel: Vector2) -> void:
	if _cam_mode == CamMode.CAB:
		_cab_yaw = clampf(_cab_yaw - rel.x * 0.0042, deg_to_rad(-105.0), deg_to_rad(105.0))
		_cab_pitch = clampf(_cab_pitch - rel.y * 0.0036, deg_to_rad(-36.0), deg_to_rad(30.0))
	elif _cam_mode == CamMode.INTERIOR:
		_cab_yaw = wrapf(_cab_yaw - rel.x * 0.0045, -PI, PI)
		_cab_pitch = clampf(_cab_pitch - rel.y * 0.0036, deg_to_rad(-38.0), deg_to_rad(32.0))
	elif _cam_mode == CamMode.DOOR_ACTION:
		_door_cam_yaw = clampf(_door_cam_yaw - rel.x * 0.0045, deg_to_rad(-75.0), deg_to_rad(75.0))
		_door_cam_pitch = clampf(_door_cam_pitch + rel.y * 0.0038, deg_to_rad(-18.0), deg_to_rad(42.0))
	elif _cam_mode == CamMode.CHASE:
		_orbit_yaw -= rel.x * 0.0055
		_orbit_pitch = clampf(_orbit_pitch + rel.y * 0.0045, deg_to_rad(4.0), deg_to_rad(82.0))


func _screen_to_ground_xz(screen_pos: Vector2) -> Variant:
	var orig := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return null
	var t := -orig.y / dir.y
	if t <= 0.0:
		return null
	var hit := orig + dir * t
	return Vector2(hit.x, hit.z)


func _update_build_hover_preview(screen_pos: Vector2) -> void:
	var xz_var = _screen_to_ground_xz(screen_pos)
	if xz_var == null:
		_preview_mi.mesh = null
		return
	var xz: Vector2 = xz_var

	if _build_tool == BuildTool.TRACK_SINGLE:
		var hit := _graph.find_closest_edge(xz, 22.0, false)
		if hit.is_empty():
			_preview_mi.mesh = null
			return
		var eid := int(hit["edge_id"])
		var prev_w := 6.6 if _build_track_mode == NetworkGraph.TrackMode.DOUBLE else 3.4
		var mode_tag := "双线并行" if _build_track_mode == NetworkGraph.TrackMode.DOUBLE else "单线"
		_set_ribbon_preview(_preview_mi, [eid], Color(0.20, 0.92, 0.56, 0.72), prev_w)
		var ed_name: String = str(_graph.edges[eid]["name"])
		_lbl_build_hint.text = "悬停街道：%s · 单击铺设【%s · %s】（按下触摸板左右滑动拖动地图）" % [ed_name, mode_tag, BED_STYLE_NAMES[_build_bed_style]]

	elif _build_tool == BuildTool.TRACK_PATH:
		var nid := _graph.find_closest_node(xz, 26.0)
		if nid < 0:
			_preview_mi.mesh = null
			return
		if _path_start_node >= 0 and nid != _path_start_node:
			var path_eids := _graph.shortest_street_path(_path_start_node, nid, false)
			var prev_w := 6.6 if _build_track_mode == NetworkGraph.TrackMode.DOUBLE else 3.6
			var mode_tag := "双线并行" if _build_track_mode == NetworkGraph.TrackMode.DOUBLE else "单线"
			_set_ribbon_preview(_preview_mi, path_eids, Color(0.22, 0.85, 0.98, 0.78), prev_w)
			_lbl_build_hint.text = "自动寻路：%d 段街道 · 单击铺设【%s · %s】（Esc 取消起点）" % [path_eids.size(), mode_tag, BED_STYLE_NAMES[_build_bed_style]]
		else:
			var np: Vector2 = _graph.nodes[nid]["pos"]
			_set_point_box_preview(_preview_mi, Vector3(np.x, 0.6, np.y), Vector3(6.0, 1.2, 6.0), Color(0.22, 0.85, 0.98, 0.80))
			_lbl_build_hint.text = "路口：%s · 单击选为连线铺轨起点" % str(_graph.nodes[nid]["name"])

	elif _build_tool == BuildTool.CROSSOVER:
		var hit := _graph.find_closest_edge(xz, 22.0, true)
		var xo_name := "交叉渡线 (剪刀)" if _build_crossover_type == NetworkGraph.CrossoverType.DOUBLE else "单渡线"
		if hit.is_empty():
			_preview_mi.mesh = null
			_lbl_build_hint.text = "请将光标移至【已铺设双线轨道】的街道上修建%s（按 R 切换单/交叉渡线）" % xo_name
			return
		var eid := int(hit["edge_id"])
		var is_dbl := (int(_graph.built_track_modes.get(eid, NetworkGraph.TrackMode.SINGLE)) == NetworkGraph.TrackMode.DOUBLE)
		var elen := float(_graph.edges[eid]["length"])
		if not is_dbl or elen < 26.0:
			_set_ribbon_preview(_preview_mi, [eid], Color(0.95, 0.45, 0.22, 0.70), 6.2)
			_lbl_build_hint.text = "⚠ 仅限长度 ≥26m 的【双线轨道】可修建渡线（当前：%s）" % ("长度不足" if is_dbl else "单线轨道")
			return
		var smp := _graph.sample_edge(eid, 0.5)
		_set_oriented_box_preview(_preview_mi, (smp["pos"] as Vector3) + Vector3(0.0, 0.35, 0.0), smp["fwd"] as Vector3, Vector3(5.8, 0.7, 21.0), Color(0.96, 0.78, 0.22, 0.80))
		_lbl_build_hint.text = "单击在 %s 中段修建【%s】（按 R 切换单/交叉渡线）" % [str(_graph.edges[eid]["name"]), xo_name]

	elif _build_tool == BuildTool.STATION:
		var near_sid := _graph.find_closest_station(xz, 8.5)
		if near_sid >= 0:
			var sp_ex := _graph.get_station_platform_world_pos(near_sid)
			_set_point_box_preview(_preview_mi, sp_ex + Vector3(0.0, 1.5, 0.0), Vector3(4.5, 3.0, 27.0), Color(0.28, 0.78, 0.98, 0.75))
			_lbl_build_hint.text = "已对准车站【%s】· 单击可选中并在左侧修改站名" % str(_graph.stations[near_sid]["name"])
			return
		var hit := _graph.find_closest_edge(xz, 22.0, true)
		if hit.is_empty():
			_preview_mi.mesh = null
			_lbl_build_hint.text = "请将光标移至【已铺设轨道】的街道上建造车站（按 R 切换左右侧站台）"
			return
		var eid := int(hit["edge_id"])
		var is_dbl := (int(_graph.built_track_modes.get(eid, NetworkGraph.TrackMode.SINGLE)) == NetworkGraph.TrackMode.DOUBLE)
		var sep_prev := _graph.get_edge_track_half_sep(eid)
		var pos3: Vector3 = hit["pos"]
		var fwd3: Vector3 = hit["fwd"]
		var right3 := fwd3.cross(Vector3.UP).normalized()
		if is_dbl and _build_station_kind == NetworkGraph.StationKind.ISLAND:
			_set_oriented_box_preview(_preview_mi, pos3 + Vector3(0.0, 0.4, 0.0), fwd3, Vector3(3.1, 0.8, 27.0), Color(0.25, 0.92, 0.62, 0.78))
			_lbl_build_hint.text = "单击建造【中央岛式站台】（双线将自动加宽至 ±3.05m，列车开内侧门）"
		elif is_dbl and _build_station_kind == NetworkGraph.StationKind.SIDE_DUAL:
			_set_oriented_box_preview(_preview_mi, pos3 + Vector3(0.0, 0.4, 0.0), fwd3, Vector3(11.8, 0.7, 27.0), Color(0.25, 0.92, 0.62, 0.58))
			_lbl_build_hint.text = "单击建造【对称双侧站台】（同时覆盖双线轨道左右两侧）"
		else:
			var plat_pos := pos3 + right3 * (float(_build_station_side) * (2.9 + sep_prev)) + Vector3(0.0, 0.4, 0.0)
			_set_oriented_box_preview(_preview_mi, plat_pos, fwd3, Vector3(3.0, 0.8, 27.0), Color(0.25, 0.92, 0.62, 0.78))
			_lbl_build_hint.text = "单击在此建造精细 3D 车站（按 R 切换左右侧站台）"

	elif _build_tool == BuildTool.DEMOLISH:
		var sid := _graph.find_closest_station(xz, 18.0)
		if sid >= 0:
			var sp := _graph.get_station_platform_world_pos(sid)
			_set_point_box_preview(_preview_mi, sp + Vector3(0.0, 1.5, 0.0), Vector3(5.0, 3.0, 28.0), Color(0.96, 0.26, 0.22, 0.75))
			_lbl_build_hint.text = "单击拆除车站：%s" % str(_graph.stations[sid]["name"])
			return
		var hit := _graph.find_closest_edge(xz, 18.0, true)
		if not hit.is_empty():
			_set_ribbon_preview(_preview_mi, [int(hit["edge_id"])], Color(0.96, 0.26, 0.22, 0.78), 3.8)
			_lbl_build_hint.text = "单击拆除该段轨道"
		else:
			_preview_mi.mesh = null


func _handle_map_left_click(screen_pos: Vector2) -> void:
	var xz_var = _screen_to_ground_xz(screen_pos)
	if xz_var == null:
		return
	var xz: Vector2 = xz_var

	if _game_mode == GameMode.BUILD:
		var mode_tag := "双线" if _build_track_mode == NetworkGraph.TrackMode.DOUBLE else "单线"
		if _build_tool == BuildTool.TRACK_SINGLE:
			var hit := _graph.find_closest_edge(xz, 22.0, false)
			if not hit.is_empty():
				var eid := int(hit["edge_id"])
				_graph.set_track_on_edge(eid, _build_bed_style, _build_track_mode)
				_rebuild_tracks_only_visual()
				_mark_modified_and_quick_save()
				_show_toast("已铺设【%s · %s】轨道：%s" % [mode_tag, BED_STYLE_NAMES[_build_bed_style], str(_graph.edges[eid]["name"])])

		elif _build_tool == BuildTool.TRACK_PATH:
			var nid := _graph.find_closest_node(xz, 26.0)
			if nid < 0:
				return
			if _path_start_node < 0:
				_path_start_node = nid
				_show_toast("已选起点路口：%s，请点击终点路口自动寻路铺轨" % str(_graph.nodes[nid]["name"]))
			elif nid != _path_start_node:
				var eids := _graph.shortest_street_path(_path_start_node, nid, false)
				for eid: int in eids:
					_graph.set_track_on_edge(eid, _build_bed_style, _build_track_mode)
				_path_start_node = nid
				_rebuild_tracks_only_visual()
				_mark_modified_and_quick_save()
				_show_toast("已沿最短路径铺设 %d 段【%s · %s】轨道！" % [eids.size(), mode_tag, BED_STYLE_NAMES[_build_bed_style]])

		elif _build_tool == BuildTool.CROSSOVER:
			var hit := _graph.find_closest_edge(xz, 22.0, true)
			if hit.is_empty():
				_show_toast("请先铺设【双线轨道】，再点击该双线路段修建渡线 Crossover！")
				return
			var eid := int(hit["edge_id"])
			if _graph.set_crossover_on_edge(eid, _build_crossover_type):
				_rebuild_tracks_only_visual()
				_mark_modified_and_quick_save()
				var xo_name := "交叉渡线 (剪刀)" if _build_crossover_type == NetworkGraph.CrossoverType.DOUBLE else "单渡线"
				_show_toast("已在 %s 修建【%s】！" % [str(_graph.edges[eid]["name"]), xo_name])
			else:
				_show_toast("⚠ 仅限长度 ≥26m 的【双线轨道】可修建渡线！")

		elif _build_tool == BuildTool.STATION:
			var near_sid := _graph.find_closest_station(xz, 8.5)
			if near_sid >= 0:
				_editing_station_id = near_sid
				if _edit_station_name != null:
					_edit_station_name.text = str(_graph.stations[near_sid]["name"])
				_show_toast("已选中车站【%s】，可在左侧「站名编辑」栏修改名称！" % str(_graph.stations[near_sid]["name"]))
				return
			var hit := _graph.find_closest_edge(xz, 22.0, true)
			if hit.is_empty():
				_show_toast("请先在街道上铺设轨道，再在轨道旁建造车站！")
				return
			var eid := int(hit["edge_id"])
			var t_hit := float(hit["t"])
			var is_dbl := (int(_graph.built_track_modes.get(eid, NetworkGraph.TrackMode.SINGLE)) == NetworkGraph.TrackMode.DOUBLE)
			var custom_n := _edit_station_name.text.strip_edges() if (_edit_station_name != null and _editing_station_id < 0) else ""
			if is_dbl and _build_station_kind == NetworkGraph.StationKind.SIDE_DUAL:
				var sid1 := _graph.add_station_on_edge(eid, t_hit, 1, custom_n, NetworkGraph.StationKind.SIDE_SINGLE)
				var sid2 := _graph.add_station_on_edge(eid, t_hit, -1, custom_n, NetworkGraph.StationKind.SIDE_SINGLE)
				if sid1 >= 0 or sid2 >= 0:
					var last_sid := sid2 if sid2 >= 0 else sid1
					_editing_station_id = last_sid
					if _edit_station_name != null and _graph.stations.has(last_sid):
						_edit_station_name.text = str(_graph.stations[last_sid]["name"])
					_rebuild_tracks_only_visual()
					_mark_modified_and_quick_save()
					_show_toast("已建成对称双侧站台：%s / %s" % [
						str(_graph.stations.get(sid1, {}).get("name", "")),
						str(_graph.stations.get(sid2, {}).get("name", "")),
					])
			else:
				var req_kind := _build_station_kind if is_dbl else NetworkGraph.StationKind.SIDE_SINGLE
				var sid := _graph.add_station_on_edge(eid, t_hit, _build_station_side, custom_n, req_kind)
				if sid >= 0:
					_editing_station_id = sid
					if _edit_station_name != null:
						_edit_station_name.text = str(_graph.stations[sid]["name"])
					_rebuild_tracks_only_visual()
					_mark_modified_and_quick_save()
					_show_toast("已建成车站：%s" % str(_graph.stations[sid]["name"]))

		elif _build_tool == BuildTool.DEMOLISH:
			var sid := _graph.find_closest_station(xz, 18.0)
			if sid >= 0:
				var sname := str(_graph.stations[sid]["name"])
				_graph.remove_station(sid)
				_rebuild_tracks_only_visual()
				_mark_modified_and_quick_save()
				_show_toast("已拆除车站：%s" % sname)
				return
			var hit := _graph.find_closest_edge(xz, 18.0, true)
			if not hit.is_empty():
				var deid := int(hit["edge_id"])
				if _graph.crossovers.has(deid):
					_graph.crossovers.erase(deid)
					_rebuild_tracks_only_visual()
					_mark_modified_and_quick_save()
					_show_toast("已拆除该段渡线 Crossover（保留双线轨道）")
				else:
					_graph.remove_track_on_edge(deid)
					_rebuild_tracks_only_visual()
					_mark_modified_and_quick_save()
					_show_toast("已拆除轨道段")

	elif _game_mode == GameMode.PLAN:
		var sid := _graph.find_closest_station(xz, 32.0)
		if sid < 0:
			_show_toast("请点击已建成的 3D 车站将其加入新线路！（按下触摸板移动可拖动地图）")
			return
		if not _draft_station_ids.is_empty():
			var prev_sid := _draft_station_ids[_draft_station_ids.size() - 1]
			if prev_sid == sid:
				return
			var check_path := _graph.find_track_path_between_stations(prev_sid, sid)
			if check_path.is_empty():
				_show_toast("该车站与上一站之间没有连通的已建轨道！请先在【建设轨道】连通轨道。")
				return
		_draft_station_ids.append(sid)
		_refresh_plan_ui()


func _mark_modified_and_quick_save() -> void:
	if not _is_demo_readonly:
		_save_current_progress(false)


func _rebuild_tracks_only_visual() -> void:
	for c in _track_root.get_children():
		c.queue_free()
	var built := TrackBuilder.build_network_tracks_and_stations(
		_track_root,
		_graph,
		_cjk_font,
		_grass_track_mat
	)
	_station_views = built["stations"]
	_sync_landmark_monorail()
	CityBuilder.apply_track_clearance(_city_root, _graph.get_meta("track_clear_idx", {}), _graph.get_meta("station_bays", []))
	CityBuilder.apply_station_bays(_city_root, _graph.get_meta("station_bays", []))
	_track_lights.clear()
	for l in built["lights"]:
		_track_lights.append(l)
	_apply_lighting_from_clock()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)

	# Safety guard so mouse drag state never sticks if button was released over a UI control
	if _lmb_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_lmb_down = false
		_lmb_drag_active = false
	if _rmb_dragging and not (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
		_rmb_dragging = false

	if _toast_timer > 0.0:
		_toast_timer -= dt
		if _toast_timer <= 0.0 and _lbl_toast != null:
			_lbl_toast.visible = false

	if _reset_confirm_timer > 0.0:
		_reset_confirm_timer -= dt
		if _reset_confirm_timer <= 0.0 and _btn_home_reset != null:
			_btn_home_reset.text = "重新开始"

	if _game_mode == GameMode.RUN and not _in_home_menu and not _game_over:
		_update_monorail(dt)
	_update_accident_fx(dt)

	if delta > 0.0005 and delta < 0.25:
		_fps_ema = lerpf(_fps_ema, 1.0 / delta, 0.12)
	if _lbl_fps != null:
		_lbl_fps.text = "%d FPS" % int(round(_fps_ema))

	if _game_over:
		_transit_sim.step_accident_visuals(dt)
		_accident_orbit_yaw += dt * 0.34
		var acc_pos := _accident_focus + Vector3(cos(_accident_orbit_yaw) * 18.5, 9.8, sin(_accident_orbit_yaw) * 18.5)
		_camera.fov = 52.0
		_camera.global_position = _camera.global_position.lerp(acc_pos, minf(1.0, dt * 6.5))
		_camera.look_at(_accident_focus + Vector3(0.0, 1.35, 0.0), Vector3.UP)
		_process_shot_tour()
		return

	if _in_home_menu:
		_home_orbit_angle += dt * 0.08
		_pax_sim.step_simulation(dt, _graph)
		_traffic_sim.step_traffic(dt, _graph, _transit_sim.trams, 0, false, Vector3.ZERO)
		_transit_sim.step_all_trams(dt, _graph, _pax_sim, _traffic_sim, _sound)
		_sound.speed_mps = 0.0
		_sound.traction_effort = 0.0
		_sound.overspeed_squeal = 0.0
		_update_home_backdrop_camera()
		_process_shot_tour()
		return

	# Periodic rotating auto-save every 120 seconds during active play
	if not _is_demo_readonly:
		_autosave_timer += dt
		if _autosave_timer >= 120.0:
			_autosave_timer = 0.0
			var payload := _build_current_save_payload("定时自动存档")
			SaveManager.save_current(_current_map_key, payload)
			SaveManager.push_autosave(_current_map_key, "定时自动存档", payload)

	if _slot_modal == null or not _slot_modal.visible:
		_handle_bird_pan_keys(dt)

	if _game_mode == GameMode.RUN:
		if _slot_modal == null or not _slot_modal.visible:
			_handle_run_held_keys(dt)
			_handle_run_arrow_camera_keys(dt)
		_pax_sim.step_simulation(dt, _graph)
		_traffic_sim.step_traffic(
			dt,
			_graph,
			_transit_sim.trams,
			_transit_sim.active_tram_idx,
			_transit_sim.manual_drive,
			_get_traffic_focus_pos()
		)
		var acc_ev := _transit_sim.step_all_trams(dt, _graph, _pax_sim, _traffic_sim, _sound)
		if not acc_ev.is_empty():
			_trigger_game_over_accident(acc_ev)
			_process_shot_tour()
			return

		_hud_refresh_timer += dt
		if _hud_refresh_timer >= 0.065:
			_hud_refresh_timer = 0.0
			_update_run_hud()
			_update_station_announcements()
		if _stats_modal != null and _stats_modal.visible:
			_stats_refresh_accum += dt
			if _stats_refresh_accum >= 0.5:
				_stats_refresh_accum = 0.0
				_refresh_stats_modal_ui()
	else:
		_sound.speed_mps = 0.0
		_sound.traction_effort = 0.0
		_sound.overspeed_squeal = 0.0

	_update_camera(dt)
	_process_shot_tour()


func _update_home_backdrop_camera() -> void:
	var center := Vector3(0.0, 18.0, 60.0 if _current_map_key == "seattle" else 0.0)
	var radius := 310.0
	var cam_pos := center + Vector3(cos(_home_orbit_angle) * radius, 195.0, sin(_home_orbit_angle) * radius)
	_camera.fov = 50.0
	_camera.global_position = cam_pos
	_camera.look_at(center, Vector3.UP)


func _handle_bird_pan_keys(dt: float) -> void:
	if _game_mode == GameMode.RUN and _cam_mode != CamMode.BIRD:
		return
	var move := Vector2.ZERO
	if _game_mode != GameMode.RUN:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0
	else:
		# In RUN + BIRD mode, W/S remain reserved for driving while Arrow keys & A/D pan the bird view!
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1.0
		if Input.is_key_pressed(KEY_UP):
			move.y -= 1.0
		if Input.is_key_pressed(KEY_DOWN):
			move.y += 1.0

	if move.length_squared() > 0.01:
		var spd := _plan_height * 0.85 * dt
		_plan_target.x = clampf(_plan_target.x + move.normalized().x * spd, -_pan_limit_x, _pan_limit_x)
		_plan_target.z = clampf(_plan_target.z + move.normalized().y * spd, -_pan_limit_z, _pan_limit_z)


func _handle_run_held_keys(dt: float) -> void:
	if Input.is_key_pressed(KEY_W):
		_hold_up_timer -= dt
		if _hold_up_timer <= 0.0:
			_transit_sim.manual_step_notch(1, _sound)
			_hold_up_timer = 0.16
	if Input.is_key_pressed(KEY_S):
		_hold_down_timer -= dt
		if _hold_down_timer <= 0.0:
			_transit_sim.manual_step_notch(-1, _sound)
			_hold_down_timer = 0.16


func _handle_run_arrow_camera_keys(dt: float) -> void:
	if _cam_mode == CamMode.BIRD:
		return # Handled in _handle_bird_pan_keys
	var look := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		look.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		look.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		look.y += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		look.y -= 1.0

	if look.length_squared() < 0.01:
		return

	var yaw_spd := 1.45 * dt
	var pitch_spd := 1.05 * dt

	if _cam_mode == CamMode.CAB:
		_cab_yaw = clampf(_cab_yaw - look.x * yaw_spd, deg_to_rad(-105.0), deg_to_rad(105.0))
		_cab_pitch = clampf(_cab_pitch + look.y * pitch_spd, deg_to_rad(-36.0), deg_to_rad(30.0))
	elif _cam_mode == CamMode.INTERIOR:
		_cab_yaw = wrapf(_cab_yaw - look.x * yaw_spd, -PI, PI)
		_cab_pitch = clampf(_cab_pitch + look.y * pitch_spd, deg_to_rad(-38.0), deg_to_rad(32.0))
	elif _cam_mode == CamMode.DOOR_ACTION:
		_door_cam_yaw = clampf(_door_cam_yaw + look.x * yaw_spd, deg_to_rad(-75.0), deg_to_rad(75.0))
		_door_cam_pitch = clampf(_door_cam_pitch + look.y * pitch_spd, deg_to_rad(-18.0), deg_to_rad(42.0))
	else:
		# CHASE external orbit camera
		_orbit_yaw += look.x * yaw_spd
		_orbit_pitch = clampf(_orbit_pitch + look.y * pitch_spd, deg_to_rad(4.0), deg_to_rad(82.0))


func _update_monorail(dt: float) -> void:
	if _monorail_curve == null or _monorail_cars.is_empty() or _monorail_cars_hidden:
		return
	var mlen := _monorail_curve.get_baked_length()
	if mlen < 40.0:
		return
	if _monorail_pause > 0.0:
		_monorail_pause -= dt
	else:
		_monorail_s += _monorail_dir * 13.5 * dt
		if _monorail_s >= mlen - 8.0:
			_monorail_s = mlen - 8.0
			_monorail_dir = -1.0
			_monorail_pause = 3.5
		elif _monorail_s <= 38.0:
			_monorail_s = 38.0
			_monorail_dir = 1.0
			_monorail_pause = 2.0
	for i in range(_monorail_cars.size()):
		var car: Node3D = _monorail_cars[i]
		var cs := clampf(_monorail_s - float(i) * 8.8, 1.0, mlen - 1.0)
		car.global_transform = TrackBuilder.sample_track_frame(_monorail_curve, cs, mlen, false)


func _zoom_camera(step_dir: float) -> void:
	if _game_mode != GameMode.RUN or _cam_mode == CamMode.BIRD:
		_plan_height = clampf(_plan_height * (1.0 + step_dir * 0.13), 55.0, 1180.0)
	elif _cam_mode == CamMode.CAB or _cam_mode == CamMode.INTERIOR:
		_cab_fov = clampf(_cab_fov * (1.0 + step_dir * 0.12), 30.0, 92.0)
	elif _cam_mode == CamMode.CHASE:
		_orbit_dist = clampf(_orbit_dist * (1.0 + step_dir * 0.11), 7.5, 95.0)


func _set_cam_mode(mode: int) -> void:
	_cam_mode = mode
	_snap_camera_next = true
	_cab_yaw = 0.0
	_cab_pitch = deg_to_rad(-8.5) if mode == CamMode.CAB else deg_to_rad(-4.0)
	_cab_fov = 66.0 if mode == CamMode.CAB else 72.0
	_cab_dragging_lever = false
	if _lbl_cab_tip != null:
		_lbl_cab_tip.visible = false
	_door_cam_yaw = 0.0
	_door_cam_pitch = 0.0
	if mode == CamMode.CAB:
		_camera.fov = _cab_fov
	elif mode == CamMode.INTERIOR:
		_camera.fov = 72.0
	elif mode == CamMode.BIRD:
		_camera.fov = 46.0
		_sun.directional_shadow_max_distance = 540.0
		var tr := _transit_sim.get_active_tram()
		if not tr.is_empty():
			var p := ((tr["tram_info"]["sections"] as Array)[0] as Node3D).global_position
			_plan_target = Vector3(p.x, 0.0, p.z)
	else:
		_camera.fov = 56.0
	if mode != CamMode.BIRD and _game_mode == GameMode.RUN:
		_sun.directional_shadow_max_distance = 290.0


func _update_camera(dt: float) -> void:
	if _game_mode != GameMode.RUN or _cam_mode == CamMode.BIRD or _transit_sim.trams.is_empty():
		var cam_pos := _plan_target + Vector3(0.0, _plan_height, _plan_height * 0.20)
		if _snap_camera_next:
			_camera.global_position = cam_pos
			_snap_camera_next = false
		else:
			_camera.global_position = _camera.global_position.lerp(cam_pos, minf(1.0, dt * 12.0))
		_camera.look_at(_plan_target, Vector3.FORWARD)
		return

	var tr := _transit_sim.get_active_tram()
	var tinfo: Dictionary = tr["tram_info"]
	var sections: Array = tinfo["sections"]
	if sections.is_empty():
		return
	var active_end := int(tinfo.get("active_end", 0))
	var front_sec: Node3D = sections[0] if active_end == 0 else sections[sections.size() - 1]
	var mid_sec: Node3D = sections[sections.size() / 2]

	if _cam_mode == CamMode.CAB:
		_camera.fov = lerpf(_camera.fov, _cab_fov, minf(1.0, dt * 14.0))
		var anchor: Node3D = tinfo.get("cab_anchor")
		if is_instance_valid(anchor):
			var base_tf := anchor.global_transform
			var local_rot := Basis.from_euler(Vector3(_cab_pitch, _cab_yaw, 0.0))
			_camera.global_transform = Transform3D(base_tf.basis * local_rot, base_tf.origin)
	elif _cam_mode == CamMode.INTERIOR:
		_camera.fov = lerpf(_camera.fov, _cab_fov, minf(1.0, dt * 14.0))
		var i_anchor: Node3D = tinfo.get("interior_anchor")
		if is_instance_valid(i_anchor):
			var base_tf := i_anchor.global_transform
			var local_rot := Basis.from_euler(Vector3(_cab_pitch, _cab_yaw, 0.0))
			_camera.global_transform = Transform3D(base_tf.basis * local_rot, base_tf.origin)
	elif _cam_mode == CamMode.DOOR_ACTION:
		# Automatically pick platform side if docked near a station, and allow arrow-key orbit!
		var side_sign := 1.0
		var near_st := _transit_sim._find_station_at_current_pos(tr)
		if int(near_st["stop_idx"]) >= 0:
			var st_pos: Vector3 = (tr["stops"] as Array)[int(near_st["stop_idx"])]["pos"]
			var local_st := front_sec.global_transform.affine_inverse() * st_pos
			side_sign = 1.0 if local_st.x >= 0.0 else -1.0
		var base_offset := Vector3(side_sign * 4.2, 1.78, -3.6).rotated(Vector3.UP, _door_cam_yaw)
		base_offset.y += sin(_door_cam_pitch) * 3.2
		var cam_pos := front_sec.global_transform * base_offset
		var look_pt := front_sec.global_transform * Vector3(side_sign * 0.65, 1.26, 0.25)
		_camera.global_position = cam_pos
		_camera.look_at(look_pt, Vector3.UP)
	else:
		var focus := mid_sec.global_position + Vector3(0.0, 2.1, 0.0)
		var lead_fwd := -front_sec.global_transform.basis.z if active_end == 0 else front_sec.global_transform.basis.z
		var tr_yaw := atan2(lead_fwd.x, lead_fwd.z)
		var total_yaw := tr_yaw + _orbit_yaw + PI
		var horiz := cos(_orbit_pitch) * _orbit_dist
		var offset := Vector3(sin(total_yaw) * horiz, sin(_orbit_pitch) * _orbit_dist, cos(total_yaw) * horiz)
		var desired_pos := focus + offset
		desired_pos.y = maxf(desired_pos.y, focus.y - 1.2)
		if _snap_camera_next:
			_camera.global_position = desired_pos
			_snap_camera_next = false
		else:
			_camera.global_position = _camera.global_position.lerp(desired_pos, minf(1.0, dt * 10.0))
		_camera.look_at(focus, Vector3.UP)


# --- Preview Mesh Helpers for Build & Plan Modes ---
func _set_ribbon_preview(mi: MeshInstance3D, edge_ids: Array[int], col: Color, width: float) -> void:
	if edge_ids.is_empty():
		mi.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	for eid: int in edge_ids:
		if not _graph.edges.has(eid):
			continue
		var pts: Array = _graph.edges[eid]["pts"]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := b - a
			if d.length() < 0.1:
				continue
			var nrm := Vector2(-d.y, d.x).normalized() * hw
			var y := 0.32
			for v: Vector3 in [
				Vector3(a.x - nrm.x, y, a.y - nrm.y),
				Vector3(b.x + nrm.x, y, b.y + nrm.y),
				Vector3(a.x + nrm.x, y, a.y + nrm.y),
				Vector3(a.x - nrm.x, y, a.y - nrm.y),
				Vector3(b.x - nrm.x, y, b.y - nrm.y),
				Vector3(b.x + nrm.x, y, b.y + nrm.y),
			]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	mi.global_transform = Transform3D.IDENTITY
	mi.mesh = st.commit()
	mi.material_override = _translucent_mat(col)


func _set_point_box_preview(mi: MeshInstance3D, pos: Vector3, sz: Vector3, col: Color) -> void:
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.global_transform = Transform3D(Basis.IDENTITY, pos)
	mi.material_override = _translucent_mat(col)


func _set_oriented_box_preview(mi: MeshInstance3D, pos: Vector3, fwd: Vector3, sz: Vector3, col: Color) -> void:
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	mi.material_override = _translucent_mat(col)


static func _translucent_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# --- UI Construction & Callbacks ---
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var master_root := Control.new()
	master_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	master_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	if _cjk_font != null:
		theme.default_font = _cjk_font
		theme.default_font_size = 14
	master_root.theme = theme
	canvas.add_child(master_root)

	# In-Game HUD root container
	_hud_layer_ctrl = Control.new()
	_hud_layer_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	master_root.add_child(_hud_layer_ctrl)

	# 1. Persistent Top Mode & Lighting Bar (Centered Top)
	_nav_bar = _make_panel(Color(0.07, 0.09, 0.12, 0.90))
	_nav_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_nav_bar.position = Vector2(-470, 12)
	_hud_layer_ctrl.add_child(_nav_bar)

	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 7)
	_nav_bar.add_child(nav_hbox)

	nav_hbox.add_child(_make_btn("◀ 主页(Esc)", func(): _enter_home_screen()))
	nav_hbox.add_child(VSeparator.new())

	_btn_mode_build = _make_btn("[1] 建设轨道", func(): _set_game_mode(GameMode.BUILD))
	_btn_mode_plan = _make_btn("[2] 规划线路", func(): _set_game_mode(GameMode.PLAN))
	_btn_mode_run = _make_btn("[3] 运行与驾驶 (Tab)", func(): _set_game_mode(GameMode.RUN))
	nav_hbox.add_child(_btn_mode_build)
	nav_hbox.add_child(_btn_mode_plan)
	nav_hbox.add_child(_btn_mode_run)

	nav_hbox.add_child(VSeparator.new())
	nav_hbox.add_child(_make_btn("存档(F5/F9)", func(): _open_slot_modal(_current_map_key, false)))
	_btn_quick_save_run = _make_btn("存运行档", func(): _open_slot_modal(_current_map_key, false))
	nav_hbox.add_child(_btn_quick_save_run)
	nav_hbox.add_child(_make_btn("运营看板(T)", func(): _toggle_stats_modal()))
	nav_hbox.add_child(_make_btn("音频设置", func(): _toggle_audio_modal()))
	nav_hbox.add_child(VSeparator.new())
	nav_hbox.add_child(_make_btn("纯白天", func(): _set_time_hours(13.5)))
	nav_hbox.add_child(_make_btn("纯夜景", func(): _set_time_hours(22.0)))

	_slider_time = HSlider.new()
	_slider_time.min_value = 0.0; _slider_time.max_value = 24.0; _slider_time.step = 0.1
	_slider_time.value = _time_hours
	_slider_time.custom_minimum_size = Vector2(110, 22)
	_slider_time.focus_mode = Control.FOCUS_NONE
	_slider_time.value_changed.connect(func(v: float):
		if not _updating_slider:
			_time_hours = v
			_apply_lighting_from_clock()
	)
	nav_hbox.add_child(_slider_time)

	_lbl_clock = Label.new()
	_lbl_clock.text = "13:30"
	_lbl_clock.add_theme_color_override("font_color", Color(0.96, 0.90, 0.70))
	nav_hbox.add_child(_lbl_clock)

	nav_hbox.add_child(VSeparator.new())
	_lbl_fps = Label.new()
	_lbl_fps.text = "60 FPS"
	_lbl_fps.add_theme_font_size_override("font_size", 12)
	_lbl_fps.add_theme_color_override("font_color", Color(0.55, 0.88, 0.70))
	nav_hbox.add_child(_lbl_fps)

	# Toast Notification Banner (bottom-center above console, never overlaps top HUD panels)
	_lbl_toast = Label.new()
	_lbl_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_lbl_toast.position = Vector2(-340, -44)
	_lbl_toast.custom_minimum_size = Vector2(680, 28)
	_lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_toast.add_theme_color_override("font_color", Color(0.98, 0.94, 0.62))
	_lbl_toast.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_lbl_toast.add_theme_constant_override("shadow_offset_x", 1)
	_lbl_toast.add_theme_constant_override("shadow_offset_y", 1)
	_lbl_toast.visible = false
	master_root.add_child(_lbl_toast)

	# Interactive 3D Cab Control Hover Tooltip
	_lbl_cab_tip = Label.new()
	_lbl_cab_tip.add_theme_font_size_override("font_size", 13)
	_lbl_cab_tip.add_theme_color_override("font_color", Color(0.55, 0.96, 0.80))
	_lbl_cab_tip.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.90))
	_lbl_cab_tip.add_theme_constant_override("shadow_offset_x", 1)
	_lbl_cab_tip.add_theme_constant_override("shadow_offset_y", 1)
	_lbl_cab_tip.visible = false
	master_root.add_child(_lbl_cab_tip)

	# 2. BUILD MODE PANEL (Left Side)
	_build_panel = _make_panel(Color(0.07, 0.09, 0.12, 0.90))
	_build_panel.position = Vector2(16, 72)
	_build_panel.custom_minimum_size = Vector2(375, 595)
	_hud_layer_ctrl.add_child(_build_panel)

	var b_vbox := VBoxContainer.new()
	b_vbox.add_theme_constant_override("separation", 8)
	_build_panel.add_child(b_vbox)

	var b_title := Label.new()
	b_title.text = "轨道与车站建设（铺设后轨道类型永久锁定）"
	b_title.add_theme_font_size_override("font_size", 15)
	b_title.add_theme_color_override("font_color", Color(0.50, 0.90, 0.72))
	b_vbox.add_child(b_title)

	var t_lbl := Label.new()
	t_lbl.text = "① 选择建造工具："
	b_vbox.add_child(t_lbl)

	var tool_names := [
		"铺设单段街道轨道",
		"连点两路口自动寻路铺轨",
		"在双线轨道修建渡线 Crossover (R切换)",
		"在已建轨道旁建造精细车站 (R换侧)",
		"拆除车站或轨道段",
	]
	_tool_btns.clear()
	for ti in range(tool_names.size()):
		var idx_copy := ti
		var tb := _make_btn(tool_names[ti], func():
			_build_tool = idx_copy
			_path_start_node = -1
			_refresh_build_buttons()
		)
		b_vbox.add_child(tb)
		_tool_btns.append(tb)

	var tm_row := HBoxContainer.new()
	tm_row.add_theme_constant_override("separation", 6)
	b_vbox.add_child(tm_row)
	_track_mode_btns.clear()
	for t_pair: Array in [[NetworkGraph.TrackMode.SINGLE, "轨道制式：单线"], [NetworkGraph.TrackMode.DOUBLE, "轨道制式：双线并行"]]:
		var tm_val := int(t_pair[0])
		var tmb := _make_btn(str(t_pair[1]), func():
			_build_track_mode = tm_val
			_refresh_build_buttons()
		)
		tmb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tm_row.add_child(tmb)
		_track_mode_btns.append(tmb)

	var xo_row := HBoxContainer.new()
	xo_row.add_theme_constant_override("separation", 6)
	b_vbox.add_child(xo_row)
	_crossover_type_btns.clear()
	for xo_pair: Array in [[NetworkGraph.CrossoverType.SINGLE, "渡线：单渡线"], [NetworkGraph.CrossoverType.DOUBLE, "渡线：双渡线(交叉)"]]:
		var xo_val := int(xo_pair[0])
		var xob := _make_btn(str(xo_pair[1]), func():
			_build_crossover_type = xo_val
			_build_tool = BuildTool.CROSSOVER
			_path_start_node = -1
			_refresh_build_buttons()
		)
		xob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xo_row.add_child(xob)
		_crossover_type_btns.append(xob)

	var sk_row := HBoxContainer.new()
	sk_row.add_theme_constant_override("separation", 5)
	b_vbox.add_child(sk_row)
	_station_kind_btns.clear()
	for sk_pair: Array in [
		[NetworkGraph.StationKind.SIDE_SINGLE, "站台：单侧"],
		[NetworkGraph.StationKind.SIDE_DUAL, "站台：对称双侧"],
		[NetworkGraph.StationKind.ISLAND, "站台：中央岛式"],
	]:
		var sk_val := int(sk_pair[0])
		var skb := _make_btn(str(sk_pair[1]), func():
			_build_station_kind = sk_val
			_build_tool = BuildTool.STATION
			_path_start_node = -1
			_refresh_build_buttons()
		)
		skb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sk_row.add_child(skb)
		_station_kind_btns.append(skb)

	var rename_row := HBoxContainer.new()
	rename_row.add_theme_constant_override("separation", 6)
	b_vbox.add_child(rename_row)
	_edit_station_name = LineEdit.new()
	_edit_station_name.placeholder_text = "点击已有车站或新建后可在此修改站名"
	_edit_station_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_station_name.text_submitted.connect(func(_txt: String): _apply_station_rename())
	rename_row.add_child(_edit_station_name)
	rename_row.add_child(_make_btn("修改站名", func(): _apply_station_rename()))

	var s_lbl := Label.new()
	s_lbl.text = "② 选择新铺轨道道床类型（运行中不可更改）："
	b_vbox.add_child(s_lbl)

	_bed_btns.clear()
	for bi in range(BED_STYLE_NAMES.size()):
		var b_copy := bi
		var bb := _make_btn("铺装：" + BED_STYLE_NAMES[bi], func():
			_build_bed_style = b_copy
			_refresh_build_buttons()
		)
		b_vbox.add_child(bb)
		_bed_btns.append(bb)

	_lbl_build_hint = Label.new()
	_lbl_build_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_build_hint.custom_minimum_size = Vector2(330, 44)
	_lbl_build_hint.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90))
	_lbl_build_hint.text = "提示：按下触摸板/左键拖动可平移地图，滚轮缩放，单击施工。"
	b_vbox.add_child(_lbl_build_hint)

	var util_row := HBoxContainer.new()
	util_row.add_theme_constant_override("separation", 6)
	b_vbox.add_child(util_row)
	util_row.add_child(_make_btn("存档管理(F5)", func(): _open_slot_modal(_current_map_key, false)))
	util_row.add_child(_make_btn("清空全部重建", func():
		_graph.clear_player_network()
		_rebuild_tracks_and_operations(false)
		_mark_modified_and_quick_save()
		_show_toast("已清空全城轨道与线路，可从零自由建设！")
	))
	_refresh_build_buttons()

	# 3. PLAN MODE PANEL (Left Side)
	_plan_panel = _make_panel(Color(0.07, 0.09, 0.12, 0.90))
	_plan_panel.position = Vector2(16, 72)
	_plan_panel.custom_minimum_size = Vector2(395, 510)
	_hud_layer_ctrl.add_child(_plan_panel)

	var p_vbox := VBoxContainer.new()
	p_vbox.add_theme_constant_override("separation", 7)
	_plan_panel.add_child(p_vbox)

	var p_title := Label.new()
	p_title.text = "公交化电车线路规划与选车配车"
	p_title.add_theme_font_size_override("font_size", 15)
	p_title.add_theme_color_override("font_color", Color(0.48, 0.84, 0.98))
	p_vbox.add_child(p_title)

	_lbl_draft_stops = Label.new()
	_lbl_draft_stops.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_draft_stops.custom_minimum_size = Vector2(365, 58)
	_lbl_draft_stops.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	p_vbox.add_child(_lbl_draft_stops)

	var draft_btns := HBoxContainer.new()
	draft_btns.add_theme_constant_override("separation", 6)
	p_vbox.add_child(draft_btns)
	draft_btns.add_child(_make_btn("撤销上一站 (Bksp)", func():
		if not _draft_station_ids.is_empty():
			_draft_station_ids.pop_back()
			_refresh_plan_ui()
	))
	draft_btns.add_child(_make_btn("清空选站", func():
		_draft_station_ids.clear()
		_refresh_plan_ui()
	))

	var flt_row := HBoxContainer.new()
	flt_row.add_theme_constant_override("separation", 6)
	p_vbox.add_child(flt_row)
	flt_row.add_child(_make_btn("全部车型(17)", func(): _set_era_filter("all")))
	flt_row.add_child(_make_btn("现代电车(8)", func(): _set_era_filter("modern")))
	flt_row.add_child(_make_btn("古典老车(6)", func(): _set_era_filter("vintage")))
	flt_row.add_child(_make_btn("单轨(3)", func(): _set_era_filter("monorail")))

	var car_sel_row := HBoxContainer.new()
	car_sel_row.add_theme_constant_override("separation", 6)
	p_vbox.add_child(car_sel_row)
	car_sel_row.add_child(_make_btn("◀ 上一款", func(): _step_plan_model(-1)))
	car_sel_row.add_child(_make_btn("下一款 ▶", func(): _step_plan_model(1)))

	_lbl_model_card = Label.new()
	_lbl_model_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_model_card.add_theme_color_override("font_color", Color(0.96, 0.90, 0.72))
	p_vbox.add_child(_lbl_model_card)

	var cfg_row := HBoxContainer.new()
	cfg_row.add_theme_constant_override("separation", 6)
	p_vbox.add_child(cfg_row)
	cfg_row.add_child(_make_btn("配车 -", func(): _plan_fleet_count = maxi(1, _plan_fleet_count - 1); _refresh_plan_ui()))
	cfg_row.add_child(_make_btn("配车 +", func(): _plan_fleet_count = mini(8, _plan_fleet_count + 1); _refresh_plan_ui()))
	cfg_row.add_child(_make_btn("编组 -", func(): _plan_sections = maxi(1, _plan_sections - 1); _refresh_plan_ui()))
	cfg_row.add_child(_make_btn("编组 +", func(): _plan_sections = mini(2, _plan_sections + 1); _refresh_plan_ui()))

	_lbl_fleet_cfg = Label.new()
	p_vbox.add_child(_lbl_fleet_cfg)

	p_vbox.add_child(_make_btn("✓ 确认开通此线路", func(): _commit_draft_line()))

	p_vbox.add_child(HSeparator.new())
	var exist_lbl := Label.new()
	exist_lbl.text = "已开通运营线路："
	p_vbox.add_child(exist_lbl)

	_lines_list_vbox = VBoxContainer.new()
	_lines_list_vbox.add_theme_constant_override("separation", 4)
	p_vbox.add_child(_lines_list_vbox)

	# 4. RUN & DRIVE MODE PANELS
	_run_top_panel = _make_panel(Color(0.07, 0.09, 0.12, 0.88))
	_run_top_panel.position = Vector2(16, 72)
	_run_top_panel.custom_minimum_size = Vector2(475, 156)
	_hud_layer_ctrl.add_child(_run_top_panel)

	var rt_vbox := VBoxContainer.new()
	rt_vbox.add_theme_constant_override("separation", 4)
	_run_top_panel.add_child(rt_vbox)

	_lbl_net_stats = Label.new()
	_lbl_net_stats.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	rt_vbox.add_child(_lbl_net_stats)

	_lbl_tram_info = Label.new()
	_lbl_tram_info.add_theme_color_override("font_color", Color(0.96, 0.88, 0.66))
	rt_vbox.add_child(_lbl_tram_info)

	_lbl_station_next = Label.new()
	_lbl_station_next.add_theme_color_override("font_color", Color(0.46, 0.90, 0.70))
	rt_vbox.add_child(_lbl_station_next)

	_lbl_hazard_hint = Label.new()
	_lbl_hazard_hint.add_theme_color_override("font_color", Color(0.98, 0.78, 0.36))
	rt_vbox.add_child(_lbl_hazard_hint)

	var rt_btns := HBoxContainer.new()
	rt_btns.add_theme_constant_override("separation", 6)
	rt_vbox.add_child(rt_btns)
	rt_btns.add_child(_make_btn("◀ 上一线路", func(): _switch_line(-1)))
	rt_btns.add_child(_make_btn("下一线路(L) ▶", func(): _switch_line(1)))
	rt_btns.add_child(_make_btn("◀ 本线上一列", func(): _transit_sim.cycle_active_tram(-1)))
	rt_btns.add_child(_make_btn("本线下一列(F) ▶", func(): _transit_sim.cycle_active_tram(1)))
	_btn_pax_rate = _make_btn("客流: 3档 标准 (P)", func():
		var lvl := _pax_sim.cycle_spawn_level()
		_btn_pax_rate.text = "客流: %s (P)" % PassengerSim.SPAWN_LEVEL_NAMES[lvl]
		_mark_modified_and_quick_save()
	)
	rt_btns.add_child(_btn_pax_rate)

	_cam_panel = _make_panel(Color(0.07, 0.09, 0.12, 0.88))
	_cam_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cam_panel.position = Vector2(-478, 72)
	_hud_layer_ctrl.add_child(_cam_panel)

	var cam_vbox := VBoxContainer.new()
	cam_vbox.add_theme_constant_override("separation", 4)
	_cam_panel.add_child(cam_vbox)

	var cam_hbox := HBoxContainer.new()
	cam_hbox.add_theme_constant_override("separation", 5)
	cam_vbox.add_child(cam_hbox)
	cam_hbox.add_child(_make_btn("1 驾驶室", func(): _set_cam_mode(CamMode.CAB)))
	cam_hbox.add_child(_make_btn("2 追尾外景", func(): _set_cam_mode(CamMode.CHASE)))
	cam_hbox.add_child(_make_btn("3 车厢内部", func(): _set_cam_mode(CamMode.INTERIOR)))
	cam_hbox.add_child(_make_btn("4 车门上下客", func(): _set_cam_mode(CamMode.DOOR_ACTION)))
	cam_hbox.add_child(_make_btn("5 鸟瞰全局", func(): _set_cam_mode(CamMode.BIRD)))

	var cam_hint := Label.new()
	cam_hint.text = "↑↓←→ 方向键移动/旋转视角 · W/S 牵引与制动 · O 开关车门 · G 扳道岔(单轨)"
	cam_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cam_hint.add_theme_font_size_override("font_size", 12)
	cam_hint.add_theme_color_override("font_color", Color(0.75, 0.82, 0.88))
	cam_vbox.add_child(cam_hint)

	# Bottom-Left Driver's Console
	_drv_panel = _make_panel(Color(0.07, 0.09, 0.12, 0.90))
	_drv_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_drv_panel.position = Vector2(16, -172)
	_drv_panel.custom_minimum_size = Vector2(515, 156)
	_hud_layer_ctrl.add_child(_drv_panel)

	var drv_vbox := VBoxContainer.new()
	drv_vbox.add_theme_constant_override("separation", 5)
	_drv_panel.add_child(drv_vbox)

	var spd_row := HBoxContainer.new()
	spd_row.add_theme_constant_override("separation", 14)
	drv_vbox.add_child(spd_row)

	_lbl_speed = Label.new()
	_lbl_speed.add_theme_font_size_override("font_size", 27)
	spd_row.add_child(_lbl_speed)

	_lbl_speed_limit = Label.new()
	_lbl_speed_limit.add_theme_font_size_override("font_size", 15)
	spd_row.add_child(_lbl_speed_limit)

	_lbl_notch = Label.new()
	_lbl_notch.add_theme_font_size_override("font_size", 18)
	spd_row.add_child(_lbl_notch)

	_lbl_drv_status = Label.new()
	_lbl_drv_status.add_theme_color_override("font_color", Color(0.80, 0.84, 0.88))
	drv_vbox.add_child(_lbl_drv_status)

	var bars_row := HBoxContainer.new()
	bars_row.add_theme_constant_override("separation", 4)
	drv_vbox.add_child(bars_row)
	_notch_bars.clear()
	for i in range(TransitSim.NOTCH_LABELS.size()):
		var slot := VBoxContainer.new()
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(37, 11)
		slot.add_child(bar)
		var nl := Label.new()
		nl.text = TransitSim.NOTCH_LABELS[i]
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.add_theme_font_size_override("font_size", 11)
		slot.add_child(nl)
		bars_row.add_child(slot)
		_notch_bars.append(bar)

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	drv_vbox.add_child(act_row)
	_btn_doors = _make_btn("开关车门 (O/Space)", func(): _toggle_doors_with_safety_check())
	act_row.add_child(_btn_doors)
	act_row.add_child(_make_btn("叮叮铜铃警示 (H)", func(): _ring_tram_bell()))
	_btn_drive_mode = _make_btn("切换手动驾驶 (Q)", func(): _transit_sim.manual_drive = not _transit_sim.manual_drive)
	act_row.add_child(_btn_drive_mode)
	act_row.add_child(_make_btn("换端折返 (R)", func(): _do_cab_change()))
	act_row.add_child(_make_btn("扳道岔 (G)", func(): _do_throw_switch()))

	# 5. HOME SCREEN OVERLAY (Map Selection + Progress Summary + Actions)
	_build_home_screen_ui(master_root)

	# 6. MULTI-SLOT SAVE/LOAD MANAGER MODAL (10 Manual + 5 Rotating Auto-saves)
	_build_slot_modal_ui(master_root)
	_build_audio_modal_ui(master_root)
	_build_stats_modal_ui(master_root)

	# 7. ACCIDENT / DERAILMENT GAME OVER MODAL (Forces Map Restart!)
	_build_gameover_modal_ui(master_root)


func _build_home_screen_ui(parent: Control) -> void:
	_home_overlay = Control.new()
	_home_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_home_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(_home_overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.05, 0.08, 0.62)
	_home_overlay.add_child(backdrop)

	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_home_overlay.add_child(center_wrap)

	var main_card := _make_panel(Color(0.06, 0.08, 0.12, 0.94))
	main_card.custom_minimum_size = Vector2(820, 470)
	center_wrap.add_child(main_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	main_card.add_child(vbox)

	var title := Label.new()
	title.text = "3D 有轨电车建设与模拟驾驶"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "选择城市地图开始规划 · 支持独立工字草皮/柏油等多路权铺轨 · 14款现代与古典电车 · 10槽手动+5槽自动存档"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.72, 0.80, 0.88))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 16)
	vbox.add_child(cards_row)

	for mkey: String in MAP_ORDER:
		var preset: Dictionary = MAP_PRESETS[mkey]
		var card := _make_panel(Color(0.08, 0.11, 0.16, 0.90))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(380, 245)
		cards_row.add_child(card)
		_home_card_panels[mkey] = card

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)

		var head_row := HBoxContainer.new()
		head_row.add_theme_constant_override("separation", 8)
		cv.add_child(head_row)

		var idx_lbl := Label.new()
		idx_lbl.text = str(preset["index"])
		idx_lbl.add_theme_font_size_override("font_size", 22)
		idx_lbl.add_theme_color_override("font_color", Color(0.42, 0.88, 0.68))
		head_row.add_child(idx_lbl)

		var t_lbl := Label.new()
		t_lbl.text = str(preset["title"])
		t_lbl.add_theme_font_size_override("font_size", 20)
		t_lbl.add_theme_color_override("font_color", Color(0.96, 0.97, 0.99))
		head_row.add_child(t_lbl)

		var sub_lbl := Label.new()
		sub_lbl.text = str(preset["subtitle"])
		sub_lbl.add_theme_color_override("font_color", Color(0.62, 0.78, 0.94))
		cv.add_child(sub_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = str(preset["desc"])
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(340, 46)
		desc_lbl.add_theme_color_override("font_color", Color(0.80, 0.84, 0.88))
		cv.add_child(desc_lbl)

		cv.add_child(HSeparator.new())

		var badge_lbl := Label.new()
		badge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		badge_lbl.custom_minimum_size = Vector2(340, 44)
		cv.add_child(badge_lbl)
		_home_card_badges[mkey] = badge_lbl

		var m_copy := mkey
		var sel_btn := _make_btn("选择此地图", func(): _select_home_map_card(m_copy))
		cv.add_child(sel_btn)

	vbox.add_child(HSeparator.new())

	var act_bar := HBoxContainer.new()
	act_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	act_bar.add_theme_constant_override("separation", 12)
	vbox.add_child(act_bar)

	_btn_home_primary = _make_btn("▶ 开始建设", func(): _start_map_continue_or_new())
	_btn_home_primary.custom_minimum_size = Vector2(210, 38)
	_btn_home_primary.modulate = Color(0.62, 1.0, 0.80)
	act_bar.add_child(_btn_home_primary)

	_btn_home_demo = _make_btn("示例线网试驾", func(): _start_map_demo_network())
	_btn_home_demo.custom_minimum_size = Vector2(145, 38)
	act_bar.add_child(_btn_home_demo)

	_btn_home_slots = _make_btn("存档管理 (10槽)", func(): _open_slot_modal(_selected_home_map, false))
	_btn_home_slots.custom_minimum_size = Vector2(150, 38)
	act_bar.add_child(_btn_home_slots)

	_btn_home_reset = _make_btn("重新开始", func(): _handle_home_reset_button())
	_btn_home_reset.custom_minimum_size = Vector2(125, 38)
	act_bar.add_child(_btn_home_reset)


func _build_slot_modal_ui(parent: Control) -> void:
	_slot_modal = Control.new()
	_slot_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_slot_modal.visible = false
	parent.add_child(_slot_modal)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	_slot_modal.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_modal.add_child(center)

	var box := _make_panel(Color(0.07, 0.09, 0.13, 0.97))
	box.custom_minimum_size = Vector2(740, 510)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	_lbl_slot_title = Label.new()
	_lbl_slot_title.text = "存档管理"
	_lbl_slot_title.add_theme_font_size_override("font_size", 18)
	_lbl_slot_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_slot_title.add_theme_color_override("font_color", Color(0.52, 0.90, 0.74))
	top_row.add_child(_lbl_slot_title)

	top_row.add_child(_make_btn("✕ 关闭 (Esc)", func():
		_slot_modal.visible = false
		if _in_home_menu:
			_refresh_home_screen_ui()
	))

	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tabs_row)

	_btn_tab_manual = _make_btn("建设规划档 (10 · 每档含3运行档)", func():
		_slot_tab_mode = 0
		_refresh_slot_modal_ui()
	)
	_btn_tab_auto = _make_btn("轮换自动档 (5)", func():
		_slot_tab_mode = 1
		_refresh_slot_modal_ui()
	)
	tabs_row.add_child(_btn_tab_manual)
	tabs_row.add_child(_btn_tab_auto)

	_slot_name_row = HBoxContainer.new()
	_slot_name_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_slot_name_row)

	var nm_lbl := Label.new()
	nm_lbl.text = "存档备注名称："
	_slot_name_row.add_child(nm_lbl)

	_edit_slot_name = LineEdit.new()
	_edit_slot_name.placeholder_text = "输入自定义存档名（如：西雅图双环线方案A），留空自动命名"
	_edit_slot_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_name_row.add_child(_edit_slot_name)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 365)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_slot_list_vbox = VBoxContainer.new()
	_slot_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_slot_list_vbox)


func _save_run_progress_to_slot(plan_idx: int, sub_idx: int = 0) -> void:
	if _transit_sim.trams.is_empty():
		_show_toast("当前没有在线运行的电车，请先规划线路并进入运行模式！")
		return
	var pidx := clampi(plan_idx, 0, SaveManager.MANUAL_SLOT_COUNT - 1)
	var sidx := clampi(sub_idx, 0, SaveManager.RUN_PER_PLAN_COUNT - 1)
	_active_plan_slot_idx = pidx
	if SaveManager.load_slot(_current_map_key, false, pidx).is_empty():
		var bp_payload := _build_current_save_payload("规划存档 %02d" % (pidx + 1))
		SaveManager.save_manual_slot(_current_map_key, pidx, "规划存档 %02d" % (pidx + 1), bp_payload)
		SaveManager.save_current(_current_map_key, bp_payload)
	var run_payload := {
		"plan_slot_idx": pidx,
		"sub_idx": sidx,
		"time_hours": snappedf(_time_hours, 0.05),
		"pax_spawn_level": _pax_sim.spawn_level,
		"total_delivered": _pax_sim.total_delivered,
		"transit": _transit_sim.export_run_state(),
	}
	if SaveManager.save_run_slot(_current_map_key, pidx, run_payload, sidx):
		_is_demo_readonly = false
		_show_toast("✓ 已保存至规划 %02d · 运行档 %d（累计送达 %d 人）！" % [pidx + 1, sidx + 1, _pax_sim.total_delivered])


func _toggle_stats_modal() -> void:
	if _stats_modal == null:
		return
	_stats_modal.visible = not _stats_modal.visible
	if _stats_modal.visible:
		_stats_refresh_accum = 0.0
		_refresh_stats_modal_ui()


func _build_stats_modal_ui(parent: Control) -> void:
	_stats_modal = ColorRect.new()
	_stats_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_modal.color = Color(0.02, 0.03, 0.05, 0.68)
	_stats_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_modal.visible = false
	parent.add_child(_stats_modal)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_modal.add_child(center)

	var box := _make_panel(Color(0.06, 0.09, 0.13, 0.97))
	box.custom_minimum_size = Vector2(820, 540)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	var title := Label.new()
	title.text = "线路管理 · 运营数据看板"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.48, 0.90, 0.74))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	top_row.add_child(_make_btn("刷新", func(): _refresh_stats_modal_ui()))
	top_row.add_child(_make_btn("✕ 关闭 (T/Esc)", func(): _stats_modal.visible = false))

	var sum_pc := _make_panel(Color(0.10, 0.14, 0.20, 0.95))
	vbox.add_child(sum_pc)
	_stats_summary_lbl = Label.new()
	_stats_summary_lbl.add_theme_font_size_override("font_size", 13)
	_stats_summary_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	sum_pc.add_child(_stats_summary_lbl)

	var l_hdr := Label.new()
	l_hdr.text = "各线路运营指标"
	l_hdr.add_theme_font_size_override("font_size", 14)
	l_hdr.add_theme_color_override("font_color", Color(0.68, 0.86, 1.0))
	vbox.add_child(l_hdr)

	var l_scroll := ScrollContainer.new()
	l_scroll.custom_minimum_size = Vector2(780, 175)
	vbox.add_child(l_scroll)

	_stats_lines_vbox = VBoxContainer.new()
	_stats_lines_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_lines_vbox.add_theme_constant_override("separation", 4)
	l_scroll.add_child(_stats_lines_vbox)

	vbox.add_child(HSeparator.new())

	var s_hdr := Label.new()
	s_hdr.text = "各站客流统计（按当前候车人数降序）"
	s_hdr.add_theme_font_size_override("font_size", 14)
	s_hdr.add_theme_color_override("font_color", Color(0.98, 0.86, 0.56))
	vbox.add_child(s_hdr)

	var s_scroll := ScrollContainer.new()
	s_scroll.custom_minimum_size = Vector2(780, 195)
	s_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(s_scroll)

	_stats_stations_vbox = VBoxContainer.new()
	_stats_stations_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_stations_vbox.add_theme_constant_override("separation", 4)
	s_scroll.add_child(_stats_stations_vbox)


func _make_stat_row(cols: Array[String], widths: Array[int], text_color: Color, bg_color: Color) -> PanelContainer:
	var pc := _make_panel(bg_color)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	pc.add_child(hb)
	for i in range(cols.size()):
		var lbl := Label.new()
		lbl.text = cols[i]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", text_color)
		if i < widths.size() and widths[i] > 0:
			lbl.custom_minimum_size = Vector2(widths[i], 0)
		else:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(lbl)
	return pc


func _refresh_stats_modal_ui() -> void:
	if _stats_modal == null or not _stats_modal.visible:
		return

	var op_sec := int(_transit_sim.operating_seconds)
	var op_min := op_sec / 60
	var op_rem := op_sec % 60
	var total_onboard := 0
	for tr_var in _transit_sim.trams:
		var tr: Dictionary = tr_var
		total_onboard += (tr.get("pax_dests", []) as Array).size()
	var total_waiting := _pax_sim.get_total_waiting()
	_stats_summary_lbl.text = "运营时长 %02d:%02d  ·  在线线路 %d 条  ·  在线电车 %d 辆  ·  在车 %d 人  ·  候车 %d 人  ·  累计上车 %d 人  ·  累计送达 %d 人" % [
		op_min,
		op_rem,
		_graph.lines.size(),
		_transit_sim.trams.size(),
		total_onboard,
		total_waiting,
		_pax_sim.total_boarded,
		_pax_sim.total_delivered,
	]

	for c in _stats_lines_vbox.get_children():
		c.queue_free()
	for c in _stats_stations_vbox.get_children():
		c.queue_free()

	var l_widths: Array[int] = [92, 165, 52, 62, 82, 64, 64, 62, 72]
	_stats_lines_vbox.add_child(_make_stat_row(
		["线路", "车型 / 编组", "配车", "总定员", "运营均速", "累计上车", "累计送达", "当前在车", "满载率"],
		l_widths,
		Color(0.68, 0.80, 0.92),
		Color(0.09, 0.12, 0.18, 0.96)
	))

	if _graph.lines.is_empty():
		_stats_lines_vbox.add_child(_make_stat_row(
			["暂无线路数据，请先在【规划线路】模式中创建至少一条电车线路。"],
			[0],
			Color(0.62, 0.68, 0.74),
			Color(0.08, 0.10, 0.14, 0.85)
		))
	else:
		var op_hrs := maxf(_transit_sim.operating_seconds / 3600.0, 1.0 / 3600.0)
		var sorted_lids := _graph.lines.keys()
		sorted_lids.sort()
		for lid_var in sorted_lids:
			var lid := int(lid_var)
			var ln: Dictionary = _graph.lines[lid_var]
			var tr_cnt := 0
			var cap_sum := 0
			var ob_sum := 0
			var model_label := str(ln.get("model_key", "Tram"))
			var sec_cnt := clampi(int(ln.get("sections", 2)), 1, 2)
			for tr_var in _transit_sim.trams:
				var tr: Dictionary = tr_var
				if int(tr.get("line_id", -1)) == lid:
					tr_cnt += 1
					cap_sum += int(tr.get("capacity", 0))
					ob_sum += (tr.get("pax_dests", []) as Array).size()
					var sp: Dictionary = tr.get("spec", {})
					if not sp.is_empty():
						model_label = str(sp.get("name", model_label))
			var dist_km := float(_transit_sim.line_dist_m.get(lid, 0.0)) / 1000.0
			var avg_kmh := (dist_km / maxf(float(maxi(1, tr_cnt)) * op_hrs, 0.0001)) if _transit_sim.operating_seconds > 1.0 else 0.0
			var boarded := int(_pax_sim.line_boarded.get(lid, 0))
			var delivered := int(_pax_sim.line_delivered.get(lid, 0))
			var load_pct := (float(ob_sum) / float(maxi(1, cap_sum)) * 100.0) if cap_sum > 0 else 0.0
			var l_col: Color = ln.get("color", Color(0.85, 0.92, 1.0))
			_stats_lines_vbox.add_child(_make_stat_row(
				[
					str(ln.get("name", "线路 %d" % lid)),
					"%s · %d节" % [model_label, sec_cnt],
					"%d 辆" % tr_cnt,
					"%d 人" % cap_sum,
					"%.1f km/h" % avg_kmh,
					"%d" % boarded,
					"%d" % delivered,
					"%d" % ob_sum,
					"%.0f%%" % load_pct,
				],
				l_widths,
				l_col.lerp(Color.WHITE, 0.55),
				Color(0.10, 0.13, 0.19, 0.90)
			))

	var s_widths: Array[int] = [0, 95, 95, 95, 90]
	_stats_stations_vbox.add_child(_make_stat_row(
		["车站名称", "当前候车", "累计上车", "累计下车", "站台状态"],
		s_widths,
		Color(0.95, 0.84, 0.58),
		Color(0.09, 0.12, 0.18, 0.96)
	))

	var st_rows: Array[Dictionary] = []
	for sid_var in _graph.stations.keys():
		var sid := int(sid_var)
		var st: Dictionary = _graph.stations[sid]
		var waiting := _pax_sim.get_waiting_count(sid)
		var st_b := int(_pax_sim.station_boarded.get(sid, 0))
		var st_a := int(_pax_sim.station_alighted.get(sid, 0))
		st_rows.append({
			"name": str(st.get("name", "车站 %d" % sid)),
			"waiting": waiting,
			"boarded": st_b,
			"alighted": st_a,
		})
	st_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["waiting"]) != int(b["waiting"]):
			return int(a["waiting"]) > int(b["waiting"])
		return int(a["boarded"]) > int(b["boarded"])
	)
	if st_rows.is_empty():
		_stats_stations_vbox.add_child(_make_stat_row(
			["暂无车站数据"],
			[0],
			Color(0.62, 0.68, 0.74),
			Color(0.08, 0.10, 0.14, 0.85)
		))
	else:
		for sr: Dictionary in st_rows:
			var w := int(sr["waiting"])
			var status_txt := "宽松"
			var st_col := Color(0.86, 0.94, 0.90)
			if w >= 60:
				status_txt = "拥挤"
				st_col = Color(1.0, 0.56, 0.48)
			elif w >= 25:
				status_txt = "较忙"
				st_col = Color(0.98, 0.84, 0.46)
			_stats_stations_vbox.add_child(_make_stat_row(
				[str(sr["name"]), "%d 人" % w, "%d 人" % int(sr["boarded"]), "%d 人" % int(sr["alighted"]), status_txt],
				s_widths,
				st_col,
				Color(0.10, 0.13, 0.18, 0.88)
			))


func _toggle_audio_modal() -> void:
	if _audio_modal != null:
		_audio_modal.visible = not _audio_modal.visible


# Platform passenger exchange status while docked: waiting / alighting counts and a progress bar,
# so a manual driver knows when everyone is on board and the doors can be closed.
func _boarding_status_text(tr: Dictionary, st_info: Dictionary) -> String:
	var sid := int(st_info.get("station_id", -1))
	var st_name := str(st_info.get("name", ""))
	var onboard: Array = tr["pax_dests"]
	var cap := int(tr["capacity"])
	var alight_left := onboard.count(sid)
	var pending := int(tr.get("pending_boarders", 0))
	var waiting := _pax_sim.get_waiting_count(sid)
	var room := maxi(0, cap - onboard.size() - pending)
	var board_left := mini(waiting, room)
	var doors_open := bool(tr.get("doors_target_open", false)) and float(tr.get("door_ratio", 0.0)) > 0.5
	if not doors_open:
		if float(tr.get("door_ratio", 0.0)) < 0.02:
			tr.erase("xfer_snap")
		if bool(tr.get("doors_target_open", false)):
			return "● 已停靠：%s · 车门正在打开…" % st_name
		return "● 已停靠：%s · 车门正在关闭…" % st_name
	var remaining := alight_left + board_left + pending
	var snap: Dictionary = tr.get("xfer_snap", {})
	if snap.is_empty() or int(snap.get("sid", -1)) != sid:
		snap = {"sid": sid, "total": maxi(1, remaining), "done_toast": false}
		tr["xfer_snap"] = snap
	snap["total"] = maxi(int(snap["total"]), remaining)
	var prog := 1.0 - float(remaining) / float(maxi(1, int(snap["total"])))
	var cells := 10
	var filled := int(round(prog * float(cells)))
	var bar := "▰".repeat(filled) + "▱".repeat(cells - filled)
	if remaining == 0:
		if _transit_sim.manual_drive and not bool(snap["done_toast"]):
			snap["done_toast"] = true
			_show_toast("✅ %s 上下客完毕，可以关门 (O) 出发" % st_name)
		var full_note := "（车厢已满，站台还有 %d 人等下一班）" % waiting if waiting > 0 and room == 0 else ""
		return "✅ %s 上下客完毕 %s 100%%，可关门 (O) 出发%s" % [st_name, bar, full_note]
	var open_n := int(tr.get("open_doorways", 0))
	var tot_n := maxi(1, int(tr.get("total_doorways", 1)))
	var door_note := "" if open_n >= tot_n else " · ⚠ 停靠错位，仅 %d/%d 个车门对准站台，上下客较慢" % [open_n, tot_n]
	return "⏳ %s 上下客中 %s %d%% · 下车剩 %d · 上车剩 %d（站台 %d，正在上车 %d）%s" % [
		st_name, bar, int(round(prog * 100.0)), alight_left, board_left, waiting, pending, door_note]


func _update_station_announcements() -> void:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	var st_info := _transit_sim.find_next_stop_info(tr)
	var sid := int(st_info.get("station_id", -1))
	var dist := float(st_info.get("dist", 999.0))
	var st_name := str(st_info.get("name", ""))
	if sid < 0 or st_name.is_empty():
		return

	var door_open_now := bool(tr.get("doors_target_open", false)) and float(tr.get("door_ratio", 0.0)) > 0.18
	if door_open_now and not _last_ann_door_open:
		_last_ann_door_open = true
		var dock := _transit_sim.get_dock_info_for_tram(tr, _graph)
		var side_zh := "站台侧"
		var side_en := "platform side"
		var secs: Array = tr["tram_info"]["sections"]
		if bool(dock.get("has_station", false)) and not secs.is_empty():
			var s0 := secs[0] as Node3D
			var st_fwd := (dock["st_fwd"] as Vector3).normalized()
			var st_side := float(dock["st_side"])
			var plat_dir := (dock["st_pos"] as Vector3 - s0.global_position).normalized() if int(st_side) == 0 else (st_fwd.cross(Vector3.UP).normalized() * st_side)
			# Driver's right-hand side in the direction of travel. After a cab change the lead car runs
			# reversed (rear cab active), so its local +X is then the driver's LEFT.
			var cab_sign := -1.0 if int(tr["tram_info"].get("active_end", 0)) == 1 else 1.0
			var drv_right := s0.global_transform.basis.x * cab_sign
			var is_right := drv_right.dot(plat_dir) >= 0.0
			side_zh = "右侧" if is_right else "左侧"
			side_en = "right" if is_right else "left"
		_sound.announce_station("%s 到了，请从%s车门下车。" % [st_name, side_zh], "Arriving at %s. Doors open on the %s." % [st_name, side_en])
		_show_toast("📢 报站：%s 到了，请从%s车门下车" % [st_name, side_zh])
	elif (not bool(tr.get("doors_target_open", false))) and _last_ann_door_open:
		_last_ann_door_open = false
		_sound.announce_station("车门即将关闭，请站稳扶好。", "Doors closing. Please hold on.")
	elif dist <= 48.0 and dist > 7.5 and sid != _last_ann_approach_sid and float(tr.get("speed_mps", 0.0)) > 1.2:
		_last_ann_approach_sid = sid
		_sound.announce_station("下一站，%s，请准备下车。" % st_name, "Next stop, %s." % st_name)
		_show_toast("📢 报站：下一站，%s" % st_name)


func _build_audio_modal_ui(parent: Control) -> void:
	_audio_modal = ColorRect.new()
	_audio_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_audio_modal.color = Color(0.02, 0.03, 0.05, 0.58)
	_audio_modal.visible = false
	parent.add_child(_audio_modal)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_audio_modal.add_child(center)

	var card := _make_panel(Color(0.08, 0.11, 0.16, 0.97))
	card.custom_minimum_size = Vector2(470, 368)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "音频与语音报站设置"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.50, 0.90, 0.98))
	header.add_child(title)
	header.add_child(_make_btn("关闭", func(): _audio_modal.visible = false))

	# Master Volume
	var m_row := HBoxContainer.new()
	m_row.add_theme_constant_override("separation", 10)
	vbox.add_child(m_row)
	var m_lbl := Label.new()
	m_lbl.text = "总音量：85%"
	m_lbl.custom_minimum_size = Vector2(124, 24)
	m_row.add_child(m_lbl)
	var m_slider := HSlider.new()
	m_slider.min_value = 0.0; m_slider.max_value = 100.0; m_slider.step = 1.0; m_slider.value = 85.0
	m_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_slider.value_changed.connect(func(v: float):
		_sound.master_volume = v / 100.0
		m_lbl.text = "总音量：%d%%" % int(round(v))
	)
	m_row.add_child(m_slider)

	# Tram SFX Volume
	var s_row := HBoxContainer.new()
	s_row.add_theme_constant_override("separation", 10)
	vbox.add_child(s_row)
	var s_lbl := Label.new()
	s_lbl.text = "电车音效：85%"
	s_lbl.custom_minimum_size = Vector2(124, 24)
	s_row.add_child(s_lbl)
	var s_slider := HSlider.new()
	s_slider.min_value = 0.0; s_slider.max_value = 100.0; s_slider.step = 1.0; s_slider.value = 85.0
	s_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_slider.value_changed.connect(func(v: float):
		_sound.sfx_volume = v / 100.0
		s_lbl.text = "电车音效：%d%%" % int(round(v))
	)
	s_row.add_child(s_slider)

	# Station Announcement (TTS) Volume
	var t_row := HBoxContainer.new()
	t_row.add_theme_constant_override("separation", 10)
	vbox.add_child(t_row)
	var t_lbl := Label.new()
	t_lbl.text = "报站音量：85%"
	t_lbl.custom_minimum_size = Vector2(124, 24)
	t_row.add_child(t_lbl)
	var t_slider := HSlider.new()
	t_slider.min_value = 0.0; t_slider.max_value = 100.0; t_slider.step = 1.0; t_slider.value = 85.0
	t_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_slider.value_changed.connect(func(v: float):
		_sound.tts_volume = v / 100.0
		t_lbl.text = "报站音量：%d%%" % int(round(v))
	)
	t_row.add_child(t_slider)

	var toggle_row := HBoxContainer.new()
	toggle_row.add_theme_constant_override("separation", 8)
	vbox.add_child(toggle_row)
	var btn_sfx_t := _make_btn("电车音效：已开启", func(): pass)
	btn_sfx_t.pressed.connect(func():
		_sound.sfx_enabled = not _sound.sfx_enabled
		btn_sfx_t.text = "电车音效：已开启" if _sound.sfx_enabled else "电车音效：已关闭"
	)
	btn_sfx_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_row.add_child(btn_sfx_t)

	var btn_tts_t := _make_btn("自动报站：已开启", func(): pass)
	btn_tts_t.pressed.connect(func():
		_sound.tts_enabled = not _sound.tts_enabled
		if not _sound.tts_enabled and DisplayServer.get_name() != "headless":
			DisplayServer.tts_stop()
		btn_tts_t.text = "自动报站：已开启" if _sound.tts_enabled else "自动报站：已关闭"
	)
	btn_tts_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_row.add_child(btn_tts_t)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vbox.add_child(lang_row)
	var lang_names := ["中英双语", "仅中文", "仅英语"]
	var btn_biling := _make_btn("报站语言：中英双语", func(): pass)
	btn_biling.pressed.connect(func():
		_sound.tts_lang_mode = (_sound.tts_lang_mode + 1) % 3
		btn_biling.text = "报站语言：%s" % lang_names[_sound.tts_lang_mode]
	)
	btn_biling.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_row.add_child(btn_biling)
	lang_row.add_child(_make_btn("试听报站", func():
		var was_sil := _sound._menu_silenced
		_sound._menu_silenced = false
		_sound.announce_station("下一站，西湖中心站，请准备下车。", "Next stop, Westlake Center.")
		_sound._menu_silenced = was_sil
	))

	var note_lbl := Label.new()
	note_lbl.text = "提示：退出地图返回主页或在建设/规划模式下，电车音效与语音报站将自动静音停止。"
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.add_theme_font_size_override("font_size", 12)
	note_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
	vbox.add_child(note_lbl)


func _build_gameover_modal_ui(parent: Control) -> void:
	_gameover_modal = Control.new()
	_gameover_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameover_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_gameover_modal.visible = false
	parent.add_child(_gameover_modal)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.02, 0.02, 0.42)
	_gameover_modal.add_child(dim)

	var card := _make_panel(Color(0.11, 0.06, 0.07, 0.95))
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card.position = Vector2(-310, -230)
	card.custom_minimum_size = Vector2(620, 195)
	_gameover_modal.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	_lbl_gameover_title = Label.new()
	_lbl_gameover_title.text = "【重大安全事故 · 本局游戏结束】"
	_lbl_gameover_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_gameover_title.add_theme_font_size_override("font_size", 22)
	_lbl_gameover_title.add_theme_color_override("font_color", Color(1.0, 0.36, 0.32))
	vbox.add_child(_lbl_gameover_title)

	_lbl_gameover_detail = Label.new()
	_lbl_gameover_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_gameover_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_gameover_detail.custom_minimum_size = Vector2(580, 52)
	_lbl_gameover_detail.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	vbox.add_child(_lbl_gameover_detail)

	var rule_lbl := Label.new()
	rule_lbl.text = "本局运营已中止，但您建设的轨道、车站、线路及所有存档均完整保留，可立即重新发车。"
	rule_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule_lbl.add_theme_color_override("font_color", Color(0.96, 0.72, 0.42))
	vbox.add_child(rule_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var restart_btn := _make_btn("▸ 重新开始该地图 (Enter / R)", func(): _restart_current_map_after_crash())
	restart_btn.custom_minimum_size = Vector2(240, 38)
	restart_btn.modulate = Color(1.0, 0.72, 0.62)
	btn_row.add_child(restart_btn)

	var home_btn := _make_btn("◀ 返回主页选图", func(): _enter_home_screen())
	home_btn.custom_minimum_size = Vector2(150, 38)
	btn_row.add_child(home_btn)


func _toggle_doors_with_safety_check() -> void:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	if float(tr["speed_mps"]) > 0.30:
		_show_toast("⚠ 行驶中车门安全互锁，请先停车后再开门！")
		return
	var was_open := bool(tr["doors_target_open"])
	var ok := _transit_sim.manual_toggle_doors(_sound, _graph)
	if not was_open and not ok:
		_show_toast("⚠ 没有车门对准站台，车门已安全锁闭！请对准停车位置后再开门")
	elif not was_open and ok:
		var al := int(tr.get("aligned_doorways", 0))
		var tot := int(tr.get("total_doorways", 1))
		if al < tot:
			_show_toast("⚠ 停靠错位：仅 %d/%d 个车门对准站台，只开对准的车门，上下客会变慢" % [al, tot])


func _apply_station_rename() -> void:
	if _edit_station_name == null:
		return
	var new_n := _edit_station_name.text.strip_edges()
	if new_n.is_empty():
		_show_toast("站名不能为空")
		return
	if _editing_station_id < 0 or not _graph.stations.has(_editing_station_id):
		_show_toast("请先用「建造车站」工具点击要改名的已有车站！")
		return
	if _graph.rename_station(_editing_station_id, new_n):
		_edit_station_name.release_focus()
		_rebuild_tracks_only_visual()
		_mark_modified_and_quick_save()
		_show_toast("站名已修改为：%s" % new_n)


func _refresh_build_buttons() -> void:
	for i in range(_tool_btns.size()):
		_highlight_active_btn(_tool_btns[i], i == _build_tool)
	for i in range(_track_mode_btns.size()):
		_highlight_active_btn(_track_mode_btns[i], i == _build_track_mode)
	var xo_idx := 0 if _build_crossover_type == NetworkGraph.CrossoverType.SINGLE else 1
	for i in range(_crossover_type_btns.size()):
		_highlight_active_btn(_crossover_type_btns[i], i == xo_idx)
	for i in range(_station_kind_btns.size()):
		_highlight_active_btn(_station_kind_btns[i], i == _build_station_kind)
	for i in range(_bed_btns.size()):
		_highlight_active_btn(_bed_btns[i], i == _build_bed_style)


func _set_era_filter(era: String) -> void:
	_plan_era_filter = era
	for i in range(_tram_models.size()):
		if _era_matches(_tram_models[i]):
			_plan_model_idx = i
			break
	_plan_sections = mini(2, int(_tram_models[_plan_model_idx].get("default_sections", 2)))
	_refresh_plan_ui()


func _era_matches(m: Dictionary) -> bool:
	if _plan_era_filter == "all":
		return true
	return str(m.get("era", "modern")) == _plan_era_filter


func _step_plan_model(step_dir: int) -> void:
	if _tram_models.is_empty():
		return
	var n := _tram_models.size()
	for k in range(1, n + 1):
		var cand := posmod(_plan_model_idx + step_dir * k, n)
		if _era_matches(_tram_models[cand]):
			_plan_model_idx = cand
			_plan_sections = mini(2, int(_tram_models[cand].get("default_sections", 2)))
			break
	_refresh_plan_ui()


func _refresh_plan_ui() -> void:
	if _lbl_draft_stops == null:
		return
	if _draft_station_ids.is_empty():
		_lbl_draft_stops.text = "当前待建线路站点：（请直接单击地图上已建成的 3D 车站按顺序串联站点；再次点击首站可组成闭合环线）"
		_route_preview_mi.mesh = null
	else:
		var names: PackedStringArray = []
		for i in range(_draft_station_ids.size()):
			var sid := _draft_station_ids[i]
			if _graph.stations.has(sid):
				names.append("%d.%s" % [i + 1, str(_graph.stations[sid]["name"])])
		var mode_tag := "【闭合环线】" if (_draft_station_ids.size() >= 3 and _draft_station_ids[0] == _draft_station_ids[_draft_station_ids.size() - 1]) else "【双向往返线】"
		_lbl_draft_stops.text = "%s 已选 %d 站：\n%s" % [mode_tag, _draft_station_ids.size(), " → ".join(names)]
		_update_draft_route_preview()

	if not _tram_models.is_empty():
		var m: Dictionary = _tram_models[_plan_model_idx]
		var era_txt := "古典老电车" if bool(m.get("vintage", false)) else "现代低地板"
		_lbl_model_card.text = "车型 [%d/%d]：%s\n%s · %s · 极速 %d km/h · 加速度 %.2f m/s²" % [
			_plan_model_idx + 1,
			_tram_models.size(),
			str(m.get("name_zh", "")),
			str(m.get("origin", "")),
			era_txt,
			int(m.get("max_speed_kmh", 70)),
			float(m.get("accel", 1.2)),
		]
		var total_cap := _plan_sections * int(m.get("cap_per_section", 58))
		var is_draft_loop := (_draft_station_ids.size() >= 3 and _draft_station_ids[0] == _draft_station_ids[_draft_station_ids.size() - 1])
		var warn_single := ""
		if not _draft_station_ids.is_empty() and not is_draft_loop and _plan_fleet_count > 1:
			warn_single = "\n⚠ 单轨往返线配多车对开将迎面相撞！多车请连回首站组成环线"
		_lbl_fleet_cfg.text = "配车规模：%d 辆 · 编组：%d 节/列（适配26m站台全开门 · 定员 %d 人）%s" % [_plan_fleet_count, _plan_sections, total_cap, warn_single]

	_refresh_lines_list_ui()


func _update_draft_route_preview() -> void:
	if _draft_station_ids.size() < 2:
		_route_preview_mi.mesh = null
		return
	var pts3: Array[Vector3] = []
	for i in range(_draft_station_ids.size() - 1):
		var seg := _graph.find_track_path_between_stations(_draft_station_ids[i], _draft_station_ids[i + 1])
		for p: Vector3 in seg:
			pts3.append(p)
	if pts3.size() < 2:
		_route_preview_mi.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pts3.size() - 1):
		var a := Vector2(pts3[i].x, pts3[i].z)
		var b := Vector2(pts3[i + 1].x, pts3[i + 1].z)
		var d := b - a
		if d.length() < 0.1:
			continue
		var nrm := Vector2(-d.y, d.x).normalized() * 2.2
		var y := 0.45
		for v: Vector3 in [
			Vector3(a.x - nrm.x, y, a.y - nrm.y), Vector3(b.x + nrm.x, y, b.y + nrm.y), Vector3(a.x + nrm.x, y, a.y + nrm.y),
			Vector3(a.x - nrm.x, y, a.y - nrm.y), Vector3(b.x - nrm.x, y, b.y - nrm.y), Vector3(b.x + nrm.x, y, b.y + nrm.y),
		]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	_route_preview_mi.mesh = st.commit()
	_route_preview_mi.material_override = _translucent_mat(Color(0.18, 0.72, 1.0, 0.85))


func _commit_draft_line() -> void:
	if _draft_station_ids.size() < 2:
		_show_toast("请至少在地图上依次点击 2 座已连通轨道的车站！")
		return
	var m: Dictionary = _tram_models[_plan_model_idx]
	# Trams run on street track, monorails only on the elevated guideway: match the vehicle to the system
	var st0: Dictionary = _graph.stations.get(_draft_station_ids[0], {})
	var on_mono := not st0.is_empty() and TrackBuilder.is_monorail_style(int(_graph.built_tracks.get(int(st0["edge_id"]), -1)))
	if on_mono != bool(m.get("monorail", false)):
		for mi_k in range(_tram_models.size()):
			if bool(_tram_models[mi_k].get("monorail", false)) == on_mono:
				m = _tram_models[mi_k]
				_plan_model_idx = mi_k
				break
		_show_toast("已自动换成%s车型：%s" % ["单轨" if on_mono else "电车", str(m.get("name_zh", ""))])
	var lid := _graph.create_line(_draft_station_ids, str(m["key"]), _plan_fleet_count, _plan_sections)
	if lid < 0:
		_show_toast("无法生成线路：站点间缺少连通轨道！")
		return
	_draft_station_ids.clear()
	_refresh_plan_ui()
	_mark_modified_and_quick_save()
	_show_toast("✓ 已成功开通 %s（配车 %d 辆 · %s）！点击顶部【3.运行与驾驶】即可发车！" % [
		str(_graph.lines[lid]["name"]),
		_plan_fleet_count,
		str(m["name_zh"]),
	])


func _refresh_lines_list_ui() -> void:
	if _lines_list_vbox == null:
		return
	for c in _lines_list_vbox.get_children():
		c.queue_free()
	if _graph.lines.is_empty():
		var empty_l := Label.new()
		empty_l.text = "（暂无开通线路）"
		_lines_list_vbox.add_child(empty_l)
		return

	for lid: int in _graph.lines.keys():
		var ln: Dictionary = _graph.lines[lid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var dot := ColorRect.new()
		dot.color = ln["color"]
		dot.custom_minimum_size = Vector2(12, 18)
		row.add_child(dot)

		var lbl := Label.new()
		lbl.text = "%s (%d站 · %d辆)" % [str(ln["name"]), (ln["station_ids"] as Array).size(), int(ln["trams_count"])]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var lid_copy := lid
		row.add_child(_make_btn("删除", func():
			_graph.lines.erase(lid_copy)
			_refresh_lines_list_ui()
			_mark_modified_and_quick_save()
		))
		_lines_list_vbox.add_child(row)


func _update_run_hud() -> void:
	var map_nm := str(MAP_PRESETS[_current_map_key]["title"])
	_lbl_net_stats.text = "%s：%d 条线路 · 在线 %d 辆 · 候车 %d 人 · 累计送达 %d 人" % [
		map_nm,
		_graph.lines.size(),
		_transit_sim.trams.size(),
		_pax_sim.get_total_waiting(),
		_pax_sim.total_delivered,
	]

	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		_lbl_tram_info.text = "当前无线路车辆运行，请前往【1.建设轨道】与【2.规划线路】开通电车线！"
		_lbl_station_next.text = ""
		_lbl_speed.text = "00.0 km/h"
		return

	var spec: Dictionary = tr["spec"]
	var pax_n: int = (tr["pax_dests"] as Array).size()
	var cap: int = int(tr["capacity"])
	var mode_str := "【手动驾驶】" if _transit_sim.manual_drive else "【AI 运营】"
	var same_line := _transit_sim.line_tram_indices(int(tr["line_id"]))
	_lbl_tram_info.text = "%s 第%d/%d列 · %s · 车上乘客：%d/%d 人 %s" % [
		str(tr["line_name"]),
		same_line.find(_transit_sim.active_tram_idx) + 1,
		same_line.size(),
		str(spec.get("name_zh", "")),
		pax_n,
		cap,
		mode_str,
	]

	var st_info := _transit_sim.find_next_stop_info(tr)
	var dist := float(st_info["dist"])
	var doors_engaged := bool(tr.get("doors_target_open", false)) or float(tr.get("door_ratio", 0.0)) > 0.02
	if _transit_sim.manual_drive and not doors_engaged:
		# Manual driving: until the doors open, show the signed distance to the stopping position
		tr.erase("xfer_snap")
		var ap := _transit_sim.stop_approach_info(tr)
		if ap.is_empty():
			_lbl_station_next.text = "▸ 下一站：%s · 距离 %.0f m" % [str(st_info["name"]), dist]
		else:
			var sd := float(ap["signed_dist"])
			var nm := str(ap["name"])
			var wait_n := _pax_sim.get_waiting_count(int(ap["station_id"]))
			if sd < -0.5:
				_lbl_station_next.text = "⚠ 已越过 %s 停车位置 %.1f m · 只有对准站台的车门能打开" % [nm, sd]
			elif sd <= 0.5:
				_lbl_station_next.text = "◎ %s · 停车位置 %+.1f m（对准）· 站台候车 %d 人 · 停稳后按 O 开门" % [nm, sd, wait_n]
			elif sd < 60.0:
				_lbl_station_next.text = "▸ 进站：%s · 距停车位置 %.1f m · 站台候车 %d 人" % [nm, sd, wait_n]
			else:
				_lbl_station_next.text = "▸ 下一站：%s · 距离 %.0f m" % [nm, sd]
	elif dist < 5.5 or doors_engaged:
		_lbl_station_next.text = _boarding_status_text(tr, st_info)
	else:
		tr.erase("xfer_snap")
		_lbl_station_next.text = "▸ 下一站：%s · 距离 %.0f m" % [str(st_info["name"]), dist]

	var kmh := float(tr["speed_mps"]) * 3.6
	_lbl_speed.text = "%04.1f km/h" % kmh

	# Live Curve & Turnout Speed Limit Badge + Upcoming Restriction / Traffic Hazard Warning!
	var lim_stat := _transit_sim.get_speed_limit_status(tr)
	var lim_kmh := float(lim_stat["limit_kmh"])
	var der_kmh := float(lim_stat["derail_kmh"])
	var z_name := str(lim_stat["zone_name"])
	var is_over := (kmh > lim_kmh + 0.4)

	if is_over and der_kmh < 900.0:
		_lbl_speed.add_theme_color_override("font_color", Color(1.0, 0.30, 0.26))
		_lbl_speed_limit.text = "⚠ %s限速 %.0f km/h（超速！≥%.0f 翻车）" % [z_name, lim_kmh, der_kmh]
		_lbl_speed_limit.add_theme_color_override("font_color", Color(1.0, 0.34, 0.28))
	elif is_over:
		_lbl_speed.add_theme_color_override("font_color", Color(1.0, 0.76, 0.28))
		_lbl_speed_limit.text = "【%s限速 %.0f km/h · 超速】" % [z_name, lim_kmh]
		_lbl_speed_limit.add_theme_color_override("font_color", Color(1.0, 0.76, 0.28))
	else:
		_lbl_speed.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		_lbl_speed_limit.text = "【%s限速 %.0f km/h】" % [z_name, lim_kmh]
		var badge_c := Color(0.98, 0.78, 0.32) if int(lim_stat["zone_kind"]) >= 2 else Color(0.54, 0.92, 0.72)
		_lbl_speed_limit.add_theme_color_override("font_color", badge_c)

	# Check upcoming Dedicated Tram Signal, traffic hazard, or curve/turnout speed limit!
	var hazard_msg := ""
	var sig_badge_txt := "电车灯 ┃ 通行"
	var secs_h: Array = tr["tram_info"]["sections"]
	if _traffic_sim != null and not secs_h.is_empty():
		var sig_info := _traffic_sim.get_upcoming_tram_signal(tr, _graph)
		if bool(sig_info["has_signal"]):
			var asp := str(sig_info["aspect"])
			var sd := float(sig_info["dist"])
			if asp == "red":
				sig_badge_txt = "电车灯 ━ 禁行(%.0fm)" % sd
				hazard_msg = "● 前方 %.0fm 电车专用灯【━ 禁行】· 横向绿灯车流通过，请在停止线前停车！" % sd
			elif asp == "yellow":
				sig_badge_txt = "电车灯 ● 黄灯(%.0fm)" % sd
				hazard_msg = "● 前方 %.0fm 电车专用灯【● 黄灯转换】· 请提前减速准备停车" % sd
			else:
				sig_badge_txt = "电车灯 ┃ 通行(%.0fm)" % sd

		if bool(tr.get("elevated", false)):
			var swi := _transit_sim.switch_ahead_info(tr, _transit_sim.active_tram_idx)
			sig_badge_txt = "道岔信号 ┃ 通行"
			if not swi.is_empty() and float(swi["dist"]) < 220.0:
				var sd2 := maxf(0.0, float(swi["dist"]) - TransitSim.SW_SIGNAL_BACK + 2.0)
				var need_txt := "侧向(渡线)" if float(swi["need"]) > 0.5 else "直向"
				var cur_txt := "侧向(渡线)" if float(swi["target"]) > 0.5 else "直向"
				if bool(swi["green"]):
					sig_badge_txt = "道岔信号 ┃ 通行(%.0fm)" % sd2
					hazard_msg = "▸ 前方 %.0fm 道岔已排列【%s】并锁闭 · 信号开放" % [float(swi["dist"]), cur_txt]
				else:
					sig_badge_txt = "道岔信号 ━ 停车(%.0fm)" % sd2
					if bool(swi["busy"]):
						hazard_msg = "● 前方 %.0fm 道岔被其他列车占用 · 信号【━ 停车】，请在信号机前停车等待" % float(swi["dist"])
					elif bool(swi["moving"]):
						hazard_msg = "● 前方 %.0fm 道岔转辙中 → %s · 信号【━ 停车】" % [float(swi["dist"]), cur_txt]
					elif _transit_sim.manual_drive and _transit_sim.active_tram_idx >= 0:
						hazard_msg = "● 前方 %.0fm 道岔在【%s】，本次进路需要【%s】· 按 G 扳道岔，否则驶入将脱轨！" % [float(swi["dist"]), cur_txt, need_txt]
					else:
						hazard_msg = "● 前方 %.0fm 道岔信号【━ 停车】· 等待道岔排列 %s" % [float(swi["dist"]), need_txt]
		var f0 := secs_h[0] as Node3D
		var car_haz := {"has_hazard": false} if bool(tr.get("elevated", false)) else _traffic_sim.find_hazard_ahead_of_tram(f0.global_position, -f0.global_transform.basis.z, 36.0)
		if bool(car_haz["has_hazard"]):
			hazard_msg = "⚠ 前方 %.0fm 路口有小车通行！请制动(S)避让" % float(car_haz["dist"])

	if hazard_msg.is_empty():
		var next_d := float(lim_stat["next_dist_m"])
		if next_d < 72.0:
			hazard_msg = "▸ 预告：前方 %.0fm 进入【%s】，限速 %.0f km/h（超速将脱轨翻车）" % [
				next_d,
				str(lim_stat["next_zone_name"]),
				float(lim_stat["next_limit_kmh"]),
			]
		else:
			hazard_msg = "交通秩序正常：遵守电车专用灯(┃通行/━禁行)与弯道道岔限速牌"
	_lbl_hazard_hint.text = hazard_msg

	var n_idx := int(tr["notch"])
	var n_col := Color(0.78, 0.82, 0.86)
	if n_idx > TransitSim.NOTCH_NEUTRAL:
		n_col = Color(0.28, 0.88, 0.54)
	elif n_idx == 0:
		n_col = Color(1.0, 0.28, 0.28)
	elif n_idx < TransitSim.NOTCH_NEUTRAL:
		n_col = Color(0.96, 0.72, 0.26)
	_lbl_notch.text = "档位 " + TransitSim.NOTCH_LABELS[n_idx]
	_lbl_notch.add_theme_color_override("font_color", n_col)

	var dir_txt := "前进" if float(tr["dir"]) > 0.0 else "折返向"
	var door_txt := "车门锁闭"
	if float(tr["door_ratio"]) > 0.1:
		var od := int(tr.get("open_doorways", 0))
		var td := int(tr.get("total_doorways", 1))
		door_txt = "站台侧开启 %d/%d 门(非站台侧锁闭)" % [od, td] if od > 0 else "未对齐站台·全门锁闭"
	_lbl_drv_status.text = "%s · %s · %s" % [dir_txt, door_txt, sig_badge_txt]

	for i in range(_notch_bars.size()):
		if i == n_idx:
			_notch_bars[i].color = n_col
		elif i < TransitSim.NOTCH_NEUTRAL:
			_notch_bars[i].color = Color(0.32, 0.24, 0.18, 0.65)
		elif i == TransitSim.NOTCH_NEUTRAL:
			_notch_bars[i].color = Color(0.28, 0.30, 0.32, 0.65)
		else:
			_notch_bars[i].color = Color(0.18, 0.32, 0.24, 0.65)

	_btn_doors.text = "关闭车门 (O)" if bool(tr["doors_target_open"]) else "打开车门 (O)"
	_btn_drive_mode.text = "切回 AI 托管 (Q)" if _transit_sim.manual_drive else "接管手动驾驶 (Q)"


func _trigger_game_over_accident(ev: Dictionary) -> void:
	if _game_over:
		return
	_game_over = true
	_lbl_toast.visible = false
	_sound.speed_mps = 0.0
	_sound.traction_effort = 0.0
	_sound.overspeed_squeal = 0.0
	_sound.play_crash_sound()

	# Keep all built tracks, stations, lines, manual saves & auto-saves intact!
	if not _is_demo_readonly:
		_mark_modified_and_quick_save()

	var acc_type := str(ev.get("type", "car_collision"))
	var spd_kmh := float(ev.get("speed_kmh", 30.0))
	_accident_focus = ev.get("world_pos", _get_traffic_focus_pos()) as Vector3
	_accident_orbit_yaw = 0.65
	_spawn_accident_fx(_accident_focus)

	var map_nm := str(MAP_PRESETS[_current_map_key]["title"])
	if acc_type == "derail":
		var z_nm := str(ev.get("zone_name", "急弯/道岔"))
		var lim_v := float(ev.get("limit_kmh", 20.0))
		_lbl_gameover_title.text = "【超速脱轨翻车 · 本局运营中止】"
		_lbl_gameover_detail.text = "地图：%s\n电车以 %.1f km/h 高速冲入【%s】（规定限速 %.0f km/h），离心力超限导致脱轨侧翻！\n（您建设的轨道、车站、线路及所有存档均完整保留）" % [
			map_nm, spd_kmh, z_nm, lim_v
		]
	elif acc_type == "buffer":
		_lbl_gameover_title.text = "【撞击车挡脱轨 · 本局运营中止】"
		_lbl_gameover_detail.text = "地图：%s\n电车以 %.1f km/h 冲过终点站停车位置，撞上轨道尽头的车挡后脱轨！（车挡只能承受 %.0f km/h 以下的轻触）\n（您建设的轨道、车站、线路及所有存档均完整保留）" % [
			map_nm, spd_kmh, TransitSim.BUFFER_SAFE_KMH
		]
	elif acc_type == "switch":
		_lbl_gameover_title.text = "【驶入未开通道岔脱轨 · 本局运营中止】"
		_lbl_gameover_detail.text = "地图：%s\n单轨列车以 %.1f km/h 冒进红色道岔信号，驶入%s的道岔，走行轮离开轨道梁脱轨！（手动驾驶请按 G 把前方道岔扳到本次进路方向，待信号开放后再通过）\n（您建设的轨道、车站、线路及所有存档均完整保留）" % [
			map_nm, spd_kmh, "正在转辙" if bool(ev.get("moving", false)) else "方向不对"
		]
	elif acc_type == "tram_collision":
		_lbl_gameover_title.text = "【电车相撞事故 · 本局运营中止】"
		_lbl_gameover_detail.text = "地图：%s\n两列有轨电车发生严重碰撞（相对撞击速度 %.1f km/h），全线被迫紧急停运！\n（您建设的轨道、车站、线路及所有存档均完整保留）" % [
			map_nm, spd_kmh
		]
	else:
		_lbl_gameover_title.text = "【电车与小车碰撞 · 本局运营中止】"
		_lbl_gameover_detail.text = "地图：%s\n电车以 %.1f km/h 与路面社会小车发生碰撞事故，本局运营立即终止！\n（您建设的轨道、车站、线路及所有存档均完整保留）" % [
			map_nm, spd_kmh
		]

	_nav_bar.visible = false
	_build_panel.visible = false
	_plan_panel.visible = false
	_run_top_panel.visible = false
	_cam_panel.visible = false
	_drv_panel.visible = false
	_slot_modal.visible = false
	_gameover_modal.visible = true


func _restart_current_map_after_crash() -> void:
	_game_over = false
	_gameover_modal.visible = false
	_clear_accident_fx()
	if _started_from_demo:
		_selected_home_map = _current_map_key
		_start_map_demo_network()
	else:
		# Keep player's built tracks, stations & lines; simply reset trams, traffic & passengers!
		_rebuild_tracks_and_operations(true)
		_nav_bar.visible = true
		_set_game_mode(GameMode.RUN)
		_show_toast("已重新发车运营（您建设的轨道、车站与线路均已保留）")


func _spawn_accident_fx(world_pos: Vector3) -> void:
	_clear_accident_fx()
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.72, 0.18)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.55, 0.10)
	spark_mat.emission_energy_multiplier = 3.2

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.24, 0.24, 0.25, 0.72)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.roughness = 0.95

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for _i in range(22):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.14, 0.36)
		bm.material = spark_mat
		mi.mesh = bm
		_fx_root.add_child(mi)
		mi.global_position = world_pos + Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(0.3, 1.6), rng.randf_range(-1.2, 1.2))
		_fx_particles.append({
			"node": mi,
			"vel": Vector3(rng.randf_range(-7.5, 7.5), rng.randf_range(3.5, 9.0), rng.randf_range(-7.5, 7.5)),
			"gravity": 16.0,
			"life": rng.randf_range(0.7, 1.6),
			"smoke": false,
		})

	for _j in range(10):
		var smi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.55; sph.height = 1.1; sph.radial_segments = 8; sph.rings = 5
		sph.material = smoke_mat
		smi.mesh = sph
		_fx_root.add_child(smi)
		smi.global_position = world_pos + Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(0.8, 2.2), rng.randf_range(-1.8, 1.8))
		_fx_particles.append({
			"node": smi,
			"vel": Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(1.4, 2.8), rng.randf_range(-0.8, 0.8)),
			"gravity": -0.2,
			"life": 8.0,
			"smoke": true,
		})


func _update_accident_fx(dt: float) -> void:
	if _fx_particles.is_empty():
		return
	var idx := _fx_particles.size() - 1
	while idx >= 0:
		var p: Dictionary = _fx_particles[idx]
		var n: Node3D = p["node"]
		if not is_instance_valid(n):
			_fx_particles.remove_at(idx)
			idx -= 1
			continue
		var life := float(p["life"]) - dt
		p["life"] = life
		if life <= 0.0 and not bool(p["smoke"]):
			n.queue_free()
			_fx_particles.remove_at(idx)
			idx -= 1
			continue
		var vel: Vector3 = p["vel"]
		vel.y -= float(p["gravity"]) * dt
		if bool(p["smoke"]):
			vel *= (1.0 - dt * 0.65)
			n.scale += Vector3.ONE * (dt * 0.38)
		else:
			if n.global_position.y < 0.12 and vel.y < 0.0:
				n.global_position.y = 0.12
				vel.y = -vel.y * 0.35
		p["vel"] = vel
		n.global_position += vel * dt
		idx -= 1


func _clear_accident_fx() -> void:
	_fx_particles.clear()
	if _fx_root != null:
		for c in _fx_root.get_children():
			c.queue_free()


func _make_panel(bg: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 9; sb.corner_radius_top_right = 9
	sb.corner_radius_bottom_left = 9; sb.corner_radius_bottom_right = 9
	sb.border_width_left = 1; sb.border_width_top = 1
	sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = Color(0.32, 0.36, 0.42, 0.60)
	sb.content_margin_left = 11; sb.content_margin_right = 11
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	return pc


func _make_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b


static func _highlight_active_btn(btn: Button, active: bool) -> void:
	if btn == null:
		return
	btn.modulate = Color(0.55, 1.0, 0.78) if active else Color(1.0, 1.0, 1.0)


func _parse_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	var cli_map := ""
	var cli_demo := false
	for i in range(args.size()):
		if args[i] == "--map" and i + 1 < args.size():
			cli_map = args[i + 1]
		elif args[i] == "--demo":
			cli_demo = true
		elif args[i] == "--shot-tour" and i + 1 < args.size():
			_shot_dir = args[i + 1]
			DirAccess.make_dir_recursive_absolute(_shot_dir)
			_shot_step = 1
			_shot_frames_wait = 10

	if not cli_map.is_empty() and MAP_PRESETS.has(cli_map):
		_selected_home_map = cli_map
		if cli_demo:
			_start_map_demo_network()
		else:
			_start_map_continue_or_new()


func _process_shot_tour() -> void:
	if _shot_step <= 0:
		return
	if _shot_frames_wait > 0:
		_shot_frames_wait -= 1
		return

	match _shot_step:
		1:
			# Load Seattle Demo & run 1,200 physics steps (~40 simulated seconds of station stops + full traffic light cycles!)
			_selected_home_map = "seattle"
			_start_map_demo_network()
			var sim_accidents := 0
			for _step_k in range(1800):
				var step_dt := 0.033
				_pax_sim.step_simulation(step_dt, _graph)
				_traffic_sim.step_traffic(step_dt, _graph, _transit_sim.trams, _transit_sim.active_tram_idx, false, _get_traffic_focus_pos())
				var ev := _transit_sim.step_all_trams(step_dt, _graph, _pax_sim, _traffic_sim, _sound)
				if not ev.is_empty():
					sim_accidents += 1
					print("UNEXPECTED ACCIDENT IN DEMO STRESS TEST: ", ev)
					break
			print("Stress test 60s completed: accidents = ", sim_accidents, ", boarded = ", _pax_sim.total_boarded, ", delivered = ", _pax_sim.total_delivered)
			_stats_modal.visible = true
			_refresh_stats_modal_ui()
			print("Stats dashboard lines rows = ", _stats_lines_vbox.get_child_count(), ", stations rows = ", _stats_stations_vbox.get_child_count())
			_stats_modal.visible = false

			# Shot 1: Amazon The Spheres + Multi-Branched Trees + Sidewalk + Sculpted Cars!
			var tr := _transit_sim.get_active_tram()
			if not tr.is_empty():
				var curve_s1: Curve3D = tr["curve"]
				tr["s"] = curve_s1.get_closest_offset(Vector3(-95.0, 0.0, 268.0))
				_transit_sim._position_tram_3d(tr)
			_set_cam_mode(CamMode.CHASE)
			_orbit_dist = 24.0
			_orbit_yaw = deg_to_rad(138.0)
			_orbit_pitch = deg_to_rad(11.0)
			_shot_step = 2
			_shot_frames_wait = 8
		2:
			_save_viewport_png(_shot_dir.path_join("pbr_01_spheres_trees_sidewalk.png"))
			# Shot 2: Close-up of Signalized Intersection (Motor Red/Yellow/Green + Dedicated Tram Signal + Sculpted Cars!)
			var tr2 := _transit_sim.get_active_tram()
			if not tr2.is_empty():
				for nid: int in _traffic_sim.signals.keys():
					var sig: Dictionary = _traffic_sim.signals[nid]
					if bool(sig["has_track"]) and (sig["tram_heads"] as Array).size() > 0:
						var jp2: Vector2 = sig["pos2"]
						var curve: Curve3D = tr2["curve"]
						var s_int := curve.get_closest_offset(Vector3(jp2.x, 0.0, jp2.y))
						tr2["s"] = fposmod(s_int - 16.5 * float(tr2["dir"]), float(tr2["route_len"]))
						tr2["speed_mps"] = 0.0
						sig["timer"] = 4.0 # Show Green Motor Light + Dedicated Tram Vertical Proceed Bar '┃'!
						_traffic_sim._refresh_signal_visuals(sig)
						_transit_sim._position_tram_3d(tr2)
						break
				_update_run_hud()
			_set_cam_mode(CamMode.CHASE)
			_orbit_dist = 13.5
			_orbit_yaw = deg_to_rad(8.0)
			_orbit_pitch = deg_to_rad(10.0)
			_shot_step = 3
			_shot_frames_wait = 8
		3:
			_save_viewport_png(_shot_dir.path_join("pbr_02_signals_and_cars.png"))
			# Shot 3: Partial-alignment door safety test (offset +10m so only aligned platform-side doors open!)
			var tr3 := _transit_sim.get_active_tram()
			if not tr3.is_empty():
				var stops3: Array = tr3["stops"]
				tr3["s"] = fposmod(float(stops3[1]["offset"]) + 10.0 * float(tr3["dir"]), float(tr3["route_len"]))
				tr3["speed_mps"] = 0.0
				tr3["doors_target_open"] = true
				tr3["door_ratio"] = 1.0
				_transit_sim._position_tram_3d(tr3)
				var dock3 := _transit_sim.get_dock_info_for_tram(tr3, _graph)
				var d_res3 := TramBuilder.update_doors(tr3["tram_info"], 1.0, dock3)
				print("Partial-align door test at ", stops3[1]["name"], ": open_doorways=", d_res3.get("open_doorways"), "/", d_res3.get("total_doorways"))
			_set_cam_mode(CamMode.DOOR_ACTION)
			_shot_step = 4
			_shot_frames_wait = 12
		4:
			_save_viewport_png(_shot_dir.path_join("pbr_03_pedestrians_and_monorail.png"))
			# Shot 4: Grid City Double Track + Scissors Crossover Build & Render Test!
			_selected_home_map = "grid"
			_start_map_demo_network()
			var dbl_count := 0
			for eid_raw in _graph.built_tracks.keys():
				var eid := int(eid_raw)
				_graph.set_track_on_edge(eid, int(_graph.built_tracks[eid]), NetworkGraph.TrackMode.DOUBLE)
				if dbl_count == 0 and float(_graph.edges[eid]["length"]) >= 26.0:
					_graph.set_crossover_on_edge(eid, NetworkGraph.CrossoverType.DOUBLE)
				dbl_count += 1
			_rebuild_tracks_and_operations(true)
			_set_cam_mode(CamMode.CHASE)
			_orbit_dist = 24.0
			_orbit_yaw = deg_to_rad(32.0)
			_orbit_pitch = deg_to_rad(22.0)
			_shot_step = 5
			_shot_frames_wait = 10
		5:
			_save_viewport_png(_shot_dir.path_join("pbr_04_grid_city_pbr.png"))
			get_tree().quit()


func _save_viewport_png(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("Saved screenshot: ", path)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}
