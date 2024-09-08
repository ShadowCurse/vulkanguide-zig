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

    return .{
        .window = window,
        .vk_instance = vk_instance,
    };
}

pub fn deinit(self: *Self) void {
    vk.vkDestroyInstance(self.vk_instance);
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
