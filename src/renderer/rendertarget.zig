const std = @import("std");
const Vec2 = @import("../vec2.zig").Vec2;

pub const Color = struct { r: f16, g: f16, b: f16 };

pub const RenderTargetR16 = struct {
    width: u32,
    height: u32,
    buffer: []f16,
    allocator: std.mem.Allocator,

    pub fn create(_allocator: std.mem.Allocator, _width: u32, _height: u32) RenderTargetR16 {
        var _buffer: []f16 = undefined;

        if (_allocator.alloc(f16, _width * _height)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.print("error: {any}", .{err});
        }

        return RenderTargetR16{
            .width = _width,
            .height = _height,
            .buffer = _buffer,
            .allocator = _allocator,
        };
    }

    pub fn deinit(self: *RenderTargetR16) void {
        self.allocator.free(self.buffer);
    }

    pub fn putPixel(self: *RenderTargetR16, x: u32, y: u32, value: f16) void {
        self.buffer[y * self.width + x] = value;
    }

    pub fn getPixel(self: *RenderTargetR16, x: u32, y: u32) f16 {
        return self.buffer[y * self.width + x];
    }

    pub fn clearColor(self: *RenderTargetR16, value: f16) void {
        std.mem.set(f16, self.buffer, value);
    }
};

pub const RenderTargetRGBA16 = struct {
    width: u32,
    height: u32,
    buffer: []f16,
    allocator: std.mem.Allocator,

    pub fn create(_allocator: std.mem.Allocator, _width: u32, _height: u32) RenderTargetRGBA16 {
        var _buffer: []f16 = undefined;

        if (_allocator.alloc(f16, _width * _height * 4)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.print("error: {any}", .{err});
        }
        return RenderTargetRGBA16{
            .width = _width,
            .height = _height,
            .allocator = _allocator,
            .buffer = _buffer,
        };
    }

    pub fn deinit(self: *RenderTargetRGBA16) void {
        self.allocator.free(self.buffer);
    }

    pub fn putPixel(self: *RenderTargetRGBA16, x: u32, y: u32, color: Color) void {
        self.buffer[y * 4 * self.width + (x * 4 + 0)] = color.r;
        self.buffer[y * 4 * self.width + (x * 4 + 1)] = color.g;
        self.buffer[y * 4 * self.width + (x * 4 + 2)] = color.b;
        self.buffer[y * 4 * self.width + (x * 4 + 3)] = 1.0;
    }

    pub fn clearColor(self: *RenderTargetRGBA16, value: f16) void {
        std.mem.set(f16, self.buffer, value);
    }
};
