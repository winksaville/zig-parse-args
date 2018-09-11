const ArrayU1 = @import("array-u1/array-u1.zig").ArrayU1;

// Module dbg_bits bit base offsets
pub const dbg_offset_parse_args = 0;
pub const dbg_offset_parsers = 16;

// Array of dbg_bits
pub var debug_bits = ArrayU1(32).init();
pub const dbg_bits = &debug_bits;
