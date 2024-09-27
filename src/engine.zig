const std = @import("std");
const sdl = @import("sdl.zig");
const vk = @import("vulkan.zig");
const cimgui = @import("cimgui.zig");
const cgltf = @import("cgltf.zig");

const math = @import("math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;

const Self = @This();

const WIDTH = 1280;
const HEIGHT = 720;
const VK_VALIDATION_LAYERS_NAMES = [_][]const u8{"VK_LAYER_KHRONOS_validation"};
const VK_ADDITIONAL_EXTENSIONS_NAMES = [_][]const u8{"VK_EXT_debug_utils"};
const VK_PHYSICAL_DEVICE_EXTENSION_NAMES = [_][]const u8{"VK_KHR_swapchain"};

const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const MAGENTA = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
};

const Vertex = extern struct {
    position: Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    uv_x: f32 = 0.0,
    normal: Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    uv_y: f32 = 0.0,
    color: Vec4 = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
};

const MeshAsset = struct {
    name: [:0]const u8,
    surfaces: []SurfaceInfo,
    mesh: GpuMesh,

    const SurfaceInfo = struct {
        start_index: u32,
        count: u32,
    };

    pub fn deinit(self: *const MeshAsset, allocator: *Allocator, vma_allocator: vk.VmaAllocator) void {
        allocator.free(self.name);
        allocator.free(self.surfaces);
        self.mesh.deinit(vma_allocator);
    }
};

const GpuMesh = struct {
    index_buffer: vk.AllocatedBuffer,
    vertex_buffer: vk.AllocatedBuffer,
    vertex_device_address: vk.VkDeviceAddress,

    pub fn deinit(self: *const GpuMesh, vma_allocator: vk.VmaAllocator) void {
        vk.vmaDestroyBuffer(vma_allocator, self.index_buffer.buffer, self.index_buffer.allocation);
        vk.vmaDestroyBuffer(vma_allocator, self.vertex_buffer.buffer, self.vertex_buffer.allocation);
    }
};

const GpuPushConstants = extern struct {
    world_matrix: Mat4,
    device_address: vk.VkDeviceAddress,
};

const ComputePushConstants = extern struct {
    data1: Vec4 = .{},
    data2: Vec4 = .{},
    data3: Vec4 = .{},
    data4: Vec4 = .{},
};

const ComputeData = struct {
    name: [:0]const u8,
    constants: ComputePushConstants,
    pipeline: vk.VkPipeline,
    layout: vk.VkPipelineLayout,

    pub fn deinit(self: *const ComputeData, device: vk.VkDevice) void {
        vk.vkDestroyPipelineLayout(device, self.layout, null);
        vk.vkDestroyPipeline(device, self.pipeline, null);
    }
};

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

const Swapchain = struct {
    swap_chain: vk.VkSwapchainKHR,
    images: []vk.VkImage,
    image_views: []vk.VkImageView,
    format: vk.VkFormat,
    extent: vk.VkExtent2D,

    pub fn deinit(self: *const Swapchain, device: vk.VkDevice, allocator: *const Allocator) void {
        for (self.image_views) |view| {
            vk.vkDestroyImageView(device, view, null);
        }
        vk.vkDestroySwapchainKHR(device, self.swap_chain, null);
        allocator.free(self.images);
        allocator.free(self.image_views);
    }
};

const Commands = struct {
    pool: vk.VkCommandPool,
    buffer: vk.VkCommandBuffer,
    swap_chain_semaphore: vk.VkSemaphore,
    render_semaphore: vk.VkSemaphore,
    render_fence: vk.VkFence,

    pub fn deinit(self: *const Commands, device: vk.VkDevice) void {
        vk.vkDestroyFence(device, self.render_fence, null);
        vk.vkDestroySemaphore(device, self.render_semaphore, null);
        vk.vkDestroySemaphore(device, self.swap_chain_semaphore, null);
        vk.vkDestroyCommandPool(device, self.pool, null);
    }
};

const FRAMES = 2;
const TIMEOUT = std.math.maxInt(u64);
current_frame: u32 = 0,

allocator: Allocator,
window: *sdl.SDL_Window,
surface: vk.VkSurfaceKHR = undefined,
vma_allocator: vk.VmaAllocator = undefined,
vk_instance: vk.VkInstance = undefined,
vk_debug_messanger: vk.VkDebugUtilsMessengerEXT = undefined,
vk_physical_device: PhysicalDevice = undefined,
vk_logical_device: LogicalDevice = undefined,
vk_swap_chain: Swapchain = undefined,
vk_commands: [FRAMES]Commands = undefined,
vk_descriptor_pool: vk.VkDescriptorPool = undefined,

draw_image: vk.AllocatedImage = undefined,
depth_image: vk.AllocatedImage = undefined,
draw_image_desc_set: vk.VkDescriptorSet = undefined,
draw_image_desc_set_layout: vk.VkDescriptorSetLayout = undefined,

immediate_fence: vk.VkFence = undefined,
immediate_command_pool: vk.VkCommandPool = undefined,
immediate_command_buffer: vk.VkCommandBuffer = undefined,

imgui_pool: vk.VkDescriptorPool = undefined,

selected_compute_data: i32 = 0,
compute_data: [2]ComputeData = undefined,

mesh_pipeline_layout: vk.VkPipelineLayout = undefined,
mesh_pipeline: vk.VkPipeline = undefined,

selected_mesh: i32 = 0,
mesh_assets: std.ArrayListUnmanaged(MeshAsset) = undefined,

checkerboard_image: vk.AllocatedImage = undefined,
linear_sampler: vk.VkSampler = undefined,
nearest_sampler: vk.VkSampler = undefined,

texture_desc_set: vk.VkDescriptorSet = undefined,
texture_desc_set_layout: vk.VkDescriptorSetLayout = undefined,

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

    const allocator_info = vk.VmaAllocatorCreateInfo{
        .instance = self.vk_instance,
        .physicalDevice = self.vk_physical_device.device,
        .device = self.vk_logical_device.device,
        .flags = vk.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };
    try vk.check_result(vk.vmaCreateAllocator(&allocator_info, &self.vma_allocator));

    try self.create_swap_chain();
    try self.create_commands();
    try self.create_immediate_objects();

    try self.create_debug_image();
    try self.create_descriptors();

    try self.create_compute_pipelines();
    try self.create_mesh_pipeline();

    try self.init_imgui();

    try self.load_gltf_meshes("assets/monkey.glb");
    try self.load_gltf_meshes("assets/basicmesh.glb");

    return self;
}

pub fn deinit(self: *Self) void {
    _ = vk.vkDeviceWaitIdle(self.vk_logical_device.device);

    cimgui.ImGui_ImplVulkan_DestroyFontsTexture();
    cimgui.ImGui_ImplVulkan_Shutdown();
    vk.vkDestroyDescriptorPool(self.vk_logical_device.device, self.imgui_pool, null);

    vk.vkDestroyFence(self.vk_logical_device.device, self.immediate_fence, null);
    vk.vkDestroyCommandPool(self.vk_logical_device.device, self.immediate_command_pool, null);

    for (self.mesh_assets.items) |asset| {
        asset.deinit(&self.allocator, self.vma_allocator);
    }
    self.mesh_assets.deinit(self.allocator);

    vk.vkDestroyPipelineLayout(self.vk_logical_device.device, self.mesh_pipeline_layout, null);
    vk.vkDestroyPipeline(self.vk_logical_device.device, self.mesh_pipeline, null);

    for (self.compute_data) |data| {
        data.deinit(self.vk_logical_device.device);
    }

    vk.vkDestroyDescriptorSetLayout(self.vk_logical_device.device, self.draw_image_desc_set_layout, null);
    vk.vkDestroyDescriptorPool(self.vk_logical_device.device, self.vk_descriptor_pool, null);

    self.depth_image.deinit(self.vk_logical_device.device, self.vma_allocator);
    self.draw_image.deinit(self.vk_logical_device.device, self.vma_allocator);

    self.checkerboard_image.deinit(self.vk_logical_device.device, self.vma_allocator);
    vk.vkDestroySampler(self.vk_logical_device.device, self.nearest_sampler, null);
    vk.vkDestroySampler(self.vk_logical_device.device, self.linear_sampler, null);

    vk.vmaDestroyAllocator(self.vma_allocator);

    for (self.vk_commands) |command| {
        command.deinit(self.vk_logical_device.device);
    }

    self.vk_swap_chain.deinit(self.vk_logical_device.device, &self.allocator);

    vk.vkDestroyDevice(self.vk_logical_device.device, null);
    vk.vkDestroySurfaceKHR(self.vk_instance, self.surface, null);
    self.destroy_debug_messanger() catch {
        std.log.err("Could not destroy debug messanger", .{});
    };
    vk.vkDestroyInstance(self.vk_instance, null);
    sdl.SDL_DestroyWindow(self.window);
}

pub fn current_frame_command(self: *Self) *Commands {
    return &self.vk_commands[self.current_frame % Self.FRAMES];
}

pub fn run(self: *Self) !void {
    var stop = false;
    while (!stop) {
        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event) != 0) {
            if (sdl_event.type == sdl.SDL_QUIT) {
                stop = true;
                break;
            }

            _ = cimgui.ImGui_ImplSDL2_ProcessEvent(@ptrCast(&sdl_event));
        }

        cimgui.ImGui_ImplVulkan_NewFrame();
        cimgui.ImGui_ImplSDL2_NewFrame();
        cimgui.igNewFrame();

        var open = true;
        if (cimgui.igBegin("Parameters", &open, 0)) {
            const current_compute_data = &self.compute_data[@intCast(self.selected_compute_data)];

            _ = cimgui.igText("Shader name: %s", current_compute_data.name.ptr);

            _ = cimgui.igSliderInt("Shader index", &self.selected_compute_data, 0, self.compute_data.len - 1, null, 0);

            _ = cimgui.igInputFloat4("data1", @ptrCast(&current_compute_data.constants.data1), null, 0);
            _ = cimgui.igInputFloat4("data2", @ptrCast(&current_compute_data.constants.data2), null, 0);
            _ = cimgui.igInputFloat4("data3", @ptrCast(&current_compute_data.constants.data3), null, 0);
            _ = cimgui.igInputFloat4("data4", @ptrCast(&current_compute_data.constants.data4), null, 0);

            const current_mesh = &self.mesh_assets.items[@intCast(self.selected_mesh)];
            _ = cimgui.igText("Mesh name: %s", current_mesh.name.ptr);
            _ = cimgui.igSliderInt("Mesh index", &self.selected_mesh, 0, @intCast(self.mesh_assets.items.len - 1), null, 0);

            cimgui.igEnd();
        }

        cimgui.igRender();

        const current_commands = self.current_frame_command();

        // Wait for a GPU
        try vk.check_result(vk.vkWaitForFences(
            self.vk_logical_device.device,
            1,
            &current_commands.render_fence,
            vk.VK_TRUE,
            Self.TIMEOUT,
        ));
        try vk.check_result(vk.vkResetFences(self.vk_logical_device.device, 1, &current_commands.render_fence));

        // Get new image
        var image_index: u32 = 0;
        const aquire_result = vk.vkAcquireNextImageKHR(
            self.vk_logical_device.device,
            self.vk_swap_chain.swap_chain,
            Self.TIMEOUT,
            current_commands.swap_chain_semaphore,
            null,
            &image_index,
        );
        // If window is resized, recreate swap chain
        // and try again
        if (aquire_result == vk.VK_ERROR_OUT_OF_DATE_KHR or
            aquire_result == vk.VK_SUBOPTIMAL_KHR)
        {
            try self.recreate_swap_chain();
            try vk.check_result(vk.vkAcquireNextImageKHR(
                self.vk_logical_device.device,
                self.vk_swap_chain.swap_chain,
                Self.TIMEOUT,
                null,
                null,
                &image_index,
            ));
        } else {
            try vk.check_result(aquire_result);
        }

        // Write commands
        try vk.check_result(vk.vkResetCommandBuffer(current_commands.buffer, 0));
        const begin_info = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        try vk.check_result(vk.vkBeginCommandBuffer(current_commands.buffer, &begin_info));

        vk.transition_image(
            current_commands.buffer,
            self.draw_image.image,
            vk.VK_IMAGE_LAYOUT_UNDEFINED,
            vk.VK_IMAGE_LAYOUT_GENERAL,
        );

        self.draw_background(current_commands.buffer);

        vk.transition_image(
            current_commands.buffer,
            self.draw_image.image,
            vk.VK_IMAGE_LAYOUT_GENERAL,
            vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        );

        vk.transition_image(
            current_commands.buffer,
            self.depth_image.image,
            vk.VK_IMAGE_LAYOUT_UNDEFINED,
            vk.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        );

        self.draw_geometry(current_commands.buffer);

        vk.transition_image(
            current_commands.buffer,
            self.draw_image.image,
            vk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
            vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        );
        vk.transition_image(
            current_commands.buffer,
            self.vk_swap_chain.images[image_index],
            vk.VK_IMAGE_LAYOUT_UNDEFINED,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        );
        vk.copy_image_to_image(
            current_commands.buffer,
            self.draw_image.image,
            .{
                .width = self.draw_image.extent.width,
                .height = self.draw_image.extent.height,
            },
            self.vk_swap_chain.images[image_index],
            self.vk_swap_chain.extent,
        );
        vk.transition_image(
            current_commands.buffer,
            self.vk_swap_chain.images[image_index],
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        );

        const imgui_attachment = vk.VkRenderingAttachmentInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = self.vk_swap_chain.image_views[image_index],
            .imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp = vk.VK_ATTACHMENT_LOAD_OP_LOAD,
            .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        };
        const imgui_render_info = vk.VkRenderingInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .pColorAttachments = &imgui_attachment,
            .colorAttachmentCount = 1,
            .renderArea = .{ .extent = self.vk_swap_chain.extent },
            .layerCount = 1,
        };
        vk.vkCmdBeginRendering(current_commands.buffer, &imgui_render_info);
        cimgui.ImGui_ImplVulkan_RenderDrawData(cimgui.igGetDrawData(), @ptrCast(current_commands.buffer), null);
        vk.vkCmdEndRendering(current_commands.buffer);

        vk.transition_image(
            current_commands.buffer,
            self.vk_swap_chain.images[image_index],
            vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        );

        try vk.check_result(vk.vkEndCommandBuffer(current_commands.buffer));

        // Submit commands
        const buffer_submit_info = vk.VkCommandBufferSubmitInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = current_commands.buffer,
            .deviceMask = 0,
        };
        const wait_semaphore_info = vk.VkSemaphoreSubmitInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = current_commands.swap_chain_semaphore,
            .stageMask = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
        };
        const signal_semaphore_info = vk.VkSemaphoreSubmitInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = current_commands.render_semaphore,
            .stageMask = vk.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
        };
        const submit_info = vk.VkSubmitInfo2{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .pWaitSemaphoreInfos = &wait_semaphore_info,
            .waitSemaphoreInfoCount = 1,
            .pSignalSemaphoreInfos = &signal_semaphore_info,
            .signalSemaphoreInfoCount = 1,
            .pCommandBufferInfos = &buffer_submit_info,
            .commandBufferInfoCount = 1,
        };
        try vk.check_result(vk.vkQueueSubmit2(
            self.vk_logical_device.graphics_queue,
            1,
            &submit_info,
            current_commands.render_fence,
        ));

        // Present image in the screen
        const present_info = vk.VkPresentInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pSwapchains = &self.vk_swap_chain.swap_chain,
            .swapchainCount = 1,
            .pWaitSemaphores = &current_commands.render_semaphore,
            .waitSemaphoreCount = 1,
            .pImageIndices = &image_index,
        };
        const present_result = vk.vkQueuePresentKHR(self.vk_logical_device.graphics_queue, &present_info);
        if (present_result == vk.VK_ERROR_OUT_OF_DATE_KHR or
            present_result == vk.VK_SUBOPTIMAL_KHR)
        {
            try self.recreate_swap_chain();
        } else {
            try vk.check_result(present_result);
        }
        self.current_frame += 1;
    }
}

pub fn draw_background(self: *const Self, buffer: vk.VkCommandBuffer) void {
    const current_compute_data = &self.compute_data[@intCast(self.selected_compute_data)];
    vk.vkCmdBindPipeline(buffer, vk.VK_PIPELINE_BIND_POINT_COMPUTE, current_compute_data.pipeline);
    vk.vkCmdBindDescriptorSets(
        buffer,
        vk.VK_PIPELINE_BIND_POINT_COMPUTE,
        current_compute_data.layout,
        0,
        1,
        &self.draw_image_desc_set,
        0,
        null,
    );
    vk.vkCmdPushConstants(
        buffer,
        current_compute_data.layout,
        vk.VK_SHADER_STAGE_COMPUTE_BIT,
        0,
        @sizeOf(ComputePushConstants),
        &current_compute_data.constants,
    );
    vk.vkCmdDispatch(
        buffer,
        @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(self.vk_swap_chain.extent.width)) / 16.0))),
        @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(self.vk_swap_chain.extent.height)) / 16.0))),
        1,
    );
}

pub fn draw_geometry(self: *const Self, buffer: vk.VkCommandBuffer) void {
    const color_attachment = vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.draw_image.view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
    };
    const depth_attachment = vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_image.view,
        .imageLayout = vk.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .depthStencil = .{ .depth = 0.0 } },
    };

    const render_info = vk.VkRenderingInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .pColorAttachments = &color_attachment,
        .colorAttachmentCount = 1,
        .pDepthAttachment = &depth_attachment,
        .renderArea = .{ .extent = .{
            .width = self.draw_image.extent.width,
            .height = self.draw_image.extent.height,
        } },
        .layerCount = 1,
    };
    vk.vkCmdBeginRendering(buffer, &render_info);

    const viewport = vk.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.draw_image.extent.width),
        .height = @floatFromInt(self.draw_image.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vk.vkCmdSetViewport(buffer, 0, 1, &viewport);
    const scissor = vk.VkRect2D{ .offset = .{
        .x = 0.0,
        .y = 0.0,
    }, .extent = .{
        .width = self.draw_image.extent.width,
        .height = self.draw_image.extent.height,
    } };
    vk.vkCmdSetScissor(buffer, 0, 1, &scissor);

    // Draw meshes
    vk.vkCmdBindPipeline(buffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.mesh_pipeline);

    vk.vkCmdBindDescriptorSets(
        buffer,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.mesh_pipeline_layout,
        0,
        1,
        &self.texture_desc_set,
        0,
        null,
    );

    const view = Mat4.IDENDITY.translate(Vec3{ .x = 0.0, .y = 0.0, .z = -5.0 });
    var projection = Mat4.perspective(
        std.math.degreesToRadians(70.0),
        @as(f32, @floatFromInt(self.draw_image.extent.width)) /
            @as(f32, @floatFromInt(self.draw_image.extent.height)),
        10000.0,
        0.1,
    );
    projection.j.y *= -1.0;

    var gpu_push_constatns = GpuPushConstants{
        .world_matrix = view.mul(projection),
        .device_address = undefined,
    };

    // Other meshes
    const asset = self.mesh_assets.items[@intCast(self.selected_mesh)];
    gpu_push_constatns.device_address = asset.mesh.vertex_device_address;
    vk.vkCmdPushConstants(
        buffer,
        self.mesh_pipeline_layout,
        vk.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        @sizeOf(GpuPushConstants),
        &gpu_push_constatns,
    );
    vk.vkCmdBindIndexBuffer(buffer, asset.mesh.index_buffer.buffer, 0, vk.VK_INDEX_TYPE_UINT32);
    vk.vkCmdDrawIndexed(buffer, asset.surfaces[0].count, 1, asset.surfaces[0].start_index, 0, 0);

    vk.vkCmdEndRendering(buffer);
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

pub fn create_swap_chain(self: *Self) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var surface_capabilities: vk.VkSurfaceCapabilitiesKHR = undefined;
    try vk.check_result(vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(self.vk_physical_device.device, self.surface, &surface_capabilities));

    var device_surface_format_count: u32 = 0;
    try vk.check_result(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(
        self.vk_physical_device.device,
        self.surface,
        &device_surface_format_count,
        null,
    ));
    const device_surface_formats = try arena_allocator.alloc(vk.VkSurfaceFormatKHR, device_surface_format_count);
    try vk.check_result(vk.vkGetPhysicalDeviceSurfaceFormatsKHR(
        self.vk_physical_device.device,
        self.surface,
        &device_surface_format_count,
        device_surface_formats.ptr,
    ));
    var found_format: ?vk.VkSurfaceFormatKHR = null;
    for (device_surface_formats) |format| {
        if (format.format == vk.VK_FORMAT_B8G8R8A8_UNORM and format.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            found_format = format;
            break;
        }
    }
    if (found_format == null) {
        return error.SurfaceFormatNotFound;
    }
    const surface_format = found_format.?;

    var swap_chain_extent: vk.VkExtent2D = surface_capabilities.currentExtent;
    if (swap_chain_extent.width == std.math.maxInt(u32)) {
        var w: i32 = 0;
        var h: i32 = 0;
        sdl.SDL_GetWindowSize(self.window, &w, &h);
        const window_w: u32 = @intCast(w);
        const window_h: u32 = @intCast(h);
        swap_chain_extent.width = @min(@max(window_w, surface_capabilities.minImageExtent.width), surface_capabilities.maxImageExtent.width);
        swap_chain_extent.height = @min(@max(window_h, surface_capabilities.minImageExtent.height), surface_capabilities.maxImageExtent.height);
    }

    const create_info = vk.VkSwapchainCreateInfoKHR{
        .sType = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = self.surface,
        .minImageCount = surface_capabilities.minImageCount + 1,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = swap_chain_extent,
        .imageArrayLayers = 1,
        .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .preTransform = surface_capabilities.currentTransform,
        .compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vk.VK_PRESENT_MODE_FIFO_KHR,
        .clipped = vk.VK_TRUE,
        .oldSwapchain = null,
    };

    try vk.check_result(vk.vkCreateSwapchainKHR(self.vk_logical_device.device, &create_info, null, &self.vk_swap_chain.swap_chain));
    self.vk_swap_chain.format = surface_format.format;
    self.vk_swap_chain.extent = swap_chain_extent;

    var swap_chain_images_count: u32 = 0;
    try vk.check_result(vk.vkGetSwapchainImagesKHR(
        self.vk_logical_device.device,
        self.vk_swap_chain.swap_chain,
        &swap_chain_images_count,
        null,
    ));
    self.vk_swap_chain.images = try self.allocator.alloc(vk.VkImage, swap_chain_images_count);
    errdefer self.allocator.free(self.vk_swap_chain.images);
    try vk.check_result(vk.vkGetSwapchainImagesKHR(
        self.vk_logical_device.device,
        self.vk_swap_chain.swap_chain,
        &swap_chain_images_count,
        self.vk_swap_chain.images.ptr,
    ));

    self.vk_swap_chain.image_views = try self.allocator.alloc(vk.VkImageView, swap_chain_images_count);
    errdefer self.allocator.free(self.vk_swap_chain.image_views);
    for (self.vk_swap_chain.images, self.vk_swap_chain.image_views) |image, *view| {
        const view_create_info = vk.VkImageViewCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = self.vk_swap_chain.format,
            .components = .{
                .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        try vk.check_result(
            vk.vkCreateImageView(
                self.vk_logical_device.device,
                &view_create_info,
                null,
                view,
            ),
        );
    }

    self.draw_image = try self.create_image(
        self.vk_swap_chain.extent.width,
        self.vk_swap_chain.extent.height,
        vk.VK_FORMAT_R16G16B16A16_SFLOAT,
        vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.VK_IMAGE_USAGE_STORAGE_BIT |
            vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    );
    self.depth_image = try self.create_image(
        self.vk_swap_chain.extent.width,
        self.vk_swap_chain.extent.height,
        vk.VK_FORMAT_D32_SFLOAT,
        vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
    );
}

pub fn recreate_swap_chain(self: *Self) !void {
    try vk.check_result(vk.vkDeviceWaitIdle(self.vk_logical_device.device));

    self.vk_swap_chain.deinit(self.vk_logical_device.device, &self.allocator);
    self.depth_image.deinit(self.vk_logical_device.device, self.vma_allocator);
    self.draw_image.deinit(self.vk_logical_device.device, self.vma_allocator);

    try self.create_swap_chain();

    const desc_image_info = vk.VkDescriptorImageInfo{
        .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
        .imageView = self.draw_image.view,
    };
    const desc_image_write = vk.VkWriteDescriptorSet{
        .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = 0,
        .dstSet = self.draw_image_desc_set,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .pImageInfo = &desc_image_info,
    };
    vk.vkUpdateDescriptorSets(self.vk_logical_device.device, 1, &desc_image_write, 0, null);
}

pub fn create_commands(self: *Self) !void {
    const pool_create_info = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = self.vk_physical_device.graphics_queue_family,
    };
    for (&self.vk_commands) |*commands| {
        try vk.check_result(vk.vkCreateCommandPool(self.vk_logical_device.device, &pool_create_info, null, &commands.pool));
        const allocate_info = vk.VkCommandBufferAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = commands.pool,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };
        try vk.check_result(vk.vkAllocateCommandBuffers(self.vk_logical_device.device, &allocate_info, &commands.buffer));
        const fence_create_info = vk.VkFenceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
        };
        try vk.check_result(vk.vkCreateFence(self.vk_logical_device.device, &fence_create_info, null, &commands.render_fence));
        const semaphore_creaet_info = vk.VkSemaphoreCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };
        try vk.check_result(vk.vkCreateSemaphore(self.vk_logical_device.device, &semaphore_creaet_info, null, &commands.render_semaphore));
        try vk.check_result(vk.vkCreateSemaphore(self.vk_logical_device.device, &semaphore_creaet_info, null, &commands.swap_chain_semaphore));
    }
}

pub fn create_descriptors(self: *Self) !void {
    const pool_sizes = [_]vk.VkDescriptorPoolSize{
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = 1,
        },
        .{
            .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
        },
    };
    const pool_info = vk.VkDescriptorPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 10,
        .pPoolSizes = &pool_sizes,
        .poolSizeCount = pool_sizes.len,
    };
    try vk.check_result(vk.vkCreateDescriptorPool(self.vk_logical_device.device, &pool_info, null, &self.vk_descriptor_pool));

    // Draw image set
    {
        const binging_layout = vk.VkDescriptorSetLayoutBinding{
            .binding = 0,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
        };
        const layout_create_info = vk.VkDescriptorSetLayoutCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pBindings = &binging_layout,
            .bindingCount = 1,
        };
        try vk.check_result(vk.vkCreateDescriptorSetLayout(
            self.vk_logical_device.device,
            &layout_create_info,
            null,
            &self.draw_image_desc_set_layout,
        ));
        const set_alloc_info = vk.VkDescriptorSetAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = self.vk_descriptor_pool,
            .pSetLayouts = &self.draw_image_desc_set_layout,
            .descriptorSetCount = 1,
        };
        try vk.check_result(vk.vkAllocateDescriptorSets(self.vk_logical_device.device, &set_alloc_info, &self.draw_image_desc_set));
        const desc_info = vk.VkDescriptorImageInfo{
            .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
            .imageView = self.draw_image.view,
        };
        const desc_image_write = vk.VkWriteDescriptorSet{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = 0,
            .dstSet = self.draw_image_desc_set,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .pImageInfo = &desc_info,
        };
        vk.vkUpdateDescriptorSets(self.vk_logical_device.device, 1, &desc_image_write, 0, null);
    }

    // Texture set
    {
        const binging_layout = vk.VkDescriptorSetLayoutBinding{
            .binding = 0,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        };
        const layout_create_info = vk.VkDescriptorSetLayoutCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pBindings = &binging_layout,
            .bindingCount = 1,
        };
        try vk.check_result(vk.vkCreateDescriptorSetLayout(
            self.vk_logical_device.device,
            &layout_create_info,
            null,
            &self.texture_desc_set_layout,
        ));
        const set_alloc_info = vk.VkDescriptorSetAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = self.vk_descriptor_pool,
            .pSetLayouts = &self.texture_desc_set_layout,
            .descriptorSetCount = 1,
        };
        try vk.check_result(vk.vkAllocateDescriptorSets(self.vk_logical_device.device, &set_alloc_info, &self.texture_desc_set));
        const desc_image_info = vk.VkDescriptorImageInfo{
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .imageView = self.checkerboard_image.view,
            .sampler = self.nearest_sampler,
        };
        const desc_image_write = vk.VkWriteDescriptorSet{
            .sType = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = 0,
            .dstSet = self.texture_desc_set,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = &desc_image_info,
        };
        vk.vkUpdateDescriptorSets(self.vk_logical_device.device, 1, &desc_image_write, 0, null);
    }
}

pub fn load_shader_module(self: *Self, path: []const u8) !vk.VkShaderModule {
    const file = try std.fs.cwd().openFile(path, .{});
    const content = try file.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));
    defer self.allocator.free(content);

    const create_info = vk.VkShaderModuleCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pCode = @alignCast(@ptrCast(content.ptr)),
        .codeSize = content.len,
    };

    var module: vk.VkShaderModule = undefined;
    try vk.check_result(vk.vkCreateShaderModule(self.vk_logical_device.device, &create_info, null, &module));
    return module;
}

pub fn create_compute_pipelines(self: *Self) !void {
    const compute_push_constants = vk.VkPushConstantRange{
        .offset = 0,
        .size = @sizeOf(ComputePushConstants),
        .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
    };

    const compute_layout_create_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pSetLayouts = &self.draw_image_desc_set_layout,
        .setLayoutCount = 1,
        .pPushConstantRanges = &compute_push_constants,
        .pushConstantRangeCount = 1,
    };
    for (&self.compute_data) |*data| {
        try vk.check_result(vk.vkCreatePipelineLayout(
            self.vk_logical_device.device,
            &compute_layout_create_info,
            null,
            &data.layout,
        ));
    }

    {
        self.compute_data[0].name = "gradient";
        self.compute_data[0].constants = .{
            .data1 = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 },
            .data2 = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 1.0 },
        };

        const gradient_shader_module = try self.load_shader_module("gradient.spv");
        defer vk.vkDestroyShaderModule(self.vk_logical_device.device, gradient_shader_module, null);

        const shader_stage_create_info = vk.VkPipelineShaderStageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .module = gradient_shader_module,
            .pName = "main",
        };
        const compute_pipeline_create_info = vk.VkComputePipelineCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .layout = self.compute_data[0].layout,
            .stage = shader_stage_create_info,
        };
        try vk.check_result(vk.vkCreateComputePipelines(
            self.vk_logical_device.device,
            null,
            1,
            &compute_pipeline_create_info,
            null,
            &self.compute_data[0].pipeline,
        ));
    }

    {
        self.compute_data[1].name = "sky";
        self.compute_data[1].constants = .{
            .data1 = .{ .x = 0.1, .y = 0.2, .z = 0.4, .w = 0.999 },
        };

        const sky_shader_module = try self.load_shader_module("sky.spv");
        defer vk.vkDestroyShaderModule(self.vk_logical_device.device, sky_shader_module, null);

        const shader_stage_create_info = vk.VkPipelineShaderStageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = vk.VK_SHADER_STAGE_COMPUTE_BIT,
            .module = sky_shader_module,
            .pName = "main",
        };
        const compute_pipeline_create_info = vk.VkComputePipelineCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .layout = self.compute_data[1].layout,
            .stage = shader_stage_create_info,
        };
        try vk.check_result(vk.vkCreateComputePipelines(
            self.vk_logical_device.device,
            null,
            1,
            &compute_pipeline_create_info,
            null,
            &self.compute_data[1].pipeline,
        ));
    }
}

pub fn create_immediate_objects(self: *Self) !void {
    const pool_create_info = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = self.vk_physical_device.graphics_queue_family,
    };
    try vk.check_result(vk.vkCreateCommandPool(self.vk_logical_device.device, &pool_create_info, null, &self.immediate_command_pool));

    const allocate_info = vk.VkCommandBufferAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.immediate_command_pool,
        .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    try vk.check_result(vk.vkAllocateCommandBuffers(self.vk_logical_device.device, &allocate_info, &self.immediate_command_buffer));
    const fence_create_info = vk.VkFenceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    try vk.check_result(vk.vkCreateFence(self.vk_logical_device.device, &fence_create_info, null, &self.immediate_fence));
}

pub fn immediate_submit_begin(self: *const Self) !void {
    try vk.check_result(vk.vkResetFences(self.vk_logical_device.device, 1, &self.immediate_fence));
    try vk.check_result(vk.vkResetCommandBuffer(self.immediate_command_buffer, 0));

    const begin_info = vk.VkCommandBufferBeginInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try vk.check_result(vk.vkBeginCommandBuffer(self.immediate_command_buffer, &begin_info));
}

pub fn immediate_submit_end(self: *const Self) !void {
    try vk.check_result(vk.vkEndCommandBuffer(self.immediate_command_buffer));

    const buffer_submit_info = vk.VkCommandBufferSubmitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = self.immediate_command_buffer,
        .deviceMask = 0,
    };
    const submit_info = vk.VkSubmitInfo2{
        .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .pCommandBufferInfos = &buffer_submit_info,
        .commandBufferInfoCount = 1,
    };
    try vk.check_result(vk.vkQueueSubmit2(
        self.vk_logical_device.graphics_queue,
        1,
        &submit_info,
        self.immediate_fence,
    ));

    try vk.check_result(vk.vkWaitForFences(
        self.vk_logical_device.device,
        1,
        &self.immediate_fence,
        vk.VK_TRUE,
        Self.TIMEOUT,
    ));
}

pub fn init_imgui(self: *Self) !void {
    const pool_sizes = [_]vk.VkDescriptorPoolSize{
        .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, .descriptorCount = 1000 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, .descriptorCount = 1000 },
    };

    const pool_create_info = vk.VkDescriptorPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = vk.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        .maxSets = 1000,
        .pPoolSizes = &pool_sizes,
        .poolSizeCount = pool_sizes.len,
    };

    try vk.check_result(vk.vkCreateDescriptorPool(self.vk_logical_device.device, &pool_create_info, null, &self.imgui_pool));

    _ = cimgui.igCreateContext(null);
    _ = cimgui.ImGui_ImplSDL2_InitForVulkan(@ptrCast(self.window));

    var imgui_init_info = cimgui.ImGui_ImplVulkan_InitInfo{
        .Instance = @ptrCast(self.vk_instance),
        .PhysicalDevice = @ptrCast(self.vk_physical_device.device),
        .Device = @ptrCast(self.vk_logical_device.device),
        .Queue = @ptrCast(self.vk_logical_device.graphics_queue),
        .DescriptorPool = @ptrCast(self.imgui_pool),
        .MinImageCount = 3,
        .ImageCount = 3,
        .UseDynamicRendering = true,
        .PipelineRenderingCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
            .pColorAttachmentFormats = &self.vk_swap_chain.format,
            .colorAttachmentCount = 1,
        },
        .MSAASamples = vk.VK_SAMPLE_COUNT_1_BIT,
    };

    _ = cimgui.ImGui_ImplVulkan_Init(&imgui_init_info);
    _ = cimgui.ImGui_ImplVulkan_CreateFontsTexture();
}

pub fn create_mesh_pipeline(self: *Self) !void {
    const vertex_shader_module = try self.load_shader_module("mesh_vert.spv");
    defer vk.vkDestroyShaderModule(self.vk_logical_device.device, vertex_shader_module, null);
    const fragment_shader_module = try self.load_shader_module("texture_frag.spv");
    defer vk.vkDestroyShaderModule(self.vk_logical_device.device, fragment_shader_module, null);

    const push_constant_range = vk.VkPushConstantRange{
        .size = @sizeOf(GpuPushConstants),
        .offset = 0,
        .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
    };

    const layout_create_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pPushConstantRanges = &push_constant_range,
        .pushConstantRangeCount = 1,
        .pSetLayouts = &self.texture_desc_set_layout,
        .setLayoutCount = 1,
    };
    try vk.check_result(vk.vkCreatePipelineLayout(
        self.vk_logical_device.device,
        &layout_create_info,
        null,
        &self.mesh_pipeline_layout,
    ));

    var builder: vk.PipelineBuilder = .{};
    self.mesh_pipeline = try builder
        .layout(self.mesh_pipeline_layout)
        .shaders(vertex_shader_module, fragment_shader_module)
        .input_topology(vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST)
        .polygon_mode(vk.VK_POLYGON_MODE_FILL)
        .cull_mode(vk.VK_CULL_MODE_NONE, vk.VK_FRONT_FACE_CLOCKWISE)
        .multisampling_none()
        .blending_alphablend()
        .color_attachment_format(self.draw_image.format)
        .depthtest(true, vk.VK_COMPARE_OP_GREATER_OR_EQUAL)
        .depth_format(self.depth_image.format)
        .build(self.vk_logical_device.device);
}

pub fn create_buffer(self: *const Self, size: usize, usage: vk.VkBufferUsageFlags, memory_usage: vk.VmaMemoryUsage) !vk.AllocatedBuffer {
    const buffer_info = vk.VkBufferCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
    };
    const alloc_info = vk.VmaAllocationCreateInfo{
        .usage = memory_usage,
        .flags = vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    };
    var new_buffer: vk.AllocatedBuffer = undefined;
    try vk.check_result(vk.vmaCreateBuffer(
        self.vma_allocator,
        &buffer_info,
        &alloc_info,
        &new_buffer.buffer,
        &new_buffer.allocation,
        &new_buffer.allocation_info,
    ));
    return new_buffer;
}

pub fn create_image(self: *const Self, width: u32, height: u32, format: vk.VkFormat, usage: u32) !vk.AllocatedImage {
    var image: vk.AllocatedImage = undefined;
    image.extent = vk.VkExtent3D{
        .width = width,
        .height = height,
        .depth = 1,
    };
    image.format = format;
    const image_create_info = vk.VkImageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = image.format,
        .extent = image.extent,
        .usage = usage,
        .mipLevels = 1,
        .arrayLayers = 1,
        //for MSAA. we will not be using it by default, so default it to 1 sample per pixel.
        .samples = vk.VK_SAMPLE_COUNT_1_BIT,
        //optimal tiling, which means the image is stored on the best gpu format
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
    };
    const alloc_info = vk.VmaAllocationCreateInfo{
        .usage = vk.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };
    try vk.check_result(vk.vmaCreateImage(
        self.vma_allocator,
        &image_create_info,
        &alloc_info,
        &image.image,
        &image.allocation,
        null,
    ));

    const aspect_mask: u32 = if (usage & vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT != 0)
        vk.VK_IMAGE_ASPECT_DEPTH_BIT
    else
        vk.VK_IMAGE_ASPECT_COLOR_BIT;
    const image_view_create_info = vk.VkImageViewCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .image = image.image,
        .format = image.format,
        .subresourceRange = .{
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .aspectMask = aspect_mask,
        },
    };
    try vk.check_result(vk.vkCreateImageView(
        self.vk_logical_device.device,
        &image_view_create_info,
        null,
        &image.view,
    ));
    return image;
}

pub fn upload_image(self: *const Self, image: *const vk.AllocatedImage, data: []const u8, extent: vk.VkExtent3D) !void {
    const buffer_size = extent.height * extent.width * extent.depth * @sizeOf(u32);
    const staging_buffer = try self.create_buffer(
        buffer_size,
        vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer vk.vmaDestroyBuffer(self.vma_allocator, staging_buffer.buffer, staging_buffer.allocation);

    var buffer_slice: []u8 = undefined;
    buffer_slice.ptr = @ptrCast(staging_buffer.allocation_info.pMappedData);
    buffer_slice.len = buffer_size;
    @memcpy(buffer_slice, data[0..buffer_size]);

    {
        try self.immediate_submit_begin();

        vk.transition_image(
            self.immediate_command_buffer,
            image.image,
            vk.VK_IMAGE_LAYOUT_UNDEFINED,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        );

        const copy_region = vk.VkBufferImageCopy{
            .imageExtent = extent,
            .imageSubresource = .{
                .layerCount = 1,
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
            },
        };

        vk.vkCmdCopyBufferToImage(
            self.immediate_command_buffer,
            staging_buffer.buffer,
            image.image,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &copy_region,
        );

        vk.transition_image(
            self.immediate_command_buffer,
            image.image,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        );

        try self.immediate_submit_end();
    }
}

pub fn create_gpu_mesh(self: *const Self, indices: []const u32, vertices: []const Vertex) !GpuMesh {
    const index_buffer_size = indices.len * @sizeOf(u32);
    const vertex_buffer_size = vertices.len * @sizeOf(Vertex);

    var new_mesh: GpuMesh = undefined;
    new_mesh.index_buffer = try self.create_buffer(
        index_buffer_size,
        vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        vk.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    new_mesh.vertex_buffer = try self.create_buffer(
        vertex_buffer_size,
        vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vk.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    const device_address_info = vk.VkBufferDeviceAddressInfo{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .buffer = new_mesh.vertex_buffer.buffer,
    };
    new_mesh.vertex_device_address = vk.vkGetBufferDeviceAddress(self.vk_logical_device.device, &device_address_info);

    const staging_buffer = try self.create_buffer(
        index_buffer_size + vertex_buffer_size,
        vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vk.VMA_MEMORY_USAGE_CPU_ONLY,
    );
    defer vk.vmaDestroyBuffer(self.vma_allocator, staging_buffer.buffer, staging_buffer.allocation);

    var vertex_buffer_slice: []Vertex = undefined;
    vertex_buffer_slice.ptr = @alignCast(@ptrCast(staging_buffer.allocation_info.pMappedData));
    vertex_buffer_slice.len = vertices.len;
    @memcpy(vertex_buffer_slice, vertices);

    var index_buffer_slice: []u32 = undefined;
    index_buffer_slice.ptr = @alignCast(@as([*]u32, @ptrFromInt(
        @as(usize, @intFromPtr(
            staging_buffer.allocation_info.pMappedData,
        )) + vertex_buffer_size,
    )));
    index_buffer_slice.len = indices.len;
    @memcpy(index_buffer_slice, indices);

    {
        try self.immediate_submit_begin();

        const vertex_copy = vk.VkBufferCopy{
            .dstOffset = 0,
            .srcOffset = 0,
            .size = vertex_buffer_size,
        };
        vk.vkCmdCopyBuffer(self.immediate_command_buffer, staging_buffer.buffer, new_mesh.vertex_buffer.buffer, 1, &vertex_copy);

        const index_copy = vk.VkBufferCopy{
            .dstOffset = 0,
            .srcOffset = vertex_buffer_size,
            .size = index_buffer_size,
        };
        vk.vkCmdCopyBuffer(self.immediate_command_buffer, staging_buffer.buffer, new_mesh.index_buffer.buffer, 1, &index_copy);

        try self.immediate_submit_end();
    }

    return new_mesh;
}

pub fn load_gltf_meshes(self: *Self, path: [:0]const u8) !void {
    std.log.info("Loading gltf mesh from path: {s}", .{path});
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const options = cgltf.cgltf_options{};
    var data: *cgltf.cgltf_data = undefined;
    if (cgltf.cgltf_parse_file(&options, path.ptr, @ptrCast(&data)) != cgltf.cgltf_result_success) {
        return error.cgltf_parse_file_error;
    }
    if (cgltf.cgltf_load_buffers(&options, data, path.ptr) != cgltf.cgltf_result_success) {
        return error.cgltf_load_buffers;
    }

    for (data.meshes[0..data.meshes_count]) |mesh| {
        _ = arena.reset(.retain_capacity);

        var indices: std.ArrayListUnmanaged(u32) = .{};
        var vertices: std.ArrayListUnmanaged(Vertex) = .{};

        std.log.info("Mesh name: {s}", .{mesh.name});
        var mesh_asset: MeshAsset = undefined;
        mesh_asset.name = try self.allocator.dupeZ(u8, std.mem.span(mesh.name));
        mesh_asset.surfaces = try self.allocator.alloc(MeshAsset.SurfaceInfo, mesh.primitives_count);

        for (mesh.primitives[0..mesh.primitives_count], mesh_asset.surfaces) |primitive, *surface| {
            surface.* = .{
                .start_index = @intCast(indices.items.len),
                .count = @intCast(primitive.indices[0].count),
            };
            std.log.info("Surface info: {any}", .{surface});

            const initial_vertex_num = vertices.items.len;
            const initial_index_num = indices.items.len;

            try indices.resize(arena_allocator, initial_index_num + primitive.indices[0].count);
            for (indices.items[initial_index_num..], 0..) |*i, j| {
                const index = cgltf.cgltf_accessor_read_index(primitive.indices, j);
                i.* = @intCast(initial_vertex_num + index);
            }

            try vertices.resize(arena_allocator, vertices.items.len + primitive.attributes[0].data[0].count);

            std.log.info("Mesh primitive type: {}", .{primitive.type});
            for (primitive.attributes[0..primitive.attributes_count]) |attr| {
                std.log.info("Mesh primitive attr name: {s}, type: {}, index: {}, data type: {}, data count: {}", .{
                    attr.name,
                    attr.type,
                    attr.index,
                    attr.data[0].type,
                    attr.data[0].count,
                });
                const num_floats = cgltf.cgltf_accessor_unpack_floats(attr.data, null, 0);
                const floats = try arena_allocator.alloc(f32, num_floats);
                _ = cgltf.cgltf_accessor_unpack_floats(attr.data, floats.ptr, num_floats);

                switch (attr.type) {
                    cgltf.cgltf_attribute_type_position => {
                        const num_components = cgltf.cgltf_num_components(attr.data[0].type);
                        std.log.info("Position has components: {}", .{num_components});
                        std.debug.assert(num_components == 3);

                        var positions: []const Vec3 = undefined;
                        positions.ptr = @ptrCast(floats.ptr);
                        positions.len = floats.len / 3;

                        for (vertices.items[initial_vertex_num..], positions) |*vertex, position| {
                            vertex.position = position;
                        }
                    },
                    cgltf.cgltf_attribute_type_normal => {
                        const num_components = cgltf.cgltf_num_components(attr.data[0].type);
                        std.log.info("Normal has components: {}", .{num_components});
                        std.debug.assert(num_components == 3);

                        var normals: []const Vec3 = undefined;
                        normals.ptr = @ptrCast(floats.ptr);
                        normals.len = floats.len / 3;

                        for (vertices.items[initial_vertex_num..], normals) |*vertex, normal| {
                            vertex.normal = normal;
                        }
                    },
                    cgltf.cgltf_attribute_type_texcoord => {
                        const num_components = cgltf.cgltf_num_components(attr.data[0].type);
                        std.log.info("Tx_coord has components: {}", .{num_components});
                        std.debug.assert(num_components == 2);

                        var uvs: []const Vec2 = undefined;
                        uvs.ptr = @ptrCast(floats.ptr);
                        uvs.len = floats.len / 2;

                        for (vertices.items[initial_vertex_num..], uvs) |*vertex, uv| {
                            vertex.uv_x = uv.x;
                            vertex.uv_y = uv.y;
                        }
                    },
                    else => {
                        std.log.err("Unknown attribute type: {}. Skipping", .{attr.type});
                    },
                }
            }

            // For debugging use normals as colors
            for (vertices.items) |*v| {
                v.color = v.normal.extend(1.0);
            }

            std.log.info("Creating mesh with {} indiced and {} vertices", .{ indices.items.len, vertices.items.len });
            mesh_asset.mesh = try self.create_gpu_mesh(indices.items, vertices.items);
            try self.mesh_assets.append(self.allocator, mesh_asset);
        }
    }

    cgltf.cgltf_free(data);
}

pub fn create_debug_image(self: *Self) !void {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var checkerboard = try arena_allocator.alloc(Color, 16 * 16);
    for (0..16) |x| {
        for (0..16) |y| {
            checkerboard[y * 16 + x] = if ((x % 2) ^ (y % 2) != 0) Color.MAGENTA else Color.BLACK;
        }
    }

    var bytes: []const u8 = undefined;
    bytes.ptr = @ptrCast(checkerboard.ptr);
    bytes.len = checkerboard.len * @sizeOf(Color);

    self.checkerboard_image = try self.create_image(
        16,
        16,
        vk.VK_FORMAT_R8G8B8A8_UNORM,
        vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
    );
    try self.upload_image(&self.checkerboard_image, bytes, vk.VkExtent3D{ .width = 16, .height = 16, .depth = 1 });

    const near_sampler = vk.VkSamplerCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = vk.VK_FILTER_NEAREST,
        .minFilter = vk.VK_FILTER_NEAREST,
    };
    try vk.check_result(vk.vkCreateSampler(self.vk_logical_device.device, &near_sampler, null, &self.nearest_sampler));

    const linear_sampler = vk.VkSamplerCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = vk.VK_FILTER_LINEAR,
        .minFilter = vk.VK_FILTER_LINEAR,
    };
    try vk.check_result(vk.vkCreateSampler(self.vk_logical_device.device, &linear_sampler, null, &self.linear_sampler));
}
