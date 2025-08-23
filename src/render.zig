//! The render module is responsible for interacting with whatever library we wish to use for the
//! gui and render loop. The intention is for this to be a Maze User Interface or (MUI). Most like
//! a game or perhaps interactive application.
//!
//! Currently, we use Raylib for the rendering logic because it seems nice and has pretty good
//! Zig support currently, but having a separate module like this allows us to swap out the render
//! code without affecting main or maze building and solving.
//!
//! The current style of graphics for the maze generator and solver is based on pixel art and uses
//! Aseprite to help illustrate different wall pieces and maybe some animations.
//!
//! At its core a maze is a simple 2D grid we can make some optimizations for how we draw the walls
//! of the maze. Specifically, I created a texture atlas for every possible wall shape we can have
//! in the maze. Because mazes operate in cardinal directions there are exactly 16 different
//! configurations of wall shape. We place those in a 4x4 grid currently of 32x32 pixel squares for
//! a total of 128x128 pixels. Then we use bits in our maze Square types to index into this grid
//! and choose the correct shape that we encoded.
//!
//! As an added bonus, we are able to animate a wide variety of building and solving progressions
//! because we build and solve the mazes before we display anything. We record our work in playback
//! Tape type that records the changes in the bits of our integer maze Square types. We have a huge
//! amount of freedom then to animate this on the render side how we wish, completely separate from
//! maze logic.
const std = @import("std");
const assert = std.debug.assert;

/// Raylib is the graphics driving library for this application. Awesome!
const rl = @import("raylib");

const maze = @import("maze.zig");

/// We will place any texture atlas for any wall styles we want in an asset folder. This is where
/// we should also find solver animations (torch light, explorers, who knows).
const asset_path: [:0]const u8 = "assets/";

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

/// Currently all WallTextureAtlas types help us construct wall shapes for the given maze with pixel
/// art. Every WallTextureAtlas can be discerned from an accompanying *.json and *.png file with the
/// same prefix in the appropriate asset path.
///
/// The only important detail that does not come specified in the json file is the individual square
/// size which we must hand code here.
///
/// One should never alter the size of the atlas map when reading in the squares. Output may be
/// scaled up or down according to preference and graphics library capabilities.
const WallAtlas = struct {
    /// The location of all texture atlas files of *.json and *.png type.
    pub const path: [:0]const u8 = "assets/atlas/";
    /// The total area of the texture atlas grid in pixels.
    pub const area: Xy = .{ .x = 128, .y = 128 };
    /// The area of a single maze wall shape square.
    pub const square: Xy = .{ .x = 32, .y = 32 };
    // The number of rows and columns for a wall texture atlas.
    pub const dimensions: Xy = .{ .x = 4, .y = 4 };
    texture: rl.Texture2D,

    pub fn init(comptime file_name: [:0]const u8) !WallAtlas {
        return WallAtlas{
            .texture = try rl.Texture2D.init(WallAtlas.path ++ file_name),
        };
    }

    pub fn getPixelPoint(square_bits: maze.Square) Xy {
        _ = square_bits;
        // const wall_i: i32 = @intCast((square_bits & maze.wall_mask) >> maze.wall_shift);
        // return Xy{
        //     .x = @mod(wall_i, WallAtlas.dimensions.x) * WallAtlas.square.x,
        //     .y = @divFloor(wall_i, WallAtlas.dimensions.y) * WallAtlas.square.y,
        // };
        return Xy{ .x = 0, .y = 0 };
    }
};

pub const Render = struct {
    walls: WallAtlas,
    virtual_screen: rl.RenderTexture2D,
    real_screen_dimensions: Xy,
    pub fn init(
        m: *const maze.Maze,
        screen_width: i32,
        screen_height: i32,
    ) !Render {
        comptime assert(WallAtlas.area.x >= 0 and WallAtlas.area.y >= 0);
        comptime assert(WallAtlas.square.x >= 0 and WallAtlas.square.y >= 0);
        comptime assert(WallAtlas.dimensions.x >= 0 and WallAtlas.dimensions.y >= 0);
        rl.initWindow(screen_width, screen_height, "zig-zag-mui");
        rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
        const cols: i32 = @intCast(m.maze.cols);
        const rows: i32 = @intCast(m.maze.rows);
        const r = Render{
            .walls = try WallAtlas.init("atlas_maze_walls_isometric.png"),
            .virtual_screen = try rl.RenderTexture2D.init(
                cols * WallAtlas.square.x,
                rows * WallAtlas.square.y,
            ),
            .real_screen_dimensions = Xy{
                .x = screen_width,
                .y = screen_height,
            },
        };
        return r;
    }

    pub fn deinit() void {
        rl.closeWindow();
    }

    pub fn run(
        self: *const Render,
        m: *maze.Maze,
    ) void {
        while (!rl.windowShouldClose()) {
            self.renderMaze(m);
            // Note that if any new textures are loaded the old one must be unloaded here.
        }
    }

    /// Performs pass over maze rendering the current state given the status of the Square bits.
    fn renderMaze(
        self: *const Render,
        m: *const maze.Maze,
    ) void {
        // First, draw the maze as the user has specified to a pixel perfect virtual screen.
        rl.beginTextureMode(self.virtual_screen);
        rl.clearBackground(.black);
        {
            const x_start: i32 = @divTrunc(self.virtual_screen.texture.width, 2) - @divTrunc(WallAtlas.square.x, 2);
            const y_start: i32 = @divTrunc(self.virtual_screen.texture.height, 8);
            var r: isize = 0;
            while (r < m.maze.rows) : (r += 1) {
                var c: isize = 0;
                while (c < m.maze.cols) : (c += 1) {
                    if (m.isPath(r, c)) {
                        continue;
                    }
                    const atlas_square: Xy = WallAtlas.getPixelPoint(m.get(r, c));
                    rl.drawTexturePro(
                        self.walls.texture,
                        rl.Rectangle{
                            .x = @floatFromInt(atlas_square.x),
                            .y = @floatFromInt(atlas_square.y),
                            .width = @floatFromInt(WallAtlas.square.x),
                            .height = @floatFromInt(WallAtlas.square.y),
                        },
                        rl.Rectangle{
                            .x = @floatFromInt(x_start + ((c - r) * @divTrunc(WallAtlas.square.x, 2))),
                            .y = @floatFromInt(y_start + ((c + r) * @divTrunc(WallAtlas.square.y / 2, 2))),
                            .width = @floatFromInt(WallAtlas.square.x),
                            .height = @floatFromInt(WallAtlas.square.y),
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
        rl.endTextureMode();

        // Next, draw virtual pixel perfect maze to screen all at once scaled as we need.
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);
        rl.setTextureFilter(self.virtual_screen.texture, .point);
        rl.drawTexturePro(
            self.virtual_screen.texture,
            rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(self.virtual_screen.texture.width),
                // Don't forget to flip the virtual screen source due to OpenGL buffer quirk.
                .height = @floatFromInt(-self.virtual_screen.texture.height),
            },
            rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(self.real_screen_dimensions.x),
                .height = @floatFromInt(self.real_screen_dimensions.y),
            },
            rl.Vector2{
                .x = 0,
                .y = 0,
            },
            0.0,
            .ray_white,
        );
    }
};
