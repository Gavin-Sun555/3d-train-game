class_name JiaxingUrbanLandmarks
extends RefCounted

# Detailed bespoke 3D landmarks for Jiaxing's major civic, medical, commercial & eastern wetland sites:
#   - 嘉兴天主教堂 · 圣母显灵堂 (Gothic Twin-Spire Cathedral, national heritage)
#   - 嘉兴市第一医院 / 第二医院 / 中医医院 (Major medical complexes with red-cross & helipad)
#   - 八佰伴购物中心 & 标志性环形空中人行天桥 (Yaohan Plaza + Circular Skywalk Footbridge)
#   - 嘉兴希尔顿酒店 (Hilton Jiaxing landmark glass tower)
#   - 南湖万达广场 (Nanhu Wanda Plaza + Golden Street + SOHO towers)
#   - 嘉兴山姆会员商店 (Sam's Club blue-diamond warehouse superstore)
#   - 湘家荡湿地公园 (Xiangjiadang Wetland Park: ecological birding tower, 100m boardwalk, Moon Bay beach & archway)


static func build(root: Node3D, lm: Dictionary, lights: Array) -> void:
	if lm.has("catholic_church"):
		var cc: Dictionary = lm["catholic_church"]
		_catholic_church(root, _p(cc["pos"]), float(cc.get("angle", 0.06)), lights)
	if lm.has("first_hospital"):
		var h1: Dictionary = lm["first_hospital"]
		_first_hospital(root, _p(h1["pos"]), float(h1.get("angle", 0.03)), lights)
	if lm.has("second_hospital"):
		var h2: Dictionary = lm["second_hospital"]
		_second_hospital(root, _p(h2["pos"]), float(h2.get("angle", 0.08)), lights)
	if lm.has("tcm_hospital"):
		var h3: Dictionary = lm["tcm_hospital"]
		_tcm_hospital(root, _p(h3["pos"]), float(h3.get("angle", -0.10)), lights)
	if lm.has("yaohan_mall"):
		var yh: Dictionary = lm["yaohan_mall"]
		_yaohan_mall_and_bridge(root, _p(yh["pos"]), _p(yh.get("bridge_pos", yh["pos"])), float(yh.get("angle", 0.28)), lights)
	if lm.has("hilton_hotel"):
		var hi: Dictionary = lm["hilton_hotel"]
		_hilton_hotel(root, _p(hi["pos"]), float(hi.get("angle", 0.08)), lights)
	if lm.has("wanda_nanhu"):
		var wd: Dictionary = lm["wanda_nanhu"]
		_wanda_nanhu(root, _p(wd["pos"]), float(wd.get("angle", 0.06)), lights)
	if lm.has("sams_club"):
		var sm: Dictionary = lm["sams_club"]
		_sams_club(root, _p(sm["pos"]), float(sm.get("angle", 0.05)), lights)
	if lm.has("xiangjiadang_park"):
		var xj: Dictionary = lm["xiangjiadang_park"]
		_xiangjiadang_park(root, _p(xj["pos"]), float(xj.get("angle", 0.12)), lights)


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


static func _red_cross(parent: Node3D, pos: Vector3, ry: float, sz: float = 3.2) -> void:
	var rc := _emissive(Color(0.96, 0.12, 0.12), 2.4)
	var bg := _mat(Color(0.96, 0.97, 0.99), 0.45)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = ry
	parent.add_child(holder)
	_box(holder, Vector3(sz * 1.35, sz * 1.35, 0.25), Vector3.ZERO, bg, 0.0, 0.0, 0.0, false)
	_box(holder, Vector3(sz, sz * 0.34, 0.38), Vector3(0.0, 0.0, 0.08), rc, 0.0, 0.0, 0.0, false)
	_box(holder, Vector3(sz * 0.34, sz, 0.38), Vector3(0.0, 0.0, 0.08), rc, 0.0, 0.0, 0.0, false)


# =============================================================================================
# 1. 嘉兴天主教堂 · 圣母显灵堂 (Gothic Twin-Spire Cathedral, National Heritage Monument)
# =============================================================================================
static func _catholic_church(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var ch := Node3D.new()
	ch.name = "JiaxingCatholicChurch"
	ch.position = center
	ch.rotation.y = angle
	parent.add_child(ch)

	var brick_grey := _mat(Color(0.46, 0.46, 0.49), 0.80)
	var brick_red := _mat(Color(0.64, 0.27, 0.22), 0.78)
	var stone := _mat(Color(0.84, 0.82, 0.78), 0.74)
	var slate := _mat(Color(0.20, 0.22, 0.28), 0.56, 0.10)
	var rose := _emissive(Color(0.96, 0.72, 0.34), 1.5)
	var gold := _mat(Color(0.94, 0.78, 0.24), 0.25, 0.78)

	# Courtyard stone terrace
	_box(ch, Vector3(44.0, 0.06, 62.0), Vector3(0.0, 0.03, 0.0), stone, 0.0, 0.0, 0.0, false)
	# Long Gothic nave (42m long, 18m wide, 16m tall) + pitched slate roof & side buttresses
	_box(ch, Vector3(18.0, 15.5, 42.0), Vector3(0.0, 7.75, -4.0), brick_grey)
	for bz: float in [-20.0, -12.0, -4.0, 4.0, 12.0]:
		for bs: float in [-1.0, 1.0]:
			_box(ch, Vector3(2.2, 13.5, 1.6), Vector3(bs * 9.8, 6.75, bz), brick_red)
			_box(ch, Vector3(0.25, 4.8, 1.8), Vector3(bs * 9.05, 8.2, bz + 4.0), rose, 0.0, 0.0, 0.0, false)
	_box(ch, Vector3(11.5, 0.65, 43.0), Vector3(-5.0, 18.2, -4.0), slate, 0.0, 0.62)
	_box(ch, Vector3(11.5, 0.65, 43.0), Vector3(5.0, 18.2, -4.0), slate, 0.0, -0.62)
	# Iconic Twin Gothic Bell Towers (34m tall) flanking the West/South Facade with Rose Window & Golden Crosses!
	for ts: float in [-1.0, 1.0]:
		var tx := ts * 7.8
		_box(ch, Vector3(6.4, 24.0, 6.4), Vector3(tx, 12.0, 18.5), brick_grey)
		for band_y: float in [6.0, 13.0, 20.0]:
			_box(ch, Vector3(6.8, 0.85, 6.8), Vector3(tx, band_y, 18.5), brick_red)
		_cyl(ch, 0.25, 4.2, 11.5, Vector3(tx, 29.7, 18.5), slate, 4, Vector3(0.0, PI * 0.25, 0.0))
		# Golden spire cross atop each bell tower
		_box(ch, Vector3(0.24, 3.2, 0.24), Vector3(tx, 36.8, 18.5), gold)
		_box(ch, Vector3(1.6, 0.24, 0.24), Vector3(tx, 37.4, 18.5), gold)
	# Central Gothic gable portal + luminous stained-glass rose window
	_box(ch, Vector3(10.0, 19.5, 2.2), Vector3(0.0, 9.75, 19.8), brick_red)
	_cyl(ch, 2.6, 2.6, 0.45, Vector3(0.0, 12.6, 21.0), rose, 16, Vector3(PI * 0.5, 0.0, 0.0))
	_box(ch, Vector3(4.2, 6.2, 1.2), Vector3(0.0, 3.1, 20.9), stone)
	_sign(ch, "嘉 兴 天 主 教 堂", Vector3(0.0, 21.2, 21.2), 0.0, 60, 0.022, Color(0.98, 0.90, 0.68))
	_add_light(ch, Vector3(0.0, 14.0, 26.0), Color(1.0, 0.86, 0.60), 46.0, lights)


# =============================================================================================
# 2. 嘉兴市第一医院 (Jiaxing First Hospital — Major Modern Medical Campus + Helipad)
# =============================================================================================
static func _first_hospital(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var h1 := Node3D.new()
	h1.name = "JiaxingFirstHospital"
	h1.position = center
	h1.rotation.y = angle
	parent.add_child(h1)

	var facade := _mat(Color(0.90, 0.92, 0.95), 0.56, 0.06)
	var accent := _mat(Color(0.24, 0.48, 0.72), 0.42, 0.14)
	var glass := _glass(Color(0.32, 0.54, 0.68), 0.62)
	var stone := _mat(Color(0.78, 0.79, 0.80), 0.74)
	var pad := _mat(Color(0.26, 0.28, 0.30), 0.82)
	var yellow := _mat(Color(0.96, 0.80, 0.18), 0.50)

	_box(h1, Vector3(138.0, 0.06, 130.0), Vector3(0.0, 0.03, 0.0), stone, 0.0, 0.0, 0.0, false)
	# Sweeping 5-story Outpatient & Emergency Podium (门急诊综合楼)
	_box(h1, Vector3(114.0, 18.0, 36.0), Vector3(0.0, 9.0, -34.0), facade)
	_box(h1, Vector3(108.0, 13.5, 36.4), Vector3(0.0, 9.5, -34.0), glass)
	_box(h1, Vector3(116.0, 1.4, 38.0), Vector3(0.0, 18.4, -34.0), accent)
	# Main 16-story Twin-Wing Inpatient Tower (住院主楼, 54m tall) + Skybridge Link
	_box(h1, Vector3(84.0, 52.0, 26.0), Vector3(0.0, 26.0, 22.0), facade)
	_box(h1, Vector3(84.5, 44.0, 22.0), Vector3(0.0, 26.5, 22.0), glass)
	for fl in range(1, 7):
		_box(h1, Vector3(86.0, 0.85, 27.0), Vector3(0.0, float(fl) * 7.6, 22.0), facade)
	_box(h1, Vector3(26.0, 14.0, 32.0), Vector3(0.0, 12.0, -6.0), glass)
	# Rooftop Emergency Helipad (屋顶急救停机坪 "H")
	_cyl(h1, 8.8, 9.2, 0.65, Vector3(26.0, 52.35, 22.0), pad, 20)
	_box(h1, Vector3(1.1, 0.08, 6.4), Vector3(23.8, 52.72, 22.0), yellow, 0.0, 0.0, 0.0, false)
	_box(h1, Vector3(1.1, 0.08, 6.4), Vector3(28.2, 52.72, 22.0), yellow, 0.0, 0.0, 0.0, false)
	_box(h1, Vector3(5.0, 0.08, 1.1), Vector3(26.0, 52.72, 22.0), yellow, 0.0, 0.0, 0.0, false)
	# Glowing Red Crosses & Signage
	_red_cross(h1, Vector3(-36.0, 14.5, -52.3), PI, 4.2)
	_red_cross(h1, Vector3(0.0, 48.0, 35.3), 0.0, 5.2)
	_sign(h1, "嘉 兴 市 第 一 医 院", Vector3(4.0, 21.6, -52.4), PI, 92, 0.032, Color(0.92, 0.14, 0.14))
	_sign(h1, "嘉 兴 市 第 一 医 院", Vector3(0.0, 55.8, 35.4), 0.0, 108, 0.036, Color(0.92, 0.14, 0.14))
	_add_light(h1, Vector3(0.0, 16.0, -58.0), Color(0.92, 0.97, 1.0), 60.0, lights)


# =============================================================================================
# 3. 嘉兴市第二医院 (Jiaxing Second Hospital — Century Renji Heritage + Modern Tower)
# =============================================================================================
static func _second_hospital(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var h2 := Node3D.new()
	h2.name = "JiaxingSecondHospital"
	h2.position = center
	h2.rotation.y = angle
	parent.add_child(h2)

	var facade := _mat(Color(0.88, 0.89, 0.91), 0.60, 0.05)
	var brick := _mat(Color(0.62, 0.28, 0.22), 0.78)
	var slate := _mat(Color(0.24, 0.27, 0.32), 0.56)
	var glass := _glass(Color(0.30, 0.50, 0.64), 0.62)

	# Modern 13-story Inpatient & Surgical Main Tower (44m)
	_box(h2, Vector3(58.0, 44.0, 24.0), Vector3(-12.0, 22.0, -8.0), facade)
	_box(h2, Vector3(58.4, 36.0, 20.0), Vector3(-12.0, 22.5, -8.0), glass)
	_box(h2, Vector3(62.0, 14.0, 32.0), Vector3(-12.0, 7.0, 18.0), facade)
	# Century-old Renji Brick Heritage Pavilion (百年仁济楼)
	_box(h2, Vector3(26.0, 13.0, 16.0), Vector3(34.0, 6.5, 10.0), brick)
	_box(h2, Vector3(28.0, 1.8, 18.0), Vector3(34.0, 13.8, 10.0), slate)
	_red_cross(h2, Vector3(-12.0, 40.0, 4.3), 0.0, 4.6)
	_sign(h2, "嘉 兴 市 第 二 医 院", Vector3(-12.0, 47.2, 4.4), 0.0, 92, 0.032, Color(0.92, 0.14, 0.14))
	_sign(h2, "嘉 兴 市 第 二 医 院", Vector3(-12.0, 47.2, -20.4), PI, 92, 0.032, Color(0.92, 0.14, 0.14))
	_add_light(h2, Vector3(0.0, 14.0, 36.0), Color(0.92, 0.96, 1.0), 52.0, lights)


# =============================================================================================
# 4. 嘉兴市中医医院 (Jiaxing Traditional Chinese Medicine Hospital — Neo-Chinese Campus)
# =============================================================================================
static func _tcm_hospital(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var h3 := Node3D.new()
	h3.name = "JiaxingTCMHospital"
	h3.position = center
	h3.rotation.y = angle
	parent.add_child(h3)

	var cream := _mat(Color(0.91, 0.89, 0.84), 0.70)
	var tile := _mat(Color(0.22, 0.25, 0.30), 0.56, 0.08)
	var glass := _glass(Color(0.32, 0.48, 0.58), 0.60)
	var wood := _mat(Color(0.48, 0.24, 0.14), 0.62)

	# Neo-Chinese Pitched-Roof Outpatient Hall + 12-story Inpatient Tower
	_box(h3, Vector3(72.0, 16.0, 28.0), Vector3(0.0, 8.0, 22.0), cream)
	_box(h3, Vector3(66.0, 11.0, 28.4), Vector3(0.0, 8.5, 22.0), glass)
	_box(h3, Vector3(76.0, 2.2, 31.0), Vector3(0.0, 17.0, 22.0), tile)
	_box(h3, Vector3(52.0, 40.0, 22.0), Vector3(0.0, 20.0, -14.0), cream)
	_box(h3, Vector3(52.4, 33.0, 18.0), Vector3(0.0, 20.5, -14.0), glass)
	_box(h3, Vector3(56.0, 2.4, 25.0), Vector3(0.0, 41.2, -14.0), tile)
	_box(h3, Vector3(16.0, 6.2, 16.0), Vector3(0.0, 3.1, 4.0), wood)
	_red_cross(h3, Vector3(-28.0, 13.0, 36.3), 0.0, 3.8)
	_sign(h3, "嘉 兴 市 中 医 医 院", Vector3(4.0, 19.8, 36.4), 0.0, 88, 0.030, Color(0.88, 0.16, 0.14))
	_sign(h3, "嘉 兴 市 中 医 医 院", Vector3(0.0, 44.5, -2.5), 0.0, 96, 0.032, Color(0.88, 0.16, 0.14))
	_add_light(h3, Vector3(0.0, 14.0, 40.0), Color(1.0, 0.94, 0.82), 54.0, lights)


# =============================================================================================
# 5. 八佰伴购物中心 & 标志性环形空中人行天桥 (Yaohan Plaza + Circular Skywalk Footbridge)
# =============================================================================================
static func _yaohan_mall_and_bridge(parent: Node3D, mall_pos: Vector3, bridge_pos: Vector3, angle: float, lights: Array) -> void:
	var yh := Node3D.new()
	yh.name = "JiaxingYaohanPlazaAndBridge"
	yh.position = mall_pos
	yh.rotation.y = angle
	parent.add_child(yh)

	var champ := _mat(Color(0.86, 0.80, 0.68), 0.36, 0.38)
	var dark_alu := _mat(Color(0.18, 0.21, 0.26), 0.38, 0.45)
	var steel_w := _mat(Color(0.92, 0.94, 0.96), 0.30, 0.36)
	var glass := _glass(Color(0.28, 0.48, 0.66), 0.64)
	var screen := _emissive(Color(0.28, 0.72, 1.0), 1.8)
	var warm := _emissive(Color(1.0, 0.88, 0.56), 1.4)

	# --- A. Grand Yaohan Shopping Center (八佰伴购物中心, 112m x 72m x 28m) ---
	_box(yh, Vector3(112.0, 26.0, 72.0), Vector3(0.0, 13.0, 0.0), champ)
	_box(yh, Vector3(112.6, 18.0, 64.0), Vector3(0.0, 12.0, 0.0), glass)
	_box(yh, Vector3(114.0, 2.2, 74.0), Vector3(0.0, 26.8, 0.0), dark_alu)
	# Corner curved glass atrium & giant illuminated LED commercial screen
	_cyl(yh, 18.0, 18.0, 28.0, Vector3(48.0, 14.0, 28.0), glass, 18)
	_box(yh, Vector3(24.0, 12.0, 0.6), Vector3(32.0, 16.0, 36.5), screen, 0.0, 0.0, 0.0, false)
	# Horizontal glowing commercial fascia ribbons
	for fy: float in [7.2, 14.4, 21.6]:
		_box(yh, Vector3(113.2, 0.45, 73.0), Vector3(0.0, fy, 0.0), warm, 0.0, 0.0, 0.0, false)
	_sign(yh, "八 佰 伴 购 物 中 心", Vector3(0.0, 30.8, 36.8), 0.0, 116, 0.036, Color(0.98, 0.84, 0.30))
	_sign(yh, "Y A O H A N   P L A Z A", Vector3(0.0, 28.2, 36.8), 0.0, 44, 0.026, Color(0.95, 0.97, 1.0))
	_sign(yh, "八 佰 伴 购 物 中 心", Vector3(0.0, 30.8, -36.8), PI, 116, 0.036, Color(0.98, 0.84, 0.30))
	_add_light(yh, Vector3(36.0, 16.0, 44.0), Color(1.0, 0.90, 0.68), 64.0, lights)

	# --- B. Iconic Circular Multi-Arm Pedestrian Skywalk Bridge (八佰伴标志性环形人行天桥) ---
	var br := Node3D.new()
	br.name = "YaohanCircularFootbridge"
	br.position = bridge_pos
	parent.add_child(br)
	var r_ring := 21.0
	var deck_y := 5.8
	var n_seg := 24
	for k in range(n_seg):
		var a0 := float(k) * TAU / float(n_seg)
		var a1 := float(k + 1) * TAU / float(n_seg)
		var am := (a0 + a1) * 0.5
		var seg_l := 2.0 * r_ring * sin(PI / float(n_seg)) + 0.35
		var px := cos(am) * r_ring
		var pz := sin(am) * r_ring
		# Sleek white steel ring deck + translucent glass guardrails + overhead canopy ring
		_box(br, Vector3(seg_l, 0.72, 4.6), Vector3(px, deck_y, pz), steel_w, -am + PI * 0.5)
		_box(br, Vector3(seg_l, 1.25, 0.14), Vector3(cos(am) * (r_ring + 2.2), deck_y + 0.95, sin(am) * (r_ring + 2.2)), glass, -am + PI * 0.5)
		_box(br, Vector3(seg_l, 1.25, 0.14), Vector3(cos(am) * (r_ring - 2.2), deck_y + 0.95, sin(am) * (r_ring - 2.2)), glass, -am + PI * 0.5)
		_box(br, Vector3(seg_l, 0.24, 5.2), Vector3(px, deck_y + 3.45, pz), glass, -am + PI * 0.5)
		if k % 3 == 0:
			_cyl(br, 0.42, 0.48, deck_y, Vector3(px, deck_y * 0.5, pz), steel_w, 10)
			_cyl(br, 0.14, 0.14, 3.4, Vector3(cos(am) * (r_ring + 2.1), deck_y + 1.7, sin(am) * (r_ring + 2.1)), steel_w, 8)
	# 4 Corner Escalator & Stairway Descent Arms touching sidewalks cleanly outside the carriageway
	for ca_deg: float in [45.0, 135.0, 225.0, 315.0]:
		var ca := deg_to_rad(ca_deg)
		var ux := cos(ca)
		var uz := sin(ca)
		var sx := ux * (r_ring + 8.5)
		var sz := uz * (r_ring + 8.5)
		_box(br, Vector3(15.5, 0.58, 3.6), Vector3(sx, deck_y * 0.5, sz), steel_w, -ca, -0.37)
		_box(br, Vector3(15.5, 1.15, 0.16), Vector3(sx - uz * 1.7, deck_y * 0.5 + 0.85, sz + ux * 1.7), glass, -ca, -0.37)
	# Direct 2nd-floor pedestrian skywalk arm linking the circular bridge to Yaohan Mall
	var to_mall := mall_pos - bridge_pos
	var arm_len := clampf(to_mall.length() - 36.0, 12.0, 48.0)
	if to_mall.length() > 10.0:
		var dir_m := to_mall.normalized()
		var arm_mid := dir_m * (r_ring + arm_len * 0.5)
		var arm_ang := -atan2(dir_m.z, dir_m.x)
		_box(br, Vector3(arm_len, 0.72, 4.4), Vector3(arm_mid.x, deck_y, arm_mid.z), steel_w, arm_ang)
		_box(br, Vector3(arm_len, 3.2, 4.6), Vector3(arm_mid.x, deck_y + 1.9, arm_mid.z), glass, arm_ang)
	_add_light(br, Vector3(0.0, 9.5, 0.0), Color(0.92, 0.96, 1.0), 54.0, lights)


# =============================================================================================
# 6. 嘉兴希尔顿酒店 (Hilton Jiaxing — Iconic Champagne-Gold & Glass High-Rise Landmark Tower)
# =============================================================================================
static func _hilton_hotel(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var hi := Node3D.new()
	hi.name = "JiaxingHiltonHotel"
	hi.position = center
	hi.rotation.y = angle
	parent.add_child(hi)

	var gold_fin := _mat(Color(0.84, 0.74, 0.54), 0.30, 0.55)
	var stone := _mat(Color(0.82, 0.80, 0.76), 0.66)
	var glass := _glass(Color(0.20, 0.38, 0.54), 0.72)
	var crown := _emissive(Color(1.0, 0.92, 0.74), 1.8)

	# Grand ballroom & lobby podium (88m x 56m x 16m)
	_box(hi, Vector3(88.0, 16.0, 56.0), Vector3(0.0, 8.0, 0.0), stone)
	_box(hi, Vector3(82.0, 10.5, 56.4), Vector3(0.0, 7.2, 0.0), glass)
	_box(hi, Vector3(28.0, 0.65, 14.0), Vector3(0.0, 6.2, 34.0), gold_fin)
	# Sleek 26-story High-Rise Hotel Tower (78m tall) with chamfered glass curtain & champagne fins
	_box(hi, Vector3(42.0, 78.0, 26.0), Vector3(0.0, 39.0, -6.0), glass)
	_box(hi, Vector3(44.2, 3.6, 28.2), Vector3(0.0, 76.8, -6.0), gold_fin)
	_box(hi, Vector3(44.6, 0.55, 28.6), Vector3(0.0, 78.6, -6.0), crown, 0.0, 0.0, 0.0, false)
	for fx: float in [-21.0, -14.0, -7.0, 0.0, 7.0, 14.0, 21.0]:
		_box(hi, Vector3(0.85, 76.0, 26.8), Vector3(fx, 38.0, -6.0), gold_fin)
	# Adjacent World Trade Center partner office tower
	_box(hi, Vector3(28.0, 62.0, 24.0), Vector3(48.0, 31.0, -4.0), glass)
	_box(hi, Vector3(29.0, 2.6, 25.0), Vector3(48.0, 61.5, -4.0), gold_fin)
	_sign(hi, "Hilton  嘉兴希尔顿酒店", Vector3(0.0, 82.8, 7.8), 0.0, 118, 0.038, Color(0.98, 0.88, 0.52))
	_sign(hi, "Hilton  嘉兴希尔顿酒店", Vector3(0.0, 82.8, -19.8), PI, 118, 0.038, Color(0.98, 0.88, 0.52))
	_add_light(hi, Vector3(0.0, 12.0, 36.0), Color(1.0, 0.88, 0.62), 62.0, lights)


# =============================================================================================
# 7. 嘉兴南湖万达广场 (Nanhu Wanda Plaza — Mega Mall, Golden Street & Dual SOHO Towers)
# =============================================================================================
static func _wanda_nanhu(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var wd := Node3D.new()
	wd.name = "JiaxingNanhuWandaPlaza"
	wd.position = center
	wd.rotation.y = angle
	parent.add_child(wd)

	var alu := _mat(Color(0.86, 0.88, 0.91), 0.34, 0.42)
	var wanda_blue := _mat(Color(0.08, 0.32, 0.68), 0.38, 0.25)
	var warm_band := _mat(Color(0.88, 0.52, 0.16), 0.42, 0.22)
	var glass := _glass(Color(0.24, 0.46, 0.68), 0.64)
	var glow := _emissive(Color(1.0, 0.86, 0.52), 1.6)
	var stone := _mat(Color(0.76, 0.77, 0.78), 0.74)

	_box(wd, Vector3(170.0, 0.06, 126.0), Vector3(0.0, 0.03, 0.0), stone, 0.0, 0.0, 0.0, false)
	# Mega 5-story Wanda Shopping Mall body (136m x 76m x 24m) with iconic ribbon facade bands
	_box(wd, Vector3(136.0, 24.0, 76.0), Vector3(-10.0, 12.0, -10.0), alu)
	_box(wd, Vector3(136.6, 16.0, 68.0), Vector3(-10.0, 11.5, -10.0), glass)
	for by: float in [6.4, 13.0, 19.6]:
		_box(wd, Vector3(137.8, 1.35, 77.2), Vector3(-10.0, by, -10.0), wanda_blue if by > 15.0 else warm_band)
	# Iconic arched glass main atrium entrance (Gate 1)
	_box(wd, Vector3(32.0, 18.0, 10.0), Vector3(-10.0, 9.0, 31.0), glass)
	_box(wd, Vector3(36.0, 2.2, 12.0), Vector3(-10.0, 19.0, 31.0), wanda_blue)
	# Twin Wanda SOHO Office/Apartment Towers (58m tall) anchoring the complex corners
	for sx: float in [-58.0, 56.0]:
		_box(wd, Vector3(26.0, 58.0, 24.0), Vector3(sx, 29.0, -34.0), alu)
		_box(wd, Vector3(26.4, 50.0, 20.0), Vector3(sx, 29.5, -34.0), glass)
		_box(wd, Vector3(27.0, 2.2, 25.0), Vector3(sx, 57.5, -34.0), wanda_blue)
	# Wanda Golden Street (万达金街 — lively pedestrian retail strip on east flank)
	for gz: float in [-28.0, -8.0, 12.0, 32.0]:
		_box(wd, Vector3(16.0, 10.5, 16.0), Vector3(72.0, 5.25, gz), alu)
		_box(wd, Vector3(16.4, 3.6, 14.0), Vector3(72.0, 2.4, gz), glow, 0.0, 0.0, 0.0, false)
	_sign(wd, "南 湖 万 达 广 场", Vector3(-10.0, 27.8, 36.8), 0.0, 132, 0.042, Color(0.98, 0.98, 1.0))
	_sign(wd, "W A N D A   P L A Z A", Vector3(-10.0, 24.4, 36.8), 0.0, 48, 0.028, Color(0.96, 0.82, 0.34))
	_sign(wd, "南 湖 万 达 广 场", Vector3(-10.0, 27.8, -48.8), PI, 132, 0.042, Color(0.98, 0.98, 1.0))
	_add_light(wd, Vector3(-10.0, 15.0, 42.0), Color(1.0, 0.90, 0.72), 70.0, lights)


# =============================================================================================
# 8. 嘉兴山姆会员商店 (Sam's Club Jiaxing — Blue-Diamond Warehouse Superstore)
# =============================================================================================
static func _sams_club(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var sm := Node3D.new()
	sm.name = "JiaxingSamsClub"
	sm.position = center
	sm.rotation.y = angle
	parent.add_child(sm)

	var wall_w := _mat(Color(0.93, 0.94, 0.96), 0.56, 0.08)
	var sam_blue := _mat(Color(0.05, 0.36, 0.76), 0.34, 0.22)
	var sam_cyan := _emissive(Color(0.16, 0.68, 0.96), 1.6)
	var roof_g := _mat(Color(0.76, 0.78, 0.81), 0.64)
	var lot := _mat(Color(0.28, 0.30, 0.33), 0.86)
	var glass := _glass(Color(0.26, 0.48, 0.66), 0.58)
	var stripe := _mat(Color(0.94, 0.95, 0.96), 0.70)

	# Large surface parking apron & white stall markings (会员停车场)
	_box(sm, Vector3(148.0, 0.06, 128.0), Vector3(0.0, 0.03, 12.0), lot, 0.0, 0.0, 0.0, false)
	for lx: float in [-50.0, -30.0, -10.0, 10.0, 30.0, 50.0]:
		_box(sm, Vector3(0.28, 0.08, 34.0), Vector3(lx, 0.05, 50.0), stripe, 0.0, 0.0, 0.0, false)
	# Iconic Big-Box Membership Warehouse (112m x 68m x 14.5m) with Blue Fascia Band
	_box(sm, Vector3(112.0, 14.2, 68.0), Vector3(0.0, 7.1, -12.0), wall_w)
	_box(sm, Vector3(113.0, 2.8, 69.0), Vector3(0.0, 13.0, -12.0), sam_blue)
	_box(sm, Vector3(110.0, 0.45, 66.0), Vector3(0.0, 14.5, -12.0), roof_g)
	# Grand Glass Member Entrance Vestibule + Covered Drop-Off Canopy
	_box(sm, Vector3(36.0, 8.6, 10.0), Vector3(0.0, 4.3, 25.0), glass)
	_box(sm, Vector3(44.0, 1.4, 14.0), Vector3(0.0, 9.2, 26.5), sam_blue)
	# Iconic Giant Rotated Blue Diamond Emblem (山姆蓝钻徽标) above the main entrance!
	_box(sm, Vector3(8.5, 8.5, 1.0), Vector3(-28.0, 13.5, 22.8), sam_blue, 0.0, PI * 0.25)
	_box(sm, Vector3(5.6, 5.6, 1.2), Vector3(-28.0, 13.5, 23.0), sam_cyan, 0.0, PI * 0.25, 0.0, false)
	_sign(sm, "山 姆 会 员 商 店", Vector3(6.0, 15.6, 23.2), 0.0, 118, 0.038, Color(0.96, 0.98, 1.0))
	_sign(sm, "S A M ' S   C L U B", Vector3(6.0, 12.6, 23.2), 0.0, 58, 0.030, Color(0.56, 0.88, 1.0))
	_add_light(sm, Vector3(0.0, 12.0, 34.0), Color(0.92, 0.96, 1.0), 65.0, lights)


# =============================================================================================
# 9. 湘家荡湿地公园 (Xiangjiadang Wetland Park — Birding Tower, 100m Boardwalk & Moon Bay Beach)
# =============================================================================================
static func _xiangjiadang_park(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var xj := Node3D.new()
	xj.name = "XiangjiadangWetlandPark"
	xj.position = center
	xj.rotation.y = angle
	parent.add_child(xj)

	var wood := _mat(Color(0.56, 0.40, 0.26), 0.76)
	var wood_dark := _mat(Color(0.36, 0.22, 0.14), 0.72)
	var tile := _mat(Color(0.20, 0.23, 0.28), 0.58)
	var wall := _mat(Color(0.92, 0.90, 0.85), 0.80)
	var sand := _mat(Color(0.86, 0.79, 0.60), 0.90)
	var reed := _mat(Color(0.38, 0.50, 0.24), 0.88)
	var foliage := _mat(Color(0.20, 0.46, 0.22), 0.84)
	var glow := _emissive(Color(1.0, 0.86, 0.54), 1.4)

	# --- A. Wetland Park Grand Ecological Entrance Archway & Visitor Center (湘家荡湿地公园大门) ---
	for ax: float in [-11.0, -4.5, 4.5, 11.0]:
		_cyl(xj, 0.42, 0.48, 8.8, Vector3(ax, 4.4, -42.0), wood_dark, 10)
	_box(xj, Vector3(25.0, 1.2, 3.6), Vector3(0.0, 9.2, -42.0), tile)
	_sign(xj, "湘 家 荡 湿 地 公 园", Vector3(0.0, 7.6, -40.8), 0.0, 88, 0.030, Color(0.98, 0.88, 0.42))
	_sign(xj, "湘 家 荡 湿 地 公 园", Vector3(0.0, 7.6, -43.2), PI, 88, 0.030, Color(0.98, 0.88, 0.42))

	# --- B. 32m Timber Ecological Bird-Watching Observation Tower (湿地观鸟塔) ---
	var ty := 0.0
	for lv in range(5):
		var r := lerpf(7.5, 4.0, float(lv) / 4.0)
		_cyl(xj, r * 0.92, r, 5.4, Vector3(-28.0, ty + 2.7, 0.0), wood_dark, 8)
		_cyl(xj, r + 1.8, r + 2.4, 0.85, Vector3(-28.0, ty + 5.6, 0.0), tile, 8)
		ty += 5.8
	_cyl(xj, 0.4, 5.6, 4.5, Vector3(-28.0, ty + 2.2, 0.0), tile, 8)
	_box(xj, Vector3(3.2, 2.2, 3.2), Vector3(-28.0, ty - 2.6, 0.0), glow, 0.0, 0.0, 0.0, false)

	# --- C. 120m Winding Timber Wetland Boardwalk extending into Xiangjiadang Lake + Over-Water Deck ---
	_box(xj, Vector3(115.0, 0.35, 4.8), Vector3(42.0, 0.48, 12.0), wood, 0.0, 0.0, 0.0, false)
	_box(xj, Vector3(4.8, 0.35, 66.0), Vector3(96.0, 0.48, -18.0), wood, 0.0, 0.0, 0.0, false)
	# Over-water octagonal ecological observation pavilion
	_cyl(xj, 9.5, 10.0, 0.65, Vector3(106.0, 0.55, 12.0), wood, 8)
	for ka in range(8):
		var a := float(ka) * TAU / 8.0
		_cyl(xj, 0.22, 0.24, 4.8, Vector3(106.0 + cos(a) * 7.2, 3.1, 12.0 + sin(a) * 7.2), wood_dark, 8)
	_cyl(xj, 1.2, 11.4, 3.0, Vector3(106.0, 6.8, 12.0), tile, 8)

	# --- D. Moon Bay Golden Lakefront Beach (月亮湾沙滩) & Reed Marsh Islands ---
	_cyl(xj, 36.0, 38.0, 0.22, Vector3(26.0, 0.14, 58.0), sand, 20)
	_box(xj, Vector3(22.0, 4.8, 12.0), Vector3(8.0, 2.4, 48.0), wall)
	_box(xj, Vector3(25.0, 1.2, 14.5), Vector3(8.0, 5.4, 48.0), tile)
	for ri in range(6):
		var rx := 42.0 + float(ri) * 18.0
		var rz := -32.0 + float((ri % 3) - 1) * 28.0
		_cyl(xj, 9.0, 11.0, 0.55, Vector3(rx, 0.30, rz), reed, 10)
		_cyl(xj, 3.2, 4.8, 5.0, Vector3(rx, 3.2, rz), foliage, 8)
	_add_light(xj, Vector3(0.0, 10.0, -36.0), Color(1.0, 0.88, 0.62), 62.0, lights)
