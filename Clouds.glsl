#[compute]
#version 450
#define COMPUTE

#include "CloudMaths.gdshaderinc"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Set 0 Reserved for Compute

//layout(set = 0, binding = 2) uniform sampler2D depth_texture;

layout(rgba16f, set = 0, binding = 5) uniform image2D cloud_depth;
layout(rgba16f, set = 0, binding = 4) uniform image2D cloud_display;
layout(rgba16f, set = 0, binding = 3) uniform image2D cloud_image_prev;

layout(rgba8, set = 0, binding = 0) uniform image2DArray cloud_image;
layout(column_major, set = 0, binding = 1) uniform RenderData
{
    mat4 INV_VIEW_MATRIX;
    mat4 INV_PROJECTION_MATRIX;
    mat4[4] PREV_VIEW_MATRIX;
    mat4[4] PREV_PROJECTION_MATRIX;
} render_data;

layout(push_constant, std430) uniform PushConstants {
    vec2 time;
    ivec2 offset;
    vec2 cloud_size;
    ivec2 current_offset;
} constants;

vec2 ReprojectPixel(
    mat4 prev_view_mat, 
    mat4 prev_proj_mat, 
    vec2 uv, 
    float norm_depth
)
{
	vec2 ndc = uv * 2.0 - 1.0;

    vec4 view = render_data.INV_PROJECTION_MATRIX * vec4(ndc, 1.0, 1.0);
    view /= view.w;

    vec4 ray_direction = render_data.INV_VIEW_MATRIX * vec4(normalize(view.xyz) * norm_depth, 1.0);


    vec4 prev_view = prev_view_mat * ray_direction;
    vec4 prev_ndc = prev_proj_mat * prev_view;

    prev_ndc /= prev_ndc.w;
    vec2 prev_uv = (prev_ndc.xy + 1.0) * 0.5;

    if ( prev_ndc.z < 0.0 || prev_ndc.z > 1.0 )
    {
        return vec2(-1.0, 1.0);
    }

    return prev_uv;
}

float LinearDepth(vec2 uv, float non_linear_depth)
{
    vec3 ndc = vec3(uv * 2.0 - 1.0, non_linear_depth);

    vec4 view = render_data.INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view /= view.w;
    float linear_depth = -view.z;
    return linear_depth;
}

float ClipDepth(vec2 uv, float depth)
{
    vec4 ndc = inverse(render_data.INV_PROJECTION_MATRIX) * vec4(0.0, 0.0, -depth, 1.0);
    ndc /= ndc.w;
    return ndc.z;
}

void main()
{
    // Render
    ivec2 index = 2 * ivec2(gl_GlobalInvocationID.xy);
    ivec2 max_size = 2 * ivec2(gl_WorkGroupSize.xy * gl_NumWorkGroups.xy);

    // Cloud
    ivec2 render_index = index + constants.offset;

    vec2 screen_uv = vec2(render_index) / (max_size-1);

    float proj_depth = 1000000.0;
    vec4 cloud_pixel = ProcessPixel(
        proj_depth,
        render_data.INV_VIEW_MATRIX,
        render_data.INV_PROJECTION_MATRIX,
        screen_uv,
        constants.time.x
    );

    // vec4 cloud_pixel_new = ProcessPixel(
    //     proj_depth,
    //     render_data.INV_VIEW_MATRIX,
    //     render_data.INV_PROJECTION_MATRIX,
    //     screen_uv,
    //     constants.time.x
    // );

    float norm_depth = ClipDepth(screen_uv, proj_depth);
    norm_depth = clamp(norm_depth, 0.0, 1.0);


    // Reproject

    ivec2[4] reproject_offset = {
        ivec2(0,0),
        ivec2(1,1),
        ivec2(1,0),
        ivec2(0,1),
    };

    // for ( int i = 0; i < 4; i++ )
    // {

    //     //constants.current_offset.x;
    //     //int i = (constants.current_offset.x + 0) % 4;

    //     ivec2 reproject_index = index + reproject_offset[i];
    //     vec2 uv = vec2(reproject_index) / (max_size-1);

    //     float pixel_depth = imageLoad(cloud_depth, reproject_index).r;

    //     vec2 old_uv = ReprojectPixel(uv, proj_depth);

    //     ivec2 old_index = ivec2(round(old_uv * vec2(max_size-1)));

    //     // if ( reproject_index == old_index )
    //     // {
    //     //     imageStore(cloud_display, reproject_index, vec4(0.0, 1.0, 0.0, 1.0));
    //     // }
    //     // else
    //     // {
    //     //     imageStore(cloud_display, render_index, cloud_pixel);
    //     //     //imageStore(cloud_display, reproject_index, vec4(0.0, 0.0, 1.0, 1.0));

    //     // }

    //     if (
    //         proj_depth < 0.0 ||
    //         old_index.x < 0 || 
    //         old_index.y < 0 ||
    //         old_index.x >= (max_size.x) ||
    //         old_index.y >= (max_size.y)
    //     )
    //     {
    //         //cloud_pixel
    //         //imageStore(cloud_image, reproject_index, cloud_pixel);
    //         //imageStore(cloud_image, reproject_index, vec4(1.0, 0.0, 0.0, 1.0));
    //     }
    //     else
    //     {
    //         //vec2 half_texel = 0.5 / textureSize(cloud_image_prev, 0);

    //         vec2 min_uv = vec2(0.0);
    //         vec2 max_uv = constants.cloud_size; 
            
    //         vec2 adjusted_uv = mix(min_uv, max_uv, old_uv);

    //         vec4 pixel = imageLoad(cloud_image_prev, old_index);

    //         // if ( pixel.a == 0.0 )
    //         // {
    //         //     imageStore(cloud_image, reproject_index, cloud_pixel);
    //         // }
    //         // else
    //         // {
    //         // }

    //         //imageStore(cloud_display, reproject_index, vec4(old_uv, 0.0, 1.0));
    //         imageStore(cloud_image, reproject_index, pixel);
    //     }

    //     //vec4 pixel = imageLoad(cloud_image_prev, old_index);

    //     float real_depth = texture(depth_texture, uv).r;

        

    //     // if ( real_depth >= norm_depth )
    //     // {
    //     //     imageStore(cloud_display, reproject_index, vec4(0.0, 0.0, 0.0, 0.0));
    //     // }
    //     // else
    //     // {

    //     // }

    //     float d = LinearDepth(screen_uv, texture(depth_texture, screen_uv).r);
    //     float d1 = ClipDepth(screen_uv, d);

    //     //imageStore(cloud_display, reproject_index, vec4(vec3(proj_depth / 100000.0), 1.0));
        
    //     //vec2 pixel_same = uv - old_uv;
    //     //bool same = reproject_index == old_index;

       
    // }

    
    //imageStore(cloud_display, render_index, cloud_pixel);

    imageStore(cloud_image, ivec3(index + reproject_offset[0], constants.current_offset.x), cloud_pixel);
    imageStore(cloud_image, ivec3(index + reproject_offset[1], constants.current_offset.x), cloud_pixel);
    imageStore(cloud_image, ivec3(index + reproject_offset[2], constants.current_offset.x), cloud_pixel);
    imageStore(cloud_image, ivec3(index + reproject_offset[3], constants.current_offset.x), cloud_pixel);

    //imageStore(cloud_display, render_index, cloud_pixel);

    for ( int i = 0; i < 4; i++ )
    {
        int j = (i + constants.current_offset.x + 1) % 4;

        ivec2 reproject_index = index + reproject_offset[j];
        vec2 uv = vec2(reproject_index) / (max_size-1);

        //float pixel_depth = imageLoad(cloud_depth, reproject_index).r;

        vec2 old_uv = ReprojectPixel(
            render_data.PREV_VIEW_MATRIX[j],
            render_data.PREV_PROJECTION_MATRIX[j],
            uv, 
            proj_depth
        );

        ivec2 old_index = ivec2(round(old_uv * vec2(max_size - 1)));
        

        if (
            proj_depth < 0.0 ||
            old_index.x < 0 || 
            old_index.y < 0 ||
            old_index.x >= (max_size.x) ||
            old_index.y >= (max_size.y)
        )
        {
            imageStore(cloud_display, reproject_index, cloud_pixel);
            //imageStore(cloud_display, reproject_index, vec4(1.0, 0.0, 0.0, 1.0));
        }
        else
        {
            vec4 pixel = imageLoad(cloud_image, ivec3(old_index,j));
            if ( pixel.a == 0.0 )
                imageStore(cloud_display, reproject_index, cloud_pixel);
            else
                imageStore(cloud_display, reproject_index, pixel);
        }
    }

    

    // if ( index.x >= constants.raster_size.x || index.y >= constants.raster_size.y )
    //     return;

    

    //imageStore(cloud_image, render_index, cloud_pixel);
    //imageStore(cloud_depth, render_index, vec4(vec3(norm_depth), 1.0));
    
    //imageStore(cloud_display, render_index, imageLoad(cloud_image,  render_index));
    //imageStore(cloud_display, render_index, cloud_pixel);
    //imageStore(cloud_display, render_index, vec4(vec3(norm_depth), 1.0));
}