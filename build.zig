const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    var env_map = try std.process.getEnvMap(b.allocator);
    defer env_map.deinit();

    const cimgui = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = target,
        .optimize = optimize,
    });
    cimgui.addCSourceFiles(.{
        .files = &.{
            "thirdparty/cimgui/cimgui.cpp",
            "thirdparty/cimgui/imgui/imgui.cpp",
            "thirdparty/cimgui/imgui/imgui_demo.cpp",
            "thirdparty/cimgui/imgui/imgui_draw.cpp",
            "thirdparty/cimgui/imgui/imgui_tables.cpp",
            "thirdparty/cimgui/imgui/imgui_widgets.cpp",
            "thirdparty/cimgui/imgui/backends/imgui_impl_sdl2.cpp",
            "thirdparty/cimgui/imgui/backends/imgui_impl_vulkan.cpp",
        },
        .flags = &.{},
    });
    cimgui.addIncludePath(b.path("thirdparty/cimgui"));
    cimgui.addIncludePath(b.path("thirdparty/cimgui/imgui"));
    cimgui.addIncludePath(b.path("thirdparty/cimgui/imgui/backends"));
    cimgui.addIncludePath(.{ .cwd_relative = env_map.get("X11_INCLUDE_PATH").? });
    cimgui.addIncludePath(.{ .cwd_relative = env_map.get("XORGPROTO_INCLUDE_PATH").? });
    const cimgui_sdl2_path = try std.fs.path.join(b.allocator, &.{ env_map.get("SDL2_INCLUDE_PATH").?, "SDL2" });
    cimgui.addIncludePath(.{ .cwd_relative = cimgui_sdl2_path });
    cimgui.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });
    cimgui.linkLibCpp();

    const exe = b.addExecutable(.{
        .name = "vulkanguide-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(b.path("thirdparty/cimgui"));
    exe.addIncludePath(b.path("thirdparty/cimgui/imgui"));
    exe.addIncludePath(b.path("thirdparty/cimgui/imgui/backends"));
    exe.addIncludePath(b.path("thirdparty/cimgui_generated"));
    exe.addIncludePath(.{ .cwd_relative = env_map.get("SDL2_INCLUDE_PATH").? });
    exe.addIncludePath(.{ .cwd_relative = env_map.get("VULKAN_INCLUDE_PATH").? });

    exe.addIncludePath(b.path("thirdparty/vma"));
    exe.addCSourceFile(.{ .file = b.path("thirdparty/vma/vk_mem_alloc.cpp"), .flags = &.{} });

    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("vulkan");
    exe.linkLibrary(cimgui);
    exe.linkLibCpp();

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

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
