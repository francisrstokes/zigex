const std = @import("std");
const Allocator = std.mem.Allocator;

const compiler_common = @import("common.zig");
const ASTNode = compiler_common.ASTNode;

const tokeniser = @import("tokeniser.zig");
const TokenStream = tokeniser.TokenStream;
const Token = tokeniser.Token;

const NodeLists = std.ArrayList(std.ArrayList(ASTNode));

pub const ParsedRegex = struct {
    const Self = @This();

    ast: ASTNode,
    node_lists: NodeLists,
    ophan_nodes: std.ArrayList(ASTNode),

    pub fn deinit(self: *Self) void {
        for (self.node_lists.items) |node_list| {
            node_list.deinit();
        }
        self.node_lists.deinit();
        self.ophan_nodes.deinit();
    }
};

const ParseState = struct {
    in_alternation: bool = false,
    in_list: bool = false,
    is_negative: bool = false,
    alternation_index: usize = 0,
    group_index: usize = 0,
    nodes: usize,
};

const RegexError = error{ParseError};

fn to_quantifier_node(token: Token, greedy: bool, child_index: usize) !ASTNode {
    switch (token.tok_type) {
        .zero_or_one => return ASTNode{ .zero_or_one = .{ .greedy = greedy, .node = child_index } },
        .zero_or_more => return ASTNode{ .zero_or_more = .{ .greedy = greedy, .node = child_index } },
        .one_or_more => return ASTNode{ .one_or_more = .{ .greedy = greedy, .node = child_index } },
        else => return error.Unreachable,
    }
}

pub const Parser = struct {
    const Self = @This();

    group_index: usize,

    fn maybe_parse_and_wrap_quantifier(node: ASTNode, tokens: *TokenStream, ophan_nodes: *std.ArrayList(ASTNode)) !?ASTNode {
        if (tokens.peek(0)) |next_token| {
            if (next_token.is_quantifier()) {
                var greedy = true;

                if (tokens.peek(1)) |next_next_token| {
                    greedy = next_next_token.tok_type != .zero_or_one;
                }

                const quantifier_token = try tokens.consume();
                if (!greedy) {
                    _ = try tokens.consume();
                }

                try ophan_nodes.append(node);
                var child_index = ophan_nodes.items.len - 1;

                return try to_quantifier_node(quantifier_token, greedy, child_index);
            }
        }
        return null;
    }

    fn maybe_parse_rangenode(node: ASTNode, tokens: *TokenStream) !?ASTNode {
        if (tokens.peek(0)) |next_token| {
            if (tokens.peek(1)) |next_next_token| {
                if (next_token.tok_type == .dash) {
                    if (next_next_token.can_be_range_literal()) {
                        _ = try tokens.consume();
                        const range_token = try tokens.consume();

                        if (range_token.value < node.literal) {
                            std.debug.print("Invalid range: {c} to {c}\n", .{ node.literal, range_token.value });
                            return error.ParseError;
                        }

                        return ASTNode{ .range = .{ .a = node.literal, .b = range_token.value } };
                    }
                }
            }
        }
        return null;
    }

    fn maybe_parse_hex_literal(tokens: *TokenStream) !?ASTNode {
        if (tokens.peek(0)) |next_token| {
            if (tokens.peek(1)) |next_next_token| {
                const both_literals = next_token.tok_type == .literal and next_next_token.tok_type == .literal;
                if (both_literals) {
                    if (is_hex_char(next_token.value)) {
                        _ = try tokens.consume();
                        var hex_str: [2]u8 = .{ '0', '0' };
                        if (is_hex_char(next_next_token.value)) {
                            _ = try tokens.consume();
                            hex_str[0] = next_token.value;
                            hex_str[1] = next_next_token.value;
                        } else {
                            hex_str[1] = next_token.value;
                        }

                        const byte_value = try std.fmt.parseInt(u8, &hex_str, 16);
                        return ASTNode{ .literal = byte_value };
                    }
                }
            }
        }
        return null;
    }

    fn parse_node(self: *Self, token: Token, current_state: *ParseState, tokens: *TokenStream, ophan_nodes: *std.ArrayList(ASTNode), node_lists: *NodeLists, state_stack: *std.ArrayList(ParseState)) !void {
        // Ugly, but saves on passing in another argument.
        const allocator = ophan_nodes.allocator;

        switch (token.tok_type) {
            .literal => {
                var node = ASTNode{ .literal = token.value };
                if (current_state.in_list) {
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                if (try maybe_parse_and_wrap_quantifier(node, tokens, ophan_nodes)) |quantifier_node| {
                    try node_lists.items[current_state.nodes].append(quantifier_node);
                } else {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .dollar => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                var node = ASTNode{ .end_of_input = 0 };
                try node_lists.items[current_state.nodes].append(node);
                return;
            },
            .escaped => {
                var node: ASTNode = undefined;
                switch (token.value) {
                    'd' => node = ASTNode{ .digit = 0 },
                    's' => node = ASTNode{ .whitespace = 0 },
                    'x' => {
                        if (try maybe_parse_hex_literal(tokens)) |n| {
                            node = n;
                        } else {
                            node = ASTNode{ .literal = 0 };
                        }
                    },
                    else => node = ASTNode{ .literal = token.value },
                }

                if (current_state.in_list) {
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                if (try maybe_parse_and_wrap_quantifier(node, tokens, ophan_nodes)) |quantifier_node| {
                    try node_lists.items[current_state.nodes].append(quantifier_node);
                } else {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .wildcard => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                var node = ASTNode{ .wildcard = 0 };
                if (try maybe_parse_and_wrap_quantifier(node, tokens, ophan_nodes)) |quantifier_node| {
                    try node_lists.items[current_state.nodes].append(quantifier_node);
                } else {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .lsquare => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                try state_stack.append(current_state.*);
                var is_negative = false;

                if (tokens.peek(0)) |peeked_token| {
                    if (peeked_token.tok_type == .caret) {
                        _ = try tokens.consume();
                        is_negative = true;
                    }
                }

                try node_lists.append(std.ArrayList(ASTNode).init(allocator));
                const new_nodes_index = node_lists.items.len - 1;

                current_state.nodes = new_nodes_index;
                current_state.in_list = true;
                current_state.is_negative = is_negative;

                return;
            },
            .rsquare => {
                var node = ASTNode{ .list = .{ .nodes = current_state.nodes, .negative = current_state.is_negative } };
                current_state.* = state_stack.pop();

                if (try maybe_parse_and_wrap_quantifier(node, tokens, ophan_nodes)) |quantifier_node| {
                    try node_lists.items[current_state.nodes].append(quantifier_node);
                } else {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .lparen => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                try state_stack.append(current_state.*);

                try node_lists.append(std.ArrayList(ASTNode).init(allocator));
                const new_nodes_index = node_lists.items.len - 1;
                current_state.* = .{ .nodes = new_nodes_index, .group_index = self.group_index };
                self.group_index += 1;
                return;
            },
            .rparen => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                const copy_index = if (current_state.in_alternation) current_state.alternation_index else current_state.nodes;
                try node_lists.append(try node_lists.items[copy_index].clone());
                var group_nodes_index = node_lists.items.len - 1;

                var node = ASTNode{ .group = .{ .index = current_state.group_index, .nodes = group_nodes_index } };
                current_state.* = state_stack.pop();

                if (try maybe_parse_and_wrap_quantifier(node, tokens, ophan_nodes)) |quantifier_node| {
                    try node_lists.items[current_state.nodes].append(quantifier_node);
                } else {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .alternation => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                // Copy all the existing nodes to what will become the left branch of this alternation.
                try node_lists.append(try node_lists.items[current_state.nodes].clone());
                var left_nodes_index = node_lists.items.len - 1;

                // Create an empty list for the right branch of this alternation.
                try node_lists.append(std.ArrayList(ASTNode).init(allocator));
                var right_nodes_index = node_lists.items.len - 1;

                // Create the alternation node, free everything that was in the current node list, and add this node
                var node = ASTNode{ .alternation = .{ .left = left_nodes_index, .right = right_nodes_index } };
                node_lists.items[current_state.nodes].clearAndFree();
                try node_lists.items[current_state.nodes].append(node);

                // Mark that we're in an alternation state.
                // If we already happen to be in an alternation state, then we want to keep the alternation_index set
                // to the original, since it represents the root of the tree that also covers this alternation.
                current_state.alternation_index = if (current_state.in_alternation) current_state.alternation_index else current_state.nodes;
                current_state.in_alternation = true;

                // Finally set the new current node list to the right branch of the alternation.
                current_state.nodes = right_nodes_index;

                return;
            },
            else => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (try maybe_parse_rangenode(node, tokens)) |range_node| {
                        try node_lists.items[current_state.nodes].append(range_node);
                    } else {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                std.debug.print("Unexpected quantifier: {any}\n", .{token});
                @panic("unreachable");
            },
            // else => @panic("unreachable"),
        }
    }

    pub fn parse(allocator: Allocator, tokens: *TokenStream) !ParsedRegex {
        var self = Self{ .group_index = 0 };

        // We need a home for nodes that are pointed to by other nodes. When we come to deinit the
        // AST, we can walk the AST itself and deinit all the ArrayLists we find along the way, and
        // then free the ophan_nodes ArrayList.
        var ophan_nodes = std.ArrayList(ASTNode).init(allocator);
        var node_lists = NodeLists.init(allocator);

        try node_lists.append(std.ArrayList(ASTNode).init(allocator));
        var root_node = ASTNode{ .regex = node_lists.items.len - 1 };

        var current_state = ParseState{ .nodes = root_node.regex };
        var state_stack = std.ArrayList(ParseState).init(allocator);
        defer state_stack.deinit();

        while (tokens.available() > 0) {
            const token = try tokens.consume();
            try self.parse_node(token, &current_state, tokens, &ophan_nodes, &node_lists, &state_stack);
        }

        return ParsedRegex{ .ast = root_node, .ophan_nodes = ophan_nodes, .node_lists = node_lists };
    }
};

fn is_hex_char(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}
