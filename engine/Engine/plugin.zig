const std = @import("std");

pub const Plugin = struct {
    path: [:0]const u8,
    lib: std.DynLib,

    pub const VTable = struct {
        pub const Startup = *const fn (*Engine) callconv(.C) ?*anyopaque;
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

        var plugin = Plugin{ .path = path, .lib = try std.DynLib.open(path) };
        const vtable = try VTable.lookup(&plugin.lib, plugin.path);

        return .{ plugin, vtable };
    }

    pub fn unload(plugin: *Plugin) void {
        Engine.log.info("unloading plugin - '{s}'", .{std.fs.path.basename(plugin.path)});
        plugin.lib.close();
    }

    pub fn reload(plugin: *Plugin) Error!VTable {
        Engine.log.info("reloading plugin - '{s}'", .{std.fs.path.basename(plugin.path)});

        plugin.lib.close();
        plugin.lib = try std.DynLib.open(plugin.path);

        return VTable.lookup(&plugin.lib, plugin.path);
    }
};

pub const Error = std.DynLib.Error || error{
    missing_plugin_symbol,
};

const Engine = @import("../Engine.zig");
