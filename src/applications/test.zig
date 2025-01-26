







var timer = std.time.Timer.start() catch @panic("Failed to start timer");
var delta: u64 = undefined;
var quit = false;
var event: c.SDL_Event = undefined;

while (!quit) {
    while (c.SDL_PollEvent(&event) == true) {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                quit = true;
            },
            c.SDL_EVENT_KEY_DOWN => {
                win.handle_key_down(self, event.key);
                if (event.key.key == c.SDLK_R) {
                    self.pc = if (self.white) blk: {
                        self.white = false;
                        break :blk background_color_dark;
                    } else blk: {
                        self.white = true;
                        break :blk background_color_light;
                    };
                }
            },
            c.SDL_EVENT_WINDOW_RESIZED => {
                self.resize_request = true;
            },
            c.SDL_EVENT_KEY_UP => {
                s.handle_key_up(self, event.key);
            },
            else => {},
        }
    }
    if (self.frame_number % 100 == 0) {
        delta = timer.read();
        log.info("FPS: {d}", .{@as(u32, (@intFromFloat(100_000_000_000.0 / @as(f32, @floatFromInt(delta)))))});
        timer.reset();
    }
    if (self.resize_request) {
        self.resize_swapchain();
    }
    engine.draw();
}
