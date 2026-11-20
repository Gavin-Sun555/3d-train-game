class_name StationBuilder
extends RefCounted


static func build_detailed_station(
	parent: Node3D,
	st_data: Dictionary,
	rail_top_y: float,
	cjk_font: Font,
	station_lights: Array[OmniLight3D]
) -> Dictionary:
	var sid := int(st_data.get("id", 1))
	var st_name := str(st_data.get("name", "电车站"))
	var pos: Vector3 = st_data.get("pos", Vector3.ZERO)
	var fwd: Vector3 = (st_data.get("fwd", Vector3.FORWARD) as Vector3).normalized()
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd).normalized()
	var tf := Transform3D(Basis(right, up, -fwd), pos)

	var side := float(st_data.get("side", 1))
	var st_node := Node3D.new()
	st_node.name = "Station_%d" % sid
	st_node.transform = tf
	parent.add_child(st_node)

	var is_island := (int(side) == 0)
	var plat_h := 0.30 + maxf(0.0, rail_top_y - TrackBuilder.EMBED_RAIL_TOP)
	var plat_len := clampf(float(st_data.get("platform_len", 27.0)), 20.0, 56.0)
	var plat_half := plat_len * 0.5
	var plat_w := 3.10 if is_island else 2.95
	var inner_edge_x := (-plat_w * 0.5) if is_island else (side * 1.46)
	var plat_cx := 0.0 if is_island else (inner_edge_x + side * (plat_w * 0.5))
	var outer_edge_x := (plat_w * 0.5) if is_island else (inner_edge_x + side * plat_w)

	var mats := _station_mats()
	var face_sign := 1.0 if is_island else side # +x when island (mirrored per half below)
	var plat_top := plat_h

	# 1. Platform deck (triplanar granite pavers), edge coping, tactile warning strip, rubbing strip
	# Elevated (monorail) stations: platform slab on twin columns, stairs + lift tower to the street
	var elevated := plat_h > 3.0
	if elevated:
		_box(st_node, Vector3(plat_w, 0.55, plat_len), Vector3(plat_cx, plat_h - 0.275, 0.0), mats["paver"])
		_box(st_node, Vector3(plat_w + 0.3, 0.35, plat_len + 0.3), Vector3(plat_cx, plat_h - 0.72, 0.0), mats["coping"])
		var pier_end := plat_half - 1.5
		var n_piers := maxi(3, int(round(plat_len / 6.0)) + 1)
		for pi_ in range(n_piers):
			var cz := lerpf(-pier_end, pier_end, float(pi_) / float(n_piers - 1))
			for cx_off: float in ([-0.8, 0.8] if plat_w > 2.0 else [0.0]):
				_cyl(st_node, 0.32, plat_h - 0.9, Vector3(plat_cx + cx_off, (plat_h - 0.9) * 0.5, cz), mats["coping"])
	else:
		_box(st_node, Vector3(plat_w, plat_h, plat_len), Vector3(plat_cx, plat_h * 0.5, 0.0), mats["paver"])
	var edges: Array[float] = []
	if is_island:
		edges.assign([-1.0, 1.0])
	else:
		edges.append(side)
	for e_s: float in edges:
		# e_s points from platform centre toward the track on that edge (side platform: track is at -side)
		var track_dir := e_s if is_island else -side
		var edge_x := (e_s * plat_w * 0.5) if is_island else inner_edge_x
		_box(st_node, Vector3(0.32, 0.05, plat_len), Vector3(edge_x - track_dir * 0.16, plat_top + 0.002, 0.0), mats["coping"])
		var rub_h := 0.5 if elevated else plat_h * 0.7
		_box(st_node, Vector3(0.04, rub_h, plat_len), Vector3(edge_x + track_dir * 0.005, plat_h - rub_h * 0.5 - 0.04, 0.0), mats["rubber"])
		_box(st_node, Vector3(0.30, 0.012, plat_len - 0.6), Vector3(edge_x - track_dir * 0.55, plat_top + 0.006, 0.0), mats["tactile"])
		# Door-position boarding marks evenly distributed along the platform
		var n_marks := maxi(4, int(round(plat_len / 6.4)))
		var mark_span := plat_half - 3.6
		for mi_m in range(n_marks):
			var mz := lerpf(-mark_span, mark_span, float(mi_m) / float(n_marks - 1))
			_box(st_node, Vector3(0.36, 0.008, 1.3), Vector3(edge_x - track_dir * 0.98, plat_top + 0.004, mz), mats["mark"])
	# Back/outer edge: low granite kerb + stainless guardrail with glass infill (side platforms)
	if not is_island:
		var rail_x := outer_edge_x - side * 0.08
		_box(st_node, Vector3(0.16, 0.12, plat_len), Vector3(outer_edge_x - side * 0.08, plat_top + 0.06, 0.0), mats["coping"])
		var gz_end := plat_half - 2.5
		for gz: float in [-gz_end, gz_end]:
			_box(st_node, Vector3(0.05, 0.05, 4.6), Vector3(rail_x, plat_top + 1.05, gz), mats["stainless"])
			_box(st_node, Vector3(0.02, 0.86, 4.5), Vector3(rail_x, plat_top + 0.58, gz), mats["glass"])
			for pz: float in [-2.25, 0.0, 2.25]:
				_cyl(st_node, 0.028, 1.05, Vector3(rail_x, plat_top + 0.53, gz + pz), mats["stainless"])

	# 2. Ramps at both ends with stainless handrails
	var ramp_len := 3.4
	var ramp_angle := atan2(plat_h, ramp_len)
	var stair_x := plat_cx if is_island else (outer_edge_x - side * 1.0)
	var stair_run := plat_h / 0.62
	if elevated:
		# Straight stair down from the +Z platform end (rise 0.155m, tread 0.32m per step)
		var n_steps := int(ceil(plat_h / 0.155))
		var tread := stair_run / float(n_steps)
		for k in range(n_steps):
			var y_top := plat_h - float(k) * 0.155
			_box(st_node, Vector3(1.9, 0.155, tread + 0.02), Vector3(stair_x, y_top - 0.0775, plat_len * 0.5 + (float(k) + 0.5) * tread), mats["coping"])
		var stringer := _box(st_node, Vector3(2.1, 0.35, sqrt(stair_run * stair_run + plat_h * plat_h)), Vector3(stair_x, plat_h * 0.5 - 0.3, plat_len * 0.5 + stair_run * 0.5), mats["steel_dark"])
		stringer.rotation.x = atan2(plat_h, stair_run)
		for hs: float in [-1.0, 1.0]:
			var hr2 := _box(st_node, Vector3(0.05, 0.05, sqrt(stair_run * stair_run + plat_h * plat_h)), Vector3(stair_x + hs * 0.98, plat_h * 0.5 + 0.95, plat_len * 0.5 + stair_run * 0.5), mats["stainless"])
			hr2.rotation.x = atan2(plat_h, stair_run)
		# Glass lift tower at the -Z end
		_box(st_node, Vector3(2.4, plat_h + 3.2, 2.4), Vector3(stair_x, (plat_h + 3.2) * 0.5, -plat_len * 0.5 - 1.4), mats["glass"])
		_box(st_node, Vector3(2.6, 0.4, 2.6), Vector3(stair_x, plat_h + 3.3, -plat_len * 0.5 - 1.4), mats["accent"])
		_box(st_node, Vector3(plat_w, 0.5, 3.0), Vector3(plat_cx, plat_h - 0.25, -plat_len * 0.5 - 1.4), mats["paver"])
	for end_sign: float in ([] if elevated else [-1.0, 1.0]):
		var rz := end_sign * (plat_len * 0.5 + ramp_len * 0.48)
		var ramp := _box(st_node, Vector3(plat_w - 0.12, plat_h * 0.65, ramp_len), Vector3(plat_cx, plat_h * 0.32, rz), mats["paver"])
		ramp.rotation.x = end_sign * ramp_angle
		if not is_island:
			var hr := _box(st_node, Vector3(0.045, 0.045, ramp_len + 0.2), Vector3(outer_edge_x - side * 0.1, plat_h * 0.5 + 0.95, rz), mats["stainless"])
			hr.rotation.x = end_sign * ramp_angle

	# 3. Shelter: round steel columns, thick roof with accent fascia + light soffit + LED strips, framed glass walls
	var sh_half := clampf(plat_half - 5.1, 7.5, 22.0)
	var roof_y := plat_top + 2.95
	var roof_w := 2.6 if is_island else 2.55
	var roof_cx := 0.0 if is_island else (outer_edge_x - side * (roof_w * 0.5 - 0.05))
	var col_x := 0.0 if is_island else (outer_edge_x - side * 0.42)
	var n_cols := maxi(4, int(round((sh_half * 2.0) / 5.2)) + 1)
	var col_span := sh_half - 1.0
	for ci_ in range(n_cols):
		var cz := lerpf(-col_span, col_span, float(ci_) / float(n_cols - 1))
		_cyl(st_node, 0.085, 2.95, Vector3(col_x, plat_top + 1.475, cz), mats["steel_dark"])
		_box(st_node, Vector3(0.34, 0.025, 0.34), Vector3(col_x, plat_top + 0.012, cz), mats["steel_dark"])
		_box(st_node, Vector3(roof_w - 0.3, 0.10, 0.12), Vector3(roof_cx, roof_y - 0.14, cz), mats["steel_dark"])
	_box(st_node, Vector3(roof_w, 0.16, sh_half * 2.0 + 0.4), Vector3(roof_cx, roof_y, 0.0), mats["roof_top"])
	_box(st_node, Vector3(roof_w - 0.06, 0.02, sh_half * 2.0 + 0.3), Vector3(roof_cx, roof_y - 0.085, 0.0), mats["soffit"])
	var fascia_xs: Array[float] = []
	if is_island:
		fascia_xs = [-roof_w * 0.5, roof_w * 0.5]
	else:
		fascia_xs = [roof_cx - side * roof_w * 0.5, roof_cx + side * roof_w * 0.5]
	for fx: float in fascia_xs:
		_box(st_node, Vector3(0.06, 0.34, sh_half * 2.0 + 0.4), Vector3(fx, roof_y - 0.02, 0.0), mats["accent"])
		_box(st_node, Vector3(0.065, 0.045, sh_half * 2.0 + 0.4), Vector3(fx, roof_y + 0.09, 0.0), mats["fascia_white"])
	for lx_off: float in ([-0.55, 0.55] if is_island else [0.0]):
		_box(st_node, Vector3(0.10, 0.02, sh_half * 2.0 - 1.0), Vector3(roof_cx + lx_off, roof_y - 0.10, 0.0), mats["led"])
	_box(st_node, Vector3(roof_w + 0.04, 0.05, 0.08), Vector3(roof_cx, roof_y - 0.02, -sh_half - 0.2), mats["accent"])
	_box(st_node, Vector3(roof_w + 0.04, 0.05, 0.08), Vector3(roof_cx, roof_y - 0.02, sh_half + 0.2), mats["accent"])

	# Framed glass windscreen (back wall on side platforms / spine on islands) with frit band
	var wall_x := 0.0 if is_island else (outer_edge_x - side * 0.22)
	var pan_n := maxi(8, int(round((sh_half * 2.0) / 1.7)))
	var pan_len := (sh_half * 2.0 - 0.4) / float(pan_n)
	var z0 := -sh_half + 0.2
	_box(st_node, Vector3(0.07, 0.07, sh_half * 2.0 - 0.4), Vector3(wall_x, plat_top + 0.12, 0.0), mats["frame"])
	_box(st_node, Vector3(0.07, 0.07, sh_half * 2.0 - 0.4), Vector3(wall_x, plat_top + 2.38, 0.0), mats["frame"])
	for pi_ in range(pan_n):
		var pz := z0 + (float(pi_) + 0.5) * pan_len
		_box(st_node, Vector3(0.02, 2.2, pan_len - 0.05), Vector3(wall_x, plat_top + 1.25, pz), mats["glass"])
		_box(st_node, Vector3(0.024, 0.16, pan_len - 0.05), Vector3(wall_x, plat_top + 1.42, pz), mats["frit"])
	for mi_ in range(pan_n + 1):
		_box(st_node, Vector3(0.06, 2.3, 0.05), Vector3(wall_x, plat_top + 1.25, z0 + float(mi_) * pan_len), mats["frame"])
	# End screens with double-sided advertising lightboxes
	for es: float in [-1.0, 1.0]:
		var ez := es * (sh_half - 0.15)
		var e_w := 1.5 if not is_island else 1.2
		var e_cx := (wall_x - side * e_w * 0.5) if not is_island else 0.0
		var e_len := e_w if not is_island else 1.6
		_box(st_node, Vector3(e_len, 1.75, 0.16), Vector3(e_cx, plat_top + 1.2, ez), mats["frame"])
		_box(st_node, Vector3(e_len - 0.12, 1.6, 0.17), Vector3(e_cx, plat_top + 1.2, ez), mats["poster_a"] if es < 0.0 else mats["poster_b"])
		_box(st_node, Vector3(e_len, 0.3, 0.05), Vector3(e_cx, plat_top + 0.18, ez), mats["frame"])

	# 4. Hanging station name boards (facing the tracks) + CIS next-tram displays
	var name_short := st_name.split("（")[0].split("(")[0].strip_edges()
	for e_s: float in edges:
		var toward_track := e_s if is_island else -side
		var bx := (e_s * 1.0) if is_island else (inner_edge_x + side * 0.85)
		var rot_face := toward_track * 90.0
		_box(st_node, Vector3(0.05, 0.46, 3.6), Vector3(bx, roof_y - 0.42, 4.6), mats["sign_blue"])
		for hz: float in [3.2, 6.0]:
			_cyl(st_node, 0.012, 0.3, Vector3(bx, roof_y - 0.2, hz), mats["steel_dark"])
		_label(st_node, name_short, Vector3(bx + toward_track * 0.03, roof_y - 0.42, 4.6), rot_face, 64, 0.0052, Color(1, 1, 1), cjk_font)
		_label(st_node, name_short, Vector3(bx - toward_track * 0.03, roof_y - 0.42, 4.6), rot_face + 180.0, 64, 0.0052, Color(1, 1, 1), cjk_font)
		# Next-tram display (double sided)
		_box(st_node, Vector3(0.12, 0.42, 1.7), Vector3(bx, roof_y - 0.48, -3.8), mats["steel_dark"])
		for f_s: float in [1.0, -1.0]:
			_box(st_node, Vector3(0.01, 0.30, 1.56), Vector3(bx + toward_track * f_s * 0.062, roof_y - 0.48, -3.8), mats["cis_screen"])
			var cis := _label(st_node, "1  NEXT  2 min", Vector3(bx + toward_track * f_s * 0.07, roof_y - 0.48, -3.8), rot_face + (0.0 if f_s > 0.0 else 180.0), 40, 0.0042, Color(1.0, 0.72, 0.2), null)
			cis.outline_size = 0
		for hz2: float in [-4.4, -3.2]:
			_cyl(st_node, 0.012, 0.22, Vector3(bx, roof_y - 0.17, hz2), mats["steel_dark"])

	# 5. Furniture (scales proportionally with platform length)
	var furn_n := maxi(3, int(round((sh_half * 2.0) / 5.4)))
	var furn_span := sh_half - 2.6
	if is_island:
		# Leaning rails along the spine (islands are too narrow for benches)
		for fi_ in range(furn_n):
			var lz := lerpf(-furn_span, furn_span, float(fi_) / float(furn_n - 1))
			for ls: float in [-1.0, 1.0]:
				_box(st_node, Vector3(0.10, 0.07, 2.2), Vector3(ls * 0.12, plat_top + 0.78, lz), mats["wood"])
			for lp: float in [-0.9, 0.9]:
				_box(st_node, Vector3(0.18, 0.78, 0.05), Vector3(0.0, plat_top + 0.39, lz + lp), mats["steel_dark"])
	else:
		var bench_x := outer_edge_x - side * 0.72
		for fi_ in range(furn_n):
			var bz := lerpf(-furn_span, furn_span, float(fi_) / float(furn_n - 1))
			_build_bench(st_node, Vector3(bench_x, plat_top, bz), side, mats)
		# Litter + recycling bins
		var bin_off := sh_half - 1.6
		for bin_z: float in [-bin_off, bin_off]:
			_cyl(st_node, 0.24, 0.86, Vector3(bench_x, plat_top + 0.43, bin_z), mats["steel_dark"])
			_cyl(st_node, 0.255, 0.07, Vector3(bench_x, plat_top + 0.88, bin_z), mats["stainless"])
			_cyl(st_node, 0.245, 0.10, Vector3(bench_x, plat_top + 0.62, bin_z), mats["accent"])
	# Ticket vending machine (outside shelter)
	var tvm_x := 0.0 if is_island else (outer_edge_x - side * 0.55)
	var tvm_face := 1.0 if is_island else -side
	var tvm_z := -(sh_half + 1.8)
	_box(st_node, Vector3(0.62, 1.70, 0.95), Vector3(tvm_x, plat_top + 0.85, tvm_z), mats["steel_dark"])
	_box(st_node, Vector3(0.66, 0.34, 0.99), Vector3(tvm_x, plat_top + 1.88, tvm_z), mats["accent"])
	var scr := _box(st_node, Vector3(0.05, 0.42, 0.56), Vector3(tvm_x + tvm_face * 0.31, plat_top + 1.32, tvm_z - 0.1), mats["tvm_screen"])
	scr.rotation.z = tvm_face * deg_to_rad(-8.0)
	_box(st_node, Vector3(0.06, 0.16, 0.16), Vector3(tvm_x + tvm_face * 0.32, plat_top + 1.30, tvm_z + 0.3), mats["tap_green"])
	_box(st_node, Vector3(0.12, 0.05, 0.6), Vector3(tvm_x + tvm_face * 0.33, plat_top + 1.02, tvm_z), mats["stainless"])
	_box(st_node, Vector3(0.04, 0.12, 0.3), Vector3(tvm_x + tvm_face * 0.32, plat_top + 0.55, tvm_z), mats["black"])
	_label(st_node, "TICKETS", Vector3(tvm_x + tvm_face * 0.34, plat_top + 1.88, tvm_z), tvm_face * -90.0 + 180.0, 40, 0.004, Color(1, 1, 1), null)
	# Card validators at both entries
	var val_z := plat_half - 1.5
	for vz: float in [-val_z, val_z]:
		var vx := 0.0 if is_island else (outer_edge_x - side * 0.6)
		_cyl(st_node, 0.06, 1.05, Vector3(vx, plat_top + 0.525, vz), mats["steel_dark"])
		var vh := _box(st_node, Vector3(0.20, 0.30, 0.16), Vector3(vx, plat_top + 1.15, vz), mats["accent"])
		vh.rotation.x = deg_to_rad(-vz / absf(vz) * 15.0)
		_box(st_node, Vector3(0.14, 0.12, 0.17), Vector3(vx, plat_top + 1.2, vz), mats["tap_green"])
	# Network map lightbox on the windscreen + help point
	var lb_x := 0.0 if is_island else (wall_x - side * 0.06)
	_box(st_node, Vector3(0.12, 1.6, 1.2), Vector3(lb_x, plat_top + 1.35, 2.5 if not is_island else 3.0), mats["frame"])
	_box(st_node, Vector3(0.13, 1.45, 1.06), Vector3(lb_x, plat_top + 1.35, 2.5 if not is_island else 3.0), mats["map"])
	_box(st_node, Vector3(0.16, 0.36, 0.22), Vector3(col_x + (0.0 if is_island else -side * 0.12), plat_top + 1.35, -2.5), mats["help_yellow"])
	_box(st_node, Vector3(0.17, 0.07, 0.07), Vector3(col_x + (0.0 if is_island else -side * 0.12), plat_top + 1.30, -2.5), mats["red_btn"])
	# Station totem with lit "T" roundel
	var pylon_x := 0.0 if is_island else (outer_edge_x - side * 0.4)
	var pylon_z := sh_half + 2.5
	_box(st_node, Vector3(0.24, 3.4, 0.6), Vector3(pylon_x, plat_top + 1.7, pylon_z), mats["sign_blue"])
	_box(st_node, Vector3(0.26, 0.56, 0.5), Vector3(pylon_x, plat_top + 2.95, pylon_z), mats["fascia_white"])
	_label(st_node, "T", Vector3(pylon_x + 0.14, plat_top + 2.95, pylon_z), 90.0, 120, 0.004, Color(0.08, 0.3, 0.6), null)
	_label(st_node, "T", Vector3(pylon_x - 0.14, plat_top + 2.95, pylon_z), -90.0, 120, 0.004, Color(0.08, 0.3, 0.6), null)
	# Platform lamp posts at both ends
	var lp_end := plat_half - 0.9
	for lpz: float in [-lp_end, lp_end]:
		var lpx := 0.0 if is_island else (outer_edge_x - side * 0.25)
		_cyl(st_node, 0.06, 4.6, Vector3(lpx, plat_top + 2.3, lpz), mats["steel_dark"])
		var arm_dir := 0.0 if is_island else -side
		_box(st_node, Vector3(0.9 if not is_island else 0.12, 0.08, 0.18), Vector3(lpx + arm_dir * 0.4, plat_top + 4.55, lpz), mats["steel_dark"])
		_box(st_node, Vector3(0.5, 0.04, 0.16), Vector3(lpx + arm_dir * 0.7, plat_top + 4.5, lpz), mats["led"])

	# 6. Crisp 3D Station Name Sign + Live Waiting Queue Counter Label
	var lbl := Label3D.new()
	lbl.text = st_name
	if cjk_font != null:
		lbl.font = cjk_font
	lbl.font_size = 70
	lbl.pixel_size = 0.0072
	lbl.modulate = Color(0.98, 0.99, 1.0)
	lbl.outline_modulate = Color(0.06, 0.11, 0.18)
	lbl.outline_size = 18
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(plat_cx, plat_h + 3.95, 0.0)
	st_node.add_child(lbl)

	var wait_lbl := Label3D.new()
	wait_lbl.text = ""
	if cjk_font != null:
		wait_lbl.font = cjk_font
	wait_lbl.font_size = 50
	wait_lbl.pixel_size = 0.0068
	wait_lbl.modulate = Color(0.46, 0.94, 0.70)
	wait_lbl.outline_modulate = Color(0.05, 0.09, 0.14)
	wait_lbl.outline_size = 14
	wait_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	wait_lbl.position = Vector3(plat_cx, plat_h + 3.45, 0.0)
	st_node.add_child(wait_lbl)

	# Warm under-canopy linear LED lighting
	for lz: float in [-4.5, 4.5]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.92, 0.78)
		light.light_energy = 0.0
		light.visible = false
		light.omni_range = 15.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 90.0
		light.distance_fade_length = 30.0
		light.position = Vector3(plat_cx, plat_h + 2.7, lz)
		st_node.add_child(light)
		station_lights.append(light)

	# Precompute world-space passenger waiting positions along the full platform length safely behind the yellow line
	var waiting_slots: Array[Vector3] = []
	var slot_cols := maxi(10, int(round(plat_len / 2.2)))
	var slot_span := plat_half - 4.2
	for row_i in range(2):
		var wx_local := (-0.68 if row_i == 0 else 0.68) if is_island else (inner_edge_x + side * (0.88 + float(row_i) * 0.68))
		for col_i in range(slot_cols):
			var wz_local := lerpf(-slot_span, slot_span, float(col_i) / float(slot_cols - 1)) + float(row_i) * 0.35
			waiting_slots.append(tf * Vector3(wx_local, plat_h, wz_local))

	var ramp_world := tf * Vector3(plat_cx, 0.04, (plat_len * 0.5 + ramp_len + 1.0))
	if elevated:
		ramp_world = tf * Vector3(stair_x, 0.2, plat_len * 0.5 + stair_run + 1.0)
	var board_edge_center := tf * Vector3(0.0 if is_island else (inner_edge_x + side * 0.28), plat_h, 0.0)
	# Top of the stairs / ramp: where arriving passengers step onto the platform deck
	var plat_entry := tf * Vector3(stair_x if elevated else plat_cx, plat_h, plat_len * 0.5 - 0.6)

	return {
		"station_id": sid,
		"name": st_name,
		"node": st_node,
		"pos": pos,
		"fwd": fwd,
		"side": side,
		"plat_h": plat_h,
		"platform_len": plat_len,
		"waiting_slots": waiting_slots,
		"ramp_entry": ramp_world,
		"platform_entry": plat_entry,
		"board_edge": board_edge_center,
		"wait_label": wait_lbl,
		"name_label": lbl,
	}


static func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func _emit_mat(alb: Color, em: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = alb
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = em
	m.emission_energy_multiplier = energy
	return m


static func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, radius: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = h
	c.radial_segments = 12
	c.material = mat
	mi.mesh = c
	mi.position = pos
	parent.add_child(mi)
	return mi


static var _mat_cache: Dictionary = {}


static func _station_mats() -> Dictionary:
	if not _mat_cache.is_empty():
		return _mat_cache
	var m := {}
	var paver := _mat(Color(1, 1, 1), 0.82, 0.0)
	paver.albedo_texture = _paver_tex()
	paver.uv1_triplanar = true
	paver.uv1_scale = Vector3(1.0 / 2.4, 1.0 / 2.4, 1.0 / 2.4)
	m["paver"] = paver
	m["coping"] = _mat(Color(0.80, 0.79, 0.76), 0.62, 0.0)
	m["rubber"] = _mat(Color(0.10, 0.10, 0.11), 0.9, 0.0)
	var tact := _mat(Color(1, 1, 1), 0.7, 0.0)
	tact.albedo_texture = _tactile_tex()
	tact.uv1_triplanar = true
	tact.uv1_scale = Vector3(1.0 / 0.6, 1.0 / 0.6, 1.0 / 0.6)
	m["tactile"] = tact
	m["mark"] = _mat(Color(0.90, 0.90, 0.88), 0.7, 0.0)
	m["stainless"] = _mat(Color(0.78, 0.80, 0.83), 0.22, 0.85)
	m["steel_dark"] = _mat(Color(0.17, 0.19, 0.22), 0.38, 0.7)
	m["frame"] = _mat(Color(0.22, 0.24, 0.27), 0.4, 0.6)
	m["black"] = _mat(Color(0.05, 0.05, 0.06), 0.5, 0.2)
	m["roof_top"] = _mat(Color(0.30, 0.32, 0.35), 0.7, 0.2)
	m["soffit"] = _mat(Color(0.86, 0.87, 0.88), 0.55, 0.15)
	m["accent"] = _mat(Color(0.08, 0.36, 0.66), 0.3, 0.3)
	m["fascia_white"] = _mat(Color(0.94, 0.95, 0.96), 0.35, 0.1)
	m["sign_blue"] = _mat(Color(0.05, 0.22, 0.44), 0.35, 0.2)
	m["wood"] = _mat(Color(0.58, 0.38, 0.22), 0.6, 0.0)
	m["help_yellow"] = _mat(Color(0.95, 0.78, 0.10), 0.5, 0.1)
	m["red_btn"] = _emit_mat(Color(0.8, 0.1, 0.1), Color(1.0, 0.2, 0.15), 0.8)
	m["led"] = _emit_mat(Color(0.95, 0.95, 0.92), Color(1.0, 0.96, 0.88), 2.4)
	m["cis_screen"] = _emit_mat(Color(0.02, 0.02, 0.03), Color(0.08, 0.05, 0.02), 0.6)
	m["tvm_screen"] = _emit_mat(Color(0.08, 0.22, 0.30), Color(0.2, 0.7, 0.95), 1.3)
	m["tap_green"] = _emit_mat(Color(0.08, 0.24, 0.14), Color(0.18, 0.95, 0.52), 1.8)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.62, 0.74, 0.80, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.2
	glass.metallic_specular = 0.9
	m["glass"] = glass
	var frit := StandardMaterial3D.new()
	frit.albedo_color = Color(0.92, 0.94, 0.95, 0.6)
	frit.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frit.roughness = 0.4
	m["frit"] = frit
	m["poster_a"] = _poster_mat(0)
	m["poster_b"] = _poster_mat(1)
	m["map"] = _poster_mat(2)
	_mat_cache = m
	return m


static func _build_bench(parent: Node3D, base: Vector3, side: float, mats: Dictionary) -> void:
	# 3-seat perforated steel bench with armrest dividers; seat faces the track (-side)
	var seat_len := 2.1
	for k in range(5):
		var sx := base.x + side * (-0.17 + float(k) * 0.085)
		_box(parent, Vector3(0.07, 0.035, seat_len), Vector3(sx, base.y + 0.45, base.z), mats["wood"])
	for k in range(4):
		var back := _box(parent, Vector3(0.03, 0.075, seat_len), Vector3(base.x + side * 0.24, base.y + 0.58 + float(k) * 0.095, base.z), mats["wood"])
		back.rotation.z = -side * deg_to_rad(12.0)
	for lz: float in [-seat_len * 0.5 + 0.05, -0.35, 0.35, seat_len * 0.5 - 0.05]:
		_box(parent, Vector3(0.44, 0.04, 0.05), Vector3(base.x, base.y + 0.42, base.z + lz), mats["steel_dark"])
		_box(parent, Vector3(0.05, 0.42, 0.05), Vector3(base.x + side * 0.16, base.y + 0.21, base.z + lz), mats["steel_dark"])
		_box(parent, Vector3(0.05, 0.62, 0.05), Vector3(base.x + side * 0.25, base.y + 0.68, base.z + lz), mats["steel_dark"])
		# Armrest
		_box(parent, Vector3(0.38, 0.035, 0.05), Vector3(base.x + side * 0.02, base.y + 0.65, base.z + lz), mats["steel_dark"])
		_box(parent, Vector3(0.035, 0.2, 0.05), Vector3(base.x - side * 0.15, base.y + 0.55, base.z + lz), mats["steel_dark"])


static func _label(parent: Node3D, txt: String, pos: Vector3, rot_y_deg: float, font_size: int, px: float, col: Color, font: Font) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	if font != null:
		l.font = font
	l.font_size = font_size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.position = pos
	l.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	parent.add_child(l)
	return l


static func _paver_tex() -> ImageTexture:
	var sz := 256 # 2.4m: 4 x 4 pavers of 0.6m
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var tile := sz / 4
	for ty in range(4):
		for tx in range(4):
			var base := Color(0.60, 0.59, 0.56).lerp(Color(0.68, 0.66, 0.62), rng.randf())
			if (tx + ty) % 3 == 0:
				base = base.darkened(0.08)
			for y in range(tile):
				for x in range(tile):
					var c := base.darkened(rng.randf() * 0.06)
					if x == 0 or y == 0 or x == tile - 1 or y == tile - 1:
						c = Color(0.38, 0.37, 0.35)
					img.set_pixel(tx * tile + x, ty * tile + y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _tactile_tex() -> ImageTexture:
	var sz := 96 # 0.6m with 8x8 truncated domes
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.90, 0.72, 0.12))
	var cell := sz / 8
	for gy in range(8):
		for gx in range(8):
			var cx := float(gx * cell) + cell * 0.5
			var cy := float(gy * cell) + cell * 0.5
			for y in range(gy * cell, (gy + 1) * cell):
				for x in range(gx * cell, (gx + 1) * cell):
					var d := Vector2(float(x) + 0.5 - cx, float(y) + 0.5 - cy).length()
					if d < cell * 0.32:
						img.set_pixel(x, y, Color(0.98, 0.84, 0.28) if d < cell * 0.22 else Color(0.72, 0.56, 0.08))
	for i in range(sz):
		img.set_pixel(i, 0, Color(0.6, 0.48, 0.08))
		img.set_pixel(0, i, Color(0.6, 0.48, 0.08))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _poster_mat(kind: int) -> StandardMaterial3D:
	var w := 64
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + kind
	if kind == 2:
		# Stylised network map: white board, coloured lines and station dots
		img.fill(Color(0.95, 0.96, 0.97))
		var cols: Array[Color] = [Color(0.12, 0.54, 0.88), Color(0.9, 0.3, 0.2), Color(0.2, 0.7, 0.35)]
		for li in range(3):
			var y0 := 20 + li * 26
			var x := 6
			var y := y0
			while x < w - 6:
				for t in range(3):
					img.set_pixel(x, clampi(y + t - 1, 0, h - 1), cols[li])
				if x % 14 == 0:
					for oy in range(-2, 3):
						for ox in range(-2, 3):
							img.set_pixel(clampi(x + ox, 0, w - 1), clampi(y + oy, 0, h - 1), Color(1, 1, 1) if absi(ox) + absi(oy) < 2 else cols[li])
				x += 1
				if x % 9 == 0:
					y += rng.randi_range(-3, 3)
		for x in range(w):
			for y in range(8):
				img.set_pixel(x, y, Color(0.08, 0.3, 0.6))
	else:
		var top := Color(0.95, 0.45, 0.2) if kind == 0 else Color(0.2, 0.55, 0.85)
		var bot := Color(0.98, 0.82, 0.3) if kind == 0 else Color(0.85, 0.92, 0.98)
		for y in range(h):
			for x in range(w):
				img.set_pixel(x, y, top.lerp(bot, float(y) / float(h)))
		# product silhouette + headline bars
		for y in range(30, 70):
			for x in range(14, 50):
				var d := Vector2(float(x - 32) / 18.0, float(y - 50) / 20.0).length()
				if d < 1.0:
					img.set_pixel(x, y, Color(1, 1, 1).lerp(top, 0.25 + 0.3 * d))
		for bar in range(3):
			for y in range(8 + bar * 6, 11 + bar * 6):
				for x in range(8, w - 8 - bar * 10):
					img.set_pixel(x, y, Color(1, 1, 1))
		for y in range(80, 88):
			for x in range(8, 30):
				img.set_pixel(x, y, Color(0.1, 0.1, 0.12))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 0.32
	m.roughness = 0.2
	return m
