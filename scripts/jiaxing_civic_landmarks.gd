class_name JiaxingCivicLandmarks
extends RefCounted

# Realistic bespoke 3D landmarks for Jiaxing's iconic civic, scenic, heritage & aviation sites:
#   - 南湖景区: 壕股塔 (7-story Song pagoda), 会景园码头 (ferry pavilion + boats), 南湖天地 (waterfront district)
#   - 嘉兴市人民政府 (Municipal Government civic palace + Citizen Square)
#   - 嘉兴市第一中学 (Historic arched clocktower campus + 400m athletics track stadium)
#   - 月河历史街区 (Jiangnan horse-head gable watertown street, archway, lanterns, canal boats)
#   - 子城遗址公园 (Ancient brick city-gate terrace + Tang/Ming Qiaolou Watch Tower)
#   - 嘉兴中央公园 (Sweeping white steel-and-glass pedestrian landmark bridge + lakeside pavilion)
#   - 嘉兴南湖机场 (IATA: JNH / ZSJX — wing-roofed terminal, 6 jetbridges, ATC tower, 3400m Runway 12/30, airliners, cargo hangars)
#   - 嘉兴商业地标招牌 (五芳斋总店, 戴梦得, 旭辉广场, 万达广场, 八佰伴)


static func build(root: Node3D, lm: Dictionary, lights: Array) -> void:
	if lm.has("haogu_pagoda"):
		_haogu_pagoda(root, _p(lm["haogu_pagoda"]["pos"]), lights)
	if lm.has("huijingyuan"):
		_huijingyuan(root, _p(lm["huijingyuan"]["pos"]), lights)
	if lm.has("nanhu_gate"):
		var ng: Dictionary = lm["nanhu_gate"]
		_nanhu_gate(root, _p(ng["pos"]), float(ng.get("angle", -0.25)), lights)
	if lm.has("nanhu_tiandi"):
		_nanhu_tiandi(root, _p(lm["nanhu_tiandi"]["pos"]), lights)
	if lm.has("jiaxing_gov"):
		var g: Dictionary = lm["jiaxing_gov"]
		_jiaxing_gov(root, _p(g["pos"]), float(g.get("angle", 0.0)), lights)
	if lm.has("jiaxing_no1_school"):
		var s: Dictionary = lm["jiaxing_no1_school"]
		_jiaxing_no1_school(root, _p(s["pos"]), float(s.get("angle", 0.0)), lights)
	if lm.has("yuehe_quarter"):
		var y: Dictionary = lm["yuehe_quarter"]
		_yuehe_quarter(root, _p(y["pos"]), float(y.get("angle", 0.14)), lights)
	if lm.has("zicheng_park"):
		var z: Dictionary = lm["zicheng_park"]
		_zicheng_park(root, _p(z["pos"]), float(z.get("angle", 0.05)), lights)
	if lm.has("central_park"):
		var c: Dictionary = lm["central_park"]
		_central_park(root, _p(c["pos"]), float(c.get("angle", 0.0)), lights)
	if lm.has("jiaxing_airport"):
		_jiaxing_airport(root, lm["jiaxing_airport"], lights)
	JiaxingUrbanLandmarks.build(root, lm, lights)
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
# 1. 南湖景区 · 壕股塔 (7-Story Song-Style Octagonal Pagoda on Nanhu's West/North Shore)
# =============================================================================================
static func _haogu_pagoda(parent: Node3D, center: Vector3, lights: Array) -> void:
	var pg := Node3D.new()
	pg.name = "NanhuHaoguPagoda"
	pg.position = center
	parent.add_child(pg)

	var stone := _mat(Color(0.82, 0.80, 0.76), 0.76)
	var wall_cream := _mat(Color(0.91, 0.88, 0.81), 0.82)
	var wood_red := _mat(Color(0.56, 0.16, 0.12), 0.56, 0.04)
	var tile_dark := _mat(Color(0.20, 0.22, 0.26), 0.58, 0.08)
	var gold := _mat(Color(0.90, 0.74, 0.22), 0.28, 0.72)
	var warm := _emissive(Color(1.0, 0.80, 0.44), 1.4)

	# Stepped octagonal stone base terrace
	_cyl(pg, 11.5, 12.2, 2.2, Vector3(0.0, 1.1, 0.0), stone, 8)
	_cyl(pg, 9.6, 10.2, 1.0, Vector3(0.0, 2.7, 0.0), stone, 8)

	# 7 tapering octagonal Song-style stories (~42m total height)
	var y_cur := 3.2
	for lv in range(7):
		var frac := float(lv) / 6.0
		var r_body := lerpf(6.8, 3.6, frac)
		var h_story := lerpf(5.2, 3.6, frac)
		# Cream brick octagonal core
		_cyl(pg, r_body * 0.96, r_body, h_story, Vector3(0.0, y_cur + h_story * 0.5, 0.0), wall_cream, 8)
		# Vermilion wooden balcony collar & window glow bands
		_cyl(pg, r_body + 0.45, r_body + 0.45, 0.75, Vector3(0.0, y_cur + 0.55, 0.0), wood_red, 8)
		for side in range(4):
			var ang := float(side) * PI * 0.5
			_box(pg, Vector3(1.1, 1.9, 0.25), Vector3(cos(ang) * (r_body - 0.05), y_cur + h_story * 0.52, sin(ang) * (r_body - 0.05)), warm, -ang + PI * 0.5, 0.0, 0.0, false)
		# Upturned dark-tile octagonal eave roof
		_cyl(pg, r_body * 0.92, r_body + 2.35, 1.45, Vector3(0.0, y_cur + h_story + 0.45, 0.0), tile_dark, 8)
		y_cur += h_story + 0.95

	# Steep pyramidal spire cap + golden bronze finial (塔刹)
	_cyl(pg, 0.4, 4.4, 3.6, Vector3(0.0, y_cur + 1.8, 0.0), tile_dark, 8)
	_cyl(pg, 0.12, 0.42, 6.2, Vector3(0.0, y_cur + 6.4, 0.0), gold, 10)
	_cyl(pg, 0.65, 0.65, 0.55, Vector3(0.0, y_cur + 5.2, 0.0), gold, 12)
	_sign(pg, "壕 股 塔", Vector3(0.0, 7.2, 7.6), 0.0, 68, 0.024, Color(0.96, 0.84, 0.34))

	# Lakeside temple courtyard flanking halls
	_box(pg, Vector3(22.0, 5.2, 10.0), Vector3(-20.0, 2.6, 8.0), wall_cream)
	_box(pg, Vector3(24.5, 1.4, 12.2), Vector3(-20.0, 5.8, 8.0), tile_dark)
	_add_light(pg, Vector3(0.0, 14.0, 12.0), Color(1.0, 0.80, 0.46), 46.0, lights)


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
# 3. 南湖景区 · 南湖天地 (Nanhu Tiandi Lakeside Heritage & Modern Commercial Complex)
# =============================================================================================
static func _nanhu_tiandi(parent: Node3D, center: Vector3, lights: Array) -> void:
	var td := Node3D.new()
	td.name = "NanhuTiandiDistrict"
	td.position = center
	parent.add_child(td)

	var brick := _mat(Color(0.58, 0.27, 0.21), 0.78)
	var cream := _mat(Color(0.88, 0.86, 0.81), 0.76)
	var slate := _mat(Color(0.22, 0.24, 0.28), 0.52, 0.12)
	var deck := _mat(Color(0.58, 0.46, 0.34), 0.80)
	var glass := _glass(Color(0.32, 0.48, 0.60), 0.62)
	var warm := _emissive(Color(1.0, 0.88, 0.66), 1.0)

	# Lakeside timber waterfront promenade deck (flush low height y=0.05)
	_box(td, Vector3(18.0, 0.08, 175.0), Vector3(-42.0, 0.04, 0.0), deck, 0.0, 0.0, 0.0, false)

	# 5 staggered contemporary Jiangnan glass-and-slate waterfront pavilions (嘉绢印象 / 鸳湖里弄)
	var specs := [
		[Vector3(-12.0, 0.0, -64.0), Vector3(34.0, 11.0, 24.0), false],
		[Vector3(14.0, 0.0, -26.0), Vector3(42.0, 13.5, 28.0), true],  # Historic red-brick silk mill
		[Vector3(-10.0, 0.0, 16.0), Vector3(38.0, 11.5, 26.0), false],
		[Vector3(18.0, 0.0, 56.0), Vector3(36.0, 10.5, 24.0), false],
		[Vector3(-14.0, 0.0, 88.0), Vector3(30.0, 9.5, 22.0), true],
	]
	for sp: Array in specs:
		var p: Vector3 = sp[0]
		var sz: Vector3 = sp[1]
		var is_brick: bool = sp[2]
		_box(td, sz, p + Vector3(0.0, sz.y * 0.5, 0.0), brick if is_brick else cream)
		_box(td, Vector3(sz.x + 0.3, 4.2, sz.z - 4.0), p + Vector3(0.0, 2.2, 0.0), glass)
		_box(td, Vector3(sz.x - 1.5, 3.6, sz.z - 5.0), p + Vector3(0.0, 2.0, 0.0), warm, 0.0, 0.0, 0.0, false)
		# Crisp pitched Jiangnan dark-slate gable roof
		_box(td, Vector3(sz.x + 3.2, 0.55, sz.z * 0.62), p + Vector3(0.0, sz.y + 1.5, -sz.z * 0.24), slate, 0.0, 0.0, 0.38)
		_box(td, Vector3(sz.x + 3.2, 0.55, sz.z * 0.62), p + Vector3(0.0, sz.y + 1.5, sz.z * 0.24), slate, 0.0, 0.0, -0.38)

	# Iconic illuminated waterfront landmark sign "南 湖 天 地" facing Nanhu Lake
	_box(td, Vector3(1.2, 7.0, 18.0), Vector3(-36.0, 3.5, 0.0), slate)
	_sign(td, "南 湖 天 地", Vector3(-36.8, 4.4, 0.0), -PI * 0.5, 86, 0.028, Color(0.98, 0.86, 0.42))
	_sign(td, "NANHU TIANDI", Vector3(-36.8, 2.3, 0.0), -PI * 0.5, 34, 0.022, Color(0.95, 0.96, 0.98))
	_add_light(td, Vector3(-28.0, 10.0, 0.0), Color(1.0, 0.86, 0.62), 54.0, lights)


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
	_cyl(gv, 13.4, 13.4, 0.52, Vector3(0.0, 0.42, -64.0), water, 24)
	_cyl(gv, 0.14, 0.24, 24.0, Vector3(0.0, 12.0, -48.0), _mat(Color(0.86, 0.88, 0.90), 0.25, 0.8), 10)
	_box(gv, Vector3(4.2, 2.6, 0.1), Vector3(2.1, 22.2, -48.0), emblem)
	_add_light(gv, Vector3(0.0, 18.0, -40.0), Color(1.0, 0.90, 0.72), 62.0, lights)


# =============================================================================================
# 5. 嘉兴市第一中学 (Jiaxing No.1 High School — Clocktower Campus & 400m Athletics Stadium)
# =============================================================================================
static func _jiaxing_no1_school(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var sc := Node3D.new()
	sc.name = "JiaxingNo1HighSchool"
	sc.position = center
	sc.rotation.y = angle
	parent.add_child(sc)

	var brick := _mat(Color(0.64, 0.29, 0.22), 0.78)
	var cream := _mat(Color(0.91, 0.88, 0.82), 0.72)
	var roof_dark := _mat(Color(0.24, 0.26, 0.30), 0.58, 0.10)
	var glass := _glass(Color(0.30, 0.46, 0.58), 0.64)
	var track_red := _mat(Color(0.70, 0.24, 0.19), 0.86)
	var pitch_green := _mat(Color(0.18, 0.48, 0.18), 0.88)
	var line_white := _mat(Color(0.94, 0.95, 0.94), 0.70)
	var clock_face := _emissive(Color(1.0, 0.96, 0.84), 1.3)

	# --- A. Century-Old Main Teaching Building & Iconic Central Clocktower ---
	_box(sc, Vector3(112.0, 16.5, 22.0), Vector3(-36.0, 8.25, -42.0), brick)
	_box(sc, Vector3(24.0, 11.0, 22.4), Vector3(-36.0, 7.2, -42.0), glass)
	_box(sc, Vector3(114.0, 1.4, 23.0), Vector3(-36.0, 16.8, -42.0), cream)
	_box(sc, Vector3(110.0, 1.6, 20.0), Vector3(-36.0, 18.2, -42.0), roof_dark)
	# Flanking teaching wings
	for wx: float in [-82.0, 10.0]:
		_box(sc, Vector3(20.0, 14.5, 58.0), Vector3(wx, 7.25, -8.0), brick)
		_box(sc, Vector3(21.2, 1.1, 59.0), Vector3(wx, 14.8, -8.0), cream)
	# Central Iconic Clocktower (百年一中钟楼)
	_box(sc, Vector3(16.0, 29.0, 16.0), Vector3(-36.0, 14.5, -42.0), brick)
	_box(sc, Vector3(17.2, 1.2, 17.2), Vector3(-36.0, 25.5, -42.0), cream)
	_cyl(sc, 2.2, 2.2, 0.35, Vector3(-36.0, 22.8, -50.1), clock_face, 16, Vector3(PI * 0.5, 0.0, 0.0))
	_cyl(sc, 2.2, 2.2, 0.35, Vector3(-36.0, 22.8, -33.9), clock_face, 16, Vector3(PI * 0.5, 0.0, 0.0))
	_cyl(sc, 0.6, 10.5, 6.2, Vector3(-36.0, 32.1, -42.0), roof_dark, 4, Vector3(0.0, PI * 0.25, 0.0))
	# Campus Main Gate with plaque
	_box(sc, Vector3(26.0, 0.9, 4.0), Vector3(-36.0, 7.4, 42.0), cream)
	for gx: float in [-11.0, 11.0]:
		_box(sc, Vector3(2.8, 7.4, 3.6), Vector3(-36.0 + gx, 3.7, 42.0), brick)
	_sign(sc, "浙江省嘉兴市第一中学", Vector3(-36.0, 8.6, 44.2), 0.0, 76, 0.025, Color(0.92, 0.18, 0.14))

	# --- B. Standard 400m Athletics Track & Football Stadium (田径场) on East Side ---
	var sx := 74.0
	var sz := 6.0
	# Crimson synthetic running track oval (flushed slightly above ground y=0.05)
	_box(sc, Vector3(68.0, 0.08, 112.0), Vector3(sx, 0.05, sz), track_red, 0.0, 0.0, 0.0, false)
	_cyl(sc, 34.0, 34.0, 0.08, Vector3(sx, 0.05, sz - 56.0), track_red, 20)
	_cyl(sc, 34.0, 34.0, 0.08, Vector3(sx, 0.05, sz + 56.0), track_red, 20)
	# Lush green football pitch inside the track + white touchlines & center circle
	_box(sc, Vector3(52.0, 0.09, 98.0), Vector3(sx, 0.06, sz), pitch_green, 0.0, 0.0, 0.0, false)
	_box(sc, Vector3(50.0, 0.10, 0.35), Vector3(sx, 0.07, sz), line_white, 0.0, 0.0, 0.0, false)
	_box(sc, Vector3(0.35, 0.10, 96.0), Vector3(sx - 25.0, 0.07, sz), line_white, 0.0, 0.0, 0.0, false)
	_box(sc, Vector3(0.35, 0.10, 96.0), Vector3(sx + 25.0, 0.07, sz), line_white, 0.0, 0.0, 0.0, false)
	# Covered west grandstand bleachers facing the stadium
	_box(sc, Vector3(11.0, 6.2, 68.0), Vector3(sx - 44.0, 3.1, sz), cream)
	_box(sc, Vector3(16.0, 0.65, 72.0), Vector3(sx - 41.5, 11.2, sz), _mat(Color(0.88, 0.90, 0.93), 0.36, 0.32), 0.0, -0.14)
	_add_light(sc, Vector3(-36.0, 14.0, 26.0), Color(1.0, 0.90, 0.72), 52.0, lights)


# =============================================================================================
# 6. 月河历史街区 (Yuehe Historic Quarter — Jiangnan Horse-Head Walls, Archway & Lanterns)
# =============================================================================================
static func _yuehe_quarter(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var yh := Node3D.new()
	yh.name = "YueheHistoricQuarter"
	yh.position = center
	yh.rotation.y = angle
	parent.add_child(yh)

	var plaster := _mat(Color(0.93, 0.91, 0.86), 0.82)
	var wood_dark := _mat(Color(0.28, 0.17, 0.12), 0.66)
	var tile_dark := _mat(Color(0.19, 0.21, 0.25), 0.60, 0.08)
	var stone := _mat(Color(0.68, 0.67, 0.64), 0.82)
	var lantern := _emissive(Color(1.0, 0.32, 0.16), 2.2)
	var warm_win := _emissive(Color(1.0, 0.82, 0.48), 1.1)

	# --- A. Iconic Jiangnan Timber & Tile Entrance Archway ("月河历史街区" 牌坊) ---
	var arch_z := 58.0
	for ax: float in [-8.5, -4.2, 4.2, 8.5]:
		_box(yh, Vector3(0.65, 8.4, 0.65), Vector3(ax, 4.2, arch_z), wood_dark)
		_box(yh, Vector3(1.15, 1.2, 1.15), Vector3(ax, 0.6, arch_z), stone)
	_box(yh, Vector3(19.0, 0.9, 1.1), Vector3(0.0, 7.6, arch_z), wood_dark)
	_box(yh, Vector3(11.0, 1.5, 3.2), Vector3(0.0, 9.6, arch_z), tile_dark)
	for ax: float in [-6.4, 6.4]:
		_box(yh, Vector3(6.8, 1.2, 2.6), Vector3(ax, 8.2, arch_z), tile_dark)
	_sign(yh, "月 河 历 史 街 区", Vector3(0.0, 8.1, arch_z + 0.7), 0.0, 66, 0.022, Color(0.98, 0.84, 0.34))

	# --- B. Expanded Cross-Axis Jiangnan Old Town Streets (中基路 + 小猪廊下 + 荷花池花鸟街, 26 Heritage Houses!) ---
	_box(yh, Vector3(9.2, 0.06, 134.0), Vector3(0.0, 0.03, 0.0), stone, 0.0, 0.0, 0.0, false)
	_box(yh, Vector3(144.0, 0.06, 8.4), Vector3(0.0, 0.03, -8.0), stone, 0.0, 0.0, 0.0, false)
	# North-South main pedestrian old street (14 houses with stepped horse-head walls + lanterns)
	for ri in range(7):
		var hz := -50.0 + float(ri) * 16.0
		if absf(hz + 8.0) < 9.0:
			continue # leave clean cross-alley junction!
		for side: float in [-1.0, 1.0]:
			var hx := side * 14.5
			var hh := 7.2 if (ri % 2 == 0) else 8.4
			var hw := 14.0
			var hd := 12.0
			_box(yh, Vector3(hw, hh, hd), Vector3(hx, hh * 0.5, hz), plaster)
			_box(yh, Vector3(0.45, 3.4, hd - 1.2), Vector3(hx - side * (hw * 0.5 + 0.15), 1.7, hz), wood_dark)
			_box(yh, Vector3(0.25, 1.8, hd - 3.0), Vector3(hx - side * (hw * 0.5 + 0.25), 1.9, hz), warm_win, 0.0, 0.0, 0.0, false)
			_box(yh, Vector3(hw * 0.62, 0.45, hd + 0.8), Vector3(hx - hw * 0.22, hh + 1.35, hz), tile_dark, 0.0, 0.42)
			_box(yh, Vector3(hw * 0.62, 0.45, hd + 0.8), Vector3(hx + hw * 0.22, hh + 1.35, hz), tile_dark, 0.0, -0.42)
			for gz: float in [-hd * 0.5 - 0.15, hd * 0.5 + 0.15]:
				_box(yh, Vector3(hw + 0.4, hh + 1.1, 0.42), Vector3(hx, (hh + 1.1) * 0.5, hz + gz), plaster)
				_box(yh, Vector3(hw * 0.58, 1.8, 0.46), Vector3(hx, hh + 1.9, hz + gz), plaster)
				_box(yh, Vector3(hw * 0.64, 0.35, 0.85), Vector3(hx, hh + 2.85, hz + gz), tile_dark)
			_box(yh, Vector3(2.4, 0.28, hd + 0.4), Vector3(hx - side * (hw * 0.5 + 1.1), 3.7, hz), tile_dark, 0.0, side * 0.26)
			_cyl(yh, 0.32, 0.28, 0.68, Vector3(hx - side * (hw * 0.5 + 1.8), 3.1, hz), lantern, 8)
	# East-West canal-side old street (花鸟市场 / 小猪廊下 — 12 waterfront heritage shopfronts + timber veranda!)
	for ei in range(-3, 4):
		if ei == 0:
			continue
		var hx2 := float(ei) * 19.5
		for side2: float in [-1.0, 1.0]:
			var hz2 := -8.0 + side2 * 13.5
			var hh2 := 6.8 if (absi(ei) % 2 == 0) else 7.8
			_box(yh, Vector3(14.5, hh2, 11.5), Vector3(hx2, hh2 * 0.5, hz2), plaster)
			_box(yh, Vector3(13.2, 3.2, 0.45), Vector3(hx2, 1.6, hz2 - side2 * 5.85), wood_dark)
			_box(yh, Vector3(11.4, 1.7, 0.25), Vector3(hx2, 1.8, hz2 - side2 * 5.95), warm_win, 0.0, 0.0, 0.0, false)
			_box(yh, Vector3(15.2, 0.45, 7.2), Vector3(hx2, hh2 + 1.25, hz2 - 2.6), tile_dark, 0.0, 0.0, 0.42)
			_box(yh, Vector3(15.2, 0.45, 7.2), Vector3(hx2, hh2 + 1.25, hz2 + 2.6), tile_dark, 0.0, 0.0, -0.42)
			_cyl(yh, 0.30, 0.26, 0.62, Vector3(hx2, 3.0, hz2 - side2 * 6.8), lantern, 8)
	# Waterside Opera Stage Pavilion (月河戏台水榭) & Classic Jiangnan Wupeng Canal Boats (乌篷船)
	_box(yh, Vector3(12.0, 0.9, 10.0), Vector3(-42.0, 0.45, 36.0), stone)
	_box(yh, Vector3(10.5, 4.8, 8.8), Vector3(-42.0, 3.3, 36.0), wood_dark)
	_box(yh, Vector3(13.6, 1.5, 11.6), Vector3(-42.0, 6.4, 36.0), tile_dark)
	_sign(yh, "月 河 古 戏 台", Vector3(-42.0, 5.4, 40.8), 0.0, 48, 0.018, Color(0.98, 0.84, 0.34))
	for b_off: Vector3 in [Vector3(38.0, 0.35, 34.0), Vector3(54.0, 0.35, 18.0), Vector3(-52.0, 0.35, -36.0)]:
		_box(yh, Vector3(7.4, 0.7, 2.0), b_off, wood_dark, 0.35)
		_box(yh, Vector3(4.2, 1.1, 1.7), b_off + Vector3(0.0, 0.8, 0.0), tile_dark, 0.35)
	_add_light(yh, Vector3(0.0, 8.5, 12.0), Color(1.0, 0.72, 0.38), 64.0, lights)
	_add_light(yh, Vector3(0.0, 8.5, -28.0), Color(1.0, 0.72, 0.38), 64.0, lights)


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
	_box(zc, Vector3(8.5, 0.14, 72.0), Vector3(0.0, 0.07, -34.0), stone, 0.0, 0.0, 0.0, false)
	# Enclosing East / West / North ancient brick ramparts & corner pavilions
	for ws_z: float in [-1.0, 1.0]:
		_box(zc, Vector3(5.2, 5.6, 86.0), Vector3(ws_z * 42.0, 2.8, -36.0), brick_grey)
		_box(zc, Vector3(9.5, 6.4, 9.5), Vector3(ws_z * 42.0, 3.2, -78.0), brick_grey)
		_box(zc, Vector3(11.2, 2.2, 11.2), Vector3(ws_z * 42.0, 7.4, -78.0), tile_dark)
		# Golden ginkgo trees flanking the ceremonial courtyard axis
		for gz_t: float in [-24.0, -38.0, -56.0]:
			_cyl(zc, 0.32, 0.42, 4.6, Vector3(ws_z * 16.0, 2.3, gz_t), wood_red, 8)
			_cyl(zc, 2.8, 4.2, 4.4, Vector3(ws_z * 16.0, 6.2, gz_t), ginkgo, 10)
	_box(zc, Vector3(86.0, 5.6, 5.2), Vector3(0.0, 2.8, -78.0), brick_grey)
	# Ceremonial Yimen Gate (仪门) & Main 嘉兴府衙 Great Hall on raised stone plinth
	_box(zc, Vector3(20.0, 4.8, 9.0), Vector3(0.0, 2.4, -26.0), plaster)
	_box(zc, Vector3(23.5, 1.6, 11.5), Vector3(0.0, 5.6, -26.0), tile_dark)
	_box(zc, Vector3(38.0, 1.1, 20.0), Vector3(0.0, 0.55, -52.0), stone)
	_box(zc, Vector3(34.0, 7.2, 16.0), Vector3(0.0, 4.6, -52.0), plaster)
	_box(zc, Vector3(38.5, 2.4, 19.5), Vector3(0.0, 9.2, -52.0), tile_dark)
	_sign(zc, "嘉 兴 府 衙 遗 址", Vector3(0.0, 7.5, -43.5), 0.0, 58, 0.022, Color(0.98, 0.84, 0.34))
	_add_light(zc, Vector3(0.0, 12.0, 14.0), Color(1.0, 0.80, 0.44), 52.0, lights)


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
