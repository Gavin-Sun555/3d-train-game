class_name CityBuilder
extends RefCounted

static var _curb_mat_cache: StandardMaterial3D = null
static var _sidewalk_mat_cache: ShaderMaterial = null


static func build_city(
	parent: Node3D,
	map_data: Dictionary,
	building_mat: ShaderMaterial,
	road_mat: ShaderMaterial,
	sidewalk_mat: ShaderMaterial,
	globe_mat: StandardMaterial3D
) -> Dictionary:
	var bounds: Array = map_data.get("bounds", [-280.0, -320.0, 280.0, 320.0])
	var cx: float = (float(bounds[0]) + float(bounds[2])) * 0.5
	var cz: float = (float(bounds[1]) + float(bounds[3])) * 0.5
	var span_x: float = float(bounds[2]) - float(bounds[0])
	var span_z: float = float(bounds[3]) - float(bounds[1])
	var pad_margin: float = 2400.0 if maxf(span_x, span_z) > 2000.0 else 620.0
	var sx: float = span_x + pad_margin
	var sz: float = span_z + pad_margin

	# 1. Brushed expansion-joint concrete sidewalk ground slab (the real terrain where there is DEM elevation data)
	var use_dem_ground := Terrain.has_dem()
	if use_dem_ground:
		Terrain.build_ground(parent, bounds, sidewalk_mat)
	var ground_mi := MeshInstance3D.new()
	ground_mi.name = "UrbanSidewalkBase"
	var g_mesh := PlaneMesh.new()
	g_mesh.size = Vector2(sx, sz)
	# Subdivide the base ground slab so its vertex depth-push stays locally accurate at close zoom
	# (a 4-vertex 6km plane pushes its corners negligibly in Y and would otherwise slice above lakes when zoomed in)
	g_mesh.subdivide_width = clampi(int(ceil(sx / 65.0)), 16, 112)
	g_mesh.subdivide_depth = clampi(int(ceil(sz / 65.0)), 16, 112)
	ground_mi.mesh = g_mesh
	ground_mi.position = Vector3(cx, -0.01, cz)
	ground_mi.material_override = sidewalk_mat
	ground_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not use_dem_ground:
		ground_mi.set_meta("on_terrain", true)
		parent.add_child(ground_mi)
	else:
		ground_mi.free()

	# Big maps (Seattle v4): only the core is built here; the outer map streams in as CityTiles
	var full_data := map_data
	map_data = CityTiles.core_subset(map_data)

	# 2. Plazas, brick squares, parks & water: water for the whole map (flat sheets), the rest for the core;
	#    the outer map's lawns / plazas are filled in by their tiles
	_build_areas(parent, map_data.get("fill_areas", full_data.get("areas", [])))

	# 3. Realistic weathered asphalt streets, 3D granite curbs, lane dashes & crosswalks
	_build_roads_and_curbs(parent, map_data.get("roads", []), map_data.get("crosswalks", []), road_mat)

	# 3a. Freeways (I-5, SR-520, Aurora Bridge ...) and the structure under street bridges
	FreewayBuilder.build(parent, map_data.get("freeways", []), road_mat, map_data.get("roads", []))
	FreewayBuilder.build_street_bridges(parent, map_data.get("roads", []))

	var is_zh := str(map_data.get("key", "")) == "jiaxing" or str(map_data.get("name", "")).contains("嘉兴")
	if building_mat != null:
		building_mat.set_shader_parameter("chinese_style", 1.0 if is_zh else 0.0)

	# 4. 3D architectural buildings (podium setbacks + 3D piers/cornices + interior parallax walls)
	_build_buildings(parent, map_data.get("buildings", []), building_mat)

	# 4a. Landmark facade details (Nordstrom, Westlake Center, Pacific Place, terracotta towers)
	LandmarkFacades.build_details(parent, map_data.get("buildings", []), map_data.get("roads", []))

	# 4b. Real OSM storefronts on street-facing ground floors (names, brand colours, lit interiors)
	var shop_mat := StorefrontBuilder.build_storefronts(parent, map_data.get("storefronts", []), map_data.get("buildings", []))

	# 5. Custom Westlake Landmarks (pass road polylines so Monorail piers NEVER land on roads or curved tracks!)
	var lm_info := LandmarksBuilder.build_landmarks(
		parent,
		map_data.get("landmarks", {}),
		building_mat,
		map_data.get("roads", [])
	)

	lm_info["night_mats"] = [shop_mat] if shop_mat != null else []
	# Seattle Center (Space Needle, Climate Pledge Arena, MoPOP...) and Elliott Bay waterfront landmarks
	if map_data.get("landmarks", {}).has("space_needle"):
		SeattleV2Landmarks.build(parent, map_data, lm_info["lights"])
	if map_data.get("landmarks", {}).has("jiaxing_south_station"):
		JiaxingLandmarks.build(parent, map_data, lm_info["lights"])
	if parent.has_meta("water_mat"):
		(lm_info["night_mats"] as Array).append(parent.get_meta("water_mat"))
	LandmarkFacades.build_plazas(parent, map_data.get("plazas", []), lm_info["lights"])

	# 6. Vintage Seattle streetlamps (with real warm night light pools)
	var lamp_lights := _build_streetlamps(parent, map_data.get("streetlamps", []), globe_mat)
	RoadSignBuilder.build(parent, map_data.get("road_signs", []))
	for ll in lamp_lights:
		lm_info["lights"].append(ll)

	# 7. High-detail Seattle parks, Lake Union waterfront, and multi-species sculpted 3D trees!
	var park_data := map_data
	if map_data.has("park_areas"):
		park_data = map_data.duplicate(false)
		park_data["areas"] = map_data["park_areas"]
	ParkLandscapeBuilder.build_all_parks_and_trees(parent, park_data, lm_info["lights"], globe_mat)

	# 8. Real terrain: put everything built above on the ground (buildings / water already placed)
	Terrain.drape_subtree(parent)
	return lm_info


# Player edits / track grading: rebuild core non-water area fills (parks, plazas, brick squares) on current terrain
static func rebuild_area_layer(parent: Node3D, areas: Array) -> void:
	for nm: String in ["ParkAreas", "PlazaAreas", "BrickPlazas"]:
		var old := parent.get_node_or_null(nm)
		if old != null:
			parent.remove_child(old)
			old.queue_free()
	var non_water: Array = []
	for a in areas:
		if str((a as Dictionary).get("kind", "")) not in ["water", "island"]:
			non_water.append(a)
	if not non_water.is_empty():
		_build_areas(parent, non_water)


# Player edits: rebuild only the street surface (asphalt, markings, kerbs, sidewalks, furniture)
static func rebuild_road_layer(parent: Node3D, roads: Array, crosswalks: Array, road_mat: ShaderMaterial) -> void:
	for nm: String in ["Roads", "RoadMarkings", "RoadCentreLines"]:
		var old := parent.get_node_or_null(nm)
		if old != null:
			parent.remove_child(old)
			old.queue_free()
	if parent.has_meta("last_bays_sig"):
		parent.remove_meta("last_bays_sig")
	_build_roads_and_curbs(parent, roads, crosswalks, road_mat)
	Terrain.drape_subtree(parent)


# Player edits: rebuild the generic buildings and their shopfronts (demolished ones have no footprint).
# Returns the new storefront night material (or null).
static func rebuild_building_layer(parent: Node3D, buildings: Array, storefronts: Array, building_mat: ShaderMaterial) -> ShaderMaterial:
	for nm: String in ["Buildings", "BuildingFrames3D", "BuildingBalconies", "RooftopBeacons", "StorefrontSigns", "StorefrontFrames", "StorefrontGlazing"]:
		var old := parent.get_node_or_null(nm)
		if old != null:
			parent.remove_child(old)
			old.queue_free()
	_build_buildings(parent, buildings, building_mat)
	var sm := StorefrontBuilder.build_storefronts(parent, storefronts, buildings)
	Terrain.drape_subtree(parent)
	return sm


static func _clean_poly(raw_pts: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in raw_pts:
		var v := Vector2(float(p[0]), float(p[1]))
		if pts.size() == 0 or pts[pts.size() - 1].distance_to(v) > 0.08:
			pts.append(v)
	if pts.size() >= 3 and pts[0].distance_to(pts[pts.size() - 1]) <= 0.08:
		pts.resize(pts.size() - 1)
	return pts


static func _build_areas(parent: Node3D, areas: Array) -> void:
	var buckets := {
		"water": [],
		"park": [],
		"island": [],
		"brick": [],
		"plaza": [],
		"lawn": [],
		"vacant": [],
	}
	for a in areas:
		var kind: String = str(a.get("kind", ""))
		if kind == "water":
			buckets["water"].append(a)
		elif kind == "island":
			buckets["island"].append(a)
		elif kind in ["park", "grass", "wood", "meadow", "garden", "sports"]:
			buckets["park"].append(a)
		elif kind == "brick_plaza":
			buckets["brick"].append(a)
		elif kind == "compound_green":
			buckets["lawn"].append(a)
		elif kind == "vacant_green":
			buckets["vacant"].append(a)
		else:
			buckets["plaza"].append(a)

	_emit_area_group(parent, "ParkAreas", buckets["park"], 0.014, Color(0.20, 0.35, 0.14), 0.90, 0.0)
	# compound courtyards: own height (never coplanar with parks, which they are kept apart from anyway)
	_emit_area_group(parent, "CompoundLawns", buckets["lawn"], 0.006, Color(0.20, 0.32, 0.14), 0.92, 0.0)
	# undeveloped plots: rough, slightly dry grass (kept apart from every other area, same height as the lawns)
	_emit_area_group(parent, "VacantPlots", buckets["vacant"], 0.006, Color(0.30, 0.34, 0.18), 0.95, 0.0)
	_emit_area_group(parent, "WaterAreas", buckets["water"], 0.026, Color(0.08, 0.22, 0.30), 0.06, 0.35)
	_emit_area_group(parent, "PlazaAreas", buckets["plaza"], 0.030, Color(0.39, 0.38, 0.36), 0.86, 0.0)
	_emit_area_group(parent, "BrickPlazas", buckets["brick"], 0.034, Color(0.45, 0.27, 0.22), 0.84, 0.0)
	_emit_area_group(parent, "IslandParkAreas", buckets["island"], 0.22, Color(0.22, 0.38, 0.16), 0.90, 0.0)


# Flat triangle; with terrain, split until no edge is longer than 8 m so the later drape bends smoothly over graded embankments
static var _tess_flat := false # water: stays one flat sheet

static func _tri_out(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, y: float) -> void:
	var max_e2 := 64.0 if (Terrain.active and not _tess_flat) else 6400.0
	var lab := a.distance_squared_to(b)
	var lbc := b.distance_squared_to(c)
	var lca := c.distance_squared_to(a)
	var lm := maxf(lab, maxf(lbc, lca))
	if lm > max_e2:
		if lm == lab:
			var m := (a + b) * 0.5
			_tri_out(st, a, m, c, y)
			_tri_out(st, m, b, c, y)
		elif lm == lbc:
			var m2 := (b + c) * 0.5
			_tri_out(st, a, b, m2, y)
			_tri_out(st, a, m2, c, y)
		else:
			var m3 := (c + a) * 0.5
			_tri_out(st, a, b, m3, y)
			_tri_out(st, m3, b, c, y)
		return
	for rp: Vector2 in [a, b, c]:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(rp.x, y, rp.y))


static func _append_triangulated_poly(st: SurfaceTool, poly: PackedVector2Array, y_level: float) -> int:
	var idx := Geometry2D.triangulate_polygon(poly)
	if not idx.is_empty():
		var n_tri := 0
		for i in range(0, idx.size(), 3):
			_tri_out(st, poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]], y_level)
			n_tri += 1
		return n_tri
	# Fallback for self-touching / clipped OSM water & park polygons (e.g., Lake Union!):
	# merge_polygons splits self-overlapping boundary edges into clean, valid outer rings!
	var cleaned := Geometry2D.merge_polygons(poly, PackedVector2Array())
	var total_tri := 0
	for sub: PackedVector2Array in cleaned:
		if sub.size() < 3 or Geometry2D.is_polygon_clockwise(sub):
			continue
		var sidx := Geometry2D.triangulate_polygon(sub)
		if sidx.is_empty():
			var nudged := Geometry2D.offset_polygon(sub, -0.05)
			for np: PackedVector2Array in nudged:
				var nidx := Geometry2D.triangulate_polygon(np)
				for i in range(0, nidx.size(), 3):
					_tri_out(st, np[nidx[i]], np[nidx[i + 1]], np[nidx[i + 2]], y_level)
					total_tri += 1
			continue
		for i in range(0, sidx.size(), 3):
			_tri_out(st, sub[sidx[i]], sub[sidx[i + 1]], sub[sidx[i + 2]], y_level)
			total_tri += 1
	return total_tri


static func _emit_area_group(
	parent: Node3D,
	node_name: String,
	list: Array,
	y_level: float,
	col: Color,
	rough: float,
	metal: float
) -> void:
	if list.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri_count := 0
	var is_water := node_name == "WaterAreas"
	_tess_flat = is_water
	for a in list:
		var poly := _clean_poly(a.get("pts", []))
		if poly.size() < 3:
			continue
		# water sits flat at its own lake / sea level (terrain); everything else is draped afterwards
		var y_use := y_level + (float(a.get("_level", 0.0)) if (is_water and Terrain.active) else 0.0)
		tri_count += _append_triangulated_poly(st, poly, y_use)
	_tess_flat = false
	if tri_count == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	if is_water:
		mi.set_meta("on_terrain", true)
		mi.mesh = st.commit()
	else:
		mi.mesh = Terrain.commit_draped(st, mi)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	mat.metallic = metal
	mat.metallic_specular = 0.22
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if node_name == "WaterAreas":
		var wm := ShaderMaterial.new()
		wm.shader = load("res://shaders/water_bay.gdshader") as Shader
		mi.material_override = wm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.set_meta("water_mat", wm)
		parent.add_child(mi)
		return
	if node_name in ["ParkAreas", "IslandParkAreas", "CompoundLawns", "VacantPlots"]:
		var pm := ShaderMaterial.new()
		pm.shader = load("res://shaders/park_lawn.gdshader") as Shader
		if node_name == "VacantPlots":
			pm.set_shader_parameter("tint_mul", Vector3(1.04, 0.94, 0.72))
		elif node_name == "CompoundLawns":
			pm.set_shader_parameter("tint_mul", Vector3(0.96, 0.98, 0.94))
		if node_name == "IslandParkAreas":
			pm.set_shader_parameter("depth_push", 0.13)
			pm.set_shader_parameter("depth_slope", 0.00050)
		mi.material_override = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		return
	if node_name == "PlazaAreas" or node_name == "BrickPlazas":
		var plm := ShaderMaterial.new()
		plm.shader = load("res://shaders/plaza_surface.gdshader") as Shader
		plm.set_shader_parameter("base_col", col)
		plm.set_shader_parameter("rough_val", rough)
		mi.material_override = plm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		return
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# Greedy graph colouring of streets that meet at a junction (shared end-point, or end-points within 18m):
# neighbours always get different height levels, so their overlapping quads never sit exactly coplanar.
static func _road_height_levels(roads: Array) -> PackedInt32Array:
	var n := roads.size()
	var levels := PackedInt32Array()
	levels.resize(n)
	var ends: Array = []
	for r in roads:
		var rp: Array = r.get("pts", [])
		if rp.size() < 2:
			ends.append([])
			continue
		ends.append([Vector2(float(rp[0][0]), float(rp[0][1])), Vector2(float(rp[rp.size() - 1][0]), float(rp[rp.size() - 1][1]))])
	var cell := {}
	for i in range(n):
		for e in ends[i]:
			var k := Vector2i(int(floor((e as Vector2).x / 20.0)), int(floor((e as Vector2).y / 20.0)))
			if not cell.has(k):
				cell[k] = []
			(cell[k] as Array).append(i)
	for i in range(n):
		var used := {}
		for e in ends[i]:
			var ev: Vector2 = e
			var k0 := Vector2i(int(floor(ev.x / 20.0)), int(floor(ev.y / 20.0)))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for j: int in cell.get(k0 + Vector2i(dx, dz), []):
						if j >= i:
							continue
						for e2 in ends[j]:
							if ev.distance_to(e2) < 18.0:
								used[levels[j]] = true
		var lv := 0
		while used.has(lv) and lv < 7:
			lv += 1
		levels[i] = lv
	return levels


static func _build_roads_and_curbs(
	parent: Node3D,
	roads: Array,
	crosswalks: Array,
	road_mat: ShaderMaterial,
	emit_n: int = -1,
	bays: Array = [],
	clear_idx: Dictionary = {}
) -> void:
	if roads.is_empty():
		return
	# Map tiles pass their own streets first and the neighbouring ones after them: those only inform
	# junctions, kerbs and sidewalk widths, and are built by their own tile.
	if emit_n < 0:
		emit_n = roads.size()
	var kerb_src := roads # kerbs sample every 0.5 m anyway: they keep the original polylines
	if Terrain.active:
		# short segments so the draped carriageway and its lines follow the slope
		var dense: Array = []
		for r0: Dictionary in roads:
			var rd := r0.duplicate()
			rd["pts"] = Terrain.densify_adaptive(r0.get("pts", []), 8.0, 2.0, 0.03)
			dense.append(rd)
		roads = dense
	var road_st := SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mark_st := SurfaceTool.new()
	mark_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yellow_st := SurfaceTool.new()
	yellow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_yellow := false

	var curb_st := SurfaceTool.new()
	curb_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var has_road := false
	var has_mark := false
	var has_curb := false

	var road_level := _road_height_levels(roads)
	for road_i in range(roads.size()):
		var r: Dictionary = roads[road_i]
		if road_i >= emit_n:
			break
		if bool(r.get("underground", false)):
			continue
		if r.has("lv"):
			road_level[road_i] = int(r["lv"]) # level fixed map-wide, so streets meeting across tiles differ
		var raw_pts: Array = r.get("pts", [])
		if raw_pts.size() < 2:
			continue
		var hw: float = clampf(float(r.get("width", 12.0)) * 0.5, 3.2, 13.5)
		var layer: int = int(r.get("layer", 0))
		var y_base: float = 0.042 + float(maxi(0, layer)) * 5.2
		var y := y_base

		for i in range(raw_pts.size() - 1):
			var a := Vector2(float(raw_pts[i][0]), float(raw_pts[i][1]))
			var b := Vector2(float(raw_pts[i + 1][0]), float(raw_pts[i + 1][1]))
			var d := b - a
			var seg_len := d.length()
			if seg_len < 0.25:
				continue
			var dir := d / seg_len
			var nrm := Vector2(-dir.y, dir.x) * hw
			# Overlap past the ends closes the wedge gaps at junctions and bends; where the street runs straight
			# on (points added by densifying) a tiny overlap is enough, and a long one would reach over the next
			# span's slope and stand above the ground there
			var ext := minf(hw * 0.55, 2.6)
			var ext_a := ext
			var ext_b := ext
			if i > 0:
				var pa := Vector2(float(raw_pts[i - 1][0]), float(raw_pts[i - 1][1]))
				if pa.distance_to(a) > 0.1 and (a - pa).normalized().dot(dir) > 0.9986:
					ext_a = 0.08
			if i + 2 < raw_pts.size():
				var pb := Vector2(float(raw_pts[i + 2][0]), float(raw_pts[i + 2][1]))
				if pb.distance_to(b) > 0.1 and (pb - b).normalized().dot(dir) > 0.9986:
					ext_b = 0.08
			var a_ext := a - dir * ext_a
			var b_ext := b + dir * ext_b
			# Road quads overlap at junctions and polyline bends: give each a fixed, distinct height so the
			# overlap always resolves the same way (exactly coplanar overlaps z-fight and flicker in motion)
			y = y_base + float(road_level[road_i]) * 0.0015 + float(i % 2) * 0.0005

			var v0 := Vector3(a_ext.x - nrm.x, y, a_ext.y - nrm.y)
			var v1 := Vector3(a_ext.x + nrm.x, y, a_ext.y + nrm.y)
			var v2 := Vector3(b_ext.x + nrm.x, y, b_ext.y + nrm.y)
			var v3 := Vector3(b_ext.x - nrm.x, y, b_ext.y - nrm.y)

			# On terrain the quad is split across its width into strips of at most 4 m: draped only at its four
			# corners, a wide street across a slope would bow up to ~1 m above the ground along its middle
			# (where tracks, markings and previews sit)
			var strips := 1
			if Terrain.active:
				# only where the ground actually bows across the street (most streets stay one quad)
				var bow := 0.0
				for q in [a_ext, (a_ext + b_ext) * 0.5, b_ext]:
					var qv: Vector2 = q
					var gm := Terrain.surface(qv.x, qv.y)
					var gl := Terrain.surface(qv.x - nrm.x, qv.y - nrm.y)
					var gr := Terrain.surface(qv.x + nrm.x, qv.y + nrm.y)
					bow = maxf(bow, absf((gl + gr) * 0.5 - gm))
				if bow > 0.03:
					strips = clampi(int(ceil(hw * 2.0 / 4.0)), 2, 7)
			# Lengthwise the overlaps past the ends are pieces of their own on terrain, so the draped street
			# bends exactly at the junction / bend point instead of spanning straight across it
			var cuts: Array[float] = [0.0, 1.0]
			if Terrain.active:
				var tot := ext_a + seg_len + ext_b
				cuts = [0.0]
				if ext_a > 0.5:
					cuts.append(ext_a / tot)
				if ext_b > 0.5:
					cuts.append((ext_a + seg_len) / tot)
				cuts.append(1.0)
			for c in range(cuts.size() - 1):
				var t0 := cuts[c]
				var t1 := cuts[c + 1]
				var p0 := v0.lerp(v3, t0)
				var p1 := v1.lerp(v2, t0)
				var p2 := v1.lerp(v2, t1)
				var p3 := v0.lerp(v3, t1)
				for k in range(strips):
					var f0 := float(k) / float(strips)
					var f1 := float(k + 1) / float(strips)
					var w0 := p0.lerp(p1, f0)
					var w1 := p0.lerp(p1, f1)
					var w2 := p3.lerp(p2, f1)
					var w3 := p3.lerp(p2, f0)
					var u0 := lerpf(-1.0, 1.0, f0)
					var u1 := lerpf(-1.0, 1.0, f1)
					var s0 := t0 * seg_len
					var s1 := t1 * seg_len
					road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(u0, s0)); road_st.add_vertex(w0)
					road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(u1, s0)); road_st.add_vertex(w1)
					road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(u1, s1)); road_st.add_vertex(w2)
					road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(u0, s0)); road_st.add_vertex(w0)
					road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(u1, s1)); road_st.add_vertex(w2)
					road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(u0, s1)); road_st.add_vertex(w3)
			has_road = true

			# Lane markings from the real lane counts: yellow centre line(s) on two-way streets, white dashes
			# between lanes running the same way (roads without lane data keep the single centre dash)
			if r.has("lanes_f"):
				var lf := int(r.get("lanes_f", 1))
				var lb := int(r.get("lanes_b", 1))
				var nrm1 := Vector2(-dir.y, dir.x)
				var ym2 := y + 0.016
				var dash_offs: Array[float] = []
				if lf > 0 and lb > 0:
					if bool(r.get("tram_median", false)) and hw >= 8.5:
						# Center-of-road tramway boulevard: solid yellow borders outside the central ±3.1m tramway
						# + white dashed dividers between outer motorized car lanes on BOTH sides!
						for yo: float in [-3.55, 3.55]:
							var c0 := a + nrm1 * yo
							var c1 := b + nrm1 * yo
							var cn := nrm1 * 0.075
							_add_flat_quad(yellow_st, Vector3(c0.x - cn.x, ym2, c0.y - cn.y), Vector3(c0.x + cn.x, ym2, c0.y + cn.y),
								Vector3(c1.x + cn.x, ym2, c1.y + cn.y), Vector3(c1.x - cn.x, ym2, c1.y - cn.y), Vector3.UP)
							has_yellow = true
						if lf >= 2 and hw >= 10.5:
							dash_offs.append(6.90)
						if lb >= 2 and hw >= 10.5:
							dash_offs.append(-6.90)
					else:
						var med := 0.8 if lf + lb >= 4 else 0.0
						for yo: float in ([-med - 0.1, med + 0.1] if med > 0.0 else [-0.12, 0.12]):
							var c0 := a + nrm1 * yo
							var c1 := b + nrm1 * yo
							var cn := nrm1 * 0.06
							_add_flat_quad(yellow_st, Vector3(c0.x - cn.x, ym2, c0.y - cn.y), Vector3(c0.x + cn.x, ym2, c0.y + cn.y),
								Vector3(c1.x + cn.x, ym2, c1.y + cn.y), Vector3(c1.x - cn.x, ym2, c1.y - cn.y), Vector3.UP)
							has_yellow = true
						for k in range(1, lf):
							dash_offs.append(med + float(k) * 3.3)
						for k in range(1, lb):
							dash_offs.append(-(med + float(k) * 3.3))
				else:
					var n_l := maxi(lf, lb)
					for k in range(1, n_l):
						dash_offs.append(-float(n_l) * 1.65 + float(k) * 3.3)
				for off: float in dash_offs:
					if absf(off) > hw - 1.0:
						continue
					var sd := 3.5
					while sd + 3.0 < seg_len - 3.0:
						var d0 := a + dir * sd + nrm1 * off
						var d1 := a + dir * (sd + 3.0) + nrm1 * off
						var dn := nrm1 * 0.07
						_add_flat_quad(mark_st, Vector3(d0.x - dn.x, ym2, d0.y - dn.y), Vector3(d0.x + dn.x, ym2, d0.y + dn.y),
							Vector3(d1.x + dn.x, ym2, d1.y + dn.y), Vector3(d1.x - dn.x, ym2, d1.y - dn.y), Vector3.UP)
						has_mark = true
						sd += 9.2
				# Bike-lane strips & divider stripes are built track-aware inside _build_kerbs() -> _build_bike_lane_strips()
				# so green non-motorized lanes NEVER overlap laid tram tracks!
				continue
			var s := 3.5
			while s + 3.0 < seg_len - 3.0:
				var m0 := a + dir * s
				var m1 := a + dir * (s + 3.0)
				var mn := Vector2(-dir.y, dir.x) * 0.08
				var ym := y + 0.016
				_add_flat_quad(
					mark_st,
					Vector3(m0.x - mn.x, ym, m0.y - mn.y),
					Vector3(m0.x + mn.x, ym, m0.y + mn.y),
					Vector3(m1.x + mn.x, ym, m1.y + mn.y),
					Vector3(m1.x - mn.x, ym, m1.y - mn.y),
					Vector3.UP
				)
				has_mark = true
				s += 9.2

	# Weathered thermoplastic crosswalk zebra stripes
	for cw in crosswalks:
		var cp: Array = cw["pos"]
		var cd: Array = cw["dir"]
		var cw_w := clampf(float(cw.get("width", 12.0)) * 0.44, 3.0, 11.0)
		var center := Vector2(float(cp[0]), float(cp[1]))
		var along := Vector2(float(cd[0]), float(cd[1])).normalized()
		var across := Vector2(-along.y, along.x)
		var y_cw := 0.060

		var lat := -cw_w + 0.55
		while lat <= cw_w - 0.55:
			var bar_c := center + across * lat
			var b0 := bar_c - along * 1.25 - across * 0.21
			var b1 := bar_c - along * 1.25 + across * 0.21
			var b2 := bar_c + along * 1.25 + across * 0.21
			var b3 := bar_c + along * 1.25 - across * 0.21
			_add_flat_quad(
				mark_st,
				Vector3(b0.x, y_cw, b0.y),
				Vector3(b1.x, y_cw, b1.y),
				Vector3(b2.x, y_cw, b2.y),
				Vector3(b3.x, y_cw, b3.y),
				Vector3.UP
			)
			has_mark = true
			lat += 0.98

	if has_road:
		var road_mi := MeshInstance3D.new()
		road_mi.name = "Roads"
		road_mi.mesh = Terrain.commit_draped(road_st, road_mi)
		road_mi.material_override = road_mat
		road_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(road_mi)

	parent.set_meta("kerb_roads", kerb_src)
	parent.set_meta("kerb_emit_n", emit_n)
	parent.set_meta("road_mat", road_mat)
	_build_kerbs(parent, kerb_src, bays, road_mat, clear_idx)

	if has_mark:
		var mark_mi := MeshInstance3D.new()
		mark_mi.name = "RoadMarkings"
		mark_mi.mesh = Terrain.commit_draped(mark_st, mark_mi)
		var m_mat := ShaderMaterial.new()
		m_mat.shader = load("res://shaders/road_marking.gdshader") as Shader
		m_mat.set_shader_parameter("paint_col", Color(0.78, 0.77, 0.73))
		m_mat.set_shader_parameter("rough_val", 0.82)
		mark_mi.material_override = m_mat
		mark_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mark_mi)
	if has_yellow:
		var y_mi := MeshInstance3D.new()
		y_mi.name = "RoadCentreLines"
		y_mi.mesh = Terrain.commit_draped(yellow_st, y_mi)
		var y_mat := ShaderMaterial.new()
		y_mat.shader = load("res://shaders/road_marking.gdshader") as Shader
		y_mat.set_shader_parameter("paint_col", Color(0.86, 0.68, 0.18))
		y_mat.set_shader_parameter("rough_val", 0.80)
		y_mi.material_override = y_mat
		y_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(y_mi)


static func _build_buildings(parent: Node3D, buildings: Array, building_mat: ShaderMaterial) -> void:
	if buildings.is_empty():
		return

	# Natural sunlit architectural palettes (never pitch black!)
	var glass_pal: Array[Color] = [
		Color(0.56, 0.66, 0.73),
		Color(0.52, 0.63, 0.67),
		Color(0.62, 0.67, 0.71),
		Color(0.50, 0.59, 0.66),
	]
	var brick_pal: Array[Color] = [
		Color(0.68, 0.41, 0.32), # Classic Seattle terracotta brick
		Color(0.82, 0.77, 0.69), # Beaux-Arts cream limestone / terracotta
		Color(0.74, 0.57, 0.44), # Warm buff sandstone
		Color(0.60, 0.36, 0.30), # Aged downtown red brick
		Color(0.76, 0.73, 0.67), # Carved grey-cream stone
	]
	var mod_pal: Array[Color] = [
		Color(0.77, 0.74, 0.70),
		Color(0.68, 0.69, 0.70),
		Color(0.81, 0.78, 0.74),
		Color(0.64, 0.63, 0.61),
	]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Separate batched mesh for 3D structural columns, pilasters, belt ledges & overhanging cornices!
	var frame_st := SurfaceTool.new()
	frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_frames := false

	var roof_props := Node3D.new()
	roof_props.name = "RooftopBeacons"
	parent.add_child(roof_props)

	var mech_col := Color(0.52, 0.52, 0.50)
	var awning_col_a := Color(0.16, 0.32, 0.24)
	var awning_col_b := Color(0.48, 0.19, 0.18)

	var beacon_mat := LandmarksBuilder._make_beacon_mat()

	# Houses (style 3): painted lap siding walls + real pitched roofs (separate double-sided roof mesh)
	var roof_st := SurfaceTool.new()
	roof_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_roofs := false
	var house_pal: Array[Color] = [
		Color(0.55, 0.60, 0.62), # grey-blue
		Color(0.45, 0.51, 0.43), # sage green
		Color(0.79, 0.75, 0.66), # beige
		Color(0.87, 0.86, 0.82), # white
		Color(0.38, 0.43, 0.49), # slate blue
		Color(0.64, 0.55, 0.43), # tan
		Color(0.52, 0.33, 0.27), # barn red
		Color(0.70, 0.66, 0.56), # khaki
	]
	var shingle_pal: Array[Color] = [
		Color(0.22, 0.22, 0.23),
		Color(0.31, 0.27, 0.24),
		Color(0.37, 0.35, 0.33),
		Color(0.25, 0.29, 0.27),
		Color(0.40, 0.25, 0.20),
	]

	var b_idx := 0
	var any_geom := false
	var is_zh := building_mat != null and float(building_mat.get_shader_parameter("chinese_style")) > 0.5
	# Balconies: own meshes per BALC_CELL map cell, drawn only near the camera (one city-wide batch would be
	# far too heavy and cannot be distance-culled)
	var bal_cells := {} # Vector2i -> Terrain accumulator
	var bal_st := SurfaceTool.new()
	bal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bal_used := false
	var bal_key := Vector2i.ZERO
	# Terrain: every building is built into its own small tools, then appended to the batch raised onto the
	# lowest ground under its footprint (rigid: level roofs, walls reaching down into the slope)
	var acc_st := Terrain.acc_new()
	var acc_fr := Terrain.acc_new()
	var acc_rf := Terrain.acc_new()
	var cur_y0 := 0.0
	var pending := false

	for b in buildings:
		if pending:
			Terrain.acc_add(acc_st, st, cur_y0)
			Terrain.acc_add(acc_fr, frame_st, cur_y0)
			Terrain.acc_add(acc_rf, roof_st, cur_y0)
			if bal_used:
				if not bal_cells.has(bal_key):
					bal_cells[bal_key] = Terrain.acc_new()
				Terrain.acc_add(bal_cells[bal_key], bal_st, cur_y0)
				bal_st = SurfaceTool.new()
				bal_st.begin(Mesh.PRIMITIVE_TRIANGLES)
				bal_used = false
			pending = false
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			frame_st = SurfaceTool.new()
			frame_st.begin(Mesh.PRIMITIVE_TRIANGLES)
			roof_st = SurfaceTool.new()
			roof_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var poly := _clean_poly(b.get("pts", []))
		if poly.size() < 3:
			continue
		if str(b.get("lm", "")) in SeattleV2Landmarks.SKIP_GENERIC or str(b.get("lm", "")) in JiaxingLandmarks.SKIP_GENERIC:
			continue # built as a dedicated landmark model
		cur_y0 = Terrain.base_under(poly)
		b["_y0"] = cur_y0
		pending = true
		if Terrain.active:
			# a skirt below the base: on steep ground no gap opens between the walls and the slope
			var skirt := Color(0.46, 0.45, 0.43, (2.0 * 64.0) / 255.0)
			var cw := poly.duplicate()
			if Geometry2D.is_polygon_clockwise(cw):
				cw.reverse()
			for si in range(cw.size()):
				var q0 := cw[si]
				var q1 := cw[(si + 1) % cw.size()]
				var ed := q1 - q0
				if ed.length() < 0.1:
					continue
				var dn := ed.normalized()
				_emit_wall_quad(st, Vector3(q0.x, -4.0, q0.y), Vector3(q1.x, -4.0, q1.y), Vector3(q1.x, 0.0, q1.y), Vector3(q0.x, 0.0, q0.y), Vector3(-dn.y, 0.0, dn.x), 0.0, ed.length(), -4.0, 0.0, skirt)
		var h: float = clampf(float(b.get("h", 14.0)), 5.0, 185.0)
		var style: int = clampi(int(b.get("style", 2)), 0, 3)
		# Real-world look for named OSM buildings (landmark facades, recorded building colours)
		var lm_o: Dictionary = LandmarkFacades.override_for(b)
		if not lm_o.is_empty():
			if int(lm_o["style"]) >= 0:
				style = int(lm_o["style"])
			if float(lm_o["h"]) > 0.0:
				h = float(lm_o["h"])
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		var b_hash := absi(int(poly[0].x * 7.31 + poly[0].y * 3.17))
		if is_zh and lm_o.get("style", -1) == -1 and str(b.get("lm", "")) == "" and style == 0 and h < 75.0 \
				and str(b.get("kind", "")) in ["apartments", "residential", "yes"]:
			# Ordinary apartment blocks are concrete, not CBD glass curtain walls: most get the residential
			# facade, some the mixed-use stone facade, a few keep glass
			var pick := b_hash % 20
			style = 2 if pick < 14 else (1 if pick < 17 else 0)

		if style == 3:
			var hc: Color = house_pal[int(absf(poly[0].x * 7.0 + poly[0].y * 13.0)) % house_pal.size()]
			if str(b.get("colour", "")) != "":
				hc = Color.from_string(str(b["colour"]), hc)
			var rc: Color = shingle_pal[int(absf(poly[0].x * 3.0 + poly[0].y * 5.0)) % shingle_pal.size()]
			if str(b.get("roof_colour", "")) != "":
				rc = Color.from_string(str(b["roof_colour"]), rc)
			var hcol := Color(hc.r, hc.g, hc.b, (3.0 * 64.0 + float(b_idx % 60)) / 255.0)
			b_idx += 1
			_emit_house(st, roof_st, poly, h, b.get("roof", {}), hcol, rc)
			any_geom = true
			has_roofs = has_roofs or not (b.get("roof", {}) as Dictionary).is_empty()
			continue

		# Stadium stands with the field as a hole (OSM inner ring): an open seating bowl round a grass field
		if b.has("inner") and str(b.get("kind", "")) == "stadium":
			var inner := _clean_poly(b["inner"])
			if inner.size() >= 3:
				if Geometry2D.is_polygon_clockwise(inner):
					inner.reverse()
				var svcol := Color(0.70, 0.70, 0.68, (2.0 * 64.0 + float(b_idx % 60)) / 255.0)
				b_idx += 1
				_emit_stadium(st, roof_st, frame_st, poly, inner, h, svcol, str(b.get("stadium_roof", "")))
				any_geom = true
				has_roofs = true
				has_frames = true
				continue

		var base_c: Color
		var trim_c: Color
		if style == 0:
			base_c = glass_pal[b_idx % glass_pal.size()]
			if str(b.get("colour", "")) != "":
				base_c = Color.from_string(str(b["colour"]), base_c)
			trim_c = Color(0.48, 0.51, 0.54) # Brushed aluminum / dark steel mullions & columns
		elif style == 1:
			base_c = brick_pal[b_idx % brick_pal.size()]
			if str(b.get("colour", "")) != "":
				base_c = Color.from_string(str(b["colour"]), base_c)
			trim_c = base_c.lerp(Color(0.82, 0.80, 0.75), 0.52) # Carved limestone / Chinese dry-hung granite piers & cornices
		else:
			base_c = mod_pal[b_idx % mod_pal.size()]
			if str(b.get("colour", "")) != "":
				base_c = Color.from_string(str(b["colour"]), base_c)
			trim_c = base_c.lightened(0.06)

		if not lm_o.is_empty():
			base_c = lm_o["color"]
			trim_c = base_c.lightened(0.10) if style != 0 else trim_c
		if is_zh and style in [1, 2] and str(b.get("lm", "")) == "" and b.has("cpd") and str(b.get("trim", "")) != "":
			# One developer scheme per compound (wall + line colour), a hair of per-building weathering
			base_c = Color.from_string(str(b["colour"]), Color(0.9, 0.88, 0.84))
			var jt := (float(b_hash % 9) - 4.0) * 0.006
			base_c = Color(clampf(base_c.r + jt, 0.0, 1.0), clampf(base_c.g + jt, 0.0, 1.0), clampf(base_c.b + jt, 0.0, 1.0))
			trim_c = Color.from_string(str(b["trim"]), Color(0.35, 0.36, 0.38))
		elif is_zh and style in [1, 2] and str(b.get("lm", "")) == "":
			# Real Chinese residential colour schemes instead of six near-identical pale greys: neighbouring
			# blocks (one compound) share a colour family, each building varies a little
			base_c = _zh_facade_colour(Vector2(poly[0].x, poly[0].y), b_hash)
			trim_c = base_c.lerp(Color(0.92, 0.91, 0.88), 0.45)
		var seed_i := b_idx % 60
		if not lm_o.is_empty() and bool(lm_o["ashlar"]):
			seed_i = LandmarkFacades.ASHLAR_SEED
		var encoded_a := (float(style) * 64.0 + float(seed_i)) / 255.0
		var vcol := Color(base_c.r, base_c.g, base_c.b, encoded_a)
		b_idx += 1

		var min_v := poly[0]
		var max_v := poly[0]
		var sum_v := Vector2.ZERO
		for pt in poly:
			min_v = min_v.min(pt)
			max_v = max_v.max(pt)
			sum_v += pt
		var span := max_v - min_v
		var center2 := sum_v / float(poly.size())

		# Check if tall skyscraper qualifies for realistic Podium + Setback Tower massing!
		var has_setback := false
		var tower_poly := poly
		var podium_h := 16.0
		if h >= 44.0 and span.x > 30.0 and span.y > 30.0:
			var inset_arr := Geometry2D.offset_polygon(poly, -3.4)
			if inset_arr.size() == 1 and inset_arr[0].size() >= 3:
				tower_poly = inset_arr[0]
				if Geometry2D.is_polygon_clockwise(tower_poly):
					tower_poly.reverse()
				has_setback = true

		var min_h := float(b.get("min_h", 0.0))
		if min_h > 0.5:
			# 3D building part raised off the ground (upper tower stage, skybridge, cantilever): extrude
			# min_h .. h and close its underside
			_extrude_tier_with_3d_relief(st, frame_st, poly, min_h, h, style, vcol, trim_c, false)
			var tri_u := Geometry2D.triangulate_polygon(poly)
			for k in range(0, tri_u.size(), 3):
				for rp: Vector2 in [poly[tri_u[k]], poly[tri_u[k + 2]], poly[tri_u[k + 1]]]:
					st.set_color(vcol)
					st.set_normal(Vector3.DOWN)
					st.set_uv(Vector2.ZERO)
					st.add_vertex(Vector3(rp.x, min_h, rp.y))
			has_frames = true
			any_geom = true
			continue
		var kind_s := str(b.get("kind", ""))
		var resid := kind_s in ["apartments", "residential", "dormitory"]
		# Plain buildings (a recorded facade colour is fine; named landmarks keep their own modelling)
		var yang := bool(b.get("yangfang", false))
		var generic := ((b.get("roof", {}) as Dictionary).is_empty() or yang) and str(b.get("lm", "")) == ""
		# Balconies line up with the facade shader's floor / bay grid (Chinese slab towers: balcony bays
		# alternate; Seattle apartment blocks: every other window bay)
		var balc := {}
		if generic and resid and style == 2 and h >= 9.0:
			bal_key = Vector2i(int(floor(center2.x / BALC_CELL)), int(floor(center2.y / BALC_CELL)))
			var wall_c := base_c.lerp(Color(0.86, 0.83, 0.78), 0.45)
			if is_zh:
				balc = {"fh": 3.05, "bw": 4.2, "seed": seed_i, "zh": true, "y0": 4.6, "depth": 1.35,
					"slab": wall_c, "rail": wall_c.lightened(0.06), "st": bal_st}
			else:
				balc = {"fh": 3.55, "bw": 3.4, "seed": seed_i, "zh": false, "y0": 3.0, "depth": 1.15,
					"slab": base_c.lerp(Color(0.80, 0.80, 0.78), 0.5), "rail": Color(0.20, 0.21, 0.23), "st": bal_st}
		var top_piece := poly
		var top_h := h
		var pitched := {}
		if yang:
			# 洋房: 6-11 storeys under a dark grey hipped tile roof
			pitched = (b["roof"] as Dictionary).duplicate()
			pitched["col"] = Color.from_string(str(b.get("roof_colour", "#3c4148")), Color(0.24, 0.26, 0.29))
		elif is_zh and generic and resid and style == 2 and h >= 9.0 and h <= 25.0 and (b_hash % 10) < 5:
			var obr := _obb2d(poly)
			if not obr.is_empty() and absf(_poly_area(poly)) > 0.82 * 4.0 * float(obr[2]) * float(obr[3]):
				var ou: Vector2 = obr[1]
				var hs_r := float(obr[3])
				var tile_c: Color = [Color(0.30, 0.32, 0.35), Color(0.26, 0.28, 0.30), Color(0.56, 0.31, 0.24), Color(0.40, 0.42, 0.45)][b_hash % 4]
				pitched = {"c": [obr[0].x, obr[0].y], "a": atan2(ou.y, ou.x), "hl": float(obr[2]), "hw": hs_r,
					"h": clampf(hs_r * 0.55, 1.6, 3.4), "shape": "hipped" if (b_hash / 10) % 3 != 0 else "gabled", "col": tile_c}
		if has_setback:
			# Extrude street-edge podium (0 .. podium_h) + setback upper tower (podium_h .. h)
			_extrude_tier_with_3d_relief(st, frame_st, poly, 0.0, podium_h, style, vcol, trim_c, true)
			_extrude_tier_with_3d_relief(st, frame_st, tower_poly, podium_h, h, style, vcol, trim_c, false, balc)
			has_frames = true
			any_geom = true
			top_piece = tower_poly
		else:
			# Varied massing instead of one plain box: long slabs step down floor by floor at their ends,
			# point towers get a set-back crown (top floors), the rest stay simple
			var fh_m := 3.05 if is_zh else 3.4
			var pieces: Array = _massing_pieces(poly, h, fh_m) if generic and poly.size() >= 4 and pitched.is_empty() else [[poly, 0.0, h]]
			for pc: Array in pieces:
				_extrude_tier_with_3d_relief(st, frame_st, pc[0], float(pc[1]), float(pc[2]), style, vcol, trim_c, float(pc[1]) < 0.5, balc)
				if is_zh and generic and resid and style == 2 and not yang and h >= 40.0:
					_emit_zh_tower_lines(frame_st, pc[0], float(pc[2]), trim_c, base_c, float(pc[2]) >= h - 0.01)
				if float(pc[2]) >= top_h - 0.01:
					top_piece = pc[0]
			has_frames = true
			any_geom = true
		if not balc.is_empty() and bool(balc.get("used", false)):
			bal_used = true
		if not pitched.is_empty():
			# Pitched tile roof of an older 6-8 storey residential block (老小区坡屋顶)
			_emit_roof(st, roof_st, pitched, h + 0.3, vcol, pitched["col"])
			has_roofs = true
		if generic and resid and style == 2 and h >= 24.0 and span.x > 14.0 and span.y > 14.0 and pitched.is_empty():
			_emit_roof_core(frame_st, top_piece, top_h, base_c, trim_c, seed_i)
			has_frames = true

		# Landmark detail: Collegiate Gothic halls / churches (steep slate roofs, buttresses, pinnacles, towers),
		# King Street Station's campanile
		var lm_k := str(b.get("lm", ""))
		var roof_d: Dictionary = b.get("roof", {})
		if not roof_d.is_empty() and not yang:
			var rcol := Color.from_string(str(b.get("roof_colour", "#4a5552")), Color(0.29, 0.33, 0.32))
			_emit_roof(st, roof_st, roof_d, h + 0.3, vcol, rcol)
			has_roofs = true
			if lm_k in ["uw_gothic", "suzzallo", "church"]:
				_emit_gothic(frame_st, poly, h, roof_d, trim_c.lightened(0.15))
			if lm_k == "church" and float(roof_d.get("hl", 0.0)) > 9.0:
				_emit_church_towers(st, roof_st, roof_d, h, bool(b.get("twin_towers", false)), vcol, rcol)
		if lm_k == "campanile":
			_emit_campanile(st, roof_st, frame_st, poly, vcol)
			has_roofs = true
		elif lm_k == "campanile_tower":
			_emit_campanile(st, roof_st, frame_st, poly, vcol, h)
			has_roofs = true

		# Ground-floor shopfront fabric awnings batched into BuildingFrames3D (zero extra draw calls!)
		if style == 1 and (b_idx % 2 == 0):
			for e_i in range(mini(2, poly.size())):
				var p0 := poly[e_i]
				var p1 := poly[(e_i + 1) % poly.size()]
				var elen := p0.distance_to(p1)
				if elen >= 13.0 and elen <= 46.0:
					var edge := p1 - p0
					var nrm := Vector3(-edge.y, 0.0, edge.x).normalized()
					var mid2 := (p0 + p1) * 0.5
					var aw_basis := Basis.from_euler(Vector3(deg_to_rad(14.0), atan2(nrm.x, nrm.z), 0.0))
					var aw_tf := Transform3D(aw_basis, Vector3(mid2.x, 3.75, mid2.y) + nrm * 0.62)
					var aw_c := awning_col_a if ((b_idx + e_i) % 2 == 0) else awning_col_b
					_emit_colored_box(frame_st, aw_tf, Vector3(minf(elen * 0.68, 16.0), 0.32, 1.30), aw_c)
					has_frames = true

		# Rooftop mechanical penthouse, HVAC chillers batched into BuildingFrames3D + skyscraper beacons
		var top_poly := tower_poly if has_setback else poly
		var got_core := str(b.get("kind", "")) in ["apartments", "residential", "dormitory"] and style == 2 and h >= 24.0 and span.x > 14.0 and span.y > 14.0 and (b.get("roof", {}) as Dictionary).is_empty() and str(b.get("lm", "")) == ""
		if not got_core and pitched.is_empty() and Geometry2D.is_point_in_polygon(center2, top_poly) and span.x > 16.0 and span.y > 16.0 and h >= 15.0:
			var pw := clampf(span.x * 0.25, 4.2, 11.5)
			var pd := clampf(span.y * 0.25, 4.2, 11.5)
			var ph := clampf(h * 0.048 + 2.2, 2.5, 5.2)

			_emit_colored_box(
				frame_st,
				Transform3D(Basis.IDENTITY, Vector3(center2.x, h + ph * 0.5, center2.y)),
				Vector3(pw, ph, pd),
				mech_col
			)
			has_frames = true

			if span.x > 26.0:
				_emit_colored_box(
					frame_st,
					Transform3D(Basis.IDENTITY, Vector3(center2.x + pw * 0.68, h + 0.75, center2.y)),
					Vector3(2.6, 1.5, 3.8),
					mech_col.darkened(0.06)
				)

			if h >= 82.0:
				LandmarksBuilder._add_beacon(
					roof_props,
					Vector3(center2.x, h + ph + 1.2 + cur_y0, center2.y),
					beacon_mat
				)

	if pending:
		Terrain.acc_add(acc_st, st, cur_y0)
		Terrain.acc_add(acc_fr, frame_st, cur_y0)
		Terrain.acc_add(acc_rf, roof_st, cur_y0)
		if bal_used:
			if not bal_cells.has(bal_key):
				bal_cells[bal_key] = Terrain.acc_new()
			Terrain.acc_add(bal_cells[bal_key], bal_st, cur_y0)
	roof_props.set_meta("on_terrain", true)
	if not bal_cells.is_empty():
		var bal_root := Node3D.new()
		bal_root.name = "BuildingBalconies"
		parent.add_child(bal_root)
		var bal_mat := StandardMaterial3D.new()
		bal_mat.vertex_color_use_as_albedo = true
		bal_mat.roughness = 0.82
		bal_mat.metallic_specular = 0.25
		for ck: Vector2i in bal_cells.keys():
			var acc_b: Dictionary = bal_cells[ck]
			if Terrain.acc_empty(acc_b):
				continue
			var bmi := MeshInstance3D.new()
			bmi.name = "Balconies_%d_%d" % [ck.x, ck.y]
			bmi.set_meta("on_terrain", true)
			bmi.mesh = Terrain.acc_mesh(acc_b)
			bmi.material_override = bal_mat
			bmi.visibility_range_end = BALC_VIS
			bmi.visibility_range_end_margin = 30.0
			bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			bal_root.add_child(bmi)
	any_geom = any_geom and not Terrain.acc_empty(acc_st)
	has_roofs = has_roofs and not Terrain.acc_empty(acc_rf)
	has_frames = has_frames and not Terrain.acc_empty(acc_fr)
	if any_geom:
		var b_mi := MeshInstance3D.new()
		b_mi.name = "Buildings"
		b_mi.set_meta("on_terrain", true)
		b_mi.mesh = Terrain.acc_mesh(acc_st)
		b_mi.material_override = building_mat
		b_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(b_mi)

	if has_roofs:
		var r_mi := MeshInstance3D.new()
		r_mi.name = "HouseRoofs"
		r_mi.set_meta("on_terrain", true)
		r_mi.mesh = Terrain.acc_mesh(acc_rf)
		var r_mat := StandardMaterial3D.new()
		r_mat.vertex_color_use_as_albedo = true
		r_mat.roughness = 0.92
		r_mat.metallic_specular = 0.18
		r_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		r_mi.material_override = r_mat
		r_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(r_mi)

	if has_frames:
		var f_mi := MeshInstance3D.new()
		f_mi.name = "BuildingFrames3D"
		f_mi.set_meta("on_terrain", true)
		f_mi.mesh = Terrain.acc_mesh(acc_fr)
		var f_mat := StandardMaterial3D.new()
		f_mat.vertex_color_use_as_albedo = true
		f_mat.roughness = 0.76
		f_mat.metallic = 0.08
		f_mat.metallic_specular = 0.28
		f_mi.material_override = f_mat
		# Solid Buildings mesh already casts the full building shadow; skipping mullions/frames cuts millions of shadow tris!
		f_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(f_mi)


# Stadium: precast outer facade up to the rim, raked seating from the rim down to the field edge, grass
# field, and floodlight masts round the rim. The two rings are resampled to the same count to loft the bowl.
static func _emit_stadium(st: SurfaceTool, bowl_st: SurfaceTool, frame_st: SurfaceTool, outer: PackedVector2Array, inner: PackedVector2Array, h: float, wcol: Color, roof_kind: String = "") -> void:
	if roof_kind != "":
		_emit_stadium_roof(bowl_st, frame_st, outer, h, roof_kind)
	var rim := h
	var u_acc := 0.0
	for i in range(outer.size()):
		var p0 := outer[i]
		var p1 := outer[(i + 1) % outer.size()]
		var e := p1 - p0
		var el := e.length()
		if el < 0.1:
			continue
		var d2 := e / el
		_emit_wall_quad(st, Vector3(p0.x, 0.0, p0.y), Vector3(p1.x, 0.0, p1.y), Vector3(p1.x, rim, p1.y), Vector3(p0.x, rim, p0.y), Vector3(-d2.y, 0.0, d2.x), u_acc, u_acc + el, 0.0, rim, wcol)
		u_acc += el
	var n := 72
	var ro := _resample_ring(outer, n)
	var ri := _resample_ring(inner, n)
	# align the inner ring's start with the outer ring's (nearest point), so the seating rows run straight
	var best_k := 0
	var best_d := 1e18
	for k in range(n):
		var dd := ro[0].distance_squared_to(ri[k])
		if dd < best_d:
			best_d = dd
			best_k = k
	var seat_a := Color(0.16, 0.30, 0.24)
	var seat_b := Color(0.20, 0.34, 0.28)
	var conc := Color(0.62, 0.61, 0.58)
	var y_field := 0.22
	var y_low := 2.6 # front row (field wall top)
	for k in range(n):
		var o0 := ro[k]
		var o1 := ro[(k + 1) % n]
		var i0 := ri[(k + best_k) % n]
		var i1 := ri[(k + 1 + best_k) % n]
		# two tiers: lower bowl to a concourse ledge, then the upper deck to the rim
		var m0 := i0.lerp(o0, 0.52)
		var m1 := i1.lerp(o1, 0.52)
		var y_mid := lerpf(y_low, rim, 0.42)
		var col := seat_a if k % 2 == 0 else seat_b
		_roof_quad(bowl_st, _v3(i0, y_low), _v3(i1, y_low), _v3(m1, y_mid), _v3(m0, y_mid), col)
		_roof_quad(bowl_st, _v3(m0, y_mid + 0.9), _v3(m1, y_mid + 0.9), _v3(o1, rim), _v3(o0, rim), col.darkened(0.06))
		_roof_quad(bowl_st, _v3(m0, y_mid), _v3(m1, y_mid), _v3(m1, y_mid + 0.9), _v3(m0, y_mid + 0.9), conc) # concourse fascia
		_roof_quad(bowl_st, _v3(i0, y_field), _v3(i1, y_field), _v3(i1, y_low), _v3(i0, y_low), Color(0.18, 0.20, 0.22)) # field wall
	# grass field (mown stripes) on the inner ring
	var tri := Geometry2D.triangulate_polygon(inner)
	for k in range(0, tri.size(), 3):
		var a := inner[tri[k]]
		var stripe := int(floor((a.x + a.y) / 9.0)) % 2 == 0
		_roof_tri(bowl_st, _v3(a, y_field), _v3(inner[tri[k + 1]], y_field), _v3(inner[tri[k + 2]], y_field), Color(0.24, 0.48, 0.20) if stripe else Color(0.27, 0.53, 0.23))
	# floodlight masts at four points round the rim
	for q in range(4):
		var pm := ro[(q * n / 4 + n / 8) % n]
		var mh := rim + 16.0
		_emit_colored_box(frame_st, Transform3D(Basis.IDENTITY, Vector3(pm.x, mh * 0.5, pm.y)), Vector3(0.9, mh, 0.9), Color(0.55, 0.56, 0.58))
		var toward := (ri[(q * n / 4 + n / 8 + best_k) % n] - pm).normalized()
		var lp := pm + toward * 1.2
		_emit_colored_box(frame_st, Transform3D(Basis(Vector3.UP, atan2(toward.x, toward.y)), Vector3(lp.x, mh + 1.2, lp.y)), Vector3(7.0, 3.2, 0.6), Color(0.92, 0.92, 0.86))


static func _resample_ring(poly: PackedVector2Array, n: int) -> PackedVector2Array:
	var total := 0.0
	for i in range(poly.size()):
		total += poly[i].distance_to(poly[(i + 1) % poly.size()])
	var out := PackedVector2Array()
	var step := total / float(n)
	var seg := 0
	var seg_pos := 0.0
	for k in range(n):
		var target := step * float(k)
		while seg < poly.size():
			var a := poly[seg]
			var b := poly[(seg + 1) % poly.size()]
			var L := a.distance_to(b)
			if seg_pos + L >= target or seg == poly.size() - 1:
				var t := 0.0 if L < 1e-6 else clampf((target - seg_pos) / L, 0.0, 1.0)
				out.append(a.lerp(b, t))
				break
			seg_pos += L
			seg += 1
	return out


# Oriented box of a 2D outline: [centre, long axis, half length, half width]
static func _obb2d(poly: PackedVector2Array) -> Array:
	var best: Array = []
	var best_a := 1e18
	for i in range(poly.size()):
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() < 0.5:
			continue
		var u := e.normalized()
		var v := Vector2(-u.y, u.x)
		var lo_u := 1e18
		var hi_u := -1e18
		var lo_v := 1e18
		var hi_v := -1e18
		for p in poly:
			lo_u = minf(lo_u, p.dot(u))
			hi_u = maxf(hi_u, p.dot(u))
			lo_v = minf(lo_v, p.dot(v))
			hi_v = maxf(hi_v, p.dot(v))
		var a := (hi_u - lo_u) * (hi_v - lo_v)
		if a < best_a:
			best_a = a
			var c := u * (lo_u + hi_u) * 0.5 + v * (lo_v + hi_v) * 0.5
			if hi_u - lo_u >= hi_v - lo_v:
				best = [c, u, (hi_u - lo_u) * 0.5, (hi_v - lo_v) * 0.5]
			else:
				best = [c, v, (hi_v - lo_v) * 0.5, (hi_u - lo_u) * 0.5]
	return best


# Stadium roofs: T-Mobile Park's retractable roof (three arched panels, parked to the east over the rail
# yards), Lumen Field's two arch-supported canopies over the side stands, Husky Stadium's cantilevered canopies
static func _emit_stadium_roof(rst: SurfaceTool, fst: SurfaceTool, outer: PackedVector2Array, rim: float, kind: String) -> void:
	var ob := _obb2d(outer)
	if ob.is_empty():
		return
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var hl: float = ob[2]
	var hw: float = ob[3]
	var v := Vector2(-u.y, u.x)
	var steel := Color(0.56, 0.58, 0.60)
	var membrane := Color(0.86, 0.87, 0.86)
	if kind == "retractable":
		# panels span north-south and slide east-west: park them east of the bowl
		var ns := u if absf(u.y) > absf(u.x) else v
		var ew := Vector2(-ns.y, ns.x)
		if ew.x < 0.0:
			ew = -ew
		var span := (hl if ns == u else hw) + 12.0
		var ext_e := 0.0
		for p in outer:
			ext_e = maxf(ext_e, (p - c).dot(ew))
		var steps := 16
		for k in range(3):
			var pc := c + ew * (ext_e - 30.0 + float(k) * 22.0)
			var top := rim + 42.0 - float(k) * 4.0
			var half_w := 26.0
			for i in range(steps):
				var t0 := -1.0 + 2.0 * float(i) / float(steps)
				var t1 := -1.0 + 2.0 * float(i + 1) / float(steps)
				var y0 := rim + 6.0 + (top - rim - 6.0) * (1.0 - t0 * t0)
				var y1 := rim + 6.0 + (top - rim - 6.0) * (1.0 - t1 * t1)
				var a0 := pc + ns * (t0 * span)
				var a1 := pc + ns * (t1 * span)
				_roof_quad(rst, _v3(a0 - ew * half_w, y0), _v3(a1 - ew * half_w, y1), _v3(a1 + ew * half_w, y1), _v3(a0 + ew * half_w, y0), membrane.darkened(0.05 * float(k)))
				for sd: float in [-1.0, 1.0]:
					_beam3(fst, _v3(a0 + ew * (half_w * sd), y0 - 1.5), _v3(a1 + ew * (half_w * sd), y1 - 1.5), 1.6, steel)
			# the bogies carrying each panel on its rails at both ends
			for sd2: float in [-1.0, 1.0]:
				var bp := pc + ns * (span * sd2)
				_emit_colored_box(fst, Transform3D(Basis(Vector3.UP, atan2(ew.x, ew.y)), Vector3(bp.x, (rim + 6.0) * 0.5, bp.y)), Vector3(half_w * 2.0, rim + 6.0, 6.0), steel.darkened(0.1))
		return
	for sd3: float in [-1.0, 1.0]:
		var steps2 := 18
		for i in range(steps2):
			var t0 := -0.82 + 1.64 * float(i) / float(steps2)
			var t1 := -0.82 + 1.64 * float(i + 1) / float(steps2)
			var o0 := c + u * (t0 * hl) + v * (sd3 * hw * 0.98)
			var o1 := c + u * (t1 * hl) + v * (sd3 * hw * 0.98)
			var i0 := c + u * (t0 * hl) + v * (sd3 * hw * 0.42)
			var i1 := c + u * (t1 * hl) + v * (sd3 * hw * 0.42)
			if kind == "arch_canopy":
				var ya0 := rim + 10.0 + 10.0 * (1.0 - t0 * t0 / 0.67)
				var ya1 := rim + 10.0 + 10.0 * (1.0 - t1 * t1 / 0.67)
				_roof_quad(rst, _v3(o0, ya0), _v3(o1, ya1), _v3(i1, ya1 - 6.0), _v3(i0, ya0 - 6.0), membrane)
				# the big arch along the canopy's top edge
				var ar0 := rim + 14.0 + 26.0 * (1.0 - t0 * t0 / 0.67)
				var ar1 := rim + 14.0 + 26.0 * (1.0 - t1 * t1 / 0.67)
				_beam3(fst, _v3(o0.lerp(i0, 0.25), ar0), _v3(o1.lerp(i1, 0.25), ar1), 2.4, steel)
				if i % 3 == 0:
					_beam3(fst, _v3(o0.lerp(i0, 0.25), ar0), _v3(o0.lerp(i0, 0.25), ya0 - 1.0), 0.6, steel)
			else:
				_roof_quad(rst, _v3(o0, rim + 9.0), _v3(o1, rim + 9.0), _v3(i1, rim + 12.0), _v3(i0, rim + 12.0), membrane)
				if i % 2 == 0:
					_beam3(fst, _v3(o0, rim), _v3(i0, rim + 12.0), 0.7, steel)
		if kind == "arch_canopy":
			# arch feet
			for e2: float in [-0.82, 0.82]:
				var fp := c + u * (e2 * hl) + v * (sd3 * hw * 0.85)
				_emit_colored_box(fst, Transform3D(Basis.IDENTITY, Vector3(fp.x, rim * 0.5 + 6.0, fp.y)), Vector3(3.0, rim + 12.0, 3.0), steel.darkened(0.15))


static func _beam3(st: SurfaceTool, a: Vector3, b: Vector3, th: float, col: Color) -> void:
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
	var cs: Array[Vector3] = [side + upv, -side + upv, -side - upv, side - upv]
	for k in range(4):
		var c0: Vector3 = cs[k]
		var c1: Vector3 = cs[(k + 1) % 4]
		_add_colored_quad(st, a + c0, a + c1, b + c1, b + c0, (c0 + c1).normalized(), col)


# Collegiate Gothic: buttresses along the long walls, pinnacles at the corners, finials on the gable peaks
static func _emit_gothic(fst: SurfaceTool, poly: PackedVector2Array, h: float, roof: Dictionary, stone: Color) -> void:
	for i in range(poly.size()):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var e := p1 - p0
		var el := e.length()
		if el < 7.0:
			continue
		var d := e / el
		var nrm := Vector2(-d.y, d.x)
		var n_b := int(floor(el / 6.5))
		for k in range(1, n_b):
			var bp := p0 + d * (el * float(k) / float(n_b)) + nrm * 0.45
			_emit_colored_box(fst, Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(bp.x, h * 0.45, bp.y)), Vector3(0.8, h * 0.9, 0.9), stone)
			_emit_colored_box(fst, Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(bp.x, h * 0.93, bp.y)), Vector3(0.55, h * 0.16, 0.6), stone.lightened(0.05))
	# corner pinnacles where the outline turns outward
	var ccw := not Geometry2D.is_polygon_clockwise(poly)
	for i in range(poly.size()):
		var a := poly[(i - 1 + poly.size()) % poly.size()]
		var b := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var cross := (b - a).cross(c - b)
		if (cross > 0.0) != ccw or (b - a).length() < 3.0 or (c - b).length() < 3.0:
			continue
		_pinnacle(fst, b, h, 1.1, 4.0, stone)
	# gable peak finials
	var cc: Array = roof.get("c", [0.0, 0.0])
	var cv := Vector2(float(cc[0]), float(cc[1]))
	var ang := float(roof.get("a", 0.0))
	var u := Vector2(cos(ang), sin(ang))
	for sgn: float in [-1.0, 1.0]:
		var gp := cv + u * (float(roof.get("hl", 4.0)) * sgn)
		_pinnacle(fst, gp, h + float(roof.get("h", 3.0)), 0.7, 2.6, stone)


static func _pinnacle(fst: SurfaceTool, p: Vector2, base_y: float, w: float, shaft: float, col: Color) -> void:
	_emit_colored_box(fst, Transform3D(Basis.IDENTITY, Vector3(p.x, base_y + shaft * 0.5, p.y)), Vector3(w, shaft, w), col)
	var top := Vector3(p.x, base_y + shaft + w * 2.6, p.y)
	var hw := w * 0.55
	var cs: Array[Vector3] = [Vector3(p.x - hw, base_y + shaft, p.y - hw), Vector3(p.x + hw, base_y + shaft, p.y - hw), Vector3(p.x + hw, base_y + shaft, p.y + hw), Vector3(p.x - hw, base_y + shaft, p.y + hw)]
	for k in range(4):
		var a: Vector3 = cs[k]
		var b: Vector3 = cs[(k + 1) % 4]
		var n := (b - a).cross(top - a).normalized()
		for vv: Vector3 in [a, b, top]:
			fst.set_color(col.lightened(0.05))
			fst.set_normal(n)
			fst.add_vertex(vv)


# Church bell tower(s) at the gable end with a spire (twin towers for a cathedral)
static func _emit_church_towers(st: SurfaceTool, rst: SurfaceTool, roof: Dictionary, h: float, twin: bool, wcol: Color, rcol: Color) -> void:
	var cc: Array = roof.get("c", [0.0, 0.0])
	var c := Vector2(float(cc[0]), float(cc[1]))
	var ang := float(roof.get("a", 0.0))
	var u := Vector2(cos(ang), sin(ang))
	var v := Vector2(-u.y, u.x)
	var hl := float(roof.get("hl", 6.0))
	var hw := float(roof.get("hw", 4.0))
	var ts := clampf(hw * (0.7 if twin else 0.9), 4.0, 9.0)
	var ht := h * 1.6 + float(roof.get("h", 4.0)) + 6.0
	var centres: Array[Vector2] = []
	if twin:
		centres.append(c + u * (hl - ts * 0.5) + v * (hw - ts * 0.5))
		centres.append(c + u * (hl - ts * 0.5) - v * (hw - ts * 0.5))
	else:
		centres.append(c + u * (hl - ts * 0.5))
	for tc: Vector2 in centres:
		var sq := PackedVector2Array([tc + (-u - v) * ts * 0.5, tc + (u - v) * ts * 0.5, tc + (u + v) * ts * 0.5, tc + (-u + v) * ts * 0.5])
		if Geometry2D.is_polygon_clockwise(sq):
			sq.reverse()
		_tower_walls(st, sq, 0.0, ht, wcol)
		var apex := Vector3(tc.x, ht + ts * 2.4, tc.y)
		for k in range(4):
			_roof_tri(rst, _v3(sq[k], ht), _v3(sq[(k + 1) % 4], ht), apex, rcol)


static func _tower_walls(st: SurfaceTool, sq: PackedVector2Array, y0: float, y1: float, wcol: Color) -> void:
	var u_acc := 0.0
	for k in range(sq.size()):
		var p0 := sq[k]
		var p1 := sq[(k + 1) % sq.size()]
		var e := p1 - p0
		var el := e.length()
		var d := e / maxf(el, 0.001)
		_emit_wall_quad(st, Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y), Vector3(-d.y, 0.0, d.x), u_acc, u_acc + el, y0, y1, wcol)
		u_acc += el


# King Street Station's clock tower (after St Mark's campanile in Venice): 74 m brick shaft, clock faces,
# open belfry stage and a pyramid cap, at the station's north end
static func _emit_campanile(st: SurfaceTool, rst: SurfaceTool, fst: SurfaceTool, poly: PackedVector2Array, wcol: Color, own_shaft_h: float = -1.0) -> void:
	var north := poly[0]
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
		if p.y < north.y:
			north = p
	cen /= float(poly.size())
	var tc := north + (cen - north).normalized() * 7.0
	var s := 8.5
	var shaft := 58.0
	if own_shaft_h > 0.0:
		# the tower is already a building part (OSM 3D): crown its shaft
		var ob := _obb2d(poly)
		tc = cen
		s = clampf(float(ob[3]) * 2.0 if not ob.is_empty() else 8.0, 5.0, 12.0)
		shaft = own_shaft_h - 10.0
	var sq := PackedVector2Array([tc + Vector2(-s, -s) * 0.5, tc + Vector2(s, -s) * 0.5, tc + Vector2(s, s) * 0.5, tc + Vector2(-s, s) * 0.5])
	if Geometry2D.is_polygon_clockwise(sq):
		sq.reverse()
	if own_shaft_h <= 0.0:
		_tower_walls(st, sq, 0.0, shaft, wcol)
	var stone := Color(0.84, 0.80, 0.72)
	_emit_colored_box(fst, Transform3D(Basis.IDENTITY, Vector3(tc.x, shaft + 0.6, tc.y)), Vector3(s + 1.2, 1.2, s + 1.2), stone)
	# belfry stage: four corner piers
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			_emit_colored_box(fst, Transform3D(Basis.IDENTITY, Vector3(tc.x + cx * (s * 0.5 - 0.7), shaft + 5.0, tc.y + cz * (s * 0.5 - 0.7))), Vector3(1.4, 8.0, 1.4), stone)
	_emit_colored_box(fst, Transform3D(Basis.IDENTITY, Vector3(tc.x, shaft + 9.6, tc.y)), Vector3(s + 0.8, 1.2, s + 0.8), stone)
	var apex := Vector3(tc.x, shaft + 10.2 + 9.0, tc.y)
	for k in range(4):
		_roof_tri(rst, _v3(sq[k], shaft + 10.2), _v3(sq[(k + 1) % 4], shaft + 10.2), apex, Color(0.36, 0.42, 0.40))
	# clock faces on all four sides
	for k in range(4):
		var a := sq[k]
		var b := sq[(k + 1) % 4]
		var mid := (a + b) * 0.5
		var out := (mid - tc).normalized()
		var fc := mid + out * 0.08
		var along := (b - a).normalized()
		var r := 2.4
		var yc := shaft - 5.0
		var prev := Vector3.ZERO
		for q in range(17):
			var t := TAU * float(q) / 16.0
			var pt := Vector3(fc.x + along.x * cos(t) * r, yc + sin(t) * r, fc.y + along.y * cos(t) * r)
			if q > 0:
				for vv: Vector3 in [Vector3(fc.x, yc, fc.y), prev, pt]:
					fst.set_color(Color(0.95, 0.94, 0.88))
					fst.set_normal(Vector3(out.x, 0.0, out.y))
					fst.add_vertex(vv)
			prev = pt


# House: plain siding walls up to the eave (flat cap when there is no pitched roof), then a gabled /
# hipped / pyramidal / skillion roof over the footprint's oriented box (OSM roof:shape or estimated).
static func _emit_house(st: SurfaceTool, roof_st: SurfaceTool, poly: PackedVector2Array, h: float, roof: Dictionary, wcol: Color, rcol: Color) -> void:
	var u_acc := 0.0
	for i in range(poly.size()):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var e := p1 - p0
		var el := e.length()
		if el < 0.1:
			continue
		var d2 := e / el
		var n3 := Vector3(-d2.y, 0.0, d2.x)
		_emit_wall_quad(st, Vector3(p0.x, 0.0, p0.y), Vector3(p1.x, 0.0, p1.y), Vector3(p1.x, h, p1.y), Vector3(p0.x, h, p0.y), n3, u_acc, u_acc + el, 0.0, h, wcol)
		u_acc += el
	if roof.is_empty():
		var tri := Geometry2D.triangulate_polygon(poly)
		for k in range(0, tri.size(), 3):
			for rp: Vector2 in [poly[tri[k]], poly[tri[k + 1]], poly[tri[k + 2]]]:
				st.set_color(wcol)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(Vector3(rp.x, h, rp.y))
		return
	_emit_roof(st, roof_st, roof, h, wcol, rcol)


# Pitched roof over a footprint's oriented box (house, Gothic hall, church), eaves at height h
static func _emit_roof(st: SurfaceTool, roof_st: SurfaceTool, roof: Dictionary, h: float, wcol: Color, rcol: Color) -> void:
	var cc: Array = roof.get("c", [0.0, 0.0])
	var c := Vector2(float(cc[0]), float(cc[1]))
	var ang := float(roof.get("a", 0.0))
	var u := Vector2(cos(ang), sin(ang))
	var v := Vector2(-u.y, u.x)
	var hl := float(roof.get("hl", 4.0))
	var hw := float(roof.get("hw", 3.0))
	var rh := float(roof.get("h", 2.5))
	var shape := str(roof.get("shape", "gabled"))
	var ov := 0.38 # eave overhang
	var L := hl + ov
	var W := hw + ov
	var y0 := h - 0.12 # eaves sit a touch below the wall top: no light gap
	var y1 := h + rh

	if shape == "pyramidal" or (shape == "hipped" and hl <= hw * 1.02):
		var apex := Vector3(c.x, y1, c.y)
		var cs: Array = [c - u * L - v * W, c + u * L - v * W, c + u * L + v * W, c - u * L + v * W]
		for k in range(4):
			_roof_tri(roof_st, _v3(cs[k], y0), _v3(cs[(k + 1) % 4], y0), apex, rcol)
	elif shape == "hipped":
		var rr := L - W # ridge half length
		var ra := Vector3((c - u * rr).x, y1, (c - u * rr).y)
		var rb := Vector3((c + u * rr).x, y1, (c + u * rr).y)
		var a0 := _v3(c - u * L - v * W, y0)
		var a1 := _v3(c + u * L - v * W, y0)
		var a2 := _v3(c + u * L + v * W, y0)
		var a3 := _v3(c - u * L + v * W, y0)
		_roof_quad(roof_st, a0, a1, rb, ra, rcol)
		_roof_quad(roof_st, a2, a3, ra, rb, rcol)
		_roof_tri(roof_st, a1, a2, rb, rcol)
		_roof_tri(roof_st, a3, a0, ra, rcol)
	elif shape == "skillion":
		var lo0 := _v3(c - u * L - v * W, y0)
		var lo1 := _v3(c + u * L - v * W, y0)
		var hi1 := _v3(c + u * L + v * W, y1)
		var hi0 := _v3(c - u * L + v * W, y1)
		_roof_quad(roof_st, lo0, lo1, hi1, hi0, rcol)
		# raised wall under the high eave and the two side triangles (siding)
		_gable_end(st, c + v * hw, u, hl, h, h + rh * 0.96, wcol, true)
		_gable_wedge(st, c - u * hl, -u, v, hw, h, rh, wcol)
		_gable_wedge(st, c + u * hl, u, v, hw, h, rh, wcol)
	else: # gabled: ridge along the long axis, siding gable triangles at both ends
		var ra2 := _v3(c - u * L, y1)
		var rb2 := _v3(c + u * L, y1)
		_roof_quad(roof_st, _v3(c - u * L - v * W, y0), _v3(c + u * L - v * W, y0), rb2, ra2, rcol)
		_roof_quad(roof_st, _v3(c + u * L + v * W, y0), _v3(c - u * L + v * W, y0), ra2, rb2, rcol)
		for sgn: float in [-1.0, 1.0]:
			var ec := c + u * (hl * sgn)
			var n2 := u * sgn
			var d := Vector2(n2.y, -n2.x)
			var b0 := Vector3((ec - d * hw).x, h, (ec - d * hw).y)
			var b1 := Vector3((ec + d * hw).x, h, (ec + d * hw).y)
			var ap := Vector3(ec.x, y1 - 0.05, ec.y)
			var n3 := Vector3(n2.x, 0.0, n2.y)
			st.set_color(wcol); st.set_normal(n3); st.set_uv(Vector2(0.0, h)); st.add_vertex(b0)
			st.set_color(wcol); st.set_normal(n3); st.set_uv(Vector2(hw * 2.0, h)); st.add_vertex(b1)
			st.set_color(wcol); st.set_normal(n3); st.set_uv(Vector2(hw, y1)); st.add_vertex(ap)


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


static func _roof_tri(rst: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var shade := col * (0.86 + 0.14 * clampf(n.dot(Vector3(0.45, 0.8, 0.4).normalized()), 0.0, 1.0))
	shade.a = 1.0
	for p: Vector3 in [a, b, c]:
		rst.set_color(shade)
		rst.set_normal(n)
		rst.add_vertex(p)


static func _roof_quad(rst: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_roof_tri(rst, a, b, c, col)
	_roof_tri(rst, a, c, d, col)


# Raised siding wall along a skillion's high eave (outward normal `side` direction from the centre)
static func _gable_end(st: SurfaceTool, mid: Vector2, along: Vector2, half: float, yb: float, yt: float, wcol: Color, _hi: bool) -> void:
	var p0 := mid - along * half
	var p1 := mid + along * half
	var e := (p1 - p0).normalized()
	var n3 := Vector3(-e.y, 0.0, e.x)
	_emit_wall_quad(st, Vector3(p0.x, yb, p0.y), Vector3(p1.x, yb, p1.y), Vector3(p1.x, yt, p1.y), Vector3(p0.x, yt, p0.y), n3, 0.0, half * 2.0, yb, yt, wcol)


# Triangular siding wedge under a skillion roof at one end of the box
static func _gable_wedge(st: SurfaceTool, ec: Vector2, out_u: Vector2, v: Vector2, hw: float, h: float, rh: float, wcol: Color) -> void:
	var n3 := Vector3(out_u.x, 0.0, out_u.y)
	var lo := ec - v * hw
	var hi := ec + v * hw
	var verts: Array = [Vector3(lo.x, h, lo.y), Vector3(hi.x, h, hi.y), Vector3(hi.x, h + rh, hi.y)]
	if Vector2(-(hi - lo).y, (hi - lo).x).dot(out_u) < 0.0:
		verts = [Vector3(hi.x, h, hi.y), Vector3(lo.x, h, lo.y), Vector3(hi.x, h + rh, hi.y)]
	for k in range(3):
		var vv: Vector3 = verts[k]
		st.set_color(wcol); st.set_normal(n3); st.set_uv(Vector2(float(k) * hw, vv.y)); st.add_vertex(vv)


static func _extrude_tier_with_3d_relief(
	st: SurfaceTool,
	frame_st: SurfaceTool,
	poly: PackedVector2Array,
	y_bot: float,
	y_top: float,
	style: int,
	vcol: Color,
	trim_c: Color,
	include_ground_cornice: bool,
	balc: Dictionary = {}
) -> void:
	var parapet_h := 0.90 if style != 0 else 1.15
	var max_edge := 0.0
	for i in range(poly.size()):
		max_edge = maxf(max_edge, poly[i].distance_to(poly[(i + 1) % poly.size()]))
	var wall_top := y_top + parapet_h
	var u_accum := 0.0
	var pier_spacing := 5.55 if style == 0 else (6.0 if style == 1 else 6.8)
	var pier_depth := 0.22 if style == 0 else 0.28
	var pier_hw := 0.16 if style == 0 else 0.24

	for i in range(poly.size()):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var edge := p1 - p0
		var elen := edge.length()
		if elen < 0.10:
			continue
		var dir2 := edge / elen
		var nrm2 := Vector2(-dir2.y, dir2.x)
		var nrm3 := Vector3(nrm2.x, 0.0, nrm2.y)

		var u0 := u_accum
		var u1 := u_accum + elen
		u_accum = u1

		# 1. Main recessed window/facade wall
		_emit_wall_quad(
			st,
			Vector3(p0.x, y_bot, p0.y),
			Vector3(p1.x, y_bot, p1.y),
			Vector3(p1.x, wall_top, p1.y),
			Vector3(p0.x, wall_top, p0.y),
			nrm3,
			u0,
			u1,
			y_bot,
			wall_top,
			vcol
		)

		# 1b. Balconies on the long facades (residential): slab, parapet and side returns per balcony bay
		if not balc.is_empty() and elen >= 9.0 and elen >= max_edge * 0.55:
			if _emit_balconies(balc, p0, dir2, nrm2, u0, u1, y_bot, y_top):
				balc["used"] = true

		# 2. 3D Corner Pilasters + Intermediate Vertical Structural Columns!
		var bays := maxi(1, int(round(elen / pier_spacing)))
		for b_k in range(bays + 1):
			# Skip end pier if not corner? Including both ends forms crisp corner columns!
			if b_k == bays:
				continue
			var t_k := float(b_k) / float(bays)
			var pc := p0.lerp(p1, t_k)
			var hw_use := pier_hw * (1.45 if b_k == 0 else 1.0)
			_emit_3d_beam_along_wall(
				frame_st,
				pc - dir2 * hw_use,
				pc + dir2 * hw_use,
				nrm2,
				y_bot,
				wall_top,
				pier_depth,
				trim_c
			)

		# 3. 3D Projecting Ground-Floor Retail Cornice (at y = 4.55m)
		if include_ground_cornice and (y_top - y_bot) > 8.0 and y_bot < 0.5:
			_emit_3d_beam_along_wall(
				frame_st,
				p0,
				p1,
				nrm2,
				4.42,
				4.78,
				pier_depth + 0.12,
				trim_c.lightened(0.05)
			)

		# 4. Intermediate 3D Stone Belt Courses / Spandrel Ledges every ~14.6m
		var belt_y := y_bot + 14.8
		while belt_y < y_top - 4.5:
			_emit_3d_beam_along_wall(
				frame_st,
				p0,
				p1,
				nrm2,
				belt_y,
				belt_y + 0.32,
				pier_depth + 0.06,
				trim_c
			)
			belt_y += 14.8

		# 5. Bold 3D Overhanging Roof Cornice & Parapet Coping Cap!
		var cornice_overhang := 0.44 if style == 1 else 0.30
		_emit_3d_beam_along_wall(
			frame_st,
			p0 - dir2 * 0.15,
			p1 + dir2 * 0.15,
			nrm2,
			wall_top - 0.48,
			wall_top + 0.08,
			cornice_overhang,
			trim_c.lightened(0.08)
		)

	# Recessed flat roof cap at y_top
	var tri := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tri.size(), 3):
		for rp: Vector2 in [poly[tri[i]], poly[tri[i + 1]], poly[tri[i + 2]]]:
			st.set_color(vcol)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(Vector3(rp.x, y_top, rp.y))


const BALC_CELL := 120.0 # balcony mesh cell size (m)
const BALC_VIS := 320.0 # balconies drawn within this distance of their cell


# Balconies on one wall edge (u0..u1 along the facade, as the facade shader counts it). Returns true if any.
static func _emit_balconies(balc: Dictionary, p0: Vector2, dir2: Vector2, nrm2: Vector2, u0: float, u1: float, y_bot: float, y_top: float) -> bool:
	var bst: SurfaceTool = balc["st"]
	var fh := float(balc["fh"])
	var bw := float(balc["bw"])
	var zh := bool(balc["zh"])
	var seed_f := float(balc["seed"])
	var depth := float(balc["depth"])
	var slab_c: Color = balc["slab"]
	var rail_c: Color = balc["rail"]
	var x_in := 0.08 if zh else 0.12
	var basis := Basis(Vector3(dir2.x, 0.0, dir2.y), Vector3.UP, Vector3(nrm2.x, 0.0, nrm2.y))
	var k0 := int(ceil(maxf(float(balc["y0"]), y_bot + 0.5) / fh))
	var any := false
	var bay := int(ceil((u0 + 0.4) / bw))
	while float(bay + 1) * bw <= u1 - 0.4:
		var is_balc := posmod(bay + int(floor(seed_f * 0.5)), 2) == 0 if zh else posmod(bay, 2) == 0
		if is_balc:
			var xa := (float(bay) + x_in) * bw - u0
			var xb := (float(bay) + 1.0 - x_in) * bw - u0
			var w := xb - xa
			var k := k0
			while float(k) * fh + fh <= y_top + 0.05:
				var yk := float(k) * fh
				var mid := p0 + dir2 * ((xa + xb) * 0.5)
				# floor slab (top flush with the floor line)
				_emit_colored_box(bst, Transform3D(basis, Vector3(mid.x, yk - 0.09, mid.y) + basis.z * (depth * 0.5)), Vector3(w + 0.10, 0.18, depth), slab_c)
				# front parapet
				_emit_colored_box(bst, Transform3D(basis, Vector3(mid.x, yk + 0.52, mid.y) + basis.z * (depth - 0.06)), Vector3(w + 0.10, 1.04, 0.12), rail_c)
				# side returns (Seattle's deep open balconies; Jiaxing's glazed balconies read fine without, and the
				# 18-33 storey towers there would otherwise double the balcony triangle count)
				for sx: float in ([] if zh else [-0.5, 0.5]):
					_emit_colored_box(bst, Transform3D(basis, Vector3(mid.x, yk + 0.52, mid.y) + basis.x * (sx * (w + 0.10) - signf(sx) * 0.05) + basis.z * (depth * 0.5)), Vector3(0.10, 1.04, depth - 0.02), rail_c)
				any = true
				k += 1
		bay += 1
	return any


# Building massing: [[poly, y_bot, y_top], ...]. Long slab blocks step down at one or both ends (退台);
# point towers get a set-back crown of their top two floors; small or low buildings stay one volume.
static func _massing_pieces(poly: PackedVector2Array, h: float, fh: float) -> Array:
	var one: Array = [[poly, 0.0, h]]
	if h < 12.0:
		return one
	var ob := _obb2d(poly)
	if ob.is_empty():
		return one
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var hl := float(ob[2])
	var hs := float(ob[3])
	var v := Vector2(-u.y, u.x)
	var rnd := absf(sin(poly[0].x * 12.9898 + poly[0].y * 78.233) * 43758.5453)
	rnd = rnd - floor(rnd)
	var floors := int(round(h / fh))
	if hl * 2.0 >= 34.0 and hl >= hs * 2.0 and floors >= 5:
		var cuts: Array[float] = [-hl]
		var drops: Array = []
		if hl * 2.0 >= 56.0:
			cuts.append(-hl + hl * 2.0 * (0.20 + 0.10 * rnd))
			cuts.append(hl - hl * 2.0 * (0.20 + 0.10 * fposmod(rnd * 7.0, 1.0)))
			drops = [1 + int(rnd * 3.0) % 3, 0, (2 + int(rnd * 5.0)) % 4]
		else:
			cuts.append(-hl + hl * 2.0 * (0.36 + 0.14 * rnd))
			drops = [0, 1 + int(rnd * 4.0) % 3] if rnd < 0.5 else [1 + int(rnd * 4.0) % 3, 0]
		cuts.append(hl)
		var out: Array = []
		for i in range(cuts.size() - 1):
			var a := cuts[i]
			var bb := cuts[i + 1]
			var ext := hs + 4.0
			var rect := PackedVector2Array([c + u * a - v * ext, c + u * bb - v * ext, c + u * bb + v * ext, c + u * a + v * ext])
			var hp := maxf(fh * 3.0, h - float(mini(int(drops[i]), floors - 3)) * fh)
			for part: PackedVector2Array in Geometry2D.intersect_polygons(poly, rect):
				if part.size() < 3 or absf(_poly_area(part)) < 25.0:
					continue
				var pp := part
				if Geometry2D.is_polygon_clockwise(pp):
					pp.reverse()
				out.append([pp, 0.0, hp])
		return out if not out.is_empty() else one
	if h >= 27.0 and hs * 2.0 >= 12.0 and floors >= 9:
		var inset := Geometry2D.offset_polygon(poly, -1.6)
		if inset.size() == 1 and inset[0].size() >= 3 and absf(_poly_area(inset[0])) > absf(_poly_area(poly)) * 0.45:
			var crown: PackedVector2Array = inset[0]
			if Geometry2D.is_polygon_clockwise(crown):
				crown.reverse()
			var hb := h - fh * 2.0
			return [[poly, 0.0, hb], [crown, hb, h]]
	return one


# Contemporary Chinese high-rise residential facade (2010s-2020s 高层住宅): continuous vertical lines (竖向线条)
# at every unit pair, a two-storey crown band and the lines rising past the roof as a decorative top frame
static func _emit_zh_tower_lines(fst: SurfaceTool, poly: PackedVector2Array, top: float, line_c: Color, wall_c: Color, crown: bool) -> void:
	var bw := 4.2 * 2.0
	var y0 := 4.6
	var rise := 2.6 if crown else 0.0
	var band_c := wall_c.lerp(Color(0.95, 0.94, 0.91), 0.55)
	for i in range(poly.size()):
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var elen := p0.distance_to(p1)
		if elen < 10.0:
			continue
		var dir2 := (p1 - p0) / elen
		var nrm2 := Vector2(-dir2.y, dir2.x)
		var basis := Basis(Vector3(dir2.x, 0.0, dir2.y), Vector3.UP, Vector3(nrm2.x, 0.0, nrm2.y))
		var n_seg := int(floor(elen / bw))
		var lead := (elen - float(n_seg) * bw) * 0.5
		for k in range(n_seg + 1):
			var u := lead + float(k) * bw
			if u < 0.6 or u > elen - 0.6:
				continue
			var hgt := top + rise - y0
			var pos := p0 + dir2 * u + nrm2 * 0.20
			_emit_colored_box(fst, Transform3D(basis, Vector3(pos.x, y0 + hgt * 0.5, pos.y)), Vector3(0.36, hgt, 0.40), line_c)
		if crown:
			# crown band over the top two floors + the open frame beam tying the risen lines together
			var mid := (p0 + p1) * 0.5 + nrm2 * 0.12
			_emit_colored_box(fst, Transform3D(basis, Vector3(mid.x, top - 2.4, mid.y)), Vector3(elen - 0.2, 0.55, 0.26), band_c)
			_emit_colored_box(fst, Transform3D(basis, Vector3(mid.x, top + rise - 0.25, mid.y + 0.0) + basis.z * 0.08), Vector3(elen - 0.6, 0.5, 0.40), line_c)
		# corner pilasters in the wall colour, slightly proud of the wall, full height
		var c0 := p0 + dir2 * 0.30 + nrm2 * 0.16
		_emit_colored_box(fst, Transform3D(basis, Vector3(c0.x, (top + rise) * 0.5, c0.y)), Vector3(0.60, top + rise, 0.34), band_c)


# Facade colour of a Chinese residential / mixed-use block: a colour family per ~180 m cell (one compound or
# street block shares it), per-building variation inside the family
static func _zh_facade_colour(p: Vector2, b_hash: int) -> Color:
	var fams: Array = [
		[Color(0.91, 0.89, 0.84), Color(0.88, 0.86, 0.81)], # warm white 真石漆
		[Color(0.94, 0.91, 0.86), Color(0.90, 0.87, 0.81)], # ivory
		[Color(0.86, 0.84, 0.79), Color(0.82, 0.80, 0.75)], # light warm grey
		[Color(0.85, 0.79, 0.70), Color(0.81, 0.75, 0.66)], # light coffee stone
		[Color(0.84, 0.83, 0.80), Color(0.79, 0.78, 0.76)], # grey-white
		[Color(0.89, 0.86, 0.80), Color(0.85, 0.82, 0.75)], # champagne beige
		[Color(0.80, 0.79, 0.77), Color(0.75, 0.74, 0.72)], # mid grey
		[Color(0.66, 0.44, 0.36), Color(0.62, 0.41, 0.33)], # brick (older blocks)
	]
	var cx := int(floor(p.x / 180.0))
	var cy := int(floor(p.y / 180.0))
	var fam_i := absi(cx * 73856093 ^ cy * 19349663) % fams.size()
	if fam_i == 7 and absi(cx * 31 + cy * 17) % 3 != 0:
		fam_i = 1 # brick only now and then
	var fam: Array = fams[fam_i]
	var c := (fam[0] as Color).lerp(fam[1], float(b_hash % 7) / 6.0)
	var jit := (float((b_hash / 7) % 9) - 4.0) * 0.008
	return Color(clampf(c.r + jit, 0.0, 1.0), clampf(c.g + jit, 0.0, 1.0), clampf(c.b + jit, 0.0, 1.0))


static func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


# Roof of a residential tower: stair / lift core housing (楼梯间·电梯机房) with a decorative open frame (屋顶构架)
static func _emit_roof_core(fst: SurfaceTool, poly: PackedVector2Array, h: float, base_c: Color, trim_c: Color, seed_i: int) -> void:
	var ob := _obb2d(poly)
	if ob.is_empty():
		return
	var c: Vector2 = ob[0]
	var u: Vector2 = ob[1]
	var hl := float(ob[2])
	var hs := float(ob[3])
	var basis := Basis(Vector3(u.x, 0.0, u.y), Vector3.UP, Vector3(-u.y, 0.0, u.x))
	var core_l := clampf(hl * 0.42, 4.0, 9.0)
	var core_w := clampf(hs * 0.70, 3.6, 6.5)
	var core_h := 3.4
	var wall := base_c.lerp(Color(0.88, 0.86, 0.82), 0.35)
	var off := (float(seed_i % 3) - 1.0) * minf(hl * 0.3, 6.0)
	var cc := c + u * off
	_emit_colored_box(fst, Transform3D(basis, Vector3(cc.x, h + core_h * 0.5, cc.y)), Vector3(core_l, core_h, core_w), wall)
	# open frame on top of the core: corner posts + perimeter beams + a cross beam
	var fy := h + core_h
	var fhgt := 2.2
	var beam := trim_c.lerp(Color(0.90, 0.88, 0.84), 0.5)
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var pp := Vector3(cc.x, fy + fhgt * 0.5, cc.y) + basis.x * (sx * (core_l + 1.0)) + basis.z * (sz * (core_w + 1.0))
			_emit_colored_box(fst, Transform3D(basis, pp), Vector3(0.35, fhgt, 0.35), beam)
	for sz2: float in [-0.5, 0.5]:
		_emit_colored_box(fst, Transform3D(basis, Vector3(cc.x, fy + fhgt - 0.2, cc.y) + basis.z * (sz2 * (core_w + 1.0))), Vector3(core_l + 1.35, 0.4, 0.35), beam)
	for sx2: float in [-0.5, 0.0, 0.5]:
		_emit_colored_box(fst, Transform3D(basis, Vector3(cc.x, fy + fhgt - 0.2, cc.y) + basis.x * (sx2 * (core_l + 1.0))), Vector3(0.35, 0.4, core_w + 1.35), beam)


static func _emit_3d_beam_along_wall(
	fst: SurfaceTool,
	a2: Vector2,
	b2: Vector2,
	out_nrm2: Vector2,
	yb: float,
	yt: float,
	depth: float,
	col: Color
) -> void:
	var a_out := a2 + out_nrm2 * depth
	var b_out := b2 + out_nrm2 * depth
	var edge := (b2 - a2).normalized()
	var n_front := Vector3(out_nrm2.x, 0.0, out_nrm2.y)
	var n_left := Vector3(-edge.x, 0.0, -edge.y)
	var n_right := Vector3(edge.x, 0.0, edge.y)

	# Front face
	_add_colored_quad(
		fst,
		Vector3(a_out.x, yb, a_out.y),
		Vector3(b_out.x, yb, b_out.y),
		Vector3(b_out.x, yt, b_out.y),
		Vector3(a_out.x, yt, a_out.y),
		n_front,
		col
	)
	# Top ledge face
	_add_colored_quad(
		fst,
		Vector3(a2.x, yt, a2.y),
		Vector3(a_out.x, yt, a_out.y),
		Vector3(b_out.x, yt, b_out.y),
		Vector3(b2.x, yt, b2.y),
		Vector3.UP,
		col.lightened(0.06)
	)
	# Bottom soffit face (casts real upward/downward shading!)
	_add_colored_quad(
		fst,
		Vector3(a_out.x, yb, a_out.y),
		Vector3(a2.x, yb, a2.y),
		Vector3(b2.x, yb, b2.y),
		Vector3(b_out.x, yb, b_out.y),
		Vector3.DOWN,
		col.darkened(0.18)
	)
	# Left & right side cheeks
	_add_colored_quad(
		fst,
		Vector3(a2.x, yb, a2.y),
		Vector3(a_out.x, yb, a_out.y),
		Vector3(a_out.x, yt, a_out.y),
		Vector3(a2.x, yt, a2.y),
		n_left,
		col.darkened(0.06)
	)
	_add_colored_quad(
		fst,
		Vector3(b_out.x, yb, b_out.y),
		Vector3(b2.x, yb, b2.y),
		Vector3(b2.x, yt, b2.y),
		Vector3(b_out.x, yt, b_out.y),
		n_right,
		col.darkened(0.06)
	)


static func _add_colored_quad(
	st: SurfaceTool,
	v0: Vector3,
	v1: Vector3,
	v2: Vector3,
	v3: Vector3,
	nrm: Vector3,
	col: Color
) -> void:
	for v: Vector3 in [v0, v1, v2, v0, v2, v3]:
		st.set_color(col)
		st.set_normal(nrm)
		st.add_vertex(v)


static func _emit_wall_quad(
	st: SurfaceTool,
	b0: Vector3,
	b1: Vector3,
	t1: Vector3,
	t0: Vector3,
	nrm: Vector3,
	u0: float,
	u1: float,
	v0: float,
	v1: float,
	vcol: Color
) -> void:
	st.set_color(vcol); st.set_normal(nrm); st.set_uv(Vector2(u0, v0)); st.add_vertex(b0)
	st.set_color(vcol); st.set_normal(nrm); st.set_uv(Vector2(u1, v0)); st.add_vertex(b1)
	st.set_color(vcol); st.set_normal(nrm); st.set_uv(Vector2(u1, v1)); st.add_vertex(t1)
	st.set_color(vcol); st.set_normal(nrm); st.set_uv(Vector2(u0, v0)); st.add_vertex(b0)
	st.set_color(vcol); st.set_normal(nrm); st.set_uv(Vector2(u1, v1)); st.add_vertex(t1)
	st.set_color(vcol); st.set_normal(nrm); st.set_uv(Vector2(u0, v1)); st.add_vertex(t0)


static func _build_streetlamps(
	parent: Node3D,
	lamps: Array,
	globe_mat: StandardMaterial3D
) -> Array[OmniLight3D]:
	var night_lights: Array[OmniLight3D] = []
	if lamps.is_empty():
		return night_lights
	if (lamps[0] as Array).size() >= 4:
		return _build_led_streetlamps(parent, lamps, globe_mat)
	var count := lamps.size()

	var post_mm := MultiMesh.new()
	post_mm.transform_format = MultiMesh.TRANSFORM_3D
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.065
	cyl.bottom_radius = 0.13
	cyl.height = 4.6
	cyl.radial_segments = 8
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.12, 0.19, 0.15)
	post_mat.metallic = 0.60
	post_mat.roughness = 0.42
	cyl.material = post_mat
	post_mm.mesh = cyl
	post_mm.instance_count = count

	var globe_mm := MultiMesh.new()
	globe_mm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.46
	sph.radial_segments = 10
	sph.rings = 6
	sph.material = globe_mat
	globe_mm.mesh = sph
	globe_mm.instance_count = count

	var light_holder := Node3D.new()
	light_holder.name = "StreetlampPools"
	if Terrain.active:
		light_holder.set_meta("on_terrain", true)
	parent.add_child(light_holder)

	var post_tfs: Array[Transform3D] = []
	var globe_tfs: Array[Transform3D] = []
	for i in range(count):
		var lx := float(lamps[i][0])
		var lz := float(lamps[i][1])
		var dy := Terrain.surface(lx, lz) if Terrain.active else 0.0
		var ptf := Transform3D(Basis.IDENTITY, Vector3(lx, 2.30 + dy, lz))
		var gtf := Transform3D(Basis.IDENTITY, Vector3(lx, 4.72 + dy, lz))
		post_mm.set_instance_transform(i, ptf)
		globe_mm.set_instance_transform(i, gtf)
		post_tfs.append(ptf)
		globe_tfs.append(gtf)

		# Spaced streetlamps cast warm pools of light at night (disabled in daytime & distance-faded!)
		if i % 14 == 0:
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.84, 0.58)
			ol.light_energy = 0.0
			ol.visible = false
			ol.omni_range = 19.0
			ol.omni_attenuation = 1.35
			ol.distance_fade_enabled = true
			ol.distance_fade_begin = 95.0
			ol.distance_fade_length = 35.0
			ol.position = Vector3(lx, 4.55 + dy, lz)
			light_holder.add_child(ol)
			night_lights.append(ol)

	var p_inst := MultiMeshInstance3D.new()
	p_inst.name = "StreetlampPosts"
	p_inst.multimesh = post_mm
	p_inst.set_meta("base_tfs", post_tfs)
	if Terrain.active:
		p_inst.set_meta("on_terrain", true)
	parent.add_child(p_inst)

	var g_inst := MultiMeshInstance3D.new()
	g_inst.name = "StreetlampGlobes"
	g_inst.multimesh = globe_mm
	g_inst.set_meta("base_tfs", globe_tfs)
	g_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if Terrain.active:
		g_inst.set_meta("on_terrain", true)
	parent.add_child(g_inst)

	return night_lights


# Chinese urban road lighting (嘉兴城市道路照明): 10 m tapered grey steel pole, a single upswept arm reaching
# over the carriageway and a flat LED luminaire. Lamps carry [x, z, arm_dir_x, arm_dir_z].
static func _build_led_streetlamps(parent: Node3D, lamps: Array, head_mat: StandardMaterial3D) -> Array[OmniLight3D]:
	var night_lights: Array[OmniLight3D] = []
	var count := lamps.size()
	const POLE_H := 10.0
	const ARM_L := 2.3
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.56, 0.58, 0.60)
	steel.metallic = 0.55
	steel.roughness = 0.40
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.075
	cyl.bottom_radius = 0.14
	cyl.height = POLE_H
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.material = steel
	var arm := BoxMesh.new()
	arm.size = Vector3(0.07, 0.07, ARM_L)
	arm.material = steel
	var head := BoxMesh.new()
	head.size = Vector3(0.34, 0.11, 0.78)
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.40, 0.42, 0.45)
	housing.metallic = 0.5
	housing.roughness = 0.45
	head.material = housing
	# the lens under the housing glows at night (shared street-globe material toggles its emission)
	var lens := BoxMesh.new()
	lens.size = Vector3(0.26, 0.02, 0.64)
	lens.material = head_mat
	var mms: Array[MultiMesh] = []
	for m: Mesh in [cyl, arm, head, lens]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = count
		mms.append(mm)
	var light_holder := Node3D.new()
	light_holder.name = "StreetlampPools"
	if Terrain.active:
		light_holder.set_meta("on_terrain", true)
	parent.add_child(light_holder)
	var tf_lists: Array = [[], [], [], []]
	for i in range(count):
		var la: Array = lamps[i]
		var lx := float(la[0])
		var lz := float(la[1])
		var ad := Vector3(float(la[2]), 0.0, float(la[3]))
		if ad.length_squared() < 0.01:
			ad = Vector3.RIGHT
		ad = ad.normalized()
		var dy := Terrain.surface(lx, lz) if Terrain.active else 0.0
		var yaw := Basis(Vector3.UP, atan2(ad.x, ad.z)) # local +Z along the arm
		var tfs: Array[Transform3D] = [
			Transform3D(Basis.IDENTITY, Vector3(lx, POLE_H * 0.5 + dy, lz)),
			Transform3D(yaw * Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(lx, POLE_H - 0.15 + dy, lz) + ad * (ARM_L * 0.5)),
			Transform3D(yaw * Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3(lx, POLE_H + 0.12 + dy, lz) + ad * (ARM_L + 0.30)),
			Transform3D(yaw * Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3(lx, POLE_H + 0.055 + dy, lz) + ad * (ARM_L + 0.32)),
		]
		for k in range(4):
			mms[k].set_instance_transform(i, tfs[k])
			(tf_lists[k] as Array).append(tfs[k])
		if i % 14 == 0:
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.90, 0.74)
			ol.light_energy = 0.0
			ol.visible = false
			ol.omni_range = 24.0
			ol.omni_attenuation = 1.35
			ol.distance_fade_enabled = true
			ol.distance_fade_begin = 95.0
			ol.distance_fade_length = 35.0
			ol.position = Vector3(lx, POLE_H - 0.4 + dy, lz) + ad * (ARM_L + 0.3)
			light_holder.add_child(ol)
			night_lights.append(ol)
	var names := ["StreetlampPosts", "StreetlampArms", "StreetlampHeads", "StreetlampGlobes"]
	for k in range(4):
		var inst := MultiMeshInstance3D.new()
		inst.name = names[k]
		inst.multimesh = mms[k]
		var typed: Array[Transform3D] = []
		typed.assign(tf_lists[k])
		inst.set_meta("base_tfs", typed)
		if k == 3:
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if Terrain.active:
			inst.set_meta("on_terrain", true)
		parent.add_child(inst)
	return night_lights


static func _build_traffic_signals(parent: Node3D, sigs: Array) -> void:
	if sigs.is_empty():
		return
	var pole_st := SurfaceTool.new(); pole_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lens_st := SurfaceTool.new(); lens_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pole_col := Color(0.18, 0.19, 0.20)
	var green_col := Color(0.18, 0.95, 0.48)
	var red_col := Color(0.95, 0.20, 0.16)

	for i in range(sigs.size()):
		var sx := float(sigs[i][0]) + 7.2
		var sz := float(sigs[i][1]) - 6.8
		var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float((i * 90) % 360) + 42.0), 0.0))
		var tf := Transform3D(basis, Vector3(sx, 0.0, sz))

		_emit_colored_box(pole_st, tf * Transform3D(Basis.IDENTITY, Vector3(0.0, 2.9, 0.0)), Vector3(0.18, 5.8, 0.18), pole_col)
		_emit_colored_box(pole_st, tf * Transform3D(Basis.IDENTITY, Vector3(-2.5, 5.65, 0.0)), Vector3(5.2, 0.12, 0.12), pole_col)
		_emit_colored_box(pole_st, tf * Transform3D(Basis.IDENTITY, Vector3(-4.1, 5.45, 0.0)), Vector3(0.32, 0.88, 0.26), pole_col)
		var is_grn := (i % 3 != 0)
		var lens_y := 5.20 if is_grn else 5.70
		_emit_colored_box(lens_st, tf * Transform3D(Basis.IDENTITY, Vector3(-4.1, lens_y, 0.0)), Vector3(0.16, 0.16, 0.30), green_col if is_grn else red_col)

	var p_mi := MeshInstance3D.new()
	p_mi.name = "TrafficSignalFrames"
	p_mi.mesh = pole_st.commit()
	var pole_mat := StandardMaterial3D.new()
	pole_mat.vertex_color_use_as_albedo = true
	pole_mat.metallic = 0.55
	pole_mat.roughness = 0.42
	p_mi.material_override = pole_mat
	parent.add_child(p_mi)

	var l_mi := MeshInstance3D.new()
	l_mi.name = "TrafficSignalLenses"
	l_mi.mesh = lens_st.commit()
	var lens_mat := StandardMaterial3D.new()
	lens_mat.vertex_color_use_as_albedo = true
	lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	l_mi.material_override = lens_mat
	l_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l_mi)


static func _emit_colored_box(st: SurfaceTool, tf: Transform3D, sz: Vector3, col: Color) -> void:
	var h := sz * 0.5
	var faces := [
		[Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3.UP],
		[Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3.DOWN],
		[Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3.BACK],
		[Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3.FORWARD],
		[Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3.RIGHT],
		[Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3.LEFT],
	]
	for f: Array in faces:
		var nrm := (tf.basis * (f[4] as Vector3)).normalized()
		_add_colored_quad(
			st,
			tf * (f[0] as Vector3),
			tf * (f[1] as Vector3),
			tf * (f[2] as Vector3),
			tf * (f[3] as Vector3),
			nrm,
			col
		)


# Street trees, split into ~160m chunks: full-detail trees (trunk, branches, 7-bough crowns) within ~300m,
# a single low-poly crown per tree beyond that. Per-chunk nodes give frustum + distance culling, which a
# single city-wide MultiMesh cannot (it is culled as one box measured from the city centre).
const TREE_CHUNK := 160.0


static func _build_trees(parent: Node3D, trees: Array) -> void:
	if trees.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "StreetTrees"
	parent.add_child(holder)
	var chunks := {}
	for i in range(trees.size()):
		var k := Vector2i(int(floor(float(trees[i][0]) / TREE_CHUNK)), int(floor(float(trees[i][1]) / TREE_CHUNK)))
		if not chunks.has(k):
			chunks[k] = []
		(chunks[k] as Array).append(i)
	var far_mat := ShaderMaterial.new()
	far_mat.shader = load("res://shaders/foliage.gdshader") as Shader
	var far_mesh := SphereMesh.new()
	far_mesh.radius = 1.0
	far_mesh.height = 1.6
	far_mesh.radial_segments = 8
	far_mesh.rings = 4
	far_mesh.material = far_mat
	var species_far: Array[Color] = [Color(0.19, 0.36, 0.15), Color(0.23, 0.40, 0.18), Color(0.16, 0.32, 0.14), Color(0.26, 0.38, 0.16), Color(0.56, 0.40, 0.14), Color(0.48, 0.25, 0.14)]
	for key: Vector2i in chunks.keys():
		var idxs: Array = chunks[key]
		var chunk := Node3D.new()
		chunk.name = "TreeChunk_%d_%d" % [key.x, key.y]
		holder.add_child(chunk)
		_build_tree_chunk(chunk, trees, idxs, 330.0)
		# Far LOD: one low-poly crown per tree, no shadows
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = far_mesh
		mm.instance_count = idxs.size()
		for k in range(idxs.size()):
			var i := int(idxs[k])
			var s := 0.86 + 0.42 * float((i * 37) % 11) / 10.0
			var pal_idx := (i * 7) % 4
			if i % 9 == 0:
				pal_idx = 4
			elif i % 17 == 0:
				pal_idx = 5
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(2.3, 2.6, 2.3) * s), Vector3(float(trees[i][0]), 3.9 * s, float(trees[i][1]))))
			mm.set_instance_color(k, species_far[pal_idx])
		var far_inst := MultiMeshInstance3D.new()
		far_inst.name = "TreeCrownsFar"
		far_inst.multimesh = mm
		far_inst.visibility_range_begin = 330.0
		far_inst.visibility_range_end = 1800.0
		far_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(far_inst)


static func _build_tree_chunk(parent: Node3D, trees: Array, idxs: Array, vis_end: float) -> void:
	var count := idxs.size()
	if count == 0:
		return

	var bark_mat := ShaderMaterial.new()
	bark_mat.shader = load("res://shaders/bark.gdshader") as Shader

	var foliage_mat := ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader") as Shader
	foliage_mat.set_shader_parameter("leaf_cards", false) # primitive sphere crowns: their UVs are not leaf cards

	# 1. Sidewalk Cast-Iron Tree Pit Grates & Granite Planter Rings
	var pit_mm := MultiMesh.new()
	pit_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pit_box := BoxMesh.new()
	pit_box.size = Vector3(1.52, 0.04, 1.52)
	var pit_mat := StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.16, 0.15, 0.14)
	pit_mat.roughness = 0.68
	pit_mat.metallic = 0.55
	pit_box.material = pit_mat
	pit_mm.mesh = pit_box
	pit_mm.instance_count = count

	# 2. Tapered Furrowed Bark Trunk + 3 Angled Primary Branches per Tree!
	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.top_radius = 0.105
	trunk_cyl.bottom_radius = 0.22
	trunk_cyl.height = 2.85
	trunk_cyl.radial_segments = 10
	trunk_cyl.material = bark_mat
	trunk_mm.mesh = trunk_cyl
	trunk_mm.instance_count = count

	var branch_mm := MultiMesh.new()
	branch_mm.transform_format = MultiMesh.TRANSFORM_3D
	var br_cyl := CylinderMesh.new()
	br_cyl.top_radius = 0.045
	br_cyl.bottom_radius = 0.095
	br_cyl.height = 1.65
	br_cyl.radial_segments = 7
	br_cyl.material = bark_mat
	branch_mm.mesh = br_cyl
	branch_mm.instance_count = count * 3

	# 3. Multi-layered 7-Cluster Organic Foliage Canopy with Custom Leaf Shader!
	var boughs_per_tree := 7
	var crown_mm := MultiMesh.new()
	crown_mm.transform_format = MultiMesh.TRANSFORM_3D
	crown_mm.use_colors = true
	var crown_sph := SphereMesh.new()
	crown_sph.radius = 1.18
	crown_sph.height = 1.95
	crown_sph.radial_segments = 14
	crown_sph.rings = 9
	crown_sph.material = foliage_mat
	crown_mm.mesh = crown_sph
	crown_mm.instance_count = count * boughs_per_tree

	var bough_dirs: Array[Vector3] = [
		Vector3(0.0, 4.45, 0.0),
		Vector3(0.92, 3.65, 0.35),
		Vector3(-0.88, 3.55, 0.48),
		Vector3(0.28, 3.45, -0.92),
		Vector3(-0.42, 3.85, -0.68),
		Vector3(0.62, 4.18, -0.32),
		Vector3(-0.55, 4.22, 0.52),
	]
	var bough_scales: Array[Vector3] = [
		Vector3(1.18, 0.92, 1.15),
		Vector3(0.95, 0.78, 0.92),
		Vector3(0.92, 0.76, 0.96),
		Vector3(0.88, 0.74, 0.90),
		Vector3(0.86, 0.80, 0.88),
		Vector3(0.82, 0.75, 0.84),
		Vector3(0.80, 0.74, 0.82),
	]

	var species_pal: Array[Color] = [
		Color(0.19, 0.36, 0.15), # Pacific Bigleaf Maple
		Color(0.23, 0.40, 0.18), # London Plane
		Color(0.16, 0.32, 0.14), # Pin Oak
		Color(0.26, 0.38, 0.16), # Honey Locust
		Color(0.56, 0.40, 0.14), # Golden Autumn Ginkgo (accent)
		Color(0.48, 0.25, 0.14), # Scarlet Red Maple (rare accent)
	]

	for k in range(count):
		var i := int(idxs[k])
		var tx := float(trees[i][0])
		var tz := float(trees[i][1])
		var s := 0.86 + 0.42 * float((i * 37) % 11) / 10.0
		var yaw := float((i * 53) % 360) * PI / 180.0
		var rot_y := Basis(Vector3.UP, yaw)

		pit_mm.set_instance_transform(k, Transform3D(rot_y, Vector3(tx, 0.205, tz)))
		trunk_mm.set_instance_transform(
			k,
			Transform3D(rot_y.scaled(Vector3(s, s, s)), Vector3(tx, 1.40 * s, tz))
		)

		for b_i in range(3):
			var b_ang := yaw + float(b_i) * TAU / 3.0 + 0.35
			var br_basis := Basis(Vector3.UP, b_ang) * Basis(Vector3.RIGHT, deg_to_rad(34.0))
			var br_pos := Vector3(tx, 2.55 * s, tz) + Vector3(sin(b_ang) * 0.42 * s, 0.52 * s, cos(b_ang) * 0.42 * s)
			branch_mm.set_instance_transform(
				k * 3 + b_i,
				Transform3D(br_basis.scaled(Vector3(s, s, s)), br_pos)
			)

		var pal_idx := (i * 7) % 4
		if i % 9 == 0:
			pal_idx = 4
		elif i % 17 == 0:
			pal_idx = 5
		var base_col := species_pal[pal_idx]

		for p_i in range(boughs_per_tree):
			var off := (rot_y * bough_dirs[p_i]) * s
			var bsc := bough_scales[p_i] * s
			var tilt := Basis.from_euler(Vector3(sin(float(i + p_i)) * 0.18, yaw + float(p_i) * 0.9, cos(float(i * 2 + p_i)) * 0.18))
			crown_mm.set_instance_transform(
				k * boughs_per_tree + p_i,
				Transform3D(tilt.scaled(bsc), Vector3(tx, 0.0, tz) + off)
			)
			var shade_var := -0.06 + 0.03 * float(p_i)
			var c_use := base_col.lightened(maxf(0.0, shade_var)).darkened(maxf(0.0, -shade_var))
			crown_mm.set_instance_color(k * boughs_per_tree + p_i, c_use)

	var pit_inst := MultiMeshInstance3D.new()
	pit_inst.name = "TreePitGrates"
	pit_inst.visibility_range_end = vis_end
	pit_inst.multimesh = pit_mm
	parent.add_child(pit_inst)

	var t_inst := MultiMeshInstance3D.new()
	t_inst.name = "TreeTrunks"
	t_inst.visibility_range_end = vis_end
	t_inst.multimesh = trunk_mm
	parent.add_child(t_inst)

	var br_inst := MultiMeshInstance3D.new()
	br_inst.name = "TreeBranches"
	br_inst.visibility_range_end = vis_end
	br_inst.multimesh = branch_mm
	parent.add_child(br_inst)

	var c_inst := MultiMeshInstance3D.new()
	c_inst.name = "TreeCrowns"
	c_inst.visibility_range_end = vis_end
	c_inst.multimesh = crown_mm
	parent.add_child(c_inst)


static func _add_flat_quad(
	st: SurfaceTool,
	v0: Vector3,
	v1: Vector3,
	v2: Vector3,
	v3: Vector3,
	nrm: Vector3
) -> void:
	for v: Vector3 in [v0, v1, v2, v0, v2, v3]:
		st.set_normal(nrm)
		st.add_vertex(v)


static func _touched_tiles(clear_idx: Dictionary, bays: Array) -> Dictionary:
	var base_t: Dictionary = {}
	if not clear_idx.is_empty():
		if clear_idx.has("_touched_tiles"):
			base_t = clear_idx["_touched_tiles"]
		else:
			for ck: Vector2i in (clear_idx["grid"] as Dictionary).keys():
				var cp := (Vector2(ck) + Vector2(0.5, 0.5)) * TrackBuilder.CLEAR_CELL
				for dx in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						base_t[Vector2i(int(floor((cp.x + dx * 30.0) / CityTiles.TILE)), int(floor((cp.y + dz * 30.0) / CityTiles.TILE)))] = true
			clear_idx["_touched_tiles"] = base_t
	if bays.is_empty():
		return base_t
	var touched := base_t.duplicate()
	for bay: Dictionary in bays:
		var bp: Vector3 = bay["pos"]
		touched[Vector2i(int(floor(bp.x / CityTiles.TILE)), int(floor(bp.z / CityTiles.TILE)))] = true
	return touched


# Hide streetlamps / street trees that would stand on (or overhang) laid tram track.
# Re-run after every track rebuild; original transforms are kept in metadata so removed track restores them.
static func apply_track_clearance(city_root: Node3D, clear_idx: Dictionary, bays: Array = []) -> void:
	if city_root == null:
		return
	var rname := str(city_root.name)
	if rname.begins_with("Tile_"):
		var rparts := rname.split("_")
		if rparts.size() == 3:
			var rtk := Vector2i(int(rparts[1]), int(rparts[2]))
			var rhit := _touched_tiles(clear_idx, bays).has(rtk)
			if not rhit and not bool(city_root.get_meta("clear_hidden", false)):
				return
			city_root.set_meta("clear_hidden", rhit)
	var tiles := city_root.get_node_or_null("CityTiles")
	if tiles != null:
		# Only tiles a track or station bay reaches (or that still hide something from before) need a pass
		var touched := _touched_tiles(clear_idx, bays)
		for tile: Node in tiles.get_children():
			if not (tile is Node3D):
				continue
			var parts := str(tile.name).split("_")
			var tk := Vector2i(int(parts[1]), int(parts[2])) if parts.size() == 3 else Vector2i.ZERO
			var hit := touched.has(tk)
			if hit or bool(tile.get_meta("clear_hidden", false)):
				apply_track_clearance(tile as Node3D, clear_idx, bays)
				tile.set_meta("clear_hidden", hit)
	var lamp_posts := city_root.get_node_or_null("StreetlampPosts") as MultiMeshInstance3D
	var lamp_hidden := _clearance_hidden_set(lamp_posts, clear_idx, TrackBuilder.LAMP_CLEARANCE_M, bays)
	_apply_hidden(lamp_posts, lamp_hidden, 1)
	for lnm: String in ["StreetlampGlobes", "StreetlampArms", "StreetlampHeads"]:
		_apply_hidden(city_root.get_node_or_null(lnm) as MultiMeshInstance3D, lamp_hidden, 1)
	var pools := city_root.get_node_or_null("StreetlampPools")
	if pools != null:
		for ol: Node in pools.get_children():
			if not (ol is Node3D):
				continue
			var n3 := ol as Node3D
			if not n3.has_meta("base_pos"):
				n3.set_meta("base_pos", n3.position)
			var bp: Vector3 = n3.get_meta("base_pos")
			var blocked := TrackBuilder.track_clearance_dist(clear_idx, Vector2(bp.x, bp.z)) < TrackBuilder.LAMP_CLEARANCE_M or _in_bay(bays, Vector2(bp.x, bp.z))
			n3.position = bp + (Vector3(0.0, -200.0, 0.0) if blocked else Vector3.ZERO)
	var tree_holder := city_root.get_node_or_null("StreetTrees")
	if tree_holder != null:
		for chunk: Node in tree_holder.get_children():
			var trunks := chunk.get_node_or_null("TreeTrunks") as MultiMeshInstance3D
			var tree_hidden := _clearance_hidden_set(trunks, clear_idx, TrackBuilder.TREE_CLEARANCE_M, bays)
			_apply_hidden(trunks, tree_hidden, 1)
			_apply_hidden(chunk.get_node_or_null("TreePitGrates") as MultiMeshInstance3D, tree_hidden, 1)
			_apply_hidden(chunk.get_node_or_null("TreeBranches") as MultiMeshInstance3D, tree_hidden, 3)
			_apply_hidden(chunk.get_node_or_null("TreeCrowns") as MultiMeshInstance3D, tree_hidden, 7)
			_apply_hidden(chunk.get_node_or_null("TreeCrownsFar") as MultiMeshInstance3D, tree_hidden, 1)
	var pal := city_root.get_node_or_null("ParksAndLandscape")
	var multi_trees := pal.get_node_or_null("MultiSpeciesTrees") if pal != null else null
	if multi_trees != null:
		for chunk: Node in multi_trees.get_children():
			var pits := chunk.get_node_or_null("TreePits") as MultiMeshInstance3D
			if pits != null:
				_apply_hidden(pits, _clearance_hidden_set(pits, clear_idx, TrackBuilder.TREE_CLEARANCE_M, bays), 1)
			for sp in range(6):
				var wm := chunk.get_node_or_null("TreeWood_S%d" % sp) as MultiMeshInstance3D
				if wm == null:
					continue
				var th := _clearance_hidden_set(wm, clear_idx, TrackBuilder.TREE_CLEARANCE_M, bays)
				_apply_hidden(wm, th, 1)
				_apply_hidden(chunk.get_node_or_null("TreeLeaf_S%d" % sp) as MultiMeshInstance3D, th, 1)
				_apply_hidden(chunk.get_node_or_null("TreeLeafMid_S%d" % sp) as MultiMeshInstance3D, th, 1)
			for fnm: String in ["FarBroadleaf", "FarConifer"]:
				var fm := chunk.get_node_or_null(fnm) as MultiMeshInstance3D
				if fm != null:
					_apply_hidden(fm, _clearance_hidden_set(fm, clear_idx, TrackBuilder.TREE_CLEARANCE_M, bays), 1)


static func _base_tfs(mmi: MultiMeshInstance3D) -> Array:
	if not mmi.has_meta("base_tfs"):
		var arr: Array = []
		var mm := mmi.multimesh
		for i in range(mm.instance_count):
			arr.append(mm.get_instance_transform(i))
		mmi.set_meta("base_tfs", arr)
	return mmi.get_meta("base_tfs")


static func _clearance_hidden_set(mmi: MultiMeshInstance3D, clear_idx: Dictionary, clearance: float, bays: Array = []) -> Dictionary:
	var hidden := {}
	if mmi == null or mmi.multimesh == null:
		return hidden
	var base := _base_tfs(mmi)
	for i in range(base.size()):
		var o: Vector3 = (base[i] as Transform3D).origin
		if TrackBuilder.track_clearance_dist(clear_idx, Vector2(o.x, o.z)) < clearance or _in_bay(bays, Vector2(o.x, o.z)):
			hidden[i] = true
	return hidden


static func _apply_hidden(mmi: MultiMeshInstance3D, hidden: Dictionary, group: int) -> void:
	if mmi == null or mmi.multimesh == null:
		return
	if hidden.is_empty() and not bool(mmi.get_meta("has_hidden", false)):
		return
	mmi.set_meta("has_hidden", not hidden.is_empty())
	var base := _base_tfs(mmi)
	var mm := mmi.multimesh
	for i in range(base.size()):
		var tf: Transform3D = base[i]
		if hidden.has(i / group):
			tf = Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), tf.origin + Vector3(0.0, -200.0, 0.0))
		mm.set_instance_transform(i, tf)



# Rebuild the granite kerbs ONLY when station bays actually changed (saves ~950ms on every track/crossover click!).
static func _station_bays_sig(bays: Array) -> String:
	if bays.is_empty():
		return ""
	var parts: PackedStringArray = []
	for bay: Dictionary in bays:
		var bp: Vector3 = bay["pos"]
		parts.append("%d_%d_%d" % [int(round(bp.x * 10.0)), int(round(bp.z * 10.0)), int(round(float(bay["bay_q"]) * 10.0))])
	parts.sort()
	return "|".join(parts)


static func _tile_clear_sig(node: Node3D, clear_idx: Dictionary) -> String:
	var grid: Dictionary = clear_idx.get("grid", {})
	if grid.is_empty():
		return ""
	var nm := str(node.name)
	var parts := nm.split("_")
	if parts.size() == 3 and parts[0] == "Tile":
		var r := Rect2(Vector2(float(parts[1]), float(parts[2])) * CityTiles.TILE, Vector2(CityTiles.TILE, CityTiles.TILE)).grow(24.0)
		var x0 := int(floor(r.position.x / TrackBuilder.CLEAR_CELL))
		var x1 := int(floor(r.end.x / TrackBuilder.CLEAR_CELL))
		var z0 := int(floor(r.position.y / TrackBuilder.CLEAR_CELL))
		var z1 := int(floor(r.end.y / TrackBuilder.CLEAR_CELL))
		var cnt := 0
		var h := 0
		for k: Vector2i in grid.keys():
			if k.x >= x0 and k.x <= x1 and k.y >= z0 and k.y <= z1:
				cnt += 1
				h = hash([h, k, (grid[k] as PackedVector2Array).size()])
		return "%d:%d" % [cnt, h]
	return "c:%d" % grid.size()


static func apply_station_bays(city_root: Node3D, bays: Array, clear_idx: Dictionary = {}) -> void:
	if city_root == null:
		return
	var tiles := city_root.get_node_or_null("CityTiles")
	if tiles != null:
		for tile: Node in tiles.get_children():
			if tile is Node3D:
				apply_station_bays(tile as Node3D, _bays_near(tile as Node3D, bays), clear_idx)
	if not city_root.has_meta("kerb_roads"):
		return
	var sig := _station_bays_sig(bays) + "#" + _tile_clear_sig(city_root, clear_idx)
	if city_root.has_meta("last_bays_sig") and str(city_root.get_meta("last_bays_sig")) == sig:
		return
	city_root.set_meta("last_bays_sig", sig)
	_build_kerbs(city_root, city_root.get_meta("kerb_roads"), bays, city_root.get_meta("road_mat"), clear_idx)


# Station bays that touch a tile (its kerbs are only rebuilt when one of these changes)
static func _bays_near(tile: Node3D, bays: Array) -> Array:
	var out: Array = []
	var nm := str(tile.name)
	var parts := nm.split("_")
	if parts.size() != 3:
		return bays
	var r := Rect2(Vector2(float(parts[1]), float(parts[2])) * CityTiles.TILE, Vector2(CityTiles.TILE, CityTiles.TILE)).grow(60.0)
	for bay: Dictionary in bays:
		var bp: Vector3 = bay["pos"]
		if r.has_point(Vector2(bp.x, bp.z)):
			out.append(bay)
	return out


static func _in_bay(bays: Array, p: Vector2) -> bool:
	for bay: Dictionary in bays:
		var bp: Vector3 = bay["pos"]
		var rel := Vector3(p.x - bp.x, 0.0, p.y - bp.z)
		var along := rel.dot(bay["fwd"] as Vector3)
		if absf(along) > float(bay["half"]) + float(bay["taper"]):
			continue
		var q := rel.dot(bay["out"] as Vector3)
		if q > float(bay["kerb_q"]) - 1.2 and q < float(bay["bay_q"]) + 1.2:
			return true
	return false


const SIDEWALK_W := 5.0
const KERB_H := 0.15
const ROAD_Y := 0.042


static func _build_kerbs(parent: Node3D, roads: Array, bays: Array, road_mat: Material, clear_idx: Dictionary = {}) -> void:
	parent.set_meta("last_bays_sig", _station_bays_sig(bays) + "#" + _tile_clear_sig(parent, clear_idx))
	var has_tracks := not clear_idx.is_empty() and not (clear_idx.get("grid", {}) as Dictionary).is_empty()
	for nm: String in ["GraniteCurbs", "StationKerbBays", "Sidewalks", "StreetFurniture", "BikeLaneStrips", "BikeLaneLines", "BikeLaneGuardrails", "BikeBufferStrips", "BikeBufferShrubs", "MedianGreens"]:
		var old := parent.get_node_or_null(nm)
		if old != null:
			parent.remove_child(old)
			old.queue_free()
	# Junction degree per road end-point (kerbs/sidewalks stop + ramp down only at real intersections)
	var deg := {}
	for r in roads:
		var rp: Array = r.get("pts", [])
		if rp.size() < 2 or int(r.get("layer", 0)) != 0 or bool(r.get("underground", false)):
			continue
		for e_pt in [rp[0], rp[rp.size() - 1]]:
			var key := Vector2i(int(round(float(e_pt[0]) * 2.0)), int(round(float(e_pt[1]) * 2.0)))
			deg[key] = int(deg.get(key, 0)) + 1
	# Spatial grid of all carriageway segments, to keep kerbs/sidewalks out of other streets
	var seg_grid := {}
	for ri in range(roads.size()):
		var rr: Dictionary = roads[ri]
		var rp2: Array = rr.get("pts", [])
		if rp2.size() < 2 or int(rr.get("layer", 0)) != 0 or bool(rr.get("underground", false)):
			continue
		var rhw: float = clampf(float(rr.get("width", 12.0)) * 0.5, 3.2, 13.5)
		for si in range(rp2.size() - 1):
			var sa := Vector2(float(rp2[si][0]), float(rp2[si][1]))
			var sb := Vector2(float(rp2[si + 1][0]), float(rp2[si + 1][1]))
			var mn := sa.min(sb) - Vector2.ONE * (rhw + 6.0)
			var mx := sa.max(sb) + Vector2.ONE * (rhw + 6.0)
			for gx in range(int(floor(mn.x / 20.0)), int(floor(mx.x / 20.0)) + 1):
				for gz in range(int(floor(mn.y / 20.0)), int(floor(mx.y / 20.0)) + 1):
					var gk := Vector2i(gx, gz)
					if not seg_grid.has(gk):
						seg_grid[gk] = []
					(seg_grid[gk] as Array).append([sa, sb, rhw, ri])
	var curb_st := SurfaceTool.new()
	curb_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walk_st := SurfaceTool.new()
	walk_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var med_st := SurfaceTool.new()
	med_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_med := false
	var furn := {"bin": [], "rack": [], "hydrant": [], "pay": [], "news": [], "cover": []}
	var has_curb := false
	var emit_n := int(parent.get_meta("kerb_emit_n", roads.size()))
	for road_i in range(mini(emit_n, roads.size())):
		var r: Dictionary = roads[road_i]
		var raw_pts: Array = r.get("pts", [])
		if raw_pts.size() < 2 or int(r.get("layer", 0)) != 0 or bool(r.get("underground", false)):
			continue
		var hw: float = clampf(float(r.get("width", 12.0)) * 0.5, 3.2, 13.5)
		var n_seg := raw_pts.size() - 1
		var u_acc := 0.0
		for i in range(n_seg):
			var a := Vector2(float(raw_pts[i][0]), float(raw_pts[i][1]))
			var b := Vector2(float(raw_pts[i + 1][0]), float(raw_pts[i + 1][1]))
			var seg_len := a.distance_to(b)
			if seg_len < 0.5:
				continue
			var dir := (b - a) / seg_len
			# Trim only at intersections: back to the far side of the crosswalk so the ramp lands on it
			var trim0 := 0.0
			var trim1 := 0.0
			if i == 0 and int(deg.get(Vector2i(int(round(a.x * 2.0)), int(round(a.y * 2.0))), 0)) >= 2:
				trim0 = 9.2
			if i == n_seg - 1 and int(deg.get(Vector2i(int(round(b.x * 2.0)), int(round(b.y * 2.0))), 0)) >= 2:
				trim1 = 9.2
			if seg_len - trim0 - trim1 < 4.0:
				if n_seg == 1 and trim0 > 0.0 and trim1 > 0.0:
					# a short link with a junction at BOTH ends lies inside one junction (e.g. between the two
					# carriageways of a divided cross street): no kerb or pavement in the middle of the crossing
					u_acc += seg_len
					continue
				trim0 = minf(trim0, 3.8)
				trim1 = minf(trim1, 3.8)
			var c_start := a + dir * trim0
			var run := seg_len - trim0 - trim1
			if run <= 2.0:
				u_acc += seg_len
				continue
			for side: float in [-1.0, 1.0]:
				var nrm := Vector2(-dir.y, dir.x) * side
				# Divided road: the other carriageway runs parallel just beyond this kerb -> this side is the
				# central median (planted), not a pavement
				var med_gap := _median_gap(seg_grid, c_start + dir * (run * 0.5) + nrm * hw, nrm, dir, road_i)
				var pieces: Array = []
				var n_s := int(ceil(run / 0.5))
				var cur0 := -1.0
				for k in range(n_s + 1):
					var t := minf(float(k) * 0.5, run)
					var kp := c_start + dir * t + nrm * hw
					var keep := (bays.is_empty() or not _in_bay(bays, kp)) and _other_road_clear(seg_grid, kp, road_i) > -0.2
					if keep and has_tracks and TrackBuilder.track_clearance_dist(clear_idx, kp) < 1.92:
						keep = false
					if keep and cur0 < 0.0:
						cur0 = t
					if (not keep or k == n_s) and cur0 >= 0.0:
						var t1 := t if keep else maxf(cur0, t - 0.5)
						if t1 - cur0 > 0.3:
							pieces.append([cur0, t1])
						cur0 = -1.0
				for pc: Array in pieces:
					var t0 := float(pc[0])
					var t1 := float(pc[1])
					var p0 := c_start + dir * t0
					var p1 := c_start + dir * t1
					_kerb_piece(curb_st, p0 + nrm * hw, p1 + nrm * hw, nrm, ROAD_Y)
					if med_gap > 0.0:
						_median_green(med_st, p0 + nrm * (hw + 0.30), p1 + nrm * (hw + 0.30), nrm, maxf(0.3, med_gap * 0.5 - 0.30))
						has_med = true
						has_curb = true
						continue
					# Sidewalk in <=2m chunks, each as wide as it can be before reaching another carriageway or tram track
					var n_ch := maxi(1, int(ceil((t1 - t0) / 2.0)))
					var w_prev := _walk_width(seg_grid, c_start + dir * t0 + nrm * (hw + 0.32), nrm, road_i, clear_idx if has_tracks else {})
					for ch in range(n_ch):
						var ta := lerpf(t0, t1, float(ch) / float(n_ch))
						var tb := lerpf(t0, t1, float(ch + 1) / float(n_ch))
						var w_next := _walk_width(seg_grid, c_start + dir * tb + nrm * (hw + 0.32), nrm, road_i, clear_idx if has_tracks else {})
						var w_use := minf(w_prev, w_next)
						if w_use >= 0.6:
							_walk_strip(walk_st, c_start + dir * ta + nrm * (hw + 0.32), c_start + dir * tb + nrm * (hw + 0.32), nrm, u_acc + trim0 + ta, u_acc + trim0 + tb, w_use, float((road_i * 5 + i * 2 + (1 if side > 0.0 else 0)) % 12) * 0.0008)
						w_prev = w_next
					has_curb = true
					# Kerb ramps (with tactile pad) where the walk ends at a crosswalk
					if trim0 > 5.0 and t0 < 0.01:
						_kerb_ramp(walk_st, curb_st, p0 + nrm * hw, -dir, nrm)
					if trim1 > 5.0 and t1 > run - 0.01:
						_kerb_ramp(walk_st, curb_st, p1 + nrm * hw, dir, nrm)
					_place_furniture(furn, p0 + nrm * hw, dir, nrm, t1 - t0, u_acc + trim0 + t0)
			u_acc += seg_len
	# Bay kerb lines + bay paving + set-back sidewalk
	var bay_st := SurfaceTool.new()
	bay_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_bay := false
	for bay: Dictionary in bays:
		var bp: Vector3 = bay["pos"]
		var f: Vector3 = bay["fwd"]
		var o: Vector3 = bay["out"]
		var L := float(bay["half"]) + float(bay["taper"])
		var kq := float(bay["kerb_q"])
		var bq := float(bay["bay_q"])
		var prev_k := Vector2.ZERO
		var prev_in := Vector2.ZERO
		var first := true
		var a := -L
		var o2 := Vector2(o.x, o.z)
		while a <= L + 0.01:
			var q := kq + (bq - kq) * TrackBuilder.bay_blend(bay, a)
			var pk3 := bp + f * a + o * q
			var pi3 := bp + f * a + o * (kq - 0.4)
			var pk := Vector2(pk3.x, pk3.z)
			var pin := Vector2(pi3.x, pi3.z)
			if not first:
				for tri: Array in [[prev_in, prev_k, pk], [prev_in, pk, pin]]:
					for v2: Vector2 in tri:
						bay_st.set_normal(Vector3.UP)
						bay_st.set_uv(Vector2(1.0, a))
						bay_st.add_vertex(Vector3(v2.x, 0.056, v2.y))
				_kerb_piece(curb_st, prev_k, pk, o2, ROAD_Y)
				_walk_strip(walk_st, prev_k + o2 * 0.32, pk + o2 * 0.32, o2, a - 1.0, a, SIDEWALK_W, 0.0102)
				has_bay = true
			prev_k = pk
			prev_in = pin
			first = false
			a += 1.0
	if has_med:
		var m_mi := MeshInstance3D.new()
		m_mi.name = "MedianGreens"
		m_mi.mesh = Terrain.commit_draped(med_st, m_mi)
		var m_mat := StandardMaterial3D.new()
		m_mat.vertex_color_use_as_albedo = true
		m_mat.roughness = 0.92
		m_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		m_mi.material_override = m_mat
		m_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(m_mi)
	if has_curb:
		var curb_mi := MeshInstance3D.new()
		curb_mi.name = "GraniteCurbs"
		curb_mi.mesh = Terrain.commit_draped(curb_st, curb_mi)
		if _curb_mat_cache == null:
			_curb_mat_cache = StandardMaterial3D.new()
			_curb_mat_cache.albedo_color = Color(0.60, 0.59, 0.56)
			_curb_mat_cache.roughness = 0.78
			_curb_mat_cache.metallic_specular = 0.22
			_curb_mat_cache.cull_mode = BaseMaterial3D.CULL_DISABLED
		curb_mi.material_override = _curb_mat_cache
		curb_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(curb_mi)
		var w_mi := MeshInstance3D.new()
		w_mi.name = "Sidewalks"
		w_mi.mesh = Terrain.commit_draped(walk_st, w_mi)
		if _sidewalk_mat_cache == null:
			_sidewalk_mat_cache = ShaderMaterial.new()
			_sidewalk_mat_cache.shader = load("res://shaders/sidewalk_strip.gdshader") as Shader
		w_mi.material_override = _sidewalk_mat_cache
		w_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(w_mi)
		_build_furniture(parent, furn)
	if has_bay:
		var bay_mi := MeshInstance3D.new()
		bay_mi.name = "StationKerbBays"
		bay_mi.mesh = Terrain.commit_draped(bay_st, bay_mi)
		bay_mi.material_override = road_mat
		bay_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(bay_mi)
	var emit_n_b := int(parent.get_meta("kerb_emit_n", roads.size()))
	_build_bike_lane_strips(parent, roads, emit_n_b, bays, clear_idx, has_tracks)
	_build_bike_guardrails(parent, roads, emit_n_b, seg_grid, bays, clear_idx, has_tracks)


# Track-aware Chinese Non-Motorized Bike Lanes (非机动车道): green outer asphalt strip + solid white divider line.
# Rebuilt whenever tracks change so green bike lanes NEVER overlap laid tram tracks or station bays!
# Kerb sides (+1: right of a -> b) that carry a non-motorised lane. A one-way carriageway (the usual case: one
# half of a divided arterial) has it at its kerb only, not along the median.
static func _bike_sides(r: Dictionary) -> Array[float]:
	var lf := int(r.get("lanes_f", 1))
	var lb := int(r.get("lanes_b", 1))
	if lf > 0 and lb == 0:
		return [1.0]
	if lb > 0 and lf == 0:
		return [-1.0]
	return [-1.0, 1.0]


static func _build_bike_lane_strips(
	parent: Node3D, roads: Array, emit_n: int,
	bays: Array, clear_idx: Dictionary, has_tracks: bool
) -> void:
	var line_st := SurfaceTool.new()
	line_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_line := false
	var ym := ROAD_Y + 0.016
	var buf_st := SurfaceTool.new()
	buf_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_buf := false
	var shrub_tfs: Array[Transform3D] = []
	var shrub_cols: Array[Color] = []

	for ri in range(mini(emit_n, roads.size())):
		var r: Dictionary = roads[ri]
		if not bool(r.get("bike_lane", false)) or bool(r.get("underground", false)) or int(r.get("layer", 0)) != 0:
			continue
		var hw := clampf(float(r.get("width", 12.0)) * 0.5, 3.2, 13.5)
		if hw < 4.0:
			continue
		var pts: Array = r.get("pts", [])
		if pts.size() < 2:
			continue
		var bl_w := 2.05 if hw >= 5.75 else (1.55 if hw >= 4.8 else 1.25)
		# The lane follows the whole street polyline continuously (smooth joins at its bends); it is only
		# trimmed back at the street's two ends, where the junction / crosswalk is
		var poly: Array[Vector2] = []
		for pp in pts:
			var v2 := Vector2(float(pp[0]), float(pp[1]))
			if poly.is_empty() or poly[poly.size() - 1].distance_to(v2) > 0.05:
				poly.append(v2)
		if poly.size() < 2:
			continue
		var cum: Array[float] = [0.0]
		for k in range(1, poly.size()):
			cum.append(cum[k - 1] + poly[k - 1].distance_to(poly[k]))
		var total := cum[cum.size() - 1]
		var end_cap := 8.5 if hw >= 5.75 else 6.5
		var t0 := minf(end_cap, (cum[1] - cum[0]) * 0.24 if poly.size() == 2 else end_cap)
		var t1 := total - minf(end_cap, (cum[cum.size() - 1] - cum[cum.size() - 2]) * 0.24 if poly.size() == 2 else end_cap)
		if t1 - t0 < 4.0:
			continue
		# samples: position + smoothed left normal (averaged across a bend)
		var samp_p: Array[Vector2] = []
		var samp_n: Array[Vector2] = []
		var seg := 0
		var sd := t0
		while true:
			var s_cl := minf(sd, t1)
			while seg < poly.size() - 2 and cum[seg + 1] < s_cl:
				seg += 1
			var a := poly[seg]
			var b := poly[seg + 1]
			var f := clampf((s_cl - cum[seg]) / maxf(cum[seg + 1] - cum[seg], 0.001), 0.0, 1.0)
			var dir := (b - a).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			# ease the normal into the neighbouring segment's within 3 m of a bend
			if f * (cum[seg + 1] - cum[seg]) > (cum[seg + 1] - cum[seg]) - 3.0 and seg < poly.size() - 2:
				var dn := (poly[seg + 2] - b).normalized()
				var w := 0.5 * (1.0 - ((cum[seg + 1] - s_cl) / 3.0))
				nrm = nrm.lerp(Vector2(-dn.y, dn.x), clampf(w, 0.0, 0.5)).normalized()
			elif f * (cum[seg + 1] - cum[seg]) < 3.0 and seg > 0:
				var dp := (a - poly[seg - 1]).normalized()
				var w2 := 0.5 * (1.0 - ((s_cl - cum[seg]) / 3.0))
				nrm = nrm.lerp(Vector2(-dp.y, dp.x), clampf(w2, 0.0, 0.5)).normalized()
			samp_p.append(a.lerp(b, f))
			samp_n.append(nrm)
			if sd >= t1:
				break
			sd += 2.0
		for bside: float in _bike_sides(r):
			# Per sample: on a tram street the lane starts outside the motor lane that keeps clear of the
			# tracks, so it narrows only where the track comes close (curves, shifted alignment)
			var samp_in: Array[float] = []
			for k in range(samp_p.size()):
				var inner_abs := hw - bl_w
				if has_tracks:
					for _it in range(2):
						var pq := samp_p[k] + samp_n[k] * (bside * inner_abs)
						inner_abs += maxf(0.0, NetworkGraph.BIKE_TRACK_CLEAR - TrackBuilder.track_clearance_dist(clear_idx, pq))
				samp_in.append(inner_abs)
			# widen each narrowing over the neighbouring samples so the edge eases in and out
			var sm_in: Array[float] = []
			for k in range(samp_in.size()):
				var v := samp_in[k]
				for kk in range(maxi(0, k - 2), mini(samp_in.size(), k + 3)):
					v = maxf(v, samp_in[kk] - 0.25 * float(absi(kk - k)))
				sm_in.append(v)
			# Decide per kerb side, not per sample: a side that mostly has room is painted continuously
			# (at least BIKE_MIN_W wide), so the lane never blinks on and off along a street; only station
			# bays cut it
			var n_room := 0
			for k0 in range(sm_in.size()):
				if hw - 0.14 - sm_in[k0] >= NetworkGraph.BIKE_MIN_W + 0.3:
					n_room += 1
			if float(n_room) < NetworkGraph.BIKE_SIDE_MIN_SHARE * float(sm_in.size()):
				continue
			for k1 in range(sm_in.size()):
				sm_in[k1] = minf(sm_in[k1], hw - 0.14 - NetworkGraph.BIKE_MIN_W)
			var ok_arr: Array[bool] = []
			for k in range(samp_p.size()):
				var pm := samp_p[k] + samp_n[k] * (bside * ((sm_in[k] + hw - 0.14) * 0.5))
				ok_arr.append(not _in_bay(bays, pm))
			# 机非隔离带 on major roads: a planted strip just inside the bike lane, wherever a motor lane still
			# fits between it and any tramway
			var buf := float(r.get("bike_buffer", 0.0))
			var strip_ok: Array[bool] = []
			for k in range(samp_p.size()):
				var s_k := minf(t0 + 2.0 * float(k), t1)
				# keep clear of the crosswalks (centred 7.8 m from each junction)
				var good := buf > 0.0 and ok_arr[k] and s_k >= 11.0 and s_k <= total - 11.0
				if good and has_tracks:
					var pin := samp_p[k] + samp_n[k] * (bside * (sm_in[k] - buf))
					good = TrackBuilder.track_clearance_dist(clear_idx, pin) >= 5.0
				strip_ok.append(good)
			if buf > 0.0:
				_emit_bike_buffer(buf_st, shrub_tfs, shrub_cols, samp_p, samp_n, sm_in, strip_ok, bside, buf)
				for sk in range(samp_p.size() - 1):
					has_buf = has_buf or (strip_ok[sk] and strip_ok[sk + 1])
			for k in range(samp_p.size() - 1):
				if not (ok_arr[k] and ok_arr[k + 1]):
					continue
				if strip_ok[k] and strip_ok[k + 1]:
					continue # the strip's kerb replaces the painted divider
				if samp_p[k].distance_to(samp_p[k + 1]) < 0.05:
					continue
				# solid white divider along the (possibly narrowed) inner edge
				var la := samp_p[k] + samp_n[k] * (bside * (sm_in[k] - 0.08))
				var lb := samp_p[k + 1] + samp_n[k + 1] * (bside * (sm_in[k + 1] - 0.08))
				var ln_a := samp_n[k] * 0.08
				var ln_b := samp_n[k + 1] * 0.08
				_add_flat_quad(line_st, Vector3(la.x - ln_a.x, ym, la.y - ln_a.y), Vector3(la.x + ln_a.x, ym, la.y + ln_a.y),
					Vector3(lb.x + ln_b.x, ym, lb.y + ln_b.y), Vector3(lb.x - ln_b.x, ym, lb.y - ln_b.y), Vector3.UP)
				has_line = true

	if has_buf:
		var b_mi := MeshInstance3D.new()
		b_mi.name = "BikeBufferStrips"
		b_mi.mesh = Terrain.commit_draped(buf_st, b_mi)
		var b_mat := StandardMaterial3D.new()
		b_mat.vertex_color_use_as_albedo = true
		b_mat.roughness = 0.9
		b_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		b_mi.material_override = b_mat
		b_mi.visibility_range_end = 650.0
		b_mi.visibility_range_end_margin = 40.0
		parent.add_child(b_mi)
		if not shrub_tfs.is_empty():
			var ball := SphereMesh.new()
			ball.radius = 0.5
			ball.height = 0.86
			ball.radial_segments = 10
			ball.rings = 5
			var s_mat := StandardMaterial3D.new()
			s_mat.vertex_color_use_as_albedo = true
			s_mat.roughness = 0.95
			ball.material = s_mat
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = ball
			mm.instance_count = shrub_tfs.size()
			for i in range(shrub_tfs.size()):
				mm.set_instance_transform(i, shrub_tfs[i])
				mm.set_instance_color(i, shrub_cols[i])
			var s_mi := MultiMeshInstance3D.new()
			s_mi.name = "BikeBufferShrubs"
			s_mi.multimesh = mm
			s_mi.set_meta("base_tfs", shrub_tfs)
			s_mi.visibility_range_end = 380.0
			s_mi.visibility_range_end_margin = 30.0
			if Terrain.active:
				s_mi.set_meta("on_terrain", true)
			parent.add_child(s_mi)
	# The non-motorised lane is plain asphalt like the motor lanes (no coloured surfacing); only its divider line is painted
	if has_line:
		var l_mi := MeshInstance3D.new()
		l_mi.name = "BikeLaneLines"
		l_mi.mesh = Terrain.commit_draped(line_st, l_mi)
		var l_mat := ShaderMaterial.new()
		l_mat.shader = load("res://shaders/road_marking.gdshader") as Shader
		l_mat.set_shader_parameter("paint_col", Color(0.78, 0.77, 0.73))
		l_mat.set_shader_parameter("rough_val", 0.82)
		l_mi.material_override = l_mat
		l_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(l_mi)


# One kerb side of a 机非隔离带: granite kerbs on both edges, a soil bed, a clipped boxwood hedge and topiary
# balls (红叶石楠 / 海桐) every few metres. The strip spans [inner - buf, inner] from the street centre line.
static func _emit_bike_buffer(st: SurfaceTool, shrub_tfs: Array[Transform3D], shrub_cols: Array[Color],
		samp_p: Array[Vector2], samp_n: Array[Vector2], sm_in: Array[float], strip_ok: Array[bool], bside: float, buf: float) -> void:
	var kerb_c := Color(0.64, 0.64, 0.62)
	var soil_c := Color(0.27, 0.22, 0.16)
	var hedge_c := Color(0.16, 0.31, 0.13)
	var hedge_top_c := Color(0.21, 0.38, 0.16)
	var y_kerb := ROAD_Y + 0.18
	var y_soil := ROAD_Y + 0.14
	var y_hedge := ROAD_Y + 0.80
	var acc := 0.0
	var next_ball := 2.0
	var ball_i := 0
	for k in range(samp_p.size() - 1):
		if not (strip_ok[k] and strip_ok[k + 1]):
			continue
		var p0 := samp_p[k]
		var p1 := samp_p[k + 1]
		if p0.distance_to(p1) < 0.05:
			continue
		var n0 := samp_n[k] * bside
		var n1 := samp_n[k + 1] * bside
		var o0 := sm_in[k] - buf # strip edge toward the motor lanes
		var o1 := sm_in[k + 1] - buf
		var i0 := sm_in[k]
		var i1 := sm_in[k + 1]
		# kerbs (0.15 m wide) on both edges + soil bed between them
		_buf_ribbon(st, p0, p1, n0, n1, o0, o1, o0 + 0.15, o1 + 0.15, ROAD_Y, y_kerb, kerb_c)
		_buf_ribbon(st, p0, p1, n0, n1, i0 - 0.15, i1 - 0.15, i0, i1, ROAD_Y, y_kerb, kerb_c)
		_buf_ribbon(st, p0, p1, n0, n1, o0 + 0.15, o1 + 0.15, i0 - 0.15, i1 - 0.15, ROAD_Y, y_soil, soil_c)
		# hedge
		_buf_ribbon(st, p0, p1, n0, n1, o0 + 0.32, o1 + 0.32, i0 - 0.32, i1 - 0.32, y_soil, y_hedge, hedge_c, hedge_top_c)
		# end caps where the strip starts / stops
		if k == 0 or not strip_ok[k - 1]:
			_buf_cap(st, p0, n0, o0, i0, y_kerb, kerb_c)
		if k + 2 >= samp_p.size() or not strip_ok[k + 2]:
			_buf_cap(st, p1, n1, o1, i1, y_kerb, kerb_c)
		# topiary balls along the centre line
		var seg_l := p0.distance_to(p1)
		while next_ball <= acc + seg_l:
			var f := (next_ball - acc) / seg_l
			var pc := p0.lerp(p1, f)
			var nc := n0.lerp(n1, f).normalized()
			var oc := lerpf((o0 + i0) * 0.5, (o1 + i1) * 0.5, f)
			var q := pc + nc * oc
			var sc := 0.92 + 0.16 * float((ball_i * 7) % 5) / 4.0
			shrub_tfs.append(Transform3D(Basis().scaled(Vector3(sc, sc, sc)), Vector3(q.x, y_hedge + 0.12, q.y)))
			shrub_cols.append(Color(0.52, 0.17, 0.12) if ball_i % 2 == 0 else Color(0.19, 0.37, 0.15))
			ball_i += 1
			next_ball += 4.0
		acc += seg_l


static func _buf_ribbon(st: SurfaceTool, p0: Vector2, p1: Vector2, n0: Vector2, n1: Vector2, a0: float, a1: float, b0: float, b1: float, y0: float, y1: float, col: Color, top_col: Color = Color(-1, 0, 0)) -> void:
	var tc := col if top_col.r < 0.0 else top_col
	var qa0 := p0 + n0 * a0
	var qa1 := p1 + n1 * a1
	var qb0 := p0 + n0 * b0
	var qb1 := p1 + n1 * b1
	# top
	_buf_quad(st, Vector3(qa0.x, y1, qa0.y), Vector3(qb0.x, y1, qb0.y), Vector3(qb1.x, y1, qb1.y), Vector3(qa1.x, y1, qa1.y), Vector3.UP, tc)
	# side faces toward the motor lanes (-n) and toward the bike lane (+n)
	var nn := Vector3(-n0.x, 0.0, -n0.y)
	_buf_quad(st, Vector3(qa0.x, y0, qa0.y), Vector3(qa1.x, y0, qa1.y), Vector3(qa1.x, y1, qa1.y), Vector3(qa0.x, y1, qa0.y), nn, col)
	_buf_quad(st, Vector3(qb0.x, y0, qb0.y), Vector3(qb1.x, y0, qb1.y), Vector3(qb1.x, y1, qb1.y), Vector3(qb0.x, y1, qb0.y), -nn, col)


static func _buf_cap(st: SurfaceTool, p: Vector2, n: Vector2, a: float, b: float, y1: float, col: Color) -> void:
	var qa := p + n * a
	var qb := p + n * b
	var fwd := Vector3(n.y, 0.0, -n.x)
	_buf_quad(st, Vector3(qa.x, ROAD_Y, qa.y), Vector3(qb.x, ROAD_Y, qb.y), Vector3(qb.x, y1, qb.y), Vector3(qa.x, y1, qa.y), fwd, col)


static func _buf_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


# Low white municipal Chinese bike-lane separation guardrails (机非隔离护栏) on wide bike_lane avenues.
# Strictly skips intersections, side streets, station bays, and laid tram tracks.
static func _build_bike_guardrails(
	parent: Node3D, roads: Array, emit_n: int, seg_grid: Dictionary,
	bays: Array, clear_idx: Dictionary, has_tracks: bool
) -> void:
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_g := false
	var rail_white := Color(0.90, 0.91, 0.92)
	var post_base := Color(0.32, 0.34, 0.37)
	var accent_blue := Color(0.10, 0.42, 0.78)

	for ri in range(mini(emit_n, roads.size())):
		var r: Dictionary = roads[ri]
		if not bool(r.get("bike_lane", false)) or bool(r.get("underground", false)) or int(r.get("layer", 0)) != 0:
			continue
		if float(r.get("bike_buffer", 0.0)) > 0.0:
			continue # the planted 机非隔离带 separates the lanes there
		var hw := clampf(float(r.get("width", 12.0)) * 0.5, 3.2, 13.5)
		if hw < 5.75:
			continue
		var pts: Array = r.get("pts", [])
		if pts.size() < 2:
			continue
		var g_off := hw - 2.12
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var d := b - a
			var sl := d.length()
			if sl < 32.0:
				continue
			var dir := d / sl
			var nrm := Vector2(-dir.y, dir.x)
			var u3 := Vector3(dir.x, 0.0, dir.y)
			var n3 := Vector3(nrm.x, 0.0, nrm.y)
			var s_start := 13.5
			var s_end := sl - 13.5
			for side: float in _bike_sides(r):
				var run_a := -1.0
				var s := s_start
				while s <= s_end + 0.01:
					var sc := minf(s, s_end)
					var p2 := a + dir * sc + nrm * (side * g_off)
					var clear_ok := _other_road_clear(seg_grid, p2, ri) >= 3.2 and not _in_bay(bays, p2)
					if clear_ok and has_tracks:
						clear_ok = TrackBuilder.track_clearance_dist(clear_idx, p2) >= 2.8
					if clear_ok and s <= s_end:
						if run_a < 0.0:
							run_a = sc
					else:
						if run_a >= 0.0 and sc - run_a >= 4.0:
							_emit_guardrail_run(gst, a + dir * run_a + nrm * (side * g_off), u3, n3, sc - run_a, rail_white, post_base, accent_blue)
							has_g = true
						run_a = -1.0
					s += 4.5
				if run_a >= 0.0 and s_end - run_a >= 4.0:
					_emit_guardrail_run(gst, a + dir * run_a + nrm * (side * g_off), u3, n3, s_end - run_a, rail_white, post_base, accent_blue)
					has_g = true

	if not has_g:
		return
	var mi := MeshInstance3D.new()
	mi.name = "BikeLaneGuardrails"
	mi.mesh = Terrain.commit_draped(gst, mi)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.48
	mat.metallic = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _emit_guardrail_run(
	st: SurfaceTool, p0: Vector2, U: Vector3, N: Vector3, run_len: float,
	rail_c: Color, base_c: Color, accent_c: Color
) -> void:
	var o := Vector3(p0.x, 0.055, p0.y)
	# Top horizontal rail (y = 0.62..0.72), blue reflective accent strip (0.55..0.62), mid rail (0.28..0.34)
	_gr_box(st, o, U, N, 0.0, run_len, 0.62, 0.72, -0.045, 0.045, rail_c)
	_gr_box(st, o, U, N, 0.0, run_len, 0.56, 0.62, -0.038, 0.038, accent_c)
	_gr_box(st, o, U, N, 0.0, run_len, 0.24, 0.30, -0.035, 0.035, rail_c.darkened(0.06))
	# Posts every ~4.5m with weighted footplates
	var n_posts := maxi(2, int(round(run_len / 4.5)) + 1)
	for pi in range(n_posts):
		var pu := run_len * float(pi) / float(n_posts - 1)
		_gr_box(st, o, U, N, pu - 0.12, pu + 0.12, 0.0, 0.10, -0.14, 0.14, base_c)
		_gr_box(st, o, U, N, pu - 0.04, pu + 0.04, 0.10, 0.74, -0.045, 0.045, rail_c)


static func _gr_box(
	st: SurfaceTool, o: Vector3, U: Vector3, N: Vector3,
	u0: float, u1: float, y0: float, y1: float, d0: float, d1: float, col: Color
) -> void:
	var p000 := o + U * u0 + N * d0 + Vector3.UP * y0
	var p100 := o + U * u1 + N * d0 + Vector3.UP * y0
	var p110 := o + U * u1 + N * d0 + Vector3.UP * y1
	var p010 := o + U * u0 + N * d0 + Vector3.UP * y1
	var p001 := o + U * u0 + N * d1 + Vector3.UP * y0
	var p101 := o + U * u1 + N * d1 + Vector3.UP * y0
	var p111 := o + U * u1 + N * d1 + Vector3.UP * y1
	var p011 := o + U * u0 + N * d1 + Vector3.UP * y1
	for face: Array in [
		[p001, p101, p111, p011, col],
		[p100, p000, p010, p110, col.darkened(0.05)],
		[p011, p111, p110, p010, col.lightened(0.06)],
		[p000, p001, p011, p010, col.darkened(0.10)],
		[p101, p100, p110, p111, col.darkened(0.10)],
	]:
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var d: Vector3 = face[3]
		var fc: Color = face[4]
		var nrm := (b - a).cross(d - a).normalized()
		for v: Vector3 in [a, b, c, a, c, d]:
			st.set_color(fc)
			st.set_normal(nrm)
			st.add_vertex(v)


# Clearance from point p to the nearest carriageway edge of any OTHER street (negative = inside it)
static func _other_road_clear(seg_grid: Dictionary, p: Vector2, own_road: int) -> float:
	var gk := Vector2i(int(floor(p.x / 20.0)), int(floor(p.y / 20.0)))
	var best := 99.0
	for sg: Array in seg_grid.get(gk, []):
		if int(sg[3]) == own_road:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])
		best = minf(best, p.distance_to(q) - float(sg[2]))
	return best


# Gap (m) to a parallel carriageway just beyond this kerb (a divided road's other half), or -1 if none within 14 m
static func _median_gap(seg_grid: Dictionary, kerb: Vector2, out_n: Vector2, along: Vector2, own_road: int) -> float:
	var o := out_n.normalized()
	var d := 0.5
	while d <= 14.0:
		var pt := kerb + o * d
		var gk := Vector2i(int(floor(pt.x / 20.0)), int(floor(pt.y / 20.0)))
		for sg: Array in seg_grid.get(gk, []):
			if int(sg[3]) == own_road:
				continue
			var q := Geometry2D.get_closest_point_to_segment(pt, sg[0], sg[1])
			if pt.distance_to(q) < float(sg[2]):
				var sd: Vector2 = (sg[1] as Vector2) - (sg[0] as Vector2)
				if sd.length() > 0.1 and absf(sd.normalized().dot(along)) > 0.94:
					return d
				return -1.0 # a crossing street, not a parallel carriageway
		d += 0.5
	return -1.0


# Planted central median of a divided road (grass with a low clipped hedge line), at kerb height
static func _median_green(st: SurfaceTool, a: Vector2, b: Vector2, out_n: Vector2, width: float) -> void:
	var o := out_n.normalized()
	var y := ROAD_Y + KERB_H - 0.01
	var grass := Color(0.21, 0.34, 0.15)
	var aw := a + o * width
	var bw := b + o * width
	for v: Vector2 in [a, b, bw, a, bw, aw]:
		st.set_color(grass)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(v.x, y, v.y))


# How far the sidewalk can extend from the kerb back before it would run onto another street or tram track
static func _walk_width(seg_grid: Dictionary, kerb_back: Vector2, out_n: Vector2, own_road: int, clear_idx: Dictionary = {}) -> float:
	var o := out_n.normalized()
	var chk_trk := not clear_idx.is_empty()
	var d := 0.0
	while d < SIDEWALK_W:
		var pt := kerb_back + o * (d + 0.5)
		if _other_road_clear(seg_grid, pt, own_road) < 0.35:
			return d
		if chk_trk and TrackBuilder.track_clearance_dist(clear_idx, pt) < 1.92:
			return d
		d += 0.5
	return SIDEWALK_W


# Raised sidewalk band behind the kerb (top at kerb height), with a bevelled back edge down to grade.
static func _walk_strip(st: SurfaceTool, a: Vector2, b: Vector2, out_n: Vector2, u0: float, u1: float, width: float, y_off: float = 0.0) -> void:
	var o := out_n.normalized()
	var y := ROAD_Y + KERB_H + y_off
	var ww := clampf(width, 0.3, SIDEWALK_W)
	var aw := a + o * ww
	var bw := b + o * ww
	var ab := a + o * (ww + 0.35)
	var bb := b + o * (ww + 0.35)
	var quads := [
		[Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(bw.x, y, bw.y), Vector3(aw.x, y, aw.y), Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, ww), Vector2(u0, ww)],
		[Vector3(aw.x, y, aw.y), Vector3(bw.x, y, bw.y), Vector3(bb.x, 0.0, bb.y), Vector3(ab.x, 0.0, ab.y), Vector2(u0, ww), Vector2(u1, ww), Vector2(u1, ww + 0.35), Vector2(u0, ww + 0.35)],
	]
	for q: Array in quads:
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(0, 0, 0))
			st.set_normal(Vector3.UP)
			st.set_uv(q[4 + idx])
			st.add_vertex(q[idx])


# Perpendicular kerb ramp: the walk slopes down to road level over 1.5m toward the crosswalk,
# with a yellow truncated-dome warning pad at the bottom; kerb flares are dropped flush.
static func _kerb_ramp(walk_st: SurfaceTool, _curb_st: SurfaceTool, kerb_pt: Vector2, along: Vector2, out_n: Vector2) -> void:
	var o := out_n.normalized()
	var y_top := ROAD_Y + KERB_H
	var ramp_len := 1.6
	var w := 2.4
	var a0 := kerb_pt
	var a1 := kerb_pt + along * ramp_len
	var verts := [
		[Vector3(a0.x, y_top, a0.y), 0.0],
		[Vector3(a1.x, ROAD_Y + 0.02, a1.y), 0.0],
		[Vector3(a1.x + o.x * w, ROAD_Y + 0.02, a1.y + o.y * w), 0.0],
		[Vector3(a0.x + o.x * w, y_top, a0.y + o.y * w), 0.0],
	]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		walk_st.set_color(Color(0, 0, 0))
		walk_st.set_normal(Vector3.UP)
		walk_st.set_uv(Vector2(0.0, 2.0))
		walk_st.add_vertex(verts[idx][0])
	# Tactile pad on the lower 0.6m of the ramp + landing beyond it
	var t0 := kerb_pt + along * (ramp_len - 0.6)
	var t1 := kerb_pt + along * (ramp_len + 0.6)
	var y0 := lerpf(y_top, ROAD_Y + 0.02, (ramp_len - 0.6) / ramp_len) + 0.015
	var pad := [
		Vector3(t0.x + o.x * 0.25, y0, t0.y + o.y * 0.25), Vector3(t1.x + o.x * 0.25, ROAD_Y + 0.035, t1.y + o.y * 0.25),
		Vector3(t1.x + o.x * (w - 0.25), ROAD_Y + 0.035, t1.y + o.y * (w - 0.25)), Vector3(t0.x + o.x * (w - 0.25), y0, t0.y + o.y * (w - 0.25)),
	]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		walk_st.set_color(Color(1, 0, 0))
		walk_st.set_normal(Vector3.UP)
		walk_st.set_uv(Vector2.ZERO)
		walk_st.add_vertex(pad[idx])
	# Landing slab beyond the ramp so the walk meets the crosswalk at grade
	var l1 := kerb_pt + along * (ramp_len + 0.9)
	var land := [
		Vector3(a1.x, ROAD_Y + 0.02, a1.y), Vector3(l1.x, ROAD_Y + 0.02, l1.y),
		Vector3(l1.x + o.x * w, ROAD_Y + 0.02, l1.y + o.y * w), Vector3(a1.x + o.x * w, ROAD_Y + 0.02, a1.y + o.y * w),
	]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		walk_st.set_color(Color(0, 0, 0))
		walk_st.set_normal(Vector3.UP)
		walk_st.set_uv(Vector2(0.0, 2.0))
		walk_st.add_vertex(land[idx])


# Furniture zone items every ~9m, chosen by a stable hash of the location
static func _place_furniture(furn: Dictionary, kerb_a: Vector2, dir: Vector2, out_n: Vector2, run: float, u_base: float) -> void:
	var o := out_n.normalized()
	var t := 4.5
	while t < run - 2.0:
		var p := kerb_a + dir * t
		var h := absf(sin((p.x * 12.9898 + p.y * 78.233)) * 43758.5453)
		h = h - floor(h)
		var yaw := atan2(dir.x, dir.y)
		var base := Vector3(p.x + o.x * 0.85, ROAD_Y + KERB_H, p.y + o.y * 0.85)
		var key := ""
		if h < 0.16:
			key = "bin"
		elif h < 0.27:
			key = "rack"
		elif h < 0.34:
			key = "hydrant"
		elif h < 0.50:
			key = "pay"
		elif h < 0.58:
			key = "news"
		elif h < 0.76:
			key = "cover"
			base = Vector3(p.x + o.x * 2.6, ROAD_Y + KERB_H + 0.004, p.y + o.y * 2.6)
		if key != "":
			(furn[key] as Array).append(Transform3D(Basis(Vector3.UP, yaw), base))
		t += 9.0


static var _furn_meshes: Dictionary = {}


static func _furn_mesh(key: String) -> Mesh:
	if _furn_meshes.has(key):
		return _furn_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match key:
		"bin": # Seattle downtown litter can: dark green slatted body, domed lid
			_cyl_into(st, 0.30, 0.0, 0.92, 12, Color(0.12, 0.22, 0.16))
			_cyl_into(st, 0.33, 0.92, 1.02, 12, Color(0.16, 0.18, 0.18))
			_cyl_into(st, 0.32, 0.0, 0.06, 12, Color(0.10, 0.10, 0.10))
		"rack": # inverted-U bike racks, galvanised
			for x: float in [-0.35, 0.35]:
				_box_into(st, Vector3(x, 0.42, 0.0), Vector3(0.05, 0.84, 0.05), Color(0.55, 0.57, 0.58))
				_box_into(st, Vector3(x, 0.84, 0.0), Vector3(0.05, 0.05, 0.8), Color(0.55, 0.57, 0.58))
				_box_into(st, Vector3(x, 0.42, 0.38), Vector3(0.05, 0.84, 0.05), Color(0.55, 0.57, 0.58))
				_box_into(st, Vector3(x, 0.42, -0.38), Vector3(0.05, 0.84, 0.05), Color(0.55, 0.57, 0.58))
		"hydrant": # Seattle fire hydrant: yellow barrel, silver bonnet & nozzles
			_cyl_into(st, 0.13, 0.0, 0.62, 10, Color(0.88, 0.70, 0.10))
			_cyl_into(st, 0.16, 0.0, 0.08, 10, Color(0.80, 0.62, 0.10))
			_cyl_into(st, 0.10, 0.62, 0.78, 10, Color(0.72, 0.73, 0.74))
			_box_into(st, Vector3(0.0, 0.45, 0.0), Vector3(0.42, 0.10, 0.10), Color(0.72, 0.73, 0.74))
		"pay": # parking pay station: grey kiosk with blue sign panel
			_box_into(st, Vector3(0.0, 0.70, 0.0), Vector3(0.36, 1.40, 0.28), Color(0.30, 0.32, 0.34))
			_box_into(st, Vector3(0.0, 1.30, -0.145), Vector3(0.30, 0.18, 0.01), Color(0.10, 0.32, 0.62))
			_box_into(st, Vector3(0.0, 1.05, -0.145), Vector3(0.18, 0.14, 0.01), Color(0.15, 0.30, 0.25))
		"news": # cluster of newspaper boxes
			var cols: Array[Color] = [Color(0.12, 0.22, 0.45), Color(0.70, 0.12, 0.10), Color(0.85, 0.85, 0.82)]
			for k in range(3):
				var x := (float(k) - 1.0) * 0.5
				_box_into(st, Vector3(x, 0.55, 0.0), Vector3(0.44, 0.75, 0.38), cols[k])
				_box_into(st, Vector3(x, 0.10, 0.0), Vector3(0.06, 0.2, 0.06), Color(0.2, 0.2, 0.2))
		"cover": # cast-iron utility / water-meter cover
			_cyl_into(st, 0.38, 0.0, 0.012, 16, Color(0.22, 0.21, 0.20))
	st.generate_normals()
	var m := st.commit()
	_furn_meshes[key] = m
	return m


static func _build_furniture(parent: Node3D, furn: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "StreetFurniture"
	parent.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.metallic = 0.3
	# Coarse 360m chunks cut ~1,800 furniture draw calls down to ~140 with identical visuals;
	# tiny sidewalk clutter (hydrants/bins/covers) skips shadow-map passes to keep FPS smooth!
	for key: String in furn.keys():
		var tfs: Array = furn[key]
		if tfs.is_empty():
			continue
		var chunks := {}
		for tf: Transform3D in tfs:
			var ck := Vector2i(int(floor(tf.origin.x / 360.0)), int(floor(tf.origin.z / 360.0)))
			if not chunks.has(ck):
				chunks[ck] = []
			(chunks[ck] as Array).append(tf)
		for ck: Vector2i in chunks.keys():
			var ctfs: Array = chunks[ck]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _furn_mesh(key)
			mm.instance_count = ctfs.size()
			for i in range(ctfs.size()):
				var ftf: Transform3D = ctfs[i]
				if Terrain.active:
					ftf.origin.y += Terrain.surface(ftf.origin.x, ftf.origin.z)
				mm.set_instance_transform(i, ftf)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Furniture_%s_%d_%d" % [key, ck.x, ck.y]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.visibility_range_end = 220.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if Terrain.active:
				mmi.set_meta("on_terrain", true)
			root.add_child(mmi)


static func _box_into(st: SurfaceTool, c: Vector3, sz: Vector3, col: Color) -> void:
	var h := sz * 0.5
	var faces := [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
	]
	for f: Array in faces:
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(c + (f[idx] as Vector3) * h)


static func _cyl_into(st: SurfaceTool, r: float, y0: float, y1: float, segs: int, col: Color) -> void:
	for k in range(segs):
		var a0 := TAU * float(k) / float(segs)
		var a1 := TAU * float(k + 1) / float(segs)
		var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
		for v: Vector3 in [p0 + Vector3.UP * y0, p1 + Vector3.UP * y1, p1 + Vector3.UP * y0, p0 + Vector3.UP * y0, p0 + Vector3.UP * y1, p1 + Vector3.UP * y1]:
			st.set_color(col)
			st.add_vertex(v)
		for v: Vector3 in [Vector3.UP * y1, p1 + Vector3.UP * y1, p0 + Vector3.UP * y1]:
			st.set_color(col.lightened(0.05))
			st.add_vertex(v)


# Granite kerb: 0.30m wide top with chamfered arris + 0.15m riser facing the roadway, gutter strip in front
static func _kerb_piece(st: SurfaceTool, a: Vector2, b: Vector2, out_n: Vector2, y: float) -> void:
	var o := out_n.normalized()
	var y_top := y + 0.15
	var a_r := Vector3(a.x, y, a.y)
	var b_r := Vector3(b.x, y, b.y)
	var a_c := Vector3(a.x + o.x * 0.04, y_top, a.y + o.y * 0.04)
	var b_c := Vector3(b.x + o.x * 0.04, y_top, b.y + o.y * 0.04)
	var a_t := Vector3(a.x + o.x * 0.32, y_top, a.y + o.y * 0.32)
	var b_t := Vector3(b.x + o.x * 0.32, y_top, b.y + o.y * 0.32)
	var face_n := Vector3(-o.x, 0.0, -o.y)
	_add_flat_quad(st, a_r, b_r, b_c - Vector3(0, 0.03, 0), a_c - Vector3(0, 0.03, 0), face_n)
	_add_flat_quad(st, a_c - Vector3(0, 0.03, 0), b_c - Vector3(0, 0.03, 0), b_c, a_c, (face_n + Vector3.UP).normalized())
	_add_flat_quad(st, a_c, b_c, b_t, a_t, Vector3.UP)
	# Concrete gutter pan strip (slightly lighter than asphalt) in front of the kerb
	var a_g := Vector3(a.x - o.x * 0.45, y + 0.018, a.y - o.y * 0.45)
	var b_g := Vector3(b.x - o.x * 0.45, y + 0.018, b.y - o.y * 0.45)
	_add_flat_quad(st, a_g, b_g, b_r + Vector3(0, 0.018, 0), a_r + Vector3(0, 0.018, 0), Vector3.UP)
