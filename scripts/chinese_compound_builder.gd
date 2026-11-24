class_name ChineseCompoundBuilder
extends RefCounted

# Authentic Chinese Gated Residential Compounds (封闭式小区):
#   - Perimeter masonry plinth + capped pilasters + dark wrought-iron fence railings + inner hedge strip
#   - Monumental street-facing 小区大门牌楼 (gatehouse canopy), 保安室 (guardhouse),
#     升降道闸 (red-and-white striped vehicle boom barriers), and crisp compound name signage!
# All wall & gate geometry is batched into one vertex-colored ArrayMesh for zero draw-call overhead.

const PALETTES := [
	# 0: Modern Neo-Chinese (新中式: 暖米石材 + 深古铜栏杆 + 香槟金门头)
	{
		"plinth": Color(0.78, 0.74, 0.66),
		"cap": Color(0.60, 0.56, 0.50),
		"iron": Color(0.18, 0.16, 0.14),
		"canopy": Color(0.24, 0.21, 0.19),
		"trim": Color(0.78, 0.66, 0.42),
		"text": Color(0.98, 0.90, 0.62),
	},
	# 1: Classic Jiangnan Garden Compound (经典花园小区: 砖红墙柱 + 黛瓦坡檐 + 深铁艺)
	{
		"plinth": Color(0.68, 0.46, 0.36),
		"cap": Color(0.84, 0.80, 0.72),
		"iron": Color(0.16, 0.18, 0.20),
		"canopy": Color(0.24, 0.26, 0.30),
		"trim": Color(0.86, 0.82, 0.74),
		"text": Color(1.0, 0.95, 0.76),
	},
	# 2: Contemporary High-Rise Residence (现代精装小区: 浅灰花岗岩 + 炭灰门楼 + 亮白门牌)
	{
		"plinth": Color(0.72, 0.74, 0.76),
		"cap": Color(0.52, 0.55, 0.58),
		"iron": Color(0.18, 0.20, 0.23),
		"canopy": Color(0.22, 0.25, 0.29),
		"trim": Color(0.82, 0.84, 0.86),
		"text": Color(0.98, 0.98, 0.96),
	},
]


const CELL := 320.0
const BASE_RANGE := 1900.0
const DETAIL_RANGE := 520.0


static func build(parent: Node3D, compounds: Array, _lights: Array) -> void:
	if compounds.is_empty():
		return
	var grp := Node3D.new()
	grp.name = "ChineseGatedCompounds"
	parent.add_child(grp)

	# Batched per 320 m cell, split into a plinth/coping layer that reads from afar and a fine layer (railings,
	# pickets, pilasters, hedges, gatehouses) that only draws near the camera: one map-wide mesh of several
	# million triangles used to be drawn (and frustum-tested) as a whole every frame
	var cells := {} # Vector2i -> [SurfaceTool base, SurfaceTool detail]
	var cell_of := func(p: Vector3) -> Array:
		var ck := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not cells.has(ck):
			var sb := SurfaceTool.new()
			sb.begin(Mesh.PRIMITIVE_TRIANGLES)
			var sd := SurfaceTool.new()
			sd.begin(Mesh.PRIMITIVE_TRIANGLES)
			cells[ck] = [sb, sd]
		return cells[ck]

	var signs := Node3D.new()
	signs.name = "CompoundGateSigns"
	grp.add_child(signs)

	var hedge_c := Color(0.20, 0.38, 0.18)
	var gate_count := 0
	for comp_v in compounds:
		if not (comp_v is Dictionary):
			continue
		var comp: Dictionary = comp_v
		var style_i := clampi(int(comp.get("style", 0)), 0, PALETTES.size() - 1)
		var pal: Dictionary = PALETTES[style_i]
		var plinth_c: Color = pal["plinth"]
		var cap_c: Color = pal["cap"]
		var iron_c: Color = pal["iron"]

		# 1) Perimeter enclosure walls (plinth + pilasters + wrought-iron railing + inner hedge)
		var segs: Array = comp.get("segs", [])
		for seg_v in segs:
			if not (seg_v is Array) or (seg_v as Array).size() < 2:
				continue
			var pa: Array = seg_v[0]
			var pb: Array = seg_v[1]
			var o := Vector3(float(pa[0]), 0.0, float(pa[1]))
			var d := Vector3(float(pb[0]), 0.0, float(pb[1])) - o
			var L := d.length()
			if L < 2.2:
				continue
			var U := d / L
			var N := Vector3(-U.z, 0.0, U.x)
			var cell: Array = cell_of.call(o + d * 0.5)
			var st: SurfaceTool = cell[0]

			# Continuous stone plinth & coping cap
			_lbox(st, o, U, N, 0.0, L, 0.0, 0.88, -0.17, 0.17, plinth_c)
			_lbox(st, o, U, N, 0.0, L, 0.88, 0.98, -0.21, 0.21, cap_c)
			st = cell[1]
			# Upper & lower horizontal wrought-iron fence rails
			_lbox(st, o, U, N, 0.0, L, 1.08, 1.15, -0.05, 0.05, iron_c)
			_lbox(st, o, U, N, 0.0, L, 2.08, 2.16, -0.05, 0.05, iron_c)

			# Brick/stone pilasters every ~10m + vertical iron pickets between pilasters
			var n_bays := maxi(1, int(round(L / 10.0)))
			for bi in range(n_bays + 1):
				var pu := L * float(bi) / float(n_bays)
				_lbox(st, o, U, N, pu - 0.25, pu + 0.25, 0.0, 2.34, -0.25, 0.25, plinth_c.darkened(0.04))
				_lbox(st, o, U, N, pu - 0.30, pu + 0.30, 2.34, 2.46, -0.30, 0.30, cap_c)
			# Pickets spaced ~1.6m for crisp silhouette with lean vertex count
			var s_p := 1.4
			while s_p < L - 0.8:
				_lbox(st, o, U, N, s_p - 0.035, s_p + 0.035, 1.00, 2.20, -0.035, 0.035, iron_c)
				s_p += 1.65

			# Subtle landscaped hedge strip tucked inside the perimeter wall
			if L >= 10.0:
				_lbox(st, o, U, N, 0.6, L - 0.6, 0.0, 0.72, -0.68, -0.22, hedge_c)

		# 2) Street-facing Compound Main Entrance Gatehouse (小区大门牌楼 + 保安亭 + 升降道闸)
		var gpos_a: Array = comp.get("gate_pos", [])
		if gpos_a.size() < 2:
			continue
		var go := Vector3(float(gpos_a[0]), 0.0, float(gpos_a[1]))
		var ang := float(comp.get("gate_angle", 0.0))
		# Local frame matching gate_angle: +N faces outward toward street, +U spans along the gate width
		var gN := Vector3(sin(ang), 0.0, cos(ang)).normalized()
		var gU := Vector3(gN.z, 0.0, -gN.x).normalized()
		_build_gatehouse((cell_of.call(go) as Array)[1], signs, go, gU, gN, str(comp.get("name", "嘉兴花园")), pal, style_i)
		gate_count += 1

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.72
	mat.metallic = 0.08
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for ck: Vector2i in cells.keys():
		for li in range(2):
			var mi := MeshInstance3D.new()
			mi.name = "CompoundWallsAndGates" if li == 0 else "CompoundWallDetail"
			mi.mesh = Terrain.commit_draped(cells[ck][li], mi)
			if mi.mesh == null or mi.mesh.get_surface_count() == 0:
				mi.free()
				continue
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = BASE_RANGE if li == 0 else DETAIL_RANGE
			mi.visibility_range_end_margin = 40.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			grp.add_child(mi)


static func _build_gatehouse(
	st: SurfaceTool, signs: Node3D,
	o: Vector3, U: Vector3, N: Vector3,
	nm: String, pal: Dictionary, style_i: int
) -> void:
	var plinth_c: Color = pal["plinth"]
	var cap_c: Color = pal["cap"]
	var canopy_c: Color = pal["canopy"]
	var trim_c: Color = pal["trim"]
	var iron_c: Color = pal["iron"]

	# Paved entry driveway apron under the gatehouse
	_lbox(st, o, U, N, -5.6, 5.6, 0.0, 0.06, -3.2, 2.6, Color(0.46, 0.45, 0.43))

	# Twin monumental gate pillars (left & right of the 11m opening)
	for sx: float in [-5.35, 5.35]:
		_lbox(st, o, U, N, sx - 0.72, sx + 0.72, 0.0, 0.55, -0.78, 0.78, cap_c)
		_lbox(st, o, U, N, sx - 0.62, sx + 0.62, 0.55, 4.45, -0.68, 0.68, plinth_c)
		_lbox(st, o, U, N, sx - 0.72, sx + 0.72, 4.30, 4.55, -0.76, 0.76, trim_c)
		# Lantern finial box on top of outer corner
		_lbox(st, o, U, N, sx - 0.22, sx + 0.22, 5.55, 6.05, 0.62, 1.06, Color(0.96, 0.86, 0.56))

	# Overhead grand entrance canopy / fascia lintel (小区门楼雨棚)
	_lbox(st, o, U, N, -6.35, 6.35, 4.42, 5.42, -1.25, 1.35, canopy_c)
	_lbox(st, o, U, N, -6.55, 6.55, 5.42, 5.68, -1.45, 1.55, trim_c)
	_lbox(st, o, U, N, -6.20, 6.20, 4.35, 4.44, -1.18, 1.28, trim_c)
	if style_i == 1:
		# Classic pitched Jiangnan tiled eave crown above the lintel
		_lbox(st, o, U, N, -6.10, 6.10, 5.68, 6.15, -1.05, 1.05, Color(0.20, 0.22, 0.26))
		_lbox(st, o, U, N, -5.60, 5.60, 6.15, 6.42, -0.45, 0.45, Color(0.24, 0.26, 0.30))

	# Security Guardhouse Booth (保安亭 / 门卫室) on the right side
	_lbox(st, o, U, N, 2.75, 4.75, 0.06, 1.08, -1.45, 0.65, plinth_c.darkened(0.08))
	_lbox(st, o, U, N, 2.82, 4.68, 1.08, 2.38, -1.38, 0.58, Color(0.18, 0.34, 0.48))  # Tinted security windows
	_lbox(st, o, U, N, 2.60, 4.90, 2.38, 2.72, -1.60, 0.82, canopy_c)
	_lbox(st, o, U, N, 2.66, 4.84, 2.72, 2.84, -1.52, 0.74, trim_c)

	# Pedestrian side-gate turnstile frame on the left
	_lbox(st, o, U, N, -4.65, -2.95, 0.06, 1.22, -0.10, 0.10, iron_c)
	_lbox(st, o, U, N, -3.02, -2.78, 0.06, 2.55, -0.22, 0.22, plinth_c)

	# Vehicle Entry/Exit Boom Barriers (升降道闸 — bright yellow pedestals + red/white striped arms!)
	var ped_c := Color(0.92, 0.68, 0.08)
	var red_c := Color(0.86, 0.12, 0.12)
	var wht_c := Color(0.96, 0.96, 0.96)
	# Entry pedestal (left of center driveway) + Exit pedestal (near guardhouse)
	_lbox(st, o, U, N, -2.65, -2.25, 0.06, 1.18, 0.30, 0.66, ped_c)
	_lbox(st, o, U, N, 2.15, 2.55, 0.06, 1.18, -0.55, -0.19, ped_c)
	# Striped horizontal boom arm (entry, closed/horizontal across incoming lane)
	for bi in range(6):
		var u0 := -2.25 + float(bi) * 0.42
		var u1 := u0 + 0.42
		_lbox(st, o, U, N, u0, u1, 0.92, 1.04, 0.42, 0.52, red_c if bi % 2 == 0 else wht_c)
	# Striped exit boom arm (raised at slight angle / shorter)
	for bi in range(5):
		var u0 := 2.15 - float(bi + 1) * 0.40
		var u1 := u0 + 0.40
		_lbox(st, o, U, N, u0, u1, 0.92, 1.04, -0.42, -0.32, red_c if bi % 2 == 0 else wht_c)

	# Crisp Compound Name Signboard (小区大门铭牌) on front of canopy
	var lp := o + N * 1.40 + Vector3.UP * 4.92
	if Terrain.active:
		lp.y += Terrain.surface(lp.x, lp.z)
	var lbl := Label3D.new()
	lbl.text = nm
	lbl.font_size = 72
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.06, 0.06, 0.08, 0.92)
	lbl.modulate = pal["text"]
	lbl.double_sided = false
	lbl.shaded = false
	lbl.visibility_range_end = 230.0
	lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lbl.render_priority = 1
	var right := (-N).cross(Vector3.UP).normalized()
	lbl.transform = Transform3D(Basis(right, Vector3.UP, N), lp)
	var eff := maxf(3.0, float(nm.length()) * 1.08)
	lbl.pixel_size = minf(9.2 / (eff * 72.0), 0.68 / 75.0)
	signs.add_child(lbl)


static func _lbox(
	st: SurfaceTool, o: Vector3, U: Vector3, N: Vector3,
	u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, col: Color
) -> void:
	if u1 - u0 < 0.005 or y1 - y0 < 0.005 or d1 - d0 < 0.005:
		return
	var p000 := o + U * u0 + N * d0 + Vector3.UP * y0
	var p100 := o + U * u1 + N * d0 + Vector3.UP * y0
	var p110 := o + U * u1 + N * d0 + Vector3.UP * y1
	var p010 := o + U * u0 + N * d0 + Vector3.UP * y1
	var p001 := o + U * u0 + N * d1 + Vector3.UP * y0
	var p101 := o + U * u1 + N * d1 + Vector3.UP * y0
	var p111 := o + U * u1 + N * d1 + Vector3.UP * y1
	var p011 := o + U * u0 + N * d1 + Vector3.UP * y1
	# Front (+N), Back (-N), Top (+Y), Left (-U), Right (+U)
	_quad(st, p001, p101, p111, p011, col)
	_quad(st, p100, p000, p010, p110, col.darkened(0.06))
	_quad(st, p011, p111, p110, p010, col.lightened(0.07))
	_quad(st, p000, p001, p011, p010, col.darkened(0.10))
	_quad(st, p101, p100, p110, p111, col.darkened(0.10))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(nrm)
		st.add_vertex(v)
