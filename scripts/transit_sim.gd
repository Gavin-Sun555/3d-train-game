class_name TransitSim
extends Node3D

const NOTCH_LABELS := ["EB", "B4", "B3", "B2", "B1", "N", "P1", "P2", "P3", "P4"]
const NOTCH_NEUTRAL := 5
const TURNBACK_STOP_MARGIN := 1.0 # Lead bogie stops this far before the terminal turnback point
const BUFFER_SAFE_KMH := 5.0 # buffer stops absorb a gentle coupling-speed touch; anything faster derails
const TERMINAL_REQUEST_DIST_M := 170.0 # Trams request a terminal platform this far before the hold point
const PLATFORM_A := 0 # Arrive straight in, cross over after departing
const PLATFORM_B := 1 # Cross over before arriving, depart straight out (needs a scissors crossover)

enum AIStyle {
	SLOW = 0,    # 缓慢：停稳过2~3秒再开门、人上好过几秒再关、等待赶来乘客、柔和加减速
	NORMAL = 1,  # 正常：目前的基准
	FURIOUS = 2, # 狂暴：加速度与刹车拉满、高巡航速度、快速进出站，开关门与候客逻辑同标准模式
}
const AI_STYLE_NAMES := ["缓慢", "正常", "狂暴"]
const AI_STYLE_NAMES_EN := ["Slow", "Normal", "Furious"]
const LINE_AI_NONE := -1
const AI_MIN_MAX_KMH := 15
const AI_SPEED_STEP_KMH := 5

var trams: Array[Dictionary] = []
var _tram_ai_prefs: Dictionary = {} # "%d:%d" % [line_id, ord_on_line] -> {"ai_style": int, "ai_max_kmh": int, "ai_max_custom": bool}
var line_ai_styles: Dictionary = {} # line_id (int) -> AIStyle (int) default group style for the line
var active_tram_idx := 0
var manual_drive := false
var _anim_time := 0.0
var _step_frame := 0
var operating_seconds := 0.0
var line_dist_m: Dictionary = {} # line_id -> float (total distance traveled by trams on this line)
var line_route_len_m: Dictionary = {} # line_id -> float (one-way full route length in meters; full circuit for pure loops)
var line_trip_time_sum_s: Dictionary = {} # line_id -> float (sum of completed full end-to-end trip durations)
var line_trip_count: Dictionary = {} # line_id -> int (count of completed full end-to-end trips)
var _switch_timer := 0.0
var _last_tram_of_line: Dictionary = {} # line_id -> tram index last watched on that line
var auto_switches := true # false: the dispatcher never moves a switch; only the player (G) does
var player_lock: Array = [] # switches of the crossover the player locked ahead of their train
var _lock_entered := false # the locking train has reached the locked crossover (it unlocks once it is through)
var lock_released := false # set when the lock lapsed on its own (the train has cleared it); main shows a note
var _graph_ref: NetworkGraph = null # for compiling wrong-track route variants on demand
var line_variants: Dictionary = {} # line_id -> {variant_key: compiled route} (one per terminal platform combination)


func rebuild_fleet(
	graph: NetworkGraph,
	catalogue: Array,
	night_factor: float
) -> void:
	var line_ord_counts: Dictionary = {}
	for old_tr: Dictionary in trams:
		var old_lid := int(old_tr.get("line_id", -1))
		var ord_i := int(line_ord_counts.get(old_lid, 0))
		line_ord_counts[old_lid] = ord_i + 1
		_tram_ai_prefs["%d:%d" % [old_lid, ord_i]] = {
			"ai_style": int(old_tr.get("ai_style", AIStyle.NORMAL)),
			"ai_max_kmh": int(old_tr.get("ai_max_kmh", int((old_tr.get("spec", {}) as Dictionary).get("max_speed_kmh", 70)))),
			"ai_max_custom": bool(old_tr.get("ai_max_custom", false)),
		}
	for c in get_children():
		c.queue_free()
	trams.clear()
	active_tram_idx = 0
	operating_seconds = 0.0
	line_dist_m.clear()
	line_route_len_m.clear()
	line_trip_time_sum_s.clear()
	line_trip_count.clear()
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
		var sec_cnt := clampi(int(ln.get("sections", int(spec.get("default_sections", 2)))), 1, 5)
		var fleet_n := clampi(int(ln.get("trams_count", 2)), 1, 15)
		var route_len := float(compiled["length"])
		var is_loop := bool(compiled["is_loop"])
		var stops: Array = compiled["stops"]
		var cap := sec_cnt * int(spec.get("cap_per_section", 58))
		var rev_cusps: Array = compiled.get("turnbacks", [])
		# Full one-way route length: half of out-and-back loop when terminal turnbacks exist, else full route length
		line_route_len_m[lid] = route_len * 0.5 if (is_loop and not rev_cusps.is_empty()) else route_len
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

			var spec_top_kmh := maxi(AI_MIN_MAX_KMH, int(spec.get("max_speed_kmh", 70)))
			var pref_d: Dictionary = _tram_ai_prefs.get("%d:%d" % [lid, ti], {})
			var line_default_style := clampi(int(line_ai_styles.get(lid, AIStyle.NORMAL)), 0, 2)
			var init_ai_style := clampi(int(pref_d.get("ai_style", line_default_style)), 0, 2)
			var init_ai_max := clampi(int(pref_d.get("ai_max_kmh", spec_top_kmh)), AI_MIN_MAX_KMH, spec_top_kmh)
			var init_ai_custom := bool(pref_d.get("ai_max_custom", false))

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
				"ai_style": init_ai_style,
				"ai_max_kmh": init_ai_max,
				"ai_max_custom": init_ai_custom,
				"ai_open_delay": 0.0,
				"ai_close_grace": 0.0,
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
		var tr_res_out := {}
		var tr_res_raw: Dictionary = tr.get("term_res", {})
		for sid_k in tr_res_raw:
			var r_d: Dictionary = tr_res_raw[sid_k]
			tr_res_out[str(sid_k)] = {
				"platform": int(r_d.get("platform", PLATFORM_A)),
				"phase": str(r_d.get("phase", "in")),
			}
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
			"term_res": tr_res_out,
			"pax_dests": (tr["pax_dests"] as Array).duplicate(),
			"reverser": float(tr.get("reverser", 1.0)),
			"stats": _tram_stats_dict(tr),
			"held_manual": bool(tr.get("held_manual", false)),
			"ai_style": int(tr.get("ai_style", AIStyle.NORMAL)),
			"ai_max_kmh": int(tr.get("ai_max_kmh", tram_spec_max_kmh(tr))),
			"ai_max_custom": bool(tr.get("ai_max_custom", false)),
		})
	var line_styles_out := {}
	for lid_k in line_ai_styles:
		var lv := int(line_ai_styles[lid_k])
		if lv >= 0 and lv <= 2:
			line_styles_out[str(lid_k)] = lv
	var trip_sum_out := {}
	for lid_k in line_trip_time_sum_s:
		trip_sum_out[str(lid_k)] = float(line_trip_time_sum_s[lid_k])
	var trip_cnt_out := {}
	for lid_k in line_trip_count:
		trip_cnt_out[str(lid_k)] = int(line_trip_count[lid_k])
	return {
		"active_tram_idx": active_tram_idx,
		"manual_drive": manual_drive,
		"auto_switches": auto_switches,
		"line_ai_styles": line_styles_out,
		"line_trip_time_sum_s": trip_sum_out,
		"line_trip_count": trip_cnt_out,
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
		var saved_res = st.get("term_res", {})
		if typeof(saved_res) == TYPE_DICTIONARY:
			var restored_res := {}
			for sid_k in (saved_res as Dictionary):
				var rd_i = (saved_res as Dictionary)[sid_k]
				if typeof(rd_i) == TYPE_DICTIONARY:
					restored_res[int(sid_k)] = {
						"platform": clampi(int((rd_i as Dictionary).get("platform", PLATFORM_A)), 0, 1),
						"phase": str((rd_i as Dictionary).get("phase", "in")),
					}
			tr["term_res"] = restored_res
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
		var spec_top := tram_spec_max_kmh(tr)
		tr["ai_style"] = clampi(int(st.get("ai_style", tr.get("ai_style", AIStyle.NORMAL))), 0, 2)
		tr["ai_max_kmh"] = clampi(int(st.get("ai_max_kmh", tr.get("ai_max_kmh", spec_top))), AI_MIN_MAX_KMH, spec_top)
		tr["ai_max_custom"] = bool(st.get("ai_max_custom", tr.get("ai_max_custom", false)))
		tr["ai_open_delay"] = 0.0
		tr["ai_close_grace"] = 0.0
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
	line_ai_styles.clear()
	var saved_ls = run_state.get("line_ai_styles", {})
	if typeof(saved_ls) == TYPE_DICTIONARY:
		for lid_k in (saved_ls as Dictionary):
			var lv := int((saved_ls as Dictionary)[lid_k])
			if lv >= 0 and lv <= 2:
				line_ai_styles[int(lid_k)] = lv
	line_trip_time_sum_s.clear()
	var saved_ts = run_state.get("line_trip_time_sum_s", {})
	if typeof(saved_ts) == TYPE_DICTIONARY:
		for lid_k in (saved_ts as Dictionary):
			line_trip_time_sum_s[int(lid_k)] = float((saved_ts as Dictionary)[lid_k])
	line_trip_count.clear()
	var saved_tc = run_state.get("line_trip_count", {})
	if typeof(saved_tc) == TYPE_DICTIONARY:
		for lid_k in (saved_tc as Dictionary):
			line_trip_count[int(lid_k)] = int((saved_tc as Dictionary)[lid_k])
	active_tram_idx = clampi(int(run_state.get("active_tram_idx", 0)), 0, maxi(0, trams.size() - 1))
	manual_drive = bool(run_state.get("manual_drive", false))
	auto_switches = bool(run_state.get("auto_switches", true))
	_heal_saved_terminal_conflicts()


# Heal any pre-existing terminal crossover head-on jam from an older run save: if an arriving tram was saved
# inside a terminal crossover/throat on the same platform as a tram already docked/departing there, back the
# arriving tram safely outside `hold_s` (and preserve safe spacing for any queued tram behind it).
func _heal_saved_terminal_conflicts() -> void:
	for i in range(trams.size()):
		var tr: Dictionary = trams[i]
		if not bool(tr["is_loop"]) or bool(tr.get("crashed", false)) or bool(tr.get("derailed", false)):
			continue
		if bool(tr["doors_target_open"]) or float(tr["door_ratio"]) > 0.05 or str(tr.get("term_stage", "")) != "":
			continue
		var rlen := float(tr["route_len"])
		var dir := float(tr["dir"])
		var s_now := float(tr["s"])
		for z: Dictionary in tr.get("terminal_zones", []):
			var sid := int(z["station_id"])
			var hold_s := float(z["hold_s"])
			var cusp_s := float(z["cusp_s"])
			var arr_len := fposmod((cusp_s - hold_s) * dir, rlen)
			var from_hold := fposmod((s_now - hold_s) * dir, rlen)
			if from_hold > arr_len + 0.5:
				continue # Not in arrival leg
			var my_plat := int(z["platform"])
			var conflict := false
			for j in range(trams.size()):
				if j == i or bool(trams[j].get("elevated", false)) != bool(tr.get("elevated", false)):
					continue
				var o: Dictionary = trams[j]
				if not bool(o["is_loop"]) or bool(o.get("crashed", false)) or bool(o.get("derailed", false)):
					continue
				var oz := _zone_for(o, sid)
				if oz.is_empty() or int(oz["platform"]) != my_plat:
					continue
				var o_rlen := float(o["route_len"])
				var o_dir := float(o["dir"])
				var o_s := float(o["s"])
				var o_hold := float(oz["hold_s"])
				var o_cusp := float(oz["cusp_s"])
				var o_exit := float(oz["exit_s"])
				var o_arr := fposmod((o_cusp - o_hold) * o_dir, o_rlen)
				var o_dep := fposmod((o_exit - o_cusp) * o_dir, o_rlen) + _consist_length(o) + 4.0
				var o_from_hold := fposmod((o_s - o_hold) * o_dir, o_rlen)
				var o_from_cusp := fposmod((o_s - o_cusp) * o_dir, o_rlen)
				var o_in_arr := o_from_hold <= o_arr + 0.5
				var o_in_dep := (not o_in_arr) and o_from_cusp <= o_dep
				if o_in_dep or (o_in_arr and o_from_hold > from_hold + 1.0):
					conflict = true
					break
			if not conflict:
				continue
			# Pull this conflicting arriving tram back just outside the terminal hold point
			var new_s := fposmod(hold_s - dir * 2.0, rlen)
			tr["s"] = new_s
			tr["speed_mps"] = 0.0
			(tr["term_res"] as Dictionary).erase(sid)
			_position_tram_3d(tr)
			# Ensure any queued trams approaching right behind it on the same arrival track keep safe spacing
			var min_gap := _consist_length(tr) + 10.5
			var rear_cands: Array = []
			for k in range(trams.size()):
				if k == i or bool(trams[k].get("elevated", false)) != bool(tr.get("elevated", false)):
					continue
				var q: Dictionary = trams[k]
				if not bool(q["is_loop"]):
					continue
				var qz := _zone_for(q, sid)
				if qz.is_empty():
					continue
				var q_rlen := float(q["route_len"])
				var q_dir := float(q["dir"])
				var q_hold := float(qz["hold_s"])
				var d_before := fposmod((q_hold - float(q["s"])) * q_dir, q_rlen)
				if d_before >= 0.0 and d_before < 120.0:
					rear_cands.append({"idx": k, "d_before": d_before, "hold_s": q_hold, "rlen": q_rlen, "dir": q_dir})
			rear_cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d_before"]) < float(b["d_before"]))
			var prev_d_before := 2.0
			var prev_gap := min_gap
			for rc: Dictionary in rear_cands:
				var qi := int(rc["idx"])
				var q: Dictionary = trams[qi]
				var need_d := prev_d_before + prev_gap
				if float(rc["d_before"]) < need_d:
					q["s"] = fposmod(float(rc["hold_s"]) - float(rc["dir"]) * need_d, float(rc["rlen"]))
					q["speed_mps"] = 0.0
					(q["term_res"] as Dictionary).erase(sid)
					_position_tram_3d(q)
					prev_d_before = need_d
				else:
					prev_d_before = float(rc["d_before"])
				prev_gap = _consist_length(q) + 10.5
			break


static func tram_spec_max_kmh(tr: Dictionary) -> int:
	var sp: Dictionary = tr.get("spec", {})
	return maxi(AI_MIN_MAX_KMH, int(sp.get("max_speed_kmh", 70)))


static func ai_style_name(st_idx: int) -> String:
	var st := clampi(st_idx, 0, AI_STYLE_NAMES.size() - 1)
	return AI_STYLE_NAMES_EN[st] if L10n.is_en() else AI_STYLE_NAMES[st]


static func tram_ai_style_name(tr: Dictionary) -> String:
	return ai_style_name(int(tr.get("ai_style", AIStyle.NORMAL)))


func set_tram_ai_style(tram_idx: int, style: int) -> void:
	if tram_idx < 0 or tram_idx >= trams.size():
		return
	var tr: Dictionary = trams[tram_idx]
	var prev_style := int(tr.get("ai_style", AIStyle.NORMAL))
	var new_style := clampi(style, 0, 2)
	tr["ai_style"] = new_style
	if new_style != AIStyle.SLOW:
		if float(tr.get("ai_open_delay", 0.0)) > 0.0:
			tr["ai_open_delay"] = 0.0
			tr["doors_target_open"] = true
		tr["ai_close_grace"] = 0.0
	elif prev_style != AIStyle.SLOW and bool(tr.get("doors_target_open", false)):
		tr["ai_close_grace"] = 2.8


func set_active_tram_ai_style(style: int) -> void:
	if trams.is_empty():
		return
	active_tram_idx = posmod(active_tram_idx, trams.size())
	set_tram_ai_style(active_tram_idx, style)


func set_line_ai_style(line_id: int, style: int) -> int:
	if style < 0:
		line_ai_styles.erase(line_id)
		return 0
	var new_style := clampi(style, 0, 2)
	line_ai_styles[line_id] = new_style
	var count := 0
	for i in range(trams.size()):
		if int(trams[i].get("line_id", -1)) == line_id:
			set_tram_ai_style(i, new_style)
			count += 1
	return count


func set_active_line_ai_style(style: int) -> int:
	var tr := get_active_tram()
	if tr.is_empty():
		return 0
	return set_line_ai_style(int(tr.get("line_id", -1)), style)


# Returns the line's explicit group default AIStyle (0/1/2), or LINE_AI_NONE (-1) if no default is set.
func get_line_ai_style(line_id: int) -> int:
	if line_ai_styles.has(line_id):
		return clampi(int(line_ai_styles[line_id]), 0, 2)
	return LINE_AI_NONE


func get_line_ai_style_pref(line_id: int) -> int:
	return get_line_ai_style(line_id)


func set_tram_ai_max_kmh(tram_idx: int, kmh: int, is_custom: bool = true) -> int:
	if tram_idx < 0 or tram_idx >= trams.size():
		return 70
	var tr: Dictionary = trams[tram_idx]
	var spec_top := tram_spec_max_kmh(tr)
	var clamped := clampi(kmh, AI_MIN_MAX_KMH, spec_top)
	tr["ai_max_kmh"] = clamped
	tr["ai_max_custom"] = is_custom
	return clamped


func adjust_active_tram_ai_max_kmh(delta_kmh: int) -> int:
	if trams.is_empty():
		return 70
	active_tram_idx = posmod(active_tram_idx, trams.size())
	var tr: Dictionary = trams[active_tram_idx]
	var cur := int(tr.get("ai_max_kmh", tram_spec_max_kmh(tr)))
	return set_tram_ai_max_kmh(active_tram_idx, cur + delta_kmh, true)


func reset_active_tram_ai_max_kmh() -> int:
	if trams.is_empty():
		return 70
	active_tram_idx = posmod(active_tram_idx, trams.size())
	var tr: Dictionary = trams[active_tram_idx]
	return set_tram_ai_max_kmh(active_tram_idx, tram_spec_max_kmh(tr), false)


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


func get_line_route_len_m(lid: int) -> float:
	return float(line_route_len_m.get(lid, 0.0))


func get_line_avg_trip_seconds(lid: int) -> float:
	var cnt := int(line_trip_count.get(lid, 0))
	if cnt > 0:
		return float(line_trip_time_sum_s.get(lid, 0.0)) / float(cnt)
	return -1.0


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

	# Track real end-to-end terminal-to-terminal trip duration (or full circuit for pure circular loops)
	var lid := int(tr.get("line_id", -1))
	var is_pure_loop := bool(tr.get("is_loop", false)) and (tr.get("reversal_offsets", []) as Array).is_empty()
	if is_pure_loop:
		var rlen := float(tr.get("route_len", 0.0))
		if rlen > 10.0:
			var ldist := float(tr.get("trip_loop_dist_m", 0.0)) + spd * dt
			var lel := float(tr.get("trip_elapsed_s", 0.0)) + dt
			if ldist >= rlen:
				line_trip_time_sum_s[lid] = float(line_trip_time_sum_s.get(lid, 0.0)) + lel
				line_trip_count[lid] = int(line_trip_count.get(lid, 0)) + 1
				ldist -= rlen
				lel = 0.0
			tr["trip_loop_dist_m"] = ldist
			tr["trip_elapsed_s"] = lel
	else:
		var t_stage := str(tr.get("term_stage", ""))
		var t_sid := int(tr.get("term_sid", -1))
		if bool(tr.get("trip_active", false)):
			tr["trip_elapsed_s"] = float(tr.get("trip_elapsed_s", 0.0)) + dt
		if t_stage == "board_only" and t_sid >= 0:
			# Armed at departure terminus; starts fresh timer as it departs
			tr["trip_origin_sid"] = t_sid
			tr["trip_elapsed_s"] = 0.0
			tr["trip_active"] = true
		elif t_stage == "alight_only" and t_sid >= 0 and bool(tr.get("trip_active", false)):
			var orig_sid := int(tr.get("trip_origin_sid", -1))
			var el := float(tr.get("trip_elapsed_s", 0.0))
			if orig_sid >= 0 and t_sid != orig_sid and el >= 15.0:
				line_trip_time_sum_s[lid] = float(line_trip_time_sum_s.get(lid, 0.0)) + el
				line_trip_count[lid] = int(line_trip_count.get(lid, 0)) + 1
			tr["trip_active"] = false


# Where a train is and what it is doing, for the operations board
func tram_status_text(tr: Dictionary) -> String:
	if bool(tr.get("derailed", false)) or bool(tr.get("crashed", false)):
		return L10n.t("事故", "Incident")
	if bool(tr.get("held_manual", false)):
		return L10n.t("手动保留 · 停车待命", "Held (Manual) · Standby")
	var spd := float(tr["speed_mps"])
	var term_stage := str(tr.get("term_stage", ""))
	if term_stage == "flip_wait":
		return L10n.t("终点换端折返", "Changing Cab at Terminus")
	if float(tr.get("ai_open_delay", 0.0)) > 0.0:
		var here_w := _find_station_at_current_pos(tr)
		var hi_w := int(here_w.get("stop_idx", -1))
		var stops_w: Array = tr["stops"]
		var raw_w := str(stops_w[hi_w]["name"]) if hi_w >= 0 and hi_w < stops_w.size() else L10n.t("站台", "Platform")
		var disp_w := L10n.station_display_name(raw_w)
		return L10n.t("停站待开门 · %s", "Stopped (Opening) · %s") % disp_w
	if float(tr["door_ratio"]) > 0.02 or bool(tr["doors_target_open"]):
		var allow_unsched := (tr == get_active_tram() and manual_drive)
		var here := _find_station_at_current_pos(tr, allow_unsched, _graph_ref)
		var hi := int(here.get("stop_idx", -1))
		var hsid := int(here.get("station_id", -1))
		var stops_h: Array = tr["stops"]
		var st_nm_raw := str(stops_h[hi]["name"]) if hi >= 0 and hi < stops_h.size() else (
			str((_graph_ref.stations[hsid] as Dictionary).get("name", L10n.t("站台", "Platform"))) if (_graph_ref != null and _graph_ref.stations.has(hsid)) else L10n.t("站台", "Platform")
		)
		var st_nm_h := L10n.station_display_name(st_nm_raw)
		if bool(tr.get("express_waiting", false)):
			return L10n.t("待避快车（开门） · %s", "Yielding to Express (Doors Open) · %s") % st_nm_h
		if bool(tr.get("pacing_waiting", false)):
			return L10n.t("调距待发（开门） · %s", "Pacing Hold (Doors Open) · %s") % st_nm_h
		if bool(here.get("unscheduled", false)):
			return L10n.t("临时停靠 · %s", "Unscheduled Stop · %s") % st_nm_h
		return L10n.t("停站 · %s", "At Station · %s") % st_nm_h
	if float(tr.get("express_hold_t", 0.0)) > 0.0 or bool(tr.get("express_waiting", false)):
		return L10n.t("待避快车", "Yielding to Express")
	var nxt := find_next_stop_info(tr)
	var nxt_name := L10n.station_display_name(str(nxt.get("name", "")))
	if spd < 0.3:
		if float(tr.get("merge_hold_s", -1.0)) >= 0.0:
			return L10n.t("汇合让行", "Yielding at Merge")
		if _terminal_hold_distance(tr) < 40.0:
			return (L10n.t("等待终点站进站 → %s", "Waiting for Terminus → %s") % nxt_name) if nxt_name != "" else L10n.t("等待终点站进站", "Waiting for Terminus")
		return (L10n.t("停车等待 → %s", "Holding → %s") % nxt_name) if nxt_name != "" else L10n.t("停车等待", "Holding")
	return (L10n.t("开往 %s", "En route to %s") % nxt_name) if nxt_name != "" else L10n.t("运行中", "Running")


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
	_step_frame += 1
	operating_seconds += dt
	sound.overspeed_squeal = 0.0
	_update_terminal_interlocking()
	_switch_timer -= dt
	if _switch_timer <= 0.0:
		_switch_timer = 0.15
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

		# Cull & skip passenger rig animation on trams beyond 115m from active tram for top FPS!
		var secs: Array = tr["tram_info"]["sections"]
		var near_cam := (i == active_tram_idx) or (not secs.is_empty() and _is_near_active_tram(secs[0] as Node3D))
		TramBuilder.set_onboard_passengers_culled(
			tr["tram_info"] as Dictionary,
			not near_cam,
			(tr["pax_dests"] as Array).size(),
			int(tr["capacity"])
		)
		if near_cam:
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
		var dock := get_dock_info_for_tram(tr, graph, true)
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


func get_dock_info_for_tram(tr: Dictionary, graph: NetworkGraph, allow_unscheduled: bool = false) -> Dictionary:
	var near := _find_station_at_current_pos(tr, allow_unscheduled, graph)
	var sid := int(near["station_id"])
	if sid < 0 or graph == null or not graph.stations.has(sid):
		return {"has_station": false, "station_id": -1, "stop_idx": -1, "unscheduled": false}
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
	var curve_spec: Dictionary = {}
	if graph.has_meta("station_curve_specs"):
		var sc_map: Dictionary = graph.get_meta("station_curve_specs")
		if sc_map.has(sid):
			curve_spec = sc_map[sid]
	return {
		"has_station": true,
		"station_id": sid,
		"stop_idx": int(near["stop_idx"]),
		"unscheduled": bool(near.get("unscheduled", false)),
		"st_pos": st_pos,
		"st_fwd": st_fwd,
		"st_side": st_side,
		"plat_half_len": float(st.get("platform_len", 27.0)) * 0.5 - 0.45,
		"curve_spec": curve_spec,
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
			"zone_name": NetworkGraph.zone_label(0),
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

	# Scan up to 140m ahead for the upcoming lower speed restriction with the tightest braking envelope
	var next_lim := cur_lim
	var next_dist := 999.0
	var next_zk := 0
	var best_env_v2 := 1e18
	for k in range(2, 72):
		var raw_idx := idx_front + k * step_sign
		if not is_loop and (raw_idx < 0 or raw_idx >= n):
			break
		var ai := posmod(raw_idx, n) if is_loop else raw_idx
		var cand_lim := limits[ai]
		if cand_lim < cur_lim - 1.0:
			var dist_k := float(k) * NetworkGraph.PROFILE_STEP_M
			var cand_v := cand_lim / 3.6
			var env_v2 := cand_v * cand_v + 1.25 * maxf(0.0, dist_k - 8.0)
			if env_v2 < best_env_v2:
				best_env_v2 = env_v2
				next_lim = cand_lim
				next_dist = dist_k
				next_zk = int(zones[ai])

	return {
		"limit_kmh": cur_lim,
		"derail_kmh": cur_der,
		"zone_kind": cur_zk,
		"zone_name": NetworkGraph.zone_label(cur_zk),
		"curve_sign": cur_cs,
		"next_limit_kmh": next_lim,
		"next_dist_m": next_dist,
		"next_zone_name": NetworkGraph.zone_label(next_zk),
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
		return {"station_id": -1, "name": L10n.t("无车站", "No Stations"), "dist": 999.0, "stop_idx": -1, "is_terminal": false}

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


func get_upcoming_station_ids(tr: Dictionary, current_stop_idx: int, exclude_sid: int = -1) -> Array[int]:
	var stops: Array = tr.get("stops", [])
	var out: Array[int] = []
	if stops.is_empty():
		return out
	var is_loop := bool(tr["is_loop"])
	var dir := float(tr["dir"])

	if current_stop_idx < 0:
		# Manual unscheduled stop: start from the next scheduled stop ahead along our route (inclusive!)
		var s_now := float(tr["s"])
		var rlen := float(tr["route_len"])
		var best_idx := -1
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
		if best_idx < 0:
			return out
		if is_loop:
			for step in range(0, stops.size()):
				var idx := posmod(best_idx + step * int(signf(dir)), stops.size())
				var st_d: Dictionary = stops[idx]
				var sid_u := int(st_d["station_id"])
				if sid_u != exclude_sid and not out.has(sid_u):
					out.append(sid_u)
				if bool(st_d.get("turnback", false)):
					break
		else:
			if dir > 0.0:
				for idx in range(best_idx, stops.size()):
					var sid_u := int(stops[idx]["station_id"])
					if sid_u != exclude_sid and not out.has(sid_u):
						out.append(sid_u)
			else:
				var idx := best_idx
				while idx >= 0:
					var sid_u := int(stops[idx]["station_id"])
					if sid_u != exclude_sid and not out.has(sid_u):
						out.append(sid_u)
					idx -= 1
		return out

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

	var ai_style := clampi(int(tr.get("ai_style", AIStyle.NORMAL)), 0, 2)
	var door_r := float(tr["door_ratio"])
	var target_open := bool(tr["doors_target_open"])
	var spd := float(tr["speed_mps"])
	var open_delay := float(tr.get("ai_open_delay", 0.0))

	var depart_pending := bool(tr.get("ai_depart_pending", false))
	var term_stage := str(tr.get("term_stage", ""))
	if open_delay > 0.0 or target_open or door_r > 0.02 or depart_pending or term_stage == "flip_wait":
		tr["notch"] = 3
		if open_delay > 0.0:
			# Slow mode: wait ~2.5s after coming to a complete stop before opening the doors
			tr["speed_mps"] = 0.0
			open_delay = maxf(0.0, open_delay - dt)
			tr["ai_open_delay"] = open_delay
			if open_delay <= 0.0:
				tr["doors_target_open"] = true
				tr["dwell_elapsed"] = 0.0
				tr["pacing_hold_t"] = 0.0
				tr["pacing_waiting"] = false
				tr["ai_close_grace"] = 2.8 if ai_style == AIStyle.SLOW else 0.0
				if play_audio:
					sound.play_door_chime()
			return

		if term_stage == "flip_wait":
			# Brief realistic cab-change pause with doors closed after reversing ends, then open doors for return boarding!
			var ft := float(tr.get("term_flip_timer", 0.0)) - dt
			tr["term_flip_timer"] = ft
			if ft <= 0.0:
				tr["term_stage"] = "board_only"
				tr["dwell_timer"] = 5.2 if ai_style == AIStyle.SLOW else 4.2
				tr["dwell_elapsed"] = 0.0
				tr["pacing_hold_t"] = 0.0
				tr["pacing_waiting"] = false
				tr["ai_close_grace"] = 2.8 if ai_style == AIStyle.SLOW else 0.0
				if ai_style == AIStyle.SLOW:
					tr["ai_open_delay"] = 2.2
				else:
					tr["doors_target_open"] = true
					if play_audio:
						sound.play_door_chime()
			return

		tr["dwell_timer"] = float(tr["dwell_timer"]) - dt
		tr["dwell_elapsed"] = float(tr.get("dwell_elapsed", 0.0)) + dt
		var docked_now := _find_station_at_current_pos(tr)
		var docked_sid := int(docked_now["station_id"])
		var docked_idx := int(docked_now["stop_idx"])
		var upcoming_chk: Array[int] = []
		if docked_idx >= 0:
			upcoming_chk = get_upcoming_station_ids(tr, docked_idx)
		var has_room := ((tr["pax_dests"] as Array).size() + int(tr.get("pending_boarders", 0))) < int(tr["capacity"])
		var more_waiting := (docked_sid >= 0) and has_room and pax_sim.has_waiting_passengers_for_tram(docked_sid, tr, upcoming_chk)
		var walkers_still_boarding := pax_sim.has_walkers_boarding_tram(tr)

		var can_close := false
		if term_stage == "alight_only":
			# Phase 1 at reversing terminus: MUST evacuate 100% of onboard passengers (只下不上) before cab change!
			var onboard_left := (tr["pax_dests"] as Array).size()
			var doors_blocked := (door_r > 0.55 and int(tr.get("open_doorways", 0)) == 0)
			var ready_a := (float(tr["dwell_timer"]) <= 0.0) and (onboard_left == 0 or doors_blocked or float(tr["dwell_elapsed"]) >= 50.0)
			if ai_style == AIStyle.SLOW:
				if not ready_a or door_r < 0.85:
					tr["ai_close_grace"] = 2.2
					can_close = false
				else:
					var cg_a := maxf(0.0, float(tr.get("ai_close_grace", 2.2)) - dt)
					tr["ai_close_grace"] = cg_a
					can_close = (cg_a <= 0.0)
			else:
				tr["ai_close_grace"] = 0.0
				can_close = ready_a
		else:
			# Keep the doors open as long as people are actually boarding: someone waiting on the platform, room
			# on board and the last passenger in or out no more than BOARD_STALL_S ago. A stalled queue (e.g. no doorway lined
			# up with the platform) does not hold the train; walkers already heading for a door are let in.
			var elapsed := float(tr["dwell_elapsed"])
			var brd := int(tr.get("st_boarded", 0)) + int(tr.get("st_alighted", 0)) # alighting first counts as progress too
			if float(tr.get("ai_brd_t", 1e9)) > elapsed:
				tr["ai_brd_t"] = 0.0 # new stop: give boarding BOARD_STALL_S to get going
				tr["ai_brd_seen"] = brd
			if brd != int(tr.get("ai_brd_seen", brd)):
				tr["ai_brd_seen"] = brd
				tr["ai_brd_t"] = elapsed
			# In Slow mode, also wait for passengers who are hurrying up the station ramp/stairs toward the platform!
			var approaching_hold := (ai_style == AIStyle.SLOW) and (docked_sid >= 0) and has_room and pax_sim.has_approaching_passengers(docked_sid) and elapsed < 28.0
			if approaching_hold:
				tr["ai_brd_t"] = elapsed
			var stall_s := 3.2 if ai_style == AIStyle.SLOW else BOARD_STALL_S
			var boarding_on := more_waiting and elapsed - float(tr["ai_brd_t"]) < stall_s
			var walkers_hold := walkers_still_boarding and elapsed < 90.0
			var hold_sid := int(tr.get("term_sid", docked_sid))
			if hold_sid < 0:
				hold_sid = docked_sid
			# Local tram keeps doors OPEN while waiting for an express tram to overtake / depart first
			# (both at 4-track twin-island stations and at multi-platform terminals!)
			var express_hold := false
			if hold_sid >= 0 and target_open:
				express_hold = _holding_for_express(tr, my_idx, hold_sid, graph, dt)
			var pacing_hold := false
			if hold_sid >= 0 and target_open and not express_hold:
				pacing_hold = _holding_for_pacing(tr, my_idx, hold_sid, dt)
			else:
				tr["pacing_waiting"] = false
			var busy_now := (float(tr["dwell_timer"]) > 0.0) or boarding_on or walkers_hold or approaching_hold or express_hold or pacing_hold
			if ai_style == AIStyle.SLOW:
				if busy_now or door_r < 0.85:
					tr["ai_close_grace"] = 2.8
					can_close = false
				else:
					var cg := maxf(0.0, float(tr.get("ai_close_grace", 2.8)) - dt)
					tr["ai_close_grace"] = cg
					can_close = (cg <= 0.0)
			else:
				tr["ai_close_grace"] = 0.0
				can_close = not busy_now

		if can_close and target_open:
			tr["doors_target_open"] = false
			tr["ai_depart_pending"] = true # Act once doors are shut (frame-rate independent)
			if play_audio:
				sound.play_door_chime()
		elif not target_open and door_r <= 0.03:
			var docked := _find_station_at_current_pos(tr)
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
					tr["term_flip_timer"] = 1.40 if ai_style == AIStyle.SLOW else 0.85
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
			if dep_sid >= 0 and _holding_for_express(tr, my_idx, dep_sid, graph, dt):
				# An express entered the yield window while doors were closing: re-open doors and wait!
				tr["doors_target_open"] = true
				tr["ai_depart_pending"] = false
				tr["notch"] = 3
				if play_audio:
					sound.play_door_chime()
				return
			tr["ai_depart_pending"] = false
			tr["express_hold_t"] = 0.0
			tr["express_waiting"] = false
			tr["express_hold_done"] = -1.0
			tr["pacing_hold_t"] = 0.0
			tr["pacing_waiting"] = false
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
			tr["depart_cooldown"] = 9.0 if ai_style == AIStyle.SLOW else (5.2 if ai_style == AIStyle.FURIOUS else 8.5)
			# Furious mode pulls straight to full P4 on departure; Slow/Normal step smoothly from P1
			tr["notch"] = (NOTCH_NEUTRAL + 4) if ai_style == AIStyle.FURIOUS else (NOTCH_NEUTRAL + 1)
			tr["ai_notch_timer"] = 0.0
			tr["ai_last_step_dir"] = 1
			tr["ai_cruising_coast"] = false
			tr["ai_crawl_active"] = false
		return

	var spec: Dictionary = tr["spec"]
	var max_decel := maxf(0.6, float(spec.get("decel", 1.35)))
	var eff_decel := max_decel * (1.75 if ai_style == AIStyle.FURIOUS else 1.0)
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
			var th_fac := 0.80 if ai_style == AIStyle.FURIOUS else (0.48 if ai_style == AIStyle.SLOW else 0.62)
			v_env = minf(v_env, sqrt(2.0 * eff_decel * th_fac * d_th))
			if term_hold_d < 155.0:
				var a_th := (spd * spd) / (2.0 * d_th)
				if a_th > eff_decel * 1.05:
					_apply_ai_notch_command(tr, 0, dt, 2)
					return
				if a_th > req_decel:
					req_decel = a_th
				if a_th > eff_decel * 0.45:
					brake_urgency = maxi(brake_urgency, 1)
				if term_hold_d < 52.0:
					hard_stop_ahead = true

	# 1. Tram ahead on path: brake smoothly to stop ~9m behind it
	var gap_ahead := _distance_to_tram_ahead(tr, my_idx)
	if gap_ahead < 900.0:
		var gap_room := gap_ahead - 9.0
		if gap_room <= 1.0:
			must_hold_stop = true
		else:
			var d_gap := maxf(0.5, gap_room)
			var gap_fac := 0.76 if ai_style == AIStyle.FURIOUS else (0.45 if ai_style == AIStyle.SLOW else 0.56)
			var safe_v := sqrt(2.0 * eff_decel * gap_fac * d_gap)
			v_env = minf(v_env, safe_v)
			if gap_room < 14.0 and spd > safe_v + 2.2:
				_apply_ai_notch_command(tr, 0, dt, 2) # Immediate EB if critically closing on tram ahead
				return
			var a_gap := (spd * spd) / (2.0 * d_gap)
			if gap_room < 145.0 and a_gap > req_decel:
				req_decel = a_gap
			if a_gap > eff_decel * 0.48:
				brake_urgency = maxi(brake_urgency, 1)
			if gap_room < 48.0:
				hard_stop_ahead = true

	# 2. Dedicated Tram Signal ('━' Stop / '●' Yellow) + Road Hazard Emergency Avoidance
	var intersection_cap_mps := 99.0
	if traffic_sim != null:
		var sig_look := clampf(maxf(120.0, (spd * spd) / maxf(0.5, eff_decel * 0.85) + 42.0), 120.0, 220.0)
		var sig_info := traffic_sim.get_upcoming_tram_signal(tr, graph, sig_look)
		if bool(sig_info["has_signal"]):
			var sig_d := float(sig_info["dist"])
			var stop_line := float(sig_info.get("stop_line", 11.8))
			var sig_aspect := str(sig_info["aspect"])
			if sig_aspect != "green":
				var d_to_stop_line := sig_d - stop_line
				var must_obey := false
				if sig_aspect == "red":
					# Strictly obey RED whenever our nose has not yet crossed into the intersection box
					must_obey = d_to_stop_line >= -1.5
				else:
					# Yellow clearance: stop before stop line unless already at speed right on top of the line
					# and able to clear it well before red (dilemma zone).
					var stop_d_y := (spd * spd) / maxf(0.5, 2.0 * eff_decel * 1.05)
					var in_dilemma := spd > 4.0 and d_to_stop_line < stop_d_y * 0.55 and (d_to_stop_line / maxf(spd, 1.0)) < 1.15
					must_obey = (d_to_stop_line >= -0.8) and (not in_dilemma)
				if must_obey:
					if d_to_stop_line <= 2.4:
						must_hold_stop = true
					else:
						var d_sig := maxf(0.5, d_to_stop_line - 1.5)
						var sig_fac := 0.80 if ai_style == AIStyle.FURIOUS else (0.52 if ai_style == AIStyle.SLOW else 0.68)
						v_env = minf(v_env, sqrt(2.0 * eff_decel * sig_fac * d_sig))
						var a_sig := (spd * spd) / (2.0 * d_sig)
						if a_sig > eff_decel * 1.02:
							# Emergency track brake so a sudden yellow/red at high speed NEVER runs a red light!
							_apply_ai_notch_command(tr, 0, dt, 2)
							return
						if a_sig > req_decel:
							req_decel = a_sig
						if a_sig > eff_decel * 0.40 or d_to_stop_line < 22.0:
							brake_urgency = maxi(brake_urgency, 1)
						if d_to_stop_line < 58.0:
							hard_stop_ahead = true
			elif ai_style != AIStyle.FURIOUS:
				var int_kmh := 22.0 if ai_style == AIStyle.SLOW else 26.0
				if sig_d > stop_line and sig_d <= 44.0:
					# Smooth defensive intersection approach cap (22 km/h in Slow, 26 km/h in Normal; Furious runs at track limit on green)
					intersection_cap_mps = int_kmh / 3.6
				elif sig_d > 44.0 and sig_d <= 72.0:
					# Gently ramp down envelope before the 44m intersection zone so we coast instead of brake-chattering
					var d_int := maxf(1.0, sig_d - 42.0)
					var v_int := int_kmh / 3.6
					v_env = minf(v_env, sqrt(v_int * v_int + 2.0 * eff_decel * 0.35 * d_int))

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

	var stop_snap_spd := 1.15 if ai_style == AIStyle.FURIOUS else 0.55
	var stop_snap_d := 3.2 if ai_style == AIStyle.FURIOUS else 3.8
	if float(tr["depart_cooldown"]) <= 0.0 and ((dist_ahead <= stop_snap_d and spd < stop_snap_spd) or (at_track_end and spd < 0.35)):
		tr["speed_mps"] = 0.0
		tr["notch"] = 3 # Steady B2 platform holding brake
		tr["ai_notch_timer"] = 0.0
		tr["ai_cruising_coast"] = true
		tr["ai_crawl_active"] = false
		var arrived_st := _find_station_at_current_pos(tr)
		var arr_idx := int(arrived_st["stop_idx"])
		var arr_sid := int(arrived_st["station_id"])
		if _is_turnback_stop(tr, arr_idx):
			if _on_terminal_departure_side(tr, arr_sid):
				tr["term_stage"] = "board_only"
				tr["term_sid"] = arr_sid
				tr["dwell_timer"] = 5.2 if ai_style == AIStyle.SLOW else 4.2
			else:
				tr["term_stage"] = "alight_only"
				tr["term_sid"] = arr_sid
				var empty_now := (tr["pax_dests"] as Array).is_empty()
				if ai_style == AIStyle.SLOW:
					tr["dwell_timer"] = 2.4 if empty_now else 3.2
				else:
					tr["dwell_timer"] = 1.8 if empty_now else 2.4
		else:
			tr["term_stage"] = ""
			tr["term_sid"] = -1
			tr["dwell_timer"] = 5.4 if ai_style == AIStyle.SLOW else 4.6
		tr["dwell_elapsed"] = 0.0
		tr["pacing_hold_t"] = 0.0
		tr["pacing_waiting"] = false
		if ai_style == AIStyle.SLOW:
			# Slow mode: pause 2.5 seconds after stopping at the platform before opening doors
			tr["ai_open_delay"] = 2.5
			tr["ai_close_grace"] = 2.8
			tr["doors_target_open"] = false
		else:
			tr["ai_open_delay"] = 0.0
			tr["ai_close_grace"] = 0.0
			tr["doors_target_open"] = true
			if play_audio:
				sound.play_door_chime()
		return

	# Hard hold at red signal / terminal interlocking / tram ahead
	if must_hold_stop:
		tr["ai_cruising_coast"] = true
		tr["ai_crawl_active"] = false
		if spd < 0.55:
			tr["speed_mps"] = 0.0
			_apply_ai_notch_command(tr, 3, dt, 2) # Immediate B2 holding brake once stopped
		elif spd > 2.6:
			_apply_ai_notch_command(tr, 0, dt, 2) # Immediate EB so we never slide past the stop line
		else:
			_apply_ai_notch_command(tr, 1, dt, 2) # Immediate B4 to stop cleanly behind stop line
		return

	# 3. Proactive Curve/Turnout, Intersection & Per-Train AI Max Speed Limits
	var lim_info := get_speed_limit_status(tr)
	tr["_lim_stat"] = lim_info
	tr["_lim_stat_frame"] = _step_frame
	var spec_max_kmh := float(spec.get("max_speed_kmh", 70))
	var user_max_kmh := clampf(float(tr.get("ai_max_kmh", spec_max_kmh)), float(AI_MIN_MAX_KMH), spec_max_kmh)
	var user_cap_mps := user_max_kmh / 3.6
	var lim_margin_kmh := 4.5 if ai_style == AIStyle.SLOW else (2.5 if ai_style == AIStyle.FURIOUS else 2.8)
	var track_lim_mps := maxf(5.0, float(lim_info["limit_kmh"]) - lim_margin_kmh) / 3.6
	var allowed_mps := minf(user_cap_mps, minf(track_lim_mps, intersection_cap_mps))
	var next_lim_mps := minf(user_cap_mps, maxf(5.0, float(lim_info["next_limit_kmh"]) - lim_margin_kmh) / 3.6)
	var next_lim_dist := float(lim_info["next_dist_m"])
	var coast_for_upcoming_limit := false
	if next_lim_dist < 142.0 and next_lim_mps < allowed_mps:
		var lead_pad := 6.0 if ai_style == AIStyle.FURIOUS else (12.0 if ai_style == AIStyle.SLOW else 10.0)
		var lim_decel_fac := 0.78 if ai_style == AIStyle.FURIOUS else (0.36 if ai_style == AIStyle.SLOW else 0.48)
		var d_lim := maxf(1.5, next_lim_dist - lead_pad)
		var v_lim_env := sqrt(next_lim_mps * next_lim_mps + 2.0 * eff_decel * lim_decel_fac * d_lim)
		v_env = minf(v_env, v_lim_env)
		if spd > next_lim_mps + 0.2:
			var a_lim := (spd * spd - next_lim_mps * next_lim_mps) / (2.0 * d_lim)
			if a_lim > req_decel:
				req_decel = a_lim
			if a_lim > eff_decel * 0.46:
				brake_urgency = maxi(brake_urgency, 1)
		var coast_d := 18.0 if ai_style == AIStyle.FURIOUS else 42.0
		if next_lim_dist < coast_d and spd >= next_lim_mps - 0.6:
			coast_for_upcoming_limit = true

	var over_tol := 0.45 if ai_style == AIStyle.FURIOUS else 0.35
	if spd > allowed_mps + over_tol:
		var over_v := spd - allowed_mps
		var a_over := clampf(over_v * (0.95 if ai_style == AIStyle.FURIOUS else 0.55), eff_decel * 0.28, eff_decel)
		if a_over > req_decel:
			req_decel = a_over
		if over_v > 0.6:
			brake_urgency = maxi(brake_urgency, 1)

	# 4. Station Approach Braking Curve (smooth service braking + high-efficiency late braking in Furious mode)
	var station_final_stop := false
	var st_decel_fac := 0.84 if ai_style == AIStyle.FURIOUS else (0.36 if ai_style == AIStyle.SLOW else 0.48)
	if float(tr["depart_cooldown"]) <= 0.0 and dist_ahead < 165.0:
		var d_st := maxf(0.5, dist_ahead - (0.6 if ai_style == AIStyle.FURIOUS else 1.0))
		var v_st_env := sqrt(2.0 * eff_decel * st_decel_fac * d_st)
		v_env = minf(v_env, v_st_env)
		var a_st := (spd * spd) / (2.0 * d_st)
		if dist_ahead <= 2.4:
			station_final_stop = true
			approaching_station = true
		elif a_st > eff_decel * (0.42 if ai_style == AIStyle.FURIOUS else 0.17) or dist_ahead < (spd * spd) / maxf(0.4, 2.0 * eff_decel * st_decel_fac) + (3.2 if ai_style == AIStyle.FURIOUS else 9.0):
			approaching_station = true
			if a_st > req_decel:
				req_decel = a_st
			if a_st > eff_decel * (0.58 if ai_style == AIStyle.FURIOUS else 0.65):
				brake_urgency = maxi(brake_urgency, 1)

	# 5. Select Steady Desired Notch with Non-Overlapping Hysteresis (Real Tram Power -> Coast -> Step-Brake Behavior)
	var desired_notch := NOTCH_NEUTRAL
	var cmd_urgency := brake_urgency

	if station_final_stop:
		tr["ai_cruising_coast"] = true
		tr["ai_crawl_active"] = false
		if ai_style == AIStyle.FURIOUS:
			desired_notch = 1 if spd > 2.2 else (2 if spd > 1.2 else 3)
			cmd_urgency = maxi(cmd_urgency, 2 if spd > 2.2 else 1)
		else:
			desired_notch = 2 if spd > 2.2 else 3 # Smooth B2 stop right onto the platform mark
			cmd_urgency = maxi(cmd_urgency, 1 if spd > 2.2 else 0)
	elif req_decel > eff_decel * (0.20 if ai_style == AIStyle.FURIOUS else 0.22) or (cur_notch < NOTCH_NEUTRAL and req_decel > eff_decel * 0.06):
		# Active proportional service braking with strict non-overlapping release thresholds
		# so easing off a brake notch NEVER immediately bounces back into the stronger notch!
		tr["ai_cruising_coast"] = true
		tr["ai_crawl_active"] = false
		var net_req := maxf(0.0, req_decel - drag_est * 0.65)
		var ratio := net_req / eff_decel
		var ideal_b := 4 # B1
		if ai_style == AIStyle.FURIOUS:
			# Furious mode: match actual high-deceleration notch capacity so it holds speed late and stops sharply on the mark!
			if ratio >= 0.84:
				ideal_b = 1 # B4
			elif ratio >= 0.58:
				ideal_b = 2 # B3
			elif ratio >= 0.34:
				ideal_b = 3 # B2
			else:
				ideal_b = 4 # B1
			cmd_urgency = maxi(cmd_urgency, 1)
		else:
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
			var cur_eff := float(NOTCH_NEUTRAL - cur_notch) * 0.25 * eff_decel + drag_est * 0.65
			var release_thresh := 0.05 * eff_decel
			if cur_notch == 1:
				release_thresh = 0.64 * eff_decel # B4 -> B3 only once B3 can easily handle it
			elif cur_notch == 2:
				release_thresh = 0.39 * eff_decel # B3 -> B2 only once B2 can easily handle it
			elif cur_notch == 3:
				release_thresh = 0.16 * eff_decel # B2 -> B1 only once B1 can easily handle it
			if req_decel > cur_eff + eff_decel * 0.12:
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
		var base_cruise := user_cap_mps
		var is_grade_sep := bool(tr.get("elevated", false)) or bool(tr.get("grade_sep", false))
		if ai_style == AIStyle.SLOW and not bool(tr.get("ai_max_custom", false)):
			base_cruise = minf(user_cap_mps, (spec_max_kmh * 0.72 / 3.6) if is_grade_sep else (minf(spec_max_kmh * 0.56, 38.0) / 3.6))
		elif ai_style == AIStyle.NORMAL and not bool(tr.get("ai_max_custom", false)):
			base_cruise = minf(user_cap_mps, (spec_max_kmh * 0.90 / 3.6) if is_grade_sep else (minf(spec_max_kmh * 0.68, 48.0) / 3.6))
		var target_mps := minf(base_cruise, minf(allowed_mps, v_env))

		var crawl_zone_d := 6.5 if ai_style == AIStyle.FURIOUS else 22.0
		if ((approaching_station and ai_style != AIStyle.FURIOUS) or (float(tr["depart_cooldown"]) <= 0.0 and dist_ahead < crawl_zone_d)) and not hard_stop_ahead:
			# Stopped slightly short of the platform mark: brisk pull-in in Furious, gentle P1 crawl in Normal/Slow
			var crawling := bool(tr.get("ai_crawl_active", false))
			var crawl_lo := 2.2 if ai_style == AIStyle.FURIOUS else 0.85
			var crawl_hi := 3.4 if ai_style == AIStyle.FURIOUS else 1.85
			if not crawling and spd < crawl_lo and dist_ahead > 3.0:
				crawling = true
			elif crawling and (spd >= crawl_hi or dist_ahead <= 2.6):
				crawling = false
			tr["ai_crawl_active"] = crawling
			desired_notch = (NOTCH_NEUTRAL + 3 if ai_style == AIStyle.FURIOUS else NOTCH_NEUTRAL + 1) if crawling else NOTCH_NEUTRAL
		else:
			tr["ai_crawl_active"] = false
			var coasting := bool(tr.get("ai_cruising_coast", false))
			var coast_top_margin := 0.22 if ai_style == AIStyle.SLOW else (0.25 if ai_style == AIStyle.FURIOUS else 0.20)
			var coast_resume_drop := 1.95 if ai_style == AIStyle.SLOW else (1.90 if ai_style == AIStyle.FURIOUS else 1.65)
			if hard_stop_ahead or coast_for_upcoming_limit or spd >= target_mps - coast_top_margin or target_mps < 1.2:
				coasting = true
			elif spd < target_mps - coast_resume_drop:
				coasting = false
			tr["ai_cruising_coast"] = coasting

			if coasting:
				desired_notch = NOTCH_NEUTRAL
			else:
				var dv := target_mps - spd
				if ai_style == AIStyle.FURIOUS:
					# Furious mode: hold steady full P4 all the way to cruise then cut cleanly to N (zero P4<->P3 chatter!)
					if cur_notch == 9:
						desired_notch = 9
					elif cur_notch == 8:
						desired_notch = 9 if dv > 3.2 else 8
					else:
						desired_notch = 9 if dv > 2.2 else 8
				elif ai_style == AIStyle.SLOW:
					# Slow mode: gentle P1 / P2 acceleration
					desired_notch = 7 if dv > 1.8 else 6
				elif cur_notch >= 6 and cur_notch <= 8:
					# Normal mode: Power-notch hysteresis so P3 -> P2 -> P1 steps down smoothly as speed approaches cruise
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

	var ai_style := clampi(int(tr.get("ai_style", AIStyle.NORMAL)), 0, 2)
	var last_dir := int(tr.get("ai_last_step_dir", 0))
	var is_reversal := (last_dir != 0 and step_dir != last_dir)
	var min_wait := 0.55 # Calm, realistic ~0.55s per notch step during normal driving
	if ai_style == AIStyle.FURIOUS:
		if urgency == 1 and step_dir < 0:
			# Crisp, authoritative braking when approaching stations, curves, or red signals
			min_wait = 0.28 if is_reversal else 0.14
		elif cur > NOTCH_NEUTRAL and clamped_target == NOTCH_NEUTRAL:
			# Clean cut from Power -> Coast once cruise speed is reached
			min_wait = 0.15
		elif cur == NOTCH_NEUTRAL and clamped_target > NOTCH_NEUTRAL:
			# After coasting down ~5.5 km/h, smoothly re-apply strong power (never chatter N <-> P4)
			min_wait = 0.90 if is_reversal else 0.35
		elif is_reversal:
			min_wait = 0.95
		else:
			min_wait = 0.45
	elif ai_style == AIStyle.SLOW:
		if urgency == 1 and step_dir < 0:
			min_wait = 0.75 if is_reversal else 0.42
		elif is_reversal:
			min_wait = 1.35
		else:
			min_wait = 0.75
	else:
		if urgency == 1 and step_dir < 0:
			# Active safety braking: crisp 0.35s per notch step (or 0.65s if just reversed)
			min_wait = 0.65 if is_reversal else 0.35
		elif is_reversal:
			# Prevent back-and-forth chatter: require a full 1.10s human dwell before reversing lever direction
			min_wait = 1.10

	if timer < min_wait:
		return

	var step_size := 4 if ai_style == AIStyle.FURIOUS else 1
	var next_n := cur + step_dir * mini(step_size, absi(clamped_target - cur))
	# Like a real master controller detent, cutting Power off to Coast/Brake pulls cleanly to Neutral (N) in one motion
	if cur > NOTCH_NEUTRAL and clamped_target <= NOTCH_NEUTRAL:
		next_n = clamped_target if ai_style == AIStyle.FURIOUS else NOTCH_NEUTRAL

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
		if oth_secs.is_empty() or not is_instance_valid(oth_secs[0]):
			continue
		if (oth_secs[0] as Node3D).global_position.distance_squared_to(my_pos) > 215.0 * 215.0:
			continue
		var oth_hl := float(trams[j]["tram_info"].get("section_len", 9.2)) * 0.5 - 0.8
		for sec: Node3D in oth_secs:
			if not is_instance_valid(sec):
				continue
			var gp := sec.global_position
			if gp.distance_squared_to(my_pos) < 175.0 * 175.0:
				var sf := -sec.global_transform.basis.z
				var sf2 := Vector2(sf.x, sf.z).normalized()
				for mul: float in [-oth_hl, 0.0, oth_hl]:
					cands.append(Vector2(gp.x, gp.z) + sf2 * mul)
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
		var min_d2 := 1e12
		for c: Vector2 in cands:
			var d2 := c.distance_squared_to(p2)
			if d2 < 1.7 * 1.7:
				return maxf(0.5, k - front_overhang - 1.4)
			if d2 < min_d2:
				min_d2 = d2
		k += maxf(1.0, floorf((sqrt(min_d2) - 1.75) * 0.95))
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
	var ai_style := clampi(int(tr.get("ai_style", AIStyle.NORMAL)), 0, 2)
	var target_r := 1.0 if bool(tr["doors_target_open"]) else 0.0
	var door_r := float(tr["door_ratio"])
	var dock_info: Dictionary = {}
	if absf(door_r - target_r) > 0.001 or door_r > 0.001:
		dock_info = get_dock_info_for_tram(tr, graph, _is_player_manual)
		var door_spd := 0.78
		if not _is_player_manual:
			door_spd = 0.52 if ai_style == AIStyle.SLOW else 0.78
		door_r = move_toward(door_r, target_r, dt * door_spd)
		tr["door_ratio"] = door_r
		var d_res := TramBuilder.update_doors(tinfo, door_r, dock_info)
		tr["open_doorways"] = int(d_res.get("open_doorways", 0))
		tr["total_doorways"] = int(d_res.get("total_doorways", 1))
	else:
		tr["open_doorways"] = 0

	if door_r > 0.55 and float(tr["speed_mps"]) < 0.30 and int(tr.get("open_doorways", 0)) > 0:
		if dock_info.is_empty():
			dock_info = get_dock_info_for_tram(tr, graph, _is_player_manual)
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
				var upcoming_b := get_upcoming_station_ids(tr, dock_idx, dock_sid)
				pax_sim.exchange_passengers_at_station(tr, dock_sid, upcoming_b, dt, false, true, false)
			else:
				var upcoming := get_upcoming_station_ids(tr, dock_idx, dock_sid)
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
		var acc_mul := 1.0
		if not _is_player_manual:
			if ai_style == AIStyle.FURIOUS:
				taper = clampf(1.0 - pow(spd / maxf(1.0, max_spd_mps), 6.0), 0.35, 1.0)
				acc_mul = 1.85
			elif ai_style == AIStyle.SLOW:
				acc_mul = 0.88
		cmd_acc = max_accel * acc_mul * p_lvl * taper
		effort = p_lvl
	elif notch < NOTCH_NEUTRAL:
		if notch == 0:
			cmd_acc = -max_decel * 3.40 # Full Electromagnetic Track-Brake Emergency Stop!
			effort = -1.0
		else:
			var b_lvl := float(NOTCH_NEUTRAL - notch) / 4.0
			var dec_mul := 1.75 if (not _is_player_manual and ai_style == AIStyle.FURIOUS) else 1.0
			cmd_acc = -max_decel * dec_mul * b_lvl
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
	var lim_stat: Dictionary = tr["_lim_stat"] if (int(tr.get("_lim_stat_frame", -1)) == _step_frame and tr.has("_lim_stat")) else get_speed_limit_status(tr)
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
					if absf(pa3.y - pb3.y) >= 3.5:
						continue # vertically grade-separated (viaduct over surface or tunnel under surface)
					if pa3.distance_squared_to(pb3) > 95.0:
						continue
					var fb3 := -sb.global_transform.basis.z
					var pb2 := Vector2(pb3.x, pb3.z)
					var fb2 := Vector2(fb3.x, fb3.z).normalized()
					if TrafficSim.obb_overlap_2d(pa2, fa2, hla, hwa, pb2, fb2, hlb, hwb):
						# Closing speed from the two velocity vectors: a rear-end hit is the speed difference, head-on the sum
						var rel_kmh := (_world_velocity(tr_a) - _world_velocity(tr_b)).length() * 3.6
						tr_a["crashed"] = true; tr_a["speed_mps"] = 0.0
						tr_b["crashed"] = true; tr_b["speed_mps"] = 0.0
						_apply_collision_jolt(tr_a, 1.0)
						_apply_collision_jolt(tr_b, -1.0)
						return {
							"hit": true,
							"tram_idx": i,
							"other_tram_idx": j,
							"world_pos": (pa3 + pb3) * 0.5,
							"speed_kmh": rel_kmh,
						}
	return {"hit": false}


# Horizontal velocity of a train along its route (direction of travel, including reverse gear)
static func _world_velocity(tr: Dictionary) -> Vector2:
	var spd := float(tr["speed_mps"])
	if spd < 0.01:
		return Vector2.ZERO
	var curve: Curve3D = tr["curve"]
	var rlen := float(tr["route_len"])
	var mv := float(tr["dir"]) * float(tr.get("reverser", 1.0))
	var s0 := float(tr["s"])
	var s1 := s0 + mv * 1.0
	if bool(tr["is_loop"]):
		s1 = fposmod(s1, rlen)
	else:
		s1 = clampf(s1, 0.0, rlen)
	var d := curve.sample_baked(s1, false) - curve.sample_baked(s0, false)
	var d2 := Vector2(d.x, d.z)
	if d2.length() < 0.001:
		return Vector2.ZERO
	return d2.normalized() * spd


static func _apply_collision_jolt(tr: Dictionary, side: float) -> void:
	var secs: Array = tr["tram_info"]["sections"]
	if not secs.is_empty() and is_instance_valid(secs[0]):
		var s0 := secs[0] as Node3D
		s0.rotate_y(deg_to_rad(9.5 * side))
		s0.rotate_object_local(Vector3.FORWARD, deg_to_rad(6.5 * side))


func _find_station_at_current_pos(tr: Dictionary, allow_unscheduled: bool = false, graph: NetworkGraph = null) -> Dictionary:
	var stops: Array = tr.get("stops", [])

	# During post-flip terminal boarding ("board_only" / "flip_wait"), keep locked to the exact terminal stop
	var t_stage := str(tr.get("term_stage", ""))
	var t_sid := int(tr.get("term_sid", -1))
	if (t_stage == "board_only" or t_stage == "flip_wait") and t_sid >= 0:
		for i in range(stops.size()):
			if int(stops[i]["station_id"]) == t_sid:
				return {"station_id": t_sid, "stop_idx": i, "unscheduled": false}

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
		return {"station_id": int(stops[best_idx]["station_id"]), "stop_idx": best_idx, "unscheduled": false}

	var tinfo: Dictionary = tr.get("tram_info", {})
	var secs: Array = tinfo.get("sections", [])
	for i in range(stops.size()):
		var st_pos: Vector3 = stops[i]["pos"]
		for sec: Node3D in secs:
			if is_instance_valid(sec) and Vector2(sec.global_position.x - st_pos.x, sec.global_position.z - st_pos.z).length() <= 21.0:
				return {"station_id": int(stops[i]["station_id"]), "stop_idx": i, "unscheduled": false}

	# Manual driving: allow stopping & opening doors at ANY physical station along the tracks (even unscheduled ones!)
	if allow_unscheduled and graph != null and not secs.is_empty():
		var tr_elev := bool(tr.get("elevated", false))
		var sec_len := float(tinfo.get("section_len", 9.2))
		var best_sid := -1
		var best_u_score := 1e9
		for sid_u: int in graph.stations.keys():
			var st_u: Dictionary = graph.stations[sid_u]
			if bool(st_u.get("elevated", false)) != tr_elev:
				continue
			var sp_u: Vector3 = st_u["pos"]
			var sf_u := (st_u["fwd"] as Vector3).normalized()
			var sf2 := Vector2(sf_u.x, sf_u.z).normalized()
			var sr2 := Vector2(-sf2.y, sf2.x)
			var half_l := float(st_u.get("platform_len", 27.0)) * 0.5
			for sec_u: Node3D in secs:
				if not is_instance_valid(sec_u):
					continue
				var dv2 := Vector2(sec_u.global_position.x - sp_u.x, sec_u.global_position.z - sp_u.z)
				var along := absf(dv2.dot(sf2))
				var lat := absf(dv2.dot(sr2))
				if along <= half_l + sec_len * 0.5 + 1.5 and lat <= 11.5:
					var sc := lat * 2.0 + along
					if sc < best_u_score:
						best_u_score = sc
						best_sid = sid_u
		if best_sid >= 0:
			return {"station_id": best_sid, "stop_idx": -1, "unscheduled": true}

	return {"station_id": -1, "stop_idx": -1, "unscheduled": false}


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
		if k == 0:
			var rel_y := mid.y - Terrain.surface(mid.x, mid.z)
			tr["rel_y"] = rel_y
			tr["grade_sep"] = bool(tr.get("elevated", false)) or rel_y > 3.5 or rel_y < -2.0

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
			# A departing train on platform A crosses the diamond into platform B: block B arrivals once A has
			# entered its "out" phase (unless a manual driver is standing still on A). While A is still dwelling
			# ("dwell"), an arriving train may pull into B freely.
			var is_man_stopped := (bool(trams[j].get("held_manual", false)) or (j == active_tram_idx and manual_drive)) and float(trams[j]["speed_mps"]) < 0.3
			if str(r["phase"]) == "out" and not is_man_stopped:
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
	# PASS 1: Maintain existing reservations AND register every tram already physically inside a terminal zone
	# (arriving on first_eval or on the departure/turnback side) BEFORE any approaching tram queries occupancy.
	# This eliminates index-order races after save reloads / fleet rebuilds where a lower-index approaching tram
	# could otherwise steal an occupied platform from a higher-index tram already sitting at the terminus.
	var requests: Array = [] # {dist, idx, sid}
	for i in range(trams.size()):
		var tr: Dictionary = trams[i]
		tr["term_hold_s"] = -1.0
		if not bool(tr["is_loop"]) or bool(tr.get("crashed", false)) or bool(tr.get("derailed", false)):
			tr["term_init_done"] = true
			continue
		var res: Dictionary = tr["term_res"]
		var first_eval := not bool(tr.get("term_init_done", false))
		var t_stage := str(tr.get("term_stage", ""))
		var is_dwelling_now := bool(tr["doors_target_open"]) or float(tr["door_ratio"]) > 0.05 \
			or t_stage == "alight_only" or t_stage == "flip_wait" or t_stage == "board_only"
		for z: Dictionary in (tr["terminal_zones"] as Array).duplicate():
			var rlen := float(tr["route_len"])
			var dir := float(tr["dir"])
			var s_now := float(tr["s"])
			var sid := int(z["station_id"])
			var hold_s := float(z["hold_s"])
			var cusp_s := float(z["cusp_s"])
			var exit_s := float(z["exit_s"])
			var arr_len := fposmod((cusp_s - hold_s) * dir, rlen)
			var dep_len := fposmod((exit_s - cusp_s) * dir, rlen) + _consist_length(tr) + 4.0
			var from_hold := fposmod((s_now - hold_s) * dir, rlen)
			var from_cusp := fposmod((s_now - cusp_s) * dir, rlen)
			var in_arr := from_hold <= arr_len + 0.5
			var in_dep := (not in_arr) and from_cusp <= dep_len
			if res.has(sid):
				var r: Dictionary = res[sid]
				if str(r["phase"]) == "out":
					if not in_dep and not in_arr:
						res.erase(sid) # Tail has fully cleared the crossover: release the platform track
				elif str(r["phase"]) == "in":
					if bool(tr["doors_target_open"]) or (float(tr["speed_mps"]) < 0.1 and fposmod((cusp_s - s_now) * dir, rlen) < 6.0 + float(z.get("stop_back", 0.0))):
						r["phase"] = "dwell"
				continue
			if (first_eval and in_arr) or in_dep:
				# Spawned / loaded inside the terminal zone: claim the physical track it occupies
				var init_phase := "dwell" if is_dwelling_now else ("out" if in_dep else "in")
				res[sid] = {"platform": int(z["platform"]), "phase": init_phase}
				continue
			var d_to_hold := 0.0 if in_arr else fposmod((hold_s - s_now) * dir, rlen)
			if not in_arr and d_to_hold > TERMINAL_REQUEST_DIST_M:
				continue
			requests.append({
				"dist": d_to_hold,
				"idx": i,
				"sid": sid,
			})
		tr["term_init_done"] = true

	# PASS 2: Grant terminal platforms to approaching trams nearest-to-hold-point first (FIFO queue order),
	# so a queued front tram always enters before a rear tram when a platform frees up, and any tram finding
	# both platforms occupied strictly waits outside the crossover until a departing train clears it.
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := float(a["dist"])
		var db := float(b["dist"])
		if absf(da - db) > 0.05:
			return da < db
		return int(a["idx"]) < int(b["idx"])
	)
	for req_item: Dictionary in requests:
		var i := int(req_item["idx"])
		var sid := int(req_item["sid"])
		var tr: Dictionary = trams[i]
		var res: Dictionary = tr["term_res"]
		if res.has(sid):
			continue
		var z := _zone_for(tr, sid)
		if z.is_empty():
			continue
		var rlen := float(tr["route_len"])
		var dir := float(tr["dir"])
		var s_now := float(tr["s"])
		var hold_s := float(z["hold_s"])
		var cusp_s := float(z["cusp_s"])
		var arr_len := fposmod((cusp_s - hold_s) * dir, rlen)
		var from_hold := fposmod((s_now - hold_s) * dir, rlen)
		var in_arr := from_hold <= arr_len + 0.5
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
			tr["term_hold_s"] = hold_s # Both platform tracks busy (or departing across diamond): wait outside crossover
			continue
		res[sid] = {"platform": pick, "phase": "in"}
		_switch_terminal_platform(tr, sid, pick)



# ---------------------------------------------------------------------------------------------
# Monorail switch interlocking. Each crossover is two moving half-beams (monorail_switch.gd) protected
# by four signals. A switch is reserved by one train at a time (the nearest ready train whose route runs
# through it), thrown automatically for that train's planned route (AI and manual driving alike), and only
# then is that train's entry signal cleared. Other trains stop at their red signal. A manual driver can
# still throw it by hand with G for special cases (manual_override), which automatic setting respects.
# ---------------------------------------------------------------------------------------------
const SW_SCAN_AHEAD := 170.0
const BOARD_STALL_S := 6.0 # AI dwell: doors close once nobody has boarded for this long (or nobody is left / no room)
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
		var any_pending := false
		var min_dm2 := 1e12
		for c: Dictionary in cands:
			if float(c["need"]) >= 0.0:
				continue
			any_pending = true
			var sw = c["sw"]
			var dm: Vector3 = sw.diverge_mid
			var dx := p.x - dm.x
			var dz := p.z - dm.z
			var dm2 := dx * dx + dz * dz
			if dm2 < min_dm2:
				min_dm2 = dm2
			if dm2 > 60.0 * 60.0:
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
		if not any_pending:
			break
		if min_dm2 > 62.0 * 62.0:
			d += maxf(1.0, floorf((sqrt(min_dm2) - 60.0) * 0.95))
		else:
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
		# Player lock: the locking train owns the crossover and nothing moves it, until that train has cleared it
		var lock_ti := int(grp[0].locked_by)
		if lock_ti >= 0 and g_de.has(lock_ti) and float(g_de[lock_ti]) <= 0.0:
			_lock_entered = true
		var lock_done := lock_ti >= 0 and (lock_ti >= trams.size() or not g_de.has(lock_ti) \
			or (_lock_entered and float(g_de[lock_ti]) > 0.0)) # through it (a terminal train meets it again ahead)
		if lock_done:
			for g in grp:
				g.locked_by = -1
			if player_lock.has(grp[0]):
				player_lock.clear()
				lock_released = true
			lock_ti = -1
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
		if lock_ti >= 0:
			cur = lock_ti
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
			if cur >= 0 and not sw.manual_override and int(sw.owner_entry) >= 0 and lock_ti < 0 and auto_switches:
				sw.target = sw.owner_need
			sw.update_signals()
	# Switches that stay put (player lock, or automatic switching off): a train whose route needs the other
	# setting takes the terminal platform the switch is set for instead, where its route allows that
	for ti: int in infos.keys():
		var trr: Dictionary = trams[ti]
		for cr: Dictionary in (infos[ti] as Dictionary).values():
			var swr = cr["sw"]
			if float(cr["need"]) < 0.0 or float(cr["d_entry"]) <= 0.0:
				continue
			var fixed := int(swr.locked_by) >= 0 or not auto_switches
			if not fixed or absf(float(swr.throw) - float(swr.target)) > 0.001 or absf(float(swr.throw) - float(cr["need"])) < 0.02:
				continue
			if not _reroute_through_switch(trr, swr, false, SW_SCAN_AHEAD):
				continue
			# New route: refresh this train's view of the crossover so its signal clears right away
			var per2 := {}
			for c3: Dictionary in _scan_switches(trr, switches):
				per2[c3["sw"]] = c3
			infos[ti] = per2
			trr["sw_next"] = {}
			for c3: Dictionary in per2.values():
				if float(c3["d_entry"]) > 0.0 and float(c3["need"]) >= 0.0 and (trr["sw_next"].is_empty() or float(c3["d_entry"]) < float(trr["sw_next"]["d_entry"])):
					trr["sw_next"] = c3
			for g3 in (swr.group if not (swr.group as Array).is_empty() else [swr]):
				var c4: Dictionary = per2.get(g3, {})
				if int(g3.owner_idx) == ti and not c4.is_empty() and float(c4["need"]) >= 0.0:
					g3.owner_need = float(c4["need"])
					g3.owner_entry = int(c4["entry"])
				g3.update_signals()
			break
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
# AI Headway Pacing Regulation: keep same-line trains evenly spaced by holding briefly at stations
# with doors open whenever the preceding train on the same line is too close compared to avg spacing.
# ---------------------------------------------------------------------------------------------
const PACING_START_RATIO := 0.72
const PACING_RELEASE_RATIO := 0.80
const PACING_MAX_HOLD_MID := 18.0
const PACING_MAX_HOLD_TERM := 26.0

func _same_line_headway_info(tr: Dictionary, my_idx: int) -> Dictionary:
	var lid := int(tr.get("line_id", -1))
	var rlen := float(tr.get("route_len", 0.0))
	if lid < 0 or rlen < 80.0:
		return {"active": false}
	var is_loop := bool(tr.get("is_loop", false))
	var cycle_len := rlen if is_loop else (rlen * 2.0)
	var my_dir := float(tr.get("dir", 1.0))
	var my_s := float(tr.get("s", 0.0))
	var my_pos := fposmod(my_s * (1.0 if my_dir >= 0.0 else -1.0), cycle_len) if is_loop else (my_s if my_dir >= 0.0 else (cycle_len - my_s))

	var fleet_n := 0
	var best_ahead := cycle_len
	var best_behind := cycle_len
	for j in range(trams.size()):
		var oth: Dictionary = trams[j]
		if int(oth.get("line_id", -1)) != lid:
			continue
		if bool(oth.get("crashed", false)) or bool(oth.get("derailed", false)):
			continue
		fleet_n += 1
		if j == my_idx:
			continue
		var o_dir := float(oth.get("dir", 1.0))
		var o_s := float(oth.get("s", 0.0))
		var o_pos: float
		if is_loop:
			var o_rlen := maxf(1.0, float(oth.get("route_len", rlen)))
			o_pos = fposmod(o_s * (1.0 if my_dir >= 0.0 else -1.0), o_rlen) * (cycle_len / o_rlen)
		else:
			o_pos = o_s if o_dir >= 0.0 else (cycle_len - o_s)
		var d_ah := fposmod(o_pos - my_pos, cycle_len)
		if d_ah > 0.5 and d_ah < best_ahead:
			best_ahead = d_ah
		var d_bh := fposmod(my_pos - o_pos, cycle_len)
		if d_bh > 0.5 and d_bh < best_behind:
			best_behind = d_bh

	if fleet_n < 2:
		return {"active": false}
	var avg_sp := cycle_len / float(fleet_n)
	return {
		"active": true,
		"fleet_n": fleet_n,
		"avg_spacing": avg_sp,
		"ahead_m": best_ahead,
		"behind_m": best_behind,
		"ratio": best_ahead / maxf(1.0, avg_sp),
	}


func _has_trailing_tram_close(tr: Dictionary, my_idx: int, max_dist_m: float = 90.0) -> bool:
	var my_secs: Array = tr["tram_info"]["sections"]
	if my_secs.is_empty():
		return false
	var active_end := int(tr["tram_info"].get("active_end", 0))
	var tail_sec: Node3D = my_secs[my_secs.size() - 1] if active_end == 0 else my_secs[0]
	var lead_sec: Node3D = my_secs[0] if active_end == 0 else my_secs[my_secs.size() - 1]
	if not is_instance_valid(tail_sec) or not is_instance_valid(lead_sec):
		return false
	var tail_p := tail_sec.global_position
	var fwd := -lead_sec.global_transform.basis.z if active_end == 0 else lead_sec.global_transform.basis.z
	var fwd2 := Vector2(fwd.x, fwd.z).normalized()
	if fwd2.length_squared() < 0.01:
		return false
	var right2 := Vector2(-fwd2.y, fwd2.x)
	var my_elev := bool(tr.get("elevated", false))
	var r2 := max_dist_m * max_dist_m
	for j in range(trams.size()):
		if j == my_idx:
			continue
		var oth: Dictionary = trams[j]
		if bool(oth.get("elevated", false)) != my_elev or bool(oth.get("crashed", false)) or bool(oth.get("derailed", false)):
			continue
		var o_secs: Array = oth["tram_info"]["sections"]
		if o_secs.is_empty():
			continue
		var o_ae := int(oth["tram_info"].get("active_end", 0))
		var o_lead: Node3D = o_secs[0] if o_ae == 0 else o_secs[o_secs.size() - 1]
		if not is_instance_valid(o_lead):
			continue
		var dv := Vector2(o_lead.global_position.x - tail_p.x, o_lead.global_position.z - tail_p.z)
		if dv.length_squared() > r2:
			continue
		var along := dv.dot(fwd2)
		var lat := absf(dv.dot(right2))
		var o_fwd := -o_lead.global_transform.basis.z if o_ae == 0 else o_lead.global_transform.basis.z
		var o_fwd2 := Vector2(o_fwd.x, o_fwd.z).normalized()
		if along < -2.0 and along > -max_dist_m and lat < 2.6 and o_fwd2.dot(fwd2) > 0.5:
			return true
	return false


func _has_tram_waiting_for_terminal(sid: int, elev: bool) -> bool:
	for o: Dictionary in trams:
		if bool(o.get("elevated", false)) != elev or float(o.get("term_hold_s", -1.0)) < 0.0:
			continue
		var oz := _zone_for(o, sid)
		if not oz.is_empty() and absf(float(o["term_hold_s"]) - float(oz["hold_s"])) < 1.0:
			return true
	return false


func _holding_for_pacing(tr: Dictionary, my_idx: int, _sid: int, dt: float) -> bool:
	var hw := _same_line_headway_info(tr, my_idx)
	if not bool(hw.get("active", false)):
		tr["pacing_waiting"] = false
		return false
	var avg_sp := float(hw["avg_spacing"])
	if avg_sp < 120.0:
		tr["pacing_waiting"] = false
		return false
	var ahead_m := float(hw["ahead_m"])
	var behind_m := float(hw["behind_m"])
	var ratio := float(hw["ratio"])
	tr["pacing_ahead_m"] = ahead_m
	tr["pacing_avg_m"] = avg_sp

	# Never block a trailing train close behind us on the same line or shared track, or a train queued outside this terminus!
	if behind_m < minf(120.0, avg_sp * 0.28) or _has_trailing_tram_close(tr, my_idx, 90.0) \
		or (_sid >= 0 and _has_tram_waiting_for_terminal(_sid, bool(tr.get("elevated", false)))):
		tr["pacing_waiting"] = false
		return false

	var is_term_dep := str(tr.get("term_stage", "")) == "board_only"
	var max_hold := PACING_MAX_HOLD_TERM if is_term_dep else PACING_MAX_HOLD_MID
	var held_t := float(tr.get("pacing_hold_t", 0.0))
	var dwell_el := float(tr.get("dwell_elapsed", 0.0))
	if held_t >= max_hold or dwell_el >= (42.0 if is_term_dep else 32.0):
		tr["pacing_waiting"] = false
		return false

	var was_waiting := bool(tr.get("pacing_waiting", false))
	var should_hold := (ratio < PACING_RELEASE_RATIO) if was_waiting else (ratio < PACING_START_RATIO)
	if should_hold:
		tr["pacing_waiting"] = true
		if float(tr.get("dwell_timer", 0.0)) <= 0.0:
			tr["pacing_hold_t"] = held_t + dt
		return true

	tr["pacing_waiting"] = false
	return false


# ---------------------------------------------------------------------------------------------
# Four-track express / local dispatch & terminal Express-First holding:
#   1. At a 4-track twin-island station, a local train keeps its doors OPEN while a same-direction express
#      is standing at the same stop, approaching behind (up to 500 m non-stop / 320 m stopping), or still
#      pulling out past the platform head (+42 m), and only closes doors once the express has cleared.
#   2. At a multi-platform turnback terminal (Platform A / B), a local train ready to depart keeps its doors
#      OPEN while an express sharing that terminal & outbound corridor is arriving (provided the other platform
#      is free or already reserved by the express), turning back / boarding on the other platform, or pulling out.
# ---------------------------------------------------------------------------------------------
const EXPRESS_LOOK_NONSTOP := 500.0
const EXPRESS_LOOK_STOPPING := 320.0
const EXPRESS_LEADOUT := 42.0
const EXPRESS_HOLD_MAX := 85.0
const TERMINAL_EXPRESS_LOOK := 260.0
const TERMINAL_EXPRESS_HOLD_MAX := 115.0

func _holding_for_express(tr: Dictionary, my_idx: int, sid: int, graph: NetworkGraph, dt: float) -> bool:
	if bool(tr.get("express", false)) or graph == null or sid < 0 or not graph.stations.has(sid):
		tr["express_hold_t"] = 0.0
		tr["express_waiting"] = false
		return false
	var is_quad_isl := graph.is_quad_island(sid)
	var my_z := _zone_for(tr, sid)
	var at_multi_term := (not my_z.is_empty()) and bool(my_z.get("b_available", false)) and (
		str(tr.get("term_stage", "")) == "board_only" or _on_terminal_departure_side(tr, sid)
	)
	if not is_quad_isl and not at_multi_term:
		tr["express_hold_t"] = 0.0
		tr["express_waiting"] = false
		return false

	var max_hold := TERMINAL_EXPRESS_HOLD_MAX if at_multi_term else EXPRESS_HOLD_MAX
	var held := float(tr.get("express_hold_t", 0.0))
	if held >= max_hold:
		tr["express_hold_done"] = float(sid)
		tr["express_waiting"] = false
		return false
	if held <= 0.0 and float(tr.get("express_hold_done", -1.0)) == float(sid):
		tr["express_waiting"] = false
		return false # already timed out once at this stop visit

	var hold := false
	var chk_age := float(tr.get("_exp_chk_t", 99.0)) + dt
	if int(tr.get("_exp_chk_sid", -999)) == sid and chk_age < 0.15:
		tr["_exp_chk_t"] = chk_age
		hold = bool(tr.get("_exp_chk_val", false))
	else:
		if at_multi_term:
			hold = _terminal_should_hold_for_express(tr, my_idx, sid)
		if not hold and is_quad_isl:
			hold = _quad_should_hold_for_express(tr, my_idx, sid, graph)
		tr["_exp_chk_sid"] = sid
		tr["_exp_chk_t"] = 0.0
		tr["_exp_chk_val"] = hold

	if hold:
		tr["express_hold_t"] = held + dt
		tr["express_waiting"] = true
	else:
		tr["express_hold_t"] = 0.0
		tr["express_waiting"] = false
	return hold


func _terminal_should_hold_for_express(tr: Dictionary, my_idx: int, sid: int) -> bool:
	var my_out_fwd := _tram_heading(tr)
	var occ := _terminal_occupancy(my_idx, int(tr["line_id"]), sid)
	var other_plat_free := (not bool(occ["a"])) and (not bool(occ["b"]))
	for j in range(trams.size()):
		var w: Dictionary = trams[j]
		if j == my_idx or not bool(w.get("express", false)) or bool(w.get("elevated", false)):
			continue
		if bool(w.get("crashed", false)) or bool(w.get("derailed", false)) or bool(w.get("held_manual", false)):
			continue
		var wz := _zone_for(w, sid)
		if wz.is_empty():
			continue
		# Confirm express departs this terminal in the same outbound direction as our local tram
		var w_curve: Curve3D = w["curve"]
		var w_rlen := float(w["route_len"])
		var w_dir := float(w["dir"])
		var w_is_loop := bool(w["is_loop"])
		var tf_ex := TrackBuilder.sample_track_frame(w_curve, float(wz["exit_s"]), w_rlen, w_is_loop)
		var w_out_fwd := (-tf_ex.basis.z) * w_dir
		w_out_fwd.y = 0.0
		if w_out_fwd.length_squared() < 0.001 or w_out_fwd.normalized().dot(my_out_fwd) < 0.55:
			continue
		var w_res: Dictionary = w.get("term_res", {})
		# 1. Express already holds a platform reservation at this terminal (entering, turning back, boarding, or pulling out!)
		if w_res.has(sid):
			return true
		# 2. Express just cleared the terminal exit_s but is still within EXPRESS_LEADOUT ahead of the throat
		var d_past := fposmod((float(w["s"]) - float(wz["exit_s"])) * w_dir, w_rlen)
		if d_past >= 0.0 and d_past < EXPRESS_LEADOUT:
			return true
		# 3. Express is approaching this terminal AND the other platform is free for it to pull right in!
		if other_plat_free:
			var d_arr := fposmod((float(wz["cusp_s"]) - float(w["s"])) * w_dir, w_rlen)
			if d_arr > 0.0 and d_arr <= TERMINAL_EXPRESS_LOOK:
				return true
	return false


func _quad_should_hold_for_express(tr: Dictionary, my_idx: int, sid: int, graph: NetworkGraph) -> bool:
	var st: Dictionary = graph.stations[sid]
	var st_pos: Vector3 = st["pos"]
	var plat_half := float(st.get("platform_len", 27.0)) * 0.5
	var my_fwd := _tram_heading(tr)
	for j in range(trams.size()):
		var w: Dictionary = trams[j]
		if j == my_idx or not bool(w.get("express", false)) or bool(w.get("elevated", false)):
			continue
		if bool(w.get("crashed", false)) or bool(w.get("derailed", false)) or bool(w.get("held_manual", false)):
			continue
		var calls := false
		for stop: Dictionary in w["stops"]:
			if int(stop["station_id"]) == sid:
				calls = true
				break
		var look_ahead := EXPRESS_LOOK_STOPPING if calls else EXPRESS_LOOK_NONSTOP
		var look_back := plat_half + EXPRESS_LEADOUT
		var arc_d := _arc_dist_to_station_same_dir(w, st_pos, my_fwd, look_back, look_ahead)
		if arc_d < 1e8:
			# Positive = express approaching behind station; 0 = at station; negative = pulling out past station
			if arc_d > -look_back and arc_d <= look_ahead:
				return true
	return false


# True forward travel heading of a tram along its route (works identically for front cab & rear cab active_end == 1!)
func _tram_heading(tr: Dictionary) -> Vector3:
	var curve: Curve3D = tr.get("curve")
	if curve != null:
		var rlen := float(tr["route_len"])
		var dir := float(tr["dir"])
		var tf := TrackBuilder.sample_track_frame(curve, float(tr["s"]), rlen, bool(tr["is_loop"]))
		var f := (-tf.basis.z) * dir
		f.y = 0.0
		if f.length_squared() > 0.0001:
			return f.normalized()
	return Vector3.FORWARD


# Signed arc-length distance along `w`'s curve from its current nose `w["s"]` to station center `st_pos`
# traveling in direction `ref_fwd` (> 0 = station still ahead of w, < 0 = w already passed station).
# Returns 1e9 if `w`'s curve does not pass near `st_pos` in `ref_fwd` within [-back_m, +ahead_m].
func _arc_dist_to_station_same_dir(w: Dictionary, st_pos: Vector3, ref_fwd: Vector3, back_m: float, ahead_m: float) -> float:
	var curve: Curve3D = w["curve"]
	var rlen := float(w["route_len"])
	var dir := float(w["dir"])
	var is_loop := bool(w["is_loop"])
	var s0 := float(w["s"])
	var sp2 := Vector2(st_pos.x, st_pos.z)
	# Quick Euclidean broad-phase rejection
	var p0 := curve.sample_baked(fposmod(s0, rlen) if is_loop else clampf(s0, 0.0, rlen), false)
	if Vector2(p0.x, p0.z).distance_squared_to(sp2) > (maxf(ahead_m, back_m) + 45.0) * (maxf(ahead_m, back_m) + 45.0):
		return 1e9
	var best_k := 1e9
	var best_d2 := 10.5 * 10.5
	var k := -back_m - 6.0
	var k_max := ahead_m + 10.0
	while k <= k_max:
		var sk := s0 + dir * k
		if is_loop:
			sk = fposmod(sk, rlen)
		elif sk < 0.0 or sk > rlen:
			k += 3.0
			continue
		var q := curve.sample_baked(sk, false)
		var d2 := Vector2(q.x - sp2.x, q.z - sp2.y).length_squared()
		if d2 < best_d2:
			var tf_k := TrackBuilder.sample_track_frame(curve, sk, rlen, is_loop)
			var fk := (-tf_k.basis.z) * dir
			fk.y = 0.0
			if fk.length_squared() > 0.001 and fk.normalized().dot(ref_fwd) > 0.55:
				best_d2 = d2
				best_k = k
		k += 3.0
	return best_k


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
const MERGE_LOOK := 115.0
const MERGE_STEP := 2.0
const MERGE_STANDOFF := 13.0

static func _is_tram_docked_holding(tr: Dictionary) -> bool:
	if bool(tr.get("doors_target_open", false)) or float(tr.get("door_ratio", 0.0)) > 0.02:
		return true
	if bool(tr.get("ai_depart_pending", false)) or bool(tr.get("express_waiting", false)) or bool(tr.get("pacing_waiting", false)):
		return true
	var ts := str(tr.get("term_stage", ""))
	if ts == "alight_only" or ts == "flip_wait" or ts == "board_only":
		return true
	var spd := float(tr.get("speed_mps", 0.0))
	if bool(tr.get("held_manual", false)) and spd < 0.25:
		return true
	return spd < 0.25 and float(tr.get("dwell_timer", 0.0)) > 0.0


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
			if absf(pa.y - pb.y) >= 3.5:
				continue # vertically separated tracks never merge in 3D
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
			var a_exp := bool(a.get("express", false))
			var b_exp := bool(b.get("express", false))
			var a_docked := _is_tram_docked_holding(a)
			var b_docked := _is_tram_docked_holding(b)
			var a_spd := float(a.get("speed_mps", 0.0))
			var b_spd := float(b.get("speed_mps", 0.0))
			var a_can_stop := (da - MERGE_STANDOFF) >= 0.0 or (a_spd < 1.2 and da >= 6.0)
			var b_can_stop := (db - MERGE_STANDOFF) >= 0.0 or (b_spd < 1.2 and db >= 6.0)
			var b_yields := db > da or (is_equal_approx(da, db) and j > i)
			if a_docked and not b_docked:
				# A tram parked/dwelling on a parallel platform track must NEVER block a moving/approaching tram
				# from entering the station or passing through the downstream merge!
				b_yields = false
			elif b_docked and not a_docked:
				b_yields = true
			elif a_docked and b_docked:
				# Both docked side-by-side at a twin-island station: express departs first; otherwise let first mover go.
				if a_exp and not b_exp:
					b_yields = true
				elif b_exp and not a_exp:
					b_yields = false
				else:
					continue
			else:
				# Both actively moving (or just starting to depart): give express merge priority over local whenever
				# the local can still stop safely short of the fouling point!
				if a_exp and not b_exp and b_can_stop and (da <= db + 75.0 or b_spd < 1.5):
					b_yields = true
				elif b_exp and not a_exp and a_can_stop and (db <= da + 75.0 or a_spd < 1.5):
					b_yields = false
				elif (b_yields and not b_can_stop) and a_can_stop:
					b_yields = false
				elif (not b_yields and not a_can_stop) and b_can_stop:
					b_yields = true
			var yielder: Dictionary = b if b_yields else a
			var d_yield := db if b_yields else da
			var y_spd := b_spd if b_yields else a_spd
			var y_docked := b_docked if b_yields else a_docked
			var stop_at := d_yield - MERGE_STANDOFF
			if stop_at < 0.0:
				if (y_docked or y_spd < 1.2) and d_yield >= 6.0:
					stop_at = 0.0 # Hold cleanly at current safe position before the fouling point
				else:
					continue # Moving tram already past standoff: effectively already merging
			var s_new := float(yielder["s"]) + float(yielder["dir"]) * stop_at
			if bool(yielder["is_loop"]):
				s_new = fposmod(s_new, float(yielder["route_len"]))
			if float(yielder["merge_hold_s"]) < 0.0 or _hold_ahead(yielder, s_new) < _hold_ahead(yielder, float(yielder["merge_hold_s"])):
				yielder["merge_hold_s"] = s_new


func _head_pos(tr: Dictionary) -> Vector3:
	var curve: Curve3D = tr.get("curve")
	if curve != null:
		var rlen := float(tr["route_len"])
		var s0 := fposmod(float(tr["s"]), rlen) if bool(tr["is_loop"]) else clampf(float(tr["s"]), 0.0, rlen)
		return curve.sample_baked(s0, false)
	var secs: Array = tr["tram_info"]["sections"]
	if secs.is_empty() or not is_instance_valid(secs[0]):
		return Vector3.ZERO
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


# First pair of indices (a, b) where the two paths come within tram body clearance heading the same way (b index into bp); (-1,-1) if none
static func _first_merge(ap: PackedVector2Array, bp: PackedVector2Array) -> Vector2i:
	var na := ap.size() - 1
	var nb := bp.size() - 1
	var ia := 2
	while ia < na:
		var pa := ap[ia]
		var min_d2 := 1e12
		var ib := 2
		while ib < nb:
			var d2 := pa.distance_squared_to(bp[ib])
			if d2 < 2.6 * 2.6:
				var ta := (ap[ia + 1] - pa).normalized()
				var tb := (bp[ib + 1] - bp[ib]).normalized()
				if ta.dot(tb) > 0.7:
					return Vector2i(ia, ib)
				return Vector2i(-1, -1) # paths cross / meet head-on: handled by signals and interlocking
			if d2 < min_d2:
				min_d2 = d2
			ib += maxi(1, int((sqrt(d2) - 2.65) / 2.05))
		ia += maxi(1, int((sqrt(min_d2) - 2.65) / 2.05))
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


# Some other train is on (or right at) this switch
func _switch_occupied(sw, me: int) -> bool:
	for j in range(trams.size()):
		if j == me:
			continue
		for c: Dictionary in _scan_switches(trams[j], [sw], 5.0):
			if c["sw"] == sw and float(c["need"]) >= 0.0 and float(c["d_entry"]) <= 2.0:
				return true
	return false


# Lock the next crossover ahead of the active train as it is set now (press again to unlock). The lock
# lapses by itself once the train has run through it.
func toggle_switch_lock(graph: NetworkGraph) -> String:
	var tr := get_active_tram()
	if tr.is_empty() or graph == null or not graph.has_meta("monorail_switches"):
		return "none"
	var me := active_tram_idx
	if not player_lock.is_empty():
		for g in player_lock:
			if is_instance_valid(g):
				g.locked_by = -1
		player_lock.clear()
		return "unlocked"
	var lst := _scan_switches(tr, graph.get_meta("monorail_switches"), SW_SCAN_AHEAD)
	var pick = null
	for c: Dictionary in lst:
		if float(c["need"]) < 0.0:
			continue
		if pick == null or float(c["d_entry"]) > 0.0:
			pick = c["sw"]
		if float(c["d_entry"]) > 0.0:
			break
	if pick == null:
		return "none"
	var grp: Array = pick.group if not (pick.group as Array).is_empty() else [pick]
	for g in grp:
		if int(g.locked_by) >= 0 and int(g.locked_by) != me:
			return "busy"
	for g in grp:
		g.locked_by = me
	player_lock = grp.duplicate()
	lock_released = false
	_lock_entered = false
	return "locked"


func set_auto_switches(on: bool) -> void:
	auto_switches = on


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
		if int(sw.owner_idx) >= 0 and int(sw.owner_idx) != me and (auto_switches or _switch_occupied(sw, me)):
			return "busy"
		if int(sw.locked_by) >= 0 and int(sw.locked_by) != me:
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
func _reroute_through_switch(tr: Dictionary, sw, allow_wrong: bool = true, scan_m: float = 40.0) -> bool:
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
			if bool(toggle[1]) and not allow_wrong:
				continue
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
			if not allow_wrong and not leaving:
				# Automatic (dispatcher) reroute: only onto a platform track nobody else holds
				var me_i := trams.find(tr)
				var occ := _terminal_occupancy(me_i, lid, sid)
				if bool(occ["b"] if int(z_new["platform"]) == PLATFORM_B else occ["a"]):
					continue
			var probe := {"curve": c["curve"], "route_len": len_new, "is_loop": bool(tr["is_loop"]), "dir": dir,
				"s": s_new, "elevated": tr.get("elevated", false), "spec": tr["spec"], "tram_info": tr["tram_info"]}
			var ok := false
			for cand: Dictionary in _scan_switches(probe, [sw], scan_m):
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
				if allow_wrong:
					_hand_over_platform(tr, sid, int(z_new["platform"])) # the driver forced it: the other train yields
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

