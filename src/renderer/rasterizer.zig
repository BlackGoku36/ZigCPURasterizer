const std = @import("std");
const zigimg = @import("zigimg");
const obj = @import("zig-obj");

const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec4 = @import("../math/vec4.zig").Vec4;
const Vec2 = @import("../math/vec2.zig").Vec2;
const Matrix4 = @import("../math/matrix4.zig").Matrix4;
const Quat = @import("../math/quaternion.zig").Quat;

const geometry = @import("geometry.zig");
const Vertex = geometry.Vertex;
const Tri = geometry.Tri;

const rendertarget = @import("rendertarget.zig");
const RenderTargetRGBA16 = rendertarget.RenderTargetRGBA16;
const RenderTargetR16 = rendertarget.RenderTargetR16;
const Color = rendertarget.Color;

const TextureR = @import("../utils/texture.zig").TextureR;
const TextureRGB = @import("../utils/texture.zig").TextureRGB;
const TexturePBR = @import("../utils/texture.zig").TexturePBR;
const PBRSolid = @import("../utils/texture.zig").PBRSolid;
const RGB = @import("../utils/texture.zig").RGB;
const PBR = @import("../utils/texture.zig").PBR;
const PBRTextureDescriptor = @import("../utils/texture.zig").PBRTextureDescriptor;

const shaders = @import("shaders.zig");

const material_import = @import("../material.zig");
const Materials = material_import.Materials;
const Material = material_import.Material;

const Mesh = @import("../mesh.zig").Mesh;
const Scene = @import("../mesh.zig").Scene;

const ltc = @import("ltc_lut.zig");
const LTC1 = ltc.LTC1Vec;
const LTC2 = ltc.LTC2Vec;

// pub const width = 1280;
// pub const height = 720;
pub const width = 1500;
pub const height = 750;

const WindingOrder = enum { CW, CCW };

const AABB = struct {
    min_x: u32,
    max_x: u32,
    min_y: u32,
    max_y: u32,

    fn getFrom(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) ?AABB {
        var min_x = @min(ax, bx, cx);
        var min_y = @min(ay, by, cy);
        // min_x = @max(min_x, 0.0);
        // min_y = @max(min_y, 0.0);

        var max_x = @max(ax, bx, cx);
        var max_y = @max(ay, by, cy);
        // max_x = @min(max_x, width);
        // max_y = @min(max_y, height);

        if (min_x > width - 1 or max_x < 0 or min_y > height - 1 or max_y < 0) {
            return null;
        } else {
            min_x = @max(0.0, min_x);
            max_x = @min(width - 1, max_x);
            min_y = @max(0.0, min_y);
            max_y = @min(height - 1, max_y);

            return AABB{ .min_x = @intFromFloat(min_x), .min_y = @intFromFloat(min_y), .max_x = @intFromFloat(max_x), .max_y = @intFromFloat(max_y) };
        }
    }
};

fn edgeFunction(a: Vec3, b: Vec3, px: f32, py: f32) f32 {
    return (px - a.x) * (b.y - a.y) - (py - a.y) * (b.x - a.x);
}

fn windingOrderTest(order: WindingOrder, w0: f32, w1: f32, w2: f32) bool {
    if (order == WindingOrder.CCW) {
        return (w0 >= 0 and w1 >= 0 and w2 >= 0);
    } else {
        return (w0 < 0 and w1 < 0 and w2 < 0);
    }
}

fn windingOrderNone(_: WindingOrder, w0: f32, w1: f32, w2: f32) bool {
    return (w0 >= 0 and w1 >= 0 and w2 >= 0) or
        (w0 <= 0 and w1 <= 0 and w2 <= 0);
}

pub var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();
pub var opaque_fb: RenderTargetRGBA16 = undefined;
pub var transcluent_fb: RenderTargetRGBA16 = undefined;
pub var depth_buffer: RenderTargetR16 = undefined;

var scene: Scene = undefined;

var tex_width_f32: f32 = 0.0;
var tex_height_f32: f32 = 0.0;
const aspect_ratio: f32 = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

const winding_order = WindingOrder.CCW;

var camera_pos = Vec3{ .x = -3.0, .y = 1.0, .z = 0.0 };

var projection_mat: Matrix4 = undefined;
var view_mat: Matrix4 = undefined;

var tris: std.ArrayList(Tri) = .{};

pub fn init() !void {
    // meshes = try Meshes.fromGLTFFile("cannon_01_2k/cannon_01_2k.gltf", allocator);
    // scene = try Scene.fromGLTFFile("assets/main_sponza/NewSponza_Main_glTF_003.gltf", allocator);
    // scene = try Scene.fromGLTFFile("assets/new_sponza/Untitled.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("assets/slum/Untitled.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("assets/arealight_test/Untitled.gltf", allocator);
    scene = try Scene.fromGLTFFile("assets/junkshop_temp/thejunkshopsplashscreen-2.gltf", allocator);
    // meshes = try Meshes.fromGLTFFile("assets/pokedstudio/pokedstudio.gltf", allocator);
    // scene = try Scene.fromGLTFFile("assets/bistro/Untitled.gltf", allocator);
    // scene = try Scene.fromGLTFFile("assets/transparency_test/Untitled.gltf", allocator);
    // scene = try Scene.fromGLTFFile("assets/bust/Untitled.gltf", allocator);
    opaque_fb = RenderTargetRGBA16.create(allocator, width, height);
    transcluent_fb = RenderTargetRGBA16.create(allocator, width, height);
    depth_buffer = RenderTargetR16.create(allocator, width, height);
    const c = scene.cameras.items[0];
    camera_pos = c.pos;
    view_mat = c.view_matrix;
    if (c.type == .Perspective) {
        projection_mat = Matrix4.perspectiveProjection(c.fov, aspect_ratio, 0.1, 100.0);
    } else {
        const adjusted_xmag = c.ymag * aspect_ratio;
        projection_mat = Matrix4.orthogonalProjection(-adjusted_xmag, adjusted_xmag, c.ymag, -c.ymag, 0.1, 1000.0);
    }
}

pub fn process_meshes(meshes: std.ArrayList(Mesh), vp_matrix: Matrix4) !void {
    tris.clearRetainingCapacity();

    for (meshes.items) |mesh| {
        if (!mesh.should_render) continue;

        const model_mat = mesh.transform;
        const model_view_projection_mat = Matrix4.multMatrix4(vp_matrix, model_mat);

        var indices_len: usize = 0;
        if (mesh.indices_16) |indice_16| {
            indices_len = indice_16.len;
        } else if (mesh.indices_32) |indice_32| {
            indices_len = indice_32.len;
        }

        // std.debug.print("Mesh name: {s}\n", .{mesh.name});
        var active_material: Material = undefined;
        if (mesh.material) |material_idx| {
            active_material = scene.materials.items[material_idx];
        } else {
            active_material = Material{
                .pbr_solid = PBRSolid{
                    .albedo = RGB{ .x = 1.0, .y = 0.0, .z = 0.0 },
                    .metallic = 0.5,
                    .roughness = 0.5,
                    .ao = 0.1,
                    .emissive = RGB{ .x = 1.0, .y = 1.0, .z = 1.0 },
                    .transmission = 0.0,
                    .ior = 1.5,
                },
                .pbr_texture = null,
                .name = "Material Less",
                .tex_coord = 0,
                .type = .Solid,
            };
        }

        var i: u32 = 0;
        while (i < indices_len) : (i += 3) {
            var idx1: usize = 0;
            var idx2: usize = 0;
            var idx3: usize = 0;
            if (mesh.indices_16) |indice_16| {
                idx1 = @intCast(indice_16[i]);
                idx2 = @intCast(indice_16[i + 1]);
                idx3 = @intCast(indice_16[i + 2]);
            } else if (mesh.indices_32) |indice_32| {
                idx1 = @intCast(indice_32[i]);
                idx2 = @intCast(indice_32[i + 1]);
                idx3 = @intCast(indice_32[i + 2]);
            }

            const vert1 = Vec3{ .x = mesh.vertices[idx1 * 3 + 0], .y = mesh.vertices[idx1 * 3 + 1], .z = mesh.vertices[idx1 * 3 + 2] };
            const vert2 = Vec3{ .x = mesh.vertices[idx2 * 3 + 0], .y = mesh.vertices[idx2 * 3 + 1], .z = mesh.vertices[idx2 * 3 + 2] };
            const vert3 = Vec3{ .x = mesh.vertices[idx3 * 3 + 0], .y = mesh.vertices[idx3 * 3 + 1], .z = mesh.vertices[idx3 * 3 + 2] };

            const norm1 = Vec3{ .x = mesh.normals[idx1 * 3 + 0], .y = mesh.normals[idx1 * 3 + 1], .z = mesh.normals[idx1 * 3 + 2] };
            const norm2 = Vec3{ .x = mesh.normals[idx2 * 3 + 0], .y = mesh.normals[idx2 * 3 + 1], .z = mesh.normals[idx2 * 3 + 2] };
            const norm3 = Vec3{ .x = mesh.normals[idx3 * 3 + 0], .y = mesh.normals[idx3 * 3 + 1], .z = mesh.normals[idx3 * 3 + 2] };

            //TODO: Instead of doing if statement, create seperate pipeline for meshes with no uvs
            var uv1: Vec2 = undefined;
            var uv2: Vec2 = undefined;
            var uv3: Vec2 = undefined;
            if (active_material.type == .Textured) {
                const mesh_uv = mesh.uvs[active_material.tex_coord];
                uv1 = Vec2{ .x = mesh_uv[idx1 * 2 + 0], .y = mesh_uv[idx1 * 2 + 1] };
                uv2 = Vec2{ .x = mesh_uv[idx2 * 2 + 0], .y = mesh_uv[idx2 * 2 + 1] };
                uv3 = Vec2{ .x = mesh_uv[idx3 * 2 + 0], .y = mesh_uv[idx3 * 2 + 1] };
            } else {
                uv1 = Vec2{ .x = 0.5, .y = 0.5 };
                uv2 = Vec2{ .x = 0.5, .y = 0.5 };
                uv3 = Vec2{ .x = 0.5, .y = 0.5 };
            }

            const tan1 = geometry.calculateTangent(vert1, vert2, vert3, uv1, uv2, uv3);
            const tan2 = geometry.calculateTangent(vert2, vert3, vert1, uv2, uv3, uv1);
            const tan3 = geometry.calculateTangent(vert3, vert1, vert2, uv3, uv1, uv2);

            const normalMatrix = Matrix4.transpose(Matrix4.invert(model_mat));

            const newNorm1 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm1));
            const newNorm2 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm2));
            const newNorm3 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm3));

            var newTan1 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan1));
            var newTan2 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan2));
            var newTan3 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan3));

            // T = normalize(T - dot(T, N) * N);
            newTan1 = Vec3.normalize(Vec3.sub(newTan1, Vec3.multf(newNorm1, Vec3.dot(newTan1, newNorm1))));
            newTan2 = Vec3.normalize(Vec3.sub(newTan2, Vec3.multf(newNorm2, Vec3.dot(newTan2, newNorm2))));
            newTan3 = Vec3.normalize(Vec3.sub(newTan3, Vec3.multf(newNorm3, Vec3.dot(newTan3, newNorm3))));

            const newBitan1 = Vec3.normalize(Vec3.cross(newTan1, newNorm1));
            const newBitan2 = Vec3.normalize(Vec3.cross(newTan2, newNorm2));
            const newBitan3 = Vec3.normalize(Vec3.cross(newTan3, newNorm3));

            const world_pos1 = Matrix4.multVec3(model_mat, vert1);
            const world_pos2 = Matrix4.multVec3(model_mat, vert2);
            const world_pos3 = Matrix4.multVec3(model_mat, vert3);

            const proj_vert1 = Matrix4.multVec4(model_view_projection_mat, vert1);
            const proj_vert2 = Matrix4.multVec4(model_view_projection_mat, vert2);
            const proj_vert3 = Matrix4.multVec4(model_view_projection_mat, vert3);

            var tri: Tri = undefined;
            tri.v0 = Vertex{ .position = proj_vert1, .world_position = world_pos1, .normal = newNorm1, .uv = uv1, .tangent = newTan1, .bitangent = newBitan1 };
            tri.v1 = Vertex{ .position = proj_vert2, .world_position = world_pos2, .normal = newNorm2, .uv = uv2, .tangent = newTan2, .bitangent = newBitan2 };
            tri.v2 = Vertex{ .position = proj_vert3, .world_position = world_pos3, .normal = newNorm3, .uv = uv3, .tangent = newTan3, .bitangent = newBitan3 };
            tri.material_idx = @intCast(mesh.material.?);

            try tris.append(allocator, tri);
        }
    }
}

pub fn render_opaque_meshes(view_projection_mat: Matrix4) !void {
    for (scene.opaque_meshes.items) |mesh| {
        if (!mesh.should_render) continue;

        // const model_mat = Matrix4.multMatrix4(rot_mat, mesh.transform);
        // _ = theta;
        const model_mat = mesh.transform;

        const model_view_projection_mat = Matrix4.multMatrix4(view_projection_mat, model_mat);

        var indices_len: usize = 0;
        if (mesh.indices_16) |indice_16| {
            indices_len = indice_16.len;
        } else if (mesh.indices_32) |indice_32| {
            indices_len = indice_32.len;
        }

        // std.debug.print("Mesh name: {s}\n", .{mesh.name});
        var active_material: Material = undefined;
        if (mesh.material) |material_idx| {
            active_material = scene.materials.items[material_idx];
        } else {
            active_material = Material{
                .pbr_solid = PBRSolid{
                    .albedo = RGB{ .x = 1.0, .y = 0.0, .z = 0.0 },
                    .metallic = 0.5,
                    .roughness = 0.5,
                    .ao = 0.1,
                    .emissive = RGB{ .x = 1.0, .y = 1.0, .z = 1.0 },
                    .transmission = 1.0,
                    .ior = 1.5,
                },
                .pbr_texture = null,
                .name = "Material Less",
                .tex_coord = 0,
                .type = .Solid,
            };
        }

        var i: u32 = 0;
        while (i < indices_len) : (i += 3) {
            var idx1: usize = 0;
            var idx2: usize = 0;
            var idx3: usize = 0;
            if (mesh.indices_16) |indice_16| {
                idx1 = @intCast(indice_16[i]);
                idx2 = @intCast(indice_16[i + 1]);
                idx3 = @intCast(indice_16[i + 2]);
            } else if (mesh.indices_32) |indice_32| {
                idx1 = @intCast(indice_32[i]);
                idx2 = @intCast(indice_32[i + 1]);
                idx3 = @intCast(indice_32[i + 2]);
            }

            const vert1 = Vec3{ .x = mesh.vertices[idx1 * 3 + 0], .y = mesh.vertices[idx1 * 3 + 1], .z = mesh.vertices[idx1 * 3 + 2] };
            const vert2 = Vec3{ .x = mesh.vertices[idx2 * 3 + 0], .y = mesh.vertices[idx2 * 3 + 1], .z = mesh.vertices[idx2 * 3 + 2] };
            const vert3 = Vec3{ .x = mesh.vertices[idx3 * 3 + 0], .y = mesh.vertices[idx3 * 3 + 1], .z = mesh.vertices[idx3 * 3 + 2] };

            const norm1 = Vec3{ .x = mesh.normals[idx1 * 3 + 0], .y = mesh.normals[idx1 * 3 + 1], .z = mesh.normals[idx1 * 3 + 2] };
            const norm2 = Vec3{ .x = mesh.normals[idx2 * 3 + 0], .y = mesh.normals[idx2 * 3 + 1], .z = mesh.normals[idx2 * 3 + 2] };
            const norm3 = Vec3{ .x = mesh.normals[idx3 * 3 + 0], .y = mesh.normals[idx3 * 3 + 1], .z = mesh.normals[idx3 * 3 + 2] };

            // const norm1 = Vec3.normalize(Vec3.cross(Vec3.sub(vert1, vert2), Vec3.sub(vert1, vert3)));
            // const norm2 = Vec3.normalize(Vec3.cross(Vec3.sub(vert2, vert3), Vec3.sub(vert2, vert1)));
            // const norm3 = Vec3.normalize(Vec3.cross(Vec3.sub(vert3, vert1), Vec3.sub(vert3, vert2)));

            //TODO: Instead of doing if statement, create seperate pipeline for meshes with no uvs
            var uv1: Vec2 = undefined;
            var uv2: Vec2 = undefined;
            var uv3: Vec2 = undefined;
            if (active_material.type == .Textured) {
                const mesh_uv = mesh.uvs[active_material.tex_coord];
                uv1 = Vec2{ .x = mesh_uv[idx1 * 2 + 0], .y = mesh_uv[idx1 * 2 + 1] };
                uv2 = Vec2{ .x = mesh_uv[idx2 * 2 + 0], .y = mesh_uv[idx2 * 2 + 1] };
                uv3 = Vec2{ .x = mesh_uv[idx3 * 2 + 0], .y = mesh_uv[idx3 * 2 + 1] };
            } else {
                uv1 = Vec2{ .x = 0.5, .y = 0.5 };
                uv2 = Vec2{ .x = 0.5, .y = 0.5 };
                uv3 = Vec2{ .x = 0.5, .y = 0.5 };
            }

            const tan1 = geometry.calculateTangent(vert1, vert2, vert3, uv1, uv2, uv3);
            const tan2 = geometry.calculateTangent(vert2, vert3, vert1, uv2, uv3, uv1);
            const tan3 = geometry.calculateTangent(vert3, vert1, vert2, uv3, uv1, uv2);

            const normalMatrix = Matrix4.transpose(Matrix4.invert(model_mat));

            const newNorm1 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm1));
            const newNorm2 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm2));
            const newNorm3 = Vec3.normalize(Matrix4.multVec3(normalMatrix, norm3));

            var newTan1 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan1));
            var newTan2 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan2));
            var newTan3 = Vec3.normalize(Matrix4.multVec3(normalMatrix, tan3));

            // T = normalize(T - dot(T, N) * N);
            newTan1 = Vec3.normalize(Vec3.sub(newTan1, Vec3.multf(newNorm1, Vec3.dot(newTan1, newNorm1))));
            newTan2 = Vec3.normalize(Vec3.sub(newTan2, Vec3.multf(newNorm2, Vec3.dot(newTan2, newNorm2))));
            newTan3 = Vec3.normalize(Vec3.sub(newTan3, Vec3.multf(newNorm3, Vec3.dot(newTan3, newNorm3))));

            const newBitan1 = Vec3.normalize(Vec3.cross(newTan1, newNorm1));
            const newBitan2 = Vec3.normalize(Vec3.cross(newTan2, newNorm2));
            const newBitan3 = Vec3.normalize(Vec3.cross(newTan3, newNorm3));

            const world_pos1 = Matrix4.multVec3(model_mat, vert1);
            const world_pos2 = Matrix4.multVec3(model_mat, vert2);
            const world_pos3 = Matrix4.multVec3(model_mat, vert3);

            const proj_vert1 = Matrix4.multVec4(model_view_projection_mat, vert1);
            const proj_vert2 = Matrix4.multVec4(model_view_projection_mat, vert2);
            const proj_vert3 = Matrix4.multVec4(model_view_projection_mat, vert3);

            var tri: Tri = undefined;
            tri.v0 = Vertex{ .position = proj_vert1, .world_position = world_pos1, .normal = newNorm1, .uv = uv1, .tangent = newTan1, .bitangent = newBitan1 };
            tri.v1 = Vertex{ .position = proj_vert2, .world_position = world_pos2, .normal = newNorm2, .uv = uv2, .tangent = newTan2, .bitangent = newBitan2 };
            tri.v2 = Vertex{ .position = proj_vert3, .world_position = world_pos3, .normal = newNorm3, .uv = uv3, .tangent = newTan3, .bitangent = newBitan3 };

            if (Vec3.dot(newNorm1, Vec3.normalize(Vec3.sub(camera_pos, Matrix4.multVec3(model_mat, vert1)))) > -0.25) {
                var clipped_triangle: [8]Tri = undefined;
                const count = Tri.clipAgainstFrustrum(tri, &clipped_triangle);

                for (clipped_triangle, 0..) |triangle, t_idx| {
                    if (t_idx >= count) break;

                    const new_tri = Tri.clipToNDC(triangle);

                    const a = Vec4.ndcToRaster(new_tri.v0.position, width, height);
                    const b = Vec4.ndcToRaster(new_tri.v1.position, width, height);
                    const c = Vec4.ndcToRaster(new_tri.v2.position, width, height);

                    if (AABB.getFrom(a.x, a.y, b.x, b.y, c.x, c.y)) |aabb| {
                        const area = edgeFunction(a, b, c.x, c.y);

                        const xf32 = @as(f32, @floatFromInt(aabb.min_x));
                        const yf32 = @as(f32, @floatFromInt(aabb.min_y));

                        var w_y0: f32 = edgeFunction(a, b, xf32, yf32);
                        var w_y1: f32 = edgeFunction(b, c, xf32, yf32);
                        var w_y2: f32 = edgeFunction(c, a, xf32, yf32);

                        const dy0 = (b.y - a.y);
                        const dy1 = (c.y - b.y);
                        const dy2 = (a.y - c.y);

                        const dx0 = (a.x - b.x);
                        const dx1 = (b.x - c.x);
                        const dx2 = (c.x - a.x);

                        var y: u32 = aabb.min_y;
                        while (y <= aabb.max_y) : (y += 1) {
                            var x: u32 = aabb.min_x;

                            var w_x0: f32 = w_y0;
                            var w_x1: f32 = w_y1;
                            var w_x2: f32 = w_y2;

                            while (x <= aabb.max_x) : (x += 1) {
                                if (windingOrderNone(winding_order, w_x0, w_x1, w_x2)) {
                                    const area0 = w_x0 / area;
                                    const area1 = w_x1 / area;
                                    const area2 = w_x2 / area;

                                    const z = (area1 * new_tri.v0.position.z + area2 * new_tri.v1.position.z + area0 * new_tri.v2.position.z);

                                    if (z < depth_buffer.getPixel(x, y)) {
                                        const one_over_w = (area1 * (1 / new_tri.v0.position.w) + area2 * (1 / new_tri.v1.position.w) + area0 * (1 / new_tri.v2.position.w));
                                        const w: f32 = 1 / one_over_w;

                                        const norx = area1 * new_tri.v0.normal.x + area2 * new_tri.v1.normal.x + area0 * new_tri.v2.normal.x;
                                        const nory = area1 * new_tri.v0.normal.y + area2 * new_tri.v1.normal.y + area0 * new_tri.v2.normal.y;
                                        const norz = area1 * new_tri.v0.normal.z + area2 * new_tri.v1.normal.z + area0 * new_tri.v2.normal.z;
                                        const frag_normal = Vec3.normalize(Vec3{ .x = norx * w, .y = nory * w, .z = norz * w });

                                        var albedo: Vec3 = Vec3.init(0.0);
                                        var normal: Vec3 = Vec3.init(0.0);
                                        var metallic: f32 = 0.0;
                                        var roughness: f32 = 0.0;
                                        // var ao: f32 = 0.0;

                                        var emissive: Vec3 = Vec3.init(0.0);

                                        if (active_material.type == .Textured) {
                                            var u = area1 * new_tri.v0.uv.x + area2 * new_tri.v1.uv.x + area0 * new_tri.v2.uv.x;
                                            var v = area1 * new_tri.v0.uv.y + area2 * new_tri.v1.uv.y + area0 * new_tri.v2.uv.y;

                                            u *= w;
                                            v *= w;

                                            u = @mod(u, 1.0);
                                            v = @mod(v, 1.0);

                                            const tex_uv = Vec2{ .x = u, .y = v };

                                            const tangentx = area1 * new_tri.v0.tangent.x + area2 * new_tri.v1.tangent.x + area0 * new_tri.v2.tangent.x;
                                            const tangenty = area1 * new_tri.v0.tangent.y + area2 * new_tri.v1.tangent.y + area0 * new_tri.v2.tangent.y;
                                            const tangentz = area1 * new_tri.v0.tangent.z + area2 * new_tri.v1.tangent.z + area0 * new_tri.v2.tangent.z;
                                            const tangent = Vec3.normalize(Vec3{ .x = tangentx * w, .y = tangenty * w, .z = tangentz * w });

                                            const bitangentx = area1 * new_tri.v0.bitangent.x + area2 * new_tri.v1.bitangent.x + area0 * new_tri.v2.bitangent.x;
                                            const bitangenty = area1 * new_tri.v0.bitangent.y + area2 * new_tri.v1.bitangent.y + area0 * new_tri.v2.bitangent.y;
                                            const bitangentz = area1 * new_tri.v0.bitangent.z + area2 * new_tri.v1.bitangent.z + area0 * new_tri.v2.bitangent.z;
                                            const bitangent = Vec3.normalize(Vec3{ .x = bitangentx * w, .y = bitangenty * w, .z = bitangentz * w });

                                            const pbr = shaders.pbrBilinearSample(active_material.pbr_texture.?, tex_uv);
                                            if (pbr.albedo.w < 0.1) {
                                                continue;
                                            }

                                            albedo = Vec3{ .x = @floatCast(pbr.albedo.x), .y = @floatCast(pbr.albedo.y), .z = @floatCast(pbr.albedo.z) };

                                            var normal_map = Vec3{ .x = @floatCast(pbr.normal.x), .y = @floatCast(pbr.normal.y), .z = @floatCast(pbr.normal.z) };
                                            normal_map = Vec3.normalize(normal_map);

                                            metallic = @floatCast(pbr.metallic);
                                            roughness = @floatCast(pbr.roughness);
                                            // ao = @floatCast(pbr.ao);
                                            emissive = Vec3{ .x = pbr.emissive.x, .y = pbr.emissive.y, .z = pbr.emissive.z };

                                            normal = frag_normal;
                                            if (active_material.pbr_texture.?.normal) {
                                                normal = Vec3.add(Vec3.multf(tangent, normal_map.x), Vec3.add(Vec3.multf(bitangent, normal_map.y), Vec3.multf(frag_normal, normal_map.z)));
                                                normal = Vec3.normalize(normal);
                                            }
                                        } else {
                                            const pbr_solid = active_material.pbr_solid.?;
                                            albedo = Vec3{ .x = @floatCast(pbr_solid.albedo.x), .y = @floatCast(pbr_solid.albedo.y), .z = @floatCast(pbr_solid.albedo.z) };
                                            normal = frag_normal;
                                            metallic = @floatCast(pbr_solid.metallic);
                                            roughness = @floatCast(pbr_solid.roughness);
                                            // ao = @floatCast(pbr_solid.ao);

                                            emissive = Vec3{ .x = @floatCast(pbr_solid.emissive.x), .y = @floatCast(pbr_solid.emissive.y), .z = @floatCast(pbr_solid.emissive.z) };
                                        }

                                        const worldx = area1 * new_tri.v0.world_position.x + area2 * new_tri.v1.world_position.x + area0 * new_tri.v2.world_position.x;
                                        const worldy = area1 * new_tri.v0.world_position.y + area2 * new_tri.v1.world_position.y + area0 * new_tri.v2.world_position.y;
                                        const worldz = area1 * new_tri.v0.world_position.z + area2 * new_tri.v1.world_position.z + area0 * new_tri.v2.world_position.z;
                                        const world = Vec3{ .x = worldx * w, .y = worldy * w, .z = worldz * w };

                                        const view_dir = Vec3.normalize(Vec3.sub(camera_pos, world));

                                        var Lo: Vec3 = Vec3.init(0.0);

                                        var f0 = Vec3{ .x = 0.04, .y = 0.04, .z = 0.04 };
                                        f0 = Vec3.mix(f0, albedo, metallic);

                                        for (scene.lights.items) |light| {
                                            if (light.type == .Area) {
                                                const dotNV = std.math.clamp(Vec3.dot(normal, view_dir), 0.0, 1.0);

                                                var uv = Vec2{ .x = roughness, .y = @sqrt(1.0 - dotNV) };
                                                uv = uv.multf(shaders.lut_scale).add(Vec2{ .x = shaders.lut_bias, .y = shaders.lut_bias });

                                                const t1 = shaders.bilinearClampSample(LTC1, uv);
                                                const t2 = shaders.bilinearClampSample(LTC2, uv);

                                                const mInv = Matrix4.fromVec3(
                                                    Vec3{ .x = t1.x, .y = 0.0, .z = t1.y },
                                                    Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 },
                                                    Vec3{ .x = t1.z, .y = 0.0, .z = t1.w },
                                                );

                                                var verts: [4]Vec3 = undefined;
                                                // verts[0] = Matrix4.multVec3(rot_mat, light.verts.?[0]);
                                                // verts[1] = Matrix4.multVec3(rot_mat, light.verts.?[1]);
                                                // verts[2] = Matrix4.multVec3(rot_mat, light.verts.?[2]);
                                                // verts[3] = Matrix4.multVec3(rot_mat, light.verts.?[3]);
                                                verts[0] = light.verts.?[0];
                                                verts[1] = light.verts.?[1];
                                                verts[2] = light.verts.?[2];
                                                verts[3] = light.verts.?[3];

                                                const diffuse = shaders.areaLightContribution(normal, view_dir, world, Matrix4.getIdentity(), verts);
                                                var specular = shaders.areaLightContribution(normal, view_dir, world, mInv, verts);

                                                const fresnel = Vec3{
                                                    .x = f0.x * t2.x + (1.0 - f0.x) * t2.y,
                                                    .y = f0.y * t2.x + (1.0 - f0.y) * t2.y,
                                                    .z = f0.z * t2.x + (1.0 - f0.z) * t2.y,
                                                };

                                                specular = specular.multv(fresnel);
                                                const kD = Vec3.init(1.0 - metallic);

                                                const l_diffuse = kD.multv(albedo.multv(diffuse).multf(1.0 / std.math.pi));
                                                const radiance = light.color;
                                                const Lo1 = Vec3.add(specular, l_diffuse).multv(radiance);

                                                Lo = Lo.add(Lo1);
                                            } else {
                                                var light_dir: Vec3 = Vec3.init(0.0);
                                                var radiance: Vec3 = Vec3.init(0.0);
                                                if (light.type == .Directional) {
                                                    light_dir = Vec3.normalize(light.pos);
                                                    light_dir = Vec3.multf(light_dir, -1.0);
                                                    radiance = light.color.multf(light.intensity);
                                                } else if (light.type == .Point) {
                                                    light_dir = Vec3.normalize(Vec3.sub(light.pos, world));
                                                    const distance = Vec3.getLength(Vec3.sub(light.pos, world));
                                                    const attenuation = 1.0 / (distance * distance + 1.0);

                                                    radiance = Vec3.multf(light.color.multf(light.intensity), attenuation);
                                                }
                                                const half_vec = Vec3.normalize(Vec3.add(light_dir, view_dir));

                                                const fresnel: Vec3 = shaders.fresnelSchlick(f0, @max(Vec3.dot(half_vec, view_dir), 0.0));

                                                const normal_distr: f32 = shaders.normalDistributionGGX(normal, half_vec, roughness);
                                                const geometryS: f32 = shaders.geometrySmith(normal, view_dir, light_dir, roughness);

                                                const numerator: Vec3 = fresnel.multf(geometryS * normal_distr);
                                                const denominator: f32 = 4.0 * @max(Vec3.dot(normal, view_dir), 0.0) * @max(Vec3.dot(normal, light_dir), 0.0) + 0.0001;
                                                const specular: Vec3 = numerator.multf(1 / denominator);

                                                const kS: Vec3 = fresnel;
                                                var kD: Vec3 = Vec3.init(1.0).sub(kS);

                                                kD = kD.multf(1.0 - metallic);

                                                const NdotL: f32 = @max(Vec3.dot(normal, light_dir), 0.0);
                                                const Lo1 = Vec3.multv(kD, Vec3.multf(albedo, 1.0 / std.math.pi));
                                                const Lo2 = Vec3.add(Lo1, specular);
                                                Lo = Vec3.add(Lo, Vec3.multv(Lo2, radiance).multf(NdotL));
                                            }
                                        }

                                        // const ambient = Vec3.init(0.03).multv(albedo).multf(ao);
                                        // var color = Vec3.add(ambient, Lo);
                                        var color = Lo;
                                        color = color.add(emissive);
                                        color = color.divv(color.add(Vec3.init(1.0)));
                                        const srgb = zigimg.color.sRGB.toGamma(zigimg.color.Colorf32.from.rgb(color.x, color.y, color.z));

                                        opaque_fb.putPixel(x, y, Color{ .r = @floatCast(srgb.r), .g = @floatCast(srgb.g), .b = @floatCast(srgb.b) }, 1.0);
                                        depth_buffer.putPixel(x, y, @floatCast(z));
                                    }
                                }
                                w_x0 += dy0;
                                w_x1 += dy1;
                                w_x2 += dy2;
                            }
                            w_y0 += dx0;
                            w_y1 += dx1;
                            w_y2 += dx2;
                        }
                    }
                }
            }
        }
    }
}

pub fn render_transcluent_meshes(view_projection_mat: Matrix4) !void {
    for (tris.items) |tri| {
        const active_material = scene.materials.items[tri.material_idx];

        var clipped_triangle: [8]Tri = undefined;
        const count = Tri.clipAgainstFrustrum(tri, &clipped_triangle);

        for (clipped_triangle, 0..) |triangle, t_idx| {
            if (t_idx >= count) break;

            const new_tri = Tri.clipToNDC(triangle);

            const a = Vec4.ndcToRaster(new_tri.v0.position, width, height);
            const b = Vec4.ndcToRaster(new_tri.v1.position, width, height);
            const c = Vec4.ndcToRaster(new_tri.v2.position, width, height);

            if (AABB.getFrom(a.x, a.y, b.x, b.y, c.x, c.y)) |aabb| {
                const area = edgeFunction(a, b, c.x, c.y);

                const xf32 = @as(f32, @floatFromInt(aabb.min_x));
                const yf32 = @as(f32, @floatFromInt(aabb.min_y));

                var w_y0: f32 = edgeFunction(a, b, xf32, yf32);
                var w_y1: f32 = edgeFunction(b, c, xf32, yf32);
                var w_y2: f32 = edgeFunction(c, a, xf32, yf32);

                const dy0 = (b.y - a.y);
                const dy1 = (c.y - b.y);
                const dy2 = (a.y - c.y);

                const dx0 = (a.x - b.x);
                const dx1 = (b.x - c.x);
                const dx2 = (c.x - a.x);

                var y: u32 = aabb.min_y;
                while (y <= aabb.max_y) : (y += 1) {
                    var x: u32 = aabb.min_x;

                    var w_x0: f32 = w_y0;
                    var w_x1: f32 = w_y1;
                    var w_x2: f32 = w_y2;

                    while (x <= aabb.max_x) : (x += 1) {
                        if (windingOrderNone(winding_order, w_x0, w_x1, w_x2)) {
                            const area0 = w_x0 / area;
                            const area1 = w_x1 / area;
                            const area2 = w_x2 / area;

                            const z = (area1 * new_tri.v0.position.z + area2 * new_tri.v1.position.z + area0 * new_tri.v2.position.z);

                            if (z < depth_buffer.getPixel(x, y)) {
                                const one_over_w = (area1 * (1 / new_tri.v0.position.w) + area2 * (1 / new_tri.v1.position.w) + area0 * (1 / new_tri.v2.position.w));
                                const w: f32 = 1 / one_over_w;

                                const norx = area1 * new_tri.v0.normal.x + area2 * new_tri.v1.normal.x + area0 * new_tri.v2.normal.x;
                                const nory = area1 * new_tri.v0.normal.y + area2 * new_tri.v1.normal.y + area0 * new_tri.v2.normal.y;
                                const norz = area1 * new_tri.v0.normal.z + area2 * new_tri.v1.normal.z + area0 * new_tri.v2.normal.z;
                                const frag_normal = Vec3.normalize(Vec3{ .x = norx * w, .y = nory * w, .z = norz * w });

                                var albedo: Vec3 = Vec3.init(0.0);
                                var normal: Vec3 = Vec3.init(0.0);
                                var metallic: f32 = 0.0;
                                var roughness: f32 = 0.0;
                                // const ao: f32 = 0.1;

                                var emissive: Vec3 = Vec3.init(0.0);

                                var transmission: f16 = 0.0;
                                var ior: f16 = 1.5;

                                if (active_material.type == .Textured) {
                                    var u = area1 * new_tri.v0.uv.x + area2 * new_tri.v1.uv.x + area0 * new_tri.v2.uv.x;
                                    var v = area1 * new_tri.v0.uv.y + area2 * new_tri.v1.uv.y + area0 * new_tri.v2.uv.y;

                                    u *= w;
                                    v *= w;

                                    u = @mod(u, 1.0);
                                    v = @mod(v, 1.0);

                                    const tex_uv = Vec2{ .x = u, .y = v };

                                    const tangentx = area1 * new_tri.v0.tangent.x + area2 * new_tri.v1.tangent.x + area0 * new_tri.v2.tangent.x;
                                    const tangenty = area1 * new_tri.v0.tangent.y + area2 * new_tri.v1.tangent.y + area0 * new_tri.v2.tangent.y;
                                    const tangentz = area1 * new_tri.v0.tangent.z + area2 * new_tri.v1.tangent.z + area0 * new_tri.v2.tangent.z;
                                    const tangent = Vec3.normalize(Vec3{ .x = tangentx * w, .y = tangenty * w, .z = tangentz * w });

                                    const bitangentx = area1 * new_tri.v0.bitangent.x + area2 * new_tri.v1.bitangent.x + area0 * new_tri.v2.bitangent.x;
                                    const bitangenty = area1 * new_tri.v0.bitangent.y + area2 * new_tri.v1.bitangent.y + area0 * new_tri.v2.bitangent.y;
                                    const bitangentz = area1 * new_tri.v0.bitangent.z + area2 * new_tri.v1.bitangent.z + area0 * new_tri.v2.bitangent.z;
                                    const bitangent = Vec3.normalize(Vec3{ .x = bitangentx * w, .y = bitangenty * w, .z = bitangentz * w });

                                    const pbr = shaders.pbrBilinearSample(active_material.pbr_texture.?, tex_uv);
                                    // if (pbr.albedo.w < 0.1) {
                                    // continue;
                                    // }

                                    albedo = Vec3{ .x = @floatCast(pbr.albedo.x), .y = @floatCast(pbr.albedo.y), .z = @floatCast(pbr.albedo.z) };

                                    var normal_map = Vec3{ .x = @floatCast(pbr.normal.x), .y = @floatCast(pbr.normal.y), .z = @floatCast(pbr.normal.z) };
                                    normal_map = Vec3.normalize(normal_map);

                                    metallic = @floatCast(pbr.metallic);
                                    roughness = @floatCast(pbr.roughness);
                                    // ao = @floatCast(pbr.ao);
                                    emissive = Vec3{ .x = pbr.emissive.x, .y = pbr.emissive.y, .z = pbr.emissive.z };

                                    normal = frag_normal;
                                    if (active_material.pbr_texture.?.normal) {
                                        normal = Vec3.add(Vec3.multf(tangent, normal_map.x), Vec3.add(Vec3.multf(bitangent, normal_map.y), Vec3.multf(frag_normal, normal_map.z)));
                                        normal = Vec3.normalize(normal);
                                    }
                                    transmission = pbr.transmission;
                                    ior = pbr.ior;
                                } else {
                                    const pbr_solid = active_material.pbr_solid.?;
                                    albedo = Vec3{ .x = @floatCast(pbr_solid.albedo.x), .y = @floatCast(pbr_solid.albedo.y), .z = @floatCast(pbr_solid.albedo.z) };
                                    normal = frag_normal;
                                    metallic = @floatCast(pbr_solid.metallic);
                                    roughness = @floatCast(pbr_solid.roughness);
                                    // ao = @floatCast(pbr_solid.ao);

                                    emissive = Vec3{ .x = @floatCast(pbr_solid.emissive.x), .y = @floatCast(pbr_solid.emissive.y), .z = @floatCast(pbr_solid.emissive.z) };
                                    transmission = pbr_solid.transmission;
                                    ior = pbr_solid.ior;
                                }

                                const worldx = area1 * new_tri.v0.world_position.x + area2 * new_tri.v1.world_position.x + area0 * new_tri.v2.world_position.x;
                                const worldy = area1 * new_tri.v0.world_position.y + area2 * new_tri.v1.world_position.y + area0 * new_tri.v2.world_position.y;
                                const worldz = area1 * new_tri.v0.world_position.z + area2 * new_tri.v1.world_position.z + area0 * new_tri.v2.world_position.z;
                                const world = Vec3{ .x = worldx * w, .y = worldy * w, .z = worldz * w };

                                const view_dir = Vec3.normalize(Vec3.sub(camera_pos, world));

                                var Lo: Vec3 = Vec3.init(0.0);

                                // var f0 = Vec3{ .x = 0.04, .y = 0.04, .z = 0.04 };
                                var f0 = Vec3.init(std.math.pow(f32, (ior - 1.0) / (ior + 1.0), 2.0));
                                f0 = Vec3.mix(f0, albedo, metallic);

                                const eta = 1.0 / ior;
                                //TODO: Improve this refraction code?
                                const r = Vec3.normalize(Vec3.refract(view_dir.multf(-1.0), normal, eta));
                                // const thickness = 0.5;
                                const thickness = @abs(depth_buffer.getPixel(x, y) - z) * 500.0;
                                const new_r = Matrix4.multVec3(view_projection_mat, r);

                                var uv_offset = Vec2{ .x = new_r.x * thickness, .y = new_r.y * thickness };

                                // We clamp because int part of float overflows.
                                // We make sure the offset doesn't go outside opaque fb's bounds
                                uv_offset.x = std.math.clamp(uv_offset.x, 0.0, 1.0);
                                uv_offset.y = std.math.clamp(uv_offset.y, 0.0, 1.0);

                                uv_offset.x = uv_offset.x * @as(f32, @floatFromInt(opaque_fb.width));
                                uv_offset.y = uv_offset.y * @as(f32, @floatFromInt(opaque_fb.height));

                                const uv_offset_i_x = @as(u32, @intFromFloat(uv_offset.x));
                                const uv_offset_i_y = @as(u32, @intFromFloat(uv_offset.y));

                                const sample_pos_x = std.math.clamp(x + uv_offset_i_x, 0, opaque_fb.width - 1);
                                const sample_pos_y = std.math.clamp(y + uv_offset_i_y, 0, opaque_fb.height - 1);

                                const bg = opaque_fb.getPixel(sample_pos_x, sample_pos_y);

                                const linear = zigimg.color.sRGB.toLinear(zigimg.color.Colorf32.from.rgb(bg.r, bg.g, bg.b));
                                const bg_color = Vec3{ .x = linear.r, .y = linear.g, .z = linear.b };

                                for (scene.lights.items) |light| {
                                    if (light.type == .Area) {
                                        const dotNV = std.math.clamp(Vec3.dot(normal, view_dir), 0.0, 1.0);

                                        var uv = Vec2{ .x = roughness, .y = @sqrt(1.0 - dotNV) };
                                        uv = uv.multf(shaders.lut_scale).add(Vec2{ .x = shaders.lut_bias, .y = shaders.lut_bias });

                                        const t1 = shaders.bilinearClampSample(LTC1, uv);
                                        const t2 = shaders.bilinearClampSample(LTC2, uv);

                                        const mInv = Matrix4.fromVec3(
                                            Vec3{ .x = t1.x, .y = 0.0, .z = t1.y },
                                            Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 },
                                            Vec3{ .x = t1.z, .y = 0.0, .z = t1.w },
                                        );

                                        var verts: [4]Vec3 = undefined;
                                        // verts[0] = Matrix4.multVec3(rot_mat, light.verts.?[0]);
                                        // verts[1] = Matrix4.multVec3(rot_mat, light.verts.?[1]);
                                        // verts[2] = Matrix4.multVec3(rot_mat, light.verts.?[2]);
                                        // verts[3] = Matrix4.multVec3(rot_mat, light.verts.?[3]);
                                        verts[0] = light.verts.?[0];
                                        verts[1] = light.verts.?[1];
                                        verts[2] = light.verts.?[2];
                                        verts[3] = light.verts.?[3];

                                        const diffuse = shaders.areaLightContribution(normal, view_dir, world, Matrix4.getIdentity(), verts);
                                        var specular = shaders.areaLightContribution(normal, view_dir, world, mInv, verts);
                                        const transmitted = shaders.areaLightContribution(normal.multf(-1.0), view_dir, world, Matrix4.getIdentity(), verts);

                                        const fresnel = Vec3{
                                            .x = f0.x * t2.x + (1.0 - f0.x) * t2.y,
                                            .y = f0.y * t2.x + (1.0 - f0.y) * t2.y,
                                            .z = f0.z * t2.x + (1.0 - f0.z) * t2.y,
                                        };

                                        specular = specular.multv(fresnel);
                                        const kD = Vec3.init(1.0 - metallic);

                                        const l_diffuse = kD.multv(albedo.multv(diffuse).multf(1.0 / std.math.pi));
                                        const l_transmitted = kD.multv(albedo.multv(bg_color).multv(transmitted));
                                        const radiance = light.color;

                                        // const Lo1 = Vec3.add(specular, l_diffuse).multv(radiance);

                                        const front = Vec3.add(specular, l_diffuse).multv(radiance).multf(1.0 - transmission);
                                        const back = Vec3.add(specular, l_transmitted).multv(radiance).multf(transmission);

                                        Lo = Lo.add(front.add(back));
                                    } else {
                                        var light_dir: Vec3 = Vec3.init(0.0);
                                        var radiance: Vec3 = Vec3.init(0.0);
                                        if (light.type == .Directional) {
                                            light_dir = Vec3.normalize(light.pos);
                                            light_dir = Vec3.multf(light_dir, -1.0);
                                            radiance = light.color.multf(light.intensity);
                                        } else if (light.type == .Point) {
                                            light_dir = Vec3.normalize(Vec3.sub(light.pos, world));
                                            const distance = Vec3.getLength(Vec3.sub(light.pos, world));
                                            const attenuation = 1.0 / (distance * distance + 1.0);

                                            radiance = Vec3.multf(light.color.multf(light.intensity), attenuation);
                                        }
                                        const half_vec = Vec3.normalize(Vec3.add(light_dir, view_dir));

                                        const fresnel: Vec3 = shaders.fresnelSchlick(f0, @max(Vec3.dot(half_vec, view_dir), 0.0));

                                        const normal_distr: f32 = shaders.normalDistributionGGX(normal, half_vec, roughness);
                                        const geometryS: f32 = shaders.geometrySmith(normal, view_dir, light_dir, roughness);

                                        const numerator: Vec3 = fresnel.multf(geometryS * normal_distr);
                                        const denominator: f32 = 4.0 * @max(Vec3.dot(normal, view_dir), 0.0) * @max(Vec3.dot(normal, light_dir), 0.0) + 0.0001;
                                        const specular: Vec3 = numerator.multf(1 / denominator);

                                        const kS: Vec3 = fresnel;
                                        var kD: Vec3 = Vec3.init(1.0).sub(kS);

                                        kD = kD.multf(1.0 - metallic);

                                        const NdotL: f32 = @max(Vec3.dot(normal, light_dir), 0.0);

                                        const Lo1 = Vec3.multv(kD, Vec3.multf(albedo, 1.0 / std.math.pi));

                                        const Lo2 = Vec3.add(Lo1, specular);
                                        // Lo = Vec3.add(Lo, Vec3.multv(Lo2, radiance).multf(NdotL));
                                        const opaque_result = Vec3.multv(Lo2, radiance).multf(NdotL);

                                        const one_minus_fresnel = Vec3.init(1.0).sub(fresnel);

                                        const kT = one_minus_fresnel.multf(1.0 - metallic);

                                        // const eta = 1.0 / ior;
                                        // const r = Vec3.refract(view_dir.multf(-1.0), normal, eta);
                                        // const thickness = 1.0;

                                        // const new_r = Matrix4.multVec3(view_mat, r);

                                        // var uv_offset = Vec2{ .x = r.x * thickness, .y = r.y * thickness };
                                        // uv_offset.x = uv_offset.x * @as(f32, @floatFromInt(opaque_fb.width));
                                        // uv_offset.y = uv_offset.y * @as(f32, @floatFromInt(opaque_fb.height));

                                        // const sample_pos_x = std.math.clamp(x + @as(u32, @intFromFloat(uv_offset.x)), 0, opaque_fb.width);
                                        // const sample_pos_y = std.math.clamp(y + @as(u32, @intFromFloat(uv_offset.y)), 0, opaque_fb.height);

                                        // const bg = opaque_fb.getPixel(sample_pos_x, sample_pos_y);
                                        // const linear = zigimg.color.sRGB.toLinear(zigimg.color.Colorf32.from.rgb(bg.r, bg.g, bg.b));
                                        // const bg_color = Vec3{ .x = linear.r, .y = linear.g, .z = linear.b };
                                        const transmitted = kT.multv(bg_color.multv(albedo)).multf(transmission);

                                        const NdotL_Back: f32 = @max(Vec3.dot(normal, light_dir.multf(-1.0)), 0.0);

                                        const transmissive_specular = specular.multv(radiance).multf(NdotL);
                                        const transmissive_refraction = transmitted.multv(radiance).multf(NdotL_Back);

                                        const transmissive_result = transmissive_specular.add(transmissive_refraction);
                                        // const l_transmission = one_minus_fresnel.multv(bg_color.multv(albedo)).multf(transmission).multv(radiance).multf(NdotL_Back);

                                        const mix = Vec3.mix(opaque_result, transmissive_result, transmission);
                                        Lo = Lo.add(mix);
                                    }
                                }

                                // const ambient = Vec3.init(0.03).multv(albedo).multf(ao);
                                // var color = Vec3.add(ambient, Lo);
                                var color = Lo;
                                color = color.add(emissive);
                                color = color.divv(color.add(Vec3.init(1.0)));
                                const srgb = zigimg.color.sRGB.toGamma(zigimg.color.Colorf32.from.rgb(color.x, color.y, color.z));
                                if (transmission > 0.0) {
                                    // const prev_color = transcluent_fb.getPixel(x, y);
                                    // const blend_factor: f16 = 0.5;
                                    // const blend = Color{
                                    // .r = @as(f16, @floatCast(srgb.r)) * (1.0 - blend_factor) + blend_factor * prev_color.r,
                                    // .g = @as(f16, @floatCast(srgb.g)) * (1.0 - blend_factor) + blend_factor * prev_color.g,
                                    // .b = @as(f16, @floatCast(srgb.b)) * (1.0 - blend_factor) + blend_factor * prev_color.b,
                                    // };

                                    // opaque_fb.putPixel(x, y, Color{ .r = blend.r, .g = blend.g, .b = blend.b }, 0.0);
                                    // transcluent_fb.putPixel(x, y, Color{ .r = blend.r, .g = blend.g, .b = blend.b }, 0.0);
                                    // transcluent_fb.putPixel(x, y, Color{ .r = @floatCast(blend.r), .g = @floatCast(blend.g), .b = @floatCast(blend.b) }, 1.0);
                                    transcluent_fb.putPixel(x, y, Color{ .r = @floatCast(srgb.r), .g = @floatCast(srgb.g), .b = @floatCast(srgb.b) }, 1.0);
                                    depth_buffer.putPixel(x, y, z);
                                } else {
                                    opaque_fb.putPixel(x, y, Color{ .r = @floatCast(srgb.r), .g = @floatCast(srgb.g), .b = @floatCast(srgb.b) }, 1.0);
                                    depth_buffer.putPixel(x, y, z);
                                }
                                // transcluent_fb.putPixel(x, y, Color{ .r = @floatCast(srgb.r), .g = @floatCast(srgb.g), .b = @floatCast(srgb.b) }, 1.0);
                                // depth_buffer.putPixel(x, y, @floatCast(z));
                            }
                        }
                        w_x0 += dy0;
                        w_x1 += dy1;
                        w_x2 += dy2;
                    }
                    w_y0 += dx0;
                    w_y1 += dx1;
                    w_y2 += dx2;
                }
            }
        }
    }
}

const TriSortContext = struct {
    camera_pos: Vec3,

    pub fn compare(context: TriSortContext, a: Tri, b: Tri) bool {
        var centroid_a = a.v0.world_position.add(a.v1.world_position.add(a.v2.world_position));
        centroid_a = centroid_a.divv(Vec3.init(3.0));

        var centroid_b = b.v0.world_position.add(b.v1.world_position.add(b.v2.world_position));
        centroid_b = centroid_b.divv(Vec3.init(3.0));

        const dist_a = distanceSquared(context.camera_pos, centroid_a);
        const dist_b = distanceSquared(context.camera_pos, centroid_b);

        return dist_a > dist_b;
    }

    fn distanceSquared(a: Vec3, b: Vec3) f32 {
        const dx = a.x - b.x;
        const dy = a.y - b.y;
        const dz = a.z - b.z;
        return dx * dx + dy * dy + dz * dz;
    }
};

// TODO: Merge Opaque and Transcluent same frag/vert code
pub fn render(_: f32, camera: usize) !void {
    opaque_fb.clearColor(0.0);
    transcluent_fb.clearColor(0.0);
    depth_buffer.clearColor(1.0);

    const cam = scene.cameras.items[camera % scene.cameras.items.len];

    camera_pos = cam.pos;
    view_mat = cam.view_matrix;
    projection_mat = Matrix4.perspectiveProjection(cam.fov, aspect_ratio, 0.1, 100.0);
    const view_projection_mat = Matrix4.multMatrix4(projection_mat, view_mat);

    // const bust = scene.translucent_meshes.items[0];
    // const rot_mat = Matrix4.rotateY(theta);
    // const model_mat = Matrix4.multMatrix4(rot_mat, bust.transform);
    // scene.translucent_meshes.items[0].transform = model_mat;

    try render_opaque_meshes(view_projection_mat);

    try process_meshes(scene.translucent_meshes, view_projection_mat);
    std.mem.sort(Tri, tris.items, TriSortContext{ .camera_pos = camera_pos }, TriSortContext.compare);
    try render_transcluent_meshes(view_projection_mat);

    opaque_fb.add(&transcluent_fb);
}

pub fn deinit() void {
    // mesh.deinit(allocator);
    // TODO: Deallocate name strings and textures/materials in mesh.zig and material.zig
    // texture_pbr.deinit(allocator);
    tris.deinit(allocator);
    scene.deinit(allocator);
    opaque_fb.deinit();
    transcluent_fb.deinit();
    depth_buffer.deinit();
    arena.deinit();
}
