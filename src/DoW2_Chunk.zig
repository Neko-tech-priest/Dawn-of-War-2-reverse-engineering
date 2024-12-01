const std = @import("std");
const print = std.debug.print;

const Chunk = packed struct
{
    type: u32,
    id: u32,
    version: u32,
    size: u32,
    len: u32,
    unknown1: u32,
    unknown2: u32,
    string: [*]u8,
    data: [*]u8,
};
pub fn printChunkHierarchy(bufferPtrIterator: [*]u8, level: usize) void
{
    var chunk: Chunk = undefined;
    @as(*align(1) @Vector(4, u32), @ptrCast(@alignCast(&chunk.type))).* = @as(*align(1) @Vector(4, u32), @ptrCast(@alignCast(bufferPtrIterator))).* ;
    chunk.len = @bitCast(bufferPtrIterator[16..20].*);
    for(0..level) |indexLevel|
    {
        _ = indexLevel;
        print("    ", .{});
    }
    print("{s}", .{bufferPtrIterator[0..8]});
    if(chunk.type == @as(u32, @bitCast([4]u8{'F','O','L','D'})))
    {
        print("\n", .{});
        var currentPtr = bufferPtrIterator+28+chunk.len;
        while(@intFromPtr(currentPtr) < @intFromPtr(bufferPtrIterator+28+chunk.len+chunk.size))
        {
            printChunkHierarchy(currentPtr, level+1);
            currentPtr += 28+@as(u32, @bitCast(currentPtr[16..20].*)) + @as(u32, @bitCast(currentPtr[12..16].*));
        }
    }
    else
    {
        print(" {d}\n", .{chunk.size});
    }
}
pub fn childChunkCount(chunk: Chunk, id: [4]u8) usize
{
    var chunkCount: usize = 0;
    var ptr = chunk.data;
    while(@intFromPtr(ptr) < @intFromPtr(chunk.data)+chunk.size)
    {
        if(@as(u32, @bitCast(ptr[4..8].*)) == @as(u32, @bitCast(id)))
            chunkCount+=1;
        const data = @as([2]u32, @bitCast(ptr[12..20].*));//
        ptr += 28+data[0]+data[1];
    }
    return chunkCount;
}
pub fn childChunkCountPtr(bufferPtr: [*]u8, id: [4]u8) usize
{
    var chunkCount: usize = 0;
    var ptr = bufferPtr;
    while(@as(u32, @bitCast(ptr[4..8].*)) == @as(u32, @bitCast(id)))
    {
        chunkCount+=1;
        const data = @as([2]u32, @bitCast(ptr[12..20].*));//
        ptr += 28+data[0]+data[1];
    }
    return chunkCount;
}
pub fn chunkRead(bufferPtrIterator: *[*]u8) Chunk
{
    var chunk: Chunk = undefined;
    @as(*align(1) @Vector(4, u32), @ptrCast(@alignCast(&chunk.type))).* = @as(*align(1) @Vector(4, u32), @ptrCast(@alignCast(bufferPtrIterator.*))).* ;
    chunk.len = @bitCast(bufferPtrIterator.*[16..20].*);
    chunk.string = bufferPtrIterator.*+28;
    chunk.data = chunk.string+chunk.len;
    bufferPtrIterator.* = chunk.data+chunk.size;
    return chunk;
}
pub fn chunkReadHeader(bufferPtrIterator: *[*]u8) Chunk
{
    var chunk: Chunk = undefined;
    @as(*align(1) @Vector(4, u32), @ptrCast(@alignCast(&chunk.type))).* = @as(*align(1) @Vector(4, u32), @ptrCast(@alignCast(bufferPtrIterator.*))).* ;
    chunk.len = @bitCast(bufferPtrIterator.*[16..20].*);
    chunk.string = bufferPtrIterator.*+28;
    chunk.data = chunk.string+chunk.len;
    bufferPtrIterator.* = chunk.data;
    return chunk;
}
pub fn chunkSkip(bufferPtrIterator: *[*]u8) void
{
    bufferPtrIterator.* += 28 + @as(u32, @bitCast(bufferPtrIterator.*[16..20].*)) + @as(u32, @bitCast(bufferPtrIterator.*[12..16].*));
}
pub fn chunkSkipHeader(bufferPtrIterator: *[*]u8) void
{
    bufferPtrIterator.* += 28 + @as(u32, @bitCast(bufferPtrIterator.*[16..20].*));
}
