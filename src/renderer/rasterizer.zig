const std = @import("std");

const Vec3 = @import("../vec3.zig").Vec3;
const Vec2 = @import("../vec2.zig").Vec2;
const Matrix4 = @import("../matrix4.zig").Matrix4;
const RenderTargetRGBA16 = @import("rendertarget.zig").RenderTargetRGBA16;
const RenderTargetR16 = @import("rendertarget.zig").RenderTargetR16;
const Color = @import("rendertarget.zig").Color;
const Mesh = @import("../mesh.zig").Mesh;
const zigimg = @import("zigimg");
const sokol = @import("sokol");

pub const width = 1280;
pub const height = 720;

const WindingOrder = enum { CW, CCW };
const AABB = struct {
    min_x: u32,
    max_x: u32,
    min_y: u32,
    max_y: u32,

    fn getFrom(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) AABB {
        var min_x = std.math.min(std.math.min(ax, bx), cx);
        min_x = std.math.max(0, std.math.min(width - 1, min_x));
        var min_y = std.math.min(std.math.min(ay, by), cy);
        min_y = std.math.max(0, std.math.min(height - 1, min_y));

        var max_x = std.math.max(std.math.max(ax, bx), cx);
        max_x = std.math.max(0, std.math.min(width - 1, max_x));
        var max_y = std.math.max(std.math.max(ay, by), cy);
        max_y = std.math.max(0, std.math.min(height - 1, max_y));

        return AABB{ .min_x = @floatToInt(u32, min_x), .min_y = @floatToInt(u32, min_y), .max_x = @floatToInt(u32, max_x), .max_y = @floatToInt(u32, max_y) };
    }
};

fn clamp(comptime T: type, min: anytype, max: anytype, val: anytype) T {
    switch (@typeInfo(@TypeOf(val))) {
        .Int, .Float => {
            if (val < min) {
                return min;
            } else if (val > max) {
                return max;
            } else {
                return val;
            }
        },
        else => {
            @compileError("Unable to clamp type '" ++ @typeName(@TypeOf(val)) ++ "'");
        },
    }
}

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
var texture: zigimg.Image = undefined;

var tex_width_f32: f32 = 0.0;
var tex_height_f32: f32 = 0.0;
const aspect_ratio: f32 = @intToFloat(f32, width) / @intToFloat(f32, height);

pub fn init() !void {
    frame_buffer = RenderTargetRGBA16.create(allocator, width, height);
    depth_buffer = RenderTargetR16.create(allocator, width, height);
    mesh = try Mesh.fromObjFile("spot_mesh.obj", allocator);
    texture = try zigimg.Image.fromFilePath(allocator, "spot_texture.png");
    tex_width_f32 = @intToFloat(f32, texture.width);
    tex_height_f32 = @intToFloat(f32, texture.height);
}

pub fn render() !void {
    frame_buffer.clearColor(1.0);
    depth_buffer.clearColor(1.0);

    var winding_order = WindingOrder.CCW;

    var light_from = Vec3{ .x = 3.0, .y = 2.0, .z = -2.0 };
    var light_to = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };

    var from = Vec3{ .x = 3.0, .y = 1.5, .z = -2.0 };
    var to = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    var up = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };

    var projection_mat = Matrix4.perspectiveProjection(45.0, aspect_ratio, 1.0, 10.0);
    var view_mat = Matrix4.lookAt(from, to, up);
    var view_projection_mat = Matrix4.multMatrix4(projection_mat, view_mat);

    var i: u32 = 0;
    while (i < mesh.indices.items.len) : (i += 3) {
        var index1 = mesh.indices.items[i];
        var index2 = mesh.indices.items[i + 1];
        var index3 = mesh.indices.items[i + 2];

        var vert1 = mesh.vertices.items[index1 - 1];
        var vert2 = mesh.vertices.items[index2 - 1];
        var vert3 = mesh.vertices.items[index3 - 1];

        var a = Vec3.ndlToRaster(Matrix4.multVec3(view_projection_mat, vert1), width, height);
        var b = Vec3.ndlToRaster(Matrix4.multVec3(view_projection_mat, vert2), width, height);
        var c = Vec3.ndlToRaster(Matrix4.multVec3(view_projection_mat, vert3), width, height);

        var a_uv = mesh.uvs.items[mesh.uv_indices.items[i + 0] - 1];
        a_uv.x *= a.z;
        a_uv.y *= a.z;
        var b_uv = mesh.uvs.items[mesh.uv_indices.items[i + 1] - 1];
        b_uv.x *= b.z;
        b_uv.y *= b.z;
        var c_uv = mesh.uvs.items[mesh.uv_indices.items[i + 2] - 1];
        c_uv.x *= c.z;
        c_uv.y *= c.z;

        // TODO: Replace with actual clipping
        if (a.x > 0 and a.y > 0 and b.x > 0 and b.y > 0 and c.x > 0 and c.y > 0) {
            var aabb = AABB.getFrom(a.x, a.y, b.x, b.y, c.x, c.y);

            var area = edgeFunction(a, b, c.x, c.y);

            var x: u32 = aabb.min_x;
            var y: u32 = aabb.min_y;
            while (y <= aabb.max_y) : (y += 1) {
                while (x <= aabb.max_x) : (x += 1) {
                    const xf32 = @intToFloat(f32, x);
                    const yf32 = @intToFloat(f32, y);

                    var w0: f32 = edgeFunction(a, b, xf32, yf32);
                    var w1: f32 = edgeFunction(b, c, xf32, yf32);
                    var w2: f32 = edgeFunction(c, a, xf32, yf32);

                    if (windingOrderTest(winding_order, w0, w1, w2)) {
                        w0 /= area;
                        w1 /= area;
                        w2 /= area;

                        var z = 1.0 / (w1 * a.z + w2 * b.z + w0 * c.z);

                        if (z < depth_buffer.getPixel(x, y)) {
                            depth_buffer.putPixel(x, y, @floatCast(f16, z));

                            var u = w1 * a_uv.x + w2 * b_uv.x + w0 * c_uv.x;
                            var v = w1 * a_uv.y + w2 * b_uv.y + w0 * c_uv.y;

                            u *= z;
                            v *= z;

                            u = clamp(f32, 0.0, 1.0, u);
                            v = clamp(f32, 0.0, 1.0, v);

                            // WHYYYYYYYYYYYYYY!!!!!!
                            v = 1.0 - v;

                            var tex_u = @floatToInt(u32, u * tex_width_f32);
                            var tex_v = @floatToInt(u32, v * tex_height_f32);

                            var albedo = texture.pixels.rgb24[tex_v * texture.width + tex_u].toColorf32();

                            var normal = mesh.normals.items[mesh.normal_indices.items[i + 0] - 1];

                            var light_dir = Vec3.normalize(Vec3.sub(light_from, light_to));
                            var pong = std.math.max(0.0, Vec3.dot(normal, light_dir));

                            albedo.r *= pong;
                            albedo.g *= pong;
                            albedo.b *= pong;

                            frame_buffer.putPixel(x, y, Color{ .r = @floatCast(f16, albedo.r), .g = @floatCast(f16, albedo.g), .b = @floatCast(f16, albedo.b) });
                        }
                    }
                }
                x = 0;
            }
        }
    }
}

pub fn deinit() void {
    mesh.deinit();
    texture.deinit();
    frame_buffer.deinit();
    depth_buffer.deinit();
    arena.deinit();
}