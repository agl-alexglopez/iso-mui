/// Standard library stuff.
const std = @import("std");

/// Rendering pipeline module.
const render = @import("render.zig");

/// Maze stuff.
const maze = @import("maze.zig");
const rdfs = @import("builders/rdfs.zig");
const wilson = @import("builders/wilson_adder.zig");
const gen = @import("generator.zig");

/// Argument parsing helper.
const Args = struct {
    const row_flag: []const u8 = "-r=";
    const col_flag: []const u8 = "-c=";
    rows: isize = 20,
    cols: isize = 20,

    /// Helper to set fields of the argument struct.
    const Set = enum {
        r,
        c,
    };

    /// Attempts to set the field as specified according to arg input.
    pub fn set(
        /// [in] A reference to self to modify the row or col field.
        self: *Args,
        /// [in] The field to set.
        field: Set,
        /// [in] The string input. Assumes it is clean from any characters other than digits.
        arg: []const u8,
    ) !void {
        const conversion = try std.fmt.parseInt(isize, arg, 10);
        switch (field) {
            Set.r => self.rows = conversion,
            Set.c => self.cols = conversion,
        }
    }
};

fn roundup(n: isize, multiple: isize) isize {
    if (multiple == 0) {
        return n;
    }
    return @divTrunc((n + multiple - 1), multiple) * multiple;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var maze_args = Args{};
    const allocator = arena.allocator();
    for (std.os.argv[1..]) |a| {
        const arg = std.mem.span(a);
        if (std.mem.startsWith(u8, arg, Args.row_flag)) {
            try maze_args.set(Args.Set.r, arg[Args.row_flag.len..]);
        } else if (std.mem.startsWith(u8, arg, Args.col_flag)) {
            try maze_args.set(Args.Set.c, arg[Args.col_flag.len..]);
        } else {
            return error.UnrecognizedCommandLineArgument;
        }
    }
    const screen_width: i32 = @intCast(roundup(1000, 4));
    const screen_height: i32 = @intCast(roundup(1000, 3));
    var labyrinth: maze.Maze = try maze.Maze.init(
        allocator,
        roundup(maze_args.rows, 3),
        roundup(maze_args.cols, 4),
    );
    defer {
        labyrinth.deinit(allocator);
        arena.deinit();
    }
    _ = try wilson.generate(&labyrinth);

    // Rendering code when maze is complete.
    const loop = try render.Render.init(&labyrinth, screen_width, screen_height);
    defer render.Render.deinit();
    loop.run(&labyrinth);
}
