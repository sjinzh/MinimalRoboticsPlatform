const std = @import("std");
const bl_utils = @import("utils.zig");
const utils = @import("utils");
const intHandle = @import("gicHandle.zig");
const arm = @import("arm");
const periph = @import("periph");
const board = @import("board");
const b_options = @import("build_options");
const proc = arm.processor.ProccessorRegMap(.ttbr0, .el1, false);
const mmu = arm.mmu;
// .ttbr0 arg sets the addresses value to either or user_, kernel_space
const PeriphConfig = board.PeriphConfig(.ttbr0);
const pl011 = periph.Pl011(.ttbr0);
const kprint = periph.uart.UartWriter(.ttbr0).kprint;

// raspberry
const bcm2835IntController = arm.bcm2835IntController.InterruptController(.ttbr0);

const gic = arm.gicv2.Gic(.ttbr0);

const Granule = board.boardConfig.Granule;
const GranuleParams = board.boardConfig.GranuleParams;
const TransLvl = board.boardConfig.TransLvl;

const kernel_bin_size = b_options.kernel_bin_size;
const bl_bin_size = b_options.bl_bin_size;

// todo => replace if(rom_size == null) with explicit if (no_rom)...

// note: when bl_main gets too bit(instruction mem wise), the exception vector table could be pushed too far up and potentially not be read!
export fn bl_main() callconv(.Naked) noreturn {
    // using userspace as stack, incase the bootloader is located in rom
    proc.setSp(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + board.config.mem.ram_layout.kernel_space_size + board.config.mem.bl_stack_size);
    // mmu configuration...
    {
        // todo => ttbr1 for kernel is ranging from 0x0-1g instead of _ramSize_ + _bl_load_addr-1g!. Alternatively link kernel with additional offset
        const ttbr0 align(4096) = blk: {
            // in case there is no rom(rom_size is equal to zero) and the kernel(and bl) are directly loaded to memory by some rom bootloader
            // the ttbr0 memory is also identity mapped to the ram
            comptime var mapping_bl_phys_size: usize = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_size;
            comptime var mapping_bl_phys_addr: usize = board.config.mem.rom_start_addr orelse 0;
            if (board.config.mem.rom_start_addr == null) {
                mapping_bl_phys_size = board.config.mem.ram_size;
                mapping_bl_phys_addr = board.config.mem.ram_start_addr;
            }

            // ttbr0 (rom) mapps both rom and ram
            comptime var ttbr0_size = (board.boardConfig.calcPageTableSizeTotal(board.boardConfig.Granule.FourkSection, mapping_bl_phys_size) catch |e| {
                kprint("[panic] Page table size calc error: {s}\n", .{@errorName(e)});
                bl_utils.panic();
            });

            var ttbr0_arr: [ttbr0_size]usize align(4096) = [_]usize{0} ** ttbr0_size;

            // MMU page dir config

            // writing to _id_mapped_dir(label) page table and creating new
            // identity mapped memory for bootloader to kernel transfer
            const bootloader_mapping = mmu.Mapping{
                .mem_size = mapping_bl_phys_size,
                .phys_addr = mapping_bl_phys_addr,
                .granule = Granule.FourkSection,
                .flags = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .block, .attrIndex = .mair0 },
            };
            // identity mapped memory for bootloader and kernel contrtol handover!
            var ttbr0_write = (mmu.PageTable(bootloader_mapping) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                bl_utils.panic();
            }).init(&ttbr0_arr) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                bl_utils.panic();
            };
            ttbr0_write.mapMem() catch |e| {
                kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                bl_utils.panic();
            };

            break :blk ttbr0_arr;
        };

        const ttbr1 align(4096) = blk: {
            // ttbr0 (rom) mapps both rom and ram
            comptime var ttbr1_size = (board.boardConfig.calcPageTableSizeTotal(board.boardConfig.Granule.FourkSection, board.config.mem.ram_size) catch |e| {
                kprint("[panic] Page table size calc error: {s}\n", .{@errorName(e)});
                bl_utils.panic();
            });

            var ttbr1_arr: [ttbr1_size]usize align(4096) = [_]usize{0} ** ttbr1_size;

            // creating virtual address space for kernel
            const kernel_mapping = mmu.Mapping{
                .mem_size = board.config.mem.ram_size,
                .phys_addr = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0),
                .granule = Granule.FourkSection,
                // todo => .descType should be .page but does not work with raspberry board..
                .flags = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .block, .attrIndex = .mair0 },
            };
            // mapping general kernel mem (inlcuding device base)
            var ttbr1_write = (mmu.PageTable(kernel_mapping) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                bl_utils.panic();
            }).init(&ttbr1_arr) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                bl_utils.panic();
            };
            ttbr1_write.mapMem() catch |e| {
                kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                bl_utils.panic();
            };
            // @compileLog(ttbr1_arr);
            break :blk ttbr1_arr;
        };
        kprint("{any} \n", .{ttbr0});
        kprint("0: {x} 1: {x} \n", .{ @ptrToInt(&ttbr0), @ptrToInt(&ttbr1) });
        brfn();
        // updating page dirs
        proc.setTTBR1(@ptrToInt(&ttbr1));
        proc.setTTBR0(@ptrToInt(&ttbr0));

        // t0sz: The size offset of the memory region addressed by TTBR0_EL1 (64-48=16)
        // t1sz: The size offset of the memory region addressed by TTBR1_EL1
        // tg0: Granule size for the TTBR0_EL1.
        // tg1 not required since it's sections
        proc.TcrReg.setTcrEl(.el1, (proc.TcrReg{ .t0sz = 16, .t1sz = 16, .tg0 = 0, .tg1 = 0 }).asInt());
        // attr0 is normal mem, not cachable
        proc.MairReg.setMairEl(.el1, (proc.MairReg{ .attr0 = 4, .attr1 = 0x0, .attr2 = 0x0, .attr3 = 0x0, .attr4 = 0x0 }).asInt());

        proc.invalidateMmuTlbEl1();
        proc.invalidateCache();
        proc.isb();
        proc.dsb();
        kprint("[bootloader] enabling mmu... \n", .{});
        proc.enableMmu(.el1);
    }
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

    if (board.config.mem.rom_start_addr != null) {
        kprint("[bootloader] setup mmu, el1, exc table. \n", .{});
        kprint("[bootloader] Copying kernel to addr_space: 0x{x}, with size: {d} \n", .{ @ptrToInt(kernel_target_loc.ptr), kernel_target_loc.len });
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

pub fn brfn() void {
    kprint("[kernel] gdb breakpoint function... \n", .{});
}
comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
