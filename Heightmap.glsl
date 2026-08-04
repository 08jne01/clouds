#[compute]
#version 450

//
// Description : Array and textureless GLSL 2D simplex noise function.
//      Author : Ian McEwan, Ashima Arts.
//  Maintainer : stegu
//     Lastmod : 20110822 (ijm)
//     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
//               Distributed under the MIT License. See LICENSE file.
//               https://github.com/ashima/webgl-noise
//               https://github.com/stegu/webgl-noise
// 

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec2 mod289(vec2 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec3 permute(vec3 x) {
  return mod289(((x*34.0)+10.0)*x);
}

float snoise(vec2 v)
  {
  const vec4 C = vec4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                      0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                     -0.577350269189626,  // -1.0 + 2.0 * C.x
                      0.024390243902439); // 1.0 / 41.0
// First corner
  vec2 i  = floor(v + dot(v, C.yy) );
  vec2 x0 = v -   i + dot(i, C.xx);

// Other corners
  vec2 i1;
  //i1.x = step( x0.y, x0.x ); // x0.x > x0.y ? 1.0 : 0.0
  //i1.y = 1.0 - i1.x;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  // x0 = x0 - 0.0 + 0.0 * C.xx ;
  // x1 = x0 - i1 + 1.0 * C.xx ;
  // x2 = x0 - 1.0 + 2.0 * C.xx ;
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;

// Permutations
  i = mod289(i); // Avoid truncation effects in permutation
  vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))
		+ i.x + vec3(0.0, i1.x, 1.0 ));

  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
  m = m*m ;
  m = m*m ;

// Gradients: 41 points uniformly over a line, mapped onto a diamond.
// The ring size 17*17 = 289 is close to a multiple of 41 (41*7 = 287)

  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;

// Normalise gradients implicitly by scaling m
// Approximation of: m *= inversesqrt( a0*a0 + h*h );
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );

// Compute final noise value at P
  vec3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

vec3 FractalNoise(float height, float scale, vec2 position, int octaves)
{
    float h = 0.0;

    float fraction = 1.0;
    float total_height = 0.0;

    for ( int i = 0; i < octaves; i++ )
    {
        h += fraction * snoise(scale * position);
        total_height += fraction;
        fraction *= 0.5;
        scale *= 2.0;
    }

    return vec3(position.x, height * h / total_height, position.y);
}

vec3 Normal( float height, float scale, vec3 position, float step, int octaves )
{
    vec3 x0 = FractalNoise( height, scale, position.xz + vec2(-step,0.0), octaves );
    vec3 x1 = FractalNoise( height, scale, position.xz + vec2(step,0.0), octaves );

    vec3 z0 = FractalNoise( height, scale, position.xz + vec2(0.0,-step), octaves );
    vec3 z1 = FractalNoise( height, scale, position.xz + vec2(0.0,step), octaves );

    vec3 normal = normalize(cross( z1 - z0, x1 - x0 ));
    return normal;
}

// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(r32f, set = 0, binding = 0) uniform restrict writeonly image2DArray height_map;

layout(set = 1, binding = 0, std430) restrict buffer MapPositions {
    ivec4 data[]; // (x,z,scale,block)
} map_positions;

layout(push_constant, std430) uniform Params
{
    ivec2 position;
    int size;
} params;

// The code we want to execute in each invocation
void main() {




    uvec2 max_size = gl_WorkGroupSize.xy * gl_NumWorkGroups.xy;
    vec2 uv = vec2(gl_GlobalInvocationID.xy) / vec2(max_size-1);

    // gl_GlobalInvocationID.x uniquely identifies this invocation across all work groups

    uint level = gl_GlobalInvocationID.z;
    uint scale = 1 << level;
    
    ivec4 data_2 = map_positions.data[2];


    vec2 coordinates = vec2(map_positions.data[level].xy) + 0.25 * uv * float(map_positions.data[level].z);

    // vec2 origin_2 = vec2(data_2.xy);
    // float scale_2 = float(data_2.z);

    // vec2 real_uv = (coordinates - origin_2) / scale_2;

    //float value = 5.0 * sin(0.01 * coordinates.y + coordinates.x * 0.001);// 

    float value = FractalNoise(100.0, 0.001, coordinates, 6).y + 0.5;
    // if ( map_positions.data[level].xy == ivec2(-240,-240) )
    // {
    //     value = 0.0;
    // }



    vec4 result = vec4(value, value, value, 1.0);

    ivec3 index = ivec3(gl_GlobalInvocationID.xyz);
    imageStore(height_map, index, result);
}