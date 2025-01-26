const c = @import("../clibs.zig");
const std = @import("std");
const check_vk = @import("debug.zig").check_vk;
const create_image_view = @import("image.zig").create_image_view;

// const gpu = @import("core").physical_device;

pub const SwapchainSupportInfo = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    formats: []c.VkSurfaceFormatKHR = &.{},
    present_modes: []c.VkPresentModeKHR = &.{},

    pub fn init(a: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) !SwapchainSupportInfo {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        try check_vk(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities));

        var format_count: u32 = undefined;
        try check_vk(c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, null));
        const formats = try a.alloc(c.VkSurfaceFormatKHR, format_count);
        try check_vk(c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, formats.ptr));

        var present_mode_count: u32 = undefined;
        try check_vk(c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, null));
        const present_modes = try a.alloc(c.VkPresentModeKHR, present_mode_count);
        try check_vk(c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_mode_count, present_modes.ptr));

        return .{
            .capabilities = capabilities,
            .formats = formats,
            .present_modes = present_modes,
        };
    }

    pub fn deinit(self: *const SwapchainSupportInfo, a: std.mem.Allocator) void {
        a.free(self.formats);
        a.free(self.present_modes);
    }
};

pub const SwapchainCreateOpts = struct {
    physical_device: c.VkPhysicalDevice,
    graphics_queue_family: u32,
    present_queue_family: u32,
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    old_swapchain: c.VkSwapchainKHR = null,
    format: c.VkSurfaceFormatKHR = undefined,
    vsync: bool = false,
    triple_buffer: bool = false,
    window_width: u32 = 0,
    window_height: u32 = 0,
    alloc_cb: ?*c.VkAllocationCallbacks = null,
};

pub const Swapchain = struct {
    handle: c.VkSwapchainKHR = null,
    images: []c.VkImage = &.{},
    image_views: []c.VkImageView = &.{},
    format: c.VkFormat = undefined,
    extent: c.VkExtent2D = undefined,

    pub fn create(a: std.mem.Allocator, opts: SwapchainCreateOpts) !Swapchain {
        const support_info = try SwapchainSupportInfo.init(a, opts.physical_device, opts.surface);
        defer support_info.deinit(a);

        const format = pick_format(support_info.formats, opts);
        const present_mode = pick_present_mode(support_info.present_modes, opts);
        // log.info("Selected swapchain format: {d}, present mode: {d}", .{ format, present_mode });
        const extent = make_extent(support_info.capabilities, opts);

        const image_count = blk: {
            const desired_count = support_info.capabilities.minImageCount + 1;
            if (support_info.capabilities.maxImageCount > 0) {
                break :blk @min(desired_count, support_info.capabilities.maxImageCount);
            }
            break :blk desired_count;
        };

        var swapchain_info = std.mem.zeroInit(c.VkSwapchainCreateInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = opts.surface,
            .minImageCount = image_count,
            .imageFormat = format,
            .imageColorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
            .preTransform = support_info.capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = present_mode,
            .clipped = c.VK_TRUE,
            .oldSwapchain = opts.old_swapchain,
        });

        if (opts.graphics_queue_family != opts.present_queue_family) {
            const queue_family_indices: []const u32 = &.{
                opts.graphics_queue_family,
                opts.present_queue_family,
            };
            swapchain_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
            swapchain_info.queueFamilyIndexCount = 2;
            swapchain_info.pQueueFamilyIndices = queue_family_indices.ptr;
        } else {
            swapchain_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        }

        var swapchain: c.VkSwapchainKHR = undefined;
        try check_vk(c.vkCreateSwapchainKHR(opts.device, &swapchain_info, opts.alloc_cb, &swapchain));
        errdefer c.vkDestroySwapchainKHR(opts.device, swapchain, opts.alloc_cb);

        // Try and fetch the images from the swpachain.
        var swapchain_image_count: u32 = undefined;
        try check_vk(c.vkGetSwapchainImagesKHR(opts.device, swapchain, &swapchain_image_count, null));
        const swapchain_images = try a.alloc(c.VkImage, swapchain_image_count);
        errdefer a.free(swapchain_images);
        try check_vk(c.vkGetSwapchainImagesKHR(opts.device, swapchain, &swapchain_image_count, swapchain_images.ptr));

        // Create image views for the swapchain images.
        const swapchain_image_views = try a.alloc(c.VkImageView, swapchain_image_count);
        errdefer a.free(swapchain_image_views);

        for (swapchain_images, swapchain_image_views) |image, *view| {
            view.* = try create_image_view(opts.device, image, format, c.VK_IMAGE_ASPECT_COLOR_BIT, opts.alloc_cb);
        }

        return .{
            .handle = swapchain,
            .images = swapchain_images,
            .image_views = swapchain_image_views,
            .format = format,
            .extent = extent,
        };
    }

    fn pick_format(formats: []const c.VkSurfaceFormatKHR, opts: SwapchainCreateOpts) c.VkFormat {
        const desired_format = opts.format;
        for (formats) |format| {
            if (format.format == desired_format.format and
                format.colorSpace == desired_format.colorSpace)
            {
                return format.format;
            }
        }
        return formats[0].format;
    }

    fn pick_present_mode(modes: []const c.VkPresentModeKHR, opts: SwapchainCreateOpts) c.VkPresentModeKHR {
        if (opts.vsync == true) {
            for (modes) |mode| {
                if (mode == c.VK_PRESENT_MODE_FIFO_RELAXED_KHR) {
                    return mode;
                }
            }
        } else {
            for (modes) |mode| {
                if (mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                    return mode;
                }
            }
        }
        // fallback
        return c.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn make_extent(capabilities: c.VkSurfaceCapabilitiesKHR, opts: SwapchainCreateOpts) c.VkExtent2D {
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        }

        var extent = c.VkExtent2D{
            .width = opts.window_width,
            .height = opts.window_height,
        };

        extent.width = @max(capabilities.minImageExtent.width, @min(capabilities.maxImageExtent.width, extent.width));
        extent.height = @max(capabilities.minImageExtent.height, @min(capabilities.maxImageExtent.height, extent.height));

        return extent;
    }
};

// fn create_swapchain(width: u32, height: u32) void {
//     const swapchain = Swapchain.create(cpu_allocator, .{
//         .physical_device = self.gpu,
//         .graphics_queue_family = self.graphics_queue_family,
//         .present_queue_family = self.graphics_queue_family,
//         .device = self.device,
//         .surface = self.window.surface,
//         .old_swapchain = null,
//         .vsync = false,
//         .format = .{ .format = c.VK_FORMAT_B8G8R8A8_SRGB, .colorSpace = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR },
//         .window_width = width,
//         .window_height = height,
//         .alloc_cb = vk_alloc_cbs,
//     }) catch @panic("Failed to create swapchain");
// }


// fn init_swapchain(self: *Self) void {
//     self.create_swapchain(self.window_extent.width, self.window_extent.height);
//     log.info("Created swapchain", .{});

//     self.draw_image_extent = c.VkExtent3D{
//         .width = self.window_extent.width,
//         .height = self.window_extent.height,
//         .depth = 1,
//     };

//     self.draw_image_format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
//     const draw_image_ci = std.mem.zeroInit(c.VkImageCreateInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
//         .imageType = c.VK_IMAGE_TYPE_2D,
//         .format = self.draw_image_format,
//         .extent = self.draw_image_extent,
//         .mipLevels = 1,
//         .arrayLayers = 1,
//         .samples = c.VK_SAMPLE_COUNT_1_BIT,
//         .tiling = c.VK_IMAGE_TILING_OPTIMAL,
//         .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_STORAGE_BIT,
//     });

//     const draw_image_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
//         .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
//         .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
//     });

//     check_vk(c.vmaCreateImage(self.gpu_allocator, &draw_image_ci, &draw_image_ai, &self.draw_image.image, &self.draw_image.allocation, null)) catch @panic("Failed to create draw image");
//     const draw_image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
//         .image = self.draw_image.image,
//         .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
//         .format = self.draw_image_format,
//         .subresourceRange = .{
//             .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
//             .baseMipLevel = 0,
//             .levelCount = 1,
//             .baseArrayLayer = 0,
//             .layerCount = 1,
//         },
//     });

//     check_vk(c.vkCreateImageView(self.device, &draw_image_view_ci, vk_alloc_cbs, &self.draw_image.view)) catch @panic("Failed to create draw image view");

//     self.depth_image_extent = self.draw_image_extent;
//     self.depth_image_format = c.VK_FORMAT_D32_SFLOAT;
//     const depth_image_ci = std.mem.zeroInit(c.VkImageCreateInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
//         .imageType = c.VK_IMAGE_TYPE_2D,
//         .format = self.depth_image_format,
//         .extent = self.depth_image_extent,
//         .mipLevels = 1,
//         .arrayLayers = 1,
//         .samples = c.VK_SAMPLE_COUNT_1_BIT,
//         .tiling = c.VK_IMAGE_TILING_OPTIMAL,
//         .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
//     });

//     check_vk(c.vmaCreateImage(self.gpu_allocator, &depth_image_ci, &draw_image_ai, &self.depth_image.image, &self.depth_image.allocation, null)) catch @panic("Failed to create depth image");

//     const depth_image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
//         .image = self.depth_image.image,
//         .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
//         .format = self.depth_image_format,
//         .subresourceRange = .{
//             .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
//             .baseMipLevel = 0,
//             .levelCount = 1,
//             .baseArrayLayer = 0,
//             .layerCount = 1,
//         },
//     });
//     check_vk(c.vkCreateImageView(self.device, &depth_image_view_ci, vk_alloc_cbs, &self.depth_image.view)) catch @panic("Failed to create depth image view");

//     self.image_deletion_queue.push(self.draw_image);
//     self.image_deletion_queue.push(self.depth_image);

//     log.info("Created depth image", .{});
// }

// fn resize_swapchain(self: *Self) void {
//     // log.info("Resizing swapchain", .{});
//     check_vk(c.vkDeviceWaitIdle(self.device)) catch |err| {
//         std.log.err("Failed to wait for device idle with error: {s}", .{@errorName(err)});
//         @panic("Failed to wait for device idle");
//     };
//     c.vkDestroySwapchainKHR(self.device, self.swapchain, vk_alloc_cbs);
//     for (self.swapchain_image_views) |view| {
//         c.vkDestroyImageView(self.device, view, vk_alloc_cbs);
//     }
//     self.cpu_allocator.free(self.swapchain_image_views);
//     self.cpu_allocator.free(self.swapchain_images);

//     var win_width: c_int = undefined;
//     var win_height: c_int = undefined;
//     check_sdl_bool(c.SDL_GetWindowSize(self.window.sdl_window, &win_width, &win_height));
//     self.window_extent.width = @intCast(win_width);
//     self.window_extent.height = @intCast(win_height);
//     self.create_swapchain(self.window_extent.width, self.window_extent.height);
//     self.resize_request = false;
// }
