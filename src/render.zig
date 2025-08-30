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
//! > [!note]
//! > As an added bonus, we are able to animate a wide variety of building and solving progressions
//! > because we build and solve the mazes before we display anything. We record our work in
//! > playback Tape type that records the changes in the bits of our integer maze Square types. We
//! > have a huge amount of freedom then to animate this on the render side how we wish, completely
//! > separate from maze logic.

////////////////////////////////////////  Imports   ///////////////////////////////////////////////

///////////////////////////////////////   STD

const std = @import("std");
const assert = std.debug.assert;

///////////////////////////////////////   Raylib

// Raylib is the graphics driving library for this application. Awesome!
const rl = @import("raylib");
const rg = @import("raygui");

///////////////////////////////////////   Maze

// Low level maze helper module for the core Square type and grid indexing logic.
const maze = @import("maze.zig");
// The maze generator module for maze building related helpers and logic.
const gen = @import("generator.zig");
const rdfs = @import("builders/rdfs.zig");
const wilson = @import("builders/wilson_adder.zig");

////////////////////////////////////////  Constants   /////////////////////////////////////////////

/// We will place any texture atlas for any wall styles we want in an asset folder. This is where
/// we should also find solver animations (torch light, explorers, who knows).
const asset_path: [:0]const u8 = "assets/";
/// Walls can be efficiently stored and displayed in a 4x4 grid, aka a tile map or tile atlas.
const atlas_folder: [:0]const u8 = "atlas/";
/// Backtracking is the same texture no matter the style so leave it here.
const backtracking_texture_atlas: [:0]const u8 = "atlas_maze_walls_backtrack.png";

////////////////////////////////////////    Types    //////////////////////////////////////////////

/// A Render wraps the library being used to render textures and shapes so that the calling code
/// does not need to have a dependency on the specific library being used. Now we use Raylib and
/// pixel art, but with this design that may change in the future.
pub const Render = struct {
    allocator: std.mem.Allocator,
    maze: maze.Maze,
    atlas: WallAtlas,
    virtual_screen: rl.RenderTexture2D,
    real_screen_dimensions: Xy,
    menu: Menu,

    /// Initialize the render context.
    pub fn init(
        allocator: std.mem.Allocator,
        maze_rows: isize,
        maze_cols: isize,
        screen_width: i32,
        screen_height: i32,
    ) !Render {
        comptime assert(WallAtlas.sprite_pixels.x >= 0 and WallAtlas.sprite_pixels.y >= 0);
        comptime assert(WallAtlas.wall_dimensions.x >= 0 and WallAtlas.wall_dimensions.y >= 0);
        rl.initWindow(screen_width, screen_height, "zig-zag-mui");
        rg.loadStyle("style_cyber.h");
        rl.setTargetFPS(60);
        const cols: i32 = @intCast(@max(maze_cols, maze_rows));
        const rows: i32 = @intCast(@max(maze_cols, maze_rows));
        const r = Render{
            .allocator = allocator,
            .maze = try maze.Maze.init(allocator, rows, cols),
            .atlas = try WallAtlas.init("atlas_maze_walls_isometric_animated.png"),
            .virtual_screen = try rl.RenderTexture2D.init(
                (cols * WallAtlas.sprite_pixels.x) + 100,
                rows * WallAtlas.sprite_pixels.y,
            ),
            .real_screen_dimensions = Xy{
                .x = screen_width,
                .y = screen_height,
            },
            .menu = Menu.init(),
        };
        return r;
    }

    /// Frees any resources used by the Render type and the library it uses.
    pub fn deinit(self: *Render) void {
        rl.unloadTexture(self.virtual_screen.texture);
        self.atlas.deinit();
        rl.closeWindow();
        self.maze.deinit(self.allocator);
    }

    /// The run loop continues until the user has exited the application by closing the window.
    /// This function may allocate memory and thus can fail.
    pub fn run(
        self: *Render,
    ) !void {
        _ = try wilson.generate(&self.maze);
        const cur_tape: *maze.Tape = &self.maze.build_history;
        var algorithm_t: f64 = 0.0;
        var animation_t: f64 = 0.0;
        const animation_dt: f64 = 0.195;
        const algorithm_dt: f64 = 0.5;
        var cur_time: f64 = rl.getTime();
        var algorithm_accumulate: f64 = 0.0;
        var animation_accumulate: f64 = 0.0;
        while (!rl.windowShouldClose()) {
            const new_time: f64 = rl.getTime();
            const frame_time: f64 = rl.getFrameTime();
            cur_time = new_time;
            algorithm_accumulate += frame_time;
            animation_accumulate += frame_time;
            while (algorithm_accumulate >= algorithm_dt) {
                _ = nextMazeStep(&self.maze, cur_tape);
                algorithm_t += algorithm_dt;
                algorithm_accumulate -= algorithm_dt;
            }
            while (animation_accumulate >= animation_dt) {
                updateAnimations(&self.maze);
                animation_t += animation_dt;
                animation_accumulate -= animation_dt;
            }
            self.render();
            // Note that if any new textures are loaded the old one must be unloaded here.
        }
    }

    fn updateAnimations(m: *maze.Maze) void {
        var r: i32 = 0;
        const sync_frame: i32 = @intCast((m.get(0, 0) & WallAtlas.animation_mask) >>
            WallAtlas.animation_shift);
        while (r < m.maze.rows) : (r += 1) {
            var c: i32 = 0;
            while (c < m.maze.cols) : (c += 1) {
                if (m.isPath(r, c)) {
                    continue;
                }
                var next_frame = (sync_frame + 1) &
                    (WallAtlas.animation_mask >> WallAtlas.animation_shift);
                next_frame = @max(next_frame, 1);
                m.getPtr(r, c).* &= ~WallAtlas.animation_mask;
                m.getPtr(r, c).* |= @intCast(next_frame << WallAtlas.animation_shift);
            }
        }
    }

    /// Progresses the tape forward and performs the required next step by adjusting maze squares.
    /// The step may be a single square update or multiple if a burst is specified.
    fn nextMazeStep(
        m: *maze.Maze,
        t: *maze.Tape,
    ) bool {
        if (t.i >= t.deltas.items.len) {
            return false;
        }
        const end = t.deltas.items[t.i].burst;
        for (t.i..t.i + end) |i| {
            const d: maze.Delta = t.deltas.items[i];
            m.getPtr(d.p.r, d.p.c).* = d.after;
        }
        t.i += @max(end, 1);
        return true;
    }

    /// Progresses the tape in reverse and performs the required previous step by adjusting maze
    /// squares. The step may be a single square update or multiple if a burst is specified.
    fn prevMazeStep(
        m: *maze.Maze,
        t: *maze.Tape,
    ) bool {
        if (t.i <= 0 or t.deltas.items[t.i - 1].burst > t.i) {
            return false;
        }
        var i: usize = t.i - 1;
        const end = t.i - t.deltas.items[i].burst;
        while (i > end) : (i -= 1) {
            const d: maze.Delta = t.deltas.items[i];
            m.getPtr(d.p.r, d.p.c).* = d.after;
        }
        t.i = end;
        return true;
    }

    /// Performs pass over maze rendering the current state given the status of the Square bits.
    fn render(
        self: *Render,
    ) void {
        // First, draw the maze as the user has specified to a pixel perfect virtual screen.
        rl.beginTextureMode(self.virtual_screen);
        rl.clearBackground(.black);
        {
            const x_start: i32 = @divTrunc(self.virtual_screen.texture.width, 2) -
                @divTrunc(WallAtlas.sprite_pixels.x, 2);
            const y_start: i32 = @divTrunc(self.virtual_screen.texture.height, 8);
            var r: i32 = 0;
            while (r < self.maze.maze.rows) : (r += 1) {
                var c: i32 = 0;
                while (c < self.maze.maze.cols) : (c += 1) {
                    self.atlas.drawMazeTexture(&self.maze, r, c, x_start, y_start);
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
        self.menu.drawMenu();
    }
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
    pub const sprite_pixels: Xy = .{ .x = 32, .y = 32 };
    /// The number of rows and columns for a wall texture atlas.
    pub const wall_dimensions: Xy = .{ .x = 4, .y = 4 };
    /// The dimensions of the backtracking square texture. Pixel dimensions are the same.
    pub const backtrack_dimensions: Xy = .{ .x = 2, .y = 2 };
    const animation_mask: maze.Square = 0xf00000;
    const animation_shift: usize = 20;

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

    pub fn deinit(self: *WallAtlas) void {
        rl.unloadTexture(self.wall_texture);
        rl.unloadTexture(self.backtrack_texture);
    }

    /// Given a square returns the texture and pixel (x, y) coordinates on that texture that should
    /// be rendered as the source rectangle.
    fn drawMazeTexture(
        self: *const WallAtlas,
        m: *const maze.Maze,
        r: i32,
        c: i32,
        x_start: i32,
        y_start: i32,
    ) void {
        const square_bits: maze.Square = m.get(r, c);
        const isometric_x: i32 = x_start + ((c - r) *
            @divTrunc(WallAtlas.sprite_pixels.x, 2));
        const isometric_y: i32 = y_start + ((c + r) *
            @divTrunc(WallAtlas.sprite_pixels.y, 4));
        const texture_src: struct { rl.Texture2D, rl.Rectangle } = choosing_src: {
            if (gen.hasBacktracking(square_bits)) {
                const i: i32 = @intCast((square_bits & gen.backtrack_mask) - 1);
                break :choosing_src .{
                    self.backtrack_texture,
                    rl.Rectangle{
                        .x = @floatFromInt(@mod(i, backtrack_dimensions.x) * sprite_pixels.x),
                        .y = @floatFromInt(@divTrunc(i, backtrack_dimensions.y) * sprite_pixels.y),
                        .width = @floatFromInt(WallAtlas.sprite_pixels.x),
                        .height = @floatFromInt(WallAtlas.sprite_pixels.y),
                    },
                };
            }
            if (maze.isPath(square_bits)) {
                break :choosing_src .{
                    self.wall_texture,
                    rl.Rectangle{
                        .x = 0.0,
                        .y = 0.0,
                        .width = @floatFromInt(WallAtlas.sprite_pixels.x),
                        .height = @floatFromInt(WallAtlas.sprite_pixels.y),
                    },
                };
            }
            const i: i32 = @intCast((square_bits & animation_mask) >> animation_shift);
            break :choosing_src .{
                self.wall_texture,
                rl.Rectangle{
                    .x = @floatFromInt(@mod(i, wall_dimensions.x) * sprite_pixels.x),
                    .y = @floatFromInt(@divTrunc(i, wall_dimensions.y) * sprite_pixels.y),
                    .width = @floatFromInt(WallAtlas.sprite_pixels.x),
                    .height = @floatFromInt(WallAtlas.sprite_pixels.y),
                },
            };
        };
        rl.drawTexturePro(
            texture_src[0],
            texture_src[1],
            rl.Rectangle{
                .x = @floatFromInt(isometric_x),
                .y = @floatFromInt(isometric_y),
                .width = @floatFromInt(WallAtlas.sprite_pixels.x),
                .height = @floatFromInt(WallAtlas.sprite_pixels.y),
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

const Menu = struct {
    const Direction = enum {
        forward,
        reverse,
    };
    const Generator = enum(u32) {
        rdfs = 0,
        wilson_adder = 1,
    };
    const Solver = enum(u32) {
        dfs = 0,
        bfs = 1,
    };
    const default_animation_dt: f64 = 0.195;

    /// The generator table stores the functions available that we have imported. These can be
    /// selected via an enum as index.
    const generator_table: [2]struct { [:0]const u8, *const fn (*maze.Maze) maze.MazeError!*maze.Maze } = .{
        .{ "RDFS", rdfs.generate },
        .{ "Wilson's Adder", wilson.generate },
    };
    const generator_options: [:0]const u8 = generator_table[0][0] ++ ";" ++ generator_table[1][0];

    // Tuple selectors. Tuples in Zig are convenient for grouping together loose logic of similar
    // but not identical types. The indexing syntax of tuples can be vague so these indices will
    // help the reader understand what field of the tuple is being accessed.

    /// The tuple field holding the rl.Rectangle dimensions of the box.
    const dimension = 0;
    /// The tuple field holding the active selection integer we can turn into an int.
    const active = 1;
    /// The tuple field determining if the drop down is editable.
    const editmode = 2;

    const dropdown_width = 100;
    const dropdown_height = 20;
    const label_height = 20;
    const x_padding = 20;

    generator: struct {
        rl.Rectangle,
        i32,
        bool,
    } = .{
        rl.Rectangle{
            .x = 0 + x_padding,
            .y = label_height,
            .width = dropdown_width,
            .height = dropdown_height,
        },
        0,
        false,
    },
    solver: struct {
        rl.Rectangle,
        i32,
        bool,
    } = .{
        rl.Rectangle{
            .x = (dropdown_width) + x_padding,
            .y = label_height,
            .width = dropdown_width,
            .height = dropdown_height,
        },
        0,
        false,
    },
    dir: struct {
        rl.Rectangle,
        i32,
        bool,
    } = .{
        rl.Rectangle{
            .x = (dropdown_width * 2) + x_padding,
            .y = label_height,
            .width = dropdown_width,
            .height = dropdown_height,
        },
        0,
        false,
    },
    speed: f64 = default_animation_dt,

    fn init() Menu {
        rg.loadStyleDefault();
        return Menu{};
    }

    fn drawMenu(self: *Menu) void {
        _ = rg.label(
            rl.Rectangle{
                .x = self.generator[dimension].x,
                .y = 1,
                .width = self.generator[dimension].width,
                .height = self.generator[dimension].height,
            },
            "Generator:",
        );
        _ = rg.dropdownBox(
            self.generator[dimension],
            Menu.generator_options,
            &self.generator[active],
            self.generator[editmode],
        );
    }
};

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
