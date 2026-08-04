shader_type canvas_item;

uniform sampler3D texture_input;
uniform int channel: hint_range(0,3,1);
uniform float slice : hint_range(0.0, 1.0, 0.01);

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	vec4 sample = texture(texture_input, vec3(UV, slice));
	vec3 color = vec3(sample[channel]);
	COLOR = vec4(color, 1.0);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
