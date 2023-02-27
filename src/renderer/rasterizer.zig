const std = @import("std");
const zigimg = @import("zigimg");
const obj = @import("zig-obj");

const Vec3 = @import("../math/vec3.zig").Vec3;
const Vec2 = @import("../math/vec2.zig").Vec2;
const Matrix4 = @import("../math/matrix4.zig").Matrix4;

const rendertarget = @import("rendertarget.zig");
const RenderTargetRGBA16 = rendertarget.RenderTargetRGBA16;
const RenderTargetR16 = rendertarget.RenderTargetR16;
const Color = rendertarget.Color;

const Mesh = @import("../mesh.zig").Mesh;

pub const width = 1280;
pub const height = 720;

const WindingOrder = enum { CW, CCW };
const AABB = struct {
    min_x: u32,
    max_x: u32,
    min_y: u32,
    max_y: u32,

    fn getFrom(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) ?AABB {
        var min_x = std.math.min3(ax, bx, cx);
        var min_y = std.math.min3(ay, by, cy);

        var max_x = std.math.max3(ax, bx, cx);
        var max_y = std.math.max3(ay, by, cy);

        if (min_x > width - 1 or max_x < 0 or min_y > height - 1 or max_y < 0) {
            return null;
        } else {
            min_x = std.math.max(0.0, min_x);
            max_x = std.math.min(width - 1, max_x);
            min_y = std.math.max(0.0, min_y);
            max_y = std.math.min(height - 1, max_y);

            return AABB{ .min_x = @floatToInt(u32, min_x), .min_y = @floatToInt(u32, min_y), .max_x = @floatToInt(u32, max_x), .max_y = @floatToInt(u32, max_y) };
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

pub var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();
pub var frame_buffer: RenderTargetRGBA16 = undefined;
pub var depth_buffer: RenderTargetR16 = undefined;

var mesh: Mesh = undefined;
var albedo_tex: zigimg.Image = undefined;

var tex_width_f32: f32 = 0.0;
var tex_height_f32: f32 = 0.0;
const aspect_ratio: f32 = @intToFloat(f32, width) / @intToFloat(f32, height);

const winding_order = WindingOrder.CCW;

const light_from = Vec3{ .x = 0.0, .y = 3.0, .z = 0.0 };
const light_to = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };

const from = Vec3{ .x = 3.0, .y = 2.0, .z = 0.0 };
const to = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
const up = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };

const projection_mat = Matrix4.perspectiveProjection(45.0, aspect_ratio, 0.1, 100.0);
const view_mat = Matrix4.lookAt(from, to, up);

pub fn init() !void {
    frame_buffer = RenderTargetRGBA16.create(allocator, width, height);
    depth_buffer = RenderTargetR16.create(allocator, width, height);
    mesh = try Mesh.fromObjFile("../glTF-Sample-Models/2.0/SciFiHelmet/glTF/untitled.obj", allocator);
    albedo_tex = try zigimg.Image.fromFilePath(allocator, "../glTF-Sample-Models/2.0/SciFiHelmet/glTF/SciFiHelmet_BaseColor.png");
    tex_width_f32 = @intToFloat(f32, albedo_tex.width);
    tex_height_f32 = @intToFloat(f32, albedo_tex.height);
}

pub fn render(theta: f32) !void {
    frame_buffer.clearColor(0.5);
    depth_buffer.clearColor(1.0);

    var model_mat = Matrix4.rotateY(theta);

    var model_view_mat = Matrix4.multMatrix4(view_mat, model_mat);
    var view_projection_mat = Matrix4.multMatrix4(projection_mat, model_view_mat);

    var i: u32 = 0;
    while (i < mesh.indices) : (i += 3) {
        var vert1 = mesh.vertices.items[i];
        var vert2 = mesh.vertices.items[i + 1];
        var vert3 = mesh.vertices.items[i + 2];

        var a_rot = Matrix4.multVec3(model_mat, vert1);
        var b_rot = Matrix4.multVec3(model_mat, vert2);
        var c_rot = Matrix4.multVec3(model_mat, vert3);

        var normal = Vec3.cross(Vec3.sub(b_rot, a_rot), Vec3.sub(c_rot, a_rot)).normalize();

        if (Vec3.dot(normal, Vec3.normalize(Vec3.sub(from, vert1))) > -0.25) {
            var proj_vert1 = Matrix4.multVec3(view_projection_mat, vert1);
            var proj_vert2 = Matrix4.multVec3(view_projection_mat, vert2);
            var proj_vert3 = Matrix4.multVec3(view_projection_mat, vert3);

            var light_dir = Vec3.normalize(Vec3.sub(light_from, light_to));

            var a = Vec3.ndlToRaster(proj_vert1, width, height);
            var b = Vec3.ndlToRaster(proj_vert2, width, height);
            var c = Vec3.ndlToRaster(proj_vert3, width, height);

            var a_uv = mesh.uvs.items[i];
            a_uv.x *= a.z;
            a_uv.y *= a.z;
            var b_uv = mesh.uvs.items[i + 1];
            b_uv.x *= b.z;
            b_uv.y *= b.z;
            var c_uv = mesh.uvs.items[i + 2];
            c_uv.x *= c.z;
            c_uv.y *= c.z;

            if (AABB.getFrom(a.x, a.y, b.x, b.y, c.x, c.y)) |aabb| {
                var area = edgeFunction(a, b, c.x, c.y);

                const xf32 = @intToFloat(f32, aabb.min_x);
                const yf32 = @intToFloat(f32, aabb.min_y);

                var w_y0: f32 = edgeFunction(a, b, xf32, yf32);
                var w_y1: f32 = edgeFunction(b, c, xf32, yf32);
                var w_y2: f32 = edgeFunction(c, a, xf32, yf32);

                var dy0 = (b.y - a.y);
                var dy1 = (c.y - b.y);
                var dy2 = (a.y - c.y);

                var dx0 = (a.x - b.x);
                var dx1 = (b.x - c.x);
                var dx2 = (c.x - a.x);

                var y: u32 = aabb.min_y;
                while (y <= aabb.max_y) : (y += 1) {
                    var x: u32 = aabb.min_x;

                    var w_x0: f32 = w_y0;
                    var w_x1: f32 = w_y1;
                    var w_x2: f32 = w_y2;

                    while (x <= aabb.max_x) : (x += 1) {
                        if (windingOrderTest(winding_order, w_x0, w_x1, w_x2)) {
                            var area0 = w_x0 / area;
                            var area1 = w_x1 / area;
                            var area2 = w_x2 / area;

                            var z = 1.0 / (area1 * a.z + area2 * b.z + area0 * c.z);

                            if (z < depth_buffer.getPixel(x, y)) {
                                depth_buffer.putPixel(x, y, @floatCast(f16, z));

                                var u = area1 * a_uv.x + area2 * b_uv.x + area0 * c_uv.x;
                                var v = area1 * a_uv.y + area2 * b_uv.y + area0 * c_uv.y;

                                u *= z;
                                v *= z;

                                u = std.math.clamp(u, 0.0, 1.0);
                                v = std.math.clamp(v, 0.0, 1.0);

                                // WHYYYYYYYYYYYYYY!!!!!!
                                v = 1.0 - v;

                                var tex_u = @floatToInt(u32, u * tex_width_f32);
                                var tex_v = @floatToInt(u32, v * tex_height_f32);

                                var albedo = albedo_tex.pixels.rgba32[tex_v * albedo_tex.width + tex_u].toColorf32();

                                var pong = std.math.max(0.0, Vec3.dot(normal, light_dir));

                                albedo.r *= pong * 1.5;
                                albedo.g *= pong * 1.5;
                                albedo.b *= pong * 1.5;

                                frame_buffer.putPixel(x, y, Color{ .r = @floatCast(f16, albedo.r), .g = @floatCast(f16, albedo.g), .b = @floatCast(f16, albedo.b) });
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

pub fn deinit() void {
    mesh.deinit();
    albedo_tex.deinit();
    frame_buffer.deinit();
    depth_buffer.deinit();
    arena.deinit();
}
