class_name HumanMeshGen
extends RefCounted

# High-Precision Procedural 3D Human Commuter & Apparel Generator (4 Urban Archetypes).
# Features indexed smooth-shaded anatomical geometry (head, hair, sloping shoulders, articulated limbs),
# warm natural non-uncanny facial features, and surface-conforming tailored clothing & commuter gear
# (placket/metallic zippers, folded collars, contoured backpacks with S-curved shoulder straps,
# body-hugging crossbody straps, curved headphones, knit scarves, caps & beanies).

static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------------------------
# 1. Anatomical Head, Layered Hair & Natural Facial Features
# ---------------------------------------------------------------------------------------------

# Unified parametric anatomical head surface: v in [0..1] (chin -> crown), a in [0..TAU) (sa < 0 is front face -Z)
static func _eval_head_point(v: float, a: float) -> Vector3:
	var ca := cos(a)
	var sa := sin(a) # -1 = front face (-Z), +1 = back of skull (+Z)
	var y := lerpf(-0.104, 0.114, v)

	# Smooth natural ovoid cranium transitioning smoothly into jawline and softly rounded chin
	var theta := lerpf(-PI * 0.45, PI * 0.47, v)
	var ct := cos(theta)
	var y_sphere := sin(theta) * 0.109 + 0.004
	y = lerpf(y, y_sphere, 0.76)
	var jaw_taper := lerpf(0.66, 1.0, smoothstep(0.05, 0.54, v))
	var rx := 0.075 * ct * (jaw_taper if sa < 0.15 else lerpf(0.85, 1.0, smoothstep(0.08, 0.48, v)))
	var rzf := 0.084 * ct * lerpf(0.75, 1.0, smoothstep(0.04, 0.48, v))
	var rzb := 0.094 * ct * lerpf(0.72, 1.0, smoothstep(0.08, 0.45, v))
	var rz := rzf if sa < 0.0 else rzb

	var x := ca * rx
	var z := sa * rz + 0.004

	# Gentle sculpted 3D facial topography on front hemisphere (sa < 0)
	if sa < 0.0:
		var front := -sa
		var mid_x := absf(ca)

		# 1. Softly recessed eye sockets around v = 0.515, |ca| = 0.35
		var eye_dv := (v - 0.515) / 0.068
		var eye_dx := (mid_x - 0.35) / 0.18
		var orbit := exp(-(eye_dv * eye_dv + eye_dx * eye_dx)) * smoothstep(0.45, 0.85, front)
		z += 0.0062 * orbit

		# 2. Gentle brow ridge (v = 0.60)
		var brow_dv := (v - 0.60) / 0.048
		var brow := exp(-(brow_dv * brow_dv)) * smoothstep(0.55, 0.92, front) * (1.0 - smoothstep(0.52, 0.74, mid_x))
		z -= 0.0038 * brow

		# 3. Soft natural cheekbones (v = 0.42, |ca| = 0.50)
		var chk_dv := (v - 0.42) / 0.090
		var chk_dx := (mid_x - 0.50) / 0.24
		var cheek := exp(-(chk_dv * chk_dv + chk_dx * chk_dx)) * smoothstep(0.35, 0.82, front)
		z -= 0.0052 * cheek
		x += signf(ca) * 0.0032 * cheek

		# 4. Continuous smooth sculpted nose (bridge -> natural rounded tip -> gentle philtrum)
		var nose_w := exp(-pow(mid_x / 0.155, 2.0)) * smoothstep(0.76, 0.98, front)
		var nose_bridge := exp(-pow((v - 0.475) / 0.085, 2.0)) * 0.0135
		var nose_tip := exp(-pow((v - 0.395) / 0.044, 2.0)) * 0.0195
		var nose_under := exp(-pow((v - 0.340) / 0.025, 2.0)) * 0.0038
		z -= (nose_bridge + nose_tip - nose_under) * nose_w

		# 5. Soft natural lip fullness & chin contour (relaxed gentle contour, no harsh crease)
		var lip_w := exp(-pow(mid_x / 0.23, 2.0)) * smoothstep(0.74, 0.96, front)
		var u_lip := exp(-pow((v - 0.282) / 0.024, 2.0)) * 0.0048
		var m_line := exp(-pow((v - 0.260) / 0.012, 2.0)) * 0.0018
		var l_lip := exp(-pow((v - 0.236) / 0.025, 2.0)) * 0.0046
		var chin_dip := exp(-pow((v - 0.180) / 0.034, 2.0)) * 0.0028
		var chin_pt := exp(-pow((v - 0.100) / 0.058, 2.0)) * 0.0062 * exp(-pow(mid_x / 0.30, 2.0))
		z -= (u_lip - m_line + l_lip - chin_dip) * lip_w + chin_pt * smoothstep(0.65, 0.95, front)

	return Vector3(x, y, z)


static func get_head_mesh() -> ArrayMesh:
	if _cache.has("head"):
		return _cache["head"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var v_steps := 22
	var segs := 28
	var ring_pts: Array = []
	for vi in range(v_steps + 1):
		var v := float(vi) / float(v_steps)
		var pts: Array[Vector3] = []
		for si in range(segs):
			var a := float(si) * TAU / float(segs)
			pts.append(_eval_head_point(v, a))
		ring_pts.append(pts)
	_stitch_rings(st, ring_pts, segs, true)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["head"] = mesh
	return mesh


static func get_hair_mesh(style_idx: int) -> ArrayMesh:
	var key := "hair_%d" % (style_idx % 4)
	if _cache.has(key):
		return _cache[key]
	var style := style_idx % 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var v_steps := 16
	var segs := 28
	var ring_pts: Array = []

	for li in range(v_steps + 1):
		var t := float(li) / float(v_steps) # 0 = hairline/hem, 1 = top crown
		var pts: Array[Vector3] = []
		for si in range(segs):
			var a := float(si) * TAU / float(segs)
			var ca := cos(a)
			var sa := sin(a) # -1 = forehead (-Z), +1 = back (+Z)
			var backness := clampf((sa + 1.0) * 0.5, 0.0, 1.0)
			var sideness := absf(ca)

			var v_start := 0.70
			if style == 0: # Short tailored executive cut with soft side part
				v_start = lerpf(0.71, 0.23, pow(backness, 0.65)) - sideness * 0.065 + ca * 0.018 * (1.0 - backness)
			elif style == 1: # Fuller textured side-swept casual wave
				v_start = lerpf(0.64, 0.19, pow(backness, 0.65)) - sideness * 0.075 + sin(a * 2.0 + 0.6) * 0.015 * (1.0 - backness)
			elif style == 2: # Soft layered shoulder-length bob
				v_start = lerpf(0.68, 0.02, pow(clampf((sa + 0.45) / 1.45, 0.0, 1.0), 0.55))
			else: # Sleek pulled-back hair (paired with low bun)
				v_start = lerpf(0.73, 0.22, pow(backness, 0.72)) - sideness * 0.045

			v_start = clampf(v_start, 0.02, 0.85)
			var v_cur := lerpf(v_start, 0.995, t)
			var p_skull := _eval_head_point(v_cur, a)

			# Subtle sculpted hair strand undulation + natural layered crown volume (never spiky, never balding)
			var strand_wave := (sin(a * 7.0 + t * 2.5) * 0.0016 + cos(a * 11.0 - t * 1.8) * 0.0010) * sin(t * PI)
			var thick := 0.0125 + 0.0065 * sin(t * PI) + strand_wave
			if style == 1:
				thick += 0.0055 * smoothstep(0.18, 0.88, t)
			elif style == 2 and t < 0.48 and sa > -0.35:
				thick += 0.0085 * (1.0 - t / 0.48)

			var out_n := Vector3(p_skull.x, p_skull.y - 0.01, p_skull.z - 0.004)
			if out_n.length_squared() < 1e-5:
				out_n = Vector3.UP
			else:
				out_n = out_n.normalized()

			var p_hair := p_skull + out_n * thick
			if style == 2 and sa > -0.35 and t < 0.38:
				var drape := (1.0 - t / 0.38) * smoothstep(-0.35, 0.22, sa)
				p_hair.y -= drape * 0.062
				p_hair.x *= (1.0 + drape * 0.13)
				p_hair.z += drape * 0.014
			pts.append(p_hair)
		ring_pts.append(pts)

	_stitch_rings(st, ring_pts, segs, true)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func get_neck_mesh() -> ArrayMesh:
	if _cache.has("neck"):
		return _cache["neck"]
	var rings: Array = [
		[-0.055, 0.058, 0.056, 0.058, 0.002],
		[-0.015, 0.047, 0.048, 0.050, 0.001],
		[0.032,  0.045, 0.046, 0.048, 0.0],
		[0.068,  0.048, 0.050, 0.050, -0.002],
	]
	var mesh := _loft_asymmetric_rings(rings, 16, true)
	_cache["neck"] = mesh
	return mesh


static func _get_brow_arc_mesh(side: float) -> ArrayMesh:
	var key := "brow_arc_%s" % ("r" if side > 0.0 else "l")
	if _cache.has(key):
		return _cache[key]
	var pts: Array[Vector3] = []
	var rads: Array[float] = []
	for i in range(9):
		var u := float(i) / 8.0 # 0 = inner bridge -> 1 = outer temple
		var a := -PI * 0.5 + side * lerpf(0.16, 0.60, u)
		var v := 0.598 + sin(u * PI) * 0.022 - u * 0.010
		var p := _eval_head_point(v, a) + Vector3(0.0, 0.0, -0.0012)
		pts.append(p)
		rads.append(lerpf(0.0024, 0.0012, u) + sin(u * PI) * 0.0008)
	var mesh := _sweep_tube(pts, rads, 8, Vector3(0.0, 0.0, -1.0))
	_cache[key] = mesh
	return mesh


static func _get_eyelid_arc_mesh(side: float) -> ArrayMesh:
	var key := "eyelid_arc_%s" % ("r" if side > 0.0 else "l")
	if _cache.has(key):
		return _cache[key]
	var pts: Array[Vector3] = []
	var rads: Array[float] = []
	for i in range(9):
		var u := float(i) / 8.0
		var a := -PI * 0.5 + side * lerpf(0.19, 0.53, u)
		var v := 0.514 + sin(u * PI) * 0.028
		var p := _eval_head_point(v, a) + Vector3(0.0, 0.0, -0.0032)
		pts.append(p)
		rads.append(0.0011 + sin(u * PI) * 0.0007)
	var mesh := _sweep_tube(pts, rads, 8, Vector3(0.0, 0.0, -1.0))
	_cache[key] = mesh
	return mesh


static func _get_lip_mesh() -> ArrayMesh:
	if _cache.has("lip_arch"):
		return _cache["lip_arch"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	# Soft gently smiling upper + lower lip cushion derived directly from _eval_head_point (exact flush fit!)
	for is_lower: bool in [false, true]:
		var pts: Array[Vector3] = []
		var rads: Array[float] = []
		for i in range(11):
			var u := float(i) / 10.0 # 0..1 left corner -> right corner
			var s := (u - 0.5) * 2.0 # -1..1
			var a := -PI * 0.5 + s * 0.30
			var v_base := 0.244 if is_lower else 0.276
			var v := v_base + s * s * 0.012 + ((1.0 - absf(s)) * 0.006 if not is_lower else 0.0)
			var p := _eval_head_point(v, a) + Vector3(0.0, 0.0, -0.0012)
			pts.append(p)
			var t_mid := sin(u * PI)
			rads.append((0.0030 if is_lower else 0.0026) * (0.28 + 0.72 * t_mid))
		_append_tube(st, pts, rads, 8, Vector3(0.0, 0.0, -1.0))
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["lip_arch"] = mesh
	return mesh


static func _get_glasses_mesh() -> ArrayMesh:
	if _cache.has("glasses_wire"):
		return _cache["glasses_wire"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var r_wire := 0.00145
	# Rounded wire rims around both eyes
	for side: float in [-1.0, 1.0]:
		var rim_pts: Array[Vector3] = []
		var rim_r: Array[float] = []
		var cx := side * 0.028
		var cy := 0.014
		for i in range(17):
			var a := float(i) * TAU / 16.0
			var rx := 0.0165
			var ry := 0.0125
			# Soft super-ellipse lens frame
			var ca := cos(a)
			var sa := sin(a)
			var px := cx + signf(ca) * pow(absf(ca), 0.78) * rx
			var py := cy + signf(sa) * pow(absf(sa), 0.78) * ry
			var pz := -0.0885 + pow(absf(px) / 0.05, 1.6) * 0.006
			rim_pts.append(Vector3(px, py, pz))
			rim_r.append(r_wire)
		_append_tube(st, rim_pts, rim_r, 6, Vector3(0.0, 0.0, -1.0))
		# Slim temple arms curving gently back over the ears
		var arm_pts: Array[Vector3] = [
			Vector3(side * 0.0445, 0.016, -0.083),
			Vector3(side * 0.068, 0.016, -0.055),
			Vector3(side * 0.075, 0.015, -0.005),
			Vector3(side * 0.075, 0.007, 0.018),
		]
		var arm_r: Array[float] = [r_wire, r_wire, r_wire, r_wire * 0.9]
		_append_tube(st, arm_pts, arm_r, 6, Vector3.UP)
	# Delicate curved nose bridge
	var br_pts: Array[Vector3] = [
		Vector3(-0.0115, 0.016, -0.088),
		Vector3(0.0, 0.0185, -0.0905),
		Vector3(0.0115, 0.016, -0.088),
	]
	_append_tube(st, br_pts, [r_wire, r_wire, r_wire], 6, Vector3.UP)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["glasses_wire"] = mesh
	return mesh


static func build_detailed_head(
	parent: Node3D,
	skin_mat: Material,
	hair_mat: Material,
	hair_style: int,
	skin_col: Color,
	hair_col: Color,
	add_glasses: bool = false
) -> Node3D:
	var head := Node3D.new()
	parent.add_child(head)

	# 1. Smooth sculpted anatomical head + layered full-coverage hair
	_add_part(head, get_head_mesh(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, skin_mat)
	_add_part(head, get_hair_mesh(hair_style), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, hair_mat)
	if hair_style % 4 == 3:
		_add_part(head, _get_unit_sphere(), Vector3(0.0, -0.012, 0.118), Vector3.ZERO, Vector3(0.042, 0.039, 0.039), hair_mat)

	# 2. Natural sculpted ears
	var sph := _get_unit_sphere()
	for side: float in [-1.0, 1.0]:
		_add_part(head, sph, Vector3(side * 0.072, -0.003, 0.006), Vector3(0.0, side * 14.0, -side * 6.0), Vector3(0.0125, 0.027, 0.017), skin_mat)

	# 3. Warm, soft, natural facial features (non-uncanny: curved brows, soft almond eyes with lively catchlight, gentle lips)
	var brow_mat := _cached_simple_mat("brow2_%02x%02x" % [int(hair_col.r * 255), int(hair_col.g * 255)], hair_col.lerp(skin_col.darkened(0.32), 0.36), 0.85)
	var lid_mat := _cached_simple_mat("lid2_%02x%02x" % [int(skin_col.r * 255), int(skin_col.g * 255)], skin_col.darkened(0.24), 0.70)
	var eye_mat := _cached_simple_mat("eye_iris2", Color(0.20, 0.14, 0.10), 0.14)
	var sclera_mat := _cached_simple_mat("eye_sclera2", Color(0.91, 0.89, 0.87), 0.32)
	var catch_mat := _cached_simple_mat("eye_catch", Color(0.98, 0.98, 1.0), 0.08)
	var lip_mat := _cached_simple_mat("lip2_%02x" % int(skin_col.r * 255), skin_col.lerp(Color(0.68, 0.39, 0.38), 0.32), 0.56)

	for side: float in [-1.0, 1.0]:
		_add_part(head, _get_brow_arc_mesh(side), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, brow_mat)
		_add_part(head, _get_eyelid_arc_mesh(side), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, lid_mat)
		# Softly seated almond sclera + warm brown iris + subtle specular catchlight seated flush in orbital socket
		var p_eye := _eval_head_point(0.515, -PI * 0.5 + side * 0.36)
		_add_part(head, sph, p_eye + Vector3(0.0, 0.0, 0.0018), Vector3(0.0, -side * 16.0, 0.0), Vector3(0.0135, 0.0076, 0.0058), sclera_mat)
		_add_part(head, sph, p_eye + Vector3(0.0, 0.0, -0.0034), Vector3.ZERO, Vector3(0.0064, 0.0066, 0.0024), eye_mat)
		_add_part(head, sph, p_eye + Vector3(-0.0020, 0.0018, -0.0054), Vector3.ZERO, Vector3(0.0015, 0.0015, 0.0010), catch_mat)

	# Gentle softly curved lips seated flush on the sculpted head surface (nose is already sculpted into head mesh!)
	_add_part(head, _get_lip_mesh(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, lip_mat)

	# Slim refined eyeglasses
	if add_glasses:
		var frame_mat := _cached_metallic_mat("glasses_wire_mat", Color(0.18, 0.19, 0.21), 0.28, 0.65)
		_add_part(head, _get_glasses_mesh(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, frame_mat)

	return head


# ---------------------------------------------------------------------------------------------
# 2. Smooth Anatomically-Proportioned Torso, Limbs, Skirt & Hands
# ---------------------------------------------------------------------------------------------

static func _torso_rings_for_arch(archetype: int) -> Array:
	match archetype % 4:
		0: # Tailored business coat / blazer (smooth sloping shoulders & refined waist)
			return [
				[-0.31, 0.164, 0.106, 0.108, 0.002],
				[-0.19, 0.154, 0.100, 0.102, 0.002],
				[-0.06, 0.146, 0.097, 0.096, 0.0],
				[0.06,  0.168, 0.112, 0.104, -0.004],
				[0.16,  0.192, 0.110, 0.102, -0.004],
				[0.215, 0.184, 0.096, 0.094, -0.002],
				[0.252, 0.132, 0.078, 0.080, 0.0],
				[0.278, 0.066, 0.062, 0.064, 0.0],
			]
		1: # Casual modern jacket / parka (soft rounded shoulders, natural drape)
			return [
				[-0.27, 0.156, 0.105, 0.108, 0.002],
				[-0.14, 0.162, 0.112, 0.112, 0.0],
				[0.02,  0.172, 0.116, 0.110, -0.004],
				[0.15,  0.190, 0.110, 0.104, -0.004],
				[0.210, 0.180, 0.096, 0.094, -0.002],
				[0.250, 0.130, 0.078, 0.080, 0.0],
				[0.278, 0.068, 0.064, 0.066, 0.0],
			]
		2: # Tailored long coat / trench (graceful waist & smooth shoulder line)
			return [
				[-0.44, 0.196, 0.130, 0.136, 0.004],
				[-0.26, 0.164, 0.108, 0.112, 0.002],
				[-0.08, 0.134, 0.092, 0.093, 0.0],
				[0.06,  0.156, 0.108, 0.098, -0.005],
				[0.16,  0.174, 0.102, 0.095, -0.004],
				[0.212, 0.164, 0.090, 0.088, -0.002],
				[0.250, 0.118, 0.074, 0.075, 0.0],
				[0.278, 0.062, 0.058, 0.060, 0.0],
			]
		_: # Smart casual sweater / overshirt
			return [
				[-0.27, 0.154, 0.100, 0.103, 0.002],
				[-0.12, 0.148, 0.097, 0.097, 0.0],
				[0.04,  0.164, 0.110, 0.102, -0.004],
				[0.155, 0.182, 0.104, 0.098, -0.004],
				[0.210, 0.172, 0.092, 0.090, -0.002],
				[0.248, 0.124, 0.075, 0.076, 0.0],
				[0.278, 0.064, 0.060, 0.062, 0.0],
			]


# Evaluates exact torso cross-section [rx, rzf, rzb, zsh] at height y so zippers, collars & straps fit flush!
static func _eval_torso_ring(archetype: int, y: float) -> Array[float]:
	var rings := _torso_rings_for_arch(archetype)
	if y <= float(rings[0][0]):
		return [float(rings[0][1]), float(rings[0][2]), float(rings[0][3]), float(rings[0][4])]
	var last := rings.size() - 1
	if y >= float(rings[last][0]):
		return [float(rings[last][1]), float(rings[last][2]), float(rings[last][3]), float(rings[last][4])]
	for i in range(last):
		var y0 := float(rings[i][0])
		var y1 := float(rings[i + 1][0])
		if y >= y0 and y <= y1:
			var t := (y - y0) / maxf(y1 - y0, 1e-4)
			return [
				lerpf(float(rings[i][1]), float(rings[i + 1][1]), t),
				lerpf(float(rings[i][2]), float(rings[i + 1][2]), t),
				lerpf(float(rings[i][3]), float(rings[i + 1][3]), t),
				lerpf(float(rings[i][4]), float(rings[i + 1][4]), t),
			]
	return [0.16, 0.10, 0.10, 0.0]


# Point on the exact torso surface at height y, angle a (a=-PI/2 front, +PI/2 back), pushed outward by `pad`
static func _eval_torso_surface(archetype: int, y: float, a: float, pad: float = 0.0) -> Vector3:
	var r := _eval_torso_ring(archetype, y)
	var ca := cos(a)
	var sa := sin(a)
	var rx := r[0] + pad
	var rz := (r[1] if sa < 0.0 else r[2]) + pad
	return Vector3(ca * rx, y, sa * rz + r[3])


static func get_torso_mesh(archetype: int) -> ArrayMesh:
	var key := "torso_%d" % (archetype % 4)
	if _cache.has(key):
		return _cache[key]
	var mesh := _loft_asymmetric_rings(_torso_rings_for_arch(archetype), 22, true)
	_cache[key] = mesh
	return mesh


static func get_skirt_mesh(is_long: bool = false) -> ArrayMesh:
	var key := "skirt_long" if is_long else "skirt_knee"
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rings: Array = [
		[-0.62, 0.245, 0.195, 0.200, 0.0],
		[-0.44, 0.224, 0.176, 0.182, 0.0],
		[-0.24, 0.202, 0.156, 0.162, 0.0],
		[-0.08, 0.180, 0.132, 0.138, 0.0],
		[0.04,  0.156, 0.110, 0.112, 0.0],
	] if is_long else [
		[-0.42, 0.228, 0.178, 0.184, 0.0],
		[-0.26, 0.208, 0.160, 0.165, 0.0],
		[-0.12, 0.186, 0.138, 0.144, 0.0],
		[0.04,  0.156, 0.110, 0.112, 0.0],
	]
	var segs := 24
	var ring_pts: Array = []
	for ri in range(rings.size()):
		var r: Array = rings[ri]
		var y := float(r[0])
		var rx := float(r[1])
		var rzf := float(r[2])
		var rzb := float(r[3])
		var zsh := float(r[4])
		# Gentle fabric drape ripple near hem for realistic cloth feel
		var drape_amp := (1.0 - float(ri) / float(rings.size() - 1)) * 0.0085
		var pts: Array[Vector3] = []
		for i in range(segs):
			var a := float(i) * TAU / float(segs)
			var ripple := 1.0 + drape_amp * sin(a * 6.0) / maxf(rx, 0.1)
			var rz := (rzf if sin(a) < 0.0 else rzb) * ripple
			pts.append(Vector3(cos(a) * rx * ripple, y, sin(a) * rz + zsh))
		ring_pts.append(pts)
	_stitch_rings(st, ring_pts, segs, true)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func get_thigh_mesh() -> ArrayMesh:
	if _cache.has("thigh"):
		return _cache["thigh"]
	var rings: Array = [
		[-0.21, 0.050, 0.054, 0.053, 0.0],
		[-0.08, 0.062, 0.066, 0.066, 0.0],
		[0.08,  0.072, 0.076, 0.078, 0.0],
		[0.21,  0.074, 0.075, 0.078, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 14, true)
	_cache["thigh"] = mesh
	return mesh


static func get_shin_mesh() -> ArrayMesh:
	if _cache.has("shin"):
		return _cache["shin"]
	var rings: Array = [
		[-0.20, 0.035, 0.039, 0.037, 0.0],
		[-0.06, 0.046, 0.048, 0.055, 0.004],
		[0.08,  0.051, 0.053, 0.057, 0.002],
		[0.20,  0.049, 0.051, 0.049, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 14, true)
	_cache["shin"] = mesh
	return mesh


static func get_upper_arm_mesh() -> ArrayMesh:
	if _cache.has("upper_arm"):
		return _cache["upper_arm"]
	# Rounded deltoid shoulder cap at top blends organically into the sloping torso shoulder!
	var rings: Array = [
		[-0.145, 0.038, 0.040, 0.040, 0.0],
		[-0.02,  0.045, 0.047, 0.047, 0.0],
		[0.09,   0.052, 0.055, 0.054, 0.0],
		[0.145,  0.050, 0.053, 0.052, 0.0],
		[0.175,  0.034, 0.038, 0.038, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 14, true)
	_cache["upper_arm"] = mesh
	return mesh


static func get_forearm_mesh() -> ArrayMesh:
	if _cache.has("forearm"):
		return _cache["forearm"]
	var rings: Array = [
		[-0.135, 0.027, 0.029, 0.029, 0.0],
		[-0.04,  0.035, 0.037, 0.037, 0.0],
		[0.07,   0.040, 0.042, 0.042, 0.0],
		[0.135,  0.039, 0.041, 0.041, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 14, true)
	_cache["forearm"] = mesh
	return mesh


static func get_hand_mesh() -> ArrayMesh:
	if _cache.has("hand"):
		return _cache["hand"]
	var rings: Array = [
		[-0.050, 0.014, 0.024, 0.020, -0.002],
		[-0.022, 0.020, 0.034, 0.028, -0.002],
		[0.012,  0.021, 0.034, 0.030, 0.0],
		[0.036,  0.022, 0.026, 0.026, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 12, true)
	_cache["hand"] = mesh
	return mesh


static func get_shoe_mesh() -> ArrayMesh:
	if _cache.has("shoe"):
		return _cache["shoe"]
	var rings: Array = [
		[0.0,   0.041, 0.142, 0.082, 0.0],
		[0.024, 0.043, 0.140, 0.082, 0.0],
		[0.048, 0.038, 0.104, 0.076, 0.005],
		[0.072, 0.034, 0.056, 0.062, 0.012],
		[0.088, 0.032, 0.042, 0.048, 0.014],
	]
	var mesh := _loft_asymmetric_rings(rings, 14, true)
	_cache["shoe"] = mesh
	return mesh


# ---------------------------------------------------------------------------------------------
# 3. Surface-Conforming Tailored Garment Details (Collar, V-Neck, Fine Zipper, Belt, Pockets)
# ---------------------------------------------------------------------------------------------

# Sculpted folded jacket collar hugging the neck opening cleanly with an open front V
static func get_collar_mesh(archetype: int) -> ArrayMesh:
	var key := "collar_%d" % (archetype % 4)
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var pts: Array[Vector3] = []
	var rads: Array[float] = []
	var steps := 18
	# Sweep from front-left V-notch around the back of the neck to front-right V-notch
	for i in range(steps + 1):
		var u := float(i) / float(steps)
		var a := lerpf(-PI * 0.38, PI * 1.38, u) # avoids center front (-PI/2) to form neat V-neck!
		var is_front := clampf((-sin(a) - 0.1) / 0.9, 0.0, 1.0)
		var y := lerpf(0.278, 0.236, is_front)
		var p := _eval_torso_surface(archetype, y, a, 0.008)
		pts.append(p)
		rads.append(lerpf(0.016, 0.011, is_front))
	_append_tube(st, pts, rads, 10, Vector3.UP)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# Contoured inner shirt V-neck panel sitting cleanly flush inside the jacket collar opening
static func get_shirt_vneck_mesh(archetype: int) -> ArrayMesh:
	var key := "vneck_%d" % (archetype % 4)
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rows := 6
	var cols := 7
	var grid: Array = []
	for ri in range(rows + 1):
		var v := float(ri) / float(rows) # 0 = V bottom (y=0.145) -> 1 = neck top (y=0.276)
		var y := lerpf(0.145, 0.276, v)
		var half_span := lerpf(0.06, 0.50, v) # angular half-width around front (-PI/2)
		var row: Array[Vector3] = []
		for ci in range(cols + 1):
			var u := float(ci) / float(cols) * 2.0 - 1.0
			var a := -PI * 0.5 + u * half_span
			row.append(_eval_torso_surface(archetype, y, a, 0.0032))
		grid.append(row)
	_stitch_grid(st, grid, rows, cols)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# Wafer-thin surface-conforming center front metallic zipper track + pull slider (NEVER floats or clips!)
static func get_zipper_mesh(archetype: int) -> ArrayMesh:
	var key := "zipper_%d" % (archetype % 4)
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var y_bot := -0.25 if archetype % 4 != 2 else -0.34
	var y_top := 0.165
	var rows := 10
	var cols := 3
	var grid: Array = []
	for ri in range(rows + 1):
		var y := lerpf(y_bot, y_top, float(ri) / float(rows))
		var row: Array[Vector3] = []
		for ci in range(cols + 1):
			var u := float(ci) / float(cols) * 2.0 - 1.0 # -1..1
			var a := -PI * 0.5 + u * 0.022 # ~4mm crisp zipper track width
			var relief := 0.0028 if absf(u) < 0.5 else 0.0012
			row.append(_eval_torso_surface(archetype, y, a, relief))
		grid.append(row)
	_stitch_grid(st, grid, rows, cols)
	# Tiny sculpted metallic zipper slider + pull tab at top of zipper
	var p_top := _eval_torso_surface(archetype, y_top - 0.006, -PI * 0.5, 0.0045)
	var slider_pts: Array[Vector3] = [
		p_top + Vector3(0.0, 0.005, 0.0),
		p_top + Vector3(0.0, -0.011, -0.0015),
	]
	_append_tube(st, slider_pts, [0.0032, 0.0022], 6, Vector3(0.0, 0.0, -1.0))
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# Contoured oval waist belt hugging the exact torso waist ring + slim buckle
static func get_belt_mesh(archetype: int) -> ArrayMesh:
	var key := "belt_%d" % (archetype % 4)
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var segs := 22
	var y_lo := -0.232
	var y_hi := -0.200
	var ring_pts: Array = []
	for y_cur: float in [y_lo, (y_lo + y_hi) * 0.5, y_hi]:
		var pad := 0.0055 if absf(y_cur - (y_lo + y_hi) * 0.5) < 0.005 else 0.0032
		var pts: Array[Vector3] = []
		for i in range(segs):
			var a := float(i) * TAU / float(segs)
			pts.append(_eval_torso_surface(archetype, y_cur, a, pad))
		ring_pts.append(pts)
	_stitch_rings(st, ring_pts, segs, false)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# ---------------------------------------------------------------------------------------------
# 4. High-Precision Sculpted Commuter Gear: Backpacks, Crossbody Bags, Headphones, Scarves, Hats
# ---------------------------------------------------------------------------------------------

# Modern sculpted urban commuter daypack (rounded clamshell, concave back fit, front pocket, side bottle pockets)
static func get_backpack_body_mesh() -> ArrayMesh:
	if _cache.has("bp_body"):
		return _cache["bp_body"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)

	# Main sculpted clamshell body centered around (0, 0.01, 0.165), tapering smoothly toward top
	var v_steps := 14
	var segs := 22
	var main_rings: Array = []
	for vi in range(v_steps + 1):
		var t := float(vi) / float(v_steps) # 0 = bottom -> 1 = rounded top
		var y := lerpf(-0.175, 0.215, t)
		var cap := sin(clampf(t, 0.015, 0.985) * PI)
		var dome := pow(cap, 0.34) # crisp rounded top & bottom edges
		var top_taper := lerpf(1.04, 0.80, smoothstep(0.35, 1.0, t))
		var rx := 0.138 * dome * top_taper
		var rz_back := 0.032 * dome # gentle flush back panel hugging spine
		var rz_out := 0.088 * dome * lerpf(1.06, 0.78, smoothstep(0.25, 1.0, t))
		var pts: Array[Vector3] = []
		for si in range(segs):
			var a := float(si) * TAU / float(segs)
			var ca := cos(a)
			var sa := sin(a) # -1 = toward person's back (-Z), +1 = outward (+Z)
			# Soft super-ellipse rectangular pack cross-section
			var sx := signf(ca) * pow(absf(ca), 0.72) * rx
			var sz := signf(sa) * pow(absf(sa), 0.78) * (rz_back if sa < 0.0 else rz_out)
			pts.append(Vector3(sx, y, 0.135 + sz))
		main_rings.append(pts)
	_stitch_rings(st, main_rings, segs, true)

	# Contoured rounded front organizer pocket on lower half of backpack
	var p_rings: Array = []
	for vi in range(9):
		var t := float(vi) / 8.0
		var y := lerpf(-0.155, 0.025, t)
		var dome := pow(sin(clampf(t, 0.02, 0.98) * PI), 0.38)
		var rx := 0.106 * dome * lerpf(1.0, 0.90, t)
		var rz := 0.032 * dome
		var pts: Array[Vector3] = []
		for si in range(16):
			var a := float(si) * TAU / 16.0
			var ca := cos(a)
			var sa := sin(a)
			var sx := signf(ca) * pow(absf(ca), 0.72) * rx
			var sz := (0.008 * sa if sa < 0.0 else rz * pow(sa, 0.75))
			pts.append(Vector3(sx, y, 0.212 + sz))
		p_rings.append(pts)
	_stitch_rings(st, p_rings, 16, true)

	# Side water-bottle pockets on both flanks
	for side: float in [-1.0, 1.0]:
		var s_rings: Array = []
		for vi in range(7):
			var t := float(vi) / 6.0
			var y := lerpf(-0.155, -0.025, t)
			var dome := pow(sin(clampf(t, 0.03, 0.97) * PI), 0.35)
			var pts: Array[Vector3] = []
			for si in range(12):
				var a := float(si) * TAU / 12.0
				pts.append(Vector3(side * (0.130 + cos(a) * 0.020 * dome), y, 0.158 + sin(a) * 0.032 * dome))
			s_rings.append(pts)
		_stitch_rings(st, s_rings, 12, true)

	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["bp_body"] = mesh
	return mesh


# Backpack metallic zipper tracks + curved top haul handle loop
static func get_backpack_trim_mesh() -> ArrayMesh:
	if _cache.has("bp_trim"):
		return _cache["bp_trim"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	# Top grab handle arch
	var h_pts: Array[Vector3] = []
	var h_r: Array[float] = []
	for i in range(11):
		var u := float(i) / 10.0
		var x := lerpf(-0.044, 0.044, u)
		var y := 0.205 + sin(u * PI) * 0.034
		var z := 0.132 + sin(u * PI) * 0.008
		h_pts.append(Vector3(x, y, z))
		h_r.append(0.0055)
	_append_tube(st, h_pts, h_r, 8, Vector3(0.0, 0.0, 1.0))

	# Curved front pocket zipper seam
	var z_pts: Array[Vector3] = []
	var z_r: Array[float] = []
	for i in range(11):
		var u := float(i) / 10.0
		var s := (u - 0.5) * 2.0
		var x := s * 0.095
		var y := 0.004 - s * s * 0.016
		var z := 0.238 - s * s * 0.018
		z_pts.append(Vector3(x, y, z))
		z_r.append(0.0028)
	_append_tube(st, z_pts, z_r, 6, Vector3(0.0, 0.0, 1.0))

	# Upper main compartment horseshoe zipper seam
	var m_pts: Array[Vector3] = []
	var m_r: Array[float] = []
	for i in range(15):
		var u := float(i) / 14.0
		var ang := lerpf(-PI * 0.45, PI * 0.45, u)
		var x := sin(ang) * 0.118
		var y := 0.08 + cos(ang) * 0.115
		var z := 0.185 + cos(ang) * 0.022
		m_pts.append(Vector3(x, y, z))
		m_r.append(0.0026)
	_append_tube(st, m_pts, m_r, 6, Vector3(0.0, 0.0, 1.0))

	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["bp_trim"] = mesh
	return mesh


# Ergonomic S-curved padded backpack shoulder straps hugging the exact torso contour (ZERO floating sticks!)
static func get_backpack_straps_mesh(archetype: int) -> ArrayMesh:
	var key := "bp_straps_%d" % (archetype % 4)
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for side: float in [-1.0, 1.0]:
		var pts: Array[Vector3] = []
		var rads: Array[float] = []
		# Anchor inside upper backpack -> over shoulder top -> down chest -> around lower ribcage -> lower pack corner
		var specs: Array = [
			[0.185, PI * 0.5 - side * 0.36, 0.024, 0.014],  # top back anchor into pack
			[0.242, PI * 0.5 - side * 0.60, 0.014, 0.015],  # rear trapezius rise
			[0.258, -side * 0.05 if side > 0.0 else PI + 0.05, 0.013, 0.016], # shoulder crest
			[0.212, -PI * 0.5 + side * 0.60, 0.013, 0.016], # front clavicle
			[0.100, -PI * 0.5 + side * 0.52, 0.013, 0.015], # upper chest
			[-0.04, -PI * 0.5 + side * 0.66, 0.012, 0.013], # lower chest curving under arm
			[-0.14, 0.0 if side > 0.0 else PI, 0.012, 0.011], # side waist wrap
			[-0.155, PI * 0.5 - side * 0.55, 0.022, 0.011], # lower back anchor into pack
		]
		for sp: Array in specs:
			var p := _eval_torso_surface(archetype, float(sp[0]), float(sp[1]), float(sp[2]))
			pts.append(p)
			rads.append(float(sp[3]))
		_append_ribbon_strap(st, pts, rads, 0.0045)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# Softly bevelled leather/canvas commuter messenger bag with folded flap
static func get_messenger_bag_mesh() -> ArrayMesh:
	if _cache.has("msg_bag"):
		return _cache["msg_bag"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rings: Array = []
	for vi in range(11):
		var t := float(vi) / 10.0
		var y := lerpf(-0.115, 0.115, t)
		var dome := pow(sin(clampf(t, 0.02, 0.98) * PI), 0.32)
		var rx := 0.036 * dome * lerpf(1.08, 0.85, t) # slim profile against hip
		var rz := 0.145 * dome * lerpf(1.02, 0.96, t)
		var pts: Array[Vector3] = []
		for si in range(18):
			var a := float(si) * TAU / 18.0
			var ca := cos(a)
			var sa := sin(a)
			pts.append(Vector3(signf(ca) * pow(absf(ca), 0.68) * rx, y, signf(sa) * pow(absf(sa), 0.68) * rz))
		rings.append(pts)
	_stitch_rings(st, rings, 18, true)
	# Slightly thicker top fold-over flap
	var f_rings: Array = []
	for vi in range(7):
		var t := float(vi) / 6.0
		var y := lerpf(-0.025, 0.118, t)
		var dome := pow(sin(clampf(t, 0.03, 0.97) * PI), 0.35)
		var rx := 0.041 * dome
		var rz := 0.148 * dome
		var pts: Array[Vector3] = []
		for si in range(16):
			var a := float(si) * TAU / 16.0
			var ca := cos(a)
			var sa := sin(a)
			pts.append(Vector3(signf(ca) * pow(absf(ca), 0.68) * rx, y, signf(sa) * pow(absf(sa), 0.68) * rz))
		f_rings.append(pts)
	_stitch_rings(st, f_rings, 16, true)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["msg_bag"] = mesh
	return mesh


# Body-hugging curved crossbody strap swept cleanly over opposite shoulder, across chest & back to hip bag!
static func get_crossbody_strap_mesh(archetype: int, hip_side: float) -> ArrayMesh:
	var key := "xstrap_%d_%s" % [archetype % 4, "r" if hip_side > 0.0 else "l"]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var opp := -hip_side # shoulder opposite to the hip bag
	var pts: Array[Vector3] = []
	var widths: Array[float] = []
	# Continuous loop: hip bag -> front diagonal across chest -> over opposite shoulder -> back diagonal -> hip bag
	var front_steps := 12
	for i in range(front_steps + 1):
		var u := float(i) / float(front_steps)
		var y := lerpf(-0.20, 0.248, u)
		var a := 0.0
		if hip_side < 0.0:
			# On left hip (a=-PI), sweep smoothly to -PI/2 + 0.55 (right shoulder)
			a = lerpf(-PI, -PI * 0.5 + 0.55, u)
		else:
			# On right hip (a=0), sweep smoothly through -PI/2 to -PI/2 - 0.55 (left shoulder)
			a = lerpf(0.0, -PI * 0.5 - 0.55, u)
		var p := _eval_torso_surface(archetype, y, a, 0.0085)
		pts.append(p)
		widths.append(0.012)
	# Smooth arch point over the top crest of the opposite shoulder so strap never cuts through neck/trapezius!
	var a_crest := PI if hip_side > 0.0 else 0.0
	pts.append(_eval_torso_surface(archetype, 0.258, a_crest, 0.012))
	widths.append(0.012)
	# Over top of opposite shoulder -> down back to hip bag
	for i in range(1, front_steps + 1):
		var u := float(i) / float(front_steps)
		var y := lerpf(0.248, -0.20, u)
		var a := 0.0
		if hip_side > 0.0:
			# Left shoulder (+PI/2 + 0.55) -> back (+PI/2) -> right hip (0.0)
			a = lerpf(PI * 0.5 + 0.55, 0.0, u)
		else:
			# Right shoulder (+PI/2 - 0.55) -> back (+PI/2) -> left hip (+PI)
			a = lerpf(PI * 0.5 - 0.55, PI, u)
		var p := _eval_torso_surface(archetype, y, a, 0.0085)
		pts.append(p)
		widths.append(0.012)
	_append_ribbon_strap(st, pts, widths, 0.0038)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# Smooth curved horseshoe over-ear headphones (NO square corners / cat ears!)
static func get_headphones_mesh() -> ArrayMesh:
	if _cache.has("headphones"):
		return _cache["headphones"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	# Smooth curved headband arc hugging cleanly above the hair crown
	var band_pts: Array[Vector3] = []
	var band_r: Array[float] = []
	for i in range(19):
		var u := float(i) / 18.0
		var ang := lerpf(-PI * 0.54, PI * 0.54, u) # left ear -> crown -> right ear
		var x := sin(ang) * 0.095
		var y := 0.008 + cos(ang) * 0.116
		var z := 0.006 - cos(ang) * 0.004
		band_pts.append(Vector3(x, y, z))
		band_r.append(lerpf(0.0065, 0.0105, sin(u * PI)))
	_append_tube(st, band_pts, band_r, 10, Vector3(0.0, 0.0, -1.0))

	# Sculpted oval cushioned earcups sitting cleanly over both ears
	for side: float in [-1.0, 1.0]:
		var cup_rings: Array = []
		for vi in range(7):
			var t := float(vi) / 6.0
			var x_off := lerpf(0.076, 0.104, t)
			var dome := sin(clampf(t, 0.04, 0.96) * PI)
			var ry := 0.036 * pow(dome, 0.42)
			var rz := 0.030 * pow(dome, 0.42)
			var pts: Array[Vector3] = []
			for si in range(14):
				var a := float(si) * TAU / 14.0
				pts.append(Vector3(side * x_off, -0.002 + cos(a) * ry, 0.006 + sin(a) * rz))
			cup_rings.append(pts)
		_stitch_rings(st, cup_rings, 14, true)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["headphones"] = mesh
	return mesh


# Draped knit scarf ring hugging the neck + naturally curved front scarf tail conforming to chest
static func get_scarf_mesh(archetype: int) -> ArrayMesh:
	var key := "scarf_%d" % (archetype % 4)
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	# Soft plump wrap around neck
	var ring_p: Array[Vector3] = []
	var ring_r: Array[float] = []
	for i in range(21):
		var a := float(i) * TAU / 20.0
		var y := 0.278 - maxf(0.0, -sin(a)) * 0.022
		var p := _eval_torso_surface(archetype, y, a, 0.016)
		ring_p.append(p)
		ring_r.append(0.022 + sin(a * 3.0) * 0.0025)
	_append_tube(st, ring_p, ring_r, 10, Vector3.UP)
	# Draped front scarf tail hugging the chest surface cleanly
	var tail_p: Array[Vector3] = []
	var tail_w: Array[float] = []
	for i in range(8):
		var u := float(i) / 7.0
		var y := lerpf(0.255, 0.02, u)
		var a := -PI * 0.5 + lerpf(0.22, 0.34, u)
		tail_p.append(_eval_torso_surface(archetype, y, a, 0.015))
		tail_w.append(lerpf(0.026, 0.032, u))
	_append_ribbon_strap(st, tail_p, tail_w, 0.009)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# Smooth contoured baseball cap derived directly from the head dome + curved visor brim
static func get_cap_mesh() -> ArrayMesh:
	if _cache.has("cap"):
		return _cache["cap"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var v_steps := 8
	var segs := 22
	var crown_rings: Array = []
	for li in range(v_steps + 1):
		var t := float(li) / float(v_steps)
		var pts: Array[Vector3] = []
		for si in range(segs):
			var a := float(si) * TAU / float(segs)
			var sa := sin(a)
			var v_start := lerpf(0.66, 0.56, clampf((sa + 1.0) * 0.5, 0.0, 1.0))
			var v_cur := lerpf(v_start, 0.995, t)
			var p := _eval_head_point(v_cur, a)
			var out_n := Vector3(p.x, p.y - 0.008, p.z - 0.004).normalized()
			pts.append(p + out_n * (0.021 + 0.004 * sin(t * PI)))
		crown_rings.append(pts)
	_stitch_rings(st, crown_rings, segs, true)
	# Curved visor bill projecting cleanly forward above the brow
	var rows := 4
	var cols := 10
	var brim_top: Array = []
	for ri in range(rows + 1):
		var u_len := float(ri) / float(rows) # 0 = forehead band -> 1 = visor tip
		var row: Array[Vector3] = []
		for ci in range(cols + 1):
			var s := float(ci) / float(cols) * 2.0 - 1.0 # -1..1
			var a := -PI * 0.5 + s * 0.85
			var hp := _eval_head_point(0.65, a)
			var reach := u_len * 0.072 * cos(s * 0.95)
			var droop := -u_len * 0.010 - s * s * 0.008 * u_len
			row.append(Vector3(hp.x * 1.18, hp.y + 0.012 + droop, hp.z - 0.018 - reach))
		brim_top.append(row)
	# Top of visor faces +Y (reverse row order so CW winding faces upward)
	var brim_top_rev := brim_top.duplicate()
	brim_top_rev.reverse()
	_stitch_grid(st, brim_top_rev, rows, cols)
	# Underside of brim faces -Y
	var brim_bot: Array = []
	for row_b: Array in brim_top:
		var shifted: Array[Vector3] = []
		for vp: Vector3 in row_b:
			shifted.append(vp + Vector3(0.0, -0.0045, 0.0))
		brim_bot.append(shifted)
	_stitch_grid(st, brim_bot, rows, cols)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["cap"] = mesh
	return mesh


# Contoured cozy knit beanie derived from the head surface with folded rib cuff
static func get_beanie_mesh() -> ArrayMesh:
	if _cache.has("beanie"):
		return _cache["beanie"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var v_steps := 10
	var segs := 22
	var rings: Array = []
	for li in range(v_steps + 1):
		var t := float(li) / float(v_steps)
		var pts: Array[Vector3] = []
		for si in range(segs):
			var a := float(si) * TAU / float(segs)
			var sa := sin(a)
			var v_start := lerpf(0.64, 0.44, clampf((sa + 1.0) * 0.5, 0.0, 1.0))
			var v_cur := lerpf(v_start, 0.995, t)
			var p := _eval_head_point(v_cur, a)
			var out_n := Vector3(p.x, p.y - 0.008, p.z - 0.004).normalized()
			var cuff := 0.006 if t < 0.25 else 0.0
			var crown_lift := Vector3(0.0, 0.022 * pow(t, 1.5), 0.014 * pow(t, 1.6))
			pts.append(p + out_n * (0.021 + cuff) + crown_lift)
		rings.append(pts)
	_stitch_rings(st, rings, segs, true)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache["beanie"] = mesh
	return mesh


# ---------------------------------------------------------------------------------------------
# 5. Low-Level Smooth Mesh & Material Helpers
# ---------------------------------------------------------------------------------------------

static func _get_unit_sphere() -> SphereMesh:
	if not _cache.has("u_sph"):
		var s := SphereMesh.new()
		s.radius = 1.0; s.height = 2.0; s.radial_segments = 12; s.rings = 8
		_cache["u_sph"] = s
	return _cache["u_sph"]


static func _get_unit_box() -> BoxMesh:
	if not _cache.has("u_box"):
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		_cache["u_box"] = b
	return _cache["u_box"]


static func _cached_simple_mat(key: String, col: Color, rough: float) -> StandardMaterial3D:
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		_cache[key] = m
	return _cache[key]


static func _cached_metallic_mat(key: String, col: Color, rough: float, metal: float) -> StandardMaterial3D:
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		_cache[key] = m
	return _cache[key]


static func _add_part(parent: Node3D, m: Mesh, pos: Vector3, rot_deg: Vector3, sc: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = sc
	mi.visibility_range_end = 140.0 if sc.x >= 0.5 else 85.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _loft_asymmetric_rings(rings: Array, segs: int, cap_ends: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var ring_pts: Array = []
	for r: Array in rings:
		var y := float(r[0])
		var rx := float(r[1])
		var rzf := float(r[2])
		var rzb := float(r[3])
		var zsh := float(r[4])
		var pts: Array[Vector3] = []
		for i in range(segs):
			var a := float(i) * TAU / float(segs)
			var ca := cos(a)
			var sa := sin(a)
			var rz := rzf if sa < 0.0 else rzb
			pts.append(Vector3(ca * rx, y, sa * rz + zsh))
		ring_pts.append(pts)
	_stitch_rings(st, ring_pts, segs, cap_ends)
	st.index()
	st.generate_normals()
	return st.commit()


static func _sweep_tube(pts: Array[Vector3], rads: Array[float], segs: int, ref_up: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_append_tube(st, pts, rads, segs, ref_up)
	st.index()
	st.generate_normals()
	return st.commit()


static func _append_tube(st: SurfaceTool, pts: Array[Vector3], rads: Array[float], segs: int, ref_up: Vector3) -> void:
	var n := pts.size()
	if n < 2:
		return
	var ring_pts: Array = []
	for i in range(n):
		var p_prev := pts[maxi(0, i - 1)]
		var p_next := pts[mini(n - 1, i + 1)]
		var tang := (p_next - p_prev)
		if tang.length_squared() < 1e-8:
			tang = Vector3.UP
		else:
			tang = tang.normalized()
		var up_v := ref_up
		if absf(tang.dot(up_v)) > 0.94:
			up_v = Vector3.RIGHT if absf(tang.x) < 0.9 else Vector3.FORWARD
		var b1 := tang.cross(up_v).normalized()
		var b2 := b1.cross(tang).normalized()
		var r := rads[mini(i, rads.size() - 1)]
		var ring: Array[Vector3] = []
		for si in range(segs):
			var a := float(si) * TAU / float(segs)
			ring.append(pts[i] + (b1 * cos(a) + b2 * sin(a)) * r)
		ring_pts.append(ring)
	_stitch_rings(st, ring_pts, segs, true)


# Sweeps a flat rounded-rectangle fabric strap along `pts` whose outward normal points away from the torso spine
static func _append_ribbon_strap(st: SurfaceTool, pts: Array[Vector3], half_widths: Array[float], half_thick: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	var segs := 8
	var ring_pts: Array = []
	for i in range(n):
		var p_prev := pts[maxi(0, i - 1)]
		var p_next := pts[mini(n - 1, i + 1)]
		var tang := (p_next - p_prev)
		if tang.length_squared() < 1e-8:
			tang = Vector3.DOWN
		else:
			tang = tang.normalized()
		var out_n := Vector3(pts[i].x, maxf(0.0, pts[i].y - 0.16) * 0.7, pts[i].z)
		if out_n.length_squared() < 1e-6:
			out_n = Vector3.FORWARD
		else:
			out_n = out_n.normalized()
		var side_v := tang.cross(out_n)
		if side_v.length_squared() < 1e-6:
			side_v = Vector3.RIGHT
		else:
			side_v = side_v.normalized()
		out_n = side_v.cross(tang).normalized()
		var hw := half_widths[mini(i, half_widths.size() - 1)]
		var ring: Array[Vector3] = []
		for si in range(segs):
			var a := float(si) * TAU / float(segs)
			ring.append(pts[i] + side_v * (cos(a) * hw) + out_n * (sin(a) * half_thick))
		ring_pts.append(ring)
	_stitch_rings(st, ring_pts, segs, true)


static func _stitch_grid(st: SurfaceTool, grid: Array, rows: int, cols: int) -> void:
	for ri in range(rows):
		var r0: Array = grid[ri]
		var r1: Array = grid[ri + 1]
		for ci in range(cols):
			var p00: Vector3 = r0[ci]
			var p01: Vector3 = r0[ci + 1]
			var p10: Vector3 = r1[ci]
			var p11: Vector3 = r1[ci + 1]
			st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)


static func _stitch_rings(st: SurfaceTool, ring_pts: Array, segs: int, cap_ends: bool) -> void:
	# Godot 4 front-face winding is CLOCKWISE when viewed from outside!
	for ri in range(ring_pts.size() - 1):
		var r0: Array = ring_pts[ri]
		var r1: Array = ring_pts[ri + 1]
		for i in range(segs):
			var ni := (i + 1) % segs
			var p00: Vector3 = r0[i]
			var p01: Vector3 = r0[ni]
			var p10: Vector3 = r1[i]
			var p11: Vector3 = r1[ni]
			st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
	if cap_ends and ring_pts.size() >= 2:
		var bot: Array = ring_pts[0]
		var b_mid := Vector3.ZERO
		for p: Vector3 in bot: b_mid += p
		b_mid /= float(segs)
		for i in range(segs):
			var ni := (i + 1) % segs
			st.add_vertex(b_mid); st.add_vertex(bot[ni]); st.add_vertex(bot[i])
		var top: Array = ring_pts[ring_pts.size() - 1]
		var t_mid := Vector3.ZERO
		for p: Vector3 in top: t_mid += p
		t_mid /= float(segs)
		for i in range(segs):
			var ni := (i + 1) % segs
			st.add_vertex(t_mid); st.add_vertex(top[i]); st.add_vertex(top[ni])
