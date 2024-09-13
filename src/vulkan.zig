const std = @import("std");

const vk = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vk_mem_alloc.h");
});

pub usingnamespace vk;

pub fn check_result(result: vk.VkResult) !void {
    switch (result) {
        vk.VK_SUCCESS => return,
        else => {
            std.log.err("Got Vulkan error: {}", .{result});
            return error.VkError;
        },
    }
}

pub fn transition_image(
    buffer: vk.VkCommandBuffer,
    image: vk.VkImage,
    source_layout: vk.VkImageLayout,
    target_layout: vk.VkImageLayout,
) void {
    const aspect_mask = if (target_layout == vk.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL)
        vk.VK_IMAGE_ASPECT_DEPTH_BIT
    else
        vk.VK_IMAGE_ASPECT_COLOR_BIT;
    const subresource = vk.VkImageSubresourceRange{
        .aspectMask = @intCast(aspect_mask),
        .baseMipLevel = 0,
        .levelCount = vk.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = vk.VK_REMAINING_ARRAY_LAYERS,
    };
    const barrier = vk.VkImageMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .srcAccessMask = vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
        .dstStageMask = vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        .dstAccessMask = vk.VK_ACCESS_2_MEMORY_WRITE_BIT | vk.VK_ACCESS_2_MEMORY_READ_BIT,
        .oldLayout = source_layout,
        .newLayout = target_layout,
        .subresourceRange = subresource,
        .image = image,
    };

    const dependency = vk.VkDependencyInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .pImageMemoryBarriers = &barrier,
        .imageMemoryBarrierCount = 1,
    };

    vk.vkCmdPipelineBarrier2(buffer, &dependency);
}
