const std = @import("std");

pub const Plugin = struct {
    path: [:0]const u8,
    lib: std.DynLib,

    pub const VTable = struct {
        pub const Startup = *const fn (*Engine, ?*anyopaque) callconv(.C) ?*anyopaque;
        pub const Shutdown = *const fn (*Engine, *anyopaque) callconv(.C) void;
        pub const Update = *const fn (*Engine, *anyopaque) callconv(.C) bool;

        startup: Startup,
        shutdown: Shutdown,
        update: Update,

        pub fn lookup(lib: *std.DynLib, path: [:0]const u8) Error!VTable {
            var vtable: VTable = undefined;
            inline for (std.meta.fields(VTable)) |field| {
                const name = "Plug_" ++ [1]u8{std.ascii.toUpper(field.name[0])} ++ field.name[1..];
                const func = lib.lookup(field.type, name) orelse {
                    Engine.log.err("failed to load symbol - '{x}' for plugin - '{s}'", .{ name, std.fs.path.basename(path) });
                    return Error.missing_plugin_symbol;
                };

                Engine.log.debug("loaded symbol - '{s}' at address '0x{X}' for plugin - '{s}'", .{ name, @intFromPtr(func), std.fs.path.basename(path) });

                @field(vtable, field.name) = func;
            }

            return vtable;
        }
    };

    pub fn load(path: [:0]const u8) !struct { Plugin, VTable } {
        Engine.log.info("loading plugin - '{s}'", .{std.fs.path.basename(path)});

        var lib = std.DynLib.open(path) catch |err| {
            Engine.log.debug("{?s}\n", .{std.c.dlerror()});
            return err;
        };

        const plugin = Plugin{ .path = path, .lib = lib };
        const vtable = try VTable.lookup(&lib, plugin.path);

        return .{ plugin, vtable };
    }

    pub fn unload(plugin: *Plugin) void {
        Engine.log.info("unloading plugin - '{s}'", .{std.fs.path.basename(plugin.path)});

        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrintZ(&buf, "{s}.0", .{plugin.path}) catch unreachable;

        std.fs.cwd().deleteFileZ(path) catch {};

        plugin.lib.close();
    }

    pub fn reload(plugin: *Plugin) !VTable {
        Engine.log.info("reloading plugin - '{s}'", .{std.fs.path.basename(plugin.path)});

        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrintZ(&buf, "{s}.0", .{plugin.path});

        plugin.lib.close();
        std.fs.cwd().copyFile(plugin.path, std.fs.cwd(), path, .{}) catch unreachable;

        plugin.lib = try std.DynLib.open(path);

        return VTable.lookup(&plugin.lib, plugin.path);
    }
};

pub const Error = std.DynLib.Error || error{
    missing_plugin_symbol,
};

const Engine = @import("../Engine.zig");
