extends Node3D

const BED_STYLE_NAMES := [
	"独立工字草皮",
	"柏油槽型嵌轨",
	"齐平绿茵草皮",
	"花岗岩专用道",
	"碎石工字枕木",
	"高架单轨梁 (单轨系统)",
]
const BED_STYLE_NAMES_EN := [
	"Turf Tie-Track",
	"Asphalt Grooved Rail",
	"Flush Lawn Track",
	"Granite Transitway",
	"Ballasted Timber Ties",
	"Elevated Monorail Beam",
]

const MAP_ORDER: Array[String] = ["grid", "seattle", "jiaxing"]

const MAP_PRESETS := {
	"grid": {
		"key": "grid",
		"index": "01",
		"title": "网格新城",
		"title_en": "Grid City",
		"subtitle": "9×9 棋盘街区 · 跨河绿带 · 中央广场",
		"subtitle_en": "9×9 Grid · River Greenway · Central Plaza",
		"desc": "规整开阔的 1km² 棋盘街网与滨河绿廊，适合从零规划草皮工字轨、柏油嵌轨与多线换乘。",
		"desc_en": "Clean 1 km² street grid and river parkway, ideal for planning turf/grooved tracks and multi-line transfers from scratch.",
		"data_path": "res://data/grid_city.json",
		"default_target": Vector3(0.0, 0.0, 0.0),
		"default_height": 560.0,
	},
	"seattle": {
		"key": "seattle",
		"index": "02",
		"title": "西雅图 · 城区",
		"title_en": "Seattle · Downtown",
		"subtitle": "市中心 · 联合湖 · 弗里蒙特 · 华盛顿大学 · 国会山 · 体育场区",
		"subtitle_en": "Downtown · Lake Union · Fremont · UW · Capitol Hill · SODO",
		"desc": "基于真实 OSM 数据：从弗里蒙特、华盛顿大学到 T-Mobile 球场，约 5 万栋按真实高度与屋顶还原的建筑，高架单轨与湖岸城景。",
		"desc_en": "Real OSM layout from Fremont & UW to T-Mobile Park: ~50k buildings with real heights & roofs, elevated monorail, and waterfront views.",
		"data_path": "res://data/seattle_expanded.json",
		"default_target": Vector3(0.0, 0.0, 120.0),
		"default_height": 600.0,
	},
	"jiaxing": {
		"key": "jiaxing",
		"index": "03",
		"title": "嘉兴 · 南湖与高铁南站",
		"title_en": "Jiaxing · Nanhu & South Sta.",
		"subtitle": "南湖烟雨楼 · 环城水网 · 内环高架 · 长水路—庆丰路 · 嘉兴南站",
		"subtitle_en": "Nanhu Lake · Canals · Inner Ring Viaduct · Changshui-Qingfeng · HSR South Sta.",
		"desc": "基于真实 OSM 数据还原嘉兴主城与高铁南站走廊：南湖红船与烟雨楼、南湖革命纪念馆、森林火车站、江南河网与嘉兴南站。",
		"desc_en": "Real OSM Jiaxing city & HSR corridor: Nanhu Lake & Yanyu Tower, Revolutionary Memorial Hall, Forest Station, canals & Jiaxing South HSR Station.",
		"data_path": "res://data/jiaxing.json",
		"default_target": Vector3(0.0, 0.0, 0.0),
		"default_height": 620.0,
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
	TRACK_OFFROAD = 5, # 空地直连：click points across open ground, tram-only right of way
	ROAD_BUILD = 6,
	ROAD_REMOVE = 7,
	ROAD_LANES = 8,
	BUILDING_DEMOLISH = 9,
}

const LANE_CFGS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)]
const LANE_CFG_LABELS: Array[String] = ["单向1", "单向2", "单向3", "单向4", "双向1+1", "双向2+2", "双向3+3"]
const LANE_CFG_LABELS_EN: Array[String] = ["1-Way 1", "1-Way 2", "1-Way 3", "1-Way 4", "2-Way 1+1", "2-Way 2+2", "2-Way 3+3"]


static func _bed_style_name(idx: int) -> String:
	var i := clampi(idx, 0, BED_STYLE_NAMES.size() - 1)
	return BED_STYLE_NAMES_EN[i] if L10n.is_en() else BED_STYLE_NAMES[i]


static func _lane_cfg_label(idx: int) -> String:
	var i := clampi(idx, 0, LANE_CFG_LABELS.size() - 1)
	return LANE_CFG_LABELS_EN[i] if L10n.is_en() else LANE_CFG_LABELS[i]


static func _map_title(map_key: String) -> String:
	var p: Dictionary = MAP_PRESETS.get(map_key, {})
	return str(p.get("title_en", p.get("title", map_key))) if L10n.is_en() else str(p.get("title", map_key))


static func _map_subtitle(map_key: String) -> String:
	var p: Dictionary = MAP_PRESETS.get(map_key, {})
	return str(p.get("subtitle_en", p.get("subtitle", ""))) if L10n.is_en() else str(p.get("subtitle", ""))


static func _map_desc(map_key: String) -> String:
	var p: Dictionary = MAP_PRESETS.get(map_key, {})
	return str(p.get("desc_en", p.get("desc", ""))) if L10n.is_en() else str(p.get("desc", ""))

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
var _loaded_city_map_key := ""
var _ops_dirty := true
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
var _last_track_tool: int = BuildTool.TRACK_SINGLE
var _build_bed_style: int = TrackBuilder.BedStyle.GRASS_VIGNOLE
var _build_track_mode: int = NetworkGraph.TrackMode.SINGLE
var _build_crossover_type: int = NetworkGraph.CrossoverType.SINGLE
const STATION_LEN_PRESETS: Array[float] = [27.0, 38.0, 50.0]
const STATION_LEN_LABELS: Array[String] = ["27m (2节)", "38m (3节)", "50m (4节)"]

var _land_prev_has := false # 3D free-build track / new road: first point placed
var _land_prev_xz := Vector2.ZERO
var _land_prev_nid := -1
var _land_prev_elev := 0.0
var _build_elev_idx := 2 # 0=B2(-18m), 1=B1(-10m), 2=G(0m), 3=L1(+7.2m), 4=L2(+13.8m)
var _underground_view := false
var _blueprint_root: Node3D = null
var _underground_landmarks_root: Node3D = null
var _btn_underground: Button
var _elev_btns: Array[Button] = []
var _road_lane_idx := 4
var _road_tool_btns: Array[Button] = []
var _lane_cfg_btns: Array[Button] = []
var _built_land_sig := ""
var _shop_mat: ShaderMaterial = null
var _bld_grid: Dictionary = {}
var _city_tiles: CityTiles = null # outer map tiles (Seattle v4), streamed in around the core
var _build_station_side := 1
var _build_station_kind: int = NetworkGraph.StationKind.SIDE_SINGLE
var _build_station_len_idx := 0
var _editing_station_id := -1
var _path_start_node := -1
var _build_cat_btns: Array[Button] = []
var _build_cat_subpanels: Array[Control] = []
var _track_lay_btns: Array[Button] = []
var _track_mode_btns: Array[Button] = []
var _crossover_type_btns: Array[Button] = []
var _station_kind_btns: Array[Button] = []
var _station_len_btns: Array[Button] = []
var _edit_station_name: LineEdit

# Plan mode state
var _draft_station_ids: Array[int] = []
var _plan_era_filter := "all"
var _plan_model_idx := 0
var _plan_fleet_count := 3
var _plan_sections := 2
var _plan_express := false # 快车：四轨区段走内侧快车道，四轨站优先发车 / 越行慢车
var _plan_signal_priority := false # 信号优先（TSP）：进路口自动延长绿灯或提前切绿
var _btn_plan_service: Button
var _btn_plan_tsp: Button
var _editing_line_id := -1 # line being edited in the planner (-1: drafting a new line)
var _draft_insert_idx := -1 # stations clicked on the map go in after this draft index (-1: at the end)
var _draft_list_vbox: VBoxContainer
var _btn_commit_line: Button
var _btn_cancel_edit: Button

# Time of day (continuous 0..24h) & Weather
var _time_hours := 13.5
var _night_factor := 0.0
var _updating_slider := false
var _weather_mode: int = WeatherSystem.WeatherType.SUNNY
var _weather: WeatherSystem
var _btn_weather: Button
var _settings_weather_btns: Array[Button] = []

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
var _stats_trams_vbox: VBoxContainer
var _stats_refresh_accum := 0.0
var _last_ann_approach_sid := -1
var _last_ann_door_open := false
var _door_cam_yaw := 0.0
var _door_cam_pitch := 0.0
var _plan_target := Vector3(0.0, 0.0, 120.0)
var _plan_height := 560.0
var _plan_max_height := 1180.0 # grows with the map, so the whole city fits on screen
# Whole-city overview (bird's-eye view zoomed far out): light model in place of the detailed city; no building
const OVERVIEW_ON_H := 1500.0
const OVERVIEW_OFF_H := 1300.0
var _overview_on := false
var _overview_root: Node3D = null
var _overview_task := -1
var _overview_result: Node3D = null
var _overview_sig := ""
var _overview_saved_far := 2800.0
var _overview_toast_cd := 0.0
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

var _plan_panel: PanelContainer
var _lbl_draft_stops: Label
var _lbl_model_card: Label
var _lbl_fleet_cfg: Label
var _lines_list_vbox: VBoxContainer

var _run_top_panel: PanelContainer
var _cam_panel: PanelContainer
var _cam_btns: Array[Button] = []
var _drv_panel: PanelContainer
var _lbl_net_stats: Label
var _lbl_tram_info: Label
var _lbl_station_next: Label
var _lbl_hazard_hint: Label
var _btn_pax_rate: Button
var _ui_canvas: CanvasLayer
var _ai_style_btns: Array[Button] = []
var _line_ai_style_btns: Array[Button] = []
var _lbl_line_ai_group: Label
var _btn_ai_spd_down: Button
var _btn_ai_spd_val: Button
var _btn_ai_spd_up: Button
var _btn_line_tsp: Button
var _btn_global_tsp: Button
var _btn_stats_global_tsp: Button
var _lbl_speed: Label
var _lbl_speed_limit: Label
var _lbl_notch: Label
var _lbl_drv_status: Label
var _btn_doors: Button
var _btn_reverser: Button
var _run_paused := false # RUN mode paused: trains, cars, passengers and autosave stand still; the camera stays free
var _btn_pause: Button
var _btn_hold_manual: Button
var _btn_sw_lock: Button
var _btn_auto_sw: Button
var _lbl_paused: Label
var _btn_drive_mode: Button
var _notch_bars: Array[ColorRect] = []

var _gameover_modal: Control
var _lbl_gameover_title: Label
var _lbl_gameover_detail: Label

# Home Screen & Multi-Slot Save Manager UI
var _home_overlay: Control
var _home_card_panels: Dictionary = {}
var _home_cards_scroll: ScrollContainer
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
var _startup_loading := false
var _startup_overlay: ColorRect
var _startup_title_lbl: Label
var _startup_status_lbl: Label
var _startup_pct_lbl: Label
var _startup_spinner_lbl: Label
var _startup_bar: ProgressBar
var _loading_spin_t := 0.0
const LOADING_SPIN_FRAMES := ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]


func _enter_tree() -> void:
	# Strip "(DEBUG)" from the window title at the earliest possible engine lifecycle hook!
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("3D train game")


func _ready() -> void:
	L10n.init_from_settings()
	_apply_app_branding()
	_setup_font()
	_load_tram_catalogue()
	_setup_environment()
	_setup_scene_nodes()
	_build_ui()

	# Headless or automated shot-tour: run synchronously for deterministic CLI execution
	var is_headless_or_tour := (DisplayServer.get_name() == "headless")
	for a in OS.get_cmdline_user_args():
		if a == "--shot-tour":
			is_headless_or_tour = true
			break

	if is_headless_or_tour:
		_load_map_world("seattle", true, false)
		_set_time_hours(_time_hours)
		_enter_home_screen()
		_parse_cli_args()
	else:
		# Non-blocking staged startup: return from _ready() in <25ms so macOS IMMEDIATELY
		# updates the window title to "3D train game" (removing "(DEBUG)" before fade-in finishes!)
		# and paints our branded loading screen instead of freezing on a black screen!
		_startup_loading = true
		_home_overlay.visible = false
		_hud_layer_ctrl.visible = false
		_overlay_root.visible = false
		if _startup_overlay != null:
			_startup_overlay.visible = true
		call_deferred("_async_startup_load")


func _async_startup_load() -> void:
	_apply_app_branding()
	_set_startup_progress(15.0, L10n.t("正在初始化 3D 渲染与音频系统...", "Initializing 3D renderer & audio..."))
	await get_tree().process_frame
	_apply_app_branding()
	await get_tree().process_frame

	_set_startup_progress(32.0, L10n.t("正在解析西雅图城区街道路网...", "Parsing Seattle street network..."))
	await get_tree().process_frame
	var preset: Dictionary = MAP_PRESETS["seattle"]
	_current_map_key = "seattle"
	_map_data = _read_json(str(preset["data_path"]))
	Terrain.load_for("seattle", _map_data.get("areas", []), _map_data.get("graph_edges", [])) # real ground (elevation data)
	var bounds: Array = _map_data.get("bounds", [-520.0, -520.0, 520.0, 520.0])
	_pan_limit_x = maxf(absf(float(bounds[0])), absf(float(bounds[2]))) + 80.0
	_pan_limit_z = maxf(absf(float(bounds[1])), absf(float(bounds[3]))) + 80.0
	_plan_max_height = maxf(1180.0, maxf(float(bounds[2]) - float(bounds[0]), float(bounds[3]) - float(bounds[1])) * 0.78)
	_plan_target = preset["default_target"] as Vector3
	_plan_height = float(preset["default_height"])
	_snap_camera_next = true
	_graph.load_from_map_data(_map_data, true)
	Terrain.grade_for_tracks(_graph)

	_set_startup_progress(58.0, L10n.t("正在构建建筑、公园绿地与 Lake Union 湖岸...", "Building city blocks, parks & Lake Union waterfront..."))
	await get_tree().process_frame
	_build_city_world()

	_set_startup_progress(86.0, L10n.t("正在铺设轨道、道岔与车站...", "Laying tracks, switches & stations..."))
	await get_tree().process_frame
	_rebuild_tracks_and_operations(false)
	_set_time_hours(_time_hours)

	_set_startup_progress(100.0, L10n.t("准备就绪", "Ready"))
	await get_tree().process_frame
	_startup_loading = false
	if _startup_overlay != null:
		_startup_overlay.visible = false
	_apply_app_branding()
	_enter_home_screen()
	_parse_cli_args()


func _set_startup_progress(val: float, msg: String) -> void:
	var clamped := clampf(val, 0.0, 100.0)
	if _startup_bar != null:
		_startup_bar.value = clamped
	if _startup_pct_lbl != null:
		_startup_pct_lbl.text = "%d%%" % int(round(clamped))
	if _startup_status_lbl != null:
		_startup_status_lbl.text = msg
	_tick_loading_spinner(0.06)


func _tick_loading_spinner(delta: float) -> void:
	_loading_spin_t += delta * 11.0
	if _startup_spinner_lbl != null:
		_startup_spinner_lbl.text = LOADING_SPIN_FRAMES[int(floor(_loading_spin_t)) % LOADING_SPIN_FRAMES.size()]


func _begin_loading_overlay(title_text: String, initial_msg: String, opaque: bool = false) -> void:
	_startup_loading = true
	if _sound != null:
		_sound.set_menu_silenced(true)
	if _startup_overlay != null:
		_startup_overlay.color = Color(0.05, 0.08, 0.12, 1.0 if opaque else 0.90)
		_startup_overlay.visible = true
	if _startup_title_lbl != null:
		_startup_title_lbl.text = title_text
	_set_startup_progress(4.0, initial_msg)


func _end_loading_overlay() -> void:
	_set_startup_progress(100.0, L10n.t("准备就绪", "Ready"))
	if _startup_overlay != null:
		_startup_overlay.visible = false
	_startup_loading = false
	if _sound != null:
		_sound.set_menu_silenced(_in_home_menu or _game_mode != GameMode.RUN)


# Pre-build nearby outer CityTiles + warm TrafficSim caches + render warmup frames behind the loading overlay
# so Metal shader compilation & initial chunk uploads finish BEFORE gameplay starts!
func _prewarm_city_and_gpu(focus_pos: Vector3, is_run_mode: bool, pct_start: float, pct_end: float) -> void:
	var tile_end := lerpf(pct_start, pct_end, 0.78) if is_run_mode else pct_end
	if _city_tiles != null:
		var prewarm_r := 2350.0
		var need_n := mini(45, _city_tiles.near_unbuilt_count(focus_pos, prewarm_r))
		if need_n > 0:
			var done_n := 0
			var last_built := _city_tiles.built_count()
			var max_ticks := 600 # safety bound
			var tick := 0
			while tick < max_ticks and done_n < need_n:
				tick += 1
				var still_going := _city_tiles.prewarm_step(focus_pos, prewarm_r)
				var now_built := _city_tiles.built_count()
				if now_built > last_built:
					done_n += (now_built - last_built)
					last_built = now_built
				var frac := clampf(float(done_n) / float(maxi(1, need_n)), 0.0, 1.0)
				_set_startup_progress(
					lerpf(pct_start, tile_end, frac),
					L10n.t("正在预热周边城市区块与渲染缓存 (%d/%d)...", "Pre-warming city chunks & caches (%d/%d)...") % [mini(done_n, need_n), need_n]
				)
				await get_tree().process_frame
				if not still_going:
					break
	if is_run_mode:
		_set_startup_progress(lerpf(tile_end, pct_end, 0.25), L10n.t("正在预热信号灯与道路净空缓存...", "Pre-warming traffic signals & clearance..."))
		await get_tree().process_frame
		if _traffic_sim != null:
			_traffic_sim.prewarm_near(_graph, focus_pos, 520.0)
		_snap_camera_next = true
		_update_camera(0.016)
		_update_run_hud()
		# Render 6 real frames behind the loading overlay so Metal compiles PSOs & uploads GPU buffers!
		for wi in range(6):
			_set_startup_progress(
				lerpf(tile_end, pct_end, 0.35 + 0.65 * (float(wi + 1) / 6.0)),
				L10n.t("正在预热 GPU 着色器与渲染管线...", "Warming GPU shaders & render pipeline...")
			)
			await get_tree().process_frame


func _apply_app_branding() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Use DisplayServer.window_set_title directly — NEVER set Window.title,
	# because Godot's Window::set_title() automatically re-appends " (DEBUG)"!
	DisplayServer.window_set_title("3D train game")
	var icon_img: Image = null
	var icon_tex := load("res://assets/app_icon.png") as Texture2D
	if icon_tex != null:
		icon_img = icon_tex.get_image()
	if icon_img == null or icon_img.is_empty():
		var abs_path := ProjectSettings.globalize_path("res://assets/app_icon.png")
		if FileAccess.file_exists(abs_path):
			icon_img = Image.load_from_file(abs_path)
	if icon_img != null and not icon_img.is_empty():
		DisplayServer.set_icon(icon_img)


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
	var next_key := str(preset["key"])
	var same_city := (_loaded_city_map_key == next_key and _city_root != null and _city_root.get_child_count() > 0 and not _map_data.is_empty())
	_current_map_key = next_key
	if not same_city:
		if _city_tiles != null and is_instance_valid(_city_tiles):
			_city_tiles.finish_pending()
		_map_data = _read_json(str(preset["data_path"]))
		Terrain.load_for(next_key, _map_data.get("areas", []), _map_data.get("graph_edges", [])) # real ground (elevation data)

	var bounds: Array = _map_data.get("bounds", [-520.0, -520.0, 520.0, 520.0])
	_pan_limit_x = maxf(absf(float(bounds[0])), absf(float(bounds[2]))) + 80.0
	_pan_limit_z = maxf(absf(float(bounds[1])), absf(float(bounds[3]))) + 80.0
	_plan_max_height = maxf(1180.0, maxf(float(bounds[2]) - float(bounds[0]), float(bounds[3]) - float(bounds[1])) * 0.78)

	_plan_target = preset["default_target"] as Vector3
	_plan_height = float(preset["default_height"])
	_snap_camera_next = true

	_graph.load_from_map_data(_map_data, use_starter)
	if _city_tiles != null and is_instance_valid(_city_tiles):
		_city_tiles.finish_pending()
	var grade_changed := Terrain.grade_for_tracks(_graph)
	if not same_city or grade_changed:
		_build_city_world()
	else:
		_refresh_land_layers_if_needed()
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
	# 2 cascades over 220m: ~2.5cm texels within 48m of the tram, cutting shadow passes in half!
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_split_1 = 0.22
	_sun.directional_shadow_blend_splits = false
	_sun.directional_shadow_max_distance = 220.0
	_sun.shadow_bias = 0.06
	_sun.shadow_normal_bias = 1.6
	_sun.shadow_blur = 0.9
	add_child(_sun)

	_weather = WeatherSystem.new()
	add_child(_weather)

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
	if _city_tiles != null:
		_city_tiles.finish_pending()
	for c in _city_root.get_children():
		_city_root.remove_child(c)
		c.queue_free()
	if _blueprint_root != null and is_instance_valid(_blueprint_root):
		_blueprint_root.queue_free()
		_blueprint_root = null
	if _underground_landmarks_root != null and is_instance_valid(_underground_landmarks_root):
		_underground_landmarks_root.queue_free()
		_underground_landmarks_root = null
	_underground_view = false
	_city_root.visible = true
	_bld_grid.clear()
	var lm_info := CityBuilder.build_city(
		_city_root,
		_effective_land_data(),
		_building_mat,
		_road_mat,
		_sidewalk_mat,
		_globe_mat
	)
	# Reparent underground landmark concourses (e.g. Jiaxing Station B1 Hall) out of _city_root so they stay
	# crisply visible at B1 (-10m) in Underground X-Ray View (U) for seamless subway interchange planning!
	var b1_hall := _city_root.get_node_or_null("JiaxingLandmarks/JiaxingForestRailwayStation/JiaxingStationB1Hall") as Node3D
	if b1_hall != null:
		_underground_landmarks_root = Node3D.new()
		_underground_landmarks_root.name = "UndergroundLandmarks"
		add_child(_underground_landmarks_root)
		var gtf := b1_hall.global_transform
		b1_hall.get_parent().remove_child(b1_hall)
		_underground_landmarks_root.add_child(b1_hall)
		b1_hall.global_transform = gtf
	_monorail_curve = lm_info.get("monorail_curve")
	_monorail_cars = lm_info.get("monorail_cars", [])
	_spheres_mat = lm_info.get("spheres_mat")
	_night_mats.clear()
	for nm in lm_info.get("night_mats", []):
		_night_mats.append(nm)
	var nm_list: Array = lm_info.get("night_mats", [])
	_shop_mat = nm_list[0] if not nm_list.is_empty() else null
	_built_land_sig = _graph.land_edit_signature()
	_city_lights.clear()
	for l in lm_info.get("lights", []):
		if l is OmniLight3D:
			_city_lights.append(l)
	_city_tiles = null
	if CityTiles.has_tiles(_map_data):
		_city_tiles = CityTiles.new()
		_city_tiles.name = "CityTiles"
		_city_tiles.set_meta("on_terrain", true) # its tiles are put on the ground one by one as they stream in
		_city_root.add_child(_city_tiles)
		_city_tiles.on_tile_built = _on_city_tile_built
		_city_tiles.setup(_effective_land_data(), {"building": _building_mat, "road": _road_mat, "globe": _globe_mat})
		_city_tiles.set_track_context(_graph.get_meta("track_clear_idx", {}), _graph.get_meta("station_bays", []))
	_loaded_city_map_key = _current_map_key


# A streamed map tile is in: clear it for player tracks / station bays and hook up its night lighting
func _on_city_tile_built(tile: Node3D) -> void:
	var bays: Array = _graph.get_meta("station_bays", [])
	var cidx: Dictionary = _graph.get_meta("track_clear_idx", {})
	var cur_ver := _city_tiles.track_ctx_ver if _city_tiles != null else -1
	if int(tile.get_meta("clear_ctx_ver", -2)) != cur_ver:
		CityBuilder.apply_track_clearance(tile, cidx, bays)
	CityBuilder.apply_station_bays(tile, CityBuilder._bays_near(tile, bays), cidx)
	var i := 0
	while i < _city_lights.size():
		if is_instance_valid(_city_lights[i]):
			i += 1
		else:
			_city_lights.remove_at(i)
	for l in tile.get_meta("lights", []):
		if l is OmniLight3D:
			_city_lights.append(l)
	if tile.has_meta("shop_mat"):
		var sm_t = tile.get_meta("shop_mat")
		if sm_t != null and not _night_mats.has(sm_t):
			_night_mats.append(sm_t)
	var lamp_e := _night_factor * 2.05
	for l in tile.get_meta("lights", []):
		if l is OmniLight3D:
			(l as OmniLight3D).visible = lamp_e > 0.02
			(l as OmniLight3D).light_energy = lamp_e
	if tile.has_meta("shop_mat"):
		(tile.get_meta("shop_mat") as ShaderMaterial).set_shader_parameter("night_factor", _night_factor)


# ---------------------------------------------------------------------------------------------
# Player land edits (streets, lanes, demolished buildings, open-ground track): the city's road and building
# layers are rebuilt from the edited graph instead of the raw map.
# ---------------------------------------------------------------------------------------------
func _effective_land_data() -> Dictionary:
	if _graph.road_edits.is_empty() and _graph.demolished_buildings.is_empty():
		return _map_data
	var d := _map_data.duplicate(false)
	if not _graph.road_edits.is_empty():
		var roads: Array = []
		for eid: int in _graph.edges.keys():
			var ed: Dictionary = _graph.edges[eid]
			if bool(ed.get("no_cars", false)):
				continue
			var pts: Array = []
			for p2: Vector2 in ed["pts"]:
				pts.append([p2.x, p2.y])
			roads.append({"name": ed["name"], "width": ed["width"], "lanes_f": ed.get("lanes_f", 1), "lanes_b": ed.get("lanes_b", 1), "layer": 0, "pts": pts})
			if bool(ed.get("bridge", false)):
				roads[roads.size() - 1]["bridge"] = true
		d["roads"] = roads
		# Zebra crossings: keep the map's where a street still runs, add them at the ends of new streets
		var cws: Array = []
		for cw: Dictionary in _map_data.get("crosswalks", []):
			var cp: Array = cw["pos"]
			# 7 m: crossings are placed along the street's chord, so on a curve they sit a few metres off its centreline
			var hit := _graph.find_closest_edge(Vector2(float(cp[0]), float(cp[1])), 7.0, false)
			if not hit.is_empty() and not bool(_graph.edges[int(hit["edge_id"])].get("no_cars", false)):
				cws.append(cw)
		for eid2: int in _graph.edges.keys():
			var ed2: Dictionary = _graph.edges[eid2]
			if not bool(ed2.get("player", false)) or bool(ed2.get("no_cars", false)):
				continue
			var pp: Array = ed2["pts"]
			var p0: Vector2 = pp[0]
			var p1: Vector2 = pp[pp.size() - 1]
			var sl := p0.distance_to(p1)
			if sl < 22.0:
				continue
			var dv := (p1 - p0) / sl
			for end_i in range(2):
				var nid := int(ed2["a"]) if end_i == 0 else int(ed2["b"])
				if (_graph.adj.get(nid, []) as Array).size() < 3:
					continue
				var c := p0 + dv * 7.8 if end_i == 0 else p1 - dv * 7.8
				cws.append({"pos": [c.x, c.y], "dir": [dv.x, dv.y], "width": ed2["width"]})
		d["crosswalks"] = cws
	if not _graph.demolished_buildings.is_empty():
		var blds: Array = (_map_data.get("buildings", []) as Array).duplicate()
		for bi: int in _graph.demolished_buildings.keys():
			if bi >= 0 and bi < blds.size():
				blds[bi] = {"pts": [], "h": 0.0, "demolished": true}
		d["buildings"] = blds
		var sfs: Array = []
		for sf: Dictionary in _map_data.get("storefronts", []):
			if not _graph.demolished_buildings.has(int(sf.get("b", -1))):
				sfs.append(sf)
		d["storefronts"] = sfs
	return d


func _refresh_land_layers_if_needed() -> void:
	if _city_root == null or _graph.land_edit_signature() == _built_land_sig:
		return
	_refresh_land_layers(true, true)


func _refresh_land_layers(roads: bool, buildings: bool) -> void:
	var d_full := _effective_land_data()
	var d := CityTiles.core_subset(d_full)
	if _city_tiles != null:
		_city_tiles.finish_pending() # the builders' shared mesh caches are not touched by two threads at once
	if roads:
		Terrain.rebuild_ground(_city_root)
		CityBuilder.rebuild_area_layer(_city_root, d.get("fill_areas", d_full.get("areas", [])))
		CityBuilder.rebuild_road_layer(_city_root, d.get("roads", []), d.get("crosswalks", []), _road_mat)
	if buildings:
		var sm := CityBuilder.rebuild_building_layer(_city_root, d.get("buildings", []), d.get("storefronts", []), _building_mat)
		if _shop_mat != null:
			_night_mats.erase(_shop_mat)
		_shop_mat = sm
		if sm != null:
			_night_mats.append(sm)
		_apply_lighting_from_clock()
	if _city_tiles != null:
		_city_tiles.update_data(d_full)
	_built_land_sig = _graph.land_edit_signature()


func _after_land_edit(roads: bool, buildings: bool) -> void:
	_refresh_land_layers(roads, buildings)
	_rebuild_tracks_only_visual()
	_mark_modified_and_quick_save()


func _ensure_building_grid() -> void:
	if not _bld_grid.is_empty():
		return
	var blds: Array = _map_data.get("buildings", [])
	for bi in range(blds.size()):
		var pts: Array = (blds[bi] as Dictionary).get("pts", [])
		if pts.size() < 3:
			continue
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for p in pts:
			var v := Vector2(float(p[0]), float(p[1]))
			mn = mn.min(v)
			mx = mx.max(v)
		for gx in range(int(floor(mn.x / 40.0)), int(floor(mx.x / 40.0)) + 1):
			for gz in range(int(floor(mn.y / 40.0)), int(floor(mx.y / 40.0)) + 1):
				var k := Vector2i(gx, gz)
				if not _bld_grid.has(k):
					_bld_grid[k] = []
				(_bld_grid[k] as Array).append(bi)


func _building_poly(bi: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in ((_map_data.get("buildings", []) as Array)[bi] as Dictionary).get("pts", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


# Standing building under point xz (-1 if none)
func _building_at(xz: Vector2) -> int:
	_ensure_building_grid()
	for bi in _bld_grid.get(Vector2i(int(floor(xz.x / 40.0)), int(floor(xz.y / 40.0))), []):
		if _graph.demolished_buildings.has(int(bi)):
			continue
		if Geometry2D.is_point_in_polygon(xz, _building_poly(int(bi))):
			return int(bi)
	return -1


# First standing building the strip pa -> pb (half width hw) runs into, or -1
func _strip_hits_building(pa: Vector2, pb: Vector2, hw: float) -> int:
	_ensure_building_grid()
	var sl := pa.distance_to(pb)
	var dv := (pb - pa) / maxf(sl, 0.001)
	var nv := Vector2(-dv.y, dv.x)
	var seen := {}
	var u := 0.0
	while u <= sl + 0.01:
		for lat: float in [-hw, 0.0, hw]:
			var q := pa + dv * minf(u, sl) + nv * lat
			for bi in _bld_grid.get(Vector2i(int(floor(q.x / 40.0)), int(floor(q.y / 40.0))), []):
				var bii := int(bi)
				if _graph.demolished_buildings.has(bii):
					continue
				if Geometry2D.is_point_in_polygon(q, _building_poly(bii)):
					return bii
				seen[bii] = true
		u += 1.5
	return -1


# Graph edges the new segment pa -> pb crosses away from its own end nodes: [{eid, has_track}]
func _segment_crossings(pa: Vector2, pb: Vector2, na: int, nb: int) -> Array:
	var out: Array = []
	var seen := {}
	var mn := pa.min(pb) - Vector2.ONE * 5.0
	var mx := pa.max(pb) + Vector2.ONE * 5.0
	for eid: int in _graph.edges.keys():
		if seen.has(eid):
			continue
		var ed: Dictionary = _graph.edges[eid]
		if int(ed["a"]) in [na, nb] or int(ed["b"]) in [na, nb]:
			continue
		var pts: Array = ed["pts"]
		var hit := false
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if maxf(a.x, b.x) < mn.x or minf(a.x, b.x) > mx.x or maxf(a.y, b.y) < mn.y or minf(a.y, b.y) > mx.y:
				continue
			var ip = Geometry2D.segment_intersects_segment(pa, pb, a, b)
			if ip != null and (ip as Vector2).distance_to(pa) > 3.0 and (ip as Vector2).distance_to(pb) > 3.0:
				hit = true
				break
		if hit:
			seen[eid] = true
			out.append({"eid": eid, "has_track": _graph.built_tracks.has(eid)})
	return out


func _node_or_point_pos(nid: int, xz: Vector2) -> Vector2:
	return _graph.nodes[nid]["pos"] if nid >= 0 and _graph.nodes.has(nid) else xz


func _get_build_elev() -> float:
	return NetworkGraph.ELEV_PRESETS[clampi(_build_elev_idx, 0, NetworkGraph.ELEV_PRESETS.size() - 1)]


func _active_elev_filter() -> int:
	return -1 if _underground_view else 1


func _set_build_elev_idx(idx: int, auto_view: bool = true) -> void:
	var clamped := clampi(idx, 0, NetworkGraph.ELEV_PRESETS.size() - 1)
	if TrackBuilder.is_monorail_style(_build_bed_style) and clamped == 2:
		# Monorail runs on elevated beams (L1/L2) or underground tunnels (B1/B2), never at ground grade
		clamped = 3 if _build_elev_idx < 2 else 1
		_show_toast(L10n.t("跨座式单轨支持高架 (L1/L2) 与地下隧道 (B1/B2)，自动跳过地面层", "Monorail supports Elevated (L1/L2) & Underground (B1/B2); skipping ground level"))
	_build_elev_idx = clamped
	if auto_view:
		_set_underground_view(_get_build_elev() < -1.5)
	_refresh_build_buttons()


func _step_build_elev(delta: int) -> void:
	var nxt := clampi(_build_elev_idx + delta, 0, NetworkGraph.ELEV_PRESETS.size() - 1)
	if TrackBuilder.is_monorail_style(_build_bed_style) and nxt == 2:
		nxt = clampi(nxt + (1 if delta >= 0 else -1), 0, NetworkGraph.ELEV_PRESETS.size() - 1)
	_set_build_elev_idx(nxt, true)
	_show_toast(L10n.t("建造高程：%s", "Build Elevation: %s") % NetworkGraph.elev_label(_get_build_elev()))


func _set_underground_view(enabled: bool) -> void:
	_underground_view = enabled
	if _city_root != null and is_instance_valid(_city_root):
		_city_root.visible = not enabled
	if enabled:
		_ensure_blueprint_overlay()
	if _blueprint_root != null and is_instance_valid(_blueprint_root):
		_blueprint_root.visible = enabled
	_apply_underground_track_roof_visibility()
	if _btn_underground != null and is_instance_valid(_btn_underground):
		_highlight_active_btn(_btn_underground, enabled)


func _apply_underground_track_roof_visibility() -> void:
	if _track_root == null or not is_instance_valid(_track_root):
		return
	var show_roof := not _underground_view
	var t_roof := _track_root.get_node_or_null("UndergroundTunnelRoofs")
	if t_roof != null and t_roof is Node3D:
		(t_roof as Node3D).visible = show_roof
	for ch in _track_root.get_children():
		if ch is Node3D and str(ch.name).begins_with("Station_"):
			var sr := ch.get_node_or_null("UndergroundStationRoof")
			if sr != null and sr is Node3D:
				(sr as Node3D).visible = show_roof
	if _underground_landmarks_root != null and is_instance_valid(_underground_landmarks_root):
		for uch in _underground_landmarks_root.get_children():
			if uch is Node3D:
				var usr := uch.get_node_or_null("UndergroundStationRoof")
				if usr != null and usr is Node3D:
					(usr as Node3D).visible = show_roof


func _ensure_blueprint_overlay() -> void:
	if _blueprint_root != null and is_instance_valid(_blueprint_root):
		return
	_blueprint_root = Node3D.new()
	_blueprint_root.name = "UndergroundBlueprintOverlay"
	add_child(_blueprint_root)
	# Dark slate subsurface backdrop below B2 (-18m) so tunnels, rails & stations pop cleanly
	var bounds: Array = _map_data.get("bounds", [-600.0, -600.0, 600.0, 600.0])
	var cx := (float(bounds[0]) + float(bounds[2])) * 0.5
	var cz := (float(bounds[1]) + float(bounds[3])) * 0.5
	var sx := (float(bounds[2]) - float(bounds[0])) + 2400.0
	var sz := (float(bounds[3]) - float(bounds[1])) + 2400.0
	var bg_mi := MeshInstance3D.new()
	var bg_p := PlaneMesh.new()
	bg_p.size = Vector2(sx, sz)
	bg_mi.mesh = bg_p
	bg_mi.position = Vector3(cx, -25.0, cz)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.05, 0.07, 0.10)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mi.material_override = bg_mat
	bg_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blueprint_root.add_child(bg_mi)
	# Translucent street-grid reference ribbons at y = +0.05m for clear spatial orientation underground
	var st_road := SurfaceTool.new()
	st_road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_r := false
	for eid: int in _graph.edges.keys():
		var ed: Dictionary = _graph.edges[eid]
		if bool(ed.get("rail_3d", false)):
			continue
		var pts: Array = ed["pts"]
		var hw := 0.85
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := b - a
			if d.length_squared() < 0.04:
				continue
			var nrm := Vector2(-d.y, d.x).normalized() * hw
			var y0 := 0.08 + Terrain.surface(a.x, a.y)
			var y1 := 0.08 + Terrain.surface(b.x, b.y)
			for v: Vector3 in [
				Vector3(a.x - nrm.x, y0, a.y - nrm.y), Vector3(b.x + nrm.x, y1, b.y + nrm.y), Vector3(a.x + nrm.x, y0, a.y + nrm.y),
				Vector3(a.x - nrm.x, y0, a.y - nrm.y), Vector3(b.x - nrm.x, y1, b.y - nrm.y), Vector3(b.x + nrm.x, y1, b.y + nrm.y),
			]:
				st_road.add_vertex(v)
			has_r = true
	if has_r:
		var r_mi := MeshInstance3D.new()
		r_mi.name = "BlueprintStreets"
		r_mi.mesh = st_road.commit()
		var r_mat := StandardMaterial3D.new()
		r_mat.albedo_color = Color(0.26, 0.56, 0.72, 0.34)
		r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		r_mi.material_override = r_mat
		r_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blueprint_root.add_child(r_mi)
	# Translucent water / lake blueprint outlines so Nanhu Lake & canals stay recognizable underground!
	var st_wat := SurfaceTool.new()
	st_wat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_w := false
	for area: Dictionary in _map_data.get("areas", []):
		if str(area.get("kind", "")) != "water":
			continue
		var poly := PackedVector2Array()
		for p in area.get("pts", []):
			poly.append(Vector2(float(p[0]), float(p[1])))
		if poly.size() < 3:
			continue
		var idx := Geometry2D.triangulate_polygon(poly)
		for k in range(0, idx.size(), 3):
			for vi in range(3):
				var vp2 := poly[idx[k + vi]]
				st_wat.add_vertex(Vector3(vp2.x, 0.04, vp2.y))
			has_w = true
	if has_w:
		var w_mi := MeshInstance3D.new()
		w_mi.name = "BlueprintWater"
		w_mi.mesh = st_wat.commit()
		var w_mat := StandardMaterial3D.new()
		w_mat.albedo_color = Color(0.10, 0.38, 0.56, 0.24)
		w_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		w_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		w_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		w_mi.material_override = w_mat
		w_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blueprint_root.add_child(w_mi)


func _sync_portal_cutouts() -> void:
	var raw_list: Array = _graph.get_meta("portal_cutouts", [])
	var count := mini(raw_list.size(), 16)
	var pos_arr: Array[Vector4] = []
	var dir_arr: Array[Vector4] = []
	for i in range(16):
		if i < count:
			var it: Dictionary = raw_list[i]
			var p2: Vector2 = it["pos"]
			var f2: Vector2 = (it["fwd"] as Vector2).normalized()
			pos_arr.append(Vector4(p2.x, p2.y, float(it["hl"]), 0.0))
			dir_arr.append(Vector4(f2.x, f2.y, float(it["hw"]), 0.0))
		else:
			pos_arr.append(Vector4.ZERO)
			dir_arr.append(Vector4.ZERO)
	var mats_to_set: Array = []
	if _sidewalk_mat != null:
		mats_to_set.append(_sidewalk_mat)
	if _road_mat != null:
		mats_to_set.append(_road_mat)
	if _city_root != null and is_instance_valid(_city_root):
		for nm: String in ["ParkAreas", "PlazaAreas", "BrickPlazas"]:
			var nd := _city_root.get_node_or_null(nm)
			if nd is MeshInstance3D and (nd as MeshInstance3D).material_override is ShaderMaterial:
				mats_to_set.append((nd as MeshInstance3D).material_override)
	for sm in mats_to_set:
		var shm := sm as ShaderMaterial
		shm.set_shader_parameter("portal_count", count)
		shm.set_shader_parameter("portal_pos_hl", pos_arr)
		shm.set_shader_parameter("portal_dir_hw", dir_arr)


func _validate_ramp_grade(dist_2d: float, ya: float, yb: float, bed_style: int) -> Dictionary:
	var dh := absf(yb - ya)
	var max_g := NetworkGraph.max_grade_for_style(bed_style)
	if dh < 0.05:
		return {"ok": true, "grade": 0.0, "max_grade": max_g, "min_len": 0.0}
	var g := dh / maxf(dist_2d, 0.1)
	return {"ok": g <= max_g + 0.0005, "grade": g, "max_grade": max_g, "min_len": dh / max_g}


# Height-aware building collision check: underground (<= -3.5m) passes cleanly under all buildings;
# elevated viaducts (>= 3.5m) fly over low structures while rejecting cutting through tall buildings.
func _strip_hits_building_3d(pa: Vector2, pb: Vector2, hw: float, ya: float, yb: float) -> int:
	if maxf(ya, yb) <= -3.5:
		return -1
	_ensure_building_grid()
	var sl := pa.distance_to(pb)
	var dv := (pb - pa) / maxf(sl, 0.001)
	var nv := Vector2(-dv.y, dv.x)
	var blds: Array = _map_data.get("buildings", [])
	var u := 0.0
	while u <= sl + 0.01:
		var frac := clampf(u / maxf(sl, 0.001), 0.0, 1.0)
		var local_y := NetworkGraph.hermite_elev(ya, yb, frac)
		if local_y > -3.5:
			for lat: float in [-hw, 0.0, hw]:
				var q := pa + dv * minf(u, sl) + nv * lat
				for bi in _bld_grid.get(Vector2i(int(floor(q.x / 40.0)), int(floor(q.y / 40.0))), []):
					var bii := int(bi)
					if _graph.demolished_buildings.has(bii):
						continue
					var bh := float((blds[bii] as Dictionary).get("h", 12.0)) if bii < blds.size() else 12.0
					if local_y >= 3.5 and local_y > bh + 1.8:
						continue # viaduct clears this low building roof
					if Geometry2D.is_point_in_polygon(q, _building_poly(bii)):
						return bii
		u += 1.5
	return -1


# Height-aware crossing check: ignores crossings separated vertically by >= ELEV_CLEARANCE_M (4.5m).
func _segment_crossings_3d(pa: Vector2, pb: Vector2, na: int, nb: int, ya: float, yb: float) -> Array:
	var out: Array = []
	var seen := {}
	var mn := pa.min(pb) - Vector2.ONE * 5.0
	var mx := pa.max(pb) + Vector2.ONE * 5.0
	var seg_len := maxf(pa.distance_to(pb), 0.1)
	for eid: int in _graph.edges.keys():
		if seen.has(eid):
			continue
		var ed: Dictionary = _graph.edges[eid]
		if int(ed["a"]) in [na, nb] or int(ed["b"]) in [na, nb]:
			continue
		var pts: Array = ed["pts"]
		var total_e := 0.0
		for i in range(pts.size() - 1):
			total_e += (pts[i] as Vector2).distance_to(pts[i + 1])
		var acc_e := 0.0
		var hit := false
		var same_level := false
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var sl_i := a.distance_to(b)
			if maxf(a.x, b.x) < mn.x or minf(a.x, b.x) > mx.x or maxf(a.y, b.y) < mn.y or minf(a.y, b.y) > mx.y:
				acc_e += sl_i
				continue
			var ip = Geometry2D.segment_intersects_segment(pa, pb, a, b)
			if ip != null and (ip as Vector2).distance_to(pa) > 3.0 and (ip as Vector2).distance_to(pb) > 3.0:
				var p_int := ip as Vector2
				var my_t := clampf(p_int.distance_to(pa) / seg_len, 0.0, 1.0)
				var my_y := NetworkGraph.hermite_elev(ya, yb, my_t)
				var o_t := clampf((acc_e + p_int.distance_to(a)) / maxf(total_e, 0.1), 0.0, 1.0)
				var o_y := _graph.get_edge_elev_at_t(eid, o_t) if _graph.built_tracks.has(eid) else 0.0
				hit = true
				same_level = absf(my_y - o_y) < NetworkGraph.ELEV_CLEARANCE_M
				break
			acc_e += sl_i
		if hit:
			seen[eid] = true
			out.append({"eid": eid, "has_track": _graph.built_tracks.has(eid), "same_level": same_level})
	return out


# 3D Free-Build track (ground / elevated / underground / ramps, light rail & monorail) or new surface road
func _land_chain_click(xz: Vector2, is_road: bool) -> void:
	var lane_cfg := LANE_CFGS[_road_lane_idx]
	var hw := NetworkGraph.row_width_for(_build_track_mode) * 0.5 if not is_road else NetworkGraph.road_width_for(lane_cfg.x, lane_cfg.y) * 0.5
	var target_elev := 0.0 if is_road else _get_build_elev()
	var sys_here := 1 if TrackBuilder.is_monorail_style(_build_bed_style) else 0
	if not _land_prev_has:
		_land_prev_has = true
		_land_prev_xz = xz
		_land_prev_nid = -1
		_land_prev_elev = target_elev
		var snap0 := _graph.find_closest_node(xz, 9.0, 0 if is_road else _active_elev_filter(), NAN if is_road else target_elev)
		if snap0 >= 0:
			_land_prev_xz = _graph.nodes[snap0]["pos"]
			if not is_road:
				var ny0 := _graph.get_node_track_elev(snap0, sys_here, target_elev)
				if not is_nan(ny0):
					_land_prev_elev = ny0
					_land_prev_nid = snap0
		var start_lbl := L10n.t("修建道路", "road") if is_road else (L10n.t("立体轨道 [%s]", "3D track [%s]") % NetworkGraph.elev_label(_land_prev_elev))
		_show_toast(L10n.t("已选起点，继续点击下一点%s（[ / ] 调高程，Esc 结束）", "Start set — click next point for %s ([ / ] change elevation, Esc to finish)") % start_lbl)
		return
	var pa := _node_or_point_pos(_land_prev_nid, _land_prev_xz)
	var snap_b := _graph.find_closest_node(xz, 9.0, 0 if is_road else _active_elev_filter(), NAN if is_road else target_elev)
	var pb: Vector2 = _graph.nodes[snap_b]["pos"] if snap_b >= 0 else xz
	var yb := target_elev
	if not is_road and snap_b >= 0:
		var nyb := _graph.get_node_track_elev(snap_b, sys_here, target_elev)
		if not is_nan(nyb) and absf(nyb - target_elev) <= 1.2:
			yb = nyb
	var seg_dist := pa.distance_to(pb)
	if seg_dist < 10.0:
		_show_toast(L10n.t("⚠ 两点距离太近（至少 10m）", "⚠ Points too close (minimum 10 m)"))
		return
	var ya := 0.0 if is_road else _land_prev_elev
	if not is_road:
		var gr := _validate_ramp_grade(seg_dist, ya, yb, _build_bed_style)
		if not bool(gr["ok"]):
			_show_toast(L10n.t("⚠ 坡度过陡 (%.1f%% > 上限 %.1f%%)：高差 %.1fm 至少需要 %.0fm 水平长度", "⚠ Grade too steep (%.1f%% > max %.1f%%): %.1fm rise needs ≥%.0fm run") % [float(gr["grade"]) * 100.0, float(gr["max_grade"]) * 100.0, absf(yb - ya), float(gr["min_len"])])
			return
	var bi := _strip_hits_building(pa.lerp(pb, 0.04), pb.lerp(pa, 0.04), hw + 0.5) if is_road else _strip_hits_building_3d(pa.lerp(pb, 0.04), pb.lerp(pa, 0.04), hw + 0.5, ya, yb)
	if bi >= 0:
		_show_toast(L10n.t("⚠ 路线穿过建筑，请绕开建筑、切至地下(B1/B2)或先拆除建筑", "⚠ Path hits a building — route around, go underground (B1/B2), or demolish"))
		return
	if is_road:
		for cr: Dictionary in _segment_crossings(pa, pb, _land_prev_nid, snap_b):
			if not bool(_graph.edges[int(cr["eid"])].get("rail_3d", false)):
				_show_toast(L10n.t("⚠ 新建道路不能直接与 %s 交叉：请把道路连接到路口或路段上（点在路上即可接出）", "⚠ Cannot cross %s directly — connect to a junction or mid-block") % L10n.street_display_name(str(_graph.edges[int(cr["eid"])]["name"])))
				return
	else:
		for cr2: Dictionary in _segment_crossings_3d(pa, pb, _land_prev_nid, snap_b, ya, yb):
			if bool(cr2["has_track"]) and bool(cr2["same_level"]):
				_show_toast(L10n.t("⚠ 同高程轨道不能无节点交叉：请连接到路口，或升降至不同高程（如 L2 / B2）立交跨越", "⚠ Cannot cross same-level track mid-span — connect at a node or step to L2/B2"))
				return
	# Resolve both ends to graph nodes
	var na := _land_prev_nid
	var nb := -1
	if is_road:
		if na < 0:
			var ra := _graph.node_for_point(_land_prev_xz, 9.0)
			if ra.has("error"):
				_show_toast(L10n.t("⚠ 起点落在车站或道岔上，请换个位置", "⚠ Start point falls on a station or switch — pick another spot"))
				_land_prev_has = false
				return
			na = int(ra["nid"])
		var rb := _graph.node_for_point(xz, 9.0)
		if rb.has("error"):
			_show_toast(L10n.t("⚠ 终点落在车站或道岔上，请换个位置", "⚠ End point falls on a station or switch — pick another spot"))
			return
		nb = int(rb["nid"])
		var eid_r := _graph.add_road(na, nb, lane_cfg.x, lane_cfg.y, false, _build_track_mode)
		if eid_r < 0:
			_show_toast(L10n.t("⚠ 这两点已经相连或无法连接", "⚠ Points are already connected or invalid"))
			return
		_land_prev_nid = nb
		_land_prev_xz = _graph.nodes[nb]["pos"]
		_after_land_edit(true, false)
		_show_toast(L10n.t("已新建道路（%s · %.0fm）· 继续点击延伸，Esc 结束", "Built road (%s · %.0fm) · Click to extend, Esc to finish") % [_lane_cfg_label(_road_lane_idx), float(_graph.edges[eid_r]["length"])])
		return

	# 3D Rail Edge (ground / elevated / underground / vertical ramp)
	var allow_st_a := absf(ya) <= NetworkGraph.ELEV_CONNECT_TOL
	var allow_st_b := absf(yb) <= NetworkGraph.ELEV_CONNECT_TOL
	if na < 0:
		var ra3 := _graph.node_for_point_3d(_land_prev_xz, ya, 9.0, sys_here, allow_st_a)
		if ra3.has("error"):
			_show_toast(L10n.t("⚠ 起点落在车站或道岔上，请换个位置", "⚠ Start point falls on a station or switch — pick another spot"))
			_land_prev_has = false
			return
		na = int(ra3["nid"])
	var rb3 := _graph.node_for_point_3d(xz, yb, 9.0, sys_here, allow_st_b)
	if rb3.has("error"):
		_show_toast(L10n.t("⚠ 终点落在车站或道岔上，请换个位置", "⚠ End point falls on a station or switch — pick another spot"))
		return
	nb = int(rb3["nid"])
	var eid := _graph.add_3d_rail_edge(na, nb, _build_track_mode, _build_bed_style, ya, yb)
	if eid < 0:
		_show_toast(L10n.t("⚠ 这两点无法连接", "⚠ Points cannot be connected"))
		return
	_land_prev_nid = nb
	_land_prev_xz = _graph.nodes[nb]["pos"]
	_land_prev_elev = yb
	_after_land_edit(false, false)
	var elev_str := NetworkGraph.elev_label(yb) if absf(ya - yb) < 0.05 else ("%s → %s (%.1f%%)" % [NetworkGraph.elev_label(ya), NetworkGraph.elev_label(yb), absf(yb - ya) / maxf(seg_dist, 0.1) * 100.0])
	_show_toast(L10n.t("已建造立体轨道【%s · %s · %s】%.0fm · 继续点击延伸，Esc 结束", "Built 3D track [%s · %s · %s] %.0fm · Click to extend, Esc to finish") % [_track_mode_tag(false), _bed_style_name(_build_bed_style), elev_str, float(_graph.edges[eid]["length"])])


func _rebuild_tracks_and_operations(seed_pax: bool = false, defer_ops: bool = false) -> void:
	# Seattle: offer the real Seattle Center Monorail as a playable line once per save (5th Ave & Stewart
	# -> 5th Ave N & Harrison). Kept off any street the player already built on.
	if _current_map_key == "seattle" and not _graph.monorail_seeded:
		_graph.monorail_seeded = true
		var mono_lid := _graph.seed_seattle_monorail(Vector2(-7.57, 583.6), Vector2(-737.9, -424.2), "seattle-alweg-red")
		if mono_lid > 0:
			_show_toast(L10n.t("🚝 西雅图中心单轨已作为一条线路加入，可在线路列表中选择并驾驶", "🚝 Seattle Center Monorail added — select it from the line list to drive!"))
	for c in _track_root.get_children():
		c.queue_free()

	var built := TrackBuilder.build_network_tracks_and_stations(
		_track_root,
		_graph,
		_cjk_font,
		_grass_track_mat
	)
	_station_views = built["stations"]
	if _pax_sim != null:
		_pax_sim.rebind_station_views(_station_views)
	_put_tracks_on_terrain()
	_sync_landmark_monorail()
	if _city_tiles != null:
		_city_tiles.set_track_context(_graph.get_meta("track_clear_idx", {}), _graph.get_meta("station_bays", []))
	CityBuilder.apply_track_clearance(_city_root, _graph.get_meta("track_clear_idx", {}), _graph.get_meta("station_bays", []))
	CityBuilder.apply_station_bays(_city_root, _graph.get_meta("station_bays", []), _graph.get_meta("track_clear_idx", {}))
	_sync_portal_cutouts()
	_apply_underground_track_roof_visibility()
	_track_lights.clear()
	for l in built["lights"]:
		_track_lights.append(l)

	_clear_accident_fx()
	# Do NOT spawn/simulate trams, traffic cars, or pedestrians while on the Home Screen or in BUILD/PLAN mode!
	if not defer_ops and _game_mode == GameMode.RUN and not _in_home_menu:
		_transit_sim.visible = true
		_pax_sim.visible = true
		_traffic_sim.visible = true
		_pax_sim.reset_for_stations(_station_views)
		if seed_pax:
			_pax_sim.seed_initial_passengers(_graph, 22)
		_transit_sim.rebuild_fleet(_graph, _tram_models, _night_factor)
		if _traffic_sim != null:
			_traffic_sim.rebuild_traffic(_graph, _get_traffic_focus_pos())
		_ops_dirty = false
	else:
		_ops_dirty = true
		if _transit_sim != null:
			_transit_sim.visible = false
		if _pax_sim != null:
			_pax_sim.visible = false
		if _traffic_sim != null:
			_traffic_sim.visible = false
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
			elif ch == _city_tiles:
				continue # the landmark monorail is part of the core city, never of the streamed outer tiles
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
		_show_toast(L10n.t("当前只有一条线路在运营", "Only one line is currently operating"))
	else:
		_show_toast(L10n.t("已切换到线路：%s（%d 列车）", "Switched to %s (%d trams)") % [L10n.line_display_name(str(tr["line_name"])), _transit_sim.line_tram_indices(int(tr["line_id"])).size()])


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
	if _transit_sim != null:
		_transit_sim.visible = false
	if _pax_sim != null:
		_pax_sim.visible = false
	if _traffic_sim != null:
		_traffic_sim.visible = false
	if _sun != null:
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_overlay_root.visible = false
	_hud_layer_ctrl.visible = false
	_home_overlay.visible = true
	_selected_home_map = _current_map_key
	_refresh_home_screen_ui()


func _select_home_map_card(map_key: String) -> void:
	if _startup_loading:
		return
	_selected_home_map = map_key
	_reset_confirm_timer = 0.0
	if _current_map_key != map_key:
		if DisplayServer.get_name() == "headless":
			_load_map_world(map_key, true, false)
			_refresh_home_screen_ui()
		else:
			_async_select_home_map_card(map_key)
		return
	_refresh_home_screen_ui()


func _async_select_home_map_card(map_key: String) -> void:
	var title := _map_title(map_key)
	_begin_loading_overlay(L10n.t("正在切换地图 · %s", "Switching Map · %s") % title, L10n.t("正在解析城市场景与道路网...", "Parsing city scene & street network..."))
	await get_tree().process_frame
	_set_startup_progress(35.0, L10n.t("正在构建 %s 城区场景...", "Building %s city scene...") % title)
	await get_tree().process_frame
	_load_map_world(map_key, true, false)
	_set_startup_progress(88.0, L10n.t("正在刷新地图预览...", "Refreshing map preview..."))
	await get_tree().process_frame
	_refresh_home_screen_ui()
	_end_loading_overlay()


func _apply_run_signal_priority(run_data: Dictionary) -> void:
	if run_data.has("global_signal_priority"):
		_graph.global_signal_priority = bool(run_data["global_signal_priority"])
	var line_tsp_raw = run_data.get("line_signal_priority", {})
	if line_tsp_raw is Dictionary:
		for k in (line_tsp_raw as Dictionary).keys():
			_graph.set_line_signal_priority(int(k), bool((line_tsp_raw as Dictionary)[k]))


func _async_enter_saved_world(
	map_key: String,
	save_data: Dictionary,
	run_data: Dictionary,
	target_mode: int,
	toast_msg: String,
	save_as_current: bool = false
) -> void:
	var title := _map_title(map_key)
	_begin_loading_overlay(L10n.t("正在进入 %s", "Entering %s") % title, L10n.t("正在读取存档数据...", "Loading save data..."))
	await get_tree().process_frame

	if _current_map_key != map_key or _map_data.is_empty():
		_set_startup_progress(14.0, L10n.t("正在载入 %s 城市地形与建筑数据...", "Loading %s terrain & buildings...") % title)
		await get_tree().process_frame
		_load_map_world(map_key, false, false)

	_set_startup_progress(26.0, L10n.t("正在解析轨道网络与线路规划...", "Parsing track network & lines..."))
	await get_tree().process_frame
	var net: Dictionary = save_data.get("network", {})
	_graph.import_state(net)

	_set_startup_progress(36.0, L10n.t("正在整平轨道地势与纵断面坡度...", "Grading trackbeds & elevation..."))
	await get_tree().process_frame
	if _city_tiles != null and is_instance_valid(_city_tiles):
		_city_tiles.finish_pending()
	var grade_changed := Terrain.grade_for_tracks(_graph)
	if grade_changed:
		_set_startup_progress(46.0, L10n.t("正在按整平后地形重建城区地面、公园与道路...", "Rebuilding city ground, parks & roads..."))
		await get_tree().process_frame
		_build_city_world()
	elif _graph.land_edit_signature() != _built_land_sig:
		_set_startup_progress(46.0, L10n.t("正在同步道路与建筑改造层...", "Syncing road & lot edits..."))
		await get_tree().process_frame
		_refresh_land_layers_if_needed()

	_pax_sim.set_spawn_level(int(save_data.get("pax_spawn_level", 3)))
	_pax_sim.total_delivered = int(save_data.get("total_delivered", 0))
	if _btn_pax_rate != null:
		_btn_pax_rate.text = L10n.t("客流: %s (P)", "Pax: %s (P)") % PassengerSim.spawn_level_name(_pax_sim.spawn_level)
	_set_time_hours(float(save_data.get("time_hours", 13.5)))
	_set_weather_mode(int(save_data.get("weather", WeatherSystem.WeatherType.SUNNY)), false)
	if not run_data.is_empty():
		_apply_run_signal_priority(run_data)

	_set_startup_progress(58.0, L10n.t("正在铺设轨道、道岔与车站...", "Laying tracks, switches & stations..."))
	await get_tree().process_frame
	_rebuild_tracks_and_operations(not _graph.lines.is_empty(), true)
	if save_as_current:
		SaveManager.save_current(map_key, save_data)

	var enter_run := (target_mode == GameMode.RUN)
	if enter_run:
		_set_startup_progress(68.0, L10n.t("正在编组上线电车与站台客流...", "Spawning fleet & station passengers..."))
		await get_tree().process_frame
		_transit_sim.line_ai_styles.clear()
		_transit_sim.rebuild_fleet(_graph, _tram_models, _night_factor)
		_pax_sim.reset_for_stations(_station_views)
		_pax_sim.seed_initial_passengers(_graph, 20)
		if not run_data.is_empty():
			_set_startup_progress(74.0, L10n.t("正在恢复运行存档列车位置与配置...", "Restoring run save state & settings..."))
			await get_tree().process_frame
			_pax_sim.set_spawn_level(int(run_data.get("pax_spawn_level", _pax_sim.spawn_level)))
			_pax_sim.total_delivered = int(run_data.get("total_delivered", 0))
			if _btn_pax_rate != null:
				_btn_pax_rate.text = L10n.t("客流: %s (P)", "Pax: %s (P)") % PassengerSim.spawn_level_name(_pax_sim.spawn_level)
			_set_time_hours(float(run_data.get("time_hours", _time_hours)))
			_set_weather_mode(int(run_data.get("weather", _weather_mode)), false)
			_apply_run_signal_priority(run_data)
			_transit_sim.import_run_state(run_data.get("transit", {}), _graph)
		_set_startup_progress(79.0, L10n.t("正在构建交通信号系统与街道车流...", "Building signals & street traffic..."))
		await get_tree().process_frame
		var focus_pos := _get_traffic_focus_pos()
		_traffic_sim.rebuild_traffic(_graph, focus_pos)
		_ops_dirty = false
		_set_game_mode(GameMode.RUN)
		await _prewarm_city_and_gpu(focus_pos, true, 82.0, 99.0)
	else:
		_set_game_mode(target_mode)
		await _prewarm_city_and_gpu(_plan_target, false, 78.0, 99.0)

	_end_loading_overlay()
	if not toast_msg.is_empty():
		_show_toast(toast_msg)


func _async_enter_fresh_world(
	map_key: String,
	use_starter: bool,
	seed_pax: bool,
	target_mode: int,
	toast_msg: String,
	set_chase: bool = false,
	save_progress: bool = false
) -> void:
	var title := _map_title(map_key)
	_begin_loading_overlay(L10n.t("正在进入 %s", "Entering %s") % title, L10n.t("正在准备地图与道路网...", "Preparing map & road network..."))
	await get_tree().process_frame

	_set_startup_progress(35.0, L10n.t("正在构建 %s 城区与轨道网络...", "Building %s city & track network...") % title)
	await get_tree().process_frame
	_load_map_world(map_key, use_starter, seed_pax)
	_pax_sim.total_delivered = 0

	if target_mode == GameMode.RUN:
		_set_startup_progress(64.0, L10n.t("正在编组上线电车、乘客与街道交通...", "Spawning fleet, passengers & street traffic..."))
		await get_tree().process_frame
		_set_game_mode(GameMode.RUN)
		if set_chase:
			_set_cam_mode(CamMode.CHASE)
		await _prewarm_city_and_gpu(_get_traffic_focus_pos(), true, 75.0, 99.0)
	else:
		_set_game_mode(target_mode)
		if save_progress:
			_save_current_progress(false)
		await _prewarm_city_and_gpu(_plan_target, false, 75.0, 99.0)

	_end_loading_overlay()
	if not toast_msg.is_empty():
		_show_toast(toast_msg)


func _start_map_continue_or_new() -> void:
	if _startup_loading:
		return
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
		var msg := L10n.t("✓ 已继续驾驶【%s】运行存档（槽位 %02d · 已送达 %d 人）", "✓ Resumed [%s] run save (Slot %02d · %d delivered)") % [
			_map_title(mkey),
			_active_plan_slot_idx + 1,
			int(run_data.get("total_delivered", 0)),
		]
		if DisplayServer.get_name() == "headless":
			_apply_loaded_save_state(mkey, bp_data)
			_apply_run_signal_priority(run_data)
			_set_game_mode(GameMode.RUN)
			_pax_sim.set_spawn_level(int(run_data.get("pax_spawn_level", _pax_sim.spawn_level)))
			_pax_sim.total_delivered = int(run_data.get("total_delivered", 0))
			if _btn_pax_rate != null:
				_btn_pax_rate.text = L10n.t("客流: %s (P)", "Pax: %s (P)") % PassengerSim.spawn_level_name(_pax_sim.spawn_level)
			_set_time_hours(float(run_data.get("time_hours", _time_hours)))
			_set_weather_mode(int(run_data.get("weather", _weather_mode)), false)
			_transit_sim.import_run_state(run_data.get("transit", {}), _graph)
			_show_toast(msg)
		else:
			_async_enter_saved_world(mkey, bp_data, run_data, GameMode.RUN, msg)
	elif not saved.is_empty():
		var net_lines: Array = (saved.get("network", {}) as Dictionary).get("lines", [])
		var start_mode := GameMode.RUN if not net_lines.is_empty() else GameMode.BUILD
		var msg := L10n.t("✓ 已继续【%s】上次进度", "✓ Resumed [%s] last progress") % _map_title(mkey)
		if DisplayServer.get_name() == "headless":
			_apply_loaded_save_state(mkey, saved)
			_set_game_mode(GameMode.RUN if not _graph.lines.is_empty() else GameMode.BUILD)
			_show_toast(msg)
		else:
			_async_enter_saved_world(mkey, saved, {}, start_mode, msg)
	else:
		var msg := L10n.t("已进入【%s】空白沙盒 · 左键铺设轨道，按下触摸板左右滑动平移地图", "Entered [%s] sandbox · Click to lay tracks, drag to pan map") % _map_title(mkey)
		if DisplayServer.get_name() == "headless":
			_load_map_world(mkey, false, false)
			_pax_sim.total_delivered = 0
			_set_game_mode(GameMode.BUILD)
			_save_current_progress(false)
			_show_toast(msg)
		else:
			_async_enter_fresh_world(mkey, false, false, GameMode.BUILD, msg, false, true)


func _start_map_demo_network() -> void:
	if _startup_loading:
		return
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
	var msg := L10n.t("✓ 已进入【%s】示例线网！注意弯道/道岔限速与路口小车（超速翻车或撞车将结束本局）", "✓ Entered [%s] Demo Network! Watch curve/switch speed limits and crossing traffic.") % _map_title(mkey)
	if DisplayServer.get_name() == "headless":
		_load_map_world(mkey, true, true)
		_pax_sim.total_delivered = 0
		_set_game_mode(GameMode.RUN)
		_set_cam_mode(CamMode.CHASE)
		_show_toast(msg)
	else:
		_async_enter_fresh_world(mkey, true, true, GameMode.RUN, msg, true, false)


func _handle_home_reset_button() -> void:
	if _startup_loading:
		return
	var mkey := _selected_home_map
	if _reset_confirm_timer <= 0.0:
		_reset_confirm_timer = 3.6
		_btn_home_reset.text = L10n.t("确认清空重开？", "Confirm Reset?")
		return

	_reset_confirm_timer = 0.0
	var prev := SaveManager.load_current(mkey)
	if not prev.is_empty():
		SaveManager.push_autosave(mkey, L10n.t("重开前自动备份", "Pre-reset Backup"), prev)
	SaveManager.delete_current(mkey)

	_is_demo_readonly = false
	_started_from_demo = false
	_game_over = false
	_gameover_modal.visible = false
	_in_home_menu = false
	_home_overlay.visible = false
	_hud_layer_ctrl.visible = true
	_nav_bar.visible = true
	var msg := L10n.t("已清空并重新开始【%s】", "Reset [%s] map") % _map_title(mkey)
	if DisplayServer.get_name() == "headless":
		_load_map_world(mkey, false, false)
		_pax_sim.total_delivered = 0
		_set_game_mode(GameMode.BUILD)
		_save_current_progress(false)
		_show_toast(msg)
	else:
		_async_enter_fresh_world(mkey, false, false, GameMode.BUILD, msg, false, true)


func _apply_loaded_save_state(map_key: String, save_data: Dictionary) -> void:
	if _current_map_key != map_key or _map_data.is_empty():
		_load_map_world(map_key, false, false)
	var net: Dictionary = save_data.get("network", {})
	_graph.import_state(net)
	if _city_tiles != null and is_instance_valid(_city_tiles):
		_city_tiles.finish_pending()
	if Terrain.grade_for_tracks(_graph):
		_build_city_world()
	else:
		_refresh_land_layers_if_needed()
	_pax_sim.set_spawn_level(int(save_data.get("pax_spawn_level", 3)))
	_pax_sim.total_delivered = int(save_data.get("total_delivered", 0))
	if _btn_pax_rate != null:
		_btn_pax_rate.text = L10n.t("客流: %s (P)", "Pax: %s (P)") % PassengerSim.spawn_level_name(_pax_sim.spawn_level)
	_set_time_hours(float(save_data.get("time_hours", 13.5)))
	_set_weather_mode(int(save_data.get("weather", WeatherSystem.WeatherType.SUNNY)), false)
	_transit_sim.line_ai_styles.clear()
	_rebuild_tracks_and_operations(not _graph.lines.is_empty())


func _build_current_save_payload(slot_name: String) -> Dictionary:
	return SaveManager.build_payload(
		_current_map_key,
		slot_name,
		_graph,
		_pax_sim.spawn_level,
		_time_hours,
		_pax_sim.total_delivered,
		_weather_mode
	)


func _save_current_progress(show_msg: bool = false) -> void:
	var payload := _build_current_save_payload(L10n.t("当前进度", "Current Progress"))
	SaveManager.save_current(_current_map_key, payload)
	if show_msg:
		_show_toast(L10n.t("✓ 已自动保存当前进度", "✓ Progress autosaved"))


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
				badge_lbl.text = L10n.t(
					"● 已有进度：轨道 %d 段 · 车站 %d 座 · 线路 %d 条\n   上次保存：%s",
					"● Saved: %d track segs · %d stations · %d lines\n   Last saved: %s"
				) % [
					int(summary["tracks"]),
					int(summary["stations"]),
					int(summary["lines"]),
					str(summary["saved_at"]),
				]
				badge_lbl.add_theme_color_override("font_color", Color(0.46, 0.92, 0.70))
			else:
				badge_lbl.text = L10n.t(
					"○ 暂无本地存档\n   可点击【开始建设】从零规划，或进入【示例线网】试驾",
					"○ No local save yet\n   Click [Start Building] or [Try Demo Network]"
				)
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
			if is_sel and _home_cards_scroll != null and is_instance_valid(_home_cards_scroll):
				_home_cards_scroll.call_deferred("ensure_control_visible", card_pc)

	var sel_sum := SaveManager.get_current_summary(_selected_home_map)
	var latest_run := SaveManager.get_latest_run_slot(_selected_home_map)
	var has_run := bool(latest_run.get("exists", false))
	var has_cur := bool(sel_sum["exists"]) or has_run
	var map_title := _map_title(_selected_home_map)
	if has_run:
		_btn_home_primary.text = L10n.t("▶ 继续驾驶（%s · 运行档）", "▶ Resume Run (%s)") % map_title
	elif has_cur:
		_btn_home_primary.text = L10n.t("▶ 继续游戏（%s）", "▶ Continue (%s)") % map_title
	else:
		_btn_home_primary.text = L10n.t("▶ 开始建设（%s）", "▶ Start Building (%s)") % map_title
	_btn_home_reset.visible = has_cur
	if _reset_confirm_timer <= 0.0:
		_btn_home_reset.text = L10n.t("重新开始", "Reset Map")


# Label that takes the spare row width but never forces the row wider (long text ends in "…")
func _fit_label(lbl: Label) -> void:
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.custom_minimum_size = Vector2(40, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS


func _refresh_slot_modal_ui() -> void:
	if _slot_modal == null or not _slot_modal.visible:
		return
	var map_title := _map_title(_slot_modal_map_key)
	_lbl_slot_title.text = L10n.t("存档管理 · %s", "Save Manager · %s") % map_title
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
		_fit_label(info_lbl)
		info_lbl.text = str(s_info["name"])
		info_lbl.tooltip_text = info_lbl.text
		info_lbl.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98) if exists else Color(0.58, 0.62, 0.68))
		hbox.add_child(info_lbl)
		if exists:
			var meta_lbl := Label.new()
			_fit_label(meta_lbl)
			meta_lbl.text = L10n.t("      轨道 %d · 车站 %d · 线路 %d · %s", "      Tracks %d · Stations %d · Lines %d · %s") % [
				int(s_info["tracks"]),
				int(s_info["stations"]),
				int(s_info["lines"]),
				str(s_info["saved_at"]),
			]
			meta_lbl.add_theme_font_size_override("font_size", 12)
			meta_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.75))
			row_vbox.add_child(meta_lbl)

		if can_save_here:
			var idx_save := idx
			var save_btn := _make_btn(L10n.t("覆盖", "Overwrite") if exists else L10n.t("保存规划", "Save Plan"), func():
				var custom_nm := _edit_slot_name.text.strip_edges()
				var payload := _build_current_save_payload(custom_nm)
				if SaveManager.save_manual_slot(_current_map_key, idx_save, custom_nm, payload):
					_active_plan_slot_idx = idx_save
					_is_demo_readonly = false
					SaveManager.save_current(_current_map_key, payload)
					_edit_slot_name.text = ""
					_refresh_slot_modal_ui()
					_show_toast(L10n.t("✓ 已保存建设规划至槽位 %02d", "✓ Plan saved to Slot %02d") % (idx_save + 1))
			)
			hbox.add_child(save_btn)

		if exists:
			var idx_load := idx
			var is_auto_load := is_auto_tab
			var mkey_load := _slot_modal_map_key
			hbox.add_child(_make_btn(L10n.t("读取", "Load"), func():
				if _startup_loading:
					return
				if not _in_home_menu and not _is_demo_readonly:
					SaveManager.push_autosave(_current_map_key, L10n.t("读档前自动备份", "Pre-load Backup"), _build_current_save_payload(L10n.t("读档前备份", "Pre-load Backup")))
				var loaded := SaveManager.load_slot(mkey_load, is_auto_load, idx_load)
				if not loaded.is_empty():
					if not is_auto_load:
						_active_plan_slot_idx = idx_load
					_is_demo_readonly = false
					_in_home_menu = false
					_slot_modal.visible = false
					_home_overlay.visible = false
					_hud_layer_ctrl.visible = true
					_nav_bar.visible = true
					var net_lines: Array = (loaded.get("network", {}) as Dictionary).get("lines", [])
					var t_mode := GameMode.RUN if not net_lines.is_empty() else GameMode.BUILD
					var msg := L10n.t("✓ 已读取建设规划：%s", "✓ Loaded plan: %s") % str(loaded.get("name", ""))
					if DisplayServer.get_name() == "headless":
						_apply_loaded_save_state(mkey_load, loaded)
						SaveManager.save_current(mkey_load, loaded)
						_set_game_mode(GameMode.RUN if not _graph.lines.is_empty() else GameMode.BUILD)
						_show_toast(msg)
					else:
						_async_enter_saved_world(mkey_load, loaded, {}, t_mode, msg, true)
			))

			var idx_del := idx
			var is_auto_del := is_auto_tab
			var mkey_del := _slot_modal_map_key
			var del_btn := _make_btn(L10n.t("删除", "Delete"), func():
				SaveManager.delete_slot(mkey_del, is_auto_del, idx_del)
				_refresh_slot_modal_ui()
				_show_toast(L10n.t("已删除槽位 %02d（关联运行存档已同步删除）", "Deleted Slot %02d (and linked run saves)") % (idx_del + 1))
			)
			if not is_auto_del:
				del_btn.tooltip_text = L10n.t("删除该建设规划及其 3 个运行档", "Delete this plan save and its 3 run saves")
			hbox.add_child(del_btn)

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
					indent.text = L10n.t("   ↳ 运行档%d", "   ↳ Run %d") % (si + 1)
					indent.add_theme_font_size_override("font_size", 12)
					indent.add_theme_color_override("font_color", Color(0.46, 0.86, 0.96) if rexists else Color(0.50, 0.56, 0.62))
					sub_row.add_child(indent)

					var r_lbl := Label.new()
					_fit_label(r_lbl)
					r_lbl.add_theme_font_size_override("font_size", 12)
					if rexists:
						r_lbl.text = L10n.t("送达 %d 人 · %s", "%d delivered · %s") % [int(rs.get("delivered", 0)), str(rs.get("saved_at", ""))]
						r_lbl.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0))
					else:
						r_lbl.text = L10n.t("空", "Empty")
						r_lbl.add_theme_color_override("font_color", Color(0.52, 0.56, 0.62))
					r_lbl.tooltip_text = r_lbl.text
					sub_row.add_child(r_lbl)

					if can_save_here and _game_mode == GameMode.RUN and not _transit_sim.trams.is_empty():
						var p_s := idx
						var s_s := si
						sub_row.add_child(_make_btn(L10n.t("覆盖", "Overwrite") if rexists else L10n.t("保存运行", "Save Run"), func():
							_save_run_progress_to_slot(p_s, s_s)
							_refresh_slot_modal_ui()
						))

					if rexists:
						var p_l := idx
						var s_l := si
						var mkey_rl := _slot_modal_map_key
						sub_row.add_child(_make_btn(L10n.t("继续驾驶", "Resume"), func():
							if _startup_loading:
								return
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
								var msg := L10n.t("✓ 已继续驾驶规划 %02d · 运行档 %d（送达 %d 人）", "✓ Resumed Plan %02d · Run %d (%d delivered)") % [p_l + 1, s_l + 1, int(rd.get("total_delivered", 0))]
								if DisplayServer.get_name() == "headless":
									_apply_loaded_save_state(mkey_rl, bp)
									_apply_run_signal_priority(rd)
									_set_game_mode(GameMode.RUN)
									_set_time_hours(float(rd.get("time_hours", _time_hours)))
									_set_weather_mode(int(rd.get("weather", _weather_mode)), false)
									_pax_sim.set_spawn_level(int(rd.get("pax_spawn_level", _pax_sim.spawn_level)))
									_pax_sim.total_delivered = int(rd.get("total_delivered", 0))
									if _btn_pax_rate != null:
										_btn_pax_rate.text = L10n.t("客流: %s (P)", "Pax: %s (P)") % PassengerSim.spawn_level_name(_pax_sim.spawn_level)
									_transit_sim.import_run_state(rd.get("transit", {}), _graph)
									_show_toast(msg)
								else:
									_async_enter_saved_world(mkey_rl, bp, rd, GameMode.RUN, msg)
						))

						var p_d := idx
						var s_d := si
						var mkey_rd := _slot_modal_map_key
						sub_row.add_child(_make_btn(L10n.t("删除", "Delete"), func():
							SaveManager.delete_run_slot(mkey_rd, p_d, s_d)
							_refresh_slot_modal_ui()
							_show_toast(L10n.t("已删除规划 %02d · 运行档 %d", "Deleted Plan %02d · Run %d") % [p_d + 1, s_d + 1])
						))


func _request_game_mode(mode: int) -> void:
	if _startup_loading:
		return
	if mode == GameMode.RUN and _game_mode != GameMode.RUN and DisplayServer.get_name() != "headless":
		_async_enter_run_mode()
		return
	_set_game_mode(mode)


func _async_enter_run_mode() -> void:
	var need_rebuild := _ops_dirty or _transit_sim.trams.is_empty()
	_begin_loading_overlay(L10n.t("正在进入运行与驾驶模式", "Entering Run & Drive Mode"), L10n.t("正在准备运营环境...", "Preparing simulation..."))
	await get_tree().process_frame

	if need_rebuild:
		_draft_station_ids.clear()
		_editing_line_id = -1
		_draft_insert_idx = -1
		_route_preview_mi.mesh = null
		_set_startup_progress(22.0, L10n.t("正在编组上线电车与编译线路...", "Spawning fleet & compiling routes..."))
		await get_tree().process_frame
		_transit_sim.rebuild_fleet(_graph, _tram_models, _night_factor)

		_set_startup_progress(45.0, L10n.t("正在初始化站台候车客流...", "Seeding station passengers..."))
		await get_tree().process_frame
		_pax_sim.reset_for_stations(_station_views)
		_pax_sim.seed_initial_passengers(_graph, 20)

		_set_startup_progress(62.0, L10n.t("正在构建交通信号系统与街道车流...", "Building signals & street traffic..."))
		await get_tree().process_frame
		_traffic_sim.rebuild_traffic(_graph, _get_traffic_focus_pos())
		_ops_dirty = false
	else:
		_set_startup_progress(45.0, L10n.t("正在恢复列车运营与视角...", "Restoring operations & camera..."))
		await get_tree().process_frame

	_set_game_mode(GameMode.RUN)
	var focus_pos := _get_traffic_focus_pos()
	await _prewarm_city_and_gpu(focus_pos, true, 66.0 if need_rebuild else 55.0, 99.0)
	_end_loading_overlay()


func _set_game_mode(mode: int) -> void:
	var prev_mode := _game_mode
	_game_mode = mode
	if _run_paused:
		_set_run_paused(false)
	_path_start_node = -1
	_preview_mi.mesh = null
	_last_ann_approach_sid = -1
	_last_ann_door_open = false
	if _btn_quick_save_run != null:
		_btn_quick_save_run.visible = (_game_mode == GameMode.RUN)
	_sound.set_menu_silenced(_startup_loading or _in_home_menu or _game_mode != GameMode.RUN)

	if _game_mode == GameMode.RUN:
		_transit_sim.visible = true
		_pax_sim.visible = true
		_traffic_sim.visible = true
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		if _ops_dirty or _transit_sim.trams.is_empty():
			_draft_station_ids.clear()
			_editing_line_id = -1
			_draft_insert_idx = -1
			_route_preview_mi.mesh = null
			_transit_sim.rebuild_fleet(_graph, _tram_models, _night_factor)
			_pax_sim.reset_for_stations(_station_views)
			_pax_sim.seed_initial_passengers(_graph, 20)
			_traffic_sim.rebuild_traffic(_graph, _get_traffic_focus_pos())
			_ops_dirty = false
		if _cam_mode == CamMode.BIRD and not _transit_sim.trams.is_empty():
			_set_cam_mode(CamMode.CHASE)

	if _game_mode in [GameMode.BUILD, GameMode.PLAN]:
		var active_tr := _transit_sim.get_active_tram()
		if prev_mode == GameMode.RUN and not active_tr.is_empty():
			var secs: Array = active_tr["tram_info"]["sections"]
			if not secs.is_empty():
				var p := (secs[0] as Node3D).global_position
				_plan_target = Vector3(p.x, 0.0, p.z)
		# Hide trams, cars & pedestrians while building/planning (saves thousands of nodes & shadow passes!)
		_transit_sim.visible = false
		_pax_sim.visible = false
		_traffic_sim.visible = false
		_camera.fov = 46.0
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_sun.directional_shadow_max_distance = 540.0
	else:
		_sun.directional_shadow_max_distance = 480.0 if _cam_mode == CamMode.BIRD else 220.0

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


func _set_weather_mode(mode: int, show_msg: bool = true) -> void:
	_weather_mode = clampi(mode, 0, 2)
	if _weather != null:
		_weather.set_weather(_weather_mode)
	_apply_lighting_from_clock()
	_refresh_weather_buttons()
	if show_msg:
		var msg_desc := L10n.t("蓝天晴朗", "Clear skies") if _weather_mode == WeatherSystem.WeatherType.SUNNY else (
			L10n.t("多云阴沉 · 柔和漫射光", "Overcast clouds · soft diffuse light") if _weather_mode == WeatherSystem.WeatherType.CLOUDY else
			L10n.t("细雨绵绵 · 开启雨景与雨声", "Steady rainfall · rain visuals & ambience")
		)
		_show_toast(L10n.t("天气已切换为：%s（%s）", "Weather set to: %s (%s)") % [WeatherSystem.weather_button_label(_weather_mode), msg_desc])


func _cycle_weather_mode() -> void:
	_set_weather_mode((_weather_mode + 1) % 3, true)


func _refresh_weather_buttons() -> void:
	if _btn_weather != null and is_instance_valid(_btn_weather):
		_btn_weather.text = WeatherSystem.weather_button_label(_weather_mode)
		_highlight_active_btn(_btn_weather, _weather_mode != WeatherSystem.WeatherType.SUNNY)
	for wi in range(_settings_weather_btns.size()):
		var wb := _settings_weather_btns[wi]
		if wb != null and is_instance_valid(wb):
			_highlight_active_btn(wb, _weather_mode == wi)


func _apply_lighting_from_clock() -> void:
	var env := _world_env.environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial

	var hour_angle := ((_time_hours - 13.0) / 12.0) * PI
	var elev_deg := cos(hour_angle) * 56.0
	var azim_deg := -110.0 + ((_time_hours - 6.0) / 14.0) * 155.0

	var day_fac := smoothstep(-4.0, 14.0, elev_deg)
	var dusk_fac := smoothstep(20.0, 1.0, elev_deg) * smoothstep(-6.0, 1.0, elev_deg)
	_night_factor = smoothstep(9.0, -5.0, elev_deg)

	var is_cloudy := (_weather_mode == WeatherSystem.WeatherType.CLOUDY)
	var is_rainy := (_weather_mode == WeatherSystem.WeatherType.RAINY)
	var overcast_amt := 1.0 if is_rainy else (0.72 if is_cloudy else 0.0)

	# Base sunny sky colors
	var sunny_top := Color(0.025, 0.035, 0.065).lerp(Color(0.32, 0.52, 0.78), day_fac).lerp(Color(0.18, 0.26, 0.46), dusk_fac * 0.75)
	var sunny_hor := Color(0.055, 0.075, 0.12).lerp(Color(0.76, 0.82, 0.89), day_fac).lerp(Color(0.94, 0.58, 0.36), dusk_fac * 0.85)
	# Overcast / Rainy sky colors (cool moody grey-blue in daytime, dark slate at night)
	var cloud_top := Color(0.028, 0.036, 0.052).lerp(Color(0.42, 0.46, 0.52), day_fac).lerp(Color(0.30, 0.30, 0.34), dusk_fac * 0.65)
	var cloud_hor := Color(0.058, 0.070, 0.095).lerp(Color(0.64, 0.67, 0.71), day_fac).lerp(Color(0.54, 0.46, 0.43), dusk_fac * 0.60)
	var rain_top := Color(0.018, 0.024, 0.038).lerp(Color(0.28, 0.33, 0.39), day_fac).lerp(Color(0.20, 0.22, 0.27), dusk_fac * 0.55)
	var rain_hor := Color(0.042, 0.054, 0.076).lerp(Color(0.48, 0.53, 0.59), day_fac).lerp(Color(0.35, 0.34, 0.38), dusk_fac * 0.50)

	if is_rainy:
		sky_mat.sky_top_color = rain_top
		sky_mat.sky_horizon_color = rain_hor
		sky_mat.sky_curve = 0.30
		sky_mat.sun_angle_max = 88.0
	elif is_cloudy:
		sky_mat.sky_top_color = cloud_top
		sky_mat.sky_horizon_color = cloud_hor
		sky_mat.sky_curve = 0.22
		sky_mat.sun_angle_max = 62.0
	else:
		sky_mat.sky_top_color = sunny_top
		sky_mat.sky_horizon_color = sunny_hor
		sky_mat.sky_curve = 0.12
		sky_mat.sun_angle_max = 30.0

	# Below the horizon the sky continues as distant haze over Elliott Bay (no dark band past the far plane)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.lerp(Color(0.30, 0.40, 0.46), 0.25 * day_fac)
	sky_mat.ground_bottom_color = Color(0.03, 0.03, 0.04).lerp(Color(0.28, 0.28, 0.27) if not is_rainy else Color(0.18, 0.20, 0.22), day_fac)

	if elev_deg > -2.5:
		_sun.rotation_degrees = Vector3(-maxf(elev_deg, 2.0), azim_deg, 0.0)
		var base_sun_col := Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.66, 0.38), dusk_fac)
		var base_sun_e := lerpf(0.08, 2.35, smoothstep(-2.5, 18.0, elev_deg))
		if is_rainy:
			_sun.light_color = base_sun_col.lerp(Color(0.76, 0.82, 0.90), 0.78)
			_sun.light_energy = base_sun_e * 0.20
			_sun.shadow_opacity = 0.32
		elif is_cloudy:
			_sun.light_color = base_sun_col.lerp(Color(0.86, 0.89, 0.93), 0.58)
			_sun.light_energy = base_sun_e * 0.38
			_sun.shadow_opacity = 0.50
		else:
			_sun.light_color = base_sun_col
			_sun.light_energy = base_sun_e
			_sun.shadow_opacity = 1.0
	else:
		_sun.rotation_degrees = Vector3(-48.0, 125.0, 0.0)
		_sun.light_color = Color(0.68, 0.72, 0.82)
		_sun.light_energy = 0.14 if is_rainy else (0.18 if is_cloudy else 0.24)
		_sun.shadow_opacity = 0.45 if overcast_amt > 0.0 else 1.0

	if is_rainy:
		env.ambient_light_color = Color(0.15, 0.17, 0.22).lerp(Color(0.56, 0.61, 0.68), day_fac)
		env.ambient_light_energy = lerpf(0.42, 0.76, day_fac)
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = 38.0
		env.fog_depth_end = 310.0
		env.fog_density = 0.68
		env.fog_sky_affect = 0.55
		env.fog_light_color = sky_mat.sky_horizon_color
	elif is_cloudy:
		env.ambient_light_color = Color(0.18, 0.20, 0.24).lerp(Color(0.70, 0.73, 0.77), day_fac)
		env.ambient_light_energy = lerpf(0.44, 0.82, day_fac)
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = 115.0
		env.fog_depth_end = 560.0
		env.fog_density = 0.40
		env.fog_sky_affect = 0.35
		env.fog_light_color = sky_mat.sky_horizon_color
	else:
		env.ambient_light_color = Color(0.20, 0.22, 0.26).lerp(Color(0.76, 0.77, 0.79), day_fac).lerp(Color(0.56, 0.49, 0.47), dusk_fac * 0.55)
		env.ambient_light_energy = lerpf(0.45, 0.70, day_fac)
		env.fog_enabled = false

	var sky_refl := Color(0.10, 0.12, 0.18).lerp(
		Color(0.62, 0.70, 0.78).lerp(Color(0.86, 0.64, 0.48), dusk_fac),
		day_fac
	)
	if is_rainy:
		sky_refl = sky_refl.lerp(Color(0.40, 0.45, 0.52), 0.65 * day_fac)
	elif is_cloudy:
		sky_refl = sky_refl.lerp(Color(0.56, 0.60, 0.65), 0.55 * day_fac)

	var bldg_night := maxf(_night_factor, 0.14 if is_rainy else 0.0)
	_building_mat.set_shader_parameter("night_factor", bldg_night)
	for nm in _night_mats:
		nm.set_shader_parameter("night_factor", bldg_night)
	_building_mat.set_shader_parameter("env_sky_tint", Vector3(sky_refl.r, sky_refl.g, sky_refl.b))
	if _spheres_mat != null:
		_spheres_mat.set_shader_parameter("night_factor", bldg_night)

	var eff_lamp_fac := maxf(_night_factor, 0.38 if is_rainy else 0.0)
	_globe_mat.emission_energy_multiplier = eff_lamp_fac * 2.8
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
		_transit_sim.apply_night_lights(eff_lamp_fac)
	if _weather != null:
		_weather.update_lighting(_night_factor)

	if _lbl_clock != null:
		var hh := int(floor(_time_hours)) % 24
		var mm := int(floor((_time_hours - floor(_time_hours)) * 60.0)) % 60
		_lbl_clock.text = "%02d:%02d" % [hh, mm]


func _unhandled_input(event: InputEvent) -> void:
	if _startup_loading:
		return
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
			if hk == KEY_1:
				_select_home_map_card("grid")
			elif hk == KEY_2:
				_select_home_map_card("seattle")
			elif hk == KEY_3:
				_select_home_map_card("jiaxing")
			elif hk == KEY_LEFT:
				var mi := MAP_ORDER.find(_selected_home_map)
				_select_home_map_card(MAP_ORDER[posmod(mi - 1, MAP_ORDER.size())])
			elif hk == KEY_RIGHT:
				var mi := MAP_ORDER.find(_selected_home_map)
				_select_home_map_card(MAP_ORDER[posmod(mi + 1, MAP_ORDER.size())])
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
							_show_toast(L10n.t("💡 远光前照灯：%s", "💡 High-Beam Headlight: %s") % (L10n.t("已开启", "ON") if hi else L10n.t("已切回近光", "Low Beam")))
						return
					elif hit_ctrl == "btn_wiper":
						_sound.play_notch_click()
						var tr_w := _transit_sim.get_active_tram()
						if not tr_w.is_empty():
							var won := not bool(tr_w.get("wipers_on", false))
							tr_w["wipers_on"] = won
							_show_toast(L10n.t("🌧 前挡风玻璃雨刮：%s", "🌧 Windshield Wipers: %s") % (L10n.t("已开启", "ON") if won else L10n.t("已关闭", "OFF")))
						return
					elif hit_ctrl == "btn_panto":
						_sound.play_notch_click()
						_show_toast(L10n.t("⚡ 受电弓状态：已升弓受流（750V DC 正常）", "⚡ Pantograph: Raised (750V DC Normal)"))
						return
					elif hit_ctrl == "btn_sand":
						_sound.play_notch_click()
						_show_toast(L10n.t("🏜 轨道撒砂防滑系统已触发（增粘防滑）", "🏜 Track Sander activated (traction boost)"))
						return
					elif hit_ctrl == "btn_rev":
						_sound.play_notch_click()
						_do_cab_change()
						return
					elif hit_ctrl == "btn_eb":
						_sound.play_notch_click()
						_transit_sim.manual_set_notch(0)
						_show_toast(L10n.t("⚠ 已拍下驾驶台【紧急制动 EB】按钮！", "⚠ Emergency Brake (EB) triggered!"))
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
			if _game_mode == GameMode.BUILD and _land_prev_has:
				_land_prev_has = false
				_land_prev_nid = -1
				_preview_mi.mesh = null
				_show_toast(L10n.t("已结束本次连续施工", "Finished chained construction"))
			elif _game_mode == GameMode.BUILD and _path_start_node >= 0:
				_path_start_node = -1
				_preview_mi.mesh = null
				_show_toast(L10n.t("已取消连线铺轨起点", "Cancelled pathfind start node"))
			else:
				_enter_home_screen()
			return
		elif k == KEY_TAB:
			_request_game_mode((_game_mode + 1) % 3)
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
		elif k == KEY_V and _game_mode == GameMode.RUN:
			_toggle_run_pause()
			return

		if _game_mode == GameMode.BUILD:
			if k == KEY_U:
				_set_underground_view(not _underground_view)
				_show_toast(L10n.t("地下透视视图：已开启（再次按 U 恢复地表）", "Underground X-Ray View: ON (press U to restore)") if _underground_view else L10n.t("已恢复地表视图", "Restored surface view"))
				return
			elif k == KEY_BRACKETLEFT or k == KEY_PAGEDOWN:
				_step_build_elev(-1)
				return
			elif k == KEY_BRACKETRIGHT or k == KEY_PAGEUP:
				_step_build_elev(1)
				return
			elif k == KEY_R:
				if _build_tool == BuildTool.CROSSOVER:
					_build_crossover_type = NetworkGraph.CrossoverType.DOUBLE if _build_crossover_type == NetworkGraph.CrossoverType.SINGLE else NetworkGraph.CrossoverType.SINGLE
					_refresh_build_buttons()
					_show_toast(L10n.t("渡线类型已切换为：%s", "Crossover type: %s") % (L10n.t("双渡线 (交叉渡线)", "Scissors Crossover") if _build_crossover_type == NetworkGraph.CrossoverType.DOUBLE else L10n.t("单渡线", "Single Crossover")))
				else:
					_build_station_side = -_build_station_side
					_show_toast(L10n.t("站台方向已切换至轨道%s侧", "Platform side flipped to %s") % (L10n.t("右", "right") if _build_station_side > 0 else L10n.t("左", "left")))
		elif _game_mode == GameMode.PLAN:
			if k == KEY_U:
				_set_underground_view(not _underground_view)
				_show_toast(L10n.t("地下透视视图：已开启（再次按 U 恢复地表）", "Underground X-Ray View: ON (press U to restore)") if _underground_view else L10n.t("已恢复地表视图", "Restored surface view"))
				return
			if k == KEY_BACKSPACE and not _draft_station_ids.is_empty():
				_draft_undo_last()
		else:
			# RUN & DRIVE Mode Controls:
			# W / S = Throttle / Brake; Arrow Keys (Up/Down/Left/Right) = Move/Rotate Camera View!
			if _run_paused and k in [KEY_Q, KEY_W, KEY_S, KEY_SPACE, KEY_O, KEY_B, KEY_R, KEY_X, KEY_G, KEY_H, KEY_K, KEY_J, KEY_U]:
				_show_toast(L10n.t("⏸ 已暂停：按 V 继续运营后再操作列车", "⏸ Paused: press V to resume before controlling tram"))
				return
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
					_btn_pax_rate.text = L10n.t("客流: %s (P)", "Pax: %s (P)") % PassengerSim.spawn_level_name(lvl)
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
				KEY_X:
					_do_toggle_reverser()
				KEY_K:
					_do_toggle_hold_manual()
				KEY_J:
					_do_toggle_switch_lock()
				KEY_U:
					_do_toggle_auto_switches()
				KEY_G:
					_do_throw_switch()
				KEY_H:
					_ring_tram_bell()


# Manual driving: throw the next switch ahead for this train's route
func _do_throw_switch() -> void:
	if not _transit_sim.manual_drive:
		_show_toast(L10n.t("⚠ 自动运营时道岔由调度按进路自动排列；切换手动驾驶 (Q) 后可手动干预道岔", "⚠ Switches are dispatcher-controlled in AI mode; take manual control (Q) to throw switches"))
		return
	var res := _transit_sim.manual_throw_switch(_graph)
	var swi := _transit_sim.switch_ahead_info(_transit_sim.get_active_tram(), _transit_sim.active_tram_idx)
	var ovr := not swi.is_empty() and bool(swi.get("override", false))
	match res:
		"diverge", "straight":
			_sound.play_notch_click()
			var dir_txt := L10n.t("侧向/渡线", "Diverging") if res == "diverge" else L10n.t("直向", "Straight")
			if ovr:
				_show_toast(L10n.t("⚠ 手动干预：道岔扳向【%s】，与本次进路不符，信号保持红灯；再按 G 恢复自动进路", "⚠ Manual override: switch set [%s] (mismatches route, signal stays red); press G again to restore") % dir_txt)
			else:
				_show_toast(L10n.t("✅ 道岔恢复按进路自动排列【%s】，锁闭后信号开放", "✅ Switch aligned [%s] for route — signal clears once locked") % dir_txt)
		"busy":
			_show_toast(L10n.t("⚠ 前方道岔已被其他列车的进路占用，请在信号机前停车等待", "⚠ Switch ahead is reserved by another train — wait at the signal"))
		"locked":
			_show_toast(L10n.t("⚠ 列车正在道岔上，道岔已锁闭不能扳动", "⚠ Train is currently on the switch — cannot throw while locked"))
		"trailing":
			_show_toast(L10n.t("⚠ 前方道岔对本车是顺向（渡线从另一股道汇入），只能直向通过，不能扳向侧向", "⚠ Trailing switch ahead — can only pass straight"))
		_:
			_show_toast(L10n.t("前方 260 m 内没有道岔", "No switch within 260 m ahead"))


func _do_toggle_switch_lock() -> void:
	match _transit_sim.toggle_switch_lock(_graph):
		"locked":
			_sound.play_notch_click()
			var sw = _transit_sim.player_lock[0] if not _transit_sim.player_lock.is_empty() else null
			var pos_txt := ""
			if sw != null:
				var any_div := false
				for g in _transit_sim.player_lock:
					if float(g.target) > 0.5:
						any_div = true
				pos_txt = L10n.t("（当前：%s）", " (%s)") % (L10n.t("侧向/渡线", "Diverging") if any_div else L10n.t("直向", "Straight"))
			_show_toast(L10n.t("🔒 已锁定前方道岔%s：调度不会再扳动它，本车驶出该道岔后自动解锁；再按 J 手动解锁", "🔒 Switch ahead locked%s — unlocks after clearing, or press J to unlock") % pos_txt)
		"unlocked":
			_show_toast(L10n.t("🔓 已解除道岔锁定，道岔恢复由调度按进路排列", "🔓 Switch unlocked — returned to automatic routing"))
		"busy":
			_show_toast(L10n.t("⚠ 前方道岔已被锁定", "⚠ Switch ahead is already locked"))
		_:
			_show_toast(L10n.t("前方 %d m 内没有道岔", "No switch within %d m ahead") % int(TransitSim.SW_SCAN_AHEAD))


func _do_toggle_auto_switches() -> void:
	var on := not _transit_sim.auto_switches
	_transit_sim.set_auto_switches(on)
	_sound.play_notch_click()
	if on:
		_show_toast(L10n.t("✅ AI 自动道岔已开启：调度按各列车进路自动排列道岔", "✅ AI Auto Switches: ON — dispatcher routes switches automatically"))
	else:
		_show_toast(L10n.t("⚠ AI 自动道岔已关闭：所有道岔保持不动，只能按 G 手动扳动；进路不符时信号保持红灯，AI 列车会停车等待", "⚠ AI Auto Switches: OFF — switches hold position; throw manually with G"))


func _do_toggle_hold_manual() -> void:
	match _transit_sim.manual_toggle_hold():
		"held":
			_sound.play_notch_click()
			_show_toast(L10n.t("📌 已保留手动：切换到其他列车后，本车原地停车待命（不交给 AI）；切回本车即可继续手动驾驶", "📌 Held Manual: this tram stays parked in standby when you switch trams"))
		"released":
			_show_toast(L10n.t("已取消保留手动：切换到其他列车后，本车交回 AI 自动运营", "Released Hold Manual: tram will return to AI when you switch away"))
		"moving":
			_show_toast(L10n.t("⚠ 请先停车，再保留手动", "⚠ Stop completely before holding manual"))
		"not_manual":
			_show_toast(L10n.t("⚠ 先接管手动驾驶 (Q) 并停车，才能把本车保留为手动", "⚠ Switch to manual control (Q) and stop first"))


func _toggle_run_pause() -> void:
	if _game_mode != GameMode.RUN or _in_home_menu or _game_over:
		return
	_set_run_paused(not _run_paused)
	_show_toast(L10n.t("⏸ 运营已暂停（V 继续）", "⏸ Paused (press V to resume)") if _run_paused else L10n.t("▶ 继续运营", "▶ Resumed"))


func _set_run_paused(p: bool) -> void:
	_run_paused = p
	if _btn_pause != null:
		_btn_pause.text = L10n.t("▶ 继续 (V)", "▶ Resume (V)") if p else L10n.t("⏸ 暂停 (V)", "⏸ Pause (V)")
		_highlight_active_btn(_btn_pause, p)
	if _lbl_paused != null:
		_lbl_paused.visible = p and _game_mode == GameMode.RUN


# Reverser: forward <-> R (reverse gear). Not needed for normal service, just for shunting about.
func _do_toggle_reverser() -> void:
	match _transit_sim.manual_toggle_reverser():
		"reverse":
			_sound.play_notch_click()
			_show_toast(L10n.t("⏪ 已挂倒档 R：牵引时列车向后行驶（限速 %d km/h）；停车后再按 X 回到前进档", "⏪ Reverse Gear (R): limit %d km/h · Stop and press X for Forward") % int(TransitSim.REVERSE_MAX_KMH))
		"forward":
			_sound.play_notch_click()
			_show_toast(L10n.t("⏩ 已回到前进档", "⏩ Forward Gear"))
		"moving":
			_show_toast(L10n.t("⚠ 请先停车再切换前进 / 倒档", "⚠ Come to a stop before changing Forward / Reverse"))


# Manual cab change: the driver walks to the other cab; at a terminal the tram then departs back the way it came
func _do_cab_change() -> void:
	var res := _transit_sim.manual_reverse_dir()
	match res:
		"ok":
			_sound.play_notch_click()
			var tr_ok := _transit_sim.get_active_tram()
			if str(tr_ok.get("term_stage", "")) == "board_only":
				_show_toast(L10n.t("🔄 已换端：请开门 (O) 让返程新乘客上车，关门后即可发车！", "🔄 Cab changed: open doors (O) to board return passengers, then depart!"))
			else:
				_show_toast(L10n.t("🔄 已换端：现在从另一端驾驶室驾驶，前方为返程方向（出站后经渡线进入对向轨道）", "🔄 Cab changed: driving from opposite cab for return trip"))
		"moving":
			_show_toast(L10n.t("⚠ 换端前请先停车（速度降到 0）", "⚠ Stop completely before changing cab"))
		"doors":
			_show_toast(L10n.t("⚠ 换端前请先关闭车门 (O)", "⚠ Close doors (O) before changing cab"))
		"pax_onboard":
			var tr_p := _transit_sim.get_active_tram()
			var left_n := (tr_p.get("pax_dests", []) as Array).size()
			_show_toast(L10n.t("⚠ 终点站仍有 %d 名乘客未下车：请先开门 (O) 全员清客后再关门换端！", "⚠ %d passenger(s) still onboard at terminus — open doors (O) to alight everyone first!") % left_n)
		"not_terminal":
			var d := _transit_sim.turnback_distance_ahead(_transit_sim.get_active_tram())
			if d > 0.0:
				_show_toast(L10n.t("⚠ 只能在终点站换端：再向前行驶约 %d m 进入终点站后停车", "⚠ Cab change only at terminus (~%d m ahead)") % int(round(maxf(1.0, d - 55.0))))
			else:
				_show_toast(L10n.t("⚠ 只能在终点站换端折返（环线中途不能掉头）", "⚠ Cab change is only allowed at a turnback terminus"))


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
		"throttle": L10n.t("▲▼ 按住上下推拉【主控牵引/制动手柄】", "▲▼ Drag [Master Controller Lever]"),
		"btn_doors": L10n.t("● 点击【DOORS 车门开关】", "● Click [DOORS]"),
		"btn_bell": L10n.t("● 点击【BELL 叮叮铜铃】", "● Click [BELL]"),
		"btn_light": L10n.t("● 点击【LIGHT 远近光前照灯】", "● Click [HEADLIGHT]"),
		"btn_wiper": L10n.t("● 点击【WIPER 挡风玻璃雨刮】", "● Click [WIPERS]"),
		"btn_panto": L10n.t("● 点击【PANTO 受电弓状态检查】", "● Click [PANTOGRAPH]"),
		"btn_sand": L10n.t("● 点击【SAND 轨道撒砂防滑】", "● Click [SANDER]"),
		"btn_rev": L10n.t("● 点击【F/N/R 换向/换端开关】", "● Click [F/N/R CAB SWITCH]"),
		"btn_eb": L10n.t("⚠ 点击【EB STOP 紧急制动】", "⚠ Click [EB EMERGENCY STOP]"),
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


func _track_mode_tag(long: bool = true) -> String:
	if _build_track_mode == NetworkGraph.TrackMode.QUAD:
		return L10n.t("四轨快慢线", "4-Track Express/Local") if long else L10n.t("四轨", "4-Track")
	if _build_track_mode == NetworkGraph.TrackMode.DOUBLE:
		return L10n.t("双线并行", "Double Track") if long else L10n.t("双线", "Double")
	return L10n.t("单线", "Single")


func _track_preview_width() -> float:
	if _build_track_mode == NetworkGraph.TrackMode.QUAD:
		return 13.2
	return 6.6 if _build_track_mode == NetworkGraph.TrackMode.DOUBLE else 3.4


func _screen_to_ground_xz(screen_pos: Vector2) -> Variant:
	var orig := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var hit = Terrain.raycast(orig, dir) # the real ground (a plane at 0 on flat maps)
	if hit == null:
		return null
	return Vector2((hit as Vector3).x, (hit as Vector3).z)


# Tracks, platforms and stations onto the real ground; station passenger points with them
func _put_tracks_on_terrain() -> void:
	if not Terrain.active:
		return
	if _city_tiles != null and is_instance_valid(_city_tiles):
		_city_tiles.finish_pending()
	if Terrain.grade_for_tracks(_graph):
		_refresh_land_layers(true, false)
	Terrain.drape_subtree(_track_root)
	for sv in _station_views.values():
		if sv is Dictionary:
			Terrain.lift_station_view(sv)


func _update_build_hover_preview(screen_pos: Vector2) -> void:
	if _overview_on:
		_preview_mi.mesh = null
		return
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
		var prev_w := _track_preview_width()
		var mode_tag := _track_mode_tag()
		var elev_y := _get_build_elev()
		var prev_col := Color(0.24, 0.72, 0.98, 0.74) if elev_y < -1.0 else (Color(0.96, 0.78, 0.24, 0.74) if elev_y > 1.0 else Color(0.20, 0.92, 0.56, 0.72))
		_set_ribbon_preview(_preview_mi, [eid], prev_col, prev_w, elev_y)
		var ed_name: String = L10n.street_display_name(str(_graph.edges[eid]["name"]))
		_lbl_build_hint.text = L10n.t("悬停街道：%s · 单击铺设【%s · %s · %s】（[ / ] 调高程，U 地下透视）", "Street: %s · Click to lay [%s · %s · %s] ([ / ] elevation, U underground)") % [ed_name, mode_tag, _bed_style_name(_build_bed_style), NetworkGraph.elev_label(elev_y)]

	elif _build_tool == BuildTool.TRACK_PATH:
		var nid := _graph.find_closest_node(xz, 26.0)
		if nid < 0:
			_preview_mi.mesh = null
			return
		var elev_p := _get_build_elev()
		if _path_start_node >= 0 and nid != _path_start_node:
			var path_eids := _graph.shortest_street_path(_path_start_node, nid, false)
			var prev_w := _track_preview_width()
			var mode_tag := _track_mode_tag()
			var prev_col_p := Color(0.24, 0.72, 0.98, 0.78) if elev_p < -1.0 else (Color(0.96, 0.78, 0.24, 0.78) if elev_p > 1.0 else Color(0.22, 0.85, 0.98, 0.78))
			_set_ribbon_preview(_preview_mi, path_eids, prev_col_p, prev_w, elev_p)
			_lbl_build_hint.text = L10n.t("自动寻路：%d 段街道 · 单击铺设【%s · %s · %s】（Esc 取消起点）", "Pathfind: %d segs · Click to lay [%s · %s · %s] (Esc to cancel)") % [path_eids.size(), mode_tag, _bed_style_name(_build_bed_style), NetworkGraph.elev_label(elev_p)]
		else:
			var np: Vector2 = _graph.nodes[nid]["pos"]
			_set_point_box_preview(_preview_mi, Vector3(np.x, elev_p + 0.6, np.y), Vector3(6.0, 1.2, 6.0), Color(0.22, 0.85, 0.98, 0.80))
			_lbl_build_hint.text = L10n.t("路口：%s · 单击选为连线铺轨起点 [%s]", "Junction: %s · Click to set pathfind start [%s]") % [L10n.street_display_name(str(_graph.nodes[nid]["name"])), NetworkGraph.elev_label(elev_p)]

	elif _build_tool == BuildTool.CROSSOVER:
		var hit := _graph.find_closest_edge(xz, 22.0, true, _active_elev_filter())
		var xo_name := L10n.t("交叉渡线 (剪刀)", "Scissors Crossover") if _build_crossover_type == NetworkGraph.CrossoverType.DOUBLE else L10n.t("单渡线", "Single Crossover")
		if hit.is_empty():
			_preview_mi.mesh = null
			_lbl_build_hint.text = L10n.t("请将光标移至【已铺设双线轨道】的街道上修建%s（按 R 切换单/交叉渡线）", "Hover a [Double Track] street to place %s (Press R to toggle)") % xo_name
			return
		var eid := int(hit["edge_id"])
		var t_hit := float(hit["t"])
		var place := TrackBuilder.compute_crossover_placement(_graph, eid, t_hit, _build_crossover_type)
		if not bool(place.get("valid", false)):
			var rsn := str(place.get("reason", ""))
			if rsn == "on_station":
				_set_oriented_box_preview(_preview_mi, (place["pos"] as Vector3) + Vector3(0.0, 0.35, 0.0), place["fwd"] as Vector3, Vector3(5.8, 0.7, float(place["x_half"]) * 2.0 + 1.0), Color(0.95, 0.28, 0.22, 0.78))
				_lbl_build_hint.text = L10n.t("⚠ 禁止在车站站台上修建道岔/渡线，请移至出站并线后的轨道位置！", "⚠ Cannot place crossover on a station platform — move clear of the station!")
			else:
				var is_dbl := _graph.is_multi_track(eid)
				_set_ribbon_preview(_preview_mi, [eid], Color(0.95, 0.45, 0.22, 0.70), 6.2)
				var why := L10n.t("长度不足", "segment too short") if is_dbl else L10n.t("单线轨道", "single track")
				if _graph.is_quad(eid):
					why = L10n.t("四轨区段不设渡线，请在两端的双线区段修建", "no crossovers on 4-track; build on adjacent double-track")
				_lbl_build_hint.text = L10n.t("⚠ 仅限有效长度充足的【双线轨道】可修建渡线（当前：%s）", "⚠ Crossovers require a long enough [Double Track] (%s)") % why
			return
		var xo_len := float(place["x_half"]) * 2.0 + 1.2
		_set_oriented_box_preview(_preview_mi, (place["pos"] as Vector3) + Vector3(0.0, 0.35, 0.0), place["fwd"] as Vector3, Vector3(5.8, 0.7, xo_len), Color(0.96, 0.78, 0.22, 0.82))
		_lbl_build_hint.text = L10n.t("单击在 %s 光标处修建【%s】（可紧贴出站并线后修建，按 R 切换单/交叉渡线）", "Click to build [%s] on %s (Press R to toggle)") % ([L10n.street_display_name(str(_graph.edges[eid]["name"])), xo_name] if not L10n.is_en() else [xo_name, L10n.street_display_name(str(_graph.edges[eid]["name"]))])

	elif _build_tool == BuildTool.STATION:
		var near_sid := _graph.find_closest_station(xz, 8.5, _active_elev_filter())
		if near_sid >= 0:
			var sp_ex := _graph.get_station_platform_world_pos(near_sid)
			var st_fwd_ex: Vector3 = _graph.stations[near_sid]["fwd"]
			var st_len_ex := float(_graph.stations[near_sid].get("platform_len", 27.0))
			_set_oriented_box_preview(_preview_mi, sp_ex + Vector3(0.0, 1.5, 0.0), st_fwd_ex, Vector3(3.6, 3.0, st_len_ex + 0.6), Color(0.28, 0.78, 0.98, 0.75))
			_lbl_build_hint.text = L10n.t("已对准车站【%s】（%.0fm 站台）· 单击可选中并在左侧修改站名", "Station [%s] (%.0fm) · Click to select & rename on the left") % [L10n.station_display_name(str(_graph.stations[near_sid]["name"])), st_len_ex]
			return
		var hit := _graph.find_closest_edge(xz, 22.0, true, _active_elev_filter())
		if hit.is_empty():
			_preview_mi.mesh = null
			_lbl_build_hint.text = L10n.t("请将光标移至【已铺设轨道】的街道上建造车站（按 R 切换左右侧站台）", "Hover a [Tracked] street to place a station (Press R to flip side)")
			return
		var eid := int(hit["edge_id"])
		var plat_len := STATION_LEN_PRESETS[_build_station_len_idx]
		var is_dbl_chk := _graph.is_multi_track(eid)
		var req_k_prev := _build_station_kind if is_dbl_chk else NetworkGraph.StationKind.SIDE_SINGLE
		if TrackBuilder.station_overlaps_crossover(_graph, eid, float(hit["t"]), req_k_prev, plat_len):
			_set_oriented_box_preview(_preview_mi, (hit["pos"] as Vector3) + Vector3(0.0, 0.4, 0.0), hit["fwd"] as Vector3, Vector3(4.8, 0.8, plat_len), Color(0.95, 0.28, 0.22, 0.78))
			_lbl_build_hint.text = L10n.t("⚠ 该位置与已有道岔/渡线重叠，不可在道岔上建造车站！", "⚠ Overlaps an existing crossover/switch — cannot build station here!")
			return
		var is_dbl := _graph.is_multi_track(eid)
		var sep_prev := _graph.get_edge_track_half_sep(eid)
		var pos3: Vector3 = hit["pos"]
		var fwd3: Vector3 = hit["fwd"]
		var right3 := fwd3.cross(Vector3.UP).normalized()
		if _graph.is_quad(eid):
			sep_prev = NetworkGraph.QUAD_LOCAL_HALF_SEP
		if _graph.is_quad(eid) and _build_station_kind == NetworkGraph.StationKind.ISLAND:
			_set_oriented_box_preview(_preview_mi, pos3 + Vector3(0.0, 0.4, 0.0), fwd3, Vector3(12.6, 0.8, plat_len), Color(0.25, 0.92, 0.62, 0.62))
			_lbl_build_hint.text = L10n.t("单击建造 %.0fm【四轨双岛式站台】（第1-2轨、第3-4轨之间各一岛，慢车道在站前外扩，快慢车同台换乘）", "Click to build %.0fm [4-Track Twin-Island] (express/local cross-platform transfer)") % plat_len
		elif _graph.is_quad(eid) and _build_station_kind == NetworkGraph.StationKind.SIDE_DUAL:
			_set_oriented_box_preview(_preview_mi, pos3 + Vector3(0.0, 0.4, 0.0), fwd3, Vector3(16.8, 0.7, plat_len), Color(0.25, 0.92, 0.62, 0.50))
			_lbl_build_hint.text = L10n.t("单击建造 %.0fm【四轨外侧侧式站台】（第1、4轨外侧设站台，仅慢车停靠，快车通过）", "Click to build %.0fm [4-Track Outer Side Platforms] (local stops only; express bypasses)") % plat_len
		elif is_dbl and _build_station_kind == NetworkGraph.StationKind.ISLAND:
			_set_oriented_box_preview(_preview_mi, pos3 + Vector3(0.0, 0.4, 0.0), fwd3, Vector3(3.1, 0.8, plat_len), Color(0.25, 0.92, 0.62, 0.78))
			_lbl_build_hint.text = L10n.t("单击建造 %.0fm【中央岛式站台】（双线将自动加宽至 ±3.05m，列车开内侧门）", "Click to build %.0fm [Center Island Platform] (tracks widen to ±3.05m)") % plat_len
		elif is_dbl and _build_station_kind == NetworkGraph.StationKind.SIDE_DUAL:
			_set_oriented_box_preview(_preview_mi, pos3 + Vector3(0.0, 0.4, 0.0), fwd3, Vector3(11.8, 0.7, plat_len), Color(0.25, 0.92, 0.62, 0.58))
			_lbl_build_hint.text = L10n.t("单击建造 %.0fm【对称双侧站台】（同时覆盖双线轨道左右两侧）", "Click to build %.0fm [Dual Side Platforms] (both sides of double track)") % plat_len
		else:
			var plat_pos := pos3 + right3 * (float(_build_station_side) * (2.9 + sep_prev)) + Vector3(0.0, 0.4, 0.0)
			_set_oriented_box_preview(_preview_mi, plat_pos, fwd3, Vector3(3.0, 0.8, plat_len), Color(0.25, 0.92, 0.62, 0.78))
			_lbl_build_hint.text = L10n.t("单击在此建造 %.0fm 精细 3D 车站（按 R 切换左右侧站台）", "Click to build %.0fm 3D Station (Press R to flip side)") % plat_len

	elif _build_tool == BuildTool.TRACK_OFFROAD or _build_tool == BuildTool.ROAD_BUILD:
		var is_road := _build_tool == BuildTool.ROAD_BUILD
		var cfg := LANE_CFGS[_road_lane_idx]
		var w_prev := NetworkGraph.road_width_for(cfg.x, cfg.y) if is_road else NetworkGraph.row_width_for(_build_track_mode)
		var target_elev := 0.0 if is_road else _get_build_elev()
		var sys_p := 1 if TrackBuilder.is_monorail_style(_build_bed_style) else 0
		var snap := _graph.find_closest_node(xz, 9.0, 0 if is_road else _active_elev_filter(), NAN if is_road else target_elev)
		var pb: Vector2 = _graph.nodes[snap]["pos"] if snap >= 0 else xz
		var yb_p := target_elev
		if not is_road and snap >= 0:
			var nyp := _graph.get_node_track_elev(snap, sys_p, target_elev)
			if not is_nan(nyp) and absf(nyp - target_elev) <= 1.2:
				yb_p = nyp
		if not _land_prev_has:
			var y0_p := target_elev
			if not is_road and snap >= 0:
				var ny0p := _graph.get_node_track_elev(snap, sys_p, target_elev)
				if not is_nan(ny0p):
					y0_p = ny0p
			_set_point_box_preview(_preview_mi, Vector3(pb.x, y0_p + 0.6, pb.y), Vector3(w_prev, 1.2, w_prev), Color(0.22, 0.85, 0.98, 0.76))
			_lbl_build_hint.text = (L10n.t("单击选择新道路起点（%s）· 可点在路口或路段中间接出", "Click start point for New Road (%s) · Branch from junction or mid-block") % _lane_cfg_label(_road_lane_idx)) if is_road else (L10n.t("单击选择立体轨道起点【%s · %s】（[ / ] 调高程，U 地下透视 · 可建高架/地下/立体坡道）", "Click start for 3D Track [%s · %s] ([ / ] elevation, U underground · viaduct/tunnel/ramp)") % [_track_mode_tag(), NetworkGraph.elev_label(y0_p)])
			return
		var pa := _node_or_point_pos(_land_prev_nid, _land_prev_xz)
		var seg := pb - pa
		if seg.length() < 1.0:
			return
		var ya_p := 0.0 if is_road else _land_prev_elev
		var blocked := (_strip_hits_building(pa.lerp(pb, 0.04), pb.lerp(pa, 0.04), w_prev * 0.5 + 0.5) >= 0) if is_road else (_strip_hits_building_3d(pa.lerp(pb, 0.04), pb.lerp(pa, 0.04), w_prev * 0.5 + 0.5, ya_p, yb_p) >= 0)
		var gr_p := _validate_ramp_grade(seg.length(), ya_p, yb_p, _build_bed_style) if not is_road else {"ok": true, "grade": 0.0, "max_grade": 1.0, "min_len": 0.0}
		var same_lvl_x := false
		if not is_road:
			for crp: Dictionary in _segment_crossings_3d(pa, pb, _land_prev_nid, snap, ya_p, yb_p):
				if bool(crp["has_track"]) and bool(crp["same_level"]):
					same_lvl_x = true
					break
		var bad := blocked or not bool(gr_p["ok"]) or same_lvl_x
		var steep_warn := (not bad) and float(gr_p["grade"]) > 0.045
		var col := Color(0.95, 0.28, 0.22, 0.74) if bad else (Color(0.96, 0.72, 0.18, 0.74) if steep_warn else (Color(0.24, 0.74, 0.98, 0.72) if minf(ya_p, yb_p) < -1.0 else Color(0.25, 0.92, 0.62, 0.70)))
		if is_road:
			var mid := (pa + pb) * 0.5
			_set_oriented_box_preview(_preview_mi, Vector3(mid.x, 0.35, mid.y), Vector3(seg.x, 0.0, seg.y).normalized(), Vector3(w_prev, 0.5, seg.length()), col)
			_lbl_build_hint.text = L10n.t("%.0fm%s · 单击确认，Esc 结束", "%.0fm%s · Click to place, Esc to finish") % [seg.length(), L10n.t(" · ⚠ 穿过建筑", " · ⚠ Hits building") if blocked else ""]
		else:
			_set_sloped_ribbon_preview(_preview_mi, pa, pb, ya_p, yb_p, w_prev, col)
			var elev_info := NetworkGraph.elev_label(yb_p) if absf(ya_p - yb_p) < 0.05 else ("%s → %s · 坡度 %.1f%%" % [NetworkGraph.elev_label(ya_p), NetworkGraph.elev_label(yb_p), float(gr_p["grade"]) * 100.0])
			var warn_str := ""
			if not bool(gr_p["ok"]):
				warn_str = L10n.t(" · ⚠ 坡度超限 (需≥%.0fm)", " · ⚠ Too steep (need ≥%.0fm)") % float(gr_p["min_len"])
			elif blocked:
				warn_str = L10n.t(" · ⚠ 穿过建筑", " · ⚠ Hits building")
			elif same_lvl_x:
				warn_str = L10n.t(" · ⚠ 同层轨道交叉", " · ⚠ Same-level track crossing")
			_lbl_build_hint.text = L10n.t("%.0fm · %s%s · 单击确认，[ / ] 调高程，Esc 结束", "%.0fm · %s%s · Click to place, [ / ] elevation, Esc to finish") % [seg.length(), elev_info, warn_str]

	elif _build_tool == BuildTool.ROAD_REMOVE or _build_tool == BuildTool.ROAD_LANES:
		var hit_r := _graph.find_closest_edge(xz, 14.0, false)
		if hit_r.is_empty():
			_preview_mi.mesh = null
			return
		var eid_r := int(hit_r["edge_id"])
		var ed_r: Dictionary = _graph.edges[eid_r]
		var lanes_now := "%d+%d" % [int(ed_r.get("lanes_f", 1)), int(ed_r.get("lanes_b", 1))]
		var r_nm := L10n.street_display_name(str(ed_r["name"]))
		if _build_tool == BuildTool.ROAD_REMOVE:
			var has_t := _graph.built_tracks.has(eid_r)
			_set_ribbon_preview(_preview_mi, [eid_r], Color(0.96, 0.26, 0.22, 0.72) if not has_t else Color(0.96, 0.62, 0.22, 0.6), float(ed_r["width"]))
			_lbl_build_hint.text = (L10n.t("单击拆除道路：%s（%s 车道 · %.0fm）", "Click to demolish road: %s (%s lanes · %.0fm)") % [r_nm, lanes_now, float(ed_r["width"])]) if not has_t else (L10n.t("⚠ %s 上铺有轨道：请先拆除轨道再拆道路", "⚠ %s has tracks — remove tracks first") % r_nm)
		else:
			var cfg2 := LANE_CFGS[_road_lane_idx]
			_set_ribbon_preview(_preview_mi, [eid_r], Color(0.30, 0.70, 0.98, 0.62), NetworkGraph.road_width_for(cfg2.x, cfg2.y))
			_lbl_build_hint.text = L10n.t("单击把 %s 改为【%s】（现为 %s 车道 · %.0fm → %.0fm）· 单向路再次单击可调转方向", "Click to set %s to [%s] (now %s · %.0fm → %.0fm) · Click again to flip 1-way") % [r_nm, _lane_cfg_label(_road_lane_idx), lanes_now, float(ed_r["width"]), NetworkGraph.road_width_for(cfg2.x, cfg2.y)]

	elif _build_tool == BuildTool.BUILDING_DEMOLISH:
		var bi := _building_at(xz)
		if bi < 0:
			_preview_mi.mesh = null
			_lbl_build_hint.text = L10n.t("将光标移到要拆除的建筑上（地标建筑不可拆除）", "Hover a building to demolish (landmarks cannot be demolished)")
			return
		var poly := _building_poly(bi)
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for v: Vector2 in poly:
			mn = mn.min(v)
			mx = mx.max(v)
		var bd: Dictionary = (_map_data["buildings"] as Array)[bi]
		var h := float(bd.get("h", 12.0))
		var lm := str(bd.get("lm", "")) != ""
		_set_point_box_preview(_preview_mi, Vector3((mn.x + mx.x) * 0.5, h * 0.5, (mn.y + mx.y) * 0.5), Vector3(mx.x - mn.x + 0.6, h + 0.6, mx.y - mn.y + 0.6), Color(0.96, 0.26, 0.22, 0.45) if not lm else Color(0.6, 0.6, 0.6, 0.35))
		_lbl_build_hint.text = (L10n.t("单击拆除这栋建筑（高 %.0fm），腾出空地可铺设专用轨道或新建道路", "Click to demolish building (height %.0fm) to clear space") % h) if not lm else L10n.t("地标建筑不可拆除", "Landmarks cannot be demolished")

	elif _build_tool == BuildTool.DEMOLISH:
		var sid := _graph.find_closest_station(xz, 18.0, _active_elev_filter())
		if sid >= 0:
			var sp := _graph.get_station_platform_world_pos(sid)
			var st_fwd: Vector3 = _graph.stations[sid]["fwd"]
			var st_len := float(_graph.stations[sid].get("platform_len", 27.0))
			_set_oriented_box_preview(_preview_mi, sp + Vector3(0.0, 1.5, 0.0), st_fwd, Vector3(3.6, 3.0, st_len + 0.6), Color(0.96, 0.26, 0.22, 0.75))
			_lbl_build_hint.text = L10n.t("单击拆除车站：%s", "Click to demolish station: %s") % L10n.station_display_name(str(_graph.stations[sid]["name"]))
			return
		var hit := _graph.find_closest_edge(xz, 18.0, true, _active_elev_filter())
		if not hit.is_empty():
			var d_eid := int(hit["edge_id"])
			var d_ep := _graph.get_edge_elev_pair(d_eid)
			_set_ribbon_preview(_preview_mi, [d_eid], Color(0.96, 0.26, 0.22, 0.78), 3.8, (d_ep.x + d_ep.y) * 0.5)
			_lbl_build_hint.text = L10n.t("单击拆除该段轨道 [%s]", "Click to demolish this track segment [%s]") % NetworkGraph.elev_label((d_ep.x + d_ep.y) * 0.5)
		else:
			_preview_mi.mesh = null


func _handle_map_left_click(screen_pos: Vector2) -> void:
	if _overview_on and _game_mode != GameMode.RUN:
		_show_toast(L10n.t("全城视图下不能建设 / 规划，放大后再操作", "Zoom in from City Overview before building or planning"))
		return
	var xz_var = _screen_to_ground_xz(screen_pos)
	if xz_var == null:
		return
	var xz: Vector2 = xz_var

	if _game_mode == GameMode.BUILD:
		var mode_tag := _track_mode_tag(false)
		if _build_tool == BuildTool.TRACK_SINGLE or _build_tool == BuildTool.TRACK_PATH:
			if _build_track_mode == NetworkGraph.TrackMode.QUAD and TrackBuilder.is_monorail_style(_build_bed_style):
				_show_toast(L10n.t("⚠ 四轨快慢线仅适用于有轨电车（独立路权），单轨请选双线", "⚠ 4-Track is for trams only; use Double Track for monorail"))
				return
		if _build_tool == BuildTool.TRACK_SINGLE:
			var hit := _graph.find_closest_edge(xz, 22.0, false)
			if not hit.is_empty():
				var eid := int(hit["edge_id"])
				var elev_y := _get_build_elev()
				if _build_track_mode == NetworkGraph.TrackMode.QUAD and absf(elev_y) < 1.5 and float(_graph.edges[eid].get("width", 12.0)) < 13.0:
					_show_toast(L10n.t("⚠ %s 路面太窄（%.0fm），地面四轨需要至少 13m 宽道路（或切至高架/地下）", "⚠ %s is too narrow (%.0fm) — ground 4-Track needs ≥13m (or go elevated/underground)") % [L10n.street_display_name(str(_graph.edges[eid]["name"])), float(_graph.edges[eid].get("width", 12.0))])
					return
				_graph.lay_track_along_street(eid, _build_bed_style, _build_track_mode, elev_y, elev_y)
				_rebuild_tracks_only_visual()
				_mark_modified_and_quick_save()
				_show_toast(L10n.t("已铺设【%s · %s · %s】轨道：%s", "Laid [%s · %s · %s] track on %s") % [mode_tag, _bed_style_name(_build_bed_style), NetworkGraph.elev_label(elev_y), L10n.street_display_name(str(_graph.edges[eid]["name"]))])

		elif _build_tool == BuildTool.TRACK_PATH:
			var nid := _graph.find_closest_node(xz, 26.0)
			if nid < 0:
				return
			if _path_start_node < 0:
				_path_start_node = nid
				_show_toast(L10n.t("已选起点路口：%s，请点击终点路口自动寻路铺轨", "Pathfind start: %s — click destination junction") % L10n.street_display_name(str(_graph.nodes[nid]["name"])))
			elif nid != _path_start_node:
				var eids := _graph.shortest_street_path(_path_start_node, nid, false)
				var elev_p := _get_build_elev()
				for eid: int in eids:
					_graph.lay_track_along_street(eid, _build_bed_style, _build_track_mode, elev_p, elev_p)
				_path_start_node = nid
				_rebuild_tracks_only_visual()
				_mark_modified_and_quick_save()
				var narrow := 0
				if _build_track_mode == NetworkGraph.TrackMode.QUAD and absf(elev_p) < 1.5:
					for eid_n: int in eids:
						if float(_graph.edges[eid_n].get("width", 12.0)) < 13.0:
							narrow += 1
				var narrow_note := (L10n.t("（其中 %d 段路面较窄，四轨将占用全部路面）", " (%d narrow segs full-width)") % narrow) if narrow > 0 else ""
				_show_toast(L10n.t("已沿最短路径铺设 %d 段【%s · %s · %s】轨道！%s", "Laid %d [%s · %s · %s] track segments!%s") % [eids.size(), mode_tag, _bed_style_name(_build_bed_style), NetworkGraph.elev_label(elev_p), narrow_note])

		elif _build_tool == BuildTool.CROSSOVER:
			var hit := _graph.find_closest_edge(xz, 22.0, true, _active_elev_filter())
			if hit.is_empty():
				_show_toast(L10n.t("请先铺设【双线轨道】，再点击该双线路段修建渡线！", "Lay [Double Track] first, then click it to place a crossover!"))
				return
			var eid := int(hit["edge_id"])
			var t_hit := float(hit["t"])
			var place := TrackBuilder.compute_crossover_placement(_graph, eid, t_hit, _build_crossover_type)
			if not bool(place.get("valid", false)):
				if str(place.get("reason", "")) == "on_station":
					_show_toast(L10n.t("⚠ 不可在车站站台上修建道岔/渡线，请移至出站并线后的轨道位置！", "⚠ Cannot place crossover on a station platform!"))
				else:
					_show_toast(L10n.t("⚠ 四轨区段不设渡线，请在两端的双线区段修建", "⚠ No crossovers on 4-track — place on adjacent double-track") if _graph.is_quad(eid) else L10n.t("⚠ 仅限有效长度充足的【双线轨道】可修建渡线！", "⚠ Crossovers require a long enough [Double Track]!"))
				return
			if _graph.set_crossover_on_edge(eid, _build_crossover_type, float(place["t_clamped"])):
				_rebuild_tracks_only_visual()
				_mark_modified_and_quick_save()
				var xo_name := L10n.t("交叉渡线 (剪刀)", "Scissors Crossover") if _build_crossover_type == NetworkGraph.CrossoverType.DOUBLE else L10n.t("单渡线", "Single Crossover")
				if TrackBuilder.edge_system(_graph, eid) == 1:
					xo_name = L10n.t("双向单轨道岔 (两组梁式道岔)", "Double Monorail Switch") if _build_crossover_type == NetworkGraph.CrossoverType.DOUBLE else L10n.t("单向单轨道岔", "Single Monorail Switch")
				_show_toast(L10n.t("已在 %s 修建【%s】！", "Built [%s] on %s!") % ([L10n.street_display_name(str(_graph.edges[eid]["name"])), xo_name] if not L10n.is_en() else [xo_name, L10n.street_display_name(str(_graph.edges[eid]["name"]))]))

		elif _build_tool == BuildTool.STATION:
			var near_sid := _graph.find_closest_station(xz, 8.5, _active_elev_filter())
			if near_sid >= 0:
				_editing_station_id = near_sid
				if _edit_station_name != null:
					_edit_station_name.text = str(_graph.stations[near_sid]["name"])
				_show_toast(L10n.t("已选中车站【%s】，可在左侧「站名编辑」栏修改名称！", "Selected [%s] — edit its name in the left panel!") % L10n.station_display_name(str(_graph.stations[near_sid]["name"])))
				return
			var hit := _graph.find_closest_edge(xz, 22.0, true, _active_elev_filter())
			if hit.is_empty():
				_show_toast(L10n.t("请先在街道上铺设轨道，再在轨道旁建造车站！", "Lay tracks on a street first before placing a station!"))
				return
			var eid := int(hit["edge_id"])
			var t_hit := float(hit["t"])
			var plat_len := STATION_LEN_PRESETS[_build_station_len_idx]
			var is_dbl := _graph.is_multi_track(eid)
			var req_k_chk := _build_station_kind if is_dbl else NetworkGraph.StationKind.SIDE_SINGLE
			if TrackBuilder.station_overlaps_crossover(_graph, eid, t_hit, req_k_chk, plat_len):
				_show_toast(L10n.t("⚠ 该位置与已有道岔/渡线重叠，不可在道岔上建造车站！", "⚠ Overlaps a crossover/switch — cannot build station here!"))
				return
			var custom_n := _edit_station_name.text.strip_edges() if (_edit_station_name != null and _editing_station_id < 0) else ""
			if is_dbl and _build_station_kind == NetworkGraph.StationKind.SIDE_DUAL:
				var sid1 := _graph.add_station_on_edge(eid, t_hit, 1, custom_n, NetworkGraph.StationKind.SIDE_SINGLE, plat_len)
				var sid2 := _graph.add_station_on_edge(eid, t_hit, -1, custom_n, NetworkGraph.StationKind.SIDE_SINGLE, plat_len)
				if sid1 >= 0 or sid2 >= 0:
					var last_sid := sid2 if sid2 >= 0 else sid1
					_editing_station_id = last_sid
					if _edit_station_name != null and _graph.stations.has(last_sid):
						_edit_station_name.text = str(_graph.stations[last_sid]["name"])
					_rebuild_tracks_only_visual()
					_mark_modified_and_quick_save()
					var n1 := L10n.station_display_name(str(_graph.stations.get(sid1, {}).get("name", "")))
					var n2 := L10n.station_display_name(str(_graph.stations.get(sid2, {}).get("name", "")))
					var pair_lbl := n1 if n1 == n2 or n2.is_empty() else ("%s / %s" % [n1, n2])
					_show_toast(L10n.t("已建成 %.0fm 对称双侧站台：%s", "Built %.0fm dual side platforms: %s") % [plat_len, pair_lbl])
			else:
				var req_kind := _build_station_kind if is_dbl else NetworkGraph.StationKind.SIDE_SINGLE
				var sid := _graph.add_station_on_edge(eid, t_hit, _build_station_side, custom_n, req_kind, plat_len)
				if sid >= 0:
					_editing_station_id = sid
					if _edit_station_name != null:
						_edit_station_name.text = str(_graph.stations[sid]["name"])
					_rebuild_tracks_only_visual()
					_mark_modified_and_quick_save()
					_show_toast(L10n.t("已建成 %.0fm 车站：%s", "Built %.0fm station: %s") % [plat_len, L10n.station_display_name(str(_graph.stations[sid]["name"]))])

		elif _build_tool == BuildTool.TRACK_OFFROAD:
			_land_chain_click(xz, false)

		elif _build_tool == BuildTool.ROAD_BUILD:
			_land_chain_click(xz, true)

		elif _build_tool == BuildTool.ROAD_REMOVE:
			var hit_rr := _graph.find_closest_edge(xz, 14.0, false)
			if hit_rr.is_empty():
				return
			var eid_rr := int(hit_rr["edge_id"])
			var nm_rr := L10n.street_display_name(str(_graph.edges[eid_rr]["name"]))
			if bool(_graph.edges[eid_rr].get("no_cars", false)):
				_show_toast(L10n.t("这是空地专用轨道：请用【拆除车站 / 轨道】拆除", "This is a dedicated track — use [Demolish Station / Track]"))
				return
			var res := _graph.remove_road(eid_rr)
			if res == "has_track":
				_show_toast(L10n.t("⚠ %s 上铺有轨道：请先拆除轨道再拆道路", "⚠ %s has tracks — remove tracks first") % nm_rr)
				return
			_after_land_edit(true, false)
			_show_toast(L10n.t("已拆除道路：%s", "Demolished road: %s") % nm_rr)

		elif _build_tool == BuildTool.ROAD_LANES:
			var hit_rl := _graph.find_closest_edge(xz, 14.0, false)
			if hit_rl.is_empty():
				return
			var eid_rl := int(hit_rl["edge_id"])
			var cfg_l := LANE_CFGS[_road_lane_idx]
			var lf := cfg_l.x
			var lb := cfg_l.y
			var ed_l: Dictionary = _graph.edges[eid_rl]
			if lb == 0 and int(ed_l.get("lanes_f", 1)) == lf and int(ed_l.get("lanes_b", 1)) == 0:
				lb = lf # same one-way setting clicked again: turn it around
				lf = 0
			if not _graph.set_road_lanes(eid_rl, lf, lb):
				_show_toast(L10n.t("⚠ 专用轨道没有机动车道", "⚠ Dedicated tracks have no vehicle lanes"))
				return
			var w_new := float(_graph.edges[eid_rl]["width"])
			var b_hit := _strip_hits_building((ed_l["pts"] as Array)[0], (ed_l["pts"] as Array)[(ed_l["pts"] as Array).size() - 1], w_new * 0.5) >= 0
			_after_land_edit(true, false)
			_show_toast(L10n.t("已把 %s 改为 %d+%d 车道（宽 %.0fm）%s", "Set %s to %d+%d lanes (width %.0fm)%s") % [L10n.street_display_name(str(ed_l["name"])), lf, lb, w_new, L10n.t(" · ⚠ 路面已贴近建筑，可拆除建筑拓宽", " · ⚠ Close to buildings") if b_hit else ""])

		elif _build_tool == BuildTool.BUILDING_DEMOLISH:
			var bi_d := _building_at(xz)
			if bi_d < 0:
				return
			if str(((_map_data["buildings"] as Array)[bi_d] as Dictionary).get("lm", "")) != "":
				_show_toast(L10n.t("地标建筑不可拆除", "Landmarks cannot be demolished"))
				return
			_graph.demolish_building(bi_d)
			_after_land_edit(false, true)
			_preview_mi.mesh = null
			_show_toast(L10n.t("已拆除建筑，腾出空地", "Building demolished"))

		elif _build_tool == BuildTool.DEMOLISH:
			var sid := _graph.find_closest_station(xz, 18.0, _active_elev_filter())
			if sid >= 0:
				var sname := L10n.station_display_name(str(_graph.stations[sid]["name"]))
				_graph.remove_station(sid)
				_rebuild_tracks_only_visual()
				_mark_modified_and_quick_save()
				_show_toast(L10n.t("已拆除车站：%s", "Demolished station: %s") % sname)
				return
			var hit := _graph.find_closest_edge(xz, 18.0, true, _active_elev_filter())
			if not hit.is_empty():
				var deid := int(hit["edge_id"])
				if _graph.crossovers.has(deid):
					_graph.crossovers.erase(deid)
					_graph.crossover_t.erase(deid)
					_rebuild_tracks_only_visual()
					_mark_modified_and_quick_save()
					_show_toast(L10n.t("已拆除该段渡线（保留双线轨道）", "Removed crossover (double track kept)"))
				elif bool(_graph.edges[deid].get("no_cars", false)):
					_graph.remove_offroad_track(deid)
					_after_land_edit(false, false)
					_show_toast(L10n.t("已拆除立体专用轨道段", "Demolished 3D dedicated track segment"))
				else:
					_graph.remove_track_on_edge(deid)
					_rebuild_tracks_only_visual()
					_mark_modified_and_quick_save()
					_show_toast(L10n.t("已拆除轨道段", "Demolished track segment"))

	elif _game_mode == GameMode.PLAN:
		var sid := _graph.find_closest_station(xz, 32.0, _active_elev_filter())
		if sid < 0:
			_show_toast(L10n.t("请点击已建成的 3D 车站将其加入新线路！（按下触摸板移动可拖动地图）", "Click a built 3D station to add it to the line! (Drag to pan map)"))
			return
		_draft_insert_station(sid)


func _mark_modified_and_quick_save() -> void:
	if not _is_demo_readonly:
		_save_current_progress(false)


func _rebuild_tracks_only_visual() -> void:
	_ops_dirty = true
	for c in _track_root.get_children():
		c.queue_free()
	var built := TrackBuilder.build_network_tracks_and_stations(
		_track_root,
		_graph,
		_cjk_font,
		_grass_track_mat
	)
	_station_views = built["stations"]
	if _pax_sim != null:
		_pax_sim.rebind_station_views(_station_views)
	_put_tracks_on_terrain()
	_sync_landmark_monorail()
	if _city_tiles != null:
		_city_tiles.set_track_context(_graph.get_meta("track_clear_idx", {}), _graph.get_meta("station_bays", []))
	CityBuilder.apply_track_clearance(_city_root, _graph.get_meta("track_clear_idx", {}), _graph.get_meta("station_bays", []))
	CityBuilder.apply_station_bays(_city_root, _graph.get_meta("station_bays", []), _graph.get_meta("track_clear_idx", {}))
	_sync_portal_cutouts()
	_apply_underground_track_roof_visibility()
	_track_lights.clear()
	for l in built["lights"]:
		_track_lights.append(l)
	_apply_lighting_from_clock()


func _process(delta: float) -> void:
	if _startup_loading:
		_tick_loading_spinner(delta)
		return
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
			_btn_home_reset.text = L10n.t("重新开始", "Reset Map")

	_update_city_overview()
	# Outer map tiles stream in on a worker thread on every screen (home backdrop included)
	if _city_tiles != null and _camera != null and not _overview_on:
		_city_tiles.focus = _camera.global_position
		_city_tiles.step()

	# Save manager open during play: the game is paused (no simulation, clock, traffic or autosave)
	if _slot_modal != null and _slot_modal.visible and not _in_home_menu and not _game_over:
		_sound.speed_mps = 0.0
		_sound.traction_effort = 0.0
		_sound.overspeed_squeal = 0.0
		_sound.weather_rain_intensity = 0.0
		if _weather != null:
			_weather.set_paused(true)
		_process_shot_tour()
		return

	var paused_run := _run_paused and _game_mode == GameMode.RUN
	if _lbl_paused != null:
		_lbl_paused.visible = paused_run and not _in_home_menu and not _game_over
	if _game_mode == GameMode.RUN and not _in_home_menu and not _game_over and not paused_run:
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
		_sound.speed_mps = 0.0
		_sound.traction_effort = 0.0
		_sound.overspeed_squeal = 0.0
		_sound.weather_rain_intensity = 0.0
		_update_home_backdrop_camera()
		if _weather != null:
			_weather.set_paused(false)
			_weather.update_camera_follow(_camera, false)
		_process_shot_tour()
		return

	# Periodic rotating auto-save every 120 seconds during active play
	if not _is_demo_readonly and not paused_run:
		_autosave_timer += dt
		if _autosave_timer >= 120.0:
			_autosave_timer = 0.0
			var auto_nm := L10n.t("定时自动存档", "Scheduled Autosave")
			var payload := _build_current_save_payload(auto_nm)
			SaveManager.save_current(_current_map_key, payload)
			SaveManager.push_autosave(_current_map_key, auto_nm, payload)

	if _slot_modal == null or not _slot_modal.visible:
		_handle_bird_pan_keys(dt)

	if paused_run:
		# Paused: nothing moves, but the camera, HUD and operations board still work
		_sound.speed_mps = 0.0
		_sound.traction_effort = 0.0
		_sound.overspeed_squeal = 0.0
		if _slot_modal == null or not _slot_modal.visible:
			_handle_run_arrow_camera_keys(dt)
		_hud_refresh_timer += dt
		if _hud_refresh_timer >= 0.065:
			_hud_refresh_timer = 0.0
			_update_run_hud()
	elif _game_mode == GameMode.RUN:
		if _slot_modal == null or not _slot_modal.visible:
			_handle_run_held_keys(dt)
			_handle_run_arrow_camera_keys(dt)
		_pax_sim.step_simulation(dt, _graph, _camera.global_position if is_instance_valid(_camera) else _get_traffic_focus_pos())
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
	var is_raining := (_weather_mode == WeatherSystem.WeatherType.RAINY)
	var is_in_cab := (_game_mode == GameMode.RUN and (_cam_mode == CamMode.CAB or _cam_mode == CamMode.INTERIOR))
	if _weather != null:
		_weather.set_paused(paused_run)
		_weather.update_camera_follow(_camera, is_in_cab)
	if _sound != null:
		_sound.weather_rain_intensity = 1.0 if (is_raining and _game_mode == GameMode.RUN and not paused_run) else 0.0
		_sound.weather_rain_muffled = is_in_cab
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


# ---------------------------------------------------------------------------------------------
# Whole-city overview: past OVERVIEW_ON_H the bird's-eye view swaps the detailed city (façades, kerbs, trees,
# furniture, streamed tiles, cars, pedestrians, shadows) for one light model of the whole map, so the player
# can zoom out until the whole city is on screen. Building and planning are off while it shows.
# ---------------------------------------------------------------------------------------------
func _overview_wanted() -> bool:
	if _camera == null or _in_home_menu:
		return false
	var bird := _game_mode != GameMode.RUN or _cam_mode == CamMode.BIRD or _transit_sim.trams.is_empty()
	if not bird:
		return false
	return _plan_height > (OVERVIEW_OFF_H if _overview_on else OVERVIEW_ON_H)


func _overview_signature() -> String:
	return "%s|%s|%d|%d|%d" % [_current_map_key, str(_graph.land_edit_signature()), _graph.built_tracks.size(), _graph.stations.size(), hash(_graph.built_tracks.keys())]


func _overview_snapshot() -> Dictionary:
	var d := _effective_land_data()
	var tracks: Array = []
	for eid in _graph.built_tracks.keys():
		if not _graph.edges.has(eid):
			continue
		var pts: Array = []
		for p in _graph.edges[eid]["pts"]:
			pts.append(p as Vector2)
		tracks.append({"pts": pts, "mono": int(_graph.built_tracks[eid]) == TrackBuilder.BedStyle.MONORAIL})
	var sts: Array = []
	for st: Dictionary in _graph.stations.values():
		var sp: Vector3 = st["pos"]
		sts.append(Vector2(sp.x, sp.z))
	return {
		"buildings": d.get("buildings", []),
		"roads": d.get("roads", []),
		"areas": d.get("areas", []),
		"freeways": d.get("freeways", []),
		"railways": d.get("railways", []),
		"landmarks": d.get("landmarks", {}),
		"tracks": tracks,
		"stations": sts,
	}


func _overview_thread(snap: Dictionary) -> void:
	_overview_result = CityOverview.build(snap)


func _update_city_overview() -> void:
	_overview_toast_cd = maxf(0.0, _overview_toast_cd - get_process_delta_time())
	var want := _overview_wanted()
	# (re)build in the background whenever it is wanted and the map, the streets or the network changed
	if _overview_task >= 0 and WorkerThreadPool.is_task_completed(_overview_task):
		WorkerThreadPool.wait_for_task_completion(_overview_task)
		_overview_task = -1
		if _overview_root != null:
			_overview_root.queue_free()
		_overview_root = _overview_result
		_overview_result = null
		_overview_root.visible = _overview_on
		add_child(_overview_root)
	var sig := _overview_signature()
	if (want or _plan_height > OVERVIEW_ON_H * 0.7) and _overview_task < 0 and sig != _overview_sig and (Terrain.active or CityTiles.has_tiles(_map_data)):
		_overview_sig = sig
		_overview_task = WorkerThreadPool.add_task(_overview_thread.bind(_overview_snapshot()), false, "city overview")
	# switch only once there is something to show
	if want and not _overview_on and _overview_root != null:
		_set_overview(true)
	elif not want and _overview_on:
		_set_overview(false)
	if _overview_on:
		_traffic_sim.visible = false
		_pax_sim.visible = false


func _set_overview(on: bool) -> void:
	_overview_on = on
	if _overview_root != null:
		_overview_root.visible = on
	for c in _city_root.get_children():
		if c is Node3D and c.name != "TerrainGround" and c.name != "UrbanSidewalkBase":
			(c as Node3D).visible = not on
	_track_root.visible = not on
	if on:
		_overview_saved_far = _camera.far
		_camera.far = 16000.0
		_sun.shadow_enabled = false
		_preview_mi.mesh = null
		if _game_mode != GameMode.RUN and _overview_toast_cd <= 0.0:
			_show_toast(L10n.t("全城视图：放大后可以建设 / 规划", "City Overview: zoom in to build or plan"))
			_overview_toast_cd = 20.0
	else:
		_camera.far = maxf(_overview_saved_far, maxf(4500.0, _plan_height * 4.8))
		_sun.shadow_enabled = true
		var run_vis := _game_mode == GameMode.RUN and not _in_home_menu
		_traffic_sim.visible = run_vis
		_pax_sim.visible = run_vis


func _zoom_camera(step_dir: float) -> void:
	if _game_mode != GameMode.RUN or _cam_mode == CamMode.BIRD:
		_plan_height = clampf(_plan_height * (1.0 + step_dir * 0.13), 55.0, _plan_max_height)
	elif _cam_mode == CamMode.CAB or _cam_mode == CamMode.INTERIOR:
		_cab_fov = clampf(_cab_fov * (1.0 + step_dir * 0.12), 30.0, 92.0)
	elif _cam_mode == CamMode.CHASE:
		_orbit_dist = clampf(_orbit_dist * (1.0 + step_dir * 0.11), 7.5, 95.0)


func _set_cam_mode(mode: int) -> void:
	_cam_mode = mode
	for i in range(_cam_btns.size()):
		_highlight_active_btn(_cam_btns[i], i == _cam_mode)
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
		_sun.directional_shadow_max_distance = 220.0


func _update_camera(dt: float) -> void:
	if _game_mode != GameMode.RUN or _cam_mode == CamMode.BIRD or _transit_sim.trams.is_empty():
		# the bird's-eye view looks at the real ground under its target; scale far clip so zooming out never clips to grey
		_camera.far = 16000.0 if _overview_on else maxf(4500.0, _plan_height * 4.8)
		var gy := Terrain.surface(_plan_target.x, _plan_target.z)
		_plan_target.y = gy if _snap_camera_next else lerpf(_plan_target.y, gy, minf(1.0, dt * 6.0))
		var cam_pos := _plan_target + Vector3(0.0, _plan_height, _plan_height * 0.20)
		if _snap_camera_next:
			_camera.global_position = cam_pos
			_snap_camera_next = false
		else:
			_camera.global_position = _camera.global_position.lerp(cam_pos, minf(1.0, dt * 12.0))
		_camera.look_at(_plan_target, Vector3.FORWARD)
		return
	if not _overview_on:
		_camera.far = 2800.0

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
		var near_st := _transit_sim._find_station_at_current_pos(tr, _transit_sim.manual_drive, _graph)
		var near_sid := int(near_st.get("station_id", -1))
		if int(near_st["stop_idx"]) >= 0:
			var st_pos: Vector3 = (tr["stops"] as Array)[int(near_st["stop_idx"])]["pos"]
			var local_st := front_sec.global_transform.affine_inverse() * st_pos
			side_sign = 1.0 if local_st.x >= 0.0 else -1.0
		elif near_sid >= 0 and _graph.stations.has(near_sid):
			var st_pos_u: Vector3 = _graph.stations[near_sid]["pos"]
			var local_st_u := front_sec.global_transform.affine_inverse() * st_pos_u
			side_sign = 1.0 if local_st_u.x >= 0.0 else -1.0
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
		var gy_tr := Terrain.surface(focus.x, focus.z)
		var desired_pos := Vector3.ZERO
		if focus.y < gy_tr - 1.8 and not _underground_view:
			# Underground tunnel chase: stay snugly inside the lit tunnel envelope behind the train!
			var back_dir := -Vector3(lead_fwd.x, 0.0, lead_fwd.z).normalized()
			if back_dir.length_squared() < 0.01:
				back_dir = Vector3.BACK
			desired_pos = focus + back_dir * clampf(_orbit_dist * 0.55, 7.0, 14.5) + Vector3(0.0, 1.35, 0.0)
		else:
			var total_yaw := tr_yaw + _orbit_yaw + PI
			var horiz := cos(_orbit_pitch) * _orbit_dist
			var offset := Vector3(sin(total_yaw) * horiz, sin(_orbit_pitch) * _orbit_dist, cos(total_yaw) * horiz)
			desired_pos = focus + offset
			desired_pos.y = maxf(desired_pos.y, focus.y - 1.2)
			if not _underground_view:
				desired_pos.y = maxf(desired_pos.y, Terrain.surface(desired_pos.x, desired_pos.z) + 1.5) # never inside a hill
		if _snap_camera_next:
			_camera.global_position = desired_pos
			_snap_camera_next = false
		else:
			_camera.global_position = _camera.global_position.lerp(desired_pos, 1.0 - exp(-dt * 12.0))
		_camera.look_at(focus, Vector3.UP)


# --- Preview Mesh Helpers for Build & Plan Modes ---
func _set_ribbon_preview(mi: MeshInstance3D, edge_ids: Array[int], col: Color, width: float, elev_y: float = 0.0) -> void:
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
		if Terrain.active:
			var dense: Array = []
			for p2: Vector2 in pts:
				dense.append([p2.x, p2.y])
			pts = []
			for q in Terrain.densify(dense, 6.0):
				pts.append(Vector2(float(q[0]), float(q[1])))
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := b - a
			if d.length() < 0.1:
				continue
			var nrm := Vector2(-d.y, d.x).normalized() * hw
			var y := elev_y + 0.32
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
	mi.mesh = Terrain.drape_mesh(st.commit()) if Terrain.active else st.commit()
	mi.material_override = _translucent_mat(col)


func _set_sloped_ribbon_preview(mi: MeshInstance3D, pa: Vector2, pb: Vector2, ya: float, yb: float, width: float, col: Color) -> void:
	var seg := pb - pa
	if seg.length() < 0.5:
		mi.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nrm := Vector2(-seg.y, seg.x).normalized() * (width * 0.5)
	var steps := 14
	for k in range(steps):
		var t0 := float(k) / float(steps)
		var t1 := float(k + 1) / float(steps)
		var a := pa.lerp(pb, t0)
		var b := pa.lerp(pb, t1)
		var y0 := NetworkGraph.hermite_elev(ya, yb, t0) + 0.35 + Terrain.surface(a.x, a.y)
		var y1 := NetworkGraph.hermite_elev(ya, yb, t1) + 0.35 + Terrain.surface(b.x, b.y)
		for v: Vector3 in [
			Vector3(a.x - nrm.x, y0, a.y - nrm.y),
			Vector3(b.x + nrm.x, y1, b.y + nrm.y),
			Vector3(a.x + nrm.x, y0, a.y + nrm.y),
			Vector3(a.x - nrm.x, y0, a.y - nrm.y),
			Vector3(b.x - nrm.x, y1, b.y - nrm.y),
			Vector3(b.x + nrm.x, y1, b.y + nrm.y),
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
	mi.global_transform = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, Terrain.surface(pos.x, pos.z), 0.0))
	mi.material_override = _translucent_mat(col)


func _set_oriented_box_preview(mi: MeshInstance3D, pos: Vector3, fwd: Vector3, sz: Vector3, col: Color) -> void:
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos + Vector3(0.0, Terrain.surface(pos.x, pos.z), 0.0))
	mi.material_override = _translucent_mat(col)


# Build / plan overlays: translucent, unshaded, and pulled a little toward the camera in depth so they always
# show over the street they highlight (on slopes the draped road surface can rise above a thin ground offset
# between its vertices), while buildings in front still hide them.
static var _overlay_shader: Shader = null

static func _translucent_mat(col: Color) -> ShaderMaterial:
	if _overlay_shader == null:
		_overlay_shader = Shader.new()
		_overlay_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.2, 0.9, 0.5, 0.7);
void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vp.xyz);
	// toward the eye by 1.5 m + 0.4 % of the distance (never past the near plane)
	vp.xyz *= max(0.05, 1.0 - (1.5 + d * 0.004) / max(d, 0.001));
	POSITION = PROJECTION_MATRIX * vp;
}
void fragment() {
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _overlay_shader
	m.set_shader_parameter("col", col)
	return m


# --- UI Construction & Callbacks ---
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	_ui_canvas = canvas
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
	_nav_bar.position = Vector2(-565, 12)
	_hud_layer_ctrl.add_child(_nav_bar)

	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 7)
	_nav_bar.add_child(nav_hbox)

	nav_hbox.add_child(_make_btn(L10n.t("◀ 主页(Esc)", "◀ Home (Esc)"), func(): _enter_home_screen()))
	nav_hbox.add_child(VSeparator.new())

	_btn_mode_build = _make_btn(L10n.t("[1] 建设轨道", "[1] Build Track"), func(): _request_game_mode(GameMode.BUILD))
	_btn_mode_plan = _make_btn(L10n.t("[2] 规划线路", "[2] Plan Lines"), func(): _request_game_mode(GameMode.PLAN))
	_btn_mode_run = _make_btn(L10n.t("[3] 运行与驾驶 (Tab)", "[3] Run & Drive (Tab)"), func(): _request_game_mode(GameMode.RUN))
	nav_hbox.add_child(_btn_mode_build)
	nav_hbox.add_child(_btn_mode_plan)
	nav_hbox.add_child(_btn_mode_run)

	nav_hbox.add_child(VSeparator.new())
	nav_hbox.add_child(_make_btn(L10n.t("存档(F5/F9)", "Saves (F5)"), func(): _open_slot_modal(_current_map_key, false)))
	_btn_quick_save_run = _make_btn(L10n.t("存运行档", "Save Run"), func(): _open_slot_modal(_current_map_key, false))
	nav_hbox.add_child(_btn_quick_save_run)
	nav_hbox.add_child(_make_btn(L10n.t("运营看板(T)", "Ops Board (T)"), func(): _toggle_stats_modal()))
	nav_hbox.add_child(_make_btn(L10n.t("游戏设置", "Settings"), func(): _toggle_audio_modal()))
	_btn_underground = _make_btn(L10n.t("地下视图(U)", "Underground(U)"), func(): _set_underground_view(not _underground_view))
	_btn_underground.tooltip_text = L10n.t("切换地下透视视图（显示地下隧道/地铁站与地表蓝图参考线，快捷键 U）", "Toggle Underground X-Ray View (inspect/build tunnels & subway stations, key U)")
	nav_hbox.add_child(_btn_underground)
	nav_hbox.add_child(VSeparator.new())
	nav_hbox.add_child(_make_btn(L10n.t("纯白天", "Day"), func(): _set_time_hours(13.5)))
	nav_hbox.add_child(_make_btn(L10n.t("纯夜景", "Night"), func(): _set_time_hours(22.0)))
	_btn_weather = _make_btn(WeatherSystem.weather_button_label(_weather_mode), func(): _cycle_weather_mode())
	_btn_weather.tooltip_text = L10n.t("点击切换天气：晴天 / 阴天 / 雨天（雨天带雨声，亦可在游戏设置中直选）", "Click to cycle weather: Sunny / Cloudy / Rainy (rain includes rainfall ambience)")
	nav_hbox.add_child(_btn_weather)

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

	_lbl_paused = Label.new()
	_lbl_paused.set_anchors_preset(Control.PRESET_CENTER)
	_lbl_paused.position = Vector2(-260, -40)
	_lbl_paused.custom_minimum_size = Vector2(520, 80)
	_lbl_paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_paused.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_paused.text = L10n.t("⏸ 已暂停\n按 V 或点击【▶ 继续】恢复运营 · 视角仍可移动", "⏸ PAUSED\nPress V or click [▶ Resume] to continue · Camera remains free")
	_lbl_paused.add_theme_font_size_override("font_size", 22)
	_lbl_paused.add_theme_color_override("font_color", Color(0.98, 0.96, 0.86))
	_lbl_paused.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_lbl_paused.add_theme_constant_override("shadow_offset_x", 2)
	_lbl_paused.add_theme_constant_override("shadow_offset_y", 2)
	_lbl_paused.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_paused.visible = false
	master_root.add_child(_lbl_paused)

	# Interactive 3D Cab Control Hover Tooltip
	_lbl_cab_tip = Label.new()
	_lbl_cab_tip.add_theme_font_size_override("font_size", 13)
	_lbl_cab_tip.add_theme_color_override("font_color", Color(0.55, 0.96, 0.80))
	_lbl_cab_tip.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.90))
	_lbl_cab_tip.add_theme_constant_override("shadow_offset_x", 1)
	_lbl_cab_tip.add_theme_constant_override("shadow_offset_y", 1)
	_lbl_cab_tip.visible = false
	master_root.add_child(_lbl_cab_tip)

	# 2. BUILD MODE PANEL (Left Side — Two-Level Collapsible Category Accordion)
	_build_panel = _make_panel(Color(0.07, 0.09, 0.12, 0.92))
	_build_panel.position = Vector2(16, 72)
	_build_panel.custom_minimum_size = Vector2(362, 0)
	_hud_layer_ctrl.add_child(_build_panel)

	var b_vbox := VBoxContainer.new()
	b_vbox.add_theme_constant_override("separation", 6)
	_build_panel.add_child(b_vbox)

	var b_title := Label.new()
	b_title.text = L10n.t("轨道与车站建设", "Track & Station Construction")
	b_title.add_theme_font_size_override("font_size", 15)
	b_title.add_theme_color_override("font_color", Color(0.50, 0.90, 0.72))
	b_vbox.add_child(b_title)

	var b_sub := Label.new()
	b_sub.text = L10n.t("点击建造类别展开二级选项 · 轨道类型铺设后锁定", "Click a category to expand options · Track type locks once laid")
	b_sub.add_theme_font_size_override("font_size", 11)
	b_sub.add_theme_color_override("font_color", Color(0.62, 0.68, 0.74))
	b_vbox.add_child(b_sub)

	_build_cat_btns.clear()
	_build_cat_subpanels.clear()
	_track_lay_btns.clear()
	_track_mode_btns.clear()
	_bed_btns.clear()
	_crossover_type_btns.clear()
	_station_kind_btns.clear()
	_station_len_btns.clear()
	_road_tool_btns.clear()
	_lane_cfg_btns.clear()

	var make_sub_box := func() -> Array:
		var sub_wrap := MarginContainer.new()
		sub_wrap.add_theme_constant_override("margin_left", 6)
		sub_wrap.add_theme_constant_override("margin_top", 0)
		sub_wrap.add_theme_constant_override("margin_bottom", 4)
		var sub_panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.045, 0.062, 0.088, 0.88)
		sb.corner_radius_top_left = 4; sb.corner_radius_top_right = 7
		sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 7
		sb.border_width_left = 3; sb.border_width_top = 1
		sb.border_width_right = 1; sb.border_width_bottom = 1
		sb.border_color = Color(0.32, 0.82, 0.62, 0.65)
		sb.content_margin_left = 10; sb.content_margin_right = 10
		sb.content_margin_top = 8; sb.content_margin_bottom = 8
		sub_panel.add_theme_stylebox_override("panel", sb)
		sub_wrap.add_child(sub_panel)
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 6)
		sub_panel.add_child(sv)
		b_vbox.add_child(sub_wrap)
		return [sub_wrap, sv]

	var add_sub_lbl := func(parent_v: VBoxContainer, txt: String) -> void:
		var l := Label.new()
		l.text = txt
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(0.68, 0.76, 0.82))
		parent_v.add_child(l)

	# --- Category 0: 修建轨道 (Track) ---
	var cat_track_btn := _make_cat_btn(L10n.t("修建轨道", "Build Track"), func():
		_build_tool = _last_track_tool
		_path_start_node = -1
		_refresh_build_buttons()
	)
	b_vbox.add_child(cat_track_btn)
	_build_cat_btns.append(cat_track_btn)

	var track_sub_pair: Array = make_sub_box.call()
	var track_sub_wrap: Control = track_sub_pair[0]
	var track_sv: VBoxContainer = track_sub_pair[1]
	_build_cat_subpanels.append(track_sub_wrap)

	add_sub_lbl.call(track_sv, L10n.t("铺设方式", "Laying Mode"))
	var lay_row := HBoxContainer.new()
	lay_row.add_theme_constant_override("separation", 6)
	track_sv.add_child(lay_row)
	for lay_pair: Array in [
		[BuildTool.TRACK_SINGLE, L10n.t("单段铺设", "Single Seg")],
		[BuildTool.TRACK_PATH, L10n.t("两点寻路", "Pathfind")],
		[BuildTool.TRACK_OFFROAD, L10n.t("立体直连", "3D Free")],
	]:
		var lay_val := int(lay_pair[0])
		var lb := _make_btn(str(lay_pair[1]), func():
			_build_tool = lay_val
			_last_track_tool = lay_val
			_path_start_node = -1
			_land_prev_has = false
			_refresh_build_buttons()
		)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lay_row.add_child(lb)
		_track_lay_btns.append(lb)

	add_sub_lbl.call(track_sv, L10n.t("轨道制式", "Track Layout"))
	var tm_row := HBoxContainer.new()
	tm_row.add_theme_constant_override("separation", 6)
	track_sv.add_child(tm_row)
	for t_pair: Array in [
		[NetworkGraph.TrackMode.SINGLE, L10n.t("单线", "Single")],
		[NetworkGraph.TrackMode.DOUBLE, L10n.t("双线并行", "Double")],
		[NetworkGraph.TrackMode.QUAD, L10n.t("四轨快慢线", "4-Track")],
	]:
		var tm_val := int(t_pair[0])
		var tmb := _make_btn(str(t_pair[1]), func():
			_build_track_mode = tm_val
			_build_tool = _last_track_tool
			_refresh_build_buttons()
		)
		tmb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tm_row.add_child(tmb)
		_track_mode_btns.append(tmb)

	add_sub_lbl.call(track_sv, L10n.t("建造高程（[ / ] 或 PgUp/PgDn 升降）", "Build Elevation ([ / ] or PgUp/PgDn)"))
	var elev_row := HBoxContainer.new()
	elev_row.add_theme_constant_override("separation", 4)
	track_sv.add_child(elev_row)
	_elev_btns.clear()
	var elev_short_labels := [
		"B2 -18m",
		"B1 -10m",
		L10n.t("G 地面", "G 0m"),
		"L1 +7m",
		"L2 +14m",
	]
	for ei in range(elev_short_labels.size()):
		var ei_copy := ei
		var eb := _make_btn(elev_short_labels[ei], func():
			_set_build_elev_idx(ei_copy, true)
			_build_tool = _last_track_tool
		)
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elev_row.add_child(eb)
		_elev_btns.append(eb)

	add_sub_lbl.call(track_sv, L10n.t("轨道与道床类型", "Track & Trackbed Style"))
	var bed_grid := GridContainer.new()
	bed_grid.columns = 2
	bed_grid.add_theme_constant_override("h_separation", 6)
	bed_grid.add_theme_constant_override("v_separation", 5)
	track_sv.add_child(bed_grid)
	var bed_short_names := [
		L10n.t("独立工字草皮", "Turf Tie-Track"),
		L10n.t("柏油槽型嵌轨", "Asphalt Grooved"),
		L10n.t("齐平绿茵草皮", "Flush Lawn"),
		L10n.t("花岗岩专用道", "Granite ROW"),
		L10n.t("碎石工字枕木", "Ballasted Ties"),
		L10n.t("跨座式单轨", "Monorail"),
	]
	for bi in range(BED_STYLE_NAMES.size()):
		var b_copy := bi
		var bb := _make_btn(bed_short_names[bi], func():
			_build_bed_style = b_copy
			if TrackBuilder.is_monorail_style(b_copy) and _build_elev_idx == 2:
				_build_elev_idx = 3 # monorail defaults cleanly to L1 (+7.2m) elevated
			_build_tool = _last_track_tool
			_refresh_build_buttons()
		)
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bed_grid.add_child(bb)
		_bed_btns.append(bb)

	# --- Category 1: 修建渡线 (Crossover) ---
	var cat_xo_btn := _make_cat_btn(L10n.t("修建渡线", "Build Crossover"), func():
		_build_tool = BuildTool.CROSSOVER
		_path_start_node = -1
		_refresh_build_buttons()
	)
	b_vbox.add_child(cat_xo_btn)
	_build_cat_btns.append(cat_xo_btn)

	var xo_sub_pair: Array = make_sub_box.call()
	var xo_sub_wrap: Control = xo_sub_pair[0]
	var xo_sv: VBoxContainer = xo_sub_pair[1]
	_build_cat_subpanels.append(xo_sub_wrap)

	add_sub_lbl.call(xo_sv, L10n.t("渡线类型（按 R 键切换）", "Crossover Type (Press R to toggle)"))
	var xo_row := HBoxContainer.new()
	xo_row.add_theme_constant_override("separation", 6)
	xo_sv.add_child(xo_row)
	for xo_pair: Array in [
		[NetworkGraph.CrossoverType.SINGLE, L10n.t("单渡线", "Single")],
		[NetworkGraph.CrossoverType.DOUBLE, L10n.t("交叉双渡线", "Scissors")],
	]:
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

	var xo_tip := Label.new()
	xo_tip.text = L10n.t("点击双线轨道即可放置，自动避让站台与合并过渡段", "Click any double-track segment to place; avoids platforms & merge tapers automatically")
	xo_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	xo_tip.custom_minimum_size = Vector2(310, 0)
	xo_tip.add_theme_font_size_override("font_size", 11)
	xo_tip.add_theme_color_override("font_color", Color(0.60, 0.68, 0.74))
	xo_sv.add_child(xo_tip)

	# --- Category 2: 修建车站 (Station) ---
	var cat_st_btn := _make_cat_btn(L10n.t("修建车站", "Build Station"), func():
		_build_tool = BuildTool.STATION
		_path_start_node = -1
		_refresh_build_buttons()
	)
	b_vbox.add_child(cat_st_btn)
	_build_cat_btns.append(cat_st_btn)

	var st_sub_pair: Array = make_sub_box.call()
	var st_sub_wrap: Control = st_sub_pair[0]
	var st_sv: VBoxContainer = st_sub_pair[1]
	_build_cat_subpanels.append(st_sub_wrap)

	add_sub_lbl.call(st_sv, L10n.t("站台形式（按 R 键换侧）", "Platform Type (Press R to flip side)"))
	var sk_row := HBoxContainer.new()
	sk_row.add_theme_constant_override("separation", 5)
	st_sv.add_child(sk_row)
	for sk_pair: Array in [
		[NetworkGraph.StationKind.SIDE_SINGLE, L10n.t("单侧", "Single Side")],
		[NetworkGraph.StationKind.SIDE_DUAL, L10n.t("对称双侧", "Dual Side")],
		[NetworkGraph.StationKind.ISLAND, L10n.t("中央岛式", "Island")],
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

	add_sub_lbl.call(st_sv, L10n.t("站台长度", "Platform Length"))
	var sl_row := HBoxContainer.new()
	sl_row.add_theme_constant_override("separation", 5)
	st_sv.add_child(sl_row)
	var sl_labels := [
		L10n.t("27m (2节)", "27m (2-car)"),
		L10n.t("38m (3节)", "38m (3-car)"),
		L10n.t("50m (4节)", "50m (4-car)"),
	]
	for li in range(STATION_LEN_PRESETS.size()):
		var li_copy := li
		var slb := _make_btn(sl_labels[li], func():
			_build_station_len_idx = li_copy
			_build_tool = BuildTool.STATION
			_path_start_node = -1
			_refresh_build_buttons()
		)
		slb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl_row.add_child(slb)
		_station_len_btns.append(slb)

	add_sub_lbl.call(st_sv, L10n.t("站名（点击已有车站或新建后修改）", "Station Name (click existing or new station)"))
	var rename_row := HBoxContainer.new()
	rename_row.add_theme_constant_override("separation", 6)
	st_sv.add_child(rename_row)
	_edit_station_name = LineEdit.new()
	_edit_station_name.placeholder_text = L10n.t("输入站名...", "Enter station name...")
	_edit_station_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_station_name.text_submitted.connect(func(_txt: String): _apply_station_rename())
	rename_row.add_child(_edit_station_name)
	rename_row.add_child(_make_btn(L10n.t("改名", "Rename"), func(): _apply_station_rename()))

	# --- Category 3: 拆除 (Demolish) ---
	var cat_dem_btn := _make_cat_btn(L10n.t("拆除车站 / 轨道", "Demolish Station / Track"), func():
		_build_tool = BuildTool.DEMOLISH
		_path_start_node = -1
		_refresh_build_buttons()
	)
	b_vbox.add_child(cat_dem_btn)
	_build_cat_btns.append(cat_dem_btn)

	var dem_sub_pair: Array = make_sub_box.call()
	var dem_sub_wrap: Control = dem_sub_pair[0]
	var dem_sv: VBoxContainer = dem_sub_pair[1]
	_build_cat_subpanels.append(dem_sub_wrap)

	var dem_tip := Label.new()
	dem_tip.text = L10n.t("将鼠标移到已有车站、渡线或轨道段上，单击高亮红框即可拆除", "Hover an existing station, crossover, or track segment and click to demolish")
	dem_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dem_tip.custom_minimum_size = Vector2(310, 0)
	dem_tip.add_theme_font_size_override("font_size", 11)
	dem_tip.add_theme_color_override("font_color", Color(0.86, 0.64, 0.62))
	dem_sv.add_child(dem_tip)

	# --- Category 4: 道路与地块 (roads, lanes, buildings) ---
	var cat_road_btn := _make_cat_btn(L10n.t("道路与地块", "Roads & Lots"), func():
		if _build_tool < BuildTool.ROAD_BUILD:
			_build_tool = BuildTool.ROAD_BUILD
		_land_prev_has = false
		_path_start_node = -1
		_refresh_build_buttons()
	)
	b_vbox.add_child(cat_road_btn)
	_build_cat_btns.append(cat_road_btn)
	var road_sub_pair: Array = make_sub_box.call()
	var road_sub_wrap: Control = road_sub_pair[0]
	var road_sv: VBoxContainer = road_sub_pair[1]
	_build_cat_subpanels.append(road_sub_wrap)
	add_sub_lbl.call(road_sv, L10n.t("工具", "Tool"))
	var rt_row := HBoxContainer.new()
	rt_row.add_theme_constant_override("separation", 5)
	road_sv.add_child(rt_row)
	for rt_pair: Array in [
		[BuildTool.ROAD_BUILD, L10n.t("新建道路", "New Road")],
		[BuildTool.ROAD_REMOVE, L10n.t("拆除道路", "Del Road")],
		[BuildTool.ROAD_LANES, L10n.t("修改车道", "Lanes")],
		[BuildTool.BUILDING_DEMOLISH, L10n.t("拆除建筑", "Demolish")],
	]:
		var rt_val := int(rt_pair[0])
		var rtb := _make_btn(str(rt_pair[1]), func():
			_build_tool = rt_val
			_land_prev_has = false
			_path_start_node = -1
			_refresh_build_buttons()
		)
		rtb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rt_row.add_child(rtb)
		_road_tool_btns.append(rtb)
	add_sub_lbl.call(road_sv, L10n.t("车道（新建 / 修改道路时使用）", "Lanes (for New Road / Edit Lanes)"))
	var lane_grid := GridContainer.new()
	lane_grid.columns = 4
	lane_grid.add_theme_constant_override("h_separation", 5)
	lane_grid.add_theme_constant_override("v_separation", 5)
	road_sv.add_child(lane_grid)
	for li in range(LANE_CFGS.size()):
		var li_c := li
		var lcb := _make_btn(_lane_cfg_label(li), func():
			_road_lane_idx = li_c
			if _build_tool != BuildTool.ROAD_BUILD and _build_tool != BuildTool.ROAD_LANES:
				_build_tool = BuildTool.ROAD_BUILD
			_refresh_build_buttons()
		)
		lcb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lane_grid.add_child(lcb)
		_lane_cfg_btns.append(lcb)
	var road_tip := Label.new()
	road_tip.text = L10n.t("新建道路 / 空地直连轨道：依次点击各点连续施工（可从路口或路段中间接出），Esc 结束；不可穿过建筑，可先拆除建筑腾出空地", "New Road / Open-Ground Track: click points to chain segments (can branch from junctions or mid-block), Esc to finish. Clear buildings first if blocked.")
	road_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	road_tip.custom_minimum_size = Vector2(310, 0)
	road_tip.add_theme_font_size_override("font_size", 11)
	road_tip.add_theme_color_override("font_color", Color(0.70, 0.80, 0.86))
	road_sv.add_child(road_tip)

	var foot_sep := HSeparator.new()
	b_vbox.add_child(foot_sep)

	_lbl_build_hint = Label.new()
	_lbl_build_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_build_hint.custom_minimum_size = Vector2(336, 36)
	_lbl_build_hint.add_theme_font_size_override("font_size", 12)
	_lbl_build_hint.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90))
	_lbl_build_hint.text = L10n.t("提示：按下触摸板/左键拖动可平移地图，滚轮缩放，单击施工。", "Tip: Drag to pan map, scroll to zoom, click to build.")
	b_vbox.add_child(_lbl_build_hint)

	var util_row := HBoxContainer.new()
	util_row.add_theme_constant_override("separation", 6)
	b_vbox.add_child(util_row)
	var save_u := _make_btn(L10n.t("存档管理(F5)", "Saves (F5)"), func(): _open_slot_modal(_current_map_key, false))
	save_u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	util_row.add_child(save_u)
	var clr_u := _make_btn(L10n.t("清空全部重建", "Clear All"), func():
		_graph.clear_player_network()
		_refresh_land_layers_if_needed()
		_rebuild_tracks_and_operations(false)
		_mark_modified_and_quick_save()
		_show_toast(L10n.t("已清空全城轨道与线路，可从零自由建设！", "Cleared all tracks & lines. Ready to build from scratch!"))
	)
	clr_u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	util_row.add_child(clr_u)
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
	p_title.text = L10n.t("公交化电车线路规划与选车配车", "Line Planner & Fleet Assignment")
	p_title.add_theme_font_size_override("font_size", 15)
	p_title.add_theme_color_override("font_color", Color(0.48, 0.84, 0.98))
	p_vbox.add_child(p_title)

	_lbl_draft_stops = Label.new()
	_lbl_draft_stops.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_draft_stops.custom_minimum_size = Vector2(365, 0)
	_lbl_draft_stops.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	p_vbox.add_child(_lbl_draft_stops)

	# Editable stop list: delete any stop, or pick where the next clicked station is inserted
	var draft_scroll := ScrollContainer.new()
	draft_scroll.custom_minimum_size = Vector2(365, 118)
	draft_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p_vbox.add_child(draft_scroll)
	_draft_list_vbox = VBoxContainer.new()
	_draft_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draft_list_vbox.add_theme_constant_override("separation", 2)
	draft_scroll.add_child(_draft_list_vbox)

	var draft_btns := HBoxContainer.new()
	draft_btns.add_theme_constant_override("separation", 6)
	p_vbox.add_child(draft_btns)
	draft_btns.add_child(_make_btn(L10n.t("撤销上一站 (Bksp)", "Undo Stop (Bksp)"), func():
		_draft_undo_last()
	))
	draft_btns.add_child(_make_btn(L10n.t("清空选站", "Clear Stops"), func():
		_draft_station_ids.clear()
		_draft_insert_idx = -1
		_refresh_plan_ui()
	))

	var flt_row := HBoxContainer.new()
	flt_row.add_theme_constant_override("separation", 6)
	p_vbox.add_child(flt_row)
	flt_row.add_child(_make_btn(L10n.t("全部车型(17)", "All (17)"), func(): _set_era_filter("all")))
	flt_row.add_child(_make_btn(L10n.t("现代电车(8)", "Modern (8)"), func(): _set_era_filter("modern")))
	flt_row.add_child(_make_btn(L10n.t("古典老车(6)", "Vintage (6)"), func(): _set_era_filter("vintage")))
	flt_row.add_child(_make_btn(L10n.t("单轨(3)", "Monorail (3)"), func(): _set_era_filter("monorail")))

	var car_sel_row := HBoxContainer.new()
	car_sel_row.add_theme_constant_override("separation", 6)
	p_vbox.add_child(car_sel_row)
	car_sel_row.add_child(_make_btn(L10n.t("◀ 上一款", "◀ Prev Model"), func(): _step_plan_model(-1)))
	car_sel_row.add_child(_make_btn(L10n.t("下一款 ▶", "Next Model ▶"), func(): _step_plan_model(1)))

	_lbl_model_card = Label.new()
	_lbl_model_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_model_card.add_theme_color_override("font_color", Color(0.96, 0.90, 0.72))
	p_vbox.add_child(_lbl_model_card)

	var cfg_row := HBoxContainer.new()
	cfg_row.add_theme_constant_override("separation", 6)
	p_vbox.add_child(cfg_row)
	cfg_row.add_child(_make_btn(L10n.t("配车 -", "Fleet -"), func(): _plan_fleet_count = maxi(1, _plan_fleet_count - 1); _refresh_plan_ui()))
	cfg_row.add_child(_make_btn(L10n.t("配车 +", "Fleet +"), func(): _plan_fleet_count = mini(15, _plan_fleet_count + 1); _refresh_plan_ui()))
	cfg_row.add_child(_make_btn(L10n.t("编组 -", "Cars -"), func(): _plan_sections = maxi(1, _plan_sections - 1); _refresh_plan_ui()))
	cfg_row.add_child(_make_btn(L10n.t("编组 +", "Cars +"), func(): _plan_sections = mini(_max_sections_for_draft(), _plan_sections + 1); _refresh_plan_ui()))

	_btn_plan_service = _make_btn(L10n.t("运行类别：普通慢车", "Service: Local"), func():
		_plan_express = not _plan_express
		_refresh_plan_ui()
	)
	_btn_plan_service.tooltip_text = L10n.t("快车：在四轨区段走中间快车道，在四轨双岛站优先发车并越行慢车；慢车：走外侧慢车道，遇快车待避", "Express uses inner 4-track rails and overtakes locals at twin-island stops; Local uses outer rails and yields to express.")
	p_vbox.add_child(_btn_plan_service)

	_btn_plan_tsp = _make_btn(L10n.t("信号优先：关", "Signal Priority: OFF"), func():
		_plan_signal_priority = not _plan_signal_priority
		_refresh_plan_ui()
	)
	_btn_plan_tsp.tooltip_text = L10n.t("开启后，该线路电车接近路口信号灯时自动触发公交信号优先（延长绿灯 / 提前清空横向车流切绿）", "When enabled, trams on this line trigger Transit Signal Priority at intersections (extend green / early green).")
	p_vbox.add_child(_btn_plan_tsp)

	_lbl_fleet_cfg = Label.new()
	p_vbox.add_child(_lbl_fleet_cfg)

	var commit_row := HBoxContainer.new()
	commit_row.add_theme_constant_override("separation", 6)
	p_vbox.add_child(commit_row)
	_btn_commit_line = _make_btn(L10n.t("✓ 确认开通此线路", "✓ Launch Line"), func(): _commit_draft_line())
	_btn_commit_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commit_row.add_child(_btn_commit_line)
	_btn_cancel_edit = _make_btn(L10n.t("取消编辑", "Cancel Edit"), func(): _cancel_line_edit(true))
	_btn_cancel_edit.visible = false
	commit_row.add_child(_btn_cancel_edit)

	p_vbox.add_child(HSeparator.new())
	var exist_lbl := Label.new()
	exist_lbl.text = L10n.t("已开通运营线路：", "Active Lines:")
	p_vbox.add_child(exist_lbl)

	_lines_list_vbox = VBoxContainer.new()
	_lines_list_vbox.add_theme_constant_override("separation", 4)
	p_vbox.add_child(_lines_list_vbox)

	# 4. RUN & DRIVE MODE PANELS
	_run_top_panel = _make_panel(Color(0.07, 0.09, 0.12, 0.88))
	_run_top_panel.position = Vector2(16, 72)
	_run_top_panel.custom_minimum_size = Vector2(495, 178)
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
	rt_btns.add_child(_make_btn(L10n.t("◀ 上一线路", "◀ Prev Line"), func(): _switch_line(-1)))
	rt_btns.add_child(_make_btn(L10n.t("下一线路(L) ▶", "Next Line (L) ▶"), func(): _switch_line(1)))
	rt_btns.add_child(_make_btn(L10n.t("◀ 本线上一列", "◀ Prev Tram"), func(): _transit_sim.cycle_active_tram(-1)))
	rt_btns.add_child(_make_btn(L10n.t("本线下一列(F) ▶", "Next Tram (F) ▶"), func(): _transit_sim.cycle_active_tram(1)))
	_btn_pax_rate = _make_btn(L10n.t("客流: %s (P)", "Pax: %s (P)") % PassengerSim.spawn_level_name(_pax_sim.spawn_level if _pax_sim != null else 3), func():
		var lvl := _pax_sim.cycle_spawn_level()
		_btn_pax_rate.text = L10n.t("客流: %s (P)", "Pax: %s (P)") % PassengerSim.spawn_level_name(lvl)
		_mark_modified_and_quick_save()
	)
	rt_btns.add_child(_btn_pax_rate)

	var ai_row := HBoxContainer.new()
	ai_row.add_theme_constant_override("separation", 5)
	rt_vbox.add_child(ai_row)

	var ai_lbl := Label.new()
	ai_lbl.text = L10n.t("本车AI运营：", "Tram AI:")
	ai_lbl.add_theme_font_size_override("font_size", 13)
	ai_lbl.add_theme_color_override("font_color", Color(0.76, 0.86, 0.94))
	ai_row.add_child(ai_lbl)

	_ai_style_btns.clear()
	var ai_style_defs := [
		[L10n.t("缓慢", "Slow"), TransitSim.AIStyle.SLOW, L10n.t("缓慢模式：停稳后过2~3秒再开门、人上好后过几秒再关门、有乘客赶来会等待，开关门与加减速平缓柔和", "Slow: waits 2-3s before opening doors, holds for approaching riders, gentle acceleration & braking")],
		[L10n.t("正常", "Normal"), TransitSim.AIStyle.NORMAL, L10n.t("正常模式：当前标准运营基准", "Normal: standard transit operation profile")],
		[L10n.t("狂暴", "Furious"), TransitSim.AIStyle.FURIOUS, L10n.t("狂暴模式：加速度与刹车拉满、进出站高效，开关门与标准模式一致", "Furious: maximum acceleration & braking with smooth cruising and full normal boarding")],
	]
	for sd in ai_style_defs:
		var st_idx: int = sd[1]
		var sb := _make_btn(sd[0], func(): _on_set_active_tram_ai_style(st_idx))
		sb.tooltip_text = sd[2]
		ai_row.add_child(sb)
		_ai_style_btns.append(sb)

	ai_row.add_child(VSeparator.new())

	var spd_lbl := Label.new()
	spd_lbl.text = L10n.t("最高速度：", "Max Speed:")
	spd_lbl.add_theme_font_size_override("font_size", 13)
	spd_lbl.add_theme_color_override("font_color", Color(0.76, 0.86, 0.94))
	ai_row.add_child(spd_lbl)

	_btn_ai_spd_down = _make_btn("-5", func(): _on_adjust_active_tram_ai_max_kmh(-TransitSim.AI_SPEED_STEP_KMH))
	_btn_ai_spd_down.tooltip_text = L10n.t("降低本列 AI 车运营最高速度 (-5 km/h)", "Lower this AI tram's max speed (-5 km/h)")
	ai_row.add_child(_btn_ai_spd_down)

	_btn_ai_spd_val = _make_btn("70 km/h", func(): _on_reset_active_tram_ai_max_kmh())
	_btn_ai_spd_val.custom_minimum_size = Vector2(72, 0)
	_btn_ai_spd_val.tooltip_text = L10n.t("当前列车的 AI 运营最高速度（点击恢复该车型默认极速）", "Current AI tram max speed (click to reset to model default)")
	ai_row.add_child(_btn_ai_spd_val)

	_btn_ai_spd_up = _make_btn("+5", func(): _on_adjust_active_tram_ai_max_kmh(TransitSim.AI_SPEED_STEP_KMH))
	_btn_ai_spd_up.tooltip_text = L10n.t("提高本列 AI 车运营最高速度 (+5 km/h)", "Raise this AI tram's max speed (+5 km/h)")
	ai_row.add_child(_btn_ai_spd_up)

	# Per-Line AI Style Group Row
	var line_ai_row := HBoxContainer.new()
	line_ai_row.add_theme_constant_override("separation", 5)
	rt_vbox.add_child(line_ai_row)

	_lbl_line_ai_group = Label.new()
	_lbl_line_ai_group.text = L10n.t("本线AI整组：", "Line AI Group:")
	_lbl_line_ai_group.add_theme_font_size_override("font_size", 13)
	_lbl_line_ai_group.add_theme_color_override("font_color", Color(0.68, 0.90, 0.86))
	line_ai_row.add_child(_lbl_line_ai_group)

	_line_ai_style_btns.clear()
	var lsb_none := _make_btn(L10n.t("无默认", "No Default"), func(): _on_set_active_line_ai_style(TransitSim.LINE_AI_NONE))
	lsb_none.tooltip_text = L10n.t("取消当前线路的整组默认 AI 模式（保留各车当前独立设置，新发列车按正常模式）", "Clear line-level default AI mode (keeps each tram's individual mode; new trams use Normal)")
	line_ai_row.add_child(lsb_none)
	_line_ai_style_btns.append(lsb_none)
	for sd in ai_style_defs:
		var st_idx_l: int = sd[1]
		var lsb := _make_btn(sd[0], func(): _on_set_active_line_ai_style(st_idx_l))
		lsb.tooltip_text = L10n.t("将当前线路全部列车的 AI 运营模式统一设为【%s】（保存至运行档）", "Set ALL trams on the current line to [%s] mode (saved in run slots)") % str(sd[0])
		line_ai_row.add_child(lsb)
		_line_ai_style_btns.append(lsb)

	var tsp_row := HBoxContainer.new()
	tsp_row.add_theme_constant_override("separation", 6)
	rt_vbox.add_child(tsp_row)

	var tsp_lbl := Label.new()
	tsp_lbl.text = L10n.t("信号优先(TSP)：", "Signal Priority (TSP):")
	tsp_lbl.add_theme_font_size_override("font_size", 13)
	tsp_lbl.add_theme_color_override("font_color", Color(0.76, 0.86, 0.94))
	tsp_row.add_child(tsp_lbl)

	_btn_line_tsp = _make_btn(L10n.t("本线信号优先：关", "Line TSP: OFF"), func(): _on_toggle_active_line_tsp())
	_btn_line_tsp.tooltip_text = L10n.t("为当前线路开启/关闭公交信号优先（也可在运营看板中逐条线路开关）", "Toggle Transit Signal Priority for the current line (also available per-line in Ops Board)")
	tsp_row.add_child(_btn_line_tsp)

	_btn_global_tsp = _make_btn(L10n.t("全局信号优先：关", "Global TSP: OFF"), func(): _on_toggle_global_tsp())
	_btn_global_tsp.tooltip_text = L10n.t("全局为全城所有有轨电车线路开启/关闭公交信号优先", "Toggle Transit Signal Priority globally for all lines")
	tsp_row.add_child(_btn_global_tsp)

	_cam_panel = _make_panel(Color(0.07, 0.09, 0.12, 0.88))
	_cam_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cam_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cam_panel.grow_vertical = Control.GROW_DIRECTION_END
	_cam_panel.offset_left = -16.0
	_cam_panel.offset_right = -16.0
	_cam_panel.offset_top = 72.0
	_cam_panel.offset_bottom = 72.0
	_hud_layer_ctrl.add_child(_cam_panel)

	var cam_vbox := VBoxContainer.new()
	cam_vbox.add_theme_constant_override("separation", 6)
	_cam_panel.add_child(cam_vbox)

	var cam_hbox := HBoxContainer.new()
	cam_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cam_hbox.add_theme_constant_override("separation", 5)
	cam_vbox.add_child(cam_hbox)
	_cam_btns.clear()
	var cam_defs := [
		[L10n.t("1 驾驶室", "1 Cab"), CamMode.CAB],
		[L10n.t("2 追尾外景", "2 Chase"), CamMode.CHASE],
		[L10n.t("3 车厢内部", "3 Interior"), CamMode.INTERIOR],
		[L10n.t("4 车门上下客", "4 Doors"), CamMode.DOOR_ACTION],
		[L10n.t("5 鸟瞰全局", "5 Bird's-Eye"), CamMode.BIRD],
	]
	for cd in cam_defs:
		var mode_idx: int = cd[1]
		var cb := _make_btn(cd[0], func(): _set_cam_mode(mode_idx))
		cam_hbox.add_child(cb)
		_cam_btns.append(cb)
	for i in range(_cam_btns.size()):
		_highlight_active_btn(_cam_btns[i], i == _cam_mode)

	var cam_hint := Label.new()
	cam_hint.text = L10n.t(
		"↑↓←→ 视角移动/旋转 · W/S 牵引制动 · X 倒档 · O 车门 · V 暂停\nK 保留手动 · J 锁道岔 · U AI道岔 · G 手动扳道岔(特殊情况)",
		"Arrows Camera · W/S Throttle/Brake · X Reverse · O Doors · V Pause\nK Hold Manual · J Lock Switch · U AI Switch · G Throw Switch"
	)
	cam_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cam_hint.add_theme_font_size_override("font_size", 12)
	cam_hint.add_theme_color_override("font_color", Color(0.75, 0.82, 0.88))
	cam_hint.add_theme_constant_override("line_spacing", 2)
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
	_btn_doors = _make_btn(L10n.t("开关车门 (O/Space)", "Doors (O/Space)"), func(): _toggle_doors_with_safety_check())
	act_row.add_child(_btn_doors)
	act_row.add_child(_make_btn(L10n.t("叮叮铜铃警示 (H)", "Bell (H)"), func(): _ring_tram_bell()))
	_btn_drive_mode = _make_btn(L10n.t("切换手动驾驶 (Q)", "Manual Drive (Q)"), func(): _transit_sim.manual_drive = not _transit_sim.manual_drive)
	act_row.add_child(_btn_drive_mode)
	act_row.add_child(_make_btn(L10n.t("换端折返 (R)", "Change Cab (R)"), func(): _do_cab_change()))
	_btn_reverser = _make_btn(L10n.t("倒档 R (X)", "Reverse R (X)"), func(): _do_toggle_reverser())
	act_row.add_child(_btn_reverser)
	_btn_hold_manual = _make_btn(L10n.t("保留手动 (K)", "Hold Manual (K)"), func(): _do_toggle_hold_manual())
	_btn_hold_manual.tooltip_text = L10n.t("手动驾驶且停车时：切换到其他列车后，本车原地停车待命（不交给 AI），切回后继续手动驾驶", "When stopped in manual mode: keeps this tram parked in standby (not handed to AI) when you switch to another tram")
	act_row.add_child(_btn_hold_manual)
	_btn_sw_lock = _make_btn(L10n.t("锁定前方道岔 (J)", "Lock Switch (J)"), func(): _do_toggle_switch_lock())
	_btn_sw_lock.tooltip_text = L10n.t("把前方道岔按现在的位置锁住，调度不会再扳动它；本车驶出该道岔后自动解锁", "Locks the switch ahead in its current position until this tram clears it")
	act_row.add_child(_btn_sw_lock)
	_btn_auto_sw = _make_btn(L10n.t("AI 道岔: 开 (U)", "AI Switch: ON (U)"), func(): _do_toggle_auto_switches())
	_btn_auto_sw.tooltip_text = L10n.t("关闭后调度不再自动扳动任何道岔，道岔只能由玩家按 G 扳动", "When OFF, dispatcher stops moving switches automatically; throw them manually with G")
	act_row.add_child(_btn_auto_sw)
	_btn_pause = _make_btn(L10n.t("⏸ 暂停 (V)", "⏸ Pause (V)"), func(): _toggle_run_pause())
	act_row.add_child(_btn_pause)
	act_row.add_child(_make_btn(L10n.t("手动扳道岔 (G)", "Throw Switch (G)"), func(): _do_throw_switch()))

	# 5. HOME SCREEN OVERLAY (Map Selection + Progress Summary + Actions)
	_build_home_screen_ui(master_root)

	# 6. MULTI-SLOT SAVE/LOAD MANAGER MODAL (10 Manual + 5 Rotating Auto-saves)
	_build_slot_modal_ui(master_root)
	_build_audio_modal_ui(master_root)
	_build_stats_modal_ui(master_root)

	# 7. ACCIDENT / DERAILMENT GAME OVER MODAL (Forces Map Restart!)
	_build_gameover_modal_ui(master_root)

	# 8. BRANDED STARTUP LOADING OVERLAY (Instant frame-1 launch screen matching boot_splash bg_color)
	_build_startup_loading_ui(master_root)


func _build_startup_loading_ui(parent: Control) -> void:
	_startup_overlay = ColorRect.new()
	_startup_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_startup_overlay.color = Color(0.05, 0.08, 0.12, 1.0)
	_startup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_startup_overlay.visible = false
	parent.add_child(_startup_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_startup_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var icon_tex := load("res://assets/app_icon.png") as Texture2D
	if icon_tex != null:
		var tr_icon := TextureRect.new()
		tr_icon.texture = icon_tex
		tr_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr_icon.custom_minimum_size = Vector2(156, 156)
		tr_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(tr_icon)

	_startup_title_lbl = Label.new()
	_startup_title_lbl.text = "3D train game"
	_startup_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_startup_title_lbl.add_theme_font_size_override("font_size", 28)
	_startup_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	vbox.add_child(_startup_title_lbl)

	var bar_row := HBoxContainer.new()
	bar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_row.add_theme_constant_override("separation", 10)
	vbox.add_child(bar_row)

	_startup_bar = ProgressBar.new()
	_startup_bar.min_value = 0.0
	_startup_bar.max_value = 100.0
	_startup_bar.value = 10.0
	_startup_bar.show_percentage = false
	_startup_bar.custom_minimum_size = Vector2(360, 10)
	_startup_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.14, 0.19, 0.26, 1.0)
	bg_sb.corner_radius_top_left = 5; bg_sb.corner_radius_top_right = 5
	bg_sb.corner_radius_bottom_left = 5; bg_sb.corner_radius_bottom_right = 5
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.28, 0.80, 0.96, 1.0)
	fill_sb.corner_radius_top_left = 5; fill_sb.corner_radius_top_right = 5
	fill_sb.corner_radius_bottom_left = 5; fill_sb.corner_radius_bottom_right = 5
	_startup_bar.add_theme_stylebox_override("background", bg_sb)
	_startup_bar.add_theme_stylebox_override("fill", fill_sb)
	bar_row.add_child(_startup_bar)

	_startup_pct_lbl = Label.new()
	_startup_pct_lbl.text = "10%"
	_startup_pct_lbl.custom_minimum_size = Vector2(44, 0)
	_startup_pct_lbl.add_theme_font_size_override("font_size", 14)
	_startup_pct_lbl.add_theme_color_override("font_color", Color(0.55, 0.88, 0.98))
	bar_row.add_child(_startup_pct_lbl)

	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	vbox.add_child(status_row)

	_startup_spinner_lbl = Label.new()
	_startup_spinner_lbl.text = "⠋"
	_startup_spinner_lbl.add_theme_font_size_override("font_size", 16)
	_startup_spinner_lbl.add_theme_color_override("font_color", Color(0.32, 0.86, 0.98))
	status_row.add_child(_startup_spinner_lbl)

	_startup_status_lbl = Label.new()
	_startup_status_lbl.text = L10n.t("正在启动...", "Starting...")
	_startup_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_startup_status_lbl.add_theme_font_size_override("font_size", 14)
	_startup_status_lbl.add_theme_color_override("font_color", Color(0.76, 0.84, 0.92))
	status_row.add_child(_startup_status_lbl)


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
	main_card.custom_minimum_size = Vector2(920, 520)
	center_wrap.add_child(main_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	main_card.add_child(vbox)

	var top_bar_h := HBoxContainer.new()
	top_bar_h.add_theme_constant_override("separation", 6)
	vbox.add_child(top_bar_h)

	var title_sp := Control.new()
	title_sp.custom_minimum_size = Vector2(180, 0)
	top_bar_h.add_child(title_sp)

	var title := Label.new()
	title.text = "3D train game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	top_bar_h.add_child(title)

	var home_lang_box := HBoxContainer.new()
	home_lang_box.custom_minimum_size = Vector2(180, 0)
	home_lang_box.alignment = BoxContainer.ALIGNMENT_END
	home_lang_box.add_theme_constant_override("separation", 4)
	top_bar_h.add_child(home_lang_box)
	for lp in [["auto", L10n.t("自动", "Auto")], ["zh", "中文"], ["en", "EN"]]:
		var pref_c: String = lp[0]
		var lb_h := _make_btn(str(lp[1]), func(): _on_set_language(pref_c))
		lb_h.tooltip_text = L10n.t("切换界面语言（自动跟随系统语言）", "Switch UI language (Auto follows system locale)")
		_highlight_active_btn(lb_h, L10n.lang_pref == pref_c)
		home_lang_box.add_child(lb_h)

	var sub := Label.new()
	sub.text = L10n.t(
		"选择城市地图开始规划 · 支持独立工字草皮/柏油等多路权铺轨 · 17款现代/古典电车与单轨 · 10槽手动+5槽自动存档",
		"Choose a city map to build · Turf/grooved/monorail tracks · 17 modern, vintage & monorail fleets · 10 manual + 5 auto saves"
	)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(860, 0)
	sub.add_theme_color_override("font_color", Color(0.72, 0.80, 0.88))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# Horizontal scrollable city map carousel with left/right arrows (scales cleanly to any number of cities)
	var carousel_row := HBoxContainer.new()
	carousel_row.add_theme_constant_override("separation", 8)
	vbox.add_child(carousel_row)

	var btn_prev_cards := _make_btn("◀", func():
		if _home_cards_scroll != null:
			_home_cards_scroll.scroll_horizontal = maxi(0, _home_cards_scroll.scroll_horizontal - 382)
	)
	btn_prev_cards.custom_minimum_size = Vector2(30, 88)
	btn_prev_cards.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_prev_cards.tooltip_text = L10n.t("向左滚动地图列表", "Scroll map list left")
	carousel_row.add_child(btn_prev_cards)

	_home_cards_scroll = ScrollContainer.new()
	_home_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_home_cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_home_cards_scroll.custom_minimum_size = Vector2(796, 298)
	_home_cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_cards_scroll.follow_focus = true
	carousel_row.add_child(_home_cards_scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.add_theme_constant_override("margin_bottom", 12)
	scroll_margin.add_theme_constant_override("margin_left", 2)
	scroll_margin.add_theme_constant_override("margin_right", 2)
	_home_cards_scroll.add_child(scroll_margin)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 14)
	scroll_margin.add_child(cards_row)

	var btn_next_cards := _make_btn("▶", func():
		if _home_cards_scroll != null:
			_home_cards_scroll.scroll_horizontal += 382
	)
	btn_next_cards.custom_minimum_size = Vector2(30, 88)
	btn_next_cards.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_next_cards.tooltip_text = L10n.t("向右滚动地图列表", "Scroll map list right")
	carousel_row.add_child(btn_next_cards)

	_home_card_panels.clear()
	_home_card_badges.clear()
	for mkey: String in MAP_ORDER:
		var preset: Dictionary = MAP_PRESETS[mkey]
		var card := _make_panel(Color(0.08, 0.11, 0.16, 0.90))
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		card.custom_minimum_size = Vector2(368, 274)
		cards_row.add_child(card)
		_home_card_panels[mkey] = card

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 7)
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
		t_lbl.text = _map_title(mkey)
		t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_lbl.clip_text = true
		t_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t_lbl.add_theme_font_size_override("font_size", 19)
		t_lbl.add_theme_color_override("font_color", Color(0.96, 0.97, 0.99))
		head_row.add_child(t_lbl)

		var sub_lbl := Label.new()
		sub_lbl.text = _map_subtitle(mkey)
		sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_lbl.custom_minimum_size = Vector2(332, 34)
		sub_lbl.add_theme_font_size_override("font_size", 13)
		sub_lbl.add_theme_color_override("font_color", Color(0.62, 0.78, 0.94))
		cv.add_child(sub_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = _map_desc(mkey)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(332, 56)
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.80, 0.84, 0.88))
		cv.add_child(desc_lbl)

		cv.add_child(HSeparator.new())

		var badge_lbl := Label.new()
		badge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		badge_lbl.custom_minimum_size = Vector2(332, 42)
		badge_lbl.add_theme_font_size_override("font_size", 13)
		cv.add_child(badge_lbl)
		_home_card_badges[mkey] = badge_lbl

		var card_sp := Control.new()
		card_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(card_sp)

		var m_copy := mkey
		var sel_btn := _make_btn(L10n.t("选择此地图", "Select Map"), func(): _select_home_map_card(m_copy))
		cv.add_child(sel_btn)

	vbox.add_child(HSeparator.new())

	var act_bar := HBoxContainer.new()
	act_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	act_bar.add_theme_constant_override("separation", 12)
	vbox.add_child(act_bar)

	_btn_home_primary = _make_btn(L10n.t("▶ 开始建设", "▶ Start Building"), func(): _start_map_continue_or_new())
	_btn_home_primary.custom_minimum_size = Vector2(210, 38)
	_btn_home_primary.modulate = Color(0.62, 1.0, 0.80)
	act_bar.add_child(_btn_home_primary)

	_btn_home_demo = _make_btn(L10n.t("示例线网试驾", "Try Demo Network"), func(): _start_map_demo_network())
	_btn_home_demo.custom_minimum_size = Vector2(145, 38)
	act_bar.add_child(_btn_home_demo)

	_btn_home_slots = _make_btn(L10n.t("存档管理 (10槽)", "Save Slots (10)"), func(): _open_slot_modal(_selected_home_map, false))
	_btn_home_slots.custom_minimum_size = Vector2(150, 38)
	act_bar.add_child(_btn_home_slots)

	_btn_home_reset = _make_btn(L10n.t("重新开始", "Reset Map"), func(): _handle_home_reset_button())
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
	box.custom_minimum_size = Vector2(640, 540)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	_lbl_slot_title = Label.new()
	_lbl_slot_title.text = L10n.t("存档管理", "Save Manager")
	_lbl_slot_title.add_theme_font_size_override("font_size", 18)
	_lbl_slot_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_slot_title.add_theme_color_override("font_color", Color(0.52, 0.90, 0.74))
	top_row.add_child(_lbl_slot_title)

	top_row.add_child(_make_btn(L10n.t("✕ 关闭 (Esc)", "✕ Close (Esc)"), func():
		_slot_modal.visible = false
		if _in_home_menu:
			_refresh_home_screen_ui()
	))

	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tabs_row)

	_btn_tab_manual = _make_btn(L10n.t("建设规划档 (10槽 · 各含3运行档)", "Plan Slots (10 · 3 Run Saves each)"), func():
		_slot_tab_mode = 0
		_refresh_slot_modal_ui()
	)
	_btn_tab_auto = _make_btn(L10n.t("轮换自动档 (5)", "Rotating Autosaves (5)"), func():
		_slot_tab_mode = 1
		_refresh_slot_modal_ui()
	)
	tabs_row.add_child(_btn_tab_manual)
	tabs_row.add_child(_btn_tab_auto)

	_slot_name_row = HBoxContainer.new()
	_slot_name_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_slot_name_row)

	var nm_lbl := Label.new()
	nm_lbl.text = L10n.t("存档备注名称：", "Save Name:")
	_slot_name_row.add_child(nm_lbl)

	_edit_slot_name = LineEdit.new()
	_edit_slot_name.placeholder_text = L10n.t("自定义存档名（留空自动命名）", "Custom save name (blank for auto)")
	_edit_slot_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_name_row.add_child(_edit_slot_name)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(610, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED # rows fit the width: never scroll sideways
	vbox.add_child(scroll)

	_slot_list_vbox = VBoxContainer.new()
	_slot_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_slot_list_vbox)


func _save_run_progress_to_slot(plan_idx: int, sub_idx: int = 0) -> void:
	if _transit_sim.trams.is_empty():
		_show_toast(L10n.t("当前没有在线运行的电车，请先规划线路并进入运行模式！", "No active trams to save — launch a line and enter Run mode first!"))
		return
	var pidx := clampi(plan_idx, 0, SaveManager.MANUAL_SLOT_COUNT - 1)
	var sidx := clampi(sub_idx, 0, SaveManager.RUN_PER_PLAN_COUNT - 1)
	_active_plan_slot_idx = pidx
	if SaveManager.load_slot(_current_map_key, false, pidx).is_empty():
		var bp_nm := L10n.t("规划存档 %02d", "Plan Save %02d") % (pidx + 1)
		var bp_payload := _build_current_save_payload(bp_nm)
		SaveManager.save_manual_slot(_current_map_key, pidx, bp_nm, bp_payload)
		SaveManager.save_current(_current_map_key, bp_payload)
	var line_tsp := {}
	for lid: int in _graph.lines.keys():
		var ln: Dictionary = _graph.lines[lid]
		line_tsp[str(lid)] = bool(ln.get("signal_priority", false))
	var run_payload := {
		"plan_slot_idx": pidx,
		"sub_idx": sidx,
		"time_hours": snappedf(_time_hours, 0.05),
		"weather": _weather_mode,
		"pax_spawn_level": _pax_sim.spawn_level,
		"total_delivered": _pax_sim.total_delivered,
		"global_signal_priority": _graph.global_signal_priority,
		"line_signal_priority": line_tsp,
		"transit": _transit_sim.export_run_state(),
	}
	if SaveManager.save_run_slot(_current_map_key, pidx, run_payload, sidx):
		_is_demo_readonly = false
		_show_toast(L10n.t("✓ 已保存至规划 %02d · 运行档 %d（累计送达 %d 人）！", "✓ Saved to Plan %02d · Run %d (%d delivered)!") % [pidx + 1, sidx + 1, _pax_sim.total_delivered])


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
	box.custom_minimum_size = Vector2(1060, 760)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	box.add_child(vbox)

	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	var title := Label.new()
	title.text = L10n.t("线路管理 · 运营数据看板", "Line Management · Operations Board")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.48, 0.90, 0.74))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	_btn_stats_global_tsp = _make_btn(L10n.t("全局信号优先：关", "Global TSP: OFF"), func():
		_on_toggle_global_tsp()
		_refresh_stats_modal_ui()
	)
	_btn_stats_global_tsp.tooltip_text = L10n.t("开启后全城所有线路电车接近路口信号灯时自动享有信号优先", "Enables Transit Signal Priority for all lines across the city")
	top_row.add_child(_btn_stats_global_tsp)
	top_row.add_child(_make_btn(L10n.t("刷新", "Refresh"), func(): _refresh_stats_modal_ui()))
	top_row.add_child(_make_btn(L10n.t("✕ 关闭 (T/Esc)", "✕ Close (T/Esc)"), func(): _stats_modal.visible = false))

	var sum_pc := _make_panel(Color(0.10, 0.14, 0.20, 0.95))
	vbox.add_child(sum_pc)
	_stats_summary_lbl = Label.new()
	_stats_summary_lbl.add_theme_font_size_override("font_size", 13)
	_stats_summary_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	sum_pc.add_child(_stats_summary_lbl)

	var l_hdr := Label.new()
	l_hdr.text = L10n.t("各线路运营指标（支持按线路整组设置 AI 模式与信号优先）", "Line Metrics (Per-line AI Group & Signal Priority)")
	l_hdr.add_theme_font_size_override("font_size", 14)
	l_hdr.add_theme_color_override("font_color", Color(0.68, 0.86, 1.0))
	vbox.add_child(l_hdr)

	var l_scroll := ScrollContainer.new()
	l_scroll.custom_minimum_size = Vector2(1020, 130)
	vbox.add_child(l_scroll)

	_stats_lines_vbox = VBoxContainer.new()
	_stats_lines_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_lines_vbox.add_theme_constant_override("separation", 4)
	l_scroll.add_child(_stats_lines_vbox)

	vbox.add_child(HSeparator.new())

	var t_hdr := Label.new()
	t_hdr.text = L10n.t("各列车运营数据（点击一行切换到该列车）", "Active Trams (click a row to jump to that tram)")
	t_hdr.add_theme_font_size_override("font_size", 14)
	t_hdr.add_theme_color_override("font_color", Color(0.62, 0.92, 0.80))
	vbox.add_child(t_hdr)

	var t_scroll := ScrollContainer.new()
	t_scroll.custom_minimum_size = Vector2(1020, 250)
	t_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(t_scroll)

	_stats_trams_vbox = VBoxContainer.new()
	_stats_trams_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_trams_vbox.add_theme_constant_override("separation", 3)
	t_scroll.add_child(_stats_trams_vbox)

	vbox.add_child(HSeparator.new())

	var s_hdr := Label.new()
	s_hdr.text = L10n.t("各站客流统计（按当前候车人数降序）", "Station Ridership (sorted by waiting passengers)")
	s_hdr.add_theme_font_size_override("font_size", 14)
	s_hdr.add_theme_color_override("font_color", Color(0.98, 0.86, 0.56))
	vbox.add_child(s_hdr)

	var s_scroll := ScrollContainer.new()
	s_scroll.custom_minimum_size = Vector2(1020, 150)
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


func _fmt_hms(sec: float) -> String:
	var t := int(sec)
	if t >= 3600:
		return "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
	return "%d:%02d" % [t / 60, t % 60]


# One row per train: what it is doing now and what it has done since the run started
func _refresh_stats_trams() -> void:
	for c in _stats_trams_vbox.get_children():
		c.queue_free()
	var t_widths: Array[int] = [148, 0, 58, 60, 62, 62, 42, 46, 46, 66, 44, 58, 58]
	_stats_trams_vbox.add_child(_make_stat_row(
		[
			L10n.t("列车", "Tram"),
			L10n.t("当前状态", "Status"),
			L10n.t("速度", "Speed"),
			L10n.t("里程", "Dist"),
			L10n.t("运行均速", "Avg Spd"),
			L10n.t("最高速度", "Top Spd"),
			L10n.t("停站", "Stops"),
			L10n.t("上车", "Board"),
			L10n.t("下车", "Alight"),
			L10n.t("在车/定员", "Load"),
			L10n.t("满载", "Occ"),
			L10n.t("停站时间", "Dwell"),
			L10n.t("等待时间", "Wait"),
		],
		t_widths,
		Color(0.66, 0.90, 0.80),
		Color(0.09, 0.12, 0.18, 0.96)
	))
	if _transit_sim.trams.is_empty():
		_stats_trams_vbox.add_child(_make_stat_row([L10n.t("暂无运营列车", "No active trams")], [0], Color(0.62, 0.68, 0.74), Color(0.08, 0.10, 0.14, 0.85)))
		return
	var order: Array = range(_transit_sim.trams.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var la := int(_transit_sim.trams[a]["line_id"])
		var lb := int(_transit_sim.trams[b]["line_id"])
		return la < lb if la != lb else a < b
	)
	for i: int in order:
		var tr: Dictionary = _transit_sim.trams[i]
		var lid := int(tr["line_id"])
		var same := _transit_sim.line_tram_indices(lid)
		var is_active := i == _transit_sim.active_tram_idx
		var ob := (tr["pax_dests"] as Array).size()
		var cap := int(tr["capacity"])
		var dist_m := float(tr.get("st_dist_m", 0.0))
		var t_all := float(tr.get("st_move_s", 0.0)) + float(tr.get("st_stand_s", 0.0))
		var avg_kmh := dist_m / t_all * 3.6 if t_all > 1.0 else 0.0
		var ai_tag := "%s·%d" % [TransitSim.tram_ai_style_name(tr), int(tr.get("ai_max_kmh", TransitSim.tram_spec_max_kmh(tr)))]
		var ln_disp := L10n.line_display_name(str(tr["line_name"]))
		var name_txt := L10n.t("%s%s 第%d列 (%s)", "%s%s #%d (%s)") % ["▶ " if is_active else "", ln_disp, same.find(i) + 1, ai_tag]
		if is_active and _transit_sim.manual_drive:
			name_txt += L10n.t("·手动", "·Man")
		var l_col: Color = tr.get("line_color", Color(0.85, 0.92, 1.0))
		var row := _make_stat_row(
			[
				name_txt,
				_transit_sim.tram_status_text(tr),
				"%.0f km/h" % (float(tr["speed_mps"]) * 3.6),
				"%.2f km" % (dist_m / 1000.0),
				"%.1f km/h" % avg_kmh,
				"%.0f km/h" % float(tr.get("st_max_kmh", 0.0)),
				"%d" % int(tr.get("st_stops", 0)),
				"%d" % int(tr.get("st_boarded", 0)),
				"%d" % int(tr.get("st_alighted", 0)),
				"%d/%d" % [ob, cap],
				"%.0f%%" % (float(ob) / float(maxi(1, cap)) * 100.0),
				_fmt_hms(float(tr.get("st_dwell_s", 0.0))),
				_fmt_hms(float(tr.get("st_hold_s", 0.0))),
			],
			t_widths,
			l_col.lerp(Color.WHITE, 0.55),
			Color(0.16, 0.24, 0.22, 0.95) if is_active else Color(0.10, 0.13, 0.19, 0.90)
		)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		(row.get_child(0) as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = L10n.t(
			"峰值载客 %d 人 · 行驶 %s · 停车 %s（其中开门上下客 %s，待避/让行 %s）",
			"Peak load %d · Moving %s · Stopped %s (Boarding %s, Yielding %s)"
		) % [
			int(tr.get("st_peak_load", 0)), _fmt_hms(float(tr.get("st_move_s", 0.0))), _fmt_hms(float(tr.get("st_stand_s", 0.0))),
			_fmt_hms(float(tr.get("st_dwell_s", 0.0))), _fmt_hms(float(tr.get("st_hold_s", 0.0)))]
		row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_transit_sim.select_tram(i)
				_show_toast(L10n.t("已切换到 %s 第%d列", "Switched to %s #%d") % [ln_disp, same.find(i) + 1])
				_refresh_stats_modal_ui()
		)
		_stats_trams_vbox.add_child(row)


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
	_stats_summary_lbl.text = L10n.t(
		"运营时长 %02d:%02d  ·  在线线路 %d 条  ·  在线电车 %d 辆  ·  在车 %d 人  ·  候车 %d 人  ·  累计上车 %d 人  ·  缓急换乘 %d 人  ·  累计送达 %d 人",
		"Uptime %02d:%02d  ·  Lines %d  ·  Trams %d  ·  Onboard %d  ·  Waiting %d  ·  Boarded %d  ·  Transfers %d  ·  Delivered %d"
	) % [
		op_min,
		op_rem,
		_graph.lines.size(),
		_transit_sim.trams.size(),
		total_onboard,
		total_waiting,
		_pax_sim.total_boarded,
		_pax_sim.total_transfers,
		_pax_sim.total_delivered,
	]

	for c in _stats_lines_vbox.get_children():
		c.queue_free()
	for c in _stats_stations_vbox.get_children():
		c.queue_free()
	_refresh_stats_trams()

	if _btn_stats_global_tsp != null:
		_btn_stats_global_tsp.text = L10n.t("全局信号优先：开", "Global TSP: ON") if _graph.global_signal_priority else L10n.t("全局信号优先：关", "Global TSP: OFF")
		_highlight_active_btn(_btn_stats_global_tsp, _graph.global_signal_priority)

	var l_widths: Array[int] = [88, 138, 46, 52, 68, 52, 52, 50, 52, 168, 98]
	_stats_lines_vbox.add_child(_make_stat_row(
		[
			L10n.t("线路", "Line"),
			L10n.t("车型 / 编组", "Model / Cars"),
			L10n.t("配车", "Fleet"),
			L10n.t("总定员", "Cap"),
			L10n.t("运营均速", "Avg Spd"),
			L10n.t("累计上车", "Boarded"),
			L10n.t("累计送达", "Deliv."),
			L10n.t("当前在车", "Onbrd"),
			L10n.t("满载率", "Load"),
			L10n.t("整组AI模式", "Line AI"),
			L10n.t("信号优先", "TSP"),
		],
		l_widths,
		Color(0.68, 0.80, 0.92),
		Color(0.09, 0.12, 0.18, 0.96)
	))

	if _graph.lines.is_empty():
		_stats_lines_vbox.add_child(_make_stat_row(
			[L10n.t("暂无线路数据，请先在【规划线路】模式中创建至少一条电车线路。", "No lines yet. Create at least one line in [Plan Lines] mode.")],
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
			var sec_cnt := clampi(int(ln.get("sections", 2)), 1, 4)
			for tr_var in _transit_sim.trams:
				var tr: Dictionary = tr_var
				if int(tr.get("line_id", -1)) == lid:
					tr_cnt += 1
					cap_sum += int(tr.get("capacity", 0))
					ob_sum += (tr.get("pax_dests", []) as Array).size()
					var sp: Dictionary = tr.get("spec", {})
					if not sp.is_empty():
						model_label = L10n.model_name(sp)
			var dist_km := float(_transit_sim.line_dist_m.get(lid, 0.0)) / 1000.0
			var avg_kmh := (dist_km / maxf(float(maxi(1, tr_cnt)) * op_hrs, 0.0001)) if _transit_sim.operating_seconds > 1.0 else 0.0
			var boarded := int(_pax_sim.line_boarded.get(lid, 0))
			var delivered := int(_pax_sim.line_delivered.get(lid, 0))
			var load_pct := (float(ob_sum) / float(maxi(1, cap_sum)) * 100.0) if cap_sum > 0 else 0.0
			var l_col: Color = ln.get("color", Color(0.85, 0.92, 1.0))
			var row_pc := _make_stat_row(
				[
					L10n.line_display_name(str(ln.get("name", L10n.t("线路 %d", "Line %d") % lid))),
					L10n.t("%s · %d节", "%s · %dc") % [model_label, sec_cnt],
					L10n.t("%d 辆", "%d") % tr_cnt,
					L10n.t("%d 人", "%d") % cap_sum,
					"%.1f km/h" % avg_kmh,
					"%d" % boarded,
					"%d" % delivered,
					"%d" % ob_sum,
					"%.0f%%" % load_pct,
				],
				l_widths.slice(0, 9),
				l_col.lerp(Color.WHITE, 0.55),
				Color(0.10, 0.13, 0.19, 0.90)
			)
			var row_hb := row_pc.get_child(0) as HBoxContainer
			var ai_grp_box := HBoxContainer.new()
			ai_grp_box.custom_minimum_size = Vector2(168, 0)
			ai_grp_box.add_theme_constant_override("separation", 3)
			var cur_line_style := _transit_sim.get_line_ai_style(lid)
			var lid_ai := lid
			var line_ai_opts := [
				[TransitSim.LINE_AI_NONE, L10n.t("无默认", "None"), 52],
				[TransitSim.AIStyle.SLOW, L10n.t("慢", "S"), 32],
				[TransitSim.AIStyle.NORMAL, L10n.t("常", "N"), 32],
				[TransitSim.AIStyle.FURIOUS, L10n.t("狂", "F"), 32],
			]
			for sp_pair in line_ai_opts:
				var st_v: int = sp_pair[0]
				var ab := _make_btn(str(sp_pair[1]), func():
					_on_set_line_ai_style(lid_ai, st_v)
					_refresh_stats_modal_ui()
				)
				ab.custom_minimum_size = Vector2(int(sp_pair[2]), 0)
				if st_v == TransitSim.LINE_AI_NONE:
					ab.tooltip_text = L10n.t("取消本线整组默认 AI 模式（各车保留当前独立设置）", "Clear line-level default AI mode (trams keep individual modes)")
				else:
					ab.tooltip_text = L10n.t("整条线路设为【%s】模式", "Set entire line to [%s] mode") % TransitSim.ai_style_name(st_v)
				_highlight_active_btn(ab, cur_line_style == st_v)
				ai_grp_box.add_child(ab)
			row_hb.add_child(ai_grp_box)

			var lid_tsp := lid
			var line_tsp_on := bool(ln.get("signal_priority", false))
			var eff_tsp_on := _graph.is_line_signal_priority(lid)
			var tsp_btn := _make_btn(
				L10n.t("⚡ 全局优", "⚡ Global") if (_graph.global_signal_priority and not line_tsp_on) else (L10n.t("⚡ 优先：开", "⚡ TSP: ON") if line_tsp_on else L10n.t("优先：关", "TSP: OFF")),
				func():
					_on_toggle_line_tsp(lid_tsp)
					_refresh_stats_modal_ui()
			)
			tsp_btn.custom_minimum_size = Vector2(96, 0)
			_highlight_active_btn(tsp_btn, eff_tsp_on)
			row_hb.add_child(tsp_btn)
			_stats_lines_vbox.add_child(row_pc)

	var s_widths: Array[int] = [0, 82, 82, 82, 118, 118, 76]
	_stats_stations_vbox.add_child(_make_stat_row(
		[
			L10n.t("车站名称", "Station"),
			L10n.t("当前候车", "Waiting"),
			L10n.t("累计上车", "Boarded"),
			L10n.t("累计下车", "Alighted"),
			L10n.t("平均等待(已上车)", "Avg Wait (Brd)"),
			L10n.t("当前候车已等", "Cur Wait"),
			L10n.t("站台状态", "Crowd"),
		],
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
			"name": L10n.station_display_name(str(st.get("name", L10n.t("车站 %d", "Station %d") % sid))),
			"waiting": waiting,
			"boarded": st_b,
			"alighted": st_a,
			"avg_wait": _pax_sim.get_avg_wait_boarded(sid),
			"cur_wait": _pax_sim.get_avg_wait_current(sid),
		})
	st_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["waiting"]) != int(b["waiting"]):
			return int(a["waiting"]) > int(b["waiting"])
		return int(a["boarded"]) > int(b["boarded"])
	)
	if st_rows.is_empty():
		_stats_stations_vbox.add_child(_make_stat_row(
			[L10n.t("暂无车站数据", "No stations yet")],
			[0],
			Color(0.62, 0.68, 0.74),
			Color(0.08, 0.10, 0.14, 0.85)
		))
	else:
		for sr: Dictionary in st_rows:
			var w := int(sr["waiting"])
			var status_txt := L10n.t("宽松", "Light")
			var st_col := Color(0.86, 0.94, 0.90)
			if w >= 60:
				status_txt = L10n.t("拥挤", "Crowded")
				st_col = Color(1.0, 0.56, 0.48)
			elif w >= 25:
				status_txt = L10n.t("较忙", "Busy")
				st_col = Color(0.98, 0.84, 0.46)
			_stats_stations_vbox.add_child(_make_stat_row(
				[str(sr["name"]), L10n.t("%d 人", "%d") % w, L10n.t("%d 人", "%d") % int(sr["boarded"]), L10n.t("%d 人", "%d") % int(sr["alighted"]),
					"—" if float(sr["avg_wait"]) < 0.0 else _fmt_hms(float(sr["avg_wait"])),
					"—" if float(sr["cur_wait"]) < 0.0 else _fmt_hms(float(sr["cur_wait"])), status_txt],
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
	var st_name := L10n.station_display_name(str(st_info.get("name", "")))
	var term_stage := str(tr.get("term_stage", ""))
	if term_stage == "flip_wait":
		tr.erase("xfer_snap")
		return L10n.t("🔄 已停靠：%s · 终点清客完毕，正在换端折返…", "🔄 Docked: %s · Terminus cleared, changing cab…") % st_name
	var onboard: Array = tr["pax_dests"]
	var cap := int(tr["capacity"])
	var alight_left := onboard.size() if term_stage == "alight_only" else (0 if term_stage == "board_only" else onboard.count(sid))
	var pending := int(tr.get("pending_boarders", 0))
	var is_unsched := bool(st_info.get("unscheduled", false))
	var waiting: int
	if is_unsched:
		var up_u := _transit_sim.get_upcoming_station_ids(tr, -1, sid)
		waiting = _pax_sim.get_boardable_count_for_tram(sid, tr, up_u)
	else:
		waiting = _pax_sim.get_boardable_count(sid) # on the platform now (not still walking up from the street)
	var room := maxi(0, cap - onboard.size() - pending)
	var board_left := 0 if term_stage == "alight_only" else mini(waiting, room)
	var doors_open := bool(tr.get("doors_target_open", false)) and float(tr.get("door_ratio", 0.0)) > 0.5
	var open_delay := float(tr.get("ai_open_delay", 0.0))
	if not doors_open:
		if float(tr.get("door_ratio", 0.0)) < 0.02:
			tr.erase("xfer_snap")
		var phase_tag := L10n.t("（终点清客）", " (Terminus Alight)") if term_stage == "alight_only" else (L10n.t("（始发上客）", " (Origin Boarding)") if term_stage == "board_only" else "")
		if open_delay > 0.0:
			return L10n.t("● 已停靠：%s%s · 缓慢模式停稳确认中（%.1fs 后开门）…", "● Docked: %s%s · Slow mode safety pause (opening in %.1fs)…") % [st_name, phase_tag, open_delay]
		if bool(tr.get("doors_target_open", false)):
			return L10n.t("● 已停靠：%s%s · 车门正在打开…", "● Docked: %s%s · Doors opening…") % [st_name, phase_tag]
		return L10n.t("● 已停靠：%s%s · 车门正在关闭…", "● Docked: %s%s · Doors closing…") % [st_name, phase_tag]
	var remaining := alight_left + board_left + pending
	var approaching_n := _pax_sim.get_approaching_count(sid) if (int(tr.get("ai_style", 1)) == TransitSim.AIStyle.SLOW and term_stage != "alight_only" and room > 0) else 0
	var close_grace := float(tr.get("ai_close_grace", 0.0))
	var snap: Dictionary = tr.get("xfer_snap", {})
	if snap.is_empty() or int(snap.get("sid", -1)) != sid or str(snap.get("stage", "")) != term_stage:
		snap = {"sid": sid, "stage": term_stage, "total": maxi(1, remaining), "done_toast": false}
		tr["xfer_snap"] = snap
	snap["total"] = maxi(int(snap["total"]), remaining)
	var prog := 1.0 - float(remaining) / float(maxi(1, int(snap["total"])))
	var cells := 10
	var filled := int(round(prog * float(cells)))
	var bar := "▰".repeat(filled) + "▱".repeat(cells - filled)
	if remaining == 0:
		snap["done"] = true
	if bool(snap.get("done", false)) and term_stage != "alight_only" and alight_left == 0:
		if not _transit_sim.manual_drive and bool(tr.get("express_waiting", false)):
			var done_tag_e := L10n.t("始发上客完毕", "Boarding done") if term_stage == "board_only" else L10n.t("上下客完毕", "Boarding done")
			return L10n.t("⏳ %s %s · 正在开门待避快车（等快车离站后关门发车）…", "⏳ %s %s · Holding doors open for Express…") % [st_name, done_tag_e]
		if not _transit_sim.manual_drive and bool(tr.get("pacing_waiting", false)):
			var done_tag_p := L10n.t("始发上客完毕", "Boarding done") if term_stage == "board_only" else L10n.t("上下客完毕", "Boarding done")
			return L10n.t("⏱ %s %s · 前方同线列车较近，正在站台开门调距（%.0fm / 均距 %.0fm）…", "⏱ %s %s · Holding doors open for headway pacing (%.0fm / avg %.0fm)…") % [
				st_name, done_tag_p,
				float(tr.get("pacing_ahead_m", 0.0)),
				float(tr.get("pacing_avg_m", 0.0)),
			]
		if not _transit_sim.manual_drive and int(tr.get("ai_style", 1)) == TransitSim.AIStyle.SLOW:
			var done_tag_s := L10n.t("始发上客完毕", "Boarding done") if term_stage == "board_only" else L10n.t("上下客完毕", "Boarding done")
			if remaining == 0 and approaching_n > 0:
				return L10n.t("⏳ %s %s %s 100%% · 缓慢模式正在等待 %d 名赶来的乘客上车…", "⏳ %s %s %s 100%% · Slow mode waiting for %d approaching rider(s)…") % [st_name, done_tag_s, "▰".repeat(cells), approaching_n]
			if remaining == 0 and close_grace > 0.05:
				return L10n.t("✅ %s %s %s 100%% · 缓慢模式候客确认中（%.1fs 后关门）…", "✅ %s %s %s 100%% · Slow mode closing in %.1fs…") % [st_name, done_tag_s, "▰".repeat(cells), close_grace]
		# Everyone who was on the platform is aboard; late arrivals still walking in don't hold the train
		var late_note := (L10n.t(" · 另有 %d 人正赶来上车", " · +%d approaching") % (board_left + pending)) if remaining > 0 else ""
		if _transit_sim.manual_drive and not bool(snap["done_toast"]):
			snap["done_toast"] = true
			_show_toast(L10n.t("✅ %s %s完毕，可以关门 (O) 出发", "✅ %s %s complete — press O to close doors & depart") % [st_name, L10n.t("始发上客", "boarding") if term_stage == "board_only" else L10n.t("上下客", "boarding")])
		var full_note := (L10n.t("（车厢已满，站台还有 %d 人等下一班）", " (Full, %d left waiting)") % waiting) if waiting > 0 and room == 0 else ""
		var done_tag := L10n.t("始发上客完毕", "Boarding done") if term_stage == "board_only" else L10n.t("上下客完毕", "Boarding done")
		return L10n.t("✅ %s %s %s 100%%，可关门 (O) 出发%s%s", "✅ %s %s %s 100%% — Close doors (O)%s%s") % [st_name, done_tag, "▰".repeat(cells), full_note, late_note]
	if remaining == 0:
		if term_stage == "alight_only":
			if _transit_sim.manual_drive and not bool(snap["done_toast"]):
				snap["done_toast"] = true
				_show_toast(L10n.t("✅ %s 终点清客完毕，请关门 (O) 后按 R 换端", "✅ %s terminus cleared — close doors (O), then press R to change cab") % st_name)
			return L10n.t("✅ %s 终点清客完毕 %s 100%% · 请关门后换端", "✅ %s Terminus cleared %s 100%% · Close doors & change cab") % [st_name, bar]
		if _transit_sim.manual_drive and not bool(snap["done_toast"]):
			snap["done_toast"] = true
			_show_toast(L10n.t("✅ %s %s完毕，可以关门 (O) 出发", "✅ %s %s complete — press O to close doors & depart") % [st_name, L10n.t("始发上客", "boarding") if term_stage == "board_only" else L10n.t("上下客", "boarding")])
		var full_note := (L10n.t("（车厢已满，站台还有 %d 人等下一班）", " (Full, %d left waiting)") % waiting) if waiting > 0 and room == 0 else ""
		var done_tag := L10n.t("始发上客完毕", "Boarding done") if term_stage == "board_only" else L10n.t("上下客完毕", "Boarding done")
		return L10n.t("✅ %s %s %s 100%%，可关门 (O) 出发%s", "✅ %s %s %s 100%% — Close doors (O)%s") % [st_name, done_tag, bar, full_note]
	var open_n := int(tr.get("open_doorways", 0))
	var tot_n := maxi(1, int(tr.get("total_doorways", 1)))
	var door_note := "" if open_n >= tot_n else (L10n.t(" · ⚠ 停靠错位，仅 %d/%d 个车门对准站台，上下客较慢", " · ⚠ Misaligned: only %d/%d doors open (slower)") % [open_n, tot_n])
	if term_stage == "alight_only":
		return L10n.t("⏳ %s 终点清客中（只下不上）%s %d%% · 下车剩 %d%s", "⏳ %s Terminus alighting %s %d%% · %d left%s") % [
			st_name, bar, int(round(prog * 100.0)), alight_left, door_note]
	if term_stage == "board_only":
		return L10n.t("⏳ %s 始发上客中（只上车）%s %d%% · 上车剩 %d（站台 %d，正在上车 %d）%s", "⏳ %s Boarding %s %d%% · %d left (plat %d, moving %d)%s") % [
			st_name, bar, int(round(prog * 100.0)), board_left, waiting, pending, door_note]
	return L10n.t("⏳ %s 上下客中 %s %d%% · 下车剩 %d · 上车剩 %d（站台 %d，正在上车 %d）%s", "⏳ %s Exchange %s %d%% · Alight %d · Board %d (plat %d, moving %d)%s") % [
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
		var dock := _transit_sim.get_dock_info_for_tram(tr, _graph, _transit_sim.manual_drive)
		var ann_name := st_name
		var is_unsched_ann := bool(dock.get("unscheduled", false))
		var dock_sid := int(dock.get("station_id", -1))
		if is_unsched_ann and dock_sid >= 0 and _graph.stations.has(dock_sid):
			ann_name = str((_graph.stations[dock_sid] as Dictionary).get("name", st_name))
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
		var prefix_zh := "临时停靠，" if is_unsched_ann else ""
		var prefix_en := "Unscheduled stop, " if is_unsched_ann else ""
		var disp_ann := L10n.station_display_name(ann_name)
		_sound.announce_station("%s%s 到了，请从%s车门下车。" % [prefix_zh, ann_name, side_zh], "%sArriving at %s. Doors open on the %s." % [prefix_en, disp_ann, side_en])
		_show_toast(L10n.t("📢 报站：%s%s 到了，请从%s车门下车", "📢 Announcement: %sArriving at %s (doors on %s)") % [prefix_zh if not L10n.is_en() else prefix_en, disp_ann, side_zh if not L10n.is_en() else side_en])
	elif (not bool(tr.get("doors_target_open", false))) and _last_ann_door_open:
		_last_ann_door_open = false
		_sound.announce_station("车门即将关闭，请站稳扶好。", "Doors closing. Please hold on.")
	elif dist <= 48.0 and dist > 7.5 and sid != _last_ann_approach_sid and float(tr.get("speed_mps", 0.0)) > 1.2:
		_last_ann_approach_sid = sid
		var disp_next := L10n.station_display_name(st_name)
		_sound.announce_station("下一站，%s，请准备下车。" % st_name, "Next stop, %s." % disp_next)
		_show_toast(L10n.t("📢 报站：下一站，%s", "📢 Next stop: %s") % disp_next)


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
	card.custom_minimum_size = Vector2(500, 468)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = L10n.t("游戏、语言与音频设置", "Game, Language & Audio Settings")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.50, 0.90, 0.98))
	header.add_child(title)
	header.add_child(_make_btn(L10n.t("关闭", "Close"), func(): _audio_modal.visible = false))

	# UI Language Setting (Auto / Chinese / English)
	var ui_lang_row := HBoxContainer.new()
	ui_lang_row.add_theme_constant_override("separation", 8)
	vbox.add_child(ui_lang_row)
	var ui_lang_lbl := Label.new()
	ui_lang_lbl.text = L10n.t("界面语言：", "Language:")
	ui_lang_lbl.custom_minimum_size = Vector2(124, 24)
	ui_lang_row.add_child(ui_lang_lbl)
	var sys_tag := "中文" if L10n.detect_system_lang() == "zh" else "EN"
	for lp in [
		["auto", L10n.t("跟随系统 (%s)", "System (%s)") % sys_tag],
		["zh", "中文"],
		["en", "English"],
	]:
		var pref_c: String = lp[0]
		var lb := _make_btn(str(lp[1]), func(): _on_set_language(pref_c))
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_highlight_active_btn(lb, L10n.lang_pref == pref_c)
		ui_lang_row.add_child(lb)

	# Weather Setting (Sunny / Cloudy / Rainy)
	var wx_row := HBoxContainer.new()
	wx_row.add_theme_constant_override("separation", 8)
	vbox.add_child(wx_row)
	var wx_lbl := Label.new()
	wx_lbl.text = L10n.t("当前天气：", "Weather:")
	wx_lbl.custom_minimum_size = Vector2(124, 24)
	wx_row.add_child(wx_lbl)
	_settings_weather_btns.clear()
	for wm in [WeatherSystem.WeatherType.SUNNY, WeatherSystem.WeatherType.CLOUDY, WeatherSystem.WeatherType.RAINY]:
		var wm_v: int = wm
		var wb := _make_btn(WeatherSystem.weather_button_label(wm_v), func(): _set_weather_mode(wm_v, true))
		wb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_highlight_active_btn(wb, _weather_mode == wm_v)
		wx_row.add_child(wb)
		_settings_weather_btns.append(wb)

	vbox.add_child(HSeparator.new())

	var cur_m_pct := int(round((_sound.master_volume if _sound != null else 0.85) * 100.0))
	var cur_s_pct := int(round((_sound.sfx_volume if _sound != null else 0.85) * 100.0))
	var cur_t_pct := int(round((_sound.tts_volume if _sound != null else 0.85) * 100.0))

	# Master Volume
	var m_row := HBoxContainer.new()
	m_row.add_theme_constant_override("separation", 10)
	vbox.add_child(m_row)
	var m_lbl := Label.new()
	m_lbl.text = L10n.t("总音量：%d%%", "Master Vol: %d%%") % cur_m_pct
	m_lbl.custom_minimum_size = Vector2(132, 24)
	m_row.add_child(m_lbl)
	var m_slider := HSlider.new()
	m_slider.min_value = 0.0; m_slider.max_value = 100.0; m_slider.step = 1.0; m_slider.value = float(cur_m_pct)
	m_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_slider.value_changed.connect(func(v: float):
		_sound.master_volume = v / 100.0
		m_lbl.text = L10n.t("总音量：%d%%", "Master Vol: %d%%") % int(round(v))
	)
	m_row.add_child(m_slider)

	# Tram SFX Volume
	var s_row := HBoxContainer.new()
	s_row.add_theme_constant_override("separation", 10)
	vbox.add_child(s_row)
	var s_lbl := Label.new()
	s_lbl.text = L10n.t("电车音效：%d%%", "Tram SFX: %d%%") % cur_s_pct
	s_lbl.custom_minimum_size = Vector2(132, 24)
	s_row.add_child(s_lbl)
	var s_slider := HSlider.new()
	s_slider.min_value = 0.0; s_slider.max_value = 100.0; s_slider.step = 1.0; s_slider.value = float(cur_s_pct)
	s_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_slider.value_changed.connect(func(v: float):
		_sound.sfx_volume = v / 100.0
		s_lbl.text = L10n.t("电车音效：%d%%", "Tram SFX: %d%%") % int(round(v))
	)
	s_row.add_child(s_slider)

	# Station Announcement (TTS) Volume
	var t_row := HBoxContainer.new()
	t_row.add_theme_constant_override("separation", 10)
	vbox.add_child(t_row)
	var t_lbl := Label.new()
	t_lbl.text = L10n.t("报站音量：%d%%", "TTS Vol: %d%%") % cur_t_pct
	t_lbl.custom_minimum_size = Vector2(132, 24)
	t_row.add_child(t_lbl)
	var t_slider := HSlider.new()
	t_slider.min_value = 0.0; t_slider.max_value = 100.0; t_slider.step = 1.0; t_slider.value = float(cur_t_pct)
	t_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_slider.value_changed.connect(func(v: float):
		_sound.tts_volume = v / 100.0
		t_lbl.text = L10n.t("报站音量：%d%%", "TTS Vol: %d%%") % int(round(v))
	)
	t_row.add_child(t_slider)

	var toggle_row := HBoxContainer.new()
	toggle_row.add_theme_constant_override("separation", 8)
	vbox.add_child(toggle_row)
	var sfx_on := _sound.sfx_enabled if _sound != null else true
	var btn_sfx_t := _make_btn(L10n.t("电车音效：已开启", "Tram SFX: ON") if sfx_on else L10n.t("电车音效：已关闭", "Tram SFX: OFF"), func(): pass)
	btn_sfx_t.pressed.connect(func():
		_sound.sfx_enabled = not _sound.sfx_enabled
		btn_sfx_t.text = L10n.t("电车音效：已开启", "Tram SFX: ON") if _sound.sfx_enabled else L10n.t("电车音效：已关闭", "Tram SFX: OFF")
	)
	btn_sfx_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_row.add_child(btn_sfx_t)

	var tts_on := _sound.tts_enabled if _sound != null else true
	var btn_tts_t := _make_btn(L10n.t("自动报站：已开启", "Station TTS: ON") if tts_on else L10n.t("自动报站：已关闭", "Station TTS: OFF"), func(): pass)
	btn_tts_t.pressed.connect(func():
		_sound.tts_enabled = not _sound.tts_enabled
		if not _sound.tts_enabled and DisplayServer.get_name() != "headless":
			DisplayServer.tts_stop()
		btn_tts_t.text = L10n.t("自动报站：已开启", "Station TTS: ON") if _sound.tts_enabled else L10n.t("自动报站：已关闭", "Station TTS: OFF")
	)
	btn_tts_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_row.add_child(btn_tts_t)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	vbox.add_child(lang_row)
	var lang_names := [L10n.t("中英双语", "Bilingual"), L10n.t("仅中文", "Chinese Only"), L10n.t("仅英语", "English Only")]
	var cur_tts_mode := clampi(_sound.tts_lang_mode if _sound != null else 0, 0, 2)
	var btn_biling := _make_btn(L10n.t("报站语言：%s", "TTS Language: %s") % lang_names[cur_tts_mode], func(): pass)
	btn_biling.pressed.connect(func():
		_sound.tts_lang_mode = (_sound.tts_lang_mode + 1) % 3
		btn_biling.text = L10n.t("报站语言：%s", "TTS Language: %s") % lang_names[_sound.tts_lang_mode]
	)
	btn_biling.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_row.add_child(btn_biling)
	lang_row.add_child(_make_btn(L10n.t("试听报站", "Test TTS"), func():
		var was_sil := _sound._menu_silenced
		_sound._menu_silenced = false
		_sound.announce_station("下一站，西湖中心站，请准备下车。", "Next stop, Westlake Center.")
		_sound._menu_silenced = was_sil
	))

	var note_lbl := Label.new()
	note_lbl.text = L10n.t(
		"提示：退出地图返回主页或在建设/规划模式下，电车音效与语音报站将自动静音停止。",
		"Note: Tram SFX and station announcements automatically mute on the Home screen or in Build/Plan modes."
	)
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.add_theme_font_size_override("font_size", 12)
	note_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
	vbox.add_child(note_lbl)


func _on_set_language(pref: String) -> void:
	L10n.set_language(pref)
	var was_home := _in_home_menu
	var was_audio := _audio_modal != null and _audio_modal.visible
	var was_slot := _slot_modal != null and _slot_modal.visible
	var was_stats := _stats_modal != null and _stats_modal.visible
	var was_over := _gameover_modal != null and _gameover_modal.visible
	var prev_mode := _game_mode

	if _ui_canvas != null and is_instance_valid(_ui_canvas):
		remove_child(_ui_canvas)
		_ui_canvas.queue_free()
		_ui_canvas = null

	_build_ui()

	_home_overlay.visible = was_home
	_hud_layer_ctrl.visible = not was_home
	_nav_bar.visible = not was_home
	_audio_modal.visible = was_audio
	_slot_modal.visible = was_slot
	_stats_modal.visible = was_stats
	_gameover_modal.visible = was_over
	_lbl_paused.visible = (not was_home) and (prev_mode == GameMode.RUN) and _run_paused

	_build_panel.visible = (prev_mode == GameMode.BUILD)
	_plan_panel.visible = (prev_mode == GameMode.PLAN)
	_run_top_panel.visible = (prev_mode == GameMode.RUN)
	_cam_panel.visible = (prev_mode == GameMode.RUN)
	_drv_panel.visible = (prev_mode == GameMode.RUN)
	_btn_quick_save_run.visible = (prev_mode == GameMode.RUN) and not _is_demo_readonly
	_highlight_active_btn(_btn_mode_build, prev_mode == GameMode.BUILD)
	_highlight_active_btn(_btn_mode_plan, prev_mode == GameMode.PLAN)
	_highlight_active_btn(_btn_mode_run, prev_mode == GameMode.RUN)

	_refresh_build_buttons()
	_refresh_plan_ui()
	_set_time_hours(_time_hours)
	_refresh_weather_buttons()
	if was_home:
		_refresh_home_screen_ui()
	if was_slot:
		_refresh_slot_modal_ui()
	if was_stats:
		_refresh_stats_modal_ui()
	if prev_mode == GameMode.RUN and not was_home:
		_update_run_hud()
	if _graph != null and not _graph.stations.is_empty():
		var was_ops_dirty := _ops_dirty
		_rebuild_tracks_only_visual()
		_ops_dirty = was_ops_dirty
	elif _pax_sim != null:
		_pax_sim.refresh_all_station_labels()
	var lang_label := L10n.t("中文", "English")
	var auto_note := L10n.t("（跟随系统）", " (System)") if L10n.lang_pref == "auto" else ""
	_show_toast(L10n.t("✓ 界面语言已切换为：%s%s", "✓ Language set to: %s%s") % [lang_label, auto_note])


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
	_lbl_gameover_title.text = L10n.t("【重大安全事故 · 本局游戏结束】", "[Major Safety Incident · Run Ended]")
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
	rule_lbl.text = L10n.t("本局运营已中止，但您建设的轨道、车站、线路及所有存档均完整保留，可立即重新发车。", "This run has ended, but all tracks, stations, lines, and saves are intact. You can restart immediately.")
	rule_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule_lbl.add_theme_color_override("font_color", Color(0.96, 0.72, 0.42))
	vbox.add_child(rule_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var restart_btn := _make_btn(L10n.t("▸ 重新开始该地图 (Enter / R)", "▸ Restart Map (Enter / R)"), func(): _restart_current_map_after_crash())
	restart_btn.custom_minimum_size = Vector2(240, 38)
	restart_btn.modulate = Color(1.0, 0.72, 0.62)
	btn_row.add_child(restart_btn)

	var home_btn := _make_btn(L10n.t("◀ 返回主页选图", "◀ Home Screen"), func(): _enter_home_screen())
	home_btn.custom_minimum_size = Vector2(150, 38)
	btn_row.add_child(home_btn)


func _toggle_doors_with_safety_check() -> void:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	if float(tr["speed_mps"]) > 0.30:
		_show_toast(L10n.t("⚠ 行驶中车门安全互锁，请先停车后再开门！", "⚠ Doors interlocked while moving — come to a complete stop first!"))
		return
	var was_open := bool(tr["doors_target_open"])
	var ok := _transit_sim.manual_toggle_doors(_sound, _graph)
	if not was_open and not ok:
		_show_toast(L10n.t("⚠ 没有车门对准站台，车门已安全锁闭！请对准停车位置后再开门", "⚠ No doorways aligned with platform — doors stay locked. Align with the platform first!"))
	elif not was_open and ok:
		var al := int(tr.get("aligned_doorways", 0))
		var tot := int(tr.get("total_doorways", 1))
		if al < tot:
			_show_toast(L10n.t("⚠ 停靠错位：仅 %d/%d 个车门对准站台，只开对准的车门，上下客会变慢", "⚠ Misaligned stop: only %d/%d doorways aligned — boarding will be slower") % [al, tot])


func _apply_station_rename() -> void:
	if _edit_station_name == null:
		return
	var new_n := _edit_station_name.text.strip_edges()
	if new_n.is_empty():
		_show_toast(L10n.t("站名不能为空", "Station name cannot be empty"))
		return
	if _editing_station_id < 0 or not _graph.stations.has(_editing_station_id):
		_show_toast(L10n.t("请先用「建造车站」工具点击要改名的已有车站！", "Click an existing station with [Build Station] first to rename it!"))
		return
	if _graph.rename_station(_editing_station_id, new_n):
		_edit_station_name.release_focus()
		_rebuild_tracks_only_visual()
		_mark_modified_and_quick_save()
		_show_toast(L10n.t("站名已修改为：%s", "Station renamed to: %s") % new_n)


func _refresh_build_buttons() -> void:
	var active_cat := 0
	if _build_tool == BuildTool.CROSSOVER:
		active_cat = 1
	elif _build_tool == BuildTool.STATION:
		active_cat = 2
	elif _build_tool == BuildTool.DEMOLISH:
		active_cat = 3
	elif _build_tool >= BuildTool.ROAD_BUILD:
		active_cat = 4

	var cat_titles := [
		L10n.t("修建轨道", "Build Track"),
		L10n.t("修建渡线", "Build Crossover"),
		L10n.t("修建车站", "Build Station"),
		L10n.t("拆除车站 / 轨道", "Demolish Station / Track"),
		L10n.t("道路与地块", "Roads & Lots"),
	]

	for ci in range(_build_cat_btns.size()):
		var is_open := (ci == active_cat)
		var btn := _build_cat_btns[ci]
		btn.text = ("%s  %s" % ["▾" if is_open else "▸", cat_titles[ci]])
		_highlight_active_btn(btn, is_open)
		if ci < _build_cat_subpanels.size():
			_build_cat_subpanels[ci].visible = is_open

	var lay_tools: Array[int] = [BuildTool.TRACK_SINGLE, BuildTool.TRACK_PATH, BuildTool.TRACK_OFFROAD]
	for i in range(_track_lay_btns.size()):
		_highlight_active_btn(_track_lay_btns[i], _build_tool == lay_tools[i])
	var road_tools: Array[int] = [BuildTool.ROAD_BUILD, BuildTool.ROAD_REMOVE, BuildTool.ROAD_LANES, BuildTool.BUILDING_DEMOLISH]
	for i in range(_road_tool_btns.size()):
		_highlight_active_btn(_road_tool_btns[i], _build_tool == road_tools[i])
	for i in range(_lane_cfg_btns.size()):
		_highlight_active_btn(_lane_cfg_btns[i], i == _road_lane_idx)
	for i in range(_track_mode_btns.size()):
		_highlight_active_btn(_track_mode_btns[i], i == _build_track_mode)
	var xo_idx := 0 if _build_crossover_type == NetworkGraph.CrossoverType.SINGLE else 1
	for i in range(_crossover_type_btns.size()):
		_highlight_active_btn(_crossover_type_btns[i], i == xo_idx)
	for i in range(_station_kind_btns.size()):
		_highlight_active_btn(_station_kind_btns[i], i == _build_station_kind)
	for i in range(_station_len_btns.size()):
		_highlight_active_btn(_station_len_btns[i], i == _build_station_len_idx)
	for i in range(_bed_btns.size()):
		_highlight_active_btn(_bed_btns[i], i == _build_bed_style)
	for i in range(_elev_btns.size()):
		_highlight_active_btn(_elev_btns[i], i == _build_elev_idx)
	if _btn_underground != null and is_instance_valid(_btn_underground):
		_highlight_active_btn(_btn_underground, _underground_view)

	if _build_panel != null:
		_build_panel.reset_size()


func _max_sections_for_draft() -> int:
	if _draft_station_ids.is_empty():
		return 4
	var min_plat := 56.0
	for sid: int in _draft_station_ids:
		if _graph.stations.has(sid):
			min_plat = minf(min_plat, float(_graph.stations[sid].get("platform_len", 27.0)))
	if min_plat >= 48.0:
		return 4
	if min_plat >= 36.0:
		return 3
	return 2


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
	if _editing_line_id >= 0 and not _graph.lines.has(_editing_line_id):
		_editing_line_id = -1
	var edit_tag := ""
	if _editing_line_id >= 0:
		edit_tag = L10n.t("✎ 正在编辑【%s】· ", "✎ Editing [%s] · ") % L10n.line_display_name(str(_graph.lines[_editing_line_id]["name"]))
	if _draft_station_ids.is_empty():
		_lbl_draft_stops.text = edit_tag + L10n.t("当前待建线路站点：（请直接单击地图上已建成的 3D 车站按顺序串联站点；再次点击首站可组成闭合环线）", "Draft Stops: (Click built 3D stations on the map in order; click the 1st station again for a closed loop)")
		_route_preview_mi.mesh = null
	else:
		var mode_tag := L10n.t("【闭合环线】", "[Loop]") if _draft_is_loop() else L10n.t("【双向往返线】", "[Shuttle]")
		var where := L10n.t("地图上点击车站将追加到末尾", "Clicking a station appends to end") if _draft_insert_idx < 0 else (L10n.t("地图上点击车站将插入到第 %d 站之后", "Clicking a station inserts after #%d") % (_draft_insert_idx + 1))
		_lbl_draft_stops.text = L10n.t("%s%s 已选 %d 站 · %s", "%s%s %d stops · %s") % [edit_tag, mode_tag, _draft_station_ids.size(), where]
		_update_draft_route_preview()
	_refresh_draft_list_ui()
	if _btn_plan_service != null:
		_btn_plan_service.text = L10n.t("运行类别：快车（四轨走内侧快车道 · 优先越行）", "Service: Express (4-track inner rails · overtakes)") if _plan_express else L10n.t("运行类别：普通慢车（四轨走外侧慢车道 · 遇快车待避）", "Service: Local (4-track outer rails · yields)")
		_highlight_active_btn(_btn_plan_service, _plan_express)
	if _btn_plan_tsp != null:
		_btn_plan_tsp.text = L10n.t("信号优先：开（进路口自动延长绿灯 / 提前切绿）", "Signal Priority: ON (green ext. / early green)") if _plan_signal_priority else L10n.t("信号优先：关（按固定信号灯周期通行）", "Signal Priority: OFF (fixed cycle)")
		_highlight_active_btn(_btn_plan_tsp, _plan_signal_priority)
	if _btn_commit_line != null:
		_btn_commit_line.text = L10n.t("✓ 保存对线路的修改", "✓ Save Line Changes") if _editing_line_id >= 0 else L10n.t("✓ 确认开通此线路", "✓ Launch Line")
		_btn_cancel_edit.visible = _editing_line_id >= 0

	if not _tram_models.is_empty():
		var m: Dictionary = _tram_models[_plan_model_idx]
		var era_txt := L10n.t("古典老电车", "Vintage") if bool(m.get("vintage", false)) else L10n.t("现代低地板", "Modern")
		_lbl_model_card.text = L10n.t("车型 [%d/%d]：%s\n%s · %s · 极速 %d km/h · 加速度 %.2f m/s²", "Model [%d/%d]: %s\n%s · %s · Max %d km/h · Accel %.2f m/s²") % [
			_plan_model_idx + 1,
			_tram_models.size(),
			L10n.model_name(m),
			L10n.model_origin(m),
			era_txt,
			int(m.get("max_speed_kmh", 70)),
			float(m.get("accel", 1.2)),
		]
		var max_sec := _max_sections_for_draft()
		if _plan_sections > max_sec:
			_plan_sections = max_sec
		var total_cap := _plan_sections * int(m.get("cap_per_section", 58))
		var is_draft_loop := (_draft_station_ids.size() >= 3 and _draft_station_ids[0] == _draft_station_ids[_draft_station_ids.size() - 1])
		var warn_single := ""
		if not _draft_station_ids.is_empty() and not is_draft_loop and _plan_fleet_count > 1:
			warn_single = L10n.t("\n⚠ 单轨往返线配多车对开将迎面相撞！多车请连回首站组成环线", "\n⚠ Multi-tram shuttles on single track will collide! Close the loop for multiple trams")
		_lbl_fleet_cfg.text = L10n.t("配车规模：%d 辆 · 编组：%d/%d 节（适配所选站台长度 · 定员 %d 人）%s", "Fleet: %d trams · Consist: %d/%d cars (Cap %d)%s") % [_plan_fleet_count, _plan_sections, max_sec, total_cap, warn_single]

	_refresh_lines_list_ui()


func _draft_is_loop() -> bool:
	var n := _draft_station_ids.size()
	return n >= 3 and _draft_station_ids[0] == _draft_station_ids[n - 1]


func _stations_linked(a: int, b: int) -> bool:
	return a != b and not _graph.find_track_path_between_stations(a, b).is_empty()


# Load an existing line into the planner: stops, vehicle model, fleet size and consist length can then be changed
func _begin_line_edit(lid: int) -> void:
	if not _graph.lines.has(lid):
		return
	var ln: Dictionary = _graph.lines[lid]
	_editing_line_id = lid
	_draft_insert_idx = -1
	_draft_station_ids.clear()
	for raw_sid in ln["station_ids"]:
		_draft_station_ids.append(int(raw_sid))
	_plan_era_filter = "all"
	for i in range(_tram_models.size()):
		if str(_tram_models[i].get("key", "")) == str(ln.get("model_key", "")):
			_plan_model_idx = i
	_plan_fleet_count = int(ln.get("trams_count", 2))
	_plan_sections = int(ln.get("sections", 2))
	_plan_express = bool(ln.get("express", false))
	_plan_signal_priority = bool(ln.get("signal_priority", false))
	_refresh_plan_ui()
	_show_toast(L10n.t("✎ 正在编辑 %s：可增删车站、换车型、改配车数量与编组，完成后点【保存对线路的修改】", "✎ Editing %s: adjust stops, model, fleet & cars, then click [Save Line Changes]") % L10n.line_display_name(str(ln["name"])))


func _cancel_line_edit(toast: bool) -> void:
	var was := _editing_line_id
	_editing_line_id = -1
	_draft_insert_idx = -1
	_draft_station_ids.clear()
	_refresh_plan_ui()
	if toast and was >= 0:
		_show_toast(L10n.t("已取消编辑，线路保持原样", "Edit cancelled — line unchanged"))


# Station clicked on the map: append it, or insert it after the chosen stop (both neighbours must be linked by track)
func _draft_insert_station(sid: int) -> void:
	var n := _draft_station_ids.size()
	var pos := n
	if _draft_insert_idx >= 0 and _draft_insert_idx < n - 1:
		pos = _draft_insert_idx + 1
	elif _draft_is_loop():
		pos = n - 1 # a closed loop grows before its closing stop
	var prev_sid := _draft_station_ids[pos - 1] if pos > 0 else -1
	var next_sid := _draft_station_ids[pos] if pos < n else -1
	if sid == prev_sid or sid == next_sid:
		return
	if prev_sid >= 0 and not _stations_linked(prev_sid, sid):
		_show_toast(L10n.t("该车站与前一站（%s）之间没有连通的已建轨道！请先在【建设轨道】连通轨道。", "No connected track from previous stop (%s) — connect tracks first in [Build Track]!") % L10n.station_display_name(str(_graph.stations[prev_sid]["name"])))
		return
	if next_sid >= 0 and not _stations_linked(sid, next_sid):
		_show_toast(L10n.t("该车站与后一站（%s）之间没有连通的已建轨道，无法插入到这里！", "No connected track to next stop (%s) — cannot insert here!") % L10n.station_display_name(str(_graph.stations[next_sid]["name"])))
		return
	_draft_station_ids.insert(pos, sid)
	if _draft_insert_idx >= 0:
		_draft_insert_idx = pos # keep inserting after the stop just added
	_refresh_plan_ui()


func _draft_undo_last() -> void:
	if _draft_station_ids.is_empty():
		return
	if _draft_insert_idx >= 0 and _draft_insert_idx < _draft_station_ids.size():
		_draft_remove_at(_draft_insert_idx)
		return
	_draft_station_ids.pop_back()
	_draft_insert_idx = -1
	_refresh_plan_ui()


# Remove one stop; the stops either side must still be linked by track
func _draft_remove_at(idx: int) -> void:
	var n := _draft_station_ids.size()
	if idx < 0 or idx >= n:
		return
	var cand: Array[int] = []
	if _draft_is_loop():
		var ring: Array[int] = _draft_station_ids.slice(0, n - 1)
		ring.remove_at(idx % (n - 1))
		cand = ring
		if ring.size() >= 2:
			cand.append(ring[0])
	else:
		cand = _draft_station_ids.duplicate()
		cand.remove_at(idx)
	for i in range(cand.size() - 1):
		if not _stations_linked(cand[i], cand[i + 1]):
			_show_toast(L10n.t("删除后 %s 与 %s 之间没有连通轨道，无法删除这一站！", "Removing this stop breaks track connectivity between %s and %s!") % [L10n.station_display_name(str(_graph.stations[cand[i]]["name"])), L10n.station_display_name(str(_graph.stations[cand[i + 1]]["name"]))])
			return
	_draft_station_ids = cand
	if _draft_insert_idx >= idx:
		_draft_insert_idx -= 1 # cursor stays on the same stop (or the one before a removed cursor stop)
	if _draft_insert_idx >= _draft_station_ids.size() - 1:
		_draft_insert_idx = -1 # after the last stop is simply "append"
	_refresh_plan_ui()


func _refresh_draft_list_ui() -> void:
	if _draft_list_vbox == null:
		return
	for c in _draft_list_vbox.get_children():
		c.queue_free()
	var n := _draft_station_ids.size()
	var loop := _draft_is_loop()
	for i in range(n):
		var sid := _draft_station_ids[i]
		if not _graph.stations.has(sid):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var lbl := Label.new()
		var st_nm := L10n.station_display_name(str(_graph.stations[sid]["name"]))
		if loop and i == n - 1:
			lbl.text = L10n.t("    ↺ 回到 %s（闭合环线）", "    ↺ Return to %s (Loop)") % st_nm
			lbl.add_theme_color_override("font_color", Color(0.62, 0.78, 0.9))
			_fit_label(lbl)
			row.add_child(lbl)
			_draft_list_vbox.add_child(row)
			continue
		var cur := i == _draft_insert_idx
		lbl.text = "%s%d. %s" % ["▶ " if cur else "", i + 1, st_nm]
		lbl.tooltip_text = st_nm
		lbl.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45) if cur else Color(0.9, 0.93, 0.97))
		_fit_label(lbl)
		row.add_child(lbl)
		var i_copy := i
		var ins_btn := _make_btn(L10n.t("取消插入", "Cancel") if cur else L10n.t("在此后插入", "Insert After"), func():
			_draft_insert_idx = -1 if _draft_insert_idx == i_copy else i_copy
			_refresh_plan_ui()
		)
		ins_btn.tooltip_text = L10n.t("之后在地图上点击的车站会插入到这一站后面", "Stations clicked on the map will be inserted after this stop")
		row.add_child(ins_btn)
		var del_btn := _make_btn("✕", func(): _draft_remove_at(i_copy))
		del_btn.tooltip_text = L10n.t("从线路中删除这一站", "Remove this stop from the line")
		row.add_child(del_btn)
		_draft_list_vbox.add_child(row)


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
	_route_preview_mi.mesh = Terrain.drape_mesh(st.commit()) if Terrain.active else st.commit()
	_route_preview_mi.material_override = _translucent_mat(Color(0.18, 0.72, 1.0, 0.85))


func _commit_draft_line() -> void:
	if _draft_station_ids.size() < 2:
		_show_toast(L10n.t("请至少在地图上依次点击 2 座已连通轨道的车站！", "Click at least 2 connected stations on the map!"))
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
		_show_toast(L10n.t("已自动换成%s车型：%s", "Auto-switched to %s model: %s") % [L10n.t("单轨", "monorail") if on_mono else L10n.t("电车", "tram"), L10n.model_name(m)])
	if _plan_express:
		for sid_x: int in _draft_station_ids:
			if not _graph.express_can_call_at(sid_x):
				_show_toast(L10n.t("⚠ 快车不能停靠四轨外侧侧式站台（%s）：请改为慢车，或在该处建四轨双岛式站台", "⚠ Express cannot stop at 4-track outer side platform (%s) — switch to Local or build Twin-Island!") % L10n.station_display_name(str(_graph.stations[sid_x]["name"])))
				return
	if _editing_line_id >= 0:
		var elid := _editing_line_id
		if not _graph.update_line(elid, _draft_station_ids, str(m["key"]), _plan_fleet_count, _plan_sections, _plan_express, _plan_signal_priority):
			_show_toast(L10n.t("无法保存修改：站点间缺少连通轨道！", "Cannot save changes: missing track connection between stops!"))
			return
		_editing_line_id = -1
		_draft_insert_idx = -1
		_draft_station_ids.clear()
		_ops_dirty = true
		_refresh_plan_ui()
		_mark_modified_and_quick_save()
		_show_toast(L10n.t("✓ 已保存 %s 的修改（%d 站 · 配车 %d 辆 · %s · %d 节编组），进入【3.运行与驾驶】后按新方案发车", "✓ Saved %s (%d stops · %d trams · %s · %d-car). Enter [3. Run & Drive] to dispatch!") % [
			L10n.line_display_name(str(_graph.lines[elid]["name"])),
			(_graph.lines[elid]["station_ids"] as Array).size(),
			_plan_fleet_count,
			L10n.model_name(m),
			_plan_sections,
		])
		return
	var lid := _graph.create_line(_draft_station_ids, str(m["key"]), _plan_fleet_count, _plan_sections, "", _plan_express, _plan_signal_priority)
	if lid < 0:
		_show_toast(L10n.t("无法生成线路：站点间缺少连通轨道！", "Cannot create line: missing track connection between stops!"))
		return
	_draft_station_ids.clear()
	_draft_insert_idx = -1
	_ops_dirty = true
	_refresh_plan_ui()
	_mark_modified_and_quick_save()
	_show_toast(L10n.t("✓ 已成功开通 %s（配车 %d 辆 · %s）！点击顶部【3.运行与驾驶】即可发车！", "✓ Launched %s (%d trams · %s)! Click [3. Run & Drive] to begin!") % [
		L10n.line_display_name(str(_graph.lines[lid]["name"])),
		_plan_fleet_count,
		L10n.model_name(m),
	])


func _refresh_lines_list_ui() -> void:
	if _lines_list_vbox == null:
		return
	for c in _lines_list_vbox.get_children():
		c.queue_free()
	if _graph.lines.is_empty():
		var empty_l := Label.new()
		empty_l.text = L10n.t("（暂无开通线路）", "(No active lines)")
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
		var mdl_nm := ""
		for md: Dictionary in _tram_models:
			if str(md.get("key", "")) == str(ln.get("model_key", "")):
				mdl_nm = L10n.model_name(md)
		lbl.text = L10n.t("%s%s%s%s (%d站 · %d辆 · %s)", "%s%s%s%s (%d sta · %d trams · %s)") % [
			"✎ " if lid == _editing_line_id else "",
			L10n.t("【快】", "[EXP] ") if bool(ln.get("express", false)) else "",
			L10n.t("【优】", "[TSP] ") if _graph.is_line_signal_priority(lid) else "",
			L10n.line_display_name(str(ln["name"])),
			(ln["station_ids"] as Array).size(),
			int(ln["trams_count"]),
			mdl_nm,
		]
		lbl.tooltip_text = lbl.text
		_fit_label(lbl)
		if lid == _editing_line_id:
			lbl.add_theme_color_override("font_color", Color(0.98, 0.86, 0.45))
		row.add_child(lbl)

		var lid_copy := lid
		row.add_child(_make_btn(L10n.t("编辑", "Edit"), func(): _begin_line_edit(lid_copy)))
		row.add_child(_make_btn(L10n.t("删除", "Del"), func():
			_graph.lines.erase(lid_copy)
			if _editing_line_id == lid_copy:
				_cancel_line_edit(false)
			_ops_dirty = true
			_refresh_plan_ui()
			_mark_modified_and_quick_save()
		))
		_lines_list_vbox.add_child(row)


func _update_run_hud() -> void:
	var map_nm := _map_title(_current_map_key)
	_lbl_net_stats.text = L10n.t(
		"%s：%d 条线路 · 在线 %d 辆 · 候车 %d 人 · 累计送达 %d 人",
		"%s: %d lines · %d trams · %d waiting · %d delivered"
	) % [
		map_nm,
		_graph.lines.size(),
		_transit_sim.trams.size(),
		_pax_sim.get_total_waiting(),
		_pax_sim.total_delivered,
	]

	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		_lbl_tram_info.text = L10n.t("当前无线路车辆运行，请前往【1.建设轨道】与【2.规划线路】开通电车线！", "No active trams — build tracks in [1] and launch a line in [2]!")
		_lbl_station_next.text = ""
		_lbl_speed.text = "00.0 km/h"
		return

	var spec: Dictionary = tr["spec"]
	var pax_n: int = (tr["pax_dests"] as Array).size()
	var cap: int = int(tr["capacity"])
	var cur_ai_style := int(tr.get("ai_style", TransitSim.AIStyle.NORMAL))
	var cur_ai_max := int(tr.get("ai_max_kmh", TransitSim.tram_spec_max_kmh(tr)))
	var style_nm := TransitSim.tram_ai_style_name(tr)
	var mode_str := L10n.t("【手动驾驶】", "[Manual Drive]") if _transit_sim.manual_drive else (L10n.t("【AI 运营 · %s · 最高 %d km/h】", "[AI · %s · Max %d km/h]") % [style_nm, cur_ai_max])
	var act_lid := int(tr["line_id"])
	var same_line := _transit_sim.line_tram_indices(act_lid)
	var ln_disp := L10n.line_display_name(str(tr["line_name"]))
	_lbl_tram_info.text = L10n.t(
		"%s 第%d/%d列 · %s · 车上乘客：%d/%d 人 %s",
		"%s #%d/%d · %s · Onboard: %d/%d %s"
	) % [
		ln_disp,
		same_line.find(_transit_sim.active_tram_idx) + 1,
		same_line.size(),
		L10n.model_name(spec),
		pax_n,
		cap,
		mode_str,
	]
	for si in range(_ai_style_btns.size()):
		_highlight_active_btn(_ai_style_btns[si], si == cur_ai_style)
	var line_common_style := _transit_sim.get_line_ai_style(act_lid)
	if _lbl_line_ai_group != null:
		_lbl_line_ai_group.text = L10n.t("%s 整组AI：", "%s AI Group:") % ln_disp
	var line_btn_styles := [TransitSim.LINE_AI_NONE, TransitSim.AIStyle.SLOW, TransitSim.AIStyle.NORMAL, TransitSim.AIStyle.FURIOUS]
	for lsi in range(mini(_line_ai_style_btns.size(), line_btn_styles.size())):
		_highlight_active_btn(_line_ai_style_btns[lsi], line_common_style == line_btn_styles[lsi])
	if _btn_ai_spd_val != null:
		var spec_top := TransitSim.tram_spec_max_kmh(tr)
		_btn_ai_spd_val.text = "%d km/h" % cur_ai_max
		_highlight_active_btn(_btn_ai_spd_val, bool(tr.get("ai_max_custom", false)) or cur_ai_max != spec_top)
		if _btn_ai_spd_down != null:
			_btn_ai_spd_down.disabled = cur_ai_max <= TransitSim.AI_MIN_MAX_KMH
		if _btn_ai_spd_up != null:
			_btn_ai_spd_up.disabled = cur_ai_max >= spec_top
	if _btn_line_tsp != null:
		var line_tsp := bool((_graph.lines.get(act_lid, {}) as Dictionary).get("signal_priority", false))
		_btn_line_tsp.text = (L10n.t("%s信号优先：开", "%s TSP: ON") % ln_disp) if line_tsp else (L10n.t("%s信号优先：关", "%s TSP: OFF") % ln_disp)
		_highlight_active_btn(_btn_line_tsp, _graph.is_line_signal_priority(act_lid))
	if _btn_global_tsp != null:
		_btn_global_tsp.text = L10n.t("全局信号优先：开", "Global TSP: ON") if _graph.global_signal_priority else L10n.t("全局信号优先：关", "Global TSP: OFF")
		_highlight_active_btn(_btn_global_tsp, _graph.global_signal_priority)

	var st_info := _transit_sim.find_next_stop_info(tr)
	var dist := float(st_info["dist"])
	var doors_engaged := bool(tr.get("doors_target_open", false)) or float(tr.get("door_ratio", 0.0)) > 0.02
	if _transit_sim.manual_drive and not doors_engaged:
		# Manual driving: until the doors open, show unscheduled station if currently alongside one, else scheduled approach
		tr.erase("xfer_snap")
		var near_u := _transit_sim._find_station_at_current_pos(tr, true, _graph)
		if bool(near_u.get("unscheduled", false)) and int(near_u.get("station_id", -1)) >= 0 and _graph.stations.has(int(near_u["station_id"])):
			var usid := int(near_u["station_id"])
			var unm := L10n.station_display_name(str((_graph.stations[usid] as Dictionary).get("name", L10n.t("站台", "Platform"))))
			var up_u := _transit_sim.get_upcoming_station_ids(tr, -1, usid)
			var match_n := _pax_sim.get_boardable_count_for_tram(usid, tr, up_u)
			var tot_w := _pax_sim.get_boardable_count(usid)
			_lbl_station_next.text = L10n.t("◎ 临时停靠：%s（非本线计划站）· 可乘 %d/%d 人 · 停稳后可按 O 开门", "◎ Unscheduled Stop: %s (off-schedule) · %d/%d boardable · Stop & press O") % [unm, match_n, tot_w]
		else:
			var ap := _transit_sim.stop_approach_info(tr)
			if ap.is_empty():
				_lbl_station_next.text = L10n.t("▸ 下一站：%s · 距离 %.0f m", "▸ Next Stop: %s · %.0f m") % [L10n.station_display_name(str(st_info["name"])), dist]
			else:
				var sd := float(ap["signed_dist"])
				var nm := L10n.station_display_name(str(ap["name"]))
				var wait_n := _pax_sim.get_boardable_count(int(ap["station_id"]))
				if sd < -0.5:
					_lbl_station_next.text = L10n.t("⚠ 已越过 %s 停车位置 %.1f m · 只有对准站台的车门能打开", "⚠ Overshot %s stop mark by %.1f m · Only aligned doors will open") % [nm, sd]
				elif sd <= 0.5:
					_lbl_station_next.text = L10n.t("◎ %s · 停车位置 %+.1f m（对准）· 站台候车 %d 人 · 停稳后按 O 开门", "◎ %s · Stop mark %+.1f m (aligned) · %d waiting · Stop & press O") % [nm, sd, wait_n]
				elif sd < 60.0:
					_lbl_station_next.text = L10n.t("▸ 进站：%s · 距停车位置 %.1f m · 站台候车 %d 人", "▸ Approaching: %s · %.1f m to mark · %d waiting") % [nm, sd, wait_n]
				else:
					_lbl_station_next.text = L10n.t("▸ 下一站：%s · 距离 %.0f m", "▸ Next Stop: %s · %.0f m") % [nm, sd]
	elif dist < 5.5 or doors_engaged:
		var board_st := st_info
		if _transit_sim.manual_drive and doors_engaged:
			var dock_u := _transit_sim.get_dock_info_for_tram(tr, _graph, true)
			if bool(dock_u.get("unscheduled", false)) and int(dock_u.get("station_id", -1)) >= 0 and _graph.stations.has(int(dock_u["station_id"])):
				var usid2 := int(dock_u["station_id"])
				var unm2 := L10n.station_display_name(str((_graph.stations[usid2] as Dictionary).get("name", L10n.t("站台", "Platform"))))
				board_st = {"station_id": usid2, "name": L10n.t("%s（临时停靠）", "%s (Unscheduled)") % unm2, "stop_idx": -1, "unscheduled": true}
		_lbl_station_next.text = _boarding_status_text(tr, board_st)
	else:
		tr.erase("xfer_snap")
		_lbl_station_next.text = L10n.t("▸ 下一站：%s · 距离 %.0f m", "▸ Next Stop: %s · %.0f m") % [L10n.station_display_name(str(st_info["name"])), dist]

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
		_lbl_speed_limit.text = L10n.t("⚠ %s限速 %.0f km/h（超速！≥%.0f 翻车）", "⚠ %s Limit %.0f km/h (OVERSPEED! ≥%.0f derail)") % [z_name, lim_kmh, der_kmh]
		_lbl_speed_limit.add_theme_color_override("font_color", Color(1.0, 0.34, 0.28))
	elif is_over:
		_lbl_speed.add_theme_color_override("font_color", Color(1.0, 0.76, 0.28))
		_lbl_speed_limit.text = L10n.t("【%s限速 %.0f km/h · 超速】", "[%s Limit %.0f km/h · OVERSPEED]") % [z_name, lim_kmh]
		_lbl_speed_limit.add_theme_color_override("font_color", Color(1.0, 0.76, 0.28))
	else:
		_lbl_speed.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		_lbl_speed_limit.text = L10n.t("【%s限速 %.0f km/h】", "[%s Limit %.0f km/h]") % [z_name, lim_kmh]
		var badge_c := Color(0.98, 0.78, 0.32) if int(lim_stat["zone_kind"]) >= 2 else Color(0.54, 0.92, 0.72)
		_lbl_speed_limit.add_theme_color_override("font_color", badge_c)

	# Check upcoming Dedicated Tram Signal, traffic hazard, or curve/turnout speed limit!
	var hazard_msg := ""
	var sig_badge_txt := L10n.t("电车灯 ┃ 通行", "Signal ┃ Go")
	var secs_h: Array = tr["tram_info"]["sections"]
	if _traffic_sim != null and not secs_h.is_empty():
		var sig_info := _traffic_sim.get_upcoming_tram_signal(tr, _graph)
		if bool(sig_info["has_signal"]):
			var asp := str(sig_info["aspect"])
			var sd := float(sig_info["dist"])
			var tsp_tag := L10n.t(" · ⚡信号优先", " · ⚡TSP") if bool(sig_info.get("tsp_active", false)) else ""
			if asp == "red":
				sig_badge_txt = L10n.t("电车灯 ━ 禁行(%.0fm)%s", "Signal ━ Stop(%.0fm)%s") % [sd, tsp_tag]
				hazard_msg = L10n.t("● 前方 %.0fm 电车专用灯【━ 禁行】· 横向绿灯车流通过，请在停止线前停车！%s", "● %.0fm ahead: Tram Signal [━ STOP] · Cross-traffic active, stop before line!%s") % [sd, tsp_tag]
			elif asp == "yellow":
				sig_badge_txt = L10n.t("电车灯 ● 黄灯(%.0fm)%s", "Signal ● Caution(%.0fm)%s") % [sd, tsp_tag]
				hazard_msg = L10n.t("● 前方 %.0fm 电车专用灯【● 黄灯转换】· 请提前减速准备停车%s", "● %.0fm ahead: Tram Signal [● CAUTION] · Prepare to stop%s") % [sd, tsp_tag]
			else:
				sig_badge_txt = L10n.t("电车灯 ┃ 通行(%.0fm)%s", "Signal ┃ Go(%.0fm)%s") % [sd, tsp_tag]

		var swi := _transit_sim.switch_ahead_info(tr, _transit_sim.active_tram_idx)
		var sw_near := not swi.is_empty() and float(swi["dist"]) < 220.0
		if bool(tr.get("elevated", false)) or sw_near: # street trams: shown while a switch signal is ahead
			sig_badge_txt = L10n.t("道岔信号 ┃ 通行", "Switch ┃ Clear")
			if not swi.is_empty() and float(swi["dist"]) < 220.0:
				var sd2 := maxf(0.0, float(swi["dist"]) - TransitSim.SW_SIGNAL_BACK + 2.0)
				var need_txt := L10n.t("侧向(渡线)", "Diverging") if float(swi["need"]) > 0.5 else L10n.t("直向", "Straight")
				var cur_txt := L10n.t("侧向(渡线)", "Diverging") if float(swi["target"]) > 0.5 else L10n.t("直向", "Straight")
				if bool(swi["green"]):
					sig_badge_txt = L10n.t("道岔信号 ┃ 通行(%.0fm)", "Switch ┃ Clear(%.0fm)") % sd2
					hazard_msg = L10n.t("▸ 前方 %.0fm 道岔已排列【%s】并锁闭 · 信号开放", "▸ %.0fm ahead: Switch set [%s] & locked · Signal clear") % [float(swi["dist"]), cur_txt]
				else:
					sig_badge_txt = L10n.t("道岔信号 ━ 停车(%.0fm)", "Switch ━ Stop(%.0fm)") % sd2
					if bool(swi["busy"]):
						hazard_msg = L10n.t("● 前方 %.0fm 道岔被其他列车占用 · 信号【━ 停车】，请在信号机前停车等待", "● %.0fm ahead: Switch occupied · [━ STOP], hold before signal") % float(swi["dist"])
					elif bool(swi["moving"]):
						hazard_msg = L10n.t("● 前方 %.0fm 道岔转辙中 → %s · 信号【━ 停车】", "● %.0fm ahead: Switch throwing → %s · [━ STOP]") % [float(swi["dist"]), cur_txt]
					elif bool(swi.get("override", false)):
						hazard_msg = L10n.t("● 前方 %.0fm 道岔被手动扳到【%s】，与进路【%s】不符 · 信号【━ 停车】，再按 G 恢复，否则驶入将脱轨！", "● %.0fm ahead: Switch manually set [%s], route needs [%s] · [━ STOP], press G to align!") % [float(swi["dist"]), cur_txt, need_txt]
					else:
						hazard_msg = L10n.t("● 前方 %.0fm 道岔信号【━ 停车】· 等待道岔排列 %s", "● %.0fm ahead: Switch [━ STOP] · Waiting for %s route") % [float(swi["dist"]), need_txt]
		var f0 := secs_h[0] as Node3D
		var car_haz := {"has_hazard": false} if bool(tr.get("elevated", false)) else _traffic_sim.find_hazard_ahead_of_tram(f0.global_position, -f0.global_transform.basis.z, 36.0)
		if bool(car_haz["has_hazard"]):
			hazard_msg = L10n.t("⚠ 前方 %.0fm 路口有小车通行！请制动(S)避让", "⚠ Car crossing %.0fm ahead! Brake (S) to yield") % float(car_haz["dist"])

	if hazard_msg.is_empty():
		var next_d := float(lim_stat["next_dist_m"])
		if next_d < 72.0:
			hazard_msg = L10n.t("▸ 预告：前方 %.0fm 进入【%s】，限速 %.0f km/h（超速将脱轨翻车）", "▸ Ahead %.0fm: [%s] Limit %.0f km/h (overspeed risks derailment)") % [
				next_d,
				str(lim_stat["next_zone_name"]),
				float(lim_stat["next_limit_kmh"]),
			]
		else:
			hazard_msg = L10n.t("交通秩序正常：遵守电车专用灯(┃通行/━禁行)与弯道道岔限速牌", "Traffic normal: obey tram signals (┃Go / ━Stop) and curve/switch limits")
	_lbl_hazard_hint.text = hazard_msg

	var n_idx := int(tr["notch"])
	var n_col := Color(0.78, 0.82, 0.86)
	if n_idx > TransitSim.NOTCH_NEUTRAL:
		n_col = Color(0.28, 0.88, 0.54)
	elif n_idx == 0:
		n_col = Color(1.0, 0.28, 0.28)
	elif n_idx < TransitSim.NOTCH_NEUTRAL:
		n_col = Color(0.96, 0.72, 0.26)
	var reversing := float(tr.get("reverser", 1.0)) < 0.0
	_lbl_notch.text = (L10n.t("档位 R · ", "Notch R · ") if reversing else L10n.t("档位 ", "Notch ")) + TransitSim.NOTCH_LABELS[n_idx]
	if reversing:
		n_col = Color(0.98, 0.56, 0.30)
	_lbl_notch.add_theme_color_override("font_color", n_col)

	var dir_txt := L10n.t("前进", "Forward") if float(tr["dir"]) > 0.0 else L10n.t("折返向", "Return")
	if reversing:
		dir_txt = L10n.t("⏪ 倒车 R（向后）", "⏪ Reverse R")
	var door_txt := L10n.t("车门锁闭", "Doors Locked")
	if float(tr["door_ratio"]) > 0.1:
		var od := int(tr.get("open_doorways", 0))
		var td := int(tr.get("total_doorways", 1))
		door_txt = (L10n.t("站台侧开启 %d/%d 门(非站台侧锁闭)", "Platform Doors Open %d/%d") % [od, td]) if od > 0 else L10n.t("未对齐站台·全门锁闭", "Not Aligned · Doors Locked")
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

	_btn_doors.text = L10n.t("关闭车门 (O)", "Close Doors (O)") if bool(tr["doors_target_open"]) else L10n.t("打开车门 (O)", "Open Doors (O)")
	if _btn_reverser != null:
		_btn_reverser.text = L10n.t("回前进档 (X)", "Forward (X)") if reversing else L10n.t("倒档 R (X)", "Reverse R (X)")
		_highlight_active_btn(_btn_reverser, reversing)
	if _btn_sw_lock != null:
		var locked := not _transit_sim.player_lock.is_empty()
		_btn_sw_lock.text = L10n.t("🔒 道岔已锁定 (J)", "🔒 Switch Locked (J)") if locked else L10n.t("锁定前方道岔 (J)", "Lock Switch (J)")
		_highlight_active_btn(_btn_sw_lock, locked)
		if _transit_sim.lock_released:
			_transit_sim.lock_released = false
			_show_toast(L10n.t("🔓 本车已驶出锁定的道岔，锁定自动解除", "🔓 Cleared locked switch — lock released automatically"))
	if _btn_auto_sw != null:
		_btn_auto_sw.text = L10n.t("AI 道岔: 开 (U)", "AI Switch: ON (U)") if _transit_sim.auto_switches else L10n.t("AI 道岔: 关 (U)", "AI Switch: OFF (U)")
		_highlight_active_btn(_btn_auto_sw, not _transit_sim.auto_switches)
	if _btn_hold_manual != null:
		var held := bool(tr.get("held_manual", false))
		_btn_hold_manual.text = L10n.t("📌 已保留手动 (K)", "📌 Held Manual (K)") if held else L10n.t("保留手动 (K)", "Hold Manual (K)")
		_highlight_active_btn(_btn_hold_manual, held)
	_btn_drive_mode.text = L10n.t("切回 AI 托管 (Q)", "Return to AI (Q)") if _transit_sim.manual_drive else L10n.t("接管手动驾驶 (Q)", "Take Manual Control (Q)")


func _on_set_active_tram_ai_style(style: int) -> void:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	_transit_sim.set_active_tram_ai_style(style)
	var same_line := _transit_sim.line_tram_indices(int(tr["line_id"]))
	var ord_i := same_line.find(_transit_sim.active_tram_idx) + 1
	var desc := L10n.t("平缓驾驶 · 停稳2.5s开门 · 上客后延后关门并等待赶来乘客", "Gentle drive · 2.5s door delay · holds for approaching riders") if style == TransitSim.AIStyle.SLOW else (
		L10n.t("加速度与刹车拉满 · 进出站高效 · 开关门同标准模式", "Max accel/brake · smooth cruise · full normal boarding") if style == TransitSim.AIStyle.FURIOUS else L10n.t("标准运营基准", "Standard transit profile")
	)
	_show_toast(L10n.t("🚋 %s 第%d列 AI运营方式设为【%s】（%s）", "🚋 %s #%d AI mode set to [%s] (%s)") % [L10n.line_display_name(str(tr["line_name"])), ord_i, TransitSim.tram_ai_style_name(tr), desc])
	_update_run_hud()


func _on_set_line_ai_style(lid: int, style: int) -> void:
	if not _graph.lines.has(lid):
		return
	var ln: Dictionary = _graph.lines[lid]
	var cnt := _transit_sim.set_line_ai_style(lid, style)
	var ln_disp := L10n.line_display_name(str(ln.get("name", L10n.t("线路 %d", "Line %d") % lid)))
	if style < 0:
		_show_toast(L10n.t("🚋 %s 整组AI已恢复【无默认】（各车保持当前独立设置）", "🚋 %s AI Group reset to [No Default] (trams keep individual modes)") % ln_disp)
	else:
		_show_toast(L10n.t("🚋 %s 全部 %d 列电车 AI 运营模式已设为【%s】", "🚋 All %d trams on %s set to [%s] AI mode") % ([ln_disp, cnt, TransitSim.ai_style_name(style)] if not L10n.is_en() else [cnt, ln_disp, TransitSim.ai_style_name(style)]))
	_update_run_hud()


func _on_set_active_line_ai_style(style: int) -> void:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	_on_set_line_ai_style(int(tr["line_id"]), style)


func _on_adjust_active_tram_ai_max_kmh(delta_kmh: int) -> void:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	var new_kmh := _transit_sim.adjust_active_tram_ai_max_kmh(delta_kmh)
	var same_line := _transit_sim.line_tram_indices(int(tr["line_id"]))
	var ord_i := same_line.find(_transit_sim.active_tram_idx) + 1
	_show_toast(L10n.t("🚋 %s 第%d列 AI运营最高速度设为 %d km/h", "🚋 %s #%d AI max speed set to %d km/h") % [L10n.line_display_name(str(tr["line_name"])), ord_i, new_kmh])
	_update_run_hud()


func _on_reset_active_tram_ai_max_kmh() -> void:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	var new_kmh := _transit_sim.reset_active_tram_ai_max_kmh()
	var same_line := _transit_sim.line_tram_indices(int(tr["line_id"]))
	var ord_i := same_line.find(_transit_sim.active_tram_idx) + 1
	_show_toast(L10n.t("🚋 %s 第%d列 AI运营最高速度已恢复车型默认（%d km/h）", "🚋 %s #%d AI max speed reset to model default (%d km/h)") % [L10n.line_display_name(str(tr["line_name"])), ord_i, new_kmh])
	_update_run_hud()


func _on_toggle_line_tsp(lid: int) -> void:
	if not _graph.lines.has(lid):
		return
	var ln: Dictionary = _graph.lines[lid]
	var new_v := not bool(ln.get("signal_priority", false))
	_graph.set_line_signal_priority(lid, new_v)
	_mark_modified_and_quick_save()
	var ln_disp := L10n.line_display_name(str(ln["name"]))
	_show_toast(L10n.t("⚡ %s 信号优先已%s", "⚡ %s Signal Priority: %s") % [
		ln_disp,
		L10n.t("开启（进路口自动延长绿灯 / 提前切绿）", "ON (green extension / early green)") if new_v else L10n.t("关闭", "OFF"),
	])
	_update_run_hud()


func _on_toggle_active_line_tsp() -> void:
	var tr := _transit_sim.get_active_tram()
	if tr.is_empty():
		return
	_on_toggle_line_tsp(int(tr["line_id"]))


func _on_toggle_global_tsp() -> void:
	_graph.global_signal_priority = not _graph.global_signal_priority
	_mark_modified_and_quick_save()
	_show_toast(L10n.t("⚡ 全局信号优先已%s", "⚡ Global Signal Priority: %s") % (
		L10n.t("开启（所有线路享有路口信号优先）", "ON (all lines enabled)") if _graph.global_signal_priority else L10n.t("关闭（按各线路独立设置生效）", "OFF (per-line settings apply)")
	))
	_update_run_hud()


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

	var map_nm := _map_title(_current_map_key)
	if acc_type == "derail":
		var z_nm := str(ev.get("zone_name", L10n.t("急弯/道岔", "Curve/Switch")))
		var lim_v := float(ev.get("limit_kmh", 20.0))
		_lbl_gameover_title.text = L10n.t("【超速脱轨翻车 · 本局运营中止】", "[Overspeed Derailment · Run Ended]")
		_lbl_gameover_detail.text = L10n.t("地图：%s\n电车以 %.1f km/h 高速冲入【%s】（规定限速 %.0f km/h），离心力超限导致脱轨侧翻！\n（您建设的轨道、车站、线路及所有存档均完整保留）", "Map: %s\nEntered [%s] at %.1f km/h (limit %.0f km/h) and derailed!\n(All tracks, stations, lines & saves remain intact)") % ([map_nm, spd_kmh, z_nm, lim_v] if not L10n.is_en() else [map_nm, z_nm, spd_kmh, lim_v])
	elif acc_type == "buffer":
		_lbl_gameover_title.text = L10n.t("【撞击车挡脱轨 · 本局运营中止】", "[Buffer Stop Collision · Run Ended]")
		_lbl_gameover_detail.text = L10n.t("地图：%s\n电车以 %.1f km/h 冲过终点站停车位置，撞上轨道尽头的车挡后脱轨！（车挡只能承受 %.0f km/h 以下的轻触）\n（您建设的轨道、车站、线路及所有存档均完整保留）", "Map: %s\nOverran terminus at %.1f km/h and hit the buffer stop (max safe %.0f km/h)!\n(All tracks, stations, lines & saves remain intact)") % [
			map_nm, spd_kmh, TransitSim.BUFFER_SAFE_KMH
		]
	elif acc_type == "switch":
		_lbl_gameover_title.text = L10n.t("【驶入未开通道岔脱轨 · 本局运营中止】", "[Misaligned Switch Derailment · Run Ended]")
		_lbl_gameover_detail.text = L10n.t("地图：%s\n单轨列车以 %.1f km/h 冒进红色道岔信号，驶入%s的道岔，走行轮离开轨道梁脱轨！（手动驾驶请按 G 把前方道岔扳到本次进路方向，待信号开放后再通过）\n（您建设的轨道、车站、线路及所有存档均完整保留）", "Map: %s\nPassed red switch signal at %.1f km/h into a %s switch and derailed! (Press G in manual mode to align switch)\n(All tracks, stations, lines & saves remain intact)") % [
			map_nm, spd_kmh, L10n.t("正在转辙", "moving") if bool(ev.get("moving", false)) else L10n.t("方向不对", "misaligned")
		]
	elif acc_type == "tram_collision":
		_lbl_gameover_title.text = L10n.t("【电车相撞事故 · 本局运营中止】", "[Tram Collision · Run Ended]")
		_lbl_gameover_detail.text = L10n.t("地图：%s\n两列有轨电车发生严重碰撞（相对撞击速度 %.1f km/h），全线被迫紧急停运！\n（您建设的轨道、车站、线路及所有存档均完整保留）", "Map: %s\nTwo trams collided (relative speed %.1f km/h)! Service halted.\n(All tracks, stations, lines & saves remain intact)") % [
			map_nm, spd_kmh
		]
	else:
		_lbl_gameover_title.text = L10n.t("【电车与小车碰撞 · 本局运营中止】", "[Tram-Vehicle Collision · Run Ended]")
		_lbl_gameover_detail.text = L10n.t("地图：%s\n电车以 %.1f km/h 与路面社会小车发生碰撞事故，本局运营立即终止！\n（您建设的轨道、车站、线路及所有存档均完整保留）", "Map: %s\nTram collided with street traffic at %.1f km/h! Run ended.\n(All tracks, stations, lines & saves remain intact)") % [
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
		_nav_bar.visible = true
		if DisplayServer.get_name() == "headless":
			_rebuild_tracks_and_operations(true)
			_set_game_mode(GameMode.RUN)
			_show_toast(L10n.t("已重新发车运营（您建设的轨道、车站与线路均已保留）", "Operations restarted (tracks, stations & lines preserved)"))
		else:
			_ops_dirty = true
			_async_restart_after_crash()


func _async_restart_after_crash() -> void:
	_begin_loading_overlay(L10n.t("正在重新发车", "Restarting Service"), L10n.t("正在重置轨道与运营状态...", "Resetting tracks & operations..."))
	await get_tree().process_frame
	_set_startup_progress(35.0, L10n.t("正在重置轨道与车站...", "Resetting tracks & stations..."))
	await get_tree().process_frame
	_rebuild_tracks_and_operations(true, true)
	_set_startup_progress(62.0, L10n.t("正在编组上线电车与街道交通...", "Spawning fleet & street traffic..."))
	await get_tree().process_frame
	_set_game_mode(GameMode.RUN)
	await _prewarm_city_and_gpu(_get_traffic_focus_pos(), true, 75.0, 99.0)
	_end_loading_overlay()
	_show_toast(L10n.t("已重新发车运营（您建设的轨道、车站与线路均已保留）", "Operations restarted (tracks, stations & lines preserved)"))


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


func _make_cat_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
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
			var prev_notches: Array[int] = []
			var prev_dirs: Array[int] = []
			var prev_change_t: Array[float] = []
			var win_changes: Array = []
			for ti in range(_transit_sim.trams.size()):
				prev_notches.append(int(_transit_sim.trams[ti]["notch"]))
				prev_dirs.append(0)
				prev_change_t.append(-10.0)
				win_changes.append([])
			var total_notch_changes := 0
			var rapid_reversals := 0
			var max_in_1s := 0
			for _step_k in range(1800):
				var step_dt := 0.033
				var sim_t := float(_step_k) * step_dt
				_pax_sim.step_simulation(step_dt, _graph)
				_traffic_sim.step_traffic(step_dt, _graph, _transit_sim.trams, _transit_sim.active_tram_idx, false, _get_traffic_focus_pos())
				var ev := _transit_sim.step_all_trams(step_dt, _graph, _pax_sim, _traffic_sim, _sound)
				for ti in range(mini(_transit_sim.trams.size(), prev_notches.size())):
					var cur_n := int(_transit_sim.trams[ti]["notch"])
					if cur_n != prev_notches[ti]:
						total_notch_changes += 1
						var d_n := 1 if cur_n > prev_notches[ti] else -1
						if prev_dirs[ti] != 0 and d_n != prev_dirs[ti] and (sim_t - prev_change_t[ti]) < 0.8:
							rapid_reversals += 1
						prev_dirs[ti] = d_n
						prev_change_t[ti] = sim_t
						prev_notches[ti] = cur_n
						var w: Array = win_changes[ti]
						w.append(sim_t)
						while not w.is_empty() and (sim_t - float(w[0])) > 1.0:
							w.remove_at(0)
						max_in_1s = maxi(max_in_1s, w.size())
				if not ev.is_empty():
					sim_accidents += 1
					print("UNEXPECTED ACCIDENT IN DEMO STRESS TEST: ", ev)
					break
			print("Stress test 60s completed: accidents = ", sim_accidents, ", boarded = ", _pax_sim.total_boarded, ", delivered = ", _pax_sim.total_delivered, ", notch_changes = ", total_notch_changes, ", rapid_reversals(<0.8s) = ", rapid_reversals, ", max_in_1s = ", max_in_1s)
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
