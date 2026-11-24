class_name TramBuilder
extends RefCounted


static func build_tram(spec: Dictionary, override_sections: int = -1) -> Dictionary:
	var root := Node3D.new()
	root.name = "TramVehicle"

	var default_sec := maxi(1, int(spec.get("default_sections", spec.get("sections", 3))))
	var sections_count := clampi(override_sections if override_sections > 0 else default_sec, 1, 5)
	var sec_len := float(spec.get("section_len", 9.2))
	var width := float(spec.get("width", 2.60))
	var vintage := bool(spec.get("vintage", false))
	var nose_kind := str(spec.get("nose", "streamlined"))
	var roof_kind := str(spec.get("roof", "shrouded"))
	var panto_kind := str(spec.get("panto", "single_arm"))
	var single_lamp := bool(spec.get("single_headlamp", false))
	var monorail := bool(spec.get("monorail", false))

	var b_arr: Array = spec.get("body_color", [0.92, 0.95, 0.94])
	var a_arr: Array = spec.get("accent_color", [0.12, 0.45, 0.72])
	var r_arr: Array = spec.get("roof_color", [0.24, 0.28, 0.31])
	var s_arr: Array = spec.get("seat_color", [0.18, 0.42, 0.62])

	var body_col := Color(float(b_arr[0]), float(b_arr[1]), float(b_arr[2]))
	var accent_col := Color(float(a_arr[0]), float(a_arr[1]), float(a_arr[2]))
	var roof_col := Color(float(r_arr[0]), float(r_arr[1]), float(r_arr[2]))
	var seat_col := Color(float(s_arr[0]), float(s_arr[1]), float(s_arr[2]))

	var body_sh := load("res://shaders/tram_body_pbr.gdshader") as Shader
	var cab_sh := load("res://shaders/tram_cab_pbr.gdshader") as Shader
	var glass_sh := load("res://shaders/tram_glass_pbr.gdshader") as Shader

	var mat_body := ShaderMaterial.new()
	mat_body.shader = body_sh
	mat_body.set_shader_parameter("base_color", body_col)
	# Painted car body: dielectric paint under a satin clear coat (no chrome-like sky mirroring)
	mat_body.set_shader_parameter("metallic_val", 0.04 if not vintage else 0.06)
	mat_body.set_shader_parameter("rough_val", 0.30 if not vintage else 0.36)
	mat_body.set_shader_parameter("clearcoat_val", 0.55 if not vintage else 0.45)
	mat_body.set_shader_parameter("seam_strength", 0.42)

	var mat_accent := ShaderMaterial.new()
	mat_accent.shader = body_sh
	mat_accent.set_shader_parameter("base_color", accent_col)
	mat_accent.set_shader_parameter("metallic_val", 0.04)
	mat_accent.set_shader_parameter("rough_val", 0.28)
	mat_accent.set_shader_parameter("clearcoat_val", 0.55)
	mat_accent.set_shader_parameter("seam_strength", 0.30)

	var mat_roof := ShaderMaterial.new()
	mat_roof.shader = body_sh
	mat_roof.set_shader_parameter("base_color", roof_col)
	mat_roof.set_shader_parameter("metallic_val", 0.12)
	mat_roof.set_shader_parameter("rough_val", 0.48)
	mat_roof.set_shader_parameter("clearcoat_val", 0.20)
	mat_roof.set_shader_parameter("seam_strength", 0.50)

	var mat_dark := ShaderMaterial.new()
	mat_dark.shader = cab_sh
	mat_dark.set_shader_parameter("base_color", Color(0.12, 0.14, 0.16))
	mat_dark.set_shader_parameter("is_wood", 0.0)
	mat_dark.set_shader_parameter("rough_val", 0.56)
	mat_dark.set_shader_parameter("metal_val", 0.24)

	var mat_floor := _make_mat(Color(0.88, 0.90, 0.92) if not vintage else Color(0.32, 0.24, 0.17), 0.78, 0.04)
	if not vintage:
		mat_floor.albedo_texture = CabTextureGen.get_cabin_floor_tex()
		mat_floor.uv1_scale = Vector3(4.0, 12.0, 1.0)
	var mat_ceiling := _make_mat(Color(0.88, 0.89, 0.91) if not vintage else Color(0.86, 0.80, 0.68), 0.72, 0.05)
	mat_ceiling.emission_enabled = true
	mat_ceiling.emission = Color(0.96, 0.95, 0.92) if not vintage else Color(0.95, 0.86, 0.68)
	mat_ceiling.emission_energy_multiplier = 0.22
	var mat_lining := _make_mat(Color(0.84, 0.85, 0.86) if not vintage else Color(0.62, 0.44, 0.28), 0.55, 0.05)
	var mat_rubber := _make_mat(Color(0.08, 0.08, 0.09), 0.85, 0.0)
	var mat_ad_a: Material = StationBuilder._poster_mat(0)
	var mat_ad_b: Material = StationBuilder._poster_mat(1)
	var mat_route_map: Material = StationBuilder._poster_mat(2)
	var mat_seat := _make_mat(Color(0.95, 0.96, 0.98), 0.86, 0.02)
	mat_seat.albedo_texture = CabTextureGen.get_moquette_seat_tex(seat_col)
	mat_seat.uv1_scale = Vector3(2.0, 2.0, 1.0)
	var mat_cabin_lcd := StandardMaterial3D.new()
	mat_cabin_lcd.albedo_texture = CabTextureGen.get_cabin_lcd_tex()
	mat_cabin_lcd.emission_enabled = true
	mat_cabin_lcd.emission = Color(0.95, 0.98, 1.0)
	mat_cabin_lcd.emission_texture = CabTextureGen.get_cabin_lcd_tex()
	mat_cabin_lcd.emission_energy_multiplier = 1.25
	mat_cabin_lcd.roughness = 0.22
	var mat_stop_btn := _emit_mat(Color(0.88, 0.16, 0.12), Color(1.0, 0.24, 0.14), 0.75)

	var mat_wood_trim := ShaderMaterial.new()
	mat_wood_trim.shader = cab_sh
	mat_wood_trim.set_shader_parameter("base_color", Color(0.46, 0.27, 0.14))
	mat_wood_trim.set_shader_parameter("is_wood", 1.0)

	var mat_steel := _make_mat(Color(0.76, 0.79, 0.83), 0.22, 0.84)
	var mat_brass := _make_mat(Color(0.85, 0.68, 0.26), 0.24, 0.86)
	var mat_yellow_thresh := _make_mat(Color(0.92, 0.76, 0.14), 0.68, 0.0)

	# Jiaxing T1 (CRRC Changchun 嘉兴有轨电车): pearl-white body, black glazing band, charcoal glazed doors,
	# maroon nose sweep, thin red cantrail line, smooth roof fairing (see _build_jx_nose / _build_jx_fairing)
	var is_jx := nose_kind == "nanhu_swift"
	var mat_glass := ShaderMaterial.new()
	mat_glass.shader = glass_sh
	mat_glass.set_shader_parameter("tint_color", Color(0.03, 0.035, 0.04) if is_jx else Color(0.08, 0.16, 0.22))
	mat_glass.set_shader_parameter("base_alpha", 0.62 if is_jx else 0.30)
	var mat_door_jx := ShaderMaterial.new()
	mat_door_jx.shader = body_sh
	mat_door_jx.set_shader_parameter("base_color", Color(0.20, 0.21, 0.23))
	mat_door_jx.set_shader_parameter("metallic_val", 0.10)
	mat_door_jx.set_shader_parameter("rough_val", 0.32)
	mat_door_jx.set_shader_parameter("clearcoat_val", 0.6)
	mat_door_jx.set_shader_parameter("seam_strength", 0.2)

	var mat_part_glass := ShaderMaterial.new()
	mat_part_glass.shader = glass_sh
	mat_part_glass.set_shader_parameter("tint_color", Color(0.42, 0.56, 0.62))
	mat_part_glass.set_shader_parameter("base_alpha", 0.28)

	var mat_cab_glass := ShaderMaterial.new()
	mat_cab_glass.shader = glass_sh
	mat_cab_glass.set_shader_parameter("tint_color", Color(0.10, 0.18, 0.24))
	mat_cab_glass.set_shader_parameter("base_alpha", 0.14)

	var mat_headlight := _emit_mat(Color(1.0, 0.98, 0.90), Color(1.0, 0.96, 0.84), 2.8)
	var mat_taillight := _emit_mat(Color(0.95, 0.12, 0.12), Color(1.0, 0.12, 0.10), 2.2)
	var mat_led_sign := _emit_mat(Color(0.08, 0.10, 0.12), Color(1.0, 0.68, 0.16), 1.6)
	var mat_cove_light := _emit_mat(Color(0.96, 0.96, 0.92), Color(1.0, 0.95, 0.85), 1.1)
	var mat_door_led := _emit_mat(Color(0.10, 0.35, 0.18), Color(0.18, 0.96, 0.48), 0.0)

	var section_nodes: Array[Node3D] = []
	var gangway_nodes: Array[Node3D] = []
	var door_leaves: Array[Dictionary] = []
	var step_plates: Array[Dictionary] = []
	var onboard_pax_nodes: Array[Node3D] = []
	var onboard_pax_rigs: Array[Dictionary] = []
	var door_world_anchors: Array[Node3D] = []
	var door_portals: Array[Dictionary] = []
	var interior_lights: Array[OmniLight3D] = []
	var head_spot: SpotLight3D = null
	var rear_head_spot: SpotLight3D = null
	var cab_anchor: Node3D = null
	var rear_cab_anchor: Node3D = null
	var interior_anchor: Node3D = null
	var throttle_lever: Node3D = null
	var rear_throttle_lever: Node3D = null
	var cab_controls: Dictionary = {}
	var rear_cab_controls: Dictionary = {}

	var pole_mat: Material = mat_brass if vintage else mat_steel

	for idx in range(sections_count):
		var is_front := (idx == 0)
		var is_rear := (idx == sections_count - 1)
		var sec := Node3D.new()
		sec.name = "Section_%d" % idx
		root.add_child(sec)
		section_nodes.append(sec)

		var hw := width * 0.5
		var hl := sec_len * 0.5
		# Jiaxing raked nose: longitudinal roof / ceiling / cantrail parts stop short of the cab nose
		var zf_cut := -hl + (1.42 if (is_jx and is_front) else 0.0)
		var zr_cut := hl - (1.42 if (is_jx and is_rear) else 0.0)
		var span_c := (zf_cut + zr_cut) * 0.5
		var span_l := zr_cut - zf_cut

		# Doorway center(s) along Z: real open portal cut through side walls!
		var door_z := 0.25 if (is_front and sections_count > 1) else 0.0
		var door_half_w := 0.68 # 1.36m wide clear open double doorway!

		# 1. Floor deck & anti-slip cabin aisle + doorway yellow threshold strips
		_add_box(sec, Vector3(width - 0.04, 0.14, sec_len - 0.18), Vector3(0.0, 0.48, 0.0), mat_body)
		_add_box(sec, Vector3(width - 0.16, 0.03, sec_len - 0.30), Vector3(0.0, 0.56, 0.0), mat_floor)
		for side: float in [-1.0, 1.0]:
			_add_box(
				sec,
				Vector3(0.16, 0.035, door_half_w * 2.0),
				Vector3(side * (hw - 0.10), 0.562, door_z),
				mat_yellow_thresh
			)
			# Doorway world anchors for 3D boarding/alighting passengers (step plate -> inner cabin aisle!)
			var d_anc := Node3D.new()
			d_anc.position = Vector3(side * (hw + 0.14), 0.52 if not vintage else 0.40, door_z)
			sec.add_child(d_anc)
			door_world_anchors.append(d_anc)

			var d_inner := Node3D.new()
			d_inner.position = Vector3(side * 0.12, 0.58, door_z)
			sec.add_child(d_inner)

			var d_aisle := Node3D.new()
			d_aisle.position = Vector3(0.0, 0.58, door_z + (0.65 if idx % 2 == 0 else -0.65))
			sec.add_child(d_aisle)

			door_portals.append({
				"outer": d_anc,
				"inner": d_inner,
				"aisle": d_aisle,
				"side": side,
			})

		# 2. Roof structure + Interior Ceiling + Cove LED Lighting Strips + HVAC Diffusers!
		_add_box(sec, Vector3(width - 0.04, 0.22, span_l - 0.16), Vector3(0.0, 3.04, span_c), mat_roof)
		_add_box(sec, Vector3(width - 0.18, 0.04, span_l - 0.34), Vector3(0.0, 2.91, span_c), mat_ceiling)
		for side: float in [-0.52, 0.52]:
			_add_box(sec, Vector3(0.20, 0.03, span_l - 1.4), Vector3(side, 2.885, span_c), mat_cove_light)
		# Angled cove panels from cantrail to ceiling carrying ad frames + route-map strip
		var cove_x0 := hw - 0.08
		var cove_dx := cove_x0 - 0.66
		var cove_dy := 0.25
		var cove_len := sqrt(cove_dx * cove_dx + cove_dy * cove_dy)
		var cove_ang := atan2(cove_dy, cove_dx)
		for c_side: float in [-1.0, 1.0]:
			var cove_mid := Vector3(c_side * (cove_x0 + 0.66) * 0.5, 2.64 + cove_dy * 0.5, span_c)
			var cove := _add_box(sec, Vector3(cove_len, 0.025, span_l - 0.5), cove_mid, mat_ceiling)
			cove.rotation.z = -c_side * cove_ang
			var n_frames := maxi(1, int((span_l - 1.6) / 1.05))
			for f_i in range(n_frames):
				var fz := -((span_l - 1.6) * 0.5) + (float(f_i) + 0.5) * ((span_l - 1.6) / float(n_frames))
				var f_mat: Material = mat_route_map if f_i == n_frames / 2 else (mat_ad_a if (f_i + idx) % 2 == 0 else mat_ad_b)
				var fr := _add_box(sec, Vector3(cove_len * 0.62, 0.012, 0.86), cove_mid + Vector3(-c_side * 0.006, -0.016, fz), f_mat)
				fr.rotation.z = -c_side * cove_ang
		# Center ceiling longitudinal HVAC diffuser grille slats
		for vz: float in [-2.4, -0.8, 0.8, 2.4]:
			if absf(vz) < hl - 1.1:
				_add_box(sec, Vector3(0.34, 0.024, 0.92), Vector3(0.0, 2.886, vz), mat_dark)
				_add_box(sec, Vector3(0.28, 0.028, 0.84), Vector3(0.0, 2.884, vz), mat_steel)
		# Interior overhead Next-Stop Passenger Information LCD Display (high-res route map!)
		_add_box(sec, Vector3(0.88, 0.24, 0.07), Vector3(0.0, 2.68, -hl * 0.36), mat_dark)
		_add_quad(sec, Vector2(0.82, 0.20), Vector3(0.0, 2.68, -hl * 0.36 + 0.038), Vector3.ZERO, mat_cabin_lcd)
		_add_quad(sec, Vector2(0.82, 0.20), Vector3(0.0, 2.68, -hl * 0.36 - 0.038), Vector3(0.0, 180.0, 0.0), mat_cabin_lcd)

		# Upper cantrail header band above windows & doors (y = 2.66 .. 2.94)
		# (side-wall strips only: a full-width slab here would form a low lid over the cabin)
		for cr_side: float in [-1.0, 1.0]:
			_add_box(sec, Vector3(0.10, 0.28, span_l - 0.16), Vector3(cr_side * (hw - 0.05), 2.80, span_c), mat_body)
			_add_box(sec, Vector3(0.11, 0.08, span_l - 0.16), Vector3(cr_side * (hw - 0.0475), 2.68, span_c), mat_accent)

		# 3. Split Side Walls & Windows cleanly BEFORE and AFTER the open 1.36m Doorway!
		var z_body_front := -hl + (1.42 if is_front else 0.22)
		var z_body_rear := hl - (1.42 if is_rear else 0.22)
		var wall_spans: Array[Vector2] = [
			Vector2(z_body_front, door_z - door_half_w),
			Vector2(door_z + door_half_w, z_body_rear),
		]

		for side: float in [-1.0, 1.0]:
			for sp: Vector2 in wall_spans:
				var span_len := sp.y - sp.x
				if span_len < 0.35:
					continue
				var span_mid := (sp.x + sp.y) * 0.5
				# Lower waist wall (y = 0.55 .. 1.28) + livery belt stripe
				_add_box(sec, Vector3(0.08, 0.74, span_len), Vector3(side * (hw - 0.04), 0.92, span_mid), mat_body)
				if not is_jx:
					_add_box(sec, Vector3(0.095, 0.20, span_len), Vector3(side * (hw - 0.04), 0.96, span_mid), mat_accent)
				# Interior lining below the windows with dark kick plate, rubber window gaskets
				_add_box(sec, Vector3(0.02, 0.62, span_len - 0.04), Vector3(side * (hw - 0.095), 1.0, span_mid), mat_lining)
				_add_box(sec, Vector3(0.022, 0.13, span_len - 0.04), Vector3(side * (hw - 0.096), 0.635, span_mid), mat_dark)
				_add_box(sec, Vector3(0.06, 0.04, span_len), Vector3(side * (hw - 0.085), 1.30, span_mid), mat_rubber)
				_add_box(sec, Vector3(0.06, 0.04, span_len), Vector3(side * (hw - 0.085), 2.63, span_mid), mat_rubber)
				# Panoramic window glass (y = 1.28 .. 2.66)
				_add_box(sec, Vector3(0.035, 1.38, span_len), Vector3(side * (hw - 0.04), 1.97, span_mid), mat_glass)

				# Window mullions (wood/cream on vintage, slim dark on modern)
				var mul_n := maxi(1, int(round(span_len / (1.15 if vintage else 1.75))))
				for m_i in range(mul_n + 1):
					var mz := lerpf(sp.x, sp.y, float(m_i) / float(mul_n))
					_add_box(
						sec,
						Vector3(0.075, 1.40, 0.09),
						Vector3(side * (hw - 0.038), 1.97, mz),
						mat_wood_trim if vintage else mat_dark
					)

			# Doorway vertical portal frames + green boarding LED status strip
			for d_edge: float in [door_z - door_half_w, door_z + door_half_w]:
				_add_box(sec, Vector3(0.10, 2.12, 0.08), Vector3(side * (hw - 0.04), 1.61, d_edge), mat_dark)
			_add_box(sec, Vector3(0.04, 0.05, door_half_w * 1.9), Vector3(side * (hw + 0.01), 2.64, door_z), mat_door_led)

			# Animated Plug-Sliding / Bi-Fold Double Door Leaves!
			for leaf_dir: float in [-1.0, 1.0]:
				var leaf := Node3D.new()
				var closed_z := door_z + leaf_dir * (door_half_w * 0.5)
				leaf.position = Vector3(side * (hw - 0.01), 1.60, closed_z)
				sec.add_child(leaf)
				_add_box(leaf, Vector3(0.05, 2.06, door_half_w - 0.02), Vector3.ZERO, mat_door_jx if is_jx else (mat_accent if not vintage else mat_wood_trim))
				if is_jx:
					_add_box(leaf, Vector3(0.06, 1.66, door_half_w - 0.14), Vector3(0.0, 0.12, 0.0), mat_glass)
				else:
					_add_box(leaf, Vector3(0.06, 1.22, door_half_w - 0.18), Vector3(0.0, 0.18, 0.0), mat_glass)
				# Interior door grab bar
				_add_box(leaf, Vector3(0.04, 0.04, door_half_w - 0.24), Vector3(-side * 0.05, -0.18, 0.0), pole_mat)
				door_leaves.append({
					"node": leaf,
					"sec": sec,
					"door_z": door_z,
					"base_x": side * (hw - 0.01),
					"side": side,
					"closed_z": closed_z,
					"dir": leaf_dir,
					"vintage": vintage,
				})

			# Retractable Gap-Filler Step Plate / Folding Boarding Step!
			var step_node := Node3D.new()
			var step_base_x := side * (hw - 0.16)
			step_node.position = Vector3(step_base_x, 0.51 if not vintage else 0.36, door_z)
			sec.add_child(step_node)
			_add_box(step_node, Vector3(0.32, 0.032, door_half_w * 1.85), Vector3.ZERO, mat_steel)
			_add_box(step_node, Vector3(0.05, 0.036, door_half_w * 1.85), Vector3(side * 0.14, 0.0, 0.0), mat_yellow_thresh)
			step_plates.append({
				"node": step_node,
				"sec": sec,
				"door_z": door_z,
				"base_x": step_base_x,
				"side": side,
			})

		# 4. Detailed Cabin Interior: Tempered Windscreen Partitions, Seats, Stanchions, Handrails & Straps!
		# Overhead twin longitudinal handrails + hanging passenger straps
		for rail_side: float in [-0.44, 0.44]:
			_add_cyl(sec, 0.018, sec_len - 1.8, Vector3(rail_side, 2.38, 0.0), pole_mat, Vector3(90.0, 0.0, 0.0))
			var strap_z := z_body_front + 0.65
			while strap_z < z_body_rear - 0.55:
				_add_box(sec, Vector3(0.012, 0.17, 0.03), Vector3(rail_side, 2.28, strap_z), mat_dark)
				var ring := MeshInstance3D.new()
				ring.mesh = _get_strap_ring_mesh()
				ring.material_override = mat_yellow_thresh if not vintage else mat_brass
				ring.position = Vector3(rail_side, 2.15, strap_z)
				ring.rotation_degrees = Vector3(0.0, 0.0, 90.0)
				ring.visibility_range_end = 150.0
				ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				sec.add_child(ring)
				strap_z += 0.92

		# Doorway glass windscreen partitions + vertical grab poles + yellow STOP request buttons
		for d_edge_off: float in [door_z - door_half_w - 0.08, door_z + door_half_w + 0.08]:
			for side: float in [-1.0, 1.0]:
				var px := side * (hw - 0.36)
				_add_box(sec, Vector3(0.52, 1.08, 0.03), Vector3(px, 1.38, d_edge_off), mat_part_glass)
				_add_box(sec, Vector3(0.54, 0.04, 0.045), Vector3(px, 1.93, d_edge_off), pole_mat)
				var pole_x := side * (hw - 0.62)
				_add_cyl(sec, 0.022, 2.32, Vector3(pole_x, 1.72, d_edge_off), pole_mat, Vector3.ZERO)
				# Yellow housing + illuminated red STOP button at chest height!
				_add_box(sec, Vector3(0.056, 0.11, 0.046), Vector3(pole_x - side * 0.026, 1.46, d_edge_off), mat_yellow_thresh)
				_add_box(sec, Vector3(0.030, 0.042, 0.052), Vector3(pole_x - side * 0.042, 1.46, d_edge_off), mat_stop_btn)

		# Contoured Seats (Moquette Fabric + Back Shell + Aisle Grab Handle) + Onboard Passengers!
		for sp: Vector2 in wall_spans:
			var sz := sp.x + 0.58
			var row_idx := 0
			while sz < sp.y - 0.52:
				for side: float in [-1.0, 1.0]:
					var sx := side * (hw - 0.36)
					if vintage:
						# Classic varnished wooden slat bench with brass aisle grab handle
						_add_box(sec, Vector3(0.48, 0.06, 0.56), Vector3(sx, 0.92, sz), mat_wood_trim)
						_add_box(sec, Vector3(0.46, 0.44, 0.06), Vector3(sx, 1.16, sz + 0.24), mat_wood_trim)
						_add_box(sec, Vector3(0.05, 0.36, 0.42), Vector3(sx, 0.74, sz), mat_dark)
						_add_cyl(sec, 0.015, 0.18, Vector3(sx - side * 0.22, 1.42, sz + 0.24), mat_brass, Vector3.ZERO)
					else:
						# Modern sculpted transit bucket seat: composite shell + moquette pad + aisle grab handle + armrest
						# Moulded composite shell + inset moquette cushion (lofted contour, not boxes)
						var shell := MeshInstance3D.new()
						shell.mesh = _get_seat_mesh(false)
						shell.material_override = mat_dark
						shell.position = Vector3(sx, 0.93, sz)
						shell.visibility_range_end = 160.0
						shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						sec.add_child(shell)
						var cushion := MeshInstance3D.new()
						cushion.mesh = _get_seat_mesh(true)
						cushion.material_override = mat_seat
						cushion.position = Vector3(sx, 0.93, sz)
						cushion.visibility_range_end = 160.0
						cushion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						sec.add_child(cushion)
						# Aisle-side top grab-loop handle + low side armrest
						_add_box(sec, Vector3(0.032, 0.14, 0.032), Vector3(sx - side * 0.21, 1.54, sz + 0.25), mat_yellow_thresh)
						_add_box(sec, Vector3(0.14, 0.030, 0.032), Vector3(sx - side * 0.15, 1.60, sz + 0.25), mat_yellow_thresh)
						_add_box(sec, Vector3(0.035, 0.04, 0.32), Vector3(sx - side * 0.22, 1.12, sz + 0.02), mat_dark)
						_add_box(sec, Vector3(0.38, 0.055, 0.075), Vector3(sx, 0.85, sz), mat_steel)

					# Build an articulated seated 3D passenger figure on ~75% of seats (toggled & animated dynamically!)
					if (row_idx + idx) % 3 != 2:
						var pax_rig := _build_seated_passenger(onboard_pax_rigs.size(), sx, sz, side)
						var pax_node: Node3D = pax_rig["root"]
						pax_node.visible = false
						sec.add_child(pax_node)
						onboard_pax_nodes.append(pax_node)
						onboard_pax_rigs.append(pax_rig)
				sz += 0.92
				row_idx += 1

		# Add standing aisle passengers aligned directly beneath actual overhead hanging straps so hands grip the straps!
		for strap_k: int in [1, 3, 5]:
			var st_z := z_body_front + 0.65 + float(strap_k) * 0.92
			if st_z > z_body_front + 0.55 and st_z < z_body_rear - 0.85:
				var st_x := 0.26 if (onboard_pax_rigs.size() % 2 == 0) else -0.26
				var spax_rig := _build_standing_cabin_passenger(onboard_pax_rigs.size(), st_x, st_z)
				var spax_node: Node3D = spax_rig["root"]
				spax_node.visible = false
				sec.add_child(spax_node)
				# Insert standing riders interleaved so early boarders include standing strap-holders too!
				var insert_at := mini(onboard_pax_rigs.size(), maxi(2, idx * 3 + 2))
				onboard_pax_nodes.insert(insert_at, spax_node)
				onboard_pax_rigs.insert(insert_at, spax_rig)

		# Interior passenger camera anchor centered in the clear walkthrough aisle!
		if interior_anchor == null and (idx == 0 or idx == sections_count / 2):
			interior_anchor = Node3D.new()
			interior_anchor.name = "InteriorPassengerCamAnchor"
			interior_anchor.position = Vector3(0.0, 1.84, z_body_rear - 0.48)
			sec.add_child(interior_anchor)

		# 5. Detailed Bogies, Coil Springs, Magnetic Track Brakes & Wheels
		var bogie_offsets: Array[float] = []
		if sections_count == 1:
			bogie_offsets.append(-hl * 0.54)
			bogie_offsets.append(hl * 0.54)
		elif is_front:
			bogie_offsets.append(-hl * 0.32)
		elif is_rear:
			bogie_offsets.append(hl * 0.32)
		else:
			bogie_offsets.append(0.0)
		if monorail:
			# Straddle-beam monorail: body skirts wrap both flanks of the 0.9m guideway beam (running and
			# guide wheels are hidden inside), with an accent band along the skirt bottom
			for sk: float in [-1.0, 1.0]:
				_add_box(sec, Vector3(hw - 0.50, 1.45, sec_len - 0.30), Vector3(sk * (0.50 + (hw - 0.50) * 0.5), -0.30, 0.0), mat_body)
				_add_box(sec, Vector3(hw - 0.48, 0.22, sec_len - 0.28), Vector3(sk * (0.50 + (hw - 0.50) * 0.5), -0.92, 0.0), mat_accent)
			_add_box(sec, Vector3(1.0, 0.25, sec_len - 0.3), Vector3(0.0, 0.42, 0.0), mat_dark)
		else:
			for bz: float in bogie_offsets:
				_build_detailed_bogie(sec, bz, mat_dark, mat_steel, mat_accent)

		# 6. Rooftop Shrouds / HVAC / Supercap Pods / Vintage Clerestory Lantern Roof
		if is_jx:
			# Smooth full-length roof fairing (supercapacitors are under it), white skirts over the bogies and
			# the round red line logo near the first door
			_build_jx_fairing(sec, width, zf_cut, zr_cut, mat_body)
			for sk_side: float in [-1.0, 1.0]:
				_add_box(sec, Vector3(0.06, 0.30, span_l - 0.1), Vector3(sk_side * (hw - 0.05), 0.33, span_c), mat_body)
			if is_front or is_rear:
				for lg_side: float in [-1.0, 1.0]:
					var lz := (door_z - door_half_w - 0.45) if is_front else (door_z + door_half_w + 0.45)
					var lg := _add_cyl(sec, 0.17, 0.02, Vector3(lg_side * (hw + 0.012), 2.38, lz), mat_accent, Vector3(0.0, 0.0, 90.0))
					lg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_add_cyl(sec, 0.12, 0.024, Vector3(lg_side * (hw + 0.014), 2.38, lz), mat_body, Vector3(0.0, 0.0, 90.0))
					_add_cyl(sec, 0.075, 0.028, Vector3(lg_side * (hw + 0.016), 2.38, lz), mat_accent, Vector3(0.0, 0.0, 90.0))
		else:
			_build_roof_equipment(sec, width, sec_len, roof_kind, vintage, mat_roof, mat_body, mat_dark, mat_cove_light, mat_accent)

		var panto_sec_idx := (sections_count / 2) if sections_count >= 3 else 0
		if idx == panto_sec_idx and not monorail:
			_build_pantograph(sec, panto_kind, mat_dark, mat_steel, mat_brass)

		# 7. Sculpted Front Cab Cockpit & Nose
		if is_front:
			var cab_parts := _build_front_cab_and_nose(
				sec, width, hl, nose_kind, vintage, single_lamp,
				mat_body, mat_accent, mat_dark, mat_steel, mat_brass,
				mat_cab_glass, mat_part_glass, mat_seat, mat_headlight, mat_led_sign
			)
			head_spot = cab_parts["head_spot"]
			cab_anchor = cab_parts["cab_anchor"]
			throttle_lever = cab_parts["throttle_lever"]
			cab_controls = cab_parts["cab_controls"]
		else:
			# Open walkthrough gangway portal cheeks on left & right (clear central aisle!)
			for p_side: float in [-1.0, 1.0]:
				_add_box(sec, Vector3(0.56, 2.38, 0.16), Vector3(p_side * (hw - 0.32), 1.74, -hl + 0.10), mat_dark)
			_add_box(sec, Vector3(width - 0.08, 0.32, 0.16), Vector3(0.0, 2.78, -hl + 0.10), mat_dark)

		# 8. Double-Ended Bidirectional Rear Driver Cab (rotated 180 deg around Y) or open gangway portal!
		if is_rear:
			var rear_cab_holder := Node3D.new()
			rear_cab_holder.name = "RearCabHolder"
			rear_cab_holder.rotation.y = PI
			sec.add_child(rear_cab_holder)
			var rcab_parts := _build_front_cab_and_nose(
				rear_cab_holder, width, hl, nose_kind, vintage, single_lamp,
				mat_body, mat_accent, mat_dark, mat_steel, mat_brass,
				mat_cab_glass, mat_part_glass, mat_seat, mat_taillight, mat_led_sign
			)
			rear_head_spot = rcab_parts["head_spot"]
			if is_instance_valid(rear_head_spot):
				rear_head_spot.visible = false
			rear_cab_anchor = rcab_parts["cab_anchor"]
			rear_throttle_lever = rcab_parts["throttle_lever"]
			rear_cab_controls = rcab_parts["cab_controls"]
		else:
			for p_side: float in [-1.0, 1.0]:
				_add_box(sec, Vector3(0.56, 2.38, 0.16), Vector3(p_side * (hw - 0.32), 1.74, hl - 0.10), mat_dark)
			_add_box(sec, Vector3(width - 0.08, 0.32, 0.16), Vector3(0.0, 2.78, hl - 0.10), mat_dark)

		var ilight := OmniLight3D.new()
		ilight.light_color = Color(1.0, 0.92, 0.78)
		ilight.light_energy = 0.25
		ilight.omni_range = 8.0
		ilight.distance_fade_enabled = true
		ilight.distance_fade_begin = 75.0
		ilight.distance_fade_length = 25.0
		ilight.position = Vector3(0.0, 2.65, 0.0)
		sec.add_child(ilight)
		interior_lights.append(ilight)

	# Hollow Ribbed Articulated Accordion Gangway Bellows between sections (open central walkthrough!)
	for g_idx in range(sections_count - 1):
		var gw := Node3D.new()
		gw.name = "Gangway_%d" % g_idx
		root.add_child(gw)
		for rib_z: float in [-0.32, 0.0, 0.32]:
			for g_side: float in [-1.0, 1.0]:
				_add_box(gw, Vector3(0.32, 2.40, 0.24), Vector3(g_side * (width * 0.5 - 0.24), 1.74, rib_z), mat_dark)
			_add_box(gw, Vector3(width - 0.18, 0.24, 0.24), Vector3(0.0, 2.82, rib_z), mat_dark)
		_add_box(gw, Vector3(width - 0.36, 0.06, 0.98), Vector3(0.0, 0.56, 0.0), mat_floor)
		gangway_nodes.append(gw)

	var tinfo := {
		"root": root,
		"sections": section_nodes,
		"gangways": gangway_nodes,
		"doors": door_leaves,
		"step_plates": step_plates,
		"door_led_mat": mat_door_led,
		"door_anchors": door_world_anchors,
		"door_portals": door_portals,
		"onboard_pax": onboard_pax_nodes,
		"onboard_rigs": onboard_pax_rigs,
		"interior_lights": interior_lights,
		"head_spot": head_spot,
		"front_head_spot": head_spot,
		"rear_head_spot": rear_head_spot,
		"front_lamp_mat": mat_headlight,
		"rear_lamp_mat": mat_taillight,
		"cab_anchor": cab_anchor,
		"front_cab_anchor": cab_anchor,
		"rear_cab_anchor": rear_cab_anchor,
		"interior_anchor": interior_anchor,
		"throttle_lever": throttle_lever,
		"front_throttle_lever": throttle_lever,
		"rear_throttle_lever": rear_throttle_lever,
		"cab_controls": cab_controls,
		"front_cab_controls": cab_controls,
		"rear_cab_controls": rear_cab_controls,
		"active_end": 0,
		"section_len": sec_len,
		"sections_count": sections_count,
		"width": width,
		"pax_culled": false,
	}
	_merge_static_tram_meshes(tinfo)
	return tinfo


# Merge hundreds of static interior/exterior leaf MeshInstance3D parts per tram section & gangway
# by (material, cast_shadow, lod_tier) while strictly keeping every animated door, cab control, and passenger rig untouched!
static func _merge_static_tram_meshes(tinfo: Dictionary) -> void:
	var keep := {}
	for d: Dictionary in tinfo.get("doors", []):
		if d.get("node") is Object:
			keep[(d["node"] as Object).get_instance_id()] = true
	for sp: Dictionary in tinfo.get("step_plates", []):
		if sp.get("node") is Object:
			keep[(sp["node"] as Object).get_instance_id()] = true
	for pn in tinfo.get("onboard_pax", []):
		if pn is Object:
			keep[(pn as Object).get_instance_id()] = true
	for k_s: String in ["throttle_lever", "rear_throttle_lever"]:
		var n_s = tinfo.get(k_s)
		if n_s is Object:
			keep[(n_s as Object).get_instance_id()] = true
	for cc_k: String in ["front_cab_controls", "rear_cab_controls"]:
		var cc: Dictionary = tinfo.get(cc_k, {})
		for v in cc.values():
			if v is Object:
				keep[(v as Object).get_instance_id()] = true
			elif v is Array:
				for elem in v:
					if elem is Object:
						keep[(elem as Object).get_instance_id()] = true

	var containers: Array = []
	for sec in tinfo.get("sections", []):
		containers.append(sec)
	for gw in tinfo.get("gangways", []):
		containers.append(gw)

	for cont: Node3D in containers:
		if not is_instance_valid(cont):
			continue
		var groups := {}
		var to_remove: Array[MeshInstance3D] = []
		for ch in cont.get_children():
			if not (ch is MeshInstance3D):
				continue
			var mi := ch as MeshInstance3D
			if mi.mesh == null or mi.get_child_count() > 0 or keep.has(mi.get_instance_id()):
				continue
			var mat: Material = mi.material_override
			if mat == null and mi.mesh.get_surface_count() > 0:
				mat = mi.mesh.surface_get_material(0)
			var cast_sh := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var vis_e := mi.visibility_range_end
			var tier := 2 if (vis_e <= 0.0 or vis_e >= 500.0) else (1 if vis_e >= 250.0 else 0)
			var mat_id := mat.get_instance_id() if mat != null else 0
			var gk := "%d_%d_%d" % [mat_id, 1 if cast_sh else 0, tier]
			if not groups.has(gk):
				groups[gk] = {"mat": mat, "cast_sh": cast_sh, "vis": vis_e, "items": []}
			var g: Dictionary = groups[gk]
			(g["items"] as Array).append(mi)
			if vis_e <= 0.0 or (float(g["vis"]) > 0.0 and vis_e > float(g["vis"])):
				g["vis"] = vis_e
			to_remove.append(mi)

		var b_i := 0
		for gk: String in groups.keys():
			var g: Dictionary = groups[gk]
			var items: Array = g["items"]
			if items.size() <= 1:
				continue # single mesh already optimal
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var appended := 0
			for mi: MeshInstance3D in items:
				if mi.mesh.get_surface_count() <= 0:
					continue
				append_mesh_flat(st, mi.mesh, mi.transform)
				appended += 1
			if appended == 0:
				continue
			var merged := MeshInstance3D.new()
			merged.name = "SecBatch_%d" % b_i
			b_i += 1
			merged.mesh = st.commit()
			if g["mat"] != null:
				merged.material_override = g["mat"]
			merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(g["cast_sh"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if float(g["vis"]) > 0.0:
				merged.visibility_range_end = float(g["vis"])
			cont.add_child(merged)
			for old_mi: MeshInstance3D in items:
				cont.remove_child(old_mi)
				old_mi.queue_free()


# SurfaceTool.append_from keeps the index list of whatever was appended first: mixing indexed parts
# (BoxMesh / CylinderMesh) with non-indexed sculpted parts (seats ...) silently drops the triangles of the
# latter. Always append de-indexed geometry (cached per source mesh).
static var _flat_cache := {}

static func append_mesh_flat(st: SurfaceTool, mesh: Mesh, xf: Transform3D) -> void:
	if mesh == null or mesh.get_surface_count() <= 0:
		return
	var key := mesh.get_instance_id()
	var src: Mesh = _flat_cache.get(key)
	if src == null:
		src = mesh
		if mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] != null:
			var tmp := SurfaceTool.new()
			tmp.create_from(mesh, 0)
			tmp.deindex()
			src = tmp.commit()
		_flat_cache[key] = src
	st.append_from(src, 0, xf)


# Hide/restore onboard passenger rig trees on distant trams so 30+ trams never clutter RenderingServer!
static func set_onboard_passengers_culled(tinfo: Dictionary, culled: bool, pax_count: int, capacity: int) -> void:
	if bool(tinfo.get("pax_culled", false)) == culled:
		return
	tinfo["pax_culled"] = culled
	if culled:
		for rig: Dictionary in tinfo.get("onboard_rigs", []):
			var n: Node3D = rig.get("root")
			if is_instance_valid(n):
				n.visible = false
	else:
		update_onboard_passengers(tinfo, pax_count, capacity)


static func set_active_cab_end(tinfo: Dictionary, end_idx: int) -> void:
	var target := 1 if end_idx == 1 else 0
	if int(tinfo.get("active_end", -1)) == target:
		return
	tinfo["active_end"] = target
	var f_spot: SpotLight3D = tinfo.get("front_head_spot")
	var r_spot: SpotLight3D = tinfo.get("rear_head_spot")
	var f_mat: StandardMaterial3D = tinfo.get("front_lamp_mat")
	var r_mat: StandardMaterial3D = tinfo.get("rear_lamp_mat")
	if target == 0:
		tinfo["cab_anchor"] = tinfo.get("front_cab_anchor")
		tinfo["throttle_lever"] = tinfo.get("front_throttle_lever")
		tinfo["cab_controls"] = tinfo.get("front_cab_controls", {})
		tinfo["head_spot"] = f_spot
		if is_instance_valid(f_spot): f_spot.visible = true
		if is_instance_valid(r_spot): r_spot.visible = false
		if f_mat != null:
			f_mat.albedo_color = Color(1.0, 0.98, 0.90)
			f_mat.emission = Color(1.0, 0.96, 0.84)
			f_mat.emission_energy_multiplier = 2.8
		if r_mat != null:
			r_mat.albedo_color = Color(0.95, 0.12, 0.12)
			r_mat.emission = Color(1.0, 0.12, 0.10)
			r_mat.emission_energy_multiplier = 2.2
	else:
		tinfo["cab_anchor"] = tinfo.get("rear_cab_anchor", tinfo.get("front_cab_anchor"))
		tinfo["throttle_lever"] = tinfo.get("rear_throttle_lever", tinfo.get("front_throttle_lever"))
		tinfo["cab_controls"] = tinfo.get("rear_cab_controls", tinfo.get("front_cab_controls", {}))
		tinfo["head_spot"] = r_spot
		if is_instance_valid(f_spot): f_spot.visible = false
		if is_instance_valid(r_spot): r_spot.visible = true
		if r_mat != null:
			r_mat.albedo_color = Color(1.0, 0.98, 0.90)
			r_mat.emission = Color(1.0, 0.96, 0.84)
			r_mat.emission_energy_multiplier = 2.8
		if f_mat != null:
			f_mat.albedo_color = Color(0.95, 0.12, 0.12)
			f_mat.emission = Color(1.0, 0.12, 0.10)
			f_mat.emission_energy_multiplier = 2.2


static func _is_door_allowed_by_platform(sec: Node3D, side: float, door_z: float, dock_info: Dictionary) -> bool:
	if not bool(dock_info.get("has_station", false)) or not is_instance_valid(sec):
		return false
	var st_fwd := (dock_info.get("st_fwd", Vector3.FORWARD) as Vector3).normalized()
	var st_pos: Vector3 = dock_info.get("st_pos", Vector3.ZERO)
	var st_side := float(dock_info.get("st_side", 1.0))
	var half_len := float(dock_info.get("plat_half_len", 13.05))
	var door_world := sec.global_transform * Vector3(0.0, 0.0, door_z)
	var curve_spec: Dictionary = dock_info.get("curve_spec", {})
	var st_right := st_fwd.cross(Vector3.UP).normalized()
	var along := (door_world - st_pos).dot(st_fwd)
	var ref_center := st_pos
	if not curve_spec.is_empty() and curve_spec.has("geom"):
		var g_c: Dictionary = curve_spec["geom"]
		var c_c: Curve3D = g_c["curve"]
		var clen_c := float(g_c["clen"])
		var s_cen := float(curve_spec["s_center"])
		var s_door := c_c.get_closest_offset(Vector3(door_world.x, 0.0, door_world.z))
		along = s_door - s_cen
		var tf_d := TrackBuilder.sample_track_frame(c_c, s_door, clen_c, false)
		st_fwd = (-tf_d.basis.z).normalized()
		st_right = st_fwd.cross(Vector3.UP).normalized()
		if int(st_side) == 0:
			var c_mode := str(curve_spec.get("mode", "double_island"))
			if c_mode == "quad_twin":
				var lat_sgn := signf((sec.global_position - tf_d.origin).dot(st_right))
				if lat_sgn == 0.0:
					lat_sgn = 1.0
				var isl_lat := 0.5 * (TrackBuilder.geom_sep_at(g_c, s_door) + TrackBuilder.geom_lsep_at(g_c, s_door))
				ref_center = tf_d.origin + st_right * (lat_sgn * isl_lat)
			else:
				ref_center = tf_d.origin
	var plat_dir := Vector3.ZERO
	if int(st_side) == 0:
		# Central Island Platform: platform is at ref_center between both tracks; project laterally so longitudinal offset never shrinks the dot!
		var lat_to_island := (ref_center - sec.global_position).dot(st_right)
		if absf(lat_to_island) < 0.05:
			return false
		plat_dir = st_right * signf(lat_to_island)
	else:
		plat_dir = st_right * st_side
	var tram_right := sec.global_transform.basis.x.normalized()
	if side * tram_right.dot(plat_dir) <= 0.35:
		return false
	return absf(along) <= half_len


static func update_doors(tram_info: Dictionary, open_ratio: float, dock_info: Dictionary = {}) -> Dictionary:
	var base_r := clampf(open_ratio, 0.0, 1.0)
	var doors: Array = tram_info.get("doors", [])
	var has_st := bool(dock_info.get("has_station", false))
	var open_leaves := 0
	var total_doors_one_side := maxi(1, doors.size() / 4)

	for d in doors:
		var node: Node3D = d["node"]
		var side: float = float(d["side"])
		var base_x: float = float(d["base_x"])
		var closed_z: float = float(d["closed_z"])
		var dir: float = float(d["dir"])
		var is_vint: bool = bool(d.get("vintage", false))
		var allowed := false
		if base_r > 0.001 and has_st:
			allowed = _is_door_allowed_by_platform(d.get("sec") as Node3D, side, float(d.get("door_z", 0.0)), dock_info)
		var r := base_r if allowed else 0.0
		if r > 0.05:
			open_leaves += 1

		if is_vint:
			# Vintage bi-fold door swings inward/slides compactly + rotates 78 deg!
			node.position.x = base_x - r * 0.06 * side
			node.position.z = closed_z + r * 0.44 * dir
			node.rotation.y = side * dir * deg_to_rad(r * 72.0)
		else:
			# Modern plug-sliding door: swing out 9.5cm on arm, then glide smoothly apart 64cm
			var out_shift := minf(r * 3.2, 1.0) * 0.095 * side
			var z_shift := maxf(0.0, (r - 0.14) / 0.86) * 0.64 * dir
			node.position.x = base_x + out_shift
			node.position.z = closed_z + z_shift

	# Extend gap-filler boarding step plates ONLY for aligned platform-side doors!
	var steps: Array = tram_info.get("step_plates", [])
	for sp in steps:
		var snode: Node3D = sp["node"]
		var s_base_x: float = float(sp["base_x"])
		var s_side: float = float(sp["side"])
		var allowed_s := false
		if base_r > 0.001 and has_st:
			allowed_s = _is_door_allowed_by_platform(sp.get("sec") as Node3D, s_side, float(sp.get("door_z", 0.0)), dock_info)
		var rs := base_r if allowed_s else 0.0
		var ext := clampf(rs * 1.8, 0.0, 1.0) * 0.22 * s_side
		snode.position.x = s_base_x + ext

	var led_mat: StandardMaterial3D = tram_info.get("door_led_mat")
	if led_mat != null:
		led_mat.emission_energy_multiplier = 2.4 if open_leaves > 0 else 0.0

	return {
		"open_doorways": open_leaves / 2,
		"total_doorways": total_doors_one_side,
	}


static func update_onboard_passengers(tram_info: Dictionary, pax_count: int, capacity: int) -> void:
	if bool(tram_info.get("pax_culled", false)):
		return
	var rigs: Array = tram_info.get("onboard_rigs", [])
	if rigs.is_empty():
		return
	var max_rigs := rigs.size()
	var show_n := 0
	if pax_count <= 0:
		show_n = 0
	elif pax_count <= 10:
		# 1-to-1 visible 3D figure for each of the first 10 boarding passengers!
		show_n = mini(pax_count, max_rigs)
	else:
		var rest_ratio := clampf(float(pax_count - 10) / float(maxi(1, int(capacity * 0.60) - 10)), 0.0, 1.0)
		show_n = mini(max_rigs, 10 + int(ceil(rest_ratio * float(maxi(0, max_rigs - 10)))))

	for i in range(max_rigs):
		var rig: Dictionary = rigs[i]
		var n: Node3D = rig.get("root")
		if is_instance_valid(n):
			var should_show := (i < show_n)
			if should_show and not n.visible:
				rig["pop_t"] = 0.0
				n.scale = Vector3(0.45, 0.45, 0.45)
			n.visible = should_show


static func animate_onboard_passengers(
	tram_info: Dictionary,
	time_sec: float,
	speed_mps: float,
	accel_mps2: float,
	dt: float
) -> void:
	var rigs: Array = tram_info.get("onboard_rigs", [])
	if rigs.is_empty():
		return
	var move_amp := clampf(speed_mps / 9.5, 0.0, 1.0)
	var inertia_pitch := clampf(-accel_mps2 * 0.075, -0.16, 0.16)

	for rig: Dictionary in rigs:
		var root_n: Node3D = rig.get("root")
		if not is_instance_valid(root_n) or not root_n.visible:
			continue

		var pop_t := float(rig.get("pop_t", 1.0))
		if pop_t < 1.0:
			pop_t = minf(1.0, pop_t + dt * 4.5)
			rig["pop_t"] = pop_t
			var s_ease := 1.0 - pow(1.0 - pop_t, 3.0)
			var sc := lerpf(0.45, 1.0, s_ease)
			root_n.scale = Vector3(sc, sc, sc)

		var torso: Node3D = rig.get("torso")
		var head: Node3D = rig.get("head")
		var arm_l: Node3D = rig.get("arm_l")
		var arm_r: Node3D = rig.get("arm_r")
		var seed := float(rig.get("seed", 0.0))
		var side := float(rig.get("side", 1.0))
		var is_standing := bool(rig.get("is_standing", false))

		if is_standing:
			if is_instance_valid(torso):
				torso.rotation.x = inertia_pitch * 1.15 + sin(time_sec * 2.5 + seed) * 0.036 * (0.25 + move_amp)
				torso.rotation.z = sin(time_sec * 3.1 + seed * 1.4) * 0.045 * (0.20 + move_amp)
			if is_instance_valid(head):
				head.rotation.y = sin(time_sec * 0.78 + seed) * 0.42
				head.rotation.x = sin(time_sec * 1.15 + seed * 0.7) * 0.08
			if is_instance_valid(arm_l):
				arm_l.rotation.x = deg_to_rad(-16.0) + sin(time_sec * 2.2 + seed) * 0.09 * (0.3 + move_amp)
		else:
			if is_instance_valid(torso):
				torso.rotation.x = inertia_pitch * 0.55 + sin(time_sec * 1.7 + seed) * 0.025
				torso.rotation.z = sin(time_sec * 2.8 + seed) * 0.022 * move_amp
			if is_instance_valid(head):
				# Look out the panoramic window at passing buildings or glance around cabin!
				var win_yaw := -side * 0.52 * (0.45 + 0.55 * sin(time_sec * 0.52 + seed))
				head.rotation.y = win_yaw + sin(time_sec * 0.95 + seed * 1.9) * 0.16
				head.rotation.x = (0.14 if bool(rig.get("has_phone", false)) else 0.0) + sin(time_sec * 0.85 + seed) * 0.07
			if is_instance_valid(arm_r) and bool(rig.get("has_phone", false)):
				arm_r.rotation.x = deg_to_rad(-44.0) + sin(time_sec * 2.1 + seed) * 0.05


static func _build_front_cab_and_nose(
	sec: Node3D,
	width: float,
	hl: float,
	nose_kind: String,
	vintage: bool,
	single_lamp: bool,
	mat_body: Material,
	mat_accent: Material,
	mat_dark: Material,
	mat_steel: Material,
	mat_brass: Material,
	mat_cab_glass: Material,
	mat_part_glass: Material,
	mat_seat: Material,
	mat_headlight: Material,
	mat_led_sign: Material
) -> Dictionary:
	var hw := width * 0.5
	var fz := -hl
	var is_nanhu := (nose_kind == "nanhu_swift")
	var slope_deg := 21.0 if is_nanhu else (18.0 if nose_kind == "sleek" else (12.0 if nose_kind in ["streamlined", "faceted"] else 5.0))

	if is_nanhu:
		_build_jx_nose(sec, width, fz, mat_body, mat_accent, mat_headlight, mat_led_sign)
	else:
		# Sculpted bumper, coupler pocket & lower nose apron
		_add_box(sec, Vector3(width - 0.10, 0.32, 0.64), Vector3(0.0, 0.48, fz + 0.14), mat_dark)
		var nose_apron := _add_box(sec, Vector3(width - 0.04, 0.76, 0.58), Vector3(0.0, 0.94, fz + 0.24), mat_body)
		nose_apron.rotation.x = deg_to_rad(slope_deg * 0.45)
		_add_box(sec, Vector3(width + 0.015, 0.20, 0.60), Vector3(0.0, 0.96, fz + 0.22), mat_accent)
	if false:
		# Iconic Jiaxing "南湖号" CRRC Changchun aerodynamic "南湖雨燕 / 红船" prow:
		var prow := _add_box(sec, Vector3(width - 0.16, 0.68, 0.42), Vector3(0.0, 0.88, fz - 0.06), mat_body)
		prow.rotation.x = deg_to_rad(14.0)
		var red_wave := _add_box(sec, Vector3(width - 0.08, 0.14, 0.46), Vector3(0.0, 1.18, fz - 0.04), mat_accent)
		red_wave.rotation.x = deg_to_rad(16.0)
		var brow := _add_box(sec, Vector3(width - 0.12, 0.34, 0.56), Vector3(0.0, 2.86, fz + 0.36), mat_body)
		brow.rotation.x = deg_to_rad(10.0)
		_add_box(sec, Vector3(width - 0.06, 0.11, 0.62), Vector3(0.0, 3.04, fz + 0.44), mat_accent)
		for side_n: float in [-1.0, 1.0]:
			var drl := _add_box(sec, Vector3(0.46, 0.075, 0.14), Vector3(side_n * (hw - 0.36), 1.04, fz - 0.24), mat_headlight)
			drl.rotation.z = deg_to_rad(-side_n * 14.0)
			_add_box(sec, Vector3(0.05, 1.48, 0.22), Vector3(side_n * (hw - 0.03), 1.98, fz + 0.42), mat_dark)

	# Vintage iron cowcatcher / lifeguard grille under front bumper!
	if vintage:
		var catcher := _add_box(sec, Vector3(width * 0.78, 0.06, 0.42), Vector3(0.0, 0.26, fz - 0.02), mat_dark)
		catcher.rotation.x = deg_to_rad(18.0)
		for slat_x in range(-3, 4):
			_add_box(sec, Vector3(0.035, 0.22, 0.36), Vector3(float(slat_x) * 0.26, 0.30, fz - 0.02), mat_dark)

	# Left & right A-pillars + side cab cheek windows + rearview mirrors
	for side: float in [-1.0, 1.0]:
		if is_nanhu:
			# Compact white camera-mirror pod on a short arm at the cab corner
			_add_box(sec, Vector3(0.16, 0.035, 0.035), Vector3(side * (hw + 0.07), 2.52, fz + 0.86), mat_dark)
			_add_box(sec, Vector3(0.10, 0.20, 0.14), Vector3(side * (hw + 0.15), 2.46, fz + 0.86), mat_body)
			continue
		var pil := _add_box(sec, Vector3(0.13, 1.66, 0.20), Vector3(side * (hw - 0.08), 2.04, fz + 0.34), mat_dark)
		pil.rotation.x = deg_to_rad(slope_deg)
		_add_box(sec, Vector3(0.04, 1.38, 1.02), Vector3(side * (hw - 0.04), 1.97, fz + 0.92), mat_cab_glass)
		_add_box(sec, Vector3(0.08, 0.74, 1.04), Vector3(side * (hw - 0.04), 0.92, fz + 0.92), mat_body)
		# Exterior mirror arm & housing
		_add_box(sec, Vector3(0.18, 0.04, 0.04), Vector3(side * (hw + 0.08), 2.34, fz + 0.44), mat_dark)
		_add_box(sec, Vector3(0.14, 0.34, 0.08), Vector3(side * (hw + 0.16), 2.22, fz + 0.44), mat_dark)

	if not is_nanhu:
		# Sloped panoramic front windshield + sun visor + wiper
		var ws := _add_box(sec, Vector3(width - 0.24, 1.52, 0.035), Vector3(0.0, 2.02, fz + 0.32), mat_cab_glass)
		ws.rotation.x = deg_to_rad(slope_deg)
		_add_box(sec, Vector3(width - 0.36, 0.14, 0.05), Vector3(0.0, 2.62, fz + 0.42), mat_dark)
		var wiper := _add_box(sec, Vector3(0.56, 0.024, 0.024), Vector3(0.16, 1.38, fz + 0.21), mat_dark)
		wiper.rotation.z = deg_to_rad(13.0)
		# Front destination matrix board
		_add_box(sec, Vector3(width * 0.64, 0.24, 0.08), Vector3(0.0, 2.82, fz + 0.16), mat_led_sign)

	# Detailed Cab Interior: Partition Bulkhead with Doorway, Wrap-Around Sculpted Console, High-Res MFD/CCTV/Switches & Props!
	var part_z := fz + 1.58
	for side: float in [-1.0, 1.0]:
		_add_box(sec, Vector3(0.62, 2.28, 0.06), Vector3(side * (hw - 0.35), 1.72, part_z), mat_dark)
		_add_box(sec, Vector3(0.48, 1.05, 0.07), Vector3(side * (hw - 0.35), 2.02, part_z), mat_part_glass)
		# Interior A-pillar stainless grab handles
		_add_cyl(sec, 0.016, 0.62, Vector3(side * (hw - 0.16), 1.98, fz + 0.56), mat_steel, Vector3(slope_deg, 0.0, 0.0))

	# Overhead pull-down translucent tinted sun visor + interior cab dome light
	var mat_visor := _make_mat(Color(0.05, 0.08, 0.10, 0.72), 0.18, 0.0)
	mat_visor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_box(sec, Vector3(0.96, 0.035, 0.055), Vector3(0.0, 2.62, fz + 0.44), mat_dark)
	_add_box(sec, Vector3(0.90, 0.18, 0.012), Vector3(0.0, 2.52, fz + 0.45), mat_visor)
	# Dual articulated windshield wiper blades on front glass (animated when WIPER switch is ON!)
	var wiper_l_piv := Node3D.new()
	wiper_l_piv.position = Vector3(-0.32, 1.30, (fz - 0.50) if is_nanhu else (fz + 0.21))
	sec.add_child(wiper_l_piv)
	var wiper2 := _add_box(wiper_l_piv, Vector3(0.56, 0.022, 0.022), Vector3(0.18, 0.08, 0.0), mat_dark)
	wiper2.rotation.z = deg_to_rad(-11.0)
	var wiper_r_piv := Node3D.new()
	wiper_r_piv.position = Vector3(0.18, 1.30, (fz - 0.52) if is_nanhu else (fz + 0.21))
	sec.add_child(wiper_r_piv)
	var wiper1 := _add_box(wiper_r_piv, Vector3(0.56, 0.022, 0.022), Vector3(0.18, 0.08, 0.0), mat_dark)
	wiper1.rotation.z = deg_to_rad(11.0)

	# Crisp UNSHADED OLED-style instrument materials (zero sun washout, deep dark-navy contrast!)
	var mat_mfd := StandardMaterial3D.new()
	mat_mfd.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_mfd.albedo_texture = CabTextureGen.get_modern_mfd_tex()

	var mat_cctv := StandardMaterial3D.new()
	mat_cctv.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_cctv.albedo_texture = CabTextureGen.get_cctv_tex()

	var mat_switch_plate := StandardMaterial3D.new()
	mat_switch_plate.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_switch_plate.albedo_texture = CabTextureGen.get_switch_panel_tex()

	var mat_btn_green := _emit_mat(Color(0.08, 0.42, 0.18), Color(0.16, 0.92, 0.42), 1.05)
	var mat_btn_red := _emit_mat(Color(0.58, 0.10, 0.10), Color(0.96, 0.20, 0.14), 1.15)
	var mat_btn_amber := _emit_mat(Color(0.54, 0.38, 0.06), Color(0.96, 0.74, 0.16), 1.05)
	var mat_btn_blue := _emit_mat(Color(0.08, 0.28, 0.56), Color(0.22, 0.68, 0.98), 1.00)
	var mat_rubber := _make_mat(Color(0.08, 0.09, 0.10), 0.88, 0.02)
	var cab_sh2 := load("res://shaders/tram_cab_pbr.gdshader") as Shader
	var mat_console_top := ShaderMaterial.new()
	mat_console_top.shader = cab_sh2
	mat_console_top.set_shader_parameter("base_color", Color(0.36, 0.20, 0.10) if vintage else Color(0.14, 0.16, 0.19))
	mat_console_top.set_shader_parameter("is_wood", 1.0 if vintage else 0.0)
	mat_console_top.set_shader_parameter("rough_val", 0.52)
	mat_console_top.set_shader_parameter("metal_val", 0.22)

	# Wrap-around 3-segment ergonomic driver desk + padded rubber armrest lip + angled side wings
	_add_box(sec, Vector3(width - 0.18, 0.54, 0.64), Vector3(0.0, 1.01, fz + 0.61), mat_dark)
	_add_box(sec, Vector3(width - 0.14, 0.042, 0.68), Vector3(0.0, 1.30, fz + 0.63), mat_console_top)
	_add_cyl(sec, 0.026, width - 0.42, Vector3(0.0, 1.31, fz + 0.96), mat_rubber, Vector3(0.0, 0.0, 90.0))
	for w_side: float in [-1.0, 1.0]:
		var wing := _add_box(sec, Vector3(0.36, 0.52, 0.50), Vector3(w_side * (hw - 0.24), 1.04, fz + 0.96), mat_dark)
		wing.rotation.y = -w_side * deg_to_rad(16.0)
		var wing_top := _add_box(sec, Vector3(0.35, 0.036, 0.48), Vector3(w_side * (hw - 0.24), 1.31, fz + 0.96), mat_console_top)
		wing_top.rotation.y = -w_side * deg_to_rad(16.0)
		_add_box(sec, Vector3(0.16, 0.022, 0.075), Vector3(w_side * (hw - 0.36), 1.328, fz + 0.40), mat_rubber)

	# Raised Sculpted Instrument Binnacle (y = 1.48 so 100% of MFD & CCTV screens sit cleanly above the desk!)
	_add_box(sec, Vector3(0.92, 0.30, 0.24), Vector3(0.0, 1.47, fz + 0.49), mat_dark)
	var glare_hood := _add_box(sec, Vector3(0.94, 0.026, 0.26), Vector3(0.0, 1.625, fz + 0.55), mat_rubber)
	glare_hood.rotation.x = deg_to_rad(-8.0)
	for g_side: float in [-0.46, 0.46]:
		_add_box(sec, Vector3(0.026, 0.30, 0.25), Vector3(g_side, 1.48, fz + 0.54), mat_dark)

	if vintage:
		var mat_dial_spd := StandardMaterial3D.new()
		mat_dial_spd.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat_dial_spd.albedo_texture = CabTextureGen.get_vintage_dial_tex(false)
		var mat_dial_pres := StandardMaterial3D.new()
		mat_dial_pres.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat_dial_pres.albedo_texture = CabTextureGen.get_vintage_dial_tex(true)
		var dial_specs := [
			[-0.26, 0.092, mat_dial_spd],
			[0.02, 0.080, mat_dial_pres],
			[0.26, 0.074, mat_dial_pres],
		]
		for ds: Array in dial_specs:
			var gx := float(ds[0])
			var gr := float(ds[1])
			_add_cyl(sec, gr + 0.012, 0.036, Vector3(gx, 1.475, fz + 0.618), mat_brass, Vector3(72.0, 0.0, 0.0))
			_add_quad(sec, Vector2(gr * 1.92, gr * 1.92), Vector3(gx, 1.482, fz + 0.638), Vector3(-18.0, 0.0, 0.0), ds[2] as Material)
	else:
		# Modern Dual Glass-Cockpit MFD HMI + Split-Screen Platform CCTV Monitor (fully visible, zero clipping!)
		_add_box(sec, Vector3(0.50, 0.25, 0.022), Vector3(-0.16, 1.485, fz + 0.608), mat_rubber)
		_add_quad(sec, Vector2(0.47, 0.232), Vector3(-0.16, 1.485, fz + 0.624), Vector3(-18.0, 0.0, 0.0), mat_mfd)
		_add_box(sec, Vector3(0.30, 0.21, 0.022), Vector3(0.26, 1.480, fz + 0.608), mat_rubber)
		_add_quad(sec, Vector2(0.275, 0.185), Vector3(0.26, 1.480, fz + 0.624), Vector3(-18.0, 0.0, 0.0), mat_cctv)

	# Sleek, Recessed Digital Speed Readout inside the MFD Speedometer Box (no abrupt oversized text!)
	var mfd_lbl := Label3D.new()
	mfd_lbl.text = "00.0"
	mfd_lbl.font_size = 20
	mfd_lbl.pixel_size = 0.00068
	mfd_lbl.outline_size = 0
	mfd_lbl.modulate = Color(0.62, 0.96, 1.0)
	mfd_lbl.position = Vector3(-0.292, 1.448, fz + 0.638)
	mfd_lbl.rotation.x = deg_to_rad(-18.0)
	mfd_lbl.visibility_range_end = 90.0
	mfd_lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sec.add_child(mfd_lbl)

	# Live In-Cab Tram Traffic Signal Repeater inside the MFD Screen (shows upcoming ┃ GO / ● WAIT / ━ STOP + dist!)
	var sig_lbl := Label3D.new()
	sig_lbl.text = "┃ GO"
	sig_lbl.font_size = 20
	sig_lbl.pixel_size = 0.00072
	sig_lbl.outline_size = 0
	sig_lbl.modulate = Color(0.30, 0.96, 0.62)
	sig_lbl.position = Vector3(-0.045, 1.568, fz + 0.602)
	sig_lbl.rotation.x = deg_to_rad(-18.0)
	sig_lbl.visibility_range_end = 90.0
	sig_lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sec.add_child(sig_lbl)

	# Cab Radio Handset on right wing + Driver Timetable Clipboard on left A-pillar
	_add_box(sec, Vector3(0.06, 0.03, 0.18), Vector3(hw - 0.24, 1.345, fz + 0.92), mat_rubber)
	_add_box(sec, Vector3(0.05, 0.045, 0.16), Vector3(hw - 0.24, 1.375, fz + 0.92), mat_dark)
	_add_box(sec, Vector3(0.11, 0.16, 0.012), Vector3(-(hw - 0.26), 1.62, fz + 0.56), _make_mat(Color(0.92, 0.90, 0.84), 0.78, 0.0))

	# Driver's ergonomic suspension pedestal seat behind console
	_add_cyl(sec, 0.08, 0.42, Vector3(0.0, 0.76, fz + 1.28), mat_steel, Vector3.ZERO)
	_add_box(sec, Vector3(0.50, 0.10, 0.48), Vector3(0.0, 0.98, fz + 1.28), mat_seat)
	_add_box(sec, Vector3(0.48, 0.58, 0.09), Vector3(0.0, 1.30, fz + 1.48), mat_seat)
	_add_box(sec, Vector3(0.28, 0.16, 0.07), Vector3(0.0, 1.65, fz + 1.50), mat_rubber)

	# Left-Hand Slotted Master Controller Quadrant Gate + Corrugated Dust Boot + Interactive Lever!
	var gate_pos := Vector3(-0.58, 1.326, fz + 0.76)
	_add_box(sec, Vector3(0.18, 0.024, 0.36), gate_pos, mat_brass if vintage else mat_steel)
	_add_box(sec, Vector3(0.038, 0.028, 0.30), gate_pos + Vector3(0.0, 0.004, 0.0), mat_rubber)
	for nz_i in range(-3, 4):
		var tick_m: Material = mat_btn_green if nz_i < 0 else (mat_btn_red if nz_i > 0 else mat_steel)
		_add_box(sec, Vector3(0.042, 0.008, 0.010), gate_pos + Vector3(0.056, 0.015, float(nz_i) * 0.044), tick_m)

	var throttle_lever := Node3D.new()
	throttle_lever.name = "ThrottleLeverPivot"
	throttle_lever.position = gate_pos + Vector3(0.0, 0.01, 0.0)
	sec.add_child(throttle_lever)
	_add_cyl(throttle_lever, 0.036, 0.026, Vector3(0.0, 0.018, 0.0), mat_rubber, Vector3.ZERO)
	_add_cyl(throttle_lever, 0.028, 0.026, Vector3(0.0, 0.042, 0.0), mat_rubber, Vector3.ZERO)
	if vintage:
		_add_cyl(throttle_lever, 0.018, 0.28, Vector3(0.0, 0.15, 0.0), mat_brass, Vector3.ZERO)
		_add_cyl(throttle_lever, 0.024, 0.15, Vector3(0.06, 0.28, 0.0), mat_console_top, Vector3(0.0, 0.0, 90.0))
		_add_sph(throttle_lever, 0.026, Vector3(0.135, 0.28, 0.0), mat_brass)
	else:
		_add_cyl(throttle_lever, 0.016, 0.22, Vector3(0.0, 0.13, 0.0), mat_steel, Vector3.ZERO)
		_add_cyl(throttle_lever, 0.026, 0.18, Vector3(0.0, 0.245, 0.0), mat_rubber, Vector3(0.0, 0.0, 90.0))
		_add_cyl(throttle_lever, 0.028, 0.018, Vector3(-0.095, 0.245, 0.0), mat_steel, Vector3(0.0, 0.0, 90.0))
		_add_cyl(throttle_lever, 0.028, 0.018, Vector3(0.095, 0.245, 0.0), mat_steel, Vector3(0.0, 0.0, 90.0))
		_add_box(throttle_lever, Vector3(0.14, 0.018, 0.022), Vector3(0.0, 0.278, 0.0), mat_accent)

	# Animated 3D Speedometer Needle accurately aligned to the raised MFD / Vintage Speedometer Center!
	var speed_needle := Node3D.new()
	speed_needle.name = "SpeedometerNeedle"
	if vintage:
		speed_needle.position = Vector3(-0.26, 1.482, fz + 0.644)
	else:
		speed_needle.position = Vector3(-0.292, 1.474, fz + 0.632)
	speed_needle.rotation.x = deg_to_rad(-18.0)
	sec.add_child(speed_needle)
	_add_box(speed_needle, Vector3(0.0045, 0.058, 0.003), Vector3(0.0, 0.022, 0.0), mat_btn_red)

	# Unified High-Definition Backlit Industrial Switch Console (replaces chunky cartoon buttons!)
	# Left & Right Backlit Switch Plates + Sleek Low-Profile Interactive Square Pushbuttons!
	_add_box(sec, Vector3(0.86, 0.014, 0.20), Vector3(0.06, 1.324, fz + 0.79), mat_dark)
	_add_quad(sec, Vector2(0.40, 0.185), Vector3(-0.15, 1.333, fz + 0.79), Vector3(-88.0, 0.0, 0.0), mat_switch_plate)
	_add_quad(sec, Vector2(0.40, 0.185), Vector3(0.28, 1.333, fz + 0.79), Vector3(-88.0, 0.0, 0.0), mat_switch_plate)

	# 8 Sleek Clickable Low-Profile Backlit Square Industrial Pushbuttons aligned over the switch panel!
	var btn_doors := _add_sleek_switch(sec, "CabBtnDoors", Vector3(-0.30, 1.334, fz + 0.745), mat_btn_green, mat_dark)
	var btn_bell := _add_sleek_switch(sec, "CabBtnBell", Vector3(-0.258, 1.334, fz + 0.745), mat_btn_amber, mat_dark)
	var btn_light := _add_sleek_switch(sec, "CabBtnLight", Vector3(-0.216, 1.334, fz + 0.745), mat_btn_blue, mat_dark)
	var btn_wiper := _add_sleek_switch(sec, "CabBtnWiper", Vector3(-0.174, 1.334, fz + 0.745), mat_btn_blue, mat_dark)
	var btn_panto := _add_sleek_switch(sec, "CabBtnPanto", Vector3(-0.112, 1.334, fz + 0.745), mat_btn_green, mat_dark)
	var btn_sand := _add_sleek_switch(sec, "CabBtnSand", Vector3(-0.070, 1.334, fz + 0.745), mat_btn_amber, mat_dark)

	# Right-Side Compact Industrial Rotary Reverser (F/N/R) + Compact Guarded Red EB Stop Switch!
	var btn_rev := Node3D.new()
	btn_rev.name = "CabBtnReverser"
	btn_rev.position = Vector3(0.18, 1.335, fz + 0.825)
	sec.add_child(btn_rev)
	_add_cyl(btn_rev, 0.022, 0.012, Vector3.ZERO, mat_steel, Vector3.ZERO)
	_add_box(btn_rev, Vector3(0.010, 0.026, 0.044), Vector3(0.0, 0.016, 0.0), mat_dark)
	_add_box(btn_rev, Vector3(0.004, 0.004, 0.020), Vector3(0.0, 0.030, -0.010), mat_btn_blue)

	var btn_eb := Node3D.new()
	btn_eb.name = "CabBtnEB"
	btn_eb.position = Vector3(0.40, 1.336, fz + 0.820)
	sec.add_child(btn_eb)
	_add_cyl(btn_eb, 0.030, 0.010, Vector3.ZERO, mat_btn_amber, Vector3.ZERO)
	_add_cyl(btn_eb, 0.013, 0.020, Vector3(0.0, 0.010, 0.0), mat_steel, Vector3.ZERO)
	var eb_dome := _add_sph(btn_eb, 0.025, Vector3(0.0, 0.024, 0.0), mat_btn_red)
	eb_dome.scale = Vector3(1.0, 0.52, 1.0)

	# Headlamps (single central brass housing on vintage vs twin sculpted LED blades on modern)
	if single_lamp:
		_add_cyl(sec, 0.17, 0.15, Vector3(0.0, 1.04, fz - 0.08), mat_brass, Vector3(90.0, 0.0, 0.0))
		_add_box(sec, Vector3(0.22, 0.22, 0.04), Vector3(0.0, 1.04, fz - 0.15), mat_headlight)
	else:
		for side: float in [-1.0, 1.0]:
			var hl_blade := _add_box(sec, Vector3(0.36, 0.15, 0.06), Vector3(side * (hw - 0.34), 0.86, fz - 0.06), mat_headlight)
			hl_blade.rotation.z = side * deg_to_rad(-8.0)

	var head_spot := SpotLight3D.new()
	head_spot.name = "HeadlampBeam"
	head_spot.light_color = Color(1.0, 0.96, 0.86)
	head_spot.light_energy = 1.2
	head_spot.spot_range = 74.0
	head_spot.spot_angle = 34.0
	head_spot.position = Vector3(0.0, 1.12, fz - 0.18)
	head_spot.rotation.x = deg_to_rad(-4.0)
	sec.add_child(head_spot)

	var cab_anchor := Node3D.new()
	cab_anchor.name = "CabCameraAnchor"
	cab_anchor.position = Vector3(0.0, 1.88, fz + 1.18)
	sec.add_child(cab_anchor)

	return {
		"head_spot": head_spot,
		"cab_anchor": cab_anchor,
		"throttle_lever": throttle_lever,
		"cab_controls": {
			"throttle": throttle_lever,
			"btn_doors": btn_doors,
			"btn_bell": btn_bell,
			"btn_light": btn_light,
			"btn_wiper": btn_wiper,
			"btn_panto": btn_panto,
			"btn_sand": btn_sand,
			"btn_rev": btn_rev,
			"btn_eb": btn_eb,
			"mfd_label": mfd_lbl,
			"sig_label": sig_lbl,
			"speed_needle": speed_needle,
			"wipers": [wiper_l_piv, wiper_r_piv],
			"door_btn_mat": mat_btn_green,
		},
	}


# ---------------------------------------------------------------------------------------------
# Jiaxing T1 tram (CRRC Changchun, 2021) exterior. The cab front is one smooth surface P(u, y): u -1..1
# across, y = height; in plan it bulges forward (superellipse), in side view the chin juts out and the large
# windscreen rakes back into the roof fairing. Regions painted on it: black glass mask (see-through
# windscreen + opaque upper band with the LED destination display), maroon lower nose that sweeps back
# along the cab flanks, slanted headlight clusters, white elsewhere. Cab flanks are flat strips back to the
# body side walls, shoulders follow the roof-fairing profile so nose, flanks and fairing meet seamlessly.
# ---------------------------------------------------------------------------------------------
const JX_TOP := 3.38
const JX_SHOULDER_Y := 2.95
const JX_SHOULDER_R := 0.43
const JX_CAB_LEN := 1.42 # nose tip .. body side walls

static var _jx_mat_cache := {}

static func _jx_mat(key: String) -> Material:
	if _jx_mat_cache.has(key):
		return _jx_mat_cache[key]
	var m: Material
	var body_sh := load("res://shaders/tram_body_pbr.gdshader") as Shader
	match key:
		"maroon":
			var sm := ShaderMaterial.new()
			sm.shader = body_sh
			sm.set_shader_parameter("base_color", Color(0.33, 0.14, 0.11))
			sm.set_shader_parameter("metallic_val", 0.0)
			sm.set_shader_parameter("rough_val", 0.32)
			sm.set_shader_parameter("clearcoat_val", 0.5)
			sm.set_shader_parameter("seam_strength", 0.0)
			m = sm
		"black":
			var sb := ShaderMaterial.new()
			sb.shader = body_sh
			sb.set_shader_parameter("base_color", Color(0.03, 0.032, 0.036))
			sb.set_shader_parameter("metallic_val", 0.0)
			sb.set_shader_parameter("rough_val", 0.30)
			sb.set_shader_parameter("clearcoat_val", 0.5)
			sb.set_shader_parameter("seam_strength", 0.0)
			m = sb
		"glass":
			var sg := ShaderMaterial.new()
			sg.shader = load("res://shaders/tram_glass_pbr.gdshader") as Shader
			sg.set_shader_parameter("tint_color", Color(0.015, 0.018, 0.022))
			sg.set_shader_parameter("base_alpha", 0.86)
			m = sg
	_jx_mat_cache[key] = m
	return m


static func _jx_lerp_tab(tab: Array, y: float) -> float:
	if y <= float(tab[0][0]):
		return float(tab[0][1])
	for i in range(tab.size() - 1):
		var a: Array = tab[i]
		var b: Array = tab[i + 1]
		if y <= float(b[0]):
			var t := (y - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(tab[tab.size() - 1][1])


# Half width of the body / fairing cross-section at height y (rounded shoulders, slight tuck at the bottom)
static func _jx_half_w(hw: float, y: float) -> float:
	if y > JX_SHOULDER_Y:
		var dy := minf(y - JX_SHOULDER_Y, JX_SHOULDER_R)
		return hw - JX_SHOULDER_R + sqrt(maxf(0.0, JX_SHOULDER_R * JX_SHOULDER_R - dy * dy))
	if y < 0.5:
		return hw - 0.06 * (0.5 - y) / 0.28
	return hw


static func _jx_point(hw: float, fz: float, u: float, y: float) -> Vector3:
	# centre-line profile (z relative to the tip plane fz; negative = forward) and plan bulge
	var zb := _jx_lerp_tab([[0.22, -0.18], [0.45, -0.33], [0.80, -0.37], [1.10, -0.33], [1.30, -0.22], [1.60, -0.02],
		[2.40, 0.42], [2.80, 0.66], [3.05, 0.90], [3.25, 1.15], [JX_TOP, JX_CAB_LEN]], y)
	var dep := _jx_lerp_tab([[0.22, 0.26], [0.80, 0.36], [1.30, 0.34], [2.40, 0.26], [3.00, 0.16], [JX_TOP, 0.0]], y)
	var au := absf(u)
	var x := u * _jx_half_w(hw, y)
	var z := fz + zb - dep * (1.0 - pow(au, 2.4))
	return Vector3(x, y, z)


static func _jx_front_region(u: float, y: float) -> String:
	var au := absf(u)
	if y >= 1.24 and y <= 2.96:
		if y < 2.46:
			return "glass"
		if y > 2.55 and y < 2.78 and au < 0.50:
			return "led"
		return "black"
	var hl_lo := 0.98 + 0.20 * (au - 0.40)
	if au > 0.40 and au < 0.90 and y > hl_lo - 0.035 and y < hl_lo + 0.145:
		if y > hl_lo and y < hl_lo + 0.11 and au > 0.43 and au < 0.87:
			return "lamp"
		return "black"
	if y < 0.98 + 0.30 * au * au:
		return "maroon"
	return "white"


static func _jx_side_region(t: float, y: float) -> String:
	# t: 0 at the nose edge .. 1 at the body side wall
	if y >= 1.30 and y <= 2.70 and t < 0.80 - 0.22 * ((y - 1.30) / 1.40):
		return "glass" if y < 2.46 else "black"
	if y >= 2.64 and y <= 2.72 and t > 0.45:
		return "red"
	if y >= 0.25 + 0.75 * t and y <= 1.28 + 0.02 * t:
		return "maroon"
	return "white"


static func _build_jx_nose(sec: Node3D, width: float, fz: float, mat_body: Material, mat_red: Material, mat_lamp: Material, mat_led: Material) -> void:
	var hw := width * 0.5
	var mats := {"white": mat_body, "red": mat_red, "lamp": mat_lamp, "led": _jx_mat("black"),
		"maroon": _jx_mat("maroon"), "black": _jx_mat("black"), "glass": _jx_mat("glass")}
	var sts := {}
	var get_st := func(k: String) -> SurfaceTool:
		if not sts.has(k):
			var st0 := SurfaceTool.new()
			st0.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[k] = st0
		return sts[k]
	# rows: denser around the region boundaries
	var ys: Array[float] = []
	var yy := 0.22
	while yy < JX_TOP - 0.001:
		ys.append(yy)
		var step := 0.04 if (yy > 0.22 and yy < 1.40) or (yy > 2.40 and yy < 3.00) else 0.08
		yy += step
	ys.append(JX_TOP)
	for yb: float in [1.24, 2.46, 2.55, 2.78, 2.96, 1.30, 2.70, 2.64, 2.72]:
		if not ys.has(yb):
			ys.append(yb)
	ys.sort()
	var NU := 56
	var nrm_at := func(u: float, y: float) -> Vector3:
		var du := 0.01
		var dy := 0.01
		var pu: Vector3 = _jx_point(hw, fz, clampf(u + du, -1.0, 1.0), y) - _jx_point(hw, fz, clampf(u - du, -1.0, 1.0), y)
		var py: Vector3 = _jx_point(hw, fz, u, y + dy) - _jx_point(hw, fz, u, y - dy)
		var n: Vector3 = pu.cross(py).normalized()
		if n.z > 0.0:
			n = -n
		return n
	# --- front surface (double-sided except glass so the cab view stays clear) ---
	for j in range(ys.size() - 1):
		var y0 := ys[j]
		var y1 := ys[j + 1]
		for i in range(NU):
			var u0 := -1.0 + 2.0 * float(i) / float(NU)
			var u1 := -1.0 + 2.0 * float(i + 1) / float(NU)
			var reg := _jx_front_region((u0 + u1) * 0.5, (y0 + y1) * 0.5)
			var st: SurfaceTool = get_st.call(reg)
			var q := [[u0, y0], [u1, y0], [u1, y1], [u0, y1]]
			var vs: Array[Vector3] = []
			var ns: Array[Vector3] = []
			for c: Array in q:
				vs.append(_jx_point(hw, fz, c[0], c[1]))
				ns.append(nrm_at.call(c[0], c[1]))
			_jx_quad(st, vs, ns, reg != "glass")
	# --- cab flanks: strips from the nose edge back to the body side wall ---
	var NZ := 30
	for side: float in [-1.0, 1.0]:
		for j in range(ys.size() - 1):
			var y0 := ys[j]
			var y1 := ys[j + 1]
			var e0 := _jx_point(hw, fz, side, y0)
			var e1 := _jx_point(hw, fz, side, y1)
			var zb0 := fz + JX_CAB_LEN
			for k in range(NZ):
				var t0 := float(k) / float(NZ)
				var t1 := float(k + 1) / float(NZ)
				var reg2 := _jx_side_region((t0 + t1) * 0.5, (y0 + y1) * 0.5)
				var st2: SurfaceTool = get_st.call(reg2)
				var a := Vector3(e0.x, y0, lerpf(e0.z, zb0, t0))
				var b := Vector3(e0.x, y0, lerpf(e0.z, zb0, t1))
				var c2 := Vector3(e1.x, y1, lerpf(e1.z, zb0, t1))
				var d := Vector3(e1.x, y1, lerpf(e1.z, zb0, t0))
				var n0 := _jx_side_normal(hw, y0, side)
				var n1 := _jx_side_normal(hw, y1, side)
				var vs2: Array[Vector3] = [a, b, c2, d]
				var ns2: Array[Vector3] = [n0, n0, n1, n1]
				if side < 0.0:
					vs2.assign([b, a, d, c2])
				_jx_quad(st2, vs2, ns2, reg2 != "glass")
	# --- underside of the chin ---
	var stb: SurfaceTool = get_st.call("maroon")
	for i in range(NU):
		var u0 := -1.0 + 2.0 * float(i) / float(NU)
		var u1 := -1.0 + 2.0 * float(i + 1) / float(NU)
		var p0 := _jx_point(hw, fz, u0, 0.22)
		var p1 := _jx_point(hw, fz, u1, 0.22)
		var vs3: Array[Vector3] = [p1, p0, Vector3(p0.x, 0.22, fz + JX_CAB_LEN), Vector3(p1.x, 0.22, fz + JX_CAB_LEN)]
		var ns3: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN]
		_jx_quad(stb, vs3, ns3, true)
	for k: String in sts.keys():
		var mi := MeshInstance3D.new()
		mi.name = "JxNose_" + k
		mi.mesh = (sts[k] as SurfaceTool).commit()
		mi.material_override = mats[k]
		mi.visibility_range_end = 800.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if k == "glass" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		sec.add_child(mi)
	# Orange LED destination text on the black display band (front: route + destination)
	var dp := _jx_point(hw, fz, 0.0, 2.665)
	var dn := _jx_point(hw, fz, 0.0, 2.70) - _jx_point(hw, fz, 0.0, 2.63)
	var dest := Label3D.new()
	dest.name = "JxDestination"
	dest.text = "T1  嘉兴南站"
	dest.font_size = 48
	dest.pixel_size = 0.0042
	dest.outline_size = 0
	dest.modulate = Color(1.0, 0.42, 0.12)
	dest.shaded = false
	dest.double_sided = false
	dest.visibility_range_end = 220.0
	dest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tilt := atan2(dn.z, dn.y)
	dest.transform = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, tilt), dp + Vector3(0.0, 0.0, -0.012))
	sec.add_child(dest)
	# Round red-ring logo on the nose + headlight housings' inner LED strip
	var lp := _jx_point(hw, fz, 0.0, 0.90)
	var logo := _add_cyl(sec, 0.11, 0.02, lp + Vector3(0.0, 0.0, -0.005), mat_red, Vector3(90.0, 0.0, 0.0))
	logo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_cyl(sec, 0.075, 0.022, lp + Vector3(0.0, 0.0, -0.008), mat_body, Vector3(90.0, 0.0, 0.0))
	_add_cyl(sec, 0.045, 0.024, lp + Vector3(0.0, 0.0, -0.011), mat_red, Vector3(90.0, 0.0, 0.0))


static func _jx_side_normal(hw: float, y: float, side: float) -> Vector3:
	if y > JX_SHOULDER_Y:
		var dy := minf(y - JX_SHOULDER_Y, JX_SHOULDER_R - 0.001)
		var dx := sqrt(maxf(0.0, JX_SHOULDER_R * JX_SHOULDER_R - dy * dy))
		return Vector3(side * dx, dy, 0.0).normalized()
	return Vector3(side, 0.0, 0.0)


# Quad (CCW seen from outside) with per-vertex normals; optionally also the back face (seen from inside)
static func _jx_quad(st: SurfaceTool, vs: Array[Vector3], ns: Array[Vector3], both: bool) -> void:
	# Godot front faces wind clockwise as seen by the viewer; vs run counter-clockwise seen from outside
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(ns[idx])
		st.set_uv(Vector2(vs[idx].x, vs[idx].y))
		st.add_vertex(vs[idx])
	if both:
		for idx: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(-ns[idx])
			st.set_uv(Vector2(vs[idx].x, vs[idx].y))
			st.add_vertex(vs[idx])


# Roof fairing over one body section: wall top (y = shoulder) rounding into a flat top, closed at both ends
static func _build_jx_fairing(sec: Node3D, width: float, z0: float, z1: float, mat_body: Material) -> void:
	var hw := width * 0.5
	var prof: Array[Vector2] = []
	var n_arc := 8
	for k in range(n_arc + 1):
		var a := float(k) / float(n_arc) * PI * 0.5
		prof.append(Vector2(hw - JX_SHOULDER_R + cos(a) * JX_SHOULDER_R, JX_SHOULDER_Y + sin(a) * JX_SHOULDER_R))
	var full: Array[Vector2] = []
	for p in prof:
		full.append(p)
	for k in range(prof.size() - 1, -1, -1):
		full.append(Vector2(-prof[k].x, prof[k].y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(full.size() - 1):
		var a2 := full[k]
		var b2 := full[k + 1]
		var na := Vector3(a2.x, a2.y - JX_SHOULDER_Y + 0.05, 0.0).normalized()
		var nb := Vector3(b2.x, b2.y - JX_SHOULDER_Y + 0.05, 0.0).normalized()
		if absf(a2.x) < hw - JX_SHOULDER_R + 0.001:
			na = Vector3.UP
		if absf(b2.x) < hw - JX_SHOULDER_R + 0.001:
			nb = Vector3.UP
		var vs: Array[Vector3] = [Vector3(a2.x, a2.y, z1), Vector3(b2.x, b2.y, z1), Vector3(b2.x, b2.y, z0), Vector3(a2.x, a2.y, z0)]
		var ns: Array[Vector3] = [na, nb, nb, na]
		_jx_quad(st, vs, ns, false)
	# end caps (visible at the gangways)
	for zc: float in [z0, z1]:
		var nz := Vector3(0.0, 0.0, -1.0 if zc == z0 else 1.0)
		var ctr := Vector3(0.0, JX_SHOULDER_Y, zc)
		for k in range(full.size() - 1):
			var p0 := Vector3(full[k].x, full[k].y, zc)
			var p1 := Vector3(full[k + 1].x, full[k + 1].y, zc)
			var tri: Array = [ctr, p0, p1] if zc == z0 else [ctr, p1, p0]
			for v: Vector3 in tri:
				st.set_normal(nz)
				st.set_uv(Vector2(v.x, v.y))
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "JxFairing"
	mi.mesh = st.commit()
	mi.material_override = mat_body
	mi.visibility_range_end = 900.0
	sec.add_child(mi)


static func _build_roof_equipment(
	sec: Node3D,
	width: float,
	sec_len: float,
	roof_kind: String,
	vintage: bool,
	mat_roof: Material,
	mat_body: Material,
	mat_dark: Material,
	mat_cove: Material,
	mat_accent: Material = null
) -> void:
	if vintage or roof_kind == "clerestory":
		# Classic raised monitor clerestory roof with glowing side transom windows!
		_add_box(sec, Vector3(width * 0.58, 0.28, sec_len * 0.78), Vector3(0.0, 3.26, 0.0), mat_roof)
		_add_box(sec, Vector3(width * 0.60, 0.12, sec_len * 0.74), Vector3(0.0, 3.22, 0.0), mat_cove)
	elif roof_kind == "vintage_arch":
		_add_box(sec, Vector3(width * 0.74, 0.20, sec_len * 0.84), Vector3(0.0, 3.22, 0.0), mat_roof)
		for vz: float in [-2.6, 0.0, 2.6]:
			_add_cyl(sec, 0.16, 0.12, Vector3(0.0, 3.36, vz), mat_dark, Vector3.ZERO)
	elif roof_kind == "nanhu_supercap":
		# Authentic Jiaxing "南湖号" full-length sleek white aerodynamic supercapacitor roof fairings + red pinstripe!
		for side: float in [-1.0, 1.0]:
			_add_box(sec, Vector3(0.12, 0.30, sec_len - 0.22), Vector3(side * (width * 0.47), 3.26, 0.0), mat_body)
			if mat_accent != null:
				_add_box(sec, Vector3(0.135, 0.08, sec_len - 0.18), Vector3(side * (width * 0.472), 3.16, 0.0), mat_accent)
		_add_box(sec, Vector3(width * 0.76, 0.26, sec_len * 0.68), Vector3(0.0, 3.25, 0.0), mat_roof)
		_add_box(sec, Vector3(width * 0.56, 0.06, sec_len * 0.58), Vector3(0.0, 3.39, 0.0), mat_dark)
	elif roof_kind == "shrouded":
		# Sleek full-length aerodynamic rooftop side fairings
		for side: float in [-1.0, 1.0]:
			_add_box(sec, Vector3(0.10, 0.24, sec_len - 0.5), Vector3(side * (width * 0.46), 3.24, 0.0), mat_body)
		_add_box(sec, Vector3(width * 0.62, 0.20, 2.6), Vector3(0.0, 3.22, 0.0), mat_roof)
	elif roof_kind == "battery":
		# Supercapacitor / ESS battery pack enclosures + HVAC pod
		_add_box(sec, Vector3(width * 0.68, 0.28, 2.2), Vector3(0.0, 3.26, -1.8), mat_dark)
		_add_box(sec, Vector3(width * 0.64, 0.22, 2.0), Vector3(0.0, 3.23, 1.6), mat_roof)
	else:
		_add_box(sec, Vector3(width * 0.68, 0.24, 2.5), Vector3(0.0, 3.24, 0.0), mat_roof)


static func _build_detailed_bogie(
	parent: Node3D,
	z_pos: float,
	mat_frame: Material,
	mat_wheel: Material,
	mat_accent: Material
) -> void:
	var bogie := Node3D.new()
	bogie.position = Vector3(0.0, 0.0, z_pos)
	parent.add_child(bogie)

	_add_box(bogie, Vector3(1.92, 0.18, 2.15), Vector3(0.0, 0.36, 0.0), mat_frame)
	# Magnetic track brake shoes between wheels + primary suspension springs!
	for side: float in [-1.0, 1.0]:
		_add_box(bogie, Vector3(0.12, 0.10, 0.92), Vector3(side * 0.72, 0.18, 0.0), mat_accent)
		_add_cyl(bogie, 0.11, 0.24, Vector3(side * 0.84, 0.42, 0.0), mat_frame, Vector3.ZERO)

	for axle_z: float in [-0.70, 0.70]:
		_add_cyl(bogie, 0.065, 1.52, Vector3(0.0, 0.426, axle_z), mat_frame, Vector3(0.0, 0.0, 90.0))
		for side: float in [-1.0, 1.0]:
			_add_cyl(bogie, 0.33, 0.10, Vector3(side * 0.72, 0.426, axle_z), mat_wheel, Vector3(0.0, 0.0, 90.0))


static func _build_pantograph(
	parent: Node3D,
	kind: String,
	mat_dark: Material,
	mat_steel: Material,
	mat_brass: Material
) -> void:
	var panto := Node3D.new()
	panto.name = "Pantograph"
	panto.position = Vector3(0.0, 3.18, 0.0)
	parent.add_child(panto)

	_add_box(panto, Vector3(1.15, 0.08, 1.25), Vector3(0.0, 0.04, 0.0), mat_dark)

	if kind == "trolley_pole":
		var pole := _add_box(panto, Vector3(0.055, 0.055, 3.85), Vector3(0.0, 0.92, 1.45), mat_brass)
		pole.rotation.x = deg_to_rad(27.0)
		_add_box(panto, Vector3(0.24, 0.10, 0.18), Vector3(0.0, 1.77, 3.15), mat_dark)
	elif kind == "diamond":
		for side: float in [-0.42, 0.42]:
			var low1 := _add_box(panto, Vector3(0.04, 0.98, 0.04), Vector3(side, 0.44, -0.35), mat_steel)
			low1.rotation.x = deg_to_rad(-36.0)
			var low2 := _add_box(panto, Vector3(0.04, 0.98, 0.04), Vector3(side, 0.44, 0.35), mat_steel)
			low2.rotation.x = deg_to_rad(36.0)
			var up1 := _add_box(panto, Vector3(0.04, 0.98, 0.04), Vector3(side, 1.28, -0.35), mat_steel)
			up1.rotation.x = deg_to_rad(36.0)
			var up2 := _add_box(panto, Vector3(0.04, 0.98, 0.04), Vector3(side, 1.28, 0.35), mat_steel)
			up2.rotation.x = deg_to_rad(-36.0)
		_add_box(panto, Vector3(1.48, 0.05, 0.14), Vector3(0.0, 1.76, 0.0), mat_dark)
	elif kind == "supercap_charge":
		# Compact low-profile station rapid-charge supercapacitor collector (retracted while running catenary-free!)
		var arm_low := _add_box(panto, Vector3(0.08, 0.52, 0.08), Vector3(0.0, 0.20, 0.18), mat_steel)
		arm_low.rotation.x = deg_to_rad(68.0)
		var arm_up := _add_box(panto, Vector3(0.06, 0.54, 0.06), Vector3(0.0, 0.42, 0.16), mat_steel)
		arm_up.rotation.x = deg_to_rad(-70.0)
		_add_box(panto, Vector3(1.18, 0.06, 0.24), Vector3(0.0, 0.56, -0.06), mat_dark)
	else:
		var lower_arm := _add_box(panto, Vector3(0.08, 1.08, 0.08), Vector3(0.0, 0.46, 0.32), mat_steel)
		lower_arm.rotation.x = deg_to_rad(38.0)
		var upper_arm := _add_box(panto, Vector3(0.06, 1.16, 0.06), Vector3(0.0, 1.30, 0.28), mat_steel)
		upper_arm.rotation.x = deg_to_rad(-42.0)
		_add_box(panto, Vector3(1.56, 0.05, 0.22), Vector3(0.0, 1.76, -0.10), mat_dark)


static func _build_seated_passenger(seed_i: int, sx: float, sz: float, side: float) -> Dictionary:
	var p := Node3D.new()
	p.position = Vector3(sx, 0.96, sz)
	var h_sc := 0.94 + float(seed_i % 5) * 0.025
	p.scale = Vector3(h_sc, h_sc, h_sc)
	var coat_pal: Array[Color] = [
		Color(0.14, 0.23, 0.36), Color(0.50, 0.38, 0.25), Color(0.20, 0.29, 0.23),
		Color(0.26, 0.26, 0.30), Color(0.45, 0.18, 0.19), Color(0.35, 0.40, 0.46),
	]
	var skin_pal: Array[Color] = [
		Color(0.87, 0.71, 0.60), Color(0.78, 0.60, 0.47), Color(0.90, 0.76, 0.66), Color(0.56, 0.40, 0.30),
	]
	var hair_pal: Array[Color] = [
		Color(0.11, 0.09, 0.08), Color(0.25, 0.16, 0.10), Color(0.38, 0.28, 0.16), Color(0.17, 0.16, 0.15),
	]
	var pants_pal: Array[Color] = [
		Color(0.20, 0.31, 0.48), Color(0.56, 0.49, 0.38), Color(0.36, 0.38, 0.42),
		Color(0.26, 0.32, 0.24), Color(0.34, 0.44, 0.56), Color(0.42, 0.34, 0.28),
	]
	var arch := seed_i % 4
	var hair_st := (seed_i / 2) % 4
	var wears_skirt := (arch == 2 or (seed_i % 3 == 1))
	var mat_coat := _make_mat(coat_pal[seed_i % coat_pal.size()], 0.84, 0.0)
	var mat_skin := _make_mat(skin_pal[seed_i % skin_pal.size()], 0.62, 0.0)
	var mat_pants := _make_mat(pants_pal[seed_i % pants_pal.size()], 0.86, 0.0)
	var mat_hair := _make_mat(hair_pal[seed_i % hair_pal.size()], 0.76, 0.0)
	var mat_shoe := _make_mat(Color(0.18, 0.16, 0.15) if seed_i % 2 == 0 else Color(0.36, 0.24, 0.16), 0.72, 0.0)
	var mat_leg_low: Material = mat_skin if wears_skirt else mat_pants

	# Anatomically sculpted seated thighs + shins + shoes (+ skirt drape when wearing skirt!)
	var thigh_m := HumanMeshGen.get_thigh_mesh()
	var shin_m := HumanMeshGen.get_shin_mesh()
	var shoe_m := HumanMeshGen.get_shoe_mesh()
	for lx: float in [-0.085, 0.085]:
		_add_mesh_inst(p, thigh_m, Vector3(lx, 0.03, -0.10), Vector3(90.0, 0.0, 0.0), mat_coat if wears_skirt else mat_pants)
		_add_mesh_inst(p, shin_m, Vector3(lx, -0.18, -0.25), Vector3.ZERO, mat_leg_low)
		_add_mesh_inst(p, shoe_m, Vector3(lx, -0.39, -0.27), Vector3.ZERO, mat_shoe)
	if wears_skirt:
		_add_box(p, Vector3(0.32, 0.08, 0.34), Vector3(0.0, 0.06, -0.09), mat_coat)

	var torso := Node3D.new()
	torso.position = Vector3(0.0, 0.26, 0.05)
	p.add_child(torso)
	_add_mesh_inst(torso, HumanMeshGen.get_torso_mesh(arch), Vector3.ZERO, Vector3.ZERO, mat_coat)
	_add_mesh_inst(torso, HumanMeshGen.get_collar_mesh(arch), Vector3.ZERO, Vector3.ZERO, mat_coat)
	_add_mesh_inst(torso, HumanMeshGen.get_neck_mesh(), Vector3(0.0, 0.295, 0.0), Vector3.ZERO, mat_skin)

	var sh_x := 0.166 if arch == 2 else 0.180
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-sh_x, 0.175, 0.0)
	arm_l.rotation.x = deg_to_rad(-28.0)
	torso.add_child(arm_l)
	_add_mesh_inst(arm_l, HumanMeshGen.get_upper_arm_mesh(), Vector3(0.0, -0.12, 0.0), Vector3.ZERO, mat_coat)
	_add_mesh_inst(arm_l, HumanMeshGen.get_forearm_mesh(), Vector3(0.0, -0.28, -0.05), Vector3(-25.0, 0.0, 0.0), mat_coat)
	_add_mesh_inst(arm_l, HumanMeshGen.get_hand_mesh(), Vector3(0.0, -0.39, -0.09), Vector3.ZERO, mat_skin)

	var has_phone := (seed_i % 3 == 0)
	var arm_r := Node3D.new()
	arm_r.position = Vector3(sh_x, 0.175, 0.0)
	arm_r.rotation.x = deg_to_rad(-44.0 if has_phone else -26.0)
	torso.add_child(arm_r)
	_add_mesh_inst(arm_r, HumanMeshGen.get_upper_arm_mesh(), Vector3(0.0, -0.12, 0.0), Vector3.ZERO, mat_coat)
	_add_mesh_inst(arm_r, HumanMeshGen.get_forearm_mesh(), Vector3(0.0, -0.28, -0.05), Vector3(-25.0, 0.0, 0.0), mat_coat)
	_add_mesh_inst(arm_r, HumanMeshGen.get_hand_mesh(), Vector3(0.0, -0.39, -0.09), Vector3.ZERO, mat_skin)
	if has_phone:
		var mat_phone := _emit_mat(Color(0.12, 0.18, 0.24), Color(0.45, 0.78, 0.98), 1.2)
		_add_box(arm_r, Vector3(0.062, 0.012, 0.105), Vector3(-0.04, -0.39, -0.12), mat_phone)

	var head := HumanMeshGen.build_detailed_head(
		torso, mat_skin, mat_hair, hair_st,
		skin_pal[seed_i % skin_pal.size()], hair_pal[seed_i % hair_pal.size()],
		(seed_i % 4 == 1)
	)
	head.position = Vector3(0.0, 0.40, -0.005)

	return {
		"root": p,
		"torso": torso,
		"head": head,
		"arm_l": arm_l,
		"arm_r": arm_r,
		"is_standing": false,
		"has_phone": has_phone,
		"side": side,
		"seed": float(seed_i) * 1.73,
		"pop_t": 1.0,
	}


static func _build_standing_cabin_passenger(seed_i: int, ax: float, az: float) -> Dictionary:
	var p := Node3D.new()
	p.position = Vector3(ax, 0.57, az)
	var h_sc := 0.96
	p.scale = Vector3(h_sc, h_sc, h_sc)
	var coat_pal: Array[Color] = [
		Color(0.16, 0.28, 0.42), Color(0.46, 0.20, 0.19), Color(0.22, 0.32, 0.24),
		Color(0.54, 0.42, 0.28), Color(0.28, 0.26, 0.32),
	]
	var pants_pal: Array[Color] = [
		Color(0.20, 0.31, 0.48), Color(0.56, 0.49, 0.38), Color(0.36, 0.38, 0.42),
		Color(0.26, 0.32, 0.24), Color(0.34, 0.44, 0.56),
	]
	var arch := seed_i % 4
	var hair_st := (seed_i + 1) % 4
	var wears_skirt := (arch == 2 or (seed_i % 3 == 1))
	var mat_coat := _make_mat(coat_pal[seed_i % coat_pal.size()], 0.84, 0.0)
	var mat_skin := _make_mat(Color(0.85, 0.69, 0.58), 0.62, 0.0)
	var mat_pants := _make_mat(pants_pal[seed_i % pants_pal.size()], 0.86, 0.0)
	var mat_hair := _make_mat(Color(0.13, 0.10, 0.08), 0.76, 0.0)
	var mat_shoe := _make_mat(Color(0.18, 0.16, 0.15), 0.72, 0.0)
	var leg_mat: Material = mat_skin if wears_skirt else mat_pants

	for lx: float in [-0.085, 0.085]:
		_add_mesh_inst(p, HumanMeshGen.get_thigh_mesh(), Vector3(lx, 0.62, 0.0), Vector3.ZERO, leg_mat)
		_add_mesh_inst(p, HumanMeshGen.get_shin_mesh(), Vector3(lx, 0.22, 0.0), Vector3.ZERO, leg_mat)
		_add_mesh_inst(p, HumanMeshGen.get_shoe_mesh(), Vector3(lx, 0.0, -0.02), Vector3.ZERO, mat_shoe)

	var torso := Node3D.new()
	torso.position = Vector3(0.0, 1.08, 0.0)
	p.add_child(torso)
	_add_mesh_inst(torso, HumanMeshGen.get_torso_mesh(arch), Vector3.ZERO, Vector3.ZERO, mat_coat)
	_add_mesh_inst(torso, HumanMeshGen.get_collar_mesh(arch), Vector3.ZERO, Vector3.ZERO, mat_coat)
	_add_mesh_inst(torso, HumanMeshGen.get_neck_mesh(), Vector3(0.0, 0.295, 0.0), Vector3.ZERO, mat_skin)
	# Attach skirt to root `p` (pelvis) instead of swaying `torso` so thighs NEVER poke through during braking/accel!
	if wears_skirt:
		_add_mesh_inst(p, HumanMeshGen.get_skirt_mesh(seed_i % 2 == 0), Vector3(0.0, 0.88, 0.0), Vector3.ZERO, mat_coat)

	# Raise the arm on the rail side (+X holds right rail +0.44 with arm_r; -X holds left rail -0.44 with arm_l)
	# so the hand sits DIRECTLY inside the hanging strap handle at y = 2.18, x = +-0.44, z = az!
	var hold_right := (ax >= 0.0)
	var sh_x_s := 0.168 if arch == 2 else 0.180
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-sh_x_s, 0.175, 0.0)
	arm_l.rotation.x = deg_to_rad(-174.0 if not hold_right else -14.0)
	torso.add_child(arm_l)
	_add_mesh_inst(arm_l, HumanMeshGen.get_upper_arm_mesh(), Vector3(0.0, -0.12, 0.0), Vector3.ZERO, mat_coat)
	_add_mesh_inst(arm_l, HumanMeshGen.get_forearm_mesh(), Vector3(0.0, -0.32, 0.0), Vector3.ZERO, mat_coat)
	_add_mesh_inst(arm_l, HumanMeshGen.get_hand_mesh(), Vector3(0.0, -0.43, 0.0), Vector3.ZERO, mat_skin)

	var arm_r := Node3D.new()
	arm_r.position = Vector3(sh_x_s, 0.175, 0.0)
	arm_r.rotation.x = deg_to_rad(-174.0 if hold_right else -14.0)
	torso.add_child(arm_r)
	_add_mesh_inst(arm_r, HumanMeshGen.get_upper_arm_mesh(), Vector3(0.0, -0.12, 0.0), Vector3.ZERO, mat_coat)
	_add_mesh_inst(arm_r, HumanMeshGen.get_forearm_mesh(), Vector3(0.0, -0.32, 0.0), Vector3.ZERO, mat_coat)
	_add_mesh_inst(arm_r, HumanMeshGen.get_hand_mesh(), Vector3(0.0, -0.43, 0.0), Vector3.ZERO, mat_skin)

	var head := HumanMeshGen.build_detailed_head(
		torso, mat_skin, mat_hair, hair_st,
		Color(0.85, 0.69, 0.58), Color(0.13, 0.10, 0.08),
		(seed_i % 4 == 2)
	)
	head.position = Vector3(0.0, 0.40, -0.005)

	return {
		"root": p,
		"torso": torso,
		"head": head,
		"arm_l": arm_l,
		"arm_r": arm_r,
		"is_standing": true,
		"has_phone": false,
		"side": signf(ax),
		"seed": float(seed_i) * 2.17,
		"pop_t": 1.0,
	}


static func _add_mesh_inst(parent: Node3D, m: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.visibility_range_end = 140.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _add_sleek_switch(parent: Node3D, s_name: String, pos: Vector3, cap_mat: Material, bezel_mat: Material) -> Node3D:
	var sw := Node3D.new()
	sw.name = s_name
	sw.position = pos
	parent.add_child(sw)
	_add_box(sw, Vector3(0.033, 0.008, 0.028), Vector3.ZERO, bezel_mat)
	_add_box(sw, Vector3(0.025, 0.011, 0.020), Vector3(0.0, 0.003, 0.0), cap_mat)
	return sw


static func _add_cap(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cp := CapsuleMesh.new()
	cp.radius = r
	cp.height = h
	cp.radial_segments = 10
	cp.rings = 4
	cp.material = mat
	mi.mesh = cp
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.visibility_range_end = 140.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _make_mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func _emit_mat(alb: Color, em: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = alb
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = em
	m.emission_energy_multiplier = energy
	return m


static func _add_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	var max_dim := maxf(sz.x, maxf(sz.y, sz.z))
	var min_dim := minf(sz.x, minf(sz.y, sz.z))
	mi.visibility_range_end = 800.0 if max_dim >= 1.4 else (320.0 if max_dim >= 0.55 else 160.0)
	if max_dim < 1.4 or min_dim <= 0.045:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _add_cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.visibility_range_end = 450.0 if r >= 0.25 else 180.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _add_sph(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	sm.material = mat
	mi.mesh = sm
	mi.position = pos
	mi.visibility_range_end = 150.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _add_quad(parent: Node3D, sz: Vector2, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = sz
	qm.material = mat
	mi.mesh = qm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.visibility_range_end = 160.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _add_cab_label(parent: Node3D, txt: String, pos: Vector3, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = 24
	lbl.pixel_size = 0.00075
	lbl.modulate = col
	lbl.outline_size = 3
	lbl.outline_modulate = Color(0.03, 0.04, 0.06)
	lbl.position = pos
	lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	lbl.visibility_range_end = 90.0
	lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lbl)


static var _shape_cache: Dictionary = {}


static func _get_strap_ring_mesh() -> Mesh:
	if not _shape_cache.has("ring"):
		var t := TorusMesh.new()
		t.inner_radius = 0.048
		t.outer_radius = 0.064
		t.rings = 16
		t.ring_segments = 6
		_shape_cache["ring"] = t
	return _shape_cache["ring"]


# Contoured transit seat: profile (z, y) swept across the seat width. Seat faces -Z, back at +Z.
static func _get_seat_mesh(cushion: bool) -> Mesh:
	var key := "seat_c" if cushion else "seat_s"
	if _shape_cache.has(key):
		return _shape_cache[key]
	var prof: Array[Vector2] = [
		Vector2(-0.235, -0.035), Vector2(-0.215, 0.0), Vector2(-0.16, 0.012), Vector2(-0.02, 0.006),
		Vector2(0.11, -0.006), Vector2(0.18, 0.01), Vector2(0.215, 0.07), Vector2(0.235, 0.20),
		Vector2(0.255, 0.36), Vector2(0.27, 0.52), Vector2(0.275, 0.62), Vector2(0.262, 0.665),
	]
	var thick := 0.032
	var half_w := 0.235
	var lift := 0.0
	if cushion:
		prof = prof.slice(1, prof.size() - 1)
		thick = 0.034
		half_w = 0.205
		lift = 0.026
	# Offset line on the "top/front" side of the shell (normal of profile pointing up/forward)
	var n := prof.size()
	var top: Array[Vector2] = []
	var bot: Array[Vector2] = []
	for i in range(n):
		var t := (prof[mini(i + 1, n - 1)] - prof[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(t.y, -t.x) # left normal: up on the pan, forward (-z) on the back
		if nrm.y < 0.0 and absf(t.x) > 0.5:
			nrm = -nrm
		if t.y > 0.5 and nrm.x > 0.0:
			nrm = -nrm
		var base := prof[i] + nrm * lift
		top.append(base + nrm * thick)
		bot.append(base)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs: Array[float] = [-half_w, half_w]
	var rnd := 0.03
	for i in range(n - 1):
		for pair: Array in [[top, true], [bot, false]]:
			var ln: Array[Vector2] = pair[0]
			var a := ln[i]
			var b := ln[i + 1]
			# rounded side edges: narrow the outermost strip slightly
			var p00 := Vector3(xs[0] + rnd, a.y, a.x); var p10 := Vector3(xs[1] - rnd, a.y, a.x)
			var p01 := Vector3(xs[0] + rnd, b.y, b.x); var p11 := Vector3(xs[1] - rnd, b.y, b.x)
			if pair[1]:
				_tri(st, p00, p01, p11); _tri(st, p00, p11, p10)
			else:
				_tri(st, p00, p11, p01); _tri(st, p00, p10, p11)
		# side walls (with a bevel strip toward the rounded edge)
		for sd in range(2):
			var x_out := xs[sd]
			var x_in := xs[sd] + (rnd if sd == 0 else -rnd)
			var ta := top[i]; var tb := top[i + 1]; var ba := bot[i]; var bb := bot[i + 1]
			var mid_a := (ta + ba) * 0.5; var mid_b := (tb + bb) * 0.5
			var q := [
				[Vector3(x_in, ta.y, ta.x), Vector3(x_in, tb.y, tb.x), Vector3(x_out, mid_b.y, mid_b.x), Vector3(x_out, mid_a.y, mid_a.x)],
				[Vector3(x_out, mid_a.y, mid_a.x), Vector3(x_out, mid_b.y, mid_b.x), Vector3(x_in, bb.y, bb.x), Vector3(x_in, ba.y, ba.x)],
			]
			for quad: Array in q:
				if sd == 0:
					_tri(st, quad[0], quad[1], quad[2]); _tri(st, quad[0], quad[2], quad[3])
				else:
					_tri(st, quad[0], quad[2], quad[1]); _tri(st, quad[0], quad[3], quad[2])
	# end caps
	for e_i: int in [0, n - 1]:
		var tt := top[e_i]; var bb2 := bot[e_i]
		var c := [Vector3(xs[0] + rnd, tt.y, tt.x), Vector3(xs[1] - rnd, tt.y, tt.x), Vector3(xs[1] - rnd, bb2.y, bb2.x), Vector3(xs[0] + rnd, bb2.y, bb2.x)]
		if e_i == 0:
			_tri(st, c[0], c[1], c[2]); _tri(st, c[0], c[2], c[3])
		else:
			_tri(st, c[0], c[2], c[1]); _tri(st, c[0], c[3], c[2])
	st.generate_normals()
	var mesh := st.commit()
	_shape_cache[key] = mesh
	return mesh


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_uv(Vector2(a.x * 2.0, a.y * 2.0 + a.z)); st.add_vertex(a)
	st.set_uv(Vector2(b.x * 2.0, b.y * 2.0 + b.z)); st.add_vertex(b)
	st.set_uv(Vector2(c.x * 2.0, c.y * 2.0 + c.z)); st.add_vertex(c)
