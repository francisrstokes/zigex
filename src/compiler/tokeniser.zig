const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TokenType = enum { literal, escaped, wildcard, lparen, rparen, alternation, zero_or_one, zero_or_more, one_or_more, lsquare, rsquare, dollar, caret, dash };

pub const Token = struct {
    tok_type: TokenType,
    value: u8 = 0,

    pub fn is_quantifier(self: Token) bool {
        return (self.tok_type == TokenType.zero_or_one) or (self.tok_type == TokenType.zero_or_more) or (self.tok_type == TokenType.one_or_more);
    }

    pub fn can_be_range_literal(self: Token) bool {
        return self.tok_type != TokenType.rsquare;
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
