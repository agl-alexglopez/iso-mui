const std = @import("std");
const maze = @import("maze.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const square: maze.Square = maze.north_wall | maze.east_wall;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var new_maze: maze.Maze = try maze.Maze.init(gpa.allocator(), 10, 10);
    defer new_maze.deinit(gpa.allocator());
    try stdout.print("Hello from main {s}!\n", .{maze.wallPiece(square)});
}
