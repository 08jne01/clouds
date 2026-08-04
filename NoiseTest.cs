using Godot;
using System;

public partial class NoiseTest : CanvasLayer
{
    [Export]
    public bool Generate
    {
        get => false;
        set
        {
            Dispatch();
        }
    }

    [Export] uint width = 32;
    [Export] uint height = 32;
    [Export] Vector4I square_size2d = new Vector4I(8,8,8,8);


    [Export] uint width3d = 128;
    [Export] uint height3d = 128;
    [Export] uint depth3d = 128;
    [Export] Vector4I square_size3d = new Vector4I(8,8,8,8);



    Worley.WorleyCompute compute2d;
    Worley.WorleyCompute compute3d;

    public void Dispatch()
    {
        compute2d.square_size = square_size2d;
        compute3d.square_size = square_size3d;

        if ( compute2d.shader.IsValid )
            Worley.Dispatch(compute2d);

        if ( compute3d.shader.IsValid )
            Worley.Dispatch(compute3d);
    }

    public override void _Ready()
    {
        compute2d = Worley.Generate(width, height, 1, square_size2d);
        compute3d = Worley.Generate(width3d, height3d, depth3d, square_size3d);

        Texture2Drd texture2d = new Texture2Drd
        {
            TextureRdRid = compute2d.texture
        };

        Texture3Drd texture3d = new Texture3Drd
        {
            TextureRdRid = compute3d.texture
        };

        GetNode<TextureRect>("TextureDisplay").Texture = texture2d;



        var material = GetNode<ColorRect>("TextureDisplay3D").Material as ShaderMaterial;
        material.SetShaderParameter("texture_input", texture3d);
    }

    ~NoiseTest()
    {
        Worley.FreeButKeepTexture(compute2d);
        Worley.FreeButKeepTexture(compute3d);
        RenderingServer.GetRenderingDevice().FreeRid(compute2d.texture);
        RenderingServer.GetRenderingDevice().FreeRid(compute3d.texture);
    }


}
