const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.addModule("zig-zag-mui", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zig-zag-mui",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Check on save for LSP help.
    const exe_check = b.addExecutable(.{
        .name = "zig-zag-mui",
        .root_module = exe_mod,
    });
    const check = b.step("check", "Check if zig-zag-mui compiles");
    check.dependOn(&exe_check.step);

    const exe_run = b.addRunArtifact(exe);
    if (b.args) |args| {
        exe_run.addArgs(args);
    }
    const run = b.step("run", "Run zig-zag-mui");
    run.dependOn(&exe_run.step);
}
