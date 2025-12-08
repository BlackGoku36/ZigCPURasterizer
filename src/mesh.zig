const std = @import("std");
const Vec3 = @import("math/vec3.zig").Vec3;
const Vec2 = @import("math/vec2.zig").Vec2;
const Matrix4 = @import("math/matrix4.zig").Matrix4;
const Quat = @import("math/quaternion.zig").Quat;
const Gltf = @import("zgltf").Gltf;
const GltfMaterial = Gltf.Material;
const PBRMaterial = @import("material.zig").Material;

pub const MaterialInfo = struct {
    material_name: []u8,
    index_end: usize,
};

pub const Mesh = struct {
    vertices: []f32,
    uvs: [3][]f32,
    normals: []f32,
    name: []u8,
    indices_16: ?[]u16,
    indices_32: ?[]u32,
    transform: Matrix4,
    material: usize,
};

pub const LightType = enum {
    Point,
    Directional,
};

pub const Light = struct {
    pos: Vec3,
    range: f32,
    intensity: f32,
    color: Vec3,
    type: LightType,
};

pub const Camera = struct {
    view_matrix: Matrix4,
    fov: f32,
    pos: Vec3,
};

pub fn getMeshFromNode(gltf: Gltf, binary: []u8, node: Gltf.Node, meshes: *std.ArrayList(Mesh), allocator: std.mem.Allocator) !void {
    const m = gltf.data.meshes[node.mesh.?];

    //TODO: Free this memory
    const name = try allocator.alloc(u8, m.name.?.len);
    @memcpy(name, m.name.?);
    if (!std.mem.containsAtLeast(u8, node.name.?, 0, "decal")) {
        return;
    }

    var mat: Matrix4 = undefined;
    if (node.matrix) |transform| {
        mat.mat = transform;
    } else {
        const trans = Matrix4.getTranslation(node.translation[0], node.translation[1], node.translation[2]);
        const rot = Quat{
            .c = Vec3{ .x = node.rotation[0], .y = node.rotation[1], .z = node.rotation[2] },
            .r = node.rotation[3],
        };
        const scale = Matrix4.getScale(node.scale[0], node.scale[1], node.scale[2]);
        mat = Matrix4.multMatrix4(Quat.mat4FromQuat(rot), scale);
        mat = Matrix4.multMatrix4(trans, mat);
    }

    for (m.primitives) |p| {
        // TODO: primitives means subgroups of mesh and not entire mesh

        var vertices: []f32 = undefined;
        var normals: []f32 = undefined;
        var uvs: [3][]f32 = undefined;
        var indices_16: ?[]u16 = null;
        var indices_32: ?[]u32 = null;

        const indices_accessor = gltf.data.accessors[p.indices.?];
        if (indices_accessor.component_type == .unsigned_short) {
            indices_16 = try gltf.getDataFromBufferView(u16, allocator, indices_accessor, binary);
        } else {
            indices_32 = try gltf.getDataFromBufferView(u32, allocator, indices_accessor, binary);
        }

        var pbr_material_idx: usize = undefined;

        if (p.material) |material_idx| {
            pbr_material_idx = material_idx;
        } else {
            std.debug.print("No Material found for: {s}\n", .{m.name.?});
        }

        var tex_coord_count: u8 = 0;
        for (p.attributes) |a| {
            switch (a) {
                .position => |accessor_index| {
                    const accessor = gltf.data.accessors[accessor_index];
                    vertices = try gltf.getDataFromBufferView(f32, allocator, accessor, binary);
                },
                .normal => |accessor_index| {
                    const accessor = gltf.data.accessors[accessor_index];
                    normals = try gltf.getDataFromBufferView(f32, allocator, accessor, binary);
                },
                .texcoord => |accessor_index| {
                    const accessor = gltf.data.accessors[accessor_index];
                    uvs[tex_coord_count] = try gltf.getDataFromBufferView(f32, allocator, accessor, binary);
                    tex_coord_count += 1;
                },
                else => {
                    std.debug.print("Found attribute but not implemented: {}\n", .{a});
                },
            }
        }
        try meshes.append(allocator, Mesh{
            .vertices = vertices,
            .uvs = uvs,
            .normals = normals,
            .indices_16 = indices_16,
            .indices_32 = indices_32,
            .name = name,
            .transform = mat,
            .material = pbr_material_idx,
        });
    }
}

pub fn traverseGLTFNodes(gltf: Gltf, binary: []u8, node: Gltf.Node, meshes: *std.ArrayList(Mesh), allocator: std.mem.Allocator) !void {
    const children = node.children;

    for (children) |child| {
        const child_node = gltf.data.nodes[child];
        if (child_node.mesh) |_| {
            try getMeshFromNode(gltf, binary, child_node, meshes, allocator);
        }
        try traverseGLTFNodes(gltf, binary, child_node, meshes, allocator);
    }
}

pub fn getTexturedMaterialGltf(gltf: Gltf, material: GltfMaterial, parent_path: []const u8, allocator: std.mem.Allocator) !PBRMaterial {
    var color_texture_path: ?[]u8 = null;
    var metallic_rougness_texture_path: ?[]u8 = null;
    var normal_texture_path: ?[]u8 = null;
    var occlusion_texture_path: ?[]u8 = null;
    if (material.metallic_roughness.base_color_texture) |color_texture| {
        const color_texture_idx = color_texture.index;
        const color_texture_source_idx = gltf.data.textures[color_texture_idx].source.?;
        const color_texture_uri = gltf.data.images[color_texture_source_idx].uri.?;
        color_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, color_texture_uri });
    }
    if (material.metallic_roughness.metallic_roughness_texture) |metallic_rougness_texture| {
        const texture_idx = metallic_rougness_texture.index;
        const metallic_rougness_texture_source_idx = gltf.data.textures[texture_idx].source.?;
        const metallic_rougness_texture_uri = gltf.data.images[metallic_rougness_texture_source_idx].uri.?;
        metallic_rougness_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, metallic_rougness_texture_uri });
    }
    if (material.normal_texture) |normal_texture| {
        const texture_idx = normal_texture.index;
        const normal_texture_source_idx = gltf.data.textures[texture_idx].source.?;
        const normal_texture_uri = gltf.data.images[normal_texture_source_idx].uri.?;
        normal_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, normal_texture_uri });
    }
    if (material.occlusion_texture) |occlusion_texture| {
        const texture_idx = occlusion_texture.index;
        const occlusion_texture_source_idx = gltf.data.textures[texture_idx].source.?;
        const occlusion_texture_uri = gltf.data.images[occlusion_texture_source_idx].uri.?;
        occlusion_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, occlusion_texture_uri });
    }
    std.debug.print("Has Color Texture: {}\n", .{color_texture_path != null});
    std.debug.print("Has Metallic-Roughness Texture: {}\n", .{metallic_rougness_texture_path != null});
    std.debug.print("Has Normal Texture: {}\n", .{normal_texture_path != null});
    std.debug.print("Has Occlusion Texture: {}\n", .{occlusion_texture_path != null});

    var pbr_material = PBRMaterial.fromGltfTextureFiles(
        color_texture_path,
        metallic_rougness_texture_path,
        normal_texture_path,
        allocator,
    );

    pbr_material.tex_coord = @intCast(material.metallic_roughness.base_color_texture.?.texcoord);
    std.debug.print("TEXCOORD: {d}\n", .{pbr_material.tex_coord});

    return pbr_material;
}

pub const Meshes = struct {
    meshes: std.ArrayList(Mesh),
    // TODO: Move this out of here
    materials: std.ArrayList(PBRMaterial),
    lights: std.ArrayList(Light),
    cameras: std.ArrayList(Camera),

    pub fn fromGLTFFile(fileName: []const u8, allocator: std.mem.Allocator) !Meshes {
        const parent_path = std.fs.path.dirname(fileName).?;

        var meshes: std.ArrayList(Mesh) = .{};
        var materials: std.ArrayList(PBRMaterial) = .{};
        var lights: std.ArrayList(Light) = .{};
        var cameras: std.ArrayList(Camera) = .{};

        const buffer = std.fs.cwd().readFileAllocOptions(allocator, fileName, 5_000_000, null, std.mem.Alignment.@"4", null) catch |err| {
            std.debug.print("Couldn't open glTF's file {s} : {any}\n", .{ fileName, err });
            return err;
        };
        defer allocator.free(buffer);

        var gltf = Gltf.init(allocator);
        defer gltf.deinit();

        try gltf.parse(buffer);

        const bin_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, gltf.data.buffers[0].uri.? });
        defer allocator.free(bin_path);
        std.debug.print("Binary Path: {s}\n", .{bin_path});

        const binary = std.fs.cwd().readFileAllocOptions(allocator, bin_path, 14_00_00_001, null, std.mem.Alignment.@"4", null) catch |err| {
            std.debug.print("Couldn't open glTF's binary file {s} : {any}\n", .{ bin_path, err });
            return err;
        };
        defer allocator.free(binary);

        for (gltf.data.materials) |material| {
            std.debug.print("Material Name: {s}\n", .{material.name orelse "name_less"});
            var pbr_material: PBRMaterial = undefined;
            if (material.metallic_roughness.base_color_texture != null) {
                pbr_material = try getTexturedMaterialGltf(gltf, material, parent_path, allocator);
            } else {
                var rgb: [3]f32 = [_]f32{ 0.0, 0.0, 0.0 };
                rgb[0] = material.metallic_roughness.base_color_factor[0];
                rgb[1] = material.metallic_roughness.base_color_factor[1];
                rgb[2] = material.metallic_roughness.base_color_factor[2];
                pbr_material = PBRMaterial.fromGltfConstants(
                    material.name orelse "name_less material",
                    rgb,
                    material.metallic_roughness.metallic_factor,
                    material.metallic_roughness.roughness_factor,
                    0.1,
                );
            }

            try materials.append(allocator, pbr_material);
        }

        for (gltf.data.scenes) |scene| {
            if (scene.nodes) |root_nodes| {
                for (root_nodes) |root_node| {
                    const node = gltf.data.nodes[root_node];
                    if (node.mesh) |_| {
                        try getMeshFromNode(gltf, binary, node, &meshes, allocator);
                    } else if (node.light) |light_idx| {
                        // const light_pos = node.translation;
                        const light = gltf.data.lights[light_idx];
                        if (light.type == .directional) {
                            // const q = Quat{ .c = Vec3{ .x = node.rotation[0], .y = node.rotation[1], .z = node.rotation[2] }, .r = node.rotation[3] };
                            // const v = Vec3{ .x = 0.0, .y = 0.0, .z = -1.0 };
                            // const direction = Matrix4.multVec3(Quat.mat4FromQuat(q), v);
                            // try lights.append(allocator, Light{
                            //     .color = Vec3{ .x = light.color[0], .y = light.color[1], .z = light.color[2] },
                            //     .pos = direction,
                            //     .intensity = 0.8, //light.intensity,
                            //     .range = 10.0, //light.range,
                            //     .type = .Directional,
                            // });
                        } else if (light.type == .point) {
                            try lights.append(allocator, Light{
                                .color = Vec3{ .x = light.color[0], .y = light.color[1], .z = light.color[2] },
                                .pos = Vec3{ .x = node.translation[0], .y = node.translation[1], .z = node.translation[2] },
                                .intensity = 1.5, //light.intensity,
                                .range = 10.0, //light.range,
                                .type = .Point,
                            });
                        } else {
                            std.debug.print("TODO: Spot Light not supported!\n", .{});
                        }

                        std.debug.print("Light Type: {}\n", .{light.type});
                        std.debug.print("Light intensity, range: {d}, {d}\n\n", .{ light.intensity, light.range });
                    } else if (node.camera) |camera_idx| {
                        const camera = gltf.data.cameras[camera_idx];
                        const pos = Vec3{ .x = node.translation[0], .y = node.translation[1], .z = node.translation[2] };
                        var fov: f32 = 0.0;

                        switch (camera.type) {
                            .perspective => |p| {
                                fov = p.yfov;
                                // aspect_ratio = p.aspect_ratio.?;
                            },
                            .orthographic => {
                                std.debug.panic("Orthographic Projection Not Implemented!\n", .{});
                            },
                        }

                        std.debug.print("Camera name: {s}\n", .{node.name.?});

                        if (node.matrix) |matrix| {
                            var view_mat = Matrix4.getIdentity();
                            view_mat.mat = matrix;
                            view_mat.print();
                            try cameras.append(allocator, Camera{
                                .view_matrix = view_mat,
                                .fov = fov,
                                .pos = pos,
                            });
                        } else {
                            const rot = Quat{ .c = Vec3{ .x = node.rotation[0], .y = node.rotation[1], .z = node.rotation[2] }, .r = node.rotation[3] };
                            const c_trans = Matrix4.getTranslation(pos.x, pos.y, pos.z);
                            const c_rot = Quat.mat4FromQuat(rot);
                            const view_mat = Matrix4.invert(Matrix4.multMatrix4(c_trans, c_rot));
                            std.debug.print("Pos: {}, {}, {}\n", .{ pos.x, pos.y, pos.z });
                            std.debug.print("Quat: {}, {}, {}, {}\n", .{ rot.c.x, rot.c.y, rot.c.z, rot.r });
                            try cameras.append(allocator, Camera{
                                .view_matrix = view_mat,
                                .fov = fov,
                                .pos = pos,
                            });
                        }
                    }
                    try traverseGLTFNodes(gltf, binary, node, &meshes, allocator);
                }
            }
        }
        return Meshes{
            .meshes = meshes,
            .materials = materials,
            .lights = lights,
            .cameras = cameras,
        };
    }
};
