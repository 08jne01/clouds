using Godot;
using System;

public partial class Clouds : MeshInstance3D
{
    void UpdateBB()
    {
        ShaderMaterial material = Mesh.SurfaceGetMaterial(0) as ShaderMaterial;
        var bb = GetAabb();
        material.SetShaderParameter("bb_min", Position + bb.Position);
        material.SetShaderParameter("bb_max", Position + bb.End);
    }

    public override void _Ready()
    {
        var bb = GetAabb();
        GD.Print($"{Position + bb.Position} -> {Position + bb.End}");
        UpdateBB();
    }

    public override void _Process(double delta)
    {
        UpdateBB();
    }


}
