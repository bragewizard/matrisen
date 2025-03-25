const draw = @import("vulkan/draw.zig").draw;
const std = @import("std");
const c = @import("clibs");
const Core = @import("vulkan/core.zig");
const Window = @import("window.zig");
const log = std.log.scoped(.app);

pub fn loop(engine: *Core, window: *Window) void {
    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var delta: u64 = undefined;

    Window.check_sdl_bool(c.SDL_SetWindowRelativeMouseMode(window.sdl_window, true));

    while (!window.state.quit) {
        window.processInput();
        if (window.state.w) engine.camera.translateForward(-0.1);
        if (window.state.s) engine.camera.translateForward(0.1);
        if (window.state.a) engine.camera.translatePitch(0.1);
        if (window.state.d) engine.camera.translatePitch(-0.1);
        if (window.state.q) engine.camera.translateWorldZ(-0.1);
        if (window.state.e) engine.camera.translateWorldZ(0.1);
        engine.camera.rotatePitch(-window.state.mouse_y/100);
        engine.camera.rotateWorldZ(window.state.mouse_x/100);
        if (engine.framenumber % 100 == 0) {
            delta = timer.read();
            log.info("FPS: {d}            \x1b[1A", .{@as(u32, (@intFromFloat(100_000_000_000.0 / @as(f32, @floatFromInt(delta)))))});
            timer.reset();
        }
        if (engine.resizerequest) {
            window.get_size(&engine.extents2d[0].width, &engine.extents2d[0].height);
            engine.swapchain.resize(engine, engine.extents2d[0]);
        }
        draw(engine);
    }
}
// .d => self.camera.transform.translatePitch(-0.2),
// .a => self.camera.transform.translatePitch(0.2),
// .q => self.camera.transform.translateWorldZ(-0.2),
// .e => self.camera.transform.translateWorldZ(0.2),
// .w => self.camera.transform.translateRoll(0.2),
// .s => self.camera.transform.translateRoll(-0.2),
// .j => self.camera.transform.rotateWorldZ(-0.1),
// .l => self.camera.transform.rotateWorldZ(0.1),
// .i => self.camera.transform.rotatePitch(-0.1),
// .k => self.camera.transform.rotatePitch(0.1),
// .o => self.camera.transform.rotateRoll(-0.1),
// .u => self.camera.transform.rotateRoll(0.1),
// .zero => self.camera.transform = algreba.Transform(f32).origin(),
