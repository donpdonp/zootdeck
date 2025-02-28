const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    // b.installArtifact(lib);

    const gen_ragel = b.addSystemCommand(&.{ "ragel", "-o", "ragel/lang.c", "ragel/lang.c.rl" });

    const exe = b.addExecutable(.{
        .name = "zootdeck",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.addIncludePath(b.path("."));
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/gtk-3.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/glib-2.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/pango-1.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/gdk-pixbuf-2.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/atk-1.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/harfbuzz" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/cairo" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/glib-2.0/include" });
    exe.linkSystemLibrary("gtk-3");
    exe.linkSystemLibrary("gdk-3");
    exe.linkSystemLibrary("curl");
    exe.linkSystemLibrary("lmdb");
    exe.linkSystemLibrary("gumbo");
    exe.addCSourceFile(.{ .file = b.path("ragel/lang.c") });
    exe.step.dependOn(&gen_ragel.step);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const prefix = "src";
    var dir = std.fs.cwd().openDir(prefix, .{ .iterate = true }) catch unreachable;
    scan_dir(b, test_step, prefix, &dir);
}

fn scan_dir(b: *std.Build, test_step: *std.Build.Step, prefix: []const u8, dir: *std.fs.Dir) void {
    var iter = dir.iterate();
    while (iter.next() catch unreachable) |file_entry| {
        const prefix2 = std.fs.path.join(b.allocator, &.{ prefix, file_entry.name }) catch unreachable;
        if (file_entry.kind == .directory) {
            var dir2 = std.fs.cwd().openDir(prefix2, .{ .iterate = true }) catch unreachable;
            scan_dir(b, test_step, prefix2, &dir2);
        }
        if (file_entry.kind == .file) {
            if (std.mem.endsWith(u8, prefix2, ".zig")) {
                const unit_test = b.addTest(.{ .root_source_file = b.path(prefix2) });
                unit_test.linkLibC();
                const run_unit_tests = b.addRunArtifact(unit_test);
                test_step.dependOn(&run_unit_tests.step);
            }
        }
    }
}
