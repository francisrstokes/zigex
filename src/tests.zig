const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const Regex = @import("regex.zig").Regex;

fn test_fully_matching_string(comptime re_str: []const u8, comptime input: []const u8, captures: []const []const u8) !void {
    const allocator = std.testing.allocator;

    var re = try Regex.init(allocator, re_str);
    defer re.deinit();

    var match = try re.match(input);
    defer match.?.deinit();

    try expect(match != null);
    try expect(std.mem.eql(u8, match.?.match, input));

    var groups = try match.?.get_groups(allocator);
    defer groups.deinit();

    try expect(groups.items.len == captures.len);
    for (0..captures.len) |i| {
        try expect(std.mem.eql(u8, captures[i], groups.items[i]));
    }
}

fn test_non_matching_string(comptime re_str: []const u8, comptime input: []const u8) !void {
    const allocator = std.testing.allocator;

    var re = try Regex.init(allocator, re_str);
    defer re.deinit();

    var match = try re.match(input);
    try expect(match == null);
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
    try test_fully_matching_string("(a|b)?c", "c", &.{});
}

test ".+b|\\d" {
    try test_fully_matching_string(".+b|\\d", "aaaaaaab", &.{});
    try test_fully_matching_string(".+b|\\d", "1", &.{});
}

test ".+(b|\\d)" {
    try test_fully_matching_string(".+(b|\\d)", "aaaaaaa5", &.{"5"});
}

test "((.).)" {
    try test_fully_matching_string("((.).)", "ab", &.{ "ab", "a" });
}

test "((...)(...)+)" {
    try test_fully_matching_string("((...)(...)+)", "abcdef123", &.{ "abcdef123", "abc", "123" });
}

test "[a]" {
    try test_fully_matching_string("[a]", "a", &.{});
}

test "[abc]" {
    try test_fully_matching_string("[abc]", "a", &.{});
    try test_fully_matching_string("[abc]", "b", &.{});
    try test_fully_matching_string("[abc]", "c", &.{});
    try test_non_matching_string("[abc]", "d");
}

test "0x[0-9a-f]+$" {
    try test_fully_matching_string("0x[0-9a-f]+$", "0xdeadbeef", &.{});
    try test_fully_matching_string("0x[0-9a-f]+$", "0xc0decafe", &.{});
    try test_non_matching_string("0x[0-9a-f]+$", "0xcodecafe");
}

test "[a-\\d]" {
    try test_fully_matching_string("[a-\\d]", "a", &.{});
    try test_fully_matching_string("[a-\\d]", "b", &.{});
    try test_fully_matching_string("[a-\\d]", "c", &.{});
    try test_fully_matching_string("[a-\\d]", "d", &.{});
    try test_non_matching_string("[a-\\d]", "e");
}

test "[^abc]" {
    try test_non_matching_string("[^abc]", "a");
    try test_non_matching_string("[^abc]", "b");
    try test_non_matching_string("[^abc]", "c");
    try test_fully_matching_string("[^abc]", "d", &.{});
    try test_fully_matching_string("[^abc]", "$", &.{});
}
