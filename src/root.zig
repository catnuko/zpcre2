const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const re = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});
const PCRE2_ZERO_TERMINATED = ~@as(re.PCRE2_SIZE, 0);

pub const Regex = struct {
    regex: *re.pcre2_code_8,
    matchData: *re.pcre2_match_data_8,
    capture_count: usize,

    pub const RegexError = error{ CompileError, ExecError } || std.mem.Allocator.Error;

    pub fn compile(
        pattern: [:0]const u8,
    ) RegexError!Regex {
        var errornumber: c_int = undefined;
        var erroroffset: re.PCRE2_SIZE = undefined;

        const regex = re.pcre2_compile_8(pattern.ptr, PCRE2_ZERO_TERMINATED, 0, &errornumber, &erroroffset, null) orelse {
            std.debug.print("Error: errorcode {d} at offset {d}\n", .{ errornumber, erroroffset });
            return RegexError.CompileError;
        };

        const matchData = re.pcre2_match_data_create_from_pattern_8(regex, null) orelse {
            std.debug.print("Error: create match data error\n", .{});
            return RegexError.CompileError;
        };

        var capture_count: c_int = undefined;
        const fullinfo_rc = re.pcre2_pattern_info_8(regex, re.PCRE2_INFO_CAPTURECOUNT, &capture_count);
        if (fullinfo_rc != 0) @panic("could not request PCRE2_INFO_CAPTURECOUNT");

        return Regex{
            .regex = regex,
            .matchData = matchData,
            .capture_count = @as(usize, @intCast(capture_count)),
        };
    }

    pub fn deinit(self: *const Regex) void {
        re.pcre2_match_data_free_8(self.matchData);
        re.pcre2_code_free_8(self.regex);
    }

    pub fn match(self: *const Regex, allocator: std.mem.Allocator, s: []const u8) RegexError![]?Capture {
        const rc = re.pcre2_match_8(self.regex, s.ptr, s.len, 0, 0, self.matchData, null);
        if (rc == re.PCRE2_ERROR_NOMATCH) {
            std.debug.print("no match\n", .{});
            return RegexError.ExecError;
        } else if (rc < 0) {
            std.debug.print("matching error\n", .{});
            return RegexError.ExecError;
        } else {
            const ovector = re.pcre2_get_ovector_pointer_8(self.matchData);
            const caps: []?Capture = try allocator.alloc(?Capture, self.capture_count + 1);
            errdefer allocator.free(caps);
            for (caps, 0..) |*cap, i| {
                if (i >= rc) {
                    cap.* = null;
                } else if (ovector[i * 2] == re.PCRE2_SIZE_MAX) {
                    assert(ovector[i * 2 + 1] == re.PCRE2_SIZE_MAX);
                    cap.* = null;
                } else {
                    cap.* = .{
                        .start = @as(usize, @intCast(ovector[2 * i])),
                        .end = @as(usize, @intCast(ovector[2 * i + 1])),
                    };
                }
            }
            return caps;
        }
    }
};

pub const Capture = struct {
    start: usize,
    end: usize,
};

test "compiles" {
    const v = Regex.compile("(");
    try testing.expectError(Regex.RegexError.CompileError, v);
}

test "match" {
    const regex = try Regex.compile("hello");
    defer regex.deinit();
    const caps = try regex.match(std.testing.allocator, "hello");
    defer std.testing.allocator.free(caps);
    try testing.expect(caps.len == 1);
}

test "captures" {
    const regex = try Regex.compile("(a+)b(c+)");
    defer regex.deinit();
    const captures = try regex.match(std.testing.allocator, "aaaaabcc");
    defer std.testing.allocator.free(captures);
    try testing.expectEqualSlices(?Capture, &[_]?Capture{
        .{
            .start = 0,
            .end = 8,
        },
        .{
            .start = 0,
            .end = 5,
        },
        .{
            .start = 6,
            .end = 8,
        },
    }, captures);
}

test "missing capture group" {
    const regex = try Regex.compile("abc(def)(ghi)?(jkl)");
    defer regex.deinit();
    const captures = try regex.match(std.testing.allocator, "abcdefjkl");
    defer std.testing.allocator.free(captures);
    try testing.expectEqualSlices(?Capture, &[_]?Capture{
        .{
            .start = 0,
            .end = 9,
        },
        .{
            .start = 3,
            .end = 6,
        },
        null,
        .{
            .start = 6,
            .end = 9,
        },
    }, captures);
}

test "missing capture group at end of capture list" {
    const regex = try Regex.compile("abc(def)(ghi)?jkl");
    defer regex.deinit();
    const captures = try regex.match(std.testing.allocator, "abcdefjkl");
    defer std.testing.allocator.free(captures);
    try testing.expectEqualSlices(?Capture, &[_]?Capture{
        .{
            .start = 0,
            .end = 9,
        },
        .{
            .start = 3,
            .end = 6,
        },
        null,
    }, captures);
}

test "what" {
    const regex = try Regex.compile("(?:ab|.)*");
    defer regex.deinit();

    const line =
        "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" ++
        "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
       const caps =  try regex.match(std.testing.allocator,line);
       defer std.testing.allocator.free(caps);
    try testing.expect(caps.len != 0);
}
