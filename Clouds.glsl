#[compute]
#version 450
#define COMPUTE

#include "CloudMaths.gdshaderinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Set 0 Reserved for Compute

//layout(set = 0, binding = 2) uniform sampler2D depth_texture;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(column_major, set = 0, binding = 1) uniform RenderData
{
    mat4 INV_VIEW_MATRIX;
    mat4 INV_PROJECTION_MATRIX;
} render_data;

layout(push_constant, std430) uniform PushConstants {
    ivec2 raster_size;
    vec2 time;
    
} constants;

void main()
{
    ivec2 index = ivec2(gl_GlobalInvocationID.xy);

    if ( index.x >= constants.raster_size.x || index.y >= constants.raster_size.y )
        return;

    vec2 screen_uv = vec2(gl_GlobalInvocationID.xy) / (constants.raster_size - 1);

    vec4 cloud_pixel = ProcessPixel(
        render_data.INV_VIEW_MATRIX,
        render_data.INV_PROJECTION_MATRIX,
        screen_uv,
        constants.time.x
    );

    vec4 image_pixel = imageLoad(color_image, index);

    // imageStore(color_image, index, 
    //     texture(density_texture, vec3(screen_uv, 0.0))
    // );

    imageStore(color_image, index, mix(
        image_pixel,
        vec4(cloud_pixel.rgb, 1.0),
        cloud_pixel.a
    ));


    // float screen_depth = texture(depth_texture, screen_uv).r;
    // vec3 ndc = vec3(screen_uv * 2.0 - 1.0, screen_depth);
    // vec4 view = render_data.INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	// view.xyz /= view.w;
    // float linear_depth = -view.z / 100.0;
    
    // imageStore(color_image, ivec2(gl_GlobalInvocationID.xy), vec4(vec3(linear_depth), 1.0));
}