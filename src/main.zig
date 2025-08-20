/// Standard library stuff.
const std = @import("std");

/// Raylib stuff.
const rl = @import("raylib");

/// Maze stuff.
const maze = @import("maze.zig");
const rdfs = @import("builders/rdfs.zig");
const wilson = @import("builders/wilson_adder.zig");
const gen = @import("generator.zig");

const Args = struct {
    rows: isize = 37,
    cols: isize = 137,
};

const row_flag: []const u8 = "-r=";
const col_flag: []const u8 = "-c=";

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var maze_args = Args{};
    const allocator = arena.allocator();
    for (std.os.argv[1..]) |a| {
        const arg = std.mem.span(a);
        if (std.mem.startsWith(u8, arg, row_flag)) {
            const str_rows = arg[row_flag.len..];
            maze_args.rows = try std.fmt.parseInt(isize, str_rows, 10);
        } else if (std.mem.startsWith(u8, arg, col_flag)) {
            const str_cols = arg[row_flag.len..];
            maze_args.cols = try std.fmt.parseInt(isize, str_cols, 10);
        } else {
            return error.UnrecognizedCommandLineArgument;
        }
    }
    var new_maze: maze.Maze = try maze.Maze.init(allocator, maze_args.rows, maze_args.cols);
    defer {
        new_maze.deinit(allocator);
        arena.deinit();
    }
    _ = try wilson.generate(&new_maze);

    // Initialization
    //--------------------------------------------------------------------------------------
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "zig-zag-mui");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);

        rl.drawText("Congrats! You created your first window!", 190, 200, 20, .light_gray);
        //----------------------------------------------------------------------------------
    }
}
