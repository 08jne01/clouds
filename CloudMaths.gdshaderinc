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
	UNIFORM(float fine_scale)                   HINT(hint_range(0.0, 10.0, 0.1))    DEFAULT(4.0);
	UNIFORM(float fine_blend)                   HINT(hint_range(0.0, 1.0, 0.01))    DEFAULT(0.2);
	
	UNIFORM(float scattering_forward)           HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float scattering_backward)          HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float scattering_omnidirectional)   HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float scattering_directional)       HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float scattering_direction_blend)   HINT(hint_range(0.0, 1.0, 0.1));
	UNIFORM(float curl_noise_blend)				HINT(hint_range(0.0, 20.0, 0.001));
	UNIFORM(float curl_noise_scale) 			HINT(hint_range(0.0, 1.0, 0.001)); 
	
	UNIFORM(float coverage_density) 			HINT(hint_range(0.0, 1.0, 0.001))   DEFAULT(1.0);
	UNIFORM(float ambient_light_bottom_factor)  HINT(hint_range(0.0, 5.0, 0.1))     DEFAULT(0.8);
	UNIFORM(float ambient_light_top_factor)		HINT(hint_range(0.0, 5.0, 0.1))     DEFAULT(1.0);
	UNIFORM(float padding2); // 36
	UNIFORM(vec4 ambient_light_color)			HINT(source_color);
#ifdef COMPUTE
};
#endif

LAYOUT(set = 1, binding = 1, uniform sampler3D density_texture)      HINT(repeat_enable);
LAYOUT(set = 1, binding = 2, uniform sampler3D fine_density_texture) HINT(repeat_enable);
LAYOUT(set = 1, binding = 3, uniform sampler2D height_texture)       HINT(repeat_disable);
LAYOUT(set = 1, binding = 4, uniform sampler2D cloud_coverage)       HINT(repeat_enable);
LAYOUT(set = 1, binding = 5, uniform sampler2D blue_noise)           HINT(filter_nearest);
LAYOUT(set = 1, binding = 6, uniform sampler3D curl_noise)           HINT(repeat_enable);
//LAYOUT(set = 1, binding = 6, uniform sampler3D curl_noise)           HINT(repeat_enable);

const float earth_radius = 6400000.0; //6400000.0;
const float atmosphere_0 = 500.0;
const float atmosphere_1 = 5000.0;
const float atmosphere_thickness = atmosphere_1 - atmosphere_0;
const float max_ray_distance = 10000.0;

const vec4 atmosphere_inner = vec4(
	0.0, -earth_radius, 0.0,
	atmosphere_0 + earth_radius
);

vec2 DistanceDepth(vec2 intersection)
{
	float distance_to_surface = max(intersection.x, 0.0);	
	float depth = max(intersection.y - distance_to_surface, 0.0);
	return vec2(distance_to_surface, depth);
}

// See notes about catastrophic cancellation in these below
//https://en.wikipedia.org/wiki/Quadratic_formula#Numerical_calculation
//https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-sphere-intersection.html
// sphere xyz origin, w radius
// returns all intersections (even ones behind)
void IntersectSphere(inout vec2 t, vec3 p, vec3 rd, vec4 sphere)
{
	vec3 p_minus_c = p - sphere.xyz;
	float r2 = sphere.w * sphere.w;

	float c = dot(p_minus_c, p_minus_c) - r2;
	float b = 2.0 * dot(rd, p_minus_c);

	float discriminant = b*b - 4.0 * c;

	if ( discriminant < 0.0 )
		return;

	float sqrt_discriminant = sqrt(discriminant); // always positive

	// vec2 intersection = vec2(
	// 	(-b - sqrt_discriminant) * 0.5,
	// 	(-b + sqrt_discriminant) * 0.5
	// );

	// t0 = q/a (a is 1 here)
	float t0 = -0.5 * (b + sign(b) * sqrt_discriminant);

	if ( discriminant == 0.0 )
	{
		t = min(t, vec2(t0));
		return;
	}

	float t1 = c / t0;

	vec2 intersection = vec2(
		min(t0,t1),
		max(t0,t1)
	);

	//t = intersection;
	t = min(t, intersection); // get minimum distance
}

float AbsMin(vec2 v)
{
	return abs(v.x) <= abs(v.y) ? v.x : v.y;
}

void IntersectShell(inout vec2 t, vec3 p, vec3 rd, vec4 sphere, float thickness)
{
	vec2 intersect0 = t;
	vec2 intersect1 = t;

	IntersectSphere(
		intersect0, 
		p,
		rd,
		vec4(sphere.xyz, sphere.w + thickness)
	);
	
	IntersectSphere(
		intersect1, 
		p,
		rd,
		sphere
	);

	vec2 td0 = DistanceDepth(intersect0);
	vec2 td1 = DistanceDepth(intersect1);

	float t0 = td0.x;
	float d0 = td0.y;

	float t1 = td1.x;
	float d1 = td1.y;

	vec2 intersect = vec2(t.x,0.0);

	if ( d1 > 0.0 )
	{
		if ( t0 > 0.0 )
		{
			intersect.x = t0;
			intersect.y =  t1 - t0;
		}
		else if ( t1 > 0.0 )
		{
			intersect.x = 0.0;
			intersect.y =  d0;
		}
		else
		{
			intersect.x = d1;
			intersect.y = d0 - d1;
		}
	}
	else if ( d0 > 0.0 )
	{	// doesn't intersect the centre sphere then it's just a normal sphere


		if ( t0 > 0.0 )
		{
			intersect = vec2(
				t0,
				d0
			);
		}
		else
		{
			intersect = vec2(
				0.0,
				d0
			);
		}

		
	}

	t = min(t, intersect);
}

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

// ISO Surface
float DensityISO(vec3 position)
{
	// float coarse_density = 
	// 	0.5 * (texture(density_texture, uvw_world * 0.1).r) +
	// 	0.25 * (texture(density_texture, uvw_world * 0.25).g) +
	// 	0.125 * (texture(density_texture, uvw_world * 2.0).b);
	// 	//-0.125 * (texture(density_texture, uvw_world * 5.0).a);
	// coarse_density /= 0.9375;
	return 0.0;
}

float Density(vec3 position)
{
	
	
	vec3 delta = bb_max - bb_min;
	float max_dim = cloud_scale * delta.y; //max(delta.x, max(delta.y,delta.z));
	
	vec3 uvw = (position - bb_min) / vec3(delta);
	vec3 uvw_world = position / vec3(max_dim);
	
	//float coverage = texture(cloud_coverage, uvw_world.xz * 0.1).r;
	
	
	
	float coarse_density = 
		0.5 * (texture(density_texture, uvw_world * 0.1).r) +
		0.25 * (texture(density_texture, uvw_world * 0.25).g) +
		0.125 * (texture(density_texture, uvw_world * 2.0).b);
		//-0.125 * (texture(density_texture, uvw_world * 5.0).a);
	coarse_density /= 0.9375;

	float coverage = clamp(texture(cloud_coverage, uvw_world.xz * 0.1).r + coverage_density, 0.0, 1.0);

	vec3 curl_noise_vector = curl_noise_blend * (texture(curl_noise, uvw_world * curl_noise_scale).rgb - 0.5) * 2.0;
	float fine_density = SampleDensityTexture(texture(fine_density_texture, curl_noise_vector + (uvw_world) * fine_scale)); //;
	
	//float density = course_density * (1.0 - fine_blend) + fine_density * fine_blend;
	
	float density = coarse_density
		- mix(0.0, 1.0 - fine_density, (1.0 - coarse_density) * fine_blend);
	



	float height_u = (length(position - atmosphere_inner.xyz) - atmosphere_inner.w) / (atmosphere_thickness);

	float height_density = texture(height_texture, vec2(height_u, 0.0)).r;
	//density *= height_density;

	density = clamp(density,0.0,1.0);
	//density *= 1.0 - uvw.y;
	
	// 0.0, 0.0,
	// 
	
	//density *= height_density * height_density;
	//density *= cloud_threshold;
	
	

	float cloud_t = clamp((density - (1.0 - coverage * height_density * cloud_threshold)) / cloud_threshold_delta, 0.0, 1.0);
	
	
	
	
	//return density * cloud_threshold;
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
	vec2 intersection = vec2(max_ray_distance); // pass in max distance
	
	IntersectShell(
		intersection,
		ray_origin,
		light_direction,
		atmosphere_inner,
		atmosphere_thickness
	);

	float depth = intersection.y;

	if ( depth > max_ray_distance )
		return 1.0;

	// vec2 intersection = IntersectBox(bb_min, bb_max, ray_origin, 1.0 / light_direction);
	// float depth = intersection.y;
	
	const int n_samples = 16;
	float dt = 0.5 * depth / float(n_samples-1);
	
	vec3 ray_step = light_direction * dt;
	
	float density = 0.0;
	
	float exit_threshold = 6.0 / (falloff_light * dt);
	
	for ( int i = 0; i < n_samples; i++ )
	{			
		density += Density(ray_origin);//exp(-falloff * );
		if ( density > exit_threshold )
		{
			break;
		}
		ray_origin += ray_step;
	}

	density += Density(ray_origin + light_direction * depth * 0.25);

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


float AmbientLightContribution( vec3 position, float alpha )
{
	float h = (position.y - atmosphere_0) / atmosphere_thickness;
	return alpha * mix(ambient_light_bottom_factor, ambient_light_top_factor, h);
}

vec4 RayMarch(inout float proj_depth, vec3 ray_origin, vec3 ray_direction, float depth, vec2 screen_uv)
{
	// environment colour
	vec3 color = vec3(0.0, 0.0, 0.0);// texture(screen_texture, screen_uv).rgb;// vec3(1.0);//vec3(0.0);
	
	const int n_samples = 128;
	
	float dt = depth / float(n_samples-1);
	
	vec3 ray_step = ray_direction * dt;
	
	
	float light_energy = 0.0;
	float ambient_light_energy = 0.0;
	
	float cosa = dot(ray_direction, light_direction);
	float phase = Phase(cosa);// max(, 0.0);
	
	float transmittance = 1.0;
	float t = dt * (texture(blue_noise, fract(4.0 * screen_uv + ray_origin.xz)).r - 0.5);
	float accumulated_weight = 0.0;
	for ( int i = 0; i < n_samples; i++ )
	{
		//float t = -a / z + b;

		
		vec3 ray_position = ray_origin + ray_direction * (t);

		float density = Density(ray_position);
		
		if ( density > 0.001 )
		{
			float light_transmittance = LightContribution(ray_position);
			
			//color = light_color;// * 0.1 * light_depth;// LightContribution(ray_origin, light_depth);

			float alpha = density * falloff_color;
			float transmittance_step = exp(-alpha * dt);

			// analytic integral of transmittance over this step
			float light_transmittance_step = (1.0 - transmittance_step) / falloff_color;
			float S = transmittance * light_transmittance_step;
			light_energy += S * light_transmittance;
			ambient_light_energy += S * AmbientLightContribution(ray_position, alpha);
			transmittance *= transmittance_step;
			

			// float weight = density * dt;
			// proj_depth += (t + depth) * weight;
			// accumulated_weight += weight;

			if ( transmittance < 0.8 )
			{
				proj_depth = min(proj_depth, t);
			}

			if ( transmittance < 0.001 )
			{
				transmittance = 0.0;
				break;
			}
		}
		//ray_origin += ray_step;
		t += dt;
	}

	//proj_depth = proj_depth / accumulated_weight;
	
	light_energy *= phase;// * dt * 1.0;
	ambient_light_energy *= phase;
	return vec4(ambient_light_color.rgb * ambient_light_energy + light_color.rgb * light_energy, 1.0 - transmittance);
}

vec4 CalculateCloud(
	inout float proj_depth, // projected depth
	vec3 ray_origin,
	vec3 ray_direction,
	vec2 screen_uv,
	float pixel_depth
)
{
	vec3 inverse_ray_direction = 1.0 / ray_direction;
	//vec2 intersection = IntersectBox(bb_min, bb_max, ray_origin, inverse_ray_direction);

	float max_ray_distance_truncated = max_ray_distance;
	// if ( ray_direction.y < 0.0 )
	// {
	// 	max_ray_distance_truncated = min(-ray_origin.y / ray_direction.y, max_ray_distance_truncated);
	// }

	vec2 intersection = vec2(max_ray_distance_truncated);

	IntersectShell(
		intersection,
		ray_origin,
		ray_direction,
		//vec4(0.0,0.0,0.0,100.0),
		//50.0
		atmosphere_inner,
		atmosphere_thickness
	);


	float t = intersection.x;
	float depth = intersection.y;

	
	depth = min(depth, pixel_depth-intersection.x);

	float T = exp(-intersection.y * 0.01);
	
	//return vec4(t / max_ray_distance, depth / max_ray_distance, 0.0, 0.5);



	if ( depth <= 0.0 || intersection.y <= 0.0 )
	{
		proj_depth = -1.0;
		return vec4(0.0);
	}

	proj_depth = depth;
	
	vec4 pixel = RayMarch(
		proj_depth,
		ray_origin + ray_direction * (t - 0.01), 
		ray_direction, 
		depth, 
		screen_uv
	);

	if ( abs(proj_depth-depth) < 0.1 )
	{
		proj_depth = -1.0;
	}
	else
	{
		proj_depth += t;
	}

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

	ray_origin += time * vec3(20.0,0.0,0.0);

	vec4 pixel = CalculateCloud(
		proj_depth,
		ray_origin,
		ray_direction,
		screen_uv,
		linear_depth
	);

	return pixel;
}