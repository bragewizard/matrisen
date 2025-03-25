//! Copyright (C) 2025 B.W. bragewiseth@icloud.com
//! This file is part of MATRISEN.
//! MATRISEN is free software: you can redistribute it and/or modify it under
//! the terms of the GNU General Public License (GPL3)
//! see the LICENSE file or <https://www.gnu.org/licenses/> for more details

const std = @import("std");
const log = std.log.scoped(.core);
const debug = @import("debug.zig");
const c = @import("clibs");
const Window = @import("../window.zig");
const PipelineBuilder = @import("pipelines/pipelinebuilder.zig");
const Instance = @import("instance.zig");
const PhysicalDevice = @import("device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig");
const buffer = @import("buffer.zig");
const commands = @import("commands.zig");
const image = @import("image.zig");
const descriptors = @import("descriptor.zig");
const meshpipeline = @import("pipelines/meshpipeline.zig");
const metalrough = @import("pipelines/metallicroughness.zig");
const common = @import("pipelines/common.zig");
const loop = @import("../gameloop.zig").loop;
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
asynccontext: commands.AsyncContext = .{},
globaldescriptorallocator: descriptors.Allocator = undefined,
formats: [3]c.VkFormat = undefined,
extents3d: [1]c.VkExtent3D = undefined,
extents2d: [1]c.VkExtent2D = undefined,
pipelines: [3]c.VkPipeline = undefined,
pipelinelayouts: [3]c.VkPipelineLayout = undefined,
descriptorsetlayouts: [6]c.VkDescriptorSetLayout = undefined,
descriptorsets: [3]c.VkDescriptorSet = undefined,
allocatedimages: [6]image.AllocatedImage = undefined,
imageviews: [3]c.VkImageView = undefined,
samplers: [2]c.VkSampler = undefined,
allocatedbuffers: [4]buffer.AllocatedBuffer = undefined,
// TODO covert to a more flat layout for meshes as we did with images and views
meshassets: std.ArrayList(buffer.MeshAsset) = undefined,

pub fn run(allocator: std.mem.Allocator, window: *Window) void {
    var engine = Self{};
    engine.extents2d[0] = .{ .width = 0, .height = 0 };

    engine.cpuallocator = allocator;
    var initallocator = std.heap.ArenaAllocator.init(engine.cpuallocator);
    const initallocatorinstance = initallocator.allocator();

    engine.instance = Instance.create(initallocatorinstance);
    defer c.vkDestroyInstance(engine.instance.handle, vkallocationcallbacks);
    defer if (engine.instance.debug_messenger != null) {
        const destroy_fn = engine.instance.get_destroy_debug_utils_messenger_fn().?;
        destroy_fn(engine.instance.handle, engine.instance.debug_messenger, vkallocationcallbacks);
    };

    window.create_surface(engine.instance.handle, &engine.surface);
    window.get_size(&engine.extents2d[0].width, &engine.extents2d[0].height);
    defer c.vkDestroySurfaceKHR(engine.instance.handle, engine.surface, vkallocationcallbacks);

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

    engine.asynccontext.init(&engine);
    defer engine.asynccontext.deinit(engine.device.handle);

    descriptors.init_global(&engine);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[0], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[1], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[2], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[4], vkallocationcallbacks);
    defer engine.globaldescriptorallocator.deinit(engine.device.handle);

    meshpipeline.build_pipeline(&engine);
    defer c.vkDestroyPipeline(engine.device.handle, engine.pipelines[0], vkallocationcallbacks);
    defer c.vkDestroyPipelineLayout(engine.device.handle, engine.pipelinelayouts[0], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[5], vkallocationcallbacks);

    metalrough.build_pipelines(&engine);
    defer c.vkDestroyPipeline(engine.device.handle, engine.pipelines[1], vkallocationcallbacks);
    defer c.vkDestroyPipeline(engine.device.handle, engine.pipelines[2], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(engine.device.handle, engine.descriptorsetlayouts[3], vkallocationcallbacks);
    defer c.vkDestroyPipelineLayout(engine.device.handle, engine.pipelinelayouts[1], vkallocationcallbacks);

    engine.meshassets = .init(engine.cpuallocator);
    defer engine.meshassets.deinit();
    defer for (engine.meshassets.items) |mesh| {
        mesh.surfaces.deinit();
    };

    data.init_default(&engine);
    defer c.vmaDestroyBuffer(engine.gpuallocator, engine.allocatedbuffers[0].buffer, engine.allocatedbuffers[0].allocation);
    // defer c.vmaDestroyBuffer(engine.gpuallocator, engine.allocatedbuffers[1].buffer, engine.allocatedbuffers[1].allocation);
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
    loop(&engine, window);
}
