const std = @import("std");
const log = std.log.scoped(.core);
const lua = @import("scripting.zig");
const check_vk = @import("debug.zig").check_vk;
const check_vk_panic = @import("debug.zig").check_vk_panic;
const c = @import("../clibs.zig");
const Window = @import("../window.zig");
const PipelineBuilder = @import("pipelines&materials/pipelinebuilder.zig");
const Instance = @import("instance.zig");
const PhysicalDevice = @import("device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig");
const FrameContext = @import("framecontext.zig");
const OffFrameContext = @import("off-framecontext.zig");
const descriptors = @import("descriptors.zig");
const init_mesh_pipeline = @import("pipelines&materials/meshpipeline.zig").init_mesh_pipeline;
const loop = @import("../applications/test.zig").loop;

pub const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;
const Self = @This();

vkCmdDrawMeshTasksEXT : c.PFN_vkCmdDrawMeshTasksEXT = undefined,
resize_request: bool = false,
frame_number: u64 = 0,
cpu_allocator: std.mem.Allocator = undefined,
gpu_allocator: c.VmaAllocator = undefined,
instance: Instance = undefined,
physical_device: PhysicalDevice = undefined,
device: Device = undefined,
surface: c.VkSurfaceKHR = undefined,
swapchain: Swapchain = undefined,
framecontext: FrameContext = undefined,
off_framecontext : OffFrameContext = .{},
pipelines: [1]c.VkPipeline = undefined,
pipeline_layouts: [1]c.VkPipelineLayout = undefined,
descriptorset_layouts: [1]c.VkDescriptorSetLayout = undefined,
descriptorsets: [1]c.VkDescriptorSet = undefined,
global_descriptor_allocator: descriptors.Allocator = undefined,
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

    engine.framecontext.init_frames(engine.physical_device, engine.device);
    defer engine.framecontext.deinit(engine.device);

    engine.off_framecontext.init(&engine);
    defer engine.off_framecontext.deinit(engine.device);

    engine.init_mesh_pipeline();
    defer c.vkDestroyPipeline(engine.device.handle, engine.pipelines[0], vk_alloc_cbs);
    defer c.vkDestroyPipelineLayout(engine.device.handle, engine.pipeline_layouts[0], vk_alloc_cbs);

    // descriptors.init_descriptors(&engine);


    // TODO fix this ugly ahh pointer thing
    const procAddr : c.PFN_vkCmdDrawMeshTasksEXT = @ptrCast(c.vkGetDeviceProcAddr(engine.device.handle, "vkCmdDrawMeshTasksEXT"));
    if (procAddr == null) {
        log.info("noo",.{});
        @panic("");
    }
    engine.vkCmdDrawMeshTasksEXT = procAddr;

    defer check_vk(c.vkDeviceWaitIdle(engine.device.handle)) catch @panic("Failed to wait for device idle");
    init_allocator.deinit();
    loop(&engine, window.?);
}
