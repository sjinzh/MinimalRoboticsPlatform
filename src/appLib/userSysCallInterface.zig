const std = @import("std");
const alignForward = std.mem.alignForward;
const AppAllocator = @import("AppAllocator.zig").AppAllocator;
const utils = @import("utils");

pub const SysCallPrint = struct {
    const Self = @This();
    pub const Writer = std.io.Writer(*Self, error{}, appendWrite);

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }

    fn callKernelPrint(data: [*]const u8, len: usize) void {
        asm volatile (
        // args
            \\mov x0, %[data_addr]
            \\mov x1, %[len]
            // sys call id
            \\mov x8, #0
            \\svc #0
            :
            : [data_addr] "r" (@ptrToInt(data)),
              [len] "r" (len),
            : "x0", "x1", "x8"
        );
        // asm volatile ("brk 0xdead");
    }
    /// Same as `append` except it returns the number of bytes written, which is always the same
    /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
    fn appendWrite(self: *Self, data: []const u8) error{}!usize {
        _ = self;
        // asm volatile ("brk 0xdead");
        callKernelPrint(data.ptr, data.len);
        return data.len;
    }

    pub fn kprint(comptime print_string: []const u8, args: anytype) void {
        var tempW: SysCallPrint = undefined;
        std.fmt.format(tempW.writer(), print_string, args) catch |err| {
            @panic(err);
        };
    }
};

pub fn killProcess(pid: usize) noreturn {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #1
        \\svc #0
        :
        : [pid] "r" (pid),
        : "x0", "x8"
    );
    while (true) {}
}

pub fn forkProcess(pid: usize) void {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #2
        \\svc #0
        :
        : [pid] "r" (pid),
        : "x0", "x8"
    );
}

pub fn getPid() usize {
    return asm (
        \\mov x8, #3
        \\svc #0
        \\mov %[curr], x0
        : [curr] "=r" (-> usize),
        :
        : "x0", "x8"
    );
}

pub fn killProcessRecursively(starting_pid: usize) void {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #4
        \\svc #0
        :
        : [pid] "r" (starting_pid),
        : "x0", "x8"
    );
}

// todo => fix that scheduler gets stuck at higher delays
pub fn wait(delay_in_nano_secs: usize) void {
    asm volatile (
    // args
        \\mov x0, %[delay]
        // sys call id
        \\mov x8, #5
        \\svc #0
        :
        : [delay] "r" (delay_in_nano_secs),
        : "x0", "x8"
    );
}

// creates thread for current process
pub fn createThread(app_alloc: *AppAllocator, thread_fn: anytype, args: anytype) !void {
    // todo => make thread_stack_size configurable
    const thread_stack_mem = try app_alloc.alloc(u8, 0x10000, 16);
    var thread_stack_start: []u8 = undefined;
    thread_stack_start.ptr = @intToPtr([*]u8, @ptrToInt(thread_stack_mem.ptr) + thread_stack_mem.len);
    thread_stack_start.len = thread_stack_mem.len;

    var arg_mem: []const u8 = undefined;
    arg_mem.ptr = @ptrCast([*]const u8, @alignCast(1, &args));
    arg_mem.len = @sizeOf(@TypeOf(args));

    std.mem.copy(u8, thread_stack_start, arg_mem);

    asm volatile (
    // args
        \\mov x0, %[entry_fn_ptr]
        \\mov x1, %[thread_stack]
        \\mov x2, %[args_addr]
        \\mov x3, %[thread_fn_ptr]
        // sys call id
        \\mov x8, #6
        \\svc #0
        :
        : [entry_fn_ptr] "r" (@ptrToInt(&(ThreadInstance(thread_fn, @TypeOf(args)).threadEntry))),
          [thread_stack] "r" (@ptrToInt(thread_stack_start.ptr) - alignForward(@sizeOf(@TypeOf(args)), 16)),
          [args_addr] "r" (@ptrToInt(thread_stack_start.ptr)),
          [thread_fn_ptr] "r" (@ptrToInt(&thread_fn)),
        : "x0", "x1", "x2", "x3", "x8"
    );
}

// provides a generic entry function (generic in regard to the thread and argument function since @call builtin needs them to properly invoke the thread start)
fn ThreadInstance(comptime thread_fn: anytype, comptime Args: type) type {
    const ThreadFn = @TypeOf(thread_fn);
    return struct {
        fn threadEntry(entry_fn: *ThreadFn, entry_args: *Args) callconv(.C) void {
            @call(.{ .modifier = .auto }, entry_fn, entry_args.*);
        }
    };
}

pub fn sleep(delay_in_nano_secs: usize) void {
    asm volatile (
    // args
        \\mov x0, %[delay]
        // sys call id
        \\mov x8, #7
        \\svc #0
        :
        : [delay] "r" (delay_in_nano_secs),
        : "x0", "x8"
    );
}
