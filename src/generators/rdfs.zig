//! The Randomized Depth First search, or rdfs, module implements the most basic maze building
//! algorithm, depth first search. It simply carves out paths by randomly branching down unexplored
//! sections of the maze and carving paths. It records the backtracking directions and caches seen
//! squares by modifying their bits so no auxiliary data structures or storage is needed. Only
//! 4 bits are required to run all the logic of this algorithm. We do, however, use the Tape data
//! structure to record the build process but this is for later display purposes.
//!
//! We need the help of the standard library for random generation and shuffling to produce uniform
//! random mazes, but otherwise the algorithm is extremely simple and efficient.
const std = @import("std");

const gen = @import("../generate.zig");
const maze = @import("../maze.zig");

/// Generates a randomized depth first search maze. This maze will produce long windy passages.
/// Because the building of the maze is recorded in the maze build history, allocation may fail.
pub fn generate(
    m: *maze.Maze,
    allocator: std.mem.Allocator,
) maze.MazeError!*maze.Maze {
    // Randomized depth first search needs no auxiliary memory.
    _ = allocator;
    try gen.fillMazeWithWalls(m);
    var randgen = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const rand = randgen.random();
    const start = try gen.randPoint(
        rand,
        .{ 0, m.maze.rows - 3 },
        .{ 0, m.maze.cols - 3 },
        gen.ParityPoint.odd,
    );
    var cur = start;
    var random_direction_indices: [gen.num_directions]usize = .{ 0, 1, 2, 3 };
    branching: while (true) {
        rand.shuffle(usize, &random_direction_indices);
        for (random_direction_indices) |i| {
            const direction = gen.generator_cardinals[i];
            const branch = maze.Point{
                .r = cur.r + direction.r,
                .c = cur.c + direction.c,
            };
            if (gen.canBuildNewSquare(m, branch)) {
                try gen.recordBacktrackPath(m, cur, branch);
                cur = branch;
                continue :branching;
            }
        }
        // Backtracking.
        const direction: maze.Square = m.get(cur.r, cur.c) & gen.backtrack_mask;
        const half_point = gen.backtracking_half_points[@intCast(direction)];
        const half_step = maze.Point{
            .r = cur.r + half_point.r,
            .c = cur.c + half_point.c,
        };
        const cur_square = m.get(cur.r, cur.c);
        const half_step_square = m.get(half_step.r, half_step.c);
        try m.build_history.record(.{
            .p = cur,
            .before = cur_square,
            .after = cur_square & ~gen.backtrack_mask,
            .burst = 1,
        });
        try m.build_history.record(.{
            .p = half_step,
            .before = half_step_square,
            .after = half_step_square & ~gen.backtrack_mask,
            .burst = 1,
        });
        m.getPtr(cur.r, cur.c).* &= ~gen.backtrack_mask;
        m.getPtr(half_step.r, half_step.c).* &= ~gen.backtrack_mask;
        const full_point = gen.backtracking_points[@intCast(direction)];
        cur.r += full_point.r;
        cur.c += full_point.c;

        // Return to origin and so tree is complete.
        if (std.meta.eql(cur, start)) {
            return m;
        }
    }
}
