//! This module provides the core type and structure of a maze square. The main
//! goal is to provide the wall pieces and some fundamental helper functions
//! such that the builder and solver can perform their tasks more easily.

/// A Square is the fundamental maze cell type. It has 32 bits available
/// for various building and solving logic that other modules can apply.
/// blue bits────────────────────────────────┬┬┬┬─┬┬┬┐
/// green bits─────────────────────┬┬┬┬─┬┬┬┐ ││││ ││││
/// red bits─────────────┬┬┬┬─┬┬┬┐ ││││ ││││ ││││ ││││
/// walls/threads───┬┬┬┐ ││││ ││││ ││││ ││││ ││││ ││││
/// built bit─────┐ ││││ ││││ ││││ ││││ ││││ ││││ ││││
/// path bit─────┐│ ││││ ││││ ││││ ││││ ││││ ││││ ││││
/// start bit───┐││ ││││ ││││ ││││ ││││ ││││ ││││ ││││
/// finish bit─┐│││ ││││ ││││ ││││ ││││ ││││ ││││ ││││
///          0b0000 0000 0000 0000 0000 0000 0000 0000
pub const Square = u32;
