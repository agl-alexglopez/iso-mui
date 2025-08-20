const std = @import("std");
const maze = @import("maze.zig");
const rdfs = @import("builders/rdfs.zig");
const wilson = @import("builders/wilson_adder.zig");
const gen = @import("generator.zig");

const Args = struct {
    rows: isize = 37,
    cols: isize = 137,
};

const row_flag: []const u8 = "-r=";
const col_flag: []const u8 = "-c=";

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var maze_args = Args{};
    const allocator = arena.allocator();
    for (std.os.argv[1..]) |a| {
        const arg = std.mem.span(a);
        if (std.mem.startsWith(u8, arg, row_flag)) {
            const str_rows = arg[row_flag.len..];
            maze_args.rows = try std.fmt.parseInt(isize, str_rows, 10);
        } else if (std.mem.startsWith(u8, arg, col_flag)) {
            const str_cols = arg[row_flag.len..];
            maze_args.cols = try std.fmt.parseInt(isize, str_cols, 10);
        } else {
            return error.UnrecognizedCommandLineArgument;
        }
    }
    var new_maze: maze.Maze = try maze.Maze.init(allocator, maze_args.rows, maze_args.cols);
    defer {
        new_maze.deinit(allocator);
        arena.deinit();
    }
    _ = try wilson.generate(&new_maze);
    for (0..@intCast(new_maze.maze.rows)) |r| {
        for (0..@intCast(new_maze.maze.cols)) |c| {
            try stdout.print("{s}", .{gen.getSquare(new_maze.get(@intCast(r), @intCast(c)))});
        }
        try stdout.print("\n", .{});
    }
}
