const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const wgpu_dep = b.dependency("wgpu_native_zig", .{
        .target = target,
        .optimize = optimize,
        .link_mode = .dynamic,
    });
    const zmath_dep = b.dependency("zmath", .{});

    const engine_mod = b.addModule("Engine", .{
        .root_source_file = b.path("engine/Engine.zig"),
        .optimize = optimize,
        .target = target,
    });

    engine_mod.addImport("gpu", wgpu_dep.module("wgpu"));

    const engine_exe = b.addExecutable(.{
        .root_source_file = b.path("engine/main.zig"),
        .optimize = optimize,
        .target = target,
        .name = "engine",
    });

    engine_exe.linkSystemLibrary("wgpu_native");
    engine_exe.linkSystemLibrary("glfw");
    engine_exe.linkLibC();

    const game_lib = b.addSharedLibrary(.{
        .root_source_file = b.path("game/root.zig"),
        .optimize = optimize,
        .target = target,
        .name = "game",
        .pic = true,
    });

    game_lib.root_module.addImport("gpu", wgpu_dep.module("wgpu"));
    game_lib.root_module.addImport("math", zmath_dep.module("root"));
    game_lib.root_module.addImport("Engine", engine_mod);
    game_lib.linkSystemLibrary("wgpu_native");

    const game_install = b.addInstallArtifact(game_lib, .{});

    const engine_install = b.addInstallArtifact(engine_exe, .{});
    engine_install.step.dependOn(&game_install.step);

    const game_step = b.step("game", "compile the game library");
    game_step.dependOn(&game_install.step);

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
