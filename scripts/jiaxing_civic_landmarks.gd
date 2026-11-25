class_name JiaxingCivicLandmarks
extends RefCounted

# Realistic bespoke 3D landmarks for Jiaxing's iconic civic, scenic, heritage & aviation sites:
#   - 南湖景区: 会景园码头 (ferry pavilion + boats); 壕股塔, 烟雨楼 and 南湖天地 are built by NanhuBuilder
#   - 嘉兴市人民政府 (Municipal Government civic palace + Citizen Square)
#   - 嘉兴市第一中学 (Historic arched clocktower campus + 400m athletics track stadium)
#   - 月河历史街区 (Jiangnan horse-head gable watertown street, archway, lanterns, canal boats)
#   - 子城遗址公园 (Ancient brick city-gate terrace + Tang/Ming Qiaolou Watch Tower)
#   - 嘉兴中央公园 (Sweeping white steel-and-glass pedestrian landmark bridge + lakeside pavilion)
#   - 嘉兴南湖机场 (IATA: JNH / ZSJX — wing-roofed terminal, 6 jetbridges, ATC tower, 3400m Runway 12/30, airliners, cargo hangars)
#   - 嘉兴商业地标招牌 (五芳斋总店, 戴梦得, 旭辉广场, 万达广场, 八佰伴)


static func build(root: Node3D, lm: Dictionary, lights: Array) -> void:
	NanhuBuilder.build(root, lm, lights) # 湖心岛 烟雨楼, 壕股塔, 南湖天地, 凯悦 hotels
	if lm.has("huijingyuan"):
		_huijingyuan(root, _p(lm["huijingyuan"]["pos"]), lights)
	if lm.has("nanhu_gate"):
		var ng: Dictionary = lm["nanhu_gate"]
		_nanhu_gate(root, _p(ng["pos"]), float(ng.get("angle", -0.25)), lights)
	if lm.has("jiaxing_gov"):
		var g: Dictionary = lm["jiaxing_gov"]
		_jiaxing_gov(root, _p(g["pos"]), float(g.get("angle", 0.0)), lights)
	if lm.has("jiaxing_no1_school"):
		var s: Dictionary = lm["jiaxing_no1_school"]
		_jiaxing_no1_school(root, _p(s["pos"]), float(s.get("angle", 0.0)), lights)
	if lm.has("hanlin_residence"):
		var hl: Dictionary = lm["hanlin_residence"]
		_hanlin_residence_and_skybridge(root, _p(hl["pos"]), _p(hl.get("bridge_pos", [1432.1, 1531.9])), float(hl.get("angle", 0.20)), lights)
	if lm.has("yuehe_quarter"):
		var y: Dictionary = lm["yuehe_quarter"]
		_yuehe_quarter(root, y, lights)
	if lm.has("zicheng_park"):
		var z: Dictionary = lm["zicheng_park"]
		_zicheng_park(root, _p(z["pos"]), float(z.get("angle", 0.05)), lights)
	if lm.has("central_park"):
		var c: Dictionary = lm["central_park"]
		_central_park(root, _p(c["pos"]), float(c.get("angle", 0.0)), lights)
	if lm.has("jiaxing_airport"):
		_jiaxing_airport(root, lm["jiaxing_airport"], lights)
	JiaxingUrbanLandmarks.build(root, lm, lights)
	var spaths: Array = lm.get("scenic_paths", [])
	var spavs: Array = lm.get("scenic_pavilions", [])
	if not spaths.is_empty() or not spavs.is_empty():
		_build_scenic_paths_and_pavilions(root, spaths, spavs)
	var gcomps: Array = lm.get("gated_compounds", [])
	if not gcomps.is_empty():
		ChineseCompoundBuilder.build(root, gcomps, lights)
	for cs in lm.get("commercial_signs", []):
		if cs is Dictionary:
			_commercial_signboard(root, cs)


static func _p(a: Array) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1]))


static func _mat(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	return JiaxingLandmarks._mat(col, rough, metal)


static func _emissive(col: Color, energy: float = 1.6) -> StandardMaterial3D:
	return JiaxingLandmarks._emissive(col, energy)


static func _glass(col: Color, alpha: float = 0.62) -> StandardMaterial3D:
	return JiaxingLandmarks._glass(col, alpha)


static func _box(p: Node3D, sz: Vector3, pos: Vector3, m: Material, ry: float = 0.0, rz: float = 0.0, rx: float = 0.0, sh: bool = true) -> void:
	JiaxingLandmarks._add_box(p, sz, pos, m, ry, rz, rx, sh)


static func _cyl(p: Node3D, rt: float, rb: float, h: float, pos: Vector3, m: Material, segs: int = 12, rot: Vector3 = Vector3.ZERO) -> void:
	JiaxingLandmarks._add_cyl(p, rt, rb, h, pos, m, segs, rot)


static func _sign(p: Node3D, txt: String, pos: Vector3, ry: float, fsz: int, px: float, col: Color) -> void:
	JiaxingLandmarks._add_sign_label(p, txt, pos, ry, fsz, px, col)


static func _add_light(p: Node3D, pos: Vector3, col: Color, rng: float, lights: Array) -> void:
	var pl := OmniLight3D.new()
	pl.position = pos
	pl.light_color = col
	pl.omni_range = rng
	pl.light_energy = 0.0
	pl.visible = false
	p.add_child(pl)
	lights.append(pl)


# =============================================================================================
# 2. 南湖景区 · 会景园景区与游船码头 (Huijingyuan Scenic Garden, Lakeside Pavilions & Ferry Pier)
# =============================================================================================
static func _huijingyuan(parent: Node3D, center: Vector3, lights: Array) -> void:
	var hj := Node3D.new()
	hj.name = "NanhuHuijingyuanPier"
	hj.position = center
	parent.add_child(hj)

	var wall := _mat(Color(0.92, 0.90, 0.86), 0.80)
	var wood := _mat(Color(0.46, 0.24, 0.15), 0.64)
	var wood_red := _mat(Color(0.56, 0.16, 0.12), 0.56)
	var tile := _mat(Color(0.21, 0.23, 0.27), 0.60, 0.06)
	var stone := _mat(Color(0.79, 0.78, 0.74), 0.78)
	var pier := _mat(Color(0.56, 0.44, 0.32), 0.78)
	var glow := _emissive(Color(1.0, 0.82, 0.46), 1.5)
	var foliage := _mat(Color(0.20, 0.45, 0.21), 0.86)

	# --- A. Grand 2-Story Song-Style Huijingyuan Ferry Terminal Hall (会景园渡船大楼) ---
	_box(hj, Vector3(34.0, 0.45, 42.0), Vector3(16.0, 0.22, 0.0), stone, 0.0, 0.0, 0.0, false)
	_box(hj, Vector3(28.0, 6.0, 14.0), Vector3(14.0, 3.2, 0.0), wall)
	_box(hj, Vector3(31.5, 0.75, 17.5), Vector3(14.0, 6.5, 0.0), tile)
	_box(hj, Vector3(22.0, 4.2, 10.2), Vector3(14.0, 8.9, 0.0), wall)
	_box(hj, Vector3(26.5, 1.5, 13.5), Vector3(14.0, 11.4, 0.0), tile)
	for cz_c: float in [-5.5, 0.0, 5.5]:
		_cyl(hj, 0.24, 0.26, 6.0, Vector3(-0.2, 3.2, cz_c), wood_red, 8)
	_sign(hj, "会 景 园 码 头", Vector3(-1.6, 6.2, 0.0), -PI * 0.5, 66, 0.024, Color(0.96, 0.84, 0.34))

	# --- B. Jiangnan Garden Corridors & Water-Front Hexagonal Pavilions (亲水长廊 & 水榭六角亭) ---
	for gs: float in [-1.0, 1.0]:
		_box(hj, Vector3(6.0, 3.6, 26.0), Vector3(18.0, 2.0, gs * 21.0), wall)
		_box(hj, Vector3(7.6, 0.65, 28.0), Vector3(18.0, 4.1, gs * 21.0), tile)
		# Lakeside hexagonal pavilion jutting over Nanhu water via zig-zag timber bridge
		_box(hj, Vector3(18.0, 0.32, 2.8), Vector3(-2.0, 0.35, gs * 31.0), pier, 0.0, 0.0, 0.0, false)
		var px_t := -12.0
		var pz_t := gs * 31.0
		_cyl(hj, 5.2, 5.5, 0.6, Vector3(px_t, 0.35, pz_t), stone, 6)
		for ka in range(6):
			var a := float(ka) * PI / 3.0
			_cyl(hj, 0.18, 0.20, 4.0, Vector3(px_t + cos(a) * 4.0, 2.6, pz_t + sin(a) * 4.0), wood_red, 8)
		_cyl(hj, 1.0, 6.6, 2.2, Vector3(px_t, 5.5, pz_t), tile, 6)
		# Weeping willow groves framing Huijingyuan shore
		_cyl(hj, 0.3, 0.42, 4.2, Vector3(26.0, 2.1, gs * 26.0), wood, 8)
		_cyl(hj, 3.2, 4.6, 4.8, Vector3(26.0, 5.2, gs * 26.0), foliage, 10)

	# --- C. Twin Wooden Ferry Jetties & 3 Painted Nanhu Sightseeing Boats (游湖画舫船) ---
	_box(hj, Vector3(38.0, 0.42, 7.2), Vector3(-14.0, 0.42, 0.0), pier, 0.0, 0.0, 0.0, false)
	for bz: float in [-10.5, 0.0, 10.5]:
		var bx := -36.0 if bz == 0.0 else -24.0
		_box(hj, Vector3(16.0, 1.1, 3.8), Vector3(bx, 0.52, bz), wood)
		_box(hj, Vector3(11.2, 2.2, 3.2), Vector3(bx, 2.0, bz), wall)
		_box(hj, Vector3(10.0, 0.9, 3.3), Vector3(bx, 2.1, bz), glow, 0.0, 0.0, 0.0, false)
		_box(hj, Vector3(13.0, 0.48, 4.0), Vector3(bx, 3.25, bz), tile)
	_add_light(hj, Vector3(-6.0, 8.5, 0.0), Color(1.0, 0.84, 0.56), 54.0, lights)


# =============================================================================================
# 2B. 南湖景区主大门广场 (Nanhu Scenic Area Grand Entrance Archway & Visitor Center)
# =============================================================================================
static func _nanhu_gate(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var ng := Node3D.new()
	ng.name = "NanhuScenicMainGate"
	ng.position = center
	ng.rotation.y = angle
	parent.add_child(ng)

	var stone := _mat(Color(0.84, 0.82, 0.78), 0.72)
	var wall := _mat(Color(0.93, 0.91, 0.86), 0.80)
	var wood_red := _mat(Color(0.58, 0.14, 0.12), 0.52)
	var tile := _mat(Color(0.19, 0.21, 0.26), 0.56, 0.08)
	var gold := _mat(Color(0.95, 0.80, 0.26), 0.28, 0.65)
	var glass := _glass(Color(0.32, 0.50, 0.62), 0.58)

	# Ceremonial granite entrance plaza (flushed y=0.02 so surrounding streets stay clean)
	_box(ng, Vector3(58.0, 0.05, 40.0), Vector3(0.0, 0.02, 0.0), stone, 0.0, 0.0, 0.0, false)
	# Grand 4-Pillar 3-Bay Jiangnan Ceremonial Entrance Archway (南湖旅游区大门牌坊)
	for ax: float in [-12.5, -5.2, 5.2, 12.5]:
		_box(ng, Vector3(1.5, 1.8, 1.8), Vector3(ax, 0.9, 6.0), stone)
		_cyl(ng, 0.42, 0.48, 10.2, Vector3(ax, 5.9, 6.0), wood_red, 10)
	_box(ng, Vector3(27.0, 1.1, 1.3), Vector3(0.0, 9.2, 6.0), wood_red)
	_box(ng, Vector3(13.5, 1.8, 4.0), Vector3(0.0, 11.8, 6.0), tile)
	_box(ng, Vector3(12.2, 0.35, 0.6), Vector3(0.0, 12.9, 6.0), gold)
	for sx: float in [-8.9, 8.9]:
		_box(ng, Vector3(8.6, 1.4, 3.2), Vector3(sx, 10.1, 6.0), tile)
	_sign(ng, "南 湖 旅 游 区", Vector3(0.0, 9.8, 6.8), 0.0, 82, 0.026, Color(0.98, 0.86, 0.34))
	_sign(ng, "南 湖 旅 游 区", Vector3(0.0, 9.8, 5.2), PI, 82, 0.026, Color(0.98, 0.86, 0.34))
	# Flanking Jiangnan-style Visitor Center & Ticket Halls
	for vs: float in [-1.0, 1.0]:
		_box(ng, Vector3(20.0, 6.2, 14.0), Vector3(vs * 21.0, 3.1, -9.0), wall)
		_box(ng, Vector3(16.0, 3.6, 14.3), Vector3(vs * 21.0, 2.4, -9.0), glass)
		_box(ng, Vector3(23.0, 1.4, 16.5), Vector3(vs * 21.0, 6.9, -9.0), tile)
	# Red-Boat Sculptural Monument Emblem in Center Forecourt
	_box(ng, Vector3(10.5, 1.2, 3.4), Vector3(0.0, 0.6, -12.0), stone)
	_box(ng, Vector3(8.5, 1.1, 2.2), Vector3(0.0, 1.75, -12.0), wood_red)
	_box(ng, Vector3(5.6, 1.4, 1.8), Vector3(0.0, 2.8, -12.0), gold)
	_add_light(ng, Vector3(0.0, 11.0, 8.0), Color(1.0, 0.86, 0.56), 54.0, lights)


# =============================================================================================
# 4. 嘉兴市人民政府 (Jiaxing Municipal Government Civic Palace & Citizen Square)
# =============================================================================================
static func _jiaxing_gov(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var gv := Node3D.new()
	gv.name = "JiaxingMunicipalGovernment"
	gv.position = center
	gv.rotation.y = angle
	parent.add_child(gv)

	var cream := _mat(Color(0.89, 0.86, 0.80), 0.66, 0.04)
	var stone_base := _mat(Color(0.68, 0.67, 0.64), 0.74)
	var roof_slate := _mat(Color(0.28, 0.32, 0.38), 0.50, 0.16)
	var glass := _glass(Color(0.24, 0.38, 0.52), 0.72)
	var water := _mat(Color(0.14, 0.42, 0.56), 0.12, 0.22)
	var emblem := _mat(Color(0.88, 0.16, 0.14), 0.34, 0.35)
	var gold := _mat(Color(0.94, 0.78, 0.24), 0.28, 0.70)

	# Raised civic granite plinth & grand entrance stair flight facing South/North Citizen Square
	_box(gv, Vector3(152.0, 3.0, 34.0), Vector3(0.0, 1.5, -18.0), stone_base)
	for si in range(5):
		_box(gv, Vector3(48.0, 0.55, 1.5), Vector3(0.0, 0.28 + float(si) * 0.55, -36.0 - float(4 - si) * 1.3), stone_base)

	# Symmetrical main administration palace (144m wide x 28m tall) + central glass atrium
	_box(gv, Vector3(144.0, 24.0, 26.0), Vector3(0.0, 15.0, -18.0), cream)
	_box(gv, Vector3(54.0, 29.0, 29.0), Vector3(0.0, 17.5, -18.0), cream)
	_box(gv, Vector3(42.0, 20.0, 30.0), Vector3(0.0, 14.5, -18.0), glass)
	# Twin flanking East & West civic wings forming a stately U-courtyard
	for sx: float in [-58.0, 58.0]:
		_box(gv, Vector3(26.0, 21.0, 56.0), Vector3(sx, 12.0, 16.0), cream)
		_box(gv, Vector3(27.5, 1.6, 58.0), Vector3(sx, 23.0, 16.0), roof_slate)
	# 10 monumental white-granite colonnade pillars across the main facade
	for ci in range(-5, 6):
		if ci == 0:
			continue
		var cx := float(ci) * 4.4
		_box(gv, Vector3(1.25, 22.0, 1.45), Vector3(cx, 14.0, -33.2), cream)
	# Crown entablature & subtle sloped civic roof
	_box(gv, Vector3(150.0, 2.2, 31.0), Vector3(0.0, 28.0, -18.0), cream)
	_box(gv, Vector3(58.0, 2.4, 33.0), Vector3(0.0, 33.0, -18.0), roof_slate)

	# National Emblem + "嘉兴市人民政府" plaque
	_cyl(gv, 2.1, 2.1, 0.4, Vector3(0.0, 29.5, -33.5), emblem, 16, Vector3(PI * 0.5, 0.0, 0.0))
	_cyl(gv, 1.3, 1.3, 0.46, Vector3(0.0, 29.5, -33.55), gold, 16, Vector3(PI * 0.5, 0.0, 0.0))
	_sign(gv, "嘉 兴 市 人 民 政 府", Vector3(0.0, 24.8, -33.8), PI, 88, 0.028, Color(0.92, 0.16, 0.14))

	# Citizen Square reflecting fountain basin & ceremonial flagpole
	_cyl(gv, 14.5, 15.0, 0.65, Vector3(0.0, 0.34, -64.0), stone_base, 24)
	JiaxingLandmarks.add_fountain(gv, Vector3(0.0, 0.0, -64.0), 13.4, 0.70, 8.5, 12, 4.2)
	_cyl(gv, 0.14, 0.24, 24.0, Vector3(0.0, 12.0, -48.0), _mat(Color(0.86, 0.88, 0.90), 0.25, 0.8), 10)
	_box(gv, Vector3(4.2, 2.6, 0.1), Vector3(2.1, 22.2, -48.0), emblem)
	_add_light(gv, Vector3(0.0, 18.0, -40.0), Color(1.0, 0.90, 0.72), 62.0, lights)


# =============================================================================================
# 5. 嘉兴市第一中学 (Jiaxing No.1 High School — Authentic Full Campus Layout matching Satellite View:
#    West Gate on 纺工路, North Gate, South Gate on 中环南路, NW/SW Teaching Courtyards & Library,
#    NE 3 Parallel Dormitory Slabs, SE 400m Red Athletics Stadium, White-Roof Indoor Gym & 6 Outdoor Courts)
# =============================================================================================
static func _jiaxing_no1_school(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var sc := Node3D.new()
	sc.name = "JiaxingNo1HighSchool"
	sc.position = center
	sc.rotation.y = angle
	parent.add_child(sc)
	SchoolBuilder.build(sc, lights)


# =============================================================================================
# 5B. 嘉兴一中过街人行天桥 (直达中央有轨电车嘉兴一中站) + 纺工路西侧 瀚林府邸 (Hanlin Residence)
# =============================================================================================
static func _hanlin_residence_and_skybridge(parent: Node3D, hanlin_center: Vector3, bridge_center: Vector3, angle: float, lights: Array) -> void:
	var stone := _mat(Color(0.84, 0.81, 0.76), 0.72)
	var stone_dk := _mat(Color(0.56, 0.54, 0.51), 0.76)
	var cream := _mat(Color(0.90, 0.87, 0.81), 0.68)
	var roof_slate := _mat(Color(0.22, 0.25, 0.30), 0.52, 0.14)
	var steel_white := _mat(Color(0.92, 0.94, 0.96), 0.34, 0.42)
	var bronze := _mat(Color(0.40, 0.32, 0.22), 0.38, 0.62)
	var glass := _glass(Color(0.28, 0.50, 0.66), 0.56)
	var glow := _emissive(Color(1.0, 0.90, 0.64), 1.5)
	var lawn := JiaxingLandmarks.lawn_material()
	var water := _mat(Color(0.16, 0.44, 0.54), 0.16, 0.20)
	var trunk := _mat(Color(0.30, 0.22, 0.16), 0.88)
	var foliage := _mat(Color(0.19, 0.44, 0.20), 0.85)
	var barrier := _mat(Color(0.88, 0.22, 0.16), 0.48)

	# --- A. 嘉兴一中人行过街天桥 (Pedestrian Overpass Skybridge spanning 纺工路 + direct drop to Tram T1 嘉兴一中站!) ---
	var sb := Node3D.new()
	sb.name = "JiaxingNo1Skybridge"
	sb.position = bridge_center
	sb.rotation.y = angle
	parent.add_child(sb)

	# Main elevated steel-and-glass skybridge span at y = +5.75m (clears 4.8m tram & road lanes cleanly!)
	_box(sb, Vector3(39.0, 0.52, 4.6), Vector3(0.0, 5.75, 0.0), steel_white)
	_box(sb, Vector3(39.0, 0.18, 4.8), Vector3(0.0, 5.42, 0.0), bronze)
	# Sleek curved glass side parapets & translucent architectural roof canopy
	for zs: float in [-2.22, 2.22]:
		_box(sb, Vector3(38.5, 1.35, 0.12), Vector3(0.0, 6.65, zs), glass, 0.0, 0.0, 0.0, false)
	_box(sb, Vector3(39.6, 0.24, 5.4), Vector3(0.0, 8.65, 0.0), steel_white)
	for px_r in range(-18, 20, 6):
		_box(sb, Vector3(0.18, 2.7, 0.18), Vector3(float(px_r), 7.25, -2.25), steel_white)
		_box(sb, Vector3(0.18, 2.7, 0.18), Vector3(float(px_r), 7.25, 2.25), steel_white)
	# Supporting steel portal piers strictly outside the carriageway (x = +-16.5m) & glass elevator cores
	for side_x: float in [-17.5, 17.5]:
		_cyl(sb, 0.42, 0.48, 5.6, Vector3(side_x, 2.8, -1.6), steel_white, 10)
		_cyl(sb, 0.42, 0.48, 5.6, Vector3(side_x, 2.8, 1.6), steel_white, 10)
		# Glass elevator shaft + covered stair ramp landing on East (嘉兴一中) & West (瀚林府邸) sidewalks
		_box(sb, Vector3(2.8, 8.2, 2.8), Vector3(side_x + signf(side_x) * 2.2, 4.1, -3.2), glass)
		_box(sb, Vector3(3.1, 0.45, 3.1), Vector3(side_x + signf(side_x) * 2.2, 8.3, -3.2), steel_white)
		# Sloped pedestrian stair flight running north along the sidewalk (y: 5.75 -> 0.0 over 14m)
		_box(sb, Vector3(3.0, 0.45, 15.2), Vector3(side_x + signf(side_x) * 1.6, 2.85, 8.8), steel_white, 0.0, 0.0, 0.37)
		_box(sb, Vector3(3.2, 0.22, 15.4), Vector3(side_x + signf(side_x) * 1.6, 5.45, 8.8), glass, 0.0, 0.0, 0.37, false)
	# Central Station Drop Stairway & Elevator descending directly into the central 嘉兴一中站 tram platform!
	_box(sb, Vector3(2.5, 0.42, 13.8), Vector3(0.0, 2.85, -8.2), steel_white, 0.0, 0.0, -0.39)
	_box(sb, Vector3(2.6, 0.20, 14.0), Vector3(0.0, 5.35, -8.2), glass, 0.0, 0.0, -0.39, false)
	_box(sb, Vector3(2.4, 7.6, 2.4), Vector3(0.0, 3.8, 3.6), glass)
	_box(sb, Vector3(2.7, 0.38, 2.7), Vector3(0.0, 7.7, 3.6), steel_white)
	# Overhead bridge signs facing both north & south along 纺工路!
	_sign(sb, "嘉 兴 一 中 站  ·  过 街 天 桥", Vector3(0.0, 6.9, 2.42), 0.0, 66, 0.024, Color(0.98, 0.90, 0.44))
	_sign(sb, "嘉 兴 一 中 站  ·  过 街 天 桥", Vector3(0.0, 6.9, -2.42), PI, 66, 0.024, Color(0.98, 0.90, 0.44))
	_add_light(sb, Vector3(0.0, 8.0, 0.0), Color(1.0, 0.94, 0.80), 42.0, lights)

	# --- B. 瀚林府邸 (Hanlin Residence — Upscale Chinese Gated Residential Community directly opposite 嘉兴一中!) ---
	var hl := Node3D.new()
	hl.name = "HanlinResidence"
	hl.position = hanlin_center
	hl.rotation.y = angle
	parent.add_child(hl)

	# Compound footprint: local x in [-105 .. +105] (210m E-W), z in [-142 .. +142] (284m N-S)
	_box(hl, Vector3(204.0, 0.05, 278.0), Vector3(0.0, 0.025, 0.0), lawn, 0.0, 0.0, 0.0, false)
	# Internal paved community paths + central courtyard reflecting pool & timber pavilion
	_box(hl, Vector3(178.0, 0.07, 8.0), Vector3(0.0, 0.04, 18.0), stone, 0.0, 0.0, 0.0, false)
	_box(hl, Vector3(8.0, 0.07, 240.0), Vector3(0.0, 0.04, 0.0), stone, 0.0, 0.0, 0.0, false)
	_box(hl, Vector3(26.0, 0.12, 16.0), Vector3(4.0, 0.08, -8.0), water, 0.0, 0.0, 0.0, false)
	_box(hl, Vector3(14.0, 0.4, 10.0), Vector3(4.0, 4.2, -26.0), bronze)
	for px_p: float in [-2.2, 10.2]:
		for pz_p: float in [-30.0, -22.0]:
			_cyl(hl, 0.20, 0.22, 4.2, Vector3(px_p, 2.1, pz_p), stone_dk, 8)

	# Enclosed neoclassical perimeter wall (stone plinth + dark-iron fence) with Grand East Gate facing 纺工路!
	for z_w: float in [-138.0, 138.0]:
		_box(hl, Vector3(204.0, 2.2, 0.6), Vector3(0.0, 1.1, z_w), cream, 0.0, 0.0, 0.0, false)
	_box(hl, Vector3(0.6, 2.2, 276.0), Vector3(-102.0, 1.1, 0.0), cream, 0.0, 0.0, 0.0, false)
	# East wall facing 纺工路 with 26m grand gateway opening at z = +18 (aligned right by the skybridge!)
	_box(hl, Vector3(0.7, 2.4, 140.0), Vector3(102.0, 1.2, -68.0), cream, 0.0, 0.0, 0.0, false)
	_box(hl, Vector3(0.7, 2.4, 104.0), Vector3(102.0, 1.2, 86.0), cream, 0.0, 0.0, 0.0, false)
	# Grand Neoclassical East Gatehouse (瀚林府邸大门) + security lodge & boom barriers facing EAST (+X)
	_box(hl, Vector3(5.2, 1.2, 28.0), Vector3(102.0, 7.6, 18.0), stone)
	_box(hl, Vector3(6.4, 0.85, 30.5), Vector3(102.0, 8.5, 18.0), roof_slate)
	for gz_h: float in [6.0, 12.5, 23.5, 30.0]:
		_box(hl, Vector3(3.0, 7.6, 2.2), Vector3(102.0, 3.8, gz_h), cream)
		_box(hl, Vector3(3.4, 0.65, 2.6), Vector3(102.0, 7.0, gz_h), bronze)
	_box(hl, Vector3(4.2, 3.4, 6.2), Vector3(98.5, 1.7, 18.0), cream)
	_box(hl, Vector3(0.22, 0.16, 4.6), Vector3(101.5, 1.05, 15.2), barrier, 0.0, 0.0, 0.0, false)
	_box(hl, Vector3(0.22, 0.16, 4.6), Vector3(101.5, 1.05, 20.8), barrier, 0.0, 0.0, 0.0, false)
	_sign(hl, "瀚  林  府  邸", Vector3(104.8, 7.7, 18.0), PI * 0.5, 84, 0.030, Color(0.98, 0.86, 0.36))
	_sign(hl, "HANLIN RESIDENCE", Vector3(104.8, 6.3, 18.0), PI * 0.5, 38, 0.022, Color(0.95, 0.96, 0.98))

	# 8 Upscale Stepped Chinese High-Rise Residential Slab Towers (新中式高层住宅楼, 28m..46m)
	var towers := [
		[Vector3(-56.0, 0.0, -96.0), Vector3(52.0, 38.0, 16.0)],
		[Vector3(38.0, 0.0, -96.0), Vector3(54.0, 42.0, 16.0)],
		[Vector3(-56.0, 0.0, -48.0), Vector3(52.0, 34.0, 16.0)],
		[Vector3(46.0, 0.0, -48.0), Vector3(48.0, 36.0, 16.0)],
		[Vector3(-58.0, 0.0, 56.0), Vector3(54.0, 44.0, 16.0)],
		[Vector3(40.0, 0.0, 58.0), Vector3(52.0, 38.0, 16.0)],
		[Vector3(-54.0, 0.0, 106.0), Vector3(56.0, 46.0, 16.0)],
		[Vector3(42.0, 0.0, 106.0), Vector3(54.0, 40.0, 16.0)],
	]
	# The tower bodies themselves are ordinary city buildings (tools/build_jiaxing_map.py HANLIN_TOWERS) so they
	# get the residential facade with window grids and balconies; only the stone podium band, the slate eaves
	# cap and the lit lobby stay here
	for tw: Array in towers:
		var tp: Vector3 = tw[0]
		var ts: Vector3 = tw[1]
		_box(hl, Vector3(ts.x + 0.5, 4.2, ts.z + 0.5), tp + Vector3(0.0, 2.1, 0.0), stone_dk)
		_box(hl, Vector3(ts.x + 2.4, 2.2, ts.z + 2.4), tp + Vector3(0.0, ts.y + 1.1, 0.0), roof_slate)
		_box(hl, Vector3(ts.x * 0.42, 3.0, ts.z * 0.65), tp + Vector3(0.0, ts.y + 3.2, 0.0), cream)
		_box(hl, Vector3(8.0, 3.2, 0.4), tp + Vector3(0.0, 1.8, ts.z * 0.5 + 0.35), glow, 0.0, 0.0, 0.0, false)
	# Lush community garden trees throughout courtyard & along east promenade
	for ti in range(42):
		var tx := -88.0 + float(ti % 7) * 29.0
		var tz := -122.0 + float(ti / 7) * 46.0
		if absf(tx - 4.0) < 16.0 and absf(tz + 8.0) < 14.0:
			continue
		if absf(tz - 18.0) < 10.0 and tx > 55.0:
			continue
		ParkLandscapeBuilder.plant_tree(hl, Vector3(tx, 0.0, tz), 1, 1.0, ParkLandscapeBuilder.CAMPHOR)
	_add_light(hl, Vector3(104.0, 10.0, 18.0), Color(1.0, 0.88, 0.64), 56.0, lights)


# =============================================================================================
# 6. 月河历史街区 (Yuehe Historic Quarter — Dry-Land Archway, Opera Stage & Canal Wupeng Boats)
#    All Yuehe Jiangnan heritage houses are generated in build_jiaxing_map.py strictly on dry land
#    around the real OSM canals & 14 stone arch bridges so ZERO houses ever sit on water!
# =============================================================================================
static func _yuehe_quarter(parent: Node3D, data: Dictionary, lights: Array) -> void:
	var yh := Node3D.new()
	yh.name = "YueheHistoricQuarter"
	yh.position = Vector3.ZERO
	parent.add_child(yh)

	var wood_dark := _mat(Color(0.28, 0.17, 0.12), 0.66)
	var wood_red := _mat(Color(0.56, 0.16, 0.12), 0.56)
	var tile_dark := _mat(Color(0.19, 0.21, 0.25), 0.60, 0.08)
	var stone := _mat(Color(0.72, 0.71, 0.67), 0.80)
	var lantern := _emissive(Color(1.0, 0.32, 0.16), 2.2)

	# --- A. Iconic Jiangnan Timber & Tile Entrance Archway ("月河历史街区" 牌坊) on verified dry land ---
	var arch_pos := _p(data.get("arch_pos", data["pos"]))
	var arch_ang := float(data.get("angle", 0.14))
	var arch := Node3D.new()
	arch.name = "YueheEntranceArchway"
	arch.position = arch_pos
	arch.rotation.y = arch_ang
	yh.add_child(arch)
	for ax: float in [-8.5, -4.2, 4.2, 8.5]:
		_box(arch, Vector3(0.65, 8.4, 0.65), Vector3(ax, 4.2, 0.0), wood_dark)
		_box(arch, Vector3(1.15, 1.2, 1.15), Vector3(ax, 0.6, 0.0), stone)
	_box(arch, Vector3(19.0, 0.9, 1.1), Vector3(0.0, 7.6, 0.0), wood_dark)
	_box(arch, Vector3(11.0, 1.5, 3.2), Vector3(0.0, 9.6, 0.0), tile_dark)
	for ax: float in [-6.4, 6.4]:
		_box(arch, Vector3(6.8, 1.2, 2.6), Vector3(ax, 8.2, 0.0), tile_dark)
	for lx: float in [-6.4, -2.0, 2.0, 6.4]:
		_cyl(arch, 0.30, 0.26, 0.64, Vector3(lx, 6.6, 0.65), lantern, 8)
	_sign(arch, "月 河 历 史 街 区", Vector3(0.0, 8.1, 0.7), 0.0, 66, 0.022, Color(0.98, 0.84, 0.34))
	_sign(arch, "月 河 历 史 街 区", Vector3(0.0, 8.1, -0.7), PI, 66, 0.022, Color(0.98, 0.84, 0.34))
	_add_light(arch, Vector3(0.0, 8.0, 3.0), Color(1.0, 0.72, 0.38), 58.0, lights)

	# --- B. Waterside Historic Opera Stage Pavilion (月河古戏台) on verified dry bank ---
	if data.has("opera_pos"):
		var op_pos := _p(data["opera_pos"])
		var op := Node3D.new()
		op.name = "YueheOperaStage"
		op.position = op_pos
		op.rotation.y = arch_ang
		yh.add_child(op)
		_box(op, Vector3(13.0, 0.9, 10.6), Vector3(0.0, 0.45, 0.0), stone)
		for cx: float in [-5.2, 5.2]:
			for cz: float in [-4.0, 4.0]:
				_cyl(op, 0.20, 0.22, 4.6, Vector3(cx, 3.2, cz), wood_red, 8)
		_box(op, Vector3(11.6, 4.4, 1.4), Vector3(0.0, 3.1, -4.0), wood_dark)
		_box(op, Vector3(14.6, 1.5, 12.2), Vector3(0.0, 6.2, 0.0), tile_dark)
		_box(op, Vector3(10.0, 0.9, 7.6), Vector3(0.0, 7.2, 0.0), tile_dark)
		_sign(op, "月 河 古 戏 台", Vector3(0.0, 5.3, 4.8), 0.0, 48, 0.018, Color(0.98, 0.84, 0.34))
		_add_light(op, Vector3(0.0, 6.5, 4.0), Color(1.0, 0.76, 0.42), 48.0, lights)

	# --- B2. The watertown itself: houses, canal banks, arcades, lanes, lanterns, archway ---
	WatertownBuilder.build(yh, data, lights)

	# --- C. Classic Jiangnan Wupeng Boats (乌篷船) floating strictly inside verified real OSM canal water! ---
	var boats: Array = data.get("boats", [])
	for bd in boats:
		if not (bd is Dictionary):
			continue
		var bp := _p(bd["pos"])
		var bang := float(bd.get("angle", 0.3))
		var b_node := Node3D.new()
		b_node.position = Vector3(bp.x, 0.22, bp.z)
		b_node.rotation.y = bang
		yh.add_child(b_node)
		_box(b_node, Vector3(7.6, 0.68, 2.0), Vector3.ZERO, wood_dark)
		_box(b_node, Vector3(4.4, 1.05, 1.75), Vector3(0.0, 0.75, 0.0), tile_dark)
		_cyl(b_node, 0.16, 0.14, 0.42, Vector3(3.2, 0.85, 0.0), lantern, 6)


# =============================================================================================
# 6B. Batched Scenic Park Walkways & Jiangnan Lakeside Gazebos (南湖/月河/湘家荡 景区步道与景观亭)
# =============================================================================================
static func _build_scenic_paths_and_pavilions(parent: Node3D, paths: Array, pavilions: Array) -> void:
	var holder := Node3D.new()
	holder.name = "JiaxingScenicWalkways"
	parent.add_child(holder)

	var st_stone := SurfaceTool.new()
	st_stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_stone := false
	var st_timber := SurfaceTool.new()
	st_timber.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_timber := false
	var st_red := SurfaceTool.new()
	st_red.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_red := false

	for pd in paths:
		if not (pd is Dictionary):
			continue
		var raw_pts: Array = pd.get("pts", [])
		if raw_pts.size() < 2:
			continue
		var kind := str(pd.get("kind", "stone"))
		var w := clampf(float(pd.get("w", 3.0)), 1.8, 6.5)
		var st_use := st_stone
		var y_top := 0.115
		if kind == "timber":
			st_use = st_timber
			y_top = 0.16
		elif kind == "greenway":
			st_use = st_red
			y_top = 0.125
		for i in range(raw_pts.size() - 1):
			var a := Vector2(float(raw_pts[i][0]), float(raw_pts[i][1]))
			var b := Vector2(float(raw_pts[i + 1][0]), float(raw_pts[i + 1][1]))
			if a.distance_squared_to(b) < 0.25:
				continue
			JiaxingLandmarks._st_box_along(st_use, a, b, w, 0.02, y_top)
			if kind == "timber":
				has_timber = true
			elif kind == "greenway":
				has_red = true
			else:
				has_stone = true

	if has_stone:
		st_stone.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "ScenicStoneWalkways"
		mi.mesh = st_stone.commit()
		var m := _mat(Color(0.81, 0.78, 0.72), 0.84)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	if has_timber:
		st_timber.generate_normals()
		var mi_t := MeshInstance3D.new()
		mi_t.name = "ScenicTimberBoardwalks"
		mi_t.mesh = st_timber.commit()
		var m_t := _mat(Color(0.58, 0.42, 0.27), 0.78)
		m_t.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi_t.material_override = m_t
		mi_t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi_t)
	if has_red:
		st_red.generate_normals()
		var mi_r := MeshInstance3D.new()
		mi_r.name = "ScenicGreenwayTrails"
		mi_r.mesh = st_red.commit()
		var m_r := _mat(Color(0.70, 0.34, 0.26), 0.82)
		m_r.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi_r.material_override = m_r
		mi_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi_r)

	# Traditional Jiangnan Hexagonal Park Gazebos (景观凉亭) placed at verified dry lakeside viewpoints!
	if not pavilions.is_empty():
		var stone_p := _mat(Color(0.82, 0.80, 0.76), 0.78)
		var wood_red := _mat(Color(0.54, 0.16, 0.12), 0.56)
		var tile_p := _mat(Color(0.20, 0.22, 0.26), 0.58, 0.08)
		var gold_p := _mat(Color(0.90, 0.74, 0.24), 0.30, 0.65)
		var trunk_p := _mat(Color(0.32, 0.24, 0.17), 0.88)
		var leaf_p := _mat(Color(0.22, 0.48, 0.22), 0.82)
		for pv in pavilions:
			if not (pv is Dictionary):
				continue
			var pos := _p(pv["pos"])
			var gn := Node3D.new()
			gn.position = pos
			holder.add_child(gn)
			_cyl(gn, 4.2, 4.6, 0.75, Vector3(0.0, 0.38, 0.0), stone_p, 6)
			for ka in range(6):
				var a := float(ka) * TAU / 6.0
				_cyl(gn, 0.15, 0.17, 3.6, Vector3(cos(a) * 3.1, 2.55, sin(a) * 3.1), wood_red, 6)
			_cyl(gn, 0.55, 5.4, 2.2, Vector3(0.0, 5.2, 0.0), tile_p, 6)
			_cyl(gn, 0.10, 0.24, 0.85, Vector3(0.0, 6.6, 0.0), gold_p, 6)
			# Pair of ornamental lakeside trees framing the gazebo
			for side_t: float in [-1.0, 1.0]:
				ParkLandscapeBuilder.plant_tree(gn, Vector3(side_t * 7.8, 0.0, -4.5), 5, 0.85, Color(0.24, 0.44, 0.18))


# =============================================================================================
# 7. 子城遗址公园 · 谯楼 (Zicheng Historic Site — Ancient Brick City Gate Terrace & Qiaolou Tower)
# =============================================================================================
static func _zicheng_park(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var zc := Node3D.new()
	zc.name = "ZichengHistoricSitePark"
	zc.position = center
	zc.rotation.y = angle
	parent.add_child(zc)

	var brick_grey := _mat(Color(0.44, 0.45, 0.47), 0.84)
	var stone := _mat(Color(0.76, 0.75, 0.71), 0.76)
	var plaster := _mat(Color(0.91, 0.88, 0.82), 0.80)
	var wood_red := _mat(Color(0.56, 0.16, 0.13), 0.54, 0.05)
	var tile_dark := _mat(Color(0.20, 0.22, 0.26), 0.58, 0.08)
	var gold := _mat(Color(0.94, 0.78, 0.26), 0.30, 0.68)

	# --- A. Massive Grey-Brick Ancient City Wall Terrace (子城城台) with Central Arched Gate ---
	# Left & Right massive city wall bastions flanking the 6.8m wide central arched gate tunnel
	_box(zc, Vector3(19.0, 7.2, 16.5), Vector3(-13.0, 3.6, 0.0), brick_grey)
	_box(zc, Vector3(19.0, 7.2, 16.5), Vector3(13.0, 3.6, 0.0), brick_grey)
	# Bridge lintel & arch soffit over the central gate portal
	_box(zc, Vector3(8.5, 2.4, 16.5), Vector3(0.0, 6.0, 0.0), brick_grey)
	# Stone battlements / crenellations along top of city wall terrace
	for bi in range(-10, 11):
		_box(zc, Vector3(1.2, 1.1, 0.65), Vector3(float(bi) * 2.1, 7.75, 7.9), brick_grey)
		_box(zc, Vector3(1.2, 1.1, 0.65), Vector3(float(bi) * 2.1, 7.75, -7.9), brick_grey)
	# Flanking carved stone guardian pedestals in front of the gate
	for sx: float in [-5.8, 5.8]:
		_box(zc, Vector3(1.8, 2.2, 2.2), Vector3(sx, 1.1, 11.2), stone)

	# --- B. Iconic 2-Story Tang/Ming Qiaolou Watch Tower (子城谯楼) atop the City Wall ---
	var ty := 7.2
	_box(zc, Vector3(24.0, 5.4, 11.5), Vector3(0.0, ty + 2.7, 0.0), plaster)
	for cx in [-12.2, -6.1, 0.0, 6.1, 12.2]:
		for cz in [-6.0, 6.0]:
			_cyl(zc, 0.26, 0.28, 5.4, Vector3(cx, ty + 2.7, cz), wood_red, 10)
	# Lower sweeping upturned eave roof
	_box(zc, Vector3(29.5, 0.65, 16.2), Vector3(0.0, ty + 5.7, 0.0), tile_dark)
	_box(zc, Vector3(26.5, 0.75, 14.0), Vector3(0.0, ty + 6.35, 0.0), tile_dark)
	# Upper Pavilion Story + Stepped Hip-and-Gable Roof (重檐歇山顶)
	_box(zc, Vector3(17.5, 4.4, 8.8), Vector3(0.0, ty + 8.8, 0.0), plaster)
	for ri in range(5):
		var f := float(ri) / 4.0
		_box(zc, Vector3(lerpf(23.5, 12.0, f), 0.78, lerpf(13.5, 2.0, f)), Vector3(0.0, ty + 11.3 + float(ri) * 0.72, 0.0), tile_dark)
	_box(zc, Vector3(0.7, 1.3, 0.7), Vector3(-5.8, ty + 15.2, 0.0), gold)
	_box(zc, Vector3(0.7, 1.3, 0.7), Vector3(5.8, ty + 15.2, 0.0), gold)
	_sign(zc, "子  城", Vector3(0.0, ty + 10.2, 4.9), 0.0, 88, 0.028, Color(0.98, 0.84, 0.32))

	# Restored 嘉兴府衙 historic timber hall, ceremonial stone axis, enclosing brick ramparts & corner watchtowers!
	var ginkgo := _mat(Color(0.84, 0.68, 0.16), 0.78)
	var lantern := _emissive(Color(1.0, 0.30, 0.14), 2.1)
	var moat_water := _mat(Color(0.15, 0.36, 0.42), 0.18, 0.16)
	# Ancient city moat & carved stone ceremonial arch bridge in front of Qiaolou Gate + red palace lanterns
	_box(zc, Vector3(76.0, 0.08, 9.5), Vector3(0.0, 0.04, 18.5), moat_water, 0.0, 0.0, 0.0, false)
	_box(zc, Vector3(8.4, 0.85, 12.0), Vector3(0.0, 0.45, 18.5), stone)
	for br_s: float in [-4.0, 4.0]:
		_box(zc, Vector3(0.45, 1.1, 12.2), Vector3(br_s, 1.35, 18.5), stone)
	for lx: float in [-11.0, -5.5, 5.5, 11.0]:
		_cyl(zc, 0.28, 0.24, 0.62, Vector3(lx, ty + 4.8, 6.2), lantern, 8)
		_cyl(zc, 0.28, 0.24, 0.62, Vector3(lx, ty + 4.8, -6.2), lantern, 8)

	_box(zc, Vector3(11.0, 0.14, 148.0), Vector3(0.0, 0.07, -76.0), stone, 0.0, 0.0, 0.0, false)
	# Enclosing East / West / North ancient brick ramparts, side wing galleries & corner pavilions
	for ws_z: float in [-1.0, 1.0]:
		_box(zc, Vector3(5.2, 5.6, 118.0), Vector3(ws_z * 42.0, 2.8, -52.0), brick_grey)
		_box(zc, Vector3(9.5, 6.4, 9.5), Vector3(ws_z * 42.0, 3.2, -110.0), brick_grey)
		_box(zc, Vector3(11.2, 2.2, 11.2), Vector3(ws_z * 42.0, 7.4, -110.0), tile_dark)
		# East & West timber side halls (东西配殿) flanking the main courtyard
		_box(zc, Vector3(10.0, 5.0, 32.0), Vector3(ws_z * 26.0, 2.5, -52.0), plaster)
		_box(zc, Vector3(12.2, 1.8, 34.5), Vector3(ws_z * 26.0, 5.8, -52.0), tile_dark)
		# Golden ginkgo trees flanking the ceremonial courtyard axis
		for gz_t: float in [-22.0, -40.0, -64.0, -88.0, -124.0]:
			_cyl(zc, 0.32, 0.42, 4.6, Vector3(ws_z * 16.0, 2.3, gz_t), wood_red, 8)
			_cyl(zc, 2.8, 4.2, 4.4, Vector3(ws_z * 16.0, 6.2, gz_t), ginkgo, 10)
	_box(zc, Vector3(86.0, 5.6, 5.2), Vector3(0.0, 2.8, -110.0), brick_grey)
	# Ceremonial Yimen Gate (仪门) & Main 嘉兴府衙 Great Hall on raised stone plinth
	_box(zc, Vector3(22.0, 5.0, 9.5), Vector3(0.0, 2.5, -26.0), plaster)
	_box(zc, Vector3(25.5, 1.7, 12.0), Vector3(0.0, 5.8, -26.0), tile_dark)
	_box(zc, Vector3(40.0, 1.2, 22.0), Vector3(0.0, 0.6, -54.0), stone)
	_box(zc, Vector3(36.0, 7.6, 17.0), Vector3(0.0, 4.9, -54.0), plaster)
	_box(zc, Vector3(41.0, 2.6, 21.0), Vector3(0.0, 9.8, -54.0), tile_dark)
	_sign(zc, "嘉 兴 府 衙 遗 址", Vector3(0.0, 7.8, -45.2), 0.0, 62, 0.022, Color(0.98, 0.84, 0.34))
	# North Heritage Entrance Archway facing 中山东路 (directly visible from Tram T1!)
	_box(zc, Vector3(28.0, 0.14, 24.0), Vector3(0.0, 0.07, -148.0), stone, 0.0, 0.0, 0.0, false)
	for ax_n: float in [-9.0, -4.5, 4.5, 9.0]:
		_box(zc, Vector3(0.75, 7.8, 0.75), Vector3(ax_n, 3.9, -156.0), wood_red)
		_box(zc, Vector3(1.3, 1.1, 1.3), Vector3(ax_n, 0.55, -156.0), stone)
	_box(zc, Vector3(20.0, 1.2, 2.6), Vector3(0.0, 8.2, -156.0), tile_dark)
	_box(zc, Vector3(11.5, 1.4, 3.2), Vector3(0.0, 9.4, -156.0), tile_dark)
	_sign(zc, "子 城 遗 址 公 园", Vector3(0.0, 7.9, -157.5), PI, 72, 0.024, Color(0.98, 0.84, 0.34))
	_add_light(zc, Vector3(0.0, 12.0, 14.0), Color(1.0, 0.80, 0.44), 56.0, lights)
	_add_light(zc, Vector3(0.0, 10.0, -152.0), Color(1.0, 0.78, 0.42), 52.0, lights)


# =============================================================================================
# 8. 嘉兴中央公园 (Jiaxing Central Park — Iconic White Ribbon Bridge & Lakeside Pavilion)
# =============================================================================================
static func _central_park(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var cp := Node3D.new()
	cp.name = "JiaxingCentralParkLandmark"
	cp.position = center
	cp.rotation.y = angle
	parent.add_child(cp)

	var steel_white := _mat(Color(0.92, 0.94, 0.96), 0.30, 0.35)
	var wood := _mat(Color(0.58, 0.42, 0.28), 0.72)
	var glass := _glass(Color(0.38, 0.62, 0.68), 0.56)
	var warm := _emissive(Color(1.0, 0.90, 0.70), 1.0)
	var stone := _mat(Color(0.80, 0.79, 0.76), 0.74)

	# Sweeping sculpted white steel pedestrian landmark arch bridge (中央公园景观廊桥, 78m span)
	var span := 78.0
	for k in range(14):
		var u0 := -0.5 + float(k) / 14.0
		var u1 := -0.5 + float(k + 1) / 14.0
		var um := (u0 + u1) * 0.5
		var h0 := 0.5 + cos(u0 * PI) * 5.2
		var h1 := 0.5 + cos(u1 * PI) * 5.2
		var dx := (u1 - u0) * span
		var dy := h1 - h0
		var sl := sqrt(dx * dx + dy * dy) + 0.18
		var tilt := atan2(dy, dx)
		_box(cp, Vector3(sl, 0.48, 6.4), Vector3(um * span, (h0 + h1) * 0.5, 0.0), wood, 0.0, tilt)
		# Sculptural sweeping twin steel arch ribbons
		var ah0 := h0 + 1.2 + cos(u0 * PI) * 6.5
		var ah1 := h1 + 1.2 + cos(u1 * PI) * 6.5
		var ady := ah1 - ah0
		var asl := sqrt(dx * dx + ady * ady) + 0.18
		_box(cp, Vector3(asl, 0.55, 0.45), Vector3(um * span, (ah0 + ah1) * 0.5, -3.1), steel_white, 0.0, atan2(ady, dx))
		_box(cp, Vector3(asl, 0.55, 0.45), Vector3(um * span, (ah0 + ah1) * 0.5, 3.1), steel_white, 0.0, atan2(ady, dx))

	# Contemporary circular glass Lakeside Visitor Pavilion & Tea House
	_cyl(cp, 15.5, 16.0, 0.55, Vector3(0.0, 0.28, -42.0), stone, 20)
	_cyl(cp, 12.2, 12.2, 5.2, Vector3(0.0, 3.1, -42.0), glass, 20)
	_cyl(cp, 9.6, 9.6, 4.2, Vector3(0.0, 2.7, -42.0), warm, 16)
	_cyl(cp, 17.5, 17.0, 0.65, Vector3(0.0, 6.0, -42.0), steel_white, 20)
	_sign(cp, "嘉 兴 中 央 公 园", Vector3(0.0, 7.6, -24.5), 0.0, 68, 0.024, Color(0.18, 0.66, 0.36))
	_add_light(cp, Vector3(0.0, 9.5, -32.0), Color(1.0, 0.90, 0.72), 48.0, lights)


# =============================================================================================
# 9. 嘉兴南湖机场 (Jiaxing Nanhu Airport — Terminal, 6 Jetbridges, ATC Tower, 3400m Runway 12/30)
# =============================================================================================
static func _jiaxing_airport(parent: Node3D, cfg: Dictionary, lights: Array) -> void:
	var center := _p(cfg["pos"])
	var angle := float(cfg.get("angle", -0.354))

	var ap := Node3D.new()
	ap.name = "JiaxingNanhuAirport"
	parent.add_child(ap)

	# --- A. Real OSM 3400m Runway 12/30, Parallel Taxiways & Concrete Apron (world coordinates!) ---
	var rwy_raw: Array = cfg.get("runway", [[-10101.0, 5712.0], [-6909.0, 6893.0]])
	var rwy_a := Vector2(float(rwy_raw[0][0]), float(rwy_raw[0][1]))
	var rwy_b := Vector2(float(rwy_raw[1][0]), float(rwy_raw[1][1]))
	var st_asphalt := SurfaceTool.new()
	st_asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_mark := SurfaceTool.new()
	st_mark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_yellow := SurfaceTool.new()
	st_yellow.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Runway 12/30 (50m wide dark aviation asphalt, y = 0.04..0.09)
	JiaxingLandmarks._st_box_along(st_asphalt, rwy_a, rwy_b, 50.0, 0.03, 0.08)
	var r_vec := rwy_b - rwy_a
	var r_len := r_vec.length()
	var r_dir := r_vec / maxf(r_len, 1.0)
	var r_nrm := Vector2(-r_dir.y, r_dir.x)
	# Crisp white runway edge lines, piano-key threshold bars & dashed centerline
	for side: float in [-23.0, 23.0]:
		JiaxingLandmarks._st_box_along(st_mark, rwy_a + r_nrm * side, rwy_b + r_nrm * side, 0.9, 0.08, 0.11)
	for end_d: float in [24.0, r_len - 64.0]:
		for pi in range(-5, 6):
			if pi == 0:
				continue
			var p0 := rwy_a + r_dir * end_d + r_nrm * (float(pi) * 3.8)
			JiaxingLandmarks._st_box_along(st_mark, p0, p0 + r_dir * 38.0, 1.9, 0.08, 0.11)
	var ds := 95.0
	while ds < r_len - 95.0:
		var c0 := rwy_a + r_dir * ds
		JiaxingLandmarks._st_box_along(st_mark, c0, c0 + r_dir * 32.0, 1.2, 0.08, 0.11)
		ds += 62.0

	# Real OSM Taxiways (23m wide asphalt + yellow guidance centerline)
	for tw: Array in cfg.get("taxiways", []):
		for ti in range(tw.size() - 1):
			var ta := Vector2(float(tw[ti][0]), float(tw[ti][1]))
			var tb := Vector2(float(tw[ti + 1][0]), float(tw[ti + 1][1]))
			JiaxingLandmarks._st_box_along(st_asphalt, ta, tb, 23.0, 0.02, 0.07)
			JiaxingLandmarks._st_box_along(st_yellow, ta, tb, 0.65, 0.07, 0.10)

	JiaxingLandmarks._emit_st(ap, "AirportRunwayAndTaxiways", st_asphalt, _mat(Color(0.22, 0.23, 0.25), 0.88), false)
	JiaxingLandmarks._emit_st(ap, "AirportRunwayMarkings", st_mark, _mat(Color(0.95, 0.96, 0.96), 0.72), false)
	JiaxingLandmarks._emit_st(ap, "AirportTaxiwayLines", st_yellow, _mat(Color(0.95, 0.78, 0.14), 0.65), false)

	# --- B. Modern Wing-Roofed Passenger Terminal Complex (local space aligned with Runway 12/30!) ---
	var tm := Node3D.new()
	tm.name = "JiaxingAirportTerminal"
	tm.position = center
	tm.rotation.y = angle
	ap.add_child(tm)

	var roof_silver := _mat(Color(0.87, 0.90, 0.93), 0.26, 0.56)
	var roof_rib := _mat(Color(0.66, 0.71, 0.77), 0.34, 0.58)
	var steel_white := _mat(Color(0.92, 0.94, 0.96), 0.34, 0.26)
	var concrete := _mat(Color(0.75, 0.75, 0.73), 0.80)
	var glass_blue := _glass(Color(0.24, 0.44, 0.60), 0.68)
	var warm_hall := _emissive(Color(1.0, 0.92, 0.76), 1.0)
	var sign_red := Color(0.90, 0.14, 0.14)

	# Concrete aircraft apron slab south of Terminal (flush y=0.04)
	_box(tm, Vector3(340.0, 0.08, 175.0), Vector3(0.0, 0.04, 128.0), concrete, 0.0, 0.0, 0.0, false)
	# Terminal main concourse building (204m wide x 66m deep)
	_box(tm, Vector3(196.0, 15.5, 58.0), Vector3(0.0, 8.2, 0.0), warm_hall, 0.0, 0.0, 0.0, false)
	_box(tm, Vector3(204.0, 17.5, 0.55), Vector3(0.0, 9.0, -31.0), glass_blue)
	_box(tm, Vector3(204.0, 17.5, 0.55), Vector3(0.0, 9.0, 31.0), glass_blue)
	_box(tm, Vector3(0.55, 17.5, 62.0), Vector3(-102.0, 9.0, 0.0), glass_blue)
	_box(tm, Vector3(0.55, 17.5, 62.0), Vector3(102.0, 9.0, 0.0), glass_blue)
	for ci in range(-10, 11):
		var cx := float(ci) * 10.0
		_box(tm, Vector3(0.75, 19.0, 0.95), Vector3(cx, 9.5, -31.8), steel_white)
		_box(tm, Vector3(0.65, 18.0, 0.80), Vector3(cx, 9.0, 31.6), steel_white)

	# Sweeping 18-segment outstretched aviation wing silver roof (224m span x 82m deep!)
	var span_x := 224.0
	for k in range(18):
		var u0 := -0.5 + float(k) / 18.0
		var u1 := -0.5 + float(k + 1) / 18.0
		var um := (u0 + u1) * 0.5
		var y0 := 19.5 + cos(u0 * PI) * 5.8 + pow(absf(u0 * 2.0), 3.0) * 3.2
		var y1 := 19.5 + cos(u1 * PI) * 5.8 + pow(absf(u1 * 2.0), 3.0) * 3.2
		var dx := (u1 - u0) * span_x
		var dy := y1 - y0
		var sw := sqrt(dx * dx + dy * dy) + 0.4
		_box(tm, Vector3(sw, 1.15, 82.0), Vector3(um * span_x, (y0 + y1) * 0.5, -4.0), roof_silver, 0.0, atan2(dy, dx))
		_box(tm, Vector3(0.7, 0.85, 80.0), Vector3(u0 * span_x, y0 - 0.7, -4.0), roof_rib)

	# Iconic Red Airport Roof Signage ("嘉兴南湖机场" / "JIAXING NANHU AIRPORT")
	_sign(tm, "嘉 兴 南 湖 机 场", Vector3(0.0, 27.8, -45.6), PI, 136, 0.044, sign_red)
	_sign(tm, "JIAXING NANHU AIRPORT · JNH", Vector3(0.0, 25.0, -45.6), PI, 44, 0.030, Color(0.95, 0.96, 0.98))
	_sign(tm, "嘉 兴 南 湖 机 场", Vector3(0.0, 27.8, 37.5), 0.0, 128, 0.040, sign_red)

	# 6 Articulated Glass Passenger Boarding Jetbridges (登机廊桥) + 3 Docked Commercial Airliners
	for ji in range(6):
		var jx := -75.0 + float(ji) * 30.0
		_box(tm, Vector3(6.0, 8.5, 16.0), Vector3(jx, 4.25, 39.0), steel_white)
		_box(tm, Vector3(3.4, 3.2, 24.0), Vector3(jx, 5.2, 58.0), glass_blue)
		_cyl(tm, 0.65, 0.75, 4.6, Vector3(jx, 2.3, 68.0), roof_rib, 8)
		if ji in [1, 3, 4]:
			_add_airliner(tm, Vector3(jx + 4.5, 0.1, 86.0), PI, ji == 3)

	# 1 Extra Airliner on East Apron Stand
	_add_airliner(tm, Vector3(135.0, 0.1, 128.0), -0.45, false)

	# --- C. 58m Air Traffic Control Tower (空管塔台) East of Terminal ---
	var tc := Vector3(165.0, 0.0, -18.0)
	_cyl(tm, 4.6, 7.2, 42.0, tc + Vector3(0.0, 21.0, 0.0), steel_white, 12)
	_cyl(tm, 9.2, 5.6, 5.2, tc + Vector3(0.0, 44.5, 0.0), concrete, 8)
	_cyl(tm, 9.8, 8.8, 5.8, tc + Vector3(0.0, 49.8, 0.0), _glass(Color(0.22, 0.56, 0.52), 0.70), 8)
	_cyl(tm, 10.6, 10.6, 1.2, tc + Vector3(0.0, 53.2, 0.0), roof_silver, 8)
	_cyl(tm, 2.4, 2.4, 3.8, tc + Vector3(0.0, 55.6, 0.0), steel_white, 12) # Radar radome
	_cyl(tm, 0.18, 0.18, 5.5, tc + Vector3(0.0, 59.5, 0.0), _emissive(Color(1.0, 0.2, 0.15), 2.0), 8)

	# --- D. YuanTong / Yangtze River Delta Air-Cargo Hub Hangars (嘉兴航空物流枢纽) ---
	for hx: float in [-210.0, -135.0]:
		_box(tm, Vector3(64.0, 18.0, 48.0), Vector3(hx, 9.0, 62.0), _mat(Color(0.76, 0.80, 0.84), 0.52, 0.22))
		_box(tm, Vector3(66.0, 2.6, 50.0), Vector3(hx, 19.2, 62.0), roof_rib)
		_box(tm, Vector3(48.0, 13.0, 0.6), Vector3(hx, 6.5, 86.2), _mat(Color(0.28, 0.34, 0.42), 0.48, 0.35))
	_sign(tm, "嘉兴全球航空物流枢纽", Vector3(-172.0, 16.5, 86.6), 0.0, 74, 0.032, Color(0.98, 0.88, 0.36))

	_add_light(tm, Vector3(0.0, 18.0, -52.0), Color(1.0, 0.92, 0.78), 75.0, lights)
	_add_light(tm, Vector3(0.0, 18.0, 82.0), Color(0.90, 0.95, 1.0), 85.0, lights)


static func _add_airliner(parent: Node3D, pos: Vector3, rot_y: float, blue_livery: bool) -> void:
	var pl := Node3D.new()
	pl.position = pos
	pl.rotation.y = rot_y
	parent.add_child(pl)

	var body := _mat(Color(0.95, 0.96, 0.98), 0.22, 0.20)
	var wing := _mat(Color(0.84, 0.86, 0.89), 0.30, 0.32)
	var tail := _mat(Color(0.10, 0.34, 0.72) if blue_livery else Color(0.78, 0.14, 0.16), 0.28, 0.20)
	var eng := _mat(Color(0.28, 0.30, 0.34), 0.40, 0.65)
	var glass := _mat(Color(0.08, 0.12, 0.18), 0.12, 0.55)

	# Narrow-body / C919 / A320 airliner (~38m long, 36m wingspan)
	_cyl(pl, 2.05, 2.05, 31.0, Vector3(0.0, 3.6, 0.0), body, 12, Vector3(PI * 0.5, 0.0, 0.0))
	_cyl(pl, 0.4, 2.05, 5.2, Vector3(0.0, 3.3, 18.0), body, 12, Vector3(PI * 0.5, 0.0, 0.0))
	_cyl(pl, 2.05, 0.35, 6.2, Vector3(0.0, 3.8, -18.5), body, 12, Vector3(PI * 0.5, 0.0, 0.0))
	_box(pl, Vector3(2.2, 0.75, 1.8), Vector3(0.0, 4.15, 16.4), glass, 0.0, 0.0, 0.0, false)
	# Swept main wings + twin underwing turbofan engines
	_box(pl, Vector3(17.5, 0.55, 4.6), Vector3(-9.2, 3.0, -1.2), wing, 0.38, -0.05)
	_box(pl, Vector3(17.5, 0.55, 4.6), Vector3(9.2, 3.0, -1.2), wing, -0.38, 0.05)
	for side: float in [-5.8, 5.8]:
		_cyl(pl, 1.05, 1.05, 3.8, Vector3(side, 1.85, 1.8), eng, 10, Vector3(PI * 0.5, 0.0, 0.0))
	# Vertical tail fin & horizontal stabilizers
	_box(pl, Vector3(0.45, 7.6, 4.8), Vector3(0.0, 7.8, -17.5), tail, 0.0, 0.0, -0.32)
	_box(pl, Vector3(12.0, 0.38, 2.6), Vector3(0.0, 4.2, -18.0), wing)


# =============================================================================================
# 10. Iconic Jiaxing Commercial Mall / Flagship Brand Signboards (商业地标招牌)
# =============================================================================================
static func _commercial_signboard(parent: Node3D, cs: Dictionary) -> void:
	var pos := _p(cs["pos"])
	var ang := float(cs.get("angle", 0.0))
	var ca: Array = cs.get("color", [0.76, 0.14, 0.14])
	var col := Color(float(ca[0]), float(ca[1]), float(ca[2]))

	var sb := Node3D.new()
	sb.position = pos
	sb.rotation.y = ang
	parent.add_child(sb)

	var board := _mat(col, 0.32, 0.16)
	var trim := _mat(Color(0.92, 0.90, 0.86), 0.35, 0.45)
	# Sleek vertical architectural commercial pylon totem at plaza edge
	_box(sb, Vector3(14.5, 4.6, 0.9), Vector3(0.0, 8.2, 0.0), board)
	_box(sb, Vector3(15.0, 0.25, 1.05), Vector3(0.0, 10.55, 0.0), trim)
	_box(sb, Vector3(15.0, 0.25, 1.05), Vector3(0.0, 5.85, 0.0), trim)
	for px: float in [-5.8, 5.8]:
		_box(sb, Vector3(0.55, 6.0, 0.65), Vector3(px, 3.0, 0.0), trim)
	_sign(sb, str(cs.get("name", "")), Vector3(0.0, 8.8, 0.52), 0.0, 72, 0.024, Color(1.0, 0.96, 0.82))
	_sign(sb, str(cs.get("sub", "")), Vector3(0.0, 6.9, 0.52), 0.0, 32, 0.020, Color(0.95, 0.96, 0.98))
	_sign(sb, str(cs.get("name", "")), Vector3(0.0, 8.8, -0.52), PI, 72, 0.024, Color(1.0, 0.96, 0.82))
