class_name NanhuBuilder
extends RefCounted

# 南湖 after photos and the satellite view:
#  湖心岛 · 烟雨楼: granite embankment along the island's real shore, the two-storey 烟雨楼 (red columns, teal
#          carved 挂落 friezes under the eaves, lattice doors, balcony, double hip roofs with upturned corners and
#          the 烟雨楼 board), front court with a gate hall and covered corridors, a rear hall, pavilions, rockery,
#          dense autumn-coloured trees (camphor, ginkgo gold, maple red, willows), the 红船 and tour boats at the pier
#  壕股塔: square seven-storey pagoda, cream walls in dark timber frames, a gallery with railings on every storey,
#          grey eaves, pyramid roof and ringed spire with chains, over a yellow-walled hall; stone screen wall and
#          a quay with red railings toward the lake
#  南湖天地 (east shore, 纺工路 / 景湖路): 嘉绢 brick sawtooth factory hall, glass shop pavilions with butterfly
#          fascias and gold louvres, the central axis with its water channel, lawns and trees, the red ribbed
#          sculpture and the NANHU PLACE letters, the lakeside terrace, 南湖书院 courtyards, the new glass mall with
#          flared Chinese roofs and an LED wall along 纺工路, the 鸳湖里弄 lane houses
#  凯悦: 南湖凯悦酒店 (courtyard block, bronze floor bands and fins, porte-cochere, reflecting pool) and
#          凯悦嘉轩酒店 (long block of bronze fins along 纺工路 with the tram), both with upswept roof edges

const TILE := Color(0.24, 0.25, 0.27)
const RED_COL := Color(0.55, 0.14, 0.10)
const TEAL := Color(0.34, 0.52, 0.52)
const LIME := Color(0.90, 0.89, 0.85)
const GRANITE := Color(0.64, 0.62, 0.58)
const BRONZE := Color(0.68, 0.50, 0.34)

static var _trees: Node3D


static func build(root: Node3D, lm: Dictionary, lights: Array) -> void:
	BatchKit.begin()
	var node := Node3D.new()
	node.name = "NanhuDistrict"
	root.add_child(node)
	_trees = Node3D.new()
	_trees.name = "NanhuTrees"
	node.add_child(_trees)
	# each site is committed as its own meshes: visibility ranges are measured to a mesh's centre, so one mesh
	# spanning the whole lake would drop its near detail everywhere
	if lm.has("yanyu_tower"):
		var y: Dictionary = lm["yanyu_tower"]
		_island(node, _v(y["pos"]), y.get("island_pts", []), lights)
		BatchKit.commit(node, "Nanhu_Yanyu")
	if lm.has("haogu_pagoda"):
		var h: Dictionary = lm["haogu_pagoda"]
		var f: Array = h.get("face", [0.0, 1.0])
		_pagoda(node, _v(h["pos"]), atan2(float(f[0]), float(f[1])), lights)
		BatchKit.commit(node, "Nanhu_Haogu")
	var nd: Dictionary = lm.get("nanhu_district", {})
	_district(node, nd, lights)
	_hyatt_regency(node, lights)
	BatchKit.commit(node, "Nanhu_HyattRegency")
	_hyatt_place(node, lights)
	BatchKit.commit(node, "Nanhu_HyattPlace")
	_trees = null


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1]))


# hip roof with upswept corners (Jiangnan / modern Chinese)
static func _flared(layer: String, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, col: Color, oh: float, lift: float) -> void:
	BatchKit.hip(layer, xf, x0, x1, z0, z1, ye, yr, col, oh)
	var reach := minf(3.2, minf(x1 - x0, z1 - z0) * 0.25)
	for cx: float in [x0 - oh, x1 + oh]:
		for cz: float in [z0 - oh, z1 + oh]:
			var sx := 1.0 if cx > x0 else -1.0
			var sz := 1.0 if cz > z0 else -1.0
			var tip := Vector3(cx + sx * 0.6, ye + lift, cz + sz * 0.6)
			BatchKit.fan(layer, xf, [Vector3(cx - sx * reach, ye, cz), Vector3(cx, ye, cz - sz * reach), tip], col, Vector3(sx, 1.0, sz))
			BatchKit.fan(layer, xf, [Vector3(cx - sx * reach, ye, cz), Vector3(cx, ye, cz), tip], col, Vector3(0.0, 1.0, sz))
			BatchKit.fan(layer, xf, [Vector3(cx, ye, cz - sz * reach), Vector3(cx, ye, cz), tip], col, Vector3(sx, 1.0, 0.0))


# pent roof skirting a body (x0..x1, z0..z1) from y_top at the wall down to y_edge `out` metres beyond it
static func _pent(layer: String, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, y_top: float, y_edge: float, out: float, col: Color) -> void:
	var a := Vector3(x0, y_top, z0)
	var b := Vector3(x1, y_top, z0)
	var c := Vector3(x1, y_top, z1)
	var d := Vector3(x0, y_top, z1)
	var A := Vector3(x0 - out, y_edge, z0 - out)
	var B := Vector3(x1 + out, y_edge, z0 - out)
	var C := Vector3(x1 + out, y_edge, z1 + out)
	var D := Vector3(x0 - out, y_edge, z1 + out)
	var r := y_top - y_edge
	BatchKit.quad(layer, xf, a, b, B, A, col, Vector3(0.0, out, -r))
	BatchKit.quad(layer, xf, b, c, C, B, col, Vector3(r, out, 0.0))
	BatchKit.quad(layer, xf, c, d, D, C, col, Vector3(0.0, out, r))
	BatchKit.quad(layer, xf, d, a, A, D, col, Vector3(-r, out, 0.0))
	for P: Vector3 in [A, B, C, D]:
		var s := Vector3(signf(P.x - (x0 + x1) * 0.5), 0.0, signf(P.z - (z0 + z1) * 0.5))
		BatchKit.box(layer, xf, P + s * 0.35 + Vector3(0.0, 0.35, 0.0), Vector3(0.5, 0.18, 0.5), col.darkened(0.15))


static func _tree(pos: Vector3, kind: int, sc: float) -> void:
	# 0 camphor green, 1 ginkgo gold, 2 maple red, 3 orange, 4 willow
	match kind:
		1:
			ParkLandscapeBuilder.plant_tree(_trees, pos, 4, sc, Color(0.86, 0.70, 0.16))
		2:
			ParkLandscapeBuilder.plant_tree(_trees, pos, 1, sc * 0.85, Color(0.72, 0.18, 0.10))
		3:
			ParkLandscapeBuilder.plant_tree(_trees, pos, 1, sc * 0.9, Color(0.86, 0.46, 0.14))
		4:
			ParkLandscapeBuilder.plant_tree(_trees, pos, 5, sc, ParkLandscapeBuilder.CAMPHOR_LT)
		_:
			ParkLandscapeBuilder.plant_tree(_trees, pos, 1, sc, ParkLandscapeBuilder.CAMPHOR)


static func _hash(x: float, z: float) -> int:
	return absi(int(x * 7.31 + z * 13.17 + x * z * 0.013))


# ------------------------------------------------------------------------------------------------ 湖心岛 烟雨楼
static func _island(parent: Node3D, c: Vector3, pts_raw: Array, lights: Array) -> void:
	var poly := PackedVector2Array()
	for q in pts_raw:
		poly.append(Vector2(float(q[0]), float(q[1])))
	var I := Transform3D.IDENTITY
	if poly.size() >= 3:
		var area := 0.0
		for i in poly.size():
			area += poly[i].cross(poly[(i + 1) % poly.size()])
		var ccw := area > 0.0
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var d := b - a
			var L := d.length()
			if L < 0.5:
				continue
			d /= L
			var inn := Vector2(-d.y, d.x) if ccw else Vector2(d.y, -d.x)
			var m := (a + b) * 0.5 + inn * 0.6
			var ry := atan2(-d.y, d.x)
			BatchKit.box("op", I, Vector3(m.x, 0.05, m.y), Vector3(L + 0.4, 1.9, 1.2), GRANITE.darkened(0.12), ry)
			BatchKit.box("op", I, Vector3(m.x, 1.06, m.y) - Vector3(inn.x, 0.0, inn.y) * 0.05, Vector3(L + 0.5, 0.16, 1.45), GRANITE.lightened(0.12), ry)
	var xf := BatchKit.xf(c.x, c.z, 0.0)
	# --- 烟雨楼 (front to the south) on its terrace ---
	var hall_z0 := -14.0
	var hall_z1 := 0.0
	BatchKit.bx("op", xf, Vector3(-16.5, 0.0, hall_z0 - 2.5), Vector3(16.5, 1.0, hall_z1 + 2.5), GRANITE)
	BatchKit.bx("op", xf, Vector3(-12.5, 1.0, hall_z0 + 1.5), Vector3(12.5, 6.0, hall_z1 - 1.5), Color(0.40, 0.16, 0.12))
	# lattice doors on the front, columns all round, teal frieze under the eave
	var x := -11.0
	while x < 11.5:
		BatchKit.bx("op_d", xf, Vector3(x - 0.9, 1.3, hall_z1 - 1.45), Vector3(x + 0.9, 5.2, hall_z1 - 1.38), Color(0.72, 0.66, 0.52))
		BatchKit.bx("op_d", xf, Vector3(x - 0.08, 1.3, hall_z1 - 1.35), Vector3(x + 0.08, 5.2, hall_z1 - 1.30), RED_COL)
		x += 2.2
	for cxk in 9:
		var cx := -12.8 + cxk * 3.2
		for cz: float in [hall_z1 + 1.4, hall_z0 - 1.4]:
			BatchKit.prism("op", xf, Vector3(cx, 1.0, cz), 0.24, 0.22, 5.0, 8, RED_COL)
			if cxk < 8:
				BatchKit.bx("op_d", xf, Vector3(cx + 0.25, 5.15, cz - 0.08), Vector3(cx + 2.95, 5.75, cz + 0.08), TEAL)
				for t in 4:
					BatchKit.bx("op_d", xf, Vector3(cx + 0.5 + t * 0.65, 4.85, cz - 0.06), Vector3(cx + 0.62 + t * 0.65, 5.15, cz + 0.06), TEAL.darkened(0.2))
	for cz2 in 5:
		for cx2: float in [-14.4, 14.4]:
			BatchKit.prism("op", xf, Vector3(cx2, 1.0, hall_z0 - 1.4 + cz2 * (hall_z1 - hall_z0 + 2.8) / 4.0), 0.24, 0.22, 5.0, 8, RED_COL)
	_pent("op", xf, -14.6, 14.6, hall_z0 - 1.6, hall_z1 + 1.6, 6.9, 5.9, 2.0, TILE)
	# upper storey with a red balcony railing, lattice windows and the board
	BatchKit.bx("op", xf, Vector3(-11.0, 6.0, hall_z0 + 2.5), Vector3(11.0, 11.0, hall_z1 - 2.5), Color(0.42, 0.17, 0.12))
	BatchKit.bx("op", xf, Vector3(-12.6, 6.6, hall_z0 + 0.9), Vector3(12.6, 6.9, hall_z1 - 0.9), Color(0.36, 0.14, 0.10))
	var bx := -12.4
	while bx <= 12.45:
		BatchKit.bx("op_d", xf, Vector3(bx - 0.06, 6.9, hall_z1 - 1.0), Vector3(bx + 0.06, 7.9, hall_z1 - 0.9), RED_COL)
		BatchKit.bx("op_d", xf, Vector3(bx - 0.06, 6.9, hall_z0 + 0.9), Vector3(bx + 0.06, 7.9, hall_z0 + 1.0), RED_COL)
		bx += 0.9
	BatchKit.bx("op_d", xf, Vector3(-12.6, 7.85, hall_z1 - 1.05), Vector3(12.6, 8.0, hall_z1 - 0.85), RED_COL)
	BatchKit.bx("op_d", xf, Vector3(-12.6, 7.85, hall_z0 + 0.85), Vector3(12.6, 8.0, hall_z0 + 1.05), RED_COL)
	var wx := -9.6
	while wx < 10.0:
		BatchKit.bx("op_d", xf, Vector3(wx - 0.75, 7.6, hall_z1 - 2.45), Vector3(wx + 0.75, 10.0, hall_z1 - 2.38), Color(0.76, 0.72, 0.60))
		wx += 2.4
	BatchKit.bx("op_d", xf, Vector3(-11.2, 10.1, hall_z1 - 2.4), Vector3(11.2, 10.7, hall_z1 - 2.3), TEAL)
	_flared("op", xf, -11.0, 11.0, hall_z0 + 2.5, hall_z1 - 2.5, 11.0, 14.6, TILE, 2.4, 1.3)
	BatchKit.bx("op", xf, Vector3(-6.2, 14.5, -7.1), Vector3(6.2, 15.1, -6.9), TILE.darkened(0.3))
	for sx: float in [-6.4, 6.4]:
		BatchKit.box("op_d", xf, Vector3(sx, 15.4, -7.0), Vector3(0.5, 1.0, 0.5), TILE.darkened(0.3))
	BatchKit.bx("op_d", xf, Vector3(-2.6, 8.4, hall_z1 - 0.7), Vector3(2.6, 9.9, hall_z1 - 0.62), Color(0.92, 0.90, 0.82))
	BatchKit.label(parent, xf, "烟 雨 楼", Vector3(0.0, 9.15, hall_z1 - 0.55), 0.0, 110, 0.02, Color(0.10, 0.10, 0.10))
	for lx: float in [-6.0, 6.0]:
		BatchKit.sphere("em", xf, Vector3(lx, 4.6, hall_z1 + 1.6), 0.38, Color(0.95, 0.20, 0.12), 1.0)
	BatchKit.light(parent, xf, Vector3(0.0, 4.0, 4.0), Color(1.0, 0.80, 0.55), 28.0, lights)
	# front court: paving, covered corridors, gate hall; rear hall; side pavilion
	BatchKit.bx("op", xf, Vector3(-15.0, 0.0, 2.5), Vector3(15.0, 0.12, 22.0), Color(0.66, 0.64, 0.60))
	for sx2: float in [-1.0, 1.0]:
		var zc := 3.0
		while zc <= 21.0:
			BatchKit.prism("op_d", xf, Vector3(sx2 * 15.0, 0.0, zc), 0.16, 0.15, 3.2, 6, RED_COL)
			BatchKit.prism("op_d", xf, Vector3(sx2 * 17.4, 0.0, zc), 0.16, 0.15, 3.2, 6, RED_COL)
			zc += 3.0
		BatchKit.gable_z("op", xf, sx2 * 16.2 - 1.6, sx2 * 16.2 + 1.6, 2.5, 21.5, 3.2, 4.4, TILE, 0.5)
	BatchKit.bx("op", xf, Vector3(-8.0, 0.0, 22.0), Vector3(8.0, 4.6, 28.0), LIME)
	BatchKit.bx("op_d", xf, Vector3(-1.4, 0.0, 27.95), Vector3(1.4, 3.4, 28.05), Color(0.30, 0.12, 0.08))
	_flared("op", xf, -8.0, 8.0, 22.0, 28.0, 4.6, 7.2, TILE, 1.0, 0.8)
	BatchKit.bx("op", xf, Vector3(-10.0, 0.0, -32.0), Vector3(10.0, 5.2, -22.0), LIME)
	for k in 6:
		BatchKit.bx("op_d", xf, Vector3(-8.5 + k * 3.2, 1.0, -21.98), Vector3(-6.9 + k * 3.2, 4.0, -21.9), Color(0.40, 0.17, 0.12))
	_flared("op", xf, -10.0, 10.0, -32.0, -22.0, 5.2, 8.4, TILE, 1.2, 0.9)
	for sx3: float in [-1.0, 1.0]:
		BatchKit.bx("op", xf, Vector3(sx3 * 20.0 - 4.0, 0.0, -10.0), Vector3(sx3 * 20.0 + 4.0, 4.4, 0.0), LIME)
		BatchKit.gable_z("op", xf, sx3 * 20.0 - 4.0, sx3 * 20.0 + 4.0, -10.0, 0.0, 4.4, 6.6, TILE, 0.6)
	# rockery
	for k in 9:
		var rp := Vector3(-26.0 + float(k % 3) * 2.6, 0.0, -18.0 + floorf(float(k) / 3.0) * 2.4)
		BatchKit.prism("op_d", xf, rp, 1.4 - float(k % 2) * 0.4, 0.5, 1.6 + float((k * 7) % 5) * 0.5, 6, Color(0.50, 0.50, 0.48), float(k))
	# pavilions near the shore (NE, W) and the pier with the 红船 (SE)
	var cen2 := Vector2(c.x, c.z)
	for dir: Vector2 in [Vector2(0.8, -0.6).normalized(), Vector2(-1.0, 0.15).normalized(), Vector2(0.1, -1.0)]:
		var far := _farthest(poly, cen2, dir)
		var p := far - dir * 9.0
		var pxf := BatchKit.xf(p.x, p.y, 0.0)
		BatchKit.prism("op", pxf, Vector3(0.0, 0.0, 0.0), 3.6, 3.6, 0.6, 6, GRANITE)
		for k in 6:
			var a := TAU * float(k) / 6.0
			BatchKit.prism("op_d", pxf, Vector3(cos(a) * 2.9, 0.6, sin(a) * 2.9), 0.14, 0.13, 3.0, 6, RED_COL)
		BatchKit.prism("op", pxf, Vector3(0.0, 3.6, 0.0), 4.2, 0.3, 2.6, 6, TILE)
		BatchKit.prism("op_d", pxf, Vector3(0.0, 6.2, 0.0), 0.3, 0.05, 0.9, 6, TILE)
	var se := Vector2(0.76, 0.65).normalized()
	var shore := _farthest(poly, cen2, se)
	var jet_end := shore + se * 12.0
	var jl := shore.distance_to(jet_end)
	var jry := atan2(-se.y, se.x)
	var jm := (shore + jet_end) * 0.5
	BatchKit.box("op", I, Vector3(jm.x, 0.75, jm.y), Vector3(jl, 0.25, 3.0), Color(0.48, 0.36, 0.24), jry)
	var boat_c := jet_end + se * 1.0 + Vector2(-se.y, se.x) * 4.5
	_red_boat(BatchKit.xf(boat_c.x, boat_c.y, jry + PI * 0.5))
	for k in 2:
		var tb := jet_end + Vector2(se.y, -se.x) * (5.0 + k * 5.0) - se * 2.0
		_tour_boat(BatchKit.xf(tb.x, tb.y, jry + PI * 0.5))
	# dense autumn trees inside the embankment, clear of the buildings and court
	if poly.size() >= 3:
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for v in poly:
			mn = mn.min(v)
			mx = mx.max(v)
		var gz := mn.y + 3.0
		while gz < mx.y:
			var gx := mn.x + 3.0 + fposmod(gz * 0.37, 3.0)
			gz += 8.0
			while gx < mx.x:
				var p2 := Vector2(gx, gz)
				gx += 8.5
				if not Geometry2D.is_point_in_polygon(p2, poly):
					continue
				var edge_d := _edge_dist(poly, p2)
				if edge_d < 3.2:
					continue
				var l2 := p2 - cen2
				if l2.x > -27.0 and l2.x < 27.0 and l2.y > -35.0 and l2.y < 31.0:
					continue
				var hsh := _hash(p2.x, p2.y)
				var kind := 0
				if edge_d < 7.0 and hsh % 3 == 0:
					kind = 4
				else:
					kind = [0, 1, 2, 0, 1, 3, 0, 2][hsh % 8]
				_tree(Vector3(p2.x + float(hsh % 5) * 0.4 - 0.8, 0.0, p2.y + float(int(hsh / 5.0) % 5) * 0.4 - 0.8), kind, 1.05 + float(hsh % 7) * 0.06)
	# a few trees inside the court
	for tp: Vector3 in [Vector3(-10.0, 0.0, 12.0), Vector3(10.0, 0.0, 12.0), Vector3(-22.0, 0.0, 8.0), Vector3(22.0, 0.0, -18.0)]:
		_tree(xf * tp, 1 if tp.x < 0.0 else 2, 0.8)


static func _farthest(poly: PackedVector2Array, cen: Vector2, dir: Vector2) -> Vector2:
	var best := cen + dir * 30.0
	var bp := -1e9
	for v in poly:
		var pr := (v - cen).dot(dir)
		var side := absf((v - cen).cross(dir))
		if pr - side * 0.6 > bp:
			bp = pr - side * 0.6
			best = v
	return best


static func _edge_dist(poly: PackedVector2Array, p: Vector2) -> float:
	var best := 1e9
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(p))
	return best


static func _red_boat(xf: Transform3D) -> void:
	var hull := Color(0.42, 0.12, 0.08)
	BatchKit.bx("op", xf, Vector3(-1.6, -0.2, -7.0), Vector3(1.6, 0.9, 7.0), hull)
	BatchKit.box("op", xf, Vector3(0.0, 0.9, -7.6), Vector3(2.6, 0.9, 1.6), hull, 0.0)
	BatchKit.box("op", xf, Vector3(0.0, 0.9, 7.6), Vector3(2.6, 0.9, 1.6), hull, 0.0)
	BatchKit.bx("op", xf, Vector3(-1.4, 0.9, -4.0), Vector3(1.4, 2.6, 3.5), Color(0.52, 0.16, 0.10))
	for k in 5:
		BatchKit.bx("op_d", xf, Vector3(-1.45, 1.5, -3.2 + k * 1.4), Vector3(1.45, 2.2, -2.5 + k * 1.4), Color(0.86, 0.80, 0.62))
	BatchKit.gable_z("op", xf, -1.7, 1.7, -4.3, 3.8, 2.6, 3.3, Color(0.10, 0.10, 0.11), 0.2)
	BatchKit.bx("op_d", xf, Vector3(-0.08, 0.9, 5.0), Vector3(0.08, 4.2, 5.16), Color(0.30, 0.20, 0.14))
	BatchKit.box("em", xf, Vector3(0.0, 2.2, 4.0), Vector3(0.45, 0.6, 0.45), Color(0.95, 0.22, 0.12))


static func _tour_boat(xf: Transform3D) -> void:
	BatchKit.bx("op_d", xf, Vector3(-1.4, -0.2, -5.0), Vector3(1.4, 0.7, 5.0), Color(0.36, 0.26, 0.18))
	BatchKit.bx("op_d", xf, Vector3(-1.2, 0.7, -2.8), Vector3(1.2, 2.2, 2.8), Color(0.80, 0.74, 0.60))
	BatchKit.gable_z("op_d", xf, -1.5, 1.5, -3.0, 3.0, 2.2, 2.8, Color(0.14, 0.14, 0.15), 0.2)


# ------------------------------------------------------------------------------------------------ 壕股塔
static func _pagoda(parent: Node3D, c: Vector3, ry: float, lights: Array) -> void:
	var xf := BatchKit.xf(c.x, c.z, ry)
	var cream := Color(0.86, 0.82, 0.70)
	var timber := Color(0.24, 0.17, 0.12)
	var roof := Color(0.27, 0.28, 0.30)
	var pz := -10.0
	var y := 0.0
	var w := 10.0
	for k in 7:
		var h := 6.0 if k == 0 else 4.6
		var hw := w * 0.5
		BatchKit.bx("op", xf, Vector3(-hw, y, pz - hw), Vector3(hw, y + h, pz + hw), cream)
		# timber frame: corner and mid posts, beams
		for px: float in [-hw, -hw * 0.33, hw * 0.33, hw]:
			for f: int in 4:
				var a := Vector3(px, 0.0, hw) if f == 0 else (Vector3(px, 0.0, -hw) if f == 1 else (Vector3(hw, 0.0, px) if f == 2 else Vector3(-hw, 0.0, px)))
				BatchKit.box("op_d", xf, Vector3(a.x, y + h * 0.5, pz + a.z), Vector3(0.32, h, 0.32), timber)
		for by: float in [y + 0.15, y + h - 0.35]:
			BatchKit.bx("op_d", xf, Vector3(-hw - 0.05, by, pz - hw - 0.05), Vector3(hw + 0.05, by + 0.3, pz + hw + 0.05), timber)
		# arched door / window on each face
		for fd: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
			BatchKit.arch("op_d", xf, Vector3(0.0, y + 0.9, pz) + fd * hw, 1.5, 2.6, fd, Color(0.12, 0.10, 0.09), false, 0.06)
			var u := Vector3.UP.cross(fd)
			for o: float in [-1.0, 1.0]:
				BatchKit.bx("op_d", xf, Vector3(0.0, y + 1.4, pz) + fd * (hw + 0.04) + u * o * hw * 0.62 - u.abs() * 0.5, Vector3(0.0, y + 2.9, pz) + fd * (hw + 0.07) + u * o * hw * 0.62 + u.abs() * 0.5, Color(0.30, 0.22, 0.16))
		# gallery with railing
		if k > 0:
			var gw := hw + 1.3
			BatchKit.bx("op", xf, Vector3(-gw, y - 0.25, pz - gw), Vector3(gw, y, pz + gw), timber)
			var rx := -gw
			while rx <= gw + 0.01:
				for f2: int in 4:
					var rp := Vector3(rx, 0.0, gw) if f2 == 0 else (Vector3(rx, 0.0, -gw) if f2 == 1 else (Vector3(gw, 0.0, rx) if f2 == 2 else Vector3(-gw, 0.0, rx)))
					BatchKit.box("op_d", xf, Vector3(rp.x, y + 0.55, pz + rp.z), Vector3(0.1, 1.1, 0.1), timber)
				rx += 0.8
			for f3: int in 4:
				var rr := Vector3(0.0, y + 1.1, gw) if f3 == 0 else (Vector3(0.0, y + 1.1, -gw) if f3 == 1 else (Vector3(gw, y + 1.1, 0.0) if f3 == 2 else Vector3(-gw, y + 1.1, 0.0)))
				var sz := Vector3(gw * 2.0, 0.1, 0.14) if f3 < 2 else Vector3(0.14, 0.1, gw * 2.0)
				BatchKit.box("op_d", xf, rr + Vector3(0.0, 0.0, pz), sz, timber)
		y += h
		if k < 6:
			_pent("op", xf, -hw, hw, pz - hw, pz + hw, y + 0.6, y - 0.5, 2.6, roof)
			BatchKit.bx("op", xf, Vector3(-hw, y, pz - hw), Vector3(hw, y + 0.7, pz + hw), timber)
			y += 0.7
		w -= 0.55
	# pyramid roof, ringed spire, chains
	var hw2 := w * 0.5 + 0.55
	BatchKit.prism("op", xf, Vector3(0.0, y, pz), (hw2 + 2.8) * 1.414, 0.4, 4.8, 4, roof, PI * 0.25)
	var sy := y + 4.6
	BatchKit.prism("op", xf, Vector3(0.0, sy, pz), 0.7, 0.6, 0.8, 8, roof.darkened(0.2))
	for r in 7:
		BatchKit.prism("op", xf, Vector3(0.0, sy + 0.8 + r * 0.75, pz), 0.62 - r * 0.05, 0.62 - r * 0.05, 0.3, 10, Color(0.45, 0.42, 0.36))
		BatchKit.prism("op", xf, Vector3(0.0, sy + 1.1 + r * 0.75, pz), 0.22, 0.22, 0.45, 6, Color(0.45, 0.42, 0.36))
	BatchKit.sphere("op", xf, Vector3(0.0, sy + 6.6, pz), 0.45, Color(0.45, 0.42, 0.36))
	BatchKit.prism("op", xf, Vector3(0.0, sy + 7.0, pz), 0.08, 0.02, 1.6, 4, Color(0.45, 0.42, 0.36))
	var top := Vector3(0.0, sy + 5.6, pz)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var corner := Vector3(cx * (hw2 + 2.4), y + 0.4, pz + cz * (hw2 + 2.4))
			var mid := (top + corner) * 0.5
			var L := top.distance_to(corner)
			var dirv := (corner - top).normalized()
			var b := Basis.looking_at(dirv, Vector3.UP if absf(dirv.y) < 0.99 else Vector3.RIGHT)
			RoadSignBuilder._box(BatchKit.s("op_d"), xf * Transform3D(b, mid), Vector3(0.06, 0.06, L), Color(0.20, 0.20, 0.20))
	# yellow-walled hall in front, lower wings, stone screen wall, quay with red railing
	var yellow := Color(0.86, 0.70, 0.28)
	BatchKit.bx("op", xf, Vector3(-9.0, 0.0, -4.0), Vector3(9.0, 0.7, 7.0), GRANITE)
	BatchKit.bx("op", xf, Vector3(-8.5, 0.7, -3.5), Vector3(8.5, 8.0, 6.5), yellow)
	BatchKit.arch("op_d", xf, Vector3(0.0, 0.7, 6.5), 3.4, 4.6, Vector3.BACK, Color(0.80, 0.78, 0.72), false, 0.04)
	BatchKit.arch("op_d", xf, Vector3(0.0, 0.7, 6.5), 2.6, 4.1, Vector3.BACK, Color(0.10, 0.09, 0.08), false, 0.08)
	BatchKit.disc("op_d", xf, Vector3(5.2, 3.6, 6.5), 1.3, Vector3.BACK, Color(0.80, 0.78, 0.72), 0.04)
	BatchKit.disc("op_d", xf, Vector3(5.2, 3.6, 6.5), 1.0, Vector3.BACK, Color(0.18, 0.16, 0.14), 0.08)
	BatchKit.bx("op_d", xf, Vector3(-1.8, 5.8, 6.52), Vector3(1.8, 6.9, 6.62), Color(0.28, 0.22, 0.16))
	BatchKit.label(parent, xf, "壕 股 塔", Vector3(0.0, 6.35, 6.66), 0.0, 64, 0.016, Color(0.95, 0.82, 0.40))
	_flared("op", xf, -8.5, 8.5, -3.5, 6.5, 8.0, 10.6, roof, 1.2, 0.9)
	for sx: float in [-1.0, 1.0]:
		BatchKit.bx("op", xf, Vector3(sx * 8.5 - (6.0 if sx < 0.0 else 0.0), 0.0, -2.0), Vector3(sx * 8.5 + (6.0 if sx > 0.0 else 0.0), 5.6, 5.0), LIME)
		BatchKit.gable_x("op", xf, minf(sx * 8.5, sx * 14.5), maxf(sx * 8.5, sx * 14.5), -2.0, 5.0, 5.6, 7.2, roof, 0.6)
	BatchKit.bx("op", xf, Vector3(-15.0, 0.0, 22.0), Vector3(15.0, 4.2, 23.2), Color(0.80, 0.80, 0.77))
	BatchKit.bx("op_d", xf, Vector3(-13.6, 0.8, 23.2), Vector3(13.6, 3.6, 23.28), Color(0.72, 0.72, 0.70))
	BatchKit.bx("op_d", xf, Vector3(-12.8, 1.2, 23.28), Vector3(12.8, 3.2, 23.34), Color(0.84, 0.84, 0.82))
	BatchKit.gable_x("op", xf, -15.2, 15.2, 21.9, 23.3, 4.2, 4.9, roof, 0.3)
	BatchKit.bx("op", xf, Vector3(-17.0, 0.0, 24.0), Vector3(17.0, 0.45, 31.0), GRANITE)
	var qx := -16.6
	while qx <= 16.65:
		BatchKit.box("op_d", xf, Vector3(qx, 1.05, 30.7), Vector3(0.14, 1.2, 0.14), Color(0.58, 0.24, 0.14))
		qx += 2.4
	BatchKit.bx("op_d", xf, Vector3(-16.7, 1.55, 30.62), Vector3(16.7, 1.68, 30.78), Color(0.58, 0.24, 0.14))
	BatchKit.bx("op_d", xf, Vector3(-16.7, 0.9, 30.64), Vector3(16.7, 0.98, 30.76), Color(0.58, 0.24, 0.14))
	BatchKit.prism("em", xf, Vector3(9.0, 0.95, 30.85), 0.38, 0.38, 0.12, 10, Color(1.0, 0.45, 0.12), 0.0, true, 0.0, TAU)
	for tp: Vector3 in [Vector3(-20.0, 0.0, 8.0), Vector3(20.0, 0.0, 6.0), Vector3(-22.0, 0.0, -8.0), Vector3(22.0, 0.0, -10.0), Vector3(-19.0, 0.0, 18.0), Vector3(19.0, 0.0, 18.0)]:
		_tree(xf * tp, 1 if tp.x > 0.0 else 0, 1.1)
	BatchKit.light(parent, xf, Vector3(0.0, 6.0, 14.0), Color(1.0, 0.82, 0.55), 36.0, lights)


# ------------------------------------------------------------------------------------------------ 南湖天地
static func _district(parent: Node3D, nd: Dictionary, lights: Array) -> void:
	_jiajuan_hall(parent)
	# glass shop pavilions east of the hall (two rows) and along the south side of the axis
	var k := 0
	for py: float in [-450.0, -388.0]:
		for px: float in [819.0, 851.0, 883.0]:
			_shop_pavilion(BatchKit.xf(px, py, 0.0), 24.0, 30.0, 12.0 + float((k * 5) % 4), k, PI * 0.5 if k % 2 == 0 else -PI * 0.5)
			k += 1
	for px2: float in [733.0, 765.0, 797.0, 829.0]:
		_shop_pavilion(BatchKit.xf(px2, -283.0, 0.0), 26.0, 26.0, 11.0 + float((k * 3) % 4), k, PI)
		k += 1
	_axis_plaza(parent, lights)
	BatchKit.commit(parent, "Nanhu_Tiandi")
	_academy(BatchKit.xf(876.0, -221.0, 0.0))
	BatchKit.commit(parent, "Nanhu_Academy")
	_mall(parent, lights)
	BatchKit.commit(parent, "Nanhu_Mall")
	for hv in nd.get("lanes", []):
		if hv is Dictionary:
			_lane_house(hv)
	BatchKit.commit(parent, "Nanhu_Lanes")


static func _jiajuan_hall(parent: Node3D) -> void:
	var xf := BatchKit.xf(747.0, -412.0, 0.0)
	var brick := Color(0.70, 0.63, 0.50)
	var tile := Color(0.30, 0.29, 0.28)
	var hx := 47.0
	var hz := 50.0
	var eave := 7.5
	BatchKit.bx("op", xf, Vector3(-hx, 0.0, -hz), Vector3(hx, eave, hz), brick)
	BatchKit.bx("op_d", xf, Vector3(-hx - 0.05, 0.0, -hz - 0.05), Vector3(hx + 0.05, 0.5, hz + 0.05), Color(0.36, 0.34, 0.32))
	# sawtooth roof: 8 bays, tile slope rising south to north, north-light glazing
	var bays := 8
	var bd := hz * 2.0 / float(bays)
	for b in bays:
		var z0 := -hz + b * bd
		var z1 := z0 + bd
		BatchKit.quad("op", xf, Vector3(-hx, eave, z1), Vector3(hx, eave, z1), Vector3(hx, eave + 4.0, z0 + 0.6), Vector3(-hx, eave + 4.0, z0 + 0.6), tile, Vector3(0.0, bd, 4.0))
		BatchKit.bx("gl", xf, Vector3(-hx + 0.4, eave, z0 + 0.45), Vector3(hx - 0.4, eave + 4.0, z0 + 0.6), Color(0.40, 0.48, 0.52))
		for ex: float in [-hx, hx]:
			BatchKit.fan("op", xf, [Vector3(ex, eave, z0 + 0.45), Vector3(ex, eave, z1), Vector3(ex, eave + 4.0, z0 + 0.45)], brick, Vector3(signf(ex), 0.0, 0.0))
			# grey metal coping following the teeth
			var L := Vector2(bd - 0.45, 4.0).length()
			var mid := Vector3(ex, eave + 2.05, (z0 + 0.45 + z1) * 0.5)
			var ang := atan2(4.0, bd - 0.45)
			RoadSignBuilder._box(BatchKit.s("op"), xf * Transform3D(Basis(Vector3.RIGHT, ang), mid), Vector3(0.6, 0.25, L), Color(0.46, 0.47, 0.48))
			BatchKit.box("op", xf, Vector3(ex, eave + 2.0, z0 + 0.5), Vector3(0.6, 4.2, 0.3), Color(0.46, 0.47, 0.48))
	BatchKit.bx("gl", xf, Vector3(-12.0, eave + 3.6, -16.0), Vector3(12.0, eave + 4.4, 16.0), Color(0.60, 0.70, 0.76))
	# big black-framed shop windows in the brick walls
	var wx := -hx + 5.0
	while wx < hx - 3.0:
		for zf: float in [-hz, hz]:
			var s := signf(zf)
			BatchKit.bx("op_d", xf, Vector3(wx - 2.4, 0.5, zf - s * 0.02), Vector3(wx + 2.4, 5.6, zf + s * 0.10), Color(0.10, 0.10, 0.11))
			BatchKit.bx("gl", xf, Vector3(wx - 2.1, 0.7, zf + s * 0.10), Vector3(wx + 2.1, 5.3, zf + s * 0.14), Color(0.34, 0.40, 0.42))
		wx += 8.0
	var wz := -hz + 5.0
	while wz < hz - 3.0:
		for xf2: float in [-hx, hx]:
			var s2 := signf(xf2)
			BatchKit.bx("op_d", xf, Vector3(xf2 - s2 * 0.02, 0.5, wz - 2.4), Vector3(xf2 + s2 * 0.10, 5.6, wz + 2.4), Color(0.10, 0.10, 0.11))
			BatchKit.bx("gl", xf, Vector3(xf2 + s2 * 0.10, 0.7, wz - 2.1), Vector3(xf2 + s2 * 0.14, 5.3, wz + 2.1), Color(0.34, 0.40, 0.42))
		wz += 8.0
	BatchKit.label(parent, xf, "嘉 绢 印 象", Vector3(0.0, 6.4, hz + 0.2), 0.0, 120, 0.03, Color(0.95, 0.92, 0.84))
	# the old silk mill chimney
	BatchKit.prism("op", xf, Vector3(hx - 6.0, 0.0, -hz - 6.0), 1.9, 1.2, 32.0, 12, Color(0.58, 0.32, 0.24))
	for r in 3:
		BatchKit.prism("op_d", xf, Vector3(hx - 6.0, 26.0 + r * 1.6, -hz - 6.0), 1.45 - r * 0.05, 1.45 - r * 0.05, 0.4, 12, Color(0.86, 0.84, 0.80))


# glass shop pavilion (two-to-three storeys) with butterfly fascia on the front and back, gold louvres on the
# sides; `face` turns the front
static func _shop_pavilion(xf0: Transform3D, w: float, d: float, h: float, k: int, face: float) -> void:
	var xf := xf0 * Transform3D(Basis(Vector3.UP, face), Vector3.ZERO)
	var hw := w * 0.5
	var hd := d * 0.5
	var metal := Color(0.40, 0.42, 0.45)
	var gold := Color(0.74, 0.62, 0.42)
	var glass := Color(0.55, 0.66, 0.78)
	BatchKit.bx("op", xf, Vector3(-hw, 0.0, -hd), Vector3(hw, h, hd), metal)
	for zf: float in [-hd, hd]:
		var s := signf(zf)
		BatchKit.bx("gl", xf, Vector3(-hw + 1.2, 0.3, zf + s * 0.05), Vector3(hw - 1.2, h - 0.6, zf + s * 0.12), glass if (k + int(s)) % 3 != 0 else glass.darkened(0.25))
		var m := -hw + 1.2 + 2.4
		while m < hw - 1.3:
			BatchKit.bx("op_d", xf, Vector3(m - 0.08, 0.3, zf + s * 0.12), Vector3(m + 0.08, h - 0.6, zf + s * 0.22), metal.darkened(0.2))
			m += 2.4
		BatchKit.bx("op_d", xf, Vector3(-hw + 1.2, 4.2, zf + s * 0.12), Vector3(hw - 1.2, 4.5, zf + s * 0.24), metal.darkened(0.2))
		# butterfly fascia: rising toward both corners
		for side: float in [-1.0, 1.0]:
			var a := Vector3(0.0, h - 0.2, zf + s * 0.3)
			var b := Vector3(side * (hw + 0.6), h + 1.8, zf + s * 0.3)
			var mid := (a + b) * 0.5
			var L := a.distance_to(b)
			var ang := atan2(b.y - a.y, absf(b.x - a.x)) * side
			RoadSignBuilder._box(BatchKit.s("op"), xf * Transform3D(Basis(Vector3.BACK, ang), mid), Vector3(L, 0.5, 0.7), metal.darkened(0.35))
		if k % 2 == 0:
			var g := -hw + 1.6
			while g < hw - 1.4:
				BatchKit.bx("op_d", xf, Vector3(g - 0.12, h * 0.35, zf + s * 0.24), Vector3(g + 0.12, h - 0.8, zf + s * 0.5), gold)
				g += 0.9
	for xf2: float in [-hw, hw]:
		var s2 := signf(xf2)
		var g2 := -hd + 0.8
		while g2 < hd - 0.6:
			BatchKit.bx("op_d", xf, Vector3(xf2 + s2 * 0.02, 1.0, g2 - 0.12), Vector3(xf2 + s2 * 0.32, h - 0.8, g2 + 0.12), gold if k % 3 != 1 else metal.lightened(0.1))
			g2 += 0.7
	BatchKit.bx("op", xf, Vector3(-hw - 0.4, h - 0.2, -hd - 0.4), Vector3(hw + 0.4, h + 0.2, hd + 0.4), metal.darkened(0.3))


static func _axis_plaza(parent: Node3D, lights: Array) -> void:
	var I := Transform3D.IDENTITY
	var y0 := -323.5
	BatchKit.bx("op", I, Vector3(704.0, 0.0, -342.0), Vector3(925.0, 0.08, -305.0), Color(0.70, 0.70, 0.68))
	# water channel with granite kerbs and small jets, lawns and flower strips either side, trees
	BatchKit.bx("op", I, Vector3(778.0, 0.08, y0 - 2.2), Vector3(902.0, 0.34, y0 + 2.2), Color(0.56, 0.56, 0.54))
	BatchKit.bx("gl", I, Vector3(778.5, 0.30, y0 - 1.6), Vector3(901.5, 0.36, y0 + 1.6), Color(0.16, 0.26, 0.30))
	var jx := 782.0
	while jx < 900.0:
		BatchKit.box("em_d", I, Vector3(jx, 0.62, y0), Vector3(0.12, 0.6, 0.12), Color(0.86, 0.92, 0.96))
		jx += 6.0
	for s: float in [-1.0, 1.0]:
		BatchKit.bx("op", I, Vector3(782.0, 0.08, y0 + s * 2.6), Vector3(900.0, 0.42, y0 + s * 8.0), Color(0.30, 0.48, 0.20))
		BatchKit.bx("op_d", I, Vector3(782.0, 0.42, y0 + s * 6.2), Vector3(900.0, 0.62, y0 + s * 7.6), Color(0.86, 0.40, 0.20) if s < 0.0 else Color(0.90, 0.72, 0.24))
		var tx := 786.0
		while tx < 900.0:
			_tree(Vector3(tx, 0.0, y0 + s * 13.0), 0, 0.9)
			tx += 14.0
	# red ribbed sculpture on its dark pedestal
	var sc := Vector3(770.0, 0.0, y0)
	BatchKit.bx("op", I, sc + Vector3(-2.4, 0.0, -2.4), sc + Vector3(2.4, 3.0, 2.4), Color(0.16, 0.16, 0.17))
	BatchKit.bx("em_d", I, sc + Vector3(2.42, 1.0, -1.6), sc + Vector3(2.48, 2.2, 1.6), Color(0.92, 0.55, 0.25))
	var red := Color(0.86, 0.10, 0.10)
	for rib in 12:
		var a := TAU * float(rib) / 12.0
		var prev := Vector3.ZERO
		for t in 9:
			var u := float(t) / 8.0
			var r := 2.0 * sin(PI * minf(u * 1.15, 1.0)) + 0.4 * (1.0 - u)
			var p := sc + Vector3(cos(a) * r, 3.0 + u * 8.5, sin(a) * r)
			if t > 0:
				var mid := (p + prev) * 0.5
				var L := p.distance_to(prev)
				var dv := (p - prev).normalized()
				var bas := Basis.looking_at(dv, Vector3(cos(a), 0.0, sin(a)))
				RoadSignBuilder._box(BatchKit.s("op"), Transform3D(bas, mid), Vector3(0.12, 0.45, L + 0.05), red)
			prev = p
	BatchKit.prism("op", I, sc + Vector3(0.0, 11.4, 0.0), 0.12, 0.02, 1.4, 6, red)
	# NANHU PLACE letters at the east entrance (facing 南湖路)
	var lx := 914.0
	BatchKit.bx("op", I, Vector3(lx - 2.5, 0.0, y0 - 11.0), Vector3(lx + 1.0, 0.9, y0 + 11.0), Color(0.24, 0.24, 0.25))
	BatchKit.bx("op", I, Vector3(lx - 3.0, 0.0, y0 - 12.0), Vector3(lx + 2.0, 0.45, y0 + 12.0), Color(0.80, 0.80, 0.78))
	# seen from the east the viewer's left is +Z: NANHU on the left, 南湖天地 over PLACE on the right
	JiaxingLandmarks._add_sign_label(parent, "NANHU", Vector3(lx + 1.05, 2.2, y0 + 5.8), PI * 0.5, 220, 0.016, Color(0.86, 0.86, 0.84))
	JiaxingLandmarks._add_sign_label(parent, "南湖天地", Vector3(lx + 1.05, 3.0, y0 - 5.6), PI * 0.5, 120, 0.016, Color(0.86, 0.86, 0.84))
	JiaxingLandmarks._add_sign_label(parent, "PLACE", Vector3(lx + 1.05, 1.3, y0 - 5.6), PI * 0.5, 120, 0.016, Color(0.86, 0.86, 0.84))
	# lakeside viewing terrace at the west end
	BatchKit.prism("op", I, Vector3(712.0, 0.0, y0), 9.0, 9.0, 0.45, 24, Color(0.74, 0.73, 0.70))
	for k in 20:
		var a2 := PI * 0.5 + PI * float(k) / 19.0
		BatchKit.box("op_d", I, Vector3(712.0 + cos(a2) * 8.6, 1.0, y0 + sin(a2) * 8.6), Vector3(0.12, 1.1, 0.12), Color(0.30, 0.30, 0.32))
	BatchKit.light(parent, I, Vector3(820.0, 6.0, y0), Color(1.0, 0.88, 0.70), 50.0, lights)


static func _academy(xf: Transform3D) -> void:
	var roof := TILE
	for s: float in [-1.0, 1.0]:
		BatchKit.bx("op", xf, Vector3(s * 28.0 - 0.4, 0.0, -40.0), Vector3(s * 28.0 + 0.4, 3.4, 40.0), LIME)
		BatchKit.bx("op", xf, Vector3(s * 28.0 - 0.7, 3.4, -40.3), Vector3(s * 28.0 + 0.7, 3.8, 40.3), roof)
		BatchKit.bx("op", xf, Vector3(-28.0, 0.0, s * 40.0 - 0.4), Vector3(28.0, 3.4, s * 40.0 + 0.4), LIME)
		BatchKit.bx("op", xf, Vector3(-28.3, 3.4, s * 40.0 - 0.7), Vector3(28.3, 3.8, s * 40.0 + 0.7), roof)
		BatchKit.bx("op", xf, Vector3(s * 23.0 - 3.5, 0.0, -24.0), Vector3(s * 23.0 + 3.5, 4.6, 24.0), LIME)
		BatchKit.gable_z("op", xf, s * 23.0 - 3.5, s * 23.0 + 3.5, -24.0, 24.0, 4.6, 6.8, roof, 0.6)
	for hall: Array in [[-32.0, -18.0, 12.0, 7.4], [-6.0, 4.0, 10.0, 6.2], [26.0, 34.0, 6.0, 5.2]]:
		var z0: float = hall[0]
		var z1: float = hall[1]
		var hw: float = hall[2]
		var hh: float = hall[3]
		BatchKit.bx("op", xf, Vector3(-hw, 0.0, z0), Vector3(hw, 0.6, z1), GRANITE)
		BatchKit.bx("op", xf, Vector3(-hw + 0.8, 0.6, z0 + 0.8), Vector3(hw - 0.8, hh, z1 - 0.8), Color(0.42, 0.20, 0.14))
		var cx := -hw + 1.0
		while cx <= hw - 0.9:
			BatchKit.prism("op_d", xf, Vector3(cx, 0.6, z1 - 0.5), 0.2, 0.18, hh - 0.6, 6, RED_COL)
			cx += 3.0
		_flared("op", xf, -hw, hw, z0, z1, hh, hh + 3.4, roof, 1.4, 0.8)
	for tp: Vector3 in [Vector3(-12.0, 0.0, -8.0), Vector3(12.0, 0.0, -8.0), Vector3(-12.0, 0.0, 16.0), Vector3(12.0, 0.0, 16.0)]:
		_tree(xf * tp, 1 if tp.z < 0.0 else 0, 0.9)


static func _mall(parent: Node3D, lights: Array) -> void:
	var xf := BatchKit.xf(1040.0, -165.0, 0.1)
	var white := Color(0.92, 0.91, 0.88)
	var glass := Color(0.62, 0.72, 0.80)
	var roof := Color(0.32, 0.30, 0.28)
	var wood := Color(0.70, 0.56, 0.40)
	# two-storey glass base the whole length with white fins
	BatchKit.bx("gl", xf, Vector3(-42.0, 0.0, -128.0), Vector3(42.0, 10.0, 128.0), glass)
	var fz := -127.0
	while fz <= 127.5:
		BatchKit.bx("op_d", xf, Vector3(-42.4, 0.0, fz - 0.15), Vector3(-41.9, 10.0, fz + 0.15), white)
		BatchKit.bx("op_d", xf, Vector3(41.9, 0.0, fz - 0.15), Vector3(42.4, 10.0, fz + 0.15), white)
		fz += 3.0
	BatchKit.bx("op", xf, Vector3(-43.0, 9.8, -129.0), Vector3(43.0, 10.6, 129.0), white)
	BatchKit.bx("em", xf, Vector3(-43.1, 0.4, -127.0), Vector3(-43.0, 0.6, 127.0), Color(1.0, 0.86, 0.62))
	# volumes on the podium, each under a flared roof
	var vols := [[-126.0, -74.0, 26.0, 0], [-64.0, -8.0, 22.0, 1], [2.0, 66.0, 28.0, 0], [76.0, 126.0, 20.0, 2]]
	for v: Array in vols:
		var z0: float = v[0]
		var z1: float = v[1]
		var top: float = v[2]
		var kind: int = v[3]
		if kind == 0:
			BatchKit.bx("op", xf, Vector3(-36.0, 10.6, z0), Vector3(36.0, top, z1), white)
			var lz := z0 + 1.0
			while lz < z1:
				BatchKit.bx("op_d", xf, Vector3(-36.5, 12.0, lz - 0.2), Vector3(-36.0, top - 1.2, lz + 0.2), white.darkened(0.06))
				BatchKit.bx("op_d", xf, Vector3(36.0, 12.0, lz - 0.2), Vector3(36.5, top - 1.2, lz + 0.2), white.darkened(0.06))
				lz += 1.2
			BatchKit.bx("op_d", xf, Vector3(-36.6, 10.6, z0 + 3.0), Vector3(-36.0, 12.0, z1 - 3.0), wood)
			_flared("op", xf, -36.0, 36.0, z0, z1, top, top + 7.0, roof, 4.0, 2.4)
			BatchKit.bx("op_d", xf, Vector3(-40.0, top - 0.6, z0 - 4.0), Vector3(40.0, top - 0.4, z1 + 4.0), wood)
		elif kind == 1:
			BatchKit.bx("gl", xf, Vector3(-32.0, 10.6, z0), Vector3(32.0, top, z1), glass.lightened(0.08))
			# LED wall facing 南湖路 (flower-like gradient, no text)
			var cols := [Color(0.55, 0.70, 0.98), Color(0.80, 0.88, 1.0), Color(0.62, 0.55, 0.95), Color(0.92, 0.95, 1.0)]
			for gz in 6:
				for gy in 3:
					var c: Color = cols[(gz * 2 + gy) % cols.size()]
					BatchKit.bx("em", xf, Vector3(-32.25, 12.0 + gy * 3.0, z0 + 6.0 + gz * 7.0), Vector3(-32.1, 15.0 + gy * 3.0, z0 + 13.0 + gz * 7.0), c)
			_flared("op", xf, -32.0, 32.0, z0, z1, top, top + 5.0, roof, 3.0, 1.8)
			BatchKit.label(parent, xf, "南 湖 天 地", Vector3(-32.3, 8.0, (z0 + z1) * 0.5), -PI * 0.5, 160, 0.03, Color(0.98, 0.95, 0.88))
		else:
			# glass hall under a sawtooth glass roof, roof garden trees
			BatchKit.bx("gl", xf, Vector3(-34.0, 10.6, z0), Vector3(34.0, top, z1), glass)
			var sz := z0
			while sz < z1 - 0.5:
				BatchKit.quad("gl", xf, Vector3(-34.0, top, sz + 5.0), Vector3(34.0, top, sz + 5.0), Vector3(34.0, top + 3.0, sz), Vector3(-34.0, top + 3.0, sz), Color(0.70, 0.80, 0.86), Vector3(0.0, 5.0, 3.0))
				BatchKit.bx("op_d", xf, Vector3(-34.0, top, sz - 0.1), Vector3(34.0, top + 3.0, sz + 0.1), white)
				sz += 5.0
	# roof gardens between the volumes
	for gz2: float in [-69.0, -3.0, 71.0]:
		BatchKit.bx("op", xf, Vector3(-30.0, 10.6, gz2 - 3.0), Vector3(30.0, 11.2, gz2 + 3.0), Color(0.30, 0.46, 0.22))
	for tp: Vector3 in [Vector3(-48.0, 0.0, -100.0), Vector3(-48.0, 0.0, -40.0), Vector3(-48.0, 0.0, 30.0), Vector3(-48.0, 0.0, 100.0)]:
		_tree(xf * tp, 2 if int(tp.z) % 3 == 0 else 0, 1.0)
	# entrances and shop boards along the 南湖路 front
	var ents := [-100.0, -36.0, 34.0, 100.0]
	for i in ents.size():
		var ez: float = ents[i]
		BatchKit.entrance(parent, xf, Vector3(-42.4, 0.0, ez), Vector3.LEFT, 8.0, "南湖天地" if i == 1 else "")
		if i < ents.size() - 1:
			BatchKit.shop_signs(parent, xf, Vector3(-42.6, 0.0, ez + 7.0), Vector3(-42.6, 0.0, float(ents[i + 1]) - 7.0), Vector3.LEFT, 5.4, i * 5 + 2)
	BatchKit.light(parent, xf, Vector3(-50.0, 8.0, 0.0), Color(1.0, 0.88, 0.70), 60.0, lights)


static func _lane_house(h: Dictionary) -> void:
	var c := _v(h["c"])
	var f := float(h.get("f", 1.0))
	var xf := BatchKit.xf(c.x, c.z, 0.0 if f > 0.0 else PI)
	var hl := float(h["l"]) * 0.5
	var hd := float(h["d"]) * 0.5
	var H := float(h["h"])
	var wall := Color(0.62, 0.50, 0.40) if int(h.get("brick", 0)) == 1 else LIME.darkened(float(_hash(c.x, c.z) % 5) * 0.03)
	BatchKit.bx("op", xf, Vector3(-hl, 0.0, -hd), Vector3(hl, H, hd), wall)
	BatchKit.bx("op_d", xf, Vector3(-hl - 0.05, 0.0, -hd - 0.05), Vector3(hl + 0.05, 0.45, hd + 0.05), Color(0.40, 0.40, 0.39))
	BatchKit.gable_x("op", xf, -hl, hl, -hd, hd, H, H + 2.6, TILE, 0.5)
	for s: float in [-1.0, 1.0]:
		BatchKit.fan("op", xf, [Vector3(s * hl, H, -hd), Vector3(s * hl, H, hd), Vector3(s * hl, H + 2.6, 0.0)], wall, Vector3(s, 0.0, 0.0))
	# shop front glazing and upper windows on the lane side
	BatchKit.bx("op_d", xf, Vector3(-hl + 0.8, 0.4, hd - 0.02), Vector3(hl - 0.8, 3.4, hd + 0.08), Color(0.12, 0.12, 0.13))
	BatchKit.bx("gl", xf, Vector3(-hl + 1.0, 0.5, hd + 0.08), Vector3(hl - 1.0, 3.2, hd + 0.12), Color(0.30, 0.36, 0.38))
	var wx := -hl + 2.0
	while wx < hl - 1.5:
		BatchKit.bx("op_d", xf, Vector3(wx - 0.6, H - 3.0, hd - 0.02), Vector3(wx + 0.6, H - 1.0, hd + 0.08), Color(0.16, 0.16, 0.18))
		wx += 3.0


# ------------------------------------------------------------------------------------------------ 凯悦
static func _hotel_floors(xf: Transform3D, x0: float, x1: float, z0: float, z1: float, floors: int, fh: float, fin_from: int) -> void:
	var slab := Color(0.80, 0.68, 0.54)
	var glass := Color(0.30, 0.38, 0.45)
	for f in floors:
		var y := float(f) * fh
		BatchKit.bx("gl", xf, Vector3(x0 - 0.05, y + 0.6, z0 - 0.05), Vector3(x1 + 0.05, y + fh - 0.3, z1 + 0.05), glass)
		BatchKit.bx("op", xf, Vector3(x0 - 0.45, y + fh - 0.4, z0 - 0.45), Vector3(x1 + 0.45, y + fh + 0.05, z1 + 0.45), slab)
	var fy0 := float(fin_from) * fh
	var fy1 := float(floors) * fh
	for zf: float in [z0, z1]:
		var s := -1.0 if zf == z0 else 1.0
		var x := x0 + 0.6
		while x < x1 - 0.3:
			BatchKit.bx("op", xf, Vector3(x - 0.16, fy0, zf + s * 0.1), Vector3(x + 0.16, fy1, zf + s * 0.95), BRONZE)
			x += 1.1
	for xf2: float in [x0, x1]:
		var s2 := -1.0 if xf2 == x0 else 1.0
		var z := z0 + 0.6
		while z < z1 - 0.3:
			BatchKit.bx("op", xf, Vector3(xf2 + s2 * 0.1, fy0, z - 0.16), Vector3(xf2 + s2 * 0.95, fy1, z + 0.16), BRONZE)
			z += 1.1


static func _swept_roof(xf: Transform3D, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var col := Color(0.30, 0.27, 0.24)
	BatchKit.bx("op", xf, Vector3(x0 - 1.4, y, z0 - 1.4), Vector3(x1 + 1.4, y + 0.5, z1 + 1.4), col)
	for cx: float in [x0 - 1.4, x1 + 1.4]:
		for cz: float in [z0 - 1.4, z1 + 1.4]:
			var sx := 1.0 if cx > x0 else -1.0
			var sz := 1.0 if cz > z0 else -1.0
			var tip := Vector3(cx + sx * 1.0, y + 1.6, cz + sz * 1.0)
			BatchKit.fan("op", xf, [Vector3(cx - sx * 6.0, y + 0.5, cz), Vector3(cx, y + 0.5, cz - sz * 6.0), tip], col, Vector3(sx, 1.0, sz))
			BatchKit.fan("op", xf, [Vector3(cx - sx * 6.0, y, cz), Vector3(cx, y, cz - sz * 6.0), tip], col, Vector3(sx, -1.0, sz))
	BatchKit.bx("em", xf, Vector3(x0 - 1.45, y - 0.12, z0 - 1.45), Vector3(x1 + 1.45, y, z0 - 1.35), Color(1.0, 0.80, 0.50))


static func _hyatt_regency(parent: Node3D, lights: Array) -> void:
	var xf := BatchKit.xf(930.0, -560.0, 0.5)
	var hx := 35.0
	var hz := 30.0
	var fh := 4.0
	var floors := 6
	# courtyard block: four wings round a garden court
	_hotel_floors(xf, -hx, hx, -hz, -hz + 14.0, floors, fh, 3)
	_hotel_floors(xf, -hx, hx, hz - 14.0, hz, floors, fh, 3)
	_hotel_floors(xf, -hx, -hx + 14.0, -hz + 14.0, hz - 14.0, floors, fh, 3)
	_hotel_floors(xf, hx - 14.0, hx, -hz + 14.0, hz - 14.0, floors, fh, 3)
	BatchKit.bx("op", xf, Vector3(-hx + 14.0, 0.0, -hz + 14.0), Vector3(hx - 14.0, 0.3, hz - 14.0), Color(0.30, 0.46, 0.22))
	_swept_roof(xf, -hx, hx, -hz, hz, floors * fh)
	# porte-cochere on the west (南湖路) side, reflecting pool with the boat sculpture and a pine
	BatchKit.bx("op", xf, Vector3(-hx - 16.0, 6.0, -14.0), Vector3(-hx, 7.4, 14.0), Color(0.74, 0.66, 0.58))
	BatchKit.bx("em", xf, Vector3(-hx - 16.1, 5.9, -14.1), Vector3(-hx, 6.0, 14.1), Color(1.0, 0.84, 0.60))
	for cz: float in [-12.0, -4.0, 4.0, 12.0]:
		BatchKit.bx("op", xf, Vector3(-hx - 14.6, 0.0, cz - 0.45), Vector3(-hx - 13.7, 6.0, cz + 0.45), Color(0.70, 0.62, 0.55))
	BatchKit.bx("gl", xf, Vector3(-hx - 30.0, 0.0, -12.0), Vector3(-hx - 18.0, 0.35, 12.0), Color(0.06, 0.08, 0.10))
	var bow := [Vector3(-hx - 28.0, 0.35, -10.0), Vector3(-hx - 20.0, 0.35, 9.0), Vector3(-hx - 24.0, 3.2, 10.5)]
	BatchKit.fan("op", xf, bow, Color(0.16, 0.17, 0.19), Vector3(1.0, 0.2, -0.5))
	_tree(xf * Vector3(-hx - 22.0, 0.0, 0.0), 0, 0.7)
	BatchKit.label(parent, xf, "HYATT REGENCY", Vector3(-hx - 0.8, floors * fh - 2.6, 0.0), -PI * 0.5, 150, 0.03, Color(0.92, 0.92, 0.96))
	BatchKit.label(parent, xf, "嘉兴南湖凯悦酒店", Vector3(-hx - 16.2, 6.7, 0.0), -PI * 0.5, 90, 0.022, Color(0.95, 0.88, 0.70))
	BatchKit.light(parent, xf, Vector3(-hx - 8.0, 5.0, 0.0), Color(1.0, 0.84, 0.62), 36.0, lights)


static func _hyatt_place(parent: Node3D, lights: Array) -> void:
	var xf := BatchKit.xf(1040.0, -430.0, 0.43)
	var hx := 25.0
	var hz := 55.0
	var fh := 4.0
	var floors := 6
	_hotel_floors(xf, -hx, hx, -hz, hz, floors, fh, 1)
	# lobby glazing glowing at the base, two horizontal glass bands on the tram side
	BatchKit.bx("em", xf, Vector3(hx + 0.8, 0.6, -hz + 4.0), Vector3(hx + 0.9, 3.4, hz - 4.0), Color(0.95, 0.78, 0.50))
	for y: float in [9.0, 13.0]:
		BatchKit.bx("gl", xf, Vector3(hx + 0.8, y, -hz + 18.0), Vector3(hx + 1.0, y + 2.4, hz - 2.0), Color(0.28, 0.34, 0.40))
	# roof edge rising to a shallow gable on the long sides, swept corners
	_swept_roof(xf, -hx, hx, -hz, hz, floors * fh)
	for xs: float in [-hx - 1.4, hx + 1.4]:
		BatchKit.fan("op", xf, [Vector3(xs, floors * fh + 0.5, -hz - 1.4), Vector3(xs, floors * fh + 0.5, hz + 1.4), Vector3(xs, floors * fh + 2.6, 0.0)], Color(0.30, 0.27, 0.24), Vector3(signf(xs), 0.0, 0.0))
	BatchKit.label(parent, xf, "凯悦嘉轩酒店", Vector3(hx + 1.1, floors * fh - 2.2, 22.0), PI * 0.5, 150, 0.03, Color(0.98, 0.96, 0.92))
	BatchKit.label(parent, xf, "HYATT PLACE", Vector3(hx + 1.1, floors * fh - 2.2, -24.0), PI * 0.5, 140, 0.03, Color(0.98, 0.96, 0.92))
	BatchKit.light(parent, xf, Vector3(hx + 6.0, 4.0, 0.0), Color(1.0, 0.84, 0.62), 40.0, lights)
