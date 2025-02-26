const background_color_light: t.ComputePushConstants = .{
    .data1 = m.Vec4{ .x = 0.5, .y = 0.5, .z = 0.5, .w = 0.0 },
    .data2 = m.Vec4{ .x = 0.8, .y = 0.8, .z = 0.8, .w = 0.0 },
    .data3 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    .data4 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
};
const background_color_dark: t.ComputePushConstants = .{
    .data1 = m.Vec4{ .x = 0.05, .y = 0.05, .z = 0.05, .w = 0.0 },
    .data2 = m.Vec4{ .x = 0.08, .y = 0.08, .z = 0.08, .w = 0.0 },
    .data3 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
    .data4 = m.Vec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
};


 
suzanne = load.load_gltf_meshes(self, "assets/icosphere.glb") catch @panic("Failed to load suzanne mesh");
const size = c.VkExtent3D{ .width = 1, .height = 1, .depth = 1 };
var white: u32 = m.Vec4.packU8(.{ .x = 1, .y = 1, .z = 1, .w = 1 });
var grey: u32 = m.Vec4.packU8(.{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 });
var black: u32 = m.Vec4.packU8(.{ .x = 0, .y = 0, .z = 0, .w = 0 });
const magenta: u32 = m.Vec4.packU8(.{ .x = 1, .y = 0, .z = 1, .w = 1 });

white_image = self.create_upload_image(&white, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);
grey_image = self.create_upload_image(&grey, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);
black_image = self.create_upload_image(&black, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);

var checker = [_]u32{0} ** (16 * 16);
for (0..16) |x| {
    for (0..16) |y| {
        const tile = ((x % 2) ^ (y % 2));
        checker[y * 16 + x] = if (tile == 1) black else magenta;
    }
}

self.error_checkerboard_image = self.create_upload_image(&checker, .{ .width = 16, .height = 16, .depth = 1 }, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);


fn init_default_data(self: *Self) void {
    self.suzanne = load.load_gltf_meshes(self, "assets/icosphere.glb") catch @panic("Failed to load suzanne mesh");
    const size = c.VkExtent3D{ .width = 1, .height = 1, .depth = 1 };
    var white: u32 = m.Vec4.packU8(.{ .x = 1, .y = 1, .z = 1, .w = 1 });
    var grey: u32 = m.Vec4.packU8(.{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 });
    var black: u32 = m.Vec4.packU8(.{ .x = 0, .y = 0, .z = 0, .w = 0 });
    const magenta: u32 = m.Vec4.packU8(.{ .x = 1, .y = 0, .z = 1, .w = 1 });

    self.white_image = self.create_upload_image(&white, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);
    self.grey_image = self.create_upload_image(&grey, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);
    self.black_image = self.create_upload_image(&black, size, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);

    var checker = [_]u32{0} ** (16 * 16);
    for (0..16) |x| {
        for (0..16) |y| {
            const tile = ((x % 2) ^ (y % 2));
            checker[y * 16 + x] = if (tile == 1) black else magenta;
        }
    }

    self.error_checkerboard_image = self.create_upload_image(&checker, .{ .width = 16, .height = 16, .depth = 1 }, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT, false);

    var sampl = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = c.VK_FILTER_NEAREST,
        .minFilter = c.VK_FILTER_NEAREST,
    };
    check_vk(c.vkCreateSampler(self.device, &sampl, null, &self.default_sampler_nearest)) catch @panic("falied to make sampler");
    sampl.magFilter = c.VK_FILTER_LINEAR;
    sampl.minFilter = c.VK_FILTER_LINEAR;
    check_vk(c.vkCreateSampler(self.device, &sampl, null, &self.default_sampler_linear)) catch @panic("failed to make sampler");
    self.sampler_deletion_queue.push(self.default_sampler_nearest);
    self.sampler_deletion_queue.push(self.default_sampler_linear);
    self.image_deletion_queue.push(self.white_image);
    self.image_deletion_queue.push(self.grey_image);
    self.image_deletion_queue.push(self.black_image);
    self.image_deletion_queue.push(self.error_checkerboard_image);

    var materialresources = GLTFMetallicRoughness.MaterialResources{};
    materialresources.colorimage = self.white_image;
    materialresources.colorsampler = self.default_sampler_linear;
    materialresources.metalroughimage = self.white_image;
    materialresources.metalroughsampler = self.default_sampler_linear;

    const materialconstants = self.create_buffer(@sizeOf(GLTFMetallicRoughness.MaterialConstants), c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    self.buffer_deletion_queue.push(materialconstants);

    var sceneuniformdata = @as(*GLTFMetallicRoughness.MaterialConstants, @alignCast(@ptrCast(materialconstants.info.pMappedData.?)));
    sceneuniformdata.colorfactors = m.Vec4{ .x = 1, .y = 1, .z = 1, .w = 1 };
    sceneuniformdata.metalrough_factors = m.Vec4{ .x = 1, .y = 0.5, .z = 1, .w = 1 };
    materialresources.databuffer = materialconstants.buffer;
    materialresources.databuffer_offset = 0;
    self.defaultdata = self.metalroughmaterial.write_material(self.device, t.MaterialPass.MainColor, materialresources, &self.global_descriptor_allocator);

    std.log.info("Initialized default data", .{});
}
