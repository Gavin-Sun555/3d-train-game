class_name SeattleV2Landmarks
extends RefCounted

# Seattle Center & Elliott Bay waterfront landmarks for the extended Seattle map (v2).
# Proportions follow the real structures:
#   Space Needle (1962): 184m; three pairs of legs pinching to a waist then flaring into the halo top house
#     (restaurant ~150m, observation deck ~158m, roof + spire to 184m); 30m "SpaceBase" ring; glass Pavilion.
#   Climate Pledge Arena: the 1962 hyperbolic-paraboloid saddle roof floating over a glass curtain wall.
#   MoPOP (Gehry, 2000): cluster of crumpled metal-clad volumes in red, purple, gold, silver and blue.
#   Pacific Science Center (Yamasaki, 1962): white Gothic lattice arches over reflecting pools.
#   International Fountain: wide white bowl with the central silver dome of nozzles.
#   Chihuly Garden and Glass: steel-and-glass Glasshouse with a giant red/orange glass sculpture.
#   Seattle Great Wheel (Pier 57, 53m), Seattle Aquarium (Pier 59), Pike Place Market "PUBLIC MARKET
#   CENTER" neon sign + clock, Calder's red "Eagle" (Olympic Sculpture Park), Seattle Center monorail terminal.

const SKIP_GENERIC := ["space_needle", "mopop", "climate_pledge"]


static func build(parent: Node3D, map_data: Dictionary, lights: Array) -> void:
	var lm: Dictionary = map_data.get("landmarks", {})
	var root := Node3D.new()
	root.name = "SeattleCenterAndWaterfront"
	parent.add_child(root)
	var buildings: Array = map_data.get("buildings", [])
	if lm.has("space_needle"):
		_space_needle(root, _p(lm["space_needle"]["pos"]), lights)
	for b: Dictionary in buildings:
		match str(b.get("lm", "")):
			"climate_pledge":
				_climate_pledge(root, b)
			"mopop":
				_mopop(root, b)
	if lm.has("pacific_science"):
		_science_arches(root, _p(lm["pacific_science"]["pos"]) + Vector3(-6.0, 0.0, 4.0))
	if lm.has("international_fountain"):
		_international_fountain(root, _p(lm["international_fountain"]["pos"]), lights)
	if lm.has("chihuly"):
		_chihuly_glasshouse(root, _p(lm["chihuly"]["pos"]), lights)
	if lm.has("colman_dock"):
		_colman_dock(root, lights)
	if lm.has("great_wheel"):
		_great_wheel(root, _p(lm["great_wheel"]["pos"]), lights)
	if lm.has("aquarium"):
		_aquarium_sign(root, _p(lm["aquarium"]["pos"]))
	if lm.has("pike_market_sign"):
		var pm: Dictionary = lm["pike_market_sign"]
		var fa: Array = pm.get("face", [0.85, 0.52])
		_pike_market_sign(root, _p(pm["pos"]), Vector3(float(fa[0]), 0.0, float(fa[1])), float(pm.get("roof_h", 10.5)), lights)
	if lm.has("sculpture_eagle"):
		_calder_eagle(root, _p(lm["sculpture_eagle"]["pos"]))
	var mono: Dictionary = lm.get("monorail", {})
	if mono.has("station2_pos") and mono.has("path"):
		_monorail_terminal(root, mono)
	_piers(root, map_data.get("piers", []))
	_outer_bay(root, map_data, parent.get_meta("water_mat") if parent.has_meta("water_mat") else null)


# Elliott Bay continues to the horizon beyond the map edge: the half-plane seaward of the Alaskan Way
# shoreline, minus the map rectangle (inside the map the real OSM water polygons are used).
static func _outer_bay(parent: Node3D, map_data: Dictionary, water_mat: Material) -> void:
	if water_mat == null:
		return
	var b: Array = map_data.get("bounds", [])
	if b.size() < 4:
		return
	var A := Vector2(-1285.0, 351.0)
	var B := Vector2(120.0, 1829.0)
	var d := (B - A).normalized()
	var n := Vector2(-d.y, d.x)
	if n.dot(Vector2(-1500.0, 351.0) - A) < 0.0:
		n = -n
	var far := 20000.0
	var bay := PackedVector2Array([A - d * far, B + d * far, B + d * far + n * far, A - d * far + n * far])
	var inset := 50.0
	var rect := PackedVector2Array([
		Vector2(float(b[0]) + inset, float(b[1]) + inset), Vector2(float(b[2]) - inset, float(b[1]) + inset),
		Vector2(float(b[2]) - inset, float(b[3]) - inset), Vector2(float(b[0]) + inset, float(b[3]) - inset),
	])
	var parts := Geometry2D.clip_polygons(bay, rect)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for poly: PackedVector2Array in parts:
		if Geometry2D.is_polygon_clockwise(poly):
			continue # holes (not expected here)
		var idx := Geometry2D.triangulate_polygon(poly)
		for i in range(0, idx.size(), 3):
			for k: int in [0, 2, 1]:
				var p := poly[idx[i + k]]
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p.x, -0.005, p.y))
				any = true
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.name = "ElliottBayOuter"
	mi.mesh = st.commit()
	mi.material_override = water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _p(a: Array) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1]))


# ---------------------------------------------------------------------------------------------
# Materials & mesh helpers
# ---------------------------------------------------------------------------------------------
static func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func _glass(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.4
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _emit(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = sz
	var mi := _mi(parent, b, mat, pos)
	mi.rotation_degrees = rot_deg
	return mi


# Surface of revolution around +Y from a (radius, height) profile
static func _lathe(profile: Array, segs: int, cap_top: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(profile.size() - 1):
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for k in range(segs):
			var t0 := TAU * float(k) / float(segs)
			var t1 := TAU * float(k + 1) / float(segs)
			var p00 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			for v: Vector3 in [p00, p10, p11, p00, p11, p01]:
				st.set_uv(Vector2(float(k) / float(segs), v.y))
				st.add_vertex(v)
	if cap_top:
		var top: Vector2 = profile[profile.size() - 1]
		for k in range(segs):
			var t0 := TAU * float(k) / float(segs)
			var t1 := TAU * float(k + 1) / float(segs)
			for v: Vector3 in [Vector3(0, top.y, 0), Vector3(cos(t1) * top.x, top.y, sin(t1) * top.x), Vector3(cos(t0) * top.x, top.y, sin(t0) * top.x)]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


# Tube swept along a polyline (radius per point)
static func _tube(st: SurfaceTool, pts: Array, radii: Array, sides: int = 8) -> void:
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := (b - a).normalized()
		var side := d.cross(Vector3.UP)
		if side.length_squared() < 1e-4:
			side = d.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(d).normalized()
		var ra := float(radii[i])
		var rb := float(radii[i + 1])
		for k in range(sides):
			var t0 := TAU * float(k) / float(sides)
			var t1 := TAU * float(k + 1) / float(sides)
			var o0 := side * cos(t0) + up * sin(t0)
			var o1 := side * cos(t1) + up * sin(t1)
			for v: Vector3 in [a + o0 * ra, b + o0 * rb, b + o1 * rb, a + o0 * ra, b + o1 * rb, a + o1 * ra]:
				st.add_vertex(v)


static func _tube_mesh(paths: Array, radii_list: Array, sides: int = 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(paths.size()):
		_tube(st, paths[i], radii_list[i], sides)
	st.generate_normals()
	return st.commit()


static func _light(parent: Node3D, pos: Vector3, col: Color, rng: float, lights: Array) -> void:
	var ol := OmniLight3D.new()
	ol.light_color = col
	ol.light_energy = 0.0
	ol.visible = false
	ol.omni_range = rng
	ol.distance_fade_enabled = true
	ol.distance_fade_begin = 220.0
	ol.distance_fade_length = 60.0
	ol.position = pos
	parent.add_child(ol)
	lights.append(ol)


static func _label(parent: Node3D, txt: String, pos: Vector3, face: Vector3, height: float, col: Color, unlit: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 96
	l.outline_size = 0
	l.modulate = col
	l.shaded = not unlit
	l.double_sided = false
	l.pixel_size = height / 96.0
	l.transform = Transform3D(StorefrontBuilder._face_basis(face.normalized()), pos)
	parent.add_child(l)
	return l


# ---------------------------------------------------------------------------------------------
# Space Needle
# ---------------------------------------------------------------------------------------------
static func _space_needle(parent: Node3D, base: Vector3, lights: Array) -> void:
	var root := Node3D.new()
	root.name = "SpaceNeedle"
	root.position = base
	parent.add_child(root)
	var white := _mat(Color(0.94, 0.94, 0.92), 0.4, 0.15)
	var steel := _mat(Color(0.82, 0.83, 0.84), 0.3, 0.6)
	var concrete := _mat(Color(0.78, 0.77, 0.74), 0.85, 0.0)
	var gold := _mat(Color(0.86, 0.62, 0.20), 0.3, 0.8)
	var glass := _glass(Color(0.42, 0.55, 0.62), 0.45)
	# Leg radius profile (height -> distance from axis): pinches to a waist, flares into the top house
	var prof: Array = [[0.0, 17.5], [20.0, 13.6], [45.0, 9.6], [70.0, 7.0], [92.0, 5.6], [108.0, 5.3], [124.0, 6.4], [138.0, 9.6], [147.0, 14.0]]
	var paths: Array = []
	var radii: Array = []
	for leg in range(3):
		var az0 := TAU * float(leg) / 3.0 + 0.3
		for m: float in [-1.0, 1.0]:
			var pts: Array = []
			var rr: Array = []
			for i in range(prof.size()):
				var h := float(prof[i][0])
				var r := float(prof[i][1])
				# The two members of a leg pair spread apart at the base and close at the waist
				var spread := lerpf(0.30, 0.07, clampf(h / 108.0, 0.0, 1.0)) if h <= 108.0 else lerpf(0.07, 0.16, (h - 108.0) / 39.0)
				var az := az0 + m * spread
				pts.append(Vector3(cos(az) * r, h, sin(az) * r))
				rr.append(lerpf(0.95, 0.62, h / 147.0))
			paths.append(pts)
			radii.append(rr)
	# Cross bracing inside each leg pair every ~12m
	var braces: Array = []
	var brr: Array = []
	for leg in range(3):
		var pa: Array = paths[leg * 2]
		var pb: Array = paths[leg * 2 + 1]
		for i in range(1, prof.size() - 1):
			braces.append([pa[i], pb[i]])
			brr.append([0.32, 0.32])
	_mi(root, _tube_mesh(paths, radii, 10), white)
	_mi(root, _tube_mesh(braces, brr, 6), white)
	# Central core with the golden elevator cabs
	_mi(root, _lathe([Vector2(4.2, 0.0), Vector2(3.4, 30.0), Vector2(3.0, 148.0)], 20), concrete)
	for k in range(2):
		var az := 0.3 + TAU * float(k) / 3.0 + 0.5
		_box(root, Vector3(2.0, 3.0, 2.0), Vector3(cos(az) * 4.2, 62.0 + float(k) * 38.0, sin(az) * 4.2), gold)
	# 100ft "SpaceBase" ring
	_mi(root, _lathe([Vector2(13.2, 29.0), Vector2(14.6, 30.2), Vector2(14.6, 31.4), Vector2(13.0, 32.0)], 48), white)
	_mi(root, _lathe([Vector2(4.0, 29.4), Vector2(13.0, 29.4)], 48), white)
	# Top house: underside cone, glass restaurant drum, observation deck, halo lip, roof and spire
	_mi(root, _lathe([Vector2(5.5, 138.0), Vector2(14.0, 146.0), Vector2(20.5, 150.0)], 64), white)
	_mi(root, _lathe([Vector2(20.5, 150.0), Vector2(20.8, 153.0)], 64), glass)
	_mi(root, _lathe([Vector2(20.8, 153.0), Vector2(22.6, 153.4), Vector2(22.6, 154.2), Vector2(21.0, 154.4)], 64), white)
	_mi(root, _lathe([Vector2(21.0, 154.4), Vector2(21.0, 158.4)], 64), glass)
	_mi(root, _lathe([Vector2(23.4, 154.4), Vector2(23.6, 157.4)], 64), _glass(Color(0.7, 0.8, 0.85), 0.25))
	_mi(root, _lathe([Vector2(21.0, 158.4), Vector2(24.6, 158.9), Vector2(24.6, 159.8), Vector2(20.5, 160.3), Vector2(15.0, 162.2), Vector2(7.0, 164.6), Vector2(3.2, 166.0)], 64, true), white)
	# Halo fins around the top house
	for k in range(48):
		var az := TAU * float(k) / 48.0
		var fin := _box(root, Vector3(3.6, 0.35, 0.22), Vector3(cos(az) * 22.6, 151.6, sin(az) * 22.6), steel)
		fin.rotation.y = -az
	# Spire + beacon
	_mi(root, _lathe([Vector2(1.6, 166.0), Vector2(0.9, 176.0), Vector2(0.25, 184.0)], 12), steel)
	var beacon := SphereMesh.new()
	beacon.radius = 0.55
	beacon.height = 1.1
	_mi(root, beacon, _emit(Color(1.0, 0.25, 0.15), 3.0), Vector3(0, 184.3, 0))
	_light(root, Vector3(0, 156.0, 0), Color(1.0, 0.92, 0.80), 40.0, lights)
	# Glass spiral Pavilion around the base
	_mi(root, _lathe([Vector2(24.0, 0.0), Vector2(24.0, 6.0)], 48), _glass(Color(0.5, 0.62, 0.68), 0.5))
	_mi(root, _lathe([Vector2(9.0, 6.0), Vector2(24.5, 6.0), Vector2(24.5, 6.6), Vector2(9.0, 6.6)], 48), white)
	for k in range(24):
		var az := TAU * float(k) / 24.0
		_box(root, Vector3(0.25, 6.0, 0.25), Vector3(cos(az) * 24.0, 3.0, sin(az) * 24.0), steel)
	# Leg footings
	for leg in range(3):
		for m: float in [-1.0, 1.0]:
			var p: Vector3 = (paths[leg * 2 + (0 if m < 0.0 else 1)] as Array)[0]
			_box(root, Vector3(3.0, 1.2, 3.0), Vector3(p.x, 0.6, p.z), concrete)


# ---------------------------------------------------------------------------------------------
# Climate Pledge Arena: hyperbolic-paraboloid saddle roof over a glass curtain wall
# ---------------------------------------------------------------------------------------------
static func _climate_pledge(parent: Node3D, b: Dictionary) -> void:
	var pts := PackedVector2Array()
	for p in b["pts"]:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	# Orientation from the longest footprint edge
	var best_d := Vector2.RIGHT
	var best_l := 0.0
	for i in range(pts.size()):
		var e := pts[(i + 1) % pts.size()] - pts[i]
		if e.length() > best_l:
			best_l = e.length()
			best_d = e.normalized()
	var u2 := best_d
	var v2 := Vector2(-best_d.y, best_d.x)
	var hu := 0.0
	var hv := 0.0
	for p in pts:
		hu = maxf(hu, absf((p - c).dot(u2)))
		hv = maxf(hv, absf((p - c).dot(v2)))
	hu = minf(hu, 70.0)
	hv = minf(hv, 70.0)
	var U := Vector3(u2.x, 0, u2.y)
	var V := Vector3(v2.x, 0, v2.y)
	var C := Vector3(c.x, 0, c.y)
	var root := Node3D.new()
	root.name = "ClimatePledgeArena"
	parent.add_child(root)
	var roof_h := func(su: float, sv: float) -> float: return 22.0 + 10.0 * su * sv
	var over := 5.0
	var n := 16
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		for j in range(n):
			var quad: Array = []
			for dd: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var su := -1.0 + 2.0 * float(i + dd.x) / float(n)
				var sv := -1.0 + 2.0 * float(j + dd.y) / float(n)
				quad.append(C + U * (su * (hu + over)) + V * (sv * (hv + over)) + Vector3.UP * float(roof_h.call(su, sv)))
			var shade := 0.94 if (i + j) % 2 == 0 else 0.90
			for idx: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(Color(0.66 * shade, 0.72 * shade, 0.68 * shade))
				st.add_vertex(quad[idx])
	# Thick fascia along the roof edge
	for e in range(4):
		for k in range(n):
			var a0 := -1.0 + 2.0 * float(k) / float(n)
			var a1 := -1.0 + 2.0 * float(k + 1) / float(n)
			var s0 := Vector2(a0, -1.0)
			var s1 := Vector2(a1, -1.0)
			match e:
				1:
					s0 = Vector2(a0, 1.0)
					s1 = Vector2(a1, 1.0)
				2:
					s0 = Vector2(-1.0, a0)
					s1 = Vector2(-1.0, a1)
				3:
					s0 = Vector2(1.0, a0)
					s1 = Vector2(1.0, a1)
			var p0 := C + U * (s0.x * (hu + over)) + V * (s0.y * (hv + over)) + Vector3.UP * float(roof_h.call(s0.x, s0.y))
			var p1 := C + U * (s1.x * (hu + over)) + V * (s1.y * (hv + over)) + Vector3.UP * float(roof_h.call(s1.x, s1.y))
			for v: Vector3 in [p0, p1, p1 - Vector3.UP * 1.6, p0, p1 - Vector3.UP * 1.6, p0 - Vector3.UP * 1.6]:
				st.set_color(Color(0.55, 0.58, 0.56))
				st.add_vertex(v)
	st.generate_normals()
	var rm := _mat(Color(1, 1, 1), 0.7, 0.15)
	rm.vertex_color_use_as_albedo = true
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(root, st.commit(), rm)
	# Glass curtain walls under the roof edge with mullions
	var gl := _glass(Color(0.30, 0.42, 0.46), 0.6)
	var mull := _mat(Color(0.2, 0.22, 0.24), 0.4, 0.6)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in range(4):
		var nseg := 24
		for k in range(nseg):
			var a0 := -1.0 + 2.0 * float(k) / float(nseg)
			var a1 := -1.0 + 2.0 * float(k + 1) / float(nseg)
			var s0 := Vector2(a0, -1.0) if e == 0 else (Vector2(a0, 1.0) if e == 1 else (Vector2(-1.0, a0) if e == 2 else Vector2(1.0, a0)))
			var s1 := Vector2(a1, -1.0) if e == 0 else (Vector2(a1, 1.0) if e == 1 else (Vector2(-1.0, a1) if e == 2 else Vector2(1.0, a1)))
			var b0 := C + U * (s0.x * hu) + V * (s0.y * hv)
			var b1 := C + U * (s1.x * hu) + V * (s1.y * hv)
			var t0 := float(roof_h.call(s0.x * hu / (hu + over), s0.y * hv / (hv + over))) - 1.2
			var t1 := float(roof_h.call(s1.x * hu / (hu + over), s1.y * hv / (hv + over))) - 1.2
			for v: Vector3 in [b0, b1, b1 + Vector3.UP * t1, b0, b1 + Vector3.UP * t1, b0 + Vector3.UP * t0]:
				wst.add_vertex(v)
			var mh := (t0 + t1) * 0.5
			_box(root, Vector3(0.3, mh, 0.3), (b0 + b1) * 0.5 + Vector3.UP * (mh * 0.5), mull)
	wst.generate_normals()
	_mi(root, wst.commit(), gl)
	# Inner drum (the arena bowl wall) seen through the glass
	_mi(root, _lathe([Vector2(minf(hu, hv) * 0.8, 0.0), Vector2(minf(hu, hv) * 0.8, 18.0)], 40), _mat(Color(0.32, 0.34, 0.36), 0.8, 0.1), C)
	_label(root, "CLIMATE PLEDGE ARENA", C - V * (hv + 0.3) + Vector3.UP * 7.0, -V, 2.4, Color(0.95, 0.95, 0.95), false)


# ---------------------------------------------------------------------------------------------
# MoPOP: crumpled metal blobs
# ---------------------------------------------------------------------------------------------
static func _blob_mesh(radii: Vector3, seed_v: float, ground_y: float = -1e9) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var segs := 24
	var pos := func(i: int, k: int) -> Vector3:
		var th := PI * float(i) / float(rings)
		var ph := TAU * float(k) / float(segs)
		var dir := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		var wob := 1.0 + 0.16 * sin(ph * 2.0 + seed_v) * sin(th * 3.0 + seed_v * 1.7) + 0.08 * sin(ph * 5.0 + th * 4.0 + seed_v)
		var p := Vector3(dir.x * radii.x, dir.y * radii.y, dir.z * radii.z) * wob
		p.y = maxf(p.y, maxf(-radii.y * 0.15, ground_y)) if ground_y < -1e8 else maxf(p.y, ground_y)
		return p
	for i in range(rings):
		for k in range(segs):
			var a: Vector3 = pos.call(i, k)
			var b: Vector3 = pos.call(i + 1, k)
			var cc: Vector3 = pos.call(i + 1, k + 1)
			var d: Vector3 = pos.call(i, k + 1)
			for v: Vector3 in [a, b, cc, a, cc, d]:
				st.set_uv(Vector2(float(k) / float(segs) * 6.0, float(i) / float(rings) * 4.0))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _mopop(parent: Node3D, b: Dictionary) -> void:
	var c := Vector3.ZERO
	var pts: Array = b["pts"]
	for p in pts:
		c += Vector3(float(p[0]), 0.0, float(p[1]))
	c /= float(pts.size())
	var root := Node3D.new()
	root.name = "MoPOP"
	root.position = c
	parent.add_child(root)
	# Panelled metal skins (stainless shingles) via a tiled texture
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var edge := (x % 16 == 0) or (y % 10 == 0)
			img.set_pixel(x, y, Color(0.82, 0.82, 0.82) if edge else Color(1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	# Weathered real-world finishes: oxblood red, dusky purple, brushed gold, matte stainless, pale sky blue
	var cols: Array[Color] = [Color(0.46, 0.17, 0.18), Color(0.38, 0.29, 0.44), Color(0.66, 0.56, 0.38), Color(0.70, 0.71, 0.72), Color(0.38, 0.50, 0.62), Color(0.60, 0.40, 0.42)]
	var blobs: Array = [
		[Vector3(-18, 7, -6), Vector3(17, 12, 14), 0],
		[Vector3(4, 9, -10), Vector3(15, 15, 12), 1],
		[Vector3(18, 6, 4), Vector3(14, 11, 13), 2],
		[Vector3(-4, 10, 10), Vector3(13, 17, 11), 3],
		[Vector3(-22, 4, 14), Vector3(10, 8, 9), 4],
		[Vector3(12, 7, 18), Vector3(11, 12, 9), 5],
	]
	for i in range(blobs.size()):
		var bl: Array = blobs[i]
		var m := _mat(cols[int(bl[2])], 0.42, 0.55)
		m.albedo_texture = tex
		m.uv1_scale = Vector3(2, 2, 1)
		_mi(root, _blob_mesh(bl[1], float(i) * 1.37, -(bl[0] as Vector3).y), m, bl[0])
	_label(root, "MoPOP", Vector3(0, 4.0, -24.0), Vector3(0, 0, -1), 2.6, Color(1, 1, 1), false)


# ---------------------------------------------------------------------------------------------
# Pacific Science Center arches
# ---------------------------------------------------------------------------------------------
static func _science_arches(parent: Node3D, c: Vector3) -> void:
	var root := Node3D.new()
	root.name = "PacificScienceArches"
	root.position = c
	parent.add_child(root)
	var white := _mat(Color(0.96, 0.96, 0.95), 0.35, 0.05)
	var water := _mat(Color(0.18, 0.36, 0.44), 0.05, 0.3)
	_box(root, Vector3(44, 0.5, 22), Vector3(0, 0.25, 0), _mat(Color(0.86, 0.86, 0.84), 0.8, 0.0))
	_box(root, Vector3(40, 0.08, 18), Vector3(0, 0.52, 0), water)
	var paths: Array = []
	var radii: Array = []
	for k in range(5):
		var ox := -16.0 + float(k) * 8.0
		var rot := deg_to_rad(-30.0 + float(k) * 15.0)
		var span := 9.0
		var hgt := 30.0 + float(k % 2) * 3.0
		for leg: float in [-1.0, 1.0]:
			var pts: Array = []
			var rr: Array = []
			for i in range(13):
				var t := float(i) / 12.0
				# Pointed (Gothic) arch: each leg is an arc that meets at the apex
				var x := leg * span * (1.0 - sin(t * PI * 0.5))
				var y := hgt * sin(t * PI * 0.5) * (0.82 + 0.18 * t)
				var lp := Vector3(x * cos(rot), y, x * sin(rot))
				pts.append(Vector3(ox, 0.5, 0) + lp)
				rr.append(lerpf(0.75, 0.35, t))
			paths.append(pts)
			radii.append(rr)
	_mi(root, _tube_mesh(paths, radii, 8), white)


# ---------------------------------------------------------------------------------------------
# International Fountain
# ---------------------------------------------------------------------------------------------
static func _international_fountain(parent: Node3D, c: Vector3, lights: Array) -> void:
	var root := Node3D.new()
	root.name = "InternationalFountain"
	root.position = c
	parent.add_child(root)
	var conc := _mat(Color(0.88, 0.87, 0.84), 0.8, 0.0)
	_mi(root, _lathe([Vector2(30.0, 0.05), Vector2(24.0, -0.6), Vector2(10.0, -2.2), Vector2(0.0, -2.4)], 64), conc)
	var dome := _mat(Color(0.82, 0.84, 0.86), 0.18, 0.95)
	_mi(root, _lathe([Vector2(4.6, -2.4), Vector2(4.4, -1.2), Vector2(3.6, 0.4), Vector2(2.2, 1.4), Vector2(0.0, 1.8)], 32), dome)
	var nozzle := SphereMesh.new()
	nozzle.radius = 0.16
	nozzle.height = 0.32
	var jet_mat := _glass(Color(0.85, 0.92, 1.0), 0.35)
	for k in range(24):
		var az := TAU * float(k) / 24.0
		var p := Vector3(cos(az) * 3.2, 0.6, sin(az) * 3.2)
		_mi(root, nozzle, dome, p)
		if k % 3 == 0:
			var jet := CylinderMesh.new()
			jet.top_radius = 0.05
			jet.bottom_radius = 0.18
			jet.height = 6.0 + float(k % 2) * 4.0
			var jm := _mi(root, jet, jet_mat, p + Vector3(cos(az) * 1.2, jet.height * 0.5, sin(az) * 1.2))
			jm.rotation = Vector3(sin(az) * 0.25, 0.0, -cos(az) * 0.25)
			jm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light(root, Vector3(0, 2.0, 0), Color(0.75, 0.9, 1.0), 18.0, lights)


# ---------------------------------------------------------------------------------------------
# Chihuly Garden and Glass – Glasshouse
# ---------------------------------------------------------------------------------------------
static func _chihuly_glasshouse(parent: Node3D, c: Vector3, lights: Array) -> void:
	var root := Node3D.new()
	root.name = "ChihulyGlasshouse"
	root.position = c + Vector3(-14.0, 0.0, 6.0)
	root.rotation.y = deg_to_rad(15.0)
	parent.add_child(root)
	var steel := _mat(Color(0.28, 0.29, 0.30), 0.4, 0.7)
	var gl := _glass(Color(0.75, 0.85, 0.88), 0.22)
	var L := 30.0
	var W := 13.0
	var H := 12.5
	# Ribs: vertical walls + arched roof, with glass skin
	var paths: Array = []
	var radii: Array = []
	for k in range(9):
		var z := -L * 0.5 + float(k) * L / 8.0
		var pts: Array = []
		var rr: Array = []
		for i in range(13):
			var t := float(i) / 12.0
			var ang := PI * t
			pts.append(Vector3(-cos(ang) * W * 0.5, 7.0 + sin(ang) * (H - 7.0), z))
			rr.append(0.12)
		pts.insert(0, Vector3(-W * 0.5, 0.0, z))
		rr.insert(0, 0.14)
		pts.append(Vector3(W * 0.5, 0.0, z))
		rr.append(0.14)
		paths.append(pts)
		radii.append(rr)
	_mi(root, _tube_mesh(paths, radii, 6), steel)
	var skin := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof: Array = [Vector2(-W * 0.5, 0.0)]
	for i in range(13):
		var ang := PI * float(i) / 12.0
		prof.append(Vector2(-cos(ang) * W * 0.5, 7.0 + sin(ang) * (H - 7.0)))
	prof.append(Vector2(W * 0.5, 0.0))
	for i in range(prof.size() - 1):
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for v: Vector3 in [Vector3(a.x, a.y, -L * 0.5), Vector3(b.x, b.y, -L * 0.5), Vector3(b.x, b.y, L * 0.5), Vector3(a.x, a.y, -L * 0.5), Vector3(b.x, b.y, L * 0.5), Vector3(a.x, a.y, L * 0.5)]:
			skin.add_vertex(v)
	skin.generate_normals()
	_mi(root, skin.commit(), gl)
	# Giant red / orange / amber glass sculpture suspended inside
	var cols: Array[Color] = [Color(0.95, 0.15, 0.08), Color(1.0, 0.45, 0.05), Color(1.0, 0.75, 0.15), Color(0.85, 0.08, 0.20)]
	var petal := SphereMesh.new()
	petal.radius = 0.5
	petal.height = 1.0
	for k in range(70):
		var a := float(k) * 2.39996
		var r := 1.2 + float(k % 7) * 0.55
		var y := 9.0 - float(k) * 0.06
		var pm := _emit(cols[k % cols.size()], 0.6)
		pm.roughness = 0.1
		var mi := _mi(root, petal, pm, Vector3(cos(a) * r, y, sin(a) * r * 2.2))
		mi.scale = Vector3(0.8, 0.5, 2.6)
		mi.rotation = Vector3(0.4 * sin(a), a, 0.3)
	_light(root, Vector3(0, 8.0, 0), Color(1.0, 0.55, 0.25), 20.0, lights)


# ---------------------------------------------------------------------------------------------
# Seattle Great Wheel (Pier 57)
# ---------------------------------------------------------------------------------------------
static func _great_wheel(parent: Node3D, c: Vector3, lights: Array) -> void:
	var root := Node3D.new()
	root.name = "SeattleGreatWheel"
	root.position = c + Vector3(0.0, 0.6, 0.0)
	# The wheel faces the city: its plane runs parallel to the Alaskan Way shoreline
	var to_city := Vector3(0.72, 0.0, -0.69).normalized()
	root.basis = Basis.looking_at(to_city, Vector3.UP)
	parent.add_child(root)
	var white := _mat(Color(0.95, 0.95, 0.95), 0.35, 0.35)
	var hub_h := 29.0
	var R := 24.0
	# A-frame legs on both sides of the wheel
	var legs: Array = []
	var lr: Array = []
	for side: float in [-1.6, 1.6]:
		for spread: float in [-13.0, 13.0]:
			legs.append([Vector3(spread, 0.0, side * 2.2), Vector3(0.0, hub_h, side)])
			lr.append([0.65, 0.4])
	_mi(root, _tube_mesh(legs, lr, 10), white)
	_box(root, Vector3(0.6, 0.6, 3.6), Vector3(0, hub_h, 0), white)
	var wheel: Node3D = (load("res://scripts/spin_node.gd") as GDScript).new()
	wheel.name = "WheelRotor"
	wheel.position = Vector3(0, hub_h, 0)
	root.add_child(wheel)
	for zz: float in [-0.9, 0.9]:
		var rim := TorusMesh.new()
		rim.inner_radius = R - 0.35
		rim.outer_radius = R + 0.35
		rim.rings = 96
		rim.ring_segments = 8
		var rmi := _mi(wheel, rim, white, Vector3(0, 0, zz))
		rmi.rotation_degrees = Vector3(90, 0, 0)
		var rim2 := TorusMesh.new()
		rim2.inner_radius = R - 3.2
		rim2.outer_radius = R - 2.7
		rim2.rings = 96
		rim2.ring_segments = 6
		var r2 := _mi(wheel, rim2, white, Vector3(0, 0, zz))
		r2.rotation_degrees = Vector3(90, 0, 0)
	var spokes: Array = []
	var sr: Array = []
	for k in range(42):
		var a := TAU * float(k) / 42.0
		for zz: float in [-0.9, 0.9]:
			spokes.append([Vector3(0, 0, zz * 2.0), Vector3(cos(a) * (R - 0.3), sin(a) * (R - 0.3), zz)])
			sr.append([0.07, 0.05])
	_mi(wheel, _tube_mesh(spokes, sr, 4), white)
	var cab_mat := _mat(Color(0.92, 0.93, 0.95), 0.3, 0.4)
	var cab_glass := _glass(Color(0.25, 0.35, 0.42), 0.7)
	var spin_script: Node3D = wheel
	for k in range(42):
		var a := TAU * float(k) / 42.0 + TAU / 84.0
		var holder := Node3D.new()
		holder.position = Vector3(cos(a) * (R + 0.4), sin(a) * (R + 0.4), 0)
		wheel.add_child(holder)
		_box(holder, Vector3(2.3, 2.4, 2.3), Vector3(0, -1.5, 0), cab_mat)
		_box(holder, Vector3(2.35, 1.3, 2.35), Vector3(0, -1.2, 0), cab_glass)
		(spin_script.get("upright") as Array).append(holder)
	_light(root, Vector3(0, hub_h, 3.0), Color(0.6, 0.75, 1.0), 40.0, lights)


# ---------------------------------------------------------------------------------------------
# Seattle Aquarium entrance sign (Pier 59)
# ---------------------------------------------------------------------------------------------
static func _aquarium_sign(parent: Node3D, c: Vector3) -> void:
	var root := Node3D.new()
	root.name = "SeattleAquariumSign"
	root.position = c + Vector3(24.0, 0.0, -10.0)
	parent.add_child(root)
	var face := Vector3(0.72, 0.0, -0.69).normalized() # toward Alaskan Way / the promenade
	var blue := _mat(Color(0.05, 0.32, 0.56), 0.4, 0.2)
	var wave := _mat(Color(0.20, 0.62, 0.78), 0.4, 0.2)
	var side := face.cross(Vector3.UP).normalized()
	for s: float in [-6.0, 6.0]:
		_box(root, Vector3(0.6, 7.5, 0.6), side * s + Vector3.UP * 3.75, blue)
	var beam := _box(root, Vector3(13.0, 1.6, 0.8), Vector3.UP * 7.4, blue)
	beam.basis = Basis.looking_at(-face, Vector3.UP)
	var wv := _box(root, Vector3(13.4, 0.5, 0.9), Vector3.UP * 6.4, wave)
	wv.basis = Basis.looking_at(-face, Vector3.UP)
	_label(root, "SEATTLE AQUARIUM", face * 0.45 + Vector3.UP * 7.45, face, 1.0, Color(1, 1, 1))


# ---------------------------------------------------------------------------------------------
# Pike Place Market: "PUBLIC MARKET CENTER" neon sign and clock (Pike St & Pike Pl)
# ---------------------------------------------------------------------------------------------
static func _pike_market_sign(parent: Node3D, c: Vector3, face_in: Vector3, roof_h: float, lights: Array) -> void:
	var root := Node3D.new()
	root.name = "PikePlaceMarketSign"
	root.position = c + Vector3(0.0, roof_h, 0.0)
	var face := face_in.normalized() # looking up Pike Street
	root.basis = Basis.looking_at(-face, Vector3.UP)
	parent.add_child(root)
	var steel := _mat(Color(0.15, 0.15, 0.16), 0.5, 0.6)
	var neon := _emit(Color(1.0, 0.12, 0.10), 2.6)
	# Support frame on the roof
	for x: float in [-6.5, -2.0, 2.0, 6.5]:
		_box(root, Vector3(0.18, 4.6, 0.18), Vector3(x, 2.3, 0.4), steel)
	_box(root, Vector3(14.0, 0.18, 0.18), Vector3(0, 4.5, 0.4), steel)
	_box(root, Vector3(14.0, 0.18, 0.18), Vector3(0, 2.4, 0.4), steel)
	var l1 := _label(root, "PUBLIC MARKET", Vector3(0, 3.6, 0.0), Vector3(0, 0, 1), 1.9, Color(1.0, 0.18, 0.12))
	l1.outline_size = 10
	l1.outline_modulate = Color(0.6, 0.02, 0.02)
	var l2 := _label(root, "CENTER", Vector3(-2.6, 1.3, 0.0), Vector3(0, 0, 1), 1.5, Color(1.0, 0.18, 0.12))
	l2.outline_size = 10
	l2.outline_modulate = Color(0.6, 0.02, 0.02)
	_label(root, "MEET THE PRODUCER", Vector3(1.0, 0.25, 0.0), Vector3(0, 0, 1), 0.55, Color(1.0, 0.85, 0.3))
	# Clock
	var clock := CylinderMesh.new()
	clock.top_radius = 1.25
	clock.bottom_radius = 1.25
	clock.height = 0.3
	var cm := _mi(root, clock, _emit(Color(0.98, 0.96, 0.88), 0.6), Vector3(4.0, 1.3, 0.1))
	cm.rotation_degrees = Vector3(90, 0, 0)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.2
	ring.outer_radius = 1.38
	var rmi := _mi(root, ring, neon, Vector3(4.0, 1.3, 0.12))
	rmi.rotation_degrees = Vector3(90, 0, 0)
	_box(root, Vector3(0.08, 0.85, 0.05), Vector3(4.0, 1.62, 0.28), steel)
	var mh := _box(root, Vector3(0.06, 1.05, 0.05), Vector3(4.3, 1.1, 0.29), steel)
	mh.rotation_degrees = Vector3(0, 0, -55)
	_light(root, Vector3(0, 2.5, 2.0), Color(1.0, 0.2, 0.15), 16.0, lights)


# ---------------------------------------------------------------------------------------------
# Calder "Eagle" – Olympic Sculpture Park
# ---------------------------------------------------------------------------------------------
static func _calder_eagle(parent: Node3D, c: Vector3) -> void:
	var root := Node3D.new()
	root.name = "CalderEagle"
	root.position = c
	parent.add_child(root)
	var red := _mat(Color(0.80, 0.12, 0.06), 0.45, 0.35)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Stabile: two splayed legs + a tall swept "wing" of folded steel plates
	var plates: Array = [
		[Vector3(-6, 0, -2), Vector3(-2, 0, 1), Vector3(-1, 8, 0)],
		[Vector3(5, 0, -3), Vector3(2, 0, 2), Vector3(1, 8.5, 0)],
		[Vector3(-1, 8, 0), Vector3(1, 8.5, 0), Vector3(-3, 13.5, 1.5)],
		[Vector3(1, 8.5, 0), Vector3(4, 11, -1), Vector3(-3, 13.5, 1.5)],
		[Vector3(-2, 0, 1), Vector3(2, 0, 2), Vector3(0, 5, 1)],
	]
	for pl: Array in plates:
		for v in pl:
			st.add_vertex(v)
		for v in [pl[0], pl[2], pl[1]]:
			st.add_vertex(v)
	st.generate_normals()
	_mi(root, st.commit(), red)


# ---------------------------------------------------------------------------------------------
# Seattle Center monorail terminal
# ---------------------------------------------------------------------------------------------
static func _monorail_terminal(parent: Node3D, mono: Dictionary) -> void:
	var path: Array = mono["path"]
	if path.size() < 2:
		return
	var p0 := Vector3(float(path[0][0]), float(path[0][1]), float(path[0][2]))
	var p1 := Vector3(float(path[1][0]), float(path[1][1]), float(path[1][2]))
	var fwd := (p1 - p0)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var root := Node3D.new()
	root.name = "SeattleCenterMonorailTerminal"
	root.position = Vector3(p0.x, 0.0, p0.z) + fwd * 20.0
	root.basis = Basis.looking_at(fwd, Vector3.UP)
	parent.add_child(root)
	var conc := _mat(Color(0.74, 0.73, 0.70), 0.85, 0.0)
	var canopy := _mat(Color(0.92, 0.92, 0.90), 0.5, 0.2)
	var steel := _mat(Color(0.3, 0.32, 0.34), 0.4, 0.6)
	for s: float in [-3.4, 3.4]:
		_box(root, Vector3(3.2, 0.5, 40.0), Vector3(s, 6.6, 0), conc)
		for z in range(-18, 19, 6):
			_box(root, Vector3(0.5, 6.4, 0.5), Vector3(s * 1.25, 3.2, float(z)), conc)
			_box(root, Vector3(0.18, 4.0, 0.18), Vector3(s * 1.4, 8.9, float(z)), steel)
		_box(root, Vector3(0.06, 1.05, 40.0), Vector3(s * 1.45, 7.4, 0), _glass(Color(0.7, 0.8, 0.85), 0.3))
	_box(root, Vector3(11.5, 0.35, 42.0), Vector3(0, 11.0, 0), canopy)
	_box(root, Vector3(2.6, 6.6, 3.0), Vector3(-6.6, 3.3, -16.0), conc)
	_label(root, "SEATTLE CENTER MONORAIL", Vector3(0, 11.6, -21.2), Vector3(0, 0, -1), 0.9, Color(0.12, 0.3, 0.6), false)


# ---------------------------------------------------------------------------------------------
# Piers: timber decks on piles over the water, with edge beams and railings
# ---------------------------------------------------------------------------------------------
static func _piers(parent: Node3D, piers: Array) -> void:
	if piers.is_empty():
		return
	var deck_y := 0.62
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge_st := SurfaceTool.new()
	edge_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pile_tfs: Array[Transform3D] = []
	for pr: Dictionary in piers:
		var poly := PackedVector2Array()
		for p in pr["pts"]:
			var v := Vector2(float(p[0]), float(p[1]))
			if poly.is_empty() or poly[poly.size() - 1].distance_to(v) > 0.1:
				poly.append(v)
		if poly.size() >= 3 and poly[0].distance_to(poly[poly.size() - 1]) < 0.1:
			poly.resize(poly.size() - 1)
		if poly.size() < 3:
			continue
		var idx := Geometry2D.triangulate_polygon(poly)
		for i in range(0, idx.size(), 3):
			for k: int in [0, 2, 1]:
				var p := poly[idx[i + k]]
				st.set_normal(Vector3.UP)
				st.set_uv(p * 0.25)
				st.add_vertex(Vector3(p.x, deck_y, p.y))
		for i in range(poly.size()):
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			for v: Vector3 in [Vector3(a.x, deck_y, a.y), Vector3(b.x, deck_y, b.y), Vector3(b.x, -1.2, b.y), Vector3(a.x, deck_y, a.y), Vector3(b.x, -1.2, b.y), Vector3(a.x, -1.2, a.y)]:
				edge_st.add_vertex(v)
			var seg := a.distance_to(b)
			var nps := int(seg / 4.0)
			for k in range(nps):
				var q := a.lerp(b, (float(k) + 0.5) / float(maxi(1, nps)))
				pile_tfs.append(Transform3D(Basis.IDENTITY, Vector3(q.x, -0.6, q.y)))
	var deck_mi := MeshInstance3D.new()
	deck_mi.name = "PierDecks"
	deck_mi.mesh = st.commit()
	deck_mi.material_override = _plank_mat()
	deck_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(deck_mi)
	edge_st.generate_normals()
	var em := _mat(Color(0.30, 0.25, 0.20), 0.9, 0.0)
	em.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edge_mi := _mi(parent, edge_st.commit(), em)
	edge_mi.name = "PierEdgeBeams"
	if not pile_tfs.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.22
		cyl.bottom_radius = 0.25
		cyl.height = 3.2
		cyl.radial_segments = 8
		mm.mesh = cyl
		mm.instance_count = pile_tfs.size()
		for i in range(pile_tfs.size()):
			mm.set_instance_transform(i, pile_tfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "PierPiles"
		mmi.multimesh = mm
		mmi.material_override = _mat(Color(0.22, 0.18, 0.14), 0.95, 0.0)
		parent.add_child(mmi)


static func _plank_mat() -> StandardMaterial3D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 57
	for y in range(128):
		var board := y / 16
		var tone := 0.85 + 0.15 * float((board * 37) % 7) / 7.0
		for x in range(128):
			var seam := (y % 16 == 0) or ((x + board * 41) % 96 == 0)
			var c := Color(0.48, 0.40, 0.31) * tone
			c = c.darkened(rng.randf() * 0.08)
			if seam:
				c = Color(0.18, 0.15, 0.12)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.88
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m



# ---------------------------------------------------------------------------------------------
# Colman Dock – Seattle Ferry Terminal (Pier 52) with two docked Washington State Ferries
# ---------------------------------------------------------------------------------------------
const DOCK_EDGE_X := -122.0 # dock face (water to the west, -X)


static func _colman_dock(parent: Node3D, lights: Array) -> void:
	var root := Node3D.new()
	root.name = "ColmanDock"
	parent.add_child(root)
	var glass := _glass(Color(0.42, 0.55, 0.60), 0.55)
	var steel := _mat(Color(0.30, 0.32, 0.34), 0.4, 0.6)
	var roof := _mat(Color(0.82, 0.83, 0.84), 0.5, 0.3)
	var conc := _mat(Color(0.70, 0.69, 0.66), 0.85, 0.0)
	var timber := _mat(Color(0.30, 0.25, 0.20), 0.9, 0.0)
	# Terminal building: two-storey glass hall with a long sloping roof
	var t_c := Vector3(-62.0, 0.0, 1748.0)
	_box(root, Vector3(44.0, 0.4, 72.0), t_c + Vector3(0, 0.2, 0), conc)
	_box(root, Vector3(40.0, 10.0, 68.0), t_c + Vector3(0, 5.2, 0), glass)
	for k in range(15):
		var z := -34.0 + float(k) * (68.0 / 14.0)
		for sx: float in [-20.0, 20.0]:
			_box(root, Vector3(0.3, 10.0, 0.3), t_c + Vector3(sx, 5.2, z), steel)
	_box(root, Vector3(40.4, 0.3, 68.4), t_c + Vector3(0, 5.2, 0), steel)
	var rf := _box(root, Vector3(48.0, 0.6, 76.0), t_c + Vector3(0, 11.4, 0), roof)
	rf.rotation_degrees = Vector3(0, 0, 4.0)
	_label(root, "SEATTLE FERRY TERMINAL", t_c + Vector3(20.6, 8.6, 0), Vector3(1, 0, 0), 2.2, Color(0.06, 0.32, 0.22), false)
	_label(root, "COLMAN DOCK", t_c + Vector3(20.6, 6.6, 0), Vector3(1, 0, 0), 1.4, Color(0.15, 0.15, 0.16), false)
	_light(root, t_c + Vector3(0, 8.0, 0), Color(1.0, 0.92, 0.8), 30.0, lights)
	# Dock apron over the water between terminal and slips
	_box(root, Vector3(10.0, 0.6, 120.0), Vector3(DOCK_EDGE_X + 2.0, 0.35, 1748.0), conc)
	var slips: Array[float] = [1712.0, 1784.0]
	var names: Array[String] = ["WENATCHEE", "TACOMA"]
	for i in range(slips.size()):
		var z := slips[i]
		# Transfer span (vehicle ramp) and overhead passenger bridge to the upper deck
		var ramp := _box(root, Vector3(14.0, 0.5, 11.0), Vector3(DOCK_EDGE_X - 6.0, 1.6, z), steel)
		ramp.rotation_degrees = Vector3(0, 0, -6.0)
		for sz: float in [-6.5, 6.5]:
			_box(root, Vector3(2.0, 9.0, 2.0), Vector3(DOCK_EDGE_X - 11.0, 3.0, z + sz), conc)
		_box(root, Vector3(44.0, 3.2, 3.6), Vector3(-104.0, 10.4, z - 3.0), glass)
		_box(root, Vector3(44.2, 0.3, 3.8), Vector3(-104.0, 12.1, z - 3.0), roof)
		for bx: float in [-118.0, -96.0]:
			_box(root, Vector3(0.6, 8.8, 0.6), Vector3(bx, 4.4, z - 3.0), steel)
		# Timber wing walls + mooring dolphins guiding the ferry into the slip
		for side: float in [-1.0, 1.0]:
			for k in range(6):
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.35
				cyl.bottom_radius = 0.38
				cyl.height = 8.0
				_mi(root, cyl, timber, Vector3(DOCK_EDGE_X - 18.0 - float(k) * 9.0, 1.0, z + side * (15.5 + float(k) * 0.9)))
			_box(root, Vector3(48.0, 1.2, 0.8), Vector3(DOCK_EDGE_X - 40.0, 3.6, z + side * 17.5), timber)
		_wsf_ferry(root, Vector3(DOCK_EDGE_X - 14.0 - 70.0, 0.0, z), names[i], lights)


# Washington State Ferries Jumbo-class style double-ended ferry, ~140m x 27m, lying along X.
static func _wsf_ferry(parent: Node3D, c: Vector3, ship_name: String, lights: Array) -> void:
	var root := Node3D.new()
	root.name = "Ferry_" + ship_name
	root.position = c
	parent.add_child(root)
	var white := _mat(Color(0.94, 0.94, 0.93), 0.45, 0.1)
	var green := _mat(Color(0.05, 0.36, 0.24), 0.45, 0.1)
	var dark := _mat(Color(0.10, 0.12, 0.13), 0.5, 0.1)
	var win := _mat(Color(0.12, 0.17, 0.20), 0.15, 0.4)
	var L := 140.0
	var W := 27.0
	# Hull: rounded double-ended deck outline, green boot-top band + white topsides
	var outline := PackedVector2Array()
	for k in range(25):
		var a := -PI * 0.5 + PI * float(k) / 24.0
		outline.append(Vector2(L * 0.5 - W * 0.5 + cos(a) * W * 0.5, sin(a) * W * 0.5))
	for k in range(25):
		var a := PI * 0.5 + PI * float(k) / 24.0
		outline.append(Vector2(-L * 0.5 + W * 0.5 + cos(a) * W * 0.5, sin(a) * W * 0.5))
	_mi(root, _prism(outline, -2.0, 1.2), green)
	_mi(root, _prism(outline, 1.2, 4.0), white)
	# Open car deck (dark interior with white posts) and the white passenger deck above
	var inner := PackedVector2Array()
	for p in outline:
		inner.append(p * Vector2(0.97, 0.9))
	_mi(root, _prism(inner, 4.0, 8.6), dark)
	for k in range(15):
		var x := -L * 0.42 + float(k) * L * 0.06
		for sz: float in [-1.0, 1.0]:
			_box(root, Vector3(0.6, 4.6, 0.4), Vector3(x, 6.3, sz * W * 0.43), white)
	_mi(root, _prism(outline, 8.6, 9.4), white)
	var pass_out := PackedVector2Array()
	for p in outline:
		pass_out.append(p * Vector2(0.86, 0.92))
	_mi(root, _prism(pass_out, 9.4, 13.6), white)
	for sz: float in [-1.0, 1.0]:
		_box(root, Vector3(L * 0.72, 1.7, 0.2), Vector3(0, 11.6, sz * W * 0.46), win)
		_box(root, Vector3(L * 0.86, 0.5, 0.15), Vector3(0, 2.6, sz * (W * 0.5 + 0.02)), green)
		_label(root, "WASHINGTON STATE FERRIES", Vector3(0, 6.0, sz * (W * 0.5 + 0.08)), Vector3(0, 0, sz), 2.0, Color(0.05, 0.36, 0.24), false)
	# Sun deck, double-ended pilothouses, twin stacks and masts
	var sun := PackedVector2Array()
	for p in outline:
		sun.append(p * Vector2(0.62, 0.8))
	_mi(root, _prism(sun, 13.6, 14.2), white)
	for ex: float in [-1.0, 1.0]:
		_box(root, Vector3(7.0, 4.0, 15.0), Vector3(ex * L * 0.33, 16.2, 0), white)
		_box(root, Vector3(0.2, 1.6, 14.2), Vector3(ex * (L * 0.33 + 3.55), 16.6, 0), win)
		_label(root, ship_name, Vector3(ex * (L * 0.33 + 3.62), 14.9, 0), Vector3(ex, 0, 0), 1.1, Color(0.05, 0.36, 0.24), false)
		var stack := CylinderMesh.new()
		stack.top_radius = 2.2
		stack.bottom_radius = 2.5
		stack.height = 8.0
		var sm := _mi(root, stack, white, Vector3(ex * 18.0, 18.2, 0))
		sm.scale = Vector3(1.6, 1.0, 1.0)
		var band := CylinderMesh.new()
		band.top_radius = 2.25
		band.bottom_radius = 2.25
		band.height = 1.4
		var bm := _mi(root, band, green, Vector3(ex * 18.0, 20.6, 0))
		bm.scale = Vector3(1.62, 1.0, 1.02)
		var top := CylinderMesh.new()
		top.top_radius = 2.2
		top.bottom_radius = 2.2
		top.height = 0.6
		var tm := _mi(root, top, dark, Vector3(ex * 18.0, 22.4, 0))
		tm.scale = Vector3(1.6, 1.0, 1.0)
		_box(root, Vector3(0.3, 7.0, 0.3), Vector3(ex * L * 0.33, 21.7, 0), white)
	_light(root, Vector3(0, 12.0, 0), Color(1.0, 0.93, 0.82), 40.0, lights)


# Vertical prism of a 2D outline (x, z) between y0 and y1, with top cap
static func _prism(outline: PackedVector2Array, y0: float, y1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := outline.size()
	for i in range(n):
		var a := outline[i]
		var b := outline[(i + 1) % n]
		for v: Vector3 in [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]:
			st.add_vertex(v)
	var idx := Geometry2D.triangulate_polygon(outline)
	for i in range(0, idx.size(), 3):
		for k: int in [0, 1, 2]:
			var p := outline[idx[i + k]]
			st.add_vertex(Vector3(p.x, y1, p.y))
	st.generate_normals()
	var m := st.commit()
	return m
