const std = @import("std");
const maze = @import("maze.zig");
const rdfs = @import("builders/rdfs.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    var new_maze: maze.Maze = try maze.Maze.init(allocator, 20, 20);
    defer {
        new_maze.deinit(allocator);
        arena.deinit();
    }
    _ = try rdfs.generate(&new_maze);
}
