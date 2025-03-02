const std = @import("std");
const graphics = @import("vulkan/core.zig");
const c = @import("clibs.zig");
const Window = @import("window.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const window_extent = c.VkExtent2D{ .width = 1200, .height = 1000 };
    var window : Window = Window.init(window_extent);
    defer window.deinit();
    graphics.run(allocator, &window);
}
