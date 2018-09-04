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
const parseInt = std.fmt.parseInt;
const parseUnsiged = std.fmt.parseUnsigned;

pub const ArgIteratorTest = struct {
    const Self = this;

    index: usize,
    count: usize,
    args: []const []const u8,

    pub fn init(pSelf: *Self, args: []const []const u8) void {
        pSelf.index = 0;
        pSelf.count = args.len;
        pSelf.args = args;
    }

    pub fn next(pSelf: *Self) ?[]const u8 {
        if (pSelf.index == pSelf.count) return null;

        pSelf.index += 1;
        return pSelf.args[pSelf.index - 1];
    }

    pub fn skip(pSelf: *Self) bool {
        if (pSelf.index == pSelf.count) return false;

        pSelf.index += 1;
        return true;
    }
};

const ArgIteratorTypes = enum {
    testAi,
    osAi,
};

const ArgumentIterator = union(ArgIteratorTypes) {
    testAi: ArgIteratorTest,
    osAi: std.os.ArgIterator,
};

const MyArgIterator = struct {
    const Self = this;

    ai: ArgumentIterator,

    pub fn initOsAi(pSelf: *Self) void {
        // TODO: init() returns ArgIterator
        pSelf.ai(ArgIteratorTypes.osAi).init();
    }

    pub fn initTestAi(pSelf: *Self, args: []const []const u8) void {
        pSelf.ai.testAi.init(args);
    }

    pub fn next(pSelf: *Self, pAllocator: *Allocator) ?[]const u8 {
        switch (pSelf.ai) {
            ArgIteratorTypes.testAi => {
                return pSelf.ai.testAi.next();
            },
            //ArgIteratorTypes.osAi => |ai| return ai.next(pAllocator),
            else => return null,
        }
    }

    pub fn skip(pSelf: *Self) bool {
        switch (pSelf.ai) {
            ArgIteratorTypes.testAi => {
                return pSelf.ai.testAi.skip();
            },
            ArgIteratorTypes.osAi => {
                return pSelf.ai.osAi.skip();
            },
        }
    }
};

const ParsedArg = struct {
    leader: []const u8,
    lhs: []const u8,
    sep: []const u8,
    rhs: []const u8,
};

const Argument = struct {
   leader: []const u8,              /// empty if none
   name: []const u8,                /// name of arg
   value_default_set: bool,         /// true if value_default has default value
   value_set: bool,                 /// true if parse set the value
   arg_union: ArgUnionFields,       /// union
};

const ArgUnionFields = union(enum) {
    argU32: ArgUnion(u32),
    argU64: ArgUnion(u64),
    argU128: ArgUnion(u128),
    argF32: ArgUnion(f32),
    argF64: ArgUnion(f64),
    argStr: ArgUnion([]const u8),
};

fn ArgUnion(comptime T: type) type {
    return struct {
        parser: fn([]const u8) error!T, /// Parse the []const u8 to T
        value_default: T,               /// Value if .value_default_set is true and value_set is false
        value: T,                       /// Value if .value_set is true
    };
}

pub fn parseInteger(comptime T: type, value_str: []const u8) !T {
    var radix: u32 = 10;
    var value: u128 = 0;
    for (value_str) |ch, i| {
        if (ch == '_') continue;

        // To lower case
        var lc: u8 = if ((ch >= 'A') and (ch <= 'Z')) ch + ('a' - 'A') else ch;

        var v: u8 = undefined;
        if ((lc >= '0') and (lc <= '9')) {
            v = lc - '0';
        } else {
            if ((i == 1) and (value == 0)) {
                switch (lc) {
                    'b' => { radix = 2; continue; },
                    'o' => { radix = 8; continue; },
                    'd' => { radix = 10; continue; },
                    'x' => { radix = 16; continue; },
                    else => radix = 10,
                }
            }
            v = 10 + (lc - 'a');
        }
        if (v >= radix) return error.InvalidCharacter;
        value *= radix;
        value += v;
    }
    return @intCast(T, value);
}

pub fn parseU32(value_str: []const u8) !u32 {
    return try parseInteger(u32, value_str);
}

pub fn parseU64(value_str: []const u8) !u64 {
    return try parseInteger(u64, value_str);
}

pub fn parseU128(value_str: []const u8) !u128 {
    return try parseInteger(u128, value_str);
}

pub fn parseString(value_str: []const u8) ![]const u8 {
    if (value_str.len == 0) return error.WTF;
    return value_str;
}


fn parseArg(leader: []const u8, arg: []const u8, sep: []const u8) ParsedArg {
    var parsedArg = ParsedArg {
        .leader = "", .lhs = "", .sep = "", .rhs = "",
    };
    var idx: usize = 0;
    if (mem.eql(u8, leader, arg[idx..leader.len])) {
        idx += leader.len;
        parsedArg.leader = leader;
    }
    var sep_idx = idx;
    var found_sep = while (sep_idx < arg.len) : (sep_idx += 1) {
                        if (mem.eql(u8, arg[sep_idx..(sep_idx + sep.len)], sep[0..])) {
                            parsedArg.sep = sep;
                            break true;
                        }
                    } else false;
    if (found_sep) {
        parsedArg.lhs = arg[idx..sep_idx];
        parsedArg.sep = sep;
        parsedArg.rhs = arg[(sep_idx + sep.len)..];
    } else {
        parsedArg.lhs = arg[idx..];
    }
    return parsedArg;
}


pub fn parseArgs(
    pAllocator: *Allocator,
    args_it: *MyArgIterator,
    arg_proto_list: ArrayList(Argument),
) !ArrayList([]const u8) {
    if (!args_it.skip()) @panic("expected arg[0] to exist");

    var positionalArgs = ArrayList([]const u8).init(pAllocator);

    // Add the arg_prototypes to a hash map
    const ArgProtoMap = HashMap([]const u8, *Argument, mem.hash_slice_u8, mem.eql_slice_u8);
    var arg_proto_map = ArgProtoMap.init(pAllocator);
    var i: usize = 0;
    while (i < arg_proto_list.len) {
        var arg_proto: *Argument = &arg_proto_list.items[i];
        //warn("&arg_proto={*} name={}\n", arg_proto, arg_proto.name);

        if (arg_proto.value_default_set) {
            switch (arg_proto.arg_union) {
                ArgUnionFields.argU32 => arg_proto.arg_union.argU32.value = arg_proto.arg_union.argU32.value_default,
                ArgUnionFields.argU64 => arg_proto.arg_union.argU64.value = arg_proto.arg_union.argU64.value_default,
                ArgUnionFields.argU128 => arg_proto.arg_union.argU128.value = arg_proto.arg_union.argU128.value_default,
                ArgUnionFields.argF32 => arg_proto.arg_union.argF32.value = arg_proto.arg_union.argF32.value_default,
                ArgUnionFields.argF64 => arg_proto.arg_union.argF64.value = arg_proto.arg_union.argF64.value_default,
                ArgUnionFields.argStr => arg_proto.arg_union.argStr.value = arg_proto.arg_union.argStr.value_default,
            }
            arg_proto.value_set = false;
        }

        if (arg_proto_map.contains(arg_proto.name)) {
            var pKV = arg_proto_map.get(arg_proto.name);
            var v = pKV.?.value;
            warn("Duplicate arg_proto.name={} previous value was at index {}\n", arg_proto.name, i);
            return error.ArgProtoDuplicate;
        }
        _ = try arg_proto_map.put(arg_proto.name, arg_proto);

        i += 1;
    }
    
    // Loop through all of the arguments passed setting the prototype values
    // and returning the positional list.
    while (args_it.next(pAllocator)) |arg_or_error| {
        //var raw_arg = try arg_or_error;
        var raw_arg = arg_or_error;
        var arg = parseArg("--", raw_arg, "=");
        var pKV = arg_proto_map.get(arg.lhs);
        if (pKV == null) {
            // Doesn't match
            if (mem.eql(u8, arg.leader, "") and mem.eql(u8, arg.rhs, ""))  {
                if (mem.eql(u8, arg.sep, "")) {
                    try positionalArgs.append(arg.lhs);
                    continue;
                } else {
                    warn("error.UnknownButEmptyNamedParameterUnknown, raw_arg={} parsed arg={}\n", raw_arg, arg);
                    return error.UnknownButEmptyNamedParameter;
                }
            } else {
                warn("error.UnknownOption raw_arg={} parsed arg={}\n", raw_arg, arg);
                return error.UnknownOption;
            } 
        }

        // Got a match
        var v = pKV.?.value;
        var isa_option = if (mem.eql(u8, arg.leader, "")) false else mem.eql(u8, arg.leader[0..], v.leader[0..]);
        if (!mem.eql(u8, arg.rhs, "")) {
            switch (v.arg_union) {
                ArgUnionFields.argU32 => v.arg_union.argU32.value = try v.arg_union.argU32.parser(arg.rhs[0..]),
                ArgUnionFields.argU64 => v.arg_union.argU64.value = try v.arg_union.argU64.parser(arg.rhs[0..]),
                ArgUnionFields.argU128 => v.arg_union.argU128.value = try v.arg_union.argU128.parser(arg.rhs[0..]),
                ArgUnionFields.argF32 => v.arg_union.argF32.value = try v.arg_union.argF32.parser(arg.rhs[0..]),
                ArgUnionFields.argF64 => v.arg_union.argF64.value = try v.arg_union.argF64.parser(arg.rhs[0..]),
                ArgUnionFields.argStr => v.arg_union.argStr.value = try v.arg_union.argStr.parser(arg.rhs[0..]),
            }
            v.value_set = true; // This was set from the command line
        } else {
            // Do nothgin as We've already initialize the default if there was one set
        }
    }
    return positionalArgs;
}

test "parseInteger" {
    assert((try parseInteger(u8, "0")) == @intCast(u8, 0));
    assert((try parseInteger(u8, "0b0")) == @intCast(u8, 0));
    assert((try parseInteger(u8, "0b1")) == @intCast(u8, 1));
    assert((try parseInteger(u8, "0b1010_0101")) == @intCast(u8, 0xA5));
    assertError(parseInteger(u8, "0b2"), error.InvalidCharacter);

    assert((try parseInteger(u8, "0o0")) == @intCast(u8, 0));
    assert((try parseInteger(u8, "0o1")) == @intCast(u8, 1));
    assert((try parseInteger(u8, "0o7")) == @intCast(u8, 7));
    assert((try parseInteger(u8, "0o77")) == @intCast(u8, 0x3f));
    assert((try parseInteger(u32, "0o111_777")) == @intCast(u32, 0b1001001111111111));
    assertError(parseInteger(u8, "0b8"), error.InvalidCharacter);

    assert((try parseInteger(u8, "0d0")) == @intCast(u8, 0));
    assert((try parseInteger(u8, "0d1")) == @intCast(u8, 1));
    assert((try parseInteger(u8, "0d9")) == @intCast(u8, 9));
    assert((try parseInteger(u8, "0")) == @intCast(u8, 0));
    assert((try parseInteger(u8, "1")) == @intCast(u8, 1));
    assert((try parseInteger(u8, "9")) == @intCast(u8, 9));
    assert((try parseInteger(u64, "123_456_789")) == @intCast(u32, 123456789));
    assertError(parseInteger(u8, "0d0000000a"), error.InvalidCharacter);

    assert((try parseInteger(u8, "0x0")) == @intCast(u8, 0x0));
    assert((try parseInteger(u8, "0x1")) == @intCast(u8, 0x1));
    assert((try parseInteger(u8, "0x9")) == @intCast(u8, 0x9));
    assert((try parseInteger(u8, "0xa")) == @intCast(u8, 0xa));
    assert((try parseInteger(u8, "0xf")) == @intCast(u8, 0xf));
    assert((try parseInteger(u128, "0x1234_5678_9ABc_Def0_0FEd_Cba9_8765_4321")) == @intCast(u128, 0x123456789ABcDef00FEdCba987654321));
    assertError(parseInteger(u8, "0xg"), error.InvalidCharacter);
}

test "parseArgs.basic" {
    warn("\n");

    var argList = ArrayList(Argument).init(debug.global_allocator);

    try argList.append(Argument {
        .leader = "",
        .name = "countU32",
        .value_default_set = true,
        .value_set = false,
        .arg_union = ArgUnionFields {
            .argU32 = ArgUnion(u32) {
                .parser = parseU32,
                .value_default = 32,
                .value = 0,
            },
        },
    });

    try argList.append(Argument {
        .leader = "",
        .name = "countU64",
        .value_default_set = true,
        .value_set = false,
        .arg_union = ArgUnionFields {
            .argU64 = ArgUnion(u64) {
                .parser = parseU64,
                .value_default = 64,
                .value = 0,
            },
        },
    });

    try argList.append(Argument {
        .leader = "",
        .name = "countU128",
        .value_default_set = true,
        .value_set = false,
        .arg_union = ArgUnionFields {
            .argU128 = ArgUnion(u128) {
                .parser = parseU128,
                .value_default = 128,
                .value = 0,
            },
        },
    });

    try argList.append(Argument {
        .leader = "",
        .name = "first_name",
        .value_default_set = false,
        .value_set = false,
        .arg_union = ArgUnionFields {
            .argStr = ArgUnion([]const u8) {
                .parser = parseString,
                .value_default = "",
                .value = "",
            },
        },
    });

    var arg_iter: MyArgIterator = undefined;
    arg_iter.initTestAi([]const []const u8 {
        "abc",
        "hello",
        "countU32=321",
        "countU64=641",
        "countU128=0x1234_5678_9ABC_DEF0",
        "first_name=wink",
        "world",
    });

    var positionalArgs = try parseArgs(debug.global_allocator, &arg_iter, argList);
    for (positionalArgs.toSlice()) |arg, i| {
        warn("positionalArgs[{}]={}\n", i, arg);
    }
    for (argList.toSlice()) |arg, i| {
        warn("argList[{}]: name={} value_set={} arg.value=", i, arg.name, arg.value_set);
        switch (arg.arg_union) {
            ArgUnionFields.argU32 => warn("{}", arg.arg_union.argU32.value),
            ArgUnionFields.argU64 => warn("{}", arg.arg_union.argU64.value),
            ArgUnionFields.argU128 => warn("{x}", arg.arg_union.argU128.value),
            ArgUnionFields.argF32 => warn("{}", arg.arg_union.argF32.value),
            ArgUnionFields.argF64 => warn("{}", arg.arg_union.argF64.value),
            ArgUnionFields.argStr => warn("{}", arg.arg_union.argStr.value),
        }
        warn("\n");
    }
}
