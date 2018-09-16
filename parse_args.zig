const parsers = @import("parsers.zig");
const ParseNumber = parsers.ParseNumber;
const ParseAllocated = parsers.ParseAllocated;

const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const assertError = debug.assertError;
const warn = debug.warn;
const fmt = std.fmt;
const mem = std.mem;
const HashMap = std.HashMap;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;

const builtin = @import("builtin");
const TypeId = builtin.TypeId;

const globals = @import("modules/globals.zig");

fn d(bit: usize) bool {
    return globals.dbg_bits.r(globals.dbg_offset_parse_args + bit) == 1;
}

fn dbgw(bit: usize, value: usize) void {
    globals.dbg_bits.w(globals.dbg_offset_parse_args + bit, value);
}

const ArgRecCommon = struct {
    leader: []const u8,         /// empty if none
    name: []const u8,           /// name of arg
    value_default_set: bool,    /// true if value_default has default value
    value_set: bool,            /// true if parseArgs set the value from command line
};

pub fn ArgRec(comptime T: type) type {
    return struct {
        const Self = @This();

        pub common: ArgRecCommon,
    
        parser: comptime switch (@typeId(T)) {
                TypeId.Pointer, TypeId.Array, TypeId.Struct =>
                        fn(*Allocator, []const u8) error!T,
                else => fn([]const u8) error!T,
        },
        value_default: T,               /// value_default copied to value if .value_default_set is true and value_set is false
        value: T,                       /// value is from command line if .value_set is true
    
        fn getArgRecPtr(pArc: *ArgRecCommon) *Self {
            return @fieldParentPtr(Self, "common", pArc);
        }

        fn initNamed(
            name: []const u8,
            default: T
        ) Self {
            return initFlag("", name, default);
        }
    
        fn initFlag(
            leader: []const u8,
            name: []const u8,
            default: T
        ) Self {
            return Self {
                .common = ArgRecCommon {
                    .leader = leader,
                    .name = name,
                    .value_default_set = true,
                    .value_set = false,
                },
                .value_default = default,
                .value = default,
                .parser = ParseNumber(T).parse,
            };
        }
    };
}

test "parseArgs.ArgRec" {
    // Initialize the debug bits
    dbgw(0, 1);
    dbgw(1, 1);

    warn("\n");

    var argList = ArrayList(*ArgRecCommon).init(debug.global_allocator);
    var ar1 = ArgRec(u32).initNamed("countU32", 32);
    try argList.append(&ar1.common);

    var ar2 = ArgRec(i32).initNamed("countI32", 32);
    try argList.append(&ar2.common);

    for (argList.toSlice()) |pArc, i| {
        warn("pArc.name={}\n", pArc.name);
        if (mem.endsWith(u8, pArc.name[0..], "U32")) {
            var pArgRec = ArgRec(u32).getArgRecPtr(pArc);
            warn("argList[{}].value={}\n", i, pArgRec.value);
            warn("argList[{}].common.name={}\n", i, pArgRec.common.name);
        } else {
            var pArgRec = ArgRec(i32).getArgRecPtr(pArc);
            warn("argList[{}].value={}\n", i, pArgRec.value);
            warn("argList[{}].common.name={}\n", i, pArgRec.common.name);
        }
    }
}
