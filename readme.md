# zigex

`zigex` is a regular expression library for [Zig](https://github.com/ziglang/zig/).

**⚠️ Warning ⚠️**: This is not a production-ready library. It is incomplete and minimally documented.

## Installation (git submodule)

1. Add the repo as a submodule to your project. Place it `libs/` at the root of your project:

```bash
git submodule add https://github.com/francisrstokes/zigex libs/zigex
```

2. Add the library as a module to your projects `build.zig`:

```zig
exe.addAnonymousModule("zigex", .{
    .source_file = .{ .path = "libs/zigex/src/regex.zig" },
});
```

3. Import in your project source:

```zig
const zigex = @import("zigex");

...

var re = try zigex.Regex.init(your_allocator, "(a.+\\d)?(x|y)$", .{});
defer re.deinit();

var match = try re.match("aHelloWorld1y") orelse {
    std.debug.print("No match\n", .{});
    return;
};
defer match.deinit();

std.debug.print("Match: \"{s}\" index={d}\n", .{match.match.value, match.match.index});

var groups = try match.get_groups(your_allocator);
defer groups.deinit();

for (groups.items, 1..) |group, i| {
    if (group) |g| {
        std.debug.print("Group {d}: \"{s}\" index={d}\n", .{ i, g.value, g.index });
    } else {
        std.debug.print("Group {d}: <null>\n", .{i});
    }
}
```

4. Build and run

```bash
$ zig build
$ ./zig-out/bin/your-app

Match: aHelloWorld1y
Group 1: "aHelloWorld1" index=0
Group 2: "y" index=12
```
