const std = @import("std");
const linux = std.os.linux;
const print = std.debug.print;
const exit = std.process.exit;

const zlib = @import("zlib.zig");
const VulkanInclude = @import("VulkanInclude.zig");

const globalState = @import("globalState.zig");
const VulkanGlobalState = @import("VulkanGlobalState.zig");
const VK_CHECK = VulkanGlobalState.VK_CHECK;
const camera = @import("camera.zig");

const VkBuffer = @import("VkBuffer.zig");
const VkImage = @import("VkImage.zig");
const VkPipeline = @import("VkPipeline.zig");

const customMem = @import("customMem.zig");
const memcpyDstAlign = customMem.memcpyDstAlign;
const memcpy = customMem.memcpy;
const algebra = @import("algebra.zig");
const Image = @import("Image.zig").Image;
const dds_load = @import("dds_load.zig").dds_load;
const ddsLoadCubemapAsImages = @import("dds_load.zig").ddsLoadCubemapAsImages;

const DoW2_Chunk = @import("DoW2_Chunk.zig");
const DoW2_model = @import("DoW2_model.zig");

pub const Map = struct
{
    const Vertex = struct
    {
        position: algebra.vec3,
        normal: algebra.vec3,
//         uv: algebra.vec2,
    };
    const Texture = struct
    {
        vkImage: VulkanInclude.VkImage,
        vkImageView: VulkanInclude.VkImageView,
//         descriptorSet: VulkanInclude.VkDescriptorSet,
    };
    const Splatmap = struct
    {
        vkImage: VulkanInclude.VkImage,
        vkImageView: VulkanInclude.VkImageView,
//         descriptorSet: VulkanInclude.VkDescriptorSet,
    };
    vertices: [*]Vertex,
    indices: [*]u32,
    indicesCount: u32,
    width: u16,
    height: u16,
    
    layersCount: u8,
    
    vertexVkBuffer: VulkanInclude.VkBuffer,
    indexVkBuffer: VulkanInclude.VkBuffer,
    vertexVkDeviceMemory: VulkanInclude.VkDeviceMemory,
    indexVkDeviceMemory: VulkanInclude.VkDeviceMemory,
    
    terrainTextures: [32]Texture,
    splatmaps: [2]Splatmap,
    layersVkDeviceMemory: VulkanInclude.VkDeviceMemory,
    splatmapsVkDeviceMemory: VulkanInclude.VkDeviceMemory,
    descriptorSetLayout: VulkanInclude.VkDescriptorSetLayout,
    descriptorPool: VulkanInclude.VkDescriptorPool,
    descriptorSet: VulkanInclude.VkDescriptorSet,
    
    world_objects: [*]DoW2_model.Model,
    world_objectsCount: u32,
    
    pub fn unload(self: Map) void
    {
        VulkanInclude.vkDestroyBuffer(VulkanGlobalState._device, self.vertexVkBuffer, null);
        VulkanInclude.vkFreeMemory(VulkanGlobalState._device, self.vertexVkDeviceMemory, null);
        VulkanInclude.vkDestroyBuffer(VulkanGlobalState._device, self.indexVkBuffer, null);
        VulkanInclude.vkFreeMemory(VulkanGlobalState._device, self.indexVkDeviceMemory, null);
        for(0..self.layersCount*4) |index|
        {
            VulkanInclude.vkDestroyImage(VulkanGlobalState._device, self.terrainTextures[index].vkImage, null);
            VulkanInclude.vkDestroyImageView(VulkanGlobalState._device, self.terrainTextures[index].vkImageView, null);
        }
        VulkanInclude.vkFreeMemory(VulkanGlobalState._device, self.layersVkDeviceMemory, null);
        for(0..2) |index|
        {
            VulkanInclude.vkDestroyImage(VulkanGlobalState._device, self.splatmaps[index].vkImage, null);
            VulkanInclude.vkDestroyImageView(VulkanGlobalState._device, self.splatmaps[index].vkImageView, null);
        }
        VulkanInclude.vkFreeMemory(VulkanGlobalState._device, self.splatmapsVkDeviceMemory, null);
        // descriptors
        VulkanInclude.vkDestroyDescriptorSetLayout(VulkanGlobalState._device, self.descriptorSetLayout, null);
        VulkanInclude.vkDestroyDescriptorPool(VulkanGlobalState._device, self.descriptorPool, null);
        
        // models
//         for(0..2) |i|
//         {
//             self.models[i].unload();
//         }
    }
};
fn readTextureFromCubemap(arenaAllocator: std.mem.Allocator, srcBuffer: [*]u8, image: *Image) void
{
    const dstBuffer: [*]u8 = (arenaAllocator.alignedAlloc(u8, customMem.alingment, 349440) catch unreachable).ptr;
    var srcMipLevelData = srcBuffer;
    var bufferDstOffsetPtr = dstBuffer;
    var mipDimencion: usize = 512;
    for(0..6) |mipLevel|
    {
        _ = mipLevel;
        for(0..mipDimencion/4) |index|
        {
            customMem.memcpyAlign(bufferDstOffsetPtr, srcMipLevelData+mipDimencion*8*4*index, mipDimencion*4);
            bufferDstOffsetPtr += (mipDimencion*4);
        }
        srcMipLevelData += (mipDimencion*mipDimencion*8);
        mipDimencion /= 2;
    }
    image.width = 512;
    image.mipSize = 512*512;
    image.size = 349440;
    image.data = dstBuffer;
}
pub fn scenarioLoad(arenaAllocator: std.mem.Allocator, path: [*:0]const u8, map: *Map) !void
{
    const scenarioFile: std.fs.File = try std.fs.cwd().openFileZ(path, .{});
    defer scenarioFile.close();
    const stat = scenarioFile.stat() catch unreachable;
    const scenarioFileSize: usize = stat.size;
    const scenarioFileBuffer: [*]u8 = (arenaAllocator.alignedAlloc(u8, customMem.alingment, scenarioFileSize) catch unreachable).ptr;
    _ = scenarioFile.read(scenarioFileBuffer[0..scenarioFileSize]) catch unreachable;
    
    var bufferPtrItr = scenarioFileBuffer;
    // skip Relic Chunky
    bufferPtrItr+=36;
    // DATASDSC
    DoW2_Chunk.chunkSkip(&bufferPtrItr);
    // FOLDPRCH
//     DoW2_Chunk.printChunkHierarchy(bufferPtrItr, 0);
    const FOLDPRCH = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    {
        defer bufferPtrItr = FOLDPRCH.data+FOLDPRCH.size;
        const FOLDGEWD = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
        {
            defer bufferPtrItr = FOLDGEWD.data+FOLDGEWD.size;
            // DATAVIZ
            DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
//             print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
            const artCount: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
            bufferPtrItr+=4;
            print("artCount: {d}\n", .{artCount});
            map.world_objects = (arenaAllocator.alloc(DoW2_model.Model, artCount) catch unreachable).ptr;
            map.world_objectsCount = @intCast(artCount);
            for(0..artCount) |index|
            {
//                 _ = index;
                const artNameLength: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                bufferPtrItr+=4;
                var pathBufferStack: [256]u8 align(customMem.alingment) = undefined;
                const modelExt = ".model";
                for(0..artNameLength) |i|
                {
                    if(bufferPtrItr[i] == '\\')
                    {
                        bufferPtrItr[i] = '/';
                    }
                }
                memcpyDstAlign(&pathBufferStack, bufferPtrItr, artNameLength);
                memcpy(@as([*]u8, @ptrCast(&pathBufferStack))+artNameLength, modelExt, modelExt.len+1);
                print("{s}\n", .{pathBufferStack[0..artNameLength+modelExt.len]});
                DoW2_model.modelLoad(arenaAllocator, &pathBufferStack, &map.world_objects[index]);
//                 print("{s}\n", .{bufferPtrItr[0..artNameLength]});
                bufferPtrItr+=artNameLength;
            }
//             bufferPtrItr = DATAVIZ.data+DATAVIZ.size;
//             const DATAEBPL = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
//             print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
//             const epbsCount: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
//             bufferPtrItr+=4;
//             print("epbsCount: {d}\n", .{epbsCount});
//             for(0..epbsCount) |index|
//             {
//                 _ = index;
//                 const epbsNameLength: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
//                 bufferPtrItr+=4;
//                 print("{s}\n", .{bufferPtrItr[0..epbsNameLength]});
//                 bufferPtrItr+=epbsNameLength;
//             }
//             bufferPtrItr = DATAEBPL.data+DATAEBPL.size;
        }
    }
//     DoW2_Chunk.chunkSkip(&bufferPtrItr);
    // FOLDSCEN
//     DoW2_Chunk.printChunkHierarchy(bufferPtrItr, 0);
    const FOLDSCEN = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    {
        _ = FOLDSCEN;
        // FOLDGEWD
        const FOLDGEWD = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
        {
            
//         DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
        // FOLDATMO
            DoW2_Chunk.chunkSkip(&bufferPtrItr);
            {
    //             const FOLDATMO = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    //             for(0..9) |chunkIndex|
    //             {
    //                 _ = chunkIndex;
    //                 DoW2_Chunk.chunkSkip(&bufferPtrItr);
    //             }
    //             // DATALGRD
    //             const DATALGRD = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    //             _ = DATALGRD;
    //             print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
    //             bufferPtrItr = FOLDATMO.data+FOLDATMO.size;
            }
            const FOLDTERR = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            {
                const DATAINFO = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                bufferPtrItr = DATAINFO.data+DATAINFO.size;
                const FOLDHMAN = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                {
                    const FOLDHITE = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    {
                        const DATADATA = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                        bufferPtrItr = DATADATA.data+DATADATA.size;
                        // FOLDHVAL x2
                        DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                        {
                            const DATAHEAD = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                            const width: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                            print("width: {d}\n", .{width});
                            const height: usize = @as(u32, @bitCast(bufferPtrItr[4..8].*));
                            print("height: {d}\n", .{height});
                            var size: usize = @as(u32, @bitCast(bufferPtrItr[8..12].*));
                            print("size: {d}\n", .{size});
                            map.width = @intCast(width);
                            map.height = @intCast(height);
                            bufferPtrItr = DATAHEAD.data+DATAHEAD.size;
                            
                            const DATAVALS = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                            map.indicesCount = @intCast((width-1)*(height-1)*6);
                            const buffer = (arenaAllocator.alignedAlloc(u8, 4, size) catch unreachable).ptr;
                            _ = zlib.uncompress(buffer, &size, bufferPtrItr, DATAVALS.size);
                            map.vertices = (arenaAllocator.alloc(Map.Vertex, width*height) catch unreachable).ptr;
                            map.indices = (arenaAllocator.alloc(u32, map.indicesCount) catch unreachable).ptr;
                            var heightMin: f32 = @as(*f32, @alignCast(@ptrCast(buffer))).*;
                            var heightMax: f32 = @as(*f32, @alignCast(@ptrCast(buffer))).*;
                            for(0..height*width) |i|
                            {
                                const value = @as(*f32, @alignCast(@ptrCast(buffer+i*4))).*;
                                if(value < heightMin)
                                    heightMin = value;
                                if(value > heightMax)
                                    heightMax = value;
                            }
                            print("heightMin: {d:.5}\nheightMax: {d:.5}\n", .{heightMin, heightMax});
//                             for(0..height*width) |i|
//                             {
//                                 @as(*f32, @alignCast(@ptrCast(buffer+i*4))).* -= heightMin;
//                             }
                            var vertexIndex: usize = 0;
                            {
                                var y: i32 = 0;
                                while(y < height): (y+=1)
                                {
                                    var x: i32 = 0;
                                    while(x < width): (x+=1)
                                    {
                                        map.vertices[vertexIndex].position.data[0] = @floatFromInt(-@as(isize, @intCast((width-1)/2)) + x);
                                        map.vertices[vertexIndex].position.data[1] = @floatFromInt(-@as(isize, @intCast((height-1)/2)) + y);
                                        map.vertices[vertexIndex].position.data[2] = @as(*f32, @alignCast(@ptrCast(buffer+vertexIndex*4))).*;
                                        vertexIndex+=1;
                                    }
                                }
                            }
                            const heightHalf = (height-1)/2;
                            const widthHalf = (width-1)/2;
                            for(0..height-1) |y|
                            {
                                for(0..width-1) |x|
                                {
                                    const in = (y*(width-1)+x)*6;
                                    const v = y*(width)+x;
                                    if(y < heightHalf and x < widthHalf or y > heightHalf and x > widthHalf)
                                    {
                                        map.indices[in+0] = @intCast(v+1);
                                        map.indices[in+1] = @intCast(v+width+1);
                                        map.indices[in+2] = @intCast(v+width);
                                        map.indices[in+3] = @intCast(v+width);
                                        map.indices[in+4] = @intCast(v);
                                        map.indices[in+5] = @intCast(v+1);
                                    }
                                    else
                                    {
                                        map.indices[in+0] = @intCast(v);
                                        map.indices[in+1] = @intCast(v+1);
                                        map.indices[in+2] = @intCast(v+width+1);
                                        map.indices[in+3] = @intCast(v+width+1);
                                        map.indices[in+4] = @intCast(v+width);
                                        map.indices[in+5] = @intCast(v);
                                    }
                                    if(@abs(map.vertices[v].position.data[2] - map.vertices[v+width+1].position.data[2])>2)
                                    {
                                        map.indices[in+0] = @intCast(v+1);
                                        map.indices[in+1] = @intCast(v+width+1);
                                        map.indices[in+2] = @intCast(v+width);
                                        map.indices[in+3] = @intCast(v+width);
                                        map.indices[in+4] = @intCast(v);
                                        map.indices[in+5] = @intCast(v+1);
                                    }
                                    if(@abs(map.vertices[v+1].position.data[2] - map.vertices[v+width].position.data[2])>2)
                                    {
                                        map.indices[in+0] = @intCast(v);
                                        map.indices[in+1] = @intCast(v+1);
                                        map.indices[in+2] = @intCast(v+width+1);
                                        map.indices[in+3] = @intCast(v+width+1);
                                        map.indices[in+4] = @intCast(v+width);
                                        map.indices[in+5] = @intCast(v);
                                    }
                                }
                            }
                            // calculate normals
                            const normalsBuffer = (arenaAllocator.alloc(algebra.vec3, (height-1)*(width-1)) catch unreachable).ptr;
                            for(0..height-1) |y|
                            {
                                for(0..width-1) |x|
                                {
                                    const indexVertex = y*width+x;
                                    const indexQuad = y*(width-1)+x;
                                    const height_00 = map.vertices[indexVertex].position.data[2];
                                    const height_10 = map.vertices[indexVertex+1].position.data[2];
                                    const height_01 = map.vertices[indexVertex+width].position.data[2];
                                    const height_11 = map.vertices[indexVertex+width+1].position.data[2];
                                    const diagonal_00_11 = algebra.vec3{.data = [3]f32{1, 1, height_11-height_00}};
                                    const diagonal_10_01 = algebra.vec3{.data = [3]f32{-1, 1, height_01-height_10}};
                                    var vec3Result = algebra.vec3.vectorMultiplication(diagonal_00_11, diagonal_10_01);
                                    vec3Result.normalize();
                                    normalsBuffer[indexQuad] = vec3Result;
                                }
                            }
                            // conrners
                            map.vertices[0].normal = normalsBuffer[0];
                            map.vertices[width].normal = normalsBuffer[width-1];
                            map.vertices[(height-1)*width].normal = normalsBuffer[(height-2)*(width-1)];
                            map.vertices[height*width-1].normal = normalsBuffer[(height-1)*(width-1)-1];
                            // ribs
                            for(1..width-1) |x|
                            {
                                var vector = algebra.vec3.sum(normalsBuffer[x-1], normalsBuffer[x]);
                                vector.normalize();
                                map.vertices[x].normal = vector;
                            }
                            for(1..width-1) |x|
                            {
                                const indexQuad = (height-2)*(width-1)+x;
                                var vector = algebra.vec3.sum(normalsBuffer[indexQuad-1], normalsBuffer[indexQuad]);
                                vector.normalize();
                                map.vertices[(height-1)*width+x].normal = vector;
                            }
                            for(1..height-1) |y|
                            {
                                const indexQuad = (y)*(width-1);
                                var vector = algebra.vec3.sum(normalsBuffer[indexQuad-(width-1)], normalsBuffer[indexQuad]);
                                vector.normalize();
                                map.vertices[y*width].normal = vector;
                            }
                            for(1..height-1) |y|
                            {
                                const indexQuad = (y+1)*(width-1)-1;
                                var vector = algebra.vec3.sum(normalsBuffer[indexQuad-(width-1)], normalsBuffer[indexQuad]);
                                vector.normalize();
                                map.vertices[(y+1)*width-1].normal = vector;
                            }
                            for(1..height-1) |y|
                            {
                                for(1..width-1) |x|
                                {
                                    const indexQuad = y*(width-1)+x;
                                    var vector: algebra.vec3 = normalsBuffer[indexQuad-(width-1)-1];
                                    vector = algebra.vec3.sum(vector, normalsBuffer[indexQuad-(width-1)]);
                                    vector = algebra.vec3.sum(vector, normalsBuffer[indexQuad-1]);
                                    vector = algebra.vec3.sum(vector, normalsBuffer[indexQuad]);
                                    vector.normalize();
                                    map.vertices[y*width+x].normal = vector;
                                }
                            }
//                             print("normalVector: {d:.3} {d:.3} {d:.3}\n", .{normalsBuffer[3].data[0], normalsBuffer[3].data[1], normalsBuffer[3].data[2]});
                            VkBuffer.createVkBuffer__VkDeviceMemory(VulkanInclude.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, @ptrCast(map.vertices), width*height*@sizeOf(Map.Vertex), &map.vertexVkBuffer, &map.vertexVkDeviceMemory);
                            VkBuffer.createVkBuffer__VkDeviceMemory(VulkanInclude.VK_BUFFER_USAGE_INDEX_BUFFER_BIT, @ptrCast(map.indices), map.indicesCount*4, &map.indexVkBuffer, &map.indexVkDeviceMemory);
                            
    //                             print("result: {d}\n", .{result});
    //                             const mode: linux.mode_t = 0o755;
    //                             const heightmap_fd: i32 = @intCast(linux.open("heightmap2.raw", .{.ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true}, mode));
    //                             _ = linux.write(heightmap_fd, buffer, size);
    //                             _ = linux.close(heightmap_fd);
    //                         print("{x}\n\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                            bufferPtrItr = DATAVALS.data+DATAVALS.size;
                        }
                        DoW2_Chunk.chunkSkip(&bufferPtrItr);
                        {
                            // DATAHEAD
//                             DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
// //                             const width: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
// //                             const height: usize = @as(u32, @bitCast(bufferPtrItr[4..8].*));
//                             var size: usize = @as(u32, @bitCast(bufferPtrItr[8..12].*));
//                             print("size: {d}\n", .{size});
//     //                         _ = size;
//                             bufferPtrItr+=12;
//     //                         
//                             const DATAVALS = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
//     //                         _ = DATAVALS;
//                             const buffer = (arenaAllocator.alloc(u8, size) catch unreachable).ptr;
//                             _ = zlib.uncompress(buffer, &size, bufferPtrItr, DATAVALS.size);
// //                             for(0..width*height) |i|
// //                             {
// //                                 var vector = algebra.vec3{.data = [3]f32{0, 0, @as(f32, @floatFromInt(buffer[i]))/255}};
// //                                 vector.normalize();
// //                                 map.vertices[i].normal = vector;
// //                             }
//                             bufferPtrItr += DATAVALS.size;
//                             var maxValue: isize = 0;
//                             for(0..size) |index|
//                             {
//                                 const value = @as(*i8, @ptrCast(buffer+index)).*;
//                                 if(value > maxValue)
//                                     maxValue = value;
//                             }
//                             print("maxValue: {d}\n\n", .{maxValue});
//                             const mode: linux.mode_t = 0o755;
//                             const heightmap_fd: i32 = @intCast(linux.open("heightmap2.raw", .{.ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true}, mode));
//                             _ = linux.write(heightmap_fd, buffer, size);
//                             _ = linux.close(heightmap_fd);
                        }
                        bufferPtrItr = FOLDHITE.data+FOLDHITE.size;
                    }
                    // FOLDH2OH
                    bufferPtrItr = FOLDHMAN.data+FOLDHMAN.size;
                }
                const FOLDTCHM = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                {
    //                 _ = FOLDTCHM;
                    // DATADATA
//                     print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                    DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                    bufferPtrItr+=20;
                    const FOLDCHNK = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    {
    //                     // DATAEXST
    //                     DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
    //                     bufferPtrItr+=1;
    //                     const FOLDTCHK = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    //                     {
    //                         // DATADATA
    //                         DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
    //                         bufferPtrItr+=8;
    //                         const FOLDCOMP = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    //                         {
    //                             const FOLDWCNK = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    //                             {
    //                                 _ = FOLDWCNK;
    //                                 // DATADATA
    //                                 DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
    //                                 bufferPtrItr+=1;
    //                             }
    //                             const FOLDGRAS = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
    //                             {
    //                                 _ = FOLDGRAS;
    //                                 // DATAEXST
    //                                 DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
    //                                 print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
    //                                 bufferPtrItr+=1;
    //                             }
    //                         }
    //                         bufferPtrItr = FOLDCOMP.data+FOLDCOMP.size;
    //                     }
                        bufferPtrItr = FOLDCHNK.data+FOLDCHNK.size;
                    }
                    bufferPtrItr = FOLDTCHM.data+FOLDTCHM.size;
                }
                const FOLDGMGR = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                {
    //                 _ = FOLDGMGR;
                    // DATAINFO
                    DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                    bufferPtrItr+=29;
                    const FOLDTYPS = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    {
                        // DATATYPE
                        bufferPtrItr = FOLDTYPS.data+FOLDTYPS.size;
                    }
                    bufferPtrItr = FOLDGMGR.data+FOLDGMGR.size;
                }
                const FOLDTTEX = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                {
                    // DATADATA
                    print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                    DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                    const width: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                    print("width: {d}\n", .{width});
                    const height: usize = @as(u32, @bitCast(bufferPtrItr[4..8].*));
                    print("height: {d}\n", .{height});
                    const float = @as(f32, @bitCast(bufferPtrItr[8..12].*));
                    print("float: {d:.5}\n\n", .{float});
                    bufferPtrItr+=24;
                    const FOLDCOMP = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    {
                        const FOLDRCNG = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                        {
                            // DATADATA
                            DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
//                             print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                            bufferPtrItr+=72;
                            bufferPtrItr = FOLDRCNG.data+FOLDRCNG.size;
                        }
                        const FOLDRCTI = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                        {
                            // DATAHEAD
                            print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                            DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                            bufferPtrItr+=8;
                            const FOLDLAYR = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                            {
                                var layersCount: usize = 0;
                                var texturesCount: usize = 0;
                                var images: [32]Image = undefined;
                                // DATADATA
                                for(0..8) |DATADATA_index|
                                {
                                    _ = DATADATA_index;
                                    DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                                    var pathBufferStack: [256]u8 = undefined;
                                    const basePath = "art/terrain_textures/layers/";
                                    const cubemapName = "/cubemap.dds";
                                    var pathSize = basePath.len;
                                    memcpy(&pathBufferStack, basePath, basePath.len);
                                    var nameLength: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                    bufferPtrItr+=4;
                                    if(nameLength == 0)
                                        break;
//                                     print("{s}\t", .{bufferPtrItr[0..nameLength]});
                                    memcpy(@as([*]u8, @ptrCast(&pathBufferStack))+pathSize, bufferPtrItr, nameLength);
                                    pathSize+=nameLength;
                                    bufferPtrItr+=nameLength;
                                    pathBufferStack[pathSize] = '/';
                                    pathSize+=1;
                                    nameLength = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                    bufferPtrItr+=4;
//                                     print("{s}\n", .{bufferPtrItr[0..nameLength]});
                                    memcpy(@as([*]u8, @ptrCast(&pathBufferStack))+pathSize, bufferPtrItr, nameLength);
                                    pathSize+=nameLength;
                                    bufferPtrItr+=nameLength;
                                    memcpy(@as([*]u8, @ptrCast(&pathBufferStack))+pathSize, cubemapName, cubemapName.len+1);
                                    pathSize+=cubemapName.len;
                                    print("{s}\n", .{pathBufferStack[0..pathSize]});
                                    ddsLoadCubemapAsImages(arenaAllocator, &pathBufferStack, @ptrCast(&images[texturesCount]), 4);
//                                     const image = &images[layersCount];
//                                     dds_load(arenaAllocator, &pathBufferStack, image);
//                                     const imageBuffer = image.data;
//                                     // ground
//                                     readTextureFromCubemap(arenaAllocator, imageBuffer, &images[texturesCount]);
//                                     texturesCount+=1;
//                                     // cliff
//                                     readTextureFromCubemap(arenaAllocator, imageBuffer+2560, &images[texturesCount]);
                                    texturesCount+=4;
                                    
                                    layersCount+=1;
//                                     break;
                                }
                                map.layersCount = @intCast(layersCount);
//                                 VkImage.createVkImages__VkImageViews__VkDeviceMemory_VkBuffer_AoS_dst(&images, @as([*]u8, @ptrCast(&map.layers)), @sizeOf(Map.Layer), layersCount, &map.layersVkDeviceMemory);
                                bufferPtrItr = FOLDLAYR.data+FOLDLAYR.size;
                                VkImage.createVkImages__VkImageViews__VkDeviceMemory_AoS_dst(&images, @as([*]u8, @ptrCast(&map.terrainTextures)), @sizeOf(Map.Texture), texturesCount, &map.layersVkDeviceMemory);
                            }
                            const FOLDMASK = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                            {
                                var splatmaps: [2]Image = undefined;
                                for(splatmaps[0..2]) |*splatmap|
                                {
//                                     _ = FOLDIMAG_index;
                                    const FOLDIMAG = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                                    {
                                        // DATAATTR
                                        DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                                        const value: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                                        print("value: {d}\n", .{value});
                                        const splatmapWidth: usize = @as(u32, @bitCast(bufferPtrItr[4..8].*));
                                        print("splatmapWidth: {d}\n", .{splatmapWidth});
                                        const splatmapHeight: usize = @as(u32, @bitCast(bufferPtrItr[8..12].*));
                                        print("splatmapHeight: {d}\n", .{splatmapHeight});
                                        bufferPtrItr+=12;
                                        // DATADATA
                                        DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                                        splatmap.width = @intCast(splatmapWidth);
                                        splatmap.height = @intCast(splatmapHeight);
                                        splatmap.size = @intCast(splatmapWidth * splatmapHeight*4);
                                        splatmap.data = bufferPtrItr;
                                        splatmap.mipsCount = 1;
                                        splatmap.format = VulkanInclude.VK_FORMAT_R8G8B8A8_SRGB;
                                        bufferPtrItr = FOLDIMAG.data+FOLDIMAG.size;
                                    }
                                }
                                VkImage.createVkImages__VkImageViews__VkDeviceMemory_AoS_dst(&splatmaps, @as([*]u8, @ptrCast(&map.splatmaps)), @sizeOf(Map.Splatmap), 2, &map.splatmapsVkDeviceMemory);
                                print("\n", .{});
                                bufferPtrItr = FOLDMASK.data+FOLDMASK.size;
                            }
                            // DATAUSAG
                            const DATAUSAG = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                            bufferPtrItr = DATAUSAG.data+DATAUSAG.size;
                            bufferPtrItr = FOLDRCTI.data+FOLDRCTI.size;
                        }
                        const FOLDRCSP = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                        {
                            // DATAHEAD
                            DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                            bufferPtrItr+=16;
                            const DATAEXST = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                            bufferPtrItr = DATAEXST.data+DATAEXST.size;
                            bufferPtrItr = FOLDRCSP.data+FOLDRCSP.size;
                        }
                        const FOLDRCST = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                        {
                            // DATAHEAD
                            DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                            bufferPtrItr+=16;
                            const DATAEXST = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                            bufferPtrItr = DATAEXST.data+DATAEXST.size;
                            
                            bufferPtrItr = FOLDRCST.data+FOLDRCST.size;
                        }
                        bufferPtrItr = FOLDCOMP.data+FOLDCOMP.size;
                    }
    //                 print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                    bufferPtrItr = FOLDTTEX.data+FOLDTTEX.size;
                }
                const FOLDMAT = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                {
                    const DATAMATS = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    bufferPtrItr = DATAMATS.data+DATAMATS.size;
                    const DATAGRID = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    bufferPtrItr = DATAGRID.data+DATAGRID.size;
                    bufferPtrItr = FOLDMAT.data+FOLDMAT.size;
                }
                const FOLDDMSK = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                {
//                     print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                    bufferPtrItr = FOLDDMSK.data+FOLDDMSK.size;
                }
                bufferPtrItr = FOLDTERR.data+FOLDTERR.size;
            }
            const FOLDVIZ = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
            {
//                 _ = FOLDVIZ;
                print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                const FOLDNODE_count = DoW2_Chunk.childChunkCount(FOLDVIZ, [4]u8{'N','O','D','E'});
                print("FOLDNODE_count: {d}\n", .{FOLDNODE_count});
//                 var capture_point_Index: usize = 0;
                while(@as(u32, @bitCast(bufferPtrItr[4..8].*)) == @as(u32, @bitCast([4]u8{'N','O','D','E'})))
                {
                    const FOLDNODE = DoW2_Chunk.chunkReadHeader(&bufferPtrItr);
                    // DATAINFO
                    DoW2_Chunk.chunkSkip(&bufferPtrItr);
                    if(@as(u32, @bitCast(bufferPtrItr[4..8].*)) == @as(u32, @bitCast([4]u8{'A','N','I','M'})))
                    {
                        DoW2_Chunk.chunkSkipHeader(&bufferPtrItr);
                        const nameLength: usize = @as(u32, @bitCast(bufferPtrItr[0..4].*));
                        bufferPtrItr+=4;
//                         if(@as(u64, @bitCast(bufferPtrItr[18..26].*)) == @as(u64, @bitCast([8]u8{'g','a','m','e','p','l','a','y'})))
//                         {
//                             print("{s}\n", .{bufferPtrItr[0..nameLength]});
//                         }
                        if(@as(u64, @bitCast(bufferPtrItr[27..35].*)) == @as(u64, @bitCast([8]u8{'c','a','p','t','u','r','e','_'})))
                        {
                            for(0..nameLength) |i|
                            {
                                if(bufferPtrItr[i] == '\\')
                                {
                                    bufferPtrItr[i] = '/';
                                }
                            }
                            print("{x}\n", .{@intFromPtr(bufferPtrItr) - @intFromPtr(scenarioFileBuffer)});
                            var pathBufferStack: [256]u8 align(customMem.alingment) = undefined;
                            const modelExt = ".model";
                            memcpyDstAlign(&pathBufferStack, bufferPtrItr, nameLength);
                            memcpy(@as([*]u8, @ptrCast(&pathBufferStack))+nameLength, modelExt, modelExt.len+1);
                            print("{s}\n", .{pathBufferStack[0..nameLength+modelExt.len]});
//                             DoW2_model.modelLoad(arenaAllocator, &pathBufferStack, &map.models[capture_point_Index]);
//                             capture_point_Index+=1;
                        }
//                         print("{s}\n", .{bufferPtrItr[0..nameLength]});
                    }
                    bufferPtrItr = FOLDNODE.data+FOLDNODE.size;
                }
                bufferPtrItr = FOLDVIZ.data+FOLDVIZ.size;
            }
            bufferPtrItr = FOLDGEWD.data+FOLDGEWD.size;
        }
    }
    createDescriptors(map);
}
pub fn createDescriptors(map: *Map) void
{
    const descriptorSetLayoutBindings = [5]VulkanInclude.VkDescriptorSetLayoutBinding
    {
        .{
            .binding = 1,
            .descriptorCount = map.layersCount,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImmutableSamplers = null,
            .stageFlags = VulkanInclude.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
        .{
            .binding = 2,
            .descriptorCount = map.layersCount,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImmutableSamplers = null,
            .stageFlags = VulkanInclude.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
        .{
            .binding = 3,
            .descriptorCount = map.layersCount,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImmutableSamplers = null,
            .stageFlags = VulkanInclude.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
        .{
            .binding = 4,
            .descriptorCount = map.layersCount,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImmutableSamplers = null,
            .stageFlags = VulkanInclude.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
        .{
            .binding = 5,
            .descriptorCount = 2,
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
    VK_CHECK(VulkanInclude.vkCreateDescriptorSetLayout(VulkanGlobalState._device, &layoutInfo, null, &map.descriptorSetLayout));
    const poolSizes = [5]VulkanInclude.VkDescriptorPoolSize
    {
        .{
            .type = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = map.layersCount,
        },
        .{
            .type = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = map.layersCount,
        },
        .{
            .type = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = map.layersCount,
        },
        .{
            .type = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = map.layersCount,
        },
        .{
            .type = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 2,
        },
    };
    const poolInfo = VulkanInclude.VkDescriptorPoolCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = poolSizes.len,
        .pPoolSizes = &poolSizes,
        .maxSets = 1,
    };
    VK_CHECK(VulkanInclude.vkCreateDescriptorPool(VulkanGlobalState._device, &poolInfo, null, &map.descriptorPool));
    const allocInfo = VulkanInclude.VkDescriptorSetAllocateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = map.descriptorPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &map.descriptorSetLayout,
    };
    VK_CHECK(VulkanInclude.vkAllocateDescriptorSets(VulkanGlobalState._device, &allocInfo, &map.descriptorSet));
    var groundColorVkDescriptorImageInfo: [8]VulkanInclude.VkDescriptorImageInfo = undefined;
    for(0..map.layersCount) |index|
    {
        const descriptorImageInfo = &groundColorVkDescriptorImageInfo[index];
        descriptorImageInfo.imageLayout = VulkanInclude.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        descriptorImageInfo.imageView = map.terrainTextures[index*4].vkImageView;
        descriptorImageInfo.sampler = VulkanGlobalState._textureSampler;
    }
    var cliffColorVkDescriptorImageInfo: [8]VulkanInclude.VkDescriptorImageInfo = undefined;
    for(0..map.layersCount) |index|
    {
        const descriptorImageInfo = &cliffColorVkDescriptorImageInfo[index];
        descriptorImageInfo.imageLayout = VulkanInclude.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        descriptorImageInfo.imageView = map.terrainTextures[index*4+1].vkImageView;
        descriptorImageInfo.sampler = VulkanGlobalState._textureSampler;
    }
    var groundNormalVkDescriptorImageInfo: [8]VulkanInclude.VkDescriptorImageInfo = undefined;
    for(0..map.layersCount) |index|
    {
        const descriptorImageInfo = &groundNormalVkDescriptorImageInfo[index];
        descriptorImageInfo.imageLayout = VulkanInclude.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        descriptorImageInfo.imageView = map.terrainTextures[index*4+2].vkImageView;
        descriptorImageInfo.sampler = VulkanGlobalState._textureSampler;
    }
    var cliffNormalVkDescriptorImageInfo: [8]VulkanInclude.VkDescriptorImageInfo = undefined;
    for(0..map.layersCount) |index|
    {
        const descriptorImageInfo = &cliffNormalVkDescriptorImageInfo[index];
        descriptorImageInfo.imageLayout = VulkanInclude.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        descriptorImageInfo.imageView = map.terrainTextures[index*4+3].vkImageView;
        descriptorImageInfo.sampler = VulkanGlobalState._textureSampler;
    }
    var splatmapsVkDescriptorImageInfo: [2]VulkanInclude.VkDescriptorImageInfo = undefined;
    for(0..2) |index|
    {
        const descriptorImageInfo = &splatmapsVkDescriptorImageInfo[index];
        descriptorImageInfo.imageLayout = VulkanInclude.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        descriptorImageInfo.imageView = map.splatmaps[index].vkImageView;
        descriptorImageInfo.sampler = VulkanGlobalState._textureSampler;
    }
    const descriptorWrites = [5]VulkanInclude.VkWriteDescriptorSet
    {
        .{
            .sType = VulkanInclude.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = map.descriptorSet,
            .dstBinding = 1,
            .dstArrayElement = 0,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = map.layersCount,
            .pImageInfo = &groundColorVkDescriptorImageInfo,
        },
        .{
            .sType = VulkanInclude.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = map.descriptorSet,
            .dstBinding = 2,
            .dstArrayElement = 0,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = map.layersCount,
            .pImageInfo = &cliffColorVkDescriptorImageInfo,
        },
        .{
            .sType = VulkanInclude.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = map.descriptorSet,
            .dstBinding = 3,
            .dstArrayElement = 0,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = map.layersCount,
            .pImageInfo = &groundNormalVkDescriptorImageInfo,
        },
        .{
            .sType = VulkanInclude.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = map.descriptorSet,
            .dstBinding = 4,
            .dstArrayElement = 0,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = map.layersCount,
            .pImageInfo = &cliffNormalVkDescriptorImageInfo,
        },
        .{
            .sType = VulkanInclude.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = map.descriptorSet,
            .dstBinding = 5,
            .dstArrayElement = 0,
            .descriptorType = VulkanInclude.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 2,
            .pImageInfo = &splatmapsVkDescriptorImageInfo,
        },
    };
    VulkanInclude.vkUpdateDescriptorSets(VulkanGlobalState._device, descriptorWrites.len, &descriptorWrites, 0, null);
}
pub fn Create_VkPipeline(descriptorSetLayout: VulkanInclude.VkDescriptorSetLayout, pipelineLayout: *VulkanInclude.VkPipelineLayout, pipeline: *VulkanInclude.VkPipeline) void
{
    const vertShaderModule: VulkanInclude.VkShaderModule = VkPipeline.createShaderModule("shaders/mapShader.vert.spv");
    const fragShaderModule: VulkanInclude.VkShaderModule = VkPipeline.createShaderModule("shaders/mapShader.frag.spv");
    defer VulkanInclude.vkDestroyShaderModule(VulkanGlobalState._device, fragShaderModule, null);
    defer VulkanInclude.vkDestroyShaderModule(VulkanGlobalState._device, vertShaderModule, null);
    
    const shaderStages = [2]VulkanInclude.VkPipelineShaderStageCreateInfo
    {
        .{
            .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VulkanInclude.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertShaderModule,
            .pName = "main",
        },
        .{
            .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = VulkanInclude.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragShaderModule,
            .pName = "main",
        }
    };
    const bindingDescriptions = [1]VulkanInclude.VkVertexInputBindingDescription
    {
        .{
            .binding = 0,
            .stride = @sizeOf(Map.Vertex),
            .inputRate = VulkanInclude.VK_VERTEX_INPUT_RATE_VERTEX,
        }
    };
    const attributeDescriptions = [2]VulkanInclude.VkVertexInputAttributeDescription
    {
        .{
            .binding = 0,
            .location = 0,
            .format = VulkanInclude.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = 0,
        },
        .{
            .binding = 0,
            .location = 1,
            .format = VulkanInclude.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @offsetOf(Map.Vertex, "normal"),
        },
//         .{
//             .binding = 0,
//             .location = 2,
//             .format = VulkanInclude.VK_FORMAT_R32G32_SFLOAT,
//             .offset = @offsetOf(Map.Vertex, "uv"),
//         },
    };
    const VertexInputState = VulkanInclude.VkPipelineVertexInputStateCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        
        .vertexBindingDescriptionCount = bindingDescriptions.len,
        .vertexAttributeDescriptionCount = attributeDescriptions.len,
        .pVertexBindingDescriptions = &bindingDescriptions,
        .pVertexAttributeDescriptions = &attributeDescriptions,
    };
    const InputAssemblyState = VulkanInclude.VkPipelineInputAssemblyStateCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VulkanInclude.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = VulkanInclude.VK_FALSE,
    };
    //VkPipelineTessellationStateCreateInfo TessellationState{};
    //make viewport state from our stored viewport and scissor.
    const ViewportState = VulkanInclude.VkPipelineViewportStateCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        //.pViewports = &_viewport;
        .scissorCount = 1,
        //.pScissors = &_scissor;
    };
    //configure the rasterizer to draw filled triangles
    const RasterizationState = VulkanInclude.VkPipelineRasterizationStateCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        
        .depthClampEnable = VulkanInclude.VK_FALSE,
        //discards all primitives before the rasterization stage if enabled which we don't want
        .rasterizerDiscardEnable = VulkanInclude.VK_FALSE,
        
        .polygonMode = VulkanInclude.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = VulkanInclude.VK_CULL_MODE_BACK_BIT,
        .frontFace = VulkanInclude.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        //no depth bias
        .depthBiasEnable = VulkanInclude.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };
    //we dont use multisampling, so just run the default one
    const MultisampleState = VulkanInclude.VkPipelineMultisampleStateCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        
        .sampleShadingEnable = VulkanInclude.VK_FALSE,
        .rasterizationSamples = VulkanInclude.VK_SAMPLE_COUNT_1_BIT,
        //multisampling defaulted to no multisampling (1 sample per pixel)
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = VulkanInclude.VK_FALSE,
        .alphaToOneEnable = VulkanInclude.VK_FALSE,
    };
    const DepthStencilState = VulkanInclude.VkPipelineDepthStencilStateCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        
        .depthTestEnable = VulkanInclude.VK_TRUE,
        .depthWriteEnable = VulkanInclude.VK_TRUE,
        .depthCompareOp = VulkanInclude.VK_COMPARE_OP_LESS,//VK_COMPARE_OP_GREATER
        .depthBoundsTestEnable = VulkanInclude.VK_FALSE,
        .minDepthBounds = 0.0, // Optional
        .maxDepthBounds = 1.0, // Optional
        .stencilTestEnable = VulkanInclude.VK_FALSE,
    };
    //setup dummy color blending. We arent using transparent objects yet
    //the blending is just "no blend", but we do write to the color attachment
    //a single blend attachment with no blending and writing to RGBA
    const colorBlendAttachment = VulkanInclude.VkPipelineColorBlendAttachmentState
    {
        .colorWriteMask = VulkanInclude.VK_COLOR_COMPONENT_R_BIT | VulkanInclude.VK_COLOR_COMPONENT_G_BIT | VulkanInclude.VK_COLOR_COMPONENT_B_BIT | VulkanInclude.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = VulkanInclude.VK_FALSE,
    };
    const ColorBlendState = VulkanInclude.VkPipelineColorBlendStateCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        
        .logicOpEnable = VulkanInclude.VK_FALSE,
        .logicOp = VulkanInclude.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &colorBlendAttachment,
    };
    const dynamicStates = [2]VulkanInclude.VkDynamicState
    {
        VulkanInclude.VK_DYNAMIC_STATE_VIEWPORT,
        VulkanInclude.VK_DYNAMIC_STATE_SCISSOR,
    };
    const DynamicState = VulkanInclude.VkPipelineDynamicStateCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamicStates.len,
        .pDynamicStates = &dynamicStates,
    };
    const descriptorSetLayouts = [2]VulkanInclude.VkDescriptorSetLayout
    {
        camera._cameraDescriptorSetLayout,
        descriptorSetLayout,
    };
    // setup push constants
    const pushConstantRange = VulkanInclude.VkPushConstantRange
    {
        .offset = 0,
        .size = 8,
        .stageFlags = VulkanInclude.VK_SHADER_STAGE_VERTEX_BIT | VulkanInclude.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    const pipelineLayoutInfo = VulkanInclude.VkPipelineLayoutCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        //.flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &descriptorSetLayouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &pushConstantRange,
    };
    VK_CHECK(VulkanInclude.vkCreatePipelineLayout(VulkanGlobalState._device, &pipelineLayoutInfo, null, pipelineLayout));
    const pipelineRenderingCreateInfo = VulkanInclude.VkPipelineRenderingCreateInfoKHR
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &VulkanGlobalState._swapchainImageFormat,
        .depthAttachmentFormat = VulkanGlobalState._depthFormat,
    };
    const pipelineInfo = VulkanInclude.VkGraphicsPipelineCreateInfo
    {
        .sType = VulkanInclude.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        //.flags = VK_PIPELINE_CREATE_DESCRIPTOR_BUFFER_BIT_EXT,
        
        .stageCount = 2,
        .pStages = &shaderStages,
        .pVertexInputState = &VertexInputState,
        .pInputAssemblyState = &InputAssemblyState,
        .pViewportState = &ViewportState,
        .pRasterizationState = &RasterizationState,
        .pMultisampleState = &MultisampleState,
        .pDepthStencilState = &DepthStencilState,
        .pColorBlendState = &ColorBlendState,
        .pDynamicState = &DynamicState,
        .layout = pipelineLayout.*,
        //.renderPass = _renderPass,
        .subpass = 0,
        .basePipelineHandle = null,
        
        .renderPass = null,
        .pNext = &pipelineRenderingCreateInfo,
    };
    VK_CHECK(VulkanInclude.vkCreateGraphicsPipelines(VulkanGlobalState._device, null, 1, &pipelineInfo, null, pipeline));
}
