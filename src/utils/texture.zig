const std = @import("std");
const Vec3 = @import("../math/vec3.zig").Vec3;
const zigimg = @import("zigimg");

pub const RGB = struct {
    x: f16,
    y: f16,
    z: f16,

    pub fn lerp(start: RGB, end: RGB, t: f16) RGB {
        return RGB{
            .x = std.math.lerp(start.x, end.x, t),
            .y = std.math.lerp(start.y, end.y, t),
            .z = std.math.lerp(start.z, end.z, t),
        };
    }
};

pub const RGBA = struct {
    x: f16,
    y: f16,
    z: f16,
    w: f16,

    pub fn lerp(start: RGBA, end: RGBA, t: f16) RGBA {
        return RGBA{
            .x = std.math.lerp(start.x, end.x, t),
            .y = std.math.lerp(start.y, end.y, t),
            .z = std.math.lerp(start.z, end.z, t),
            .w = std.math.lerp(start.w, end.w, t),
        };
    }
};

pub const PBR = struct {
    albedo: RGBA,
    normal: RGB,
    metallic: f16,
    roughness: f16,
    ao: f16,
    emissive: RGB,
    transmission: f16,
    ior: f16,

    pub fn lerp(start: PBR, end: PBR, t: f16) PBR {
        return PBR{
            // TODO: This way of mixing color good enough?
            .albedo = RGBA.lerp(start.albedo, end.albedo, t),
            .normal = RGB.lerp(start.normal, end.normal, t),
            .emissive = RGB.lerp(start.emissive, end.emissive, t),
            .metallic = std.math.lerp(start.metallic, end.metallic, t),
            .roughness = std.math.lerp(start.roughness, end.roughness, t),
            .ao = std.math.lerp(start.ao, end.ao, t),
            .transmission = std.math.lerp(start.transmission, end.transmission, t),
            .ior = std.math.lerp(start.ior, end.ior, t),
        };
    }
};

pub const PBRSolid = struct {
    albedo: RGB,
    metallic: f16,
    roughness: f16,
    ao: f16,
    emissive: RGB,
    transmission: f16,
    ior: f16,
};

pub const TextureType = enum { Seperate, RMPacked, ARMPacked };

pub const PBRTextureDescriptor = struct {
    albedo_tex_path: ?[]const u8,
    normal_tex_path: ?[]const u8,
    rm_tex_path: ?[]const u8,
    occlusion_tex_path: ?[]const u8,
    emissive_tex_path: ?[]const u8,
    transmission_tex_path: ?[]const u8,
    emissive_strength: f32,
    color_factor: [4]f32,
    normal_scale: f32,
    metallic_factor: f32,
    roughness_factor: f32,
    occlusion_strength: f32,
    emissive_factor: [3]f32,
    alpha_cutoff: f32,
    transmission_factor: f32,
    ior: f32,
    blend: bool,
};

pub const PBRTexture = struct {
    width: usize,
    height: usize,
    normal: bool = false,
    alpha_cutoff: f32,
    buffer: []PBR,

    fn getFileFromPath(path: []const u8) std.fs.File {
        var file: std.fs.File = undefined;
        if (std.fs.path.isAbsolute(path)) {
            if (std.fs.openFileAbsolute(path, .{})) |f| {
                file = f;
            } else |err| {
                std.debug.panic("Error getting std.fs.File ({any}). Relative Path: {s}", .{ err, path });
            }
        } else {
            if (std.fs.cwd().openFile(path, .{})) |f| {
                file = f;
            } else |err| {
                std.debug.panic("Error getting std.fs.File ({any}). Relative Path: {s}", .{ err, path });
            }
        }
        return file;
    }

    pub fn loadTextureFromDescriptor(desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !PBRTexture {
        var normals: bool = false;
        var occlusion: bool = false;
        var occlusion_seperate: bool = false;

        var texture_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

        var albedo_file: ?std.fs.File = null;
        var normal_file: ?std.fs.File = null;
        var rm_file: ?std.fs.File = null;
        var occlusion_file: ?std.fs.File = null;
        var emissive_file: ?std.fs.File = null;
        var transmission_file: ?std.fs.File = null;

        if (desc.albedo_tex_path) |albedo_tex_path| {
            std.debug.print("Albedo file path: {s}\n", .{albedo_tex_path});
            albedo_file = getFileFromPath(albedo_tex_path);
        }
        if (desc.normal_tex_path) |normal_tex_path| {
            std.debug.print("Normal file path: {s}\n", .{normal_tex_path});
            normal_file = getFileFromPath(normal_tex_path);
            normals = true;
        }
        if (desc.rm_tex_path) |rm_tex_path| {
            std.debug.print("RM file path: {s}\n", .{rm_tex_path});
            rm_file = getFileFromPath(rm_tex_path);
        }
        if (desc.occlusion_tex_path) |occlusion_tex_path| {
            occlusion = true;
            if (!std.mem.eql(u8, occlusion_tex_path, desc.rm_tex_path orelse "fake_path")) {
                occlusion_seperate = true;
            }
            std.debug.print("Occlusion file path (seperate: {}): {s}\n", .{ occlusion_seperate, occlusion_tex_path });
            occlusion_file = getFileFromPath(occlusion_tex_path);
        }
        if (desc.emissive_tex_path) |emissive_tex_path| {
            std.debug.print("Emissive file path: {s}\n", .{emissive_tex_path});
            emissive_file = getFileFromPath(emissive_tex_path);
        }
        if (desc.transmission_tex_path) |transmission_tex_path| {
            std.debug.print("Transmission file path: {s}\n", .{transmission_tex_path});
            transmission_file = getFileFromPath(transmission_tex_path);
        }

        var albedo_tex: ?zigimg.Image = null;
        var normal_tex: ?zigimg.Image = null;
        var rm_tex: ?zigimg.Image = null;
        var occlusion_tex: ?zigimg.Image = null;
        var emissive_tex: ?zigimg.Image = null;
        var transmission_tex: ?zigimg.Image = null;

        var albedo_width: usize = 0;
        var albedo_height: usize = 0;
        var normal_width: usize = 0;
        var normal_height: usize = 0;
        var rm_width: usize = 0;
        var rm_height: usize = 0;
        var occlusion_width: usize = 0;
        var occlusion_height: usize = 0;
        var emissive_width: usize = 0;
        var emissive_height: usize = 0;
        var transmission_width: usize = 0;
        var transmission_height: usize = 0;

        if (albedo_file) |file| {
            var tex = try zigimg.Image.fromFile(allocator, file, texture_read_buffer[0..]);
            albedo_width = tex.width;
            albedo_height = tex.height;

            try tex.convert(allocator, zigimg.PixelFormat.rgba64);
            albedo_tex = tex;
        }
        if (normal_file) |file| {
            var tex = try zigimg.Image.fromFile(allocator, file, texture_read_buffer[0..]);

            normal_width = tex.width;
            normal_height = tex.height;
            try tex.convert(allocator, zigimg.PixelFormat.rgb24);
            normal_tex = tex;
        }
        if (rm_file) |file| {
            var tex = try zigimg.Image.fromFile(allocator, file, texture_read_buffer[0..]);

            rm_width = tex.width;
            rm_height = tex.height;
            occlusion_width = tex.width;
            occlusion_height = tex.height;
            try tex.convert(allocator, zigimg.PixelFormat.rgb24);
            rm_tex = tex;
        }
        if (emissive_file) |file| {
            var tex = try zigimg.Image.fromFile(allocator, file, texture_read_buffer[0..]);

            emissive_width = tex.width;
            emissive_height = tex.height;
            try tex.convert(allocator, zigimg.PixelFormat.rgb24);
            emissive_tex = tex;
        }
        if (transmission_file) |file| {
            var tex = try zigimg.Image.fromFile(allocator, file, texture_read_buffer[0..]);

            transmission_width = tex.width;
            transmission_height = tex.height;
            try tex.convert(allocator, zigimg.PixelFormat.grayscale16);
            transmission_tex = tex;
        }
        if (occlusion and occlusion_seperate) {
            if (occlusion_file) |file| {
                var tex = try zigimg.Image.fromFile(allocator, file, texture_read_buffer[0..]);

                occlusion_width = tex.width;
                occlusion_height = tex.height;
                try tex.convert(allocator, zigimg.PixelFormat.grayscale16);
                occlusion_tex = tex;
            }
        }

        var alloc_width: usize = 0;
        var alloc_height: usize = 0;

        alloc_width = @max(albedo_width, normal_width, rm_width, emissive_width, transmission_width, occlusion_width);
        alloc_height = @max(albedo_height, normal_height, rm_height, emissive_height, transmission_height, occlusion_height);

        var _buffer: []PBR = undefined;

        if (allocator.alloc(PBR, alloc_width * alloc_height)) |_buf| {
            _buffer = _buf;
            var basics_pbr: PBR = undefined;
            basics_pbr.albedo = RGBA{
                .x = @floatCast(desc.color_factor[0]),
                .y = @floatCast(desc.color_factor[1]),
                .z = @floatCast(desc.color_factor[2]),
                .w = @floatCast(desc.color_factor[3]),
            };
            const normal = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
            basics_pbr.normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
            basics_pbr.emissive = RGB{
                .x = @floatCast(desc.emissive_factor[0] * desc.emissive_strength),
                .y = @floatCast(desc.emissive_factor[1] * desc.emissive_strength),
                .z = @floatCast(desc.emissive_factor[2] * desc.emissive_strength),
            };
            basics_pbr.transmission = @floatCast(desc.transmission_factor);
            basics_pbr.metallic = @floatCast(desc.metallic_factor);
            basics_pbr.roughness = @floatCast(desc.roughness_factor);
            basics_pbr.ao = 1.0;
            basics_pbr.ior = @floatCast(desc.ior);
            @memset(_buffer, basics_pbr);
        } else |err| {
            std.debug.panic("Error allocating texture: {any}\n", .{err});
        }

        if (albedo_tex) |img| {
            for (0..albedo_width) |x| {
                for (0..albedo_height) |y| {
                    const sample_index = @mod(y, albedo_height) * albedo_width + @mod(x, albedo_width);
                    const albedo_value = img.pixels.rgba64[sample_index].to.float4();
                    const linear = zigimg.color.sRGB.toLinear(zigimg.color.Colorf32.from.float4(albedo_value)).to.float4();

                    const normal = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };

                    const out_index = y * albedo_width + x;
                    _buffer[out_index].albedo = RGBA{
                        .x = @floatCast(linear[0] * desc.color_factor[0]),
                        .y = @floatCast(linear[1] * desc.color_factor[1]),
                        .z = @floatCast(linear[2] * desc.color_factor[2]),
                        .w = @floatCast(linear[3] * desc.color_factor[3]),
                    };
                    _buffer[out_index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                    // _buffer[out_index].metallic = @floatCast(desc.metallic_factor);
                    // _buffer[out_index].roughness = @floatCast(desc.roughness_factor);
                    // _buffer[out_index].ao = 1.0;
                    // _buffer[out_index].transmission = 0.0;
                    if (desc.blend) {
                        _buffer[out_index].transmission = @floatCast(1.0 - albedo_value[3] * desc.color_factor[3]);
                    }
                    _buffer[out_index].emissive = RGB{
                        .x = @floatCast(desc.emissive_factor[0] * desc.emissive_strength),
                        .y = @floatCast(desc.emissive_factor[1] * desc.emissive_strength),
                        .z = @floatCast(desc.emissive_factor[2] * desc.emissive_strength),
                    };
                }
            }
        }

        if (normal_tex) |img| {
            for (0..normal_width) |x| {
                for (0..normal_height) |y| {
                    const sample_index = @mod(y, normal_height) * normal_width + @mod(x, normal_width);
                    const normal_value = img.pixels.rgb24[sample_index].to.float4();

                    var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
                    normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
                    normal.x = normal.x * desc.normal_scale;
                    normal.y = normal.y * desc.normal_scale;
                    normal = normal.normalize();

                    const out_index = y * normal_width + x;
                    _buffer[out_index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
                }
            }
        }

        if (rm_tex) |img| {
            for (0..rm_width) |x| {
                for (0..rm_height) |y| {
                    const sample_index = @mod(y, rm_height) * rm_width + @mod(x, rm_width);
                    const rm = img.pixels.rgb24[sample_index].to.float4();
                    const roughness_value = rm[1] * desc.roughness_factor;
                    const metal_value = rm[2] * desc.metallic_factor;

                    const out_index = y * rm_width + x;
                    _buffer[out_index].metallic = @floatCast(metal_value);
                    _buffer[out_index].roughness = @floatCast(roughness_value);

                    if (occlusion and !occlusion_seperate) {
                        _buffer[out_index].ao = @floatCast(rm[0] * desc.occlusion_strength);
                    }
                }
            }
        }

        if (emissive_tex) |img| {
            for (0..emissive_width) |x| {
                for (0..emissive_height) |y| {
                    const sample_index = @mod(y, emissive_height) * emissive_width + @mod(x, emissive_width);
                    const color = img.pixels.rgb24[sample_index].to.float4();
                    const linear = zigimg.color.sRGB.toLinear(zigimg.color.Colorf32.from.float4(color)).to.float4();

                    const out_index = y * emissive_width + x;
                    _buffer[out_index].emissive.x = @floatCast(linear[0] * desc.emissive_factor[0] * desc.emissive_strength);
                    _buffer[out_index].emissive.y = @floatCast(linear[1] * desc.emissive_factor[1] * desc.emissive_strength);
                    _buffer[out_index].emissive.z = @floatCast(linear[2] * desc.emissive_factor[2] * desc.emissive_strength);
                }
            }
        }

        if (transmission_tex) |img| {
            for (0..transmission_width) |x| {
                for (0..transmission_height) |y| {
                    const sample_index = @mod(y, transmission_height) * transmission_width + @mod(x, transmission_width);
                    // TODO: To gamma or not to gamma
                    const opacity = img.pixels.grayscale16[sample_index].toColorf32().r;
                    // const opacity = img.pixels.grayscale16[sample_index];
                    // const linear = zigimg.color.sRGB.toLinear(zigimg.color.Colorf32.from.grayscale(opacity)).to.float4();

                    const out_index = y * transmission_width + x;
                    // We flip the opacity because that what "The Junk Shop" does.
                    // TODO: Check with other scene
                    _buffer[out_index].transmission = @floatCast(1.0 - opacity);
                }
            }
        }
        if (occlusion and occlusion_seperate) {
            if (occlusion_tex) |img| {
                for (0..occlusion_width) |x| {
                    for (0..occlusion_height) |y| {
                        const sample_index = @mod(y, occlusion_height) * occlusion_width + @mod(x, occlusion_width);
                        const occlusion_value = img.pixels.grayscale16[sample_index].toColorf32().r;

                        const out_index = y * occlusion_width + x;
                        _buffer[out_index].ao = @floatCast(occlusion_value * desc.occlusion_strength);
                    }
                }
            }
        }

        if (albedo_file) |file| {
            file.close();
            albedo_tex.?.deinit(allocator);
        }
        if (normal_file) |file| {
            file.close();
            normal_tex.?.deinit(allocator);
        }
        if (rm_file) |file| {
            file.close();
            rm_tex.?.deinit(allocator);
        }
        if (occlusion and occlusion_seperate) {
            if (occlusion_file) |file| {
                file.close();
                occlusion_tex.?.deinit(allocator);
            }
        }
        if (emissive_file) |file| {
            file.close();
            emissive_tex.?.deinit(allocator);
        }
        if (transmission_file) |file| {
            file.close();
            transmission_tex.?.deinit(allocator);
        }

        return PBRTexture{
            .width = alloc_width,
            .height = alloc_height,
            .buffer = _buffer,
            .normal = normals,
            .alpha_cutoff = desc.alpha_cutoff,
        };
    }

    // pub fn loadAlbedoTextureFromDescriptor(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
    //     var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

    //     var albedo_file: std.fs.File = undefined;

    //     defer albedo_file.close();

    //     std.debug.print("Albedo file path: {s}\n", .{tex_desc.albedo_tex_path.?});
    //     std.debug.print("----\n", .{});

    //     // Assume all file paths are either absolute or relative
    //     if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
    //         albedo_file = try std.fs.openFileAbsolute(tex_desc.albedo_tex_path.?, .{});
    //     } else {
    //         albedo_file = try std.fs.cwd().openFile(tex_desc.albedo_tex_path.?, .{});
    //     }

    //     var albedo_tex = try zigimg.Image.fromFile(allocator, albedo_file, albedo_read_buffer[0..]);
    //     try albedo_tex.convert(allocator, zigimg.PixelFormat.rgb24);

    //     var _buffer: []PBR = undefined;

    //     if (allocator.alloc(PBR, albedo_tex.width * albedo_tex.height)) |_buf| {
    //         _buffer = _buf;
    //     } else |err| {
    //         std.debug.panic("error: {any}", .{err});
    //     }

    //     var index: usize = 0;
    //     for (albedo_tex.pixels.rgb24) |a| {
    //         var albedo_value = a.to.float4();
    //         albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
    //         albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
    //         albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
    //         const normal = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    //         _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
    //         _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
    //         _buffer[index].metallic = 0.0;
    //         _buffer[index].roughness = 0.0;
    //         _buffer[index].ao = 0.1;
    //         _buffer[index].emissive = RGB{ .x = 0.0, .y = 0.0, .z = 0.0 };
    //         index += 1;
    //     }

    //     return TexturePBR{
    //         .width = albedo_tex.width,
    //         .height = albedo_tex.height,
    //         .buffer = _buffer,
    //     };
    // }

    // pub fn loadRMTextureFromDescriptor(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
    //     var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    //     var normal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    //     var rm_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

    //     var albedo_file: std.fs.File = undefined;
    //     var normal_file: std.fs.File = undefined;
    //     var rm_file: std.fs.File = undefined;

    //     defer albedo_file.close();
    //     defer normal_file.close();
    //     defer rm_file.close();

    //     std.debug.print("Albedo file path: {s}\n", .{tex_desc.albedo_tex_path.?});
    //     std.debug.print("Normal file path: {s}\n", .{tex_desc.normal_tex_path.?});
    //     std.debug.print("Metallic file path: {s}\n", .{tex_desc.metallic_tex_path.?});
    //     std.debug.print("Roughness file path: {s}\n", .{tex_desc.roughness_tex_path.?});

    //     // Assume all file paths are either absolute or relative
    //     if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
    //         albedo_file = try std.fs.openFileAbsolute(tex_desc.albedo_tex_path.?, .{});
    //         normal_file = try std.fs.openFileAbsolute(tex_desc.normal_tex_path.?, .{});
    //         rm_file = try std.fs.openFileAbsolute(tex_desc.roughness_tex_path.?, .{});
    //         // emissive_file = try std.fs.openFileAbsolute(tex_desc.emissive_tex_path.?, .{});
    //     } else {
    //         albedo_file = try std.fs.cwd().openFile(tex_desc.albedo_tex_path.?, .{});
    //         normal_file = try std.fs.cwd().openFile(tex_desc.normal_tex_path.?, .{});
    //         rm_file = try std.fs.cwd().openFile(tex_desc.roughness_tex_path.?, .{});
    //     }

    //     var albedo_tex = try zigimg.Image.fromFile(allocator, albedo_file, albedo_read_buffer[0..]);
    //     var normal_tex = try zigimg.Image.fromFile(allocator, normal_file, normal_read_buffer[0..]);
    //     var rm_tex = try zigimg.Image.fromFile(allocator, rm_file, rm_read_buffer[0..]);

    //     try albedo_tex.convert(allocator, zigimg.PixelFormat.rgb24);
    //     try normal_tex.convert(allocator, zigimg.PixelFormat.rgb24);
    //     try rm_tex.convert(allocator, zigimg.PixelFormat.rgb24);

    //     // std.debug.assert(albedo_tex.width == rm_tex.width and rm_tex.width == normal_tex.width);
    //     // std.debug.assert(albedo_tex.height == rm_tex.height and rm_tex.height == normal_tex.height);
    //     const max_width = @max(albedo_tex.width, normal_tex.width, rm_tex.width);
    //     const max_height = @max(albedo_tex.height, normal_tex.height, rm_tex.height);

    //     var _buffer: []PBR = undefined;

    //     if (allocator.alloc(PBR, max_width * max_height)) |_buf| {
    //         _buffer = _buf;
    //     } else |err| {
    //         std.debug.panic("error: {any}", .{err});
    //     }

    //     // var index: usize = 0;

    //     for (albedo_tex.pixels.rgb24, 0..) |a, index| {
    //         var albedo_value = a.to.float4();
    //         albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
    //         albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
    //         albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);

    //         // const roughness_value = rm.to.float4()[1];
    //         // const metal_value = rm.to.float4()[2];

    //         // const normal_value = n.to.float4();
    //         // var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
    //         // normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
    //         // normal = normal.multf(tex_desc.normal_scale);

    //         _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
    //         _buffer[index].normal = RGB{ .x = 0.0, .y = 0.0, .z = 0.0 };
    //         _buffer[index].metallic = 0.0;
    //         _buffer[index].roughness = 1.0;
    //         _buffer[index].ao = 0.1;
    //         _buffer[index].emissive = RGB{ .x = 0.0, .y = 0.0, .z = 0.0 };
    //         // index += 1;
    //     }

    //     // index = 0;
    //     for (normal_tex.pixels.rgb24, 0..) |n, index| {
    //         // var albedo_value = a.to.float4();
    //         // albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
    //         // albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
    //         // albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);

    //         // const roughness_value = rm.to.float4()[1];
    //         // const metal_value = rm.to.float4()[2];

    //         const normal_value = n.to.float4();
    //         var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
    //         normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
    //         normal = normal.multf(tex_desc.normal_scale);

    //         // _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
    //         _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
    //         // _buffer[index].metallic = 0.0;
    //         // _buffer[index].roughness = 1.0;
    //         // _buffer[index].ao = 0.1;
    //         // _buffer[index].emissive = RGB{ .x = 0.0, .y = 0.0, .z = 0.0 };
    //         // index += 1;
    //     }

    //     // index = 0;
    //     for (rm_tex.pixels.rgb24, 0..) |rm, index| {
    //         // var albedo_value = a.to.float4();
    //         // albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
    //         // albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
    //         // albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);

    //         const roughness_value = rm.to.float4()[1];
    //         const metal_value = rm.to.float4()[2];

    //         // const normal_value = n.to.float4();
    //         // var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
    //         // normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
    //         // normal = normal.multf(tex_desc.normal_scale);

    //         // _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
    //         // _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
    //         _buffer[index].metallic = @floatCast(metal_value);
    //         _buffer[index].roughness = @floatCast(roughness_value);
    //         // _buffer[index].ao = 0.1;
    //         // _buffer[index].emissive = RGB{ .x = 0.0, .y = 0.0, .z = 0.0 };
    //         // index += 1;
    //     }

    //     if (tex_desc.emissive_tex_path) |emissive_tex_path| {
    //         std.debug.print("Emissive file path: {s}\n", .{emissive_tex_path});
    //         var emissive_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

    //         var emissive_file: std.fs.File = undefined;
    //         defer emissive_file.close();

    //         if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
    //             emissive_file = try std.fs.openFileAbsolute(emissive_tex_path, .{});
    //         } else {
    //             emissive_file = try std.fs.cwd().openFile(emissive_tex_path, .{});
    //         }

    //         var emissive_tex = try zigimg.Image.fromFile(allocator, emissive_file, emissive_read_buffer[0..]);

    //         std.debug.assert(albedo_tex.height == emissive_tex.height);

    //         try emissive_tex.convert(allocator, zigimg.PixelFormat.rgb24);

    //         // index = 0;
    //         for (emissive_tex.pixels.rgb24, 0..) |e, index| {
    //             const color = e.to.float4();
    //             // Do we gamme correct?
    //             _buffer[index].emissive.x = @floatCast(std.math.pow(f32, color[0], 2.22) * tex_desc.emissive_strength);
    //             _buffer[index].emissive.y = @floatCast(std.math.pow(f32, color[1], 2.22) * tex_desc.emissive_strength);
    //             _buffer[index].emissive.z = @floatCast(std.math.pow(f32, color[2], 2.22) * tex_desc.emissive_strength);
    //             // index += 1;
    //         }
    //     }

    //     std.debug.print("----\n", .{});
    //     return TexturePBR{
    //         .width = albedo_tex.width,
    //         .height = albedo_tex.height,
    //         .buffer = _buffer,
    //     };
    // }

    // //TODO: This is unused even when material supports AO map
    // pub fn loadARMTextureFromDescriptor(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
    //     var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    //     var normal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    //     var arm_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

    //     var albedo_file: std.fs.File = undefined;
    //     var normal_file: std.fs.File = undefined;
    //     var arm_file: std.fs.File = undefined;

    //     defer albedo_file.close();
    //     defer normal_file.close();
    //     defer arm_file.close();

    //     std.debug.print("Albedo file path: {s}\n", .{tex_desc.albedo_tex_path.?});
    //     std.debug.print("Normal file path: {s}\n", .{tex_desc.normal_tex_path.?});
    //     std.debug.print("AO/Roughness/Metallic file path: {s}\n", .{tex_desc.roughness_tex_path.?});
    //     std.debug.print("----\n", .{});

    //     // Assume all file paths are either absolute or relative
    //     if (std.fs.path.isAbsolute(tex_desc.albedo_tex_path.?)) {
    //         albedo_file = try std.fs.openFileAbsolute(tex_desc.albedo_tex_path.?, .{});
    //         normal_file = try std.fs.openFileAbsolute(tex_desc.normal_tex_path.?, .{});
    //         arm_file = try std.fs.openFileAbsolute(tex_desc.roughness_tex_path.?, .{});
    //     } else {
    //         albedo_file = try std.fs.cwd().openFile(tex_desc.albedo_tex_path.?, .{});
    //         normal_file = try std.fs.cwd().openFile(tex_desc.normal_tex_path.?, .{});
    //         arm_file = try std.fs.cwd().openFile(tex_desc.roughness_tex_path.?, .{});
    //     }

    //     const albedo_tex = try zigimg.Image.fromFile(allocator, albedo_file, albedo_read_buffer[0..]);
    //     const normal_tex = try zigimg.Image.fromFile(allocator, normal_file, normal_read_buffer[0..]);
    //     const arm_tex = try zigimg.Image.fromFile(allocator, arm_file, arm_read_buffer[0..]);

    //     std.debug.assert(albedo_tex.width == arm_tex.width and arm_tex.width == normal_tex.width);
    //     std.debug.assert(albedo_tex.height == arm_tex.height and arm_tex.height == normal_tex.height);

    //     const tex_format = albedo_tex.pixelFormat();
    //     const bits_per_channel = tex_format.bitsPerChannel();
    //     const channel_count = tex_format.channelCount();

    //     var _buffer: []PBR = undefined;

    //     if (allocator.alloc(PBR, albedo_tex.width * albedo_tex.height)) |_buf| {
    //         _buffer = _buf;
    //     } else |err| {
    //         std.debug.panic("error: {any}", .{err});
    //     }

    //     var index: usize = 0;
    //     if (channel_count == 3) {
    //         if (bits_per_channel == 8) {
    //             for (albedo_tex.pixels.rgb24, normal_tex.pixels.rgb24, arm_tex.pixels.rgba32) |a, n, arm| {
    //                 var albedo_value = a.to.float4();
    //                 albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
    //                 albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
    //                 albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);

    //                 const normal_value = n.to.float4();
    //                 const ao_value = arm.to.float4()[0];
    //                 const roughness_value = arm.to.float4()[1];
    //                 const metal_value = arm.to.float4()[2];

    //                 var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
    //                 normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
    //                 normal = normal.multf(tex_desc.normal_scale);
    //                 normal = Vec3.normalize(normal);

    //                 _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
    //                 _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
    //                 _buffer[index].metallic = @floatCast(metal_value);
    //                 _buffer[index].roughness = @floatCast(roughness_value);
    //                 _buffer[index].ao = @floatCast(ao_value);
    //                 index += 1;
    //             }
    //         } else {
    //             for (albedo_tex.pixels.rgb48, normal_tex.pixels.rgb48, arm_tex.pixels.rgb48) |a, n, arm| {
    //                 var albedo_value = a.to.float4();
    //                 albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
    //                 albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
    //                 albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);

    //                 const normal_value = n.to.float4();
    //                 const ao_value = arm.to.float4()[0];
    //                 const roughness_value = arm.to.float4()[1];
    //                 const metal_value = arm.to.float4()[2];

    //                 var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
    //                 normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
    //                 normal = normal.multf(tex_desc.normal_scale);
    //                 // normal = Vec3.normalize(normal);

    //                 _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
    //                 _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
    //                 _buffer[index].metallic = @floatCast(metal_value);
    //                 _buffer[index].roughness = @floatCast(roughness_value);
    //                 _buffer[index].ao = @floatCast(ao_value);
    //                 index += 1;
    //             }
    //         }
    //     } else if (channel_count == 4) {
    //         if (bits_per_channel == 8) {
    //             for (albedo_tex.pixels.rgba32, normal_tex.pixels.rgba32, arm_tex.pixels.rgba32) |a, n, arm| {
    //                 var albedo_value = a.to.float4();
    //                 albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
    //                 albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
    //                 albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);

    //                 const normal_value = n.to.float4();
    //                 const ao_value = arm.to.float4()[0];
    //                 const roughness_value = arm.to.float4()[1];
    //                 const metal_value = arm.to.float4()[2];

    //                 var normal = Vec3{ .x = normal_value[0], .y = normal_value[1], .z = normal_value[2] };
    //                 normal = Vec3.sub(normal.multf(2.0), Vec3.init(1.0));
    //                 normal = normal.multf(tex_desc.normal_scale);
    //                 // normal = Vec3.normalize(normal);

    //                 _buffer[index].albedo = RGB{ .x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2]) };
    //                 _buffer[index].normal = RGB{ .x = @floatCast(normal.x), .y = @floatCast(normal.y), .z = @floatCast(normal.z) };
    //                 _buffer[index].metallic = @floatCast(metal_value);
    //                 _buffer[index].roughness = @floatCast(roughness_value);
    //                 _buffer[index].ao = @floatCast(ao_value);
    //                 index += 1;
    //             }
    //         }
    //     } else {
    //         std.debug.panic("Format Not Found. Channels: {}, Bits per channel: {}\n", .{ channel_count, bits_per_channel });
    //     }

    //     return TexturePBR{
    //         .width = albedo_tex.width,
    //         .height = albedo_tex.height,
    //         .buffer = _buffer,
    //     };
    // }

    pub fn deinit(texture: PBRTexture, allocator: std.mem.Allocator) void {
        allocator.free(texture.buffer);
    }
};
