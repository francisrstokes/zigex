const std = @import("std");
const Allocator = std.mem.Allocator;

pub const OpType = enum { char, digit, wildcard, jump, jump_and_link, split, end, end_of_input, start_capture, end_capture };

const Op = union(OpType) {
    // Content based
    char: u8,
    digit: u8,
    wildcard: u8,

    // Capture based
    start_capture: u8,
    end_capture: u8,

    // Flow based
    jump: usize,
    jump_and_link: usize,
    split: struct { a: usize, b: usize },
    end: u8,
    end_of_input: u8,

    pub fn print(self: *@This(), block_index: usize, pc: usize, match: []const u8) void {
        switch (self.*) {
            OpType.char => std.debug.print("B{d}.{d}: char({c})         \"{s}\"\n", .{ block_index, pc, self.char, match }),
            OpType.digit => std.debug.print("B{d}.{d}: digit           \"{s}\"\n", .{ block_index, pc, match }),
            OpType.wildcard => std.debug.print("B{d}.{d}: wildcard        \"{s}\"\n", .{ block_index, pc, match }),
            OpType.split => std.debug.print("B{d}.{d}: split({d}, {d})     \"{s}\"\n", .{ block_index, pc, self.split.a, self.split.b, match }),
            OpType.jump => std.debug.print("B{d}.{d}: jump({d})         \"{s}\"\n", .{ block_index, pc, self.jump, match }),
            OpType.jump_and_link => std.debug.print("B{d}.{d}: jal({d})          \"{s}\"\n", .{ block_index, pc, self.jump_and_link, match }),
            OpType.start_capture => std.debug.print("B{d}.{d}: start_capture   \"{s}\"\n", .{ block_index, pc, match }),
            OpType.end_capture => std.debug.print("B{d}.{d}: end_capture     \"{s}\"\n", .{ block_index, pc, match }),
            OpType.end => std.debug.print("B{d}.{d}: end             \"{s}\"\n", .{ block_index, pc, match }),
            OpType.end_of_input => std.debug.print("B{d}.{d}: end_of_input    \"{s}\"\n", .{ block_index, pc, match }),
        }
    }
};

const Wildcard = Op{ .wildcard = '.' };
const Digit = Op{ .digit = 'd' };
const End = Op{ .end = 'e' };
const EndOfInput = Op{ .end = 'e' };

pub const Block = std.ArrayList(Op);
pub fn print_block(block: Block, index: usize) void {
    std.debug.print("Block {d}:\n", .{index});

    if (block.items.len == 0) {
        std.debug.print("  <empty>\n", .{});
    }

    for (block.items) |instruction| {
        switch (instruction) {
            OpType.char => std.debug.print("  char({c})\n", .{instruction.char}),
            OpType.digit => std.debug.print("  digit\n", .{}),
            OpType.wildcard => std.debug.print("  wildcard\n", .{}),
            OpType.split => std.debug.print("  split({d}, {d})\n", .{ instruction.split.a, instruction.split.b }),
            OpType.jump => std.debug.print("  jump({d})\n", .{instruction.jump}),
            OpType.jump_and_link => std.debug.print("  jal({d})\n", .{instruction.jump_and_link}),
            OpType.end => std.debug.print("  end\n", .{}),
            OpType.end_of_input => std.debug.print("  end_of_input\n", .{}),
            OpType.start_capture => std.debug.print("  start_capture\n", .{}),
            OpType.end_capture => std.debug.print("  end_capture\n", .{}),
        }
    }
    std.debug.print("\n", .{});
}

const ThreadState = struct {
    const Self = @This();

    block_index: usize,
    pc: usize,
    index: usize,
    next_split: ?usize,
    capture_stack: std.ArrayList(usize),
    captures: std.ArrayList([]const u8),

    pub fn clone(self: *Self) !ThreadState {
        return .{
            .block_index = self.block_index,
            .pc = self.pc,
            .index = self.index,
            .next_split = self.next_split,
            .capture_stack = try self.capture_stack.clone(),
            .captures = try self.captures.clone(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.capture_stack.deinit();
        self.captures.deinit();
    }
};

pub const State = struct {
    const Self = @This();

    blocks: *std.ArrayList(Block),
    state: ThreadState,
    stack: std.ArrayList(ThreadState),
    input_str: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, blocks: *std.ArrayList(Block), input_str: []const u8) State {
        return .{
            .blocks = blocks,
            .state = .{ .block_index = 0, .pc = 0, .index = 0, .next_split = null, .captures = std.ArrayList([]const u8).init(allocator), .capture_stack = std.ArrayList(usize).init(allocator) },
            .stack = std.ArrayList(ThreadState).init(allocator),
            .input_str = input_str,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var i: usize = 0;
        while (i < self.stack.items.len) : (i += 1) {
            self.stack.items[i].deinit();
        }
        self.stack.deinit();
        self.state.deinit();
    }

    fn is_end_of_input(self: *Self) bool {
        return self.state.index >= self.input_str.len;
    }

    fn push_state(self: *Self) void {
        self.stack.append(self.state);
    }

    fn unwind(self: *Self) !bool {
        if (self.stack.items.len == 0) {
            return false;
        }

        // Was this the "A" path? Then try "B"
        if (self.state.next_split) |split_block| {
            std.debug.print("Unwinding to split block {d}\n", .{split_block});
            self.state.block_index = split_block;
            self.state.pc = 0;
            self.state.next_split = null;

            // Copy the parents index
            self.state.index = self.stack.items[self.stack.items.len - 1].index;

            // Copy the parents captures and capture_stack to this state
            self.state.captures.clearAndFree();
            for (self.stack.items[self.stack.items.len - 1].captures.items) |x| {
                try self.state.captures.append(x);
            }

            self.state.capture_stack.clearAndFree();
            for (self.stack.items[self.stack.items.len - 1].capture_stack.items) |x| {
                try self.state.capture_stack.append(x);
            }

            return true;
        }

        // Otherwise, unwind the stack
        self.state.deinit();
        self.state = self.stack.pop();
        std.debug.print("Unwinding to block {d}\n", .{self.state.block_index});

        return true;
    }

    fn join(self: *Self) !bool {
        if (self.stack.items.len == 0) {
            return false;
        }

        var current_state = self.state;
        self.state = self.stack.pop();

        self.state.captures.clearAndFree();
        for (current_state.captures.items) |x| {
            try self.state.captures.append(x);
        }

        self.state.capture_stack.clearAndFree();
        for (current_state.capture_stack.items) |x| {
            try self.state.capture_stack.append(x);
        }

        self.state.index = current_state.index;
        self.state.next_split = current_state.next_split;

        std.debug.print("Joining to block {d}\n", .{self.state.block_index});

        current_state.deinit();
        return true;
    }

    pub fn run(self: *Self) !bool {
        var done = false;
        var return_value = false;

        while (!done) {
            var block = self.blocks.items[self.state.block_index];
            if (self.state.pc < block.items.len) {
                var op = block.items[self.state.pc];
                op.print(self.state.block_index, self.state.pc, self.input_str[0..self.state.index]);
                switch (op) {
                    .char => {
                        if (!self.is_end_of_input()) {
                            if (self.input_str[self.state.index] == op.char) {
                                self.state.index += 1;
                                self.state.pc += 1;
                                continue;
                            } else {
                                if (try self.unwind()) {
                                    continue;
                                }
                                done = true;
                            }
                        } else {
                            if (try self.unwind()) {
                                continue;
                            }
                            done = true;
                        }
                    },
                    .end_of_input => {
                        if (self.is_end_of_input()) {
                            done = true;
                            return_value = true;
                        } else {
                            if (try self.unwind()) {
                                continue;
                            }
                            done = true;
                        }
                    },
                    .digit => {
                        if (!self.is_end_of_input()) {
                            if (self.input_str[self.state.index] >= '0' and self.input_str[self.state.index] <= '9') {
                                self.state.index += 1;
                                self.state.pc += 1;
                                continue;
                            } else {
                                if (try self.unwind()) {
                                    continue;
                                }
                                done = true;
                            }
                        } else {
                            if (try self.unwind()) {
                                continue;
                            }
                            done = true;
                        }
                    },
                    .wildcard => {
                        if (!self.is_end_of_input()) {
                            self.state.index += 1;
                            self.state.pc += 1;
                            continue;
                        } else {
                            if (try self.unwind()) {
                                continue;
                            }
                            done = true;
                        }
                    },
                    .jump => {
                        self.state.block_index = op.jump;
                        self.state.pc = 0;
                        continue;
                    },
                    .jump_and_link => {
                        self.state.pc += 1;
                        try self.stack.append(try self.state.clone());

                        self.state.block_index = op.jump_and_link;
                        self.state.pc = 0;
                        continue;
                    },
                    .split => {
                        self.state.pc += 1;
                        try self.stack.append(try self.state.clone());

                        self.state.next_split = op.split.b;
                        self.state.block_index = op.split.a;
                        self.state.pc = 0;

                        continue;
                    },
                    .end => {
                        done = true;
                        return_value = true;
                    },
                    .start_capture => {
                        try self.state.capture_stack.append(self.state.index);
                        self.state.pc += 1;
                        continue;
                    },
                    .end_capture => {
                        const start = self.state.capture_stack.pop();
                        const end = self.state.index;
                        try self.state.captures.append(self.input_str[start..end]);
                        self.state.pc += 1;
                        continue;
                    },
                }
            } else {
                // This is the case that we've reached the end of the block
                const join_successful = try self.join();
                done = !join_successful;
            }
        }

        return return_value;
    }
};
