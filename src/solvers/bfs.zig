//! This file implements a breadth first search to solve a randomly generated maze starting at a
//! random start point and ending at a random finish point within maze boundaries.
const std = @import("std");

const maze = @import("../maze.zig");
const sol = @import("../solve.zig");

const QueueElem = struct {
    e: std.DoublyLinkedList.Node = .{},
    point: maze.Point,
};

const Queue = struct {
    list: std.DoublyLinkedList,
    len: usize,

    pub fn deinit(self: *Queue, allocator: std.mem.Allocator) void {
        while (self.len != 0) {
            const handle = self.list.popFirst() orelse return;
            const elem: *QueueElem = @fieldParentPtr("e", handle);
            allocator.destroy(elem);
        }
    }

    pub fn queue(self: *Queue, p: maze.Point, allocator: std.mem.Allocator) maze.MazeError!void {
        var node: *QueueElem = allocator.create(QueueElem) catch return maze.MazeError.AllocFail;
        node.point = p;
        self.list.append(&node.e);
        self.len += 1;
    }

    fn dequeue(self: *Queue) maze.MazeError!*QueueElem {
        const handle: ?*std.DoublyLinkedList.Node = self.list.popFirst();
        if (handle) |h| {
            self.len -= 1;
            return @fieldParentPtr("e", h);
        }
        return maze.MazeError.AllocFail;
    }
};

pub fn solve(m: *maze.Maze, allocator: std.mem.Allocator) maze.MazeError!*maze.Maze {
    var bfs: Queue = .{ .list = std.DoublyLinkedList{}, .len = 0 };
    var parents = std.AutoArrayHashMap(maze.Point, maze.Point).init(allocator);
    defer {
        parents.deinit();
        bfs.deinit(allocator);
    }
    const start: maze.Point = try sol.setStartAndFinish(m);
    try put(&parents, start, .{ .r = -1, .c = -1 });
    try bfs.queue(start, allocator);
    while (bfs.len != 0) {
        const cur: *QueueElem = try bfs.dequeue();
        defer allocator.destroy(cur);
        const square: maze.Square = m.get(cur.point.r, cur.point.c);
        if (sol.isFinish(square)) {
            try m.solve_history.record(maze.Delta{
                .p = cur.point,
                .before = square,
                .after = square | sol.thread_paints[0],
                .burst = 1,
            });
            m.getPtr(cur.point.r, cur.point.c).* |= sol.thread_paints[0];
            var prev = parents.get(cur.point) orelse return maze.MazeError.LogicFail;
            // For now the winning solver will just paint the bright finish block color all the
            // way back to the start. However, if we were to implement multiple solver threads
            // with their own colors, we should just record this winning path in auxiliary storage
            // and then paint this path the color of the winner when all threads finish.
            while (prev.r > 0) {
                const s = m.get(prev.r, prev.c);
                try m.solve_history.record(maze.Delta{
                    .p = prev,
                    .before = s,
                    .after = s | sol.finish_bit,
                    .burst = 1,
                });
                m.getPtr(prev.r, prev.c).* |= sol.finish_bit;
                prev = parents.get(prev) orelse return maze.MazeError.LogicFail;
            }
            return m;
        }
        try m.solve_history.record(maze.Delta{
            .p = cur.point,
            .before = square,
            .after = square | sol.thread_paints[0],
            .burst = 1,
        });
        m.getPtr(cur.point.r, cur.point.c).* |= sol.thread_paints[0];
        for (maze.cardinal_directions) |p| {
            const next = maze.Point{ .r = cur.point.r + p.r, .c = cur.point.c + p.c };
            if (m.isPath(next.r, next.c) and !parents.contains(next)) {
                try put(&parents, next, cur.point);
                try bfs.queue(next, allocator);
            }
        }
    }
    return m;
}

fn put(
    map: *std.AutoArrayHashMap(maze.Point, maze.Point),
    k: maze.Point,
    v: maze.Point,
) maze.MazeError!void {
    _ = map.put(k, v) catch return maze.MazeError.AllocFail;
}
