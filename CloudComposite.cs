using Godot;
using System;

[Tool]
public partial class CloudComposite : Camera3D
{
    public override void _Ready()
    {
        MeshInstance3D composite = GetNode("CloudComposite") as MeshInstance3D;
        var material = composite.Mesh.SurfaceGetMaterial(0) as ShaderMaterial;
        var viewport = GetNode("SubViewport") as SubViewport;
        viewport.TransparentBg = true;
        viewport.RenderTargetClearMode = SubViewport.ClearMode.Always;
        material.SetShaderParameter("cloud_texture", viewport.GetTexture());
    }

    public override void _Process(double delta)
    {
        var camera = GetNode("SubViewport/Camera3D") as Camera3D;
        GetViewport().GetCamera3D().CullMask = 1;
        camera.GlobalTransform = GetViewport().GetCamera3D().GlobalTransform;
        //GD.Print(camera.GlobalTransform);
    }


}
