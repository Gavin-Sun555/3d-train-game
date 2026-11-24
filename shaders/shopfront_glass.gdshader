shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Shop window glazing with a parallax-traced, lit shop interior behind it, plus the surface details of a real
// street shop: window posters, opening-hours sticker, door sign and clear PVC strip door curtains. The same
// shader also draws the scrolling LED text board over a door and the galvanised roller shutter.
// UV.x = metres along the shopfront, UV.y = metres above window sill (LED board / shutter: own 0..w, 0..h).
// COLOR.rgb = interior accent (brand / merchandise colour), COLOR.a * 255 = code:
//   code & 7  : 0 cafe/restaurant  1 fashion/retail  2 bank/office  3 grocery/pharmacy/convenience  4 bar
//               5 LED text board  6 roller shutter
//   code & 8  : door glass (door sign, PVC strip curtain for local shops)
//   code & 16 : posters / stickers on this window
//   code & 32 : Chinese local shop (white wall tiles, strip curtain, LED-lit, fridges)

uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sky_tint = vec3(0.62, 0.72, 0.82);

varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying vec4 v_col;
varying vec2 v_uv;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
	v_uv = UV;
}

// Packaging colours: muted, varied, with some of the shop's accent colour
vec3 product_col(vec2 id, vec3 accent) {
	float h = hash21(id);
	vec3 pal[6] = vec3[6](vec3(0.82, 0.22, 0.18), vec3(0.95, 0.80, 0.30), vec3(0.20, 0.45, 0.70),
		vec3(0.92, 0.92, 0.88), vec3(0.25, 0.55, 0.30), vec3(0.95, 0.55, 0.20));
	vec3 c = pal[int(h * 5.99)];
	return mix(c, accent, 0.25) * (0.80 + 0.25 * fract(h * 9.7));
}

// A shelf face (x along, y up, metres): rows of small packs with white shelf lips and price strips
vec3 shelf_face(vec2 p, float bay, vec3 accent, out float is_item) {
	float row_h = 0.42;
	float row = floor(p.y / row_h);
	float fy = fract(p.y / row_h) * row_h;
	is_item = 0.0;
	if (fy < 0.045) {
		return vec3(0.93, 0.93, 0.92); // shelf lip
	}
	if (fy < 0.075) {
		return mix(vec3(0.95, 0.95, 0.9), vec3(0.9, 0.2, 0.15), step(0.8, fract(p.x * 3.1))); // price strip
	}
	float w = 0.07 + 0.08 * hash21(vec2(row, bay));
	float id = floor(p.x / w);
	float fx = fract(p.x / w);
	float ph = 0.16 + 0.20 * hash21(vec2(id + bay * 31.0, row));
	if (fx > 0.08 && fx < 0.94 && fy < 0.075 + ph) {
		is_item = 1.0;
		vec3 c = product_col(vec2(floor(id * 0.5) + bay * 17.0, row), accent);
		float label = step(0.35, (fy - 0.075) / ph) * step((fy - 0.075) / ph, 0.62);
		return mix(c, vec3(0.95), label * 0.45);
	}
	return vec3(0.40, 0.40, 0.42); // shelf back panel
}

void fragment() {
	int code = int(round(v_col.a * 255.0));
	int kind = code % 8;
	bool is_door = (code / 8) % 2 == 1;
	bool posters = (code / 16) % 2 == 1;
	bool local_zh = (code / 32) % 2 == 1;
	vec3 accent = v_col.rgb;

	vec3 n_h = normalize(vec3(v_world_nrm.x, 0.0, v_world_nrm.z) + vec3(1e-5, 0.0, 0.0));
	vec3 t_h = vec3(n_h.z, 0.0, -n_h.x);
	vec3 to_frag = v_world_pos - CAMERA_POSITION_WORLD;
	float dist = length(to_frag);
	vec3 vd = to_frag / max(dist, 1e-4);
	float ndv = clamp(dot(n_h, -vd), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);

	// --- Scrolling red LED text board (LED走字屏) ---
	if (kind == 5) {
		vec2 cell = v_uv / 0.045;
		vec2 f = fract(cell) - 0.5;
		float dot_m = 1.0 - smoothstep(0.28, 0.42, length(f));
		float col_i = floor(cell.x + TIME * 9.0);
		float row_i = floor(cell.y);
		// pseudo glyphs: 6-dot wide characters, 7 rows of the 9-dot board lit by a hash pattern
		float ch = floor(col_i / 7.0);
		float in_ch = step(0.5, mod(col_i, 7.0)) * step(mod(col_i, 7.0), 5.5) * step(1.0, row_i) * step(row_i, 7.0);
		float on = in_ch * step(0.45, hash21(vec2(ch * 3.0 + mod(col_i, 7.0), row_i + ch)));
		vec3 led = mix(vec3(1.0, 0.08, 0.04), vec3(1.0, 0.62, 0.08), step(0.7, hash21(vec2(ch, 2.0))));
		ALBEDO = vec3(0.03) + led * on * dot_m * 0.3;
		EMISSION = led * on * dot_m * (2.2 + night_factor * 2.0);
		ROUGHNESS = 0.35;
		METALLIC = 0.0;
		SPECULAR = 0.4;
	}
	// --- Galvanised roller shutter (卷帘门) ---
	else if (kind == 6) {
		float rib = fract(v_uv.y / 0.085);
		float shade = 0.78 + 0.22 * smoothstep(0.0, 0.5, rib) * (1.0 - smoothstep(0.55, 1.0, rib));
		float grime = 0.92 + 0.08 * hash21(floor(v_uv * vec2(1.3, 6.0)));
		ALBEDO = vec3(0.66, 0.68, 0.70) * shade * grime;
		ROUGHNESS = 0.45;
		METALLIC = 0.55;
		SPECULAR = 0.5;
	}
	else {
		vec3 r = vec3(dot(vd, t_h), vd.y, max(dot(vd, -n_h), 0.03));
		// Room: 4 m bays wide, 3.0 m tall (from sill), 5.5 m deep
		float bay_w = 4.0;
		float room_h = 3.0;
		float depth = 5.5;
		vec2 p0 = vec2(fract(v_uv.x / bay_w) * bay_w, v_uv.y);
		float bay_id = floor(v_uv.x / bay_w);
		float shop_h = hash21(vec2(bay_id, accent.r * 13.0 + accent.g * 7.0));
		float tx = ((r.x > 0.0 ? bay_w : 0.0) - p0.x) / (abs(r.x) < 1e-4 ? 1e-4 : r.x);
		float ty = ((r.y > 0.0 ? room_h : -0.5) - p0.y) / (abs(r.y) < 1e-4 ? 1e-4 : r.y);
		float tz = depth / r.z;
		float t = min(min(tx, ty), tz);
		vec3 hit = vec3(p0, 0.0) + r * t;
		bool on_ceil = abs(t - ty) < 1e-3 && r.y > 0.0;
		bool on_floor = abs(t - ty) < 1e-3 && r.y < 0.0;
		bool on_back = abs(t - tz) < 1e-3;

		vec3 wall = mix(vec3(0.88, 0.86, 0.82), accent, 0.14);
		vec3 floor_c = vec3(0.58, 0.45, 0.32);
		if (kind == 1) { wall = vec3(0.86, 0.85, 0.83); floor_c = vec3(0.80, 0.79, 0.76); }
		if (kind == 2) { wall = vec3(0.84, 0.86, 0.88); floor_c = vec3(0.46, 0.48, 0.50); }
		if (kind == 3) { wall = vec3(0.90, 0.91, 0.91); floor_c = vec3(0.86, 0.86, 0.84); }
		if (kind == 4) { wall = vec3(0.32, 0.22, 0.16); floor_c = vec3(0.22, 0.15, 0.10); }
		if (local_zh && kind != 4) { floor_c = vec3(0.80, 0.80, 0.78); }

		vec3 c = wall;
		float lamp = 0.0;
		if (on_ceil) {
			c = (kind == 4) ? vec3(0.18, 0.13, 0.10) : vec3(0.94, 0.94, 0.92);
			vec2 g = vec2(fract(hit.x / 1.3) - 0.5, fract(hit.z / 1.4) - 0.5);
			lamp = 1.0 - smoothstep(0.06, 0.13, length(g));
			if (kind == 3 || kind == 2 || local_zh) {
				// long LED tube panels (supermarket / pharmacy / Chinese local shop)
				lamp = (1.0 - smoothstep(0.05, 0.09, abs(g.x))) * (1.0 - smoothstep(0.32, 0.4, abs(g.y)));
			}
		} else if (on_floor) {
			float tile = step(0.04, fract(hit.x * (local_zh ? 1.25 : 1.6))) * step(0.04, fract(hit.z * (local_zh ? 1.25 : 1.6)));
			c = floor_c * mix(0.80, 1.0, tile);
		} else if (on_back) {
			if (kind == 0) {
				// Counter, menu light box with price lines, drinks fridge at the side
				if (hit.y < 0.75 && abs(hit.x - bay_w * 0.45) < 1.5) {
					c = mix(vec3(0.38, 0.26, 0.17), accent, 0.2) * (0.9 + 0.1 * step(0.5, fract(hit.x * 2.0)));
				} else if (hit.y > 1.55 && hit.y < 2.45 && abs(hit.x - bay_w * 0.45) < 1.35) {
					vec2 m = vec2(fract((hit.x - bay_w * 0.45 + 1.35) / 0.9), fract((hit.y - 1.55) / 0.18));
					float line = step(0.12, m.y) * step(m.y, 0.55) * step(0.08, m.x) * step(m.x, 0.7);
					c = mix(vec3(0.97, 0.95, 0.88), vec3(0.75, 0.10, 0.08), line * 0.8);
					lamp = 0.6;
				} else if (local_zh && hit.x > bay_w - 1.1 && hit.y < 2.0) {
					float is_it;
					vec3 f = shelf_face(hit.xy * vec2(1.0, 1.15), bay_id + 5.0, vec3(0.3, 0.5, 0.8), is_it);
					c = mix(f, vec3(0.9, 0.95, 1.0), 0.25); // drinks fridge behind glass
					lamp = 0.5;
				} else {
					float tile = step(0.03, fract(hit.x / 0.3)) * step(0.03, fract(hit.y / 0.3));
					c = local_zh ? vec3(0.93, 0.93, 0.92) * mix(0.86, 1.0, tile) : wall * 0.88;
				}
			} else if (kind == 1) {
				bool rail = abs(hit.y - 1.7) < 0.025;
				float gx = fract(hit.x / 0.13);
				bool garment = hit.y > 0.72 && hit.y < 1.68 - 0.18 * hash21(vec2(floor(hit.x / 0.13), bay_id)) && gx > 0.18;
				vec3 cloth = product_col(vec2(floor(hit.x / 0.52), bay_id + 3.0), accent) * 0.85;
				bool cubby = hit.y > 1.85 && hit.y < 2.7 && fract(hit.x / 0.7) > 0.08 && fract((hit.y - 1.85) / 0.42) > 0.12;
				c = rail ? vec3(0.32) : (garment ? cloth * (0.9 + 0.1 * gx) : (cubby ? product_col(vec2(floor(hit.x / 0.7), floor(hit.y / 0.42)), accent) * 0.9 : wall));
			} else if (kind == 3) {
				// Back wall: lit drinks / dairy fridges (convenience) or tall shelving (pharmacy)
				float is_it;
				vec3 f = shelf_face(hit.xy, bay_id, accent, is_it);
				if (hit.y < 2.15) {
					bool door_frame = fract(hit.x / 0.75) < 0.05 && local_zh;
					c = door_frame ? vec3(0.2) : mix(f, vec3(0.92, 0.96, 1.0), local_zh ? 0.18 : 0.0);
					lamp = local_zh ? 0.35 : 0.0;
				} else {
					c = wall;
				}
			} else if (kind == 4) {
				bool bottles = hit.y > 0.9 && hit.y < 2.0 && fract(hit.x / 0.12) > 0.4;
				vec3 merch = product_col(vec2(floor(hit.x / 0.12), floor(hit.y / 0.4)), accent);
				c = bottles ? mix(vec3(0.5, 0.35, 0.15), merch, 0.4) * 1.3 : wall;
			} else {
				// Bank / office: service counter with glass screens, queue number display
				if (hit.y < 1.05) c = vec3(0.50, 0.48, 0.46) * (0.92 + 0.08 * step(0.5, fract(hit.x / 1.3)));
				else if (hit.y < 1.75) c = mix(wall, vec3(0.75, 0.82, 0.88), 0.4);
				else if (hit.y > 2.1 && hit.y < 2.45 && abs(hit.x - bay_w * 0.5) < 0.9) {
					vec2 dgt = fract(vec2(hit.x * 4.0, (hit.y - 2.1) * 3.0));
					c = vec3(0.05);
					lamp = step(0.2, dgt.x) * step(dgt.x, 0.8) * step(0.2, dgt.y) * step(dgt.y, 0.8) * 0.9;
					c += vec3(0.9, 0.15, 0.08) * lamp;
				} else c = wall * 0.92;
			}
		} else {
			// Side walls: shelving / racks along the walls
			if (kind == 3 || (kind == 1 && local_zh)) {
				float is_it;
				vec3 f = shelf_face(vec2(hit.z, hit.y), bay_id + 11.0, accent, is_it);
				c = hit.y < 1.95 ? f : wall;
			} else if (kind == 1) {
				float fixture = step(0.9, hit.y) * step(hit.y, 1.9) * step(0.5, fract(hit.z / 0.9));
				c = mix(wall * 0.88, product_col(vec2(floor(hit.z / 0.9), bay_id), accent), fixture * 0.7);
			} else if (kind == 0 && local_zh) {
				float tile = step(0.03, fract(hit.z / 0.3)) * step(0.03, fract(hit.y / 0.3));
				c = vec3(0.93, 0.93, 0.92) * mix(0.86, 1.0, tile);
			} else {
				c = wall * 0.9;
			}
		}

		// Free-standing fixtures between the glass and the back wall (nearest first)
		if (kind == 3) {
			// two shelving gondolas parallel to the window, with an aisle gap at alternate ends
			for (int gi = 0; gi < 2; gi++) {
				float zg = 1.6 + float(gi) * 1.5;
				float t_g = zg / r.z;
				if (t_g < t) {
					vec3 gp = vec3(p0, 0.0) + r * t_g;
					float gap0 = (gi == 0) ? 0.0 : bay_w - 0.95;
					bool in_gap = gp.x > gap0 && gp.x < gap0 + 0.95;
					if (!in_gap && gp.y < 1.55 && gp.y > -0.5) {
						float is_it;
						c = shelf_face(gp.xy + vec2(0.0, 0.5), bay_id * 5.0 + float(gi), accent, is_it);
						if (gp.y > 1.48) c = vec3(0.92);
						t = t_g;
						break;
					}
				}
			}
		} else if (kind == 0 || kind == 4) {
			// Tables (horizontal tops seen from above) with chairs / stools; Chinese local eateries: light tables
			// and red plastic stools. Two rows of tables, offset per row.
			float tbl_h = 0.30; // table top above the window sill line (sill 0.44 m above the floor)
			for (int ti = 0; ti < 2; ti++) {
				float zt = 1.4 + float(ti) * 1.9;
				// table top: plane y = tbl_h
				if (r.y < -0.02) {
					float t_top = (tbl_h - p0.y) / r.y;
					if (t_top > 0.0 && t_top < t) {
						vec3 hp = vec3(p0, 0.0) + r * t_top;
						float cx = fract(hp.x / 1.6 + float(ti) * 0.5) - 0.5;
						if (abs(cx) < 0.40 && abs(hp.z - zt) < 0.38) {
							c = local_zh ? vec3(0.88, 0.86, 0.82) : vec3(0.46, 0.33, 0.22);
							t = t_top;
						}
					}
				}
				// table front edge, leg and the stools / chair backs: vertical plane in front of the table
				float t_f = (zt - 0.38) / r.z;
				if (t_f < t) {
					vec3 fp = vec3(p0, 0.0) + r * t_f;
					float cx2 = fract(fp.x / 1.6 + float(ti) * 0.5) - 0.5;
					if (abs(cx2) < 0.40 && fp.y < tbl_h && fp.y > tbl_h - 0.06) {
						c = local_zh ? vec3(0.78, 0.76, 0.72) : vec3(0.36, 0.25, 0.16);
						t = t_f;
					} else if (abs(cx2) < 0.035 && fp.y < tbl_h && fp.y > -0.5) {
						c = vec3(0.18);
						t = t_f;
					} else if (abs(abs(cx2) - 0.30) < 0.10 && fp.y < (local_zh ? -0.02 : 0.40) && fp.y > -0.5) {
						c = local_zh ? vec3(0.80, 0.16, 0.14) : vec3(0.24, 0.17, 0.12);
						if (!local_zh && fp.y < 0.0) c *= 0.7;
						t = t_f;
					}
				}
			}
		} else if (kind == 1) {
			// mannequins and a display table near the window
			float t_fg = 1.0 / r.z;
			if (t_fg < t) {
				vec3 fg = vec3(p0, 0.0) + r * t_fg;
				float hsh2 = hash21(vec2(bay_id, 7.0));
				float mx = abs(fract(fg.x / 1.6 + hsh2) - 0.5);
				if (fg.y < 1.3 + hsh2 * 0.2 && fg.y > -0.4 && mx < 0.10 - 0.04 * step(1.05 + hsh2 * 0.2, fg.y)) {
					c = product_col(vec2(bay_id, 9.0), accent) * 0.9;
					if (fg.y > 1.05 + hsh2 * 0.2) c = vec3(0.92, 0.90, 0.86);
					t = t_fg;
				}
			}
		}

		float ao = mix(1.0, 0.6, clamp(t * r.z / depth, 0.0, 1.0));
		float lit = (kind == 4) ? 0.55 : 1.0;
		vec3 warm = (kind == 2 || kind == 3 || local_zh) ? vec3(0.95, 0.97, 1.0) : vec3(1.0, 0.86, 0.66);
		vec3 interior = c * ao * lit;

		// --- Things on the glass itself ---
		float decal = 0.0;
		vec3 decal_c = vec3(0.0);
		if (posters && !is_door) {
			// one or two posters in the lower part of the window, a promo sticker band
			vec2 pp = vec2(fract(v_uv.x / bay_w) * bay_w, v_uv.y);
			float px0 = 0.25 + 0.6 * shop_h;
			if (pp.x > px0 && pp.x < px0 + 0.62 && pp.y > 0.35 && pp.y < 1.20) {
				vec2 q = vec2((pp.x - px0) / 0.62, (pp.y - 0.35) / 0.85);
				decal_c = mix(accent * 1.1, vec3(0.97, 0.95, 0.9), step(0.62, q.y));
				decal_c = mix(decal_c, vec3(0.85, 0.12, 0.1), step(0.1, q.x) * step(q.x, 0.9) * step(0.70, q.y) * step(q.y, 0.85));
				decal = 1.0;
			}
			if (pp.x > px0 + 0.85 && pp.x < px0 + 1.25 && pp.y > 1.05 && pp.y < 1.32) {
				decal_c = vec3(0.98, 0.84, 0.10); // "促销" sticker
				decal = 1.0;
			}
		}
		if (is_door) {
			// door sign (营业中) and an opening-hours sticker
			vec2 dp = vec2(fract(v_uv.x / bay_w) * bay_w, v_uv.y);
			float dx = fract(v_uv.x) ;
			if (abs(v_uv.y - 1.05) < 0.10 && abs(fract(v_uv.x * 0.5) - 0.5) < 0.14) {
				decal_c = vec3(0.82, 0.08, 0.08);
				decal = 1.0;
			}
			if (local_zh && kind != 2) {
				// clear PVC strip curtain: overlapping vertical strips, slightly blue and less transparent
				float strip = fract(v_uv.x / 0.20);
				float edge = smoothstep(0.0, 0.06, strip) * (1.0 - smoothstep(0.90, 1.0, strip));
				interior = mix(interior, vec3(0.62, 0.72, 0.76), 0.14 + 0.22 * (1.0 - edge));
			}
		}

		float refl = clamp(0.06 + fres * 0.72, 0.0, 0.85) * (1.0 - night_factor * 0.7);
		// Far LOD: flat, lit-looking glass
		float far = smoothstep(90.0, 150.0, dist);
		interior = mix(interior, accent * 0.25 + vec3(0.40, 0.37, 0.32), far);

		vec3 alb = mix(interior * 0.70, sky_tint * 0.62, refl);
		vec3 em = (interior * 0.30 + warm * lamp * 0.8) * (0.50 + night_factor * 0.60) * (1.0 - refl);
		if (decal > 0.5) {
			alb = decal_c * 0.85;
			em = decal_c * (0.10 + night_factor * 0.25);
		}
		ALBEDO = alb;
		EMISSION = em;
		ROUGHNESS = decal > 0.5 ? 0.6 : 0.06;
		METALLIC = 0.0;
		SPECULAR = decal > 0.5 ? 0.3 : 0.6;
	}
}
