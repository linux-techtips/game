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

        pub fn lookup(lib: *std.DynLib) Error!VTable {
            var vtable: VTable = undefined;
            inline for (std.meta.fields(VTable)) |field| {
                const name = "Plug_" ++ [1]u8{std.ascii.toUpper(field.name[0])} ++ field.name[1..];
                @field(vtable, field.name) = lib.lookup(field.type, name) orelse {
                    Engine.log.err("failed to load plugin symbol: '{s}'", .{name});
                    return Error.missing_plugin_symbol;
                };
            }

            return vtable;
        }
    };

    pub fn load(path: [:0]const u8) !struct { Plugin, VTable } {
        var plugin = Plugin{ .path = path, .lib = try std.DynLib.open(path) };
        const vtable = try VTable.lookup(&plugin.lib);

        return .{ plugin, vtable };
    }

    pub fn unload(plugin: *Plugin) void {
        plugin.lib.close();
    }

    pub fn reload(plugin: *Plugin) Error!VTable {
        plugin.lib.close();
        plugin.lib = try std.DynLib.open(plugin.path);

        return VTable.lookup(&plugin.lib);
    }
};

pub const Error = std.DynLib.Error || error{
    missing_plugin_symbol,
};

const Engine = @import("../Engine.zig");
