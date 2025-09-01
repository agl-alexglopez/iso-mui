//! The solve helper module provides low level support for any and all maze solving algorithms.
//! Operations such as placing the start and finish squares or handling colors of the solver or
//! solvers can be handled by this module.
const std = @import("std");
const maze = @import("maze.zig");

pub const start_bit: maze.Square = 0x40000000;
pub const finish_bit: maze.Square = 0x80000000;

/// Here are all four tetradic colors if more solvers are added in a multithreading scheme:
/// 0x880044, 0x766002, 0x009531, 0x010a88
pub const thread_paints = [1]maze.Square{0x880044};
/// The bit a thread can use to mark a square as seen.
pub const thread_seen: maze.Square = 0x1000000;
/// Mask for obtaining the paint of a square.
pub const paint_mask: maze.Square = 0xFFFFFF;
pub const red_mask: maze.Square = 0xFF0000;
pub const red_shift: maze.Square = 16;
pub const green_mask: maze.Square = 0xFF00;
pub const green_shift: maze.Square = 8;
pub const blue_mask: maze.Square = 0xFF;

pub const all_directions = [8]maze.Point{
    .{ .r = 1, .c = 0 },
    .{ .r = 1, .c = 1 },
    .{ .r = 0, .c = 1 },
    .{ .r = -1, .c = 1 },
    .{ .r = -1, .c = 0 },
    .{ .r = -1, .c = -1 },
    .{ .r = 0, .c = -1 },
    .{ .r = 1, .c = -1 },
};

/// Sets the start and finish squares randomly and records their construction in the solve
/// history tape. If sufficient starting and finishing squares cannot be found a logical error
/// is returned. Returns the starting square upon success.
pub fn setStartAndFinish(m: *maze.Maze) maze.MazeError!maze.Point {
    var randgen = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const rand = randgen.random();
    const start: maze.Point = try randPoint(m, rand);
    const start_square = m.get(start.r, start.c);
    try m.solve_history.record(maze.Delta{
        .p = start,
        .before = start_square,
        .after = start_square | start_bit,
        .burst = 1,
    });
    m.getPtr(start.r, start.c).* |= start_bit;
    const finish: maze.Point = try randPoint(m, rand);
    const finish_square = m.get(finish.r, finish.c);
    try m.solve_history.record(maze.Delta{
        .p = finish,
        .before = finish_square,
        .after = finish_square | finish_bit,
        .burst = 1,
    });
    m.getPtr(finish.r, finish.c).* |= finish_bit;
    return start;
}

pub fn randPoint(m: *const maze.Maze, rand: std.Random) maze.MazeError!maze.Point {
    const pick = maze.Point{
        .r = rand.intRangeAtMost(isize, 1, m.maze.rows - 2),
        .c = rand.intRangeAtMost(isize, 1, m.maze.cols - 2),
    };
    if (isValidStartOrFinish(m, pick)) {
        return pick;
    }
    for (all_directions) |dir| {
        const point = maze.Point{
            .r = pick.r + dir.r,
            .c = pick.c + dir.c,
        };
        if (isValidStartOrFinish(m, point)) {
            return point;
        }
    }
    {
        var r: isize = 0;
        while (r < m.maze.rows - 1) : (r += 1) {
            var c: isize = 0;
            while (c < m.maze.cols - 1) : (c += 1) {
                const point = maze.Point{ .r = r, .c = c };
                if (isValidStartOrFinish(m, point)) {
                    return point;
                }
            }
        }
    }
    return maze.MazeError.LogicFail;
}

fn isValidStartOrFinish(m: *const maze.Maze, check: maze.Point) bool {
    return check.r > 0 and
        check.r < m.maze.rows - 1 and
        check.c > 0 and
        check.c < m.maze.cols - 1 and
        maze.isPath(m.get(check.r, check.c)) and
        !isStartOrFinish(m.get(check.r, check.c));
}

pub fn isStartOrFinish(square: maze.Square) bool {
    return (square & (start_bit | finish_bit)) != 0;
}

pub fn isFinish(square: maze.Square) bool {
    return (square & finish_bit) != 0;
}

pub fn hasPaint(square: maze.Square) bool {
    return (square & paint_mask) != 0;
}

/// Returns the {r, g, b} tuple of color found at this square.
pub fn getPaint(square: maze.Square) struct { u8, u8, u8 } {
    return .{
        @intCast((square & red_mask) >> red_shift),
        @intCast((square & green_mask) >> green_shift),
        @intCast(square & blue_mask),
    };
}
