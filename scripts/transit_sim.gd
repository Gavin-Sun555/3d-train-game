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
var _switch_timer := 0.0
var _last_tram_of_line: Dictionary = {} # line_id -> tram index last watched on that line
var _graph_ref: NetworkGraph = null # for compiling wrong-track route variants on demand
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
	_graph_ref = graph
	var placed_pts := PackedVector3Array() # every spawned train's footprint (any line) so new ones never overlap

	for lid: int in graph.lines.keys():
		var ln: Dictionary = graph.lines[lid]
		var compiled := graph.compile_line_route(ln)
		if compiled.is_empty():
			continue
		line_variants[lid] = _compile_line_variants(graph, ln, compiled)

		var spec := _find_model_spec(catalogue, str(ln.get("model_key", "siemens-s700")))
		var sec_cnt := clampi(int(ln.get("sections", int(spec.get("default_sections", 2)))), 1, 4)
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
			var sec_l := float(tinfo.get("section_len", 9.2))
			var c_len_spawn := float(sec_cnt - 1) * (sec_l + 0.62) + sec_l * 0.68
			if is_loop:
				init_s = fposmod(float(ti) * (route_len / float(fleet_n)) + 16.0, route_len)
				# A train starting at a terminal stands exactly where a train that stopped perfectly and changed cab
				# would be: ready to load and depart (stop readout 0 m, not up against the buffer stop)
				for st_t: Dictionary in stops:
					if not bool(st_t.get("turnback", false)):
						continue
					var dep_s := _departure_spawn_s(st_t, c_len_spawn, route_len)
					var cusp_t := float(st_t.get("cusp", st_t["offset"]))
					var span_t := fposmod(dep_s - cusp_t, route_len) + 45.0
					if (ti == 0 and st_t == stops[0]) or fposmod(init_s - cusp_t, route_len) < span_t:
						init_s = dep_s
						break
			else:
				if fleet_n == 1:
					init_s = clampf(float(stops[0]["offset"]) + minf(c_len_spawn * 0.38, 9.5), 2.0, route_len - 2.0)
				else:
					var frac := float(ti) / float(maxi(1, fleet_n - 1))
					var safe_pad := minf(26.0, route_len * 0.14)
					init_s = lerpf(safe_pad, maxf(safe_pad + 8.0, route_len - safe_pad), frac)
					init_dir = 1.0 if (ti % 2 == 0) else -1.0

			# Another line may already have a train standing here (lines sharing a terminal): move on until clear
			var c_spawn: Curve3D = compiled["curve"]
			var foot := float(sec_cnt) * (float(tinfo.get("section_len", 9.2)) + 0.62) + 6.0
			for _try in range(40):
				if _spawn_clear(c_spawn, init_s, init_dir, foot, route_len, is_loop, placed_pts):
					break
				var nxt_s := init_s + init_dir * 23.0
				if is_loop:
					init_s = fposmod(nxt_s, route_len)
				else:
					if nxt_s < 2.0 or nxt_s > route_len - 2.0:
						init_dir = -init_dir
						nxt_s = clampf(init_s, 2.0, route_len - 2.0)
					init_s = nxt_s
			placed_pts.append_array(_spawn_footprint(c_spawn, init_s, init_dir, foot, route_len, is_loop))

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
				"express": bool(ln.get("express", false)),
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
				"term_stage": "", # "" | "alight_only" | "flip_wait" | "board_only"
				"term_sid": -1,
				"term_flip_timer": 0.0,
			}
			trams.append(tr_dict)
			_position_tram_3d(tr_dict)

	apply_night_lights(night_factor)


# Head position of a train standing perfectly at terminal `stop` after its cab change (mirror of the arrival stop)
static func _departure_spawn_s(stop: Dictionary, c_len: float, rlen: float) -> float:
	var cusp := float(stop.get("cusp", stop["offset"]))
	var back := fposmod(cusp - float(stop["offset"]), rlen)
	if back > rlen * 0.5:
		back = 0.0
	return fposmod(cusp + back + TURNBACK_STOP_MARGIN + c_len, rlen)


static func _spawn_footprint(c: Curve3D, s: float, dir: float, foot: float, rlen: float, is_loop: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var k := -4.0
	while k <= foot:
		var sk := s - dir * k
		sk = fposmod(sk, rlen) if is_loop else clampf(sk, 0.0, rlen)
		out.append(c.sample_baked(sk))
		k += 3.0
	return out


static func _spawn_clear(c: Curve3D, s: float, dir: float, foot: float, rlen: float, is_loop: bool, placed: PackedVector3Array) -> bool:
	for p: Vector3 in _spawn_footprint(c, s, dir, foot, rlen, is_loop):
		for q: Vector3 in placed:
			if Vector2(p.x - q.x, p.z - q.z).length_squared() < 3.0 * 3.0:
				return false
	return true


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
			"term_stage": str(tr.get("term_stage", "")),
			"term_sid": int(tr.get("term_sid", -1)),
			"pax_dests": (tr["pax_dests"] as Array).duplicate(),
			"reverser": float(tr.get("reverser", 1.0)),
			"stats": _tram_stats_dict(tr),
			"held_manual": bool(tr.get("held_manual", false)),
		})
	return {
		"active_tram_idx": active_tram_idx,
		"manual_drive": manual_drive,
		"trams": tr_states,
	}


func _tram_stats_dict(tr: Dictionary) -> Dictionary:
	var d := {}
	for k: String in TRAM_STAT_KEYS:
		if tr.has(k):
			d[k] = tr[k]
	return d


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
		var v_route := _get_variant(int(tr["line_id"]), v_key) if v_key != "" else {}
		if not v_route.is_empty():
			_apply_route_variant(tr, v_route, v_key)
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
		tr["term_stage"] = str(st.get("term_stage", ""))
		tr["term_sid"] = int(st.get("term_sid", -1))
		tr["term_flip_timer"] = 0.0
		tr["reverser"] = -1.0 if float(st.get("reverser", 1.0)) < 0.0 else 1.0
		tr["held_manual"] = bool(st.get("held_manual", false))
		var sd: Dictionary = st.get("stats", {})
		for k: String in TRAM_STAT_KEYS:
			if sd.has(k):
				tr[k] = sd[k]
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


# Previous / next train on the SAME line as the currently watched train.
func cycle_active_tram(delta_i: int = 1) -> void:
	if trams.is_empty():
		return
	var lid := int(get_active_tram().get("line_id", -1))
	var same := line_tram_indices(lid)
	if same.size() <= 1:
		return
	var pos := maxi(0, same.find(active_tram_idx))
	active_tram_idx = int(same[posmod(pos + delta_i, same.size())])
	_last_tram_of_line[lid] = active_tram_idx
	_on_active_changed()


func select_tram(idx: int) -> void:
	if idx < 0 or idx >= trams.size():
		return
	active_tram_idx = idx
	_last_tram_of_line[int(trams[idx]["line_id"])] = idx
	_on_active_changed()


# Previous / next line (in line-id order); returns to the train last watched on that line.
func cycle_active_line(delta_i: int = 1) -> void:
	var lids := line_ids_in_service()
	if lids.size() <= 1:
		return
	var cur := int(get_active_tram().get("line_id", -1))
	var pos := maxi(0, lids.find(cur))
	var nl := int(lids[posmod(pos + delta_i, lids.size())])
	_last_tram_of_line[cur] = active_tram_idx
	var idxs := line_tram_indices(nl)
	var prefer := int(_last_tram_of_line.get(nl, -1))
	active_tram_idx = prefer if idxs.has(prefer) else int(idxs[0])
	_on_active_changed()


func line_ids_in_service() -> Array:
	var out: Array = []
	for tr: Dictionary in trams:
		var lid := int(tr["line_id"])
		if not out.has(lid):
			out.append(lid)
	out.sort()
	return out


# Per-train service statistics (shown on the operations board): distance, time moving / standing / dwelling,
# stops served (doors opened), top speed and peak load. Boarded / alighted counts come from PassengerSim.
const TRAM_STAT_KEYS := ["st_dist_m", "st_move_s", "st_stand_s", "st_dwell_s", "st_stops", "st_max_kmh", "st_boarded", "st_alighted", "st_peak_load", "st_hold_s"]


func _accumulate_tram_stats(tr: Dictionary, dt: float) -> void:
	var spd := float(tr["speed_mps"])
	var door_r := float(tr["door_ratio"])
	if spd > 0.3:
		tr["st_move_s"] = float(tr.get("st_move_s", 0.0)) + dt
	else:
		tr["st_stand_s"] = float(tr.get("st_stand_s", 0.0)) + dt
		if door_r > 0.02:
			tr["st_dwell_s"] = float(tr.get("st_dwell_s", 0.0)) + dt
	var opening := door_r > 0.02
	if opening and not bool(tr.get("st_doors_were_open", false)):
		tr["st_stops"] = int(tr.get("st_stops", 0)) + 1
	tr["st_doors_were_open"] = opening
	tr["st_max_kmh"] = maxf(float(tr.get("st_max_kmh", 0.0)), spd * 3.6)
	tr["st_peak_load"] = maxi(int(tr.get("st_peak_load", 0)), (tr["pax_dests"] as Array).size())
	if spd <= 0.3 and (float(tr.get("express_hold_t", 0.0)) > 0.0 or float(tr.get("merge_hold_s", -1.0)) >= 0.0):
		tr["st_hold_s"] = float(tr.get("st_hold_s", 0.0)) + dt


# Where a train is and what it is doing, for the operations board
func tram_status_text(tr: Dictionary) -> String:
	if bool(tr.get("derailed", false)) or bool(tr.get("crashed", false)):
		return "事故"
	if bool(tr.get("held_manual", false)):
		return "手动保留 · 停车待命"
	var spd := float(tr["speed_mps"])
	var term_stage := str(tr.get("term_stage", ""))
	if term_stage == "flip_wait":
		return "终点换端折返"
	if float(tr["door_ratio"]) > 0.02 or bool(tr["doors_target_open"]):
		var here := _find_station_at_current_pos(tr)
		var hi := int(here.get("stop_idx", -1))
		var stops_h: Array = tr["stops"]
		return "停站 · %s" % (str(stops_h[hi]["name"]) if hi >= 0 and hi < stops_h.size() else "站台")
	if float(tr.get("express_hold_t", 0.0)) > 0.0:
		return "待避快车"
	var nxt := find_next_stop_info(tr)
	var nxt_name := str(nxt.get("name", ""))
	if spd < 0.3:
		if float(tr.get("merge_hold_s", -1.0)) >= 0.0:
			return "汇合让行"
		if _terminal_hold_distance(tr) < 40.0:
			return "等待终点站进站 → %s" % nxt_name if nxt_name != "" else "等待终点站进站"
		return "停车等待 → %s" % nxt_name if nxt_name != "" else "停车等待"
	return "开往 %s" % nxt_name if nxt_name != "" else "运行中"


func line_tram_indices(lid: int) -> Array:
	var out: Array = []
	for i in range(trams.size()):
		if int(trams[i]["line_id"]) == lid:
			out.append(i)
	return out


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
	_switch_timer -= dt
	if _switch_timer <= 0.0:
		_switch_timer = 0.25
		_update_monorail_switches(graph)
		_update_merge_yields()
	if graph != null and graph.has_meta("monorail_switches"):
		for sw_n in graph.get_meta("monorail_switches"):
			if is_instance_valid(sw_n):
				sw_n.call("advance", dt)

	for i in range(trams.size()):
		var tr: Dictionary = trams[i]
		var is_player_manual := (i == active_tram_idx and manual_drive)
		if i == active_tram_idx and bool(tr.get("held_manual", false)) and (not manual_drive or float(tr["speed_mps"]) > 0.5):
			tr["held_manual"] = false # the player drove off (or handed it to the AI): no longer held
		var is_held := i != active_tram_idx and bool(tr.get("held_manual", false))

		if is_held:
			tr["notch"] = 3 # held in manual by the player: stands with the brakes on, no AI driving
		elif not is_player_manual:
			tr["reverser"] = 1.0
			_step_ai_driver(tr, i, dt, graph, pax_sim, traffic_sim, sound, i == active_tram_idx)

		var derail_ev := _step_tram_physics_and_doors(tr, i, dt, graph, pax_sim, sound, i == active_tram_idx, is_player_manual)
		_accumulate_tram_stats(tr, dt)
		_clear_wrong_track(tr)
		if derail_ev.is_empty() and is_player_manual:
			derail_ev = _check_switch_entry(tr, i)
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


# Reverser (方向手柄): forward / R. Only changed at a standstill; reverse runs the train backwards along its
# route (rear cab end leading) at shunting speed. AI driving always runs forward.
const REVERSE_MAX_KMH := 15.0

# Keep a stopped, manually driven train in manual: once the player switches to another train it stands where
# it is (brakes on, no AI) until the player comes back to it and drives on.
func manual_toggle_hold() -> String:
	var tr := get_active_tram()
	if tr.is_empty():
		return "no_tram"
	if bool(tr.get("held_manual", false)):
		tr["held_manual"] = false
		return "released"
	if not manual_drive:
		return "not_manual"
	if float(tr["speed_mps"]) >= 0.15:
		return "moving"
	tr["held_manual"] = true
	tr["notch"] = 3
	return "held"


# Coming back to a held train: the player drives it again (manual), and the hold has done its job
func _on_active_changed() -> void:
	var tr := get_active_tram()
	if not tr.is_empty() and bool(tr.get("held_manual", false)):
		tr["held_manual"] = false
		manual_drive = true


func manual_toggle_reverser() -> String:
	var tr := get_active_tram()
	if tr.is_empty():
		return "no_tram"
	if float(tr["speed_mps"]) >= 0.15:
		return "moving"
	manual_drive = true
	tr["reverser"] = -1.0 if float(tr.get("reverser", 1.0)) > 0.0 else 1.0
	tr["notch"] = NOTCH_NEUTRAL
	return "reverse" if float(tr["reverser"]) < 0.0 else "forward"


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
	var st_right := st_fwd.cross(Vector3.UP).normalized()
	if eid >= 0 and graph.is_quad(eid):
		if int(st_side) == 0:
			# Twin islands: the one beside this train's track (express and local of a direction share it)
			var secs: Array = tr["tram_info"]["sections"]
			var lat := 1.0
			if not secs.is_empty():
				lat = signf((secs[0] as Node3D).global_position.dot(st_right) - st_pos.dot(st_right))
			st_pos += st_right * ((lat if lat != 0.0 else 1.0) * NetworkGraph.QUAD_ISLAND_CENTER)
		else:
			st_pos += st_right * (st_side * NetworkGraph.QUAD_LOCAL_HALF_SEP)
	elif eid >= 0 and graph.is_multi_track(eid):
		st_pos += st_right * (st_side * NetworkGraph.DOUBLE_TRACK_HALF_SEP)
	return {
		"has_station": true,
		"station_id": sid,
		"stop_idx": int(near["stop_idx"]),
		"st_pos": st_pos,
		"st_fwd": st_fwd,
		"st_side": st_side,
		"plat_half_len": float(st.get("platform_len", 27.0)) * 0.5 - 0.45,
	}


# Driver's cab change ("换端"): walk to the other cab and drive back the way you came.
# Returns "ok" on success, otherwise a reason code: "moving", "doors", "pax_onboard", "not_terminal", "no_tram".
func manual_reverse_dir() -> String:
	var tr := get_active_tram()
	if tr.is_empty():
		return "no_tram"
	if float(tr["speed_mps"]) >= 0.15:
		return "moving"
	if float(tr["door_ratio"]) >= 0.05 or bool(tr.get("doors_target_open", false)):
		return "doors"
	var near := _find_station_at_current_pos(tr)
	var near_sid := int(near["station_id"])
	var at_turnback := _is_turnback_stop(tr, int(near["stop_idx"]))
	if at_turnback and not (tr["pax_dests"] as Array).is_empty():
		return "pax_onboard"
	if bool(tr["is_loop"]):
		# Loop lines are compiled with terminal turnbacks: the cab can only be changed at a terminal
		# (anywhere on the platform / tail track before the turnback point).
		if _try_turnback_flip(tr, 60.0, near_sid >= 0):
			manual_drive = true
			tr["notch"] = NOTCH_NEUTRAL
			if near_sid >= 0:
				tr["term_stage"] = "board_only"
				tr["term_sid"] = near_sid
			return "ok"
		return "not_terminal"
	manual_drive = true
	tr["notch"] = NOTCH_NEUTRAL
	_reverse_tram_switch_cab(tr)
	if near_sid >= 0 and at_turnback:
		tr["term_stage"] = "board_only"
		tr["term_sid"] = near_sid
	return "ok"


# True when the train stands on the departure side of terminal `sid` (past the turnback point, facing out)
func _on_terminal_departure_side(tr: Dictionary, sid: int) -> bool:
	if not bool(tr["is_loop"]):
		return false
	var rlen := float(tr["route_len"])
	var dir := float(tr["dir"])
	var s_now := float(tr["s"])
	for z: Dictionary in tr.get("terminal_zones", []):
		if int(z["station_id"]) != sid:
			continue
		var cusp_s := float(z["cusp_s"])
		var arr_len := fposmod((cusp_s - float(z["hold_s"])) * dir, rlen)
		var from_hold := fposmod((s_now - float(z["hold_s"])) * dir, rlen)
		if from_hold <= arr_len + 0.5:
			return false
		var dep_len := fposmod((float(z["exit_s"]) - cusp_s) * dir, rlen) + _consist_length(tr)
		return fposmod((s_now - cusp_s) * dir, rlen) <= dep_len
	return false


# True when stop `stop_idx` is a reversing terminus (either a double-track/monorail turnback cusp
# or the forward end station of a single-track shuttle). Pure circular loops return false.
func _is_turnback_stop(tr: Dictionary, stop_idx: int) -> bool:
	var stops: Array = tr.get("stops", [])
	if stop_idx < 0 or stop_idx >= stops.size():
		return false
	if bool(tr["is_loop"]):
		return bool((stops[stop_idx] as Dictionary).get("turnback", false))
	var dir := float(tr["dir"])
	return (dir > 0.0 and stop_idx == stops.size() - 1) or (dir < 0.0 and stop_idx == 0)


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
func _try_turnback_flip(tr: Dictionary, reach: float = 30.0, keep_dwell: bool = false) -> bool:
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
			res[int(z["station_id"])] = {"platform": int(z["platform"]), "phase": "dwell" if keep_dwell else "out"}
			_position_tram_3d(tr)
			return true
	return false


func _reverse_tram_switch_cab(tr: Dictionary) -> void:
	tr["sw_pending"] = {}
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
	# Standing on the departure side of a terminal (after the cab change, or at the start of a run): measure
	# against the mirrored stopping position, so a perfectly placed train reads 0 m
	if is_loop and float(tr["speed_mps"]) < 0.3:
		for i0 in range(stops.size()):
			var st0: Dictionary = stops[i0]
			if not bool(st0.get("turnback", false)) or not _on_terminal_departure_side(tr, int(st0["station_id"])):
				continue
			var dep_s := _departure_spawn_s(st0, _consist_length(tr), rlen)
			var dd := fposmod((s_now - dep_s) * dir + rlen * 0.5, rlen) - rlen * 0.5
			if absf(dd) < 40.0:
				return {"station_id": int(st0["station_id"]), "name": str(st0["name"]), "signed_dist": dd, "stop_idx": i0}
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
			var st_d: Dictionary = stops[idx]
			out.append(int(st_d["station_id"]))
			# On bidirectional turnback routes (double-track tram & monorail), passengers must alight
			# by the reversing terminus — never assign destinations across a turnback!
			if bool(st_d.get("turnback", false)):
				break
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
	var term_stage := str(tr.get("term_stage", ""))
	if target_open or door_r > 0.02 or depart_pending or term_stage == "flip_wait":
		tr["notch"] = 3
		if term_stage == "flip_wait":
			# Brief realistic cab-change pause with doors closed after reversing ends, then open doors for return boarding!
			var ft := float(tr.get("term_flip_timer", 0.0)) - dt
			tr["term_flip_timer"] = ft
			if ft <= 0.0:
				tr["term_stage"] = "board_only"
				tr["doors_target_open"] = true
				tr["dwell_timer"] = 4.2
				tr["dwell_elapsed"] = 0.0
				if play_audio:
					sound.play_door_chime()
			return

		tr["dwell_timer"] = float(tr["dwell_timer"]) - dt
		tr["dwell_elapsed"] = float(tr.get("dwell_elapsed", 0.0)) + dt
		var docked_now := _find_station_at_current_pos(tr)
		var docked_sid := int(docked_now["station_id"])
		var has_room := ((tr["pax_dests"] as Array).size() + int(tr.get("pending_boarders", 0))) < int(tr["capacity"])
		var more_waiting := (docked_sid >= 0) and has_room and pax_sim.has_waiting_passengers(docked_sid)
		var walkers_still_boarding := pax_sim.has_walkers_boarding_tram(tr)

		var can_close := false
		if term_stage == "alight_only":
			# Phase 1 at reversing terminus: MUST evacuate 100% of onboard passengers (只下不上) before cab change!
			var onboard_left := (tr["pax_dests"] as Array).size()
			var doors_blocked := (door_r > 0.55 and int(tr.get("open_doorways", 0)) == 0)
			can_close = (float(tr["dwell_timer"]) <= 0.0) and (onboard_left == 0 or doors_blocked or float(tr["dwell_elapsed"]) >= 50.0)
		else:
			can_close = (float(tr["dwell_timer"]) <= 0.0) and ((not more_waiting and not walkers_still_boarding) or float(tr["dwell_elapsed"]) >= 16.0)

		if can_close and target_open:
			tr["doors_target_open"] = false
			tr["ai_depart_pending"] = true # Act once doors are shut (frame-rate independent)
			if play_audio:
				sound.play_door_chime()
		elif not target_open and door_r <= 0.03:
			var docked := _find_station_at_current_pos(tr)
			var stops: Array = tr["stops"]
			var d_idx := int(docked["stop_idx"])
			var d_sid := int(docked["station_id"])

			# End of Phase 1 ("alight_only"): doors shut with empty train -> change cab, pause briefly, then open for Phase 2 ("board_only")!
			if term_stage == "alight_only":
				var t_sid := int(tr.get("term_sid", d_sid))
				if t_sid < 0:
					t_sid = d_sid
				var flipped := false
				if not bool(tr["is_loop"]):
					_reverse_tram_switch_cab(tr)
					flipped = true
				else:
					flipped = _try_turnback_flip(tr, 40.0, true)
				tr["ai_depart_pending"] = false
				if flipped:
					tr["term_sid"] = t_sid
					tr["term_stage"] = "flip_wait"
					tr["term_flip_timer"] = 0.85
					return
				# Fallback if not actually near a turnback cusp: continue departure normally
				tr["term_stage"] = ""
				tr["term_sid"] = -1

			var dep_sid := int(tr.get("term_sid", d_sid))
			if dep_sid < 0:
				dep_sid = d_sid
			if bool(tr["is_loop"]) and dep_sid >= 0 and _terminal_departure_blocked(tr, dep_sid):
				tr["notch"] = 3 # Hold at the platform: a tram is crossing over into the other platform track
				return
			if _holding_for_express(tr, my_idx, d_sid, graph, dt):
				tr["notch"] = 3 # Four-track stop: let the express go first / overtake
				return
			tr["ai_depart_pending"] = false
			if term_stage == "board_only":
				# End of Phase 2 ("board_only"): mark terminal reservation as departing ("out") and leave!
				var res_d: Dictionary = tr["term_res"]
				if dep_sid >= 0 and res_d.has(dep_sid):
					(res_d[dep_sid] as Dictionary)["phase"] = "out"
				tr["term_stage"] = ""
				tr["term_sid"] = -1
			else:
				# Non-turnback or edge-end fallback (e.g. stopped past last stop on open line)
				var dir_now := float(tr["dir"])
				var s_cur := float(tr["s"])
				var rlen_cur := float(tr["route_len"])
				if not bool(tr["is_loop"]):
					var near_end := (dir_now > 0.0 and s_cur >= rlen_cur - 6.0) or (dir_now < 0.0 and s_cur <= 6.0)
					if near_end:
						_reverse_tram_switch_cab(tr)
			if play_audio:
				sound.ring_bell()
			tr["depart_cooldown"] = 8.5
			# Release holding brake cleanly to P1 on departure, then step up smoothly P1 -> P2 -> P3
			tr["notch"] = NOTCH_NEUTRAL + 1
			tr["ai_notch_timer"] = 0.0
			tr["ai_last_step_dir"] = 1
			tr["ai_cruising_coast"] = false
			tr["ai_crawl_active"] = false
		return

	var spec: Dictionary = tr["spec"]
	var max_decel := maxf(0.6, float(spec.get("decel", 1.35)))
	var drag_est := 0.045 + 0.0012 * spd * spd
	var cur_notch := int(tr["notch"])

	# Unified forward-constraint evaluation (never falls through from braking to cruise acceleration!)
	var must_hold_stop := false
	var hard_stop_ahead := false
	var approaching_station := false
	var req_decel := 0.0
	var v_env := 99.0
	var brake_urgency := 0 # 0 = smooth, 1 = firm safety brake, 2 = emergency immediate

	# 0. Terminal interlocking & monorail switch signal
	var term_hold_d := minf(minf(_terminal_hold_distance(tr), _switch_hold_distance(tr)), _merge_hold_distance(tr))
	if term_hold_d < 1e8:
		if term_hold_d <= 1.4:
			must_hold_stop = true
		else:
			var d_th := maxf(0.4, term_hold_d - 1.2)
			v_env = minf(v_env, sqrt(2.0 * max_decel * 0.62 * d_th))
			if term_hold_d < 70.0:
				var a_th := (spd * spd) / (2.0 * d_th)
				if a_th > req_decel:
					req_decel = a_th
				if a_th > max_decel * 0.45:
					brake_urgency = maxi(brake_urgency, 1)
				if term_hold_d < 45.0:
					hard_stop_ahead = true

	# 1. Tram ahead on path: brake smoothly to stop ~9m behind it
	var gap_ahead := _distance_to_tram_ahead(tr, my_idx)
	if gap_ahead < 900.0:
		var gap_room := gap_ahead - 9.0
		if gap_room <= 1.0:
			must_hold_stop = true
		else:
			var d_gap := maxf(0.5, gap_room)
			var safe_v := sqrt(2.0 * max_decel * 0.56 * d_gap)
			v_env = minf(v_env, safe_v)
			if gap_room < 12.0 and spd > safe_v + 2.4:
				_apply_ai_notch_command(tr, 0, dt, 2) # Immediate EB if critically closing on tram ahead
				return
			var a_gap := (spd * spd) / (2.0 * d_gap)
			if gap_room < 85.0 and a_gap > req_decel:
				req_decel = a_gap
			if a_gap > max_decel * 0.48:
				brake_urgency = maxi(brake_urgency, 1)
			if gap_room < 42.0:
				hard_stop_ahead = true

	# 2. Dedicated Tram Signal ('━' Stop / '●' Yellow) + Road Hazard Emergency Avoidance
	var intersection_cap_mps := 99.0
	if traffic_sim != null:
		var sig_info := traffic_sim.get_upcoming_tram_signal(tr, graph)
		if bool(sig_info["has_signal"]):
			var sig_d := float(sig_info["dist"])
			var stop_line := float(sig_info.get("stop_line", 11.2))
			if str(sig_info["aspect"]) != "green":
				if sig_d >= stop_line - 1.4 and sig_d <= 62.0:
					var d_to_stop_line := sig_d - stop_line
					if d_to_stop_line <= 2.3:
						must_hold_stop = true
					else:
						var d_sig := maxf(0.5, d_to_stop_line - 1.5)
						v_env = minf(v_env, sqrt(2.0 * max_decel * 0.64 * d_sig))
						var a_sig := (spd * spd) / (2.0 * d_sig)
						if a_sig > req_decel:
							req_decel = a_sig
						if a_sig > max_decel * 0.45 or d_to_stop_line < 16.0:
							brake_urgency = maxi(brake_urgency, 1)
						if d_to_stop_line < 42.0:
							hard_stop_ahead = true
			elif sig_d > stop_line and sig_d <= 44.0:
				# Smooth defensive intersection approach cap (26 km/h)
				intersection_cap_mps = 26.0 / 3.6
			elif sig_d > 44.0 and sig_d <= 72.0:
				# Gently ramp down envelope before the 44m intersection zone so we coast instead of brake-chattering
				var d_int := maxf(1.0, sig_d - 42.0)
				var v_int := 26.0 / 3.6
				v_env = minf(v_env, sqrt(v_int * v_int + 2.0 * max_decel * 0.35 * d_int))

		var haz := traffic_sim.find_hazard_along_tram_curve(tr, 48.0)
		if bool(haz["has_hazard"]):
			var hd := float(haz["dist"])
			var eb_dist := maxf(24.0, (spd * spd) / 4.8 + 8.0)
			if hd < eb_dist:
				tr["ai_eb_hold"] = 0.75
				_apply_ai_notch_command(tr, 0, dt, 2) # Full Electromagnetic Track-Brake EB!
				if hd < 9.5:
					tr["speed_mps"] = move_toward(spd, 0.0, 14.0 * dt)
				elif spd < 0.45:
					tr["speed_mps"] = 0.0
				return
			elif hd < 46.0:
				var d_hz := maxf(0.5, hd - 11.0)
				v_env = minf(v_env, sqrt(2.0 * 1.15 * d_hz))
				var a_hz := (spd * spd) / (2.0 * d_hz)
				if a_hz > req_decel:
					req_decel = a_hz
				brake_urgency = maxi(brake_urgency, 1)
				hard_stop_ahead = true

	# Hold EB briefly after an emergency hazard trigger so flickering traffic never chatters EB <-> B1
	var eb_hold := float(tr.get("ai_eb_hold", 0.0))
	if eb_hold > 0.0:
		tr["ai_eb_hold"] = maxf(0.0, eb_hold - dt)
		if cur_notch == 0 and spd > 0.25:
			tr["ai_notch_timer"] = 0.0
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

	if float(tr["depart_cooldown"]) <= 0.0 and ((dist_ahead <= 3.8 and spd < 0.55) or (at_track_end and spd < 0.35)):
		tr["speed_mps"] = 0.0
		tr["notch"] = 3 # Steady B2 platform holding brake
		tr["ai_notch_timer"] = 0.0
		tr["ai_cruising_coast"] = true
		tr["ai_crawl_active"] = false
		var arrived_st := _find_station_at_current_pos(tr)
		var arr_idx := int(arrived_st["stop_idx"])
		var arr_sid := int(arrived_st["station_id"])
		if _is_turnback_stop(tr, arr_idx):
			tr["term_stage"] = "alight_only"
			tr["term_sid"] = arr_sid
			tr["dwell_timer"] = 1.8 if (tr["pax_dests"] as Array).is_empty() else 2.4
		else:
			tr["term_stage"] = ""
			tr["term_sid"] = -1
			tr["dwell_timer"] = 4.6
		tr["doors_target_open"] = true
		tr["dwell_elapsed"] = 0.0
		if play_audio:
			sound.play_door_chime()
		return

	# Hard hold at red signal / terminal interlocking / tram ahead
	if must_hold_stop:
		tr["ai_cruising_coast"] = true
		tr["ai_crawl_active"] = false
		if spd < 0.55:
			tr["speed_mps"] = 0.0
			_apply_ai_notch_command(tr, 3, dt, 0) # Calm B2 holding brake once stopped
		else:
			_apply_ai_notch_command(tr, 1 if spd > 1.8 else 2, dt, 1)
		return

	# 3. Proactive Curve/Turnout & Intersection Speed Limits
	var lim_info := get_speed_limit_status(tr)
	var allowed_mps := minf((float(lim_info["limit_kmh"]) - 2.8) / 3.6, intersection_cap_mps)
	var next_lim_mps := (float(lim_info["next_limit_kmh"]) - 2.8) / 3.6
	var next_lim_dist := float(lim_info["next_dist_m"])
	var coast_for_upcoming_limit := false
	if next_lim_dist < 120.0 and next_lim_mps < allowed_mps:
		var d_lim := maxf(2.0, next_lim_dist - 10.0)
		var v_lim_env := sqrt(next_lim_mps * next_lim_mps + 2.0 * max_decel * 0.48 * d_lim)
		v_env = minf(v_env, v_lim_env)
		if spd > next_lim_mps + 0.2:
			var a_lim := (spd * spd - next_lim_mps * next_lim_mps) / (2.0 * d_lim)
			if a_lim > req_decel:
				req_decel = a_lim
			if a_lim > max_decel * 0.50:
				brake_urgency = maxi(brake_urgency, 1)
		if next_lim_dist < 42.0 and spd >= next_lim_mps - 0.6:
			coast_for_upcoming_limit = true

	if spd > allowed_mps + 0.35:
		var over_v := spd - allowed_mps
		var a_over := clampf(over_v * 0.55, max_decel * 0.28, max_decel)
		if a_over > req_decel:
			req_decel = a_over
		if over_v > 0.7:
			brake_urgency = maxi(brake_urgency, 1)

	# 4. Station Approach Braking Curve (smooth service braking + gentle final ease-off)
	var station_final_stop := false
	if float(tr["depart_cooldown"]) <= 0.0 and dist_ahead < 95.0:
		var d_st := maxf(0.6, dist_ahead - 1.0)
		var v_st_env := sqrt(2.0 * max_decel * 0.48 * d_st)
		v_env = minf(v_env, v_st_env)
		var a_st := (spd * spd) / (2.0 * d_st)
		if dist_ahead <= 2.4:
			station_final_stop = true
			approaching_station = true
		elif a_st > max_decel * 0.17 or dist_ahead < (spd * spd) / maxf(0.4, 2.0 * max_decel * 0.46) + 9.0:
			approaching_station = true
			if a_st > req_decel:
				req_decel = a_st
			if a_st > max_decel * 0.65:
				brake_urgency = maxi(brake_urgency, 1)

	# 5. Select Steady Desired Notch with Non-Overlapping Hysteresis (Real Tram Power -> Coast -> Step-Brake Behavior)
	var desired_notch := NOTCH_NEUTRAL
	var cmd_urgency := brake_urgency

	if station_final_stop:
		tr["ai_cruising_coast"] = true
		tr["ai_crawl_active"] = false
		desired_notch = 2 if spd > 2.2 else 3 # Smooth B2 stop right onto the platform mark
		cmd_urgency = maxi(cmd_urgency, 1 if spd > 2.2 else 0)
	elif req_decel > max_decel * 0.22 or (cur_notch < NOTCH_NEUTRAL and req_decel > max_decel * 0.05):
		# Active proportional service braking with strict non-overlapping release thresholds
		# so easing off a brake notch NEVER immediately bounces back into the stronger notch!
		tr["ai_cruising_coast"] = true
		tr["ai_crawl_active"] = false
		var net_req := maxf(0.0, req_decel - drag_est * 0.65)
		var ratio := net_req / max_decel
		var ideal_b := 4 # B1
		if ratio >= 0.88:
			ideal_b = 1 # B4
		elif ratio >= 0.62:
			ideal_b = 2 # B3
		elif ratio >= 0.36:
			ideal_b = 3 # B2
		else:
			ideal_b = 4 # B1

		if cur_notch >= 1 and cur_notch <= 4:
			# Current brake notch: only strengthen if demand exceeds this notch's capacity;
			# only release if demand has dropped well below the WEAKER notch's capacity!
			var cur_eff := float(NOTCH_NEUTRAL - cur_notch) * 0.25 * max_decel + drag_est * 0.65
			var release_thresh := 0.05 * max_decel
			if cur_notch == 1:
				release_thresh = 0.64 * max_decel # B4 -> B3 only once B3 can easily handle it
			elif cur_notch == 2:
				release_thresh = 0.39 * max_decel # B3 -> B2 only once B2 can easily handle it
			elif cur_notch == 3:
				release_thresh = 0.16 * max_decel # B2 -> B1 only once B1 can easily handle it
			if req_decel > cur_eff + max_decel * 0.12:
				desired_notch = mini(cur_notch - 1, ideal_b)
			elif req_decel < release_thresh and not (approaching_station and dist_ahead < 10.0):
				desired_notch = cur_notch + 1
				cmd_urgency = 0 # Brake release is always calm
			else:
				desired_notch = cur_notch
		else:
			desired_notch = ideal_b
	else:
		# Not actively braking -> check short-station crawl vs. Power-and-Coast cruising
		var base_cruise := minf(float(spec.get("max_speed_kmh", 70)) * 0.68, 48.0) / 3.6
		if bool(tr.get("elevated", false)):
			base_cruise = float(spec.get("max_speed_kmh", 70)) * 0.9 / 3.6 # grade-separated: no street traffic to mind
		var target_mps := minf(base_cruise, minf(allowed_mps, v_env))

		if (approaching_station or (float(tr["depart_cooldown"]) <= 0.0 and dist_ahead < 22.0)) and not hard_stop_ahead:
			# Stopped slightly short of the platform mark: gentle single P1 crawl with hysteresis latch
			var crawling := bool(tr.get("ai_crawl_active", false))
			if not crawling and spd < 0.85 and dist_ahead > 3.6:
				crawling = true
			elif crawling and (spd >= 1.85 or dist_ahead <= 3.1):
				crawling = false
			tr["ai_crawl_active"] = crawling
			desired_notch = (NOTCH_NEUTRAL + 1) if crawling else NOTCH_NEUTRAL
		else:
			tr["ai_crawl_active"] = false
			var coasting := bool(tr.get("ai_cruising_coast", false))
			# Wide ~5.0 km/h coasting deadband: accelerate to cruise speed, then coast calmly in N!
			if hard_stop_ahead or coast_for_upcoming_limit or spd >= target_mps - 0.15 or target_mps < 1.2:
				coasting = true
			elif spd < target_mps - 1.40:
				coasting = false
			tr["ai_cruising_coast"] = coasting

			if coasting:
				desired_notch = NOTCH_NEUTRAL
			else:
				var dv := target_mps - spd
				if cur_notch >= 6 and cur_notch <= 8:
					# Power-notch hysteresis so P3 -> P2 -> P1 steps down smoothly as speed approaches cruise
					if cur_notch == 8:
						desired_notch = 8 if dv > 2.2 else 7
					elif cur_notch == 7:
						if dv > 3.5:
							desired_notch = 8
						elif dv < 0.9:
							desired_notch = 6
						else:
							desired_notch = 7
					else:
						desired_notch = 7 if dv > 1.9 else 6
				else:
					if dv > 3.0:
						desired_notch = 8 # P3 (stepped up via P1 -> P2 -> P3 by rate limiter)
					elif dv > 1.3:
						desired_notch = 7 # P2
					else:
						desired_notch = 6 # P1

	_apply_ai_notch_command(tr, desired_notch, dt, cmd_urgency)


func _apply_ai_notch_command(tr: Dictionary, desired_notch: int, dt: float, urgency: int) -> void:
	var cur := int(tr["notch"])
	var timer := float(tr.get("ai_notch_timer", 1.0)) + dt
	tr["ai_notch_timer"] = timer
	var clamped_target := clampi(desired_notch, 0, NOTCH_LABELS.size() - 1)
	if clamped_target == cur:
		return

	var step_dir := 1 if clamped_target > cur else -1
	# Emergency Brake (EB) only: apply immediately without rate limit
	if urgency >= 2:
		tr["notch"] = clamped_target
		tr["ai_notch_timer"] = 0.0
		tr["ai_last_step_dir"] = step_dir
		return

	var last_dir := int(tr.get("ai_last_step_dir", 0))
	var is_reversal := (last_dir != 0 and step_dir != last_dir)
	var min_wait := 0.55 # Calm, realistic ~0.55s per notch step during normal driving
	if urgency == 1 and step_dir < 0:
		# Active safety braking: crisp 0.35s per notch step (or 0.65s if just reversed)
		min_wait = 0.65 if is_reversal else 0.35
	elif is_reversal:
		# Prevent back-and-forth chatter: require a full 1.10s human dwell before reversing lever direction
		min_wait = 1.10

	if timer < min_wait:
		return

	var next_n := cur + step_dir
	# Like a real master controller detent, cutting Power off to Coast/Brake pulls cleanly to Neutral (N) in one motion
	if cur > NOTCH_NEUTRAL and clamped_target <= NOTCH_NEUTRAL:
		next_n = NOTCH_NEUTRAL

	tr["notch"] = clampi(next_n, 0, NOTCH_LABELS.size() - 1)
	tr["ai_notch_timer"] = 0.0
	tr["ai_last_step_dir"] = step_dir


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
		var dock_sid := int(dock_info["station_id"])
		var dock_idx := int(dock_info["stop_idx"])
		if dock_sid >= 0:
			var stage_now := str(tr.get("term_stage", ""))
			# In manual mode, opening doors at a reversing terminus before cab change enters Phase 1 ("alight_only")
			if stage_now == "" and _is_turnback_stop(tr, dock_idx):
				# Already past the turnback (e.g. the start of a run, standing at the origin platform facing out):
				# this is the starting station, so board; otherwise it is the arrival end, so clear the train first
				stage_now = "board_only" if _on_terminal_departure_side(tr, dock_sid) else "alight_only"
				tr["term_stage"] = stage_now
				tr["term_sid"] = dock_sid
			if stage_now == "alight_only":
				# Phase 1: ONLY alight (evacuate 100% of passengers), NO boarding before cab change!
				pax_sim.exchange_passengers_at_station(tr, dock_sid, [], dt, true, false, true)
			elif stage_now == "board_only":
				# Phase 2 (after cab change): ONLY board new passengers for the return trip!
				var upcoming_b := get_upcoming_station_ids(tr, dock_idx)
				pax_sim.exchange_passengers_at_station(tr, dock_sid, upcoming_b, dt, false, true, false)
			else:
				var upcoming := get_upcoming_station_ids(tr, dock_idx)
				pax_sim.exchange_passengers_at_station(tr, dock_sid, upcoming, dt, true, true, false)
	elif float(tr["speed_mps"]) > 0.25 and str(tr.get("term_stage", "")) != "":
		# Manual driver pulled out of the terminal: transition reservation to "out" and clear terminal stage
		var prev_tsid := int(tr.get("term_sid", -1))
		var res_m: Dictionary = tr["term_res"]
		if prev_tsid >= 0 and res_m.has(prev_tsid):
			(res_m[prev_tsid] as Dictionary)["phase"] = "out"
		tr["term_stage"] = ""
		tr["term_sid"] = -1

	var spec: Dictionary = tr["spec"]
	var max_spd_mps := float(spec.get("max_speed_kmh", 70)) / 3.6
	var rev := float(tr.get("reverser", 1.0))
	if rev < 0.0:
		max_spd_mps = REVERSE_MAX_KMH / 3.6
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
	var mv := dir * rev # actual travel direction along s (reverse gear: backwards)
	var ds := spd * mv * dt
	var s_prev := float(tr["s"])
	var s_new := s_prev + ds
	var lid_dist := int(tr["line_id"])
	line_dist_m[lid_dist] = float(line_dist_m.get(lid_dist, 0.0)) + absf(ds)
	tr["st_dist_m"] = float(tr.get("st_dist_m", 0.0)) + absf(ds)

	if bool(tr["is_loop"]):
		s_new = fposmod(s_new, rlen)
		# Buffer stop at the end of a terminal tail track: the route only continues past the turnback
		# point after a cab change, so a tram (manually driven or not) can never run through it.
		if ds != 0.0:
			# Reversing, the rear end leads: it is what reaches the turnback point / buffer
			var lead_off := 0.0 if rev > 0.0 else -dir * _consist_length(tr)
			for z: Dictionary in tr.get("terminal_zones", []):
				var cusp := float(z["cusp_s"])
				var d_prev := fposmod((cusp - (s_prev + lead_off)) * mv, rlen)
				if d_prev > 0.5 and d_prev < 40.0 and absf(ds) >= d_prev - 0.5:
					s_new = fposmod(cusp - mv * 0.5 - lead_off, rlen)
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
			btn_rev.rotation.y = lerpf(btn_rev.rotation.y, deg_to_rad(32.0 if rev > 0.0 else -32.0), minf(1.0, dt * 12.0))
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

	# During post-flip terminal boarding ("board_only" / "flip_wait"), keep locked to the exact terminal stop
	var t_stage := str(tr.get("term_stage", ""))
	var t_sid := int(tr.get("term_sid", -1))
	if (t_stage == "board_only" or t_stage == "flip_wait") and t_sid >= 0:
		for i in range(stops.size()):
			if int(stops[i]["station_id"]) == t_sid:
				return {"station_id": t_sid, "stop_idx": i}

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

static func _variant_key(b_sids: Dictionary, w_sids: Dictionary = {}) -> String:
	var ks: Array = b_sids.keys()
	ks.sort()
	var parts: PackedStringArray = []
	for k in ks:
		parts.append(str(k))
	var ws: Array = w_sids.keys()
	ws.sort()
	for k in ws:
		parts.append("w%d" % int(k))
	return ",".join(parts)


# Compiled route for a variant key (platform B choices + "w<sid>" wrong-track departures); wrong-track ones
# are compiled the first time a driver needs them
func _get_variant(lid: int, key: String) -> Dictionary:
	var variants: Dictionary = line_variants.get(lid, {})
	if variants.has(key):
		return variants[key]
	if _graph_ref == null or not _graph_ref.lines.has(lid):
		return {}
	var b := {}
	var w := {}
	for part in key.split(",", false):
		if part.begins_with("w"):
			w[int(part.substr(1))] = true
		else:
			b[int(part)] = true
	var c := _graph_ref.compile_line_route(_graph_ref.lines[lid], b, w)
	if not c.is_empty():
		variants[key] = c
		line_variants[lid] = variants
	return c


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
	tr["sw_pending"] = {}
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
	var w_sids := {}
	for part in key.split(",", false):
		if part.begins_with("w"):
			w_sids[int(part.substr(1))] = true
		else:
			b_sids[int(part)] = true
	tr["b_sids"] = b_sids
	tr["w_sids"] = w_sids


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
	var key := _variant_key(b_sids, tr.get("w_sids", {}))
	if key == str(tr.get("variant_key", "")):
		return
	var v_route := _get_variant(int(tr["line_id"]), key)
	if v_route.is_empty():
		return
	var old_z := _zone_for(tr, sid)
	var dir := float(tr["dir"])
	var d_before_hold := fposmod((float(old_z["hold_s"]) - float(tr["s"])) * dir, float(tr["route_len"]))
	_apply_route_variant(tr, v_route, key)
	var new_z := _zone_for(tr, sid)
	tr["s"] = fposmod(float(new_z["hold_s"]) - dir * d_before_hold, float(tr["route_len"]))
	_position_tram_3d(tr)


func _terminal_occupancy(my_idx: int, _line_id: int, sid: int) -> Dictionary:
	var occ := {"a": false, "b": false, "a_out": false, "b_in": false}
	for j in range(trams.size()):
		# Every line turning back at this station shares its two platform tracks (not just this line's trains)
		if j == my_idx or bool(trams[j].get("elevated", false)) != bool(trams[my_idx].get("elevated", false)):
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
			# A departing train only cuts across the way into platform B once it is actually moving; while it
			# still stands at A, the arriving train may take B (and the departure waits for it, see below)
			if str(r["phase"]) == "out" and float(trams[j]["speed_mps"]) > 0.3:
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
			if can_b and not (tr.get("w_sids", {}) as Dictionary).is_empty():
				pick = PLATFORM_B # arriving on the wrong track: platform B lies straight ahead
			elif can_a:
				pick = PLATFORM_A
			elif can_b:
				pick = PLATFORM_B
			if pick < 0:
				tr["term_hold_s"] = hold_s # Both platform tracks busy: wait before the crossover
				continue
			res[sid] = {"platform": pick, "phase": "in"}
			_switch_terminal_platform(tr, sid, pick)
		tr["term_init_done"] = true



# ---------------------------------------------------------------------------------------------
# Monorail switch interlocking. Each crossover is two moving half-beams (monorail_switch.gd) protected
# by four signals. A switch is reserved by one train at a time (the nearest ready train whose route runs
# through it), thrown automatically for that train's planned route (AI and manual driving alike), and only
# then is that train's entry signal cleared. Other trains stop at their red signal. A manual driver can
# still throw it by hand with G for special cases (manual_override), which automatic setting respects.
# ---------------------------------------------------------------------------------------------
const SW_SCAN_AHEAD := 170.0
const SW_SIGNAL_BACK := 12.0 # stop point: 2 m before the signal mast, which stands 10 m before the span

func _sw_ready(tr: Dictionary) -> bool:
	if bool(tr.get("derailed", false)) or bool(tr.get("crashed", false)):
		return false
	if bool(tr["doors_target_open"]) or float(tr["door_ratio"]) > 0.02 or bool(tr.get("ai_depart_pending", false)):
		return false
	var t_st := str(tr.get("term_stage", ""))
	if t_st == "alight_only" or t_st == "flip_wait" or t_st == "board_only":
		return false
	return _terminal_hold_distance(tr) >= 1e8


# Where this train's route meets each switch: {sw, need (0 straight / 1 crossover), entry (signal index),
# d_entry (m ahead of the head, <=0 once inside), s_entry (route s of the entry point)}. Nearest first.
func _scan_switches(tr: Dictionary, switches: Array, ahead: float = SW_SCAN_AHEAD) -> Array:
	var out: Array = []
	var curve: Curve3D = tr["curve"]
	var rlen := float(tr["route_len"])
	var is_loop := bool(tr["is_loop"])
	var dir := float(tr["dir"])
	var s0 := float(tr["s"])
	var back := _consist_length(tr) + 1.5
	var cands: Array = []
	var head := curve.sample_baked(s0, false)
	var my_sys := 1 if bool(tr.get("elevated", false)) else 0
	for sw in switches:
		if is_instance_valid(sw) and int(sw.system) == my_sys and Vector2(head.x - sw.diverge_mid.x, head.z - sw.diverge_mid.z).length() < ahead + 80.0:
			cands.append({"sw": sw, "need": -1.0, "entry": -1, "d_entry": -1e9, "s_entry": 0.0, "occ": false, "d_probe": 1e9})
	if cands.is_empty():
		return out
	var d := -back
	while d <= ahead:
		var sk := s0 + dir * d
		if is_loop:
			sk = fposmod(sk, rlen)
		elif sk < 0.0 or sk > rlen:
			d += 1.0
			continue
		var p := curve.sample_baked(sk, false)
		for c: Dictionary in cands:
			if float(c["need"]) >= 0.0:
				continue
			var sw = c["sw"]
			var dm: Vector3 = sw.diverge_mid
			var dx := p.x - dm.x
			var dz := p.z - dm.z
			if dx * dx + dz * dz > 60.0 * 60.0:
				continue
			var ents: Array = sw.entries
			for ei in range(ents.size()):
				var e: Vector3 = ents[ei]
				if Vector2(p.x - e.x, p.z - e.z).length() < 0.8:
					c["occ"] = true
					if d > float(c["d_entry"]) + 3.0:
						c["entry"] = ei
						c["d_entry"] = d
						c["s_entry"] = sk
			if Vector2(dx, dz).length() < 1.3:
				c["need"] = 1.0
			elif Vector2(p.x - sw.straight_a.x, p.z - sw.straight_a.z).length() < 1.3 \
					or Vector2(p.x - sw.straight_b.x, p.z - sw.straight_b.z).length() < 1.3:
				c["need"] = 0.0
			if float(c["need"]) >= 0.0:
				c["occ"] = true
				c["d_probe"] = d
				if float(c["d_entry"]) > d:
					c["d_entry"] = -1e9 # entry hit belongs to a later pass
		d += 1.0
	for c: Dictionary in cands:
		if bool(c["occ"]):
			if float(c["d_entry"]) < -1e8:
				c["d_entry"] = minf(0.0, float(c["d_probe"])) if float(c["need"]) >= 0.0 else -1.0
			out.append(c)
	out.sort_custom(func(x, y): return float(x["d_entry"]) < float(y["d_entry"]))
	return out


func _update_monorail_switches(graph: NetworkGraph) -> void:
	if graph == null or not graph.has_meta("monorail_switches"):
		return
	var switches: Array = graph.get_meta("monorail_switches")
	if switches.is_empty():
		return
	var infos := {} # train idx -> {sw -> info}
	for ti in range(trams.size()):
		var tr: Dictionary = trams[ti]
		tr["sw_hold_s"] = -1.0
		var lst := _scan_switches(tr, switches)
		var prev_next: Dictionary = tr.get("sw_next", {})
		tr["sw_next"] = {}
		var per := {}
		for c: Dictionary in lst:
			per[c["sw"]] = c
		infos[ti] = per
		for c: Dictionary in lst:
			if float(c["d_entry"]) > 0.0 and float(c["need"]) >= 0.0:
				tr["sw_next"] = c
				break
		# The scan works in 1 m steps, so it may move on to the next switch a moment before the head actually
		# enters this one: keep it pending until the entry check (_check_switch_entry) has seen the head pass.
		var new_next: Dictionary = tr["sw_next"]
		if not prev_next.is_empty() and (new_next.is_empty() or new_next["sw"] != prev_next["sw"]):
			tr["sw_pending"] = prev_next
	# A crossover's switches (two in series for a two-way crossover) are owned as one unit, so a train never
	# has to stop between them and two trains can never deadlock on them.
	var done := {}
	for sw0 in switches:
		if not is_instance_valid(sw0) or done.has(sw0):
			continue
		var grp: Array = []
		for g in (sw0.group if not (sw0.group as Array).is_empty() else [sw0]):
			if is_instance_valid(g):
				grp.append(g)
				done[g] = true
		# Group view of each train: nearest entry over the group's switches (present while any part is ahead/under it)
		var g_de := {}
		for ti: int in infos.keys():
			var best := 1e9
			var found := false
			for g in grp:
				var c: Dictionary = (infos[ti] as Dictionary).get(g, {})
				if c.is_empty() or float(c["need"]) < 0.0:
					continue
				found = true
				best = minf(best, float(c["d_entry"]))
			if found:
				g_de[ti] = best
		# First come, first served: a train claims the crossover from the moment it starts approaching it
		# (request time kept per train); trains standing idle (dwelling, or a manual train parked at a platform)
		# do not claim it, so they never lock out a train that is actually coming.
		var gkey := (grp[0] as Object).get_instance_id()
		var req := {} # train -> request time (active requests only)
		var passive := {} # idle manual trains: may take a free switch, give it up to anyone actually coming
		for ti: int in g_de.keys():
			var rq_map: Dictionary = trams[ti].get("sw_req_t", {})
			var lvl := _sw_requesting(ti, float(g_de[ti]))
			if lvl == 2:
				if not rq_map.has(gkey):
					rq_map[gkey] = operating_seconds
				req[ti] = float(rq_map[gkey])
			else:
				rq_map.erase(gkey)
				if lvl == 1:
					passive[ti] = true
			trams[ti]["sw_req_t"] = rq_map
		for ti in range(trams.size()):
			if not g_de.has(ti):
				(trams[ti].get("sw_req_t", {}) as Dictionary).erase(gkey)
		var cur := -1
		for g in grp:
			if int(g.owner_idx) >= 0 and int(g.owner_idx) < trams.size():
				cur = int(g.owner_idx)
				break
		if cur >= 0 and not req.has(cur) and not (passive.has(cur) and req.is_empty()):
			cur = -1 # tail has cleared the crossover, or it stands idle short of it while another train is coming
		if cur < 0 and req.is_empty() and not passive.is_empty():
			cur = int(passive.keys()[0])
		if cur < 0:
			var best_key := 1e18
			for ti: int in req.keys():
				var de := float(g_de[ti])
				var key := float(req[ti])
				if de <= 0.0 or (de <= SW_SIGNAL_BACK and float(trams[ti]["speed_mps"]) > 0.3):
					key -= 1e9 # already on it / past its stop point: cannot stop any more
				if key < best_key:
					best_key = key
					cur = ti
		for sw in grp:
			if cur >= 0:
				var c2: Dictionary = (infos[cur] as Dictionary).get(sw, {})
				if c2.is_empty() or float(c2["need"]) < 0.0:
					sw.owner_entry = -1 # this part is already behind the train
				elif float(c2["d_entry"]) > 0.0 or cur != int(sw.owner_idx):
					sw.owner_need = float(c2["need"])
					sw.owner_entry = int(c2["entry"])
			if cur != int(sw.owner_idx) or cur < 0 or not (cur == active_tram_idx and manual_drive):
				sw.manual_override = false # override only lasts while that manual train holds the switch
			sw.owner_idx = cur
			if cur >= 0 and not sw.manual_override and int(sw.owner_entry) >= 0:
				sw.target = sw.owner_need
			sw.update_signals()
	# Stop points for trains whose next switch is not (yet) set and cleared for them
	for ti: int in infos.keys():
		var tr: Dictionary = trams[ti]
		var nx: Dictionary = tr.get("sw_next", {})
		if nx.is_empty():
			continue
		var sw = nx["sw"]
		if int(sw.owner_idx) == ti and sw.signal_green(int(nx["entry"])):
			continue
		var de := float(nx["d_entry"])
		var hold := de - SW_SIGNAL_BACK
		if hold < 0.0:
			hold = maxf(0.0, de - 1.5)
		tr["sw_hold_s"] = fposmod(float(tr["s"]) + float(tr["dir"]) * hold, float(tr["route_len"])) if bool(tr["is_loop"]) else float(tr["s"]) + float(tr["dir"]) * hold


# How much train `ti` wants the crossover now: 2 = it is on it or coming towards it, 1 = a manual train
# standing still short of it (gets it only while nobody else is coming), 0 = not at all (dwelling etc.)
func _sw_requesting(ti: int, d_entry: float) -> int:
	if d_entry <= 0.0:
		return 2
	var tr: Dictionary = trams[ti]
	if not _sw_ready(tr):
		return 0 # dwelling at a platform, doors open, turning back or held at a terminal
	if _distance_to_tram_ahead(tr, ti) + 4.0 < d_entry:
		return 0 # another train stands between it and the switch: that one goes first (no deadlock behind it)
	if ti == active_tram_idx and manual_drive:
		if float(tr["speed_mps"]) > 0.3 or int(tr["notch"]) > NOTCH_NEUTRAL:
			return 2
		return 1
	return 2


# ---------------------------------------------------------------------------------------------
# Four-track express / local dispatch (after the 2D game's holdLocalForExpress): a local train ready to leave
# a twin-island stop waits while a same-direction express
#   * is standing at the same stop (the express departs first), or
#   * is coming up behind: within 450 m if it runs through non-stop, 240 m if it will call here,
# and is released once the express is 35 m past the platform head. Never longer than EXPRESS_HOLD_MAX.
# ---------------------------------------------------------------------------------------------
const EXPRESS_LOOK_NONSTOP := 450.0
const EXPRESS_LOOK_STOPPING := 240.0
const EXPRESS_LEADOUT := 35.0
const EXPRESS_HOLD_MAX := 75.0

func _holding_for_express(tr: Dictionary, my_idx: int, sid: int, graph: NetworkGraph, dt: float) -> bool:
	if bool(tr.get("express", false)) or graph == null or sid < 0 or not graph.is_quad_island(sid):
		tr["express_hold_t"] = 0.0
		return false
	var held := float(tr.get("express_hold_t", 0.0))
	if held >= EXPRESS_HOLD_MAX:
		return false
	if held <= 0.0 and float(tr.get("express_hold_done", -1.0)) == float(sid):
		return false # already gave way once at this stop
	var st: Dictionary = graph.stations[sid]
	var st_pos: Vector3 = st["pos"]
	var plat_half := float(st.get("platform_len", 27.0)) * 0.5
	var my_fwd := _tram_heading(tr)
	var hold := false
	for j in range(trams.size()):
		var w: Dictionary = trams[j]
		if j == my_idx or not bool(w.get("express", false)) or bool(w.get("elevated", false)):
			continue
		if bool(w.get("crashed", false)) or bool(w.get("derailed", false)):
			continue
		var w_fwd := _tram_heading(w)
		if w_fwd.dot(my_fwd) < 0.5:
			continue # other direction
		var secs: Array = w["tram_info"]["sections"]
		if secs.is_empty():
			continue
		var wp := (secs[0] as Node3D).global_position
		var to_st := st_pos - wp
		to_st.y = 0.0
		var along := to_st.dot(w_fwd) # > 0: station still ahead of the express head
		var lateral := absf(to_st.dot(w_fwd.cross(Vector3.UP).normalized()))
		if lateral > 14.0:
			continue
		var calls := false
		for stop: Dictionary in w["stops"]:
			if int(stop["station_id"]) == sid:
				calls = true
		var w_here := int(_find_station_at_current_pos(w)["station_id"]) == sid
		if w_here and calls and (float(w["speed_mps"]) < 0.5 or bool(w["doors_target_open"])):
			hold = true # express dwelling at this stop departs first
		elif along > -(plat_half + EXPRESS_LEADOUT) and along <= (EXPRESS_LOOK_STOPPING if calls else EXPRESS_LOOK_NONSTOP):
			if not _path_passes(w, st_pos, along + 20.0):
				continue
			hold = true # approaching (or still pulling out past the platform head)
		if hold:
			break
	if hold:
		tr["express_hold_t"] = held + dt
		tr["express_waiting"] = true
	else:
		if held > 0.0:
			tr["express_hold_done"] = float(sid)
		tr["express_hold_t"] = 0.0
		tr["express_waiting"] = false
	return hold


func _tram_heading(tr: Dictionary) -> Vector3:
	var secs: Array = tr["tram_info"]["sections"]
	if secs.is_empty() or not is_instance_valid(secs[0]):
		return Vector3.FORWARD
	var f := -(secs[0] as Node3D).global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


# The train's route passes within a few metres of p somewhere in the next `ahead` metres
func _path_passes(tr: Dictionary, p: Vector3, ahead: float) -> bool:
	var curve: Curve3D = tr["curve"]
	var rlen := float(tr["route_len"])
	var dir := float(tr["dir"])
	var s0 := float(tr["s"])
	var k := -40.0
	while k <= maxf(ahead, 0.0) + 40.0:
		var sk := s0 + dir * k
		sk = fposmod(sk, rlen) if bool(tr["is_loop"]) else clampf(sk, 0.0, rlen)
		var q := curve.sample_baked(sk, false)
		if Vector2(q.x - p.x, q.z - p.z).length() < 10.0:
			return true
		k += 4.0
	return false


# ---------------------------------------------------------------------------------------------
# Merging tracks (four-track ends, junction turnouts): two trains heading for the same merge point from different
# tracks would otherwise only see each other once one is already on the other's path. The one further from the
# merge point waits ~14 m short of it until the other has passed.
# ---------------------------------------------------------------------------------------------
const MERGE_LOOK := 80.0
const MERGE_STEP := 2.0
const MERGE_STANDOFF := 16.0

func _update_merge_yields() -> void:
	var paths := {}
	for i in range(trams.size()):
		trams[i]["merge_hold_s"] = -1.0
	for i in range(trams.size()):
		var a: Dictionary = trams[i]
		if bool(a.get("elevated", false)) or bool(a.get("crashed", false)) or bool(a.get("derailed", false)):
			continue
		for j in range(i + 1, trams.size()):
			var b: Dictionary = trams[j]
			if bool(b.get("elevated", false)) or bool(b.get("crashed", false)) or bool(b.get("derailed", false)):
				continue
			var pa := _head_pos(a)
			var pb := _head_pos(b)
			if pa.distance_to(pb) > MERGE_LOOK * 2.0 + 20.0:
				continue
			if not paths.has(i):
				paths[i] = _path_ahead_pts(a)
			if not paths.has(j):
				paths[j] = _path_ahead_pts(b)
			var ap: PackedVector2Array = paths[i]
			var bp: PackedVector2Array = paths[j]
			if _on_path(ap, Vector2(pb.x, pb.z)) or _on_path(bp, Vector2(pa.x, pa.z)):
				continue # already one behind the other on the same track: normal headway keeps them apart
			var hit := _first_merge(ap, bp)
			if hit.x < 0:
				continue
			var da := float(hit.x) * MERGE_STEP
			var db := float(hit.y) * MERGE_STEP
			var b_yields := db > da or (is_equal_approx(da, db) and j > i) # further from the merge point waits
			var yielder: Dictionary = b if b_yields else a
			var stop_at := (db if b_yields else da) - MERGE_STANDOFF
			if stop_at < 0.0:
				continue # too close to stop short: it is effectively already merging
			var s_new := float(yielder["s"]) + float(yielder["dir"]) * stop_at
			if bool(yielder["is_loop"]):
				s_new = fposmod(s_new, float(yielder["route_len"]))
			if float(yielder["merge_hold_s"]) < 0.0 or _hold_ahead(yielder, s_new) < _hold_ahead(yielder, float(yielder["merge_hold_s"])):
				yielder["merge_hold_s"] = s_new


func _head_pos(tr: Dictionary) -> Vector3:
	var secs: Array = tr["tram_info"]["sections"]
	if secs.is_empty() or not is_instance_valid(secs[0]):
		return (tr["curve"] as Curve3D).sample_baked(float(tr["s"]))
	return (secs[0] as Node3D).global_position


func _path_ahead_pts(tr: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var curve: Curve3D = tr["curve"]
	var rlen := float(tr["route_len"])
	var dir := float(tr["dir"])
	var s0 := float(tr["s"])
	var k := 0.0
	while k <= MERGE_LOOK:
		var sk := s0 + dir * k
		if bool(tr["is_loop"]):
			sk = fposmod(sk, rlen)
		elif sk < 0.0 or sk > rlen:
			break
		var q := curve.sample_baked(sk, false)
		out.append(Vector2(q.x, q.z))
		k += MERGE_STEP
	return out


static func _on_path(pts: PackedVector2Array, p: Vector2) -> bool:
	for q: Vector2 in pts:
		if q.distance_squared_to(p) < 2.2 * 2.2:
			return true
	return false


# First pair of indices (a, b) where the two paths come together heading the same way (b index into bp); (-1,-1) if none
static func _first_merge(ap: PackedVector2Array, bp: PackedVector2Array) -> Vector2i:
	for ia in range(2, ap.size() - 1):
		for ib in range(2, bp.size() - 1):
			if ap[ia].distance_squared_to(bp[ib]) < 2.0 * 2.0:
				var ta := (ap[ia + 1] - ap[ia]).normalized()
				var tb := (bp[ib + 1] - bp[ib]).normalized()
				if ta.dot(tb) > 0.7:
					return Vector2i(ia, ib)
				return Vector2i(-1, -1) # paths cross / meet head-on: handled by signals and interlocking
	return Vector2i(-1, -1)


func _hold_ahead(tr: Dictionary, s_hold: float) -> float:
	if s_hold < 0.0:
		return 1e9
	var d := (s_hold - float(tr["s"])) * float(tr["dir"])
	if bool(tr["is_loop"]):
		d = fposmod(d, float(tr["route_len"]))
		return d if d < float(tr["route_len"]) * 0.5 else 0.0
	return maxf(0.0, d)


func _merge_hold_distance(tr: Dictionary) -> float:
	var hs := float(tr.get("merge_hold_s", -1.0))
	if hs < 0.0:
		return 1e9
	return _hold_ahead(tr, hs)


func _switch_hold_distance(tr: Dictionary) -> float:
	var hs := float(tr.get("sw_hold_s", -1.0))
	if hs < 0.0:
		return 1e9
	var d := (hs - float(tr["s"])) * float(tr["dir"])
	if bool(tr["is_loop"]):
		d = fposmod(d, float(tr["route_len"]))
		return d if d < float(tr["route_len"]) * 0.5 else 0.0
	return maxf(0.0, d)


# Driver's view of the next switch: {} or {dist, need, set_ok, moving, green, mine, throw}
func switch_ahead_info(tr: Dictionary, me: int) -> Dictionary:
	var nx: Dictionary = tr.get("sw_next", {})
	if nx.is_empty() or not is_instance_valid(nx["sw"]):
		return {}
	var sw = nx["sw"]
	var de := (float(nx["s_entry"]) - float(tr["s"])) * float(tr["dir"])
	if bool(tr["is_loop"]):
		de = fposmod(de, float(tr["route_len"]))
	return {
		"dist": de,
		"need": float(nx["need"]),
		"target": float(sw.target),
		"moving": absf(float(sw.throw) - float(sw.target)) > 0.001,
		"green": int(sw.owner_idx) == me and sw.signal_green(int(nx["entry"])),
		"mine": int(sw.owner_idx) == me,
		"busy": int(sw.owner_idx) >= 0 and int(sw.owner_idx) != me,
		"override": bool(sw.manual_override) and int(sw.owner_idx) == me,
	}


# A switch is facing for a train entering at `entry` (0: low end -1, 1: low end +1, 2: high end -1, 3: high end +1)
# when its crossing beam starts from that end: hand +1 runs lane -1 (low s) -> lane +1 (high s), hand -1 the mirror.
static func _is_facing(sw, entry: int) -> bool:
	if entry < 0:
		return true
	if float(sw.hand) > 0.0:
		return entry == 0 or entry == 3
	return entry == 1 or entry == 2


# Manual driving: throw the next switch ahead of the active train (G). Returns a status string.
func manual_throw_switch(graph: NetworkGraph) -> String:
	var tr := get_active_tram()
	if tr.is_empty():
		return "none"
	if graph == null or not graph.has_meta("monorail_switches"):
		return "none"
	var lst := _scan_switches(tr, graph.get_meta("monorail_switches"), 260.0)
	var me := active_tram_idx
	var trailing: Array = [] # switches of the same crossover the train only runs straight through
	for ci in range(lst.size()):
		var c: Dictionary = lst[ci]
		if float(c["need"]) < 0.0:
			continue
		var sw = c["sw"]
		if float(c["d_entry"]) <= 2.0:
			if int(sw.owner_idx) == me:
				continue # the train is on it: locked, look at the next one
			return "locked"
		if int(sw.owner_idx) >= 0 and int(sw.owner_idx) != me:
			return "busy"
		if not _is_facing(sw, int(c["entry"])):
			# Its crossing beam joins from the other track: the train can only pass it straight. Throw the
			# next switch of the same crossover instead; with none, this switch cannot be used from here.
			var nxt_same := ci + 1 < lst.size() and (sw.group as Array).has((lst[ci + 1] as Dictionary)["sw"])
			if nxt_same:
				trailing.append(c)
				continue
			return "trailing"
		for tc: Dictionary in trailing:
			var tsw = tc["sw"]
			tsw.owner_idx = me
			tsw.owner_need = float(tc["need"])
			tsw.owner_entry = int(tc["entry"])
			tsw.target = 0.0
			tsw.manual_override = absf(float(tc["need"])) > 0.5
		sw.owner_idx = me
		sw.owner_need = float(c["need"])
		sw.owner_entry = int(c["entry"])
		sw.target = 0.0 if float(sw.target) > 0.5 else 1.0
		sw.manual_override = absf(float(sw.target) - float(c["need"])) > 0.5 # back on route = automatic again
		tr["sw_next"] = lst[0] if not trailing.is_empty() else c
		return "diverge" if float(sw.target) > 0.5 else "straight"
	return "none"


# The driver set a terminal crossover against the train's route: find the route variant whose path through `sw`
# matches how it is set (arriving: the other platform track; leaving: wrong-track running, or both) and move
# the train onto it. The train keeps its place relative to that terminal (hold point when arriving, turnback
# point when leaving), where the variants are identical.
func _reroute_through_switch(tr: Dictionary, sw) -> bool:
	var lid := int(tr["line_id"])
	var b_now: Dictionary = tr.get("b_sids", {})
	var w_now: Dictionary = tr.get("w_sids", {})
	var dir := float(tr["dir"])
	var s_now := float(tr["s"])
	var rlen := float(tr["route_len"])
	var head_old := (tr["curve"] as Curve3D).sample_baked(s_now, false)
	for z: Dictionary in tr.get("terminal_zones", []):
		var sid := int(z["station_id"])
		# Signed distance past the turnback point decides arriving vs leaving this terminal
		var past_cusp := fposmod((s_now - float(z["cusp_s"])) * dir, rlen)
		if past_cusp > rlen * 0.5:
			past_cusp -= rlen
		var leaving := past_cusp >= 0.0
		var anchor_key := "cusp_s" if leaving else "hold_s"
		var d_anchor := fposmod((s_now - float(z[anchor_key])) * dir, rlen)
		if d_anchor > rlen * 0.5:
			d_anchor -= rlen
		if absf(d_anchor) > 400.0:
			continue # this terminal is nowhere near
		for toggle: Array in [[true, false], [false, true], [true, true]]:
			var b_new := b_now.duplicate()
			var w_new := w_now.duplicate()
			if toggle[0]:
				if b_new.has(sid):
					b_new.erase(sid)
				else:
					b_new[sid] = true
			if toggle[1]:
				if w_new.has(sid):
					w_new.erase(sid)
				else:
					w_new[sid] = true
			var key := _variant_key(b_new, w_new)
			if key == str(tr.get("variant_key", "")):
				continue
			var c := _get_variant(lid, key)
			if c.is_empty():
				continue
			var z_new := {}
			for zc: Dictionary in c.get("terminal_zones", []):
				if int(zc["station_id"]) == sid:
					z_new = zc
			if z_new.is_empty():
				continue
			var len_new := float(c["length"])
			var s_new := float(z_new[anchor_key]) + dir * d_anchor
			s_new = fposmod(s_new, len_new) if bool(tr["is_loop"]) else clampf(s_new, 0.0, len_new)
			var head_new := (c["curve"] as Curve3D).sample_baked(s_new, false)
			if head_old.distance_to(head_new) > 1.5:
				continue # not the same track here
			var probe := {"curve": c["curve"], "route_len": len_new, "is_loop": bool(tr["is_loop"]), "dir": dir,
				"s": s_new, "elevated": tr.get("elevated", false), "spec": tr["spec"], "tram_info": tr["tram_info"]}
			var ok := false
			for cand: Dictionary in _scan_switches(probe, [sw], 40.0):
				if cand["sw"] == sw and float(cand["need"]) >= 0.0 and absf(float(cand["need"]) - float(sw.throw)) < 0.02:
					ok = true
			if not ok:
				continue
			_apply_route_variant(tr, c, key)
			tr["s"] = s_new
			tr["sw_next"] = {}
			var res: Dictionary = tr.get("term_res", {})
			if not leaving:
				res[sid] = {"platform": int(z_new["platform"]), "phase": "in"}
				tr["term_res"] = res
				_hand_over_platform(tr, sid, int(z_new["platform"]))
			elif res.has(sid):
				(res[sid] as Dictionary)["platform"] = int(z_new["platform"])
			_position_tram_3d(tr)
			return true
	return false


# Back to normal routing once a wrong-track run has reached the next terminal and turned back there (the
# variants agree from that turnback point on, so the train keeps its place relative to it)
func _hand_over_platform(me_tr: Dictionary, sid: int, platform: int) -> void:
	# The driver took platform `platform` by hand: another train still waiting to enter it goes to the other one
	for j in range(trams.size()):
		var o: Dictionary = trams[j]
		if o == me_tr or bool(o.get("elevated", false)) != bool(me_tr.get("elevated", false)):
			continue
		var r: Dictionary = (o.get("term_res", {}) as Dictionary).get(sid, {})
		if r.is_empty() or str(r["phase"]) != "in" or int(r["platform"]) != platform:
			continue
		var z := _zone_for(o, sid)
		if z.is_empty() or not bool(z["b_available"]):
			continue
		var from_hold := fposmod((float(o["s"]) - float(z["hold_s"])) * float(o["dir"]), float(o["route_len"]))
		if from_hold < float(o["route_len"]) * 0.5 and from_hold > NetworkGraph.TERMINAL_HOLD_MARGIN_M - 1.0:
			continue # already at the crossover: cannot change track any more
		var other := PLATFORM_A if platform == PLATFORM_B else PLATFORM_B
		_switch_terminal_platform(o, sid, other)
		r["platform"] = other


func _clear_wrong_track(tr: Dictionary) -> void:
	var w_now: Dictionary = tr.get("w_sids", {})
	if w_now.is_empty() or float(tr["speed_mps"]) > 0.05:
		return
	var sid := int(tr.get("term_sid", -1))
	if sid < 0 or w_now.has(sid) or str(tr.get("term_stage", "")) != "board_only":
		return
	var key := _variant_key(tr.get("b_sids", {}), {})
	var c := _get_variant(int(tr["line_id"]), key)
	if c.is_empty():
		return
	var cusp_old := -1.0
	var cusp_new := -1.0
	for st: Dictionary in tr["stops"]:
		if int(st["station_id"]) == sid and bool(st.get("turnback", false)):
			cusp_old = float(st.get("cusp", st["offset"]))
	for st: Dictionary in c["stops"]:
		if int(st["station_id"]) == sid and bool(st.get("turnback", false)):
			cusp_new = float(st.get("cusp", st["offset"]))
	if cusp_old < 0.0 or cusp_new < 0.0:
		return
	var rel := float(tr["s"]) - cusp_old
	_apply_route_variant(tr, c, key)
	var rlen := float(tr["route_len"])
	tr["s"] = fposmod(cusp_new + rel, rlen) if bool(tr["is_loop"]) else clampf(cusp_new + rel, 0.0, rlen)
	_position_tram_3d(tr)


# Player-driven train entering a switch span that is not set and cleared for it -> derailment
func _check_switch_entry(tr: Dictionary, tram_idx: int) -> Dictionary:
	for key: String in ["sw_pending", "sw_next"]:
		var ev := _check_switch_entry_one(tr, tram_idx, key)
		if not ev.is_empty():
			return ev
	return {}


func _check_switch_entry_one(tr: Dictionary, tram_idx: int, key: String) -> Dictionary:
	var nx: Dictionary = tr.get(key, {})
	if nx.is_empty() or not is_instance_valid(nx["sw"]):
		return {}
	var de := (float(nx["s_entry"]) - float(tr["s"])) * float(tr["dir"])
	if bool(tr["is_loop"]):
		de = fposmod(de, float(tr["route_len"]))
		if de > float(tr["route_len"]) * 0.5:
			de -= float(tr["route_len"])
	if de < -6.0 and key == "sw_pending":
		tr[key] = {} # passed long ago (or the route changed): nothing left to check
		return {}
	if de > 0.0 or de < -6.0:
		return {}
	var sw = nx["sw"]
	var need := float(nx["need"])
	tr[key] = {}
	# Physically at that switch's entry (guards against a stale entry after a reversal / route change)
	var ent := int(nx["entry"])
	if ent >= 0 and ent < (sw.entries as Array).size():
		var head := (tr["curve"] as Curve3D).sample_baked(float(tr["s"]), false)
		var ep: Vector3 = sw.entries[ent]
		if Vector2(head.x - ep.x, head.z - ep.z).length() > 8.0:
			return {}
	if absf(float(sw.throw) - need) < 0.02:
		return {}
	# Switch fully set the other way at a terminal crossover: the train simply follows the beam / rails it is
	# set for (wrong-track running to the next terminal) instead of coming off
	if absf(float(sw.throw) - float(sw.target)) < 0.001 and _reroute_through_switch(tr, sw):
		return {}
	tr["derailed"] = true
	tr["rollover_sign"] = 1.0
	tr["rollover_progress"] = 0.06
	var kmh := float(tr["speed_mps"]) * 3.6
	tr["speed_mps"] = 0.0
	var secs: Array = tr["tram_info"]["sections"]
	return {
		"accident": true,
		"type": "switch",
		"tram_idx": tram_idx,
		"world_pos": (secs[0] as Node3D).global_position if not secs.is_empty() else Vector3.ZERO,
		"speed_kmh": kmh,
		"moving": absf(float(sw.throw) - float(sw.target)) > 0.001,
	}

