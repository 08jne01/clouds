shader_type spatial;
render_mode unshaded;
render_mode cull_disabled;
uniform sampler3D density_texture : repeat_enable;
uniform sampler3D fine_density_texture : repeat_enable;
uniform sampler2D height_texture : repeat_disable;
uniform sampler2D cloud_coverage : repeat_enable;
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

uniform sampler2D blue_noise : filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture;

//https://jcgt.org/published/0007/03/04/
//https://github.com/SebLague/Clouds/blob/master/Assets/Scripts/Clouds/Shaders/Clouds.shader
vec2 IntersectBox(vec3 box_min, vec3 box_max, vec3 ray_origin, vec3 inverse_ray) 
{
	vec3 t0 = (box_min - ray_origin) * inverse_ray;
	vec3 t1 = (box_max - ray_origin) * inverse_ray;
	vec3 tmin = min(t0,t1);
	vec3 tmax = max(t0,t1); 
	
	float tnear = max(tmin.x,max(tmin.y,tmin.z)); // near intersection
	float tfar = min(tmax.x,min(tmax.y,tmax.z)); // far intersection
	
	float distance_to_box = max(0, tnear);
	float distance_inside_box = max(0, tfar - distance_to_box); // tfar > tnear actually intersects, so 0 is no intersection
	return vec2(distance_to_box, distance_inside_box);
}

void vertex() {
	// Called for every vertex the material is visible on.
}

float SampleDensityTexture(sampler3D sampler, vec3 uvw)
{
	vec4 layer_density = texture(sampler, uvw);
	float density = 
		layer_density.w * 0.5 + 
		layer_density.z * 0.25 +
		layer_density.y * 0.125 +
		layer_density.x * 0.0625;
		
	density /= 0.9375;
	return density;
}

float Density(vec3 position)
{
	position += TIME * vec3(20.0,0.0,0.0);
	
	vec3 delta = bb_max - bb_min;
	float max_dim = cloud_scale * delta.y; //max(delta.x, max(delta.y,delta.z));
	
	vec3 uvw = (position - bb_min) / vec3(max_dim);
	vec3 uvw_world = position / vec3(max_dim);
	
	float coverage = texture(cloud_coverage, uvw_world.xz).b;
	
	float course_density = SampleDensityTexture(density_texture, uvw_world);
	float fine_density = SampleDensityTexture(fine_density_texture, uvw_world * fine_scale);
	
	float density = course_density * (1.0 - fine_blend) + fine_density * fine_blend;
	density *= texture(height_texture, vec2(uvw.y, 0.0)).r;
	//density *= coverage;
	
	float cloud_t = clamp((density - cloud_threshold) / cloud_threshold_delta, 0.0, 1.0);
	
	return mix(0.0, cloud_density, cloud_t);
	
	//return step(density, cloud_threshold) * cloud_density;
}

float BeerPowder(float optical_depth)
{
	return (1.0 - exp(-optical_depth * 2.0)) * exp(-optical_depth);
}

float Beer(float optical_depth)
{
	return exp(-optical_depth);
}

float LightContribution(vec3 ray_origin)
{
	vec2 intersection = IntersectBox(bb_min, bb_max, ray_origin, 1.0 / light_direction);
	float depth = intersection.y;
	
	const int n_samples = 16;
	float dt = depth / float(n_samples-1);
	
	vec3 ray_step = light_direction * dt;
	
	float density = 0.0;
	
	for ( int i = 0; i < n_samples; i++ )
	{
		density += Density(ray_origin);//exp(-falloff * );
		ray_origin += ray_step;
	}
	float optical_depth = falloff_light * density * dt;
	
	float transmittance = BeerPowder(optical_depth);
	
	return transmittance * (1.0 - darkness_threshold) + darkness_threshold;
}

//https://en.wikipedia.org/wiki/Henyey%E2%80%93Greenstein_phase_function
// g [-1,1]
float HenyeyGreenSteinPhase(float cosa, float g) {
    const float one_by_4pi = 1.0 / (4.0 * 3.14159);
	
	float g2 = g*g;
	
	float num = 1.0 - g2;
	float denom = 1.0 + g2 - 2.0 * g * cosa;
	
    return num / pow(denom, 1.5);
}

float Phase(float cosa) 
{
	float forward = HenyeyGreenSteinPhase(cosa, scattering_forward);
	float backward = HenyeyGreenSteinPhase(cosa, -scattering_backward);
    float directional = forward * ( 1.0 - scattering_direction_blend ) + backward * scattering_direction_blend;
	return scattering_omnidirectional + directional * scattering_directional;
}

vec4 RayMarch(vec3 ray_origin, vec3 ray_direction, float depth, vec2 screen_uv)
{
	// environment colour
	vec3 color = texture(screen_texture, screen_uv).rgb;// vec3(1.0);//vec3(0.0);
	
	const int n_samples = 128;
	
	float dt = depth / float(n_samples-1);
	
	float noise_offset = dt * texture(blue_noise, fract(4.0 * screen_uv * TIME)).r;
	
	ray_origin += ray_direction * noise_offset;
	
	vec3 ray_step = ray_direction * dt;
	
	
	float light_energy = 0.0;
	
	float cosa = dot(ray_direction, light_direction);
	float phase = Phase(cosa);// max(, 0.0);
	
	float transmittance = 1.0;
	
	for ( int i = 0; i < n_samples; i++ )
	{
		//float t = -a / z + b;
		float density = Density(ray_origin);
		
		if ( density > 0.0 )
		{
			float light_transmittance = LightContribution(ray_origin);
			
			//color = light_color;// * 0.1 * light_depth;// LightContribution(ray_origin, light_depth);
			light_energy += light_transmittance * transmittance * density;
			transmittance *= exp(-falloff_color * density * dt);
			if ( transmittance < 0.01 )
			{
				transmittance = 0.0;
				break;
			}
			//break;
		}
		
		
		
		//z += dt;
		ray_origin += ray_step;
	}
	
	light_energy *= phase * dt * 1.0;
	
	//return vec4(light_color * light_energy,1.0 - transmittance);
	//return vec4(light_energy, 0.0, 0.0, 1.0);
	return vec4(color * transmittance + light_color * light_energy ,1.0 - transmittance);
}

void fragment() {
	// Called for every pixel the material is visible on.
	vec3 ray_origin = INV_VIEW_MATRIX[3].xyz;
	
	vec2 screen_uv = FRAGCOORD.xy / VIEWPORT_SIZE.xy;
	//https://godotshaders.com/shader/volumetric-raymarched-animated-clouds-v2/
	vec4 clip_pos = vec4(screen_uv * 2.0 - 1.0, FRAGCOORD.z, 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * clip_pos;
	vec3 ray_direction_local = normalize(view_pos.xyz / view_pos.w);
	vec3 ray_direction = mat3(INV_VIEW_MATRIX) * ray_direction_local;
	
	vec3 inverse_ray_direction = 1.0 / ray_direction;
	
	vec2 intersection = IntersectBox(bb_min, bb_max, ray_origin, inverse_ray_direction);

	//if ( intersection.x <= 0.0 )
	//{
		//discard;
	//}
	
	float t = intersection.x;
	float depth = intersection.y;

	//intersection = IntersectBox(bb_min, bb_max, ray_origin + ray_direction * (t + 1.0), inverse_ray_direction);

	vec4 light_result = RayMarch(
		ray_origin + ray_direction * (t - 0.01), 
		ray_direction, 
		depth, 
		screen_uv
	); //vec3(value);
	ALBEDO = light_result.rgb;//Density(ray_origin + ray_direction * t) * vec3(1.0);// light_result.rgb;
	//ALPHA = clamp(light_result.a, 0.0, 1.0);
	
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
