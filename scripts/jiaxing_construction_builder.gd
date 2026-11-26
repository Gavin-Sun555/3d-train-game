class_name JiaxingConstructionBuilder
extends RefCounted

# High-craft batched 3D builder for REAL active construction sites (正在建设的工地) and
# rural agricultural polytunnel greenhouses (农田蔬菜大棚) across Jiaxing:
#   - Construction Sites (from OSM landuse=construction / building=construction + Google Earth bare-earth detection):
#       1. Compacted earth workpad, gravel staging strip & recessed excavated foundation pit
#       2. Chinese blue-and-white perimeter engineering hoarding (2.4m 蓝色工程围挡 + 安全文明施工红白腰带) & site gate arch
#       3. Multi-storey under-construction concrete structural frames wrapped in emerald-green safety netting (绿色密目安全网)
#          with open top formwork deck & vertical rebar starter columns
#       4. Tall bright-yellow & red lattice Tower Cranes (塔吊: mast, cab, counter-jib + concrete ballast, jib boom, hook cable)
#       5. 2-storey blue-and-white prefab site office barracks (彩钢板活动板房), stacked materials & yellow excavators
#   - Farmland Greenhouses (on real Google Earth / OSM farmland plots):
#       Neat parallel rows of arched white translucent agricultural polytunnels (蔬菜大棚) with dark steel hoop ribs.
#
# All geometry is batched into 6 static meshes (6 draw calls city-wide!) for zero framerate impact.


static func _emit_box(st: SurfaceTool, pos: Vector3, sz: Vector3, col: Color, rot_y: float = 0.0, rot_z: float = 0.0, rot_x: float = 0.0) -> void:
	var b := Basis.from_euler(Vector3(rot_x, rot_y, rot_z))
	RoadSignBuilder._box(st, Transform3D(b, pos), sz, col)


static func _commit_vc(parent: Node3D, node_name: String, st: SurfaceTool, rough: float = 0.78, metal: float = 0.08, shadow: bool = true) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = rough
	mat.metallic = metal
	mat.metallic_specular = 0.26
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _commit_poly_flat(st: SurfaceTool, poly: PackedVector2Array, y_lvl: float, col: Color) -> void:
	if poly.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	for i in range(0, idx.size(), 3):
		for k in [0, 1, 2]:
			var p: Vector2 = poly[idx[i + k]]
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y_lvl, p.y))


static func build(parent: Node3D, map_data: Dictionary, _lights: Array) -> void:
	var lm: Dictionary = map_data.get("landmarks", {})
	var sites: Array = lm.get("construction_sites", [])
	var greenhouses: Array = lm.get("farmland_greenhouses", [])
	if sites.is_empty() and greenhouses.is_empty():
		return

	var root := Node3D.new()
	root.name = "JiaxingConstructionAndAgri"
	parent.add_child(root)

	var earth_st := SurfaceTool.new()
	earth_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var struct_st := SurfaceTool.new()
	struct_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var net_st := SurfaceTool.new()
	net_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crane_st := SurfaceTool.new()
	crane_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var beacon_st := SurfaceTool.new()
	beacon_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gh_st := SurfaceTool.new()
	gh_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for s_idx in range(sites.size()):
		var s: Dictionary = sites[s_idx]
		_emit_construction_site(earth_st, struct_st, net_st, crane_st, beacon_st, s, s_idx)

	for g_idx in range(greenhouses.size()):
		var g: Dictionary = greenhouses[g_idx]
		_emit_greenhouse_cluster(gh_st, struct_st, g, g_idx)

	# Textured rugged compacted-earth & gravel pad shader (never flat smooth tan!)
	var earth_mesh := earth_st.commit()
	if earth_mesh != null and earth_mesh.get_surface_count() > 0:
		var emi := MeshInstance3D.new()
		emi.name = "ConstructionEarthPads"
		emi.mesh = earth_mesh
		var emat := ShaderMaterial.new()
		emat.shader = load("res://shaders/construction_earth.gdshader") as Shader
		emi.material_override = emat
		emi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(emi)
	_commit_vc(root, "ConstructionStructures", struct_st, 0.74, 0.12, true)
	_commit_vc(root, "ConstructionSafetyNets", net_st, 0.86, 0.02, true)
	_commit_vc(root, "ConstructionCranes", crane_st, 0.42, 0.56, true)

	# Translucent plastic agricultural greenhouses (蔬菜大棚)
	var gh_mesh := gh_st.commit()
	if gh_mesh != null and gh_mesh.get_surface_count() > 0:
		var gh_mi := MeshInstance3D.new()
		gh_mi.name = "FarmlandGreenhouses"
		gh_mi.mesh = gh_mesh
		var gh_mat := StandardMaterial3D.new()
		gh_mat.vertex_color_use_as_albedo = true
		gh_mat.roughness = 0.28
		gh_mat.metallic = 0.04
		gh_mat.metallic_specular = 0.55
		gh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		gh_mi.material_override = gh_mat
		root.add_child(gh_mi)

	# Glowing red aviation obstruction beacons atop every tower crane
	var bm := beacon_st.commit()
	if bm != null and bm.get_surface_count() > 0:
		var bmi := MeshInstance3D.new()
		bmi.name = "CraneAviationBeacons"
		bmi.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.vertex_color_use_as_albedo = true
		bmat.emission_enabled = true
		bmat.emission = Color(1.0, 0.18, 0.10)
		bmat.emission_energy_multiplier = 2.6
		bmat.roughness = 0.25
		bmi.material_override = bmat
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bmi)


static func _emit_construction_site(
	earth_st: SurfaceTool,
	struct_st: SurfaceTool,
	net_st: SurfaceTool,
	crane_st: SurfaceTool,
	beacon_st: SurfaceTool,
	s: Dictionary,
	s_idx: int
) -> void:
	var raw_pts: Array = s.get("pts", [])
	var poly := PackedVector2Array()
	for p in raw_pts:
		if p is Array and p.size() >= 2:
			poly.append(Vector2(float(p[0]), float(p[1])))
	if poly.size() < 3:
		return

	var cc: Array = s.get("c", [0.0, 0.0])
	var center := Vector2(float(cc[0]), float(cc[1]))
	var ang := float(s.get("a", 0.0))
	var hl := float(s.get("hl", 32.0))
	var hw := float(s.get("hw", 22.0))
	var ux := Vector2(cos(ang), sin(ang))
	var uz := Vector2(-ux.y, ux.x)
	var rot_y := -ang

	# 1. Compacted ochre-tan construction earth pad covering the real site polygon
	var earth_col := Color(0.56, 0.46, 0.34) if (s_idx % 2 == 0) else Color(0.52, 0.44, 0.35)
	_commit_poly_flat(earth_st, poly, 0.045, earth_col)

	# Concrete haul road apron & compacted gravel patch inside the pad
	var road_c := Color(0.54, 0.53, 0.50)
	var haul_len := minf(hl * 1.45, 78.0)
	var haul_pos := center + uz * (hw * 0.52)
	_emit_box(earth_st, Vector3(haul_pos.x, 0.08, haul_pos.y), Vector3(haul_len, 0.06, 5.2), road_c, rot_y)

	# 2. Chinese Blue-and-White Perimeter Construction Hoarding (2.4m 蓝色工程围挡) + Gate Arch
	var hoard_blue := Color(0.11, 0.34, 0.66)
	var hoard_white := Color(0.88, 0.90, 0.92)
	var hoard_red := Color(0.80, 0.18, 0.16)
	var gate_edge := s_idx % poly.size()
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var dv := b - a
		var sl := dv.length()
		if sl < 3.0:
			continue
		var ea := atan2(dv.y, dv.x)
		var erot := -ea
		var mid := (a + b) * 0.5
		if i == gate_edge and sl >= 14.0:
			# Leave an 8.5m truck entrance opening & erect a blue steel safety gate arch!
			var dir := dv / sl
			var half_l := (sl - 8.5) * 0.5
			for side: float in [-1.0, 1.0]:
				var seg_c := mid + dir * (side * (4.25 + half_l * 0.5))
				_emit_box(struct_st, Vector3(seg_c.x, 1.15, seg_c.y), Vector3(half_l, 2.30, 0.24), hoard_blue, erot)
				_emit_box(struct_st, Vector3(seg_c.x, 2.15, seg_c.y), Vector3(half_l, 0.36, 0.28), hoard_white, erot)
			# Entrance steel portal arch ("安全文明施工")
			for side: float in [-1.0, 1.0]:
				var gp := mid + dir * (side * 4.25)
				_emit_box(struct_st, Vector3(gp.x, 2.75, gp.y), Vector3(0.45, 5.5, 0.45), hoard_blue, erot)
			_emit_box(struct_st, Vector3(mid.x, 5.15, mid.y), Vector3(9.2, 0.95, 0.50), hoard_blue, erot)
			_emit_box(struct_st, Vector3(mid.x, 5.15, mid.y), Vector3(7.6, 0.42, 0.56), hoard_white, erot)
		else:
			_emit_box(struct_st, Vector3(mid.x, 1.15, mid.y), Vector3(sl, 2.30, 0.24), hoard_blue, erot)
			_emit_box(struct_st, Vector3(mid.x, 2.15, mid.y), Vector3(sl, 0.36, 0.28), hoard_white, erot)
			_emit_box(struct_st, Vector3(mid.x, 1.38, mid.y), Vector3(sl, 0.14, 0.28), hoard_red, erot)
			# Vertical galvanized steel bracing posts every ~12m
			var n_posts := clampi(int(floor(sl / 12.0)), 1, 14)
			for pk in range(n_posts):
				var t := (float(pk) + 0.5) / float(n_posts)
				var pp := a.lerp(b, t)
				_emit_box(struct_st, Vector3(pp.x, 1.25, pp.y), Vector3(0.18, 2.50, 0.34), hoard_white, erot)

	# 3. Under-construction buildings (1 to 3 towers/slabs depending on site footprint size!)
	var n_bldgs := 1
	if hl >= 46.0 and hw >= 24.0:
		n_bldgs = 2
	if hl >= 78.0 and hw >= 34.0:
		n_bldgs = 3

	var conc_col := Color(0.58, 0.59, 0.58)
	var conc_dk := Color(0.42, 0.43, 0.44)
	var net_col := Color(0.08, 0.44, 0.22)     # Iconic Chinese emerald-green safety mesh (绿色密目安全网)
	var net_stripe := Color(0.06, 0.34, 0.17)
	var scaf_col := Color(0.50, 0.52, 0.54)
	var formwork_col := Color(0.58, 0.34, 0.20) # Reddish plywood concrete formwork panels on top deck

	var b_w := clampf(hw * 0.48, 10.5, 17.5)
	var b_l := clampf((hl * 1.45) / float(n_bldgs) - 8.0, 14.0, 34.0)
	var crane_anchors: Array[Vector2] = []

	for bi in range(n_bldgs):
		var frac := 0.0 if n_bldgs == 1 else (float(bi) / float(n_bldgs - 1) - 0.5)
		var off_u := frac * minf(hl * 1.15, float(n_bldgs - 1) * (b_l + 10.0))
		var off_v := -hw * 0.12 if (bi % 2 == 0) else hw * 0.06
		var bp := center + ux * off_u + uz * off_v
		if not Geometry2D.is_point_in_polygon(bp, poly):
			bp = center
		# Stagger construction progress: foundation pit / low frame / mid-rise green-netted tower
		var floors := 4 + ((s_idx * 3 + bi * 5) % 9) # 4 to 12 storeys built so far
		var fh := 3.1
		var total_h := float(floors) * fh

		# Excavated concrete foundation raft slab
		_emit_box(earth_st, Vector3(bp.x, 0.22, bp.y), Vector3(b_l + 4.0, 0.38, b_w + 4.0), conc_dk, rot_y)

		# Concrete floor slabs & open structural perimeter columns
		for fl in range(floors + 1):
			var fy := float(fl) * fh + 0.35
			_emit_box(struct_st, Vector3(bp.x, fy, bp.y), Vector3(b_l, 0.32, b_w), conc_col, rot_y)

		var n_col_u := clampi(int(round(b_l / 6.2)), 3, 7)
		var n_col_v := clampi(int(round(b_w / 5.5)), 2, 4)
		for cu in range(n_col_u):
			var tu := lerpf(-b_l * 0.47, b_l * 0.47, float(cu) / float(n_col_u - 1))
			for cv in range(n_col_v):
				if cu > 0 and cu < n_col_u - 1 and cv > 0 and cv < n_col_v - 1:
					continue
				var tv := lerpf(-b_w * 0.46, b_w * 0.46, float(cv) / float(n_col_v - 1))
				var cp := bp + ux * tu + uz * tv
				_emit_box(struct_st, Vector3(cp.x, total_h * 0.5 + 0.35, cp.y), Vector3(0.55, total_h, 0.55), conc_dk, rot_y)
				# Exposed vertical steel rebar starters sticking 1.6m above the topmost poured deck!
				_emit_box(struct_st, Vector3(cp.x, total_h + 1.15, cp.y), Vector3(0.22, 1.60, 0.22), Color(0.32, 0.22, 0.16), rot_y)

		# Central reinforced-concrete elevator core projecting 1 floor above main slab
		_emit_box(struct_st, Vector3(bp.x, total_h * 0.5 + 1.4, bp.y), Vector3(minf(b_l * 0.26, 6.5), total_h + 2.8, minf(b_w * 0.42, 5.2)), conc_col.darkened(0.08), rot_y)

		# Iconic Chinese Emerald-Green Safety Netting (绿色密目安全网) wrapping floors 2..(floors-1)!
		if floors >= 3:
			var net_y0 := fh * 1.1
			var net_h := float(floors - 2) * fh + 0.8
			var net_yc := net_y0 + net_h * 0.5
			var nl := b_l + 1.3
			var nw := b_w + 1.3
			# 4 outer scaffolding mesh curtains
			for side: float in [-1.0, 1.0]:
				var p_v := bp + uz * (side * nw * 0.5)
				_emit_box(net_st, Vector3(p_v.x, net_yc, p_v.y), Vector3(nl, net_h, 0.16), net_col, rot_y)
				var p_u := bp + ux * (side * nl * 0.5)
				_emit_box(net_st, Vector3(p_u.x, net_yc, p_u.y), Vector3(0.16, net_h, nw), net_stripe, rot_y)
			# Horizontal steel scaffolding ledgers & orange safety toe-boards every 2 floors
			for fl in range(2, floors, 2):
				var ly := float(fl) * fh + 0.35
				for side: float in [-1.0, 1.0]:
					var p_v := bp + uz * (side * (nw * 0.5 + 0.12))
					_emit_box(struct_st, Vector3(p_v.x, ly, p_v.y), Vector3(nl + 0.2, 0.22, 0.14), scaf_col, rot_y)
			# Top plywood formwork lip around active pouring deck
			_emit_box(struct_st, Vector3(bp.x, total_h + 0.65, bp.y), Vector3(b_l + 0.4, 0.65, b_w + 0.4), formwork_col, rot_y)

		# Exterior construction hoist cage (施工电梯) on one flank
		var hoist_p := bp + uz * (b_w * 0.5 + 1.45)
		_emit_box(crane_st, Vector3(hoist_p.x, total_h * 0.5 + 1.0, hoist_p.y), Vector3(1.1, total_h + 2.0, 1.1), Color(0.82, 0.24, 0.18), rot_y)
		_emit_box(struct_st, Vector3(hoist_p.x, fh * 2.2, hoist_p.y), Vector3(2.4, 2.7, 1.8), Color(0.88, 0.68, 0.14), rot_y)

		crane_anchors.append(bp + uz * (b_w * 0.5 + 4.8) + ux * (b_l * 0.22))

	# 4. Lattice Tower Cranes (塔吊: 1-2 per site, bright yellow/red with jib, counter-jib, cab & aviation beacon!)
	var n_cranes := mini(2, crane_anchors.size())
	for ci in range(n_cranes):
		var cp := crane_anchors[ci]
		if not Geometry2D.is_point_in_polygon(cp, poly):
			cp = center + ux * (float(ci) * 14.0 - 7.0)
		var mast_h := 36.0 + float((s_idx * 7 + ci * 13) % 24)
		var jib_l := 28.0 + float((s_idx * 5 + ci * 9) % 12)
		var jib_yaw := ang + 0.55 + float(s_idx) * 0.87 + float(ci) * 1.9
		_emit_tower_crane(crane_st, struct_st, beacon_st, cp, mast_h, jib_l, jib_yaw, (s_idx + ci) % 3 == 0)

	# 5. 2-Storey Blue-and-White Prefab Site Office Barracks (彩钢板活动板房) + Material Yard & Excavator
	var barrack_p := center - ux * (hl * 0.55) + uz * (hw * 0.46)
	if Geometry2D.is_point_in_polygon(barrack_p, poly):
		_emit_prefab_barracks(struct_st, barrack_p, rot_y)

	# Material stockpiles (rebar bundles, gravel mound, red brick pallets) + Yellow Excavator silhouette
	var yard_p := center + ux * (hl * 0.45) + uz * (hw * 0.36)
	if Geometry2D.is_point_in_polygon(yard_p, poly):
		_emit_box(earth_st, Vector3(yard_p.x, 0.85, yard_p.y), Vector3(6.5, 1.6, 4.5), Color(0.62, 0.58, 0.50), rot_y)
		var brick_p := yard_p - ux * 5.2
		_emit_box(struct_st, Vector3(brick_p.x, 0.70, brick_p.y), Vector3(3.2, 1.3, 2.4), Color(0.66, 0.34, 0.24), rot_y)
		var exc_p := yard_p + ux * 5.8
		_emit_excavator(crane_st, struct_st, exc_p, rot_y + 0.65)


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
	var main_c := Color(0.84, 0.20, 0.16) if is_red else Color(0.92, 0.70, 0.10)
	var accent_c := Color(0.94, 0.94, 0.92) if is_red else Color(0.84, 0.20, 0.16)
	var steel_dk := Color(0.24, 0.26, 0.28)
	var conc_c := Color(0.56, 0.57, 0.56)

	# Concrete anchor pedestal
	_emit_box(struct_st, Vector3(pos.x, 0.70, pos.y), Vector3(4.6, 1.4, 4.6), conc_c, 0.0)

	# 4 vertical corner chords of the open-lattice crane mast (authentic silhouette against the sky!)
	var mw := 0.92
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_emit_box(crane_st, Vector3(pos.x + sx * mw, mast_h * 0.5, pos.y + sz * mw), Vector3(0.22, mast_h, 0.22), main_c, 0.0)
	# Horizontal lattice bracing rings every 3.4m up the mast
	var y := 2.8
	var ring_i := 0
	while y < mast_h - 0.5:
		var rc := main_c if (ring_i % 4 != 3) else accent_c
		_emit_box(crane_st, Vector3(pos.x, y, pos.y + mw), Vector3(mw * 2.0, 0.18, 0.16), rc, 0.0)
		_emit_box(crane_st, Vector3(pos.x, y, pos.y - mw), Vector3(mw * 2.0, 0.18, 0.16), rc, 0.0)
		_emit_box(crane_st, Vector3(pos.x + mw, y, pos.y), Vector3(0.16, 0.18, mw * 2.0), rc, 0.0)
		_emit_box(crane_st, Vector3(pos.x - mw, y, pos.y), Vector3(0.16, 0.18, mw * 2.0), rc, 0.0)
		y += 3.4
		ring_i += 1

	# Slewing ring & operator cabin
	var rot_y := -yaw
	var jdir := Vector2(cos(yaw), sin(yaw))
	var jside := Vector2(-jdir.y, jdir.x)
	var cab_p := pos + jdir * 1.4 + jside * 1.55
	_emit_box(struct_st, Vector3(cab_p.x, mast_h - 1.1, cab_p.y), Vector3(2.2, 2.5, 1.6), Color(0.92, 0.93, 0.94), rot_y)
	_emit_box(struct_st, Vector3(cab_p.x, mast_h - 0.9, cab_p.y), Vector3(2.3, 1.2, 1.65), Color(0.16, 0.24, 0.32), rot_y)

	# Upper tower apex spire (塔帽)
	var apex_h := 6.2
	_emit_box(crane_st, Vector3(pos.x, mast_h + apex_h * 0.5, pos.y), Vector3(1.15, apex_h, 1.15), main_c, rot_y)
	_emit_box(beacon_st, Vector3(pos.x, mast_h + apex_h + 0.45, pos.y), Vector3(0.55, 0.55, 0.55), Color(1.0, 0.18, 0.10), 0.0)

	# Long triangulated horizontal Jib Boom (臂架)
	var jib_c := pos + jdir * (jib_l * 0.5)
	_emit_box(crane_st, Vector3(jib_c.x, mast_h + 0.35, jib_c.y), Vector3(jib_l, 0.30, 1.45), main_c, rot_y)
	_emit_box(crane_st, Vector3(jib_c.x, mast_h + 1.85, jib_c.y), Vector3(jib_l, 0.26, 0.30), main_c, rot_y)
	# Periodic triangular truss struts along jib
	var s := 3.5
	while s < jib_l - 1.0:
		var sp := pos + jdir * s
		_emit_box(crane_st, Vector3(sp.x, mast_h + 1.1, sp.y), Vector3(0.20, 1.55, 1.35), accent_c if (int(s) % 7 < 3) else main_c, rot_y)
		s += 3.5

	# Counter-jib & concrete counterweight ballast blocks (平衡臂 + 配重块)
	var cj_l := 11.5
	var cj_c := pos - jdir * (cj_l * 0.5)
	_emit_box(crane_st, Vector3(cj_c.x, mast_h + 0.45, cj_c.y), Vector3(cj_l, 0.45, 1.55), main_c, rot_y)
	var bal_p := pos - jdir * (cj_l - 2.0)
	_emit_box(struct_st, Vector3(bal_p.x, mast_h + 1.55, bal_p.y), Vector3(3.4, 2.2, 2.0), conc_c, rot_y)

	# Steel stay cables from tower apex to jib & counter-jib
	var stay_f_p := pos + jdir * (jib_l * 0.38)
	var stay_f_len := hypot2(jib_l * 0.76, apex_h - 1.6)
	var stay_f_ang := atan2(apex_h - 1.6, jib_l * 0.76)
	_emit_box(crane_st, Vector3(stay_f_p.x, mast_h + 1.6 + (apex_h - 1.6) * 0.5, stay_f_p.y), Vector3(stay_f_len, 0.12, 0.12), steel_dk, rot_y, -stay_f_ang)
	var stay_b_p := pos - jdir * (cj_l * 0.44)
	var stay_b_len := hypot2(cj_l * 0.88, apex_h - 0.8)
	var stay_b_ang := atan2(apex_h - 0.8, cj_l * 0.88)
	_emit_box(crane_st, Vector3(stay_b_p.x, mast_h + 0.8 + (apex_h - 0.8) * 0.5, stay_b_p.y), Vector3(stay_b_len, 0.14, 0.14), steel_dk, rot_y, stay_b_ang)

	# Trolley & dangling lifting cable + yellow hook block
	var tr_p := pos + jdir * (jib_l * 0.62)
	_emit_box(crane_st, Vector3(tr_p.x, mast_h - 0.2, tr_p.y), Vector3(1.4, 0.6, 1.4), accent_c, rot_y)
	var drop_h := mast_h * 0.42
	_emit_box(crane_st, Vector3(tr_p.x, mast_h - 0.5 - drop_h * 0.5, tr_p.y), Vector3(0.08, drop_h, 0.08), steel_dk, 0.0)
	_emit_box(crane_st, Vector3(tr_p.x, mast_h - 0.5 - drop_h, tr_p.y), Vector3(0.85, 0.95, 0.55), Color(0.92, 0.70, 0.10), rot_y)


static func hypot2(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


static func _emit_prefab_barracks(st: SurfaceTool, pos: Vector2, rot_y: float) -> void:
	# 2-storey Chinese blue-and-white corrugated steel construction office (彩钢板活动板房)
	var wall_w := Color(0.90, 0.91, 0.92)
	var roof_b := Color(0.14, 0.36, 0.68)
	var win_c := Color(0.18, 0.28, 0.38)
	var stair_c := Color(0.32, 0.35, 0.38)
	_emit_box(st, Vector3(pos.x, 2.85, pos.y), Vector3(16.0, 5.7, 5.6), wall_w, rot_y)
	_emit_box(st, Vector3(pos.x, 5.88, pos.y), Vector3(16.8, 0.40, 6.4), roof_b, rot_y)
	# Blue horizontal floor belt & corner trim
	_emit_box(st, Vector3(pos.x, 2.85, pos.y), Vector3(16.12, 0.30, 5.72), roof_b, rot_y)
	# Row of small barracks windows on 1F & 2F
	var u := Vector2(cos(-rot_y), sin(-rot_y))
	var v := Vector2(-u.y, u.x)
	for fl: int in [0, 1]:
		var wy := 1.55 + float(fl) * 2.85
		for wi in range(5):
			var tu := lerpf(-6.2, 6.2, float(wi) / 4.0)
			for side: float in [-1.0, 1.0]:
				var wp := pos + u * tu + v * (side * 2.84)
				_emit_box(st, Vector3(wp.x, wy, wp.y), Vector3(1.35, 1.05, 0.10), win_c, rot_y)
	# Exterior metal walkway along 2F front
	var wk_p := pos + v * 3.35
	_emit_box(st, Vector3(wk_p.x, 2.85, wk_p.y), Vector3(15.6, 0.16, 1.1), stair_c, rot_y)
	_emit_box(st, Vector3(wk_p.x, 3.85, wk_p.y), Vector3(15.6, 0.12, 0.10), roof_b, rot_y)


static func _emit_excavator(crane_st: SurfaceTool, struct_st: SurfaceTool, pos: Vector2, rot_y: float) -> void:
	# Compact yellow tracked excavator (挖掘机)
	var yel := Color(0.92, 0.68, 0.08)
	var dk := Color(0.18, 0.19, 0.21)
	var u := Vector2(cos(-rot_y), sin(-rot_y))
	_emit_box(struct_st, Vector3(pos.x, 0.45, pos.y), Vector3(4.2, 0.90, 2.9), dk, rot_y) # tracks
	_emit_box(crane_st, Vector3(pos.x, 1.65, pos.y), Vector3(3.6, 1.45, 2.6), yel, rot_y) # body
	var cab := pos + u * 0.45
	_emit_box(struct_st, Vector3(cab.x, 2.55, cab.y), Vector3(1.5, 1.35, 1.1), Color(0.18, 0.26, 0.34), rot_y)
	var boom_p := pos + u * 3.4
	_emit_box(crane_st, Vector3(boom_p.x, 3.10, boom_p.y), Vector3(4.6, 0.55, 0.45), yel, rot_y, 0.52)
	var arm_p := pos + u * 5.7
	_emit_box(crane_st, Vector3(arm_p.x, 2.65, arm_p.y), Vector3(3.2, 0.40, 0.38), yel, rot_y, -1.05)


static func _emit_greenhouse_cluster(gh_st: SurfaceTool, struct_st: SurfaceTool, g: Dictionary, g_idx: int) -> void:
	# Neat parallel rows of arched Jiangnan white-film vegetable polytunnel greenhouses (蔬菜大棚)
	var cc: Array = g.get("c", [0.0, 0.0])
	var center := Vector2(float(cc[0]), float(cc[1]))
	var ang := float(g.get("a", 0.0))
	var n_rows := clampi(int(g.get("n", 4)), 2, 8)
	var gh_len := clampf(float(g.get("len", 34.0)), 18.0, 48.0)
	var u := Vector2(cos(ang), sin(ang))
	var v := Vector2(-u.y, u.x)
	var rot_y := -ang
	var spacing := 7.6
	var gw := 5.8
	var gh_h := 2.65
	var film_c := Color(0.84, 0.87, 0.86) if (g_idx % 2 == 0) else Color(0.80, 0.84, 0.84)
	var film_top := Color(0.90, 0.92, 0.91)
	var rib_c := Color(0.32, 0.36, 0.38)

	# 5-segment arched cross-section profile across local V (-gw/2 .. +gw/2)
	var prof: Array[Vector2] = [
		Vector2(-gw * 0.50, 0.0),
		Vector2(-gw * 0.46, gh_h * 0.52),
		Vector2(-gw * 0.25, gh_h * 0.90),
		Vector2(0.0, gh_h),
		Vector2(gw * 0.25, gh_h * 0.90),
		Vector2(gw * 0.46, gh_h * 0.52),
		Vector2(gw * 0.50, 0.0),
	]

	for ri in range(n_rows):
		var off_v := (float(ri) - float(n_rows - 1) * 0.5) * spacing
		var rc := center + v * off_v
		var p0 := rc - u * (gh_len * 0.5)
		var p1 := rc + u * (gh_len * 0.5)
		# Extrude curved polytunnel barrel skin along u
		for pi in range(prof.size() - 1):
			var a2: Vector2 = prof[pi]
			var b2: Vector2 = prof[pi + 1]
			var v00 := Vector3(p0.x + v.x * a2.x, a2.y, p0.y + v.y * a2.x)
			var v01 := Vector3(p0.x + v.x * b2.x, b2.y, p0.y + v.y * b2.x)
			var v10 := Vector3(p1.x + v.x * a2.x, a2.y, p1.y + v.y * a2.x)
			var v11 := Vector3(p1.x + v.x * b2.x, b2.y, p1.y + v.y * b2.x)
			var nrm := (v01 - v00).cross(v10 - v00).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			var sc := film_top if (pi == 2 or pi == 3) else film_c
			for tri_v: Vector3 in [v00, v10, v11, v00, v11, v01]:
				gh_st.set_color(sc)
				gh_st.set_normal(nrm)
				gh_st.add_vertex(tri_v)
		# End-caps + dark galvanized hoop ribs along the greenhouse
		for end_p: Vector2 in [p0, p1]:
			_emit_box(struct_st, Vector3(end_p.x, gh_h * 0.42, end_p.y), Vector3(0.14, gh_h * 0.84, gw * 0.90), Color(0.68, 0.72, 0.72), rot_y)
		var n_ribs := clampi(int(round(gh_len / 6.0)), 3, 8)
		for rk in range(n_ribs):
			var tr := lerpf(-gh_len * 0.46, gh_len * 0.46, float(rk) / float(n_ribs - 1))
			var rp := rc + u * tr
			_emit_box(struct_st, Vector3(rp.x, gh_h + 0.02, rp.y), Vector3(0.10, 0.08, gw * 0.62), rib_c, rot_y)
