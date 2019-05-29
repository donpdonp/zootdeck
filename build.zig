const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
  const exe = b.addExecutable("zootdeck", "src/main.zig");

  exe.linkSystemLibrary("c");

  // gtk3
  exe.addIncludeDir("/usr/include/gtk-3.0");
  exe.addIncludeDir("/usr/include/glib-2.0");
  exe.addIncludeDir("/usr/include/atk-1.0");
  exe.addIncludeDir("/usr/include/pango-1.0");
  exe.addIncludeDir("/usr/include/gdk-pixbuf-2.0");
  exe.addIncludeDir("/usr/include/cairo");
  exe.addIncludeDir("/usr/lib/x86_64-linux-gnu/glib-2.0/include/");

  // opengl
  exe.addIncludeDir("../glfw/include");
  exe.addIncludeDir("../glfw/deps");
  exe.addLibPath("../glfw/build/src");

  // gtk3
  exe.linkSystemLibrary("gdk-3");
  exe.linkSystemLibrary("gtk-3");
  exe.linkSystemLibrary("gobject-2.0");
  exe.linkSystemLibrary("gmodule-2.0");

  // opengl
  //exe.addObjectFile("ext/glad.o"); // build glad.c by hand for now
  exe.linkSystemLibrary("dl");
  exe.linkSystemLibrary("X11");
  exe.linkSystemLibrary("pthread");
  exe.linkSystemLibrary("glfw3");

  // net
  exe.linkSystemLibrary("curl");

  // nng
  exe.addIncludeDir("../nng/include");
  exe.addLibPath("../nng/build");
  exe.linkSystemLibrary("nng");

  // lmdb
  exe.linkSystemLibrary("lmdb");

  exe.setOutputDir(".");
  b.default_step.dependOn(&exe.step);
  //b.verbose_link = true;
  //b.installExecutable(exe);
}
