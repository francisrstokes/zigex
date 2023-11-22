const std = @import("std");
const Allocator = std.mem.Allocator;

pub const OpType = enum { char, digit, wildcard, range, jump, split, end, end_of_input, start_capture, end_capture };

var op_count: usize = 0;

const Op = union(OpType) {
    // Content based
    char: u8,
    digit: u8,
    wildcard: u8,
    range: struct { a: u8, b: u8 },

    // Capture based
    start_capture: usize,
    end_capture: usize,

    // Flow based
    jump: usize,
    split: struct { a: usize, b: usize },
    end: u8,
    end_of_input: u8,

    pub fn print(self: *@This(), block_index: usize, pc: usize, match: []const u8) void {
        switch (self.*) {
            OpType.char => std.debug.print("{d}: B{d}.{d}: char({c})         \"{s}\"\n", .{ op_count, block_index, pc, self.char, match }),
            OpType.digit => std.debug.print("{d}: B{d}.{d}: digit           \"{s}\"\n", .{ op_count, block_index, pc, match }),
            OpType.wildcard => std.debug.print("{d}: B{d}.{d}: wildcard        \"{s}\"\n", .{ op_count, block_index, pc, match }),
            OpType.range => std.debug.print("{d}: B{d}.{d}: range({c}, {c})     \"{s}\"\n", .{ op_count, block_index, pc, self.range.a, self.range.b, match }),
            OpType.split => std.debug.print("{d}: B{d}.{d}: split({d}, {d})     \"{s}\"\n", .{ op_count, block_index, pc, self.split.a, self.split.b, match }),
            OpType.jump => std.debug.print("{d}: B{d}.{d}: jump({d})         \"{s}\"\n", .{ op_count, block_index, pc, self.jump, match }),
            OpType.start_capture => std.debug.print("{d}: B{d}.{d}: start_capture({d}) \"{s}\"\n", .{ op_count, block_index, pc, self.start_capture, match }),
            OpType.end_capture => std.debug.print("{d}: B{d}.{d}: end_capture({d})  \"{s}\"\n", .{ op_count, block_index, pc, self.end_capture, match }),
            OpType.end => std.debug.print("{d}: B{d}.{d}: end             \"{s}\"\n", .{ op_count, block_index, pc, match }),
            OpType.end_of_input => std.debug.print("{d}: B{d}.{d}: end_of_input    \"{s}\"\n", .{ op_count, block_index, pc, match }),
        }
        op_count += 1;
    }
};

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
            OpType.range => std.debug.print("  range({c}, {c})\n", .{ instruction.range.a, instruction.range.b }),
            OpType.jump => std.debug.print("  jump({d})\n", .{instruction.jump}),
            OpType.end => std.debug.print("  end\n", .{}),
            OpType.end_of_input => std.debug.print("  end_of_input\n", .{}),
            OpType.start_capture => std.debug.print("  start_capture({d})\n", .{instruction.start_capture}),
            OpType.end_capture => std.debug.print("  end_capture({d})\n", .{instruction.end_capture}),
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
    captures: std.AutoHashMap(usize, []const u8),

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

    const Config = struct { log: bool = false };

    blocks: *std.ArrayList(Block),
    state: ThreadState,
    stack: std.ArrayList(ThreadState),
    input_str: []const u8,
    allocator: Allocator,
    config: Config,

    pub fn init(allocator: Allocator, blocks: *std.ArrayList(Block), input_str: []const u8, config: Config) State {
        return .{
            .blocks = blocks,
            .state = .{ .block_index = 0, .pc = 0, .index = 0, .next_split = null, .captures = std.AutoHashMap(usize, []const u8).init(allocator), .capture_stack = std.ArrayList(usize).init(allocator) },
            .stack = std.ArrayList(ThreadState).init(allocator),
            .input_str = input_str,
            .allocator = allocator,
            .config = config,
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

    fn log(self: *Self, comptime fmt: []const u8, args: anytype) void {
        if (self.config.log) {
            std.debug.print(fmt, args);
        }
    }

    pub fn get_match(self: *Self) []const u8 {
        return self.input_str[0..self.state.index];
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
            self.log("  <-- split block {d}\n", .{split_block});
            self.state.block_index = split_block;
            self.state.pc = 0;
            self.state.next_split = null;

            // Copy the parents index
            self.state.index = self.stack.items[self.stack.items.len - 1].index;

            // Copy the parents captures and capture_stack to this state
            self.state.captures.deinit();
            self.state.captures = try self.stack.items[self.stack.items.len - 1].captures.clone();

            self.state.capture_stack.deinit();
            self.state.capture_stack = try self.stack.items[self.stack.items.len - 1].capture_stack.clone();

            return true;
        }

        // Otherwise, unwind the stack
        self.state.deinit();
        self.state = self.stack.pop();
        self.log("  <-- block {d}\n", .{self.state.block_index});

        return true;
    }

    pub fn run(self: *Self) !bool {
        var done = false;
        var return_value = false;

        while (!done) {
            var block = self.blocks.items[self.state.block_index];
            if (self.state.pc < block.items.len) {
                var op = block.items[self.state.pc];

                if (self.config.log) {
                    op.print(self.state.block_index, self.state.pc, self.get_match());
                }

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
                    .range => {
                        if (!self.is_end_of_input()) {
                            if (self.input_str[self.state.index] >= op.range.a and self.input_str[self.state.index] <= op.range.b) {
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
                        try self.state.captures.put(op.end_capture, self.input_str[start..end]);
                        self.state.pc += 1;
                        continue;
                    },
                    // else => @panic("Unknown op type"),
                }
            } else {
                if (try self.unwind()) {
                    continue;
                }
                done = true;
            }
        }

        return return_value;
    }
};
