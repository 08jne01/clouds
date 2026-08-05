shader_type spatial;

render_mode unshaded;
render_mode cull_disabled;

#include "CloudMaths.gdshaderinc"

void vertex() {
	// Called for every vertex the material is visible on.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec4 pixel = ProcessPixel(
		INV_VIEW_MATRIX,
		INV_PROJECTION_MATRIX,
		SCREEN_UV,
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
