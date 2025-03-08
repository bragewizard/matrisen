const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const override_colors = b.option(bool, "override-colors", "Override vertex colors") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "override_colors", override_colors);

    const exe = b.addExecutable(.{
        .name = "matrisen",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addOptions("config", options);
    exe.linkLibCpp();
    exe.linkLibC();

    exe.linkSystemLibrary("SDL3");
    exe.linkSystemLibrary("lua5.4");
    exe.linkSystemLibrary("vulkan");

    exe.addCSourceFile(.{ .file = b.path("src/vk_mem_alloc.cpp"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/stb_image.c"), .flags = &.{""} });
    compile_all_shaders(b, exe);

    // artifacts
    // default
    b.installArtifact(exe);

    // run
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // test
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn compile_all_shaders(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const shaders_dir = if (@hasDecl(@TypeOf(b.build_root.handle), "openIterableDir"))
        b.build_root.handle.openIterableDir("src/shaders", .{}) catch @panic("Failed to open shaders directory")
    else
        b.build_root.handle.openDir("src/shaders", .{ .iterate = true }) catch @panic("Failed to open shaders directory");

    var file_it = shaders_dir.iterate();
    while (file_it.next() catch @panic("failed to iterate shader directory")) |entry| {
        if (entry.kind == .file) {
            var numperiod: u8 = 0;
            for (entry.name) |char| {
                if (char == '.') {
                    numperiod += 1;
                }
            }
            if (numperiod > 1) {
                const basename = std.fs.path.basename(entry.name);
                std.debug.print("found shader to compile: {s}\n", .{basename});
                add_shader(b, exe, basename);
            }
        }
    }
}

fn add_shader(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8) void {
    const source = std.fmt.allocPrint(b.allocator, "src/shaders/{s}", .{name}) catch @panic("OOM");
    const outpath = std.fmt.allocPrint(b.allocator, "src/shaders/{s}.spv", .{name}) catch @panic("OOM");
    const shader_compilation = b.addSystemCommand(&.{"glslangValidator"});
    shader_compilation.addArg("--target-env");
    shader_compilation.addArg("vulkan1.3");
    shader_compilation.addArg("--target-env");
    shader_compilation.addArg("spirv1.5");
    shader_compilation.addArg("-V");
    shader_compilation.addArg("-o");
    const output = shader_compilation.addOutputFileArg(outpath);
    shader_compilation.addFileArg(b.path(source));
    const base = std.fmt.allocPrint(b.allocator, "{s}/", .{b.build_root.path.?}) catch @panic("OOM");
    const end = std.fmt.allocPrint(b.allocator, "{s}\n", .{source}) catch @panic("OOM");
    const parts = [_][]const u8{ base, end };
    const result = std.mem.concat(b.allocator, u8, &parts) catch unreachable;
    shader_compilation.expectStdOutEqual(result);
    exe.root_module.addAnonymousImport(name, .{ .root_source_file = output });
}
