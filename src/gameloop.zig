const draw = @import("vulkan/draw.zig").draw;
const std = @import("std");
const c = @import("clibs");
const Core = @import("vulkan/core.zig");
const Window = @import("window.zig");
const log = std.log.scoped(.app);
const linalg = @import("linalg");
const Quat = linalg.Quat(f32);
const Vec3 = linalg.Vec3(f32);

rotations: [3]Quat = undefined,
positions: [3]Vec3 = undefined,

const Self = @This();

pub fn loop(self: Self, engine: *Core, window: *Window) void {
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var delta: u64 = undefined;

    const camera = 0;
    const susanne = 1;
    self.position[camera] = .{ .x = 0, .y = -10, .z = 8 };
    self.position[susanne] = .{ .x = 0, .y = -10, .z = 8 };
    engine.camera.rotatePitch(std.math.degreesToRadians(60));
    engine.camera.rotateYaw(std.math.degreesToRadians(180));
    engine.camera.rotateRoll(std.math.degreesToRadians(180));

    Window.check_sdl_bool(c.SDL_SetWindowRelativeMouseMode(window.sdl_window, true));

    while (!window.state.quit) {
        window.processInput();
        if (window.state.w) engine.camera.translateForward(0.1);
        if (window.state.s) engine.camera.translateForward(-0.1);
        if (window.state.a) engine.camera.translatePitch(-0.1);
        if (window.state.d) engine.camera.translatePitch(0.1);
        if (window.state.q) engine.camera.translateWorldZ(0.1);
        if (window.state.e) engine.camera.translateWorldZ(-0.1);
        engine.camera.rotatePitch(-window.state.mouse_y / 150);
        engine.camera.rotateWorldZ(-window.state.mouse_x / 150);
        if (engine.framenumber % 100 == 0) {
            delta = timer.read();
            log.info("FPS: {d}                        \x1b[1A", .{
                @as(u32, (@intFromFloat(100_000_000_000.0 / @as(f32, @floatFromInt(delta))))),
            });
            timer.reset();
        }
        if (engine.resizerequest) {
            window.get_size(&engine.extents2d[0].width, &engine.extents2d[0].height);
            engine.swapchain.resize(engine, engine.extents2d[0]);
        }
        draw(engine);
    }
}
