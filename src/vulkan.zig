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

pub fn transition_image(
    buffer: Self.VkCommandBuffer,
    image: Self.VkImage,
    source_layout: Self.VkImageLayout,
    target_layout: Self.VkImageLayout,
) void {
    const aspect_mask = if (target_layout == Self.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL)
        Self.VK_IMAGE_ASPECT_DEPTH_BIT
    else
        Self.VK_IMAGE_ASPECT_COLOR_BIT;
    const subresource = Self.VkImageSubresourceRange{
        .aspectMask = @intCast(aspect_mask),
        .baseMipLevel = 0,
        .levelCount = Self.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = Self.VK_REMAINING_ARRAY_LAYERS,
    };
    const barrier = Self.VkImageMemoryBarrier2{
        .sType = Self.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = Self.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .srcAccessMask = Self.VK_ACCESS_2_MEMORY_WRITE_BIT,
        .dstStageMask = Self.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .dstAccessMask = Self.VK_ACCESS_2_MEMORY_WRITE_BIT | Self.VK_ACCESS_2_MEMORY_READ_BIT,
        .oldLayout = source_layout,
        .newLayout = target_layout,
        .subresourceRange = subresource,
        .image = image,
    };

    const dependency = Self.VkDependencyInfo{
        .sType = Self.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .pImageMemoryBarriers = &barrier,
        .imageMemoryBarrierCount = 1,
    };

    Self.vkCmdPipelineBarrier2(buffer, &dependency);
}
