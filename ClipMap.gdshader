shader_type spatial;


uniform sampler2D height_map_course : repeat_enable;
uniform sampler2D height_map_fine : repeat_enable;
uniform sampler2DArray test : repeat_disable;//, filter_nearest;
uniform ivec4 map_position; // (x,z,scale)
uniform ivec2 parent_position;
uniform uint level;

vec2 CalculateUV(ivec2 vertex_position, ivec2 origin, int size)
{
	ivec2 difference = vertex_position - origin;
	vec2 uv = vec2(difference) / float(size);
	return uv;
}

void vertex() {
	// Called for every vertex the material is visible on.
	//VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vertex_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	
	ivec2 ivertex_position = ivec2(vertex_position.xz);
	//ivec2 difference = ivertex_position - map_position.xy;
	
	ivec2 difference = ivertex_position - map_position.xy;
	vec2 uv = CalculateUV(ivertex_position, map_position.xy, map_position.z); //vec2(difference) / float(map_position.z);
	
	//vec2 centre = vec2(ivertex_position % map_position.z) / float(map_position.z);
	
	//difference *= 0.5;
	
	UV = uv;// + centre;
	
	bool edge = difference.x == 0 || difference.y == 0 || difference.x == (map_position.z) || difference.y == (map_position.z);
	if ( false )
	{

		vec2 uv_coarse = CalculateUV(ivertex_position, parent_position, map_position.z * 2);

		// int m = (map_position.z + 2) / 4;
		// float offset = 0.5 * float(map_position.w) / float(map_position.z); //float(m-1) / float(map_position.z);
		// vec2 uv_offset = vec2(offset,offset);
		
		//VERTEX.y += texture(test, vec3(uv_offset + UV * 0.5,float(level-1u))).r;
		VERTEX.y += texture(test, vec3(uv_coarse,float(level+1u))).r;
	}
	else
	{
		VERTEX.y += texture(test, vec3(UV,float(level))).r;
	}
}

void fragment() {
	// Called for every pixel the material is visible on.
	//ALBEDO = vec3(UV.x, UV.y, 0.0);
	//ALBEDO = vec3(sin(UV.x * 2.0 * 3.141)); //texture(test, vec3(UV,float(level))).rrr; //vec3(UV.x, UV.y, 0.0);

	// if ( level == 0 )
	// {
	// 	int m = (map_position.z + 2) / 4;
	// 	float offset = float(m-1) / float(map_position.z) * 2.0;
	// 	vec2 uv_offset = vec2(offset,offset);
	// 	ALBEDO = vec3(UV.x, UV.y, 0.0);
	// }
	// else
	// {
	// 	ALBEDO = vec3(UV.x, UV.y, 0.0);
	// }

	//ALBEDO = vec3(UV.x, UV.y, 0.0);

	//ALBEDO = texture(height_map_fine, UV).rgb;
	ALBEDO = (texture(test, vec3(UV,float(level))).rrr + 50.0) / 100.0;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
