# Extism Zig Host SDK

This repo contains the Zig code for integrating with the [Extism](https://extism.org/) runtime. Install this library into your host Zig application to run Extism plug-ins.

> **Note**: If you're unsure what Extism is or what an SDK is see our homepage: [https://extism.org](https://extism.org).

> **Note**: This is an early 1.0 release and is unstable until we hit 1.0. If you are looking to integrate now consider looking at the 0.x version in the [extism/extism](https://github.com/extism/extism/tree/main/zig) repo.

## Installation

### Install the Extism Runtime Dependency

For this library, you first need to install the Extism Runtime. You can [download the shared object directly from a release](https://github.com/extism/extism/releases) or use the [Extism CLI](https://github.com/extism/cli) to install it:

```bash
sudo extism lib install latest

#=> Fetching https://github.com/extism/extism/releases/download/v0.5.2/libextism-aarch64-apple-darwin-v0.5.2.tar.gz
#=> Copying libextism.dylib to /usr/local/lib/libextism.dylib
#=> Copying extism.h to /usr/local/include/extism.h
```

> **Note**: This library has breaking changes and targets 1.0 of the runtime. For the time being, install the runtime from our nightly development builds on git: `sudo extism lib install --version git`.

# within your Zig project directory:
This package works with the Zig package manager introduced in Zig 0.11. Create a `build.zig.zon` file like this:
```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .paths = .{""},
    .dependencies = .{
        .extism = .{
            .url = "https://github.com/extism/zig-sdk/archive/<git-ref-here>.tar.gz",
            // .hash = "" (zig build will tell you what to put here)
        },
    },
}
```
And in your `build.zig`:
```zig
const extism_module = b.dependency("extism", .{ .target = target, .optimize = optimize }).module("extism");
exe.root_module.addImport("extism", extism_module);
// TODO: make this easier to install
// add the shared library & header
exe.linkLibC();
exe.addIncludePath(.{ .path = "/usr/local/include" });
exe.addLibraryPath(.{ .path = "/usr/local/lib" });
exe.linkSystemLibrary("extism");
```

## Getting Started

This guide should walk you through some of the concepts in Extism and this Zig library.

### Creating A Plug-in

The primary concept in Extism is the [plug-in](https://extism.org/docs/concepts/plug-in). You can think of a plug-in as a code module stored in a `.wasm` file.

Since you may not have an Extism plug-in on hand to test, let's load a demo plug-in from the web:

```zig
// First require the library
const extism = @import("extism");
const std = @import("std");

const wasm_url = extism.manifest.WasmUrl{ .url = "https://github.com/extism/plugins/releases/latest/download/count_vowels.wasm" };
const manifest = .{ .wasm = &[_]extism.manifest.Wasm{.{ .wasm_url= wasm_url }} };

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer std.debug.assert(gpa.deinit() == .ok);
const allocator = gpa.allocator();

var plugin = try extism.Plugin.initFromManifest(
    allocator,
    manifest,
    &[_]extism.Function{},
    false,  
);

defer plugin.deinit();
```

> **Note**: See [the Manifest docs](https://github.com/extism/zig-sdk/blob/main/src/manifest.zig#L32) as it has a rich schema and a lot of options.

### Calling A Plug-in's Exports

This plug-in was written in Rust and it does one thing, it counts vowels in a string. As such, it exposes one "export" function: `count_vowels`. We can call exports using [Extism::Plugin#call](https://github.com/extism/zig-sdk/blob/main/src/plugin.zig#L61):

```zig
try plugin.call("count_vowels", "Hello, World!");
# => {"count": 3, "total": 3, "vowels": "aeiouAEIOU"}
```

All exports have a simple interface of bytes-in and bytes-out. This plug-in happens to take a string and return a JSON encoded string with a report of results.

### Plug-in State

Plug-ins may be stateful or stateless. Plug-ins can maintain state b/w calls by the use of variables. Our count vowels plug-in remembers the total number of vowels it's ever counted in the "total" key in the result. You can see this by making subsequent calls to the export:

```zig
try plugin.call("count_vowels", "Hello, World!");
# => {"count": 3, "total": 6, "vowels": "aeiouAEIOU"}
try plugin.call("count_vowels", "Hello, World!");
# => {"count": 3, "total": 9, "vowels": "aeiouAEIOU"}
```

These variables will persist until this plug-in is freed or you initialize a new one.

### Configuration

Plug-ins may optionally take a configuration object. This is a static way to configure the plug-in. Our count-vowels plugin takes an optional configuration to change out which characters are considered vowels. Example:

```zig
try plugin.call("count_vowels", "Yellow, World!");
# => {"count": 3, "total": 3, "vowels": "aeiouAEIOU"}

var config = std.json.ArrayHashMap([]const u8){};
defer config.deinit(allocator);

try config.map.put(allocator, "vowels", "aeiouyAEIOUY");
try plugin.setConfig(allocator, config);

try plugin.call("count_vowels", "Yellow, World!");
# => {"count": 4, "total": 4, "vowels": "aeiouAEIOUY"}
```

### Host Functions

Let's extend our count-vowels example a little bit: Instead of storing the `total` in an ephemeral plug-in var, let's store it in a persistent key-value store!

Wasm can't use our KV store on it's own. This is where [Host Functions](https://extism.org/docs/concepts/host-functions) come in.

[Host functions](https://extism.org/docs/concepts/host-functions) allow us to grant new capabilities to our plug-ins from our application. They are simply some zig methods you write which can be passed down and invoked from any language inside the plug-in.

Let's load the manifest like usual but load up this `count_vowels_kvstore` plug-in:

```zig
const wasm_url = extism.manifest.WasmUrl{ .url = "https://github.com/extism/plugins/releases/latest/download/count_vowels_kvstore.wasm" };
const manifest = .{ .wasm = &[_]extism.manifest.Wasm{.{ .wasm_url= wasm_url }} };
```

> *Note*: The source code for this is [here](https://github.com/extism/plugins/blob/main/count_vowels_kvstore/src/lib.rs) and is written in rust, but it could be written in any of our PDK languages.

Unlike our previous plug-in, this plug-in expects you to provide host functions that satisfy our its import interface for a KV store.

We want to expose two functions to our plugin, `kv_write(key: String, value: Bytes)` which writes a bytes value to a key and `kv_read(key: String) -> Bytes` which reads the bytes at the given `key`.

```zig
// pretend this is Redis or something
var KV_STORE: std.StringHashMap(u32) = undefined;

export fn kv_read(caller: ?*extism.c.ExtismCurrentPlugin, inputs: [*c]const extism.c.ExtismVal, n_inputs: u64, outputs: [*c]extism.c.ExtismVal, n_outputs: u64, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    var curr_plugin = extism.CurrentPlugin.getCurrentPlugin(caller orelse unreachable);

    // retrieve the key from the plugin
    var input_slice = inputs[0..n_inputs];
    const key = curr_plugin.inputBytes(&input_slice[0]);

    var out = outputs[0..n_outputs];
    // Try to get the value from KV_STORE
    if (KV_STORE.get(key)) |val| {
        // return the value to the plugin
        var data: [4]u8 = undefined;
        std.mem.writeInt(u32, &data, val, .little);
        curr_plugin.returnBytes(&out[0], &data);
    } else {
        KV_STORE.put(key, 0) catch unreachable;
        curr_plugin.returnBytes(&out[0], &[4]u8{ 0, 0, 0, 0 });
    }
}

export fn kv_write(caller: ?*extism.c.ExtismCurrentPlugin, inputs: [*c]const extism.c.ExtismVal, n_inputs: u64, outputs: [*c]extism.c.ExtismVal, n_outputs: u64, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    _ = outputs;
    _ = n_outputs;
    var curr_plugin = extism.CurrentPlugin.getCurrentPlugin(caller orelse unreachable);

    // retrieve key and value from the plugin
    var in = inputs[0..n_inputs];
    const key = curr_plugin.inputBytes(&in[0]);
    const val = curr_plugin.inputBytes(&in[1]);

    // write to the KV
    KV_STORE.put(key, std.mem.readInt(u32, val[0..4], .little)) catch unreachable;
}

```

Now we just need to create a new host environment and pass it in when loading the plug-in. Here our environment initializer takes no arguments, but you could imagine putting some customer specific instance variables in there:

```zig
 var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

KV_STORE = std.StringHashMap([]const u8).init(allocator);
defer KV_STORE.deinit();

var f_read = extism.Function.init(
    "kv_read",
    &[_]extism.c.ExtismValType{extism.c.I64},
    &[_]extism.c.ExtismValType{extism.c.I64},
    &kv_read,
    @constCast(@as(*const anyopaque, @ptrCast("user data"))),
);
defer f_read.deinit();

var f_write = extism.Function.init(
    "kv_write",
    &[_]extism.c.ExtismValType{extism.c.I64, extism.c.I64},
    &[_]extism.c.ExtismValType{},
    &kv_write,
    @constCast(@as(*const anyopaque, @ptrCast("user data"))),
);
defer f_write.deinit();

var plugin = try extism.Plugin.initFromManifest(
    allocator,
    manifest,
    &[_]extism.Function{f_read, f_write},
    false,  
);
defer plugin.deinit();
```

Now we can invoke the event:

```zig
try plugin.call("count_vowels", "Hello, World!");
# => {"count": 3, "total": 3, "vowels": "aeiouAEIOU"}

try plugin.call("count_vowels", "Hello, World!");
# => {"count": 3, "total": 6, "vowels": "aeiouAEIOU"}
```

