const std = @import("std");
const print = std.debug.print;
const exit = std.process.exit;

const VulkanInclude = @import("VulkanInclude.zig");

const VulkanGlobalState = @import("VulkanGlobalState.zig");
const VK_CHECK = VulkanGlobalState.VK_CHECK;

const customMem = @import("customMem.zig");
const memcpy = customMem.memcpy;
const memcpyDstAlign = customMem.memcpyDstAlign;

const VkBuffer = @import("VkBuffer.zig");
const VkImage = @import("VkImage.zig");

const Image = @import("Image.zig");
const algebra = @import("algebra.zig");
const dds_load = @import("dds_load.zig").dds_load;

const DoW2_Chunk = @import("DoW2_Chunk.zig");

const Model = struct
{
    const Material = struct
    {
        texture: Image.Image,
    };
    const Mesh = struct
    {
        pub const Vertex = struct
        {
            position: algebra.vec3,
            //                 normal: algebra.vec3,
            //                 binormal: algebra.vec3,
            //                 tangent: algebra.vec3,
            uv: algebra.vec2,
        };
        vertices: [*]Vertex,
        indices: [*]u16,
        verticesBufferSize: u32,
        indicesBufferSize: u32,
        vertexSize: u8,
        verticesCount: u16,
        indicesCount: u16,
        //         verticesBufferSize: u16,
        //         indicesBufferSize: u16,
    };
    materials: [*]Material,
    meshes: [*]Mesh,
    materialsCount: u8,
    meshesCount: u8,
};
pub fn modelsetImport(arenaAllocator: std.mem.Allocator, modelsetPtr: *Modelset) !void
{
    
    //     _ = modelsetPtr;
    const modelsetFile: std.fs.File = try std.fs.cwd().openFileZ("Modelset.txt", .{});
    defer modelsetFile.close();
    const stat = modelsetFile.stat() catch unreachable;
    const modelsetFileSize: usize = stat.size;
    const modelsetFileBuffer: [*]u8 = (arenaAllocator.alignedAlloc(u8, customMem.alingment, modelsetFileSize) catch unreachable).ptr;
    _ = modelsetFile.read(modelsetFileBuffer[0..modelsetFileSize]) catch unreachable;
    var modelsCount: usize = 0;
    for(0..stat.size) |bufferIndex|
    {
        if(modelsetFileBuffer[bufferIndex] == '\n')
        {
            modelsCount+=1;
            modelsetFileBuffer[bufferIndex] = 0;
        }
    }
    var models: [*]Model = (arenaAllocator.alloc(Model, modelsCount) catch unreachable).ptr;
    modelsetPtr.models  = (arenaAllocator.alloc(Modelset.Model, modelsCount) catch unreachable).ptr;
    var modelsetFileBufferPtr: [*]u8 = modelsetFileBuffer;
    for(0..modelsCount) |modelIndex|
    {
        //         _ = modelNameIndex;
        var nameLength: usize = 0;
        const modelsetFileBufferPtrStart = modelsetFileBufferPtr;
        while(modelsetFileBufferPtr[0] != 0)
        {
            nameLength+=1;
            modelsetFileBufferPtr+=1;
        }
        print("{s}\n", .{modelsetFileBufferPtrStart[0..nameLength]});
        try modelImport(arenaAllocator, @ptrCast(modelsetFileBufferPtrStart), &models[modelIndex]);
        modelsetPtr.models[modelIndex].materialsCount = models[modelIndex].materialsCount;
        modelsetPtr.models[modelIndex].meshesCount = models[modelIndex].meshesCount;
        modelsetPtr.models[modelIndex].materials = (arenaAllocator.alloc(Modelset.Model.Material, models[modelIndex].materialsCount) catch unreachable).ptr;
        modelsetPtr.models[modelIndex].meshes = (arenaAllocator.alloc(Modelset.Model.Mesh, models[modelIndex].meshesCount) catch unreachable).ptr;
        //         print("{d}\n", .{@intFromPtr(modelsetPtr.models[modelIndex].materials) % 8});
        //         print("{d}\n", .{@intFromPtr(modelsetPtr.models) % 8});
        //         exit(0);
        // Loading on GPU
        VkImage.createVkImages__VkImageViews__VkDeviceMemory_AoS(@as([*]u8, @ptrCast(@alignCast(models[modelIndex].materials))), @sizeOf(Model.Material), @as([*]u8, @ptrCast(@alignCast(modelsetPtr.models[modelIndex].materials)))+@offsetOf(Modelset.Model.Material, "vkImage"), @sizeOf(Modelset.Model.Material), models[modelIndex].materialsCount, &modelsetPtr.models[modelIndex].texturesVkDeviceMemory);
        VkBuffer.createVkBuffers__VkDeviceMemory_AoS(VulkanInclude.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, @as([*]u8, @ptrCast(@alignCast(models[modelIndex].meshes)))+0, @sizeOf(Model.Mesh), @offsetOf(Model.Mesh, "verticesBufferSize"), @as([*]u8, @ptrCast(@alignCast(modelsetPtr.models[modelIndex].meshes)))+@offsetOf(Modelset.Model.Mesh, "vertexVkBuffer"), @sizeOf(Modelset.Model.Mesh), modelsetPtr.models[modelIndex].meshesCount, &modelsetPtr.models[modelIndex].vertexVkDeviceMemory);
        VkBuffer.createVkBuffers__VkDeviceMemory_AoS(VulkanInclude.VK_BUFFER_USAGE_INDEX_BUFFER_BIT, @as([*]u8, @ptrCast(@alignCast(models[modelIndex].meshes)))+8, @sizeOf(Model.Mesh), @offsetOf(Model.Mesh, "indicesBufferSize")-8, @as([*]u8, @ptrCast(@alignCast(modelsetPtr.models[modelIndex].meshes)))+@offsetOf(Modelset.Model.Mesh, "indexVkBuffer"), @sizeOf(Modelset.Model.Mesh), modelsetPtr.models[modelIndex].meshesCount, &modelsetPtr.models[modelIndex].indexVkDeviceMemory);
        //         modelsetFileBufferPtr+=1;
    }
}
pub fn modelImport(arenaAllocator: std.mem.Allocator, path: [*:0]const u8, modelPtr: *Model) !void
{
    //     _ = modelPtr;
    //     var model: Modelset.Model = undefined;
    //     defer modelPtr.* = model;
    
    const modelFile: std.fs.File = try std.fs.cwd().openFileZ(path, .{});
    defer modelFile.close();
    
    const stat = modelFile.stat() catch unreachable;
    const modelFileSize: usize = stat.size;
    const modelFileBuffer: [*]u8 = (arenaAllocator.alignedAlloc(u8, customMem.alingment, modelFileSize) catch unreachable).ptr;
    _ = modelFile.read(modelFileBuffer[0..modelFileSize]) catch unreachable;
    
    var fileBufferPtrIterator = modelFileBuffer;
    // skip Relic Chunky
    fileBufferPtrIterator+=36;
    //     var ChunkBuffer: Chunk = undefined;
    DoW2_Chunk.printChunkHierarchy(fileBufferPtrIterator, 0);
    // FOLDMODL
    const FOLDMODL = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
    print("{s}\n", .{FOLDMODL.string[0..FOLDMODL.len]});
    // FOLDMTRL
    const FOLDMTRL_count: usize = DoW2_Chunk.childChunkCount(FOLDMODL, .{'M', 'T', 'R', 'L'});
    print("materialCount: {d}\n", .{FOLDMTRL_count});
    modelPtr.materialsCount = @intCast(FOLDMTRL_count);
    modelPtr.materials = (arenaAllocator.alloc(Model.Material, FOLDMTRL_count) catch unreachable).ptr;
    for(0..FOLDMTRL_count) |FOLDMTRL_index|
    {
        //         _ = FOLDMTRL_index;
        const FOLDMTRL = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
        print("    {s}\n", .{FOLDMTRL.string[0..FOLDMTRL.len]});
        // DATAINFO
        const DATAINFO = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
        _ = DATAINFO;
        const materialTypeLength: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
        fileBufferPtrIterator+=4;
        print("    {s}\n", .{fileBufferPtrIterator[0..materialTypeLength]});
        fileBufferPtrIterator+=materialTypeLength;
        // DATAVAR
        while(@as(u32, @bitCast(fileBufferPtrIterator[4..8].*)) == @as(u32, @bitCast([4]u8{0,'V','A','R'})))
        {
            const DATAVAR = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
            //             _ = DATAVAR;
            const varNameLength: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
            fileBufferPtrIterator+=4;
            //             const varNamePtr = fileBufferPtrIterator;
            print("        {s}\n", .{fileBufferPtrIterator[0..varNameLength]});
            fileBufferPtrIterator+=varNameLength;
            const varType: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
            fileBufferPtrIterator+=4;
            //             _ = varType;
            const varSize: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
            fileBufferPtrIterator+=4;
            //             _ = varSize;
            if(varType == 9)
            {
                //                 print("            {s}\n", .{fileBufferPtrIterator[0..varSize]});
                var namePathStack: [256]u8 align(customMem.alingment) = undefined;
                customMem.memcpyDstAlign(&namePathStack, fileBufferPtrIterator, varSize);
                for(0..varSize) |byteIndex|
                {
                    if(namePathStack[byteIndex] == '\\')
                        namePathStack[byteIndex] = '/';
                }
                namePathStack[varSize-1] = '.';
                namePathStack[varSize] = 'd';
                namePathStack[varSize+1] = 'd';
                namePathStack[varSize+2] = 's';
                namePathStack[varSize+3] = 0;
                print("            {s}\n", .{namePathStack[0..varSize+3]});
                const textureTypePtr = fileBufferPtrIterator+varSize-4;
                if(@as(u32, @bitCast(textureTypePtr[0..4].*)) == @as(u32, @bitCast([4]u8{'d','i','f', 0})))
                {
                    dds_load(arenaAllocator, &namePathStack, &modelPtr.materials[FOLDMTRL_index].texture);
                }
                //                 var namePathStack: [256]u8 align(8) = undefined;
                //                 customMem.memcpyDstAlign(&namePathStack, fileBufferPtrIterator, varSize);
            }
            //             else {print("\n", .{});}
            //             const textureLength: usize = mem.bytesToValue(u32, fileBufferPtrIterator);
            //             fileBufferPtrIterator+=4;
            //             print("    {s}\n", .{fileBufferPtrIterator[0..varNameLength]});
            //             fileBufferPtrIterator+=varNameLength;
            fileBufferPtrIterator = DATAVAR.data+DATAVAR.size;
        }
        //         print("{x}\n", .{@intFromPtr(fileBufferPtrIterator) - @intFromPtr(modelFileBuffer)});
        fileBufferPtrIterator = FOLDMTRL.data+FOLDMTRL.size;
    }
    // FOLDMESH
    const FOLDMESH = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
    //     _ = FOLDMESH;
    // підрахунок кількості lod0 мешів
    {
        // FOLDMGRP
        const FOLDMGRP = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
        _ = FOLDMGRP;
        // FOLDMESH
        //         const FOLDMESH_foldmgrpCount = childChunkCount(FOLDMGRP, [4]u8{'M','E','S','H'});
        //         _ = FOLDMESH_foldmgrpCount;
        const FOLDMESH_foldmgrp = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
        _ = FOLDMESH_foldmgrp;
        const FOLDIMDG = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
        _ = FOLDIMDG;
        const FOLDMESH_foldimdg = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
        _ = FOLDMESH_foldimdg;
        const FOLDIMOD = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
        //                 _ = FOLDIMOD;
        // DATADATA
        DoW2_Chunk.chunkSkipHeader(&fileBufferPtrIterator);
        fileBufferPtrIterator+=4;
        const FOLDMESH_foldimodCount = DoW2_Chunk.childChunkCount(FOLDIMOD, [4]u8{'M','E','S','H'});
        modelPtr.meshesCount = @intCast(FOLDMESH_foldimodCount);
        print("meshesCount: {d}\n", .{FOLDMESH_foldimodCount});
        modelPtr.meshes = (arenaAllocator.alloc(Model.Mesh, FOLDMESH_foldimodCount) catch unreachable).ptr;
    }
    fileBufferPtrIterator = FOLDMESH.data;
    {
        // FOLDMGRP
        const FOLDMGRP = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
        //         _ = FOLDMGRP;
        // FOLDMESH
        const FOLDMESH_foldmgrpCount = DoW2_Chunk.childChunkCount(FOLDMGRP, [4]u8{'M','E','S','H'});
        //         _ = FOLDMESH_foldmgrpCount;
        for(0..FOLDMESH_foldmgrpCount) |FOLDMESH_foldmgrpIndex|
        {
            _ = FOLDMESH_foldmgrpIndex;
            const FOLDMESH_foldmgrp = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
            // //             _ = FOLDMESH_foldmgrp;
            const FOLDIMDG = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
            // //             //             _ = FOLDIMDG;
            const FOLDMESH_foldimdgCount = DoW2_Chunk.childChunkCount(FOLDIMDG, [4]u8{'M','E','S','H'});
            //             print("{d}\n", .{FOLDMESH_foldimdgCount});
            for(0..FOLDMESH_foldimdgCount) |FOLDMESH_foldimdgIndex|
            {
                _ = FOLDMESH_foldimdgIndex;
                const FOLDMESH_foldimdg = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
                //                 _ = FOLDMESH_foldimdg;
                // FOLDIMOD
                const FOLDIMOD = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
                print("    {x}\n", .{@intFromPtr(fileBufferPtrIterator) - @intFromPtr(modelFileBuffer)});
                print("    {s}\n", .{FOLDIMOD.string[0..FOLDIMOD.len]});
                // DATADATA
                DoW2_Chunk.chunkSkipHeader(&fileBufferPtrIterator);
                // //                 //                 const lodlevel: usize = mem.bytesToValue(u32, fileBufferPtrIterator);
                // //                 //                 _ = lodlevel;
                fileBufferPtrIterator+=4;
                const FOLDMESH_foldimodCount = DoW2_Chunk.childChunkCount(FOLDIMOD, [4]u8{'M','E','S','H'});
                for(0..FOLDMESH_foldimodCount) |FOLDMESH_foldimodIndex|
                {
                    //                     _ = FOLDMESH_foldimodIndex;
                    const FOLDMESH_foldimod = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
                    const FOLDTRIM = DoW2_Chunk.ChunkReadHeader(&fileBufferPtrIterator);
                    _ = FOLDTRIM;
                    //                     print("        {s}\n", .{FOLDTRIM.string[0..FOLDTRIM.len]});
                    // DATADATA
                    DoW2_Chunk.chunkSkipHeader(&fileBufferPtrIterator);
                    const numVertexElements: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
                    //                     print("numVertexElements: {d}\n", .{numVertexElements});
                    fileBufferPtrIterator+=4;
                    const VertexElement = struct
                    {
                        type: u32,
                        //                         version: u32,
                        dataType: u32,
                    };
                    var vertexElements: [10]VertexElement = undefined;
                    for(vertexElements[0..numVertexElements]) |*vertexElement|
                        vertexElement.dataType = 0;
                    for(0..numVertexElements) |vertexElementIndex|
                    {
                        _ = vertexElementIndex;
                        const data = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
                        vertexElements[data].type = data;
                        vertexElements[data].dataType = @as(u32, @bitCast(fileBufferPtrIterator[8..12].*));
                        fileBufferPtrIterator+=12;
                    }
                    // Read vertices
                    const verticesCount: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
                    fileBufferPtrIterator+=4;
                    print("        verticesCount: {d}\n", .{verticesCount});
                    const meshPtr = &modelPtr.meshes[FOLDMESH_foldimodIndex];
                    //                     const vertSize: usize = mem.bytesToValue(u32, fileBufferPtrIterator);
                    fileBufferPtrIterator+=4;
                    meshPtr.verticesCount = @intCast(verticesCount);
                    meshPtr.vertices = (arenaAllocator.alloc(Model.Mesh.Vertex
                    , verticesCount*20) catch unreachable).ptr;
                    meshPtr.verticesBufferSize = @intCast(verticesCount*20);
                    //                     print("        vertSize: {d}\n", .{vertSize});
                    
                    for(0..verticesCount) |verticesIndex|
                    {
                        //                         _ = verticesIndex;
                        const vertexPtr = &meshPtr.vertices[verticesIndex];
                        // position
                        if(vertexElements[0].dataType != 0)
                        {
                            memcpy(@ptrCast(&vertexPtr.position), fileBufferPtrIterator, 12);
                            fileBufferPtrIterator+=12;
                        }
                        // blendIndices
                        if(vertexElements[1].dataType != 0)
                        {
                            fileBufferPtrIterator+=4;
                        }
                        // blendWeights
                        if(vertexElements[2].dataType != 0)
                        {
                            fileBufferPtrIterator+=4;
                        }
                        // normals
                        if(vertexElements[3].dataType != 0)
                        {
                            switch(vertexElements[3].dataType)
                            {
                                2 =>
                                {
                                    fileBufferPtrIterator+=4;
                                },
                                4 =>
                                {
                                    fileBufferPtrIterator+=12;
                                },
                                else => unreachable
                            }
                        }
                        // binormals
                        if(vertexElements[4].dataType != 0)
                        {
                            switch(vertexElements[4].dataType)
                            {
                                2 =>
                                {
                                    fileBufferPtrIterator+=4;
                                },
                                4 =>
                                {
                                    fileBufferPtrIterator+=12;
                                },
                                else => unreachable
                            }
                        }
                        // tangent
                        if(vertexElements[5].dataType != 0)
                        {
                            switch(vertexElements[5].dataType)
                            {
                                2 =>
                                {
                                    fileBufferPtrIterator+=4;
                                },
                                4 =>
                                {
                                    fileBufferPtrIterator+=12;
                                },
                                else => unreachable
                            }
                        }
                        // color
                        if(vertexElements[6].dataType != 0)
                        {
                            fileBufferPtrIterator+=4;
                        }
                        // UV
                        //                         vertexPtr.uv.data = @as([2]f32, @bitCast(fileBufferPtrIterator[0..8].*));
                        @as(*align(1)u64, @ptrCast(&vertexPtr.uv.data)).* = @as(*align(1)u64, @ptrCast(fileBufferPtrIterator)).*;
                        fileBufferPtrIterator+=8;
                    }
                    // Read faces
                    fileBufferPtrIterator+=8;
                    const vertPerFace: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
                    fileBufferPtrIterator+=4;
                    if(vertPerFace != 3)
                        exit(0);
                    const indicesCount: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
                    fileBufferPtrIterator+=4;
                    print("        indicesCount: {d}\n", .{indicesCount});
                    meshPtr.indicesCount = @intCast(indicesCount);
                    meshPtr.indicesBufferSize = @intCast(indicesCount*2);
                    meshPtr.indices = (arenaAllocator.alloc(u16, indicesCount) catch unreachable).ptr;
                    memcpy(@ptrCast(meshPtr.indices), fileBufferPtrIterator, indicesCount*2);
                    fileBufferPtrIterator+=indicesCount*2;
                    const materialNameLength: usize  = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
                    fileBufferPtrIterator+=4;
                    print("        {s}\n", .{fileBufferPtrIterator[0..materialNameLength]});
                    fileBufferPtrIterator+=materialNameLength;
                    // Read skin
                    const skinBonesCount: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
                    fileBufferPtrIterator+=4;
                    print("        skinBonesCount: {d}\n", .{skinBonesCount});
                    print("\n", .{});
                    for(0..skinBonesCount) |skinBoneIndex|
                    {
                        _ = skinBoneIndex;
                        fileBufferPtrIterator+=24*4;
                        const skinBoneNameLength: usize = @as(u32, @bitCast(fileBufferPtrIterator[0..4].*));
                        fileBufferPtrIterator+=4;
                        fileBufferPtrIterator+=skinBoneNameLength;
                        //                         break;
                    }
                    fileBufferPtrIterator+=8;//unknown
                    // //                     print("        {x}\n", .{@intFromPtr(fileBufferPtrIterator) - @intFromPtr(fileBuffer)});
                    fileBufferPtrIterator = FOLDMESH_foldimod.data+FOLDMESH_foldimod.size;
                    // //                     //                     break;
                }
                fileBufferPtrIterator = FOLDMESH_foldimdg.data+FOLDMESH_foldimdg.size;
                //                 break;
            }
            fileBufferPtrIterator = FOLDMESH_foldmgrp.data+FOLDMESH_foldmgrp.size;
            break;
        }
        fileBufferPtrIterator = FOLDMESH.data+FOLDMESH.size;
    }
    //     fileBufferPtrIterator = FOLDMESH.data+FOLDMESH.size;
    // Loading on GPU
    //     VkImage.createVkImages__VkImageViews__VkDeviceMemory_AoS((@as([*]u8, @ptrCast(@alignCast(modelPtr.materials)))), );
}

pub const Modelset = struct
{
    pub const Model = struct
    {
        pub const Material = struct
        {
            vkImage: VulkanInclude.VkImage,
            vkImageView: VulkanInclude.VkImageView,
            descriptorSet: VulkanInclude.VkDescriptorSet = undefined,
            
            pub fn unload(self: Material) void
            {
                VulkanInclude.vkDestroyImage(VulkanGlobalState._device, self.vkImage, null);
                VulkanInclude.vkDestroyImageView(VulkanGlobalState._device, self.vkImageView, null);
            }
        };
        pub const Mesh = struct
        {
            pub const Vertex = struct
            {
                position: algebra.vec3,
                //                 normal: algebra.vec3,
                //                 binormal: algebra.vec3,
                //                 tangent: algebra.vec3,
                uv: algebra.vec2,
            };
            indicesCount: u16,
            vertexVkBuffer: VulkanInclude.VkBuffer,
            indexVkBuffer: VulkanInclude.VkBuffer,
            pub fn unload(self: Mesh) void
            {
                VulkanInclude.vkDestroyBuffer(VulkanGlobalState._device, self.vertexVkBuffer, null);
                VulkanInclude.vkDestroyBuffer(VulkanGlobalState._device, self.indexVkBuffer, null);
            }
        };
        materials: [*]Material,
        meshes: [*]Mesh,
        materialsCount: u8,
        meshesCount: u8,
        texturesVkDeviceMemory: VulkanInclude.VkDeviceMemory,
        vertexVkDeviceMemory: VulkanInclude.VkDeviceMemory,
        indexVkDeviceMemory: VulkanInclude.VkDeviceMemory,
        pub fn unload(self: Modelset.Model) void
        {
            for(0..self.materialsCount) |materialIndex|
                self.materials[materialIndex].unload();
            for(0..self.meshesCount) |meshIndex|
                self.meshes[meshIndex].unload();
            VulkanInclude.vkFreeMemory(VulkanGlobalState._device, self.texturesVkDeviceMemory, null);
            VulkanInclude.vkFreeMemory(VulkanGlobalState._device, self.vertexVkDeviceMemory, null);
            VulkanInclude.vkFreeMemory(VulkanGlobalState._device, self.indexVkDeviceMemory, null);
        }
    };
    models: [*]Modelset.Model,
    modelsCount: u8,
};

pub fn Create_VkDescriptorSetLayout(descriptorSetLayout: *VulkanInclude.VkDescriptorSetLayout) void
{
    const descriptorSetLayoutBindings = [1]VulkanInclude.VkDescriptorSetLayoutBinding
    {
        .{
            .binding = 1,
            .descriptorCount = 1,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImmutableSamplers = null,
            .stageFlags = VulkanInclude.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
    };
    const layoutInfo = VulkanInclude.VkDescriptorSetLayoutCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = descriptorSetLayoutBindings.len,
        .pBindings = &descriptorSetLayoutBindings,
    };
    VK_CHECK(VulkanInclude.vkCreateDescriptorSetLayout(VulkanGlobalState._device, &layoutInfo, null, descriptorSetLayout));
}
pub fn Create_VkDescriptorPool(descriptorPool: *VulkanInclude.VkDescriptorPool, texturesCount: u32) void
{
    const poolSizes = [1]VulkanInclude.VkDescriptorPoolSize
    {
        .{
            .type = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = texturesCount,
        },
    };
    
    const poolInfo = VulkanInclude.VkDescriptorPoolCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = poolSizes.len,
        .pPoolSizes = &poolSizes,
        .maxSets = texturesCount,
    };
    //
    VK_CHECK(VulkanInclude.vkCreateDescriptorPool(VulkanGlobalState._device, &poolInfo, null, descriptorPool));
}
pub fn Create_VkDescriptorSet(material: *Modelset.Model.Material, descriptorSetLayout: VulkanInclude.VkDescriptorSetLayout, descriptorPool: VulkanInclude.VkDescriptorPool) void
{
    const allocInfo = VulkanInclude.VkDescriptorSetAllocateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptorPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &descriptorSetLayout,
    };
    
    VK_CHECK(VulkanInclude.vkAllocateDescriptorSets(VulkanGlobalState._device, &allocInfo, &material.descriptorSet));
    
    const textureInfo = VulkanInclude.VkDescriptorImageInfo
    {
        .imageLayout = VulkanInclude.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .imageView = material.vkImageView,
        .sampler = VulkanGlobalState._textureSampler,
    };
    
    const descriptorWrites = [1]VulkanInclude.VkWriteDescriptorSet
    {
        .{
            .sType = VulkanInclude.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = material.descriptorSet,
            .dstBinding = 1,
            .dstArrayElement = 0,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .pImageInfo = &textureInfo,
        },
    };
    
    VulkanInclude.vkUpdateDescriptorSets(VulkanGlobalState._device, descriptorWrites.len, &descriptorWrites, 0, null);
}
pub fn Create_VkPipeline() void
{
    
}
