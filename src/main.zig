const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sglue = sokol.glue;

const sg = sokol.gfx;
const sapp = sokol.app;
const sgapp = sokol.app_gfx_glue;

const shd = @import("shader");
const rasterizer = @import("renderer/rasterizer.zig");
const zigimg = @import("zigimg");
const clap = @import("clap");

const Color = @import("renderer/rendertarget.zig").Color;
const Radiance = @import("utils/radiance_file.zig").Radiance;

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var pass_action: sg.PassAction = .{};

    var fb_image: sg.Image = .{};
    var db_image: sg.Image = .{};

    var dbg_pip: sg.Pipeline = .{};
    var dbg_bind: sg.Bindings = .{};
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    const quad_vbuf = sg.makeBuffer(.{ .data = sg.asRange(&[_]f32{ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0 }) });

    const fb_img_desc: sg.ImageDesc = .{
        .width = @intCast(rasterizer.width),
        .height = @intCast(rasterizer.height),
        .pixel_format = sg.PixelFormat.RGBA16F,
        .usage = .{ .stream_update = true },
    };

    const db_img_desc: sg.ImageDesc = .{
        .width = @intCast(rasterizer.width),
        .height = @intCast(rasterizer.height),
        .pixel_format = sg.PixelFormat.R32F,
        .usage = .{ .stream_update = true },
    };

    state.bind.vertex_buffers[0] = quad_vbuf;

    state.fb_image = sg.makeImage(fb_img_desc);
    state.db_image = sg.makeImage(db_img_desc);

    const sampler = sg.makeSampler(.{
        .min_filter = sg.Filter.LINEAR,
        .mag_filter = sg.Filter.LINEAR,
        .wrap_u = sg.Wrap.CLAMP_TO_EDGE,
        .wrap_v = sg.Wrap.CLAMP_TO_EDGE,
        .label = "png-sampler",
    });

    state.bind.samplers[shd.SMP_smp] = sampler;
    state.dbg_bind.samplers[shd.SMP_smp] = sampler;

    state.bind.views[shd.VIEW_tex] = sg.makeView(.{
        .texture = .{
            .image = state.fb_image,
        },
    });

    const shader = sg.makeShader(shd.shaderShaderDesc(sg.queryBackend()));

    var pip_desc: sg.PipelineDesc = .{
        .primitive_type = .TRIANGLE_STRIP,
        .shader = shader,
    };
    pip_desc.layout.attrs[shd.ATTR_shader_position].format = .FLOAT2;
    state.pip = sg.makePipeline(pip_desc);

    state.dbg_bind.vertex_buffers[0] = quad_vbuf;
    state.dbg_bind.views[shd.VIEW_tex] = sg.makeView(.{
        .texture = .{
            .image = state.db_image,
        },
    });
    var dbg_pip_desc: sg.PipelineDesc = .{
        .primitive_type = .TRIANGLE_STRIP,
        .shader = shader,
    };
    dbg_pip_desc.layout.attrs[shd.ATTR_shader_position].format = .FLOAT2;
    state.dbg_pip = sg.makePipeline(dbg_pip_desc);

    state.pass_action.colors[0] = .{ .load_action = sg.LoadAction.CLEAR, .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 } };
}

var time_accum: i64 = 0;
var num_frames: u64 = 0;
const to_rad = std.math.pi / 180.0;
var animation_time_start: i64 = 0;
var animation_time_accum: i64 = 0;

var anim_play: bool = true;

const animation_len = 10 * std.time.ms_per_s;

var min_time: i64 = 1000000;
var max_time: i64 = 0;
var min_avg_time: f64 = 10000000.0;
var max_avg_time: f64 = 0.0;
var camera_idx: usize = 0;

export fn frame() void {
    if (num_frames == 1000) {
        num_frames = 0;
        time_accum = 0;
    }
    const animation_time_end = std.time.milliTimestamp();
    const animation_time_diff = animation_time_end - animation_time_start;
    if (anim_play) animation_time_accum += animation_time_diff;
    // We want to rotate the object by 360 in second (despite framerate)
    // we map millisecond time to range [0.0, 1.0] the convert it to range in degrees
    const normalized_time = @as(f32, @floatFromInt(@mod(animation_time_accum, animation_len))) / animation_len;
    animation_time_start = std.time.milliTimestamp();
    const theta = normalized_time * (360 * to_rad);

    const time_0 = std.time.milliTimestamp();
    rasterizer.render(theta, camera_idx) catch |err| {
        std.debug.print("error: {any}", .{err});
    };
    const time_1 = std.time.milliTimestamp();
    const interval = time_1 - time_0;
    time_accum += interval;

    var fb_image_data: sg.ImageData = .{};
    fb_image_data.mip_levels[0] = sg.asRange(rasterizer.opaque_fb.buffer);
    sg.updateImage(state.fb_image, fb_image_data);

    var db_image_data: sg.ImageData = .{};
    db_image_data.mip_levels[0] = sg.asRange(rasterizer.depth_buffer.buffer);
    sg.updateImage(state.db_image, db_image_data);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.draw(0, 4, 1);

    // sg.applyPipeline(state.dbg_pip);
    // sg.applyViewport(0 * 150, 0, 150, 150, false);
    // sg.applyBindings(state.dbg_bind);
    // sg.draw(0, 4, 1);

    sg.endPass();
    sg.commit();

    var buffer: [256:0]u8 = undefined;
    const avg_time: f64 = @as(f64, @floatFromInt(time_accum)) / @as(f64, @floatFromInt(num_frames));
    const window_title = std.fmt.bufPrintZ(&buffer, "ZigCPURasterizer | {d} ms | Avg {d:.5} ms", .{ interval, avg_time }) catch "ZigCPURasterizer";
    sapp.setWindowTitle(window_title);
    if (interval < min_time) min_time = interval;
    if (interval > max_time) max_time = interval;
    if (avg_time < min_avg_time) min_avg_time = avg_time;
    if (avg_time > max_avg_time and avg_time != std.math.inf(f64) and num_frames > 30) max_avg_time = avg_time;
    num_frames += 1;
}

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    switch (event.type) {
        .KEY_DOWN => {
            switch (event.key_code) {
                .Q, .ESCAPE => {
                    std.debug.print("Frame Time (Min - Max): {d} - {d}\n", .{ min_time, max_time });
                    std.debug.print("Avg.  Time (Min - Max): {d:.5} - {d:.5}\n", .{ min_avg_time, max_avg_time });
                    sapp.requestQuit();
                },
                .SPACE => {
                    if (anim_play) {
                        anim_play = false;
                    } else {
                        anim_play = true;
                    }
                    camera_idx += 1;
                },
                else => {},
            }
        },
        else => {},
    }
}

export fn cleanup() void {
    rasterizer.deinit();
    sg.shutdown();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interactive = false;
    var input_file: []const u8 = undefined;
    var output_file: []const u8 = undefined;
    input_file.len = 0;
    output_file.len = 0;
    var input_file_extension: []const u8 = undefined;
    var output_file_extension: []const u8 = undefined;
    input_file_extension.len = 0;
    output_file.len = 0;

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\--interactive             Display this help and exit.
        \\-i, --input <str>   An option parameter, which takes a value.
        \\-o, --output <str>  An option parameter which can be specified multiple times.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .assignment_separators = "=:",
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0 or (res.args.interactive == 0 and res.args.input == null and res.args.output == null)) {
        std.debug.print("{s}", .{help_string});
        return;
    }

    if (res.args.interactive != 0) {
        interactive = true;
    }

    if (res.args.input) |n| {
        input_file = n;
        input_file_extension = std.fs.path.extension(input_file);
        if (!std.mem.eql(u8, input_file_extension, ".gltf")) {
            std.debug.print("Invalid input file type '{s}', only '.gltf' file is supported. Make sure path is correct.\n", .{input_file_extension});
            return;
        }
    } else {
        std.debug.print("{s}", .{input_file_help_string});
        return;
    }

    if (res.args.output) |s| {
        output_file = s;
        output_file_extension = std.fs.path.extension(output_file);
        if (!(std.mem.eql(u8, output_file_extension, ".hdr") or std.mem.eql(u8, output_file_extension, ".png"))) {
            std.debug.print("Invalid export file type '{s}', only '.hdr' for HDR image and '.png' for SDR image are supported.\n", .{output_file_extension});
            return;
        }
    } else {
        if (interactive == false) {
            std.debug.print("{s}", .{output_file_help_string});
            return;
        }
    }

    if (!interactive) {
        rasterizer.init(input_file) catch |err| {
            std.debug.print("Error initializing the rasterizer: {any}\n", .{err});
        };
        defer rasterizer.deinit();

        var file_name_buffer: [100]u8 = undefined;
        for (0..rasterizer.scene.cameras.items.len) |idx| {
            try rasterizer.render(0, idx);

            const formated_string = try std.fmt.bufPrint(&file_name_buffer, "{d}_{s}", .{ idx, output_file });
            if (std.mem.eql(u8, output_file_extension, ".hdr")) {
                try Radiance.writeToDisk(formated_string, &rasterizer.opaque_fb);
            } else if (std.mem.eql(u8, output_file_extension, ".png")) {
                const width = rasterizer.opaque_fb.width;
                const height = rasterizer.opaque_fb.height;

                var image_write_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
                var image = try zigimg.Image.create(allocator, width, height, .rgb24);
                defer image.deinit(allocator);

                for (0..height) |y| {
                    for (0..width) |x| {
                        var col = rasterizer.opaque_fb.getPixel(@intCast(x), @intCast(y));
                        col.r /= col.r + 1.0;
                        col.g /= col.g + 1.0;
                        col.b /= col.b + 1.0;
                        const col_srgb = zigimg.color.sRGB.toGamma(zigimg.color.Colorf32.from.color(col));
                        image.pixels.rgb24[y * width + x] = zigimg.color.Rgb24.from.color(col_srgb);
                    }
                }

                try image.writeToFilePath(allocator, formated_string, &image_write_buffer, .{ .png = .{} });
            }
        }
    } else {
        rasterizer.init(input_file) catch |err| {
            std.debug.print("Error initializing the rasterizer: {any}\n", .{err});
        };

        sapp.run(
            .{
                .init_cb = init,
                .frame_cb = frame,
                .cleanup_cb = cleanup,
                //TODO: Fix width and height here
                .width = @intCast(rasterizer.width),
                .height = @intCast(rasterizer.height),
                .icon = .{
                    .sokol_default = true,
                },
                .window_title = "ZigSoftwareRasterizerCPU",
                .event_cb = input,
            },
        );
    }
}

const help_string =
    \\ Usage: ZigCPURasterizer [commands] [options]
    \\
    \\ Commands:
    \\     --interactive                          Launch rasterizer in interactive mode.
    \\
    \\ Options:
    \\     -i [GLTF_FILE_PATH].gltf             Input glTF file. Currently only ".glTF" file is supported.
    \\     -o [IMAGE_FILE_PATH].[hdr/png]       Output Image. Currently only ".hdr" (HDR range) and ".png" (SDR range) file is supported.
    \\
;

const input_file_help_string =
    \\ No input file detected.
    \\
    \\ Options:
    \\     -i [GLTF_FILE_PATH].gltf             Input glTF file. Currently only ".glTF" file is supported.
    \\
    \\ Note: CLI arguments parser is pretty dumb. So, do EXACTLY as it says.
    \\
;

const output_file_help_string =
    \\ No output file detected.
    \\
    \\ Options:
    \\     -o [IMAGE_FILE_PATH].[hdr/png]       Output Image. Currently only ".hdr" (HDR range) and ".png" (SDR range) file is supported.
    \\
    \\ Note: CLI arguments parser is pretty dumb. So, do EXACTLY as it says.
    \\
;
