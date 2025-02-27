const periph = @import("periph");
const pl011 = periph.Pl011(.ttbr1);

const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const kernelTimer = @import("kernelTimer.zig");
const utils = @import("utils");
const board = @import("board");
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const k_utils = @import("utils.zig");

const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;
const Topics = sharedKernelServices.Topics;

// global user required since the scheduler calls are invoked via svc
extern var scheduler: *Scheduler;
extern var topics: *Topics;

pub const Syscall = struct {
    id: u32,
    //x0..x7 = parameters and arguments
    //x8 = SysCall id
    fn_call: *const fn (params_args: *CpuContext) void,
};

pub const sysCallTable = [_]Syscall{
    .{ .id = 0, .fn_call = &sysCallPrint },
    .{ .id = 1, .fn_call = &killProcess },
    .{ .id = 2, .fn_call = &forkProcess },
    .{ .id = 3, .fn_call = &getPid },
    .{ .id = 4, .fn_call = &killProcessRecursively },
    // sys call id 5 is not used
    .{ .id = 6, .fn_call = &createThread },
    .{ .id = 7, .fn_call = &sleep },
    .{ .id = 8, .fn_call = &haltProcess },
    .{ .id = 9, .fn_call = &continueProcess },
    .{ .id = 10, .fn_call = &closeTopic },
    .{ .id = 11, .fn_call = &openTopic },
    .{ .id = 12, .fn_call = &pushToTopic },
    .{ .id = 13, .fn_call = &popFromTopic },
};

fn sysCallPrint(params_args: *CpuContext) void {
    // arguments for the function from the saved interrupt context
    const data = params_args.x0;
    const len = params_args.x1;
    var sliced_data: []u8 = undefined;
    sliced_data.len = len;
    sliced_data.ptr = @intToPtr([*]u8, data);
    pl011.write(sliced_data);
}

fn killProcess(params_args: *CpuContext) void {
    kprint("[kernel] killing task with pid: {d} \n", .{params_args.x0});
    scheduler.killProcess(params_args.x0, params_args) catch |e| {
        kprint("[panic] killProcess error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}

// kill a process and all its children processes
fn killProcessRecursively(params_args: *CpuContext) void {
    kprint("[kernel] killing task and children starting with pid: {d} \n", .{params_args.x0});
    scheduler.killProcessAndChildrend(params_args.x0, params_args) catch |e| {
        kprint("[panic] killProcessRecursively error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}

fn forkProcess(params_args: *CpuContext) void {
    kprint("[kernel] forking task with pid: {d} \n", .{params_args.x0});
    scheduler.deepForkProcess(params_args.x0) catch |e| {
        kprint("[panic] deepForkProcess error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}

fn getPid(params_args: *CpuContext) void {
    params_args.x0 = scheduler.getCurrentProcessPid();
}

fn createThread(params_args: *CpuContext) void {
    const entry_fn_ptr = @intToPtr(*anyopaque, params_args.x0);
    const thread_stack = params_args.x1;
    const args = @intToPtr(*anyopaque, params_args.x2);
    const thread_fn_ptr = @intToPtr(*anyopaque, params_args.x3);
    scheduler.createThreadFromCurrentProcess(entry_fn_ptr, thread_fn_ptr, thread_stack, args);
}

fn sleep(params_args: *CpuContext) void {
    const delay_in_sched_inter = params_args.x0;
    scheduler.setProcessAsleep(scheduler.getCurrentProcessPid(), delay_in_sched_inter, params_args) catch |e| {
        kprint("[panic] setProcessAsleep error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}

fn haltProcess(params_args: *CpuContext) void {
    const pid: usize = params_args.x0;
    scheduler.setProcessState(pid, .halted, params_args);
}

fn continueProcess(params_args: *CpuContext) void {
    const pid: usize = params_args.x0;
    scheduler.setProcessState(pid, .running, params_args);
}

fn closeTopic(params_args: *CpuContext) void {
    const index = params_args.x0;
    topics.closeTopic(index);
}

fn openTopic(params_args: *CpuContext) void {
    const index = params_args.x0;
    topics.openTopic(index);
}

fn pushToTopic(params_args: *CpuContext) void {
    const index = params_args.x0;
    const data_ptr = params_args.x1;
    const data_len = params_args.x2;
    topics.push(index, @intToPtr(*u8, data_ptr), data_len) catch return;
}

fn popFromTopic(params_args: *CpuContext) void {
    const index = params_args.x0;
    const data_len = params_args.x1;
    var data = topics.pop(index, data_len) catch {};
    if (data) |return_data| {
        params_args.x0 = @ptrToInt(return_data.ptr);
        params_args.x1 = return_data.len;
    }
}
