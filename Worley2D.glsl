#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba8, set = 0, binding = 0) uniform restrict writeonly image2D out_texture;

layout(push_constant, std430) uniform Params
{
    uvec4 square_size;
} params;

vec2 PixelToUV(ivec2 pixel, ivec2 size)
{
    return vec2(pixel) / vec2(size-1);
}

vec2 Random(vec2 uv)
{
	return vec2(fract(sin(dot(uv.xy,
		vec2(12.9898,78.233))) * 43758.5453123));
}

float WorleyNoise(ivec2 pixel, ivec2 max_size, int square_size)
{
    ivec2 n_squares = max_size / square_size;

    const ivec2[9] squares = {
        ivec2(-1,-1), // clockwise
        ivec2( 0,-1),
        ivec2( 1,-1),
        ivec2( 1, 0),
        ivec2( 1, 1),
        ivec2( 0, 1),
        ivec2(-1, 1),
        ivec2(-1, 0),
        ivec2( 0, 0) // centre square
    };

    float min_distance = 1.0;

    ivec2 current_square = pixel / square_size;

    vec2 pixel_location = vec2(pixel % square_size) / float(square_size);

    for ( int i = 0; i < 9; i++ )
    {
        ivec2 offset = squares[i];

        ivec2 wrapped_square = ((current_square + offset) + n_squares) % n_squares;

        vec2 uv_square = PixelToUV(wrapped_square, n_squares);
        vec2 point = Random(uv_square) + vec2(offset);
        float pixel_distance = length(point - pixel_location);
        min_distance = min(min_distance, pixel_distance);
    }

    return 1.0 - min_distance;
}

void main() {

    ivec2 max_size = ivec2(gl_WorkGroupSize.xy * gl_NumWorkGroups.xy);


    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    

    ivec4 square_size = ivec4(params.square_size);

    //vec2 uv = PixelToUV(pixel, max_size);

    //vec2 uv_square = PixelToUV(square, n_squares);

    


    // vec2 uv_square = PixelToUV(current_square, n_squares);
    // vec2 point = Random(uv_square);
    // float p = length(point - pixel_location);
    // float point_hightlight = 1.0;
    // if ( p < 0.1 )
    // {
    //     point_hightlight = 0.0;
    // }

    //vec2 N = Random(uv_square);

    //vec2 pixel_location = vec2(pixel % params.square_size) / float(params.square_size);
    //vec2 uv_square = PixelToUV(current_square, n_squares);

    // vec2 uv_square = PixelToUV(current_square, n_squares);
    // vec2 point = Random(uv_square);
    // vec2 pixel_location = vec2(pixel % params.square_size) / float(params.square_size);
    // float pixel_distance = length(point - pixel_location);

    vec4 result = vec4(
        WorleyNoise(pixel, max_size, square_size.x),
        WorleyNoise(pixel, max_size, square_size.y),
        WorleyNoise(pixel, max_size, square_size.z),
        WorleyNoise(pixel, max_size, square_size.w)
    );

    //vec4 result = vec4(vec2(1.0 - min_distance), point_hightlight, 1.0);

    ivec2 index = ivec2(gl_GlobalInvocationID.xy);
    imageStore(out_texture, index, result);
}