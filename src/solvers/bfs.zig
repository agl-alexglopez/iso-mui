//! This file implements a breadth first search to solve a randomly generated maze starting at a
//! random start point and ending at a random finish point within maze boundaries.
const std = @import("std");
const q = @import("../flat_queue.zig");

const maze = @import("../maze.zig");
const sol = @import("../solve.zig");

/// When following a trail of parent points in the maze this signals the end or origin.
const sentinel_point = maze.Point{ .r = -1, .c = -1 };

/// Solves a maze with a breadth first search. Visually this is distinct from a depth first search
/// because the colored blocks will expand in a different section of the map on each step.
pub fn solve(
    allocator: std.mem.Allocator,
    m: *maze.Maze,
) maze.MazeError!*maze.Maze {
    var bfs = q.FlatQueue(maze.Point, null).empty;
    var parents = std.AutoArrayHashMapUnmanaged(maze.Point, maze.Point).empty;
    defer {
        parents.deinit(allocator);
        bfs.deinit(allocator);
    }
    const start: maze.Point = try sol.setStartAndFinish(allocator, m);
    try put(allocator, &parents, start, sentinel_point);
    try queue(&bfs, allocator, start);
    while (!bfs.isEmpty()) {
        const cur: maze.Point = try dequeue(&bfs);
        const square: maze.SquareU32 = m.get(cur.r, cur.c).load();
        if (sol.isFinish(square)) {
            try m.solve_history.record(allocator, maze.Delta{
                .p = cur,
                .before = square,
                .after = square | sol.thread_paints[0],
                .burst = 1,
            });
            m.getPtr(cur.r, cur.c).bitOrEq(sol.thread_paints[0]);
            var prev = try get(&parents, cur);
            // For now the winning solver will just paint the bright finish block color all the
            // way back to the start. However, if we were to implement multiple solver threads
            // with their own colors, we should just record this winning path in auxiliary storage
            // and then paint this path the color of the winner when all threads finish.
            while (!std.meta.eql(prev, sentinel_point)) {
                const s = m.get(prev.r, prev.c).load();
                try m.solve_history.record(allocator, maze.Delta{
                    .p = prev,
                    .before = s,
                    .after = s | sol.finish_bit,
                    .burst = 1,
                });
                m.getPtr(prev.r, prev.c).bitOrEq(sol.finish_bit);
                prev = try get(&parents, prev);
            }
            return m;
        }
        try m.solve_history.record(allocator, maze.Delta{
            .p = cur,
            .before = square,
            .after = square | sol.thread_paints[0],
            .burst = 1,
        });
        m.getPtr(cur.r, cur.c).bitOrEq(sol.thread_paints[0]);
        for (maze.cardinal_directions) |p| {
            const next = maze.Point{ .r = cur.r + p.r, .c = cur.c + p.c };
            if (m.isPath(next.r, next.c) and !parents.contains(next)) {
                try put(allocator, &parents, next, cur);
                try queue(&bfs, allocator, next);
            }
        }
    }
    return m;
}

fn queue(
    bfs: *q.FlatQueue(maze.Point, null),
    gpa: std.mem.Allocator,
    v: maze.Point,
) maze.MazeError!void {
    _ = bfs.append(gpa, v) catch return maze.MazeError.AllocFail;
}

fn dequeue(
    bfs: *q.FlatQueue(maze.Point, null),
) maze.MazeError!maze.Point {
    if (bfs.popFirst()) |f| {
        return f;
    }
    return maze.MazeError.LogicFail;
}

/// Puts the requested key and value in the hash map or returns an allocation failure.
fn put(
    allocator: std.mem.Allocator,
    map: *std.AutoArrayHashMapUnmanaged(maze.Point, maze.Point),
    k: maze.Point,
    v: maze.Point,
) maze.MazeError!void {
    _ = map.put(allocator, k, v) catch return maze.MazeError.AllocFail;
}

/// Gets the requested value from the given key k. If k is not in the map, returns a logic error.
fn get(
    map: *std.AutoArrayHashMapUnmanaged(maze.Point, maze.Point),
    k: maze.Point,
) maze.MazeError!maze.Point {
    return map.get(k) orelse return maze.MazeError.LogicFail;
}
