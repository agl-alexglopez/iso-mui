//! This file implements a depth first search to solve a randomly generated maze starting at a
//! random start point and ending at a random finish point within maze boundaries.
const std = @import("std");
const zthreads = std.Thread;

const maze = @import("../maze.zig");
const sol = @import("../solve.zig");

/// It may seem redundant to have a monitor in addition to atomic maze squares but consider that
/// we must protect the maze Tape for the solve history with mutual exclusion. We benefit from
/// atomics by not having to lock the maze for every little check that a thread might peform
/// that is unrelated to recording history (checking if a square is a path or wall, checking
/// if it is seen, etc).
///
/// Then, when history or critical visual updates must occur, we can use the lock to protect
/// the tape and ordering of our painting.
const Monitor = struct {
    /// The lock for protecting painting and history update steps.
    lock: zthreads.Mutex,
    /// The monitor takes ownership of the maze temporarily for updates to its Tape.
    maze: *maze.Maze,
    /// Every thread has access to their own start, no locking required.
    starts: [sol.thread_count]maze.Point = undefined,
    /// Protection is handled by this being an atomic type.
    winning_thread_id: maze.Square = undefined,
    /// Each thread has their own path stack. Allocator provided must be thread safe.
    thread_paths: [sol.thread_count]std.array_list.Aligned(maze.Point, null),
    /// Threads can only execute functions that return void so they can leave errors here.
    thread_errors: [sol.thread_count]?maze.MazeError,

    fn init(m: *maze.Maze) Monitor {
        var res = Monitor{
            .lock = .{},
            .maze = m,
            .thread_paths = .{std.array_list.Aligned(maze.Point, null){}} ** sol.thread_count,
            .thread_errors = .{null} ** sol.thread_count,
        };
        res.winning_thread_id.store(sol.no_winner);
        return res;
    }

    fn deinit(self: *Monitor, allocator: std.mem.Allocator) void {
        for (0..self.thread_paths.len) |i| {
            self.thread_paths[i].deinit(allocator);
        }
    }
};

/// Expects a thread safe allocator and maze to solve.
pub fn solve(
    allocator: std.mem.Allocator,
    m: *maze.Maze,
) maze.MazeError!*maze.Maze {
    var monitor = Monitor.init(m);
    defer monitor.deinit(allocator);
    for (0..monitor.thread_paths.len) |i| {
        monitor.thread_paths[i].ensureTotalCapacity(
            allocator,
            1024,
        ) catch return maze.MazeError.AllocFail;
    }
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
    return m;
}

pub fn solver_thread(
    allocator: std.mem.Allocator,
    monitor: *Monitor,
    id: maze.SquareU32,
) void {
    var dfs = &monitor.thread_paths[id];
    push(allocator, dfs, monitor.starts[id]) catch |e| {
        monitor.thread_errors[id] = e;
        return;
    };
    branching: while (dfs.items.len != 0) {
        if (monitor.winning_thread_id.load() != sol.no_winner) {
            return;
        }
        const cur: maze.Point = dfs.getLast();
        if (sol.isFinish(monitor.maze.get(cur.r, cur.c).load())) {
            _ = monitor.winning_thread_id.compareXchg(sol.no_winner, id);
            _ = dfs.pop();
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
            return;
        }
        {
            monitor.lock.lock();
            defer monitor.lock.unlock();
            const s: maze.SquareU32 = monitor.maze.get(cur.r, cur.c).load();
            monitor.maze.solve_history.record(allocator, maze.Delta{
                .p = cur,
                .before = s,
                .after = s | sol.thread_paints[id] | sol.thread_cache_bits[id],
                .burst = 1,
            }) catch |e| {
                monitor.thread_errors[id] = e;
                return;
            };
            monitor.maze.getPtr(cur.r, cur.c).bitOrEq(
                sol.thread_paints[id] | sol.thread_cache_bits[id],
            );
        }
        // Bias threads toward unique directions for better visual spread.
        var i: usize = id;
        for (0..sol.thread_count) |_| {
            const p = maze.cardinal_directions[i];
            i = (i + 1) % maze.cardinal_directions.len;
            const next = maze.Point{ .r = cur.r + p.r, .c = cur.c + p.c };
            const s: maze.SquareU32 = monitor.maze.get(next.r, next.c).load();
            if (maze.isPath(s) and ((s & sol.thread_cache_bits[id]) == 0)) {
                push(allocator, dfs, next) catch |e| {
                    monitor.thread_errors[id] = e;
                    return;
                };
                continue :branching;
            }
        }
        {
            monitor.lock.lock();
            defer monitor.lock.unlock();
            const s: maze.SquareU32 = monitor.maze.get(cur.r, cur.c).load();
            monitor.maze.solve_history.record(allocator, maze.Delta{
                .p = cur,
                .before = s,
                .after = s & ~sol.thread_paints[id],
                .burst = 1,
            }) catch |e| {
                monitor.thread_errors[id] = e;
                return;
            };
            monitor.maze.getPtr(cur.r, cur.c).bitAndEq(~sol.thread_paints[id]);
        }
        _ = dfs.pop();
    }
}

fn push(
    allocator: std.mem.Allocator,
    stack: *std.array_list.Aligned(maze.Point, null),
    p: maze.Point,
) maze.MazeError!void {
    _ = stack.append(allocator, p) catch return maze.MazeError.AllocFail;
}
