//! The solve helper module provides low level support for any and all maze solving algorithms.
//! Operations such as placing the start and finish squares or handling colors of the solver or
//! solvers can be handled by this module.
const std = @import("std");
const maze = @import("maze.zig");

/// The bit marking where one or more threads may be dispatched from to solve.
pub const start_bit: maze.SquareU32 = 0x40000000;

/// The bit marking the goal or finish square.
pub const finish_bit: maze.SquareU32 = 0x80000000;

/// A value to give to a monitor or manager of threads to indicate none have solved the maze.
pub const no_winner: maze.SquareU32 = std.math.maxInt(u32);

/// The thread limit for solvers.
pub const thread_count: usize = 4;

/// Here are all four tetradic colors if more solvers are added in a multithreading scheme:
pub const thread_paints = [thread_count]maze.SquareU32{
    0x880_044,
    0x766_002,
    0x009_531,
    0x010_A88,
};

/// Every thread can cache a square as seen individually.
pub const thread_cache_bits = [thread_count]maze.SquareU32{
    0x1_000_000,
    0x2_000_000,
    0x4_000_000,
    0x8_000_000,
};

/// Mask for obtaining the paint of a square.
pub const paint_mask: maze.SquareU32 = 0xFFFFFF;

// Masking to help obtain RGB color values

const red_mask: maze.SquareU32 = 0xFF0000;
const red_shift: maze.SquareU32 = 16;
const green_mask: maze.SquareU32 = 0xFF00;
const green_shift: maze.SquareU32 = 8;
const blue_mask: maze.SquareU32 = 0xFF;

/// A circular pattern of offsets from a point that include diagonal directions.
const all_directions = [8]maze.Point{
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
pub fn setStartAndFinish(allocator: std.mem.Allocator, m: *maze.Maze) maze.MazeError!maze.Point {
    var randgen = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const rand = randgen.random();
    const start: maze.Point = try randStartOrFinish(m, rand);
    const start_square = m.get(start.r, start.c).load();
    try m.solve_history.record(allocator, maze.Delta{
        .p = start,
        .before = start_square,
        .after = start_square | start_bit,
        .burst = 1,
    });
    m.getPtr(start.r, start.c).bitOrEq(start_bit);
    const finish: maze.Point = try randStartOrFinish(m, rand);
    const finish_square = m.get(finish.r, finish.c).load();
    try m.solve_history.record(allocator, maze.Delta{
        .p = finish,
        .before = finish_square,
        .after = finish_square | finish_bit,
        .burst = 1,
    });
    m.getPtr(finish.r, finish.c).bitOrEq(finish_bit);
    return start;
}

/// A randomly chosen point in the maze. We first start by trying to find a random valid point
/// or one close to a random point for a start or finish. If that fails we simply scan the entire
/// maze for an available square. If nothing works we return a logic error.
pub fn randStartOrFinish(m: *const maze.Maze, rand: std.Random) maze.MazeError!maze.Point {
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

/// A valid start or finish is an in bounds path square that is not already start or finish.
fn isValidStartOrFinish(m: *const maze.Maze, check: maze.Point) bool {
    return check.r > 0 and
        check.r < m.maze.rows - 1 and
        check.c > 0 and
        check.c < m.maze.cols - 1 and
        maze.isPath(m.get(check.r, check.c).load()) and
        !isStartOrFinish(m.get(check.r, check.c).load());
}

/// Returns true if the square is either start or finish.
pub fn isStartOrFinish(square: maze.SquareU32) bool {
    return (square & (start_bit | finish_bit)) != 0;
}

/// Returns true if the square is only a finish square.
pub fn isFinish(square: maze.SquareU32) bool {
    return (square & finish_bit) != 0;
}

/// Returns true if the square has been painted by any thread.
pub fn hasPaint(square: maze.SquareU32) bool {
    return (square & paint_mask) != 0;
}

/// Returns the {r, g, b} tuple of color found at this square.
pub fn getPaint(square: maze.SquareU32) struct { u8, u8, u8 } {
    return .{
        @intCast((square & red_mask) >> red_shift),
        @intCast((square & green_mask) >> green_shift),
        @intCast(square & blue_mask),
    };
}
