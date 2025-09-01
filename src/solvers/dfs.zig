//! This file implements a depth first search to solve a randomly generated maze starting at a
//! random start point and ending at a random finish point within maze boundaries.
const std = @import("std");

const maze = @import("../maze.zig");
const sol = @import("../solve.zig");

pub fn solve(m: *maze.Maze, allocator: std.mem.Allocator) maze.MazeError!*maze.Maze {
    const start: maze.Point = try sol.setStartAndFinish(m);
    var dfs = std.array_list.Managed(maze.Point).init(allocator);
    defer dfs.deinit();
    _ = dfs.append(start) catch return maze.MazeError.AllocFail;
    branching: while (dfs.items.len != 0) {
        const cur: maze.Point = dfs.getLast();
        const square: maze.Square = m.get(cur.r, cur.c);
        if (sol.isFinish(square)) {
            try m.solve_history.record(maze.Delta{
                .p = cur,
                .before = square,
                .after = square | sol.thread_paints[0],
                .burst = 1,
            });
            m.getPtr(cur.r, cur.c).* |= sol.thread_paints[0];
            return m;
        }
        try m.solve_history.record(maze.Delta{
            .p = cur,
            .before = square,
            .after = square | sol.thread_paints[0] | sol.thread_seen,
            .burst = 1,
        });
        m.getPtr(cur.r, cur.c).* |= sol.thread_paints[0] | sol.thread_seen;
        for (maze.cardinal_directions) |p| {
            const next = maze.Point{ .r = cur.r + p.r, .c = cur.c + p.c };
            const s: maze.Square = m.get(next.r, next.c);
            if (maze.isPath(s) and ((s & sol.thread_seen) == 0)) {
                _ = dfs.append(next) catch return maze.MazeError.AllocFail;
                continue :branching;
            }
        }
        try m.solve_history.record(maze.Delta{
            .p = cur,
            .before = square,
            .after = square & ~sol.thread_paints[0],
            .burst = 1,
        });
        m.getPtr(cur.r, cur.c).* &= ~sol.thread_paints[0];
        _ = dfs.pop();
    }
    return m;
}
