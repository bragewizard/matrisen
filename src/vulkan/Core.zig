//! Copyright (C) 2025 B.W. brage.wis@gmail.com
//! This file is part of MATRISEN.
//! MATRISEN is free software: you can redistribute it and/or modify it under
//! the terms of the GNU General Public License (GPL3)
//! see the LICENSE file or <https://www.gnu.org/licenses/> for more details

const std = @import("std");
const debug = @import("debug.zig");
const c = @import("../clibs.zig").libs;
const commands = @import("command.zig");
const buffer = @import("buffer.zig");
const geometry = @import("linalg");
const descriptor = @import("descriptor.zig");
const image = @import("image.zig");
const Mat4x4 = geometry.Mat4x4(f32);
const ResourceEntry = buffer.ResourceEntry;
const Allocator = descriptor.Allocator;
const FrameContexts = commands.FrameContexts(multibuffering);
const AsyncContext = commands.AsyncContext;
const Window = @import("../window.zig");
const Instance = @import("instance.zig");
const PhysicalDevice = @import("device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig");

pub const vkallocationcallbacks: ?*c.VkAllocationCallbacks = null;
pub const multibuffering = 2;

const Self = @This();

resizerequest: bool = false,
framenumber: u64 = 0,
cpuallocator: std.mem.Allocator = undefined,
gpuallocator: c.VmaAllocator = undefined,
surface: c.VkSurfaceKHR = null,
instance: Instance = .{},
physicaldevice: PhysicalDevice = .{},
device: Device = .{},
swapchain: Swapchain = .{},
framecontexts: FrameContexts = .{},
asynccontext: AsyncContext = .{},
pipelines: Pipelines = .{},
globaldescriptorallocator: descriptor.Allocator = .{},
textures: [6]image.AllocatedImage(1) = undefined,
depths: [1]image.AllocatedImage(1) = undefined,
extent3d: [1]c.VkExtent3D = undefined,
extent2d: [1]c.VkExtent2D = undefined,
samplers: [2]c.VkSampler = undefined,
renderattachmentformat: c.VkFormat = c.VK_FORMAT_R16G16B16A16_SFLOAT,
depth_format: c.VkFormat = c.VK_FORMAT_D32_SFLOAT,
colorattachment: image.AllocatedImage(1) = undefined,
resolvedattachment: image.AllocatedImage(1) = undefined,
depthstencilattachment: image.AllocatedImage(1) = undefined,
swapchain_format: c.VkFormat = undefined,
swapchain_extent: c.VkExtent2D = .{},
swapchain_image: []c.VkImage = &.{},
swapchain_views: []c.VkImageView = &.{},

pub fn init(allocator: std.mem.Allocator, window: *Window) Self {
    var self: Self = .{};
    self.swapchain_extent = .{ .width = 0, .height = 0 };
    self.cpuallocator = allocator;
    var initallocator = std.heap.ArenaAllocator.init(self.cpuallocator);
    const initallocatorinstance = initallocator.allocator();
    Instance.init(&self, initallocatorinstance);
    window.create_surface(self.instance.handle, &self.surface);
    window.get_size(&self.swapchain_extent.width, &self.swapchain_extent.height);
    PhysicalDevice.select(&self, initallocatorinstance);
    Device.init(&self, initallocatorinstance);
    Swapchain.init(&self);
    const allocator_ci: c.VmaAllocatorCreateInfo = .{
        .physicalDevice = self.physicaldevice.handle,
        .device = self.device.handle,
        .instance = self.instance.handle,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };
    debug.check_vk_panic(c.vmaCreateAllocator(&allocator_ci, &self.gpuallocator));
    image.createRenderAttachments(&self);
    FrameContexts.init(&self);
    AsyncContext.init(&self);
    image.createDefaultTextures(&self);
    Pipelines.init(&self);
    initallocator.deinit();
    return self;
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
    defer c.vmaDestroyAllocator(self.gpuallocator);
    defer Swapchain.deinit(self);
    defer FrameContexts.deinit(self);
    defer AsyncContext.deinit(self);
    defer Pipelines.deinit(self);
}

const Pipelines = struct {
    vertexshader: @import("pipelines/vertexshader.zig") = .{},

    pub fn init(core: *Self) void {
        inline for (std.meta.fields(Pipelines)) |field| {
            @field(core.pipelines, field.name).init(core);
        }
    }

    pub fn deinit(core: *Self) void {
        inline for (std.meta.fields(Pipelines)) |field| {
            @field(core.pipelines, field.name).deinit(core);
        }
    }
};
