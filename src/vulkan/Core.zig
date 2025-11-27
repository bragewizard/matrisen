//! Copyright (C) 2025 B.W. brage.wis@gmail.com
//! This file is part of MATRISEN.
//! MATRISEN is free software: you can redistribute it and/or modify it under
//! the terms of the GNU General Public License (GPL3)
//! see the LICENSE file or <https://www.gnu.org/licenses/> for more details

const std = @import("std");
const debug = @import("debug.zig");
const c = @import("../clibs/clibs.zig").libs;
const buffer = @import("buffer.zig");
const image = @import("image.zig");
const instance = @import("instance.zig");
const swapchain = @import("swapchain.zig");
const device = @import("device.zig");

const DescriptorLayoutBuilder = @import("DescriptorLayoutBuilder.zig");
const DescriptorAllocator = @import("DescriptorAllocator.zig");
const DescriptorWriter = @import("DescriptorWriter.zig");
const FrameContext = @import("FrameContext.zig");
const AsyncContext = @import("AsyncContext.zig");
const Window = @import("../Window.zig");
const ImageManager = @import("ImageManager.zig");
const BufferManager = @import("BufferManager.zig");
const PipelineManager = @import("PipelineManager.zig");

const Self = @This();

/// Bookkeeping
pub const multibuffering = 2;
resizerequest: bool = false,
framenumber: u64 = 0,
current_frame: u8 = 0,

/// Memory allocators
cpuallocator: std.mem.Allocator = undefined,
gpuallocator: c.VmaAllocator = undefined,

/// Managers
framecontexts: [multibuffering]FrameContext = .{FrameContext{}} ** multibuffering,
asynccontext: AsyncContext = .{}, // manages sync and command independet of frame
// imagemanager: ImageManager = .{}, // manages image resources linked to app (not screen, except maybe postprocesing)
// buffermanager: BufferManager = .{}, // manages buffer resources
// pipelinemanager: PipelineManager = .{},

/// Vulkan essentials
instance_handle: c.VkInstance = null,
debug_messenger: c.VkDebugUtilsMessengerEXT = null,
vkallocationcallbacks: ?*c.VkAllocationCallbacks = null,
device_handle: c.VkDevice = null,
graphics_queue: c.VkQueue = null,
present_queue: c.VkQueue = null,
compute_queue: c.VkQueue = null,
transfer_queue: c.VkQueue = null,
physical_device_handle: c.VkPhysicalDevice = null,
properties: c.VkPhysicalDeviceProperties = undefined,
graphics_queue_family: u32 = undefined,
present_queue_family: u32 = undefined,
compute_queue_family: u32 = undefined,
transfer_queue_family: u32 = undefined,

/// Layouts
pipelinelayout: c.VkPipelineLayout = undefined,
staticlayout: c.VkDescriptorSetLayout = undefined,
dynamiclayout: c.VkDescriptorSetLayout = undefined,

/// Global static set
static_set: c.VkDescriptorSet = undefined,
globaldescriptorallocator: DescriptorAllocator = .{},

/// Screen resources
surface: c.VkSurfaceKHR = null,
swapchain_handle: c.VkSwapchainKHR = null,
renderattachmentformat: c.VkFormat = c.VK_FORMAT_R16G16B16A16_SFLOAT,
depth_format: c.VkFormat = c.VK_FORMAT_D32_SFLOAT,
drawextent3d: c.VkExtent3D = undefined,
drawextent2d: c.VkExtent2D = undefined,
colorattachment: image.AllocatedImage = undefined,
resolvedattachment: image.AllocatedImage = undefined,
depthstencilattachment: image.AllocatedImage = undefined,
swapchain_format: c.VkFormat = undefined,
swapchain_extent: c.VkExtent2D = .{},
swapchain_images: []c.VkImage = &.{},
swapchain_views: []c.VkImageView = &.{},

pub fn init(allocator: std.mem.Allocator, window: *Window) Self {
    var self: Self = .{};
    self.swapchain_extent = .{ .width = 0, .height = 0 };
    self.cpuallocator = allocator;
    var initallocator = std.heap.ArenaAllocator.init(self.cpuallocator);
    defer initallocator.deinit();
    const initallocatorinstance = initallocator.allocator();
    instance.init(&self, initallocatorinstance);
    window.create_surface(&self);
    window.get_size(&self.swapchain_extent.width, &self.swapchain_extent.height);
    device.select(&self, initallocatorinstance);
    device.initDevice(&self, initallocatorinstance);
    swapchain.init(&self);
    const allocator_ci: c.VmaAllocatorCreateInfo = .{
        .physicalDevice = self.physical_device_handle,
        .device = self.device_handle,
        .instance = self.instance_handle,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };
    debug.check_vk_panic(c.vmaCreateAllocator(&allocator_ci, &self.gpuallocator));
    image.createRenderAttachments(&self);
    for (&self.framecontexts) |*framecontext| {
        framecontext.init(&self);
    }
    self.asynccontext.init(&self);
    // image.createDefaultTextures(&self);
    // initPipelineLayout(&self);
    return self;
}

pub fn deinit(self: *Self) void {
    debug.check_vk(c.vkDeviceWaitIdle(self.device_handle)) catch @panic("Failed to wait for device idle");
    defer c.vkDestroyInstance(self.instance_handle, self.vkallocationcallbacks);
    defer if (self.debug_messenger != null) {
        const destroyFn = instance.getDestroyDebugUtilsMessengerFn(self).?;
        destroyFn(self.instance_handle, self.debug_messenger, self.vkallocationcallbacks);
    };
    defer c.vkDestroySurfaceKHR(self.instance_handle, self.surface, self.vkallocationcallbacks);
    defer c.vkDestroyDevice(self.device_handle, self.vkallocationcallbacks);
    defer c.vmaDestroyAllocator(self.gpuallocator);
    defer swapchain.deinit(self);
    defer image.deinitRenderAttachments(self);
    for (&self.framecontexts) |*frame| {
        defer frame.deinit(self);
    }
    defer self.asynccontext.deinit(self);
}

pub fn switch_frame(self: *Self) void {
    self.current_frame = (self.current_frame + 1) % multibuffering;
}
