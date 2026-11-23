class_name TrafficSim
extends Node3D

const MAX_CARS := 40
const CAR_HALF_LEN := 2.22
const CAR_HALF_WID := 0.90
const CYCLE_SEC := 26.0
const STOP_LINE_DIST := 9.2

var cars: Array[Dictionary] = []
var signals: Dictionary = {} # node_id (int) -> {axis: Vector2, timer: float, state_code: int, heads_a: Array, heads_b: Array, tram_heads: Array}
# Big maps have thousands of signals: only tram-crossing signals (few) are stepped individually (transit signal
# priority); plain street signals run off one shared clock and only refresh their lamps near the camera.
var track_sig_ids: Array[int] = []
var _sim_clock := 0.0
var _near_sigs: Array[int] = []
var _sig_grid: Dictionary = {} # Vector2i (200m cell) -> Array[int] of non-track signal nids
var _pending_sig_builds: Array[int] = []
var _near_focus := Vector3(1e9, 0.0, 0.0)
var _near_age := 99.0
const SIG_NEAR_M := 320.0
const SIG_GRID_CELL := 200.0
var _sig_holder: Node3D = null
var _sig_frame_mat: StandardMaterial3D = null
static var _sig_box_cache: Dictionary = {}
static var _sig_disc_cache: Dictionary = {}
static var _sig_badge_mat: StandardMaterial3D = null
var _edge_ids: Array = []
var _edge_ids_age := 0.0
var _edge_xings_cache: Dictionary = {} # "eid|dir|lane" -> Array
var _bay_grid_ref: Array = []
var _bay_grid: Dictionary = {} # Vector2i (60m cell) -> Array[Dictionary]
var _tram_sec_cache: Array = [] # per-frame flat [pos2, fwd2, hl, hw, is_rear_lead, spd, tr_idx]
var _tsp_sig_cache_frame := -1
var _tsp_sig_cache: Dictionary = {} # tram_dict_id -> {"reach": float, "res": Dictionary}

var _car_meshes: Array[ArrayMesh] = []
var _veh_mat: ShaderMaterial
var _sig_pole_mat: StandardMaterial3D
var _sig_box_mat: StandardMaterial3D
var _mat_red_on: StandardMaterial3D
var _mat_yel_on: StandardMaterial3D
var _mat_grn_on: StandardMaterial3D
var _mat_tram_go: StandardMaterial3D
var _mat_tram_stop: StandardMaterial3D
var _mat_lamp_off: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_init_signal_materials()
	_build_shared_car_meshes()


func _init_signal_materials() -> void:
	_sig_pole_mat = StandardMaterial3D.new()
	_sig_pole_mat.albedo_color = Color(0.16, 0.18, 0.20)
	_sig_pole_mat.metallic = 0.62
	_sig_pole_mat.roughness = 0.38

	_sig_box_mat = StandardMaterial3D.new()
	_sig_box_mat.albedo_color = Color(0.09, 0.10, 0.12)
	_sig_box_mat.roughness = 0.55

	_mat_lamp_off = StandardMaterial3D.new()
	_mat_lamp_off.albedo_color = Color(0.14, 0.15, 0.16)
	_mat_lamp_off.roughness = 0.65

	_mat_red_on = _unshaded_glow(Color(1.0, 0.16, 0.12))
	_mat_yel_on = _unshaded_glow(Color(1.0, 0.76, 0.12))
	_mat_grn_on = _unshaded_glow(Color(0.16, 0.96, 0.46))
	_mat_tram_go = _unshaded_glow(Color(0.86, 0.98, 1.0))   # Lunar-white vertical transit bar '┃'
	_mat_tram_stop = _unshaded_glow(Color(1.0, 0.24, 0.12)) # High-vis red-orange horizontal bar '━'


static func _unshaded_glow(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.6
	return m


func rebuild_traffic(graph: NetworkGraph, focus_pos: Vector3) -> void:
	for c in get_children():
		c.queue_free()
	cars.clear()
	_rides_rails.clear()
	signals.clear()
	track_sig_ids.clear()
	_near_sigs.clear()

	if graph.edges.is_empty():
		return

	_build_intersection_signals(graph, focus_pos)

	var edge_ids := graph.edges.keys()
	var target_count := mini(MAX_CARS, maxi(14, edge_ids.size() / 7))

	for i in range(target_count):
		var eid := _pick_spawn_edge(graph, edge_ids, focus_pos, i < (target_count * 2) / 3)
		if eid < 0:
			continue
		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
		if elen < 26.0:
			continue

		var dir := 1.0 if (_rng.randf() < 0.5) else -1.0
		if not car_dir_allowed(graph, eid, dir):
			dir = -dir
		var lane_k := _rng.randi() % maxi(1, dir_lanes(graph, eid, dir))
		var s_init := lerpf(11.0, elen - 11.0, _rng.randf())
		var base_lane := _compute_dynamic_lane_offset(graph, eid, s_init, elen, dir, lane_k)

		var mi := MeshInstance3D.new()
		mi.mesh = _car_meshes[i % _car_meshes.size()]
		mi.material_override = _veh_mat
		mi.visibility_range_end = 260.0
		add_child(mi)

		var car_dict := {
			"node": mi,
			"edge_id": eid,
			"dir": dir,
			"s": s_init,
			"edge_len": elen,
			"speed": 7.2 + _rng.randf() * 2.8,
			"cruise_speed": 7.8 + _rng.randf() * 3.2,
			"lane_offset": base_lane,
			"lane_k": lane_k,
			"crashed": false,
			"pos": Vector3.ZERO,
			"fwd": Vector3.FORWARD,
			"turning": false,
			"turn_t": 0.0,
			"turn_len": 1.0,
			"turn_p0": Vector3.ZERO,
			"turn_p1": Vector3.ZERO,
			"turn_p2": Vector3.ZERO,
		}
		_update_car_transform(car_dict, graph)

		var overlap := false
		for other: Dictionary in cars:
			if (other["pos"] as Vector3).distance_squared_to(car_dict["pos"] as Vector3) < 72.0:
				overlap = true
				break
		if overlap:
			mi.queue_free()
			continue

		cars.append(car_dict)


func _build_intersection_signals(graph: NetworkGraph, focus_pos: Vector3 = Vector3.ZERO) -> void:
	var sig_holder := Node3D.new()
	sig_holder.name = "SignalizedIntersections"
	add_child(sig_holder)

	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.90, 0.92, 0.94)
	frame_mat.roughness = 0.42

	# Prioritize EVERY track intersection first (never skip track crossings!), then major 4-way non-track crossings spaced >= 72m apart!
	var ordered_nids: Array[int] = []
	for nid_raw in graph.nodes.keys():
		var nid := int(nid_raw)
		var nbs_chk: Array = graph.adj.get(nid, [])
		if nbs_chk.size() < 3:
			continue
		var node_has_track := false
		for x: Dictionary in nbs_chk:
			if _is_tram_edge(graph, int(x["edge_id"])):
				node_has_track = true
				break
		if not node_has_track:
			var near_station := false
			var np2: Vector2 = graph.nodes[nid]["pos"]
			for sid: int in graph.stations.keys():
				var sp3: Vector3 = graph.stations[sid]["pos"]
				if np2.distance_squared_to(Vector2(sp3.x, sp3.z)) < 12.5 * 12.5:
					near_station = true
					break
			if near_station:
				continue
		ordered_nids.append(nid)

	ordered_nids.sort_custom(func(a: int, b: int) -> bool:
		var na: Array = graph.adj.get(a, [])
		var nb_arr: Array = graph.adj.get(b, [])
		var ta := 0
		for x: Dictionary in na:
			if _is_tram_edge(graph, int(x["edge_id"])):
				ta += 1
		var tb := 0
		for x: Dictionary in nb_arr:
			if _is_tram_edge(graph, int(x["edge_id"])):
				tb += 1
		var score_a := ta * 10 + na.size()
		var score_b := tb * 10 + nb_arr.size()
		return score_a > score_b
	)

	var placed_grid := {} # 72 m cells -> placed signal positions (spacing checks without an O(n^2) scan)

	for nid: int in ordered_nids:
		var nbs: Array = graph.adj.get(nid, [])
		var np2: Vector2 = graph.nodes[nid]["pos"]

		# Determine Primary Axis (Phase A): align with built tram track if present, else main N-S street!
		var primary_axis := Vector2(0.0, 1.0)
		var has_track := false
		for nb: Dictionary in nbs:
			var eid := int(nb["edge_id"])
			if _is_tram_edge(graph, eid):
				primary_axis = _edge_outward_dir_2d(graph, eid, nid)
				has_track = true
				break

		# Track intersections ALWAYS get dedicated tram signals (only deduplicate within 14m); non-track intersections keep 72m spacing!
		var min_space := 14.0 if has_track else 72.0
		var too_close := false
		var gc := Vector2i(int(floor(np2.x / 72.0)), int(floor(np2.y / 72.0)))
		for gdx in range(-1, 2):
			for gdz in range(-1, 2):
				for pp: Vector2 in placed_grid.get(gc + Vector2i(gdx, gdz), []):
					if np2.distance_squared_to(pp) < min_space * min_space:
						too_close = true
						break
		if too_close:
			continue

		if not has_track:
			if nbs.size() < 4 and (nid % 3 != 0):
				continue
			var best_w := -1.0
			for nb: Dictionary in nbs:
				var eid := int(nb["edge_id"])
				var w := float(graph.edges[eid]["width"])
				if w > best_w:
					best_w = w
					primary_axis = _edge_outward_dir_2d(graph, eid, nid)

		if not placed_grid.has(gc):
			placed_grid[gc] = []
		(placed_grid[gc] as Array).append(np2)

		var init_t := fposmod(float((nid * 7) % 13) * 2.1, CYCLE_SEC)
		var max_w_sig := 10.0
		var max_trk_sep := 0.0
		for nb_s: Dictionary in nbs:
			var se_id := int(nb_s["edge_id"])
			max_w_sig = maxf(max_w_sig, float(graph.edges[se_id]["width"]))
			if _is_tram_edge(graph, se_id):
				if graph.is_quad(se_id):
					max_trk_sep = maxf(max_trk_sep, NetworkGraph.QUAD_ISLAND_LOCAL_SEP)
				elif graph.is_multi_track(se_id):
					max_trk_sep = maxf(max_trk_sep, maxf(graph.get_edge_track_half_sep(se_id), NetworkGraph.ISLAND_TRACK_HALF_SEP))
		var detect_r := maxf(6.2, max_trk_sep + 2.4)
		var stop_line_m := clampf(max_w_sig * 0.5 + 4.8, 10.6, 15.6)

		var sig_entry := {
			"node_id": nid,
			"root": null,
			"built": false,
			"pos2": graph.nodes[nid]["pos"],
			"axis": primary_axis,
			"has_track": has_track,
			"detect_r": detect_r,
			"stop_line": stop_line_m,
			"timer": init_t,
			"offset": init_t,
			"state_code": -1,
			"tsp_ext": 0.0,
			"tsp_active": false,
			"heads_a": [],
			"heads_b": [],
			"tram_heads": [],
		}
		signals[nid] = sig_entry
		if has_track:
			_ensure_signal_visuals(sig_entry, graph, sig_holder, frame_mat)
			_refresh_signal_visuals(sig_entry)
	_sig_holder = sig_holder
	_sig_frame_mat = frame_mat
	track_sig_ids.clear()
	_sig_grid.clear()
	_pending_sig_builds.clear()
	_edge_xings_cache.clear()
	_bay_grid.clear()
	_bay_grid_ref = []
	var f2_init := Vector2(focus_pos.x, focus_pos.z)
	_near_focus = focus_pos
	_near_age = 0.0
	for nid2: int in signals.keys():
		var s2: Dictionary = signals[nid2]
		var p2_s: Vector2 = s2["pos2"]
		if bool(s2["has_track"]):
			track_sig_ids.append(nid2)
			var tr_r: Node3D = s2.get("root")
			if is_instance_valid(tr_r):
				tr_r.visible = p2_s.distance_squared_to(f2_init) < 420.0 * 420.0
		else:
			var ck := Vector2i(int(floor(p2_s.x / SIG_GRID_CELL)), int(floor(p2_s.y / SIG_GRID_CELL)))
			if not _sig_grid.has(ck):
				_sig_grid[ck] = []
			(_sig_grid[ck] as Array).append(nid2)
			var in_range := p2_s.distance_squared_to(f2_init) < SIG_NEAR_M * SIG_NEAR_M
			if in_range:
				_ensure_signal_visuals(s2, graph, sig_holder, frame_mat)
				_refresh_signal_visuals(s2)
				_near_sigs.append(nid2)


# Pre-build nearby street signals & warm road/track-clearance caches during the loading overlay
# so the first frames of driving never stall on lazy signal construction or cold edge scans!
func prewarm_near(graph: NetworkGraph, focus_pos: Vector3, radius_m: float = 520.0) -> void:
	if graph == null:
		return
	if clear_idx_cache.is_empty() and graph.has_meta("track_clear_idx"):
		clear_idx_cache = graph.get_meta("track_clear_idx")
	var f2 := Vector2(focus_pos.x, focus_pos.z)
	_near_focus = focus_pos
	_pending_sig_builds.clear()
	for old_nid: int in _near_sigs:
		if signals.has(old_nid):
			var old_r: Node3D = (signals[old_nid] as Dictionary).get("root")
			if is_instance_valid(old_r):
				old_r.visible = false
	_near_sigs.clear()
	var gcx := int(floor(f2.x / SIG_GRID_CELL))
	var gcz := int(floor(f2.y / SIG_GRID_CELL))
	var gr := int(ceil(radius_m / SIG_GRID_CELL))
	var r2_build := radius_m * radius_m
	var r2_vis := SIG_NEAR_M * SIG_NEAR_M
	for gx in range(gcx - gr, gcx + gr + 1):
		for gz in range(gcz - gr, gcz + gr + 1):
			var cell_arr = _sig_grid.get(Vector2i(gx, gz))
			if cell_arr == null:
				continue
			for nid0: int in cell_arr:
				var s0: Dictionary = signals[nid0]
				var d2 := (s0["pos2"] as Vector2).distance_squared_to(f2)
				if d2 <= r2_build:
					if not bool(s0.get("built", false)):
						_ensure_signal_visuals(s0, graph, _sig_holder, _sig_frame_mat)
					s0["timer"] = fposmod(_sim_clock + float(s0["offset"]), CYCLE_SEC)
					s0["state_code"] = -1
					_refresh_signal_visuals(s0)
					var vis_now := d2 < r2_vis
					var sr: Node3D = s0.get("root")
					if is_instance_valid(sr):
						sr.visible = vis_now
					if vis_now:
						_near_sigs.append(nid0)
	var r2_trk := 420.0 * 420.0
	for tnid: int in track_sig_ids:
		if signals.has(tnid):
			var ts0: Dictionary = signals[tnid]
			var tr0: Node3D = ts0.get("root")
			if is_instance_valid(tr0):
				tr0.visible = (ts0["pos2"] as Vector2).distance_squared_to(f2) < r2_trk
	# Pre-populate _rides_rails & _bay_grid_cells for nearby street edges
	var bays: Array = graph.get_meta("station_bays", []) if graph.has_meta("station_bays") else []
	if not bays.is_empty():
		_get_nearby_bays(bays, focus_pos)
	for eid: int in _edge_ids:
		var ed: Dictionary = graph.edges[eid]
		var pts: Array = ed.get("pts", [])
		if pts.is_empty():
			continue
		if (pts[0] as Vector2).distance_squared_to(f2) <= r2_build:
			_edge_rides_rails(graph, eid)


func _ensure_signal_visuals(sig: Dictionary, graph: NetworkGraph, sig_holder: Node3D, frame_mat: Material) -> void:
	if bool(sig.get("built", false)) or not is_instance_valid(sig_holder):
		return
	sig["built"] = true
	var nid := int(sig["node_id"])
	var primary_axis: Vector2 = sig["axis"]
	var nbs: Array = graph.adj.get(nid, [])
	var heads_a: Array[Dictionary] = []
	var heads_b: Array[Dictionary] = []
	var tram_heads: Array[Dictionary] = []
	var int_root := Node3D.new()
	sig_holder.add_child(int_root)

	for nb: Dictionary in nbs:
		var eid := int(nb["edge_id"])
		var ed: Dictionary = graph.edges[eid]
		var edge_has_track := _is_tram_edge(graph, eid)
		var elen_sig := float(ed["length"])
		if elen_sig < (12.0 if edge_has_track else 22.0):
			continue
		var out_dir2 := _edge_outward_dir_2d(graph, eid, nid)
		var is_phase_a := (absf(out_dir2.dot(primary_axis)) >= 0.65)
		var app_fwd := Vector3(-out_dir2.x, 0.0, -out_dir2.y).normalized()
		var app_right := app_fwd.cross(Vector3.UP).normalized()
		var j_p2: Vector2 = graph.nodes[nid]["pos"]
		var j_pos3 := Vector3(j_p2.x, 0.0, j_p2.y)
		var road_hw := clampf(float(ed["width"]) * 0.5, 4.5, 13.5)
		var track_sep := graph.get_edge_track_half_sep(eid) if edge_has_track else 0.0
		var cross_hw := 5.5
		for nb_c: Dictionary in nbs:
			var ceid := int(nb_c["edge_id"])
			if ceid != eid:
				cross_hw = maxf(cross_hw, float(graph.edges[ceid]["width"]) * 0.5)
		var pull_back := clampf(cross_hw + 4.8, 9.5, minf(16.0, elen_sig * 0.44))
		var mast_lat := maxf(road_hw + 1.15, track_sep + 3.45)

		var pole_pos := j_pos3 - app_fwd * pull_back + app_right * mast_lat
		if _is_pole_clear_of_tracks(graph, Vector2(pole_pos.x, pole_pos.z)):
			var m_head := _spawn_motor_signal_mast(int_root, pole_pos, app_fwd, frame_mat)
			if is_phase_a:
				heads_a.append(m_head)
			else:
				heads_b.append(m_head)

		if edge_has_track:
			var tram_pb := clampf(cross_hw + 5.8, 10.2, minf(16.8, elen_sig * 0.46))
			var track_lat := track_sep + 1.92
			var chosen_pos := j_pos3 - app_fwd * tram_pb + app_right * track_lat
			var hit_t := graph.find_closest_edge(Vector2(chosen_pos.x, chosen_pos.z), 4.0, true)
			if not hit_t.is_empty() and int(hit_t["edge_id"]) != eid:
				chosen_pos = j_pos3 - app_fwd * minf(tram_pb + 2.8, elen_sig * 0.48) + app_right * track_lat
			if graph.has_meta("track_clear_idx"):
				var cidx: Dictionary = graph.get_meta("track_clear_idx")
				for _k in range(10):
					if TrackBuilder.track_clearance_dist(cidx, Vector2(chosen_pos.x, chosen_pos.z)) >= 1.8:
						break
					chosen_pos += app_right * 0.4
			var t_head := _spawn_dedicated_tram_signal(int_root, chosen_pos, app_fwd, is_phase_a, frame_mat)
			tram_heads.append(t_head)

	sig["root"] = int_root
	sig["heads_a"] = heads_a
	sig["heads_b"] = heads_b
	sig["tram_heads"] = tram_heads
	if Terrain.active:
		int_root.set_meta("on_terrain", true)


# Street-running tram track (monorail, elevated viaducts and underground tunnels do not interact with road traffic)
static func _is_tram_edge(graph: NetworkGraph, eid: int) -> bool:
	return graph.built_tracks.has(eid) and not TrackBuilder.is_monorail_style(int(graph.built_tracks[eid])) and not graph.is_edge_grade_separated(eid)


static func _ground_trams(trams: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in trams:
		if not bool(t.get("elevated", false)) and not bool(t.get("grade_sep", false)):
			out.append(t)
	return out


static func _is_pole_clear_of_tracks(graph: NetworkGraph, pt2: Vector2) -> bool:
	if graph.has_meta("track_clear_idx"):
		return TrackBuilder.track_clearance_dist(graph.get_meta("track_clear_idx"), pt2) >= 2.75
	var hit := graph.find_closest_edge(pt2, 8.5, true)
	if hit.is_empty():
		return true
	var eid := int(hit["edge_id"])
	var sep := graph.get_edge_track_half_sep(eid)
	# Require >= sep + 2.75m clearance from ANY built track centerline so turning trams never clip poles!
	return float(hit["dist"]) >= (sep + 2.75)


func _spawn_motor_signal_mast(parent: Node3D, pos: Vector3, app_fwd: Vector3, frame_mat: Material) -> Dictionary:
	var root := Node3D.new()
	# Face TOWARD the approaching driver (-app_fwd is +Z in Basis.looking_at(app_fwd))
	var placed := pos + (Vector3(0.0, Terrain.surface(pos.x, pos.z), 0.0) if Terrain.active else Vector3.ZERO)
	root.transform = Transform3D(Basis.looking_at(app_fwd, Vector3.UP), placed)
	parent.add_child(root)

	# Vertical steel mast + horizontal cantilever arm extending left over motor lane
	_sig_box(root, Vector3(0.16, 5.6, 0.16), Vector3(0.0, 2.8, 0.0), _sig_pole_mat, 230.0)
	_sig_box(root, Vector3(3.6, 0.11, 0.11), Vector3(-1.75, 5.45, 0.0), _sig_pole_mat, 230.0)

	# 3-aspect signal housing with high-contrast white reflective border backplate (+Z faces approaching driver)
	var hx := -2.65
	var hy := 5.15
	_sig_box(root, Vector3(0.44, 1.04, 0.04), Vector3(hx, hy, -0.02), frame_mat, 230.0)
	_sig_box(root, Vector3(0.38, 0.98, 0.22), Vector3(hx, hy, 0.0), _sig_box_mat, 230.0)

	var l_red := _sig_disc(root, 0.115, Vector3(hx, hy + 0.29, 0.12), _mat_red_on, 230.0)
	var l_yel := _sig_disc(root, 0.115, Vector3(hx, hy, 0.12), _mat_lamp_off, 230.0)
	var l_grn := _sig_disc(root, 0.115, Vector3(hx, hy - 0.29, 0.12), _mat_lamp_off, 230.0)

	return {
		"red": l_red,
		"yel": l_yel,
		"grn": l_grn,
	}


func _spawn_dedicated_tram_signal(parent: Node3D, pos: Vector3, app_fwd: Vector3, is_phase_a: bool, frame_mat: Material) -> Dictionary:
	var root := Node3D.new()
	var placed := pos + (Vector3(0.0, Terrain.surface(pos.x, pos.z), 0.0) if Terrain.active else Vector3.ZERO)
	root.transform = Transform3D(Basis.looking_at(app_fwd, Vector3.UP), placed)
	parent.add_child(root)

	# Slim Trackside Dedicated Tram Signal Post directly beside the rails at cab upper-windshield height (~3.10m)
	_sig_box(root, Vector3(0.09, 3.55, 0.09), Vector3(0.0, 1.77, 0.0), _sig_pole_mat, 225.0)
	var hy := 3.10
	if _sig_badge_mat == null:
		_sig_badge_mat = StandardMaterial3D.new()
		_sig_badge_mat.albedo_color = Color(0.08, 0.44, 0.78)
		_sig_badge_mat.roughness = 0.32
	_sig_box(root, Vector3(0.36, 0.13, 0.14), Vector3(0.0, hy + 0.54, 0.0), _sig_badge_mat, 225.0)
	_sig_box(root, Vector3(0.46, 0.96, 0.04), Vector3(0.0, hy, -0.02), frame_mat, 225.0)
	_sig_box(root, Vector3(0.40, 0.90, 0.20), Vector3(0.0, hy, 0.0), _sig_box_mat, 225.0)

	# Top: Horizontal Stop Bar '━━' | Middle: Amber Caution Dot '●' | Bottom: Vertical Proceed Bar '┃'
	var bar_stop := _sig_box(root, Vector3(0.28, 0.072, 0.04), Vector3(0.0, hy + 0.26, 0.105), _mat_tram_stop, 225.0)
	var dot_wait := _sig_disc(root, 0.082, Vector3(0.0, hy, 0.105), _mat_lamp_off, 225.0)
	var bar_go := _sig_box(root, Vector3(0.072, 0.28, 0.04), Vector3(0.0, hy - 0.26, 0.105), _mat_lamp_off, 225.0)

	return {
		"is_phase_a": is_phase_a,
		"stop_bar": bar_stop,
		"wait_dot": dot_wait,
		"go_bar": bar_go,
	}


static func _sig_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, vis_end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b: BoxMesh = _sig_box_cache.get(sz)
	if b == null:
		b = BoxMesh.new()
		b.size = sz
		_sig_box_cache[sz] = b
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = vis_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _sig_disc(parent: Node3D, r: float, pos: Vector3, mat: Material, vis_end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c: CylinderMesh = _sig_disc_cache.get(r)
	if c == null:
		c = CylinderMesh.new()
		c.top_radius = r; c.bottom_radius = r; c.height = 0.03; c.radial_segments = 12
		_sig_disc_cache[r] = c
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	mi.visibility_range_end = vis_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# Phase code: 0 = A_GREEN/B_RED, 1 = A_YELLOW/B_RED, 2 = A_RED/B_GREEN, 3 = A_RED/B_YELLOW
static func _phase_code_from_timer(t: float) -> int:
	if t < 15.0:
		return 0
	elif t < 17.5:
		return 1
	elif t < 23.8:
		return 2
	return 3


func _refresh_signal_visuals(sig: Dictionary) -> void:
	var code := _phase_code_from_timer(float(sig["timer"]))
	if code == int(sig["state_code"]):
		return
	sig["state_code"] = code

	# Phase A motor lights
	for h: Dictionary in sig["heads_a"]:
		(h["grn"] as MeshInstance3D).material_override = _mat_grn_on if code == 0 else _mat_lamp_off
		(h["yel"] as MeshInstance3D).material_override = _mat_yel_on if code == 1 else _mat_lamp_off
		(h["red"] as MeshInstance3D).material_override = _mat_red_on if code >= 2 else _mat_lamp_off

	# Phase B motor lights
	for h: Dictionary in sig["heads_b"]:
		(h["grn"] as MeshInstance3D).material_override = _mat_grn_on if code == 2 else _mat_lamp_off
		(h["yel"] as MeshInstance3D).material_override = _mat_yel_on if code == 3 else _mat_lamp_off
		(h["red"] as MeshInstance3D).material_override = _mat_red_on if code <= 1 else _mat_lamp_off

	# Dedicated Tram Bar Signals ('┃' Go, '●' Caution, '━' Stop)
	for th: Dictionary in sig["tram_heads"]:
		var is_a := bool(th["is_phase_a"])
		var go_now := (code == 0) if is_a else (code == 2)
		var yel_now := (code == 1) if is_a else (code == 3)
		var stop_now := (not go_now) and (not yel_now)
		(th["go_bar"] as MeshInstance3D).material_override = _mat_tram_go if go_now else _mat_lamp_off
		(th["wait_dot"] as MeshInstance3D).material_override = _mat_yel_on if yel_now else _mat_lamp_off
		(th["stop_bar"] as MeshInstance3D).material_override = _mat_tram_stop if stop_now else _mat_lamp_off


# Returns "green", "yellow", or "red" for any vehicle/tram approaching `node_id` along `approach_fwd_2d`!
func get_signal_aspect(node_id: int, approach_fwd_2d: Vector2) -> String:
	if not signals.has(node_id):
		return "green"
	var sig: Dictionary = signals[node_id]
	if not bool(sig["has_track"]):
		sig["timer"] = fposmod(_sim_clock + float(sig["offset"]), CYCLE_SEC)
	var axis: Vector2 = sig["axis"]
	var is_phase_a := (absf(approach_fwd_2d.normalized().dot(axis)) >= 0.65)
	var code := _phase_code_from_timer(float(sig["timer"]))
	if is_phase_a:
		if code == 0:
			return "green"
		elif code == 1:
			return "yellow"
		return "red"
	else:
		if code == 2:
			return "green"
		elif code == 3:
			return "yellow"
		return "red"


# Queries the nearest signalized intersection ahead of a tram's FRONT NOSE along its actual curve (works on curves & quad tracks!)
func get_upcoming_tram_signal(tr: Dictionary, graph: NetworkGraph, max_look: float = 190.0) -> Dictionary:
	var secs: Array = tr["tram_info"]["sections"]
	if secs.is_empty() or signals.is_empty() or bool(tr.get("elevated", false)) or bool(tr.get("grade_sep", false)):
		return {"has_signal": false, "aspect": "green", "dist": 999.0, "stop_line": 11.2, "is_phase_a": true, "tsp_active": false}

	var curve: Curve3D = tr.get("curve")
	var rlen := float(tr.get("route_len", 10.0))
	var is_loop := bool(tr.get("is_loop", false))
	var dir := float(tr.get("dir", 1.0))
	var sec_len := float(tr["tram_info"].get("section_len", 9.2))
	# Match TransitSim._position_tram_3d: front bumper sits sec_len * 0.16 ahead of lead bogie tr["s"]
	var nose_s := float(tr["s"]) + dir * (sec_len * 0.16)

	var cur_pf := Engine.get_process_frames()
	if int(tr.get("_sig_geo_f", -1)) == cur_pf and absf(float(tr.get("_sig_geo_s", -1e9)) - nose_s) < 0.01:
		var c_nid := int(tr.get("_sig_geo_nid", -1))
		if c_nid >= 0 and signals.has(c_nid):
			var c_d := float(tr["_sig_geo_d"])
			if c_d <= max_look:
				var sig_c: Dictionary = signals[c_nid]
				return {
					"has_signal": true,
					"node_id": c_nid,
					"aspect": get_signal_aspect(c_nid, tr["_sig_geo_app2"] as Vector2),
					"is_phase_a": bool(tr["_sig_geo_isa"]),
					"dist": c_d,
					"stop_line": float(tr["_sig_geo_sl"]),
					"tsp_active": bool(sig_c.get("tsp_active", false)),
				}
			return {"has_signal": false, "aspect": "green", "dist": 999.0, "stop_line": 11.2, "is_phase_a": true, "tsp_active": false}
		elif max_look <= float(tr.get("_sig_geo_max", 0.0)):
			return {"has_signal": false, "aspect": "green", "dist": 999.0, "stop_line": 11.2, "is_phase_a": true, "tsp_active": false}

	if curve != null and rlen > 5.0 and not track_sig_ids.is_empty():
		var s_nose := fposmod(nose_s, rlen) if is_loop else clampf(nose_s, 0.0, rlen)
		var p_nose3 := curve.sample_baked(s_nose, false)
		var p_nose2 := Vector2(p_nose3.x, p_nose3.z)
		var near_nids: Array[int] = []
		var broad_r2 := (max_look + 24.0) * (max_look + 24.0)
		for nid0: int in track_sig_ids:
			var sig0: Dictionary = signals[nid0]
			if (sig0["pos2"] as Vector2).distance_squared_to(p_nose2) <= broad_r2:
				near_nids.append(nid0)
		if near_nids.is_empty():
			return {"has_signal": false, "aspect": "green", "dist": 999.0, "stop_line": 11.2, "is_phase_a": true, "tsp_active": false}

		var look_d := 0.0
		while look_d <= max_look:
			var s_probe := nose_s + dir * look_d
			if is_loop:
				s_probe = fposmod(s_probe, rlen)
			elif s_probe < 0.0 or s_probe > rlen:
				break
			var p3 := curve.sample_baked(s_probe, false)
			var p2 := Vector2(p3.x, p3.z)
			var min_margin := 1e9
			var hit_nid := -1
			var hit_r := 6.2
			for nid: int in near_nids:
				var sig: Dictionary = signals[nid]
				var dr := float(sig.get("detect_r", 6.2))
				var dist_sig := (sig["pos2"] as Vector2).distance_to(p2)
				if dist_sig <= dr:
					hit_nid = nid
					hit_r = dr
					break
				var margin := dist_sig - dr
				if margin < min_margin:
					min_margin = margin
			if hit_nid >= 0:
				# Refine to the EXACT closest point of approach to sig["pos2"] so dist measures to junction center
				# (never prematurely underestimated by the detection circle radius!)
				var sig_h: Dictionary = signals[hit_nid]
				var sp2: Vector2 = sig_h["pos2"]
				var best_d := look_d
				var best_d2 := sp2.distance_squared_to(p2)
				var ref_lo := maxf(0.0, look_d - 2.5)
				var ref_hi := minf(max_look + hit_r + 4.0, look_d + hit_r * 2.0 + 4.0)
				var rd := ref_lo
				while rd <= ref_hi:
					var sr := nose_s + dir * rd
					if is_loop:
						sr = fposmod(sr, rlen)
					elif sr < 0.0 or sr > rlen:
						break
					var pr := curve.sample_baked(sr, false)
					var d2r := sp2.distance_squared_to(Vector2(pr.x, pr.z))
					if d2r < best_d2:
						best_d2 = d2r
						best_d = rd
					elif d2r > best_d2 + 12.0 and rd > best_d + 2.0:
						break
					rd += 0.75
				# Ignore if the closest point is behind/at our nose (we already passed the junction center)
				if best_d >= 2.0:
					var stop_line := float(sig_h.get("stop_line", 11.8))
					# Sample approach tangent strictly BEFORE the junction turn (at the stop line) so 90° turns
					# always read the approach street's phase rather than the cross street's phase!
					var s_app := nose_s + dir * (best_d - stop_line)
					if is_loop:
						s_app = fposmod(s_app, rlen)
					else:
						s_app = clampf(s_app, 0.0, rlen)
					var tf_p := TrackBuilder.sample_track_frame(curve, s_app, rlen, is_loop)
					var app_fwd := (-tf_p.basis.z) * dir
					var app2 := Vector2(app_fwd.x, app_fwd.z).normalized()
					var is_a := (absf(app2.dot(sig_h["axis"] as Vector2)) >= 0.65)
					tr["_sig_geo_f"] = cur_pf
					tr["_sig_geo_s"] = nose_s
					tr["_sig_geo_max"] = max_look
					tr["_sig_geo_nid"] = hit_nid
					tr["_sig_geo_d"] = best_d
					tr["_sig_geo_sl"] = stop_line
					tr["_sig_geo_app2"] = app2
					tr["_sig_geo_isa"] = is_a
					return {
						"has_signal": true,
						"node_id": hit_nid,
						"aspect": get_signal_aspect(hit_nid, app2),
						"is_phase_a": is_a,
						"dist": best_d,
						"stop_line": stop_line,
						"tsp_active": bool(sig_h.get("tsp_active", false)),
					}
				# Already past this node's center: skip past it and keep searching ahead
				look_d += maxf(3.0, hit_r)
				continue
			look_d += clampf(min_margin * 0.85, 1.8, 16.0)

	tr["_sig_geo_f"] = cur_pf
	tr["_sig_geo_s"] = nose_s
	tr["_sig_geo_max"] = max_look
	tr["_sig_geo_nid"] = -1
	return {"has_signal": false, "aspect": "green", "dist": 999.0, "stop_line": 11.2, "is_phase_a": true, "tsp_active": false}


# True if `tr` has a scheduled station stop between its current position and `dist_to_stop_line` metres ahead
static func _has_stop_before_dist(tr: Dictionary, dist_m: float) -> bool:
	if dist_m <= 4.0 or float(tr.get("depart_cooldown", 0.0)) > 0.0:
		return false
	var stops: Array = tr.get("stops", [])
	if stops.is_empty():
		return false
	var s_now := float(tr["s"])
	var dir := float(tr["dir"])
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	for st: Dictionary in stops:
		var st_off := float(st["offset"])
		var d := (st_off - s_now) * dir
		if is_loop:
			d = fposmod(d, rlen)
		if d > 3.5 and d < dist_m - 2.0:
			return true
	return false


func on_bell_rung(tram_pos: Vector3, tram_fwd: Vector3) -> void:
	# Ringing bell ('H') cautions nearby cars & requests immediate Transit Signal Priority ahead!
	var tf2 := Vector2(tram_fwd.x, tram_fwd.z).normalized()
	var tp2 := Vector2(tram_pos.x, tram_pos.z)
	for nid: int in track_sig_ids:
		var sig: Dictionary = signals[nid]
		if (sig["pos2"] as Vector2).distance_squared_to(tp2) > 55.0 * 55.0:
			continue
		# Advance red phase into yellow clearance if cross green has served >= 3.5s
		var t := float(sig["timer"])
		var is_a := (absf(tf2.dot(sig["axis"] as Vector2)) >= 0.65)
		if is_a and t >= 20.5 and t < 23.8:
			sig["timer"] = 23.8
			_refresh_signal_visuals(sig)
		elif (not is_a) and t >= 5.0 and t < 15.0:
			sig["timer"] = 15.0
			_refresh_signal_visuals(sig)
	for c: Dictionary in cars:
		if not bool(c["crashed"]) and (c["pos"] as Vector3).distance_squared_to(tram_pos) < 38.0 * 38.0:
			c["speed"] = minf(float(c["speed"]), 2.5)


func step_traffic(
	dt: float,
	graph: NetworkGraph,
	trams: Array[Dictionary],
	_active_tram_idx: int,
	_manual_drive: bool,
	focus_pos: Vector3
) -> void:
	trams = _ground_trams(trams)
	_sim_clock += dt
	# 1a. Plain street signals: spatial-grid lookup + 1/frame budgeted lazy build (never spikes on 40m moves!)
	if _near_focus.distance_squared_to(focus_pos) > 40.0 * 40.0:
		_near_focus = focus_pos
		for old_nid: int in _near_sigs:
			if signals.has(old_nid):
				var old_r: Node3D = (signals[old_nid] as Dictionary).get("root")
				if is_instance_valid(old_r):
					old_r.visible = false
		_near_sigs.clear()
		_pending_sig_builds.clear()
		var f2 := Vector2(focus_pos.x, focus_pos.z)
		var gcx := int(floor(f2.x / SIG_GRID_CELL))
		var gcz := int(floor(f2.y / SIG_GRID_CELL))
		var gr := int(ceil(SIG_NEAR_M / SIG_GRID_CELL))
		var r2_sig := SIG_NEAR_M * SIG_NEAR_M
		for gx in range(gcx - gr, gcx + gr + 1):
			for gz in range(gcz - gr, gcz + gr + 1):
				var cell_arr = _sig_grid.get(Vector2i(gx, gz))
				if cell_arr == null:
					continue
				for nid0: int in cell_arr:
					var s0: Dictionary = signals[nid0]
					if (s0["pos2"] as Vector2).distance_squared_to(f2) < r2_sig:
						if bool(s0.get("built", false)):
							_near_sigs.append(nid0)
							var new_r: Node3D = s0.get("root")
							if is_instance_valid(new_r):
								new_r.visible = true
						else:
							_pending_sig_builds.append(nid0)
		# Also cull distant track-signal visuals (> 420m from camera) while keeping their phase timers running!
		var r2_trk := 420.0 * 420.0
		for tnid: int in track_sig_ids:
			if signals.has(tnid):
				var ts0: Dictionary = signals[tnid]
				var tr0: Node3D = ts0.get("root")
				if is_instance_valid(tr0):
					var want_v := (ts0["pos2"] as Vector2).distance_squared_to(f2) < r2_trk
					if tr0.visible != want_v:
						tr0.visible = want_v
						if want_v:
							ts0["state_code"] = -1
	# Build at most 1 queued street signal intersection per frame for rock-solid frame pacing
	if not _pending_sig_builds.is_empty():
		var build_nid: int = _pending_sig_builds.pop_back()
		if signals.has(build_nid):
			var sb: Dictionary = signals[build_nid]
			if not bool(sb.get("built", false)):
				_ensure_signal_visuals(sb, graph, _sig_holder, _sig_frame_mat)
			sb["timer"] = fposmod(_sim_clock + float(sb["offset"]), CYCLE_SEC)
			sb["state_code"] = -1
			_refresh_signal_visuals(sb)
			var br: Node3D = sb.get("root")
			if is_instance_valid(br):
				br.visible = true
			_near_sigs.append(build_nid)
	for nid1: int in _near_sigs:
		if signals.has(nid1):
			var s1: Dictionary = signals[nid1]
			s1["timer"] = fposmod(_sim_clock + float(s1["offset"]), CYCLE_SEC)
			_refresh_signal_visuals(s1)
	# 1b. Tram-crossing signals + configurable Transit Signal Priority (per-line or global)
	var tsp_reqs := {} # nid -> {"is_a": bool, "dist": float}
	if not trams.is_empty() and not track_sig_ids.is_empty():
		for tr: Dictionary in trams:
			if bool(tr.get("crashed", false)) or bool(tr.get("derailed", false)) or bool(tr.get("held_manual", false)):
				continue
			if not graph.is_line_signal_priority(int(tr.get("line_id", -1))):
				continue
			if bool(tr.get("doors_target_open", false)) or float(tr.get("door_ratio", 0.0)) > 0.05 or float(tr.get("ai_open_delay", 0.0)) > 0.0 or str(tr.get("term_stage", "")) != "":
				continue
			var spd_t := float(tr.get("speed_mps", 0.0))
			var reach := clampf(maxf(54.0, spd_t * 5.8 + 20.0), 54.0, 125.0)
			var s_inf := get_upcoming_tram_signal(tr, graph, reach)
			if not bool(s_inf["has_signal"]):
				continue
			var sd_t := float(s_inf["dist"])
			var sl_t := float(s_inf.get("stop_line", 11.8))
			if sd_t < sl_t - 2.0:
				continue
			if _has_stop_before_dist(tr, sd_t - sl_t):
				continue
			var req_nid := int(s_inf["node_id"])
			var req_a := bool(s_inf.get("is_phase_a", true))
			if not tsp_reqs.has(req_nid):
				tsp_reqs[req_nid] = {"is_a": req_a, "dist": sd_t}
			else:
				var prev_r: Dictionary = tsp_reqs[req_nid]
				var cur_code := _phase_code_from_timer(float((signals[req_nid] as Dictionary)["timer"]))
				var prev_green := (bool(prev_r["is_a"]) and cur_code == 0) or ((not bool(prev_r["is_a"])) and cur_code == 2)
				var new_green := (req_a and cur_code == 0) or ((not req_a) and cur_code == 2)
				if (new_green and not prev_green) or (new_green == prev_green and sd_t < float(prev_r["dist"])):
					tsp_reqs[req_nid] = {"is_a": req_a, "dist": sd_t}

	for nid: int in track_sig_ids:
		if not signals.has(nid):
			continue
		var sig: Dictionary = signals[nid]
		var prev_code := _phase_code_from_timer(float(sig["timer"]))
		var t := fposmod(float(sig["timer"]) + dt, CYCLE_SEC)
		sig["tsp_active"] = false

		if tsp_reqs.has(nid):
			var req: Dictionary = tsp_reqs[nid]
			var req_a := bool(req["is_a"])
			var jp2: Vector2 = sig["pos2"]
			var car_crossing := false
			for cc: Dictionary in cars:
				if int(cc.get("xcommit_nid", -1)) == nid:
					car_crossing = true
					break
				var cp: Vector3 = cc["pos"]
				if Vector2(cp.x - jp2.x, cp.z - jp2.y).length_squared() < 11.5 * 11.5 and float(cc.get("speed", 0.0)) > 0.35:
					car_crossing = true
					break
			var ext_so_far := float(sig.get("tsp_ext", 0.0))
			if req_a:
				if t < 15.0:
					sig["tsp_active"] = true
					# Green extension: hold Phase A green while priority tram approaches (up to 18s max)
					if t >= 11.5 and ext_so_far < 18.0:
						t = 11.5
						sig["tsp_ext"] = ext_so_far + dt
				elif t >= 19.0 and t < 23.8 and not car_crossing:
					# Safe early green: jump cross street into full 2.2s yellow clearance -> Phase A green!
					t = 23.8
					sig["tsp_active"] = true
				elif t >= 23.8:
					sig["tsp_active"] = true
			else:
				if t >= 17.5 and t < 23.8:
					sig["tsp_active"] = true
					# Green extension: hold Phase B green while priority tram approaches (up to 18s max)
					if t >= 20.5 and ext_so_far < 18.0:
						t = 20.5
						sig["tsp_ext"] = ext_so_far + dt
				elif t >= 2.0 and t < 15.0 and not car_crossing:
					# Safe early green: jump cross street into full 2.5s yellow clearance -> Phase B green!
					t = 15.0
					sig["tsp_active"] = true
				elif t >= 15.0 and t < 17.5:
					sig["tsp_active"] = true

		var next_code := _phase_code_from_timer(t)
		if next_code != prev_code:
			sig["tsp_ext"] = 0.0
		sig["timer"] = t
		_refresh_signal_visuals(sig)

	if cars.is_empty() or graph.edges.is_empty():
		return

	# Edge id list for respawns: rebuilt when the street graph changes size, else once a second (not every frame)
	_edge_ids_age += dt
	if graph.edges.size() != _edge_ids.size() or _edge_ids_age > 1.0:
		_edge_ids = graph.edges.keys()
		_edge_ids_age = 0.0
	var edge_ids := _edge_ids
	clear_idx_cache = graph.get_meta("track_clear_idx") if graph.has_meta("track_clear_idx") else {}
	# Cars only exist within ~460m of focus_pos: filter trams_c to trams within 620m so 30+ trams stay O(1)!
	var trams_near_cars: Array[Dictionary] = []
	var f2_c := Vector2(focus_pos.x, focus_pos.z)
	for tr_nc: Dictionary in trams:
		var secs_nc: Array = tr_nc["tram_info"]["sections"]
		if secs_nc.is_empty() or not is_instance_valid(secs_nc[0]):
			continue
		var gp_nc := (secs_nc[0] as Node3D).global_position
		if Vector2(gp_nc.x - f2_c.x, gp_nc.z - f2_c.y).length_squared() <= 620.0 * 620.0:
			trams_near_cars.append(tr_nc)
	_precompute_tram_threat_paths(trams_near_cars)
	_tram_sec_cache.clear()
	for tr_sc: Dictionary in trams_near_cars:
		var tinfo_sc: Dictionary = tr_sc["tram_info"]
		var secs_sc: Array = tinfo_sc["sections"]
		var shl_sc := float(tinfo_sc.get("section_len", 9.2)) * 0.5
		var shw_sc := float(tinfo_sc.get("width", 2.6)) * 0.5
		var is_rear_sc := (int(tinfo_sc.get("active_end", 0)) == 1)
		var spd_sc := float(tr_sc.get("speed_mps", 0.0))
		for sec_sc: Node3D in secs_sc:
			if not is_instance_valid(sec_sc):
				continue
			var gp_sc := sec_sc.global_position
			var f3_sc := -sec_sc.global_transform.basis.z
			var f2_sc := Vector2(f3_sc.x, f3_sc.z)
			if f2_sc.length_squared() > 1e-6:
				f2_sc = f2_sc.normalized()
			else:
				f2_sc = Vector2(0.0, -1.0)
			_tram_sec_cache.append([Vector2(gp_sc.x, gp_sc.z), f2_sc, shl_sc, shw_sc, is_rear_sc, spd_sc])
	var trams_c_all := trams_near_cars

	# 2. Step all Street Cars with Strict Signal Obedience & Full-Consist Tram Avoidance!
	for idx in range(cars.size()):
		var c: Dictionary = cars[idx]
		if bool(c["crashed"]):
			continue

		if bool(c.get("force_respawn", false)):
			c.erase("force_respawn")
			_respawn_car_near(c, graph, edge_ids, focus_pos, trams, true)
			continue

		if (c["pos"] as Vector3).distance_squared_to(focus_pos) > 460.0 * 460.0:
			_respawn_car_near(c, graph, edge_ids, focus_pos, trams)
			continue

		var eid := int(c["edge_id"])
		if not graph.edges.has(eid):
			_respawn_car_near(c, graph, edge_ids, focus_pos, trams, true)
			continue
		if _is_transit_mall_double_track(graph, eid) or (not bool(c.get("turning", false)) and _edge_rides_rails(graph, eid)):
			_respawn_car_near(c, graph, edge_ids, focus_pos, trams, true)
			continue
		if not car_dir_allowed(graph, eid, float(c["dir"])):
			# Wrong-way on a one-way street (including aborted dead-end U-turn): relocate cleanly
			_respawn_car_near(c, graph, edge_ids, focus_pos, trams, true)
			if not car_dir_allowed(graph, int(c["edge_id"]), float(c["dir"])):
				c["dir"] = -float(c["dir"])
			continue

		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
		# A bridge street without tracks of its own passes over (or under) the tram lines: no conflict with trams
		var grade_sep := (bool(ed.get("bridge", false)) and not _is_tram_edge(graph, eid)) or (bool(c.get("turning", false)) and bool(c.get("grade_sep", false)))
		c["grade_sep"] = grade_sep
		var trams_c: Array[Dictionary] = _no_trams if grade_sep else trams_c_all
		var dir := float(c["dir"])
		var s_now := float(c["s"])
		var dist_to_end := (elen - s_now) if dir > 0.0 else s_now
		var next_nid := int(ed["b"]) if dir > 0.0 else int(ed["a"])

		var target_spd := float(c["cruise_speed"])
		if dist_to_end < 14.0:
			target_spd = minf(target_spd, 6.2)

		var c_pos: Vector3 = c["pos"]
		var c_fwd: Vector3 = c["fwd"]
		var c_right := c_fwd.cross(Vector3.UP).normalized()

		# (A) Car-to-Car safe following distance
		for j in range(cars.size()):
			if j == idx:
				continue
			var oth: Dictionary = cars[j]
			var dv := (oth["pos"] as Vector3) - c_pos
			var d2 := dv.length_squared()
			if d2 < 196.0 and d2 > 0.05:
				var along := dv.dot(c_fwd)
				var lat := absf(dv.dot(c_right))
				if along > 0.4 and lat < 2.1:
					if along < 7.4:
						target_spd = 0.0
					elif along < 14.0:
						target_spd = minf(target_spd, float(oth["speed"]) * 0.78)

		# (B) Strict Motor Traffic Light Obedience WELL BEHIND Crosswalk & Tram Tracks!
		var stop_line_d := _intersection_stop_line(graph, next_nid, eid)
		# (B0) Moves that cross tram tracks: decided at the stop line, never inside the junction. While a tram signal
		# here shows go / caution (or turns to go within 4 s), or a tram is in the box / heading for the crossing
		# point, the car takes another move that keeps off the rails, or waits behind the stop line.
		if dist_to_end <= stop_line_d + 40.0:
			var pl := _plan_move(c, graph, eid, next_nid)
			var xing = _plan_track_crossing(c, graph, pl)
			if xing != null and dist_to_end > stop_line_d - 1.5:
				var ok := not _tram_threat_at(trams_c, xing, 11.0)
				if ok and signals.has(next_nid) and bool(signals[next_nid]["has_track"]):
					var ths := _tram_heads_state(signals[next_nid])
					if bool(ths["active"]) or float(ths["t_go"]) < 4.0:
						ok = false
						# a long wait with no tram anywhere near (tracks on both axes keep some tram head lit)
						var jp_w: Vector2 = graph.nodes[next_nid]["pos"]
						if float(c.get("xwait", 0.0)) > 20.0 and not _any_tram_within(trams_c, Vector3(jp_w.x, 0.0, jp_w.y), 150.0):
							ok = true
				if ok and pl.has("exit_pts"):
					# don't block the box: only across the rails with room to clear them on the far side
					for ex: Vector3 in pl["exit_pts"]:
						for oc: Dictionary in cars:
							if oc != c and Vector2((oc["pos"] as Vector3).x - ex.x, (oc["pos"] as Vector3).z - ex.z).length() < 5.5:
								ok = false
								break
						if not ok:
							break
				if not ok:
					# another way through that stays off the rails?
					if dist_to_end > stop_line_d - 0.5 and not bool(pl.get("rerouted", false)):
						pl["rerouted"] = true
						var alts := _move_candidates(graph, eid, next_nid)
						alts.shuffle()
						for alt: Dictionary in alts:
							if int(alt["eid"]) == int(pl["eid"]):
								continue
							var pl2 := _make_plan(graph, eid, dir, next_nid, alt)
							pl2["rerouted"] = true
							c["plan"] = pl2
							if _plan_track_crossing(c, graph, pl2) == null:
								pl = pl2
								xing = null
								break
							c["plan"] = pl
					if xing != null:
						if dist_to_end <= stop_line_d + 1.8:
							target_spd = 0.0
							c["xwait"] = float(c.get("xwait", 0.0)) + dt
						else:
							target_spd = minf(target_spd, maxf(1.0, (dist_to_end - stop_line_d) * 0.50))
				elif dist_to_end <= stop_line_d + 0.6:
					c["xcommit_nid"] = next_nid # past the stop line with the crossing clear: drives through
					c["xwait"] = 0.0
		if dist_to_end >= stop_line_d - 1.4 and dist_to_end <= stop_line_d + 16.0 and signals.has(next_nid):
			var app2 := Vector2(c_fwd.x, c_fwd.z)
			var aspect := get_signal_aspect(next_nid, app2)
			if aspect != "green":
				# Stop cleanly well behind crosswalk & double-track clearance zone!
				if dist_to_end <= stop_line_d + 1.8:
					target_spd = 0.0
				else:
					target_spd = minf(target_spd, maxf(1.0, (dist_to_end - stop_line_d) * 0.50))
			else:
				# Even on Green, "Don't Block the Box": never enter intersection if a tram is currently occupying the box!
				var jp2_box: Vector2 = graph.nodes[next_nid]["pos"]
				var jp3_box := Vector3(jp2_box.x, 0.0, jp2_box.y)
				if _is_any_tram_occupying_point(trams_c, jp3_box, 14.5):
					if dist_to_end <= stop_line_d + 2.2:
						target_spd = 0.0

		# (C) Full-Consist & Crossing Tram Hard Protection (handles BOTH Front Cab & Rear Cab active_end == 1!)
		var emerg_stop := false
		var lat_guard := 4.85 if dist_to_end < 20.0 else 4.15
		# A car already standing on the rails of a level crossing never waits there: it drives on and clears the track
		# (only a tram right in front of its bonnet stops it)
		var on_crossing := false
		if clear_idx_cache.is_empty() and graph.has_meta("track_clear_idx"):
			clear_idx_cache = graph.get_meta("track_clear_idx")
		if not clear_idx_cache.is_empty() and (not _is_tram_edge(graph, eid) or bool(c.get("turning", false))):
			# (also mid-turn onto / off a tram street: a car that is on the rails drives on and clears them)
			on_crossing = TrackBuilder.track_clearance_dist(clear_idx_cache, Vector2(c_pos.x, c_pos.z)) < 3.4
		# (B1) Level crossings along the street itself (tracks crossing it away from a junction): stop 4 m short of
		# the rails while a tram is near or its route reaches the crossing within ~10 s
		if not on_crossing and not bool(c.get("turning", false)) and not _is_tram_edge(graph, eid) and not trams_c.is_empty():
			for xr: Array in _edge_xings(c, graph, eid, dir, elen):
				var xs := float(xr[0])
				var ahead := (xs - s_now) * dir
				if ahead <= 0.0 or ahead > 34.0:
					continue
				var xs_fr := _edge_frame(graph, eid, xs, elen, dir)
				var xpt := (xs_fr[0] as Vector3) + (xs_fr[1] as Vector3).cross(Vector3.UP).normalized() * float(c["lane_offset"])
				var hold := _tram_threat_at(trams_c, Vector3(xpt.x, 0.0, xpt.z), 11.0)
				if not hold:
					# room to clear the rails on the far side? (never queue on a level crossing)
					var s_out := clampf(float(xr[1]) + dir * (CAR_HALF_LEN + 3.5), 0.0, elen)
					var out_fr := _edge_frame(graph, eid, s_out, elen, dir)
					var opt := (out_fr[0] as Vector3) + (out_fr[1] as Vector3).cross(Vector3.UP).normalized() * float(c["lane_offset"])
					for oc: Dictionary in cars:
						if oc != c and Vector2((oc["pos"] as Vector3).x - opt.x, (oc["pos"] as Vector3).z - opt.z).length() < 5.0:
							hold = true
							break
				if hold:
					var room := ahead - (CAR_HALF_LEN + 4.0)
					target_spd = 0.0 if room <= 0.6 else minf(target_spd, room * 0.5)
				break
		if not trams_c.is_empty():
			var cp2_c := Vector2(c_pos.x, c_pos.z)
			var cf2_c := Vector2(c_fwd.x, c_fwd.z)
			var cr2_c := Vector2(c_right.x, c_right.z)
			for se: Array in _tram_sec_cache:
				var dv2_t: Vector2 = (se[0] as Vector2) - cp2_c
				var d2_t := dv2_t.length_squared()
				if d2_t > 1225.0:
					continue
				var along_t := dv2_t.dot(cf2_c)
				var lat_signed_t := dv2_t.dot(cr2_c)
				var lat_t := absf(lat_signed_t)
				if on_crossing:
					if along_t > -0.5 and along_t < 5.5 and lat_t < 2.4:
						target_spd = 0.0
						emerg_stop = true
						break
					continue
				# 1. Any tram section in forward corridor (including close nose range -1.5..24m)
				if along_t > -1.5 and along_t < 24.0 and lat_t < lat_guard:
					target_spd = 0.0
					emerg_stop = true
					break
				# 2. Moving tram crossing perpendicularly toward car's path ahead (using TRUE travel direction!)
				var tr_spd := float(se[5])
				var sec_fwd2: Vector2 = -(se[1] as Vector2) if bool(se[4]) else (se[1] as Vector2)
				var cross_dot := sec_fwd2.dot(cr2_c)
				if tr_spd > 0.3 and along_t > -1.5 and along_t < 28.0 and lat_t < 18.0 and absf(cross_dot) > 0.30 and (lat_signed_t * cross_dot) < 0.0:
					target_spd = 0.0
					emerg_stop = true
					break

		# (D) Never enter an intersection box if ANY tram is within 30m of that intersection!
		var committed := int(c.get("xcommit_nid", -1)) == next_nid and dist_to_end < stop_line_d
		if dist_to_end >= stop_line_d - 3.2 and dist_to_end <= stop_line_d + 6.5 and not committed and not on_crossing:
			var np2_chk: Vector2 = graph.nodes[next_nid]["pos"]
			if _is_any_tram_occupying_point(trams_c, Vector3(np2_chk.x, 0.0, np2_chk.y), 30.0):
				target_spd = 0.0
				emerg_stop = true

		var cur_spd := float(c["speed"])
		var acc_rate := 32.0 if emerg_stop else (9.5 if target_spd < cur_spd else 3.2)
		cur_spd = move_toward(cur_spd, target_spd, acc_rate * dt)
		if emerg_stop:
			cur_spd = 0.0
		c["speed"] = cur_spd

		# Anti-gridlock recovery: if a car stays deadlocked (especially near a tram or longer than a full signal cycle),
		# cleanly relocate it to an open street so road gridlock can never freeze a tram route!
		var stuck_t := (float(c.get("stuck_t", 0.0)) + dt) if cur_spd < 0.25 else 0.0
		c["stuck_t"] = stuck_t
		if stuck_t >= 48.0 or (stuck_t >= 20.0 and _is_any_tram_occupying_point(trams_c, c_pos, 42.0)):
			_respawn_car_near(c, graph, edge_ids, focus_pos, trams, true)
			continue

		# Smooth Quadratic Bezier corner turn between edges (STRICTLY obeys emerg_stop & cur_spd == 0!)
		if bool(c.get("turning", false)):
			if emerg_stop or cur_spd <= 0.05:
				c["speed"] = 0.0
				continue
			var t_len := maxf(2.0, float(c.get("turn_len", 8.0)))
			var t_step := (cur_spd * dt) / t_len
			var t_next := float(c.get("turn_t", 0.0)) + t_step
			var p0: Vector3 = c["turn_p0"]
			var p1: Vector3 = c["turn_p1"]
			var p2: Vector3 = c["turn_p2"]
			var u := clampf(t_next, 0.0, 1.0)
			var omt := 1.0 - u
			var b_pos := (omt * omt) * p0 + (2.0 * omt * u) * p1 + (u * u) * p2
			var b_tan := (2.0 * omt) * (p1 - p0) + (2.0 * u) * (p2 - p1)
			b_tan.y = 0.0
			var b_fwd := b_tan.normalized() if b_tan.length_squared() > 0.001 else c_fwd
			if not _would_car_invade_tram_shield(b_pos, b_fwd, trams_c, 1.85) and not _rail_entry_blocked(c, c_pos, c_fwd, b_pos, b_fwd, trams_c, graph):
				c["turn_t"] = t_next
				c["pos"] = b_pos
				c["fwd"] = b_fwd
				var mi_t: MeshInstance3D = c["node"]
				if is_instance_valid(mi_t):
					mi_t.global_transform = Transform3D(Basis.looking_at(b_fwd, Vector3.UP), b_pos)
				if t_next >= 1.0:
					c["turning"] = false
			else:
				c["speed"] = 0.0
			continue

		# Smoothly shift lane outward around side station platforms (Item 4) without sudden lateral jumps!
		var desired_lane := _compute_dynamic_lane_offset(graph, eid, s_now, elen, dir, int(c.get("lane_k", 0)))
		c["lane_offset"] = move_toward(float(c["lane_offset"]), desired_lane, dt * 3.4)

		var s_next := s_now + dir * cur_spd * dt
		if (dir > 0.0 and s_next >= elen - 5.5) or (dir < 0.0 and s_next <= 5.5):
			var np2_adv: Vector2 = graph.nodes[next_nid]["pos"]
			if _is_any_tram_occupying_point(trams_c, Vector3(np2_adv.x, 0.0, np2_adv.y), 28.0) and not committed and not on_crossing:
				c["speed"] = 0.0
			else:
				_advance_car_to_next_edge(c, graph, next_nid, eid)
		else:
			# Hard invariant: never move a car into any tram's OBB + 1.85m safety shield!
			var fr_c := _edge_frame(graph, eid, s_next, elen, dir)
			var fwd_c: Vector3 = fr_c[1]
			var right_c := fwd_c.cross(Vector3.UP).normalized()
			var cand_pos := (fr_c[0] as Vector3) + right_c * float(c["lane_offset"])
			if _would_car_invade_tram_shield(cand_pos, fwd_c, trams_c, 1.85):
				c["speed"] = 0.0
			elif _rail_entry_blocked(c, c_pos, c_fwd, cand_pos, fwd_c, trams_c, graph):
				c["speed"] = 0.0
			else:
				c["s"] = s_next

		if not bool(c.get("turning", false)):
			_update_car_transform(c, graph)

	# Visual pass: the mesh follows the simulated pose with a short critically-damped lag, so any
	# residual discontinuity (edge hand-over, lane re-plan) is spread over a few frames instead of popping.
	var k := 1.0 - exp(-dt * 14.0)
	for c2: Dictionary in cars:
		var mi2: MeshInstance3D = c2["node"]
		if not is_instance_valid(mi2):
			continue
		var tp: Vector3 = c2["pos"]
		var tf_: Vector3 = c2["fwd"]
		if not c2.has("vis_pos") or (c2["vis_pos"] as Vector3).distance_to(tp) > 12.0:
			c2["vis_pos"] = tp
			c2["vis_fwd"] = tf_
		else:
			var max_step := float(c2["speed"]) * dt * 1.6 + 0.02
			var vp: Vector3 = c2["vis_pos"]
			var nxt := vp.lerp(tp, k)
			if vp.distance_to(nxt) > max_step and vp.distance_to(tp) < 3.0:
				nxt = vp.move_toward(tp, max_step)
			c2["vis_pos"] = nxt
			var vf := (c2["vis_fwd"] as Vector3).lerp(tf_, k)
			c2["vis_fwd"] = vf.normalized() if vf.length_squared() > 1e-4 else tf_
		# Shown on the real ground (the traffic simulation itself runs on the flat street plan), pitched to the slope
		var vp2: Vector3 = c2["vis_pos"]
		var vf2: Vector3 = c2["vis_fwd"]
		var gy := Terrain.surface(vp2.x, vp2.z)
		var look := vf2
		if Terrain.active:
			var dh := Terrain.surface(vp2.x + vf2.x * 2.0, vp2.z + vf2.z * 2.0) - Terrain.surface(vp2.x - vf2.x * 2.0, vp2.z - vf2.z * 2.0)
			look = (Vector3(vf2.x, 0.0, vf2.z).normalized() * 4.0 + Vector3(0.0, dh, 0.0)).normalized()
		mi2.global_transform = Transform3D(Basis.looking_at(look, Vector3.UP), vp2 + Vector3(0.0, gy, 0.0))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _would_car_invade_tram_shield(car_pos: Vector3, car_fwd: Vector3, trams: Array[Dictionary], pad: float) -> bool:
	if trams.is_empty():
		return false
	var c2 := Vector2(car_pos.x, car_pos.z)
	var cf2 := Vector2(car_fwd.x, car_fwd.z).normalized()
	if not _tram_sec_cache.is_empty():
		for se: Array in _tram_sec_cache:
			var sp2: Vector2 = se[0]
			if sp2.distance_squared_to(c2) > 120.0:
				continue
			if obb_overlap_2d(sp2, se[1] as Vector2, float(se[2]) + pad, float(se[3]) + pad, c2, cf2, CAR_HALF_LEN + 0.25, CAR_HALF_WID + 0.20):
				return true
		return false
	for tr: Dictionary in trams:
		var tinfo: Dictionary = tr["tram_info"]
		var secs: Array = tinfo["sections"]
		var sec_hl := float(tinfo.get("section_len", 9.2)) * 0.5 + pad
		var sec_hw := float(tinfo.get("width", 2.6)) * 0.5 + pad
		for sec: Node3D in secs:
			if not is_instance_valid(sec):
				continue
			var spos := _flat(sec.global_position)
			if spos.distance_squared_to(_flat(car_pos)) > 120.0:
				continue
			var sfwd := -sec.global_transform.basis.z
			if obb_overlap_2d(Vector2(spos.x, spos.z), Vector2(sfwd.x, sfwd.z).normalized(), sec_hl, sec_hw, c2, cf2, CAR_HALF_LEN + 0.25, CAR_HALF_WID + 0.20):
				return true
	return false


static func _is_any_tram_occupying_point(trams: Array[Dictionary], pt: Vector3, radius: float) -> bool:
	var r2 := radius * radius
	for tr: Dictionary in trams:
		var secs: Array = tr["tram_info"]["sections"]
		for sec: Node3D in secs:
			if is_instance_valid(sec) and _flat(sec.global_position).distance_squared_to(_flat(pt)) <= r2:
				return true
	return false


static func _intersection_stop_line(graph: NetworkGraph, nid: int, my_eid: int) -> float:
	var cross_hw := 5.5
	for nb: Dictionary in graph.adj.get(nid, []):
		var ceid := int(nb["edge_id"])
		if ceid != my_eid and graph.edges.has(ceid):
			cross_hw = maxf(cross_hw, float(graph.edges[ceid]["width"]) * 0.5)
	return clampf(cross_hw + 6.2, 12.2, 16.5)


func find_hazard_along_tram_curve(tr: Dictionary, max_lookahead: float = 48.0) -> Dictionary:
	if bool(tr.get("elevated", false)) or bool(tr.get("grade_sep", false)):
		return {"has_hazard": false, "dist": 999.0}
	var curve: Curve3D = tr.get("curve")
	var rlen := float(tr.get("route_len", 10.0))
	var is_loop := bool(tr.get("is_loop", false))
	var dir := float(tr.get("dir", 1.0))
	var sec_len := float(tr["tram_info"].get("section_len", 9.2))
	var nose_s := float(tr["s"]) + dir * (sec_len * 0.5)
	if curve == null or rlen < 5.0 or cars.is_empty():
		return {"has_hazard": false, "dist": 999.0}

	var s_nose := fposmod(nose_s, rlen) if is_loop else clampf(nose_s, 0.0, rlen)
	var p_nose := curve.sample_baked(s_nose, true)
	var max_r2 := (max_lookahead + 5.0) * (max_lookahead + 5.0)
	var near_cars: Array[Dictionary] = []
	for c0: Dictionary in cars:
		if bool(c0["crashed"]) or bool(c0.get("grade_sep", false)):
			continue
		if p_nose.distance_squared_to(c0["pos"] as Vector3) <= max_r2:
			near_cars.append(c0)
	if near_cars.is_empty():
		return {"has_hazard": false, "dist": 999.0}

	var d := 0.8
	while d <= max_lookahead:
		var s_probe := nose_s + dir * d
		if is_loop:
			s_probe = fposmod(s_probe, rlen)
		elif s_probe < 0.0 or s_probe > rlen:
			break
		var p3 := curve.sample_baked(s_probe, true)
		for c: Dictionary in near_cars:
			var cp: Vector3 = c["pos"]
			# A car standing beside the rails (waiting for this tram) is outside its swept path: pass it
			var r_h := 3.65 if float(c.get("speed", 0.0)) > 0.3 else 2.75
			if p3.distance_squared_to(cp) <= r_h * r_h:
				return {"has_hazard": true, "dist": d, "car": c}
		d += 1.5
	return {"has_hazard": false, "dist": 999.0}


func find_hazard_ahead_of_tram(tram_pos: Vector3, tram_fwd: Vector3, max_lookahead: float) -> Dictionary:
	var best_d := max_lookahead
	var best_car: Dictionary = {}
	var right_v := tram_fwd.cross(Vector3.UP).normalized()

	for c: Dictionary in cars:
		if bool(c["crashed"]) or bool(c.get("grade_sep", false)):
			continue
		var dv := (c["pos"] as Vector3) - tram_pos
		var along := dv.dot(tram_fwd)
		if along < 1.5 or along > best_d:
			continue
		var lat := absf(dv.dot(right_v))
		var c_fwd: Vector3 = c["fwd"]
		var lat_signed := dv.dot(right_v)
		var crossing_rails := (absf(c_fwd.dot(right_v)) > 0.55 and float(c["speed"]) > 1.0 and lat < 5.2 and (lat_signed * c_fwd.dot(right_v)) < 0.0)
		if lat < 2.15 or crossing_rails:
			best_d = along
			best_car = c

	if best_car.is_empty():
		return {"has_hazard": false, "dist": 999.0}
	return {"has_hazard": true, "dist": best_d, "car": best_car}


func check_tram_collisions(trams: Array[Dictionary]) -> Dictionary:
	for ti in range(trams.size()):
		var tr: Dictionary = trams[ti]
		if bool(tr.get("elevated", false)) or bool(tr.get("grade_sep", false)):
			continue
		var tinfo: Dictionary = tr["tram_info"]
		var secs: Array = tinfo["sections"]
		var sec_hl := float(tinfo.get("section_len", 9.2)) * 0.5 - 0.20
		var sec_hw := float(tinfo.get("width", 2.6)) * 0.5 - 0.10

		for sec: Node3D in secs:
			if not is_instance_valid(sec):
				continue
			var stf := sec.global_transform
			var spos := stf.origin
			var sfwd := -stf.basis.z
			var s2 := Vector2(spos.x, spos.z)
			var f2 := Vector2(sfwd.x, sfwd.z).normalized()

			for c: Dictionary in cars:
				var cpos: Vector3 = c["pos"]
				if spos.distance_squared_to(cpos) > 48.0 or bool(c.get("grade_sep", false)):
					continue
				var cfwd: Vector3 = c["fwd"]
				var c2 := Vector2(cpos.x, cpos.z)
				var cf2 := Vector2(cfwd.x, cfwd.z).normalized()
				if obb_overlap_2d(s2, f2, sec_hl, sec_hw, c2, cf2, CAR_HALF_LEN - 0.14, CAR_HALF_WID - 0.10):
					c["crashed"] = true
					c["speed"] = 0.0
					var cnode: Node3D = c["node"]
					if is_instance_valid(cnode):
						var push_dir := (cpos - spos).normalized()
						push_dir.y = 0.0
						cnode.global_position += push_dir * 1.15 + Vector3(0.0, 0.18, 0.0)
						cnode.rotate_y(deg_to_rad(42.0))
						cnode.rotate_object_local(Vector3.FORWARD, deg_to_rad(24.0))
					return {
						"hit": true,
						"tram_idx": ti,
						"world_pos": (spos + cpos) * 0.5,
					}
	return {"hit": false}


static func obb_overlap_2d(
	pa: Vector2, fa: Vector2, hla: float, hwa: float,
	pb: Vector2, fb: Vector2, hlb: float, hwb: float
) -> bool:
	var ra := Vector2(-fa.y, fa.x)
	var rb := Vector2(-fb.y, fb.x)
	var d := pb - pa

	for axis: Vector2 in [fa, ra, fb, rb]:
		var proj_d := absf(d.dot(axis))
		var ext_a := absf(fa.dot(axis)) * hla + absf(ra.dot(axis)) * hwa
		var ext_b := absf(fb.dot(axis)) * hlb + absf(rb.dot(axis)) * hwb
		if proj_d > ext_a + ext_b:
			return false
	return true


func _advance_car_to_next_edge(c: Dictionary, graph: NetworkGraph, at_node: int, prev_eid: int) -> void:
	var nbs: Array = graph.adj.get(at_node, [])
	var old_pos: Vector3 = c["pos"]
	var old_fwd: Vector3 = c["fwd"]
	var j_p2: Vector2 = graph.nodes[at_node]["pos"]
	var j_center := Vector3(j_p2.x, 0.042, j_p2.y)

	# The move planned before the stop line (checked there against the tram tracks); else pick one now
	var plan := _plan_move(c, graph, prev_eid, at_node)
	var new_eid := int(plan["eid"])
	var new_dir := float(plan["dir"])
	var new_k := int(plan["k"])
	c.erase("plan")
	c.erase("xcommit_nid")
	if not car_dir_allowed(graph, new_eid, new_dir) or _is_transit_mall_double_track(graph, new_eid):
		c["force_respawn"] = true
		c["speed"] = 0.0
		return

	var new_ed: Dictionary = graph.edges[new_eid]
	var new_len := float(new_ed["length"])
	var entry_s := 5.6 if new_dir > 0.0 else maxf(1.0, new_len - 5.6)
	c["lane_k"] = new_k
	var new_lane := _compute_dynamic_lane_offset(graph, new_eid, entry_s, new_len, new_dir, new_k)

	var fr_n := _edge_frame(graph, new_eid, entry_s, new_len, new_dir)
	var new_fwd: Vector3 = fr_n[1]
	var new_right := new_fwd.cross(Vector3.UP).normalized()
	var entry_pos := (fr_n[0] as Vector3) + new_right * new_lane + Vector3(0.0, 0.042, 0.0)

	# Compute smooth Quadratic Bezier control point through the intersection so the car glides around corners!
	var ctrl_pt := j_center + (old_fwd.cross(Vector3.UP).normalized() * 1.4)
	if new_eid == prev_eid:
		ctrl_pt = (old_pos + entry_pos) * 0.5 + old_fwd * 4.5
	var arc_len := old_pos.distance_to(ctrl_pt) + ctrl_pt.distance_to(entry_pos)

	c["edge_id"] = new_eid
	c["edge_len"] = new_len
	c["dir"] = new_dir
	c["s"] = entry_s
	c["lane_offset"] = new_lane
	c["turning"] = (arc_len > 1.2)
	c["turn_t"] = 0.0
	c["turn_len"] = maxf(2.5, arc_len)
	c["turn_p0"] = old_pos
	c["turn_p1"] = ctrl_pt
	c["turn_p2"] = entry_pos


# Moves a car may take at a junction (one-way streets, tram-only rights of way and short stubs excluded)
func _move_candidates(graph: NetworkGraph, prev_eid: int, at_node: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for nb: Dictionary in graph.adj.get(at_node, []):
		var cand_eid := int(nb["edge_id"])
		if cand_eid == prev_eid or float(nb["length"]) < 18.0:
			continue
		if _is_transit_mall_double_track(graph, cand_eid) or _edge_rides_rails(graph, cand_eid):
			continue
		var cand_dir := 1.0 if int(graph.edges[cand_eid]["a"]) == at_node else -1.0
		if not car_dir_allowed(graph, cand_eid, cand_dir):
			continue # one-way street the wrong way
		out.append({"eid": cand_eid, "dir": cand_dir})
	return out


func _make_plan(graph: NetworkGraph, eid: int, dir: float, at_node: int, cand: Dictionary) -> Dictionary:
	var k := _rng.randi() % maxi(1, dir_lanes(graph, int(cand["eid"]), float(cand["dir"])))
	return {"from": eid, "from_dir": dir, "node": at_node, "eid": int(cand["eid"]), "dir": float(cand["dir"]), "k": k, "xing": null, "xing_done": false}


# The car's next move at the junction ahead, chosen once (well before the stop line) and kept
func _plan_move(c: Dictionary, graph: NetworkGraph, eid: int, at_node: int) -> Dictionary:
	var pl: Dictionary = c.get("plan", {})
	if not pl.is_empty() and int(pl["from"]) == eid and int(pl["node"]) == at_node and float(pl["from_dir"]) == float(c["dir"]) and graph.edges.has(int(pl["eid"])):
		return pl
	var cands := _move_candidates(graph, eid, at_node)
	if cands.is_empty():
		# dead end: smooth Bezier U-turn back the way it came (never teleport)
		pl = {"from": eid, "from_dir": float(c["dir"]), "node": at_node, "eid": eid, "dir": -float(c["dir"]), "k": 0, "xing": null, "xing_done": false}
	else:
		pl = _make_plan(graph, eid, float(c["dir"]), at_node, cands[_rng.randi() % cands.size()])
	c["plan"] = pl
	return pl


# First point where this move's path (rest of the lane, the turn through the junction, the start of the next
# street) comes onto a tram track; null when it never does. Cached in the plan.
func _plan_track_crossing(c: Dictionary, graph: NetworkGraph, pl: Dictionary) -> Variant:
	if bool(pl["xing_done"]):
		return pl["xing"]
	pl["xing_done"] = true
	pl["xing"] = null
	if clear_idx_cache.is_empty():
		return null
	var eid := int(pl["from"])
	var dir := float(pl["from_dir"])
	var elen := float(graph.edges[eid]["length"])
	var lane := float(c["lane_offset"])
	var pts: Array[Vector3] = []
	# rest of the own lane from the stop line to where the turn starts
	var stop_d := _intersection_stop_line(graph, int(pl["node"]), eid)
	for f in [1.0, 0.66, 0.33, 0.0]:
		var dist_end := lerpf(5.5, stop_d, f)
		var s_q := (elen - dist_end) if dir > 0.0 else dist_end
		var fr := _edge_frame(graph, eid, clampf(s_q, 0.0, elen), elen, dir)
		pts.append((fr[0] as Vector3) + (fr[1] as Vector3).cross(Vector3.UP).normalized() * lane)
	var p0: Vector3 = pts[pts.size() - 1]
	var old_fwd: Vector3 = _edge_frame(graph, eid, clampf((elen - 5.5) if dir > 0.0 else 5.5, 0.0, elen), elen, dir)[1]
	var new_eid := int(pl["eid"])
	var new_dir := float(pl["dir"])
	var new_len := float(graph.edges[new_eid]["length"])
	var j_p2: Vector2 = graph.nodes[int(pl["node"])]["pos"]
	var j_center := Vector3(j_p2.x, 0.0, j_p2.y)
	var entry_pos := Vector3.ZERO
	for k2 in range(3):
		var e_s := 5.6 + float(k2) * 4.0
		var s_e := e_s if new_dir > 0.0 else maxf(1.0, new_len - e_s)
		var lane_n := _compute_dynamic_lane_offset(graph, new_eid, s_e, new_len, new_dir, int(pl["k"]))
		var fr_n := _edge_frame(graph, new_eid, s_e, new_len, new_dir)
		var q := (fr_n[0] as Vector3) + (fr_n[1] as Vector3).cross(Vector3.UP).normalized() * lane_n
		if k2 == 0:
			entry_pos = q
		else:
			pts.append(q)
		var exs: Array = pl.get("exit_pts", [])
		exs.append(q)
		pl["exit_pts"] = exs
	var ctrl := j_center + old_fwd.cross(Vector3.UP).normalized() * 1.4
	if new_eid == eid:
		ctrl = (p0 + entry_pos) * 0.5 + old_fwd * 4.5
	var bez: Array[Vector3] = []
	for i in range(1, 13):
		var u := float(i) / 12.0
		var o := 1.0 - u
		bez.append(o * o * p0 + 2.0 * o * u * ctrl + u * u * entry_pos)
	var path: Array[Vector3] = []
	path.append_array(pts.slice(0, 4))
	path.append_array(bez)
	path.append_array(pts.slice(4))
	for q2: Vector3 in path:
		if TrackBuilder.track_clearance_dist(clear_idx_cache, Vector2(q2.x, q2.z)) < 3.0:
			pl["xing"] = Vector3(q2.x, 0.0, q2.z)
			break
	return pl["xing"]


# Hard rule at the moment a car's nose would come onto tram rails (within 2 m of a track centre, i.e. into a
# tram's envelope): only with no tram in the box or reaching that point within ~10 s, and no tram signal there
# showing go / caution (or about to). A car whose nose is already on the rails always drives on and clears them.
func _rail_entry_blocked(c: Dictionary, pos_now: Vector3, fwd_now: Vector3, pos_next: Vector3, fwd_next: Vector3, trams: Array[Dictionary], graph: NetworkGraph) -> bool:
	if clear_idx_cache.is_empty() or trams.is_empty():
		return false
	# the whole footprint counts (mid-turn a car runs almost along the rails: a rear corner reaches them first)
	var fp_next := _footprint_clearance(pos_next, fwd_next)
	if float(fp_next[0]) >= FOOT_CLEAR:
		return false
	if float(_footprint_clearance(pos_now, fwd_now)[0]) < FOOT_CLEAR:
		return false # already on the rails: drive on and clear them
	var n_next: Vector3 = fp_next[1]
	var p_chk := Vector3(n_next.x, 0.0, n_next.z)
	var blocked := _tram_threat_at(trams, p_chk, 11.0) or _exit_blocked(c)
	if not blocked:
		var n2 := Vector2(n_next.x, n_next.z)
		for nid: int in track_sig_ids:
			var sig: Dictionary = signals[nid]
			if (sig["pos2"] as Vector2).distance_to(n2) < 24.0:
				var ths := _tram_heads_state(sig)
				if bool(ths["active"]) or float(ths["t_go"]) < 2.5:
					blocked = true
					# tracks on both axes keep some tram head lit: after a long wait with no tram anywhere near, go
					if float(c.get("xwait", 0.0)) > 20.0 and not _any_tram_within(trams, Vector3((sig["pos2"] as Vector2).x, 0.0, (sig["pos2"] as Vector2).y), 150.0):
						blocked = false
				break
	if blocked:
		c["xwait"] = float(c.get("xwait", 0.0)) + get_process_delta_time()
	else:
		c["xwait"] = 0.0
	return blocked


const FOOT_CLEAR := 1.6 # car footprint to a track centre: tram half width 1.3 m + margin


# Smallest distance from the car's footprint (corners, nose, centre) to a track centre, and that point
func _footprint_clearance(pos: Vector3, fwd: Vector3) -> Array:
	var d0 := TrackBuilder.track_clearance_dist(clear_idx_cache, Vector2(pos.x, pos.z))
	if d0 >= FOOT_CLEAR + 2.5:
		return [d0, pos]
	var f := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var r := f.cross(Vector3.UP).normalized()
	var best := d0
	var bp := pos
	for q: Vector3 in [pos + f * CAR_HALF_LEN, pos + f * CAR_HALF_LEN + r * CAR_HALF_WID, pos + f * CAR_HALF_LEN - r * CAR_HALF_WID, pos - f * CAR_HALF_LEN + r * CAR_HALF_WID, pos - f * CAR_HALF_LEN - r * CAR_HALF_WID]:
		var d := TrackBuilder.track_clearance_dist(clear_idx_cache, Vector2(q.x, q.z))
		if d < best:
			best = d
			bp = q
	return [best, bp]


# Room on the far side of the rails for this car (stopped / slow cars where it is heading): never start
# across the rails into a queue that would leave it standing on them
func _exit_blocked(c: Dictionary) -> bool:
	var pts: Array[Vector3] = []
	if bool(c.get("turning", false)):
		var p1: Vector3 = c["turn_p1"]
		var p2: Vector3 = c["turn_p2"]
		var d := Vector3(p2.x - p1.x, 0.0, p2.z - p1.z)
		d = d.normalized() if d.length_squared() > 0.01 else (c["fwd"] as Vector3)
		pts = [p2, p2 + d * 6.0]
	else:
		var pl: Dictionary = c.get("plan", {})
		for q in pl.get("exit_pts", []):
			pts.append(q)
	for q2: Vector3 in pts:
		for oc: Dictionary in cars:
			if oc == c or float(oc["speed"]) > 2.5:
				continue
			var op: Vector3 = oc["pos"]
			if Vector2(op.x - q2.x, op.z - q2.z).length() < 5.0:
				return true
	return false


# Where the car's lane on this street comes onto tram rails (s values), scanned once per street and lane
func _edge_xings(c: Dictionary, graph: NetworkGraph, eid: int, dir: float, elen: float) -> Array:
	var key := "%d|%d|%d" % [eid, int(dir), int(round(float(c["lane_offset"]) * 2.0))]
	if str(c.get("xs_key", "")) == key:
		return c["xs"]
	if _edge_xings_cache.has(key):
		var cached: Array = _edge_xings_cache[key]
		c["xs_key"] = key
		c["xs"] = cached
		return cached
	var out: Array = []
	if not clear_idx_cache.is_empty():
		var inside := false
		var s_q := 0.0 if dir > 0.0 else elen
		var step := 2.0 if dir > 0.0 else -2.0
		while (s_q <= elen) if dir > 0.0 else (s_q >= 0.0):
			var fr := _edge_frame(graph, eid, s_q, elen, dir)
			var q := (fr[0] as Vector3) + (fr[1] as Vector3).cross(Vector3.UP).normalized() * float(c["lane_offset"])
			var on := TrackBuilder.track_clearance_dist(clear_idx_cache, Vector2(q.x, q.z)) < 3.0
			if on and not inside:
				out.append([s_q, s_q])
			if on:
				out[out.size() - 1][1] = s_q
			inside = on
			s_q += step
	_edge_xings_cache[key] = out
	c["xs_key"] = key
	c["xs"] = out
	return out


# Tram signal heads at a junction: is any showing go / caution, and how long until one next turns to go
func _tram_heads_state(sig: Dictionary) -> Dictionary:
	var t := float(sig["timer"])
	var code := _phase_code_from_timer(t)
	var any_a := false
	var any_b := false
	for th: Dictionary in sig.get("tram_heads", []):
		if bool(th["is_phase_a"]):
			any_a = true
		else:
			any_b = true
	if not any_a and not any_b and bool(sig.get("has_track", false)):
		any_a = true
		any_b = true
	var active := (any_a and code <= 1) or (any_b and code >= 2)
	var t_go := 999.0
	if any_a and code >= 2:
		t_go = minf(t_go, CYCLE_SEC - t)
	if any_b and code <= 1:
		t_go = minf(t_go, 17.5 - t)
	return {"active": active, "t_go": t_go}


static func _precompute_tram_threat_paths(trams: Array[Dictionary]) -> void:
	for tr: Dictionary in trams:
		var sec_pts := PackedVector2Array()
		for sec: Node3D in tr["tram_info"]["sections"]:
			if is_instance_valid(sec):
				var gp := sec.global_position
				sec_pts.append(Vector2(gp.x, gp.z))
		tr["_threat_sec_pts"] = sec_pts
		var path_pts := PackedVector2Array()
		var curve: Curve3D = tr.get("curve")
		var rlen := float(tr.get("route_len", 0.0))
		if curve != null and rlen >= 5.0:
			var spd := absf(float(tr.get("speed_mps", 0.0)))
			var dir := float(tr.get("dir", 1.0))
			var is_loop := bool(tr.get("is_loop", false))
			var nose_s := float(tr["s"]) + dir * float(tr["tram_info"].get("section_len", 9.2)) * 0.5
			var look := 40.0 + spd * 10.0
			var d := 0.0
			while d <= look:
				var sp := nose_s + dir * d
				if is_loop:
					sp = fposmod(sp, rlen)
				elif sp < 0.0 or sp > rlen:
					break
				var q := curve.sample_baked(sp, true)
				path_pts.append(Vector2(q.x, q.z))
				d += 3.0
			tr["_threat_reach2"] = (look + 12.0) * (look + 12.0)
		else:
			tr["_threat_reach2"] = 0.0
		tr["_threat_path_pts"] = path_pts


# A tram in the junction box, or one whose route ahead passes the crossing point within ~10 s (+ 40 m)
static func _tram_threat_at(trams: Array[Dictionary], pt: Vector3, box_r: float) -> bool:
	var p2 := Vector2(pt.x, pt.z)
	var box_r2 := box_r * box_r
	for tr: Dictionary in trams:
		if tr.has("_threat_sec_pts"):
			for sp2: Vector2 in (tr["_threat_sec_pts"] as PackedVector2Array):
				if sp2.distance_squared_to(p2) < box_r2:
					return true
			var ppts: PackedVector2Array = tr["_threat_path_pts"]
			if not ppts.is_empty() and ppts[0].distance_squared_to(p2) <= float(tr.get("_threat_reach2", 1e12)):
				for qp2: Vector2 in ppts:
					if qp2.distance_squared_to(p2) < 64.0: # covers the other track(s) of a double / quad line too
						return true
			continue
		for sec: Node3D in tr["tram_info"]["sections"]:
			if is_instance_valid(sec) and _flat(sec.global_position).distance_to(pt) < box_r:
				return true
		var curve: Curve3D = tr.get("curve")
		var rlen := float(tr.get("route_len", 0.0))
		if curve == null or rlen < 5.0:
			continue
		var spd := absf(float(tr.get("speed_mps", 0.0)))
		var dir := float(tr.get("dir", 1.0))
		var is_loop := bool(tr.get("is_loop", false))
		var nose_s := float(tr["s"]) + dir * float(tr["tram_info"].get("section_len", 9.2)) * 0.5
		var look := 40.0 + spd * 10.0
		var d := 0.0
		while d <= look:
			var sp := nose_s + dir * d
			if is_loop:
				sp = fposmod(sp, rlen)
			elif sp < 0.0 or sp > rlen:
				break
			var q := curve.sample_baked(sp, true)
			if Vector2(q.x, q.z).distance_to(p2) < 8.0: # covers the other track(s) of a double / quad line too
				return true
			d += 3.0
	return false


static func _any_tram_within(trams: Array[Dictionary], pt: Vector3, r: float) -> bool:
	return _is_any_tram_occupying_point(trams, pt, r)


func _respawn_car_near(c: Dictionary, graph: NetworkGraph, edge_ids: Array, focus_pos: Vector3, trams: Array[Dictionary], force_clear: bool = false) -> void:
	var attempts := 14 if force_clear else 1
	for _try in range(attempts):
		var eid := _pick_spawn_edge(graph, edge_ids, focus_pos, _try < 8)
		if eid < 0:
			continue
		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
		if elen < 26.0:
			continue
		var new_dir := 1.0 if _rng.randf() < 0.5 else -1.0
		if not car_dir_allowed(graph, eid, new_dir):
			new_dir = -new_dir
		if not car_dir_allowed(graph, eid, new_dir):
			continue
		var new_s := lerpf(11.0, elen - 11.0, _rng.randf())
		var smp := graph.sample_edge(eid, new_s / elen)
		var sp3: Vector3 = smp["pos"]
		var min_focus := 110.0 if (force_clear and _try >= 6) else 170.0
		if sp3.distance_squared_to(focus_pos) < min_focus * min_focus:
			continue
		if _is_any_tram_occupying_point(trams, sp3, 28.0):
			continue
		c["edge_id"] = eid
		c["edge_len"] = elen
		c["dir"] = new_dir
		c["s"] = new_s
		c["turning"] = false
		c["stuck_t"] = 0.0
		c["speed"] = float(c.get("cruise_speed", 7.8))
		c.erase("plan")
		c.erase("xcommit_nid")
		c["lane_k"] = _rng.randi() % maxi(1, dir_lanes(graph, eid, new_dir))
		c["lane_offset"] = _compute_dynamic_lane_offset(graph, eid, new_s, elen, new_dir, int(c["lane_k"]))
		_update_car_transform(c, graph)
		return


func _pick_spawn_edge(graph: NetworkGraph, edge_ids: Array, focus_pos: Vector3, near_focus: bool) -> int:
	if edge_ids.is_empty():
		return -1
	var f2 := Vector2(focus_pos.x, focus_pos.z)
	for _attempt in range(28):
		var eid := int(edge_ids[_rng.randi() % edge_ids.size()])
		var ed: Dictionary = graph.edges[eid]
		if float(ed["length"]) < 26.0:
			continue
		if near_focus:
			var p2: Vector2 = (ed["pts"] as Array)[0]
			var d2 := f2.distance_squared_to(p2)
			if d2 < 60.0 * 60.0 or d2 > 380.0 * 380.0:
				continue
		if _is_transit_mall_double_track(graph, eid) or _edge_rides_rails(graph, eid):
			continue
		return eid
	# Fallback anywhere on the map, still strictly respecting tram-only & rail-riding exclusions!
	for _fb in range(40):
		var eid2 := int(edge_ids[_rng.randi() % edge_ids.size()])
		if float(graph.edges[eid2]["length"]) < 26.0:
			continue
		if _is_transit_mall_double_track(graph, eid2) or _edge_rides_rails(graph, eid2):
			continue
		return eid2
	return -1


static func _is_transit_mall_double_track(graph: NetworkGraph, eid: int) -> bool:
	if not graph.edges.has(eid) or bool(graph.edges[eid].get("no_cars", false)):
		return true # tram-only right of way built across open ground
	if not _is_tram_edge(graph, eid):
		return false
	if graph.is_quad(eid):
		# Four-track corridor: cars only fit if a lane remains outside the local tracks
		return float(graph.edges[eid]["width"]) * 0.5 < QUAD_CAR_LANE + 1.6
	if int(graph.built_track_modes.get(eid, NetworkGraph.TrackMode.SINGLE)) != NetworkGraph.TrackMode.DOUBLE:
		return false
	var min_w := 14.2 if graph.get_edge_track_half_sep(eid) > 2.0 else 11.5
	return float(graph.edges[eid]["width"]) < min_w


var clear_idx_cache: Dictionary = {}
var _no_trams: Array[Dictionary] = []
var _rides_rails: Dictionary = {} # eid -> bool


# A street without tracks of its own whose car lanes run along tram rails for a stretch (e.g. the other
# carriageway of a divided street, drawn close beside the tram one): cars keep off it altogether
func _edge_rides_rails(graph: NetworkGraph, eid: int) -> bool:
	if _rides_rails.has(eid):
		return bool(_rides_rails[eid])
	var res := false
	if not _is_tram_edge(graph, eid) and graph.has_meta("track_clear_idx") and graph.edges.has(eid):
		var idx: Dictionary = graph.get_meta("track_clear_idx")
		var elen := float(graph.edges[eid]["length"])
		for dir: float in [1.0, -1.0]:
			if not car_dir_allowed(graph, eid, dir):
				continue
			var run := 0.0
			var s_q := 0.0
			while s_q <= elen and not res:
				var lane := _compute_dynamic_lane_offset(graph, eid, s_q, elen, dir, 0)
				var fr := _edge_frame(graph, eid, s_q, elen, dir)
				var q := (fr[0] as Vector3) + (fr[1] as Vector3).cross(Vector3.UP).normalized() * lane
				if TrackBuilder.track_clearance_dist(idx, Vector2(q.x, q.z)) < 2.6:
					run += 2.0
					if run > 14.0:
						res = true
				else:
					run = 0.0
				s_q += 2.0
	_rides_rails[eid] = res
	return res
const TRAM_CAR_CLEAR := 3.8 # car centre to the nearest tram track centre (tram hazard probe reaches 3.65 m)

const LANE_W := 3.3
const QUAD_CAR_LANE := 8.1 # first motor lane beside a four-track corridor (local track 4.95 + body + clearance)


# Motor lanes in travel direction dir (+1: a -> b) on an edge
static func dir_lanes(graph: NetworkGraph, eid: int, dir: float) -> int:
	var ed: Dictionary = graph.edges[eid]
	return int(ed.get("lanes_f", 1)) if dir > 0.0 else int(ed.get("lanes_b", 1))


static func car_dir_allowed(graph: NetworkGraph, eid: int, dir: float) -> bool:
	return dir_lanes(graph, eid, dir) > 0


# Offset (right of travel) of motor lane k for direction dir: kerb-side lanes on two-way streets (median on 4+ lanes),
# spread across the whole carriageway on one-way streets, outside the tracks where trams run
static func lane_base_offset(graph: NetworkGraph, eid: int, dir: float, lane_k: int) -> float:
	var ed: Dictionary = graph.edges[eid]
	var w := float(ed["width"])
	var n := maxi(1, dir_lanes(graph, eid, dir))
	var k := clampi(lane_k, 0, n - 1)
	var max_off := maxf(1.6, w * 0.5 - 1.7)
	if _is_tram_edge(graph, eid):
		var inner := QUAD_CAR_LANE if graph.is_quad(eid) else _safe_motor_lane_offset(graph, eid)
		return minf(inner + float(k) * LANE_W, maxf(inner, max_off))
	var other := dir_lanes(graph, eid, -dir)
	if other == 0:
		return minf(-float(n) * LANE_W * 0.5 + (float(k) + 0.5) * LANE_W, max_off) # one-way street
	if n == 1 and k == 0:
		return _safe_motor_lane_offset(graph, eid)
	var median := 0.8 if n + other >= 4 else 0.0
	var off := median + (float(k) + 0.5) * LANE_W
	var shift := maxf(0.0, median + float(n) * LANE_W - max_off - LANE_W * 0.5)
	return clampf(off - shift, 1.4, max_off)


static var _bay_grid_sig := ""
static var _bay_grid_cells: Dictionary = {} # Vector2i (64m cell) -> Array[Dictionary]


static func _get_nearby_bays(bays: Array, center: Vector3) -> Array:
	var sig := "%d_%s" % [bays.size(), str(bays[0]["pos"]) if not bays.is_empty() else ""]
	if sig != _bay_grid_sig:
		_bay_grid_sig = sig
		_bay_grid_cells.clear()
		for b: Dictionary in bays:
			var bp: Vector3 = b["pos"]
			var cx := int(floor(bp.x / 64.0))
			var cz := int(floor(bp.z / 64.0))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var ck := Vector2i(cx + dx, cz + dz)
					if not _bay_grid_cells.has(ck):
						_bay_grid_cells[ck] = []
					(_bay_grid_cells[ck] as Array).append(b)
	return _bay_grid_cells.get(Vector2i(int(floor(center.x / 64.0)), int(floor(center.z / 64.0))), [])


static func _compute_dynamic_lane_offset(graph: NetworkGraph, eid: int, s_now: float, elen: float, car_dir: float, lane_k: int = 0) -> float:
	var base := lane_base_offset(graph, eid, car_dir, lane_k)
	var is_trk := _is_tram_edge(graph, eid) and graph.has_meta("track_clear_idx")
	var bays: Array = graph.get_meta("station_bays", []) if graph.has_meta("station_bays") else []
	if not is_trk and bays.is_empty():
		return base
	var fr := _edge_frame(graph, eid, s_now, elen, car_dir)
	var center: Vector3 = fr[0]
	var right: Vector3 = (fr[1] as Vector3).cross(Vector3.UP).normalized()
	if is_trk:
		# The laid track is straightened within the street (up to ~2 m off the centre line): keep the car lane
		# clear of the actual rails, not just of the street centre
		var idx: Dictionary = graph.get_meta("track_clear_idx")
		var p_car: Vector3 = center + right * base
		var d_trk := TrackBuilder.track_clearance_dist(idx, Vector2(p_car.x, p_car.z))
		if d_trk < TRAM_CAR_CLEAR:
			base = minf(base + (TRAM_CAR_CLEAR - d_trk), maxf(base, float(graph.edges[eid]["width"]) * 0.5 - 0.9))
	if bays.is_empty():
		return base
	var near_bays: Array = _get_nearby_bays(bays, center)
	if near_bays.is_empty():
		return base
	var off := base
	for bay: Dictionary in near_bays:
		var rel := center - (bay["pos"] as Vector3)
		if rel.length_squared() > 1600.0:
			continue
		var along := rel.dot(bay["fwd"] as Vector3)
		if absf(along) > float(bay["half"]) + float(bay["taper"]):
			continue
		var ro := right.dot(bay["out"] as Vector3)
		if ro < 0.5:
			continue
		var q0 := rel.dot(bay["out"] as Vector3)
		# Only streets running alongside this platform (centreline within the carriageway next to it)
		if q0 > 1.0 or q0 < -float(bay["bay_q"]) - 6.0:
			continue
		# Shift outward so the car runs in the kerb bay beside the platform (world space, so it also
		# applies on the neighbouring street segment when a platform spills past a node)
		var needed := (float(bay["lane_q"]) - q0) / ro
		if needed <= base or needed > base + 6.0:
			continue
		off = maxf(off, lerpf(base, needed, TrackBuilder.bay_blend(bay, along)))
	return off


# Lane frame on an edge: centreline point + travel direction from a +-2.5m finite difference,
# so heading and lane offset turn smoothly through polyline vertices instead of snapping.
static func _edge_frame(graph: NetworkGraph, eid: int, s: float, elen: float, dir: float) -> Array:
	var L := maxf(1.0, elen)
	var c: Vector3 = graph.sample_edge(eid, clampf(s / L, 0.0, 1.0))["pos"]
	var pa: Vector3 = graph.sample_edge(eid, clampf((s - 2.5) / L, 0.0, 1.0))["pos"]
	var pb: Vector3 = graph.sample_edge(eid, clampf((s + 2.5) / L, 0.0, 1.0))["pos"]
	var f := (pb - pa) * dir
	f.y = 0.0
	if f.length_squared() < 1e-4:
		f = (graph.sample_edge(eid, clampf(s / L, 0.0, 1.0))["fwd"] as Vector3) * dir
	return [c, f.normalized()]


static func _safe_motor_lane_offset(graph: NetworkGraph, eid: int) -> float:
	var w := float(graph.edges[eid]["width"])
	# On streets with tram tracks, motor vehicles stay strictly clear of trams & median/island platforms!
	if _is_tram_edge(graph, eid):
		var sep := graph.get_edge_track_half_sep(eid)
		if sep > 2.0:
			return maxf(6.25, w * 0.40)
		if sep > 0.5:
			return maxf(4.95, w * 0.34)
		return maxf(3.85, w * 0.28)
	return clampf(w * 0.24, 2.35, 3.65)


static func _edge_side_has_station(graph: NetworkGraph, eid: int, car_dir: float) -> bool:
	if not _is_tram_edge(graph, eid):
		return false
	for sid: int in graph.stations.keys():
		var st: Dictionary = graph.stations[sid]
		if int(st["edge_id"]) == eid:
			# Station `side` (+1 or -1) is relative to edge a->b (+1). Right-hand lane of car_dir is `sign(car_dir)`!
			if int(signf(car_dir)) == int(st["side"]):
				return true
	return false


static func _edge_outward_dir_2d(graph: NetworkGraph, eid: int, nid: int) -> Vector2:
	var ed: Dictionary = graph.edges[eid]
	var pts: Array = ed["pts"]
	if pts.size() < 2:
		return Vector2(0.0, 1.0)
	if int(ed["a"]) == nid:
		return ((pts[1] as Vector2) - (pts[0] as Vector2)).normalized()
	var n := pts.size()
	return ((pts[n - 2] as Vector2) - (pts[n - 1] as Vector2)).normalized()


static func _update_car_transform(c: Dictionary, graph: NetworkGraph) -> void:
	var eid := int(c["edge_id"])
	var elen := maxf(1.0, float(c["edge_len"]))
	var fr := _edge_frame(graph, eid, float(c["s"]), elen, float(c["dir"]))
	var center_pos: Vector3 = fr[0]
	var fwd: Vector3 = fr[1]
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD

	var right_v := fwd.cross(Vector3.UP).normalized()
	var world_pos := center_pos + right_v * float(c["lane_offset"]) + Vector3(0.0, 0.042, 0.0)
	c["pos"] = world_pos
	c["fwd"] = fwd

	var mi: MeshInstance3D = c["node"]
	if is_instance_valid(mi):
		mi.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), world_pos)


# Builds sculpted Cities: Skylines II style 3D vehicles (sloped hood/windshield/fastback + round 5-spoke alloy wheels!)
func _build_shared_car_meshes() -> void:
	_veh_mat = ShaderMaterial.new()
	_veh_mat.shader = load("res://shaders/vehicle_pbr.gdshader") as Shader

	var palette: Array[Color] = [
		Color(0.84, 0.86, 0.89), # Pearl Silver-White Sedan
		Color(0.88, 0.66, 0.10), # City Yellow Cab
		Color(0.14, 0.28, 0.48), # Sapphire Metallic SUV
		Color(0.58, 0.12, 0.14), # Crimson Metallic Fastback
		Color(0.46, 0.49, 0.53), # Gunmetal Grey Sedan
		Color(0.14, 0.30, 0.22), # British Racing Green SUV
		Color(0.16, 0.17, 0.19), # Obsidian Executive Sedan
		Color(0.66, 0.58, 0.46), # Warm Champagne Crossover
	]

	_car_meshes.clear()
	for idx in range(palette.size()):
		var body_rgb := palette[idx]
		var is_suv := (idx % 3 == 2)
		var is_taxi := (idx == 1)

		var c_paint := Color(body_rgb.r, body_rgb.g, body_rgb.b, 0.0) # mat_id = 0: Clearcoat Metallic Paint
		var c_glass := Color(0.08, 0.12, 0.16, 0.1)                  # mat_id = 1: Fresnel Tinted Glass
		var c_wheel := Color(0.10, 0.10, 0.11, 0.2)                  # mat_id = 2: Tire + 5-Spoke Alloy Rim
		var c_trim := Color(0.13, 0.14, 0.16, 0.3)                   # mat_id = 3: Grille / Trim
		var c_chrome := Color(0.76, 0.79, 0.83, 0.3)                 # mat_id = 3: Chrome Accent
		var c_head := Color(1.0, 0.96, 0.86, 0.4)                    # mat_id = 4: Projector LED Headlight
		var c_tail := Color(0.95, 0.10, 0.10, 0.5)                    # mat_id = 5: Ruby LED Taillight

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		# 1. Sculpted Aerodynamic Side-Profile Extrusion (Front -Z = -2.18 -> Rear +Z = +2.18)!
		var roof_y := 1.48 if is_suv else 1.36
		var rear_glass_z := 1.88 if is_suv else 1.46
		var trunk_y := 1.02 if is_suv else 0.88
		# Counter-clockwise profile in (z, y) extruded from x = -0.89 to +0.89:
		var prof_zy: Array[Vector2] = [
			Vector2(-2.16, 0.22),
			Vector2(-2.20, 0.54), # Sculpted front bumper nose
			Vector2(-2.05, 0.72), # Hood leading edge
			Vector2(-0.88, 0.82), # Base of windshield
			Vector2(-0.28, roof_y), # Sloped 32-deg A-pillar & windshield
			Vector2(0.88 if not is_suv else 1.52, roof_y - 0.02), # Sleek roofline
			Vector2(rear_glass_z, trunk_y), # Sloped C-pillar / tailgate
			Vector2(2.14, trunk_y - 0.04), # Trunk deck
			Vector2(2.18, 0.52), # Rear bumper
			Vector2(2.08, 0.22), # Rear diffuser
		]
		_emit_car_hull_profile(st, prof_zy, 0.88, c_paint)

		# 2. Flush Recessed Tinted Windshield, Rear Window & Side Windows (mat_id = 1)!
		# Raked front windshield quad
		_emit_sloped_quad(
			st,
			Vector3(-0.75, 0.83, -0.89), Vector3(0.75, 0.83, -0.89),
			Vector3(0.69, roof_y - 0.03, -0.30), Vector3(-0.69, roof_y - 0.03, -0.30),
			c_glass
		)
		# Sloped rear backlight window quad
		var r_top_z := 0.89 if not is_suv else 1.53
		_emit_sloped_quad(
			st,
			Vector3(0.69, roof_y - 0.05, r_top_z), Vector3(-0.69, roof_y - 0.05, r_top_z),
			Vector3(-0.74, trunk_y + 0.02, rear_glass_z + 0.01), Vector3(0.74, trunk_y + 0.02, rear_glass_z + 0.01),
			c_glass
		)
		# Left & right side greenhouse glass + B-pillar divider + side mirrors!
		var win_len := (1.68 if is_suv else 1.38)
		var win_cz := (0.48 if is_suv else 0.28)
		for side: float in [-1.0, 1.0]:
			var sx := side * 0.886
			var out_n := Vector3(side, 0.0, 0.0)
			_emit_uv_quad(
				st,
				Vector3(sx, 0.84, win_cz - win_len * 0.5),
				Vector3(sx, 0.84, win_cz + win_len * 0.5),
				Vector3(sx * 0.92, roof_y - 0.06, win_cz + win_len * 0.42),
				Vector3(sx * 0.92, roof_y - 0.06, win_cz - win_len * 0.36),
				out_n,
				c_glass
			)
			# Matte black B-pillar & aerodynamic wing mirror
			CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(side * 0.86, 1.08, 0.18)), Vector3(0.06, 0.44, 0.09), c_trim)
			CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(side * 0.96, 0.90, -0.58)), Vector3(0.15, 0.09, 0.12), c_paint)

		# 3. Front Honeycomb Grille, Lower Splitter, License Plates & LED Light Clusters!
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.48, -2.19)), Vector3(1.12, 0.22, 0.06), c_trim)
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.60, -2.20)), Vector3(1.16, 0.035, 0.06), c_chrome)
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.34, -2.21)), Vector3(0.38, 0.10, 0.03), Color(0.92, 0.92, 0.90, 0.3))
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.46, 2.18)), Vector3(0.38, 0.10, 0.03), Color(0.92, 0.92, 0.90, 0.3))

		for lx: float in [-0.66, 0.66]:
			CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(lx, 0.62, -2.17)), Vector3(0.34, 0.12, 0.08), c_head)
			CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(lx, 0.68, 2.16)), Vector3(0.38, 0.13, 0.08), c_tail)
		# Modern rear LED light-bar strip
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.71, 2.165)), Vector3(1.36, 0.04, 0.06), c_tail)

		if is_taxi:
			CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, roof_y + 0.08, 0.10)), Vector3(0.46, 0.14, 0.20), c_head)

		# 4. Four Round 14-Segment Cylindrical Rubber Tires + 5-Spoke Alloy Rims!
		for wx: float in [-0.84, 0.84]:
			for wz: float in [-1.36, 1.34]:
				_emit_round_wheel(st, Vector3(wx, 0.33, wz), 0.33, 0.22, signf(wx), c_wheel)

		_car_meshes.append(st.commit())


static func _emit_car_hull_profile(st: SurfaceTool, prof: Array[Vector2], half_w: float, col: Color) -> void:
	var n := prof.size()
	# Top/front/rear/bottom perimeter ribbon with slightly narrower greenhouse taper above y = 0.85!
	for i in range(n):
		var a := prof[i]
		var b := prof[(i + 1) % n]
		var hw_a := half_w * (0.86 if a.y > 0.95 else 1.0)
		var hw_b := half_w * (0.86 if b.y > 0.95 else 1.0)
		var dz := b.x - a.x
		var dy := b.y - a.y
		var nrm := Vector3(0.0, dz, -dy).normalized()
		if nrm.dot(Vector3(0.0, (a.y + b.y) * 0.5 - 0.65, (a.x + b.x) * 0.5)) < 0.0:
			nrm = -nrm

		var v0 := Vector3(-hw_a, a.y, a.x)
		var v1 := Vector3(hw_a, a.y, a.x)
		var v2 := Vector3(hw_b, b.y, b.x)
		var v3 := Vector3(-hw_b, b.y, b.x)
		for v: Vector3 in [v0, v1, v2, v0, v2, v3]:
			st.set_color(col); st.set_normal(nrm); st.set_uv(Vector2.ZERO); st.add_vertex(v)

	# Left & Right sculpted body side panels (triangulated polygon!)
	var tri := Geometry2D.triangulate_polygon(PackedVector2Array(prof))
	for side: float in [-1.0, 1.0]:
		var side_n := Vector3(side, 0.08, 0.0).normalized()
		for k in range(0, tri.size(), 3):
			var i0 := tri[k]
			var i1 := tri[k + 1] if side > 0.0 else tri[k + 2]
			var i2 := tri[k + 2] if side > 0.0 else tri[k + 1]
			for pi: int in [i0, i1, i2]:
				var pt := prof[pi]
				var x_use := side * half_w * (0.86 if pt.y > 0.95 else 1.0)
				st.set_color(col)
				st.set_normal(side_n)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(Vector3(x_use, pt.y, pt.x))


static func _emit_sloped_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, col: Color) -> void:
	var nrm := (v1 - v0).cross(v3 - v0).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	_emit_uv_quad(st, v0, v1, v2, v3, nrm, col)


static func _emit_uv_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, nrm: Vector3, col: Color) -> void:
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = [v0, v1, v2, v3][idx]
		st.set_color(col)
		st.set_normal(nrm)
		st.set_uv(uvs[idx])
		st.add_vertex(p)


static func _emit_round_wheel(st: SurfaceTool, center: Vector3, radius: float, width: float, out_side: float, col: Color) -> void:
	var segs := 14
	var x_in := center.x - out_side * width * 0.5
	var x_out := center.x + out_side * width * 0.5
	var cap_n := Vector3(out_side, 0.0, 0.0)

	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var y0 := center.y + sin(a0) * radius
		var z0 := center.z + cos(a0) * radius
		var y1 := center.y + sin(a1) * radius
		var z1 := center.z + cos(a1) * radius
		var n0 := Vector3(0.0, sin(a0), cos(a0))
		var n1 := Vector3(0.0, sin(a1), cos(a1))

		# Tire tread cylinder band (UV.x = 0.90 -> grooved rubber tread)
		var p00 := Vector3(x_in, y0, z0)
		var p01 := Vector3(x_out, y0, z0)
		var p11 := Vector3(x_out, y1, z1)
		var p10 := Vector3(x_in, y1, z1)
		for pair in [[p00, n0], [p01, n0], [p11, n1], [p00, n0], [p11, n1], [p10, n1]]:
			st.set_color(col); st.set_normal(pair[1]); st.set_uv(Vector2(0.90, 0.0)); st.add_vertex(pair[0])

		# Outer wheel face fan (UV = (r, angle) -> 5-spoke silver alloy rim inside rubber tire!)
		var c_out := Vector3(x_out, center.y, center.z)
		var v_a := p01 if out_side > 0.0 else p11
		var v_b := p11 if out_side > 0.0 else p01
		var ang_a := a0 if out_side > 0.0 else a1
		var ang_b := a1 if out_side > 0.0 else a0
		st.set_color(col); st.set_normal(cap_n); st.set_uv(Vector2(0.02, 0.0)); st.add_vertex(c_out)
		st.set_color(col); st.set_normal(cap_n); st.set_uv(Vector2(1.0, ang_a)); st.add_vertex(v_a)
		st.set_color(col); st.set_normal(cap_n); st.set_uv(Vector2(1.0, ang_b)); st.add_vertex(v_b)
