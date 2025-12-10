const std = @import("std");
const TexturePBR = @import("utils/texture.zig").TexturePBR;
const RGB = @import("utils/texture.zig").RGB;
const PBRSolid = @import("utils/texture.zig").PBRSolid;
const PBRTextureDescriptor = @import("utils/texture.zig").PBRTextureDescriptor;
const PBRPackedTextureDescriptor = @import("utils/texture.zig").PBRPackedTextureDescriptor;
const Vec3 = @import("math/vec3.zig").Vec3;
const Vec2 = @import("math/vec2.zig").Vec2;

pub const MaterialType = enum { Textured, Solid };

// TODO: Decide whether to use PBR as suffix or prefix
pub const Material = struct {
    pbr_texture: ?TexturePBR,
    pbr_solid: ?PBRSolid,
    type: MaterialType,
    tex_coord: u8,
    name: []const u8,

    pub fn fromGltfTextureFiles(
        diffuse_path: ?[]const u8,
        metalness_roughness_path: ?[]const u8,
        normal_path: ?[]const u8,
        emissive_path: ?[]const u8,
        emissive_strength: f32,
        normal_scale: f32,
        allocator: std.mem.Allocator,
    ) Material {
        var mat: TexturePBR = undefined;
        if (TexturePBR.loadTextureFromDescriptor(PBRTextureDescriptor{
            .albedo_tex_path = diffuse_path,
            .normal_tex_path = normal_path,
            .roughness_tex_path = metalness_roughness_path,
            .metallic_tex_path = metalness_roughness_path,
            // .occlusion_tex_path = occlusion_path,
            .occlusion_tex_path = null,
            .emissive_tex_path = emissive_path,
            .emissive_strength = emissive_strength,
            .normal_scale = normal_scale,
        }, allocator)) |pbr| {
            mat = pbr;
        } else |err| {
            std.debug.print("Error while creating Material: {}\n", .{err});
        }

        return Material{
            .pbr_texture = mat,
            .pbr_solid = null,
            .name = diffuse_path.?,
            .type = .Textured,
            .tex_coord = 0,
        };
    }

    pub fn fromGltfConstants(name: []const u8, rgb: [3]f32, metallic: f32, roughness: f32, ao: f32) Material {
        return Material{
            .pbr_solid = PBRSolid{
                .albedo = RGB{ .x = @floatCast(rgb[0]), .y = @floatCast(rgb[1]), .z = @floatCast(rgb[2]) },
                .metallic = @floatCast(metallic),
                .roughness = @floatCast(roughness),
                .ao = @floatCast(ao),
            },
            .pbr_texture = null,
            .name = name,
            .type = .Solid,
            .tex_coord = 0,
        };
    }
};
