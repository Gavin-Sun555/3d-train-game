class_name CityOverview
extends RefCounted
# Whole-city overview for the bird's-eye view zoomed far out: the detailed city (façade shaders, kerbs,
# furniture, trees, storefronts, streamed tiles) is swapped for a light model built straight from the map data:
# buildings as plain shaded blocks on the ground, streets / freeways / parks as flat shapes, and the player's
# tram network drawn bold. Built on a worker thread (plain arrays, no reads back from the RenderingServer).

const ROAD_COL := Color(0.36, 0.37, 0.39)
const FREEWAY_COL := Color(0.30, 0.31, 0.33)
const PARK_COL := Color(0.42, 0.58, 0.34)
const PLAZA_COL := Color(0.70, 0.69, 0.66)
const WATER_COL := Color(0.10, 0.25, 0.33)
const TRACK_COL := Color(0.98, 0.55, 0.12)
const MONO_COL := Color(0.86, 0.22, 0.24)


# snapshot: {buildings, roads, areas, freeways, tracks: [{pts: [Vector2], mono: bool}], stations: [Vector2]}
static func build(snap: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "CityOverview"
	root.set_meta("on_terrain", true)
	var flat := _Acc.new()
	var blds := _Acc.new()
	var net := _Acc.new()
	# water, parks and plazas
	for a: Dictionary in snap.get("areas", []):
		var kind := str(a.get("kind", ""))
		var col := PARK_COL if kind in ["park", "grass", "wood", "meadow", "garden", "sports", "pitch"] else PLAZA_COL
		if kind == "wood":
			col = PARK_COL.darkened(0.18)
		elif kind == "water":
			col = WATER_COL
		var poly := _poly(a.get("pts", []))
		if poly.size() < 3:
			continue
		var idx := Geometry2D.triangulate_polygon(poly)
		for i in range(0, idx.size(), 3):
			for k in [0, 1, 2]:
				var p := poly[idx[i + k]]
				flat.add(Vector3(p.x, Terrain.surface(p.x, p.y) + (0.3 if kind == "water" else 0.6), p.y), Vector3.UP, col)
	# streets (wide enough to read from kilometres up) and freeways
	for r: Dictionary in snap.get("roads", []):
		_ribbon(flat, r.get("pts", []), maxf(float(r.get("width", 10.0)), 9.0), 1.2, ROAD_COL)
	for f: Dictionary in snap.get("freeways", []):
		var fp: Array = []
		var ys: Array = []
		for p in f.get("pts", []):
			fp.append([p[0], p[1]])
			ys.append(float(p[2]))
		_ribbon(flat, fp, maxf(float(f.get("w", 12.0)), 12.0), 1.6, FREEWAY_COL, ys)
	# buildings: blocks with a flat roof, sitting on their lowest ground
	for b: Dictionary in snap.get("buildings", []):
		var poly := _simplify(_poly(b.get("pts", [])), 1.2)
		if poly.size() < 3 or absf(_area(poly)) < 20.0:
			continue
		var h := clampf(float(b.get("h", 10.0)), 3.0, 300.0)
		if b.has("roof"):
			h += float((b["roof"] as Dictionary).get("h", 2.0)) * 0.5
		var y0 := Terrain.base_under(poly)
		var col := _bld_col(b, h)
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		for i in range(poly.size()):
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var e := p1 - p0
			if e.length() < 0.2:
				continue
			var n := Vector3(-e.y, 0.0, e.x).normalized()
			var wc := col.darkened(0.12 + 0.12 * absf(n.x))
			var a0 := Vector3(p0.x, y0, p0.y)
			var a1 := Vector3(p1.x, y0, p1.y)
			var t0 := Vector3(p0.x, y0 + h, p0.y)
			var t1 := Vector3(p1.x, y0 + h, p1.y)
			for v: Vector3 in [a0, a1, t1, a0, t1, t0]:
				blds.add(v, n, wc)
		var idx2 := Geometry2D.triangulate_polygon(poly)
		for i in range(0, idx2.size(), 3):
			for k in [0, 2, 1]:
				var q := poly[idx2[i + k]]
				blds.add(Vector3(q.x, y0 + h, q.y), Vector3.UP, col)
	# the player's network: bold lines, stations as dots
	for t: Dictionary in snap.get("tracks", []):
		var pts: Array = []
		for p2: Vector2 in t["pts"]:
			pts.append([p2.x, p2.y])
		var mono := bool(t.get("mono", false))
		_ribbon(net, pts, 30.0, 9.0 if mono else 3.0, MONO_COL if mono else TRACK_COL)
	for sp: Vector2 in snap.get("stations", []):
		var y := Terrain.surface(sp.x, sp.y) + 4.0
		for k in range(16):
			var a1 := TAU * float(k) / 16.0
			var a2 := TAU * float(k + 1) / 16.0
			for v2: Vector3 in [Vector3(sp.x, y, sp.y), Vector3(sp.x + cos(a2) * 34.0, y, sp.y + sin(a2) * 34.0), Vector3(sp.x + cos(a1) * 34.0, y, sp.y + sin(a1) * 34.0)]:
				net.add(v2, Vector3.UP, Color(1, 1, 1))
	_emit(root, "OverviewGround", flat, false)
	_emit(root, "OverviewBuildings", blds, false)
	_emit(root, "OverviewNetwork", net, true)
	return root


static func _bld_col(b: Dictionary, h: float) -> Color:
	var st := int(b.get("style", 2))
	if st == 3:
		return Color(0.78, 0.74, 0.69)
	if st == 0 or h > 60.0:
		return Color(0.62, 0.68, 0.74)
	if st == 1:
		return Color(0.74, 0.60, 0.52)
	return Color(0.82, 0.81, 0.79)


static func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		var v := Vector2(float(p[0]), float(p[1]))
		if out.is_empty() or out[out.size() - 1].distance_to(v) > 0.3:
			out.append(v)
	if out.size() >= 3 and out[0].distance_to(out[out.size() - 1]) < 0.3:
		out.resize(out.size() - 1)
	return out


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return a * 0.5


# Drop footprint corners closer than tol to the line through their neighbours (curved façades, tiny jogs)
static func _simplify(poly: PackedVector2Array, tol: float) -> PackedVector2Array:
	if poly.size() <= 4:
		return poly
	var out := poly.duplicate()
	var changed := true
	while changed and out.size() > 4:
		changed = false
		var i := 0
		while i < out.size() and out.size() > 4:
			var a := out[(i - 1 + out.size()) % out.size()]
			var b := out[i]
			var c := out[(i + 1) % out.size()]
			var ac := c - a
			var l := ac.length()
			var dev := (b - a).length() if l < 0.01 else absf(ac.cross(b - a)) / l
			if dev < tol:
				out.remove_at(i)
				changed = true
			else:
				i += 1
	return out


# Flat strip along a polyline, on the ground (or at given deck heights)
static func _ribbon(acc: _Acc, pts: Array, w: float, lift: float, col: Color, ys: Array = []) -> void:
	var dense := pts if not ys.is_empty() else Terrain.densify(pts, 40.0)
	if dense.size() < 2:
		return
	var hw := w * 0.5
	for i in range(dense.size() - 1):
		var a := Vector2(float(dense[i][0]), float(dense[i][1]))
		var b := Vector2(float(dense[i + 1][0]), float(dense[i + 1][1]))
		var d := b - a
		if d.length() < 0.1:
			continue
		var n := Vector2(-d.y, d.x).normalized() * hw
		var ya := (float(ys[i]) if not ys.is_empty() else Terrain.surface(a.x, a.y)) + lift
		var yb := (float(ys[i + 1]) if not ys.is_empty() else Terrain.surface(b.x, b.y)) + lift
		var v0 := Vector3(a.x - n.x, ya, a.y - n.y)
		var v1 := Vector3(a.x + n.x, ya, a.y + n.y)
		var v2 := Vector3(b.x + n.x, yb, b.y + n.y)
		var v3 := Vector3(b.x - n.x, yb, b.y - n.y)
		for v: Vector3 in [v0, v2, v1, v0, v3, v2]:
			acc.add(v, Vector3.UP, col)


static func _emit(root: Node3D, nm: String, acc: _Acc, unshaded: bool) -> void:
	if acc.v.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = acc.v
	arr[Mesh.ARRAY_NORMAL] = acc.n
	arr[Mesh.ARRAY_COLOR] = acc.c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


class _Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	func add(p: Vector3, nrm: Vector3, col: Color) -> void:
		v.append(p)
		n.append(nrm)
		c.append(col)
