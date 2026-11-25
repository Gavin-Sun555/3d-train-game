class_name SchoolBuilder
extends RefCounted

# 浙江省嘉兴市第一中学 (Jiaxing No.1 High School), laid out after the satellite view of the real campus: muted orange
# brick buildings under dark slate hipped roofs with white cornices — the north-west main complex, west teaching
# blocks, the square science hall with its observatory dome, the north-centre academic blocks, north-east
# dormitory rows and canteen cluster, the south-west courtyard building round its patterned garden with the fan
# plaza, two white-roof sports halls, maroon court banks, the stadium on the east side with its grandstand, and the
# wooded heart of the campus with its pond. Main gate on 纺工路: the natural granite stone carved 嘉興一中, stainless
# retractable gates, the white V sculpture and the camphor avenue leading to the round plaza and the clock tower.
# All boxes are batched per material class into one mesh (opaque vertex colour / glass / glow).
#
# Local frame of the campus node: x east (-208 .. 208), z south (-196 .. 196). Building rectangles are given in
# pixels of the reference satellite image (campus = px 80..1100 x 60..1000) and mapped by _rect().

const WHITE := Color(0.93, 0.92, 0.89)
const BRICK := Color(0.70, 0.45, 0.33) # muted orange-brown brick (the real walls are less saturated than photos)
const BRICK_D := Color(0.58, 0.36, 0.27)
const SLATE := Color(0.29, 0.31, 0.35)
const STONE := Color(0.56, 0.56, 0.57)
const STONE_LT := Color(0.76, 0.74, 0.70)
const TAN := Color(0.78, 0.68, 0.57) # forecourt tiles
const FRAME := Color(0.20, 0.22, 0.25)
const GLASS := Color(0.28, 0.40, 0.50)
const TRACK := Color(0.70, 0.34, 0.24)
const PITCH := Color(0.24, 0.45, 0.21)
const LINE := Color(0.95, 0.96, 0.95)
const COURT := Color(0.50, 0.24, 0.21) # maroon court banks
const COURT_IN := Color(0.30, 0.42, 0.33)
const SEAT_A := Color(0.15, 0.40, 0.70)
const SEAT_B := Color(0.90, 0.78, 0.25)
const GATE_Z := -34.0


# reference-image pixel rectangle -> [centre (x, z), size (x, z)] in the campus frame
static func _rect(px0: float, py0: float, px1: float, py1: float) -> Array:
	var x0 := (px0 - 590.0) * 0.408
	var x1 := (px1 - 590.0) * 0.408
	var z0 := (py0 - 530.0) * 0.413
	var z1 := (py1 - 530.0) * 0.413
	return [Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5), Vector2(absf(x1 - x0), absf(z1 - z0))]


static func _px(px: float, py: float) -> Vector3:
	return Vector3((px - 590.0) * 0.408, 0.0, (py - 530.0) * 0.413)


static func build(sc: Node3D, lights: Array) -> void:
	var kit := {"op": _st(), "gl": _st(), "em": _st()}
	var labels := Node3D.new()
	labels.name = "SchoolSigns"
	sc.add_child(labels)

	_grounds(sc, kit)
	_fence(kit)
	_main_gate(sc, kit, labels)

	# --- buildings, from the satellite view ---
	# north-west main complex: long main block + short west wing
	_bld(kit, _rect(100, 72, 390, 160), 4)
	_bld(kit, _rect(100, 160, 150, 205), 3)
	# west teaching blocks (two parallel slabs joined by a west wing)
	_bld(kit, _rect(150, 192, 300, 248), 4)
	_bld(kit, _rect(150, 258, 300, 322), 4)
	_bld(kit, _rect(122, 200, 158, 318), 4)
	# square science hall with the observatory dome
	var sci := _rect(365, 232, 488, 360)
	_bld(kit, sci, 4)
	_dome(sc, Vector3(sci[0].x, 4.0 * 3.8 + 2.5, sci[0].y))
	# north-centre academic blocks
	_bld(kit, _rect(560, 72, 700, 112), 3)
	_bld(kit, _rect(572, 120, 696, 214), 4)
	_bld(kit, _rect(566, 218, 696, 300), 4)
	# north-east dormitory rows
	for r: Array in [[720, 70, 860, 120], [870, 70, 1010, 120], [1020, 70, 1095, 120], [720, 175, 905, 230], [912, 175, 1095, 230]]:
		_bld(kit, _rect(r[0], r[1], r[2], r[3]), 5, true)
	# canteen / student-centre cluster
	_bld(kit, _rect(930, 290, 1095, 330), 3)
	_bld(kit, _rect(830, 330, 940, 412), 2)
	_bld(kit, _rect(915, 400, 1020, 440), 2)
	_flat_hall(kit, _rect(1040, 332, 1090, 462), 8.0)
	# south-west courtyard building round its garden + east extension + fan plaza
	_bld(kit, _rect(188, 524, 404, 562), 4)
	_bld(kit, _rect(188, 652, 404, 700), 4)
	_bld(kit, _rect(188, 562, 236, 652), 4)
	_bld(kit, _rect(358, 562, 404, 652), 4)
	_bld(kit, _rect(404, 596, 600, 660), 3)
	_bld(kit, _rect(404, 660, 486, 712), 3)
	_courtyard_garden(kit, _rect(236, 562, 358, 652))
	_fan_plaza(kit, _px(540, 700), 17.0)
	# sports halls (white flat roofs) and courts
	_flat_hall(kit, _rect(200, 760, 388, 916), 12.0)
	_flat_hall(kit, _rect(386, 852, 512, 946), 10.0)
	_courts(kit, _rect(394, 762, 506, 850), 2, 1)
	_courts(kit, _rect(545, 775, 765, 960), 4, 2)
	_courts(kit, _rect(410, 95, 500, 185), 1, 1)
	_stadium(kit, Vector3(132.0, 0.0, 92.0))
	_clock_tower(sc, kit, Vector3(-30.0, 0.0, GATE_Z))

	_trees(sc)
	_commit(sc, kit)
	JiaxingCivicLandmarks._add_light(sc, Vector3(-200.0, 8.0, GATE_Z), Color(1.0, 0.90, 0.72), 50.0, lights)
	JiaxingCivicLandmarks._add_light(sc, Vector3(-106.0, 8.0, GATE_Z), Color(1.0, 0.90, 0.72), 40.0, lights)
	JiaxingCivicLandmarks._add_light(sc, Vector3(132.0, 20.0, 92.0), Color(1.0, 0.96, 0.88), 90.0, lights)


# ------------------------------------------------------------------------------------------------- kit
static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _b(kit: Dictionary, layer: String, xf: Transform3D, c: Vector3, size: Vector3, col: Color) -> void:
	RoadSignBuilder._box(kit[layer], xf * Transform3D(Basis.IDENTITY, c), size, col)
	kit[layer + "_n"] = true


static func _flat(kit: Dictionary, pts: Array, y: float, col: Color) -> void:
	# convex fan in the campus frame
	var st: SurfaceTool = kit["op"]
	for i in range(1, pts.size() - 1):
		for p: Vector2 in [pts[0], pts[i + 1], pts[i]]:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y, p.y))
	kit["op_n"] = true


static func _strip(kit: Dictionary, inner: Array, outer: Array, y: float, col: Color) -> void:
	var st: SurfaceTool = kit["op"]
	for i in range(inner.size() - 1):
		var a: Vector2 = inner[i]
		var b: Vector2 = inner[i + 1]
		var c: Vector2 = outer[i + 1]
		var d: Vector2 = outer[i]
		for p: Vector2 in [a, c, b, a, d, c]:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y, p.y))
	kit["op_n"] = true


static func _commit(sc: Node3D, kit: Dictionary) -> void:
	var am := ArrayMesh.new()
	var mats: Array[Material] = []
	if kit.get("op_n", false):
		(kit["op"] as SurfaceTool).commit(am)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.82
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mats.append(m)
	if kit.get("gl_n", false):
		(kit["gl"] as SurfaceTool).commit(am)
		var g := StandardMaterial3D.new()
		g.vertex_color_use_as_albedo = true
		g.metallic = 0.35
		g.roughness = 0.06
		g.metallic_specular = 0.8
		mats.append(g)
	if kit.get("em_n", false):
		(kit["em"] as SurfaceTool).commit(am)
		var e := StandardMaterial3D.new()
		e.vertex_color_use_as_albedo = true
		e.emission_enabled = true
		e.emission = Color(1.0, 0.96, 0.86)
		e.emission_energy_multiplier = 1.2
		mats.append(e)
	for i in range(mats.size()):
		am.surface_set_material(i, mats[i])
	var mi := MeshInstance3D.new()
	mi.name = "CampusBuildings"
	mi.mesh = am
	sc.add_child(mi)


static func _sign(labels: Node3D, txt: String, pos: Vector3, ry: float, fsz: int, px: float, col: Color) -> void:
	JiaxingLandmarks._add_sign_label(labels, txt, pos, ry, fsz, px, col)


# ------------------------------------------------------------------------------------------------- grounds
static func _grounds(sc: Node3D, kit: Dictionary) -> void:
	var lawn := MeshInstance3D.new()
	lawn.name = "CampusLawn"
	var pm := PlaneMesh.new()
	pm.size = Vector2(416.0, 388.0)
	lawn.mesh = pm
	lawn.material_override = JiaxingLandmarks.lawn_material()
	lawn.position = Vector3(0.0, 0.02, 0.0)
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.add_child(lawn)
	var I := Transform3D.IDENTITY
	# gate forecourt (tan tiles), the avenue to the round plaza, paths north / south from it, campus roads
	_b(kit, "op", I, Vector3(-232.0, 0.03, 12.0), Vector3(48.0, 0.06, 220.0), STONE_LT)
	_b(kit, "op", I, Vector3(-200.0, 0.05, GATE_Z), Vector3(18.0, 0.06, 40.0), TAN)
	_b(kit, "op", I, Vector3(-150.0, 0.05, GATE_Z), Vector3(100.0, 0.06, 16.0), TAN)
	_b(kit, "op", I, Vector3(-108.0, 0.05, -92.0), Vector3(12.0, 0.06, 112.0), STONE_LT)
	_b(kit, "op", I, Vector3(-108.0, 0.05, -10.0), Vector3(10.0, 0.06, 46.0), STONE_LT)
	_b(kit, "op", I, Vector3(-60.0, 0.05, GATE_Z), Vector3(78.0, 0.06, 6.0), STONE_LT)
	_b(kit, "op", I, Vector3(70.0, 0.05, 0.0), Vector3(7.0, 0.06, 380.0), STONE_LT)
	_b(kit, "op", I, Vector3(0.0, 0.05, -60.0), Vector3(132.0, 0.06, 6.0), STONE_LT)
	_b(kit, "op", I, Vector3(0.0, 0.05, 92.0), Vector3(140.0, 0.06, 7.0), STONE_LT)
	# round plaza with a ring pattern
	var pc := Vector2(-106.0, GATE_Z)
	var disc: Array = []
	for k in range(48):
		var a := TAU * float(k) / 48.0
		disc.append(pc + Vector2(cos(a), sin(a)) * 14.0)
	_flat(kit, disc, 0.09, Color(0.80, 0.77, 0.72))
	for rr: float in [5.0, 9.5, 13.6]:
		var ri: Array = []
		var ro: Array = []
		for k2 in range(49):
			var a2 := TAU * float(k2) / 48.0
			ri.append(pc + Vector2(cos(a2), sin(a2)) * (rr - 0.25))
			ro.append(pc + Vector2(cos(a2), sin(a2)) * (rr + 0.25))
		_strip(kit, ri, ro, 0.095, Color(0.62, 0.58, 0.54))
	# wooded heart: the pond (irregular, from the satellite view)
	var pond: Array = []
	var pcen := Vector2(38.0, 50.0)
	for k3 in range(36):
		var a3 := TAU * float(k3) / 36.0
		var rad := Vector2(13.5, 27.0) * (0.86 + 0.18 * sin(a3 * 3.0 + 0.7) * cos(a3 * 2.0))
		pond.append(pcen + Vector2(cos(a3) * rad.x, sin(a3) * rad.y))
	var pond_st := SurfaceTool.new()
	pond_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pond.size()):
		var a4: Vector2 = pond[i]
		var b4: Vector2 = pond[(i + 1) % pond.size()]
		for p: Vector2 in [pcen, a4, b4]: # clockwise from above = front face (the water shader culls back faces)
			pond_st.set_normal(Vector3.UP)
			pond_st.add_vertex(Vector3(p.x - pcen.x, 0.0, p.y - pcen.y))
	var pmi := MeshInstance3D.new()
	pmi.name = "FountainWater"
	pmi.mesh = pond_st.commit()
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/fountain_water.gdshader") as Shader
	wm.set_shader_parameter("radius", 27.0)
	wm.set_shader_parameter("ripple_speed", 0.45)
	wm.set_shader_parameter("deep_col", Color(0.10, 0.20, 0.17))
	wm.set_shader_parameter("shallow_col", Color(0.20, 0.32, 0.24))
	pmi.material_override = wm
	pmi.position = Vector3(pcen.x, 0.12, pcen.y)
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.add_child(pmi)
	var rim_o: Array = []
	var rim_i: Array = []
	for k5 in range(pond.size() + 1):
		var q: Vector2 = pond[k5 % pond.size()]
		var dq := (q - pcen).normalized()
		rim_i.append(q)
		rim_o.append(q + dq * 1.4)
	_strip(kit, rim_i, rim_o, 0.16, Color(0.52, 0.50, 0.46))


static func _fence(kit: Dictionary) -> void:
	var runs := [
		[Vector2(-208, -196), Vector2(-208, -54)], [Vector2(-208, -14), Vector2(-208, 196)],
		[Vector2(-208, -196), Vector2(208, -196)], [Vector2(-208, 196), Vector2(208, 196)],
		[Vector2(208, -196), Vector2(208, 196)],
	]
	for rn: Array in runs:
		var a: Vector2 = rn[0]
		var b: Vector2 = rn[1]
		var L := a.distance_to(b)
		var u := (b - a) / L
		var xf := Transform3D(Basis(Vector3.UP, -atan2(u.y, u.x)), Vector3(a.x, 0.0, a.y))
		_b(kit, "op", xf, Vector3(L * 0.5, 0.3, 0.0), Vector3(L, 0.6, 0.45), BRICK_D)
		_b(kit, "op", xf, Vector3(L * 0.5, 1.05, 0.0), Vector3(L, 0.07, 0.07), FRAME)
		_b(kit, "op", xf, Vector3(L * 0.5, 2.05, 0.0), Vector3(L, 0.07, 0.07), FRAME)
		var n := int(L / 3.2)
		for k in range(n + 1):
			_b(kit, "op", xf, Vector3(float(k) * L / float(maxi(1, n)), 1.2, 0.0), Vector3(0.42, 2.4, 0.42), BRICK if k % 3 == 0 else FRAME)
		if absf(a.x + 208.0) < 0.1 and absf(b.x + 208.0) < 0.1:
			for k2 in range(int(L / 0.6)):
				_b(kit, "op", xf, Vector3(float(k2) * 0.6 + 0.3, 1.55, 0.0), Vector3(0.035, 1.0, 0.035), FRAME)


# Main gate (from the photo): a great natural granite stone carved 嘉興一中 in gold, a low hedge in front, stainless
# retractable gates either side, the white V sculpture behind, a notice board, classical lamps along the avenue
static func _main_gate(sc: Node3D, kit: Dictionary, labels: Node3D) -> void:
	var I := Transform3D.IDENTITY
	var gz := GATE_Z
	var granite := Color(0.68, 0.57, 0.50)
	# the stone: a natural boulder built from tilted, uneven chunks (rough top edge, slightly bulging faces)
	var sx := -206.0
	var chunks := [
		[Vector3(0.0, 1.45, 0.0), Vector3(2.3, 2.9, 10.6), 0.0, 0.0],
		[Vector3(0.05, 3.05, -3.3), Vector3(2.0, 0.55, 4.0), 0.05, 0.02],
		[Vector3(-0.05, 3.15, 0.4), Vector3(2.1, 0.75, 3.6), -0.04, -0.03],
		[Vector3(0.1, 2.95, 3.6), Vector3(1.9, 0.45, 3.4), 0.06, 0.05],
		[Vector3(-0.25, 1.4, -4.9), Vector3(1.9, 2.6, 1.6), 0.0, 0.12],
		[Vector3(-0.2, 1.35, 4.9), Vector3(1.9, 2.5, 1.6), 0.0, -0.10],
		[Vector3(-0.42, 1.5, -1.5), Vector3(1.6, 2.7, 4.0), 0.03, 0.0],
		[Vector3(-0.38, 1.45, 2.4), Vector3(1.6, 2.6, 3.2), -0.03, 0.0],
	]
	for ci in range(chunks.size()):
		var ch: Array = chunks[ci]
		var cxf := Transform3D(Basis.from_euler(Vector3(float(ch[2]), 0.0, float(ch[3]))), Vector3(sx, 0.0, gz) + (ch[0] as Vector3))
		var tone := granite.lerp(Color(0.74, 0.64, 0.57), float(ci % 3) / 3.0).darkened(0.03 * float(ci % 2))
		RoadSignBuilder._box(kit["op"], cxf, ch[1], tone)
	kit["op_n"] = true
	_b(kit, "op", I, Vector3(sx - 1.9, 0.35, gz), Vector3(1.6, 0.7, 11.4), Color(0.30, 0.46, 0.22))
	_b(kit, "op", I, Vector3(sx - 1.9, 0.1, gz), Vector3(1.9, 0.2, 11.8), STONE)
	_sign(labels, "嘉 興 一 中", Vector3(sx - 1.34, 1.85, gz), -PI * 0.5, 96, 0.020, Color(0.86, 0.64, 0.14))
	# stainless retractable gates: top / bottom rails with criss-cross lattice
	for side: float in [-1.0, 1.0]:
		var z0 := gz + side * 6.2
		var z1 := gz + side * 19.0
		var L := absf(z1 - z0)
		var zc := (z0 + z1) * 0.5
		var steel := Color(0.80, 0.82, 0.84)
		for y: float in [0.25, 1.75]:
			_b(kit, "op", I, Vector3(-207.4, y, zc), Vector3(0.12, 0.10, L), steel)
		var n := int(L / 0.9)
		for k in range(n):
			var zz := minf(z0, z1) + (float(k) + 0.5) * L / float(n)
			for sgn: float in [-1.0, 1.0]:
				var xf := Transform3D(Basis(Vector3(1, 0, 0), sgn * 0.75), Vector3(-207.4, 1.0, zz))
				RoadSignBuilder._box(kit["op"], xf, Vector3(0.05, 1.9, 0.05), steel)
			_b(kit, "op", I, Vector3(-207.4, 1.0, zz), Vector3(0.08, 1.8, 0.08), steel)
		kit["op_n"] = true
		# end posts with the track wheels' housing
		_b(kit, "op", I, Vector3(-207.4, 1.0, z1), Vector3(0.5, 2.0, 0.5), steel.darkened(0.2))
	# white V sculpture on a plinth behind the stone
	var vx := -196.0
	_b(kit, "op", I, Vector3(vx, 0.4, gz), Vector3(3.0, 0.8, 3.0), STONE_LT)
	for sgn2: float in [-1.0, 1.0]:
		var xf2 := Transform3D(Basis(Vector3(1, 0, 0), sgn2 * 0.62), Vector3(vx, 3.0, gz + sgn2 * 1.25))
		RoadSignBuilder._box(kit["op"], xf2, Vector3(0.6, 4.6, 1.0), Color(0.90, 0.90, 0.88))
	kit["op_n"] = true
	# notice board on the right of the gate
	_b(kit, "op", I, Vector3(-203.0, 1.6, gz + 24.0), Vector3(0.3, 3.2, 7.0), Color(0.86, 0.87, 0.88))
	_b(kit, "op", I, Vector3(-203.2, 2.0, gz + 24.0), Vector3(0.05, 2.2, 6.4), Color(0.70, 0.22, 0.20))
	# classical lamps (black poles, three white globes) lining the avenue
	for lx in range(-198, -116, 12):
		for side2: float in [-1.0, 1.0]:
			var lp := Vector3(float(lx), 0.0, gz + side2 * 9.5)
			_b(kit, "op", I, lp + Vector3(0.0, 2.3, 0.0), Vector3(0.16, 4.6, 0.16), Color(0.12, 0.12, 0.13))
			_b(kit, "op", I, lp + Vector3(0.0, 4.6, 0.0), Vector3(1.2, 0.08, 0.08), Color(0.12, 0.12, 0.13))
			for gx: float in [-0.6, 0.0, 0.6]:
				_b(kit, "em", I, lp + Vector3(gx, 4.85 + (0.25 if gx == 0.0 else 0.0), 0.0), Vector3(0.34, 0.34, 0.34), Color(0.98, 0.97, 0.94))


# ------------------------------------------------------------------------------------------------- buildings
# Brick building under a slate hipped roof: stone plinth, white floor bands and cornice, white-framed windows on
# every face; dorms get a balcony rail per bay on their south face
static func _bld(kit: Dictionary, r: Array, floors: int, dorm: bool = false) -> void:
	var c: Vector2 = r[0]
	var sz: Vector2 = r[1]
	var fh := 3.6 if dorm else 3.8
	var H := float(floors) * fh
	var I := Transform3D.IDENTITY
	var cen := Vector3(c.x, 0.0, c.y)
	_b(kit, "op", I, cen + Vector3(0.0, H * 0.5, 0.0), Vector3(sz.x, H, sz.y), BRICK)
	_b(kit, "op", I, cen + Vector3(0.0, 0.6, 0.0), Vector3(sz.x + 0.3, 1.2, sz.y + 0.3), STONE)
	for f in range(1, floors):
		_b(kit, "op", I, cen + Vector3(0.0, float(f) * fh, 0.0), Vector3(sz.x + 0.16, 0.22, sz.y + 0.16), WHITE)
	_b(kit, "op", I, cen + Vector3(0.0, H - 0.25, 0.0), Vector3(sz.x + 0.5, 0.5, sz.y + 0.5), WHITE)
	# windows on the four faces
	for face in range(4):
		var along_x := face < 2
		var sgn := 1.0 if face % 2 == 0 else -1.0
		var span := sz.x if along_x else sz.y
		var off := (sz.y if along_x else sz.x) * 0.5
		var nb := int((span - 2.0) / 3.6)
		if nb < 1:
			continue
		for f2 in range(floors):
			var y := float(f2) * fh + fh * 0.55
			for k in range(nb):
				var t := -span * 0.5 + 1.0 + (float(k) + 0.5) * (span - 2.0) / float(nb)
				var p := cen + (Vector3(t, y, sgn * off) if along_x else Vector3(sgn * off, y, t))
				var fsz := Vector3(2.0, 2.2, 0.12) if along_x else Vector3(0.12, 2.2, 2.0)
				var gsz := Vector3(1.6, 1.85, 0.06) if along_x else Vector3(0.06, 1.85, 1.6)
				var out := Vector3(0.0, 0.0, sgn * 0.05) if along_x else Vector3(sgn * 0.05, 0.0, 0.0)
				_b(kit, "op", I, p + out, fsz, WHITE)
				_b(kit, "gl", I, p + out * 2.0, gsz, GLASS)
				if dorm and face == 0 and f2 > 0:
					_b(kit, "op", I, p + Vector3(0.0, -1.1, 0.75), Vector3(2.6, 0.12, 1.4), WHITE)
					_b(kit, "op", I, p + Vector3(0.0, -0.6, 1.42), Vector3(2.6, 0.9, 0.08), WHITE)
	_hip_roof(kit, cen, sz, H, 0.9)


# hipped slate roof over a footprint, white eaves board
static func _hip_roof(kit: Dictionary, cen: Vector3, sz: Vector2, base_y: float, oh: float) -> void:
	var a := sz.x * 0.5 + oh
	var b := sz.y * 0.5 + oh
	var rise := minf(minf(a, b) * 0.62, 6.5)
	var st: SurfaceTool = kit["op"]
	var y0 := base_y
	var y1 := base_y + rise
	var pts: Array = []
	if a >= b:
		var r := a - b
		pts = [
			[Vector3(-a, y0, -b), Vector3(a, y0, -b), Vector3(r, y1, 0), Vector3(-r, y1, 0)],
			[Vector3(a, y0, b), Vector3(-a, y0, b), Vector3(-r, y1, 0), Vector3(r, y1, 0)],
			[Vector3(a, y0, -b), Vector3(a, y0, b), Vector3(r, y1, 0)],
			[Vector3(-a, y0, b), Vector3(-a, y0, -b), Vector3(-r, y1, 0)],
		]
	else:
		var r2 := b - a
		pts = [
			[Vector3(-a, y0, b), Vector3(-a, y0, -b), Vector3(0, y1, -r2), Vector3(0, y1, r2)],
			[Vector3(a, y0, -b), Vector3(a, y0, b), Vector3(0, y1, r2), Vector3(0, y1, -r2)],
			[Vector3(-a, y0, -b), Vector3(a, y0, -b), Vector3(0, y1, -r2)],
			[Vector3(a, y0, b), Vector3(-a, y0, b), Vector3(0, y1, r2)],
		]
	for poly: Array in pts:
		var n: Vector3 = ((poly[1] as Vector3) - (poly[0] as Vector3)).cross((poly[2] as Vector3) - (poly[0] as Vector3)).normalized()
		if n.y < 0.0:
			n = -n
		var tris := [[0, 1, 2]] if poly.size() == 3 else [[0, 1, 2], [0, 2, 3]]
		for tri: Array in tris:
			for idx: int in tri:
				st.set_color(SLATE)
				st.set_normal(n)
				st.add_vertex(cen + (poly[idx] as Vector3))
	kit["op_n"] = true
	# eaves board + ridge
	var I := Transform3D.IDENTITY
	_b(kit, "op", I, cen + Vector3(0.0, base_y - 0.12, -b), Vector3(2.0 * a, 0.3, 0.12), WHITE)
	_b(kit, "op", I, cen + Vector3(0.0, base_y - 0.12, b), Vector3(2.0 * a, 0.3, 0.12), WHITE)
	_b(kit, "op", I, cen + Vector3(-a, base_y - 0.12, 0.0), Vector3(0.12, 0.3, 2.0 * b), WHITE)
	_b(kit, "op", I, cen + Vector3(a, base_y - 0.12, 0.0), Vector3(0.12, 0.3, 2.0 * b), WHITE)
	if a >= b:
		_b(kit, "op", I, cen + Vector3(0.0, y1 + 0.05, 0.0), Vector3(2.0 * (a - b) + 0.3, 0.18, 0.3), SLATE.darkened(0.2))
	else:
		_b(kit, "op", I, cen + Vector3(0.0, y1 + 0.05, 0.0), Vector3(0.3, 0.18, 2.0 * (b - a) + 0.3), SLATE.darkened(0.2))


# white flat-roofed sports hall with roof seams, brick walls, clerestory band
static func _flat_hall(kit: Dictionary, r: Array, h: float) -> void:
	var c: Vector2 = r[0]
	var sz: Vector2 = r[1]
	var I := Transform3D.IDENTITY
	var cen := Vector3(c.x, 0.0, c.y)
	_b(kit, "op", I, cen + Vector3(0.0, h * 0.5, 0.0), Vector3(sz.x, h, sz.y), BRICK)
	_b(kit, "op", I, cen + Vector3(0.0, 0.6, 0.0), Vector3(sz.x + 0.3, 1.2, sz.y + 0.3), STONE)
	for s: float in [-1.0, 1.0]:
		_b(kit, "gl", I, cen + Vector3(0.0, h - 1.8, s * (sz.y * 0.5 + 0.03)), Vector3(sz.x - 3.0, 1.8, 0.06), GLASS)
		_b(kit, "gl", I, cen + Vector3(s * (sz.x * 0.5 + 0.03), h - 1.8, 0.0), Vector3(0.06, 1.8, sz.y - 3.0), GLASS)
	_b(kit, "op", I, cen + Vector3(0.0, h + 0.3, 0.0), Vector3(sz.x + 1.0, 0.6, sz.y + 1.0), Color(0.90, 0.91, 0.92))
	var n := int(sz.x / 9.0)
	for k in range(1, n):
		_b(kit, "op", I, cen + Vector3(-sz.x * 0.5 + float(k) * sz.x / float(n), h + 0.65, 0.0), Vector3(0.35, 0.12, sz.y + 0.9), Color(0.80, 0.82, 0.84))


static func _dome(sc: Node3D, top: Vector3) -> void:
	var drum := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.6
	cm.bottom_radius = 4.6
	cm.height = 2.2
	drum.mesh = cm
	drum.material_override = JiaxingLandmarks._mat(WHITE, 0.6)
	drum.position = top + Vector3(0.0, 1.1, 0.0)
	sc.add_child(drum)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.5
	sm.height = 9.0
	sm.is_hemisphere = true
	dome.mesh = sm
	var dm := JiaxingLandmarks._mat(Color(0.82, 0.84, 0.86), 0.25, 0.8)
	dome.material_override = dm
	dome.position = top + Vector3(0.0, 2.2, 0.0)
	sc.add_child(dome)


# clock tower (photo): brick shaft with white corner piers and belts, white clock storey, small hipped cap
static func _clock_tower(sc: Node3D, kit: Dictionary, c: Vector3) -> void:
	var I := Transform3D.IDENTITY
	var th := 26.0
	_b(kit, "op", I, c + Vector3(0.0, th * 0.5, 0.0), Vector3(6.0, th, 6.0), BRICK)
	_b(kit, "op", I, c + Vector3(0.0, 0.8, 0.0), Vector3(7.0, 1.6, 7.0), STONE)
	for by: float in [9.0, 18.0, th]:
		_b(kit, "op", I, c + Vector3(0.0, by, 0.0), Vector3(6.6, 0.45, 6.6), WHITE)
	_b(kit, "op", I, c + Vector3(0.0, th + 2.2, 0.0), Vector3(6.4, 4.0, 6.4), BRICK_D)
	for f: Vector3 in [Vector3(3.22, 0, 0), Vector3(-3.22, 0, 0), Vector3(0, 0, 3.22), Vector3(0, 0, -3.22)]:
		var s := Vector3(0.06, 2.4, 2.4) if absf(f.x) > 0.1 else Vector3(2.4, 2.4, 0.06)
		_b(kit, "em", I, c + f + Vector3(0.0, th + 2.2, 0.0), s, Color(1.0, 0.98, 0.92))
		_b(kit, "op", I, c + f * 1.02 + Vector3(0.0, th + 2.5, 0.0), Vector3(0.1, 1.0, 0.1), FRAME)
	_b(kit, "op", I, c + Vector3(0.0, th + 4.4, 0.0), Vector3(7.2, 0.5, 7.2), WHITE)
	_hip_roof(kit, c, Vector2(5.6, 5.6), th + 4.6, 0.6)


static func _courtyard_garden(kit: Dictionary, r: Array) -> void:
	var c: Vector2 = r[0]
	var sz: Vector2 = r[1]
	var I := Transform3D.IDENTITY
	_b(kit, "op", I, Vector3(c.x, 0.06, c.y), Vector3(sz.x, 0.06, sz.y), Color(0.25, 0.42, 0.20))
	# diamond / cross path pattern with a round centre bed (as seen from above)
	for k in range(2):
		var ang := 0.6 if k == 0 else -0.6
		var xf := Transform3D(Basis(Vector3.UP, ang), Vector3(c.x, 0.11, c.y))
		RoadSignBuilder._box(kit["op"], xf, Vector3(sz.x * 1.05, 0.04, 2.2), STONE_LT)
	_b(kit, "op", I, Vector3(c.x, 0.12, c.y), Vector3(sz.x, 0.04, 2.0), STONE_LT)
	_b(kit, "op", I, Vector3(c.x, 0.12, c.y), Vector3(2.0, 0.04, sz.y), STONE_LT)
	var ring_i: Array = []
	var ring_o: Array = []
	for k2 in range(33):
		var a := TAU * float(k2) / 32.0
		ring_i.append(c + Vector2(cos(a), sin(a)) * 5.0)
		ring_o.append(c + Vector2(cos(a), sin(a)) * 6.4)
	_strip(kit, ring_i, ring_o, 0.13, STONE_LT)
	# clipped box hedges along the diamond
	for s: float in [-1.0, 1.0]:
		for s2: float in [-1.0, 1.0]:
			_b(kit, "op", I, Vector3(c.x + s * sz.x * 0.25, 0.45, c.y + s2 * sz.y * 0.25), Vector3(6.0, 0.7, 4.0), Color(0.18, 0.34, 0.15))


static func _fan_plaza(kit: Dictionary, c: Vector3, r: float) -> void:
	var pts: Array = [Vector2(c.x, c.z)]
	for k in range(25):
		var a := PI * float(k) / 24.0 # opening to the south
		pts.append(Vector2(c.x + cos(a) * r, c.z + sin(a) * r))
	_flat(kit, pts, 0.09, Color(0.80, 0.78, 0.74))


static func _courts(kit: Dictionary, r: Array, nx: int, nz: int) -> void:
	var c: Vector2 = r[0]
	var sz: Vector2 = r[1]
	var I := Transform3D.IDENTITY
	_b(kit, "op", I, Vector3(c.x, 0.06, c.y), Vector3(sz.x, 0.08, sz.y), COURT)
	var cw := sz.x / float(nx)
	var cl := sz.y / float(nz)
	for i in range(nx):
		for j in range(nz):
			var cc := Vector3(c.x - sz.x * 0.5 + (float(i) + 0.5) * cw, 0.0, c.y - sz.y * 0.5 + (float(j) + 0.5) * cl)
			var w := minf(cw - 4.0, 15.0)
			var l := minf(cl - 4.0, 28.0)
			_b(kit, "op", I, cc + Vector3(0.0, 0.11, 0.0), Vector3(w, 0.03, l), COURT_IN)
			for lz: float in [-l * 0.5, 0.0, l * 0.5]:
				_b(kit, "op", I, cc + Vector3(0.0, 0.135, lz), Vector3(w, 0.02, 0.08), LINE)
			for lx: float in [-w * 0.5, w * 0.5]:
				_b(kit, "op", I, cc + Vector3(lx, 0.135, 0.0), Vector3(0.08, 0.02, l), LINE)
			for kz: float in [-1.0, 1.0]:
				_b(kit, "op", I, cc + Vector3(0.0, 1.6, kz * (l * 0.5 + 0.9)), Vector3(0.16, 3.2, 0.16), Color(0.22, 0.24, 0.27))
				_b(kit, "op", I, cc + Vector3(0.0, 3.4, kz * (l * 0.5 - 0.2)), Vector3(1.8, 1.05, 0.05), Color(0.97, 0.97, 0.97))
				_b(kit, "op", I, cc + Vector3(0.0, 3.05, kz * (l * 0.5 - 0.5)), Vector3(0.46, 0.03, 0.46), Color(0.92, 0.42, 0.12))
	for s: float in [-1.0, 1.0]:
		_b(kit, "op", I, Vector3(c.x + s * sz.x * 0.5, 1.8, c.y), Vector3(0.08, 0.08, sz.y), FRAME)
		_b(kit, "op", I, Vector3(c.x, 1.8, c.y + s * sz.y * 0.5), Vector3(sz.x, 0.08, 0.08), FRAME)


static func _trees(sc: Node3D) -> void:
	var P := ParkLandscapeBuilder
	# camphor avenue from the gate to the round plaza
	for ax in range(-196, -118, 10):
		for side: float in [-1.0, 1.0]:
			P.plant_tree(sc, Vector3(float(ax), 0.0, GATE_Z + side * 13.0), 1, 1.7, P.CAMPHOR if ax % 20 == 0 else P.CAMPHOR_LT)
	# the wooded heart of the campus (dense camphor grove, pond excluded)
	var blocked := func(p: Vector2) -> bool:
		if Vector2((p.x - 38.0) / 16.0, (p.y - 50.0) / 30.0).length() < 1.0:
			return true
		if p.x < -40.0 and p.y > -126.0 and p.y < -68.0:
			return true # science hall
		if p.x < 6.0 and p.y > 22.0:
			return true # courtyard building east wing / fan plaza
		if absf(p.y - GATE_Z) < 4.0 or absf(p.y + 60.0) < 4.0 or absf(p.y - 92.0) < 5.0:
			return true # paths
		if Vector2(p.x + 30.0, p.y - GATE_Z).length() < 9.0:
			return true # clock tower
		return false
	# scattered, not gridded: hashed random positions over the grove, rejected where blocked or too close
	var placed: Array[Vector2] = []
	var k := 0
	var tries := 0
	while placed.size() < 140 and tries < 4000:
		tries += 1
		var h1 := fposmod(sin(float(tries) * 12.9898) * 43758.5453, 1.0)
		var h2 := fposmod(sin(float(tries) * 78.233 + 1.3) * 24634.6345, 1.0)
		var p := Vector2(lerpf(-62.0, 66.0, h1), lerpf(-94.0, 88.0, h2))
		if blocked.call(p):
			continue
		var ok := true
		for q: Vector2 in placed:
			if q.distance_squared_to(p) < 8.5 * 8.5:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		k += 1
		P.plant_tree(sc, Vector3(p.x, 0.0, p.y), 1, 1.6 + 0.6 * fposmod(h1 * 7.0, 1.0), P.CAMPHOR if k % 3 != 0 else P.CAMPHOR_LT)
	# perimeter rows (north, east, south) and between the north-east dorm rows
	for x in range(-196, 206, 20):
		P.plant_tree(sc, Vector3(float(x), 0.0, -190.0), 1, 1.5, P.CAMPHOR_LT)
		P.plant_tree(sc, Vector3(float(x), 0.0, 190.0), 1, 1.5, P.CAMPHOR)
	for z in range(-182, 190, 20):
		P.plant_tree(sc, Vector3(202.0, 0.0, float(z)), 1, 1.5, P.CAMPHOR)
		P.plant_tree(sc, Vector3(-202.0, 0.0, float(z)), 1, 1.5, P.CAMPHOR_LT)
	for x2 in range(58, 206, 18):
		P.plant_tree(sc, Vector3(float(x2), 0.0, -159.0), 3, 0.8, Color(0.30, 0.48, 0.20))


# Standard 400 m track (inner radius 36.5 m, straights 84.39 m along z, 8 lanes x 1.22 m), football pitch with
# goals and markings, covered stepped grandstand on the west straight, four floodlight masts
static func _stadium(kit: Dictionary, c: Vector3) -> void:
	var I := Transform3D.IDENTITY
	var half_s := 84.39 * 0.5
	var ri := 36.5
	var lanes := 8
	var lw := 1.22
	var ro := ri + float(lanes) * lw
	var outline := func(r: float) -> Array:
		var pts: Array = []
		for k in range(25):
			var a := PI + PI * float(k) / 24.0
			pts.append(Vector2(c.x + cos(a) * r, c.z - half_s + sin(a) * r))
		for k2 in range(25):
			var a2 := PI * float(k2) / 24.0
			pts.append(Vector2(c.x + cos(a2) * r, c.z + half_s + sin(a2) * r))
		pts.append(pts[0])
		return pts
	# green surround (the field's corners), track, infield
	_b(kit, "op", I, Vector3(c.x, 0.05, c.z), Vector3(2.0 * (ro + 4.0), 0.04, 2.0 * (half_s + ro + 4.0)), Color(0.27, 0.46, 0.24))
	_strip(kit, outline.call(ri), outline.call(ro), 0.07, TRACK)
	var inner: Array = outline.call(ri)
	inner.pop_back()
	_flat(kit, inner, 0.065, PITCH)
	for li in range(lanes + 1):
		var r := ri + float(li) * lw
		_strip(kit, outline.call(r - 0.025), outline.call(r + 0.025), 0.078, LINE)
	# start / finish line across the home straight
	_b(kit, "op", I, Vector3(c.x - ri - float(lanes) * lw * 0.5, 0.079, c.z + half_s - 2.0), Vector3(float(lanes) * lw, 0.01, 0.06), LINE)
	# football pitch 100 x 64 with markings and goals
	var pw := 64.0
	var pl := 100.0
	for z: float in [-pl * 0.5, 0.0, pl * 0.5]:
		_b(kit, "op", I, Vector3(c.x, 0.08, c.z + z), Vector3(pw, 0.01, 0.12), LINE)
	for x: float in [-pw * 0.5, pw * 0.5]:
		_b(kit, "op", I, Vector3(c.x + x, 0.08, c.z), Vector3(0.12, 0.01, pl), LINE)
	var cc_in: Array = []
	var cc_out: Array = []
	for k3 in range(41):
		var a3 := TAU * float(k3) / 40.0
		cc_in.append(Vector2(c.x + cos(a3) * 9.08, c.z + sin(a3) * 9.08))
		cc_out.append(Vector2(c.x + cos(a3) * 9.2, c.z + sin(a3) * 9.2))
	_strip(kit, cc_in, cc_out, 0.081, LINE)
	for s: float in [-1.0, 1.0]:
		var gz := c.z + s * pl * 0.5
		# penalty / goal boxes
		_b(kit, "op", I, Vector3(c.x, 0.08, gz - s * 16.5), Vector3(40.3, 0.01, 0.12), LINE)
		for bx: float in [-20.15, 20.15]:
			_b(kit, "op", I, Vector3(c.x + bx, 0.08, gz - s * 8.25), Vector3(0.12, 0.01, 16.5), LINE)
		_b(kit, "op", I, Vector3(c.x, 0.08, gz - s * 5.5), Vector3(18.3, 0.01, 0.12), LINE)
		# goal frame + net back
		for gx: float in [-3.66, 3.66]:
			_b(kit, "op", I, Vector3(c.x + gx, 1.22, gz), Vector3(0.12, 2.44, 0.12), LINE)
		_b(kit, "op", I, Vector3(c.x, 2.44, gz), Vector3(7.44, 0.12, 0.12), LINE)
		_b(kit, "op", I, Vector3(c.x, 1.0, gz + s * 1.6), Vector3(7.3, 2.0, 0.03), Color(0.88, 0.90, 0.92))
	# grandstand on the west straight: 8 stepped rows with seats, back wall, cantilever roof on columns
	# grandstand on the EAST straight (as on the real campus), facing west over the pitch
	var gx0 := c.x + ro + 3.0
	for row in range(8):
		var rx := gx0 + float(row) * 0.85
		var ry := 0.45 * float(row + 1)
		_b(kit, "op", I, Vector3(rx, ry * 0.5, c.z), Vector3(0.85, ry, 70.0), Color(0.70, 0.70, 0.68))
		_b(kit, "op", I, Vector3(rx - 0.1, ry + 0.22, c.z), Vector3(0.45, 0.42, 68.0), SEAT_A if row % 3 != 1 else SEAT_B)
	var back_x := gx0 + 8.0 * 0.85 + 0.3
	_b(kit, "op", I, Vector3(back_x, 3.2, c.z), Vector3(0.6, 6.4, 72.0), WHITE)
	for k4 in range(7):
		_b(kit, "op", I, Vector3(back_x, 5.0, c.z - 33.0 + float(k4) * 11.0), Vector3(0.6, 10.0, 0.6), WHITE)
	var roof_xf := Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(8.0)), Vector3(gx0 + 2.0, 10.2, c.z))
	RoadSignBuilder._box(kit["op"], roof_xf, Vector3(12.0, 0.4, 74.0), Color(0.90, 0.92, 0.94))
	# floodlight masts
	for fx: float in [c.x - ro - 1.5, c.x + ro + 1.5]:
		for fz: float in [c.z - half_s - 20.0, c.z + half_s + 20.0]:
			_b(kit, "op", I, Vector3(fx, 11.0, fz), Vector3(0.5, 22.0, 0.5), Color(0.62, 0.64, 0.66))
			_b(kit, "em", I, Vector3(fx, 22.4, fz), Vector3(3.6, 1.4, 0.6), Color(1.0, 0.98, 0.92))
