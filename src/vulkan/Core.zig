//! Copyright (C) 2025 B.W. brage.wis@gmail.com
//! This file is part of MATRISEN.
//! MATRISEN is free software: you can redistribute it and/or modify it under
//! the terms of the GNU General Public License (GPL3)
//! see the LICENSE file or <https://www.gnu.org/licenses/> for more details

const std = @import("std");
const debug = @import("debug.zig");
const c = @import("../clibs/clibs.zig").libs;

const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const Swapchain = @import("Swapchain.zig");
const DescriptorLayoutBuilder = @import("DescriptorLayoutBuilder.zig");
const Instance = @import("Instance.zig");
const DescriptorAllocator = @import("DescriptorAllocator.zig");
const DescriptorWriter = @import("DescriptorWriter.zig");
const FrameContext = @import("FrameContext.zig");
const AsyncContext = @import("AsyncContext.zig");
const Window = @import("../Window.zig");
const ImageAllocator = @import("ImageAllocator.zig");
const ImageManager = @import("ImageManager.zig");
const BufferAllocator = @import("BufferAllocator.zig");
const BufferManager = @import("BufferManager.zig");
const PipelineManager = @import("PipelineManager.zig");

const Self = @This();

/// Bookkeeping
pub const multibuffering = 2;
const renderformat: c.VkFormat = c.VK_FORMAT_R16G16B16A16_SFLOAT;
const depthformat: c.VkFormat = c.VK_FORMAT_D32_SFLOAT;

resizerequest: bool = false,
framenumber: u64 = 0,
current_frame: u8 = 0,

/// Memory allocators
cpuallocator: std.mem.Allocator,
gpuallocator: c.VmaAllocator,

/// Managers
framecontexts: [multibuffering]FrameContext,
asynccontext: AsyncContext, // manages sync and command independet of frame
// imagemanager: ImageManager = .{}, // manages image resources linked to app (not screen, except maybe postprocesing)
// buffermanager: BufferManager = .{}, // manages buffer resources
// pipelinemanager: PipelineManager = .{},

/// Vulkan essentials
instance: Instance,
device: Device,
physicaldevice: PhysicalDevice,
allocationcallbacks: ?*c.VkAllocationCallbacks,

/// Layouts
// pipelinelayout: c.VkPipelineLayout,
// staticlayout: c.VkDescriptorSetLayout,
// dynamiclayout: c.VkDescriptorSetLayout,
imageallocator: ImageAllocator,
// bufferallocator: BufferAllocator,
/// Global static set
// staticset: c.VkDescriptorSet,
// globaldescriptorallocator: DescriptorAllocator,

/// Screen resources
surface: c.VkSurfaceKHR,
swapchain: Swapchain,
swapchainextent: c.VkExtent2D,
drawextent3d: c.VkExtent3D, // for resolution scaling
drawextent2d: c.VkExtent2D, //for resolution scaling
drawimage: ImageAllocator.AllocatedImage = undefined,
renderimage: ImageAllocator.AllocatedImage = undefined,
depthimage: ImageAllocator.AllocatedImage = undefined,

pub fn init(allocator: std.mem.Allocator, window: *Window) Self {
    var arenaallocator = std.heap.ArenaAllocator.init(allocator);
    defer arenaallocator.deinit();
    const initallocator = arenaallocator.allocator();

    const instance: Instance = .init(initallocator);
    const allocationcallbacks: ?*c.VkAllocationCallbacks = null;
    const surface = window.createSurface(instance, allocationcallbacks);
    const physicaldevice: PhysicalDevice = .select(initallocator, instance.handle, surface);
    const device: Device = .init(initallocator, physicaldevice);
    const gpuallocator = makeGpuAllocator(physicaldevice.handle, device.handle, instance.handle);

    var swapchainextent: c.VkExtent2D = .{ .width = 0, .height = 0 };
    window.getSize(&swapchainextent.width, &swapchainextent.height);
    const drawextent: c.VkExtent2D = .{ .width = swapchainextent.width, .height = swapchainextent.height };
    const depthextent: c.VkExtent3D = .{ .width = swapchainextent.width, .height = swapchainextent.height, .depth = 1 };
    const swapchain: Swapchain = .init(
        allocator,
        physicaldevice,
        device.handle,
        surface,
        swapchainextent,
        allocationcallbacks,
    );
    var imageallocator: ImageAllocator = .init(device.handle, gpuallocator, allocationcallbacks);
    const drawimage = imageallocator.createDrawImage(drawextent, renderformat);
    const renderimage = imageallocator.createRenderImage(drawextent, renderformat);
    const depthimage = imageallocator.createDepthImage(depthextent, depthformat);
    var framecontexts: [multibuffering]FrameContext = @splat(.{});
    for (&framecontexts) |*framecontext| framecontext.init(device, physicaldevice, allocationcallbacks);
    const asynccontext: AsyncContext = .init(device, physicaldevice, allocationcallbacks);

    // const bufferallocator: BufferAllocator = .init();

    return .{
        .cpuallocator = allocator,
        .gpuallocator = gpuallocator,
        .allocationcallbacks = allocationcallbacks,
        .asynccontext = asynccontext,
        .framecontexts = framecontexts,
        .surface = surface,
        .swapchain = swapchain,
        .instance = instance,
        .device = device,
        .physicaldevice = physicaldevice,
        .drawimage = drawimage,
        .renderimage = renderimage,
        .drawextent2d = drawextent,
        .drawextent3d = depthextent,
        .swapchainextent = swapchainextent,
        .depthimage = depthimage,
        .imageallocator = imageallocator,
        // .bufferallocator = bufferallocator,
    };
}

pub fn deinit(self: *Self) void {
    debug.checkVkPanic(c.vkDeviceWaitIdle(self.device.handle));
    defer self.instance.deinit();
    defer c.vkDestroySurfaceKHR(self.instance.handle, self.surface, self.allocationcallbacks);
    defer c.vkDestroyDevice(self.device.handle, self.allocationcallbacks);
    defer c.vmaDestroyAllocator(self.gpuallocator);
    defer self.swapchain.deinit(self.cpuallocator, self.device.handle, self.allocationcallbacks);
    defer self.imageallocator.deinitImage(self.drawimage);
    defer self.imageallocator.deinitImage(self.renderimage);
    defer self.imageallocator.deinitImage(self.depthimage);
    defer for (&self.framecontexts) |*frame| frame.deinit(self.device, self.allocationcallbacks);
    defer self.asynccontext.deinit(self.device, self.allocationcallbacks);
}

pub fn switch_frame(self: *Self) void {
    self.current_frame = (self.current_frame + 1) % multibuffering;
}

fn makeGpuAllocator(
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    instance: c.VkInstance,
) c.VmaAllocator {
    var gpuallocator: c.VmaAllocator = undefined;
    const allocator_ci: c.VmaAllocatorCreateInfo = .{
        .physicalDevice = physical_device,
        .device = device,
        .instance = instance,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };
    debug.checkVkPanic(c.vmaCreateAllocator(&allocator_ci, &gpuallocator));
    return gpuallocator;
}

pub fn resize(self: *Self, window: *Window) void {
    debug.checkVkPanic(c.vkDeviceWaitIdle(self.device.handle));
    self.swapchain.deinit(self.cpuallocator, self.device.handle, self.allocationcallbacks);
    self.imageallocator.deinitImage(self.drawimage);
    self.imageallocator.deinitImage(self.renderimage);
    self.imageallocator.deinitImage(self.depthimage);
    window.getSize(&self.swapchainextent.width, &self.swapchainextent.height);
    var drawextent: c.VkExtent2D = .{};
    const render_scale = 1;
    drawextent.width = @intFromFloat(@as(f32, @floatFromInt(@min(
        self.swapchainextent.width,
        self.swapchainextent.width,
    ))) * render_scale);
    drawextent.height = @intFromFloat(@as(f32, @floatFromInt(@min(
        self.swapchainextent.height,
        self.swapchainextent.height,
    ))) * render_scale);
    self.drawextent2d = drawextent;
    self.drawextent3d = .{ .width = drawextent.width, .height = drawextent.height, .depth = 1 };
    self.drawimage = self.imageallocator.createDrawImage(self.drawextent2d, renderformat);
    self.renderimage = self.imageallocator.createRenderImage(self.drawextent2d, renderformat);
    self.depthimage = self.imageallocator.createDepthImage(self.drawextent3d, depthformat);
}
