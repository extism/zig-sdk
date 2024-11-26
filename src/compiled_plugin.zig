const std = @import("std");
const Manifest = @import("manifest.zig").Manifest;
const Function = @import("function.zig");
const CancelHandle = @import("cancel_handle.zig");
const c = @import("ffi.zig");

const Self = @This();

ptr: *c.ExtismCompiledPlugin,

// We have to use this until ziglang/zig#2647 is resolved.
error_info: ?[]const u8,

/// Create a new plugin from a WASM module
pub fn init(allocator: std.mem.Allocator, data: []const u8, functions: []const Function, wasi: bool) !Self {
    var plugin: ?*c.ExtismCompiledPlugin = null;
    var errmsg: [*c]u8 = null;
    if (functions.len > 0) {
        var funcPtrs = try allocator.alloc(?*c.ExtismFunction, functions.len);
        defer allocator.free(funcPtrs);
        var i: usize = 0;
        for (functions) |function| {
            funcPtrs[i] = function.c_func;
            i += 1;
        }
        plugin = c.extism_compiled_plugin_new(data.ptr, @as(u64, data.len), &funcPtrs[0], functions.len, wasi, &errmsg);
    } else {
        plugin = c.extism_compiled_plugin_new(data.ptr, @as(u64, data.len), null, 0, wasi, &errmsg);
    }

    if (plugin == null) {
        // TODO: figure out what to do with this error
        std.debug.print("extism_compiled_plugin_new: {s}\n", .{
            errmsg,
        });
        c.extism_plugin_new_error_free(errmsg);
        return error.PluginLoadFailed;
    }
    return Self{
        .ptr = plugin.?,
        .error_info = null,
    };
}

/// Create a new plugin from the given manifest
pub fn initFromManifest(allocator: std.mem.Allocator, manifest: Manifest, functions: []const Function, wasi: bool) !Self {
    const json = try std.json.stringifyAlloc(allocator, manifest, .{ .emit_null_optional_fields = false });
    defer allocator.free(json);
    return init(allocator, json, functions, wasi);
}

pub fn deinit(self: *Self) void {
    c.extism_compiled_plugin_free(self.ptr);
}
