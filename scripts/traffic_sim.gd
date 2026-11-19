class_name TrafficSim
extends Node3D

const MAX_CARS := 40
const CAR_HALF_LEN := 2.22
const CAR_HALF_WID := 0.90
const CYCLE_SEC := 26.0
const STOP_LINE_DIST := 9.2

var cars: Array[Dictionary] = []
var signals: Dictionary = {} # node_id (int) -> {axis: Vector2, timer: float, state_code: int, heads_a: Array, heads_b: Array, tram_heads: Array}

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
	signals.clear()

	if graph.edges.is_empty():
		return

	_build_intersection_signals(graph)

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
		var s_init := lerpf(11.0, elen - 11.0, _rng.randf())
		var base_lane := _compute_dynamic_lane_offset(graph, eid, s_init, elen, dir)

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


func _build_intersection_signals(graph: NetworkGraph) -> void:
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
			if graph.built_tracks.has(int(x["edge_id"])):
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
			if graph.built_tracks.has(int(x["edge_id"])):
				ta += 1
		var tb := 0
		for x: Dictionary in nb_arr:
			if graph.built_tracks.has(int(x["edge_id"])):
				tb += 1
		var score_a := ta * 10 + na.size()
		var score_b := tb * 10 + nb_arr.size()
		return score_a > score_b
	)

	var placed_positions: Array[Vector2] = []

	for nid: int in ordered_nids:
		var nbs: Array = graph.adj.get(nid, [])
		var np2: Vector2 = graph.nodes[nid]["pos"]

		# Determine Primary Axis (Phase A): align with built tram track if present, else main N-S street!
		var primary_axis := Vector2(0.0, 1.0)
		var has_track := false
		for nb: Dictionary in nbs:
			var eid := int(nb["edge_id"])
			if graph.built_tracks.has(eid):
				primary_axis = _edge_outward_dir_2d(graph, eid, nid)
				has_track = true
				break

		# Track intersections ALWAYS get dedicated tram signals (only deduplicate within 14m); non-track intersections keep 72m spacing!
		var min_space := 14.0 if has_track else 72.0
		var too_close := false
		for pp: Vector2 in placed_positions:
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

		placed_positions.append(np2)

		var init_t := fposmod(float((nid * 7) % 13) * 2.1, CYCLE_SEC)
		var heads_a: Array[Dictionary] = []
		var heads_b: Array[Dictionary] = []
		var tram_heads: Array[Dictionary] = []

		# Build visible 3D Motor Traffic Lights + Dedicated Tram Signals on EVERY track intersection!
		for nb: Dictionary in nbs:
			var eid := int(nb["edge_id"])
			var ed: Dictionary = graph.edges[eid]
			var edge_has_track := graph.built_tracks.has(eid)
			var elen_sig := float(ed["length"])
			if elen_sig < (12.0 if edge_has_track else 22.0):
				continue
			var out_dir2 := _edge_outward_dir_2d(graph, eid, nid)
			var is_phase_a := (absf(out_dir2.dot(primary_axis)) >= 0.65)

			# Approach direction is -out_dir2 (vehicles driving TOWARD node `nid`)
			var app_fwd := Vector3(-out_dir2.x, 0.0, -out_dir2.y).normalized()
			var app_right := app_fwd.cross(Vector3.UP).normalized()
			var j_p2: Vector2 = graph.nodes[nid]["pos"]
			var j_pos3 := Vector3(j_p2.x, 0.0, j_p2.y)
			var road_hw := clampf(float(ed["width"]) * 0.5, 4.5, 9.5)
			var track_sep := graph.get_edge_track_half_sep(eid) if edge_has_track else 0.0
			var cross_hw := 5.5
			for nb_c: Dictionary in nbs:
				var ceid := int(nb_c["edge_id"])
				if ceid != eid:
					cross_hw = maxf(cross_hw, float(graph.edges[ceid]["width"]) * 0.5)
			var pull_back := clampf(cross_hw + 4.8, 9.5, minf(16.0, elen_sig * 0.44))
			var mast_lat := maxf(road_hw + 1.15, track_sep + 3.45)

			# 1. Overhead Cantilever 3-Aspect Motor Traffic Signal (Red / Yellow / Green)
			var pole_pos := j_pos3 - app_fwd * pull_back + app_right * mast_lat
			if _is_pole_clear_of_tracks(graph, Vector2(pole_pos.x, pole_pos.z)):
				var m_head := _spawn_motor_signal_mast(sig_holder, pole_pos, app_fwd, frame_mat)
				if is_phase_a:
					heads_a.append(m_head)
				else:
					heads_b.append(m_head)

			# 2. Dedicated Streetcar / Tram Bar Signal ('━' Stop / '●' Wait / '┃' Proceed) DIRECTLY BESIDE THE TRAM TRACK!
			# Positioned at track_sep + 1.92m (right beside the tramway curb, well inside the outer road sidewalk motor lights)
			# so drivers see it straight ahead in their natural sightline without blocking motor traffic lights!
			if edge_has_track:
				var tram_pb := clampf(cross_hw + 5.8, 10.2, minf(16.8, elen_sig * 0.46))
				var track_lat := track_sep + 1.92
				var chosen_pos := j_pos3 - app_fwd * tram_pb + app_right * track_lat
				# Verify clearance from cross-street tracks (if another track crosses right there, pull slightly further back)
				var hit_t := graph.find_closest_edge(Vector2(chosen_pos.x, chosen_pos.z), 4.0, true)
				if not hit_t.is_empty() and int(hit_t["edge_id"]) != eid:
					chosen_pos = j_pos3 - app_fwd * minf(tram_pb + 2.8, elen_sig * 0.48) + app_right * track_lat
				# Tracks widen on curves: step the post outward until it clears every laid lane
				if graph.has_meta("track_clear_idx"):
					var cidx: Dictionary = graph.get_meta("track_clear_idx")
					for _k in range(10):
						if TrackBuilder.track_clearance_dist(cidx, Vector2(chosen_pos.x, chosen_pos.z)) >= 1.8:
							break
						chosen_pos += app_right * 0.4
				var t_head := _spawn_dedicated_tram_signal(sig_holder, chosen_pos, app_fwd, is_phase_a, frame_mat)
				tram_heads.append(t_head)

		var sig_entry := {
			"node_id": nid,
			"pos2": graph.nodes[nid]["pos"],
			"axis": primary_axis,
			"has_track": has_track,
			"timer": init_t,
			"state_code": -1,
			"heads_a": heads_a,
			"heads_b": heads_b,
			"tram_heads": tram_heads,
		}
		signals[nid] = sig_entry
		_refresh_signal_visuals(sig_entry)


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
	root.transform = Transform3D(Basis.looking_at(app_fwd, Vector3.UP), pos)
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
	root.transform = Transform3D(Basis.looking_at(app_fwd, Vector3.UP), pos)
	parent.add_child(root)

	# Slim Trackside Dedicated Tram Signal Post directly beside the rails at cab upper-windshield height (~3.10m)
	_sig_box(root, Vector3(0.09, 3.55, 0.09), Vector3(0.0, 1.77, 0.0), _sig_pole_mat, 225.0)
	var hy := 3.10
	var badge_mat := StandardMaterial3D.new()
	badge_mat.albedo_color = Color(0.08, 0.44, 0.78)
	badge_mat.roughness = 0.32
	_sig_box(root, Vector3(0.36, 0.13, 0.14), Vector3(0.0, hy + 0.54, 0.0), badge_mat, 225.0)
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
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = vis_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _sig_disc(parent: Node3D, r: float, pos: Vector3, mat: Material, vis_end: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r; c.bottom_radius = r; c.height = 0.03; c.radial_segments = 12
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


# Queries the nearest signalized intersection ahead of a tram's FRONT NOSE along its actual curve (works on curves too!)
func get_upcoming_tram_signal(tr: Dictionary, graph: NetworkGraph) -> Dictionary:
	var secs: Array = tr["tram_info"]["sections"]
	if secs.is_empty() or signals.is_empty():
		return {"has_signal": false, "aspect": "green", "dist": 999.0, "stop_line": 11.2}

	var curve: Curve3D = tr.get("curve")
	var rlen := float(tr.get("route_len", 10.0))
	var is_loop := bool(tr.get("is_loop", false))
	var dir := float(tr.get("dir", 1.0))
	var sec_len := float(tr["tram_info"].get("section_len", 9.2))
	var nose_s := float(tr["s"]) + dir * (sec_len * 0.5)

	if curve != null and rlen > 5.0:
		var look_d := 2.0
		while look_d <= 52.0:
			var s_probe := nose_s + dir * look_d
			if is_loop:
				s_probe = fposmod(s_probe, rlen)
			elif s_probe < 0.0 or s_probe > rlen:
				break
			var p3 := curve.sample_baked(s_probe, true)
			var p2 := Vector2(p3.x, p3.z)
			for nid: int in signals.keys():
				var sig: Dictionary = signals[nid]
				if not bool(sig["has_track"]):
					continue
				if (sig["pos2"] as Vector2).distance_squared_to(p2) <= 5.8 * 5.8:
					var tf_p := TrackBuilder.sample_track_frame(curve, s_probe, rlen, is_loop)
					var app_fwd := (-tf_p.basis.z) * dir
					var app2 := Vector2(app_fwd.x, app_fwd.z).normalized()
					var max_w := 10.0
					for nb: Dictionary in graph.adj.get(nid, []):
						max_w = maxf(max_w, float(graph.edges[int(nb["edge_id"])]["width"]))
					var stop_line := clampf(max_w * 0.5 + 3.4, 10.8, 13.8)
					return {
						"has_signal": true,
						"node_id": nid,
						"aspect": get_signal_aspect(nid, app2),
						"dist": look_d,
						"stop_line": stop_line,
					}
			look_d += 2.2

	return {"has_signal": false, "aspect": "green", "dist": 999.0, "stop_line": 11.2}


func on_bell_rung(tram_pos: Vector3, tram_fwd: Vector3) -> void:
	# Ringing bell ('H') cautions nearby cars & requests immediate Transit Signal Priority ahead!
	var tf2 := Vector2(tram_fwd.x, tram_fwd.z).normalized()
	var tp2 := Vector2(tram_pos.x, tram_pos.z)
	for nid: int in signals.keys():
		var sig: Dictionary = signals[nid]
		if not bool(sig["has_track"]):
			continue
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
	# 1. Advance all Intersection Signal Controllers (+ gentle Transit Signal Priority for approaching trams)
	for nid: int in signals.keys():
		var sig: Dictionary = signals[nid]
		var t := fposmod(float(sig["timer"]) + dt, CYCLE_SEC)

		# Gentle Transit Signal Priority (TSP): if a tram is waiting within 22m on Red and cross-street served >= 6.5s, transition to yellow clearance!
		if bool(sig["has_track"]) and not trams.is_empty():
			var jp2: Vector2 = graph.nodes[nid]["pos"]
			var jp3 := Vector3(jp2.x, 0.0, jp2.y)
			for tr: Dictionary in trams:
				var secs_t: Array = tr["tram_info"]["sections"]
				if secs_t.is_empty():
					continue
				var s0 := secs_t[0] as Node3D
				var d_j := s0.global_position.distance_to(jp3)
				if d_j > 6.5 and d_j < 24.0:
					var tfwd := -s0.global_transform.basis.z
					var is_a := (absf(Vector2(tfwd.x, tfwd.z).normalized().dot(sig["axis"] as Vector2)) >= 0.65)
					if is_a and t >= 21.2 and t < 23.8:
						t = 23.8
					elif (not is_a) and t >= 8.5 and t < 15.0:
						t = 15.0
					break

		sig["timer"] = t
		_refresh_signal_visuals(sig)

	if cars.is_empty() or graph.edges.is_empty():
		return

	var edge_ids := graph.edges.keys()

	# 2. Step all Street Cars with Strict Signal Obedience & Full-Consist Tram Avoidance!
	for idx in range(cars.size()):
		var c: Dictionary = cars[idx]
		if bool(c["crashed"]):
			continue

		if (c["pos"] as Vector3).distance_squared_to(focus_pos) > 460.0 * 460.0:
			_respawn_car_near(c, graph, edge_ids, focus_pos, trams)
			continue

		var eid := int(c["edge_id"])
		if not graph.edges.has(eid):
			_respawn_car_near(c, graph, edge_ids, focus_pos, trams)
			continue

		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
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
				if _is_any_tram_occupying_point(trams, jp3_box, 14.5):
					if dist_to_end <= stop_line_d + 2.2:
						target_spd = 0.0

		# (C) Full-Consist & Crossing Tram Hard Protection (handles BOTH Front Cab & Rear Cab active_end == 1!)
		var emerg_stop := false
		var lat_guard := 4.85 if dist_to_end < 20.0 else 4.15
		for tr: Dictionary in trams:
			var secs_chk: Array = tr["tram_info"]["sections"]
			var tr_spd := float(tr.get("speed_mps", 0.0))
			var is_rear_lead := (int(tr["tram_info"].get("active_end", 0)) == 1)
			for sec: Node3D in secs_chk:
				if not is_instance_valid(sec):
					continue
				var dv_t := sec.global_position - c_pos
				var d2_t := dv_t.length_squared()
				if d2_t > 1225.0:
					continue
				var along_t := dv_t.dot(c_fwd)
				var lat_signed_t := dv_t.dot(c_right)
				var lat_t := absf(lat_signed_t)
				# 1. Any tram section in forward corridor (including close nose range -1.5..24m)
				if along_t > -1.5 and along_t < 24.0 and lat_t < lat_guard:
					target_spd = 0.0
					emerg_stop = true
					break
				# 2. Moving tram crossing perpendicularly toward car's path ahead (using TRUE travel direction!)
				var sec_fwd := sec.global_transform.basis.z if is_rear_lead else -sec.global_transform.basis.z
				var cross_dot := sec_fwd.dot(c_right)
				if tr_spd > 0.3 and along_t > -1.5 and along_t < 28.0 and lat_t < 18.0 and absf(cross_dot) > 0.30 and (lat_signed_t * cross_dot) < 0.0:
					target_spd = 0.0
					emerg_stop = true
					break
			if emerg_stop:
				break

		# (D) Never enter an intersection box if ANY tram is within 30m of that intersection!
		if dist_to_end >= stop_line_d - 3.2 and dist_to_end <= stop_line_d + 6.5:
			var np2_chk: Vector2 = graph.nodes[next_nid]["pos"]
			if _is_any_tram_occupying_point(trams, Vector3(np2_chk.x, 0.0, np2_chk.y), 30.0):
				target_spd = 0.0
				emerg_stop = true

		var cur_spd := float(c["speed"])
		var acc_rate := 32.0 if emerg_stop else (9.5 if target_spd < cur_spd else 3.2)
		cur_spd = move_toward(cur_spd, target_spd, acc_rate * dt)
		if emerg_stop:
			cur_spd = 0.0
		c["speed"] = cur_spd

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
			if not _would_car_invade_tram_shield(b_pos, b_fwd, trams, 1.85):
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
		var desired_lane := _compute_dynamic_lane_offset(graph, eid, s_now, elen, dir)
		c["lane_offset"] = move_toward(float(c["lane_offset"]), desired_lane, dt * 3.4)

		var s_next := s_now + dir * cur_spd * dt
		if (dir > 0.0 and s_next >= elen - 5.5) or (dir < 0.0 and s_next <= 5.5):
			var np2_adv: Vector2 = graph.nodes[next_nid]["pos"]
			if _is_any_tram_occupying_point(trams, Vector3(np2_adv.x, 0.0, np2_adv.y), 28.0):
				c["speed"] = 0.0
			else:
				_advance_car_to_next_edge(c, graph, next_nid, eid)
		else:
			# Hard invariant: never move a car into any tram's OBB + 1.85m safety shield!
			var fr_c := _edge_frame(graph, eid, s_next, elen, dir)
			var fwd_c: Vector3 = fr_c[1]
			var right_c := fwd_c.cross(Vector3.UP).normalized()
			var cand_pos := (fr_c[0] as Vector3) + right_c * float(c["lane_offset"])
			if _would_car_invade_tram_shield(cand_pos, fwd_c, trams, 1.85):
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
		mi2.global_transform = Transform3D(Basis.looking_at(c2["vis_fwd"], Vector3.UP), c2["vis_pos"])


static func _would_car_invade_tram_shield(car_pos: Vector3, car_fwd: Vector3, trams: Array[Dictionary], pad: float) -> bool:
	var c2 := Vector2(car_pos.x, car_pos.z)
	var cf2 := Vector2(car_fwd.x, car_fwd.z).normalized()
	for tr: Dictionary in trams:
		var tinfo: Dictionary = tr["tram_info"]
		var secs: Array = tinfo["sections"]
		var sec_hl := float(tinfo.get("section_len", 9.2)) * 0.5 + pad
		var sec_hw := float(tinfo.get("width", 2.6)) * 0.5 + pad
		for sec: Node3D in secs:
			if not is_instance_valid(sec):
				continue
			var spos := sec.global_position
			if spos.distance_squared_to(car_pos) > 120.0:
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
			if is_instance_valid(sec) and sec.global_position.distance_squared_to(pt) <= r2:
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
	var curve: Curve3D = tr.get("curve")
	var rlen := float(tr.get("route_len", 10.0))
	var is_loop := bool(tr.get("is_loop", false))
	var dir := float(tr.get("dir", 1.0))
	var sec_len := float(tr["tram_info"].get("section_len", 9.2))
	var nose_s := float(tr["s"]) + dir * (sec_len * 0.5)
	if curve == null or rlen < 5.0 or cars.is_empty():
		return {"has_hazard": false, "dist": 999.0}

	var d := 0.8
	while d <= max_lookahead:
		var s_probe := nose_s + dir * d
		if is_loop:
			s_probe = fposmod(s_probe, rlen)
		elif s_probe < 0.0 or s_probe > rlen:
			break
		var p3 := curve.sample_baked(s_probe, true)
		for c: Dictionary in cars:
			if bool(c["crashed"]):
				continue
			var cp: Vector3 = c["pos"]
			if p3.distance_squared_to(cp) <= 3.65 * 3.65:
				return {"has_hazard": true, "dist": d, "car": c}
		d += 1.5
	return {"has_hazard": false, "dist": 999.0}


func find_hazard_ahead_of_tram(tram_pos: Vector3, tram_fwd: Vector3, max_lookahead: float) -> Dictionary:
	var best_d := max_lookahead
	var best_car: Dictionary = {}
	var right_v := tram_fwd.cross(Vector3.UP).normalized()

	for c: Dictionary in cars:
		if bool(c["crashed"]):
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
				if spos.distance_squared_to(cpos) > 48.0:
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

	var candidates: Array[Dictionary] = []
	for nb: Dictionary in nbs:
		var cand_eid := int(nb["edge_id"])
		if cand_eid == prev_eid or float(nb["length"]) < 18.0:
			continue
		if _is_transit_mall_double_track(graph, cand_eid):
			continue
		candidates.append(nb)

	# Prefer going straight or gentle turn over sharp U-turn; if dead-end, do a smooth Bezier U-turn (never teleport!)
	var new_eid := prev_eid
	var new_dir := -float(c["dir"])
	if not candidates.is_empty():
		var chosen: Dictionary = candidates[_rng.randi() % candidates.size()]
		new_eid = int(chosen["edge_id"])
		var new_ed_c: Dictionary = graph.edges[new_eid]
		new_dir = 1.0 if int(new_ed_c["a"]) == at_node else -1.0

	var new_ed: Dictionary = graph.edges[new_eid]
	var new_len := float(new_ed["length"])
	var entry_s := 5.6 if new_dir > 0.0 else maxf(1.0, new_len - 5.6)
	var new_lane := _compute_dynamic_lane_offset(graph, new_eid, entry_s, new_len, new_dir)

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


func _respawn_car_near(c: Dictionary, graph: NetworkGraph, edge_ids: Array, focus_pos: Vector3, trams: Array[Dictionary]) -> void:
	var eid := _pick_spawn_edge(graph, edge_ids, focus_pos, true)
	if eid < 0:
		return
	var ed: Dictionary = graph.edges[eid]
	var elen := float(ed["length"])
	if elen < 26.0:
		return
	var new_dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var new_s := lerpf(11.0, elen - 11.0, _rng.randf())
	var smp := graph.sample_edge(eid, new_s / elen)
	var sp3: Vector3 = smp["pos"]
	if sp3.distance_squared_to(focus_pos) < 170.0 * 170.0:
		return
	if _is_any_tram_occupying_point(trams, sp3, 24.0):
		return
	c["edge_id"] = eid
	c["edge_len"] = elen
	c["dir"] = new_dir
	c["s"] = new_s
	c["turning"] = false
	c["lane_offset"] = _compute_dynamic_lane_offset(graph, eid, new_s, elen, new_dir)
	_update_car_transform(c, graph)


func _pick_spawn_edge(graph: NetworkGraph, edge_ids: Array, focus_pos: Vector3, near_focus: bool) -> int:
	for _attempt in range(18):
		var eid := int(edge_ids[_rng.randi() % edge_ids.size()])
		var ed: Dictionary = graph.edges[eid]
		if float(ed["length"]) < 26.0 or _is_transit_mall_double_track(graph, eid):
			continue
		if near_focus:
			var p2: Vector2 = (ed["pts"] as Array)[0]
			var d := Vector2(focus_pos.x, focus_pos.z).distance_to(p2)
			if d < 60.0 or d > 350.0:
				continue
		return eid
	return int(edge_ids[_rng.randi() % edge_ids.size()])


static func _is_transit_mall_double_track(graph: NetworkGraph, eid: int) -> bool:
	if not graph.built_tracks.has(eid):
		return false
	if int(graph.built_track_modes.get(eid, NetworkGraph.TrackMode.SINGLE)) != NetworkGraph.TrackMode.DOUBLE:
		return false
	var min_w := 14.2 if graph.get_edge_track_half_sep(eid) > 2.0 else 11.5
	return float(graph.edges[eid]["width"]) < min_w


static func _compute_dynamic_lane_offset(graph: NetworkGraph, eid: int, s_now: float, elen: float, car_dir: float) -> float:
	var base := _safe_motor_lane_offset(graph, eid)
	var bays: Array = graph.get_meta("station_bays", []) if graph.has_meta("station_bays") else []
	if bays.is_empty():
		return base
	var fr := _edge_frame(graph, eid, s_now, elen, car_dir)
	var center: Vector3 = fr[0]
	var right: Vector3 = (fr[1] as Vector3).cross(Vector3.UP).normalized()
	var off := base
	for bay: Dictionary in bays:
		var rel := center - (bay["pos"] as Vector3)
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
	if graph.built_tracks.has(eid):
		var sep := graph.get_edge_track_half_sep(eid)
		if sep > 2.0:
			return maxf(6.25, w * 0.40)
		if sep > 0.5:
			return maxf(4.95, w * 0.34)
		return maxf(3.85, w * 0.28)
	return clampf(w * 0.24, 2.35, 3.65)


static func _edge_side_has_station(graph: NetworkGraph, eid: int, car_dir: float) -> bool:
	if not graph.built_tracks.has(eid):
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
