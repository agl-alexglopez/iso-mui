//! The wilson_adder module implements Wilson's wall adder algorithm to build a maze. This is fast
//! randomized walk algorithm that takes the concepts of the Wilson's algorithm and inverts them.
//! Instead of starting with a random path square and seeking to find it with a random walk from
//! another point in the maze, we perform a random walk while building walls. Because the maze
//! has a perimeter of walls, we will find another wall square quickly.
//!
//! Even though this algorithm is completely randomized, and thus has the potential to take a long
//! time, in practice it is one of the faster algorithm in the collection and produces some of the
//! most visually pleasing mazes possible.
const std = @import("std");

const gen = @import("../generator.zig");
const maze = @import("../maze.zig");

/// Bit to help detect loops during random walks.
const walk_bit: maze.Square = 0b0100_0000_0000_0000;

/// A loop is found during a random walk when we encounter a square we previously used as a step.
/// Loops must be erased until we return to the point of intersection that caused the loop.
const Loop = struct {
    walk: maze.Point,
    root: maze.Point,
};

/// A RandomWalk helps structure the logic of Wilson's random walking algorithm. To help speed up
/// the algorithm we remember the row from which we should start scanning for a new walk start.
const RandomWalk = struct {
    prev_row_start: isize,
    prev: maze.Point,
    walk: maze.Point,
    next: maze.Point,
};

/// Generates a perfect maze using Wilson's algorithm. This is a wall adding algorithm that connects
/// wall pieces by loop erased random walks. This means the algorithm could take longer if the
/// randomness determines. However, in practice this is a very fast algorithm because we start by
/// connecting walls and there is a perimeter of complete walls around the maze.
pub fn generate(
    m: *maze.Maze,
) !*maze.Maze {
    try gen.buildWallPerimeter(m);
    var randgen = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const rand = randgen.random();
    var cur: RandomWalk = .{
        .prev_row_start = 2,
        .prev = .{ .r = 0, .c = 0 },
        .walk = try gen.randPoint(
            rand,
            .{ 2, m.maze.rows - 2 },
            .{ 2, m.maze.cols - 2 },
            gen.ParityPoint.even,
        ),
        .next = .{ .r = 0, .c = 0 },
    };
    var indices: [4]usize = .{ 0, 1, 2, 3 };
    walking: while (true) {
        m.getPtr(cur.walk.r, cur.walk.c).* |= walk_bit;
        rand.shuffle(usize, &indices);
        choosing_step: for (indices) |i| {
            const p = gen.generator_cardinals[i];
            cur.next = .{
                .r = cur.walk.r + p.r,
                .c = cur.walk.c + p.c,
            };
            if (!isValidStep(m, cur.next, cur.prev)) {
                continue :choosing_step;
            }
            if (!try nextStep(m, &cur)) {
                return m;
            }
            continue :walking;
        }
    }
}

/// Takes the next step of the random walk and one of the following occurs.
///   - The random walk is complete by finding another section of built maze
///   - The random walk finds a loop it must erase.
///   - The random walk takes the next step, building more walls.
/// In the case of finding more maze to connect to the algorithm may finish after this section is
/// built because the maze is complete. In this case null is returned. Otherwise the next RandomWalk
/// state is returned via pointer to the same argument provided.
fn nextStep(
    m: *maze.Maze,
    walk: *RandomWalk,
) !bool {
    if (gen.isBuilt(m, walk.next)) {
        try closeGap(m, walk.walk, walk.next);
        try connectWalk(m, walk.walk);
        if (try gen.choosePointFromRow(m, walk.prev_row_start, gen.ParityPoint.even)) |point| {
            walk.prev_row_start = point.r;
            walk.walk = point;
            m.getPtr(walk.walk.r, walk.walk.c).* &= ~gen.backtrack_mask;
            walk.prev = .{ .r = 0, .c = 0 };
            return true;
        }
        return false;
    }
    if (foundLoop(m, walk.next)) {
        try eraseLoop(m, .{
            .walk = walk.walk,
            .root = walk.next,
        });
        walk.walk = walk.next;
        const dir = backtrackPoint(m, walk.walk);
        walk.prev = .{
            .r = walk.walk.r + dir.r,
            .c = walk.walk.c + dir.c,
        };
        return true;
    }
    try markWall(m, walk);
    walk.prev = walk.walk;
    walk.walk = walk.next;
    return true;
}

/// Erases a loop if encountered during a random walk. The loop is erased all the way back to the
/// point of intersection between the next step and the current walk head.
fn eraseLoop(
    m: *maze.Maze,
    walk: Loop,
) !void {
    var cur = walk;
    while (!std.meta.eql(cur.walk, cur.root)) {
        // Obtain the square and backtracking directions before square cleanup occurs.
        const cur_square = m.get(cur.walk.r, cur.walk.c);
        const half_offset = backtrackHalfPoint(m, cur.walk);
        const full_offset = backtrackPoint(m, cur.walk);
        std.debug.assert(half_offset.r != 0 or half_offset.c != 0);
        const half_step: maze.Point = .{
            .r = cur.walk.r + half_offset.r,
            .c = cur.walk.c + half_offset.c,
        };
        const half_square = m.get(half_step.r, half_step.c);
        try m.build_history.record(.{
            .p = cur.walk,
            .before = cur_square,
            .after = (((cur_square & ~walk_bit) & ~maze.wall_mask) & ~gen.backtrack_mask) |
                maze.path_bit,
            .burst = 1,
        });
        try m.build_history.record(.{
            .p = half_step,
            .before = half_square,
            .after = ((half_square & ~gen.backtrack_mask) & ~maze.wall_mask) | maze.path_bit,
            .burst = 1,
        });
        // Cleanup and backtrack.
        m.getPtr(half_step.r, half_step.c).* = ((half_square & ~gen.backtrack_mask) &
            ~maze.wall_mask) |
            maze.path_bit;
        m.getPtr(cur.walk.r, cur.walk.c).* = (((cur_square & ~walk_bit) & ~maze.wall_mask) &
            ~gen.backtrack_mask) |
            maze.path_bit;
        std.debug.assert(full_offset.r != 0 or full_offset.c != 0);
        cur.walk.r += full_offset.r;
        cur.walk.c += full_offset.c;
    }
}

/// Connects a valid random walk that has found another built section of the maze to connect with.
/// No loop has formed and therefore the randomized walk is valid and connectable.
fn connectWalk(
    m: *maze.Maze,
    walk: maze.Point,
) !void {
    var cur = walk;
    while ((m.get(cur.r, cur.c) & gen.backtrack_mask) != 0) {
        const full_offset = backtrackPoint(m, cur);
        const half_offset = backtrackHalfPoint(m, cur);
        try buildWalkLine(m, cur);
        try buildWalkLine(m, .{
            .r = cur.r + half_offset.r,
            .c = cur.c + half_offset.c,
        });
        cur.r += full_offset.r;
        cur.c += full_offset.c;
    }
    try buildWalkLine(m, cur);
}

/// Marks the wall with the appropriate backtracking marks while building. This should be used when
/// a valid step has been found to progress the random walk. Neither a loop or another part of the
/// built maze has been found so we continue building, leaving backtracking marks for ourselves.
fn markWall(
    m: *maze.Maze,
    this_walk: *const RandomWalk,
) !void {
    var wall = this_walk.walk;
    const next_before = m.get(this_walk.next.r, this_walk.next.c);
    var wall_before: maze.Square = undefined;
    if (this_walk.next.r > this_walk.walk.r) {
        wall.r += 1;
        wall_before = m.get(wall.r, wall.c);
        m.getPtr(wall.r, wall.c).* = (wall_before | gen.from_north) & ~maze.path_bit;
        m.getPtr(this_walk.next.r, this_walk.next.c).* = (next_before | gen.from_north) &
            ~maze.path_bit;
    } else if (this_walk.next.r < this_walk.walk.r) {
        wall.r -= 1;
        wall_before = m.get(wall.r, wall.c);
        m.getPtr(wall.r, wall.c).* = (wall_before | gen.from_south) & ~maze.path_bit;
        m.getPtr(this_walk.next.r, this_walk.next.c).* = (next_before | gen.from_south) &
            ~maze.path_bit;
    } else if (this_walk.next.c < this_walk.walk.c) {
        wall.c -= 1;
        wall_before = m.get(wall.r, wall.c);
        m.getPtr(wall.r, wall.c).* = (wall_before | gen.from_east) & ~maze.path_bit;
        m.getPtr(this_walk.next.r, this_walk.next.c).* = (next_before | gen.from_east) &
            ~maze.path_bit;
    } else if (this_walk.next.c > this_walk.walk.c) {
        wall.c += 1;
        wall_before = m.get(wall.r, wall.c);
        m.getPtr(wall.r, wall.c).* = (wall_before | gen.from_west) & ~maze.path_bit;
        m.getPtr(this_walk.next.r, this_walk.next.c).* = (next_before | gen.from_west) &
            ~maze.path_bit;
    } else {
        return error.nextAndWalkAreEqual;
    }
    try m.build_history.record(.{
        .p = wall,
        .before = wall_before,
        .after = m.get(wall.r, wall.c),
        .burst = 1,
    });
    try m.build_history.record(.{
        .p = this_walk.next,
        .before = next_before,
        .after = m.get(this_walk.next.r, this_walk.next.c),
        .burst = 1,
    });
}

/// The function should be used when a successful random walk is in the building stage and is now
/// connecting the wall section to another built section of the maze. All backtracking marks will
/// be erased and all that will remain is the wall bits indicating the shape the piece takes. All
/// surrounding walls must be updated to indicate a new location of a wall as well.
fn buildWalkLine(
    m: *maze.Maze,
    p: maze.Point,
) !void {
    var wall_changes: [5]maze.Delta = undefined;
    var burst: usize = 1;
    var wall: maze.Square = 0b0;
    const square = m.get(p.r, p.c);
    if (p.r > 0 and m.isWall(p.r - 1, p.c)) {
        const neighbor = m.get(p.r - 1, p.c);
        wall_changes[burst] = .{
            .p = .{
                .r = p.r - 1,
                .c = p.c,
            },
            .before = neighbor,
            .after = (neighbor | maze.south_wall),
            .burst = burst + 1,
        };
        burst += 1;
        m.getPtr(p.r - 1, p.c).* |= maze.south_wall;
        wall |= maze.north_wall;
    }
    if (p.r + 1 < m.maze.rows and m.isWall(p.r + 1, p.c)) {
        const neighbor = m.get(p.r + 1, p.c);
        wall_changes[burst] = .{
            .p = .{
                .r = p.r + 1,
                .c = p.c,
            },
            .before = neighbor,
            .after = (neighbor | maze.north_wall),
            .burst = burst + 1,
        };
        burst += 1;
        m.getPtr(p.r + 1, p.c).* |= maze.north_wall;
        wall |= maze.south_wall;
    }
    if (p.c > 0 and m.isWall(p.r, p.c - 1)) {
        const neighbor = m.get(p.r, p.c - 1);
        wall_changes[burst] = .{
            .p = .{
                .r = p.r,
                .c = p.c - 1,
            },
            .before = neighbor,
            .after = (neighbor | maze.east_wall),
            .burst = burst + 1,
        };
        burst += 1;
        m.getPtr(p.r, p.c - 1).* |= maze.east_wall;
        wall |= maze.west_wall;
    }
    if (p.c + 1 < m.maze.cols and m.isWall(p.r, p.c + 1)) {
        const neighbor = m.get(p.r, p.c + 1);
        wall_changes[burst] = .{
            .p = .{
                .r = p.r,
                .c = p.c + 1,
            },
            .before = neighbor,
            .after = (neighbor | maze.west_wall),
            .burst = burst + 1,
        };
        burst += 1;
        m.getPtr(p.r, p.c + 1).* |= maze.west_wall;
        wall |= maze.east_wall;
    }
    wall_changes[0] = .{
        .p = p,
        .before = square,
        .after = (((square | wall | gen.builder_bit) & ~maze.path_bit) &
            ~walk_bit) &
            ~gen.backtrack_mask,
        .burst = burst,
    };
    m.getPtr(p.r, p.c).* = (((square | wall | gen.builder_bit) & ~maze.path_bit) &
        ~walk_bit) &
        ~gen.backtrack_mask;
    try m.build_history.recordBurst(wall_changes[0..burst]);
}

/// Closes the gap between cur and next by building a wall line.
fn closeGap(
    m: *maze.Maze,
    cur: maze.Point,
    next: maze.Point,
) !void {
    var wall = cur;
    if (next.r < cur.r) {
        wall.r -= 1;
    } else if (next.r > cur.r) {
        wall.r += 1;
    } else if (next.c < cur.c) {
        wall.c -= 1;
    } else if (next.c > cur.c) {
        wall.c += 1;
    } else {
        return error.CurAndNextAreEqual;
    }
    try buildWalkLine(m, wall);
}

/// Returns true if the next step we want to take in the random walk is not a loop and is valid.
fn isValidStep(
    m: *const maze.Maze,
    next: maze.Point,
    prev: maze.Point,
) bool {
    return (next.r >= 0) and
        (next.r < m.maze.rows) and
        (next.c >= 0) and
        (next.c < m.maze.cols) and
        (!std.meta.eql(next, prev));
}

/// Return a reference to the appropriate backtrack offset point from the given square.
fn backtrackPoint(
    m: *const maze.Maze,
    walk: maze.Point,
) *const maze.Point {
    const i = (m.get(walk.r, walk.c) & gen.backtrack_mask);
    return &gen.backtracking_points[i];
}

/// Return a reference to the appropriate backtrack half step offset point from the given square.
fn backtrackHalfPoint(
    m: *const maze.Maze,
    walk: maze.Point,
) *const maze.Point {
    const i = (m.get(walk.r, walk.c) & gen.backtrack_mask);
    return &gen.backtracking_half_points[i];
}

/// Returns true if the current square has been encountered earlier during the random walk.
fn foundLoop(
    m: *const maze.Maze,
    p: maze.Point,
) bool {
    return (m.get(p.r, p.c) & walk_bit) != 0;
}
