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
	if lm.has("pingshan_park"):
		var ps: Dictionary = lm["pingshan_park"]
		_pingshan_park(root, _p(ps["pos"]), float(ps.get("angle", 0.14)), lights)
	if lm.has("jiangnan_mall"):
		var jn: Dictionary = lm["jiangnan_mall"]
		_jiangnan_mall(root, _p(jn["pos"]), float(jn.get("angle", 0.16)), lights)
	if lm.has("diamond_plaza"):
		var dm: Dictionary = lm["diamond_plaza"]
		_diamond_plaza(root, _p(dm["pos"]), float(dm.get("angle", 0.14)), lights)
	if lm.has("cifi_plaza"):
		var cf: Dictionary = lm["cifi_plaza"]
		_cifi_plaza(root, _p(cf["pos"]), float(cf.get("angle", 0.17)), lights)
	if lm.has("shaonian_street"):
		var sn: Dictionary = lm["shaonian_street"]
		_shaonian_pedestrian_street(root, _p(sn["pos"]), float(sn.get("angle", 0.144)), lights)


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
# 9. 湘家荡湿地公园 (Xiangjiadang Wetland Park — Dry-Shore Archway, Birding Tower, 160m Boardwalk & Moon Bay)
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
	var stone := _mat(Color(0.80, 0.78, 0.73), 0.78)
	var sand := _mat(Color(0.86, 0.79, 0.60), 0.90)
	var reed := _mat(Color(0.38, 0.50, 0.24), 0.88)
	var foliage := _mat(Color(0.20, 0.46, 0.22), 0.84)
	var foliage_lt := _mat(Color(0.28, 0.55, 0.25), 0.82)
	var glow := _emissive(Color(1.0, 0.86, 0.54), 1.4)

	# --- A. Wetland Park Grand Ecological Entrance Archway & Visitor Hall on Dry West Lawn (x = -75..-20) ---
	_box(xj, Vector3(48.0, 0.08, 42.0), Vector3(-42.0, 0.05, 0.0), stone, 0.0, 0.0, 0.0, false)
	for az: float in [-11.0, -4.5, 4.5, 11.0]:
		_cyl(xj, 0.42, 0.48, 8.8, Vector3(-62.0, 4.4, az), wood_dark, 10)
	_box(xj, Vector3(3.6, 1.2, 25.0), Vector3(-62.0, 9.2, 0.0), tile)
	_sign(xj, "湘 家 荡 湿 地 公 园", Vector3(-63.2, 7.6, 0.0), -PI * 0.5, 88, 0.030, Color(0.98, 0.88, 0.42))
	_sign(xj, "湘 家 荡 湿 地 公 园", Vector3(-60.8, 7.6, 0.0), PI * 0.5, 88, 0.030, Color(0.98, 0.88, 0.42))
	# Visitor Ecological Exhibition Hall & Tea House on dry shore
	_box(xj, Vector3(24.0, 5.2, 16.0), Vector3(-34.0, 2.6, -26.0), wall)
	_box(xj, Vector3(27.0, 1.3, 18.5), Vector3(-34.0, 5.8, -26.0), tile)

	# --- B. 32m Timber Ecological Bird-Watching Observation Tower (湿地观鸟塔 — strictly on dry west shore!) ---
	var ty := 0.0
	for lv in range(5):
		var r := lerpf(7.2, 3.8, float(lv) / 4.0)
		_cyl(xj, r * 0.92, r, 5.4, Vector3(-28.0, ty + 2.7, 26.0), wood_dark, 8)
		_cyl(xj, r + 1.8, r + 2.4, 0.85, Vector3(-28.0, ty + 5.6, 26.0), tile, 8)
		ty += 5.8
	_cyl(xj, 0.4, 5.4, 4.5, Vector3(-28.0, ty + 2.2, 26.0), tile, 8)
	_box(xj, Vector3(3.2, 2.2, 3.2), Vector3(-28.0, ty - 2.6, 26.0), glow, 0.0, 0.0, 0.0, false)
	_sign(xj, "湿 地 观 鸟 塔", Vector3(-28.0, 8.2, 34.0), 0.0, 56, 0.022, Color(0.98, 0.88, 0.42))

	# --- C. Lush Dry-Shore Woodland Groves framing the entrance lawn ---
	for gi in range(14):
		var gx := -72.0 + float(gi % 4) * 20.0
		var gz := -70.0 + float(gi / 4) * 44.0
		if absf(gz) < 20.0 and gx > -58.0:
			continue
		_cyl(xj, 0.24, 0.34, 3.8, Vector3(gx, 1.9, gz), wood_dark, 6)
		_cyl(xj, 2.2, 4.0, 4.8, Vector3(gx, 5.2, gz), foliage if (gi % 2 == 0) else foliage_lt, 8)

	# --- D. 200m Winding Timber Wetland Boardwalk extending EAST from dry shore into Xiangjiadang Lake ---
	_box(xj, Vector3(175.0, 0.36, 4.8), Vector3(72.0, 0.48, 0.0), wood, 0.0, 0.0, 0.0, false)
	_box(xj, Vector3(4.8, 0.36, 92.0), Vector3(145.0, 0.48, -32.0), wood, 0.0, 0.0, 0.0, false)
	# Over-water octagonal ecological observation pavilion floating out over Xiangjiadang Lake
	_cyl(xj, 9.5, 10.0, 0.65, Vector3(168.0, 0.55, 0.0), wood, 8)
	for ka in range(8):
		var a := float(ka) * TAU / 8.0
		_cyl(xj, 0.22, 0.24, 4.8, Vector3(168.0 + cos(a) * 7.2, 3.1, sin(a) * 7.2), wood_dark, 8)
	_cyl(xj, 1.2, 11.4, 3.0, Vector3(168.0, 6.8, 0.0), tile, 8)

	# --- E. Moon Bay Golden Lakefront Beach (月亮湾沙滩 along shore) & Over-Water Reed Marsh Islands ---
	_cyl(xj, 32.0, 35.0, 0.18, Vector3(12.0, 0.12, 72.0), sand, 20)
	for ri in range(6):
		var rx := 115.0 + float(ri) * 26.0
		var rz := -48.0 + float((ri % 3) - 1) * 42.0
		_cyl(xj, 9.0, 11.5, 0.55, Vector3(rx, 0.30, rz), reed, 10)
		_cyl(xj, 3.2, 4.8, 5.0, Vector3(rx, 3.2, rz), foliage, 8)
	_add_light(xj, Vector3(-44.0, 10.0, 0.0), Color(1.0, 0.88, 0.62), 68.0, lights)


# =============================================================================================
# 10. 瓶山公园 (Pingshan Park — Historic Song-Dynasty Bottle Hill, Stone Steps, 瓶山亭 & Memorial Stele)
# =============================================================================================
static func _pingshan_park(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var ps := Node3D.new()
	ps.name = "PingshanPark"
	ps.position = center
	ps.rotation.y = angle
	parent.add_child(ps)

	var grass := _mat(Color(0.22, 0.46, 0.22), 0.90)
	var grass_hi := _mat(Color(0.26, 0.52, 0.24), 0.88)
	var stone := _mat(Color(0.78, 0.76, 0.72), 0.78)
	var granite := _mat(Color(0.66, 0.65, 0.62), 0.76)
	var wood_red := _mat(Color(0.58, 0.16, 0.12), 0.52, 0.06)
	var tile_dark := _mat(Color(0.19, 0.21, 0.26), 0.56, 0.08)
	var gold := _mat(Color(0.94, 0.78, 0.24), 0.28, 0.72)
	var trunk := _mat(Color(0.30, 0.22, 0.16), 0.88)
	var pine := _mat(Color(0.14, 0.34, 0.18), 0.86)
	var lantern := _emissive(Color(1.0, 0.42, 0.18), 1.9)

	# --- A. Sculpted 3-Tier Terraced Green Hillock ("瓶山" 10m wooded hill rising over old town) ---
	_cyl(ps, 46.0, 52.0, 3.2, Vector3(0.0, 1.6, -4.0), grass, 20)
	_cyl(ps, 32.0, 42.0, 3.4, Vector3(0.0, 4.9, -6.0), grass_hi, 18)
	_cyl(ps, 19.0, 28.0, 3.2, Vector3(0.0, 8.2, -8.0), grass, 16)
	_cyl(ps, 18.2, 18.8, 0.35, Vector3(0.0, 9.95, -8.0), stone, 16)

	# --- B. Grand South Ceremonial Stone Stairway climbing from 中山东路 Entrance to the Summit ---
	for si in range(14):
		var f := float(si) / 13.0
		var sy := 0.35 + f * 9.5
		var sz := 48.0 - f * 42.0
		_box(ps, Vector3(7.4, 0.75, 3.8), Vector3(0.0, sy, sz), stone)
		for bs: float in [-3.9, 3.9]:
			_box(ps, Vector3(0.55, 1.15, 3.8), Vector3(bs, sy + 0.7, sz), granite)
	# South Park Entrance Plaza & Heritage Archway facing 中山东路建国南路(瓶山) station!
	_box(ps, Vector3(34.0, 0.12, 18.0), Vector3(0.0, 0.06, 56.0), stone, 0.0, 0.0, 0.0, false)
	for px_a: float in [-7.8, -3.9, 3.9, 7.8]:
		_box(ps, Vector3(0.72, 7.4, 0.72), Vector3(px_a, 3.7, 58.0), granite)
		_box(ps, Vector3(1.25, 1.1, 1.25), Vector3(px_a, 0.55, 58.0), stone)
	_box(ps, Vector3(18.0, 1.1, 2.4), Vector3(0.0, 7.6, 58.0), tile_dark)
	_box(ps, Vector3(10.5, 1.3, 3.0), Vector3(0.0, 8.8, 58.0), tile_dark)
	_sign(ps, "瓶  山  公  园", Vector3(0.0, 7.3, 59.3), 0.0, 78, 0.026, Color(0.98, 0.85, 0.32))
	_sign(ps, "PINGSHAN PARK", Vector3(0.0, 5.9, 59.3), 0.0, 38, 0.020, Color(0.94, 0.95, 0.96))

	# --- C. Summit Two-Tier Octagonal Jiangnan Pavilion (瓶山亭 / 揽胜亭) + Memorial Stele ---
	var top_y := 10.1
	_cyl(ps, 7.4, 8.0, 0.9, Vector3(0.0, top_y + 0.45, -8.0), stone, 8)
	for ka in range(8):
		var a := float(ka) * TAU / 8.0
		_cyl(ps, 0.22, 0.24, 5.2, Vector3(cos(a) * 5.6, top_y + 3.5, -8.0 + sin(a) * 5.6), wood_red, 8)
	# Lower & upper sweeping octagonal roofs + golden finial
	_cyl(ps, 5.6, 9.6, 2.2, Vector3(0.0, top_y + 7.0, -8.0), tile_dark, 8)
	_cyl(ps, 4.2, 4.4, 3.2, Vector3(0.0, top_y + 9.2, -8.0), wood_red, 8)
	_cyl(ps, 0.8, 7.6, 3.0, Vector3(0.0, top_y + 12.1, -8.0), tile_dark, 8)
	_cyl(ps, 0.14, 0.38, 1.35, Vector3(0.0, top_y + 14.1, -8.0), gold, 8)
	for la in range(4):
		var a2 := float(la) * PI * 0.5 + PI * 0.25
		_cyl(ps, 0.24, 0.20, 0.52, Vector3(cos(a2) * 6.2, top_y + 5.6, -8.0 + sin(a2) * 6.2), lantern, 8)
	_sign(ps, "瓶 山 亭", Vector3(0.0, top_y + 6.0, -1.6), 0.0, 58, 0.020, Color(0.98, 0.85, 0.34))

	# Pingshan Revolutionary Memorial Stele (瓶山烈士纪念碑) on east mid-terrace
	_box(ps, Vector3(7.5, 1.2, 7.5), Vector3(24.0, 6.9, 6.0), granite)
	_box(ps, Vector3(2.4, 11.5, 1.6), Vector3(24.0, 13.0, 6.0), stone)
	_box(ps, Vector3(2.8, 1.0, 2.0), Vector3(24.0, 19.2, 6.0), gold)

	# Lush Hillside Cypress & Pine Groves framing the entire bottle hill
	for ti in range(22):
		var ang := float(ti) * TAU / 22.0
		var rad := 26.0 if (ti % 2 == 0) else 39.0
		var ty_h := 6.2 if (ti % 2 == 0) else 3.0
		var tx := cos(ang) * rad
		var tz := -6.0 + sin(ang) * rad
		if absf(tx) < 7.5 and tz > 4.0:
			continue # keep south stairway clear
		ParkLandscapeBuilder.plant_tree(ps, Vector3(tx, ty_h, tz), 0, 0.75, Color(0.12, 0.27, 0.14))

	_add_light(ps, Vector3(0.0, top_y + 8.0, -8.0), Color(1.0, 0.82, 0.44), 55.0, lights)
	_add_light(ps, Vector3(0.0, 9.0, 58.0), Color(1.0, 0.84, 0.52), 48.0, lights)


# =============================================================================================
# 11. 江南大厦 (Jiangnan Department Store — Iconic Corner Flagship Mall at 中山东路 / 禾兴南路)
# =============================================================================================
static func _jiangnan_mall(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var jn := Node3D.new()
	jn.name = "JiangnanDepartmentStore"
	jn.position = center
	jn.rotation.y = angle
	parent.add_child(jn)

	var stone_warm := _mat(Color(0.84, 0.79, 0.71), 0.66)
	var stone_trim := _mat(Color(0.92, 0.89, 0.84), 0.56)
	var accent_red := _mat(Color(0.76, 0.14, 0.12), 0.42, 0.12)
	var bronze := _mat(Color(0.42, 0.34, 0.24), 0.36, 0.65)
	var glass := _glass(Color(0.24, 0.42, 0.58), 0.64)
	var glow_red := _emissive(Color(0.96, 0.18, 0.14), 2.1)
	var glow_warm := _emissive(Color(1.0, 0.90, 0.64), 1.5)
	var plaza := _mat(Color(0.80, 0.78, 0.74), 0.76)

	# Corner granite entrance plaza
	_box(jn, Vector3(68.0, 0.12, 52.0), Vector3(0.0, 0.06, 0.0), plaza, 0.0, 0.0, 0.0, false)
	# 6-Story Flagship Department Store Podium (56m x 38m x 25m)
	_box(jn, Vector3(56.0, 25.0, 38.0), Vector3(2.0, 12.5, -2.0), stone_warm)
	# Horizontal architectural stone cornices & illuminated display window bands
	for fy: float in [4.8, 9.2, 13.6, 18.0, 22.4]:
		_box(jn, Vector3(57.0, 0.65, 39.0), Vector3(2.0, fy, -2.0), stone_trim)
	_box(jn, Vector3(50.0, 14.5, 38.5), Vector3(2.0, 13.5, -2.0), glass)
	# Ground-floor grand department store display windows (glowing warm inside)
	_box(jn, Vector3(48.0, 4.2, 38.6), Vector3(2.0, 2.3, -2.0), glow_warm, 0.0, 0.0, 0.0, false)
	# Iconic Curved/Chamfered SW Corner Glass Atrium Tower facing 中山东路/禾兴南路 intersection!
	_cyl(jn, 12.2, 12.2, 29.0, Vector3(-22.0, 14.5, 14.0), glass, 16)
	_cyl(jn, 12.8, 12.8, 1.2, Vector3(-22.0, 26.2, 14.0), accent_red, 16)
	_cyl(jn, 12.8, 12.8, 1.0, Vector3(-22.0, 29.2, 14.0), stone_trim, 16)
	_cyl(jn, 13.8, 13.8, 0.55, Vector3(-22.0, 5.2, 14.0), bronze, 16)
	# Upper Stepped Main Commercial Office Block (12-story, 48m total) + Crown
	_box(jn, Vector3(36.0, 22.0, 24.0), Vector3(6.0, 36.0, -5.0), stone_warm)
	_box(jn, Vector3(30.0, 18.0, 24.5), Vector3(6.0, 36.0, -5.0), glass)
	_box(jn, Vector3(38.0, 1.6, 26.0), Vector3(6.0, 47.4, -5.0), stone_trim)
	_box(jn, Vector3(24.0, 3.2, 14.0), Vector3(6.0, 49.6, -5.0), accent_red)
	# Iconic glowing red rooftop & corner signage facing South (中山东路) & West (禾兴南路)
	_box(jn, Vector3(32.0, 0.45, 0.45), Vector3(2.0, 25.4, 17.5), glow_red, 0.0, 0.0, 0.0, false)
	_sign(jn, "江  南  大  厦", Vector3(2.0, 27.6, 17.6), 0.0, 118, 0.036, Color(0.98, 0.20, 0.16))
	_sign(jn, "JIANGNAN DEPARTMENT STORE", Vector3(2.0, 24.2, 17.6), 0.0, 42, 0.024, Color(0.98, 0.90, 0.62))
	_sign(jn, "江  南  大  厦", Vector3(-26.5, 27.6, -2.0), -PI * 0.5, 110, 0.034, Color(0.98, 0.20, 0.16))
	_sign(jn, "江 南 大 厦", Vector3(6.0, 49.8, 2.4), 0.0, 96, 0.034, Color(0.98, 0.88, 0.34))
	_add_light(jn, Vector3(-18.0, 14.0, 24.0), Color(1.0, 0.88, 0.66), 60.0, lights)


# =============================================================================================
# 12. 戴梦得大厦 · 戴梦得购物中心 (Diamond Plaza & Landmark Hotel Tower with Revolving Restaurant)
# =============================================================================================
static func _diamond_plaza(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var dm := Node3D.new()
	dm.name = "DiamondPlazaTower"
	dm.position = center
	dm.rotation.y = angle
	parent.add_child(dm)

	var stone_silver := _mat(Color(0.76, 0.79, 0.84), 0.46, 0.18)
	var facade_navy := _mat(Color(0.14, 0.19, 0.30), 0.38, 0.40)
	var glass_blue := _glass(Color(0.18, 0.38, 0.62), 0.68)
	var gold := _mat(Color(0.92, 0.78, 0.30), 0.28, 0.74)
	var glow_gold := _emissive(Color(1.0, 0.86, 0.46), 1.9)
	var glow_blue := _emissive(Color(0.40, 0.74, 1.0), 1.7)
	var plaza := _mat(Color(0.78, 0.79, 0.81), 0.74)

	# --- A. 6-Story Diamond Shopping Center Podium (戴梦得购物中心, 60m x 46m x 24m) ---
	_box(dm, Vector3(72.0, 0.12, 58.0), Vector3(0.0, 0.06, 0.0), plaza, 0.0, 0.0, 0.0, false)
	_box(dm, Vector3(60.0, 24.0, 46.0), Vector3(0.0, 12.0, 0.0), stone_silver)
	_box(dm, Vector3(54.0, 16.5, 46.6), Vector3(0.0, 12.5, 0.0), glass_blue)
	_box(dm, Vector3(60.6, 16.5, 38.0), Vector3(0.0, 12.5, 0.0), glass_blue)
	for py: float in [5.4, 10.6, 15.8, 21.0, 24.2]:
		_box(dm, Vector3(61.4, 0.65, 47.4), Vector3(0.0, py, 0.0), facade_navy)
	# Faceted Diamond Entrance Canopy facing North (toward 中山东路) & East (toward 禾兴南路)
	_box(dm, Vector3(24.0, 1.1, 7.5), Vector3(0.0, 6.2, -25.5), facade_navy)
	_box(dm, Vector3(24.4, 0.3, 7.8), Vector3(0.0, 6.8, -25.5), glow_gold, 0.0, 0.0, 0.0, false)
	_box(dm, Vector3(7.5, 1.1, 22.0), Vector3(32.5, 6.2, 0.0), facade_navy)
	_box(dm, Vector3(7.8, 0.3, 22.4), Vector3(32.5, 6.8, 0.0), glow_gold, 0.0, 0.0, 0.0, false)

	# --- B. Iconic 88m Octagonal Skyscraper Tower + Crown Revolving Restaurant (戴梦得旋转餐厅!) ---
	_cyl(dm, 16.5, 17.5, 58.0, Vector3(-4.0, 53.0, 2.0), glass_blue, 8, Vector3(0.0, PI / 8.0, 0.0))
	for rib_k in range(8):
		var a := float(rib_k) * TAU / 8.0 + PI / 8.0
		_box(dm, Vector3(1.5, 58.5, 1.5), Vector3(-4.0 + cos(a) * 16.8, 53.0, 2.0 + sin(a) * 16.8), stone_silver, -a)
	for band_y: float in [36.0, 48.0, 60.0, 72.0, 81.5]:
		_cyl(dm, 17.3, 17.3, 0.75, Vector3(-4.0, band_y, 2.0), facade_navy, 8, Vector3(0.0, PI / 8.0, 0.0))
	# Signature Panoramic Circular Revolving Restaurant Drum at 82m..89m!
	_cyl(dm, 15.8, 13.8, 2.2, Vector3(-4.0, 83.2, 2.0), stone_silver, 20)
	_cyl(dm, 15.6, 15.6, 4.4, Vector3(-4.0, 86.5, 2.0), glow_gold, 20)
	_cyl(dm, 16.2, 16.2, 0.55, Vector3(-4.0, 84.4, 2.0), facade_navy, 20)
	_cyl(dm, 16.2, 16.2, 0.55, Vector3(-4.0, 88.8, 2.0), facade_navy, 20)
	_cyl(dm, 4.2, 15.2, 4.8, Vector3(-4.0, 91.4, 2.0), facade_navy, 16)
	_cyl(dm, 0.18, 0.55, 11.0, Vector3(-4.0, 99.0, 2.0), gold, 8)
	_box(dm, Vector3(1.8, 1.8, 1.8), Vector3(-4.0, 104.5, 2.0), glow_blue, 0.0, 0.0, 0.0, false)

	# Bilingual Signage facing North (中山东路) & East (禾兴南路)
	_sign(dm, "戴 梦 得 大 厦", Vector3(0.0, 22.8, -23.6), PI, 116, 0.036, Color(0.98, 0.86, 0.36))
	_sign(dm, "D I A M O N D   P L A Z A", Vector3(0.0, 19.4, -23.6), PI, 48, 0.026, Color(0.84, 0.92, 1.0))
	_sign(dm, "戴 梦 得 购 物 中 心", Vector3(30.6, 22.8, 0.0), PI * 0.5, 104, 0.034, Color(0.98, 0.86, 0.36))
	_sign(dm, "戴 梦 得", Vector3(-4.0, 77.5, -14.8), PI, 98, 0.042, Color(1.0, 0.90, 0.42))
	_add_light(dm, Vector3(0.0, 16.0, -30.0), Color(1.0, 0.90, 0.68), 64.0, lights)
	_add_light(dm, Vector3(34.0, 14.0, 0.0), Color(0.88, 0.94, 1.0), 58.0, lights)


# =============================================================================================
# 13. 旭辉广场 (Jiaxing CIFI Plaza — Modern Champagne-Gold Mall, Twin Towers & Sunken Forecourt on 中山东路)
# =============================================================================================
static func _cifi_plaza(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var cf := Node3D.new()
	cf.name = "JiaxingCIFIPlaza"
	cf.position = center
	cf.rotation.y = angle
	parent.add_child(cf)

	var champagne := _mat(Color(0.84, 0.74, 0.58), 0.36, 0.46)
	var stone_lt := _mat(Color(0.88, 0.86, 0.83), 0.56)
	var charcoal := _mat(Color(0.20, 0.22, 0.26), 0.46, 0.32)
	var glass := _glass(Color(0.26, 0.48, 0.62), 0.62)
	var glow_amber := _emissive(Color(1.0, 0.68, 0.24), 2.1)
	var glow_warm := _emissive(Color(1.0, 0.92, 0.76), 1.4)
	var water_fnt := _mat(Color(0.22, 0.56, 0.72), 0.14, 0.20)
	var plaza := _mat(Color(0.82, 0.80, 0.76), 0.74)

	# --- A. Broad Sunken Granite Forecourt Plaza facing 中山东路 (North, -Z) ---
	_box(cf, Vector3(96.0, 0.12, 68.0), Vector3(0.0, 0.06, -4.0), plaza, 0.0, 0.0, 0.0, false)
	# Reflecting fountain basin & illuminated CIFI sculptural totem in forecourt
	_cyl(cf, 7.5, 8.2, 0.65, Vector3(0.0, 0.35, -31.0), stone_lt, 18)
	_cyl(cf, 6.6, 6.6, 0.15, Vector3(0.0, 0.70, -31.0), water_fnt, 18)
	_box(cf, Vector3(1.8, 9.5, 1.8), Vector3(24.0, 4.75, -31.0), champagne)
	_box(cf, Vector3(2.0, 1.6, 2.0), Vector3(24.0, 8.2, -31.0), glow_amber, 0.0, 0.0, 0.0, false)

	# --- B. 5-Story Contemporary Champagne-Gold Shopping Mall Podium (84m x 42m x 22m) ---
	_box(cf, Vector3(84.0, 22.0, 42.0), Vector3(0.0, 11.0, 2.0), stone_lt)
	_box(cf, Vector3(76.0, 17.0, 42.6), Vector3(0.0, 10.5, 2.0), glass)
	# Signature sweeping horizontal champagne-gold louver ribbons along the 中山东路 facade
	for ly: float in [5.0, 9.4, 13.8, 18.2, 22.2]:
		_box(cf, Vector3(85.8, 0.85, 43.8), Vector3(0.0, ly, 2.0), champagne)
	# Dramatic recessed double-height central atrium portal with glowing golden arch
	_box(cf, Vector3(26.0, 14.0, 4.5), Vector3(0.0, 7.2, -20.5), charcoal)
	_box(cf, Vector3(22.0, 11.5, 4.8), Vector3(0.0, 6.0, -20.6), glow_warm, 0.0, 0.0, 0.0, false)
	_box(cf, Vector3(28.0, 1.4, 6.5), Vector3(0.0, 14.6, -21.2), champagne)
	_box(cf, Vector3(28.4, 0.35, 6.8), Vector3(0.0, 15.4, -21.2), glow_amber, 0.0, 0.0, 0.0, false)

	# --- C. Twin Modern Glass-and-Champagne Commercial / Apartment Towers (56m East + 46m West) ---
	_box(cf, Vector3(24.0, 34.0, 22.0), Vector3(24.0, 39.0, 8.0), glass)
	_box(cf, Vector3(25.2, 1.1, 23.2), Vector3(24.0, 56.2, 8.0), champagne)
	for tx_r: float in [12.0, 20.0, 28.0, 36.0]:
		_box(cf, Vector3(0.9, 34.5, 22.6), Vector3(tx_r, 39.0, 8.0), champagne)
	_box(cf, Vector3(22.0, 24.0, 20.0), Vector3(-25.0, 34.0, 8.0), glass)
	_box(cf, Vector3(23.2, 1.1, 21.2), Vector3(-25.0, 46.2, 8.0), champagne)
	for tx_l: float in [-36.0, -28.5, -21.5, -14.0]:
		_box(cf, Vector3(0.9, 24.5, 20.6), Vector3(tx_l, 34.0, 8.0), champagne)

	# Bold Glowing Signage facing North directly onto 中山东路 & T1 western terminus!
	_sign(cf, "旭  辉  广  场", Vector3(0.0, 20.6, -20.6), PI, 126, 0.038, Color(1.0, 0.72, 0.24))
	_sign(cf, "C I F I   P L A Z A", Vector3(0.0, 17.0, -20.6), PI, 52, 0.028, Color(0.98, 0.96, 0.92))
	_sign(cf, "旭 辉 广 场", Vector3(24.0, 53.5, -3.5), PI, 94, 0.036, Color(1.0, 0.76, 0.26))
	_add_light(cf, Vector3(0.0, 14.0, -28.0), Color(1.0, 0.84, 0.56), 68.0, lights)


# =============================================================================================
# 14. 少年路步行街 (Shaonian Road Historic Pedestrian Commercial Street — 中山东路 to 环城北路!)
#     Jiaxing's century-old vibrant pedestrian street west of Pingshan Park: granite promenade,
#     3 entrance archways, continuous 2-3 story Republic-era & Jiangnan shopfront arcades,
#     diverse illuminated signboards, striped awnings, overhead lantern garlands & street cafes!
# =============================================================================================
static func _shaonian_pedestrian_street(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var sn := Node3D.new()
	sn.name = "ShaonianPedestrianStreet"
	sn.position = center
	sn.rotation.y = angle
	parent.add_child(sn)

	var granite := _mat(Color(0.76, 0.74, 0.70), 0.78)
	var bluestone := _mat(Color(0.56, 0.57, 0.59), 0.80)
	var brick_grey := _mat(Color(0.46, 0.47, 0.50), 0.80)
	var brick_red := _mat(Color(0.62, 0.28, 0.22), 0.78)
	var cream := _mat(Color(0.90, 0.87, 0.81), 0.76)
	var tile_dark := _mat(Color(0.20, 0.22, 0.26), 0.56, 0.10)
	var wood_red := _mat(Color(0.58, 0.15, 0.12), 0.52)
	var glass := _glass(Color(0.28, 0.44, 0.58), 0.62)
	var warm := _emissive(Color(1.0, 0.88, 0.62), 1.3)
	var lantern_r := _emissive(Color(1.0, 0.28, 0.14), 2.0)
	var lantern_g := _emissive(Color(1.0, 0.78, 0.24), 1.9)
	var iron := _mat(Color(0.18, 0.20, 0.23), 0.44, 0.55)
	var shrub := _mat(Color(0.20, 0.48, 0.22), 0.86)

	var sign_mats := [
		_mat(Color(0.80, 0.12, 0.12), 0.42),
		_mat(Color(0.08, 0.34, 0.70), 0.42),
		_mat(Color(0.12, 0.48, 0.26), 0.44),
		_mat(Color(0.92, 0.58, 0.10), 0.42),
		_mat(Color(0.22, 0.16, 0.14), 0.44),
		_mat(Color(0.64, 0.12, 0.24), 0.42),
	]
	var awning_mats := [
		_mat(Color(0.76, 0.16, 0.14), 0.72),
		_mat(Color(0.10, 0.40, 0.30), 0.72),
		_mat(Color(0.16, 0.30, 0.58), 0.72),
		_mat(Color(0.86, 0.52, 0.14), 0.72),
	]
	var wall_mats := [cream, brick_grey, brick_red, _mat(Color(0.84, 0.81, 0.75), 0.76)]

	# --- A. 540m Continuous Patterned Granite & Bluestone Pedestrian Promenade (z in [-270 .. +270]) ---
	_box(sn, Vector3(15.0, 0.07, 544.0), Vector3(0.0, 0.035, 0.0), granite, 0.0, 0.0, 0.0, false)
	_box(sn, Vector3(4.6, 0.08, 540.0), Vector3(0.0, 0.042, 0.0), bluestone, 0.0, 0.0, 0.0, false)

	# --- B. 3 Grand Pedestrian Street Archways (South at 中山东路, Mid at 勤俭路, North at 环城北路) ---
	var arch_zs := [262.0, -48.0, -262.0]
	for ai in range(arch_zs.size()):
		var az: float = arch_zs[ai]
		for ax: float in [-6.4, -3.2, 3.2, 6.4]:
			_box(sn, Vector3(0.68, 8.2, 0.68), Vector3(ax, 4.1, az), wood_red)
			_box(sn, Vector3(1.15, 1.0, 1.15), Vector3(ax, 0.5, az), bluestone)
		_box(sn, Vector3(14.8, 1.1, 2.2), Vector3(0.0, 8.4, az), tile_dark)
		_box(sn, Vector3(8.8, 1.3, 2.8), Vector3(0.0, 9.6, az), tile_dark)
		var title_s := "少 年 路 步 行 街" if ai != 1 else "少 年 路 老 街"
		_sign(sn, title_s, Vector3(0.0, 7.8, az + 1.25), 0.0, 72, 0.024, Color(0.98, 0.86, 0.34))
		_sign(sn, title_s, Vector3(0.0, 7.8, az - 1.25), PI, 72, 0.024, Color(0.98, 0.86, 0.34))
		if ai == 0:
			_sign(sn, "SHAONIAN PEDESTRIAN STREET", Vector3(0.0, 6.5, az + 1.25), 0.0, 32, 0.018, Color(0.96, 0.96, 0.96))

	# --- C. Continuous 2-3 Story Republic-Era & Jiangnan Arcade Shopfronts along BOTH Sides! ---
	# Leave clean cross-street gaps at 勤俭路 (z ≈ -66..-40), 中和街 (z ≈ 54..72), 道前街 (z ≈ 162..178)
	var shop_names := [
		"五芳斋老店", "文虎酱鸭", "嘉兴老面馆", "真真老老", "霸王茶姬", "瑞幸咖啡",
		"蜜雪冰城", "丝绸百货", "老凤祥银楼", "百年糕点铺", "潮流服饰城", "新华书店",
		"古茗奶茶", "老娘舅快餐", "三元臭豆腐", "江南茶庄", "光明眼镜", "阿婆粽子",
	]
	var bay_idx := 0
	var bz := -246.0
	while bz <= 246.0:
		if (bz > -72.0 and bz < -34.0) or (bz > 48.0 and bz < 76.0) or (bz > 158.0 and bz < 182.0):
			bz += 16.0
			continue
		for side: float in [-1.0, 1.0]:
			var h_b := 7.6 + float((bay_idx * 7) % 3) * 2.4 # 7.6m / 10.0m / 12.4m authentic varied eaves!
			var w_mat: Material = wall_mats[(bay_idx + (1 if side > 0.0 else 0)) % wall_mats.size()]
			var s_mat: Material = sign_mats[(bay_idx * 3 + (2 if side > 0.0 else 0)) % sign_mats.size()]
			var a_mat: Material = awning_mats[(bay_idx + (1 if side > 0.0 else 0)) % awning_mats.size()]
			var bx := side * 12.2
			# Shopfront arcade building body + pitched dark Jiangnan gable roof
			_box(sn, Vector3(9.2, h_b, 14.8), Vector3(bx, h_b * 0.5, bz), w_mat)
			_box(sn, Vector3(10.6, 1.4, 15.2), Vector3(bx, h_b + 0.7, bz), tile_dark)
			# Ground-floor illuminated display glazing + vibrant shop fascia signboard + sloped striped awning
			var face_x := side * 7.55
			_box(sn, Vector3(0.28, 3.2, 12.4), Vector3(face_x, 1.75, bz), glass)
			_box(sn, Vector3(0.18, 2.7, 11.4), Vector3(face_x + side * 0.16, 1.65, bz), warm, 0.0, 0.0, 0.0, false)
			_box(sn, Vector3(0.55, 1.15, 13.6), Vector3(face_x - side * 0.15, 3.95, bz), s_mat)
			_box(sn, Vector3(1.6, 0.22, 12.8), Vector3(face_x - side * 0.8, 3.15, bz), a_mat, 0.0, side * 0.26)
			# Upper-floor arched/framed windows
			_box(sn, Vector3(0.24, 1.9, 9.6), Vector3(face_x, 6.2, bz), glass)
			if bay_idx % 2 == 0:
				var s_lbl: String = shop_names[(bay_idx + (5 if side > 0.0 else 0)) % shop_names.size()]
				_sign(sn, s_lbl, Vector3(face_x - side * 0.48, 3.98, bz), (-PI * 0.5 if side > 0.0 else PI * 0.5), 48, 0.020, Color(1.0, 0.96, 0.86))
			bay_idx += 1

		# Overhead festive red/gold lantern garlands spanning across the pedestrian street + planters & lamps!
		if int(round(bz)) % 30 == 0 or absf(fmod(bz + 300.0, 32.0)) < 15.0:
			_box(sn, Vector3(14.8, 0.06, 0.06), Vector3(0.0, 6.6, bz), iron, 0.0, 0.0, 0.0, false)
			for lx_g: float in [-4.5, -1.5, 1.5, 4.5]:
				_cyl(sn, 0.26, 0.22, 0.56, Vector3(lx_g, 6.2, bz), lantern_r if (int(absf(lx_g)) % 2 == 0) else lantern_g, 8)
		# Alternating center flower planters, benches & vintage globe streetlamps
		if bay_idx % 4 == 0:
			_box(sn, Vector3(2.2, 0.65, 2.2), Vector3(0.0, 0.35, bz), bluestone)
			_cyl(sn, 0.85, 1.1, 0.9, Vector3(0.0, 1.05, bz), shrub, 8)
			for ls: float in [-5.6, 5.6]:
				_cyl(sn, 0.08, 0.12, 4.4, Vector3(ls, 2.2, bz + 5.0), iron, 6)
				_cyl(sn, 0.28, 0.28, 0.36, Vector3(ls, 4.55, bz + 5.0), warm, 8)
		bz += 15.5

	_add_light(sn, Vector3(0.0, 10.0, 240.0), Color(1.0, 0.82, 0.48), 58.0, lights)
	_add_light(sn, Vector3(0.0, 10.0, 0.0), Color(1.0, 0.82, 0.48), 58.0, lights)
	_add_light(sn, Vector3(0.0, 10.0, -240.0), Color(1.0, 0.82, 0.48), 58.0, lights)
