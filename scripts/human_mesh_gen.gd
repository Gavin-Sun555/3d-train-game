class_name HumanMeshGen
extends RefCounted

# Procedural Anatomically-Proportioned 3D Human Character Generator (4 Urban Commuter Archetypes).
# Uses a unified parametric sculpted head surface (eye sockets, brow ridge, cheekbones, sculpted nose, lips, jaw)
# and derives full-coverage hair shells directly from the skull surface + outward offset so bald gaps are impossible.

static var _cache: Dictionary = {}


# Unified parametric anatomical head surface: v in [0..1] (chin -> crown), a in [0..TAU) (sa < 0 is front face -Z)
static func _eval_head_point(v: float, a: float) -> Vector3:
	var ca := cos(a)
	var sa := sin(a) # -1 = front face (-Z), +1 = back of skull (+Z)
	var y := lerpf(-0.105, 0.115, v)

	# Smooth spherical-ovoid cranium transitioning to tapered jawline/chin (rounded crown, never pointy!)
	var theta := lerpf(-PI * 0.44, PI * 0.46, v)
	var ct := cos(theta)
	var y_sphere := sin(theta) * 0.110 + 0.004
	y = lerpf(y, y_sphere, 0.72)
	var jaw_taper := lerpf(0.68, 1.0, smoothstep(0.05, 0.56, v))
	var rx := 0.077 * ct * (jaw_taper if sa < 0.15 else lerpf(0.86, 1.0, smoothstep(0.08, 0.50, v)))
	var rzf := 0.085 * ct * lerpf(0.76, 1.0, smoothstep(0.04, 0.48, v))
	var rzb := 0.095 * ct * lerpf(0.72, 1.0, smoothstep(0.08, 0.45, v))
	var rz := rzf if sa < 0.0 else rzb

	var x := ca * rx
	var z := sa * rz + 0.004

	# Sculpted 3D facial topography on front hemisphere (sa < 0)
	if sa < 0.0:
		var front := -sa # 0 at side, 1 at center midline
		var mid_x := absf(ca) # 0 at midline, 1 at temple

		# 1. Recessed Eye Sockets (Orbits) around v = 0.52, |ca| = 0.36
		var eye_dv := (v - 0.52) / 0.065
		var eye_dx := (mid_x - 0.36) / 0.17
		var orbit := exp(-(eye_dv * eye_dv + eye_dx * eye_dx)) * smoothstep(0.45, 0.85, front)
		z += 0.0075 * orbit # push inward (+Z)

		# 2. Brow Ridge above eyes (v = 0.60)
		var brow_dv := (v - 0.60) / 0.045
		var brow := exp(-(brow_dv * brow_dv)) * smoothstep(0.55, 0.92, front) * (1.0 - smoothstep(0.50, 0.72, mid_x))
		z -= 0.0045 * brow # push outward (-Z)

		# 3. Cheekbones (Zygomatic arch) around v = 0.42, |ca| = 0.52
		var chk_dv := (v - 0.42) / 0.085
		var chk_dx := (mid_x - 0.52) / 0.22
		var cheek := exp(-(chk_dv * chk_dv + chk_dx * chk_dx)) * smoothstep(0.35, 0.80, front)
		z -= 0.0055 * cheek
		x += signf(ca) * 0.0035 * cheek

		# 4. Continuous Sculpted 3D Nose (bridge v=0.53 -> defined tip v=0.39 -> tuck under nostrils v=0.335)
		var nose_w := exp(-pow(mid_x / 0.16, 2.0)) * smoothstep(0.76, 0.98, front)
		var nose_bridge := exp(-pow((v - 0.47) / 0.088, 2.0)) * 0.015
		var nose_tip := exp(-pow((v - 0.39) / 0.045, 2.0)) * 0.022
		var nose_under := exp(-pow((v - 0.335) / 0.024, 2.0)) * 0.005
		z -= (nose_bridge + nose_tip - nose_under) * nose_w

		# 5. Sculpted Upper & Lower Lips + Chin contour (v = 0.21..0.29)
		var lip_w := exp(-pow(mid_x / 0.24, 2.0)) * smoothstep(0.72, 0.96, front)
		var u_lip := exp(-pow((v - 0.285) / 0.022, 2.0)) * 0.0055
		var m_line := exp(-pow((v - 0.260) / 0.012, 2.0)) * 0.0035
		var l_lip := exp(-pow((v - 0.232) / 0.024, 2.0)) * 0.0050
		var chin_dip := exp(-pow((v - 0.175) / 0.032, 2.0)) * 0.0035
		var chin_pt := exp(-pow((v - 0.095) / 0.055, 2.0)) * 0.0070 * exp(-pow(mid_x / 0.28, 2.0))
		z -= (u_lip - m_line + l_lip - chin_dip) * lip_w + chin_pt * smoothstep(0.65, 0.95, front)

	return Vector3(x, y, z)


static func get_head_mesh() -> ArrayMesh:
	if _cache.has("head"):
		return _cache["head"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v_steps := 18
	var segs := 24
	var ring_pts: Array = []
	for vi in range(v_steps + 1):
		var v := float(vi) / float(v_steps)
		var pts: Array[Vector3] = []
		for si in range(segs):
			var a := float(si) * TAU / float(segs)
			pts.append(_eval_head_point(v, a))
		ring_pts.append(pts)
	_stitch_rings(st, ring_pts, segs, true)
	st.generate_normals()
	var mesh := st.commit()
	_cache["head"] = mesh
	return mesh


static func get_hair_mesh(style_idx: int) -> ArrayMesh:
	var key := "hair_%d" % (style_idx % 4)
	if _cache.has(key):
		return _cache[key]
	# Derived DIRECTLY from _eval_head_point(v, a) + outward offset so bald gaps/skull poke-through are IMPOSSIBLE!
	var style := style_idx % 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v_steps := 12
	var segs := 24
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

			# Hairline v_start: naturally above brow on forehead (v=0.66..0.72), low at temples & nape (v=0.16..0.28)!
			var v_start := 0.70
			if style == 0: # Short tailored executive cut
				v_start = lerpf(0.71, 0.24, pow(backness, 0.65)) - sideness * 0.06
			elif style == 1: # Fuller casual wave with soft swept fringe
				v_start = lerpf(0.65, 0.20, pow(backness, 0.65)) - sideness * 0.07
			elif style == 2: # Shoulder-length bob (wraps down sides & back past jaw)
				v_start = lerpf(0.68, 0.02, pow(clampf((sa + 0.45) / 1.45, 0.0, 1.0), 0.55))
			else: # Sleek pulled-back hair (paired with bun)
				v_start = lerpf(0.73, 0.22, pow(backness, 0.72)) - sideness * 0.04

			v_start = clampf(v_start, 0.02, 0.85)
			var v_cur := lerpf(v_start, 0.995, t)
			var p_skull := _eval_head_point(v_cur, a)

			# Guaranteed positive outward hair thickness (+12mm..+21mm strictly outside skull!)
			var thick := 0.013 + 0.006 * sin(t * PI)
			if style == 1:
				thick += 0.005 * smoothstep(0.2, 0.9, t) # fuller top volume
			elif style == 2 and t < 0.45 and sa > -0.35:
				thick += 0.008 * (1.0 - t / 0.45) # natural bob curtain volume

			var out_n := Vector3(p_skull.x, p_skull.y - 0.01, p_skull.z - 0.004)
			if out_n.length_squared() < 1e-5:
				out_n = Vector3.UP
			else:
				out_n = out_n.normalized()

			var p_hair := p_skull + out_n * thick
			# For shoulder-length bob (style 2), drape the lower hair smoothly downward past chin/neck!
			if style == 2 and sa > -0.35 and t < 0.35:
				var drape := (1.0 - t / 0.35) * smoothstep(-0.35, 0.25, sa)
				p_hair.y -= drape * 0.055
				p_hair.x *= (1.0 + drape * 0.14)
				p_hair.z += drape * 0.016
			pts.append(p_hair)
		ring_pts.append(pts)

	_stitch_rings(st, ring_pts, segs, true)
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
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

	# 1. Sculpted anatomical head (with real eye sockets, brow, cheekbones, continuous nose & lips) + full-coverage hair!
	_add_part(head, get_head_mesh(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, skin_mat)
	_add_part(head, get_hair_mesh(hair_style), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, hair_mat)
	if hair_style % 4 == 3:
		_add_part(head, _get_unit_sphere(), Vector3(0.0, -0.015, 0.122), Vector3.ZERO, Vector3(0.044, 0.042, 0.042), hair_mat)

	# 2. Properly proportioned sculpted 3D Ears (brow-to-nose height, x = +-0.073)
	var sph := _get_unit_sphere()
	var box := _get_unit_box()
	for side: float in [-1.0, 1.0]:
		_add_part(head, sph, Vector3(side * 0.074, -0.002, 0.006), Vector3(0.0, side * 14.0, -side * 6.0), Vector3(0.014, 0.029, 0.019), skin_mat)

	# 3. Natural, Properly-Scaled Facial Features seated inside the sculpted eye sockets & lip contour!
	var brow_mat := _cached_simple_mat("brow_%02x%02x" % [int(hair_col.r * 255), int(hair_col.g * 255)], hair_col.lerp(skin_col.darkened(0.42), 0.22), 0.82)
	var lid_mat := _cached_simple_mat("lid_%02x%02x" % [int(skin_col.r * 255), int(skin_col.g * 255)], skin_col.darkened(0.18), 0.65)
	var eye_mat := _cached_simple_mat("eye_iris", Color(0.14, 0.11, 0.09), 0.22)
	var sclera_mat := _cached_simple_mat("eye_sclera", Color(0.87, 0.84, 0.81), 0.40)
	var lip_mat := _cached_simple_mat("lip_%02x" % int(skin_col.r * 255), skin_col.lerp(Color(0.62, 0.34, 0.34), 0.44), 0.58)

	for side: float in [-1.0, 1.0]:
		# Clear, well-proportioned arched eyebrows seated cleanly outside the brow ridge (z = -0.084)
		_add_part(head, box, Vector3(side * 0.028, 0.034, -0.084), Vector3(0.0, -side * 16.0, -side * 5.0), Vector3(0.033, 0.0068, 0.007), brow_mat)
		# Natural expressive almond eyes seated cleanly on the orbital surface (never buried inside skull!)
		_add_part(head, sph, Vector3(side * 0.028, 0.014, -0.077), Vector3(0.0, -side * 14.0, 0.0), Vector3(0.0168, 0.0092, 0.008), sclera_mat)
		_add_part(head, sph, Vector3(side * 0.028, 0.014, -0.0835), Vector3.ZERO, Vector3(0.0086, 0.0088, 0.0045), eye_mat)
		# Upper eyelid lash contour for crisp 3D facial depth
		_add_part(head, box, Vector3(side * 0.028, 0.0225, -0.082), Vector3(0.0, -side * 15.0, -side * 3.0), Vector3(0.032, 0.0044, 0.007), lid_mat)

	# Sculpted 3D Nose (bridge + tip + subtle shadow underside so it reads clearly in cabin lighting!)
	var nose_sh_mat := _cached_simple_mat("nose_sh_%02x" % int(skin_col.r * 255), skin_col.darkened(0.14), 0.65)
	_add_part(head, sph, Vector3(0.0, -0.010, -0.090), Vector3(16.0, 0.0, 0.0), Vector3(0.0135, 0.024, 0.017), skin_mat)
	_add_part(head, sph, Vector3(0.0, -0.024, -0.093), Vector3.ZERO, Vector3(0.0155, 0.0095, 0.012), skin_mat)
	_add_part(head, sph, Vector3(0.0, -0.030, -0.086), Vector3.ZERO, Vector3(0.014, 0.0045, 0.008), nose_sh_mat)

	# Natural sculpted upper & lower lips + subtle mouth line cleanly on the outer face plane (z = -0.075)
	var mouth_line_mat := _cached_simple_mat("mline_%02x" % int(skin_col.r * 255), skin_col.lerp(Color(0.32, 0.16, 0.16), 0.55), 0.65)
	_add_part(head, sph, Vector3(0.0, -0.047, -0.074), Vector3.ZERO, Vector3(0.024, 0.0056, 0.007), lip_mat)
	_add_part(head, box, Vector3(0.0, -0.051, -0.079), Vector3.ZERO, Vector3(0.038, 0.0024, 0.004), mouth_line_mat)
	_add_part(head, sph, Vector3(0.0, -0.054, -0.073), Vector3.ZERO, Vector3(0.021, 0.0058, 0.007), lip_mat)

	# Optional stylish commuter eyeglasses seated cleanly in front of brow & nose bridge (z = -0.092)
	if add_glasses:
		var frame_mat := _cached_simple_mat("glasses_frame", Color(0.12, 0.12, 0.14), 0.30)
		_add_part(head, box, Vector3(0.0, 0.016, -0.092), Vector3.ZERO, Vector3(0.016, 0.0040, 0.0040), frame_mat)
		for side: float in [-1.0, 1.0]:
			_add_part(head, box, Vector3(side * 0.030, 0.028, -0.092), Vector3.ZERO, Vector3(0.036, 0.0040, 0.0040), frame_mat)
			_add_part(head, box, Vector3(side * 0.030, 0.001, -0.092), Vector3.ZERO, Vector3(0.034, 0.0038, 0.0040), frame_mat)
			_add_part(head, box, Vector3(side * 0.048, 0.014, -0.092), Vector3.ZERO, Vector3(0.0040, 0.028, 0.0040), frame_mat)
			_add_part(head, box, Vector3(side * 0.012, 0.014, -0.092), Vector3.ZERO, Vector3(0.0038, 0.026, 0.0040), frame_mat)
			_add_part(head, box, Vector3(side * 0.062, 0.015, -0.044), Vector3.ZERO, Vector3(0.0038, 0.0038, 0.098), frame_mat)

	return head


static func _get_unit_sphere() -> SphereMesh:
	if not _cache.has("u_sph"):
		var s := SphereMesh.new()
		s.radius = 1.0; s.height = 2.0; s.radial_segments = 10; s.rings = 6
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


static func _add_part(parent: Node3D, m: Mesh, pos: Vector3, rot_deg: Vector3, sc: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = sc
	mi.visibility_range_end = 150.0
	parent.add_child(mi)
	return mi


static func get_torso_mesh(archetype: int) -> ArrayMesh:
	var key := "torso_%d" % (archetype % 4)
	if _cache.has(key):
		return _cache[key]
	var rings: Array = []
	match archetype % 4:
		0: # Tailored business coat / blazer
			rings = [
				[-0.31, 0.165, 0.108, 0.110, 0.0],
				[-0.20, 0.156, 0.102, 0.104, 0.0],
				[-0.06, 0.148, 0.098, 0.098, 0.0],
				[0.08,  0.172, 0.114, 0.106, -0.004],
				[0.20,  0.205, 0.106, 0.100, -0.004],
				[0.26,  0.165, 0.086, 0.084, 0.0],
				[0.28,  0.074, 0.066, 0.068, 0.0],
			]
		1: # Casual bomber jacket / parka
			rings = [
				[-0.26, 0.152, 0.106, 0.108, 0.0],
				[-0.14, 0.164, 0.116, 0.114, 0.0],
				[0.04,  0.176, 0.120, 0.114, -0.004],
				[0.19,  0.202, 0.110, 0.104, -0.004],
				[0.26,  0.158, 0.088, 0.086, 0.0],
				[0.28,  0.078, 0.070, 0.072, 0.0],
			]
		2: # Long flared trench coat
			rings = [
				[-0.44, 0.198, 0.132, 0.138, 0.004],
				[-0.26, 0.166, 0.110, 0.114, 0.002],
				[-0.08, 0.134, 0.092, 0.094, 0.0],
				[0.08,  0.158, 0.110, 0.100, -0.006],
				[0.20,  0.182, 0.098, 0.094, -0.004],
				[0.26,  0.145, 0.080, 0.078, 0.0],
				[0.28,  0.068, 0.062, 0.064, 0.0],
			]
		_: # Smart casual sweater / cardigan
			rings = [
				[-0.27, 0.156, 0.102, 0.104, 0.0],
				[-0.12, 0.148, 0.098, 0.098, 0.0],
				[0.06,  0.166, 0.112, 0.104, -0.004],
				[0.19,  0.190, 0.102, 0.098, -0.004],
				[0.25,  0.150, 0.082, 0.080, 0.0],
				[0.28,  0.070, 0.064, 0.066, 0.0],
			]
	var mesh := _loft_asymmetric_rings(rings, 14, true)
	_cache[key] = mesh
	return mesh


static func get_skirt_mesh(is_long: bool = false) -> ArrayMesh:
	var key := "skirt_long" if is_long else "skirt_knee"
	if _cache.has(key):
		return _cache[key]
	# Graceful A-line skirt mesh (fuller hip clearance so thighs NEVER clip through during walking/braking!)
	var rings: Array = []
	if is_long:
		rings = [
			[-0.62, 0.250, 0.200, 0.205, 0.0],
			[-0.42, 0.228, 0.180, 0.185, 0.0],
			[-0.22, 0.205, 0.160, 0.165, 0.0],
			[-0.08, 0.182, 0.136, 0.140, 0.0],
			[0.04,  0.158, 0.112, 0.114, 0.0],
		]
	else:
		rings = [
			[-0.42, 0.230, 0.182, 0.188, 0.0],
			[-0.26, 0.210, 0.162, 0.168, 0.0],
			[-0.12, 0.188, 0.140, 0.146, 0.0],
			[0.04,  0.158, 0.112, 0.114, 0.0],
		]
	var mesh := _loft_asymmetric_rings(rings, 14, true)
	_cache[key] = mesh
	return mesh


static func get_thigh_mesh() -> ArrayMesh:
	if _cache.has("thigh"):
		return _cache["thigh"]
	var rings: Array = [
		[-0.21, 0.052, 0.056, 0.054, 0.0],
		[-0.06, 0.064, 0.068, 0.068, 0.0],
		[0.12,  0.074, 0.078, 0.080, 0.0],
		[0.21,  0.076, 0.076, 0.080, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 10, true)
	_cache["thigh"] = mesh
	return mesh


static func get_shin_mesh() -> ArrayMesh:
	if _cache.has("shin"):
		return _cache["shin"]
	var rings: Array = [
		[-0.20, 0.036, 0.040, 0.038, 0.0],
		[-0.04, 0.048, 0.050, 0.056, 0.004],
		[0.10,  0.052, 0.054, 0.058, 0.002],
		[0.20,  0.050, 0.052, 0.050, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 10, true)
	_cache["shin"] = mesh
	return mesh


static func get_upper_arm_mesh() -> ArrayMesh:
	if _cache.has("upper_arm"):
		return _cache["upper_arm"]
	var rings: Array = [
		[-0.14, 0.038, 0.040, 0.040, 0.0],
		[0.0,   0.046, 0.048, 0.048, 0.0],
		[0.12,  0.052, 0.054, 0.054, 0.0],
		[0.15,  0.044, 0.046, 0.046, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 10, true)
	_cache["upper_arm"] = mesh
	return mesh


static func get_forearm_mesh() -> ArrayMesh:
	if _cache.has("forearm"):
		return _cache["forearm"]
	var rings: Array = [
		[-0.13, 0.028, 0.030, 0.030, 0.0],
		[0.02,  0.038, 0.040, 0.040, 0.0],
		[0.13,  0.040, 0.042, 0.042, 0.0],
	]
	var mesh := _loft_asymmetric_rings(rings, 10, true)
	_cache["forearm"] = mesh
	return mesh


static func get_shoe_mesh() -> ArrayMesh:
	if _cache.has("shoe"):
		return _cache["shoe"]
	var rings: Array = [
		[0.0,   0.042, 0.145, 0.085, 0.0],
		[0.028, 0.044, 0.142, 0.084, 0.0],
		[0.058, 0.036, 0.082, 0.072, 0.008],
		[0.082, 0.032, 0.042, 0.054, 0.014],
	]
	var mesh := _loft_asymmetric_rings(rings, 10, true)
	_cache["shoe"] = mesh
	return mesh


static func _loft_asymmetric_rings(rings: Array, segs: int, cap_ends: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
	st.generate_normals()
	return st.commit()


static func _stitch_rings(st: SurfaceTool, ring_pts: Array, segs: int, cap_ends: bool) -> void:
	# Godot 4 front-face winding is CLOCKWISE when viewed from outside!
	# Since ring angle `a` increments (+X -> +Z -> -X -> -Z), (p00 -> p01 -> p11) and (p00 -> p11 -> p10) face OUTWARD!
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
