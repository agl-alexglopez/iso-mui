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
    .{ .r = 0, .c = 2 }, // West
    .{ .r = 2, .c = 0 }, // South
    .{ .r = 0, .c = -2 }, // East
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

pub fn canBuildNewSquare(m: *const maze.Maze, next: maze.Point) bool {
    return next.r > 0 and
        next.r < m.maze.rows - 1 and
        next.c > 0 and
        next.c < m.maze.cols - 1 and
        (m.get(next.r, next.c) & builder_bit) == 0;
}

pub fn fillMazeWithWalls(m: *maze.Maze) !void {
    for (0..@intCast(m.maze.rows)) |r| {
        for (0..@intCast(m.maze.cols)) |c| {
            try buildWall(m, .{ .r = @intCast(r), .c = @intCast(c) });
        }
    }
}

pub fn buildWall(m: *maze.Maze, p: maze.Point) !void {
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

pub fn buildPath(m: *maze.Maze, p: maze.Point) usize {
    var wall_changes: [5]maze.Delta = .{};
    var burst = 1;
    var square = m.get(p.row, p.col);
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
    m.build_history.recordBurst(wall_changes[0..burst]);
    return burst;
}

pub fn carveWall(m: *maze.Maze, p: maze.Point, backtrack: maze.Square) !void {
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

pub fn recordPath(m: *maze.Maze, cur: maze.Point, next: maze.Point) !void {
    try carveWall(m, cur, m.get(cur.r, cur.c) & backtrack_mask);
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
        return error.WallBreakError;
    }
    try carveWall(m, wall, backtracking);
    try carveWall(m, next, backtracking);
}

pub fn getSquare(s: maze.Square) []const u8 {
    if ((s & maze.path_bit) == 0) {
        return maze.wallPiece(s);
    } else {
        return " ";
    }
}
