const std = @import("std");

const vk = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vk_mem_alloc.h");
});

pub usingnamespace vk;

pub const AllocatedImage = struct {
    image: vk.VkImage,
    view: vk.VkImageView,
    extent: vk.VkExtent3D,
    format: vk.VkFormat,
    allocation: vk.VmaAllocation,
};

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

pub fn copy_image_to_image(
    buffer: vk.VkCommandBuffer,
    src: vk.VkImage,
    src_size: vk.VkExtent2D,
    dst: vk.VkImage,
    dst_size: vk.VkExtent2D,
) void {
    const blit_region = vk.VkImageBlit2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
        .srcOffsets = .{
            .{}, .{
                .x = @intCast(src_size.width),
                .y = @intCast(src_size.height),
                .z = 1,
            },
        },
        .dstOffsets = .{
            .{}, .{
                .x = @intCast(dst_size.width),
                .y = @intCast(dst_size.height),
                .z = 1,
            },
        },
        .srcSubresource = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .mipLevel = 0,
        },
        .dstSubresource = .{
            .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .mipLevel = 0,
        },
    };

    const blit_info = vk.VkBlitImageInfo2{
        .sType = vk.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
        .srcImage = src,
        .srcImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .dstImage = dst,
        .dstImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .filter = vk.VK_FILTER_LINEAR,
        .regionCount = 1,
        .pRegions = &blit_region,
    };
    vk.vkCmdBlitImage2(buffer, &blit_info);
}

pub const PipelineBuilder = struct {
    stages: [2]vk.VkPipelineShaderStageCreateInfo = .{
        .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        },
        .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        },
    },
    input_assembly: vk.VkPipelineInputAssemblyStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    },
    rasterization: vk.VkPipelineRasterizationStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    },
    multisampling: vk.VkPipelineMultisampleStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    },
    depth_stencil: vk.VkPipelineDepthStencilStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    },
    rendering: vk.VkPipelineRenderingCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
    },
    color_blend_attachment: vk.VkPipelineColorBlendAttachmentState = .{
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT |
            vk.VK_COLOR_COMPONENT_G_BIT |
            vk.VK_COLOR_COMPONENT_B_BIT |
            vk.VK_COLOR_COMPONENT_A_BIT,
    },
    _layout: vk.VkPipelineLayout = undefined,
    _color_attachment_format: vk.VkFormat = undefined,

    const Self = @This();

    pub fn layout(self: *Self, l: vk.VkPipelineLayout) *Self {
        self._layout = l;
        return self;
    }

    pub fn shaders(self: *Self, vertex_shader: vk.VkShaderModule, fragment_shader: vk.VkShaderModule) *Self {
        self.stages[0].stage = vk.VK_SHADER_STAGE_VERTEX_BIT;
        self.stages[0].module = vertex_shader;
        self.stages[0].pName = "main";

        self.stages[1].stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT;
        self.stages[1].module = fragment_shader;
        self.stages[1].pName = "main";

        return self;
    }

    pub fn input_topology(self: *Self, topology: vk.VkPrimitiveTopology) *Self {
        self.input_assembly.topology = topology;
        self.input_assembly.primitiveRestartEnable = vk.VK_FALSE;
        return self;
    }

    pub fn polygon_mode(self: *Self, mode: vk.VkPolygonMode) *Self {
        self.rasterization.polygonMode = mode;
        self.rasterization.lineWidth = 1.0;
        return self;
    }

    pub fn cull_mode(self: *Self, mode: vk.VkCullModeFlags, front_face: vk.VkFrontFace) *Self {
        self.rasterization.cullMode = mode;
        self.rasterization.frontFace = front_face;
        return self;
    }

    pub fn multisampling_none(self: *Self) *Self {
        self.multisampling.sampleShadingEnable = vk.VK_FALSE;
        self.multisampling.rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT;
        self.multisampling.minSampleShading = 1.0;
        self.multisampling.alphaToOneEnable = vk.VK_FALSE;
        self.multisampling.alphaToCoverageEnable = vk.VK_FALSE;
        return self;
    }

    pub fn blending_none(self: *Self) *Self {
        self.color_blend_attachment.blendEnable = vk.VK_FALSE;
        return self;
    }

    pub fn color_attachment_format(self: *Self, format: vk.VkFormat) *Self {
        self._color_attachment_format = format;
        return self;
    }

    pub fn depth_format(self: *Self, format: vk.VkFormat) *Self {
        self.rendering.depthAttachmentFormat = format;
        return self;
    }

    pub fn depthtest_none(self: *Self) *Self {
        self.depth_stencil.depthTestEnable = vk.VK_FALSE;
        self.depth_stencil.depthWriteEnable = vk.VK_FALSE;
        self.depth_stencil.depthCompareOp = vk.VK_COMPARE_OP_NEVER;
        self.depth_stencil.depthBoundsTestEnable = vk.VK_FALSE;
        self.depth_stencil.stencilTestEnable = vk.VK_FALSE;
        self.depth_stencil.front = .{};
        self.depth_stencil.back = .{};
        self.depth_stencil.minDepthBounds = 0.0;
        self.depth_stencil.maxDepthBounds = 1.0;
        return self;
    }

    pub fn build(self: *Self, device: vk.VkDevice) !vk.VkPipeline {
        self.rendering.pColorAttachmentFormats = &self._color_attachment_format;
        self.rendering.colorAttachmentCount = 1;

        const viewport = vk.VkPipelineViewportStateCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
        };

        const color_blending = vk.VkPipelineColorBlendStateCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = vk.VK_FALSE,
            .logicOp = vk.VK_LOGIC_OP_COPY,
            .pAttachments = &self.color_blend_attachment,
            .attachmentCount = 1,
        };

        const vertex_input = vk.VkPipelineVertexInputStateCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        };

        const dynamic_states = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
        const dynamic_state_info = vk.VkPipelineDynamicStateCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .pDynamicStates = &dynamic_states,
            .dynamicStateCount = @intCast(dynamic_states.len),
        };

        const pipeline_create_info = vk.VkGraphicsPipelineCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pStages = &self.stages,
            .stageCount = @intCast(self.stages.len),
            .pVertexInputState = &vertex_input,
            .pInputAssemblyState = &self.input_assembly,
            .pViewportState = &viewport,
            .pRasterizationState = &self.rasterization,
            .pMultisampleState = &self.multisampling,
            .pColorBlendState = &color_blending,
            .pDepthStencilState = &self.depth_stencil,
            .pDynamicState = &dynamic_state_info,
            .layout = self._layout,
            .pNext = &self.rendering,
        };

        var pipeline: vk.VkPipeline = undefined;
        try check_result(vk.vkCreateGraphicsPipelines(
            device,
            null,
            1,
            &pipeline_create_info,
            null,
            &pipeline,
        ));
        return pipeline;
    }
};
