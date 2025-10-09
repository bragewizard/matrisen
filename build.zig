const std = @import("std");
const Build = std.Build;
const builtin = @import("builtin");

pub fn build(b: *Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = b.addOptions();
    const version_opt = b.option(
        []const u8,
        "version",
        "overrides the version reported",
    ) orelse v: {
        var code: u8 = undefined;
        const git_describe = b.runAllowFail(&[_][]const u8{
            "git", "describe", "--tags",
        }, &code, .Ignore) catch {
            break :v "<unk>";
        };
        break :v std.mem.trim(u8, git_describe, " \n\r");
    };
    options.addOption([]const u8, "version", version_opt);

    const matrisen = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "matrisen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
            .imports = &.{
                .{ .name = "matrisen", .module = matrisen },
            },
        }),
    });

    exe.root_module.addOptions("config", options);
    exe.linkLibCpp();
    exe.linkLibC();
    exe.linkSystemLibrary("SDL3");
    exe.linkSystemLibrary("vulkan");
    exe.addCSourceFile(.{ .file = b.path("src/vk_mem_alloc.cpp"), .flags = &.{""} });
    // TODO: replace with zigimg or my own
    exe.addCSourceFile(.{ .file = b.path("src/stb_image.c"), .flags = &.{""} });

    compile_all_shaders(b, exe);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn compile_all_shaders(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const shaders_dir = if (@hasDecl(@TypeOf(b.build_root.handle), "openIterableDir"))
        b.build_root.handle.openIterableDir("src/vulkan/pipelines", .{}) catch @panic("Failed to open shaders directory")
    else
        b.build_root.handle.openDir(
            "src/vulkan/pipelines",
            .{ .iterate = true },
        ) catch @panic("Failed to open shaders directory");

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
    const source = std.fmt.allocPrint(b.allocator, "src/vulkan/pipelines/{s}", .{name}) catch @panic("OOM");
    const outpath = std.fmt.allocPrint(b.allocator, "src/vulkan/pipelines/{s}.spv", .{name}) catch @panic("OOM");
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
