const std = @import("std");
const meshshadermodule = @import("meshshader.zig");
const pbrmodule = @import("pbr.zig");
const c = @import("clibs");
const geometry = @import("geometry");
const buffers = @import("../buffers.zig");
const check_vk_panic = @import("../debug.zig").check_vk_panic;
const check_vk = @import("../debug.zig").check_vk;
const common = @import("common.zig");
const descriptorbuilder = @import("../descriptorbuilder.zig");
const MaterialConstantsUniform = common.MaterialConstantsUniform;
const SceneDataUniform = common.SceneDataUniform;
const Writer = descriptorbuilder.Writer;
const Allocator = descriptorbuilder.Allocator;
const Core = @import("../core.zig");
const FrameContext = @import("../commands.zig").FrameContext;
const Vec4 = geometry.Vec4(f32);
const Vec3 = geometry.Vec3(f32);
const Quat = geometry.Quat(f32);
const Mat4x4 = geometry.Mat4x4(f32);

meshshader: meshshadermodule = .{},
pbr: pbrmodule = .{},
descriptorallocator: Allocator = .{},

const Self = @This();

pub fn init(core: *Core) void {
    var self = &core.pipelines;
    self.meshshader.init(core);
    self.pbr.init(core);
    self.writeDescriptorsets(core);
}

pub fn deinit(core: *Core) void {
    var self = &core.pipelines;
    self.meshshader.deinit(core);
    self.pbr.deinit(core);
    self.descriptorallocator.deinit(core.device.handle);
}

/// Write the texture data before we start rendering
pub fn writeDescriptorsets(self: *Self, core: *Core) void {
    var sizes = [_]Allocator.PoolSizeRatio{
        .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
        .{ .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 1 },
    };
    self.descriptorallocator.init(core.device.handle, 10, &sizes, core.cpuallocator);

    self.meshshader.textureset = self.descriptorallocator.allocate(core.device.handle, self.meshshader.texturelayout, null);
    self.pbr.textureset = self.descriptorallocator.allocate(core.device.handle, self.pbr.texturelayout, null);

    core.buffers.uniform[0] = buffers.create(
        core,
        @sizeOf(MaterialConstantsUniform),
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    var materialuniformdata = @as(
        *MaterialConstantsUniform,
        @alignCast(@ptrCast(core.buffers.uniform[0].info.pMappedData.?)),
    );
    materialuniformdata.colorfactors = Vec4{ .x = 1, .y = 1, .z = 1, .w = 1 };
    materialuniformdata.metalrough_factors = Vec4{ .x = 1, .y = 0.5, .z = 1, .w = 1 };

    {
        var writer: Writer = .init(core.cpuallocator);
        defer writer.deinit();
        writer.clear();
        writer.write_buffer(
            0,
            core.buffers.uniform[0].buffer,
            @sizeOf(MaterialConstantsUniform),
            0,
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        );
        writer.write_image(
            1,
            core.images.textures[1].views[0],
            core.images.samplers[0],
            c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL,
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        );
        writer.write_image(
            2,
            core.images.textures[1].views[0],
            core.images.samplers[0],
            c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL,
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        );
        writer.update_set(core.device.handle, self.meshshader.textureset);
        writer.update_set(core.device.handle, self.pbr.textureset);
    }
}

pub fn setSceneData(core: *Core, frame: *FrameContext, view: Mat4x4 ) void {
    frame.allocatedbuffers = buffers.create(
        core,
        @sizeOf(SceneDataUniform),
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    var scene_uniform_data: *SceneDataUniform = @alignCast(@ptrCast(frame.allocatedbuffers.info.pMappedData.?));
    scene_uniform_data.view = view;
    scene_uniform_data.proj = Mat4x4.perspective(
        std.math.degreesToRadians(60.0),
        @as(f32, @floatFromInt(frame.draw_extent.width)) / @as(f32, @floatFromInt(frame.draw_extent.height)),
        0.1,
        1000.0,
    );
    scene_uniform_data.viewproj = Mat4x4.mul(scene_uniform_data.proj, scene_uniform_data.view);
    scene_uniform_data.sunlight_dir = .{ .x = 0.1, .y = 0.1, .z = 1, .w = 1 };
    scene_uniform_data.sunlight_color = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    scene_uniform_data.ambient_color = .{ .x = 1, .y = 0.6, .z = 0, .w = 1 };
}
