const std = @import("std");
const c = @import("clibs");
const geometry = @import("geometry");
const check_vk_panic = @import("../debug.zig").check_vk_panic;
const common = @import("common.zig");
const descriptorbuilder = @import("../descriptorbuilder.zig");
const vk_alloc_cbs = Core.vkallocationcallbacks;
const PipelineBuilder = @import("../pipelinebuilder.zig");
const ModelPushConstants = common.ModelPushConstants;
const SceneDataUniform = common.SceneDataUniform;
const FrameContext = @import("../commands.zig").FrameContext;
const LayoutBuilder = descriptorbuilder.LayoutBuilder;
const Writer = descriptorbuilder.Writer;
const Core = @import("../core.zig");
const Mat4x4 = geometry.Mat4x4(f32);

layout: c.VkPipelineLayout = undefined,
pipeline: c.VkPipeline = undefined,
texturelayout: c.VkDescriptorSetLayout = undefined,
scenedatalayout: c.VkDescriptorSetLayout = undefined,
textureset: c.VkDescriptorSet = undefined,

const Self = @This();

pub fn init(self: *Self, core: *Core) void {
    {
        var builder: LayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        self.scenedatalayout = builder.build(
            core.device.handle,
            c.VK_SHADER_STAGE_MESH_BIT_EXT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    {
        var builder: LayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        builder.add_binding(1, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        builder.add_binding(2, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        self.texturelayout = builder.build(
            core.device.handle,
            c.VK_SHADER_STAGE_MESH_BIT_EXT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    const mesh_code align(4) = @embedFile("simple.mesh.glsl").*;
    const fragment_code align(4) = @embedFile("simple.frag.glsl").*;

    const mesh_module = PipelineBuilder.createShaderModule(core.device.handle, &mesh_code, vk_alloc_cbs) orelse null;
    const fragment_module = PipelineBuilder.createShaderModule(core.device.handle, &fragment_code, vk_alloc_cbs) orelse null;
    if (mesh_module != null) std.log.info("Created mesh shader module", .{});
    if (fragment_module != null) std.log.info("Created fragment shader module", .{});

    defer c.vkDestroyShaderModule(core.device.handle, mesh_module, vk_alloc_cbs);
    defer c.vkDestroyShaderModule(core.device.handle, fragment_module, vk_alloc_cbs);
    const stage_mesh: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT,
        .module = mesh_module,
        .pName = "main",
    };

    const stage_frag: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragment_module,
        .pName = "main",
    };

    const matrixrange = c.VkPushConstantRange{
        .offset = 0,
        .size = @sizeOf(ModelPushConstants),
        .stageFlags = c.VK_SHADER_STAGE_MESH_BIT_EXT,
    };
    const layouts = [_]c.VkDescriptorSetLayout{ self.scenedatalayout, self.texturelayout };

    const mesh_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &matrixrange,
    };

    var newlayout: c.VkPipelineLayout = undefined;

    check_vk_panic(c.vkCreatePipelineLayout(core.device.handle, &mesh_layout_info, null, &newlayout));

    self.layout = newlayout;

    var shaders :[2]c.VkPipelineShaderStageCreateInfo = .{ stage_mesh, stage_frag };
    var pipelineBuilder : PipelineBuilder = .init();
    pipelineBuilder.shader_stages = &shaders;
    pipelineBuilder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
    pipelineBuilder.set_cull_mode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.set_multisampling_none();
    pipelineBuilder.disable_blending();
    pipelineBuilder.enable_depthtest(true, c.VK_COMPARE_OP_LESS);
    pipelineBuilder.set_color_attachment_format(core.images.renderattachmentformat);
    pipelineBuilder.set_depth_format(core.images.depth_format);
    pipelineBuilder.pipeline_layout = newlayout;
    self.pipeline = pipelineBuilder.buildPipeline(core.device.handle);
}

pub fn deinit(self: *Self, core: *Core) void {
    c.vkDestroyDescriptorSetLayout(core.device.handle, self.scenedatalayout, vk_alloc_cbs);
    c.vkDestroyDescriptorSetLayout(core.device.handle, self.texturelayout, vk_alloc_cbs);
    c.vkDestroyPipelineLayout(core.device.handle, self.layout, vk_alloc_cbs);
    c.vkDestroyPipeline(core.device.handle, self.pipeline, vk_alloc_cbs);
}

pub fn draw(self: *Self, core: *Core, frame: *FrameContext) void {
    const cmd = frame.command_buffer;
    const set = frame.descriptors.allocate(core.device.handle, self.scenedatalayout, null);
    {
        var writer: Writer = .init(core.cpuallocator);
        defer writer.deinit();
        writer.write_buffer(
            0,
            frame.allocatedbuffers.buffer,
            @sizeOf(SceneDataUniform),
            0,
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        );
        writer.update_set(core.device.handle, set);
    }

    const view = Mat4x4.identity;
    const model = view;
    var pc: ModelPushConstants = .{
        .model = model,
        .vertex_buffer = 0,
    };

    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.layout, 0, 1, &set, 0, null);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.layout, 1, 1, &self.textureset, 0, null);
    c.vkCmdPushConstants(cmd, self.layout, c.VK_SHADER_STAGE_MESH_BIT_EXT, 0, @sizeOf(ModelPushConstants), &pc);
    core.vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1);
}
