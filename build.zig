const std = @import("std");
const sokol = @import("libs/sokol-zig/build.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const compile_shader = b.addSystemCommand(&[_][]const u8{ "sokol-shdc", "-i", "src/shaders/shader.glsl", "-o", "src/shaders/shader.glsl.zig", "-l", "glsl330:metal_macos:hlsl4", "-f", "sokol_zig" });

    const sokol_build = sokol.buildSokol(b, target, mode, sokol.Backend.auto, "libs/sokol-zig/");

    const exe = b.addExecutable("cg_from_scratch_zig", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("zigimg", "libs/zigimg/zigimg.zig");
    exe.addPackagePath("sokol", "libs/sokol-zig/src/sokol/sokol.zig");
    exe.linkLibrary(sokol_build);
    exe.install();

    exe.step.dependOn(&compile_shader.step);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
