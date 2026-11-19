class_name LandmarkFacades
extends RefCounted

# Real-world looks for named downtown Seattle buildings (OSM name -> "lm" key, see tools/osm_storefronts.py)
# and named plazas / parks. Colours and massing follow the real buildings:
#   Nordstrom flagship (1918 Frederick & Nelson): cream terracotta, two-storey display windows,
#     bronze entrance canopies, raised "NORDSTROM" letters.
#   Westlake Center (1988): warm granite + green glass, gabled glass entrance atrium on Pine St.
#   Pacific Place (1998): buff precast stone, full-height glass corner atrium at 6th & Pine.
#   Terracotta-era towers (Times Square, Securities, Medical Dental, Joshua Green, Coliseum...):
#     smooth cream / buff ashlar facades instead of generic brick.
#   Westlake Park: Salish basket-weave granite paving + Halprin water-wall arch, planters, trees.
#   McGraw Square: granite plaza with the John McGraw bronze statue on its pedestal.

# lm key -> [style, base colour, smooth ashlar?, override height (0 = keep)]
const OVERRIDES := {
	"nordstrom": [1, Color(0.87, 0.84, 0.76), true, 41.0],
	"westlake_mall": [2, Color(0.70, 0.62, 0.58), false, 24.0],
	"pacific_place": [2, Color(0.80, 0.76, 0.68), false, 26.0],
	"times_square": [1, Color(0.86, 0.83, 0.74), true, 0.0],
	"securities": [1, Color(0.84, 0.80, 0.70), true, 0.0],
	"medical_dental": [1, Color(0.84, 0.81, 0.72), true, 0.0],
	"joshua_green": [1, Color(0.88, 0.86, 0.80), true, 0.0],
	"coliseum": [1, Color(0.90, 0.87, 0.78), true, 0.0],
	"fourth_pike": [1, Color(0.80, 0.74, 0.62), true, 0.0],
	"terminal_sales": [1, Color(0.62, 0.40, 0.30), false, 0.0],
	"great_northern": [1, Color(0.58, 0.34, 0.26), false, 0.0],
	"wac": [1, Color(0.74, 0.62, 0.48), false, 0.0],
	"sixth_pine": [1, Color(0.76, 0.70, 0.60), true, 0.0],
	"century_square": [2, Color(0.80, 0.64, 0.58), false, 117.0],
	"amazon_meeting": [2, Color(0.30, 0.38, 0.40), false, 0.0],
	"amazon_day1": [0, Color(0.55, 0.64, 0.70), false, 0.0],
	"amazon_doppler": [0, Color(0.50, 0.60, 0.66), false, 0.0],
	"amazon_reinvent": [0, Color(0.58, 0.66, 0.72), false, 0.0],
	"amazon_blackfoot": [0, Color(0.48, 0.56, 0.62), false, 0.0],
	"church": [1, Color(0.62, 0.38, 0.30), false, 0.0],
}

const ASHLAR_SEED := 62 # building shader: seeds >= 60 draw smooth cut-stone instead of brick


static func override_for(b: Dictionary) -> Dictionary:
	var lm := str(b.get("lm", ""))
	if OVERRIDES.has(lm):
		var o: Array = OVERRIDES[lm]
		return {"style": int(o[0]), "color": o[1], "ashlar": bool(o[2]), "h": float(o[3])}
	var col_s := str(b.get("colour", ""))
	if col_s.begins_with("#") and col_s.length() == 7:
		return {"style": -1, "color": Color.html(col_s), "ashlar": false, "h": 0.0}
	return {}


static func build_details(parent: Node3D, buildings: Array, roads: Array) -> void:
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var labels := Node3D.new()
	labels.name = "LandmarkLettering"
	parent.add_child(labels)
	var any := false
	for b: Dictionary in buildings:
		var lm := str(b.get("lm", ""))
		if lm == "":
			continue
		var poly := _poly(b)
		if poly.size() < 3:
			continue
		var h := float(b.get("h", 12.0))
		var o: Dictionary = override_for(b)
		if not o.is_empty() and float(o["h"]) > 0.0:
			h = float(o["h"])
		var street := _street_edges(poly, roads)
		match lm:
			"nordstrom":
				_nordstrom(fst, gst, labels, street, h)
				any = true
			"westlake_mall":
				_westlake_mall(fst, gst, labels, street, h)
				any = true
			"pacific_place":
				_pacific_place(fst, gst, labels, poly, street, h)
				any = true
			"times_square", "coliseum", "joshua_green", "medical_dental", "securities":
				_terracotta_details(fst, street, h)
				any = true
		if TOWER_LOOKS.has(lm):
			_tower_overlay(fst, poly, h, lm)
			any = true
	if not any:
		return
	var f_mi := MeshInstance3D.new()
	f_mi.name = "LandmarkFacadeDetails"
	f_mi.mesh = fst.commit()
	var f_mat := StandardMaterial3D.new()
	f_mat.vertex_color_use_as_albedo = true
	f_mat.roughness = 0.45
	f_mat.metallic = 0.35
	f_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	f_mi.material_override = f_mat
	parent.add_child(f_mi)
	var g_mi := MeshInstance3D.new()
	g_mi.name = "LandmarkGlazing"
	g_mi.mesh = gst.commit()
	var g_mat := StandardMaterial3D.new()
	g_mat.albedo_color = Color(0.30, 0.42, 0.44, 0.55)
	g_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g_mat.roughness = 0.04
	g_mat.metallic = 0.6
	g_mat.metallic_specular = 0.9
	g_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	g_mi.material_override = g_mat
	g_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(g_mi)


# ---------------------------------------------------------------------------------------------
static func _poly(b: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in b.get("pts", []):
		var v := Vector2(float(p[0]), float(p[1]))
		if pts.is_empty() or pts[pts.size() - 1].distance_to(v) > 0.08:
			pts.append(v)
	if pts.size() >= 3 and pts[0].distance_to(pts[pts.size() - 1]) <= 0.08:
		pts.resize(pts.size() - 1)
	if pts.size() >= 3 and Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	return pts


# Street-facing edges: [{o: Vector3, u: Vector3, n: Vector3, w: float}], longest first
static func _street_edges(poly: PackedVector2Array, roads: Array) -> Array:
	var out: Array = []
	for i in range(poly.size()):
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var el := a.distance_to(c)
		if el < 8.0:
			continue
		var d2 := (c - a) / el
		var n2 := Vector2(-d2.y, d2.x)
		var mid := (a + c) * 0.5
		if Geometry2D.is_point_in_polygon(mid + n2 * 0.5, poly):
			n2 = -n2
		var dm := _road_dist(mid, roads)
		var do_ := _road_dist(mid + n2 * 3.0, roads)
		if dm < 16.0 and do_ < dm:
			out.append({"o": Vector3(a.x, 0.0, a.y), "u": Vector3(d2.x, 0.0, d2.y), "n": Vector3(n2.x, 0.0, n2.y), "w": el})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["w"]) > float(y["w"]))
	return out


static func _road_dist(p: Vector2, roads: Array) -> float:
	var best := 1e9
	for r: Dictionary in roads:
		var pts: Array = r["pts"]
		var hw := float(r.get("width", 12.0)) * 0.5
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			if absf(a.x - p.x) > 120.0 and absf(b.x - p.x) > 120.0:
				continue
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			best = minf(best, p.distance_to(q) - hw)
	return best


static func _ctx(st: SurfaceTool, e: Dictionary) -> Dictionary:
	return {"o": e["o"], "u": e["u"], "n": e["n"], "st": st}


static func _letters(labels: Node3D, txt: String, pos: Vector3, n: Vector3, height: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 96
	l.outline_size = 0
	l.modulate = col
	l.shaded = true
	l.double_sided = false
	l.pixel_size = height / 96.0
	l.transform = Transform3D(StorefrontBuilder._face_basis(n), pos)
	l.visibility_range_end = 600.0
	labels.add_child(l)


# Two-storey retail display bays with bronze frames along a facade edge
static func _display_bays(fst: SurfaceTool, gst: SurfaceTool, e: Dictionary, u0: float, u1: float, top: float, frame_c: Color, accent: Color) -> void:
	var ctx := _ctx(fst, e)
	var n_b := maxi(1, int(round((u1 - u0) / 6.5)))
	var bw := (u1 - u0) / float(n_b)
	var col := Color(accent.r, accent.g, accent.b, 1.0 / 255.0)
	for k in range(n_b):
		var a := u0 + float(k) * bw
		var b := a + bw
		StorefrontBuilder._box(ctx, a, a + 0.55, 0.0, top + 0.3, 0.0, 0.42, frame_c.lightened(0.25)) # stone pier
		StorefrontBuilder._box(ctx, a + 0.55, b, 0.0, 0.55, 0.0, 0.22, Color(0.22, 0.22, 0.22)) # granite base
		StorefrontBuilder._glass(gst, e["o"], e["u"], e["n"], a + 0.55, b, 0.55, top, 0.12, col)
		StorefrontBuilder._box(ctx, a + 0.55, b, top - 0.05, top + 0.3, 0.0, 0.20, frame_c)
		StorefrontBuilder._box(ctx, a + 0.55, b, 3.2, 3.3, 0.0, 0.16, frame_c)
		var mid := (a + 0.55 + b) * 0.5
		StorefrontBuilder._box(ctx, mid - 0.04, mid + 0.04, 0.55, top, 0.0, 0.16, frame_c)
	StorefrontBuilder._box(ctx, u1 - 0.55, u1, 0.0, top + 0.3, 0.0, 0.42, frame_c.lightened(0.25))


static func _nordstrom(fst: SurfaceTool, gst: SurfaceTool, labels: Node3D, street: Array, h: float) -> void:
	var bronze := Color(0.22, 0.17, 0.12)
	for i in range(mini(3, street.size())):
		var e: Dictionary = street[i]
		var w := float(e["w"])
		var o: Vector3 = e["o"]
		var U: Vector3 = e["u"]
		var N: Vector3 = e["n"]
		var ctx := _ctx(fst, e)
		_display_bays(fst, gst, e, 1.0, w - 1.0, 6.4, bronze, Color(0.75, 0.70, 0.62))
		# Bronze-and-glass entrance canopy over the middle of the facade
		var c0 := w * 0.35
		var c1 := w * 0.65
		StorefrontBuilder._box(ctx, c0, c1, 6.9, 7.25, 0.0, 2.6, bronze)
		StorefrontBuilder._box(ctx, c0, c1, 7.25, 7.32, 0.1, 2.5, Color(0.55, 0.50, 0.42))
		for tu: float in [c0 + 0.6, c1 - 0.6]:
			StorefrontBuilder._box(ctx, tu - 0.04, tu + 0.04, 7.3, 10.2, 0.0, 0.08, bronze)
		# Raised serif "NORDSTROM" letters above the canopy
		_letters(labels, "NORDSTROM", o + U * (w * 0.5) + N * 0.32 + Vector3.UP * 8.7, N, 1.5, Color(0.10, 0.10, 0.10))
		# Upper terracotta: attic arcade band + deep cornice
		StorefrontBuilder._box(ctx, 0.0, w, h - 4.4, h - 4.1, 0.0, 0.45, Color(0.92, 0.90, 0.84))
		var n_arch := maxi(2, int(w / 4.2))
		for k in range(n_arch + 1):
			var au := lerpf(0.4, w - 0.4, float(k) / float(n_arch))
			StorefrontBuilder._box(ctx, au - 0.28, au + 0.28, h - 4.1, h - 0.6, 0.0, 0.38, Color(0.90, 0.88, 0.80))
		StorefrontBuilder._box(ctx, 0.0, w, 7.6, 8.0, 0.0, 0.40, Color(0.90, 0.88, 0.82))


static func _westlake_mall(fst: SurfaceTool, gst: SurfaceTool, labels: Node3D, street: Array, h: float) -> void:
	if street.is_empty():
		return
	var granite := Color(0.62, 0.54, 0.50)
	var green_steel := Color(0.16, 0.30, 0.26)
	# Pick the Pine Street (south-facing, +z) frontage for the main gabled glass atrium
	var main := 0
	for i in range(street.size()):
		if (street[i]["n"] as Vector3).z > 0.6:
			main = i
			break
	for i in range(mini(3, street.size())):
		var e: Dictionary = street[i]
		var w := float(e["w"])
		var ctx := _ctx(fst, e)
		_display_bays(fst, gst, e, 0.8, w - 0.8, 5.0, green_steel, Color(0.70, 0.62, 0.56))
		# Polished granite banding and green-glass ribbon windows on the upper floors
		for fy: float in [9.5, 14.0, 18.5]:
			StorefrontBuilder._box(ctx, 0.3, w - 0.3, fy, fy + 0.5, 0.0, 0.25, granite)
			StorefrontBuilder._glass(gst, e["o"], e["u"], e["n"], 0.5, w - 0.5, fy + 0.5, fy + 2.9, 0.08, Color(0.2, 0.4, 0.36, 2.0 / 255.0))
	var e: Dictionary = street[main]
	var w := float(e["w"])
	var o: Vector3 = e["o"]
	var U: Vector3 = e["u"]
	var N: Vector3 = e["n"]
	var ctx := _ctx(fst, e)
	var aw := minf(16.0, w * 0.45)
	var a0 := w * 0.5 - aw * 0.5
	var a1 := w * 0.5 + aw * 0.5
	var top := h - 2.0
	# Projecting glass atrium box + gable
	for k in range(7):
		var mu := lerpf(a0, a1, float(k) / 6.0)
		StorefrontBuilder._box(ctx, mu - 0.09, mu + 0.09, 0.0, top, 1.6, 1.8, green_steel)
	for yk in range(1, 6):
		StorefrontBuilder._box(ctx, a0, a1, float(yk) * top / 6.0, float(yk) * top / 6.0 + 0.12, 1.6, 1.8, green_steel)
	StorefrontBuilder._glass(gst, o, U, N, a0, a1, 0.0, top, 1.7, Color(0.3, 0.5, 0.45, 2.0 / 255.0))
	for sd: float in [0.0, 1.0]:
		var su := a0 if sd == 0.0 else a1
		StorefrontBuilder._glass(gst, o + N * 0.0, N, -U if sd == 0.0 else U, 0.0, 1.7, 0.0, top, -su if sd == 0.0 else su, Color(0.3, 0.5, 0.45, 2.0 / 255.0))
	var g0 := o + U * a0 + N * 1.7 + Vector3.UP * top
	var g1 := o + U * a1 + N * 1.7 + Vector3.UP * top
	var gp := o + U * (w * 0.5) + N * 1.7 + Vector3.UP * (top + aw * 0.32)
	StorefrontBuilder._tri(fst, g0, g1, gp, Color(0.22, 0.38, 0.34))
	StorefrontBuilder._box(ctx, a0 - 0.3, a1 + 0.3, top - 0.1, top + 0.25, 0.0, 2.1, green_steel)
	_letters(labels, "WESTLAKE CENTER", o + U * (w * 0.5) + N * 1.95 + Vector3.UP * 6.3, N, 0.9, Color(0.92, 0.86, 0.62))
	# Entrance canopy
	StorefrontBuilder._box(ctx, a0 + 2.0, a1 - 2.0, 3.6, 3.85, 0.0, 4.0, green_steel)


static func _pacific_place(fst: SurfaceTool, gst: SurfaceTool, labels: Node3D, poly: PackedVector2Array, street: Array, h: float) -> void:
	var stone := Color(0.84, 0.80, 0.72)
	var steel := Color(0.70, 0.72, 0.74)
	for i in range(mini(3, street.size())):
		var e: Dictionary = street[i]
		var w := float(e["w"])
		var ctx := _ctx(fst, e)
		_display_bays(fst, gst, e, 0.8, w - 0.8, 5.2, Color(0.30, 0.31, 0.33), Color(0.78, 0.72, 0.62))
		for fy: float in [10.0, 15.5, 21.0]:
			StorefrontBuilder._box(ctx, 0.0, w, fy, fy + 0.4, 0.0, 0.3, stone.lightened(0.08))
	# Glass corner atrium at the south-east corner (6th Ave & Pine St)
	var ci := 0
	for i in range(poly.size()):
		if poly[i].y + poly[i].x * 0.3 > poly[ci].y + poly[ci].x * 0.3:
			ci = i
	var cp := poly[ci]
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= float(poly.size())
	var inward := (cen - cp).normalized()
	var ac := cp + inward * 7.0
	var r := 9.0
	var top := h + 5.0
	var segs := 10
	var outward_ang := atan2(-inward.y, -inward.x)
	for k in range(segs):
		var t0 := outward_ang - PI * 0.5 + PI * float(k) / float(segs)
		var t1 := outward_ang - PI * 0.5 + PI * float(k + 1) / float(segs)
		var p0 := Vector3(ac.x + cos(t0) * r, 0.0, ac.y + sin(t0) * r)
		var p1 := Vector3(ac.x + cos(t1) * r, 0.0, ac.y + sin(t1) * r)
		var u := (p1 - p0)
		var seg_w := u.length()
		var nrm := Vector3(cos((t0 + t1) * 0.5), 0.0, sin((t0 + t1) * 0.5))
		StorefrontBuilder._glass(gst, p0, u / seg_w, nrm, 0.0, seg_w, 0.0, top, 0.0, Color(0.6, 0.6, 0.55, 1.0 / 255.0))
		var e2 := {"o": p0, "u": u / seg_w, "n": nrm, "st": fst}
		StorefrontBuilder._box(e2, -0.08, 0.08, 0.0, top + 0.3, -0.05, 0.18, steel)
		for yk in range(1, 8):
			StorefrontBuilder._box(e2, 0.0, seg_w, float(yk) * top / 8.0, float(yk) * top / 8.0 + 0.08, -0.02, 0.12, steel)
		StorefrontBuilder._tri(fst, Vector3(ac.x, top + 1.2, ac.y), p0 + Vector3.UP * top, p1 + Vector3.UP * top, Color(0.62, 0.66, 0.68))
	var front := Vector3(-inward.x, 0.0, -inward.y)
	_letters(labels, "PACIFIC PLACE", Vector3(ac.x, 0.0, ac.y) + front * (r + 0.25) + Vector3.UP * (top - 3.0), front, 1.1, Color(0.95, 0.95, 0.95))


static func _terracotta_details(fst: SurfaceTool, street: Array, h: float) -> void:
	var cream := Color(0.90, 0.87, 0.78)
	for i in range(mini(3, street.size())):
		var e: Dictionary = street[i]
		var w := float(e["w"])
		var ctx := _ctx(fst, e)
		# Ornate terracotta cornice with dentil course, and a second-floor belt course
		StorefrontBuilder._box(ctx, -0.2, w + 0.2, h - 1.2, h - 0.4, 0.0, 0.85, cream)
		var nd := int(w / 0.5)
		for k in range(nd):
			var du := 0.25 + float(k) * 0.5
			StorefrontBuilder._box(ctx, du - 0.11, du + 0.11, h - 1.55, h - 1.2, 0.0, 0.45, cream.darkened(0.05))
		StorefrontBuilder._box(ctx, 0.0, w, 7.9, 8.3, 0.0, 0.32, cream)


# ---------------------------------------------------------------------------------------------
# Plazas & parks
# ---------------------------------------------------------------------------------------------
static func build_plazas(parent: Node3D, plazas: Array, lights: Array) -> void:
	var paving := _weave_paving_mat()
	var granite := StandardMaterial3D.new()
	granite.albedo_color = Color(0.56, 0.54, 0.52)
	granite.roughness = 0.7
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.30, 0.24, 0.16)
	bronze.metallic = 0.85
	bronze.roughness = 0.38
	for pz: Dictionary in plazas:
		var nm := str(pz.get("name", ""))
		var poly := _poly(pz)
		if poly.size() < 3:
			continue
		if nm in ["Westlake Park", "Westlake Center Plaza", "McGraw Square", "Westlake Square", "Van Vorst Plaza", "Mayer Plaza", "James R. and Mary Lou Ellis Plaza"]:
			_paving(parent, poly, paving, 0.06 if nm != "Westlake Center Plaza" else 0.055)
		var cen := Vector2.ZERO
		for p in poly:
			cen += p
		cen /= float(poly.size())
		if nm == "Westlake Park":
			_westlake_water_arch(parent, poly, cen, granite, lights)
		elif nm == "McGraw Square":
			_mcgraw_statue(parent, cen, granite, bronze)


static func _paving(parent: Node3D, poly: PackedVector2Array, mat: Material, y: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	for i in range(0, idx.size(), 3):
		for k in [0, 2, 1]:
			var p := poly[idx[i + k]]
			st.set_normal(Vector3.UP)
			st.set_uv(p / 9.6)
			st.add_vertex(Vector3(p.x, y, p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static var _weave_cache: StandardMaterial3D = null


# Westlake Park's Salish basket-weave granite paving (red, grey and white granite strips)
static func _weave_paving_mat() -> StandardMaterial3D:
	if _weave_cache != null:
		return _weave_cache
	var sz := 512
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1988
	var cols: Array[Color] = [Color(0.62, 0.36, 0.30), Color(0.58, 0.57, 0.56), Color(0.82, 0.80, 0.76), Color(0.40, 0.39, 0.40)]
	var cell := 64 # 1.2m weave cell (texture spans 9.6m)
	for y in range(sz):
		for x in range(sz):
			var cx := x / cell
			var cy := y / cell
			var horiz := (cx + cy) % 2 == 0
			var along := (x % cell) if horiz else (y % cell)
			var across := (y % cell) if horiz else (x % cell)
			var strip := across / 16
			var ci := (strip + (cx * 3 + cy) % 4) % 4
			var c := cols[ci]
			var joint := across % 16 == 0 or along == 0
			if joint:
				c = Color(0.30, 0.29, 0.28)
			else:
				c = c.darkened(rng.randf() * 0.07)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.62
	m.metallic_specular = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_weave_cache = m
	return m


# Lawrence Halprin's concrete water-wall arch at the east end of Westlake Park
static func _westlake_water_arch(parent: Node3D, poly: PackedVector2Array, cen: Vector2, granite: Material, lights: Array) -> void:
	var east := poly[0]
	for p in poly:
		if p.x > east.x:
			east = p
	var base := cen.lerp(east, 0.55)
	var root := Node3D.new()
	root.name = "WestlakeParkWaterArch"
	root.position = Vector3(base.x, 0.0, base.y)
	root.rotation.y = deg_to_rad(-30.0)
	parent.add_child(root)
	var conc := StandardMaterial3D.new()
	conc.albedo_color = Color(0.68, 0.66, 0.62)
	conc.roughness = 0.9
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.55, 0.70, 0.78, 0.55)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	water.metallic = 0.3
	water.emission_enabled = true
	water.emission = Color(0.6, 0.8, 0.9)
	water.emission_energy_multiplier = 0.15
	# Two thick wall piers + lintel forming a walk-through arch, water sheeting down the inner faces
	for sx: float in [-3.4, 3.4]:
		_mesh_box(root, Vector3(2.2, 5.6, 3.0), Vector3(sx, 2.8, 0.0), conc)
		_mesh_box(root, Vector3(0.05, 5.0, 2.6), Vector3(sx - signf(sx) * 1.13, 2.6, 0.0), water)
	_mesh_box(root, Vector3(9.0, 1.4, 3.0), Vector3(0.0, 6.3, 0.0), conc)
	for k in range(5):
		_mesh_box(root, Vector3(9.2, 0.06, 3.1), Vector3(0.0, 1.2 + float(k) * 1.1, 0.0), conc)
	# Shallow pool at the foot of the wall
	_mesh_box(root, Vector3(11.0, 0.45, 2.4), Vector3(0.0, 0.22, 2.7), granite)
	_mesh_box(root, Vector3(10.4, 0.06, 1.9), Vector3(0.0, 0.42, 2.7), water)
	# Granite planters with trees and benches around the paving
	var plant := StandardMaterial3D.new()
	plant.albedo_color = Color(0.20, 0.34, 0.16)
	for k in range(4):
		var off := Vector3(-14.0 + float(k) * 6.0, 0.0, 9.0)
		_mesh_box(root, Vector3(2.4, 0.55, 2.4), off + Vector3(0, 0.275, 0), granite)
		_mesh_box(root, Vector3(2.2, 0.1, 2.2), off + Vector3(0, 0.58, 0), plant)
		_mesh_box(root, Vector3(2.6, 0.08, 0.5), off + Vector3(0, 0.46, 1.6), granite)
	var fl := OmniLight3D.new()
	fl.light_color = Color(0.70, 0.92, 1.0)
	fl.light_energy = 0.0
	fl.visible = false
	fl.omni_range = 12.0
	fl.position = Vector3(0.0, 2.0, 2.0)
	root.add_child(fl)
	lights.append(fl)


# John H. McGraw statue (1913, bronze, on a granite pedestal) in McGraw Square
static func _mcgraw_statue(parent: Node3D, cen: Vector2, granite: Material, bronze: Material) -> void:
	var root := Node3D.new()
	root.name = "McGrawStatue"
	root.position = Vector3(cen.x, 0.0, cen.y)
	parent.add_child(root)
	_mesh_box(root, Vector3(3.2, 0.4, 3.2), Vector3(0, 0.2, 0), granite)
	_mesh_box(root, Vector3(2.2, 0.5, 2.2), Vector3(0, 0.65, 0), granite)
	_mesh_box(root, Vector3(1.5, 2.6, 1.5), Vector3(0, 2.2, 0), granite)
	_mesh_box(root, Vector3(1.8, 0.3, 1.8), Vector3(0, 3.65, 0), granite)
	# Bronze figure: standing man in a frock coat, right arm raised
	var fig := Node3D.new()
	fig.position = Vector3(0, 3.8, 0)
	root.add_child(fig)
	var coat := CapsuleMesh.new()
	coat.radius = 0.36; coat.height = 1.5
	_mesh(fig, coat, Vector3(0, 1.25, 0), bronze, Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
	var legs := CylinderMesh.new()
	legs.top_radius = 0.3; legs.bottom_radius = 0.34; legs.height = 0.8
	_mesh(fig, legs, Vector3(0, 0.4, 0), bronze, Vector3.ZERO, Vector3(1.0, 1.0, 0.75))
	var head := SphereMesh.new()
	head.radius = 0.17; head.height = 0.38
	_mesh(fig, head, Vector3(0, 2.2, 0), bronze, Vector3.ZERO, Vector3.ONE)
	var arm := CapsuleMesh.new()
	arm.radius = 0.09; arm.height = 0.85
	_mesh(fig, arm, Vector3(0.42, 1.95, -0.12), bronze, Vector3(-20.0, 0.0, -35.0), Vector3.ONE)
	_mesh(fig, arm, Vector3(-0.42, 1.3, 0.0), bronze, Vector3(0.0, 0.0, 10.0), Vector3.ONE)


static func _mesh_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = sz
	_mesh(parent, b, pos, mat, Vector3.ZERO, Vector3.ONE)


static func _mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: Material, rot_deg: Vector3, sc: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = sc
	parent.add_child(mi)



# ---------------------------------------------------------------------------------------------
# Iconic tower facades: per-building fins / spandrels / piers / crowns over the shader curtain wall
# ---------------------------------------------------------------------------------------------
# kind -> {fins: [spacing, width, depth, colour], bands: [spacing, height, depth, colour], crown: id}
const TOWER_LOOKS := {
	# Amazon Doppler (2015): blue-grey glass wrapped in thin horizontal white spandrel bands
	"amazon_doppler": {"bands": [4.0, 0.42, 0.22, Color(0.86, 0.87, 0.86)], "crown": "flat_dark"},
	# Amazon Day 1 (2016): bronze-tinted glass with closely spaced vertical champagne fins
	"amazon_day1": {"fins": [1.55, 0.10, 0.55, Color(0.72, 0.64, 0.52)], "crown": "flat_dark"},
	# re:Invent / Blackfoot: silver glass, wide fins + every-2-floor belt
	"amazon_reinvent": {"fins": [3.1, 0.14, 0.45, Color(0.78, 0.80, 0.82)], "bands": [8.0, 0.35, 0.18, Color(0.70, 0.72, 0.74)], "crown": "flat_dark"},
	"amazon_blackfoot": {"fins": [3.1, 0.14, 0.45, Color(0.60, 0.62, 0.64)], "bands": [8.0, 0.35, 0.18, Color(0.50, 0.52, 0.55)], "crown": "flat_dark"},
	# Medical Dental Building (1925): cream terracotta Gothic, continuous piers to a pinnacled crown
	"medical_dental": {"fins": [2.2, 0.50, 0.45, Color(0.88, 0.85, 0.77)], "bands": [3.6, 0.22, 0.14, Color(0.80, 0.77, 0.69)], "crown": "gothic"},
	# Century Square (1985): rose granite post-modern tower with gabled crown
	"century_square": {"fins": [2.6, 0.55, 0.35, Color(0.74, 0.56, 0.50)], "bands": [3.9, 0.30, 0.12, Color(0.68, 0.50, 0.45)], "crown": "gable"},
	"times_square": {"fins": [3.0, 0.40, 0.25, Color(0.90, 0.88, 0.80)]},
	"wac": {"fins": [2.0, 0.45, 0.32, Color(0.70, 0.56, 0.42)], "crown": "deco"},
	"securities": {"fins": [3.2, 0.40, 0.25, Color(0.86, 0.82, 0.72)]},
	"joshua_green": {"fins": [3.0, 0.40, 0.25, Color(0.92, 0.90, 0.84)]},
}


static func _tower_overlay(fst: SurfaceTool, poly: PackedVector2Array, h: float, lm: String) -> void:
	var look: Dictionary = TOWER_LOOKS[lm]
	# Follow the podium/setback massing used by CityBuilder for tall wide towers
	var tiers: Array = [[poly, 0.0, h]]
	var mn := poly[0]
	var mx := poly[0]
	for p in poly:
		mn = mn.min(p)
		mx = mx.max(p)
	if h >= 44.0 and mx.x - mn.x > 30.0 and mx.y - mn.y > 30.0:
		var inset := Geometry2D.offset_polygon(poly, -3.4)
		if inset.size() == 1 and inset[0].size() >= 3:
			var tp: PackedVector2Array = inset[0]
			if Geometry2D.is_polygon_clockwise(tp):
				tp.reverse()
			tiers = [[poly, 0.0, 16.0], [tp, 16.0, h]]
	for tier: Array in tiers:
		var tpoly: PackedVector2Array = tier[0]
		var y0 := maxf(float(tier[1]), 5.0)
		var y1 := float(tier[2])
		var is_top := y1 >= h - 0.01
		for i in range(tpoly.size()):
			var a := tpoly[i]
			var c := tpoly[(i + 1) % tpoly.size()]
			var w := a.distance_to(c)
			if w < 3.0:
				continue
			var d2 := (c - a) / w
			var n2 := Vector2(-d2.y, d2.x)
			if Geometry2D.is_point_in_polygon((a + c) * 0.5 + n2 * 0.4, tpoly):
				n2 = -n2
			var ctx := {"o": Vector3(a.x, 0.0, a.y), "u": Vector3(d2.x, 0.0, d2.y), "n": Vector3(n2.x, 0.0, n2.y), "st": fst}
			if look.has("fins"):
				var fn: Array = look["fins"]
				var sp := float(fn[0])
				var nf := maxi(1, int(round(w / sp)))
				for k in range(nf + 1):
					var fu := w * float(k) / float(nf)
					StorefrontBuilder._box(ctx, fu - float(fn[1]) * 0.5, fu + float(fn[1]) * 0.5, y0, y1, 0.0, float(fn[2]), fn[3])
			if look.has("bands"):
				var bd: Array = look["bands"]
				var yb := y0 + float(bd[0])
				while yb < y1 - 1.0:
					StorefrontBuilder._box(ctx, -0.05, w + 0.05, yb, yb + float(bd[1]), 0.0, float(bd[2]), bd[3])
					yb += float(bd[0])
			if not is_top:
				continue
			match str(look.get("crown", "")):
				"flat_dark":
					StorefrontBuilder._box(ctx, -0.1, w + 0.1, y1 - 3.2, y1 + 2.2, 0.0, 0.35, Color(0.18, 0.20, 0.22))
				"gothic":
					StorefrontBuilder._box(ctx, -0.1, w + 0.1, y1 - 1.0, y1 + 1.2, 0.0, 0.55, Color(0.90, 0.87, 0.79))
					var npin := maxi(1, int(round(w / 2.2)))
					for k in range(npin + 1):
						var pu := w * float(k) / float(npin)
						StorefrontBuilder._box(ctx, pu - 0.25, pu + 0.25, y1 + 1.2, y1 + 3.0, 0.05, 0.5, Color(0.90, 0.87, 0.79))
						StorefrontBuilder._box(ctx, pu - 0.12, pu + 0.12, y1 + 3.0, y1 + 4.2, 0.15, 0.4, Color(0.92, 0.89, 0.81))
				"deco":
					StorefrontBuilder._box(ctx, -0.1, w + 0.1, y1 - 4.0, y1 + 0.8, 0.0, 0.4, Color(0.78, 0.66, 0.50))
					StorefrontBuilder._box(ctx, w * 0.25, w * 0.75, y1 + 0.8, y1 + 3.5, -1.5, -0.6, Color(0.76, 0.64, 0.48))
				"gable":
					StorefrontBuilder._box(ctx, -0.1, w + 0.1, y1 - 0.6, y1 + 0.6, 0.0, 0.5, Color(0.70, 0.52, 0.46))
					if w > 14.0:
						var o3: Vector3 = ctx["o"]
						var u3: Vector3 = ctx["u"]
						var n3: Vector3 = ctx["n"]
						var g0 := o3 + n3 * 0.3 + Vector3.UP * (y1 + 0.6)
						var g1 := o3 + u3 * w + n3 * 0.3 + Vector3.UP * (y1 + 0.6)
						var gp := o3 + u3 * (w * 0.5) + n3 * 0.3 + Vector3.UP * (y1 + 0.6 + w * 0.28)
						StorefrontBuilder._tri(fst, g0, g1, gp, Color(0.72, 0.55, 0.49))
						StorefrontBuilder._tri(fst, g0, gp, g1, Color(0.72, 0.55, 0.49))
