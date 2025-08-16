const std = @import("std");
const maze = @import("maze.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const square: maze.Square = maze.north_wall | maze.east_wall;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    var new_maze: maze.Maze = try maze.Maze.init(allocator, 10, 10);
    defer {
        new_maze.deinit(allocator);
        arena.deinit();
    }
    try stdout.print("Hello from main {s}!\n", .{maze.wallPiece(square)});
}
