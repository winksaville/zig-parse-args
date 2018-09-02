const std = @import("std");
const warn = std.debug.warn;
const args = std.os.args;
const fmt = std.fmt;
const mem = std.mem;

const Allocator = mem.Allocator;
const parseInt = std.fmt.parseInt;
const parseUnsiged = std.fmt.parseUnsigned;

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
        parser: fn (T, []const u8) !T,  /// Parse the []const u8 to T
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

pub fn parseDecInt(comptime T: type, value_str: []const u8) !T {
    return parseInt(T, value_str, 10);
}

pub fn parseFloat(comptime T: type, value_str: []const u8) !T {
    @panic("Not implemented");
}

pub fn parseStr(comptime T: type, value_str: []const u8) !T {
    if (false) error.WTF;
    return value_str;
}

pub fn parseArgs(
    pAllocator: *Allocator,
    args_it: ArgsIterator,
    arg_proto_list: ArrayList(ArgProtoUnion),
) !void {
    if (!args_it.skip()) @panic("expected arg[0] to exist");

    // Add the arg_prototypes to a hash map
    const ArgProtoMap = HashMap([]const u8, ArgProtoUnion,
                            mem.hash_slice_u8, mem.eql_slice_u8);
    var arg_proto_map = HashMap(ArgProtoMap).init();
    for (arg_proto_list) |arg_proto, i| {
        if (arg_proto_map.contains(arg_proto.name)) {
            warn("{} exists arg_proto_list[{}]={}",
                arg_proto.name, i, arg_proto_map.get(arg_proto.name).?);
            return error.ArgProtoDuplicate;
        }
        var r = try arg_proto_map.put(arg_proto.name, arg_proto);
        if (r != null) {
            return error.ArgProtoDuplicateWhenThereShouldNotBeAnDuplicate;
        }
    }
    
    while (args_it.next(pAllocator)) |arg_or_error| {
        var raw_arg = try arg_or_error;
        var arg = parseArg("--", raw_arg, "=");
        var pR = arg_proto.map.get(arg.lhs);
        if (pR == null) {
            if (mem.eql(arg.leader, "") and mem.eql(arg.rhs = ""))  {
                if (mem.eql(arg.sep, "")) {
                    // TODO: add to list of positional parameters to return. 
                    warn("positional parameter={}\n", arg.name);
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
        isa_option = mem.eql(u8, arg.leader[0..], arg_proto.leader[0..]);
        if (mem.eql(arg_proto.rhs, "")) {
            if (arg_proto.value_default_set) {
                arg_proto.value = arg_proto.value_default;
            } else {
                warn("No default value for {} {}\n",
                    if (is_option) "option" else "named parameter", arg_proto);
                return error.NoDefaultValue;
            }
        } else {
            arg_proto.value = try ArgPrototype.parser(arg.rhs[0..]);
            arg_proto.value_set = true;
        }
    }
}

test "parseArgs.basic" {
}
