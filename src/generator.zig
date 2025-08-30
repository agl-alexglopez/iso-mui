//! The generator module is responsible for providing the core maze building utilities. The goal
//! is for the constants, types, and/or functions offered here to be the bare minimum that maze
//! building algorithms would need to implement their own functionality.
//!
//! Maze building algorithms can be divided into two major categories.
//!
//! 1. Path carving algorithms start with a maze that is completely filled with walls, and then it
//!    carves out the paths.
//! 2. Wall adder algorithms start with only an outline of the perimeter wall. All squares within
//!    this perimeter are paths. The algorithm then builds and connects wall pieces.
//!
//! Therefore, this module should offer utilities for both types of algorithm, while not getting
//! too specific to any builder. For example, while it might be easy to assume that recursive
//! backtracking maze builders are the only type that uses backtracking, actually Wilson's algorithm
//! for generating mazes makes great use of backtracking during its random walks.
const std = @import("std");

const maze = @import("maze.zig");

/// Any builders that choose to cache seen squares in place can use this bit.
pub const builder_bit: maze.Square = 0b0001_0000_0000_0000_0000_0000_0000_0000;
/// The number of cardinal directions in a square grid.
pub const num_directions: usize = 4;
/// The mask we can use for backtracking markers.
pub const backtrack_mask: maze.Square = 0b1111;
/// The bit value for indicating return North.
pub const from_north: maze.Square = 0b0001;
/// The bit value for indicating return East.
pub const from_east: maze.Square = 0b0010;
/// The bit value for indicating return South.
pub const from_south: maze.Square = 0b0011;
/// The bit value for indicating return West.
pub const from_west: maze.Square = 0b0100;

/// While generating mazes we operate in steps of two so offsets are in steps of 2
pub const generator_cardinals: [4]maze.Point = .{
    .{ .r = -2, .c = 0 }, // North
    .{ .r = 0, .c = 2 }, // East
    .{ .r = 2, .c = 0 }, // South
    .{ .r = 0, .c = -2 }, // West
};

/// Building works in steps of two so we need to backtrack by this amount.
pub const backtracking_points: [5]maze.Point = .{
    .{ .r = 0, .c = 0 },
    .{ .r = -2, .c = 0 },
    .{ .r = 0, .c = 2 },
    .{ .r = 2, .c = 0 },
    .{ .r = 0, .c = -2 },
};

/// For display purposes we may use single steps while building.
pub const backtracking_half_points: [5]maze.Point = .{
    .{ .r = 0, .c = 0 },
    .{ .r = -1, .c = 0 },
    .{ .r = 0, .c = 1 },
    .{ .r = 1, .c = 0 },
    .{ .r = 0, .c = -1 },
};

pub const ParityPoint = enum(usize) {
    odd = 1,
    even = 2,
};

/// Returns a random point within the inclusive ranges `[row_start, ro_inclusive_end]` and
/// `[col_start, col_inclusive_end]`. The point will also be even or odd according to parity arg.
pub fn randPoint(
    /// [in] The random generator that is already initialized.
    rand: std.Random,
    /// [in] The inclusive range [start, end] for valid row values.
    row_range: struct { isize, isize },
    /// [in] The inclusive range [start, end] for valid column values.
    col_range: struct { isize, isize },
    /// [in] The desired parity of the random result, even or odd.
    parity: ParityPoint,
) !maze.Point {
    if ((row_range[0] >= row_range[1]) or (col_range[0] >= col_range[1])) {
        return maze.MazeError.LogicFail;
    }
    return .{
        .r = 2 * (@divTrunc(rand.intRangeAtMost(isize, row_range[0], row_range[1]), 2)) +
            @as(isize, @intCast(@intFromEnum(parity) % 2)),
        .c = 2 * (@divTrunc(rand.intRangeAtMost(isize, col_range[0], col_range[1]), 2)) +
            @as(isize, @intCast(@intFromEnum(parity) % 2)),
    };
}

/// Returns true if the maze is already been processed by a building algorithm.
pub fn isBuilt(
    /// [in] The read only pointer to the maze.
    m: *const maze.Maze,
    /// [in] The point in the maze to check. Checked in debug.
    p: maze.Point,
) bool {
    return (m.get(p.r, p.c) & builder_bit) != 0;
}

/// Chooses an un-built point from the current starting row and returns it. The point may be odd
/// or even as specified by the parity. The parity much match that of the starting row.
pub fn choosePointFromRow(
    /// [in] The read only pointer to the maze.
    m: *const maze.Maze,
    /// [in] The starting row position.
    start_row: isize,
    /// [in] The desired parity for steps, must match parity of starting input as a safety check.
    parity: ParityPoint,
) !?maze.Point {
    std.debug.assert(start_row >= 0);
    if (@mod(start_row, 2) != (@intFromEnum(parity) % 2)) {
        return maze.MazeError.LogicFail;
    }
    var r: isize = @intCast(start_row);
    while (r < m.maze.rows - 1) : (r += 2) {
        var c: isize = @intCast(@intFromEnum(parity));
        while (c < m.maze.cols - 1) : (c += 2) {
            if (!isBuilt(m, .{ .r = r, .c = c })) {
                return .{ .r = r, .c = c };
            }
        }
    }
    return null;
}

pub fn hasBacktracking(square: maze.Square) bool {
    return (square & backtrack_mask) != 0;
}

/// Returns true if the maze allows a square to be built on point next. It must be within the maze
/// perimeter and not already built by the algorithm in prior exploration.
pub fn canBuildNewSquare(
    /// [in] The read only pointer to the maze.
    m: *const maze.Maze,
    /// [in] The next point we wish to build at.
    next: maze.Point,
) bool {
    return next.r > 0 and
        next.r < m.maze.rows - 1 and
        next.c > 0 and
        next.c < m.maze.cols - 1 and
        (m.get(next.r, next.c) & builder_bit) == 0;
}

/// Prepares the maze for a path carving algorithm. All squares will become walls. Because the
/// history of this action must be recorded in the maze Tape, allocation may fail.
pub fn fillMazeWithWalls(
    m: *maze.Maze,
) !void {
    for (0..@intCast(m.maze.rows)) |r| {
        for (0..@intCast(m.maze.cols)) |c| {
            try buildWall(m, .{ .r = @intCast(r), .c = @intCast(c) });
        }
    }
    const burst: usize = @intCast(m.maze.rows * m.maze.cols);
    m.build_history.deltas.items[0].burst = burst;
    m.build_history.deltas.items[burst - 1].burst = burst;
}

/// Builds a perimeter wall around the outside of the maze. All Squares within are paths.
pub fn buildWallPerimeter(
    m: *maze.Maze,
) !void {
    var burst: usize = 0;
    for (0..@intCast(m.maze.rows)) |r| {
        for (0..@intCast(m.maze.cols)) |c| {
            if ((c == 0) or (c == m.maze.cols - 1) or (r == 0) or (r == m.maze.rows - 1)) {
                m.getPtr(@intCast(r), @intCast(c)).* |= builder_bit;
                burst += try buildPerimeterPiece(m, .{ .r = @intCast(r), .c = @intCast(c) });
            } else {
                burst += try buildPath(m, .{ .r = @intCast(r), .c = @intCast(c) });
            }
        }
    }
    m.build_history.deltas.items[0].burst = burst;
    m.build_history.deltas.items[burst - 1].burst = burst;
}

/// Builds a wall at Point p. The Point must check its surrounding squares in cardinal directions
/// to decide what shape it should take and how to connect to others. The history is recorded in
/// the Tape and so allocation may fail.
pub fn buildWall(
    m: *maze.Maze,
    p: maze.Point,
) !void {
    var wall: maze.Square = 0b0;
    if (p.r > 0) {
        wall |= maze.north_wall;
    }
    if (p.r + 1 < m.maze.rows) {
        wall |= maze.south_wall;
    }
    if (p.c > 0) {
        wall |= maze.west_wall;
    }
    if (p.c + 1 < m.maze.cols) {
        wall |= maze.east_wall;
    }
    try m.build_history.record(.{
        .p = p,
        .before = 0b0,
        .after = wall,
        .burst = 1,
    });
    m.getPtr(p.r, p.c).* = wall;
}

pub fn buildPerimeterPiece(
    m: *maze.Maze,
    p: maze.Point,
) !usize {
    var deltas: [5]maze.Delta = undefined;
    var burst: usize = 1;
    var wall: maze.Square = 0b0;
    if (p.r > 0 and m.isWall(p.r - 1, p.c)) {
        const square = m.get(p.r - 1, p.c);
        deltas[burst] = .{
            .p = .{
                .r = p.r - 1,
                .c = p.c,
            },
            .before = square,
            .after = square | maze.south_wall,
            .burst = 1,
        };
        burst += 1;
        wall |= maze.north_wall;
        m.getPtr(p.r - 1, p.c).* |= maze.south_wall;
    }
    if (p.r + 1 < m.maze.rows and m.isWall(p.r + 1, p.c)) {
        const square = m.get(p.r + 1, p.c);
        deltas[burst] = .{
            .p = .{
                .r = p.r + 1,
                .c = p.c,
            },
            .before = square,
            .after = square | maze.north_wall,
            .burst = 1,
        };
        burst += 1;
        wall |= maze.south_wall;
        m.getPtr(p.r + 1, p.c).* |= maze.north_wall;
    }
    if (p.c > 0 and m.isWall(p.r, p.c - 1)) {
        const square = m.get(p.r, p.c - 1);
        deltas[burst] = .{
            .p = .{
                .r = p.r,
                .c = p.c - 1,
            },
            .before = square,
            .after = square | maze.east_wall,
            .burst = 1,
        };
        burst += 1;
        wall |= maze.west_wall;
        m.getPtr(p.r, p.c - 1).* |= maze.east_wall;
    }
    if (p.c + 1 < m.maze.cols and m.isWall(p.r, p.c + 1)) {
        const square = m.get(p.r, p.c + 1);
        deltas[burst] = .{
            .p = .{
                .r = p.r,
                .c = p.c + 1,
            },
            .before = square,
            .after = square | maze.west_wall,
            .burst = 1,
        };
        burst += 1;
        wall |= maze.east_wall;
        m.getPtr(p.r, p.c + 1).* |= maze.west_wall;
    }
    const before: maze.Square = m.get(p.r, p.c);
    deltas[0] = .{
        .p = p,
        .before = before,
        .after = before | wall,
        .burst = burst,
    };
    deltas[burst - 1].burst = burst;
    m.getPtr(p.r, p.c).* |= (before & ~maze.path_bit) | wall;
    try m.build_history.recordBurst(deltas[0..burst]);
    return burst;
}

/// Builds a path at point p, recording the history. To build a path, the current square must be
/// changed and surrounding squares must be notified a neighboring wall no longer exists. Allocation
/// may fail while recording the history.
pub fn buildPath(
    m: *maze.Maze,
    p: maze.Point,
) !usize {
    var wall_changes: [5]maze.Delta = undefined;
    var burst: usize = 1;
    var square = m.get(p.r, p.c);
    wall_changes[0] = .{
        .p = p,
        .before = square,
        .after = (square & ~maze.wall_mask) | maze.path_bit,
        .burst = burst,
    };
    m.getPtr(p.r, p.c).* = wall_changes[0].after;
    if (p.r > 0) {
        square = m.get(p.r - 1, p.c);
        wall_changes[burst] = .{
            .p = .{ .r = p.r - 1, .c = p.c },
            .before = square,
            .after = square & ~maze.south_wall,
            .burst = burst + 1,
        };
        m.getPtr(p.r - 1, p.c).* = wall_changes[burst].after;
        burst += 1;
    }
    if (p.r + 1 < m.maze.rows) {
        square = m.get(p.r + 1, p.c);
        wall_changes[burst] = .{
            .p = .{ .r = p.r + 1, .c = p.c },
            .before = square,
            .after = square & ~maze.north_wall,
            .burst = burst + 1,
        };
        m.getPtr(p.r + 1, p.c).* = wall_changes[burst].after;
        burst += 1;
    }
    if (p.c > 0) {
        square = m.get(p.r, p.c - 1);
        wall_changes[burst] = .{
            .p = .{ .r = p.r, .c = p.c - 1 },
            .before = square,
            .after = square & ~maze.east_wall,
            .burst = burst + 1,
        };
        m.getPtr(p.r, p.c - 1).* = wall_changes[burst].after;
        burst += 1;
    }
    if (p.c + 1 < m.maze.cols) {
        square = m.get(p.r, p.c + 1);
        wall_changes[burst] = .{
            .p = .{ .r = p.r, .c = p.c + 1 },
            .before = square,
            .after = square & ~maze.west_wall,
            .burst = burst + 1,
        };
        m.getPtr(p.r, p.c + 1).* = wall_changes[burst].after;
        burst += 1;
    }
    wall_changes[0].burst = burst;
    try m.build_history.recordBurst(wall_changes[0..burst]);
    return burst;
}

/// Carves the wall Square to become a path for backtracking. The current square records what
/// direction it came from and also updates surrounding walls of a new path Square. History is
/// recorded so allocation may fail.
pub fn carveBacktrackSquare(
    m: *maze.Maze,
    p: maze.Point,
    backtrack: maze.Square,
) maze.MazeError!void {
    var wall_changes: [5]maze.Delta = undefined;
    var burst: usize = 1;
    const before = m.get(p.r, p.c);
    wall_changes[0] = .{
        .p = p,
        .before = before,
        .after = (before & ~maze.wall_mask) | maze.path_bit | builder_bit | backtrack,
        .burst = burst,
    };
    m.getPtr(p.r, p.c).* = wall_changes[0].after;
    if (p.r > 0) {
        const square = m.get(p.r - 1, p.c);
        wall_changes[burst] = .{
            .p = .{
                .r = p.r - 1,
                .c = p.c,
            },
            .before = square,
            .after = square & ~maze.south_wall,
            .burst = burst + 1,
        };
        m.getPtr(p.r - 1, p.c).* = wall_changes[burst].after;
        burst += 1;
    }
    if (p.r < m.maze.rows) {
        const square = m.get(p.r + 1, p.c);
        wall_changes[burst] = .{
            .p = .{
                .r = p.r + 1,
                .c = p.c,
            },
            .before = square,
            .after = square & ~maze.north_wall,
            .burst = burst + 1,
        };
        m.getPtr(p.r + 1, p.c).* = wall_changes[burst].after;
        burst += 1;
    }
    if (p.c > 0) {
        const square = m.get(p.r, p.c - 1);
        wall_changes[burst] = .{
            .p = .{
                .r = p.r,
                .c = p.c - 1,
            },
            .before = square,
            .after = square & ~maze.east_wall,
            .burst = burst + 1,
        };
        m.getPtr(p.r, p.c - 1).* = wall_changes[burst].after;
        burst += 1;
    }
    if (p.c < m.maze.cols) {
        const square = m.get(p.r, p.c + 1);
        wall_changes[burst] = .{
            .p = .{
                .r = p.r,
                .c = p.c + 1,
            },
            .before = square,
            .after = square & ~maze.west_wall,
            .burst = burst + 1,
        };
        m.getPtr(p.r, p.c + 1).* = wall_changes[burst].after;
        burst += 1;
    }
    wall_changes[0].burst = burst;
    try m.build_history.recordBurst(wall_changes[0..burst]);
}

/// Records the intended progress of the backtracking path from current to next. We progress the
/// path by building from cur to next but leave backtracking marks leading from next to cur. Because
/// we record this history allocation may fail. Assumes cur and next are not equal and returns
/// an error if this is not the case.
pub fn recordBacktrackPath(
    m: *maze.Maze,
    cur: maze.Point,
    next: maze.Point,
) maze.MazeError!void {
    try carveBacktrackSquare(m, cur, m.get(cur.r, cur.c) & backtrack_mask);
    var wall = cur;
    var backtracking: maze.Square = 0;
    if (next.r < cur.r) {
        wall.r -= 1;
        backtracking = from_south;
    } else if (next.r > cur.r) {
        wall.r += 1;
        backtracking = from_north;
    } else if (next.c < cur.c) {
        wall.c -= 1;
        backtracking = from_east;
    } else if (next.c > cur.c) {
        wall.c += 1;
        backtracking = from_west;
    } else {
        return maze.MazeError.LogicFail;
    }
    try carveBacktrackSquare(m, wall, backtracking);
    try carveBacktrackSquare(m, next, backtracking);
}

/// Gets a string representation of a maze square. Right now only path or wall for debug print.
pub fn getSquare(
    s: maze.Square,
) [:0]const u8 {
    if ((s & maze.path_bit) == 0) {
        return maze.wallPiece(s);
    } else {
        return " ";
    }
}
