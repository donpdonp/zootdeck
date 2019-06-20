// gui.zig
const std = @import("std");
const warn = std.debug.warn;
const thread = @import("./thread.zig");

const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});

pub fn gui_setup() ?&c.struct_GLFWwindow {
    var ver_cstr = ??c.glfwGetVersionString();
    var initOk = c.glfwInit();
    if (initOk == c.GLFW_TRUE) {
        warn("GUI init {} vulkan{}\n", std.cstr.toSliceConst(ver_cstr), c.glfwVulkanSupported());

        var window = c.glfwCreateWindow(240, 380, c"Window title", @intToPtr(&c.struct_GLFWmonitor, 0), @intToPtr(&c.struct_GLFWwindow, 0));
        if (window != null) {
            c.glfwMakeContextCurrent(window);
            //@compileLog(@sizeOf(c.struct_nk_context));
            //var nk_context: c.nk_context = c.nk_context{};
            //_ = c.nk_init_fixed();
            //var font: c.FT_Face = c.get_font();
            var width: c_int = 0;
            var height: c_int = 0;
            c.glfwGetFramebufferSize(window, &width, &height);
            warn("framebuf w {} h {}\n", width, height);
            //typedef void (*GLFWglproc)(void);
            //GLFWAPI GLFWglproc glfwGetProcAddress(const char* procname)
            var addrfind = c.glfwGetProcAddress; //'extern fn(?&const u8) ?extern fn() void'
            //var tmap = middle(addrfind);
            //typedef void* (* GLADloadproc)(const char *name);
            var procwut = c.GLADloadproc(adapt); //'?extern fn(?&const u8) ?&c_void'
            //GLAPI int gladLoadGLLoader(GLADloadproc);
            _ = c.gladLoadGLLoader(procwut);
            _ = c.glViewport(0, 0, width, height);

            var x11 = c.glfwGetWaylandDisplay(); //glfwGetX11Display();

            return window;
        } else {
            warn("window fail {}\n", window);
        }
    } else {
        warn("init not ok {}\n", initOk);
    }
    return null;
}

pub fn gui_mainloop(window: ?&c.struct_GLFWwindow) bool {
    if (c.glfwWindowShouldClose(window) != 0) {
        return true;
    }
    c.glfwWaitEventsTimeout(1);
    c.glfwSwapBuffers(window);
    return false;
}

pub fn gui_end() void {
    c.glfwTerminate();
}
