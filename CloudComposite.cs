using Godot;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

[Tool]
public partial class CloudComposite : CompositorEffect
{
    [Export] ShaderMaterial cloud_material;

    Rid shader = new Rid();
    Rid pipeline;
    Rid repeat_enabled_sampler;
    Rid repeat_disabled_sampler;
    Rid nearest_sampler;

    Rid uniform_set0;
    Rid uniform_set1;

    RDShaderFile shader_file;
    ShaderInclude shader_file_inc;

    Mutex mutex = new Mutex();

    Rid render_data_buffer;
    byte[] render_data_buffer_bytes = new byte[128];

    Rid cloud_settings_buffer;
    byte[] cloud_settings_buffer_bytes = new byte[32 * 4];

    (string, ulong)[] dependencies = [
        ("res://Clouds.glsl", 0),
        ("res://CloudMaths.gdshaderinc", 0)
    ];

    public CloudComposite()
    {
        shader_file = GD.Load<RDShaderFile>(dependencies[0].Item1);
        shader_file_inc = GD.Load<ShaderInclude>(dependencies[1].Item1);
        shader_file.Changed += CompileShader;
        shader_file_inc.Changed += CompileShader;
        CompileShader();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationPredelete)
		{
			if (shader.IsValid)
			{
				RenderingServer.GetRenderingDevice().FreeRid(shader);
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

    void CompileShader()
    {
        var rd = RenderingServer.GetRenderingDevice();

        GD.Print("Compiling Shader...");

        //var shader_file = ResourceLoader.Load<RDShaderFile>(dependencies[0].Item1, null, ResourceLoader.CacheMode.Ignore);
        var shader_byte_code = shader_file.GetSpirV();

        if ( shader.IsValid )
        {
            rd.FreeRid(shader);
        }
        else
        {   // Only done first time
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
        }

        // Done regardless
        shader = rd.ShaderCreateFromSpirV(shader_byte_code);
        pipeline = rd.ComputePipelineCreate(shader);
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

    public Rid CreateUniformSet0(
        RenderSceneBuffersRD render_scene_buffers
    )
    {
        var color_uniform = new RDUniform
        {
            Binding = 0,
            UniformType = RenderingDevice.UniformType.Image  
        };
        color_uniform.AddId(render_scene_buffers.GetColorLayer(0));

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
        depth_uniform.AddId(repeat_enabled_sampler);
        depth_uniform.AddId(render_scene_buffers.GetDepthLayer(0));

        return UniformSetCacheRD.GetCache(shader, 0, [
            color_uniform,
            render_data_buffer_uniform,
            depth_uniform
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

    public Rid CreateUniformSet1()
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

        // Padding0, Padding1
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

        return UniformSetCacheRD.GetCache(shader, 1, [
            cloud_settings_uniform,
            CreateTextureUniform(1, "density_texture",      repeat_enabled_sampler),
            CreateTextureUniform(2, "fine_density_texture", repeat_enabled_sampler),
            CreateTextureUniform(3, "height_texture",       repeat_disabled_sampler),
            CreateTextureUniform(4, "cloud_coverage",       repeat_enabled_sampler),
            CreateTextureUniform(5, "blue_noise",           nearest_sampler),
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

        byte[] push_constants = new byte[256];
        int constants_size = 0;

        constants_size = CopyValue(push_constants, constants_size, buffer_size.X);
        constants_size = CopyValue(push_constants, constants_size, buffer_size.Y);
        constants_size = CopyValue(push_constants, constants_size, (float)Time.GetTicksMsec() / 1000.0f);
        constants_size = CopyValue(push_constants, constants_size, 0);

        int render_data_buffer_size = 0;

        float[] inv_view_matrix = Matrix(render_scene_data.GetCamTransform());
        float[] inv_proj_matrix = Matrix(render_scene_data.GetCamProjection().Inverse());

        render_data_buffer_size = CopySpanValues<float>(
            render_data_buffer_bytes, render_data_buffer_size, inv_view_matrix
        );

        render_data_buffer_size = CopySpanValues<float>(
            render_data_buffer_bytes, render_data_buffer_size, inv_proj_matrix
        );

        Debug.Assert(constants_size % 4 == 0);
        Debug.Assert(render_data_buffer_size % 4 == 0);

        
        var uniform_set0 = CreateUniformSet0(render_scene_buffers);
        var uniform_set1 = CreateUniformSet1();

        
        var rd = RenderingServer.GetRenderingDevice();

        rd.BufferUpdate(render_data_buffer, 0, (uint)render_data_buffer_bytes.Length, render_data_buffer_bytes);
        rd.BufferUpdate(cloud_settings_buffer, 0, (uint)cloud_settings_buffer_bytes.Length, cloud_settings_buffer_bytes);

        var compute_list = rd.ComputeListBegin();
        rd.ComputeListBindComputePipeline(compute_list, pipeline);
        rd.ComputeListSetPushConstant(compute_list, push_constants, (uint)constants_size);
        rd.ComputeListBindUniformSet(compute_list, uniform_set0, 0);
        rd.ComputeListBindUniformSet(compute_list, uniform_set1, 1);
        
        int dispatch_width = (buffer_size.X / 8) + (buffer_size.X % 8 == 0 ? 0 : 8); 
        int dispatch_height = (buffer_size.Y / 8) + (buffer_size.Y % 8 == 0 ? 0 : 8); 
        
        //GD.Print($"{buffer_size} - {dispatch_width} x {dispatch_height}");

        rd.ComputeListDispatch(compute_list, (uint)dispatch_width, (uint)dispatch_height, 1);
        rd.ComputeListEnd();

    }
}
