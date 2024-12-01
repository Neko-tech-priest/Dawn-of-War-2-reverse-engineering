const std = @import("std");
const print = std.debug.print;
const exit = std.process.exit;

const customMem = @import("customMem.zig");

const Image = @import("Image.zig");
const VulkanInclude = @import("VulkanInclude.zig");

pub fn dds_load(arenaAllocator: std.mem.Allocator, path: [*]u8, texture: *Image.Image) void
{
    const textureFile: std.fs.File = std.fs.cwd().openFileZ(@ptrCast(path), .{}) catch
    {
        print("texture not found!\n", .{});exit(0);
    };
    defer textureFile.close();
    const stat = textureFile.stat() catch unreachable;
    const textureFileSize: usize = stat.size;
    const textureFileBuffer: [*]u8 = (arenaAllocator.alignedAlloc(u8, customMem.alingment, textureFileSize) catch unreachable).ptr;
    _ = textureFile.read(textureFileBuffer[0..textureFileSize]) catch unreachable;
    texture.height = @as(*u16, @alignCast(@ptrCast(textureFileBuffer+12))).*;
    texture.width = @as(*u16, @alignCast(@ptrCast(textureFileBuffer+16))).*;
    texture.mipSize = @as(*u32, @alignCast(@ptrCast(textureFileBuffer+20))).*;
    texture.size = @intCast(textureFileSize-128);//@as(*u32, @alignCast(@ptrCast(textureFileBuffer+20))).*
    texture.mipsCount = @as(*u32, @alignCast(@ptrCast(textureFileBuffer+28))).*;
//     print("height: {d}\n", .{texture.height});
//     print("width: {d}\n", .{texture.width});
//     print("mipsCount: {d}\n", .{texture.mipsCount});
    const ddspf_dwFourCC: u32 = @as(*u32, @alignCast(@ptrCast(textureFileBuffer+0x54))).*;
    switch(ddspf_dwFourCC)
    {
        0x31545844 =>//DXT1
        {
            texture.format = VulkanInclude.VK_FORMAT_BC1_RGBA_SRGB_BLOCK;
        },
        0x35545844 =>//DXT5
        {
            texture.format = VulkanInclude.VK_FORMAT_BC3_SRGB_BLOCK;
        },
        else =>
        {
            print("unknown dds format!\n", .{});
            exit(0);
        }
    }
    texture.data = textureFileBuffer+128;
}
pub fn ddsLoadCubemapAsImages(arenaAllocator: std.mem.Allocator, path: [*]u8, textures: [*]Image.Image, texturesCount: usize) void
{
    const textureFile: std.fs.File = std.fs.cwd().openFileZ(@ptrCast(path), .{}) catch unreachable;
    defer textureFile.close();
    const stat = textureFile.stat() catch unreachable;
    const textureFileSize: usize = stat.size;
    const textureFileBuffer: [*]u8 = (arenaAllocator.alignedAlloc(u8, customMem.alingment, textureFileSize) catch unreachable).ptr;
    _ = textureFile.read(textureFileBuffer[0..textureFileSize]) catch unreachable;
    const pixelsData = textureFileBuffer+128;
    for(0..texturesCount) |i|
    {
        const texture = &textures[i];
        texture.format = VulkanInclude.VK_FORMAT_BC3_SRGB_BLOCK;
        texture.mipsCount = 6;
        texture.width = 512;
        texture.height = 512;
        texture.mipSize = 512*512;
        texture.size = 512*512+256*256+128*128+64*64+32*32+16*16;//349440
        texture.data = (arenaAllocator.alignedAlloc(u8, customMem.alingment, 349440) catch unreachable).ptr;
        var offset: usize = 2560*i;
        var srcMipLevelData = pixelsData;
        var bufferDstOffsetPtr = texture.data;
        var mipDimencion: usize = 512;
        
        for(0..6) |mipLevel|
        {
            _ = mipLevel;
            for(0..mipDimencion/4) |index|
            {
                customMem.memcpyAlign(bufferDstOffsetPtr, srcMipLevelData+offset+mipDimencion*8*4*index, mipDimencion*4);
                bufferDstOffsetPtr += (mipDimencion*4);
            }
            offset /= 2;
            srcMipLevelData += (mipDimencion*mipDimencion*8);
            mipDimencion /= 2;
        }
    }
}
