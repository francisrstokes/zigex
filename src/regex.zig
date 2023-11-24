const std = @import("std");
const Allocator = std.mem.Allocator;

const Tokeniser = @import("compiler/tokeniser.zig");
const Parser = @import("compiler/parser.zig").Parser;
const compiler = @import("compiler/compiler.zig");
const Compiler = compiler.Compiler;
const vm = @import("vm.zig");
const VMInstance = vm.VMInstance;
const DebugConfig = @import("debug-config.zig").DebugConfig;

pub const MatchObject = struct {
    const Self = @This();

    num_groups: usize,
    groups: std.AutoHashMap(usize, []const u8),
    match: []const u8,

    pub fn get_match(self: *Self) []const u8 {
        return self.match;
    }

    pub fn get_group(self: *Self, group: usize) !?[]const u8 {
        // Groups are actually 1-indexed, but we store them as 0-indexed.
        if (group == 0) {
            return null;
        }
        return self.groups.get(group - 1);
    }

    pub fn get_groups(self: *Self, allocator: Allocator) !std.ArrayList(?[]const u8) {
        var array = std.ArrayList(?[]const u8).init(allocator);
        for (0..self.num_groups) |i| {
            try array.append(self.groups.get(i));
        }
        return array;
    }

    pub fn deinit(self: *Self) void {
        self.groups.deinit();
    }
};

pub const Regex = struct {
    const Self = @This();

    allocator: Allocator,
    vm_blocks: std.ArrayList(vm.Block),
    debug_config: DebugConfig,

    pub fn init(allocator: Allocator, regular_expression: []const u8, debug_config: DebugConfig) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var arena_allocator = arena.allocator();

        var token_stream = try Tokeniser.tokenise(arena_allocator, regular_expression);
        var ast = try Parser.parse(arena_allocator, &token_stream);
        if (debug_config.dump_ast) {
            std.debug.print("\n------------- AST -------------\n", .{});
            ast.root.pretty_print(&ast.ophan_nodes, &ast.node_lists);
        }

        var vm_blocks = try Compiler.compile(allocator, &ast);
        if (debug_config.dump_blocks) {
            var i: usize = 0;
            std.debug.print("\n---------- VM Blocks ----------\n", .{});
            for (vm_blocks.items) |block| {
                vm.print_block(block, i);
                i += 1;
            }
        }

        return .{
            .allocator = allocator,
            .vm_blocks = vm_blocks,
            .debug_config = debug_config,
        };
    }

    pub fn match(self: *Self, input: []const u8) !?MatchObject {
        var vm_instance = VMInstance.init(self.allocator, &self.vm_blocks, input, self.debug_config);
        defer vm_instance.deinit();
        const matched = try vm_instance.run();

        if (!matched) {
            return null;
        }

        return MatchObject{ .num_groups = vm_instance.num_groups, .groups = vm_instance.state.captures.move(), .match = vm_instance.get_match() };
    }

    pub fn deinit(self: *Self) void {
        compiler.blocks_deinit(self.vm_blocks);
    }
};
