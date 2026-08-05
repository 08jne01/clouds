shader_type spatial;
render_mode unshaded;
uniform sampler2D cloud_texture;
uniform sampler2D screen_texture : hint_screen_texture;

void vertex() {
	// Called for every vertex the material is visible on.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 screen = texture(screen_texture, SCREEN_UV).rgb;
	vec4 cloud = texture(cloud_texture, SCREEN_UV);
	
	ALBEDO = mix(screen, cloud.rgb, cloud.a);
	// Called for every pixel the material is visible on.
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
