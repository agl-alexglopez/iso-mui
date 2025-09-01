//! This file implements a depth first search to solve a randomly generated maze starting at a
//! random start point and ending at a random finish point within maze boundaries.
const std = @import("std");

const maze = @import("../maze.zig");
const sol = @import("solve.zig");

pub fn solve(m: *maze.Maze, allocator: std.mem.Allocator) maze.MazeError!*maze.Maze {
    const start: maze.Point = try sol.randPoint(m);
    const start_square = m.get(start.r, start.c);
    m.solve_history.record(maze.Delta{
        .p = start,
        .before = start_square,
        .after = start_square | sol.start_bit,
        .burst = 1,
    });
    m.getPtr(start.r, start.c).* |= sol.start_bit;
    const finish: maze.Point = try sol.randPoint(m);
    const finish_square = m.get(finish.r, finish.c);
    m.solve_history.record(maze.Delta{
        .p = finish,
        .before = finish_square,
        .after = finish_square | sol.finish_bit,
        .burst = 1,
    });
    m.getPtr(finish.r, finish.c).* |= sol.finish_bit;
    var dfs = std.array_list.Managed(maze.Point).init(allocator);
    dfs.append(start);
    branching: while (dfs.items.len) {
        const cur: maze.Point = dfs.getLast();
        const square: maze.Square = m.get(cur.r, cur.c);
        if (sol.isFinish(square)) {
            m.solve_history.record(maze.Delta{
                .p = cur,
                .before = square,
                .after = square | sol.thread_paints[0],
                .burst = 1,
            });
            m.getPtr(cur.r, cur.c).* |= sol.thread_paints[0];
            return m;
        }
        m.solve_history.record(maze.Delta{
            .p = cur,
            .before = square,
            .after = square | sol.thread_paints[0] | sol.thread_seen,
            .burst = 1,
        });
        m.getPtr(cur.r, cur.c).* |= sol.thread_paints[0] | sol.thread_seen;
        for (maze.cardinal_directions) |p| {
            const next = maze.Point{ .r = cur.r + p.r, .c = cur.c + p.c };
            const s: maze.Square = m.get(next.r, next.c);
            if (maze.isPath(next.r, next.c) and ((s & sol.thread_seen) == 0)) {
                dfs.append(next);
                continue :branching;
            }
        }
        m.solve_history.record(maze.Delta{
            .p = cur,
            .before = square,
            .after = square & !sol.thread_paints[0],
            .burst = 1,
        });
        m.getPtr(cur.r, cur.c).* &= !sol.thread_paints[0];
        _ = dfs.pop();
    }
    return m;
}
