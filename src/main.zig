const std = @import("std");
const maze = @import("maze.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    var new_maze: maze.Maze = try maze.Maze.init(allocator, 37, 137);
    defer {
        new_maze.deinit(allocator);
        arena.deinit();
    }
}
