const std = @import("std");
const Allocator = std.mem.Allocator;

const vm = @import("../vm.zig");

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

    allocator: Allocator,
    blocks: std.ArrayList(vm.Block),
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

                if (!content.negative) {
                    // Trivial case where we only have a single node in the list.
                    // Generate a block for that node, and add a jump to the next block.
                    if (parsed.node_lists.items[content.nodes].items.len == 1) {
                        const final_block_index = try self.compile_node(parsed, parsed.node_lists.items[content.nodes].items[0], current_block_index);
                        try self.add_to_block(final_block_index, .{ .jump = next_block_index });
                        return next_block_index;
                    }

                    // In the case that we have N nodes in the list, we need to generate N-1 splits.
                    try self.blocks.append(vm.Block.init(self.allocator));
                    var split_block_index = self.blocks.items.len - 1;

                    try self.add_to_block(current_block_index, .{ .jump = split_block_index });

                    for (0..parsed.node_lists.items[content.nodes].items.len - 1) |i| {
                        // Create a block for the content node, compile it, and add a jump to the next block.
                        const block_index = try self.create_block();
                        const final_block_index = try self.compile_node(parsed, parsed.node_lists.items[content.nodes].items[i], block_index);
                        try self.add_to_block(final_block_index, .{ .jump = next_block_index });

                        // If this is the last node in the list, the split should direct to the next element in the list, not a new split
                        if (i == parsed.node_lists.items[content.nodes].items.len - 2) {
                            const last_block_index = try self.create_block();
                            const final_last_block_index = try self.compile_node(parsed, parsed.node_lists.items[content.nodes].items[i + 1], last_block_index);
                            try self.add_to_block(final_last_block_index, .{ .jump = next_block_index });

                            try self.add_to_block(split_block_index, .{ .split = .{ .a = block_index, .b = last_block_index } });
                        } else {
                            // Create a new block for the next split
                            const new_split_block_index = try self.create_block();

                            // Update the split block to point to the new content block and the new split block
                            try self.add_to_block(split_block_index, .{ .split = .{ .a = block_index, .b = new_split_block_index } });
                            split_block_index = new_split_block_index;
                        }
                    }
                } else {
                    // For a negative list, we need to generate a split for each node in the list.
                    var split_block_index = try self.create_block();
                    try self.add_to_block(split_block_index, .{ .split = .{ .a = 0, .b = 0 } });

                    try self.add_to_block(current_block_index, .{ .deadend_marker = 0 });
                    try self.add_to_block(current_block_index, .{ .jump = split_block_index });

                    for (0..parsed.node_lists.items[content.nodes].items.len) |i| {
                        // Create a block for the content node, compile it, and add a deadend after.
                        const block_index = try self.create_block();
                        const final_block_index = try self.compile_node(parsed, parsed.node_lists.items[content.nodes].items[i], block_index);
                        try self.add_to_block(final_block_index, .{ .deadend = 0 });

                        const split_block_len = self.blocks.items[split_block_index].items.len;
                        // If this is the last node in the list, the split should direct to the next_block_index
                        if (i == parsed.node_lists.items[content.nodes].items.len - 1) {
                            self.blocks.items[split_block_index].items[split_block_len - 1].split.a = block_index;
                            self.blocks.items[split_block_index].items[split_block_len - 1].split.b = next_block_index;
                        } else {
                            // Update the split block to point to the new content block and the new split block
                            const new_split_block_index = try self.create_block();
                            try self.add_to_block(new_split_block_index, .{ .split = .{ .a = 0, .b = 0 } });

                            self.blocks.items[split_block_index].items[split_block_len - 1].split.a = block_index;
                            self.blocks.items[split_block_index].items[split_block_len - 1].split.b = new_split_block_index;
                            split_block_index = new_split_block_index;
                        }
                    }

                    try self.add_to_block(next_block_index, .{ .wildcard = 0 });
                }

                return next_block_index;
            },
            .one_or_more => {
                const quantifier = node.one_or_more;
                var content = parsed.ophan_nodes.items[quantifier.node];

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
                var content = parsed.ophan_nodes.items[quantifier.node];

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
                var content = parsed.ophan_nodes.items[quantifier.node];

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

    pub fn compile(allocator: Allocator, parsed: *ParsedRegex) !std.ArrayList(vm.Block) {
        var self = Self{ .allocator = allocator, .blocks = std.ArrayList(vm.Block).init(allocator) };
        try self.blocks.append(vm.Block.init(self.allocator));
        _ = try self.compile_node(parsed, parsed.ast, 0);
        return self.blocks;
    }
};
