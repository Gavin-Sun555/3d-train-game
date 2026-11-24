class_name ParkLandscapeBuilder
extends RefCounted

# High-detail Seattle park landscaping, multi-species sculpted 3D trees, park greenways,
# benches, picnic tables, flowerbeds, pavilions, and the Lake Union waterfront park masterpiece.

const TREE_CHUNK := 360.0
const PROP_CHUNK := 380.0

static var _species_cache: Dictionary = {}
static var _prop_cache: Dictionary = {}


static func build_all_parks_and_trees(
	parent: Node3D,
	map_data: Dictionary,
	lights: Array,
	globe_mat: StandardMaterial3D
) -> void:
	var areas: Array = map_data.get("areas", [])
	var roads: Array = map_data.get("roads", [])
	var buildings: Array = map_data.get("buildings", [])
	var raw_trees: Array = map_data.get("trees", [])
	var map_key := str(map_data.get("key", ""))

	var root := Node3D.new()
	root.name = "ParksAndLandscape"
	parent.add_child(root)

	# Build fast spatial clearance grids so park props & trees NEVER land on roads, tracks, buildings, or water
	var clear := _build_clearance_data(roads, buildings, areas)

	# Collect park prop transforms & path-exclusion segments across all parks + Lake Union
	var prop_lists := {
		"bench": [] as Array[Transform3D],
		"picnic": [] as Array[Transform3D],
		"shrub": [] as Array[Transform3D],
		"flower_pink": [] as Array[Transform3D],
		"flower_blue": [] as Array[Transform3D],
		"flower_gold": [] as Array[Transform3D],
		"park_lamp": [] as Array[Transform3D],
		"bollard_light": [] as Array[Transform3D],
		"park_bin": [] as Array[Transform3D],
	}
	var path_segs: Array = [] # [[Vector2, Vector2, half_width]] so park trees don't grow inside walkways
	var plaza_circles: Array = [] # [[Vector2, radius]]
	var extra_park_trees: Array = [] # [{pos: Vector2, species: int, scale: float, is_park: true}]

	# 1. Lake Union & Lake Union Park Waterfront Masterpiece (Seattle map)
	if map_key == "seattle" or map_data.get("landmarks", {}).has("space_needle"):
		_build_lake_union_waterfront(
			root, areas, clear, prop_lists, path_segs, plaza_circles, extra_park_trees, lights, globe_mat
		)

	# 2. All City Parks & Green Spaces: granite curbs, winding greenways, focal plazas, pavilions, furniture & tree groves
	_build_parks_detail(
		root, areas, clear, prop_lists, path_segs, plaza_circles, extra_park_trees, lights
	)

	# 3. Instanced Park Furniture (Chunked MultiMeshes for smooth 50+ FPS)
	_emit_park_props(root, prop_lists, globe_mat)

	# 4. Multi-Species High-Detail Sculpted 3D Trees (Street Trees + Lush Multi-Species Park Groves!)
	_build_multi_species_trees(root, raw_trees, extra_park_trees, clear, path_segs, plaza_circles)


# ---------------------------------------------------------------------------------------------
# Spatial Clearance Helpers (O(1) Grid Lookup against Roads, Buildings & Water)
# ---------------------------------------------------------------------------------------------
static func _build_clearance_data(roads: Array, buildings: Array, areas: Array) -> Dictionary:
	var road_grid := {}
	for r in roads:
		var pts: Array = r.get("pts", [])
		var hw := clampf(float(r.get("width", 12.0)) * 0.5, 3.2, 13.5)
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var minx := int(floor((minf(a.x, b.x) - hw - 6.0) / 40.0))
			var maxx := int(floor((maxf(a.x, b.x) + hw + 6.0) / 40.0))
			var minz := int(floor((minf(a.y, b.y) - hw - 6.0) / 40.0))
			var maxz := int(floor((maxf(a.y, b.y) + hw + 6.0) / 40.0))
			var seg := [a, b, hw]
			for gx in range(minx, maxx + 1):
				for gz in range(minz, maxz + 1):
					var ck := Vector2i(gx, gz)
					if not road_grid.has(ck):
						road_grid[ck] = []
					(road_grid[ck] as Array).append(seg)

	var bldg_grid := {}
	for b in buildings:
		var raw: Array = b.get("pts", [])
		if raw.size() < 3:
			continue
		var poly := PackedVector2Array()
		var bmin := Vector2(1e9, 1e9)
		var bmax := Vector2(-1e9, -1e9)
		for p in raw:
			var v := Vector2(float(p[0]), float(p[1]))
			poly.append(v)
			bmin = Vector2(minf(bmin.x, v.x), minf(bmin.y, v.y))
			bmax = Vector2(maxf(bmax.x, v.x), maxf(bmax.y, v.y))
		var rec := [bmin, bmax, poly]
		var minx := int(floor((bmin.x - 4.0) / 40.0))
		var maxx := int(floor((bmax.x + 4.0) / 40.0))
		var minz := int(floor((bmin.y - 4.0) / 40.0))
		var maxz := int(floor((bmax.y + 4.0) / 40.0))
		for gx in range(minx, maxx + 1):
			for gz in range(minz, maxz + 1):
				var ck := Vector2i(gx, gz)
				if not bldg_grid.has(ck):
					bldg_grid[ck] = []
				(bldg_grid[ck] as Array).append(rec)

	var water_polys: Array = []
	var island_polys: Array = []
	var park_polys: Array = []
	for a in areas:
		var kind := str(a.get("kind", ""))
		var poly := _clean_poly(a.get("pts", []))
		if poly.size() < 3:
			continue
		var amin := Vector2(1e9, 1e9)
		var amax := Vector2(-1e9, -1e9)
		for v in poly:
			amin = Vector2(minf(amin.x, v.x), minf(amin.y, v.y))
			amax = Vector2(maxf(amax.x, v.x), maxf(amax.y, v.y))
		if kind == "water":
			var w_parts: Array[PackedVector2Array] = [poly]
			if Geometry2D.triangulate_polygon(poly).is_empty():
				w_parts = []
				for sub: PackedVector2Array in Geometry2D.merge_polygons(poly, PackedVector2Array()):
					if sub.size() >= 3 and not Geometry2D.is_polygon_clockwise(sub):
						w_parts.append(sub)
			for wp: PackedVector2Array in w_parts:
				var wmin := Vector2(1e9, 1e9)
				var wmax := Vector2(-1e9, -1e9)
				for v in wp:
					wmin = Vector2(minf(wmin.x, v.x), minf(wmin.y, v.y))
					wmax = Vector2(maxf(wmax.x, v.x), maxf(wmax.y, v.y))
				water_polys.append([wmin, wmax, wp])
		elif kind == "island":
			island_polys.append([amin, amax, poly])
			# Lake islands (except Yanyu Tower Lake Heart Island which has bespoke landmarks) also grow lush island groves!
			var ic := (amin + amax) * 0.5
			if ic.distance_to(Vector2(368.0, -276.0)) > 90.0:
				park_polys.append([amin, amax, poly, "park"])
		elif kind in ["park", "grass", "wood", "meadow", "garden"]:
			park_polys.append([amin, amax, poly, kind])

	return {
		"road_grid": road_grid,
		"bldg_grid": bldg_grid,
		"water_polys": water_polys,
		"island_polys": island_polys,
		"park_polys": park_polys,
	}


static func _road_clearance(clear: Dictionary, p: Vector2) -> float:
	var ck := Vector2i(int(floor(p.x / 40.0)), int(floor(p.y / 40.0)))
	var segs: Array = (clear["road_grid"] as Dictionary).get(ck, [])
	var best := 999.0
	for s in segs:
		var q := Geometry2D.get_closest_point_to_segment(p, s[0] as Vector2, s[1] as Vector2)
		best = minf(best, p.distance_to(q) - float(s[2]))
	return best


static func _inside_any_building(clear: Dictionary, p: Vector2, pad: float = 2.0) -> bool:
	var ck := Vector2i(int(floor(p.x / 40.0)), int(floor(p.y / 40.0)))
	var bldgs: Array = (clear["bldg_grid"] as Dictionary).get(ck, [])
	for rec in bldgs:
		var bmin: Vector2 = rec[0]
		var bmax: Vector2 = rec[1]
		if p.x < bmin.x - pad or p.x > bmax.x + pad or p.y < bmin.y - pad or p.y > bmax.y + pad:
			continue
		var poly: PackedVector2Array = rec[2]
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		if pad > 0.1:
			for i in range(poly.size()):
				var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
				if p.distance_squared_to(q) < pad * pad:
					return true
	return false


static func _inside_any_water(clear: Dictionary, p: Vector2, pad: float = 0.0) -> bool:
	# Lake islands are dry land strictly inside water polygons — check islands first (inset by pad from shoreline)!
	for irec in clear.get("island_polys", []):
		var imin: Vector2 = irec[0]
		var imax: Vector2 = irec[1]
		if p.x < imin.x or p.x > imax.x or p.y < imin.y or p.y > imax.y:
			continue
		var ipoly: PackedVector2Array = irec[2]
		if Geometry2D.is_point_in_polygon(p, ipoly):
			var near_edge := false
			var edge_pad := maxf(2.2, pad)
			for i in range(ipoly.size()):
				var q := Geometry2D.get_closest_point_to_segment(p, ipoly[i], ipoly[(i + 1) % ipoly.size()])
				if p.distance_squared_to(q) < edge_pad * edge_pad:
					near_edge = true
					break
			if not near_edge:
				return false
	for rec in clear["water_polys"]:
		var amin: Vector2 = rec[0]
		var amax: Vector2 = rec[1]
		if p.x < amin.x - pad or p.x > amax.x + pad or p.y < amin.y - pad or p.y > amax.y + pad:
			continue
		var poly: PackedVector2Array = rec[2]
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		if pad > 0.1:
			for i in range(poly.size()):
				var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
				if p.distance_squared_to(q) < pad * pad:
					return true
	return false


static func _inside_any_park(clear: Dictionary, p: Vector2) -> bool:
	for rec in clear["park_polys"]:
		var amin: Vector2 = rec[0]
		var amax: Vector2 = rec[1]
		if p.x < amin.x or p.x > amax.x or p.y < amin.y or p.y > amax.y:
			continue
		if Geometry2D.is_point_in_polygon(p, rec[2] as PackedVector2Array):
			return true
	return false


static func _near_any_path_or_plaza(p: Vector2, path_segs: Array, plaza_circles: Array, extra_pad: float) -> bool:
	for pc in plaza_circles:
		var c: Vector2 = pc[0]
		var r := float(pc[1]) + extra_pad
		if p.distance_squared_to(c) < r * r:
			return true
	for ps in path_segs:
		var q := Geometry2D.get_closest_point_to_segment(p, ps[0] as Vector2, ps[1] as Vector2)
		var w := float(ps[2]) + extra_pad
		if p.distance_squared_to(q) < w * w:
			return true
	return false


static func _clean_poly(raw_pts: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in raw_pts:
		var v := Vector2(float(p[0]), float(p[1]))
		if pts.size() == 0 or pts[pts.size() - 1].distance_to(v) > 0.12:
			pts.append(v)
	if pts.size() >= 3 and pts[0].distance_to(pts[pts.size() - 1]) <= 0.12:
		pts.resize(pts.size() - 1)
	return pts


static func _poly_signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in range(n):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		a += p0.x * p1.y - p1.x * p0.y
	return a * 0.5


static func _hash01(x: float, z: float, salt: float = 0.0) -> float:
	var v := sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453
	return v - floor(v)


# ---------------------------------------------------------------------------------------------
# 1. LAKE UNION & LAKE UNION PARK WATERFRONT MASTERPIECE (SEATTLE)
# ---------------------------------------------------------------------------------------------
static func _build_lake_union_waterfront(
	parent: Node3D,
	areas: Array,
	clear: Dictionary,
	prop_lists: Dictionary,
	path_segs: Array,
	plaza_circles: Array,
	extra_park_trees: Array,
	lights: Array,
	globe_mat: StandardMaterial3D
) -> void:
	var lu_root := Node3D.new()
	lu_root.name = "LakeUnionWaterfront"
	parent.add_child(lu_root)

	# Locate the cleaned Lake Union water polygon (largest northern water body)
	var lu_poly := PackedVector2Array()
	for rec in clear["water_polys"]:
		var poly: PackedVector2Array = rec[2]
		if poly.size() > 120:
			var wmin: Vector2 = rec[0]
			var wmax: Vector2 = rec[1]
			if wmin.y < -1500.0 and wmax.y > -960.0:
				lu_poly = poly
				break

	if lu_poly.is_empty():
		return

	# Extract the continuous south shoreline polyline along Lake Union Park & SLU Waterfront
	var shore_pts: Array[Vector2] = []
	for v in lu_poly:
		if v.x >= -175.0 and v.x <= 325.0 and v.y >= -1165.0 and v.y <= -870.0:
			if shore_pts.is_empty() or shore_pts[shore_pts.size() - 1].distance_to(v) > 2.2:
				shore_pts.append(v)

	# 1A. 3D Granite Seawall, Stepped Stone Riprap & Cedar Waterfront Boardwalk along the Shoreline
	var seawall_st := SurfaceTool.new()
	seawall_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var riprap_st := SurfaceTool.new()
	riprap_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var board_st := SurfaceTool.new()
	board_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail_st := SurfaceTool.new()
	rail_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var accum_d := 0.0
	var next_lamp_d := 14.0
	var next_bench_d := 9.0
	var next_willow_d := 22.0

	for i in range(shore_pts.size() - 1):
		var a := shore_pts[i]
		var b := shore_pts[i + 1]
		var seg_v := b - a
		var seg_len := seg_v.length()
		if seg_len < 0.8 or seg_len > 48.0:
			continue
		var dir := seg_v / seg_len
		var left_n := Vector2(-dir.y, dir.x)
		var mid := (a + b) * 0.5
		# Determine which normal points inland (away from Lake Union water)
		var inland_n := left_n
		if _inside_any_water(clear, mid + inland_n * 2.4):
			inland_n = -left_n
		var lake_n := -inland_n

		# Concrete/Granite seawall curb right on the shoreline (y = -0.35 .. 0.48)
		var wall_w := 0.65
		_add_strip_prism(seawall_st, a, b, inland_n, 0.0, wall_w, -0.35, 0.46, Color(0.62, 0.61, 0.58))
		# Sloped dark-granite stone riprap toe entering the water
		_add_slope_quad(
			riprap_st,
			a + lake_n * 0.05, b + lake_n * 0.05, 0.28,
			a + lake_n * 1.85, b + lake_n * 1.85, -0.22,
			Color(0.36, 0.37, 0.36)
		)

		# Cedar-plank waterfront boardwalk / esplanade inland behind seawall (when clear of buildings & roads!)
		var bw_mid := mid + inland_n * 2.5
		if _road_clearance(clear, bw_mid) > 1.8 and not _inside_any_building(clear, bw_mid, 1.4) and not _inside_any_water(clear, bw_mid):
			_add_strip_prism(board_st, a, b, inland_n, wall_w, wall_w + 3.6, 0.02, 0.24, Color(0.56, 0.41, 0.28))
			path_segs.append([a + inland_n * (wall_w + 1.8), b + inland_n * (wall_w + 1.8), 2.8])

			# Post-and-cable maritime railing along the seawall edge
			var n_posts := maxi(1, int(floor(seg_len / 3.0)))
			for pk in range(n_posts):
				var t0 := float(pk) / float(n_posts)
				var t1 := float(pk + 1) / float(n_posts)
				var p0 := a.lerp(b, t0) + inland_n * 0.34
				var p1 := a.lerp(b, t1) + inland_n * 0.34
				# Vertical dark steel stanchion
				_box_into(rail_st, Vector3(p0.x, 0.88, p0.y), Vector3(0.08, 0.90, 0.08), Color(0.18, 0.21, 0.25))
				# Cedar top handrail & 2 stainless mid cables
				_add_beam(rail_st, Vector3(p0.x, 1.32, p0.y), Vector3(p1.x, 1.32, p1.y), 0.09, 0.05, Color(0.54, 0.38, 0.24))
				_add_beam(rail_st, Vector3(p0.x, 0.98, p0.y), Vector3(p1.x, 0.98, p1.y), 0.025, 0.025, Color(0.72, 0.75, 0.78))
				_add_beam(rail_st, Vector3(p0.x, 0.72, p0.y), Vector3(p1.x, 0.72, p1.y), 0.025, 0.025, Color(0.72, 0.75, 0.78))

			# Waterfront benches facing Lake Union, bollard lights & lakeside weeping willows
			var yaw_lake := atan2(lake_n.x, lake_n.y)
			if accum_d + seg_len >= next_bench_d:
				var bp := mid + inland_n * 3.35
				if _road_clearance(clear, bp) > 2.2 and not _inside_any_building(clear, bp, 1.6):
					(prop_lists["bench"] as Array).append(Transform3D(Basis(Vector3.UP, yaw_lake), Vector3(bp.x, 0.24, bp.y)))
					if _hash01(bp.x, bp.y, 3.0) < 0.45:
						var flp := bp + dir * 2.2 + inland_n * 0.65
						if not _inside_any_water(clear, flp) and _road_clearance(clear, flp) > 2.0:
							(prop_lists["flower_blue"] as Array).append(Transform3D(Basis(Vector3.UP, yaw_lake), Vector3(flp.x, 0.03, flp.y)))
				next_bench_d = accum_d + 19.0
			if accum_d + seg_len >= next_lamp_d:
				var lp := mid + inland_n * 0.75
				(prop_lists["park_lamp"] as Array).append(Transform3D(Basis(Vector3.UP, yaw_lake), Vector3(lp.x, 0.24, lp.y)))
				if lights.size() < 42 and int(accum_d) % 45 < 16:
					var om := OmniLight3D.new()
					om.position = Vector3(lp.x, 4.1 + (Terrain.surface(lp.x, lp.y) if Terrain.active else 0.0), lp.y)
					om.light_color = Color(1.0, 0.86, 0.62)
					om.light_energy = 1.6
					om.omni_range = 19.0
					om.shadow_enabled = false
					if Terrain.active:
						om.set_meta("on_terrain", true)
					lu_root.add_child(om)
					lights.append(om)
				next_lamp_d = accum_d + 22.0
			if accum_d + seg_len >= next_willow_d:
				var wp := mid + inland_n * 6.8
				if _inside_any_park(clear, wp) and _road_clearance(clear, wp) > 4.2 and not _inside_any_building(clear, wp, 3.5) and not _inside_any_water(clear, wp, 1.5):
					extra_park_trees.append({"pos": wp, "species": 5, "scale": 1.0 + _hash01(wp.x, wp.y, 1.0) * 0.35})
				next_willow_d = accum_d + 28.0

		accum_d += seg_len

	_commit_vc_mesh(lu_root, "LakeUnionSeawall", seawall_st, 0.86, 0.02, false)
	_commit_vc_mesh(lu_root, "LakeUnionRiprap", riprap_st, 0.94, 0.0, false)
	_commit_vc_mesh(lu_root, "LakeUnionBoardwalk", board_st, 0.82, 0.02, false)
	_commit_vc_mesh(lu_root, "LakeUnionRailings", rail_st, 0.55, 0.35, true)

	# 1B. Iconic Lake Union Park Curved Timber Pedestrian Footbridge spanning the cove!
	_build_lake_union_footbridge(lu_root, Vector2(-56.0, -914.0), Vector2(-20.0, -919.0), path_segs)

	# 1C. Model Boat Pond Plaza (exact OSM pond center: x=3.8, z=-954.8, R=15.0m)
	var pond_c := Vector2(3.8, -954.8)
	_build_model_boat_pond(lu_root, pond_c, 15.2, prop_lists, plaza_circles, lights)

	# 1D. Lake Union Park Fountain & Terraced Amphitheater Lawn overlooking Lake Union!
	var fount_c := Vector2(44.0, -926.0)
	if not _inside_any_building(clear, fount_c, 6.0) and _road_clearance(clear, fount_c) > 6.0:
		_build_lake_union_fountain_plaza(lu_root, fount_c, prop_lists, plaza_circles, lights)

	# 1E. Pier Mooring Bollards, Dock Benches & Vibrant Lake Union Maritime Fleet (Sailboats, Historic Ship, Floatplanes!)
	_build_lake_union_maritime_life(lu_root, prop_lists, globe_mat)


static func _build_lake_union_footbridge(parent: Node3D, p_start: Vector2, p_end: Vector2, path_segs: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 14
	var span_v := p_end - p_start
	var dir := span_v.normalized()
	var side := Vector2(-dir.y, dir.x)
	var half_w := 2.05
	var arch_h := 2.35

	# Granite abutments on both banks
	_box_into(st, Vector3(p_start.x, 0.35, p_start.y), Vector3(5.2, 1.0, 3.6), Color(0.62, 0.61, 0.58))
	_box_into(st, Vector3(p_end.x, 0.35, p_end.y), Vector3(5.2, 1.0, 3.6), Color(0.62, 0.61, 0.58))

	for i in range(segs):
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var c0 := p_start.lerp(p_end, t0) + side * (sin(t0 * PI) * 2.4)
		var c1 := p_start.lerp(p_end, t1) + side * (sin(t1 * PI) * 2.4)
		var y0 := 0.55 + sin(t0 * PI) * arch_h
		var y1 := 0.55 + sin(t1 * PI) * arch_h
		var seg_d := (c1 - c0).normalized()
		var s_n := Vector2(-seg_d.y, seg_d.x)

		# Cedar planked deck + underside structural steel arch beam
		var l0 := Vector3(c0.x - s_n.x * half_w, y0, c0.y - s_n.y * half_w)
		var r0 := Vector3(c0.x + s_n.x * half_w, y0, c0.y + s_n.y * half_w)
		var r1 := Vector3(c1.x + s_n.x * half_w, y1, c1.y + s_n.y * half_w)
		var l1 := Vector3(c1.x - s_n.x * half_w, y1, c1.y - s_n.y * half_w)
		_add_vc_quad(st, l0, r0, r1, l1, Color(0.58, 0.42, 0.26))
		_add_vc_quad(st, l0 - Vector3(0, 0.32, 0), l1 - Vector3(0, 0.32, 0), r1 - Vector3(0, 0.32, 0), r0 - Vector3(0, 0.32, 0), Color(0.24, 0.27, 0.30))
		# Side steel fascia girders
		_add_vc_quad(st, l0, l1, l1 - Vector3(0, 0.32, 0), l0 - Vector3(0, 0.32, 0), Color(0.22, 0.25, 0.28))
		_add_vc_quad(st, r1, r0, r0 - Vector3(0, 0.32, 0), r1 - Vector3(0, 0.32, 0), Color(0.22, 0.25, 0.28))

		# Bridge handrails & stanchions on both sides
		for sgn: float in [-1.0, 1.0]:
			var b0 := Vector3(c0.x + s_n.x * (half_w - 0.12) * sgn, y0, c0.y + s_n.y * (half_w - 0.12) * sgn)
			var b1 := Vector3(c1.x + s_n.x * (half_w - 0.12) * sgn, y1, c1.y + s_n.y * (half_w - 0.12) * sgn)
			_box_into(st, b0 + Vector3(0, 0.58, 0), Vector3(0.09, 1.15, 0.09), Color(0.20, 0.23, 0.27))
			_add_beam(st, b0 + Vector3(0, 1.14, 0), b1 + Vector3(0, 1.14, 0), 0.10, 0.06, Color(0.55, 0.39, 0.24))
			_add_beam(st, b0 + Vector3(0, 0.66, 0), b1 + Vector3(0, 0.66, 0), 0.03, 0.03, Color(0.75, 0.78, 0.80))

		# Support piers into cove water near quarter spans
		if i == 4 or i == 10:
			for sgn: float in [-1.0, 1.0]:
				var pp := c0 + s_n * (half_w * 0.72 * sgn)
				_cyl_into(st, 0.24, -0.5, y0 - 0.2, 10, Color(0.35, 0.33, 0.31), Vector3(pp.x, 0.0, pp.y))

	path_segs.append([p_start, p_end, 4.0])
	_commit_vc_mesh(parent, "LakeUnionFootbridge", st, 0.72, 0.18, true)


static func _build_model_boat_pond(
	parent: Node3D,
	center: Vector2,
	radius: float,
	prop_lists: Dictionary,
	plaza_circles: Array,
	lights: Array
) -> void:
	plaza_circles.append([center, radius + 6.5])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 36
	var r_in := radius - 0.3
	var r_coping := radius + 0.55
	var r_walk := radius + 5.2

	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))

		# Raised granite coping rim around the Model Boat Pond
		var p_in0 := center + d0 * r_in
		var p_in1 := center + d1 * r_in
		var p_cp0 := center + d0 * r_coping
		var p_cp1 := center + d1 * r_coping
		var p_wk0 := center + d0 * r_walk
		var p_wk1 := center + d1 * r_walk

		_add_vc_quad(st, Vector3(p_in0.x, 0.44, p_in0.y), Vector3(p_cp0.x, 0.44, p_cp0.y), Vector3(p_cp1.x, 0.44, p_cp1.y), Vector3(p_in1.x, 0.44, p_in1.y), Color(0.74, 0.73, 0.69))
		_add_vc_quad(st, Vector3(p_in0.x, 0.0, p_in0.y), Vector3(p_in0.x, 0.44, p_in0.y), Vector3(p_in1.x, 0.44, p_in1.y), Vector3(p_in1.x, 0.0, p_in1.y), Color(0.52, 0.53, 0.52))
		_add_vc_quad(st, Vector3(p_cp0.x, 0.44, p_cp0.y), Vector3(p_cp0.x, 0.04, p_cp0.y), Vector3(p_cp1.x, 0.04, p_cp1.y), Vector3(p_cp1.x, 0.44, p_cp1.y), Color(0.58, 0.57, 0.54))
		# Surrounding circular stone-paver promenade ring
		var w_col := Color(0.74, 0.71, 0.64) if i % 2 == 0 else Color(0.70, 0.67, 0.60)
		_add_vc_quad(st, Vector3(p_cp0.x, 0.042, p_cp0.y), Vector3(p_wk0.x, 0.042, p_wk0.y), Vector3(p_wk1.x, 0.042, p_wk1.y), Vector3(p_cp1.x, 0.042, p_cp1.y), w_col)

	# 4 Colorful miniature model sailboats floating on the Model Boat Pond!
	var mini_cols: Array[Color] = [Color(0.88, 0.22, 0.18), Color(0.14, 0.42, 0.82), Color(0.92, 0.72, 0.14), Color(0.18, 0.62, 0.36)]
	for m in range(4):
		var ang := float(m) * 1.55 + 0.4
		var mp := center + Vector2(cos(ang), sin(ang)) * (radius * 0.46)
		_add_sailboat_into(st, Vector3(mp.x, 0.04, mp.y), ang + 1.2, 0.26, mini_cols[m], Color(0.98, 0.97, 0.94))

	_commit_vc_mesh(parent, "ModelBoatPondPlaza", st, 0.78, 0.04, true)

	# 8 radial park benches, 4 park lamps & 4 flowerbeds around the pond
	for k in range(8):
		var a := TAU * float(k) / 8.0 + 0.2
		var dir_out := Vector2(cos(a), sin(a))
		var bp := center + dir_out * (radius + 3.6)
		var yaw_in := atan2(-dir_out.x, -dir_out.y)
		(prop_lists["bench"] as Array).append(Transform3D(Basis(Vector3.UP, yaw_in), Vector3(bp.x, 0.045, bp.y)))
		if k % 2 == 0:
			var lp := center + dir_out * (radius + 4.7)
			(prop_lists["park_lamp"] as Array).append(Transform3D(Basis(Vector3.UP, yaw_in), Vector3(lp.x, 0.045, lp.y)))
			var fp := center + Vector2(cos(a + 0.38), sin(a + 0.38)) * (radius + 5.8)
			var fkey := "flower_pink" if k % 4 == 0 else "flower_gold"
			(prop_lists[fkey] as Array).append(Transform3D(Basis(Vector3.UP, a), Vector3(fp.x, 0.03, fp.y)))
	if lights.size() < 46:
		var om := OmniLight3D.new()
		om.position = Vector3(center.x, 4.4 + (Terrain.surface(center.x, center.y) if Terrain.active else 0.0), center.y)
		om.light_color = Color(1.0, 0.88, 0.66)
		om.light_energy = 1.8
		om.omni_range = 24.0
		om.shadow_enabled = false
		if Terrain.active:
			om.set_meta("on_terrain", true)
		parent.add_child(om)
		lights.append(om)


static func _build_lake_union_fountain_plaza(
	parent: Node3D,
	center: Vector2,
	prop_lists: Dictionary,
	plaza_circles: Array,
	lights: Array
) -> void:
	plaza_circles.append([center, 13.5])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28

	# Circular granite spray-fountain plaza + central sculpted fountain basin & translucent water plumes
	_cyl_into(st, 11.5, 0.0, 0.045, segs, Color(0.73, 0.71, 0.67), Vector3(center.x, 0.0, center.y))
	_cyl_into(st, 6.2, 0.045, 0.065, segs, Color(0.62, 0.63, 0.64), Vector3(center.x, 0.0, center.y))
	_cyl_into(st, 3.6, 0.065, 0.42, segs, Color(0.76, 0.75, 0.72), Vector3(center.x, 0.0, center.y))
	_cyl_into(st, 3.2, 0.42, 0.44, segs, Color(0.16, 0.46, 0.56), Vector3(center.x, 0.0, center.y))
	# Central stainless spray sculpture & sparkling water column
	_cyl_into(st, 0.45, 0.44, 1.35, 12, Color(0.66, 0.70, 0.74), Vector3(center.x, 0.0, center.y))
	_cyl_into(st, 0.16, 1.35, 3.10, 10, Color(0.84, 0.94, 0.98), Vector3(center.x, 0.0, center.y))
	for j in range(6):
		var a := TAU * float(j) / 6.0
		var jp := Vector3(center.x + cos(a) * 1.4, 0.0, center.y + sin(a) * 1.4)
		_cyl_into(st, 0.09, 0.44, 1.85, 8, Color(0.86, 0.95, 0.99), jp)

	# 3 Concentric stepped granite amphitheater seating arcs on the south side facing north to Lake Union!
	for tier in range(3):
		var r0 := 11.8 + float(tier) * 1.55
		var r1 := r0 + 1.15
		var h := 0.42 + float(tier) * 0.44
		for s in range(10):
			var a0 := deg_to_rad(25.0 + float(s) * 13.0)
			var a1 := deg_to_rad(25.0 + float(s + 1) * 13.0)
			var p00 := center + Vector2(cos(a0), sin(a0)) * r0
			var p01 := center + Vector2(cos(a1), sin(a1)) * r0
			var p10 := center + Vector2(cos(a0), sin(a0)) * r1
			var p11 := center + Vector2(cos(a1), sin(a1)) * r1
			_add_vc_quad(st, Vector3(p00.x, h, p00.y), Vector3(p10.x, h, p10.y), Vector3(p11.x, h, p11.y), Vector3(p01.x, h, p01.y), Color(0.75, 0.73, 0.69))
			_add_vc_quad(st, Vector3(p00.x, 0.0, p00.y), Vector3(p00.x, h, p00.y), Vector3(p01.x, h, p01.y), Vector3(p01.x, 0.0, p01.y), Color(0.56, 0.55, 0.52))

	_commit_vc_mesh(parent, "LakeUnionFountainPlaza", st, 0.72, 0.08, true)

	for k in range(4):
		var a := deg_to_rad(-140.0 + float(k) * 34.0)
		var dir_out := Vector2(cos(a), sin(a))
		var bp := center + dir_out * 9.2
		(prop_lists["bench"] as Array).append(Transform3D(Basis(Vector3.UP, atan2(-dir_out.x, -dir_out.y)), Vector3(bp.x, 0.048, bp.y)))
	for k in range(4):
		var a := deg_to_rad(40.0 + float(k) * 34.0)
		var fp := center + Vector2(cos(a), sin(a)) * 17.5
		(prop_lists["flower_pink" if k % 2 == 0 else "flower_blue"] as Array).append(Transform3D(Basis(Vector3.UP, a), Vector3(fp.x, 0.03, fp.y)))
	if lights.size() < 48:
		var om := OmniLight3D.new()
		om.position = Vector3(center.x, 3.8 + (Terrain.surface(center.x, center.y) if Terrain.active else 0.0), center.y)
		om.light_color = Color(0.82, 0.94, 1.0)
		om.light_energy = 1.6
		om.omni_range = 20.0
		om.shadow_enabled = false
		if Terrain.active:
			om.set_meta("on_terrain", true)
		parent.add_child(om)
		lights.append(om)


static func _build_lake_union_maritime_life(parent: Node3D, prop_lists: Dictionary, _globe_mat: StandardMaterial3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Yellow maritime mooring bollards & dock benches along Lake Union wooden piers
	var pier_bollards: Array[Vector2] = [
		Vector2(120.5, -945.0), Vector2(120.5, -975.0), Vector2(120.5, -1005.0), Vector2(120.5, -1040.0), Vector2(120.5, -1072.0),
		Vector2(150.5, -945.0), Vector2(150.5, -985.0), Vector2(150.5, -1030.0), Vector2(150.5, -1072.0),
		Vector2(174.0, -965.0), Vector2(174.0, -1015.0), Vector2(174.0, -1065.0), Vector2(174.0, -1095.0),
		Vector2(215.0, -965.0), Vector2(215.0, -1025.0), Vector2(215.0, -1085.0),
		Vector2(62.0, -1073.0), Vector2(85.0, -1073.0), Vector2(106.0, -1073.0),
	]
	for bp in pier_bollards:
		_cyl_into(st, 0.16, 0.62, 1.18, 10, Color(0.92, 0.72, 0.12), Vector3(bp.x, 0.0, bp.y))
		_cyl_into(st, 0.22, 1.12, 1.24, 10, Color(0.86, 0.64, 0.10), Vector3(bp.x, 0.0, bp.y))

	# Dockside benches & warm promenade lights on the piers
	for dp: Array in [
		[Vector2(132.0, -1055.0), 0.0],
		[Vector2(180.0, -1045.0), PI * 0.5],
		[Vector2(76.0, -1072.0), PI],
	]:
		var p2: Vector2 = dp[0]
		(prop_lists["bench"] as Array).append(Transform3D(Basis(Vector3.UP, float(dp[1])), Vector3(p2.x, 0.62, p2.y)))
		(prop_lists["bollard_light"] as Array).append(Transform3D(Basis.IDENTITY, Vector3(p2.x + 2.2, 0.62, p2.y)))

	# 18 Sculpted Sailboats & Wooden Boats moored along the piers AND gliding on Lake Union!
	var boats: Array = [
		# Moored at Center for Wooden Boats & Marina slips (hull_pos, yaw, scale, hull_col, sail_up)
		[Vector2(161.0, -978.0), 0.05, 0.88, Color(0.94, 0.95, 0.96), false],
		[Vector2(162.0, -1006.0), -0.04, 0.95, Color(0.14, 0.28, 0.52), false],
		[Vector2(161.0, -1034.0), 0.02, 0.82, Color(0.62, 0.22, 0.16), false],
		[Vector2(162.0, -1062.0), 0.06, 1.02, Color(0.92, 0.91, 0.86), false],
		[Vector2(194.0, -985.0), -0.05, 0.92, Color(0.46, 0.28, 0.16), false],
		[Vector2(195.0, -1018.0), 0.04, 1.05, Color(0.16, 0.38, 0.34), false],
		[Vector2(194.0, -1052.0), -0.02, 0.86, Color(0.94, 0.94, 0.92), false],
		[Vector2(196.0, -1082.0), 0.03, 0.96, Color(0.20, 0.32, 0.56), false],
		[Vector2(246.0, -1010.0), 0.12, 0.90, Color(0.88, 0.88, 0.85), false],
		[Vector2(248.0, -1055.0), -0.08, 1.05, Color(0.58, 0.20, 0.16), false],
		# Sailing gracefully out on Lake Union with full hoisted white/cream sails!
		[Vector2(-15.0, -1115.0), 0.72, 1.15, Color(0.95, 0.96, 0.97), true],
		[Vector2(45.0, -1165.0), 1.25, 1.25, Color(0.14, 0.26, 0.48), true],
		[Vector2(138.0, -1185.0), -0.85, 1.18, Color(0.72, 0.18, 0.16), true],
		[Vector2(-82.0, -1190.0), 0.45, 1.10, Color(0.96, 0.94, 0.88), true],
		[Vector2(220.0, -1220.0), -1.10, 1.32, Color(0.16, 0.40, 0.36), true],
		[Vector2(18.0, -1280.0), 1.80, 1.22, Color(0.95, 0.95, 0.95), true],
		[Vector2(-140.0, -1260.0), 0.25, 1.12, Color(0.24, 0.36, 0.58), true],
		[Vector2(165.0, -1330.0), -0.50, 1.30, Color(0.88, 0.86, 0.82), true],
	]
	for b in boats:
		var bp: Vector2 = b[0]
		_add_sailboat_into(st, Vector3(bp.x, 0.04, bp.y), float(b[1]), float(b[2]), b[3] as Color, Color(0.98, 0.97, 0.93), bool(b[4]))

	# Historic Ships Wharf Steamship / Tugboat tribute moored right north of MOHAI!
	_add_historic_ship_into(st, Vector3(84.0, 0.04, -1090.0), 0.04)

	# 2 Iconic Seattle Kenmore Air Seaplanes / Floatplanes on Lake Union!
	_add_floatplane_into(st, Vector3(-92.0, 0.06, -1062.0), -0.45)
	_add_floatplane_into(st, Vector3(-18.0, 0.06, -1158.0), 0.62)

	_commit_vc_mesh(parent, "LakeUnionMaritimeFleet", st, 0.48, 0.14, true)


static func _add_sailboat_into(
	st: SurfaceTool,
	pos: Vector3,
	yaw: float,
	sc: float,
	hull_col: Color,
	sail_col: Color,
	sail_up: bool = true
) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), pos)
	# Sculpted tapered hull (bow at +Z, stern at -Z)
	var hull_pts := [
		Vector3(0.0, 0.0, 4.4),
		Vector3(1.15, 0.15, 1.5),
		Vector3(1.22, 0.15, -2.0),
		Vector3(0.92, 0.15, -3.6),
		Vector3(-0.92, 0.15, -3.6),
		Vector3(-1.22, 0.15, -2.0),
		Vector3(-1.15, 0.15, 1.5),
	]
	var hull_top := [
		Vector3(0.0, 0.95, 4.7),
		Vector3(1.28, 0.88, 1.5),
		Vector3(1.32, 0.84, -2.0),
		Vector3(0.98, 0.86, -3.7),
		Vector3(-0.98, 0.86, -3.7),
		Vector3(-1.32, 0.84, -2.0),
		Vector3(-1.28, 0.88, 1.5),
	]
	for i in range(hull_pts.size()):
		var j := (i + 1) % hull_pts.size()
		_add_vc_quad(st, xf * hull_pts[i], xf * hull_pts[j], xf * hull_top[j], xf * hull_top[i], hull_col)
	# Teak deck & white cabin trunk
	var deck_c := xf * Vector3(0.0, 0.86, 0.0)
	for i in range(hull_top.size()):
		var j := (i + 1) % hull_top.size()
		_add_vc_tri(st, deck_c, xf * hull_top[j], xf * hull_top[i], Color(0.76, 0.68, 0.56))
	_box_xf(st, xf, Vector3(0.0, 1.15, -0.3), Vector3(1.35, 0.55, 2.8), Color(0.96, 0.95, 0.93))
	_box_xf(st, xf, Vector3(0.0, 1.20, -0.2), Vector3(1.38, 0.22, 1.6), Color(0.12, 0.18, 0.24))
	# Aluminum mast & boom
	_box_xf(st, xf, Vector3(0.0, 5.2, 0.45), Vector3(0.11, 8.2, 0.11), Color(0.80, 0.82, 0.85))
	_box_xf(st, xf, Vector3(0.0, 2.05, -1.25), Vector3(0.09, 0.09, 3.4), Color(0.78, 0.80, 0.82))
	if sail_up:
		# Hoisted mainsail + jib (double-sided via cull_disabled)
		var m_top := xf * Vector3(0.0, 9.1, 0.42)
		var m_bot := xf * Vector3(0.0, 2.1, 0.42)
		var m_aft := xf * Vector3(0.32, 2.1, -2.85)
		_add_vc_tri(st, m_top, m_bot, m_aft, sail_col)
		var j_top := xf * Vector3(0.0, 8.6, 0.55)
		var j_bow := xf * Vector3(0.0, 1.1, 4.55)
		var j_clew := xf * Vector3(0.28, 1.9, 0.85)
		_add_vc_tri(st, j_top, j_bow, j_clew, sail_col.darkened(0.04))
	else:
		# Furled navy sail cover along the boom
		_box_xf(st, xf, Vector3(0.0, 2.18, -1.25), Vector3(0.26, 0.24, 3.3), Color(0.14, 0.24, 0.44))


static func _add_historic_ship_into(st: SurfaceTool, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	# Classic Lake Union steamship / tugboat (28m long)
	_box_xf(st, xf, Vector3(0.0, 1.15, 0.0), Vector3(6.8, 2.2, 24.0), Color(0.16, 0.18, 0.20))
	_box_xf(st, xf, Vector3(0.0, 0.35, 0.0), Vector3(6.9, 0.65, 24.2), Color(0.68, 0.16, 0.14))
	# Pointed bow prism
	var b_l := xf * Vector3(-3.4, 2.25, 12.0)
	var b_r := xf * Vector3(3.4, 2.25, 12.0)
	var b_tip := xf * Vector3(0.0, 2.45, 16.5)
	var b_l0 := xf * Vector3(-3.4, 0.0, 12.0)
	var b_r0 := xf * Vector3(3.4, 0.0, 12.0)
	var b_t0 := xf * Vector3(0.0, 0.0, 15.8)
	_add_vc_quad(st, b_l0, b_t0, b_tip, b_l, Color(0.16, 0.18, 0.20))
	_add_vc_quad(st, b_t0, b_r0, b_r, b_tip, Color(0.16, 0.18, 0.20))
	_add_vc_tri(st, b_l, b_tip, b_r, Color(0.62, 0.48, 0.34))
	# Main timber deck & 2-tier white passenger deckhouse + wheelhouse
	_box_xf(st, xf, Vector3(0.0, 2.32, 0.0), Vector3(6.6, 0.18, 23.6), Color(0.64, 0.48, 0.32))
	_box_xf(st, xf, Vector3(0.0, 3.65, -1.0), Vector3(5.2, 2.5, 16.0), Color(0.95, 0.94, 0.91))
	_box_xf(st, xf, Vector3(0.0, 3.85, -1.0), Vector3(5.28, 0.72, 13.5), Color(0.14, 0.20, 0.28))
	_box_xf(st, xf, Vector3(0.0, 5.75, 2.2), Vector3(3.8, 1.8, 5.6), Color(0.96, 0.95, 0.92))
	_box_xf(st, xf, Vector3(0.0, 6.05, 2.5), Vector3(3.88, 0.65, 4.8), Color(0.12, 0.18, 0.26))
	# Classic buff-and-black tall steamship smokestack + mast
	_cyl_into(st, 0.72, 4.9, 9.6, 12, Color(0.90, 0.74, 0.26), xf * Vector3(0.0, 0.0, -2.5))
	_cyl_into(st, 0.75, 8.6, 9.7, 12, Color(0.14, 0.14, 0.16), xf * Vector3(0.0, 0.0, -2.5))
	_box_xf(st, xf, Vector3(0.0, 7.6, 8.2), Vector3(0.22, 10.6, 0.22), Color(0.76, 0.68, 0.54))


static func _add_floatplane_into(st: SurfaceTool, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	# Twin aluminum pontoons / floats
	for sx: float in [-1.35, 1.35]:
		_box_xf(st, xf, Vector3(sx, 0.35, 0.4), Vector3(0.68, 0.56, 6.8), Color(0.84, 0.86, 0.88))
		_box_xf(st, xf, Vector3(sx * 0.72, 1.15, 0.9), Vector3(0.10, 1.45, 0.14), Color(0.22, 0.26, 0.30))
		_box_xf(st, xf, Vector3(sx * 0.72, 1.15, -0.9), Vector3(0.10, 1.45, 0.14), Color(0.22, 0.26, 0.30))
	# Fuselage (Kenmore Air white + Pacific blue belly stripe)
	_box_xf(st, xf, Vector3(0.0, 2.05, 0.4), Vector3(1.55, 1.45, 5.2), Color(0.96, 0.97, 0.98))
	_box_xf(st, xf, Vector3(0.0, 1.65, 0.2), Vector3(1.58, 0.45, 6.2), Color(0.10, 0.34, 0.66))
	_box_xf(st, xf, Vector3(0.0, 2.25, 1.2), Vector3(1.58, 0.55, 2.2), Color(0.14, 0.22, 0.32))
	_box_xf(st, xf, Vector3(0.0, 2.00, -3.4), Vector3(0.85, 0.95, 3.6), Color(0.95, 0.96, 0.98))
	# High wing + wing struts + tailplane + vertical fin + engine cowling
	_box_xf(st, xf, Vector3(0.0, 2.88, 0.65), Vector3(14.2, 0.24, 1.85), Color(0.96, 0.97, 0.98))
	_box_xf(st, xf, Vector3(0.0, 2.89, 0.65), Vector3(14.3, 0.26, 0.35), Color(0.10, 0.34, 0.66))
	_box_xf(st, xf, Vector3(0.0, 2.22, -4.85), Vector3(4.2, 0.14, 0.95), Color(0.95, 0.96, 0.98))
	_box_xf(st, xf, Vector3(0.0, 3.35, -4.75), Vector3(0.16, 2.15, 1.35), Color(0.10, 0.34, 0.66))
	_box_xf(st, xf, Vector3(0.0, 1.98, 3.35), Vector3(1.15, 1.15, 0.95), Color(0.10, 0.34, 0.66))
	_box_xf(st, xf, Vector3(0.0, 1.98, 3.92), Vector3(2.35, 0.14, 0.06), Color(0.18, 0.18, 0.20))


# ---------------------------------------------------------------------------------------------
# 2. ALL CITY PARKS & GREEN SPACES (GREENWAYS, PLAZAS, PAVILIONS, FURNITURE & GROVES)
# ---------------------------------------------------------------------------------------------
static func _build_parks_detail(
	parent: Node3D,
	areas: Array,
	clear: Dictionary,
	prop_lists: Dictionary,
	path_segs: Array,
	plaza_circles: Array,
	extra_park_trees: Array,
	lights: Array
) -> void:
	var path_st := SurfaceTool.new()
	path_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curb_st := SurfaceTool.new()
	curb_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plaza_st := SurfaceTool.new()
	plaza_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pav_st := SurfaceTool.new()
	pav_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var park_idx := 0
	for a in areas:
		var kind := str(a.get("kind", ""))
		if not (kind in ["park", "grass", "wood", "meadow", "garden"]):
			continue
		var poly := _clean_poly(a.get("pts", []))
		if poly.size() < 3:
			continue
		var area_m2 := absf(_poly_signed_area(poly))
		if area_m2 < 180.0:
			continue
		park_idx += 1

		var pmin := Vector2(1e9, 1e9)
		var pmax := Vector2(-1e9, -1e9)
		var centroid := Vector2.ZERO
		for v in poly:
			pmin = Vector2(minf(pmin.x, v.x), minf(pmin.y, v.y))
			pmax = Vector2(maxf(pmax.x, v.x), maxf(pmax.y, v.y))
			centroid += v
		centroid /= float(poly.size())
		var span := maxf(pmax.x - pmin.x, pmax.y - pmin.y)

		# 2A. Low Beveled Granite Perimeter Curb along park edges (only where clear of roads/water/buildings)
		if area_m2 >= 450.0 and kind != "wood":
			var is_ccw := _poly_signed_area(poly) > 0.0
			for i in range(poly.size()):
				var p0 := poly[i]
				var p1 := poly[(i + 1) % poly.size()]
				var slen := p0.distance_to(p1)
				if slen < 1.2 or slen > 140.0:
					continue
				var mid := (p0 + p1) * 0.5
				if _road_clearance(clear, mid) < 1.5 or _inside_any_water(clear, mid, 1.5) or _inside_any_building(clear, mid, 1.2):
					continue
				var d := (p1 - p0) / slen
				var in_n := Vector2(-d.y, d.x) if is_ccw else Vector2(d.y, -d.x)
				_add_strip_prism(curb_st, p0, p1, in_n, 0.0, 0.28, 0.015, 0.14, Color(0.68, 0.67, 0.63))

		# 2B. Organic Inset Loop Greenway / Walking Path & Central Stone Focal Plaza (Medium & Large Parks!)
		if area_m2 >= 1400.0 and span >= 34.0 and kind != "wood":
			var inset := clampf(minf(pmax.x - pmin.x, pmax.y - pmin.y) * 0.18, 6.0, 14.0)
			var offset_polys := Geometry2D.offset_polygon(poly, -inset, Geometry2D.JOIN_ROUND)
			var bench_accum := 0.0
			var lamp_accum := 0.0
			for op: PackedVector2Array in offset_polys:
				if op.size() < 4 or absf(_poly_signed_area(op)) < 260.0:
					continue
				var smooth_loop := _chaikin_smooth(op, 1)
				for i in range(smooth_loop.size()):
					var a0 := smooth_loop[i]
					var b0 := smooth_loop[(i + 1) % smooth_loop.size()]
					var slen := a0.distance_to(b0)
					if slen < 0.8 or slen > 80.0:
						continue
					var mid := (a0 + b0) * 0.5
					if _road_clearance(clear, mid) < 3.0 or _inside_any_building(clear, mid, 2.8) or _inside_any_water(clear, mid, 2.2):
						continue
					var dir := (b0 - a0) / slen
					var perp := Vector2(-dir.y, dir.x)
					# Warm cream/tan paved park greenway (2.6m wide) + stone edging (strictly below roads at 0.042)
					_add_strip_prism(path_st, a0, b0, perp, -1.30, 1.30, 0.016, 0.035, Color(0.76, 0.72, 0.64))
					_add_strip_prism(curb_st, a0, b0, perp, -1.46, -1.30, 0.016, 0.040, Color(0.58, 0.56, 0.52))
					_add_strip_prism(curb_st, a0, b0, perp, 1.30, 1.46, 0.016, 0.040, Color(0.58, 0.56, 0.52))
					path_segs.append([a0, b0, 2.4])

					# Place Seattle park benches, flowerbeds & bollard/park lamps neatly along the greenway
					bench_accum += slen
					lamp_accum += slen
					if bench_accum >= 22.0:
						bench_accum = 0.0
						var bp := mid + perp * 2.15
						if not Geometry2D.is_point_in_polygon(bp, poly):
							bp = mid - perp * 2.15
							perp = -perp
						if _road_clearance(clear, bp) > 3.2 and not _inside_any_building(clear, bp, 2.5) and not _inside_any_water(clear, bp, 2.0):
							var yaw_face := atan2(-perp.x, -perp.y)
							(prop_lists["bench"] as Array).append(Transform3D(Basis(Vector3.UP, yaw_face), Vector3(bp.x, 0.03, bp.y)))
							var side_p := bp + dir * 2.0
							if _hash01(bp.x, bp.y, 4.0) < 0.55 and _road_clearance(clear, side_p) > 3.0 and not _inside_any_building(clear, side_p, 2.2):
								var fkeys := ["flower_pink", "flower_blue", "flower_gold"]
								var fk: String = fkeys[int(absf(bp.x + bp.y)) % 3]
								(prop_lists[fk] as Array).append(Transform3D(Basis(Vector3.UP, yaw_face), Vector3(side_p.x, 0.03, side_p.y)))
							elif _hash01(bp.x, bp.y, 5.0) < 0.45:
								(prop_lists["park_bin"] as Array).append(Transform3D(Basis(Vector3.UP, yaw_face), Vector3(side_p.x, 0.03, side_p.y)))
					if lamp_accum >= 26.0:
						lamp_accum = 0.0
						var lp := mid - perp * 1.75
						if Geometry2D.is_point_in_polygon(lp, poly) and _road_clearance(clear, lp) > 2.8 and not _inside_any_building(clear, lp, 2.2) and not _inside_any_water(clear, lp, 1.8):
							(prop_lists["park_lamp"] as Array).append(Transform3D(Basis.IDENTITY, Vector3(lp.x, 0.03, lp.y)))

			# Find open interior clearings for Circular Focal Stone Plazas + Timber Pavilions (1-3 per park by size!)
			var n_plazas := 1 if area_m2 < 14000.0 else (2 if area_m2 < 42000.0 else 3)
			var plaza_anchors: Array[Vector2] = [
				centroid,
				centroid.lerp(pmin, 0.36),
				centroid.lerp(pmax, 0.36),
			]
			for pi_z in range(n_plazas):
				var plaza_c := _find_clear_park_spot(poly, plaza_anchors[pi_z], pmin, pmax, clear, 8.0)
				if plaza_c == Vector2(1e9, 1e9) or _near_any_path_or_plaza(plaza_c, [], plaza_circles, 22.0):
					continue
				var p_rad := 6.6 if area_m2 < 8000.0 else (8.8 if pi_z == 0 else 6.4)
				plaza_circles.append([plaza_c, p_rad + 2.4])
				_cyl_into(plaza_st, p_rad, 0.025, 0.058, 24, Color(0.76, 0.73, 0.67), Vector3(plaza_c.x, 0.0, plaza_c.y))
				_cyl_into(plaza_st, p_rad - 0.55, 0.058, 0.068, 24, Color(0.67, 0.63, 0.58), Vector3(plaza_c.x, 0.0, plaza_c.y))
				# Cross-park radial stone footpaths connecting the focal plaza out toward the perimeter walkways!
				for rk in range(4):
					var rang := float(rk) * PI * 0.5 + 0.25
					var rdir := Vector2(cos(rang), sin(rang))
					var rperp := Vector2(-rdir.y, rdir.x)
					var prev_rp := plaza_c + rdir * (p_rad - 0.4)
					for step_r in range(1, 7):
						var nxt_rp := plaza_c + rdir * (p_rad + float(step_r) * 7.5)
						if not Geometry2D.is_point_in_polygon(nxt_rp, poly) or _road_clearance(clear, nxt_rp) < 2.8 or _inside_any_water(clear, nxt_rp, 2.0) or _inside_any_building(clear, nxt_rp, 2.4):
							break
						_add_strip_prism(path_st, prev_rp, nxt_rp, rperp, -1.05, 1.05, 0.016, 0.036, Color(0.75, 0.71, 0.64))
						path_segs.append([prev_rp, nxt_rp, 2.0])
						prev_rp = nxt_rp
				# Timber Park Pavilion / Gazebo in medium & large parks (every focal plaza >= 2400m2!)
				if area_m2 >= 2400.0 and p_rad >= 6.2:
					_add_park_pavilion_into(pav_st, Vector3(plaza_c.x, 0.068, plaza_c.y), _hash01(plaza_c.x, plaza_c.y, 9.0) * PI)
					if lights.size() < 58:
						var om := OmniLight3D.new()
						om.position = Vector3(plaza_c.x, 3.6 + (Terrain.surface(plaza_c.x, plaza_c.y) if Terrain.active else 0.0), plaza_c.y)
						om.light_color = Color(1.0, 0.86, 0.62)
						om.light_energy = 1.6
						om.omni_range = 20.0
						om.shadow_enabled = false
						if Terrain.active:
							om.set_meta("on_terrain", true)
						parent.add_child(om)
						lights.append(om)
				# 4 radial benches + 4 ornamental flowerbeds around focal plaza
				for k in range(4):
					var ang := float(k) * PI * 0.5 + 0.35
					var dir_o := Vector2(cos(ang), sin(ang))
					var bp := plaza_c + dir_o * (p_rad - 1.3)
					(prop_lists["bench"] as Array).append(Transform3D(Basis(Vector3.UP, atan2(-dir_o.x, -dir_o.y)), Vector3(bp.x, 0.068, bp.y)))
					var fp := plaza_c + Vector2(cos(ang + 0.78), sin(ang + 0.78)) * (p_rad + 1.2)
					if Geometry2D.is_point_in_polygon(fp, poly) and _road_clearance(clear, fp) > 2.5:
						var fkey := "flower_pink" if k % 2 == 0 else "flower_gold"
						(prop_lists[fkey] as Array).append(Transform3D(Basis(Vector3.UP, ang), Vector3(fp.x, 0.03, fp.y)))

		# 2C. Populate Parks with Lush Multi-Species Woodland Groves (~10x denser trees!), Shrubs, Picnic Tables & Flowerbeds!
		var step_m := 6.4 if area_m2 < 12000.0 else (7.8 if area_m2 < 60000.0 else 9.2)
		var gx := pmin.x + 3.5
		while gx <= pmax.x - 3.5:
			var gz := pmin.y + 3.5
			while gz <= pmax.y - 3.5:
				var jx := (_hash01(gx, gz, 11.0) - 0.5) * step_m * 0.64
				var jz := (_hash01(gx, gz, 17.0) - 0.5) * step_m * 0.64
				var pt := Vector2(gx + jx, gz + jz)
				gz += step_m

				if not Geometry2D.is_point_in_polygon(pt, poly):
					continue
				if _road_clearance(clear, pt) < 3.6 or _inside_any_building(clear, pt, 3.0) or _inside_any_water(clear, pt, 2.0):
					continue
				if _near_any_path_or_plaza(pt, path_segs, plaza_circles, 2.3):
					continue

				var r := _hash01(pt.x, pt.y, 23.0)
				var yaw := _hash01(pt.x, pt.y, 29.0) * TAU
				if kind == "wood":
					if r < 0.88:
						var sp_w := 0 if _hash01(pt.x, pt.y, 31.0) < 0.62 else 1
						extra_park_trees.append({"pos": pt, "species": sp_w, "scale": 0.90 + _hash01(pt.x, pt.y, 37.0) * 0.50})
					else:
						(prop_lists["shrub"] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * (0.9 + r * 0.5)), Vector3(pt.x, 0.03, pt.y)))
				else:
					# Rich multi-species lush park canopy with natural sunlit glade pockets (grove_n < -0.58)
					var grove_n := sin(pt.x * 0.032) * cos(pt.y * 0.032)
					if grove_n > -0.58 and r < 0.80:
						var sp_r := _hash01(pt.x, pt.y, 41.0)
						var sp := 0 # Evergreen / Camphor (32%)
						if sp_r > 0.86:
							sp = 4 # Autumn Maple / Ginkgo (14%)
						elif sp_r > 0.72:
							sp = 3 # Silver Birch / Willow (14%)
						elif sp_r > 0.56:
							sp = 2 # Ornamental Cherry / Plum Blossom (16%)
						elif sp_r > 0.32:
							sp = 1 # Broadleaf Plane / Maple (24%)
						var sc := 0.86 + _hash01(pt.x, pt.y, 43.0) * 0.52
						extra_park_trees.append({"pos": pt, "species": sp, "scale": sc})
					elif r >= 0.80 and r < 0.90:
						(prop_lists["shrub"] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * (0.85 + _hash01(pt.x, pt.y, 47.0) * 0.55)), Vector3(pt.x, 0.03, pt.y)))
					elif r >= 0.90 and r < 0.95 and area_m2 >= 1800.0:
						(prop_lists["picnic"] as Array).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pt.x, 0.03, pt.y)))
					elif r >= 0.95:
						var fk := "flower_pink" if _hash01(pt.x, pt.y, 53.0) < 0.4 else ("flower_blue" if _hash01(pt.x, pt.y, 59.0) < 0.5 else "flower_gold")
						(prop_lists[fk] as Array).append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pt.x, 0.03, pt.y)))
			gx += step_m

	_commit_vc_mesh(parent, "ParkGreenways", path_st, 0.88, 0.0, false)
	_commit_vc_mesh(parent, "ParkGraniteCurbs", curb_st, 0.85, 0.02, false)
	_commit_vc_mesh(parent, "ParkFocalPlazas", plaza_st, 0.84, 0.02, false)
	_commit_vc_mesh(parent, "ParkPavilions", pav_st, 0.74, 0.08, true)


static func _find_clear_park_spot(
	poly: PackedVector2Array,
	centroid: Vector2,
	pmin: Vector2,
	pmax: Vector2,
	clear: Dictionary,
	min_r: float
) -> Vector2:
	var cands: Array[Vector2] = [
		centroid,
		(pmin + pmax) * 0.5,
		centroid.lerp(pmin, 0.32),
		centroid.lerp(pmax, 0.32),
		Vector2(pmin.x * 0.65 + pmax.x * 0.35, pmin.y * 0.35 + pmax.y * 0.65),
		Vector2(pmin.x * 0.35 + pmax.x * 0.65, pmin.y * 0.65 + pmax.y * 0.35),
	]
	for c in cands:
		if not Geometry2D.is_point_in_polygon(c, poly):
			continue
		if _road_clearance(clear, c) < min_r or _inside_any_building(clear, c, min_r * 0.75) or _inside_any_water(clear, c, min_r * 0.75):
			continue
		return c
	return Vector2(1e9, 1e9)


static func _add_park_pavilion_into(st: SurfaceTool, pos: Vector3, yaw: float) -> void:
	# Authentic Pacific Northwest cedar timber park pavilion / pergola with stone column plinths!
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var hw := 2.45
	var hd := 2.45
	var col_h := 3.15
	for sx: float in [-hw, hw]:
		for sz: float in [-hd, hd]:
			# Stone plinth base
			_box_xf(st, xf, Vector3(sx, 0.42, sz), Vector3(0.52, 0.84, 0.52), Color(0.60, 0.58, 0.54))
			_box_xf(st, xf, Vector3(sx, 0.86, sz), Vector3(0.58, 0.08, 0.58), Color(0.72, 0.70, 0.66))
			# Warm cedar timber column
			_box_xf(st, xf, Vector3(sx, 0.88 + col_h * 0.5, sz), Vector3(0.24, col_h, 0.24), Color(0.48, 0.30, 0.16))
	# Heavy perimeter roof girders & hipped shingle pavilion roof
	var top_y := 0.88 + col_h
	_box_xf(st, xf, Vector3(0.0, top_y, -hd), Vector3(hw * 2.0 + 0.9, 0.28, 0.26), Color(0.42, 0.26, 0.14))
	_box_xf(st, xf, Vector3(0.0, top_y, hd), Vector3(hw * 2.0 + 0.9, 0.28, 0.26), Color(0.42, 0.26, 0.14))
	_box_xf(st, xf, Vector3(-hw, top_y, 0.0), Vector3(0.26, 0.28, hd * 2.0 + 0.9), Color(0.42, 0.26, 0.14))
	_box_xf(st, xf, Vector3(hw, top_y, 0.0), Vector3(0.26, 0.28, hd * 2.0 + 0.9), Color(0.42, 0.26, 0.14))
	# Hipped cedar-slate pyramid roof
	var eave := hw + 0.65
	var r_y := top_y + 0.14
	var apex := xf * Vector3(0.0, r_y + 1.55, 0.0)
	var c0 := xf * Vector3(-eave, r_y, -eave)
	var c1 := xf * Vector3(eave, r_y, -eave)
	var c2 := xf * Vector3(eave, r_y, eave)
	var c3 := xf * Vector3(-eave, r_y, eave)
	_add_vc_tri(st, c0, c1, apex, Color(0.24, 0.30, 0.26))
	_add_vc_tri(st, c1, c2, apex, Color(0.20, 0.26, 0.22))
	_add_vc_tri(st, c2, c3, apex, Color(0.23, 0.29, 0.25))
	_add_vc_tri(st, c3, c0, apex, Color(0.21, 0.27, 0.23))
	# Central hanging brass lantern
	_box_xf(st, xf, Vector3(0.0, top_y - 0.45, 0.0), Vector3(0.32, 0.42, 0.32), Color(0.98, 0.88, 0.56))


static func _chaikin_smooth(poly: PackedVector2Array, iters: int) -> PackedVector2Array:
	var cur := poly
	for _it in range(iters):
		if cur.size() > 90:
			break
		var nxt := PackedVector2Array()
		var n := cur.size()
		for i in range(n):
			var a := cur[i]
			var b := cur[(i + 1) % n]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		cur = nxt
	return cur


# ---------------------------------------------------------------------------------------------
# 3. CHUNKED INSTANCED PARK FURNITURE (BENCHES, PICNIC TABLES, SHRUBS, FLOWERBEDS, LAMPS)
# ---------------------------------------------------------------------------------------------
static func _emit_park_props(parent: Node3D, prop_lists: Dictionary, globe_mat: StandardMaterial3D) -> void:
	var holder := Node3D.new()
	holder.name = "ParkFurniture"
	parent.add_child(holder)

	var mat_vc := StandardMaterial3D.new()
	mat_vc.vertex_color_use_as_albedo = true
	mat_vc.roughness = 0.76
	mat_vc.metallic = 0.10
	mat_vc.cull_mode = BaseMaterial3D.CULL_DISABLED

	for key: String in prop_lists.keys():
		var tfs: Array = prop_lists[key]
		if tfs.is_empty():
			continue
		var mesh := _get_prop_mesh(key)
		var chunks := {}
		for tf: Transform3D in tfs:
			var ck := Vector2i(int(floor(tf.origin.x / PROP_CHUNK)), int(floor(tf.origin.z / PROP_CHUNK)))
			if not chunks.has(ck):
				chunks[ck] = []
			(chunks[ck] as Array).append(tf)
		for ck: Vector2i in chunks.keys():
			var ctfs: Array = chunks[ck]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = ctfs.size()
			for i in range(ctfs.size()):
				var ptf: Transform3D = ctfs[i]
				if Terrain.active:
					ptf.origin.y += Terrain.surface(ptf.origin.x, ptf.origin.z)
				mm.set_instance_transform(i, ptf)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "ParkProp_%s_%d_%d" % [key, ck.x, ck.y]
			mmi.multimesh = mm
			mmi.material_override = mat_vc
			mmi.visibility_range_end = 340.0 if key in ["shrub", "park_lamp"] else 260.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key in ["bench", "picnic", "park_lamp"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if Terrain.active:
				mmi.set_meta("on_terrain", true)
			holder.add_child(mmi)

		# Glowing lantern globes for park lamps & waterfront bollard lights
		if key == "park_lamp" or key == "bollard_light":
			var g_sph := SphereMesh.new()
			g_sph.radius = 0.20 if key == "park_lamp" else 0.11
			g_sph.height = 0.40 if key == "park_lamp" else 0.24
			g_sph.radial_segments = 10
			g_sph.rings = 6
			g_sph.material = globe_mat
			var g_mm := MultiMesh.new()
			g_mm.transform_format = MultiMesh.TRANSFORM_3D
			g_mm.mesh = g_sph
			g_mm.instance_count = tfs.size()
			var gy := 3.65 if key == "park_lamp" else 0.92
			for i in range(tfs.size()):
				var tf: Transform3D = tfs[i]
				var g_dy := Terrain.surface(tf.origin.x, tf.origin.z) if Terrain.active else 0.0
				g_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, tf.origin + Vector3(0.0, gy + g_dy, 0.0)))
			var g_mmi := MultiMeshInstance3D.new()
			g_mmi.name = "ParkLampGlobes_%s" % key
			g_mmi.multimesh = g_mm
			g_mmi.visibility_range_end = 520.0
			g_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if Terrain.active:
				g_mmi.set_meta("on_terrain", true)
			holder.add_child(g_mmi)


static func _get_prop_mesh(key: String) -> Mesh:
	if _prop_cache.has(key):
		return _prop_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var iron := Color(0.14, 0.16, 0.17)
	var cedar := Color(0.56, 0.36, 0.20)
	var cedar_d := Color(0.46, 0.29, 0.16)

	match key:
		"bench":
			# Classic Seattle cast-iron & cedar slatted park bench (facing +Z)
			for sx: float in [-0.78, 0.78]:
				_box_into(st, Vector3(sx, 0.22, 0.18), Vector3(0.06, 0.44, 0.06), iron)
				_box_into(st, Vector3(sx, 0.42, -0.22), Vector3(0.06, 0.84, 0.06), iron)
				_box_into(st, Vector3(sx, 0.44, -0.02), Vector3(0.06, 0.05, 0.48), iron)
				_box_into(st, Vector3(sx, 0.62, 0.02), Vector3(0.06, 0.04, 0.46), iron) # armrest
				_box_into(st, Vector3(sx, 0.52, 0.22), Vector3(0.05, 0.20, 0.05), iron)
			# 3 beveled cedar seat slats + 2 curved backrest slats
			for k in range(3):
				_box_into(st, Vector3(0.0, 0.46, -0.10 + float(k) * 0.14), Vector3(1.86, 0.045, 0.11), cedar if k != 1 else cedar_d)
			for k in range(2):
				_box_into(st, Vector3(0.0, 0.68 + float(k) * 0.15, -0.23 - float(k) * 0.03), Vector3(1.86, 0.11, 0.04), cedar)
		"picnic":
			# Full cedar A-frame picnic table with attached dual benches
			for sx: float in [-0.72, 0.72]:
				_add_beam(st, Vector3(sx, 0.0, -0.58), Vector3(sx, 0.74, -0.18), 0.08, 0.08, cedar_d)
				_add_beam(st, Vector3(sx, 0.0, 0.58), Vector3(sx, 0.74, 0.18), 0.08, 0.08, cedar_d)
				_box_into(st, Vector3(sx, 0.42, 0.0), Vector3(0.07, 0.08, 1.56), cedar_d)
			for k in range(5):
				_box_into(st, Vector3(0.0, 0.76, -0.34 + float(k) * 0.17), Vector3(1.96, 0.05, 0.14), cedar)
			for sz: float in [-0.68, 0.68]:
				_box_into(st, Vector3(0.0, 0.46, sz), Vector3(1.96, 0.05, 0.28), cedar)
		"shrub":
			# Multi-lobed sculpted Pacific Northwest rhododendron / boxwood evergreen mound
			var lobes := [
				[Vector3(0.0, 0.48, 0.0), Vector3(0.95, 0.58, 0.92), Color(0.14, 0.30, 0.12)],
				[Vector3(0.55, 0.38, 0.32), Vector3(0.68, 0.46, 0.64), Color(0.18, 0.35, 0.14)],
				[Vector3(-0.52, 0.36, 0.38), Vector3(0.64, 0.44, 0.68), Color(0.16, 0.32, 0.13)],
				[Vector3(0.18, 0.42, -0.56), Vector3(0.72, 0.48, 0.62), Color(0.20, 0.38, 0.16)],
				[Vector3(-0.42, 0.34, -0.44), Vector3(0.58, 0.40, 0.58), Color(0.15, 0.31, 0.12)],
			]
			for lb in lobes:
				_add_faceted_blob(st, lb[0] as Vector3, lb[1] as Vector3, lb[2] as Color, 1.3)
		"flower_pink", "flower_blue", "flower_gold":
			# Stone-edged park flowerbed with lush soil, foliage base & vibrant blossom clusters!
			var bloom_a := Color(0.92, 0.34, 0.56)
			var bloom_b := Color(0.98, 0.66, 0.78)
			if key == "flower_blue":
				bloom_a = Color(0.32, 0.50, 0.88)
				bloom_b = Color(0.56, 0.44, 0.86)
			elif key == "flower_gold":
				bloom_a = Color(0.96, 0.72, 0.14)
				bloom_b = Color(0.92, 0.36, 0.16)
			_cyl_into(st, 1.38, 0.0, 0.22, 14, Color(0.62, 0.60, 0.56))
			_cyl_into(st, 1.22, 0.20, 0.26, 14, Color(0.24, 0.18, 0.12))
			for k in range(7):
				var a := TAU * float(k) / 7.0
				var r := 0.0 if k == 0 else 0.72
				var fp := Vector3(cos(a) * r, 0.42, sin(a) * r)
				_add_faceted_blob(st, fp, Vector3(0.42, 0.28, 0.42), Color(0.16, 0.34, 0.13), float(k) * 0.7)
				_add_faceted_blob(st, fp + Vector3(0.0, 0.22, 0.0), Vector3(0.28, 0.20, 0.28), bloom_a if k % 2 == 0 else bloom_b, float(k) * 1.1)
		"park_lamp":
			# Vintage Seattle dark-green cast-iron park pedestrian lamp post
			var pgreen := Color(0.12, 0.21, 0.17)
			_cyl_into(st, 0.22, 0.0, 0.55, 10, pgreen)
			_cyl_into(st, 0.11, 0.55, 1.20, 10, pgreen)
			_cyl_into(st, 0.075, 1.20, 3.45, 10, pgreen)
			_cyl_into(st, 0.24, 3.40, 3.50, 10, pgreen)
			_cyl_into(st, 0.26, 3.84, 3.94, 10, pgreen)
		"bollard_light":
			# Modern stainless & charcoal waterfront pathway bollard light
			_cyl_into(st, 0.11, 0.0, 0.84, 10, Color(0.20, 0.22, 0.25))
			_cyl_into(st, 0.12, 1.02, 1.10, 10, Color(0.20, 0.22, 0.25))
		"park_bin":
			_cyl_into(st, 0.28, 0.0, 0.88, 10, Color(0.13, 0.24, 0.17))
			_cyl_into(st, 0.31, 0.88, 0.98, 10, Color(0.18, 0.20, 0.20))

	st.generate_normals()
	var m := st.commit()
	_prop_cache[key] = m
	return m


# ---------------------------------------------------------------------------------------------
# 4. MULTI-SPECIES HIGH-DETAIL SCULPTED 3D TREES (6 SPECIES + CHUNKED MULTIMESH + FAR LOD)
# ---------------------------------------------------------------------------------------------
# Species IDs:
#   0 = PNW Douglas Fir / Western Red Cedar (conifer, iconic Seattle evergreen)
#   1 = Pacific Bigleaf Maple / Park Oak (grand spreading broadleaf with visible multi-fork branches)
#   2 = Seattle Ornamental Cherry Blossom (sakura pink / blush white blossoms)
#   3 = Twin-Stem Silver Birch (white charcoal-banded bark + airy bright spring foliage)
#   4 = Autumn Golden Ginkgo / Scarlet Maple (warm amber & crimson broadleaf accent)
#   5 = Lakeside Weeping Willow (cascading emerald willow curtains near Lake Union & ponds)
static func _build_multi_species_trees(
	parent: Node3D,
	raw_trees: Array,
	extra_park_trees: Array,
	clear: Dictionary,
	path_segs: Array,
	plaza_circles: Array
) -> void:
	var holder := Node3D.new()
	holder.name = "MultiSpeciesTrees"
	parent.add_child(holder)

	# Collect unified tree records: {pos: Vector2, species: int, scale: float, yaw: float, is_street: bool, tint: Color}
	var all_trees: Array = []
	var occupied := {} # 4.5m spatial hash so newly generated park trees don't stack on top of OSM trees

	for i in range(raw_trees.size()):
		var tx := float(raw_trees[i][0])
		var tz := float(raw_trees[i][1])
		var p2 := Vector2(tx, tz)
		if _inside_any_water(clear, p2):
			continue
		var in_park := _inside_any_park(clear, p2)
		if in_park and _near_any_path_or_plaza(p2, path_segs, plaza_circles, 1.5):
			continue
		var sp := 1
		var sc := 0.82 + 0.36 * float((i * 37) % 11) / 10.0
		if in_park:
			var r := _hash01(tx, tz, 71.0)
			if r < 0.32:
				sp = 0 # Douglas Fir
				sc *= 1.12
			elif r < 0.58:
				sp = 1 # Bigleaf Maple
			elif r < 0.74:
				sp = 2 # Cherry Blossom
			elif r < 0.88:
				sp = 3 # Silver Birch
			else:
				sp = 4 # Autumn Maple / Ginkgo
		else:
			# Sidewalk street trees: well-proportioned Maple, Birch, Cherry & Ginkgo accents
			var r := _hash01(tx, tz, 73.0)
			if r < 0.52:
				sp = 1
			elif r < 0.74:
				sp = 3
			elif r < 0.88:
				sp = 2
			else:
				sp = 4
		var yaw := _hash01(tx, tz, 79.0) * TAU
		var tint := _tree_tint(sp, _hash01(tx, tz, 83.0))
		all_trees.append({"pos": p2, "species": sp, "scale": sc, "yaw": yaw, "is_street": not in_park, "tint": tint})
		var ok := Vector2i(int(floor(tx / 4.8)), int(floor(tz / 4.8)))
		occupied[ok] = true

	for et: Dictionary in extra_park_trees:
		var p2: Vector2 = et["pos"]
		var ok := Vector2i(int(floor(p2.x / 4.8)), int(floor(p2.y / 4.8)))
		if occupied.has(ok):
			continue
		occupied[ok] = true
		var sp := int(et["species"])
		var sc := float(et["scale"])
		var yaw := _hash01(p2.x, p2.y, 89.0) * TAU
		var tint := _tree_tint(sp, _hash01(p2.x, p2.y, 97.0))
		all_trees.append({"pos": p2, "species": sp, "scale": sc, "yaw": yaw, "is_street": false, "tint": tint})

	if all_trees.is_empty():
		return

	# Shared materials
	var bark_mat := StandardMaterial3D.new()
	bark_mat.vertex_color_use_as_albedo = true
	bark_mat.roughness = 0.90
	bark_mat.metallic = 0.0
	bark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var foliage_mat := ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader") as Shader

	var pit_box := BoxMesh.new()
	pit_box.size = Vector3(1.52, 0.04, 1.52)
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.16, 0.15, 0.14)
	pit_mat.roughness = 0.68
	pit_mat.metallic = 0.52
	pit_box.material = pit_mat

	# Far LOD simple species silhouettes (conifer cone vs broadleaf sphere)
	var far_broad := SphereMesh.new()
	far_broad.radius = 2.6
	far_broad.height = 4.2
	far_broad.radial_segments = 8
	far_broad.rings = 4
	far_broad.material = foliage_mat

	var far_conifer := CylinderMesh.new()
	far_conifer.top_radius = 0.15
	far_conifer.bottom_radius = 2.5
	far_conifer.height = 9.2
	far_conifer.radial_segments = 8
	far_conifer.material = foliage_mat

	# Group trees into 160m spatial chunks
	var chunks := {}
	for tr_d in all_trees:
		var p2: Vector2 = tr_d["pos"]
		var ck := Vector2i(int(floor(p2.x / TREE_CHUNK)), int(floor(p2.y / TREE_CHUNK)))
		if not chunks.has(ck):
			chunks[ck] = []
		(chunks[ck] as Array).append(tr_d)

	for ck: Vector2i in chunks.keys():
		var c_list: Array = chunks[ck]
		var chunk_node := Node3D.new()
		chunk_node.name = "TreeChunk_%d_%d" % [ck.x, ck.y]
		if Terrain.active:
			chunk_node.set_meta("on_terrain", true)
		holder.add_child(chunk_node)

		var by_sp := [[], [], [], [], [], []]
		var street_pits: Array[Transform3D] = []
		var far_broad_list: Array = []
		var far_conifer_list: Array = []

		for tr_d in c_list:
			var sp := clampi(int(tr_d["species"]), 0, 5)
			(by_sp[sp] as Array).append(tr_d)
			var p2: Vector2 = tr_d["pos"]
			var sc := float(tr_d["scale"])
			var yaw := float(tr_d["yaw"])
			var y_terr := Terrain.surface(p2.x, p2.y) if Terrain.active else 0.0
			tr_d["y_terr"] = y_terr
			if bool(tr_d["is_street"]):
				street_pits.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p2.x, 0.205 + y_terr, p2.y)))
			if sp == 0:
				far_conifer_list.append([Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(p2.x, 5.5 * sc + y_terr, p2.y)), tr_d["tint"]])
			else:
				far_broad_list.append([Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(p2.x, 4.4 * sc + y_terr, p2.y)), tr_d["tint"]])

		# Sidewalk cast-iron grates ONLY for street trees (never inside parks!)
		if not street_pits.is_empty():
			var pmm := MultiMesh.new()
			pmm.transform_format = MultiMesh.TRANSFORM_3D
			pmm.mesh = pit_box
			pmm.instance_count = street_pits.size()
			for k in range(street_pits.size()):
				pmm.set_instance_transform(k, street_pits[k])
			var pmmi := MultiMeshInstance3D.new()
			pmmi.name = "TreePits"
			pmmi.multimesh = pmm
			pmmi.set_meta("base_tfs", street_pits)
			pmmi.visibility_range_end = 260.0
			pmmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk_node.add_child(pmmi)

		# Emit detailed 2-part MultiMesh (wood + foliage) per species present in this chunk
		for sp in range(6):
			var sp_list: Array = by_sp[sp]
			if sp_list.is_empty():
				continue
			var pair := _get_species_meshes(sp)
			var wood_m: Mesh = pair["wood"]
			var leaf_m: Mesh = pair["leaf"]

			var w_mm := MultiMesh.new()
			w_mm.transform_format = MultiMesh.TRANSFORM_3D
			w_mm.mesh = wood_m
			w_mm.instance_count = sp_list.size()

			var l_mm := MultiMesh.new()
			l_mm.transform_format = MultiMesh.TRANSFORM_3D
			l_mm.use_colors = true
			l_mm.mesh = leaf_m
			l_mm.instance_count = sp_list.size()

			var sp_tfs: Array[Transform3D] = []
			for k in range(sp_list.size()):
				var tr_d: Dictionary = sp_list[k]
				var p2: Vector2 = tr_d["pos"]
				var sc := float(tr_d["scale"])
				var yaw := float(tr_d["yaw"])
				var y_base := (0.20 if bool(tr_d["is_street"]) else 0.02) + float(tr_d.get("y_terr", 0.0))
				var tf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(p2.x, y_base, p2.y))
				w_mm.set_instance_transform(k, tf)
				l_mm.set_instance_transform(k, tf)
				l_mm.set_instance_color(k, tr_d["tint"] as Color)
				sp_tfs.append(tf)

			var w_mmi := MultiMeshInstance3D.new()
			w_mmi.name = "TreeWood_S%d" % sp
			w_mmi.multimesh = w_mm
			w_mmi.set_meta("base_tfs", sp_tfs)
			w_mmi.material_override = bark_mat
			w_mmi.visibility_range_end = 360.0
			# Crown casts full canopy shadow onto the ground; skipping interior trunk shadow cuts tree shadow pass in half!
			w_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk_node.add_child(w_mmi)

			var l_mmi := MultiMeshInstance3D.new()
			l_mmi.name = "TreeLeaf_S%d" % sp
			l_mmi.multimesh = l_mm
			l_mmi.set_meta("base_tfs", sp_tfs)
			l_mmi.material_override = foliage_mat
			l_mmi.visibility_range_end = 360.0
			l_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			chunk_node.add_child(l_mmi)

		# Far LOD instances (beyond 350m)
		if not far_broad_list.is_empty():
			var fb_mm := MultiMesh.new()
			fb_mm.transform_format = MultiMesh.TRANSFORM_3D
			fb_mm.use_colors = true
			fb_mm.mesh = far_broad
			fb_mm.instance_count = far_broad_list.size()
			var fb_tfs: Array[Transform3D] = []
			for k in range(far_broad_list.size()):
				var fbtf: Transform3D = far_broad_list[k][0]
				fb_mm.set_instance_transform(k, fbtf)
				fb_mm.set_instance_color(k, far_broad_list[k][1])
				fb_tfs.append(fbtf)
			var fb_mmi := MultiMeshInstance3D.new()
			fb_mmi.name = "FarBroadleaf"
			fb_mmi.multimesh = fb_mm
			fb_mmi.set_meta("base_tfs", fb_tfs)
			fb_mmi.visibility_range_begin = 350.0
			fb_mmi.visibility_range_end = 2200.0
			fb_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk_node.add_child(fb_mmi)

		if not far_conifer_list.is_empty():
			var fc_mm := MultiMesh.new()
			fc_mm.transform_format = MultiMesh.TRANSFORM_3D
			fc_mm.use_colors = true
			fc_mm.mesh = far_conifer
			fc_mm.instance_count = far_conifer_list.size()
			var fc_tfs: Array[Transform3D] = []
			for k in range(far_conifer_list.size()):
				var fctf: Transform3D = far_conifer_list[k][0]
				fc_mm.set_instance_transform(k, fctf)
				fc_mm.set_instance_color(k, far_conifer_list[k][1])
				fc_tfs.append(fctf)
			var fc_mmi := MultiMeshInstance3D.new()
			fc_mmi.name = "FarConifer"
			fc_mmi.multimesh = fc_mm
			fc_mmi.set_meta("base_tfs", fc_tfs)
			fc_mmi.visibility_range_begin = 350.0
			fc_mmi.visibility_range_end = 2200.0
			fc_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk_node.add_child(fc_mmi)


static func _tree_tint(sp: int, rnd: float) -> Color:
	match sp:
		0: # Douglas Fir / Western Red Cedar: deep Pacific Northwest pine-emerald
			return Color(0.11, 0.25, 0.13).lerp(Color(0.17, 0.34, 0.17), rnd)
		1: # Pacific Bigleaf Maple / Oak: lush rich green
			return Color(0.18, 0.36, 0.14).lerp(Color(0.28, 0.44, 0.18), rnd)
		2: # Seattle Ornamental Cherry Blossom: soft sakura pink & blush white!
			return Color(0.95, 0.68, 0.78).lerp(Color(0.98, 0.85, 0.90), rnd)
		3: # Silver Birch: luminous fresh spring green
			return Color(0.32, 0.50, 0.20).lerp(Color(0.46, 0.58, 0.24), rnd)
		4: # Autumn Golden Ginkgo / Scarlet Maple
			return Color(0.76, 0.52, 0.14) if rnd < 0.55 else Color(0.66, 0.24, 0.14)
		_: # Lakeside Weeping Willow: bright airy willow green
			return Color(0.24, 0.44, 0.18).lerp(Color(0.34, 0.52, 0.22), rnd)


static func _get_species_meshes(sp: int) -> Dictionary:
	if _species_cache.has(sp):
		return _species_cache[sp]
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lst := SurfaceTool.new()
	lst.begin(Mesh.PRIMITIVE_TRIANGLES)

	match sp:
		0: # PNW DOUGLAS FIR / WESTERN RED CEDAR (Majestic layered conifer!)
			var bark := Color(0.26, 0.17, 0.11)
			var bark_d := Color(0.19, 0.12, 0.08)
			_taper_cyl(wst, 0.34, 0.22, 0.0, 2.2, 8, bark_d, Vector3.ZERO)
			_taper_cyl(wst, 0.22, 0.05, 2.2, 10.6, 8, bark, Vector3.ZERO)
			# Flared root buttresses
			for k in range(4):
				var a := float(k) * PI * 0.5 + 0.3
				_add_beam(wst, Vector3(cos(a) * 0.48, 0.0, sin(a) * 0.48), Vector3(cos(a) * 0.12, 0.95, sin(a) * 0.12), 0.14, 0.14, bark_d)
			# 8 cascading fluted evergreen bough tiers (drooping star-skirt silhouette!)
			var tiers := 8
			for t in range(tiers):
				var f := float(t) / float(tiers - 1)
				var y_top := lerpf(3.2, 11.4, f)
				var y_bot := y_top - lerpf(1.75, 0.95, f)
				var r_outer := lerpf(2.55, 0.55, pow(f, 0.88))
				var rot := float(t) * 0.68
				_add_evergreen_tier(lst, y_bot, y_top, r_outer, 9, rot, Color(0.86, 0.94, 0.86).lerp(Color(1.0, 1.0, 1.0), f))
		1: # PACIFIC BIGLEAF MAPLE / PARK OAK (Buttressed trunk + 4 boughs + 8 sub-branches + 14 faceted leaf pads!)
			var bark := Color(0.28, 0.22, 0.17)
			var bark_d := Color(0.20, 0.16, 0.12)
			_taper_cyl(wst, 0.32, 0.20, 0.0, 2.8, 9, bark, Vector3.ZERO)
			for k in range(4):
				var a := float(k) * PI * 0.5 + 0.2
				_add_beam(wst, Vector3(cos(a) * 0.42, 0.0, sin(a) * 0.42), Vector3(cos(a) * 0.14, 0.72, sin(a) * 0.14), 0.13, 0.13, bark_d)
			var bough_tips: Array[Vector3] = []
			for k in range(4):
				var a := float(k) * PI * 0.5 + 0.45
				var p0 := Vector3(0.0, 2.45, 0.0)
				var p1 := Vector3(cos(a) * 1.45, 4.35 + (k % 2) * 0.35, sin(a) * 1.45)
				_add_taper_branch(wst, p0, p1, 0.13, 0.065, bark)
				bough_tips.append(p1)
				# 2 secondary forked twigs per primary bough
				for sgn: float in [-1.0, 1.0]:
					var a2 := a + sgn * 0.55
					var p2 := p1 + Vector3(cos(a2) * 1.05, 0.95, sin(a2) * 1.05)
					_add_taper_branch(wst, p1, p2, 0.06, 0.028, bark_d)
					bough_tips.append(p2)
			# 14 sculpted irregular organic foliage clusters forming a rich cathedral crown
			_add_faceted_blob(lst, Vector3(0.0, 6.45, 0.0), Vector3(1.85, 1.25, 1.85), Color.WHITE, 1.0)
			_add_faceted_blob(lst, Vector3(0.55, 5.95, -0.45), Vector3(1.55, 1.10, 1.50), Color.WHITE, 2.0)
			for idx in range(bough_tips.size()):
				var tip := bough_tips[idx]
				var sc_v := Vector3(1.32, 0.92, 1.28) if idx % 3 == 0 else Vector3(1.12, 0.84, 1.15)
				_add_faceted_blob(lst, tip + Vector3(0.0, 0.55, 0.0), sc_v, Color.WHITE, float(idx) * 1.7 + 3.0)
		2: # SEATTLE ORNAMENTAL CHERRY BLOSSOM (Graceful dark reddish-brown spreading trunk + layered sakura clouds!)
			var bark := Color(0.24, 0.13, 0.11)
			_taper_cyl(wst, 0.24, 0.15, 0.0, 2.1, 8, bark, Vector3.ZERO)
			var tips: Array[Vector3] = []
			for k in range(5):
				var a := TAU * float(k) / 5.0 + 0.25
				var p1 := Vector3(cos(a) * 1.35, 3.65 + (k % 2) * 0.3, sin(a) * 1.35)
				_add_taper_branch(wst, Vector3(0.0, 1.85, 0.0), p1, 0.10, 0.045, bark)
				tips.append(p1)
				var p2 := p1 + Vector3(cos(a + 0.35) * 0.95, 0.78, sin(a + 0.35) * 0.95)
				_add_taper_branch(wst, p1, p2, 0.045, 0.022, bark)
				tips.append(p2)
			_add_faceted_blob(lst, Vector3(0.0, 5.15, 0.0), Vector3(1.75, 1.05, 1.75), Color.WHITE, 4.0)
			_add_faceted_blob(lst, Vector3(-0.3, 4.8, 0.3), Vector3(1.45, 0.95, 1.45), Color.WHITE, 5.0)
			for idx in range(tips.size()):
				_add_faceted_blob(lst, tips[idx] + Vector3(0.0, 0.42, 0.0), Vector3(1.18, 0.74, 1.18), Color.WHITE, float(idx) * 1.3 + 6.0)
		3: # TWIN-STEM SILVER BIRCH (Distinctive white bark with dark charcoal rings + airy upright crown!)
			var wbark := Color(0.86, 0.84, 0.80)
			var dband := Color(0.20, 0.19, 0.18)
			for stem in range(2):
				var sx := -0.22 if stem == 0 else 0.24
				var sz := -0.10 if stem == 0 else 0.16
				var top_x := sx * 2.4
				var top_z := sz * 2.4
				var h_st := 6.6 if stem == 0 else 5.8
				_add_taper_branch(wst, Vector3(sx, 0.0, sz), Vector3(top_x, h_st, top_z), 0.12, 0.04, wbark)
				# Charcoal horizontal birch bark bands
				for b in range(5):
					var by := 0.8 + float(b) * 1.05
					var f := by / h_st
					_cyl_into(wst, lerpf(0.115, 0.055, f), by, by + 0.12, 7, dband, Vector3(lerpf(sx, top_x, f), 0.0, lerpf(sz, top_z, f)))
				for k in range(3):
					var a := float(k) * 2.1 + float(stem) * 1.2
					var base_p := Vector3(lerpf(sx, top_x, 0.55), h_st * 0.55, lerpf(sz, top_z, 0.55))
					var tip_p := base_p + Vector3(cos(a) * 1.05, 1.45, sin(a) * 1.05)
					_add_taper_branch(wst, base_p, tip_p, 0.045, 0.02, wbark)
					_add_faceted_blob(lst, tip_p + Vector3(0.0, 0.35, 0.0), Vector3(1.05, 1.15, 1.05), Color.WHITE, float(k + stem * 4) * 1.9)
			_add_faceted_blob(lst, Vector3(-0.35, 7.2, -0.15), Vector3(1.25, 1.35, 1.25), Color.WHITE, 9.0)
			_add_faceted_blob(lst, Vector3(0.45, 6.4, 0.25), Vector3(1.18, 1.25, 1.18), Color.WHITE, 10.0)
			_add_faceted_blob(lst, Vector3(0.0, 5.2, 0.0), Vector3(1.45, 1.15, 1.45), Color.WHITE, 11.0)
		4: # AUTUMN GOLDEN GINKGO / SCARLET MAPLE (Sculpted broadleaf seasonal centerpiece)
			var bark := Color(0.25, 0.20, 0.16)
			_taper_cyl(wst, 0.26, 0.15, 0.0, 2.7, 8, bark, Vector3.ZERO)
			for k in range(4):
				var a := float(k) * PI * 0.5 + 0.15
				var p1 := Vector3(cos(a) * 1.35, 4.35, sin(a) * 1.35)
				_add_taper_branch(wst, Vector3(0.0, 2.35, 0.0), p1, 0.11, 0.05, bark)
				_add_faceted_blob(lst, p1 + Vector3(0.0, 0.55, 0.0), Vector3(1.38, 1.05, 1.35), Color.WHITE, float(k) * 2.1)
				var p2 := p1 + Vector3(cos(a + 0.5) * 0.9, 1.0, sin(a + 0.5) * 0.9)
				_add_faceted_blob(lst, p2 + Vector3(0.0, 0.4, 0.0), Vector3(1.15, 0.95, 1.15), Color.WHITE, float(k) * 2.1 + 7.0)
			_add_faceted_blob(lst, Vector3(0.0, 6.3, 0.0), Vector3(1.70, 1.35, 1.65), Color.WHITE, 13.0)
			_add_faceted_blob(lst, Vector3(0.0, 4.8, 0.0), Vector3(1.55, 1.05, 1.55), Color.WHITE, 14.0)
		_: # LAKESIDE WEEPING WILLOW (Gnarled leaning trunk + overarching boughs + 14 drooping willow curtains!)
			var bark := Color(0.26, 0.21, 0.15)
			_add_taper_branch(wst, Vector3(0.0, 0.0, 0.0), Vector3(0.35, 2.8, 0.15), 0.34, 0.20, bark)
			for k in range(5):
				var a := TAU * float(k) / 5.0
				var p1 := Vector3(0.35 + cos(a) * 1.85, 4.65, 0.15 + sin(a) * 1.85)
				_add_taper_branch(wst, Vector3(0.35, 2.65, 0.15), p1, 0.12, 0.05, bark)
				_add_faceted_blob(lst, p1 + Vector3(0.0, 0.4, 0.0), Vector3(1.45, 0.95, 1.45), Color.WHITE, float(k) * 1.5)
			_add_faceted_blob(lst, Vector3(0.35, 5.95, 0.15), Vector3(2.15, 1.25, 2.15), Color.WHITE, 20.0)
			# 14 cascading drooping willow-curtain fronds draping gracefully down toward the shore!
			for k in range(14):
				var a := TAU * float(k) / 14.0
				var r := 1.85 + (k % 2) * 0.55
				var top_p := Vector3(0.35 + cos(a) * r, 4.75, 0.15 + sin(a) * r)
				var len_d := 2.6 + float(k % 3) * 0.45
				_taper_cyl(lst, 0.22, 0.46, top_p.y - len_d, top_p.y, 6, Color.WHITE, Vector3(top_p.x, 0.0, top_p.z))

	wst.generate_normals()
	lst.generate_normals()
	var res := {"wood": wst.commit(), "leaf": lst.commit()}
	_species_cache[sp] = res
	return res


# ---------------------------------------------------------------------------------------------
# Geometry & SurfaceTool Primitives
# ---------------------------------------------------------------------------------------------
static func _add_evergreen_tier(
	st: SurfaceTool,
	y_bot: float,
	y_top: float,
	r_outer: float,
	lobes: int,
	rot: float,
	col: Color
) -> void:
	var apex := Vector3(0.0, y_top, 0.0)
	var base_c := Vector3(0.0, y_bot + 0.22, 0.0)
	var pts_n := lobes * 2
	var ring: Array[Vector3] = []
	for i in range(pts_n):
		var a := rot + TAU * float(i) / float(pts_n)
		var is_tip := (i % 2 == 0)
		var r := r_outer if is_tip else (r_outer * 0.64)
		var y := (y_bot - 0.12) if is_tip else (y_bot + 0.18)
		ring.append(Vector3(cos(a) * r, y, sin(a) * r))
	for i in range(pts_n):
		var j := (i + 1) % pts_n
		# Outer upper skirt (outward CW viewed from outside)
		_add_vc_tri(st, apex, ring[j], ring[i], col)
		# Dark shaded underside skirt
		_add_vc_tri(st, base_c, ring[i], ring[j], col.darkened(0.28))


static func _add_faceted_blob(st: SurfaceTool, center: Vector3, radii: Vector3, col: Color, seed_v: float) -> void:
	# Organic perturbed geodesic-like foliage cluster (3 rings x 8 segments, bumpy natural silhouette)
	var segs := 8
	var rings := 4
	var grid: Array = []
	for r in range(rings + 1):
		var phi := PI * float(r) / float(rings)
		var row: Array[Vector3] = []
		for s in range(segs):
			var th := TAU * float(s) / float(segs)
			var dir := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var bump := 0.86 + 0.28 * _hash01(dir.x * 5.0 + seed_v, dir.z * 5.0 + dir.y * 3.0, seed_v)
			row.append(center + Vector3(dir.x * radii.x, dir.y * radii.y, dir.z * radii.z) * bump)
		grid.append(row)
	for r in range(rings):
		var r0: Array = grid[r]
		var r1: Array = grid[r + 1]
		for s in range(segs):
			var s1 := (s + 1) % segs
			var shade := col.darkened(0.14 * float(r) / float(rings))
			_add_vc_tri(st, r0[s] as Vector3, r0[s1] as Vector3, r1[s1] as Vector3, shade)
			_add_vc_tri(st, r0[s] as Vector3, r1[s1] as Vector3, r1[s] as Vector3, shade)


static func _add_taper_branch(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float, col: Color) -> void:
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.05:
		return
	var up := axis / length
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.85 else Vector3.FORWARD
	var u := up.cross(ref).normalized()
	var v := up.cross(u).normalized()
	var segs := 6
	for k in range(segs):
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		_add_vc_quad(st, p0 + d0 * r0, p0 + d1 * r0, p1 + d1 * r1, p1 + d0 * r1, col)


static func _taper_cyl(
	st: SurfaceTool,
	r_bot: float,
	r_top: float,
	y0: float,
	y1: float,
	segs: int,
	col: Color,
	off: Vector3 = Vector3.ZERO
) -> void:
	for k in range(segs):
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var c0 := cos(a0); var s0 := sin(a0)
		var c1 := cos(a1); var s1 := sin(a1)
		var b0 := off + Vector3(c0 * r_bot, y0, s0 * r_bot)
		var b1 := off + Vector3(c1 * r_bot, y0, s1 * r_bot)
		var t0 := off + Vector3(c0 * r_top, y1, s0 * r_top)
		var t1 := off + Vector3(c1 * r_top, y1, s1 * r_top)
		_add_vc_quad(st, b0, b1, t1, t0, col)


static func _cyl_into(
	st: SurfaceTool,
	r: float,
	y0: float,
	y1: float,
	segs: int,
	col: Color,
	off: Vector3 = Vector3.ZERO
) -> void:
	_taper_cyl(st, r, r, y0, y1, segs, col, off)
	var top_c := off + Vector3(0.0, y1, 0.0)
	for k in range(segs):
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		_add_vc_tri(st, top_c, off + Vector3(cos(a1) * r, y1, sin(a1) * r), off + Vector3(cos(a0) * r, y1, sin(a0) * r), col.lightened(0.04))


static func _add_strip_prism(
	st: SurfaceTool,
	a: Vector2,
	b: Vector2,
	n: Vector2,
	off0: float,
	off1: float,
	y0: float,
	y1: float,
	col: Color
) -> void:
	var a0 := a + n * off0
	var a1 := a + n * off1
	var b0 := b + n * off0
	var b1 := b + n * off1
	# Top
	_add_vc_quad(st, Vector3(a0.x, y1, a0.y), Vector3(b0.x, y1, b0.y), Vector3(b1.x, y1, b1.y), Vector3(a1.x, y1, a1.y), col)
	# Both vertical sides
	var side_c := col.darkened(0.14)
	_add_vc_quad(st, Vector3(a0.x, y0, a0.y), Vector3(b0.x, y0, b0.y), Vector3(b0.x, y1, b0.y), Vector3(a0.x, y1, a0.y), side_c)
	_add_vc_quad(st, Vector3(b1.x, y0, b1.y), Vector3(a1.x, y0, a1.y), Vector3(a1.x, y1, a1.y), Vector3(b1.x, y1, b1.y), side_c)


static func _add_slope_quad(
	st: SurfaceTool,
	a0: Vector2,
	b0: Vector2,
	y0: float,
	a1: Vector2,
	b1: Vector2,
	y1: float,
	col: Color
) -> void:
	_add_vc_quad(st, Vector3(a0.x, y0, a0.y), Vector3(b0.x, y0, b0.y), Vector3(b1.x, y1, b1.y), Vector3(a1.x, y1, a1.y), col)


static func _add_beam(st: SurfaceTool, p0: Vector3, p1: Vector3, w: float, h: float, col: Color) -> void:
	var d := p1 - p0
	var length := d.length()
	if length < 0.02:
		return
	var mid := (p0 + p1) * 0.5
	var fwd := d / length
	var ref := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var right := fwd.cross(ref).normalized()
	var up := right.cross(fwd).normalized()
	var xf := Transform3D(Basis(right, up, fwd), mid)
	_box_xf(st, xf, Vector3.ZERO, Vector3(w, h, length), col)


static func _box_into(st: SurfaceTool, c: Vector3, sz: Vector3, col: Color) -> void:
	_box_xf(st, Transform3D.IDENTITY, c, sz, col)


static func _box_xf(st: SurfaceTool, xf: Transform3D, c: Vector3, sz: Vector3, col: Color) -> void:
	var h := sz * 0.5
	var faces := [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
		[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
	]
	for f: Array in faces:
		var v0 := xf * (c + (f[0] as Vector3) * h)
		var v1 := xf * (c + (f[1] as Vector3) * h)
		var v2 := xf * (c + (f[2] as Vector3) * h)
		var v3 := xf * (c + (f[3] as Vector3) * h)
		_add_vc_quad(st, v0, v1, v2, v3, col)


static func _add_vc_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, col: Color) -> void:
	_add_vc_tri(st, v0, v1, v2, col)
	_add_vc_tri(st, v0, v2, v3, col)


static func _add_vc_tri(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, col: Color) -> void:
	st.set_color(col); st.add_vertex(v0)
	st.set_color(col); st.add_vertex(v1)
	st.set_color(col); st.add_vertex(v2)


static func _commit_vc_mesh(parent: Node3D, node_name: String, st: SurfaceTool, rough: float, metal: float, cast_sh: bool) -> void:
	st.generate_normals()
	var arr := st.commit_to_arrays()
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
		return
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	if Terrain.active:
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for v: Vector3 in verts:
			if v.x < mn.x: mn.x = v.x
			if v.x > mx.x: mx.x = v.x
			if v.z < mn.y: mn.y = v.z
			if v.z > mx.y: mx.y = v.z
		if maxf(mx.x - mn.x, mx.y - mn.y) <= Terrain._rigid_max:
			var lo := minf(
				minf(Terrain.surface(mn.x, mn.y), Terrain.surface(mx.x, mn.y)),
				minf(Terrain.surface(mn.x, mx.y), Terrain.surface(mx.x, mx.y))
			)
			var mid := (mn + mx) * 0.5
			mi.position.y += minf(lo, Terrain.surface(mid.x, mid.y))
		else:
			arr[Mesh.ARRAY_VERTEX] = Terrain._lift_verts(verts)
		mi.set_meta("on_terrain", true)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = rough
	mat.metallic = metal
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
