class_name PassengerSim
extends Node3D

const SPAWN_RATES := [0.0, 0.35, 0.75, 1.45, 2.55, 4.50]
const SPAWN_LEVEL_NAMES := ["", "1档 稀少", "2档 较少", "3档 标准", "4档 繁忙", "5档 高峰"]
const SPAWN_LEVEL_NAMES_EN := ["", "Lv.1 Sparse", "Lv.2 Light", "Lv.3 Normal", "Lv.4 Busy", "Lv.5 Peak"]


static func spawn_level_name(lvl: int) -> String:
	var idx := clampi(lvl, 1, SPAWN_LEVEL_NAMES.size() - 1)
	return SPAWN_LEVEL_NAMES_EN[idx] if L10n.is_en() else SPAWN_LEVEL_NAMES[idx]

var spawn_level := 3 # 1..5
var total_delivered := 0
var total_boarded := 0
var total_transfers := 0
var station_boarded: Dictionary = {}  # station_id -> int
var station_wait_sum: Dictionary = {} # station_id -> total seconds boarded passengers spent waiting
var station_wait_n: Dictionary = {}   # station_id -> number of boarded passengers in that total
var station_alighted: Dictionary = {} # station_id -> int
var line_boarded: Dictionary = {}     # line_id -> int
var line_delivered: Dictionary = {}   # line_id -> int

# Cached transit transfer graph for Express/Local timed-transfer (缓急接续换乘) pathfinding
var _net_sig := ""
var _all_served_sids: Array[int] = []
var _st_lines: Dictionary = {}        # station_id -> Array[int]
var _adj_transit: Dictionary = {}     # "sid:lid" -> Array[{to_key, sid, lid, cost, express}]
var _route_cache: Dictionary = {}     # "orig:dest" -> Array[Dictionary] (legs)

# station_id (int) -> Array[Dictionary] ({dest_sid: int, line_id: int, agent: Dictionary})
var station_queues: Dictionary = {}
var _station_views: Dictionary = {}
var _active_walkers: Array[Dictionary] = []

var _spawn_accum := 0.0
var _idle_time := 0.0
var _rng := RandomNumberGenerator.new()

var _coat_mats: Array[Material] = []
var _pants_mats: Array[Material] = []
var _skin_mats: Array[Material] = []
var _hair_mats: Array[Material] = []
var _face_mats: Array[Material] = []
var _shoe_mat: StandardMaterial3D
var _shoe_sole_mat: StandardMaterial3D
var _belt_mat: StandardMaterial3D
var _bag_mat: StandardMaterial3D
var _shirt_mat: StandardMaterial3D
var _acc_mats: Array[Material] = []
var _phone_mat: StandardMaterial3D
var _screen_mat: StandardMaterial3D
var _sneaker_mat: StandardMaterial3D
var _zipper_mat: StandardMaterial3D
var _strap_mat: StandardMaterial3D

var _leg_mesh: CapsuleMesh
var _shoe_mesh: CapsuleMesh
var _torso_mesh: CapsuleMesh
var _arm_mesh: CapsuleMesh
var _hand_mesh: SphereMesh
var _head_mesh: SphereMesh
var _hair_dome_mesh: SphereMesh


func _ready() -> void:
	_rng.randomize()
	var fab_shader := load("res://shaders/fabric_person.gdshader") as Shader

	# Realistic muted urban commuter coat/jacket palette (Cities: Skylines II style)
	var coat_colors: Array[Color] = [
		Color(0.14, 0.22, 0.34), # Navy wool coat
		Color(0.52, 0.39, 0.26), # Camel trench
		Color(0.20, 0.28, 0.22), # Olive parka
		Color(0.24, 0.25, 0.28), # Charcoal blazer
		Color(0.44, 0.17, 0.18), # Burgundy jacket
		Color(0.32, 0.38, 0.44), # Slate denim hoodie
		Color(0.58, 0.54, 0.48), # Warm stone trench
		Color(0.18, 0.32, 0.36), # Deep teal windbreaker
		Color(0.62, 0.15, 0.14), # Red puffer
		Color(0.72, 0.56, 0.18), # Mustard raincoat
		Color(0.86, 0.86, 0.83), # Off-white knit
		Color(0.48, 0.62, 0.78), # Sky-blue shirt jacket
		Color(0.78, 0.52, 0.56), # Dusty pink coat
		Color(0.16, 0.38, 0.24), # Forest green anorak
		Color(0.08, 0.08, 0.09), # Black leather jacket
		Color(0.50, 0.46, 0.66), # Lavender hoodie
	]
	for c: Color in coat_colors:
		var sm := ShaderMaterial.new()
		sm.shader = fab_shader
		sm.set_shader_parameter("base_tint", c)
		sm.set_shader_parameter("is_skin", 0.0)
		_coat_mats.append(sm)

	var pants_colors: Array[Color] = [
		Color(0.20, 0.30, 0.46), # Classic blue denim jeans
		Color(0.34, 0.44, 0.56), # Light wash denim
		Color(0.56, 0.49, 0.38), # Warm khaki chinos
		Color(0.36, 0.38, 0.41), # Medium grey wool slacks
		Color(0.26, 0.32, 0.24), # Olive twill trousers
		Color(0.16, 0.20, 0.30), # Navy dress trousers
		Color(0.42, 0.34, 0.28), # Warm brown corduroy
		Color(0.22, 0.22, 0.25), # Charcoal pants
		Color(0.07, 0.07, 0.08), # Black skinny jeans
		Color(0.74, 0.70, 0.62), # Stone chinos
	]
	for pc: Color in pants_colors:
		var pm := ShaderMaterial.new()
		pm.shader = fab_shader
		pm.set_shader_parameter("base_tint", pc)
		pm.set_shader_parameter("is_skin", 0.0)
		_pants_mats.append(pm)

	var skin_cols: Array[Color] = [Color(0.87, 0.71, 0.60), Color(0.78, 0.60, 0.47), Color(0.91, 0.77, 0.67), Color(0.54, 0.38, 0.28)]
	var hair_cols: Array[Color] = [Color(0.11, 0.09, 0.08), Color(0.24, 0.15, 0.10), Color(0.38, 0.28, 0.16), Color(0.17, 0.16, 0.16)]
	for sc: Color in skin_cols:
		var skm := ShaderMaterial.new()
		skm.shader = fab_shader
		skm.set_shader_parameter("base_tint", sc)
		skm.set_shader_parameter("is_skin", 1.0)
		_skin_mats.append(skm)

	for hc: Color in hair_cols:
		var hm := StandardMaterial3D.new()
		hm.albedo_color = hc
		hm.roughness = 0.78
		_hair_mats.append(hm)

	for fi in range(skin_cols.size()):
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = CabTextureGen.get_person_face_tex(skin_cols[fi], hair_cols[fi % hair_cols.size()])
		fm.roughness = 0.62
		_face_mats.append(fm)

	_shoe_mat = StandardMaterial3D.new()
	_shoe_mat.albedo_color = Color(0.14, 0.14, 0.15)
	_shoe_mat.roughness = 0.72

	_shoe_sole_mat = StandardMaterial3D.new()
	_shoe_sole_mat.albedo_color = Color(0.82, 0.81, 0.79)
	_shoe_sole_mat.roughness = 0.82

	_belt_mat = StandardMaterial3D.new()
	_belt_mat.albedo_color = Color(0.18, 0.13, 0.10)
	_belt_mat.roughness = 0.56

	_bag_mat = StandardMaterial3D.new()
	_bag_mat.albedo_color = Color(0.19, 0.17, 0.16)
	_bag_mat.roughness = 0.80

	var acc_cols: Array[Color] = [
		Color(0.10, 0.10, 0.11), Color(0.42, 0.26, 0.14), Color(0.60, 0.12, 0.12), Color(0.14, 0.24, 0.42),
		Color(0.80, 0.78, 0.74), Color(0.28, 0.40, 0.22), Color(0.82, 0.60, 0.20), Color(0.55, 0.55, 0.58),
	]
	for ac: Color in acc_cols:
		var am := StandardMaterial3D.new()
		am.albedo_color = ac
		am.roughness = 0.62
		_acc_mats.append(am)
	_phone_mat = StandardMaterial3D.new()
	_phone_mat.albedo_color = Color(0.05, 0.05, 0.06)
	_phone_mat.roughness = 0.2
	_phone_mat.metallic = 0.5
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.3, 0.5, 0.7)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0.55, 0.75, 1.0)
	_screen_mat.emission_energy_multiplier = 1.2
	_sneaker_mat = StandardMaterial3D.new()
	_sneaker_mat.albedo_color = Color(0.88, 0.88, 0.86)
	_sneaker_mat.roughness = 0.7
	_shirt_mat = StandardMaterial3D.new()
	_shirt_mat.albedo_color = Color(0.88, 0.87, 0.85)
	_shirt_mat.roughness = 0.86
	_zipper_mat = StandardMaterial3D.new()
	_zipper_mat.albedo_color = Color(0.64, 0.66, 0.70)
	_zipper_mat.metallic = 0.72
	_zipper_mat.roughness = 0.34
	_strap_mat = StandardMaterial3D.new()
	_strap_mat.albedo_color = Color(0.15, 0.15, 0.17)
	_strap_mat.roughness = 0.78

	_leg_mesh = CapsuleMesh.new()
	_leg_mesh.radius = 0.056; _leg_mesh.height = 0.43; _leg_mesh.radial_segments = 10; _leg_mesh.rings = 4

	_shoe_mesh = CapsuleMesh.new()
	_shoe_mesh.radius = 0.046; _shoe_mesh.height = 0.22; _shoe_mesh.radial_segments = 8; _shoe_mesh.rings = 3

	_torso_mesh = CapsuleMesh.new()
	_torso_mesh.radius = 0.140; _torso_mesh.height = 0.56; _torso_mesh.radial_segments = 12; _torso_mesh.rings = 5

	_arm_mesh = CapsuleMesh.new()
	_arm_mesh.radius = 0.042; _arm_mesh.height = 0.30; _arm_mesh.radial_segments = 8; _arm_mesh.rings = 3

	_hand_mesh = SphereMesh.new()
	_hand_mesh.radius = 0.036; _hand_mesh.height = 0.072; _hand_mesh.radial_segments = 8; _hand_mesh.rings = 4

	_head_mesh = SphereMesh.new()
	_head_mesh.radius = 0.098; _head_mesh.height = 0.215; _head_mesh.radial_segments = 12; _head_mesh.rings = 7

	_hair_dome_mesh = SphereMesh.new()
	_hair_dome_mesh.radius = 0.104; _hair_dome_mesh.height = 0.195; _hair_dome_mesh.radial_segments = 12; _hair_dome_mesh.rings = 6


func reset_for_stations(station_views: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	station_queues.clear()
	station_boarded.clear()
	station_wait_sum.clear()
	station_wait_n.clear()
	station_alighted.clear()
	line_boarded.clear()
	line_delivered.clear()
	_active_walkers.clear()
	total_transfers = 0
	_net_sig = ""
	_route_cache.clear()
	_all_served_sids.clear()
	_st_lines.clear()
	_adj_transit.clear()
	_station_views = station_views
	for sid: int in _station_views.keys():
		station_queues[sid] = []
		station_boarded[sid] = 0
		station_alighted[sid] = 0
		_refresh_station_label(sid)


func has_waiting_passengers(station_id: int) -> bool:
	return get_boardable_count(station_id) > 0


func has_waiting_passengers_for_tram(station_id: int, tram_state: Dictionary, upcoming_sids: Array[int] = []) -> bool:
	return get_boardable_count_for_tram(station_id, tram_state, upcoming_sids) > 0


func get_boardable_count_for_tram(station_id: int, tram_state: Dictionary, upcoming_sids: Array[int] = []) -> int:
	if not _station_views.has(station_id):
		return 0
	var sview: Dictionary = _station_views[station_id]
	var plat_view := _platform_view_for(tram_state, sview)
	var cnt := 0
	for item: Dictionary in station_queues.get(station_id, []):
		if not _is_boardable(item) or not _item_on_platform_view(item, sview, plat_view):
			continue
		if _item_matches_tram(item, tram_state, upcoming_sids):
			cnt += 1
	return cnt


static func _item_final_dest(item: Dictionary) -> int:
	var xlegs: Array = item.get("xfer_legs", [])
	if not xlegs.is_empty():
		var last_leg = xlegs[xlegs.size() - 1]
		if last_leg is Dictionary and (last_leg as Dictionary).has("to"):
			return int((last_leg as Dictionary)["to"])
	return int(item.get("dest_sid", -1))


func _item_matches_tram(item: Dictionary, tram_state: Dictionary, upcoming_sids: Array[int]) -> bool:
	var dest := int(item.get("dest_sid", -1))
	var final_dest := _item_final_dest(item)
	var reaches_direct_final := (final_dest >= 0 and not upcoming_sids.is_empty() and upcoming_sids.has(final_dest))
	if not upcoming_sids.is_empty() and not upcoming_sids.has(dest) and not reaches_direct_final:
		return false
	var tr_exp := bool(tram_state.get("express", false))
	var want_exp_set := item.has("want_express")
	var want_exp := bool(item.get("want_express", false))
	var is_xfer := bool(item.get("is_transfer", false))
	var has_more_legs := not (item.get("xfer_legs", []) as Array).is_empty()
	if want_exp_set and want_exp and not tr_exp:
		# Waiting specifically for an Express tram (e.g. Local -> Express timed transfer)
		var waited := _idle_time - float(item.get("t0", _idle_time))
		if is_xfer or has_more_legs or waited < 110.0:
			return false
	return true


func _ensure_transfer_graph(graph: NetworkGraph) -> void:
	if graph == null:
		return
	var sig_parts: PackedStringArray = []
	var lids := graph.lines.keys()
	lids.sort()
	for lid: int in lids:
		var ln: Dictionary = graph.lines[lid]
		sig_parts.append("%d:%d:%s" % [lid, 1 if bool(ln.get("express", false)) else 0, str(ln.get("station_ids", []))])
	var sig := "|".join(sig_parts)
	if sig == _net_sig:
		return
	_net_sig = sig
	_route_cache.clear()
	_all_served_sids.clear()
	_st_lines.clear()
	_adj_transit.clear()

	for lid: int in lids:
		var ln: Dictionary = graph.lines[lid]
		var exp_l := bool(ln.get("express", false))
		var raw_sids: Array = ln.get("station_ids", [])
		if raw_sids.size() < 2:
			continue
		var sids: Array[int] = []
		for r in raw_sids:
			var si := int(r)
			if graph.stations.has(si) and _station_views.has(si):
				sids.append(si)
		if sids.size() < 2:
			continue
		var is_closed_loop := sids.size() >= 3 and sids[0] == sids[sids.size() - 1]
		for si: int in sids:
			if not _all_served_sids.has(si):
				_all_served_sids.append(si)
			if not _st_lines.has(si):
				_st_lines[si] = []
			if not (_st_lines[si] as Array).has(lid):
				(_st_lines[si] as Array).append(lid)
		var spd_est := 15.5 if exp_l else 10.5
		var dwell_est := 10.0 if exp_l else 19.0
		for i in range(sids.size() - 1):
			var u := sids[i]
			var v := sids[i + 1]
			if u == v:
				continue
			var d_m := (graph.stations[u]["pos"] as Vector3).distance_to(graph.stations[v]["pos"] as Vector3)
			var cost := d_m / spd_est + dwell_est
			var ku := "%d:%d" % [u, lid]
			var kv := "%d:%d" % [v, lid]
			if not _adj_transit.has(ku):
				_adj_transit[ku] = []
			(_adj_transit[ku] as Array).append({"to": kv, "sid": v, "lid": lid, "cost": cost, "express": exp_l, "xfer": false})
			if not is_closed_loop:
				if not _adj_transit.has(kv):
					_adj_transit[kv] = []
				(_adj_transit[kv] as Array).append({"to": ku, "sid": u, "lid": lid, "cost": cost, "express": exp_l, "xfer": false})

	# Transfer edges at shared stations (low penalty for cross-platform twin-island 缓急接续换乘!)
	for sid: int in _st_lines.keys():
		var sl: Array = _st_lines[sid]
		if sl.size() < 2:
			continue
		var xfer_pen := 10.0 if graph.is_quad_island(sid) else 22.0
		for a_i in range(sl.size()):
			for b_i in range(sl.size()):
				if a_i == b_i:
					continue
				var la := int(sl[a_i])
				var lb := int(sl[b_i])
				var ka := "%d:%d" % [sid, la]
				var kb := "%d:%d" % [sid, lb]
				if not _adj_transit.has(ka):
					_adj_transit[ka] = []
				var exp_b := bool((graph.lines[lb] as Dictionary).get("express", false))
				(_adj_transit[ka] as Array).append({"to": kb, "sid": sid, "lid": lb, "cost": xfer_pen, "express": exp_b, "xfer": true})


# Computes shortest-time multi-leg journey (including Local <-> Express 缓急接续换乘) between orig_sid and dest_sid.
# Returns Array of legs: [{"line_id": int, "from": int, "to": int, "express": bool, "next_hop": int}, ...]
func _plan_passenger_legs(graph: NetworkGraph, orig_sid: int, dest_sid: int) -> Array:
	if orig_sid == dest_sid:
		return []
	_ensure_transfer_graph(graph)
	var ckey := "%d:%d" % [orig_sid, dest_sid]
	if _route_cache.has(ckey):
		return _route_cache[ckey]
	var orig_lines: Array = _st_lines.get(orig_sid, [])
	if orig_lines.is_empty():
		return []

	var dist := {}
	var prev := {}
	var visited := {}
	var frontier: Array[String] = []
	for lid: int in orig_lines:
		var k0 := "%d:%d" % [orig_sid, lid]
		dist[k0] = 0.0
		frontier.append(k0)

	var best_end := ""
	var best_cost := 1e18
	while not frontier.is_empty():
		var best_i := 0
		var best_d := float(dist[frontier[0]])
		for fi in range(1, frontier.size()):
			var fd := float(dist[frontier[fi]])
			if fd < best_d:
				best_d = fd
				best_i = fi
		var u_key := frontier[best_i]
		frontier.remove_at(best_i)
		if visited.has(u_key):
			continue
		visited[u_key] = true
		if best_d >= best_cost:
			break
		var u_sid := int(u_key.split(":")[0])
		if u_sid == dest_sid:
			best_cost = best_d
			best_end = u_key
			break
		for ed: Dictionary in _adj_transit.get(u_key, []):
			var v_key: String = ed["to"]
			if visited.has(v_key):
				continue
			var nd := best_d + float(ed["cost"])
			if nd < float(dist.get(v_key, 1e18)):
				dist[v_key] = nd
				prev[v_key] = {"from": u_key, "ed": ed}
				frontier.append(v_key)

	var legs: Array = []
	if best_end != "":
		var chain: Array = []
		var cur := best_end
		while prev.has(cur):
			var p: Dictionary = prev[cur]
			chain.append(p)
			cur = str(p["from"])
		chain.reverse()
		for step_d: Dictionary in chain:
			var ed: Dictionary = step_d["ed"]
			if bool(ed["xfer"]):
				continue
			var from_sid := int(str(step_d["from"]).split(":")[0])
			var to_sid := int(ed["sid"])
			var lid_e := int(ed["lid"])
			var exp_e := bool(ed["express"])
			if not legs.is_empty() and int((legs[legs.size() - 1] as Dictionary)["line_id"]) == lid_e:
				(legs[legs.size() - 1] as Dictionary)["to"] = to_sid
			else:
				legs.append({
					"line_id": lid_e,
					"from": from_sid,
					"to": to_sid,
					"next_hop": to_sid,
					"express": exp_e,
				})
	if legs.size() > 3:
		legs = []
	_route_cache[ckey] = legs
	return legs


static func _sub_view_for_pos(sview: Dictionary, pt: Vector3) -> Dictionary:
	if not sview.has("twins"):
		return sview
	var best: Dictionary = sview
	var best_d := 1e18
	for tw: Dictionary in sview["twins"]:
		var d := pt.distance_squared_to(tw.get("pos", Vector3.ZERO) as Vector3)
		if d < best_d:
			best_d = d
			best = tw
	return best


static func _item_on_platform_view(item: Dictionary, sview: Dictionary, plat_view: Dictionary) -> bool:
	if not sview.has("twins"):
		return true
	var ag: Dictionary = item.get("agent", {})
	if ag.is_empty() or not is_instance_valid(ag.get("node")):
		return true
	var pv: Dictionary = ag.get("plat_view", {})
	if not pv.is_empty():
		return pv.get("node") == plat_view.get("node")
	return _sub_view_for_pos(sview, (ag["node"] as Node3D).global_position).get("node") == plat_view.get("node")


# A queued passenger can board once they are up on the platform (not still walking in from the street ramp)
func _is_boardable(item: Dictionary) -> bool:
	var ag: Dictionary = item.get("agent", {})
	if ag.is_empty() or not is_instance_valid(ag.get("node")):
		return true
	return bool(ag.get("on_platform", false))


# Passengers already on the platform (the ones a train at the platform can take right now)
# Average wait of the passengers who boarded here (seconds; -1 = nobody yet)
func get_avg_wait_boarded(sid: int) -> float:
	var nb := int(station_wait_n.get(sid, 0))
	return float(station_wait_sum.get(sid, 0.0)) / float(nb) if nb > 0 else -1.0


# How long the people waiting here now have been waiting on average (seconds; -1 = nobody waiting)
func get_avg_wait_current(sid: int) -> float:
	var q: Array = station_queues.get(sid, [])
	if q.is_empty():
		return -1.0
	var tot := 0.0
	for item: Dictionary in q:
		tot += maxf(0.0, _idle_time - float(item.get("t0", _idle_time)))
	return tot / float(q.size())


func get_boardable_count(sid: int) -> int:
	var n := 0
	for item: Dictionary in station_queues.get(sid, []):
		if _is_boardable(item):
			n += 1
	return n


# Passengers who have entered the station ramp/stairs and are hurrying toward the platform
func get_approaching_count(sid: int) -> int:
	var n := 0
	for item: Dictionary in station_queues.get(sid, []):
		if not _is_boardable(item):
			n += 1
	return n


func has_approaching_passengers(sid: int) -> bool:
	return get_approaching_count(sid) > 0


func cycle_spawn_level() -> int:
	spawn_level = (spawn_level % 5) + 1
	return spawn_level


func set_spawn_level(lvl: int) -> void:
	spawn_level = clampi(lvl, 1, 5)


func get_total_waiting() -> int:
	var sum_w := 0
	for sid: int in station_queues.keys():
		sum_w += (station_queues[sid] as Array).size()
	return sum_w


func get_waiting_count(sid: int) -> int:
	if not station_queues.has(sid):
		return 0
	return (station_queues[sid] as Array).size()


func has_walkers_boarding_tram(tram_state: Dictionary) -> bool:
	for ag: Dictionary in _active_walkers:
		if str(ag.get("mode", "")) == "board_enter" and ag.get("tram_ref") == tram_state:
			return true
	return false


func seed_initial_passengers(graph: NetworkGraph, count: int = 20) -> void:
	for _i in range(count):
		_spawn_one_random_passenger(graph, true)


func step_simulation(dt: float, graph: NetworkGraph, focus_pos: Vector3 = Vector3(1e9, 0.0, 0.0)) -> void:
	_idle_time += dt
	if not graph.lines.is_empty() and not _station_views.is_empty():
		var rate: float = SPAWN_RATES[clampi(spawn_level, 1, 5)]
		var scale := clampf(float(_station_views.size()) / 5.0, 0.65, 3.0)
		_spawn_accum += dt * rate * scale
		while _spawn_accum >= 1.0:
			_spawn_accum -= 1.0
			_spawn_one_random_passenger(graph, false)

	_update_walkers(dt)
	_update_waiting_visibility_and_idle(focus_pos)


# Called by TransitSim when a tram has open doors at `station_id`.
# Handles alighting passengers AND visible multi-waypoint boarding through the open tram doors!
# At turnback terminals:
#   Phase 1 (before cab change): allow_alight=true, allow_board=false, force_alight_all=true  (只下不上，全员清客)
#   Phase 2 (after cab change):  allow_alight=false, allow_board=true, force_alight_all=false (只上车)
func exchange_passengers_at_station(
	tram_state: Dictionary,
	station_id: int,
	upcoming_sids: Array[int],
	dt: float,
	allow_alight: bool = true,
	allow_board: bool = true,
	force_alight_all: bool = false
) -> void:
	if not _station_views.has(station_id):
		return
	var sview: Dictionary = _station_views[station_id]
	var plat_view := _platform_view_for(tram_state, sview)
	var portals := _get_platform_facing_portals(tram_state, plat_view)
	if portals.is_empty():
		return

	# ~7.5 passengers/sec normally (~11.0/sec during terminal full-train evacuation so packed monorails clear briskly)
	var n_open := maxi(1, portals.size())
	var n_total := maxi(n_open, int(tram_state.get("total_doorways", n_open)))
	var base_rate := 11.0 if force_alight_all else 7.5
	var ai_st := int(tram_state.get("ai_style", 1))
	if ai_st == 0:
		base_rate *= 0.85
	elif ai_st == 2:
		base_rate *= 1.35
	var xfer_rate := base_rate * float(n_open) / float(n_total)
	tram_state["pax_xfer_accum"] = float(tram_state.get("pax_xfer_accum", 0.0)) + dt * xfer_rate
	while float(tram_state["pax_xfer_accum"]) >= 1.0:
		var did_work := false
		var onboard_list: Array = tram_state["pax_dests"]
		var lid_t := int(tram_state.get("line_id", 0))
		var alight_idx := -1
		if allow_alight:
			alight_idx = onboard_list.find(station_id)
			if alight_idx < 0 and (force_alight_all or upcoming_sids.is_empty()) and not onboard_list.is_empty():
				alight_idx = 0

		if alight_idx >= 0:
			var alighted_sid := int(onboard_list[alight_idx])
			onboard_list.remove_at(alight_idx)
			station_alighted[station_id] = int(station_alighted.get(station_id, 0)) + 1
			tram_state["st_alighted"] = int(tram_state.get("st_alighted", 0)) + 1
			var tinfo: Dictionary = tram_state["tram_info"]
			TramBuilder.update_onboard_passengers(tinfo, onboard_list.size(), int(tram_state["capacity"]))
			var p_info: Dictionary = portals[_rng.randi() % portals.size()]
			# Check if this alighting passenger is performing a Local <-> Express timed transfer (缓急接续换乘)!
			var xmap: Dictionary = tram_state.get("pax_xfer_legs", {})
			var xfer_arr: Array = xmap.get(station_id, [])
			if alighted_sid == station_id and not xfer_arr.is_empty():
				var xfer_info: Dictionary = xfer_arr.pop_front()
				total_transfers += 1
				_spawn_transfer_walker(p_info, plat_view, station_id, xfer_info)
			else:
				total_delivered += 1
				line_delivered[lid_t] = int(line_delivered.get(lid_t, 0)) + 1
				_spawn_alighting_walker(p_info, plat_view)
			did_work = true
		elif allow_board:
			var cap: int = int(tram_state["capacity"])
			var pending_n: int = int(tram_state.get("pending_boarders", 0))
			if onboard_list.size() + pending_n < cap and station_queues.has(station_id):
				var q: Array = station_queues[station_id]
				if not q.is_empty():
					var found_q := -1
					var fallback_q := -1
					for qi in range(q.size()):
						var cand_item: Dictionary = q[qi]
						if not _is_boardable(cand_item) or not _item_on_platform_view(cand_item, sview, plat_view):
							continue # Still walking up from the street or standing on the opposite island platform
						if _item_matches_tram(cand_item, tram_state, upcoming_sids):
							found_q = qi
							break
						# Fallback only for stale non-transfer, non-express-waiting passengers (e.g. after line edits)
						if fallback_q < 0 and not bool(cand_item.get("is_transfer", false)) and not bool(cand_item.get("want_express", false)) and (cand_item.get("xfer_legs", []) as Array).is_empty():
							if _idle_time - float(cand_item.get("t0", _idle_time)) > 24.0:
								fallback_q = qi
					if found_q < 0 and fallback_q >= 0 and not upcoming_sids.is_empty():
						found_q = fallback_q
						q[found_q]["dest_sid"] = upcoming_sids[_rng.randi() % upcoming_sids.size()]

					if found_q >= 0:
						var item: Dictionary = q[found_q]
						q.remove_at(found_q)
						var dest_final := int(item["dest_sid"])
						var direct_final := _item_final_dest(item)
						# If this tram (e.g. a manually-stopped express) reaches the passenger's final destination directly,
						# skip their planned intermediate transfer legs and take them straight there!
						if direct_final >= 0 and direct_final != station_id and not upcoming_sids.is_empty() and upcoming_sids.has(direct_final):
							dest_final = direct_final
							item["dest_sid"] = direct_final
							item["xfer_legs"] = []
						elif dest_final == station_id and not upcoming_sids.is_empty():
							dest_final = upcoming_sids[_rng.randi() % upcoming_sids.size()]
						tram_state["pending_boarders"] = pending_n + 1
						total_boarded += 1
						station_boarded[station_id] = int(station_boarded.get(station_id, 0)) + 1
						station_wait_sum[station_id] = float(station_wait_sum.get(station_id, 0.0)) + maxf(0.0, _idle_time - float(item.get("t0", _idle_time)))
						station_wait_n[station_id] = int(station_wait_n.get(station_id, 0)) + 1
						line_boarded[lid_t] = int(line_boarded.get(lid_t, 0)) + 1
						tram_state["st_boarded"] = int(tram_state.get("st_boarded", 0)) + 1
						# Pick the nearest OPEN platform-facing doorway to this passenger so they never cut across the tram!
						var p_target: Dictionary = portals[0]
						var ag_chk: Dictionary = item.get("agent", {})
						if not ag_chk.is_empty() and is_instance_valid(ag_chk.get("node")):
							var cur_p3 := (ag_chk["node"] as Node3D).global_position
							var best_pd := 1e18
							for cand_p: Dictionary in portals:
								var d2 := cur_p3.distance_squared_to(cand_p["outer_pos"] as Vector3)
								if d2 < best_pd:
									best_pd = d2
									p_target = cand_p
						else:
							p_target = portals[_rng.randi() % portals.size()]
						_start_boarding_walker(item, p_target, plat_view, tram_state, dest_final, station_id)
						_repack_waiting_queue(station_id)
						_refresh_station_label(station_id)
						did_work = true

		if did_work:
			tram_state["pax_xfer_accum"] = float(tram_state["pax_xfer_accum"]) - 1.0
		else:
			tram_state["pax_xfer_accum"] = 0.0
			break


func _spawn_one_random_passenger(graph: NetworkGraph, instant_place: bool) -> void:
	_ensure_transfer_graph(graph)
	if _all_served_sids.size() < 2:
		return

	var orig_sid := -1
	var dest_sid := -1
	var legs: Array = []

	# 55% network-wide OD (naturally generates Express <-> Local 缓急接续换乘 & cross-line transfers);
	# 45% same-line OD (still checks if Express-assisted transfer beats staying on Local!)
	if _rng.randf() < 0.55:
		for _try in range(4):
			var o_c: int = _all_served_sids[_rng.randi() % _all_served_sids.size()]
			var d_c: int = _all_served_sids[_rng.randi() % _all_served_sids.size()]
			if o_c == d_c:
				continue
			var planned := _plan_passenger_legs(graph, o_c, d_c)
			if not planned.is_empty():
				orig_sid = o_c
				dest_sid = d_c
				legs = planned
				break

	if legs.is_empty():
		var line_ids := graph.lines.keys()
		if line_ids.is_empty():
			return
		var lid_r: int = int(line_ids[_rng.randi() % line_ids.size()])
		var ln: Dictionary = graph.lines[lid_r]
		var sids: Array = ln["station_ids"]
		var unique_sids: Array[int] = []
		for raw_s in sids:
			var s_int := int(raw_s)
			if not unique_sids.has(s_int) and _station_views.has(s_int):
				unique_sids.append(s_int)
		if unique_sids.size() < 2:
			return
		orig_sid = unique_sids[_rng.randi() % unique_sids.size()]
		dest_sid = unique_sids[_rng.randi() % unique_sids.size()]
		if dest_sid == orig_sid:
			dest_sid = unique_sids[(unique_sids.find(orig_sid) + 1) % unique_sids.size()]
		var planned2 := _plan_passenger_legs(graph, orig_sid, dest_sid)
		# 85% of riders take the faster Express-transfer itinerary when it beats staying on Local
		if not planned2.is_empty() and (planned2.size() == 1 or _rng.randf() < 0.85):
			legs = planned2
		else:
			legs = [{
				"line_id": lid_r,
				"from": orig_sid,
				"to": dest_sid,
				"next_hop": dest_sid,
				"express": bool(ln.get("express", false)),
			}]

	var first_leg: Dictionary = legs[0]
	var leg_dest := int(first_leg["to"])
	var leg_lid := int(first_leg["line_id"])
	var want_exp := bool(first_leg.get("express", false))
	var rem_legs: Array = legs.slice(1) if legs.size() > 1 else []

	var q: Array = station_queues.get(orig_sid, [])
	var sview: Dictionary = _station_views[orig_sid]
	var pview := _pick_spawn_platform_view(graph, sview, orig_sid, int(first_leg.get("next_hop", leg_dest)))
	var p_slots: Array = pview.get("waiting_slots", [])
	# Count existing agents on this specific platform view so each twin island fills cleanly without cross-island overflow
	var on_pv := 0
	for it: Dictionary in q:
		if _item_on_platform_view(it, sview, pview):
			on_pv += 1
	var agent_dict: Dictionary = {}

	if on_pv < p_slots.size():
		var slot_pos: Vector3 = _pick_island_edge_slot(pview, on_pv, want_exp)
		var start_pos: Vector3 = slot_pos if instant_place else (pview["ramp_entry"] as Vector3)
		agent_dict = _create_3d_person(start_pos)
		agent_dict["station_id"] = orig_sid
		agent_dict["plat_view"] = pview
		agent_dict["target"] = slot_pos
		agent_dict["face_pos"] = pview["pos"] as Vector3
		agent_dict["mode"] = "wait" if instant_place else "walk_to_slot"
		agent_dict["on_platform"] = instant_place
		if not instant_place and pview.has("platform_entry"):
			# Up the stairs / ramp of this exact platform first; never cross tracks from another island
			agent_dict["entry_pt"] = pview["platform_entry"]
		if not instant_place:
			_active_walkers.append(agent_dict)
		else:
			_orient_person_toward(agent_dict["node"] as Node3D, pview["pos"] as Vector3)

	var item_dict := {
		"dest_sid": leg_dest,
		"final_dest": dest_sid,
		"line_id": leg_lid,
		"pref_line_id": leg_lid,
		"want_express": want_exp,
		"xfer_legs": rem_legs,
		"is_transfer": false,
		"agent": agent_dict,
		"t0": _idle_time, # arrival at the station (simulation time) for waiting-time statistics
	}
	q.append(item_dict)
	station_queues[orig_sid] = q
	_refresh_station_label(orig_sid)


# Pick the matching directional island at a twin-island stop (right-hand traffic: +fwd -> twins[1], -fwd -> twins[0])
static func _pick_spawn_platform_view(graph: NetworkGraph, sview: Dictionary, orig_sid: int, next_sid: int) -> Dictionary:
	if not sview.has("twins"):
		return sview
	var twins: Array = sview["twins"]
	if twins.size() < 2 or not graph.stations.has(orig_sid) or not graph.stations.has(next_sid):
		return twins[1]
	var st_o: Dictionary = graph.stations[orig_sid]
	var st_n: Dictionary = graph.stations[next_sid]
	var st_fwd := (st_o["fwd"] as Vector3).normalized()
	var dir_v := (st_n["pos"] as Vector3) - (st_o["pos"] as Vector3)
	dir_v.y = 0.0
	if dir_v.length_squared() < 0.01:
		return twins[1]
	return twins[1] if dir_v.normalized().dot(st_fwd) >= 0.0 else twins[0]


# On a twin-island platform, express riders stand on the inner express edge and local riders on the outer local edge!
static func _pick_island_edge_slot(pview: Dictionary, rank: int, want_express: bool) -> Vector3:
	var p_slots: Array = pview.get("waiting_slots", [])
	if p_slots.is_empty():
		return pview.get("pos", Vector3.ZERO) as Vector3
	var n := p_slots.size()
	if int(pview.get("side", 1)) != 0 or n < 4:
		return p_slots[rank % n] as Vector3
	var half := n / 2 # row 0 = -X edge, row 1 = +X edge
	var isl_s := float(pview.get("island_sign", 1.0))
	# For isl_s = +1 (right twin): express is at -X (row 0), local is at +X (row 1).
	# For isl_s = -1 (left twin): express is at +X (row 1), local is at -X (row 0).
	var row := (0 if isl_s > 0.0 else 1) if want_express else (1 if isl_s > 0.0 else 0)
	return p_slots[row * half + (rank % half)] as Vector3


func _start_boarding_walker(
	item: Dictionary,
	portal: Dictionary,
	sview: Dictionary,
	tram_state: Dictionary,
	dest_sid: int,
	station_id: int = -1
) -> void:
	var ag: Dictionary = item.get("agent", {})
	if ag.is_empty() or not is_instance_valid(ag.get("node")):
		var slots: Array = sview["waiting_slots"]
		var start_p: Vector3 = slots[0] if not slots.is_empty() else (sview["board_edge"] as Vector3)
		ag = _create_3d_person(start_p)
		ag["on_platform"] = true
		ag["plat_view"] = sview
		item["agent"] = ag
	ag["plat_view"] = sview
	ag["board_item"] = item
	ag["board_sid"] = station_id

	var outer_p: Vector3 = portal["outer_pos"]
	var inner_p: Vector3 = portal["inner_pos"]
	var aisle_p: Vector3 = portal["aisle_pos"]
	var out_dir: Vector3 = portal.get("out_dir", (outer_p - inner_p).normalized())
	out_dir.y = 0.0
	if out_dir.length_squared() < 0.01:
		out_dir = Vector3.RIGHT
	else:
		out_dir = out_dir.normalized()

	# L-shaped platform approach: walk along the platform outside the tram to a standoff point right in front of the open door,
	# then step straight perpendicular through the open doorway -> never cutting through the cab or side wall!
	var plat_standoff := outer_p + out_dir * 0.92
	plat_standoff.y = outer_p.y
	var door_thresh := outer_p + out_dir * 0.12
	var wps_b: Array = [plat_standoff, door_thresh, inner_p, aisle_p]
	if is_instance_valid(ag.get("node")):
		var cur_p := (ag["node"] as Node3D).global_position
		var lat_now := (cur_p - outer_p).dot(out_dir)
		var along_dist := ((cur_p - outer_p) - out_dir * lat_now).length()
		if along_dist > 1.2 and lat_now < 0.85:
			var safe_start := cur_p + out_dir * (0.92 - lat_now)
			safe_start.y = outer_p.y
			wps_b.push_front(safe_start)

	ag["waypoints"] = wps_b
	ag["target"] = wps_b[0]
	ag["mode"] = "board_enter"
	ag["speed"] = 2.25 + _rng.randf() * 0.35
	ag["tram_ref"] = tram_state
	ag["dest_sid"] = dest_sid
	ag["xfer_legs"] = (item.get("xfer_legs", []) as Array).duplicate(true)
	ag["final_dest"] = int(item.get("final_dest", dest_sid))
	ag["t0"] = float(item.get("t0", _idle_time))
	ag["portal_ref"] = portal
	if not _active_walkers.has(ag):
		_active_walkers.append(ag)


# Alighting passenger transferring between Express <-> Local (缓急接续换乘): steps onto the SAME platform
# (never crossing tracks!) and joins the waiting queue on the connecting edge of that platform!
func _spawn_transfer_walker(portal: Dictionary, sview: Dictionary, station_id: int, xfer_info: Dictionary) -> void:
	var rem_legs: Array = xfer_info.get("legs", [])
	if rem_legs.is_empty():
		_spawn_alighting_walker(portal, sview)
		return
	var next_leg: Dictionary = rem_legs[0]
	var inner_p: Vector3 = portal["inner_pos"]
	var outer_p: Vector3 = portal["outer_pos"]
	var out_dir: Vector3 = portal.get("out_dir", (outer_p - inner_p).normalized())
	out_dir.y = 0.0
	out_dir = out_dir.normalized() if out_dir.length_squared() > 0.01 else Vector3.RIGHT
	var plat_standoff := outer_p + out_dir * 0.95
	plat_standoff.y = outer_p.y
	var ag := _create_3d_person(inner_p)
	var want_exp := bool(next_leg.get("express", false))
	var q: Array = station_queues.get(station_id, [])
	var slot_pos := _pick_island_edge_slot(sview, q.size(), want_exp)
	ag["station_id"] = station_id
	ag["plat_view"] = sview
	ag["face_pos"] = sview.get("pos", slot_pos) as Vector3
	ag["waypoints"] = [outer_p, plat_standoff]
	ag["target"] = outer_p
	ag["xfer_slot"] = slot_pos
	ag["xfer_item"] = {
		"dest_sid": int(next_leg["to"]),
		"final_dest": int(xfer_info.get("final_dest", int(next_leg["to"]))),
		"line_id": int(next_leg["line_id"]),
		"pref_line_id": int(next_leg["line_id"]),
		"want_express": want_exp,
		"xfer_legs": rem_legs.slice(1) if rem_legs.size() > 1 else [],
		"is_transfer": true,
		"agent": ag,
		"t0": float(xfer_info.get("t0", _idle_time)),
	}
	ag["mode"] = "transfer_walk"
	ag["on_platform"] = false
	ag["speed"] = 2.10 + _rng.randf() * 0.25
	_active_walkers.append(ag)


func _spawn_alighting_walker(portal: Dictionary, sview: Dictionary) -> void:
	var inner_p: Vector3 = portal["inner_pos"]
	var outer_p: Vector3 = portal["outer_pos"]
	var out_dir: Vector3 = portal.get("out_dir", (outer_p - inner_p).normalized())
	out_dir.y = 0.0
	out_dir = out_dir.normalized() if out_dir.length_squared() > 0.01 else Vector3.RIGHT
	var plat_standoff := outer_p + out_dir * 0.95
	plat_standoff.y = outer_p.y
	var ag := _create_3d_person(inner_p)
	var plat_entry: Vector3 = sview.get("platform_entry", sview["board_edge"]) as Vector3
	var exit_pt: Vector3 = sview["ramp_entry"] as Vector3
	ag["waypoints"] = [outer_p, plat_standoff, plat_entry, exit_pt]
	ag["target"] = outer_p
	ag["mode"] = "alight_exit"
	ag["speed"] = 1.95 + _rng.randf() * 0.25
	_active_walkers.append(ag)


func _repack_waiting_queue(station_id: int) -> void:
	if not _station_views.has(station_id):
		return
	var sview: Dictionary = _station_views[station_id]
	var q: Array = station_queues.get(station_id, [])
	if sview.has("twins"):
		var twins: Array = sview["twins"]
		var tw_counts: Array[int] = [0, 0]
		for i in range(q.size()):
			var item: Dictionary = q[i]
			var ag: Dictionary = item.get("agent", {})
			var tw_idx := i % 2
			if not ag.is_empty() and is_instance_valid(ag.get("node")):
				var pv: Dictionary = ag.get("plat_view", _sub_view_for_pos(sview, (ag["node"] as Node3D).global_position))
				tw_idx = 0 if pv.get("node") == (twins[0] as Dictionary).get("node") else 1
			var pview: Dictionary = twins[tw_idx]
			var p_slots: Array = pview.get("waiting_slots", [])
			var s_i := tw_counts[tw_idx]
			if s_i >= p_slots.size():
				continue
			tw_counts[tw_idx] = s_i + 1
			var target_slot: Vector3 = _pick_island_edge_slot(pview, s_i, bool(item.get("want_express", false)))
			if ag.is_empty() or not is_instance_valid(ag.get("node")):
				ag = _create_3d_person(target_slot)
				ag["on_platform"] = true
				ag["plat_view"] = pview
				item["agent"] = ag
			ag["plat_view"] = pview
			ag["target"] = target_slot
			ag["face_pos"] = pview["pos"] as Vector3
			ag["mode"] = "walk_to_slot"
			if not _active_walkers.has(ag):
				_active_walkers.append(ag)
		return
	var slots: Array = sview["waiting_slots"]
	for i in range(mini(q.size(), slots.size())):
		var item: Dictionary = q[i]
		var ag: Dictionary = item.get("agent", {})
		if ag.is_empty() or not is_instance_valid(ag.get("node")):
			ag = _create_3d_person(slots[i] as Vector3)
			ag["on_platform"] = true
			item["agent"] = ag
		ag["target"] = slots[i]
		ag["face_pos"] = sview["pos"] as Vector3
		ag["mode"] = "walk_to_slot"
		if not _active_walkers.has(ag):
			_active_walkers.append(ag)


func _update_walkers(dt: float) -> void:
	var idx := _active_walkers.size() - 1
	while idx >= 0:
		var ag: Dictionary = _active_walkers[idx]
		var node: Node3D = ag.get("node")
		if not is_instance_valid(node):
			_finish_boarding_if_needed(ag)
			_active_walkers.remove_at(idx)
			idx -= 1
			continue

		var mode := str(ag.get("mode", "wait"))
		# If tram starts moving away while a walker is still boarding, dynamically track its live door anchor or complete boarding!
		if mode == "board_enter":
			var tr_ref: Dictionary = ag.get("tram_ref", {})
			if tr_ref.is_empty() or float(tr_ref.get("door_ratio", 0.0)) < 0.12 or not bool(tr_ref.get("doors_target_open", true)):
				# Doors closing: whoever is already in the doorway gets on, everyone else stays on the platform
				var wps_c: Array = ag.get("waypoints", [])
				if tr_ref.is_empty() or wps_c.size() <= 2 or not _return_boarder_to_platform(ag):
					_finish_boarding_if_needed(ag)
					node.queue_free()
				_active_walkers.remove_at(idx)
				idx -= 1
				continue
			var pref: Dictionary = ag.get("portal_ref", {})
			var wps_live: Array = ag.get("waypoints", [])
			if pref.has("inner_node") and is_instance_valid(pref["inner_node"]) and not wps_live.is_empty():
				if wps_live.size() == 2:
					wps_live[0] = (pref["inner_node"] as Node3D).global_position
					wps_live[1] = (pref["aisle_node"] as Node3D).global_position
					ag["target"] = wps_live[0]
				elif wps_live.size() == 1:
					wps_live[0] = (pref["aisle_node"] as Node3D).global_position
					ag["target"] = wps_live[0]

		var via_entry := mode == "walk_to_slot" and ag.has("entry_pt")
		var target: Vector3 = ag["entry_pt"] if via_entry else ag["target"]
		var spd := float(ag.get("speed", 1.85))
		var cur := node.global_position
		var diff := target - cur
		var dist := diff.length()

		if dist <= 0.14 and via_entry:
			# Reached the platform deck: walk on to its waiting spot, already able to board
			node.global_position = target
			ag.erase("entry_pt")
			ag["on_platform"] = true
			_refresh_station_label(int(ag.get("station_id", -1)))
		elif dist <= 0.14:
			node.global_position = target
			if mode == "board_enter":
				var wps: Array = ag.get("waypoints", [])
				if wps.size() > 1:
					wps.remove_at(0)
					ag["target"] = wps[0]
					# Once walker steps through doorway threshold (entering inner_pos -> aisle_pos), count onboard!
					if wps.size() == 1:
						_finish_boarding_if_needed(ag)
				else:
					_finish_boarding_if_needed(ag)
					node.queue_free()
					_active_walkers.remove_at(idx)
			elif mode == "alight_exit":
				var wps_a: Array = ag.get("waypoints", [])
				if wps_a.size() > 1:
					wps_a.remove_at(0)
					ag["target"] = wps_a[0]
				else:
					node.queue_free()
					_active_walkers.remove_at(idx)
			elif mode == "transfer_walk":
				var wps_x: Array = ag.get("waypoints", [])
				if wps_x.size() > 1:
					wps_x.remove_at(0)
					ag["target"] = wps_x[0]
				else:
					# Stepped cleanly onto the island platform: immediately join the connecting queue (boardable right away!)
					var x_sid := int(ag.get("station_id", -1))
					var x_item: Dictionary = ag.get("xfer_item", {})
					ag.erase("xfer_item")
					ag["waypoints"] = []
					ag["on_platform"] = true
					ag["mode"] = "walk_to_slot"
					ag["target"] = ag.get("xfer_slot", cur) as Vector3
					if x_sid >= 0 and not x_item.is_empty():
						var qx: Array = station_queues.get(x_sid, [])
						qx.append(x_item)
						station_queues[x_sid] = qx
						_refresh_station_label(x_sid)
			else:
				(ag["leg_l"] as Node3D).rotation.x = 0.0
				(ag["leg_r"] as Node3D).rotation.x = 0.0
				(ag["arm_l"] as Node3D).rotation.x = 0.0
				(ag["leg_l"] as Node3D).rotation.x = 0.0
				(ag["leg_r"] as Node3D).rotation.x = 0.0
				if ag.has("knee_l"):
					(ag["knee_l"] as Node3D).rotation.x = 0.0
					(ag["knee_r"] as Node3D).rotation.x = 0.0
				(ag["arm_l"] as Node3D).rotation.x = 0.0
				(ag["arm_r"] as Node3D).rotation.x = 0.0
				if ag.has("elbow_l"):
					(ag["elbow_l"] as Node3D).rotation.x = deg_to_rad(-8.0)
					(ag["elbow_r"] as Node3D).rotation.x = deg_to_rad(-8.0)
				(ag["torso"] as Node3D).position.y = 1.12
				(ag["torso"] as Node3D).rotation = Vector3.ZERO
				_orient_person_toward(node, ag.get("face_pos", cur + Vector3.FORWARD) as Vector3)
				ag["mode"] = "wait"
				ag["on_platform"] = true
				_active_walkers.remove_at(idx)
		else:
			var step := minf(dist, spd * dt)
			node.global_position = cur + (diff / dist) * step
			_orient_person_smooth(node, target, dt)
			var phase := float(ag.get("phase", 0.0)) + dt * spd * 4.8
			ag["phase"] = phase
			var s_ph := sin(phase)
			var c_ph := cos(phase)
			# Natural human stride: hip swing + trailing knee flexion + subtle elbow bend + torso counter-twist
			(ag["leg_l"] as Node3D).rotation.x = s_ph * deg_to_rad(23.0)
			(ag["leg_r"] as Node3D).rotation.x = -s_ph * deg_to_rad(23.0)
			if ag.has("knee_l"):
				(ag["knee_l"] as Node3D).rotation.x = maxf(0.0, -c_ph) * deg_to_rad(32.0)
				(ag["knee_r"] as Node3D).rotation.x = maxf(0.0, c_ph) * deg_to_rad(32.0)
			(ag["arm_l"] as Node3D).rotation.x = -s_ph * deg_to_rad(15.0)
			(ag["arm_r"] as Node3D).rotation.x = s_ph * deg_to_rad(15.0)
			if ag.has("elbow_l"):
				(ag["elbow_l"] as Node3D).rotation.x = deg_to_rad(-10.0 - maxf(0.0, -s_ph) * 14.0)
				(ag["elbow_r"] as Node3D).rotation.x = deg_to_rad(-10.0 - maxf(0.0, s_ph) * 14.0)
			var torso_n := ag["torso"] as Node3D
			torso_n.position.y = 1.12 + absf(s_ph) * 0.022
			torso_n.rotation.y = s_ph * deg_to_rad(3.8)
			torso_n.rotation.z = c_ph * deg_to_rad(1.2)

		idx -= 1


# A boarder who had not reached the door when it started closing goes back to the head of the platform queue
func _return_boarder_to_platform(ag: Dictionary) -> bool:
	var sid := int(ag.get("board_sid", -1))
	var item: Dictionary = ag.get("board_item", {})
	if sid < 0 or item.is_empty() or not station_queues.has(sid) or bool(ag.get("board_committed", false)):
		return false
	ag["board_committed"] = true # never counted on board
	var tr_ref: Dictionary = ag.get("tram_ref", {})
	tr_ref["pending_boarders"] = maxi(0, int(tr_ref.get("pending_boarders", 1)) - 1)
	var new_ag := ag.duplicate()
	new_ag.erase("board_committed")
	new_ag.erase("tram_ref")
	new_ag.erase("portal_ref")
	new_ag.erase("board_item")
	new_ag["waypoints"] = []
	new_ag["on_platform"] = true
	item["agent"] = new_ag
	item["dest_sid"] = int(ag.get("dest_sid", item.get("dest_sid", -1)))
	var q: Array = station_queues[sid]
	q.push_front(item)
	_repack_waiting_queue(sid) # walks them back to a waiting slot
	_refresh_station_label(sid)
	return true


func _finish_boarding_if_needed(ag: Dictionary) -> void:
	if bool(ag.get("board_committed", false)):
		return
	if str(ag.get("mode", "")) != "board_enter":
		return
	ag["board_committed"] = true
	var tr_ref: Dictionary = ag.get("tram_ref", {})
	if tr_ref.is_empty():
		return
	tr_ref["pending_boarders"] = maxi(0, int(tr_ref.get("pending_boarders", 1)) - 1)
	var onboard_list: Array = tr_ref.get("pax_dests", [])
	var d_sid := int(ag.get("dest_sid", -1))
	onboard_list.append(d_sid)
	var xlegs: Array = ag.get("xfer_legs", [])
	if not xlegs.is_empty() and d_sid >= 0:
		var xmap: Dictionary = tr_ref.get("pax_xfer_legs", {})
		if not xmap.has(d_sid):
			xmap[d_sid] = []
		(xmap[d_sid] as Array).append({
			"legs": xlegs.duplicate(true),
			"final_dest": int(ag.get("final_dest", d_sid)),
			"t0": float(ag.get("t0", _idle_time)),
		})
		tr_ref["pax_xfer_legs"] = xmap
	var tinfo: Dictionary = tr_ref.get("tram_info", {})
	if not tinfo.is_empty():
		TramBuilder.update_onboard_passengers(tinfo, onboard_list.size(), int(tr_ref.get("capacity", 120)))


func _update_waiting_visibility_and_idle(focus_pos: Vector3) -> void:
	var use_cull := focus_pos.x < 1e8
	var max_r2 := 155.0 * 155.0
	for sid: int in station_queues.keys():
		var sv: Dictionary = _station_views.get(sid, {})
		var show_st := true
		if use_cull and not sv.is_empty():
			var sp: Vector3 = sv.get("pos", Vector3.ZERO)
			var dx := sp.x - focus_pos.x
			var dz := sp.z - focus_pos.z
			show_st = (dx * dx + dz * dz) <= max_r2
		var q: Array = station_queues[sid]
		for i in range(q.size()):
			var ag: Dictionary = q[i].get("agent", {})
			if ag.is_empty():
				continue
			var n: Node3D = ag.get("node")
			if is_instance_valid(n):
				var want_vis := show_st or str(ag.get("mode", "")) == "board_enter"
				if n.visible != want_vis:
					n.visible = want_vis
			if not show_st or i >= 18 or str(ag.get("mode", "")) != "wait":
				continue
			var head: Node3D = ag.get("head")
			var torso: Node3D = ag.get("torso")
			var ph := float(ag.get("phase", 0.0))
			if is_instance_valid(head):
				var glance := sin(_idle_time * 0.42 + ph) * 0.14 + sin(_idle_time * 0.17 + ph * 2.1) * 0.10
				head.rotation.y = glance
			if is_instance_valid(torso):
				torso.rotation.z = sin(_idle_time * 0.75 + ph) * 0.012
				torso.position.y = 1.12 + sin(_idle_time * 1.6 + ph) * 0.004


func _create_3d_person(world_pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.global_position = world_pos
	var h_scale := 0.93 + _rng.randf() * 0.12
	var w_scale := h_scale * (0.94 + _rng.randf() * 0.12)
	root.scale = Vector3(w_scale, h_scale, w_scale)

	var arch := _rng.randi() % 4
	var hair_style := _rng.randi() % 4
	var coat_mat: Material = _coat_mats[_rng.randi() % _coat_mats.size()]
	var pants_mat: Material = _pants_mats[_rng.randi() % _pants_mats.size()]
	var skin_idx := _rng.randi() % _skin_mats.size()
	var skin_mat: Material = _skin_mats[skin_idx]
	var hair_mat: Material = _hair_mats[_rng.randi() % _hair_mats.size()]

	var thigh_m := HumanMeshGen.get_thigh_mesh()
	var shin_m := HumanMeshGen.get_shin_mesh()
	var uarm_m := HumanMeshGen.get_upper_arm_mesh()
	var farm_m := HumanMeshGen.get_forearm_mesh()
	var shoe_m := HumanMeshGen.get_shoe_mesh()
	var torso_m := HumanMeshGen.get_torso_mesh(arch)
	var wears_skirt := (arch == 2 or _rng.randf() < 0.30)
	var lower_leg_mat: Material = skin_mat if (wears_skirt and _rng.randf() < 0.65) else pants_mat

	# Articulated Left & Right Legs (Sculpted Thigh + Knee Hinge + Sculpted Shin + Sculpted Shoe)
	var leg_l := Node3D.new()
	leg_l.position = Vector3(-0.088, 0.84, 0.0)
	root.add_child(leg_l)
	_inst(leg_l, thigh_m, Vector3(0.0, -0.20, 0.0), lower_leg_mat if wears_skirt else pants_mat)
	var knee_l := Node3D.new()
	knee_l.position = Vector3(0.0, -0.40, 0.0)
	leg_l.add_child(knee_l)
	_inst(knee_l, shin_m, Vector3(0.0, -0.20, 0.0), lower_leg_mat)
	var shoe_mat: Material = _sneaker_mat if _rng.randf() < 0.35 else (_shoe_mat if _rng.randf() < 0.6 else _acc_mats[_rng.randi() % _acc_mats.size()])
	_inst(knee_l, shoe_m, Vector3(0.0, -0.438, -0.02), shoe_mat)
	_inst(knee_l, shoe_m, Vector3(0.0, -0.446, -0.02), _shoe_sole_mat).scale = Vector3(1.07, 0.32, 1.05)

	var leg_r := Node3D.new()
	leg_r.position = Vector3(0.088, 0.84, 0.0)
	root.add_child(leg_r)
	_inst(leg_r, thigh_m, Vector3(0.0, -0.20, 0.0), lower_leg_mat if wears_skirt else pants_mat)
	var knee_r := Node3D.new()
	knee_r.position = Vector3(0.0, -0.40, 0.0)
	leg_r.add_child(knee_r)
	_inst(knee_r, shin_m, Vector3(0.0, -0.20, 0.0), lower_leg_mat)
	_inst(knee_r, shoe_m, Vector3(0.0, -0.438, -0.02), shoe_mat)
	_inst(knee_r, shoe_m, Vector3(0.0, -0.446, -0.02), _shoe_sole_mat).scale = Vector3(1.07, 0.32, 1.05)

	# Sculpted Archetype Torso + Optional A-Line Skirt (attached to root pelvis to prevent leg clipping!)
	var torso := Node3D.new()
	torso.position = Vector3(0.0, 1.12, 0.0)
	root.add_child(torso)
	_inst(torso, torso_m, Vector3.ZERO, coat_mat, true)
	if wears_skirt:
		var skirt_mat: Material = coat_mat if arch == 2 else _coat_mats[_rng.randi() % _coat_mats.size()]
		_inst(root, HumanMeshGen.get_skirt_mesh(_rng.randf() < 0.45), Vector3(0.0, 0.90, 0.0), skirt_mat)
	elif arch != 2:
		_inst(torso, HumanMeshGen.get_belt_mesh(arch), Vector3.ZERO, _belt_mat)

	# Surface-conforming tailored collar, inner shirt V-neck & subtle metallic zipper (zero floating bars!)
	_inst(torso, HumanMeshGen.get_collar_mesh(arch), Vector3.ZERO, coat_mat)
	_inst(torso, HumanMeshGen.get_shirt_vneck_mesh(arch), Vector3.ZERO, _shirt_mat)
	if arch == 1 or _rng.randf() < 0.45:
		_inst(torso, HumanMeshGen.get_zipper_mesh(arch), Vector3.ZERO, _zipper_mat)

	var bag_mat: Material = _acc_mats[_rng.randi() % _acc_mats.size()]
	var bag_roll := _rng.randf()
	if arch == 3 or bag_roll < 0.32:
		# High-precision contoured commuter backpack + metallic zipper trims + ergonomic S-curved shoulder straps
		_inst(torso, HumanMeshGen.get_backpack_body_mesh(), Vector3.ZERO, bag_mat)
		_inst(torso, HumanMeshGen.get_backpack_trim_mesh(), Vector3.ZERO, _zipper_mat)
		_inst(torso, HumanMeshGen.get_backpack_straps_mesh(arch), Vector3.ZERO, _strap_mat)
	elif bag_roll < 0.54:
		# Sculpted leather/canvas commuter messenger bag + body-hugging curved crossbody strap
		var hip_s := -1.0 if _rng.randf() < 0.5 else 1.0
		_inst(torso, HumanMeshGen.get_messenger_bag_mesh(), Vector3(hip_s * 0.205, -0.29, 0.015), bag_mat)
		_inst(torso, HumanMeshGen.get_crossbody_strap_mesh(arch, hip_s), Vector3.ZERO, _strap_mat)

	# Articulated Left & Right Arms (Rounded Deltoid Shoulder Cap + Elbow Hinge + Forearm + Mitten-Topology Hand!)
	var hand_l_m := HumanMeshGen.get_hand_mesh(-1.0)
	var hand_r_m := HumanMeshGen.get_hand_mesh(1.0)
	var sh_x := 0.166 if arch == 2 else 0.182
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-sh_x, 0.175, 0.0)
	arm_l.rotation.z = deg_to_rad(-3.5)
	torso.add_child(arm_l)
	_inst(arm_l, uarm_m, Vector3(0.0, -0.125, 0.0), coat_mat)
	var elbow_l := Node3D.new()
	elbow_l.position = Vector3(0.0, -0.255, 0.0)
	elbow_l.rotation.x = deg_to_rad(-9.0)
	arm_l.add_child(elbow_l)
	_inst(elbow_l, farm_m, Vector3(0.0, -0.13, 0.0), coat_mat)
	_inst(elbow_l, hand_l_m, Vector3(0.0, -0.275, 0.0), skin_mat)

	var arm_r := Node3D.new()
	arm_r.position = Vector3(sh_x, 0.175, 0.0)
	arm_r.rotation.z = deg_to_rad(3.5)
	torso.add_child(arm_r)
	_inst(arm_r, uarm_m, Vector3(0.0, -0.125, 0.0), coat_mat)
	var elbow_r := Node3D.new()
	elbow_r.position = Vector3(0.0, -0.255, 0.0)
	elbow_r.rotation.x = deg_to_rad(-9.0)
	arm_r.add_child(elbow_r)
	_inst(elbow_r, farm_m, Vector3(0.0, -0.13, 0.0), coat_mat)
	_inst(elbow_r, hand_r_m, Vector3(0.0, -0.275, 0.0), skin_mat)

	# Sculpted Anatomical Neck + Layered Hair + Natural Non-Uncanny 3D Face + Optional Slim Glasses
	_inst(torso, HumanMeshGen.get_neck_mesh(), Vector3(0.0, 0.300, 0.0), skin_mat)
	var skin_pal_c: Array[Color] = [Color(0.87, 0.71, 0.60), Color(0.78, 0.60, 0.47), Color(0.91, 0.77, 0.67), Color(0.54, 0.38, 0.28)]
	var hair_pal_c: Array[Color] = [Color(0.11, 0.09, 0.08), Color(0.24, 0.15, 0.10), Color(0.38, 0.28, 0.16), Color(0.17, 0.16, 0.16)]
	var hair_c_idx := _rng.randi() % hair_pal_c.size()
	var head := HumanMeshGen.build_detailed_head(
		torso, skin_mat, _hair_mats[hair_c_idx], hair_style,
		skin_pal_c[skin_idx % skin_pal_c.size()], hair_pal_c[hair_c_idx],
		_rng.randf() < 0.25
	)
	head.position = Vector3(0.0, 0.415, -0.005)
	var acc_roll := _rng.randf()
	var hat_mat: Material = _acc_mats[_rng.randi() % _acc_mats.size()]
	if acc_roll < 0.11:
		# Sculpted baseball cap with curved visor
		_inst(head, HumanMeshGen.get_cap_mesh(), Vector3.ZERO, hat_mat)
	elif acc_roll < 0.20:
		# Sculpted knit beanie
		_inst(head, HumanMeshGen.get_beanie_mesh(), Vector3.ZERO, hat_mat)
	elif acc_roll < 0.28:
		# Smooth curved over-ear headphones (horseshoe band + oval earcups)
		_inst(head, HumanMeshGen.get_headphones_mesh(), Vector3.ZERO, _phone_mat)
	if _rng.randf() < 0.15:
		# Draped knit scarf conforming to neck & chest
		_inst(torso, HumanMeshGen.get_scarf_mesh(arch), Vector3.ZERO, hat_mat)
	if _rng.randf() < 0.24:
		# Looking at a phone: forearm raised, glowing screen in hand
		elbow_r.rotation.x = deg_to_rad(78.0)
		_box(elbow_r, Vector3(0.068, 0.142, 0.009), Vector3(-0.015, -0.30, -0.028), _phone_mat)
		_box(elbow_r, Vector3(0.060, 0.126, 0.004), Vector3(-0.015, -0.30, -0.034), _screen_mat)

	# Distant Platform Crowd LOD1 (~1,800 tris single mesh at 36m..165m; all LOD0 articulated sub-parts swap out cleanly at 40m!)
	var coat_tint: Color = (coat_mat as ShaderMaterial).get_shader_parameter("base_tint") if coat_mat is ShaderMaterial else Color(0.24, 0.30, 0.38)
	var pants_tint: Color = (pants_mat as ShaderMaterial).get_shader_parameter("base_tint") if pants_mat is ShaderMaterial else Color(0.22, 0.28, 0.38)
	var lod1_mi := MeshInstance3D.new()
	lod1_mi.name = "NpcLOD1"
	lod1_mi.mesh = HumanMeshGen.get_npc_lod1_mesh(arch, coat_tint, pants_tint, skin_pal_c[skin_idx % skin_pal_c.size()], hair_pal_c[hair_c_idx])
	lod1_mi.material_override = HumanMeshGen.get_npc_lod1_mat()
	lod1_mi.visibility_range_begin = 36.0
	lod1_mi.visibility_range_end = 165.0
	lod1_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lod1_mi)

	return {
		"node": root,
		"leg_l": leg_l,
		"leg_r": leg_r,
		"knee_l": knee_l,
		"knee_r": knee_r,
		"arm_l": arm_l,
		"arm_r": arm_r,
		"elbow_l": elbow_l,
		"elbow_r": elbow_r,
		"torso": torso,
		"head": head,
		"phase": _rng.randf() * TAU,
		"speed": 1.38 + _rng.randf() * 0.28,
	}


static func _inst(parent: Node3D, m: Mesh, pos: Vector3, mat: Material, cast_sh: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = 40.0
	if not cast_sh:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _orient_person_smooth(node: Node3D, look_world: Vector3, dt: float) -> void:
	var flat_target := Vector3(look_world.x, node.global_position.y, look_world.z)
	if flat_target.distance_to(node.global_position) > 0.05:
		var fwd := (flat_target - node.global_position).normalized()
		var target_yaw := atan2(-fwd.x, -fwd.z)
		node.rotation.y = lerp_angle(node.rotation.y, target_yaw, minf(1.0, dt * 8.5))


static func _orient_person_toward(node: Node3D, look_world: Vector3) -> void:
	var flat_target := Vector3(look_world.x, node.global_position.y, look_world.z)
	if flat_target.distance_to(node.global_position) > 0.05:
		var fwd := (flat_target - node.global_position).normalized()
		node.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), node.global_position)


# A four-track stop has twin islands: the train is served from the island beside its own track
static func _platform_view_for(tram_state: Dictionary, sview: Dictionary) -> Dictionary:
	if not sview.has("twins"):
		return sview
	var secs: Array = (tram_state.get("tram_info", {}) as Dictionary).get("sections", [])
	if secs.is_empty() or not is_instance_valid(secs[0]):
		return sview
	var tp := (secs[0] as Node3D).global_position
	var best: Dictionary = sview
	var best_d := 1e18
	for tw: Dictionary in sview["twins"]:
		var d := tp.distance_squared_to(tw.get("pos", Vector3.ZERO) as Vector3)
		if d < best_d:
			best_d = d
			best = tw
	return best


static func _get_platform_facing_portals(tram_state: Dictionary, sview: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tinfo: Dictionary = tram_state.get("tram_info", {})
	var portals: Array = tinfo.get("door_portals", [])
	if portals.is_empty():
		return out

	var st_pos: Vector3 = sview.get("pos", Vector3.ZERO)
	var st_fwd := (sview.get("fwd", Vector3.FORWARD) as Vector3).normalized()
	var st_right := st_fwd.cross(Vector3.UP).normalized()
	var st_side := int(sview.get("side", 1))
	var curve_spec: Dictionary = sview.get("curve_spec", {})
	var has_cspec := not curve_spec.is_empty() and curve_spec.has("geom")

	for p: Dictionary in portals:
		var outer_n: Node3D = p.get("outer")
		var inner_n: Node3D = p.get("inner")
		var aisle_n: Node3D = p.get("aisle")
		if not (is_instance_valid(outer_n) and is_instance_valid(inner_n) and is_instance_valid(aisle_n)):
			continue
		var op := outer_n.global_position
		var ip := inner_n.global_position
		var out_v := op - ip
		out_v.y = 0.0
		if out_v.length_squared() < 0.01:
			continue
		out_v = out_v.normalized()

		var loc_right := st_right
		var loc_ref := st_pos
		var along_p := (op - st_pos).dot(st_fwd)
		if has_cspec:
			var g_p: Dictionary = curve_spec["geom"]
			var c_p: Curve3D = g_p["curve"]
			var clen_p := float(g_p["clen"])
			var s_p := c_p.get_closest_offset(Vector3(op.x, 0.0, op.z))
			along_p = s_p - float(curve_spec["s_center"])
			var tf_p := TrackBuilder.sample_track_frame(c_p, s_p, clen_p, false)
			var loc_fwd := (-tf_p.basis.z).normalized()
			loc_right = loc_fwd.cross(Vector3.UP).normalized()
			if st_side == 0:
				var c_mode_p := str(curve_spec.get("mode", "double_island"))
				if c_mode_p == "quad_twin":
					var isl_s_p := float(curve_spec.get("side_sign", 1.0))
					var isl_lat_p := 0.5 * (TrackBuilder.geom_sep_at(g_p, s_p) + TrackBuilder.geom_lsep_at(g_p, s_p))
					loc_ref = tf_p.origin + loc_right * (isl_s_p * isl_lat_p)
				else:
					loc_ref = tf_p.origin

		# Compute pure lateral direction toward the raised platform (matching TramBuilder._is_door_allowed_by_platform!)
		var plat_dir := Vector3.ZERO
		if st_side != 0:
			plat_dir = loc_right * float(st_side)
		else:
			# Central Island Platform: loc_ref lies between both tracks; use lateral projection so longitudinal offset never fails!
			var lat_to_island := (loc_ref - ip).dot(loc_right)
			if absf(lat_to_island) < 0.05:
				continue
			plat_dir = loc_right * signf(lat_to_island)

		# Verify this doorway STRICTLY faces the platform side (never the opposite closed side!)
		if out_v.dot(plat_dir) <= 0.35:
			continue
		# Also ensure the doorway is within the raised platform longitudinal span!
		var plat_half_allow := float(sview.get("platform_len", 27.0)) * 0.5 - 0.45
		if absf(along_p) > plat_half_allow:
			continue
		out.append({
			"outer_pos": op,
			"inner_pos": ip,
			"aisle_pos": aisle_n.global_position,
			"out_dir": out_v,
			"outer_node": outer_n,
			"inner_node": inner_n,
			"aisle_node": aisle_n,
			"dist2": op.distance_squared_to(st_pos),
		})
	return out


func rebind_station_views(station_views: Dictionary) -> void:
	_station_views = station_views
	refresh_all_station_labels()


func refresh_all_station_labels() -> void:
	for sid_k in _station_views.keys():
		_refresh_station_label(int(sid_k))


func _refresh_station_label(station_id: int) -> void:
	if not _station_views.has(station_id):
		return
	var raw_lbl = _station_views[station_id].get("wait_label")
	if is_instance_valid(raw_lbl):
		var lbl := raw_lbl as Label3D
		var cnt: int = (station_queues.get(station_id, []) as Array).size()
		var on_plat := get_boardable_count(station_id)
		if cnt <= 0:
			lbl.text = L10n.t("暂无候车", "No passengers")
		elif on_plat < cnt:
			lbl.text = L10n.t("候车 %d 人（另 %d 人进站中）", "%d waiting (+%d arriving)") % [on_plat, cnt - on_plat]
		else:
			lbl.text = L10n.t("候车 %d 人", "%d waiting") % cnt


static var _box_cache: Dictionary = {}


static func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b: BoxMesh = _box_cache.get(sz)
	if b == null:
		b = BoxMesh.new()
		b.size = sz
		_box_cache[sz] = b
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = 120.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
