const image = @import("image.zig");
const c = @import("../clibs/clibs.zig").libs;

// pub fn AllocatedImage(N: comptime_int) type {
//     return struct {
//         image: c.VkImage,
//         allocation: c.VmaAllocation,
//         views: [N]c.VkImageView,
//     };
// }

textures: [6]image.AllocatedImage = undefined,
depths: [1]image.AllocatedImage = undefined,
extent3d: [1]c.VkExtent3D = undefined,
extent2d: [1]c.VkExtent2D = undefined,
samplers: [2]c.VkSampler = undefined,
