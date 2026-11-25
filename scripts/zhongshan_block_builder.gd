class_name ZhongshanBlockBuilder
extends RefCounted

# 中山东路 × 禾兴南路 — the block around the junction, laid out from the satellite view and built after photos:
#  天主堂 (圣母显灵堂): cream stucco basilica on an open lawn, nave with lower side aisles and round-headed windows,
#          transept with oculi, apse to the north; south front between twin bell towers with lantern domes, a
#          columned porch under a carved pointed tympanum, arcaded frieze bands and a pierced parapet; two-storey
#          arcaded annexes behind, car parks north and south
#  中山影城: grey cinema hall with a curved white frame round a glass front, raised over fan-shaped planted
#          terraces with stairs and sweeping white side walls; round corner plaza with a music-staff railing
#  戴梦得: stone podium with a white rotunda (LED screen, blue faceted glass dome) at the corner, blue glass
#          tower with stone fins, triangular wing behind
#  旭辉广场: U-shaped mall round a forecourt open to 中山东路, copper vertical fins and light lines on the
#          inner facades, LED billboards, the entrance block with its name, residential slabs, the white wire
#          bear and mushroom canopies on a coloured play-plaza floor
#  江南大厦: white corner drum with a glass band and the name over the junction, ribbon-window podium along
#          中山东路, grey wing with a glass slot along 禾兴南路, beige tower behind (no advertising boards)
# All geometry is batched into a few meshes: masses (far range, shadows), details and cars (near range), glass,
# and unshaded light/screen surfaces.

const FAR_RANGE := 2600.0
const DETAIL_RANGE := 460.0

const STUCCO := Color(0.86, 0.82, 0.71)
const STUCCO_SH := Color(0.78, 0.74, 0.64)
const TRIM := Color(0.74, 0.71, 0.62)
const CARVE := Color(0.60, 0.57, 0.50)
const SLATE := Color(0.23, 0.25, 0.28)
const WIN := Color(0.11, 0.12, 0.14)
const PLINTH := Color(0.55, 0.54, 0.50)

static var _st := {}
static var _no_cars: Array[Rect2] = []


static func build(root: Node3D, data: Dictionary, lights: Array) -> void:
	_st = {}
	_no_cars = []
	var node := Node3D.new()
	node.name = "ZhongshanBlock"
	root.add_child(node)
	_church(node, lights)
	_cinema(node, lights)
	_diamond(node, lights)
	_cifi(node, lights)
	_jiangnan(node, lights)
	for pv in data.get("parking", []):
		if pv is Array:
			_parked_cars(pv)
	_commit(node)
	_st = {}


# ------------------------------------------------------------------------------------------------ primitives
static func _s(layer: String) -> SurfaceTool:
	if not _st.has(layer):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[layer] = st
	return _st[layer]


static func _xf(x: float, z: float, ry: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, ry), Vector3(x, 0.0, z))


static func _box(layer: String, xf: Transform3D, c: Vector3, size: Vector3, col: Color, ry: float = 0.0) -> void:
	RoadSignBuilder._box(_s(layer), xf * Transform3D(Basis(Vector3.UP, ry), c), size, col)


# axis-aligned box from local min/max corners
static func _bx(layer: String, xf: Transform3D, a: Vector3, b: Vector3, col: Color) -> void:
	_box(layer, xf, (a + b) * 0.5, (b - a).abs(), col)


static func _tri(layer: String, a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	var order: Array = [a, c, b] # Godot's front faces wind clockwise: (b-a)x(c-a) must point away from the normal
	if n.dot(out) < 0.0:
		n = -n
		order = [a, b, c]
	var st := _s(layer)
	for v: Vector3 in order:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


static func _quad(layer: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
	var o := xf.basis * out
	_tri(layer, xf * a, xf * b, xf * c, col, o)
	_tri(layer, xf * a, xf * c, xf * d, col, o)


# convex/star-shaped flat polygon fanned from its first point
static func _fan(layer: String, xf: Transform3D, pts: Array, col: Color, out: Vector3) -> void:
	var o := xf.basis * out
	for i in range(1, pts.size() - 1):
		_tri(layer, xf * (pts[0] as Vector3), xf * (pts[i] as Vector3), xf * (pts[i + 1] as Vector3), col, o)


# frustum / prism standing on `c` (local), radius r0 at the bottom and r1 at the top
static func _prism(layer: String, xf: Transform3D, c: Vector3, r0: float, r1: float, h: float, sides: int, col: Color, rot: float = 0.0, cap: bool = true, a_from: float = 0.0, a_to: float = TAU) -> void:
	var span := a_to - a_from
	for i in sides:
		var a0 := rot + a_from + span * float(i) / float(sides)
		var a1 := rot + a_from + span * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var dm := (d0 + d1).normalized()
		var p0 := c + d0 * r0
		var p1 := c + d1 * r0
		var q0 := c + d0 * r1 + Vector3(0.0, h, 0.0)
		var q1 := c + d1 * r1 + Vector3(0.0, h, 0.0)
		_quad(layer, xf, p0, p1, q1, q0, col, dm * h + Vector3(0.0, r0 - r1, 0.0))
		if cap and r1 > 0.01:
			_tri(layer, xf * (c + Vector3(0.0, h, 0.0)), xf * q0, xf * q1, col, xf.basis * Vector3.UP)


static func _sphere(layer: String, xf: Transform3D, c: Vector3, r: float, col: Color, sx: float = 1.0) -> void:
	var rings := 6
	for k in rings:
		var t0 := PI * float(k) / float(rings) - PI * 0.5
		var t1 := PI * float(k + 1) / float(rings) - PI * 0.5
		var y0 := sin(t0) * r
		var y1 := sin(t1) * r
		_prism(layer, xf, c + Vector3(0.0, y0, 0.0), cos(t0) * r * sx, cos(t1) * r * sx, y1 - y0, 12, col, 0.0, false)


# flat arched panel on a wall face: bottom centre `c`, width w, height h, facing `f` (local unit vector);
# pointed = Gothic two-centred arch, else round-headed; `off` lifts it off the wall
static func _arch(layer: String, xf: Transform3D, c: Vector3, w: float, h: float, f: Vector3, col: Color, pointed: bool = false, off: float = 0.04) -> void:
	var u := Vector3.UP.cross(f).normalized()
	var hw := w * 0.5
	var rise := w * 0.866 if pointed else hw
	var spring := maxf(h - rise, 0.0)
	var base := c + f * off
	var pts: Array = [base - u * hw, base + u * hw, base + u * hw + Vector3(0.0, spring, 0.0)]
	var segs := 5
	if pointed:
		for k in range(1, segs + 1):
			var th := deg_to_rad(60.0) * float(k) / float(segs)
			pts.append(base + u * (-hw + w * cos(th)) + Vector3(0.0, spring + w * sin(th), 0.0))
		for k in range(segs - 1, 0, -1):
			var th2 := deg_to_rad(60.0) * float(k) / float(segs)
			pts.append(base + u * (hw - w * cos(th2)) + Vector3(0.0, spring + w * sin(th2), 0.0))
	else:
		for k in range(1, segs * 2):
			var th3 := PI * float(k) / float(segs * 2)
			pts.append(base + u * (hw * cos(th3)) + Vector3(0.0, spring + hw * sin(th3), 0.0))
	pts.append(base - u * hw + Vector3(0.0, spring, 0.0))
	_fan(layer, xf, pts, col, f)


# window with a carved surround
static func _window(xf: Transform3D, c: Vector3, w: float, h: float, f: Vector3, pointed: bool = false, glass: Color = WIN) -> void:
	_arch("op_d", xf, c - Vector3(0.0, 0.2, 0.0), w + 0.6, h + 0.45, f, CARVE, pointed, 0.03)
	_arch("op_d", xf, c, w, h, f, glass, pointed, 0.06)


static func _disc(layer: String, xf: Transform3D, c: Vector3, r: float, f: Vector3, col: Color, off: float = 0.05) -> void:
	var u := Vector3.UP.cross(f).normalized()
	var pts: Array = []
	for k in 16:
		var a := TAU * float(k) / 16.0
		pts.append(c + f * off + u * cos(a) * r + Vector3(0.0, sin(a) * r, 0.0))
	_fan(layer, xf, pts, col, f)


# gable roof with its ridge along local Z (x0..x1 wide, z0..z1 long)
static func _gable_z(layer: String, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, col: Color, oh: float = 0.5) -> void:
	var xm := (x0 + x1) * 0.5
	var run := xm - x0
	_quad(layer, xf, Vector3(x0 - oh, ye - oh * (yr - ye) / run, z0 - oh), Vector3(x0 - oh, ye - oh * (yr - ye) / run, z1 + oh), Vector3(xm, yr, z1 + oh), Vector3(xm, yr, z0 - oh), col, Vector3(-(yr - ye), run, 0.0))
	_quad(layer, xf, Vector3(x1 + oh, ye - oh * (yr - ye) / run, z0 - oh), Vector3(x1 + oh, ye - oh * (yr - ye) / run, z1 + oh), Vector3(xm, yr, z1 + oh), Vector3(xm, yr, z0 - oh), col, Vector3(yr - ye, run, 0.0))


# gable roof with its ridge along local X
static func _gable_x(layer: String, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, col: Color, oh: float = 0.5) -> void:
	var zm := (z0 + z1) * 0.5
	var run := zm - z0
	_quad(layer, xf, Vector3(x0 - oh, ye - oh * (yr - ye) / run, z0 - oh), Vector3(x1 + oh, ye - oh * (yr - ye) / run, z0 - oh), Vector3(x1 + oh, yr, zm), Vector3(x0 - oh, yr, zm), col, Vector3(0.0, run, -(yr - ye)))
	_quad(layer, xf, Vector3(x0 - oh, ye - oh * (yr - ye) / run, z1 + oh), Vector3(x1 + oh, ye - oh * (yr - ye) / run, z1 + oh), Vector3(x1 + oh, yr, zm), Vector3(x0 - oh, yr, zm), col, Vector3(0.0, run, yr - ye))


static func _hip(layer: String, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, col: Color, oh: float = 0.6) -> void:
	var a := Vector3(x0 - oh, ye, z0 - oh)
	var b := Vector3(x1 + oh, ye, z0 - oh)
	var c := Vector3(x1 + oh, ye, z1 + oh)
	var d := Vector3(x0 - oh, ye, z1 + oh)
	var inset := minf(x1 - x0, z1 - z0) * 0.5
	var long_x := (x1 - x0) >= (z1 - z0)
	var zm := (z0 + z1) * 0.5
	var xm := (x0 + x1) * 0.5
	var r0 := Vector3(x0 + inset, yr, zm) if long_x else Vector3(xm, yr, z0 + inset)
	var r1 := Vector3(x1 - inset, yr, zm) if long_x else Vector3(xm, yr, z1 - inset)
	if long_x:
		_quad(layer, xf, a, b, r1, r0, col, Vector3(0.0, 1.0, -1.0))
		_quad(layer, xf, d, c, r1, r0, col, Vector3(0.0, 1.0, 1.0))
		_fan(layer, xf, [a, d, r0], col, Vector3(-1.0, 1.0, 0.0))
		_fan(layer, xf, [b, c, r1], col, Vector3(1.0, 1.0, 0.0))
	else:
		_quad(layer, xf, a, d, r1, r0, col, Vector3(-1.0, 1.0, 0.0))
		_quad(layer, xf, b, c, r1, r0, col, Vector3(1.0, 1.0, 0.0))
		_fan(layer, xf, [a, b, r0], col, Vector3(0.0, 1.0, -1.0))
		_fan(layer, xf, [d, c, r1], col, Vector3(0.0, 1.0, 1.0))


static func _label(parent: Node3D, xf: Transform3D, txt: String, c: Vector3, face_ry: float, fsz: int, px: float, col: Color) -> void:
	JiaxingLandmarks._add_sign_label(parent, txt, xf * c, xf.basis.get_euler().y + face_ry, fsz, px, col)


static func _light(parent: Node3D, xf: Transform3D, c: Vector3, col: Color, rng: float, lights: Array) -> void:
	var pl := OmniLight3D.new()
	pl.position = xf * c
	pl.light_color = col
	pl.omni_range = rng
	pl.light_energy = 0.0
	pl.visible = false
	parent.add_child(pl)
	lights.append(pl)


static func _commit(parent: Node3D) -> void:
	var op := StandardMaterial3D.new()
	op.vertex_color_use_as_albedo = true
	op.vertex_color_is_srgb = true
	op.roughness = 0.86
	op.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gl := StandardMaterial3D.new()
	gl.vertex_color_use_as_albedo = true
	gl.vertex_color_is_srgb = true
	gl.roughness = 0.10
	gl.metallic = 0.55
	gl.metallic_specular = 0.8
	gl.cull_mode = BaseMaterial3D.CULL_DISABLED
	var em := StandardMaterial3D.new()
	em.vertex_color_use_as_albedo = true
	em.vertex_color_is_srgb = true
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.cull_mode = BaseMaterial3D.CULL_DISABLED
	for layer: String in _st.keys():
		var mi := MeshInstance3D.new()
		mi.name = "Zhongshan_" + layer
		mi.mesh = (_st[layer] as SurfaceTool).commit()
		mi.material_override = em if layer.begins_with("em") else (gl if layer.begins_with("gl") else op)
		var detail := layer.ends_with("_d")
		mi.visibility_range_end = DETAIL_RANGE if detail else FAR_RANGE
		mi.visibility_range_end_margin = 30.0
		if detail or layer.begins_with("em"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


# ------------------------------------------------------------------------------------------------ 天主堂
static func _church(parent: Node3D, lights: Array) -> void:
	var xf := _xf(-534.0, -913.0, 0.12)
	var R := Vector3.RIGHT
	var L := Vector3.LEFT
	var S := Vector3.BACK # local +Z: the south front
	# forecourt paving, steps, and the path west to 禾兴南路
	_bx("op", xf, Vector3(-17.0, 0.0, 25.0), Vector3(17.0, 0.07, 39.0), Color(0.64, 0.62, 0.58))
	_bx("op", xf, Vector3(-140.0, 0.0, 30.5), Vector3(-17.0, 0.06, 33.5), Color(0.62, 0.60, 0.56))
	_bx("op", xf, Vector3(-1.6, 0.0, -62.0), Vector3(1.6, 0.06, -30.0), Color(0.62, 0.60, 0.56))
	# plinth all round
	_bx("op", xf, Vector3(-12.8, 0.0, -16.3), Vector3(12.8, 0.6, 20.0), PLINTH)
	_bx("op", xf, Vector3(-17.3, 0.0, -24.3), Vector3(17.3, 0.6, -15.7), PLINTH)
	# nave (13 wide, walls 17) with side aisles (6 wide, 10 high)
	_bx("op", xf, Vector3(-6.5, 0.0, -24.0), Vector3(6.5, 17.0, 20.0), STUCCO)
	_bx("op", xf, Vector3(-12.5, 0.0, -16.0), Vector3(12.5, 10.0, 20.0), STUCCO_SH)
	_gable_z("op", xf, -6.5, 6.5, -24.0, 20.5, 17.0, 23.0, SLATE, 0.4)
	for sd: float in [-1.0, 1.0]:
		# aisle lean-to roof
		_quad("op", xf, Vector3(sd * 6.5, 13.0, -16.4), Vector3(sd * 6.5, 13.0, 20.4), Vector3(sd * 13.0, 9.7, 20.4), Vector3(sd * 13.0, 9.7, -16.4), SLATE, Vector3(sd * 3.3, 6.5, 0.0))
		# cornices
		_bx("op_d", xf, Vector3(sd * 12.5 - 0.3, 9.6, -16.3), Vector3(sd * 12.5 + 0.3, 10.1, 20.0), TRIM)
		_bx("op_d", xf, Vector3(sd * 6.5 - 0.3, 16.6, -24.2), Vector3(sd * 6.5 + 0.3, 17.1, 20.0), TRIM)
		# bays: buttress pilasters, tall round-headed aisle windows, clerestory windows
		var f := R if sd > 0.0 else L
		var z := -14.0
		while z < 18.5:
			_bx("op_d", xf, Vector3(sd * 12.5 - 0.1, 0.6, z - 0.45), Vector3(sd * 12.5 + sd * 0.55, 9.6, z + 0.45), TRIM)
			_window(xf, Vector3(sd * 12.5, 2.6, z + 2.3), 1.4, 5.4, f)
			_window(xf, Vector3(sd * 6.5, 13.6, z + 2.3), 1.0, 2.3, f)
			z += 4.6
		# transept end wall: tall window under an oculus, gable triangle
		_window(xf, Vector3(sd * 17.0, 2.6, -20.0), 2.4, 7.2, f)
		_disc("op_d", xf, Vector3(sd * 17.0, 13.0, -20.0), 2.2, f, CARVE, 0.03)
		_disc("op_d", xf, Vector3(sd * 17.0, 13.0, -20.0), 1.6, f, WIN, 0.06)
		_fan("op", xf, [Vector3(sd * 17.0, 17.0, -24.0), Vector3(sd * 17.0, 17.0, -16.0), Vector3(sd * 17.0, 22.0, -20.0)], STUCCO, f)
	# transept and apse
	_bx("op", xf, Vector3(-17.0, 0.0, -24.0), Vector3(17.0, 17.0, -16.0), STUCCO)
	_gable_x("op", xf, -17.0, 17.0, -24.0, -16.0, 17.0, 22.0, SLATE, 0.4)
	_prism("op", xf, Vector3(0.0, 0.0, -24.0), 6.6, 6.6, 15.0, 8, STUCCO_SH, PI / 8.0)
	_prism("op", xf, Vector3(0.0, 15.0, -24.0), 7.0, 0.3, 4.6, 8, SLATE, PI / 8.0)
	for k in 3:
		var a := PI + PI * 0.25 + PI * 0.25 * float(k)
		var d := Vector3(cos(a), 0.0, sin(a))
		_window(xf, Vector3(0.0, 3.0, -24.0) + d * 6.1, 1.3, 5.6, d)

	# --- south front: central section between two towers ---
	var stone := STUCCO
	_bx("op", xf, Vector3(-5.5, 0.0, 20.0), Vector3(5.5, 9.0, 21.6), STUCCO_SH)          # porch back wall
	_bx("op", xf, Vector3(-5.5, 9.0, 20.0), Vector3(5.5, 21.0, 24.6), stone)             # upper front
	_bx("op_d", xf, Vector3(-1.5, 0.6, 21.6), Vector3(1.5, 4.8, 21.7), Color(0.07, 0.07, 0.08))  # doors
	_bx("op", xf, Vector3(-5.5, 0.0, 21.6), Vector3(5.5, 0.6, 25.0), PLINTH)             # porch floor
	for st_i in 3:
		_bx("op", xf, Vector3(-5.0 + st_i * 0.3, 0.0, 25.0 + st_i * 0.5), Vector3(5.0 - st_i * 0.3, 0.45 - st_i * 0.15, 25.6 + st_i * 0.5), PLINTH)
	for cx: float in [-4.3, 4.3]:
		_prism("op", xf, Vector3(cx, 0.6, 24.0), 0.48, 0.42, 7.6, 10, Color(0.80, 0.78, 0.72))
		_bx("op_d", xf, Vector3(cx - 0.7, 8.2, 23.3), Vector3(cx + 0.7, 9.0, 24.7), CARVE)   # capital
		_bx("op_d", xf, Vector3(cx - 0.65, 0.6, 23.35), Vector3(cx + 0.65, 1.1, 24.65), TRIM)  # base
	# pointed tympanum with a carved surround over the porch
	_arch("op_d", xf, Vector3(0.0, 10.0, 24.6), 9.4, 8.2, S, CARVE, true, 0.03)
	_arch("op_d", xf, Vector3(0.0, 10.4, 24.6), 7.8, 7.0, S, Color(0.88, 0.85, 0.76), true, 0.07)
	# frieze bands, arcaded band, parapet
	_bx("op_d", xf, Vector3(-5.5, 9.0, 24.6), Vector3(5.5, 9.9, 24.9), CARVE)
	_bx("op_d", xf, Vector3(-5.5, 19.4, 24.6), Vector3(5.5, 20.4, 24.95), CARVE)
	for k in 8:
		_arch("op_d", xf, Vector3(-4.4 + k * 1.257, 17.2, 24.6), 0.85, 1.9, S, Color(0.56, 0.54, 0.48), false, 0.05)
	_bx("op", xf, Vector3(-5.6, 20.9, 24.0), Vector3(5.6, 21.3, 24.9), TRIM)
	_bx("op_d", xf, Vector3(-5.5, 22.2, 24.1), Vector3(5.5, 22.5, 24.6), TRIM)
	var px := -5.2
	while px <= 5.25:
		_bx("op_d", xf, Vector3(px - 0.14, 21.3, 24.2), Vector3(px + 0.14, 22.2, 24.5), TRIM)
		px += 0.65

	# --- twin bell towers ---
	for sd: float in [-1.0, 1.0]:
		var tx := sd * 9.5
		_bx("op", xf, Vector3(tx - 4.0, 0.0, 17.5), Vector3(tx + 4.0, 27.0, 25.5), stone)
		_bx("op", xf, Vector3(tx - 4.2, 0.0, 17.3), Vector3(tx + 4.2, 0.6, 25.7), PLINTH)
		for cx2: float in [-3.9, 3.9]:   # corner pilasters
			_bx("op_d", xf, Vector3(tx + cx2 - 0.3, 0.6, 25.4), Vector3(tx + cx2 + 0.3, 26.6, 25.8), TRIM)
		# carved bands, arcaded band, cornice
		_bx("op_d", xf, Vector3(tx - 4.1, 9.0, 25.5), Vector3(tx + 4.1, 9.9, 25.85), CARVE)
		_bx("op_d", xf, Vector3(tx - 4.1, 19.4, 25.5), Vector3(tx + 4.1, 20.4, 25.9), CARVE)
		for k in 4:
			_arch("op_d", xf, Vector3(tx - 2.7 + k * 1.8, 17.2, 25.5), 0.85, 1.9, S, Color(0.56, 0.54, 0.48), false, 0.05)
		_bx("op", xf, Vector3(tx - 4.3, 26.6, 17.2), Vector3(tx + 4.3, 27.3, 25.8), TRIM)
		# side door and tall ornate window
		_arch("op_d", xf, Vector3(tx, 0.6, 25.5), 3.5, 6.2, S, CARVE, false, 0.03)
		_arch("op_d", xf, Vector3(tx, 0.6, 25.5), 2.4, 5.0, S, Color(0.09, 0.09, 0.10), false, 0.07)
		_window(xf, Vector3(tx, 10.8, 25.5), 1.5, 5.8, S, false, Color(0.42, 0.40, 0.36))
		# outer flank windows (seen from the lawn)
		var fo := R if sd > 0.0 else L
		_window(xf, Vector3(tx + sd * 4.0, 10.8, 21.5), 1.4, 5.0, fo, false, Color(0.42, 0.40, 0.36))
		# belfry stage with paired openings under a pointed hood on each face
		_bx("op", xf, Vector3(tx - 3.5, 27.3, 18.0), Vector3(tx + 3.5, 32.6, 25.0), stone)
		_bx("op", xf, Vector3(tx - 3.8, 32.4, 17.7), Vector3(tx + 3.8, 33.0, 25.3), TRIM)
		var bc := Vector3(tx, 0.0, 21.5)
		for fd: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
			var face := bc + fd * 3.5
			_arch("op_d", xf, face + Vector3(0.0, 27.9, 0.0), 3.6, 4.0, fd, CARVE, true, 0.03)
			var u := Vector3.UP.cross(fd).normalized()
			for o: float in [-0.75, 0.75]:
				_arch("op_d", xf, face + u * o + Vector3(0.0, 28.2, 0.0), 1.1, 2.9, fd, WIN, false, 0.07)
		# corner pinnacles
		for cx3: float in [-3.4, 3.4]:
			for cz3: float in [-3.4, 3.4]:
				_prism("op_d", xf, Vector3(tx + cx3, 33.0, 21.5 + cz3), 0.32, 0.05, 1.6, 6, TRIM)
		# octagonal lantern with arched openings and a ribbed bulb dome, spire
		_prism("op", xf, Vector3(tx, 33.0, 21.5), 2.7, 2.6, 2.6, 8, stone, PI / 8.0)
		for k in 8:
			var a2 := PI / 8.0 + TAU * (float(k) + 0.5) / 8.0
			var d2 := Vector3(cos(a2), 0.0, sin(a2))
			_arch("op_d", xf, Vector3(tx, 33.4, 21.5) + d2 * 2.45, 0.8, 1.8, d2, WIN, false, 0.06)
		_prism("op", xf, Vector3(tx, 35.6, 21.5), 2.95, 2.95, 0.35, 8, TRIM, PI / 8.0)
		_prism("op", xf, Vector3(tx, 35.95, 21.5), 2.7, 2.95, 1.0, 8, SLATE, PI / 8.0, false)
		_prism("op", xf, Vector3(tx, 36.95, 21.5), 2.95, 2.1, 1.3, 8, SLATE, PI / 8.0, false)
		_prism("op", xf, Vector3(tx, 38.25, 21.5), 2.1, 0.8, 1.2, 8, SLATE, PI / 8.0, false)
		_prism("op", xf, Vector3(tx, 39.45, 21.5), 0.8, 0.22, 0.8, 8, SLATE, PI / 8.0)
		_prism("op", xf, Vector3(tx, 40.25, 21.5), 0.2, 0.02, 2.6, 6, Color(0.35, 0.36, 0.38))
	_light(parent, xf, Vector3(0.0, 8.0, 32.0), Color(1.0, 0.86, 0.62), 40.0, lights)

	# two-storey arcaded annexes behind the church
	_annex(_xf(-499.0, -944.0, 0.12), 34.0, 20.0)
	_annex(_xf(-494.0, -967.0, 0.12), 24.0, 14.0)
	_annex(_xf(-536.0, -962.0, 0.12), 20.0, 14.0)


static func _annex(xf: Transform3D, w: float, d: float) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	_bx("op", xf, Vector3(-hw, 0.0, -hd), Vector3(hw, 8.6, hd), Color(0.82, 0.79, 0.71))
	_bx("op", xf, Vector3(-hw - 0.1, 0.0, -hd - 0.1), Vector3(hw + 0.1, 0.5, hd + 0.1), PLINTH)
	_bx("op_d", xf, Vector3(-hw - 0.15, 4.2, -hd - 0.15), Vector3(hw + 0.15, 4.55, hd + 0.15), TRIM)
	_hip("op", xf, -hw, hw, -hd, hd, 8.6, 11.8, SLATE)
	var n := int(w / 3.4)
	for k in n:
		var x := -hw + (float(k) + 0.5) * w / float(n)
		for f: Vector3 in [Vector3.BACK, Vector3.FORWARD]:
			var zf := hd if f == Vector3.BACK else -hd
			_arch("op_d", xf, Vector3(x, 0.5, zf), 2.2, 3.3, f, Color(0.30, 0.29, 0.27), false, 0.05)
			_arch("op_d", xf, Vector3(x, 5.2, zf), 1.2, 2.3, f, WIN, false, 0.05)
	_no_cars.append(Rect2(Vector2(xf.origin.x - hw - 4.0, xf.origin.z - hd - 4.0), Vector2(w + 8.0, d + 8.0)))


# ------------------------------------------------------------------------------------------------ 中山影城
static func _cinema(parent: Node3D, lights: Array) -> void:
	var xf := _xf(-775.0, -970.0, 0.14)
	var clad := Color(0.78, 0.77, 0.74)
	var white := Color(0.95, 0.95, 0.93)
	# hall
	_bx("op", xf, Vector3(-26.0, 0.0, -19.0), Vector3(14.0, 21.0, 19.0), clad)
	for y in [4.5, 8.5, 12.5, 16.5]:
		_bx("op_d", xf, Vector3(-26.1, y, -19.1), Vector3(14.1, y + 0.18, 19.1), clad.darkened(0.14))
	_bx("op", xf, Vector3(-26.3, 20.6, -19.3), Vector3(14.3, 21.4, 19.3), white)
	for k in 4:
		_bx("gl", xf, Vector3(-20.0 + k * 8.0, 21.0, -12.0), Vector3(-16.5 + k * 8.0, 21.6, 12.0), Color(0.40, 0.50, 0.58))
	# 中山东路 frontage: shop glazing and the name
	_bx("gl", xf, Vector3(-24.0, 0.4, -19.15), Vector3(10.0, 4.3, -19.05), Color(0.30, 0.38, 0.44))
	_label(parent, xf, "中 山 影 城", Vector3(-7.0, 18.0, -19.3), PI, 110, 0.034, Color(0.96, 0.92, 0.84))
	# raised terrace deck under the glass front
	_bx("op", xf, Vector3(14.0, 0.0, -17.0), Vector3(21.0, 4.5, 17.0), Color(0.80, 0.78, 0.71))
	# curved white frame round the glass front
	_bx("op", xf, Vector3(14.0, 4.5, -17.0), Vector3(18.6, 21.0, -13.4), white)
	_bx("op", xf, Vector3(14.0, 4.5, 13.4), Vector3(18.6, 21.0, 17.0), white)
	var nseg := 9
	for k in nseg:
		var z0 := -13.4 + 26.8 * float(k) / float(nseg)
		var z1 := -13.4 + 26.8 * float(k + 1) / float(nseg)
		var top := 21.0 + 1.6 * cos(PI * ((z0 + z1) * 0.5) / 27.0)
		_bx("op", xf, Vector3(14.0, top - 2.6, z0), Vector3(18.6, top, z1), white)
		# glass under the frame, mullions
		_bx("gl", xf, Vector3(16.6, 4.5, z0), Vector3(17.0, top - 2.6, z1), Color(0.58, 0.68, 0.76))
		_bx("op_d", xf, Vector3(17.0, 4.5, z0 - 0.07), Vector3(17.15, top - 2.6, z0 + 0.07), Color(0.30, 0.32, 0.34))
	_bx("op_d", xf, Vector3(17.0, 4.5, -1.6), Vector3(17.12, 7.2, 1.6), Color(0.20, 0.22, 0.24))   # doors
	_label(parent, xf, "中 山 影 院", Vector3(17.25, 16.6, 0.0), PI * 0.5, 120, 0.03, Color(0.10, 0.16, 0.36))
	# fan of planted terraces stepping down to the corner plaza, stairs up the middle
	var cen := Vector3(18.0, 0.0, 0.0)
	var a0 := deg_to_rad(-62.0)
	var a1 := deg_to_rad(62.0)
	for k in 6:
		var r := 6.6 + 3.6 * float(k)
		var h := 4.5 * (1.0 - float(k) / 6.0)
		_prism("op", xf, cen, r, r, h, 14, Color(0.80, 0.78, 0.71), 0.0, true, a0, a1)
		# hedges along the edge (gaps for the stairs), alternating dark and golden green
		var segs := 14
		for sgi in segs:
			var am := a0 + (a1 - a0) * (float(sgi) + 0.5) / float(segs)
			if absf(am) < deg_to_rad(9.0) or absf(absf(am) - deg_to_rad(40.0)) < deg_to_rad(4.0):
				continue
			var dm := Vector3(cos(am), 0.0, sin(am))
			var chord := 2.0 * r * sin((a1 - a0) / float(segs) * 0.5)
			var hc := Color(0.20, 0.36, 0.16) if k % 2 == 0 else Color(0.62, 0.66, 0.22)
			_box("op_d", xf, cen + dm * (r - 0.9) + Vector3(0.0, h + 0.3, 0.0), Vector3(1.0, 0.6, chord), hc, -am)
	# sweeping white side walls with glass balustrades
	for am2: float in [a0, a1]:
		var d3 := Vector3(cos(am2), 0.0, sin(am2))
		for k in 7:
			var rr := 4.0 + 3.0 * float(k)
			var hh := 5.6 - 0.72 * float(k)
			_box("op", xf, cen + d3 * (rr + 1.5) + Vector3(0.0, hh * 0.5, 0.0), Vector3(3.05, hh, 0.7), white, -am2)
			_box("gl", xf, cen + d3 * (rr + 1.5) + Vector3(0.0, hh + 0.5, 0.0), Vector3(3.05, 1.0, 0.08), Color(0.70, 0.80, 0.84), -am2)
	# round corner plaza: paving rings and the music-staff railing
	var pc := Vector3(39.0, 0.0, 3.0)
	_prism("op", xf, pc, 17.0, 17.0, 0.07, 28, Color(0.62, 0.59, 0.54))
	_prism("op_d", xf, pc, 11.0, 11.0, 0.085, 28, Color(0.70, 0.67, 0.61))
	_prism("op_d", xf, pc, 6.0, 6.0, 0.10, 20, Color(0.58, 0.55, 0.50))
	var nposts := 18
	for k in nposts:
		var ap := deg_to_rad(110.0) + deg_to_rad(280.0) * float(k) / float(nposts)
		var p := pc + Vector3(cos(ap), 0.0, sin(ap)) * 9.0
		_prism("op_d", xf, p, 0.08, 0.08, 1.15, 6, Color(0.16, 0.16, 0.18))
		if k < nposts - 1:
			var ap2 := deg_to_rad(110.0) + deg_to_rad(280.0) * float(k + 1) / float(nposts)
			var p2 := pc + Vector3(cos(ap2), 0.0, sin(ap2)) * 9.0
			var mid := (p + p2) * 0.5
			var ln := p.distance_to(p2)
			var yaw := -atan2(p2.z - p.z, p2.x - p.x)
			for li in 5:
				_box("op_d", xf, mid + Vector3(0.0, 0.55 + 0.1 * li, 0.0), Vector3(ln, 0.025, 0.03), Color(0.12, 0.12, 0.13), yaw)
			_box("op_d", xf, mid + Vector3(0.0, 0.68, 0.0), Vector3(0.14, 0.12, 0.05), Color(0.10, 0.10, 0.11), yaw)
	_light(parent, xf, Vector3(24.0, 8.0, 0.0), Color(1.0, 0.90, 0.72), 36.0, lights)


# ------------------------------------------------------------------------------------------------ 戴梦得
static func _diamond(parent: Node3D, lights: Array) -> void:
	var xf := _xf(-739.0, -872.0, 0.14)
	var stone := Color(0.80, 0.81, 0.83)
	var glass := Color(0.24, 0.36, 0.50)
	# podium (6 floors) with glass bays between stone piers on the street faces
	_bx("op", xf, Vector3(-50.0, 0.0, -42.0), Vector3(48.0, 24.0, 36.0), stone)
	_bx("gl", xf, Vector3(-46.0, 0.5, -42.15), Vector3(2.0, 4.4, -42.05), Color(0.32, 0.40, 0.46))
	_bx("gl", xf, Vector3(48.05, 0.5, -38.0), Vector3(48.15, 4.4, 32.0), Color(0.32, 0.40, 0.46))
	for y in [6.0, 12.0, 18.0]:
		_bx("gl", xf, Vector3(-46.0, y, -42.15), Vector3(2.0, y + 4.0, -42.05), glass)
		_bx("gl", xf, Vector3(48.05, y, -38.0), Vector3(48.15, y + 4.0, 32.0), glass)
	_bx("op", xf, Vector3(-50.3, 23.6, -42.3), Vector3(48.3, 24.6, 36.3), Color(0.66, 0.67, 0.70))
	_bx("em", xf, Vector3(-46.0, 4.6, -42.3), Vector3(2.0, 4.8, -42.2), Color(1.0, 0.90, 0.70))
	# corner rotunda: white drum, wrap-round screen, blue faceted glass dome
	var rc := Vector3(19.0, 0.0, -36.0)
	_prism("op", xf, rc, 15.0, 15.0, 26.0, 24, Color(0.93, 0.93, 0.92))
	_prism("gl", xf, rc + Vector3(0.0, 0.4, 0.0), 15.1, 15.1, 4.2, 24, Color(0.34, 0.42, 0.48), 0.0, false)
	var scr_cols := [Color(0.20, 0.45, 0.95), Color(0.45, 0.30, 0.90), Color(0.15, 0.75, 0.95), Color(0.90, 0.40, 0.75), Color(0.30, 0.55, 1.0)]
	var na := 10
	for k in na:
		var b0 := deg_to_rad(-150.0) + deg_to_rad(110.0) * float(k) / float(na)
		var b1 := deg_to_rad(-150.0) + deg_to_rad(110.0) * float(k + 1) / float(na)
		var d0 := Vector3(cos(b0), 0.0, sin(b0))
		var d1 := Vector3(cos(b1), 0.0, sin(b1))
		for row in 3:
			var y0 := 9.0 + row * 4.0
			_quad("em", xf, rc + d0 * 15.25 + Vector3(0.0, y0, 0.0), rc + d1 * 15.25 + Vector3(0.0, y0, 0.0), rc + d1 * 15.25 + Vector3(0.0, y0 + 4.0, 0.0), rc + d0 * 15.25 + Vector3(0.0, y0 + 4.0, 0.0), (scr_cols[(k + row * 2) % scr_cols.size()] as Color), (d0 + d1))
	_prism("op", xf, rc + Vector3(0.0, 25.6, 0.0), 15.7, 15.7, 0.9, 24, Color(0.70, 0.71, 0.74))
	_prism("gl", xf, rc + Vector3(0.0, 26.5, 0.0), 15.0, 2.4, 7.0, 16, Color(0.30, 0.56, 0.88))
	_prism("op", xf, rc + Vector3(0.0, 33.5, 0.0), 2.4, 1.6, 0.8, 16, Color(0.85, 0.86, 0.88))
	for k in 16:
		var ar := TAU * float(k) / 16.0
		var dr := Vector3(cos(ar), 0.0, sin(ar))
		_quad("op_d", xf, rc + dr * 15.05 + Vector3(0.0, 26.5, 0.0), rc + dr * 15.05 + Vector3(0.0, 26.5, 0.0) + Vector3(-dr.z, 0.0, dr.x) * 0.35, rc + dr * 2.45 + Vector3(0.0, 33.5, 0.0), rc + dr * 2.45 + Vector3(0.0, 33.5, 0.0), Color(0.88, 0.90, 0.92), dr + Vector3(0.0, 1.8, 0.0))
	_label(parent, xf, "戴 梦 得", Vector3(19.0, 6.4, -51.4), PI, 120, 0.036, Color(0.98, 0.82, 0.30))
	# tower: blue glass between stone fins, bands every three floors, setback crown with the name
	var tc := Vector3(10.0, 0.0, 0.0)
	_bx("gl", xf, tc + Vector3(-17.0, 24.0, -14.0), tc + Vector3(17.0, 100.0, 14.0), Color(0.16, 0.26, 0.40))
	var fx := -17.0
	while fx <= 17.05:
		_bx("op", xf, tc + Vector3(fx - 0.25, 24.0, -14.5), tc + Vector3(fx + 0.25, 100.0, -13.9), stone)
		_bx("op", xf, tc + Vector3(fx - 0.25, 24.0, 13.9), tc + Vector3(fx + 0.25, 100.0, 14.5), stone)
		fx += 3.4
	var fz := -14.0
	while fz <= 14.05:
		_bx("op", xf, tc + Vector3(-17.5, 24.0, fz - 0.25), tc + Vector3(-16.9, 100.0, fz + 0.25), stone)
		_bx("op", xf, tc + Vector3(16.9, 24.0, fz - 0.25), tc + Vector3(17.5, 100.0, fz + 0.25), stone)
		fz += 3.5
	var by := 36.0
	while by < 100.0:
		_bx("op", xf, tc + Vector3(-17.6, by, -14.6), tc + Vector3(17.6, by + 0.8, 14.6), stone)
		by += 12.0
	_bx("op", xf, tc + Vector3(-17.8, 99.6, -14.8), tc + Vector3(17.8, 101.0, 14.8), stone)
	_bx("op", xf, tc + Vector3(-13.0, 101.0, -10.0), tc + Vector3(13.0, 106.0, 10.0), Color(0.70, 0.72, 0.75))
	_bx("op", xf, tc + Vector3(-11.0, 106.0, -10.6), tc + Vector3(11.0, 111.0, -10.0), Color(0.95, 0.95, 0.94))
	_label(parent, xf, "戴梦得大厦", tc + Vector3(0.0, 108.5, -10.7), PI, 160, 0.05, Color(0.85, 0.10, 0.10))
	_prism("op", xf, tc + Vector3(0.0, 106.0, 2.0), 0.35, 0.08, 10.0, 6, Color(0.70, 0.72, 0.75))
	# triangular wing at the back
	var t0 := Vector3(-6.0, 0.0, 36.0)
	var t1 := Vector3(30.0, 0.0, 36.0)
	var t2 := Vector3(12.0, 0.0, 66.0)
	var tri := [t0, t1, t2]
	for i in 3:
		var p0: Vector3 = tri[i]
		var p1: Vector3 = tri[(i + 1) % 3]
		var out := (p0 + p1) * 0.5 - (t0 + t1 + t2) / 3.0
		_quad("op", xf, p0, p1, p1 + Vector3(0.0, 22.0, 0.0), p0 + Vector3(0.0, 22.0, 0.0), stone, out)
		for y2 in [5.0, 10.5, 16.0]:
			var o := out.normalized() * 0.08
			_quad("gl", xf, p0.lerp(p1, 0.06) + o + Vector3(0.0, y2, 0.0), p0.lerp(p1, 0.94) + o + Vector3(0.0, y2, 0.0), p0.lerp(p1, 0.94) + o + Vector3(0.0, y2 + 3.6, 0.0), p0.lerp(p1, 0.06) + o + Vector3(0.0, y2 + 3.6, 0.0), glass, out)
	_fan("op", xf, [t0 + Vector3(0.0, 22.0, 0.0), t1 + Vector3(0.0, 22.0, 0.0), t2 + Vector3(0.0, 22.0, 0.0)], Color(0.62, 0.63, 0.66), Vector3.UP)
	_light(parent, xf, Vector3(19.0, 10.0, -56.0), Color(0.88, 0.92, 1.0), 48.0, lights)


# ------------------------------------------------------------------------------------------------ 旭辉广场
static func _cifi(parent: Node3D, lights: Array) -> void:
	var xf := _xf(-899.0, -928.0, 0.14)
	var wall := Color(0.66, 0.48, 0.36)
	var copper := Color(0.82, 0.49, 0.30)
	# play-plaza floor: ochre with dark rings and glowing tiles
	_bx("op", xf, Vector3(-22.0, 0.0, -40.0), Vector3(22.0, 0.08, 30.0), Color(0.80, 0.56, 0.27))
	for rr: float in [8.0, 12.5, 17.0]:
		var nseg := int(rr * 3.0)
		for k in nseg:
			var a := TAU * float(k) / float(nseg)
			if fposmod(a + rr, 2.6) < 0.5:
				continue
			var p := Vector3(4.0 + cos(a) * rr, 0.09, -6.0 + sin(a) * rr)
			if absf(p.x) > 21.5 or p.z < -39.5 or p.z > 29.5:
				continue
			_box("op_d", xf, p, Vector3(1.3, 0.025, 0.55), Color(0.22, 0.22, 0.25), -a - PI * 0.5)
	var tile_cols := [Color(0.95, 0.70, 0.80), Color(0.55, 0.75, 1.0), Color(0.98, 0.92, 0.80)]
	for k in 22:
		var tx := -18.0 + fposmod(float(k) * 7.3, 36.0)
		var tz := -34.0 + fposmod(float(k) * 11.9, 58.0)
		_box("em_d", xf, Vector3(tx, 0.095, tz), Vector3(1.9, 0.02, 1.1), tile_cols[k % 3], float(k) * 0.3)
	# U-shaped podium round the forecourt (rounded back corners)
	_bx("op", xf, Vector3(-54.0, 0.0, -44.0), Vector3(-22.0, 24.0, 30.0), wall)
	_bx("op", xf, Vector3(22.0, 0.0, -44.0), Vector3(54.0, 24.0, 30.0), wall)
	_bx("op", xf, Vector3(-54.0, 0.0, 30.0), Vector3(54.0, 24.0, 64.0), wall)
	for sd: float in [-1.0, 1.0]:
		var pts_top: Array = [Vector3(sd * 22.0, 24.0, 30.0)]
		var pts_bot: Array = [Vector3(sd * 22.0, 0.0, 30.0)]
		for k in 7:
			var a2 := PI * 0.5 * float(k) / 6.0
			var q := Vector3(sd * (12.0 + 10.0 * cos(a2)), 0.0, 20.0 + 10.0 * sin(a2))
			pts_top.append(q + Vector3(0.0, 24.0, 0.0))
			pts_bot.append(q)
		_fan("op", xf, pts_top, wall, Vector3.UP)
		for k in range(1, pts_bot.size() - 1):
			var b0: Vector3 = pts_bot[k]
			var b1: Vector3 = pts_bot[k + 1]
			_quad("op", xf, b0, b1, b1 + Vector3(0.0, 24.0, 0.0), b0 + Vector3(0.0, 24.0, 0.0), wall, Vector3(-sd, 0.0, -1.0))
	for cap: Array in [[Vector3(-54.4, 23.6, -44.4), Vector3(-21.6, 24.6, 30.0)], [Vector3(21.6, 23.6, -44.4), Vector3(54.4, 24.6, 30.0)], [Vector3(-54.4, 23.6, 30.0), Vector3(54.4, 24.6, 64.4)]]:
		_bx("op", xf, cap[0], cap[1], Color(0.86, 0.86, 0.86))
	# inner facade outline: west side, back with rounded corners, east side
	var outline: Array = []
	var z := -44.0
	while z < 20.0:
		outline.append([Vector3(-22.0, 0.0, z), Vector3.RIGHT])
		z += 1.5
	for k in 9:
		var a3 := PI - PI * 0.5 * float(k) / 8.0
		var nrm := -Vector3(cos(a3), 0.0, sin(a3))
		outline.append([Vector3(-12.0 + 10.0 * cos(a3), 0.0, 20.0 + 10.0 * sin(a3)), nrm])
	var x := -10.5
	while x < 10.6:
		outline.append([Vector3(x, 0.0, 30.0), Vector3.FORWARD])
		x += 1.5
	for k in 9:
		var a4 := PI * 0.5 - PI * 0.5 * float(k) / 8.0
		var nrm2 := -Vector3(cos(a4), 0.0, sin(a4))
		outline.append([Vector3(12.0 + 10.0 * cos(a4), 0.0, 20.0 + 10.0 * sin(a4)), nrm2])
	z = 19.0
	while z > -44.5:
		outline.append([Vector3(22.0, 0.0, z), Vector3.LEFT])
		z -= 1.5
	for i in outline.size():
		var p2: Vector3 = outline[i][0]
		var n2: Vector3 = outline[i][1]
		if absf(p2.x) < 11.5 and p2.z > 29.0:
			continue # entrance block
		var yaw := atan2(n2.x, n2.z)
		var shade := copper.lerp(Color(0.92, 0.60, 0.40), fposmod(float(i) * 0.37, 1.0) * 0.4)
		_box("op_d", xf, p2 + n2 * 0.55 + Vector3(0.0, 14.0, 0.0), Vector3(0.36, 18.6, 1.1), shade, yaw)
		_box("gl", xf, p2 + n2 * 0.12 + Vector3(0.0, 2.2, 0.0), Vector3(1.55, 4.0, 0.1), Color(0.40, 0.36, 0.30), yaw)
		_box("em", xf, p2 + n2 * 1.15 + Vector3(0.0, 4.55, 0.0), Vector3(1.55, 0.16, 0.12), Color(0.78, 0.90, 1.0), yaw)
		_box("em", xf, p2 + n2 * 1.15 + Vector3(0.0, 23.4, 0.0), Vector3(1.55, 0.16, 0.12), Color(0.78, 0.90, 1.0), yaw)
	# copper fins on the 中山东路 ends of both wings
	for wx: float in [-38.0, 38.0]:
		var fxx := wx - 15.0
		while fxx <= wx + 15.0:
			_box("op_d", xf, Vector3(fxx, 14.0, -44.6), Vector3(0.36, 18.6, 1.1), copper)
			fxx += 1.5
		_bx("gl", xf, Vector3(wx - 15.0, 0.4, -44.15), Vector3(wx + 15.0, 4.3, -44.05), Color(0.40, 0.36, 0.30))
	# LED billboards on the east inner facade (abstract content) and the teal board on the west
	var bb_cols := [Color(0.92, 0.30, 0.42), Color(0.55, 0.25, 0.85), Color(0.20, 0.55, 0.95), Color(0.95, 0.55, 0.30)]
	for bi in 2:
		var z0 := -18.0 + bi * 15.0
		for gx in 3:
			for gy in 4:
				var c4: Color = bb_cols[(gx + gy + bi) % bb_cols.size()]
				_bx("em", xf, Vector3(20.6, 7.0 + gy * 3.3, z0 + gx * 4.0), Vector3(20.75, 10.3 + gy * 3.3, z0 + (gx + 1) * 4.0), c4.lerp(Color.WHITE, 0.08 * gy))
	_bx("em", xf, Vector3(-20.75, 8.0, -2.0), Vector3(-20.6, 20.0, 8.0), Color(0.30, 0.82, 0.86))
	# entrance block with the name
	_bx("op", xf, Vector3(-11.0, 0.0, 24.0), Vector3(11.0, 30.0, 34.0), Color(0.70, 0.72, 0.75))
	_bx("gl", xf, Vector3(-7.0, 0.3, 23.85), Vector3(7.0, 21.0, 24.0), Color(0.30, 0.40, 0.48))
	_bx("op", xf, Vector3(-9.5, 4.6, 19.5), Vector3(9.5, 5.3, 24.0), Color(0.86, 0.80, 0.66))
	_bx("em", xf, Vector3(-9.0, 4.45, 19.8), Vector3(9.0, 4.6, 23.8), Color(1.0, 0.86, 0.62))
	_label(parent, xf, "旭 辉 广 场", Vector3(0.0, 25.0, 23.8), PI, 150, 0.04, Color(1.0, 1.0, 1.0))
	# residential slab behind and the tower over the east wing
	_slab(xf, Vector3(-22.0, 24.0, 40.0), Vector3(22.0, 110.0, 58.0), Color(0.84, 0.82, 0.77))
	_slab(xf, Vector3(27.0, 24.0, -32.0), Vector3(49.0, 96.0, -10.0), Color(0.80, 0.80, 0.78))
	# white wire bear and mushroom canopies
	var bear := Color(0.90, 0.92, 0.95)
	var bc := Vector3(9.0, 0.0, -8.0)
	_sphere("op", xf, bc + Vector3(0.0, 3.8, 0.0), 3.8, bear)
	_sphere("op", xf, bc + Vector3(0.0, 8.9, -0.4), 3.0, bear, 1.1)
	for sx: float in [-1.0, 1.0]:
		_sphere("op", xf, bc + Vector3(sx * 2.3, 11.4, -0.2), 0.95, bear)
		_sphere("op", xf, bc + Vector3(sx * 2.2, 1.2, -3.0), 1.45, bear)
		_sphere("op", xf, bc + Vector3(sx * 3.4, 4.8, -1.6), 1.1, bear)
	_sphere("em", xf, bc + Vector3(0.0, 4.6, -3.6), 0.9, Color(0.98, 0.45, 0.62), 1.2)
	for mc: Vector3 in [Vector3(-9.0, 0.0, -4.0), Vector3(17.0, 0.0, 6.0)]:
		_prism("op", xf, mc, 0.5, 4.4, 6.4, 14, bear, 0.0, false)
		_prism("op", xf, mc + Vector3(0.0, 6.4, 0.0), 5.4, 5.4, 0.25, 16, bear)
	for k in 5:   # orange curved benches
		var ab := TAU * float(k) / 5.0
		_box("op_d", xf, Vector3(4.0 + cos(ab) * 14.0, 0.25, -6.0 + sin(ab) * 14.0), Vector3(3.6, 0.5, 0.9), Color(0.86, 0.42, 0.16), -ab - PI * 0.5)
	_light(parent, xf, Vector3(0.0, 10.0, -10.0), Color(1.0, 0.86, 0.66), 44.0, lights)


# residential/office slab with storey bands of glazing
static func _slab(xf: Transform3D, a: Vector3, b: Vector3, col: Color) -> void:
	_bx("op", xf, a, b, col)
	var y := a.y + 2.0
	var win := Color(0.24, 0.30, 0.36)
	while y < b.y - 2.0:
		_bx("gl", xf, Vector3(a.x + 1.0, y, a.z - 0.06), Vector3(b.x - 1.0, y + 1.5, b.z + 0.06), win)
		_bx("gl", xf, Vector3(a.x - 0.06, y, a.z + 1.0), Vector3(b.x + 0.06, y + 1.5, b.z - 1.0), win)
		y += 3.1
	var vx := a.x + 4.0
	while vx < b.x - 2.0:
		_bx("op_d", xf, Vector3(vx - 0.3, a.y, a.z - 0.25), Vector3(vx + 0.3, b.y, a.z + 0.1), col.darkened(0.08))
		_bx("op_d", xf, Vector3(vx - 0.3, a.y, b.z - 0.1), Vector3(vx + 0.3, b.y, b.z + 0.25), col.darkened(0.08))
		vx += 6.0
	_bx("op", xf, Vector3(a.x - 0.3, b.y, a.z - 0.3), Vector3(b.x + 0.3, b.y + 1.2, b.z + 0.3), col.darkened(0.12))


# ------------------------------------------------------------------------------------------------ 江南大厦
static func _jiangnan(parent: Node3D, lights: Array) -> void:
	var xf := _xf(-675.0, -1049.0, 0.16)
	var white := Color(0.92, 0.92, 0.90)
	var grey := Color(0.84, 0.84, 0.82)
	var shop := Color(0.30, 0.38, 0.44)
	# podium along 中山东路 with ribbon windows
	_bx("op", xf, Vector3(24.0, 0.0, -40.0), Vector3(85.0, 20.0, 0.0), Color(0.86, 0.85, 0.82))
	_bx("gl", xf, Vector3(26.0, 0.4, 0.05), Vector3(83.0, 4.6, 0.15), shop)
	for y in [6.4, 11.2, 16.0]:
		_bx("gl", xf, Vector3(26.0, y, 0.05), Vector3(83.0, y + 2.6, 0.15), Color(0.34, 0.44, 0.52))
	_bx("op", xf, Vector3(23.7, 19.6, -40.3), Vector3(85.3, 20.6, 0.3), white)
	# grey wing along 禾兴南路 with a tall glass slot and a top pavilion
	_bx("op", xf, Vector3(0.0, 0.0, -80.0), Vector3(22.0, 28.0, -24.0), grey)
	_bx("gl", xf, Vector3(-0.15, 0.4, -78.0), Vector3(-0.05, 4.6, -27.0), shop)
	_bx("gl", xf, Vector3(-0.2, 5.0, -48.0), Vector3(-0.05, 27.0, -42.0), Color(0.30, 0.40, 0.50))
	for zc: float in [-36.0, -54.0, -66.0]:
		_bx("op_d", xf, Vector3(-0.6, 0.0, zc - 0.6), Vector3(0.1, 28.0, zc + 0.6), white)
	_bx("op", xf, Vector3(-0.4, 27.6, -80.4), Vector3(22.4, 28.6, -23.6), white)
	_bx("op", xf, Vector3(4.0, 28.6, -66.0), Vector3(16.0, 36.0, -52.0), white)
	_bx("gl", xf, Vector3(3.9, 29.5, -65.0), Vector3(16.1, 34.5, -53.0), Color(0.34, 0.44, 0.52))
	_bx("op", xf, Vector3(3.6, 36.0, -66.4), Vector3(16.4, 36.8, -51.6), grey.darkened(0.2))
	# block between the drum and the tower
	_bx("op", xf, Vector3(0.0, 0.0, -40.0), Vector3(26.0, 22.0, -10.0), grey)
	# white corner drum facing the junction: glass band, shop glazing, the name on the band
	var dc := Vector3(13.0, 0.0, -13.0)
	_prism("op", xf, dc, 14.0, 14.0, 24.0, 28, white)
	_prism("gl", xf, dc + Vector3(0.0, 8.0, 0.0), 14.12, 14.12, 13.0, 16, Color(0.36, 0.46, 0.55), 0.0, false, deg_to_rad(60.0), deg_to_rad(210.0))
	_prism("gl", xf, dc + Vector3(0.0, 0.4, 0.0), 14.12, 14.12, 4.4, 16, shop, 0.0, false, deg_to_rad(40.0), deg_to_rad(230.0))
	_prism("op", xf, dc + Vector3(0.0, 23.6, 0.0), 14.6, 14.6, 1.0, 28, Color(0.80, 0.80, 0.80))
	_prism("op", xf, dc + Vector3(0.0, 24.6, 0.0), 10.0, 10.0, 3.0, 20, grey)
	var dir_sw := Vector3(cos(deg_to_rad(135.0)), 0.0, sin(deg_to_rad(135.0)))
	_label(parent, xf, "江  南  大  厦", dc + dir_sw * 14.3 + Vector3(0.0, 6.0, 0.0), -PI * 0.25, 130, 0.034, Color(0.86, 0.12, 0.10))
	# beige tower behind with storey glazing and a stack of balconies, plain sign frame on the roof
	var beige := Color(0.86, 0.74, 0.60)
	_slab(xf, Vector3(30.0, 0.0, -64.0), Vector3(62.0, 66.0, -42.0), beige)
	var y2 := 24.0
	while y2 < 64.0:
		for bx2: float in [50.0, 56.0]:
			_bx("op_d", xf, Vector3(bx2, y2, -41.9), Vector3(bx2 + 4.0, y2 + 1.1, -40.6), beige.lightened(0.1))
		y2 += 3.1
	_bx("op", xf, Vector3(36.0, 67.2, -60.0), Vector3(56.0, 71.0, -46.0), beige.darkened(0.1))
	_bx("op", xf, Vector3(34.0, 71.0, -50.0), Vector3(58.0, 74.5, -49.4), Color(0.18, 0.20, 0.24))
	_light(parent, xf, dc + dir_sw * 20.0 + Vector3(0.0, 8.0, 0.0), Color(1.0, 0.88, 0.68), 44.0, lights)


# ------------------------------------------------------------------------------------------------ car parks
static func _parked_cars(pv: Array) -> void:
	var poly := PackedVector2Array()
	for q in pv:
		poly.append(Vector2(float(q[0]), float(q[1])))
	if poly.size() < 3:
		return
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for v in poly:
		mn = mn.min(v)
		mx = mx.max(v)
	var ry := 0.12
	var ux := Vector2(cos(ry), -sin(ry))
	var uz := Vector2(sin(ry), cos(ry))
	var cols := [Color(0.92, 0.92, 0.92), Color(0.12, 0.12, 0.13), Color(0.62, 0.64, 0.66), Color(0.55, 0.12, 0.12), Color(0.18, 0.26, 0.42), Color(0.80, 0.80, 0.78)]
	var cen := (mn + mx) * 0.5
	var ext := (mx - mn).length() * 0.5 + 4.0
	var row := -ext
	while row <= ext:
		var col_i := -ext
		while col_i <= ext:
			var p := cen + ux * col_i + uz * row
			col_i += 2.6
			var h := absi(int(p.x * 7.0 + p.y * 13.0)) % 10
			if h < 2:
				continue
			var ok := true
			for cc: Vector2 in [p + uz * 2.6, p - uz * 2.6, p + ux * 1.2, p - ux * 1.2]:
				if not Geometry2D.is_point_in_polygon(cc, poly):
					ok = false
					break
			if not ok:
				continue
			var blocked := false
			for r: Rect2 in _no_cars:
				if r.has_point(p):
					blocked = true
					break
			if blocked:
				continue
			var xf := _xf(p.x, p.y, ry)
			var c: Color = cols[h % cols.size()]
			_bx("op_d", xf, Vector3(-0.9, 0.18, -2.2), Vector3(0.9, 0.95, 2.2), c)
			_bx("gl_d", xf, Vector3(-0.8, 0.95, -1.1), Vector3(0.8, 1.45, 1.0), Color(0.12, 0.14, 0.17))
		row += 6.4
