const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const vm = @import("vm.zig");

const TokenType = enum { literal, escaped, wildcard, lparen, rparen, alternation, zero_or_one, zero_or_more, one_or_more, lsquare, rsquare, dollar, caret, dash };

const Token = struct {
    tok_type: TokenType,
    value: u8 = 0,

    pub fn is_quantifier(self: Token) bool {
        return (self.tok_type == TokenType.zero_or_one) or (self.tok_type == TokenType.zero_or_more) or (self.tok_type == TokenType.one_or_more);
    }

    pub fn to_quantifier_node(self: Token, child_index: usize) !ASTNode {
        switch (self.tok_type) {
            TokenType.zero_or_one => return ASTNode{ .zero_or_one = child_index },
            TokenType.zero_or_more => return ASTNode{ .zero_or_more = child_index },
            TokenType.one_or_more => return ASTNode{ .one_or_more = child_index },
            else => return error.Unreachable,
        }
    }

    pub fn can_be_range_literal(self: Token) bool {
        return self.tok_type != TokenType.rsquare;
    }
};

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

const ASTNode = union(ASTNodeType) {
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
            ASTNodeType.regex => {
                std.debug.print("regex: {{\n", .{});
                const nodes = &node_lists.items[self.regex];
                for (nodes.items) |node| {
                    print(&node, indent + 2, orphan_nodes, node_lists);
                }
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            ASTNodeType.literal => {
                indent_str(indent);
                std.debug.print("lit({c})\n", .{self.literal});
            },
            ASTNodeType.range => {
                indent_str(indent);
                std.debug.print("range({c}, {c})\n", .{ self.range.a, self.range.b });
            },
            ASTNodeType.end_of_input => {
                indent_str(indent);
                std.debug.print("end_of_input\n", .{});
            },
            ASTNodeType.digit => {
                indent_str(indent);
                std.debug.print("digit({c})\n", .{self.digit});
            },
            ASTNodeType.whitespace => {
                indent_str(indent);
                std.debug.print("whitespace\n", .{});
            },
            ASTNodeType.wildcard => {
                indent_str(indent);
                std.debug.print("wildcard\n", .{});
            },
            ASTNodeType.group => {
                indent_str(indent);
                std.debug.print("group({d}): {{\n", .{self.group.index});
                const nodes = &node_lists.items[self.group.nodes];
                for (nodes.items) |node| {
                    print(&node, indent + 2, orphan_nodes, node_lists);
                }
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            ASTNodeType.list => {
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
            ASTNodeType.alternation => {
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
            ASTNodeType.zero_or_one => {
                indent_str(indent);
                std.debug.print("zero_or_one: {{\n", .{});
                print(&orphan_nodes.items[self.zero_or_one], indent + 2, orphan_nodes, node_lists);
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            ASTNodeType.zero_or_more => {
                indent_str(indent);
                std.debug.print("zero_or_more: {{\n", .{});
                print(&orphan_nodes.items[self.zero_or_more], indent + 2, orphan_nodes, node_lists);
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
            ASTNodeType.one_or_more => {
                indent_str(indent);
                std.debug.print("one_or_more: {{\n", .{});
                print(&orphan_nodes.items[self.one_or_more], indent + 2, orphan_nodes, node_lists);
                indent_str(indent);
                std.debug.print("}}\n", .{});
            },
        }
    }
};

const RegexAST = struct {
    const Self = @This();

    root: ASTNode,
    node_lists: std.ArrayList(std.ArrayList(ASTNode)),
    ophan_nodes: std.ArrayList(ASTNode),

    pub fn deinit(self: *Self) void {
        for (self.node_lists.items) |node_list| {
            node_list.deinit();
        }
        self.node_lists.deinit();
        self.ophan_nodes.deinit();
    }
};

const TokenStream = struct {
    const Self = @This();

    tokens: std.ArrayList(Token),
    index: usize = 0,

    pub fn init(allocator: Allocator) !Self {
        return Self{ .tokens = std.ArrayList(Token).init(allocator) };
    }

    pub fn available(self: *Self) usize {
        return self.tokens.items.len - self.index;
    }

    pub fn peek(self: *Self, distance: usize) !Token {
        if ((self.index + distance) >= self.tokens.items.len) {
            return error.OutOfBounds;
        }
        return self.tokens.items[self.index + distance];
    }

    pub fn consume(self: *Self) !Token {
        if (self.index >= self.tokens.items.len) {
            return error.OutOfBounds;
        }
        var token = self.tokens.items[self.index];
        self.index += 1;
        return token;
    }

    pub fn append(self: *Self, token: Token) !void {
        try self.tokens.append(token);
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }
};

pub const Compiled = struct {
    const Self = @This();

    const NodeLists = std.ArrayList(std.ArrayList(ASTNode));

    const ParseState = struct {
        in_alternation: bool = false,
        in_list: bool = false,
        is_negative: bool = false,
        alternation_index: usize = 0,
        group_index: usize = 0,
        nodes: usize,
    };
    const RegexError = error{ParseError};

    const RegexConfig = struct {
        dump_ast: bool = false,
        dump_blocks: bool = false,
    };

    re: []const u8,
    allocator: Allocator,
    config: RegexConfig,
    blocks: std.ArrayList(vm.Block),
    group_index: usize,

    pub fn init(allocator: Allocator, re: []const u8, config: RegexConfig) !Self {
        var regex = Self{ .re = re, .allocator = allocator, .config = config, .blocks = std.ArrayList(vm.Block).init(allocator), .group_index = 0 };

        var arena = std.heap.ArenaAllocator.init(allocator);
        var arena_allocator = arena.allocator();
        defer arena.deinit();

        var tokens = try regex.tokenise(arena_allocator);

        var ast = try regex.parse(arena_allocator, &tokens);
        if (regex.config.dump_ast) {
            std.debug.print("\n------------- AST -------------\n", .{});
            ast.root.pretty_print(&ast.ophan_nodes, &ast.node_lists);
        }

        try regex.compile(&ast);
        if (regex.config.dump_blocks) {
            var i: usize = 0;
            std.debug.print("\n---------- VM Blocks ----------\n", .{});
            for (regex.blocks.items) |block| {
                vm.print_block(block, i);
                i += 1;
            }
        }

        return regex;
    }

    pub fn tokenise(self: *Self, allocator: Allocator) !TokenStream {
        var token_stream = try TokenStream.init(allocator);

        var i: usize = 0;
        while (i < self.re.len) : (i += 1) {
            switch (self.re[i]) {
                '(' => try token_stream.append(.{ .tok_type = .lparen, .value = '(' }),
                ')' => try token_stream.append(.{ .tok_type = .rparen, .value = ')' }),
                '[' => try token_stream.append(.{ .tok_type = .lsquare, .value = '[' }),
                '-' => try token_stream.append(.{ .tok_type = .dash, .value = '-' }),
                ']' => try token_stream.append(.{ .tok_type = .rsquare, .value = ']' }),
                '|' => try token_stream.append(.{ .tok_type = .alternation, .value = '|' }),
                '.' => try token_stream.append(.{ .tok_type = .wildcard, .value = '.' }),
                '*' => try token_stream.append(.{ .tok_type = .zero_or_more, .value = '*' }),
                '?' => try token_stream.append(.{ .tok_type = .zero_or_one, .value = '?' }),
                '+' => try token_stream.append(.{ .tok_type = .one_or_more, .value = '+' }),
                '$' => try token_stream.append(.{ .tok_type = .dollar, .value = '$' }),
                '^' => try token_stream.append(.{ .tok_type = .caret, .value = '^' }),
                '\\' => {
                    if (i + 1 >= self.re.len) {
                        return error.OutOfBounds;
                    }
                    try token_stream.append(.{ .tok_type = .escaped, .value = self.re[i + 1] });
                    i += 1;
                },
                else => {
                    try token_stream.append(.{ .tok_type = .literal, .value = self.re[i] });
                },
            }
        }

        return token_stream;
    }

    fn maybe_parse_and_wrap_quantifier(node: ASTNode, current_state: *ParseState, tokens: *TokenStream, ophan_nodes: *std.ArrayList(ASTNode), node_lists: *NodeLists) !bool {
        if (tokens.available() > 0) {
            const next_token = try tokens.peek(0);
            if (next_token.is_quantifier()) {
                const quantifier_token = try tokens.consume();
                try ophan_nodes.append(node);
                var child_index = ophan_nodes.items.len - 1;

                const quantifier_node = try quantifier_token.to_quantifier_node(child_index);
                try node_lists.items[current_state.nodes].append(quantifier_node);
                return true;
            }
        }
        return false;
    }

    fn maybe_parse_rangenode(node: ASTNode, current_state: *ParseState, tokens: *TokenStream, node_lists: *NodeLists) !bool {
        if (tokens.available() >= 2) {
            const next_token = try tokens.peek(0);
            const next_next_token = try tokens.peek(1);
            if (next_token.tok_type == .dash) {
                if (next_next_token.can_be_range_literal()) {
                    _ = try tokens.consume();
                    const range_token = try tokens.consume();

                    if (range_token.value < node.literal) {
                        std.debug.print("Invalid range: {c} to {c}\n", .{ node.literal, range_token.value });
                        return error.ParseError;
                    }

                    const range_node = ASTNode{ .range = .{ .a = node.literal, .b = range_token.value } };
                    try node_lists.items[current_state.nodes].append(range_node);
                    return true;
                }
            }
        }
        return false;
    }

    fn parse_node(self: *Self, token: Token, current_state: *ParseState, tokens: *TokenStream, ophan_nodes: *std.ArrayList(ASTNode), node_lists: *NodeLists, state_stack: *std.ArrayList(ParseState)) !void {
        // Ugly, but saves on passing in another argument.
        const allocator = ophan_nodes.allocator;

        switch (token.tok_type) {
            .literal => {
                var node = ASTNode{ .literal = token.value };
                if (current_state.in_list) {
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                if (!try maybe_parse_and_wrap_quantifier(node, current_state, tokens, ophan_nodes, node_lists)) {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .dollar => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
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
                    else => node = ASTNode{ .literal = token.value },
                }

                if (current_state.in_list) {
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                if (!try maybe_parse_and_wrap_quantifier(node, current_state, tokens, ophan_nodes, node_lists)) {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .wildcard => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                var node = ASTNode{ .wildcard = 0 };
                if (!try maybe_parse_and_wrap_quantifier(node, current_state, tokens, ophan_nodes, node_lists)) {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .lsquare => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                try state_stack.append(current_state.*);
                var is_negative = false;

                if (tokens.available() > 0) {
                    const peeked_token = try tokens.peek(0);
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

                if (!try maybe_parse_and_wrap_quantifier(node, current_state, tokens, ophan_nodes, node_lists)) {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .lparen => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
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
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
                        try node_lists.items[current_state.nodes].append(node);
                    }
                    return;
                }

                const copy_index = if (current_state.in_alternation) current_state.alternation_index else current_state.nodes;
                try node_lists.append(try node_lists.items[copy_index].clone());
                var group_nodes_index = node_lists.items.len - 1;

                var node = ASTNode{ .group = .{ .index = current_state.group_index, .nodes = group_nodes_index } };
                current_state.* = state_stack.pop();

                if (!try maybe_parse_and_wrap_quantifier(node, current_state, tokens, ophan_nodes, node_lists)) {
                    try node_lists.items[current_state.nodes].append(node);
                }
                return;
            },
            .alternation => {
                if (current_state.in_list) {
                    var node = ASTNode{ .literal = token.value };
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
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
                    if (!try maybe_parse_rangenode(node, current_state, tokens, node_lists)) {
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

    pub fn parse(self: *Self, allocator: Allocator, tokens: *TokenStream) !RegexAST {
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

        return RegexAST{ .root = root_node, .ophan_nodes = ophan_nodes, .node_lists = node_lists };
    }

    fn compile_node(self: *Self, ast: *RegexAST, node: ASTNode, current_block_index: usize) !usize {
        switch (node) {
            ASTNodeType.regex => {
                var block_index: usize = current_block_index;
                for (ast.node_lists.items[node.regex].items) |child| {
                    block_index = try self.compile_node(ast, child, block_index);
                }
                try self.blocks.items[block_index].append(.{ .end = 0 });
                return block_index;
            },
            ASTNodeType.group => {
                try self.blocks.append(vm.Block.init(self.allocator));
                var content_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                var end_of_capture_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                var next_block_index = self.blocks.items.len - 1;

                // Start of capture
                try self.blocks.items[current_block_index].append(.{ .start_capture = node.group.index });
                try self.blocks.items[current_block_index].append(.{ .jump = content_block_index });

                // Actual content
                var block_index: usize = content_block_index;
                for (ast.node_lists.items[node.group.nodes].items) |child| {
                    block_index = try self.compile_node(ast, child, block_index);
                }

                // Jump to the end of capture
                try self.blocks.items[block_index].append(.{ .jump = end_of_capture_block_index });

                // End of capture
                try self.blocks.items[end_of_capture_block_index].append(.{ .end_capture = node.group.index });
                try self.blocks.items[end_of_capture_block_index].append(.{ .jump = next_block_index });

                return next_block_index;
            },
            ASTNodeType.literal => {
                try self.blocks.items[current_block_index].append(.{ .char = node.literal });
                return current_block_index;
            },
            ASTNodeType.digit => {
                try self.blocks.items[current_block_index].append(.{ .range = .{ .a = '0', .b = '9' } });
                return current_block_index;
            },
            ASTNodeType.whitespace => {
                try self.blocks.items[current_block_index].append(.{ .whitespace = 0 });
                return current_block_index;
            },
            ASTNodeType.wildcard => {
                try self.blocks.items[current_block_index].append(.{ .wildcard = node.wildcard });
                return current_block_index;
            },
            ASTNodeType.end_of_input => {
                try self.blocks.items[current_block_index].append(.{ .end_of_input = 0 });
                return current_block_index;
            },
            ASTNodeType.range => {
                try self.blocks.items[current_block_index].append(.{ .range = .{ .a = node.range.a, .b = node.range.b } });
                return current_block_index;
            },
            ASTNodeType.alternation => {
                var content = node.alternation;

                try self.blocks.append(vm.Block.init(self.allocator));
                var next_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                const left_index = self.blocks.items.len - 1;
                var final_left_index = left_index;
                for (ast.node_lists.items[content.left].items) |child| {
                    final_left_index = try self.compile_node(ast, child, final_left_index);
                }
                try self.blocks.items[final_left_index].append(.{ .jump = next_block_index });

                try self.blocks.append(vm.Block.init(self.allocator));
                const right_index = self.blocks.items.len - 1;
                var final_right_index = right_index;
                for (ast.node_lists.items[content.right].items) |child| {
                    final_right_index = try self.compile_node(ast, child, final_right_index);
                }
                try self.blocks.items[final_right_index].append(.{ .jump = next_block_index });

                try self.blocks.items[current_block_index].append(.{ .split = .{ .a = left_index, .b = right_index } });

                return next_block_index;
            },
            ASTNodeType.list => {
                var content = node.list;

                if (ast.node_lists.items[content.nodes].items.len == 0) {
                    @panic("Can't generate blocks for empty list, fix in parser");
                }

                try self.blocks.append(vm.Block.init(self.allocator));
                var next_block_index = self.blocks.items.len - 1;

                if (!content.negative) {
                    // Trivial case where we only have a single node in the list.
                    // Generate a block for that node, and add a jump to the next block.
                    if (ast.node_lists.items[content.nodes].items.len == 1) {
                        var final_block_index = try self.compile_node(ast, ast.node_lists.items[content.nodes].items[0], current_block_index);
                        try self.blocks.items[final_block_index].append(.{ .jump = next_block_index });
                        return next_block_index;
                    }

                    // In the case that we have N nodes in the list, we need to generate N-1 splits.
                    try self.blocks.append(vm.Block.init(self.allocator));
                    var split_block_index = self.blocks.items.len - 1;

                    try self.blocks.items[current_block_index].append(.{ .jump = split_block_index });

                    for (0..ast.node_lists.items[content.nodes].items.len - 1) |i| {
                        // Create a block for the content node, compile it, and add a jump to the next block.
                        try self.blocks.append(vm.Block.init(self.allocator));
                        var block_index = self.blocks.items.len - 1;
                        var final_block_index = try self.compile_node(ast, ast.node_lists.items[content.nodes].items[i], block_index);
                        try self.blocks.items[final_block_index].append(.{ .jump = next_block_index });

                        // If this is the last node in the list, the split should direct to the next element in the list, not a new split
                        if (i == ast.node_lists.items[content.nodes].items.len - 2) {
                            try self.blocks.append(vm.Block.init(self.allocator));
                            var last_block_index = self.blocks.items.len - 1;
                            var final_last_block_index = try self.compile_node(ast, ast.node_lists.items[content.nodes].items[i + 1], last_block_index);
                            try self.blocks.items[final_last_block_index].append(.{ .jump = next_block_index });

                            try self.blocks.items[split_block_index].append(.{ .split = .{ .a = block_index, .b = last_block_index } });
                        } else {
                            // Create a new block for the next split
                            try self.blocks.append(vm.Block.init(self.allocator));
                            var new_split_block_index = self.blocks.items.len - 1;

                            // Update the split block to point to the new content block and the new split block
                            try self.blocks.items[split_block_index].append(.{ .split = .{ .a = block_index, .b = new_split_block_index } });
                            split_block_index = new_split_block_index;
                        }
                    }
                } else {
                    // For a negative list, we need to generate a split for each node in the list.
                    try self.blocks.append(vm.Block.init(self.allocator));
                    var split_block_index = self.blocks.items.len - 1;
                    try self.blocks.items[split_block_index].append(.{ .split = .{ .a = 0, .b = 0 } });

                    try self.blocks.items[current_block_index].append(.{ .deadend_marker = 0 });
                    try self.blocks.items[current_block_index].append(.{ .jump = split_block_index });

                    for (0..ast.node_lists.items[content.nodes].items.len) |i| {
                        // Create a block for the content node, compile it, and add a deadend after.
                        try self.blocks.append(vm.Block.init(self.allocator));
                        var block_index = self.blocks.items.len - 1;
                        var final_block_index = try self.compile_node(ast, ast.node_lists.items[content.nodes].items[i], block_index);
                        try self.blocks.items[final_block_index].append(.{ .deadend = 0 });

                        const split_block_len = self.blocks.items[split_block_index].items.len;
                        // If this is the last node in the list, the split should direct to the next_block_index
                        if (i == ast.node_lists.items[content.nodes].items.len - 1) {
                            self.blocks.items[split_block_index].items[split_block_len - 1].split.a = block_index;
                            self.blocks.items[split_block_index].items[split_block_len - 1].split.b = next_block_index;
                        } else {
                            // Update the split block to point to the new content block and the new split block
                            try self.blocks.append(vm.Block.init(self.allocator));
                            var new_split_block_index = self.blocks.items.len - 1;
                            try self.blocks.items[new_split_block_index].append(.{ .split = .{ .a = 0, .b = 0 } });

                            self.blocks.items[split_block_index].items[split_block_len - 1].split.a = block_index;
                            self.blocks.items[split_block_index].items[split_block_len - 1].split.b = new_split_block_index;
                            split_block_index = new_split_block_index;
                        }
                    }

                    try self.blocks.items[next_block_index].append(.{ .wildcard = 0 });
                }

                return next_block_index;
            },
            ASTNodeType.one_or_more => {
                var content = ast.ophan_nodes.items[node.one_or_more];

                try self.blocks.append(vm.Block.init(self.allocator));
                const content_block_index = self.blocks.items.len - 1;
                const new_block_index = try self.compile_node(ast, content, content_block_index);

                try self.blocks.items[current_block_index].append(.{ .jump = content_block_index });

                try self.blocks.append(vm.Block.init(self.allocator));
                const loop_block_index = self.blocks.items.len - 1;
                var loop_block: *vm.Block = &self.blocks.items[loop_block_index];

                // The main content block needs a jump to the loop block.
                try self.blocks.items[new_block_index].append(.{ .jump = loop_block_index });

                try self.blocks.append(vm.Block.init(self.allocator));
                var next_block_index = self.blocks.items.len - 1;

                try loop_block.append(.{ .split = .{ .a = content_block_index, .b = next_block_index } });

                return next_block_index;
            },
            ASTNodeType.zero_or_one => {
                var content = ast.ophan_nodes.items[node.zero_or_one];

                try self.blocks.append(vm.Block.init(self.allocator));
                const quantification_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                const content_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                const next_block_index = self.blocks.items.len - 1;

                // First jump to the quantification block
                try self.blocks.items[current_block_index].append(.{ .jump = quantification_block_index });

                // The quantification block has the split and a jump to the next block
                try self.blocks.items[quantification_block_index].append(.{ .split = .{ .a = content_block_index, .b = next_block_index } });

                // The content block has the content itself
                const final_content_index = try self.compile_node(ast, content, content_block_index);
                try self.blocks.items[final_content_index].append(.{ .jump = next_block_index });

                return next_block_index;
            },
            ASTNodeType.zero_or_more => {
                var content = ast.ophan_nodes.items[node.zero_or_more];

                try self.blocks.append(vm.Block.init(self.allocator));
                const quantification_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                const content_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                const next_block_index = self.blocks.items.len - 1;

                // Jump to the quantification block
                try self.blocks.items[current_block_index].append(.{ .jump = quantification_block_index });

                // Content block
                const new_content_block_index = try self.compile_node(ast, content, content_block_index);
                try self.blocks.items[new_content_block_index].append(.{ .jump = quantification_block_index });

                // Quantification block
                try self.blocks.items[quantification_block_index].append(.{ .split = .{ .a = content_block_index, .b = next_block_index } });

                return next_block_index;
            },
            // else => @panic("unreachable"),
        }
    }

    pub fn compile(self: *Self, ast: *RegexAST) !void {
        try self.blocks.append(vm.Block.init(self.allocator));
        _ = try self.compile_node(ast, ast.root, 0);
    }

    pub fn deinit(self: *Self) void {
        for (self.blocks.items) |block| {
            block.deinit();
        }
        self.blocks.deinit();
    }
};
