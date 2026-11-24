class_name FreewayBuilder
extends RefCounted
# Freeways (I-5, I-90, SR-520, SR-99 / Aurora, ramps) from OSM with real deck heights (tools/extend_seattle_map.py):
# asphalt deck with lane lines, jersey barriers, and where it is up in the air: deck slab, piers with cap beams,
# steel trusses (Aurora Bridge, Ship Canal Bridge) or concrete pontoons (SR-520 floating bridge).
# Also the structure under ordinary street bridges (their deck height comes from Terrain's deck layer).
# Geometry is absolute (already on the ground): nodes are marked "on_terrain".

const LANE_W := 3.6
const BARRIER_H := 0.86
const SLAB := 1.5
const PIER_STEP := 32.0
const CONCRETE := Color(0.66, 0.65, 0.62)
const CONCRETE_DARK := Color(0.52, 0.51, 0.49)
const STEEL := Color(0.30, 0.40, 0.36) # Aurora Bridge green-grey


static func _build_road_grid(roads: Array) -> Dictionary:
	var grid := {}
	for r_raw in roads:
		var r: Dictionary = r_raw
		if bool(r.get("underground", false)) or int(r.get("layer", 0)) != 0:
			continue
		var rpts: Array = r.get("pts", [])
		if rpts.size() < 2:
			continue
		var rhw := clampf(float(r.get("width", 12.0)) * 0.5, 3.2, 14.0)
		for i in range(rpts.size() - 1):
			var a := Vector2(float(rpts[i][0]), float(rpts[i][1]))
			var b := Vector2(float(rpts[i + 1][0]), float(rpts[i + 1][1]))
			var mn := a.min(b) - Vector2.ONE * (rhw + 4.0)
			var mx := a.max(b) + Vector2.ONE * (rhw + 4.0)
			for gx in range(int(floor(mn.x / 30.0)), int(floor(mx.x / 30.0)) + 1):
				for gz in range(int(floor(mn.y / 30.0)), int(floor(mx.y / 30.0)) + 1):
					var k := Vector2i(gx, gz)
					if not grid.has(k):
						grid[k] = []
					(grid[k] as Array).append([a, b, rhw])
	return grid


static func _seg_dist_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _pier_collides(pos2: Vector2, road_grid: Dictionary, clear_idx: Dictionary, col_r: float) -> bool:
	if not clear_idx.is_empty():
		if TrackBuilder.track_clearance_dist(clear_idx, pos2) < col_r + 2.45:
			return true
	if not road_grid.is_empty():
		var k := Vector2i(int(floor(pos2.x / 30.0)), int(floor(pos2.y / 30.0)))
		var segs: Array = road_grid.get(k, [])
		for seg: Array in segs:
			var d := _seg_dist_2d(pos2, seg[0] as Vector2, seg[1] as Vector2)
			if d < float(seg[2]) + col_r + 0.55:
				return true
	return false


static func _resolve_pier_columns(p: Vector3, r: Vector3, hw: float, col_w: float, road_grid: Dictionary, clear_idx: Dictionary) -> Array[float]:
	var col_r := col_w * 0.5
	var defaults: Array[float] = []
	if hw < 8.5:
		defaults.append(0.0)
	else:
		defaults.append(-(hw - 2.6))
		defaults.append(hw - 2.6)
	if road_grid.is_empty() and clear_idx.is_empty():
		return defaults
	var all_clear := true
	for c: float in defaults:
		var cp := p + r * c
		if _pier_collides(Vector2(cp.x, cp.z), road_grid, clear_idx, col_r):
			all_clear = false
			break
	if all_clear:
		return defaults
	# Default column sits on a street carriageway or tramway -> upgrade to a real Portal Straddle Bent (门式桥墩)
	# with columns placed cleanly on the sidewalks outside the roadway/tracks!
	var left_c := NAN
	var right_c := NAN
	var step := 1.4
	var max_reach := hw + 15.5
	var off := maxf(hw - 1.2, 4.0)
	while off <= max_reach:
		if is_nan(left_c):
			var lp := p - r * off
			if not _pier_collides(Vector2(lp.x, lp.z), road_grid, clear_idx, col_r):
				left_c = -off
		if is_nan(right_c):
			var rp := p + r * off
			if not _pier_collides(Vector2(rp.x, rp.z), road_grid, clear_idx, col_r):
				right_c = off
		if not is_nan(left_c) and not is_nan(right_c):
			break
		off += step
	if not is_nan(left_c) and not is_nan(right_c) and (right_c - left_c) <= 34.0:
		return [left_c, right_c]
	# Fallback: Cantilever Inverted-L pier on one clear sidewalk if close enough to the deck edge
	if not is_nan(left_c) and absf(left_c) <= hw + 4.8:
		return [left_c]
	if not is_nan(right_c) and absf(right_c) <= hw + 4.8:
		return [right_c]
	# Inside a wide multi-way intersection where no sidewalk pier fits -> omit pier (long box-girder span!)
	return []


static func build(parent: Node3D, freeways: Array, road_mat: Material, roads: Array = [], clear_idx: Dictionary = {}) -> void:
	if freeways.is_empty():
		return
	var road_grid := _build_road_grid(roads)
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var conc := SurfaceTool.new()
	conc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_steel := false
	for f: Dictionary in freeways:
		var raw: Array = f.get("pts", [])
		if raw.size() < 2:
			continue
		var pts: Array[Vector3] = []
		for p in raw:
			pts.append(Vector3(float(p[0]), float(p[2]), float(p[1])))
		var hw := float(f.get("w", 12.0)) * 0.5
		var lanes := int(f.get("lanes", 2))
		var structure := str(f.get("structure", ""))
		var n := pts.size()
		# per-vertex right vectors (mitred joints) and distance along
		var rights: Array[Vector3] = []
		var cum: Array[float] = [0.0]
		for i in range(n):
			var d_prev := (pts[i] - pts[maxi(i - 1, 0)])
			var d_next := (pts[mini(i + 1, n - 1)] - pts[i])
			var dd := Vector3(d_prev.x + d_next.x, 0.0, d_prev.z + d_next.z)
			if dd.length_squared() < 1e-6:
				dd = Vector3(1, 0, 0)
			dd = dd.normalized()
			rights.append(Vector3(-dd.z, 0.0, dd.x))
			if i > 0:
				cum.append(cum[i - 1] + Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
		for i in range(n - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var ra := rights[i] * hw
			var rb := rights[i + 1] * hw
			# deck surface
			_quad_uv(deck, a - ra, a + ra, b + rb, b - rb, Vector2(0.0, cum[i]), Vector2(hw * 2.0, cum[i + 1]))
			# barriers along both edges (taper smoothly to 0 right at ground merge aprons so ramps blend flush into asphalt!)
			var bh_a := BARRIER_H * clampf((_clear(a) - 0.12) / 0.55, 0.0, 1.0)
			var bh_b := BARRIER_H * clampf((_clear(b) - 0.12) / 0.55, 0.0, 1.0)
			for side: float in [-1.0, 1.0]:
				var ea := a + rights[i] * (hw * side)
				var eb := b + rights[i + 1] * (hw * side)
				var ia := a + rights[i] * ((hw - 0.42) * side)
				var ib := b + rights[i + 1] * ((hw - 0.42) * side)
				var ta := a + rights[i] * ((hw - 0.16) * side)
				var tb := b + rights[i + 1] * ((hw - 0.16) * side)
				var up_a := Vector3(0.0, bh_a, 0.0)
				var up_b := Vector3(0.0, bh_b, 0.0)
				if bh_a > 0.02 or bh_b > 0.02:
					_quad_c(conc, ia, ib, tb + up_b, ta + up_a, CONCRETE)
					_quad_c(conc, ta + up_a, tb + up_b, eb + up_b, ea + up_a, CONCRETE.lightened(0.06))
				var low_a := _clear(a) > 2.2
				var low_b := _clear(b) > 2.2
				var drop_a := Vector3(0.0, -SLAB if low_a else -minf(maxf(_clear(a), 0.05), SLAB), 0.0)
				var drop_b := Vector3(0.0, -SLAB if low_b else -minf(maxf(_clear(b), 0.05), SLAB), 0.0)
				_quad_c(conc, ea + up_a, eb + up_b, eb + drop_b, ea + drop_a, CONCRETE_DARK)
			# lane lines: solid edges, dashed dividers (3 m dash every 12 m)
			var mid_u := (cum[i] + cum[i + 1]) * 0.5
			for k in range(lanes + 1):
				var off := -hw + 1.2 + float(k) * LANE_W
				if off > hw - 0.5:
					break
				var solid := k == 0 or k == lanes
				if not solid and fmod(mid_u, 12.0) > 3.0:
					continue
				var la := a + rights[i] * off + Vector3(0.0, 0.03, 0.0)
				var lb := b + rights[i + 1] * off + Vector3(0.0, 0.03, 0.0)
				var w2 := 0.08 if not solid else 0.10
				_quad_c(lines, la - rights[i] * w2, la + rights[i] * w2, lb + rights[i + 1] * w2, lb - rights[i + 1] * w2, Color.WHITE if k > 0 else Color(0.95, 0.80, 0.2))
			# elevated deck: slab underside (only where genuinely elevated above ground!)
			if _clear(a) > 2.2 and _clear(b) > 2.2:
				var sa := Vector3(0.0, -SLAB, 0.0)
				_quad_c(conc, b - rb + sa, b + rb + sa, a + ra + sa, a - ra + sa, CONCRETE_DARK.darkened(0.15))
		# piers / trusses / pontoons along the piece
		var next_pier := fmod(PIER_STEP - fmod(cum[0], PIER_STEP), PIER_STEP)
		var s := next_pier
		while s < cum[n - 1]:
			var k2 := 0
			while k2 < n - 2 and cum[k2 + 1] < s:
				k2 += 1
			var t := (s - cum[k2]) / maxf(cum[k2 + 1] - cum[k2], 0.01)
			var p := pts[k2].lerp(pts[k2 + 1], t)
			var r := rights[k2].lerp(rights[k2 + 1], t).normalized()
			var clr := _clear(p)
			if structure == "floating":
				var wl := Terrain.surface(p.x, p.z)
				_box(conc, p + Vector3(0.0, -(p.y - wl) * 0.5 - 0.6, 0.0), r, Vector3(hw * 2.0 + 6.0, maxf(0.8, p.y - wl + 1.2), PIER_STEP * 0.96), CONCRETE_DARK)
			elif clr > 3.2:
				var g := Terrain.ground(p.x, p.z) - 0.5
				var top := p.y - SLAB
				var col_w := 1.6 if clr < 30.0 else 3.2
				var cols := _resolve_pier_columns(p, r, hw, col_w, road_grid, clear_idx)
				if not cols.is_empty():
					var beam_lo := -(hw - 0.5)
					var beam_hi := (hw - 0.5)
					for c: float in cols:
						var cp := p + r * c
						_box(conc, Vector3(cp.x, (g + top) * 0.5, cp.z), r, Vector3(col_w, top - g, col_w), CONCRETE)
						beam_lo = minf(beam_lo, c - col_w * 0.55)
						beam_hi = maxf(beam_hi, c + col_w * 0.55)
					var beam_mid := (beam_lo + beam_hi) * 0.5
					var beam_w := maxf(hw * 2.0 - 1.0, beam_hi - beam_lo)
					var bp := p + r * beam_mid
					_box(conc, Vector3(bp.x, top - 0.65, bp.z), r, Vector3(beam_w, 1.3, 2.0), CONCRETE.darkened(0.05))
			s += PIER_STEP
		if structure == "truss":
			any_steel = true
			_truss(steel, pts, rights, cum, hw)
	_emit(parent, "FreewayDecks", deck, road_mat, true)
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.roughness = 0.8
	_emit(parent, "FreewayLines", lines, lm, false)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.88
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_emit(parent, "FreewayConcrete", conc, cm, true)
	if any_steel:
		var sm := StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		sm.metallic = 0.5
		sm.roughness = 0.5
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_emit(parent, "FreewaySteel", steel, sm, true)


# Steel trusses under both deck edges: top chord under the deck, bottom chord deeper towards mid span
static func _truss(st: SurfaceTool, pts: Array[Vector3], rights: Array[Vector3], cum: Array[float], hw: float) -> void:
	var n := pts.size()
	for side: float in [-1.0, 1.0]:
		for i in range(n - 1):
			var a := pts[i] + rights[i] * ((hw - 0.6) * side) + Vector3(0.0, -SLAB, 0.0)
			var b := pts[i + 1] + rights[i + 1] * ((hw - 0.6) * side) + Vector3(0.0, -SLAB, 0.0)
			var da := clampf(_clear(pts[i]) * 0.16, 3.0, 9.0)
			var db := clampf(_clear(pts[i + 1]) * 0.16, 3.0, 9.0)
			var a2 := a - Vector3(0.0, da, 0.0)
			var b2 := b - Vector3(0.0, db, 0.0)
			_beam(st, a, b, 0.5)
			_beam(st, a2, b2, 0.6)
			_beam(st, a, a2, 0.35)
			_beam(st, a, b2, 0.3) # diagonal
		# lateral bracing between the two trusses
	for i in range(0, n, 2):
		var l := pts[i] + rights[i] * -(hw - 0.6) + Vector3(0.0, -SLAB - 0.4, 0.0)
		var r := pts[i] + rights[i] * (hw - 0.6) + Vector3(0.0, -SLAB - 0.4, 0.0)
		_beam(st, l, r, 0.25)


static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, th: float) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.05:
		return
	var fwd := d / L
	var side := fwd.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = Vector3.RIGHT
	side = side.normalized() * (th * 0.5)
	var upv := side.cross(fwd).normalized() * (th * 0.5)
	var corners: Array[Vector3] = [side + upv, -side + upv, -side - upv, side - upv]
	for k in range(4):
		var c0: Vector3 = corners[k]
		var c1: Vector3 = corners[(k + 1) % 4]
		_quad_c(st, a + c0, a + c1, b + c1, b + c0, STEEL)


# Street bridges (OSM bridge=yes streets, deck height from Terrain's deck layer): slab, railings, piers
static func build_street_bridges(parent: Node3D, roads: Array) -> void:
	if not Terrain.active:
		return
	var conc := SurfaceTool.new()
	conc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for r: Dictionary in roads:
		if not bool(r.get("bridge", false)):
			continue
		var raw := Terrain.densify(r.get("pts", []), 6.0)
		if raw.size() < 2:
			continue
		var hw := clampf(float(r.get("width", 10.0)) * 0.5, 3.2, 13.5) + 2.5 # carriageway + sidewalks
		var pts: Array[Vector3] = []
		for p in raw:
			var x := float(p[0])
			var z := float(p[1])
			pts.append(Vector3(x, Terrain.surface(x, z), z))
		var acc := 0.0
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
			if d.length_squared() < 0.01:
				continue
			var rv := Vector3(-d.z, 0.0, d.x).normalized()
			var ca := a.y - Terrain.ground(a.x, a.z)
			var cb := b.y - Terrain.ground(b.x, b.z)
			if ca < 1.5 and cb < 1.5:
				acc += d.length()
				continue
			any = true
			var sl := Vector3(0.0, -1.1, 0.0)
			for side: float in [-1.0, 1.0]:
				var ea := a + rv * (hw * side)
				var eb := b + rv * (hw * side)
				_quad_c(conc, ea + Vector3(0.0, 1.05, 0.0), eb + Vector3(0.0, 1.05, 0.0), eb + sl, ea + sl, CONCRETE_DARK) # railing + fascia
			_quad_c(conc, b - rv * hw + sl, b + rv * hw + sl, a + rv * hw + sl, a - rv * hw + sl, CONCRETE_DARK.darkened(0.15))
			acc += d.length()
			if fmod(acc, 24.0) < d.length() and minf(ca, cb) > 3.0:
				var g := Terrain.ground(a.x, a.z) - 0.4
				var top := a.y - 1.1
				_box(conc, Vector3(a.x, (g + top) * 0.5, a.z), rv, Vector3(hw * 1.4, top - g, 1.2), CONCRETE)
	if any:
		var cm := StandardMaterial3D.new()
		cm.vertex_color_use_as_albedo = true
		cm.roughness = 0.88
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_emit(parent, "StreetBridgeStructure", conc, cm, true)


static func _clear(p: Vector3) -> float:
	return p.y - Terrain.surface(p.x, p.z) if Terrain.active else p.y


static func _emit(parent: Node3D, nm: String, st: SurfaceTool, mat: Material, shadows: bool) -> void:
	var arr := st.commit_to_arrays()
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null or (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = nm
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("on_terrain", true)
	parent.add_child(mi)


static func _quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv0: Vector2, uv1: Vector2) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var uvs: Array[Vector2] = [Vector2(uv0.x, uv0.y), Vector2(uv1.x, uv0.y), Vector2(uv1.x, uv1.y), Vector2(uv0.x, uv1.y)]
	var vs: Array[Vector3] = [a, b, c, d]
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_uv(uvs[k])
		st.add_vertex(vs[k])


static func _quad_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(d - a)
	nrm = nrm.normalized() if nrm.length_squared() > 1e-8 else Vector3.UP
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(nrm)
		st.add_vertex(v)


static func _box(st: SurfaceTool, c: Vector3, right: Vector3, size: Vector3, col: Color) -> void:
	var r := right.normalized() * (size.x * 0.5)
	var f := Vector3(-right.z, 0.0, right.x).normalized() * (size.z * 0.5)
	var u := Vector3(0.0, size.y * 0.5, 0.0)
	var p: Array[Vector3] = [c - r - f - u, c + r - f - u, c + r + f - u, c - r + f - u, c - r - f + u, c + r - f + u, c + r + f + u, c - r + f + u]
	_quad_c(st, p[4], p[5], p[6], p[7], col.lightened(0.05))
	_quad_c(st, p[0], p[1], p[5], p[4], col)
	_quad_c(st, p[1], p[2], p[6], p[5], col.darkened(0.06))
	_quad_c(st, p[2], p[3], p[7], p[6], col)
	_quad_c(st, p[3], p[0], p[4], p[7], col.darkened(0.06))
