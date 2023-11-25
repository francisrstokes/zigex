const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const Regex = @import("regex.zig").Regex;

fn test_fully_matching_string(comptime re_str: []const u8, comptime input: []const u8, captures: []const ?[]const u8) !void {
    const allocator = std.testing.allocator;

    var re = try Regex.init(allocator, re_str, .{});
    defer re.deinit();

    var match = try re.match(input);
    defer match.?.deinit();

    try expect(match != null);
    try expect(std.mem.eql(u8, match.?.match, input));

    var groups = try match.?.get_groups(allocator);
    defer groups.deinit();

    try expect(groups.items.len == captures.len);
    for (0..captures.len) |i| {
        const capture_null = captures[i] == null;
        const group_null = groups.items[i] == null;

        try expect(capture_null == group_null);

        if (!capture_null) {
            const capture_str = captures[i].?;
            const group_str = groups.items[i].?.value;
            const strings_equal = std.mem.eql(u8, capture_str, group_str);
            _ = try expect(strings_equal);
        }
    }
}

fn test_non_matching_string(comptime re_str: []const u8, comptime input: []const u8) !void {
    const allocator = std.testing.allocator;

    var re = try Regex.init(allocator, re_str, .{});
    defer re.deinit();

    var match = try re.match(input);
    try expect(match == null);
}

test "1-Indexed groups" {
    const allocator = std.testing.allocator;

    const re_str = "((a)(.))c";
    const input = "abc";

    var re = try Regex.init(allocator, re_str, .{});
    defer re.deinit();

    var match = (try re.match(input)).?;
    defer match.deinit();

    const group1 = (try match.get_group(1)).?.value;
    const group2 = (try match.get_group(2)).?.value;

    try expect(std.mem.eql(u8, group1, "ab"));
    try expect(std.mem.eql(u8, group2, "a"));
}

test "Group capture index information" {
    const allocator = std.testing.allocator;

    const re_str = "\\d+(...)";
    const input = "12345abc";

    var re = try Regex.init(allocator, re_str, .{});
    defer re.deinit();

    var match = (try re.match(input)).?;
    defer match.deinit();

    const group = (try match.get_group(1)).?;

    try expect(std.mem.eql(u8, group.value, "abc"));
    try expect(group.index == 5);
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
    try test_fully_matching_string("(a|b)?c", "c", &.{null});
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

test "a\\sb$" {
    try test_fully_matching_string("a\\sb$", "a b", &.{});
    try test_non_matching_string("a\\sb$", "a.b");
}

test "a\\sb\\s*c\\s+d$" {
    try test_fully_matching_string("a\\sb\\s?c\\s+d$", "a b\tc\r\x0c\n\n   d", &.{});
}

test "\\x40+" {
    try test_fully_matching_string("\\x40+", "@@@@", &.{});
}

test "\\xcz$" {
    const input: [2]u8 = .{ 0x0c, 'z' };
    try test_fully_matching_string("\\xcz$", &input, &.{});
}

test "\\xz$" {
    const input: [2]u8 = .{ 0, 'z' };
    try test_fully_matching_string("\\xz$", &input, &.{});
}

test "(a*)*" {
    try test_fully_matching_string("(a*)*", "", &.{null});
    try test_fully_matching_string("(a*)*", "a", &.{"a"});
    try test_fully_matching_string("(a*)*", "aaaa", &.{"aaaa"});
}
