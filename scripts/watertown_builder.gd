class_name WatertownBuilder
extends RefCounted

# 月河历史街区 — Jiangnan canal town after photos of the real quarter:
#  houses: weathered lime-washed walls with damp, greyed bases, granite plinths, dark timber board shop fronts,
#          overhanging lattice upper floors under a small pent eave, dark tile gable roofs with upturned ridge
#          ends; about half with stepped 马头墙 fire gables capped in black tile
#  lanes:  pedestrian granite-slab lanes (no traffic), vertical blade shop signs, red lanterns at the shops,
#          strings of coloured paper lanterns over the main lanes, the stone 花鸟坊 memorial archway
#  canal:  granite block embankments (wet lower courses), 河埠头 steps down to the water, covered 廊棚 arcades
#          with lanterns and 美人靠 benches where houses back onto the water, weeping willows
# Geometry is batched per 120 m cell into a far layer (walls, roofs, gables, banks) and a near layer (boards,
# lattices, signs, lanterns) with visibility ranges.

const CELL := 120.0
const FAR_RANGE := 900.0
const NEAR_RANGE := 180.0

const TILE := Color(0.14, 0.15, 0.16)
const TILE_CAP := Color(0.09, 0.09, 0.10)
const WOOD := Color(0.27, 0.18, 0.13)
const WOOD_LT := Color(0.42, 0.30, 0.21)
const PLINTH := Color(0.42, 0.42, 0.41)
const GRANITE := Color(0.60, 0.56, 0.50)
const GRANITE_WET := Color(0.40, 0.38, 0.34)
const RED := Color(0.86, 0.12, 0.08)

static var _cells := {}


static func build(parent: Node3D, data: Dictionary, lights: Array) -> void:
	_cells = {}
	var labels := Node3D.new()
	labels.name = "WatertownSigns"
	parent.add_child(labels)
	var trees := Node3D.new()
	trees.name = "WatertownWillows"
	parent.add_child(trees)
	var k := 0
	for hv in data.get("houses", []):
		if hv is Dictionary:
			_house(hv, labels, k)
			k += 1
	for bv in data.get("banks", []):
		if bv is Dictionary:
			_bank(bv, trees)
	_lantern_strings(data.get("alleys", []), data.get("paifang", {}))
	var pf: Dictionary = data.get("paifang", {})
	if not pf.is_empty():
		_paifang(_v(pf["pos"]), float(pf.get("angle", 0.0)), labels)
	_ground(parent)
	_commit(parent)
	_cells = {}


# granite-slab ground over the quarter's land (the generic pale pavement base used to show between the houses);
# above the base, below parks (0.014), water (0.026) and streets
static func _ground(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "WatertownStoneGround"
	var pm := PlaneMesh.new()
	pm.size = Vector2(530.0, 430.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/plaza_surface.gdshader") as Shader
	m.set_shader_parameter("base_col", Color(0.39, 0.39, 0.38))
	m.set_shader_parameter("rough_val", 0.72)
	# depth push between the water (0.17) and the pale base ground (0.42): the canals draw over the slabs,
	# the slabs over the base
	m.set_shader_parameter("depth_push", 0.30)
	m.set_shader_parameter("depth_slope", 0.0014)
	mi.material_override = m
	mi.position = Vector3(-640.0, 0.010, -2060.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), 0.0, float(a[1]))


static func _st_of(p: Vector3, layer: String) -> SurfaceTool:
	var ck := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if not _cells.has(ck):
		_cells[ck] = {}
	var c: Dictionary = _cells[ck]
	if not c.has(layer):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		c[layer] = st
	return c[layer]


static func _box(p_ref: Vector3, layer: String, xf: Transform3D, c: Vector3, size: Vector3, col: Color) -> void:
	RoadSignBuilder._box(_st_of(p_ref, layer), xf * Transform3D(Basis.IDENTITY, c), size, col)


static func _poly(p_ref: Vector3, layer: String, xf: Transform3D, pts: Array, col: Color) -> void:
	var st := _st_of(p_ref, layer)
	var w: Array = []
	for q: Vector3 in pts:
		w.append(xf * q)
	var n: Vector3 = ((w[1] as Vector3) - (w[0] as Vector3)).cross((w[2] as Vector3) - (w[0] as Vector3)).normalized()
	for i in range(1, w.size() - 1):
		for v: Vector3 in [w[0], w[i + 1], w[i]]: # clockwise about n: Godot's front face, so n lights the right side
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(v)


static func _commit(parent: Node3D) -> void:
	var op := StandardMaterial3D.new()
	op.vertex_color_use_as_albedo = true
	op.vertex_color_is_srgb = true
	op.roughness = 0.88
	op.cull_mode = BaseMaterial3D.CULL_DISABLED
	var em := StandardMaterial3D.new()
	em.vertex_color_use_as_albedo = true
	em.vertex_color_is_srgb = true
	em.emission_enabled = true
	em.emission = Color(1.0, 0.45, 0.25)
	em.emission_energy_multiplier = 0.9
	for ck: Vector2i in _cells.keys():
		var c: Dictionary = _cells[ck]
		for layer: String in c.keys():
			var mi := MeshInstance3D.new()
			mi.name = "Watertown_%s_%d_%d" % [layer, ck.x, ck.y]
			mi.mesh = (c[layer] as SurfaceTool).commit()
			mi.material_override = em if layer.begins_with("em") else op
			mi.visibility_range_end = FAR_RANGE if layer == "far" else NEAR_RANGE
			mi.visibility_range_end_margin = 20.0
			if layer != "far":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)


# ------------------------------------------------------------------------------------------------ houses
static func _house(h: Dictionary, labels: Node3D, idx: int) -> void:
	var c := _v(h["c"])
	var ang := float(h["a"])
	var X := Vector3(cos(ang), 0.0, sin(ang))
	var f: Array = h.get("f", [0.0, 1.0])
	var Z := Vector3(float(f[0]), 0.0, float(f[1])).normalized()
	if Z.cross(X).y < 0.0:
		X = -X
	var xf := Transform3D(Basis(X, Vector3.UP, Z), c)
	var L := float(h["l"]) * 2.0
	var D := float(h["w"]) * 2.0
	var H := float(h["h"])
	var seed := absi(int(c.x * 13.0 + c.z * 7.0))
	var two := H >= 5.6
	# weathered whitewash: each house its own shade between fresh lime and rain-greyed
	var wt := float(seed % 11) / 10.0
	var wall := Color(0.90, 0.89, 0.86).lerp(Color(0.70, 0.70, 0.68), wt * 0.8)
	_box(c, "far", xf, Vector3(0.0, H * 0.5, 0.0), Vector3(L, H, D), wall)
	_box(c, "far", xf, Vector3(0.0, 0.22, 0.0), Vector3(L + 0.12, 0.44, D + 0.12), PLINTH)
	_box(c, "far", xf, Vector3(0.0, 0.95, 0.0), Vector3(L + 0.03, 1.0, D + 0.03), wall.darkened(0.22).lerp(Color(0.55, 0.58, 0.52), 0.3))
	if seed % 3 == 0:
		# rain streaks down the walls
		for sx in range(3):
			var px := -L * 0.3 + float(sx) * L * 0.3
			_box(c, "near", xf, Vector3(px, H * 0.62, D * 0.5 + 0.02), Vector3(0.5, H * 0.6, 0.02), wall.darkened(0.16))
	# front: timber shop boards below, lattice gallery above (two storeys) or full-height boards (one storey)
	var fz := D * 0.5
	var fh := 3.0 if two else H - 0.5
	_box(c, "far", xf, Vector3(0.0, 0.45 + fh * 0.5, fz + 0.05), Vector3(L - 0.5, fh, 0.1), WOOD)
	var nb := int((L - 0.5) / 0.55)
	for b in range(1, nb):
		_box(c, "near", xf, Vector3(-(L - 0.5) * 0.5 + float(b) * 0.55, 0.45 + fh * 0.5, fz + 0.11), Vector3(0.04, fh - 0.2, 0.03), WOOD_LT)
	_box(c, "near", xf, Vector3(0.0, 0.45 + fh * 0.45, fz + 0.12), Vector3(1.2, fh * 0.85, 0.02), Color(0.10, 0.08, 0.07))
	if two:
		# pent eave over the shop front + overhanging lattice gallery
		var eave_xf := xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(28.0)), Vector3(0.0, 3.55, fz + 0.45))
		RoadSignBuilder._box(_st_of(c, "far"), eave_xf, Vector3(L + 0.3, 0.1, 1.1), TILE)
		var gh := H - 3.9
		if gh > 0.6:
			_box(c, "far", xf, Vector3(0.0, 3.9 + gh * 0.5, fz + 0.32), Vector3(L - 0.3, gh, 0.12), WOOD)
			_box(c, "far", xf, Vector3(0.0, 3.95, fz + 0.3), Vector3(L - 0.2, 0.12, 0.7), WOOD)
			var nl := int((L - 0.3) / 0.7)
			for li in range(nl + 1):
				_box(c, "near", xf, Vector3(-(L - 0.3) * 0.5 + float(li) * (L - 0.3) / float(maxi(1, nl)), 3.9 + gh * 0.5, fz + 0.39), Vector3(0.05, gh - 0.1, 0.03), WOOD_LT)
			for ly in [0.35, 0.7]:
				_box(c, "near", xf, Vector3(0.0, 3.9 + gh * float(ly), fz + 0.39), Vector3(L - 0.4, 0.05, 0.03), WOOD_LT)
	# gable roof along the house
	var oh := 0.45
	var rise := clampf(D * 0.36, 1.4, 3.0)
	var ry := H + rise
	var hx := L * 0.5 + 0.15
	for sgn: float in [-1.0, 1.0]:
		_poly(c, "far", xf, [Vector3(-hx, H - 0.1, sgn * (D * 0.5 + oh)), Vector3(hx, H - 0.1, sgn * (D * 0.5 + oh)), Vector3(hx, ry, 0.0), Vector3(-hx, ry, 0.0)], TILE)
	_box(c, "far", xf, Vector3(0.0, ry + 0.08, 0.0), Vector3(L + 0.4, 0.24, 0.34), TILE_CAP)
	for sgn2: float in [-1.0, 1.0]:
		var rex := xf * Transform3D(Basis(Vector3(0, 0, 1), sgn2 * deg_to_rad(-32.0)), Vector3(sgn2 * (L * 0.5 + 0.25), ry + 0.25, 0.0))
		RoadSignBuilder._box(_st_of(c, "far"), rex, Vector3(0.6, 0.18, 0.3), TILE_CAP)
	# gable ends: stepped 马头墙 fire gables or plain white gable triangles
	for gs: float in [-1.0, 1.0]:
		var gx := gs * (L * 0.5 - 0.15)
		if int(h.get("g", 0)) == 1:
			var steps := [[D + 0.2, H + rise * 0.42], [D * 0.62, H + rise * 0.82], [D * 0.26, ry + 0.75]]
			for stp: Array in steps:
				var sw := float(stp[0])
				var top := float(stp[1])
				_box(c, "far", xf, Vector3(gx, (H + top) * 0.5, 0.0), Vector3(0.32, top - H + 0.02, sw), wall)
				_box(c, "far", xf, Vector3(gx, top + 0.12, 0.0), Vector3(0.62, 0.24, sw + 0.5), TILE_CAP)
				for ez: float in [-1.0, 1.0]:
					var hxf := xf * Transform3D(Basis(Vector3(1, 0, 0), ez * deg_to_rad(30.0)), Vector3(gx, top + 0.3, ez * (sw * 0.5 + 0.3)))
					RoadSignBuilder._box(_st_of(c, "far"), hxf, Vector3(0.55, 0.16, 0.4), TILE_CAP)
		else:
			_poly(c, "far", xf, [Vector3(gx + gs * 0.17, H - 0.05, -D * 0.5), Vector3(gx + gs * 0.17, H - 0.05, D * 0.5), Vector3(gx + gs * 0.17, ry - 0.05, 0.0)], wall)
	# shops: blade sign with the name, pair of red lanterns
	var shop := str(h.get("s", ""))
	if shop != "":
		var sx2 := -L * 0.5 + 0.9
		var board_h := clampf(0.3 * float(shop.length()) + 0.4, 1.2, 2.6)
		var by := 4.2 - board_h * 0.5 if two else 3.6 - board_h * 0.5
		var dark := idx % 3 != 0
		_box(c, "near", xf, Vector3(sx2, by, fz + 0.62), Vector3(0.07, board_h, 0.58), Color(0.10, 0.10, 0.11) if dark else Color(0.46, 0.28, 0.18))
		_box(c, "near", xf, Vector3(sx2, by + board_h * 0.5 + 0.08, fz + 0.4), Vector3(0.05, 0.05, 0.6), Color(0.15, 0.15, 0.16))
		for fs: float in [1.0, -1.0]:
			var lb := Label3D.new()
			lb.text = "\n".join(shop.split(""))
			lb.font_size = 48
			lb.pixel_size = minf(0.0052, (board_h - 0.25) / (float(shop.length()) * 48.0 * 1.15))
			lb.line_spacing = -6.0
			lb.modulate = Color(0.98, 0.84, 0.36) if dark else Color(0.96, 0.92, 0.82)
			lb.outline_size = 0
			lb.visibility_range_end = 90.0
			lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var lbasis := Basis(Z * -fs, Vector3.UP, X * fs)
			lb.transform = Transform3D(lbasis, xf * Vector3(sx2 + fs * 0.045, by, fz + 0.62))
			labels.add_child(lb)
		for lx: float in [-L * 0.25, L * 0.25]:
			_box(c, "em", xf, Vector3(lx, 3.0 if two else 2.6, fz + 0.75), Vector3(0.36, 0.46, 0.36), RED)
			_box(c, "near", xf, Vector3(lx, 3.27 if two else 2.87, fz + 0.75), Vector3(0.2, 0.08, 0.2), Color(0.85, 0.70, 0.25))


# ------------------------------------------------------------------------------------------------ canal
static func _bank(b: Dictionary, trees: Node3D) -> void:
	var a := _v(b["a"])
	var e := _v(b["b"])
	var L := a.distance_to(e)
	if L < 0.5:
		return
	var dir := (e - a) / L
	var wn := Vector3(float(b["w"][0]), 0.0, float(b["w"][1])) # toward the water
	var X := dir
	var Z := wn
	if Z.cross(X).y < 0.0:
		X = -X
	var mid := (a + e) * 0.5
	var xf := Transform3D(Basis(X, Vector3.UP, Z), mid)
	# granite block embankment: wet dark lower courses, drier upper courses, pale coping stones
	_box(mid, "far", xf, Vector3(0.0, -0.45, -0.3), Vector3(L + 0.06, 0.9, 0.6), GRANITE_WET)
	_box(mid, "far", xf, Vector3(0.0, 0.17, -0.3), Vector3(L + 0.06, 0.34, 0.6), GRANITE)
	_box(mid, "far", xf, Vector3(0.0, 0.40, -0.35), Vector3(L + 0.06, 0.12, 0.85), GRANITE.lightened(0.12))
	var key := absi(int(mid.x * 3.0 + mid.z * 5.0))
	# 河埠头: stone steps down into the water now and then
	if L >= 6.0 and key % 5 == 0:
		for s in range(5):
			var sy := 0.3 - float(s) * 0.2
			_box(mid, "far", xf, Vector3(0.0, sy - 0.1, 0.25 + float(s) * 0.42), Vector3(3.2, 0.2 + float(s) * 0.2, 0.44), GRANITE.darkened(0.08 * float(s)))
	if bool(b.get("arc", false)) and L >= 2.5:
		# 廊棚: covered waterside arcade with posts on the bank edge, tile roof falling to the water,
		# 美人靠 bench rail and lanterns
		var depth := 3.2
		var ylow := 2.7
		var yhigh := 3.4
		var rxf := xf * Transform3D(Basis(Vector3.RIGHT, -atan2(yhigh - ylow, depth)), Vector3(0.0, (ylow + yhigh) * 0.5 + 0.1, -depth * 0.5))
		RoadSignBuilder._box(_st_of(mid, "far"), rxf, Vector3(L + 0.05, 0.12, depth + 0.6), TILE)
		_box(mid, "far", xf, Vector3(0.0, ylow - 0.05, -0.25), Vector3(L + 0.05, 0.18, 0.18), WOOD)
		var np := maxi(1, int(L / 3.0))
		for k in range(np + 1):
			var px := -L * 0.5 + float(k) * L / float(np)
			_box(mid, "far", xf, Vector3(px, ylow * 0.5 + 0.3, -0.25), Vector3(0.18, ylow - 0.2, 0.18), WOOD)
			if k < np:
				_box(mid, "em", xf, Vector3(px + L / float(np) * 0.5, ylow - 0.45, -0.3), Vector3(0.32, 0.4, 0.32), RED)
		_box(mid, "near", xf, Vector3(0.0, 0.85, -0.3), Vector3(L, 0.08, 0.36), WOOD_LT)
		_box(mid, "near", xf, Vector3(0.0, 0.62, -0.45), Vector3(L, 0.07, 0.5), WOOD)
	elif key % 3 == 0:
		var tp := mid - wn * 1.6
		ParkLandscapeBuilder.plant_tree(trees, tp, 5, 1.0 + 0.2 * float(key % 4) / 3.0, Color(0.36, 0.52, 0.22))


# coloured paper-lantern strings along the lanes (photo: red / yellow / blue / green / orange)
static func _lantern_strings(alleys: Array, pf: Dictionary) -> void:
	var pf_pos := _v(pf["pos"]) if pf.has("pos") else Vector3(1e9, 0.0, 1e9)
	var cols := [Color(0.95, 0.20, 0.15), Color(0.98, 0.78, 0.20), Color(0.25, 0.55, 0.95), Color(0.35, 0.85, 0.45), Color(0.98, 0.55, 0.18)]
	var k := 0
	for sg in alleys:
		var a := _v(sg[0])
		var b := _v(sg[1])
		var L := a.distance_to(b)
		if L < 14.0:
			continue
		var n := int(L / 1.3)
		for i in range(1, n):
			var p := a.lerp(b, float(i) / float(n))
			var sag := 0.35 * sin(PI * fposmod(float(i) / 8.0, 1.0))
			if p.distance_to(pf_pos) < 4.5:
				continue # keep the archway plaque clear
			var pos := p + Vector3(0.0, 4.6 - sag, 0.0)
			RoadSignBuilder._box(_st_of(pos, "em2"), Transform3D(Basis(Vector3.UP, 0.785), pos), Vector3(0.22, 0.30, 0.22), cols[k % cols.size()])
			k += 1


# 花鸟坊: grey stone memorial archway with carved lintels and a gold-lettered plaque
static func _paifang(c: Vector3, ang: float, labels: Node3D) -> void:
	var xf := Transform3D(Basis(Vector3.UP, ang + PI * 0.5), c)
	var stone := Color(0.62, 0.62, 0.60)
	var carved := Color(0.52, 0.52, 0.50)
	for px: float in [-2.6, 2.6]:
		_box(c, "far", xf, Vector3(px, 2.8, 0.0), Vector3(0.6, 5.6, 0.6), stone)
		_box(c, "far", xf, Vector3(px, 5.75, 0.0), Vector3(0.75, 0.3, 0.75), carved)
		_box(c, "far", xf, Vector3(px, 0.4, 0.0), Vector3(1.1, 0.8, 1.1), carved)
	_box(c, "far", xf, Vector3(0.0, 4.0, 0.0), Vector3(6.6, 0.5, 0.45), stone)
	_box(c, "far", xf, Vector3(0.0, 4.65, 0.0), Vector3(5.2, 0.8, 0.38), carved)
	_box(c, "far", xf, Vector3(0.0, 5.3, 0.0), Vector3(6.6, 0.45, 0.45), stone)
	_box(c, "near", xf, Vector3(0.0, 4.65, 0.2), Vector3(2.4, 0.6, 0.04), Color(0.45, 0.45, 0.44))
	for fs: float in [1.0, -1.0]:
		var lb := Label3D.new()
		lb.text = "花 鸟 坊"
		lb.font_size = 64
		lb.pixel_size = 0.0068
		lb.modulate = Color(0.95, 0.76, 0.28)
		lb.outline_size = 0
		lb.visibility_range_end = 120.0
		var lbasis := xf.basis * Basis(Vector3.UP, 0.0 if fs > 0.0 else PI)
		lb.transform = Transform3D(lbasis, xf * Vector3(0.0, 4.65, fs * 0.23))
		labels.add_child(lb)
