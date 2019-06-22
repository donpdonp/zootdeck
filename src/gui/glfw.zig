// glfw.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const thread = @import("../thread.zig");
const config = @import("../config.zig");

const GUIError = error{Init, Setup};
var vg : [*c]c.NVGcontext = undefined;

const c = @cImport({
  @cInclude("glad/glad.h");
  @cInclude("GLFW/glfw3.h");
  @cInclude("GLFW/glfw3native.h");
});

pub const Column = struct {
//  columnbox: [*c]c.uiControl,
//  config_window: [*c]c.GtkWidget,
  main: *config.ColumnInfo
};

var myActor: *thread.Actor = undefined;
var mainWindow: *c.struct_GLFWwindow = undefined;

pub fn libname() []const u8 {
  return "glfw";
}

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  var tf = usize(1);
  if(tf != 1) return GUIError.Init;
}

pub fn gui_setup(actor: *thread.Actor) !void {
  var ver_cstr = c.glfwGetVersionString();
  warn("GLFW init {} {}\n", std.cstr.toSliceConst(ver_cstr),
                           if(c.glfwVulkanSupported() == 1) "vulkan" else "");

  if (c.glfwInit() == c.GLFW_TRUE) {
    var title = c"Zootdeck";
    if (c.glfwCreateWindow(640, 380, title, null, null)) |window| {
      c.glfwMakeContextCurrent(window);
      mainWindow = window;

      var width: c_int = 0;
      var height: c_int = 0;
      c.glfwGetFramebufferSize(window, &width, &height);
      warn("framebuf w {} h {}\n", width, height);

    } else {
      warn("GLFW create window fail\n");
      return GUIError.Setup;
    }
  } else {
    warn("GLFW init not ok\n");
    return GUIError.Setup;
  }
}

pub fn mainloop() void {
  while(c.glfwWindowShouldClose(mainWindow) == 0) {
    c.glfwWaitEventsTimeout(1);
    c.glfwSwapBuffers(mainWindow);
  }
}

pub fn gui_end() void {
  c.glfwTerminate();
}

pub fn schedule(funcMaybe: ?extern fn(*c_void) c_int, param: *c_void) void {
  if(funcMaybe) |func| {
    warn("schedule FUNC {}\n", func);
    _ = func(@ptrCast(*c_void, &c"w"));
  }
}

pub extern fn show_main_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn add_column_schedule(in: *c_void) c_int {
  warn("gl add column\n");
  return 0;
}

pub extern fn column_remove_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn column_config_oauth_url_schedule(in: *c_void) c_int {
  return 0;
}


pub extern fn update_column_config_oauth_finalize_schedule(in: *c_void) c_int {
  return 0;
}


pub extern fn update_column_ui_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn update_column_netstatus_schedule(in: *c_void) c_int {
  return 0;
}

pub extern fn update_column_toots_schedule(in: *c_void) c_int {
  return 0;
}

