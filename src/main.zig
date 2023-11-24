const std = @import("std");
const Allocator = std.mem.Allocator;

const Regex = @import("regex.zig").Regex;

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

    var re = try Regex.init(allocator, re_str);
    defer re.deinit();

    var match = try re.match(input) orelse {
        std.debug.print("Failed to match\n", .{});
        return;
    };
    defer match.deinit();

    std.debug.print("Match: {s}\n", .{match.match});

    var groups = try match.get_groups(allocator);
    defer groups.deinit();

    for (groups.items, 0..) |group, i| {
        if (group) |g| {
            std.debug.print("Group {d}: {s}\n", .{ i, g });
        } else {
            std.debug.print("Group {d}: <null>\n", .{i});
        }
    }
}
