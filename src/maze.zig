//! This module provides the core type and structure of a maze square. The main goal is to provide
//! the wall pieces and some fundamental helper this is functions such that the builder and solver
//! can perform their tasks more easily.
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const expect = std.testing.expect;

/// A Square is the fundamental maze cell type. It has 32 bits available for various building and
/// solving logic that other modules can apply.
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

////////////////////////////////////////    Constants    //////////////////////////////////////////

/// While building and solving allocation of memory may fail or an impossible logical state may be
/// reached. In either case the error should be returned.
pub const MazeError = error{ AllocFail, LogicFail };
/// The bit that signifies this is a navigable path.
pub const path_bit: Square = 0x20000000;
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
/// The wall array provides us with information about what shape the current square should take for
/// its wall connections. If the square is a wall then it must specify in what directions exist
/// other walls. The character it chooses is the one that connects it to neighboring squares that
/// are also walls.
///
/// Use the north, east, south, and west wall bits to add or remove connections from a maze square
/// as the neighboring walls are built or destroyed. This table has all 16 possible combinations of
/// wall shapes covered and therefore by masking and obtaining the wall bits from a square we can
/// index into this table with those bits and print the correct character.
pub const walls = [16][:0]const u8{
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

/// Helper for iteration patterns that involve checking all surrounding maze squares during building
/// and solving algorithms. Because we use signed points we can simply add offsets to our current
/// position to go north, east, south, and west.
///
/// ```zig
/// cur: Point = .{ .r = row, .c = col };
/// next: Point = .{
///     .r = cur.r + cardinal_directions[i].r,
///     .c = cur.c + cardinal_directions[i].c,
/// };
/// ```
///
/// Notice, this way we do not care about moving in a positive or negative direction for either the
/// row or column.
pub const cardinal_directions = [4]Point{
    .{ .r = -1, .c = 0 },
    .{ .r = 0, .c = 1 },
    .{ .r = 1, .c = 0 },
    .{ .r = 0, .c = -1 },
};

/////////////////////////////////////////     Types      //////////////////////////////////////////

/// The Blueprint allocates all squares at once based on arguments provided. Because we only need
/// to know the number of squares once, we can allocate them all as a slice and deallocate them at
/// the end of the program. The slice is one dimensional. Therefore row by column access should use
/// multiplication such as `row * cols + col`.
pub const Blueprint = struct {
    squares: []Square,
    rows: isize,
    cols: isize,

    pub fn init(
        allocator: Allocator,
        r: isize,
        c: isize,
    ) !Blueprint {
        const ret = Blueprint{
            .squares = try allocator.alloc(Square, @intCast(r * c)),
            .rows = r,
            .cols = c,
        };
        for (ret.squares) |*s| {
            s.* = 0;
        }
        return ret;
    }

    pub fn deinit(
        self: *Blueprint,
        allocator: Allocator,
    ) void {
        allocator.free(self.squares);
        self.* = undefined;
    }
};

/// The Point is a simple helper to navigate squares in the maze. The fields are signed because this
/// allows for cleaner iterator patterns that check all surrounding squares as offsets from the
/// current Square.
pub const Point = struct {
    r: isize,
    c: isize,
};

/// A Delta provides a before and after snapshot of a Square. If placed in a Tape it becomes
/// possible to replay the changes forward and back. A burst can be used if many changes should
/// occur across squares simultaneously.
pub const Delta = struct {
    p: Point,
    before: Square,
    after: Square,
    burst: usize,
};

/// A Tape is used to record the history of a maze building or solving algorithm over the course of
/// the program. We can record Deltas as snapshots of our changes. By recording these simple Deltas
/// we can play the maze algorithms forward or in reverse in whatever format we please. The
/// algorithms can also be stepped through for better understanding after we record the history.
pub const Tape = struct {
    deltas: std.array_list.Managed(Delta),
    i: usize,

    /// A Tape uses a dynamic storage method for Deltas so needs an allocator.
    fn init(
        allocator: Allocator,
    ) Tape {
        return Tape{
            .deltas = std.array_list.Managed(Delta).init(allocator),
            .i = 0,
        };
    }

    /// Free the storage of Delta snapshots.
    fn deinit(
        self: *Tape,
    ) void {
        self.deltas.deinit();
        self.* = undefined;
    }

    fn clear(self: *Tape) void {
        self.deltas.clearRetainingCapacity();
        self.i = 0;
    }

    /// Records the requested delta to the back of the tape. This may allocate and can fail.
    pub fn record(
        self: *Tape,
        delta: Delta,
    ) MazeError!void {
        _ = self.deltas.append(delta) catch return MazeError.AllocFail;
    }

    /// Record a burst of deltas that correspond to a series of changes in squares that should
    /// occur at the same time. This function allocates and may fail.
    pub fn recordBurst(
        self: *Tape,
        burst: []const Delta,
    ) MazeError!void {
        if (self.deltas.items.len != 0 and
            ((burst[0].burst != burst.len) or
                (burst[burst.len - 1].burst != burst.len)))
        {
            return MazeError.LogicFail;
        }
        _ = self.deltas.appendSlice(burst) catch return MazeError.AllocFail;
    }
};

/// A Maze contains the core array of maze Squares and Tapes for the builders and solvers. The
/// builders and solvers may record their actions on the maze as Deltas that occur over time on maze
/// Squares. How the builders, solvers, and display code interprets these Deltas over the maze
/// Squares is not a concern of this type. It simply provides the types needed.
pub const Maze = struct {
    /// The core maze array with row and columns specification.
    maze: Blueprint,
    build_history: Tape,
    solve_history: Tape,

    /// Initialize the maze with an allocator and desired rows and columns. Rows and columns may be
    /// incremented for display purposes. The maze Square  array and Tape types require allocation.
    pub fn init(
        allocator: Allocator,
        rows: isize,
        cols: isize,
    ) !Maze {
        const set_rows = (rows + 1) - @mod(rows, 2);
        const set_cols = (cols + 1) - @mod(cols, 2);
        return Maze{
            .maze = try Blueprint.init(allocator, set_rows, set_cols),
            .build_history = Tape.init(allocator),
            .solve_history = Tape.init(allocator),
        };
    }

    /// Destroy the maze and Tapes stored with it.
    pub fn deinit(
        self: *Maze,
        allocator: Allocator,
    ) void {
        self.maze.deinit(allocator);
        self.build_history.deinit();
        self.solve_history.deinit();
        self.* = undefined;
    }

    /// Clears the maze of any Square state and zeros all rows and columns. The build and solve
    /// history are also cleared and reset to 0 while maintaining their capacity. This function
    /// does not free any memory.
    pub fn clearRetainingDimensions(self: *Maze) void {
        for (self.maze.squares) |*s| {
            s.* = 0;
        }
        self.build_history.clear();
        self.solve_history.clear();
    }

    /// Return a copy of the Square at the desired row and column. Assumes the row and column access
    /// is within maze bounds.
    pub fn get(
        self: *const Maze,
        row: isize,
        col: isize,
    ) Square {
        assert(row >= 0 and col >= 0 and row < self.maze.rows and col < self.maze.cols);
        return self.maze.squares[@intCast((row * self.maze.cols) + col)];
    }

    /// Return a pointer to the Square at the desired row and column. Assumes the row and column
    /// access is within maze bounds.
    pub fn getPtr(
        self: *const Maze,
        row: isize,
        col: isize,
    ) *Square {
        assert(row >= 0 and col >= 0 and row < self.maze.rows and col < self.maze.cols);
        return &self.maze.squares[@intCast((row * self.maze.cols) + col)];
    }

    /// Returns true if the path bit is off at the specified coordinates, making the square a wall.
    /// Assumes the row and column access is within maze bounds.
    pub fn isWall(
        self: *const Maze,
        row: isize,
        col: isize,
    ) bool {
        assert(row >= 0 and col >= 0 and row < self.maze.rows and col < self.maze.cols);
        return (self.maze.squares[@intCast((row * self.maze.cols) + col)] & path_bit) == 0;
    }

    /// Returns true if the path bit is off at the specified coordinates, making the square a path.
    /// Assumes the row and column access is within maze bounds.
    pub fn isPath(
        self: *const Maze,
        row: isize,
        col: isize,
    ) bool {
        assert(row >= 0 and col >= 0 and row < self.maze.rows and col < self.maze.cols);
        return (self.maze.squares[@intCast((row * self.maze.cols) + col)] & path_bit) != 0;
    }
};

/////////////////////////////////////    Module Functions    //////////////////////////////////////

/// Returns the Unicode box drawing character representing the current wall piece as a string.
/// Provide the square as is with no shifts or modifications. Assumes the square is a wall.
pub fn wallPiece(
    square: Square,
) [:0]const u8 {
    return walls[((square & wall_mask) >> wall_shift)];
}

pub fn isPath(
    square: Square,
) bool {
    return (square & path_bit) != 0;
}

/////////////////////////////////////    Tests     ////////////////////////////////////////////////

test "maze square flat 2D buffer multiplication getters" {
    var buf: [128]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    var maze: Maze = try Maze.init(allocator, 5, 5);
    defer {
        maze.deinit(allocator);
    }
    maze.getPtr(3, 3).* = 0;
    try expect(maze.get(3, 3) == 0);
    maze.getPtr(3, 3).* = east_wall | west_wall;
    try expect(maze.get(3, 3) == east_wall | west_wall);
}
