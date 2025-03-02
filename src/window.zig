const c = @import("clibs.zig");
const std = @import("std");
const vkallocationcallbacks = @import("vulkan/core.zig").vkallocationcallbacks;

const Self = @This();

sdl_window: *c.SDL_Window,
extent: c.VkExtent2D,

pub fn init(window_extent: c.VkExtent2D) Self {
    check_sdl_bool(c.SDL_Init(c.SDL_INIT_VIDEO));
    const flags = c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_UTILITY;
    const window = c.SDL_CreateWindow("matrisen", @intCast(window_extent.width), @intCast(window_extent.height), flags) orelse @panic("Failed to create SDL window");
    check_sdl_bool(c.SDL_ShowWindow(window));
    return .{ .sdl_window = window, .extent = window_extent };
}

pub fn deinit(self: *Self) void {
    c.SDL_DestroyWindow(self.sdl_window);
    c.SDL_Quit();
}

pub fn create_surface(self: *Self, instance: c.VkInstance, surface: *c.VkSurfaceKHR) void {
    check_sdl_bool(c.SDL_Vulkan_CreateSurface(self.sdl_window, instance, vkallocationcallbacks, surface));
}

pub fn resize(self: *Self) void {
    var width: c_int = undefined;
    var height: c_int = undefined;
    check_sdl_bool(c.SDL_GetWindowSize(self.sdl_window, &width, &height));
    self.extent.width = @intCast(width);
    self.extent.height = @intCast(height);
}

// pub fn handle_key_up(engine:*e, key_event: c.SDL_KeyboardEvent) void {
//     switch (key_event.key) {
//         c.SDLK_UP => {
//             engine.pc.data1.x += 0.1;
//         },
//         c.SDLK_DOWN => {
//             engine.pc.data1.x -= 0.1;
//         },
//         else => {}
//     }
// }

// pub fn handle_key_down(engine:*e, key_event: c.SDL_KeyboardEvent) void {
//     switch (key_event.key) {
//         c.SDLK_UP => {
//             engine.pc.data1.w += 0.0;
//         },
//         else => {}
//     }
// }

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
