class_name CarMeshGen
extends RefCounted

# High-Craft 3-Level LOD Procedural Automotive Sculptor (LOD0: 8,200-11,500 tris, LOD1: ~3,800 tris, LOD2: ~1,100 tris).
# Builds double-curved multi-station lofted bodywork (tumblehome doors, crowned hood/roof, flared wheel arches),
# 20-segment toroidal rubber tires + 5-spoke concave alloy rims + brake rotors, sculpted mirrors, door handles,
# shark-fin antennas, EV Star-Ring LEDs, roof LiDAR watchtowers, and independent Brake/Turn indicator lamps!


static func _pbr(c: Color, mat_id: int) -> Color:
	return Color(c.r, c.g, c.b, float(mat_id) * 0.1)


# Returns {"lod0": ArrayMesh, "lod1": ArrayMesh, "lod2": ArrayMesh} for a vehicle spec dict.
static func build_lod_bundle(sp: Dictionary) -> Dictionary:
	return {
		"lod0": _build_car_lod(sp, 0),
		"lod1": _build_car_lod(sp, 1),
		"lod2": _build_car_lod(sp, 2),
	}


static func get_tri_count(m: ArrayMesh) -> int:
	if m == null or m.get_surface_count() == 0:
		return 0
	var arrs := m.surface_get_arrays(0)
	return (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


static func _build_car_lod(sp: Dictionary, lod: int) -> ArrayMesh:
	var body_rgb: Color = sp.get("col", Color(0.84, 0.86, 0.89))
	var body_t: String = str(sp.get("body", "sedan"))
	var is_ev := bool(sp.get("ev", false))
	var is_zh := bool(sp.get("zh", false))
	var is_micro := body_t == "micro"
	var is_hatch := body_t == "hatch"
	var is_suv := body_t == "suv"
	var is_fast := body_t == "fastback"
	var is_xover := body_t == "crossover"
	var is_taxi := bool(sp.get("taxi", false))
	var is_us_taxi := bool(sp.get("us_taxi", false))

	var c_paint := _pbr(body_rgb, 0)
	var c_white := _pbr(Color(0.94, 0.95, 0.96), 0)
	var c_glass := _pbr(Color(0.07, 0.11, 0.16), 1)
	var c_tire := _pbr(Color(0.09, 0.09, 0.10), 2)
	var c_rim := _pbr(Color(0.76, 0.79, 0.83), 3)
	var c_brake := _pbr(Color(0.36, 0.38, 0.41), 3)
	var c_trim := _pbr(Color(0.12, 0.13, 0.15), 3)
	var c_chrome := _pbr(Color(0.78, 0.81, 0.85), 3)
	var c_head := _pbr(Color(1.0, 0.97, 0.90), 4)
	var c_tail := _pbr(Color(0.96, 0.10, 0.10), 5)
	var c_turn := _pbr(Color(0.95, 0.62, 0.08), 6)
	var c_plate := _pbr(
		Color(0.24, 0.88, 0.44) if (is_zh and is_ev) else (Color(0.08, 0.30, 0.78) if is_zh else Color(0.92, 0.92, 0.90)),
		3
	)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := 0.74 if is_micro else (0.84 if is_hatch else (0.94 if is_suv else 0.89))
	var roof_y := 1.54 if is_micro else (1.58 if is_suv else (1.46 if is_xover else (1.42 if is_hatch else (1.30 if is_fast else 1.36))))
	var front_z := -1.48 if is_micro else (-1.92 if is_hatch else -2.22)
	var rear_z := 1.48 if is_micro else (1.90 if is_hatch else 2.20)
	var sill_y := 0.24 if is_suv else 0.21
	var belt_y := 0.95 if is_suv else (0.86 if is_micro else 0.82)

	# Longitudinal profile control points: [z, y_bot, y_top, width_scale, greenhouse_taper]
	var prof_ctrl: Array = []
	var ws_z0 := -0.88; var ws_z1 := -0.26; var rw_z0 := 0.92; var rw_z1 := 1.56; var trunk_y := 0.90
	if is_micro:
		ws_z0 = -0.88; ws_z1 = -0.56; rw_z0 = 1.16; rw_z1 = 1.44; trunk_y = 0.94
		prof_ctrl = [
			[-1.49, 0.30, 0.56, 0.84, 0.0],
			[-1.42, 0.22, 0.76, 0.95, 0.0],
			[-1.12, 0.21, 0.83, 1.00, 0.0],
			[-0.88, 0.21, 0.86, 1.01, 0.02],
			[-0.56, 0.21, roof_y, 1.00, 0.14],
			[0.30,  0.21, roof_y + 0.01, 1.00, 0.14],
			[1.16,  0.21, roof_y - 0.01, 0.99, 0.14],
			[1.44,  0.23, 0.94, 0.96, 0.02],
			[1.49,  0.34, 0.54, 0.84, 0.0],
		]
	elif is_suv:
		ws_z0 = -0.94; ws_z1 = -0.34; rw_z0 = 1.66; rw_z1 = 2.02; trunk_y = 1.08
		prof_ctrl = [
			[-2.24, 0.36, 0.66, 0.82, 0.0],
			[-2.14, 0.26, 0.88, 0.95, 0.0],
			[-1.65, 0.25, 0.94, 1.01, 0.0],
			[-0.94, 0.25, 0.97, 1.02, 0.02],
			[-0.34, 0.25, roof_y, 1.01, 0.16],
			[0.65,  0.25, roof_y + 0.02, 1.01, 0.16],
			[1.66,  0.26, roof_y - 0.02, 0.99, 0.15],
			[2.02,  0.27, 1.08, 0.96, 0.04],
			[2.19,  0.32, 0.96, 0.92, 0.0],
			[2.23,  0.40, 0.56, 0.82, 0.0],
		]
	elif is_hatch:
		ws_z0 = -0.82; ws_z1 = -0.28; rw_z0 = 1.24; rw_z1 = 1.76; trunk_y = 0.98
		prof_ctrl = [
			[-1.93, 0.30, 0.54, 0.82, 0.0],
			[-1.78, 0.22, 0.74, 0.95, 0.0],
			[-1.32, 0.22, 0.81, 1.01, 0.0],
			[-0.82, 0.22, 0.85, 1.01, 0.02],
			[-0.28, 0.22, roof_y, 1.00, 0.17],
			[0.52,  0.22, roof_y + 0.015, 1.00, 0.17],
			[1.24,  0.22, roof_y - 0.02, 0.98, 0.16],
			[1.76,  0.24, 0.98, 0.94, 0.03],
			[1.90,  0.34, 0.54, 0.82, 0.0],
		]
	elif is_fast or is_xover:
		ws_z0 = -0.90; ws_z1 = -0.22; rw_z0 = 0.76; rw_z1 = 1.88; trunk_y = 0.92 if is_fast else 1.00
		prof_ctrl = [
			[-2.23, 0.28, 0.48, 0.80, 0.0],
			[-2.06, 0.20, 0.68, 0.94, 0.0],
			[-1.50, 0.20, 0.76, 1.02, 0.0],
			[-0.90, 0.20, 0.81, 1.02, 0.02],
			[-0.22, 0.20, roof_y, 1.01, 0.19],
			[0.32,  0.20, roof_y + 0.02, 1.01, 0.19],
			[0.76,  0.20, roof_y - 0.02, 1.00, 0.18],
			[1.42,  0.21, lerpf(roof_y, trunk_y, 0.58), 0.99, 0.11],
			[1.88,  0.22, trunk_y, 0.97, 0.03],
			[2.16,  0.26, trunk_y - 0.06, 0.91, 0.0],
			[2.21,  0.34, 0.50, 0.80, 0.0],
		]
	else:
		ws_z0 = -0.88; ws_z1 = -0.28; rw_z0 = 0.92; rw_z1 = 1.56; trunk_y = 0.88
		prof_ctrl = [
			[-2.21, 0.30, 0.52, 0.82, 0.0],
			[-2.05, 0.22, 0.72, 0.95, 0.0],
			[-1.48, 0.22, 0.78, 1.01, 0.0],
			[-0.88, 0.22, 0.83, 1.01, 0.02],
			[-0.28, 0.22, roof_y, 1.00, 0.18],
			[0.36,  0.22, roof_y + 0.02, 1.00, 0.18],
			[0.92,  0.22, roof_y - 0.02, 0.99, 0.17],
			[1.56,  0.22, 0.89, 0.98, 0.03],
			[2.12,  0.25, 0.85, 0.93, 0.0],
			[2.19,  0.34, 0.52, 0.82, 0.0],
		]

	# 1. Double-Curved 3D Lofted Automotive Bodywork (LOD0: ~8,700 tris, LOD1: ~3,800 tris, LOD2: ~1,130 tris!)
	var ring_segs := 48 if lod == 0 else (30 if lod == 1 else 10)
	var sub_steps := 4 if lod == 0 else (2 if lod == 1 else 1)
	var stations: Array = []
	for ci in range(prof_ctrl.size()):
		var cur: Array = prof_ctrl[ci]
		stations.append(_make_car_section_ring(float(cur[0]), float(cur[1]), float(cur[2]), hw * float(cur[3]), float(cur[4]), belt_y, ring_segs))
		if sub_steps > 1 and ci < prof_ctrl.size() - 1:
			var nxt: Array = prof_ctrl[ci + 1]
			for sbi in range(1, sub_steps):
				var frac := float(sbi) / float(sub_steps)
				stations.append(_make_car_section_ring(
					lerpf(float(cur[0]), float(nxt[0]), frac),
					lerpf(float(cur[1]), float(nxt[1]), frac),
					lerpf(float(cur[2]), float(nxt[2]), frac),
					hw * lerpf(float(cur[3]), float(nxt[3]), frac),
					lerpf(float(cur[4]), float(nxt[4]), frac),
					belt_y, ring_segs
				))
	var wr := 0.27 if is_micro else (0.36 if is_suv else 0.33)
	var wz_f := -0.96 if is_micro else (-1.22 if is_hatch else -1.38)
	var wz_r := 0.96 if is_micro else (1.20 if is_hatch else 1.36)
	# Glazing, pillars, sill cladding and wheel wells are painted onto the body loft itself, so the windows
	# follow the body surface exactly (no glass panels floating over / buried in the paint)
	var c_well := _pbr(Color(0.035, 0.037, 0.04), 3)
	var pano := is_ev and not is_micro and not is_taxi
	var clad := is_suv or is_xover
	var b_z := lerpf(ws_z1, rw_z0, 0.42)
	# Greenhouse sides / glass areas of the shell are dark trim; the glass itself is shrink-wrapped panels
	# laid on the shell below (clean outlines at every LOD, no staircase edges)
	var region := func(c: Vector3, n: Vector3) -> Color:
		if c.y > belt_y + 0.025:
			if n.y > 0.78 and c.y > roof_y - 0.10:
				return c_paint
			if c.z > ws_z1 and c.z < rw_z0 and absf(n.x) > 0.30:
				return c_trim # window frames / B-pillar band between the A- and C-pillars
			return c_paint
		if absf(n.x) > 0.45:
			for wz: float in [wz_f, wz_r]:
				if Vector2(c.y - wr, c.z - wz).length() < wr + 0.07 and c.y < wr + 0.34:
					return c_well
			if c.y < sill_y + (0.13 if clad else 0.07):
				return c_trim
		return c_paint
	MeshSculpt.add_lofted_hull(st, stations, c_paint, true, true, true, region)

	# Wheel-arch fender flare trim rings on LOD0 & LOD1
	if lod <= 1:
		var arch_segs := 14 if lod == 0 else 8
		for sx: float in [-1.0, 1.0]:
			for wz: float in [wz_f, wz_r]:
				_emit_wheel_arch_flare(st, Vector3(sx * (hw + 0.015), wr + 0.02, wz), wr + 0.055, sx, arch_segs, c_trim if is_suv else c_paint)

	# Two-tone white roof on Wuling MINIEV & Jiaxing EV Taxis
	if is_micro or is_taxi:
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, roof_y + 0.025, (ws_z1 + rw_z0) * 0.5)),
			Vector3(hw * 1.48, 0.04, maxf(0.85, rw_z0 - ws_z1)), c_white)

	# 2. Glazing: panels shrink-wrapped onto the shell surface (windscreen, backlight, side windows split by the
	# B-pillar, panoramic roof) with UVs so the shader draws the black ceramic frit border
	if lod <= 1:
		var ring_at := func(z: float) -> Array[Vector3]:
			var ci := 0
			while ci < prof_ctrl.size() - 2 and float(prof_ctrl[ci + 1][0]) < z:
				ci += 1
			var a0: Array = prof_ctrl[ci]
			var a1: Array = prof_ctrl[ci + 1]
			var f := clampf((z - float(a0[0])) / maxf(0.001, float(a1[0]) - float(a0[0])), 0.0, 1.0)
			return _make_car_section_ring(z, lerpf(float(a0[1]), float(a1[1]), f), lerpf(float(a0[2]), float(a1[2]), f),
				hw * lerpf(float(a0[3]), float(a1[3]), f), lerpf(float(a0[4]), float(a1[4]), f), belt_y, ring_segs)
		var off := 0.02 if lod == 0 else 0.035
		var gn := 7 if lod == 0 else 3
		# top surface point at (z, x): windscreen / backlight / roof
		var top_pt := func(z: float, x: float) -> Vector3:
			var r: Array[Vector3] = ring_at.call(z)
			var y_lo := 1e9
			var y_hi := -1e9
			for v: Vector3 in r:
				y_lo = minf(y_lo, v.y)
				y_hi = maxf(y_hi, v.y)
			var y_mid := (y_lo + y_hi) * 0.5
			var found := false
			var best := Vector3(x, y_hi, z)
			var near_d := 1e9
			for k in range(r.size()):
				var a := r[k]
				var b := r[(k + 1) % r.size()]
				if a.y < y_mid or b.y < y_mid:
					continue
				if absf(a.x - x) < near_d:
					near_d = absf(a.x - x)
					if not found:
						best = a
				if (a.x - x) * (b.x - x) <= 0.0 and absf(a.x - b.x) > 1e-5:
					var t := (x - a.x) / (b.x - a.x)
					var y := lerpf(a.y, b.y, t)
					if not found or y > best.y:
						best = Vector3(x, y, z)
						found = true
			return best
		# side surface point at (z, y) on side sgn
		var side_pt := func(z: float, y: float, sgn: float) -> Vector3:
			var r: Array[Vector3] = ring_at.call(z)
			for k in range(r.size()):
				var a := r[k]
				var b := r[(k + 1) % r.size()]
				if a.x * sgn < hw * 0.3 or b.x * sgn < hw * 0.3:
					continue
				if (a.y - y) * (b.y - y) <= 0.0 and absf(a.y - b.y) > 1e-5:
					var t := (y - a.y) / (b.y - a.y)
					return Vector3(lerpf(a.x, b.x, t), y, z)
			return Vector3(sgn * hw * 0.85, y, z)
		var panel := func(pt_fn: Callable, u0: float, u1: float, v0: float, v1: float, nu: int, nv: int, flip: bool) -> void:
			var grid: Array = []
			for iv in range(nv + 1):
				var row: Array[Vector3] = []
				for iu in range(nu + 1):
					row.append(pt_fn.call(lerpf(u0, u1, float(iu) / float(nu)), lerpf(v0, v1, float(iv) / float(nv))))
				grid.append(row)
			var ctr_body := Vector3(0.0, (belt_y + roof_y) * 0.5, 0.0)
			for iv in range(nv):
				for iu in range(nu):
					var p00: Vector3 = grid[iv][iu]
					var p10: Vector3 = grid[iv][iu + 1]
					var p11: Vector3 = grid[iv + 1][iu + 1]
					var p01: Vector3 = grid[iv + 1][iu]
					var n := (p10 - p00).cross(p01 - p00).normalized()
					if n.dot(p00 - Vector3(0.0, ctr_body.y, p00.z * 0.3)) < 0.0:
						n = -n
					var uv00 := Vector2(float(iu) / float(nu), float(iv) / float(nv))
					var uv10 := Vector2(float(iu + 1) / float(nu), float(iv) / float(nv))
					var uv11 := Vector2(float(iu + 1) / float(nu), float(iv + 1) / float(nv))
					var uv01 := Vector2(float(iu) / float(nu), float(iv + 1) / float(nv))
					var q := [p00 + n * off, p10 + n * off, p11 + n * off, p01 + n * off]
					if flip:
						MeshSculpt.emit_smooth_quad(st, q[0], n, q[3], n, q[2], n, q[1], n, c_glass, uv00, uv01, uv11, uv10)
					else:
						MeshSculpt.emit_smooth_quad(st, q[0], n, q[1], n, q[2], n, q[3], n, c_glass, uv00, uv10, uv11, uv01)
		var ws_w := func(z: float) -> float:
			var r: Array[Vector3] = ring_at.call(z)
			var mx := 0.0
			for v: Vector3 in r:
				if v.y > belt_y + 0.05:
					mx = maxf(mx, absf(v.x))
			return mx
		var w_ws := hw * 0.80 # between the A-pillars
		var w_rw := hw * 0.70
		panel.call(func(u: float, v: float) -> Vector3: return top_pt.call(v, u), -w_ws, w_ws, ws_z0 + 0.03, ws_z1 - 0.02, gn, gn, false)
		panel.call(func(u: float, v: float) -> Vector3: return top_pt.call(v, u), -w_rw, w_rw, rw_z0 + 0.02, rw_z1 - 0.03, gn, gn, false)
		if pano:
			var w_rf := hw * 0.58
			panel.call(func(u: float, v: float) -> Vector3: return top_pt.call(v, u), -w_rf, w_rf, ws_z1 + 0.08, rw_z0 - 0.08, gn, gn, false)
		for sgn: float in [-1.0, 1.0]:
			var y0 := belt_y + 0.045
			for zr: Vector2 in [Vector2(ws_z1 + 0.10, b_z - 0.05), Vector2(b_z + 0.05, rw_z0 - 0.14)]:
				# window top follows the roof line: sample the side at the cant rail height of that z
				var y1 := roof_y - 0.075
				panel.call(func(u: float, v: float) -> Vector3: return side_pt.call(u, v, sgn), zr.x, zr.y, y0, y1, gn + 2, maxi(2, gn - 3), sgn < 0.0)

	# 3. Mirrors and door handles
	for side: float in [-1.0, 1.0]:
		# Sculpted aerodynamic wing mirrors + flush door handles on LOD0 & LOD1
		if lod <= 1:
			var m_pos := Vector3(side * (hw + 0.10), belt_y + 0.08, ws_z0 + 0.24)
			MeshSculpt.add_tube(st, Vector3(side * (hw - 0.02), belt_y + 0.05, ws_z0 + 0.25), m_pos, 0.024, 0.018, 6, c_trim, 1)
			MeshSculpt.add_ellipsoid(st, m_pos, Vector3(0.095, 0.055, 0.072), 10 if lod == 0 else 6, 6 if lod == 0 else 4, c_paint)
			if lod == 0:
				for hz: float in [-0.08, 0.72]:
					if hz < rw_z1 - 0.3:
						CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(side * (hw + 0.015), belt_y - 0.08, hz)),
							Vector3(0.03, 0.035, 0.16), c_chrome if not is_ev else c_trim)

	# 3. Sculpted Bumpers, EV Aero Nose vs ICE Grille, License Plates, Shark-Fin Antenna & Roof LiDAR!
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, sill_y + 0.04, front_z + 0.06)), Vector3(hw * 1.62, 0.08, 0.12), c_trim)
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, sill_y + 0.05, rear_z - 0.06)), Vector3(hw * 1.60, 0.12, 0.12), c_trim)
	if not is_ev:
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.50, front_z + 0.02)), Vector3(hw * 1.24, 0.24, 0.06), c_trim)
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.63, front_z + 0.01)), Vector3(hw * 1.28, 0.032, 0.06), c_chrome)
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.36, front_z - 0.01)), Vector3(0.44, 0.12, 0.03), c_plate)
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.48, rear_z + 0.01)), Vector3(0.44, 0.12, 0.03), c_plate)

	if lod == 0 and not is_micro:
		# Shark-fin roof antenna
		MeshSculpt.add_ellipsoid(st, Vector3(0.0, roof_y + 0.045, rw_z0 - 0.18), Vector3(0.024, 0.055, 0.11), 8, 5, c_paint)
	if bool(sp.get("lidar", false)) and lod <= 1:
		# Signature Chinese Smart-EV Roof LiDAR Watchtower (Xiaomi SU7 / Li Auto / NIO!)
		MeshSculpt.add_ellipsoid(st, Vector3(0.0, roof_y + 0.038, ws_z1 + 0.05), Vector3(0.11, 0.042, 0.10), 10 if lod == 0 else 6, 5, c_trim)
		if bool(sp.get("nio_ears", false)):
			for ex: float in [-0.36, 0.36]:
				MeshSculpt.add_ellipsoid(st, Vector3(ex, roof_y + 0.030, ws_z1 + 0.07), Vector3(0.055, 0.032, 0.075), 8 if lod == 0 else 5, 4, c_trim)

	# 4. Independent Headlights (mat_id=4), Dynamic Ruby Brake/Taillights (mat_id=5), & Dynamic Amber Turn Signals (mat_id=6)!
	var head_y := 0.72 if is_suv else 0.62
	if bool(sp.get("star_ring", false)):
		# Li Auto full-width glowing Star-Ring front LED bar!
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.85, front_z + 0.05)), Vector3(hw * 1.72, 0.052, 0.07), c_head)
		for lx: float in [-hw * 0.70, hw * 0.70]:
			CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(lx, 0.56, front_z + 0.03)), Vector3(0.24, 0.10, 0.06), c_head)
	else:
		for lx: float in [-hw * 0.70, hw * 0.70]:
			if lod == 0:
				MeshSculpt.add_ellipsoid(st, Vector3(lx, head_y, front_z + 0.06), Vector3(0.18, 0.065, 0.06), 10, 5, c_head)
			else:
				CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(lx, head_y, front_z + 0.05)), Vector3(0.32, 0.10, 0.07), c_head)
	# Rear dynamic ruby LED brake bar + outer clusters + amber turn indicators!
	var tail_y := 0.86 if is_suv else 0.72
	CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, tail_y, rear_z - 0.01)), Vector3(hw * 1.56, 0.052, 0.06), c_tail)
	for lx: float in [-hw * 0.70, hw * 0.70]:
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(lx, tail_y - 0.02, rear_z - 0.01)), Vector3(0.30, 0.11, 0.07), c_tail)
		# Front & rear amber dynamic turn indicators (mat_id = 6)!
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(lx * 1.12, head_y - 0.04, front_z + 0.08)), Vector3(0.11, 0.055, 0.06), c_turn)
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(lx * 1.12, tail_y - 0.07, rear_z - 0.02)), Vector3(0.12, 0.055, 0.06), c_turn)

	if is_taxi or is_us_taxi:
		CityBuilder._emit_colored_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, roof_y + 0.09, 0.08)), Vector3(0.46, 0.13, 0.18), c_head)

	# 5. Four Sculpted Wheels: LOD0 = 20-seg Toroidal Tire + 5-Spoke Alloy Rim + Brake Rotor; LOD1 = 16-seg; LOD2 = 10-seg!
	var w_maj := 20 if lod == 0 else (16 if lod == 1 else 10)
	var w_min := 16 if lod == 0 else (8 if lod == 1 else 4)
	var tw := 0.20 if is_micro else 0.24
	for wx: float in [-(hw - 0.04), (hw - 0.04)]:
		for wz: float in [wz_f, wz_r]:
			MeshSculpt.add_sculpted_wheel(st, Vector3(wx, wr, wz), wr, tw, signf(wx), w_maj, w_min, c_tire, c_rim, c_brake, 5, true)

	return st.commit()


# Generates a smooth contoured automotive cross-section ring at longitudinal position z:
# flat underbody -> rounded lower rocker -> tumblehome body sides -> shoulder crease -> crowned hood/roof dome!
static func _make_car_section_ring(z: float, y_bot: float, y_top: float, hw: float, gh_taper: float, belt_y: float, segs: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var h := maxf(0.12, y_top - y_bot)
	var mid_y := (y_bot + y_top) * 0.5
	var ry := h * 0.5
	for i in range(segs):
		var a := TAU * float(i) / float(segs) # 0 = +X right, PI/2 = +Y top, PI = -X left, 3PI/2 = -Y bottom
		var ca := cos(a)
		var sa := sin(a)
		# Superellipse cross-section (p=3.2) for sleek sculpted automotive shoulders instead of a sharp rectangle!
		var sx := signf(ca) * pow(absf(ca), 0.62)
		var sy := signf(sa) * pow(absf(sa), 0.68)
		var y := mid_y + sy * ry
		var x := sx * hw
		# Greenhouse tumblehome taper above beltline
		if y > belt_y and gh_taper > 0.001:
			var t_up := clampf((y - belt_y) / maxf(0.15, y_top - belt_y), 0.0, 1.0)
			x *= (1.0 - gh_taper * pow(t_up, 1.15))
		# Subtle lower rocker tuck near ground
		elif y < y_bot + 0.14:
			var t_dn := clampf((y_bot + 0.14 - y) / 0.14, 0.0, 1.0)
			x *= (1.0 - 0.07 * t_dn)
		pts.append(Vector3(x, y, z))
	return pts


static func _emit_wheel_arch_flare(st: SurfaceTool, c: Vector3, rad: float, side: float, segs: int, col: Color) -> void:
	var lip := 0.045
	var out_n := Vector3(side, 0.2, 0.0).normalized()
	for i in range(segs):
		var a0 := lerpf(-0.15, PI + 0.15, float(i) / float(segs))
		var a1 := lerpf(-0.15, PI + 0.15, float(i + 1) / float(segs))
		var p_in0 := c + Vector3(0.0, sin(a0) * rad, cos(a0) * rad)
		var p_in1 := c + Vector3(0.0, sin(a1) * rad, cos(a1) * rad)
		var p_out0 := c + Vector3(side * lip, sin(a0) * (rad + 0.045), cos(a0) * (rad + 0.045))
		var p_out1 := c + Vector3(side * lip, sin(a1) * (rad + 0.045), cos(a1) * (rad + 0.045))
		MeshSculpt.emit_smooth_quad(st, p_in0, out_n, p_in1, out_n, p_out1, out_n, p_out0, out_n, col)


static func _emit_curved_glass_panel(
	st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
	bow: float, subs: int, col: Color
) -> void:
	var base_n := (p1 - p0).cross(p3 - p0).normalized()
	for ix in range(subs):
		var u0 := float(ix) / float(subs)
		var u1 := float(ix + 1) / float(subs)
		var b0 := sin(u0 * PI) * bow
		var b1 := sin(u1 * PI) * bow
		var v0 := p0.lerp(p1, u0) + base_n * b0
		var v1 := p0.lerp(p1, u1) + base_n * b1
		var v2 := p3.lerp(p2, u1) + base_n * b1
		var v3 := p3.lerp(p2, u0) + base_n * b0
		MeshSculpt.emit_smooth_quad(st, v0, base_n, v1, base_n, v2, base_n, v3, base_n, col,
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0))
