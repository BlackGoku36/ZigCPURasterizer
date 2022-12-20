const std = @import("std");

const sg = @import("sokol").gfx;
const sapp = @import("sokol").app;
const sgapp = @import("sokol").app_gfx_glue;
const shd = @import("shaders/shader.glsl.zig");

const rasterizer = @import("renderer/rasterizer.zig");

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var pass_action: sg.PassAction = .{};

    var dbg_pip: sg.Pipeline = .{};
    var dbg_bind: sg.Bindings = .{};
};

export fn init() void {
    rasterizer.init() catch |err| {
        std.debug.print("error: {any}", .{err});
    };

    sg.setup(.{ .context = sgapp.context() });

    const quad_vbuf = sg.makeBuffer(.{ .data = sg.asRange(&[_]f32{ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0 }) });

    var fb_img_desc: sg.ImageDesc = .{
        .width = rasterizer.width,
        .height = rasterizer.height,
        .pixel_format = sg.PixelFormat.RGBA16F,
        .usage = .STREAM,
    };

    var db_img_desc: sg.ImageDesc = .{
        .width = rasterizer.width,
        .height = rasterizer.height,
        .pixel_format = sg.PixelFormat.R16F,
        .usage = .STREAM,
    };

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

var theta: f32 = 0.0;

export fn frame() void {
    const time_0 = std.time.milliTimestamp();
    rasterizer.render(theta) catch |err| {
        std.debug.print("error: {any}", .{err});
    };
    const time_1 = std.time.milliTimestamp();
    const interval = time_1 - time_0;
    std.debug.print("ms: {d}\n", .{interval});

    var fb_image_data: sg.ImageData = .{};
    fb_image_data.subimage[0][0] = sg.asRange(rasterizer.frame_buffer.buffer);
    sg.updateImage(state.bind.fs_images[shd.SLOT_tex], fb_image_data);

    var db_image_data: sg.ImageData = .{};
    db_image_data.subimage[0][0] = sg.asRange(rasterizer.depth_buffer.buffer);
    sg.updateImage(state.dbg_bind.fs_images[shd.SLOT_tex], db_image_data);

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

    theta += 0.06;
}

export fn cleanup() void {
    rasterizer.deinit();
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{ .init_cb = init, .frame_cb = frame, .cleanup_cb = cleanup, .width = rasterizer.width, .height = rasterizer.height, .icon = .{
        .sokol_default = true,
    }, .window_title = "ZigSoftwareRasterizerCPU" });
}
