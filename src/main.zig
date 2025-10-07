const std = @import("std");
const vulkanbackend = @import("vulkan/core.zig");
const app = @import("gameloop.zig");
const Window = @import("window.zig");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    var window: Window = .init(2000, 1200);
    defer window.deinit();
    var engine: vulkanbackend = .init(allocator, &window);
    defer engine.deinit();
    app.loop(&engine, &window);
}
