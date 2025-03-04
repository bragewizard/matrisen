const std = @import("std");
const log = std.log.scoped(.core);
const lua = @import("scripting.zig");
const debug = @import("debug.zig");
const c = @import("../clibs.zig");
const Window = @import("../window.zig");
const PipelineBuilder = @import("pipelines&materials/pipelinebuilder.zig");
const Instance = @import("instance.zig");
const PhysicalDevice = @import("device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig");
const buffer = @import("buffer.zig");
const commands = @import("commands.zig");
const image = @import("image.zig");
const descriptors = @import("descriptors.zig");
const init_mesh_pipeline = @import("pipelines&materials/meshpipeline.zig").init_mesh_pipeline;
const metalrough = @import("pipelines&materials/metallicroughness.zig");
const common = @import("pipelines&materials/common.zig");
const loop = @import("../applications/test.zig").loop;
const data = @import("data.zig");

pub const vkallocationcallbacks: ?*c.VkAllocationCallbacks = null;
const Self = @This();

vkCmdDrawMeshTasksEXT: c.PFN_vkCmdDrawMeshTasksEXT = undefined,
resizerequest: bool = false,
framenumber: u64 = 0,
cpuallocator: std.mem.Allocator = undefined,
gpuallocator: c.VmaAllocator = undefined,
instance: Instance = undefined,
physicaldevice: PhysicalDevice = undefined,
device: Device = undefined,
surface: c.VkSurfaceKHR = undefined,
swapchain: Swapchain = undefined,
framecontext: commands.FrameContexts = .{},
off_framecontext: commands.OffFrameContext = .{},
globaldescriptorallocator: descriptors.Allocator = undefined,
luastate: ?*c.lua_State = undefined,
formats: [3]c.VkFormat = undefined,
extents3d: [1]c.VkExtent3D = undefined,
extents2d: [1]c.VkExtent2D = undefined,
pipelines: [3]c.VkPipeline = undefined,
pipelinelayouts: [3]c.VkPipelineLayout = undefined,
descriptorsetlayouts: [4]c.VkDescriptorSetLayout = undefined,
descriptorsets: [2]c.VkDescriptorSet = undefined,
allocatedimages: [6]image.AllocatedImage = undefined,
imageviews: [3]c.VkImageView = undefined,
samplers: [2]c.VkSampler = undefined,
// TODO covert to a more flat layout for meshes as we did with images and views
allocatedbuffers: [3]buffer.AllocatedBuffer = undefined,
meshassets: std.ArrayList(buffer.MeshAsset) = undefined,
metalrough: metalrough = undefined,

pub fn run(allocator: std.mem.Allocator, window: ?*Window) void {
    var engine = Self{};
    engine.extents2d[0] = .{ .width = 0, .height = 0 };

    engine.cpuallocator = allocator;
    var initallocator = std.heap.ArenaAllocator.init(engine.cpuallocator);
    const initallocatorinstance = initallocator.allocator();

    engine.luastate = c.luaL_newstate();
    defer c.lua_close(engine.luastate);
    lua.register_lua_functions(&engine);
    c.luaL_openlibs(engine.luastate);

    engine.instance = Instance.create(initallocatorinstance);
    defer c.vkDestroyInstance(engine.instance.handle, vkallocationcallbacks);
    defer if (engine.instance.debug_messenger != null) {
        const destroy_fn = engine.instance.get_destroy_debug_utils_messenger_fn().?;
        destroy_fn(engine.instance.handle, engine.instance.debug_messenger, vkallocationcallbacks);
    };

    if (window) |w| {
        w.create_surface(engine.instance.handle, &engine.surface);
        w.get_size(&engine.extents2d[0].width, &engine.extents2d[0].height);
    }
    defer if (window) |_| {
        c.vkDestroySurfaceKHR(engine.instance.handle, engine.surface, vkallocationcallbacks);
    };

    engine.physicaldevice = PhysicalDevice.select(initallocatorinstance, engine.instance.handle, engine.surface);
    engine.device = Device.create(initallocatorinstance, engine.physicaldevice);
    defer c.vkDestroyDevice(engine.device.handle, vkallocationcallbacks);

    engine.swapchain = Swapchain.create(&engine, engine.extents2d[0]);
    defer engine.swapchain.deinit(engine.device.handle, engine.cpuallocator);

    const allocator_ci = std.mem.zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = engine.physicaldevice.handle,
        .device = engine.device.handle,
        .instance = engine.instance.handle,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    });
    debug.check_vk_panic(c.vmaCreateAllocator(&allocator_ci, &engine.gpuallocator));
    defer c.vmaDestroyAllocator(engine.gpuallocator);

    image.create_draw_and_depth_image(&engine);
    defer c.vmaDestroyImage(engine.gpuallocator, engine.allocatedimages[0].image, engine.allocatedimages[0].allocation);
    defer c.vkDestroyImageView(engine.device.handle, engine.imageviews[0], vkallocationcallbacks);
    defer c.vmaDestroyImage(engine.gpuallocator, engine.allocatedimages[1].image, engine.allocatedimages[1].allocation);
    defer c.vkDestroyImageView(engine.device.handle, engine.imageviews[1], vkallocationcallbacks);

    engine.framecontext.init_frames(&engine);
    defer engine.framecontext.deinit(&engine);

    engine.off_framecontext.init(&engine);
    defer engine.off_framecontext.deinit(engine.device.handle);

    descriptors.init_descriptors(&engine);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[0], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[1], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[2], vkallocationcallbacks);
    defer engine.globaldescriptorallocator.deinit(engine.device.handle);

    engine.init_mesh_pipeline();
    defer c.vkDestroyPipeline(engine.device.handle, engine.pipelines[0], vkallocationcallbacks);
    defer c.vkDestroyPipelineLayout(engine.device.handle, engine.pipelinelayouts[0], vkallocationcallbacks);

    engine.metalrough = metalrough.init(engine.cpuallocator);
    defer engine.metalrough.writer.deinit();
    metalrough.build_pipelines(&engine);
    defer c.vkDestroyPipeline(engine.device.handle, engine.pipelines[1], vkallocationcallbacks);
    defer c.vkDestroyPipeline(engine.device.handle, engine.pipelines[2], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[3], vkallocationcallbacks);
    defer c.vkDestroyPipelineLayout(engine.device.handle, engine.pipelinelayouts[1], vkallocationcallbacks);

    engine.meshassets = std.ArrayList(buffer.MeshAsset).init(engine.cpuallocator);
    defer engine.meshassets.deinit();
    defer for (engine.meshassets.items) |mesh| {
        mesh.surfaces.deinit();
    };

    data.init_default(&engine);
    defer c.vmaDestroyBuffer(engine.gpuallocator, engine.allocatedbuffers[0].buffer, engine.allocatedbuffers[0].allocation);
    defer for (engine.meshassets.items) |mesh| {
        c.vmaDestroyBuffer(engine.gpuallocator, mesh.mesh_buffers.vertex_buffer.buffer, mesh.mesh_buffers.vertex_buffer.allocation);
        c.vmaDestroyBuffer(engine.gpuallocator, mesh.mesh_buffers.index_buffer.buffer, mesh.mesh_buffers.index_buffer.allocation);
    };
    defer c.vmaDestroyImage(engine.gpuallocator, engine.allocatedimages[2].image, engine.allocatedimages[2].allocation);
    defer c.vmaDestroyImage(engine.gpuallocator, engine.allocatedimages[3].image, engine.allocatedimages[3].allocation);
    defer c.vmaDestroyImage(engine.gpuallocator, engine.allocatedimages[4].image, engine.allocatedimages[4].allocation);
    defer c.vmaDestroyImage(engine.gpuallocator, engine.allocatedimages[5].image, engine.allocatedimages[5].allocation);
    defer c.vkDestroyImageView(engine.device.handle, engine.imageviews[2], vkallocationcallbacks);
    defer c.vkDestroySampler(engine.device.handle, engine.samplers[0], vkallocationcallbacks);
    defer c.vkDestroySampler(engine.device.handle, engine.samplers[1], vkallocationcallbacks);

    // TODO fix this ugly ahh pointer thing
    const procAddr: c.PFN_vkCmdDrawMeshTasksEXT = @ptrCast(c.vkGetDeviceProcAddr(engine.device.handle, "vkCmdDrawMeshTasksEXT"));
    if (procAddr == null) {
        log.info("noo", .{});
        @panic("");
    }
    engine.vkCmdDrawMeshTasksEXT = procAddr;

    defer debug.check_vk(c.vkDeviceWaitIdle(engine.device.handle)) catch @panic("Failed to wait for device idle");
    initallocator.deinit();
    loop(&engine, window.?);
}
