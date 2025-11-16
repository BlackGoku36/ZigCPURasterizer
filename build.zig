const std = @import("std");
// const sokol = @import("libs/sokol-zig/build.zig");
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

	const exe = b.addExecutable(.{
		.name = "ZigCPURasterizer",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.imports = &.{
				.{.name = "sokol", .module = sokol_module},
				.{.name = "zigimg", .module = zigimg_module},
				.{.name = "shader", .module = try createShaderModule(b, sokol_dep, sokol_module) },
			},
			.target = target,
			.optimize = optimization,
		}),
	});

	// exe.addImport()

	b.installArtifact(exe);
	const run = b.addRunArtifact(exe);
    b.step("run", "Run pacman").dependOn(&run.step);
}

fn createShaderModule(b: *std.Build, dep_sokol: *std.Build.Dependency, mod_sokol: *std.Build.Module) !*std.Build.Module {
    // const mod_sokol = dep_sokol.module("sokol");
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

// pub fn build(b: *std.build.Builder) void {
//     // Standard target options allows the person running `zig build` to choose
//     // what target to build for. Here we do not override the defaults, which
//     // means any target is allowed, and the default is native. Other options
//     // for restricting supported target set are available.
//     const target = b.standardTargetOptions(.{});

//     // Standard release options allow the person running `zig build` to select
//     // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
//     const mode = b.standardReleaseOptions();

//     const compile_shader = b.addSystemCommand(&[_][]const u8{ "sokol-shdc", "-i", "src/shaders/shader.glsl", "-o", "src/shaders/shader.glsl.zig", "-l", "glsl330:metal_macos:hlsl4", "-f", "sokol_zig" });

//     const sokol_build = sokol.buildSokol(b, target, mode, sokol.Backend.auto, "libs/sokol-zig/");

//     const exe = b.addExecutable("cg_from_scratch_zig", "src/main.zig");
//     exe.setTarget(target);
//     exe.setBuildMode(mode);
//     exe.addPackagePath("zigimg", "libs/zigimg/zigimg.zig");
//     exe.addPackagePath("sokol", "libs/sokol-zig/src/sokol/sokol.zig");
//     exe.linkLibrary(sokol_build);
//     exe.install();

//     exe.step.dependOn(&compile_shader.step);

//     const run_cmd = exe.run();
//     run_cmd.step.dependOn(b.getInstallStep());
//     if (b.args) |args| {
//         run_cmd.addArgs(args);
//     }

//     const run_step = b.step("run", "Run the app");
//     run_step.dependOn(&run_cmd.step);

//     const exe_tests = b.addTest("src/main.zig");
//     exe_tests.setTarget(target);
//     exe_tests.setBuildMode(mode);

//     const test_step = b.step("test", "Run unit tests");
//     test_step.dependOn(&exe_tests.step);
// }
