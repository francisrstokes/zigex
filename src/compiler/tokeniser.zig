const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TokenType = enum {
    literal,
    escaped,
    wildcard,
    lparen,
    rparen,
    alternation,
    zero_or_one,
    zero_or_more,
    one_or_more,
    lsquare,
    rsquare,
    dollar,
    caret,
    dash,
};

pub const Token = struct {
    tok_type: TokenType,
    value: u8 = 0,

    pub fn is_quantifier(self: Token) bool {
        return (self.tok_type == TokenType.zero_or_one) or (self.tok_type == TokenType.zero_or_more) or (self.tok_type == TokenType.one_or_more);
    }

    pub fn can_be_range_literal(self: Token) bool {
        return self.tok_type != TokenType.rsquare;
    }

    pub fn print(self: *@This()) void {
        switch (self.tok_type) {
            .literal => std.debug.print("literal({c})\n", .{self.value}),
            .escaped => std.debug.print("escaped({c})\n", .{self.value}),
            .wildcard => std.debug.print("wildcard\n", .{}),
            .lparen => std.debug.print("lparen\n", .{}),
            .rparen => std.debug.print("rparen\n", .{}),
            .alternation => std.debug.print("alternation\n", .{}),
            .zero_or_one => std.debug.print("zero_or_one\n", .{}),
            .zero_or_more => std.debug.print("zero_or_more\n", .{}),
            .one_or_more => std.debug.print("one_or_more\n", .{}),
            .lsquare => std.debug.print("lsquare\n", .{}),
            .rsquare => std.debug.print("rsquare\n", .{}),
            .dollar => std.debug.print("dollar\n", .{}),
            .caret => std.debug.print("caret\n", .{}),
            .dash => std.debug.print("dash\n", .{}),
        }
    }
};

pub const TokenStream = struct {
    const Self = @This();

    tokens: std.ArrayList(Token),
    index: usize = 0,

    pub fn init(allocator: Allocator) !Self {
        return Self{ .tokens = std.ArrayList(Token).init(allocator) };
    }

    pub fn available(self: *Self) usize {
        return self.tokens.items.len - self.index;
    }

    pub fn peek(self: *Self, distance: usize) ?Token {
        if ((self.index + distance) >= self.tokens.items.len) {
            return null;
        }
        return self.tokens.items[self.index + distance];
    }

    pub fn consume(self: *Self) !Token {
        if (self.index >= self.tokens.items.len) {
            return error.OutOfBounds;
        }
        var token = self.tokens.items[self.index];
        self.index += 1;
        return token;
    }

    pub fn append(self: *Self, token: Token) !void {
        try self.tokens.append(token);
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    pub fn print(self: *Self) void {
        for (self.tokens.items) |*token| {
            token.print();
        }
    }
};

pub fn tokenise(allocator: Allocator, regular_expression: []const u8) !TokenStream {
    var token_stream = try TokenStream.init(allocator);

    var i: usize = 0;
    while (i < regular_expression.len) : (i += 1) {
        switch (regular_expression[i]) {
            '(' => try token_stream.append(.{ .tok_type = .lparen, .value = '(' }),
            ')' => try token_stream.append(.{ .tok_type = .rparen, .value = ')' }),
            '[' => try token_stream.append(.{ .tok_type = .lsquare, .value = '[' }),
            '-' => try token_stream.append(.{ .tok_type = .dash, .value = '-' }),
            ']' => try token_stream.append(.{ .tok_type = .rsquare, .value = ']' }),
            '|' => try token_stream.append(.{ .tok_type = .alternation, .value = '|' }),
            '.' => try token_stream.append(.{ .tok_type = .wildcard, .value = '.' }),
            '*' => try token_stream.append(.{ .tok_type = .zero_or_more, .value = '*' }),
            '?' => try token_stream.append(.{ .tok_type = .zero_or_one, .value = '?' }),
            '+' => try token_stream.append(.{ .tok_type = .one_or_more, .value = '+' }),
            '$' => try token_stream.append(.{ .tok_type = .dollar, .value = '$' }),
            '^' => try token_stream.append(.{ .tok_type = .caret, .value = '^' }),
            '\\' => {
                if (i + 1 >= regular_expression.len) {
                    return error.OutOfBounds;
                }
                try token_stream.append(.{ .tok_type = .escaped, .value = regular_expression[i + 1] });
                i += 1;
            },
            else => {
                try token_stream.append(.{ .tok_type = .literal, .value = regular_expression[i] });
            },
        }
    }

    return token_stream;
}
