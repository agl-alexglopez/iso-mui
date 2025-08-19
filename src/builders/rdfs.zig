const std = @import("std");

const gen = @import("../generator.zig");
const maze = @import("../maze.zig");

pub fn generate(m: *maze.Maze) !*maze.Maze {
    try gen.fillMazeWithWalls(m);
    var randgen = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const rand = randgen.random();
    const start = maze.Point{
        .r = 2 * (@divTrunc(rand.intRangeAtMost(isize, 0, m.maze.rows - 3), 2)) + 1,
        .c = 2 * (@divTrunc(rand.intRangeAtMost(isize, 0, m.maze.cols - 3), 2)) + 1,
    };
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
        if (std.meta.eql(cur, start)) {
            return m;
        }
    }
    return m;
}
