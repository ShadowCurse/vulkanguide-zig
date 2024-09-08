const std = @import("std");
const sdl = @import("sdl.zig");
const vk = @import("vulkan.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

const WIDTH = 1280;
const HEIGHT = 720;
const VK_VALIDATION_LAYERS_NAMES = [_][]const u8{"VK_LAYER_KHRONOS_validation"};
const VK_ADDITIONAL_EXTENSIONS_NAMES = [_][]const u8{"VK_EXT_debug_utils"};
const VK_PHYSICAL_DEVICE_EXTENSION_NAMES = [_][]const u8{"VK_KHR_swapchain"};

const PhysicalDevice = struct {
    device: vk.VkPhysicalDevice,
    graphics_queue_family: u32,
    present_queue_family: u32,
    compute_queue_family: u32,
    transfer_queue_family: u32,
};

const LogicalDevice = struct {
    device: vk.VkDevice,
    graphics_queue: vk.VkQueue,
    present_queue: vk.VkQueue,
    compute_queue: vk.VkQueue,
    transfer_queue: vk.VkQueue,
};

allocator: Allocator,
window: *sdl.SDL_Window,
surface: vk.VkSurfaceKHR = undefined,
vk_instance: vk.VkInstance = undefined,
vk_debug_messanger: vk.VkDebugUtilsMessengerEXT = undefined,
vk_physical_device: PhysicalDevice = undefined,
vk_logical_device: LogicalDevice = undefined,

pub fn init(allocator: Allocator) !Self {
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        return error.SDLInit;
    }
    const window = sdl.SDL_CreateWindow(
        "VulkanGuide",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        WIDTH,
        HEIGHT,
        sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE,
    ) orelse {
        return error.SDLCreateWindow;
    };
    sdl.SDL_ShowWindow(window);

    var sdl_extension_count: u32 = undefined;
    if (sdl.SDL_Vulkan_GetInstanceExtensions(window, &sdl_extension_count, null) != 1) {
        return error.SDLGetExtensions;
    }
    const sdl_extensions = try allocator.alloc([*c]const u8, sdl_extension_count);
    defer allocator.free(sdl_extensions);
    if (sdl.SDL_Vulkan_GetInstanceExtensions(window, &sdl_extension_count, sdl_extensions.ptr) != 1) {
        return error.SDLGetExtensions;
    }
    for (sdl_extensions) |e| {
        std.log.info("Required SDL extension: {s}", .{e});
    }

    var self = Self{
        .allocator = allocator,
        .window = window,
    };

    try self.create_vk_instance(sdl_extensions);
    try self.create_debug_messanger();

    // Casts are needed because SDL and vulkan imports same type,
    // but compiler sees them as different types.
    if (sdl.SDL_Vulkan_CreateSurface(self.window, @ptrCast(self.vk_instance), @ptrCast(&self.surface)) != 1) {
        return error.SDLCreateSurface;
    }

    try self.select_physical_device();
    try self.create_logical_device();

    return self;
}

pub fn deinit(self: *Self) void {
    vk.vkDestroyDevice(self.vk_logical_device.device, null);
    vk.vkDestroySurfaceKHR(self.vk_instance, self.surface, null);
    self.destroy_debug_messanger() catch {
        std.log.err("Could not destroy debug messanger", .{});
    };
    vk.vkDestroyInstance(self.vk_instance, null);
    sdl.SDL_DestroyWindow(self.window);
}

pub fn run(self: *Self) void {
    var stop = false;
    while (!stop) {
        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event) != 0) {
            if (sdl_event.type == sdl.SDL_QUIT) {
                stop = true;
                break;
            }
        }
    }
    _ = self;
}

pub fn create_vk_instance(self: *Self, sdl_extensions: [][*c]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var extensions_count: u32 = 0;
    try vk.check_result(vk.vkEnumerateInstanceExtensionProperties(null, &extensions_count, null));
    const extensions = try arena_allocator.alloc(vk.VkExtensionProperties, extensions_count);
    try vk.check_result(vk.vkEnumerateInstanceExtensionProperties(null, &extensions_count, extensions.ptr));
    var found_sdl_extensions: u32 = 0;
    var found_additional_extensions: u32 = 0;
    for (extensions) |e| {
        var required = "--------";
        for (sdl_extensions) |se| {
            const sdl_name_span = std.mem.span(se);
            const extension_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&e.extensionName)));
            if (std.mem.eql(u8, extension_name_span, sdl_name_span)) {
                found_sdl_extensions += 1;
                required = "required";
            }
        }
        for (VK_ADDITIONAL_EXTENSIONS_NAMES) |ae| {
            const extension_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&e.extensionName)));
            if (std.mem.eql(u8, extension_name_span, ae)) {
                found_additional_extensions += 1;
                required = "required";
            }
        }
        std.log.info("({s}) Extension name: {s} version: {}", .{ required, e.extensionName, e.specVersion });
    }
    if (found_sdl_extensions != sdl_extensions.len) {
        return error.SDLExtensionsNotFound;
    }
    if (found_additional_extensions != VK_ADDITIONAL_EXTENSIONS_NAMES.len) {
        return error.AdditionalExtensionsNotFound;
    }
    var total_extensions = try std.ArrayListUnmanaged([*c]const u8).initCapacity(
        arena_allocator,
        sdl_extensions.len + VK_ADDITIONAL_EXTENSIONS_NAMES.len,
    );
    for (sdl_extensions) |e| {
        try total_extensions.append(arena_allocator, e);
    }
    for (VK_ADDITIONAL_EXTENSIONS_NAMES) |e| {
        try total_extensions.append(arena_allocator, e.ptr);
    }

    var layer_property_count: u32 = 0;
    try vk.check_result(vk.vkEnumerateInstanceLayerProperties(&layer_property_count, null));
    const layers = try arena_allocator.alloc(vk.VkLayerProperties, layer_property_count);
    try vk.check_result(vk.vkEnumerateInstanceLayerProperties(&layer_property_count, layers.ptr));
    var found_validation_layers: u32 = 0;
    for (layers) |l| {
        var required = "--------";
        for (VK_VALIDATION_LAYERS_NAMES) |vln| {
            const layer_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&l.layerName)));
            if (std.mem.eql(u8, layer_name_span, vln)) {
                found_validation_layers += 1;
                required = "required";
            }
        }
        std.log.info("({s}) Layer name: {s}, spec version: {}, description: {s}", .{ required, l.layerName, l.specVersion, l.description });
    }
    if (found_validation_layers != VK_VALIDATION_LAYERS_NAMES.len) {
        return error.ValidationLayersNotFound;
    }

    const app_info = vk.VkApplicationInfo{
        .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "vulkanguide-zig",
        .applicationVersion = vk.VK_MAKE_VERSION(0, 0, 1),
        .pEngineName = "no_engine",
        .engineVersion = vk.VK_MAKE_VERSION(0, 0, 1),
        .apiVersion = vk.VK_API_VERSION_1_3,
        .pNext = null,
    };
    const instance_create_info = vk.VkInstanceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .ppEnabledExtensionNames = total_extensions.items.ptr,
        .enabledExtensionCount = @as(u32, @intCast(total_extensions.items.len)),
        .ppEnabledLayerNames = @ptrCast(&VK_VALIDATION_LAYERS_NAMES),
        .enabledLayerCount = @as(u32, @intCast(VK_VALIDATION_LAYERS_NAMES.len)),
    };

    try vk.check_result(vk.vkCreateInstance(&instance_create_info, null, &self.vk_instance));
}

pub fn get_vk_func(comptime Fn: type, instance: vk.VkInstance, name: [*c]const u8) !Fn {
    if (sdl.SDL_Vulkan_GetVkGetInstanceProcAddr()) |f| {
        const get_proc_addr = @as(vk.PFN_vkGetInstanceProcAddr, @ptrCast(f)).?;
        if (get_proc_addr(instance, name)) |func| {
            return @ptrCast(func);
        } else {
            return error.VKGetInstanceProcAddr;
        }
    } else {
        std.log.err("Cound not create debug messanger", .{});
        return error.SDLGetInstanceProcAddr;
    }
}

pub fn create_debug_messanger(self: *Self) !void {
    const create_fn = (try get_vk_func(vk.PFN_vkCreateDebugUtilsMessengerEXT, self.vk_instance, "vkCreateDebugUtilsMessengerEXT")).?;
    const create_info = vk.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
        .messageType = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = debug_callback,
        .pUserData = null,
    };
    try vk.check_result(create_fn(self.vk_instance, &create_info, null, &self.vk_debug_messanger));
}

pub fn destroy_debug_messanger(self: *Self) !void {
    const destroy_fn = (try get_vk_func(vk.PFN_vkDestroyDebugUtilsMessengerEXT, self.vk_instance, "vkDestroyDebugUtilsMessengerEXT")).?;
    destroy_fn(self.vk_instance, self.vk_debug_messanger, null);
}

pub fn debug_callback(
    severity: vk.VkDebugUtilsMessageSeverityFlagBitsEXT,
    msg_type: vk.VkDebugUtilsMessageTypeFlagsEXT,
    data: ?*const vk.VkDebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.C) vk.VkBool32 {
    const sev = switch (severity) {
        vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => "error",
        vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => "warning",
        vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT => "verbose",
        else => "unknown",
    };
    const ty = switch (msg_type) {
        vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT => "general",
        vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT => "validation",
        vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT => "performance",
        else => "unknown",
    };
    const msg: [*c]const u8 = if (data) |d| d.pMessage else "empty";

    std.log.debug("[DEBUG MSG][{s}][{s}]: {s}", .{ sev, ty, msg });
    return vk.VK_FALSE;
}

pub fn select_physical_device(self: *Self) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var physical_device_count: u32 = 0;
    try vk.check_result(vk.vkEnumeratePhysicalDevices(self.vk_instance, &physical_device_count, null));
    const physical_devices = try arena_allocator.alloc(vk.VkPhysicalDevice, physical_device_count);
    try vk.check_result(vk.vkEnumeratePhysicalDevices(self.vk_instance, &physical_device_count, physical_devices.ptr));

    for (physical_devices) |pd| {
        var properties: vk.VkPhysicalDeviceProperties = undefined;
        var features: vk.VkPhysicalDeviceFeatures = undefined;
        vk.vkGetPhysicalDeviceProperties(pd, &properties);
        vk.vkGetPhysicalDeviceFeatures(pd, &features);

        std.log.info("Physical device: {s}", .{properties.deviceName});

        var extensions_count: u32 = 0;
        try vk.check_result(vk.vkEnumerateDeviceExtensionProperties(pd, null, &extensions_count, null));
        const extensions = try arena_allocator.alloc(vk.VkExtensionProperties, extensions_count);
        try vk.check_result(vk.vkEnumerateDeviceExtensionProperties(pd, null, &extensions_count, extensions.ptr));

        var found_extensions: u32 = 0;
        for (extensions) |e| {
            var required = "--------";
            for (VK_PHYSICAL_DEVICE_EXTENSION_NAMES) |re| {
                const extension_name_span = std.mem.span(@as([*c]const u8, @ptrCast(&e.extensionName)));
                if (std.mem.eql(u8, extension_name_span, re)) {
                    found_extensions += 1;
                    required = "required";
                }
            }
            std.log.info("({s}) extension name: {s}", .{ required, e.extensionName });
        }
        if (found_extensions != VK_PHYSICAL_DEVICE_EXTENSION_NAMES.len) {
            continue;
        }

        var queue_family_count: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(pd, &queue_family_count, null);
        const queue_families = try arena_allocator.alloc(vk.VkQueueFamilyProperties, queue_family_count);
        vk.vkGetPhysicalDeviceQueueFamilyProperties(pd, &queue_family_count, queue_families.ptr);

        var graphics_queue_family: ?u32 = null;
        var present_queue_family: ?u32 = null;
        var compute_queue_family: ?u32 = null;
        var transfer_queue_family: ?u32 = null;

        for (queue_families, 0..) |qf, i| {
            if (graphics_queue_family == null and qf.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                graphics_queue_family = @intCast(i);
            }
            if (compute_queue_family == null and qf.queueFlags & vk.VK_QUEUE_COMPUTE_BIT != 0) {
                compute_queue_family = @intCast(i);
            }
            if (transfer_queue_family == null and qf.queueFlags & vk.VK_QUEUE_TRANSFER_BIT != 0) {
                transfer_queue_family = @intCast(i);
            }
            if (present_queue_family == null) {
                var supported: vk.VkBool32 = 0;
                try vk.check_result(vk.vkGetPhysicalDeviceSurfaceSupportKHR(pd, @intCast(i), self.surface, &supported));
                if (supported == vk.VK_TRUE) {
                    present_queue_family = @intCast(i);
                }
            }
        }

        if (graphics_queue_family != null and
            present_queue_family != null and
            compute_queue_family != null and
            transfer_queue_family != null)
        {
            std.log.info("Selected graphics queue family: {}", .{graphics_queue_family.?});
            std.log.info("Selected present queue family: {}", .{present_queue_family.?});
            std.log.info("Selected compute queue family: {}", .{compute_queue_family.?});
            std.log.info("Selected transfer queue family: {}", .{transfer_queue_family.?});

            self.vk_physical_device = .{
                .device = pd,
                .graphics_queue_family = graphics_queue_family.?,
                .present_queue_family = present_queue_family.?,
                .compute_queue_family = compute_queue_family.?,
                .transfer_queue_family = transfer_queue_family.?,
            };
            break;
        }
    }
}

pub fn create_logical_device(self: *Self) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const all_queue_family_indexes: [4]u32 = .{
        self.vk_physical_device.graphics_queue_family,
        self.vk_physical_device.present_queue_family,
        self.vk_physical_device.compute_queue_family,
        self.vk_physical_device.transfer_queue_family,
    };
    var i: usize = 0;
    var unique_indexes: [4]u32 = .{ std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32) };
    for (all_queue_family_indexes) |qfi| {
        if (std.mem.count(u32, &unique_indexes, &.{qfi}) == 0) {
            unique_indexes[i] = qfi;
            i += 1;
        }
    }
    const unique = std.mem.sliceTo(&unique_indexes, std.math.maxInt(u32));
    const queue_create_infos = try arena_allocator.alloc(vk.VkDeviceQueueCreateInfo, unique.len);

    const queue_priority: f32 = 1.0;
    for (queue_create_infos, unique) |*qi, u| {
        qi.* = vk.VkDeviceQueueCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = u,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
    }

    var physical_device_features_1_3 = vk.VkPhysicalDeviceVulkan13Features{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .dynamicRendering = vk.VK_TRUE,
        .synchronization2 = vk.VK_TRUE,
    };
    const physical_device_features_1_2 = vk.VkPhysicalDeviceVulkan12Features{
        .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .bufferDeviceAddress = vk.VK_TRUE,
        .descriptorIndexing = vk.VK_TRUE,
        .pNext = @ptrCast(&physical_device_features_1_3),
    };
    const physical_device_features = vk.VkPhysicalDeviceFeatures{};

    const create_info = vk.VkDeviceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = @as(u32, @intCast(queue_create_infos.len)),
        .pQueueCreateInfos = queue_create_infos.ptr,
        .ppEnabledLayerNames = null,
        .enabledLayerCount = 0,
        .ppEnabledExtensionNames = @ptrCast(&VK_PHYSICAL_DEVICE_EXTENSION_NAMES),
        .enabledExtensionCount = @as(u32, @intCast(VK_PHYSICAL_DEVICE_EXTENSION_NAMES.len)),
        .pEnabledFeatures = &physical_device_features,
        .pNext = &physical_device_features_1_2,
    };

    try vk.check_result(vk.vkCreateDevice(
        self.vk_physical_device.device,
        &create_info,
        null,
        &self.vk_logical_device.device,
    ));
    vk.vkGetDeviceQueue(
        self.vk_logical_device.device,
        self.vk_physical_device.present_queue_family,
        0,
        &self.vk_logical_device.present_queue,
    );
    vk.vkGetDeviceQueue(
        self.vk_logical_device.device,
        self.vk_physical_device.graphics_queue_family,
        0,
        &self.vk_logical_device.graphics_queue,
    );
    vk.vkGetDeviceQueue(
        self.vk_logical_device.device,
        self.vk_physical_device.compute_queue_family,
        0,
        &self.vk_logical_device.compute_queue,
    );
    vk.vkGetDeviceQueue(
        self.vk_logical_device.device,
        self.vk_physical_device.transfer_queue_family,
        0,
        &self.vk_logical_device.transfer_queue,
    );
}
