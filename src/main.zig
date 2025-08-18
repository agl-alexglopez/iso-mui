const std = @import("std");
const maze = @import("maze.zig");
const rdfs = @import("builders/rdfs.zig");
const gen = @import("generator.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    var new_maze: maze.Maze = try maze.Maze.init(allocator, 37, 137);
    defer {
        new_maze.deinit(allocator);
        arena.deinit();
    }
    _ = try rdfs.generate(&new_maze);
    for (0..@intCast(new_maze.maze.rows)) |r| {
        for (0..@intCast(new_maze.maze.cols)) |c| {
            try stdout.print("{s}", .{gen.getSquare(new_maze.get(@intCast(r), @intCast(c)))});
        }
        try stdout.print("\n", .{});
    }
}
