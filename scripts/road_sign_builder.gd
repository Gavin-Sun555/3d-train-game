class_name RoadSignBuilder
extends RefCounted

# Chinese urban street signage (GB 5768 / GB 17733 conventions):
#   "name"  路名牌: blue plate with white border on a grey post at the junction corner, parallel to its road,
#           hanzi with the Hanyu Pinyin underneath, readable from both sides
#   "guide" 指路标志: L-shaped cantilever from the right-hand kerb, a blue panel over the lanes with white lane
#           arrows and the roads reached by turning left / going ahead / turning right
# Sign records come from tools/build_jiaxing_map.py: {"k", "p": [x, z], "d": [dx, dz], ...}

const BLUE := Color(0.04, 0.22, 0.58)
const WHITE := Color(0.96, 0.97, 0.98)
const POLE := Color(0.52, 0.54, 0.56)
const PLATE_RANGE := 170.0
const GUIDE_RANGE := 420.0
const GUIDE_TEXT_RANGE := 300.0
const CELL := 200.0

static var _mat: StandardMaterial3D = null


static func build(parent: Node3D, signs: Array) -> void:
	if signs.is_empty():
		return
	# boards are batched per 200 m cell: a visibility range is measured to a mesh's centre, so one batch over
	# a whole district hid every board while the (individually ranged) names still showed, floating in the air
	var cells := {}
	var labels := Node3D.new()
	labels.name = "RoadSignTexts"
	parent.add_child(labels)
	for sg: Dictionary in signs:
		var p: Array = sg.get("p", [])
		var d: Array = sg.get("d", [])
		if p.size() < 2 or d.size() < 2:
			continue
		var pos := Vector3(float(p[0]), 0.0, float(p[1]))
		if Terrain.active:
			pos.y = Terrain.surface(pos.x, pos.z)
		var dir := Vector3(float(d[0]), 0.0, float(d[1]))
		if dir.length_squared() < 0.01:
			continue
		dir = dir.normalized()
		var ck := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
		if not cells.has(ck):
			var stc := SurfaceTool.new()
			stc.begin(Mesh.PRIMITIVE_TRIANGLES)
			cells[ck] = stc
		var st: SurfaceTool = cells[ck]
		if str(sg.get("k", "")) == "name":
			_name_plate(st, labels, pos, dir, str(sg.get("t", "")), str(sg.get("py", "")))
		elif str(sg.get("k", "")) == "guide":
			_guide_sign(st, labels, pos, dir, float(sg.get("w", 16.0)), bool(sg.get("tram", false)),
				str(sg.get("L", "")), str(sg.get("S", "")), str(sg.get("R", "")))
	if cells.is_empty():
		return
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.45
		_mat.metallic = 0.15
	if Terrain.active:
		labels.set_meta("on_terrain", true)
	for ck: Vector2i in cells.keys():
		var mi := MeshInstance3D.new()
		mi.name = "RoadSignBoards_%d_%d" % [ck.x, ck.y]
		mi.mesh = (cells[ck] as SurfaceTool).commit()
		mi.material_override = _mat
		mi.visibility_range_end = GUIDE_RANGE
		mi.visibility_range_end_margin = 30.0
		if Terrain.active:
			mi.set_meta("on_terrain", true)
		parent.add_child(mi)


# --- 路名牌 ------------------------------------------------------------------------------------------------
static func _name_plate(st: SurfaceTool, labels: Node3D, pos: Vector3, road_dir: Vector3, hz: String, py: String) -> void:
	if hz.is_empty():
		return
	var plate_w := clampf(0.36 * float(hz.length()) + 0.50, 1.4, 3.0)
	var plate_h := 0.62
	var top := 3.35
	# plate plane contains the road direction: its faces look across the road
	var face := Vector3(-road_dir.z, 0.0, road_dir.x)
	var basis := Basis(road_dir, Vector3.UP, face)
	_box(st, Transform3D(Basis.IDENTITY, pos + Vector3(0.0, (top - plate_h) * 0.5, 0.0)), Vector3(0.09, top - plate_h, 0.09), POLE)
	var pc := pos + Vector3(0.0, top - plate_h * 0.5, 0.0)
	_box(st, Transform3D(basis, pc), Vector3(plate_w, plate_h, 0.04), WHITE)
	_box(st, Transform3D(basis, pc), Vector3(plate_w - 0.07, plate_h - 0.07, 0.055), BLUE)
	for s: float in [1.0, -1.0]:
		var fb := Basis(road_dir * s, Vector3.UP, face * s)
		var hz_l := _label(hz, minf(0.0050, (plate_w - 0.36) / (float(hz.length()) * 64.0)), 64, PLATE_RANGE)
		hz_l.transform = Transform3D(fb, pc + face * s * 0.035 + Vector3(0.0, 0.08, 0.0))
		labels.add_child(hz_l)
		if not py.is_empty():
			var py_l := _label(py, minf(0.0026, (plate_w - 0.24) / (float(py.length()) * 48.0 * 0.62)), 48, PLATE_RANGE * 0.7)
			py_l.transform = Transform3D(fb, pc + face * s * 0.035 + Vector3(0.0, -0.19, 0.0))
			labels.add_child(py_l)


# --- 指路标志 ----------------------------------------------------------------------------------------------
static func _guide_sign(st: SurfaceTool, labels: Node3D, pos: Vector3, travel: Vector3, road_w: float, tram: bool, l_nm: String, s_nm: String, r_nm: String) -> void:
	var right := Vector3(-travel.z, 0.0, travel.x)
	var inward := -right # from the kerb toward the road centre
	var arm_l := clampf(road_w * 0.5 - (4.8 if tram else 1.2), 3.2, 8.5)
	var pole_h := 8.3
	var pw := 5.4
	var ph := 2.7
	var pcy := 5.6 + ph * 0.5 # 5.5 m clearance over the lanes
	var off := maxf(2.9, arm_l - pw * 0.5 + 0.3)
	var pc := pos + inward * off + Vector3(0.0, pcy, 0.0)
	var face := -travel # the panel looks at oncoming traffic
	# local X = the driver's right as they face the sign, Y up, Z toward the driver
	var basis := Basis(right, Vector3.UP, face)
	_box(st, Transform3D(Basis.IDENTITY, pos + Vector3(0.0, pole_h * 0.5, 0.0)), Vector3(0.30, pole_h, 0.30), POLE)
	_box(st, Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.25, 0.0)), Vector3(0.62, 0.5, 0.62), POLE.darkened(0.15))
	var arm_basis := Basis(inward, Vector3.UP, inward.cross(Vector3.UP))
	# the arms carry the panel from behind (drivers see the blue face, the steel stays on the back)
	for ay: float in [pcy + ph * 0.5 - 0.25, pcy - ph * 0.5 + 0.35]:
		_box(st, Transform3D(arm_basis, pos + inward * (arm_l * 0.5) + Vector3(0.0, ay, 0.0) + travel * 0.14), Vector3(arm_l, 0.16, 0.16), POLE)
	_box(st, Transform3D(basis, pc), Vector3(pw, ph, 0.06), WHITE)
	_box(st, Transform3D(basis, pc + face * 0.008), Vector3(pw - 0.12, ph - 0.12, 0.06), BLUE)
	# lane diagram: stem from the bottom, branches to the named exits, arrowheads at their ends
	var z := 0.045
	var stem_bot := -ph * 0.5 + 0.28
	var node_y := -0.10
	var lw := 0.20
	_lbox(st, basis, pc, Vector3(0.0, (stem_bot + node_y) * 0.5, z), Vector3(lw, node_y - stem_bot, 0.02))
	if not s_nm.is_empty():
		var top_y := ph * 0.5 - 1.05
		_lbox(st, basis, pc, Vector3(0.0, (node_y + top_y) * 0.5, z), Vector3(lw, top_y - node_y, 0.02))
		_arrow_head(st, basis, pc, Vector3(0.0, top_y, z), Vector2(0.0, 1.0))
		_text(labels, basis, pc, Vector3(0.0, ph * 0.5 - 0.40, z + 0.01), s_nm, 0.0078)
	if not l_nm.is_empty():
		var lx := -1.15
		_lbox(st, basis, pc, Vector3((lx + 0.0) * 0.5, node_y, z), Vector3(-lx, lw, 0.02))
		_arrow_head(st, basis, pc, Vector3(lx, node_y, z), Vector2(-1.0, 0.0))
		_text(labels, basis, pc, Vector3(-pw * 0.5 + 0.95, node_y - 0.52, z + 0.01), l_nm, 0.0074)
	if not r_nm.is_empty():
		var rx := 1.15
		_lbox(st, basis, pc, Vector3(rx * 0.5, node_y, z), Vector3(rx, lw, 0.02))
		_arrow_head(st, basis, pc, Vector3(rx, node_y, z), Vector2(1.0, 0.0))
		_text(labels, basis, pc, Vector3(pw * 0.5 - 0.95, node_y - 0.52, z + 0.01), r_nm, 0.0074)


static func _text(labels: Node3D, basis: Basis, pc: Vector3, local: Vector3, txt: String, px: float) -> void:
	var size_fit := minf(px, 1.9 / (0.95 * float(maxi(2, txt.length())) * 64.0))
	var l := _label(txt, size_fit, 64, GUIDE_TEXT_RANGE)
	l.transform = Transform3D(basis, pc + basis * local)
	labels.add_child(l)


static func _label(txt: String, px: float, font_size: int, rng: float) -> Label3D:
	var l := Label3D.new()
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		l.set_meta("pending_text", txt) # shaped a few per frame by CityTiles when the tile is attached
	else:
		l.text = txt
	l.font_size = font_size
	l.pixel_size = px
	l.modulate = WHITE
	l.outline_size = 0
	l.double_sided = false
	l.shaded = false
	l.visibility_range_end = rng
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.render_priority = 2
	return l


# white box in panel-local coordinates
static func _lbox(st: SurfaceTool, basis: Basis, pc: Vector3, local: Vector3, size: Vector3) -> void:
	_box(st, Transform3D(basis, pc + basis * local), Vector3(absf(size.x), absf(size.y), size.z), WHITE)


static func _arrow_head(st: SurfaceTool, basis: Basis, pc: Vector3, tip_local: Vector3, dir2: Vector2) -> void:
	# filled triangle pointing along dir2 (panel plane), tip slightly past the line end
	var d := Vector3(dir2.x, dir2.y, 0.0)
	var n := Vector3(-dir2.y, dir2.x, 0.0)
	var tip := tip_local + d * 0.30
	var b0 := tip_local - d * 0.05 + n * 0.30
	var b1 := tip_local - d * 0.05 - n * 0.30
	var nrm := basis.z
	var pts: Array[Vector3] = [pc + basis * tip, pc + basis * b0, pc + basis * b1]
	# both windings so it shows regardless of the arrow direction
	for tri: Array in [[0, 1, 2], [0, 2, 1]]:
		for k: int in tri:
			st.set_color(WHITE)
			st.set_normal(nrm)
			st.add_vertex(pts[k])


static func _box(st: SurfaceTool, tf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var uu := u * h
		var vv := v * h
		var q: Array[Vector3] = [c - uu - vv, c + uu - vv, c + uu + vv, c - uu + vv]
		var wn := (tf.basis * n).normalized()
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(wn)
			st.add_vertex(tf * q[k])
