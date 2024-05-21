const std = @import("std");
const builtin = @import("builtin");
const LazyPath = std.Build.LazyPath;
pub fn build(b: *std.Build) void {
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.13.0-dev.230+50a141945") catch unreachable; // build system changes: ziglang/zig#19597
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
        }
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const extism_module = b.addModule("extism", .{
        .root_source_file = b.path("src/main.zig"),
    });

    var tests = b.addTest(.{
        .name = "Library Tests",
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
    });

    tests.root_module.addImport("extism", extism_module);
    tests.linkLibC();
    tests.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    tests.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    tests.linkSystemLibrary("extism");
    const tests_run_step = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests_run_step.step);

    var example = b.addExecutable(.{
        .name = "Example",
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
    });

    example.root_module.addImport("extism", extism_module);
    example.linkLibC();
    example.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    example.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    example.linkSystemLibrary("extism");
    const example_run_step = b.addRunArtifact(example);

    const example_step = b.step("run_example", "Run the basic example");
    example_step.dependOn(&example_run_step.step);
}

pub fn addLibrary(to: *std.Build.Step.Compile, b: *std.Build) void {
    to.root_module.addImport("extism", b.dependency("extism", .{}).module("extism"));
    to.linkLibC();
    // TODO: switch based on platform and use platform-specific paths here
    to.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    to.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    to.linkSystemLibrary("extism");
}
