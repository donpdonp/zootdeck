const std = @import("std");
const warn = std.debug.warn;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Buffers = @import("./simple_buffer.zig");

pub fn jsonStrDecode(str: []const u8, allocator: *Allocator) ![]const u8 {
    var escMarks = try jsonTokenize(str, allocator);
    defer allocator.free(escMarks);
    return try jsonBuild(str, escMarks, allocator);
}

const escMark = struct { position: usize, char: u8 };

pub fn jsonTokenize(str: []const u8, allocator: *Allocator) ![]escMark {
    const States = enum { Looking, EscBegin, uFound, Digit };
    var state = States.Looking;
    var escMarks = std.ArrayList(escMark).init(allocator);
    var escStartIdx: usize = undefined;
    for (str) |char, idx| {
        if (state == States.Looking and char == '\\') {
            state = States.EscBegin;
            escStartIdx = idx;
        } else if (state == States.EscBegin) {
            if (char == 'u' or char == 'U') {
                state = States.uFound;
            } else if (char == '"') {
                try escMarks.append(escMark{ .position = escStartIdx, .char = '"' });
                state = States.Looking;
            } else if (char == 'n') {
                try escMarks.append(escMark{ .position = escStartIdx, .char = '\n' });
                state = States.Looking;
            } else {
                state = States.Looking;
            }
        } else if (state == States.uFound) {
            if (isHexDigit(char)) {
                state = States.Digit;
            } else {
                state = States.Looking;
            }
        } else if (state == States.Digit) {
            if (isHexDigit(char)) {
                const escLen = idx - escStartIdx;
                if (escLen == 5) { // last byte of the \uXXXX code
                    try escMarks.append(escMark{ .position = escStartIdx, .char = 'u' });
                    state = States.Looking;
                }
            } else {
                state = States.Looking;
            }
        }
    }
    return escMarks.toOwnedSlice();
}

test "jsonTokenize" {
    var parts = try jsonTokenize("ab", std.testing.allocator);
    defer std.testing.allocator.free(parts);
    std.testing.expectEqual(@as(usize, 0), parts.len);

    var parts2 = try jsonTokenize("ab\\n", std.testing.allocator);
    defer std.testing.allocator.free(parts2);
    std.testing.expectEqual(@as(usize, 1), parts2.len);
    std.testing.expectEqual(@as(usize, 2), parts2[0].position);
    std.testing.expectEqual(@as(u8, '\n'), parts2[0].char);
}

pub fn jsonBuild(str: []const u8, escMarks: []escMark, allocator: *Allocator) ![]const u8 {
    var newStr = std.ArrayList(u8).init(allocator); //try Buffers.SimpleU8.initSize(allocator, 0);
    var previousStrEndMark: usize = 0;
    for (escMarks) |strMark, idx| {
        // copy the segment before the mark
        const snip = str[previousStrEndMark..strMark.position];
        try newStr.appendSlice(snip);
        if (strMark.char == 'u') {
            previousStrEndMark = strMark.position + 6;

            const digits = str[strMark.position + 2 .. strMark.position + 6];
            var decodedChar: u8 = (hexCharToByte(digits[2]) << 4) + (hexCharToByte(digits[3]));
            try newStr.append(decodedChar);
        }
        if (strMark.char == '"') {
            previousStrEndMark = strMark.position + 2;
            try newStr.append('\"');
        }
        if (strMark.char == 'n') {
            previousStrEndMark = strMark.position + 2;
            try newStr.append('\n');
        }
    }
    // copy the segment after the last mark if there is one
    if (previousStrEndMark <= str.len) {
        try newStr.appendSlice(str[previousStrEndMark..]);
    }
    return newStr.toOwnedSlice();
}

test "jsonStrDecode" {
    var allocator = std.testing.allocator;
    var decoded: []const u8 = undefined;
    decoded = jsonStrDecode("\\u0040p \\u003cY", allocator) catch unreachable;
    defer allocator.free(decoded);
    std.testing.expect(std.mem.eql(u8, decoded, "@p <Y"));

    decoded = jsonStrDecode("a \\\"real\\\" fan.", allocator) catch unreachable;
    defer allocator.free(decoded);
    std.testing.expect(std.mem.eql(u8, decoded, "a \"real\" fan."));
}

pub fn hexCharToByte(char: u8) u8 {
    if (char >= '0' and char <= '9') {
        return char - '0';
    } else if (char >= 'a' and char <= 'f') {
        return char - 'a' + 10;
    } else if (char >= 'A' and char <= 'F') {
        return char - 'A' + 10;
    } else {
        return 0; //unreachable-ish
    }
}

pub fn isHexDigit(char: u8) bool {
    return (char >= '0' and char <= '9') or (char >= 'a' and char <= 'f') or (char >= 'A' and char <= 'F');
}

pub fn toJson(allocator: *Allocator, value: var) []const u8 {
    return toJsonStep(value, 0, allocator);
}

pub fn toJsonStep(value: var, oldDepth: u32, allocator: *Allocator) []const u8 {
    var depth = oldDepth;
    var ram: []u8 = allocator.alloc(u8, 4096) catch unreachable;
    var ptr: usize = 0;
    const T = comptime @TypeOf(value);
    const info = comptime @typeInfo(T);

    if (@typeInfo(T) == builtin.TypeId.Struct) {
        if (comptime std.meta.trait.hasField("items")(T)) {
            ptr += ramSetAt(ram, ptr, toJsonStep(value.items, depth, allocator));
        } else {
            depth += 1;
            ptr += structToJson(ram, ptr, depth, value, allocator);
        }
    } else if (@typeInfo(T) == builtin.TypeId.Union) {
        if (info.Union.tag_type) |UnionTagType| {
            inline for (info.Union.fields) |u_field| {
                if (@enumToInt(UnionTagType(value)) == u_field.enum_field.?.value) {
                    // TODO
                }
            }
        }
    } else if (@typeInfo(T) == builtin.TypeId.Optional) {
        if (value) |val| {
            ptr += ramSetAt(ram, ptr, toJsonStep(val, depth, allocator));
        } else {
            ptr += nullToJson(ram, ptr, depth);
        }
        //warn("typeid optional. child {}\n", info.Optional.child);
    } else if (@typeInfo(T) == builtin.TypeId.Pointer) {
        if (info.Pointer.size == builtin.TypeInfo.Pointer.Size.Slice) {
            if (info.Pointer.child == u8) {
                ptr += strToJson(ram, ptr, depth, value);
            } else {
                depth += 1;
                ptr += arrayishToJson(ram, ptr, depth, value, allocator);
            }
        }
        if (info.Pointer.size == builtin.TypeInfo.Pointer.Size.One) {
            ptr += ramSetAt(ram, ptr, toJsonStep(value.*, depth, allocator));
        }
    } else if (@typeInfo(T) == builtin.TypeId.Array) {
        if (info.Array.child == u8) {
            depth += 1;
            ptr += strToJson(ram, ptr, depth, value);
        } else {
            warn("array unknown\n");
            for (value) |item| {
                warn("array item {c}\n", item);
            }
        }
    } else if (@typeInfo(T) == builtin.TypeId.Int) {
        ptr += intToJson(ram, ptr, depth, value, allocator);
    } else if (@typeInfo(T) == builtin.TypeId.Bool) {
        ptr += boolToJson(ram, ptr, depth, value, allocator);
    } else {
        warn("JSON TYPE UNKNOWN {} {}\n", @typeInfo(T), @typeName(T));
    }
    return ram[0..ptr];
}

pub fn boolToJson(ram: []u8, oldPtr: usize, depth: u32, value: bool, allocator: *Allocator) usize {
    var ptr = oldPtr; // params are const
    ptr += ramSetAt(ram, ptr, if (value) "true" else "false");
    return ptr;
}

pub fn intToJson(ram: []u8, oldPtr: usize, depth: u32, value: var, allocator: *Allocator) usize {
    var ptr = oldPtr; // params are const
    const intlen = 20;
    var intbuf = allocator.alloc(u8, intlen) catch unreachable;
    var intstr = std.fmt.bufPrint(intbuf, "{}", .{value}) catch unreachable;
    ptr += ramSetAt(ram, ptr, intstr);
    return ptr;
}

pub fn strToJson(ram: []u8, oldPtr: usize, depth: u32, value: var) usize {
    var ptr = oldPtr; // params are const
    ptr += ramSetAt(ram, ptr, "\"");
    ptr += ramSetAt(ram, ptr, value);
    ptr += ramSetAt(ram, ptr, "\"");
    return ptr;
}

pub fn nullToJson(ram: []u8, oldPtr: usize, depth: u32) usize {
    var ptr = oldPtr; // params are const
    ptr += ramSetAt(ram, ptr, "null");
    return ptr;
}

pub fn structToJson(ram: []u8, oldPtr: usize, depth: u32, value: var, allocator: *Allocator) usize {
    var ptr = oldPtr; // params are const
    const info = comptime @typeInfo(@TypeOf(value));
    ptr += ramSetAt(ram, ptr, "{\n");
    inline for (info.Struct.fields) |*field_info, idx| {
        const name = field_info.name;
        //warn("struct field {} name {}\n", idx, name);
        ptr += ramSetAt(ram, ptr, space(depth, allocator));
        ptr += ramSetAt(ram, ptr, "\"" ++ name ++ "\" : ");
        var fieldVal: field_info.field_type = @field(value, name);
        ptr += ramSetAt(ram, ptr, toJsonStep(fieldVal, depth, allocator));
        if (idx < info.Struct.fields.len - 1) {
            ptr += ramSetAt(ram, ptr, ",\n");
        }
    }
    ptr += ramSetAt(ram, ptr, "}");
    return ptr;
}
pub fn space(depth: usize, allocator: *Allocator) []const u8 {
    var newstr = allocator.alloc(u8, depth) catch unreachable;
    std.mem.set(u8, newstr[0..depth], ' ');
    return newstr;
}

pub fn arrayishToJson(ram: []u8, oldPtr: usize, oldDepth: u32, value: var, allocator: *Allocator) usize {
    var depth = oldDepth;
    var ptr = oldPtr; // params are const
    const info = comptime @typeInfo(@TypeOf(value));
    ptr += ramSetAt(ram, ptr, "[\n");
    depth += 1;
    for (value) |item, idx| {
        ptr += ramSetAt(ram, ptr, space(depth, allocator));
        ptr += ramSetAt(ram, ptr, toJsonStep(item, depth, allocator));
        if (idx < value.len - 1) {
            ptr += ramSetAt(ram, ptr, ",\n");
        }
    }
    ptr += ramSetAt(ram, ptr, "]\n");
    return ptr;
}

pub fn ramSetAt(ram: []u8, ptr: usize, extra: []const u8) usize {
    var newPtr = ptr + extra.len;
    std.mem.copy(u8, ram[ptr..newPtr], extra);
    return extra.len;
}
