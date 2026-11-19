class_name LandmarksBuilder
extends RefCounted


static func build_landmarks(
	parent: Node3D,
	landmarks: Dictionary,
	building_mat: ShaderMaterial,
	road_edges: Array = []
) -> Dictionary:
	var result := {
		"lights": [],
		"monorail_curve": null,
		"monorail_cars": [],
		"spheres_mat": null,
	}

	var holder := Node3D.new()
	holder.name = "CityLandmarks"
	parent.add_child(holder)

	var conc_mat := ShaderMaterial.new()
	conc_mat.shader = load("res://shaders/concrete_arch.gdshader") as Shader

	var spheres_mat := ShaderMaterial.new()
	spheres_mat.shader = load("res://shaders/landmark_spheres.gdshader") as Shader
	result["spheres_mat"] = spheres_mat

	if landmarks.is_empty():
		# Grid City Central Park Conservatory Pavilion & Granite Fountain at (-62.5, -62.5)!
		_build_amazon_spheres(
			holder,
			{
				"domes": [
					{"pos": [-62.5, -62.5], "r": 16.5, "h": 24.0},
					{"pos": [-43.0, -56.0], "r": 11.5, "h": 17.5},
				]
			},
			spheres_mat,
			conc_mat,
			result["lights"]
		)
		_build_plaza_fountain(holder, -84.0, -62.5, conc_mat, result["lights"])
		return result

	if landmarks.has("spheres"):
		_build_amazon_spheres(holder, landmarks["spheres"], spheres_mat, conc_mat, result["lights"])

	if landmarks.has("westin_towers"):
		_build_westin_towers(holder, landmarks["westin_towers"], building_mat, conc_mat)

	if landmarks.has("westlake_center"):
		_build_westlake_center(holder, landmarks["westlake_center"], building_mat, conc_mat, result["lights"])

	if landmarks.has("monorail"):
		var mono := _build_monorail_system(holder, landmarks["monorail"], conc_mat, result["lights"], road_edges)
		result["monorail_curve"] = mono["curve"]
		result["monorail_cars"] = mono["cars"]

	return result


static func _build_amazon_spheres(
	parent: Node3D,
	data: Dictionary,
	spheres_mat: ShaderMaterial,
	conc_mat: ShaderMaterial,
	lights: Array
) -> void:
	var root := Node3D.new()
	root.name = "ConservatorySpheres"
	parent.add_child(root)

	var foliage_mat := ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader") as Shader

	var bark_mat := ShaderMaterial.new()
	bark_mat.shader = load("res://shaders/bark.gdshader") as Shader

	var corten_mat := StandardMaterial3D.new()
	corten_mat.albedo_color = Color(0.42, 0.22, 0.14)
	corten_mat.roughness = 0.72
	corten_mat.metallic = 0.35

	var domes: Array = data.get("domes", [])
	for d_i in range(domes.size()):
		var d: Dictionary = domes[d_i]
		var p: Array = d["pos"]
		var cx := float(p[0])
		var cz := float(p[1])
		var r := float(d["r"])
		var h := float(d["h"])

		var dome_node := Node3D.new()
		dome_node.position = Vector3(cx, 0.0, cz)
		root.add_child(dome_node)

		# Precast architectural concrete base + Corten weathered steel planter rim
		var base_cyl := CylinderMesh.new()
		base_cyl.top_radius = r * 0.97
		base_cyl.bottom_radius = r * 1.01
		base_cyl.height = 1.9
		base_cyl.radial_segments = 36
		base_cyl.material = conc_mat
		var base_mi := MeshInstance3D.new()
		base_mi.mesh = base_cyl
		base_mi.position.y = 0.95
		dome_node.add_child(base_mi)

		var rim_tor := TorusMesh.new()
		rim_tor.inner_radius = r * 0.94
		rim_tor.outer_radius = r * 1.02
		rim_tor.rings = 32
		rim_tor.ring_segments = 8
		rim_tor.material = corten_mat
		var rim_mi := MeshInstance3D.new()
		rim_mi.mesh = rim_tor
		rim_mi.position.y = 1.92
		dome_node.add_child(rim_mi)

		# Geodesic Catalan Steel & Low-Iron Glass Dome!
		var sph := SphereMesh.new()
		sph.radius = r
		sph.height = r * 1.88
		sph.radial_segments = 42
		sph.rings = 24
		sph.material = spheres_mat
		var sph_mi := MeshInstance3D.new()
		sph_mi.mesh = sph
		sph_mi.position.y = h - r + 0.35
		dome_node.add_child(sph_mi)

		# Lush 4-story vertical living fern wall ("The Bird's Nest" core) + tropical cloud-forest trees!
		var core_wall := CylinderMesh.new()
		core_wall.top_radius = r * 0.22
		core_wall.bottom_radius = r * 0.28
		core_wall.height = h * 0.68
		core_wall.material = foliage_mat
		var cw_mi := MeshInstance3D.new()
		cw_mi.mesh = core_wall
		cw_mi.position.y = h * 0.35
		dome_node.add_child(cw_mi)

		for t_i in range(7):
			var ang := float(t_i) * TAU / 7.0 + float(d_i) * 0.8
			var tr := r * (0.42 + 0.14 * float(t_i % 2))
			var crown := SphereMesh.new()
			crown.radius = r * 0.22
			crown.height = r * 0.34
			crown.radial_segments = 12
			crown.rings = 8
			crown.material = foliage_mat
			var c_mi := MeshInstance3D.new()
			c_mi.mesh = crown
			c_mi.position = Vector3(cos(ang) * tr, 4.2 + float(t_i % 3) * 2.6, sin(ang) * tr)
			dome_node.add_child(c_mi)

			var trk := CylinderMesh.new()
			trk.top_radius = 0.14
			trk.bottom_radius = 0.24
			trk.height = 4.2
			trk.material = bark_mat
			var t_mi := MeshInstance3D.new()
			t_mi.mesh = trk
			t_mi.position = Vector3(cos(ang) * tr, 2.1, sin(ang) * tr)
			dome_node.add_child(t_mi)

		var glow := OmniLight3D.new()
		glow.light_color = Color(0.96, 0.90, 0.66)
		glow.light_energy = 0.0
		glow.visible = false
		glow.omni_range = r * 2.1
		glow.distance_fade_enabled = true
		glow.distance_fade_begin = 120.0
		glow.distance_fade_length = 40.0
		glow.position = Vector3(0.0, h * 0.45, 0.0)
		dome_node.add_child(glow)
		lights.append(glow)


static func _build_westin_towers(
	parent: Node3D,
	towers: Array,
	building_mat: ShaderMaterial,
	conc_mat: ShaderMaterial
) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var fin_st := SurfaceTool.new()
	fin_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segs := 36
	var beacon_mat := _make_beacon_mat()

	for t_i in range(towers.size()):
		var td: Dictionary = towers[t_i]
		var p: Array = td["pos"]
		var cx := float(p[0])
		var cz := float(p[1])
		var r := float(td["r"])
		var h := float(td["h"])
		var y0 := float(td.get("base_y", 12.0))
		# Dark bronze solar-tinted curtain wall with warm fluted ribs!
		var vcol := Color(0.46, 0.44, 0.41, (0.0 * 64.0 + float(18 + t_i)) / 255.0)

		for s in range(segs):
			var a0 := float(s) * TAU / float(segs)
			var a1 := float(s + 1) * TAU / float(segs)
			var x0 := cx + cos(a0) * (r - 0.18)
			var z0 := cz + sin(a0) * (r - 0.18)
			var x1 := cx + cos(a1) * (r - 0.18)
			var z1 := cz + sin(a1) * (r - 0.18)
			var n0 := Vector3(cos(a0), 0.0, sin(a0))
			var n1 := Vector3(cos(a1), 0.0, sin(a1))
			var u0 := float(s) * (TAU * r / float(segs))
			var u1 := float(s + 1) * (TAU * r / float(segs))

			var b0 := Vector3(x0, y0, z0)
			var b1 := Vector3(x1, y0, z1)
			var top1 := Vector3(x1, h, z1)
			var top0 := Vector3(x0, h, z0)

			st.set_color(vcol); st.set_normal(n0); st.set_uv(Vector2(u0, y0)); st.add_vertex(b0)
			st.set_color(vcol); st.set_normal(n1); st.set_uv(Vector2(u1, y0)); st.add_vertex(b1)
			st.set_color(vcol); st.set_normal(n1); st.set_uv(Vector2(u1, h)); st.add_vertex(top1)
			st.set_color(vcol); st.set_normal(n0); st.set_uv(Vector2(u0, y0)); st.add_vertex(b0)
			st.set_color(vcol); st.set_normal(n1); st.set_uv(Vector2(u1, h)); st.add_vertex(top1)
			st.set_color(vcol); st.set_normal(n0); st.set_uv(Vector2(u0, h)); st.add_vertex(top0)

			st.set_color(vcol); st.set_normal(Vector3.UP); st.set_uv(Vector2.ZERO); st.add_vertex(Vector3(cx, h, cz))
			st.set_color(vcol); st.set_normal(Vector3.UP); st.set_uv(Vector2.ZERO); st.add_vertex(top0)
			st.set_color(vcol); st.set_normal(Vector3.UP); st.set_uv(Vector2.ZERO); st.add_vertex(top1)

			# 36 Extruded 3D Vertical Fluted Precast Concrete Fins around each cylindrical tower!
			var fin_basis := Basis(Vector3.UP, -a0 + PI * 0.5)
			var fin_pos := Vector3(cx + cos(a0) * (r + 0.06), (y0 + h + 1.8) * 0.5, cz + sin(a0) * (r + 0.06))
			CityBuilder._emit_colored_box(fin_st, Transform3D(fin_basis, fin_pos), Vector3(0.32, (h - y0) + 1.8, 0.52), Color.WHITE)

		# Sculpted circular precast crown drum + parapet ring
		var crown := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = r * 0.66
		cyl.bottom_radius = r * 0.70
		cyl.height = 6.2
		cyl.radial_segments = 28
		cyl.material = conc_mat
		crown.mesh = cyl
		crown.position = Vector3(cx, h + 3.1, cz)
		parent.add_child(crown)

		_add_beacon(parent, Vector3(cx, h + 7.2, cz), beacon_mat)

	var mi := MeshInstance3D.new()
	mi.name = "WestinTwinCylinders"
	mi.mesh = st.commit()
	mi.material_override = building_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)

	var fin_mi := MeshInstance3D.new()
	fin_mi.name = "WestinFlutedFins3D"
	fin_mi.mesh = fin_st.commit()
	fin_mi.material_override = conc_mat
	fin_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(fin_mi)


static func _build_westlake_center(
	parent: Node3D,
	wc: Dictionary,
	building_mat: ShaderMaterial,
	conc_mat: ShaderMaterial,
	lights: Array
) -> void:
	var tp: Array = wc["tower_pos"]
	var tsz: Array = wc["tower_size"]
	var th := float(wc["tower_h"])
	var tx := float(tp[0])
	var tz := float(tp[1])
	var hw := float(tsz[0]) * 0.5
	var hd := float(tsz[1]) * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var vcol := Color(0.36, 0.48, 0.44, (0.0 * 64.0 + 33.0) / 255.0)
	var trim_c := Color(0.66, 0.56, 0.48) # Warm rose-granite piers of Westlake Center Tower!
	var poly := PackedVector2Array([
		Vector2(tx - hw, tz - hd),
		Vector2(tx + hw, tz - hd),
		Vector2(tx + hw, tz + hd),
		Vector2(tx - hw, tz + hd),
	])
	CityBuilder._extrude_tier_with_3d_relief(st, frame_st, poly, 21.0, th, 0, vcol, trim_c, false)
	# Real Westlake Tower: polished red-brown granite piers between green-tinted glass ribbons, stepped crown
	for i in range(poly.size()):
		var a2 := poly[i]
		var c2 := poly[(i + 1) % poly.size()]
		var w2 := a2.distance_to(c2)
		var d2 := (c2 - a2) / w2
		var n2 := Vector2(d2.y, -d2.x)
		if Geometry2D.is_point_in_polygon((a2 + c2) * 0.5 + n2 * 0.5, poly):
			n2 = -n2
		var ctx := {"o": Vector3(a2.x, 0.0, a2.y), "u": Vector3(d2.x, 0.0, d2.y), "n": Vector3(n2.x, 0.0, n2.y), "st": frame_st}
		for k in range(13):
			var fu := w2 * float(k) / 12.0
			StorefrontBuilder._box(ctx, fu - 0.55, fu + 0.55, 21.0, th, 0.0, 0.5, Color(0.44, 0.28, 0.24))
		var yb := 25.0
		while yb < th - 3.0:
			StorefrontBuilder._box(ctx, 0.0, w2, yb, yb + 0.9, 0.0, 0.25, Color(0.40, 0.26, 0.22))
			yb += 4.0
		StorefrontBuilder._box(ctx, -0.2, w2 + 0.2, th - 2.5, th + 1.5, 0.0, 0.6, Color(0.46, 0.30, 0.26))
		StorefrontBuilder._box(ctx, 4.0, w2 - 4.0, th + 1.5, th + 5.5, -4.0, -3.4, Color(0.42, 0.28, 0.24))

	var t_mi := MeshInstance3D.new()
	t_mi.name = "WestlakeCenterTower"
	t_mi.mesh = st.commit()
	t_mi.material_override = building_mat
	t_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(t_mi)

	var f_mi := MeshInstance3D.new()
	f_mi.name = "WestlakeTowerGraniteFrames"
	f_mi.mesh = frame_st.commit()
	var f_mat := StandardMaterial3D.new()
	f_mat.vertex_color_use_as_albedo = true
	f_mat.roughness = 0.72
	f_mi.material_override = f_mat
	parent.add_child(f_mi)

	_add_beacon(parent, Vector3(tx, th + 2.4, tz), _make_beacon_mat())

	# Vaulted Glass Galleria Atrium Skylight with Structural Steel Arch Ribs!
	var ap: Array = wc["arch_pos"]
	var arch_root := Node3D.new()
	arch_root.position = Vector3(float(ap[0]), 21.0, float(ap[1]))
	arch_root.rotation.y = deg_to_rad(-42.0)
	parent.add_child(arch_root)

	var arch_glass := StandardMaterial3D.new()
	arch_glass.albedo_color = Color(0.22, 0.42, 0.54, 0.48)
	arch_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arch_glass.roughness = 0.06
	arch_glass.metallic = 0.52

	var cyl := CylinderMesh.new()
	cyl.top_radius = 8.4; cyl.bottom_radius = 8.4; cyl.height = 28.0; cyl.radial_segments = 24
	cyl.material = arch_glass
	var arch_mi := MeshInstance3D.new()
	arch_mi.mesh = cyl
	arch_mi.rotation.x = deg_to_rad(90.0)
	arch_root.add_child(arch_mi)

	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.84, 0.86, 0.88); steel_mat.metallic = 0.65; steel_mat.roughness = 0.28
	for rz: float in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		var rib := TorusMesh.new()
		rib.inner_radius = 8.32; rib.outer_radius = 8.62; rib.rings = 24; rib.ring_segments = 8
		rib.material = steel_mat
		var rmi := MeshInstance3D.new()
		rmi.mesh = rib
		rmi.position = Vector3(0.0, 0.0, rz)
		rmi.rotation.x = deg_to_rad(90.0)
		arch_root.add_child(rmi)

	var fp: Array = wc["fountain_pos"]
	_build_plaza_fountain(parent, float(fp[0]), float(fp[1]), conc_mat, lights)


static func _build_plaza_fountain(
	parent: Node3D,
	fx: float,
	fz: float,
	conc_mat: ShaderMaterial,
	lights: Array
) -> void:
	var rim := TorusMesh.new()
	rim.inner_radius = 4.2
	rim.outer_radius = 5.2
	rim.material = conc_mat
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	rim_mi.position = Vector3(fx, 0.36, fz)
	parent.add_child(rim_mi)

	var w_mat := StandardMaterial3D.new()
	w_mat.albedo_color = Color(0.10, 0.42, 0.56)
	w_mat.roughness = 0.04
	w_mat.metallic = 0.38
	w_mat.clearcoat_enabled = true
	w_mat.clearcoat = 0.95

	var pool := CylinderMesh.new()
	pool.top_radius = 4.35; pool.bottom_radius = 4.35; pool.height = 0.28
	pool.material = w_mat
	var pool_mi := MeshInstance3D.new()
	pool_mi.mesh = pool
	pool_mi.position = Vector3(fx, 0.22, fz)
	parent.add_child(pool_mi)

	# Sculpted granite water-arch centerpiece inside fountain
	for step_i in range(3):
		var blk := BoxMesh.new()
		var sz_s := 2.8 - float(step_i) * 0.65
		blk.size = Vector3(sz_s, 0.55, sz_s)
		blk.material = conc_mat
		var bmi := MeshInstance3D.new()
		bmi.mesh = blk
		bmi.position = Vector3(fx, 0.52 + float(step_i) * 0.52, fz)
		bmi.rotation.y = deg_to_rad(float(step_i) * 22.0)
		parent.add_child(bmi)

	var fl := OmniLight3D.new()
	fl.light_color = Color(0.70, 0.92, 1.0)
	fl.light_energy = 0.0
	fl.visible = false
	fl.omni_range = 14.0
	fl.distance_fade_enabled = true
	fl.distance_fade_begin = 90.0
	fl.distance_fade_length = 30.0
	fl.position = Vector3(fx, 1.6, fz)
	parent.add_child(fl)
	lights.append(fl)


static func _build_monorail_system(
	parent: Node3D,
	mono: Dictionary,
	conc_mat: ShaderMaterial,
	lights: Array,
	road_edges: Array = []
) -> Dictionary:
	var raw_pts: Array = mono.get("path", [])
	var curve := TrackBuilder.create_smooth_curve(raw_pts, false)
	var total_len := curve.get_baked_length()

	var root := Node3D.new()
	root.name = "SeattleCenterMonorail"
	parent.add_child(root)

	# Extrude twin Alweg straddle concrete beams with precast concrete shader!
	var beam_st := SurfaceTool.new()
	beam_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := maxi(8, int(ceil(total_len / 2.5)))
	var ds := total_len / float(steps)

	for beam_x: float in [-1.45, 1.45]:
		var prof: Array[Vector2] = [
			Vector2(beam_x - 0.44, -0.56),
			Vector2(beam_x - 0.46, 0.54),
			Vector2(beam_x + 0.46, 0.54),
			Vector2(beam_x + 0.44, -0.56),
		]
		for i in range(steps):
			var f0 := TrackBuilder.sample_track_frame(curve, float(i) * ds, total_len, false)
			var f1 := TrackBuilder.sample_track_frame(curve, float(i + 1) * ds, total_len, false)
			_extrude_closed(beam_st, f0, f1, prof)

	# Batch straddle-portal concrete piers guaranteed CLEAR of EVERY street & curved tram track!
	var s_pier := 12.0
	while s_pier < total_len - 8.0:
		var placed := false
		for shift_s: float in [0.0, 5.5, -5.5, 10.5, -10.5]:
			var sc := clampf(s_pier + shift_s, 6.0, total_len - 6.0)
			var tf := TrackBuilder.sample_track_frame(curve, sc, total_len, false)
			var pier_tf := Transform3D(tf.basis, Vector3(tf.origin.x, 0.0, tf.origin.z))
			for span_half: float in [8.8, 10.8, 12.8]:
				var leg_l := pier_tf * Vector3(-span_half, 0.0, 0.0)
				var leg_r := pier_tf * Vector3(span_half, 0.0, 0.0)
				if _is_point_clear_of_roads(Vector2(leg_l.x, leg_l.z), road_edges) and _is_point_clear_of_roads(Vector2(leg_r.x, leg_r.z), road_edges):
					var col_h := tf.origin.y - 0.85
					for leg_x: float in [-span_half, span_half]:
						CityBuilder._emit_colored_box(beam_st, pier_tf * Transform3D(Basis.IDENTITY, Vector3(leg_x, col_h * 0.5, 0.0)), Vector3(1.05, col_h, 1.25), Color.WHITE)
					CityBuilder._emit_colored_box(beam_st, pier_tf * Transform3D(Basis.IDENTITY, Vector3(0.0, tf.origin.y - 0.72, 0.0)), Vector3(span_half * 2.0 + 1.1, 0.76, 1.25), Color.WHITE)
					placed = true
					break
			if placed:
				break
		s_pier += 28.0

	var beam_mi := MeshInstance3D.new()
	beam_mi.name = "MonorailGuidewayAndPiers"
	beam_mi.mesh = beam_st.commit()
	beam_mi.material_override = conc_mat
	beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(beam_mi)

	# Elevated Westlake Monorail Terminal Platform & Glass/Steel Truss Canopy
	var end_tf := TrackBuilder.sample_track_frame(curve, total_len - 14.0, total_len, false)
	var stn := Node3D.new()
	stn.transform = end_tf
	root.add_child(stn)

	_box(stn, Vector3(3.6, 0.38, 30.0), Vector3(0.0, -0.15, 0.0), conc_mat)

	var steel_dark := StandardMaterial3D.new()
	steel_dark.albedo_color = Color(0.16, 0.18, 0.21); steel_dark.metallic = 0.65; steel_dark.roughness = 0.34
	for pz: float in [-10.0, 0.0, 10.0]:
		_box(stn, Vector3(0.18, 3.5, 0.22), Vector3(0.0, 1.65, pz), steel_dark)
		_box(stn, Vector3(8.4, 0.16, 0.22), Vector3(0.0, 3.38, pz), steel_dark)

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.16, 0.30, 0.42, 0.78)
	roof_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	roof_mat.roughness = 0.14
	roof_mat.metallic = 0.48
	_box(stn, Vector3(8.5, 0.12, 30.5), Vector3(0.0, 3.48, 0.0), roof_mat)

	var m_light := OmniLight3D.new()
	m_light.light_color = Color(1.0, 0.92, 0.76)
	m_light.light_energy = 0.0
	m_light.visible = false
	m_light.omni_range = 20.0
	m_light.distance_fade_enabled = true
	m_light.distance_fade_begin = 110.0
	m_light.distance_fade_length = 35.0
	m_light.position = Vector3(0.0, 2.8, 0.0)
	stn.add_child(m_light)
	lights.append(m_light)

	# Streamlined 4-Car Alweg Blue Monorail Train with Clearcoat Metallic PBR Shader!
	var veh_mat := ShaderMaterial.new()
	veh_mat.shader = load("res://shaders/vehicle_pbr.gdshader") as Shader

	var cars: Array[Node3D] = []
	var c_blue := Color(0.08, 0.30, 0.62, 0.0)   # mat_id = 0 clearcoat paint
	var c_cream := Color(0.88, 0.90, 0.92, 0.0)  # mat_id = 0 clearcoat paint
	var c_glass := Color(0.10, 0.15, 0.20, 0.1)  # mat_id = 1 reflective glass
	var c_chrome := Color(0.74, 0.77, 0.80, 0.3) # mat_id = 3 brushed chrome
	var c_head := Color(1.0, 0.96, 0.85, 0.4)    # mat_id = 4 headlight

	for c_i in range(4):
		var car := Node3D.new()
		root.add_child(car)

		var cst := SurfaceTool.new()
		cst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bx := -1.45
		# Straddle bogie skirt + metallic blue lower hull + chrome beltline
		CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx, 0.28, 0.0)), Vector3(2.86, 1.32, 8.15), c_blue)
		CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx, 0.98, 0.0)), Vector3(2.91, 0.12, 8.20), c_chrome)
		CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx, 1.14, 0.0)), Vector3(2.88, 0.22, 8.18), c_cream)
		# Flush wrap-around tinted window band + window pillars + aerodynamic roof
		CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx, 1.66, 0.0)), Vector3(2.78, 0.88, 7.92), c_glass)
		for wz: float in [-2.6, 0.0, 2.6]:
			CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx, 1.66, wz)), Vector3(2.82, 0.90, 0.18), c_cream)
		CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx, 2.22, 0.0)), Vector3(2.68, 0.26, 8.05), c_cream)
		CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx, 2.40, 0.0)), Vector3(1.65, 0.16, 3.4), c_chrome)

		# Sloped nose headlamp cluster on end cars!
		if c_i == 0 or c_i == 3:
			var nz := -4.10 if c_i == 0 else 4.10
			CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx - 0.65, 0.72, nz)), Vector3(0.42, 0.18, 0.08), c_head)
			CityBuilder._emit_colored_box(cst, Transform3D(Basis.IDENTITY, Vector3(bx + 0.65, 0.72, nz)), Vector3(0.42, 0.18, 0.08), c_head)

		var c_mi := MeshInstance3D.new()
		c_mi.mesh = cst.commit()
		c_mi.material_override = veh_mat
		car.add_child(c_mi)
		cars.append(car)

	return {
		"curve": curve,
		"cars": cars,
	}


static func _is_point_clear_of_roads(pt: Vector2, road_edges: Array) -> bool:
	for ed in road_edges:
		var pts: Array = ed.get("pts", [])
		var hw := float(ed.get("width", 12.0)) * 0.5 + 1.35
		var hw2 := hw * hw
		for i in range(pts.size() - 1):
			var a_arr: Array = pts[i]
			var b_arr: Array = pts[i + 1]
			var a := Vector2(float(a_arr[0]), float(a_arr[1]))
			var b := Vector2(float(b_arr[0]), float(b_arr[1]))
			var ab := b - a
			var len2 := ab.length_squared()
			var t := clampf((pt - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.01 else 0.0
			var proj := a + ab * t
			if pt.distance_squared_to(proj) < hw2:
				return false
	return true


static func _make_beacon_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.15, 0.12)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.12, 0.08)
	m.emission_energy_multiplier = 3.2
	return m


static func _add_beacon(parent: Node3D, pos: Vector3, mat: Material) -> void:
	var sph := SphereMesh.new()
	sph.radius = 0.36
	sph.height = 0.72
	sph.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sph
	mi.position = pos
	parent.add_child(mi)


static func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)


static func _extrude_closed(
	st: SurfaceTool,
	f0: Transform3D,
	f1: Transform3D,
	prof: Array[Vector2]
) -> void:
	var m := prof.size()
	for j in range(m):
		var a := prof[j]
		var b := prof[(j + 1) % m]
		var v00 := f0 * Vector3(a.x, a.y, 0.0)
		var v01 := f0 * Vector3(b.x, b.y, 0.0)
		var v11 := f1 * Vector3(b.x, b.y, 0.0)
		var v10 := f1 * Vector3(a.x, a.y, 0.0)
		var edge2 := b - a
		var nrm := (f0.basis * Vector3(-edge2.y, edge2.x, 0.0).normalized()).normalized()
		for v: Vector3 in [v00, v01, v11, v00, v11, v10]:
			st.set_color(Color.WHITE)
			st.set_normal(nrm)
			st.add_vertex(v)
