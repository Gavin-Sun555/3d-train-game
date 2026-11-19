class_name CityBuilder
extends RefCounted


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
	var sx: float = (float(bounds[2]) - float(bounds[0])) + 620.0
	var sz: float = (float(bounds[3]) - float(bounds[1])) + 620.0

	# 1. Brushed expansion-joint concrete sidewalk ground slab
	var ground_mi := MeshInstance3D.new()
	ground_mi.name = "UrbanSidewalkBase"
	var g_mesh := PlaneMesh.new()
	g_mesh.size = Vector2(sx, sz)
	ground_mi.mesh = g_mesh
	ground_mi.position = Vector3(cx, -0.01, cz)
	ground_mi.material_override = sidewalk_mat
	ground_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ground_mi)

	# 2. Plazas, brick squares, parks & water
	_build_areas(parent, map_data.get("areas", []))

	# 3. Realistic weathered asphalt streets, 3D granite curbs, lane dashes & crosswalks
	_build_roads_and_curbs(parent, map_data.get("roads", []), map_data.get("crosswalks", []), road_mat)

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
	if parent.has_meta("water_mat"):
		(lm_info["night_mats"] as Array).append(parent.get_meta("water_mat"))
	LandmarkFacades.build_plazas(parent, map_data.get("plazas", []), lm_info["lights"])

	# 6. Vintage Seattle streetlamps (with real warm night light pools)
	var lamp_lights := _build_streetlamps(parent, map_data.get("streetlamps", []), globe_mat)
	for ll in lamp_lights:
		lm_info["lights"].append(ll)

	# 7. Realistic multi-branched urban street & park trees with cast-iron sidewalk grates
	_build_trees(parent, map_data.get("trees", []))

	return lm_info


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
		"brick": [],
		"plaza": [],
	}
	for a in areas:
		var kind: String = str(a.get("kind", ""))
		if kind == "water":
			buckets["water"].append(a)
		elif kind in ["park", "grass", "wood", "meadow", "garden"]:
			buckets["park"].append(a)
		elif kind == "brick_plaza":
			buckets["brick"].append(a)
		else:
			buckets["plaza"].append(a)

	_emit_area_group(parent, "WaterAreas", buckets["water"], 0.000, Color(0.08, 0.22, 0.30), 0.06, 0.35)
	_emit_area_group(parent, "ParkAreas", buckets["park"], 0.010, Color(0.20, 0.35, 0.14), 0.90, 0.0)
	_emit_area_group(parent, "BrickPlazas", buckets["brick"], 0.026, Color(0.45, 0.27, 0.22), 0.84, 0.0)
	_emit_area_group(parent, "PlazaAreas", buckets["plaza"], 0.018, Color(0.39, 0.38, 0.36), 0.86, 0.0)


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
	for a in list:
		var poly := _clean_poly(a.get("pts", []))
		if poly.size() < 3:
			continue
		var idx := Geometry2D.triangulate_polygon(poly)
		for i in range(0, idx.size(), 3):
			for rp: Vector2 in [poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(rp.x, y_level, rp.y))
			tri_count += 1
	if tri_count == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
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
	if node_name == "ParkAreas":
		# Mown-lawn texture: two octaves of noise give patchy light/dark grass instead of flat green
		var nz := FastNoiseLite.new()
		nz.frequency = 0.035
		nz.fractal_octaves = 4
		var ntex := NoiseTexture2D.new()
		ntex.width = 256
		ntex.height = 256
		ntex.seamless = true
		ntex.noise = nz
		var grad := Gradient.new()
		grad.set_color(0, Color(0.62, 0.78, 0.48))
		grad.set_color(1, Color(1.05, 1.12, 0.86))
		ntex.color_ramp = grad
		mat.albedo_texture = ntex
		mat.albedo_color = Color(0.27, 0.42, 0.18)
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.08, 0.08, 0.08)
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
	road_mat: ShaderMaterial
) -> void:
	if roads.is_empty():
		return
	var road_st := SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mark_st := SurfaceTool.new()
	mark_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var curb_st := SurfaceTool.new()
	curb_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var has_road := false
	var has_mark := false
	var has_curb := false

	var road_level := _road_height_levels(roads)
	for road_i in range(roads.size()):
		var r: Dictionary = roads[road_i]
		var raw_pts: Array = r.get("pts", [])
		if raw_pts.size() < 2:
			continue
		var hw: float = clampf(float(r.get("width", 12.0)) * 0.5, 3.2, 10.5)
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
			var a_ext := a - dir * minf(hw * 0.55, 2.6)
			var b_ext := b + dir * minf(hw * 0.55, 2.6)
			# Road quads overlap at junctions and polyline bends: give each a fixed, distinct height so the
			# overlap always resolves the same way (exactly coplanar overlaps z-fight and flicker in motion)
			y = y_base + float(road_level[road_i]) * 0.0015 + float(i % 2) * 0.0005

			var v0 := Vector3(a_ext.x - nrm.x, y, a_ext.y - nrm.y)
			var v1 := Vector3(a_ext.x + nrm.x, y, a_ext.y + nrm.y)
			var v2 := Vector3(b_ext.x + nrm.x, y, b_ext.y + nrm.y)
			var v3 := Vector3(b_ext.x - nrm.x, y, b_ext.y - nrm.y)

			road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(-1.0, 0.0)); road_st.add_vertex(v0)
			road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(1.0, 0.0)); road_st.add_vertex(v1)
			road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(1.0, seg_len)); road_st.add_vertex(v2)
			road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(-1.0, 0.0)); road_st.add_vertex(v0)
			road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(1.0, seg_len)); road_st.add_vertex(v2)
			road_st.set_normal(Vector3.UP); road_st.set_uv(Vector2(-1.0, seg_len)); road_st.add_vertex(v3)
			has_road = true

			# Dashed lane markings
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
		var cw_w := clampf(float(cw.get("width", 12.0)) * 0.44, 3.0, 8.0)
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
		road_mi.mesh = road_st.commit()
		road_mi.material_override = road_mat
		road_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(road_mi)

	parent.set_meta("kerb_roads", roads)
	parent.set_meta("road_mat", road_mat)
	_build_kerbs(parent, roads, [], road_mat)

	if has_mark:
		var mark_mi := MeshInstance3D.new()
		mark_mi.name = "RoadMarkings"
		mark_mi.mesh = mark_st.commit()
		var m_mat := StandardMaterial3D.new()
		m_mat.albedo_color = Color(0.78, 0.77, 0.73)
		m_mat.roughness = 0.82
		m_mat.metallic_specular = 0.18
		m_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mark_mi.material_override = m_mat
		mark_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mark_mi)


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

	var b_idx := 0
	var any_geom := false

	for b in buildings:
		var poly := _clean_poly(b.get("pts", []))
		if poly.size() < 3:
			continue
		if str(b.get("lm", "")) in SeattleV2Landmarks.SKIP_GENERIC:
			continue # built as a dedicated landmark model
		var h: float = clampf(float(b.get("h", 14.0)), 5.0, 185.0)
		var style: int = clampi(int(b.get("style", 2)), 0, 2)
		# Real-world look for named OSM buildings (landmark facades, recorded building colours)
		var lm_o: Dictionary = LandmarkFacades.override_for(b)
		if not lm_o.is_empty():
			if int(lm_o["style"]) >= 0:
				style = int(lm_o["style"])
			if float(lm_o["h"]) > 0.0:
				h = float(lm_o["h"])
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()

		var base_c: Color
		var trim_c: Color
		if style == 0:
			base_c = glass_pal[b_idx % glass_pal.size()]
			trim_c = Color(0.48, 0.51, 0.54) # Brushed aluminum / dark steel mullions & columns
		elif style == 1:
			base_c = brick_pal[b_idx % brick_pal.size()]
			trim_c = base_c.lerp(Color(0.80, 0.77, 0.71), 0.55) # Carved limestone piers & cornices
		else:
			base_c = mod_pal[b_idx % mod_pal.size()]
			trim_c = base_c.lightened(0.06)

		if not lm_o.is_empty():
			base_c = lm_o["color"]
			trim_c = base_c.lightened(0.10) if style != 0 else trim_c
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

		if has_setback:
			# Extrude street-edge podium (0 .. podium_h) + setback upper tower (podium_h .. h)
			_extrude_tier_with_3d_relief(st, frame_st, poly, 0.0, podium_h, style, vcol, trim_c, true)
			_extrude_tier_with_3d_relief(st, frame_st, tower_poly, podium_h, h, style, vcol, trim_c, false)
			has_frames = true
			any_geom = true
		else:
			_extrude_tier_with_3d_relief(st, frame_st, poly, 0.0, h, style, vcol, trim_c, true)
			has_frames = true
			any_geom = true

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
		if Geometry2D.is_point_in_polygon(center2, top_poly) and span.x > 16.0 and span.y > 16.0 and h >= 15.0:
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
					Vector3(center2.x, h + ph + 1.2, center2.y),
					beacon_mat
				)

	if any_geom:
		var b_mi := MeshInstance3D.new()
		b_mi.name = "Buildings"
		b_mi.mesh = st.commit()
		b_mi.material_override = building_mat
		b_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(b_mi)

	if has_frames:
		var f_mi := MeshInstance3D.new()
		f_mi.name = "BuildingFrames3D"
		f_mi.mesh = frame_st.commit()
		var f_mat := StandardMaterial3D.new()
		f_mat.vertex_color_use_as_albedo = true
		f_mat.roughness = 0.76
		f_mat.metallic = 0.08
		f_mat.metallic_specular = 0.28
		f_mi.material_override = f_mat
		f_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(f_mi)


static func _extrude_tier_with_3d_relief(
	st: SurfaceTool,
	frame_st: SurfaceTool,
	poly: PackedVector2Array,
	y_bot: float,
	y_top: float,
	style: int,
	vcol: Color,
	trim_c: Color,
	include_ground_cornice: bool
) -> void:
	var parapet_h := 0.90 if style != 0 else 1.15
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
	parent.add_child(light_holder)

	for i in range(count):
		var lx := float(lamps[i][0])
		var lz := float(lamps[i][1])
		post_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(lx, 2.30, lz)))
		globe_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(lx, 4.72, lz)))

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
			ol.position = Vector3(lx, 4.55, lz)
			light_holder.add_child(ol)
			night_lights.append(ol)

	var p_inst := MultiMeshInstance3D.new()
	p_inst.name = "StreetlampPosts"
	p_inst.multimesh = post_mm
	parent.add_child(p_inst)

	var g_inst := MultiMeshInstance3D.new()
	g_inst.name = "StreetlampGlobes"
	g_inst.multimesh = globe_mm
	g_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(g_inst)

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


# Hide streetlamps / street trees that would stand on (or overhang) laid tram track.
# Re-run after every track rebuild; original transforms are kept in metadata so removed track restores them.
static func apply_track_clearance(city_root: Node3D, clear_idx: Dictionary, bays: Array = []) -> void:
	if city_root == null:
		return
	var lamp_posts := city_root.get_node_or_null("StreetlampPosts") as MultiMeshInstance3D
	var lamp_hidden := _clearance_hidden_set(lamp_posts, clear_idx, TrackBuilder.LAMP_CLEARANCE_M, bays)
	_apply_hidden(lamp_posts, lamp_hidden, 1)
	_apply_hidden(city_root.get_node_or_null("StreetlampGlobes") as MultiMeshInstance3D, lamp_hidden, 1)
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
	var base := _base_tfs(mmi)
	var mm := mmi.multimesh
	for i in range(base.size()):
		var tf: Transform3D = base[i]
		if hidden.has(i / group):
			tf = Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), tf.origin + Vector3(0.0, -200.0, 0.0))
		mm.set_instance_transform(i, tf)



# Rebuild the granite kerbs after tracks change: kerbs are cut back into bays around side platforms
# (see TrackBuilder.station_bay) and the bay itself is paved as roadway.
static func apply_station_bays(city_root: Node3D, bays: Array) -> void:
	if city_root == null or not city_root.has_meta("kerb_roads"):
		return
	_build_kerbs(city_root, city_root.get_meta("kerb_roads"), bays, city_root.get_meta("road_mat"))


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


static func _build_kerbs(parent: Node3D, roads: Array, bays: Array, road_mat: Material) -> void:
	for nm: String in ["GraniteCurbs", "StationKerbBays", "Sidewalks", "StreetFurniture"]:
		var old := parent.get_node_or_null(nm)
		if old != null:
			parent.remove_child(old)
			old.queue_free()
	# Junction degree per road end-point (kerbs/sidewalks stop + ramp down only at real intersections)
	var deg := {}
	for r in roads:
		var rp: Array = r.get("pts", [])
		if rp.size() < 2 or int(r.get("layer", 0)) != 0:
			continue
		for e_pt in [rp[0], rp[rp.size() - 1]]:
			var key := Vector2i(int(round(float(e_pt[0]) * 2.0)), int(round(float(e_pt[1]) * 2.0)))
			deg[key] = int(deg.get(key, 0)) + 1
	# Spatial grid of all carriageway segments, to keep kerbs/sidewalks out of other streets
	var seg_grid := {}
	for ri in range(roads.size()):
		var rr: Dictionary = roads[ri]
		var rp2: Array = rr.get("pts", [])
		if rp2.size() < 2 or int(rr.get("layer", 0)) != 0:
			continue
		var rhw: float = clampf(float(rr.get("width", 12.0)) * 0.5, 3.2, 10.5)
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
	var furn := {"bin": [], "rack": [], "hydrant": [], "pay": [], "news": [], "cover": []}
	var has_curb := false
	for road_i in range(roads.size()):
		var r: Dictionary = roads[road_i]
		var raw_pts: Array = r.get("pts", [])
		if raw_pts.size() < 2 or int(r.get("layer", 0)) != 0:
			continue
		var hw: float = clampf(float(r.get("width", 12.0)) * 0.5, 3.2, 10.5)
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
				trim0 = minf(trim0, 3.8)
				trim1 = minf(trim1, 3.8)
			var c_start := a + dir * trim0
			var run := seg_len - trim0 - trim1
			if run <= 2.0:
				u_acc += seg_len
				continue
			for side: float in [-1.0, 1.0]:
				var nrm := Vector2(-dir.y, dir.x) * side
				var pieces: Array = []
				var n_s := int(ceil(run / 0.5))
				var cur0 := -1.0
				for k in range(n_s + 1):
					var t := minf(float(k) * 0.5, run)
					var kp := c_start + dir * t + nrm * hw
					var keep := (bays.is_empty() or not _in_bay(bays, kp)) and _other_road_clear(seg_grid, kp, road_i) > -0.2
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
					# Sidewalk in <=2m chunks, each as wide as it can be before reaching another carriageway
					var n_ch := maxi(1, int(ceil((t1 - t0) / 2.0)))
					var w_prev := _walk_width(seg_grid, c_start + dir * t0 + nrm * (hw + 0.32), nrm, road_i)
					for ch in range(n_ch):
						var ta := lerpf(t0, t1, float(ch) / float(n_ch))
						var tb := lerpf(t0, t1, float(ch + 1) / float(n_ch))
						var w_next := _walk_width(seg_grid, c_start + dir * tb + nrm * (hw + 0.32), nrm, road_i)
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
	if has_curb:
		var curb_mi := MeshInstance3D.new()
		curb_mi.name = "GraniteCurbs"
		curb_mi.mesh = curb_st.commit()
		var c_mat := StandardMaterial3D.new()
		c_mat.albedo_color = Color(0.60, 0.59, 0.56)
		c_mat.roughness = 0.78
		c_mat.metallic_specular = 0.22
		c_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		curb_mi.material_override = c_mat
		curb_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(curb_mi)
		var w_mi := MeshInstance3D.new()
		w_mi.name = "Sidewalks"
		w_mi.mesh = walk_st.commit()
		var w_mat := ShaderMaterial.new()
		w_mat.shader = load("res://shaders/sidewalk_strip.gdshader") as Shader
		w_mi.material_override = w_mat
		w_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(w_mi)
		_build_furniture(parent, furn)
	if has_bay:
		var bay_mi := MeshInstance3D.new()
		bay_mi.name = "StationKerbBays"
		bay_mi.mesh = bay_st.commit()
		bay_mi.material_override = road_mat
		bay_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(bay_mi)


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


# How far the sidewalk can extend from the kerb back before it would run onto another street
static func _walk_width(seg_grid: Dictionary, kerb_back: Vector2, out_n: Vector2, own_road: int) -> float:
	var o := out_n.normalized()
	var d := 0.0
	while d < SIDEWALK_W:
		if _other_road_clear(seg_grid, kerb_back + o * (d + 0.5), own_road) < 0.35:
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
	# Chunked (~120m) so each batch is frustum- and distance-culled on its own
	for key: String in furn.keys():
		var tfs: Array = furn[key]
		if tfs.is_empty():
			continue
		var chunks := {}
		for tf: Transform3D in tfs:
			var ck := Vector2i(int(floor(tf.origin.x / 120.0)), int(floor(tf.origin.z / 120.0)))
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
				mm.set_instance_transform(i, ctfs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Furniture_%s_%d_%d" % [key, ck.x, ck.y]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.visibility_range_end = 240.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key == "cover" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
