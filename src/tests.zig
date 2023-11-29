const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const Regex = @import("regex.zig").Regex;

fn test_fully_matching_string(comptime re_str: []const u8, comptime input: []const u8, index: usize, captures: []const ?[]const u8) !void {
    const allocator = std.testing.allocator;

    var re = try Regex.init(allocator, re_str, .{});
    defer re.deinit();

    var match = try re.match(input);
    defer match.?.deinit();

    try expect(match != null);
    try expect(std.mem.eql(u8, match.?.match.value, input));
    try expect(index == match.?.match.index);

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

fn test_partially_matching_string(comptime re_str: []const u8, comptime input: []const u8, index: usize, partial: []const u8, captures: []const ?[]const u8) !void {
    const allocator = std.testing.allocator;

    var re = try Regex.init(allocator, re_str, .{});
    defer re.deinit();

    var match = try re.match(input);
    defer match.?.deinit();

    try expect(match != null);
    try expect(std.mem.eql(u8, match.?.match.value, partial));
    try expect(match.?.match.index == index);

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
    try test_fully_matching_string("a", "a", 0, &.{});
}

test "a+" {
    try test_fully_matching_string("a+", "aaaaaaa", 0, &.{});
}

test ".+b" {
    try test_fully_matching_string(".+b", "aaaaaaab", 0, &.{});
}

test "a|b" {
    try test_fully_matching_string("a|b", "a", 0, &.{});
    try test_fully_matching_string("a|b", "b", 0, &.{});
}

test "(a|b)?c" {
    try test_fully_matching_string("(a|b)?c", "ac", 0, &.{"a"});
    try test_fully_matching_string("(a|b)?c", "bc", 0, &.{"b"});
    try test_fully_matching_string("(a|b)?c", "c", 0, &.{null});
}

test ".+b|\\d" {
    try test_fully_matching_string(".+b|\\d", "aaaaaaab", 0, &.{});
    try test_fully_matching_string(".+b|\\d", "1", 0, &.{});
}

test ".+(b|\\d)" {
    try test_fully_matching_string(".+(b|\\d)", "aaaaaaa5", 0, &.{"5"});
}

test "((.).)" {
    try test_fully_matching_string("((.).)", "ab", 0, &.{ "ab", "a" });
}

test "((...)(...)+)" {
    try test_fully_matching_string("((...)(...)+)", "abcdef123", 0, &.{ "abcdef123", "abc", "123" });
}

test "[a]" {
    try test_fully_matching_string("[a]", "a", 0, &.{});
}

test "[abc]" {
    try test_fully_matching_string("[abc]", "a", 0, &.{});
    try test_fully_matching_string("[abc]", "b", 0, &.{});
    try test_fully_matching_string("[abc]", "c", 0, &.{});
    try test_non_matching_string("[abc]", "d");
}

test "0x[0-9a-f]+$" {
    try test_fully_matching_string("0x[0-9a-f]+$", "0xdeadbeef", 0, &.{});
    try test_fully_matching_string("0x[0-9a-f]+$", "0xc0decafe", 0, &.{});
    try test_non_matching_string("0x[0-9a-f]+$", "0xcodecafe");
}

test "[a-\\d]" {
    try test_fully_matching_string("[a-\\d]", "a", 0, &.{});
    try test_fully_matching_string("[a-\\d]", "b", 0, &.{});
    try test_fully_matching_string("[a-\\d]", "c", 0, &.{});
    try test_fully_matching_string("[a-\\d]", "d", 0, &.{});
    try test_non_matching_string("[a-\\d]", "e");
}

test "[^abc]" {
    try test_non_matching_string("[^abc]", "a");
    try test_non_matching_string("[^abc]", "b");
    try test_non_matching_string("[^abc]", "c");
    try test_fully_matching_string("[^abc]", "d", 0, &.{});
    try test_fully_matching_string("[^abc]", "$", 0, &.{});
}

test "[^a-z\\s\\d]+" {
    try test_non_matching_string("[^a-z\\s\\d]+", "a");
    try test_non_matching_string("[^a-z\\s\\d]+", "z");
    try test_non_matching_string("[^a-z\\s\\d]+", " ");
    try test_non_matching_string("[^a-z\\s\\d]+", "5");
    try test_fully_matching_string("[^a-z\\s\\d]+", "!@#$%^&*()[]{}", 0, &.{});
    try test_fully_matching_string("[^a-z\\s\\d]+", "ABC", 0, &.{});
}

test "a\\sb$" {
    try test_fully_matching_string("a\\sb$", "a b", 0, &.{});
    try test_non_matching_string("a\\sb$", "a.b");
}

test "a\\sb\\s*c\\s+d$" {
    try test_fully_matching_string("a\\sb\\s?c\\s+d$", "a b\tc\r\x0c\n\n   d", 0, &.{});
}

test "\\x40+" {
    try test_fully_matching_string("\\x40+", "@@@@", 0, &.{});
}

test "\\xcz$" {
    const input: [2]u8 = .{ 0x0c, 'z' };
    try test_fully_matching_string("\\xcz$", &input, 0, &.{});
}

test "\\xz$" {
    const input: [2]u8 = .{ 0, 'z' };
    try test_fully_matching_string("\\xz$", &input, 0, &.{});
}

test "(a*)*" {
    try test_fully_matching_string("(a*)*", "", 0, &.{null});
    try test_fully_matching_string("(a*)*", "a", 0, &.{"a"});
    try test_fully_matching_string("(a*)*", "aaaa", 0, &.{"aaaa"});
}

test "<(.+)>" {
    try test_fully_matching_string("<(.+)>", "<html>xyz</html>", 0, &.{"html>xyz</html"});
}

test "<(.+?)>" {
    try test_partially_matching_string("<(.+?)>", "<html>xyz</html>", 0, "<html>", &.{"html"});
}

test ".*a" {
    try test_fully_matching_string(".*a", "bbbbbaa", 0, &.{});
}

test ".*?a" {
    try test_partially_matching_string(".*?a", "bbbbbaa", 0, "bbbbba", &.{});
}

test "a?." {
    try test_fully_matching_string("a?.", "ab", 0, &.{});
    try test_fully_matching_string("a?.", "a", 0, &.{});
    try test_fully_matching_string("a?.", "b", 0, &.{});
}

test ".??a" {
    try test_partially_matching_string(".??a", "ab", 0, "a", &.{});
    try test_fully_matching_string("a??.", "a", 0, &.{});
    try test_fully_matching_string("a??.", "b", 0, &.{});
}

test "abc" {
    try test_fully_matching_string("abc", "abc", 0, &.{});
    try test_partially_matching_string("abc", "xyzabc", 3, "abc", &.{});
}

test "([a-z])-" {
    try test_fully_matching_string("([a-z])-", "a-", 0, &.{"a"});
}

test "\\w" {
    try test_non_matching_string("\\w", "!@#$%^&*()-+=`~./<>?\\|{}[]");
}

test "\\w+" {
    try test_fully_matching_string("\\w+", "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", 0, &.{});
}

test "\\W+" {
    try test_fully_matching_string("\\W+", "!@#$%^&*()-+=`~./<>?\\|{}[]", 0, &.{});
}

test "\\W" {
    try test_non_matching_string("\\W", "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");
}

test "\\S" {
    try test_non_matching_string("\\S", " \t\r\x0c\n");
    try test_fully_matching_string("\\S", "a", 0, &.{});
}

test "\\D" {
    try test_non_matching_string("\\D", "0123456789");
    try test_fully_matching_string("\\D", "a", 0, &.{});
}
