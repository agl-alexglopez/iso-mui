//! This file implements a breadth first search to solve a randomly generated maze starting at a
//! random start point and ending at a random finish point within maze boundaries.
const std = @import("std");
const zthreads = std.Thread;

const q = @import("../flat_queue.zig");

const maze = @import("../maze.zig");
const sol = @import("../solve.zig");

/// When following a trail of parent points in the maze this signals the end or origin.
const sentinel_point = maze.Point{ .r = -1, .c = -1 };

/// Runs 4 threads with a breadth first search worker algorithm to see who will win and reports
/// the winning path visually in the maze with that threads shortest path color.
///
/// The provided allocator must be thread safe.
pub fn solve(allocator: std.mem.Allocator, m: *maze.Maze) maze.MazeError!*maze.Maze {
    var monitor = Monitor.init(m);
    defer monitor.deinit(allocator);
    monitor.winning_thread_path.ensureTotalCapacity(
        allocator,
        1024,
    ) catch return maze.MazeError.AllocFail;
    const start: maze.Point = try sol.setStartAndFinish(allocator, m);
    monitor.starts = .{start} ** sol.thread_count;
    var threads: [sol.thread_count]std.Thread = undefined;
    for (0..sol.thread_count - 1) |i| {
        const id: maze.SquareU32 = @intCast(i);
        threads[i] = std.Thread.spawn(
            .{
                // This allocator must be initialized as thread safe.
                .allocator = allocator,
            },
            solver_thread,
            .{
                allocator,
                &monitor,
                id,
            },
        ) catch {
            for (0..i + 1) |j| {
                threads[j].join();
            }
            return maze.MazeError.AllocFail;
        };
    }
    solver_thread(allocator, &monitor, sol.thread_count - 1);
    for (0..sol.thread_count - 1) |i| {
        threads[i].join();
    }
    // Return the first error a thread reported. Don't care too much just want to be thorough.
    for (monitor.thread_errors) |e| {
        if (e) |thread_error| {
            return thread_error;
        }
    }
    const id = monitor.winning_thread_id.load();
    if (id != sol.no_winner) {
        for (monitor.winning_thread_path.items) |s| {
            const square = m.get(s.r, s.c).load();
            try monitor.maze.solve_history.record(
                allocator,
                maze.Delta{
                    .p = s,
                    .before = square,
                    .after = (square & ~sol.paint_mask) | sol.thread_paints[id],
                    .burst = 1,
                },
            );
        }
    }
    return m;
}

/// The task for one thread running a bfs. It will try to find the finish and if it is the first
/// to arrive it will record its winning shortest path from start to finish in the monitor.
///
/// Each thread is biased to head in a cardinal direction first given its id, making the threads
/// spread out better.
fn solver_thread(
    allocator: std.mem.Allocator,
    monitor: *Monitor,
    id: maze.SquareU32,
) void {
    var bfs = q.FlatQueue(maze.Point, null).empty;
    var parents = std.AutoArrayHashMapUnmanaged(maze.Point, maze.Point).empty;
    defer {
        parents.deinit(allocator);
        bfs.deinit(allocator);
    }
    bfs.reserve(allocator, 1024) catch {
        monitor.thread_errors[id] = maze.MazeError.AllocFail;
        return;
    };
    put(allocator, &parents, monitor.starts[id], sentinel_point) catch |e| {
        monitor.thread_errors[id] = e;
        return;
    };
    queue(&bfs, allocator, monitor.starts[id]) catch |e| {
        monitor.thread_errors[id] = e;
        return;
    };
    while (!bfs.isEmpty()) {
        if (monitor.winning_thread_id.load() != sol.no_winner) {
            return;
        }
        const cur: maze.Point = dequeue(&bfs) catch |e| {
            monitor.thread_errors[id] = e;
            return;
        };
        if (sol.isFinish(monitor.maze.get(cur.r, cur.c).load())) {
            if (monitor.winning_thread_id.compareXchg(sol.no_winner, id)) |_| {
                return;
            }
            var prev = get(&parents, cur) catch |e| {
                monitor.thread_errors[id] = e;
                return;
            };
            while (!std.meta.eql(prev, sentinel_point)) {
                monitor.winning_thread_path.append(allocator, prev) catch {
                    monitor.thread_errors[id] = maze.MazeError.AllocFail;
                    return;
                };
                prev = get(&parents, prev) catch |e| {
                    monitor.thread_errors[id] = e;
                    return;
                };
            }
            return;
        }
        {
            monitor.lock.lock();
            defer monitor.lock.unlock();
            const s: maze.SquareU32 = monitor.maze.get(cur.r, cur.c).load();
            monitor.maze.solve_history.record(allocator, maze.Delta{
                .p = cur,
                .before = s,
                .after = s | sol.thread_paints[id],
                .burst = 1,
            }) catch |e| {
                monitor.thread_errors[id] = e;
                return;
            };
            monitor.maze.getPtr(cur.r, cur.c).bitOrEq(sol.thread_paints[id]);
        }
        var i: usize = id;
        for (0..maze.cardinal_directions.len) |_| {
            const p = maze.cardinal_directions[i];
            i = (i + 1) % maze.cardinal_directions.len;
            const next = maze.Point{ .r = cur.r + p.r, .c = cur.c + p.c };
            if (monitor.maze.isPath(next.r, next.c) and !parents.contains(next)) {
                put(allocator, &parents, next, cur) catch |e| {
                    monitor.thread_errors[id] = e;
                    return;
                };
                queue(&bfs, allocator, next) catch |e| {
                    monitor.thread_errors[id] = e;
                    return;
                };
            }
        }
    }
}

/// A monitor for a breadth first search awaits a winner and then allows the winner to save the
/// path. The lock is only needed when making updates to the maze history and squares that involve
/// painting visual updates. Otherwise, all squares are atomic and therefore each thread is free
/// to check and set bits unrelated to the visualization without a lock.
///
/// Because the winning thread id is an atomic it also acts as our flag for all threads when
/// recording the winning path. It is the synchronization primitive needed to ensure only one
/// winning thread is filling out the winning path. No further locking required.
const Monitor = struct {
    /// The lock for protecting painting and history update steps.
    lock: zthreads.Mutex,
    /// The monitor takes ownership of the maze temporarily for updates to its Tape.
    maze: *maze.Maze,
    /// Every thread has access to their own start, no locking required.
    starts: [sol.thread_count]maze.Point = undefined,
    /// Protection is handled by this being an atomic type.
    winning_thread_id: maze.Square = undefined,
    /// The path the winning thread took to reach finish.
    winning_thread_path: std.array_list.Aligned(maze.Point, null),
    /// Threads can only execute functions that return void so they can leave errors here.
    thread_errors: [sol.thread_count]?maze.MazeError,

    fn init(m: *maze.Maze) Monitor {
        var res = Monitor{
            .lock = .{},
            .maze = m,
            .winning_thread_path = std.array_list.Aligned(maze.Point, null).empty,
            .thread_errors = .{null} ** sol.thread_count,
        };
        res.winning_thread_id.store(sol.no_winner);
        return res;
    }

    fn deinit(self: *Monitor, allocator: std.mem.Allocator) void {
        self.winning_thread_path.deinit(allocator);
    }
};

/// Queue an element or report the allocation failure.
fn queue(
    bfs: *q.FlatQueue(maze.Point, null),
    gpa: std.mem.Allocator,
    v: maze.Point,
) maze.MazeError!void {
    _ = bfs.append(gpa, v) catch return maze.MazeError.AllocFail;
}

/// Dequeue an element or report the logic error in trying to pop from empty queue.
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
