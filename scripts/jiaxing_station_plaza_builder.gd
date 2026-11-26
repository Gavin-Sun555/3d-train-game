class_name JiaxingStationPlazaBuilder
extends RefCounted

# 1:1 ArchDaily / MAD Architects modeling of 嘉兴火车站 & 南广场 ("森林中的火车站 · 漂浮在大地之上的翠环")
# Reference: https://www.archdaily.com/zh/1013479/jia-xing-huo-che-zhan-mad-architects
# Built natively in JiaxingForestRailwayStation local space (X = NE along tracks, Z = SE into South Plaza):
#   1. Chamfered-trapezoid rounded-corner floating dark solar Waiting Lobbies with crisp white aluminum
#      aerodynamic halos, 3 recessed oval/rounded-square skylights, and 360° recessed clear glass curtain walls.
#   2. True continuous 3D sculpted green-hill terrain mesh (连绵起伏的绿丘, rising 5.5–7.5m high) wrapping
#      the flat open 1-hectare Central Lawn (中心大草坪) and carving the symmetrical Central Subway Promenade.
#   3. Landmark 38m-tall Ovoid / Egg-Shaped Glass Dome Tower (蛋形玻璃幕墙地标塔楼) at the NE track corner
#      with horizontal luminous white floor spandrel rings, curved vertical steel mullions, gridded glass dome
#      crown, and cantilevered circular glazed podium.
#   4. 7 Floating "Emerald Ring" & Organic Green-Roof Cultural/Commercial Pavilions perched on the green hills:
#        - East cluster (yellow-green sedum roofs): E1, E2 (2-tier cantilevered), E3 (inner oval), E4 (axis east)
#        - West cluster (deep-emerald roofs): W1 (axis west), W2 (seamless Figure-8/peanut pavilion), W3 (canal),
#          plus W4 far-SW sculpted hill & sunken oval courtyard.
#      Each pavilion has a cantilevered dark charcoal floating floor plate & soffit, razor-thin white/silver
#      beveled saucer roof rim, crystal-clear recessed curved glass curtain wall, and sunlit courtyard oculus.
#   5. Sweeping elevated curved white-ribbon walkways & hill ramps with stainless-glass balustrades,
#      pillared dark-ceiling undercrofts, central subway axial terraced ovals & twin white arch stair portals,
#      curved sunken lightwell, and curated woodland groves.


# ---------------------------------------------------------------------------------------------
# Continuous 3D Terrain Heightfield for the Entire South Plaza Triangle
# ---------------------------------------------------------------------------------------------
const HILL_DEFS: Array = [
	# [lx, lz, rx, rz, height, yaw]
	# East hill ridge supporting Egg Podium & Yellow-Green Sedum Rings (E1–E4)
	[184.0, 74.0, 40.0, 34.0, 4.2, 0.25],
	[148.0, 108.0, 44.0, 38.0, 6.4, 0.35],
	[128.0, 162.0, 42.0, 38.0, 7.2, 0.15],
	[80.0, 156.0, 32.0, 28.0, 5.8, -0.20],
	[66.0, 208.0, 44.0, 40.0, 7.4, 0.10],
	[52.0, 248.0, 36.0, 30.0, 5.2, 0.20],
	# West / Canal hill ridge supporting Deep-Emerald Rings & Figure-8 Pavilion (W1–W4)
	[-36.0, 206.0, 46.0, 40.0, 7.2, -0.10],
	[-30.0, 248.0, 34.0, 28.0, 4.9, -0.20],
	[-74.0, 162.0, 38.0, 32.0, 6.0, 0.48],
	[-114.0, 134.0, 44.0, 38.0, 6.4, -0.25],
	[-166.0, 92.0, 40.0, 32.0, 5.2, -0.35],
]


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(0.0001, edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _site_sdf(lx: float, lz: float) -> float:
	# Signed distance inside the South Plaza triangle (negative = inside, positive = outside)
	# Boundaries cleanly inside tracks (lz >= 26), 东方路 (lx+lz <= 326), 环城河 (lz-lx <= 306)
	var d_north := 26.0 - lz
	var d_east := (lx + lz - 324.0) * 0.7071
	var d_west := (lz - lx - 304.0) * 0.7071
	return maxf(d_north, maxf(d_east, d_west))


static func _hill_height(lx: float, lz: float) -> float:
	# Smooth sculpted 3D landscape elevation (m) at any (lx, lz) in South Plaza!
	var edge_d := -_site_sdf(lx, lz) # positive inside site
	if edge_d <= 0.0:
		return 0.06
	# Taper smoothly down to street/canal/track grade over outer 14m margin
	var border_mask := _smoothstep(2.0, 18.0, edge_d)

	# Keep the 1-hectare Central Lawn directly in front of the South Waiting Lobby crisp and flat!
	# Elliptical-trapezoid flat meadow centered at (lx=18, lz=112)
	var cl_dx := (lx - 18.0) / 76.0
	var cl_dz := (lz - 110.0) / 48.0
	var cl_r := sqrt(cl_dx * cl_dx + cl_dz * cl_dz)
	var lawn_mask := _smoothstep(0.76, 1.18, cl_r)

	# Carve the symmetrical Central Axial Subway Promenade valley along lx = 14, lz = 148..315!
	var axis_w := 17.0 + 7.0 * _smoothstep(160.0, 235.0, lz) * (1.0 - _smoothstep(235.0, 295.0, lz))
	var axis_carve := 1.0
	if lz > 142.0:
		var ax_d := absf(lx - 14.0)
		axis_carve = _smoothstep(axis_w * 0.45, axis_w * 1.45, ax_d)

	# Keep the South Waiting Lobby apron (lz < 76, lx in [-68..+106]) flat at plaza level
	var lobby_dx := maxf(0.0, absf(lx - 20.0) - 74.0)
	var lobby_dz := maxf(0.0, lz - 74.0)
	var lobby_d := sqrt(lobby_dx * lobby_dx + lobby_dz * lobby_dz)
	var lobby_mask := _smoothstep(4.0, 20.0, lobby_d)

	# Smoothly blend all hill masses (soft-max / smooth union so ridges merge organically!)
	var h := 0.0
	for hd in HILL_DEFS:
		var dx := lx - float(hd[0])
		var dz := lz - float(hd[1])
		var yaw := float(hd[5])
		var ca := cos(yaw)
		var sa := sin(yaw)
		var rx_d := (dx * ca - dz * sa) / float(hd[2])
		var rz_d := (dx * sa + dz * ca) / float(hd[3])
		var d2 := rx_d * rx_d + rz_d * rz_d
		if d2 < 2.2:
			var contrib := float(hd[4]) * exp(-d2 * 1.65)
			h = maxf(h, contrib) + minf(h, contrib) * 0.22

	# Carve crisp open circular sunken courtyards inside the major ring pavilions so courtyards sit low!
	var oculus_cuts: Array = [
		[148.0, 104.0, 10.5],
		[128.0, 162.0, 8.5],
		[64.0, 208.0, 9.6],
		[-36.0, 206.0, 11.4],
		[-114.0, 134.0, 11.2],
		[-166.0, 92.0, 10.0],
	]
	var court_mask := 1.0
	for oc in oculus_cuts:
		var od := Vector2(lx - float(oc[0]), lz - float(oc[1])).length()
		var orad := float(oc[2])
		if od < orad + 6.0:
			court_mask = minf(court_mask, 0.28 + 0.72 * _smoothstep(orad * 0.75, orad + 5.0, od))

	return 0.12 + h * border_mask * lawn_mask * axis_carve * lobby_mask * court_mask


# ---------------------------------------------------------------------------------------------
# Mesh Helpers
# ---------------------------------------------------------------------------------------------
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, force_up: bool = false) -> void:
	var n := Vector3.UP if force_up else (b - a).cross(c - a).normalized()
	if n.length_squared() < 1e-6:
		n = Vector3.UP
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, force_up: bool = false) -> void:
	_tri(st, a, b, c, col, force_up)
	_tri(st, a, c, d, col, force_up)


static func _emit_box(st: SurfaceTool, pos: Vector3, sz: Vector3, col: Color, rot_y: float = 0.0, rot_z: float = 0.0, rot_x: float = 0.0) -> void:
	var b := Basis.from_euler(Vector3(rot_x, rot_y, rot_z))
	RoadSignBuilder._box(st, Transform3D(b, pos), sz, col)


static func _emit_cyl_v(st: SurfaceTool, base: Vector3, r_bot: float, r_top: float, h: float, col: Color, segs: int = 10) -> void:
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var b0 := base + Vector3(c0 * r_bot, 0.0, s0 * r_bot)
		var b1 := base + Vector3(c1 * r_bot, 0.0, s1 * r_bot)
		var t0 := base + Vector3(c0 * r_top, h, s0 * r_top)
		var t1 := base + Vector3(c1 * r_top, h, s1 * r_top)
		_quad(st, b0, b1, t1, t0, col)


static func _commit_vc(parent: Node3D, node_name: String, st: SurfaceTool, rough: float = 0.55, metal: float = 0.08, shadow: bool = true) -> void:
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
	mat.metallic_specular = 0.34
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _commit_glass(parent: Node3D, node_name: String, st: SurfaceTool, alpha: float = 0.54) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.06
	mat.metallic = 0.52
	mat.metallic_specular = 0.88
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	parent.add_child(mi)


static func _commit_emissive(parent: Node3D, node_name: String, st: SurfaceTool, energy: float = 1.05) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.92, 0.74)
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ---------------------------------------------------------------------------------------------
# 1. Chamfered-Trapezoid Rounded-Corner Floating Solar Waiting Lobby (North & South!)
# ---------------------------------------------------------------------------------------------
static func _rounded_trapezoid_pts(half_w_track: float, half_w_plaza: float, half_d: float, r_corner: float, flip_z: bool) -> Array[Vector2]:
	# 4 trapezoid corners (track edge at z = -half_d for South lobby, +half_d for North lobby)
	var sgn := -1.0 if flip_z else 1.0
	var corners: Array[Vector2] = [
		Vector2(-half_w_track, -sgn * half_d),
		Vector2(half_w_track, -sgn * half_d),
		Vector2(half_w_plaza, sgn * half_d),
		Vector2(-half_w_plaza, sgn * half_d),
	]
	if flip_z:
		corners.reverse()
	var pts: Array[Vector2] = []
	var arc_steps := 7
	for ci in range(4):
		var p_prev := corners[(ci + 3) % 4]
		var p_curr := corners[ci]
		var p_next := corners[(ci + 1) % 4]
		var d_in := (p_curr - p_prev).normalized()
		var d_out := (p_next - p_curr).normalized()
		var p_start := p_curr - d_in * r_corner
		var p_end := p_curr + d_out * r_corner
		for s in range(arc_steps + 1):
			var t := float(s) / float(arc_steps)
			# Quadratic Bezier fillet for silky smooth aerodynamic MAD corners
			var omt := 1.0 - t
			var q := p_start * (omt * omt) + p_curr * (2.0 * omt * t) + p_end * (t * t)
			pts.append(q)
	return pts


static func build_waiting_lobby(parent: Node3D, center: Vector2, len_track: float, len_plaza: float, depth: float, is_north: bool) -> void:
	# Authentic MAD Floating Solar Pavilion (ArchDaily #1, #5, #6, #34):
	#   - Chamfered trapezoid plan with rounded aerodynamic corners
	#   - Crisp silver-white aluminum cantilevered halo rim
	#   - Gently arched dark photovoltaic solar roof panel deck
	#   - 3 signature recessed skylights (1 rounded-square center + 2 elongated flanking pill ovals)
	#   - 360° recessed clear structural glass curtain wall & minimalist luminous white honeycomb interior
	var root := Node3D.new()
	root.name = "WaitingLobbyNorth" if is_north else "WaitingLobbySouth"
	root.position = Vector3(center.x, 0.0, center.y)
	parent.add_child(root)

	var white_st := SurfaceTool.new()
	white_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var solar_st := SurfaceTool.new()
	solar_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass_st := SurfaceTool.new()
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var outer := _rounded_trapezoid_pts(len_track * 0.5, len_plaza * 0.5, depth * 0.5, 9.5, is_north)
	var inner := _rounded_trapezoid_pts(len_track * 0.5 - 2.6, len_plaza * 0.5 - 2.6, depth * 0.5 - 2.4, 7.6, is_north)
	var glass_ring := _rounded_trapezoid_pts(len_track * 0.5 - 5.2, len_plaza * 0.5 - 5.2, depth * 0.5 - 4.8, 6.2, is_north)

	var h_eave := 7.1
	var h_soffit := 6.55
	var h_crown := 8.15
	var col_white := Color(0.95, 0.96, 0.97)
	var col_soffit := Color(0.88, 0.89, 0.91)
	var col_solar := Color(0.14, 0.18, 0.24)
	var col_solar_hi := Color(0.18, 0.23, 0.30)
	var col_glass := Color(0.42, 0.58, 0.68)
	var col_glow := Color(1.0, 0.94, 0.80)
	var n := outer.size()

	for i in range(n):
		var ni := (i + 1) % n
		var o0 := outer[i]
		var o1 := outer[ni]
		var r0 := inner[i]
		var r1 := inner[ni]
		var g0 := glass_ring[i]
		var g1 := glass_ring[ni]

		# Knife-edge silver-white aluminum fascia band around perimeter
		_quad(white_st,
			Vector3(o0.x, h_soffit + 0.16, o0.y), Vector3(o1.x, h_soffit + 0.16, o1.y),
			Vector3(o1.x, h_eave, o1.y), Vector3(o0.x, h_eave, o0.y), col_white)
		# Crisp white top halo lip sloping gently into solar deck
		_quad(white_st,
			Vector3(o0.x, h_eave, o0.y), Vector3(o1.x, h_eave, o1.y),
			Vector3(r1.x, h_eave + 0.35, r1.y), Vector3(r0.x, h_eave + 0.35, r0.y), col_white, true)
		# Bright anodized honeycomb-aluminum soffit underneath cantilever
		_quad(white_st,
			Vector3(g0.x, h_soffit, g0.y), Vector3(g1.x, h_soffit, g1.y),
			Vector3(o1.x, h_soffit + 0.16, o1.y), Vector3(o0.x, h_soffit + 0.16, o0.y), col_soffit)
		# Gently arched dark photovoltaic solar roof converging to central ridge
		var c_mid0 := Vector2(clampf(r0.x, -len_plaza * 0.28, len_plaza * 0.28), 0.0)
		var c_mid1 := Vector2(clampf(r1.x, -len_plaza * 0.28, len_plaza * 0.28), 0.0)
		_quad(solar_st,
			Vector3(r0.x, h_eave + 0.35, r0.y), Vector3(r1.x, h_eave + 0.35, r1.y),
			Vector3(c_mid1.x, h_crown, c_mid1.y), Vector3(c_mid0.x, h_crown, c_mid0.y),
			col_solar if (i % 2 == 0) else col_solar_hi)
		# 360° clear structural glass curtain wall & minimalist luminous interior core
		_quad(glass_st,
			Vector3(g0.x, 0.08, g0.y), Vector3(g1.x, 0.08, g1.y),
			Vector3(g1.x, h_soffit, g1.y), Vector3(g0.x, h_soffit, g0.y), col_glass)
		var ig0 := g0 * 0.90
		var ig1 := g1 * 0.90
		_quad(glow_st,
			Vector3(ig0.x, 0.3, ig0.y), Vector3(ig1.x, 0.3, ig1.y),
			Vector3(ig1.x, h_soffit - 0.5, ig1.y), Vector3(ig0.x, h_soffit - 0.5, ig0.y), col_glow)
		# Slender vertical steel mullions
		if i % 2 == 0:
			_emit_box(solar_st, Vector3(g0.x, h_soffit * 0.5, g0.y), Vector3(0.18, h_soffit, 0.18), Color(0.24, 0.27, 0.31))

	# 3 Signature Recessed Skylights (ArchDaily #1, #5, #34): 1 central rounded square + 2 elongated ovals!
	_emit_skylight(white_st, glow_st, Vector2(0.0, 0.0), 6.2, 5.2, h_crown + 0.08)
	_emit_skylight(white_st, glow_st, Vector2(-31.0, 0.0), 11.5, 2.5, h_crown + 0.04)
	_emit_skylight(white_st, glow_st, Vector2(31.0, 0.0), 11.5, 2.5, h_crown + 0.04)

	_commit_vc(root, "LobbyWhiteHalo", white_st, 0.34, 0.22, true)
	_commit_vc(root, "LobbySolarRoof", solar_st, 0.26, 0.58, true)
	_commit_glass(root, "LobbyCurtainGlass", glass_st, 0.48)
	_commit_emissive(root, "LobbyWarmInterior", glow_st, 0.92)


static func _emit_skylight(white_st: SurfaceTool, glow_st: SurfaceTool, pos: Vector2, rx: float, rz: float, y_top: float) -> void:
	var segs := 20
	var rim_col := Color(0.86, 0.88, 0.90)
	var sky_col := Color(0.95, 0.92, 0.78)
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var p0 := pos + Vector2(cos(a0) * rx, sin(a0) * rz)
		var p1 := pos + Vector2(cos(a1) * rx, sin(a1) * rz)
		var q0 := pos + Vector2(cos(a0) * (rx + 0.9), sin(a0) * (rz + 0.9))
		var q1 := pos + Vector2(cos(a1) * (rx + 0.9), sin(a1) * (rz + 0.9))
		_quad(white_st, Vector3(q0.x, y_top - 0.12, q0.y), Vector3(q1.x, y_top - 0.12, q1.y),
			Vector3(p1.x, y_top + 0.16, p1.y), Vector3(p0.x, y_top + 0.16, p0.y), rim_col, true)
		_tri(glow_st, Vector3(pos.x, y_top + 0.14, pos.y),
			Vector3(p0.x, y_top + 0.14, p0.y), Vector3(p1.x, y_top + 0.14, p1.y), sky_col, true)


# ---------------------------------------------------------------------------------------------
# 2. Main South Plaza Builder (Called natively in JiaxingForestRailwayStation local space!)
# ---------------------------------------------------------------------------------------------
static func build(jx_station_node: Node3D, _lights: Array) -> void:
	var root := Node3D.new()
	root.name = "JiaxingStationSouthPlazaMAD"
	jx_station_node.add_child(root)

	var hill_st := SurfaceTool.new()
	hill_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plaza_st := SurfaceTool.new()
	plaza_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white_st := SurfaceTool.new()
	white_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof_green_st := SurfaceTool.new()
	roof_green_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark_st := SurfaceTool.new()
	dark_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass_st := SurfaceTool.new()
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow_st := SurfaceTool.new()
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- A. Continuous 3D Sculpted South Plaza Green Hill Terrain + Flat 1-Hectare Central Lawn ---
	_emit_sculpted_terrain(hill_st, plaza_st)

	# --- B. Sweeping Pale-Granite Central Lawn Rim, Axial Subway Promenade & Twin White Arch Portals ---
	_emit_central_axis_and_paths(plaza_st, white_st, dark_st, glass_st)

	# --- C. Landmark 38m Ovoid / Egg-Shaped Glass Dome Tower (NE corner next to tracks & 东方路) ---
	# Exact match to ArchDaily #1, #6, #7, #8, #10!
	_emit_ovoid_glass_tower(white_st, dark_st, glass_st, glow_st, roof_green_st, Vector2(194.0, 64.0), 3.4)

	# --- D. East Cluster — 4 Floating Yellow-Green Sedum "Emerald Rings" perched on the sculpted hills! ---
	var sedum_top := Color(0.41, 0.53, 0.14)
	var sedum_mid := Color(0.34, 0.46, 0.12)
	# E1: Large yellow-green circular ring SW of the Egg Tower
	_emit_floating_ring(white_st, roof_green_st, dark_st, glass_st, glow_st, plaza_st,
		Vector2(148.0, 104.0), 26.5, 10.6, 5.6, 4.7, sedum_top, sedum_mid, false)
	# E2: Iconic 2-tier cantilevered ring along 东方路 (ArchDaily #9 — floating lower terrace + upper glass ring!)
	_emit_floating_ring(white_st, roof_green_st, dark_st, glass_st, glow_st, plaza_st,
		Vector2(128.0, 162.0), 21.5, 8.4, 6.2, 4.6, sedum_top, sedum_mid, true)
	# E3: Compact inner yellow-green oval pavilion tucked on the slope facing the Central Lawn
	_emit_floating_oval_pavilion(white_st, roof_green_st, dark_st, glass_st, glow_st,
		Vector2(78.0, 154.0), 15.2, 12.6, 5.4, 4.2, -0.22, sedum_top)
	# E4: Large yellow-green ring flanking the East side of the Central Subway Axis
	_emit_floating_ring(white_st, roof_green_st, dark_st, glass_st, glow_st, plaza_st,
		Vector2(64.0, 208.0), 24.5, 9.6, 6.6, 4.8, sedum_top, sedum_mid, true)

	# --- E. West / Waterfront Cluster — Deep-Emerald Rings + Seamless Figure-8/Peanut Pavilion! ---
	var emerald_top := Color(0.16, 0.41, 0.14)
	var emerald_mid := Color(0.13, 0.35, 0.12)
	# W1: Large deep-emerald circular ring flanking the West side of the Central Subway Axis
	_emit_floating_ring(white_st, roof_green_st, dark_st, glass_st, glow_st, plaza_st,
		Vector2(-36.0, 206.0), 26.0, 11.4, 6.4, 4.8, emerald_top, emerald_mid, true)
	# W2: Seamless organic Figure-8 / Peanut twin-lobed green-roof pavilion bridging W1 and W3 (ArchDaily #1!)
	_emit_figure8_pavilion(white_st, roof_green_st, dark_st, glass_st, glow_st,
		Vector2(-74.0, 162.0), 0.72, 5.3, 4.4, emerald_top)
	# W3: Large deep-emerald circular ring commanding the SW canal waterfront
	_emit_floating_ring(white_st, roof_green_st, dark_st, glass_st, glow_st, plaza_st,
		Vector2(-114.0, 134.0), 26.5, 11.2, 5.6, 4.7, emerald_top, emerald_mid, false)
	# W4: Far-SW sculpted hill sunken oval courtyard & white sculptural loop rim (ArchDaily #1 far right!)
	_emit_sunken_oval_court(white_st, plaza_st, dark_st, Vector2(-166.0, 92.0), 12.0, 8.5, -0.35)

	# --- F. Sweeping Curved White-Ribbon Elevated Hill Walkways, Ramps & Pillared Undercrofts (ArchDaily #2,#8,#9) ---
	_emit_curved_hill_walkways(white_st, plaza_st, dark_st, glass_st)

	# --- G. Curated "Forest Station" Woodland Trees (Open Central Lawn + Lush Hillfoot & Courtyard Groves!) ---
	_plant_south_plaza_trees(root)

	# Commit all batched meshes cleanly
	_commit_vc(root, "SouthPlazaSculptedHills", hill_st, 0.88, 0.0, true)
	_commit_vc(root, "SouthPlazaGraniteWalks", plaza_st, 0.76, 0.03, false)
	_commit_vc(root, "SouthPlazaGreenRoofs", roof_green_st, 0.86, 0.0, true)
	_commit_vc(root, "SouthPlazaWhiteArchitecture", white_st, 0.32, 0.22, true)
	_commit_vc(root, "SouthPlazaDarkMetal", dark_st, 0.34, 0.56, true)
	_commit_glass(root, "SouthPlazaCurtainGlass", glass_st, 0.66)
	_commit_emissive(root, "SouthPlazaWarmGlow", glow_st, 0.90)


# ---------------------------------------------------------------------------------------------
# 3. Continuous 3D Sculpted Green-Hill Terrain Mesh in Rotated (u, v) Triangle Coordinates!
#    u = lx + lz (parallel to 东方路!), v = lz - lx (parallel to 环城河!) -> ZERO SAWTOOTH EDGES!
# ---------------------------------------------------------------------------------------------
static func _emit_sculpted_terrain(hill_st: SurfaceTool, plaza_st: SurfaceTool) -> void:
	# Pale granite perimeter sidewalk apron directly inside the triangle
	var apron := PackedVector2Array([
		Vector2(-276.0, 26.0),
		Vector2(296.0, 26.0),
		Vector2(10.0, 312.0),
	])
	var a_idx := Geometry2D.triangulate_polygon(apron)
	for k in range(0, a_idx.size(), 3):
		_tri(plaza_st,
			Vector3(apron[a_idx[k]].x, 0.04, apron[a_idx[k]].y),
			Vector3(apron[a_idx[k + 1]].x, 0.04, apron[a_idx[k + 1]].y),
			Vector3(apron[a_idx[k + 2]].x, 0.04, apron[a_idx[k + 2]].y),
			Color(0.84, 0.84, 0.81), true)

	# Parameterize the exact 45-45-90 triangle in (u, v) where:
	#   u <= U_MAX (318.0 -> razor-straight parallel to 东方路!)
	#   v <= V_MAX (298.0 -> razor-straight parallel to 环城河!)
	#   u + v >= UV_MIN (56.0 -> razor-straight along lz = 28.0!)
	# Using barycentric triangular mesh over (u, v) guarantees 100% razor-straight edges on ALL 3 sides!
	var u_max := 318.0
	var v_max := 298.0
	var uv_min := 56.0
	var span := (u_max + v_max) - uv_min # total hypotenuse span in (u,v)
	var n_div := 64 # smooth ~5.5m resolution across the entire South Plaza!

	var col_lawn := Color(0.24, 0.49, 0.19)
	var col_hill_hi := Color(0.36, 0.61, 0.21)
	var col_hill_deep := Color(0.16, 0.37, 0.13)
	var col_pave_axis := Color(0.85, 0.85, 0.82)

	# Grid indexed by (ia, ib) with ia >= 0, ib >= 0, ia + ib <= n_div:
	#   u = u_max - span * (ia / n_div)
	#   v = v_max - span * (ib / n_div)
	# Notice: ia=0 -> u=u_max (东方路), ib=0 -> v=v_max (环城河), ia+ib=n_div -> u+v=uv_min (tracks)!
	var grid_pts: Array = []
	grid_pts.resize(n_div + 1)
	for ia in range(n_div + 1):
		var row: Array[Vector3] = []
		row.resize(n_div + 1 - ia)
		var u := u_max - span * (float(ia) / float(n_div))
		for ib in range(n_div + 1 - ia):
			var v := v_max - span * (float(ib) / float(n_div))
			var lx := (u - v) * 0.5
			var lz := (u + v) * 0.5
			var h := _hill_height(lx, lz)
			row[ib] = Vector3(lx, h, lz)
		grid_pts[ia] = row

	for ia in range(n_div):
		var row0: Array[Vector3] = grid_pts[ia]
		var row1: Array[Vector3] = grid_pts[ia + 1]
		var max_ib := n_div - ia
		for ib in range(max_ib):
			# Lower triangle: (ia, ib), (ia+1, ib), (ia, ib+1)
			var p0 := row0[ib]
			var p1 := row1[ib]
			var p2 := row0[ib + 1]
			_emit_terrain_tri(hill_st, p0, p1, p2, col_lawn, col_hill_hi, col_hill_deep, col_pave_axis)
			# Upper triangle (when inside triangle): (ia+1, ib), (ia+1, ib+1), (ia, ib+1)
			if ib < max_ib - 1:
				var p3 := row1[ib + 1]
				_emit_terrain_tri(hill_st, p1, p3, p2, col_lawn, col_hill_hi, col_hill_deep, col_pave_axis)


static func _emit_terrain_tri(
	hill_st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	col_lawn: Color,
	col_hill_hi: Color,
	col_hill_deep: Color,
	col_pave_axis: Color
) -> void:
	var cx := (a.x + b.x + c.x) / 3.0
	var cz := (a.z + b.z + c.z) / 3.0
	# Cut out the circular sunken lightwell at (88, 114) so real sunken atrium floor shows!
	if Vector2(cx - 88.0, cz - 114.0).length() < 11.2:
		return
	var h_avg := (a.y + b.y + c.y) / 3.0
	var t_h := clampf((h_avg - 0.18) / 6.0, 0.0, 1.0)
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var sun_lit := clampf(n.dot(Vector3(0.38, 0.84, 0.38)), 0.0, 1.0)
	var col := col_lawn.lerp(col_hill_hi, t_h * 0.78)
	col = col_hill_deep.lerp(col, 0.36 + 0.64 * sun_lit)
	if cz > 160.0 and absf(cx - 14.0) < 7.2 and h_avg < 0.35:
		col = col_pave_axis
	_tri(hill_st, a, b, c, col)


# ---------------------------------------------------------------------------------------------
# 4. Landmark 38m Ovoid / Egg-Shaped Glass Dome Tower (ArchDaily #1, #6, #7, #8, #10!)
# ---------------------------------------------------------------------------------------------
static func _emit_ovoid_glass_tower(
	white_st: SurfaceTool,
	dark_st: SurfaceTool,
	glass_st: SurfaceTool,
	glow_st: SurfaceTool,
	roof_green_st: SurfaceTool,
	center: Vector2,
	y_base: float
) -> void:
	var segs := 32
	var white_col := Color(0.95, 0.96, 0.97)
	var silver_trim := Color(0.82, 0.85, 0.89)
	var dark_soffit := Color(0.16, 0.18, 0.21)
	var mull_col := Color(0.24, 0.28, 0.33)
	var glass_sky := Color(0.42, 0.58, 0.70)
	var glow_warm := Color(1.0, 0.92, 0.76)

	# --- 1. Circular Sculpted Glazed Podium with Sweeping Silver-White Umbrella Roof Canopy (ArchDaily #8/#10) ---
	var r_pod_out := 26.5
	var r_pod_glass := 22.8
	var y_pod_eave := y_base + 5.4
	var y_pod_inner := y_base + 7.2
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var o0 := center + d0 * r_pod_out
		var o1 := center + d1 * r_pod_out
		var g0 := center + d0 * r_pod_glass
		var g1 := center + d1 * r_pod_glass
		var t0 := center + d0 * 16.5
		var t1 := center + d1 * 16.5
		# Dark floating base ring
		_quad(dark_st, Vector3(g0.x, y_base - 0.6, g0.y), Vector3(g1.x, y_base - 0.6, g1.y),
			Vector3(g1.x, y_base, g1.y), Vector3(g0.x, y_base, g0.y), dark_soffit)
		# Clear podium curtain glass + glowing interior
		_quad(glass_st, Vector3(g0.x, y_base, g0.y), Vector3(g1.x, y_base, g1.y),
			Vector3(g1.x, y_pod_eave - 0.3, g1.y), Vector3(g0.x, y_pod_eave - 0.3, g0.y), glass_sky)
		var ig0 := center + d0 * (r_pod_glass - 1.2)
		var ig1 := center + d1 * (r_pod_glass - 1.2)
		_quad(glow_st, Vector3(ig0.x, y_base + 0.4, ig0.y), Vector3(ig1.x, y_base + 0.4, ig1.y),
			Vector3(ig1.x, y_pod_eave - 0.7, ig1.y), Vector3(ig0.x, y_pod_eave - 0.7, ig0.y), glow_warm)
		if i % 2 == 0:
			_emit_box(dark_st, Vector3(g0.x, y_base + 2.6, g0.y), Vector3(0.16, 5.2, 0.16), mull_col)
		# Dark cantilevered podium soffit
		_quad(dark_st, Vector3(g0.x, y_pod_eave - 0.3, g0.y), Vector3(g1.x, y_pod_eave - 0.3, g1.y),
			Vector3(o1.x, y_pod_eave - 0.2, o1.y), Vector3(o0.x, y_pod_eave - 0.2, o0.y), dark_soffit)
		# Razor-thin white outer rim + silver-white sloped aerodynamic umbrella roof
		_quad(white_st, Vector3(o0.x, y_pod_eave - 0.2, o0.y), Vector3(o1.x, y_pod_eave - 0.2, o1.y),
			Vector3(o1.x, y_pod_eave + 0.22, o1.y), Vector3(o0.x, y_pod_eave + 0.22, o0.y), white_col)
		_quad(white_st, Vector3(o0.x, y_pod_eave + 0.22, o0.y), Vector3(o1.x, y_pod_eave + 0.22, o1.y),
			Vector3(t1.x, y_pod_inner, t1.y), Vector3(t0.x, y_pod_inner, t0.y), silver_trim, true)
		# Small green roof terrace skirt tucked on the hillward side
		if sin(a0) > 0.25:
			var gr0 := center + d0 * (r_pod_out - 2.4)
			var gr1 := center + d1 * (r_pod_out - 2.4)
			_quad(roof_green_st, Vector3(gr0.x, y_pod_eave + 0.55, gr0.y), Vector3(gr1.x, y_pod_eave + 0.55, gr1.y),
				Vector3(t1.x, y_pod_inner + 0.15, t1.y), Vector3(t0.x, y_pod_inner + 0.15, t0.y), Color(0.50, 0.64, 0.24), true)

	# --- 2. Parametric 9-Story Egg / Ovoid Curved Glass Dome Tower (y = y_pod_inner .. y_pod_inner + 32.5m!) ---
	# Profile: subtle outward swell to belly at t=0.34 (r=18.8m), then graceful curve into gridded glass dome cap!
	var y0 := y_pod_inner - 0.4
	var tower_h := 32.5
	var n_lat := 18
	var profile_r: Array[float] = []
	var profile_y: Array[float] = []
	for li in range(n_lat + 1):
		var t := float(li) / float(n_lat)
		# Smooth egg profile matching ArchDaily #8 and #10!
		var ang_lat := lerpf(-0.34, PI * 0.48, t)
		var r_here := 18.6 * cos(ang_lat)
		if t > 0.72:
			# Soft dome crown flattening slightly at top
			var td := (t - 0.72) / 0.28
			r_here = lerpf(r_here, 18.6 * cos(ang_lat) * (1.0 - 0.18 * td), td)
		var y_here := y0 + tower_h * sin(t * PI * 0.5)
		profile_r.append(maxf(2.4, r_here))
		profile_y.append(y_here)

	# Solid architectural interior core cylinder + real concrete floor discs inside the glass Egg Tower
	# (Eliminates "hollow birdcage" transparency — matches ArchDaily #8 & #10 realistic interior floor depth!)
	var core_col := Color(0.56, 0.60, 0.65)
	var slab_col := Color(0.76, 0.78, 0.80)
	_emit_cyl_v(white_st, Vector3(center.x, y0, center.y), 10.6, 8.2, tower_h * 0.86, core_col, 24)
	for li in range(1, n_lat - 1, 2):
		var fl_r := profile_r[li] * 0.91
		var fl_y := profile_y[li]
		for i in range(segs):
			var a0 := float(i) * TAU / float(segs)
			var a1 := float(i + 1) * TAU / float(segs)
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			var f0 := center + d0 * fl_r
			var f1 := center + d1 * fl_r
			_tri(white_st, Vector3(center.x, fl_y, center.y), Vector3(f0.x, fl_y, f0.y), Vector3(f1.x, fl_y, f1.y), slab_col, true)
			_quad(dark_st, Vector3(f0.x, fl_y - 0.42, f0.y), Vector3(f1.x, fl_y - 0.42, f1.y),
				Vector3(f1.x, fl_y, f1.y), Vector3(f0.x, fl_y, f0.y), Color(0.32, 0.36, 0.42))

	# Build smooth curved ovoid glass skin + horizontal luminous white spandrel rings + vertical structural ribs!
	for li in range(n_lat):
		var r_a := profile_r[li]
		var r_b := profile_r[li + 1]
		var y_a := profile_y[li]
		var y_b := profile_y[li + 1]
		var is_floor_ring := (li % 2 == 1) or (li >= n_lat - 4)
		for i in range(segs):
			var a0 := float(i) * TAU / float(segs)
			var a1 := float(i + 1) * TAU / float(segs)
			var c0 := cos(a0)
			var s0 := sin(a0)
			var c1 := cos(a1)
			var s1 := sin(a1)
			var p00 := Vector3(center.x + c0 * r_a, y_a, center.y + s0 * r_a)
			var p10 := Vector3(center.x + c1 * r_a, y_a, center.y + s1 * r_a)
			var p01 := Vector3(center.x + c0 * r_b, y_b, center.y + s0 * r_b)
			var p11 := Vector3(center.x + c1 * r_b, y_b, center.y + s1 * r_b)
			# Curved sky-reflective architectural glass panel (ArchDaily #8/#10 silver-blue specular skin)
			var gl_c := Color(0.38, 0.54, 0.68).lightened(0.10 if c0 > 0.0 else 0.0)
			_quad(glass_st, p00, p10, p11, p01, gl_c)

			# Horizontal silver-white spandrel / structural ring at each story & crown grid (ArchDaily #8/#10!)
			if is_floor_ring:
				var band_h := 0.58 if li < n_lat - 4 else 0.38
				var q00 := Vector3(center.x + c0 * (r_b + 0.14), y_b - band_h * 0.5, center.y + s0 * (r_b + 0.14))
				var q10 := Vector3(center.x + c1 * (r_b + 0.14), y_b - band_h * 0.5, center.y + s1 * (r_b + 0.14))
				var q01 := Vector3(center.x + c0 * (r_b + 0.14), y_b + band_h * 0.5, center.y + s0 * (r_b + 0.14))
				var q11 := Vector3(center.x + c1 * (r_b + 0.14), y_b + band_h * 0.5, center.y + s1 * (r_b + 0.14))
				_quad(white_st, q00, q10, q11, q01, silver_trim)
				# Warm illuminated office window ceiling band recessed inside the floor edge
				if li < n_lat - 3:
					var ir := r_b * 0.90
					var f0 := Vector3(center.x + c0 * ir, y_b - 0.16, center.y + s0 * ir)
					var f1 := Vector3(center.x + c1 * ir, y_b - 0.16, center.y + s1 * ir)
					var f2 := Vector3(center.x + c1 * ir, y_b + 0.22, center.y + s1 * ir)
					var f3 := Vector3(center.x + c0 * ir, y_b + 0.22, center.y + s0 * ir)
					_quad(glow_st, f0, f1, f2, f3, glow_warm)

			# Fine vertical curved structural steel mullions running continuously up to the dome crown!
			var v_dir := (p01 - p00)
			var v_len := v_dir.length()
			if v_len > 0.05:
				var side_v := Vector3(-s0, 0.0, c0) * (0.11 if (i % 2 == 0) else 0.06)
				var out_v := Vector3(c0, 0.0, s0) * 0.14
				_quad(white_st, p00 + out_v - side_v, p00 + out_v + side_v,
					p01 + out_v + side_v, p01 + out_v - side_v, Color(0.78, 0.82, 0.87))

	# Gridded glass oculus dome cap at very top
	var y_crown := profile_y[n_lat]
	var r_crown := profile_r[n_lat]
	var top_pt := Vector3(center.x, y_crown + 0.45, center.y)
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var c0 := Vector3(center.x + cos(a0) * r_crown, y_crown, center.y + sin(a0) * r_crown)
		var c1 := Vector3(center.x + cos(a1) * r_crown, y_crown, center.y + sin(a1) * r_crown)
		_tri(dark_st, top_pt, c0, c1, Color(0.32, 0.38, 0.45), true)


# ---------------------------------------------------------------------------------------------
# 5. Floating "Emerald Ring" Cultural/Commercial Pavilion (ArchDaily #1, #2, #8, #9, #10!)
# ---------------------------------------------------------------------------------------------
static func _emit_floating_ring(
	white_st: SurfaceTool,
	roof_green_st: SurfaceTool,
	dark_st: SurfaceTool,
	glass_st: SurfaceTool,
	glow_st: SurfaceTool,
	plaza_st: SurfaceTool,
	center: Vector2,
	r_out: float,
	r_in: float,
	y_base: float,
	h_glass: float,
	col_roof_top: Color,
	col_roof_inner: Color,
	has_lower_cantilever_deck: bool
) -> void:
	# Authentic MAD "Floating Emerald Ring" cross-section (ArchDaily #2, #9, #10):
	#   1. Cantilevered dark charcoal/black floating floor disc hovering over the lush green hill slope!
	#   2. Recessed 360° ultra-clear curved glass curtain wall with slender mullions (zero chunky outer pillars!)
	#   3. Dramatic dark charcoal metal soffit under wide overhanging saucer roof wing
	#   4. Razor-thin gleaming white/silver aluminum beveled roof rim framing a smooth uniform sedum/grass roof!
	#   5. Optional 2nd lower cantilevered white/dark curved terrace deck on steeper hill slopes (ArchDaily #9!)
	var segs := 36
	var white_rim := Color(0.96, 0.96, 0.95)
	var silver_bevel := Color(0.88, 0.90, 0.92)
	var dark_soffit := Color(0.15, 0.17, 0.20)
	var mull_col := Color(0.22, 0.25, 0.29)
	var glass_col := Color(0.40, 0.56, 0.66)
	var glow_col := Color(1.0, 0.93, 0.78)
	var court_stone := Color(0.84, 0.84, 0.81)

	var r_glass_out := r_out - 3.2
	var r_glass_in := r_in + 2.2
	var r_floor_out := r_out - 1.4
	var r_lip_out := r_out - 2.1
	var r_lip_in := r_in + 1.6
	var y_eave := y_base + h_glass
	var y_roof := y_eave + 0.58

	# Optional lower 1F cantilevered terrace/undercroft level for 2-story hillside rings (ArchDaily #9!)
	if has_lower_cantilever_deck:
		var y_low_top := y_base - 0.55
		var y_low_bot := maxf(0.12, y_base - 4.2)
		var r_low_out := r_out + 2.2
		var r_low_gl := r_out - 2.6
		for i in range(segs):
			var a0 := float(i) * TAU / float(segs)
			var a1 := float(i + 1) * TAU / float(segs)
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			var lo0 := center + d0 * r_low_out
			var lo1 := center + d1 * r_low_out
			var lg0 := center + d0 * r_low_gl
			var lg1 := center + d1 * r_low_gl
			# Sculptural white ribbon balcony slab wrapping the hillside podium (ArchDaily #9!)
			_quad(white_st, Vector3(lo0.x, y_low_top - 0.85, lo0.y), Vector3(lo1.x, y_low_top - 0.85, lo1.y),
				Vector3(lo1.x, y_low_top, lo1.y), Vector3(lo0.x, y_low_top, lo0.y), white_rim)
			_quad(plaza_st, Vector3(lo0.x, y_low_top, lo0.y), Vector3(lo1.x, y_low_top, lo1.y),
				Vector3(lg1.x, y_low_top, lg1.y), Vector3(lg0.x, y_low_top, lg0.y), court_stone, true)
			_quad(dark_st, Vector3(lg0.x, y_low_top - 0.85, lg0.y), Vector3(lg1.x, y_low_top - 0.85, lg1.y),
				Vector3(lo1.x, y_low_top - 0.85, lo1.y), Vector3(lo0.x, y_low_top - 0.85, lo0.y), dark_soffit)
			# Lower glazed retail storefront + slender undercroft columns
			_quad(glass_st, Vector3(lg0.x, y_low_bot, lg0.y), Vector3(lg1.x, y_low_bot, lg1.y),
				Vector3(lg1.x, y_low_top - 0.85, lg1.y), Vector3(lg0.x, y_low_top - 0.85, lg0.y), glass_col)
			if i % 6 == 0:
				var cp := center + d0 * (r_low_out - 1.2)
				_emit_cyl_v(white_st, Vector3(cp.x, y_low_bot, cp.y), 0.34, 0.56, y_low_top - 0.85 - y_low_bot, white_rim, 8)

	# Main Floating Upper Ring Pavilion
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))

		var o0 := center + d0 * r_out
		var o1 := center + d1 * r_out
		var f0 := center + d0 * r_floor_out
		var f1 := center + d1 * r_floor_out
		var lo0 := center + d0 * r_lip_out
		var lo1 := center + d1 * r_lip_out
		var li0 := center + d0 * r_lip_in
		var li1 := center + d1 * r_lip_in
		var in0 := center + d0 * r_in
		var in1 := center + d1 * r_in
		var go0 := center + d0 * r_glass_out
		var go1 := center + d1 * r_glass_out
		var gi0 := center + d0 * r_glass_in
		var gi1 := center + d1 * r_glass_in

		# 1. Floating dark charcoal/black beveled base platter hovering above the green hill (ArchDaily #2!)
		_quad(dark_st, Vector3(f0.x, y_base - 0.45, f0.y), Vector3(f1.x, y_base - 0.45, f1.y),
			Vector3(f1.x, y_base + 0.04, f1.y), Vector3(f0.x, y_base + 0.04, f0.y), dark_soffit)
		_quad(dark_st, Vector3(go0.x, y_base - 1.15, go0.y), Vector3(go1.x, y_base - 1.15, go1.y),
			Vector3(f1.x, y_base - 0.45, f1.y), Vector3(f0.x, y_base - 0.45, f0.y), dark_soffit)
		# Solid dark base foundation skirt descending smoothly into the hill so ZERO gap opens on steep slopes
		var skirt_bot := maxf(0.10, y_base - 3.2)
		_quad(dark_st, Vector3(go0.x, skirt_bot, go0.y), Vector3(go1.x, skirt_bot, go1.y),
			Vector3(go1.x, y_base - 0.4, go1.y), Vector3(go0.x, y_base - 0.4, go0.y), Color(0.20, 0.22, 0.24))

		# 2. Ultra-clean recessed 360° curved glass curtain wall (outer & inner courtyard) + warm luminous depth
		_quad(glass_st, Vector3(go0.x, y_base, go0.y), Vector3(go1.x, y_base, go1.y),
			Vector3(go1.x, y_eave - 0.28, go1.y), Vector3(go0.x, y_eave - 0.28, go0.y), glass_col)
		_quad(glass_st, Vector3(gi1.x, y_base, gi1.y), Vector3(gi0.x, y_base, gi0.y),
			Vector3(gi0.x, y_eave - 0.28, gi0.y), Vector3(gi1.x, y_eave - 0.28, gi1.y), glass_col)
		var core_r := (r_glass_out + r_glass_in) * 0.5
		var gc0 := center + d0 * core_r
		var gc1 := center + d1 * core_r
		_quad(glow_st, Vector3(gc0.x, y_base + 0.5, gc0.y), Vector3(gc1.x, y_base + 0.5, gc1.y),
			Vector3(gc1.x, y_eave - 0.85, gc1.y), Vector3(gc0.x, y_eave - 0.85, gc0.y), glow_col)
		# Crisp bright interior ceiling disc visible through the clear glass!
		_quad(white_st, Vector3(go0.x, y_eave - 0.32, go0.y), Vector3(go1.x, y_eave - 0.32, go1.y),
			Vector3(gi1.x, y_eave - 0.32, gi1.y), Vector3(gi0.x, y_eave - 0.32, gi0.y), Color(0.92, 0.92, 0.90))
		# Ultra-slender vertical dark mullions on glass plane & slender internal white columns
		if i % 2 == 0:
			_emit_box(dark_st, Vector3(go0.x, y_base + h_glass * 0.5 - 0.14, go0.y), Vector3(0.14, h_glass - 0.28, 0.14), mull_col)
		if i % 4 == 0:
			var icp := center + d0 * (r_glass_out - 1.5)
			_emit_cyl_v(white_st, Vector3(icp.x, y_base, icp.y), 0.20, 0.20, h_glass - 0.32, Color(0.90, 0.90, 0.90), 6)

		# 3. Dramatic Dark Charcoal Cantilevered Roof Soffit (ArchDaily #2, #9!)
		_quad(dark_st, Vector3(go0.x, y_eave - 0.28, go0.y), Vector3(go1.x, y_eave - 0.28, go1.y),
			Vector3(o1.x, y_eave - 0.12, o1.y), Vector3(o0.x, y_eave - 0.12, o0.y), dark_soffit)
		_quad(dark_st, Vector3(in0.x, y_eave - 0.12, in0.y), Vector3(in1.x, y_eave - 0.12, in1.y),
			Vector3(gi1.x, y_eave - 0.28, gi1.y), Vector3(gi0.x, y_eave - 0.28, gi0.y), dark_soffit)

		# 4. Razor-Thin Gleaming White/Silver Saucer Edge Rim + Smooth Continuous Green Roof (NO checkerboard!)
		_quad(white_st, Vector3(o0.x, y_eave - 0.12, o0.y), Vector3(o1.x, y_eave - 0.12, o1.y),
			Vector3(o1.x, y_eave + 0.24, o1.y), Vector3(o0.x, y_eave + 0.24, o0.y), white_rim)
		_quad(white_st, Vector3(o0.x, y_eave + 0.24, o0.y), Vector3(o1.x, y_eave + 0.24, o1.y),
			Vector3(lo1.x, y_roof, lo1.y), Vector3(lo0.x, y_roof, lo0.y), silver_bevel, true)
		_quad(white_st, Vector3(in1.x, y_eave - 0.12, in1.y), Vector3(in0.x, y_eave - 0.12, in0.y),
			Vector3(in0.x, y_eave + 0.24, in0.y), Vector3(in1.x, y_eave + 0.24, in1.y), white_rim)
		_quad(white_st, Vector3(li0.x, y_roof, li0.y), Vector3(li1.x, y_roof, li1.y),
			Vector3(in1.x, y_eave + 0.24, in1.y), Vector3(in0.x, y_eave + 0.24, in0.y), silver_bevel, true)

		# Smooth flat/gently-domed lush planted roof (uniform rich sedum/emerald tone, subtly lit on ridge!)
		var r_mid := (r_lip_out + r_lip_in) * 0.5
		var m0 := center + d0 * r_mid
		var m1 := center + d1 * r_mid
		_quad(roof_green_st, Vector3(lo0.x, y_roof, lo0.y), Vector3(lo1.x, y_roof, lo1.y),
			Vector3(m1.x, y_roof + 0.26, m1.y), Vector3(m0.x, y_roof + 0.26, m0.y), col_roof_top, true)
		_quad(roof_green_st, Vector3(m0.x, y_roof + 0.26, m0.y), Vector3(m1.x, y_roof + 0.26, m1.y),
			Vector3(li1.x, y_roof, li1.y), Vector3(li0.x, y_roof, li0.y), col_roof_inner, true)

		# 5. Deep Sunlit Sunken Courtyard Floor & Curved White Wall Inside the Oculus!
		var y_court := maxf(1.2, y_base - 1.8)
		var cg0 := center + d0 * (r_in * 0.62)
		var cg1 := center + d1 * (r_in * 0.62)
		_quad(white_st, Vector3(gi1.x, y_court, gi1.y), Vector3(gi0.x, y_court, gi0.y),
			Vector3(gi0.x, y_base + 0.05, gi0.y), Vector3(gi1.x, y_base + 0.05, gi1.y), Color(0.86, 0.86, 0.84))
		_quad(plaza_st, Vector3(gi0.x, y_court, gi0.y), Vector3(gi1.x, y_court, gi1.y),
			Vector3(cg1.x, y_court, cg1.y), Vector3(cg0.x, y_court, cg0.y), court_stone, true)
		_tri(roof_green_st, Vector3(center.x, y_court + 0.06, center.y),
			Vector3(cg0.x, y_court + 0.04, cg0.y), Vector3(cg1.x, y_court + 0.04, cg1.y),
			Color(0.24, 0.48, 0.20), true)


# ---------------------------------------------------------------------------------------------
# 6. Inner Yellow-Green Oval Pavilion (E3) & Seamless Figure-8 / Peanut Pavilion (W2)
# ---------------------------------------------------------------------------------------------
static func _emit_floating_oval_pavilion(
	white_st: SurfaceTool,
	roof_green_st: SurfaceTool,
	dark_st: SurfaceTool,
	glass_st: SurfaceTool,
	glow_st: SurfaceTool,
	center: Vector2,
	rx: float,
	rz: float,
	y_base: float,
	h_glass: float,
	yaw: float,
	col_roof: Color
) -> void:
	var segs := 28
	var ca := cos(yaw)
	var sa := sin(yaw)
	var y_eave := y_base + h_glass
	var y_roof := y_eave + 0.48
	var white_rim := Color(0.96, 0.96, 0.95)
	var dark_soffit := Color(0.15, 0.17, 0.20)
	var glass_col := Color(0.40, 0.56, 0.66)

	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var l0 := Vector2(cos(a0) * rx, sin(a0) * rz)
		var l1 := Vector2(cos(a1) * rx, sin(a1) * rz)
		var o0 := center + Vector2(l0.x * ca - l0.y * sa, l0.x * sa + l0.y * ca)
		var o1 := center + Vector2(l1.x * ca - l1.y * sa, l1.x * sa + l1.y * ca)
		var g0 := center + (o0 - center) * 0.80
		var g1 := center + (o1 - center) * 0.80
		var lip0 := center + (o0 - center) * 0.86
		var lip1 := center + (o1 - center) * 0.86

		_quad(dark_st, Vector3(g0.x, maxf(0.1, y_base - 2.6), g0.y), Vector3(g1.x, maxf(0.1, y_base - 2.6), g1.y),
			Vector3(g1.x, y_base, g1.y), Vector3(g0.x, y_base, g0.y), dark_soffit)
		_quad(glass_st, Vector3(g0.x, y_base, g0.y), Vector3(g1.x, y_base, g1.y),
			Vector3(g1.x, y_eave - 0.25, g1.y), Vector3(g0.x, y_eave - 0.25, g0.y), glass_col)
		var gc0 := center + (o0 - center) * 0.72
		var gc1 := center + (o1 - center) * 0.72
		_quad(glow_st, Vector3(gc0.x, y_base + 0.4, gc0.y), Vector3(gc1.x, y_base + 0.4, gc1.y),
			Vector3(gc1.x, y_eave - 0.7, gc1.y), Vector3(gc0.x, y_eave - 0.7, gc0.y), Color(1.0, 0.93, 0.78))
		_quad(dark_st, Vector3(g0.x, y_eave - 0.25, g0.y), Vector3(g1.x, y_eave - 0.25, g1.y),
			Vector3(o1.x, y_eave - 0.10, o1.y), Vector3(o0.x, y_eave - 0.10, o0.y), dark_soffit)
		_quad(white_st, Vector3(o0.x, y_eave - 0.10, o0.y), Vector3(o1.x, y_eave - 0.10, o1.y),
			Vector3(o1.x, y_eave + 0.22, o1.y), Vector3(o0.x, y_eave + 0.22, o0.y), white_rim)
		_quad(white_st, Vector3(o0.x, y_eave + 0.22, o0.y), Vector3(o1.x, y_eave + 0.22, o1.y),
			Vector3(lip1.x, y_roof, lip1.y), Vector3(lip0.x, y_roof, lip0.y), Color(0.89, 0.90, 0.92), true)
		_tri(roof_green_st, Vector3(center.x, y_roof + 0.35, center.y),
			Vector3(lip0.x, y_roof, lip0.y), Vector3(lip1.x, y_roof, lip1.y), col_roof, true)


static func _emit_figure8_pavilion(
	white_st: SurfaceTool,
	roof_green_st: SurfaceTool,
	dark_st: SurfaceTool,
	glass_st: SurfaceTool,
	glow_st: SurfaceTool,
	center: Vector2,
	yaw: float,
	y_base: float,
	h_glass: float,
	col_roof: Color
) -> void:
	# Authentic MAD seamless peanut / figure-8 twin-lobed green pavilion bridging W1 and W3 (ArchDaily #1!)
	# Cassini-oval / pinched-peanut polar curve r(theta) = a * (1 + 0.34 * cos(2*theta))
	var segs := 44
	var ca := cos(yaw)
	var sa := sin(yaw)
	var y_eave := y_base + h_glass
	var y_roof := y_eave + 0.50
	var white_rim := Color(0.96, 0.96, 0.95)
	var dark_soffit := Color(0.15, 0.17, 0.20)
	var glass_col := Color(0.40, 0.56, 0.66)

	var o_pts: Array[Vector2] = []
	var lip_pts: Array[Vector2] = []
	var g_pts: Array[Vector2] = []
	for i in range(segs):
		var a := float(i) * TAU / float(segs)
		# Twin-lobe peanut shape: long axis ~22m half-length, pinched waist ~10.5m
		var r := 15.8 * (1.0 + 0.36 * cos(2.0 * a))
		var lp := Vector2(cos(a) * r, sin(a) * r * 0.88)
		var wp := center + Vector2(lp.x * ca - lp.y * sa, lp.x * sa + lp.y * ca)
		o_pts.append(wp)
		lip_pts.append(center + (wp - center) * 0.87)
		g_pts.append(center + (wp - center) * 0.80)

	for i in range(segs):
		var ni := (i + 1) % segs
		var o0 := o_pts[i]
		var o1 := o_pts[ni]
		var l0 := lip_pts[i]
		var l1 := lip_pts[ni]
		var g0 := g_pts[i]
		var g1 := g_pts[ni]
		_quad(dark_st, Vector3(g0.x, maxf(0.1, y_base - 2.8), g0.y), Vector3(g1.x, maxf(0.1, y_base - 2.8), g1.y),
			Vector3(g1.x, y_base, g1.y), Vector3(g0.x, y_base, g0.y), dark_soffit)
		_quad(glass_st, Vector3(g0.x, y_base, g0.y), Vector3(g1.x, y_base, g1.y),
			Vector3(g1.x, y_eave - 0.25, g1.y), Vector3(g0.x, y_eave - 0.25, g0.y), glass_col)
		var gc0 := center + (g0 - center) * 0.88
		var gc1 := center + (g1 - center) * 0.88
		_quad(glow_st, Vector3(gc0.x, y_base + 0.4, gc0.y), Vector3(gc1.x, y_base + 0.4, gc1.y),
			Vector3(gc1.x, y_eave - 0.7, gc1.y), Vector3(gc0.x, y_eave - 0.7, gc0.y), Color(1.0, 0.93, 0.78))
		if i % 3 == 0:
			_emit_box(dark_st, Vector3(g0.x, y_base + h_glass * 0.5, g0.y), Vector3(0.14, h_glass, 0.14), Color(0.22, 0.25, 0.29))
		_quad(dark_st, Vector3(g0.x, y_eave - 0.25, g0.y), Vector3(g1.x, y_eave - 0.25, g1.y),
			Vector3(o1.x, y_eave - 0.10, o1.y), Vector3(o0.x, y_eave - 0.10, o0.y), dark_soffit)
		_quad(white_st, Vector3(o0.x, y_eave - 0.10, o0.y), Vector3(o1.x, y_eave - 0.10, o1.y),
			Vector3(o1.x, y_eave + 0.24, o1.y), Vector3(o0.x, y_eave + 0.24, o0.y), white_rim)
		_quad(white_st, Vector3(o0.x, y_eave + 0.24, o0.y), Vector3(o1.x, y_eave + 0.24, o1.y),
			Vector3(l1.x, y_roof, l1.y), Vector3(l0.x, y_roof, l0.y), Color(0.89, 0.91, 0.93), true)
		_tri(roof_green_st, Vector3(center.x, y_roof + 0.30, center.y),
			Vector3(l0.x, y_roof, l0.y), Vector3(l1.x, y_roof, l1.y), col_roof, true)


static func _emit_sunken_oval_court(white_st: SurfaceTool, plaza_st: SurfaceTool, dark_st: SurfaceTool, center: Vector2, rx: float, rz: float, yaw: float) -> void:
	var segs := 24
	var ca := cos(yaw)
	var sa := sin(yaw)
	for i in range(segs):
		var a0 := float(i) * TAU / float(segs)
		var a1 := float(i + 1) * TAU / float(segs)
		var l0 := Vector2(cos(a0) * rx, sin(a0) * rz)
		var l1 := Vector2(cos(a1) * rx, sin(a1) * rz)
		var w0 := center + Vector2(l0.x * ca - l0.y * sa, l0.x * sa + l0.y * ca)
		var w1 := center + Vector2(l1.x * ca - l1.y * sa, l1.x * sa + l1.y * ca)
		var r0 := center + (w0 - center) * 1.18
		var r1 := center + (w1 - center) * 1.18
		var y0 := _hill_height(r0.x, r0.y) + 0.25
		var y1 := _hill_height(r1.x, r1.y) + 0.25
		_quad(white_st, Vector3(w0.x, 0.55, w0.y), Vector3(w1.x, 0.55, w1.y),
			Vector3(w1.x, y1, w1.y), Vector3(w0.x, y0, w0.y), Color(0.90, 0.91, 0.92))
		_quad(white_st, Vector3(w0.x, y0, w0.y), Vector3(w1.x, y1, w1.y),
			Vector3(r1.x, y1 + 0.05, r1.y), Vector3(r0.x, y0 + 0.05, r0.y), Color(0.95, 0.95, 0.93), true)
		_tri(plaza_st, Vector3(center.x, 0.55, center.y),
			Vector3(w0.x, 0.55, w0.y), Vector3(w1.x, 0.55, w1.y), Color(0.82, 0.82, 0.79), true)
		if i % 3 == 0:
			_emit_box(dark_st, Vector3(w0.x, y0 + 0.55, w0.y), Vector3(0.08, 1.05, 0.08), Color(0.32, 0.34, 0.38))


# ---------------------------------------------------------------------------------------------
# 7. Central Axial Subway Promenade, Twin Sculptural White Arch Portals & Curved Sunken Lightwell
# ---------------------------------------------------------------------------------------------
static func _emit_central_axis_and_paths(
	plaza_st: SurfaceTool,
	white_st: SurfaceTool,
	dark_st: SurfaceTool,
	glass_st: SurfaceTool
) -> void:
	var stone_col := Color(0.87, 0.87, 0.84)
	var white_arch := Color(0.95, 0.95, 0.94)
	var rail_post := Color(0.34, 0.36, 0.40)

	# 1. Crisp Rounded-Trapezoid Granite Apron underneath & framing South Waiting Lobby (cleanly above flat lawn!)
	var lobby_apron := _rounded_trapezoid_pts(82.0, 62.0, 25.5, 11.0, false)
	var la_c := Vector3(20.0, 0.17, 49.5)
	for li in range(lobby_apron.size()):
		var p0 := lobby_apron[li]
		var p1 := lobby_apron[(li + 1) % lobby_apron.size()]
		_tri(plaza_st, la_c, Vector3(20.0 + p0.x, 0.17, 49.5 + p0.y), Vector3(20.0 + p1.x, 0.17, 49.5 + p1.y), stone_col, true)
	# Symmetrical Axial Subway Promenade leading from Central Lawn (lz=152) to SE Apex Subway Portal (lz=302)
	_emit_box(plaza_st, Vector3(14.0, 0.18, 228.0), Vector3(13.5, 0.12, 152.0), stone_col)

	# 2. Two Sculpted Oval Terraced Plazas along the Central Subway Axis (ArchDaily #1 top apex!)
	for oz: float in [178.0, 240.0]:
		var segs := 24
		var rx := 15.0 if oz < 200.0 else 13.5
		var rz := 19.0 if oz < 200.0 else 16.5
		for i in range(segs):
			var a0 := float(i) * TAU / float(segs)
			var a1 := float(i + 1) * TAU / float(segs)
			var p0 := Vector2(14.0 + cos(a0) * rx, oz + sin(a0) * rz)
			var p1 := Vector2(14.0 + cos(a1) * rx, oz + sin(a1) * rz)
			var q0 := Vector2(14.0 + cos(a0) * (rx + 1.8), oz + sin(a0) * (rz + 1.8))
			var q1 := Vector2(14.0 + cos(a1) * (rx + 1.8), oz + sin(a1) * (rz + 1.8))
			_tri(plaza_st, Vector3(14.0, 0.20, oz), Vector3(p0.x, 0.20, p0.y), Vector3(p1.x, 0.20, p1.y), stone_col, true)
			_quad(white_st, Vector3(p0.x, 0.22, p0.y), Vector3(p1.x, 0.22, p1.y),
				Vector3(q1.x, 0.85, q1.y), Vector3(q0.x, 0.85, q0.y), white_arch, true)

	# 3. MAD's Iconic Twin Sculptural Curved White Arch Stair Portals flanking the Central Axis (ArchDaily #10!)
	for side: float in [-1.0, 1.0]:
		var px := 14.0 + side * 19.5
		var pz := 204.0
		# Sweeping sculptural white arch rib framing the grand hillside staircase
		var a_segs := 14
		for i in range(a_segs):
			var t0 := float(i) / float(a_segs)
			var t1 := float(i + 1) / float(a_segs)
			var ang0 := t0 * PI
			var ang1 := t1 * PI
			var y0 := 0.25 + sin(ang0) * 5.2
			var y1 := 0.25 + sin(ang1) * 5.2
			var z0 := pz - 11.0 + t0 * 22.0
			var z1 := pz - 11.0 + t1 * 22.0
			var x_in := px - side * 2.2
			var x_out := px + side * 2.2
			_quad(white_st, Vector3(x_in, y0, z0), Vector3(x_out, y0, z0),
				Vector3(x_out, y1, z1), Vector3(x_in, y1, z1), white_arch)
			_quad(white_st, Vector3(x_in, y0 - 0.85, z0), Vector3(x_in, y0, z0),
				Vector3(x_in, y1, z1), Vector3(x_in, y1 - 0.85, z1), Color(0.86, 0.87, 0.89))
		# Stepped grand stone staircase climbing from axial plaza up onto the ring hills
		for st_i in range(10):
			var sf := float(st_i) / 10.0
			var sx := 14.0 + side * (9.5 + sf * 18.0)
			var sy := 0.25 + sf * 4.8
			_emit_box(plaza_st, Vector3(sx, sy, pz), Vector3(2.2, 0.55, 7.6), stone_col)
			_emit_box(white_st, Vector3(sx, sy + 0.55, pz - 3.9), Vector3(2.2, 0.85, 0.28), white_arch)
			_emit_box(white_st, Vector3(sx, sy + 0.55, pz + 3.9), Vector3(2.2, 0.85, 0.28), white_arch)

	# 4. Curved Sunken Lightwell Court with White Aluminum Wall, Deep Atrium Floor & Glass Balustrade (ArchDaily #2!)
	var lw_c := Vector2(88.0, 114.0)
	var lw_r := 11.5
	for i in range(24):
		var a0 := float(i) * TAU / 24.0
		var a1 := float(i + 1) * TAU / 24.0
		var p0 := lw_c + Vector2(cos(a0) * lw_r, sin(a0) * lw_r)
		var p1 := lw_c + Vector2(cos(a1) * lw_r, sin(a1) * lw_r)
		var o0 := lw_c + Vector2(cos(a0) * (lw_r + 3.4), sin(a0) * (lw_r + 3.4))
		var o1 := lw_c + Vector2(cos(a1) * (lw_r + 3.4), sin(a1) * (lw_r + 3.4))
		_quad(white_st, Vector3(p0.x, -2.4, p0.y), Vector3(p1.x, -2.4, p1.y),
			Vector3(p1.x, 0.45, p1.y), Vector3(p0.x, 0.45, p0.y), Color(0.90, 0.91, 0.92))
		_tri(dark_st, Vector3(lw_c.x, -2.4, lw_c.y), Vector3(p0.x, -2.4, p0.y), Vector3(p1.x, -2.4, p1.y), Color(0.28, 0.30, 0.33), true)
		_quad(plaza_st, Vector3(p0.x, 0.22, p0.y), Vector3(p1.x, 0.22, p1.y),
			Vector3(o1.x, 0.22, o1.y), Vector3(o0.x, 0.22, o0.y), stone_col, true)
		_quad(glass_st, Vector3(p0.x, 0.45, p0.y), Vector3(p1.x, 0.45, p1.y),
			Vector3(p1.x, 1.45, p1.y), Vector3(p0.x, 1.45, p0.y), Color(0.55, 0.68, 0.76))
		if i % 2 == 0:
			_emit_box(dark_st, Vector3(p0.x, 0.95, p0.y), Vector3(0.08, 1.05, 0.08), rail_post)


# ---------------------------------------------------------------------------------------------
# 8. Sweeping Curved White-Ribbon Elevated Hill Walkways, Ramps & Undercrofts (ArchDaily #2,#8,#9)
# ---------------------------------------------------------------------------------------------
static func _emit_curved_hill_walkways(
	white_st: SurfaceTool,
	plaza_st: SurfaceTool,
	dark_st: SurfaceTool,
	glass_st: SurfaceTool
) -> void:
	# Continuous sculptural curved white ribbons winding smoothly across the green hills and bridging
	# between the floating rings, with cantilevered dark ceilings & conical white undercroft piers!
	var ribbon_paths: Array = [
		# East hill grand ribbon: South Lobby -> Inner Lawn Rim -> E1 -> E2 -> E3 -> E4 -> Central Axis!
		[
			Vector3(96.0, 0.25, 76.0),
			Vector3(124.0, 2.2, 92.0),
			Vector3(148.0, 4.6, 128.0),
			Vector3(114.0, 5.2, 148.0),
			Vector3(96.0, 5.4, 178.0),
			Vector3(56.0, 5.8, 184.0),
			Vector3(34.0, 3.8, 176.0),
			Vector3(20.0, 0.35, 162.0),
		],
		# Outer East dramatic elevated skywalk / undercroft bridge (Egg Tower -> E1 -> E2 -> E4, ArchDaily #9!)
		[
			Vector3(174.0, 3.8, 86.0),
			Vector3(160.0, 5.0, 128.0),
			Vector3(144.0, 5.6, 176.0),
			Vector3(96.0, 5.8, 206.0),
			Vector3(74.0, 5.6, 232.0),
		],
		# West hill grand ribbon: Central Axis -> W1 -> Figure-8 W2 -> W3 -> SW Courtyard W4 -> South Lobby!
		[
			Vector3(8.0, 0.35, 162.0),
			Vector3(-12.0, 3.8, 176.0),
			Vector3(-34.0, 5.6, 180.0),
			Vector3(-60.0, 5.0, 146.0),
			Vector3(-92.0, 4.8, 126.0),
			Vector3(-136.0, 4.2, 108.0),
			Vector3(-148.0, 2.2, 82.0),
			Vector3(-92.0, 0.30, 74.0),
		],
		# Outer Canal Waterfront Sculptural Bridge linking W1 -> W2 -> W3
		[
			Vector3(-56.0, 5.4, 218.0),
			Vector3(-88.0, 5.0, 184.0),
			Vector3(-124.0, 4.8, 152.0),
		],
		# Central Lawn smooth pale-stone perimeter loop hugging the foot of the hills!
		[
			Vector3(-62.0, 0.20, 76.0),
			Vector3(-76.0, 0.22, 114.0),
			Vector3(-52.0, 0.22, 144.0),
			Vector3(-12.0, 0.22, 156.0),
			Vector3(14.0, 0.22, 158.0),
			Vector3(46.0, 0.22, 154.0),
			Vector3(86.0, 0.22, 134.0),
			Vector3(102.0, 0.20, 96.0),
			Vector3(92.0, 0.20, 76.0),
		],
	]

	for path_i in range(ribbon_paths.size()):
		var ctrl: Array = ribbon_paths[path_i]
		var is_ground_loop := (path_i == 4)
		var smooth_pts := _catmull_rom_3d(ctrl, 6)
		if is_ground_loop:
			for pi in range(smooth_pts.size()):
				var sp := smooth_pts[pi]
				smooth_pts[pi] = Vector3(sp.x, _hill_height(sp.x, sp.z) + 0.15, sp.z)
		_emit_sculpted_walkway_ribbon(white_st, plaza_st, dark_st, glass_st, smooth_pts,
			3.2 if is_ground_loop else 4.2, not is_ground_loop)


static func _catmull_rom_3d(pts: Array, sub: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := pts.size()
	for i in range(n - 1):
		var p0: Vector3 = pts[maxi(0, i - 1)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(n - 1, i + 2)]
		for s in range(sub):
			var t := float(s) / float(sub)
			var t2 := t * t
			var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			out.append(q)
	out.append(pts[n - 1])
	return out


static func _emit_sculpted_walkway_ribbon(
	white_st: SurfaceTool,
	plaza_st: SurfaceTool,
	dark_st: SurfaceTool,
	glass_st: SurfaceTool,
	pts: Array[Vector3],
	width: float,
	elevated: bool
) -> void:
	var white_beam := Color(0.95, 0.95, 0.94)
	var stone_deck := Color(0.86, 0.86, 0.83)
	var dark_under := Color(0.16, 0.18, 0.21)
	var rail_glass := Color(0.55, 0.68, 0.76)
	var wood_rail := Color(0.66, 0.48, 0.30)
	var hw := width * 0.5
	var beam_d := 0.95 if elevated else 0.14

	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d2 := Vector2(b.x - a.x, b.z - a.z)
		if d2.length_squared() < 0.01:
			continue
		var t2 := d2.normalized()
		var n2 := Vector2(-t2.y, t2.x)
		var l_a := Vector3(a.x + n2.x * hw, a.y, a.z + n2.y * hw)
		var r_a := Vector3(a.x - n2.x * hw, a.y, a.z - n2.y * hw)
		var l_b := Vector3(b.x + n2.x * hw, b.y, b.z + n2.y * hw)
		var r_b := Vector3(b.x - n2.x * hw, b.y, b.z - n2.y * hw)

		# Pale granite walkway surface
		_quad(plaza_st, l_a, r_a, r_b, l_b, stone_deck, true)

		if elevated:
			var lb_a := l_a - Vector3(0.0, beam_d, 0.0)
			var rb_a := r_a - Vector3(0.0, beam_d, 0.0)
			var lb_b := l_b - Vector3(0.0, beam_d, 0.0)
			var rb_b := r_b - Vector3(0.0, beam_d, 0.0)
			# Sculptural white-clad curved side beams (ArchDaily #9!)
			_quad(white_st, lb_a, l_a, l_b, lb_b, white_beam)
			_quad(white_st, r_a, rb_a, rb_b, r_b, white_beam)
			# Dark charcoal metal slatted soffit underneath bridge!
			_quad(dark_st, rb_a, lb_a, lb_b, rb_b, dark_under)
			# Sleek stainless-mesh/glass balustrade + warm wood handrail along both edges (ArchDaily #2,#8,#9)
			_quad(glass_st, l_a, l_b, l_b + Vector3(0.0, 1.02, 0.0), l_a + Vector3(0.0, 1.02, 0.0), rail_glass)
			_quad(glass_st, r_a, r_b, r_b + Vector3(0.0, 1.02, 0.0), r_a + Vector3(0.0, 1.02, 0.0), rail_glass)
			_quad(dark_st, l_a + Vector3(0.0, 1.00, 0.0), l_b + Vector3(0.0, 1.00, 0.0),
				l_b + Vector3(0.0, 1.09, 0.0), l_a + Vector3(0.0, 1.09, 0.0), wood_rail)
			_quad(dark_st, r_a + Vector3(0.0, 1.00, 0.0), r_b + Vector3(0.0, 1.00, 0.0),
				r_b + Vector3(0.0, 1.09, 0.0), r_a + Vector3(0.0, 1.09, 0.0), wood_rail)
			# Sculptural conical white undercroft piers & slender cylindrical steel columns whenever bridge clears hill!
			if i % 5 == 2:
				var g_h := _hill_height(a.x, a.z)
				var clear_h := a.y - beam_d - g_h
				if clear_h > 0.6:
					_emit_cyl_v(white_st, Vector3(a.x, g_h - 0.3, a.z), 0.36, 0.68, clear_h + 0.4, white_beam, 8)
				elif a.y > 2.2:
					# Slender steel edge struts where bridge hugs hill slope
					_emit_cyl_v(dark_st, Vector3(r_a.x, maxf(0.1, g_h - 0.5), r_a.z), 0.16, 0.16, a.y - beam_d - maxf(0.1, g_h - 0.5) + 0.1, Color(0.26, 0.28, 0.32), 6)


# ---------------------------------------------------------------------------------------------
# 9. Curated "Forest Station" Woodland Trees (Open Central Lawn + Lush Hillfoot & Courtyard Groves)
# ---------------------------------------------------------------------------------------------
static func _plant_south_plaza_trees(root: Node3D) -> void:
	# Exact pavilions exclusion list [lx, lz, radius] so trees never clip into glass/roofs
	var excl: Array = [
		[194.0, 64.0, 28.0],
		[148.0, 104.0, 28.0],
		[128.0, 162.0, 24.5],
		[78.0, 154.0, 17.5],
		[64.0, 208.0, 27.0],
		[-36.0, 206.0, 28.5],
		[-74.0, 162.0, 22.0],
		[-114.0, 134.0, 28.5],
		[-166.0, 92.0, 14.0],
	]
	# Curated woodland groves framing the Central Lawn perimeter, hill slopes, canal bank & SE apex!
	# Note: the open 1-hectare Central Lawn center (lx in [-45..+80], lz in [76..138]) stays 100% open & clean!
	var spots: Array[Vector2] = [
		# Southern edge of Central Lawn hugging the foot of the hills (ArchDaily #1!)
		Vector2(-56.0, 142.0), Vector2(-42.0, 148.0), Vector2(-26.0, 152.0), Vector2(-8.0, 154.0),
		Vector2(34.0, 152.0), Vector2(50.0, 146.0), Vector2(64.0, 138.0), Vector2(106.0, 118.0),
		Vector2(114.0, 102.0), Vector2(116.0, 86.0), Vector2(-78.0, 118.0), Vector2(-84.0, 96.0),
		# Between hills & walkways on East cluster
		Vector2(166.0, 136.0), Vector2(158.0, 156.0), Vector2(104.0, 134.0), Vector2(102.0, 178.0),
		Vector2(98.0, 198.0), Vector2(88.0, 228.0), Vector2(60.0, 252.0), Vector2(44.0, 266.0),
		Vector2(34.0, 242.0), Vector2(36.0, 282.0), Vector2(22.0, 294.0),
		# Between hills & walkways on West cluster & along 环城河 waterfront
		Vector2(-12.0, 244.0), Vector2(-24.0, 268.0), Vector2(-46.0, 248.0), Vector2(-72.0, 212.0),
		Vector2(-94.0, 196.0), Vector2(-112.0, 174.0), Vector2(-142.0, 148.0), Vector2(-154.0, 128.0),
		Vector2(-186.0, 114.0), Vector2(-202.0, 96.0), Vector2(-216.0, 74.0), Vector2(-192.0, 62.0),
		Vector2(-150.0, 62.0), Vector2(-126.0, 72.0), Vector2(-102.0, 86.0), Vector2(-62.0, 186.0),
		Vector2(-14.0, 284.0), Vector2(2.0, 298.0),
		# Outer 东方路 green buffer grove
		Vector2(216.0, 92.0), Vector2(188.0, 124.0), Vector2(164.0, 150.0), Vector2(142.0, 184.0),
		Vector2(114.0, 206.0), Vector2(90.0, 238.0),
	]
	for ti in range(spots.size()):
		var tp := spots[ti]
		if _site_sdf(tp.x, tp.y) > -6.0:
			continue
		var clear := true
		for ex in excl:
			if tp.distance_to(Vector2(float(ex[0]), float(ex[1]))) < float(ex[2]):
				clear = false
				break
		if clear:
			var ty := _hill_height(tp.x, tp.y)
			var tcol := ParkLandscapeBuilder.CAMPHOR if (ti % 3 == 0) else (ParkLandscapeBuilder.CAMPHOR_LT if (ti % 3 == 1) else Color(0.24, 0.46, 0.19))
			ParkLandscapeBuilder.plant_tree(root, Vector3(tp.x, ty - 0.10, tp.y), 1, 0.88 + float(ti % 3) * 0.14, tcol)

	# Ornamental trees nestled inside each open circular courtyard oculus!
	var oc_list: Array = [
		[148.0, 104.0, 3.4],
		[128.0, 162.0, 4.0],
		[64.0, 208.0, 4.4],
		[-36.0, 206.0, 4.2],
		[-114.0, 134.0, 3.4],
	]
	for oi in range(oc_list.size()):
		var oc: Array = oc_list[oi]
		var cx := float(oc[0])
		var cz := float(oc[1])
		var cy := float(oc[2])
		ParkLandscapeBuilder.plant_tree(root, Vector3(cx + 2.4, cy, cz - 1.6), 1, 0.72, ParkLandscapeBuilder.CAMPHOR_LT)
		ParkLandscapeBuilder.plant_tree(root, Vector3(cx - 2.2, cy, cz + 1.8), 1, 0.64, ParkLandscapeBuilder.CAMPHOR)
