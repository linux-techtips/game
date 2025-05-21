const std = @import("std");

const Engine = @import("Engine.zig");
const Plugin = @This();

pub const Error = error{
    missing_method,
};

path: [:0]const u8,
lib: std.DynLib,
vtable: VTable,

const VTable = struct {
    const Startup = *const fn (*Engine) callconv(.C) ?*anyopaque;
    const Shutdown = *const fn (*Engine, *anyopaque) callconv(.C) void;
    const Loaded = *const fn (*Engine, *anyopaque) callconv(.C) void;
    const Update = *const fn (*Engine, *anyopaque) callconv(.C) bool;
    const Event = *const fn (*Engine, *anyopaque, *const Engine.Event) callconv(.C) bool;

    startup: Startup,
    shutdown: Shutdown,
    update: Update,
    loaded: Loaded,
    event: Event,

    pub fn lookup(lib: *std.DynLib) Error!VTable {
        var vtable: VTable = undefined;
        inline for (std.meta.fields(VTable)) |field| {
            const name = "Plug_" ++ [1]u8{std.ascii.toUpper(field.name[0])} ++ field.name[1..];
            @field(vtable, field.name) = lib.lookup(field.type, name) orelse {
                log.err("failed to load plugin method: '{s}'", .{name});
                return Error.missing_method;
            };
        }

        return vtable;
    }
};

pub fn load(path: [:0]const u8) !Plugin {
    log.debug("loading plugin '{s}'...", .{std.fs.path.basename(path)});
    var lib = try std.DynLib.open(path);

    return .{
        .vtable = try VTable.lookup(&lib),
        .path = path,
        .lib = lib,
    };
}

pub fn unload(plugin: *Plugin) void {
    log.debug("unloading plugin '{s}'...", .{std.fs.path.basename(plugin.path)});
    plugin.lib.close();
}

pub fn reload(plugin: *Plugin) !void {
    log.debug("reloading plugin '{s}'...", .{std.fs.path.basename(plugin.path)});
    plugin.lib.close();
    plugin.lib = try std.DynLib.open(plugin.path);
    plugin.vtable = try VTable.lookup(&plugin.lib);
}

const root = @import("root");
const log = if (@hasDecl(root, "log")) root.log else std.log.scoped(.plugin);
