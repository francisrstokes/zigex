const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const parser = @import("parser.zig");
const vm = @import("vm.zig");

pub fn print_block(block: vm.Block, index: usize) void {
    std.debug.print("Block {d}:\n", .{index});

    if (block.items.len == 0) {
        std.debug.print("  <empty>\n", .{});
    }

    for (block.items) |instruction| {
        switch (instruction) {
            vm.OpType.char => std.debug.print("  char({c})\n", .{instruction.char}),
            vm.OpType.digit => std.debug.print("  digit\n", .{}),
            vm.OpType.wildcard => std.debug.print("  wildcard\n", .{}),
            vm.OpType.split => std.debug.print("  split({d}, {d})\n", .{ instruction.split.a, instruction.split.b }),
            vm.OpType.jump => std.debug.print("  jump({d})\n", .{instruction.jump}),
            vm.OpType.end => std.debug.print("  end\n", .{}),
            vm.OpType.end_of_input => std.debug.print("  end_of_input\n", .{}),
        }
    }
    std.debug.print("\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <regex> <input>\n", .{args[0]});
        std.process.exit(1);
        return;
    }

    const re_str = args[1];
    const input = args[2];

    // const re_str = "a?b+.*\\d";
    // const input = "";

    std.debug.print("Regex: {s}\n", .{re_str});
    std.debug.print("Input: \"{s}\"\n", .{input});

    var re = parser.Regex.init(allocator, re_str);
    defer re.deinit();
    var tokens = try re.tokenise();
    defer tokens.deinit();

    var AST = try re.parse(tokens);
    defer AST.deinit();

    std.debug.print("\n------------- AST -------------\n", .{});
    try AST.root.pretty_print(allocator, 4096);

    try re.compile(AST.root);
    var i: usize = 0;

    std.debug.print("\n---------- VM Blocks ----------\n", .{});
    for (re.blocks.items) |block| {
        print_block(block, i);
        i += 1;
    }

    var re_state = vm.State.init(allocator, &re.blocks, input);
    defer re_state.deinit();
    var match = try re_state.run();

    std.debug.print("input {s} on \"{s}\" -> {any}\n", .{ re_str, input, match });
}

test "a" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    const input_str = "a";
    const regex_str = "a";

    var re = parser.Regex.init(allocator, regex_str);
    defer re.deinit();

    var tokens = try re.tokenise();
    defer tokens.deinit();

    var AST = try re.parse(tokens);
    defer AST.deinit();

    try re.compile(AST.root);

    var re_state = vm.State.init(allocator, &re.blocks, input_str);
    defer re_state.deinit();

    var match = try re_state.run();

    try expect(match);
}
