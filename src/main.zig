/// Standard library stuff.
const std = @import("std");

/// Raylib stuff.
const rl = @import("raylib");

/// Maze stuff.
const maze = @import("maze.zig");
const rdfs = @import("builders/rdfs.zig");
const wilson = @import("builders/wilson_adder.zig");
const gen = @import("generator.zig");

const asset_path: [:0]const u8 = "assets/";
const wall_atlas_image_path: [:0]const u8 = asset_path ++ "maze_walls.png";

const row_flag: []const u8 = "-r=";
const col_flag: []const u8 = "-c=";

// Image Loader Helpers

/// A type for modeling anything that needs and x and y position, coordinate, or size. In graphics
/// X is the starting horizontal coordinate at (0, 0) then increasing to the right. The Y is the
/// coordinate starting at (0, 0) then growing downward meaning it increments.
///  0->(X)
///  |
///  V
/// (Y)
const Xy = struct {
    x: i32,
    y: i32,
};

/// Number of pixels used for x dimension of wall square.
const cell_pixels = Xy{ .x = 32, .y = 32 };
const atlas_pixels = Xy{ .x = 128, .y = 128 };
const atlas_cols = 4;
const atlas_rows = 4;

const Args = struct {
    rows: isize = 20,
    cols: isize = 20,

    /// Helper to set fields of the argument struct.
    const Set = enum {
        r,
        c,
    };

    /// Attempts to set the field as specified according to arg input.
    pub fn set(
        /// [in] A reference to self to modify the row or col field.
        self: *Args,
        /// [in] The field to set.
        field: Set,
        /// [in] The string input. Assumes it is clean from any characters other than digits.
        arg: []const u8,
    ) !void {
        const conversion = try std.fmt.parseInt(isize, arg, 10);
        switch (field) {
            Set.r => self.rows = conversion,
            Set.c => self.cols = conversion,
        }
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var maze_args = Args{};
    const allocator = arena.allocator();
    for (std.os.argv[1..]) |a| {
        const arg = std.mem.span(a);
        if (std.mem.startsWith(u8, arg, row_flag)) {
            try maze_args.set(Args.Set.r, arg[row_flag.len..]);
        } else if (std.mem.startsWith(u8, arg, col_flag)) {
            try maze_args.set(Args.Set.c, arg[col_flag.len..]);
        } else {
            return error.UnrecognizedCommandLineArgument;
        }
    }
    var labyrinth: maze.Maze = try maze.Maze.init(allocator, maze_args.rows, maze_args.cols);
    defer {
        labyrinth.deinit(allocator);
        arena.deinit();
    }
    _ = try wilson.generate(&labyrinth);

    // Initialization
    //--------------------------------------------------------------------------------------
    const screen_width = 1440;
    const screen_height = 1080;

    rl.initWindow(screen_width, screen_height, "zig-zag-mui");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Every possible wall shape possible for a maze has been stored in a 128x128 square where
    // each wall shape occupies a 32x32 section. Because we encode the shape of walls into the
    // bits of our maze squares, we simply grab those bits and index into the appropriate shape
    // square in our grid. The only tricky part is we have columns of length 4 so we need to modulo
    // both the row and column value.
    const wall_atlas_lookup_grid: rl.Texture2D = try rl.loadTexture(wall_atlas_image_path);

    // Main game loop
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);
        // Draw entire maze every frame.
        {
            var r_pixel: f32 = 0.0;
            var r: isize = 0;
            while (r < labyrinth.maze.rows) : ({
                r += 1;
                r_pixel += cell_pixels.y;
            }) {
                var c_pixel: f32 = 0.0;
                var c: isize = 0;
                while (c < labyrinth.maze.cols) : ({
                    c += 1;
                    c_pixel += cell_pixels.x;
                }) {
                    if (labyrinth.isPath(r, c)) {
                        continue;
                    }
                    const square_bits: maze.Square = labyrinth.get(@intCast(r), @intCast(c));
                    const wall_index: i32 = @intCast((square_bits & maze.wall_mask) >> maze.wall_shift);
                    const wall_square_pixel_coordinates = Xy{
                        .x = @mod(wall_index, atlas_cols) * atlas_pixels.x,
                        .y = @divFloor(wall_index, atlas_rows) * atlas_pixels.y,
                    };
                    rl.drawTexturePro(
                        wall_atlas_lookup_grid,
                        rl.Rectangle{
                            .x = @floatFromInt(wall_square_pixel_coordinates.x),
                            .y = @floatFromInt(wall_square_pixel_coordinates.y),
                            .width = @floatFromInt(cell_pixels.x),
                            .height = @floatFromInt(cell_pixels.y),
                        },
                        rl.Rectangle{
                            .x = c_pixel * 0.5,
                            .y = r_pixel * 0.5,
                            .width = cell_pixels.x / 2,
                            .height = cell_pixels.y / 2,
                        },
                        rl.Vector2{
                            .x = 0,
                            .y = 0,
                        },
                        0.0,
                        .ray_white,
                    );
                }
            }
        }
    }
}
