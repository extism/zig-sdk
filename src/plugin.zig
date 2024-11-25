const std = @import("std");
const Manifest = @import("manifest.zig").Manifest;
const Function = @import("function.zig");
const CancelHandle = @import("cancel_handle.zig");
const c = @import("ffi.zig");
const CompiledPlugin = @import("compiled_plugin.zig");

const Self = @This();

ptr: *c.ExtismPlugin,

// We have to use this until ziglang/zig#2647 is resolved.
error_info: ?[]const u8,

/// Create a new plugin from a WASM module
pub fn init(allocator: std.mem.Allocator, data: []const u8, functions: []const Function, wasi: bool) !Self {
    var plugin: ?*c.ExtismPlugin = null;
    var errmsg: [*c]u8 = null;
    if (functions.len > 0) {
        var funcPtrs = try allocator.alloc(?*c.ExtismFunction, functions.len);
        defer allocator.free(funcPtrs);
        var i: usize = 0;
        for (functions) |function| {
            funcPtrs[i] = function.c_func;
            i += 1;
        }
        plugin = c.extism_plugin_new(data.ptr, @as(u64, data.len), &funcPtrs[0], functions.len, wasi, &errmsg);
    } else {
        plugin = c.extism_plugin_new(data.ptr, @as(u64, data.len), null, 0, wasi, &errmsg);
    }

    if (plugin == null) {
        // TODO: figure out what to do with this error
        std.debug.print("extism_plugin_new: {s}", .{
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

/// Create a new plugin from a pre-compiled plugin
pub fn initFromCompiled(compiled: *CompiledPlugin) !Self {
    var errmsg: [*c]u8 = null;
    const plugin = c.extism_plugin_new_from_compiled(compiled.ptr, &errmsg);
    if (plugin == null) {
        // TODO: figure out what to do with this error
        std.debug.print("extism_plugin_new: {s}\n", .{
            errmsg,
        });
        c.extism_plugin_new_error_free(errmsg);
        return error.PluginLoadFailed;
    }
    return plugin;
}

pub fn deinit(self: *Self) void {
    c.extism_plugin_free(self.ptr);
}

pub fn cancelHandle(self: *Self) CancelHandle {
    const ptr = c.extism_plugin_cancel_handle(self.ptr);
    return .{ .handle = ptr };
}

fn handleCall(self: *Self, res: i32) ![]const u8 {
    if (res != 0) {
        const err_c = c.extism_plugin_error(self.ptr);
        const err = std.mem.span(err_c);

        if (!std.mem.eql(u8, err, "")) {
            self.error_info = err;
        }
        self.error_info = "<unset by plugin>";
        return error.PluginCallFailed;
    }

    const len = c.extism_plugin_output_length(self.ptr);

    if (len > 0) {
        const output_data = c.extism_plugin_output_data(self.ptr);
        return output_data[0..len];
    }
    return "";
}

/// Call a function with the given input
pub fn call(self: *Self, function_name: []const u8, input: []const u8) ![]const u8 {
    const res = c.extism_plugin_call(self.ptr, function_name.ptr, input.ptr, @as(u64, input.len));
    return self.handleCall(res);
}

/// Call a function with the given input and host context
pub fn callWithContext(self: *Self, function_name: []const u8, input: []const u8, host_context: *anyopaque) ![]const u8 {
    const res = c.extism_plugin_call_with_host_context(self.ptr, function_name.ptr, input.ptr, @as(u64, input.len), host_context);
    return self.handleCall(res);
}

/// Set configuration values
pub fn setConfig(self: *Self, allocator: std.mem.Allocator, config: std.json.ArrayHashMap([]const u8)) !void {
    const config_json = try std.json.stringifyAlloc(allocator, config, .{ .emit_null_optional_fields = false });
    defer allocator.free(config_json);
    _ = c.extism_plugin_config(self.ptr, config_json.ptr, @as(u64, config_json.len));
}

/// Returns true if the plugin has a function matching `function_name`
pub fn hasFunction(self: Self, function_name: []const u8) bool {
    const res = c.extism_plugin_function_exists(self.ptr, function_name.ptr);
    return res;
}
