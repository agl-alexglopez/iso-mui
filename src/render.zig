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
const gen = @import("generate.zig");
const rdfs = @import("generators/rdfs.zig");
const wilson = @import("generators/wilson_adder.zig");

// Solvers
const sol = @import("solve.zig");
const dfs = @import("solvers/dfs.zig");
const bfs = @import("solvers/bfs.zig");

////////////////////////////////////////  Constants   /////////////////////////////////////////////

////////////////////////////////////////    Types    //////////////////////////////////////////////

/// A Render wraps the library being used to render textures and shapes so that the calling code
/// does not need to have a dependency on the specific library being used. Now we use Raylib and
/// pixel art, but with this design that may change in the future.
pub const Render = struct {
    /// The maze object we own during rendering. We must clear and reset it based on UI choices.
    maze: maze.Maze,

    /// The module we use to handle UI control of maze algorithm details.
    menu: Menu,

    /// The module responsible for handling isometric pixel art and displaying it to screen.
    atlas: WallAtlas,

    /// The virtual screen to which we draw pixel perfect textures.
    virtual_screen: rl.RenderTexture2D,

    /// The real screen we use to scale up the completed virtual screen drawing in one call.
    real_screen_dimensions: Xy,

    /// Initialize the render context.
    pub fn init(
        allocator: std.mem.Allocator,
        maze_rows: i32,
        maze_cols: i32,
        screen_width: i32,
        screen_height: i32,
    ) !Render {
        comptime assert(WallAtlas.sprite_pixels.x >= 0 and WallAtlas.sprite_pixels.y >= 0);
        comptime assert(WallAtlas.wall_dimensions.x >= 0 and WallAtlas.wall_dimensions.y >= 0);
        rl.initWindow(screen_width, screen_height, "iso-mui");
        rl.setTargetFPS(60);
        const cols: i32 = @max(maze_cols, maze_rows);
        const rows: i32 = cols;
        const r = Render{
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
            .menu = Menu.init(screen_width, screen_height),
        };
        return r;
    }

    /// Frees any resources used by the Render type and the library it uses.
    pub fn deinit(self: *Render, allocator: std.mem.Allocator) void {
        rl.unloadTexture(self.virtual_screen.texture);
        self.atlas.deinit();
        rl.closeWindow();
        self.maze.deinit(allocator);
    }

    /// The run loop continues until the user has exited the application by closing the window.
    /// This function may allocate memory and thus can fail.
    pub fn run(
        self: *Render,
        allocator: std.mem.Allocator,
    ) !void {
        _ = try Menu.generator_table[0][1](allocator, &self.maze);
        _ = try Menu.solver_table[0][1](allocator, &self.maze);
        self.maze.zeroSquares();
        var cur_tape: *maze.Tape = &self.maze.build_history;
        var algorithm_t: f64 = 0.0;
        var animation_t: f64 = 0.0;
        const animation_dt: f64 = 0.195;
        var cur_time: f64 = rl.getTime();
        var algorithm_accumulate: f64 = 0.0;
        var animation_accumulate: f64 = 0.0;
        while (!rl.windowShouldClose()) {
            const new_time: f64 = rl.getTime();
            const frame_time: f64 = rl.getFrameTime();
            cur_time = new_time;
            algorithm_accumulate += frame_time;
            animation_accumulate += frame_time;
            while (animation_accumulate >= animation_dt) {
                updateAnimations(&self.maze);
                animation_t += animation_dt;
                animation_accumulate -= animation_dt;
            }
            while (algorithm_accumulate >= self.menu.algorithm_dt) {
                algorithm_t += self.menu.algorithm_dt;
                algorithm_accumulate -= self.menu.algorithm_dt;
                if (self.menu.play_pause == Menu.PlayPause.pause) {
                    continue;
                }
                _ = switch (self.menu.direction) {
                    .forward => {
                        if (!nextMazeStep(&self.maze, cur_tape) and
                            cur_tape == &self.maze.build_history)
                        {
                            cur_tape = &self.maze.solve_history;
                            _ = nextMazeStep(&self.maze, cur_tape);
                        }
                    },
                    .reverse => {
                        if (!prevMazeStep(&self.maze, cur_tape) and
                            cur_tape == &self.maze.solve_history)
                        {
                            cur_tape = &self.maze.build_history;
                            _ = prevMazeStep(&self.maze, cur_tape);
                        }
                    },
                };
            }
            try self.render(allocator, &cur_tape);
        }
    }

    /// Performs pass over maze rendering the current state given the status of the Square bits.
    fn render(
        self: *Render,
        allocator: std.mem.Allocator,
        /// Currently generator or solver. May be adjusted to point to other phase during function.
        cur_tape: **maze.Tape,
    ) !void {
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
                    if (cur_tape.* == &self.maze.build_history) {
                        self.atlas.drawGeneratorTexture(&self.maze, r, c, x_start, y_start);
                    } else {
                        self.atlas.drawSolverTexture(&self.maze, r, c, x_start, y_start);
                    }
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
        // Menu drawing should be done in real screen only.
        try self.menu.drawMenu(allocator, &self.maze, cur_tape);
    }

    /// Progresses the animation frame of wall squares.
    fn updateAnimations(m: *maze.Maze) void {
        var r: i32 = 0;
        // Currently all walls should pulse to a set series of 15 frames so we sync them. In the
        // past I had more randomized animations so I actually could make use of storing each
        // frame in each Square and progressing it as I do now. Leave this comment in case
        // future animations become randomized or otherwise benefit from bit storage.
        const sync_frame: i32 = @intCast((m.get(0, 0).load() & WallAtlas.animation_mask) >>
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
                m.getPtr(r, c).bitAndEq(~WallAtlas.animation_mask);
                m.getPtr(r, c).bitOrEq(@intCast(next_frame << WallAtlas.animation_shift));
            }
        }
    }

    /// Progresses the tape forward and performs the required next step by adjusting maze
    /// squares. The step may be a single square update or multiple if a burst is specified.
    fn nextMazeStep(
        m: *maze.Maze,
        t: *maze.Tape,
    ) bool {
        if (t.i >= t.deltas.items.len) {
            return false;
        }
        const burst = t.deltas.items[t.i].burst;
        const end = @min(t.deltas.items.len, t.i + burst);
        for (t.i..end) |i| {
            const d: maze.Delta = t.deltas.items[i];
            m.getPtr(d.p.r, d.p.c).store(d.after);
        }
        t.i = end;
        return true;
    }

    /// Progresses the tape in reverse and performs the required previous step by adjusting maze
    /// squares. The step may be a single square update or multiple if a burst is specified.
    fn prevMazeStep(
        m: *maze.Maze,
        t: *maze.Tape,
    ) bool {
        if (t.i == 0 or t.deltas.items[t.i - 1].burst > t.i) {
            return false;
        }
        var i: usize = t.i - 1;
        const end = blk: {
            if (t.deltas.items[i].burst > t.i) {
                break :blk 0;
            } else {
                break :blk t.i - t.deltas.items[i].burst;
            }
        };
        while (true) {
            const d: maze.Delta = t.deltas.items[i];
            m.getPtr(d.p.r, d.p.c).store(d.before);
            if (i == end) {
                break;
            }
            i -= 1;
        }
        t.i = end;
        return true;
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
    /// We will place any texture atlas for any wall styles we want in an asset folder. This is
    /// where we should also find solver animations.
    const asset_path: [:0]const u8 = "assets/";

    /// Walls can be efficiently stored and displayed in a 4x4 grid, aka a tile map or tile atlas.
    const atlas_folder: [:0]const u8 = "atlas/";

    /// Backtracking is the same texture no matter the style so leave it here.
    const backtracking_texture_atlas: [:0]const u8 = "atlas_maze_walls_backtrack.png";

    /// The white solve block that will take tint. A simple 32x32 pixel block.
    const solve_block: [:0]const u8 = "solve_block.png";

    /// The location of all texture atlas files of *.json and *.png type.
    pub const path: [:0]const u8 = asset_path ++ atlas_folder;

    /// The area of a single maze wall shape square.
    pub const sprite_pixels: Xy = .{ .x = 32, .y = 32 };

    /// The number of rows and columns for a wall texture atlas.
    pub const wall_dimensions: Xy = .{ .x = 4, .y = 4 };

    /// The dimensions of the backtracking square texture. Pixel dimensions are the same.
    pub const backtrack_dimensions: Xy = .{ .x = 2, .y = 2 };

    /// The mask to get and set animation frames from wall square high bits.
    const animation_mask: maze.SquareU32 = 0xf00000;

    /// The shift to change the animation bits to indexes for the texture atlas.
    const animation_shift: usize = 20;

    /// The atlas used to load different wall shapes based on connections after building.
    wall_texture: rl.Texture2D,

    /// Texture used to aid in visual representation of backtracking during building.
    backtrack_texture: rl.Texture2D,

    /// This is a white block with an outline drawn in pixel art. It is white because this allows
    /// us to give it a tint with Raylib at runtime equivalent to the RGB color stored in the lower
    /// 24 bits of a maze square. This is not relevant for one solver but if we ever implement
    /// multiple threaded solvers we can have a runtime tetradic color scheme to illustrate exactly
    /// which threads visited maze squares and when.
    solve_texture: rl.Texture2D,

    /// Initialize the wall texture atlas by loading its files with Raylib.
    pub fn init(comptime file_name: [:0]const u8) !WallAtlas {
        return WallAtlas{
            .wall_texture = try rl.Texture2D.init(WallAtlas.path ++ file_name),
            // The backtracking squares never change styles so we can hard code them here.
            .backtrack_texture = try rl.Texture2D.init(
                WallAtlas.path ++ backtracking_texture_atlas,
            ),
            .solve_texture = try rl.Texture2D.init(WallAtlas.path ++ solve_block),
        };
    }

    /// Unloads the textures for this atlas module.
    pub fn deinit(self: *WallAtlas) void {
        rl.unloadTexture(self.wall_texture);
        rl.unloadTexture(self.backtrack_texture);
        rl.unloadTexture(self.solve_texture);
    }

    /// Draws the appropriate maze square to the screen based on the values of the square bits.
    /// Maze generators can use various tricks to make the display more interesting and we pick
    /// up on those here.
    fn drawGeneratorTexture(
        self: *const WallAtlas,
        m: *const maze.Maze,
        r: i32,
        c: i32,
        x_start: i32,
        y_start: i32,
    ) void {
        const square_bits: maze.SquareU32 = m.get(r, c).load();
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
            // The 0th index of the wall atlas is a path so if we know this is a wall we should
            // never allow it to be a path if the animation has not yet been updated.
            const i: i32 = @intCast(@max(1, (square_bits & animation_mask) >> animation_shift));
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

    /// Draws the appropriate maze square to the screen based on the values of the square bits.
    /// Solvers are focused on colors for displaying the paths. The solver block is white so that
    /// we can use Raylib's tint capability to display the RGB color stored in the lower 24 bits
    /// of a maze square.
    fn drawSolverTexture(
        self: *const WallAtlas,
        m: *const maze.Maze,
        r: i32,
        c: i32,
        x_start: i32,
        y_start: i32,
    ) void {
        const square_bits: maze.SquareU32 = m.get(r, c).load();
        const isometric_x: i32 = x_start + ((c - r) *
            @divTrunc(WallAtlas.sprite_pixels.x, 2));
        const isometric_y: i32 = y_start + ((c + r) *
            @divTrunc(WallAtlas.sprite_pixels.y, 4));
        const texture_src: struct { rl.Texture2D, rl.Rectangle, rl.Color } = choosing_src: {
            if (sol.isStartOrFinish(square_bits)) {
                break :choosing_src .{
                    self.solve_texture,
                    rl.Rectangle{
                        .x = 0.0,
                        .y = 0.0,
                        .width = @floatFromInt(WallAtlas.sprite_pixels.x),
                        .height = @floatFromInt(WallAtlas.sprite_pixels.y),
                    },
                    rl.Color{
                        .r = 0,
                        .g = 255,
                        .b = 255,
                        .a = 255,
                    },
                };
            }
            if (maze.isPath(square_bits)) {
                var color: rl.Color = .ray_white;
                var texture = self.wall_texture;
                if (sol.hasPaint(square_bits)) {
                    texture = self.solve_texture;
                    const rgb: struct { u8, u8, u8 } = sol.getPaint(square_bits);
                    color = rl.Color{
                        .r = rgb[0],
                        .g = rgb[1],
                        .b = rgb[2],
                        .a = 255,
                    };
                }
                break :choosing_src .{
                    texture,
                    rl.Rectangle{
                        .x = 0.0,
                        .y = 0.0,
                        .width = @floatFromInt(WallAtlas.sprite_pixels.x),
                        .height = @floatFromInt(WallAtlas.sprite_pixels.y),
                    },
                    color,
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
                .ray_white,
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
            texture_src[2],
        );
    }
};

/// The Menu displays various controls at the top of the screen while allowing the user to interact
/// with the maze. The user can select algorithms, speeds, and directions for the algorithm to run.
/// Therefore, the Menu module is responsible for drawing but may mutate the maze as requested by
/// the user, especially when a newly requested maze type must be loaded in.
const Menu = struct {
    /// The direction that the maze algorithms run. Fully reversible if desired.
    const Direction = enum {
        forward,
        reverse,
    };

    /// Standard toggle pause play for the user.
    const PlayPause = enum {
        play,
        pause,
    };

    /// A drop down notably requires a string of options for Raylib to display.
    const Dropdown = struct {
        /// The position and size for the real screen.
        dimensions: rl.Rectangle,
        /// The active option in the drop down.
        active: i32,
        /// Indicates drop down can be edited.
        editmode: bool,
    };

    /// The simplest UI element for simple boolean actions.
    const Button = struct {
        /// The position and size for the real screen.
        dimensions: rl.Rectangle,
        /// Taken from Raylib icon page for each button.
        icon: rg.IconName,
    };

    /// The generator table stores the functions available that we have imported. These can be
    /// selected via an enum as index.
    const generator_table: [2]struct {
        [:0]const u8,
        *const fn (std.mem.Allocator, *maze.Maze) maze.MazeError!*maze.Maze,
    } = .{
        .{ "RDFS", rdfs.generate },
        .{ "Wilson's Adder", wilson.generate },
    };

    const solver_table: [2]struct {
        [:0]const u8,
        *const fn (std.mem.Allocator, *maze.Maze) maze.MazeError!*maze.Maze,
    } = .{
        .{ "DFS", dfs.solve },
        .{ "BFS", bfs.solve },
    };

    /// The string Raylib needs to create the options in the generator drop down menu.
    const generator_options: [:0]const u8 = blk: {
        var str: [:0]const u8 = "";
        for (0..generator_table.len - 1) |i| {
            str = str ++ generator_table[i][0] ++ ";";
        }
        str = str ++ generator_table[generator_table.len - 1][0];
        break :blk str;
    };
    /// The solving algorithm options for Raylib drop down.
    const solver_options: [:0]const u8 = blk: {
        var str: [:0]const u8 = "";
        for (0..solver_table.len - 1) |i| {
            str = str ++ solver_table[i][0] ++ ";";
        }
        str = str ++ solver_table[solver_table.len - 1][0];
        break :blk str;
    };

    /// The direction the algorithm can run in a drop down menu. Tapes can be played both ways.
    const direction_options: [:0]const u8 = "Forward;Reverse";

    /// The height of the space for text above each button.
    const label_height = 20;

    /// X direction padding to left and right of menu buttons so no cutoff.
    const x_padding = 20;

    /// The color used for buttons and text.
    const green_hex = 0x00FF00FF;

    /// The slowest animation possible for our algorithms.
    const max_algorithm_dt = 1.0;

    /// The fastest animation possible for our algorithms.
    const min_algorithm_dt = 0.0001;

    // The starting animation speed.
    const default_dt = 0.3;

    /// The number of fields representing our UI elements below.
    const button_count = 8;

    /// The maze builder selection. Dimensions set based on screen size at runtime.
    generator: Dropdown = .{
        .dimensions = undefined,
        .active = 0,
        .editmode = false,
    },

    /// The maze solver selection. Dimensions set based on screen size at runtime.
    solver: Dropdown = .{
        .dimensions = undefined,
        .active = 0,
        .editmode = false,
    },

    /// Restart the visualization based on selections.
    restart: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.filetype_video,
    },

    /// Immediately reverse the visualization.
    reverse: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.player_previous,
    },

    /// Immediately pause or play the visualization.
    pause: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.player_pause,
    },

    /// Immediately play the visualization.
    forward: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.player_next,
    },

    /// Slow down the animation by increasing delta time.
    slower: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.arrow_down_fill,
    },

    /// Speed up the animation by decreasing delta time.
    faster: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.arrow_up_fill,
    },

    /// The current visualization speed.
    algorithm_dt: f64 = default_dt,

    /// The direction the algorithm plays.
    direction: Direction = Direction.forward,

    /// Toggle the visualization progress.
    play_pause: PlayPause = PlayPause.play,

    /// Initializes the dimensions and styles that will be used for the menu at the top of the
    /// screen. Buttons will control maze related options.
    fn init(screen_width: i32, screen_height: i32) Menu {
        _ = screen_height;
        rg.loadStyleDefault();
        rg.setStyle(.default, .{ .default = rg.DefaultProperty.text_size }, 20);
        rg.setStyle(.default, .{ .control = rg.ControlProperty.text_color_normal }, green_hex);
        // Buttons are spread evenly with some x padding on both sides so there is no edge clipping.
        const button_width: f32 = @floatFromInt(
            @divTrunc(
                screen_width - (2 * x_padding),
                button_count,
            ),
        );
        const button_height = 20;
        var ret = Menu{};
        ret.generator.dimensions = rl.Rectangle{
            .x = x_padding,
            .y = label_height,
            .width = button_width,
            .height = button_height,
        };
        ret.solver.dimensions = rl.Rectangle{
            .x = button_width + x_padding,
            .y = label_height,
            .width = button_width,
            .height = button_height,
        };
        ret.restart.dimensions = rl.Rectangle{
            .x = (button_width * 2) + x_padding,
            .y = label_height,
            .width = button_width,
            .height = button_height,
        };
        ret.reverse.dimensions = rl.Rectangle{
            .x = (button_width * 3) + x_padding,
            .y = label_height,
            .width = button_width,
            .height = button_height,
        };
        ret.pause.dimensions = rl.Rectangle{
            .x = (button_width * 4) + x_padding,
            .y = label_height,
            .width = button_width,
            .height = button_height,
        };
        ret.forward.dimensions = rl.Rectangle{
            .x = (button_width * 5) + x_padding,
            .y = label_height,
            .width = button_width,
            .height = button_height,
        };
        ret.slower.dimensions = rl.Rectangle{
            .x = (button_width * 6) + x_padding,
            .y = label_height,
            .width = button_width,
            .height = button_height,
        };
        ret.faster.dimensions = rl.Rectangle{
            .x = (button_width * 7) + x_padding,
            .y = label_height,
            .width = button_width,
            .height = button_height,
        };
        return ret;
    }

    /// Draws the menu elements and handles any menu interactions that require updating the maze.
    /// For example, if the user has changed menu items and requests a maze reset, it must be
    /// rebuilt and solved under the specified algorithm categories. Otherwise, the user can
    /// control the direction of the playback and the speed which requires an immediate action.
    fn drawMenu(
        self: *Menu,
        allocator: std.mem.Allocator,
        m: *maze.Maze,
        cur_tape: **maze.Tape,
    ) !void {
        drawDropdown("Generator:", Menu.generator_options, &self.generator);
        drawDropdown("Solver:", Menu.solver_options, &self.solver);
        // Restart forces us to act upon any changes in the drop down menus.
        if (drawButton("Restart:", self.restart)) {
            // Restart maze with the specified dropdown options.
            m.clearRetainingCapacity();
            _ = try generator_table[@intCast(self.generator.active)][1](allocator, m);
            _ = try solver_table[@intCast(self.solver.active)][1](allocator, m);
            m.zeroSquares();
            cur_tape.* = &m.build_history;
            self.direction = Direction.forward;
            self.algorithm_dt = default_dt;
        }
        if (drawButton("Reverse:", self.reverse)) {
            self.direction = Direction.reverse;
        }
        if (drawButton("Pause:", self.pause)) {
            self.play_pause = switch (self.play_pause) {
                Menu.PlayPause.play => Menu.PlayPause.pause,
                Menu.PlayPause.pause => Menu.PlayPause.play,
            };
        }
        if (drawButton("Forward:", self.forward)) {
            self.direction = Direction.forward;
        }
        if (drawButton("Slower:", self.slower)) {
            self.algorithm_dt = @min(self.algorithm_dt * 2, max_algorithm_dt);
        }
        if (drawButton("Faster:", self.faster)) {
            self.algorithm_dt = @max(self.algorithm_dt / 2, min_algorithm_dt);
        }
    }

    /// Draws the drop down and allows user to mutate active selection. However, no action needs
    /// be taken until the user requests a restart under the current selections. This simplifies
    /// the process of menu handling and number of restarts required to rebuild and solve a maze.
    fn drawDropdown(
        label: [:0]const u8,
        comptime options: [:0]const u8,
        dropdown: *Dropdown,
    ) void {
        _ = rg.label(
            rl.Rectangle{
                .x = dropdown.dimensions.x,
                .y = 1,
                .width = dropdown.dimensions.width,
                .height = dropdown.dimensions.height,
            },
            label,
        );
        if (rg.dropdownBox(
            dropdown.dimensions,
            options,
            &dropdown.active,
            dropdown.editmode,
        ) != 0) {
            dropdown.editmode = !dropdown.editmode;
        }
    }

    /// Draws the button and reports if it has been pressed by returning true. Otherwise the button
    /// is drawn in its default state.
    fn drawButton(
        label: [:0]const u8,
        button: Button,
    ) bool {
        _ = rg.label(
            rl.Rectangle{
                .x = button.dimensions.x,
                .y = 1,
                .width = button.dimensions.width,
                .height = button.dimensions.height,
            },
            label,
        );
        return rg.button(button.dimensions, rg.iconText(@intFromEnum(button.icon), ""));
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
    /// Left to right coordinate or size.
    x: i32,
    /// Top to bottom coordinate or size.
    y: i32,
};
