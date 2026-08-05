using Godot;
using System;
using System.Diagnostics;

public static class Worley
{
    public struct WorleyCompute
    {
        public Rid shader;
        public Rid pipeline;
        public Rid texture;
        public Rid texture_uniform_set;

        public uint width;
        public uint height;
        public uint depth;
        public Vector4I square_size;
    };

    // Width and height must be divisible by 8
    public static WorleyCompute Generate(uint width, uint height, uint depth, Vector4I square_size)
    {
        Debug.Assert(width % 8 == 0);
        Debug.Assert(height % 8 == 0);

        var rd = RenderingServer.GetRenderingDevice();

        WorleyCompute compute;

        compute.width = width;
        compute.height = height;
        compute.depth = depth;
        compute.square_size = square_size;    

        var shader_file = GD.Load<RDShaderFile>(depth == 1 ? "res://Worley2D.glsl" : "res://Worley3D.glsl");
        var shader_byte_code = shader_file.GetSpirV();
        
        compute.shader = rd.ShaderCreateFromSpirV(shader_byte_code);
        compute.pipeline = rd.ComputePipelineCreate(compute.shader);

        var texture_format = new RDTextureFormat
        {
            Format = RenderingDevice.DataFormat.R8G8B8A8Unorm,
            TextureType = depth == 1 ? RenderingDevice.TextureType.Type2D : RenderingDevice.TextureType.Type3D,
            Width = width,
            Height = height,
            Depth = depth,
            ArrayLayers = 1,
            Mipmaps = 1,
            UsageBits = 
                RenderingDevice.TextureUsageBits.StorageBit | 
                RenderingDevice.TextureUsageBits.CanUpdateBit | 
                RenderingDevice.TextureUsageBits.CanCopyToBit |
                RenderingDevice.TextureUsageBits.SamplingBit |
                RenderingDevice.TextureUsageBits.ColorAttachmentBit
        };

        compute.texture = rd.TextureCreate(texture_format, new RDTextureView());
        GD.Print(depth);
        //rd.TextureClear(compute.texture, new Color(0,0,0,0), 0, 1, 0, depth);

        var uniform = new RDUniform
        {
            UniformType = RenderingDevice.UniformType.Image,
            Binding = 0
        };

        uniform.AddId(compute.texture);

        compute.texture_uniform_set = rd.UniformSetCreate([uniform], compute.shader, 0);   
        return compute;
    }

    public static void Dispatch(WorleyCompute compute)
    {
        byte[] push_constants = new byte[16];

        BitConverter.GetBytes(compute.square_size.X).CopyTo(push_constants, 0);
        BitConverter.GetBytes(compute.square_size.Y).CopyTo(push_constants, 4);
        BitConverter.GetBytes(compute.square_size.Z).CopyTo(push_constants, 8);
        BitConverter.GetBytes(compute.square_size.W).CopyTo(push_constants, 12);

        var rd = RenderingServer.GetRenderingDevice();
        var compute_list = rd.ComputeListBegin();
        rd.ComputeListBindComputePipeline(compute_list, compute.pipeline);
        rd.ComputeListBindUniformSet(compute_list, compute.texture_uniform_set, 0);
        rd.ComputeListSetPushConstant(compute_list, push_constants, (uint)push_constants.Length);

        if ( compute.depth == 1 )
        {
            rd.ComputeListDispatch(compute_list, compute.width / 8, compute.height / 8, 1);
        }
        else
        {
            rd.ComputeListDispatch(compute_list, compute.width / 8, compute.height / 8, compute.depth / 8);
        }

        rd.ComputeListEnd();
    }

    public static void FreeButKeepTexture(WorleyCompute compute)
    {
        var rd = RenderingServer.GetRenderingDevice();
        rd.FreeRid(compute.shader);
        rd.FreeRid(compute.pipeline);
        rd.FreeRid(compute.texture_uniform_set);
    }
}
