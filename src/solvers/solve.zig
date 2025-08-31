//! The solve helper module provides low level support for any and all maze solving algorithms.
//! Operations such as placing the start and finish squares or handling colors of the solver or
//! solvers can be handled by this module.
const maze = @import("../maze.zig");

pub const start_bit: maze.Square = 0x40000000;
pub const finish_bit: maze.Square = 0x80000000;

/// Here are all four tetradic colors if more solvers are added in a multithreading scheme:
/// 0x880044, 0x766002, 0x009531, 0x010a88
pub const thread_paints = [1]maze.Square{0x880044};
/// The bit a thread can use to mark a square as seen.
pub const thread_seen: maze.Square = 0x1000000;
