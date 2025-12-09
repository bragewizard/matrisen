const std = @import("std");
const log = std.log.scoped(.build);
const Build = std.Build;
const builtin = @import("builtin");

const shaderpath = "src/vulkan/shaders/GLSL";
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
        .name = "exe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example/main.zig"),
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
    exe.addCSourceFile(.{ .file = b.path("src/clibs/vk_mem_alloc.cpp"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/clibs/stb_image.c"), .flags = &.{""} });

    const shaders_step = b.step("shaders", "Compile all shaders");
    compileAllShaders(b, matrisen, shaders_step);

    b.installArtifact(exe);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn compileAllShaders(b: *std.Build, mod: *std.Build.Module, shaders_step: *std.Build.Step) void {
    const shaders_dir = if (@hasDecl(@TypeOf(b.build_root.handle), "openIterableDir"))
        b.build_root.handle.openIterableDir(shaderpath, .{}) catch {
            @panic("Failed to open shaders directory");
        }
    else
        b.build_root.handle.openDir(shaderpath, .{ .iterate = true }) catch {
            @panic("Failed to open shaders directory");
        };
    var file_it = shaders_dir.iterate();
    while (file_it.next() catch @panic("failed to iterate")) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.name);
            if (ext.len > 0) {
                const basename = std.fs.path.basename(entry.name);
                log.info("found shader: {s}", .{basename});
                addShader(b, mod, shaders_step, basename);
            }
        }
    }
}

fn addShader(b: *std.Build, mod: *std.Build.Module, shaders_step: *std.Build.Step, filename: []const u8) void {
    const name_stem = std.fs.path.stem(filename);
    const shader_src = b.path(b.fmt(shaderpath ++ "/{s}", .{filename}));

    const cmd = b.addSystemCommand(&.{"glslangValidator"});
    cmd.addArg("-V"); // Output SPIR-V
    cmd.addArg("--target-env");
    cmd.addArg("vulkan1.4");
    cmd.addFileArg(shader_src);
    cmd.addArg("-o");

    const spv_output = cmd.addOutputFileArg(b.fmt("{s}.spv", .{name_stem}));
    shaders_step.dependOn(&cmd.step);
    const gen = b.addWriteFiles();
    _ = gen.addCopyFile(spv_output, "shader.spv");
    const wrapper_path = gen.add("shader.zig",
        \\const std = @import("std");
        \\const content align(4) = @embedFile("shader.spv").*;
        \\pub const bytes = content;
        \\pub const code_u8 = std.mem.bytesAsSlice(u8, &content);
    );
    const shader = b.createModule(.{ .root_source_file = wrapper_path });
    mod.addImport(filename, shader);
}
