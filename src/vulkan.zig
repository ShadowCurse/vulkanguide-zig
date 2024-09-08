const std = @import("std");

pub usingnamespace @cImport({
    @cInclude("vulkan/vulkan.h");
});

const Self = @This();

pub fn check_result(result: Self.VkResult) !void {
    switch (result) {
        Self.VK_SUCCESS => return,
        else => {
            std.log.err("Got Vulkan error: {}", .{result});
            return error.VkError;
        },
    }
}
