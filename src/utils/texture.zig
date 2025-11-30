const std = @import("std");
const Vec3 = @import("../math/vec3.zig").Vec3;
const zigimg = @import("zigimg");

pub const RGB = struct {
	x: f16, y: f16, z: f16
};

pub const PBR = struct{
	albedo: RGB,
	normal: RGB,
	metallic: f16,
	roughness: f16,
};

pub const PBRTextureDescriptor = struct{
	albedo_tex_path: []const u8,
	normal_tex_path: []const u8,
	metallic_tex_path: []const u8,
	roughness_tex_path: []const u8,
};
pub const TexturePBR = struct {
	width: usize,
	height: usize,
	buffer: []PBR,

	pub fn loadTextureFromFile(tex_desc: PBRTextureDescriptor, allocator: std.mem.Allocator) !TexturePBR {
		var albedo_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
		var normal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
		var metal_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
		var roughness_read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;

       	const albedo_tex = try zigimg.Image.fromFilePath(allocator, tex_desc.albedo_tex_path, albedo_read_buffer[0..]);
       	const metal_tex = try zigimg.Image.fromFilePath(allocator, tex_desc.metallic_tex_path, metal_read_buffer[0..]);
       	const roughness_tex = try zigimg.Image.fromFilePath(allocator, tex_desc.roughness_tex_path, roughness_read_buffer[0..]);
       	const normal_tex = try zigimg.Image.fromFilePath(allocator, tex_desc.normal_tex_path, normal_read_buffer[0..]);

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
        if(channel_count == 3){
        	if (bits_per_channel == 8) {
            	for (albedo_tex.pixels.rgb24, normal_tex.pixels.rgb24, metal_tex.pixels.grayscale8, roughness_tex.pixels.grayscale8) | a, n, m, r | {
           			var albedo_value = a.to.float4();
            		albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
              		albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
              		albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
              		const normal_value = n.to.float4();
                	const metal_value = m.toColorf32().r;
                 	const roughness_value = r.toColorf32().r;
            		_buffer[index].albedo = RGB{.x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2])};
            		_buffer[index].normal = RGB{.x = @floatCast(normal_value[0]), .y = @floatCast(normal_value[1]), .z = @floatCast(normal_value[2])};
            		_buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
              		_buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
              		_buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
               		_buffer[index].metallic = @floatCast(metal_value);
                	_buffer[index].roughness = @floatCast(roughness_value);
            		index += 1;
            	}
         	}else{
          		for (albedo_tex.pixels.rgb48, normal_tex.pixels.rgb48, metal_tex.pixels.grayscale16, roughness_tex.pixels.grayscale16) | a, n, m, r | {
            		var albedo_value = a.to.float4();
            		albedo_value[0] = std.math.pow(f32, albedo_value[0], 2.2);
              		albedo_value[1] = std.math.pow(f32, albedo_value[1], 2.2);
              		albedo_value[2] = std.math.pow(f32, albedo_value[2], 2.2);
           			const normal_value = n.to.float4();
            		const metal_value = m.toColorf32().r;
              		const roughness_value = r.toColorf32().r;
          			_buffer[index].albedo = RGB{.x = @floatCast(albedo_value[0]), .y = @floatCast(albedo_value[1]), .z = @floatCast(albedo_value[2])};
          			_buffer[index].normal = RGB{.x = @floatCast(normal_value[0]), .y = @floatCast(normal_value[1]), .z = @floatCast(normal_value[2])};
             		_buffer[index].normal.x = _buffer[index].normal.x * 2.0 - 1.0;
             		_buffer[index].normal.y = _buffer[index].normal.y * 2.0 - 1.0;
             		_buffer[index].normal.z = _buffer[index].normal.z * 2.0 - 1.0;
             		_buffer[index].metallic = @floatCast(metal_value);
             		_buffer[index].roughness = @floatCast(roughness_value);
          			index += 1;
         		}
          	}
		}else {
			std.debug.panic("Format Not Found. Channels: {}, Bits per channel: {}\n", .{channel_count, bits_per_channel});
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
