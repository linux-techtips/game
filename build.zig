const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const wgpu_dep = b.dependency("wgpu_native_zig", .{
        .target = target,
        .link_mode = .dynamic,
    });

    const platform_lib = b.addSharedLibrary(.{
        .root_source_file = b.path("src/platform.zig"),
        .optimize = optimize,
        .target = target,
        .name = "platform",
    });

    platform_lib.linkSystemLibrary("glfw");
    platform_lib.linkSystemLibrary("wgpu_native");
    platform_lib.linkLibC();

    platform_lib.root_module.addImport("wgpu", wgpu_dep.module("wgpu"));

    const platform_install = b.addInstallArtifact(platform_lib, .{});

    const game_lib = b.addSharedLibrary(.{
        .root_source_file = b.path("src/game.zig"),
        .optimize = optimize,
        .target = target,
        .name = "game",
    });

    game_lib.linkSystemLibrary("wgpu_native");
    game_lib.root_module.addImport("wgpu", wgpu_dep.module("wgpu"));

    const game_install = b.addInstallArtifact(game_lib, .{});

    const engine_exe = b.addExecutable(.{
        .root_source_file = b.path("src/engine.zig"),
        .optimize = optimize,
        .target = target,
        .name = "engine",
    });

    const engine_install = b.addInstallArtifact(engine_exe, .{});
    engine_install.step.dependOn(&platform_install.step);
    engine_install.step.dependOn(&game_install.step);

    engine_exe.linkLibrary(platform_lib);

    const game_step = b.step("game", "compile the game library");
    game_step.dependOn(&game_install.step);

    const platform_step = b.step("platform", "compile the engine platform");
    platform_step.dependOn(&platform_install.step);

    const engine_step = b.step("engine", "compile the engine");
    engine_step.dependOn(&engine_install.step);

    b.getInstallStep().dependOn(&engine_install.step);

    const run_cmd = b.addRunArtifact(engine_exe);
    run_cmd.step.dependOn(&engine_install.step);
    run_cmd.step.dependOn(&game_install.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
