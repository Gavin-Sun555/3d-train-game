class_name JiaxingLandmarks
extends RefCounted

# Bespoke 3D architectural landmarks for Jiaxing (嘉兴市):
#   1. 嘉兴南站 (Jiaxing South High-Speed Railway Station): sweeping silver wave-arch roof,
#      glass departure hall, bilingual signage, 4 covered HSR island platforms, 8 tracks,
#      catenary gantries, and sleek parked CR400 Fuxing high-speed trains.
#   2. 南湖湖心岛 · 烟雨楼 & 南湖红船 (Yanyu Pavilion & Red Boat on Nanhu Lake).
#   3. 南湖革命纪念馆 (Nanhu Revolutionary Memorial Hall): symmetrical red-sandstone & colonnade palace.
#   4. 嘉兴站 (Jiaxing Railway Station): MAD floating-canopy "Forest Station" + 1909 brick historic station.
#   5. 嘉兴植物园玻璃温室 (Botanical Garden Glass Conservatory) & Jiangnan stone arch bridges.

const SKIP_GENERIC := [
	"jiaxing_south_station",
	"nanhu_memorial",
	"yanyu_tower",
	"jiaxing_station",
]


static func build(parent: Node3D, map_data: Dictionary, lights: Array) -> void:
	var lm: Dictionary = map_data.get("landmarks", {})
	var root := Node3D.new()
	root.name = "JiaxingLandmarks"
	parent.add_child(root)

	if lm.has("jiaxing_south_station"):
		var s: Dictionary = lm["jiaxing_south_station"]
		_jiaxing_south_station(root, _p(s["pos"]), float(s.get("angle", -0.26)), lights)
	if lm.has("yanyu_tower"):
		var y: Dictionary = lm["yanyu_tower"]
		_yanyu_tower_and_red_boat(root, _p(y["pos"]), lights)
	if lm.has("nanhu_memorial"):
		var m: Dictionary = lm["nanhu_memorial"]
		_nanhu_memorial_hall(root, _p(m["pos"]), float(m.get("angle", 0.0)), lights)
	if lm.has("jiaxing_station"):
		var j: Dictionary = lm["jiaxing_station"]
		_jiaxing_station(root, _p(j["pos"]), float(j.get("angle", 0.12)), lights)
	if lm.has("botanical_conservatory"):
		var bc: Dictionary = lm["botanical_conservatory"]
		_botanical_conservatory(root, _p(bc["pos"]), lights)
	var bridges: Array = lm.get("canal_bridges", [])
	for br in bridges:
		if br is Dictionary:
			_jiangnan_arch_bridge(root, _p(br["pos"]), float(br.get("angle", 0.0)), float(br.get("span", 24.0)))


static func _p(a: Array) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1]))


static func _mat(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func _emissive(col: Color, energy: float = 1.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.35
	return m


static func _glass(col: Color, alpha: float = 0.62) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.38
	return m


static func _add_box(
	parent: Node3D,
	size: Vector3,
	pos: Vector3,
	mat: Material,
	rot_y: float = 0.0,
	rot_z: float = 0.0,
	rot_x: float = 0.0,
	shadow: bool = true
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(rot_x, rot_y, rot_z)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _add_cyl(
	parent: Node3D,
	r_top: float,
	r_bot: float,
	h: float,
	pos: Vector3,
	mat: Material,
	segs: int = 12,
	rot: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _add_sign_label(
	parent: Node3D,
	txt: String,
	pos: Vector3,
	rot_y: float,
	font_size: int,
	pixel_size: float,
	col: Color
) -> void:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = font_size
	lbl.pixel_size = pixel_size
	lbl.modulate = col
	lbl.outline_modulate = Color(0.18, 0.04, 0.04, 0.92)
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.shaded = false
	lbl.position = pos
	lbl.rotation.y = rot_y
	parent.add_child(lbl)


# =============================================================================================
# 1. 嘉兴南站 (Jiaxing South High-Speed Railway Station)
# =============================================================================================
static func _jiaxing_south_station(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var st := Node3D.new()
	st.name = "JiaxingSouthHSRStation"
	st.position = center
	st.rotation.y = angle
	parent.add_child(st)

	var roof_silver := _mat(Color(0.84, 0.87, 0.90), 0.30, 0.55)
	var roof_rib := _mat(Color(0.66, 0.70, 0.75), 0.35, 0.60)
	var steel_white := _mat(Color(0.90, 0.91, 0.93), 0.38, 0.22)
	var concrete := _mat(Color(0.75, 0.74, 0.72), 0.78, 0.02)
	var granite := _mat(Color(0.79, 0.78, 0.75), 0.68, 0.04)
	var dark_stone := _mat(Color(0.32, 0.34, 0.38), 0.62, 0.08)
	var glass_curtain := _glass(Color(0.28, 0.44, 0.58), 0.68)
	var warm_hall := _emissive(Color(1.0, 0.90, 0.72), 0.95)
	var sign_red := Color(0.90, 0.14, 0.14)
	var rail_steel := _mat(Color(0.45, 0.47, 0.50), 0.32, 0.75)
	var ballast := _mat(Color(0.46, 0.45, 0.43), 0.92, 0.0)
	var yellow_line := _mat(Color(0.94, 0.78, 0.18), 0.55, 0.0)

	# --- A. Elevated Station Concourse & North Plaza (local -Z = North side facing Qingfeng Rd) ---
	# North forecourt granite plaza
	_add_box(st, Vector3(210.0, 0.35, 86.0), Vector3(0.0, 0.18, -56.0), granite, 0.0, 0.0, 0.0, false)
	# Elevated station podium deck (departure level +4.2m)
	_add_box(st, Vector3(168.0, 4.2, 42.0), Vector3(0.0, 2.1, -34.0), concrete)
	# Grand entrance stair flight on north facade
	for si in range(7):
		var sh := 0.6 * float(si + 1)
		_add_box(st, Vector3(54.0, 0.6, 1.4), Vector3(0.0, sh - 0.3, -55.5 - float(6 - si) * 1.15), granite)

	# Main Departure Hall core (warm lit interior backing behind glass curtain wall)
	_add_box(st, Vector3(148.0, 14.5, 29.0), Vector3(0.0, 11.4, -34.0), warm_hall, 0.0, 0.0, 0.0, false)
	# Blue-tinted glass curtain walls on all four sides
	_add_box(st, Vector3(154.0, 15.8, 0.5), Vector3(0.0, 12.1, -49.5), glass_curtain)
	_add_box(st, Vector3(154.0, 15.8, 0.5), Vector3(0.0, 12.1, -18.5), glass_curtain)
	_add_box(st, Vector3(0.5, 15.8, 31.0), Vector3(-77.0, 12.1, -34.0), glass_curtain)
	_add_box(st, Vector3(0.5, 15.8, 31.0), Vector3(77.0, 12.1, -34.0), glass_curtain)

	# Exterior slender steel colonnade & vertical curtain-wall mullions
	for ci in range(-9, 10):
		var cx := float(ci) * 8.4
		_add_box(st, Vector3(0.65, 17.5, 0.85), Vector3(cx, 12.6, -50.2), steel_white)
		_add_box(st, Vector3(0.55, 16.2, 0.70), Vector3(cx, 12.1, -18.2), steel_white)
	# Horizontal transom beams
	for ty in [8.4, 13.4, 18.2]:
		_add_box(st, Vector3(156.0, 0.42, 0.75), Vector3(0.0, ty, -49.9), steel_white)

	# --- B. Iconic Sweeping Wave-Arch Silver Canopy Roof (18 arched segments spanning 186m) ---
	var n_seg := 18
	var span_x := 186.0
	for k in range(n_seg):
		var u0 := -0.5 + float(k) / float(n_seg)
		var u1 := -0.5 + float(k + 1) / float(n_seg)
		var um := (u0 + u1) * 0.5
		# Graceful double-crest Jiangnan wave silhouette (peaks at center, sweeps gently up at wingtips)
		var y0 := 21.0 + cos(u0 * PI) * 4.8 + pow(absf(u0 * 2.0), 3.0) * 1.8
		var y1 := 21.0 + cos(u1 * PI) * 4.8 + pow(absf(u1 * 2.0), 3.0) * 1.8
		var ym := (y0 + y1) * 0.5
		var dx := (u1 - u0) * span_x
		var dy := y1 - y0
		var seg_w := sqrt(dx * dx + dy * dy) + 0.35
		var tilt := atan2(dy, dx)
		# Deep cantilevered roof deck (covers hall + north drop-off canopy)
		_add_box(st, Vector3(seg_w, 1.05, 52.0), Vector3(um * span_x, ym, -36.0), roof_silver, 0.0, tilt)
		# Underside architectural rib
		_add_box(st, Vector3(0.65, 0.75, 50.0), Vector3(u0 * span_x, y0 - 0.65, -36.0), roof_rib)

	# Skylight clerestory band along roof spine
	_add_box(st, Vector3(110.0, 1.2, 7.5), Vector3(0.0, 26.2, -34.0), glass_curtain)

	# --- C. Iconic Red Roof Signage: "嘉兴南站" (North & South facing!) ---
	_add_box(st, Vector3(42.0, 0.45, 0.55), Vector3(0.0, 26.4, -61.8), steel_white)
	_add_sign_label(st, "嘉 兴 南 站", Vector3(0.0, 29.0, -61.9), PI, 130, 0.042, sign_red)
	_add_sign_label(st, "JIAXING SOUTH RAILWAY STATION", Vector3(0.0, 26.7, -61.9), PI, 40, 0.028, Color(0.95, 0.96, 0.98))
	_add_sign_label(st, "嘉 兴 南 站", Vector3(0.0, 29.0, -10.0), 0.0, 120, 0.038, sign_red)

	# --- D. High-Speed Rail Trackbed, 4 Covered Island Platforms, 8 Tracks & Overhead Catenary ---
	# Elevated HSR track viaduct deck extending along X (-240m .. +240m)
	_add_box(st, Vector3(460.0, 2.6, 62.0), Vector3(0.0, 1.3, 18.0), concrete, 0.0, 0.0, 0.0, false)
	_add_box(st, Vector3(460.0, 0.3, 58.0), Vector3(0.0, 2.75, 18.0), ballast, 0.0, 0.0, 0.0, false)

	# 4 Island Platforms at z = -1, +14, +29, +44 (between 8 tracks)
	var plat_zs := [-1.0, 13.5, 28.0, 42.5]
	var track_zs := [-7.5, 5.5, 8.0, 20.0, 22.5, 34.5, 37.0, 49.0]
	for pz: float in plat_zs:
		# Platform slab (length 310m, width 7.6m, height 1.25m above rail deck)
		_add_box(st, Vector3(310.0, 1.25, 7.6), Vector3(0.0, 3.4, pz), granite)
		# Yellow tactile safety lines along both edges
		_add_box(st, Vector3(308.0, 0.04, 0.28), Vector3(0.0, 4.05, pz - 3.35), yellow_line, 0.0, 0.0, 0.0, false)
		_add_box(st, Vector3(308.0, 0.04, 0.28), Vector3(0.0, 4.05, pz + 3.35), yellow_line, 0.0, 0.0, 0.0, false)
		# Sleek cantilevered white canopy over the platform
		_add_box(st, Vector3(302.0, 0.45, 9.2), Vector3(0.0, 10.2, pz), roof_silver)
		_add_box(st, Vector3(300.0, 0.14, 1.6), Vector3(0.0, 9.92, pz), warm_hall, 0.0, 0.0, 0.0, false)
		# Y-shaped steel canopy columns every 24m
		for pi in range(-6, 7):
			var px := float(pi) * 24.0
			_add_box(st, Vector3(0.55, 6.2, 0.55), Vector3(px, 7.1, pz), steel_white)
			_add_box(st, Vector3(0.4, 2.2, 0.35), Vector3(px, 9.3, pz - 1.1), steel_white, 0.0, 0.0, 0.55)
			_add_box(st, Vector3(0.4, 2.2, 0.35), Vector3(px, 9.3, pz + 1.1), steel_white, 0.0, 0.0, -0.55)

	# 8 High-Speed Steel Tracks (pairs of rails)
	for tz: float in track_zs:
		_add_box(st, Vector3(456.0, 0.18, 0.16), Vector3(0.0, 2.98, tz - 0.72), rail_steel, 0.0, 0.0, 0.0, false)
		_add_box(st, Vector3(456.0, 0.18, 0.16), Vector3(0.0, 2.98, tz + 0.72), rail_steel, 0.0, 0.0, 0.0, false)

	# Overhead HSR Catenary Gantry Portals beyond platform ends
	for gx in [-205.0, -172.0, 172.0, 205.0]:
		_add_box(st, Vector3(0.5, 9.2, 0.5), Vector3(gx, 7.2, -11.0), roof_rib)
		_add_box(st, Vector3(0.5, 9.2, 0.5), Vector3(gx, 7.2, 52.5), roof_rib)
		_add_box(st, Vector3(0.45, 0.55, 64.5), Vector3(gx, 11.4, 20.75), roof_rib)

	# Elevated Concourse Overpass Bridge connecting Main Hall across all 4 platforms
	_add_box(st, Vector3(46.0, 5.2, 60.0), Vector3(0.0, 13.8, 16.0), roof_silver)
	_add_box(st, Vector3(46.4, 3.6, 56.0), Vector3(0.0, 13.8, 16.0), glass_curtain)

	# --- E. Two Sleek Parked CR400 Fuxing High-Speed Trains at Platforms 2 & 4 ---
	_add_hsr_train(st, Vector3(-18.0, 3.1, track_zs[1]), 1.0)
	_add_hsr_train(st, Vector3(26.0, 3.1, track_zs[4]), -1.0)

	# --- F. North Plaza Tram T1 Hub Canopy & Plaza Lights ---
	_add_box(st, Vector3(44.0, 0.35, 11.0), Vector3(0.0, 5.4, -84.0), roof_silver)
	for tx in [-18.0, -6.0, 6.0, 18.0]:
		_add_box(st, Vector3(0.42, 5.2, 0.42), Vector3(tx, 2.7, -84.0), steel_white)
	_add_sign_label(st, "有轨电车 T1 线 · 嘉兴南站枢纽", Vector3(0.0, 6.1, -89.6), PI, 48, 0.025, Color(0.98, 0.85, 0.32))

	# Warm plaza architectural night spotlights
	for lx in [-56.0, 0.0, 56.0]:
		var pl := OmniLight3D.new()
		pl.position = Vector3(lx, 12.0, -66.0)
		pl.light_color = Color(1.0, 0.88, 0.68)
		pl.omni_range = 62.0
		pl.light_energy = 0.0
		pl.visible = false
		st.add_child(pl)
		lights.append(pl)


static func _add_hsr_train(parent: Node3D, pos: Vector3, heading: float) -> void:
	var tr := Node3D.new()
	tr.position = pos
	if heading < 0.0:
		tr.rotation.y = PI
	parent.add_child(tr)

	var body_white := _mat(Color(0.95, 0.96, 0.97), 0.24, 0.18)
	var stripe_red := _mat(Color(0.78, 0.12, 0.14), 0.28, 0.20)
	var window_dark := _mat(Color(0.08, 0.11, 0.16), 0.10, 0.55)
	var bogie_dark := _mat(Color(0.18, 0.19, 0.21), 0.72, 0.25)
	var head_glow := _emissive(Color(1.0, 0.96, 0.84), 2.2)

	# 8-car Fuxing CR400AF (~200m long!)
	var car_len := 24.4
	for ci in range(8):
		var cx := (float(ci) - 3.5) * (car_len + 0.4)
		var is_end := (ci == 0 or ci == 7)
		var body_l := car_len - (3.8 if is_end else 0.0)
		var body_x := cx + (-1.9 if ci == 7 else (1.9 if ci == 0 else 0.0))
		_add_box(tr, Vector3(body_l, 3.25, 3.26), Vector3(body_x, 2.05, 0.0), body_white)
		_add_box(tr, Vector3(body_l + 0.05, 0.88, 3.30), Vector3(body_x, 2.38, 0.0), window_dark, 0.0, 0.0, 0.0, false)
		_add_box(tr, Vector3(body_l + 0.08, 0.28, 3.32), Vector3(body_x, 1.52, 0.0), stripe_red, 0.0, 0.0, 0.0, false)
		_add_box(tr, Vector3(body_l - 1.0, 0.45, 2.7), Vector3(body_x, 0.35, 0.0), bogie_dark, 0.0, 0.0, 0.0, false)
		if is_end:
			var sgn := -1.0 if ci == 0 else 1.0
			var nx := cx + sgn * (car_len * 0.5 - 1.8)
			# Tapered aerodynamic nose cone
			_add_box(tr, Vector3(4.6, 2.35, 3.05), Vector3(nx + sgn * 1.4, 1.62, 0.0), body_white, 0.0, -sgn * 0.28)
			_add_box(tr, Vector3(3.2, 1.35, 2.55), Vector3(nx + sgn * 3.1, 1.12, 0.0), body_white, 0.0, -sgn * 0.16)
			_add_box(tr, Vector3(2.4, 0.72, 2.75), Vector3(nx + sgn * 1.2, 2.25, 0.0), window_dark, 0.0, -sgn * 0.36)
			_add_box(tr, Vector3(0.25, 0.24, 1.8), Vector3(nx + sgn * 4.5, 1.02, 0.0), head_glow, 0.0, 0.0, 0.0, false)


# =============================================================================================
# 2. 南湖湖心岛 · 烟雨楼 & 南湖红船 (Yanyu Tower & Red Boat on Nanhu Lake)
# =============================================================================================
static func _yanyu_tower_and_red_boat(parent: Node3D, center: Vector3, lights: Array) -> void:
	var nanhu := Node3D.new()
	nanhu.name = "NanhuYanyuTowerAndRedBoat"
	nanhu.position = center
	parent.add_child(nanhu)

	var stone_white := _mat(Color(0.86, 0.85, 0.81), 0.74, 0.0)
	var wall_plaster := _mat(Color(0.92, 0.90, 0.85), 0.80, 0.0)
	var wood_vermilion := _mat(Color(0.56, 0.15, 0.12), 0.55, 0.05)
	var tile_dark := _mat(Color(0.20, 0.22, 0.26), 0.58, 0.08)
	var gold_trim := _mat(Color(0.88, 0.72, 0.24), 0.32, 0.65)
	var lantern_glow := _emissive(Color(1.0, 0.72, 0.32), 2.0)

	# Raised stone terrace (台基) + carved balustrade
	_add_box(nanhu, Vector3(28.0, 2.2, 20.0), Vector3(0.0, 1.1, 0.0), stone_white)
	for bx in [-13.6, 13.6]:
		_add_box(nanhu, Vector3(0.4, 1.0, 19.6), Vector3(bx, 2.7, 0.0), stone_white)
	for bz in [-9.6, 9.6]:
		_add_box(nanhu, Vector3(27.6, 1.0, 0.4), Vector3(0.0, 2.7, bz), stone_white)

	# Ground Floor Hall (一层大厅)
	_add_box(nanhu, Vector3(20.0, 5.2, 13.0), Vector3(0.0, 4.8, 0.0), wall_plaster)
	for cx in [-10.6, -5.3, 0.0, 5.3, 10.6]:
		for cz in [-7.1, 7.1]:
			_add_cyl(nanhu, 0.26, 0.28, 5.2, Vector3(cx, 4.8, cz), wood_vermilion, 10)
	# Lower Upturned Eave Roof (下层飞檐)
	_add_box(nanhu, Vector3(25.2, 0.55, 17.8), Vector3(0.0, 7.55, 0.0), tile_dark)
	_add_box(nanhu, Vector3(23.4, 0.65, 16.0), Vector3(0.0, 8.15, 0.0), tile_dark)

	# Second Story Pavilion (二层烟雨楼)
	_add_box(nanhu, Vector3(15.6, 4.6, 9.8), Vector3(0.0, 10.6, 0.0), wall_plaster)
	for cx in [-8.3, -4.15, 0.0, 4.15, 8.3]:
		for cz in [-5.4, 5.4]:
			_add_cyl(nanhu, 0.22, 0.24, 4.6, Vector3(cx, 10.6, cz), wood_vermilion, 10)

	# Upper Stepped Chinese Hip-and-Gable Roof (重檐歇山顶)
	for ri in range(5):
		var frac := float(ri) / 4.0
		var rw := lerpf(21.4, 10.6, frac)
		var rd := lerpf(15.2, 2.0, frac)
		_add_box(nanhu, Vector3(rw, 0.82, rd), Vector3(0.0, 13.2 + float(ri) * 0.78, 0.0), tile_dark)
	# Main roof ridge + golden finials (正脊吻兽)
	_add_box(nanhu, Vector3(11.4, 0.65, 0.75), Vector3(0.0, 16.85, 0.0), tile_dark)
	_add_box(nanhu, Vector3(0.75, 1.3, 0.75), Vector3(-5.5, 17.5, 0.0), gold_trim)
	_add_box(nanhu, Vector3(0.75, 1.3, 0.75), Vector3(5.5, 17.5, 0.0), gold_trim)

	# Iconic Plaque "烟雨楼" & hanging red lanterns
	_add_sign_label(nanhu, "烟 雨 楼", Vector3(0.0, 12.2, 5.8), 0.0, 72, 0.024, Color(0.96, 0.82, 0.30))
	for lx in [-7.5, 7.5]:
		_add_cyl(nanhu, 0.32, 0.28, 0.75, Vector3(lx, 6.7, 7.4), lantern_glow, 10)
		_add_cyl(nanhu, 0.28, 0.24, 0.65, Vector3(lx * 0.75, 12.1, 5.7), lantern_glow, 10)

	# Warm night light for Yanyu Tower
	var nl := OmniLight3D.new()
	nl.position = Vector3(0.0, 9.5, 11.0)
	nl.light_color = Color(1.0, 0.78, 0.42)
	nl.omni_range = 42.0
	nl.light_energy = 0.0
	nl.visible = false
	nanhu.add_child(nl)
	lights.append(nl)

	# --- 南湖红船 (The Historic Red Boat) moored at SE timber pier of Lake Heart Island ---
	var boat := Node3D.new()
	boat.name = "NanhuRedBoat"
	boat.position = Vector3(34.0, 0.0, 26.0)
	boat.rotation.y = -0.52
	nanhu.add_child(boat)

	var hull_wood := _mat(Color(0.48, 0.18, 0.11), 0.52, 0.04)
	var cabin_wood := _mat(Color(0.58, 0.22, 0.14), 0.48, 0.04)
	var pier_wood := _mat(Color(0.40, 0.30, 0.21), 0.78, 0.0)
	# Timber mooring jetty
	_add_box(boat, Vector3(2.8, 0.35, 12.0), Vector3(-6.2, 0.38, -2.5), pier_wood)
	# Boat hull (16m long Jiangnan huafang)
	_add_box(boat, Vector3(13.5, 1.05, 3.2), Vector3(0.0, 0.48, 0.0), hull_wood)
	_add_box(boat, Vector3(3.0, 0.95, 2.1), Vector3(7.6, 0.62, 0.0), hull_wood, 0.0, 0.14)
	_add_box(boat, Vector3(2.8, 0.95, 2.2), Vector3(-7.4, 0.58, 0.0), hull_wood, 0.0, -0.12)
	# Ornate central cabin + double-curved roof
	_add_box(boat, Vector3(8.6, 2.1, 2.6), Vector3(-0.3, 1.95, 0.0), cabin_wood)
	_add_box(boat, Vector3(7.8, 0.9, 2.66), Vector3(-0.3, 2.1, 0.0), lantern_glow, 0.0, 0.0, 0.0, false)
	_add_box(boat, Vector3(10.2, 0.38, 3.4), Vector3(-0.3, 3.15, 0.0), tile_dark)
	_add_box(boat, Vector3(9.0, 0.35, 2.2), Vector3(-0.3, 3.48, 0.0), tile_dark)


# =============================================================================================
# 3. 南湖革命纪念馆 (Nanhu Revolutionary Memorial Hall)
# =============================================================================================
static func _nanhu_memorial_hall(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var mh := Node3D.new()
	mh.name = "NanhuRevolutionaryMemorialHall"
	mh.position = center
	mh.rotation.y = angle
	parent.add_child(mh)

	var red_sandstone := _mat(Color(0.68, 0.31, 0.23), 0.72, 0.04)
	var cream_stone := _mat(Color(0.88, 0.84, 0.76), 0.64, 0.04)
	var granite := _mat(Color(0.76, 0.75, 0.73), 0.72, 0.02)
	var gold_emblem := _mat(Color(0.92, 0.76, 0.24), 0.28, 0.70)
	var glass_dark := _glass(Color(0.22, 0.28, 0.36), 0.72)

	# Ceremonial granite plaza & stepped podium
	_add_box(mh, Vector3(132.0, 0.35, 92.0), Vector3(0.0, 0.18, 0.0), granite, 0.0, 0.0, 0.0, false)
	_add_box(mh, Vector3(108.0, 3.2, 54.0), Vector3(0.0, 1.6, 4.0), red_sandstone)
	# Wide grand stairs on north facade facing Nanhu Lake
	for si in range(6):
		_add_box(mh, Vector3(68.0, 0.52, 1.4), Vector3(0.0, 0.26 + float(si) * 0.52, -23.5 - float(5 - si) * 1.25), granite)

	# Iconic "工"-shaped symmetrical main palace & wings
	_add_box(mh, Vector3(96.0, 17.5, 42.0), Vector3(0.0, 11.9, 4.0), red_sandstone)
	# Recessed central entrance glass hall
	_add_box(mh, Vector3(52.0, 14.2, 4.0), Vector3(0.0, 10.3, -16.5), glass_dark)
	# Grand 14-column cream-limestone colonnade across the north facade
	for ci in range(-6, 7):
		var cx := float(ci) * 6.8
		_add_box(mh, Vector3(1.65, 16.5, 1.85), Vector3(cx, 11.4, -20.5), cream_stone)
		_add_box(mh, Vector3(2.2, 1.0, 2.3), Vector3(cx, 3.6, -20.5), cream_stone)
		_add_box(mh, Vector3(2.2, 0.9, 2.3), Vector3(cx, 19.6, -20.5), cream_stone)
	# Monumental stepped entablature & overhang roof
	_add_box(mh, Vector3(106.0, 2.8, 52.0), Vector3(0.0, 21.5, 3.0), cream_stone)
	_add_box(mh, Vector3(110.0, 1.2, 55.0), Vector3(0.0, 23.4, 3.0), red_sandstone)
	# Gold emblem & plaque
	_add_cyl(mh, 2.4, 2.4, 0.45, Vector3(0.0, 21.6, -23.2), gold_emblem, 18, Vector3(PI * 0.5, 0.0, 0.0))
	_add_sign_label(mh, "南 湖 革 命 纪 念 馆", Vector3(0.0, 17.4, -23.3), PI, 88, 0.028, Color(0.96, 0.84, 0.34))

	# Ceremonial flagpole in north plaza
	_add_cyl(mh, 0.14, 0.24, 24.0, Vector3(0.0, 12.0, -39.0), _mat(Color(0.85, 0.87, 0.90), 0.25, 0.8), 10)
	_add_box(mh, Vector3(4.2, 2.6, 0.1), Vector3(2.1, 22.3, -39.0), _mat(Color(0.86, 0.12, 0.12), 0.6))

	var pl := OmniLight3D.new()
	pl.position = Vector3(0.0, 15.0, -28.0)
	pl.light_color = Color(1.0, 0.88, 0.66)
	pl.omni_range = 56.0
	pl.light_energy = 0.0
	pl.visible = false
	mh.add_child(pl)
	lights.append(pl)


# =============================================================================================
# 4. 嘉兴站 ("森林中的火车站" + 1909 历史老站房)
# =============================================================================================
static func _jiaxing_station(parent: Node3D, center: Vector3, angle: float, lights: Array) -> void:
	var jx := Node3D.new()
	jx.name = "JiaxingForestRailwayStation"
	jx.position = center
	jx.rotation.y = angle
	parent.add_child(jx)

	var solar_dark := _mat(Color(0.16, 0.20, 0.26), 0.28, 0.58)
	var ceiling_wood := _mat(Color(0.76, 0.58, 0.38), 0.62, 0.04)
	var steel_white := _mat(Color(0.92, 0.93, 0.95), 0.36, 0.22)
	var brick_red := _mat(Color(0.60, 0.28, 0.22), 0.80, 0.0)
	var brick_grey := _mat(Color(0.46, 0.48, 0.50), 0.78, 0.0)
	var tile_grey := _mat(Color(0.28, 0.30, 0.34), 0.64, 0.06)
	var glass_clear := _glass(Color(0.36, 0.52, 0.64), 0.55)
	var warm_glow := _emissive(Color(1.0, 0.90, 0.70), 0.85)

	# Modern MAD "Train Station in the Forest" floating cantilevered roof (124m x 42m)
	_add_box(jx, Vector3(124.0, 0.55, 42.0), Vector3(0.0, 9.8, 0.0), solar_dark)
	_add_box(jx, Vector3(122.0, 0.32, 40.0), Vector3(0.0, 9.35, 0.0), ceiling_wood)
	_add_box(jx, Vector3(92.0, 7.6, 26.0), Vector3(0.0, 4.0, 0.0), glass_clear)
	_add_box(jx, Vector3(86.0, 6.2, 22.0), Vector3(0.0, 3.4, 0.0), warm_glow, 0.0, 0.0, 0.0, false)
	for ci in range(-6, 7):
		var cx := float(ci) * 9.6
		_add_cyl(jx, 0.28, 0.32, 9.4, Vector3(cx, 4.7, -18.0), steel_white, 10)
		_add_cyl(jx, 0.28, 0.32, 9.4, Vector3(cx, 4.7, 18.0), steel_white, 10)
	_add_sign_label(jx, "嘉 兴 站", Vector3(0.0, 11.4, 21.2), 0.0, 100, 0.032, Color(0.92, 0.16, 0.16))

	# 1909 Historic Brick Old Jiaxing Station (嘉兴老火车站) reconstructed in front plaza
	var old_st := Node3D.new()
	old_st.position = Vector3(-42.0, 0.0, 38.0)
	jx.add_child(old_st)
	_add_box(old_st, Vector3(36.0, 10.2, 14.0), Vector3(0.0, 5.1, 0.0), brick_red)
	_add_box(old_st, Vector3(36.4, 1.4, 14.4), Vector3(0.0, 0.7, 0.0), brick_grey)
	_add_box(old_st, Vector3(36.4, 0.55, 14.4), Vector3(0.0, 5.4, 0.0), steel_white)
	_add_box(old_st, Vector3(12.0, 12.6, 15.2), Vector3(0.0, 6.3, 0.0), brick_red)
	# Pitched grey tile roof
	_add_box(old_st, Vector3(38.0, 0.6, 9.2), Vector3(0.0, 11.4, -3.5), tile_grey, 0.0, 0.0, 0.42)
	_add_box(old_st, Vector3(38.0, 0.6, 9.2), Vector3(0.0, 11.4, 3.5), tile_grey, 0.0, 0.0, -0.42)
	_add_sign_label(old_st, "嘉 兴 老 站", Vector3(0.0, 13.4, 7.8), 0.0, 56, 0.022, Color(0.96, 0.88, 0.62))

	var pl := OmniLight3D.new()
	pl.position = Vector3(0.0, 8.5, 24.0)
	pl.light_color = Color(1.0, 0.88, 0.68)
	pl.omni_range = 48.0
	pl.light_energy = 0.0
	pl.visible = false
	jx.add_child(pl)
	lights.append(pl)


# =============================================================================================
# 5. 嘉兴植物园玻璃温室 & 江南石拱桥
# =============================================================================================
static func _botanical_conservatory(parent: Node3D, center: Vector3, lights: Array) -> void:
	var bc := Node3D.new()
	bc.name = "JiaxingBotanicalConservatory"
	bc.position = center
	parent.add_child(bc)

	var frame_white := _mat(Color(0.90, 0.92, 0.94), 0.34, 0.28)
	var glass_dome := _glass(Color(0.54, 0.78, 0.76), 0.52)
	var foliage := _mat(Color(0.22, 0.52, 0.26), 0.82, 0.0)

	# Stepped octagonal steel-and-glass dome conservatory
	_add_cyl(bc, 14.5, 15.0, 2.2, Vector3(0.0, 1.1, 0.0), _mat(Color(0.80, 0.79, 0.75), 0.72), 12)
	_add_cyl(bc, 12.2, 14.2, 6.4, Vector3(0.0, 5.4, 0.0), glass_dome, 12)
	_add_cyl(bc, 6.8, 12.0, 4.6, Vector3(0.0, 10.9, 0.0), glass_dome, 12)
	_add_cyl(bc, 0.8, 6.8, 2.8, Vector3(0.0, 14.6, 0.0), glass_dome, 12)
	# Vertical structural ribs & interior tropical canopy mass
	for ri in range(6):
		var a := float(ri) * PI / 6.0
		_add_box(bc, Vector3(28.5, 0.35, 0.35), Vector3(0.0, 8.6, 0.0), frame_white, a)
	_add_cyl(bc, 8.5, 10.5, 6.2, Vector3(0.0, 4.8, 0.0), foliage, 10)

	var pl := OmniLight3D.new()
	pl.position = Vector3(0.0, 8.0, 0.0)
	pl.light_color = Color(0.92, 1.0, 0.84)
	pl.omni_range = 34.0
	pl.light_energy = 0.0
	pl.visible = false
	bc.add_child(pl)
	lights.append(pl)


static func _jiangnan_arch_bridge(parent: Node3D, center: Vector3, angle: float, span: float) -> void:
	var br := Node3D.new()
	br.position = center
	br.rotation.y = angle
	parent.add_child(br)

	var stone := _mat(Color(0.82, 0.81, 0.77), 0.76, 0.0)
	var rail := _mat(Color(0.88, 0.87, 0.83), 0.70, 0.0)
	var segs := 10
	for k in range(segs):
		var u0 := -0.5 + float(k) / float(segs)
		var u1 := -0.5 + float(k + 1) / float(segs)
		var um := (u0 + u1) * 0.5
		var h0 := 0.5 + cos(u0 * PI) * 3.1
		var h1 := 0.5 + cos(u1 * PI) * 3.1
		var dx := (u1 - u0) * span
		var dy := h1 - h0
		var sl := sqrt(dx * dx + dy * dy) + 0.12
		var tilt := atan2(dy, dx)
		_add_box(br, Vector3(sl, 0.55, 5.2), Vector3(um * span, (h0 + h1) * 0.5, 0.0), stone, 0.0, tilt)
		_add_box(br, Vector3(sl, 0.95, 0.28), Vector3(um * span, (h0 + h1) * 0.5 + 0.72, -2.45), rail, 0.0, tilt)
		_add_box(br, Vector3(sl, 0.95, 0.28), Vector3(um * span, (h0 + h1) * 0.5 + 0.72, 2.45), rail, 0.0, tilt)
