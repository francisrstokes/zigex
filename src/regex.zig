const std = @import("std");
const Allocator = std.mem.Allocator;

const Tokeniser = @import("compiler/tokeniser.zig");
const Parser = @import("compiler/parser.zig").Parser;
const compiler = @import("compiler/compiler.zig");
const Compiler = compiler.Compiler;
const vm = @import("vm.zig");
const StringMatch = vm.StringMatch;
const VMInstance = vm.VMInstance;
const ListItemLists = vm.ListItemLists;
const DebugConfig = @import("debug-config.zig").DebugConfig;

pub const MatchObject = struct {
    const Self = @This();

    num_groups: usize,
    groups: std.AutoHashMap(usize, StringMatch),
    match: StringMatch,

    pub fn get_match(self: *Self) StringMatch {
        return self.match;
    }

    pub fn get_group(self: *Self, group: usize) !?StringMatch {
        // Groups are actually 1-indexed, but we store them as 0-indexed.
        if (group == 0) {
            return null;
        }
        return self.groups.get(group - 1);
    }

    pub fn get_groups(self: *Self, allocator: Allocator) !std.ArrayList(?StringMatch) {
        var array = std.ArrayList(?StringMatch).init(allocator);
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
    vm_lists: ListItemLists,
    debug_config: DebugConfig,

    pub fn init(allocator: Allocator, regular_expression: []const u8, debug_config: DebugConfig) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var arena_allocator = arena.allocator();

        var token_stream = try Tokeniser.tokenise(arena_allocator, regular_expression);
        var parsed = try Parser.parse(arena_allocator, &token_stream);
        if (debug_config.dump_ast) {
            std.debug.print("\n------------- AST -------------\n", .{});
            parsed.ast.pretty_print(&parsed.orphan_nodes, &parsed.node_lists);
        }

        var compilation_result = try Compiler.compile(allocator, &parsed);
        if (debug_config.dump_blocks) {
            var i: usize = 0;
            std.debug.print("\n---------- VM Blocks ----------\n", .{});
            for (compilation_result.blocks.items) |block| {
                vm.print_block(block, i);
                i += 1;
            }
        }

        return .{
            .allocator = allocator,
            .vm_blocks = compilation_result.blocks,
            .vm_lists = compilation_result.lists,
            .debug_config = debug_config,
        };
    }

    pub fn match(self: *Self, input: []const u8) !?MatchObject {
        var vm_instance = VMInstance.init(self.allocator, &self.vm_blocks, &self.vm_lists, input, self.debug_config);
        defer vm_instance.deinit();
        const matched = try vm_instance.run();

        if (!matched) {
            return null;
        }

        var groups = if (vm_instance.state.captures_copied) vm_instance.state.captures else vm_instance.stack.items[vm_instance.stack.items.len - 1].captures;

        const match_string = StringMatch{ .index = vm_instance.match_from_index, .value = vm_instance.get_match() };
        return MatchObject{ .num_groups = vm_instance.num_groups, .groups = try groups.clone(), .match = match_string };
    }

    pub fn deinit(self: *Self) void {
        compiler.blocks_deinit(self.vm_blocks);
        for (self.vm_lists.items) |list| {
            list.deinit();
        }
        self.vm_lists.deinit();
    }
};
