uniform vec3 bb_min;
uniform vec3 bb_max;
uniform vec3 light_direction;
uniform vec3 light_color: source_color;
uniform float falloff_light = 1.0;
uniform float falloff_color = 1.0;
uniform float darkness_threshold = 0.1;
uniform float cloud_threshold: hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float cloud_threshold_delta: hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float cloud_density;
uniform float cloud_scale = 1.0;
uniform float fine_scale : hint_range(0.0, 100.0, 1.0) = 4.0;
uniform float fine_blend : hint_range(0.0, 1.0, 0.01) = 0.2;

uniform float scattering_forward : hint_range(0.0, 1.0, 0.1);
uniform float scattering_backward : hint_range(0.0, 1.0, 0.1);
uniform float scattering_omnidirectional : hint_range(0.0, 1.0, 0.1);
uniform float scattering_directional : hint_range(0.0, 1.0, 0.1);
uniform float scattering_direction_blend : hint_range(0.0, 1.0, 0.1);

uniform sampler3D density_texture : repeat_enable;
uniform sampler3D fine_density_texture : repeat_enable;
uniform sampler2D height_texture : repeat_disable;
uniform sampler2D cloud_coverage : repeat_enable;
uniform sampler2D blue_noise : filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D depth_texture : hint_depth_texture;