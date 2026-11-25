class_name EbikeSim
extends Node3D

# Authentic Chinese Non-Motorized Bike-Lane Traffic (嘉兴电瓶车大军 / 外卖骑手 / 快递电动三轮 / 共享单车):
#   - 200 lively e-bikes, delivery couriers, cargo e-trikes & shared bikes (~4:1 ratio over cars!)
#   - Sculpted high-detail LOD0 (~4,200-5,600 tris: toroidal tires, spoked alloy rims, 8-10 seg tubular forks & frames,
#     curved fairings, mirrors, anatomical riders & smooth visored helmets) + LOD1 (~1,300-1,600 tris beyond 48m)
#   - Strict tram-mast avoidance (spatial grid of TrackBuilder mast_positions) so ZERO e-bikes ever clip a pole!
#   - Rendered via 10 LOD0 + 10 LOD1 MultiMeshInstance3D pools + 24m spatial grid for silky 60 FPS!

const MAX_EBIKES := 200
var _traffic_ref: TrafficSim = null
const VARIANT_COUNT := 10

var ebikes: Array[Dictionary] = []
var _meshes_lod0: Array[ArrayMesh] = []
var _meshes_lod1: Array[ArrayMesh] = []
var _mmis_lod0: Array[MultiMeshInstance3D] = []
var _mmis_lod1: Array[MultiMeshInstance3D] = []
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _bike_edges: Array[int] = []
var _bike_edge_grid: Dictionary = {} # Vector2i (160m cell) -> Array[int]
var _mast_grid: Dictionary = {}      # Vector2i (24m cell) -> Array[Vector2]
var _clear_idx: Dictionary = {}      # Cached TrackBuilder track_clear_idx so e-bikes NEVER overlap tram rails
var _tram_nodes: Dictionary = {}     # nid -> true for nodes touched by any surface built tram track
var _node_max_hw: Dictionary = {}    # nid -> max half-width of incident surface roads (for accurate stop lines!)


func _ready() -> void:
	_rng.randomize()
	_build_meshes()


func get_lod0_tri_count(var_idx: int = 0) -> int:
	if var_idx < 0 or var_idx >= _meshes_lod0.size() or _meshes_lod0[var_idx] == null:
		return 0
	var arrs := _meshes_lod0[var_idx].surface_get_arrays(0)
	return (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func get_lod1_tri_count(var_idx: int = 0) -> int:
	if var_idx < 0 or var_idx >= _meshes_lod1.size() or _meshes_lod1[var_idx] == null:
		return 0
	var arrs := _meshes_lod1[var_idx].surface_get_arrays(0)
	return (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func rebuild(graph: NetworkGraph, focus_pos: Vector3) -> void:
	for c in get_children():
		c.queue_free()
	ebikes.clear()
	_mmis_lod0.clear()
	_mmis_lod1.clear()
	_bike_edges.clear()
	_bike_edge_grid.clear()
	_tram_nodes.clear()
	_node_max_hw.clear()
	_clear_idx = graph.get_meta("track_clear_idx", {})
	_rebuild_mast_grid(graph)

	if not bool(graph.get_meta("is_chinese_city", false)):
		return
	if _meshes_lod0.is_empty():
		_build_meshes()

	# Precompute tram-crossed intersection nodes & maximum crossing road half-width per node
	for eid_v in graph.edges.keys():
		var eid0 := int(eid_v)
		var ed0: Dictionary = graph.edges[eid0]
		if bool(ed0.get("underground", false)):
			continue
		var hw0 := clampf(float(ed0.get("width", 10.0)) * 0.5, 4.0, 13.5)
		var na := int(ed0["a"])
		var nb := int(ed0["b"])
		_node_max_hw[na] = maxf(float(_node_max_hw.get(na, 4.5)), hw0)
		_node_max_hw[nb] = maxf(float(_node_max_hw.get(nb, 4.5)), hw0)
		if graph.built_tracks.has(eid0) and not graph.is_edge_grade_separated(eid0):
			_tram_nodes[na] = true
			_tram_nodes[nb] = true

	for eid_v in graph.edges.keys():
		var eid := int(eid_v)
		if _edge_allows_ebike(graph, eid):
			var ed: Dictionary = graph.edges[eid]
			_bike_edges.append(eid)
			var pts: Array = ed["pts"]
			var mp: Vector2 = pts[pts.size() / 2]
			var ck := Vector2i(int(floor(mp.x / 160.0)), int(floor(mp.y / 160.0)))
			if not _bike_edge_grid.has(ck):
				_bike_edge_grid[ck] = []
			(_bike_edge_grid[ck] as Array).append(eid)

	if _bike_edges.is_empty():
		return

	var target := mini(MAX_EBIKES, maxi(96, _bike_edges.size() / 2))
	var per_var_counts: Array[int] = []
	per_var_counts.resize(VARIANT_COUNT)
	per_var_counts.fill(0)

	for i in range(target):
		var eid := _pick_edge(graph, focus_pos, true, false)
		if eid < 0:
			continue
		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		if not _bike_dir_ok(graph, eid, dir):
			dir = -dir
		var pad_s := minf(16.0, elen * 0.30)
		var s_init := lerpf(pad_s, maxf(pad_s + 1.0, elen - pad_s), _rng.randf())
		var var_idx := _pick_variant_idx(i)
		var slot := per_var_counts[var_idx]
		per_var_counts[var_idx] = slot + 1

		var cruise := 5.6 + _rng.randf() * 1.8
		if var_idx == 5 or var_idx == 6:
			cruise = 6.8 + _rng.randf() * 1.7
		elif var_idx == 7:
			cruise = 5.0 + _rng.randf() * 1.3
		elif var_idx >= 8:
			cruise = 4.0 + _rng.randf() * 1.2

		var eb := {
			"var": var_idx,
			"slot": slot,
			"edge_id": eid,
			"dir": dir,
			"s": s_init,
			"speed": cruise * 0.8,
			"cruise": cruise,
			"lane_jitter": _rng.randf_range(-0.22, 0.22),
			"pos": Vector3.ZERO,
			"fwd": Vector3.FORWARD,
			"stuck_t": 0.0,
			"turning": false,
			"turn_s": 0.0,
			"turn_len": 1.0,
			"p0": Vector3.ZERO,
			"p1": Vector3.ZERO,
			"p2": Vector3.ZERO,
			"next_eid": eid,
			"next_dir": dir,
			"next_s": s_init,
			"bank": 0.0,
		}
		ebikes.append(eb)

	# Create paired LOD0 (0..52m) + LOD1 (48..220m) MultiMeshInstance3D pools per variant!
	for v in range(VARIANT_COUNT):
		var mmi0 := MultiMeshInstance3D.new()
		mmi0.name = "EbikePool_LOD0_%d" % v
		var mm0 := MultiMesh.new()
		mm0.transform_format = MultiMesh.TRANSFORM_3D
		mm0.mesh = _meshes_lod0[v]
		mm0.instance_count = per_var_counts[v]
		mmi0.multimesh = mm0
		mmi0.material_override = _mat
		mmi0.visibility_range_begin = 0.0
		mmi0.visibility_range_end = 52.0
		mmi0.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi0.extra_cull_margin = 5000.0
		add_child(mmi0)
		_mmis_lod0.append(mmi0)

		var mmi1 := MultiMeshInstance3D.new()
		mmi1.name = "EbikePool_LOD1_%d" % v
		var mm1 := MultiMesh.new()
		mm1.transform_format = MultiMesh.TRANSFORM_3D
		mm1.mesh = _meshes_lod1[v]
		mm1.instance_count = per_var_counts[v]
		mmi1.multimesh = mm1
		mmi1.material_override = _mat
		mmi1.visibility_range_begin = 48.0
		mmi1.visibility_range_end = 220.0
		mmi1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi1.extra_cull_margin = 5000.0
		add_child(mmi1)
		_mmis_lod1.append(mmi1)

	for eb: Dictionary in ebikes:
		_update_transform(eb, graph)


func _rebuild_mast_grid(graph: NetworkGraph) -> void:
	_mast_grid.clear()
	var mpts: Array = graph.get_meta("mast_positions", [])
	for mp_v in mpts:
		if mp_v is Vector2:
			var mp: Vector2 = mp_v
			var ck := Vector2i(int(floor(mp.x / 24.0)), int(floor(mp.y / 24.0)))
			if not _mast_grid.has(ck):
				_mast_grid[ck] = []
			(_mast_grid[ck] as Array).append(mp)


func step(dt: float, graph: NetworkGraph, traffic: TrafficSim, trams: Array[Dictionary], focus_pos: Vector3) -> void:
	if ebikes.is_empty() or _bike_edges.is_empty():
		return
	_traffic_ref = traffic
	var dt_c := minf(dt, 0.05)

	# Keep mast spatial index fresh if tracks were rebuilt after initial spawn
	if _mast_grid.is_empty() and not (graph.get_meta("mast_positions", []) as Array).is_empty():
		_rebuild_mast_grid(graph)

	var grid: Dictionary = {}
	for i in range(ebikes.size()):
		var p: Vector3 = ebikes[i]["pos"]
		var ck := Vector2i(int(floor(p.x / 24.0)), int(floor(p.z / 24.0)))
		if not grid.has(ck):
			grid[ck] = []
		(grid[ck] as Array).append(i)

	for i in range(ebikes.size()):
		var eb: Dictionary = ebikes[i]
		var pos: Vector3 = eb["pos"]
		# Only recycle e-bikes well outside the visible camera radius (365m) and spawn in the outer horizon ring!
		if pos.distance_squared_to(focus_pos) > 365.0 * 365.0:
			_respawn(eb, graph, focus_pos, trams)
			continue

		# --- A. Smooth Quadratic-Bezier Intersection Turn / Crossing (zero 1-frame snapping & never freeze on rails!) ---
		if bool(eb.get("turning", false)):
			var t_spd := move_toward(float(eb["speed"]), maxf(4.6, float(eb["cruise"]) * 0.78), 4.2 * dt_c)
			eb["speed"] = t_spd
			var ts_next := float(eb["turn_s"]) + t_spd * dt_c
			var t_len := maxf(1.0, float(eb["turn_len"]))
			if ts_next >= t_len and eb.has("stage2"):
				# First half of a two-stage left turn done: wait at the far corner, facing the new street
				eb["turning"] = false
				eb["waiting2"] = true
				eb["speed"] = 0.0
				continue
			if ts_next >= t_len:
				eb["turning"] = false
				eb["edge_id"] = int(eb["next_eid"])
				eb["dir"] = float(eb["next_dir"])
				eb["s"] = float(eb["next_s"])
				eb["bank"] = move_toward(float(eb.get("bank", 0.0)), 0.0, dt_c * 3.0)
				_update_transform(eb, graph)
			else:
				eb["turn_s"] = ts_next
				_update_turning_transform(eb, ts_next / t_len, dt_c)
			continue

		if bool(eb.get("waiting2", false)):
			_step_two_stage_wait(eb, graph, traffic, trams, dt_c)
			continue

		var eid := int(eb["edge_id"])
		if not graph.edges.has(eid):
			_respawn(eb, graph, focus_pos, trams)
			continue
		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
		var dir := float(eb["dir"])
		var s_now := float(eb["s"])
		var dist_end := (elen - s_now) if dir > 0.0 else s_now
		var next_nid := int(ed["b"]) if dir > 0.0 else int(ed["a"])
		var fwd: Vector3 = eb["fwd"]
		var right := fwd.cross(Vector3.UP).normalized()

		# Compute accurate stop line strictly BEHIND the crosswalk & crossing carriageway (especially 24m tram boulevards!)
		var cross_hw := float(_node_max_hw.get(next_nid, 6.0))
		var is_tram_xing := _tram_nodes.has(next_nid) and not graph.built_tracks.has(eid)
		var stop_d := clampf(cross_hw + (3.2 if is_tram_xing else 2.2), 7.5, minf(16.5, elen * 0.42))
		var corner_r := clampf(cross_hw + 0.4, 4.5, minf(12.5, elen * 0.38))

		if int(eb.get("plan_nid", -1)) != next_nid and dist_end < stop_d + 14.0:
			eb["plan"] = _choose_next(eb, graph, next_nid, eid)
			eb["plan_nid"] = next_nid

		var target_spd := float(eb["cruise"])
		if dist_end < stop_d + 6.0 and dist_end > corner_r:
			target_spd = minf(target_spd, 4.6)

		# 1) Same-direction e-bike spacing via 24m spatial grid
		var cx := int(floor(pos.x / 24.0))
		var cz := int(floor(pos.z / 24.0))
		var lead_stopped_ahead := false
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var bucket: Array = grid.get(Vector2i(cx + dx, cz + dz), [])
				for j_v in bucket:
					var j := int(j_v)
					if j == i:
						continue
					var oth: Dictionary = ebikes[j]
					if fwd.dot(oth["fwd"] as Vector3) < 0.35:
						continue
					var dv := (oth["pos"] as Vector3) - pos
					if dv.length_squared() > 48.0:
						continue
					var along := dv.dot(fwd)
					var lat := absf(dv.dot(right))
					if along > 0.2 and lat < 0.90:
						if along < 2.9:
							target_spd = 0.0
							lead_stopped_ahead = true
						elif along < 6.5:
							target_spd = minf(target_spd, float(oth["speed"]) * 0.88)

		# 2) Obey intersection traffic signals cleanly BEHIND stop_d (never creeping into the crosswalk!)
		if dist_end >= stop_d - 1.0 and dist_end <= stop_d + 11.0 and traffic.signals.has(next_nid):
			var aspect := traffic.get_signal_aspect(next_nid, Vector2(fwd.x, fwd.z))
			if aspect != "green":
				target_spd = 0.0 if dist_end <= stop_d + 1.5 else minf(target_spd, maxf(0.0, (dist_end - stop_d) * 0.55))

		# 3) Proactive Tram-Crossing Protection: stop strictly BEHIND stop_d whenever ANY tram approaches a tram intersection!
		#    NEVER brake to 0 inside the crossing box itself — if already past stop_d, accelerate cleanly across!
		if is_tram_xing and dist_end >= stop_d - 1.2 and dist_end <= stop_d + 16.0:
			var tram_approaching := _tram_near_node(graph, next_nid, trams)
			if tram_approaching or lead_stopped_ahead:
				target_spd = 0.0 if dist_end <= stop_d + 1.8 else minf(target_spd, maxf(0.0, (dist_end - stop_d) * 0.52))
		elif is_tram_xing and dist_end < stop_d - 1.2:
			# Already committed past the stop line: keep moving cleanly so we NEVER stop on top of the tram tracks!
			target_spd = maxf(target_spd, 5.4)

		var spd := move_toward(float(eb["speed"]), target_spd, (7.8 if target_spd < float(eb["speed"]) else 3.4) * dt_c)
		eb["speed"] = spd

		var st_t := (float(eb.get("stuck_t", 0.0)) + dt_c) if spd < 0.15 else 0.0
		eb["stuck_t"] = st_t
		# Only recycle truly stuck e-bikes if far from the camera (never pop/vanish right in front of the player!)
		if st_t >= 45.0 and pos.distance_squared_to(focus_pos) > 135.0 * 135.0:
			_respawn(eb, graph, focus_pos, trams)
			continue

		var s_next := s_now + dir * spd * dt_c
		var reached_end := (s_next >= elen - corner_r) if dir > 0.0 else (s_next <= corner_r)
		if reached_end:
			if int(eb.get("plan_nid", -1)) == next_nid and bool((eb["plan"] as Dictionary).get("two_stage", false)):
				_begin_two_stage_left(eb, graph, next_nid)
			else:
				_begin_smooth_turn(eb, graph, next_nid, eid, focus_pos, trams)
		else:
			eb["s"] = s_next
			eb["bank"] = move_toward(float(eb.get("bank", 0.0)), 0.0, dt_c * 3.0)
			_update_transform(eb, graph)


func _edge_allows_ebike(graph: NetworkGraph, eid: int) -> bool:
	if not graph.edges.has(eid):
		return false
	var ed: Dictionary = graph.edges[eid]
	if bool(ed.get("underground", false)):
		return false
	# Skip suppressed twin-carriageway ghost strips (lanes_f == 0 and lanes_b == 0)
	if int(ed.get("lanes_f", 1)) + int(ed.get("lanes_b", 1)) <= 0:
		return false
	var elen := float(ed.get("length", 0.0))
	var w := float(ed.get("width", 10.0))
	if w < 8.0 or elen < 22.0:
		return false
	var hw := clampf(w * 0.5, 4.0, 13.5)
	if graph.built_tracks.has(eid):
		# Only permit bike lanes on wide tram boulevards with full clearance outside the tram dynamic envelope!
		var tram_half := graph.get_edge_track_half_sep(eid)
		if hw < tram_half + 3.55:
			return false
	# Also ensure the outer bike-lane path is clear of any nearby/curved tram tracks in _clear_idx
	if not _clear_idx.is_empty():
		var pts: Array = ed["pts"]
		if pts.size() >= 2:
			var bl_w := 2.05 if hw >= 5.75 else (1.55 if hw >= 4.8 else 1.25)
			var lat_chk := maxf(2.2, hw - bl_w * 0.52)
			var p0: Vector2 = pts[0]
			var p1: Vector2 = pts[pts.size() - 1]
			var d := p1 - p0
			if d.length_squared() > 1.0:
				var nrm := Vector2(-d.y, d.x).normalized()
				var mid := pts[pts.size() / 2] as Vector2
				var clr_r := TrackBuilder.track_clearance_dist(_clear_idx, mid + nrm * lat_chk)
				var clr_l := TrackBuilder.track_clearance_dist(_clear_idx, mid - nrm * lat_chk)
				if clr_r < 2.35 or clr_l < 2.35:
					return false
	return true


# Bikes keep to the kerb-side lane, so on a one-way carriageway they ride with the traffic
static func _bike_dir_ok(graph: NetworkGraph, eid: int, dir: float) -> bool:
	var ed: Dictionary = graph.edges[eid]
	var lf := int(ed.get("lanes_f", 1))
	var lb := int(ed.get("lanes_b", 1))
	if (lf > 0) == (lb > 0):
		return true
	return (dir > 0.0) == (lf > 0)


func _edge_lane_pose(graph: NetworkGraph, eid: int, s: float, dir: float, jitter: float) -> Array:
	var ed: Dictionary = graph.edges[eid]
	var elen := maxf(1.0, float(ed["length"]))
	var hw := clampf(float(ed.get("width", 10.0)) * 0.5, 4.0, 13.5)
	var bl_w := 2.05 if hw >= 5.75 else (1.55 if hw >= 4.8 else 1.25)
	var lat_off := maxf(2.2, hw - bl_w * 0.52) + jitter * (1.0 if hw >= 5.75 else 0.55)
	if graph.built_tracks.has(eid):
		lat_off = clampf(lat_off, graph.get_edge_track_half_sep(eid) + 2.55, hw - 0.45)
	var fr := TrafficSim._edge_frame(graph, eid, clampf(s, 0.0, elen), elen, dir)
	var center: Vector3 = fr[0]
	var fwd: Vector3 = fr[1]
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() >= 1e-5 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	if graph.built_tracks.has(eid) and not _clear_idx.is_empty():
		# Ride in the middle of the (narrowed) non-motorised lane painted outside the tram-clear motor lane
		var inner_abs := hw - bl_w
		var p_in := center + right * inner_abs
		var d_in := TrackBuilder.track_clearance_dist(_clear_idx, Vector2(p_in.x, p_in.z))
		inner_abs += maxf(0.0, NetworkGraph.BIKE_TRACK_CLEAR - d_in)
		lat_off = clampf((inner_abs + hw - 0.14) * 0.5 + jitter * 0.15, inner_abs + 0.35, hw - 0.45)
	var pos := _nudge_clear_of_masts(center + right * lat_off, right)
	pos.y = 0.055 + (Terrain.surface(pos.x, pos.z) if Terrain.active else 0.0)
	return [pos, fwd]


func _begin_smooth_turn(eb: Dictionary, graph: NetworkGraph, at_nid: int, prev_eid: int, focus_pos: Vector3, trams: Array[Dictionary]) -> void:
	var cands: Array[Dictionary] = []
	var prev_fwd: Vector3 = eb["fwd"]
	var best_straight: Dictionary = {}
	var best_dot := -2.0
	for link in graph.adj.get(at_nid, []):
		var ne := int(link["edge_id"])
		if ne == prev_eid or not _edge_allows_ebike(graph, ne):
			continue
		var ed: Dictionary = graph.edges[ne]
		var ndir := 1.0 if int(ed["a"]) == at_nid else -1.0
		if not _bike_dir_ok(graph, ne, ndir):
			continue # one-way carriageway: its only bike lane runs with the traffic
		var pts: Array = ed["pts"]
		var p0: Vector2 = pts[0] if ndir > 0.0 else pts[pts.size() - 1]
		var p1: Vector2 = pts[1] if ndir > 0.0 else pts[pts.size() - 2]
		var nf := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y).normalized()
		var dp := prev_fwd.dot(nf)
		# Never pick sharp hairpins (< -0.35) that look unnatural
		if dp < -0.35:
			continue
		var item := {"eid": ne, "dir": ndir, "len": float(ed["length"]), "dot": dp}
		cands.append(item)
		if dp > best_dot:
			best_dot = dp
			best_straight = item

	if cands.is_empty():
		# Dead-end street: silently recycle out at the far horizon ring (only if >125m away, else gentle U-turn arc)
		if (eb["pos"] as Vector3).distance_squared_to(focus_pos) > 125.0 * 125.0:
			_respawn(eb, graph, focus_pos, trams)
			return
		var ed0: Dictionary = graph.edges[prev_eid]
		var ndir0 := -float(eb["dir"])
		var el0 := float(ed0["length"])
		var ent0 := minf(8.0, el0 * 0.35)
		var ns0 := ent0 if ndir0 > 0.0 else (el0 - ent0)
		var end_pose0 := _edge_lane_pose(graph, prev_eid, ns0, ndir0, float(eb.get("lane_jitter", 0.0)))
		var p0_u: Vector3 = eb["pos"]
		var p2_u: Vector3 = end_pose0[0]
		var p1_u := (p0_u + p2_u) * 0.5 + prev_fwd * 4.5
		eb["turning"] = true
		eb["p0"] = p0_u
		eb["p1"] = p1_u
		eb["p2"] = p2_u
		eb["turn_len"] = maxf(3.0, p0_u.distance_to(p1_u) + p1_u.distance_to(p2_u))
		eb["turn_s"] = 0.0
		eb["next_eid"] = prev_eid
		eb["next_dir"] = ndir0
		eb["next_s"] = ns0
		return

	# Strongly prefer straight-through (80%) or smooth right/left turn onto wide bike avenues
	var pick: Dictionary = best_straight if (best_dot > 0.60 and _rng.randf() < 0.80) else cands[_rng.randi() % cands.size()]
	if int(eb.get("plan_nid", -1)) == at_nid:
		var pl: Dictionary = eb["plan"]
		for cd: Dictionary in cands:
			if int(cd["eid"]) == int(pl.get("eid", -1)):
				pick = cd
	eb["plan_nid"] = -1
	var next_eid := int(pick["eid"])
	var next_dir := float(pick["dir"])
	var next_len := float(pick["len"])
	var cross_hw := float(_node_max_hw.get(at_nid, 6.0))
	var enter_r := clampf(cross_hw + 0.4, 4.5, minf(12.5, next_len * 0.38))
	var next_s := enter_r if next_dir > 0.0 else (next_len - enter_r)
	var end_pose := _edge_lane_pose(graph, next_eid, next_s, next_dir, float(eb.get("lane_jitter", 0.0)))
	var p0_b: Vector3 = eb["pos"]
	var p2_b: Vector3 = end_pose[0]
	var f2_b: Vector3 = end_pose[1]
	# Compute natural smooth quadratic-Bezier corner control point p1 along exit & entry tangents
	var chord := p0_b.distance_to(p2_b)
	var p1_b := (p0_b + p2_b) * 0.5
	if float(pick["dot"]) < 0.85 and chord > 1.5:
		var reach := clampf(chord * 0.42, 2.0, 12.0)
		p1_b = ((p0_b + prev_fwd * reach) + (p2_b - f2_b * reach)) * 0.5
	p1_b.y = (p0_b.y + p2_b.y) * 0.5
	var arc_est := maxf(1.5, 0.5 * chord + 0.5 * (p0_b.distance_to(p1_b) + p1_b.distance_to(p2_b)))
	eb["turning"] = true
	eb["p0"] = p0_b
	eb["p1"] = p1_b
	eb["p2"] = p2_b
	eb["turn_len"] = arc_est
	eb["turn_s"] = 0.0
	eb["next_eid"] = next_eid
	eb["next_dir"] = next_dir
	eb["next_s"] = next_s


# The move an e-bike will make at `at_nid` (picked ahead of the stop line). A left turn across tram tracks at
# a signalled junction is flagged two_stage: e-bikes then turn left in two stages (二次过街) instead of
# cutting across the tracks while the tram has its straight-ahead green.
func _choose_next(eb: Dictionary, graph: NetworkGraph, at_nid: int, prev_eid: int) -> Dictionary:
	var prev_fwd: Vector3 = eb["fwd"]
	var right := prev_fwd.cross(Vector3.UP).normalized()
	var cands: Array[Dictionary] = []
	var best_straight: Dictionary = {}
	var best_dot := -2.0
	for link in graph.adj.get(at_nid, []):
		var ne := int(link["edge_id"])
		if ne == prev_eid or not _edge_allows_ebike(graph, ne):
			continue
		var ed: Dictionary = graph.edges[ne]
		var ndir := 1.0 if int(ed["a"]) == at_nid else -1.0
		if not _bike_dir_ok(graph, ne, ndir):
			continue
		var pts: Array = ed["pts"]
		var p0: Vector2 = pts[0] if ndir > 0.0 else pts[pts.size() - 1]
		var p1: Vector2 = pts[1] if ndir > 0.0 else pts[pts.size() - 2]
		var nf := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y).normalized()
		var dp := prev_fwd.dot(nf)
		if dp < -0.35:
			continue
		var item := {"eid": ne, "dir": ndir, "dot": dp, "nf": nf, "left": nf.dot(right) < -0.35 and dp < 0.6}
		cands.append(item)
		if dp > best_dot:
			best_dot = dp
			best_straight = item
	if cands.is_empty():
		return {}
	var pick: Dictionary = best_straight if (best_dot > 0.60 and _rng.randf() < 0.80) else cands[_rng.randi() % cands.size()]
	if bool(pick["left"]) and _tram_nodes.has(at_nid) and _traffic_ref != null and _traffic_ref.signals.has(at_nid):
		var crosses_tracks := graph.built_tracks.has(prev_eid)
		if not crosses_tracks:
			for link2 in graph.adj.get(at_nid, []):
				var e2 := int(link2["edge_id"])
				if e2 != prev_eid and e2 != int(pick["eid"]) and graph.built_tracks.has(e2):
					var ed2: Dictionary = graph.edges[e2]
					var pts2: Array = ed2["pts"]
					var q0: Vector2 = pts2[0] if int(ed2["a"]) == at_nid else pts2[pts2.size() - 1]
					var q1: Vector2 = pts2[1] if int(ed2["a"]) == at_nid else pts2[pts2.size() - 2]
					# the tram street straight ahead is crossed by a left turn's far half
					if Vector3(q1.x - q0.x, 0.0, q1.y - q0.y).normalized().dot(prev_fwd) > 0.6:
						crosses_tracks = true
		pick["two_stage"] = crosses_tracks
	return pick


func _tram_near_node(graph: NetworkGraph, nid: int, trams: Array[Dictionary]) -> bool:
	var np2: Vector2 = graph.nodes[nid]["pos"]
	var node_pos := Vector3(np2.x, 0.0, np2.y)
	for tr: Dictionary in trams:
		var tp: Vector3 = tr.get("pos", Vector3.ZERO)
		var to_node := node_pos - Vector3(tp.x, 0.0, tp.z)
		var d2_n := to_node.length_squared()
		if d2_n < 28.0 * 28.0:
			return true
		if d2_n < 68.0 * 68.0:
			var tf: Vector3 = tr.get("fwd", Vector3.FORWARD)
			if to_node.normalized().dot(Vector3(tf.x, 0.0, tf.z).normalized()) > 0.25:
				return true
		# Also check trailing sections of long 5-module trams occupying the crossing!
		var secs_t: Array = tr.get("tram_info", {}).get("sections", [])
		for sc_n in secs_t:
			if is_instance_valid(sc_n):
				var sp: Vector3 = (sc_n as Node3D).global_position
				if Vector2(sp.x - np2.x, sp.z - np2.y).length_squared() < 24.0 * 24.0:
					return true
	return false


# Stage 1 of a two-stage left turn: ride straight across on our own green to the far-side corner
func _begin_two_stage_left(eb: Dictionary, graph: NetworkGraph, at_nid: int) -> void:
	var pl: Dictionary = eb["plan"]
	eb["plan_nid"] = -1
	var np2: Vector2 = graph.nodes[at_nid]["pos"]
	var node_pos := Vector3(np2.x, 0.0, np2.y)
	var fwd: Vector3 = eb["fwd"]
	var right := fwd.cross(Vector3.UP).normalized()
	var p0: Vector3 = eb["pos"]
	var lat := (p0 - node_pos).dot(right)
	var hw_x := clampf(float(graph.edges[int(pl["eid"])]["width"]) * 0.5, 3.0, 13.5)
	var w := node_pos + fwd * (hw_x + 1.6) + right * lat
	w.y = p0.y
	eb["turning"] = true
	eb["p0"] = p0
	eb["p1"] = (p0 + w) * 0.5
	eb["p2"] = w
	eb["turn_len"] = maxf(1.5, p0.distance_to(w))
	eb["turn_s"] = 0.0
	eb["stage2"] = {"nid": at_nid, "eid": int(pl["eid"]), "dir": float(pl["dir"]), "nf": pl["nf"]}


# Stage 2: wait at the corner facing the new street; go once that street has green and no tram is near
func _step_two_stage_wait(eb: Dictionary, graph: NetworkGraph, traffic: TrafficSim, trams: Array[Dictionary], dt: float) -> void:
	var st2: Dictionary = eb["stage2"]
	var nf: Vector3 = st2["nf"]
	var pos: Vector3 = eb["pos"]
	var fwd := (eb["fwd"] as Vector3).slerp(nf, minf(1.0, dt * 3.0)).normalized()
	eb["fwd"] = fwd
	_write_mm_transform(eb, Transform3D(Basis.looking_at(fwd, Vector3.UP), pos))
	var nid := int(st2["nid"])
	var go := traffic.get_signal_aspect(nid, Vector2(nf.x, nf.z)) == "green" and not _tram_near_node(graph, nid, trams)
	if not go:
		return
	var next_eid := int(st2["eid"])
	var next_dir := float(st2["dir"])
	var next_len := float(graph.edges[next_eid]["length"])
	var cross_hw := float(_node_max_hw.get(nid, 6.0))
	var enter_r := clampf(cross_hw + 0.4, 4.5, minf(12.5, next_len * 0.38))
	var next_s := enter_r if next_dir > 0.0 else (next_len - enter_r)
	var end_pose := _edge_lane_pose(graph, next_eid, next_s, next_dir, float(eb.get("lane_jitter", 0.0)))
	var p2: Vector3 = end_pose[0]
	eb.erase("stage2")
	eb["waiting2"] = false
	eb["turning"] = true
	eb["p0"] = pos
	eb["p1"] = (pos + p2) * 0.5
	eb["p2"] = p2
	eb["turn_len"] = maxf(1.5, pos.distance_to(p2))
	eb["turn_s"] = 0.0
	eb["next_eid"] = next_eid
	eb["next_dir"] = next_dir
	eb["next_s"] = next_s


func _update_turning_transform(eb: Dictionary, u_raw: float, dt: float) -> void:
	var u := clampf(u_raw, 0.0, 1.0)
	var omt := 1.0 - u
	var p0: Vector3 = eb["p0"]
	var p1: Vector3 = eb["p1"]
	var p2: Vector3 = eb["p2"]
	var pos := p0 * (omt * omt) + p1 * (2.0 * omt * u) + p2 * (u * u)
	var tang := (p1 - p0) * (2.0 * omt) + (p2 - p1) * (2.0 * u)
	tang.y = 0.0
	var old_fwd: Vector3 = eb["fwd"]
	var new_fwd := tang.normalized() if tang.length_squared() > 1e-5 else old_fwd
	var fwd := old_fwd.slerp(new_fwd, minf(1.0, dt * 10.0)).normalized()
	# Subtle realistic lean into turns (~6 deg max)
	var turn_cross := old_fwd.cross(new_fwd).y
	var target_bank := clampf(-turn_cross * 0.45, -0.11, 0.11)
	var bank := move_toward(float(eb.get("bank", 0.0)), target_bank, dt * 2.4)
	eb["bank"] = bank
	pos.y = 0.055 + (Terrain.surface(pos.x, pos.z) if Terrain.active else 0.0)
	eb["pos"] = pos
	eb["fwd"] = fwd
	var basis := Basis.looking_at(fwd, Vector3.UP)
	if absf(bank) > 0.002:
		basis = basis.rotated(fwd, bank)
	_write_mm_transform(eb, Transform3D(basis, pos))


func _respawn(eb: Dictionary, graph: NetworkGraph, focus_pos: Vector3, trams: Array[Dictionary] = []) -> void:
	var eid := _pick_edge(graph, focus_pos, true, true, trams)
	if eid < 0:
		return
	var ed: Dictionary = graph.edges[eid]
	var elen := float(ed["length"])
	var pad_s := minf(16.0, elen * 0.30)
	eb["turning"] = false
	eb["waiting2"] = false
	eb.erase("stage2")
	eb["plan_nid"] = -1
	eb["bank"] = 0.0
	eb["edge_id"] = eid
	eb["dir"] = 1.0 if _rng.randf() < 0.5 else -1.0
	if not _bike_dir_ok(graph, eid, float(eb["dir"])):
		eb["dir"] = -float(eb["dir"])
	eb["s"] = lerpf(pad_s, maxf(pad_s + 1.0, elen - pad_s), _rng.randf())
	eb["speed"] = float(eb["cruise"]) * 0.80
	eb["stuck_t"] = 0.0
	_update_transform(eb, graph)


func _pick_edge(graph: NetworkGraph, focus_pos: Vector3, near: bool, outer_ring_only: bool = false, trams: Array[Dictionary] = []) -> int:
	if _bike_edges.is_empty():
		return -1
	if near:
		var fx := int(floor(focus_pos.x / 160.0))
		var fz := int(floor(focus_pos.z / 160.0))
		var local_cands: Array[int] = []
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for eid_v in _bike_edge_grid.get(Vector2i(fx + dx, fz + dz), []):
					local_cands.append(int(eid_v))
		if not local_cands.is_empty():
			var min_d2 := (145.0 * 145.0) if outer_ring_only else 0.0
			var max_d2 := 345.0 * 345.0
			for _k in range(28):
				var cand := local_cands[_rng.randi() % local_cands.size()]
				var pts: Array = graph.edges[cand]["pts"]
				var mp: Vector2 = pts[pts.size() / 2]
				var d2 := Vector2(mp.x - focus_pos.x, mp.y - focus_pos.z).length_squared()
				if d2 < min_d2 or d2 > max_d2:
					continue
				var near_tram := false
				for tr: Dictionary in trams:
					var tp: Vector3 = tr.get("pos", Vector3.ZERO)
					if Vector2(mp.x - tp.x, mp.y - tp.z).length_squared() < 28.0 * 28.0:
						near_tram = true
						break
				if not near_tram:
					return cand
			# Fallback inside local_cands preferring the farthest edge from camera (never pop-in close!)
			if outer_ring_only:
				var best_c := local_cands[0]
				var best_d := -1.0
				for _m in range(12):
					var c2 := local_cands[_rng.randi() % local_cands.size()]
					var pts2: Array = graph.edges[c2]["pts"]
					var mp2: Vector2 = pts2[pts2.size() / 2]
					var dd := Vector2(mp2.x - focus_pos.x, mp2.y - focus_pos.z).length_squared()
					if dd <= max_d2 and dd > best_d:
						best_d = dd
						best_c = c2
				return best_c
			return local_cands[_rng.randi() % local_cands.size()]
	return _bike_edges[_rng.randi() % _bike_edges.size()]


func _write_mm_transform(eb: Dictionary, tf: Transform3D) -> void:
	# never hand the GPU a non-finite instance (a NaN/inf basis renders as screen-filling slivers)
	if not tf.is_finite():
		return
	var v := int(eb["var"])
	var slot := int(eb["slot"])
	if v >= 0 and v < _mmis_lod0.size():
		var mm0 := _mmis_lod0[v].multimesh
		if mm0 != null and slot < mm0.instance_count:
			mm0.set_instance_transform(slot, tf)
		var mm1 := _mmis_lod1[v].multimesh
		if mm1 != null and slot < mm1.instance_count:
			mm1.set_instance_transform(slot, tf)


func _nudge_clear_of_masts(pos: Vector3, right: Vector3) -> Vector3:
	if _mast_grid.is_empty():
		return pos
	var p2 := Vector2(pos.x, pos.z)
	var cx := int(floor(p2.x / 24.0))
	var cz := int(floor(p2.y / 24.0))
	var best_push := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for mp: Vector2 in _mast_grid.get(Vector2i(cx + dx, cz + dz), []):
				var dv := p2 - mp
				var d := dv.length()
				if d < 1.15:
					var r2 := Vector2(right.x, right.z)
					var side_sign := -1.0 if dv.dot(r2) < 0.0 else 1.0
					var need := (1.18 - d) * side_sign
					if absf(need) > absf(best_push):
						best_push = need
	return pos + right * best_push if absf(best_push) > 0.001 else pos


func _update_transform(eb: Dictionary, graph: NetworkGraph) -> void:
	var eid := int(eb["edge_id"])
	var pose := _edge_lane_pose(graph, eid, float(eb["s"]), float(eb["dir"]), float(eb.get("lane_jitter", 0.0)))
	var pos: Vector3 = pose[0]
	var fwd: Vector3 = pose[1]
	eb["pos"] = pos
	eb["fwd"] = fwd
	_write_mm_transform(eb, Transform3D(Basis.looking_at(fwd, Vector3.UP), pos))


func _pick_variant_idx(i: int) -> int:
	var r := i % 20
	if r in [0, 5, 11]:
		return 0 # 雅迪/九号 Pearl-White
	if r in [1, 8, 15]:
		return 1 # 爱玛 Mint-Green
	if r in [2, 12]:
		return 2 # 小牛 Matte-Black
	if r in [3, 14]:
		return 3 # 复古奶白/粉女士小电驴 (+ woven front basket)
	if r in [4, 17]:
		return 4 # 深蓝通勤电瓶车 (+ curved windshield)
	if r in [6, 13]:
		return 5 # 美团外卖骑手 (Yellow!)
	if r in [7, 16]:
		return 6 # 饿了么外卖骑手 (Blue!)
	if r in [9, 18]:
		return 7 # 顺丰/快递电动三轮车
	if r == 10:
		return 8 # 哈啰蓝共享单车
	return 9     # 美团黄共享单车


func _build_meshes() -> void:
	# Reuse vehicle_pbr.gdshader so scooter fairings & helmets get automotive clearcoat,
	# windshields get Fresnel glass, tires get matte rubber + alloy rims, and LED lamps glow!
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/vehicle_pbr.gdshader") as Shader
	_meshes_lod0.clear()
	_meshes_lod1.clear()

	var sc_specs: Array[Array] = [
		[Color(0.92, 0.93, 0.94), Color(0.24, 0.34, 0.46), Color(0.90, 0.24, 0.20), false, Color.BLACK, false, false],
		[Color(0.56, 0.80, 0.72), Color(0.86, 0.82, 0.76), Color(0.96, 0.82, 0.36), false, Color.BLACK, false, false],
		[Color(0.16, 0.17, 0.19), Color(0.20, 0.22, 0.25), Color(0.88, 0.18, 0.16), false, Color.BLACK, false, false],
		[Color(0.94, 0.78, 0.82), Color(0.92, 0.90, 0.86), Color(0.94, 0.82, 0.86), false, Color.BLACK, true, false],
		[Color(0.22, 0.36, 0.54), Color(0.32, 0.36, 0.40), Color(0.18, 0.20, 0.24), false, Color.BLACK, false, true],
		[Color(0.18, 0.18, 0.20), Color(0.98, 0.78, 0.06), Color(0.98, 0.78, 0.06), true, Color(0.98, 0.78, 0.06), false, false],
		[Color(0.20, 0.22, 0.25), Color(0.06, 0.56, 0.94), Color(0.06, 0.56, 0.94), true, Color(0.06, 0.56, 0.94), false, false],
	]
	for sp: Array in sc_specs:
		_meshes_lod0.append(_make_scooter_mesh(sp[0], sp[1], sp[2], sp[3], sp[4], sp[5], sp[6], false))
		_meshes_lod1.append(_make_scooter_mesh(sp[0], sp[1], sp[2], sp[3], sp[4], sp[5], sp[6], true))
	# 7: 顺丰/快递电动三轮车
	_meshes_lod0.append(_make_etrike_mesh(false))
	_meshes_lod1.append(_make_etrike_mesh(true))
	# 8: 哈啰蓝共享单车
	_meshes_lod0.append(_make_shared_bike_mesh(Color(0.08, 0.58, 0.92), Color(0.86, 0.88, 0.90), false))
	_meshes_lod1.append(_make_shared_bike_mesh(Color(0.08, 0.58, 0.92), Color(0.86, 0.88, 0.90), true))
	# 9: 美团黄共享单车
	_meshes_lod0.append(_make_shared_bike_mesh(Color(0.96, 0.78, 0.08), Color(0.26, 0.30, 0.36), false))
	_meshes_lod1.append(_make_shared_bike_mesh(Color(0.96, 0.78, 0.08), Color(0.26, 0.30, 0.36), true))


static func _pbr(c: Color, mat_id: int) -> Color:
	return Color(c.r, c.g, c.b, float(mat_id) * 0.1)


static func _make_scooter_mesh(
	body_rgb: Color, jacket_rgb: Color, helmet_rgb: Color,
	has_box: bool, box_rgb: Color, has_basket: bool, has_shield: bool, lod1: bool
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Material IDs for vehicle_pbr.gdshader: 0=clearcoat paint, 1=glass/visor, 2=tire/alloy, 3=chrome/grille, 4=LED head, 5=ruby tail, 7=matte cloth/leather, 8=matte skin/hair, 9=satin plastic trim
	var c_body := _pbr(body_rgb, 0)
	var c_helm := _pbr(helmet_rgb, 0)
	var c_glass := _pbr(Color(0.08, 0.14, 0.20), 1)
	var c_tire := _pbr(Color(0.09, 0.09, 0.10), 2)
	var c_rim := _pbr(Color(0.76, 0.79, 0.82), 3)
	var c_brake := _pbr(Color(0.42, 0.44, 0.47), 3)
	var c_trim := _pbr(Color(0.15, 0.16, 0.18), 9)
	var c_seat := _pbr(Color(0.16, 0.15, 0.16), 7)
	var c_chrome := _pbr(Color(0.78, 0.80, 0.84), 3)
	var c_jacket := _pbr(jacket_rgb, 7)
	var c_collar := _pbr(jacket_rgb.darkened(0.22), 7)
	var c_pants := _pbr(Color(0.18, 0.22, 0.29), 7)
	var c_skin := _pbr(Color(0.89, 0.75, 0.63), 8)
	var c_hair := _pbr(Color(0.13, 0.11, 0.10), 8)
	var c_shoe := _pbr(Color(0.16, 0.16, 0.18), 7)
	var c_head := _pbr(Color(1.0, 0.96, 0.86), 4)
	var c_tail := _pbr(Color(0.95, 0.10, 0.10), 5)

	var w_maj := 8 if lod1 else 16
	var w_min := 4 if lod1 else 10
	var t_seg := 4 if lod1 else 10
	var e_seg := 5 if lod1 else 14
	var e_rng := 3 if lod1 else 9

	# 1. Sculpted Toroidal Front & Rear Wheels + 5-Spoke Alloy Rims + Brake Rotors!
	MeshSculpt.add_sculpted_wheel(st, Vector3(0.0, 0.24, -0.64), 0.24, 0.11, 0.0, w_maj, w_min, c_tire, c_rim, c_brake, 5, false)
	MeshSculpt.add_sculpted_wheel(st, Vector3(0.0, 0.24, 0.58), 0.24, 0.12, 0.0, w_maj, w_min, c_tire, c_rim, c_brake, 5, false)

	# 2. Tubular Telescopic Front Forks, Mudguards, Rear Swingarm & Twin Shocks (8-10 seg tubes!)
	for sx: float in [-0.09, 0.09]:
		MeshSculpt.add_tube(st, Vector3(sx, 0.24, -0.64), Vector3(sx * 0.85, 0.72, -0.49), 0.024, 0.022, t_seg, c_chrome, 1)
		MeshSculpt.add_tube(st, Vector3(sx * 1.15, 0.24, 0.58), Vector3(sx * 1.15, 0.34, 0.14), 0.022, 0.024, t_seg, c_trim, 1)
		MeshSculpt.add_tube(st, Vector3(sx * 1.22, 0.28, 0.56), Vector3(sx * 1.15, 0.56, 0.44), 0.020, 0.020, t_seg, c_chrome, 1)
	# Curved front & rear fenders
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 0.43, -0.62), Vector3(0.11, 0.07, 0.21), e_seg, e_rng / 2 + 1, c_body)
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 0.45, 0.62), Vector3(0.12, 0.06, 0.19), e_seg, e_rng / 2 + 1, c_trim)

	# 3. Sculpted Swept Scooter Bodywork: Lofted Rear Fairing, Contoured Floorboard & Front Leg-Shield Apron!
	var rear_stations := [
		_oval_ring(Vector3(0.0, 0.42, 0.04), 0.18, 0.12, e_seg),
		_oval_ring(Vector3(0.0, 0.54, 0.22), 0.21, 0.18, e_seg),
		_oval_ring(Vector3(0.0, 0.58, 0.46), 0.22, 0.19, e_seg),
		_oval_ring(Vector3(0.0, 0.60, 0.68), 0.17, 0.14, e_seg),
		_oval_ring(Vector3(0.0, 0.62, 0.78), 0.10, 0.08, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, rear_stations, c_body, true, true, true)
	# Floorboard battery deck
	var deck_stations := [
		_oval_ring(Vector3(0.0, 0.27, -0.34), 0.20, 0.065, e_seg),
		_oval_ring(Vector3(0.0, 0.27, 0.12), 0.22, 0.072, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, deck_stations, c_trim, true, true, true)
	# Swept aerodynamic front leg-shield apron
	var apron_stations := [
		_oval_ring(Vector3(0.0, 0.30, -0.44), 0.20, 0.10, e_seg),
		_oval_ring(Vector3(0.0, 0.58, -0.50), 0.23, 0.13, e_seg),
		_oval_ring(Vector3(0.0, 0.86, -0.48), 0.20, 0.12, e_seg),
		_oval_ring(Vector3(0.0, 0.96, -0.44), 0.15, 0.09, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, apron_stations, c_body, true, true, true)
	# Sculpted ergonomic leather seat cushion (matte leather mat_id=7, smooth lofted contour!)
	var seat_st := [
		_oval_ring(Vector3(0.0, 0.74, 0.06), 0.11, 0.065, e_seg),
		_oval_ring(Vector3(0.0, 0.76, 0.22), 0.155, 0.075, e_seg),
		_oval_ring(Vector3(0.0, 0.78, 0.44), 0.165, 0.075, e_seg),
		_oval_ring(Vector3(0.0, 0.79, 0.60), 0.13, 0.060, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, seat_st, c_seat, true, true, true)
	# Tubular handlebars, grips, stem & twin round rear-view mirrors!
	MeshSculpt.add_tube(st, Vector3(0.0, 0.88, -0.44), Vector3(0.0, 1.00, -0.42), 0.032, 0.028, t_seg, c_trim, 1)
	MeshSculpt.add_tube(st, Vector3(-0.35, 0.98, -0.38), Vector3(0.0, 1.00, -0.44), 0.022, 0.022, t_seg, c_trim, 1)
	MeshSculpt.add_tube(st, Vector3(0.35, 0.98, -0.38), Vector3(0.0, 1.00, -0.44), 0.022, 0.022, t_seg, c_trim, 1)
	if not lod1:
		for sx: float in [-0.24, 0.24]:
			MeshSculpt.add_tube(st, Vector3(sx, 1.00, -0.41), Vector3(sx * 1.28, 1.15, -0.44), 0.008, 0.008, 6, c_chrome, 1)
			MeshSculpt.add_ellipsoid(st, Vector3(sx * 1.32, 1.16, -0.44), Vector3(0.055, 0.038, 0.022), 8, 5, c_trim)
	# Glowing LED Headlight & Ruby Taillight!
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 0.84, -0.60), Vector3(0.09, 0.065, 0.04), e_seg, 5, c_head)
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 0.65, 0.78), Vector3(0.11, 0.042, 0.03), e_seg, 4, c_tail)

	if has_basket:
		MeshSculpt.add_ellipsoid(st, Vector3(0.0, 0.80, -0.66), Vector3(0.16, 0.11, 0.11), e_seg, 5, _pbr(Color(0.76, 0.70, 0.60), 3))
	if has_shield:
		MeshSculpt.add_ellipsoid(st, Vector3(0.0, 1.18, -0.52), Vector3(0.22, 0.19, 0.035), e_seg, 5, c_glass)

	# 4. Natural Smooth Human Commuter Rider (matte woven cloth + seamless parallel-transport swept limbs, ZERO balloon joints!)
	var limb_seg := 6 if lod1 else 12
	# Seamless seated pelvis / trousers base blending hips smoothly into both thighs
	var hip_st := [
		_oval_ring(Vector3(0.0, 0.78, 0.24), 0.155, 0.115, e_seg),
		_oval_ring(Vector3(0.0, 0.87, 0.20), 0.170, 0.125, e_seg),
		_oval_ring(Vector3(0.0, 0.94, 0.17), 0.162, 0.118, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, hip_st, c_pants, true, true, true)
	# Seamless continuous swept legs (pelvis -> upper thigh -> rounded knee bend -> calf -> ankle)
	for sx: float in [-1.0, 1.0]:
		var leg_pts: Array[Vector3] = [
			Vector3(sx * 0.095, 0.85, 0.20),
			Vector3(sx * 0.115, 0.77, 0.02),
			Vector3(sx * 0.132, 0.70, -0.14),
			Vector3(sx * 0.135, 0.64, -0.20),
			Vector3(sx * 0.132, 0.54, -0.22),
			Vector3(sx * 0.128, 0.42, -0.22),
			Vector3(sx * 0.125, 0.34, -0.22),
		]
		var leg_rads: Array[float] = [0.074, 0.068, 0.060, 0.056, 0.052, 0.044, 0.038]
		MeshSculpt.add_swept_limb(st, leg_pts, leg_rads, limb_seg, c_pants, false, true)
		MeshSculpt.add_ellipsoid(st, Vector3(sx * 0.125, 0.325, -0.275), Vector3(0.046, 0.036, 0.105), e_seg, 3 if lod1 else 5, c_shoe)

	# Sculpted 7-station natural human jacket torso (coat hem -> waist -> ribs -> chest -> sloped shoulders -> collar)
	var torso_st := [
		_oval_ring(Vector3(0.0, 0.85, 0.19), 0.178, 0.125, e_seg),
		_oval_ring(Vector3(0.0, 0.98, 0.16), 0.168, 0.118, e_seg),
		_oval_ring(Vector3(0.0, 1.13, 0.13), 0.186, 0.126, e_seg),
		_oval_ring(Vector3(0.0, 1.26, 0.10), 0.205, 0.128, e_seg),
		_oval_ring(Vector3(0.0, 1.35, 0.09), 0.188, 0.114, e_seg),
		_oval_ring(Vector3(0.0, 1.40, 0.08), 0.120, 0.086, e_seg),
		_oval_ring(Vector3(0.0, 1.44, 0.075), 0.074, 0.068, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, torso_st, c_jacket, true, true, true)
	# Jacket stand collar around neck base
	var collar_st := [
		_oval_ring(Vector3(0.0, 1.41, 0.078), 0.078, 0.072, e_seg),
		_oval_ring(Vector3(0.0, 1.465, 0.072), 0.070, 0.066, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, collar_st, c_collar, true, false, true)

	# Seamless continuous swept sleeves emerging organically from inside the chest/shoulders -> elbow -> wrist -> hand!
	for sx: float in [-1.0, 1.0]:
		var arm_pts: Array[Vector3] = [
			Vector3(sx * 0.135, 1.32, 0.10),
			Vector3(sx * 0.195, 1.29, 0.08),
			Vector3(sx * 0.228, 1.20, 0.02),
			Vector3(sx * 0.240, 1.11, -0.05),
			Vector3(sx * 0.256, 1.06, -0.14),
			Vector3(sx * 0.285, 1.01, -0.26),
			Vector3(sx * 0.312, 0.99, -0.35),
		]
		var arm_rads: Array[float] = [0.062, 0.054, 0.048, 0.044, 0.041, 0.036, 0.030]
		MeshSculpt.add_swept_limb(st, arm_pts, arm_rads, limb_seg, c_jacket, false, true)
		MeshSculpt.add_ellipsoid(st, Vector3(sx * 0.322, 0.985, -0.382), Vector3(0.032, 0.028, 0.042), e_seg, 3 if lod1 else 4, c_skin)

	# Natural human neck, head, visible hair nape, and commuter half-shell helmet with dark visor!
	var neck_pts: Array[Vector3] = [Vector3(0.0, 1.42, 0.074), Vector3(0.0, 1.50, 0.062), Vector3(0.0, 1.54, 0.056)]
	var neck_rads: Array[float] = [0.054, 0.048, 0.050]
	MeshSculpt.add_swept_limb(st, neck_pts, neck_rads, limb_seg, c_skin, false, false)
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 1.575, 0.050), Vector3(0.088, 0.106, 0.098), e_seg, e_rng, c_skin)
	# Natural dark hair visible at nape and sides beneath commuter helmet
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 1.572, 0.082), Vector3(0.090, 0.088, 0.082), e_seg, 4 if lod1 else 6, c_hair)
	# Sleek ergonomic half-helmet sitting naturally on top of the head + glossy curved visor
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 1.620, 0.062), Vector3(0.114, 0.102, 0.126), e_seg, e_rng, c_helm)
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 1.586, -0.028), Vector3(0.098, 0.050, 0.062), e_seg, 4 if lod1 else 5, c_glass)

	# 5. Delivery Courier Rear Insulated Box (外卖保温箱 + 金属货架 + 反光带)
	if has_box:
		var c_box := _pbr(box_rgb, 0)
		var c_lid := _pbr(box_rgb.darkened(0.16), 3)
		var b_st := [
			_oval_ring(Vector3(0.0, 0.84, 0.72), 0.23, 0.22, e_seg),
			_oval_ring(Vector3(0.0, 1.24, 0.72), 0.24, 0.23, e_seg),
		]
		MeshSculpt.add_lofted_hull(st, b_st, c_box, true, true, true)
		var lid_st := [
			_oval_ring(Vector3(0.0, 1.24, 0.72), 0.25, 0.24, e_seg),
			_oval_ring(Vector3(0.0, 1.30, 0.72), 0.23, 0.22, e_seg),
		]
		MeshSculpt.add_lofted_hull(st, lid_st, c_lid, true, true, true)
		MeshSculpt.add_tube(st, Vector3(-0.16, 0.74, 0.56), Vector3(-0.16, 0.84, 0.74), 0.016, 0.016, 6, c_trim, 1)
		MeshSculpt.add_tube(st, Vector3(0.16, 0.74, 0.56), Vector3(0.16, 0.84, 0.74), 0.016, 0.016, 6, c_trim, 1)

	return st.commit()


static func _make_etrike_mesh(lod1: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_tire := _pbr(Color(0.09, 0.09, 0.10), 2)
	var c_rim := _pbr(Color(0.74, 0.76, 0.80), 3)
	var c_brake := _pbr(Color(0.42, 0.44, 0.47), 3)
	var c_cab := _pbr(Color(0.20, 0.22, 0.26), 0)
	var c_cargo := _pbr(Color(0.24, 0.26, 0.30), 0)
	var c_stripe := _pbr(Color(0.88, 0.14, 0.14), 0)
	var c_glass := _pbr(Color(0.10, 0.18, 0.26), 1)
	var c_trim := _pbr(Color(0.14, 0.15, 0.17), 3)
	var c_head := _pbr(Color(1.0, 0.96, 0.86), 4)
	var c_tail := _pbr(Color(0.95, 0.10, 0.10), 5)

	var w_maj := 10 if lod1 else 16
	var w_min := 6 if lod1 else 9
	var t_seg := 6 if lod1 else 8
	var e_seg := 8 if lod1 else 12

	# 3 sculpted toroidal wheels + alloy rims
	MeshSculpt.add_sculpted_wheel(st, Vector3(0.0, 0.24, -0.96), 0.24, 0.12, 0.0, w_maj, w_min, c_tire, c_rim, c_brake, 5, false)
	for sx: float in [-0.48, 0.48]:
		MeshSculpt.add_sculpted_wheel(st, Vector3(sx, 0.24, 0.72), 0.24, 0.13, signf(sx), w_maj, w_min, c_tire, c_rim, c_brake, 5, false)
	# Tubular chassis frame & rear axle
	MeshSculpt.add_tube(st, Vector3(-0.48, 0.24, 0.72), Vector3(0.48, 0.24, 0.72), 0.028, 0.028, t_seg, c_trim, 1)
	for sx: float in [-0.36, 0.36]:
		MeshSculpt.add_tube(st, Vector3(sx, 0.30, 0.85), Vector3(sx * 0.4, 0.34, -0.82), 0.026, 0.026, t_seg, c_trim, 1)
	# Sculpted front nose cowl + tubular canopy frame + curved windshield
	var cowl_st := [
		_oval_ring(Vector3(0.0, 0.42, -1.00), 0.36, 0.14, e_seg),
		_oval_ring(Vector3(0.0, 0.94, -0.86), 0.42, 0.16, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, cowl_st, c_cab, true, true, true)
	for sx: float in [-0.38, 0.38]:
		MeshSculpt.add_tube(st, Vector3(sx, 0.92, -0.82), Vector3(sx, 1.48, -0.64), 0.022, 0.022, t_seg, c_trim, 1)
		MeshSculpt.add_tube(st, Vector3(sx, 1.48, -0.64), Vector3(sx, 1.50, -0.04), 0.022, 0.022, t_seg, c_trim, 1)
	MeshSculpt.emit_quad(st, Vector3(-0.36, 0.94, -0.82), Vector3(0.36, 0.94, -0.82), Vector3(0.36, 1.44, -0.65), Vector3(-0.36, 1.44, -0.65), c_glass)
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.52, -0.34)), Vector3(0.86, 0.06, 0.68), c_cab)
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 0.74, -1.03), Vector3(0.11, 0.065, 0.04), e_seg, 5, c_head)
	# Sculpted enclosed express cargo box + red stripe + dual ruby taillights
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.02, 0.54)), Vector3(1.02, 1.18, 1.24), c_cargo)
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.10, 0.54)), Vector3(1.04, 0.18, 1.25), c_stripe)
	for sx: float in [-0.38, 0.38]:
		MeshSculpt.add_ellipsoid(st, Vector3(sx, 0.56, 1.17), Vector3(0.08, 0.045, 0.03), 8, 4, c_tail)
	return st.commit()


static func _make_shared_bike_mesh(frame_rgb: Color, jacket_rgb: Color, lod1: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_frame := _pbr(frame_rgb, 0)
	var c_tire := _pbr(Color(0.10, 0.10, 0.11), 2)
	var c_rim := _pbr(Color(0.76, 0.78, 0.80), 3)
	var c_brake := _pbr(Color(0.28, 0.30, 0.32), 3)
	var c_trim := _pbr(Color(0.15, 0.16, 0.18), 9)
	var c_jacket := _pbr(jacket_rgb, 7)
	var c_pants := _pbr(Color(0.20, 0.24, 0.32), 7)
	var c_skin := _pbr(Color(0.89, 0.75, 0.63), 8)
	var c_hair := _pbr(Color(0.14, 0.12, 0.11), 8)
	var c_shoe := _pbr(Color(0.16, 0.16, 0.18), 7)

	var w_maj := 10 if lod1 else 18
	var w_min := 5 if lod1 else 8
	var t_seg := 6 if lod1 else 8
	var e_seg := 8 if lod1 else 12

	# Slender spoked bicycle wheels
	MeshSculpt.add_sculpted_wheel(st, Vector3(0.0, 0.30, -0.56), 0.30, 0.055, 0.0, w_maj, w_min, c_tire, c_rim, c_brake, 6, false)
	MeshSculpt.add_sculpted_wheel(st, Vector3(0.0, 0.30, 0.54), 0.30, 0.055, 0.0, w_maj, w_min, c_tire, c_rim, c_brake, 6, false)
	# Real tubular diamond frame (8-seg tubes!)
	var bb := Vector3(0.0, 0.32, 0.08)
	var seat_top := Vector3(0.0, 0.76, 0.22)
	var head_bot := Vector3(0.0, 0.60, -0.42)
	var head_top := Vector3(0.0, 0.94, -0.45)
	MeshSculpt.add_tube(st, bb, seat_top, 0.022, 0.020, t_seg, c_frame, 1)
	MeshSculpt.add_tube(st, bb, head_bot, 0.024, 0.024, t_seg, c_frame, 1)
	MeshSculpt.add_tube(st, seat_top, head_bot + Vector3(0.0, 0.16, -0.02), 0.018, 0.018, t_seg, c_frame, 1)
	MeshSculpt.add_tube(st, head_bot, head_top, 0.022, 0.020, t_seg, c_frame, 1)
	for sx: float in [-0.045, 0.045]:
		MeshSculpt.add_tube(st, Vector3(sx, 0.30, -0.56), head_bot + Vector3(sx * 0.6, 0.0, 0.0), 0.014, 0.016, t_seg, c_frame, 1)
		MeshSculpt.add_tube(st, Vector3(sx, 0.30, 0.54), bb + Vector3(sx * 0.6, 0.0, 0.0), 0.014, 0.014, t_seg, c_frame, 1)
		MeshSculpt.add_tube(st, Vector3(sx, 0.30, 0.54), seat_top + Vector3(sx * 0.5, -0.05, 0.0), 0.012, 0.012, t_seg, c_frame, 1)
	MeshSculpt.add_tube(st, Vector3(-0.27, 0.96, -0.39), Vector3(0.27, 0.96, -0.39), 0.016, 0.016, t_seg, c_trim, 1)
	MeshSculpt.add_ellipsoid(st, seat_top + Vector3(0.0, 0.06, 0.02), Vector3(0.08, 0.035, 0.13), e_seg, 4, c_trim)
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 0.80, -0.56), Vector3(0.15, 0.10, 0.12), e_seg, 4, c_frame)

	# Sculpted natural cyclist (matte cloth, seamless swept limbs, natural forward riding lean!)
	var b_limb := 6 if lod1 else 10
	for sx: float in [-1.0, 1.0]:
		var kn_z := -0.04 if sx < 0.0 else 0.05
		var ft_y := 0.29 if sx < 0.0 else 0.42
		var leg_b: Array[Vector3] = [
			Vector3(sx * 0.085, 0.87, 0.22),
			Vector3(sx * 0.105, 0.74, 0.09),
			Vector3(sx * 0.112, 0.62, kn_z),
			Vector3(sx * 0.110, 0.48, 0.04),
			Vector3(sx * 0.106, ft_y, 0.08),
		]
		var rad_b: Array[float] = [0.066, 0.058, 0.050, 0.044, 0.036]
		MeshSculpt.add_swept_limb(st, leg_b, rad_b, b_limb, c_pants, false, true)
		MeshSculpt.add_ellipsoid(st, Vector3(sx * 0.106, ft_y - 0.015, 0.03), Vector3(0.042, 0.032, 0.095), e_seg, 3 if lod1 else 4, c_shoe)
	var t_st := [
		_oval_ring(Vector3(0.0, 0.85, 0.22), 0.150, 0.105, e_seg),
		_oval_ring(Vector3(0.0, 1.00, 0.18), 0.148, 0.102, e_seg),
		_oval_ring(Vector3(0.0, 1.18, 0.11), 0.168, 0.112, e_seg),
		_oval_ring(Vector3(0.0, 1.32, 0.05), 0.186, 0.114, e_seg),
		_oval_ring(Vector3(0.0, 1.40, 0.02), 0.118, 0.082, e_seg),
		_oval_ring(Vector3(0.0, 1.44, 0.00), 0.072, 0.064, e_seg),
	]
	MeshSculpt.add_lofted_hull(st, t_st, c_jacket, true, true, true)
	for sx: float in [-1.0, 1.0]:
		var arm_b: Array[Vector3] = [
			Vector3(sx * 0.125, 1.32, 0.05),
			Vector3(sx * 0.180, 1.29, 0.02),
			Vector3(sx * 0.212, 1.15, -0.11),
			Vector3(sx * 0.236, 1.05, -0.25),
			Vector3(sx * 0.255, 0.96, -0.38),
		]
		var arad_b: Array[float] = [0.054, 0.047, 0.040, 0.034, 0.028]
		MeshSculpt.add_swept_limb(st, arm_b, arad_b, b_limb, c_jacket, false, true)
		MeshSculpt.add_ellipsoid(st, Vector3(sx * 0.262, 0.96, -0.39), Vector3(0.028, 0.025, 0.036), e_seg, 3 if lod1 else 4, c_skin)
	var neck_b: Array[Vector3] = [Vector3(0.0, 1.42, 0.00), Vector3(0.0, 1.50, -0.025)]
	var nrad_b: Array[float] = [0.048, 0.044]
	MeshSculpt.add_swept_limb(st, neck_b, nrad_b, b_limb, c_skin, false, false)
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 1.565, -0.042), Vector3(0.086, 0.102, 0.094), e_seg, 6, c_skin)
	MeshSculpt.add_ellipsoid(st, Vector3(0.0, 1.608, -0.022), Vector3(0.095, 0.084, 0.102), e_seg, 5, c_hair)
	return st.commit()


static func _oval_ring(center: Vector3, rx: float, rz: float, segs: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in range(segs):
		var a := TAU * float(i) / float(segs)
		out.append(center + Vector3(cos(a) * rx, 0.0, sin(a) * rz))
	return out
