const std = @import("std");
const linux = std.os.linux;
const mem = std.mem;
// const c = std.c;
const print = std.debug.print;
const exit = std.process.exit;

const SDL = @import("SDL.zig");
const VulkanInclude = @import("VulkanInclude.zig");

const globalState = @import("globalState.zig");
const VulkanGlobalState = @import("VulkanGlobalState.zig");
const VK_CHECK = VulkanGlobalState.VK_CHECK;
const WindowGlobalState = @import("WindowGlobalState.zig");

const VkBuffer = @import("VkBuffer.zig");
const VkImage = @import("VkImage.zig");

const initBaseVulkan = @import("initBaseVulkan.zig");
const VkSwapchainKHR = @import("VkSwapchainKHR.zig");
const initVulkan = @import("initVulkan.zig");

const customMem = @import("customMem.zig");
const memcpy = customMem.memcpy;

const algebra = @import("algebra.zig");
const camera = @import("camera.zig");

const DoW2_scenario = @import("DoW2_scenario.zig");
const DoW2_modelset = @import("DoW2_modelset.zig");

pub fn main() !void
{
    globalState.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer globalState.arena.deinit();
    globalState.arenaAllocator = globalState.arena.allocator();
    
//     const argv = std.os.argv;
//     std.debug.print("{s}\n", .{argv[0]});
    
    _ = SDL.SDL_Init(SDL.SDL_INIT_VIDEO);
    defer _ = SDL.SDL_Quit();
    
    WindowGlobalState._window = SDL.SDL_CreateWindow(
        "Vulkan Engine",
        SDL.SDL_WINDOWPOS_UNDEFINED,
        SDL.SDL_WINDOWPOS_UNDEFINED,
        //512, 512,
        @intCast(WindowGlobalState._windowExtent.width),
        @intCast(WindowGlobalState._windowExtent.height),
        WindowGlobalState._window_flags
    );
    defer _ = SDL.SDL_DestroyWindow(WindowGlobalState._window);
    initBaseVulkan.initBaseVulkan();
    defer initBaseVulkan.deinitBaseVulkan();
    VkSwapchainKHR.createVkSwapchainKHR();
    defer VkSwapchainKHR.destroyVkSwapchainKHR();
    VkSwapchainKHR.createDepthResources();
    defer VkSwapchainKHR.destroyDepthResources();
    initVulkan.init_commands();
    defer VulkanInclude.vkDestroyCommandPool(VulkanGlobalState._device, VulkanGlobalState._commandPool, null);
    initVulkan.init_sync_structures();
    defer initVulkan.deinit_sync_structures();
    initVulkan.createTextureSampler();
    defer VulkanInclude.vkDestroySampler(VulkanGlobalState._device, VulkanGlobalState._textureSampler, null);
    camera.createCameraBuffers();
    defer camera.destroyCameraBuffers();
    camera.createCameraVkDescriptorSetLayout();
    defer VulkanInclude.vkDestroyDescriptorSetLayout(VulkanGlobalState._device, camera._cameraDescriptorSetLayout, null);
    camera.createCameraVkDescriptorPool();
    defer VulkanInclude.vkDestroyDescriptorPool(VulkanGlobalState._device, camera._cameraDescriptorPool, null);
    camera.createCameraVkDescriptorSets();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();
    
//     // art/race_chaos/structures/chaos_generator/chaos_generator.model
//     
//     // art/race_chaos/troops/heretic/heretic.model
//     // art/race_chaos/troops_wargear/armour/heretic_common/heretic.model
//     // art/race_chaos/troops_wargear/weapons_ranged/autogun_heretic_common/autogun_heretic_common.model
//     // art/race_chaos/troops_wargear/weapons_ranged/autopistol_heretic_common/autopistol_heretic_common.model
//     // art/race_chaos/troops_wargear/weapons_melee/sword_heretic_common/sword_heretic_common.model
//     
//     // art/race_chaos/troops_wargear/accessories/chaos_marine_backpack_common/chaos_marine_backpack_common.model
//     // art/race_chaos/troops_wargear/armour/chaos_marine_common/chaos_marine_common.model
//     // art/race_chaos/troops_wargear/heads/chaos_marine_common/chaos_marine_common_head.model
// 
    // campaign
        // xp2_a_chapterkeepselenon
        // xp2_c_convoy
        // xp2_cy_prologue
    // 2p_calderisdunes
    // 2p_outerreaches
    // 2p_questsdisaster
//     print("Data/maps/laststand/survive01.scenario\n", .{});
//     _ = linux.chdir("Data_RE");
    var map: DoW2_scenario.Map = undefined;
    try DoW2_scenario.scenarioLoad(arenaAllocator, "Data/maps/laststand/survive01.scenario", &map);
//     try DoW2_scenario.scenarioLoad(arenaAllocator, "Data/maps/campaign/xp2_c_convoy/xp2_c_convoy.scenario", &map);
    //     try DoW2_scenario.scenarioLoad(arenaAllocator, "Data/maps/campaign/xp2_t_ladonswamplands/xp2_t_ladonswamplands.scenario", &map);
//     try DoW2_scenario.scenarioLoad(arenaAllocator, "Data/maps/campaign/xp2_t_ladonswamplands/xp2_t_ladonswamplands.scenario", &map);
//     try DoW2_scenario.scenarioLoad(arenaAllocator, "Data/maps/campaign/calderissettlement/calderissettlement.scenario", &map);
    defer map.unload();
//     _ = linux.chdir("../");
    var mapPipelineLayout: VulkanInclude.VkPipelineLayout = null;
    var mapPipeline: VulkanInclude.VkPipeline = null;
    DoW2_scenario.Create_VkPipeline(map.descriptorSetLayout, &mapPipelineLayout, &mapPipeline);
    defer
    {
        VulkanInclude.vkDestroyPipeline(VulkanGlobalState._device, mapPipeline, null);
        VulkanInclude.vkDestroyPipelineLayout(VulkanGlobalState._device, mapPipelineLayout, null);
    }
    var e: SDL.SDL_Event = undefined;
    var bQuit: bool = false;
//     bQuit = true;
    var windowPresent: bool = true;
    
    var currentFrame: usize = 0;
    // var swapchainImageIndex: u32 = undefined;
    while (!bQuit)
    {
        //Handle events on queue
        while (SDL.SDL_PollEvent(&e) != 0)
        {
            switch(e.type)
            {
                SDL.SDL_QUIT =>
                {
                    bQuit = true;
                },
                SDL.SDL_WINDOWEVENT =>
                {
                    switch(e.window.event)
                    {
                        SDL.SDL_WINDOWEVENT_SHOWN =>
                        {
                            windowPresent = true;
                        },
                        SDL.SDL_WINDOWEVENT_HIDDEN =>
                        {
                            windowPresent = false;
                        },
                        else =>{}
                    }
                },
                SDL.SDL_KEYDOWN =>
                {
                    switch(e.key.keysym.scancode)
                    {
                        // камера
                        SDL.SDL_SCANCODE_D =>
                        {
                            camera.camera_translate_x+=8;
                        },
                        SDL.SDL_SCANCODE_A =>
                        {
                            camera.camera_translate_x-=8;
                        },
                        // Y
                        SDL.SDL_SCANCODE_W =>
                        {
                            camera.camera_translate_z+=8;
                        },
                        SDL.SDL_SCANCODE_S =>
                        {
                            camera.camera_translate_z-=8;
                        },
                        // Z
                        SDL.SDL_SCANCODE_E =>
                        {
                            camera.camera_translate_y+=8;
                        },
                        SDL.SDL_SCANCODE_Q =>
                        {
                            camera.camera_translate_y-=8;
                        },
                        // повороты
                        SDL.SDL_SCANCODE_UP =>
                        {
                            camera.camera_rotate_x-=5;
                        },
                        SDL.SDL_SCANCODE_DOWN =>
                        {
                            camera.camera_rotate_x+=5;
                        },
                        SDL.SDL_SCANCODE_LEFT =>
                        {
                            camera.camera_rotate_z-=5;
                        },
                        SDL.SDL_SCANCODE_RIGHT =>
                        {
                            camera.camera_rotate_z+=5;
                        },
                        else =>{}
                    }
                },
                else =>{}
            }
        }
        if (!windowPresent)//SDL_GetWindowFlags(_window) & SDL_WINDOW_MINIMIZED
        {
            SDL.SDL_Delay(50);
        }
        else
        {
            //wait until the gpu has finished rendering the last frame
            VK_CHECK(VulkanInclude.vkWaitForFences(VulkanGlobalState._device, 1, &VulkanGlobalState._renderFences[currentFrame], VulkanInclude.VK_TRUE, VulkanInclude.UINT64_MAX));
            //request image from the swapchain
            var swapchainImageIndex: u32 = undefined;
            var result: VulkanInclude.VkResult = undefined;
            //VK_CHECK
            result = (VulkanInclude.vkAcquireNextImageKHR(VulkanGlobalState._device, VulkanGlobalState._swapchain, VulkanInclude.UINT64_MAX, VulkanGlobalState._presentSemaphores[currentFrame], null, &swapchainImageIndex));
            if (result == VulkanInclude.VK_ERROR_OUT_OF_DATE_KHR)
            {
                VkSwapchainKHR.recreateVkSwapchainKHR();
            }
            else if (result != VulkanInclude.VK_SUCCESS and result != VulkanInclude.VK_SUBOPTIMAL_KHR)
            {
                print("failed to acquire swap chain image!\n", .{});
                std.process.exit(0);
            }
            camera.updateCameraBuffer(currentFrame);
            VK_CHECK(VulkanInclude.vkResetFences(VulkanGlobalState._device, 1, &VulkanGlobalState._renderFences[currentFrame]));
            //now that we are sure that the commands finished executing, we can safely reset the command buffer to begin recording again.
            VK_CHECK(VulkanInclude.vkResetCommandBuffer(VulkanGlobalState._commandBuffers[currentFrame], 0));
            //begin the command buffer recording. We will use this command buffer exactly once, so we want to let Vulkan know that
            const cmdBeginInfo = VulkanInclude.VkCommandBufferBeginInfo
            {
                .sType = VulkanInclude.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .flags = VulkanInclude.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            };
            VK_CHECK(VulkanInclude.vkBeginCommandBuffer(VulkanGlobalState._commandBuffers[currentFrame], &cmdBeginInfo));
            const image_memory_barrierBegin = VulkanInclude.VkImageMemoryBarrier
            {
                .sType = VulkanInclude.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                .dstAccessMask = VulkanInclude.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                .oldLayout = VulkanInclude.VK_IMAGE_LAYOUT_UNDEFINED,
                .newLayout = VulkanInclude.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                .image = VulkanGlobalState._swapchainImages[swapchainImageIndex],
                .subresourceRange = VulkanInclude.VkImageSubresourceRange
                {
                    .aspectMask = VulkanInclude.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                }
            };
            VulkanInclude.vkCmdPipelineBarrier(
                VulkanGlobalState._commandBuffers[currentFrame],
                VulkanInclude.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,  // srcStageMask
                VulkanInclude.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, // dstStageMask
                0,
                0,
                null,
                0,
                null,
                1, // imageMemoryBarrierCount
                &image_memory_barrierBegin // pImageMemoryBarriers
            );
            const clearValue = VulkanInclude.VkClearValue
            {
                .color = VulkanInclude.VkClearColorValue
                {
                    .float32 = [4]f32{0.5, 0.5, 1.0, 1.0},
                },
            };
            const depthClear = VulkanInclude.VkClearValue
            {
                .depthStencil = VulkanInclude.VkClearDepthStencilValue
                {
                    .depth = 1.0,
                }
            };
            const renderArea = VulkanInclude.VkRect2D
            {
                .offset = VulkanInclude.VkOffset2D{.x = 0, .y = 0},
                .extent = WindowGlobalState._windowExtent,
            };
            // VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR
            const colorAttachmentInfo = VulkanInclude.VkRenderingAttachmentInfoKHR
            {
                .sType = VulkanInclude.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO_KHR,
                .imageView = VulkanGlobalState._swapchainImageViews[swapchainImageIndex],
                .imageLayout = VulkanInclude.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                .loadOp = VulkanInclude.VK_ATTACHMENT_LOAD_OP_CLEAR,
                .storeOp = VulkanInclude.VK_ATTACHMENT_STORE_OP_STORE,
                .clearValue = clearValue,
            };
            const depthAttachmentInfo = VulkanInclude.VkRenderingAttachmentInfoKHR
            {
                .sType = VulkanInclude.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO_KHR,
                .imageView = VulkanGlobalState._depthImageView,
                .imageLayout = VulkanInclude.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,//VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
                .loadOp = VulkanInclude.VK_ATTACHMENT_LOAD_OP_CLEAR,
                .storeOp = VulkanInclude.VK_ATTACHMENT_STORE_OP_STORE,
                .clearValue = depthClear,
            };
            const renderInfo = VulkanInclude.VkRenderingInfoKHR
            {
                .sType = VulkanInclude.VK_STRUCTURE_TYPE_RENDERING_INFO_KHR,
                .renderArea = renderArea,
                .layerCount = 1,
                .colorAttachmentCount = 1,
                .pColorAttachments = &colorAttachmentInfo,
                .pDepthAttachment = &depthAttachmentInfo,
            };
            VulkanInclude.vkCmdBeginRenderingKHR(VulkanGlobalState._commandBuffers[currentFrame], &renderInfo);
            const viewport = VulkanInclude.VkViewport
            {
                .x = 0.0,
                .y = 0.0,
                .width = @floatFromInt(WindowGlobalState._windowExtent.width),
                .height = @floatFromInt(WindowGlobalState._windowExtent.height),
                .minDepth = 0.0,
                .maxDepth = 1.0,
            };
            VulkanInclude.vkCmdSetViewport(VulkanGlobalState._commandBuffers[currentFrame], 0, 1, &viewport);
            const scissor = VulkanInclude.VkRect2D
            {
                .offset = VulkanInclude.VkOffset2D{.x = 0, .y = 0},
                .extent = WindowGlobalState._windowExtent,
            };
            VulkanInclude.vkCmdSetScissor(VulkanGlobalState._commandBuffers[currentFrame], 0, 1, &scissor);
            
            VulkanInclude.vkCmdBindPipeline(VulkanGlobalState._commandBuffers[currentFrame], VulkanInclude.VK_PIPELINE_BIND_POINT_GRAPHICS, mapPipeline);
            
            const offsets = [_]VulkanInclude.VkDeviceSize{0};
            
            VulkanInclude.vkCmdBindVertexBuffers(VulkanGlobalState._commandBuffers[currentFrame], 0, 1, &map.vertexVkBuffer, &offsets);
            VulkanInclude.vkCmdBindIndexBuffer(VulkanGlobalState._commandBuffers[currentFrame], map.indexVkBuffer, 0, VulkanInclude.VK_INDEX_TYPE_UINT32);
            
            var descriptorSets: [2]VulkanInclude.VkDescriptorSet = undefined;
            descriptorSets[0] = camera._cameraDescriptorSets[currentFrame];
            descriptorSets[1] = map.descriptorSet;
            
            VulkanInclude.vkCmdBindDescriptorSets(VulkanGlobalState._commandBuffers[currentFrame], VulkanInclude.VK_PIPELINE_BIND_POINT_GRAPHICS, mapPipelineLayout, 0, 2, &descriptorSets, 0, null);
            const pushConstants = [2]i32{map.width-1, map.height-1};
            VulkanInclude.vkCmdPushConstants(VulkanGlobalState._commandBuffers[currentFrame], mapPipelineLayout, VulkanInclude.VK_SHADER_STAGE_VERTEX_BIT | VulkanInclude.VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8, &pushConstants);
            VulkanInclude.vkCmdDrawIndexed(VulkanGlobalState._commandBuffers[currentFrame], map.indicesCount, 1, 0, 0, 0);
//             VulkanInclude.vkCmdDrawIndexed(VulkanGlobalState._commandBuffers[currentFrame], AoW4_meshes_temp[@intCast(AoW4_meshIndex)].indicesBufferSize>>1, 1, 0, 0, 0);
            
            VulkanInclude.vkCmdEndRenderingKHR(VulkanGlobalState._commandBuffers[currentFrame]);
            const imageMemoryBarrierEnd = VulkanInclude.VkImageMemoryBarrier
            {
                .sType = VulkanInclude.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
                .srcAccessMask = VulkanInclude.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                .oldLayout = VulkanInclude.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                .newLayout = VulkanInclude.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                .image = VulkanGlobalState._swapchainImages[swapchainImageIndex],
                .subresourceRange = VulkanInclude.VkImageSubresourceRange
                {
                    .aspectMask = VulkanInclude.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                }
            };
            VulkanInclude.vkCmdPipelineBarrier(
                VulkanGlobalState._commandBuffers[currentFrame],
                VulkanInclude.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,  // srcStageMask
                VulkanInclude.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, // dstStageMask
                0,
                0,
                null,
                0,
                null,
                1, // imageMemoryBarrierCount
                &imageMemoryBarrierEnd // pImageMemoryBarriers
            );
            //finalize the command buffer (we can no longer add commands, but it can now be executed)
            VK_CHECK(VulkanInclude.vkEndCommandBuffer(VulkanGlobalState._commandBuffers[currentFrame]));
            
            //prepare the submission to the queue.
            //we want to wait on the _presentSemaphores[_currentFrame], as that semaphore is signaled when the swapchain is ready
            //we will signal the _renderSemaphores[_currentFrame], to signal that rendering has finished
            
            //VkSemaphore waitSemaphores[] = _presentSemaphores[_currentFrame];
            var waitStage: u32 = VulkanInclude.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
            const submitInfo = VulkanInclude.VkSubmitInfo
            {
                .sType = VulkanInclude.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .pWaitDstStageMask = &waitStage,
                
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &VulkanGlobalState._presentSemaphores[currentFrame],
                
                .signalSemaphoreCount = 1,
                .pSignalSemaphores = &VulkanGlobalState._renderSemaphores[currentFrame],
                
                .commandBufferCount = 1,
                .pCommandBuffers = &VulkanGlobalState._commandBuffers[currentFrame],
            };
            //submit command buffer to the queue and execute it.
            // _renderFence will now block until the graphic commands finish execution
            VK_CHECK(VulkanInclude.vkQueueSubmit(VulkanGlobalState._graphicsQueue, 1, &submitInfo, VulkanGlobalState._renderFences[currentFrame]));
            
            // this will put the image we just rendered into the visible window.
            // we want to wait on the _renderSemaphores[_currentFrame] for that,
            // as it's necessary that drawing commands have finished before the image is displayed to the user
            const presentInfo = VulkanInclude.VkPresentInfoKHR
            {
                .sType = VulkanInclude.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .pSwapchains = &VulkanGlobalState._swapchain,
                .swapchainCount = 1,
                .pWaitSemaphores = &VulkanGlobalState._renderSemaphores[currentFrame],
                .waitSemaphoreCount = 1,
                .pImageIndices = &swapchainImageIndex,
            };
            //VK_CHECK
            result = (VulkanInclude.vkQueuePresentKHR(VulkanGlobalState._graphicsQueue, &presentInfo));
            if (result == VulkanInclude.VK_ERROR_OUT_OF_DATE_KHR or result == VulkanInclude.VK_SUBOPTIMAL_KHR)
                VkSwapchainKHR.recreateVkSwapchainKHR();
            
            currentFrame+=1;
            if(currentFrame == VulkanGlobalState.FRAME_OVERLAP)
                currentFrame = 0;
        }
    }
    //make sure the gpu has stopped doing its things
    _ = VulkanInclude.vkDeviceWaitIdle(VulkanGlobalState._device);
    
}
