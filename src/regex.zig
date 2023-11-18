const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const parser = @import("parser.zig");
const vm = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <regex> <input>\n", .{args[0]});
        std.process.exit(1);
        return;
    }

    const re_str = args[1];
    const input = args[2];

    std.debug.print("Regex: {s}\n", .{re_str});
    std.debug.print("Input: \"{s}\"\n", .{input});

    var re = try parser.Regex.init(allocator, re_str, .{ .dump_ast = true, .dump_blocks = true });
    defer re.deinit();

    var re_state = vm.State.init(allocator, &re.blocks, input);
    defer re_state.deinit();
    var match = try re_state.run();

    std.debug.print("{s} on input \"{s}\" -> {any}\n", .{ re_str, input, match });

    if (match) {
        std.debug.print("\n---------- Captures ----------\n", .{});

        std.debug.print("Match: {s}\n", .{input[0..re_state.state.index]});

        var i: usize = 1;
        for (re_state.state.captures.items) |capture| {
            std.debug.print("Group {d}: {s}\n", .{ i, capture });
            i += 1;
        }
    }
}

test "a" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    const input_str = "a";
    const regex_str = "a";

    var re = parser.Regex.init(allocator, regex_str);
    defer re.deinit();

    var tokens = try re.tokenise();
    defer tokens.deinit();

    var AST = try re.parse(tokens);
    defer AST.deinit();

    try re.compile(AST.root);

    var re_state = vm.State.init(allocator, &re.blocks, input_str);
    defer re_state.deinit();

    var match = try re_state.run();

    try expect(match);
}
