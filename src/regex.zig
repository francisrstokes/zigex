const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const RegexVmOpType = enum { char, digit, any, jump, split, end };

const RegexVmOp = union(RegexVmOpType) {
    // Content based
    char: u8,
    digit: u8,
    any: u8,

    // Flow based
    jump: *RegexVmBlock,
    split: struct { a: *RegexVmBlock, b: *RegexVmBlock },
    end: u8,
};

const Any = RegexVmOp{ .any = '.' };
const Digit = RegexVmOp{ .digit = 'd' };
const End = RegexVmOp{ .end = 'e' };

const RegexVmBlock = std.ArrayList(RegexVmOp);
const RegexVmBlockState = struct {
    const Self = @This();

    block: *RegexVmBlock,
    pc: usize,
    index: usize,

    pub fn fork(self: *Self, new_block: *RegexVmBlock) Self {
        return .{
            .block = new_block,
            .pc = 0,
            .index = self.index,
        };
    }
};

const RegexVmState = struct {
    const Self = @This();

    state: RegexVmBlockState,
    stack: std.ArrayList(RegexVmBlockState),
    input_str: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, block: *RegexVmBlock, input_str: []const u8) RegexVmState {
        return .{
            .state = .{ .block = block, .pc = 0, .index = 0 },
            .stack = std.ArrayList(RegexVmBlockState).init(allocator),
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
        self.state = self.stack.pop();
        return true;
    }

    pub fn run(self: *Self) !bool {
        var done = false;
        var return_value = false;

        while (!done) {
            if (self.state.pc < self.state.block.items.len) {
                const op = self.state.block.items[self.state.pc];
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
                    .any => {
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
                        self.state.block = op.jump;
                        self.state.pc = 0;
                        continue;
                    },
                    .split => {
                        var state_b = self.state.fork(op.split.b);
                        try self.stack.append(state_b);

                        self.state.block = op.split.a;
                        self.state.pc = 0;

                        continue;
                    },
                    .end => {
                        done = true;
                        return_value = true;
                    },
                }
            }
        }

        return return_value;
    }
};

test "passing: a(?:b\\d)?c+." {
    const allocator = std.testing.allocator;

    var block0 = RegexVmBlock.init(allocator);
    var block1 = RegexVmBlock.init(allocator);
    var block2 = RegexVmBlock.init(allocator);
    var block3 = RegexVmBlock.init(allocator);

    defer block0.deinit();
    defer block1.deinit();
    defer block2.deinit();
    defer block3.deinit();

    try block0.append(RegexVmOp{ .char = 'a' });
    try block0.append(RegexVmOp{ .split = .{ .a = &block1, .b = &block2 } });

    try block1.append(RegexVmOp{ .char = 'b' });
    try block1.append(Digit);
    try block1.append(RegexVmOp{ .jump = &block2 });

    try block2.append(RegexVmOp{ .char = 'c' });
    try block2.append(RegexVmOp{ .split = .{ .a = &block2, .b = &block3 } });

    try block3.append(Any);
    try block3.append(End);

    // Minimal passing string
    var vm = RegexVmState.init(allocator, &block0, "acc");
    try std.testing.expect(try vm.run());
    vm.deinit();

    // Longer passing string
    vm = RegexVmState.init(allocator, &block0, "ab1ccccccccccccx");
    try std.testing.expect(try vm.run());
    vm.deinit();
}

test "failing: a(?:b\\d)?c+." {
    const allocator = std.testing.allocator;

    var block0 = RegexVmBlock.init(allocator);
    var block1 = RegexVmBlock.init(allocator);
    var block2 = RegexVmBlock.init(allocator);
    var block3 = RegexVmBlock.init(allocator);

    defer block0.deinit();
    defer block1.deinit();
    defer block2.deinit();
    defer block3.deinit();

    try block0.append(RegexVmOp{ .char = 'a' });
    try block0.append(RegexVmOp{ .split = .{ .a = &block1, .b = &block2 } });

    try block1.append(RegexVmOp{ .char = 'b' });
    try block1.append(Digit);
    try block1.append(RegexVmOp{ .jump = &block2 });

    try block2.append(RegexVmOp{ .char = 'c' });
    try block2.append(RegexVmOp{ .split = .{ .a = &block2, .b = &block3 } });

    try block3.append(Any);
    try block3.append(End);

    var vm = RegexVmState.init(allocator, &block0, "ac");
    try std.testing.expect(!try vm.run());
    vm.deinit();

    vm = RegexVmState.init(allocator, &block0, "abc");
    try std.testing.expect(!try vm.run());
    vm.deinit();
}

pub fn main() !void {}
