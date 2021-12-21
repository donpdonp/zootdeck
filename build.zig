const std = @import("std");
const builtin = @import("builtin");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable("zootdeck", "src/main.zig");
    exe.setTarget(target);
    exe.addIncludeDir(".");
    exe.addCSourceFile("ragel/lang.c", &[_][]const u8{"-std=c99"});

    // Ubuntu-x86_64
    exe.addIncludeDir("/usr/include");
    //exe.addIncludeDir("/usr/include/linux");
    exe.addIncludeDir("/usr/include/x86_64-linux-gnu");
    exe.addLibPath("/usr/lib");
    exe.addLibPath("/usr/lib/x86_64-linux-gnu");

    exe.linkSystemLibrary("c");

    // gtk3
    exe.linkSystemLibrary("glib-2.0");
    exe.linkSystemLibrary("gdk-3.0");
    exe.linkSystemLibrary("gdk_pixbuf-2.0");
    exe.linkSystemLibrary("gtk-3");
    exe.linkSystemLibrary("gobject-2.0");
    exe.linkSystemLibrary("gmodule-2.0");
    exe.linkSystemLibrary("pango-1.0");
    exe.linkSystemLibrary("atk-1.0");

    // html
    exe.linkSystemLibrary("gumbo");

    // qt5
    exe.addIncludeDir("/usr/include/x86_64-linux-gnu/qt5");

    // libui (local)
    // exe.addIncludeDir("../libui");
    // exe.linkSystemLibrary("ui");
    // exe.addLibPath("../libui/build/out");

    // glfw (local)
    exe.addIncludeDir("../glfw/include");
    exe.addIncludeDir("../glfw/deps");
    exe.addIncludeDir("../nanovg/src");
    exe.linkSystemLibrary("glfw3");
    exe.addLibPath("../glfw/build/src");

    // opengl
    //exe.addObjectFile("ext/glad.o"); // build glad.c by hand for now
    exe.linkSystemLibrary("dl");
    exe.linkSystemLibrary("X11");
    exe.linkSystemLibrary("pthread");

    // net
    exe.linkSystemLibrary("curl");

    // lmdb
    exe.linkSystemLibrary("lmdb");

    exe.install();
}
