// imports
const std = @import("std");
const lua = @import("scripting.zig");
const check_vk = @import("debug.zig").check_vk;
const transition_image = @import("image.zig").transition_image;
const copy_image_to_image = @import("image.zig").copy_image_to_image;
const d = @import("descriptors.zig");
const c = @import("../clibs.zig");
const m = @import("../3Dmath.zig");
const Window = @import("../window.zig");
const PipelineBuilder = @import("pipelinebuilder.zig");
const t = @import("types.zig");
const Instance = @import("instance.zig");
const log = std.log.scoped(.core);
const PhysicalDevice = @import("device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig").Swapchain;

// container level variables
pub const vk_alloc_cbs: ?*c.VkAllocationCallbacks = null;
const FRAME_OVERLAP = 2;
const Self = @This();

// member variables
resize_request: bool = false,
render_scale: f32 = 1.0,
window_extent: c.VkExtent2D = undefined,
depth_image: t.AllocatedImageAndView = undefined,
depth_image_format: c.VkFormat = undefined,
depth_image_extent: c.VkExtent3D = undefined,
draw_image: t.AllocatedImageAndView = undefined,
draw_image_format: c.VkFormat = undefined,
draw_image_extent: c.VkExtent3D = undefined,
draw_extent: c.VkExtent2D = undefined,

cpu_allocator: std.mem.Allocator = undefined,
gpu_allocator: c.VmaAllocator = undefined,
instance: Instance = undefined,
physical_device: PhysicalDevice = undefined,
device: Device = undefined,
surface: c.VkSurfaceKHR = undefined,
swapchain: Swapchain = undefined,
immidiate_fence: c.VkFence = null,
immidiate_command_buffer: c.VkCommandBuffer = null,
immidiate_command_pool: c.VkCommandPool = null,
frames: [FRAME_OVERLAP]t.FrameData = .{t.FrameData{}} ** FRAME_OVERLAP,
frame_number: u32 = 0,
// descriptors
global_descriptor_allocator: d.DescriptorAllocatorGrowable = undefined,
draw_image_descriptors: c.VkDescriptorSet = undefined,
draw_image_descriptor_layout: c.VkDescriptorSetLayout = undefined,
gradient_pipeline_layout: c.VkPipelineLayout = null,
gradient_pipeline: c.VkPipeline = null,
gpu_scene_data_descriptor_layout: c.VkDescriptorSetLayout = undefined,
single_image_descriptor_layout: c.VkDescriptorSetLayout = undefined,
triangle_pipeline_layout: c.VkPipelineLayout = null,
triangle_pipeline: c.VkPipeline = null,
mesh_pipeline_layout: c.VkPipelineLayout = null,
mesh_pipeline: c.VkPipeline = null,
lua_state: ?*c.lua_State = undefined,

pub fn run(allocator: std.mem.Allocator, window: ?*Window) void {
    var engine = Self{};
    engine.cpu_allocator = allocator;
    var init_allocator = std.heap.ArenaAllocator.init(engine.cpu_allocator);
    engine.lua_state = c.luaL_newstate();
    defer c.lua_close(engine.lua_state);
    lua.register_lua_functions(&engine);
    engine.instance = Instance.create(init_allocator.allocator()) catch @panic("failed to create instance");
    defer c.vkDestroyInstance(engine.instance.handle, vk_alloc_cbs);
    if (engine.instance.debug_messenger != null) {
        const destroy_fn = engine.instance.get_destroy_debug_utils_messenger_fn().?;
        defer destroy_fn(engine.instance.handle, engine.instance.debug_messenger, vk_alloc_cbs);
    }
    if (window) |w| {
        w.create_surface(engine.instance.handle, &engine.surface);
    }
    defer c.vkDestroySurfaceKHR(engine.instance.handle, engine.surface, vk_alloc_cbs);
    engine.physical_device = PhysicalDevice.select(init_allocator.allocator(), engine.instance.handle, engine.surface) catch {
        log.err("buhu", .{});
        unreachable;
    };
    engine.device = Device.create(init_allocator.allocator(), engine.physical_device) catch {
        log.err("buhu", .{});
        unreachable;
    };
    defer c.vkDestroyDevice(engine.device.handle, vk_alloc_cbs);

    const allocator_ci = std.mem.zeroInit(c.VmaAllocatorCreateInfo, .{
        .physicalDevice = engine.physical_device.handle,
        .device = engine.device.handle,
        .instance = engine.instance.handle,
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    });
    check_vk(c.vmaCreateAllocator(&allocator_ci, &engine.gpu_allocator)) catch @panic("Failed to create VMA allocator");
    defer c.vmaDestroyAllocator(engine.gpu_allocator);

    // engine.swapchain = 
    // engine.init_commands();
    // engine.init_sync_structures();
    // engine.init_descriptors();
    // engine.init_pipelines();
    // engine.init_default_data();
    // c.luaL_openlibs(engine.lua_state);
    // check_vk(c.vkDeviceWaitIdle(self.device)) catch @panic("Failed to wait for device idle");
    // c.vkDestroyDescriptorSetLayout(self.device, self.draw_image_descriptor_layout, vk_alloc_cbs);
    // c.vkDestroyDescriptorSetLayout(self.device, self.gpu_scene_data_descriptor_layout, vk_alloc_cbs);
    // c.vkDestroyDescriptorSetLayout(self.device, self.single_image_descriptor_layout, vk_alloc_cbs);
    // self.global_descriptor_allocator.deinit(self.device);
    // for (&self.frames) |*frame| {
    //     frame.buffer_deletion_queue.deinit(self.gpu_allocator);
    //     c.vkDestroyCommandPool(self.device, frame.command_pool, vk_alloc_cbs);
    //     c.vkDestroyFence(self.device, frame.render_fence, vk_alloc_cbs);
    //     c.vkDestroySemaphore(self.device, frame.render_semaphore, vk_alloc_cbs);
    //     c.vkDestroySemaphore(self.device, frame.swapchain_semaphore, vk_alloc_cbs);
    //     frame.frame_descriptors.deinit(self.device);
    // }
    // defer c.vkDestroyFence(self.device, self.immidiate_fence, vk_alloc_cbs);
    // defer c.vkDestroyCommandPool(self.device, self.immidiate_command_pool, vk_alloc_cbs);

    // defer c.vkDestroySwapchainKHR(self.device, self.swapchain, vk_alloc_cbs);
    // for (self.swapchain_image_views) |view| {
    //     defer c.vkDestroyImageView(self.device, view, vk_alloc_cbs);
    // }
    // self.cpu_allocator.free(self.swapchain_image_views);
    // self.cpu_allocator.free(self.swapchain_images);

    init_allocator.deinit();
    // loop();
}

fn get_current_frame(self: *Self) *t.FrameData {
    return &self.frames[@intCast(@mod(self.frame_number, FRAME_OVERLAP))];
}

fn draw(self: *Self) void {
    const timeout: u64 = 4_000_000_000; // 4 second in nanonesconds
    var frame = self.get_current_frame();
    check_vk(c.vkWaitForFences(self.device, 1, &frame.render_fence, c.VK_TRUE, timeout)) catch |err| {
        std.log.err("Failed to wait for render fence with error: {s}", .{@errorName(err)});
        @panic("Failed to wait for render fence");
    };

    frame.buffer_deletion_queue.flush(self.gpu_allocator);
    frame.frame_descriptors.clear_pools(self.device);

    var swapchain_image_index: u32 = undefined;
    var e = c.vkAcquireNextImageKHR(self.device, self.swapchain, timeout, frame.swapchain_semaphore, null, &swapchain_image_index);
    if (e == c.VK_ERROR_OUT_OF_DATE_KHR) {
        self.resize_request = true;
        return;
    }

    check_vk(c.vkResetFences(self.device, 1, &frame.render_fence)) catch @panic("Failed to reset render fence");
    check_vk(c.vkResetCommandBuffer(frame.main_command_buffer, 0)) catch @panic("Failed to reset command buffer");

    const cmd = frame.main_command_buffer;
    const cmd_begin_info = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });

    self.draw_extent.width = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain_extent.width, self.draw_image_extent.width))) * self.render_scale);
    self.draw_extent.height = @intFromFloat(@as(f32, @floatFromInt(@min(self.swapchain_extent.height, self.draw_image_extent.height))) * self.render_scale);

    check_vk(c.vkBeginCommandBuffer(cmd, &cmd_begin_info)) catch @panic("Failed to begin command buffer");

    transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL);
    self.draw_background(cmd);
    transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    transition_image(cmd, self.depth_image.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL);
    self.draw_geometry(cmd);
    transition_image(cmd, self.draw_image.image, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);

    transition_image(cmd, self.swapchain_images[swapchain_image_index], c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    copy_image_to_image(cmd, self.draw_image.image, self.swapchain_images[swapchain_image_index], self.draw_extent, self.swapchain_extent);
    transition_image(cmd, self.swapchain_images[swapchain_image_index], c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

    check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info = std.mem.zeroInit(c.VkCommandBufferSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    });

    const wait_info = std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame.swapchain_semaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    });

    const signal_info = std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = frame.render_semaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    });

    const submit = std.mem.zeroInit(c.VkSubmitInfo2, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &wait_info,
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal_info,
    });

    check_vk(c.vkQueueSubmit2(self.graphics_queue, 1, &submit, frame.render_fence)) catch |err| {
        std.log.err("Failed to submit to graphics queue with error: {s}", .{@errorName(err)});
        @panic("Failed to submit to graphics queue");
    };

    const present_info = std.mem.zeroInit(c.VkPresentInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &frame.render_semaphore,
        .swapchainCount = 1,
        .pSwapchains = &self.swapchain,
        .pImageIndices = &swapchain_image_index,
    });
    e = c.vkQueuePresentKHR(self.graphics_queue, &present_info);
    if (e == c.VK_ERROR_OUT_OF_DATE_KHR) {
        self.resize_request = true;
    }
    self.frame_number +%= 1;
}

pub fn create_shader_module(self: *Self, code: []const u8, alloc_callback: ?*c.VkAllocationCallbacks) ?c.VkShaderModule {
    std.debug.assert(code.len % 4 == 0);

    const data: *const u32 = @alignCast(@ptrCast(code.ptr));

    const shader_module_ci = std.mem.zeroInit(c.VkShaderModuleCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = data,
    });

    var shader_module: c.VkShaderModule = undefined;
    check_vk(c.vkCreateShaderModule(self.device, &shader_module_ci, alloc_callback, &shader_module)) catch |err| {
        log.err("Failed to create shader module with error: {s}", .{@errorName(err)});
        return null;
    };

    return shader_module;
}

fn get_vulkan_instance_funct(self: *Self, comptime Fn: type, name: [*c]const u8) Fn {
    const get_proc_addr: c.PFN_vkGetInstanceProcAddr = @ptrCast(c.SDL_Vulkan_GetVkGetInstanceProcAddr());
    if (get_proc_addr) |get_proc_addr_fn| {
        return @ptrCast(get_proc_addr_fn(self.instance, name));
    }

    @panic("SDL_Vulkan_GetVkGetInstanceProcAddr returned null");
}

fn draw_background(self: *Self, cmd: c.VkCommandBuffer) void {
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.gradient_pipeline);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.gradient_pipeline_layout, 0, 1, &self.draw_image_descriptors, 0, null);
    c.vkCmdPushConstants(cmd, self.gradient_pipeline_layout, c.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(t.ComputePushConstants), &self.pc);
    c.vkCmdDispatch(cmd, self.window_extent.width / 32, self.window_extent.height / 32, 1);
}

fn draw_geometry(self: *Self, cmd: c.VkCommandBuffer) void {
    const color_attachment = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.draw_image.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
    });
    const depth_attachment = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_image.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{
            .depthStencil = .{ .depth = 0.0, .stencil = 0.0 },
        },
    });

    const render_info = std.mem.zeroInit(c.VkRenderingInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.draw_extent,
        },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment,
        .pDepthAttachment = &depth_attachment,
    });

    const gpu_scene_data_buffer = self.create_buffer(@sizeOf(t.GPUSceneData), c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    var frame = self.get_current_frame();
    frame.buffer_deletion_queue.push(gpu_scene_data_buffer);

    const scene_uniform_data: *t.GPUSceneData = @alignCast(@ptrCast(gpu_scene_data_buffer.info.pMappedData.?));
    scene_uniform_data.* = self.scene_data;

    const global_descriptor = frame.frame_descriptors.allocate(self.device, self.gpu_scene_data_descriptor_layout, null);
    {
        var writer = d.DescriptorWriter.init(self.cpu_allocator);
        defer writer.deinit();
        writer.write_buffer(0, gpu_scene_data_buffer.buffer, @sizeOf(t.GPUSceneData), 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        writer.update_set(self.device, global_descriptor);
    }

    c.vkCmdBeginRendering(cmd, &render_info);
    const viewport = std.mem.zeroInit(c.VkViewport, .{
        .x = 0.0,
        .y = 0.0,
        .width = @as(f32, @floatFromInt(self.draw_extent.width)),
        .height = @as(f32, @floatFromInt(self.draw_extent.height)),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    });

    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline);
    const image_set = self.get_current_frame().frame_descriptors.allocate(self.device, self.single_image_descriptor_layout, null);
    {
        var writer = d.DescriptorWriter.init(self.cpu_allocator);
        defer writer.deinit();
        writer.write_image(0, self.error_checkerboard_image.view, self.default_sampler_nearest, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        writer.update_set(self.device, image_set);
    }
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline_layout, 0, 1, &image_set, 0, null);

    c.vkCmdSetViewport(cmd, 0, 1, &viewport);

    const scissor = std.mem.zeroInit(c.VkRect2D, .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.draw_extent,
    });

    c.vkCmdSetScissor(cmd, 0, 1, &scissor);
    var view = m.Mat4.rotation(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, std.math.pi / 2.0);
    view = view.rotate(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, std.math.pi);
    view = view.translate(.{ .x = 0.0, .y = 0.0, .z = -5.0 });
    const projection = m.Mat4.perspective(70.0, @as(f32, @floatFromInt(self.draw_extent.width)) / @as(f32, @floatFromInt(self.draw_extent.height)), 1000.0, 1.0);
    var model = m.Mat4.mul(projection, view);
    model.i.y *= -1.0;
    var push_constants = t.GPUDrawPushConstants{
        .model = model,
        .vertex_buffer = self.suzanne.items[0].mesh_buffers.vertex_buffer_adress,
    };

    c.vkCmdPushConstants(cmd, self.mesh_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(t.GPUDrawPushConstants), &push_constants);
    c.vkCmdBindIndexBuffer(cmd, self.suzanne.items[0].mesh_buffers.index_buffer.buffer, 0, c.VK_INDEX_TYPE_UINT32);
    const surface = self.suzanne.items[0].surfaces.items[0];
    c.vkCmdDrawIndexed(cmd, surface.count, 1, surface.start_index, 0, 0);
    c.vkCmdEndRendering(cmd);
}

pub fn immediate_submit(self: *Self, submit_ctx: anytype) void {
    comptime {
        var Context = @TypeOf(submit_ctx);
        var is_ptr = false;
        switch (@typeInfo(Context)) {
            .Struct, .Union, .Enum => {},
            .Pointer => |ptr| {
                if (ptr.size != .One) {
                    @compileError("Context must be a type with a submit function. " ++ @typeName(Context) ++ "is a multi element pointer");
                }
                Context = ptr.child;
                is_ptr = true;
                switch (Context) {
                    .Struct, .Union, .Enum, .Opaque => {},
                    else => @compileError("Context must be a type with a submit function. " ++ @typeName(Context) ++ "is a pointer to a non struct/union/enum/opaque type"),
                }
            },
            else => @compileError("Context must be a type with a submit method. Cannot use: " ++ @typeName(Context)),
        }

        if (!@hasDecl(Context, "submit")) {
            @compileError("Context should have a submit method");
        }

        const submit_fn_info = @typeInfo(@TypeOf(Context.submit));
        if (submit_fn_info != .Fn) {
            @compileError("Context submit method should be a function");
        }

        if (submit_fn_info.Fn.params.len != 2) {
            @compileError("Context submit method should have two parameters");
        }

        if (submit_fn_info.Fn.params[0].type != Context) {
            @compileError("Context submit method first parameter should be of type: " ++ @typeName(Context));
        }

        if (submit_fn_info.Fn.params[1].type != c.VkCommandBuffer) {
            @compileError("Context submit method second parameter should be of type: " ++ @typeName(c.VkCommandBuffer));
        }
    }
    check_vk(c.vkResetFences(self.device, 1, &self.immidiate_fence)) catch @panic("Failed to reset immidiate fence");
    check_vk(c.vkResetCommandBuffer(self.immidiate_command_buffer, 0)) catch @panic("Failed to reset immidiate command buffer");
    const cmd = self.immidiate_command_buffer;

    const commmand_begin_ci = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    check_vk(c.vkBeginCommandBuffer(cmd, &commmand_begin_ci)) catch @panic("Failed to begin command buffer");

    submit_ctx.submit(cmd);

    check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info = std.mem.zeroInit(c.VkCommandBufferSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    });
    const submit_info = std.mem.zeroInit(c.VkSubmitInfo2, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
    });

    check_vk(c.vkQueueSubmit2(self.graphics_queue, 1, &submit_info, self.immidiate_fence)) catch @panic("Failed to submit to graphics queue");
    check_vk(c.vkWaitForFences(self.device, 1, &self.immidiate_fence, c.VK_TRUE, 1_000_000_000)) catch @panic("Failed to wait for immidiate fence");
}

fn create_buffer(self: *Self, alloc_size: usize, usage: c.VkBufferUsageFlags, memory_usage: c.VmaMemoryUsage) t.AllocatedBuffer {
    const buffer_info = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = alloc_size,
        .usage = usage,
    });

    const vma_alloc_info = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = memory_usage,
        .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    });

    var new_buffer: t.AllocatedBuffer = undefined;
    check_vk(c.vmaCreateBuffer(self.gpu_allocator, &buffer_info, &vma_alloc_info, &new_buffer.buffer, &new_buffer.allocation, &new_buffer.info)) catch @panic("Failed to create buffer");
    return new_buffer;
}

pub fn upload_mesh(self: *Self, indices: []u32, vertices: []t.Vertex) t.GPUMeshBuffers {
    const index_buffer_size = @sizeOf(u32) * indices.len;
    const vertex_buffer_size = @sizeOf(t.Vertex) * vertices.len;

    var new_surface: t.GPUMeshBuffers = undefined;
    new_surface.vertex_buffer = self.create_buffer(vertex_buffer_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, c.VMA_MEMORY_USAGE_GPU_ONLY);

    const device_address_info = std.mem.zeroInit(c.VkBufferDeviceAddressInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .buffer = new_surface.vertex_buffer.buffer,
    });

    new_surface.vertex_buffer_adress = c.vkGetBufferDeviceAddress(self.device, &device_address_info);
    new_surface.index_buffer = self.create_buffer(index_buffer_size, c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT, c.VMA_MEMORY_USAGE_GPU_ONLY);

    const staging = self.create_buffer(index_buffer_size + vertex_buffer_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VMA_MEMORY_USAGE_CPU_ONLY);
    defer c.vmaDestroyBuffer(self.gpu_allocator, staging.buffer, staging.allocation);

    const data: *anyopaque = staging.info.pMappedData.?;

    const byte_data = @as([*]u8, @ptrCast(data));
    @memcpy(byte_data[0..vertex_buffer_size], std.mem.sliceAsBytes(vertices));
    @memcpy(byte_data[vertex_buffer_size..], std.mem.sliceAsBytes(indices));
    const submit_ctx = struct {
        vertex_buffer: c.VkBuffer,
        index_buffer: c.VkBuffer,
        staging_buffer: c.VkBuffer,
        vertex_buffer_size: usize,
        index_buffer_size: usize,
        fn submit(sself: @This(), cmd: c.VkCommandBuffer) void {
            const vertex_copy_region = std.mem.zeroInit(c.VkBufferCopy, .{
                .srcOffset = 0,
                .dstOffset = 0,
                .size = sself.vertex_buffer_size,
            });

            const index_copy_region = std.mem.zeroInit(c.VkBufferCopy, .{
                .srcOffset = sself.vertex_buffer_size,
                .dstOffset = 0,
                .size = sself.index_buffer_size,
            });

            c.vkCmdCopyBuffer(cmd, sself.staging_buffer, sself.vertex_buffer, 1, &vertex_copy_region);
            c.vkCmdCopyBuffer(cmd, sself.staging_buffer, sself.index_buffer, 1, &index_copy_region);
        }
    }{
        .vertex_buffer = new_surface.vertex_buffer.buffer,
        .index_buffer = new_surface.index_buffer.buffer,
        .staging_buffer = staging.buffer,
        .vertex_buffer_size = vertex_buffer_size,
        .index_buffer_size = index_buffer_size,
    };
    self.immediate_submit(submit_ctx);
    return new_surface;
}

fn init_commands(self: *Self) void {
    const command_pool_ci = std.mem.zeroInit(c.VkCommandPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = self.graphics_queue_family,
    });

    for (&self.frames) |*frame| {
        check_vk(c.vkCreateCommandPool(self.device, &command_pool_ci, vk_alloc_cbs, &frame.command_pool)) catch log.err("Failed to create command pool", .{});

        const command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = frame.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        });

        check_vk(c.vkAllocateCommandBuffers(self.device, &command_buffer_ai, &frame.main_command_buffer)) catch @panic("Failed to allocate command buffer");

        log.info("Created command pool and command buffer", .{});
    }

    check_vk(c.vkCreateCommandPool(self.device, &command_pool_ci, vk_alloc_cbs, &self.immidiate_command_pool)) catch @panic("Failed to create upload command pool");

    const upload_command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.immidiate_command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    check_vk(c.vkAllocateCommandBuffers(self.device, &upload_command_buffer_ai, &self.immidiate_command_buffer)) catch @panic("Failed to allocate upload command buffer");
}

fn init_sync_structures(self: *Self) void {
    const semaphore_ci = std.mem.zeroInit(c.VkSemaphoreCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    });

    const fence_ci = std.mem.zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    });

    for (&self.frames) |*frame| {
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.swapchain_semaphore)) catch @panic("Failed to create present semaphore");
        check_vk(c.vkCreateSemaphore(self.device, &semaphore_ci, vk_alloc_cbs, &frame.render_semaphore)) catch @panic("Failed to create render semaphore");
        check_vk(c.vkCreateFence(self.device, &fence_ci, vk_alloc_cbs, &frame.render_fence)) catch @panic("Failed to create render fence");
    }

    const upload_fence_ci = std.mem.zeroInit(c.VkFenceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    });

    check_vk(c.vkCreateFence(self.device, &upload_fence_ci, vk_alloc_cbs, &self.immidiate_fence)) catch @panic("Failed to create upload fence");
    log.info("Created sync structures", .{});
}

// fn init_pipelines(self: *Self) void {
//     init_background_pipelines(self);
//     init_mesh_pipeline(self);
//     self.metalroughmaterial.build_pipelines(self);
// }
