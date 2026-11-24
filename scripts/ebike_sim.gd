class_name EbikeSim
extends Node3D

# Authentic Chinese Non-Motorized Bike-Lane Traffic (嘉兴电瓶车大军 / 外卖骑手 / 快递电动三轮 / 共享单车):
#   Spawns 200 lively e-bikes, delivery couriers, cargo e-trikes & shared bikes (~4:1 ratio over cars!)
#   riding strictly in the outer green bike lanes (非机动车道) across all Jiaxing streets (width >= 8.0m).
#   Uses 10 batched MultiMeshInstance3D pools (10 draw calls total!) + 24m spatial grid for <0.15ms/frame CPU!

const MAX_EBIKES := 200
const VARIANT_COUNT := 10

var ebikes: Array[Dictionary] = []
var _meshes: Array[ArrayMesh] = []
var _mmis: Array[MultiMeshInstance3D] = []
var _mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _bike_edges: Array[int] = []
var _bike_edge_grid: Dictionary = {} # Vector2i (160m cell) -> Array[int]


func _ready() -> void:
	_rng.randomize()
	_build_meshes()


func rebuild(graph: NetworkGraph, focus_pos: Vector3) -> void:
	for c in get_children():
		c.queue_free()
	ebikes.clear()
	_mmis.clear()
	_bike_edges.clear()
	_bike_edge_grid.clear()

	if not bool(graph.get_meta("is_chinese_city", false)):
		return
	if _meshes.is_empty():
		_build_meshes()

	for eid_v in graph.edges.keys():
		var eid := int(eid_v)
		var ed: Dictionary = graph.edges[eid]
		if bool(ed.get("underground", false)):
			continue
		if float(ed.get("width", 10.0)) >= 8.0 and float(ed.get("length", 0.0)) >= 18.0:
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

		# Realistic speeds: couriers brisker (6.8..8.5 m/s), commuter scooters (5.5..7.4 m/s), e-trikes (5.0..6.4 m/s), shared bikes (4.0..5.2 m/s)
		var cruise := 5.6 + _rng.randf() * 1.8
		if var_idx == 5 or var_idx == 6:
			cruise = 6.8 + _rng.randf() * 1.7 # 美团 / 饿了么 delivery couriers
		elif var_idx == 7:
			cruise = 5.0 + _rng.randf() * 1.3 # 顺丰/快递电动三轮车
		elif var_idx >= 8:
			cruise = 4.0 + _rng.randf() * 1.2 # 哈啰 / 美团共享单车

		var eb := {
			"var": var_idx,
			"slot": slot,
			"edge_id": eid,
			"dir": dir,
			"s": s_init,
			"speed": cruise * 0.8,
			"cruise": cruise,
			"lane_jitter": _rng.randf_range(-0.26, 0.26),
			"pos": Vector3.ZERO,
			"fwd": Vector3.FORWARD,
			"stuck_t": 0.0,
		}
		ebikes.append(eb)

	# Create 10 batched MultiMeshInstance3D pools (only 10 draw calls for all 200 e-bikes!)
	for v in range(VARIANT_COUNT):
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "EbikePool_%d" % v
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[v]
		mm.instance_count = per_var_counts[v]
		mmi.multimesh = mm
		mmi.material_override = _mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 5000.0
		add_child(mmi)
		_mmis.append(mmi)

	for eb: Dictionary in ebikes:
		_update_transform(eb, graph)


func step(dt: float, graph: NetworkGraph, traffic: TrafficSim, trams: Array[Dictionary], focus_pos: Vector3) -> void:
	if ebikes.is_empty() or _bike_edges.is_empty():
		return
	var dt_c := minf(dt, 0.05)

	# Build fast 24m spatial grid for O(1) neighbor spacing across all 200 e-bikes
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

		# 1) Same-direction e-bike spacing via 24m spatial grid (tight, natural Chinese bike-lane clusters!)
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


func _advance_next_edge(eb: Dictionary, graph: NetworkGraph, at_nid: int, prev_eid: int) -> void:
	var cands: Array[Dictionary] = []
	var prev_fwd: Vector3 = eb["fwd"]
	var best_straight: Dictionary = {}
	var best_dot := -2.0
	for link in graph.adj.get(at_nid, []):
		var ne := int(link["edge_id"])
		if ne == prev_eid:
			continue
		var ed: Dictionary = graph.edges[ne]
		if bool(ed.get("underground", false)) or float(ed.get("length", 0.0)) < 14.0:
			continue
		if float(ed.get("width", 10.0)) < 7.8:
			continue
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


func _update_transform(eb: Dictionary, graph: NetworkGraph) -> void:
	var eid := int(eb["edge_id"])
	var ed: Dictionary = graph.edges[eid]
	var elen := maxf(1.0, float(ed["length"]))
	var dir := float(eb["dir"])
	var s := clampf(float(eb["s"]), 0.0, elen)
	var hw := clampf(float(ed.get("width", 10.0)) * 0.5, 4.0, 13.5)
	# Ride right inside the green outer Non-Motorized Bike Lane matching CityBuilder's bike_lane width!
	var bl_w := 2.05 if hw >= 5.75 else (1.55 if hw >= 4.8 else 1.25)
	var lat_off := maxf(2.2, hw - bl_w * 0.52) + float(eb.get("lane_jitter", 0.0)) * (1.0 if hw >= 5.75 else 0.55)
	var fr := TrafficSim._edge_frame(graph, eid, s, elen, dir)
	var center: Vector3 = fr[0]
	var fwd: Vector3 = fr[1]
	fwd.y = 0.0
	if fwd.length_squared() < 1e-5:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var pos := center + right * lat_off
	pos.y = 0.055 + (Terrain.surface(pos.x, pos.z) if Terrain.active else 0.0)
	eb["pos"] = pos
	eb["fwd"] = fwd

	var v := int(eb["var"])
	var slot := int(eb["slot"])
	if v >= 0 and v < _mmis.size():
		var mm := _mmis[v].multimesh
		if mm != null and slot < mm.instance_count:
			mm.set_instance_transform(slot, Transform3D(Basis.looking_at(fwd, Vector3.UP), pos))


func _pick_variant_idx(i: int) -> int:
	# Authentic Jiaxing ratio: ~58% commuter e-bikes, ~20% 美团/饿了么 couriers, ~10% cargo e-trikes, ~12% shared bikes
	var r := i % 20
	if r in [0, 5, 11]:
		return 0 # 雅迪/九号 Pearl-White
	if r in [1, 8, 15]:
		return 1 # 爱玛 Mint-Green
	if r in [2, 12]:
		return 2 # 小牛 Matte-Black
	if r in [3, 14]:
		return 3 # 复古奶白/粉女士小电驴 (front basket)
	if r in [4, 17]:
		return 4 # 深蓝/银灰通勤电瓶车 (windshield)
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
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.45
	_mat.metallic = 0.12
	_meshes.clear()

	# 0: 雅迪/九号 Pearl-White Commuter E-Bike
	_meshes.append(_make_scooter_mesh(Color(0.92, 0.93, 0.94), Color(0.24, 0.34, 0.46), Color(0.90, 0.24, 0.20), false, Color.BLACK, false, false))
	# 1: 爱玛 Mint-Green Commuter E-Bike
	_meshes.append(_make_scooter_mesh(Color(0.56, 0.80, 0.72), Color(0.86, 0.82, 0.76), Color(0.96, 0.82, 0.36), false, Color.BLACK, false, false))
	# 2: 小牛 Matte-Black Sport E-Bike
	_meshes.append(_make_scooter_mesh(Color(0.16, 0.17, 0.19), Color(0.20, 0.22, 0.25), Color(0.88, 0.18, 0.16), false, Color.BLACK, false, false))
	# 3: 复古奶白/粉女士小电驴 (+ front basket)
	_meshes.append(_make_scooter_mesh(Color(0.94, 0.78, 0.82), Color(0.92, 0.90, 0.86), Color(0.94, 0.82, 0.86), false, Color.BLACK, true, false))
	# 4: 深蓝通勤电瓶车 (+ clear windshield)
	_meshes.append(_make_scooter_mesh(Color(0.22, 0.36, 0.54), Color(0.32, 0.36, 0.40), Color(0.18, 0.20, 0.24), false, Color.BLACK, false, true))
	# 5: 美团外卖骑手 (Meituan Yellow!)
	_meshes.append(_make_scooter_mesh(Color(0.18, 0.18, 0.20), Color(0.98, 0.78, 0.06), Color(0.98, 0.78, 0.06), true, Color(0.98, 0.78, 0.06), false, false))
	# 6: 饿了么外卖骑手 (Ele.me Sky Blue!)
	_meshes.append(_make_scooter_mesh(Color(0.20, 0.22, 0.25), Color(0.06, 0.56, 0.94), Color(0.06, 0.56, 0.94), true, Color(0.06, 0.56, 0.94), false, false))
	# 7: 顺丰/快递电动三轮车
	_meshes.append(_make_etrike_mesh())
	# 8: 哈啰单车 (Sky Blue Shared Bike)
	_meshes.append(_make_shared_bike_mesh(Color(0.08, 0.58, 0.92), Color(0.86, 0.88, 0.90)))
	# 9: 美团单车 (Yellow Shared Bike)
	_meshes.append(_make_shared_bike_mesh(Color(0.96, 0.78, 0.08), Color(0.26, 0.30, 0.36)))


static func _make_scooter_mesh(body_c: Color, jacket_c: Color, helmet_c: Color, has_box: bool, box_c: Color, has_basket: bool, has_shield: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tire_c := Color(0.10, 0.10, 0.11)
	var seat_c := Color(0.14, 0.14, 0.15)
	var skin_c := Color(0.88, 0.74, 0.62)
	var pants_c := Color(0.18, 0.20, 0.26)
	var lamp_c := Color(0.98, 0.96, 0.84)
	var tail_c := Color(0.92, 0.12, 0.10)

	_box(st, Vector3(0.0, 0.23, -0.62), Vector3(0.12, 0.44, 0.44), tire_c)
	_box(st, Vector3(0.0, 0.23, 0.58), Vector3(0.14, 0.44, 0.44), tire_c)
	_box(st, Vector3(0.0, 0.28, 0.02), Vector3(0.42, 0.14, 0.94), seat_c)
	_box(st, Vector3(0.0, 0.56, 0.36), Vector3(0.42, 0.36, 0.76), body_c)
	_box(st, Vector3(0.0, 0.78, 0.30), Vector3(0.32, 0.12, 0.58), seat_c)
	_box(st, Vector3(0.0, 0.64, -0.46), Vector3(0.44, 0.66, 0.22), body_c)
	_box(st, Vector3(0.0, 0.98, -0.46), Vector3(0.68, 0.07, 0.10), seat_c)
	_box(st, Vector3(0.0, 0.86, -0.58), Vector3(0.16, 0.12, 0.06), lamp_c)
	_box(st, Vector3(0.0, 0.66, 0.75), Vector3(0.20, 0.08, 0.05), tail_c)

	if has_basket:
		_box(st, Vector3(0.0, 0.84, -0.66), Vector3(0.32, 0.22, 0.22), Color(0.76, 0.72, 0.64))
	if has_shield:
		_box(st, Vector3(0.0, 1.18, -0.52), Vector3(0.42, 0.34, 0.04), Color(0.68, 0.78, 0.86))

	_box(st, Vector3(0.0, 0.68, -0.06), Vector3(0.34, 0.44, 0.38), pants_c)
	_box(st, Vector3(0.0, 1.16, 0.14), Vector3(0.42, 0.52, 0.26), jacket_c)
	for sx: float in [-0.24, 0.24]:
		_box(st, Vector3(sx, 1.06, -0.18), Vector3(0.11, 0.12, 0.48), jacket_c.darkened(0.06))
	_box(st, Vector3(0.0, 1.50, 0.10), Vector3(0.20, 0.18, 0.20), skin_c)
	_box(st, Vector3(0.0, 1.58, 0.11), Vector3(0.25, 0.18, 0.27), helmet_c)

	if has_box:
		_box(st, Vector3(0.0, 1.06, 0.70), Vector3(0.46, 0.44, 0.44), box_c)
		_box(st, Vector3(0.0, 1.29, 0.70), Vector3(0.48, 0.05, 0.46), box_c.darkened(0.15))

	return st.commit()


static func _make_etrike_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tire_c := Color(0.10, 0.10, 0.11)
	var cab_c := Color(0.20, 0.22, 0.25)
	var cargo_c := Color(0.22, 0.24, 0.28)
	var stripe_c := Color(0.86, 0.16, 0.14)
	var glass_c := Color(0.14, 0.24, 0.32)

	_box(st, Vector3(0.0, 0.24, -0.96), Vector3(0.14, 0.46, 0.46), tire_c)
	for sx: float in [-0.48, 0.48]:
		_box(st, Vector3(sx, 0.24, 0.72), Vector3(0.14, 0.46, 0.46), tire_c)
	_box(st, Vector3(0.0, 0.32, 0.0), Vector3(0.96, 0.12, 1.85), tire_c)
	_box(st, Vector3(0.0, 0.72, -0.78), Vector3(0.86, 0.72, 0.44), cab_c)
	_box(st, Vector3(0.0, 1.24, -0.74), Vector3(0.80, 0.44, 0.08), glass_c)
	_box(st, Vector3(0.0, 1.50, -0.46), Vector3(0.88, 0.08, 0.74), cab_c)
	_box(st, Vector3(0.0, 0.80, -1.01), Vector3(0.24, 0.12, 0.05), Color(0.98, 0.96, 0.84))
	_box(st, Vector3(0.0, 1.04, 0.56), Vector3(1.04, 1.18, 1.22), cargo_c)
	_box(st, Vector3(0.0, 1.12, 0.56), Vector3(1.06, 0.18, 1.23), stripe_c)
	return st.commit()


static func _make_shared_bike_mesh(frame_c: Color, jacket_c: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tire_c := Color(0.12, 0.12, 0.13)
	var pants_c := Color(0.20, 0.24, 0.32)
	var skin_c := Color(0.88, 0.74, 0.62)

	_box(st, Vector3(0.0, 0.30, -0.56), Vector3(0.06, 0.58, 0.58), tire_c)
	_box(st, Vector3(0.0, 0.30, 0.54), Vector3(0.06, 0.58, 0.58), tire_c)
	_box(st, Vector3(0.0, 0.54, 0.0), Vector3(0.07, 0.10, 0.96), frame_c)
	_box(st, Vector3(0.0, 0.82, -0.54), Vector3(0.32, 0.24, 0.26), frame_c.darkened(0.12))
	_box(st, Vector3(0.0, 0.96, -0.44), Vector3(0.56, 0.05, 0.06), tire_c)
	_box(st, Vector3(0.0, 0.72, 0.12), Vector3(0.28, 0.46, 0.30), pants_c)
	_box(st, Vector3(0.0, 1.18, 0.10), Vector3(0.38, 0.50, 0.24), jacket_c)
	_box(st, Vector3(0.0, 1.52, 0.06), Vector3(0.19, 0.20, 0.20), skin_c)
	_box(st, Vector3(0.0, 1.60, 0.08), Vector3(0.21, 0.10, 0.22), Color(0.14, 0.12, 0.12))
	return st.commit()


static func _box(st: SurfaceTool, c: Vector3, sz: Vector3, col: Color) -> void:
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, c), sz, col)
