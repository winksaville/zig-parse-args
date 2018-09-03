const std = @import("std");
const debug = std.debug;
const warn = debug.warn;
const args = std.os.args;
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
    params: []const []const u8,

    pub fn init(pSelf: *Self, params: []const []const u8) void {
        pSelf.index = 0;
        pSelf.count = params.len;
        pSelf.params = params;
    }

    pub fn next(pSelf: *Self) ?[]const u8 {
        if (pSelf.index == pSelf.count) return null;

        pSelf.index += 1;
        return pSelf.params[pSelf.index - 1];
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

    pub fn initTestAi(pSelf: *Self, params: []const []const u8) void {
        pSelf.ai.testAi.init(params);
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

const Arg = struct {
    leader: []const u8,
    lhs: []const u8,
    sep: []const u8,
    rhs: []const u8,
};

fn ArgPrototype(comptime T: type) type {
    return struct {
        leader: []const u8,             /// empty if none
        name: []const u8,               /// name of arg
        parser: fn([]const u8) error!T,  /// Parse the []const u8 to T
        value_default_set: bool,        /// true if value_default has default value
        value_default: T,               /// Value if a .name has no right hand side
                                        /// and value_default_set
        value_set: bool,                /// true if parse set the value
        value: T,                       /// Value if .value_set is true
    };
}

const ArgProtoUnion = union(enum) {
    argU32: ArgPrototype(u32),
    argU64: ArgPrototype(u64),
    argF32: ArgPrototype(f32),
    argF64: ArgPrototype(f64),
    argStr: ArgPrototype([]const u8),
};

pub fn parseNumber(comptime T: type, value_str: []const u8) !T {
    warn("parseNumber: value_str={}\n", value_str);
    return parseInt(T, value_str, 10);
}

pub fn parseU32(value_str: []const u8) !u32 {
    var v = try parseNumber(u32, value_str);
    warn("parseU32: value_str={} v={}\n", value_str, v);
    return v;
}

pub fn parseStr(comptime T: type, value_str: []const u8) !T {
    if (value_str.len == 0) return error.WTF;
    return value_str;
}

pub fn parseArg(leader: []const u8, arg: []const u8, sep: []const u8) Arg {
    var parsedArg = Arg {
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
    arg_proto_list: ArrayList(ArgProtoUnion),
) !void {
    if (!args_it.skip()) @panic("expected arg[0] to exist");

    // Add the arg_prototypes to a hash map
    const ArgProtoMap = HashMap([]const u8, *ArgProtoUnion,
                            mem.hash_slice_u8, mem.eql_slice_u8);
    var arg_proto_map = ArgProtoMap.init(pAllocator);
    var i: usize = 0;
    while (i < arg_proto_list.len) {
        var arg_proto: *ArgProtoUnion = &arg_proto_list.items[i];
        warn("&arg_proto={*}\n", arg_proto);

        var name: []const u8 =
            switch (arg_proto.*) {
                ArgProtoUnion.argU32 => |ap| ap.name,
                else => "",
            };
        warn("add: name={}\n", name);

        if (arg_proto_map.contains(name)) {
            return error.ArgProtoDuplicate;
        }
        var r = try arg_proto_map.put(name, arg_proto);
        if (r != null) {
            return error.ArgProtoDuplicateWhenThereShouldNotBeAnDuplicate;
        }
        i += 1;

        var pKV = arg_proto_map.get(name);
        if (pKV == null) {
            return error.ArgJustAddedFailedGet;
        }
        var value: *ArgProtoUnion = pKV.?.value;
        warn("value={*}\n", value);
    }
    
    while (args_it.next(pAllocator)) |arg_or_error| {
        //var raw_arg = try arg_or_error;
        var raw_arg = arg_or_error;
        warn("raw_arg={}\n", raw_arg);
        var arg = parseArg("--", raw_arg, "=");
        warn("arg={}\n", arg);
        var pKV = arg_proto_map.get(arg.lhs);
        if (pKV == null) {
            warn("pKV == NULL, NO match\n");
            // Doesn't match
            if (mem.eql(u8, arg.leader, "") and mem.eql(u8, arg.rhs, ""))  {
                if (mem.eql(u8, arg.sep, "")) {
                    // TODO: add to list of positional parameters to return. 
                    warn("positional parameter={}\n", arg.lhs);
                    continue;
                } else {
                    warn("Unknown and empty named parameter, raw_arg={} parsed arg={}\n", raw_arg, arg);
                    return error.UnknownButEmptyNamedParameter;
                }
            } else {
                warn("Unknown option raw_arg={} parsed arg={}\n", raw_arg, arg);
                return error.UnknownOption;
            } 
        }

        // Got a match
        var v = pKV.?.value;
        warn("Match v={*} v.argU32.name={}\n", v, v.argU32.name);
        var leader: []const u8 =
            switch (v.*) {
                ArgProtoUnion.argU32 => |ap| ap.leader,
                else => "",
            };
        warn("Match: leader={}\n", leader);
        var value_default_set: bool =
            switch (v.*) {
                ArgProtoUnion.argU32 => |ap| ap.value_default_set,
                else => false,
            };
        warn("Match: value_default_set={}\n", value_default_set);
        var isa_option = if (!mem.eql(u8, arg.leader, "")) mem.eql(u8, arg.leader[0..], leader[0..]) else false;
        warn("Match: isa_option={}\n", isa_option);
        if (mem.eql(u8, arg.rhs, "")) {
            warn("No rhs\n");
            if (value_default_set) {
                switch (v.*) {
                    ArgProtoUnion.argU32 => |ap| {
                        v.argU32.value = ap.value_default;
                        v.argU32.value_set = false; // This wasn't set from command line
                    },
                    else => {
                        //v.argU32.value = 0;
                        //v.argU32.value_set = false;
                    },
                }
            } else {
                //warn("No default value for {} {}\n",
                //    if (isa_option) "option" else "named parameter", v.argU32);
                return error.NoDefaultValue;
            }
        } else {
            warn("rhs={}\n", arg.rhs);
            switch (v.*) {
                ArgProtoUnion.argU32 => {
                    warn("Is argU32\n");
                    v.argU32.value = try v.argU32.parser(arg.rhs[0..]);
                    v.argU32.value_set = true; // This was set from the command line
                    warn("v={*} v.argU32.value={} value_set={}\n", v, v.argU32.value, v.argU32.value_set);
                },
                else => {
                    //v.argU32.value = 0;
                    //v.argU32.value_set = false;
                },
            }
        }
    }
}

test "parseArgs.basic" {
    warn("\n");
    var param1 = ArgPrototype(u32) {
        .leader = "",
        .name = "count",
        .parser = parseU32,
        .value_default_set = false,
        .value_default = 0,
        .value_set = false,
        .value = 0,
    };
    warn("parseArgs.basic: &param1={*} &param1.name={*} param1.name={}\n", &param1, &param1.name, param1.name);
    var p1 = ArgProtoUnion {
        .argU32 = param1,
    };
    warn("parseArgs.basic: p1={*} &p1.argU32.name={*} p1.argU32.name={}\n", &p1, &p1.argU32.name, p1.argU32.name);

    // Copy p1 to paramsList
    var paramsList = ArrayList(ArgProtoUnion).init(debug.global_allocator);
    try paramsList.append(p1);
    warn("parseArgs.basic: &list[0]={*} ist[0].name={}\n", &paramsList.items[0], paramsList.items[0].argU32.name);

    var arg_iter: MyArgIterator = undefined;
    arg_iter.initTestAi([]const []const u8 {
        "abc",
        "count=123",
    });

    try parseArgs(debug.global_allocator, &arg_iter, paramsList);
    warn("parseArgs.basic: &paramsList.items[0]={*}, paramsList.items[0]argU32.value={} value_set={}\n",
            &paramsList.items[0], paramsList.items[0].argU32.value, paramsList.items[0].argU32.value_set);
}
