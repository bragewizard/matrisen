const std = @import("std");
const log = std.log.scoped(.build);
const Build = std.Build;
const builtin = @import("builtin");

// pub fn build(b: *Build) !void {
//     const optimize = b.standardOptimizeOption(.{});
//     const target = b.standardTargetOptions(.{});

//     const options = b.addOptions();
//     const version_opt = b.option(
//         []const u8,
//         "version",
//         "overrides the version reported",
//     ) orelse v: {
//         var code: u8 = undefined;
//         const git_describe = b.runAllowFail(&[_][]const u8{
//             "git", "describe", "--tags",
//         }, &code, .Ignore) catch {
//             break :v "<unk>";
//         };
//         break :v std.mem.trim(u8, git_describe, " \n\r");
//     };
//     options.addOption([]const u8, "version", version_opt);

//     const matrisen = b.createModule(.{
//         .target = target,
//         .optimize = optimize,
//         .root_source_file = b.path("src/root.zig"),
//     });

//     const exe = b.addExecutable(.{
//         .name = "exe",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("src/example/main.zig"),
//             .optimize = optimize,
//             .target = target,
//             .imports = &.{
//                 .{ .name = "matrisen", .module = matrisen },
//             },
//         }),
//     });

//     exe.root_module.addOptions("config", options);
//     exe.linkLibCpp();
//     exe.linkLibC();
//     exe.linkSystemLibrary("SDL3");
//     exe.linkSystemLibrary("vulkan");
//     exe.addCSourceFile(.{ .file = b.path("src/clibs/vk_mem_alloc.cpp"), .flags = &.{""} });
//     exe.addCSourceFile(.{ .file = b.path("src/clibs/stb_image.c"), .flags = &.{""} });

//     compileAllShaders(b, exe);
//     b.installArtifact(exe);

//     const run_cmd = b.addRunArtifact(exe);
//     run_cmd.step.dependOn(b.getInstallStep());

//     if (b.args) |args| {
//         run_cmd.addArgs(args);
//     }
//     const run_step = b.step("run", "Run the app");
//     run_step.dependOn(&run_cmd.step);
// }

// fn compileAllShaders(b: *std.Build, exe: *std.Build.Step.Compile) void {
//     const shaders_dir = if (@hasDecl(@TypeOf(b.build_root.handle), "openIterableDir"))
//         b.build_root.handle.openIterableDir("src/vulkan/pipelines", .{}) catch {
//             @panic("Failed to open shaders directory");
//         }
//     else
//         b.build_root.handle.openDir(
//             "src/vulkan/pipelines",
//             .{ .iterate = true },
//         ) catch @panic("Failed to open shaders directory");

//     var file_it = shaders_dir.iterate();
//     while (file_it.next() catch @panic("failed to iterate shader directory")) |entry| {
//         if (entry.kind == .file) {
//             var numperiod: u8 = 0;
//             for (entry.name) |char| {
//                 if (char == '.') {
//                     numperiod += 1;
//                 }
//             }
//             if (numperiod > 1) {
//                 const basename = std.fs.path.basename(entry.name);
//                 log.info("found shader to compile: {s}", .{basename});
//                 addShader(b, exe, basename);
//             }
//         }
//     }
// }

// fn addShader(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8) void {
//     const source = std.fmt.allocPrint(b.allocator, "src/vulkan/pipelines/{s}", .{name}) catch @panic("OOM");
//     const outpath = std.fmt.allocPrint(
//         b.allocator,
//         "src/vulkan/pipelines/{s}.spv",
//         .{std.fs.path.stem(name)},
//     ) catch @panic("OOM");
//     const shader_compilation = b.addSystemCommand(&.{"glslangValidator"});
//     shader_compilation.addArg("--target-env");
//     shader_compilation.addArg("vulkan1.3");
//     shader_compilation.addArg("--target-env");
//     shader_compilation.addArg("spirv1.6");
//     shader_compilation.addArg("-V");
//     shader_compilation.addArg("-o");
//     const output = shader_compilation.addOutputFileArg(outpath);
//     shader_compilation.addFileArg(b.path(source));
//     const base = std.fmt.allocPrint(b.allocator, "{s}/", .{b.build_root.path.?}) catch @panic("OOM");
//     const end = std.fmt.allocPrint(b.allocator, "{s}\n", .{source}) catch @panic("OOM");
//     const parts = [_][]const u8{ base, end };
//     const result = std.mem.concat(b.allocator, u8, &parts) catch unreachable;
//     shader_compilation.expectStdOutEqual(result);
//     exe.root_module.addAnonymousImport(name, .{ .root_source_file = output });
// }

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
