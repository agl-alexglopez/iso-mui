const std = @import("std");
const maze = @import("maze.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const square: maze.Square = maze.north_wall | maze.east_wall;
    try stdout.print("Hello from main {s}!\n", .{maze.wall_piece(square)});
}
