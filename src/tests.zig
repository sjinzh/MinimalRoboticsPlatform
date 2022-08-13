const KernelAllocator = @import("memory.zig").KernelAllocator;
const utils = @import("utils.zig");
const kprint = @import("serial.zig").kprint;
const logger = @import("logger.zig");

/// not an automated test. (yet)
pub fn testKMalloc(alloc: anytype) void {
    var p1 = alloc.alloc(u8, 875) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p1});
    var p2 = alloc.alloc(u8, 9) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p2});
    var p3 = alloc.alloc(u8, 43) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p3});
    var p4 = alloc.alloc(u8, 90) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p4});
    var p5 = alloc.alloc(u8, 156) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p5});
    var p6 = alloc.alloc(u8, 400) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p6});
    var p7 = alloc.alloc(u8, 875) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p7});

    alloc.free(u8, p1) catch |err| utils.printErrNoReturn(err);
    // alloc.free(u8, p2) catch |err| utils.printErrNoReturn(err);
    // alloc.free(u8, p3) catch |err| utils.printErrNoReturn(err);
    // alloc.free(u8, p4) catch |err| utils.printErrNoReturn(err);
    // alloc.free(u8, p5) catch |err| utils.printErrNoReturn(err);
    // alloc.free(u8, p6) catch |err| utils.printErrNoReturn(err);
    // alloc.free(u8, p7) catch |err| utils.printErrNoReturn(err);
    var p_realloced = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_realloced});
    var p_realloced1 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_realloced1});
    var p_realloced2 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_realloced2});
    var p_realloced3 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_realloced3});
    var p_realloced4 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_realloced4});

    var p_8 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_8});
    var p_9 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_9});
    var p_10 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_10});
    var p_11 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_11});
    var p_12 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_12});
    var p_13 = alloc.alloc(u8, 200) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p_13});

    alloc.free(u8, p2) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p3) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p4) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p5) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p6) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p7) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_realloced) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_realloced1) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_realloced2) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_realloced3) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_realloced4) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_8) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_9) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_10) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_11) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_12) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p_13) catch |err| utils.printErrNoReturn(err);
}
