const std = @import("std");
const linux = std.os.linux;
const print = std.debug.print;
const exit = std.process.exit;

const VulkanInclude = @import("VulkanInclude.zig");

const VulkanGlobalState = @import("VulkanGlobalState.zig");

const customMem = @import("customMem.zig");
const memcpyDstAlign = customMem.memcpyDstAlign;
const memcpy = customMem.memcpy;

const VkBuffer = @import("VkBuffer.zig");
const VkImage = @import("VkImage.zig");

const Image = @import("Image.zig");
const algebra = @import("algebra.zig");
const dds_load = @import("dds_load.zig").dds_load;

const DoW2_Chunk = @import("DoW2_Chunk.zig");

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
//         pub const Vertex = struct
//         {
//             position: algebra.vec3,
//             //                 normal: algebra.vec3,
//             //                 binormal: algebra.vec3,
//             //                 tangent: algebra.vec3,
//             uv: algebra.vec2,
//         };
        vertexVkBuffer: VulkanInclude.VkBuffer,
        indexVkBuffer: VulkanInclude.VkBuffer,
        indicesCount: u16,
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
    pub fn unload(self: Model) void
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
pub fn modelLoad(arenaAllocator: std.mem.Allocator, path: [*]u8, modelPtr: *Model) void
{
    const modelFile: std.fs.File = std.fs.cwd().openFileZ(@ptrCast(path), .{}) catch
    {
        print(".model not found!\n", .{});exit(0);
    };
    defer modelFile.close();
    const stat = modelFile.stat() catch unreachable;
    const modelFileSize: usize = stat.size;
    const modelFileBuffer: [*]u8 = (arenaAllocator.alignedAlloc(u8, customMem.alingment, modelFileSize) catch unreachable).ptr;
    _ = modelFile.read(modelFileBuffer[0..modelFileSize]) catch unreachable;
    
    var bufferPtrItr = modelFileBuffer;
    // skip Relic Chunky
    bufferPtrItr+=36;
//     DoW2_Chunk.printChunkHierarchy(bufferPtrItr, 0);
    const FOLDMODL = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    {
        const FOLDMTRL_count = DoW2_Chunk.childChunkCountPtr(bufferPtrItr, [4]u8{'M','T','R','L'});
        print("materialsCount: {d}\n", .{FOLDMTRL_count});
        modelPtr.materialsCount = @intCast(FOLDMTRL_count);
        modelPtr.materials = (arenaAllocator.alloc(Model.Material, FOLDMTRL_count) catch unreachable).ptr;
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
            verticesSize: u32,
            indicesSize: u32,
        };
        const images = (arenaAllocator.alloc(Image.Image, FOLDMTRL_count) catch unreachable).ptr;
        for(0..FOLDMTRL_count) |FOLDMTRL_index|
        {
//             _ = FOLDMTRL_index;
            const FOLDMTRL = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            {
                defer bufferPtrItr = FOLDMTRL.data+FOLDMTRL.size;
//                 print("    {s}\n", .{FOLDMTRL.string[0..FOLDMTRL.len]});
                // DATAINFO
                DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                const materialTypeLength: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                bufferPtrItr+=4;
                print("    {s}\n", .{bufferPtrItr[0..materialTypeLength]});
                bufferPtrItr+=materialTypeLength;
                // DATAVAR
                while(@as(u32, @bitCast(bufferPtrItr[4..8].*)) == @as(u32, @bitCast([4]u8{0,'V','A','R'})))
                {
                    const DATAVAR = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    defer bufferPtrItr = DATAVAR.data+DATAVAR.size;
                    const varNameLength: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                    bufferPtrItr+=4;
                    print("        {s}\n", .{bufferPtrItr[0..varNameLength]});
                    bufferPtrItr+=varNameLength;
                    const varType: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
//                     print("{d}\n", .{varType});
//                     _ = varType;
                    bufferPtrItr+=4;
                    const varSize: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
//                     _ = varSize;
                    bufferPtrItr+=4;
                    switch(varType)
                    {
                        9 =>
                        {
                            var pathBufferStack: [256]u8 align(customMem.alingment) = undefined;
                            const dds = ".dds";
                            memcpyDstAlign(&pathBufferStack, bufferPtrItr, varSize);
                            memcpy(@as([*]u8, @ptrCast(&pathBufferStack))+varSize-1, dds, dds.len+1);
                            for(0..varSize) |i|
                            {
                                if(pathBufferStack[i] == '\\')
                                    pathBufferStack[i] = '/';
                            }
                            print("        {s}\n", .{pathBufferStack[0..varSize+dds.len]});
                            const textureTypePtr = bufferPtrItr+varSize-4;
                            if(@as(u32, @bitCast(textureTypePtr[0..4].*)) == @as(u32, @bitCast([4]u8{'d','i','f', 0})))
                            {
                                dds_load(arenaAllocator, &pathBufferStack, &images[FOLDMTRL_index]);
                            }
                        },
                        else =>
                        {
                            
                        }
                    }
                }
            }
        }
        const FOLDMESH = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
        // підрахунок кількості lod0 мешів
        {
            // FOLDMGRP
            const FOLDMGRP = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            _ = FOLDMGRP;
            // FOLDMESH
            //         const FOLDMESH_foldmgrpCount = childChunkCount(FOLDMGRP, [4]u8{'M','E','S','H'});
            //         _ = FOLDMESH_foldmgrpCount;
            const FOLDMESH_foldmgrp = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            _ = FOLDMESH_foldmgrp;
            const FOLDIMDG = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            _ = FOLDIMDG;
            const FOLDMESH_foldimdg = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            _ = FOLDMESH_foldimdg;
            const FOLDIMOD = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            //                 _ = FOLDIMOD;
            // DATADATA
            DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
            bufferPtrItr+=4;
            const FOLDMESH_foldimodCount = DoW2_Chunk.childChunkCount(FOLDIMOD, [4]u8{'M','E','S','H'});
            modelPtr.meshesCount = @intCast(FOLDMESH_foldimodCount);
            print("meshesCount: {d}\n", .{FOLDMESH_foldimodCount});
            modelPtr.meshes = (arenaAllocator.alloc(Model.Mesh, FOLDMESH_foldimodCount) catch unreachable).ptr;
        }
//         const meshes = (arenaAllocator.alloc(Mesh, modelPtr.meshesCount) catch unreachable).ptr;
        const verticesArray = (arenaAllocator.alloc([*]Mesh.Vertex, modelPtr.meshesCount) catch unreachable).ptr;
        const verticesSizesArray = (arenaAllocator.alloc(usize, modelPtr.meshesCount) catch unreachable).ptr;
        const indicesArray = (arenaAllocator.alloc([*]u16, modelPtr.meshesCount) catch unreachable).ptr;
        const indicesSizesArray = (arenaAllocator.alloc(usize, modelPtr.meshesCount) catch unreachable).ptr;
        bufferPtrItr = FOLDMESH.data;
        {
            defer bufferPtrItr = FOLDMESH.data+FOLDMESH.size;
            const FOLDMGRP = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            {
                defer bufferPtrItr = FOLDMGRP.data+FOLDMGRP.size;
                // FOLDMESH
                const FOLDMESH_foldmgrpCount = DoW2_Chunk.childChunkCountPtr(bufferPtrItr, [4]u8{'M','E','S','H'});
                for(0..FOLDMESH_foldmgrpCount) |FOLDMESH_foldmgrpIndex|
                {
                    _ = FOLDMESH_foldmgrpIndex;
                    const FOLDMESH_foldmgrp = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    {
                        defer bufferPtrItr = FOLDMESH_foldmgrp.data+FOLDMESH_foldmgrp.size;
                        const FOLDIMDG = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                        { 
                            defer bufferPtrItr = FOLDIMDG.data+FOLDIMDG.size;
                            const FOLDMESH_foldimdgCount = DoW2_Chunk.childChunkCount(FOLDIMDG, [4]u8{'M','E','S','H'});
                            for(0..FOLDMESH_foldimdgCount) |FOLDMESH_foldimdgIndex|
                            {
                                _ = FOLDMESH_foldimdgIndex;
                                const FOLDMESH_foldimdg = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                                {
                                    defer bufferPtrItr = FOLDMESH_foldimdg.data+FOLDMESH_foldimdg.size;
                                    const FOLDIMOD = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                                    {
                                        defer bufferPtrItr = FOLDIMOD.data+FOLDIMOD.size;
                                        print("    {s}\n\n", .{FOLDIMOD.string[0..FOLDIMOD.len]});
                                        // DATADATA
                                        DoW2_Chunk.chunkSkip(&bufferPtrItr);
                                        const FOLDMESH_foldimodCount = DoW2_Chunk.childChunkCount(FOLDIMOD, [4]u8{'M','E','S','H'});
                                        for(0..FOLDMESH_foldimodCount) |FOLDMESH_foldimodIndex|
                                        {
//                                             print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(modelFileBuffer)});
//                                             _ = FOLDMESH_foldimodIndex;
                                            const FOLDMESH_foldimod = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                                            {
                                                defer bufferPtrItr = FOLDMESH_foldimod.data+FOLDMESH_foldimod.size;
                                                const FOLDTRIM = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                                                {
                                                    defer bufferPtrItr = FOLDTRIM.data+FOLDTRIM.size;
                                                    // DATADATA
                                                    DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                                                    const numVertexElements: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                    bufferPtrItr+=4;
                                                    print("    numVertexElements: {d}\n", .{numVertexElements});
                                                    const VertexElement = struct
                                                    {
                                                        type: isize,
//                                                         version: u32,
                                                        dataType: isize,
                                                    };
                                                    var vertexElements: [10]VertexElement = undefined;
                                                    for(vertexElements[0..10]) |*vertexElement|
                                                    {
                                                        vertexElement.type = -1;
                                                        vertexElement.dataType = -1;
                                                    }
                                                    for(0..numVertexElements) |vertexElementIndex|
                                                    {
                                                        _ = vertexElementIndex;
                                                        const value = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                        vertexElements[value].type = value;
                                                        vertexElements[value].dataType = @as(u32, @bitCast(bufferPtrItr[8..12].*));
                                                        bufferPtrItr+=12;
                                                    }
//                                                     print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(modelFileBuffer)});
//                                                     print("    mapSupport: {d} {d}\n", .{vertexElements[8].dataType, vertexElements[9].dataType});
                                                    if(vertexElements[0].dataType != -1)
                                                        print("    position: 12\n", .{});
                                                    if(vertexElements[1].dataType != -1)
                                                        print("    blendIndices: 4\n", .{});
                                                    if(vertexElements[2].dataType != -1)
                                                        print("    blendWeights: 4\n", .{});
                                                    if(vertexElements[3].dataType != -1)
                                                    {
                                                        switch(vertexElements[3].dataType)
                                                        {
                                                            2 =>
                                                            {
                                                                print("    normals: 4\n", .{});
                                                            },
                                                            4 =>
                                                            {
                                                                print("    normals: 12\n", .{});
                                                            },
                                                            else => unreachable
                                                        }
                                                    }
                                                    if(vertexElements[4].dataType != -1)
                                                    {
                                                        switch(vertexElements[4].dataType)
                                                        {
                                                            2 =>
                                                            {
                                                                print("    bitangent: 4\n", .{});
                                                            },
                                                            4 =>
                                                            {
                                                                print("    bitangent: 12\n", .{});
                                                            },
                                                            else => unreachable
                                                        }
                                                    }
                                                    if(vertexElements[5].dataType != -1)
                                                    {
                                                        switch(vertexElements[5].dataType)
                                                        {
                                                            2 =>
                                                            {
                                                                print("    tangent: 4\n", .{});
                                                            },
                                                            4 =>
                                                            {
                                                                print("    tangent: 12\n", .{});
                                                            },
                                                            else => unreachable
                                                        }
                                                    }
                                                    if(vertexElements[6].dataType != -1)
                                                        print("    color: 4\n", .{});
                                                    if(vertexElements[8].dataType != -1)
                                                    {
                                                        var size: usize = 8;
                                                        if(vertexElements[9].dataType != -1)
                                                            size+=8;
                                                        print("    UV: {d}\n", .{size});
                                                    }
                                                    // Read vertices
                                                    const verticesCount: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                    bufferPtrItr+=4;
//                                                     const meshPtr = &meshes[FOLDMESH_foldimodIndex];
//                                                     _ = meshPtr;
                                                    const vertSize: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                    bufferPtrItr+=4;
                                                    print("    vertSize: {d}\n", .{vertSize});
                                                    print("    verticesCount: {d}\n", .{verticesCount});
//                                                     meshPtr.verticesCount = @intCast(verticesCount);
                                                    verticesArray[FOLDMESH_foldimodIndex] = (arenaAllocator.alloc(Mesh.Vertex, verticesCount*@sizeOf(Mesh.Vertex)) catch unreachable).ptr;
                                                    verticesSizesArray[FOLDMESH_foldimodIndex] = verticesCount*@sizeOf(Mesh.Vertex);
                                                    for(0..verticesCount) |verticesIndex|
                                                    {
                                                        //                         _ = verticesIndex;
                                                        const vertexPtr = &verticesArray[FOLDMESH_foldimodIndex][verticesIndex];
                                                        // position
                                                        if(vertexElements[0].dataType != -1)
                                                        {
                                                            memcpy(@ptrCast(&vertexPtr.position), bufferPtrItr, 12);
                                                            bufferPtrItr+=12;
                                                        }
                                                        // blendIndices
                                                        if(vertexElements[1].dataType != -1)
                                                        {
                                                            bufferPtrItr+=4;
                                                        }
                                                        // blendWeights
                                                        if(vertexElements[2].dataType != -1)
                                                        {
                                                            bufferPtrItr+=4;
                                                        }
                                                        // normal
                                                        if(vertexElements[3].dataType != -1)
                                                        {
                                                            switch(vertexElements[3].dataType)
                                                            {
                                                                2 =>
                                                                {
                                                                    bufferPtrItr+=4;
                                                                },
                                                                4 =>
                                                                {
                                                                    bufferPtrItr+=12;
                                                                },
                                                                else => unreachable
                                                            }
                                                        }
                                                        // bitangent
                                                        if(vertexElements[4].dataType != -1)
                                                        {
                                                            switch(vertexElements[4].dataType)
                                                            {
                                                                2 =>
                                                                {
                                                                    bufferPtrItr+=4;
                                                                },
                                                                4 =>
                                                                {
                                                                    bufferPtrItr+=12;
                                                                },
                                                                else => unreachable
                                                            }
                                                        }
                                                        // tangent
                                                        if(vertexElements[5].dataType != -1)
                                                        {
                                                            switch(vertexElements[5].dataType)
                                                            {
                                                                2 =>
                                                                {
                                                                    bufferPtrItr+=4;
                                                                },
                                                                4 =>
                                                                {
                                                                    bufferPtrItr+=12;
                                                                },
                                                                else => unreachable
                                                            }
                                                        }
                                                        // color
                                                        if(vertexElements[6].dataType != -1)
                                                        {
                                                            bufferPtrItr+=4;
                                                        }
                                                        // UV
                                                        if(vertexElements[8].dataType != -1)
                                                        {
                                                            @as(*align(1)u64, @ptrCast(&vertexPtr.uv.data)).* = @as(*align(1)u64, @ptrCast(bufferPtrItr)).*;
                                                            bufferPtrItr+=8;
                                                        }
                                                        else
                                                        {
                                                            vertexPtr.uv.data = [2]f32{0,0};
                                                        }
                                                        if(vertexElements[9].dataType != -1)
                                                            bufferPtrItr+=8;
                                                    }
                                                    // Read faces
                                                    bufferPtrItr+=8;
                                                    const vertPerFace: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                    bufferPtrItr+=4;
                                                    if(vertPerFace != 3)
                                                    {
                                                        print("vertPerFace != 3!(={d})\n", .{vertPerFace});
                                                        exit(0);
                                                    }
                                                    const indicesCount: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                    bufferPtrItr+=4;
                                                    print("    indicesCount: {d}\n", .{indicesCount});
                                                    modelPtr.meshes[FOLDMESH_foldimodIndex].indicesCount = @intCast(indicesCount);
                                                    indicesArray[FOLDMESH_foldimodIndex] = (arenaAllocator.alignedAlloc(u16, customMem.alingment,indicesCount) catch unreachable).ptr;
                                                    indicesSizesArray[FOLDMESH_foldimodIndex] = indicesCount*2;
//                                                     meshPtr.indicesBufferSize = @intCast(indicesCount*2);
//                                                     meshPtr.indicesSize = @intCast(indicesCount*2);
                                                    memcpyDstAlign(@ptrCast(indicesArray[FOLDMESH_foldimodIndex]), bufferPtrItr, indicesCount*2);
                                                    bufferPtrItr+=indicesCount*2;
//                                                     VkBuffer.createVkBuffer__VkDeviceMemory(VulkanInclude.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, vertices, verticesCount*@sizeOf(Model.Mesh.Vertex), modelPtr.vertexVkDeviceMemory, modelPtr.vertexVkDeviceMemory);
                                                    const materialNameLength: usize  = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                    bufferPtrItr+=4;
                                                    print("    {s}\n", .{bufferPtrItr[0..materialNameLength]});
                                                    bufferPtrItr+=materialNameLength;
                                                    // Read skin
                                                    const skinBonesCount: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                    bufferPtrItr+=4;
                                                    print("    skinBonesCount: {d}\n", .{skinBonesCount});
                                                    print("\n", .{});
                                                    for(0..skinBonesCount) |skinBoneIndex|
                                                    {
                                                        _ = skinBoneIndex;
                                                        bufferPtrItr+=24*4;
                                                        const skinBoneNameLength: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                                        bufferPtrItr+=4;
                                                        bufferPtrItr+=skinBoneNameLength;
                                                    }
                                                    bufferPtrItr+=8;//unknown
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    break;
                }
            }
        }
//         VkImage.createVkImages__VkImageViews__VkDeviceMemory_AoS_dst(images, @ptrCast(modelPtr.materials), @sizeOf(Model.Material), modelPtr.materialsCount, &modelPtr.texturesVkDeviceMemory);
//         VkBuffer.createVkBuffers__VkDeviceMemory_AoS_Dst(VulkanInclude.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, @ptrCast(verticesArray),  verticesSizesArray, @ptrCast(&modelPtr.meshes[0].vertexVkBuffer), @sizeOf(Model.Mesh), modelPtr.meshesCount, &modelPtr.vertexVkDeviceMemory);
//         VkBuffer.createVkBuffers__VkDeviceMemory_AoS_Dst(VulkanInclude.VK_BUFFER_USAGE_INDEX_BUFFER_BIT, @ptrCast(indicesArray),  indicesSizesArray, @ptrCast(&modelPtr.meshes[0].indexVkBuffer), @sizeOf(Model.Mesh), modelPtr.meshesCount, &modelPtr.indexVkDeviceMemory);
        bufferPtrItr = FOLDMODL.data+FOLDMODL.size;
    }
}
