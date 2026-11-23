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

	var south_sta_pos := Vector3(4190.0, 0.0, 6883.0)
	if lm.has("jiaxing_south_station"):
		var s: Dictionary = lm["jiaxing_south_station"]
		south_sta_pos = _p(s["pos"])
		_jiaxing_south_station(root, south_sta_pos, float(s.get("angle", 0.47)), lights)
	if lm.has("yanyu_tower"):
		var y: Dictionary = lm["yanyu_tower"]
		_yanyu_tower_and_red_boat(root, _p(y["pos"]), y.get("island_pts", []), lights)
	if lm.has("nanhu_memorial"):
		var m: Dictionary = lm["nanhu_memorial"]
		_nanhu_memorial_hall(root, _p(m["pos"]), float(m.get("angle", 0.0)), lights)
	if lm.has("jiaxing_station"):
		var j: Dictionary = lm["jiaxing_station"]
		_jiaxing_station(root, _p(j["pos"]), float(j.get("angle", 0.788)), lights)
	if lm.has("botanical_conservatory"):
		var bc: Dictionary = lm["botanical_conservatory"]
		_botanical_conservatory(root, _p(bc["pos"]), lights)
	JiaxingCivicLandmarks.build(root, lm, lights)
	var bridges: Array = lm.get("canal_bridges", [])
	for br in bridges:
		if br is Dictionary:
			_jiangnan_arch_bridge(root, _p(br["pos"]), float(br.get("angle", 0.0)), float(br.get("span", 24.0)))
	var rail_crossings: Array = lm.get("rail_crossings", [])
	for rc in rail_crossings:
		if rc is Dictionary:
			_build_rail_crossing(root, rc)
	var railways: Array = map_data.get("railways", [])
	if not railways.is_empty():
		_build_railways(root, railways, south_sta_pos, rail_crossings)


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
	# North forecourt granite terrace (kept strictly below road/track level & clear of north tram road at z=-84)
	_add_box(st, Vector3(174.0, 0.06, 28.0), Vector3(0.0, -0.01, -60.0), granite, 0.0, 0.0, 0.0, false)
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
# 2. 南湖湖心岛 · 烟雨楼 & 南湖红船 (Lake Heart Island, Yanyu Tower & Red Boat on Nanhu Lake)
# =============================================================================================
static func _yanyu_tower_and_red_boat(parent: Node3D, center: Vector3, island_pts: Array, lights: Array) -> void:
	var nanhu := Node3D.new()
	nanhu.name = "NanhuYanyuTowerAndRedBoat"
	nanhu.position = center
	parent.add_child(nanhu)

	var stone_white := _mat(Color(0.86, 0.85, 0.81), 0.74, 0.0)
	var seawall_stone := _mat(Color(0.76, 0.75, 0.71), 0.82, 0.0)
	var wall_plaster := _mat(Color(0.92, 0.90, 0.85), 0.80, 0.0)
	var wood_vermilion := _mat(Color(0.56, 0.15, 0.12), 0.55, 0.05)
	var tile_dark := _mat(Color(0.20, 0.22, 0.26), 0.58, 0.08)
	var gold_trim := _mat(Color(0.88, 0.72, 0.24), 0.32, 0.65)
	var lantern_glow := _emissive(Color(1.0, 0.72, 0.32), 2.0)

	# --- Carved White-Stone Jiangnan Island Seawall (湖心岛石驳岸) & Perimeter Weeping Willows ---
	var trunk_mat := _mat(Color(0.32, 0.24, 0.17), 0.88, 0.0)
	var willow_mat := _mat(Color(0.28, 0.52, 0.22), 0.82, 0.0)
	var cypress_mat := _mat(Color(0.16, 0.36, 0.17), 0.84, 0.0)
	if island_pts.size() >= 3:
		var wall_st := SurfaceTool.new()
		wall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var local_ring: Array[Vector2] = []
		for raw_p in island_pts:
			local_ring.append(Vector2(float(raw_p[0]) - center.x, float(raw_p[1]) - center.z))
		var tree_acc := 0.0
		var tree_idx := 0
		for i in range(local_ring.size()):
			var a := local_ring[i]
			var b := local_ring[(i + 1) % local_ring.size()]
			var seg := b - a
			var slen := seg.length()
			if slen < 0.4:
				continue
			# Stone embankment coping beam along the island's real OSM shoreline
			_st_box_along(wall_st, a, b, 1.9, 0.0, 0.54)
			# Place Jiangnan weeping willows & lakeside cypresses ~6m inside the seawall
			tree_acc += slen
			if tree_acc >= 14.5:
				tree_acc = 0.0
				var mid := (a + b) * 0.5
				var to_in := -mid.normalized()
				var tp := mid + to_in * 6.5
				# Keep clear of Yanyu Tower terrace and SE Red Boat pier
				if tp.length() > 19.0 and tp.distance_to(Vector2(34.0, 26.0)) > 16.0:
					var is_willow := (tree_idx % 3 != 0)
					var th := 5.5 + float(tree_idx % 4) * 1.1
					_add_cyl(nanhu, 0.24, 0.36, th * 0.55, Vector3(tp.x, th * 0.28, tp.y), trunk_mat, 7)
					var crown_r := 4.0 if is_willow else 2.8
					_add_cyl(nanhu, crown_r * 0.55, crown_r, th * 0.62, Vector3(tp.x, th * 0.68, tp.y), willow_mat if is_willow else cypress_mat, 8)
					_add_cyl(nanhu, crown_r * 0.2, crown_r * 0.72, th * 0.35, Vector3(tp.x, th * 0.98, tp.y), willow_mat if is_willow else cypress_mat, 8)
					tree_idx += 1
		var wall_mi := MeshInstance3D.new()
		wall_mi.name = "LakeHeartIslandSeawall"
		wall_mi.mesh = wall_st.commit()
		seawall_stone.cull_mode = BaseMaterial3D.CULL_DISABLED
		wall_mi.material_override = seawall_stone
		nanhu.add_child(wall_mi)

	# Paved stone island courtyard pathways & north lakeside viewing pavilion (观湖亭)
	_add_box(nanhu, Vector3(4.2, 0.16, 48.0), Vector3(0.0, 0.28, 0.0), stone_white, 0.0, 0.0, 0.0, false)
	_add_box(nanhu, Vector3(44.0, 0.16, 4.2), Vector3(12.0, 0.28, 12.0), stone_white, -0.35, 0.0, 0.0, false)
	# Octagonal riverside pavilion on north point of island
	var pav_pos := Vector3(-16.0, 0.0, -32.0)
	_add_cyl(nanhu, 4.6, 5.0, 0.9, pav_pos + Vector3(0.0, 0.45, 0.0), stone_white, 8)
	for pi in range(6):
		var pa := float(pi) * TAU / 6.0
		_add_cyl(nanhu, 0.16, 0.18, 3.6, pav_pos + Vector3(cos(pa) * 3.4, 2.7, sin(pa) * 3.4), wood_vermilion, 8)
	_add_cyl(nanhu, 0.6, 5.6, 2.5, pav_pos + Vector3(0.0, 5.6, 0.0), tile_dark, 8)
	_add_cyl(nanhu, 0.12, 0.28, 0.9, pav_pos + Vector3(0.0, 7.1, 0.0), gold_trim, 8)

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

	# Ceremonial granite plaza & stepped podium (flush below street/track surface so tracks never get covered)
	_add_box(mh, Vector3(118.0, 0.06, 72.0), Vector3(0.0, -0.01, 0.0), granite, 0.0, 0.0, 0.0, false)
	_add_box(mh, Vector3(108.0, 3.2, 54.0), Vector3(0.0, 1.6, 4.0), red_sandstone)
	# Wide grand stairs on north facade facing Nanhu Lake
	for si in range(6):
		_add_box(mh, Vector3(68.0, 0.52, 1.4), Vector3(0.0, 0.26 + float(si) * 0.52, -23.5 - float(5 - si) * 1.25), granite)

	# Iconic "工"-shaped symmetrical main palace (North wing + Central hall + South wing!)
	_add_box(mh, Vector3(106.0, 17.5, 22.0), Vector3(0.0, 11.9, -10.0), red_sandstone)
	_add_box(mh, Vector3(58.0, 19.2, 26.0), Vector3(0.0, 12.8, 8.0), red_sandstone)
	_add_box(mh, Vector3(106.0, 17.5, 22.0), Vector3(0.0, 11.9, 26.0), red_sandstone)
	# Recessed central entrance glass halls on both north & south facades
	_add_box(mh, Vector3(52.0, 14.2, 4.0), Vector3(0.0, 10.3, -20.5), glass_dark)
	_add_box(mh, Vector3(52.0, 14.2, 4.0), Vector3(0.0, 10.3, 36.5), glass_dark)
	# Grand 14-column cream-limestone colonnades across BOTH north & south facades
	for ci in range(-6, 7):
		var cx := float(ci) * 7.6
		for cz: float in [-23.5, 39.5]:
			_add_box(mh, Vector3(1.65, 16.5, 1.85), Vector3(cx, 11.4, cz), cream_stone)
			_add_box(mh, Vector3(2.2, 1.0, 2.3), Vector3(cx, 3.6, cz), cream_stone)
			_add_box(mh, Vector3(2.2, 0.9, 2.3), Vector3(cx, 19.6, cz), cream_stone)
	# Monumental stepped entablature & overhang roof crowning the "工"-shaped hall
	_add_box(mh, Vector3(114.0, 2.8, 28.0), Vector3(0.0, 21.5, -10.0), cream_stone)
	_add_box(mh, Vector3(118.0, 1.2, 30.0), Vector3(0.0, 23.4, -10.0), red_sandstone)
	_add_box(mh, Vector3(64.0, 3.0, 28.0), Vector3(0.0, 22.6, 8.0), cream_stone)
	_add_box(mh, Vector3(114.0, 2.8, 28.0), Vector3(0.0, 21.5, 26.0), cream_stone)
	_add_box(mh, Vector3(118.0, 1.2, 30.0), Vector3(0.0, 23.4, 26.0), red_sandstone)
	# Gold emblem & plaque
	_add_cyl(mh, 2.4, 2.4, 0.45, Vector3(0.0, 21.6, -25.4), gold_emblem, 18, Vector3(PI * 0.5, 0.0, 0.0))
	_add_sign_label(mh, "南 湖 革 命 纪 念 馆", Vector3(0.0, 17.4, -25.5), PI, 88, 0.028, Color(0.96, 0.84, 0.34))

	# Ceremonial north reflecting pool, twin red-granite historical relief walls & flagpole
	_add_box(mh, Vector3(38.0, 0.25, 14.0), Vector3(0.0, 0.14, -46.0), _mat(Color(0.14, 0.40, 0.52), 0.12, 0.22), 0.0, 0.0, 0.0, false)
	for rx: float in [-34.0, 34.0]:
		_add_box(mh, Vector3(18.0, 4.2, 1.6), Vector3(rx, 2.1, -46.0), red_sandstone)
	_add_cyl(mh, 0.14, 0.24, 26.0, Vector3(0.0, 13.0, -58.0), _mat(Color(0.85, 0.87, 0.90), 0.25, 0.8), 10)
	_add_box(mh, Vector3(4.4, 2.8, 0.1), Vector3(2.2, 24.0, -58.0), _mat(Color(0.86, 0.12, 0.12), 0.6))

	var pl := OmniLight3D.new()
	pl.position = Vector3(0.0, 15.0, -28.0)
	pl.light_color = Color(1.0, 0.88, 0.66)
	pl.omni_range = 56.0
	pl.light_energy = 0.0
	pl.visible = false
	mh.add_child(pl)
	lights.append(pl)


# =============================================================================================
# 4. 嘉兴火车站 ("森林中的火车站" + 1909 历史老站房 + 沪昆线站台与绿巨人列车)
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
	var roof_silver := _mat(Color(0.80, 0.83, 0.87), 0.34, 0.48)
	var granite := _mat(Color(0.78, 0.77, 0.74), 0.70, 0.03)
	var yellow_line := _mat(Color(0.94, 0.78, 0.18), 0.55, 0.0)
	var brick_red := _mat(Color(0.60, 0.28, 0.22), 0.80, 0.0)
	var brick_grey := _mat(Color(0.46, 0.48, 0.50), 0.78, 0.0)
	var tile_grey := _mat(Color(0.28, 0.30, 0.34), 0.64, 0.06)
	var glass_clear := _glass(Color(0.36, 0.52, 0.64), 0.55)
	var warm_glow := _emissive(Color(1.0, 0.90, 0.70), 0.85)

	# --- A. 3 Covered Rail Platforms along real 沪昆线 tracks (local X = NE-SW track axis) ---
	for pz: float in [-18.5, 0.0, 18.5]:
		# Platform slab (290m long, 7.2m wide, 1.25m high)
		_add_box(jx, Vector3(290.0, 1.25, 7.2), Vector3(0.0, 0.65, pz), granite)
		_add_box(jx, Vector3(288.0, 0.04, 0.26), Vector3(0.0, 1.30, pz - 3.15), yellow_line, 0.0, 0.0, 0.0, false)
		_add_box(jx, Vector3(288.0, 0.04, 0.26), Vector3(0.0, 1.30, pz + 3.15), yellow_line, 0.0, 0.0, 0.0, false)
		# Sleek modern cantilevered platform canopy (warm timber soffit + dark metal roof)
		_add_box(jx, Vector3(268.0, 0.38, 8.8), Vector3(0.0, 7.6, pz), roof_silver)
		_add_box(jx, Vector3(266.0, 0.18, 7.6), Vector3(0.0, 7.34, pz), ceiling_wood, 0.0, 0.0, 0.0, false)
		_add_box(jx, Vector3(264.0, 0.10, 1.1), Vector3(0.0, 7.22, pz), warm_glow, 0.0, 0.0, 0.0, false)
		for pi in range(-5, 6):
			var px := float(pi) * 24.0
			_add_cyl(jx, 0.24, 0.28, 6.2, Vector3(px, 4.3, pz), steel_white, 10)

	# Overhead glass-and-wood passenger footbridge connecting all 3 platforms & main station hall
	_add_box(jx, Vector3(22.0, 4.4, 72.0), Vector3(0.0, 10.6, -12.0), roof_silver)
	_add_box(jx, Vector3(22.4, 3.0, 68.0), Vector3(0.0, 10.6, -12.0), glass_clear)

	# --- B. Parked Classic CR200J "复兴号绿巨人" Conventional Passenger Train at Platform 2 ---
	_add_cr200j_train(jx, Vector3(-12.0, 0.44, -9.2))

	# --- C. Modern MAD "Train Station in the Forest" floating cantilevered roof (NW plaza side, z = -46) ---
	_add_box(jx, Vector3(128.0, 0.06, 46.0), Vector3(0.0, -0.01, -48.0), granite, 0.0, 0.0, 0.0, false)
	_add_box(jx, Vector3(128.0, 0.58, 40.0), Vector3(0.0, 9.8, -46.0), solar_dark)
	_add_box(jx, Vector3(126.0, 0.34, 38.0), Vector3(0.0, 9.35, -46.0), ceiling_wood)
	_add_box(jx, Vector3(96.0, 7.6, 25.0), Vector3(0.0, 4.0, -46.0), glass_clear)
	_add_box(jx, Vector3(90.0, 6.2, 21.0), Vector3(0.0, 3.4, -46.0), warm_glow, 0.0, 0.0, 0.0, false)
	for ci in range(-6, 7):
		var cx := float(ci) * 9.8
		_add_cyl(jx, 0.28, 0.32, 9.4, Vector3(cx, 4.7, -63.0), steel_white, 10)
		_add_cyl(jx, 0.28, 0.32, 9.4, Vector3(cx, 4.7, -29.0), steel_white, 10)
	_add_sign_label(jx, "嘉 兴 站", Vector3(0.0, 11.4, -66.2), PI, 106, 0.034, Color(0.92, 0.16, 0.16))
	_add_sign_label(jx, "嘉 兴 站", Vector3(0.0, 11.4, -25.8), 0.0, 100, 0.032, Color(0.92, 0.16, 0.16))

	# --- D. 1909 Historic Brick Old Jiaxing Station (嘉兴老火车站) reconstructed in north heritage plaza ---
	var old_st := Node3D.new()
	old_st.position = Vector3(-48.0, 0.0, -86.0)
	jx.add_child(old_st)
	_add_box(old_st, Vector3(36.0, 10.2, 14.0), Vector3(0.0, 5.1, 0.0), brick_red)
	_add_box(old_st, Vector3(36.4, 1.4, 14.4), Vector3(0.0, 0.7, 0.0), brick_grey)
	_add_box(old_st, Vector3(36.4, 0.55, 14.4), Vector3(0.0, 5.4, 0.0), steel_white)
	_add_box(old_st, Vector3(12.0, 12.6, 15.2), Vector3(0.0, 6.3, 0.0), brick_red)
	# Pitched grey tile roof
	_add_box(old_st, Vector3(38.0, 0.6, 9.2), Vector3(0.0, 11.4, -3.5), tile_grey, 0.0, 0.0, 0.42)
	_add_box(old_st, Vector3(38.0, 0.6, 9.2), Vector3(0.0, 11.4, 3.5), tile_grey, 0.0, 0.0, -0.42)
	_add_sign_label(old_st, "嘉 兴 老 站", Vector3(0.0, 13.4, -7.8), PI, 56, 0.022, Color(0.96, 0.88, 0.62))

	var pl := OmniLight3D.new()
	pl.position = Vector3(0.0, 9.0, -56.0)
	pl.light_color = Color(1.0, 0.88, 0.68)
	pl.omni_range = 55.0
	pl.light_energy = 0.0
	pl.visible = false
	jx.add_child(pl)
	lights.append(pl)


static func _add_cr200j_train(parent: Node3D, pos: Vector3) -> void:
	var tr := Node3D.new()
	tr.position = pos
	parent.add_child(tr)

	var body_green := _mat(Color(0.11, 0.44, 0.25), 0.28, 0.16)
	var stripe_gold := _mat(Color(0.92, 0.76, 0.16), 0.30, 0.18)
	var roof_white := _mat(Color(0.86, 0.88, 0.90), 0.34, 0.15)
	var window_dark := _mat(Color(0.08, 0.11, 0.15), 0.10, 0.52)
	var bogie_dark := _mat(Color(0.18, 0.19, 0.21), 0.74, 0.25)
	var head_glow := _emissive(Color(1.0, 0.95, 0.80), 2.0)

	# 7-car CR200J "复兴号绿巨人" (~175m long)
	var car_len := 24.0
	for ci in range(7):
		var cx := (float(ci) - 3.0) * (car_len + 0.45)
		var is_end := (ci == 0 or ci == 6)
		var body_l := car_len - (3.0 if is_end else 0.0)
		var body_x := cx + (-1.5 if ci == 6 else (1.5 if ci == 0 else 0.0))
		_add_box(tr, Vector3(body_l, 3.2, 3.1), Vector3(body_x, 2.02, 0.0), body_green)
		_add_box(tr, Vector3(body_l - 0.4, 0.32, 2.85), Vector3(body_x, 3.68, 0.0), roof_white, 0.0, 0.0, 0.0, false)
		_add_box(tr, Vector3(body_l + 0.05, 0.82, 3.14), Vector3(body_x, 2.38, 0.0), window_dark, 0.0, 0.0, 0.0, false)
		_add_box(tr, Vector3(body_l + 0.08, 0.24, 3.16), Vector3(body_x, 1.56, 0.0), stripe_gold, 0.0, 0.0, 0.0, false)
		_add_box(tr, Vector3(body_l - 1.2, 0.45, 2.6), Vector3(body_x, 0.34, 0.0), bogie_dark, 0.0, 0.0, 0.0, false)
		if is_end:
			var sgn := -1.0 if ci == 0 else 1.0
			var nx := cx + sgn * (car_len * 0.5 - 1.5)
			_add_box(tr, Vector3(3.4, 2.4, 2.95), Vector3(nx + sgn * 1.1, 1.72, 0.0), body_green, 0.0, -sgn * 0.22)
			_add_box(tr, Vector3(1.8, 0.8, 2.7), Vector3(nx + sgn * 0.9, 2.35, 0.0), window_dark, 0.0, -sgn * 0.30)
			_add_box(tr, Vector3(0.24, 0.22, 1.7), Vector3(nx + sgn * 2.8, 1.08, 0.0), head_glow, 0.0, 0.0, 0.0, false)


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


# =============================================================================================
# 6. Grade-Separated Railway Crossings (下穿铁路隧道/框构桥 & 跨铁路立交桥)
# =============================================================================================
static func _build_rail_crossing(parent: Node3D, rc: Dictionary) -> void:
	var pos := _p(rc["pos"])
	var kind := str(rc.get("kind", "tunnel"))
	var road_ang := float(rc.get("road_angle", 0.0))
	var road_w := clampf(float(rc.get("road_w", 14.0)), 10.0, 32.0)
	var hw := road_w * 0.5

	var node := Node3D.new()
	node.name = "RailCrossing_%s" % str(rc.get("name", kind))
	node.position = pos
	node.rotation.y = road_ang
	parent.add_child(node)

	var conc := _mat(Color(0.74, 0.74, 0.72), 0.80, 0.02)
	var conc_dark := _mat(Color(0.56, 0.57, 0.58), 0.84, 0.02)
	var steel := _mat(Color(0.84, 0.86, 0.88), 0.36, 0.45)
	var warn_yellow := _mat(Color(0.95, 0.76, 0.12), 0.48, 0.05)
	var warn_black := _mat(Color(0.14, 0.14, 0.15), 0.65, 0.05)
	var tunnel_led := _emissive(Color(1.0, 0.94, 0.80), 1.4)

	if kind == "tunnel":
		# Underpass box-culvert tunnel beneath elevated 沪昆线 railway girder bridge (5.1m full road/tram headroom!)
		var tun_len := 26.0
		var ceiling_y := 5.10
		# Concrete box-culvert ceiling slab carrying the railway tracks cleanly overhead
		_add_box(node, Vector3(tun_len, 0.75, road_w + 3.2), Vector3(0.0, ceiling_y + 0.38, 0.0), conc)
		# Heavy side abutment walls flanking the roadway (completely clear of road & tram envelope!)
		for side: float in [-1.0, 1.0]:
			var wz := side * (hw + 1.35)
			_add_box(node, Vector3(tun_len + 2.0, ceiling_y + 0.5, 1.4), Vector3(0.0, (ceiling_y + 0.5) * 0.5, wz), conc)
			# Sloped approach retaining wing walls on both tunnel entrances
			for end_s: float in [-1.0, 1.0]:
				_add_box(node, Vector3(18.0, 2.2, 0.85), Vector3(end_s * (tun_len * 0.5 + 9.5), 1.1, wz), conc_dark, 0.0, -end_s * 0.11)
				_add_box(node, Vector3(18.0, 0.9, 0.26), Vector3(end_s * (tun_len * 0.5 + 9.5), 2.55, wz), steel, 0.0, -end_s * 0.11)
		# Both tunnel portal fascia beams + yellow/black clearance warning stripes (限高 4.5m)
		for end_s: float in [-1.0, 1.0]:
			var px := end_s * (tun_len * 0.5 + 0.35)
			_add_box(node, Vector3(0.65, 1.35, road_w + 4.0), Vector3(px, ceiling_y + 0.65, 0.0), conc)
			var n_stripes := maxi(6, int(road_w / 1.8))
			var sw := road_w / float(n_stripes)
			for si in range(n_stripes):
				var sz := -hw + (float(si) + 0.5) * sw
				_add_box(node, Vector3(0.18, 0.34, sw * 0.96), Vector3(px + end_s * 0.35, ceiling_y - 0.12, sz), warn_yellow if (si % 2 == 0) else warn_black, 0.0, 0.0, 0.0, false)
		# Warm recessed LED strip lights along tunnel ceiling
		for side: float in [-0.45, 0.45]:
			_add_box(node, Vector3(tun_len - 2.0, 0.10, 0.42), Vector3(0.0, ceiling_y - 0.05, side * hw), tunnel_led, 0.0, 0.0, 0.0, false)
	else:
		# Road overpass bridge across 沪昆线 (中环南路 / 南湖大桥 / 中环东路)
		var br_len := 58.0
		# Concrete side parapets, steel guardrails, and modern municipal arch side-ribs flanking the road
		for side: float in [-1.0, 1.0]:
			var pz := side * (hw + 0.75)
			_add_box(node, Vector3(br_len, 1.05, 0.55), Vector3(0.0, 0.55, pz), conc)
			_add_box(node, Vector3(br_len, 0.14, 0.18), Vector3(0.0, 1.28, pz), steel, 0.0, 0.0, 0.0, false)
			# Decorative low municipal steel arch rib rising above bridge parapet
			for k in range(10):
				var u0 := -0.5 + float(k) / 10.0
				var u1 := -0.5 + float(k + 1) / 10.0
				var um := (u0 + u1) * 0.5
				var h0 := 1.1 + cos(u0 * PI) * 3.8
				var h1 := 1.1 + cos(u1 * PI) * 3.8
				var dx := (u1 - u0) * (br_len - 8.0)
				var dy := h1 - h0
				var sl := sqrt(dx * dx + dy * dy) + 0.15
				_add_box(node, Vector3(sl, 0.42, 0.38), Vector3(um * (br_len - 8.0), (h0 + h1) * 0.5, pz), steel, 0.0, atan2(dy, dx))
			# Bridge entrance concrete abutment pylons
			for end_s: float in [-1.0, 1.0]:
				_add_box(node, Vector3(2.2, 2.2, 1.25), Vector3(end_s * (br_len * 0.5), 1.1, pz), conc_dark)


# =============================================================================================
# 7. Heavy Railways: 沪昆普速铁路 (Conventional Rail) & 沪昆高速铁路 (Extended HSR Viaducts)
#    Batched into 5 ArrayMeshes for crisp 3D tracks, viaducts, piers, sleepers & catenary!
# =============================================================================================
static func _conv_crossing_lift_and_skip(pt: Vector2, rail_crossings: Array) -> Vector2:
	# Returns Vector2(lift_y, skip_flag > 0.5 if under road overpass bridge deck)
	var lift_y := 0.0
	var skip := 0.0
	for rc: Dictionary in rail_crossings:
		var rp: Array = rc["pos"]
		var c := Vector2(float(rp[0]), float(rp[1]))
		var d := pt.distance_to(c)
		if d > 82.0:
			continue
		var rw := float(rc.get("road_w", 14.0))
		if str(rc.get("kind", "tunnel")) == "tunnel":
			# Smoothly lift 沪昆线 onto a 5.5m railway bridge deck over the underpass tunnel road!
			var inner := rw * 0.5 + 7.0
			var outer := inner + 58.0
			if d <= inner:
				lift_y = maxf(lift_y, 5.55)
			elif d < outer:
				var u := 1.0 - (d - inner) / (outer - inner)
				var s_u := u * u * (3.0 - 2.0 * u)
				lift_y = maxf(lift_y, 5.55 * s_u)
		else:
			# Under a road overpass bridge (中环南路 / 南湖大桥 / 中环东路): never draw ballast on top of bridge deck!
			if d < rw * 0.5 + 3.5:
				skip = 1.0
	return Vector2(lift_y, skip)


static func _build_railways(parent: Node3D, railways: Array, south_sta_pos: Vector3, rail_crossings: Array = []) -> void:
	var rail_root := Node3D.new()
	rail_root.name = "JiaxingHeavyRailways"
	parent.add_child(rail_root)

	var st_viaduct := SurfaceTool.new()
	st_viaduct.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_ballast := SurfaceTool.new()
	st_ballast.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_sleeper := SurfaceTool.new()
	st_sleeper.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_steel := SurfaceTool.new()
	st_steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_cat := SurfaceTool.new()
	st_cat.begin(Mesh.PRIMITIVE_TRIANGLES)

	var has_viaduct := false
	var has_ballast := false
	var has_sleeper := false
	var has_steel := false
	var has_cat := false
	var pier_cells := {}
	var mast_cells := {}
	var sta_xz := Vector2(south_sta_pos.x, south_sta_pos.z)

	for rw: Dictionary in railways:
		var raw_pts: Array = rw.get("pts", [])
		if raw_pts.size() < 2:
			continue
		var is_hsr := str(rw.get("kind", "")) == "hsr"
		var is_elev := bool(rw.get("elevated", false))
		var base_y := float(rw.get("y", 2.8 if is_hsr else 0.0))

		var pts: Array[Vector2] = []
		for rp in raw_pts:
			var v := Vector2(float(rp[0]), float(rp[1]))
			if not pts.is_empty() and not is_hsr and not rail_crossings.is_empty():
				# Densify conventional railway segments into <=10m steps so bridge/tunnel ramps grade smoothly!
				var prev := pts[pts.size() - 1]
				var dl := prev.distance_to(v)
				if dl > 10.0:
					var sub_n := int(ceil(dl / 10.0))
					for sk in range(1, sub_n):
						pts.append(prev.lerp(v, float(sk) / float(sub_n)))
			pts.append(v)

		var sleeper_acc := 0.0
		var pier_acc := 16.0
		var mast_acc := 24.0

		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var seg := b - a
			var slen := seg.length()
			if slen < 0.25:
				continue
			var dir := seg / slen
			var nrm := Vector2(-dir.y, dir.x)
			var mid := (a + b) * 0.5

			if is_hsr:
				var in_sta_box := mid.distance_to(sta_xz) < 224.0
				# Elevated HSR concrete box-girder viaduct + acoustic parapets outside the station deck
				if not in_sta_box:
					_st_box_along(st_viaduct, a, b, 6.2, 1.45, 2.75)
					# Outer acoustic noise-barrier parapets on both sides of viaduct deck
					_st_box_along(st_viaduct, a + nrm * 2.9, b + nrm * 2.9, 0.36, 2.75, 3.85)
					_st_box_along(st_viaduct, a - nrm * 2.9, b - nrm * 2.9, 0.36, 2.75, 3.85)
					has_viaduct = true
				# CRTS ballastless concrete slab + twin gleaming steel rails (seamlessly meets station deck at y=2.98!)
				if mid.distance_to(sta_xz) > 200.0:
					_st_box_along(st_sleeper, a, b, 2.55, 2.75, 2.88)
					has_sleeper = true
					for rside: float in [-0.72, 0.72]:
						_st_box_along(st_steel, a + nrm * rside, b + nrm * rside, 0.15, 2.88, 3.04)
					has_steel = true
					# Overhead HSR contact wire (y = 8.15m)
					_st_box_along(st_cat, a, b, 0.08, 8.12, 8.20)
					has_cat = true

				# Viaduct piers every 34m & catenary masts every 52m (deduplicated across twin parallel HSR tracks)
				var s := 0.0
				while s < slen:
					var p := a + dir * s
					var d_sta := p.distance_to(sta_xz)
					if d_sta > 228.0:
						if pier_acc >= 34.0:
							pier_acc = 0.0
							var pck := Vector2i(int(floor(p.x / 14.0)), int(floor(p.y / 14.0)))
							if not pier_cells.has(pck):
								pier_cells[pck] = true
								_st_axis_box(st_viaduct, p, dir, 2.2, 4.4, 0.0, 1.55)
								has_viaduct = true
						if mast_acc >= 52.0:
							mast_acc = 0.0
							var mck := Vector2i(int(floor(p.x / 18.0)), int(floor(p.y / 18.0)))
							if not mast_cells.has(mck):
								mast_cells[mck] = true
								var mp := p + nrm * 2.75
								_st_axis_box(st_cat, mp, dir, 0.28, 0.28, 2.75, 8.9)
								_st_axis_box(st_cat, p + nrm * 1.15, dir, 0.16, 3.3, 8.15, 8.32)
								has_cat = true
					var step := minf(6.0, slen - s)
					if step < 0.05:
						break
					s += step
					pier_acc += step
					mast_acc += step
			else:
				# Conventional Railway (沪昆线 & 嘉兴火车站 tracks): grade-separated over underpass tunnels & cleanly under road bridges!
				var xa := _conv_crossing_lift_and_skip(a, rail_crossings)
				var xb := _conv_crossing_lift_and_skip(b, rail_crossings)
				var xm := _conv_crossing_lift_and_skip(mid, rail_crossings)
				if xm.y > 0.5:
					continue # railway passes underneath the road overpass bridge deck
				var ya := base_y + xa.x
				var yb := base_y + xb.x
				var ym := (ya + yb) * 0.5
				var deck_ya := ya + 0.30
				var deck_yb := yb + 0.30
				var deck_ym := ym + 0.30
				var over_tun := ym > 0.35
				if is_elev or over_tun:
					var girder_bot_a := maxf(0.0, ya - 0.55) if ya > 3.2 else 0.0
					var girder_bot_b := maxf(0.0, yb - 0.55) if yb > 3.2 else 0.0
					_st_box_sloped(st_viaduct, a, b, 5.2, girder_bot_a, ya + 0.28, girder_bot_b, yb + 0.28)
					_st_box_sloped(st_viaduct, a + nrm * 2.45, b + nrm * 2.45, 0.30, ya + 0.28, ya + 1.15, yb + 0.28, yb + 1.15)
					_st_box_sloped(st_viaduct, a - nrm * 2.45, b - nrm * 2.45, 0.30, ya + 0.28, ya + 1.15, yb + 0.28, yb + 1.15)
					has_viaduct = true
				_st_box_sloped(st_ballast, a, b, 4.4, maxf(0.04, ya), deck_ya, maxf(0.04, yb), deck_yb)
				has_ballast = true
				for rside: float in [-0.72, 0.72]:
					_st_box_sloped(st_steel, a + nrm * rside, b + nrm * rside, 0.15, deck_ya + 0.06, deck_ya + 0.20, deck_yb + 0.06, deck_yb + 0.20)
				has_steel = true
				_st_box_sloped(st_cat, a, b, 0.07, deck_ya + 5.55, deck_ya + 5.62, deck_yb + 5.55, deck_yb + 5.62)
				has_cat = true

				# Sleepers every 2.2m & electrification masts every 56m
				var s2 := 0.0
				while s2 < slen:
					var u2 := s2 / slen
					var p2 := a.lerp(b, u2)
					var dy2 := lerpf(deck_ya, deck_yb, u2)
					var by2 := lerpf(ya, yb, u2)
					if sleeper_acc >= 2.2:
						sleeper_acc = 0.0
						_st_axis_box(st_sleeper, p2, dir, 0.26, 2.45, dy2 - 0.02, dy2 + 0.08)
						has_sleeper = true
					if mast_acc >= 56.0:
						mast_acc = 0.0
						var mck2 := Vector2i(int(floor(p2.x / 18.0)), int(floor(p2.y / 18.0)))
						if not mast_cells.has(mck2):
							mast_cells[mck2] = true
							var mp2 := p2 + nrm * 2.35
							_st_axis_box(st_cat, mp2, dir, 0.26, 0.26, maxf(0.0, by2), dy2 + 6.3)
							_st_axis_box(st_cat, p2 + nrm * 1.0, dir, 0.14, 2.8, dy2 + 5.58, dy2 + 5.74)
							has_cat = true
					var step2 := minf(2.2, slen - s2)
					if step2 < 0.05:
						break
					s2 += step2
					sleeper_acc += step2
					mast_acc += step2

	if has_viaduct:
		_emit_st(rail_root, "RailViaductConcrete", st_viaduct, _mat(Color(0.74, 0.74, 0.72), 0.80, 0.02), true)
	if has_ballast:
		_emit_st(rail_root, "RailBallast", st_ballast, _mat(Color(0.45, 0.43, 0.40), 0.94, 0.0), false)
	if has_sleeper:
		_emit_st(rail_root, "RailSleepers", st_sleeper, _mat(Color(0.68, 0.67, 0.64), 0.86, 0.0), false)
	if has_steel:
		_emit_st(rail_root, "RailSteel", st_steel, _mat(Color(0.50, 0.53, 0.57), 0.28, 0.80), false)
	if has_cat:
		_emit_st(rail_root, "RailCatenary", st_cat, _mat(Color(0.38, 0.41, 0.45), 0.42, 0.65), false)


static func _emit_st(parent: Node3D, nm: String, st: SurfaceTool, mat: StandardMaterial3D, shadows: bool) -> void:
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(d)


static func _st_box_along(st: SurfaceTool, a: Vector2, b: Vector2, width: float, y0: float, y1: float) -> void:
	_st_box_sloped(st, a, b, width, y0, y1, y0, y1)


static func _st_box_sloped(st: SurfaceTool, a: Vector2, b: Vector2, width: float, ya0: float, ya1: float, yb0: float, yb1: float) -> void:
	var seg := b - a
	var slen := seg.length()
	if slen < 0.05:
		return
	var dir := seg / slen
	var nrm := Vector2(-dir.y, dir.x) * (width * 0.5)
	var al := a - nrm
	var ar := a + nrm
	var bl := b - nrm
	var br := b + nrm
	var p0 := Vector3(al.x, ya1, al.y)
	var p1 := Vector3(ar.x, ya1, ar.y)
	var p2 := Vector3(br.x, yb1, br.y)
	var p3 := Vector3(bl.x, yb1, bl.y)
	var q0 := Vector3(al.x, ya0, al.y)
	var q1 := Vector3(ar.x, ya0, ar.y)
	var q2 := Vector3(br.x, yb0, br.y)
	var q3 := Vector3(bl.x, yb0, bl.y)
	_st_quad(st, p0, p3, p2, p1, Vector3.UP)
	var nl := Vector3(-nrm.x, 0.0, -nrm.y).normalized()
	var nr := -nl
	var df := Vector3(dir.x, 0.0, dir.y)
	_st_quad(st, q0, q3, p3, p0, nl)
	_st_quad(st, q1, p1, p2, q2, nr)
	_st_quad(st, q0, p0, p1, q1, -df)
	_st_quad(st, q3, q2, p2, p3, df)


static func _st_axis_box(st: SurfaceTool, center: Vector2, dir: Vector2, length: float, width: float, y0: float, y1: float) -> void:
	var half_d := dir * (length * 0.5)
	_st_box_along(st, center - half_d, center + half_d, width, y0, y1)
