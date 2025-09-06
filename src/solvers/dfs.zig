//! This file implements a depth first search to solve a randomly generated maze starting at a
//! random start point and ending at a random finish point within maze boundaries.
const std = @import("std");

const maze = @import("../maze.zig");
const sol = @import("../solve.zig");

pub fn solve(
    allocator: std.mem.Allocator,
    m: *maze.Maze,
) maze.MazeError!*maze.Maze {
    const start: maze.Point = try sol.setStartAndFinish(allocator, m);
    var dfs = std.array_list.Aligned(maze.Point, null){};
    defer dfs.deinit(allocator);
    _ = dfs.append(allocator, start) catch return maze.MazeError.AllocFail;
    branching: while (dfs.items.len != 0) {
        const cur: maze.Point = dfs.getLast();
        const square: maze.SquareU32 = m.get(cur.r, cur.c).load();
        if (sol.isFinish(square)) {
            try m.solve_history.record(allocator, maze.Delta{
                .p = cur,
                .before = square,
                .after = square | sol.thread_paints[0],
                .burst = 1,
            });
            m.getPtr(cur.r, cur.c).bitOrEq(sol.thread_paints[0]);
            return m;
        }
        try m.solve_history.record(allocator, maze.Delta{
            .p = cur,
            .before = square,
            .after = square | sol.thread_paints[0] | sol.thread_seen,
            .burst = 1,
        });
        m.getPtr(cur.r, cur.c).bitOrEq(sol.thread_paints[0] | sol.thread_seen);
        for (maze.cardinal_directions) |p| {
            const next = maze.Point{ .r = cur.r + p.r, .c = cur.c + p.c };
            const s: maze.SquareU32 = m.get(next.r, next.c).load();
            if (maze.isPath(s) and ((s & sol.thread_seen) == 0)) {
                _ = dfs.append(allocator, next) catch return maze.MazeError.AllocFail;
                continue :branching;
            }
        }
        try m.solve_history.record(allocator, maze.Delta{
            .p = cur,
            .before = square,
            .after = square & ~sol.thread_paints[0],
            .burst = 1,
        });
        m.getPtr(cur.r, cur.c).bitAndEq(~sol.thread_paints[0]);
        _ = dfs.pop();
    }
    return m;
}
