class_name TransitSim
extends Node3D

const NOTCH_LABELS := ["EB", "B4", "B3", "B2", "B1", "N", "P1", "P2", "P3", "P4"]
const NOTCH_NEUTRAL := 5
const TURNBACK_STOP_MARGIN := 1.0 # Lead bogie stops this far before the terminal turnback point
const BUFFER_SAFE_KMH := 5.0 # buffer stops absorb a gentle coupling-speed touch; anything faster derails
const TERMINAL_REQUEST_DIST_M := 170.0 # Trams request a terminal platform this far before the hold point
const PLATFORM_A := 0 # Arrive straight in, cross over after departing
const PLATFORM_B := 1 # Cross over before arriving, depart straight out (needs a scissors crossover)

var trams: Array[Dictionary] = []
var active_tram_idx := 0
var manual_drive := false
var _anim_time := 0.0
var operating_seconds := 0.0
var line_dist_m: Dictionary = {} # line_id -> float (total distance traveled by trams on this line)
var line_variants: Dictionary = {} # line_id -> {variant_key: compiled route} (one per terminal platform combination)


func rebuild_fleet(
	graph: NetworkGraph,
	catalogue: Array,
	night_factor: float
) -> void:
	for c in get_children():
		c.queue_free()
	trams.clear()
	active_tram_idx = 0
	operating_seconds = 0.0
	line_dist_m.clear()
	line_variants.clear()

	for lid: int in graph.lines.keys():
		var ln: Dictionary = graph.lines[lid]
		var compiled := graph.compile_line_route(ln)
		if compiled.is_empty():
			continue
		line_variants[lid] = _compile_line_variants(graph, ln, compiled)

		var spec := _find_model_spec(catalogue, str(ln.get("model_key", "siemens-s700")))
		var sec_cnt := clampi(int(ln.get("sections", int(spec.get("default_sections", 2)))), 1, 2)
		var fleet_n := clampi(int(ln.get("trams_count", 2)), 1, 8)
		var route_len := float(compiled["length"])
		var is_loop := bool(compiled["is_loop"])
		var stops: Array = compiled["stops"]
		var cap := sec_cnt * int(spec.get("cap_per_section", 58))
		var rev_cusps: Array = compiled.get("turnbacks", [])
		# The Seattle Center Monorail runs one red and one blue Alweg train
		var spec_line := spec
		var spec_alt: Dictionary = {}
		if str(spec.get("key", "")) == "seattle-alweg-red":
			spec_alt = _find_model_spec(catalogue, "seattle-alweg-blue")

		for ti in range(fleet_n):
			spec = spec_alt if (ti % 2 == 1 and not spec_alt.is_empty()) else spec_line
			var tinfo := TramBuilder.build_tram(spec, sec_cnt)
			add_child(tinfo["root"] as Node3D)

			var init_s := 20.0
			var init_dir := 1.0
			if is_loop:
				init_s = fposmod(float(ti) * (route_len / float(fleet_n)) + 16.0, route_len)
			else:
				if fleet_n == 1:
					init_s = clampf(float(stops[0]["offset"]) + 6.0, 2.0, route_len - 2.0)
				else:
					var frac := float(ti) / float(maxi(1, fleet_n - 1))
					var safe_pad := minf(26.0, route_len * 0.14)
					init_s = lerpf(safe_pad, maxf(safe_pad + 8.0, route_len - safe_pad), frac)
					init_dir = 1.0 if (ti % 2 == 0) else -1.0

			var seed_dests: Array = []
			if stops.size() >= 2:
				var target_stop_i := (ti + 1) % stops.size()
				var seed_sid := int(stops[target_stop_i]["station_id"])
				for _p in range(4 + (ti % 3) * 2):
					seed_dests.append(seed_sid)
			TramBuilder.update_onboard_passengers(tinfo, seed_dests.size(), cap)

			var tr_dict := {
				"line_id": lid,
				"line_name": str(ln["name"]),
				"line_color": ln["color"],
				"spec": spec,
				"elevated": bool(spec.get("monorail", false)),
				"tram_info": tinfo,
				"curve": compiled["curve"],
				"route_len": route_len,
				"is_loop": is_loop,
				"stops": stops,
				"rail_heights": compiled["rail_heights"],
				"speed_limits_kmh": compiled["speed_limits_kmh"],
				"derail_kmh": compiled["derail_kmh"],
				"curve_signs": compiled["curve_signs"],
				"zone_kinds": compiled["zone_kinds"],
				"s": init_s,
				"speed_mps": 0.0,
				"accel_mps2": 0.0,
				"dir": init_dir,
				"cab_flipped": false,
				"reversal_offsets": rev_cusps,
				"notch": NOTCH_NEUTRAL,
				"doors_target_open": false,
				"door_ratio": 0.0,
				"dwell_timer": 0.0,
				"dwell_elapsed": 0.0,
				"depart_cooldown": 0.0,
				"at_station_id": -1,
				"capacity": cap,
				"pax_dests": seed_dests,
				"pending_boarders": 0,
				"pax_xfer_accum": 0.0,
				"body_roll_rad": 0.0,
				"derailed": false,
				"crashed": false,
				"rollover_sign": 1.0,
				"rollover_progress": 0.0,
				"variant_key": "",
				"b_sids": {},
				"terminal_zones": compiled.get("terminal_zones", []),
				"term_res": {}, # station_id -> {platform, phase: "in" | "dwell" | "out"}
				"term_hold_s": -1.0,
			}
			trams.append(tr_dict)
			_position_tram_3d(tr_dict)

	apply_night_lights(night_factor)


func export_run_state() -> Dictionary:
	var tr_states: Array = []
	for tr: Dictionary in trams:
		tr_states.append({
			"line_id": int(tr["line_id"]),
			"s": float(tr["s"]),
			"speed_mps": float(tr["speed_mps"]),
			"dir": float(tr["dir"]),
			"cab_flipped": bool(tr.get("cab_flipped", false)),
			"variant_key": str(tr.get("variant_key", "")),
			"notch": int(tr["notch"]),
			"doors_target_open": bool(tr["doors_target_open"]),
			"door_ratio": float(tr["door_ratio"]),
			"pax_dests": (tr["pax_dests"] as Array).duplicate(),
		})
	return {
		"active_tram_idx": active_tram_idx,
		"manual_drive": manual_drive,
		"trams": tr_states,
	}


func import_run_state(run_state: Dictionary, graph: NetworkGraph) -> void:
	if run_state.is_empty():
		return
	var tr_states: Array = run_state.get("trams", [])
	for i in range(mini(trams.size(), tr_states.size())):
		var st: Dictionary = tr_states[i]
		var tr: Dictionary = trams[i]
		if int(st.get("line_id", -1)) != int(tr["line_id"]):
			continue
		var v_key := str(st.get("variant_key", ""))
		var variants: Dictionary = line_variants.get(int(tr["line_id"]), {})
		if v_key != "" and variants.has(v_key):
			_apply_route_variant(tr, variants[v_key] as Dictionary, v_key)
		tr["term_res"] = {}
		tr["term_init_done"] = false
		var rlen := float(tr["route_len"])
		tr["s"] = fposmod(float(st.get("s", tr["s"])), rlen) if bool(tr["is_loop"]) else clampf(float(st.get("s", tr["s"])), 1.5, maxf(2.0, rlen - 1.5))
		tr["speed_mps"] = clampf(float(st.get("speed_mps", 0.0)), 0.0, 28.0)
		tr["dir"] = 1.0 if float(st.get("dir", 1.0)) >= 0.0 else -1.0
		tr["cab_flipped"] = bool(st.get("cab_flipped", false))
		tr["notch"] = clampi(int(st.get("notch", NOTCH_NEUTRAL)), 0, NOTCH_LABELS.size() - 1)
		tr["doors_target_open"] = bool(st.get("doors_target_open", false))
		tr["door_ratio"] = clampf(float(st.get("door_ratio", 0.0)), 0.0, 1.0)
		var dests: Array = st.get("pax_dests", [])
		tr["pax_dests"] = dests.duplicate()
		_position_tram_3d(tr)
		var dock := get_dock_info_for_tram(tr, graph)
		TramBuilder.update_doors(tr["tram_info"], float(tr["door_ratio"]), dock)
		TramBuilder.update_onboard_passengers(tr["tram_info"], (tr["pax_dests"] as Array).size(), int(tr["capacity"]))
	active_tram_idx = clampi(int(run_state.get("active_tram_idx", 0)), 0, maxi(0, trams.size() - 1))
	manual_drive = bool(run_state.get("manual_drive", false))


func get_active_tram() -> Dictionary:
	if trams.is_empty():
		return {}
	active_tram_idx = posmod(active_tram_idx, trams.size())
	return trams[active_tram_idx]


func cycle_active_tram(delta_i: int = 1) -> void:
	if trams.is_empty():
		return
	active_tram_idx = posmod(active_tram_idx + delta_i, trams.size())


func apply_night_lights(night_factor: float) -> void:
	var show_interior := (night_factor > 0.08)
	for tr: Dictionary in trams:
		var tinfo: Dictionary = tr["tram_info"]
		var spot: SpotLight3D = tinfo.get("head_spot")
		if is_instance_valid(spot):
			spot.visible = (night_factor > 0.05)
			spot.light_energy = lerpf(0.0, 3.8, night_factor)
		for il in tinfo.get("interior_lights", []):
			if is_instance_valid(il):
				var omni := il as OmniLight3D
				omni.visible = show_interior
				omni.light_energy = lerpf(0.0, 1.15, night_factor)


# Returns {} normally, or an accident Dictionary when a derailment or collision terminates the run!
func step_all_trams(
	dt: float,
	graph: NetworkGraph,
	pax_sim: PassengerSim,
	traffic_sim: TrafficSim,
	sound: SoundSynth
) -> Dictionary:
	_anim_time += dt
	operating_seconds += dt
	sound.overspeed_squeal = 0.0
	_update_terminal_interlocking()

	for i in range(trams.size()):
		var tr: Dictionary = trams[i]
		var is_player_manual := (i == active_tram_idx and manual_drive)

		if not is_player_manual:
			_step_ai_driver(tr, i, dt, graph, pax_sim, traffic_sim, sound, i == active_tram_idx)

		var derail_ev := _step_tram_physics_and_doors(tr, i, dt, graph, pax_sim, sound, i == active_tram_idx, is_player_manual)
		_position_tram_3d(tr)

		if not derail_ev.is_empty():
			return derail_ev

		# Only animate passenger rigs on trams within 135m of camera/active tram for top FPS!
		var secs: Array = tr["tram_info"]["sections"]
		if i == active_tram_idx or (not secs.is_empty() and _is_near_active_tram(secs[0] as Node3D)):
			TramBuilder.animate_onboard_passengers(
				tr["tram_info"] as Dictionary,
				_anim_time,
				float(tr["speed_mps"]),
				float(tr.get("accel_mps2", 0.0)),
				dt
			)

	# 0. Update Live In-Cab MFD Tram Signal Repeater for the active tram (both Manual & AI!)
	if traffic_sim != null and not trams.is_empty():
		var act_tr := get_active_tram()
		var cab_c: Dictionary = act_tr["tram_info"].get("cab_controls", {})
		var sig_l: Label3D = cab_c.get("sig_label")
		if is_instance_valid(sig_l):
			var s_inf := traffic_sim.get_upcoming_tram_signal(act_tr, graph)
			if bool(s_inf.get("has_signal", false)):
				var asp := str(s_inf["aspect"])
				var sd := int(round(float(s_inf["dist"])))
				if asp == "red":
					sig_l.text = "━ STOP %dm" % sd
					sig_l.modulate = Color(1.0, 0.28, 0.22)
				elif asp == "yellow":
					sig_l.text = "● WAIT %dm" % sd
					sig_l.modulate = Color(1.0, 0.78, 0.16)
				else:
					sig_l.text = "┃ GO %dm" % sd
					sig_l.modulate = Color(0.28, 0.96, 0.58)
			else:
				sig_l.text = "┃ CLEAR"
				sig_l.modulate = Color(0.32, 0.88, 0.96)
			var hold_d := _terminal_hold_distance(act_tr)
			if hold_d < 220.0:
				sig_l.text = "━ HOLD %dm" % int(round(hold_d))
				sig_l.modulate = Color(1.0, 0.28, 0.22)

	# 1. Check Tram-vs-Tram Collision!
	var tt_hit := _check_tram_to_tram_collisions()
	if bool(tt_hit.get("hit", false)):
		return {
			"accident": true,
			"type": "tram_collision",
			"tram_idx": int(tt_hit["tram_idx"]),
			"other_tram_idx": int(tt_hit["other_tram_idx"]),
			"world_pos": tt_hit["world_pos"],
			"speed_kmh": float(tt_hit["speed_kmh"]),
		}

	# 2. Check Tram-vs-Car Collision!
	if traffic_sim != null:
		var tc_hit := traffic_sim.check_tram_collisions(trams)
		if bool(tc_hit.get("hit", false)):
			var hit_ti := int(tc_hit["tram_idx"])
			var hit_tr: Dictionary = trams[hit_ti]
			var impact_kmh := maxf(float(hit_tr["speed_mps"]) * 3.6, 18.0)
			hit_tr["crashed"] = true
			hit_tr["speed_mps"] = 0.0
			_apply_collision_jolt(hit_tr, 1.0)
			return {
				"accident": true,
				"type": "car_collision",
				"tram_idx": hit_ti,
				"world_pos": tc_hit["world_pos"],
				"speed_kmh": impact_kmh,
			}

	return {}


func step_accident_visuals(dt: float) -> void:
	for tr: Dictionary in trams:
		if not bool(tr.get("derailed", false)):
			continue
		var prog := float(tr.get("rollover_progress", 0.0))
		if prog >= 1.0:
			continue
		prog = minf(1.0, prog + dt * 1.55)
		tr["rollover_progress"] = prog
		_position_tram_3d(tr)


func _is_near_active_tram(node: Node3D) -> bool:
	if trams.is_empty():
		return true
	var act := get_active_tram()
	var a_secs: Array = act["tram_info"]["sections"]
	if a_secs.is_empty():
		return true
	return node.global_position.distance_squared_to((a_secs[0] as Node3D).global_position) < 135.0 * 135.0


func manual_step_notch(delta_notch: int, sound: SoundSynth) -> void:
	var tr := get_active_tram()
	if tr.is_empty():
		return
	manual_drive = true
	if delta_notch > 0 and (bool(tr["doors_target_open"]) or float(tr["door_ratio"]) > 0.05):
		if int(tr["notch"]) >= NOTCH_NEUTRAL:
			tr["doors_target_open"] = false
			sound.play_door_chime()
			return
	tr["notch"] = clampi(int(tr["notch"]) + delta_notch, 0, NOTCH_LABELS.size() - 1)


func manual_set_notch(n_idx: int) -> void:
	var tr := get_active_tram()
	if tr.is_empty():
		return
	manual_drive = true
	tr["notch"] = clampi(n_idx, 0, NOTCH_LABELS.size() - 1)


func manual_toggle_doors(sound: SoundSynth, graph: NetworkGraph = null) -> bool:
	var tr := get_active_tram()
	if tr.is_empty():
		return false
	if float(tr["speed_mps"]) > 0.30:
		return false
	manual_drive = true
	var new_open := not bool(tr["doors_target_open"])
	if new_open:
		var dock := get_dock_info_for_tram(tr, graph)
		if not bool(dock["has_station"]):
			tr["doors_target_open"] = false
			return false
		var res := TramBuilder.update_doors(tr["tram_info"], 1.0, dock)
		var aligned_n := int(res.get("open_doorways", 0))
		tr["aligned_doorways"] = aligned_n
		tr["total_doorways"] = int(res.get("total_doorways", 1))
		TramBuilder.update_doors(tr["tram_info"], float(tr["door_ratio"]), dock)
		if aligned_n <= 0:
			tr["doors_target_open"] = false
			return false
	tr["doors_target_open"] = new_open
	if new_open and int(tr["notch"]) > NOTCH_NEUTRAL:
		tr["notch"] = NOTCH_NEUTRAL
	sound.play_door_chime()
	return true


func get_dock_info_for_tram(tr: Dictionary, graph: NetworkGraph) -> Dictionary:
	var near := _find_station_at_current_pos(tr)
	var sid := int(near["station_id"])
	if sid < 0 or graph == null or not graph.stations.has(sid):
		return {"has_station": false, "station_id": -1, "stop_idx": -1}
	var st: Dictionary = graph.stations[sid]
	var st_pos: Vector3 = st["pos"]
	var st_fwd := (st["fwd"] as Vector3).normalized()
	var st_side := float(st.get("side", 1))
	var eid := int(st.get("edge_id", -1))
	if eid >= 0 and int(graph.built_track_modes.get(eid, NetworkGraph.TrackMode.SINGLE)) == NetworkGraph.TrackMode.DOUBLE:
		var st_right := st_fwd.cross(Vector3.UP).normalized()
		st_pos += st_right * (st_side * NetworkGraph.DOUBLE_TRACK_HALF_SEP)
	return {
		"has_station": true,
		"station_id": sid,
		"stop_idx": int(near["stop_idx"]),
		"st_pos": st_pos,
		"st_fwd": st_fwd,
		"st_side": st_side,
		"plat_half_len": 13.05,
	}


# Driver's cab change ("换端"): walk to the other cab and drive back the way you came.
# Returns "ok" on success, otherwise a reason code: "moving", "doors", "not_terminal", "no_tram".
func manual_reverse_dir() -> String:
	var tr := get_active_tram()
	if tr.is_empty():
		return "no_tram"
	if float(tr["speed_mps"]) >= 0.15:
		return "moving"
	if float(tr["door_ratio"]) >= 0.05 or bool(tr.get("doors_target_open", false)):
		return "doors"
	if bool(tr["is_loop"]):
		# Loop lines are compiled with terminal turnbacks: the cab can only be changed at a terminal
		# (anywhere on the platform / tail track before the turnback point).
		if _try_turnback_flip(tr, 60.0):
			manual_drive = true
			tr["notch"] = NOTCH_NEUTRAL
			return "ok"
		return "not_terminal"
	manual_drive = true
	tr["notch"] = NOTCH_NEUTRAL
	_reverse_tram_switch_cab(tr)
	return "ok"


# Distance (m) from the active tram's nose to the next terminal turnback point ahead, or -1 if none near.
func turnback_distance_ahead(tr: Dictionary, max_d: float = 400.0) -> float:
	if tr.is_empty() or not bool(tr.get("is_loop", false)):
		return -1.0
	var rlen := float(tr["route_len"])
	var dir := float(tr["dir"])
	var best := -1.0
	for z: Dictionary in tr.get("terminal_zones", []):
		var d := fposmod((float(z["cusp_s"]) - float(tr["s"])) * dir, rlen)
		if d > rlen * 0.5:
			d -= rlen
		if d >= -8.0 and d <= max_d and (best < 0.0 or d < best):
			best = d
	return best


# If a terminal turnback point lies just ahead of the lead bogie, change cab in place: the route's return leg
# retraces the arrival leg, so mirroring s about the turnback point keeps every bogie exactly where it stands.
func _try_turnback_flip(tr: Dictionary, reach: float = 30.0) -> bool:
	var rlen := float(tr["route_len"])
	var dir := float(tr["dir"])
	var s_cur := float(tr["s"])
	var c_len := _consist_length(tr)
	for z: Dictionary in tr.get("terminal_zones", []):
		var rev_s := float(z["cusp_s"])
		var d_ahead := fposmod((rev_s - s_cur) * dir, rlen)
		if d_ahead > rlen * 0.5:
			d_ahead -= rlen # Slightly overshot the turnback point
		if d_ahead <= reach + float(z.get("stop_back", 0.0)) and d_ahead >= -8.0:
			tr["cab_flipped"] = not bool(tr.get("cab_flipped", false))
			tr["s"] = fposmod(rev_s + dir * (d_ahead + c_len), rlen)
			var res: Dictionary = tr["term_res"]
			res[int(z["station_id"])] = {"platform": int(z["platform"]), "phase": "out"}
			_position_tram_3d(tr)
			return true
	return false


func _reverse_tram_switch_cab(tr: Dictionary) -> void:
	var old_dir := float(tr["dir"])
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	var tinfo: Dictionary = tr["tram_info"]
	var sec_cnt := maxi(1, int(tinfo.get("sections_count", 1)))
	var sec_len := float(tinfo.get("section_len", 9.2))
	var span := float(sec_cnt - 1) * (sec_len + 0.62) + sec_len * 0.68
	var s_shifted := float(tr["s"]) - old_dir * span
	tr["dir"] = -old_dir
	tr["s"] = fposmod(s_shifted, rlen) if is_loop else clampf(s_shifted, 1.0, maxf(2.0, rlen - 1.0))
	_position_tram_3d(tr)


# O(1) Speed Limit + Upcoming Curve/Turnout Restriction Telemetry!
func get_speed_limit_status(tr: Dictionary) -> Dictionary:
	var limits: PackedFloat32Array = tr.get("speed_limits_kmh", PackedFloat32Array())
	var derails: PackedFloat32Array = tr.get("derail_kmh", PackedFloat32Array())
	var c_signs: PackedFloat32Array = tr.get("curve_signs", PackedFloat32Array())
	var zones: PackedByteArray = tr.get("zone_kinds", PackedByteArray())
	var n := limits.size()
	if n == 0:
		return {
			"limit_kmh": 60.0,
			"derail_kmh": 999.0,
			"zone_kind": 0,
			"zone_name": "正线",
			"curve_sign": 0.0,
			"next_limit_kmh": 60.0,
			"next_dist_m": 999.0,
			"next_zone_name": "",
		}

	var s_now := float(tr["s"])
	var dir := float(tr["dir"])
	var is_loop := bool(tr["is_loop"])

	# Check strictest limit across the whole tram consist (front nose to tail)
	var c_len := _consist_length(tr)
	var idx_front := clampi(int(round(s_now / NetworkGraph.PROFILE_STEP_M)), 0, n - 1)
	var cur_lim := limits[idx_front]
	var cur_der := derails[idx_front]
	var cur_zk := int(zones[idx_front])
	var cur_cs := c_signs[idx_front]

	var tail_steps := int(ceil(c_len / NetworkGraph.PROFILE_STEP_M))
	var step_sign := int(signf(dir))
	for back_k in range(1, tail_steps + 1):
		var bi := posmod(idx_front - back_k * step_sign, n) if is_loop else clampi(idx_front - back_k * step_sign, 0, n - 1)
		if limits[bi] < cur_lim:
			cur_lim = limits[bi]
			cur_der = derails[bi]
			cur_zk = int(zones[bi])
			if absf(c_signs[bi]) > 0.1:
				cur_cs = c_signs[bi]

	# Scan up to 110m ahead for the STRICTEST upcoming lower speed restriction (never stop early at a mild bend!)
	var next_lim := cur_lim
	var next_dist := 999.0
	var next_zk := 0
	for k in range(2, 56):
		var raw_idx := idx_front + k * step_sign
		if not is_loop and (raw_idx < 0 or raw_idx >= n):
			break
		var ai := posmod(raw_idx, n) if is_loop else raw_idx
		if limits[ai] < cur_lim - 1.0 and limits[ai] < next_lim:
			next_lim = limits[ai]
			next_dist = float(k) * NetworkGraph.PROFILE_STEP_M
			next_zk = int(zones[ai])

	return {
		"limit_kmh": cur_lim,
		"derail_kmh": cur_der,
		"zone_kind": cur_zk,
		"zone_name": NetworkGraph.ZONE_LABELS[clampi(cur_zk, 0, NetworkGraph.ZONE_LABELS.size() - 1)],
		"curve_sign": cur_cs,
		"next_limit_kmh": next_lim,
		"next_dist_m": next_dist,
		"next_zone_name": NetworkGraph.ZONE_LABELS[clampi(next_zk, 0, NetworkGraph.ZONE_LABELS.size() - 1)],
	}


static func _consist_length(tr: Dictionary) -> float:
	var tinfo: Dictionary = tr.get("tram_info", {})
	var sec_cnt := maxi(1, int(tinfo.get("sections_count", 1)))
	var sec_len := float(tinfo.get("section_len", 9.2))
	return float(sec_cnt - 1) * (sec_len + 0.62) + sec_len * 0.68


func _stop_target_offset_for_station(tr: Dictionary, stop: Dictionary) -> float:
	var dir := float(tr["dir"])
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	var st_off := float(stop["offset"])
	# Terminal turnback: the stop offset IS the turnback point at the far end of the platform,
	# so pull right up to it (whole tram on the platform) and change cab there.
	if bool(stop.get("turnback", false)):
		var term_target := st_off - dir * TURNBACK_STOP_MARGIN
		return fposmod(term_target, rlen) if is_loop else clampf(term_target, 1.5, maxf(2.0, rlen - 1.5))
	var align_lead := minf(_consist_length(tr) * 0.38, 9.5)
	var target := st_off + dir * align_lead
	if is_loop:
		return fposmod(target, rlen)
	return clampf(target, 1.5, maxf(2.0, rlen - 1.5))


# Manual approach readout: the stop the driver is pulling into and the signed distance (m) from the lead
# cab to its stopping position (positive = still to go, negative = overshot). Overshoots up to 40m still
# refer to that stop, so the driver sees "-3 m" instead of the next station.
func stop_approach_info(tr: Dictionary) -> Dictionary:
	var stops: Array = tr.get("stops", [])
	if stops.is_empty():
		return {}
	var s_now := float(tr["s"])
	var dir := float(tr["dir"])
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	var best_i := -1
	var best_d := 1e9
	for i in range(stops.size()):
		var target := _stop_target_offset_for_station(tr, stops[i] as Dictionary)
		var d := (target - s_now) * dir
		if is_loop:
			d = fposmod(d + rlen * 0.5, rlen) - rlen * 0.5
			if d < -40.0:
				d += rlen
		if d >= -40.0 and d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return {}
	return {
		"station_id": int(stops[best_i]["station_id"]),
		"name": str(stops[best_i]["name"]),
		"signed_dist": best_d,
		"stop_idx": best_i,
	}


func find_next_stop_info(tr: Dictionary) -> Dictionary:
	var stops: Array = tr.get("stops", [])
	if stops.is_empty():
		return {"station_id": -1, "name": "无车站", "dist": 999.0, "stop_idx": -1, "is_terminal": false}

	if float(tr.get("depart_cooldown", 0.0)) <= 0.0 and (float(tr.get("door_ratio", 0.0)) > 0.05 or float(tr["speed_mps"]) < 0.35):
		var docked := _find_station_at_current_pos(tr)
		var d_idx := int(docked["stop_idx"])
		if d_idx >= 0:
			var dir_chk := float(tr["dir"])
			var is_loop_chk := bool(tr["is_loop"])
			var is_term_chk := (not is_loop_chk) and (
				(dir_chk > 0.0 and d_idx == stops.size() - 1)
				or (dir_chk < 0.0 and d_idx == 0)
			)
			return {
				"station_id": int(stops[d_idx]["station_id"]),
				"name": str(stops[d_idx]["name"]),
				"dist": 0.0,
				"stop_idx": d_idx,
				"is_terminal": is_term_chk,
			}

	var s_now := float(tr["s"])
	var dir := float(tr["dir"])
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])

	var best_idx := 0
	var best_dist := 1e9

	for i in range(stops.size()):
		var mark_off := _stop_target_offset_for_station(tr, stops[i] as Dictionary)
		var d := 1e9
		if is_loop:
			d = fposmod((mark_off - s_now) * dir, rlen)
			if d > rlen - 3.2:
				d = 0.0
		else:
			var signed_d := (mark_off - s_now) * dir
			if signed_d >= -3.2:
				d = maxf(0.0, signed_d)
		if d < best_dist:
			best_dist = d
			best_idx = i

	var is_term := (not is_loop) and (
		(dir > 0.0 and best_idx == stops.size() - 1)
		or (dir < 0.0 and best_idx == 0)
	)
	return {
		"station_id": int(stops[best_idx]["station_id"]),
		"name": str(stops[best_idx]["name"]),
		"dist": best_dist,
		"stop_idx": best_idx,
		"is_terminal": is_term,
	}


func get_upcoming_station_ids(tr: Dictionary, current_stop_idx: int) -> Array[int]:
	var stops: Array = tr.get("stops", [])
	var out: Array[int] = []
	if stops.is_empty() or current_stop_idx < 0:
		return out
	var is_loop := bool(tr["is_loop"])
	var dir := float(tr["dir"])

	if is_loop:
		for step in range(1, stops.size()):
			var idx := posmod(current_stop_idx + step * int(signf(dir)), stops.size())
			out.append(int(stops[idx]["station_id"]))
	else:
		if dir > 0.0:
			for idx in range(current_stop_idx + 1, stops.size()):
				out.append(int(stops[idx]["station_id"]))
		else:
			var idx := current_stop_idx - 1
			while idx >= 0:
				out.append(int(stops[idx]["station_id"]))
				idx -= 1
	return out


func _step_ai_driver(
	tr: Dictionary,
	my_idx: int,
	dt: float,
	graph: NetworkGraph,
	pax_sim: PassengerSim,
	traffic_sim: TrafficSim,
	sound: SoundSynth,
	play_audio: bool
) -> void:
	if float(tr["depart_cooldown"]) > 0.0:
		tr["depart_cooldown"] = float(tr["depart_cooldown"]) - dt

	var door_r := float(tr["door_ratio"])
	var target_open := bool(tr["doors_target_open"])
	var spd := float(tr["speed_mps"])

	var depart_pending := bool(tr.get("ai_depart_pending", false))
	if target_open or door_r > 0.02 or depart_pending:
		tr["notch"] = 3
		tr["dwell_timer"] = float(tr["dwell_timer"]) - dt
		tr["dwell_elapsed"] = float(tr.get("dwell_elapsed", 0.0)) + dt
		var docked_now := _find_station_at_current_pos(tr)
		var docked_sid := int(docked_now["station_id"])
		var has_room := ((tr["pax_dests"] as Array).size() + int(tr.get("pending_boarders", 0))) < int(tr["capacity"])
		var more_waiting := (docked_sid >= 0) and has_room and pax_sim.has_waiting_passengers(docked_sid)
		var walkers_still_boarding := pax_sim.has_walkers_boarding_tram(tr)
		var can_close := (float(tr["dwell_timer"]) <= 0.0) and ((not more_waiting and not walkers_still_boarding) or float(tr["dwell_elapsed"]) >= 16.0)
		if can_close and target_open:
			tr["doors_target_open"] = false
			tr["ai_depart_pending"] = true # Depart once doors are shut (frame-rate independent)
			if play_audio:
				sound.play_door_chime()
		elif not target_open and door_r <= 0.03:
			var docked := _find_station_at_current_pos(tr)
			var stops: Array = tr["stops"]
			var d_idx := int(docked["stop_idx"])
			if bool(tr["is_loop"]) and d_idx >= 0 and bool((stops[d_idx] as Dictionary).get("turnback", false)) \
					and _terminal_departure_blocked(tr, int((stops[d_idx] as Dictionary)["station_id"])):
				tr["notch"] = 3 # Hold at the platform: a tram is crossing over into the other platform track
				return
			tr["ai_depart_pending"] = false
			var dir_now := float(tr["dir"])
			var s_cur := float(tr["s"])
			var rlen_cur := float(tr["route_len"])
			if not bool(tr["is_loop"]):
				var near_end := (dir_now > 0.0 and s_cur >= rlen_cur - 6.0) or (dir_now < 0.0 and s_cur <= 6.0)
				var at_term_stop := (d_idx >= 0 and ((dir_now > 0.0 and d_idx == stops.size() - 1) or (dir_now < 0.0 and d_idx == 0)))
				if near_end or at_term_stop:
					_reverse_tram_switch_cab(tr)
			else:
				# Terminal turnback: change driving cab as doors close and depart back along the same
				# track; the route then crosses over to the right-hand track at the crossover.
				if d_idx >= 0 and bool((stops[d_idx] as Dictionary).get("turnback", false)):
					_try_turnback_flip(tr)
			if play_audio:
				sound.ring_bell()
			tr["depart_cooldown"] = 8.5
			tr["notch"] = 8
		return

	# 0. Terminal interlocking: wait before the crossover until a platform track is free
	var term_hold_d := _terminal_hold_distance(tr)
	if term_hold_d < 1e8:
		if term_hold_d <= 1.2:
			tr["notch"] = 1
			if spd < 0.55:
				tr["speed_mps"] = 0.0
			return
		elif spd > maxf(0.8, sqrt(2.0 * 0.92 * maxf(0.4, term_hold_d - 1.2))):
			tr["notch"] = 1 if term_hold_d < 14.0 else 2
			return

	# 1. Defensive braking for a tram occupying my path ahead: brake on a curve that stops ~9m behind it
	var gap_ahead := _distance_to_tram_ahead(tr, my_idx)
	if gap_ahead < 900.0:
		var gap_decel := float((tr["spec"] as Dictionary).get("decel", 1.3)) * 0.62
		var gap_room := gap_ahead - 9.0
		var safe_v := sqrt(2.0 * gap_decel * maxf(0.0, gap_room))
		if gap_room <= 0.6:
			tr["notch"] = 1
			if spd < 0.55:
				tr["speed_mps"] = 0.0
			return
		elif spd > safe_v + 2.5:
			tr["notch"] = 0 if gap_room < 12.0 else 1
			return
		elif spd > safe_v:
			tr["notch"] = 2
			return
		elif spd > safe_v - 0.8:
			tr["notch"] = NOTCH_NEUTRAL
			return

	# 2. Obey Dedicated Tram Signal ('━' Stop / '●' Yellow) cleanly BEHIND stop line + Defensive Intersection Slowdown!
	var intersection_cap_mps := 99.0
	if traffic_sim != null:
		var sig_info := traffic_sim.get_upcoming_tram_signal(tr, graph)
		if bool(sig_info["has_signal"]):
			var sig_d := float(sig_info["dist"])
			var stop_line := float(sig_info.get("stop_line", 11.2))
			if str(sig_info["aspect"]) != "green":
				# Brake early from 46m out so AI NEVER runs a yellow/red light!
				if sig_d >= stop_line - 1.4 and sig_d <= 46.0:
					var d_to_stop_line := sig_d - stop_line
					if d_to_stop_line <= 2.2:
						tr["notch"] = 1 # Hold firmly behind stop line
						if spd < 0.55:
							tr["speed_mps"] = 0.0
						return
					elif spd > maxf(0.8, sqrt(2.0 * 0.92 * maxf(0.4, d_to_stop_line - 1.5))):
						tr["notch"] = 1 if d_to_stop_line < 14.0 else 2
						return
			elif sig_d > stop_line and sig_d <= 36.0:
				# Defensive intersection approach slowdown (<= 26 km/h) so light changes never catch AI overspeeding!
				intersection_cap_mps = 26.0 / 3.6

		var haz := traffic_sim.find_hazard_along_tram_curve(tr, 48.0)
		if bool(haz["has_hazard"]):
			var hd := float(haz["dist"])
			var eb_dist := maxf(24.0, (spd * spd) / 4.8 + 8.0)
			if hd < eb_dist:
				tr["notch"] = 0 # Full Electromagnetic Track-Brake EB!
				if hd < 9.5:
					tr["speed_mps"] = move_toward(spd, 0.0, 14.0 * dt)
				elif spd < 0.45:
					tr["speed_mps"] = 0.0
				return
			elif hd < 46.0 and spd > maxf(0.8, sqrt(2.0 * 1.45 * maxf(0.5, hd - 11.0))):
				tr["notch"] = 1 # Firm B4 braking well ahead of obstacle
				return

	var stops_list: Array = tr.get("stops", [])
	if stops_list.is_empty():
		return

	var s_now := float(tr["s"])
	var dir := float(tr["dir"])
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	var dist_ahead := 1e9
	for i in range(stops_list.size()):
		var mark_off := _stop_target_offset_for_station(tr, stops_list[i] as Dictionary)
		var d := 1e9
		if is_loop:
			d = fposmod((mark_off - s_now) * dir, rlen)
			if d > rlen - 3.2:
				d = 0.0
		else:
			var signed_d := (mark_off - s_now) * dir
			if signed_d >= -3.2:
				d = maxf(0.0, signed_d)
		if d < dist_ahead:
			dist_ahead = d

	var at_track_end := (not is_loop) and ((dir > 0.0 and s_now >= rlen - 2.2) or (dir < 0.0 and s_now <= 2.2))

	var spec: Dictionary = tr["spec"]
	var decel := float(spec.get("decel", 1.3)) * 0.78
	var stop_dist := (spd * spd) / maxf(0.4, 2.0 * decel)

	if float(tr["depart_cooldown"]) <= 0.0 and ((dist_ahead <= 3.8 and spd < 0.55) or (at_track_end and spd < 0.35)):
		tr["speed_mps"] = 0.0
		tr["notch"] = 3
		tr["doors_target_open"] = true
		tr["dwell_timer"] = 4.6
		tr["dwell_elapsed"] = 0.0
		if play_audio:
			sound.play_door_chime()
		return

	# 3. AI strictly & proactively obeys current & upcoming Curve/Turnout Speed Limits (never overspeeding 20 km/h bends!)
	var lim_info := get_speed_limit_status(tr)
	var allowed_mps := minf((float(lim_info["limit_kmh"]) - 3.0) / 3.6, intersection_cap_mps)
	var next_lim_mps := (float(lim_info["next_limit_kmh"]) - 3.0) / 3.6
	var next_lim_dist := float(lim_info["next_dist_m"])
	if next_lim_dist < 105.0 and spd > next_lim_mps:
		var req_brake_d := (spd * spd - next_lim_mps * next_lim_mps) / maxf(0.5, 2.0 * decel * 0.72)
		if next_lim_dist <= req_brake_d + 14.0:
			allowed_mps = minf(allowed_mps, next_lim_mps)

	if float(tr["depart_cooldown"]) <= 0.0 and dist_ahead <= stop_dist + 7.0:
		if dist_ahead <= 2.2:
			tr["notch"] = 3
		elif spd > maxf(1.3, sqrt(2.0 * decel * maxf(0.5, dist_ahead - 1.2))):
			tr["notch"] = 2
		elif spd < 1.05:
			tr["notch"] = 6
		else:
			tr["notch"] = NOTCH_NEUTRAL
	else:
		var cruise_mps := minf(minf(float(spec.get("max_speed_kmh", 70)) * 0.68, 48.0) / 3.6, allowed_mps)
		if spd > allowed_mps + 2.2:
			tr["notch"] = 1 # Firm B4 braking if well above upcoming curve/intersection limit
		elif spd > allowed_mps + 0.5:
			tr["notch"] = 2 # Smooth B3 braking for curve/turnout limit
		elif spd > cruise_mps + 0.5:
			tr["notch"] = 4
		elif spd < cruise_mps - 1.4:
			tr["notch"] = 8
		elif spd < cruise_mps - 0.2:
			tr["notch"] = 6
		else:
			tr["notch"] = NOTCH_NEUTRAL


# Clear distance to the nearest tram that physically occupies MY path ahead (walks my own route curve and looks
# for other trams' car bodies on it). Works across route variants, wrong-track running and opposing trams.
func _distance_to_tram_ahead(tr: Dictionary, my_idx: int) -> float:
	var best := 999.0
	var my_secs: Array = tr["tram_info"]["sections"]
	if my_secs.is_empty():
		return best
	var my_pos := (my_secs[0] as Node3D).global_position
	var cands: Array[Vector2] = []
	for j in range(trams.size()):
		if j == my_idx or bool(trams[j].get("elevated", false)) != bool(tr.get("elevated", false)):
			continue # trams and monorails run on separate levels
		var oth_secs: Array = trams[j]["tram_info"]["sections"]
		for sec: Node3D in oth_secs:
			var gp := sec.global_position
			if gp.distance_squared_to(my_pos) < 175.0 * 175.0:
				cands.append(Vector2(gp.x, gp.z))
	if cands.is_empty():
		return best
	var curve: Curve3D = tr["curve"]
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	var dir := float(tr["dir"])
	var s_me := float(tr["s"])
	var sec_len := float(tr["tram_info"].get("section_len", 9.2))
	var front_overhang := sec_len * 0.16
	var k := 1.0
	while k <= 140.0:
		var s_k := s_me + dir * k
		if is_loop:
			s_k = fposmod(s_k, rlen)
		elif s_k < 0.0 or s_k > rlen:
			break
		var p := curve.sample_baked(s_k, false)
		var p2 := Vector2(p.x, p.z)
		for c: Vector2 in cands:
			if c.distance_squared_to(p2) < 1.7 * 1.7:
				# Section center found on my path: its near end is ~half a section closer
				return maxf(0.5, k - sec_len * 0.5 - front_overhang - 0.6)
		k += 1.0
	return best


func _step_tram_physics_and_doors(
	tr: Dictionary,
	tram_idx: int,
	dt: float,
	graph: NetworkGraph,
	pax_sim: PassengerSim,
	sound: SoundSynth,
	is_active_cam: bool,
	_is_player_manual: bool
) -> Dictionary:
	var tinfo: Dictionary = tr["tram_info"]
	var target_r := 1.0 if bool(tr["doors_target_open"]) else 0.0
	var door_r := float(tr["door_ratio"])
	var dock_info := get_dock_info_for_tram(tr, graph)
	if absf(door_r - target_r) > 0.001 or door_r > 0.001:
		door_r = move_toward(door_r, target_r, dt * 0.78)
		tr["door_ratio"] = door_r
		var d_res := TramBuilder.update_doors(tinfo, door_r, dock_info)
		tr["open_doorways"] = int(d_res.get("open_doorways", 0))
		tr["total_doorways"] = int(d_res.get("total_doorways", 1))
	else:
		tr["open_doorways"] = 0

	if door_r > 0.55 and float(tr["speed_mps"]) < 0.30 and int(tr.get("open_doorways", 0)) > 0:
		if int(dock_info["station_id"]) >= 0:
			var upcoming := get_upcoming_station_ids(tr, int(dock_info["stop_idx"]))
			if upcoming.is_empty() and not bool(tr["is_loop"]):
				var rev_copy := tr.duplicate()
				rev_copy["dir"] = -float(tr["dir"])
				upcoming = get_upcoming_station_ids(rev_copy, int(dock_info["stop_idx"]))
			pax_sim.exchange_passengers_at_station(tr, int(dock_info["station_id"]), upcoming, dt)

	var spec: Dictionary = tr["spec"]
	var max_spd_mps := float(spec.get("max_speed_kmh", 70)) / 3.6
	var max_accel := float(spec.get("accel", 1.25))
	var max_decel := float(spec.get("decel", 1.35))

	var notch := int(tr["notch"])
	var prev_spd := float(tr["speed_mps"])
	var spd := prev_spd
	var cmd_acc := 0.0
	var effort := 0.0

	if door_r > 0.03:
		cmd_acc = -max_decel
	elif notch > NOTCH_NEUTRAL:
		var p_lvl := float(notch - NOTCH_NEUTRAL) / 4.0
		var taper := clampf(1.0 - pow(spd / maxf(1.0, max_spd_mps), 3.0), 0.0, 1.0)
		cmd_acc = max_accel * p_lvl * taper
		effort = p_lvl
	elif notch < NOTCH_NEUTRAL:
		if notch == 0:
			cmd_acc = -max_decel * 3.40 # Full Electromagnetic Track-Brake Emergency Stop!
			effort = -1.0
		else:
			var b_lvl := float(NOTCH_NEUTRAL - notch) / 4.0
			cmd_acc = -max_decel * b_lvl
			effort = -b_lvl

	var drag := 0.045 + 0.0012 * spd * spd
	spd = maxf(0.0, minf(spd + (cmd_acc - drag) * dt, max_spd_mps * 1.08))
	if spd < 0.02 and notch <= NOTCH_NEUTRAL:
		spd = 0.0

	tr["accel_mps2"] = lerpf(float(tr.get("accel_mps2", 0.0)), (spd - prev_spd) / maxf(dt, 0.001), minf(1.0, dt * 8.0))

	var dir := float(tr["dir"])
	var rlen := float(tr["route_len"])
	var ds := spd * dir * dt
	var s_prev := float(tr["s"])
	var s_new := s_prev + ds
	var lid_dist := int(tr["line_id"])
	line_dist_m[lid_dist] = float(line_dist_m.get(lid_dist, 0.0)) + absf(ds)

	if bool(tr["is_loop"]):
		s_new = fposmod(s_new, rlen)
		# Buffer stop at the end of a terminal tail track: the route only continues past the turnback
		# point after a cab change, so a tram (manually driven or not) can never run through it.
		if ds != 0.0:
			for z: Dictionary in tr.get("terminal_zones", []):
				var cusp := float(z["cusp_s"])
				var d_prev := fposmod((cusp - s_prev) * dir, rlen)
				if d_prev > 0.5 and d_prev < 40.0 and absf(ds) >= d_prev - 0.5:
					s_new = fposmod(cusp - dir * 0.5, rlen)
					var hit_kmh := spd * 3.6
					spd = 0.0
					if bool(z.get("buffer", false)) and hit_kmh > BUFFER_SAFE_KMH:
						# Ran into the buffer stop at the end of the track: the tram is thrown off the rails
						tr["s"] = s_new
						tr["speed_mps"] = 0.0
						tr["derailed"] = true
						tr["rollover_sign"] = 1.0 if (tram_idx % 2 == 0) else -1.0
						tr["rollover_progress"] = 0.06
						var secs_b: Array = tinfo["sections"]
						return {
							"accident": true,
							"type": "buffer",
							"tram_idx": tram_idx,
							"world_pos": (secs_b[0] as Node3D).global_position if not secs_b.is_empty() else Vector3.ZERO,
							"speed_kmh": hit_kmh,
							"station_id": int(z["station_id"]),
						}
					if hit_kmh > 1.0 and is_active_cam and sound != null:
						sound.play_notch_click()
					break
	else:
		if s_new >= rlen - 1.0:
			s_new = rlen - 1.0
			spd = 0.0
		elif s_new <= 1.0:
			s_new = 1.0
			spd = 0.0

	tr["s"] = s_new
	tr["speed_mps"] = spd

	# Evaluate Curve & Turnout Speed Limit, Centrifugal Roll, and Derailment Rollover!
	var lim_stat := get_speed_limit_status(tr)
	var kmh := spd * 3.6
	var lim_kmh := float(lim_stat["limit_kmh"])
	var der_kmh := float(lim_stat["derail_kmh"])
	var c_sign := float(lim_stat["curve_sign"])
	var outward := (-c_sign * signf(dir)) if absf(c_sign) > 0.1 else 1.0

	var target_roll := 0.0
	if der_kmh < 900.0 and kmh > lim_kmh:
		var over_ratio := clampf((kmh - lim_kmh) / maxf(1.0, der_kmh - lim_kmh), 0.0, 1.35)
		target_roll = outward * deg_to_rad(over_ratio * 10.5)
		if is_active_cam:
			sound.overspeed_squeal = clampf(0.25 + over_ratio * 0.75, 0.0, 1.0)

		# Overturning threshold reached -> DERAILMENT & ROLLOVER!
		if kmh >= der_kmh:
			tr["derailed"] = true
			tr["rollover_sign"] = outward
			tr["rollover_progress"] = 0.12
			tr["speed_mps"] = 0.0
			var secs_d: Array = tinfo["sections"]
			var crash_pos := (secs_d[0] as Node3D).global_position if not secs_d.is_empty() else Vector3.ZERO
			return {
				"accident": true,
				"type": "derail",
				"tram_idx": tram_idx,
				"world_pos": crash_pos,
				"speed_kmh": kmh,
				"limit_kmh": lim_kmh,
				"zone_name": str(lim_stat["zone_name"]),
			}

	tr["body_roll_rad"] = lerpf(float(tr.get("body_roll_rad", 0.0)), target_roll, minf(1.0, dt * 8.0))

	var lever: Node3D = tinfo.get("throttle_lever")
	if is_instance_valid(lever):
		var norm_n := float(notch - NOTCH_NEUTRAL) / 4.0
		lever.rotation.x = lerpf(lever.rotation.x, deg_to_rad(-norm_n * 30.0), minf(1.0, dt * 15.0))

	if is_active_cam:
		var cab_ctrls: Dictionary = tinfo.get("cab_controls", {})
		var mfd_lbl: Label3D = cab_ctrls.get("mfd_label")
		if is_instance_valid(mfd_lbl):
			mfd_lbl.text = "%04.1f" % kmh
			mfd_lbl.modulate = Color(1.0, 0.35, 0.28) if (kmh > lim_kmh + 0.5) else Color(0.62, 0.96, 1.0)
		var needle: Node3D = cab_ctrls.get("speed_needle")
		if is_instance_valid(needle):
			var target_ang := deg_to_rad(135.0 - clampf(kmh / 80.0, 0.0, 1.0) * 270.0)
			needle.rotation.z = lerpf(needle.rotation.z, target_ang, minf(1.0, dt * 14.0))
		var btn_rev: Node3D = cab_ctrls.get("btn_rev")
		if is_instance_valid(btn_rev):
			btn_rev.rotation.y = lerpf(btn_rev.rotation.y, deg_to_rad(32.0 if dir > 0.0 else -32.0), minf(1.0, dt * 12.0))
		var d_mat: StandardMaterial3D = cab_ctrls.get("door_btn_mat")
		if d_mat != null:
			d_mat.emission_energy_multiplier = 2.0 if door_r > 0.1 else 0.75
		var wipers: Array = cab_ctrls.get("wipers", [])
		if not wipers.is_empty():
			var w_ang := sin(_anim_time * 4.2) * deg_to_rad(32.0) if bool(tr.get("wipers_on", false)) else 0.0
			for wp in wipers:
				if is_instance_valid(wp):
					(wp as Node3D).rotation.z = lerpf((wp as Node3D).rotation.z, w_ang, minf(1.0, dt * 12.0))
		sound.speed_mps = spd
		sound.traction_effort = effort
		sound.advance_distance(ds)

	return {}


func _check_tram_to_tram_collisions() -> Dictionary:
	var n := trams.size()
	if n < 2:
		return {"hit": false}

	for i in range(n):
		var tr_a: Dictionary = trams[i]
		var info_a: Dictionary = tr_a["tram_info"]
		var secs_a: Array = info_a["sections"]
		var hla := float(info_a.get("section_len", 9.2)) * 0.5 - 0.22
		var hwa := float(info_a.get("width", 2.6)) * 0.5 - 0.10

		for j in range(i + 1, n):
			var tr_b: Dictionary = trams[j]
			if bool(tr_a.get("elevated", false)) != bool(tr_b.get("elevated", false)):
				continue
			var info_b: Dictionary = tr_b["tram_info"]
			var secs_b: Array = info_b["sections"]
			var hlb := float(info_b.get("section_len", 9.2)) * 0.5 - 0.22
			var hwb := float(info_b.get("width", 2.6)) * 0.5 - 0.10

			# Broad-phase distance check between lead sections
			if secs_a.is_empty() or secs_b.is_empty():
				continue
			if (secs_a[0] as Node3D).global_position.distance_squared_to((secs_b[0] as Node3D).global_position) > 48.0 * 48.0:
				continue

			for sa: Node3D in secs_a:
				var pa3 := sa.global_position
				var fa3 := -sa.global_transform.basis.z
				var pa2 := Vector2(pa3.x, pa3.z)
				var fa2 := Vector2(fa3.x, fa3.z).normalized()

				for sb: Node3D in secs_b:
					var pb3 := sb.global_position
					if pa3.distance_squared_to(pb3) > 95.0:
						continue
					var fb3 := -sb.global_transform.basis.z
					var pb2 := Vector2(pb3.x, pb3.z)
					var fb2 := Vector2(fb3.x, fb3.z).normalized()
					if TrafficSim.obb_overlap_2d(pa2, fa2, hla, hwa, pb2, fb2, hlb, hwb):
						var rel_kmh := (float(tr_a["speed_mps"]) + float(tr_b["speed_mps"])) * 3.6
						tr_a["crashed"] = true; tr_a["speed_mps"] = 0.0
						tr_b["crashed"] = true; tr_b["speed_mps"] = 0.0
						_apply_collision_jolt(tr_a, 1.0)
						_apply_collision_jolt(tr_b, -1.0)
						return {
							"hit": true,
							"tram_idx": i,
							"other_tram_idx": j,
							"world_pos": (pa3 + pb3) * 0.5,
							"speed_kmh": maxf(rel_kmh, 15.0),
						}
	return {"hit": false}


static func _apply_collision_jolt(tr: Dictionary, side: float) -> void:
	var secs: Array = tr["tram_info"]["sections"]
	if not secs.is_empty() and is_instance_valid(secs[0]):
		var s0 := secs[0] as Node3D
		s0.rotate_y(deg_to_rad(9.5 * side))
		s0.rotate_object_local(Vector3.FORWARD, deg_to_rad(6.5 * side))


func _find_station_at_current_pos(tr: Dictionary) -> Dictionary:
	var stops: Array = tr.get("stops", [])
	if stops.is_empty():
		return {"station_id": -1, "stop_idx": -1}

	var s_now := float(tr["s"])
	var dir := float(tr["dir"])
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	var c_len := _consist_length(tr)

	var best_idx := -1
	var best_score := 1e9

	for i in range(stops.size()):
		var st_off := float(stops[i]["offset"])
		var rel := (st_off - s_now) * dir
		if is_loop:
			rel = fposmod(rel + rlen * 0.5, rlen) - rlen * 0.5
		if rel >= -c_len - 15.5 and rel <= 15.5:
			var center_err := absf(rel + c_len * 0.35)
			if center_err < best_score:
				best_score = center_err
				best_idx = i

	if best_idx >= 0:
		return {"station_id": int(stops[best_idx]["station_id"]), "stop_idx": best_idx}

	var tinfo: Dictionary = tr.get("tram_info", {})
	var secs: Array = tinfo.get("sections", [])
	for i in range(stops.size()):
		var st_pos: Vector3 = stops[i]["pos"]
		for sec: Node3D in secs:
			if is_instance_valid(sec) and sec.global_position.distance_to(st_pos) <= 21.0:
				return {"station_id": int(stops[i]["station_id"]), "stop_idx": i}

	return {"station_id": -1, "stop_idx": -1}


# O(1) rail height lookup from pre-baked array (replaces 576-edge scan!)
static func _sample_rail_height(tr: Dictionary, s: float) -> float:
	var heights: PackedFloat32Array = tr.get("rail_heights", PackedFloat32Array())
	var n := heights.size()
	if n == 0:
		return 0.0
	var rlen := float(tr["route_len"])
	var s_wrap := fposmod(s, rlen) if bool(tr["is_loop"]) else clampf(s, 0.0, rlen)
	var f_idx := clampf(s_wrap / NetworkGraph.PROFILE_STEP_M, 0.0, float(n - 1))
	var i0 := int(floor(f_idx))
	var i1 := mini(i0 + 1, n - 1)
	return lerpf(heights[i0], heights[i1], f_idx - float(i0))


func _position_tram_3d(tr: Dictionary) -> void:
	if bool(tr.get("crashed", false)):
		return

	var tinfo: Dictionary = tr["tram_info"]
	var curve: Curve3D = tr["curve"]
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	var dir := float(tr["dir"])

	var sections: Array = tinfo["sections"]
	var gangways: Array = tinfo["gangways"]
	var sec_len := float(tinfo.get("section_len", 9.2))
	var pitch_stride := sec_len + 0.62
	var bogie_span := sec_len * 0.68
	var lead_s := float(tr["s"])

	var body_roll := float(tr.get("body_roll_rad", 0.0))
	var is_derailed := bool(tr.get("derailed", false))
	var roll_prog := float(tr.get("rollover_progress", 0.0))
	var roll_sign := float(tr.get("rollover_sign", 1.0))

	var n_sec := sections.size()
	var active_end := 0
	if is_loop:
		active_end = (1 if bool(tr.get("cab_flipped", false)) else 0) ^ (0 if dir >= 0.0 else 1)
	else:
		active_end = 0 if dir >= 0.0 else 1
	TramBuilder.set_active_cab_end(tinfo, active_end)

	for k in range(n_sec):
		var sec_idx := k if active_end == 0 else (n_sec - 1 - k)
		var sec_node: Node3D = sections[sec_idx]
		var s_front := lead_s - dir * float(k) * pitch_stride
		var s_rear := s_front - dir * bogie_span
		var tf_f := TrackBuilder.sample_track_frame(curve, s_front, rlen, is_loop)
		var tf_r := TrackBuilder.sample_track_frame(curve, s_rear, rlen, is_loop)

		var p_f := tf_f.origin + Vector3(0.0, _sample_rail_height(tr, s_front), 0.0)
		var p_r := tf_r.origin + Vector3(0.0, _sample_rail_height(tr, s_rear), 0.0)

		var mid := (p_f + p_r) * 0.5
		var travel_fwd := (p_f - p_r).normalized()
		if travel_fwd.length_squared() < 0.001:
			travel_fwd = -tf_f.basis.z * dir
		# When Rear Cab (active_end == 1) leads, each section's local -Z points toward the trailing end
		# so the train physically reverses without flipping 180 degrees!
		var body_fwd := travel_fwd if active_end == 0 else -travel_fwd

		var base_basis := Basis.looking_at(body_fwd, Vector3.UP)
		if is_derailed:
			# Dramatic 3D Derailment & Rollover onto its side!
			var ease_p := 1.0 - pow(1.0 - roll_prog, 2.4)
			var sec_factor := clampf(1.0 - float(k) * 0.12, 0.72, 1.0)
			var tip_angle := roll_sign * deg_to_rad(83.0 * ease_p * sec_factor)
			var jackknife_yaw := roll_sign * deg_to_rad((16.0 if k % 2 == 0 else -14.0) * ease_p)
			var right_dir := base_basis.x
			mid += right_dir * (roll_sign * 2.25 * ease_p * sec_factor) + Vector3(0.0, sin(absf(tip_angle)) * 1.18, 0.0)
			base_basis = base_basis.rotated(Vector3.UP, jackknife_yaw)
			base_basis = base_basis.rotated(-base_basis.z.normalized(), tip_angle)
		elif absf(body_roll) > 0.001:
			base_basis = base_basis.rotated(-base_basis.z.normalized(), body_roll)

		sec_node.global_transform = Transform3D(base_basis, mid)

	var hl := sec_len * 0.5
	for g_i in range(gangways.size()):
		var gw: Node3D = gangways[g_i]
		var sec_a: Node3D = sections[g_i]
		var sec_b: Node3D = sections[g_i + 1]
		var p_a := sec_a.global_transform * Vector3(0.0, 0.0, hl - 0.15)
		var p_b := sec_b.global_transform * Vector3(0.0, 0.0, -hl + 0.15)
		var g_mid := (p_a + p_b) * 0.5
		var g_fwd := (p_a - p_b).normalized()
		if g_fwd.length_squared() > 0.001:
			gw.global_transform = Transform3D(Basis.looking_at(g_fwd, sec_a.global_transform.basis.y), g_mid)


static func _find_model_spec(catalogue: Array, key: String) -> Dictionary:
	for m: Dictionary in catalogue:
		if str(m.get("key", "")) == key:
			return m
	return catalogue[0] if not catalogue.is_empty() else {}


# ---------------------------------------------------------------------------------------------
# Terminal interlocking: platform tracks A / B at double-track turnback terminals
# ---------------------------------------------------------------------------------------------

static func _variant_key(b_sids: Dictionary) -> String:
	var ks: Array = b_sids.keys()
	ks.sort()
	var parts: PackedStringArray = []
	for k in ks:
		parts.append(str(k))
	return ",".join(parts)


func _compile_line_variants(graph: NetworkGraph, ln: Dictionary, base: Dictionary) -> Dictionary:
	var variants := {"": base}
	var b_list: Array[int] = []
	for z: Dictionary in base.get("terminal_zones", []):
		if bool(z["b_available"]):
			b_list.append(int(z["station_id"]))
	for mask in range(1, 1 << b_list.size()):
		var choice := {}
		for bi in range(b_list.size()):
			if mask & (1 << bi):
				choice[b_list[bi]] = true
		var c := graph.compile_line_route(ln, choice)
		if not c.is_empty():
			variants[_variant_key(choice)] = c
	return variants


func _apply_route_variant(tr: Dictionary, compiled: Dictionary, key: String) -> void:
	tr["curve"] = compiled["curve"]
	tr["route_len"] = float(compiled["length"])
	tr["stops"] = compiled["stops"]
	tr["rail_heights"] = compiled["rail_heights"]
	tr["speed_limits_kmh"] = compiled["speed_limits_kmh"]
	tr["derail_kmh"] = compiled["derail_kmh"]
	tr["curve_signs"] = compiled["curve_signs"]
	tr["zone_kinds"] = compiled["zone_kinds"]
	tr["reversal_offsets"] = compiled.get("turnbacks", [])
	tr["terminal_zones"] = compiled.get("terminal_zones", [])
	tr["variant_key"] = key
	var b_sids := {}
	for part in key.split(",", false):
		b_sids[int(part)] = true
	tr["b_sids"] = b_sids


static func _zone_for(tr: Dictionary, sid: int) -> Dictionary:
	for z: Dictionary in tr.get("terminal_zones", []):
		if int(z["station_id"]) == sid:
			return z
	return {}


# Switch a tram to the route variant where terminal `sid` uses `platform`, keeping it exactly where it is
# (variants are identical up to the hold point, so the distance to the hold point is preserved).
func _switch_terminal_platform(tr: Dictionary, sid: int, platform: int) -> void:
	var b_sids: Dictionary = (tr["b_sids"] as Dictionary).duplicate()
	if platform == PLATFORM_B:
		b_sids[sid] = true
	else:
		b_sids.erase(sid)
	var key := _variant_key(b_sids)
	if key == str(tr.get("variant_key", "")):
		return
	var variants: Dictionary = line_variants.get(int(tr["line_id"]), {})
	if not variants.has(key):
		return
	var old_z := _zone_for(tr, sid)
	var dir := float(tr["dir"])
	var d_before_hold := fposmod((float(old_z["hold_s"]) - float(tr["s"])) * dir, float(tr["route_len"]))
	_apply_route_variant(tr, variants[key] as Dictionary, key)
	var new_z := _zone_for(tr, sid)
	tr["s"] = fposmod(float(new_z["hold_s"]) - dir * d_before_hold, float(tr["route_len"]))
	_position_tram_3d(tr)


func _terminal_occupancy(my_idx: int, line_id: int, sid: int) -> Dictionary:
	var occ := {"a": false, "b": false, "a_out": false, "b_in": false}
	for j in range(trams.size()):
		if j == my_idx or int(trams[j]["line_id"]) != line_id:
			continue
		var res: Dictionary = trams[j].get("term_res", {})
		if not res.has(sid):
			continue
		var r: Dictionary = res[sid]
		if int(r["platform"]) == PLATFORM_B:
			occ["b"] = true
			if str(r["phase"]) == "in":
				occ["b_in"] = true
		else:
			occ["a"] = true
			if str(r["phase"]) == "out":
				occ["a_out"] = true
	return occ


# A tram leaving platform A crosses the path of a tram still running into platform B (scissors diamond).
func _terminal_departure_blocked(tr: Dictionary, sid: int) -> bool:
	var res: Dictionary = tr.get("term_res", {})
	if not res.has(sid) or int((res[sid] as Dictionary)["platform"]) != PLATFORM_A:
		return false
	return bool(_terminal_occupancy(trams.find(tr), int(tr["line_id"]), sid)["b_in"])


func _terminal_hold_distance(tr: Dictionary) -> float:
	var hs := float(tr.get("term_hold_s", -1.0))
	if hs < 0.0:
		return 1e9
	var d := fposmod((hs - float(tr["s"])) * float(tr["dir"]), float(tr["route_len"]))
	return d if d < float(tr["route_len"]) * 0.5 else 0.0 # Overshot the hold point: stop right here


func _update_terminal_interlocking() -> void:
	for i in range(trams.size()):
		var tr: Dictionary = trams[i]
		tr["term_hold_s"] = -1.0
		if not bool(tr["is_loop"]) or bool(tr.get("crashed", false)) or bool(tr.get("derailed", false)):
			continue
		var res: Dictionary = tr["term_res"]
		for z: Dictionary in (tr["terminal_zones"] as Array).duplicate():
			var rlen := float(tr["route_len"])
			var dir := float(tr["dir"])
			var s_now := float(tr["s"])
			var sid := int(z["station_id"])
			var hold_s := float(z["hold_s"])
			var cusp_s := float(z["cusp_s"])
			var exit_s := float(z["exit_s"])
			var arr_len := fposmod((cusp_s - hold_s) * dir, rlen)
			var dep_len := fposmod((exit_s - cusp_s) * dir, rlen) + _consist_length(tr)
			var from_hold := fposmod((s_now - hold_s) * dir, rlen)
			var from_cusp := fposmod((s_now - cusp_s) * dir, rlen)
			var in_arr := from_hold <= arr_len + 0.5
			var in_dep := (not in_arr) and from_cusp <= dep_len
			if res.has(sid):
				var r: Dictionary = res[sid]
				if str(r["phase"]) == "out":
					if not in_dep and not in_arr:
						res.erase(sid) # Tail has cleared the crossover: release the platform track
				elif str(r["phase"]) == "in":
					if bool(tr["doors_target_open"]) or (float(tr["speed_mps"]) < 0.1 and fposmod((cusp_s - s_now) * dir, rlen) < 6.0 + float(z.get("stop_back", 0.0))):
						r["phase"] = "dwell"
				continue
			var first_eval := not bool(tr.get("term_init_done", false))
			if (first_eval and in_arr) or in_dep:
				# Spawned / loaded inside the terminal zone: claim the track it is already on
				res[sid] = {"platform": int(z["platform"]), "phase": "out" if in_dep else "in"}
				continue
			if not in_arr and fposmod((hold_s - s_now) * dir, rlen) > TERMINAL_REQUEST_DIST_M:
				continue
			var occ := _terminal_occupancy(i, int(tr["line_id"]), sid)
			var can_a := not bool(occ["a"])
			var can_b := bool(z["b_available"]) and not bool(occ["b"]) and not bool(occ["a_out"])
			if in_arr and from_hold > NetworkGraph.TERMINAL_HOLD_MARGIN_M - 1.0:
				# Already at the crossover: only the track its current route takes (no sideways variant switch)
				can_a = can_a and int(z["platform"]) == PLATFORM_A
				can_b = can_b and int(z["platform"]) == PLATFORM_B
			var pick := -1
			if can_a:
				pick = PLATFORM_A
			elif can_b:
				pick = PLATFORM_B
			if pick < 0:
				tr["term_hold_s"] = hold_s # Both platform tracks busy: wait before the crossover
				continue
			res[sid] = {"platform": pick, "phase": "in"}
			_switch_terminal_platform(tr, sid, pick)
		tr["term_init_done"] = true
