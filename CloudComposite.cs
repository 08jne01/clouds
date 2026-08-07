using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

public partial class CloudComposite : CompositorEffect
{
    [Export] ShaderMaterial cloud_material;

    Rid cloud_shader = new Rid();
    Rid cloud_pipeline;

    Rid mix_shader = new Rid();
    Rid mix_pipeline;


    Rid repeat_enabled_sampler;
    Rid repeat_disabled_sampler;
    Rid nearest_sampler;

    RDShaderFile cloud_shader_file;
    ShaderInclude cloud_shader_file_inc;
    RDShaderFile mix_shader_file;

    Mutex mutex = new Mutex();

    int offset = 0;

    Rid render_data_buffer;
    byte[] render_data_buffer_bytes = new byte[1024];

    Rid cloud_settings_buffer;
    byte[] cloud_settings_buffer_bytes = new byte[36 * 4];

    [Export] Texture2DArrayRD tex = new Texture2DArrayRD();

    [Export] bool render_new = true;
    
    public enum CloudQuality
    {
        LOW,
        HIGH
    }

    [Export] public CloudQuality quality = CloudQuality.HIGH;

    uint cloud_buffer_x = 1920;
    uint cloud_buffer_y = 1080;
    Rid cloud_buffer; // clean cloud (with interlacing)
    Rid prev_cloud_buffer; // clean cloud (with interlacing) previous

    //Rid prev_cloud_buffer; // prev
    Rid cloud_display_buffer; // has reprojection
    Rid cloud_depth_buffer; 

    (string, ulong)[] dependencies = [
        ("res://Clouds.glsl", 0),
        ("res://CloudMaths.gdshaderinc", 0)
    ];

    Transform3D?[] prev_inv_camera_transform = new Transform3D?[4];
    Projection?[] prev_camera_projection = new Projection?[4];

    public CloudComposite()
    {
        var rd = RenderingServer.GetRenderingDevice();
        var repeat_enabled_sampler_state = new RDSamplerState
        {
            RepeatU = RenderingDevice.SamplerRepeatMode.Repeat,
            RepeatV = RenderingDevice.SamplerRepeatMode.Repeat,
            RepeatW = RenderingDevice.SamplerRepeatMode.Repeat,
            MinFilter = RenderingDevice.SamplerFilter.Linear,
            MagFilter = RenderingDevice.SamplerFilter.Linear,
            MipFilter = RenderingDevice.SamplerFilter.Linear,
        };
        repeat_enabled_sampler = rd.SamplerCreate(repeat_enabled_sampler_state);

        var repeat_disabled_sampler_state = new RDSamplerState
        {
            RepeatU = RenderingDevice.SamplerRepeatMode.ClampToEdge,
            RepeatV = RenderingDevice.SamplerRepeatMode.ClampToEdge,
            RepeatW = RenderingDevice.SamplerRepeatMode.ClampToEdge,
            MinFilter = RenderingDevice.SamplerFilter.Linear,
            MagFilter = RenderingDevice.SamplerFilter.Linear,
            MipFilter = RenderingDevice.SamplerFilter.Linear,
        };
        repeat_disabled_sampler = rd.SamplerCreate(repeat_disabled_sampler_state);

        var nearest_sampler_state = new RDSamplerState
        {
            MinFilter = RenderingDevice.SamplerFilter.Nearest,
            MagFilter = RenderingDevice.SamplerFilter.Nearest,
            MipFilter = RenderingDevice.SamplerFilter.Nearest,
        };
        nearest_sampler = rd.SamplerCreate(nearest_sampler_state);

        render_data_buffer      = rd.UniformBufferCreate((uint)render_data_buffer_bytes.Length);
        cloud_settings_buffer   = rd.StorageBufferCreate((uint)cloud_settings_buffer_bytes.Length);


        var texture_format = new RDTextureFormat
        {
            Format = RenderingDevice.DataFormat.R8G8B8A8Unorm,
            TextureType = RenderingDevice.TextureType.Type2D,
            Width = cloud_buffer_x,
            Height = cloud_buffer_y,
            Depth = 1,
            ArrayLayers = 1,
            Mipmaps = 1,
            UsageBits = 
                RenderingDevice.TextureUsageBits.StorageBit | 
                RenderingDevice.TextureUsageBits.CanUpdateBit | 
                RenderingDevice.TextureUsageBits.CanCopyToBit |
                RenderingDevice.TextureUsageBits.CanCopyFromBit |
                RenderingDevice.TextureUsageBits.SamplingBit |
                RenderingDevice.TextureUsageBits.ColorAttachmentBit
        };

        cloud_display_buffer = rd.TextureCreate(texture_format, new RDTextureView());
        cloud_depth_buffer = rd.TextureCreate(texture_format, new RDTextureView());

        texture_format.ArrayLayers = 4;
        texture_format.TextureType = RenderingDevice.TextureType.Type2DArray;

        cloud_buffer = rd.TextureCreate(texture_format, new RDTextureView());
        prev_cloud_buffer = rd.TextureCreate(texture_format, new RDTextureView());
        GD.Print(cloud_buffer);

        rd.TextureClear(cloud_buffer, new Color(1.0f, 1.0f, 1.0f, 1.0f), 0, 1, 0, 4);
        rd.TextureClear(prev_cloud_buffer, new Color(1.0f, 1.0f, 1.0f, 1.0f), 0, 1, 0, 4);
        rd.TextureClear(cloud_display_buffer, new Color(0.0f, 0.0f, 0.0f, 0.0f), 0, 1, 0, 1);
        rd.TextureClear(cloud_depth_buffer, new Color(0.0f, 0.0f, 0.0f, 0.0f), 0, 1, 0, 1);


        cloud_shader_file = GD.Load<RDShaderFile>("res://Clouds.glsl");
        cloud_shader_file_inc = GD.Load<ShaderInclude>("res://CloudMaths.gdshaderinc");
        mix_shader_file = GD.Load<RDShaderFile>("res://CloudMix.glsl");

        cloud_shader_file.Changed += CompileShaders;
        cloud_shader_file_inc.Changed += CompileShaders;
        mix_shader_file.Changed += CompileShaders;

        CompileShaders();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationPredelete)
		{
			if (cloud_shader.IsValid)
			{
				RenderingServer.GetRenderingDevice().FreeRid(cloud_shader);
			}

            if (mix_shader.IsValid)
			{
				RenderingServer.GetRenderingDevice().FreeRid(mix_shader);
			}
		}
    }

    // updates shader times
    bool ShaderDirty()
    {
        bool dirty = false;
        for ( int i = 0; i < dependencies.Length; i++ )
        {
            ulong last_modifiy = dependencies[i].Item2;
            ulong time = FileAccess.GetModifiedTime(dependencies[i].Item1);

            dirty |= time != last_modifiy;

            dependencies[i].Item2 = time;
        }

        return dirty;
    }

    void OnChanged()
    {
        GD.Print("Script Modified");
    }

    void CompileShaders()
    {
        var rd = RenderingServer.GetRenderingDevice();

        GD.Print("Compiling Shader...");

        if ( cloud_shader.IsValid )
        {
            rd.FreeRid(cloud_shader);
        }

        if ( mix_shader.IsValid )
        {
            rd.FreeRid(mix_shader);
        }

        // Done regardless
        var cloud_shader_byte_code = cloud_shader_file.GetSpirV();
        cloud_shader = rd.ShaderCreateFromSpirV(cloud_shader_byte_code);
        cloud_pipeline = rd.ComputePipelineCreate(cloud_shader);

        var mix_shader_byte_code = mix_shader_file.GetSpirV();
        mix_shader = rd.ShaderCreateFromSpirV(mix_shader_byte_code);
        mix_pipeline = rd.ComputePipelineCreate(mix_shader);
    }


    public static int CopyValue<T>( Span<Byte> buffer, int size, T data )
        where T : unmanaged
    {
        var span = MemoryMarshal.AsBytes(
            MemoryMarshal.CreateReadOnlySpan(ref data, 1)
        );

        span.CopyTo( buffer.Slice(size) );
        return size + span.Length;
    }

    public static int CopySpanValues<T>( Span<Byte> buffer, int size, Span<T> data )
        where T : unmanaged
    {
        foreach ( var element in data )
        {
            size = CopyValue(buffer, size, element);
        }

        return size;
    }

    public static float[] ConvertColor(Color color)
    {
        return [color.R, color.G, color.B, color.A];
    }

    public static float[] Vector(Vector3 vector)
    {
        return [ vector.X, vector.Y, vector.Z, 0.0f ]; // padding to 4 floats
    }

    public static float[] Matrix(Projection m)
    {
        return [
            m.X.X, m.X.Y, m.X.Z, m.X.W,
            m.Y.X, m.Y.Y, m.Y.Z, m.Y.W,
            m.Z.X, m.Z.Y, m.Z.Z, m.Z.W,
            m.W.X, m.W.Y, m.W.Z, m.W.W
        ];
    }

    public static float[] Matrix(Transform3D m)
    {
        return [
            m.Basis.X.X, m.Basis.X.Y, m.Basis.X.Z, 0,
            m.Basis.Y.X, m.Basis.Y.Y, m.Basis.Y.Z, 0,
            m.Basis.Z.X, m.Basis.Z.Y, m.Basis.Z.Z, 0,
            m.Origin.X,  m.Origin.Y,  m.Origin.Z,  1
        ];
    }

    public Rid CreateUniformSetMixPass0(
        RenderSceneBuffersRD render_scene_buffers
    )
    {
        var color_uniform = new RDUniform
        {
            Binding = 0,
            UniformType = RenderingDevice.UniformType.Image  
        };
        color_uniform.AddId(render_scene_buffers.GetColorLayer(0));

        var cloud_buffer_uniform = new RDUniform
        {
            Binding = 1,
            UniformType = RenderingDevice.UniformType.SamplerWithTexture  
        };
        cloud_buffer_uniform.AddId(repeat_disabled_sampler);
        cloud_buffer_uniform.AddId(cloud_display_buffer);

        return UniformSetCacheRD.GetCache(mix_shader, 0, [
            color_uniform,
            cloud_buffer_uniform
        ]);
    }

    public Rid CreateUniformSetCloudPass0(
        RenderSceneBuffersRD render_scene_buffers
    )
    {
        var cloud_buffer_uniform = new RDUniform
        {
            Binding = 0,
            UniformType = RenderingDevice.UniformType.Image  
        };
        cloud_buffer_uniform.AddId(cloud_buffer);

        var prev_cloud_buffer_uniform = new RDUniform
        {
            Binding = 3,
            UniformType = RenderingDevice.UniformType.SamplerWithTexture  
        };
        prev_cloud_buffer_uniform.AddId(repeat_disabled_sampler);
        prev_cloud_buffer_uniform.AddId(prev_cloud_buffer);

        var cloud_display_buffer_uniform = new RDUniform
        {
            Binding = 4,
            UniformType = RenderingDevice.UniformType.Image  
        };
        cloud_display_buffer_uniform.AddId(cloud_display_buffer);


        var render_data_buffer_uniform = new RDUniform
        {
            Binding = 1,
            UniformType = RenderingDevice.UniformType.UniformBuffer  
        };
        render_data_buffer_uniform.AddId(render_data_buffer);

        var depth_uniform = new RDUniform
        {
            Binding = 2,
            UniformType = RenderingDevice.UniformType.SamplerWithTexture  
        };
        depth_uniform.AddId(repeat_disabled_sampler);
        depth_uniform.AddId(render_scene_buffers.GetDepthLayer(0));

        return UniformSetCacheRD.GetCache(cloud_shader, 0, [
            cloud_buffer_uniform,
            render_data_buffer_uniform,
            depth_uniform,
            prev_cloud_buffer_uniform,
            cloud_display_buffer_uniform
        ]);
    }

    public RDUniform CreateTextureUniform(int binding, string name, Rid sampler)
    {
        var uniform = new RDUniform
        {
            Binding = binding,
            UniformType = RenderingDevice.UniformType.SamplerWithTexture
        };
        uniform.AddId(sampler);
        Rid rid = cloud_material.GetShaderParameter(name).As<Texture>().GetRid();
        Rid rd_texure_rid = RenderingServer.TextureGetRdTexture(rid);
        uniform.AddId(rd_texure_rid);
        return uniform;
    }

    public Rid CreateUniformSetCloudPass1()
    {
        // Cloud Settings
        int settings_size = 0;

        settings_size = CopySpanValues<float>(
            cloud_settings_buffer_bytes, settings_size,
            Vector(cloud_material.GetShaderParameter("bb_min").As<Vector3>())
        );

        settings_size = CopySpanValues<float>(
            cloud_settings_buffer_bytes, settings_size,
            Vector(cloud_material.GetShaderParameter("bb_max").As<Vector3>())
        );

        settings_size = CopySpanValues<float>(
            cloud_settings_buffer_bytes, settings_size,
            Vector(cloud_material.GetShaderParameter("light_direction").As<Vector3>())
        );

        settings_size = CopySpanValues<float>(
            cloud_settings_buffer_bytes, settings_size,
            ConvertColor(cloud_material.GetShaderParameter("light_color").As<Color>())
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("falloff_light").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("falloff_color").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("darkness_threshold").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("cloud_threshold").As<float>()
        );

        
        //GD.Print(cloud_material.GetShaderParameter("cloud_threshold").As<float>());

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("cloud_threshold_delta").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("cloud_density").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("cloud_scale").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("fine_scale").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("fine_blend").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("scattering_forward").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("scattering_backward").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("scattering_omnidirectional").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("scattering_directional").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("scattering_direction_blend").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("curl_noise_blend").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("curl_noise_scale").As<float>()
        );

        settings_size = CopyValue(
            cloud_settings_buffer_bytes, settings_size,
            cloud_material.GetShaderParameter("coverage_density").As<float>()
        );

        // padding
        settings_size = CopyValue(cloud_settings_buffer_bytes, settings_size,0.0f);
        settings_size = CopyValue(cloud_settings_buffer_bytes, settings_size,0.0f);
        settings_size = CopyValue(cloud_settings_buffer_bytes, settings_size,0.0f);

        Debug.Assert(settings_size % 4 == 0);

        List<RDUniform> uniform_set = new List<RDUniform>(); 

        var cloud_settings_uniform = new RDUniform
        {
            Binding = 0,
            UniformType = RenderingDevice.UniformType.StorageBuffer  
        };
        cloud_settings_uniform.AddId(cloud_settings_buffer);

        var rd = RenderingServer.GetRenderingDevice(); 

        return UniformSetCacheRD.GetCache(cloud_shader, 1, [
            cloud_settings_uniform,
            CreateTextureUniform(1, "density_texture",      repeat_enabled_sampler),
            CreateTextureUniform(2, "fine_density_texture", repeat_enabled_sampler),
            CreateTextureUniform(3, "height_texture",       repeat_disabled_sampler),
            CreateTextureUniform(4, "cloud_coverage",       repeat_enabled_sampler),
            CreateTextureUniform(5, "blue_noise",           nearest_sampler),
            CreateTextureUniform(6, "curl_noise",           repeat_enabled_sampler),
        ]);
    }

    public override void _RenderCallback(int effect_type, RenderData render_data)
    {
        if ( effect_type != (int)EffectCallbackType )
            return;

        RenderSceneBuffersRD render_scene_buffers = (RenderSceneBuffersRD)render_data.GetRenderSceneBuffers();
        RenderSceneData render_scene_data = (RenderSceneData)render_data.GetRenderSceneData();

        if ( render_scene_buffers == null )
            return;

        Vector2I buffer_size = render_scene_buffers.GetInternalSize();

        Vector2I[] offset_vectors = [
            new Vector2I(0,0),
            new Vector2I(1,1),
            new Vector2I(1,0),
            new Vector2I(0,1),
        ];

        Vector2I pixel_offset = offset_vectors[offset];

        int dispatch_denominator = 32;
        switch ( quality )
        {
        case CloudQuality.LOW:
            dispatch_denominator = 32; // half res final image, half res of that reprojected over 4 frames
            break;
        case CloudQuality.HIGH:
            dispatch_denominator = 16; // full res final image, half res of that reprojected over 4 frames
            break;
        }

        // half frame buffer (divided by 8 too for compute)
        // half again for reprojection
        int dispatch_width = buffer_size.X / dispatch_denominator; // 32 for half res buffer
        int dispatch_height = buffer_size.Y / dispatch_denominator; 

        int cloud_x = 2 * dispatch_width * 8;
        int cloud_y = 2 * dispatch_height * 8;

        Vector2 cloud_size = new Vector2(
            (float)cloud_x / (float)(cloud_buffer_x-1),
            (float)cloud_y / (float)(cloud_buffer_y-1)
        );

        byte[] push_constants = new byte[128];
        int constants_size = 0;
        constants_size = CopyValue(push_constants, constants_size, (float)Time.GetTicksMsec() / 1000.0f);
        constants_size = CopyValue(push_constants, constants_size, 0.0f);
        constants_size = CopyValue(push_constants, constants_size, pixel_offset.X);
        constants_size = CopyValue(push_constants, constants_size, pixel_offset.Y);
        constants_size = CopyValue(push_constants, constants_size, cloud_size.X);
        constants_size = CopyValue(push_constants, constants_size, cloud_size.Y);
        constants_size = CopyValue(push_constants, constants_size, offset);
        constants_size = CopyValue(push_constants, constants_size, offset);

        int render_data_buffer_size = 0;

        Transform3D camera_transform = render_scene_data.GetCamTransform();
        Transform3D inv_camera_transform = camera_transform.AffineInverse();
        Projection camera_projection = render_scene_data.GetCamProjection();
        Projection inv_camera_projection = camera_projection.Inverse();

        if ( prev_camera_projection[offset] == null )
        {
            prev_camera_projection[0] = camera_projection;
            prev_camera_projection[1] = camera_projection;
            prev_camera_projection[2] = camera_projection;
            prev_camera_projection[3] = camera_projection;
        }

        if ( prev_inv_camera_transform[offset] == null )
        {
            prev_inv_camera_transform[0] = inv_camera_transform;
            prev_inv_camera_transform[1] = inv_camera_transform;
            prev_inv_camera_transform[2] = inv_camera_transform;
            prev_inv_camera_transform[3] = inv_camera_transform;
        }

        render_data_buffer_size = CopySpanValues<float>(
            render_data_buffer_bytes, render_data_buffer_size, Matrix(camera_transform) // inv view matrix
        );

        render_data_buffer_size = CopySpanValues<float>(
            render_data_buffer_bytes, render_data_buffer_size, Matrix(inv_camera_projection) // inv proj mat
        );

        if ( render_new )
        {
            //rd.TextureCopy(cloud_buffer, prev_cloud_buffer, Vector3.Zero, Vector3.Zero, new Vector3(cloud_buffer_x, cloud_buffer_y, 1), 0, 0, 0, 0);
            prev_inv_camera_transform[offset] = inv_camera_transform;
            prev_camera_projection[offset] = camera_projection;
        }

        // prev inv view matrix
        render_data_buffer_size = CopySpanValues<float>(render_data_buffer_bytes, render_data_buffer_size, Matrix(prev_inv_camera_transform[0].Value));
        render_data_buffer_size = CopySpanValues<float>(render_data_buffer_bytes, render_data_buffer_size, Matrix(prev_inv_camera_transform[1].Value));
        render_data_buffer_size = CopySpanValues<float>(render_data_buffer_bytes, render_data_buffer_size, Matrix(prev_inv_camera_transform[2].Value));
        render_data_buffer_size = CopySpanValues<float>(render_data_buffer_bytes, render_data_buffer_size, Matrix(prev_inv_camera_transform[3].Value));

        // prev inv proj mat
        render_data_buffer_size = CopySpanValues<float>(render_data_buffer_bytes, render_data_buffer_size, Matrix(prev_camera_projection[0].Value));
        render_data_buffer_size = CopySpanValues<float>(render_data_buffer_bytes, render_data_buffer_size, Matrix(prev_camera_projection[1].Value));
        render_data_buffer_size = CopySpanValues<float>(render_data_buffer_bytes, render_data_buffer_size, Matrix(prev_camera_projection[2].Value));
        render_data_buffer_size = CopySpanValues<float>(render_data_buffer_bytes, render_data_buffer_size, Matrix(prev_camera_projection[3].Value));
        
        Debug.Assert(constants_size % 4 == 0);
        Debug.Assert(render_data_buffer_size % 4 == 0);

        
        var cloud_pass_uniform_set0 = CreateUniformSetCloudPass0(render_scene_buffers);
        var cloud_pass_uniform_set1 = CreateUniformSetCloudPass1();

        
        var rd = RenderingServer.GetRenderingDevice();

        rd.BufferUpdate(render_data_buffer, 0, (uint)render_data_buffer_bytes.Length, render_data_buffer_bytes);
        rd.BufferUpdate(cloud_settings_buffer, 0, (uint)cloud_settings_buffer_bytes.Length, cloud_settings_buffer_bytes);

        //int dispatch_width = (buffer_size.X / 8) + (buffer_size.X % 8 == 0 ? 0 : 8); 
        //int dispatch_height = (buffer_size.Y / 8) + (buffer_size.Y % 8 == 0 ? 0 : 8); 

        
        var cloud_pass = rd.ComputeListBegin();
        rd.ComputeListBindComputePipeline(cloud_pass, cloud_pipeline);
        rd.ComputeListSetPushConstant(cloud_pass, push_constants, (uint)constants_size);
        rd.ComputeListBindUniformSet(cloud_pass, cloud_pass_uniform_set0, 0);
        rd.ComputeListBindUniformSet(cloud_pass, cloud_pass_uniform_set1, 1);
        rd.ComputeListDispatch(cloud_pass, (uint)dispatch_width, (uint)dispatch_height, 1);
        rd.ComputeListEnd();

        var mix_pass_uniform_set0 = CreateUniformSetMixPass0(render_scene_buffers);

        constants_size = 0;
        constants_size = CopyValue(push_constants, constants_size, buffer_size.X);
        constants_size = CopyValue(push_constants, constants_size, buffer_size.Y);
        constants_size = CopyValue(push_constants, constants_size, cloud_size.X);
        constants_size = CopyValue(push_constants, constants_size, cloud_size.Y);

        var mix_pass = rd.ComputeListBegin();
        rd.ComputeListBindComputePipeline(mix_pass, mix_pipeline);
        rd.ComputeListSetPushConstant(mix_pass, push_constants, (uint)constants_size);
        rd.ComputeListBindUniformSet(mix_pass, mix_pass_uniform_set0, 0);
        
        int mix_dispatch_width = (buffer_size.X / 8) + (buffer_size.X % 8 == 0 ? 0 : 8); 
        int mix_dispatch_height = (buffer_size.Y / 8) + (buffer_size.Y % 8 == 0 ? 0 : 8); 

        rd.ComputeListDispatch(mix_pass, (uint)mix_dispatch_width, (uint)mix_dispatch_height, 1);
        rd.ComputeListEnd();

        

        if ( render_new )
        {
            for ( uint i = 0 ; i < 4; i++ )
            {
                rd.TextureCopy(
                    cloud_buffer, 
                    prev_cloud_buffer, 
                    Vector3.Zero, Vector3.Zero, 
                    //new Vector3(cloud_buffer_x, cloud_buffer_y, 1), 0, 0, (uint)offset, (uint)offset
                    new Vector3(cloud_buffer_x, cloud_buffer_y, 1), 0, 0, i, i
                );
            }
            
        }

        offset = (offset + 1) % 4;

    }
}
