// gl.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const thread = @import("../thread.zig");
const config = @import("../config.zig");

const GUIError = error{Init, Setup};

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
  return "gl";
}

pub fn init(alloca: *Allocator, set: *config.Settings) !void {
  var tf = usize(1);
  if(tf != 1) return GUIError.Init;
}

pub fn gui_setup(actor: *thread.Actor) !void {
  var ver_cstr = c.glfwGetVersionString();
  var initOk = c.glfwInit();
  if (initOk == c.GLFW_TRUE) {
    warn("GUI init {} vulkan{}\n", std.cstr.toSliceConst(ver_cstr), c.glfwVulkanSupported());

    var windowMaybe = c.glfwCreateWindow(240, 380, c"Window title", null, null);
    if (windowMaybe) |window| {
      c.glfwMakeContextCurrent(window);
      //@compileLog(@sizeOf(c.struct_nk_context));
      //var nk_context: c.nk_context = c.nk_context{};
      //_ = c.nk_init_fixed();
      //var font: c.FT_Face = c.get_font();
      var width: c_int = 0;
      var height: c_int = 0;
      c.glfwGetFramebufferSize(window, &width, &height);
      warn("framebuf w {} h {}\n", width, height);
      // //typedef void (*GLFWglproc)(void);
      // //GLFWAPI GLFWglproc glfwGetProcAddress(const char* procname)
      // var addrfind = c.glfwGetProcAddress; //'extern fn(?&const u8) ?extern fn() void'
      // //var tmap = middle(addrfind);
      // //typedef void* (* GLADloadproc)(const char *name);
      // var procwut = c.GLADloadproc(adapt); //'?extern fn(?&const u8) ?&c_void'
      // //GLAPI int gladLoadGLLoader(GLADloadproc);
      // _ = c.gladLoadGLLoader(procwut);
      // _ = c.glViewport(0, 0, width, height);

      // var x11 = c.glfwGetWaylandDisplay(); //glfwGetX11Display();

      mainWindow = window;
    } else {
      warn("window init fail\n");
      return GUIError.Setup;
    }
  } else {
    warn("init not ok {}\n", initOk);
    return GUIError.Setup;
  }
}

pub fn mainloop() void {
  _ = c.glfwWindowShouldClose(mainWindow);
  c.glfwWaitEventsTimeout(1);
  c.glfwSwapBuffers(mainWindow);
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

