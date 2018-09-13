# Zig parse arguments

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

# Improvements:

Allow addition of different "types" at compile time and
maybe runtime. Right now a tagged union ArgUnionFields is used
to manage different types of data that can be parsed. For new
"types" to be added ArgUnionFields and the appropriate code paths need
to be updated. It would be nicer if the programmer could add them
at comptime at a minimum and possibly at runtime.

## Test
```bash
$ zig test parse_args.zig
```

## Clean
Remove `zig-cache/` directory
```bash
$ rm -rf test ./zig-cache/
```
