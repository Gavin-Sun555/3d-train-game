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


# Shared textured lawn for hand-built plaza / campus lawns (park lawn shader, no depth push: these are raised
# planting beds, not ground sheets)
static var _lawn_mat_cache: ShaderMaterial = null


static func lawn_material() -> ShaderMaterial:
	if _lawn_mat_cache == null:
		_lawn_mat_cache = ShaderMaterial.new()
		_lawn_mat_cache.shader = load("res://shaders/park_lawn.gdshader") as Shader
		_lawn_mat_cache.set_shader_parameter("depth_push", 0.0)
		_lawn_mat_cache.set_shader_parameter("depth_slope", 0.0)
	return _lawn_mat_cache


# Fountain / reflecting pool: animated water surface (its mesh sits at the basin centre) and, with jets, a ring of
# water jets whose landing points foam and ripple; a smaller inner ring of low bubblers; water_y = surface height
static var _jet_mat_cache: ShaderMaterial = null


static func add_fountain(parent: Node3D, center: Vector3, radius: float, water_y: float, jet_ring: float = -1.0, jets: int = 12, jet_h: float = 3.0) -> void:
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/fountain_water.gdshader") as Shader
	wm.set_shader_parameter("radius", radius)
	wm.set_shader_parameter("jet_ring", jet_ring)
	wm.set_shader_parameter("jet_count", float(jets))
	var surf := MeshInstance3D.new()
	surf.name = "FountainWater"
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.04
	cm.radial_segments = 48
	cm.rings = 1
	surf.mesh = cm
	surf.material_override = wm
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.position = Vector3(center.x, water_y - 0.02, center.z)
	parent.add_child(surf)
	# raised granite rim (coping) round the water
	var rim_st := SurfaceTool.new()
	rim_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_rim := maxi(24, int(TAU * radius / 2.0))
	for k in range(n_rim):
		var a := TAU * (float(k) + 0.5) / float(n_rim)
		var seg_w := TAU * (radius + 0.4) / float(n_rim) + 0.08
		var rc := Vector3(center.x + cos(a) * (radius + 0.4), water_y + 0.12, center.z + sin(a) * (radius + 0.4))
		RoadSignBuilder._box(rim_st, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), rc), Vector3(seg_w, 0.5, 0.8), Color(0.70, 0.70, 0.69))
	var rim := MeshInstance3D.new()
	rim.name = "FountainRim"
	rim.mesh = rim_st.commit()
	var rim_mat := StandardMaterial3D.new()
	rim_mat.vertex_color_use_as_albedo = true
	rim_mat.roughness = 0.6
	rim.material_override = rim_mat
	parent.add_child(rim)
	if jet_ring <= 0.0:
		return
	if _jet_mat_cache == null:
		_jet_mat_cache = ShaderMaterial.new()
		_jet_mat_cache.shader = load("res://shaders/fountain_jet.gdshader") as Shader
	var jm := CylinderMesh.new()
	jm.top_radius = 0.42 # the column fans out into spray toward the top
	jm.bottom_radius = 0.07
	jm.height = 1.0
	jm.radial_segments = 8
	jm.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = jm
	mm.instance_count = jets * 2
	for i in range(jets):
		var a := TAU * (float(i) + 0.5) / float(jets)
		var h := jet_h * (0.85 + 0.3 * float(i % 3) / 2.0)
		var p := Vector3(center.x + cos(a) * jet_ring, water_y + h * 0.5, center.z + sin(a) * jet_ring)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.0, h, 1.0)), p))
		# low bubbler between the outer jets, nearer the rim
		var a2 := TAU * float(i) / float(jets)
		var r2 := minf(radius - 0.8, jet_ring + (radius - jet_ring) * 0.6)
		var hb := 0.6
		mm.set_instance_transform(jets + i, Transform3D(Basis().scaled(Vector3(1.3, hb, 1.3)), Vector3(center.x + cos(a2) * r2, water_y + hb * 0.5, center.z + sin(a2) * r2)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FountainJets"
	mmi.multimesh = mm
	mmi.material_override = _jet_mat_cache
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 400.0
	parent.add_child(mmi)


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
	var granite := _mat(Color(0.80, 0.79, 0.76), 0.68, 0.04)
	var granite_dark := _mat(Color(0.56, 0.57, 0.59), 0.72, 0.05)
	var asphalt_mat := _mat(Color(0.22, 0.23, 0.25), 0.86, 0.02)
	var dark_stone := _mat(Color(0.32, 0.34, 0.38), 0.62, 0.08)
	var glass_curtain := _glass(Color(0.28, 0.44, 0.58), 0.68)
	var warm_hall := _emissive(Color(1.0, 0.90, 0.72), 0.95)
	var sign_red := Color(0.90, 0.14, 0.14)
	var rail_steel := _mat(Color(0.45, 0.47, 0.50), 0.32, 0.75)
	var ballast := _mat(Color(0.46, 0.45, 0.43), 0.92, 0.0)
	var yellow_line := _mat(Color(0.94, 0.78, 0.18), 0.55, 0.0)
	var lawn_mat := lawn_material()
	var water_pool := _mat(Color(0.18, 0.48, 0.62), 0.18, 0.25)
	var trunk_mat := _mat(Color(0.34, 0.25, 0.17), 0.88, 0.0)
	var foliage_mat := _mat(Color(0.20, 0.46, 0.21), 0.82, 0.0)
	var foliage_lt := _mat(Color(0.29, 0.55, 0.25), 0.80, 0.0)
	var exit_green := _emissive(Color(0.18, 0.88, 0.46), 1.35)
	var depart_blue := _emissive(Color(0.20, 0.68, 0.98), 1.45)

	# --- A. Authentic 2-Level HSR Station (二楼进站 2F Departures · 一楼出站 1F Arrivals/Exit) ---
	# 1F Ground Arrival Forecourt Terrace (z = -97..-52, strictly flush & clear of north T1 tramway at z = -109!)
	_add_box(st, Vector3(286.0, 0.05, 45.0), Vector3(0.0, -0.015, -74.5), granite, 0.0, 0.0, 0.0, false)
	_add_box(st, Vector3(44.0, 0.06, 44.0), Vector3(0.0, -0.005, -74.5), granite_dark, 0.0, 0.0, 0.0, false)

	# 1F Ground-Level Arrival Concourse & Exit Hall (y = 0.0m .. 6.0m, 一楼出站层)
	_add_box(st, Vector3(164.0, 5.8, 36.0), Vector3(0.0, 2.9, -33.0), concrete)
	_add_box(st, Vector3(148.0, 4.6, 30.0), Vector3(0.0, 2.5, -36.5), warm_hall, 0.0, 0.0, 0.0, false)
	_add_box(st, Vector3(154.0, 5.4, 0.45), Vector3(0.0, 2.8, -51.4), glass_curtain)
	# Twin 1F Arrival Exit Portals (东/西出站口) with glowing green exit headers & automatic glass doors
	for ex_x: float in [-34.0, 34.0]:
		_add_box(st, Vector3(18.0, 0.55, 4.2), Vector3(ex_x, 4.7, -53.2), dark_stone)
		_add_box(st, Vector3(16.0, 0.22, 0.25), Vector3(ex_x, 4.7, -55.4), exit_green, 0.0, 0.0, 0.0, false)
		_add_sign_label(st, "出站口 · 1F EXIT", Vector3(ex_x, 5.15, -55.5), PI, 48, 0.022, Color(0.55, 1.0, 0.68))

	# 2F Elevated Departure Viaduct Drop-Off Deck (二楼高架落客平台, y = 6.2m, z = -67..-51, x = -94..+94)
	_add_box(st, Vector3(188.0, 0.90, 16.0), Vector3(0.0, 5.85, -59.0), concrete)
	_add_box(st, Vector3(186.0, 0.12, 13.6), Vector3(0.0, 6.35, -59.5), asphalt_mat, 0.0, 0.0, 0.0, false)
	_add_box(st, Vector3(182.0, 0.05, 0.24), Vector3(0.0, 6.43, -59.5), yellow_line, 0.0, 0.0, 0.0, false)
	# 2F Drop-off safety parapet & sidewalk curb
	_add_box(st, Vector3(188.0, 1.05, 0.45), Vector3(0.0, 6.82, -66.8), steel_white)
	_add_box(st, Vector3(160.0, 0.26, 3.2), Vector3(0.0, 6.42, -52.6), granite)
	# Sculpted viaduct piers supporting 2F drop-off deck (clear of 1F arrival exit gateways!)
	for px_v: float in [-86.0, -64.0, -14.0, 14.0, 64.0, 86.0]:
		_add_cyl(st, 0.62, 0.72, 5.6, Vector3(px_v, 2.8, -64.5), concrete, 10)
		_add_cyl(st, 0.62, 0.72, 5.6, Vector3(px_v, 2.8, -54.0), concrete, 10)
	# Twin Sweeping Vehicle Approach & Exit Ramps (东上西下高架落客匝道, y = 0.0m <-> 6.2m, clear of z=-109 tram!)
	for r_side: float in [-1.0, 1.0]:
		var ramp_len := 64.0
		var ramp_cx := r_side * (94.0 + ramp_len * 0.5)
		var ramp_tilt := -r_side * atan2(6.0, ramp_len)
		_add_box(st, Vector3(ramp_len, 0.75, 11.2), Vector3(ramp_cx, 3.05, -59.0), concrete, 0.0, ramp_tilt)
		_add_box(st, Vector3(ramp_len, 0.10, 9.6), Vector3(ramp_cx, 3.48, -59.0), asphalt_mat, 0.0, ramp_tilt, 0.0, false)
		_add_box(st, Vector3(ramp_len, 0.85, 0.32), Vector3(ramp_cx, 3.85, -64.4), steel_white, 0.0, ramp_tilt)
		_add_box(st, Vector3(ramp_len, 0.85, 0.32), Vector3(ramp_cx, 3.85, -53.6), steel_white, 0.0, ramp_tilt)
		# Intermediate ramp piers
		for rp_k in range(1, 3):
			var frac := float(rp_k) / 3.0
			var rpx := r_side * (94.0 + frac * ramp_len)
			var rph := 5.8 * (1.0 - frac)
			_add_cyl(st, 0.52, 0.60, rph, Vector3(rpx, rph * 0.5, -59.0), concrete, 10)

	# Grand Central Pedestrian Stairway & Covered Escalator Bridge (1F北广场 -> 2F进站平台)
	for si in range(10):
		var sh := 0.62 * float(si + 1)
		_add_box(st, Vector3(24.0, 0.62, 1.5), Vector3(0.0, sh - 0.31, -67.5 - float(9 - si) * 1.45), granite)
	# Twin flanked glass-sided escalators rising cleanly beside the central stair flight
	for esc_x: float in [-14.2, 14.2]:
		_add_box(st, Vector3(3.2, 0.55, 16.5), Vector3(esc_x, 3.1, -74.5), dark_stone, 0.0, 0.0, -0.38)
		_add_box(st, Vector3(3.4, 1.05, 16.5), Vector3(esc_x, 3.9, -74.5), glass_curtain, 0.0, 0.0, -0.38)
	_add_sign_label(st, "↑ 2F 进站乘车  DEPARTURES", Vector3(0.0, 7.6, -67.2), PI, 52, 0.024, Color(0.55, 0.88, 1.0))

	# 2F Main Departure Hall Core (y = 6.2m .. 21.5m, 二楼进站候车大厅)
	_add_box(st, Vector3(148.0, 14.2, 29.0), Vector3(0.0, 13.4, -34.0), warm_hall, 0.0, 0.0, 0.0, false)
	# Blue-tinted glass curtain walls enclosing 2F Departure Hall on all four sides
	_add_box(st, Vector3(154.0, 15.2, 0.5), Vector3(0.0, 14.0, -49.5), glass_curtain)
	_add_box(st, Vector3(154.0, 15.2, 0.5), Vector3(0.0, 14.0, -18.5), glass_curtain)
	_add_box(st, Vector3(0.5, 15.2, 31.0), Vector3(-77.0, 14.0, -34.0), glass_curtain)
	_add_box(st, Vector3(0.5, 15.2, 31.0), Vector3(77.0, 14.0, -34.0), glass_curtain)
	# Projecting 2F Main Entrance Security Vestibule + Glowing "进站口 · 2F DEPARTURES" Portal
	_add_box(st, Vector3(44.0, 5.4, 4.4), Vector3(0.0, 9.1, -51.6), glass_curtain)
	_add_box(st, Vector3(46.0, 0.65, 5.2), Vector3(0.0, 12.0, -51.8), dark_stone)
	_add_box(st, Vector3(42.0, 0.25, 0.25), Vector3(0.0, 12.0, -54.5), depart_blue, 0.0, 0.0, 0.0, false)
	_add_sign_label(st, "进站口 · 2F DEPARTURES", Vector3(0.0, 12.85, -54.6), PI, 64, 0.026, Color(0.75, 0.94, 1.0))
	_add_sign_label(st, "售票处 / TICKETS", Vector3(54.0, 10.8, -50.6), PI, 40, 0.022, Color(0.98, 0.92, 0.72))

	# Exterior slender steel colonnade & vertical curtain-wall mullions
	for ci in range(-9, 10):
		var cx := float(ci) * 8.4
		_add_box(st, Vector3(0.65, 16.0, 0.85), Vector3(cx, 14.4, -50.2), steel_white)
		_add_box(st, Vector3(0.55, 15.4, 0.70), Vector3(cx, 14.0, -18.2), steel_white)
	# Horizontal transom beams
	for ty in [10.4, 15.0, 19.6]:
		_add_box(st, Vector3(156.0, 0.42, 0.75), Vector3(0.0, ty, -49.9), steel_white)

	# --- B. Iconic Sweeping Wave-Arch Silver Canopy Roof (18 arched segments spanning 192m, covering 2F deck!) ---
	var n_seg := 18
	var span_x := 192.0
	for k in range(n_seg):
		var u0 := -0.5 + float(k) / float(n_seg)
		var u1 := -0.5 + float(k + 1) / float(n_seg)
		var um := (u0 + u1) * 0.5
		# Graceful double-crest Jiangnan wave silhouette (peaks at center, sweeps gently up at wingtips)
		var y0 := 22.0 + cos(u0 * PI) * 4.8 + pow(absf(u0 * 2.0), 3.0) * 1.8
		var y1 := 22.0 + cos(u1 * PI) * 4.8 + pow(absf(u1 * 2.0), 3.0) * 1.8
		var ym := (y0 + y1) * 0.5
		var dx := (u1 - u0) * span_x
		var dy := y1 - y0
		var seg_w := sqrt(dx * dx + dy * dy) + 0.35
		var tilt := atan2(dy, dx)
		# Deep cantilevered roof deck covering 2F Departure Hall + 2F Drop-off Viaduct!
		_add_box(st, Vector3(seg_w, 1.05, 58.0), Vector3(um * span_x, ym, -39.0), roof_silver, 0.0, tilt)
		_add_box(st, Vector3(0.65, 0.75, 56.0), Vector3(u0 * span_x, y0 - 0.65, -39.0), roof_rib)

	# Skylight clerestory band along roof spine
	_add_box(st, Vector3(114.0, 1.2, 7.5), Vector3(0.0, 27.2, -35.0), glass_curtain)

	# --- C. Iconic Red Roof Signage: "嘉兴南站" (North & South facing!) ---
	_add_box(st, Vector3(44.0, 0.45, 0.55), Vector3(0.0, 27.4, -67.8), steel_white)
	_add_sign_label(st, "嘉 兴 南 站", Vector3(0.0, 30.0, -67.9), PI, 134, 0.042, sign_red)
	_add_sign_label(st, "JIAXING SOUTH RAILWAY STATION", Vector3(0.0, 27.7, -67.9), PI, 40, 0.028, Color(0.95, 0.96, 0.98))
	_add_sign_label(st, "嘉 兴 南 站", Vector3(0.0, 30.0, -10.0), 0.0, 120, 0.038, sign_red)

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

	# --- F. Station Front Welcome Forecourt, Grand North Civic Plaza & Bus Transit Hub (站前广场 + 公交枢纽站) ---
	# F1. South Forecourt Lawn Islands, Trees & Covered T1 Transfer Walkway (z = -96..-70, clear of z=-109 T1 tracks!)
	for side_f: float in [-1.0, 1.0]:
		var fx_l := side_f * 58.0
		_add_box(st, Vector3(54.0, 0.42, 16.0), Vector3(fx_l, 0.21, -83.0), granite_dark)
		_add_box(st, Vector3(51.5, 0.48, 13.8), Vector3(fx_l, 0.26, -83.0), lawn_mat)
		for ti_f in range(4):
			var tx_f := fx_l - 18.0 + float(ti_f) * 12.0
			ParkLandscapeBuilder.plant_tree(st, Vector3(tx_f, 0.5, -83.0), 1, 0.9, ParkLandscapeBuilder.CAMPHOR if (ti_f % 2 == 0) else ParkLandscapeBuilder.CAMPHOR_LT)
	# Sheltered pedestrian transfer walkway leading directly to T1 Tram Terminal (嘉兴南站)
	_add_box(st, Vector3(48.0, 0.32, 8.5), Vector3(0.0, 4.8, -92.5), roof_silver)
	for tx in [-20.0, -7.0, 7.0, 20.0]:
		_add_box(st, Vector3(0.38, 4.7, 0.38), Vector3(tx, 2.35, -92.5), steel_white)
	_add_sign_label(st, "有轨电车 T1 线 · 嘉兴南站换乘通道", Vector3(0.0, 5.45, -96.8), PI, 44, 0.022, Color(0.98, 0.86, 0.34))

	# F2. Grand North Civic Square (嘉兴南站北广场, z = -242..-126, strictly NORTH of T1 tramway at z=-109!)
	var plaza_n := Node3D.new()
	plaza_n.name = "JiaxingSouthNorthPlaza"
	st.add_child(plaza_n)
	_add_box(plaza_n, Vector3(316.0, 0.05, 114.0), Vector3(46.0, -0.015, -184.0), granite, 0.0, 0.0, 0.0, false)
	# Architectural dark-granite geometric paving bands across the civic square
	for gz_band: float in [-234.0, -206.0, -172.0, -138.0]:
		_add_box(plaza_n, Vector3(308.0, 0.06, 2.6), Vector3(46.0, -0.005, gz_band), granite_dark, 0.0, 0.0, 0.0, false)
	# Central Civic Welcome Sculpture & Circular Reflection Fountain ("红船起航 · 嘉兴欢迎您", local x=-12, z=-172)
	_add_cyl(plaza_n, 16.5, 17.2, 0.55, Vector3(-12.0, 0.27, -172.0), granite_dark, 24)
	add_fountain(plaza_n, Vector3(-12.0, 0.0, -172.0), 15.2, 0.58, 10.8, 16, 3.4)
	_add_box(plaza_n, Vector3(14.0, 1.4, 4.2), Vector3(-12.0, 0.9, -172.0), granite)
	var red_sail := _mat(Color(0.84, 0.12, 0.14), 0.32, 0.25)
	_add_box(plaza_n, Vector3(11.5, 6.2, 0.55), Vector3(-12.0, 4.6, -172.0), red_sail, 0.0, 0.14)
	_add_box(plaza_n, Vector3(7.5, 4.6, 0.50), Vector3(-11.0, 3.9, -170.6), _mat(Color(0.95, 0.78, 0.24), 0.28, 0.45), 0.0, -0.18)
	_add_sign_label(plaza_n, "嘉 兴 欢 迎 您 · 红 船 起 航", Vector3(-12.0, 8.6, -172.4), PI, 48, 0.024, Color(0.94, 0.22, 0.18))
	# Landscaped green plaza lawns & lush Jiangnan shade trees framing the civic square
	for lx_p: float in [-42.0, 18.0]:
		_add_box(plaza_n, Vector3(22.8, 0.42, 34.8), Vector3(lx_p, 0.21, -172.0), granite_dark)
		_add_box(plaza_n, Vector3(22.0, 0.35, 34.0), Vector3(lx_p, 0.26, -172.0), lawn_mat)
		for ti_p in range(3):
			var tz_p := -184.0 + float(ti_p) * 12.0
			ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(lx_p, 0.35, tz_p), 1, 0.95, ParkLandscapeBuilder.CAMPHOR if (ti_p % 2 == 0) else ParkLandscapeBuilder.CAMPHOR_LT)
	# Perimeter avenue tree row along south edge of North Plaza (z = -132, facing T1 tramway!)
	for tx_row in range(-95, 195, 22):
		if absf(float(tx_row) + 12.0) < 18.0:
			continue
		ParkLandscapeBuilder.plant_tree(plaza_n, Vector3(float(tx_row), 0.0, -132.0), 1, 0.9, ParkLandscapeBuilder.CAMPHOR_LT if (tx_row % 44 == 0) else ParkLandscapeBuilder.CAMPHOR)

	# F3. Jiaxing South Station Bus Transit Hub (嘉兴南站公交枢纽站 — East Plaza, x = +52..+200, z = -234..-136)
	var bus_hub := Node3D.new()
	bus_hub.name = "JiaxingSouthBusHub"
	st.add_child(bus_hub)
	# Asphalt bus terminal staging yard & lane markings
	_add_box(bus_hub, Vector3(144.0, 0.06, 94.0), Vector3(126.0, 0.015, -184.0), asphalt_mat, 0.0, 0.0, 0.0, false)
	for by_l: float in [-206.0, -193.0, -180.0, -167.0, -154.0, -141.0]:
		_add_box(bus_hub, Vector3(132.0, 0.04, 0.25), Vector3(126.0, 0.055, by_l), yellow_line, 0.0, 0.0, 0.0, false)
	# 2-Story Bus Hub Dispatch & Passenger Waiting Pavilion (公交枢纽综合服务楼, z = -224)
	_add_box(bus_hub, Vector3(64.0, 8.6, 13.5), Vector3(126.0, 4.3, -224.0), steel_white)
	_add_box(bus_hub, Vector3(58.0, 6.2, 10.0), Vector3(126.0, 3.9, -224.0), warm_hall, 0.0, 0.0, 0.0, false)
	_add_box(bus_hub, Vector3(60.0, 6.8, 13.9), Vector3(126.0, 4.2, -224.0), glass_curtain)
	_add_box(bus_hub, Vector3(70.0, 0.65, 18.0), Vector3(126.0, 8.9, -223.5), roof_silver)
	_add_sign_label(bus_hub, "嘉兴南站公交枢纽站", Vector3(126.0, 10.6, -214.4), 0.0, 74, 0.028, Color(0.18, 0.72, 0.98))
	_add_sign_label(bus_hub, "JIAXING SOUTH BUS TRANSIT HUB", Vector3(126.0, 9.5, -214.4), 0.0, 30, 0.020, Color(0.95, 0.96, 0.98))
	_add_sign_label(bus_hub, "嘉兴南站公交枢纽站", Vector3(126.0, 10.6, -232.6), PI, 74, 0.028, Color(0.18, 0.72, 0.98))

	# 5 Parallel Covered Bus Boarding Islands with cantilevered steel-glass canopies & route sign totems!
	var bay_labels: Array[String] = ["1号站台 · K93 / K95", "2号站台 · K96 / K98", "3号站台 · 游1 / 快1", "4号站台 · 城乡公交", "5号站台 · 客运快线"]
	var bay_zs: Array[float] = [-200.0, -187.0, -174.0, -161.0, -148.0]
	for bi in range(bay_zs.size()):
		var bz: float = bay_zs[bi]
		_add_box(bus_hub, Vector3(76.0, 0.28, 3.4), Vector3(126.0, 0.16, bz), granite)
		_add_box(bus_hub, Vector3(74.0, 0.05, 0.22), Vector3(126.0, 0.31, bz + 1.45), yellow_line, 0.0, 0.0, 0.0, false)
		_add_box(bus_hub, Vector3(74.0, 0.26, 4.6), Vector3(126.0, 4.15, bz), roof_silver)
		_add_box(bus_hub, Vector3(72.0, 0.10, 1.2), Vector3(126.0, 3.98, bz), warm_hall, 0.0, 0.0, 0.0, false)
		for bcol in range(-3, 4):
			_add_cyl(bus_hub, 0.16, 0.20, 3.9, Vector3(126.0 + float(bcol) * 11.0, 2.15, bz), steel_white, 8)
		_add_box(bus_hub, Vector3(0.35, 2.6, 1.3), Vector3(88.5, 1.55, bz), dark_stone)
		_add_sign_label(bus_hub, bay_labels[bi], Vector3(88.2, 2.95, bz), -PI * 0.5, 34, 0.018, Color(0.45, 0.92, 1.0))

	# 6 Parked Modern Chinese Electric City Buses (嘉兴新能源纯电动公交车) docked cleanly at the boarding bays!
	_add_electric_city_bus(bus_hub, Vector3(106.0, 0.04, -195.8), Color(0.14, 0.56, 0.88), 0.0)
	_add_electric_city_bus(bus_hub, Vector3(144.0, 0.04, -195.8), Color(0.16, 0.64, 0.42), 0.0)
	_add_electric_city_bus(bus_hub, Vector3(114.0, 0.04, -182.8), Color(0.16, 0.64, 0.42), 0.0)
	_add_electric_city_bus(bus_hub, Vector3(148.0, 0.04, -169.8), Color(0.14, 0.56, 0.88), 0.0)
	_add_electric_city_bus(bus_hub, Vector3(108.0, 0.04, -156.8), Color(0.84, 0.18, 0.18), 0.0)
	_add_electric_city_bus(bus_hub, Vector3(142.0, 0.04, -143.8), Color(0.14, 0.56, 0.88), 0.0)

	# F4. West Plaza Taxi & Ride-Hailing Waiting Canopy (出租车 / 网约车候客区, x = -104..-56, z = -216..-146)
	_add_box(plaza_n, Vector3(48.0, 0.06, 68.0), Vector3(-82.0, 0.01, -182.0), asphalt_mat, 0.0, 0.0, 0.0, false)
	_add_box(plaza_n, Vector3(10.0, 0.34, 56.0), Vector3(-62.0, 4.4, -182.0), roof_silver)
	for tcz in range(-206, -154, 12):
		_add_cyl(plaza_n, 0.18, 0.22, 4.3, Vector3(-62.0, 2.15, float(tcz)), steel_white, 8)
	_add_sign_label(plaza_n, "出租车 · 网约车上客区  TAXI", Vector3(-56.8, 5.0, -182.0), PI * 0.5, 40, 0.022, Color(1.0, 0.84, 0.26))

	# Warm plaza architectural night spotlights (HSR station + North Plaza + Bus Hub)
	for lx in [-56.0, 0.0, 56.0, 126.0]:
		var pl := OmniLight3D.new()
		pl.position = Vector3(lx, 12.0, -172.0 if lx > 80.0 else -66.0)
		pl.light_color = Color(1.0, 0.88, 0.68)
		pl.omni_range = 68.0
		pl.light_energy = 0.0
		pl.visible = false
		st.add_child(pl)
		lights.append(pl)


static func _add_electric_city_bus(parent: Node3D, pos: Vector3, accent_col: Color, yaw: float) -> void:
	var b := Node3D.new()
	b.position = pos
	b.rotation.y = yaw
	parent.add_child(b)
	var body_white := _mat(Color(0.94, 0.95, 0.96), 0.28, 0.12)
	var accent := _mat(accent_col, 0.30, 0.16)
	var glass_dark := _mat(Color(0.08, 0.12, 0.17), 0.10, 0.55)
	var wheel_dark := _mat(Color(0.11, 0.11, 0.12), 0.85, 0.05)
	var roof_pod := _mat(Color(0.84, 0.86, 0.88), 0.38, 0.18)
	var led_amber := _emissive(Color(1.0, 0.72, 0.18), 1.8)
	var head_glow := _emissive(Color(1.0, 0.96, 0.84), 2.0)
	var tail_glow := _emissive(Color(0.95, 0.12, 0.12), 1.5)
	# 11.8m x 2.55m x 2.85m low-floor electric transit bus body (along local X)
	_add_box(b, Vector3(11.6, 2.55, 2.52), Vector3(0.0, 1.58, 0.0), body_white)
	_add_box(b, Vector3(11.66, 0.76, 2.56), Vector3(0.0, 0.82, 0.0), accent)
	# Panoramic side & front tinted windows
	_add_box(b, Vector3(10.8, 1.12, 2.58), Vector3(0.0, 1.88, 0.0), glass_dark)
	_add_box(b, Vector3(0.16, 1.45, 2.28), Vector3(-5.78, 1.75, 0.0), glass_dark)
	# Glowing amber LED destination matrix & front headlights / rear taillights
	_add_box(b, Vector3(0.12, 0.26, 1.45), Vector3(-5.82, 2.62, 0.0), led_amber, 0.0, 0.0, 0.0, false)
	for wz: float in [-0.95, 0.95]:
		_add_box(b, Vector3(0.10, 0.22, 0.34), Vector3(-5.82, 0.72, wz), head_glow, 0.0, 0.0, 0.0, false)
		_add_box(b, Vector3(0.10, 0.26, 0.30), Vector3(5.82, 0.95, wz), tail_glow, 0.0, 0.0, 0.0, false)
	# Rooftop electric battery & HVAC aerodynamic pod
	_add_box(b, Vector3(6.8, 0.42, 1.75), Vector3(0.4, 3.04, 0.0), roof_pod)
	# 4 rubber tires
	for wx: float in [-3.4, 3.3]:
		for wz: float in [-1.18, 1.18]:
			_add_cyl(b, 0.48, 0.48, 0.32, Vector3(wx, 0.48, wz), wheel_dark, 10, Vector3(PI * 0.5, 0.0, 0.0))


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

	# --- C. MAD "Train Station in the Forest" Floating Roof + Sunken Skylights (North Plaza, z = -48) ---
	var lawn_slope := lawn_material()
	var b1_floor := _mat(Color(0.76, 0.77, 0.78), 0.65, 0.04)
	var b1_wall := _mat(Color(0.86, 0.85, 0.82), 0.70, 0.02)
	var stone_warm := _mat(Color(0.83, 0.80, 0.74), 0.72, 0.03)
	var dark_frame := _mat(Color(0.20, 0.23, 0.27), 0.48, 0.42)

	# North forecourt granite plaza & sculpted green forest mounds framing the floating solar canopy
	_add_box(jx, Vector3(136.0, 0.06, 52.0), Vector3(0.0, -0.01, -50.0), granite, 0.0, 0.0, 0.0, false)
	for mx: float in [-58.0, 58.0]:
		_add_box(jx, Vector3(36.0, 2.2, 34.0), Vector3(mx, 0.9, -56.0), lawn_slope, 0.0, -signf(mx) * 0.09)
	# Ultra-low floating photovoltaic roof canopy (MAD signature low-profile timber-soffit roof hovering over sunken hall)
	_add_box(jx, Vector3(132.0, 0.52, 42.0), Vector3(0.0, 7.8, -46.0), solar_dark)
	_add_box(jx, Vector3(130.0, 0.30, 40.0), Vector3(0.0, 7.42, -46.0), ceiling_wood)
	# Sunken glass skylight pavilion descending into the B1 station hall
	_add_box(jx, Vector3(88.0, 5.4, 24.0), Vector3(0.0, 2.7, -46.0), glass_clear)
	_add_box(jx, Vector3(82.0, 4.2, 20.0), Vector3(0.0, 2.1, -46.0), warm_glow, 0.0, 0.0, 0.0, false)
	for ci in range(-6, 7):
		var cx := float(ci) * 10.2
		_add_cyl(jx, 0.24, 0.28, 7.4, Vector3(cx, 3.7, -64.0), steel_white, 10)
		_add_cyl(jx, 0.24, 0.28, 7.4, Vector3(cx, 3.7, -28.0), steel_white, 10)
	_add_sign_label(jx, "嘉 兴 站", Vector3(0.0, 9.5, -67.2), PI, 108, 0.034, Color(0.92, 0.16, 0.16))
	_add_sign_label(jx, "JIAXING RAILWAY STATION", Vector3(0.0, 7.8, -67.2), PI, 34, 0.022, Color(0.94, 0.95, 0.98))

	# --- C2. Authentic B1 Underground Station Concourse, Transfer Hub & Sunken Courts (y = -10.0m .. -2.6m) ---
	# Rich multi-zone underground transit hub: North Sunken Court + B1 Ticket/Security Hall + Central Timber Waiting Hall
	# + Commercial Arcade + B1 Drop-off Taxi Lanes + South Rail/Metro Interchange Hall (visible cleanly at B1 elevation!)
	var b1 := Node3D.new()
	b1.name = "JiaxingStationB1Hall"
	b1.position.y = -0.35 # Sit cleanly below B1 (-10.0m) T1 underground rail top with zero Z-fighting!
	jx.add_child(b1)
	var b1_slate := _mat(Color(0.22, 0.25, 0.29), 0.72, 0.08)
	var b1_terrazzo := _mat(Color(0.54, 0.56, 0.58), 0.62, 0.06)
	var b1_wood_floor := _mat(Color(0.68, 0.54, 0.38), 0.65, 0.04)
	var b1_road_dark := _mat(Color(0.16, 0.17, 0.19), 0.84, 0.02)
	var b1_lane_amber := _emissive(Color(0.95, 0.74, 0.24), 0.9)
	var b1_metro_cyan := _emissive(Color(0.22, 0.82, 0.96), 1.3)
	var b1_shop_warm := _emissive(Color(1.0, 0.84, 0.54), 1.1)
	var b1_seat_blue := _mat(Color(0.24, 0.42, 0.58), 0.58, 0.10)
	var b1_courtyard_grass := _mat(Color(0.22, 0.48, 0.24), 0.84, 0.0)

	# Structural B1 base deck (176m wide x 192m N-S spanning North Plaza -> Tracks -> South Plaza Interchange)
	# Central axial corridor (local x in [-13.5 .. +13.5]) is kept 100% UNOBSTRUCTED for the T1 B1 Underground Tramway!
	_add_box(b1, Vector3(176.0, 0.45, 192.0), Vector3(0.0, -10.2, 6.0), b1_slate, 0.0, 0.0, 0.0, false)
	# Central Main Waiting Concourse Floor (terrazzo + warm wood side concourses flanking the central tram corridor)
	_add_box(b1, Vector3(122.0, 0.16, 128.0), Vector3(0.0, -9.90, 0.0), b1_terrazzo, 0.0, 0.0, 0.0, false)
	for side_p: float in [-1.0, 1.0]:
		_add_box(b1, Vector3(14.0, 0.18, 178.0), Vector3(side_p * 21.0, -9.84, 6.0), b1_wood_floor, 0.0, 0.0, 0.0, false)
	# Twin Flanking Sunken Garden Lightwells inside B1 (signature MAD daylight courts on East & West concourses, clear of central tramway!)
	for side_g: float in [-1.0, 1.0]:
		for sc_z: float in [-56.0, 56.0]:
			var gx_c := side_g * 36.0
			_add_cyl(b1, 10.5, 11.0, 0.32, Vector3(gx_c, -9.75, sc_z), b1_courtyard_grass, 18)
			_add_cyl(b1, 11.4, 11.4, 0.55, Vector3(gx_c, -9.62, sc_z), granite, 18)
			for gt_a in range(4):
				var ang_g := float(gt_a) * TAU / 4.0
				var gx_t := gx_c + cos(ang_g) * 4.8
				var gz_t := sc_z + sin(ang_g) * 4.8
				_add_cyl(b1, 0.22, 0.28, 3.2, Vector3(gx_t, -8.1, gz_t), ceiling_wood, 7)
				_add_cyl(b1, 1.3, 2.5, 2.6, Vector3(gx_t, -6.0, gz_t), b1_courtyard_grass, 8)
	# East & West B1 Commercial Arcade Pavilions & Retail Bays (地下商业街)
	for side_b: float in [-1.0, 1.0]:
		var sx_b := side_b * 72.0
		_add_box(b1, Vector3(22.0, 6.8, 138.0), Vector3(sx_b, -6.5, 4.0), b1_wall, 0.0, 0.0, 0.0, false)
		for shop_i in range(-4, 5):
			var sz_shop := float(shop_i) * 14.5 + 4.0
			_add_box(b1, Vector3(1.2, 3.6, 10.4), Vector3(sx_b - side_b * 11.2, -7.8, sz_shop), b1_shop_warm, 0.0, 0.0, 0.0, false)
			_add_box(b1, Vector3(1.6, 0.5, 11.2), Vector3(sx_b - side_b * 11.4, -5.8, sz_shop), dark_frame, 0.0, 0.0, 0.0, false)
	# North & South B1 Perimeter Lining Walls — split symmetrically around the 28m central tram portal (x in [-14..+14]) so ZERO walls ever block the tracks!
	for side_w: float in [-1.0, 1.0]:
		_add_box(b1, Vector3(74.0, 7.2, 1.0), Vector3(side_w * 51.0, -6.4, -90.0), b1_wall, 0.0, 0.0, 0.0, false)
		_add_box(b1, Vector3(74.0, 7.2, 1.0), Vector3(side_w * 51.0, -6.4, 102.0), b1_wall, 0.0, 0.0, 0.0, false)
	# North B1 Underground Drop-Off / Taxi / Bus Bay Roadway Loop (z = -84..-72, flush floor markings)
	_add_box(b1, Vector3(148.0, 0.14, 14.0), Vector3(0.0, -9.88, -79.0), b1_road_dark, 0.0, 0.0, 0.0, false)
	for ln_z: float in [-83.5, -79.0, -74.5]:
		for side_l: float in [-1.0, 1.0]:
			_add_box(b1, Vector3(54.0, 0.06, 0.35), Vector3(side_l * 43.0, -9.78, ln_z), b1_lane_amber, 0.0, 0.0, 0.0, false)
	# South B1 Rail Transit / Tram / Metro Interchange Hall (z = +72..+98, bright cyan transfer zone!)
	_add_box(b1, Vector3(136.0, 0.22, 26.0), Vector3(0.0, -9.84, 86.0), b1_terrazzo, 0.0, 0.0, 0.0, false)
	for side_c: float in [-1.0, 1.0]:
		_add_box(b1, Vector3(50.0, 0.12, 1.4), Vector3(side_c * 41.0, -9.70, 74.0), b1_metro_cyan, 0.0, 0.0, 0.0, false)
		_add_box(b1, Vector3(50.0, 0.12, 1.4), Vector3(side_c * 41.0, -9.70, 98.0), b1_metro_cyan, 0.0, 0.0, 0.0, false)
	# B1 Ticket/Security Gate Arrays & Waiting Hall Seating Islands (strictly outside x in [-16..+16] tram clearance!)
	for side_w: float in [-1.0, 1.0]:
		for g_idx in range(4):
			var gx_gate := side_w * (18.5 + float(g_idx) * 4.4)
			_add_box(b1, Vector3(1.2, 1.25, 0.6), Vector3(gx_gate, -9.2, -34.0), b1_metro_cyan, 0.0, 0.0, 0.0, false)
			_add_box(b1, Vector3(1.2, 1.25, 0.6), Vector3(gx_gate, -9.2, 34.0), b1_metro_cyan, 0.0, 0.0, 0.0, false)
		for row_z: float in [-22.0, -10.0, 10.0, 22.0]:
			_add_box(b1, Vector3(24.0, 0.85, 3.2), Vector3(side_w * 36.0, -9.35, row_z), b1_seat_blue, 0.0, 0.0, 0.0, false)
	# Structural colonnade & escalators ascending from B1 (-10m) to the 3 surface rail platforms (strictly outside central tramway!)
	for rx: float in [-50.0, -25.0, -14.5, 14.5, 25.0, 50.0]:
		for rz: float in [-42.0, -18.0, 18.0, 42.0, 76.0]:
			_add_cyl(b1, 0.52, 0.58, 7.2, Vector3(rx, -6.4, rz), steel_white, 10)
	for bx_e: float in [-38.0, 38.0]:
		for pz_e: float in [-18.5, 0.0, 18.5]:
			_add_box(b1, Vector3(3.2, 0.65, 16.0), Vector3(bx_e, -5.2, pz_e), dark_frame, 0.0, 0.0, 0.52, false)
			_add_box(b1, Vector3(3.4, 0.18, 16.0), Vector3(bx_e, -4.85, pz_e), b1_metro_cyan, 0.0, 0.0, 0.52, false)
	# Warm timber coffered B1 ceiling beams & glowing skylight light-wells (separate roof group for X-Ray cutaway!)
	var b1_roof := Node3D.new()
	b1_roof.name = "UndergroundStationRoof"
	b1.add_child(b1_roof)
	_add_box(b1_roof, Vector3(176.0, 0.45, 192.0), Vector3(0.0, -2.75, 6.0), ceiling_wood, 0.0, 0.0, 0.0, true) # casts: keeps sunlight out of B1
	for b1_lx: float in [-42.0, 0.0, 42.0]:
		_add_box(b1_roof, Vector3(18.0, 0.25, 146.0), Vector3(b1_lx, -3.05, 4.0), warm_glow, 0.0, 0.0, 0.0, false)
	_add_sign_label(b1, "嘉兴站 · B1 地下候车大厅", Vector3(0.0, -4.4, -36.0), 0.0, 96, 0.034, Color(0.55, 0.94, 1.0))
	_add_sign_label(b1, "B1 北广场地下落客/出租车通道", Vector3(0.0, -4.4, -79.0), 0.0, 68, 0.028, Color(1.0, 0.84, 0.36))
	_add_sign_label(b1, "B1 轨交/有轨电车换乘大厅", Vector3(0.0, -4.4, 86.0), PI, 82, 0.032, Color(0.32, 0.96, 0.88))
	for b1_lz: float in [-60.0, 0.0, 70.0]:
		var b1_pl := OmniLight3D.new()
		b1_pl.position = Vector3(0.0, -4.2, b1_lz)
		b1_pl.light_color = Color(1.0, 0.95, 0.84)
		b1_pl.omni_range = 88.0
		b1_pl.light_energy = 2.0
		b1_pl.visible = true
		b1.add_child(b1_pl)

	# --- D. 1921 Historic Brick Old Jiaxing Station (嘉兴老火车站复建) in North Heritage Plaza ---
	var old_st := Node3D.new()
	old_st.position = Vector3(-48.0, 0.0, -86.0)
	jx.add_child(old_st)
	_add_box(old_st, Vector3(36.0, 10.2, 14.0), Vector3(0.0, 5.1, 0.0), brick_red)
	_add_box(old_st, Vector3(36.4, 1.4, 14.4), Vector3(0.0, 0.7, 0.0), brick_grey)
	_add_box(old_st, Vector3(36.4, 0.55, 14.4), Vector3(0.0, 5.4, 0.0), steel_white)
	_add_box(old_st, Vector3(12.0, 12.6, 15.2), Vector3(0.0, 6.3, 0.0), brick_red)
	_add_box(old_st, Vector3(38.0, 0.6, 9.2), Vector3(0.0, 11.4, -3.5), tile_grey, 0.0, 0.0, 0.42)
	_add_box(old_st, Vector3(38.0, 0.6, 9.2), Vector3(0.0, 11.4, 3.5), tile_grey, 0.0, 0.0, -0.42)
	_add_sign_label(old_st, "嘉 兴 老 站 · 1921", Vector3(0.0, 13.4, -7.8), PI, 56, 0.022, Color(0.96, 0.88, 0.62))

	# --- E. Authentic Jiaxing Station South Plaza Complex ("森林中的火车站" 南广场完整建筑群与森林公园) ---
	var tree_trunk := _mat(Color(0.32, 0.24, 0.17), 0.88, 0.0)
	var tree_green := _mat(Color(0.20, 0.46, 0.20), 0.82, 0.0)
	var tree_bright := _mat(Color(0.28, 0.54, 0.24), 0.80, 0.0)
	var facade_cream := _mat(Color(0.86, 0.83, 0.77), 0.68, 0.03)

	# Full-block South Plaza granite & sunken forest lawn promenade (z = +32 .. +146)
	_add_box(jx, Vector3(236.0, 0.05, 112.0), Vector3(0.0, -0.01, 88.0), granite, 0.0, 0.0, 0.0, false)
	# Sweeping floating timber-and-glass South Entrance Pavilion connecting directly down to B1
	_add_box(jx, Vector3(106.0, 0.50, 30.0), Vector3(0.0, 7.2, 48.0), solar_dark)
	_add_box(jx, Vector3(104.0, 0.28, 28.0), Vector3(0.0, 6.82, 48.0), ceiling_wood)
	_add_box(jx, Vector3(76.0, 5.4, 17.0), Vector3(0.0, 2.7, 48.0), glass_clear)
	_add_box(jx, Vector3(70.0, 4.2, 14.0), Vector3(0.0, 2.1, 48.0), warm_glow, 0.0, 0.0, 0.0, false)
	for sci in range(-5, 6):
		_add_cyl(jx, 0.24, 0.28, 6.8, Vector3(float(sci) * 10.0, 3.4, 61.5), steel_white, 10)
	_add_sign_label(jx, "嘉 兴 站 · 南 广 场", Vector3(0.0, 8.8, 63.4), 0.0, 102, 0.034, Color(0.92, 0.16, 0.16))

	# Circular Sunken Daylight Atrium Dome in central South Plaza (南广场下沉绿岛玻璃中庭)
	_add_cyl(jx, 15.0, 16.5, 1.4, Vector3(0.0, 0.7, 84.0), lawn_slope, 20)
	_add_cyl(jx, 11.2, 12.6, 2.8, Vector3(0.0, 2.1, 84.0), glass_clear, 20)
	_add_cyl(jx, 12.8, 12.8, 0.35, Vector3(0.0, 3.6, 84.0), roof_silver, 20)

	# Full Multi-Wing South Plaza Architectural Ensemble (东西两侧真实红砖/石材商业综合体、酒店、办公楼、文化展馆)
	for side_s: float in [-1.0, 1.0]:
		# 1. Inner Heritage Brick Cultural & Commercial Pavilion flanking central plaza (x = ±62, z = 78)
		var ix_s := side_s * 62.0
		_add_box(jx, Vector3(44.0, 10.2, 48.0), Vector3(ix_s, 5.1, 78.0), brick_red if side_s < 0.0 else stone_warm)
		_add_box(jx, Vector3(44.6, 4.4, 44.0), Vector3(ix_s, 2.6, 78.0), glass_clear)
		_add_box(jx, Vector3(46.0, 0.65, 50.0), Vector3(ix_s, 10.5, 78.0), solar_dark)
		_add_box(jx, Vector3(32.0, 7.6, 32.0), Vector3(ix_s + side_s * 3.0, 14.3, 80.0), facade_cream)
		_add_box(jx, Vector3(32.5, 4.6, 28.0), Vector3(ix_s + side_s * 3.0, 14.3, 80.0), glass_clear)
		_add_box(jx, Vector3(34.0, 0.55, 34.0), Vector3(ix_s + side_s * 3.0, 18.3, 80.0), dark_frame)
		# 2. Outer Multi-Story Commercial & Station Hotel Complex (x = ±106, z = 74)
		var ox_s := side_s * 106.0
		_add_box(jx, Vector3(36.0, 11.0, 56.0), Vector3(ox_s, 5.5, 74.0), stone_warm)
		_add_box(jx, Vector3(36.6, 4.6, 52.0), Vector3(ox_s, 2.8, 74.0), glass_clear)
		_add_box(jx, Vector3(26.0, 22.0, 30.0), Vector3(ox_s, 21.0, 68.0), facade_cream if side_s > 0.0 else brick_red)
		_add_box(jx, Vector3(26.5, 18.0, 26.0), Vector3(ox_s, 21.0, 68.0), glass_clear)
		_add_box(jx, Vector3(27.6, 0.8, 31.6), Vector3(ox_s, 32.4, 68.0), dark_frame)
		# 3. South-Wing Retail Arcade & Pedestrian Gallery (x = ±68, z = 124)
		_add_box(jx, Vector3(52.0, 12.6, 28.0), Vector3(side_s * 68.0, 6.3, 124.0), brick_red if side_s > 0.0 else facade_cream)
		_add_box(jx, Vector3(52.6, 4.8, 24.0), Vector3(side_s * 68.0, 3.0, 124.0), glass_clear)
		_add_box(jx, Vector3(54.0, 0.55, 30.0), Vector3(side_s * 68.0, 12.9, 124.0), solar_dark)
		# 4. South Plaza terraced forest lawns flanking the central pedestrian promenade
		_add_box(jx, Vector3(24.0, 1.3, 44.0), Vector3(side_s * 28.0, 0.65, 86.0), lawn_slope)
		# Lush "Forest Station" tree rows lining both plazas
		for ti in range(5):
			var tz_tr := 64.0 + float(ti) * 11.5
			var tx_tr := side_s * (24.0 + float(ti % 2) * 8.0)
			ParkLandscapeBuilder.plant_tree(jx, Vector3(tx_tr, 0.5, tz_tr), 1, 1.0, ParkLandscapeBuilder.CAMPHOR if (ti % 2 == 0) else ParkLandscapeBuilder.CAMPHOR_LT)
		for nti in range(5):
			var nx_tr := side_s * (46.0 + float(nti) * 11.0)
			var nz_tr := -62.0 - float(nti % 2) * 10.0
			ParkLandscapeBuilder.plant_tree(jx, Vector3(nx_tr, 0.0, nz_tr), 1, 1.05, ParkLandscapeBuilder.CAMPHOR if (nti % 2 == 0) else ParkLandscapeBuilder.CAMPHOR_LT)

	# South Plaza Bus & Coach Transit Hub (南广场公交与客运换乘枢纽: 6 sheltered bays + waiting hall)
	_add_box(jx, Vector3(68.0, 0.42, 18.0), Vector3(0.0, 5.4, 122.0), roof_silver)
	_add_box(jx, Vector3(66.0, 0.20, 16.0), Vector3(0.0, 5.12, 122.0), ceiling_wood, 0.0, 0.0, 0.0, false)
	_add_box(jx, Vector3(24.0, 4.6, 10.0), Vector3(0.0, 2.3, 122.0), glass_clear)
	for bci in range(-4, 5):
		_add_cyl(jx, 0.22, 0.26, 5.2, Vector3(float(bci) * 8.0, 2.6, 114.0), dark_frame, 8)
		_add_cyl(jx, 0.22, 0.26, 5.2, Vector3(float(bci) * 8.0, 2.6, 130.0), dark_frame, 8)
	_add_sign_label(jx, "嘉兴站南广场公交枢纽", Vector3(0.0, 6.5, 131.5), 0.0, 58, 0.022, Color(0.92, 0.96, 1.0))

	var pl := OmniLight3D.new()
	pl.position = Vector3(0.0, 9.0, -56.0)
	pl.light_color = Color(1.0, 0.88, 0.68)
	pl.omni_range = 55.0
	pl.light_energy = 0.0
	pl.visible = false
	jx.add_child(pl)
	lights.append(pl)
	var pl_s := OmniLight3D.new()
	pl_s.position = Vector3(0.0, 9.0, 68.0)
	pl_s.light_color = Color(1.0, 0.90, 0.72)
	pl_s.omni_range = 65.0
	pl_s.light_energy = 0.0
	pl_s.visible = false
	jx.add_child(pl_s)
	lights.append(pl_s)


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
	# Weathered granite stone arch bridge (月河 photos): humped deck, semicircular arch ring of voussoirs on both
	# faces, spandrel walls down to the water, balustrade of posts and panels with a top rail
	var br := Node3D.new()
	br.position = center
	br.rotation.y = angle
	parent.add_child(br)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.64, 0.60, 0.55)
	var stone_d := Color(0.50, 0.47, 0.43)
	var wet := Color(0.40, 0.38, 0.35)
	var hw := 2.5
	var rise := clampf(span * 0.13, 1.8, 3.4)
	var R := clampf(span * 0.24, 2.2, 5.2)
	var segs := 14
	var deck_y := func(u: float) -> float: return 0.55 + cos(u * PI) * rise
	for k in range(segs):
		var u0 := -0.5 + float(k) / float(segs)
		var u1 := -0.5 + float(k + 1) / float(segs)
		var um := (u0 + u1) * 0.5
		var h0: float = deck_y.call(u0)
		var h1: float = deck_y.call(u1)
		var dx := (u1 - u0) * span
		var tilt := atan2(h1 - h0, dx)
		var sl := sqrt(dx * dx + (h1 - h0) * (h1 - h0)) + 0.1
		var xf := Transform3D(Basis(Vector3(0, 0, 1), tilt), Vector3(um * span, (h0 + h1) * 0.5, 0.0))
		RoadSignBuilder._box(st, xf, Vector3(sl, 0.5, hw * 2.0), stone)
		# spandrel walls on both faces, open where the arch is
		var x := um * span
		var open_top := sqrt(maxf(0.0, R * R - x * x)) - 0.6 if absf(x) < R else -0.6
		var wall_bot := maxf(open_top, -0.6)
		var wall_top := (h0 + h1) * 0.5 - 0.25
		if wall_top - wall_bot > 0.1:
			for zf: float in [-1.0, 1.0]:
				RoadSignBuilder._box(st, Transform3D(Basis.IDENTITY, Vector3(x, (wall_top + wall_bot) * 0.5, zf * (hw - 0.2))), Vector3(dx + 0.05, wall_top - wall_bot, 0.4), wet if wall_bot < 0.2 else stone_d)
		# balustrade: post every segment, panel between, top rail
		for zf2: float in [-1.0, 1.0]:
			RoadSignBuilder._box(st, Transform3D(Basis.IDENTITY, Vector3(u0 * span, h0 + 0.65, zf2 * (hw - 0.15))), Vector3(0.24, 1.0, 0.24), stone)
			RoadSignBuilder._box(st, xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, zf2 * (hw - 0.15))), Vector3(sl - 0.25, 0.55, 0.12), stone_d)
			RoadSignBuilder._box(st, xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.95, zf2 * (hw - 0.15))), Vector3(sl, 0.1, 0.2), stone)
	# arch ring (voussoirs) on both faces
	for i in range(13):
		var a0 := PI * (float(i) + 0.5) / 13.0
		var p := Vector3(cos(a0) * (R + 0.25), sin(a0) * (R + 0.25) - 0.6, 0.0)
		for zf3: float in [-1.0, 1.0]:
			RoadSignBuilder._box(st, Transform3D(Basis(Vector3(0, 0, 1), a0 + PI * 0.5), p + Vector3(0.0, 0.0, zf3 * (hw - 0.15))), Vector3(R * PI / 13.0 + 0.05, 0.5, 0.46), stone.lightened(0.05))
	var mi := MeshInstance3D.new()
	mi.name = "StoneArchBridge"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	br.add_child(mi)


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
