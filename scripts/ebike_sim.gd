class_name EbikeSim
extends Node3D

# Authentic Chinese Non-Motorized Bike-Lane Traffic (嘉兴电瓶车大军 / 外卖骑手 / 快递电动三轮 / 共享单车):
#   - 200 lively e-bikes, delivery couriers, cargo e-trikes & shared bikes (~4:1 ratio over cars!)
#   - Sculpted high-detail LOD0 (~4,200-5,600 tris: toroidal tires, spoked alloy rims, 8-10 seg tubular forks & frames,
#     curved fairings, mirrors, anatomical riders & smooth visored helmets) + LOD1 (~1,300-1,600 tris beyond 48m)
#   - Strict tram-mast avoidance (spatial grid of TrackBuilder mast_positions) so ZERO e-bikes ever clip a pole!
#   - Rendered via 10 LOD0 + 10 LOD1 MultiMeshInstance3D pools + 24m spatial grid for silky 60 FPS!

const MAX_EBIKES := 200
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
	_clear_idx = graph.get_meta("track_clear_idx", {})
	_rebuild_mast_grid(graph)

	if not bool(graph.get_meta("is_chinese_city", false)):
		return
	if _meshes_lod0.is_empty():
		_build_meshes()

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
		var eid := _pick_edge(graph, focus_pos, true)
		if eid < 0:
			continue
		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		var s_init := lerpf(6.0, maxf(7.0, elen - 6.0), _rng.randf())
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
			"lane_jitter": _rng.randf_range(-0.24, 0.24),
			"pos": Vector3.ZERO,
			"fwd": Vector3.FORWARD,
			"stuck_t": 0.0,
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
		if pos.distance_squared_to(focus_pos) > 315.0 * 315.0:
			_respawn(eb, graph, focus_pos)
			continue

		var eid := int(eb["edge_id"])
		if not graph.edges.has(eid):
			_respawn(eb, graph, focus_pos)
			continue
		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
		var dir := float(eb["dir"])
		var s_now := float(eb["s"])
		var dist_end := (elen - s_now) if dir > 0.0 else s_now
		var next_nid := int(ed["b"]) if dir > 0.0 else int(ed["a"])
		var fwd: Vector3 = eb["fwd"]
		var right := fwd.cross(Vector3.UP).normalized()

		var target_spd := float(eb["cruise"])
		if dist_end < 11.0:
			target_spd = minf(target_spd, 4.2)

		# 1) Same-direction e-bike spacing via 24m spatial grid
		var cx := int(floor(pos.x / 24.0))
		var cz := int(floor(pos.z / 24.0))
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
					if dv.length_squared() > 42.0:
						continue
					var along := dv.dot(fwd)
					var lat := absf(dv.dot(right))
					if along > 0.2 and lat < 0.85:
						if along < 2.8:
							target_spd = 0.0
						elif along < 6.0:
							target_spd = minf(target_spd, float(oth["speed"]) * 0.88)

		# 2) Obey intersection traffic signals cleanly behind crosswalk
		var stop_d := 8.4
		if dist_end >= stop_d - 1.2 and dist_end <= stop_d + 9.5 and traffic.signals.has(next_nid):
			var aspect := traffic.get_signal_aspect(next_nid, Vector2(fwd.x, fwd.z))
			if aspect != "green":
				target_spd = 0.0 if dist_end <= stop_d + 1.4 else minf(target_spd, (dist_end - stop_d) * 0.65)

		# 3) Yield to any nearby tram crossing perpendicular at an intersection
		for tr: Dictionary in trams:
			var tp: Vector3 = tr.get("pos", Vector3.ZERO)
			var dv_t := tp - pos
			if dv_t.length_squared() < 225.0:
				var tf: Vector3 = tr.get("fwd", Vector3.FORWARD)
				if absf(fwd.dot(tf)) < 0.78:
					var along_t := dv_t.dot(fwd)
					if along_t > -1.0 and along_t < 14.0:
						target_spd = 0.0
						break

		var spd := move_toward(float(eb["speed"]), target_spd, (14.5 if target_spd < float(eb["speed"]) else 4.6) * dt_c)
		eb["speed"] = spd

		var st_t := (float(eb.get("stuck_t", 0.0)) + dt_c) if spd < 0.2 else 0.0
		eb["stuck_t"] = st_t
		if st_t >= 20.0:
			_respawn(eb, graph, focus_pos)
			continue

		var s_next := s_now + dir * spd * dt_c
		if s_next >= elen - 1.8 or s_next <= 1.8:
			_advance_next_edge(eb, graph, next_nid, eid)
		else:
			eb["s"] = s_next
		_update_transform(eb, graph)


func _edge_allows_ebike(graph: NetworkGraph, eid: int) -> bool:
	if not graph.edges.has(eid):
		return false
	var ed: Dictionary = graph.edges[eid]
	if bool(ed.get("underground", false)):
		return false
	var elen := float(ed.get("length", 0.0))
	var w := float(ed.get("width", 10.0))
	if w < 8.0 or elen < 18.0:
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
				if clr_r < 2.25 or clr_l < 2.25:
					return false
	return true


func _advance_next_edge(eb: Dictionary, graph: NetworkGraph, at_nid: int, prev_eid: int) -> void:
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
		var pts: Array = ed["pts"]
		var p0: Vector2 = pts[0] if ndir > 0.0 else pts[pts.size() - 1]
		var p1: Vector2 = pts[1] if ndir > 0.0 else pts[pts.size() - 2]
		var nf := Vector3(p1.x - p0.x, 0.0, p1.y - p0.y).normalized()
		var dp := prev_fwd.dot(nf)
		var item := {"eid": ne, "dir": ndir, "len": float(ed["length"]), "dot": dp}
		cands.append(item)
		if dp > best_dot:
			best_dot = dp
			best_straight = item

	if cands.is_empty():
		var ed0: Dictionary = graph.edges[prev_eid]
		eb["dir"] = -float(eb["dir"])
		eb["s"] = 2.5 if float(eb["dir"]) > 0.0 else maxf(2.5, float(ed0["length"]) - 2.5)
		return

	var pick: Dictionary = best_straight if (best_dot > 0.55 and _rng.randf() < 0.72) else cands[_rng.randi() % cands.size()]
	eb["edge_id"] = int(pick["eid"])
	eb["dir"] = float(pick["dir"])
	eb["s"] = 2.5 if float(pick["dir"]) > 0.0 else maxf(2.5, float(pick["len"]) - 2.5)


func _respawn(eb: Dictionary, graph: NetworkGraph, focus_pos: Vector3) -> void:
	var eid := _pick_edge(graph, focus_pos, true)
	if eid < 0:
		return
	var ed: Dictionary = graph.edges[eid]
	var elen := float(ed["length"])
	eb["edge_id"] = eid
	eb["dir"] = 1.0 if _rng.randf() < 0.5 else -1.0
	eb["s"] = lerpf(5.0, maxf(6.0, elen - 5.0), _rng.randf())
	eb["speed"] = float(eb["cruise"]) * 0.78
	eb["stuck_t"] = 0.0
	_update_transform(eb, graph)


func _pick_edge(graph: NetworkGraph, focus_pos: Vector3, near: bool) -> int:
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
			for _k in range(10):
				var cand := local_cands[_rng.randi() % local_cands.size()]
				var pts: Array = graph.edges[cand]["pts"]
				var mp: Vector2 = pts[pts.size() / 2]
				var d2 := Vector2(mp.x - focus_pos.x, mp.y - focus_pos.z).length_squared()
				if d2 <= 295.0 * 295.0:
					return cand
			return local_cands[_rng.randi() % local_cands.size()]
	return _bike_edges[_rng.randi() % _bike_edges.size()]


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
	var ed: Dictionary = graph.edges[eid]
	var elen := maxf(1.0, float(ed["length"]))
	var dir := float(eb["dir"])
	var s := clampf(float(eb["s"]), 0.0, elen)
	var hw := clampf(float(ed.get("width", 10.0)) * 0.5, 4.0, 13.5)
	var bl_w := 2.05 if hw >= 5.75 else (1.55 if hw >= 4.8 else 1.25)
	var lat_off := maxf(2.2, hw - bl_w * 0.52) + float(eb.get("lane_jitter", 0.0)) * (1.0 if hw >= 5.75 else 0.55)
	if graph.built_tracks.has(eid):
		lat_off = clampf(lat_off, graph.get_edge_track_half_sep(eid) + 2.55, hw - 0.45)
	var fr := TrafficSim._edge_frame(graph, eid, s, elen, dir)
	var center: Vector3 = fr[0]
	var fwd: Vector3 = fr[1]
	fwd.y = 0.0
	if fwd.length_squared() < 1e-5:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var pos := _nudge_clear_of_masts(center + right * lat_off, right)
	if not _clear_idx.is_empty():
		var tc := TrackBuilder.track_clearance_dist(_clear_idx, Vector2(pos.x, pos.z))
		if tc < 2.25:
			# Push cleanly outward toward the outer curb if a diagonal/curved track encroaches
			var p_out := pos + right * (2.35 - tc)
			var p_in := pos - right * (2.35 - tc)
			pos = p_out if TrackBuilder.track_clearance_dist(_clear_idx, Vector2(p_out.x, p_out.z)) >= TrackBuilder.track_clearance_dist(_clear_idx, Vector2(p_in.x, p_in.z)) else p_in
	pos.y = 0.055 + (Terrain.surface(pos.x, pos.z) if Terrain.active else 0.0)
	eb["pos"] = pos
	eb["fwd"] = fwd

	var tf := Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	var v := int(eb["var"])
	var slot := int(eb["slot"])
	if v >= 0 and v < _mmis_lod0.size():
		var mm0 := _mmis_lod0[v].multimesh
		if mm0 != null and slot < mm0.instance_count:
			mm0.set_instance_transform(slot, tf)
		var mm1 := _mmis_lod1[v].multimesh
		if mm1 != null and slot < mm1.instance_count:
			mm1.set_instance_transform(slot, tf)


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
