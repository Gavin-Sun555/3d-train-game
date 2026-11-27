class_name SeattleConstructionBuilder
extends RefCounted
## Authentic 3D Pacific Northwest / Seattle Active Construction Sites & Urban Excavation Pits:
##   - Terrain-draped compacted earth / crushed-gravel pads (construction_earth.gdshader)
##   - Painted plywood & chain-link perimeter site hoardings + concrete Jersey barriers
##   - Shored concrete excavation foundations / multi-storey cast-in-place cores & rebar cages
##   - Blue/orange US OSHA safety guardrails, debris netting & external construction buckhoists
##   - Tall US yellow/red lattice tower cranes with glowing red FAA aviation beacons
##   - White US mobile jobsite office trailers, CAT-yellow tracked excavators & material stacks
## Batched into 600 m spatial cells (~6 draw calls per active cell) and draped directly onto
## Seattle's real DEM Terrain.surface(x, z) so nothing ever floats on downtown hills.

const CELL_M := 600.0
const SITE_SKY_VIS := 2400.0
const SITE_FENCE_VIS := 1150.0


static func build(parent: Node3D, map_data: Dictionary, _lights: Array) -> void:
	var lm: Dictionary = map_data.get("landmarks", {})
	var sites: Array = lm.get("construction_sites", [])
	if sites.is_empty():
		return

	var root := Node3D.new()
	root.name = "SeattleConstructionSites"
	root.set_meta("on_terrain", true)
	parent.add_child(root)

	var earth_mat := _make_earth_mat()
	var fence_mat := _make_std_mat(0.74, 0.14)
	var struct_mat := _make_std_mat(0.84, 0.08)
	var crane_mat := _make_std_mat(0.42, 0.56)
	var net_mat := _make_net_mat()
	var beacon_mat := _make_beacon_mat()

	var cells: Dictionary = {}
	for si in range(sites.size()):
		var s: Dictionary = sites[si]
		var cc: Array = s.get("c", [0.0, 0.0])
		if cc.size() < 2:
			continue
		var ck := Vector2i(int(floor(float(cc[0]) / CELL_M)), int(floor(float(cc[1]) / CELL_M)))
		if not cells.has(ck):
			cells[ck] = []
		(cells[ck] as Array).append({"idx": si, "data": s})

	for ck: Vector2i in cells.keys():
		var earth_st := _st()
		var fence_st := _st()
		var struct_st := _st()
		var crane_st := _st()
		var net_st := _st()
		var beacon_st := _st()

		for item: Dictionary in cells[ck]:
			_emit_seattle_site(
				earth_st, fence_st, struct_st, crane_st, net_st, beacon_st,
				item["data"] as Dictionary, int(item["idx"])
			)

		var tag := "C_%d_%d" % [ck.x, ck.y]
		_commit_st(root, "Earth_%s" % tag, earth_st, earth_mat, SITE_SKY_VIS, false)
		_commit_st(root, "Fence_%s" % tag, fence_st, fence_mat, SITE_FENCE_VIS, false)
		_commit_st(root, "Struct_%s" % tag, struct_st, struct_mat, SITE_SKY_VIS, true)
		_commit_st(root, "Crane_%s" % tag, crane_st, crane_mat, SITE_SKY_VIS, true)
		_commit_st(root, "SafetyNet_%s" % tag, net_st, net_mat, SITE_FENCE_VIS, false)
		_commit_st(root, "Beacon_%s" % tag, beacon_st, beacon_mat, SITE_SKY_VIS, false)


static func _y(x: float, z: float) -> float:
	return Terrain.surface(x, z) if Terrain.active else 0.0


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit_st(
	parent: Node3D,
	nm: String,
	st: SurfaceTool,
	mat: Material,
	vis_end: float,
	cast_shadow: bool
) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = vis_end
	mi.visibility_range_end_margin = vis_end * 0.08
	mi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	mi.set_meta("on_terrain", true)
	parent.add_child(mi)


static func _make_earth_mat() -> Material:
	var sh := load("res://shaders/construction_earth.gdshader") as Shader
	if sh != null:
		var sm := ShaderMaterial.new()
		sm.shader = sh
		return sm
	return _make_std_mat(0.95, 0.0)


static func _make_std_mat(rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	return m


static func _make_net_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.88
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _make_beacon_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(1.0, 0.16, 0.10)
	m.emission_energy_multiplier = 4.5
	m.roughness = 0.25
	return m


static func _emit_box(
	st: SurfaceTool,
	pos: Vector3,
	size: Vector3,
	col: Color,
	rot_y: float = 0.0,
	rot_z: float = 0.0
) -> void:
	var b := Basis.IDENTITY
	if absf(rot_y) > 0.0001:
		b = b.rotated(Vector3.UP, rot_y)
	if absf(rot_z) > 0.0001:
		b = b * Basis(Vector3.BACK, rot_z)
	RoadSignBuilder._box(st, Transform3D(b, pos), size, col)


static func _emit_poly_pad(st: SurfaceTool, poly: PackedVector2Array, y_off: float, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.size() < 3:
		return
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		# Subdivide large triangles so earth pad hugs curved Seattle DEM hillsides with zero ground clipping!
		_emit_draped_tri(st, a, b, c, y_off, col, 2)


static func _emit_draped_tri(
	st: SurfaceTool,
	a: Vector2,
	b: Vector2,
	c: Vector2,
	y_off: float,
	col: Color,
	depth: int
) -> void:
	if depth > 0 and maxf(a.distance_squared_to(b), maxf(b.distance_squared_to(c), c.distance_squared_to(a))) > 14.0 * 14.0:
		var ab := (a + b) * 0.5
		var bc := (b + c) * 0.5
		var ca := (c + a) * 0.5
		_emit_draped_tri(st, a, ab, ca, y_off, col, depth - 1)
		_emit_draped_tri(st, ab, b, bc, y_off, col, depth - 1)
		_emit_draped_tri(st, ca, bc, c, y_off, col, depth - 1)
		_emit_draped_tri(st, ab, bc, ca, y_off, col, depth - 1)
		return
	var va := Vector3(a.x, _y(a.x, a.y) + y_off, a.y)
	var vb := Vector3(b.x, _y(b.x, b.y) + y_off, b.y)
	var vc := Vector3(c.x, _y(c.x, c.y) + y_off, c.y)
	var nrm := (vb - va).cross(vc - va)
	if nrm.y < 0.0:
		var tmp := vb
		vb = vc
		vc = tmp
		nrm = -nrm
	nrm = nrm.normalized() if nrm.length_squared() > 1e-6 else Vector3.UP
	for v: Vector3 in [va, vb, vc]:
		st.set_color(col)
		st.set_normal(nrm)
		st.set_uv(Vector2(v.x * 0.05, v.z * 0.05))
		st.add_vertex(v)


static func _emit_seattle_site(
	earth_st: SurfaceTool,
	fence_st: SurfaceTool,
	struct_st: SurfaceTool,
	crane_st: SurfaceTool,
	net_st: SurfaceTool,
	beacon_st: SurfaceTool,
	s: Dictionary,
	s_idx: int
) -> void:
	var raw_pts: Array = s.get("pts", [])
	if raw_pts.size() < 3:
		return
	var poly := PackedVector2Array()
	for p in raw_pts:
		poly.append(Vector2(float(p[0]), float(p[1])))

	var cc: Array = s.get("c", [0.0, 0.0])
	var center := Vector2(float(cc[0]), float(cc[1]))
	var ang := float(s.get("a", 0.0))
	var hl := maxf(8.0, float(s.get("hl", 16.0)))
	var hw := maxf(6.0, float(s.get("hw", 12.0)))
	var kind := str(s.get("kind", "midrise"))
	var ux := Vector2(cos(ang), sin(ang))
	var uz := Vector2(-ux.y, ux.x)
	var rot_y := -ang

	# 1. Excavated compacted earth / crushed-gravel work pad draped smoothly onto Seattle DEM terrain
	var pad_col := Color(0.76, 0.72, 0.65) if kind == "pit" else Color(0.84, 0.79, 0.70)
	_emit_poly_pad(earth_st, poly, 0.16, pad_col)

	# 2. Authentic Seattle / Pacific Northwest Site Perimeter Hoarding & Concrete Jersey Barriers
	#    Dark PNW forest-green or charcoal plywood panels + orange/white safety stripe + concrete barriers
	var panel_col := Color(0.16, 0.28, 0.22) if (s_idx % 2 == 0) else Color(0.22, 0.25, 0.30)
	var post_col := Color(0.56, 0.60, 0.64)
	var barrier_col := Color(0.74, 0.74, 0.72)
	var hazard_org := Color(0.94, 0.42, 0.08)
	var hazard_wht := Color(0.95, 0.96, 0.97)
	var gate_done := false
	var n := poly.size()

	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var d := b - a
		var elen := d.length()
		if elen < 1.2:
			continue
		var ea := atan2(d.y, d.x)
		var seg_ry := -ea
		var dir2 := d / elen

		# Leave one wide vehicle access gate opening with orange bollards
		if not gate_done and elen >= 16.0:
			gate_done = true
			var gate_w := 6.6
			var half_rem := (elen - gate_w) * 0.5
			_emit_hoarding_run(fence_st, a, a + dir2 * half_rem, seg_ry, panel_col, post_col, barrier_col, hazard_org, hazard_wht)
			_emit_hoarding_run(fence_st, b - dir2 * half_rem, b, seg_ry, panel_col, post_col, barrier_col, hazard_org, hazard_wht)
			# Steel gate pillars & open chain-link gate frame
			for gp: Vector2 in [a + dir2 * half_rem, b - dir2 * half_rem]:
				var gy := _y(gp.x, gp.y)
				_emit_box(fence_st, Vector3(gp.x, gy + 1.50, gp.y), Vector3(0.36, 3.2, 0.36), hazard_org, seg_ry)
			# Overhead steel jobsite gate portal truss
			var gm := (a + b) * 0.5
			var gmy := _y(gm.x, gm.y)
			_emit_box(fence_st, Vector3(gm.x, gmy + 3.25, gm.y), Vector3(gate_w + 0.5, 0.42, 0.32), panel_col, seg_ry)
		else:
			_emit_hoarding_run(fence_st, a, b, seg_ry, panel_col, post_col, barrier_col, hazard_org, hazard_wht)

	# 3. Site Interior — Differentiate Excavated Urban Pit ("pit") vs Active Tower / Mid-Rise Frame!
	var conc_raw := Color(0.62, 0.63, 0.61)
	var conc_dark := Color(0.46, 0.47, 0.46)
	var rebar_col := Color(0.42, 0.28, 0.18)
	var steel_col := Color(0.28, 0.31, 0.35)
	var safety_org := Color(0.94, 0.44, 0.08)
	var net_blue := Color(0.14, 0.30, 0.52)
	var formwork_c := Color(0.76, 0.56, 0.28)
	var crane_anchors: Array[Vector2] = []

	if kind == "pit":
		# Authentic Downtown Seattle Excavated Pit (e.g. 801 3rd Ave "The Net", Civic Square "The City Hole"):
		#   - Shotcrete soldier-pile shoring walls lining the inner excavation bench
		#   - Poured concrete mat foundation slab, elevator shear-wall core stubs & protruding steel rebar
		#   - Concrete sump/dewatering boxes, gravel ramp & crane pedestal
		var core_l := clampf(hl * 0.72, 11.0, 26.0)
		var core_w := clampf(hw * 0.72, 9.0, 18.0)
		var cy := _y(center.x, center.y)

		# Heavy poured concrete mat foundation pad (embedded -3.2m deep so sloped Seattle hills never expose gap!)
		_emit_box(struct_st, Vector3(center.x, cy - 1.25, center.y), Vector3(core_l + 6.0, 3.2, core_w + 5.0), conc_dark, rot_y)
		# Soldier-pile retaining wall curbing around mat perimeter
		for side: float in [-1.0, 1.0]:
			var wp := center + uz * (side * (core_w * 0.5 + 2.4))
			var wy := _y(wp.x, wp.y)
			_emit_box(struct_st, Vector3(wp.x, wy + 0.45, wp.y), Vector3(core_l + 5.4, 2.2, 0.55), conc_raw, rot_y)
			# Steel H-beam soldier piles sticking up along shoring wall
			for pi in range(5):
				var tu := lerpf(-core_l * 0.46, core_l * 0.46, float(pi) / 4.0)
				var sp := wp + ux * tu
				_emit_box(crane_st, Vector3(sp.x, _y(sp.x, sp.y) + 1.05, sp.y), Vector3(0.26, 2.9, 0.26), rebar_col, rot_y)

		# Concrete elevator/staircore shear walls rising out of foundation + exposed rebar starter cages
		var shear_p := center - ux * (core_l * 0.16)
		var sy := _y(shear_p.x, shear_p.y)
		_emit_box(struct_st, Vector3(shear_p.x, sy + 1.4, shear_p.y), Vector3(8.5, 4.8, 6.2), conc_raw, rot_y)
		_emit_box(struct_st, Vector3(shear_p.x, sy + 4.0, shear_p.y), Vector3(8.9, 0.55, 6.6), formwork_c, rot_y)
		# Steel rebar dowels + orange safety railing around core deck
		for rx: float in [-3.4, -1.7, 0.0, 1.7, 3.4]:
			for rz: float in [-2.4, 2.4]:
				var rp := shear_p + ux * rx + uz * rz
				_emit_box(struct_st, Vector3(rp.x, sy + 5.1, rp.y), Vector3(0.16, 1.8, 0.16), rebar_col, rot_y)
		for side: float in [-1.0, 1.0]:
			var gp := shear_p + uz * (side * 3.25)
			_emit_box(crane_st, Vector3(gp.x, sy + 4.85, gp.y), Vector3(8.8, 0.14, 0.10), safety_org, rot_y)

		# Second partially-poured concrete footing pier with column rebar cages
		var pier_p := center + ux * (core_l * 0.24) - uz * (core_w * 0.14)
		var py := _y(pier_p.x, pier_p.y)
		_emit_box(struct_st, Vector3(pier_p.x, py + 0.55, pier_p.y), Vector3(6.8, 2.8, 5.2), conc_raw, rot_y)
		for cx_o: float in [-2.2, 2.2]:
			for cz_o: float in [-1.5, 1.5]:
				var cp := pier_p + ux * cx_o + uz * cz_o
				_emit_box(struct_st, Vector3(cp.x, py + 2.5, cp.y), Vector3(0.55, 2.2, 0.55), conc_raw, rot_y)
				_emit_box(struct_st, Vector3(cp.x, py + 4.0, cp.y), Vector3(0.22, 1.2, 0.22), rebar_col, rot_y)

		crane_anchors.append(center + ux * (core_l * 0.22) + uz * (core_w * 0.30))
	else:
		# Active Seattle Tower / Mid-Rise Under Construction:
		#   - Cast-in-place concrete core + floor slabs + perimeter columns + plywood formwork
		#   - US blue debris netting + orange OSHA safety rails + external buckhoist
		var n_blds := 2 if (hl >= 28.0 and hw >= 14.0) else 1
		for bi in range(n_blds):
			var u_off := 0.0 if n_blds == 1 else (float(bi) * 2.0 - 1.0) * (hl * 0.34)
			var bp := center + ux * u_off - uz * (hw * 0.08)
			if not Geometry2D.is_point_in_polygon(bp, poly):
				bp = center
			var b_l := clampf(hl * (0.60 if n_blds == 2 else 0.72), 11.0, 28.0)
			var b_w := clampf(hw * 0.64, 9.0, 18.0)
			var floors := (5 + ((s_idx * 3 + bi * 2) % 6)) if kind == "tower" else (3 + ((s_idx + bi) % 3))
			var fh := 3.35
			var total_h := float(floors) * fh
			var by := _y(bp.x, bp.y)

			# Deep concrete basement plinth so hills never expose underside
			_emit_box(struct_st, Vector3(bp.x, by - 1.5, bp.y), Vector3(b_l + 0.8, 3.6, b_w + 0.8), conc_dark, rot_y)
			# Central poured concrete elevator/stair core (rises 1.5 floors above active pouring deck — classic Seattle!)
			_emit_box(struct_st, Vector3(bp.x, by + (total_h + 4.5) * 0.5, bp.y), Vector3(b_l * 0.34, total_h + 4.5, b_w * 0.38), conc_raw, rot_y)

			# Floor slabs + perimeter columns
			for fl in range(1, floors + 1):
				var fy := by + float(fl) * fh
				_emit_box(struct_st, Vector3(bp.x, fy, bp.y), Vector3(b_l, 0.32, b_w), conc_raw, rot_y)
			var nx_c := maxi(3, int(round(b_l / 6.2)))
			var nz_c := maxi(2, int(round(b_w / 5.5)))
			for ci in range(nx_c):
				var lu := lerpf(-b_l * 0.46, b_l * 0.46, float(ci) / float(nx_c - 1))
				for cj in range(nz_c):
					if ci > 0 and ci < nx_c - 1 and cj > 0 and cj < nz_c - 1:
						continue
					var lv := lerpf(-b_w * 0.46, b_w * 0.46, float(cj) / float(nz_c - 1))
					var cp := bp + ux * lu + uz * lv
					_emit_box(struct_st, Vector3(cp.x, by + total_h * 0.5, cp.y), Vector3(0.48, total_h, 0.48), conc_dark, rot_y)

			# Top active-pour deck: plywood formwork lip + rebar dowels + orange OSHA guardrails
			_emit_box(struct_st, Vector3(bp.x, by + total_h + 0.55, bp.y), Vector3(b_l + 0.4, 0.65, b_w + 0.4), formwork_c, rot_y)
			for side: float in [-1.0, 1.0]:
				var rp := bp + uz * (side * (b_w * 0.5 + 0.14))
				_emit_box(crane_st, Vector3(rp.x, by + total_h + 1.35, rp.y), Vector3(b_l + 0.4, 0.14, 0.12), safety_org, rot_y)

			# Blue US debris netting curtains on upper 2-4 working storeys
			if floors >= 4:
				var net_fls := mini(floors - 2, 4)
				var net_h := float(net_fls) * fh
				var net_yc := by + (float(floors - net_fls) + float(net_fls) * 0.5) * fh
				for side: float in [-1.0, 1.0]:
					var pv := bp + uz * (side * (b_w * 0.5 + 0.35))
					_emit_box(net_st, Vector3(pv.x, net_yc, pv.y), Vector3(b_l + 0.6, net_h, 0.14), net_blue, rot_y)
					var pu := bp + ux * (side * (b_l * 0.5 + 0.35))
					_emit_box(net_st, Vector3(pu.x, net_yc, pu.y), Vector3(0.14, net_h, b_w + 0.6), net_blue.lightened(0.08), rot_y)

			# Exterior steel buckhoist elevator mast & yellow/red cab on tall builds
			if floors >= 5:
				var hp := bp + uz * (b_w * 0.5 + 1.35)
				_emit_box(crane_st, Vector3(hp.x, by + total_h * 0.5 + 1.2, hp.y), Vector3(0.95, total_h + 2.4, 0.95), Color(0.84, 0.22, 0.16), rot_y)
				_emit_box(struct_st, Vector3(hp.x, by + fh * 2.1, hp.y), Vector3(2.2, 2.5, 1.7), Color(0.90, 0.70, 0.12), rot_y)

			crane_anchors.append(bp + uz * (b_w * 0.5 + 3.6) + ux * (b_l * 0.20))

	# 4. US Lattice Tower Cranes (1-2 on towers/pits, 1 on larger midrises)
	var area_est := hl * hw * 3.4
	var want_cranes := 0
	if kind == "pit":
		want_cranes = 1
	elif kind == "tower":
		want_cranes = 2 if area_est >= 4200.0 else 1
	elif area_est >= 1150.0:
		want_cranes = 1

	for ci in range(mini(want_cranes, maxi(1, crane_anchors.size()))):
		var cp := crane_anchors[ci] if ci < crane_anchors.size() else center
		if not Geometry2D.is_point_in_polygon(cp, poly):
			cp = center + ux * (float(ci) * 10.0 - 4.0)
		var mast_h := (42.0 + float((s_idx * 7 + ci * 11) % 20)) if kind != "midrise" else (30.0 + float((s_idx * 5) % 10))
		var jib_l := 26.0 + float((s_idx * 5 + ci * 9) % 12)
		var jib_yaw := ang + 0.60 + float(s_idx) * 0.91 + float(ci) * 1.85
		_emit_tower_crane(crane_st, struct_st, beacon_st, cp, mast_h, jib_l, jib_yaw, (s_idx + ci) % 3 == 0)

	# 5. White US Jobsite Office Trailer + CAT-Yellow Tracked Excavator + Material Yard
	var trailer_p := center - ux * (hl * 0.52) + uz * (hw * 0.42)
	if Geometry2D.is_point_in_polygon(trailer_p, poly):
		_emit_us_jobsite_trailer(struct_st, trailer_p, rot_y)

	var yard_p := center + ux * (hl * 0.40) - uz * (hw * 0.36)
	if not Geometry2D.is_point_in_polygon(yard_p, poly):
		yard_p = center + ux * (hl * 0.28)
	if Geometry2D.is_point_in_polygon(yard_p, poly):
		var yy := _y(yard_p.x, yard_p.y)
		# Crushed-gravel stockpile + stacked lumber/steel beams
		_emit_box(earth_st, Vector3(yard_p.x, yy + 0.72, yard_p.y), Vector3(5.6, 1.45, 3.8), Color(0.58, 0.56, 0.52), rot_y)
		var mat_p := yard_p - ux * 4.4
		if Geometry2D.is_point_in_polygon(mat_p, poly):
			var my := _y(mat_p.x, mat_p.y)
			_emit_box(struct_st, Vector3(mat_p.x, my + 0.55, mat_p.y), Vector3(3.8, 1.0, 2.0), Color(0.76, 0.58, 0.34), rot_y)
			_emit_box(crane_st, Vector3(mat_p.x, my + 1.18, mat_p.y), Vector3(3.6, 0.26, 1.6), steel_col, rot_y)
		var exc_p := yard_p + ux * 5.2
		if Geometry2D.is_point_in_polygon(exc_p, poly):
			_emit_excavator(crane_st, struct_st, exc_p, rot_y + 0.75)


static func _emit_hoarding_run(
	st: SurfaceTool,
	a: Vector2,
	b: Vector2,
	rot_y: float,
	panel_col: Color,
	post_col: Color,
	barrier_col: Color,
	hazard_org: Color,
	hazard_wht: Color
) -> void:
	var elen := a.distance_to(b)
	if elen < 0.8:
		return
	var segs := maxi(1, int(ceil(elen / 6.5)))
	var seg_l := elen / float(segs)
	for si in range(segs):
		var p0 := a.lerp(b, float(si) / float(segs))
		var p1 := a.lerp(b, float(si + 1) / float(segs))
		var mid := (p0 + p1) * 0.5
		var my := _y(mid.x, mid.y)
		# Plywood hoarding wall extending 0.7m below terrain to prevent hillside gaps
		_emit_box(st, Vector3(mid.x, my + 0.90, mid.y), Vector3(seg_l + 0.08, 3.1, 0.16), panel_col, rot_y)
		# Concrete Jersey barrier base along sidewalk edge
		_emit_box(st, Vector3(mid.x, my + 0.28, mid.y), Vector3(seg_l * 0.92, 0.75, 0.44), barrier_col, rot_y)
		# Orange/white safety stripe along top hoarding rail
		var stripe_c := hazard_org if (si % 2 == 0) else hazard_wht
		_emit_box(st, Vector3(mid.x, my + 2.38, mid.y), Vector3(seg_l, 0.20, 0.20), stripe_c, rot_y)
		# Vertical steel fence post
		var py0 := _y(p0.x, p0.y)
		_emit_box(st, Vector3(p0.x, py0 + 1.35, p0.y), Vector3(0.14, 2.9, 0.22), post_col, rot_y)


static func _emit_tower_crane(
	crane_st: SurfaceTool,
	struct_st: SurfaceTool,
	beacon_st: SurfaceTool,
	pos: Vector2,
	mast_h: float,
	jib_l: float,
	yaw: float,
	is_red: bool
) -> void:
	var by := _y(pos.x, pos.y)
	var main_c := Color(0.84, 0.20, 0.16) if is_red else Color(0.92, 0.68, 0.08)
	var accent_c := Color(0.95, 0.95, 0.94) if is_red else Color(0.86, 0.22, 0.16)
	var steel_dk := Color(0.24, 0.26, 0.29)
	var conc_c := Color(0.56, 0.57, 0.56)

	# Heavy concrete crane anchor pedestal (deep skirt for hilly ground)
	_emit_box(struct_st, Vector3(pos.x, by - 0.5, pos.y), Vector3(4.6, 3.6, 4.6), conc_c, 0.0)

	# 4 vertical corner chords of open-lattice mast
	var mw := 0.90
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_emit_box(crane_st, Vector3(pos.x + sx * mw, by + mast_h * 0.5, pos.y + sz * mw), Vector3(0.22, mast_h, 0.22), main_c, 0.0)

	# Horizontal lattice bracing rings every 3.5m up the mast
	var y_off := 2.8
	var ring_i := 0
	while y_off < mast_h - 0.5:
		var rc := main_c if (ring_i % 4 != 3) else accent_c
		var wy := by + y_off
		_emit_box(crane_st, Vector3(pos.x, wy, pos.y + mw), Vector3(mw * 2.0, 0.18, 0.16), rc, 0.0)
		_emit_box(crane_st, Vector3(pos.x, wy, pos.y - mw), Vector3(mw * 2.0, 0.18, 0.16), rc, 0.0)
		_emit_box(crane_st, Vector3(pos.x + mw, wy, pos.y), Vector3(0.16, 0.18, mw * 2.0), rc, 0.0)
		_emit_box(crane_st, Vector3(pos.x - mw, wy, pos.y), Vector3(0.16, 0.18, mw * 2.0), rc, 0.0)
		y_off += 3.5
		ring_i += 1

	var top_y := by + mast_h
	var rot_y := -yaw
	var jdir := Vector2(cos(yaw), sin(yaw))
	var jside := Vector2(-jdir.y, jdir.x)

	# Slewing ring & white/glass operator cabin
	var cab_p := pos + jdir * 1.4 + jside * 1.55
	_emit_box(struct_st, Vector3(cab_p.x, top_y - 1.1, cab_p.y), Vector3(2.2, 2.5, 1.6), Color(0.93, 0.94, 0.95), rot_y)
	_emit_box(struct_st, Vector3(cab_p.x, top_y - 0.9, cab_p.y), Vector3(2.3, 1.2, 1.65), Color(0.16, 0.24, 0.34), rot_y)

	# Upper tower apex spire + glowing red FAA aviation beacon
	var apex_h := 6.0
	_emit_box(crane_st, Vector3(pos.x, top_y + apex_h * 0.5, pos.y), Vector3(1.12, apex_h, 1.12), main_c, rot_y)
	_emit_box(beacon_st, Vector3(pos.x, top_y + apex_h + 0.45, pos.y), Vector3(0.58, 0.58, 0.58), Color(1.0, 0.16, 0.10), 0.0)

	# Horizontal triangulated jib boom + tip aviation beacon
	var jib_c := pos + jdir * (jib_l * 0.5)
	_emit_box(crane_st, Vector3(jib_c.x, top_y + 0.35, jib_c.y), Vector3(jib_l, 0.30, 1.42), main_c, rot_y)
	_emit_box(crane_st, Vector3(jib_c.x, top_y + 1.82, jib_c.y), Vector3(jib_l, 0.26, 0.30), main_c, rot_y)
	var s := 3.6
	while s < jib_l - 1.0:
		var sp := pos + jdir * s
		_emit_box(crane_st, Vector3(sp.x, top_y + 1.08, sp.y), Vector3(0.20, 1.52, 1.32), accent_c if (int(s) % 7 < 3) else main_c, rot_y)
		s += 3.6
	var tip_p := pos + jdir * (jib_l - 0.3)
	_emit_box(beacon_st, Vector3(tip_p.x, top_y + 2.15, tip_p.y), Vector3(0.45, 0.45, 0.45), Color(1.0, 0.16, 0.10), 0.0)

	# Counter-jib & concrete counterweight ballast blocks
	var cj_l := 11.2
	var cj_c := pos - jdir * (cj_l * 0.5)
	_emit_box(crane_st, Vector3(cj_c.x, top_y + 0.45, cj_c.y), Vector3(cj_l, 0.44, 1.52), main_c, rot_y)
	var bal_p := pos - jdir * (cj_l - 2.0)
	_emit_box(struct_st, Vector3(bal_p.x, top_y + 1.55, bal_p.y), Vector3(3.3, 2.2, 2.0), conc_c, rot_y)

	# Steel stay cables from apex to jib & counter-jib
	var stay_f_p := pos + jdir * (jib_l * 0.38)
	var stay_f_len := sqrt((jib_l * 0.76) * (jib_l * 0.76) + (apex_h - 1.6) * (apex_h - 1.6))
	var stay_f_ang := atan2(apex_h - 1.6, jib_l * 0.76)
	_emit_box(crane_st, Vector3(stay_f_p.x, top_y + 1.6 + (apex_h - 1.6) * 0.5, stay_f_p.y), Vector3(stay_f_len, 0.12, 0.12), steel_dk, rot_y, -stay_f_ang)
	var stay_b_p := pos - jdir * (cj_l * 0.44)
	var stay_b_len := sqrt((cj_l * 0.88) * (cj_l * 0.88) + (apex_h - 0.8) * (apex_h - 0.8))
	var stay_b_ang := atan2(apex_h - 0.8, cj_l * 0.88)
	_emit_box(crane_st, Vector3(stay_b_p.x, top_y + 0.8 + (apex_h - 0.8) * 0.5, stay_b_p.y), Vector3(stay_b_len, 0.14, 0.14), steel_dk, rot_y, stay_b_ang)

	# Trolley, steel lifting cable & yellow hook block
	var tr_p := pos + jdir * (jib_l * 0.62)
	_emit_box(crane_st, Vector3(tr_p.x, top_y - 0.2, tr_p.y), Vector3(1.35, 0.58, 1.35), accent_c, rot_y)
	var drop_h := mast_h * 0.38
	_emit_box(crane_st, Vector3(tr_p.x, top_y - 0.5 - drop_h * 0.5, tr_p.y), Vector3(0.08, drop_h, 0.08), steel_dk, 0.0)
	_emit_box(crane_st, Vector3(tr_p.x, top_y - 0.5 - drop_h, tr_p.y), Vector3(0.85, 0.92, 0.54), Color(0.92, 0.70, 0.10), rot_y)


static func _emit_us_jobsite_trailer(st: SurfaceTool, pos: Vector2, rot_y: float) -> void:
	# Authentic US white/grey corrugated mobile construction office trailer (WillScot / Mobile Mini style)
	var by := _y(pos.x, pos.y)
	var body_w := Color(0.90, 0.91, 0.90)
	var skirt_dk := Color(0.24, 0.26, 0.29)
	var stripe_bl := Color(0.14, 0.32, 0.54)
	var win_c := Color(0.16, 0.25, 0.34)
	# Under-chassis skirt extending down into hillside
	_emit_box(st, Vector3(pos.x, by - 0.25, pos.y), Vector3(11.6, 1.6, 3.5), skirt_dk, rot_y)
	# Main trailer cabin
	_emit_box(st, Vector3(pos.x, by + 2.05, pos.y), Vector3(12.2, 2.95, 3.8), body_w, rot_y)
	# Flat dark roof membrane + blue contractor fascia stripe
	_emit_box(st, Vector3(pos.x, by + 3.60, pos.y), Vector3(12.4, 0.22, 4.0), skirt_dk, rot_y)
	_emit_box(st, Vector3(pos.x, by + 3.22, pos.y), Vector3(12.28, 0.28, 3.88), stripe_bl, rot_y)
	# Side aluminum windows & end HVAC unit
	var u := Vector2(cos(-rot_y), sin(-rot_y))
	var v := Vector2(-u.y, u.x)
	for wi in range(3):
		var tu := lerpf(-4.0, 4.0, float(wi) / 2.0)
		for side: float in [-1.0, 1.0]:
			var wp := pos + u * tu + v * (side * 1.94)
			_emit_box(st, Vector3(wp.x, by + 2.15, wp.y), Vector3(1.25, 1.05, 0.10), win_c, rot_y)
	var ac_p := pos + u * 6.35
	_emit_box(st, Vector3(ac_p.x, by + 2.1, ac_p.y), Vector3(0.65, 1.45, 1.15), Color(0.64, 0.66, 0.68), rot_y)


static func _emit_excavator(crane_st: SurfaceTool, struct_st: SurfaceTool, pos: Vector2, rot_y: float) -> void:
	# CAT-yellow tracked hydraulic excavator grounded on Seattle Terrain.surface
	var by := _y(pos.x, pos.y)
	var yel := Color(0.92, 0.68, 0.08)
	var dk := Color(0.18, 0.19, 0.21)
	var u := Vector2(cos(-rot_y), sin(-rot_y))
	_emit_box(struct_st, Vector3(pos.x, by + 0.45, pos.y), Vector3(4.2, 0.90, 2.9), dk, rot_y)
	_emit_box(crane_st, Vector3(pos.x, by + 1.65, pos.y), Vector3(3.6, 1.45, 2.6), yel, rot_y)
	var cab := pos + u * 0.45
	_emit_box(struct_st, Vector3(cab.x, by + 2.55, cab.y), Vector3(1.5, 1.35, 1.1), Color(0.18, 0.26, 0.34), rot_y)
	var boom_p := pos + u * 3.4
	_emit_box(crane_st, Vector3(boom_p.x, by + 3.10, boom_p.y), Vector3(4.6, 0.55, 0.45), yel, rot_y, 0.52)
	var arm_p := pos + u * 5.7
	_emit_box(crane_st, Vector3(arm_p.x, by + 2.65, arm_p.y), Vector3(3.2, 0.40, 0.38), yel, rot_y, -1.05)
