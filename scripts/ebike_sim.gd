class_name EbikeSim
extends Node3D

# Authentic Chinese Non-Motorized Bike-Lane Traffic (电瓶车 / 外卖骑手 / 快递电动三轮 / 共享单车):
#   Spawns ~56 lively e-bikes & couriers riding strictly in the outer bike lane (非机动车道)
#   on wide Chinese streets (offset = hw - 1.12m), obeying red traffic lights, yielding to trams,
#   and never interfering with motor cars or tram rails!

const MAX_EBIKES := 56

var ebikes: Array[Dictionary] = []
var _meshes: Array[ArrayMesh] = []
var _mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _bike_edges: Array[int] = []


func _ready() -> void:
	_rng.randomize()
	_build_meshes()


func rebuild(graph: NetworkGraph, focus_pos: Vector3) -> void:
	for c in get_children():
		c.queue_free()
	ebikes.clear()
	_bike_edges.clear()

	if not bool(graph.get_meta("is_chinese_city", false)):
		return
	if _meshes.is_empty():
		_build_meshes()

	for eid_v in graph.edges.keys():
		var eid := int(eid_v)
		var ed: Dictionary = graph.edges[eid]
		if bool(ed.get("underground", false)):
			continue
		if float(ed.get("width", 10.0)) >= 10.5 and float(ed.get("length", 0.0)) >= 22.0:
			_bike_edges.append(eid)

	if _bike_edges.is_empty():
		return

	var target := mini(MAX_EBIKES, maxi(24, _bike_edges.size() / 5))
	for i in range(target):
		var eid := _pick_edge(graph, focus_pos, i < (target * 3) / 4)
		if eid < 0:
			continue
		var ed: Dictionary = graph.edges[eid]
		var elen := float(ed["length"])
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		var s_init := lerpf(10.0, elen - 10.0, _rng.randf())
		var var_idx := _pick_variant_idx(i)
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes[var_idx]
		mi.material_override = _mat
		mi.visibility_range_end = 210.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

		# Couriers ride a bit brisker (6.5..8.2 m/s), shared bikes slower (4.2..5.4 m/s), commuter e-bikes (5.5..7.2 m/s)
		var cruise := 6.4 + _rng.randf() * 1.4
		if var_idx == 3 or var_idx == 4:
			cruise = 6.8 + _rng.randf() * 1.6 # 美团 / 饿了么 delivery couriers
		elif var_idx == 5:
			cruise = 5.4 + _rng.randf() * 1.1 # 顺丰/快递电动三轮车
		elif var_idx == 6:
			cruise = 4.2 + _rng.randf() * 1.2 # 共享单车

		var eb := {
			"node": mi,
			"edge_id": eid,
			"dir": dir,
			"s": s_init,
			"speed": cruise * 0.8,
			"cruise": cruise,
			"lane_jitter": _rng.randf_range(-0.32, 0.32),
			"pos": Vector3.ZERO,
			"fwd": Vector3.FORWARD,
			"stuck_t": 0.0,
		}
		_update_transform(eb, graph)
		ebikes.append(eb)


func step(dt: float, graph: NetworkGraph, traffic: TrafficSim, trams: Array[Dictionary], focus_pos: Vector3) -> void:
	if ebikes.is_empty() or _bike_edges.is_empty():
		return
	var dt_c := minf(dt, 0.05)

	for i in range(ebikes.size()):
		var eb: Dictionary = ebikes[i]
		var pos: Vector3 = eb["pos"]
		if pos.distance_squared_to(focus_pos) > 390.0 * 390.0:
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
		if dist_end < 12.0:
			target_spd = minf(target_spd, 4.2)

		# 1) Same-direction e-bike spacing (never locks head-on with opposite bike lane!)
		for j in range(ebikes.size()):
			if j == i:
				continue
			var oth: Dictionary = ebikes[j]
			if fwd.dot(oth["fwd"] as Vector3) < 0.35:
				continue
			var dv := (oth["pos"] as Vector3) - pos
			if dv.length_squared() > 64.0:
				continue
			var along := dv.dot(fwd)
			var lat := absf(dv.dot(right))
			if along > 0.2 and lat < 1.05:
				if along < 3.4:
					target_spd = 0.0
				elif along < 7.0:
					target_spd = minf(target_spd, float(oth["speed"]) * 0.85)

		# 2) Obey intersection traffic signals cleanly behind crosswalk
		var stop_d := 8.8
		if dist_end >= stop_d - 1.2 and dist_end <= stop_d + 10.0 and traffic.signals.has(next_nid):
			var aspect := traffic.get_signal_aspect(next_nid, Vector2(fwd.x, fwd.z))
			if aspect != "green":
				target_spd = 0.0 if dist_end <= stop_d + 1.4 else minf(target_spd, (dist_end - stop_d) * 0.65)

		# 3) Yield to any nearby tram crossing the intersection
		for tr: Dictionary in trams:
			var tp: Vector3 = tr.get("pos", Vector3.ZERO)
			var dv_t := tp - pos
			if dv_t.length_squared() < 256.0:
				var tf: Vector3 = tr.get("fwd", Vector3.FORWARD)
				# Only hold if crossing or close directly ahead (parallel bike lanes are well clear of center rails!)
				if absf(fwd.dot(tf)) < 0.78:
					var along_t := dv_t.dot(fwd)
					if along_t > -1.0 and along_t < 15.0:
						target_spd = 0.0
						break

		var spd := move_toward(float(eb["speed"]), target_spd, (14.0 if target_spd < float(eb["speed"]) else 4.2) * dt_c)
		eb["speed"] = spd

		var st_t := (float(eb.get("stuck_t", 0.0)) + dt_c) if spd < 0.2 else 0.0
		eb["stuck_t"] = st_t
		if st_t >= 22.0:
			_respawn(eb, graph, focus_pos)
			continue

		var s_next := s_now + dir * spd * dt_c
		if s_next >= elen - 2.0 or s_next <= 2.0:
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
		if bool(ed.get("underground", false)) or float(ed.get("length", 0.0)) < 16.0:
			continue
		if float(ed.get("width", 10.0)) < 9.5:
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
		# Reverse cleanly onto the opposite bike lane
		var ed0: Dictionary = graph.edges[prev_eid]
		eb["dir"] = -float(eb["dir"])
		eb["s"] = 3.0 if float(eb["dir"]) > 0.0 else maxf(3.0, float(ed0["length"]) - 3.0)
		return

	# Strongly prefer going straight along the avenue (75%) so bike streams look natural!
	var pick: Dictionary = best_straight if (best_dot > 0.55 and _rng.randf() < 0.75) else cands[_rng.randi() % cands.size()]
	eb["edge_id"] = int(pick["eid"])
	eb["dir"] = float(pick["dir"])
	eb["s"] = 3.0 if float(pick["dir"]) > 0.0 else maxf(3.0, float(pick["len"]) - 3.0)


func _respawn(eb: Dictionary, graph: NetworkGraph, focus_pos: Vector3) -> void:
	var eid := _pick_edge(graph, focus_pos, true)
	if eid < 0:
		return
	var ed: Dictionary = graph.edges[eid]
	var elen := float(ed["length"])
	eb["edge_id"] = eid
	eb["dir"] = 1.0 if _rng.randf() < 0.5 else -1.0
	eb["s"] = lerpf(8.0, maxf(9.0, elen - 8.0), _rng.randf())
	eb["speed"] = float(eb["cruise"]) * 0.75
	eb["stuck_t"] = 0.0
	_update_transform(eb, graph)


func _pick_edge(graph: NetworkGraph, focus_pos: Vector3, near: bool) -> int:
	if _bike_edges.is_empty():
		return -1
	var best_eid := -1
	var best_d2 := 1e18
	for _k in range(18):
		var cand := _bike_edges[_rng.randi() % _bike_edges.size()]
		if not near:
			return cand
		var pts: Array = graph.edges[cand]["pts"]
		var mp: Vector2 = pts[pts.size() / 2]
		var d2 := Vector2(mp.x - focus_pos.x, mp.y - focus_pos.z).length_squared()
		if d2 >= 35.0 * 35.0 and d2 <= 320.0 * 320.0:
			return cand
		if d2 < best_d2:
			best_d2 = d2
			best_eid = cand
	return best_eid if best_eid >= 0 else _bike_edges[_rng.randi() % _bike_edges.size()]


func _update_transform(eb: Dictionary, graph: NetworkGraph) -> void:
	var eid := int(eb["edge_id"])
	var ed: Dictionary = graph.edges[eid]
	var elen := maxf(1.0, float(ed["length"]))
	var dir := float(eb["dir"])
	var s := clampf(float(eb["s"]), 0.0, elen)
	var hw := clampf(float(ed.get("width", 12.0)) * 0.5, 4.5, 13.5)
	# Ride right in the center of the outer Non-Motorized Bike Lane (hw - 1.12m)!
	var lat_off := maxf(2.4, hw - 1.12) + float(eb.get("lane_jitter", 0.0))
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
	var mi: MeshInstance3D = eb["node"]
	if is_instance_valid(mi):
		mi.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)


func _pick_variant_idx(i: int) -> int:
	# Realistic Chinese street ratio: ~52% commuter e-bikes, ~22% 美团/饿了么 couriers, ~12% cargo e-trikes, ~14% shared bikes
	var r := i % 16
	if r in [0, 3, 7]:
		return 0 # Pearl-White Commuter E-Bike (雅迪/九号)
	if r in [1, 8, 12]:
		return 1 # Mint-Green Commuter E-Bike (爱玛)
	if r in [2, 10]:
		return 2 # Matte-Black Sport E-Bike (小牛)
	if r in [4, 11]:
		return 3 # 美团外卖骑手 (Bright Yellow!)
	if r in [5, 14]:
		return 4 # 饿了么外卖骑手 (Sky Blue!)
	if r in [6, 15]:
		return 5 # 顺丰/快递电动三轮车 (Cargo E-Trike!)
	return 6     # 共享单车 (Meituan Yellow / Hellobike Blue)


func _build_meshes() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.45
	_mat.metallic = 0.12
	_meshes.clear()

	# 0: Pearl-White Commuter Scooter (雅迪/九号)
	_meshes.append(_make_scooter_mesh(Color(0.92, 0.93, 0.94), Color(0.24, 0.34, 0.46), Color(0.90, 0.24, 0.20), false, Color.BLACK))
	# 1: Mint-Green Commuter Scooter (爱玛)
	_meshes.append(_make_scooter_mesh(Color(0.56, 0.80, 0.72), Color(0.86, 0.82, 0.76), Color(0.96, 0.82, 0.36), false, Color.BLACK))
	# 2: Matte-Black Sport Scooter (小牛)
	_meshes.append(_make_scooter_mesh(Color(0.16, 0.17, 0.19), Color(0.20, 0.22, 0.25), Color(0.88, 0.18, 0.16), false, Color.BLACK))
	# 3: 美团外卖骑手 (Iconic Meituan Yellow helmet + jacket + rear square insulated box!)
	_meshes.append(_make_scooter_mesh(Color(0.18, 0.18, 0.20), Color(0.98, 0.78, 0.06), Color(0.98, 0.78, 0.06), true, Color(0.98, 0.78, 0.06)))
	# 4: 饿了么外卖骑手 (Iconic Ele.me Sky-Blue helmet + jacket + rear square insulated box!)
	_meshes.append(_make_scooter_mesh(Color(0.20, 0.22, 0.25), Color(0.06, 0.56, 0.94), Color(0.06, 0.56, 0.94), true, Color(0.06, 0.56, 0.94)))
	# 5: 顺丰/快递电动三轮车 (Chinese Express Cargo E-Trike with rear enclosed parcel box!)
	_meshes.append(_make_etrike_mesh())
	# 6: 共享单车 (Shared Bicycle — Hellobike Sky-Blue frame + front basket + commuter rider)
	_meshes.append(_make_shared_bike_mesh())


static func _make_scooter_mesh(body_c: Color, jacket_c: Color, helmet_c: Color, has_box: bool, box_c: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tire_c := Color(0.10, 0.10, 0.11)
	var seat_c := Color(0.14, 0.14, 0.15)
	var skin_c := Color(0.88, 0.74, 0.62)
	var pants_c := Color(0.18, 0.20, 0.26)
	var lamp_c := Color(0.98, 0.96, 0.84)
	var tail_c := Color(0.92, 0.12, 0.10)

	# Front (-Z) & rear (+Z) wheels
	_box(st, Vector3(0.0, 0.23, -0.62), Vector3(0.12, 0.44, 0.44), tire_c)
	_box(st, Vector3(0.0, 0.23, 0.58), Vector3(0.14, 0.44, 0.44), tire_c)
	# Floorboard deck & battery tub
	_box(st, Vector3(0.0, 0.28, 0.02), Vector3(0.42, 0.14, 0.94), seat_c)
	# Rear body fairing + seat
	_box(st, Vector3(0.0, 0.56, 0.36), Vector3(0.42, 0.36, 0.76), body_c)
	_box(st, Vector3(0.0, 0.78, 0.30), Vector3(0.32, 0.12, 0.58), seat_c)
	# Front leg-shield apron, steering column, handlebar & LED headlight!
	_box(st, Vector3(0.0, 0.64, -0.46), Vector3(0.44, 0.66, 0.22), body_c)
	_box(st, Vector3(0.0, 0.98, -0.46), Vector3(0.68, 0.07, 0.10), seat_c)
	_box(st, Vector3(0.0, 0.86, -0.58), Vector3(0.16, 0.12, 0.06), lamp_c)
	_box(st, Vector3(0.0, 0.66, 0.75), Vector3(0.20, 0.08, 0.05), tail_c)

	# Rider (seated legs, torso jacket, reaching arms, head + safety helmet!)
	_box(st, Vector3(0.0, 0.68, -0.06), Vector3(0.34, 0.44, 0.38), pants_c)
	_box(st, Vector3(0.0, 1.16, 0.14), Vector3(0.42, 0.52, 0.26), jacket_c)
	for sx: float in [-0.24, 0.24]:
		_box(st, Vector3(sx, 1.06, -0.18), Vector3(0.11, 0.12, 0.48), jacket_c.darkened(0.06))
	_box(st, Vector3(0.0, 1.50, 0.10), Vector3(0.20, 0.18, 0.20), skin_c)
	_box(st, Vector3(0.0, 1.58, 0.11), Vector3(0.25, 0.18, 0.27), helmet_c)

	# Delivery Courier Insulated Rear Box (外卖保温箱!)
	if has_box:
		_box(st, Vector3(0.0, 1.06, 0.70), Vector3(0.46, 0.44, 0.44), box_c)
		_box(st, Vector3(0.0, 1.29, 0.70), Vector3(0.48, 0.05, 0.46), box_c.darkened(0.15))

	return st.commit()


static func _make_etrike_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tire_c := Color(0.10, 0.10, 0.11)
	var cab_c := Color(0.20, 0.22, 0.25) # SF-Express dark slate / red-trimmed cargo trike
	var cargo_c := Color(0.22, 0.24, 0.28)
	var stripe_c := Color(0.86, 0.16, 0.14)
	var glass_c := Color(0.14, 0.24, 0.32)

	# 1 front wheel + 2 rear wheels
	_box(st, Vector3(0.0, 0.24, -0.96), Vector3(0.14, 0.46, 0.46), tire_c)
	for sx: float in [-0.48, 0.48]:
		_box(st, Vector3(sx, 0.24, 0.72), Vector3(0.14, 0.46, 0.46), tire_c)
	# Chassis floor
	_box(st, Vector3(0.0, 0.32, 0.0), Vector3(0.96, 0.12, 1.85), tire_c)
	# Front semi-enclosed driver canopy + windshield
	_box(st, Vector3(0.0, 0.72, -0.78), Vector3(0.86, 0.72, 0.44), cab_c)
	_box(st, Vector3(0.0, 1.24, -0.74), Vector3(0.80, 0.44, 0.08), glass_c)
	_box(st, Vector3(0.0, 1.50, -0.46), Vector3(0.88, 0.08, 0.74), cab_c)
	_box(st, Vector3(0.0, 0.80, -1.01), Vector3(0.24, 0.12, 0.05), Color(0.98, 0.96, 0.84))
	# Enclosed rear express delivery parcel box
	_box(st, Vector3(0.0, 1.04, 0.56), Vector3(1.04, 1.18, 1.22), cargo_c)
	_box(st, Vector3(0.0, 1.12, 0.56), Vector3(1.06, 0.18, 1.23), stripe_c)
	return st.commit()


static func _make_shared_bike_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var frame_c := Color(0.08, 0.58, 0.92) # Hellobike blue
	var tire_c := Color(0.12, 0.12, 0.13)
	var jacket_c := Color(0.86, 0.88, 0.90)
	var pants_c := Color(0.20, 0.24, 0.32)
	var skin_c := Color(0.88, 0.74, 0.62)

	# Slender bicycle wheels
	_box(st, Vector3(0.0, 0.30, -0.56), Vector3(0.06, 0.58, 0.58), tire_c)
	_box(st, Vector3(0.0, 0.30, 0.54), Vector3(0.06, 0.58, 0.58), tire_c)
	# Frame tubes + front basket + handlebar
	_box(st, Vector3(0.0, 0.54, 0.0), Vector3(0.07, 0.10, 0.96), frame_c)
	_box(st, Vector3(0.0, 0.82, -0.54), Vector3(0.32, 0.24, 0.26), frame_c.darkened(0.12))
	_box(st, Vector3(0.0, 0.96, -0.44), Vector3(0.56, 0.05, 0.06), tire_c)
	# Cyclist
	_box(st, Vector3(0.0, 0.72, 0.12), Vector3(0.28, 0.46, 0.30), pants_c)
	_box(st, Vector3(0.0, 1.18, 0.10), Vector3(0.38, 0.50, 0.24), jacket_c)
	_box(st, Vector3(0.0, 1.52, 0.06), Vector3(0.19, 0.20, 0.20), skin_c)
	_box(st, Vector3(0.0, 1.60, 0.08), Vector3(0.21, 0.10, 0.22), Color(0.14, 0.12, 0.12))
	return st.commit()


static func _box(st: SurfaceTool, c: Vector3, sz: Vector3, col: Color) -> void:
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, c), sz, col)
