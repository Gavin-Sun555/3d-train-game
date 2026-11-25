class_name SchoolBuilder
extends RefCounted

# Contemporary Chinese senior high school campus (浙江省嘉兴市第一中学): 外廊式 teaching blocks linked by covered
# bridge corridors into courtyard quads, a library with the century clock tower, dormitories with balconies, a
# canteen, a barrel-vaulted gymnasium, a standard 400 m athletics stadium with a grandstand, basketball courts, a
# flag plaza on the main gate axis and see-through railing fences. All boxes are batched per material class
# into one mesh (opaque vertex colour / glass / glow), so the whole campus is a handful of draw calls.
#
# Local frame of the campus node: x east (-210 .. 210), z south (-196 .. 196); the main gate faces west (-x)
# onto 纺工路 at z = -34.

const WHITE := Color(0.92, 0.91, 0.88)
const BRICK := Color(0.63, 0.31, 0.24)
const BRICK_D := Color(0.52, 0.25, 0.20)
const STONE := Color(0.56, 0.56, 0.57)
const STONE_LT := Color(0.74, 0.73, 0.70)
const FRAME := Color(0.20, 0.22, 0.25)
const ROOF := Color(0.33, 0.35, 0.38)
const GLASS := Color(0.30, 0.44, 0.55)
const TRACK := Color(0.66, 0.24, 0.19)
const PITCH := Color(0.22, 0.47, 0.20)
const LINE := Color(0.95, 0.96, 0.95)
const COURT := Color(0.23, 0.42, 0.52)
const COURT_IN := Color(0.62, 0.30, 0.24)
const SEAT_A := Color(0.15, 0.40, 0.70)
const SEAT_B := Color(0.90, 0.78, 0.25)


static func build(sc: Node3D, lights: Array) -> void:
	var kit := {"op": _st(), "gl": _st(), "em": _st()}
	var labels := Node3D.new()
	labels.name = "SchoolSigns"
	sc.add_child(labels)

	_grounds(sc, kit)
	_fence(kit)
	_main_gate(kit, labels)
	_flag_plaza(sc, kit, Vector3(-150.0, 0.0, -34.0))

	# North teaching quad (明德楼 / 求是楼 / 致远楼): 5 storeys, corridors facing south, linked at both ends
	var north_z := [-172.0, -136.0, -100.0]
	var north_names := ["致远楼", "求是楼", "明德楼"]
	for i in range(3):
		_teaching_block(kit, Transform3D(Basis.IDENTITY, Vector3(-118.0, 0.0, north_z[i])), 92.0, 18.0, 5, labels, north_names[i])
	for i in range(2):
		for lx: float in [-170.0, -66.0]:
			_link(kit, Vector3(lx, 0.0, north_z[i] + 9.0), Vector3(lx, 0.0, north_z[i + 1] - 9.0), 5)
	# South quad (格致楼 science & labs, 博雅楼 arts): 4 storeys
	var south_z := [10.0, 46.0, 82.0]
	var south_names := ["格致楼", "博雅楼", "实验楼"]
	for i in range(3):
		_teaching_block(kit, Transform3D(Basis.IDENTITY, Vector3(-118.0, 0.0, south_z[i])), 92.0, 18.0, 4, labels, south_names[i])
	for i in range(2):
		for lx2: float in [-170.0, -66.0]:
			_link(kit, Vector3(lx2, 0.0, south_z[i] + 9.0), Vector3(lx2, 0.0, south_z[i + 1] - 9.0), 4)
	# covered walkway across the gate axis joining both quads
	_link(kit, Vector3(-66.0, 0.0, -91.0), Vector3(-66.0, 0.0, 1.0), 1)

	_library_and_clock_tower(sc, kit, labels, Vector3(12.0, 0.0, -120.0))
	for di in range(3):
		_dorm_block(kit, Transform3D(Basis.IDENTITY, Vector3(124.0, 0.0, -162.0 + float(di) * 44.0)), 116.0, 15.0, 6, labels, "学生公寓 %d 号楼" % (di + 1))
	_canteen(kit, labels, Vector3(148.0, 0.0, -36.0))
	_gym(kit, labels, Vector3(-126.0, 0.0, 140.0), 60.0, 46.0)
	_courts(kit, Vector3(12.0, 0.0, 136.0))
	_stadium(kit, Vector3(130.0, 0.0, 92.0))

	# Trees: main avenue, quad courtyards, central garden, around the stadium
	for ax in range(-196, 196, 14):
		if absf(float(ax) + 150.0) < 16.0 or absf(float(ax) + 28.0) < 7.0 or absf(float(ax) - 60.0) < 7.0:
			continue
		for sz_: float in [-41.0, -27.0]:
			ParkLandscapeBuilder.plant_tree(sc, Vector3(float(ax), 0.0, sz_), 1, 0.95, ParkLandscapeBuilder.CAMPHOR if ax % 28 == 0 else ParkLandscapeBuilder.CAMPHOR_LT)
	for cz: float in [-154.0, -118.0, 28.0, 64.0]:
		for cx in range(-150, -80, 16):
			ParkLandscapeBuilder.plant_tree(sc, Vector3(float(cx), 0.0, cz), 3 if int(cz) % 2 == 0 else 4, 0.8, Color(0.30, 0.48, 0.20))
	for ti in range(24):
		var tx := -40.0 + float(ti % 6) * 18.0 + (8.0 if (ti / 6) % 2 == 1 else 0.0)
		var tz := -14.0 + float(ti / 6) * 20.0
		if Vector2(tx - 8.0, tz - 22.0).length() < 25.0:
			continue
		ParkLandscapeBuilder.plant_tree(sc, Vector3(tx, 0.0, tz), 1, 1.05, ParkLandscapeBuilder.CAMPHOR if ti % 2 == 0 else ParkLandscapeBuilder.CAMPHOR_LT)
	for at_z: float in [-175.0, -145.0, -115.0, -85.0, 12.0, 48.0, 88.0, 128.0, 168.0]:
		ParkLandscapeBuilder.plant_tree(sc, Vector3(-200.0, 0.0, at_z), 1, 1.05, ParkLandscapeBuilder.CAMPHOR_LT)
	for k in range(10):
		ParkLandscapeBuilder.plant_tree(sc, Vector3(186.0, 0.0, 10.0 + float(k) * 17.0), 1, 1.0, ParkLandscapeBuilder.CAMPHOR)

	_commit(sc, kit)
	JiaxingCivicLandmarks._add_light(sc, Vector3(-206.0, 12.0, -34.0), Color(1.0, 0.90, 0.72), 62.0, lights)
	JiaxingCivicLandmarks._add_light(sc, Vector3(-150.0, 10.0, -34.0), Color(1.0, 0.90, 0.72), 40.0, lights)
	JiaxingCivicLandmarks._add_light(sc, Vector3(130.0, 20.0, 92.0), Color(1.0, 0.96, 0.88), 90.0, lights)


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
	# paved gate axis avenue, campus ring roads and building aprons
	_b(kit, "op", I, Vector3(0.0, 0.05, -34.0), Vector3(400.0, 0.06, 12.0), STONE_LT)
	_b(kit, "op", I, Vector3(-28.0, 0.05, 0.0), Vector3(9.0, 0.06, 376.0), STONE_LT)
	_b(kit, "op", I, Vector3(60.0, 0.05, -40.0), Vector3(9.0, 0.06, 300.0), STONE_LT)
	_b(kit, "op", I, Vector3(-118.0, 0.05, -136.0), Vector3(120.0, 0.06, 96.0), Color(0.68, 0.67, 0.64))
	_b(kit, "op", I, Vector3(-118.0, 0.05, 46.0), Vector3(120.0, 0.06, 96.0), Color(0.68, 0.67, 0.64))
	_b(kit, "op", I, Vector3(-232.0, 0.03, 12.0), Vector3(48.0, 0.06, 220.0), STONE_LT)
	# courtyard lawns inside the quads (on top of the aprons)
	for cz: float in [-154.0, -118.0, 28.0, 64.0]:
		_b(kit, "op", I, Vector3(-118.0, 0.10, cz), Vector3(84.0, 0.08, 12.0), Color(0.24, 0.42, 0.18))
	# central garden pond
	JiaxingLandmarks.add_fountain(sc, Vector3(8.0, 0.0, 22.0), 20.0, 0.16)
	var rim_in: Array = []
	var rim_out: Array = []
	for k in range(49):
		var a := TAU * float(k) / 48.0
		rim_in.append(Vector2(8.0 + cos(a) * 20.0, 22.0 + sin(a) * 20.0))
		rim_out.append(Vector2(8.0 + cos(a) * 21.2, 22.0 + sin(a) * 21.2))
	_strip(kit, rim_in, rim_out, 0.28, STONE_LT)


static func _fence(kit: Dictionary) -> void:
	var I := Transform3D.IDENTITY
	# [start, end] runs along the perimeter, leaving the gate openings
	var runs := [
		[Vector2(-208, -196), Vector2(-208, -52)], [Vector2(-208, -16), Vector2(-208, 196)],
		[Vector2(-208, -196), Vector2(-42, -196)], [Vector2(-18, -196), Vector2(208, -196)],
		[Vector2(-208, 196), Vector2(-40, 196)], [Vector2(-16, 196), Vector2(208, 196)],
		[Vector2(208, -196), Vector2(208, 196)],
	]
	for rn: Array in runs:
		var a: Vector2 = rn[0]
		var b: Vector2 = rn[1]
		var L := a.distance_to(b)
		var u := (b - a) / L
		var xf := Transform3D(Basis(Vector3.UP, -atan2(u.y, u.x)), Vector3(a.x, 0.0, a.y))
		_b(kit, "op", xf, Vector3(L * 0.5, 0.3, 0.0), Vector3(L, 0.6, 0.45), STONE_LT)
		_b(kit, "op", xf, Vector3(L * 0.5, 1.05, 0.0), Vector3(L, 0.07, 0.07), FRAME)
		_b(kit, "op", xf, Vector3(L * 0.5, 2.15, 0.0), Vector3(L, 0.07, 0.07), FRAME)
		var n := int(L / 3.0)
		for k in range(n + 1):
			_b(kit, "op", xf, Vector3(float(k) * L / float(maxi(1, n)), 1.25, 0.0), Vector3(0.32, 2.5, 0.32), WHITE if k % 4 == 0 else FRAME)
		# pickets every 0.5 m on the street fronts only (west / south), cheap thin bars elsewhere omitted
		if absf(a.x + 208.0) < 0.1 and absf(b.x + 208.0) < 0.1:
			var np := int(L / 0.6)
			for k2 in range(np):
				_b(kit, "op", xf, Vector3(float(k2) * 0.6 + 0.3, 1.6, 0.0), Vector3(0.035, 1.1, 0.035), FRAME)


static func _main_gate(kit: Dictionary, labels: Node3D) -> void:
	var I := Transform3D.IDENTITY
	# two brick pylons carrying a white span with the school name, sliding gate between, guard rooms each side
	for pz: float in [-50.5, -17.5]:
		_b(kit, "op", I, Vector3(-207.0, 5.2, pz), Vector3(3.4, 10.4, 3.4), BRICK)
		_b(kit, "op", I, Vector3(-207.0, 10.7, pz), Vector3(3.9, 0.6, 3.9), WHITE)
		_b(kit, "op", I, Vector3(-207.0, 0.4, pz), Vector3(3.8, 0.8, 3.8), STONE)
	_b(kit, "op", I, Vector3(-207.0, 9.1, -34.0), Vector3(3.0, 2.6, 30.0), WHITE)
	_b(kit, "op", I, Vector3(-207.0, 10.6, -34.0), Vector3(3.6, 0.4, 37.0), ROOF)
	_b(kit, "op", I, Vector3(-208.6, 9.1, -34.0), Vector3(0.1, 1.9, 24.0), BRICK_D)
	# retractable electric gate
	_b(kit, "op", I, Vector3(-207.6, 0.65, -34.0), Vector3(0.6, 1.3, 13.0), Color(0.62, 0.64, 0.66))
	for gz: float in [-58.0, -10.0]:
		_b(kit, "op", I, Vector3(-202.5, 1.8, gz), Vector3(7.0, 3.6, 8.0), WHITE)
		_b(kit, "gl", I, Vector3(-206.05, 1.9, gz), Vector3(0.08, 1.6, 6.4), GLASS)
		_b(kit, "op", I, Vector3(-202.5, 3.75, gz), Vector3(8.0, 0.3, 9.0), ROOF)
	_sign(labels, "浙江省嘉兴市第一中学", Vector3(-208.75, 9.55, -34.0), -PI * 0.5, 86, 0.024, Color(0.98, 0.84, 0.30))
	_sign(labels, "JIAXING NO.1 HIGH SCHOOL", Vector3(-208.75, 8.45, -34.0), -PI * 0.5, 40, 0.016, Color(0.96, 0.96, 0.98))
	# side gates
	for g: Array in [[Vector3(-30.0, 0.0, -196.0), "嘉兴一中 · 北门", PI], [Vector3(-28.0, 0.0, 196.0), "嘉兴一中 · 南门", 0.0]]:
		var c: Vector3 = g[0]
		for px: float in [-11.0, 11.0]:
			_b(kit, "op", I, c + Vector3(px, 3.4, 0.0), Vector3(2.4, 6.8, 2.4), BRICK)
		_b(kit, "op", I, c + Vector3(0.0, 6.6, 0.0), Vector3(25.0, 1.2, 3.0), WHITE)
		_sign(labels, str(g[1]), c + Vector3(0.0, 6.6, (-1.6 if float(g[2]) > 1.0 else 1.6)), float(g[2]), 60, 0.022, Color(0.98, 0.84, 0.30))


static func _flag_plaza(sc: Node3D, kit: Dictionary, c: Vector3) -> void:
	var I := Transform3D.IDENTITY
	var ring_a: Array = []
	var ring_b: Array = []
	for k in range(41):
		var a := TAU * float(k) / 40.0
		ring_a.append(Vector2(c.x + cos(a) * 11.0, c.z + sin(a) * 11.0))
		ring_b.append(Vector2(c.x + cos(a) * 14.0, c.z + sin(a) * 14.0))
	_strip(kit, ring_a, ring_b, 0.09, Color(0.60, 0.59, 0.57))
	var disc: Array = []
	for k in range(40):
		var a2 := TAU * float(k) / 40.0
		disc.append(Vector2(c.x + cos(a2) * 11.0, c.z + sin(a2) * 11.0))
	_flat(kit, disc, 0.09, STONE_LT)
	# raised flag platform (升旗台) with steps
	_b(kit, "op", I, c + Vector3(0.0, 0.35, 0.0), Vector3(9.0, 0.7, 6.0), STONE)
	_b(kit, "op", I, c + Vector3(-3.0, 0.18, 0.0), Vector3(3.0, 0.35, 6.0), STONE_LT)
	for k3 in range(3):
		var fz := c.z + (float(k3) - 1.0) * 2.2
		var h := 15.0 if k3 == 1 else 12.0
		_b(kit, "op", I, Vector3(c.x + 1.5, 0.7 + h * 0.5, fz), Vector3(0.16, h, 0.16), Color(0.86, 0.87, 0.88))
		_b(kit, "op", I, Vector3(c.x + 1.5, 0.7 + h - 1.1, fz + 1.2), Vector3(0.04, 1.6, 2.4), Color(0.86, 0.10, 0.10) if k3 == 1 else Color(0.90, 0.88, 0.85))


# ------------------------------------------------------------------------------------------------- buildings
# 外廊式 teaching block along local x: classrooms on the north side (-z) with window walls, an open corridor with
# white parapets and a column row on the south side (+z), brick-red stair towers at both ends, flat parapeted roof
static func _teaching_block(kit: Dictionary, xf: Transform3D, L: float, D: float, floors: int, labels: Node3D, name_zh: String) -> void:
	var fh := 3.9
	var H := float(floors) * fh
	var corr := 2.6
	var db := D - corr
	var cb := -corr * 0.5
	_b(kit, "op", xf, Vector3(0.0, H * 0.5, cb), Vector3(L, H, db), WHITE)
	_b(kit, "op", xf, Vector3(0.0, 0.5, cb), Vector3(L + 0.2, 1.0, db + 0.2), STONE)
	var zn := -D * 0.5
	var zc := D * 0.5 - corr
	for f in range(floors):
		var y0 := float(f) * fh
		# classroom window wall + mullions + brick sill band
		_b(kit, "gl", xf, Vector3(0.0, y0 + 2.05, zn - 0.03), Vector3(L - 6.0, 2.1, 0.06), GLASS)
		var nm := int((L - 6.0) / 1.6)
		for k in range(nm + 1):
			_b(kit, "op", xf, Vector3(-(L - 6.0) * 0.5 + float(k) * (L - 6.0) / float(nm), y0 + 2.05, zn - 0.07), Vector3(0.09, 2.2, 0.08), FRAME)
		_b(kit, "op", xf, Vector3(0.0, y0 + 0.92, zn - 0.12), Vector3(L - 5.0, 0.2, 0.28), BRICK)
		_b(kit, "op", xf, Vector3(0.0, y0 + 3.3, zn - 0.08), Vector3(L - 5.0, 0.16, 0.18), STONE_LT)
		# corridor: deck slab, parapet with handrail, inner wall doors / windows
		if f > 0:
			_b(kit, "op", xf, Vector3(0.0, y0 + 0.11, zc + corr * 0.5), Vector3(L, 0.22, corr), WHITE)
			_b(kit, "op", xf, Vector3(0.0, y0 + 0.66, D * 0.5 - 0.1), Vector3(L, 1.1, 0.2), WHITE)
			_b(kit, "op", xf, Vector3(0.0, y0 + 1.24, D * 0.5 - 0.1), Vector3(L, 0.07, 0.3), FRAME)
			_b(kit, "op", xf, Vector3(0.0, y0 + 0.3, D * 0.5 - 0.05), Vector3(L, 0.12, 0.32), BRICK)
		_b(kit, "gl", xf, Vector3(0.0, y0 + 1.9, zc + 0.03), Vector3(L - 6.0, 1.7, 0.05), Color(0.24, 0.34, 0.42))
		var nd := int(L / 9.0)
		for k2 in range(nd):
			_b(kit, "op", xf, Vector3(-L * 0.5 + 4.5 + float(k2) * 9.0, y0 + 1.25, zc + 0.06), Vector3(1.1, 2.4, 0.06), Color(0.55, 0.38, 0.26))
	# corridor column row and corridor roof
	var ncol := int(L / 4.2)
	for k3 in range(ncol + 1):
		_b(kit, "op", xf, Vector3(-L * 0.5 + float(k3) * L / float(ncol), H * 0.5, D * 0.5 - 0.25), Vector3(0.42, H, 0.42), WHITE)
	_b(kit, "op", xf, Vector3(0.0, H + 0.15, 0.0), Vector3(L + 0.6, 0.3, D + 0.6), ROOF)
	# parapet + brick coping
	for pz: float in [-D * 0.5 - 0.15, D * 0.5 + 0.15]:
		_b(kit, "op", xf, Vector3(0.0, H + 0.85, pz), Vector3(L + 0.6, 1.1, 0.3), WHITE)
		_b(kit, "op", xf, Vector3(0.0, H + 1.45, pz), Vector3(L + 0.8, 0.12, 0.42), BRICK)
	# brick-red stair towers with a vertical glass slot
	for sx: float in [-1.0, 1.0]:
		var tx := sx * (L * 0.5 + 3.1)
		_b(kit, "op", xf, Vector3(tx, (H + 3.4) * 0.5, 0.0), Vector3(6.2, H + 3.4, D + 0.8), BRICK)
		_b(kit, "gl", xf, Vector3(tx, H * 0.5 + 1.0, -D * 0.5 - 0.43), Vector3(1.6, H - 2.0, 0.06), GLASS)
		_b(kit, "gl", xf, Vector3(tx, H * 0.5 + 1.0, D * 0.5 + 0.43), Vector3(1.6, H - 2.0, 0.06), GLASS)
		_b(kit, "op", xf, Vector3(tx, H + 3.6, 0.0), Vector3(6.8, 0.4, D + 1.4), WHITE)
	var sp := xf * Vector3(0.0, H + 1.0, -D * 0.5 - 0.35)
	_sign(labels, name_zh, sp, 0.0 + xf.basis.get_euler().y + PI, 96, 0.028, Color(0.86, 0.16, 0.12))


# covered bridge corridor (连廊) between two points on the ground plan, one deck per upper floor
static func _link(kit: Dictionary, a: Vector3, b: Vector3, floors: int) -> void:
	var L := a.distance_to(b)
	if L < 0.5:
		return
	var u := (b - a) / L
	var xf := Transform3D(Basis(Vector3.UP, -atan2(u.z, u.x)), a)
	var fh := 3.9
	var w := 3.4
	for f in range(maxi(1, floors)):
		var y0 := float(f) * fh
		if f > 0 or floors == 1:
			_b(kit, "op", xf, Vector3(L * 0.5, y0 + (0.11 if f > 0 else 0.08), 0.0), Vector3(L, 0.22, w), WHITE)
		if f > 0:
			for s: float in [-1.0, 1.0]:
				_b(kit, "op", xf, Vector3(L * 0.5, y0 + 0.65, s * (w * 0.5 - 0.1)), Vector3(L, 1.1, 0.2), WHITE)
				_b(kit, "gl", xf, Vector3(L * 0.5, y0 + 2.2, s * (w * 0.5 - 0.1)), Vector3(L, 1.7, 0.05), GLASS)
	var top := float(maxi(1, floors)) * fh if floors > 1 else 3.2
	_b(kit, "op", xf, Vector3(L * 0.5, top + 0.15, 0.0), Vector3(L + 0.4, 0.3, w + 0.6), ROOF)
	var nc := maxi(1, int(L / 6.0))
	for k in range(nc + 1):
		for s2: float in [-1.0, 1.0]:
			_b(kit, "op", xf, Vector3(float(k) * L / float(nc), top * 0.5, s2 * (w * 0.5 - 0.2)), Vector3(0.35, top, 0.35), WHITE)


static func _dorm_block(kit: Dictionary, xf: Transform3D, L: float, D: float, floors: int, labels: Node3D, name_zh: String) -> void:
	var fh := 3.2
	var H := float(floors) * fh
	_b(kit, "op", xf, Vector3(0.0, H * 0.5, 0.0), Vector3(L, H, D), WHITE)
	_b(kit, "op", xf, Vector3(0.0, 0.6, 0.0), Vector3(L + 0.2, 1.2, D + 0.2), BRICK_D)
	var nb := int(L / 3.6)
	for f in range(floors):
		var y0 := float(f) * fh
		_b(kit, "op", xf, Vector3(0.0, y0 + 0.08, 0.0), Vector3(L + 0.1, 0.16, D + 0.1), STONE_LT)
		for k in range(nb):
			var x := -L * 0.5 + 1.8 + float(k) * 3.6
			# north: room window
			_b(kit, "gl", xf, Vector3(x, y0 + 1.75, -D * 0.5 - 0.03), Vector3(1.6, 1.5, 0.06), GLASS)
			if f > 0:
				# south: balcony slab, parapet, door
				_b(kit, "op", xf, Vector3(x, y0 + 0.08, D * 0.5 + 0.7), Vector3(3.3, 0.16, 1.4), WHITE)
				_b(kit, "op", xf, Vector3(x, y0 + 0.62, D * 0.5 + 1.34), Vector3(3.3, 1.0, 0.12), BRICK if k % 2 == 0 else WHITE)
				_b(kit, "gl", xf, Vector3(x, y0 + 1.5, D * 0.5 + 0.03), Vector3(2.4, 2.2, 0.06), GLASS)
	for sx: float in [-1.0, 1.0]:
		_b(kit, "op", xf, Vector3(sx * (L * 0.5 + 2.6), (H + 2.6) * 0.5, 0.0), Vector3(5.2, H + 2.6, D + 0.6), BRICK)
	_b(kit, "op", xf, Vector3(0.0, H + 0.15, 0.0), Vector3(L + 0.4, 0.3, D + 0.4), ROOF)
	for pz: float in [-D * 0.5 - 0.1, D * 0.5 + 0.1]:
		_b(kit, "op", xf, Vector3(0.0, H + 0.75, pz), Vector3(L + 0.4, 0.9, 0.2), WHITE)
	_b(kit, "op", xf, Vector3(L * 0.25, H + 1.6, 0.0), Vector3(4.0, 2.6, 4.0), STONE)
	_sign(labels, name_zh, xf * Vector3(-L * 0.5 + 12.0, H + 1.2, -D * 0.5 - 0.25), PI, 64, 0.022, Color(0.86, 0.16, 0.12))


static func _library_and_clock_tower(sc: Node3D, kit: Dictionary, labels: Node3D, c: Vector3) -> void:
	var I := Transform3D.IDENTITY
	var L := 44.0
	var D := 32.0
	var H := 4.0 * 4.4
	_b(kit, "op", I, c + Vector3(0.0, H * 0.5, 0.0), Vector3(L, H, D), WHITE)
	# west front: full-height glass curtain wall with white vertical fins, cantilevered roof
	_b(kit, "gl", I, c + Vector3(0.0, H * 0.5, D * 0.5 + 0.05), Vector3(L - 6.0, H - 1.2, 0.08), GLASS)
	for k in range(int((L - 6.0) / 2.0) + 1):
		_b(kit, "op", I, c + Vector3(-(L - 6.0) * 0.5 + float(k) * 2.0, H * 0.5, D * 0.5 + 0.35), Vector3(0.25, H - 1.0, 0.6), WHITE)
	_b(kit, "op", I, c + Vector3(0.0, H + 0.3, 2.0), Vector3(L + 4.0, 0.6, D + 8.0), WHITE)
	_b(kit, "op", I, c + Vector3(0.0, 0.25, D * 0.5 + 4.0), Vector3(L, 0.5, 8.0), STONE)
	_sign(labels, "图书馆", c + Vector3(0.0, H + 1.4, D * 0.5 + 5.6), 0.0, 96, 0.028, Color(0.86, 0.16, 0.12))
	# century clock tower at the east end: brick shaft, white corner piers and belts, clock faces, pyramid roof
	var t := c + Vector3(L * 0.5 + 8.0, 0.0, 0.0)
	var th := 30.0
	_b(kit, "op", I, t + Vector3(0.0, th * 0.5, 0.0), Vector3(10.0, th, 10.0), BRICK)
	for px: float in [-1.0, 1.0]:
		for pz: float in [-1.0, 1.0]:
			_b(kit, "op", I, t + Vector3(px * 4.8, th * 0.5, pz * 4.8), Vector3(1.2, th + 0.4, 1.2), WHITE)
	for by: float in [10.0, 20.0, th]:
		_b(kit, "op", I, t + Vector3(0.0, by, 0.0), Vector3(10.8, 0.6, 10.8), WHITE)
	for f: Vector3 in [Vector3(5.06, 0, 0), Vector3(-5.06, 0, 0), Vector3(0, 0, 5.06), Vector3(0, 0, -5.06)]:
		var sz := Vector3(0.1, 4.0, 4.0) if absf(f.x) > 0.1 else Vector3(4.0, 4.0, 0.1)
		_b(kit, "em", I, t + f + Vector3(0.0, 25.0, 0.0), sz, Color(1.0, 0.97, 0.88))
		var hand := Vector3(0.12, 1.6, 0.12) if absf(f.x) > 0.1 else Vector3(0.12, 1.6, 0.12)
		_b(kit, "op", I, t + f * 1.01 + Vector3(0.0, 25.5, 0.0), hand, FRAME)
	JiaxingLandmarks._add_cyl(sc, 0.4, 7.6, 6.0, t + Vector3(0.0, th + 3.3, 0.0), JiaxingLandmarks._mat(ROOF, 0.6, 0.15), 4, Vector3(0.0, PI * 0.25, 0.0))


static func _canteen(kit: Dictionary, labels: Node3D, c: Vector3) -> void:
	var I := Transform3D.IDENTITY
	var L := 68.0
	var D := 24.0
	var H := 9.4
	_b(kit, "op", I, c + Vector3(0.0, H * 0.5, 0.0), Vector3(L, H, D), WHITE)
	for f in range(2):
		for s: float in [-1.0, 1.0]:
			_b(kit, "gl", I, c + Vector3(0.0, float(f) * 4.7 + 2.6, s * (D * 0.5 + 0.03)), Vector3(L - 6.0, 2.8, 0.06), GLASS)
			for k in range(17):
				_b(kit, "op", I, c + Vector3(-(L - 6.0) * 0.5 + float(k) * (L - 6.0) / 16.0, float(f) * 4.7 + 2.6, s * (D * 0.5 + 0.08)), Vector3(0.12, 2.9, 0.1), FRAME)
	_b(kit, "op", I, c + Vector3(0.0, 4.7, 0.0), Vector3(L + 0.2, 0.4, D + 0.2), BRICK)
	_b(kit, "op", I, c + Vector3(0.0, H + 0.2, 0.0), Vector3(L + 2.0, 0.4, D + 2.0), ROOF)
	_sign(labels, "学生食堂", c + Vector3(0.0, H + 1.0, D * 0.5 + 1.1), 0.0, 80, 0.024, Color(0.86, 0.16, 0.12))


static func _gym(kit: Dictionary, labels: Node3D, c: Vector3, L: float, W: float) -> void:
	var I := Transform3D.IDENTITY
	var wall_h := 10.0
	_b(kit, "op", I, c + Vector3(0.0, wall_h * 0.5, 0.0), Vector3(W, wall_h, L), WHITE)
	_b(kit, "op", I, c + Vector3(0.0, 0.8, 0.0), Vector3(W + 0.2, 1.6, L + 0.2), BRICK)
	for s: float in [-1.0, 1.0]:
		_b(kit, "gl", I, c + Vector3(s * (W * 0.5 + 0.03), wall_h - 2.2, 0.0), Vector3(0.06, 2.4, L - 4.0), GLASS)
		for k in range(int(L / 6.0) + 1):
			_b(kit, "op", I, c + Vector3(s * (W * 0.5 + 0.2), wall_h * 0.5, -L * 0.5 + float(k) * 6.0), Vector3(0.5, wall_h, 0.6), BRICK)
	# barrel-vaulted roof across the width (silver standing-seam), gable ends closed in white
	var segs := 14
	var half_ang := deg_to_rad(52.0)
	var R := (W * 0.5 + 0.6) / sin(half_ang)
	var cy := wall_h - R * cos(half_ang)
	for i in range(segs):
		var a0 := -half_ang + 2.0 * half_ang * float(i) / float(segs)
		var a1 := -half_ang + 2.0 * half_ang * float(i + 1) / float(segs)
		var am := (a0 + a1) * 0.5
		var seg_w := 2.0 * R * sin((a1 - a0) * 0.5) + 0.05
		var pc := c + Vector3(sin(am) * R, cy + cos(am) * R, 0.0)
		var xf := Transform3D(Basis(Vector3(0, 0, 1), -am), pc)
		RoadSignBuilder._box(kit["op"], xf, Vector3(seg_w, 0.35, L + 1.2), Color(0.84, 0.86, 0.88))
		for ez: float in [-1.0, 1.0]:
			var top_y := cy + cos(am) * R - wall_h
			if top_y > 0.05:
				_b(kit, "op", I, Vector3(pc.x, wall_h + top_y * 0.5, c.z + ez * (L * 0.5 - 0.1)), Vector3(seg_w, top_y, 0.2), WHITE)
	kit["op_n"] = true
	_sign(labels, "体育馆", c + Vector3(0.0, wall_h + 1.5, -L * 0.5 - 0.3), PI, 96, 0.028, Color(0.86, 0.16, 0.12))


static func _courts(kit: Dictionary, c: Vector3) -> void:
	var I := Transform3D.IDENTITY
	_b(kit, "op", I, c + Vector3(0.0, 0.06, 0.0), Vector3(84.0, 0.08, 72.0), Color(0.30, 0.48, 0.42))
	for ci in range(3):
		for cj in range(2):
			var cc := c + Vector3(-26.0 + float(ci) * 26.0, 0.0, -18.0 + float(cj) * 36.0)
			_b(kit, "op", I, cc + Vector3(0.0, 0.11, 0.0), Vector3(15.0, 0.04, 28.0), COURT)
			# lines: border, centre line, keys
			for lz: float in [-14.0, 0.0, 14.0]:
				_b(kit, "op", I, cc + Vector3(0.0, 0.14, lz), Vector3(15.0, 0.02, 0.08), LINE)
			for lx: float in [-7.5, 7.5]:
				_b(kit, "op", I, cc + Vector3(lx, 0.14, 0.0), Vector3(0.08, 0.02, 28.0), LINE)
			for kz: float in [-1.0, 1.0]:
				_b(kit, "op", I, cc + Vector3(0.0, 0.13, kz * 11.1), Vector3(4.9, 0.02, 5.8), COURT_IN)
				# hoop: pole, arm, backboard, rim
				_b(kit, "op", I, cc + Vector3(0.0, 1.6, kz * 14.9), Vector3(0.18, 3.2, 0.18), Color(0.22, 0.24, 0.27))
				_b(kit, "op", I, cc + Vector3(0.0, 3.05, kz * 14.3), Vector3(0.12, 0.12, 1.2), Color(0.22, 0.24, 0.27))
				_b(kit, "op", I, cc + Vector3(0.0, 3.4, kz * 13.7), Vector3(1.8, 1.05, 0.05), Color(0.97, 0.97, 0.97))
				_b(kit, "op", I, cc + Vector3(0.0, 3.05, kz * 13.4), Vector3(0.46, 0.03, 0.46), Color(0.92, 0.42, 0.12))
	# chain-link fence round the courts (posts + top rail)
	for s: float in [-1.0, 1.0]:
		_b(kit, "op", I, c + Vector3(s * 42.0, 1.8, 0.0), Vector3(0.08, 0.08, 72.0), FRAME)
		_b(kit, "op", I, c + Vector3(0.0, 1.8, s * 36.0), Vector3(84.0, 0.08, 0.08), FRAME)
	for k in range(15):
		for s2: float in [-1.0, 1.0]:
			_b(kit, "op", I, c + Vector3(-42.0 + float(k) * 6.0, 0.9, s2 * 36.0), Vector3(0.08, 1.8, 0.08), FRAME)


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
	# apron, track, infield
	_strip(kit, outline.call(ro), outline.call(ro + 2.5), 0.06, Color(0.58, 0.58, 0.56))
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
	var gx0 := c.x - ro - 3.0
	for row in range(8):
		var rx := gx0 - float(row) * 0.85
		var ry := 0.45 * float(row + 1)
		_b(kit, "op", I, Vector3(rx, ry * 0.5, c.z), Vector3(0.85, ry, 70.0), Color(0.70, 0.70, 0.68))
		_b(kit, "op", I, Vector3(rx + 0.1, ry + 0.22, c.z), Vector3(0.45, 0.42, 68.0), SEAT_A if row % 3 != 1 else SEAT_B)
	var back_x := gx0 - 8.0 * 0.85 - 0.3
	_b(kit, "op", I, Vector3(back_x, 3.2, c.z), Vector3(0.6, 6.4, 72.0), WHITE)
	for k4 in range(7):
		_b(kit, "op", I, Vector3(back_x, 5.0, c.z - 33.0 + float(k4) * 11.0), Vector3(0.6, 10.0, 0.6), WHITE)
	var roof_xf := Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(-8.0)), Vector3(gx0 - 2.0, 10.2, c.z))
	RoadSignBuilder._box(kit["op"], roof_xf, Vector3(12.0, 0.4, 74.0), Color(0.90, 0.92, 0.94))
	# floodlight masts
	for fx: float in [c.x - ro - 1.5, c.x + ro + 1.5]:
		for fz: float in [c.z - half_s - 20.0, c.z + half_s + 20.0]:
			_b(kit, "op", I, Vector3(fx, 11.0, fz), Vector3(0.5, 22.0, 0.5), Color(0.62, 0.64, 0.66))
			_b(kit, "em", I, Vector3(fx, 22.4, fz), Vector3(3.6, 1.4, 0.6), Color(1.0, 0.98, 0.92))
