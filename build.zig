const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe_mod = b.addModule("zig-zag-tui", .{
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
    });

    const exe = b.addExecutable(.{
        .name = "zig-zag-tui",
        .root_source_file = b.path("src/main.zig"),
        .target = b.graph.host,
    });
    b.installArtifact(exe);

    // Check on save for LSP help.
    const exe_check = b.addExecutable(.{
        .name = "zig-zag-tui",
        .root_module = exe_mod,
    });
    const check = b.step("check", "Check if zig-zag-tui compiles");
    check.dependOn(&exe_check.step);
}
