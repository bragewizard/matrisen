const std = @import("std");
const log = std.log.scoped(.core);
const lua = @import("scripting.zig");
const check_vk = @import("debug.zig").check_vk;
const check_vk_panic = @import("debug.zig").check_vk_panic;
const c = @import("../clibs.zig");
const Window = @import("../window.zig");
const PipelineBuilder = @import("pipelines/pipelinebuilder.zig");
const Instance = @import("instance.zig");
const PhysicalDevice = @import("device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig").Swapchain;
const Framebuffer = @import("framebuffer.zig");
const loop = @import("../applications/test.zig").loop;

pub const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;
const Self = @This();

resize_request: bool = false,
frame_number: u64 = 0,
cpu_allocator: std.mem.Allocator = undefined,
gpu_allocator: c.VmaAllocator = undefined,
instance: Instance = undefined,
physical_device: PhysicalDevice = undefined,
device: Device = undefined,
surface: c.VkSurfaceKHR = undefined,
swapchain: Swapchain = undefined,
framebuffer: Framebuffer = undefined,
lua_state: ?*c.lua_State = undefined,

pub fn run(allocator: std.mem.Allocator, window: ?*Window) void {
    var engine = Self{};

    engine.cpu_allocator = allocator;
    var init_allocator = std.heap.ArenaAllocator.init(engine.cpu_allocator);

    engine.lua_state = c.luaL_newstate();
    defer c.lua_close(engine.lua_state);
    lua.register_lua_functions(&engine);
    c.luaL_openlibs(engine.lua_state);

    engine.instance = Instance.create(init_allocator.allocator());
    defer c.vkDestroyInstance(engine.instance.handle, vk_alloc_cbs);
    defer if (engine.instance.debug_messenger != null) {
        const destroy_fn = engine.instance.get_destroy_debug_utils_messenger_fn().?;
        destroy_fn(engine.instance.handle, engine.instance.debug_messenger, vk_alloc_cbs);
    };

    if (window) |w| { w.create_surface(engine.instance.handle, &engine.surface); }
    defer if (window) |_| { c.vkDestroySurfaceKHR(engine.instance.handle, engine.surface, vk_alloc_cbs); };

    engine.physical_device = PhysicalDevice.select(init_allocator.allocator(), engine.instance.handle, engine.surface);
    engine.device = Device.create(init_allocator.allocator(), engine.physical_device);
    defer c.vkDestroyDevice(engine.device.handle, vk_alloc_cbs);

    engine.swapchain = Swapchain.create(engine, window.?.extent);
    defer engine.swapchain.deinit(engine.device.handle, engine.cpu_allocator);

    const allocator_ci = std.mem.zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = engine.physical_device.handle,
        .device = engine.device.handle,
        .instance = engine.instance.handle,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    });
    check_vk_panic(c.vmaCreateAllocator(&allocator_ci, &engine.gpu_allocator));
    defer c.vmaDestroyAllocator(engine.gpu_allocator);

    engine.framebuffer.init_frames(engine.physical_device, engine.device);
    defer engine.framebuffer.deinit(engine.device);

    // engine.init_descriptors();
    // engine.init_pipelines();
    // engine.init_default_data();

    // c.vkDestroyDescriptorSetLayout(self.device, self.draw_image_descriptor_layout, vk_alloc_cbs);
    // c.vkDestroyDescriptorSetLayout(self.device, self.gpu_scene_data_descriptor_layout, vk_alloc_cbs);
    // c.vkDestroyDescriptorSetLayout(self.device, self.single_image_descriptor_layout, vk_alloc_cbs);
    // self.global_descriptor_allocator.deinit(self.device);
    // for (&self.frames) |*frame| {
    //     frame.frame_descriptors.deinit(self.device);
    // }

    defer check_vk(c.vkDeviceWaitIdle(engine.device.handle)) catch @panic("Failed to wait for device idle");
    init_allocator.deinit();
    loop(&engine, window.?);
}
