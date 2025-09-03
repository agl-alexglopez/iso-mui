//! This file implements a breadth first search to solve a randomly generated maze starting at a
//! random start point and ending at a random finish point within maze boundaries.
const std = @import("std");

const maze = @import("../maze.zig");
const sol = @import("../solve.zig");

const sentinel_point = maze.Point{ .r = -1, .c = -1 };

/// Solves a maze with a breadth first search. Visually this is distinct from a depth first search
/// because the colored blocks will expand in a different section of the map on each step.
pub fn solve(
    allocator: std.mem.Allocator,
    m: *maze.Maze,
) maze.MazeError!*maze.Maze {
    var bfs: Queue = .{ .list = std.DoublyLinkedList{}, .len = 0 };
    var parents = std.AutoArrayHashMapUnmanaged(maze.Point, maze.Point).empty;
    defer {
        parents.deinit(allocator);
        bfs.deinit(allocator);
    }
    const start: maze.Point = try sol.setStartAndFinish(allocator, m);
    try put(allocator, &parents, start, sentinel_point);
    try bfs.queue(start, allocator);
    while (!bfs.isEmpty()) {
        const cur: *const QueueElem = try bfs.dequeue();
        defer allocator.destroy(cur);
        const square: maze.Square = m.get(cur.point.r, cur.point.c);
        if (sol.isFinish(square)) {
            try m.solve_history.record(allocator, maze.Delta{
                .p = cur.point,
                .before = square,
                .after = square | sol.thread_paints[0],
                .burst = 1,
            });
            m.getPtr(cur.point.r, cur.point.c).* |= sol.thread_paints[0];
            var prev = try get(&parents, cur.point);
            // For now the winning solver will just paint the bright finish block color all the
            // way back to the start. However, if we were to implement multiple solver threads
            // with their own colors, we should just record this winning path in auxiliary storage
            // and then paint this path the color of the winner when all threads finish.
            while (!std.meta.eql(prev, sentinel_point)) {
                const s = m.get(prev.r, prev.c);
                try m.solve_history.record(allocator, maze.Delta{
                    .p = prev,
                    .before = s,
                    .after = s | sol.finish_bit,
                    .burst = 1,
                });
                m.getPtr(prev.r, prev.c).* |= sol.finish_bit;
                prev = try get(&parents, prev);
            }
            return m;
        }
        try m.solve_history.record(allocator, maze.Delta{
            .p = cur.point,
            .before = square,
            .after = square | sol.thread_paints[0],
            .burst = 1,
        });
        m.getPtr(cur.point.r, cur.point.c).* |= sol.thread_paints[0];
        for (maze.cardinal_directions) |p| {
            const next = maze.Point{ .r = cur.point.r + p.r, .c = cur.point.c + p.c };
            if (m.isPath(next.r, next.c) and !parents.contains(next)) {
                try put(allocator, &parents, next, cur.point);
                try bfs.queue(next, allocator);
            }
        }
    }
    return m;
}

/// Element on which the doubly linked list can intrude.
const QueueElem = struct {
    e: std.DoublyLinkedList.Node = .{},
    point: maze.Point,
};

/// This should be flat DEQ, but I guess Zig has removed most of these from their std offerings.
/// I should make my own because a linked list is a worse version but I don't feel like implementing
/// a DEQ right now and it's a good exercise to see how Zig does intrusive stuff.
const Queue = struct {
    list: std.DoublyLinkedList,
    len: usize,

    pub fn deinit(self: *Queue, allocator: std.mem.Allocator) void {
        while (self.len != 0) : (self.len -= 1) {
            const handle = self.list.popFirst() orelse return;
            const elem: *QueueElem = @fieldParentPtr("e", handle);
            allocator.destroy(elem);
        }
        self.* = undefined;
    }

    pub fn queue(self: *Queue, p: maze.Point, allocator: std.mem.Allocator) maze.MazeError!void {
        var node: *QueueElem = allocator.create(QueueElem) catch return maze.MazeError.AllocFail;
        node.point = p;
        self.list.append(&node.e);
        self.len += 1;
    }

    pub fn isEmpty(self: *const Queue) bool {
        return self.len == 0;
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
