using Godot;
using System;

[Tool]
public partial class Clouds : MeshInstance3D
{
    [Export] DirectionalLight3D light;
    [Export] Resource scene;


    [Export] Vector3I worley_texture_size = new Vector3I(128,128,128);
    [Export] Vector4I worley_square_size = new Vector4I(8,16,32,64);

    [Export] Vector3I worley_fine_texture_size = new Vector3I(32,32,32);
    [Export] Vector4I worley_fine_square_size = new Vector4I(2,4,8,16);

    [Export] Vector2I worley_coverage_texture_size = new Vector2I(32,32);
    [Export] Vector4I worley_coverage_square_size = new Vector4I(2,4,8,16);

    [Export]
    public bool Generate
    {
        get => false;
        set
        {
            GenerateNoise();
        }
    }

    Worley.WorleyCompute worley_compute;
    Worley.WorleyCompute worley_fine_compute;

    Worley.WorleyCompute worley_coverage_compute;

    void GenerateNoise()
    {
        GenerateNoise(ref worley_compute, worley_texture_size, worley_square_size);
        GenerateNoise(ref worley_fine_compute, worley_fine_texture_size, worley_fine_square_size);
        GenerateNoise(ref worley_coverage_compute, new Vector3I(worley_coverage_texture_size.X, worley_coverage_texture_size.Y, 1), worley_coverage_square_size);

        ShaderMaterial material = Mesh.SurfaceGetMaterial(0) as ShaderMaterial;
        material.SetShaderParameter("density_texture", new Texture3Drd
        {
            TextureRdRid = worley_compute.texture
        });

        material.SetShaderParameter("fine_density_texture", new Texture3Drd
        {
            TextureRdRid = worley_fine_compute.texture
        });

        // material.SetShaderParameter("cloud_coverage", new Texture2Drd
        // {
        //     TextureRdRid = worley_coverage_compute.texture
        // });
    }

    static void GenerateNoise(
        ref Worley.WorleyCompute compute,
        Vector3I worley_texture_size,
        Vector4I worley_square_size
    )
    {
        Rid texture = new Rid();
        if ( compute.shader.IsValid )
        {
            Worley.FreeButKeepTexture(compute);
            texture = compute.texture;
        }


        compute = Worley.Generate(
            (uint)worley_texture_size.X,
            (uint)worley_texture_size.Y,
            (uint)worley_texture_size.Z,
            worley_square_size
        );

        Worley.Dispatch(compute);

        if ( texture.IsValid )
            RenderingServer.GetRenderingDevice().FreeRid(texture);
    }

    void UpdateShader()
    {
        ShaderMaterial material = Mesh.SurfaceGetMaterial(0) as ShaderMaterial;
        var bb = GetAabb();
        material.SetShaderParameter("bb_min", Position + bb.Position);
        material.SetShaderParameter("bb_max", Position + bb.End);
        material.SetShaderParameter("light_direction", light.Basis.Column2);

        // var parameters = RenderingServer.GetShaderParameterList(material.Shader.GetRid());
        // foreach ( var parameter in parameters )
        // {
        //     GD.Print(parameter);
        // }
    }

    public override void _Ready()
    {
        var bb = GetAabb();
        GD.Print($"{Position + bb.Position} -> {Position + bb.End}");
        GenerateNoise();

        UpdateShader();
    }

    public override void _Process(double delta)
    {
        UpdateShader();

        GetViewport().GetCamera3D().Near = 0.1f;
        GetViewport().GetCamera3D().Far = 40000.0f;
    }


}
