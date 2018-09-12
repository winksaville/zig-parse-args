const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const assertError = debug.assertError;
const warn = debug.warn;
const ArrayList = std.ArrayList;

const parse_args = @import("parse_args.zig");
const ArgIter = parse_args.ArgIter;
const Argument = parse_args.Argument;
const ArgUnionFields = parse_args.ArgUnionFields;
const ArgUnion = parse_args.ArgUnion;
const parseArgs = parse_args.parseArgs;
const ParseInt = parse_args.ParseInt;
const ParseFloating = parse_args.ParseFloating;
const parseStr = parse_args.parseStr;

const globals = @import("modules/globals.zig");

fn d(bit: usize) bool {
    return globals.dbg_bits.r(globals.dbg_offset_parse_args + bit) == 1;
}

fn dbgw(bit: usize, value: usize) void {
    globals.dbg_bits.w(globals.dbg_offset_parse_args + bit, value);
}

pub fn main() !void {
    // Initialize the debug bits
    dbgw(0, 1);
    dbgw(1, 1);

    warn("\n");

    var arg_list = ArrayList(Argument).init(debug.global_allocator);

    try arg_list.append(Argument {
        .leader = "",
        .name = "count",
        .value_default_set = true,
        .value_set = false,
        .arg_union = ArgUnionFields {
            .argU32 = ArgUnion(u32) {
                .parser = ParseInt(u32).parse,
                .value_default = 32,
                .value = 0,
            },
        },
    });

    // Initialize the os Argument Iterator
    var arg_iter = ArgIter.initOsArgIter();

    // Parse the arguments
    var positional_args = try parseArgs(debug.global_allocator, &arg_iter, arg_list);

    // Display the positional arguments
    for (positional_args.toSlice()) |arg, i| {
        warn("positional_args[{}]={}\n", i, arg);
    }

    // Display the options
    for (arg_list.toSlice()) |arg, i| {
        warn("arg_list[{}]: name={} value_set={} arg.value=", i, arg.name, arg.value_set);
        switch (arg.arg_union) {
            ArgUnionFields.argU32 => warn("{}", arg.arg_union.argU32.value),
            ArgUnionFields.argI32 => warn("{}", arg.arg_union.argI32.value),
            ArgUnionFields.argU64 => warn("{}", arg.arg_union.argU64.value),
            ArgUnionFields.argI64 => warn("{}", arg.arg_union.argI64.value),
            ArgUnionFields.argU128 => warn("0x{x}", arg.arg_union.argU128.value),
            ArgUnionFields.argI128 => warn("{}", arg.arg_union.argI128.value),
            ArgUnionFields.argF32 => warn("{}", arg.arg_union.argF32.value),
            ArgUnionFields.argF64 => warn("{}", arg.arg_union.argF64.value),
            ArgUnionFields.argStr => {
                warn("{} &value[0]={*}", arg.arg_union.argStr.value, &arg.arg_union.argStr.value[0]);
            },
        }
        warn("\n");
    }

    // Free data any allocated data of ArgUnionFields.argStr
    for (arg_list.toSlice()) |arg, i| {
        switch (arg.arg_union) {
            ArgUnionFields.argStr => {
                if (arg.value_set) {
                    warn("free arg_list[{}]: name={} value_set={} arg.value={}\n",
                        i, arg.name, arg.value_set, arg.arg_union.argStr.value);
                    debug.global_allocator.free(arg.arg_union.argStr.value);
                }
            },
            else => {},
        }
    }
    debug.global_allocator.free(arg_list.items);
}