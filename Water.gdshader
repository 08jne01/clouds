shader_type spatial;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow_water_color : source_color;
uniform vec3 deep_water_color : source_color;

uniform vec2 speed_0;
uniform vec2 speed_1;

uniform sampler2D waves : filter_linear; 
uniform sampler2D waves1 : filter_linear; 

uniform float falloff = 1.0;
uniform float wave_height = 5.0;
varying vec3 surface;


void vertex() {
	// Called for every vertex the material is visible on.
	surface = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float GetHeight(vec3 position, float scale)
{
	
	vec2 offset_0 = TIME * speed_0;
	vec2 offset_1 = TIME * speed_1;
	
	float height = texture(waves, scale * (position.xz + offset_0)).r;
	height += texture(waves1, scale * (position.xz + offset_1)).r;

	return wave_height * height;
}

vec3 Normal(vec3 position, float scale)
{
	const float dt = 0.01;
	vec3 dx = vec3(dt, 0.0, 0.0);
	vec3 dz = vec3(0.0, 0.0, dt);
	
	vec3 p00 = position;
	vec3 p10 = position + dx;
	vec3 p01 = position + dz;
	
	p00.y = GetHeight(p00, scale);
	p10.y = GetHeight(p10, scale);
	p01.y = GetHeight(p01, scale);
	
	vec3 dpx = normalize(p10 - p00);
	vec3 dpz = normalize(p01 - p00);
	return -cross(dpx,dpz);
}

void fragment() 
{
	vec2 screen_uv = FRAGCOORD.xy / VIEWPORT_SIZE.xy;
	// Called for every pixel the material is visible on.
	
	float depth = texture(depth_texture,screen_uv).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world_pos = world.xyz / world.w;
	
	
	float water_depth = length(surface - world_pos);
	
	
	
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	
	NORMAL = (VIEW_MATRIX * vec4(Normal(surface,0.1), 0.0)).xyz;
	
	float optical_depth = exp(-falloff * water_depth);
	
	
	vec3 water_color = mix(deep_water_color, shallow_water_color, optical_depth);
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;
	ALBEDO = mix(water_color, screen_color, optical_depth);// rr;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
