using Godot;
using System;

public partial class ClipMap : Node3D
{
    //https://developer.nvidia.com/gpugems/gpugems2/part-i-geometric-complexity/chapter-2-terrain-rendering-using-gpu-based-geometry
    // names taken from that paper
    ArrayMesh block;
    ArrayMesh horizontal_ring_fix_up;
    ArrayMesh vertical_ring_fix_up;
    ArrayMesh horizontal_interior_trim;
    ArrayMesh vertical_interior_trim;

    [Export] public int m = 4;
    [Export] public int n_levels = 3;

    [Export] Material material;


    [Export] Material mat_block;
    [Export] Material mat_fix_up;
    [Export] Material mat_trim;

    [Export] Node3D marker;

    struct ClipMapLevel
    {
        public ClipMapLevel() {}
        public ShaderMaterial material;
        public Node3D mesh_parent;
        public MeshInstance3D trim_x;
        public MeshInstance3D trim_y;
    };

    ClipMapLevel[] maps;

    Shader shader = GD.Load<Shader>("res://ClipMap.gdshader");

    // See grid-coords.png
    Vector2I[] block_positions;
    Vector2I[] horizontal_ring_fix_up_positions;
    Vector2I[] vertical_ring_fix_up_positions;
    Vector2I[] horizontal_interior_trim_positions;
    Vector2I[] vertical_interior_trim_positions;

    void CalculatePositions()
    {
        int b = m - 1; //block width
        
        // coords are given in the equivelent of the m = 4 example

        int c3 = b;
        int c6 = 2*b;
        int c8 = 2*b+2;
        int c11 = 3*b+2;
        int c10 = c11 - 1;

        block_positions = [
            new Vector2I(0,0),  
            new Vector2I(c3,0),  
            new Vector2I(c8,0),
            new Vector2I(c11,0),

            new Vector2I(0,c3),
            new Vector2I(c11,c3),

            new Vector2I(0,c8),
            new Vector2I(c11,c8),

            new Vector2I(0,c11),
            new Vector2I(c3,c11),
            new Vector2I(c8,c11),
            new Vector2I(c11,c11),
        ];

        horizontal_ring_fix_up_positions = [
            new Vector2I(0,c6),
            new Vector2I(c11,c6),
        ];

        vertical_ring_fix_up_positions = [
            new Vector2I(c6,0),
            new Vector2I(c6,c11),
        ];

        horizontal_interior_trim_positions = [
            new Vector2I(c3,c3),
        ];

        vertical_interior_trim_positions = [
            new Vector2I(c10,c3),
        ];
    }

    static ArrayMesh CreateMesh(int nx, int ny)
    {
        int n_vertices = nx * ny;
        int n_faces = (nx - 1) * (ny - 1);
        int n_indices = n_faces * 2 * 3;

        Vector3[] vertices = new Vector3[n_vertices];
        Vector3[] normals = new Vector3[n_vertices];
        Vector2[] tex_coords = new Vector2[n_vertices];
        int[] indices = new int[n_indices];

        for ( int i = 0; i < nx; i++ )
        {
            float u_frac = (float)i / (float)(nx - 1);

            for ( int j = 0; j < ny; j++ )
            {
                float v_frac = (float)j / (float)(ny - 1);
                
                int index = i + j * nx;

                vertices[index] = new Vector3(i, 0, j);
                normals[index] = Vector3.Up;
                tex_coords[index] = new Vector2(u_frac, v_frac);
            }
        }

        // Wound Clockwise
        int t = 0;
        for ( int face = 0; face < n_faces; face++ )
        {
            // gets offset by 1 each row so we have to add the number of rows
            int i = face + face / (nx - 1);

            indices[t++] = i + 1;
            indices[t++] = i + nx;
            indices[t++] = i;

            indices[t++] = i + 1;
            indices[t++] = i + nx + 1;
            indices[t++] = i + nx;
        }

        ArrayMesh array_mesh = new ArrayMesh();
        Godot.Collections.Array surface_array = [];
        surface_array.Resize((int)Mesh.ArrayType.Max);

        surface_array[(int)Mesh.ArrayType.Vertex] = vertices;
        surface_array[(int)Mesh.ArrayType.TexUV] = tex_coords;
        surface_array[(int)Mesh.ArrayType.Normal] = normals;
        surface_array[(int)Mesh.ArrayType.Index] = indices;

        array_mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, surface_array);
        return array_mesh;
    }

    public MeshInstance3D CreateTrim(Node3D parent, int scale, ArrayMesh mesh, Vector2I position)
    {
        var instance = new MeshInstance3D();
        instance.Position = GridPosition(scale, position, m);
        instance.Scale = new Vector3(scale, 1, scale);
        instance.Mesh = mesh;
        parent.AddChild(instance);
        return instance;
    }

    static Vector2I GridPosition(int scale, Vector2I position)
    {
        return new Vector2I(scale * position.X, scale * position.Y);
    }

    static int SideLength(int m)
    {
        // 4 blocks (m-1) each, then 2
        return 4 * m - 2;
    }

    static int HalfSize(int m, int scale)
    {
        int n = 4 * m - 1;
        int half_size = (n - 1) / 2 - 1;
        return half_size * scale;
    }

    static Vector3 GridPosition(int scale, Vector2I position, int m)
    {
        Vector3 local_position = new Vector3(position.X, 0, position.Y) - 2.0f * new Vector3(m-1, 0, m-1);
        return local_position * scale;
    }

    public void CreateMeshes(Node3D parent, int scale, ArrayMesh mesh, Span<Vector2I> positions)
    {
        var meshes = new MeshInstance3D[positions.Length];

        for ( int i = 0; i < positions.Length; i++ )
        {
            meshes[i] = new MeshInstance3D();
            meshes[i].Position = GridPosition(scale, positions[i], m);
            meshes[i].Scale = new Vector3(scale, 1, scale);
            meshes[i].Mesh = mesh;
            parent.AddChild(meshes[i]);
        }
    }

    ClipMapLevel CreateMap(int level)
    {
        ClipMapLevel map = new ClipMapLevel();
        var shader_material = new ShaderMaterial();
        shader_material.Shader = shader;
        shader_material.SetShaderParameter("height_map_course", GD.Load<Texture2D>("res://Test.tres"));
        shader_material.SetShaderParameter("height_map_fine", GD.Load<Texture2D>("res://HeightMap.tres"));
        map.material = shader_material;
        map.mesh_parent = new Node3D();

        block = CreateMesh(m, m);
        horizontal_ring_fix_up = CreateMesh(m, 3);
        vertical_ring_fix_up = CreateMesh(3, m);
        horizontal_interior_trim = CreateMesh(2*m + 1, 2);
        vertical_interior_trim = CreateMesh(2, 2*m + 1);

        bool debug_view = false;
        if ( debug_view )
        {
            block.SurfaceSetMaterial(0, mat_block);
            horizontal_ring_fix_up.SurfaceSetMaterial(0, mat_fix_up);
            vertical_ring_fix_up.SurfaceSetMaterial(0, mat_fix_up);
            horizontal_interior_trim.SurfaceSetMaterial(0, mat_trim);
            vertical_interior_trim.SurfaceSetMaterial(0, mat_trim);
        }
        else
        {
            block.SurfaceSetMaterial(0, map.material);
            horizontal_ring_fix_up.SurfaceSetMaterial(0, map.material);
            vertical_ring_fix_up.SurfaceSetMaterial(0, map.material);
            horizontal_interior_trim.SurfaceSetMaterial(0, map.material);
            vertical_interior_trim.SurfaceSetMaterial(0, map.material);
        }

        

        

        // MeshInstance3D mesh = new MeshInstance3D();
        // mesh.Position = Vector3.Zero;
        // mesh.Mesh = interior_trim;

        

        int scale = 1 << level;

        CreateMeshes(map.mesh_parent, scale, block, block_positions);
        CreateMeshes(map.mesh_parent, scale, horizontal_ring_fix_up, horizontal_ring_fix_up_positions);
        CreateMeshes(map.mesh_parent, scale, vertical_ring_fix_up, vertical_ring_fix_up_positions);

        map.trim_x = CreateTrim(map.mesh_parent, scale, horizontal_interior_trim, horizontal_interior_trim_positions[0]);
        map.trim_y = CreateTrim(map.mesh_parent, scale, vertical_interior_trim, vertical_interior_trim_positions[0]);

        AddChild(map.mesh_parent);

        //map.horizontal_interior_trims   = CreateMeshes(horizontal_interior_trim, horizontal_interior_trim_positions);
        //map.vertical_interior_trims     = CreateMeshes(vertical_interior_trim, vertical_interior_trim_positions);

        return map;
    }

    static Vector2I PositionLevel(int level, Vector3 position)
    {
        // twice our scale
        int scale = 2 << level;

        position /= scale;

        position = position.Floor();
        position *= scale;

        int x = (int)position.X;
        int z = (int)position.Z;

        return new Vector2I(x, z);
    }

    void UpdateMap(int level, ClipMapLevel map, Vector3 position)
    {
        Vector2I grid_position = PositionLevel(level, position);
        Vector2I grid_position_fine = PositionLevel(level-1, position);

        int scale = 1 << level;


        Vector2I difference = grid_position - grid_position_fine;

        int b = m - 1; //block width
        
        // coords are given in the equivelent of the m = 4 example
        int c3 = b;
        int c11 = 3*b+2;
        int c10 = c11 - 1;

        if ( difference.Y == 0 )
        {
            map.trim_x.Position = GridPosition(scale, new Vector2I(c3, c10), m);
        }
        else
        {
            map.trim_x.Position = GridPosition(scale, new Vector2I(c3, c3), m);
        }

        if ( difference.X == 0 )
        {
            map.trim_y.Position = GridPosition(scale, new Vector2I(c10, c3), m);
        }
        else
        {
            map.trim_y.Position = GridPosition(scale, new Vector2I(c3, c3), m);
        }


        ///GD.Print($"{grid_position} -> {grid_position_fine} = {grid_position - grid_position_fine}");

        Vector2I grid_origin = GridPosition(scale, grid_position);

        int corner_difference = 2 * scale * (m-1);

        map.material.SetShaderParameter("map_position", new Vector4(
            grid_position.X - corner_difference, grid_position.Y - corner_difference, 
            SideLength(m) * scale,
            corner_difference
        ));
        map.material.SetShaderParameter("level", (uint)(level-1));
        map.mesh_parent.Position = new Vector3(grid_position.X, 0, grid_position.Y);// - new Vector3(7, 0, 7) * scale;
    }

    Rid pipeline;
    Rid compute_shader;
    Rid texture;
    Rid uniform_set;
    Rid positions_buffer;
    Rid uniform_set_positions_buffer;
    Texture2DArrayRD texture_rd;

    void InitCompute()
    {
        var rd = RenderingServer.GetRenderingDevice();
        
        var shaderFile = GD.Load<RDShaderFile>("res://Heightmap.glsl");
        var shaderBytecode = shaderFile.GetSpirV();
        compute_shader = rd.ShaderCreateFromSpirV(shaderBytecode);
        pipeline = rd.ComputePipelineCreate(compute_shader);

        uint w = 4 * (uint)m;
        uint h = w;

        var texture_format = new RDTextureFormat
        {
            Format = RenderingDevice.DataFormat.R32Sfloat,
            TextureType = RenderingDevice.TextureType.Type2DArray,
            Width = w,
            Height = h,
            Depth = 1,
            ArrayLayers = (uint)n_levels,
            Mipmaps = 1,
            UsageBits = 
                RenderingDevice.TextureUsageBits.StorageBit | 
                RenderingDevice.TextureUsageBits.CanUpdateBit | 
                RenderingDevice.TextureUsageBits.CanCopyToBit |
                RenderingDevice.TextureUsageBits.SamplingBit |
                RenderingDevice.TextureUsageBits.ColorAttachmentBit
        };

        texture = rd.TextureCreate(texture_format, new RDTextureView());
        rd.TextureClear(texture, new Color(0,0,0,0), 0, 1, 0, (uint)n_levels);

       

        var uniform = new RDUniform
        {
            UniformType = RenderingDevice.UniformType.Image,
            Binding = 0,
        };

        uniform.AddId(texture);
        uniform_set = rd.UniformSetCreate([uniform], compute_shader, 0);


        positions_buffer = rd.StorageBufferCreate((uint)(n_levels) * 4 * sizeof(uint));
        var uniform_buffer = new RDUniform
        {
            UniformType = RenderingDevice.UniformType.StorageBuffer,
            Binding = 0,
        };

        uniform_buffer.AddId(positions_buffer);
        uniform_set_positions_buffer = rd.UniformSetCreate([uniform_buffer], compute_shader, 1);
    }

    void Compute()
    {
        uint w = 4 * (uint)m;
        uint h = w;

        GD.Print($"{w} - {h}");

        //int scale = 1 << maps.Length;

        var push_constant = new int[3];
        //Vector3 origin = LevelOrigin(maps.Length-1);
        push_constant[0] = 0;
        push_constant[1] = 0;
        push_constant[2] = 4 * m - 2;

        int[] map_positions = new int[n_levels * 4];


        for ( int i = 0; i < n_levels; i++ )
        {
            int scale = 1 << i;
            Vector3 origin = LevelOrigin(i);
            map_positions[4 * i + 0] = (int)origin.X;
            map_positions[4 * i + 1] = (int)origin.Z;
            map_positions[4 * i + 2] = (4 * m - 2) * scale * 2;

            GD.Print($"Level: {i} ({origin.X},{origin.Z}) {map_positions[4 * i + 2]}");

            map_positions[4 * i + 3] = (m-1)*scale;
        }

        var input_bytes = new byte[map_positions.Length * sizeof(int)];
        Buffer.BlockCopy(map_positions, 0, input_bytes, 0, input_bytes.Length);


        var rd = RenderingServer.GetRenderingDevice();

        rd.BufferUpdate(positions_buffer, 0, (uint)input_bytes.Length, input_bytes);

        var compute_list = rd.ComputeListBegin();
        rd.ComputeListBindComputePipeline(compute_list, pipeline);
        rd.ComputeListBindUniformSet(compute_list, uniform_set, 0);
        rd.ComputeListBindUniformSet(compute_list, uniform_set_positions_buffer, 1);
        rd.ComputeListSetPushConstant(compute_list, GD.VarToBytes(push_constant), (uint)push_constant.Length * 4);
        rd.ComputeListDispatch(compute_list, (uint)m / 2, (uint)m / 2, (uint)n_levels);
        rd.ComputeListEnd();

        texture_rd = new Texture2DArrayRD
        {
            TextureRdRid = texture
        };
    }

    public Vector3 LevelOrigin(int level)
    {
        int scale = 1 << (level+1);
        return maps[level].mesh_parent.Position - new Vector3(m-1, 0, m-1) * scale * 2;
    }

    public override void _Ready()
    {
       InitCompute();
       

        maps = new ClipMapLevel[n_levels];
        CalculatePositions();
        //GetViewport().DebugDraw = Viewport.DebugDrawEnum.Wireframe;

        for ( int i = 0; i < maps.Length; i++ )
        {
            maps[i] = CreateMap(i+1);

            int scale = 1 << i;

            //maps[i].mesh_parent.Position -= new Vector3(3, 0, 3) * scale * 2;
            GD.Print($"Texture RID {texture}");
        }

        Compute();

        for ( int i = 0; i < maps.Length; i++ )
        {
            maps[i].material.SetShaderParameter("test", texture_rd);
        }

        

        //GetTree().CurrentScene.GetNode<TextureRect>("HeightMapDisplay").Texture = texture_rd.GetLayerData(0);

        //mesh.SetSurfaceOverrideMaterial(0, material);

        //AddChild(mesh);

    
    }

    public override void _Process(double delta)
    {
        Vector3 position = Vector3.Zero;// GetViewport().GetCamera3D().Position;
        for ( int i = 0; i < maps.Length; i++ )
        {
            UpdateMap(i+1, maps[i], position);
        }

        for ( int i = 0; i < maps.Length-1; i++ )
        {
            Vector3 origin = LevelOrigin(i+1);
            maps[i].material.SetShaderParameter(
                "parent_position",
                new Vector2I((int)origin.X, (int)origin.Z)
            );
        }


        int element = 2;

        int n = 4 * m - 2;
        int scale = 1 << element;

        if ( marker != null )
            marker.Position = LevelOrigin(element) + new Vector3(n * scale * 2, 0, 0);
    }


}
