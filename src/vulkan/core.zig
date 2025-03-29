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
const linalg = @import("linalg");

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
vertex_buffers: [4]buffer.AllocatedBuffer = undefined,
index_buffers: [1]buffer.AllocatedBuffer = undefined,
vertex_buffer_adresses: [2]c.VkDeviceAddress = undefined,
meshassets: [1]buffer.GeoSurface = undefined,

pub fn init(allocator: std.mem.Allocator, window: *Window) void {
    var self = Self{};
    self.extents2d[0] = .{ .width = 0, .height = 0 };
    self.cpuallocator = allocator;
    var initallocator = std.heap.ArenaAllocator.init(self.cpuallocator);
    const initallocatorinstance = initallocator.allocator();
    self.instance = Instance.create(initallocatorinstance);
    window.create_surface(self.instance.handle, &self.surface);
    window.get_size(&self.extents2d[0].width, &self.extents2d[0].height);
    self.physicaldevice = PhysicalDevice.select(initallocatorinstance, self.instance.handle, self.surface);
    self.device = Device.create(initallocatorinstance, self.physicaldevice);
    self.swapchain = Swapchain.create(&self, self.extents2d[0]);
    const allocator_ci = std.mem.zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = self.physicaldevice.handle,
        .device = self.device.handle,
        .instance = self.instance.handle,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    });
    debug.check_vk_panic(c.vmaCreateAllocator(&allocator_ci, &self.gpuallocator));
    image.create_draw_and_depth_image(&self);
    self.framecontext.init_frames(&self);
    self.asynccontext.init(&self);
    descriptors.init_global(&self);
    meshpipeline.build_pipeline(&self);
    metalrough.build_pipelines(&self);
    self.meshassets = .init(self.cpuallocator);
    data.init_default(&self);
    // TODO fix this ugly ahh pointer thing
    const procAddr: c.PFN_vkCmdDrawMeshTasksEXT = @ptrCast(c.vkGetDeviceProcAddr(self.device.handle, "vkCmdDrawMeshTasksEXT"));
    if (procAddr == null) {
        log.info("noo", .{});
        @panic("");
    }
    self.vkCmdDrawMeshTasksEXT = procAddr;
    initallocator.deinit();
}

pub fn deinit(self: *Self) void {
    debug.check_vk(c.vkDeviceWaitIdle(self.device.handle)) catch @panic("Failed to wait for device idle");
    defer c.vkDestroyInstance(self.instance.handle, vkallocationcallbacks);
    defer if (self.instance.debug_messenger != null) {
        const destroy_fn = self.instance.get_destroy_debug_utils_messenger_fn().?;
        destroy_fn(self.instance.handle, self.instance.debug_messenger, vkallocationcallbacks);
    };
    defer c.vkDestroySurfaceKHR(self.instance.handle, self.surface, vkallocationcallbacks);
    defer c.vkDestroyDevice(self.device.handle, vkallocationcallbacks);
    defer self.swapchain.deinit(self.device.handle, self.cpuallocator);
    defer c.vmaDestroyAllocator(self.gpuallocator);
    defer c.vmaDestroyImage(self.gpuallocator, self.allocatedimages[0].image, self.allocatedimages[0].allocation);
    defer c.vkDestroyImageView(self.device.handle, self.imageviews[0], vkallocationcallbacks);
    defer c.vmaDestroyImage(self.gpuallocator, self.allocatedimages[1].image, self.allocatedimages[1].allocation);
    defer c.vkDestroyImageView(self.device.handle, self.imageviews[1], vkallocationcallbacks);
    defer self.framecontext.deinit(&self);
    defer self.asynccontext.deinit(self.device.handle);
    defer c.vkDestroyDescriptorSetLayout(self.device.handle, self.descriptorsetlayouts[0], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(self.device.handle, self.descriptorsetlayouts[1], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(self.device.handle, self.descriptorsetlayouts[2], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(self.device.handle, self.descriptorsetlayouts[4], vkallocationcallbacks);
    defer self.globaldescriptorallocator.deinit(self.device.handle);
    defer c.vkDestroyPipeline(self.device.handle, self.pipelines[0], vkallocationcallbacks);
    defer c.vkDestroyPipelineLayout(self.device.handle, self.pipelinelayouts[0], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(self.device.handle, self.descriptorsetlayouts[5], vkallocationcallbacks);
    defer c.vkDestroyPipeline(self.device.handle, self.pipelines[1], vkallocationcallbacks);
    defer c.vkDestroyPipeline(self.device.handle, self.pipelines[2], vkallocationcallbacks);
    defer c.vkDestroyDescriptorSetLayout(self.device.handle, self.descriptorsetlayouts[3], vkallocationcallbacks);
    defer c.vkDestroyPipelineLayout(self.device.handle, self.pipelinelayouts[1], vkallocationcallbacks);
    defer self.meshassets.deinit();
    defer for (self.meshassets.items) |mesh| {
        mesh.surfaces.deinit();
    };
    defer c.vmaDestroyBuffer(self.gpuallocator, self.allocatedbuffers[0].buffer, self.allocatedbuffers[0].allocation);
    // defer c.vmaDestroyBuffer(self.gpuallocator, self.allocatedbuffers[1].buffer, self.allocatedbuffers[1].allocation);
    defer for (self.meshassets.items) |mesh| {
        c.vmaDestroyBuffer(self.gpuallocator, mesh.mesh_buffers.vertex_buffer.buffer, mesh.mesh_buffers.vertex_buffer.allocation);
        c.vmaDestroyBuffer(self.gpuallocator, mesh.mesh_buffers.index_buffer.buffer, mesh.mesh_buffers.index_buffer.allocation);
    };
    defer c.vmaDestroyImage(self.gpuallocator, self.allocatedimages[2].image, self.allocatedimages[2].allocation);
    defer c.vmaDestroyImage(self.gpuallocator, self.allocatedimages[3].image, self.allocatedimages[3].allocation);
    defer c.vmaDestroyImage(self.gpuallocator, self.allocatedimages[4].image, self.allocatedimages[4].allocation);
    defer c.vmaDestroyImage(self.gpuallocator, self.allocatedimages[5].image, self.allocatedimages[5].allocation);
    defer c.vkDestroyImageView(self.device.handle, self.imageviews[2], vkallocationcallbacks);
    defer c.vkDestroySampler(self.device.handle, self.samplers[0], vkallocationcallbacks);
    defer c.vkDestroySampler(self.device.handle, self.samplers[1], vkallocationcallbacks);
}

