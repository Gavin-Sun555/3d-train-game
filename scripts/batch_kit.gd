class_name BatchKit
extends RefCounted

# Batched landmark geometry: vertex-coloured triangles collected per layer and committed as a few meshes.
# Layers: "op" opaque masses (far range, shadows), "gl" glass, "em" unshaded lights/screens; a "_d" suffix
# puts a layer in the near-range detail set (no shadows). Start a build with begin(), end it with commit().
# Polygons wind clockwise about their normal (Godot's front face), so double-sided faces shade correctly.

const FAR_RANGE := 2600.0
const DETAIL_RANGE := 460.0

static var _st := {}


static func begin() -> void:
	_st = {}


static func s(layer: String) -> SurfaceTool:
	if not _st.has(layer):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[layer] = st
	return _st[layer]


static func xf(x: float, z: float, ry: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, ry), Vector3(x, 0.0, z))


static func box(layer: String, xf: Transform3D, c: Vector3, size: Vector3, col: Color, ry: float = 0.0) -> void:
	RoadSignBuilder._box(s(layer), xf * Transform3D(Basis(Vector3.UP, ry), c), size, col)


# axis-aligned box from local min/max corners
static func bx(layer: String, xf: Transform3D, a: Vector3, b: Vector3, col: Color) -> void:
	box(layer, xf, (a + b) * 0.5, (b - a).abs(), col)


static func tri(layer: String, a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	var order: Array = [a, c, b] # Godot's front faces wind clockwise: (b-a)x(c-a) must point away from the normal
	if n.dot(out) < 0.0:
		n = -n
		order = [a, b, c]
	var st := s(layer)
	for v: Vector3 in order:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


static func quad(layer: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
	var o := xf.basis * out
	tri(layer, xf * a, xf * b, xf * c, col, o)
	tri(layer, xf * a, xf * c, xf * d, col, o)


# convex/star-shaped flat polygon fanned from its first point
static func fan(layer: String, xf: Transform3D, pts: Array, col: Color, out: Vector3) -> void:
	var o := xf.basis * out
	for i in range(1, pts.size() - 1):
		tri(layer, xf * (pts[0] as Vector3), xf * (pts[i] as Vector3), xf * (pts[i + 1] as Vector3), col, o)


# frustum / prism standing on `c` (local), radius r0 at the bottom and r1 at the top
static func prism(layer: String, xf: Transform3D, c: Vector3, r0: float, r1: float, h: float, sides: int, col: Color, rot: float = 0.0, cap: bool = true, a_from: float = 0.0, a_to: float = TAU) -> void:
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
		quad(layer, xf, p0, p1, q1, q0, col, dm * h + Vector3(0.0, r0 - r1, 0.0))
		if cap and r1 > 0.01:
			tri(layer, xf * (c + Vector3(0.0, h, 0.0)), xf * q0, xf * q1, col, xf.basis * Vector3.UP)


static func sphere(layer: String, xf: Transform3D, c: Vector3, r: float, col: Color, sx: float = 1.0) -> void:
	var rings := 6
	for k in rings:
		var t0 := PI * float(k) / float(rings) - PI * 0.5
		var t1 := PI * float(k + 1) / float(rings) - PI * 0.5
		var y0 := sin(t0) * r
		var y1 := sin(t1) * r
		prism(layer, xf, c + Vector3(0.0, y0, 0.0), cos(t0) * r * sx, cos(t1) * r * sx, y1 - y0, 12, col, 0.0, false)


# flat arched panel on a wall face: bottom centre `c`, width w, height h, facing `f` (local unit vector);
# pointed = Gothic two-centred arch, else round-headed; `off` lifts it off the wall
static func arch(layer: String, xf: Transform3D, c: Vector3, w: float, h: float, f: Vector3, col: Color, pointed: bool = false, off: float = 0.04) -> void:
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
	fan(layer, xf, pts, col, f)


static func disc(layer: String, xf: Transform3D, c: Vector3, r: float, f: Vector3, col: Color, off: float = 0.05) -> void:
	var u := Vector3.UP.cross(f).normalized()
	var pts: Array = []
	for k in 16:
		var a := TAU * float(k) / 16.0
		pts.append(c + f * off + u * cos(a) * r + Vector3(0.0, sin(a) * r, 0.0))
	fan(layer, xf, pts, col, f)


# gable roof with its ridge along local Z (x0..x1 wide, z0..z1 long)
static func gable_z(layer: String, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, col: Color, oh: float = 0.5) -> void:
	var xm := (x0 + x1) * 0.5
	var run := xm - x0
	quad(layer, xf, Vector3(x0 - oh, ye - oh * (yr - ye) / run, z0 - oh), Vector3(x0 - oh, ye - oh * (yr - ye) / run, z1 + oh), Vector3(xm, yr, z1 + oh), Vector3(xm, yr, z0 - oh), col, Vector3(-(yr - ye), run, 0.0))
	quad(layer, xf, Vector3(x1 + oh, ye - oh * (yr - ye) / run, z0 - oh), Vector3(x1 + oh, ye - oh * (yr - ye) / run, z1 + oh), Vector3(xm, yr, z1 + oh), Vector3(xm, yr, z0 - oh), col, Vector3(yr - ye, run, 0.0))


# gable roof with its ridge along local X
static func gable_x(layer: String, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, col: Color, oh: float = 0.5) -> void:
	var zm := (z0 + z1) * 0.5
	var run := zm - z0
	quad(layer, xf, Vector3(x0 - oh, ye - oh * (yr - ye) / run, z0 - oh), Vector3(x1 + oh, ye - oh * (yr - ye) / run, z0 - oh), Vector3(x1 + oh, yr, zm), Vector3(x0 - oh, yr, zm), col, Vector3(0.0, run, -(yr - ye)))
	quad(layer, xf, Vector3(x0 - oh, ye - oh * (yr - ye) / run, z1 + oh), Vector3(x1 + oh, ye - oh * (yr - ye) / run, z1 + oh), Vector3(x1 + oh, yr, zm), Vector3(x0 - oh, yr, zm), col, Vector3(0.0, run, yr - ye))


static func hip(layer: String, xf: Transform3D, x0: float, x1: float, z0: float, z1: float, ye: float, yr: float, col: Color, oh: float = 0.6) -> void:
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
		quad(layer, xf, a, b, r1, r0, col, Vector3(0.0, 1.0, -1.0))
		quad(layer, xf, d, c, r1, r0, col, Vector3(0.0, 1.0, 1.0))
		fan(layer, xf, [a, d, r0], col, Vector3(-1.0, 1.0, 0.0))
		fan(layer, xf, [b, c, r1], col, Vector3(1.0, 1.0, 0.0))
	else:
		quad(layer, xf, a, d, r1, r0, col, Vector3(-1.0, 1.0, 0.0))
		quad(layer, xf, b, c, r1, r0, col, Vector3(1.0, 1.0, 0.0))
		fan(layer, xf, [a, b, r0], col, Vector3(0.0, 1.0, -1.0))
		fan(layer, xf, [d, c, r1], col, Vector3(0.0, 1.0, 1.0))


static func label(parent: Node3D, xf: Transform3D, txt: String, c: Vector3, face_ry: float, fsz: int, px: float, col: Color) -> void:
	JiaxingLandmarks._add_sign_label(parent, txt, xf * c, xf.basis.get_euler().y + face_ry, fsz, px, col)


static func light(parent: Node3D, xf: Transform3D, c: Vector3, col: Color, rng: float, lights: Array) -> void:
	var pl := OmniLight3D.new()
	pl.position = xf * c
	pl.light_color = col
	pl.omni_range = rng
	pl.light_energy = 0.0
	pl.visible = false
	parent.add_child(pl)
	lights.append(pl)


static func commit(parent: Node3D, prefix: String) -> void:
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
		mi.name = prefix + "_" + layer
		mi.mesh = (_st[layer] as SurfaceTool).commit()
		mi.material_override = em if layer.begins_with("em") else (gl if layer.begins_with("gl") else op)
		var detail := layer.ends_with("_d")
		mi.visibility_range_end = DETAIL_RANGE if detail else FAR_RANGE
		mi.visibility_range_end_margin = 30.0
		if detail or layer.begins_with("em"):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	begin()
