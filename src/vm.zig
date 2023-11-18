const std = @import("std");
const Allocator = std.mem.Allocator;

pub const OpType = enum { char, digit, wildcard, jump, split, end };

const Op = union(OpType) {
    // Content based
    char: u8,
    digit: u8,
    wildcard: u8,

    // Flow based
    jump: usize,
    split: struct { a: usize, b: usize },
    end: u8,
};

const Wildcard = Op{ .wildcard = '.' };
const Digit = Op{ .digit = 'd' };
const End = Op{ .end = 'e' };

pub const Block = std.ArrayList(Op);
const BlockState = struct {
    block_index: usize,
    pc: usize,
    index: usize,
    next_split: ?usize,
};

pub const State = struct {
    const Self = @This();

    blocks: *std.ArrayList(Block),
    state: BlockState,
    stack: std.ArrayList(BlockState),
    input_str: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, blocks: *std.ArrayList(Block), input_str: []const u8) State {
        return .{
            .blocks = blocks,
            .state = .{ .block_index = 0, .pc = 0, .index = 0, .next_split = null },
            .stack = std.ArrayList(BlockState).init(allocator),
            .input_str = input_str,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit();
    }

    fn is_end_of_input(self: *Self) bool {
        return self.state.index >= self.input_str.len;
    }

    fn push_state(self: *Self) void {
        self.stack.append(self.state);
    }

    fn unwind(self: *Self) bool {
        if (self.stack.items.len == 0) {
            return false;
        }

        // Was this the "A" path? Then try "B"
        if (self.state.next_split) |split_block| {
            self.state.block_index = split_block;
            self.state.pc = 0;
            self.state.next_split = null;
            return true;
        }

        // Otherwise, unwind the stack
        self.state = self.stack.pop();

        return true;
    }

    fn join(self: *Self) bool {
        if (self.stack.items.len == 0) {
            return false;
        }

        const current_state = self.state;
        self.state = self.stack.pop();
        self.state.index = current_state.index;
        self.state.next_split = current_state.next_split;
        return true;
    }

    pub fn run(self: *Self) !bool {
        var done = false;
        var return_value = false;

        while (!done) {
            var block = self.blocks.items[self.state.block_index];
            if (self.state.pc < block.items.len) {
                const op = block.items[self.state.pc];
                switch (op) {
                    .char => {
                        if (!self.is_end_of_input()) {
                            if (self.input_str[self.state.index] == op.char) {
                                self.state.index += 1;
                                self.state.pc += 1;
                                continue;
                            } else {
                                if (self.unwind()) {
                                    continue;
                                }
                                done = true;
                            }
                        } else {
                            if (self.unwind()) {
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
                                if (self.unwind()) {
                                    continue;
                                }
                                done = true;
                            }
                        } else {
                            if (self.unwind()) {
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
                            if (self.unwind()) {
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
                    .split => {
                        self.state.pc += 1;
                        try self.stack.append(self.state);

                        self.state.next_split = op.split.b;
                        self.state.block_index = op.split.a;
                        self.state.pc = 0;

                        continue;
                    },
                    .end => {
                        done = true;
                        return_value = true;
                    },
                }
            } else {
                // This is the case that we've reached the end of the block
                const join_successful = self.join();
                done = !join_successful;
            }
        }

        return return_value;
    }
};
