const std = @import("std");

const ASTNodeType = enum {
    regex,
    literal,
    digit,
    wildcard,
    whitespace,
    list,
    range,
    alternation,
    zero_or_one,
    zero_or_more,
    one_or_more,
    group,
    end_of_input,
};

pub const ASTNode = union(ASTNodeType) {
    const Self = @This();

    const Group = struct { nodes: usize, index: usize };
    const Alternation = struct { left: usize, right: usize };
    const List = struct { nodes: usize, negative: bool };
    const Range = struct { a: u8, b: u8 };

    regex: usize,
    literal: u8,
    digit: u8,
    whitespace: u8,
    list: List,
    range: Range,
    wildcard: u8,
    alternation: Alternation,
    zero_or_one: usize,
    zero_or_more: usize,
    one_or_more: usize,
    group: Group,
    end_of_input: u8,

    fn indent_str(amount: usize) void {
        var str: [64]u8 = .{};
        @memset(&str, ' ');
        std.debug.print("{s}", .{str[0..amount]});
    }

    pub fn pretty_print(self: *const Self, ophan_nodes: *std.ArrayList(ASTNode), node_lists: *std.ArrayList(std.ArrayList(ASTNode))) void {
        self.print(0, ophan_nodes, node_lists);
    }

    fn print(self: *const Self, indent: usize, orphan_nodes: *std.ArrayList(ASTNode), node_lists: *std.ArrayList(std.ArrayList(ASTNode))) void {
        switch (self.*) {
            .regex => {
                std.debug.print("regex: {{\n", .{});
                const nodes = &node_lists.items[self.regex];
                for (nodes.items) |node| {
                    print(&node, indent + 2, orphan_nodes, node_lists);
                }
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            .literal => {
                indent_str(indent);
                std.debug.print("lit({c})\n", .{self.literal});
            },
            .range => {
                indent_str(indent);
                std.debug.print("range({c}, {c})\n", .{ self.range.a, self.range.b });
            },
            .end_of_input => {
                indent_str(indent);
                std.debug.print("end_of_input\n", .{});
            },
            .digit => {
                indent_str(indent);
                std.debug.print("digit({c})\n", .{self.digit});
            },
            .whitespace => {
                indent_str(indent);
                std.debug.print("whitespace\n", .{});
            },
            .wildcard => {
                indent_str(indent);
                std.debug.print("wildcard\n", .{});
            },
            .group => {
                indent_str(indent);
                std.debug.print("group({d}): {{\n", .{self.group.index});
                const nodes = &node_lists.items[self.group.nodes];
                for (nodes.items) |node| {
                    print(&node, indent + 2, orphan_nodes, node_lists);
                }
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            .list => {
                indent_str(indent);
                if (self.list.negative) {
                    std.debug.print("negative_", .{});
                }
                std.debug.print("list: {{\n", .{});
                const nodes = &node_lists.items[self.list.nodes];
                for (nodes.items) |node| {
                    print(&node, indent + 2, orphan_nodes, node_lists);
                }
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            .alternation => {
                indent_str(indent);
                std.debug.print("alt: {{\n", .{});

                indent_str(indent + 2);
                std.debug.print("left: {{\n", .{});
                const left_nodes = &node_lists.items[self.alternation.left];
                for (left_nodes.items) |node| {
                    print(&node, indent + 4, orphan_nodes, node_lists);
                }
                indent_str(indent + 2);
                std.debug.print("}}\n", .{});

                indent_str(indent + 2);
                std.debug.print("right: {{\n", .{});
                const right_nodes = &node_lists.items[self.alternation.right];
                for (right_nodes.items) |node| {
                    print(&node, indent + 4, orphan_nodes, node_lists);
                }
                indent_str(indent + 2);
                std.debug.print("}}\n", .{});

                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            .zero_or_one => {
                indent_str(indent);
                std.debug.print("zero_or_one: {{\n", .{});
                print(&orphan_nodes.items[self.zero_or_one], indent + 2, orphan_nodes, node_lists);
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            .zero_or_more => {
                indent_str(indent);
                std.debug.print("zero_or_more: {{\n", .{});
                print(&orphan_nodes.items[self.zero_or_more], indent + 2, orphan_nodes, node_lists);
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            .one_or_more => {
                indent_str(indent);
                std.debug.print("one_or_more: {{\n", .{});
                print(&orphan_nodes.items[self.one_or_more], indent + 2, orphan_nodes, node_lists);
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
        }
    }
};
