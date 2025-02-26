const Core = @import("core.zig");
const check_vk = @import("debug.zig").check_vk;
const FrameContext = @import("framecontext.zig");
const c = @import("../clibs.zig");
const std = @import("std");
const log = std.log.scoped(.draw);
const transition_image = @import("commands.zig").transition_image;
const copy_image_to_image = @import("commands.zig").copy_image_to_image;
const SceneDataUniform = @import("pipelines&materials/common.zig").SceneDataUniform;
const m = @import("../3Dmath.zig");

pub fn draw(core: *Core) void {
    const timeout: u64 = 4_000_000_000; // 4 second in nanonesconds
    const frame_index = core.framecontext.current;
    const frame = core.framecontext.frames[frame_index];
    check_vk(c.vkWaitForFences(core.device.handle, 1, &frame.render_fence, c.VK_TRUE, timeout)) catch |err| {
        log.err("Failed to wait for render fence with error: {s}", .{@errorName(err)});
        @panic("Failed to wait for render fence");
    };

    var swapchain_image_index: u32 = undefined;
    var e = c.vkAcquireNextImageKHR(core.device.handle, core.swapchain.handle, timeout, frame.swapchain_semaphore, null, &swapchain_image_index);
    if (e == c.VK_ERROR_OUT_OF_DATE_KHR) {
        // log.warn("out of date", .{});
        core.resize_request = true;
        return;
    }
    check_vk(c.vkResetFences(core.device.handle, 1, &frame.render_fence)) catch @panic("Failed to reset render fence");
    const cmd = frame.command_buffer;
    check_vk(c.vkResetCommandBuffer(cmd, 0)) catch @panic("Failed to reset command buffer");

    const cmd_begin_info = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });

    check_vk(c.vkBeginCommandBuffer(cmd, &cmd_begin_info)) catch @panic("Failed to begin command buffer");

    transition_image(cmd, core.swapchain.images[swapchain_image_index], c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL);
    // const clearvalue = c.VkClearColorValue{ .float32 = .{ 0, 0.1, 0.1, 1 } };
    // const clearrange = c.VkImageSubresourceRange{
    //     .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
    //     .levelCount = 1,
    //     .layerCount = 1,
    // };
    // c.vkCmdClearColorImage(cmd, core.swapchain.images[swapchain_image_index], c.VK_IMAGE_LAYOUT_GENERAL, &clearvalue, 1, &clearrange);
    const extent = core.swapchain.extent;

    const color_attachment: c.VkRenderingAttachmentInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = core.swapchain.image_views[swapchain_image_index],
        .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
    };

    const render_info: c.VkRenderingInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = extent,
        },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment,
    };

    const viewport: c.VkViewport = .{
        .x = 0.0,
        .y = 0.0,
        .width = @as(f32, @floatFromInt(extent.width)),
        .height = @as(f32, @floatFromInt(extent.height)),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor: c.VkRect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    c.vkCmdBeginRendering(cmd, &render_info);
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, core.pipelines[0]);
    c.vkCmdSetViewport(cmd, 0, 1, &viewport);
    c.vkCmdSetScissor(cmd, 0, 1, &scissor);
    core.vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1);
    c.vkCmdEndRendering(cmd);

    transition_image(cmd, core.swapchain.images[swapchain_image_index], c.VK_IMAGE_LAYOUT_GENERAL, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

    check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info = c.VkCommandBufferSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };

    const wait_info = c.VkSemaphoreSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame.swapchain_semaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    };

    const signal_info = c.VkSemaphoreSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame.render_semaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    };

    const submit = c.VkSubmitInfo2{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &wait_info,
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal_info,
    };

    check_vk(c.vkQueueSubmit2(core.device.graphics_queue, 1, &submit, frame.render_fence)) catch |err| {
        std.log.err("Failed to submit to graphics queue with error: {s}", .{@errorName(err)});
        @panic("Failed to submit to graphics queue");
    };

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &frame.render_semaphore,
        .swapchainCount = 1,
        .pSwapchains = &core.swapchain.handle,
        .pImageIndices = &swapchain_image_index,
    };
    e = c.vkQueuePresentKHR(core.device.graphics_queue, &present_info);
    core.frame_number +%= 1;
    core.framecontext.switch_frame();
}

// fn draw_geometry(self: *Core, cmd: c.VkCommandBuffer) void {
//     const color_attachment = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
//         .imageView = self.draw_image.view,
//         .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL,
//         .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
//         .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
//     });
//     const depth_attachment = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
//         .imageView = self.depth_image.view,
//         .imageLayout = c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
//         .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
//         .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
//         .clearValue = .{
//             .depthStencil = .{ .depth = 0.0, .stencil = 0.0 },
//         },
//     });

//     const render_info = std.mem.zeroInit(c.VkRenderingInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
//         .renderArea = .{
//             .offset = .{ .x = 0, .y = 0 },
//             .extent = self.draw_extent,
//         },
//         .layerCount = 1,
//         .colorAttachmentCount = 1,
//         .pColorAttachments = &color_attachment,
//         .pDepthAttachment = &depth_attachment,
//     });

//     self.scene_data.view = m.Mat4.translation(.{ .x=0,.y=0,.z = -5 });
//     self.scene_data.proj = m.Mat4.perspective(70.0, @as(f32, @floatFromInt(self.draw_extent.width)) / @as(f32, @floatFromInt(self.draw_extent.height)), 1000.0, 1.0);
//     self.scene_data.proj.j.y *= -1;
//     self.scene_data.viewproj = m.Mat4.mul(self.scene_data.proj, self.scene_data.view);
//     self.scene_data.sunlight_dir = .{ .x = 0, .y = 0,.z = 1,.w = 1};
//     self.scene_data.sunlight_color = .{ .x = 0.2, .y = 0, .z = 0,.w = 1 };

//     const gpu_scene_data_buffer = self.create_buffer(@sizeOf(SceneDataUniform), c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
//     var frame = self.get_current_frame();
//     frame.buffer_deletion_queue.push(gpu_scene_data_buffer);

//     const scene_uniform_data: *SceneDataUniform = @alignCast(@ptrCast(gpu_scene_data_buffer.info.pMappedData.?));
//     scene_uniform_data.* = self.scene_data;

//     const global_descriptor = frame.frame_descriptors.allocate(self.device, self.gpu_scene_data_descriptor_layout, null);
//     {
//         var writer = d.DescriptorWriter.init(self.cpu_allocator);
//         defer writer.deinit();
//         writer.write_buffer(0, gpu_scene_data_buffer.buffer, @sizeOf(t.GPUSceneData), 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
//         writer.update_set(self.device, global_descriptor);
//     }

//     c.vkCmdBeginRendering(cmd, &render_info);
//     const viewport = std.mem.zeroInit(c.VkViewport, .{
//         .x = 0.0,
//         .y = 0.0,
//         .width = @as(f32, @floatFromInt(self.draw_extent.width)),
//         .height = @as(f32, @floatFromInt(self.draw_extent.height)),
//         .minDepth = 0.0,
//         .maxDepth = 1.0,
//     });

//     // c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline);
//     // const image_set = self.get_current_frame().frame_descriptors.allocate(self.device, self.single_image_descriptor_layout, null);
//     // {
//     //     var writer = d.DescriptorWriter.init(self.cpu_allocator);
//     //     defer writer.deinit();
//     //     writer.write_image(0, self.error_checkerboard_image.view, self.default_sampler_nearest, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
//     //     writer.update_set(self.device, image_set);
//     // }
//     // c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline_layout, 0, 1, &image_set, 0, null);

//     c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.defaultdata.pipeline.pipeline);
//     c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.metalroughmaterial.opaque_pipeline.layout, 0, 1, &global_descriptor, 0, null);
//     c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.metalroughmaterial.opaque_pipeline.layout, 1, 1, &self.defaultdata.materialset, 0, null);

//     c.vkCmdSetViewport(cmd, 0, 1, &viewport);

//     const scissor = std.mem.zeroInit(c.VkRect2D, .{
//         .offset = .{ .x = 0, .y = 0 },
//         .extent = self.draw_extent,
//     });

//     c.vkCmdSetScissor(cmd, 0, 1, &scissor);
//     var view = m.Mat4.rotation(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, std.math.pi / 2.0);
//     view = view.rotate(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi);
//     view = view.translate(.{ .x = 0.0, .y = 0.0, .z = -5.0 });
//     var model = view;
//     model.i.y *= -1.0;
//     var push_constants = t.GPUDrawPushConstants{
//         .model = model,
//         .vertex_buffer = self.suzanne.items[0].mesh_buffers.vertex_buffer_adress,
//     };

//     c.vkCmdPushConstants(cmd, self.metalroughmaterial.opaque_pipeline.layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(t.GPUDrawPushConstants), &push_constants);
//     c.vkCmdBindIndexBuffer(cmd, self.suzanne.items[0].mesh_buffers.index_buffer.buffer, 0, c.VK_INDEX_TYPE_UINT32);
//     const surface = self.suzanne.items[0].surfaces.items[0];
//     c.vkCmdDrawIndexed(cmd, surface.count, 1, surface.start_index, 0, 0);
//     c.vkCmdEndRendering(cmd);
// }
