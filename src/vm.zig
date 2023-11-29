const std = @import("std");
const Allocator = std.mem.Allocator;

const DebugConfig = @import("debug-config.zig").DebugConfig;

pub const OpType = enum { char, wildcard, whitespace, range, jump, split, end, end_of_input, start_capture, end_capture, list, progress };

var op_count: usize = 0;

pub const ListItemType = enum { char, range, whitespace };
pub const ListItem = union(ListItemType) {
    char: u8,
    range: struct { a: u8, b: u8 },
    whitespace: u8,
};
pub const List = struct { items: usize, negate: bool };
pub const ListItemLists = std.ArrayList(std.ArrayList(ListItem));

pub const Op = union(OpType) {
    // Content based
    char: u8,
    wildcard: u8,
    whitespace: u8,
    range: struct { a: u8, b: u8 },

    // Capture based
    start_capture: usize,
    end_capture: usize,

    // Flow based
    jump: usize,
    split: struct { a: usize, b: usize },
    end: u8,
    progress: usize,
    end_of_input: u8,
    list: List,

    pub fn print(self: *@This(), block_index: usize, pc: usize, match: []const u8) void {
        switch (self.*) {
            OpType.char => std.debug.print("{d}: B{d}.{d}: char({c})         \"{s}\"\n", .{ op_count, block_index, pc, self.char, match }),
            OpType.wildcard => std.debug.print("{d}: B{d}.{d}: wildcard        \"{s}\"\n", .{ op_count, block_index, pc, match }),
            OpType.whitespace => std.debug.print("{d}: B{d}.{d}: whitespace        \"{s}\"\n", .{ op_count, block_index, pc, match }),
            OpType.range => std.debug.print("{d}: B{d}.{d}: range({c}, {c})     \"{s}\"\n", .{ op_count, block_index, pc, self.range.a, self.range.b, match }),
            OpType.split => std.debug.print("{d}: B{d}.{d}: split({d}, {d})     \"{s}\"\n", .{ op_count, block_index, pc, self.split.a, self.split.b, match }),
            OpType.jump => std.debug.print("{d}: B{d}.{d}: jump({d})         \"{s}\"\n", .{ op_count, block_index, pc, self.jump, match }),
            OpType.start_capture => std.debug.print("{d}: B{d}.{d}: start_capture({d}) \"{s}\"\n", .{ op_count, block_index, pc, self.start_capture, match }),
            OpType.list => {
                if (self.list.negate) {
                    std.debug.print("{d}: B{d}.{d}: negative_list({d}) \"{s}\"\n", .{ op_count, block_index, pc, self.list.items, match });
                } else {
                    std.debug.print("{d}: B{d}.{d}: list({d}) \"{s}\"\n", .{ op_count, block_index, pc, self.list.items, match });
                }
            },
            OpType.progress => std.debug.print("{d}: B{d}.{d}: progress({d})  \"{s}\"\n", .{ op_count, block_index, pc, self.progress, match }),
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
            OpType.wildcard => std.debug.print("  wildcard\n", .{}),
            OpType.whitespace => std.debug.print("  whitespace\n", .{}),
            OpType.split => std.debug.print("  split({d}, {d})\n", .{ instruction.split.a, instruction.split.b }),
            OpType.range => std.debug.print("  range({c}, {c})\n", .{ instruction.range.a, instruction.range.b }),
            OpType.jump => std.debug.print("  jump({d})\n", .{instruction.jump}),
            OpType.list => {
                if (instruction.list.negate) {
                    std.debug.print("  negative_list({d})\n", .{instruction.list.items});
                } else {
                    std.debug.print("  list({d})\n", .{instruction.list.items});
                }
            },
            OpType.progress => std.debug.print("  progress({d})\n", .{instruction.progress}),
            OpType.end => std.debug.print("  end\n", .{}),
            OpType.end_of_input => std.debug.print("  end_of_input\n", .{}),
            OpType.start_capture => std.debug.print("  start_capture({d})\n", .{instruction.start_capture}),
            OpType.end_capture => std.debug.print("  end_capture({d})\n", .{instruction.end_capture}),
        }
    }
    std.debug.print("\n", .{});
}

pub const StringMatch = struct {
    index: usize,
    value: []const u8,
};

const ThreadState = struct {
    const Self = @This();

    block_index: usize,
    pc: usize,
    index: usize,
    next_split: ?usize,
    capture_stack_copied: bool = false,
    capture_stack: std.ArrayList(usize),
    captures_copied: bool = false,
    captures: std.AutoHashMap(usize, StringMatch),

    pub fn clone(self: *Self) !ThreadState {
        return .{
            .block_index = self.block_index,
            .pc = self.pc,
            .index = self.index,
            .next_split = self.next_split,
            .capture_stack = self.capture_stack,
            .captures = self.captures,
            .captures_copied = self.captures_copied,
            .capture_stack_copied = self.capture_stack_copied,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.capture_stack_copied) {
            self.capture_stack.deinit();
        }

        if (self.captures_copied) {
            self.captures.deinit();
        }
    }
};

pub const VMInstance = struct {
    const Self = @This();

    blocks: *std.ArrayList(Block),
    state: ThreadState,
    stack: std.ArrayList(ThreadState),
    input_str: []const u8,
    allocator: Allocator,
    deadend_marker: usize = 0,
    config: DebugConfig,
    num_groups: usize = 0,
    match_from_index: usize = 0,
    progress: std.AutoHashMap(usize, ?usize),
    lists: *ListItemLists,

    pub fn init(allocator: Allocator, blocks: *std.ArrayList(Block), lists: *ListItemLists, input_str: []const u8, config: DebugConfig) Self {
        return .{
            .blocks = blocks,
            .state = .{ .block_index = 0, .pc = 0, .index = 0, .next_split = null, .captures = std.AutoHashMap(usize, StringMatch).init(allocator), .capture_stack = std.ArrayList(usize).init(allocator), .captures_copied = true, .capture_stack_copied = true },
            .stack = std.ArrayList(ThreadState).init(allocator),
            .input_str = input_str,
            .allocator = allocator,
            .config = config,
            .progress = std.AutoHashMap(usize, ?usize).init(allocator),
            .lists = lists,
        };
    }

    pub fn deinit(self: *Self) void {
        var i: usize = 0;
        while (i < self.stack.items.len) : (i += 1) {
            self.stack.items[i].deinit();
        }
        self.stack.deinit();
        self.state.deinit();
        self.progress.deinit();
    }

    fn log(self: *Self, comptime fmt: []const u8, args: anytype) void {
        if (self.config.log_execution) {
            std.debug.print(fmt, args);
        }
    }

    pub fn get_match(self: *Self) []const u8 {
        return self.input_str[self.match_from_index..self.state.index];
    }

    fn update_group_count(self: *Self, observed_group_index: usize) void {
        if (observed_group_index >= self.num_groups) {
            self.num_groups = observed_group_index + 1;
        }
    }

    fn is_end_of_input(self: *Self) bool {
        return self.state.index >= self.input_str.len;
    }

    fn push_state(self: *Self) void {
        self.stack.append(self.state);
    }

    fn unwind(self: *Self) !bool {
        if (self.stack.items.len == 0) {
            if (self.match_from_index < self.input_str.len) {
                self.match_from_index += 1;

                self.state.block_index = 0;
                self.state.pc = 0;
                self.state.index = self.match_from_index;
                self.state.next_split = null;
                self.state.captures.clearRetainingCapacity();
                self.state.capture_stack.clearRetainingCapacity();
                self.state.captures_copied = true;
                self.state.capture_stack_copied = true;

                self.log("  <~~ Restart matching from index {d}\n", .{self.match_from_index});
                return true;
            }
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
            if (self.state.captures_copied) {
                self.state.captures.clearRetainingCapacity();
                var it = self.stack.items[self.stack.items.len - 1].captures.iterator();
                while (it.next()) |entry| {
                    try self.state.captures.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }

            if (self.state.capture_stack_copied) {
                self.state.capture_stack.clearRetainingCapacity();
                for (self.stack.items[self.stack.items.len - 1].capture_stack.items) |*state| {
                    try self.state.capture_stack.append(state.*);
                }
            }

            return true;
        }

        // Otherwise, unwind the stack
        self.state.deinit();
        self.state = self.stack.pop();
        self.log("  <-- block {d}\n", .{self.state.block_index});

        return true;
    }

    fn find_copiable_capture_stack(self: *Self) usize {
        var i: usize = self.stack.items.len - 1;
        while (true) : (i -= 1) {
            if (self.stack.items[i].capture_stack_copied) {
                return i;
            }
            if (i == 0) {
                return 0;
            }
        }
    }

    fn find_copiable_captures(self: *Self) usize {
        var i: usize = self.stack.items.len - 1;
        while (true) : (i -= 1) {
            if (self.stack.items[i].captures_copied) {
                return i;
            }
            if (i == 0) {
                return 0;
            }
        }
    }

    fn peek_range(self: *Self, a: u8, b: u8) bool {
        if (!self.is_end_of_input()) {
            if (self.input_str[self.state.index] >= a and self.input_str[self.state.index] <= b) {
                return true;
            }
        }
        return false;
    }

    fn peek_char(self: *Self, char: u8) bool {
        if (!self.is_end_of_input() and self.input_str[self.state.index] == char) {
            return true;
        }
        return false;
    }

    fn match_char(self: *Self, char: u8) !bool {
        if (self.peek_char(char)) {
            self.state.index += 1;
            self.state.pc += 1;
            return true;
        } else {
            if (try self.unwind()) {
                return true;
            }
            return false;
        }
    }

    fn peek_whitespace(self: *Self) bool {
        if (!self.is_end_of_input()) {
            return switch (self.input_str[self.state.index]) {
                ' ' => true,
                '\t' => true,
                '\n' => true,
                '\r' => true,
                0x0c => true, // \f
                else => false,
            };
        }
        return false;
    }

    fn match_whitespace(self: *Self) !bool {
        if (self.peek_whitespace()) {
            self.state.index += 1;
            self.state.pc += 1;
            return true;
        } else {
            if (try self.unwind()) {
                return true;
            }
            return false;
        }
    }

    fn match_end_of_input(self: *Self) !bool {
        if (self.is_end_of_input()) {
            self.state.pc += 1;
            return true;
        } else {
            if (try self.unwind()) {
                return true;
            }
            return false;
        }
    }

    fn match_wildcard(self: *Self) !bool {
        if (!self.is_end_of_input()) {
            self.state.index += 1;
            self.state.pc += 1;
            return true;
        } else {
            if (try self.unwind()) {
                return true;
            }
            return false;
        }
    }

    pub fn run(self: *Self) !bool {
        var done = false;
        var return_value = false;

        while (!done) {
            var block = self.blocks.items[self.state.block_index];
            if (self.state.pc < block.items.len) {
                var op = block.items[self.state.pc];

                if (self.config.log_execution) {
                    op.print(self.state.block_index, self.state.pc, self.get_match());
                }

                switch (op) {
                    .char => {
                        done = !try self.match_char(op.char);
                        continue;
                    },
                    .whitespace => {
                        done = !try self.match_whitespace();
                        continue;
                    },
                    .end_of_input => {
                        done = !try self.match_end_of_input();
                        continue;
                    },
                    .range => {
                        if (self.peek_range(op.range.a, op.range.b)) {
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
                    .wildcard => {
                        done = !try self.match_wildcard();
                        continue;
                    },
                    .jump => {
                        self.state.block_index = op.jump;
                        self.state.pc = 0;
                        continue;
                    },
                    .split => {
                        self.state.pc += 1;
                        try self.stack.append(try self.state.clone());

                        self.state.captures_copied = false;
                        self.state.capture_stack_copied = false;
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
                        self.update_group_count(op.start_capture);
                        if (!self.state.capture_stack_copied) {
                            self.state.capture_stack_copied = true;
                            self.state.capture_stack = try self.stack.items[self.find_copiable_capture_stack()].capture_stack.clone();
                        }
                        try self.state.capture_stack.append(self.state.index);
                        self.state.pc += 1;
                        continue;
                    },
                    .end_capture => {
                        if (!self.state.capture_stack_copied) {
                            self.state.capture_stack_copied = true;
                            self.state.capture_stack = try self.stack.items[self.find_copiable_capture_stack()].capture_stack.clone();
                        }

                        const start = self.state.capture_stack.pop();
                        const end = self.state.index;

                        if (!self.state.captures_copied) {
                            self.state.captures_copied = true;
                            self.state.captures = try self.stack.items[self.find_copiable_captures()].captures.clone();
                        }

                        try self.state.captures.put(op.end_capture, .{ .index = start, .value = self.input_str[start..end] });
                        self.state.pc += 1;
                        continue;
                    },
                    .list => {
                        if (!self.is_end_of_input()) {
                            var is_match = false;

                            for (self.lists.items[op.list.items].items) |list_item| {
                                is_match = switch (list_item) {
                                    .char => self.peek_char(list_item.char),
                                    .range => self.peek_range(list_item.range.a, list_item.range.b),
                                    .whitespace => self.peek_whitespace(),
                                };

                                if (is_match) {
                                    break;
                                }
                            }

                            if (is_match != op.list.negate) {
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
                    .progress => {
                        // The purpose of the progress instruction is to prevent infinite loops
                        // that occur with patterns like (a*)*
                        if (self.progress.get(op.progress)) |prev| {
                            // Have we made progress since the last time we were here?
                            if (prev == self.state.index) {
                                if (try self.unwind()) {
                                    continue;
                                }
                                done = true;
                            } else {
                                // Keep moving forward
                                try self.progress.put(op.progress, self.state.index);
                                self.state.pc += 1;
                            }
                        } else {
                            // This is the first time we have been here, record the progress and keep moving forward
                            try self.progress.put(op.progress, self.state.index);
                            self.state.pc += 1;
                        }
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
