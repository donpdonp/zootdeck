const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const Buffers = @import("./simple_buffer.zig");

pub fn sliceToCstr(allocator: *Allocator, str: []const u8) [*]u8 {
  //const str_null: []u8 = std.cstr.addNullByte(allocator, colNew.config.title) catch unreachable;
  var str_null: []u8 = allocator.alloc(u8, str.len+1) catch unreachable;
  std.mem.copy(u8, str_null[0..], str);
  str_null[str.len] = 0;
  return str_null.ptr;
}

pub fn cstrToSlice(allocator: *Allocator, cstr: [*c]const u8) []const u8 {
  var i: usize = std.mem.len(u8, cstr);
  var ram = allocator.alloc(u8, i) catch unreachable;
  std.mem.copy(u8, ram, cstr[0..i]);
  return ram;
}

pub fn listContains(comptime T: type, list: std.LinkedList(T), item: T) bool {
  var ptr = list.first;
  while(ptr) |listItem| {
    if(tootIdSame(T, listItem.data, item)) {
      return true;
    }
    ptr = listItem.next;
  }
  return false;
}

fn tootIdSame(comptime T: type, a: T, b: T) bool {
  return std.mem.eql(u8, a.get("id").?.value.String, b.get("id").?.value.String);
}

pub fn listSortedInsert(comptime T: type, list: *std.LinkedList(T), item: T, allocator: *Allocator) void {
  const itemDate = item.get("created_at").?.value.String;
  const node = list.createNode(item, allocator) catch unreachable;
  var current = list.first;
  while(current) |listItem| {
    const listItemDate = listItem.data.get("created_at").?.value.String;
    if(std.mem.compare(u8, itemDate, listItemDate) == std.mem.Compare.GreaterThan) {
      list.insertBefore(listItem, node);
      return;
    } else {
    }
    current = listItem.next;
  }
  list.append(node);
}

pub fn listCount(comptime T: type, list: std.LinkedList(T)) usize {
  var count = usize(0);
  var current = list.first;
  while(current) |item| { count = count +1; current = item.next; }
  return count;
}

pub fn mastodonExpandUrl(host: []const u8, allocator: *Allocator) []const u8 {
  var url = Buffers.SimpleU8.initSize(allocator, 0) catch unreachable;
  var filteredHost = host;
  if(filteredHost[filteredHost.len-1] == '/') {
    filteredHost = filteredHost[0..filteredHost.len-1];
  }
  if(std.mem.compare(u8, filteredHost, "https:") != std.mem.Compare.Equal) {
    url.append("https://") catch unreachable;
  }
  url.append(filteredHost) catch unreachable;
  url.append("/api/v1/timelines/public") catch unreachable;
  return url.toSliceConst();
}

pub fn htmlTagStrip(str: []const u8, allocator: *Allocator) ![]const u8 {
  var newStr = try Buffers.SimpleU8.initSize(allocator, 0);
  const States = enum {Looking, TagBegin};
  var state = States.Looking;
  var tagEndPlusOne: usize = 0;
  for (str) |char, idx| {
    if (state == States.Looking and char == '<') {
      state = States.TagBegin;
      try newStr.append(str[tagEndPlusOne..idx]);
    } else if (state == States.TagBegin and char == '>') {
      tagEndPlusOne = idx+1;
      state = States.Looking;
    }
  }
  if(tagEndPlusOne <= str.len) {
    try newStr.append(str[tagEndPlusOne..]);
  }
  return newStr.toSliceConst();
}

test "htmlTagStrip" {
  const allocator = std.debug.global_allocator;
  var stripped = htmlTagStrip("a<p>b</p>", allocator) catch unreachable;
  std.testing.expect(std.mem.eql(u8, stripped, "ab"));
  stripped = htmlTagStrip("a<p>b</p>c", allocator) catch unreachable;
  std.testing.expect(std.mem.eql(u8, stripped, "abc"));
  stripped = htmlTagStrip("a<a img=\"\">b</a>c", allocator) catch unreachable;
  std.testing.expect(std.mem.eql(u8, stripped, "abc"));
}

pub fn htmlEntityDecode(str: []const u8, allocator: *Allocator) ![]const u8 {
  var newStr = try Buffers.SimpleU8.initSize(allocator, 0);
  var previousStrEndMark: usize = 0;
  const States = enum {Looking, EntityBegin, EntityFound};
  var state = States.Looking;
  var escStart: usize = undefined;
  for (str) |char, idx| {
    if (state == States.Looking and char == '&') {
      state = States.EntityBegin;
      escStart = idx;
    } else if (state == States.EntityBegin) {
      if(char == ';') {
        const snip = str[previousStrEndMark..escStart];
        previousStrEndMark = idx+1;
        try newStr.append(snip);
        const sigil = str[escStart+1..idx];
        var newChar: u8 = undefined;
        if (std.mem.compare(u8, sigil, "amp") == std.mem.Compare.Equal) {
          newChar = '&';
        }
        try newStr.appendByte(newChar);
        state = States.Looking;
      } else if (idx - escStart > 4) {
        state = States.Looking;
      }
    }
  }
  if (previousStrEndMark <= str.len) {
    try newStr.append(str[previousStrEndMark..]);
  }
  warn("html entity {}\n", newStr.toSliceConst());
  return newStr.toSliceConst();
}

test "htmlEntityParse" {
  const allocator = std.debug.global_allocator;
  var stripped = htmlEntityDecode("amp&amp;pam", allocator) catch unreachable;
  std.testing.expect(std.mem.eql(u8, stripped, "amp&pam"));
}

pub fn jsonStrDecode(str: []const u8, allocator: *Allocator) ![]const u8 {
  const States = enum {Looking, EscBegin, uFound, Digit};
  const escMark = struct { position: usize, char: u8};
  var state = States.Looking;
  var escMarks = std.ArrayList(escMark).init(allocator);
  var escStart: usize = undefined;
  for (str) |char, idx| {
    if (state == States.Looking and char == '\\') {
      state = States.EscBegin;
      escStart = idx;
    } else if (state == States.EscBegin) {
      if(char == 'u' or char == 'U') {
        state = States.uFound;
      } else if (char == '"') {
        try escMarks.append(escMark{.position = escStart, .char = '"'});
        state = States.Looking;
      } else if (char == 'n') {
        try escMarks.append(escMark{.position = escStart, .char = '\n'});
        state = States.Looking;
      } else {
        state = States.Looking;
      }
    } else if (state == States.uFound) {
      if(isHexDigit(char)) {
        state = States.Digit;
      } else {
        state = States.Looking;
      }
    } else if (state == States.Digit) {
      if(isHexDigit(char)) {
        state = States.Digit;
        const escLen = idx - escStart;
        if (escLen == 5) { // last byte of the \uXXXX code
          try escMarks.append(escMark{.position = escStart, .char = 'u'});
          state = States.Looking;
        }
      } else {
        state = States.Looking;
      }
    }
  }

  var newStr = try Buffers.SimpleU8.initSize(allocator, 0);
  var previousStrEndMark: usize = 0;
  for(escMarks.toSlice()) |strMark, idx| {
    // copy the segment before the mark
    const snip = str[previousStrEndMark..strMark.position];
    try newStr.append(snip);
    if(strMark.char == 'u') {
      previousStrEndMark = strMark.position+6;

      const digits = str[strMark.position+2..strMark.position+6];
      var decodedChar: u8 = (hexU8(digits[2]) << 4) + (hexU8(digits[3]));
      try newStr.appendByte(decodedChar);
    }
    if(strMark.char == '"') {
      previousStrEndMark = strMark.position+2;
      try newStr.appendByte('"');
    }
    if(strMark.char == 'n') {
      previousStrEndMark = strMark.position+2;
      try newStr.appendByte('\n');
    }
  }
  // copy the segment after the last mark if there is one
  if (previousStrEndMark <= str.len) {
    try newStr.append(str[previousStrEndMark..]);
  }
  return newStr.toSliceConst();
}

pub fn hexU8(char: u8) u8 {
  if(char >= '0' and char <= '9') {
    return char-'0';
  } else if(char >= 'a' and char <= 'f') {
    return char-'a'+10;
  } else if(char >= 'A' and char <= 'F') {
    return char-'A'+10;
  } else {
    return 0; //unreachable-ish
  }
}

pub fn isHexDigit(char: u8) bool {
  return (char >= '0' and char <= '9')
      or (char >= 'a' and char <= 'f')
      or (char >= 'A' and char <= 'F');
}

test "JSON String Decode" {
  var allocator = std.debug.global_allocator;
  var decoded: []const u8 = undefined;
  decoded = jsonStrDecode("\\u0040p \\u003cY", allocator) catch unreachable;
  std.testing.expect(std.mem.eql(u8, decoded, "@p <Y"));

  decoded = jsonStrDecode("a \\\"real\\\" fan.", allocator) catch unreachable;
  std.testing.expect(std.mem.eql(u8, decoded, "a \"real\" fan."));
}

pub fn toJson(allocator: *Allocator, value: var) []const u8 {
  return toJsonStep(value, 0, allocator);
}

pub fn toJsonStep(value: var, oldDepth: u32, allocator: *Allocator) []const u8 {
  var depth = oldDepth;
  var ram: []u8 = allocator.alloc(u8, 4096) catch unreachable;
  var ptr = usize(0);
  const T = comptime @typeOf(value);
  const info = comptime @typeInfo(T);
  warn("toJsonStep value typeId {} typeName {}\n", @typeId(T), @typeName(T));
  warn("typeId {}\n", @typeId(@typeOf(value)));

  if (@typeId(T) == builtin.TypeId.Struct) {
    if(comptime std.meta.trait.hasFn("toSlice")(T)) {
      ptr += ramSetAt(ram, ptr, toJsonStep(value.toSlice(), depth, allocator));
    } else {
      warn("struct {}\n", @typeId(@typeOf(value)));
      depth += 1;
      ptr += structToJson(ram, ptr, depth, value, allocator);
    }
  } else if (@typeId(T) == builtin.TypeId.Optional) {
    if(value) |val| {
      ptr += ramSetAt(ram, ptr, toJsonStep(val, depth, allocator));
    } else {
      ptr += nullToJson(ram, ptr, depth);
    }
    //warn("typeid optional. child {}\n", info.Optional.child);
  } else if (@typeId(T) == builtin.TypeId.Pointer) {
    if(info.Pointer.size == builtin.TypeInfo.Pointer.Size.Slice) {
      if(info.Pointer.child == u8) {
        warn("slice of u8 {}bytes\n", value.len);
        ptr += strToJson(ram, ptr, depth, value);
      } else {
        warn("slice of {} items\n", value.len);
        depth += 1;
        ptr += arrayishToJson(ram, ptr, depth, value, allocator);
      }
    }
    if(info.Pointer.size == builtin.TypeInfo.Pointer.Size.One) {
      ptr += ramSetAt(ram, ptr, toJsonStep(value.*, depth, allocator));
    }
  } else if (@typeId(T) == builtin.TypeId.Array) {
    warn("{}\n", @typeId(T));
    if(info.Array.child == u8) {
      depth += 1;
      ptr += strToJson(ram, ptr, depth, value);
    } else {
      warn("array unknown\n");
      for(value) |item| {
        warn("array item {c}\n", item);
      }
    }
  } else if (@typeId(T) == builtin.TypeId.Int) {
    ptr += intToJson(ram, ptr, depth, value, allocator);
  } else if (@typeId(T) == builtin.TypeId.Bool) {
    ptr += boolToJson(ram, ptr, depth, value, allocator);
  } else {
    warn("JSON TYPE UNKNOWN {} {}\n", @typeId(T), @typeName(T));
  }
  return ram[0..ptr];
}

pub fn boolToJson(ram: []u8, oldPtr: usize, depth: u32, value: bool, allocator: *Allocator) usize {
  var ptr = oldPtr; // params are const
  ptr += ramSetAt(ram, ptr, if(value) "true" else "false");
  return ptr;
}

pub fn intToJson(ram: []u8, oldPtr: usize, depth: u32, value: var, allocator: *Allocator) usize {
  var ptr = oldPtr; // params are const
  const intlen = 20;
  var intbuf = allocator.alloc(u8, intlen) catch unreachable;
  var intstr = std.fmt.bufPrint(intbuf, "{}", value) catch unreachable;
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
  const info = comptime @typeInfo(@typeOf(value));
  ptr += ramSetAt(ram, ptr, "{\n");
  inline for (info.Struct.fields) |*field_info, idx| {
    const name = field_info.name;
    warn("struct field {} name {}\n", idx, name);
    ptr += ramSetAt(ram, ptr, space(depth, allocator));
    ptr += ramSetAt(ram, ptr, "\"" ++ name ++ "\" : ");
    var fieldVal: field_info.field_type = @field(value, name);
    ptr += ramSetAt(ram, ptr, toJsonStep(fieldVal, depth, allocator));
    if(idx < info.Struct.fields.len-1) {
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
  const info = comptime @typeInfo(@typeOf(value));
  ptr += ramSetAt(ram, ptr, "[\n");
  depth += 1;
  for(value) |item, idx| {
    ptr += ramSetAt(ram, ptr, space(depth, allocator));
    ptr += ramSetAt(ram, ptr, toJsonStep(item, depth, allocator));
    if(idx < value.len-1) {
      ptr += ramSetAt(ram, ptr, ",\n");
    }
  }
  ptr += ramSetAt(ram, ptr, "]\n");
  return ptr;
}

pub fn ramSetAt(ram: []u8, ptr: usize, extra: []const u8) usize {
  var newPtr = ptr+extra.len;
  std.mem.copy(u8, ram[ptr..newPtr], extra);
  return extra.len;
}
