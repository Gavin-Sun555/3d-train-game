shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Downtown Seattle sidewalk, laid out along the kerb:
//   UV.x = metres along the street, UV.y = metres back from the kerb.
//   0 .. 0.95m : brick-paver furniture zone (running bond, warm red-brown, worn)
//   beyond     : 5ft (1.52m) scored concrete panels with tooled edges, control joints, stains
// COLOR.r = 1 marks kerb-ramp tactile warning pads (yellow truncated domes).

varying vec2 v_uv;
varying vec3 v_world;
varying float v_tactile;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_uv = UV;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_tactile = COLOR.r;
}

void fragment() {
	float u = v_uv.x;
	float v = v_uv.y;
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);
	// Pixel footprint in metres: fade any pattern finer than ~2 pixels (prevents shimmer while moving)
	float fw = max(length(dFdx(v_world.xz)), length(dFdy(v_world.xz)));
	float detail = 1.0 - smoothstep(60.0, 140.0, cam_d);
	float aa_fine = 1.0 - smoothstep(0.004, 0.012, fw);   // broom finish, domes, gum (cm scale)
	float aa_brick = 1.0 - smoothstep(0.018, 0.045, fw);  // 10cm brick courses
	float aa_panel = 1.0 - smoothstep(0.08, 0.25, fw);    // 1.5m panel joints
	vec3 col;
	float rough = 0.86;
	if (v_tactile > 0.5) {
		vec2 g = fract(v_world.xz / 0.06) - 0.5;
		float dome = 1.0 - smoothstep(0.18, 0.26, length(g));
		col = mix(vec3(0.84, 0.67, 0.14), mix(vec3(0.80, 0.62, 0.10), vec3(0.95, 0.80, 0.25), dome), aa_fine);
		rough = 0.7;
	} else if (v < 0.95) {
		// Brick pavers, running bond, laid lengthwise
		float row = floor(v / 0.105);
		float bx = (u + mod(row, 2.0) * 0.1) / 0.2;
		float id = hash21(vec2(floor(bx), row));
		vec3 brick = mix(vec3(0.46, 0.27, 0.21), vec3(0.56, 0.36, 0.27), id);
		brick = mix(vec3(0.50, 0.31, 0.24), brick * (0.88 + 0.16 * vnoise(vec2(u, v) * 9.0)), aa_brick);
		float jx = smoothstep(0.0, 0.05, fract(bx)) * smoothstep(1.0, 0.95, fract(bx));
		float jy = smoothstep(0.0, 0.08, fract(v / 0.105)) * smoothstep(1.0, 0.92, fract(v / 0.105));
		col = mix(mix(vec3(0.33, 0.31, 0.29), brick, jx * jy), brick * 0.93, 1.0 - aa_brick);
		rough = 0.9;
	} else {
		float vv = v - 0.95;
		vec2 pc = vec2(u, vv) / 1.52;
		vec2 pid = floor(pc);
		vec2 pf = fract(pc);
		float tone = hash21(pid);
		vec3 conc = mix(vec3(0.56, 0.55, 0.52), vec3(0.64, 0.63, 0.60), tone);
		// fine broom finish across the walk + aggregate speckle
		conc *= 0.95 + 0.05 * sin(vv * 140.0 + vnoise(vec2(u, vv) * 6.0) * 4.0) * aa_fine;
		conc *= 0.98 + (0.12 * vnoise(vec2(u, vv) * 22.0) - 0.06) * aa_fine;
		// tooled panel edges (smooth border band) + saw-cut joint
		float edge = min(min(pf.x, 1.0 - pf.x), min(pf.y, 1.0 - pf.y)) * 1.52;
		conc = mix(conc * 1.04, conc, mix(1.0, smoothstep(0.03, 0.06, edge), aa_brick));
		float jw = max(0.012, fw * 1.2);
		float joint = smoothstep(jw * 0.3, jw, edge);
		// every 4th panel is a wider expansion joint
		if (mod(pid.x, 4.0) == 0.0 && pf.x * 1.52 < 0.02) joint = 0.0;
		conc = mix(conc * 0.97, mix(vec3(0.24, 0.23, 0.22), conc, joint), aa_panel);
		// weathering: darker near the kerb (run-off), gum spots, occasional patched panel
		conc *= mix(0.88, 1.0, smoothstep(0.0, 1.2, vv));
		float gum = step(0.985, hash21(floor(v_world.xz * 7.0))) * aa_fine;
		conc = mix(conc, vec3(0.30, 0.29, 0.28), gum * 0.7);
		if (hash21(pid * 3.1 + 7.0) > 0.93) conc *= vec3(0.93, 0.92, 0.90);
		float stain = vnoise(v_world.xz * 0.35);
		conc *= 0.90 + 0.12 * stain;
		col = conc;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
