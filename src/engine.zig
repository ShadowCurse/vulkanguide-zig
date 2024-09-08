const std = @import("std");
const sdl = @import("sdl.zig");
const vk = @import("vulkan.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

const WIDTH = 1280;
const HEIGHT = 720;
const VK_VALIDATION_LAYERS_NAMES = [_][]const u8{"VK_LAYER_KHRONOS_validation"};
const VK_ADDITIONAL_EXTENSIONS_NAMES = [_][]const u8{"VK_EXT_debug_utils"};

window: *sdl.SDL_Window,
vk_instance: vk.VkInstance,
vk_debug_messanger: vk.VkDebugUtilsMessengerEXT,

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

    const vk_instance = try Self.create_vk_instance(allocator, sdl_extensions);
    const vk_debug_messanger = try Self.create_debug_messanger(vk_instance);

    return .{
        .window = window,
        .vk_instance = vk_instance,
        .vk_debug_messanger = vk_debug_messanger,
    };
}

pub fn deinit(self: *Self) void {
    Self.destroy_debug_messanger(self.vk_instance, self.vk_debug_messanger) catch {
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

pub fn create_vk_instance(allocator: Allocator, sdl_extensions: [][*c]const u8) !vk.VkInstance {
    var arena = std.heap.ArenaAllocator.init(allocator);
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

    var instance: vk.VkInstance = undefined;
    try vk.check_result(vk.vkCreateInstance(&instance_create_info, null, &instance));
    return instance;
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

pub fn create_debug_messanger(instance: vk.VkInstance) !vk.VkDebugUtilsMessengerEXT {
    const create_fn = (try Self.get_vk_func(vk.PFN_vkCreateDebugUtilsMessengerEXT, instance, "vkCreateDebugUtilsMessengerEXT")).?;
    const create_info = vk.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
        .messageType = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = Self.debug_callback,
        .pUserData = null,
    };
    var messanger: vk.VkDebugUtilsMessengerEXT = undefined;
    try vk.check_result(create_fn(instance, &create_info, null, &messanger));
    return messanger;
}

pub fn destroy_debug_messanger(instance: vk.VkInstance, messanger: vk.VkDebugUtilsMessengerEXT) !void {
    const destroy_fn = (try Self.get_vk_func(vk.PFN_vkDestroyDebugUtilsMessengerEXT, instance, "vkDestroyDebugUtilsMessengerEXT")).?;
    destroy_fn(instance, messanger, null);
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
