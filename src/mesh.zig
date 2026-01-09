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
    uvs_count: u8,
    normals: []f32,
    name: []u8,
    indices_16: ?[]u16,
    indices_32: ?[]u32,
    transform: Matrix4,
    material: ?usize,
    should_render: bool = true,
};

pub const LightType = enum {
    Point,
    Directional,
    Area,
};

pub const Light = struct {
    pos: Vec3,
    range: f32,
    intensity: f32,
    color: Vec3,
    type: LightType,
    verts: ?[4]Vec3 = null,
};

pub const CameraType = enum { Perspective, Orthogonal };

pub const Camera = struct {
    view_matrix: Matrix4,
    fov: f32,
    pos: Vec3,
    type: CameraType,
    xmag: f32 = 0.0,
    ymag: f32 = 0.0,
};

pub fn getMatrixFromNode(node: Gltf.Node, parent_matrix: Matrix4) Matrix4 {
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

    return Matrix4.multMatrix4(parent_matrix, mat);
}

pub fn getMeshFromNode(
    gltf: Gltf,
    binary: []u8,
    node: Gltf.Node,
    parent_matrix: Matrix4,
    // materials: std.ArrayList(PBRMaterial),
    opaque_meshes: *std.ArrayList(Mesh),
    transcluent_meshes: *std.ArrayList(Mesh),
    allocator: std.mem.Allocator,
) !void {
    const m = gltf.data.meshes[node.mesh.?];

    //TODO: Free this memory
    const name = try allocator.alloc(u8, m.name.?.len);
    @memcpy(name, m.name.?);
    if (!std.mem.containsAtLeast(u8, node.name.?, 0, "decal")) {
        return;
    }

    const transform = getMatrixFromNode(node, parent_matrix);

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
                .color => {
                    std.debug.print("Color attribute found! Must color_factor by this! Not Implemented Yet!\n", .{});
                },
                else => {
                    std.debug.print("Found attribute but not implemented: {}\n", .{a});
                },
            }
        }

        const new_normals = try allocator.alloc(f32, normals.len);
        allocator.free(normals);

        var indices_len: usize = 0;
        if (indices_16) |indice_16| {
            indices_len = indice_16.len;
        } else if (indices_32) |indice_32| {
            indices_len = indice_32.len;
        }

        var i: usize = 0;
        while (i < indices_len) : (i += 3) {
            var idx1: usize = 0;
            var idx2: usize = 0;
            var idx3: usize = 0;
            if (indices_16) |indice_16| {
                idx1 = @intCast(indice_16[i]);
                idx2 = @intCast(indice_16[i + 1]);
                idx3 = @intCast(indice_16[i + 2]);
            } else if (indices_32) |indice_32| {
                idx1 = @intCast(indice_32[i]);
                idx2 = @intCast(indice_32[i + 1]);
                idx3 = @intCast(indice_32[i + 2]);
            }

            const vert1 = Vec3{ .x = vertices[idx1 * 3 + 0], .y = vertices[idx1 * 3 + 1], .z = vertices[idx1 * 3 + 2] };
            const vert2 = Vec3{ .x = vertices[idx2 * 3 + 0], .y = vertices[idx2 * 3 + 1], .z = vertices[idx2 * 3 + 2] };
            const vert3 = Vec3{ .x = vertices[idx3 * 3 + 0], .y = vertices[idx3 * 3 + 1], .z = vertices[idx3 * 3 + 2] };

            const edge1 = Vec3.sub(vert1, vert2);
            const edge2 = Vec3.sub(vert2, vert3);

            const cross = Vec3.cross(edge1, edge2);

            new_normals[idx1 * 3 + 0] += cross.x;
            new_normals[idx2 * 3 + 0] += cross.x;
            new_normals[idx3 * 3 + 0] += cross.x;

            new_normals[idx1 * 3 + 1] += cross.y;
            new_normals[idx2 * 3 + 1] += cross.y;
            new_normals[idx3 * 3 + 1] += cross.y;

            new_normals[idx1 * 3 + 2] += cross.z;
            new_normals[idx2 * 3 + 2] += cross.z;
            new_normals[idx3 * 3 + 2] += cross.z;
        }

        // if (p.material) |material| {
        const material = gltf.data.materials[p.material.?];
        if (material.transmission_factor > 0.0 or material.transmission_texture != null) {
            try transcluent_meshes.append(allocator, Mesh{
                .vertices = vertices,
                .uvs = uvs,
                .uvs_count = tex_coord_count,
                .normals = new_normals,
                .indices_16 = indices_16,
                .indices_32 = indices_32,
                .name = name,
                .transform = transform,
                .material = p.material,
            });
        } else {
            try opaque_meshes.append(allocator, Mesh{
                .vertices = vertices,
                .uvs = uvs,
                .uvs_count = tex_coord_count,
                .normals = new_normals,
                .indices_16 = indices_16,
                .indices_32 = indices_32,
                .name = name,
                .transform = transform,
                .material = p.material,
            });
        }
        // }

        // try meshes.append(allocator, Mesh{
        //     .vertices = vertices,
        //     .uvs = uvs,
        //     .uvs_count = tex_coord_count,
        //     .normals = new_normals,
        //     .indices_16 = indices_16,
        //     .indices_32 = indices_32,
        //     .name = name,
        //     .transform = transform,
        //     .material = p.material,
        // });
    }
}

pub fn traverseGLTFNodes(gltf: Gltf, binary: []u8, node: Gltf.Node, parent_matrix: Matrix4, opaque_meshes: *std.ArrayList(Mesh), transcluent_meshes: *std.ArrayList(Mesh), allocator: std.mem.Allocator) !void {
    const children = node.children;

    const transform = getMatrixFromNode(node, parent_matrix);

    for (children) |child| {
        const child_node = gltf.data.nodes[child];
        if (child_node.mesh) |_| {
            try getMeshFromNode(gltf, binary, child_node, transform, opaque_meshes, transcluent_meshes, allocator);
        }
        try traverseGLTFNodes(gltf, binary, child_node, transform, opaque_meshes, transcluent_meshes, allocator);
    }
}

pub fn getTexturedMaterialGltf(gltf: Gltf, material: GltfMaterial, parent_path: []const u8, allocator: std.mem.Allocator) !PBRMaterial {
    var color_texture_path: ?[]u8 = null;
    var metallic_rougness_texture_path: ?[]u8 = null;
    var normal_texture_path: ?[]u8 = null;
    var occlusion_texture_path: ?[]u8 = null;
    var emissive_texture_path: ?[]u8 = null;
    var transmission_texture_path: ?[]u8 = null;

    if (material.metallic_roughness.base_color_texture) |color_texture| {
        const color_texture_idx = color_texture.index;
        const color_texture_source_idx = gltf.data.textures[color_texture_idx].source.?;
        const color_texture_uri = gltf.data.images[color_texture_source_idx].uri.?;
        color_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, color_texture_uri });
        color_texture_path = std.Uri.percentDecodeInPlace(color_texture_path.?);
    }

    if (material.metallic_roughness.metallic_roughness_texture) |metallic_rougness_texture| {
        const texture_idx = metallic_rougness_texture.index;
        const metallic_rougness_texture_source_idx = gltf.data.textures[texture_idx].source.?;
        const metallic_rougness_texture_uri = gltf.data.images[metallic_rougness_texture_source_idx].uri.?;
        metallic_rougness_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, metallic_rougness_texture_uri });
        metallic_rougness_texture_path = std.Uri.percentDecodeInPlace(metallic_rougness_texture_path.?);
    }

    var normal_strength: f32 = 1.0;
    if (material.normal_texture) |normal_texture| {
        const texture_idx = normal_texture.index;
        const normal_texture_source_idx = gltf.data.textures[texture_idx].source.?;
        const normal_texture_uri = gltf.data.images[normal_texture_source_idx].uri.?;
        normal_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, normal_texture_uri });
        normal_texture_path = std.Uri.percentDecodeInPlace(normal_texture_path.?);
        normal_strength = normal_texture.scale;
    }

    var occlusion_strength: f32 = 1.0;
    if (material.occlusion_texture) |occlusion_texture| {
        const texture_idx = occlusion_texture.index;
        const occlusion_texture_source_idx = gltf.data.textures[texture_idx].source.?;
        const occlusion_texture_uri = gltf.data.images[occlusion_texture_source_idx].uri.?;
        occlusion_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, occlusion_texture_uri });
        occlusion_texture_path = std.Uri.percentDecodeInPlace(occlusion_texture_path.?);
        occlusion_strength = occlusion_texture.strength;
    }

    if (material.emissive_texture) |emissive_texture| {
        const texture_idx = emissive_texture.index;
        const emissive_texture_source_idx = gltf.data.textures[texture_idx].source.?;
        const emissive_texture_uri = gltf.data.images[emissive_texture_source_idx].uri.?;
        emissive_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, emissive_texture_uri });
        emissive_texture_path = std.Uri.percentDecodeInPlace(emissive_texture_path.?);
    }

    if (material.transmission_texture) |transmission_texture| {
        const texture_idx = transmission_texture.index;
        const transmission_texture_source_idx = gltf.data.textures[texture_idx].source.?;
        const transmission_texture_uri = gltf.data.images[transmission_texture_source_idx].uri.?;
        transmission_texture_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_path, transmission_texture_uri });
        transmission_texture_path = std.Uri.percentDecodeInPlace(transmission_texture_path.?);
    }

    std.debug.print("Has Color Texture: {}\n", .{color_texture_path != null});
    std.debug.print("Has Metallic-Roughness Texture: {}\n", .{metallic_rougness_texture_path != null});
    std.debug.print("Has Normal Texture: {}\n", .{normal_texture_path != null});
    std.debug.print("Has Occlusion Texture: {}\n", .{occlusion_texture_path != null});
    std.debug.print("Has Emissive Texture: {}\n", .{emissive_texture_path != null});
    std.debug.print("Has Transmission Texture: {}\n", .{transmission_texture_path != null});

    var pbr_material = PBRMaterial.fromGltfTextureFiles(
        //TODO: Right now, name only lives as long as gltf lives.
        // Handle names for textures and objects properly so they
        // can be easily reference later
        material.name,
        color_texture_path,
        metallic_rougness_texture_path,
        occlusion_texture_path,
        normal_texture_path,
        emissive_texture_path,
        transmission_texture_path,
        material.emissive_strength,
        material.metallic_roughness.base_color_factor,
        normal_strength,
        material.metallic_roughness.metallic_factor,
        material.metallic_roughness.roughness_factor,
        occlusion_strength,
        material.emissive_factor,
        material.alpha_cutoff,
        material.transmission_factor,
        material.ior,
        allocator,
    );

    if (color_texture_path) |texture_path| {
        allocator.free(texture_path);
        std.debug.print("TEXCOORD: {d}\n", .{pbr_material.tex_coord});
        //TODO: Each texture has it own texcoord index, handle them all.
        pbr_material.tex_coord = @intCast(material.metallic_roughness.base_color_texture.?.texcoord);
    }
    if (metallic_rougness_texture_path) |texture_path| allocator.free(texture_path);
    if (normal_texture_path) |texture_path| allocator.free(texture_path);
    if (occlusion_texture_path) |texture_path| allocator.free(texture_path);
    if (emissive_texture_path) |texture_path| allocator.free(texture_path);
    if (transmission_texture_path) |texture_path| allocator.free(texture_path);

    return pbr_material;
}

pub const Scene = struct {
    opaque_meshes: std.ArrayList(Mesh),
    translucent_meshes: std.ArrayList(Mesh),
    // TODO: Move this out of here
    materials: std.ArrayList(PBRMaterial),
    lights: std.ArrayList(Light),
    cameras: std.ArrayList(Camera),

    pub fn fromGLTFFile(fileName: []const u8, allocator: std.mem.Allocator) !Scene {
        const parent_path = std.fs.path.dirname(fileName).?;

        var opaque_meshes: std.ArrayList(Mesh) = .{};
        var translucent_meshes: std.ArrayList(Mesh) = .{};
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

        const binary = std.fs.cwd().readFileAllocOptions(allocator, bin_path, 54_00_00_001, null, std.mem.Alignment.@"4", null) catch |err| {
            std.debug.print("Couldn't open glTF's binary file {s} : {any}\n", .{ bin_path, err });
            return err;
        };
        defer allocator.free(binary);

        for (gltf.data.materials) |material| {
            std.debug.print("Material Name: {s}\n", .{material.name orelse "name_less"});
            //TODO: Handle "double sided" property
            var pbr_material: PBRMaterial = undefined;
            if (material.metallic_roughness.base_color_texture != null or
                material.metallic_roughness.metallic_roughness_texture != null or
                material.normal_texture != null)
            {
                pbr_material = try getTexturedMaterialGltf(gltf, material, parent_path, allocator);
            } else {
                var rgb: [3]f32 = [_]f32{ 0.0, 0.0, 0.0 };
                rgb[0] = material.metallic_roughness.base_color_factor[0];
                rgb[1] = material.metallic_roughness.base_color_factor[1];
                rgb[2] = material.metallic_roughness.base_color_factor[2];

                var emissive_rgb: [3]f32 = [_]f32{ 0.0, 0.0, 0.0 };
                emissive_rgb[0] = material.emissive_factor[0] * material.emissive_strength;
                emissive_rgb[1] = material.emissive_factor[1] * material.emissive_strength;
                emissive_rgb[2] = material.emissive_factor[2] * material.emissive_strength;
                pbr_material = PBRMaterial.fromGltfConstants(
                    material.name orelse "name_less material",
                    rgb,
                    material.metallic_roughness.metallic_factor,
                    material.metallic_roughness.roughness_factor,
                    0.1,
                    emissive_rgb,
                    material.transmission_factor,
                    material.ior,
                );
            }

            try materials.append(allocator, pbr_material);
        }

        for (gltf.data.scenes) |scene| {
            if (scene.nodes) |root_nodes| {
                for (root_nodes) |root_node| {
                    const node = gltf.data.nodes[root_node];

                    const matrix = Matrix4.getIdentity();

                    if (node.mesh) |_| {
                        try getMeshFromNode(gltf, binary, node, matrix, &opaque_meshes, &translucent_meshes, allocator);
                        if (node.name) |node_name| {
                            if (std.mem.startsWith(u8, node_name, "arealight_")) {
                                const m = opaque_meshes.items[@as(u32, @intCast(opaque_meshes.items.len)) - 1];
                                opaque_meshes.items[@as(u32, @intCast(opaque_meshes.items.len)) - 1].should_render = false;

                                var area_idx1: usize = 0;
                                var area_idx2: usize = 0;
                                var area_idx5: usize = 0;
                                var area_idx6: usize = 0;

                                if (m.indices_16) |indice_16| {
                                    area_idx1 = @intCast(indice_16[0]);
                                    area_idx2 = @intCast(indice_16[1]);
                                    area_idx5 = @intCast(indice_16[4]);
                                    area_idx6 = @intCast(indice_16[5]);
                                } else if (m.indices_32) |indice_32| {
                                    area_idx1 = @intCast(indice_32[0]);
                                    area_idx2 = @intCast(indice_32[1]);
                                    area_idx5 = @intCast(indice_32[4]);
                                    area_idx6 = @intCast(indice_32[5]);
                                }

                                var area_vert1 = Vec3{ .x = m.vertices[area_idx1 * 3 + 0], .y = m.vertices[area_idx1 * 3 + 1], .z = m.vertices[area_idx1 * 3 + 2] };
                                var area_vert2 = Vec3{ .x = m.vertices[area_idx2 * 3 + 0], .y = m.vertices[area_idx2 * 3 + 1], .z = m.vertices[area_idx2 * 3 + 2] };
                                var area_vert3 = Vec3{ .x = m.vertices[area_idx5 * 3 + 0], .y = m.vertices[area_idx5 * 3 + 1], .z = m.vertices[area_idx5 * 3 + 2] };
                                var area_vert4 = Vec3{ .x = m.vertices[area_idx6 * 3 + 0], .y = m.vertices[area_idx6 * 3 + 1], .z = m.vertices[area_idx6 * 3 + 2] };

                                const transform = getMatrixFromNode(node, matrix);
                                area_vert1 = Matrix4.multVec3(transform, area_vert1);
                                area_vert2 = Matrix4.multVec3(transform, area_vert2);
                                area_vert3 = Matrix4.multVec3(transform, area_vert3);
                                area_vert4 = Matrix4.multVec3(transform, area_vert4);

                                const material_idx = m.material.?;
                                const mesh_material = materials.items[material_idx];
                                const emission = mesh_material.pbr_solid.?.emissive;

                                // const mesh_idx = node.mesh.?;
                                try lights.append(allocator, Light{
                                    .pos = Vec3.init(0.0),
                                    .range = 0.0,
                                    .intensity = 5.0,
                                    .color = Vec3{ .x = emission.x, .y = emission.y, .z = emission.z },
                                    .type = .Area,
                                    .verts = [4]Vec3{ area_vert1, area_vert2, area_vert3, area_vert4 },
                                });
                            }
                        }
                    } else if (node.light) |light_idx| {
                        // const light_pos = node.translation;
                        const light = gltf.data.lights[light_idx];
                        if (light.type == .directional) {
                            // const q = Quat{ .c = Vec3{ .x = node.rotation[0], .y = node.rotation[1], .z = node.rotation[2] }, .r = node.rotation[3] };
                            // const v = Vec3{ .x = 0.0, .y = 0.0, .z = -1.0 };
                            // const direction = Matrix4.multVec3(Quat.mat4FromQuat(q), v);
                            // TODO: Try convert the color to linear space by color^2.22
                            // try lights.append(allocator, Light{
                            //     .color = Vec3{ .x = light.color[0], .y = light.color[1], .z = light.color[2] },
                            //     .pos = direction,
                            //     .intensity = 0.8, //light.intensity,
                            //     .range = 10.0, //light.range,
                            //     .type = .Directional,
                            // });
                        } else if (light.type == .point) {
                            std.debug.print("light color: {} {} {}\n", .{ light.color[0], light.color[1], light.color[2] });
                            std.debug.print("light intensity: {}\n", .{light.intensity});
                            std.debug.print("light range: {}\n", .{light.range});
                            try lights.append(allocator, Light{
                                .color = Vec3{
                                    .x = light.color[0],
                                    .y = light.color[1],
                                    .z = light.color[2],
                                },
                                .pos = Vec3{ .x = node.translation[0], .y = node.translation[1], .z = node.translation[2] },
                                .intensity = light.intensity * 0.001,
                                .range = light.range,
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
                        var xmag: f32 = 0.0;
                        var ymag: f32 = 0.0;
                        var camera_type: CameraType = undefined;

                        switch (camera.type) {
                            .perspective => |p| {
                                fov = p.yfov;
                                camera_type = .Perspective;
                            },
                            .orthographic => |o| {
                                camera_type = .Orthogonal;
                                xmag = o.xmag;
                                ymag = o.ymag;
                            },
                        }

                        std.debug.print("Camera name: {s}\n", .{node.name.?});

                        if (node.matrix) |mat| {
                            var view_mat = Matrix4.getIdentity();
                            view_mat.mat = mat;
                            view_mat.print();
                            try cameras.append(allocator, Camera{
                                .view_matrix = view_mat,
                                .fov = fov,
                                .pos = pos,
                                .xmag = xmag,
                                .ymag = ymag,
                                .type = camera_type,
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
                                .xmag = xmag,
                                .ymag = ymag,
                                .type = camera_type,
                            });
                        }
                    }

                    try traverseGLTFNodes(gltf, binary, node, matrix, &opaque_meshes, &translucent_meshes, allocator);
                }
            }
        }
        if (cameras.items.len == 0) {
            const pos = Vec3{ .x = 2.0, .y = 2.0, .z = 2.0 };
            try cameras.append(allocator, Camera{
                .fov = 45.0,
                .pos = pos,
                .view_matrix = Matrix4.lookAt(pos, Vec3.init(0.0), Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 }),
                .type = .Perspective,
            });
        }
        if (lights.items.len == 0) {
            try lights.append(allocator, Light{
                .color = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
                .pos = Vec3{ .x = 1.0, .y = 3.0, .z = 1.0 },
                // .pos = Vec3.normalize(Vec3.sub(Vec3.init(1.0), Vec3.init(0.0))),
                .intensity = 50.0, //light.intensity,
                .range = 10.0, //light.range,
                // .type = .Directional,
                .type = .Point,
            });
        }
        return Scene{
            .opaque_meshes = opaque_meshes,
            .translucent_meshes = translucent_meshes,
            .materials = materials,
            .lights = lights,
            .cameras = cameras,
        };
    }

    pub fn deinit(meshes: *Scene, allocator: std.mem.Allocator) void {
        for (meshes.materials.items) |material| {
            material.deinit(allocator);
        }
        meshes.materials.deinit(allocator);

        for (meshes.opaque_meshes.items) |mesh| {
            allocator.free(mesh.vertices);
            allocator.free(mesh.normals);
            for (0..mesh.uvs_count) |i| {
                allocator.free(mesh.uvs[i]);
            }
            if (mesh.indices_16) |indices| {
                allocator.free(indices);
            } else {
                allocator.free(mesh.indices_32.?);
            }
        }
        for (meshes.translucent_meshes.items) |mesh| {
            allocator.free(mesh.vertices);
            allocator.free(mesh.normals);
            for (0..mesh.uvs_count) |i| {
                allocator.free(mesh.uvs[i]);
            }
            if (mesh.indices_16) |indices| {
                allocator.free(indices);
            } else {
                allocator.free(mesh.indices_32.?);
            }
        }
        meshes.opaque_meshes.deinit(allocator);
        meshes.translucent_meshes.deinit(allocator);
        meshes.lights.deinit(allocator);
        meshes.cameras.deinit(allocator);
    }
};
