const std = @import("std");
const RenderTargetRGBA16 = @import("../renderer/rendertarget.zig").RenderTargetRGBA16;
const Color = @import("../renderer/rendertarget.zig").Color;
// pub const Color = struct { r: f32, g: f32, b: f32 };

pub const RadianceRGBE = struct {
    r: u8,
    g: u8,
    b: u8,
    e: u8,
    fn fromColor(color: Color) RadianceRGBE {
        const v = @max(color.r, color.g, color.b);

        const frexp = std.math.frexp(v);

        const scale = std.math.ldexp(@as(f16, 256.0), @as(i32, -1) * @as(i32, frexp.exponent));

        return .{
            .r = @as(u8, @intFromFloat(std.math.clamp(color.r * scale, 0, 255))),
            .g = @as(u8, @intFromFloat(std.math.clamp(color.g * scale, 0, 255))),
            .b = @as(u8, @intFromFloat(std.math.clamp(color.b * scale, 0, 255))),
            .e = @as(u8, @intCast(frexp.exponent + 128)),
        };
    }
};

pub const Radiance = struct {
    width: usize,
    height: usize,
    r: []f32,
    g: []f32,
    b: []f32,
    e: []f32,

    pub fn writeToDisk(file_path: []const u8, rendertarget: *RenderTargetRGBA16) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        // std.Io.write
        var buffer: [4096]u8 = undefined;
        var fsdf = file.writer(&buffer);
        var file_writer: *std.fs.File.Writer = &fsdf;
        var writer = &file_writer.interface;

        try writer.print("#?RADIANCE\n", .{});
        try writer.print("FORMAT=32-bit_rle_rgbe\n", .{});
        try writer.print("SOFTWARE=ZigCPURasterizer\n\n", .{});
        try writer.print("-Y {d} +X {d}\n", .{ rendertarget.height, rendertarget.width });

        for (0..rendertarget.height) |y| {
            for (0..rendertarget.width) |x| {
                // const c = Color{
                // .r = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width)),
                // .g = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width)),
                // .b = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width)),
                // };
                // const c = pixels[y * width + x];
                const radiance_c = RadianceRGBE.fromColor(rendertarget.getPixel(@intCast(x), @intCast(y)));
                try writer.writeByte(radiance_c.r);
                try writer.writeByte(radiance_c.g);
                try writer.writeByte(radiance_c.b);
                try writer.writeByte(radiance_c.e);
            }
        }
        try writer.flush();
    }
};
