const std = @import("std");
const Vec2 = @import("../vec2.zig").Vec2;

pub const Color = struct { r: f32, g: f32, b: f32 };

pub const RenderTargetR32 = struct {
    width: u32,
    height: u32,
    buffer: []f32,
    allocator: std.mem.Allocator,

    pub fn create(_allocator: std.mem.Allocator, _width: u32, _height: u32) RenderTargetR32 {
        var _buffer: []f32 = undefined;

        if (_allocator.alloc(f32, _width * _height)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.print("error: {any}", .{err});
        }

        return RenderTargetR32{
            .width = _width,
            .height = _height,
            .buffer = _buffer,
            .allocator = _allocator,
        };
    }

    pub fn deinit(self: *RenderTargetR32) void {
        self.allocator.free(self.buffer);
    }

    pub fn putPixel(self: *RenderTargetR32, x: u32, y: u32, value: f32) void {
        self.buffer[y * self.width + x] = value;
    }

    pub fn getPixel(self: *RenderTargetR32, x: u32, y: u32) f32 {
        return self.buffer[y * self.width + x];
    }

    pub fn clearColor(self: *RenderTargetR32, value: f32) void {
        var y: u32 = 0;
        var x: u32 = 0;
        while (y < self.height) : (y += 1) {
            while (x < self.width) : (x += 1) {
                self.putPixel(x, y, value);
            }
            x = 0;
        }
    }
};

pub const RenderTargetRGBA32 = struct {
    width: u32,
    height: u32,
    buffer: []f32,
    allocator: std.mem.Allocator,

    pub fn create(_allocator: std.mem.Allocator, _width: u32, _height: u32) RenderTargetRGBA32 {
        var _buffer: []f32 = undefined;

        if (_allocator.alloc(f32, _width * _height * 4)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.print("error: {any}", .{err});
        }
        return RenderTargetRGBA32{
            .width = _width,
            .height = _height,
            .allocator = _allocator,
            .buffer = _buffer,
        };
    }

    pub fn deinit(self: *RenderTargetRGBA32) void {
        self.allocator.free(self.buffer);
    }

    pub fn putPixel(self: *RenderTargetRGBA32, x: u32, y: u32, color: Color) void {
        self.buffer[y * 4 * self.width + (x * 4 + 0)] = color.r;
        self.buffer[y * 4 * self.width + (x * 4 + 1)] = color.g;
        self.buffer[y * 4 * self.width + (x * 4 + 2)] = color.b;
        self.buffer[y * 4 * self.width + (x * 4 + 3)] = 1.0;
    }

    pub fn clearColor(self: *RenderTargetRGBA32, color: Color) void {
        var y: u32 = 0;
        var x: u32 = 0;
        while (y < self.height) : (y += 1) {
            while (x < self.width) : (x += 1) {
                self.putPixel(x, y, color);
            }
            x = 0;
        }
    }
};
