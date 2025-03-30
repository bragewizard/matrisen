const std = @import("std");
const c = @import("clibs");
const Core = @import("vulkan/core.zig");
const Swapchain = @import("vulkan/swapchain.zig");
const setSceneData = @import("vulkan/pipelines/root.zig").setSceneData;
const Window = @import("window.zig");
const commands = @import("vulkan/commands.zig");
const log = std.log.scoped(.app);
const geometry = @import("geometry");
const Quat = geometry.Quat(f32);
const Vec3 = geometry.Vec3(f32);

const Self = @This();

pub fn loop(engine: *Core, window: *Window) void {
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var delta: u64 = undefined;

    var camerarot: Quat = .identity;
    var camerapos: Vec3 = .{ .x = 0, .y = -5, .z = 8 };
    camerarot.rotatePitch(std.math.degreesToRadians(60));
    camerarot.rotateYaw(std.math.degreesToRadians(180));
    camerarot.rotateRoll(std.math.degreesToRadians(180));

    Window.check_sdl_bool(c.SDL_SetWindowRelativeMouseMode(window.sdl_window, true));

    while (!window.state.quit) {
        window.processInput();
        if (window.state.w) camerapos.translateForward(&camerarot, 0.1);
        if (window.state.s) camerapos.translateForward(&camerarot, -0.1);
        if (window.state.a) camerapos.translatePitch(&camerarot, -0.1);
        if (window.state.d) camerapos.translatePitch(&camerarot, 0.1);
        if (window.state.q) camerapos.translateWorldZ(0.1);
        if (window.state.e) camerapos.translateWorldZ(-0.1);
        camerarot.rotatePitch(-window.state.mouse_y / 150);
        camerarot.rotateWorldZ(-window.state.mouse_x / 150);
        if (engine.framenumber % 100 == 0) {
            delta = timer.read();
            log.info("FPS: {d}                        \x1b[1A", .{
                @as(u32, (@intFromFloat(100_000_000_000.0 / @as(f32, @floatFromInt(delta))))),
            });
            timer.reset();
        }
        if (engine.resizerequest) {
            window.get_size(&engine.images.swapchain_extent.width, &engine.images.swapchain_extent.height);
            Swapchain.resize(engine);
        }
        var frame = &engine.framecontexts.frames[engine.framecontexts.current];
        frame.submitBegin(engine);
        setSceneData(engine, frame, camerarot.view(camerapos));
        engine.pipelines.pbr.draw(engine, frame);
        engine.pipelines.meshshader.draw(engine, frame);
        frame.submitEnd(engine);
    }
}
