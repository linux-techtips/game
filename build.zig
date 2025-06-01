const std = @import("std");

pub fn validate_shaders(b: *std.Build, path: std.Build.LazyPath, step: *std.Build.Step) !void {
    const run = b.addSystemCommand(&.{ "naga", "--bulk-validate" });

    _ = run.captureStdOut();
    step.dependOn(&run.step);

    const dir_path = path.src_path.sub_path;
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.NotDir => {
            run.addFileArg(path);
            return;
        },
        else => return err,
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| if (entry.kind == .file) {
        const entry_path = try std.fs.path.join(b.allocator, &.{ dir_path, entry.name });
        run.addFileArg(b.path(entry_path));
    };
}

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const wgpu_dep = b.dependency("wgpu_native_zig", .{
        .target = target,
        .optimize = optimize,
        .link_mode = .dynamic,
    });
    const zmath_dep = b.dependency("zmath", .{});
    const zpool_dep = b.dependency("zpool", .{});

    const engine_mod = b.addModule("Engine", .{
        .root_source_file = b.path("engine/Engine.zig"),
        .optimize = optimize,
        .target = target,
    });

    engine_mod.addImport("zpool", zpool_dep.module("root"));
    engine_mod.addImport("gpu", wgpu_dep.module("wgpu"));

    const platform_mod = b.addModule("platform", .{
        .root_source_file = b.path("platform/linux-glfw.zig"),
        .optimize = optimize,
        .target = target,
        .pic = true,
    });

    platform_mod.addImport("gpu", wgpu_dep.module("wgpu"));
    platform_mod.addImport("Engine", engine_mod);

    const platform_lib = b.addSharedLibrary(.{
        .root_module = platform_mod,
        .name = "platform",
    });

    platform_lib.linkSystemLibrary("wgpu_native");
    platform_lib.linkSystemLibrary("glfw");
    platform_lib.linkLibC();

    const engine_exe = b.addExecutable(.{
        .root_source_file = b.path("engine/main.zig"),
        .optimize = optimize,
        .target = target,
        .name = "engine",
    });

    engine_exe.linkLibrary(platform_lib);

    const game_lib = b.addSharedLibrary(.{
        .root_source_file = b.path("game/root.zig"),
        .optimize = optimize,
        .target = target,
        .name = "game",
        .pic = true,
    });

    const shader_dir = b.option([]const u8, "shader_dir", "directory of shaders to validate.") orelse "game/shaders";
    if (b.option(bool, "validate", "validate shaders") orelse true) {
        try validate_shaders(b, b.path(shader_dir), &game_lib.step);
    }

    game_lib.root_module.addImport("zlm", zmath_dep.module("root"));
    game_lib.root_module.addImport("gpu", wgpu_dep.module("wgpu"));
    game_lib.root_module.addImport("Engine", engine_mod);

    game_lib.linkSystemLibrary("wgpu_native");

    const platform_install = b.addInstallArtifact(platform_lib, .{});

    const game_install = b.addInstallArtifact(game_lib, .{});

    const engine_install = b.addInstallArtifact(engine_exe, .{});
    engine_install.step.dependOn(&platform_install.step);
    engine_install.step.dependOn(&game_install.step);

    const platform_step = b.step("platform", "compile the engine platform");
    platform_step.dependOn(&platform_install.step);

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
