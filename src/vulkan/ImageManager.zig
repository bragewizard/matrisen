const image = @import("image.zig");
const c = @import("../clibs/clibs.zig").libs;

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
swapchain_images: []c.VkImage = &.{},
swapchain_views: []c.VkImageView = &.{},
