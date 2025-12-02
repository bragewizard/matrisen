const c = @import("../clibs/clibs.zig").libs;
const AllocatedImage = @import("ImageAllocator.zig").AllocatedImage;

textures: AllocatedImage = undefined,
depths: AllocatedImage = undefined,
extent3d: c.VkExtent3D = undefined,
extent2d: c.VkExtent2D = undefined,
samplers: c.VkSampler = undefined,
