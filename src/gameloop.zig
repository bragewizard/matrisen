const draw = @import("vulkan/draw.zig").draw;
const std = @import("std");
const c = @import("clibs");
const Core = @import("vulkan/core.zig");
const Window = @import("window.zig");
const log = std.log.scoped(.app);


pub fn loop(engine: *Core, window: *Window) void {

    var timer = std.time.Timer.start() catch @panic("Failed to start timer");
    var delta: u64 = undefined;
    var quit = false;
    var event: c.SDL_Event = undefined;
    var resize_request = false;

    while (!quit) {
        while (c.SDL_PollEvent(&event) == true) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    quit = true;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    // window.handle_key_down(event.key);
                },
                c.SDL_EVENT_WINDOW_RESIZED => {
                    resize_request = true;
                },
                c.SDL_EVENT_KEY_UP => {
                    // window.handle_key_up(event.key);
                },
                else => {},
            }
        }
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
