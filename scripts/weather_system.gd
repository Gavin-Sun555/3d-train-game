class_name WeatherSystem
extends Node3D

enum WeatherType {
	SUNNY = 0,
	CLOUDY = 1,
	RAINY = 2,
}

const WEATHER_NAMES_ZH := ["晴天", "阴天", "雨天"]
const WEATHER_NAMES_EN := ["Sunny", "Cloudy", "Rainy"]
const WEATHER_ICONS := ["☀", "☁", "🌧"]

const RAIN_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 rain_color : source_color = vec4(0.80, 0.87, 0.96, 0.36);
uniform float near_fade_start = 2.4;
uniform float near_fade_end = 4.8;
uniform float far_fade_start = 34.0;
uniform float far_fade_end = 58.0;
uniform float wind_slant = 0.08;

varying float v_dist_alpha;

void vertex() {
	vec3 p_world = MODEL_MATRIX[3].xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam_pos - p_world;
	float dist = length(to_cam);

	float near_a = smoothstep(near_fade_start, near_fade_end, dist);
	float far_a = 1.0 - smoothstep(far_fade_start, far_fade_end, dist);
	v_dist_alpha = near_a * far_a;

	vec3 up_dir = normalize(vec3(wind_slant, 1.0, wind_slant * 0.6));
	vec3 horiz_to_cam = vec3(to_cam.x, 0.0, to_cam.z);
	float hl = length(horiz_to_cam);
	vec3 fwd = (hl > 0.001) ? (horiz_to_cam / hl) : vec3(0.0, 0.0, 1.0);
	vec3 right_dir = normalize(cross(up_dir, fwd));

	vec3 world_pos = p_world + right_dir * VERTEX.x + up_dir * VERTEX.y;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world_pos, 1.0));
}

void fragment() {
	float sx = sin(clamp(UV.x, 0.0, 1.0) * 3.14159265);
	float sy = sin(clamp(UV.y, 0.0, 1.0) * 3.14159265);
	float streak = sx * sy * sy;
	ALBEDO = rain_color.rgb;
	ALPHA = rain_color.a * streak * v_dist_alpha;
}
"""

var weather_mode: int = WeatherType.SUNNY
var _rain_particles: GPUParticles3D
var _rain_mat: ShaderMaterial


static func weather_name(mode: int) -> String:
	var m := clampi(mode, 0, 2)
	return WEATHER_NAMES_EN[m] if L10n.is_en() else WEATHER_NAMES_ZH[m]


static func weather_button_label(mode: int) -> String:
	var m := clampi(mode, 0, 2)
	return "%s %s" % [WEATHER_ICONS[m], weather_name(m)]


func _ready() -> void:
	_build_rain_particles()
	set_weather(weather_mode)


func _build_rain_particles() -> void:
	_rain_particles = GPUParticles3D.new()
	_rain_particles.name = "RainParticles"
	_rain_particles.amount = 1800
	_rain_particles.lifetime = 1.45
	_rain_particles.preprocess = 1.45
	_rain_particles.local_coords = false
	_rain_particles.fixed_fps = 0
	_rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_particles.visibility_aabb = AABB(Vector3(-85.0, -65.0, -85.0), Vector3(170.0, 130.0, 170.0))

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(34.0, 4.0, 34.0)
	pmat.direction = Vector3(-0.08, -1.0, -0.05)
	pmat.spread = 2.5
	pmat.initial_velocity_min = 24.0
	pmat.initial_velocity_max = 31.0
	pmat.gravity = Vector3(0.0, -8.0, 0.0)
	_rain_particles.process_material = pmat

	var sh := Shader.new()
	sh.code = RAIN_SHADER_CODE
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = sh
	_rain_mat.set_shader_parameter("rain_color", Color(0.80, 0.87, 0.96, 0.36))

	var qm := QuadMesh.new()
	qm.size = Vector2(0.036, 1.05)
	qm.material = _rain_mat
	_rain_particles.draw_pass_1 = qm

	_rain_particles.emitting = false
	_rain_particles.visible = false
	add_child(_rain_particles)


func set_weather(mode: int) -> void:
	weather_mode = clampi(mode, 0, 2)
	if _rain_particles == null:
		return
	var is_rain := (weather_mode == WeatherType.RAINY)
	_rain_particles.visible = is_rain
	_rain_particles.emitting = is_rain
	if is_rain:
		_rain_particles.restart()


func set_paused(paused: bool) -> void:
	if _rain_particles != null:
		_rain_particles.speed_scale = 0.0 if paused else 1.0


func update_lighting(night_factor: float) -> void:
	if _rain_mat == null:
		return
	# Daytime rain: crisp silver-blue streaks; Nighttime rain: softly lit cool steel-blue streaks
	var day_col := Color(0.82, 0.88, 0.96, 0.38)
	var night_col := Color(0.56, 0.66, 0.82, 0.34)
	_rain_mat.set_shader_parameter("rain_color", day_col.lerp(night_col, clampf(night_factor, 0.0, 1.0)))


func update_camera_follow(cam: Camera3D, is_interior_view: bool) -> void:
	if _rain_particles == null or not _rain_particles.visible or cam == null:
		return
	var cam_pos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var fwd_xz := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_xz.length_squared() > 0.001:
		fwd_xz = fwd_xz.normalized()
	else:
		fwd_xz = Vector3(0.0, 0.0, -1.0)
	# Center emission slightly ahead of camera so rain fills the windshield & foreground
	var lead := 12.0 if cam_pos.y < 35.0 else 6.0
	var height_above := 22.0 if cam_pos.y < 45.0 else 16.0
	_rain_particles.global_position = Vector3(
		cam_pos.x + fwd_xz.x * lead,
		cam_pos.y + height_above,
		cam_pos.z + fwd_xz.z * lead
	)
	if _rain_mat != null:
		# Larger near-camera cutout inside tram cab/interior so drops stay outside the windshield
		_rain_mat.set_shader_parameter("near_fade_start", 3.0 if is_interior_view else 1.4)
		_rain_mat.set_shader_parameter("near_fade_end", 5.4 if is_interior_view else 3.2)
