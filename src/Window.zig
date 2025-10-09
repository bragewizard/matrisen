const c = @import("clibs.zig").libs;
const std = @import("std");
const vkallocationcallbacks = @import("vulkan/core.zig").vkallocationcallbacks;

const Self = @This();

sdl_window: *c.SDL_Window,
state: State = .{},

pub fn init(width: u32, height: u32) Self {
    check_sdl_bool(c.SDL_Init(c.SDL_INIT_VIDEO));
    const flags = c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_UTILITY;
    const window = c.SDL_CreateWindow("matrisen", @intCast(width), @intCast(height), flags) orelse @panic("Failed to create SDL window");
    check_sdl_bool(c.SDL_ShowWindow(window));
    return .{ .sdl_window = window };
}

pub fn deinit(self: *Self) void {
    c.SDL_DestroyWindow(self.sdl_window);
    c.SDL_Quit();
}

pub fn create_surface(self: *Self, instance: c.VkInstance, surface: *c.VkSurfaceKHR) void {
    check_sdl_bool(c.SDL_Vulkan_CreateSurface(self.sdl_window, instance, vkallocationcallbacks, surface));
}

pub fn get_size(self: *Self, width: *u32, height: *u32) void {
    var w: c_int = undefined;
    var h: c_int = undefined;
    check_sdl_bool(c.SDL_GetWindowSize(self.sdl_window, &w, &h));
    width.* = @intCast(w);
    height.* = @intCast(h);
}

pub const State = packed struct {
    w: bool = false,
    s: bool = false,
    a: bool = false,
    d: bool = false,
    q: bool = false,
    e: bool = false,
    quit: bool = false,
    capture_mouse: bool = false,
    resize_request: bool = false,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
};

pub fn processInput(self: *Self) void {
    var event: c.SDL_Event = undefined;
    self.state.mouse_x = 0;
    self.state.mouse_y = 0;
    while (c.SDL_PollEvent(&event) == true) {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                self.state.quit = true;
            },
            c.SDL_EVENT_KEY_DOWN => {
                switch (event.key.scancode) {
                    c.SDL_SCANCODE_TAB => {
                        self.state.capture_mouse = !self.state.capture_mouse;
                    },
                    c.SDL_SCANCODE_W => self.state.w = true,
                    c.SDL_SCANCODE_S => self.state.s = true,
                    c.SDL_SCANCODE_A => self.state.a = true,
                    c.SDL_SCANCODE_D => self.state.d = true,
                    c.SDL_SCANCODE_Q => self.state.q = true,
                    c.SDL_SCANCODE_E => self.state.e = true,
                    else => {},
                }
            },
            c.SDL_EVENT_KEY_UP => {
                switch (event.key.scancode) {
                    c.SDL_SCANCODE_W => self.state.w = false,
                    c.SDL_SCANCODE_S => self.state.s = false,
                    c.SDL_SCANCODE_A => self.state.a = false,
                    c.SDL_SCANCODE_D => self.state.d = false,
                    c.SDL_SCANCODE_Q => self.state.q = false,
                    c.SDL_SCANCODE_E => self.state.e = false,
                    else => {},
                }
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                self.state.mouse_x = event.motion.xrel;
                self.state.mouse_y = event.motion.yrel;
            },
            c.SDL_EVENT_WINDOW_RESIZED => {
                self.state.resize_request = true;
            },
            else => {},
        }
    }
}

pub fn check_sdl(res: c_int) void {
    if (res != 0) {
        std.log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}

pub fn check_sdl_bool(res: bool) void {
    if (res != true) {
        std.log.err("Detected SDL error: {s}", .{c.SDL_GetError()});
        @panic("SDL error");
    }
}
