// Standard library stuff.
const std = @import("std");
const heap = std.heap;
// Conditional compilation for debug or release.
const builtin = @import("builtin");
// Rendering pipeline module.
const render = @import("render.zig");

/// Argument parsing helper.
const Args = struct {
    const row_flag: []const u8 = "-r=";
    const col_flag: []const u8 = "-c=";
    const width_flag: []const u8 = "-w=";
    const height_flag: []const u8 = "-h=";
    rows: i32 = 20,
    cols: i32 = 20,
    width: i32 = 1200,
    height: i32 = 1200,

    /// Helper to set fields of the argument struct.
    const Set = enum {
        r,
        c,
        w,
        h,
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
        const conversion = try std.fmt.parseInt(i32, arg, 10);
        switch (field) {
            Set.r => self.rows = conversion,
            Set.c => self.cols = conversion,
            Set.w => self.width = conversion,
            Set.h => self.height = conversion,
        }
    }
};

pub fn main() !void {
    // Enable verbose log if needed when bugs begin to appear in the debug allocator.
    // While thread safety is not strictly needed now if solvers become multi-threaded the
    // allocators must be thread safe for thread specific requests for data structure memory.
    var allocator_impl = switch (builtin.mode) {
        .Debug => heap.DebugAllocator(.{
            .backing_allocator_zeroes = true,
            .retain_metadata = true,
            .never_unmap = true,
            .safety = true,
            .thread_safe = true,
        }){},
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => heap.GeneralPurposeAllocator(.{
            .thread_safe = true,
            .safety = true,
        }){},
    };
    var maze_args = Args{};
    const allocator = allocator_impl.allocator();
    for (std.os.argv[1..]) |a| {
        const arg = std.mem.span(a);
        if (std.mem.startsWith(u8, arg, Args.row_flag)) {
            try maze_args.set(Args.Set.r, arg[Args.row_flag.len..]);
        } else if (std.mem.startsWith(u8, arg, Args.col_flag)) {
            try maze_args.set(Args.Set.c, arg[Args.col_flag.len..]);
        } else if (std.mem.startsWith(u8, arg, Args.width_flag)) {
            try maze_args.set(Args.Set.w, arg[Args.width_flag.len..]);
        } else if (std.mem.startsWith(u8, arg, Args.height_flag)) {
            try maze_args.set(Args.Set.h, arg[Args.height_flag.len..]);
        } else {
            return error.UnrecognizedCommandLineArgument;
        }
    }

    // Rendering code when maze is complete.
    var loop = try render.Render.init(
        allocator,
        maze_args.rows,
        maze_args.cols,
        maze_args.width,
        maze_args.height,
    );
    defer loop.deinit();
    try loop.run();
}
