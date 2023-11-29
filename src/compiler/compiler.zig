const std = @import("std");
const Allocator = std.mem.Allocator;

const vm = @import("../vm.zig");
const ListItem = vm.ListItem;
const ListItemLists = vm.ListItemLists;

const parser = @import("parser.zig");
const ASTNode = @import("common.zig").ASTNode;
const ParsedRegex = parser.ParsedRegex;

pub fn blocks_deinit(blocks: std.ArrayList(vm.Block)) void {
    for (blocks.items) |block| {
        block.deinit();
    }
    blocks.deinit();
}

pub const Compiler = struct {
    const Self = @This();

    const CompilationResult = struct {
        blocks: std.ArrayList(vm.Block),
        lists: ListItemLists,
    };

    allocator: Allocator,
    blocks: std.ArrayList(vm.Block),
    lists: ListItemLists,
    progress_index: usize = 0,

    fn create_block(self: *Self) !usize {
        try self.blocks.append(vm.Block.init(self.allocator));
        return self.blocks.items.len - 1;
    }

    fn add_to_block(self: *Self, block_index: usize, op: vm.Op) !void {
        try self.blocks.items[block_index].append(op);
    }

    fn compile_node(self: *Self, parsed: *ParsedRegex, node: ASTNode, current_block_index: usize) !usize {
        switch (node) {
            .regex => {
                var block_index: usize = current_block_index;
                for (parsed.node_lists.items[node.regex].items) |child| {
                    block_index = try self.compile_node(parsed, child, block_index);
                }
                try self.add_to_block(block_index, .{ .end = 0 });
                return block_index;
            },
            .group => {
                const content_block_index = try self.create_block();
                const end_of_capture_block_index = try self.create_block();
                const next_block_index = try self.create_block();

                // Start of capture
                try self.add_to_block(current_block_index, .{ .start_capture = node.group.index });
                try self.add_to_block(current_block_index, .{ .jump = content_block_index });

                // Actual content
                var block_index: usize = content_block_index;
                for (parsed.node_lists.items[node.group.nodes].items) |child| {
                    block_index = try self.compile_node(parsed, child, block_index);
                }

                // Jump to the end of capture
                try self.add_to_block(block_index, .{ .jump = end_of_capture_block_index });

                // End of capture
                try self.add_to_block(end_of_capture_block_index, .{ .end_capture = node.group.index });
                try self.add_to_block(end_of_capture_block_index, .{ .jump = next_block_index });

                return next_block_index;
            },
            .literal => {
                try self.add_to_block(current_block_index, .{ .char = node.literal });
                return current_block_index;
            },
            .digit => {
                try self.add_to_block(current_block_index, .{ .range = .{ .a = '0', .b = '9' } });
                return current_block_index;
            },
            .whitespace => {
                try self.add_to_block(current_block_index, .{ .whitespace = 0 });
                return current_block_index;
            },
            .wildcard => {
                try self.add_to_block(current_block_index, .{ .wildcard = node.wildcard });
                return current_block_index;
            },
            .end_of_input => {
                try self.add_to_block(current_block_index, .{ .end_of_input = 0 });
                return current_block_index;
            },
            .range => {
                try self.add_to_block(current_block_index, .{ .range = .{ .a = node.range.a, .b = node.range.b } });
                return current_block_index;
            },
            .alternation => {
                const content = node.alternation;

                const next_block_index = try self.create_block();

                const left_index = try self.create_block();
                var final_left_index = left_index;
                for (parsed.node_lists.items[content.left].items) |child| {
                    final_left_index = try self.compile_node(parsed, child, final_left_index);
                }
                try self.add_to_block(final_left_index, .{ .jump = next_block_index });

                const right_index = try self.create_block();
                var final_right_index = right_index;
                for (parsed.node_lists.items[content.right].items) |child| {
                    final_right_index = try self.compile_node(parsed, child, final_right_index);
                }
                try self.add_to_block(final_right_index, .{ .jump = next_block_index });

                try self.add_to_block(current_block_index, .{ .split = .{ .a = left_index, .b = right_index } });

                return next_block_index;
            },
            .list => {
                const content = node.list;

                if (parsed.node_lists.items[content.nodes].items.len == 0) {
                    @panic("Can't generate blocks for empty list, fix in parser");
                }

                const next_block_index = try self.create_block();

                try self.lists.append(std.ArrayList(ListItem).init(self.allocator));
                const list_index = self.lists.items.len - 1;

                for (parsed.node_lists.items[content.nodes].items) |child| {
                    switch (child) {
                        .literal => {
                            try self.lists.items[list_index].append(.{ .char = child.literal });
                        },
                        .digit => {
                            try self.lists.items[list_index].append(.{ .range = .{ .a = '0', .b = '9' } });
                        },
                        .whitespace => {
                            try self.lists.items[list_index].append(.{ .whitespace = 0 });
                        },
                        .range => {
                            try self.lists.items[list_index].append(.{ .range = .{ .a = child.range.a, .b = child.range.b } });
                        },
                        else => @panic("Unexpected ASTNode found when compiling list"),
                    }
                }

                try self.add_to_block(current_block_index, .{ .list = .{ .items = list_index, .negate = content.negative } });
                try self.add_to_block(current_block_index, .{ .jump = next_block_index });

                return next_block_index;
            },
            .one_or_more => {
                const quantifier = node.one_or_more;
                var content = parsed.orphan_nodes.items[quantifier.node];

                const content_block_index = try self.create_block();
                const new_block_index = try self.compile_node(parsed, content, content_block_index);

                try self.add_to_block(current_block_index, .{ .jump = content_block_index });

                const loop_block_index = try self.create_block();

                // The main content block needs a jump to the loop block.
                try self.add_to_block(new_block_index, .{ .jump = loop_block_index });

                const next_block_index = try self.create_block();

                if (quantifier.greedy) {
                    try self.add_to_block(loop_block_index, .{ .split = .{ .a = content_block_index, .b = next_block_index } });
                } else {
                    try self.add_to_block(loop_block_index, .{ .split = .{ .a = next_block_index, .b = content_block_index } });
                }
                return next_block_index;
            },
            .zero_or_one => {
                const quantifier = node.zero_or_one;
                var content = parsed.orphan_nodes.items[quantifier.node];

                const quantification_block_index = try self.create_block();
                const content_block_index = try self.create_block();
                const next_block_index = try self.create_block();

                // First jump to the quantification block
                try self.add_to_block(current_block_index, .{ .jump = quantification_block_index });

                // The quantification block has the split and a jump to the next block
                if (quantifier.greedy) {
                    try self.add_to_block(quantification_block_index, .{ .split = .{ .a = content_block_index, .b = next_block_index } });
                } else {
                    try self.add_to_block(quantification_block_index, .{ .split = .{ .a = next_block_index, .b = content_block_index } });
                }

                // The content block has the content itself
                const final_content_index = try self.compile_node(parsed, content, content_block_index);
                try self.add_to_block(final_content_index, .{ .jump = next_block_index });

                return next_block_index;
            },
            .zero_or_more => {
                const quantifier = node.zero_or_more;
                var content = parsed.orphan_nodes.items[quantifier.node];

                const quantification_block_index = try self.create_block();
                const content_block_index = try self.create_block();
                const next_block_index = try self.create_block();

                // Jump to the quantification block
                try self.add_to_block(current_block_index, .{ .jump = quantification_block_index });

                // Content block
                const new_content_block_index = try self.compile_node(parsed, content, content_block_index);
                try self.add_to_block(new_content_block_index, .{ .jump = quantification_block_index });

                // Quantification block
                try self.add_to_block(quantification_block_index, .{ .progress = self.progress_index });

                if (quantifier.greedy) {
                    try self.add_to_block(quantification_block_index, .{ .split = .{ .a = content_block_index, .b = next_block_index } });
                } else {
                    try self.add_to_block(quantification_block_index, .{ .split = .{ .a = next_block_index, .b = content_block_index } });
                }
                self.progress_index += 1;

                return next_block_index;
            },
            // else => @panic("unreachable"),
        }
    }

    fn optimise_single_block_jumps(self: *Self) !void {
        var single_jump_blocks = std.AutoHashMap(usize, usize).init(self.allocator);
        defer single_jump_blocks.deinit();

        // Collect up all the single jump blocks
        for (self.blocks.items, 0..) |block, block_index| {
            if (block.items.len == 1) {
                switch (block.items[0]) {
                    .jump => try single_jump_blocks.put(block_index, block.items[0].jump),
                    else => {},
                }
            }
        }

        // Iterate through all of the blocks and replace the jumps with the actual block
        // Run this optimisation to a fixed point.
        // Note: This method doesn't actually remove blocks that were optimised out, instead
        //       only leaving them in place with no references to them.
        while (true) {
            var branches_rewritten: usize = 0;

            for (0..self.blocks.items.len) |block_index| {
                const block_len = self.blocks.items[block_index].items.len;
                for (0..block_len) |op_index| {
                    var op = &self.blocks.items[block_index].items[op_index];

                    switch (op.*) {
                        .jump => {
                            const jump_index = op.jump;
                            if (single_jump_blocks.get(jump_index)) |ji| {
                                op.jump = ji;
                                branches_rewritten += 1;
                            }
                        },
                        .split => {
                            const split_a_index = op.split.a;
                            const split_b_index = op.split.b;
                            if (single_jump_blocks.get(split_a_index)) |ji| {
                                op.split.a = ji;
                                branches_rewritten += 1;
                            }
                            if (single_jump_blocks.get(split_b_index)) |ji| {
                                op.split.b = ji;
                                branches_rewritten += 1;
                            }
                        },
                        else => {},
                    }
                }
            }

            if (branches_rewritten == 0) {
                break;
            }
        }
    }

    fn optimise(self: *Self) !void {
        try self.optimise_single_block_jumps();
    }

    pub fn compile(allocator: Allocator, parsed: *ParsedRegex) !CompilationResult {
        var self = Self{ .allocator = allocator, .blocks = std.ArrayList(vm.Block).init(allocator), .lists = ListItemLists.init(allocator) };

        try self.blocks.append(vm.Block.init(self.allocator));
        _ = try self.compile_node(parsed, parsed.ast, 0);

        try self.optimise();

        return .{ .blocks = self.blocks, .lists = self.lists };
    }
};
