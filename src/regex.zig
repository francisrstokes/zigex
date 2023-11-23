const std = @import("std");
const Allocator = std.mem.Allocator;

const Compiled = @import("compiler.zig").Compiled;
const VMInstance = @import("vm.zig").VMInstance;

pub const MatchObject = struct {
    const Self = @This();

    groups: std.AutoHashMap(usize, []const u8),
    match: []const u8,

    pub fn get_match(self: *Self) []u8 {
        return self.match;
    }

    pub fn get_group(self: *Self, group: usize) ![]u8 {
        return self.groups.get(group);
    }

    pub fn get_groups(self: *Self, allocator: Allocator) !std.ArrayList([]const u8) {
        var array = std.ArrayList([]const u8).init(allocator);
        for (0..self.groups.count()) |i| {
            if (self.groups.get(i)) |value| {
                try array.append(value);
            }
        }
        return array;
    }

    pub fn deinit(self: *Self) void {
        self.groups.deinit();
    }
};

pub const Regex = struct {
    const Self = @This();

    allocator: Allocator,
    compiled: Compiled,

    pub fn init(allocator: Allocator, regular_expression: []const u8) !Self {
        return .{
            .allocator = allocator,
            .compiled = try Compiled.init(allocator, regular_expression, .{}),
        };
    }

    pub fn match(self: *Self, input: []const u8) !?MatchObject {
        var vm_instance = VMInstance.init(self.allocator, &self.compiled.blocks, input, .{});
        defer vm_instance.deinit();
        const matched = try vm_instance.run();

        if (!matched) {
            return null;
        }

        return MatchObject{ .groups = vm_instance.state.captures.move(), .match = vm_instance.get_match() };
    }

    pub fn deinit(self: *Self) void {
        self.compiled.deinit();
    }
};
