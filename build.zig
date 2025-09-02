const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core module and exe
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "iso_mui",
        .root_module = exe_mod,
    });

    // Dependencies for core exe.

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    // Linking of dependencies.
    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    // Installation of core executable.
    b.installArtifact(exe);

    // LSP convenience helpers
    const exe_check = b.addExecutable(.{
        .name = "iso_mui",
        .root_module = exe_mod,
    });
    const check = b.step("check", "Check if iso_mui compiles");
    check.dependOn(&exe_check.step);

    // Add a run step for shorter command line use.
    const exe_run = b.addRunArtifact(exe);
    if (b.args) |args| {
        exe_run.addArgs(args);
    }
    const run = b.step("run", "Run iso_mui");
    run.dependOn(&exe_run.step);
}
