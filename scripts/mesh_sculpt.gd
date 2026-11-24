class_name MeshSculpt
extends RefCounted

# Procedural high-craft 3D sculpting primitives for vehicles, e-bikes & articulated NPCs:
# smooth lofted hulls, toroidal tires with concave 5-spoke alloy rims & brake rotors,
# tapered 8-20 segment tubes, anatomical capsules, UV ellipsoids, and beveled boxes.


static func _ortho_frame(axis: Vector3) -> Array[Vector3]:
	var u := axis.normalized()
	var ref := Vector3.UP if absf(u.y) < 0.92 else Vector3.RIGHT
	var r := u.cross(ref).normalized()
	var f := r.cross(u).normalized()
	return [r, f, u]


static func emit_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv_a: Vector2 = Vector2.ZERO, uv_b: Vector2 = Vector2.ZERO, uv_c: Vector2 = Vector2.ZERO, uv_d: Vector2 = Vector2.ZERO) -> void:
	var n := (b - a).cross(d - a)
	var nrm := n.normalized() if n.length_squared() > 1e-10 else Vector3.UP
	st.set_color(col); st.set_normal(nrm); st.set_uv(uv_a); st.add_vertex(a)
	st.set_color(col); st.set_normal(nrm); st.set_uv(uv_b); st.add_vertex(b)
	st.set_color(col); st.set_normal(nrm); st.set_uv(uv_c); st.add_vertex(c)
	st.set_color(col); st.set_normal(nrm); st.set_uv(uv_a); st.add_vertex(a)
	st.set_color(col); st.set_normal(nrm); st.set_uv(uv_c); st.add_vertex(c)
	st.set_color(col); st.set_normal(nrm); st.set_uv(uv_d); st.add_vertex(d)


static func emit_smooth_quad(st: SurfaceTool, a: Vector3, na: Vector3, b: Vector3, nb: Vector3, c: Vector3, nc: Vector3, d: Vector3, nd: Vector3, col: Color, uv_a: Vector2 = Vector2.ZERO, uv_b: Vector2 = Vector2.ZERO, uv_c: Vector2 = Vector2.ZERO, uv_d: Vector2 = Vector2.ZERO) -> void:
	st.set_color(col); st.set_normal(na); st.set_uv(uv_a); st.add_vertex(a)
	st.set_color(col); st.set_normal(nb); st.set_uv(uv_b); st.add_vertex(b)
	st.set_color(col); st.set_normal(nc); st.set_uv(uv_c); st.add_vertex(c)
	st.set_color(col); st.set_normal(na); st.set_uv(uv_a); st.add_vertex(a)
	st.set_color(col); st.set_normal(nc); st.set_uv(uv_c); st.add_vertex(c)
	st.set_color(col); st.set_normal(nd); st.set_uv(uv_d); st.add_vertex(d)


static func add_tube(
	st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float,
	segs: int, col: Color, rings: int = 1, cap0: bool = true, cap1: bool = true
) -> void:
	var dv := p1 - p0
	var L := dv.length()
	if L < 1e-4:
		return
	var fr := _ortho_frame(dv)
	var R: Vector3 = fr[0]
	var F: Vector3 = fr[1]
	var U: Vector3 = fr[2]
	var prev_ring: Array[Vector3] = []
	var prev_nrm: Array[Vector3] = []
	for ri in range(rings + 1):
		var t := float(ri) / float(rings)
		var c := p0.lerp(p1, t)
		var rad := lerpf(r0, r1, t)
		var ring: Array[Vector3] = []
		var nrms: Array[Vector3] = []
		for si in range(segs):
			var a := TAU * float(si) / float(segs)
			var dir := R * cos(a) + F * sin(a)
			ring.append(c + dir * rad)
			nrms.append(dir.normalized())
		if ri > 0:
			for si in range(segs):
				var sj := (si + 1) % segs
				emit_smooth_quad(st, prev_ring[si], prev_nrm[si], prev_ring[sj], prev_nrm[sj], ring[sj], nrms[sj], ring[si], nrms[si], col)
		prev_ring = ring
		prev_nrm = nrms
	if cap0 and r0 > 1e-4:
		for si in range(segs):
			var a0 := TAU * float(si) / float(segs)
			var a1 := TAU * float((si + 1) % segs) / float(segs)
			var v0 := p0 + (R * cos(a0) + F * sin(a0)) * r0
			var v1 := p0 + (R * cos(a1) + F * sin(a1)) * r0
			st.set_color(col); st.set_normal(-U); st.add_vertex(p0)
			st.set_color(col); st.set_normal(-U); st.add_vertex(v1)
			st.set_color(col); st.set_normal(-U); st.add_vertex(v0)
	if cap1 and r1 > 1e-4:
		for si in range(segs):
			var a0 := TAU * float(si) / float(segs)
			var a1 := TAU * float((si + 1) % segs) / float(segs)
			var v0 := p1 + (R * cos(a0) + F * sin(a0)) * r1
			var v1 := p1 + (R * cos(a1) + F * sin(a1)) * r1
			st.set_color(col); st.set_normal(U); st.add_vertex(p1)
			st.set_color(col); st.set_normal(U); st.add_vertex(v0)
			st.set_color(col); st.set_normal(U); st.add_vertex(v1)


static func add_ellipsoid(
	st: SurfaceTool, center: Vector3, radii: Vector3,
	segs: int, rings: int, col: Color, rot: Basis = Basis.IDENTITY
) -> void:
	var inv_r := Vector3(1.0 / maxf(1e-4, radii.x), 1.0 / maxf(1e-4, radii.y), 1.0 / maxf(1e-4, radii.z))
	var prev_v: Array[Vector3] = []
	var prev_n: Array[Vector3] = []
	for ri in range(rings + 1):
		var phi := -PI * 0.5 + PI * float(ri) / float(rings)
		var cp := cos(phi)
		var sp := sin(phi)
		var cur_v: Array[Vector3] = []
		var cur_n: Array[Vector3] = []
		for si in range(segs):
			var th := TAU * float(si) / float(segs)
			var lp := Vector3(cp * cos(th) * radii.x, sp * radii.y, cp * sin(th) * radii.z)
			var ln := Vector3(cp * cos(th) * inv_r.x, sp * inv_r.y, cp * sin(th) * inv_r.z).normalized()
			cur_v.append(center + rot * lp)
			cur_n.append((rot * ln).normalized())
		if ri > 0:
			for si in range(segs):
				var sj := (si + 1) % segs
				emit_smooth_quad(st, prev_v[si], prev_n[si], prev_v[sj], prev_n[sj], cur_v[sj], cur_n[sj], cur_v[si], cur_n[si], col)
		prev_v = cur_v
		prev_n = cur_n


static func add_capsule(
	st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float,
	segs: int, rings: int, col: Color
) -> void:
	add_tube(st, p0, p1, r0, r1, segs, col, maxi(1, rings), false, false)
	var hemi := maxi(2, rings / 2 + 1)
	add_ellipsoid(st, p0, Vector3(r0, r0, r0), segs, hemi, col)
	add_ellipsoid(st, p1, Vector3(r1, r1, r1), segs, hemi, col)


# Sculpted 3D toroidal tire + recessed multi-spoke alloy rim + inner brake rotor & caliper!
# If use_veh_uv is true, emits vehicle_pbr.gdshader wheel UVs (x = radial 0..1, y = angle).
static func add_sculpted_wheel(
	st: SurfaceTool, center: Vector3, outer_r: float, tire_w: float,
	out_side: float, maj_segs: int, min_segs: int,
	col_tire: Color, col_rim: Color, col_brake: Color,
	spokes: int = 5, use_veh_uv: bool = false
) -> void:
	var tube_r := clampf(tire_w * 0.48, 0.04, outer_r * 0.42)
	var major_r := outer_r - tube_r
	var rim_r := major_r * 0.88
	var half_w := tire_w * 0.5

	# 1. Smooth 3D Toroidal Rubber Tire (outer tread + curved sidewalls!)
	var prev_v: Array[Vector3] = []
	var prev_n: Array[Vector3] = []
	for i in range(maj_segs + 1):
		var a := TAU * float(i % maj_segs) / float(maj_segs)
		var ca := cos(a)
		var sa := sin(a)
		var ring_c := center + Vector3(0.0, sa * major_r, ca * major_r)
		var rad_dir := Vector3(0.0, sa, ca)
		var cur_v: Array[Vector3] = []
		var cur_n: Array[Vector3] = []
		for j in range(min_segs):
			var b := TAU * float(j) / float(min_segs)
			var cb := cos(b)
			var sb := sin(b)
			# Slightly flatter tread profile across tire width
			var vx := sb * half_w
			var vr := cb * tube_r
			cur_v.append(ring_c + Vector3(vx, rad_dir.y * vr, rad_dir.z * vr))
			cur_n.append(Vector3(sb, rad_dir.y * cb, rad_dir.z * cb).normalized())
		if i > 0:
			for j in range(min_segs):
				var jn := (j + 1) % min_segs
				var uv_t := Vector2(0.88, a) if use_veh_uv else Vector2.ZERO
				emit_smooth_quad(st, prev_v[j], prev_n[j], prev_v[jn], prev_n[jn], cur_v[jn], cur_n[jn], cur_v[j], cur_n[j], col_tire, uv_t, uv_t, uv_t, uv_t)
		prev_v = cur_v
		prev_n = cur_n

	# 2. Recessed Alloy Wheel Barrel & Outer Dish Face (both sides on 2-wheelers, sculpted outer face on cars)
	var face_sides: Array = [-1.0, 1.0] if absf(out_side) < 0.1 else [signf(out_side)]
	for fs: float in face_sides:
		var rim_x := center.x + fs * (half_w * 0.62)
		var dish_x := center.x + fs * (half_w * 0.36)
		var hub_x := center.x + fs * (half_w * 0.52)
		var out_n := Vector3(fs, 0.0, 0.0)
		# Alloy outer lip + concave dish ring
		for i in range(maj_segs):
			var a0 := TAU * float(i) / float(maj_segs)
			var a1 := TAU * float((i + 1) % maj_segs) / float(maj_segs)
			var c0 := cos(a0); var s0 := sin(a0)
			var c1 := cos(a1); var s1 := sin(a1)
			var p_out0 := Vector3(rim_x, center.y + s0 * rim_r, center.z + c0 * rim_r)
			var p_out1 := Vector3(rim_x, center.y + s1 * rim_r, center.z + c1 * rim_r)
			var p_in0 := Vector3(dish_x, center.y + s0 * (rim_r * 0.78), center.z + c0 * (rim_r * 0.78))
			var p_in1 := Vector3(dish_x, center.y + s1 * (rim_r * 0.78), center.z + c1 * (rim_r * 0.78))
			var p_hub0 := Vector3(hub_x, center.y + s0 * (rim_r * 0.25), center.z + c0 * (rim_r * 0.25))
			var p_hub1 := Vector3(hub_x, center.y + s1 * (rim_r * 0.25), center.z + c1 * (rim_r * 0.25))
			var uv0 := Vector2(0.58, a0) if use_veh_uv else Vector2.ZERO
			var uv1 := Vector2(0.58, a1) if use_veh_uv else Vector2.ZERO
			var uvi0 := Vector2(0.42, a0) if use_veh_uv else Vector2.ZERO
			var uvi1 := Vector2(0.42, a1) if use_veh_uv else Vector2.ZERO
			var uvh := Vector2(0.08, a0) if use_veh_uv else Vector2.ZERO
			emit_quad(st, p_out0, p_out1, p_in1, p_in0, col_rim, uv0, uv1, uvi1, uvi0)
			# Inner brake rotor disc behind spokes
			var p_brk0 := Vector3(dish_x - fs * 0.03, center.y + s0 * (rim_r * 0.72), center.z + c0 * (rim_r * 0.72))
			var p_brk1 := Vector3(dish_x - fs * 0.03, center.y + s1 * (rim_r * 0.72), center.z + c1 * (rim_r * 0.72))
			var p_bc := Vector3(dish_x - fs * 0.03, center.y, center.z)
			st.set_color(col_brake); st.set_normal(out_n); st.set_uv(Vector2(0.32, a0) if use_veh_uv else Vector2.ZERO); st.add_vertex(p_bc)
			st.set_color(col_brake); st.set_normal(out_n); st.set_uv(Vector2(0.32, a0) if use_veh_uv else Vector2.ZERO); st.add_vertex(p_brk0)
			st.set_color(col_brake); st.set_normal(out_n); st.set_uv(Vector2(0.32, a1) if use_veh_uv else Vector2.ZERO); st.add_vertex(p_brk1)
			# Center hub cap
			var p_hc := Vector3(hub_x + fs * 0.015, center.y, center.z)
			st.set_color(col_rim); st.set_normal(out_n); st.set_uv(uvh); st.add_vertex(p_hc)
			st.set_color(col_rim); st.set_normal(out_n); st.set_uv(uvh); st.add_vertex(p_hub0)
			st.set_color(col_rim); st.set_normal(out_n); st.set_uv(uvh); st.add_vertex(p_hub1)

		# 3. Real 3D Sculpted Alloy Spokes radiating from center hub to outer rim!
		var sp_r := maxf(0.012, rim_r * 0.095)
		for k in range(spokes):
			var ang := TAU * float(k) / float(spokes)
			var p_a := Vector3(hub_x, center.y + sin(ang) * (rim_r * 0.22), center.z + cos(ang) * (rim_r * 0.22))
			var p_b := Vector3(rim_x - fs * 0.01, center.y + sin(ang) * (rim_r * 0.90), center.z + cos(ang) * (rim_r * 0.90))
			add_tube(st, p_a, p_b, sp_r, sp_r * 0.85, 6, col_rim, 1, false, false)


# Smoothly lofts an array of cross-section rings (each ring: Array[Vector3] with identical vertex count).
# Computes area-weighted smooth vertex normals across adjacent longitudinal & cross-section stations!
static func add_lofted_hull(
	st: SurfaceTool, stations: Array, col: Color, closed_ring: bool = true,
	cap_start: bool = true, cap_end: bool = true
) -> void:
	var n_st := stations.size()
	if n_st < 2:
		return
	var n_p := (stations[0] as Array).size()
	if n_p < 3:
		return

	# Precompute smooth normals at every grid vertex (i, j)
	var nrms: Array = []
	for i in range(n_st):
		var rn: Array[Vector3] = []
		var r_cur: Array = stations[i]
		var r_prev: Array = stations[maxi(0, i - 1)]
		var r_next: Array = stations[mini(n_st - 1, i + 1)]
		for j in range(n_p):
			var jp := (j - 1 + n_p) % n_p if closed_ring else maxi(0, j - 1)
			var jn := (j + 1) % n_p if closed_ring else mini(n_p - 1, j + 1)
			var du: Vector3 = (r_next[j] as Vector3) - (r_prev[j] as Vector3)
			var dv: Vector3 = (r_cur[jn] as Vector3) - (r_cur[jp] as Vector3)
			var cr := du.cross(dv)
			rn.append(cr.normalized() if cr.length_squared() > 1e-10 else Vector3.UP)
		nrms.append(rn)

	var j_lim := n_p if closed_ring else (n_p - 1)
	for i in range(n_st - 1):
		var r0: Array = stations[i]
		var r1: Array = stations[i + 1]
		var n0: Array = nrms[i]
		var n1: Array = nrms[i + 1]
		for j in range(j_lim):
			var jn := (j + 1) % n_p
			emit_smooth_quad(st, r0[j], n0[j], r1[j], n1[j], r1[jn], n1[jn], r0[jn], n0[jn], col)

	if cap_start:
		var r_first: Array = stations[0]
		var cen := Vector3.ZERO
		for v: Vector3 in r_first:
			cen += v
		cen /= float(n_p)
		for j in range(n_p):
			var jn := (j + 1) % n_p
			var v0: Vector3 = r_first[j]
			var v1: Vector3 = r_first[jn]
			var fn := (v1 - cen).cross(v0 - cen)
			var fnrm := fn.normalized() if fn.length_squared() > 1e-10 else Vector3.FORWARD
			st.set_color(col); st.set_normal(fnrm); st.add_vertex(cen)
			st.set_color(col); st.set_normal(fnrm); st.add_vertex(v1)
			st.set_color(col); st.set_normal(fnrm); st.add_vertex(v0)

	if cap_end:
		var r_last: Array = stations[n_st - 1]
		var cen := Vector3.ZERO
		for v: Vector3 in r_last:
			cen += v
		cen /= float(n_p)
		for j in range(n_p):
			var jn := (j + 1) % n_p
			var v0: Vector3 = r_last[j]
			var v1: Vector3 = r_last[jn]
			var fn := (v0 - cen).cross(v1 - cen)
			var fnrm := fn.normalized() if fn.length_squared() > 1e-10 else Vector3.BACK
			st.set_color(col); st.set_normal(fnrm); st.add_vertex(cen)
			st.set_color(col); st.set_normal(fnrm); st.add_vertex(v0)
			st.set_color(col); st.set_normal(fnrm); st.add_vertex(v1)


# Sweeps ONE continuous seamless organic tube along a 3D multi-joint polyline (e.g. shoulder -> elbow -> wrist,
# or pelvis -> thigh -> knee -> calf -> ankle) using Bishop parallel-transport frames so joints bend smoothly
# with ZERO pinched spheres or balloon seams!
static func add_swept_limb(
	st: SurfaceTool,
	pts: Array[Vector3],
	rads: Array[float],
	segs: int,
	col: Color,
	cap_a: bool = true,
	cap_b: bool = true
) -> void:
	var n := pts.size()
	if n < 2 or rads.size() != n:
		return

	# Build smoothed tangents at each station
	var tangs: Array[Vector3] = []
	for i in range(n):
		var t_vec := Vector3.ZERO
		if i == 0:
			t_vec = pts[1] - pts[0]
		elif i == n - 1:
			t_vec = pts[n - 1] - pts[n - 2]
		else:
			var d0 := (pts[i] - pts[i - 1]).normalized()
			var d1 := (pts[i + 1] - pts[i]).normalized()
			t_vec = d0 + d1
			if t_vec.length_squared() < 1e-6:
				t_vec = d0
		tangs.append(t_vec.normalized() if t_vec.length_squared() > 1e-8 else Vector3.UP)

	# Parallel-transport orthonormal cross-section frame (u, v) along the limb curve
	var ref := Vector3.RIGHT if absf(tangs[0].dot(Vector3.RIGHT)) < 0.85 else Vector3.FORWARD
	var u := tangs[0].cross(ref).normalized()
	var v := tangs[0].cross(u).normalized()
	var rings_v: Array = []
	var rings_n: Array = []
	for i in range(n):
		var ti := tangs[i]
		if i > 0:
			var prev_t := tangs[i - 1]
			var axis := prev_t.cross(ti)
			var sin_a := axis.length()
			if sin_a > 1e-5:
				var ang := atan2(sin_a, clampf(prev_t.dot(ti), -1.0, 1.0))
				var q := Quaternion(axis / sin_a, ang)
				u = (q * u).normalized()
			# Re-orthogonalize cleanly
			u = (u - ti * u.dot(ti)).normalized()
			v = ti.cross(u).normalized()
		var r := rads[i]
		var rv: Array[Vector3] = []
		var rn: Array[Vector3] = []
		for j in range(segs):
			var a := TAU * float(j) / float(segs)
			var nrm := (u * cos(a) + v * sin(a)).normalized()
			rv.append(pts[i] + nrm * r)
			rn.append(nrm)
		rings_v.append(rv)
		rings_n.append(rn)

	# Connect consecutive rings with guaranteed outward-facing smooth quads
	for i in range(n - 1):
		var r0: Array = rings_v[i]
		var r1: Array = rings_v[i + 1]
		var n0: Array = rings_n[i]
		var n1: Array = rings_n[i + 1]
		for j in range(segs):
			var jn := (j + 1) % segs
			var v0: Vector3 = r0[j]
			var v1: Vector3 = r1[j]
			var v2: Vector3 = r1[jn]
			var v3: Vector3 = r0[jn]
			var avg_n := ((n0[j] as Vector3) + (n1[j] as Vector3) + (n1[jn] as Vector3) + (n0[jn] as Vector3)).normalized()
			if (v1 - v0).cross(v2 - v0).dot(avg_n) >= 0.0:
				emit_smooth_quad(st, v0, n0[j], v1, n1[j], v2, n1[jn], v3, n0[jn], col)
			else:
				emit_smooth_quad(st, v0, n0[j], v3, n0[jn], v2, n1[jn], v1, n1[j], col)

	if cap_a:
		var rf: Array = rings_v[0]
		var fn := -tangs[0]
		for j in range(segs):
			var jn := (j + 1) % segs
			var v0: Vector3 = rf[j]
			var v1: Vector3 = rf[jn]
			if (v1 - pts[0]).cross(v0 - pts[0]).dot(fn) >= 0.0:
				st.set_color(col); st.set_normal(fn); st.add_vertex(pts[0])
				st.set_color(col); st.set_normal(fn); st.add_vertex(v1)
				st.set_color(col); st.set_normal(fn); st.add_vertex(v0)
			else:
				st.set_color(col); st.set_normal(fn); st.add_vertex(pts[0])
				st.set_color(col); st.set_normal(fn); st.add_vertex(v0)
				st.set_color(col); st.set_normal(fn); st.add_vertex(v1)
	if cap_b:
		var rl: Array = rings_v[n - 1]
		var fn2 := tangs[n - 1]
		for j in range(segs):
			var jn := (j + 1) % segs
			var v0: Vector3 = rl[j]
			var v1: Vector3 = rl[jn]
			if (v0 - pts[n - 1]).cross(v1 - pts[n - 1]).dot(fn2) >= 0.0:
				st.set_color(col); st.set_normal(fn2); st.add_vertex(pts[n - 1])
				st.set_color(col); st.set_normal(fn2); st.add_vertex(v0)
				st.set_color(col); st.set_normal(fn2); st.add_vertex(v1)
			else:
				st.set_color(col); st.set_normal(fn2); st.add_vertex(pts[n - 1])
				st.set_color(col); st.set_normal(fn2); st.add_vertex(v1)
				st.set_color(col); st.set_normal(fn2); st.add_vertex(v0)
