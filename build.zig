const std = @import("std");
const sokol = @import("sokol");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimization = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimization,
    });
    const sokol_module = sokol_dep.module("sokol");

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimization,
    });
    const zigimg_module = zigimg_dep.module("zigimg");

    const zgltf = b.dependency("zgltf", .{});
    const zgltf_module = zgltf.module("zgltf");

    const exe = b.addExecutable(.{
        .name = "ZigCPURasterizer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "sokol", .module = sokol_module },
                .{ .name = "zigimg", .module = zigimg_module },
                .{ .name = "shader", .module = try createShaderModule(b, sokol_dep, sokol_module) },
                .{ .name = "zgltf", .module = zgltf_module },
            },
            .target = target,
            .optimize = optimization,
        }),
    });

    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "Run pacman").dependOn(&run.step);
}

fn createShaderModule(b: *std.Build, dep_sokol: *std.Build.Dependency, mod_sokol: *std.Build.Module) !*std.Build.Module {
    const dep_shdc = dep_sokol.builder.dependency("shdc", .{});
    return sokol.shdc.createModule(b, "shader", mod_sokol, .{
        .shdc_dep = dep_shdc,
        .input = "src/shaders/shader.glsl",
        .output = "src/shaders/shader.glsl.zig",
        .slang = .{
            .glsl410 = false,
            .glsl300es = false,
            .hlsl4 = false,
            .metal_macos = true,
            .wgsl = false,
        },
    });
}
