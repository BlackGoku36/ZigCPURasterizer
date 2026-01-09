const std = @import("std");
const PBRTexture = @import("utils/texture.zig").PBRTexture;
const RGB = @import("utils/texture.zig").RGB;
const PBRSolid = @import("utils/texture.zig").PBRSolid;
const PBRTextureDescriptor = @import("utils/texture.zig").PBRTextureDescriptor;
const PBRPackedTextureDescriptor = @import("utils/texture.zig").PBRPackedTextureDescriptor;
const Vec3 = @import("math/vec3.zig").Vec3;
const Vec2 = @import("math/vec2.zig").Vec2;

pub const MaterialType = enum { Textured, Solid };

pub const Material = struct {
    pbr_texture: ?PBRTexture,
    pbr_solid: ?PBRSolid,
    type: MaterialType,
    tex_coord: u8 = 0,
    name: ?[]const u8,

    pub fn fromGltfTextureFiles(
        material_name: ?[]const u8,
        diffuse_path: ?[]const u8,
        metalness_roughness_path: ?[]const u8,
        occlusion_path: ?[]const u8,
        normal_path: ?[]const u8,
        emissive_path: ?[]const u8,
        transmission_path: ?[]const u8,
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
        allocator: std.mem.Allocator,
    ) Material {
        var mat: PBRTexture = undefined;
        if (PBRTexture.loadTextureFromDescriptor(PBRTextureDescriptor{
            .albedo_tex_path = diffuse_path,
            .normal_tex_path = normal_path,
            .rm_tex_path = metalness_roughness_path,
            .occlusion_tex_path = occlusion_path,
            .emissive_tex_path = emissive_path,
            .transmission_tex_path = transmission_path,
            .emissive_strength = emissive_strength,
            .color_factor = color_factor,
            .normal_scale = normal_scale,
            .metallic_factor = metallic_factor,
            .roughness_factor = roughness_factor,
            .occlusion_strength = occlusion_strength,
            .emissive_factor = emissive_factor,
            .alpha_cutoff = alpha_cutoff,
            .transmission_factor = transmission_factor,
            .ior = ior,
        }, allocator)) |pbr| {
            mat = pbr;
        } else |err| {
            std.debug.panic("Error while creating Material: {}\n", .{err});
        }

        return Material{
            .pbr_texture = mat,
            .pbr_solid = null,
            .name = material_name,
            .type = .Textured,
            .tex_coord = 0,
        };
    }

    pub fn fromGltfConstants(
        name: []const u8,
        rgb: [3]f32,
        metallic: f32,
        roughness: f32,
        ao: f32,
        emissive_rgb: [3]f32,
        transmission: f32,
        ior: f32,
    ) Material {
        return Material{
            .pbr_solid = PBRSolid{
                .albedo = RGB{ .x = @floatCast(rgb[0]), .y = @floatCast(rgb[1]), .z = @floatCast(rgb[2]) },
                .metallic = @floatCast(metallic),
                .roughness = @floatCast(roughness),
                .ao = @floatCast(ao),
                .emissive = RGB{ .x = @floatCast(emissive_rgb[0]), .y = @floatCast(emissive_rgb[1]), .z = @floatCast(emissive_rgb[2]) },
                .transmission = @floatCast(transmission),
                .ior = @floatCast(ior),
            },
            .pbr_texture = null,
            .name = name,
            .type = .Solid,
            .tex_coord = 0,
        };
    }

    pub fn deinit(material: Material, allocator: std.mem.Allocator) void {
        switch (material.type) {
            .Textured => material.pbr_texture.?.deinit(allocator),
            .Solid => {},
        }
    }
};
