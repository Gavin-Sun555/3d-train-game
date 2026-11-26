class_name JiaxingSouthPlazaBuilder
extends RefCounted

# 1:1 Google Earth calibrated architectural modeling of 嘉兴南站北广场 (Jiaxing South HSR Station North Plaza):
#   - Station-front East & West surface parking lots with parked vehicle fleets & shade-tree islands
#   - Central Geometric Civic Esplanade with twin glass underground-concourse exit pavilions & tree promenades
#   - East Bus Transit Hub (嘉兴南站公交枢纽站): 4 north-south covered boarding islands, turquoise dispatch booths,
#     illuminated route totems & parked Jiaxing electric bus fleet (north-south + north layover bays)
#   - West Bus / Coach & Taxi Transfer Hub: 3 north-south covered boarding islands, coaches & taxi staging
#   - East Multi-Deck Parking Garage (P2停车楼): 2-level concrete parking structure with open rooftop parking
#     deck, 4 double-row stall bays, access ramp, elevator cores & 48 parked rooftop vehicles
#   - Northeast Grid-Frame Glass Hotel & Green-Roof Podium Complex (14F white exo-grid tower + 3F garden podium)
#   - Southwest Courtyard Atrium Civic/Business Building (5F square complex with central glazed skylight atrium)
#   - West High-Rise Hotel & Commercial Slab Complex (18F modern slab tower + 4F green-roof terrace podium)
#   - North Plaza Eco-Park & Pedestrian Connector Belt framing the sightline toward 百川路
#
# All coordinates are in the local frame of JiaxingSouthHSRStation (center=(4190.09, 6883.23), angle=0.4925 rad),
# strictly clear of 嘉兴南站站前路 & T1 tramway (z=-119..-97), 双溪路 (x=-248), internal connector (x=+143),
# 庆丰路 (x=+291), and 百川路 (z=-410..-320).


static func _emit_box(st: SurfaceTool, pos: Vector3, sz: Vector3, col: Color, rot_y: float = 0.0, rot_z: float = 0.0, rot_x: float = 0.0) -> void:
	var b := Basis.from_euler(Vector3(rot_x, rot_y, rot_z))
	RoadSignBuilder._box(st, Transform3D(b, pos), sz, col)


static func _emit_cyl_approx(st: SurfaceTool, pos: Vector3, radius: float, height: float, col: Color) -> void:
	# Clean octagonal/square architectural column batched into SurfaceTool (zero extra draw calls)
	var s := radius * 1.85
	_emit_box(st, pos, Vector3(s, height, s), col, 0.0)
	_emit_box(st, pos, Vector3(s, height, s), col, PI * 0.25)


static func _commit_vc_mesh(parent: Node3D, node_name: String, st: SurfaceTool, rough: float = 0.72, metal: float = 0.06, shadow: bool = true) -> void:
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
	mat.metallic_specular = 0.28
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _commit_glass_mesh(parent: Node3D, node_name: String, st: SurfaceTool, alpha: float = 0.72) -> void:
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
	mat.roughness = 0.08
	mat.metallic = 0.42
	mat.metallic_specular = 0.72
	mi.material_override = mat
	parent.add_child(mi)


static func _commit_emissive_mesh(parent: Node3D, node_name: String, st: SurfaceTool, energy: float = 1.25) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.94, 0.82)
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.32
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# Compact batched low-poly parked car (sedan/SUV silhouette with cabin, dark windshield & wheels)
static func _emit_parked_car(st: SurfaceTool, pos: Vector3, yaw: float, body_col: Color, is_suv: bool = false) -> void:
	var b := Basis(Vector3.UP, yaw)
	var clen := 4.55 if is_suv else 4.45
	var cwid := 1.88 if is_suv else 1.80
	var ch := 0.74 if is_suv else 0.64
	var cab_l := 2.55 if is_suv else 2.05
	var cab_h := 0.62 if is_suv else 0.52
	var cab_off := -0.15 if is_suv else -0.22
	# Lower body
	RoadSignBuilder._box(st, Transform3D(b, pos + Vector3(0.0, 0.24 + ch * 0.5, 0.0)), Vector3(clen, ch, cwid), body_col)
	# Upper greenhouse cabin
	var win_c := Color(0.11, 0.15, 0.20)
	RoadSignBuilder._box(st, Transform3D(b, pos + b * Vector3(cab_off, 0.24 + ch + cab_h * 0.5, 0.0)), Vector3(cab_l, cab_h, cwid * 0.86), win_c)
	# Roof paint cap
	RoadSignBuilder._box(st, Transform3D(b, pos + b * Vector3(cab_off, 0.24 + ch + cab_h + 0.03, 0.0)), Vector3(cab_l * 0.82, 0.06, cwid * 0.80), body_col)
	# Dark undercarriage / wheel blocks
	var tire_c := Color(0.12, 0.12, 0.13)
	for wx: float in [-1.32, 1.32]:
		RoadSignBuilder._box(st, Transform3D(b, pos + b * Vector3(wx, 0.24, 0.0)), Vector3(0.62, 0.46, cwid * 0.96), tire_c)


# Compact batched modern electric city bus / intercity coach
static func _emit_batched_bus(st: SurfaceTool, glow_st: SurfaceTool, pos: Vector3, yaw: float, accent_col: Color, body_col: Color = Color(0.94, 0.95, 0.96)) -> void:
	var b := Basis(Vector3.UP, yaw)
	var glass_c := Color(0.09, 0.13, 0.18)
	var tire_c := Color(0.11, 0.11, 0.12)
	var pod_c := Color(0.84, 0.86, 0.88)
	RoadSignBuilder._box(st, Transform3D(b, pos + Vector3(0.0, 1.56, 0.0)), Vector3(11.4, 2.52, 2.52), body_col)
	RoadSignBuilder._box(st, Transform3D(b, pos + Vector3(0.0, 0.82, 0.0)), Vector3(11.46, 0.74, 2.56), accent_col)
	RoadSignBuilder._box(st, Transform3D(b, pos + Vector3(0.0, 1.88, 0.0)), Vector3(10.6, 1.10, 2.58), glass_c)
	RoadSignBuilder._box(st, Transform3D(b, pos + b * Vector3(-5.68, 1.72, 0.0)), Vector3(0.16, 1.44, 2.28), glass_c)
	RoadSignBuilder._box(st, Transform3D(b, pos + b * Vector3(0.35, 3.02, 0.0)), Vector3(6.6, 0.40, 1.72), pod_c)
	for wx: float in [-3.35, 3.25]:
		RoadSignBuilder._box(st, Transform3D(b, pos + b * Vector3(wx, 0.46, 0.0)), Vector3(0.92, 0.90, 2.44), tire_c)
	# Amber LED route board
	RoadSignBuilder._box(glow_st, Transform3D(b, pos + b * Vector3(-5.74, 2.58, 0.0)), Vector3(0.12, 0.24, 1.42), Color(1.0, 0.74, 0.20))


static func _emit_lamp_pole(st: SurfaceTool, glow_st: SurfaceTool, pos: Vector3, h: float = 8.2) -> void:
	_emit_box(st, pos + Vector3(0.0, h * 0.5, 0.0), Vector3(0.20, h, 0.20), Color(0.28, 0.30, 0.33))
	_emit_box(st, pos + Vector3(0.0, h + 0.12, 0.0), Vector3(1.65, 0.18, 0.36), Color(0.34, 0.36, 0.40))
	_emit_box(glow_st, pos + Vector3(0.0, h + 0.01, 0.0), Vector3(1.45, 0.08, 0.24), Color(1.0, 0.94, 0.78))


static func build(st_root: Node3D, lights: Array) -> void:
	var plaza_n := Node3D.new()
	plaza_n.name = "JiaxingSouthNorthPlaza"
	st_root.add_child(plaza_n)

	var bus_hub := Node3D.new()
	bus_hub.name = "JiaxingSouthBusHub"
	st_root.add_child(bus_hub)

	# Batched geometry accumulators (dramatically higher detail with minimal draw calls!)
	var ground_st := SurfaceTool.new(); ground_st.begin(Mesh.PRIMITIVE_TRIANGLES) # non-shadow-casting paving/asphalt/markings
	var solid_st := SurfaceTool.new(); solid_st.begin(Mesh.PRIMITIVE_TRIANGLES)   # shadow-casting architecture/canopies/cars
	var glass_st := SurfaceTool.new(); glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)   # translucent reflective glazing/skylights
	var glow_st := SurfaceTool.new(); glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)     # LED strips, interior lobbies, transit signs

	var bus_ground_st := SurfaceTool.new(); bus_ground_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bus_solid_st := SurfaceTool.new(); bus_solid_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bus_glass_st := SurfaceTool.new(); bus_glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bus_glow_st := SurfaceTool.new(); bus_glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calibrated architectural palette (physical PBR tones matching Google Earth & Jiaxing photography)
	var c_granite_lt := Color(0.76, 0.75, 0.72)
	var c_granite_md := Color(0.64, 0.64, 0.62)
	var c_granite_dk := Color(0.45, 0.46, 0.48)
	var c_asphalt := Color(0.24, 0.25, 0.27)
	var c_asphalt_lt := Color(0.30, 0.31, 0.33)
	var c_concrete := Color(0.70, 0.70, 0.68)
	var c_concrete_dk := Color(0.54, 0.55, 0.56)
	var c_steel := Color(0.86, 0.88, 0.90)
	var c_roof_silver := Color(0.78, 0.81, 0.84)
	var c_dark_frame := Color(0.22, 0.24, 0.28)
	var c_white_line := Color(0.88, 0.88, 0.85)
	var c_yellow := Color(0.92, 0.74, 0.16)
	var c_teal_roof := Color(0.24, 0.50, 0.48)
	var c_glass_blue := Color(0.24, 0.40, 0.54)
	var c_glass_teal := Color(0.22, 0.48, 0.46)
	var c_glass_dark := Color(0.14, 0.21, 0.29)
	var c_warm_stone := Color(0.82, 0.78, 0.71)
	var c_ivory := Color(0.89, 0.87, 0.83)
	var c_grid_white := Color(0.90, 0.91, 0.92)
	var c_warm_glow := Color(1.0, 0.90, 0.72)

	var car_palette: Array[Color] = [
		Color(0.92, 0.92, 0.91), Color(0.20, 0.22, 0.25), Color(0.70, 0.72, 0.75),
		Color(0.88, 0.89, 0.90), Color(0.16, 0.26, 0.42), Color(0.58, 0.18, 0.18),
		Color(0.42, 0.44, 0.47), Color(0.82, 0.78, 0.70), Color(0.22, 0.34, 0.28),
	]
	var lawn_mat := JiaxingLandmarks.lawn_material()

	# =========================================================================================
	# ZONE 1: STATION-FRONT FORECOURT, T1 TRANSFER CANOPY & EAST/WEST SURFACE PARKING LOTS
	# (z = -95 .. -52, strictly SOUTH of 嘉兴南站站前路 & T1 tramway at z = -109!)
	# =========================================================================================
	# Central covered T1 transfer walkway canopy (x = -24..+24, z = -93..-84)
	_emit_box(solid_st, Vector3(0.0, 4.75, -89.5), Vector3(48.0, 0.30, 7.6), c_roof_silver)
	_emit_box(glass_st, Vector3(0.0, 4.92, -89.5), Vector3(44.0, 0.14, 4.2), c_glass_teal)
	_emit_box(glow_st, Vector3(0.0, 4.56, -89.5), Vector3(42.0, 0.08, 0.9), c_warm_glow)
	for tx_c: float in [-21.0, -7.0, 7.0, 21.0]:
		_emit_box(solid_st, Vector3(tx_c, 2.35, -89.5), Vector3(0.40, 4.70, 0.40), c_steel)
	JiaxingLandmarks._add_sign_label(plaza_n, "有轨电车 T1 线 · 嘉兴南站换乘通道", Vector3(0.0, 5.40, -93.4), PI, 42, 0.022, Color(0.98, 0.86, 0.34))

	# West Surface Parking Lot (西侧地面停车场, x = -224..-104, z = -90..-56)
	_emit_box(ground_st, Vector3(-164.0, 0.015, -73.0), Vector3(120.0, 0.05, 34.0), c_asphalt)
	_emit_box(solid_st, Vector3(-164.0, 0.14, -90.2), Vector3(120.0, 0.28, 0.6), c_granite_dk)
	for px_w in range(-216, -108, 6):
		_emit_box(ground_st, Vector3(float(px_w), 0.045, -82.0), Vector3(0.14, 0.02, 4.8), c_white_line)
		_emit_box(ground_st, Vector3(float(px_w), 0.045, -65.0), Vector3(0.14, 0.02, 4.8), c_white_line)
	for wi in range(18):
		var wx_car := -213.0 + float(wi) * 5.9
		if (wi % 5) != 2:
			_emit_parked_car(solid_st, Vector3(wx_car, 0.04, -82.0), PI * 0.5, car_palette[wi % car_palette.size()], (wi % 3) == 0)
		if (wi % 4) != 1:
			_emit_parked_car(solid_st, Vector3(wx_car, 0.04, -65.0), -PI * 0.5, car_palette[(wi * 3 + 2) % car_palette.size()], (wi % 4) == 0)
	for tw_x: float in [-212.0, -184.0, -156.0, -128.0]:
		ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(tw_x, 0.0, -91.2), 1, 0.82, ParkLandscapeBuilder.CAMPHOR)

	# East Surface Parking Lot (东侧地面停车场, x = +96..+244, z = -90..-54)
	_emit_box(ground_st, Vector3(170.0, 0.015, -72.0), Vector3(148.0, 0.05, 36.0), c_asphalt)
	_emit_box(solid_st, Vector3(170.0, 0.14, -90.2), Vector3(148.0, 0.28, 0.6), c_granite_dk)
	# Center planter strip with shade trees (visible in Google Earth dividing east lot!)
	JiaxingLandmarks._add_box(plaza_n, Vector3(136.0, 0.26, 3.6), Vector3(170.0, 0.13, -72.5), lawn_mat, 0.0, 0.0, 0.0, false)
	for te_x in range(110, 236, 16):
		ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(float(te_x), 0.22, -72.5), 1, 0.85, ParkLandscapeBuilder.CAMPHOR if (te_x % 32 == 0) else ParkLandscapeBuilder.CAMPHOR_LT)
	for ei in range(22):
		var ex_car := 104.0 + float(ei) * 6.2
		_emit_box(ground_st, Vector3(ex_car - 3.0, 0.045, -83.0), Vector3(0.14, 0.02, 4.8), c_white_line)
		_emit_box(ground_st, Vector3(ex_car - 3.0, 0.045, -62.0), Vector3(0.14, 0.02, 4.8), c_white_line)
		if (ei % 6) != 3:
			_emit_parked_car(solid_st, Vector3(ex_car, 0.04, -83.0), PI * 0.5, car_palette[(ei + 1) % car_palette.size()], (ei % 3) == 1)
		if (ei % 5) != 2:
			_emit_parked_car(solid_st, Vector3(ex_car, 0.04, -62.0), -PI * 0.5, car_palette[(ei * 2 + 4) % car_palette.size()], (ei % 4) == 2)

	# =========================================================================================
	# ZONE 2: CENTRAL GEOMETRIC CIVIC ESPLANADE (嘉兴南站北广场中心广场, x = -46..+38, z = -242..-122)
	# =========================================================================================
	# Master light-granite civic square slab (84m x 120m)
	_emit_box(ground_st, Vector3(-4.0, 0.015, -182.0), Vector3(84.0, 0.06, 120.0), c_granite_lt)
	# Iconic Google Earth grid of square concrete/granite paving bays (6 cols x 8 rows)
	for gx_p: float in [-45.5, -31.5, -17.5, -3.5, 10.5, 24.5, 37.5]:
		_emit_box(ground_st, Vector3(gx_p, 0.048, -182.0), Vector3(0.85, 0.02, 118.0), c_granite_dk)
	for gz_p in range(-240, -120, 15):
		_emit_box(ground_st, Vector3(-4.0, 0.048, float(gz_p)), Vector3(83.0, 0.02, 0.85), c_granite_dk)
	# Alternating subtle lighter/medium granite inset panels inside the grid bays
	for col_i in range(6):
		for row_i in range(7):
			if (col_i + row_i) % 2 == 0:
				var bx := -38.5 + float(col_i) * 14.0
				var bz := -232.5 + float(row_i) * 15.0
				_emit_box(ground_st, Vector3(bx, 0.046, bz), Vector3(11.6, 0.015, 12.6), c_granite_md)

	# Twin Sleek Glass Underground-Concourse Exit Pavilions (matching Google Earth teal-glass roofs!)
	for pav_pos: Vector2 in [Vector2(-35.0, -133.0), Vector2(30.0, -133.0), Vector2(-17.0, -155.0), Vector2(16.0, -155.0)]:
		var is_main := pav_pos.y > -145.0
		var pw := 11.5 if is_main else 8.8
		var pd := 15.0 if is_main else 11.5
		var ph := 4.4 if is_main else 3.8
		# Recessed granite stairwell surround & dark shaft
		_emit_box(solid_st, Vector3(pav_pos.x, 0.35, pav_pos.y), Vector3(pw + 1.4, 0.70, pd + 1.4), c_granite_dk)
		_emit_box(ground_st, Vector3(pav_pos.x, 0.06, pav_pos.y), Vector3(pw - 1.2, 0.06, pd - 1.2), c_dark_frame)
		# Slender white steel portal columns & pitched skylight roof frame
		for sx_p: float in [-pw * 0.44, pw * 0.44]:
			for sz_p: float in [-pd * 0.42, 0.0, pd * 0.42]:
				_emit_box(solid_st, Vector3(pav_pos.x + sx_p, ph * 0.5, pav_pos.y + sz_p), Vector3(0.28, ph, 0.28), c_steel)
		_emit_box(solid_st, Vector3(pav_pos.x, ph + 0.16, pav_pos.y), Vector3(pw + 0.8, 0.24, pd + 0.8), c_dark_frame, 0.0, 0.0, 0.08)
		_emit_box(glass_st, Vector3(pav_pos.x, ph + 0.24, pav_pos.y), Vector3(pw + 0.2, 0.14, pd + 0.2), c_glass_teal, 0.0, 0.0, 0.08)
		_emit_box(glass_st, Vector3(pav_pos.x - pw * 0.48, ph * 0.52, pav_pos.y), Vector3(0.12, ph * 0.84, pd * 0.90), c_glass_blue)
		_emit_box(glass_st, Vector3(pav_pos.x + pw * 0.48, ph * 0.52, pav_pos.y), Vector3(0.12, ph * 0.84, pd * 0.90), c_glass_blue)
		_emit_box(glow_st, Vector3(pav_pos.x, ph - 0.18, pav_pos.y), Vector3(pw * 0.65, 0.12, pd * 0.72), c_warm_glow)

	# Modern architectural granite civic signage plinth at south plaza entrance
	_emit_box(solid_st, Vector3(-3.5, 1.35, -128.0), Vector3(14.5, 2.5, 1.1), c_granite_dk)
	_emit_box(solid_st, Vector3(-3.5, 0.25, -128.0), Vector3(16.0, 0.5, 2.2), c_granite_lt)
	JiaxingLandmarks._add_sign_label(plaza_n, "嘉 兴 南 站 · 北 广 场", Vector3(-3.5, 1.65, -128.62), PI, 52, 0.022, Color(0.95, 0.92, 0.84))
	JiaxingLandmarks._add_sign_label(plaza_n, "嘉 兴 南 站 · 北 广 场", Vector3(-3.5, 1.65, -127.38), 0.0, 52, 0.022, Color(0.95, 0.92, 0.84))

	# Lush East & West Tree-Lined Promenade Strips flanking the Central Civic Plaza (matches Google Earth!)
	for prom_x: float in [-49.5, 41.5]:
		_emit_box(solid_st, Vector3(prom_x, 0.18, -182.0), Vector3(7.2, 0.36, 114.0), c_granite_dk)
		JiaxingLandmarks._add_box(plaza_n, Vector3(6.2, 0.30, 112.5), Vector3(prom_x, 0.22, -182.0), lawn_mat, 0.0, 0.0, 0.0, false)
		for pz_t in range(-234, -128, 11):
			ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(prom_x - 1.3, 0.30, float(pz_t)), 1, 0.92, ParkLandscapeBuilder.CAMPHOR)
			if pz_t % 22 == 0:
				ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(prom_x + 1.5, 0.30, float(pz_t) + 5.0), 1, 0.84, ParkLandscapeBuilder.CAMPHOR_LT)
		# Plaza architectural lamp poles along the esplanade edges
		for pz_l in range(-230, -130, 24):
			_emit_lamp_pole(solid_st, glow_st, Vector3(prom_x + (4.2 if prom_x < 0.0 else -4.2), 0.04, float(pz_l)), 7.6)

	# =========================================================================================
	# ZONE 3: EAST BUS TRANSIT HUB (嘉兴南站公交枢纽站, x = +46..+128, z = -238..-124)
	# Real Google Earth Layout: 4 Parallel NORTH-SOUTH Sawtooth/Island Boarding Bays!
	# =========================================================================================
	# Asphalt terminal yard (82m x 114m, strictly clear of x=+143 connector road!)
	_emit_box(bus_ground_st, Vector3(87.0, 0.015, -181.0), Vector3(82.0, 0.06, 114.0), c_asphalt)
	# Perimeter concrete curb & landscaped border
	_emit_box(bus_solid_st, Vector3(87.0, 0.16, -238.2), Vector3(82.0, 0.32, 0.7), c_granite_dk)
	# North & south pedestrian crosswalk zebra stripes across bus lanes
	for cz_eb: float in [-214.0, -146.0]:
		for cx_zb in range(52, 116, 4):
			_emit_box(bus_ground_st, Vector3(float(cx_zb), 0.052, cz_eb), Vector3(1.6, 0.015, 3.2), c_white_line)

	# 4 Parallel North-South Covered Boarding Islands (x = 58, 74, 90, 106; z = -208..-152)
	var eb_xs: Array[float] = [58.0, 74.0, 90.0, 106.0]
	var eb_labels: Array[String] = ["1号站台 · K93/K95", "2号站台 · K96/K98", "3号站台 · 游1/快1", "4号站台 · 城乡公交"]
	for bi in range(eb_xs.size()):
		var bx: float = eb_xs[bi]
		# Raised granite boarding island (3.2m wide x 56m long) + yellow safety edge stripes
		_emit_box(bus_solid_st, Vector3(bx, 0.15, -180.0), Vector3(3.2, 0.30, 56.0), c_granite_lt)
		_emit_box(bus_ground_st, Vector3(bx - 1.38, 0.31, -180.0), Vector3(0.22, 0.02, 54.5), c_yellow)
		_emit_box(bus_ground_st, Vector3(bx + 1.38, 0.31, -180.0), Vector3(0.22, 0.02, 54.5), c_yellow)
		# Sleek cantilevered silver steel + glass skylight canopy running full island length
		_emit_box(bus_solid_st, Vector3(bx, 4.15, -180.0), Vector3(4.3, 0.26, 55.0), c_roof_silver)
		_emit_box(bus_glass_st, Vector3(bx, 4.30, -180.0), Vector3(1.8, 0.12, 52.0), c_glass_teal)
		_emit_box(bus_glow_st, Vector3(bx, 3.98, -180.0), Vector3(0.75, 0.08, 52.0), c_warm_glow)
		# Slender twin steel portal columns every 11m + glass windbreak panels & benches
		for cz_col in range(-204, -152, 11):
			_emit_box(bus_solid_st, Vector3(bx, 2.15, float(cz_col)), Vector3(0.32, 3.90, 0.32), c_steel)
			_emit_box(bus_solid_st, Vector3(bx, 3.92, float(cz_col)), Vector3(3.6, 0.18, 0.24), c_steel)
			if cz_col > -200 and cz_col < -160:
				_emit_box(bus_solid_st, Vector3(bx, 0.72, float(cz_col) + 4.0), Vector3(0.55, 0.45, 2.6), c_dark_frame)
		# Iconic turquoise-roofed glass waiting/dispatch booth at the south head of each island (visible in Google Earth!)
		_emit_box(bus_solid_st, Vector3(bx, 3.55, -151.0), Vector3(4.2, 0.35, 5.2), c_teal_roof)
		_emit_box(bus_glass_st, Vector3(bx, 1.85, -151.0), Vector3(3.4, 3.10, 4.4), c_glass_teal)
		_emit_box(bus_solid_st, Vector3(bx, 1.85, -148.9), Vector3(3.5, 3.2, 0.22), c_dark_frame)
		_emit_box(bus_glow_st, Vector3(bx, 3.20, -151.0), Vector3(2.8, 0.14, 3.6), c_warm_glow)
		# Route sign totem at south head
		JiaxingLandmarks._add_sign_label(bus_hub, eb_labels[bi], Vector3(bx, 4.75, -148.3), 0.0, 34, 0.018, Color(0.55, 0.94, 1.0))

	# Main overhead gateway sign for East Bus Transit Hub
	_emit_box(bus_solid_st, Vector3(82.0, 6.2, -135.0), Vector3(38.0, 1.35, 0.85), c_dark_frame)
	for gx_b: float in [63.5, 100.5]:
		_emit_box(bus_solid_st, Vector3(gx_b, 3.2, -135.0), Vector3(0.65, 6.4, 0.65), c_steel)
	JiaxingLandmarks._add_sign_label(bus_hub, "嘉兴南站公交枢纽站", Vector3(82.0, 6.40, -134.5), 0.0, 64, 0.024, Color(0.35, 0.85, 1.0))
	JiaxingLandmarks._add_sign_label(bus_hub, "JIAXING SOUTH BUS TRANSIT HUB", Vector3(82.0, 5.65, -134.5), 0.0, 26, 0.018, Color(0.95, 0.96, 0.98))

	# 10 Parked Jiaxing New-Energy Electric Buses (6 along N-S boarding bays + 4 in north layover staging!)
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(65.5, 0.04, -196.0), PI * 0.5, Color(0.14, 0.58, 0.88))
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(65.5, 0.04, -168.0), PI * 0.5, Color(0.16, 0.64, 0.42))
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(81.5, 0.04, -184.0), PI * 0.5, Color(0.14, 0.58, 0.88))
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(97.5, 0.04, -192.0), PI * 0.5, Color(0.90, 0.68, 0.14))
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(97.5, 0.04, -164.0), PI * 0.5, Color(0.16, 0.64, 0.42))
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(113.5, 0.04, -178.0), PI * 0.5, Color(0.84, 0.20, 0.18))
	# North staging layover row (angled along north curb, exactly matching Google Earth!)
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(62.0, 0.04, -229.0), 0.15, Color(0.14, 0.58, 0.88))
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(76.0, 0.04, -230.0), 0.15, Color(0.16, 0.64, 0.42))
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(90.0, 0.04, -230.0), 0.15, Color(0.92, 0.72, 0.16))
	_emit_batched_bus(bus_solid_st, bus_glow_st, Vector3(104.0, 0.04, -229.0), 0.15, Color(0.14, 0.58, 0.88))

	# Circular green tree island at SE corner of East Bus Hub (visible in Google Earth!)
	_emit_cyl_approx(bus_solid_st, Vector3(119.0, 0.18, -138.0), 5.6, 0.36, c_granite_dk)
	JiaxingLandmarks._add_cyl(bus_hub, 5.1, 5.2, 0.38, Vector3(119.0, 0.22, -138.0), lawn_mat, 16)
	ParkLandscapeBuilder.plant_tree(bus_hub, Vector3(119.0, 0.35, -138.0), 1, 1.05, ParkLandscapeBuilder.CAMPHOR)

	# =========================================================================================
	# ZONE 4: WEST BUS / COACH & TAXI TRANSFER HUB (x = -144..-54, z = -224..-124)
	# Real Google Earth Layout: 3 Parallel NORTH-SOUTH Boarding Islands + Layover Coaches & Taxis
	# =========================================================================================
	_emit_box(ground_st, Vector3(-99.0, 0.032, -174.0), Vector3(90.0, 0.075, 100.0), c_asphalt)
	for cx_wz in range(-124, -68, 4):
		_emit_box(ground_st, Vector3(float(cx_wz), 0.074, -148.0), Vector3(1.5, 0.015, 3.0), c_white_line)

	var wb_xs: Array[float] = [-114.0, -96.0, -78.0]
	for wbi in range(wb_xs.size()):
		var wbx: float = wb_xs[wbi]
		_emit_box(solid_st, Vector3(wbx, 0.15, -179.0), Vector3(3.2, 0.30, 50.0), c_granite_lt)
		_emit_box(ground_st, Vector3(wbx - 1.38, 0.31, -179.0), Vector3(0.22, 0.02, 48.5), c_yellow)
		_emit_box(ground_st, Vector3(wbx + 1.38, 0.31, -179.0), Vector3(0.22, 0.02, 48.5), c_yellow)
		_emit_box(solid_st, Vector3(wbx, 4.10, -179.0), Vector3(4.2, 0.24, 49.0), c_roof_silver)
		_emit_box(glass_st, Vector3(wbx, 4.24, -179.0), Vector3(1.7, 0.12, 46.0), c_glass_teal)
		_emit_box(glow_st, Vector3(wbx, 3.94, -179.0), Vector3(0.7, 0.08, 46.0), c_warm_glow)
		for wcz in range(-200, -154, 11):
			_emit_box(solid_st, Vector3(wbx, 2.10, float(wcz)), Vector3(0.30, 3.85, 0.30), c_steel)
		# Turquoise south end booth
		_emit_box(solid_st, Vector3(wbx, 3.50, -153.5), Vector3(4.0, 0.34, 4.8), c_teal_roof)
		_emit_box(glass_st, Vector3(wbx, 1.82, -153.5), Vector3(3.2, 3.0, 4.0), c_glass_teal)
	JiaxingLandmarks._add_sign_label(plaza_n, "客运快线 · 出租车 / 网约车换乘区", Vector3(-96.0, 5.15, -150.5), 0.0, 46, 0.020, Color(1.0, 0.86, 0.28))

	# Parked green/white/red coaches & taxis in West Transfer Hub
	_emit_batched_bus(solid_st, glow_st, Vector3(-105.5, 0.04, -186.0), PI * 0.5, Color(0.16, 0.64, 0.42))
	_emit_batched_bus(solid_st, glow_st, Vector3(-87.5, 0.04, -174.0), PI * 0.5, Color(0.16, 0.64, 0.42))
	_emit_batched_bus(solid_st, glow_st, Vector3(-118.0, 0.04, -216.0), 0.12, Color(0.84, 0.18, 0.18))
	_emit_batched_bus(solid_st, glow_st, Vector3(-103.0, 0.04, -217.0), 0.12, Color(0.16, 0.64, 0.42))
	_emit_batched_bus(solid_st, glow_st, Vector3(-88.0, 0.04, -217.0), 0.12, Color(0.14, 0.58, 0.88))
	# Queue of yellow-green Jiaxing taxis in east bay of West Hub
	for ti_q in range(6):
		_emit_parked_car(solid_st, Vector3(-69.5, 0.04, -198.0 + float(ti_q) * 7.5), PI * 0.5, Color(0.20, 0.68, 0.44) if (ti_q % 2 == 0) else Color(0.92, 0.78, 0.18), false)

	# =========================================================================================
	# ZONE 5: EAST MULTI-DECK PARKING GARAGE (P2 社会停车楼, x = +166..+262, z = -226..-142)
	# Exact 1:1 recreation of the 2-level open-roof parking deck east of the Bus Hub!
	# =========================================================================================
	var pg_cx := 214.0
	var pg_cz := -184.0
	var pg_w := 96.0
	var pg_d := 82.0
	var pg_h := 7.2
	# Ground apron & shaded lower parking level interior
	_emit_box(ground_st, Vector3(pg_cx, 0.015, pg_cz), Vector3(pg_w + 6.0, 0.05, pg_d + 6.0), c_asphalt_lt)
	_emit_box(solid_st, Vector3(pg_cx, pg_h * 0.46, pg_cz), Vector3(pg_w - 3.6, pg_h * 0.90, pg_d - 3.6), Color(0.20, 0.21, 0.23))
	# Structural perimeter concrete columns & horizontal precast ventilation louvers (1F + 2F)
	for px_g in range(-46, 48, 8):
		_emit_box(solid_st, Vector3(pg_cx + float(px_g), pg_h * 0.5, pg_cz - pg_d * 0.5 + 0.5), Vector3(0.75, pg_h, 0.75), c_concrete)
		_emit_box(solid_st, Vector3(pg_cx + float(px_g), pg_h * 0.5, pg_cz + pg_d * 0.5 - 0.5), Vector3(0.75, pg_h, 0.75), c_concrete)
	for pz_g in range(-38, 40, 8):
		_emit_box(solid_st, Vector3(pg_cx - pg_w * 0.5 + 0.5, pg_h * 0.5, pg_cz + float(pz_g)), Vector3(0.75, pg_h, 0.75), c_concrete)
		_emit_box(solid_st, Vector3(pg_cx + pg_w * 0.5 - 0.5, pg_h * 0.5, pg_cz + float(pz_g)), Vector3(0.75, pg_h, 0.75), c_concrete)
	# Mid-level deck slab & horizontal precast concrete fascia bands
	for ly_g: float in [3.55, pg_h]:
		_emit_box(solid_st, Vector3(pg_cx, ly_g - 0.25, pg_cz), Vector3(pg_w, 0.50, pg_d), c_concrete)
	# Open Rooftop Parking Deck Surface (y = pg_h = 7.2m) + Perimeter Concrete Safety Parapet Walls
	_emit_box(solid_st, Vector3(pg_cx, pg_h + 0.04, pg_cz), Vector3(pg_w - 1.2, 0.08, pg_d - 1.2), Color(0.62, 0.62, 0.60))
	_emit_box(solid_st, Vector3(pg_cx, pg_h + 0.62, pg_cz - pg_d * 0.5 + 0.35), Vector3(pg_w, 1.15, 0.55), c_concrete)
	_emit_box(solid_st, Vector3(pg_cx, pg_h + 0.62, pg_cz + pg_d * 0.5 - 0.35), Vector3(pg_w, 1.15, 0.55), c_concrete)
	_emit_box(solid_st, Vector3(pg_cx - pg_w * 0.5 + 0.35, pg_h + 0.62, pg_cz), Vector3(0.55, 1.15, pg_d), c_concrete)
	_emit_box(solid_st, Vector3(pg_cx + pg_w * 0.5 - 0.35, pg_h + 0.62, pg_cz), Vector3(0.55, 1.15, pg_d), c_concrete)
	# Two glass-and-concrete elevator/staircase cores on the rooftop deck
	for core_x: float in [pg_cx - 34.0, pg_cx + 34.0]:
		_emit_box(solid_st, Vector3(core_x, pg_h + 2.1, pg_cz + 34.0), Vector3(8.5, 4.2, 6.2), c_concrete_dk)
		_emit_box(glass_st, Vector3(core_x, pg_h + 2.2, pg_cz + 30.8), Vector3(6.8, 3.2, 0.22), c_glass_blue)
		_emit_box(solid_st, Vector3(core_x, pg_h + 4.35, pg_cz + 34.0), Vector3(9.4, 0.32, 7.0), c_roof_silver)
	# Inclined vehicle access ramp on north flank (z = -227)
	_emit_box(solid_st, Vector3(pg_cx + 8.0, pg_h * 0.5, pg_cz - pg_d * 0.5 - 3.6), Vector3(44.0, 0.65, 6.6), c_concrete, 0.0, -atan2(pg_h, 44.0))
	_emit_box(solid_st, Vector3(pg_cx + 8.0, pg_h * 0.5 + 0.72, pg_cz - pg_d * 0.5 - 6.7), Vector3(44.0, 0.90, 0.35), c_concrete, 0.0, -atan2(pg_h, 44.0))
	# Rooftop Parking Aisles, White Stall Lines, Roof Light Poles & 48 Parked Cars!
	var deck_rows: Array[float] = [pg_cz - 31.0, pg_cz - 13.0, pg_cz + 5.0, pg_cz + 23.0]
	var car_seed := 0
	for ri in range(deck_rows.size()):
		var rz: float = deck_rows[ri]
		_emit_box(solid_st, Vector3(pg_cx, pg_h + 0.095, rz), Vector3(84.0, 0.02, 0.22), c_yellow)
		for ci_p in range(14):
			var cx_p := pg_cx - 39.0 + float(ci_p) * 6.0
			_emit_box(solid_st, Vector3(cx_p - 2.9, pg_h + 0.095, rz - 2.6), Vector3(0.14, 0.02, 4.8), c_white_line)
			_emit_box(solid_st, Vector3(cx_p - 2.9, pg_h + 0.095, rz + 2.6), Vector3(0.14, 0.02, 4.8), c_white_line)
			car_seed += 1
			if (car_seed * 7 + ri * 3) % 5 != 0:
				_emit_parked_car(solid_st, Vector3(cx_p, pg_h + 0.09, rz - 2.7), PI * 0.5, car_palette[car_seed % car_palette.size()], (car_seed % 3) == 0)
			if (car_seed * 11 + ri * 5) % 4 != 0:
				_emit_parked_car(solid_st, Vector3(cx_p, pg_h + 0.09, rz + 2.7), -PI * 0.5, car_palette[(car_seed + 4) % car_palette.size()], (car_seed % 4) == 1)
	for rlx: float in [pg_cx - 26.0, pg_cx, pg_cx + 26.0]:
		_emit_lamp_pole(solid_st, glow_st, Vector3(rlx, pg_h + 0.08, pg_cz - 13.0), 6.2)
		_emit_lamp_pole(solid_st, glow_st, Vector3(rlx, pg_h + 0.08, pg_cz + 14.0), 6.2)
	JiaxingLandmarks._add_sign_label(plaza_n, "P2 停车楼 · 社会车辆停车场", Vector3(pg_cx - pg_w * 0.5 - 0.4, 5.4, pg_cz), -PI * 0.5, 48, 0.022, Color(0.45, 0.86, 1.0))

	# =========================================================================================
	# ZONE 6: NORTHEAST GRID-FRAME GLASS HOTEL & GREEN-ROOF PODIUM COMPLEX
	# (x = +170..+264, z = -316..-242 — iconic square white-grid tower + lush green podium roof!)
	# =========================================================================================
	var ne_cx := 218.0
	var ne_cz := -278.0
	# Landscaped arrival stone terrace & sunken courtyard apron
	_emit_box(ground_st, Vector3(ne_cx, 0.02, ne_cz), Vector3(96.0, 0.06, 74.0), c_granite_lt)
	# 3-Storey Commercial/Hotel Podium (88m x 64m, h = 12.0m)
	var pod_h := 12.0
	_emit_box(solid_st, Vector3(ne_cx + 2.0, pod_h * 0.5, ne_cz + 2.0), Vector3(84.0, pod_h, 60.0), c_warm_stone)
	# Recessed dark-glass podium curtain walls + rhythmic stone pilasters
	_emit_box(glass_st, Vector3(ne_cx + 2.0, pod_h * 0.48, ne_cz + 32.1), Vector3(80.0, 9.6, 0.25), c_glass_dark)
	_emit_box(glass_st, Vector3(ne_cx + 2.0, pod_h * 0.48, ne_cz - 28.1), Vector3(80.0, 9.6, 0.25), c_glass_dark)
	_emit_box(glass_st, Vector3(ne_cx - 40.1, pod_h * 0.48, ne_cz + 2.0), Vector3(0.25, 9.6, 56.0), c_glass_dark)
	_emit_box(glass_st, Vector3(ne_cx + 44.1, pod_h * 0.48, ne_cz + 2.0), Vector3(0.25, 9.6, 56.0), c_glass_dark)
	for pi_ne in range(-36, 40, 8):
		_emit_box(solid_st, Vector3(ne_cx + 2.0 + float(pi_ne), pod_h * 0.5, ne_cz + 32.3), Vector3(0.75, pod_h, 0.65), c_ivory)
		_emit_box(solid_st, Vector3(ne_cx + 2.0 + float(pi_ne), pod_h * 0.5, ne_cz - 28.3), Vector3(0.75, pod_h, 0.65), c_ivory)
	# Warm glowing hotel entrance lobby & cantilevered steel-glass porte-cochere canopy (west side)
	_emit_box(glow_st, Vector3(ne_cx - 39.2, 3.2, ne_cz + 4.0), Vector3(1.2, 5.2, 18.0), c_warm_glow)
	_emit_box(solid_st, Vector3(ne_cx - 44.0, 5.8, ne_cz + 4.0), Vector3(9.0, 0.45, 20.0), c_dark_frame)
	_emit_box(glass_st, Vector3(ne_cx - 44.0, 6.08, ne_cz + 4.0), Vector3(8.2, 0.14, 18.5), c_glass_blue)
	# Lush Green Rooftop Terrace Garden Strip on South & East Podium Roof (exact Google Earth signature!)
	JiaxingLandmarks._add_box(plaza_n, Vector3(80.0, 0.35, 11.5), Vector3(ne_cx + 2.0, pod_h + 0.18, ne_cz + 24.5), lawn_mat, 0.0, 0.0, 0.0, false)
	JiaxingLandmarks._add_box(plaza_n, Vector3(22.0, 0.35, 36.0), Vector3(ne_cx + 31.0, pod_h + 0.18, ne_cz - 2.0), lawn_mat, 0.0, 0.0, 0.0, false)
	for rgt_x in range(186, 256, 12):
		ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(float(rgt_x), pod_h + 0.30, ne_cz + 24.5), 1, 0.55, ParkLandscapeBuilder.CAMPHOR_LT)
	# Crisp white podium roof parapet & rooftop HVAC screening on east bay
	_emit_box(solid_st, Vector3(ne_cx + 2.0, pod_h + 0.65, ne_cz + 31.8), Vector3(84.4, 1.3, 0.55), c_grid_white)
	_emit_box(solid_st, Vector3(ne_cx + 31.0, pod_h + 1.4, ne_cz - 14.0), Vector3(14.0, 2.4, 10.0), c_concrete)

	# 14-Storey Square White Exo-Grid Glass Tower (42m x 42m, h = 52.0m, centered at x=+200, z=-285)
	var tw_cx := 200.0
	var tw_cz := -285.0
	var tw_s := 42.0
	var tw_h := 52.0
	# Deep reflective dark Low-E glass tower core (slightly recessed inside white 3D structural waffle grid)
	_emit_box(solid_st, Vector3(tw_cx, pod_h + (tw_h - pod_h) * 0.5, tw_cz), Vector3(tw_s - 1.6, tw_h - pod_h - 0.8, tw_s - 1.6), c_glass_dark)
	_emit_box(glass_st, Vector3(tw_cx, pod_h + (tw_h - pod_h) * 0.5, tw_cz), Vector3(tw_s - 0.9, tw_h - pod_h - 0.6, tw_s - 0.9), c_glass_blue)
	# True 3D sculpted white architectural waffle exo-grid (9 vertical piers x 11 horizontal bands on ALL 4 faces!)
	var half_tw := tw_s * 0.5
	for gi in range(-4, 5):
		var goff := float(gi) * (tw_s / 8.0)
		_emit_box(solid_st, Vector3(tw_cx + goff, pod_h + (tw_h - pod_h) * 0.5, tw_cz + half_tw), Vector3(0.95, tw_h - pod_h, 1.05), c_grid_white)
		_emit_box(solid_st, Vector3(tw_cx + goff, pod_h + (tw_h - pod_h) * 0.5, tw_cz - half_tw), Vector3(0.95, tw_h - pod_h, 1.05), c_grid_white)
		_emit_box(solid_st, Vector3(tw_cx + half_tw, pod_h + (tw_h - pod_h) * 0.5, tw_cz + goff), Vector3(1.05, tw_h - pod_h, 0.95), c_grid_white)
		_emit_box(solid_st, Vector3(tw_cx - half_tw, pod_h + (tw_h - pod_h) * 0.5, tw_cz + goff), Vector3(1.05, tw_h - pod_h, 0.95), c_grid_white)
	for fl_i in range(11):
		var fy_t := pod_h + 3.6 * float(fl_i + 1)
		if fy_t > tw_h:
			break
		_emit_box(solid_st, Vector3(tw_cx, fy_t, tw_cz + half_tw), Vector3(tw_s + 0.9, 0.72, 1.05), c_grid_white)
		_emit_box(solid_st, Vector3(tw_cx, fy_t, tw_cz - half_tw), Vector3(tw_s + 0.9, 0.72, 1.05), c_grid_white)
		_emit_box(solid_st, Vector3(tw_cx + half_tw, fy_t, tw_cz), Vector3(1.05, 0.72, tw_s + 0.9), c_grid_white)
		_emit_box(solid_st, Vector3(tw_cx - half_tw, fy_t, tw_cz), Vector3(1.05, 0.72, tw_s + 0.9), c_grid_white)
	# Crisp tower roof parapet, recessed mechanical crown & skylight
	_emit_box(solid_st, Vector3(tw_cx, tw_h + 0.55, tw_cz), Vector3(tw_s + 0.6, 1.1, tw_s + 0.6), c_grid_white)
	_emit_box(solid_st, Vector3(tw_cx, tw_h + 0.90, tw_cz), Vector3(tw_s - 4.0, 0.6, tw_s - 4.0), c_concrete)
	_emit_box(solid_st, Vector3(tw_cx, tw_h + 2.4, tw_cz), Vector3(22.0, 2.8, 16.0), c_concrete_dk)
	_emit_box(glass_st, Vector3(tw_cx, tw_h + 1.4, tw_cz + 11.0), Vector3(18.0, 0.6, 5.0), c_glass_blue)

	# =========================================================================================
	# ZONE 7: SOUTHWEST COURTYARD ATRIUM CIVIC / BUSINESS BUILDING
	# (x = -224..-158, z = -208..-140 — 5F square building with central glazed skylight atrium!)
	# =========================================================================================
	var sw_cx := -191.0
	var sw_cz := -174.0
	var sw_s := 62.0
	var sw_h := 21.5
	var wing_t := 18.0
	# Landscaped green lawn setback framing the building along 双溪路
	JiaxingLandmarks._add_box(plaza_n, Vector3(72.0, 0.14, 72.0), Vector3(sw_cx, 0.07, sw_cz), lawn_mat, 0.0, 0.0, 0.0, false)
	_emit_box(ground_st, Vector3(sw_cx, 0.09, sw_cz), Vector3(sw_s + 5.0, 0.06, sw_s + 5.0), c_granite_lt)
	# Four sculpted wings forming a genuine hollow square courtyard around the central atrium!
	var wing_off := (sw_s - wing_t) * 0.5
	_emit_box(solid_st, Vector3(sw_cx, sw_h * 0.5, sw_cz - wing_off), Vector3(sw_s, sw_h, wing_t), c_ivory)
	_emit_box(solid_st, Vector3(sw_cx, sw_h * 0.5, sw_cz + wing_off), Vector3(sw_s, sw_h, wing_t), c_ivory)
	_emit_box(solid_st, Vector3(sw_cx - wing_off, sw_h * 0.5, sw_cz), Vector3(wing_t, sw_h, sw_s - wing_t * 2.0), c_ivory)
	_emit_box(solid_st, Vector3(sw_cx + wing_off, sw_h * 0.5, sw_cz), Vector3(wing_t, sw_h, sw_s - wing_t * 2.0), c_ivory)
	# Continuous horizontal recessed dark-glass ribbon windows & projecting warm-ivory stone cornice bands (5 floors)
	for fl_sw in range(5):
		var fy_sw := 2.4 + float(fl_sw) * 3.85
		# Dark glazing band around all 4 outer faces
		_emit_box(glass_st, Vector3(sw_cx, fy_sw, sw_cz + sw_s * 0.5 + 0.12), Vector3(sw_s - 2.4, 2.25, 0.20), c_glass_dark)
		_emit_box(glass_st, Vector3(sw_cx, fy_sw, sw_cz - sw_s * 0.5 - 0.12), Vector3(sw_s - 2.4, 2.25, 0.20), c_glass_dark)
		_emit_box(glass_st, Vector3(sw_cx - sw_s * 0.5 - 0.12, fy_sw, sw_cz), Vector3(0.20, 2.25, sw_s - 2.4), c_glass_dark)
		_emit_box(glass_st, Vector3(sw_cx + sw_s * 0.5 + 0.12, fy_sw, sw_cz), Vector3(0.20, 2.25, sw_s - 2.4), c_glass_dark)
		# Crisp cantilevered stone ribbon spandrel ledge
		_emit_box(solid_st, Vector3(sw_cx, fy_sw + 1.55, sw_cz + sw_s * 0.5 + 0.35), Vector3(sw_s + 0.9, 0.72, 0.65), c_warm_stone)
		_emit_box(solid_st, Vector3(sw_cx, fy_sw + 1.55, sw_cz - sw_s * 0.5 - 0.35), Vector3(sw_s + 0.9, 0.72, 0.65), c_warm_stone)
		_emit_box(solid_st, Vector3(sw_cx - sw_s * 0.5 - 0.35, fy_sw + 1.55, sw_cz), Vector3(0.65, 0.72, sw_s + 0.9), c_warm_stone)
		_emit_box(solid_st, Vector3(sw_cx + sw_s * 0.5 + 0.35, fy_sw + 1.55, sw_cz), Vector3(0.65, 0.72, sw_s + 0.9), c_warm_stone)
	# Central glazed skylight atrium covering the inner courtyard (exact Google Earth signature!)
	_emit_box(solid_st, Vector3(sw_cx, sw_h - 1.2, sw_cz), Vector3(26.5, 0.45, 26.5), c_dark_frame)
	_emit_box(glass_st, Vector3(sw_cx, sw_h - 0.85, sw_cz), Vector3(25.2, 0.30, 25.2), c_glass_blue)
	for sk_i in range(-2, 3):
		_emit_box(solid_st, Vector3(sw_cx + float(sk_i) * 5.0, sw_h - 0.68, sw_cz), Vector3(0.32, 0.32, 25.4), c_steel)
		_emit_box(solid_st, Vector3(sw_cx, sw_h - 0.68, sw_cz + float(sk_i) * 5.0), Vector3(25.4, 0.32, 0.32), c_steel)
	# Stepped roof parapet & east main entrance canopy facing the plaza
	_emit_box(solid_st, Vector3(sw_cx, sw_h + 0.65, sw_cz - wing_off), Vector3(sw_s + 0.6, 1.3, wing_t + 0.4), c_ivory)
	_emit_box(solid_st, Vector3(sw_cx, sw_h + 0.65, sw_cz + wing_off), Vector3(sw_s + 0.6, 1.3, wing_t + 0.4), c_ivory)
	_emit_box(solid_st, Vector3(sw_cx + sw_s * 0.5 + 3.2, 5.2, sw_cz), Vector3(6.4, 0.48, 16.0), c_dark_frame)
	_emit_box(glow_st, Vector3(sw_cx + sw_s * 0.5 + 0.2, 2.8, sw_cz), Vector3(0.5, 4.4, 13.0), c_warm_glow)
	for swt_z in range(-202, -142, 14):
		ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(sw_cx - 34.5, 0.12, float(swt_z)), 1, 0.85, ParkLandscapeBuilder.CAMPHOR)

	# =========================================================================================
	# ZONE 8: WEST HIGH-RISE HOTEL & COMMERCIAL SLAB COMPLEX
	# (x = -224..-162, z = -352..-226 — 4F green-roof terrace podium + 18F modern high-rise slab!)
	# =========================================================================================
	var wh_cx := -194.0
	var wh_cz := -288.0
	var wh_pod_w := 56.0
	var wh_pod_d := 120.0
	var wh_pod_h := 14.2
	# Ground granite podium plinth
	_emit_box(ground_st, Vector3(wh_cx, 0.02, wh_cz), Vector3(wh_pod_w + 8.0, 0.06, wh_pod_d + 8.0), c_granite_lt)
	# 4-Storey Extended Podium Body
	_emit_box(solid_st, Vector3(wh_cx, wh_pod_h * 0.5, wh_cz), Vector3(wh_pod_w, wh_pod_h, wh_pod_d), c_warm_stone)
	for fl_wp in range(4):
		var fy_wp := 2.4 + float(fl_wp) * 3.35
		_emit_box(glass_st, Vector3(wh_cx + wh_pod_w * 0.5 + 0.12, fy_wp, wh_cz), Vector3(0.20, 2.05, wh_pod_d - 3.0), c_glass_dark)
		_emit_box(glass_st, Vector3(wh_cx - wh_pod_w * 0.5 - 0.12, fy_wp, wh_cz), Vector3(0.20, 2.05, wh_pod_d - 3.0), c_glass_dark)
		_emit_box(glass_st, Vector3(wh_cx, fy_wp, wh_cz + wh_pod_d * 0.5 + 0.12), Vector3(wh_pod_w - 3.0, 2.05, 0.20), c_glass_dark)
	for wp_z in range(-344, -230, 8):
		_emit_box(solid_st, Vector3(wh_cx + wh_pod_w * 0.5 + 0.25, wh_pod_h * 0.5, float(wp_z)), Vector3(0.65, wh_pod_h, 0.72), c_ivory)
		_emit_box(solid_st, Vector3(wh_cx - wh_pod_w * 0.5 - 0.25, wh_pod_h * 0.5, float(wp_z)), Vector3(0.65, wh_pod_h, 0.72), c_ivory)
	# Lush Green Rooftop Garden Terrace on South Bay of West Podium (exact match with Google Earth photo!)
	JiaxingLandmarks._add_box(plaza_n, Vector3(wh_pod_w - 5.0, 0.36, 26.0), Vector3(wh_cx, wh_pod_h + 0.18, wh_cz + 43.0), lawn_mat, 0.0, 0.0, 0.0, false)
	for wgt_x in range(-214, -172, 10):
		ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(float(wgt_x), wh_pod_h + 0.30, wh_cz + 43.0), 1, 0.55, ParkLandscapeBuilder.CAMPHOR_LT)
	# Light-stone terrace decking & skylights on middle bay of podium roof
	_emit_box(solid_st, Vector3(wh_cx, wh_pod_h + 0.25, wh_cz + 4.0), Vector3(wh_pod_w - 4.0, 0.50, 44.0), c_granite_lt)
	_emit_box(glass_st, Vector3(wh_cx, wh_pod_h + 0.65, wh_cz + 4.0), Vector3(18.0, 0.35, 22.0), c_glass_blue)
	_emit_box(solid_st, Vector3(wh_cx, wh_pod_h + 0.65, wh_cz + wh_pod_d * 0.5 - 0.3), Vector3(wh_pod_w + 0.6, 1.3, 0.6), c_ivory)

	# 18-Storey Modern Architectural High-Rise Slab Tower on North Half (52m x 28m, h = 64.0m)
	var wt_cz := -326.0
	var wt_w := 52.0
	var wt_d := 28.0
	var wt_h := 64.0
	_emit_box(solid_st, Vector3(wh_cx, wh_pod_h + (wt_h - wh_pod_h) * 0.5, wt_cz), Vector3(wt_w - 1.4, wt_h - wh_pod_h - 0.6, wt_d - 1.4), c_glass_dark)
	_emit_box(glass_st, Vector3(wh_cx, wh_pod_h + (wt_h - wh_pod_h) * 0.5, wt_cz), Vector3(wt_w - 0.7, wt_h - wh_pod_h - 0.4, wt_d - 0.7), c_glass_blue)
	# Crisp silver-white aluminum vertical fins & floor spandrel ribbons on all 4 facades
	for wfi in range(-6, 7):
		var fx_w := float(wfi) * (wt_w / 12.0)
		_emit_box(solid_st, Vector3(wh_cx + fx_w, wh_pod_h + (wt_h - wh_pod_h) * 0.5, wt_cz + wt_d * 0.5), Vector3(0.75, wt_h - wh_pod_h, 0.90), c_grid_white)
		_emit_box(solid_st, Vector3(wh_cx + fx_w, wh_pod_h + (wt_h - wh_pod_h) * 0.5, wt_cz - wt_d * 0.5), Vector3(0.75, wt_h - wh_pod_h, 0.90), c_grid_white)
	for wdi in range(-3, 4):
		var fz_w := float(wdi) * (wt_d / 6.0)
		_emit_box(solid_st, Vector3(wh_cx + wt_w * 0.5, wh_pod_h + (wt_h - wh_pod_h) * 0.5, wt_cz + fz_w), Vector3(0.90, wt_h - wh_pod_h, 0.75), c_grid_white)
		_emit_box(solid_st, Vector3(wh_cx - wt_w * 0.5, wh_pod_h + (wt_h - wh_pod_h) * 0.5, wt_cz + fz_w), Vector3(0.90, wt_h - wh_pod_h, 0.75), c_grid_white)
	for fl_wt in range(14):
		var fy_wt := wh_pod_h + 3.45 * float(fl_wt + 1)
		if fy_wt > wt_h:
			break
		_emit_box(solid_st, Vector3(wh_cx, fy_wt, wt_cz + wt_d * 0.5), Vector3(wt_w + 0.8, 0.62, 0.92), c_grid_white)
		_emit_box(solid_st, Vector3(wh_cx, fy_wt, wt_cz - wt_d * 0.5), Vector3(wt_w + 0.8, 0.62, 0.92), c_grid_white)
		_emit_box(solid_st, Vector3(wh_cx + wt_w * 0.5, fy_wt, wt_cz), Vector3(0.92, 0.62, wt_d + 0.8), c_grid_white)
		_emit_box(solid_st, Vector3(wh_cx - wt_w * 0.5, fy_wt, wt_cz), Vector3(0.92, 0.62, wt_d + 0.8), c_grid_white)
	# Sculpted rooftop parapet & mechanical crown
	_emit_box(solid_st, Vector3(wh_cx, wt_h + 0.75, wt_cz), Vector3(wt_w + 0.6, 1.5, wt_d + 0.6), c_grid_white)
	_emit_box(solid_st, Vector3(wh_cx, wt_h + 2.5, wt_cz), Vector3(30.0, 2.8, 14.0), c_concrete)

	# =========================================================================================
	# ZONE 9: NORTH PLAZA ECO-PARK & PEDESTRIAN CONNECTOR BELT (x = -144..+126, z = -336..-244)
	# Organic landscaped woodland groves, curved park walkways & central civic boulevard to 百川路
	# =========================================================================================
	JiaxingLandmarks._add_box(plaza_n, Vector3(270.0, 0.14, 92.0), Vector3(-9.0, 0.07, -290.0), lawn_mat, 0.0, 0.0, 0.0, false)
	# Central granite pedestrian boulevard axis extending north from the Central Civic Plaza
	_emit_box(ground_st, Vector3(-4.0, 0.15, -290.0), Vector3(16.0, 0.06, 92.0), c_granite_lt)
	_emit_box(ground_st, Vector3(-4.0, 0.18, -290.0), Vector3(12.0, 0.02, 90.0), c_granite_md)
	# Diagonal park connector footpaths linking East/West hubs into the central greenbelt
	_emit_box(ground_st, Vector3(-72.0, 0.16, -288.0), Vector3(110.0, 0.05, 4.2), c_granite_lt, 0.28)
	_emit_box(ground_st, Vector3(64.0, 0.16, -288.0), Vector3(110.0, 0.05, 4.2), c_granite_lt, -0.26)
	# Organic clustered multi-species woodland groves (varied canopy sizes & natural spacing, zero rigid grid!)
	var park_rng := RandomNumberGenerator.new()
	park_rng.seed = 20260701
	var grove_zones: Array = [
		Vector4(-136.0, -48.0, -330.0, -248.0), # West woodland grove
		Vector4(34.0, 122.0, -328.0, -246.0),   # East dense woodland grove
	]
	for gz_v: Vector4 in grove_zones:
		for _ti in range(52):
			var tx_p := park_rng.randf_range(gz_v.x, gz_v.y)
			var tz_p := park_rng.randf_range(gz_v.z, gz_v.w)
			# Keep a small open meadow clearing near the center-west
			if tx_p > -68.0 and tx_p < -46.0 and tz_p > -300.0 and tz_p < -270.0:
				continue
			var sc := park_rng.randf_range(0.76, 1.32)
			var r_sp := park_rng.randi() % 10
			var col_t := ParkLandscapeBuilder.CAMPHOR if r_sp < 5 else (ParkLandscapeBuilder.CAMPHOR_LT if r_sp < 8 else Color(0.28, 0.44, 0.17))
			ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(tx_p, 0.12, tz_p), 1, sc, col_t)
	for pl_z in range(-326, -246, 22):
		_emit_lamp_pole(solid_st, glow_st, Vector3(-13.5, 0.14, float(pl_z)), 7.2)
		_emit_lamp_pole(solid_st, glow_st, Vector3(5.5, 0.14, float(pl_z)), 7.2)

	# Commit all batched meshes (just 8 lightweight draw calls for the ENTIRE North Plaza precinct!)
	_commit_vc_mesh(plaza_n, "NorthPlazaGroundAndPaving", ground_st, 0.84, 0.02, false)
	_commit_vc_mesh(plaza_n, "NorthPlazaArchitecture", solid_st, 0.66, 0.12, true)
	_commit_glass_mesh(plaza_n, "NorthPlazaGlazing", glass_st, 0.72)
	_commit_emissive_mesh(plaza_n, "NorthPlazaNightGlow", glow_st, 1.20)

	_commit_vc_mesh(bus_hub, "BusHubAsphaltAndMarkings", bus_ground_st, 0.86, 0.02, false)
	_commit_vc_mesh(bus_hub, "BusHubCanopiesAndFleet", bus_solid_st, 0.56, 0.20, true)
	_commit_glass_mesh(bus_hub, "BusHubGlazing", bus_glass_st, 0.70)
	_commit_emissive_mesh(bus_hub, "BusHubNightGlow", bus_glow_st, 1.25)

	# Warm plaza architectural night lights
	for lp: Vector3 in [
		Vector3(-4.0, 14.0, -172.0),
		Vector3(84.0, 12.0, -180.0),
		Vector3(-96.0, 12.0, -176.0),
		Vector3(214.0, 16.0, -184.0),
		Vector3(0.0, 12.0, -68.0),
	]:
		var pl := OmniLight3D.new()
		pl.position = lp
		pl.light_color = Color(1.0, 0.88, 0.68)
		pl.omni_range = 76.0
		pl.light_energy = 0.0
		pl.visible = false
		st_root.add_child(pl)
		lights.append(pl)
