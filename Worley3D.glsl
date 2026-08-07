#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
layout(rgba8, set = 0, binding = 0) uniform restrict writeonly image3D out_texture;

layout(push_constant, std430) uniform Params
{
    uvec4 square_size;
} params;

vec3 PixelToUV(ivec3 pixel, ivec3 size)
{
    return vec3(pixel) / vec3(size-1);
}

//https://jcgt.org/published/0009/03/02/
uvec3 pcg3d(uvec3 v)
{
    v = v * 1664525u + 1013904223u;
    v.x += v.y*v.z; 
    v.y += v.z*v.x; 
    v.z += v.x*v.y;
    v ^= v >> 16u;
    v.x += v.y*v.z; 
    v.y += v.z*v.x; 
    v.z += v.x*v.y;
    return v;
}


vec3 Random(vec3 uv, int seed)
{
	return vec3(pcg3d(seed + uvec3(uv * 0xffffffffu))) / float(0xffffffffu);
}

float WorleyNoise(ivec3 pixel, ivec3 max_size, int square_size, int seed)
{
    ivec3 n_squares = max_size / square_size;

    const ivec3[27] squares = {
        ivec3(-1,-1, -1), // clockwise
        ivec3( 0,-1, -1),
        ivec3( 1,-1, -1),
        ivec3( 1, 0, -1),
        ivec3( 1, 1, -1),
        ivec3( 0, 1, -1),
        ivec3(-1, 1, -1),
        ivec3(-1, 0, -1),
        ivec3( 0, 0, -1), // centre square

        ivec3(-1,-1,  0), // clockwise
        ivec3( 0,-1,  0),
        ivec3( 1,-1,  0),
        ivec3( 1, 0,  0),
        ivec3( 1, 1,  0),
        ivec3( 0, 1,  0),
        ivec3(-1, 1,  0),
        ivec3(-1, 0,  0),
        ivec3( 0, 0,  0), // centre square

        ivec3(-1,-1,  1), // clockwise
        ivec3( 0,-1,  1),
        ivec3( 1,-1,  1),
        ivec3( 1, 0,  1),
        ivec3( 1, 1,  1),
        ivec3( 0, 1,  1),
        ivec3(-1, 1,  1),
        ivec3(-1, 0,  1),
        ivec3( 0, 0,  1) // centre square
    };

    float min_distance = 1.0;

    ivec3 current_square = pixel / square_size;

    vec3 pixel_location = vec3(pixel % square_size) / float(square_size);

    for ( int i = 0; i < 27; i++ )
    {
        ivec3 offset = squares[i];

        ivec3 wrapped_square = ((current_square + offset) + n_squares) % n_squares;

        vec3 uv_square = PixelToUV(wrapped_square, n_squares);
        vec3 point = Random(uv_square, seed) + vec3(offset);
        float pixel_distance = length(point - pixel_location);
        min_distance = min(min_distance, pixel_distance);
    }

    return 1.0 - min_distance;
}

float FractalWorleyNoise(ivec3 pixel, ivec3 max_size, int square_size, int octaves, float gain_factor)
{
    float total = 0.0;
    float gain = 1.0;
    for ( int i = 0; i < octaves; i++ )
    {
        total += gain * WorleyNoise(pixel, max_size, square_size, i);
        gain *= gain_factor;
        square_size /= 2;
    }

    float norm = (1.0 - pow(gain_factor, float(octaves))) / (1.0 - gain);
    total /= norm;
    return total;
}

void main() {

    ivec3 max_size = ivec3(gl_WorkGroupSize.xyz * gl_NumWorkGroups.xyz);


    ivec3 pixel = ivec3(gl_GlobalInvocationID.xyz);
    

    ivec4 square_size = ivec4(params.square_size);

    vec4 result = vec4(
        FractalWorleyNoise(pixel, max_size, square_size.x, 5, 0.5),
        FractalWorleyNoise(pixel, max_size, square_size.y, 5, 0.5),
        FractalWorleyNoise(pixel, max_size, square_size.z, 5, 0.5),
        FractalWorleyNoise(pixel, max_size, square_size.w, 5, 0.5)
    );

    ivec3 index = ivec3(gl_GlobalInvocationID.xyz);
    imageStore(out_texture, index, result);
}