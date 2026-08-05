#[compute]
#version 450
#define COMPUTE

#include "CloudMaths.gdshaderinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Set 0 Reserved for Compute

//layout(set = 0, binding = 2) uniform sampler2D depth_texture;

layout(rgba16f, set = 0, binding = 0) uniform writeonly image2D cloud_image;
layout(column_major, set = 0, binding = 1) uniform RenderData
{
    mat4 INV_VIEW_MATRIX;
    mat4 INV_PROJECTION_MATRIX;
} render_data;

layout(push_constant, std430) uniform PushConstants {
    vec2 time;
    vec2 padding0;
} constants;

void main()
{
    ivec2 index = ivec2(gl_GlobalInvocationID.xy);

    // if ( index.x >= constants.raster_size.x || index.y >= constants.raster_size.y )
    //     return;

    ivec2 max_size = ivec2(gl_WorkGroupSize.xy * gl_NumWorkGroups.xy);
    vec2 screen_uv = vec2(gl_GlobalInvocationID.xy) / (max_size-1);

    vec4 cloud_pixel = ProcessPixel(
        render_data.INV_VIEW_MATRIX,
        render_data.INV_PROJECTION_MATRIX,
        screen_uv,
        constants.time.x
    );

    imageStore(cloud_image, index, cloud_pixel);
}