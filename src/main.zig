const std = @import("std");
const vulkanbackend = @import("vulkan/core.zig");
const loop = @import("gameloop.zig");
const Window = @import("window.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var window : Window = .init(1200,1000);
    defer window.deinit();
    var engine : vulkanbackend = .init(allocator, &window);
    defer engine.deinit();
    loop.loop(&engine, &window);
}
