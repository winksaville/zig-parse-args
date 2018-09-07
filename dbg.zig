const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const assertError = debug.assertError;
const warn = debug.warn;

const BitIdx = switch (@sizeOf(usize)) {
    4 => u5,
    8 => u6,
    else => @compileError("Currently only 4 and 8 byte usize supported for BitIdx\n"),
};

const MIN_DBG_BITS = @import("./DBG_BITS.zig").DBG_BITS;
const num_elems =
        if (MIN_DBG_BITS < bits_per_elem) 1
        else MIN_DBG_BITS + (bits_per_elem - 1) / bits_per_elem;

var dbg_bits: [num_elems]usize = undefined;
const bits_per_elem = @sizeOf(usize) * 8;
const num_bits = @sizeOf(@typeOf(dbg_bits)) * bits_per_elem;

pub fn dbg(bit_offset: usize) bool {
    if (bit_offset >= num_bits) return false;
    var elem_idx = bit_offset / bits_per_elem;
    var bit_idx: BitIdx = @intCast(BitIdx, bit_offset % bits_per_elem);
    return (dbg_bits[elem_idx] & ((usize(1) << bit_idx))) != 0;
}

pub fn dbgWriteBit(bit_offset: usize, val: usize) void {
    if (bit_offset >= num_bits) return;
    var elem_idx = bit_offset / bits_per_elem;
    var bit_idx: BitIdx = @intCast(BitIdx, bit_offset % bits_per_elem);
    var bit_mask: usize = usize(1) << bit_idx;
    if (val == 0) {
        dbg_bits[elem_idx] &= ~bit_mask;
    } else {
        dbg_bits[elem_idx] |= bit_mask;
    }
}


test "dbg" {
    var prng = std.rand.DefaultPrng.init(std.os.time.timestamp());
    
    var bit0_off: usize = 0;
    var bit0_on: usize = 0;
    var bit1_off: usize = 0;
    var bit1_on: usize = 0;

    var count: usize = 15;
    while (count > 0) : (count -= 1) {
        dbgWriteBit(0, prng.random.scalar(usize) & 1);
        if (dbg(0)) {warn("bit 0 on\n"); bit0_on += 1;} else {warn("bit 0 off\n"); bit0_off += 1;}
        dbgWriteBit(1, prng.random.scalar(usize) & 1);
        if (dbg(1)) {warn("bit 1 on\n"); bit1_on += 1;} else {warn("bit 1 off\n"); bit1_off += 1;}
    }
    warn("bit0_off:{} bit0_on:{}\n", bit0_off, bit0_on);
    warn("bit1_off:{} bit1_on:{}\n", bit1_off, bit1_on);
}
