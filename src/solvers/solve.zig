//! The solve helper module provides low level support for any and all maze solving algorithms.
//! Operations such as placing the start and finish squares or handling colors of the solver or
//! solvers can be handled by this module.
const std = @import("std");
const maze = @import("../maze.zig");

pub const start_bit: maze.Square = 0x40000000;
pub const finish_bit: maze.Square = 0x80000000;

/// Here are all four tetradic colors if more solvers are added in a multithreading scheme:
/// 0x880044, 0x766002, 0x009531, 0x010a88
pub const thread_paints = [1]maze.Square{0x880044};
/// The bit a thread can use to mark a square as seen.
pub const thread_seen: maze.Square = 0x1000000;

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

pub fn randPoint(m: *const maze.Maze) maze.MazeError!maze.Point {
    var randgen = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const rand = randgen.random();
    const pick = maze.Point{
        .r = rand.intRangeAtMost(1, m.maze.rows - 2),
        .c = rand.intRangeAtMost(1, m.maze.cols - 2),
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

fn isStartOrFinish(square: maze.Square) bool {
    return (square & (start_bit | finish_bit)) != 0;
}

pub fn isFinish(square: maze.Square) bool {
    return (square & finish_bit) != 0;
}
