const std = @import("std");
const Vec3 = @import("../math/vec3.zig").Vec3;
const zigimg = @import("zigimg");

pub const RGB = struct { x: f16, y: f16, z: f16 };

pub const PBR = struct {
    albedo: RGB,
    normal: RGB,
    metallic: f16,
    roughness: f16,
    ao: f16,
};

pub const PBRSolid = struct {
    albedo: RGB,
    metallic: f16,
    roughness: f16,
    ao: f16,
};

pub const TextureType = enum { Seperate, RMPacked, ARMPacked };

pub const PBRTextureDescriptor = struct {
    albedo_tex_path: ?[]const u8,
    normal_tex_path: ?[]const u8,
    metallic_tex_path: ?[]const u8,
    roughness_tex_path: ?[]const u8,
    occlusion_tex_path: ?[]const u8,
    normal_scale: f32 = 1.0,
};

pub const PBRPackedTextureDescriptor = struct {
    albedo_tex_path: []const u8,
    normal_tex_path: []const u8,
    // AO/Roughness/Metallic Packed Texture
    arm_tex_path: []const u8,
    // roughness_tex_path: []u8,
};

pub const TexturePBR = struct {
    width: usize,
    height: usize,
    buffer: []PBR,

    pub fn loadTextureFromDescriptor(desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
        // TODO: we are assume the roughness/metallic textures are present by unwrapping it blindly

        if (desc.roughness_tex_path != null and desc.metallic_tex_path != null) {
            if (std.mem.eql(u8, desc.roughness_tex_path.?, desc.metallic_tex_path.?)) {
                return loadARMTextureFromDescriptor(desc, allocator);
            } else {
                if (desc.occlusion_tex_path) |_| {
                    return loadSeperateTextureFromDescriptorAO(desc, allocator);
                } else {
                    return loadSeperateTextureFromDescriptor(desc, allocator);
                }
            }
        } else {
            return loadAlbedoTextureFromDescriptor(desc, allocator);
        }
    }

    pub fn loadSeperateTextureFromDescriptorAO(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
        var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var normal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var metal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var roughness_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var occlusion_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

        var albedo_file: std.fs.File = undefined;
        var normal_file: std.fs.File = undefined;
        var metalness_file: std.fs.File = undefined;
        var roughness_file: std.fs.File = undefined;
        var occlusion_file: std.fs.File = undefined;

        defer albedo_file.close();
        defer normal_file.close();
        defer metalness_file.close();
        defer roughness_file.close();
        defer occlusion_file.close();

        std.debug.print("Albedo file path: {s}\n", .{tex_desc.albedo_tex_path.?});
        std.debug.print("Normal file path: {s}\n", .{tex_desc.normal_tex_path.?});
        std.debug.print("Metallic file path: {s}\n", .{tex_desc.metallic_tex_path.?});
        std.debug.print("Roughness file path: {s}\n", .{tex_desc.roughness_tex_path.?});
        std.debug.print("Occlusion file path: {s}\n", .{tex_desc.occlusion_tex_path.?});
        std.debug.print("----\n", .{});

        // Assume all file paths are either absolute or relative
        if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
            albedo_file = try std.fs.openFileAbsolute(tex_desc.albedo_tex_path.?, .{});
            normal_file = try std.fs.openFileAbsolute(tex_desc.normal_tex_path.?, .{});
            metalness_file = try std.fs.openFileAbsolute(tex_desc.metallic_tex_path.?, .{});
            roughness_file = try std.fs.openFileAbsolute(tex_desc.roughness_tex_path.?, .{});
            occlusion_file = try std.fs.openFileAbsolute(tex_desc.occlusion_tex_path.?, .{});
        } else {
            albedo_file = try std.fs.cwd().openFile(tex_desc.albedo_tex_path.?, .{});
            normal_file = try std.fs.cwd().openFile(tex_desc.normal_tex_path.?, .{});
            metalness_file = try std.fs.cwd().openFile(tex_desc.metallic_tex_path.?, .{});
            roughness_file = try std.fs.cwd().openFile(tex_desc.roughness_tex_path.?, .{});
            occlusion_file = try std.fs.cwd().openFile(tex_desc.occlusion_tex_path.?, .{});
        }

        const albedo_tex = try zigimg.Image.fromFile(allocator, albedo_file, albedo_read_buffer[0..]);
        const normal_tex = try zigimg.Image.fromFile(allocator, normal_file, normal_read_buffer[0..]);
        const metal_tex = try zigimg.Image.fromFile(allocator, metalness_file, metal_read_buffer[0..]);
        const roughness_tex = try zigimg.Image.fromFile(allocator, roughness_file, roughness_read_buffer[0..]);
        const occlusion_tex = try zigimg.Image.fromFile(allocator, occlusion_file, occlusion_read_buffer[0..]);

        std.debug.assert(albedo_tex.width == metal_tex.width and metal_tex.width == roughness_tex.width and roughness_tex.width == normal_tex.width);
        std.debug.assert(albedo_tex.height == metal_tex.height and metal_tex.height == roughness_tex.height and roughness_tex.height == normal_tex.height);

        const tex_format = albedo_tex.pixelFormat();
        const bits_per_channel = tex_format.bitsPerChannel();
        const channel_count = tex_format.channelCount();

        var _buffer: []PBR = undefined;

        if (allocator.alloc(PBR, albedo_tex.width * albedo_tex.height)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.panic("error: {any}", .{err});
        }

        var index: usize = 0;
        if (channel_count == 3) {
            if (bits_per_channel == 8) {
                for (albedo_tex.pixels.rgb24, normal_tex.pixels.rgb24, metal_tex.pixels.grayscale8, roughness_tex.pixels.grayscale8, occlusion_tex.pixels.grayscale8) |a, n, m, r, o| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const metal_value = m.toColorf32().r;
                    const roughness_value = r.toColorf32().r;
                    const occlusion_value = o.toColorf32().r;
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    _buffer[index].ao = @floatCast(occlusion_value);
                    index += 1;
                }
            } else {
                for (albedo_tex.pixels.rgb48, normal_tex.pixels.rgb48, metal_tex.pixels.grayscale16, roughness_tex.pixels.grayscale16, occlusion_tex.pixels.grayscale16) |a, n, m, r, o| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const metal_value = m.toColorf32().r;
                    const roughness_value = r.toColorf32().r;
                    const occlusion_value = o.toColorf32().r;
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
                    // _buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
                    // _buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    _buffer[index].ao = @floatCast(occlusion_value);
                    index += 1;
                }
            }
        } else {
            std.debug.panic("Format Not Found. Channels: {}, Bits per channel: {}\n", .{ channel_count, bits_per_channel });
        }

        return TexturePBR{
            .width = albedo_tex.width,
            .height = albedo_tex.height,
            .buffer = _buffer,
        };
    }

    pub fn loadSeperateTextureFromDescriptor(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
        var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var normal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var metal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var roughness_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

        var albedo_file: std.fs.File = undefined;
        var normal_file: std.fs.File = undefined;
        var metalness_file: std.fs.File = undefined;
        var roughness_file: std.fs.File = undefined;

        defer albedo_file.close();
        defer normal_file.close();
        defer metalness_file.close();
        defer roughness_file.close();

        std.debug.print("Albedo file path: {s}\n", .{tex_desc.albedo_tex_path.?});
        std.debug.print("Normal file path: {s}\n", .{tex_desc.normal_tex_path.?});
        std.debug.print("Metallic file path: {s}\n", .{tex_desc.metallic_tex_path.?});
        std.debug.print("Roughness file path: {s}\n", .{tex_desc.roughness_tex_path.?});
        std.debug.print("----\n", .{});

        // Assume all file paths are either absolute or relative
        if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
            albedo_file = try std.fs.openFileAbsolute(tex_desc.albedo_tex_path.?, .{});
            normal_file = try std.fs.openFileAbsolute(tex_desc.normal_tex_path.?, .{});
            metalness_file = try std.fs.openFileAbsolute(tex_desc.metallic_tex_path.?, .{});
            roughness_file = try std.fs.openFileAbsolute(tex_desc.roughness_tex_path.?, .{});
        } else {
            albedo_file = try std.fs.cwd().openFile(tex_desc.albedo_tex_path.?, .{});
            normal_file = try std.fs.cwd().openFile(tex_desc.normal_tex_path.?, .{});
            metalness_file = try std.fs.cwd().openFile(tex_desc.metallic_tex_path.?, .{});
            roughness_file = try std.fs.cwd().openFile(tex_desc.roughness_tex_path.?, .{});
        }

        const albedo_tex = try zigimg.Image.fromFile(allocator, albedo_file, albedo_read_buffer[0..]);
        const normal_tex = try zigimg.Image.fromFile(allocator, normal_file, normal_read_buffer[0..]);
        const metal_tex = try zigimg.Image.fromFile(allocator, metalness_file, metal_read_buffer[0..]);
        const roughness_tex = try zigimg.Image.fromFile(allocator, roughness_file, roughness_read_buffer[0..]);

        std.debug.assert(albedo_tex.width == metal_tex.width and metal_tex.width == roughness_tex.width and roughness_tex.width == normal_tex.width);
        std.debug.assert(albedo_tex.height == metal_tex.height and metal_tex.height == roughness_tex.height and roughness_tex.height == normal_tex.height);

        const tex_format = albedo_tex.pixelFormat();
        const bits_per_channel = tex_format.bitsPerChannel();
        const channel_count = tex_format.channelCount();

        var _buffer: []PBR = undefined;

        if (allocator.alloc(PBR, albedo_tex.width * albedo_tex.height)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.panic("error: {any}", .{err});
        }

        var index: usize = 0;
        if (channel_count == 3) {
            if (bits_per_channel == 8) {
                for (albedo_tex.pixels.rgb24, normal_tex.pixels.rgb24, metal_tex.pixels.grayscale8, roughness_tex.pixels.grayscale8) |a, n, m, r| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const metal_value = m.toColorf32().r;
                    const roughness_value = r.toColorf32().r;
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
                    // _buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
                    // _buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    index += 1;
                }
            } else {
                for (albedo_tex.pixels.rgb48, normal_tex.pixels.rgb48, metal_tex.pixels.grayscale16, roughness_tex.pixels.grayscale16) |a, n, m, r| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const metal_value = m.toColorf32().r;
                    const roughness_value = r.toColorf32().r;
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
                    // _buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
                    // _buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    index += 1;
                }
            }
        } else {
            std.debug.panic("Format Not Found. Channels: {}, Bits per channel: {}\n", .{ channel_count, bits_per_channel });
        }

        return TexturePBR{
            .width = albedo_tex.width,
            .height = albedo_tex.height,
            .buffer = _buffer,
        };
    }

    pub fn loadAlbedoTextureFromDescriptor(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
        var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

        var albedo_file: std.fs.File = undefined;

        defer albedo_file.close();

        std.debug.print("Albedo file path: {s}\n", .{tex_desc.albedo_tex_path.?});
        std.debug.print("----\n", .{});

        // Assume all file paths are either absolute or relative
        if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
            albedo_file = try std.fs.openFileAbsolute(tex_desc.albedo_tex_path.?, .{});
        } else {
            albedo_file = try std.fs.cwd().openFile(tex_desc.albedo_tex_path.?, .{});
        }

        const albedo_tex = try zigimg.Image.fromFile(allocator, albedo_file, albedo_read_buffer[0..]);

        const tex_format = albedo_tex.pixelFormat();
        const bits_per_channel = tex_format.bitsPerChannel();
        const channel_count = tex_format.channelCount();

        var _buffer: []PBR = undefined;

        if (allocator.alloc(PBR, albedo_tex.width * albedo_tex.height)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.panic("error: {any}", .{err});
        }

        var index: usize = 0;
        if (channel_count == 3) {
            if (bits_per_channel == 8) {
                for (albedo_tex.pixels.rgb24) |a| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    _buffer[index].metallic = 0.0;
                    _buffer[index].roughness = 0.0;
                    _buffer[index].ao = 0.1;
                    index += 1;
                }
            } else {
                for (albedo_tex.pixels.rgb48) |a| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    _buffer[index].metallic = 0.0;
                    _buffer[index].roughness = 0.0;
                    _buffer[index].ao = 0.1;
                    index += 1;
                }
            }
        } else if (channel_count == 4) {
            if (bits_per_channel == 8) {
                for (albedo_tex.pixels.rgba32) |a| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    _buffer[index].metallic = 0.0;
                    _buffer[index].roughness = 0.0;
                    _buffer[index].ao = 0.1;
                    index += 1;
                }
            } else {
                for (albedo_tex.pixels.rgba64) |a| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    _buffer[index].metallic = 0.0;
                    _buffer[index].roughness = 0.0;
                    _buffer[index].ao = 0.1;
                    index += 1;
                }
            }
        } else {
            std.debug.panic("Format Not Found. Channels: {}, Bits per channel: {}\n", .{ channel_count, bits_per_channel });
        }

        return TexturePBR{
            .width = albedo_tex.width,
            .height = albedo_tex.height,
            .buffer = _buffer,
        };
    }

    pub fn loadRMTextureFromDescriptor(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
        var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var normal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var rm_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

        var albedo_file: std.fs.File = undefined;
        var normal_file: std.fs.File = undefined;
        var rm_file: std.fs.File = undefined;

        defer albedo_file.close();
        defer normal_file.close();
        defer rm_file.close();

        std.debug.print("Albedo file path: {s}\n", .{tex_desc.albedo_tex_path.?});
        std.debug.print("Normal file path: {s}\n", .{tex_desc.normal_tex_path.?});
        std.debug.print("Metallic file path: {s}\n", .{tex_desc.metallic_tex_path.?});
        std.debug.print("Roughness file path: {s}\n", .{tex_desc.roughness_tex_path.?});
        std.debug.print("----\n", .{});

        // Assume all file paths are either absolute or relative
        if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
            albedo_file = try std.fs.openFileAbsolute(tex_desc.albedo_tex_path.?, .{});
            normal_file = try std.fs.openFileAbsolute(tex_desc.normal_tex_path.?, .{});
            rm_file = try std.fs.openFileAbsolute(tex_desc.roughness_tex_path.?, .{});
        } else {
            albedo_file = try std.fs.cwd().openFile(tex_desc.albedo_tex_path.?, .{});
            normal_file = try std.fs.cwd().openFile(tex_desc.normal_tex_path.?, .{});
            rm_file = try std.fs.cwd().openFile(tex_desc.roughness_tex_path.?, .{});
        }

        const albedo_tex = try zigimg.Image.fromFile(allocator, albedo_file, albedo_read_buffer[0..]);
        const normal_tex = try zigimg.Image.fromFile(allocator, normal_file, normal_read_buffer[0..]);
        const rm_tex = try zigimg.Image.fromFile(allocator, rm_file, rm_read_buffer[0..]);

        std.debug.assert(albedo_tex.width == rm_tex.width and rm_tex.width == normal_tex.width);
        std.debug.assert(albedo_tex.height == rm_tex.height and rm_tex.height == normal_tex.height);

        const tex_format = albedo_tex.pixelFormat();
        const bits_per_channel = tex_format.bitsPerChannel();
        const channel_count = tex_format.channelCount();

        var _buffer: []PBR = undefined;

        if (allocator.alloc(PBR, albedo_tex.width * albedo_tex.height)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.panic("error: {any}", .{err});
        }

        var index: usize = 0;
        if (channel_count == 3) {
            if (bits_per_channel == 8) {
                for (albedo_tex.pixels.rgb24, normal_tex.pixels.rgb24, rm_tex.pixels.rgb24) |a, n, rm| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const roughness_value = rm.to.float4()[0];
                    const metal_value = rm.to.float4()[1];
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
                    // _buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
                    // _buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    _buffer[index].ao = 0.1;
                    index += 1;
                }
            } else {
                for (albedo_tex.pixels.rgb48, normal_tex.pixels.rgb48, rm_tex.pixels.rgb48) |a, n, rm| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const roughness_value = rm.to.float4()[0];
                    const metal_value = rm.to.float4()[1];
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
                    // _buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
                    // _buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    _buffer[index].ao = 0.1;
                    index += 1;
                }
            }
        } else {
            std.debug.panic("Format Not Found. Channels: {}, Bits per channel: {}\n", .{ channel_count, bits_per_channel });
        }

        return TexturePBR{
            .width = albedo_tex.width,
            .height = albedo_tex.height,
            .buffer = _buffer,
        };
    }

    pub fn loadARMTextureFromDescriptor(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
        var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var normal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
        var arm_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

        var albedo_file: std.fs.File = undefined;
        var normal_file: std.fs.File = undefined;
        var arm_file: std.fs.File = undefined;

        defer albedo_file.close();
        defer normal_file.close();
        defer arm_file.close();

        std.debug.print("Albedo file path: {s}\n", .{tex_desc.albedo_tex_path.?});
        std.debug.print("Normal file path: {s}\n", .{tex_desc.normal_tex_path.?});
        std.debug.print("AO/Roughness/Metallic file path: {s}\n", .{tex_desc.roughness_tex_path.?});
        std.debug.print("----\n", .{});

        // Assume all file paths are either absolute or relative
        if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
            albedo_file = try std.fs.openFileAbsolute(tex_desc.albedo_tex_path.?, .{});
            normal_file = try std.fs.openFileAbsolute(tex_desc.normal_tex_path.?, .{});
            arm_file = try std.fs.openFileAbsolute(tex_desc.roughness_tex_path.?, .{});
        } else {
            albedo_file = try std.fs.cwd().openFile(tex_desc.albedo_tex_path.?, .{});
            normal_file = try std.fs.cwd().openFile(tex_desc.normal_tex_path.?, .{});
            arm_file = try std.fs.cwd().openFile(tex_desc.roughness_tex_path.?, .{});
        }

        const albedo_tex = try zigimg.Image.fromFile(allocator, albedo_file, albedo_read_buffer[0..]);
        const normal_tex = try zigimg.Image.fromFile(allocator, normal_file, normal_read_buffer[0..]);
        const arm_tex = try zigimg.Image.fromFile(allocator, arm_file, arm_read_buffer[0..]);

        std.debug.assert(albedo_tex.width == arm_tex.width and arm_tex.width == normal_tex.width);
        std.debug.assert(albedo_tex.height == arm_tex.height and arm_tex.height == normal_tex.height);

        const tex_format = albedo_tex.pixelFormat();
        const bits_per_channel = tex_format.bitsPerChannel();
        const channel_count = tex_format.channelCount();

        var _buffer: []PBR = undefined;

        if (allocator.alloc(PBR, albedo_tex.width * albedo_tex.height)) |_buf| {
            _buffer = _buf;
        } else |err| {
            std.debug.panic("error: {any}", .{err});
        }

        var index: usize = 0;
        if (channel_count == 3) {
            if (bits_per_channel == 8) {
                for (albedo_tex.pixels.rgb24, normal_tex.pixels.rgb24, arm_tex.pixels.rgba32) |a, n, arm| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const ao_value = arm.to.float4()[0];
                    const roughness_value = arm.to.float4()[1];
                    const metal_value = arm.to.float4()[2];
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
                    // _buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
                    // _buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    _buffer[index].ao = @floatCast(ao_value);
                    index += 1;
                }
            } else {
                for (albedo_tex.pixels.rgb48, normal_tex.pixels.rgb48, arm_tex.pixels.rgb48) |a, n, arm| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const ao_value = arm.to.float4()[0];
                    const roughness_value = arm.to.float4()[1];
                    const metal_value = arm.to.float4()[2];
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
                    // _buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
                    // _buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    _buffer[index].ao = @floatCast(ao_value);
                    index += 1;
                }
            }
        } else if (channel_count == 4) {
            if (bits_per_channel == 8) {
                for (albedo_tex.pixels.rgba32, normal_tex.pixels.rgba32, arm_tex.pixels.rgba32) |a, n, arm| {
                    var albedo_value = a.to.float4();
                    albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
                    albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
                    albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
                    const normal_value = n.to.float4();
                    const ao_value = arm.to.float4()[0];
                    const roughness_value = arm.to.float4()[1];
                    const metal_value = arm.to.float4()[2];
                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal = normal.multf(tex_desc.normal_scale);
                    normal = Vec3.normalize(normal);
                    _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
                    _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
                    // _buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
                    // _buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
                    _buffer[index].metallic = @floatCast(metal_value);
                    _buffer[index].roughness = @floatCast(roughness_value);
                    _buffer[index].ao = @floatCast(ao_value);
                    index += 1;
                }
            }
        } else {
            std.debug.panic("Format Not Found. Channels: {}, Bits per channel: {}\n", .{ channel_count, bits_per_channel });
        }

        return TexturePBR{
            .width = albedo_tex.width,
            .height = albedo_tex.height,
            .buffer = _buffer,
        };
    }

    pub fn deinit(texture: TexturePBR, allocator: std.mem.Allocator) void {
        allocator.free(texture.buffer);
    }
};
