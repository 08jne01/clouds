shader_type spatial;

render_mode unshaded;
render_mode cull_disabled;

#include "CloudMaths.gdshaderinc"

void vertex() {
	// Called for every vertex the material is visible on.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// Called for every pixel the material is visible on.
	vec3 ray_origin = INV_VIEW_MATRIX[3].xyz;

	//https://godotshaders.com/shader/volumetric-raymarched-animated-clouds-v2/
	float screen_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, screen_depth);
	
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
    float linear_depth = -view.z;
	vec3 ray_direction_local = normalize(view.xyz);
	ray_direction_local = normalize(ray_direction_local);
	vec3 ray_direction = mat3(INV_VIEW_MATRIX) * ray_direction_local;
	
	vec4 pixel = CalculateCloud(
		ray_origin,
		ray_direction,
		SCREEN_UV,
		linear_depth,
		TIME
	);
	
	if ( pixel.a <= 0.0 )
	{
		discard;
	}
	
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
