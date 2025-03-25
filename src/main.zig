const std = @import("std");
const graphics = @import("vulkan/core.zig");
const c = @import("clibs");
const Window = @import("window.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var window : Window = .init(1200,1000);
    defer window.deinit();
    graphics.run(allocator, &window);
}
