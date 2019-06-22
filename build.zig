const builtin = @import("builtin");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
  const exe = b.addExecutable("zootdeck", "src/main.zig");

  // Ubuntu-x86_64
  exe.addIncludeDir("/usr/include");
  exe.addIncludeDir("/usr/include/x86_64-linux-gnu");
  exe.addLibPath("/usr/lib");
  exe.addLibPath("/usr/lib/x86_64-linux-gnu");
  exe.setTarget(builtin.Arch.x86_64,
                builtin.Os.linux, //buildin.Os.macosx,
                builtin.Abi.gnu);

  exe.linkSystemLibrary("c");

  // gtk3
  exe.addIncludeDir("/usr/include/gtk-3.0");
  exe.addIncludeDir("/usr/include/glib-2.0");
  exe.addIncludeDir("/usr/include/atk-1.0");
  exe.addIncludeDir("/usr/include/pango-1.0");
  exe.addIncludeDir("/usr/include/gdk-pixbuf-2.0");
  exe.addIncludeDir("/usr/include/cairo");
  exe.addIncludeDir("/usr/lib/x86_64-linux-gnu/glib-2.0/include/");

  // gtk3
  exe.linkSystemLibrary("glib-2.0");
  exe.linkSystemLibrary("gdk-3");
  exe.linkSystemLibrary("gtk-3");
  exe.linkSystemLibrary("gobject-2.0");
  exe.linkSystemLibrary("gmodule-2.0");

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

  exe.setOutputDir(".");
  b.default_step.dependOn(&exe.step);
  //b.verbose_link = true;
  //b.installExecutable(exe);
}
