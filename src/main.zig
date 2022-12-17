const std = @import("std");

const Vec3 = @import("vec3.zig").Vec3;
const Vec2 = @import("vec2.zig").Vec2;
const Matrix4 = @import("matrix4.zig").Matrix4;
const RenderTargetRGBA16 = @import("renderer/rendertarget.zig").RenderTargetRGBA16;
const RenderTargetR16 = @import("renderer/rendertarget.zig").RenderTargetR16;
const Color = @import("renderer/rendertarget.zig").Color;
const Mesh = @import("mesh.zig").Mesh;
const zigimg = @import("zigimg");
const sokol = @import("sokol");

const width = 1280;
const height = 720;

const color = extern struct { r: u8 = 0, g: u8 = 0, b: u8 = 0 };
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

var arenea = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var frame_buffer: RenderTargetRGBA16 = undefined;
var depth_buffer: RenderTargetR16 = undefined;

pub fn render() !void {
    const allocator = arenea.allocator();

    frame_buffer = RenderTargetRGBA16.create(allocator, width, height);
    depth_buffer = RenderTargetR16.create(allocator, width, height);

    // TODO: check if it is cheaper to clear or destroy-create buffer, we keep it commented for now.
    // frame_buffer.clearColor(Color{ .r = 100, .g = 0, .b = 100 });
    depth_buffer.clearColor(1.0);

    var mesh = try Mesh.fromObjFile("spot_mesh.obj", allocator);
    defer mesh.destroy();

    var texture = try zigimg.Image.fromFilePath(allocator, "spot_texture.png");
    defer texture.deinit();

    const tex_width_f32 = @intToFloat(f32, texture.width);
    const tex_height_f32 = @intToFloat(f32, texture.height);

    var winding_order = WindingOrder.CCW;

    var light_from = Vec3{ .x = 3.0, .y = 2.0, .z = -2.0 };
    var light_to = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };

    var from = Vec3{ .x = 3.0, .y = 1.5, .z = -2.0 };
    var to = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    var up = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };

    var projection_mat = Matrix4.perspectiveProjection(45.0, @intToFloat(f32, width) / @intToFloat(f32, height), 1.0, 10.0);
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

                            frame_buffer.putPixel(x, y, Color{ .r = @floatCast(f16,albedo.r), 
                                    .g = @floatCast(f16,albedo.g), 
                                        .b = @floatCast(f16,albedo.b) });
                        }
                    }
                }
                x = 0;
            }
        }
    }
}

const sg = @import("sokol").gfx;
const sapp = @import("sokol").app;
const sgapp = @import("sokol").app_gfx_glue;
const shd = @import("shaders/shader.glsl.zig");

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var pass_action: sg.PassAction = .{};

    var dbg_pip: sg.Pipeline = .{};
    var dbg_bind: sg.Bindings = .{};
};

export fn init() void {
    const time_0 = std.time.milliTimestamp();
    render() catch |err| {
        std.debug.print("error: {any}", .{err});
    };
    const time_1 = std.time.milliTimestamp();
    const interval = time_1 - time_0;
    std.debug.print("ms: {d}", .{interval});

    sg.setup(.{ .context = sgapp.context() });

    const quad_vbuf = sg.makeBuffer(.{ .data = sg.asRange(&[_]f32{ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0 }) });

    var fb_img_desc: sg.ImageDesc = .{
        .width = width,
        .height = height,
        .pixel_format = sg.PixelFormat.RGBA16F,
    };
    fb_img_desc.data.subimage[0][0] = sg.asRange(frame_buffer.buffer);

    var db_img_desc: sg.ImageDesc = .{
        .width = width,
        .height = height,
        .pixel_format = sg.PixelFormat.R16F,
    };
    db_img_desc.data.subimage[0][0] = sg.asRange(depth_buffer.buffer);

    state.bind.vertex_buffers[0] = quad_vbuf;
    state.bind.fs_images[shd.SLOT_tex] = sg.makeImage(fb_img_desc);
    var pip_desc: sg.PipelineDesc = .{
        .primitive_type = .TRIANGLE_STRIP,
        .shader = sg.makeShader(shd.shaderShaderDesc(sg.queryBackend())),
    };
    pip_desc.layout.attrs[shd.ATTR_vs_position].format = .FLOAT2;
    state.pip = sg.makePipeline(pip_desc);

    state.dbg_bind.vertex_buffers[0] = quad_vbuf;
    state.dbg_bind.fs_images[shd.SLOT_tex] = sg.makeImage(db_img_desc);
    var dbg_pip_desc: sg.PipelineDesc = .{
        .primitive_type = .TRIANGLE_STRIP,
        .shader = sg.makeShader(shd.shaderShaderDesc(sg.queryBackend())),
    };
    dbg_pip_desc.layout.attrs[shd.ATTR_vs_position].format = .FLOAT2;
    state.dbg_pip = sg.makePipeline(dbg_pip_desc);

    state.pass_action.colors[0] = .{ .action = .CLEAR, .value = .{ .r = 0, .g = 0, .b = 0, .a = 1 } };
}

export fn frame() void {
    sg.beginDefaultPass(state.pass_action, sapp.width(), sapp.height());
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.draw(0, 4, 1);

    sg.applyPipeline(state.dbg_pip);
    sg.applyViewport(0 * 150, 0, 150, 150, false);
    sg.applyBindings(state.dbg_bind);
    sg.draw(0, 4, 1);

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    frame_buffer.deinit();
    depth_buffer.deinit();
    arenea.deinit();
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{ .init_cb = init, .frame_cb = frame, .cleanup_cb = cleanup, .width = width, .height = height, .icon = .{
        .sokol_default = true,
    }, .window_title = "quad.zig" });
}
