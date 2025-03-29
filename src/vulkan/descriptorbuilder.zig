const std = @import("std");
const c = @import("clibs");
const debug = @import("debug.zig");
const check_vk = debug.check_vk;
const check_vk_panic = debug.check_vk_panic;
const buffers = @import("buffers.zig");
const geometry = @import("geometry");
const images = @import("images.zig");
const Core = @import("core.zig");
const FrameContext = @import("commands.zig").FrameContexts.Context;

pub const LayoutBuilder = struct {
    bindings: std.ArrayList(c.VkDescriptorSetLayoutBinding) = undefined,

    pub fn init(alloc: std.mem.Allocator) LayoutBuilder {
        return .{ .bindings = .init(alloc) };
    }

    pub fn deinit(self: *LayoutBuilder) void {
        self.bindings.deinit();
    }

    pub fn add_binding(self: *LayoutBuilder, binding: u32, descriptor_type: c.VkDescriptorType) void {
        const new_binding: c.VkDescriptorSetLayoutBinding = .{
            .binding = binding,
            .descriptorType = descriptor_type,
            .descriptorCount = 1,
        };
        self.bindings.append(new_binding) catch @panic("Failed to append to bindings");
    }

    pub fn clear(self: *LayoutBuilder) void {
        self.bindings.clearAndFree();
    }

    pub fn build(
        self: *LayoutBuilder,
        device: c.VkDevice,
        shader_stages: c.VkShaderStageFlags,
        pnext: ?*anyopaque,
        flags: c.VkDescriptorSetLayoutCreateFlags,
    ) c.VkDescriptorSetLayout {
        for (self.bindings.items) |*binding| {
            binding.stageFlags |= shader_stages;
        }

        const info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = @as(u32, @intCast(self.bindings.items.len)),
            .pBindings = self.bindings.items.ptr,
            .flags = flags,
            .pNext = pnext,
        };
        var layout: c.VkDescriptorSetLayout = undefined;
        check_vk(c.vkCreateDescriptorSetLayout(device, &info, null, &layout)) catch {
            @panic("Failed to create descriptor set layout");
        };
        return layout;
    }
};

pub const Allocator = struct {
    pub const PoolSizeRatio = struct {
        ratio: f32,
        type: c.VkDescriptorType,
    };

    ready_pools: std.ArrayList(c.VkDescriptorPool) = undefined,
    full_pools: std.ArrayList(c.VkDescriptorPool) = undefined,
    ratios: std.ArrayList(PoolSizeRatio) = undefined,
    sets_per_pool: u32 = 0,

    pub fn init(
        self: *@This(),
        device: c.VkDevice,
        initial_sets: u32,
        pool_ratios: []PoolSizeRatio,
        alloc: std.mem.Allocator,
    ) void {
        self.ratios = .init(alloc);
        self.ratios.clearAndFree();
        self.ready_pools = .init(alloc);
        self.full_pools = .init(alloc);

        self.ratios.appendSlice(pool_ratios) catch @panic("Failed to append to ratios");
        const new_pool = create_pool(device, initial_sets, pool_ratios, std.heap.page_allocator);
        self.sets_per_pool = @intFromFloat(@as(f32, @floatFromInt(initial_sets)) * 1.5);
        self.ready_pools.append(new_pool) catch @panic("Failed to append to ready_pools");
    }

    pub fn deinit(self: *@This(), device: c.VkDevice) void {
        self.clear_pools(device);
        self.destroy_pools(device);
        self.ready_pools.deinit();
        self.full_pools.deinit();
        self.ratios.deinit();
    }

    pub fn clear_pools(self: *@This(), device: c.VkDevice) void {
        for (self.ready_pools.items) |pool| {
            _ = c.vkResetDescriptorPool(device, pool, 0);
        }
        for (self.full_pools.items) |pool| {
            _ = c.vkResetDescriptorPool(device, pool, 0);
        }
        self.full_pools.clearAndFree();
    }

    pub fn destroy_pools(self: *@This(), device: c.VkDevice) void {
        for (self.ready_pools.items) |pool| {
            _ = c.vkDestroyDescriptorPool(device, pool, null);
        }
        self.ready_pools.clearAndFree();
        for (self.full_pools.items) |pool| {
            _ = c.vkDestroyDescriptorPool(device, pool, null);
        }
        self.full_pools.clearAndFree();
    }

    pub fn allocate(self: *@This(), device: c.VkDevice, layout: c.VkDescriptorSetLayout, pNext: ?*anyopaque) c.VkDescriptorSet {
        var pool_to_use = self.get_pool(device);

        var info = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = pNext,
            .descriptorPool = pool_to_use,
            .descriptorSetCount = 1,
            .pSetLayouts = &layout,
        };
        var descriptor_set: c.VkDescriptorSet = undefined;
        const result = c.vkAllocateDescriptorSets(device, &info, &descriptor_set);
        if (result == c.VK_ERROR_OUT_OF_POOL_MEMORY or result == c.VK_ERROR_FRAGMENTED_POOL) {
            self.full_pools.append(pool_to_use) catch @panic("Failed to append to full_pools");
            pool_to_use = self.get_pool(device);
            info.descriptorPool = pool_to_use;
            check_vk(c.vkAllocateDescriptorSets(device, &info, &descriptor_set)) catch {
                @panic("Failed to allocate descriptor set");
            };
        }
        self.ready_pools.append(pool_to_use) catch @panic("Failed to append to full_pools");
        return descriptor_set;
    }

    fn get_pool(self: *@This(), device: c.VkDevice) c.VkDescriptorPool {
        var new_pool: c.VkDescriptorPool = undefined;
        if (self.ready_pools.items.len != 0) {
            new_pool = self.ready_pools.pop().?;
        } else {
            new_pool = create_pool(device, self.sets_per_pool, self.ratios.items, std.heap.page_allocator);
            self.sets_per_pool = @intFromFloat(@as(f32, @floatFromInt(self.sets_per_pool)) * 1.5);
            if (self.sets_per_pool > 4092) {
                self.sets_per_pool = 4092;
            }
        }
        return new_pool;
    }

    fn create_pool(
        device: c.VkDevice,
        set_count: u32,
        pool_ratios: []PoolSizeRatio,
        alloc: std.mem.Allocator,
    ) c.VkDescriptorPool {
        var pool_sizes: std.ArrayList(c.VkDescriptorPoolSize) = .init(alloc);
        defer pool_sizes.deinit();
        for (pool_ratios) |ratio| {
            const size = c.VkDescriptorPoolSize{
                .type = ratio.type,
                .descriptorCount = set_count * @as(u32, @intFromFloat(ratio.ratio)),
            };
            pool_sizes.append(size) catch @panic("Failed to append to pool_sizes");
        }

        const info = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags = 0,
            .maxSets = set_count,
            .poolSizeCount = @as(u32, @intCast(pool_sizes.items.len)),
            .pPoolSizes = pool_sizes.items.ptr,
        };

        var pool: c.VkDescriptorPool = undefined;
        check_vk(c.vkCreateDescriptorPool(device, &info, null, &pool)) catch @panic("Failed to create descriptor pool");
        return pool;
    }
};

// TODO dont know if i like this writer and its arraylists, need to allocate memory every time
pub const Writer = struct {
    writes: std.ArrayList(c.VkWriteDescriptorSet) = undefined,
    buffer_infos: std.ArrayList(c.VkDescriptorBufferInfo) = undefined,
    image_infos: std.ArrayList(c.VkDescriptorImageInfo) = undefined,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .writes = .init(allocator),
            .buffer_infos = .init(allocator),
            .image_infos = .init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.writes.deinit();
        self.buffer_infos.deinit();
        self.image_infos.deinit();
    }

    pub fn write_buffer(
        self: *@This(),
        binding: u32,
        buffer: c.VkBuffer,
        size: usize,
        offset: usize,
        ty: c.VkDescriptorType,
    ) void {
        const info_container = struct {
            var info: c.VkDescriptorBufferInfo = c.VkDescriptorBufferInfo{};
        };
        info_container.info = c.VkDescriptorBufferInfo{ .buffer = buffer, .offset = offset, .range = size };
        self.buffer_infos.append(info_container.info) catch @panic("failed to append");
        const write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = binding,
            .dstSet = null,
            .descriptorCount = 1,
            .descriptorType = ty,
            .pBufferInfo = &info_container.info,
        };
        self.writes.append(write) catch @panic("failed to append");
    }

    pub fn write_image(
        self: *@This(),
        binding: u32,
        image: c.VkImageView,
        sampler: c.VkSampler,
        layout: c.VkImageLayout,
        ty: c.VkDescriptorType,
    ) void {
        const info_container = struct {
            var info: c.VkDescriptorImageInfo = c.VkDescriptorImageInfo{};
        };
        info_container.info = c.VkDescriptorImageInfo{ .sampler = sampler, .imageView = image, .imageLayout = layout };

        self.image_infos.append(info_container.info) catch @panic("append failed");
        const write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = binding,
            .dstSet = null,
            .descriptorCount = 1,
            .descriptorType = ty,
            .pImageInfo = &info_container.info,
        };
        self.writes.append(write) catch @panic("append failed");
    }

    pub fn clear(self: *@This()) void {
        self.writes.clearAndFree();
        self.buffer_infos.clearAndFree();
        self.image_infos.clearAndFree();
    }

    pub fn update_set(self: *@This(), device: c.VkDevice, set: c.VkDescriptorSet) void {
        for (self.writes.items) |*write| {
            write.*.dstSet = set;
        }
        c.vkUpdateDescriptorSets(device, @intCast(self.writes.items.len), self.writes.items.ptr, 0, null);
    }
};

pub fn init(core: *Core) void {
    _ = core;
}

pub fn deinit(core: *Core) void {
    _ = core;
}
