const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const vm = @import("vm.zig");

const TokenType = enum { literal, escaped, wildcard, lparen, rparen, alternation, zero_or_one, zero_or_more, one_or_more, lsquare, rsquare, dollar };

const Token = struct {
    tok_type: TokenType,
    value: u8 = 0,
};

const ASTNodeType = enum { regex, literal, digit, wildcard, alternation, zero_or_one, zero_or_more, one_or_more, group, end_of_input };

pub const ASTNode = union(ASTNodeType) {
    const Self = @This();

    regex: std.ArrayList(ASTNode),
    literal: u8,
    digit: u8,
    wildcard: u8,
    alternation: struct {
        left: *ASTNode,
        right: *ASTNode,
    },
    zero_or_one: *ASTNode,
    zero_or_more: *ASTNode,
    one_or_more: *ASTNode,
    group: std.ArrayList(ASTNode),
    end_of_input: u8,

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            ASTNodeType.literal => {},
            ASTNodeType.digit => {},
            ASTNodeType.wildcard => {},
            ASTNodeType.end_of_input => {},
            ASTNodeType.regex => {
                var i: usize = 0;
                while (i < self.regex.items.len) : (i += 1) {
                    var x = self.regex.items[i];
                    x.deinit();
                }
                self.regex.deinit();
            },
            ASTNodeType.group => {
                var i: usize = 0;
                while (i < self.group.items.len) : (i += 1) {
                    var x = self.group.items[i];
                    x.deinit();
                }
                self.group.deinit();
            },
            ASTNodeType.alternation => {
                self.alternation.left.deinit();
                self.alternation.right.deinit();
            },
            ASTNodeType.zero_or_one => {
                self.zero_or_one.deinit();
            },
            ASTNodeType.zero_or_more => {
                self.zero_or_more.deinit();
            },
            ASTNodeType.one_or_more => {
                self.one_or_more.deinit();
            },
        }
    }

    fn buf_print_at_offset(buf: []u8, str_offset: *usize, comptime fmt: []const u8, args: anytype) std.fmt.BufPrintError!void {
        var slice_written = try std.fmt.bufPrint(buf[str_offset.*..], fmt, args);
        str_offset.* += slice_written.len;
    }

    fn indent_str(amount: usize, str: []u8, str_offset: *usize) !void {
        var i: usize = 0;
        while (i < amount) : (i += 1) {
            _ = try buf_print_at_offset(str[str_offset.*..], str_offset, " ", .{});
        }
    }

    pub fn pretty_print(self: *Self, allocator: Allocator, max_buffer_size: usize) !void {
        var str = try allocator.alloc(u8, max_buffer_size);
        defer allocator.free(str);
        @memset(str, 0);

        var str_offset: usize = 0;
        try self.print(0, str, &str_offset);
        std.debug.print("{s}\n", .{str});
    }

    fn print(self: *Self, indent: usize, str: []u8, str_offset: *usize) !void {
        switch (self.*) {
            ASTNodeType.regex => {
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "regex: {{\n", .{});
                var i: usize = 0;
                while (i < self.regex.items.len) : (i += 1) {
                    try print(&self.regex.items[i], indent + 2, str, str_offset);
                }
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "}}\n", .{});
            },
            ASTNodeType.literal => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "lit({c})\n", .{self.literal});
            },
            ASTNodeType.end_of_input => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "end_of_input\n", .{});
            },
            ASTNodeType.digit => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "digit({c})\n", .{self.digit});
            },
            ASTNodeType.wildcard => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "wildcard\n", .{});
            },
            ASTNodeType.group => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "group: {{\n", .{});
                var i: usize = 0;
                while (i < self.group.items.len) : (i += 1) {
                    try print(&self.group.items[i], indent + 2, str, str_offset);
                }
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "}}\n", .{});
            },
            ASTNodeType.alternation => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "alt: {{\n", .{});
                try print(self.alternation.left, indent + 2, str, str_offset);
                try print(self.alternation.right, indent + 2, str, str_offset);
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "}}\n", .{});
            },
            ASTNodeType.zero_or_one => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "zero_or_one: {{\n", .{});
                try print(self.zero_or_one, indent + 2, str, str_offset);
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "}}\n", .{});
            },
            ASTNodeType.zero_or_more => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "zero_or_more: {{\n", .{});
                try print(self.zero_or_more, indent + 2, str, str_offset);
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "}}\n", .{});
            },
            ASTNodeType.one_or_more => {
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "one_or_more: {{\n", .{});
                try print(self.one_or_more, indent + 2, str, str_offset);
                try indent_str(indent, str, str_offset);
                _ = try buf_print_at_offset(str[str_offset.*..], str_offset, "}}\n", .{});
            },
        }
    }
};

pub const RegexAST = struct {
    const Self = @This();

    root: ASTNode,
    ophan_nodes: std.ArrayList(ASTNode),

    pub fn deinit(self: *Self) void {
        self.root.deinit();
        self.ophan_nodes.deinit();
    }
};

pub const Regex = struct {
    const Self = @This();

    const ParseState = struct { nodes: std.ArrayList(ASTNode), in_alternation: bool = false };
    const RegexError = error{ParseError};

    const RegexConfig = struct {
        dump_ast: bool = false,
        dump_blocks: bool = false,
    };

    re: []const u8,
    allocator: Allocator,
    config: RegexConfig,
    blocks: std.ArrayList(vm.Block),

    pub fn init(allocator: Allocator, re: []const u8, config: RegexConfig) !Self {
        var regex = Regex{
            .re = re,
            .allocator = allocator,
            .config = config,
            .blocks = std.ArrayList(vm.Block).init(allocator),
        };

        var arena = std.heap.ArenaAllocator.init(allocator);
        var arena_allocator = arena.allocator();
        defer arena.deinit();

        var tokens = try regex.tokenise(arena_allocator);

        var ast = try regex.parse(arena_allocator, tokens);
        if (regex.config.dump_ast) {
            std.debug.print("\n------------- AST -------------\n", .{});
            try ast.root.pretty_print(arena_allocator, 4 * 4096);
        }

        try regex.compile(ast.root);
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

    pub fn tokenise(self: *Self, allocator: Allocator) !std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(allocator);

        var i: usize = 0;
        while (i < self.re.len) : (i += 1) {
            switch (self.re[i]) {
                '(' => try tokens.append(.{ .tok_type = .lparen }),
                ')' => try tokens.append(.{ .tok_type = .rparen }),
                '[' => try tokens.append(.{ .tok_type = .lsquare }),
                // '-' => try tokens.append(.{ .tok_type = .dash }),
                ']' => try tokens.append(.{ .tok_type = .rsquare }),
                '|' => try tokens.append(.{ .tok_type = .alternation }),
                '.' => try tokens.append(.{ .tok_type = .wildcard }),
                '*' => try tokens.append(.{ .tok_type = .zero_or_more }),
                '?' => try tokens.append(.{ .tok_type = .zero_or_one }),
                '+' => try tokens.append(.{ .tok_type = .one_or_more }),
                '$' => try tokens.append(.{ .tok_type = .dollar }),
                '\\' => {
                    if (i + 1 >= self.re.len) {
                        return error.OutOfBounds;
                    }
                    try tokens.append(.{ .tok_type = .escaped, .value = self.re[i + 1] });
                    i += 1;
                },
                else => {
                    try tokens.append(.{ .tok_type = .literal, .value = self.re[i] });
                },
            }
        }

        return tokens;
    }

    pub fn parse(self: *Self, allocator: Allocator, tokens: std.ArrayList(Token)) !RegexAST {
        _ = self;
        // We need a home for nodes that are pointed to by other nodes. When we come to deinit the
        // AST, we can walk the AST itself and deinit all the ArrayLists we find along the way, and
        // then free the ophan_nodes ArrayList.
        var ophan_nodes = std.ArrayList(ASTNode).init(allocator);

        var current_state = ParseState{ .nodes = std.ArrayList(ASTNode).init(allocator) };
        var state_stack = std.ArrayList(ParseState).init(allocator);
        defer state_stack.deinit();

        var i: usize = 0;
        while (i < tokens.items.len) : (i += 1) {
            const token = tokens.items[i];
            switch (token.tok_type) {
                .literal => {
                    var node = ASTNode{ .literal = token.value };

                    if (current_state.in_alternation) {
                        var left = current_state.nodes.pop();

                        try ophan_nodes.append(node);
                        var node_ptr = &ophan_nodes.items[ophan_nodes.items.len - 1];

                        try ophan_nodes.append(left);
                        var left_ptr = &ophan_nodes.items[ophan_nodes.items.len - 1];

                        var alt_node = ASTNode{ .alternation = .{ .left = left_ptr, .right = node_ptr } };
                        try current_state.nodes.append(alt_node);

                        current_state.in_alternation = false;
                    } else {
                        try current_state.nodes.append(node);
                    }
                },
                .dollar => {
                    var node = ASTNode{ .end_of_input = 0 };

                    if (current_state.in_alternation) {
                        return RegexError.ParseError;
                    }

                    try current_state.nodes.append(node);
                },
                .escaped => {
                    var node: ASTNode = undefined;
                    if (token.value == 'd') {
                        node = .{ .digit = 0 };
                    } else {
                        node = .{ .literal = token.value };
                    }

                    if (current_state.in_alternation) {
                        var left = current_state.nodes.pop();

                        try ophan_nodes.append(node);
                        var node_ptr = &ophan_nodes.items[ophan_nodes.items.len - 1];

                        try ophan_nodes.append(left);
                        var left_ptr = &ophan_nodes.items[ophan_nodes.items.len - 1];

                        var alt_node = ASTNode{ .alternation = .{ .left = left_ptr, .right = node_ptr } };
                        try current_state.nodes.append(alt_node);

                        current_state.in_alternation = false;
                    } else {
                        try current_state.nodes.append(node);
                    }
                },
                .wildcard => {
                    var node = ASTNode{ .wildcard = 0 };

                    if (current_state.in_alternation) {
                        var left = current_state.nodes.pop();

                        try ophan_nodes.append(node);
                        var node_ptr = &ophan_nodes.items[ophan_nodes.items.len - 1];

                        try ophan_nodes.append(left);
                        var left_ptr = &ophan_nodes.items[ophan_nodes.items.len - 1];

                        var alt_node = ASTNode{ .alternation = .{ .left = left_ptr, .right = node_ptr } };
                        try current_state.nodes.append(alt_node);

                        current_state.in_alternation = false;
                    } else {
                        try current_state.nodes.append(node);
                    }
                },
                .lparen => {
                    try state_stack.append(current_state);
                    current_state = .{ .nodes = std.ArrayList(ASTNode).init(allocator) };
                },
                .rparen => {
                    var node = ASTNode{ .group = current_state.nodes };
                    current_state = state_stack.pop();
                    try current_state.nodes.append(node);
                },
                .alternation => {
                    current_state.in_alternation = true;
                },
                .zero_or_one => {
                    var prev_node = current_state.nodes.items[current_state.nodes.items.len - 1];
                    var node = ASTNode{ .zero_or_one = &prev_node };

                    if (@as(ASTNodeType, prev_node) == ASTNodeType.alternation) {
                        var right = prev_node.alternation.right;
                        node.zero_or_one = right;
                        prev_node.alternation.right = &node;
                    } else {
                        var prev = current_state.nodes.pop();
                        try ophan_nodes.append(prev);
                        node.zero_or_one = &ophan_nodes.items[ophan_nodes.items.len - 1];
                        try current_state.nodes.append(node);
                    }
                },
                .zero_or_more => {
                    var prev_node = current_state.nodes.items[current_state.nodes.items.len - 1];
                    var node = ASTNode{ .zero_or_more = &prev_node };

                    if (@as(ASTNodeType, prev_node) == ASTNodeType.alternation) {
                        var right = prev_node.alternation.right;
                        node.zero_or_more = right;
                        prev_node.alternation.right = &node;
                    } else {
                        var prev = current_state.nodes.pop();
                        try ophan_nodes.append(prev);
                        node.zero_or_more = &ophan_nodes.items[ophan_nodes.items.len - 1];
                        try current_state.nodes.append(node);
                        try ophan_nodes.append(prev);
                    }
                },
                .one_or_more => {
                    var prev_node = current_state.nodes.items[current_state.nodes.items.len - 1];
                    var node = ASTNode{ .one_or_more = &prev_node };

                    if (@as(ASTNodeType, prev_node) == ASTNodeType.alternation) {
                        var right = prev_node.alternation.right;
                        node.one_or_more = right;
                        prev_node.alternation.right = &node;
                    } else {
                        var prev = current_state.nodes.pop();
                        try ophan_nodes.append(prev);
                        node.one_or_more = &ophan_nodes.items[ophan_nodes.items.len - 1];
                        try current_state.nodes.append(node);
                        try ophan_nodes.append(prev);
                    }
                },
                else => @panic("unreachable"),
            }
        }

        var root = ASTNode{ .regex = current_state.nodes };
        return RegexAST{ .root = root, .ophan_nodes = ophan_nodes };
    }

    fn compile_node(self: *Self, node: ASTNode, current_block_index: usize) !usize {
        switch (node) {
            ASTNodeType.regex => {
                var block_index: usize = current_block_index;
                for (node.regex.items) |child| {
                    block_index = try self.compile_node(child, block_index);
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
                try self.blocks.items[current_block_index].append(.{ .start_capture = 0 });
                try self.blocks.items[current_block_index].append(.{ .jump_and_link = content_block_index });

                // Actual content
                var block_index: usize = current_block_index;
                for (node.group.items) |child| {
                    block_index = try self.compile_node(child, content_block_index);
                }

                // Jump to the end of capture
                try self.blocks.items[block_index].append(.{ .jump = end_of_capture_block_index });

                // End of capture
                try self.blocks.items[end_of_capture_block_index].append(.{ .end_capture = 0 });
                try self.blocks.items[end_of_capture_block_index].append(.{ .jump = next_block_index });

                return next_block_index;
            },
            ASTNodeType.literal => {
                try self.blocks.items[current_block_index].append(.{ .char = node.literal });
                return current_block_index;
            },
            ASTNodeType.digit => {
                try self.blocks.items[current_block_index].append(.{ .digit = node.digit });
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
            ASTNodeType.alternation => {
                var content = node.alternation;

                try self.blocks.append(vm.Block.init(self.allocator));
                var next_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                const left_index = self.blocks.items.len - 1;
                const final_left_index = try self.compile_node(content.left.*, left_index);
                try self.blocks.items[final_left_index].append(.{ .jump = next_block_index });

                try self.blocks.append(vm.Block.init(self.allocator));
                const right_index = self.blocks.items.len - 1;
                const final_right_index = try self.compile_node(content.right.*, right_index);
                try self.blocks.items[final_right_index].append(.{ .jump = next_block_index });

                try self.blocks.items[current_block_index].append(.{ .split = .{ .a = left_index, .b = right_index } });

                return next_block_index;
            },
            ASTNodeType.one_or_more => {
                var content = node.one_or_more;

                try self.blocks.append(vm.Block.init(self.allocator));
                const content_block_index = self.blocks.items.len - 1;
                const new_block_index = try self.compile_node(content.*, content_block_index);

                try self.blocks.items[current_block_index].append(.{ .jump = content_block_index });

                try self.blocks.append(vm.Block.init(self.allocator));
                const loop_block_index = self.blocks.items.len - 1;
                var loop_block: *vm.Block = &self.blocks.items[loop_block_index];

                // The main content block needs a jump to the loop block.
                try self.blocks.items[new_block_index].append(.{ .jump = loop_block_index });

                try self.blocks.append(vm.Block.init(self.allocator));
                var next_block_index = self.blocks.items.len - 1;

                try loop_block.append(.{ .split = .{ .a = content_block_index, .b = next_block_index } });
                try loop_block.append(.{ .jump = next_block_index });

                return next_block_index;
            },
            ASTNodeType.zero_or_one => {
                var content = node.zero_or_one;

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
                try self.blocks.items[quantification_block_index].append(.{ .jump = next_block_index });

                // The content block has the content itself
                _ = try self.compile_node(content.*, content_block_index);

                return next_block_index;
            },
            ASTNodeType.zero_or_more => {
                var content = node.zero_or_more;

                try self.blocks.append(vm.Block.init(self.allocator));
                const quantification_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                const content_block_index = self.blocks.items.len - 1;

                try self.blocks.append(vm.Block.init(self.allocator));
                const next_block_index = self.blocks.items.len - 1;

                // Jump to the quantification block
                try self.blocks.items[current_block_index].append(.{ .jump = quantification_block_index });

                // Content block
                const new_content_block_index = try self.compile_node(content.*, content_block_index);
                try self.blocks.items[new_content_block_index].append(.{ .jump = quantification_block_index });

                // Quantification block
                try self.blocks.items[quantification_block_index].append(.{ .split = .{ .a = content_block_index, .b = next_block_index } });
                try self.blocks.items[quantification_block_index].append(.{ .jump = next_block_index });

                return next_block_index;
            },
            // else => @panic("unreachable"),
        }
    }

    pub fn compile(self: *Self, ast: ASTNode) !void {
        try self.blocks.append(vm.Block.init(self.allocator));
        _ = try self.compile_node(ast, 0);
    }

    pub fn deinit(self: *Self) void {
        for (self.blocks.items) |block| {
            block.deinit();
        }
        self.blocks.deinit();
    }
};
