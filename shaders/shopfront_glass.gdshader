shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Shop window glazing with a parallax-mapped, lit shop interior behind it.
// UV.x = metres along the window, UV.y = metres above window sill.
// COLOR.rgb = interior accent (brand / merchandise colour), COLOR.a = interior kind / 255:
//   0 cafe/restaurant  1 fashion/retail  2 bank/office  3 grocery/pharmacy  4 bar (dim, warm)

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

void fragment() {
	int kind = int(round(v_col.a * 255.0));
	vec3 accent = v_col.rgb;
	vec3 n_h = normalize(vec3(v_world_nrm.x, 0.0, v_world_nrm.z) + vec3(1e-5, 0.0, 0.0));
	vec3 t_h = vec3(n_h.z, 0.0, -n_h.x);
	vec3 to_frag = v_world_pos - CAMERA_POSITION_WORLD;
	float dist = length(to_frag);
	vec3 vd = to_frag / max(dist, 1e-4);
	vec3 r = vec3(dot(vd, t_h), vd.y, max(dot(vd, -n_h), 0.03));

	// Room: 4m bays wide, 3.2m tall (from sill), 5m deep
	float bay_w = 4.0;
	float room_h = 3.0;
	float depth = 5.0;
	vec2 p0 = vec2(fract(v_uv.x / bay_w) * bay_w, v_uv.y);
	float bay_id = floor(v_uv.x / bay_w);
	float tx = ((r.x > 0.0 ? bay_w : 0.0) - p0.x) / (abs(r.x) < 1e-4 ? 1e-4 : r.x);
	float ty = ((r.y > 0.0 ? room_h : -0.5) - p0.y) / (abs(r.y) < 1e-4 ? 1e-4 : r.y);
	float tz = depth / r.z;
	float t = min(min(tx, ty), tz);
	vec3 hit = vec3(p0, 0.0) + r * t;
	bool on_ceil = abs(t - ty) < 1e-3 && r.y > 0.0;
	bool on_floor = abs(t - ty) < 1e-3 && r.y < 0.0;
	bool on_back = abs(t - tz) < 1e-3;

	vec3 wall = mix(vec3(0.86, 0.84, 0.80), accent, 0.18);
	vec3 floor_c = vec3(0.55, 0.42, 0.30);
	if (kind == 1) { wall = vec3(0.80, 0.79, 0.77); floor_c = vec3(0.78, 0.77, 0.75); }
	if (kind == 2) { wall = vec3(0.80, 0.82, 0.84); floor_c = vec3(0.42, 0.44, 0.47); }
	if (kind == 3) { wall = vec3(0.84, 0.85, 0.85); floor_c = vec3(0.82, 0.82, 0.80); }
	if (kind == 4) { wall = vec3(0.32, 0.22, 0.16); floor_c = vec3(0.22, 0.15, 0.10); }

	vec3 c = wall;
	float lamp = 0.0;
	if (on_ceil) {
		c = (kind == 4) ? vec3(0.18, 0.13, 0.10) : vec3(0.92, 0.92, 0.90);
		vec2 g = vec2(fract(hit.x / 1.3) - 0.5, fract(hit.z / 1.4) - 0.5);
		lamp = 1.0 - smoothstep(0.06, 0.13, length(g));
		if (kind == 3 || kind == 2) {
			lamp = (1.0 - smoothstep(0.05, 0.09, abs(g.x))) * (1.0 - smoothstep(0.32, 0.4, abs(g.y)));
		}
	} else if (on_floor) {
		float tile = step(0.04, fract(hit.x * 1.6)) * step(0.04, fract(hit.z * 1.6));
		c = floor_c * mix(0.82, 1.0, tile);
	} else if (on_back) {
		// Back wall: shelving / racks / counter with merchandise colours
		float shelf_row = floor(hit.y / 0.55);
		float item = floor(hit.x / 0.32);
		float hsh = hash21(vec2(item + bay_id * 13.0, shelf_row));
		vec3 merch = mix(accent, vec3(hsh, fract(hsh * 7.1), fract(hsh * 3.7)), 0.55);
		bool shelf = fract(hit.y / 0.55) < 0.08;
		if (kind == 0) {
			// counter + menu board + pendant glow
			if (hit.y < 0.6) c = vec3(0.35, 0.24, 0.16);
			else if (hit.y > 1.6 && hit.y < 2.4 && abs(hit.x - bay_w * 0.5) < 1.2) c = mix(vec3(0.08), accent, 0.35) + 0.15;
			else c = wall * 0.85;
		} else if (kind == 1) {
			bool rail = abs(hit.y - 1.7) < 0.03;
			bool garment = hit.y > 0.75 && hit.y < 1.68 && fract(hit.x / 0.16) > 0.25;
			c = rail ? vec3(0.3) : (garment ? merch : wall);
		} else if (kind == 3) {
			c = (hit.y < 2.1) ? (shelf ? vec3(0.85) : merch * 0.95) : wall;
		} else if (kind == 4) {
			bool bottles = hit.y > 0.9 && hit.y < 2.0 && fract(hit.x / 0.12) > 0.4;
			c = bottles ? mix(vec3(0.5, 0.35, 0.15), merch, 0.4) * 1.3 : wall;
		} else {
			c = (hit.y < 1.0) ? vec3(0.42, 0.40, 0.38) : wall * 0.92;
		}
	} else {
		// Side walls: display fixtures at mid height
		float fixture = step(0.9, hit.y) * step(hit.y, 1.9) * step(0.5, fract(hit.z / 0.9));
		c = mix(wall * 0.88, accent * 0.8, fixture * ((kind == 1 || kind == 3) ? 0.7 : 0.15));
	}
	// Foreground: display table / mannequins silhouettes near the glass
	float fg_d = 1.1;
	float t_fg = fg_d / r.z;
	vec3 fg = vec3(p0, 0.0) + r * t_fg;
	if (t_fg < t && fg.x > 0.3 && fg.x < bay_w - 0.3) {
		float hsh2 = hash21(vec2(bay_id, 7.0));
		if (kind == 1 && fg.y < 1.25 + hsh2 * 0.25 && abs(fract(fg.x / 1.6) - 0.5) < 0.09) {
			c = mix(accent, vec3(0.9), 0.3) * 0.8; // mannequin
			t = t_fg;
		} else if ((kind == 0 || kind == 4) && fg.y < 0.75 && fg.y > -0.4 && abs(fract(fg.x / 1.3) - 0.5) < 0.28) {
			c = (fg.y > 0.68) ? vec3(0.42, 0.30, 0.20) : vec3(0.15, 0.13, 0.12); // cafe tables
			t = t_fg;
		}
	}
	float ao = mix(1.0, 0.55, clamp(t * r.z / depth, 0.0, 1.0));
	float lit = (kind == 4) ? 0.55 : 1.0;
	vec3 warm = (kind == 2 || kind == 3) ? vec3(0.95, 0.97, 1.0) : vec3(1.0, 0.86, 0.66);
	vec3 interior = c * ao * lit;

	float ndv = clamp(dot(n_h, -vd), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);
	float refl = clamp(0.12 + fres * 0.7, 0.0, 0.85) * (1.0 - night_factor * 0.7);
	// Far LOD: flat, lit-looking glass
	float far = smoothstep(90.0, 150.0, dist);
	interior = mix(interior, accent * 0.25 + vec3(0.32, 0.29, 0.25), far);

	ALBEDO = mix(interior * 0.45, sky_tint * 0.7, refl);
	// Shops are lit inside day and night (interior light reads through glass)
	EMISSION = (interior * 0.30 + warm * lamp * 0.9) * (0.40 + night_factor * 0.55) * (1.0 - refl);
	ROUGHNESS = 0.06;
	METALLIC = 0.2;
	SPECULAR = 0.8;
}
