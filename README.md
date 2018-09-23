# Zig parse arguments

I don't like this that much, I think instead of parsing
the arguments directly to Types it should probably just
stay as strings and then any type specific parsing is done
later. This is what src-self-hosted/arg.zig does and overall
src-self-hosted/arg.zig is better execpt I like "name=value"
pairs rather than "--flag value" syntax.

An interesting technique in src-self-host/arg.zig is creating
a struct with different constructors initializing fields
differently without using "comptime T: type". This allows
straight forward creation of arrays without the need for tagged
unions or a "common interface" and @fieldParentPtr.

ParseNumber seems pretty good with the optional "\_" seperator.

# Improvements:

Allow addition of different "types" at compile time and
maybe runtime. Right now a tagged union ArgUnionFields is used
to manage different types of data that can be parsed. For new
"types" to be added ArgUnionFields and the appropriate code paths need
to be updated. It would be nicer if the programmer could add them
at comptime at a minimum and possibly at runtime.

in the use-ArgRecCommon I tried using the "common interface" and
@fieldParentPtr technique but that really didn't help, at least I
couldn't make it really extensible at compile time.

# Current

Parse the parameters passed on the command line
and available in osArgIter: std.os.ArgIterator and
well as my own ArgIteratorTest. Both are avaiable via
the wrapper ArgIter:

    ArgIter.initOsArgIter() Self
    ArgIter.initTestArgIter(args: []const []const u8) Self

Besides the iterator with the command line arguments you
need to create an ArrayList(ArgRec) and initialize the list
with a "prototype" for each possible command line argument.

See the tests in parse_args.zig and test_app.zig for details,
I'm not going to add doc's here yet, because I don't like the
API. I need to make the improvments mentioned below.

## Test
```bash
$ zig test parse_args.zig
```

## Clean
Remove `zig-cache/` directory
```bash
$ rm -rf test ./zig-cache/
```
