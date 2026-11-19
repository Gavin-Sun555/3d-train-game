class_name PassengerSim
extends Node3D

const SPAWN_RATES := [0.0, 0.35, 0.75, 1.45, 2.55, 4.50]
const SPAWN_LEVEL_NAMES := ["", "1档 稀少", "2档 较少", "3档 标准", "4档 繁忙", "5档 高峰"]

var spawn_level := 3 # 1..5
var total_delivered := 0
var total_boarded := 0
var station_boarded: Dictionary = {}  # station_id -> int
var station_alighted: Dictionary = {} # station_id -> int
var line_boarded: Dictionary = {}     # line_id -> int
var line_delivered: Dictionary = {}   # line_id -> int

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
	_shirt_mat.albedo_color = Color(0.86, 0.86, 0.84)
	_shirt_mat.roughness = 0.85

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
	station_alighted.clear()
	line_boarded.clear()
	line_delivered.clear()
	_active_walkers.clear()
	_station_views = station_views
	for sid: int in _station_views.keys():
		station_queues[sid] = []
		station_boarded[sid] = 0
		station_alighted[sid] = 0
		_refresh_station_label(sid)


func has_waiting_passengers(station_id: int) -> bool:
	return not (station_queues.get(station_id, []) as Array).is_empty()


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


func step_simulation(dt: float, graph: NetworkGraph) -> void:
	_idle_time += dt
	if not graph.lines.is_empty() and not _station_views.is_empty():
		var rate: float = SPAWN_RATES[clampi(spawn_level, 1, 5)]
		var scale := clampf(float(_station_views.size()) / 5.0, 0.65, 3.0)
		_spawn_accum += dt * rate * scale
		while _spawn_accum >= 1.0:
			_spawn_accum -= 1.0
			_spawn_one_random_passenger(graph, false)

	_update_walkers(dt)
	_update_waiting_idle()


# Called by TransitSim when a tram has open doors at `station_id`.
# Handles alighting passengers AND visible multi-waypoint boarding through the open tram doors!
func exchange_passengers_at_station(
	tram_state: Dictionary,
	station_id: int,
	upcoming_sids: Array[int],
	dt: float
) -> void:
	if not _station_views.has(station_id):
		return
	var sview: Dictionary = _station_views[station_id]
	var portals := _get_platform_facing_portals(tram_state, sview)
	if portals.is_empty():
		return

	# ~7.5 passengers/sec with every doorway on the platform side open; a badly placed stop that lines up
	# fewer doorways with the platform exchanges proportionally slower (one door ~ a third of the rate).
	var n_open := maxi(1, portals.size())
	var n_total := maxi(n_open, int(tram_state.get("total_doorways", n_open)))
	var xfer_rate := 7.5 * float(n_open) / float(n_total)
	tram_state["pax_xfer_accum"] = float(tram_state.get("pax_xfer_accum", 0.0)) + dt * xfer_rate
	while float(tram_state["pax_xfer_accum"]) >= 1.0:
		var did_work := false
		var onboard_list: Array = tram_state["pax_dests"]
		var lid_t := int(tram_state.get("line_id", 0))
		var alight_idx := onboard_list.find(station_id)
		if alight_idx < 0 and upcoming_sids.is_empty() and not onboard_list.is_empty():
			alight_idx = 0

		if alight_idx >= 0:
			onboard_list.remove_at(alight_idx)
			total_delivered += 1
			station_alighted[station_id] = int(station_alighted.get(station_id, 0)) + 1
			line_delivered[lid_t] = int(line_delivered.get(lid_t, 0)) + 1
			var tinfo: Dictionary = tram_state["tram_info"]
			TramBuilder.update_onboard_passengers(tinfo, onboard_list.size(), int(tram_state["capacity"]))
			var p_info: Dictionary = portals[_rng.randi() % portals.size()]
			_spawn_alighting_walker(p_info, sview)
			did_work = true
		else:
			var cap: int = int(tram_state["capacity"])
			var pending_n: int = int(tram_state.get("pending_boarders", 0))
			if onboard_list.size() + pending_n < cap and station_queues.has(station_id):
				var q: Array = station_queues[station_id]
				if not q.is_empty():
					var found_q := -1
					for qi in range(q.size()):
						var cand_dest := int(q[qi]["dest_sid"])
						if upcoming_sids.has(cand_dest) or upcoming_sids.is_empty():
							found_q = qi
							break
					# Ensure waiting passengers at this platform always board a stopping tram!
					if found_q < 0 and not upcoming_sids.is_empty():
						found_q = 0
						q[0]["dest_sid"] = upcoming_sids[_rng.randi() % upcoming_sids.size()]

					if found_q >= 0:
						var item: Dictionary = q[found_q]
						q.remove_at(found_q)
						var dest_final := int(item["dest_sid"])
						if dest_final == station_id and not upcoming_sids.is_empty():
							dest_final = upcoming_sids[_rng.randi() % upcoming_sids.size()]
						tram_state["pending_boarders"] = pending_n + 1
						total_boarded += 1
						station_boarded[station_id] = int(station_boarded.get(station_id, 0)) + 1
						line_boarded[lid_t] = int(line_boarded.get(lid_t, 0)) + 1
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
						_start_boarding_walker(item, p_target, sview, tram_state, dest_final)
						_repack_waiting_queue(station_id)
						_refresh_station_label(station_id)
						did_work = true

		if did_work:
			tram_state["pax_xfer_accum"] = float(tram_state["pax_xfer_accum"]) - 1.0
		else:
			tram_state["pax_xfer_accum"] = 0.0
			break


func _spawn_one_random_passenger(graph: NetworkGraph, instant_place: bool) -> void:
	var line_ids := graph.lines.keys()
	if line_ids.is_empty():
		return
	var lid: int = int(line_ids[_rng.randi() % line_ids.size()])
	var ln: Dictionary = graph.lines[lid]
	var sids: Array = ln["station_ids"]
	if sids.size() < 2:
		return

	var unique_sids: Array[int] = []
	for raw_s in sids:
		var s_int := int(raw_s)
		if not unique_sids.has(s_int) and _station_views.has(s_int):
			unique_sids.append(s_int)
	if unique_sids.size() < 2:
		return

	var orig_sid: int = unique_sids[_rng.randi() % unique_sids.size()]
	var dest_sid: int = unique_sids[_rng.randi() % unique_sids.size()]
	if dest_sid == orig_sid:
		dest_sid = unique_sids[(unique_sids.find(orig_sid) + 1) % unique_sids.size()]

	var q: Array = station_queues.get(orig_sid, [])
	if q.size() >= 45:
		return

	var sview: Dictionary = _station_views[orig_sid]
	var slots: Array = sview["waiting_slots"]
	var slot_idx := q.size()
	var agent_dict: Dictionary = {}

	if slot_idx < slots.size():
		var slot_pos: Vector3 = slots[slot_idx]
		var start_pos: Vector3 = slot_pos if instant_place else (sview["ramp_entry"] as Vector3)
		agent_dict = _create_3d_person(start_pos)
		agent_dict["target"] = slot_pos
		agent_dict["face_pos"] = sview["pos"] as Vector3
		agent_dict["mode"] = "wait" if instant_place else "walk_to_slot"
		if not instant_place:
			_active_walkers.append(agent_dict)
		else:
			_orient_person_toward(agent_dict["node"] as Node3D, sview["pos"] as Vector3)

	q.append({
		"dest_sid": dest_sid,
		"line_id": lid,
		"agent": agent_dict,
	})
	station_queues[orig_sid] = q
	_refresh_station_label(orig_sid)


func _start_boarding_walker(
	item: Dictionary,
	portal: Dictionary,
	sview: Dictionary,
	tram_state: Dictionary,
	dest_sid: int
) -> void:
	var ag: Dictionary = item.get("agent", {})
	if ag.is_empty() or not is_instance_valid(ag.get("node")):
		var slots: Array = sview["waiting_slots"]
		var start_p: Vector3 = slots[0] if not slots.is_empty() else (sview["board_edge"] as Vector3)
		ag = _create_3d_person(start_p)

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

	ag["waypoints"] = [plat_standoff, door_thresh, inner_p, aisle_p]
	ag["target"] = plat_standoff
	ag["mode"] = "board_enter"
	ag["speed"] = 2.25 + _rng.randf() * 0.35
	ag["tram_ref"] = tram_state
	ag["dest_sid"] = dest_sid
	ag["portal_ref"] = portal
	if not _active_walkers.has(ag):
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
	var slots: Array = sview["waiting_slots"]
	var mid_plat: Vector3 = (slots[_rng.randi() % mini(6, slots.size())] as Vector3) if not slots.is_empty() else (sview["board_edge"] as Vector3)
	var exit_pt: Vector3 = sview["ramp_entry"] as Vector3
	ag["waypoints"] = [outer_p, plat_standoff, mid_plat, exit_pt]
	ag["target"] = outer_p
	ag["mode"] = "alight_exit"
	ag["speed"] = 1.95 + _rng.randf() * 0.25
	_active_walkers.append(ag)


func _repack_waiting_queue(station_id: int) -> void:
	if not _station_views.has(station_id):
		return
	var sview: Dictionary = _station_views[station_id]
	var slots: Array = sview["waiting_slots"]
	var q: Array = station_queues.get(station_id, [])
	for i in range(mini(q.size(), slots.size())):
		var item: Dictionary = q[i]
		var ag: Dictionary = item.get("agent", {})
		if ag.is_empty() or not is_instance_valid(ag.get("node")):
			ag = _create_3d_person(slots[i] as Vector3)
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
			if tr_ref.is_empty() or float(tr_ref.get("door_ratio", 0.0)) < 0.12:
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

		var target: Vector3 = ag["target"]
		var spd := float(ag.get("speed", 1.85))
		var cur := node.global_position
		var diff := target - cur
		var dist := diff.length()

		if dist <= 0.14:
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
	onboard_list.append(int(ag.get("dest_sid", -1)))
	var tinfo: Dictionary = tr_ref.get("tram_info", {})
	if not tinfo.is_empty():
		TramBuilder.update_onboard_passengers(tinfo, onboard_list.size(), int(tr_ref.get("capacity", 120)))


func _update_waiting_idle() -> void:
	for sid: int in station_queues.keys():
		var q: Array = station_queues[sid]
		for i in range(mini(q.size(), 18)):
			var ag: Dictionary = q[i].get("agent", {})
			if ag.is_empty() or str(ag.get("mode", "")) != "wait":
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
	_inst(torso, torso_m, Vector3.ZERO, coat_mat)
	if wears_skirt:
		var skirt_mat: Material = coat_mat if arch == 2 else _coat_mats[_rng.randi() % _coat_mats.size()]
		_inst(root, HumanMeshGen.get_skirt_mesh(_rng.randf() < 0.45), Vector3(0.0, 0.90, 0.0), skirt_mat)
	elif arch != 2:
		_box(torso, Vector3(0.30, 0.032, 0.20), Vector3(0.0, -0.22, 0.0), _belt_mat)
	_box(torso, Vector3(0.088, 0.095, 0.145), Vector3(0.0, 0.21, -0.02), _shirt_mat)
	# Collar, front placket/zip and patch pockets
	var trim_mat: Material = _acc_mats[0] if _rng.randf() < 0.5 else _shirt_mat
	var collar := _inst(torso, _hair_dome_mesh, Vector3(0.0, 0.255, 0.0), coat_mat)
	collar.scale = Vector3(0.95, 0.32, 0.82)
	_box(torso, Vector3(0.012, 0.40, 0.008), Vector3(0.0, 0.02, -0.112), trim_mat)
	if arch != 2:
		for pk: float in [-1.0, 1.0]:
			_box(torso, Vector3(0.075, 0.008, 0.012), Vector3(pk * 0.085, -0.13, -0.108), trim_mat)
	var bag_mat: Material = _acc_mats[_rng.randi() % _acc_mats.size()]
	var bag_roll := _rng.randf()
	if arch == 3 or bag_roll < 0.30:
		# Rounded daypack with shoulder straps
		var bp := _inst(torso, _torso_mesh, Vector3(0.0, 0.0, 0.16), bag_mat)
		bp.scale = Vector3(0.92, 0.66, 0.42)
		_box(torso, Vector3(0.20, 0.10, 0.03), Vector3(0.0, -0.10, 0.215), bag_mat)
		for bs: float in [-1.0, 1.0]:
			_box(torso, Vector3(0.035, 0.012, 0.12), Vector3(bs * 0.085, 0.235, 0.09), bag_mat)
	elif bag_roll < 0.52:
		# Cross-body shoulder bag / tote at the hip
		var hip_s := -1.0 if _rng.randf() < 0.5 else 1.0
		_box(torso, Vector3(0.07, 0.24, 0.30), Vector3(hip_s * 0.215, -0.30, 0.0), bag_mat)
		var strap := _box(torso, Vector3(0.012, 0.66, 0.03), Vector3(0.0, 0.0, -0.118), bag_mat)
		strap.rotation.z = hip_s * deg_to_rad(38.0)
		var strap_b := _box(torso, Vector3(0.012, 0.66, 0.03), Vector3(0.0, 0.0, 0.118), bag_mat)
		strap_b.rotation.z = hip_s * deg_to_rad(38.0)

	# Articulated Left & Right Arms (Sculpted Upper Arm + Elbow Hinge + Sculpted Forearm + Hand)
	var sh_x := 0.185 if arch == 2 else 0.205
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-sh_x, 0.20, 0.0)
	torso.add_child(arm_l)
	_inst(arm_l, uarm_m, Vector3(0.0, -0.13, 0.0), coat_mat)
	var elbow_l := Node3D.new()
	elbow_l.position = Vector3(0.0, -0.26, 0.0)
	elbow_l.rotation.x = deg_to_rad(-8.0)
	arm_l.add_child(elbow_l)
	_inst(elbow_l, farm_m, Vector3(0.0, -0.13, 0.0), coat_mat)
	_inst(elbow_l, _hand_mesh, Vector3(0.0, -0.265, 0.0), skin_mat)

	var arm_r := Node3D.new()
	arm_r.position = Vector3(sh_x, 0.20, 0.0)
	torso.add_child(arm_r)
	_inst(arm_r, uarm_m, Vector3(0.0, -0.13, 0.0), coat_mat)
	var elbow_r := Node3D.new()
	elbow_r.position = Vector3(0.0, -0.26, 0.0)
	elbow_r.rotation.x = deg_to_rad(-8.0)
	arm_r.add_child(elbow_r)
	_inst(elbow_r, farm_m, Vector3(0.0, -0.13, 0.0), coat_mat)
	_inst(elbow_r, _hand_mesh, Vector3(0.0, -0.265, 0.0), skin_mat)

	# Sculpted Neck + Full-Coverage Hair + Detailed 3D Front Face (Ears, Eyebrows, Eyes, Nose, Lips, Optional Glasses)!
	var neck := _inst(torso, farm_m, Vector3(0.0, 0.295, 0.0), skin_mat)
	neck.scale = Vector3(1.18, 0.38, 1.18)
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
	if acc_roll < 0.12:
		# Baseball cap
		var cap := _inst(head, _hair_dome_mesh, Vector3(0.0, 0.052, 0.004), hat_mat)
		cap.scale = Vector3(0.88, 0.62, 0.95)
		_box(head, Vector3(0.13, 0.008, 0.075), Vector3(0.0, 0.052, -0.118), hat_mat).rotation.x = deg_to_rad(-8.0)
	elif acc_roll < 0.22:
		# Knit beanie
		var bn := _inst(head, _hair_dome_mesh, Vector3(0.0, 0.06, 0.006), hat_mat)
		bn.scale = Vector3(0.9, 0.78, 0.96)
	elif acc_roll < 0.30:
		# Over-ear headphones
		var hp := _box(head, Vector3(0.17, 0.012, 0.024), Vector3(0.0, 0.118, 0.006), _phone_mat)
		hp.rotation.z = 0.0
		for es: float in [-1.0, 1.0]:
			_box(head, Vector3(0.012, 0.11, 0.02), Vector3(es * 0.083, 0.07, 0.006), _phone_mat)
			_inst(head, _hand_mesh, Vector3(es * 0.084, 0.0, 0.006), _phone_mat).scale = Vector3(0.55, 1.05, 1.05)
	if _rng.randf() < 0.16:
		# Scarf wrapped at the neck
		var sc := _inst(torso, _hair_dome_mesh, Vector3(0.0, 0.29, 0.0), hat_mat)
		sc.scale = Vector3(0.82, 0.36, 0.78)
		_box(torso, Vector3(0.06, 0.22, 0.02), Vector3(0.05, 0.16, -0.12), hat_mat)
	if _rng.randf() < 0.24:
		# Looking at a phone: forearm raised, glowing screen in hand
		elbow_r.rotation.x = deg_to_rad(78.0)
		_box(elbow_r, Vector3(0.072, 0.15, 0.011), Vector3(-0.015, -0.30, -0.03), _phone_mat)
		_box(elbow_r, Vector3(0.062, 0.13, 0.004), Vector3(-0.015, -0.30, -0.037), _screen_mat)

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


static func _inst(parent: Node3D, m: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.visibility_range_end = 190.0
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

		# Compute pure lateral direction toward the raised platform (matching TramBuilder._is_door_allowed_by_platform!)
		var plat_dir := Vector3.ZERO
		if st_side != 0:
			plat_dir = st_right * float(st_side)
		else:
			# Central Island Platform: st_pos lies between both tracks; use lateral projection so longitudinal offset never fails!
			var lat_to_island := (st_pos - ip).dot(st_right)
			if absf(lat_to_island) < 0.05:
				continue
			plat_dir = st_right * signf(lat_to_island)

		# Verify this doorway STRICTLY faces the platform side (never the opposite closed side!)
		if out_v.dot(plat_dir) <= 0.35:
			continue
		# Also ensure the doorway is within the raised platform longitudinal span!
		if absf((op - st_pos).dot(st_fwd)) > 13.05:
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


func _refresh_station_label(station_id: int) -> void:
	if not _station_views.has(station_id):
		return
	var lbl: Label3D = _station_views[station_id].get("wait_label")
	if is_instance_valid(lbl):
		var cnt: int = (station_queues.get(station_id, []) as Array).size()
		lbl.text = "候车 %d 人" % cnt if cnt > 0 else "暂无候车"


static func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi
