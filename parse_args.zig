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
const pDb = &globals.debug_bits;

fn d(bit: usize) bool {
    return pDb.r(globals.dbg_offset_parse_args + bit) == 1;
}

fn dbgw(bit: usize, value: usize) void {
    pDb.w(globals.dbg_offset_parse_args + bit, value);
}

pub const ArgIteratorTest = struct {
    const Self = @This();

    index: usize,
    count: usize,
    args: []const []const u8,

    pub fn init(args: []const []const u8) Self {
        return Self{
            .index = 0,
            .count = args.len,
            .args = args,
        };
    }

    pub fn next(pSelf: *Self) ?[]const u8 {
        if (d(1)) warn("ArgIteratorTest.next:+ count={} index={}\n", pSelf.count, pSelf.index);
        defer if (d(1)) warn("ArgIteratorTest.next:-\n");

        if (pSelf.index == pSelf.count) return null;

        var n = pSelf.args[pSelf.index];
        pSelf.index += 1;
        if (d(1)) warn("&ArgIteratorTest: &n[0]={*} '{}'\n", &n[0], n);
        return n;
    }

    pub fn skip(pSelf: *Self) bool {
        if (pSelf.index == pSelf.count) return false;

        pSelf.index += 1;
        return true;
    }
};

pub const ArgIter = struct {
    const Self = @This();

    const ArgIteratorEnum = union(enum) {
        testArgIter: ArgIteratorTest,
        osArgIter: std.os.ArgIterator,
    };

    ai: ArgIteratorEnum,

    pub fn initOsArgIter() Self {
        return Self{
            .ai = ArgIteratorEnum{ .osArgIter = std.os.ArgIterator.init() },
        };
    }

    pub fn initTestArgIter(args: []const []const u8) Self {
        return Self{
            .ai = ArgIteratorEnum{ .testArgIter = ArgIteratorTest.init(args) },
        };
    }

    // Caller must free memory
    //
    // TODO: See if this analysis is true and see if we can fix it?
    //
    // This is needed because osArgIter.next needs an allocator.
    // More specifically, ArgIteratorWindows needs an allocator
    // where as ArgIteratorPosix does not. The reason
    // ArgIteratorWindows needs the allocator is that
    // the command line is parsed during next(). I believe
    // if the parsing was done by the bootstrap code
    // the allocator would not be necessary.
    pub fn next(pSelf: *Self, pAllocator: *Allocator) ?anyerror![]const u8 { // <<< This works
        //pub fn next(pSelf: *Self, pAllocator: *Allocator) ?(error![]const u8) { // <<< This works
        //pub fn next(pSelf: *Self, pAllocator: *Allocator) ?(![]const u8) {      // <<< Why doesn't this work
        //pub fn next(pSelf: *Self, pAllocator: *Allocator) ?![]const u8 {        // <<< Why doesn't this work
        switch (pSelf.ai) {
            ArgIteratorEnum.testArgIter => {
                var elem = pSelf.ai.testArgIter.next();
                if (elem == null) return null;
                return mem.dupe(pAllocator, u8, elem.?);
                //var n = mem.dupe(pAllocator, u8, elem.?) catch |err| return (error![]const u8)(err);
                //if (d(1)) warn("&ArgIteratorEnum: &n[0]={*}\n", &n[0]);
                //return (error![]const u8)(n);
            },
            ArgIteratorEnum.osArgIter => return (?anyerror![]const u8)(pSelf.ai.osArgIter.next(pAllocator)),
        }
    }

    pub fn skip(pSelf: *Self) bool {
        switch (pSelf.ai) {
            ArgIteratorEnum.testArgIter => {
                return pSelf.ai.testArgIter.skip();
            },
            ArgIteratorEnum.osArgIter => {
                return pSelf.ai.osArgIter.skip();
            },
        }
    }
};

pub const ArgRec = struct {
    /// empty if none
    leader: []const u8,
    /// name of arg
    name: []const u8,

    // Upon exit from parseArg the following holds:
    //
    // If value_set == false and value_default_set == false
    //      ArgUnion.value is undefined
    //      ArgUnion.value_default undefined
    //
    // If value_set == false and value_default_set == true
    //      ArgUnion.value == ArgUnion.value_default
    //      ArgUnion.value_default as defined when ArgRec was created
    //
    // If value_set == true and value_default_set == false
    //      ArgUnion.value == value from command line
    //      ArgUnion.value_default undefined
    //
    // If value_set == true and value_default_set == false
    //      ArgUnion.value == value from command line
    //      ArgUnion.value_default as defined when ArgRec was created
    //
    // Thus if the user initializes value_default and sets value_default_set to true
    // then value will always have a "valid" value and value_set will be true if
    // the value came from the command line and false if it came from value_default.
    /// true if value_default has default value
    value_default_set: bool,
    /// true if parseArgs set the value from command line
    value_set: bool,

    /// union
    arg_union: ArgUnionFields,

    fn initNamed(
        comptime T: type,
        name: []const u8,
        default: T,
    ) ArgRec {
        return initFlag(T, "", name, default);
    }

    fn initFlag(
        comptime T: type,
        leader: []const u8,
        name: []const u8,
        default: T,
    ) ArgRec {
        var v: ArgRec = undefined;
        v.leader = leader;
        v.name = name;
        v.value_default_set = true;
        v.value_set = false;
        switch (T) {
            u32 => {
                if (d(1)) warn("initFlag: u32\n");
                v.arg_union = ArgUnionFields{
                    .argU32 = ArgUnion(u32){
                        .value_default = default,
                        .value = default,
                        .parser = ParseNumber(u32).parse,
                    },
                };
            },
            i32 => {
                if (d(1)) warn("initFlag: i32\n");
                v.arg_union = ArgUnionFields{
                    .argI32 = ArgUnion(i32){
                        .value_default = default,
                        .value = default,
                        .parser = ParseNumber(i32).parse,
                    },
                };
            },
            u64 => {
                if (d(1)) warn("initFlag: u64\n");
                v.arg_union = ArgUnionFields{
                    .argU64 = ArgUnion(u64){
                        .value_default = default,
                        .value = default,
                        .parser = ParseNumber(u64).parse,
                    },
                };
            },
            i64 => {
                if (d(1)) warn("initFlag: i64\n");
                v.arg_union = ArgUnionFields{
                    .argI64 = ArgUnion(i64){
                        .value_default = default,
                        .value = default,
                        .parser = ParseNumber(i64).parse,
                    },
                };
            },
            u128 => {
                if (d(1)) warn("initFlag: u128\n");
                v.arg_union = ArgUnionFields{
                    .argU128 = ArgUnion(u128){
                        .value_default = default,
                        .value = default,
                        .parser = ParseNumber(u128).parse,
                    },
                };
            },
            i128 => {
                if (d(1)) warn("initFlag: i128\n");
                v.arg_union = ArgUnionFields{
                    .argI128 = ArgUnion(i128){
                        .value_default = default,
                        .value = default,
                        .parser = ParseNumber(i128).parse,
                    },
                };
            },
            f32 => {
                if (d(1)) warn("initFlag: f32\n");
                v.arg_union = ArgUnionFields{
                    .argF32 = ArgUnion(f32){
                        .value_default = default,
                        .value = default,
                        .parser = ParseNumber(f32).parse,
                    },
                };
            },
            f64 => {
                if (d(1)) warn("initFlag: f64\n");
                v.arg_union = ArgUnionFields{
                    .argF64 = ArgUnion(f64){
                        .value_default = default,
                        .value = default,
                        .parser = ParseNumber(f64).parse,
                    },
                };
            },
            []const u8 => {
                if (d(1)) warn("initFlag: []const u8\n");
                v.arg_union = ArgUnionFields{
                    .argAlloced = ArgUnion([]const u8){
                        .value_default = default,
                        .value = default,
                        .parser = ParseAllocated([]const u8).parse,
                    },
                };
            },
            else => unreachable,
        }
        return v;
    }
};

// ArgUnionFields should be more generic
pub const ArgUnionFields = union(enum) {
    argU32: ArgUnion(u32),
    argI32: ArgUnion(i32),
    argU64: ArgUnion(u64),
    argI64: ArgUnion(i64),
    argU128: ArgUnion(u128),
    argI128: ArgUnion(i128),
    argF32: ArgUnion(f32),
    argF64: ArgUnion(f64),
    argAlloced: ArgUnion([]const u8),
};

pub fn ArgUnion(comptime T: type) type {
    return struct {
        const Self = This();

        /// Parse the []const u8 to T
        parser: comptime switch (TypeId(@typeInfo(T))) {
            TypeId.Pointer, TypeId.Array, TypeId.Struct => fn (*Allocator, []const u8) anyerror!T,
            else => fn ([]const u8) anyerror!T,
        },
        /// value_default copied to value if .value_default_set is true and value_set is false
        value_default: T,
        /// value is from command line if .value_set is true
        value: T,
    };
}

const ParsedArg = struct {
    leader: []const u8,
    lhs: []const u8,
    sep: []const u8,
    rhs: []const u8,
};

fn parseArg(leader: []const u8, raw_arg: []const u8, sep: []const u8) ParsedArg {
    if (d(0)) warn("&leader[0]={*} &raw_arg[0]={*} &sep[0]={*}\n", &leader[0], &raw_arg[0], &sep[0]);
    var parsedArg = ParsedArg{
        .leader = "",
        .lhs = "",
        .sep = "",
        .rhs = "",
    };
    var idx: usize = 0;
    if (mem.eql(u8, leader, raw_arg[idx..leader.len])) {
        idx += leader.len;
        parsedArg.leader = leader;
    }
    var sep_idx = idx;
    var found_sep = while (sep_idx < raw_arg.len) : (sep_idx += 1) {
        if (mem.eql(u8, raw_arg[sep_idx..(sep_idx + sep.len)], sep[0..])) {
            parsedArg.sep = sep;
            if (d(0)) warn("&parsedArg.sep[0]={*} &sep[0]={*}\n", &parsedArg.sep[0], &sep[0]);
            break true;
        }
    } else false;
    if (found_sep) {
        parsedArg.lhs = raw_arg[idx..sep_idx];
        parsedArg.sep = sep;
        parsedArg.rhs = raw_arg[(sep_idx + sep.len)..];
    } else {
        parsedArg.lhs = raw_arg[idx..];
    }
    if (d(0))
        warn("&parsedArg={*} &leader[0]={*} &lhs[0]={*} &sep[0]={*} &rhs[0]={*}\n", &parsedArg, if (parsedArg.leader.len != 0) &parsedArg.leader[0] else null, if (parsedArg.lhs.len != 0) &parsedArg.lhs[0] else null, if (parsedArg.sep.len != 0) &parsedArg.sep[0] else null, if (parsedArg.rhs.len != 0) &parsedArg.rhs[0] else null);
    return parsedArg; // Assume this isn't copyied?
}

pub fn parseArgs(
    pAllocator: *Allocator,
    args_it: *ArgIter,
    arg_proto_list: ArrayList(ArgRec),
) !ArrayList([]const u8) {
    if (!args_it.skip()) @panic("expected arg[0] to exist");
    if (d(0)) warn("parseArgs:+ arg_proto_list.len={}\n", arg_proto_list.len);
    defer if (d(0)) warn("parseArgs:-\n");

    var positionalArgs = ArrayList([]const u8).init(pAllocator);

    // Add the arg_prototypes to a hash map
    const ArgProtoMap = HashMap([]const u8, *ArgRec, mem.hash_slice_u8, mem.eql_slice_u8);
    var arg_proto_map = ArgProtoMap.init(pAllocator);
    var i: usize = 0;
    while (i < arg_proto_list.len) {
        var arg_proto: *ArgRec = &arg_proto_list.items[i];
        if (d(0)) warn("&arg_proto={*} name={}\n", arg_proto, arg_proto.name);

        if (arg_proto_map.contains(arg_proto.name)) {
            var pKV = arg_proto_map.get(arg_proto.name);
            var v = pKV.?.value;
            if (d(0)) warn("Duplicate arg_proto.name={} previous value was at index {}\n", arg_proto.name, i);
            return error.ArgProtoDuplicate;
        }
        _ = try arg_proto_map.put(arg_proto.name, arg_proto);

        i += 1;
    }

    // Loop through all of the arguments passed setting the prototype values
    // and returning the positional list.
    while (args_it.next(pAllocator)) |arg_or_error| {
        // raw_arg must be freed is was allocated by args_it.next(pAllocator) above!
        var raw_arg = try arg_or_error;
        defer if (d(1)) {
            warn("free: &raw_arg[0]={*} &raw_arg={*} raw_arg={}\n", &raw_arg[0], &raw_arg, raw_arg);
            pAllocator.free(raw_arg);
        };

        if (d(1)) warn("&raw_arg[0]={*} raw_arg={}\n", &raw_arg[0], raw_arg);
        var parsed_arg = parseArg("--", raw_arg, "=");
        if (d(1))
            warn("&parsed_arg={*} &leader[0]={*} &lhs[0]={*} &sep[0]={*} &rhs[0]={*}\n", &parsed_arg, if (parsed_arg.leader.len != 0) &parsed_arg.leader[0] else null, if (parsed_arg.lhs.len != 0) &parsed_arg.lhs[0] else null, if (parsed_arg.sep.len != 0) &parsed_arg.sep[0] else null, if (parsed_arg.rhs.len != 0) &parsed_arg.rhs[0] else null);
        var pKV = arg_proto_map.get(parsed_arg.lhs);
        if (pKV == null) {
            // Doesn't match
            if (mem.eql(u8, parsed_arg.leader, "") and mem.eql(u8, parsed_arg.rhs, "")) {
                if (mem.eql(u8, parsed_arg.sep, "")) {
                    try positionalArgs.append(parsed_arg.lhs);
                    continue;
                } else {
                    if (d(1))
                        warn("error.UnknownButEmptyNamedParameterUnknown, raw_arg={} parsed parsed_arg={}\n", raw_arg, parsed_arg);
                    return error.UnknownButEmptyNamedParameter;
                }
            } else {
                if (d(1)) warn("error.UnknownOption raw_arg={} parsed parsed_arg={}\n", raw_arg, parsed_arg);
                return error.UnknownOption;
            }
        }

        // Got a match
        var v = pKV.?.value;
        var isa_option = if (mem.eql(u8, parsed_arg.leader, "")) false else mem.eql(u8, parsed_arg.leader[0..], v.leader[0..]);
        if (!mem.eql(u8, parsed_arg.rhs, "")) {
            // Set value to the rhs
            switch (v.arg_union) {
                ArgUnionFields.argU32 => v.arg_union.argU32.value = try v.arg_union.argU32.parser(parsed_arg.rhs[0..]),
                ArgUnionFields.argI32 => v.arg_union.argI32.value = try v.arg_union.argI32.parser(parsed_arg.rhs[0..]),
                ArgUnionFields.argU64 => v.arg_union.argU64.value = try v.arg_union.argU64.parser(parsed_arg.rhs[0..]),
                ArgUnionFields.argI64 => v.arg_union.argI64.value = try v.arg_union.argI64.parser(parsed_arg.rhs[0..]),
                ArgUnionFields.argU128 => v.arg_union.argU128.value = try v.arg_union.argU128.parser(parsed_arg.rhs[0..]),
                ArgUnionFields.argI128 => v.arg_union.argI128.value = try v.arg_union.argI128.parser(parsed_arg.rhs[0..]),
                ArgUnionFields.argF32 => v.arg_union.argF32.value = try v.arg_union.argF32.parser(parsed_arg.rhs[0..]),
                ArgUnionFields.argF64 => v.arg_union.argF64.value = try v.arg_union.argF64.parser(parsed_arg.rhs[0..]),
                ArgUnionFields.argAlloced => v.arg_union.argAlloced.value = try v.arg_union.argAlloced.parser(pAllocator, parsed_arg.rhs[0..]),
            }
            v.value_set = true; // set value_set as it's initialised via an argument
        } else {
            // parsed_arg.rhs is empty so use "default" if is was set
            if (v.value_default_set) {
                switch (v.arg_union) {
                    ArgUnionFields.argU32 => v.arg_union.argU32.value = v.arg_union.argU32.value_default,
                    ArgUnionFields.argI32 => v.arg_union.argI32.value = v.arg_union.argI32.value_default,
                    ArgUnionFields.argU64 => v.arg_union.argU64.value = v.arg_union.argU64.value_default,
                    ArgUnionFields.argI64 => v.arg_union.argI64.value = v.arg_union.argI64.value_default,
                    ArgUnionFields.argU128 => v.arg_union.argU128.value = v.arg_union.argU128.value_default,
                    ArgUnionFields.argI128 => v.arg_union.argI128.value = v.arg_union.argI128.value_default,
                    ArgUnionFields.argF32 => v.arg_union.argF32.value = v.arg_union.argF32.value_default,
                    ArgUnionFields.argF64 => v.arg_union.argF64.value = v.arg_union.argF64.value_default,
                    ArgUnionFields.argAlloced => v.arg_union.argAlloced.value = v.arg_union.argAlloced.value_default,
                }
                v.value_set = false; // Since we used the default we'll clear value_set
            }
        }
    }
    return positionalArgs;
}

test "parseArgs.basic" {
    // Initialize the debug bits
    dbgw(0, 0);
    dbgw(1, 0);

    warn("\n");

    // Create the list of options
    var argList = ArrayList(ArgRec).init(debug.global_allocator);
    try argList.append(ArgRec.initNamed(u32, "countU32", 32));
    try argList.append(ArgRec.initFlag(i32, "--", "countI32", 32));
    try argList.append(ArgRec.initNamed(u64, "countU64", 64));
    try argList.append(ArgRec.initNamed(i64, "countI64", -64));
    try argList.append(ArgRec.initNamed(u128, "countU128", 128));
    try argList.append(ArgRec.initNamed(i128, "countI128", -128));
    try argList.append(ArgRec.initNamed(f32, "valueF32", -32.32));
    try argList.append(ArgRec.initNamed(f64, "valueF64", -64.64));
    try argList.append(ArgRec.initNamed([]const u8, "first_name", "ken"));

    // Create arguments that we will parse
    var arg_iter = ArgIter.initTestArgIter([]const []const u8{
        "file.exe", // The first argument is the "executable" and is skipped
        "hello",
        "countU32=321",
        "--countI32=-321",
        "countU64=641",
        "countI64=-641",
        "countU128=123_456_789",
        "countI128=-1_281",
        "valueF32=1_232.321_021",
        "valueF64=64.64",
        "first_name=wink",
        "world",
    });

    // Parse the arguments
    var positionalArgs = try parseArgs(debug.global_allocator, &arg_iter, argList);

    // Display positional arguments
    for (positionalArgs.toSlice()) |arg, i| {
        warn("positionalArgs[{}]={}\n", i, arg);
    }

    // Display the options
    for (argList.toSlice()) |arg, i| {
        warn("argList[{}]: name={} value_set={} arg.value=", i, arg.name, arg.value_set);
        switch (arg.arg_union) {
            ArgUnionFields.argU32 => warn("{}", arg.arg_union.argU32.value),
            ArgUnionFields.argI32 => warn("{}", arg.arg_union.argI32.value),
            ArgUnionFields.argU64 => warn("{}", arg.arg_union.argU64.value),
            ArgUnionFields.argI64 => warn("{}", arg.arg_union.argI64.value),
            ArgUnionFields.argU128 => warn("{}", arg.arg_union.argU128.value),
            ArgUnionFields.argI128 => warn("{}", arg.arg_union.argI128.value),
            ArgUnionFields.argF32 => warn("{}", arg.arg_union.argF32.value),
            ArgUnionFields.argF64 => warn("{}", arg.arg_union.argF64.value),
            ArgUnionFields.argAlloced => {
                warn("{} &value[0]={*}", arg.arg_union.argAlloced.value, &arg.arg_union.argAlloced.value[0]);
            },
        }
        warn("\n");
    }

    // Assert we have the expected values
    assert(argList.items[0].arg_union.argU32.value == 321);
    assert(argList.items[1].arg_union.argI32.value == -321);
    assert(argList.items[2].arg_union.argU64.value == 641);
    assert(argList.items[3].arg_union.argI64.value == -641);
    assert(argList.items[4].arg_union.argU128.value == 123456789);
    assert(argList.items[5].arg_union.argI128.value == -1281);
    assert(argList.items[6].arg_union.argF32.value == 1232.321021);
    assert(argList.items[7].arg_union.argF64.value == 64.64);
    assert(mem.eql(u8, argList.items[8].arg_union.argAlloced.value, "wink"));

    // Free data any allocated data of ArgUnionFields.argAlloced
    for (argList.toSlice()) |arg, i| {
        switch (arg.arg_union) {
            ArgUnionFields.argAlloced => {
                if (arg.value_set) {
                    warn("free argList[{}]: name={} value_set={} arg.value={}\n", i, arg.name, arg.value_set, arg.arg_union.argAlloced.value);
                    debug.global_allocator.free(arg.arg_union.argAlloced.value);
                }
            },
            else => {},
        }
    }
    debug.global_allocator.free(argList.items);
}
