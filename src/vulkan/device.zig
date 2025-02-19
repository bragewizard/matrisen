const c = @import("../clibs.zig");
const std = @import("std");
const check_vk = @import("debug.zig").check_vk;
const check_vk_panic = @import("debug.zig").check_vk_panic;
const log = std.log.scoped(.device);
const config = @import("config");
const SwapchainSupportInfo = @import("swapchain.zig").SupportInfo;
const vk_alloc_cbs = @import("core.zig").vk_alloc_cbs;
const api_version = @import("instance.zig").api_version;
const required_device_extensions: []const [*c]const u8 = &.{
    "VK_KHR_swapchain",
    "VK_EXT_mesh_shader"
};

const PhysicalDeviceSelectionCriteria = enum {
    First,
    PreferDiscrete,
    PreferIntegrated,
};

pub const PhysicalDevice = struct {
    handle: c.VkPhysicalDevice = null,
    properties: c.VkPhysicalDeviceProperties = undefined,
    graphics_queue_family: u32 = undefined,
    present_queue_family: u32 = undefined,
    compute_queue_family: u32 = undefined,
    transfer_queue_family: u32 = undefined,

    const INVALID_QUEUE_FAMILY_INDEX = std.math.maxInt(u32);

    pub fn select(alloc: std.mem.Allocator, instance: c.VkInstance, surface: ?c.VkSurfaceKHR) PhysicalDevice {
        const criteria = PhysicalDeviceSelectionCriteria.PreferDiscrete;
        var physical_device_count: u32 = undefined;
        check_vk_panic(c.vkEnumeratePhysicalDevices(instance, &physical_device_count, null));

        const physical_devices = alloc.alloc(c.VkPhysicalDevice, physical_device_count) catch { log.err("failed to alloc", .{}); @panic(""); };
        check_vk_panic(c.vkEnumeratePhysicalDevices(instance, &physical_device_count, physical_devices.ptr));

        var suitable_pd: ?PhysicalDevice = null;

        for (physical_devices) |device| {
            const pd = make_physical_device(alloc, device, surface) catch continue;
            _ = is_physical_device_suitable(alloc, pd, surface) catch continue;
            switch (criteria) {
                PhysicalDeviceSelectionCriteria.First => {
                    suitable_pd = pd;
                    break;
                },
                PhysicalDeviceSelectionCriteria.PreferDiscrete => {
                    if (pd.properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                        suitable_pd = pd;
                        break;
                    } else if (suitable_pd == null) {
                        suitable_pd = pd;
                    }
                },
                PhysicalDeviceSelectionCriteria.PreferIntegrated => {
                    if (pd.properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
                        suitable_pd = pd;
                        break;
                    } else if (suitable_pd == null) {
                        suitable_pd = pd;
                    }
                },
            }
        }

        if (suitable_pd == null) {
            log.err("No suitable physical device found.", .{});
            @panic("");
        }
        const res = suitable_pd.?;

        const device_name = @as([*:0]const u8, @ptrCast(@alignCast(res.properties.deviceName[0..])));
        log.info("Selected physical device: {s}", .{device_name});

        return res;
    }

    fn make_physical_device(a: std.mem.Allocator, device: c.VkPhysicalDevice, surface: ?c.VkSurfaceKHR) !PhysicalDevice {
        var props = std.mem.zeroInit(c.VkPhysicalDeviceProperties, .{});
        c.vkGetPhysicalDeviceProperties(device, &props);

        var graphics_queue_family: u32 = PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX;
        var present_queue_family: u32 = PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX;
        var compute_queue_family: u32 = PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX;
        var transfer_queue_family: u32 = PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX;

        var queue_family_count: u32 = undefined;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);
        const queue_families = a.alloc(c.VkQueueFamilyProperties, queue_family_count) catch { log.err("failed to alloc", .{}); @panic(""); };
        defer a.free(queue_families);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

        for (queue_families, 0..) |queue_family, i| {
            const index: u32 = @intCast(i);

            if (graphics_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0)
            {
                graphics_queue_family = index;
            }

            if (surface) |surf| {
                if (present_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX) {
                    var present_support: c.VkBool32 = undefined;
                    check_vk_panic(c.vkGetPhysicalDeviceSurfaceSupportKHR(device, index, surf, &present_support));
                    if (present_support == c.VK_TRUE) {
                        present_queue_family = index;
                    }
                }
            }

            if (compute_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0)
            {
                compute_queue_family = index;
            }

            if (transfer_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT != 0)
            {
                transfer_queue_family = index;
            }

            if (graphics_queue_family != PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                present_queue_family != PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                compute_queue_family != PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX and
                transfer_queue_family != PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX)
            {
                break;
            }
        }

        return .{
            .handle = device,
            .properties = props,
            .graphics_queue_family = graphics_queue_family,
            .present_queue_family = present_queue_family,
            .compute_queue_family = compute_queue_family,
            .transfer_queue_family = transfer_queue_family,
        };
    }

    fn is_physical_device_suitable(alloc: std.mem.Allocator, device: PhysicalDevice, surface: ?c.VkSurfaceKHR) !bool {
        if (device.properties.apiVersion < api_version) {
            return false;
        }

        if (device.graphics_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX or
            device.present_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX or
            device.compute_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX or
            device.transfer_queue_family == PhysicalDevice.INVALID_QUEUE_FAMILY_INDEX)
        {
            return false;
        }

        if (surface) |surf| {
            const swapchain_support = SwapchainSupportInfo.init(alloc, device.handle, surf);
            defer swapchain_support.deinit(alloc);
            if (swapchain_support.formats.len == 0 or swapchain_support.present_modes.len == 0) {
                return false;
            }
        }

        if (required_device_extensions.len > 0) {
            var device_extension_count: u32 = undefined;
            check_vk_panic(c.vkEnumerateDeviceExtensionProperties(device.handle, null, &device_extension_count, null));
            const device_extensions = alloc.alloc(c.VkExtensionProperties, device_extension_count) catch { log.err("failed to alloc", .{}); @panic(""); };
            check_vk_panic(c.vkEnumerateDeviceExtensionProperties(device.handle, null, &device_extension_count, device_extensions.ptr));

            _ = blk: for (required_device_extensions) |req_ext| {
                for (device_extensions) |device_ext| {
                    const device_ext_name: [*c]const u8 = @ptrCast(device_ext.extensionName[0..]);
                    if (std.mem.eql(u8, std.mem.span(req_ext), std.mem.span(device_ext_name))) {
                        break :blk true;
                    }
                }
            } else return false;
        }

        return true;
    }
};

pub const Device = struct {
    handle: c.VkDevice = null,
    graphics_queue: c.VkQueue = null,
    present_queue: c.VkQueue = null,
    compute_queue: c.VkQueue = null,
    transfer_queue: c.VkQueue = null,

    pub fn create(alloc: std.mem.Allocator, physical_device: PhysicalDevice) Device {
        const alloc_cb: ?*c.VkAllocationCallbacks = null;

        var features13 = std.mem.zeroInit(c.VkPhysicalDeviceVulkan13Features, .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            .dynamicRendering = c.VK_TRUE,
            .synchronization2 = c.VK_TRUE,
        });

        var features12 = std.mem.zeroInit(c.VkPhysicalDeviceVulkan12Features, .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            .bufferDeviceAddress = c.VK_TRUE,
            .descriptorIndexing = c.VK_TRUE,
            .pNext = &features13,
        });

        var shader_draw_parameters_features = std.mem.zeroInit(c.VkPhysicalDeviceShaderDrawParametersFeatures, .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES,
            .shaderDrawParameters = c.VK_TRUE,
            .pNext = &features12,
        });

        var deviceFeatures2 = std.mem.zeroInit(c.VkPhysicalDeviceFeatures2, .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
            .pNext = &shader_draw_parameters_features,
        });

        const meshshading = c.VkPhysicalDeviceMeshShaderFeaturesEXT {
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT,
            .pNext = &deviceFeatures2,
            .taskShader = c.VK_TRUE,
            .meshShader = c.VK_TRUE,
        };

        var queue_create_infos = std.ArrayListUnmanaged(c.VkDeviceQueueCreateInfo){};
        const queue_priorities: f32 = 1.0;
        var queue_family_set = std.AutoArrayHashMapUnmanaged(u32, void){};
        queue_family_set.put(alloc, physical_device.graphics_queue_family, {}) catch { log.err("failed to alloc", .{}); @panic(""); };
        queue_family_set.put(alloc, physical_device.present_queue_family, {}) catch { log.err("failed to alloc", .{}); @panic(""); };
        queue_family_set.put(alloc, physical_device.compute_queue_family, {}) catch { log.err("failed to alloc", .{}); @panic(""); };
        queue_family_set.put(alloc, physical_device.transfer_queue_family, {}) catch { log.err("failed to alloc", .{}); @panic(""); };
        var qfi_iter = queue_family_set.iterator();
        queue_create_infos.ensureTotalCapacity(alloc, queue_family_set.count()) catch { log.err("failed to alloc", .{}); @panic(""); };
        while (qfi_iter.next()) |qfi| {
            queue_create_infos.append(alloc, std.mem.zeroInit(c.VkDeviceQueueCreateInfo, .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = qfi.key_ptr.*,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            })) catch { log.err("failed to append", .{}); @panic(""); };
        }

        const device_info = std.mem.zeroInit(c.VkDeviceCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = &meshshading,
            .queueCreateInfoCount = @as(u32, @intCast(queue_create_infos.items.len)),
            .pQueueCreateInfos = queue_create_infos.items.ptr,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = @as(u32, @intCast(required_device_extensions.len)),
            .ppEnabledExtensionNames = required_device_extensions.ptr,
            .pEnabledFeatures = null,
        });

        var device: c.VkDevice = undefined;
        check_vk_panic(c.vkCreateDevice(physical_device.handle, &device_info, alloc_cb, &device));

        var graphics_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, physical_device.graphics_queue_family, 0, &graphics_queue);
        var present_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, physical_device.present_queue_family, 0, &present_queue);
        var compute_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, physical_device.compute_queue_family, 0, &compute_queue);
        var transfer_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, physical_device.transfer_queue_family, 0, &transfer_queue);

        return .{
            .handle = device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .compute_queue = compute_queue,
            .transfer_queue = transfer_queue,
        };
    }
};
