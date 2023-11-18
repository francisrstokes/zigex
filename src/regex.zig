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

    var re_state = vm.State.init(allocator, &re.blocks, input, .{ .log = true });
    defer re_state.deinit();
    var match = try re_state.run();

    std.debug.print("{s} on input \"{s}\" -> {any}\n", .{ re_str, input, match });

    if (match) {
        std.debug.print("\n---------- Captures ----------\n", .{});

        std.debug.print("Match: {s}\n", .{input[0..re_state.state.index]});

        for (0..re.group_index) |group_index| {
            std.debug.print("Group {d}: {s}\n", .{ group_index, re_state.state.captures.get(group_index).? });
        }
    }
}

fn test_fully_matching_string(comptime re_str: []const u8, comptime input: []const u8, captures: []const []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    var re = try parser.Regex.init(allocator, re_str, .{});
    defer re.deinit();

    var re_state = vm.State.init(allocator, &re.blocks, input, .{});
    defer re_state.deinit();
    var match = try re_state.run();

    try expect(match);
    try expect(std.mem.eql(u8, re_state.get_match(), input));

    try expect(re_state.state.captures.count() == captures.len);
    var i: usize = 0;
    while (i < captures.len) : (i += 1) {
        try expect(std.mem.eql(u8, captures[i], re_state.state.captures.get(i).?));
    }
}

test "a" {
    try test_fully_matching_string("a", "a", &.{});
}

test "a+" {
    try test_fully_matching_string("a+", "aaaaaaa", &.{});
}

test ".+b" {
    try test_fully_matching_string(".+b", "aaaaaaab", &.{});
}

test "a|b" {
    try test_fully_matching_string("a|b", "a", &.{});
    try test_fully_matching_string("a|b", "b", &.{});
}

test "(a|b)?c" {
    try test_fully_matching_string("(a|b)?c", "ac", &.{"a"});
    try test_fully_matching_string("(a|b)?c", "bc", &.{"b"});
}

test ".+b|\\d" {
    try test_fully_matching_string(".+b|\\d", "aaaaaaa5", &.{});
}

test "((.).)" {
    try test_fully_matching_string("((.).)", "ab", &.{ "ab", "a" });
}

test "((...)(...)+)" {
    try test_fully_matching_string("((...)(...)+)", "abcdef123", &.{ "abcdef123", "abc", "123" });
}
