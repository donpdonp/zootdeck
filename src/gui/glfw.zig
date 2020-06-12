// glfw.zig
const std = @import("std");
const builtin = @import("builtin");
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

const thread = @import("../thread.zig");
const config = @import("../config.zig");

const GUIError = error{ Init, Setup };
var vg: [*c]c.NVGcontext = undefined;

const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("GLFW/glfw3.h");
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
    if (tf != 1) return GUIError.Init;
}

pub fn gui_setup(actor: *thread.Actor) !void {
    var ver_cstr = c.glfwGetVersionString();
    warn("GLFW init {} {}\n", std.cstr.toSliceConst(ver_cstr), if (c.glfwVulkanSupported() == c.GLFW_TRUE) "vulkan" else "novulkan");

    _ = c.glfwSetErrorCallback(glfw_error);
    if (c.glfwInit() == c.GLFW_TRUE) {
        var title = "Zootdeck";
        if (c.glfwCreateWindow(640, 380, title, null, null)) |window| {
            c.glfwMakeContextCurrent(window);
            mainWindow = window;
            vulkanInit(window);
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

pub fn vulkanInit(window: *c.struct_GLFWwindow) void {
    var count: c_int = -1;
    warn("GLFS EXT GO\n");
    var extensions = c.glfwGetRequiredInstanceExtensions(@ptrCast([*c]u32, &count));
    if (count == 0) {
        var errcode = c.glfwGetError(null);
        if (errcode == c.GLFW_NOT_INITIALIZED) {
            warn("vulkan ERR! GLFW NOT INITIALIZED {}\n", errcode);
        }
        if (errcode == c.GLFW_PLATFORM_ERROR) {
            warn("vulkan ERR! GLFW PLATFORM ERROR {}\n", errcode);
        }
        var description: [*c]const u8 = undefined;
        _ = c.glfwGetError(&description);
        warn("*_ err {}\n", description);
    } else {
        warn("PRE EXT count {}\n", count);
        warn("vulkan extensions {}\n", extensions);
        warn("POST EXT\n");
    }
}

fn glfw_error(code: c_int, description: [*c]const u8) callconv(.C) void {
    warn("**GLFW ErrorBack! {}\n", description);
}

pub fn mainloop() void {
    while (c.glfwWindowShouldClose(mainWindow) == 0) {
        c.glfwWaitEventsTimeout(1);
        c.glfwSwapBuffers(mainWindow);
    }
}

pub fn gui_end() void {
    c.glfwTerminate();
}

pub fn schedule(funcMaybe: ?fn (*c_void) callconv(.C) c_int, param: *c_void) void {
    if (funcMaybe) |func| {
        warn("schedule FUNC {}\n", func);
        _ = func(@ptrCast(*c_void, &"w"));
    }
}

pub fn show_main_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn add_column_schedule(in: *c_void) callconv(.C) c_int {
    warn("gl add column\n");
    return 0;
}

pub fn column_remove_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn column_config_oauth_url_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn update_column_config_oauth_finalize_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn update_column_ui_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn update_column_netstatus_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}

pub fn update_column_toots_schedule(in: *c_void) callconv(.C) c_int {
    return 0;
}
