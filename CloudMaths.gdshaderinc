#ifdef COMPUTE
#define LAYOUT(s,b,u) layout(s, b) u
#define UNIFORM(u) u
#define HINT(h)
#define DEFAULT(d)
#else
#define LAYOUT(s,b,u) u
#define UNIFORM(u) uniform u
#define HINT(h) : h
#define DEFAULT(d) = d
#endif

// Set 0 Reserved for Compute Data
LAYOUT(set = 0, binding = 2, uniform sampler2D depth_texture)        HINT(hint_depth_texture);

#ifdef COMPUTE
// Use a UBO for compute shader
layout(std430, set = 1, binding = 0) buffer CloudSettings
{
#endif
	UNIFORM(vec3 bb_min);
	UNIFORM(vec3 bb_max);
	UNIFORM(vec3 light_direction);
	UNIFORM(vec4 light_color)                   HINT(source_color);
	UNIFORM(float falloff_light)                DEFAULT(1.0);
	UNIFORM(float falloff_color)                DEFAULT(1.0);
	UNIFORM(float darkness_threshold)           DEFAULT(0.1);
	UNIFORM(float cloud_threshold)              HINT(hint_range(0.0, 1.0, 0.01))    DEFAULT(0.5);
	UNIFORM(float cloud_threshold_delta)        HINT(hint_range(0.0, 1.0, 0.01))    DEFAULT(0.1);
	UNIFORM(float cloud_density);
	UNIFORM(float cloud_scale)                  DEFAULT(1.0);
	UNIFORM(float fine_scale)                   HINT(hint_range(0.0, 100.0, 1.0))   DEFAULT(4.0);
	UNIFORM(float fine_blend)                   HINT(hint_range(0.0, 1.0, 0.01))    DEFAULT(0.2);
	
	UNIFORM(float scattering_forward)           HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float scattering_backward)          HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float scattering_omnidirectional)   HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float scattering_directional)       HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float scattering_direction_blend)   HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float padding0); // 31 floats
	UNIFORM(float padding1); // 32 floats
#ifdef COMPUTE
};
#endif

LAYOUT(set = 1, binding = 1, uniform sampler3D density_texture)      HINT(repeat_enable);
LAYOUT(set = 1, binding = 2, uniform sampler3D fine_density_texture) HINT(repeat_enable);
LAYOUT(set = 1, binding = 3, uniform sampler2D height_texture)       HINT(repeat_disable);
LAYOUT(set = 1, binding = 4, uniform sampler2D cloud_coverage)       HINT(repeat_enable);
LAYOUT(set = 1, binding = 5, uniform sampler2D blue_noise)           HINT(filter_nearest);

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

float SampleDensityTexture(vec4 layer_density)
{
	float density = 
		layer_density.w * 0.5 + 
		layer_density.z * 0.25 +
		layer_density.y * 0.125 +
		layer_density.x * 0.0625;
		
	density /= 0.9375;
	return density;
}

float Density(vec3 position, float time)
{
	position += time * vec3(20.0,0.0,0.0);
	
	vec3 delta = bb_max - bb_min;
	float max_dim = cloud_scale * delta.y; //max(delta.x, max(delta.y,delta.z));
	
	vec3 uvw = (position - bb_min) / vec3(delta);
	vec3 uvw_world = position / vec3(max_dim);
	
	float coverage = texture(cloud_coverage, uvw_world.xz).b;
	
	float course_density = SampleDensityTexture(texture(density_texture, uvw_world));
	float fine_density = SampleDensityTexture(texture(fine_density_texture, uvw_world * fine_scale));
	
	//float density = course_density * (1.0 - fine_blend) + fine_density * fine_blend;
	
	float density = course_density - mix(0.0, 1.0 - fine_density, course_density * fine_blend);
	
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

float LightContribution(vec3 ray_origin, float time)
{
	
	vec2 intersection = IntersectBox(bb_min, bb_max, ray_origin, 1.0 / light_direction);
	float depth = intersection.y;
	
	const int n_samples = 16;
	float dt = depth / float(n_samples-1);
	
	vec3 ray_step = light_direction * dt;
	
	float density = 0.0;
	
	float exit_threshold = 6.0 / (falloff_light * dt);
	
	for ( int i = 0; i < n_samples; i++ )
	{			
		density += Density(ray_origin, time);//exp(-falloff * );
		if ( density > exit_threshold )
		{
			break;
		}
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

vec2 Random(vec2 uv)
{
	return vec2(fract(sin(dot(uv.xy,
		vec2(12.9898,78.233))) * 43758.5453123));
}

vec4 RayMarch(inout float proj_depth, vec3 ray_origin, vec3 ray_direction, float depth, vec2 screen_uv, float time)
{
	// environment colour
	vec3 color = vec3(0.0);// texture(screen_texture, screen_uv).rgb;// vec3(1.0);//vec3(0.0);
	
	const int n_samples = 64;
	
	float dt = depth / float(n_samples-1);
	
	float noise_offset = dt * texture(blue_noise, fract(4.0 * screen_uv * time)).r;
	ray_origin += ray_direction * noise_offset;
	
	vec3 ray_step = ray_direction * dt;
	
	
	float light_energy = 0.0;
	
	float cosa = dot(ray_direction, light_direction);
	float phase = Phase(cosa);// max(, 0.0);
	
	float transmittance = 1.0;
	float t = 0.0;
	
	for ( int i = 0; i < n_samples; i++ )
	{
		//float t = -a / z + b;
		float density = Density(ray_origin, time);
		
		if ( density > 0.001 )
		{
			float light_transmittance = LightContribution(ray_origin, time);
			
			//color = light_color;// * 0.1 * light_depth;// LightContribution(ray_origin, light_depth);
			light_energy += light_transmittance * transmittance * density;
			transmittance *= exp(-falloff_color * density * dt);

			if ( transmittance < 0.99 )
			{
				proj_depth = min(proj_depth, t);
			}

			if ( transmittance < 0.001 )
			{
				transmittance = 0.0;
				break;
			}
		}
		ray_origin += ray_step;
		t += dt;
	}
	
	light_energy *= phase * dt * 1.0;
	return vec4(light_color.rgb * light_energy, 1.0 - transmittance);
}

vec4 CalculateCloud(
	inout float proj_depth, // projected depth
	vec3 ray_origin,
	vec3 ray_direction,
	vec2 screen_uv,
	float pixel_depth,
	float time
)
{
	vec3 inverse_ray_direction = 1.0 / ray_direction;
	vec2 intersection = IntersectBox(bb_min, bb_max, ray_origin, inverse_ray_direction);
	float t = intersection.x;
	float depth = intersection.y;
	depth = min(depth, pixel_depth-intersection.x);

	proj_depth = depth + t;

	if ( depth <= 0.0 || intersection.y <= 0.0 )
	{
		return vec4(0.0);
	}
	
	vec4 pixel = RayMarch(
		proj_depth,
		ray_origin + ray_direction * (t - 0.01), 
		ray_direction, 
		depth, 
		screen_uv,
		time
	);

	proj_depth += t;
	return pixel;
}

vec4 ProcessPixel(
	inout float proj_depth,
	mat4 inv_view_mat,
	mat4 inv_proj_mat,
	vec2 screen_uv,
	float time
)
{
	// Called for every pixel the material is visible on.
	vec3 ray_origin = inv_view_mat[3].xyz;

	//https://godotshaders.com/shader/volumetric-raymarched-animated-clouds-v2/
	float screen_depth = texture(depth_texture, screen_uv).r;
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, screen_depth);
	
	vec4 view = inv_proj_mat * vec4(ndc, 1.0);
	view.xyz /= view.w;
    float linear_depth = -view.z;
	vec3 ray_direction_local = normalize(view.xyz);
	ray_direction_local = normalize(ray_direction_local);
	vec3 ray_direction = mat3(inv_view_mat) * ray_direction_local;
	

	//return texture(blue_noise, fract(4.0 * screen_uv * time));

	//return vec4(vec3(linear_depth / 1000.0), 1.0);


	vec4 pixel = CalculateCloud(
		proj_depth,
		ray_origin,
		ray_direction,
		screen_uv,
		linear_depth,
		1.0
	);

	return pixel;
}