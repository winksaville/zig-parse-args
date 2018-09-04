# Zig parse arguments

Parse an ArrayList([]const u8) arguments

TODO: Support negative numbers.

TODO: Support operating system paramets.

TODO: Support floating point numbers.

TODO: Allow addition of different "types" at compile time and
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
$ rm -rf ./zig-cache/
```
