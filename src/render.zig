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

/// Low level maze helper module for the core Square type and grid indexing logic.
const maze = @import("maze.zig");
/// The maze generator module for maze building related helpers and logic.
const gen = @import("generator.zig");

/// We will place any texture atlas for any wall styles we want in an asset folder. This is where
/// we should also find solver animations (torch light, explorers, who knows).
const asset_path: [:0]const u8 = "assets/";
/// Walls can be efficiently stored and displayed in a 4x4 grid, aka a tile map or tile atlas.
const atlas_folder: [:0]const u8 = "atlas/";
/// Backtracking is the same texture no matter the style so leave it here.
const backtracking_texture_atlas: [:0]const u8 = "atlas_maze_walls_backtrack.png";

/// A type for modeling anything that needs and x and y position, coordinate, or size. In graphics
/// X is the starting horizontal coordinate at (0, 0) then increasing to the right. The Y is the
/// coordinate starting at (0, 0) then growing downward meaning it increments.
///  0->(X)
///  |
///  V
/// (Y)
/// One notable exception is when drawing to a virtual screen the y axis is inverted. This is
/// relevant to pixel art because all dimensions of every sprite are known. Therefore it is easier
/// to draw to a virtual pixel perfect screen first and then draw that entire screen to the real
/// screen that users see. When drawing virtual to real, the height must be inverted.
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
/// scaled up or down according to preference and graphics library capabilities. The current style
/// is isometric pixel art which means the output is rotated and tiled differently than a top down
/// pixel art style. Any sprite sheets added for wall atlases must draw squares in a 2:1 width to
/// height ratio within a square.
const WallAtlas = struct {
    /// The location of all texture atlas files of *.json and *.png type.
    pub const path: [:0]const u8 = asset_path ++ atlas_folder;
    /// The total area of the texture atlas grid in pixels.
    /// The area of a single maze wall shape square.
    pub const square: Xy = .{ .x = 32, .y = 32 };
    /// The number of rows and columns for a wall texture atlas.
    pub const wall_dimensions: Xy = .{ .x = 4, .y = 4 };
    /// The dimensions of the backtracking square texture. Pixel dimensions are the same.
    pub const backtrack_dimensions: Xy = .{ .x = 2, .y = 2 };

    /// The atlas used to load different wall shapes based on connections after building.
    wall_texture: rl.Texture2D,
    /// Texture used to aid in visual representation of backtracking during building.
    backtrack_texture: rl.Texture2D,

    /// Initialize the wall texture atlas by loading its files with Raylib.
    pub fn init(comptime file_name: [:0]const u8) !WallAtlas {
        return WallAtlas{
            .wall_texture = try rl.Texture2D.init(WallAtlas.path ++ file_name),
            // The backtracking squares never change styles so we can hard code them here.
            .backtrack_texture = try rl.Texture2D.init(
                WallAtlas.path ++ backtracking_texture_atlas,
            ),
        };
    }

    /// Given a square returns the texture and pixel (x, y) coordinates on that texture that should
    /// be rendered as the source rectangle.
    fn getTextureSrc(
        self: *const WallAtlas,
        square_bits: maze.Square,
    ) struct { rl.Texture2D, rl.Rectangle } {
        if (gen.hasBacktracking(square_bits)) {
            const i: i32 = @intCast((square_bits & gen.backtrack_mask) - 1);
            return .{
                self.backtrack_texture, rl.Rectangle{
                    .x = @floatFromInt(@mod(i, backtrack_dimensions.x) * square.x),
                    .y = @floatFromInt(@divTrunc(i, backtrack_dimensions.y) * square.y),
                    .width = @floatFromInt(WallAtlas.square.x),
                    .height = @floatFromInt(WallAtlas.square.y),
                },
            };
        }
        if (maze.isPath(square_bits)) {
            return .{
                self.wall_texture, rl.Rectangle{
                    .x = 0.0,
                    .y = 0.0,
                    .width = @floatFromInt(WallAtlas.square.x),
                    .height = @floatFromInt(WallAtlas.square.y),
                },
            };
        }
        const wall_i: i32 = @intCast((square_bits & maze.wall_mask) >> maze.wall_shift);
        return .{
            self.wall_texture, rl.Rectangle{
                .x = @floatFromInt(@mod(wall_i, wall_dimensions.x) * square.x),
                .y = @floatFromInt(@divTrunc(wall_i, wall_dimensions.y) * square.y),
                .width = @floatFromInt(WallAtlas.square.x),
                .height = @floatFromInt(WallAtlas.square.y),
            },
        };
    }
};

/// A Render wraps the library being used to render textures and shapes so that the calling code
/// does not need to have a dependency on the specific library being used. Now we use Raylib and
/// pixel art, but with this design that may change in the future.
pub const Render = struct {
    atlas: WallAtlas,
    virtual_screen: rl.RenderTexture2D,
    real_screen_dimensions: Xy,
    pub fn init(
        m: *const maze.Maze,
        screen_width: i32,
        screen_height: i32,
    ) !Render {
        comptime assert(WallAtlas.square.x >= 0 and WallAtlas.square.y >= 0);
        comptime assert(WallAtlas.wall_dimensions.x >= 0 and WallAtlas.wall_dimensions.y >= 0);
        rl.initWindow(screen_width, screen_height, "zig-zag-mui");
        rl.setTargetFPS(60);
        const cols: i32 = @intCast(m.maze.cols);
        const rows: i32 = @intCast(m.maze.rows);
        const r = Render{
            .atlas = try WallAtlas.init("atlas_maze_walls_isometric.png"),
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

    /// Frees any resources used by the Render type and the library it uses.
    pub fn deinit() void {
        rl.closeWindow();
    }

    /// The run loop continues until the user has exited the application by closing the window.
    pub fn run(
        self: *const Render,
        m: *maze.Maze,
    ) void {
        var t: f64 = 0.0;
        const dt: f64 = 0.05;
        var cur_time: f64 = rl.getTime();
        var accumulate: f64 = 0.0;
        while (!rl.windowShouldClose()) {
            const new_time: f64 = rl.getTime();
            const frame_time: f64 = rl.getFrameTime();
            cur_time = new_time;
            accumulate += frame_time;
            while (accumulate >= dt) {
                updateSquares(m);
                t += dt;
                accumulate -= dt;
            }
            self.renderMaze(m);
            // Note that if any new textures are loaded the old one must be unloaded here.
        }
    }

    /// Performs only the updates specified by the next step of the Tape.
    fn updateSquares(m: *maze.Maze) void {
        if (m.build_history.i >= m.build_history.deltas.items.len) {
            return;
        }
        const end = m.build_history.deltas.items[m.build_history.i].burst;
        for (m.build_history.i..m.build_history.i + end) |i| {
            const d: maze.Delta = m.build_history.deltas.items[i];
            m.getPtr(d.p.r, d.p.c).* = d.after;
        }
        m.build_history.i += @max(end, 1);
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
            const x_start: i32 = @divTrunc(self.virtual_screen.texture.width, 2) -
                @divTrunc(WallAtlas.square.x, 2);
            const y_start: i32 = @divTrunc(self.virtual_screen.texture.height, 8);
            var r: i32 = 0;
            while (r < m.maze.rows) : (r += 1) {
                var c: i32 = 0;
                while (c < m.maze.cols) : (c += 1) {
                    const texture_source: struct { rl.Texture2D, rl.Rectangle } =
                        self.atlas.getTextureSrc(m.get(r, c));
                    const isometric_x: i32 = x_start + ((c - r) *
                        @divTrunc(WallAtlas.square.x, 2));
                    const isometric_y: i32 = y_start + ((c + r) *
                        @divTrunc(WallAtlas.square.y, 4));
                    rl.drawTexturePro(
                        texture_source[0],
                        texture_source[1],
                        rl.Rectangle{
                            .x = @floatFromInt(isometric_x),
                            .y = @floatFromInt(isometric_y),
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

        // Now actually draw to real screen and let raylib figure out the scaling.
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);
        rl.setTextureFilter(self.virtual_screen.texture, .point);
        // Don't forget to flip the virtual screen source due to OpenGL buffer quirk.
        const inverted_virtual_height: i32 = -self.virtual_screen.texture.height;
        rl.drawTexturePro(
            self.virtual_screen.texture,
            rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(self.virtual_screen.texture.width),
                .height = @floatFromInt(inverted_virtual_height),
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
