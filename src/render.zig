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
            .menu = Menu.init(screen_width, screen_height),
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
        _ = try Menu.generator_table[0][1](&self.maze);
        const cur_tape: *maze.Tape = &self.maze.build_history;
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
            while (algorithm_accumulate >= self.menu.algorithm_dt) {
                _ = switch (self.menu.direction) {
                    .forward => nextMazeStep(&self.maze, cur_tape),
                    .reverse => prevMazeStep(&self.maze, cur_tape),
                    .pause => false,
                };
                algorithm_t += self.menu.algorithm_dt;
                algorithm_accumulate -= self.menu.algorithm_dt;
            }
            while (animation_accumulate >= animation_dt) {
                updateAnimations(&self.maze);
                animation_t += animation_dt;
                animation_accumulate -= animation_dt;
            }
            try self.render();
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
            m.getPtr(d.p.r, d.p.c).* = d.before;
            if (i == end) {
                break;
            }
            i -= 1;
        }
        t.i = end;
        return true;
    }

    /// Performs pass over maze rendering the current state given the status of the Square bits.
    fn render(
        self: *Render,
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
        // Menu drawing should be done in real screen only.
        try self.menu.drawMenu(&self.maze);
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

/// The Menu displays various controls at the top of the screen while allowing the user to interact
/// with the maze. The user can select algorithms, speeds, and directions that the algorithms run.
/// Therefore, the Menu module is responsible for drawing but may mutate the maze as requested by
/// the user.
const Menu = struct {
    const Direction = enum {
        forward,
        pause,
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

    /// The generator table stores the functions available that we have imported. These can be
    /// selected via an enum as index.
    const generator_table: [2]struct {
        [:0]const u8,
        *const fn (*maze.Maze) maze.MazeError!*maze.Maze,
    } = .{
        .{ "RDFS", rdfs.generate },
        .{ "Wilson's Adder", wilson.generate },
    };

    /// The string Raylib needs to create the options in the generator drop down menu.
    const generator_options: [:0]const u8 = generator_table[0][0] ++ ";" ++ generator_table[1][0];
    /// The solving algorithm options for Raylib drop down.
    const solver_options: [:0]const u8 = "DFS;BFS";
    /// The direction the algorithm can run in a drop down menu. Tapes can be played both ways.
    const direction_options: [:0]const u8 = "Forward;Reverse";

    const label_height = 20;
    const x_padding = 20;
    const button_count = 8;

    const green_hex = 0x00FF00FF;

    const max_algorithm_dt = 1.0;
    const min_algorithm_dt = 0.001;
    const default_dt = 0.3;

    const Dropdown = struct {
        dimensions: rl.Rectangle,
        active: i32,
        editmode: bool,
    };

    const Button = struct {
        dimensions: rl.Rectangle,
        icon: rg.IconName,
    };

    generator: Dropdown = .{
        .dimensions = undefined,
        .active = 0,
        .editmode = false,
    },
    solver: Dropdown = .{
        .dimensions = undefined,
        .active = 0,
        .editmode = false,
    },
    start: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.filetype_video,
    },
    reverse: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.player_previous,
    },
    pause: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.player_pause,
    },
    forward: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.player_next,
    },
    slower: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.arrow_down_fill,
    },
    faster: Button = .{
        .dimensions = undefined,
        .icon = rg.IconName.arrow_up_fill,
    },
    algorithm_dt: f64 = default_dt,
    direction: Direction = Direction.forward,

    /// Initializes the dimensions and styles that will be used for the menu at the top of the
    /// screen. Buttons will control maze related options.
    fn init(screen_width: i32, screen_height: i32) Menu {
        _ = screen_height;
        rg.loadStyleDefault();
        rg.setStyle(.default, .{ .default = rg.DefaultProperty.text_size }, 20);
        rg.setStyle(.default, .{ .control = rg.ControlProperty.text_color_normal }, green_hex);
        // Buttons are spread evenly with some x padding on both sides so there is no edge clipping.
        const button_width: f32 = @floatFromInt(@divTrunc(screen_width - (2 * x_padding), button_count));
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
        ret.start.dimensions = rl.Rectangle{
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
        m: *maze.Maze,
    ) !void {
        drawDropdown("Generator:", Menu.generator_options, &self.generator);
        drawDropdown("Solver:", Menu.solver_options, &self.solver);
        // Restart forces us to act upon any changes in the drop down menus.
        if (drawButton("Restart:", self.start)) {
            // Restart maze with the specified dropdown options.
            m.clearRetainingDimensions();
            _ = try generator_table[@intCast(self.generator.active)][1](m);
            self.direction = Direction.forward;
            self.algorithm_dt = default_dt;
        }
        if (drawButton("Reverse:", self.reverse)) {
            self.direction = Direction.reverse;
        }
        if (drawButton("Pause:", self.pause)) {
            self.direction = Direction.pause;
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
    x: i32,
    y: i32,
};
