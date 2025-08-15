const std = @import("std");
const maze = @import("maze.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const square: maze.Square = 1;
    try stdout.print("Hello from main {d}!\n", .{square});
}
