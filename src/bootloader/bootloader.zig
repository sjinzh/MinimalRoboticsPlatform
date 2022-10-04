const std = @import("std");
const bl_utils = @import("utils.zig");
const utils = @import("utils");
const intHandle = @import("gicHandle.zig");
const arm = @import("arm");
const periph = @import("periph");
const board = @import("board");
const b_options = @import("build_options");
const proc = arm.processor;
const mmu = arm.mmu;
const mmuComp = arm.mmuComptime;
// bool arg sets the addresses value to either mmu kernel_space or unsecure
const PeriphConfig = board.PeriphConfig(false);
const pl011 = periph.Pl011(false);
const kprint = periph.uart.UartWriter(false).kprint;

// raspberry
const bcm2835IntController = arm.bcm2835IntController.InterruptController(false);

const gic = arm.gicv2.Gic(false);

const Granule = board.boardConfig.Granule;
const GranuleParams = board.boardConfig.GranuleParams;
const TransLvl = board.boardConfig.TransLvl;

const kernel_bin_size = b_options.kernel_bin_size;
const bl_bin_size = b_options.bl_bin_size;

// todo => ttbr1 for kernel is ranging from 0x0-1g instead of _ramSize_ + _bl_load_addr-1g!. Alternatively link kernel with additional offset

// for bootloder.zig...
const ttbr0 align(4096) = blk: {
    @setEvalBranchQuota(1000000);

    // in case there is no rom(rom_size is equal to zero) and the kernel(and bl) are directly loaded to memory by some rom bootloader
    // the ttbr0 memory is also identity mapped to the ram
    comptime var mapping_bl_phys_size: usize = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_size;
    comptime var mapping_bl_phys_addr: usize = board.config.mem.rom_start_addr orelse 0;
    if (board.config.mem.rom_start_addr == null) {
        mapping_bl_phys_size = board.config.mem.ram_size;
        mapping_bl_phys_addr = board.config.mem.ram_start_addr;
    }

    // ttbr0 (rom) mapps both rom and ram
    const ttbr0_size = (board.boardConfig.calcPageTableSizeTotal(board.boardConfig.Granule.Section, mapping_bl_phys_size, 4096) catch |e| {
        @compileError(@errorName(e));
    });

    var ttbr0_arr: [ttbr0_size]usize align(4096) = [_]usize{0} ** ttbr0_size;

    // MMU page dir config

    // writing to _id_mapped_dir(label) page table and creating new
    // identity mapped memory for bootloader to kernel transfer
    const bootloader_mapping = mmuComp.Mapping{
        .mem_size = mapping_bl_phys_size,
        .virt_start_addr = 0,
        .phys_addr = mapping_bl_phys_addr,
        .granule = Granule.Section,
        .flags = mmuComp.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .block, .attrIndex = .mair0 },
    };
    // identity mapped memory for bootloader and kernel contrtol handover!
    var ttbr0_write = (mmuComp.PageTable(bootloader_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(&ttbr0_arr) catch |e| {
        @compileError(@errorName(e));
    };
    ttbr0_write.mapMem() catch |e| {
        @compileError(@errorName(e));
    };

    break :blk ttbr0_arr;
};

const ttbr1 align(4096) = blk: {
    @setEvalBranchQuota(1000000);

    // ttbr0 (rom) mapps both rom and ram
    const ttbr1_size = (board.boardConfig.calcPageTableSizeTotal(board.boardConfig.Granule.Section, board.config.mem.ram_size, 4096) catch |e| {
        @compileError(@errorName(e));
    });
    var ttbr1_arr: [ttbr1_size]usize align(4096) = [_]usize{0} ** ttbr1_size;

    // creating virtual address space for kernel
    const kernel_mapping = mmuComp.Mapping{
        .mem_size = board.config.mem.ram_size,
        .virt_start_addr = board.config.mem.va_start,
        .phys_addr = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0),
        .granule = Granule.Section,
        .flags = mmuComp.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .block, .attrIndex = .mair0 },
    };
    // mapping general kernel mem (inlcuding device base)
    var ttbr1_write = (mmuComp.PageTable(kernel_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(&ttbr1_arr) catch |e| {
        @compileError(@errorName(e));
    };
    ttbr1_write.mapMem() catch |e| {
        @compileError(@errorName(e));
    };
    break :blk ttbr1_arr;
};

// todo => replace if(rom_size == null) with explicit if (no_rom)...

// note: when bl_main gets too bit(instruction mem wise), the exception vector table could be pushed too far up and potentially not be read!
export fn bl_main() callconv(.Naked) noreturn {
    // using userspace as stack, incase the bootloader is located in rom
    proc.setSp(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + board.config.mem.ram_layout.kernel_space_size + board.config.mem.bl_stack_size);

    if (board.config.board == .raspi3b)
        bcm2835IntController.init();

    // GIC Init
    if (board.config.board == .qemuVirt) {
        gic.init() catch |e| {
            kprint("[panic] GIC init error: {s} \n", .{@errorName(e)});
            bl_utils.panic();
        };
        pl011.init();
    }

    // proc.exceptionSvc();

    // get address of external linker script variable which marks stack-top and kernel start
    const kernel_entry: usize = bl_bin_size;

    var kernel_bl: []u8 = undefined;
    kernel_bl.ptr = @intToPtr([*]u8, kernel_entry);
    kernel_bl.len = kernel_bin_size;

    var kernel_target_loc: []u8 = undefined;
    kernel_target_loc.ptr = @intToPtr([*]u8, mmu.toSecure(usize, board.config.mem.ram_start_addr));
    kernel_target_loc.len = kernel_bin_size;

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        bl_utils.panic();
    }

    // updating page dirs
    proc.setTTBR1(@ptrToInt(&ttbr1));
    proc.setTTBR0(@ptrToInt(&ttbr1));
    kprint("_ttbr0_dir: {d} \n", .{@ptrToInt(&ttbr0)});
    kprint("_ttbr1_dir: {d} \n", .{@ptrToInt(&ttbr1)});
    // t0sz: The size offset of the memory region addressed by TTBR0_EL1 (64-48=16)
    // t1sz: The size offset of the memory region addressed by TTBR1_EL1
    // tg0: Granule size for the TTBR0_EL1.
    // tg1 not required since it's sections
    proc.setTcrEl1((mmu.TcrReg{ .t0sz = 16, .t1sz = 16, .tg1 = 2 }).asInt());
    // attr0 is normal mem, not cachable
    proc.setMairEl1((mmu.MairReg{ .attr0 = 4, .attr1 = 0x0, .attr2 = 0x0, .attr3 = 0x0, .attr4 = 0x0 }).asInt());

    proc.invalidateMmuTlbEl1();
    proc.invalidateCache();
    proc.isb();
    proc.dsb();
    kprint("[bootloader] enabling mmu... \n", .{});
    proc.enableMmu();

    if (board.config.mem.rom_start_addr != null) {
        kprint("[bootloader] setup mmu, el1, exc table. \n", .{});
        kprint("[bootloader] Copying kernel to kernel_space: 0x{x}, with size: {d} \n", .{ @ptrToInt(kernel_target_loc.ptr), kernel_target_loc.len });
        std.mem.copy(u8, kernel_target_loc, kernel_bl);
        kprint("[bootloader] kernel copied \n", .{});
    }
    var kernel_addr = @ptrToInt(kernel_target_loc.ptr);
    if (board.config.mem.rom_start_addr == null)
        kernel_addr = mmu.toSecure(usize, board.config.mem.bl_load_addr.? + kernel_entry);

    kprint("[bootloader] jumping to kernel at 0x{x}\n", .{kernel_addr});

    proc.branchToAddr(kernel_addr);

    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
