const std = @import("std");
const sdl = @import("sdl.zig");
const vk = @import("vulkan.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

const Error = error{
    SDLInit,
    SDLCreateWindow,
};

const WIDTH = 1280;
const HEIGHT = 720;

window: *sdl.SDL_Window,

pub fn init(allocator: Allocator) Error!Self {
    _ = allocator;
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        return Error.SDLInit;
    }
    const window = sdl.SDL_CreateWindow(
        "VulkanGuide",
        sdl.SDL_WINDOWPOS_UNDEFINED,
        sdl.SDL_WINDOWPOS_UNDEFINED,
        WIDTH,
        HEIGHT,
        sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE,
    ) orelse {
        return Error.SDLCreateWindow;
    };
    sdl.SDL_ShowWindow(window);

    return .{ .window = window };
}

pub fn deinit(self: *Self) void {
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
