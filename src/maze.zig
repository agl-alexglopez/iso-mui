//! This module provides the core type and structure of a maze square. The main
//! goal is to provide the wall pieces and some fundamental helper this is
//! functions such that the builder and solver can perform their tasks more
//! easily.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// A Square is the fundamental maze cell type. It has 32 bits available
/// for various building and solving logic that other modules can apply.
/// blue bits────────────────────────────────┬┬┬┬─┬┬┬┐
/// green bits─────────────────────┬┬┬┬─┬┬┬┐ ││││ ││││
/// red bits─────────────┬┬┬┬─┬┬┬┐ ││││ ││││ ││││ ││││
/// walls/threads───┬┬┬┐ ││││ ││││ ││││ ││││ ││││ ││││
/// built bit─────┐ ││││ ││││ ││││ ││││ ││││ ││││ ││││
/// path bit─────┐│ ││││ ││││ ││││ ││││ ││││ ││││ ││││
/// start bit───┐││ ││││ ││││ ││││ ││││ ││││ ││││ ││││
/// finish bit─┐│││ ││││ ││││ ││││ ││││ ││││ ││││ ││││
///          0b0000 0000 0000 0000 0000 0000 0000 0000
pub const Square = u32;

/// The Blueprint allocates all squares at once based on arguments provided.
/// Because we only need to know the number of squares once, we can allocate
/// them all as a slice and deallocate them at the end of the program. The slice
/// is one dimensional. Therefore row by column access should use
/// multiplication such as `row * cols + col`.
pub const Blueprint = struct {
    squares: []Square,
    rows: isize,
    cols: isize,
};

pub const Point = struct {
    r: isize,
    c: isize,
};

pub const Delta = struct {
    p: Point,
    before: Square,
    after: Square,
    burst: usize,
};

pub const Tape = struct {
    deltas: std.ArrayList(Delta),
    i: usize,

    fn init(allocator: Allocator) Tape {
        return Tape{
            .deltas = std.ArrayList(Delta).init(allocator),
            .i = 0,
        };
    }

    fn deinit(self: *Tape) void {
        self.deltas.deinit();
    }
};

pub const Maze = struct {
    maze: Blueprint,
    build_history: Tape,
    solve_history: Tape,

    pub fn init(allocator: Allocator, rows: isize, cols: isize) !Maze {
        return Maze{
            .maze = Blueprint{
                .rows = (rows + 1) - @mod(rows, 2),
                .cols = (cols + 1) - @mod(cols, 2),
                .squares = try allocator.alloc(Square, @intCast(rows * cols)),
            },
            .build_history = Tape.init(allocator),
            .solve_history = Tape.init(allocator),
        };
    }

    pub fn deinit(self: *Maze, allocator: Allocator) void {
        allocator.free(self.maze.squares);
        self.maze.rows = 0;
        self.maze.cols = 0;
        self.build_history.deinit();
        self.solve_history.deinit();
    }
};

/// The bit signifying a wall to the north of the current square exists.
pub const north_wall: Square = 0x1000000;
/// The bit signifying a wall to the east of the current square exists.
pub const east_wall: Square = 0x2000000;
/// The bit signifying a wall to the south of the current square exists.
pub const south_wall: Square = 0x4000000;
/// The bit signifying a wall to the west of the current square exists.
pub const west_wall: Square = 0x8000000;
/// The mask for the bits that index into the proper wall shape.
pub const wall_mask: Square = 0xf000000;
/// The shift to make the wall mask bits 0-index into the table properly.
pub const wall_shift: usize = 24;

/// The wall array provides us with information about what shape the current
/// square should take for its wall connections. If the square is a wall then it
/// must specify in what directions exist other walls. The character it chooses
/// is the one that connects it to neighboring squares that are also walls.
///
/// Use the north, east, south, and west wall bits to add or remove connections
/// from a maze square as the neighboring walls are built or destroyed. This
/// table has all 16 possible combinations of wall shapes covered and therefore
/// by masking and obtaining the wall bits from a square we can index into this
/// table with those bits and print the correct character.
pub const walls = [16][]const u8{
    "■", // 0b0000 walls do not exist around me
    "╵", // 0b0001 wall North
    "╶", // 0b0010 wall East
    "└", // 0b0011 wall North and East
    "╷", // 0b0100 wall South
    "│", // 0b0101 wall North and South
    "┌", // 0b0110 wall East and South
    "├", // 0b0111 wall North, East, and South
    "╴", // 0b1000 wall West
    "┘", // 0b1001 wall North and West
    "─", // 0b1010 wall East and West
    "┴", // 0b1011 wall North, East, and West
    "┐", // 0b1100 wall South and West.
    "┤", // 0b1101 wall North, South, and West
    "┬", // 0b1110 wall East, South, and West
    "┼", // 0b1111 wall North, East, South, and West.
};

/// Helper for iteration patterns that involve checking all surrounding maze
/// squares during building and solving algorithms. Because we use signed points
/// we can simply add offsets to our current position to go north, east, south,
/// and west.
///
/// ```zig
/// cur: Point = .{ .r = row, .c = col };
/// next: Point = .{
///     .r = cur.r + cardinal_directions[i].r,
///     .c = cur.c + cardinal_directions[i].c,
/// };
/// ```
///
/// Notice, this way we do not care about moving in a positive or negative
/// direction for either the row or column.
pub const cardinal_directions = [4]Point{
    .{ .r = -1, .c = 0 },
    .{ .r = 0, .c = 1 },
    .{ .r = 1, .c = 0 },
    .{ .r = 0, .c = -1 },
};

/// Returns the Unicode box drawing character representing the current wall
/// piece as a string. Provide the square as is with no shifts or modifications.
/// Assumes the square is a wall.
pub fn wallPiece(square: Square) []const u8 {
    return walls[((square & wall_mask) >> wall_shift)];
}
